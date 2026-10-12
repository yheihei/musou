#!/usr/bin/env python3
"""fal の Meshy と画像生成を呼んで、キャラクターの三面図・3D モデル・リグとモーションを作る。

標準ライブラリだけで動く。キーは環境変数 FAL_KEY から読む（値は表示しない）。
手元の画像は base64 の data URI にして渡すので、アップロードは要らない。

  python3 fal_meshy.py views --source src.png --out DIR [--side]
  python3 fal_meshy.py model --front f.png --side s.png --back b.png --out DIR [--polycount 3000] [--pose t-pose]
  python3 fal_meshy.py rig --out DIR [--model-url URL] [--height 1.7] --anims 0,4,92

各コマンドは DIR に <段階>.json（fal の応答）と、応答に含まれるファイルを保存する。
"""

from __future__ import annotations

import argparse
import base64
import json
import mimetypes
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

QUEUE = "https://queue.fal.run"
MODEL_ENDPOINT = "meshy/v7.1/multi-image-to-3d"
RIG_ENDPOINT = "fal-ai/meshy/rigging/multi-animation"
VIEWS_ENDPOINT = "google/nano-banana-2.1/edit"

PROMPT_DIR = Path(__file__).resolve().parent.parent / "references"


def die(message: str) -> None:
    print(f"error: {message}", file=sys.stderr)
    sys.exit(1)


def key() -> str:
    value = os.environ.get("FAL_KEY")
    if not value:
        die("FAL_KEY がありません。~/.zshrc を読まないシェルなら zsh -ic '...' の中で実行してください")
    return value


def request(method: str, url: str, body: dict | None = None) -> dict:
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Key {key()}")
    if data is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=120) as res:
            return json.loads(res.read())
    except urllib.error.HTTPError as e:
        die(f"{method} {url} -> HTTP {e.code}: {e.read().decode(errors='replace')[:2000]}")
    raise AssertionError


def run(endpoint: str, payload: dict, timeout: int = 1200) -> dict:
    submitted = request("POST", f"{QUEUE}/{endpoint}", payload)
    print(f"{endpoint}: request_id={submitted['request_id']}", file=sys.stderr)
    started = time.time()
    while True:
        status = request("GET", submitted["status_url"])
        state = status.get("status")
        if state == "COMPLETED":
            break
        if state not in ("IN_QUEUE", "IN_PROGRESS"):
            die(f"{endpoint}: {json.dumps(status, ensure_ascii=False)[:2000]}")
        if time.time() - started > timeout:
            die(f"{endpoint}: {timeout} 秒たっても終わりません（request_id={submitted['request_id']}）")
        time.sleep(10)
    print(f"{endpoint}: {int(time.time() - started)} 秒で完了", file=sys.stderr)
    return request("GET", submitted["response_url"])


def data_uri(path: str) -> str:
    p = Path(path)
    if not p.is_file():
        die(f"{path} がありません")
    mime = mimetypes.guess_type(p.name)[0] or "image/png"
    return f"data:{mime};base64,{base64.b64encode(p.read_bytes()).decode()}"


def files_in(node, path: str = ""):
    """応答の中の {"url": ...} をすべて (名前, url) で返す。"""
    if isinstance(node, dict):
        if isinstance(node.get("url"), str) and node["url"].startswith("http"):
            yield path or "file", node["url"], node.get("file_name")
        for k, v in node.items():
            if k != "url":
                yield from files_in(v, f"{path}.{k}" if path else k)
    elif isinstance(node, list):
        for i, v in enumerate(node):
            yield from files_in(v, f"{path}.{i}")


def save(result: dict, out: Path, stage: str) -> None:
    out.mkdir(parents=True, exist_ok=True)
    (out / f"{stage}.json").write_text(json.dumps(result, ensure_ascii=False, indent=2))
    for name, url, file_name in files_in(result):
        suffix = Path(file_name or url.split("?")[0]).suffix
        target = out / f"{stage}.{name}{suffix}"
        urllib.request.urlretrieve(url, target)
        print(f"saved {target} ({target.stat().st_size} bytes)")


def views(args) -> None:
    out = Path(args.out)
    front_prompt = (PROMPT_DIR / "view_front.txt").read_text()
    back_prompt = (PROMPT_DIR / "view_back.txt").read_text()
    side_prompt = (PROMPT_DIR / "view_side.txt").read_text()
    common = {"num_images": 1, "output_format": "png", "aspect_ratio": "1:1", "resolution": "2K"}

    front = run(VIEWS_ENDPOINT, {**common, "prompt": front_prompt, "image_urls": [data_uri(args.source)]})
    save(front, out, "view_front")
    front_url = front["images"][0]["url"]
    back = run(VIEWS_ENDPOINT, {**common, "prompt": back_prompt, "image_urls": [front_url, data_uri(args.source)]})
    save(back, out, "view_back")
    if args.side:
        side = run(VIEWS_ENDPOINT, {**common, "prompt": side_prompt, "image_urls": [front_url, data_uri(args.source)]})
        save(side, out, "view_side")


def model(args) -> None:
    images = [args.front] + ([args.side] if args.side else []) + [args.back]
    payload = {
        "image_urls": [data_uri(p) for p in images],
        "topology": "triangle",
        "target_polycount": args.polycount,
        "symmetry_mode": "auto",
        "should_remesh": True,
        "should_texture": True,
        "enable_pbr": False,
        "pose_mode": args.pose,
        "enable_rigging": False,
    }
    if args.texture_prompt:
        payload["texture_prompt"] = args.texture_prompt
    save(run(MODEL_ENDPOINT, payload), Path(args.out), "model")


def rig(args) -> None:
    out = Path(args.out)
    model_url = args.model_url
    if not model_url:
        response = out / "model.json"
        if not response.is_file():
            die(f"{response} がありません。--model-url を渡すか、先に model を実行してください")
        model_url = json.loads(response.read_text())["model_glb"]["url"]
    anims = [int(a) for a in args.anims.split(",") if a.strip()]
    if not 1 <= len(set(anims)) <= 10:
        die("--anims は1〜10個の Meshy のモーション ID（0〜696）")
    payload = {"model_url": model_url, "height_meters": args.height, "animation_action_ids": anims}
    save(run(RIG_ENDPOINT, payload), out, "rig")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("views", help="元の絵から正面・背面（と側面）の図を fal の画像生成で作る")
    p.add_argument("--source", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--side", action="store_true", help="側面図も作る")
    p.set_defaults(func=views)

    p = sub.add_parser("model", help="三面図から Meshy 7.1 でテクスチャ付きのモデルを作る")
    p.add_argument("--front", required=True)
    p.add_argument("--side")
    p.add_argument("--back", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--polycount", type=int, default=3000)
    p.add_argument("--pose", default="t-pose", choices=["t-pose", "a-pose", ""])
    p.add_argument("--texture-prompt")
    p.set_defaults(func=model)

    p = sub.add_parser("rig", help="モデルにリグを入れ、ライブラリのモーションを付ける")
    p.add_argument("--out", required=True)
    p.add_argument("--model-url")
    p.add_argument("--height", type=float, default=1.7)
    p.add_argument("--anims", required=True, help="カンマ区切りの Meshy のモーション ID（最大10個）")
    p.set_defaults(func=rig)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
