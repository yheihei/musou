#!/usr/bin/env python3
"""紺の装束のリグ入りモデルから、装束の色だけをクランの色に塗り替えた FBX と GLB を作る（下忍のクランの色違い）。

形・リグ・テクスチャの貼り方は元のまま、埋め込みのテクスチャ（JPEG）だけを差し替える。
クランの色は src/shared/Colors.luau の Colors.Clan から読む。塗り替えは ImageMagick（magick）で行う。

  python3 clan_colors.py --base DIR --root DIR [--name genin] [--clans iga,koga,fuma,saika]

  --base  fal_meshy.py rig の出力がある作業用の場所（rig.rigged_character_fbx.fbx と rig.rigged_character_glb.glb）
  --root  出力の親。<root>/<name>_<clan>/ に <name>_<clan>.fbx・<name>_<clan>.glb・texture.jpg を置く

装束の画素は、色相が青（200〜265 度）で彩度があり、黒い線でも灰色の帯・腕の布でもないもの。
各画素の明るさを装束の平均の明るさで割った比で、クランの色の明るさを変える（陰影を残す）。
境目は重み（0〜1）でなめらかにつなぐ。
差し替えた画像は元の画像と同じ長さにする（足りない分は JPEG のコメント区画で埋める）。
FBX の節の位置と GLB の bufferView を書き換えずに済み、どちらも元のファイルと同じ大きさになる。
"""

from __future__ import annotations

import argparse
import json
import os
import re
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[4]
COLORS = REPO / "src" / "shared" / "Colors.luau"

# 装束らしさの重み（ImageMagick の -fx の式）。hue は 0〜1 で1周。紺の帯は 0.555〜0.736（200〜265 度）
WEIGHT = (
    "vhue=u.hue; vsat=u.saturation; vlig=u.lightness;"
    "whue=min(max((vhue-0.540)/0.03,0),1)*min(max((0.750-vhue)/0.03,0),1);"
    "wsat=min(max((vsat-0.07)/0.06,0),1);"
    "wlig=min(max((vlig-0.07)/0.05,0),1)*min(max((0.70-vlig)/0.08,0),1);"
    "wall=whue*wsat*wlig;"
)

JPEG = b"\xff\xd8\xff"


def die(message: str) -> None:
    print(f"error: {message}", file=sys.stderr)
    sys.exit(1)


def magick(*args: str) -> str:
    result = subprocess.run(["magick", *args], capture_output=True, text=True)
    if result.returncode != 0:
        die(result.stderr.strip())
    return result.stdout


def clan_colors() -> dict[str, tuple[int, int, int]]:
    """Colors.luau の Colors.Clan を {"iga": (r, g, b)} で返す。"""
    text = COLORS.read_text()
    block = re.search(r"Colors\.Clan = \{(.*?)\}", text, re.S)
    if not block:
        die(f"{COLORS} に Colors.Clan が無い")
    colors = {}
    for name, r, g, b in re.findall(r"(\w+) = Color3\.fromRGB\((\d+), (\d+), (\d+)\)", block.group(1)):
        colors[name.lower()] = (int(r), int(g), int(b))
    return colors


def lum(r: str, g: str, b: str) -> str:
    return f"(0.2126*{r}+0.7152*{g}+0.0722*{b})"


def costume_mean(image: str) -> tuple[float, float, float]:
    """装束の重み付きの平均の色（0〜1）。"""
    rgb = magick(image, "-alpha", "off", "-fx", WEIGHT + "channel(wall*u.r, wall*u.g, wall*u.b)",
                 "-format", "%[fx:mean.r] %[fx:mean.g] %[fx:mean.b]", "info:")
    weight = float(magick(image, "-alpha", "off", "-fx", WEIGHT + "wall", "-format", "%[fx:mean]", "info:"))
    if weight <= 0:
        die(f"{image} に紺の装束の画素が無い")
    r, g, b = (float(x) / weight for x in rgb.split())
    return r, g, b


def paint(image: str, mean: tuple[float, float, float], rgb: tuple[int, int, int], out: str) -> None:
    tr, tg, tb = (c / 255 for c in rgb)
    ratio = f"({lum('u.r', 'u.g', 'u.b')}/{lum(*(str(c) for c in mean))})"
    expr = (
        WEIGHT
        + f"kf={ratio};"
        + f"channel(u.r*(1-wall)+min({tr}*kf,1)*wall, u.g*(1-wall)+min({tg}*kf,1)*wall,"
        + f" u.b*(1-wall)+min({tb}*kf,1)*wall)"
    )
    magick(image, "-alpha", "off", "-fx", expr, out)


def jpeg_within(png: str, out: str, limit: int) -> int:
    """limit バイトに収まる一番高い品質で JPEG にする。品質を返す。"""
    best = None
    lo, hi = 70, 100
    while lo <= hi:
        quality = (lo + hi) // 2
        magick(png, "-sampling-factor", "2x2", "-quality", str(quality), out)
        if os.path.getsize(out) <= limit:
            best, lo = quality, quality + 1
        else:
            hi = quality - 1
    if best is None:
        die("品質 70 でも元の画像の大きさに収まらない")
    magick(png, "-sampling-factor", "2x2", "-quality", str(best), out)
    return best


def pad_jpeg(data: bytes, length: int) -> bytes:
    """SOI の直後にコメント区画（FF FE）を足して length バイトにする（画像の中身は変えない）。"""
    pad = length - len(data)
    if pad < 0:
        die(f"新しい画像（{len(data)} bytes）が元（{length} bytes）より大きい")
    if 0 < pad < 4:
        die("埋める長さが 1〜3 バイトで、コメント区画を作れない")
    segments = []
    while pad > 0:
        size = min(pad, 65537)  # 区画1つは 4〜65537 バイト（印 2 + 長さ 2〜65535）
        if 0 < pad - size < 4:
            size = pad - 4
        segments.append(b"\xff\xfe" + struct.pack(">H", size - 2) + b" " * (size - 4))
        pad -= size
    out = data[:2] + b"".join(segments) + data[2:]
    assert len(out) == length
    return out


def fbx_images(data: bytes) -> list[tuple[int, int]]:
    """binary FBX（7.x）の Video/Content の値の (開始, 長さ)。"""
    version = struct.unpack_from("<I", data, 23)[0]
    wide = version >= 7500
    spans = []

    def read(pos: int, path: str) -> int | None:
        if wide:
            end, count, _ = struct.unpack_from("<QQQ", data, pos)
            pos += 24
        else:
            end, count, _ = struct.unpack_from("<III", data, pos)
            pos += 12
        name_length = data[pos]
        pos += 1
        if end == 0:
            return None
        here = path + "/" + data[pos : pos + name_length].decode("latin1")
        pos += name_length
        for _ in range(count):
            kind = chr(data[pos])
            pos += 1
            if kind in "YCILFD":
                pos += {"Y": 2, "C": 1, "I": 4, "L": 8, "F": 4, "D": 8}[kind]
            elif kind in "fdlibc":
                pos += 12 + struct.unpack_from("<III", data, pos)[2]
            elif kind in "SR":
                length = struct.unpack_from("<I", data, pos)[0]
                pos += 4
                if kind == "R" and here.endswith("/Video/Content"):
                    spans.append((pos, length))
                pos += length
            else:
                die(f"FBX の値の型 {kind!r} を読めない")
        while pos < end:
            following = read(pos, here)
            if following is None:
                break
            pos = following
        return end

    pos = 27
    while True:
        following = read(pos, "")
        if following is None:
            break
        pos = following
    return spans


def glb_images(data: bytes) -> list[tuple[int, int]]:
    """GLB の画像の (開始, 長さ)。"""
    magic, version, _ = struct.unpack_from("<4sII", data, 0)
    if magic != b"glTF" or version != 2:
        die("GLB ではない")
    json_length = struct.unpack_from("<I", data, 12)[0]
    doc = json.loads(data[20 : 20 + json_length])
    bin_start = 20 + json_length + 8
    spans = []
    for image in doc.get("images", []):
        view = doc["bufferViews"][image["bufferView"]]
        spans.append((bin_start + view.get("byteOffset", 0), view["byteLength"]))
    return spans


def swap(source: Path, spans_of, image: bytes, target: Path) -> None:
    data = bytearray(source.read_bytes())
    spans = spans_of(bytes(data))
    if not spans:
        die(f"{source} に埋め込みの画像が無い")
    for start, length in spans:
        if not bytes(data[start : start + 3]) == JPEG:
            die(f"{source} の埋め込みの画像が JPEG でない")
        data[start : start + length] = pad_jpeg(image, length)
    target.write_bytes(data)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--base", required=True)
    parser.add_argument("--root", required=True)
    parser.add_argument("--name", default="genin")
    parser.add_argument("--clans", default="iga,koga,fuma,saika")
    args = parser.parse_args()

    base = Path(args.base).expanduser()
    root = Path(args.root).expanduser()
    fbx = base / "rig.rigged_character_fbx.fbx"
    glb = base / "rig.rigged_character_glb.glb"
    colors = clan_colors()

    glb_data = glb.read_bytes()
    (start, length), *_ = glb_images(glb_data)
    with tempfile.TemporaryDirectory() as tmp:
        original = Path(tmp) / "original.jpg"
        original.write_bytes(glb_data[start : start + length])
        mean = costume_mean(str(original))
        print(f"装束の平均の色 {tuple(round(c * 255, 1) for c in mean)}、画像 {length} bytes")
        for clan in args.clans.split(","):
            if clan not in colors:
                die(f"Colors.Clan に {clan} が無い（{', '.join(colors)}）")
            out = root / f"{args.name}_{clan}"
            out.mkdir(parents=True, exist_ok=True)
            png = Path(tmp) / f"{clan}.png"
            paint(str(original), mean, colors[clan], str(png))
            texture = out / "texture.jpg"
            quality = jpeg_within(str(png), str(texture), length)
            image = texture.read_bytes()
            swap(fbx, fbx_images, image, out / f"{args.name}_{clan}.fbx")
            swap(glb, glb_images, image, out / f"{args.name}_{clan}.glb")
            print(f"{clan} {colors[clan]}: 品質 {quality}、{len(image)} bytes → {out}/{args.name}_{clan}.fbx・.glb")


if __name__ == "__main__":
    main()
