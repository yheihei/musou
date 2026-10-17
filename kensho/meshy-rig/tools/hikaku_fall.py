"""ジャンプ攻撃のクリップを、ゲームの落下（Push.fall）と合わせて流したときの足と腰を、腰の移動の抜き方ごとに比べる（#68・#67）。

使い方（リポジトリの直下で）:

    lune run kensho/meshy-rig/tools/techniques > ~/musou-work/techniques.json
    python3 -I kensho/meshy-rig/tools/hikaku_fall.py ~/musou-work/characters/jin ~/musou-work/techniques.json

- ゲームのジャンプ攻撃は、行動の始めから Startup の間、根元の部品を落ちる速さ（techniques.json の fall。Config.luau の
  Jump 節の DiveSpeed）で真下へ落とし、地面に着いたら残りの間は地面に立つ（CombatService・Push.fall）。
  2026-10-17 の Studio では、頂点（7.3）で入れると 0.09 秒で着地し、着地で根元の部品が 0.6 だけ沈んで 0.15 秒で戻った
- 落ち始めの高さ（根元の部品の、立っているときの高さからの高さ）は、頂点（Jump 節の Height）・その半分・低いところの3通り
- クリップは hikaku_player.py と同じく、区間を行動の長さに合わせて等速で流し、刃の GLB の順運動学で骨の位置を求める
- 足の地面からの高さ = 根元の部品の高さ + クリップの足の骨の高さ（休息の姿勢からの差）。負なら地面に沈み、正なら浮く。
  値は R15 の脚の長さとの比を掛けたスタッド（hikaku_player.py と同じ）。根元の部品の高さは比を掛けない（ゲームのスタッド）
- 着地の沈み（Humanoid の着地の動き）は入れていない
"""

import importlib.util
import json
import os
import sys


def load_player():
    here = os.path.dirname(os.path.abspath(__file__))
    spec = importlib.util.spec_from_file_location("hikaku_player", os.path.join(here, "hikaku_player.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


P = load_player()
G = P.G

STEP = 1 / 60
# ジャンプの高さ（Config.luau の Jump 節の Height）。落ち始めの高さは、これと半分と低いところ
JUMP_HEIGHT = 7.2
STARTS = (("頂点", JUMP_HEIGHT), ("半分", JUMP_HEIGHT / 2), ("低い", 1.0))
MODES = ("xz", "all")


def rest_feet_of(rest):
    return min(rest[f][0][1] for f in P.FEET if f in rest)


def series(rows, rest, tracks, tech, mode, unit, start):
    """行動の始めからの時刻ごとの、根元の部品の高さ・腰の上下・足の地面からの高さ"""
    rest_hips = rest["Hips"][0]
    rest_feet = rest_feet_of(rest)
    span = tech["to"] - tech["from"]
    out = []
    steps = int(round(tech["duration"] / STEP))
    for i in range(steps + 1):
        t = min(i * STEP, tech["duration"])
        root = max(0.0, start - tech["fall"] * min(t, tech["startup"]))
        clip_t = tech["from"] + span * t / tech["duration"]
        world = P.pose_at(rows, tracks, clip_t, mode)
        up = (world["Hips"][0][1] - rest_hips[1]) * unit
        feet = (min(world[f][0][1] for f in P.FEET if f in world) - rest_feet) * unit
        out.append({"t": t, "clip": clip_t, "root": root, "up": up, "feet": feet, "ground": root + feet})
    return out


def summarize(samples, tech):
    landed = next((s for s in samples if s["root"] <= 1e-9), samples[-1])
    air = [s for s in samples if s["t"] < landed["t"]]
    ground = [s for s in samples if s["t"] >= landed["t"]]
    hit_from, hit_to = tech["startup"], tech["startup"] + tech["active"]
    hit = [s for s in samples if hit_from - 1e-6 <= s["t"] <= hit_to + 1e-6]
    hit_air = sum(1 for s in hit if s["root"] > 1e-9)
    return {
        "land_t": landed["t"],
        "land_clip": landed["clip"],
        "land_feet": landed["ground"],
        "air_low": min((s["ground"] for s in air), default=None),
        "ground_feet_min": min(s["ground"] for s in ground),
        "ground_feet_max": max(s["ground"] for s in ground),
        "ground_up_min": min(s["up"] for s in ground),
        "ground_up_max": max(s["up"] for s in ground),
        "hit": "空中" if hit_air == len(hit) else ("地上" if hit_air == 0 else "空中→地上"),
        "hit_feet_min": min(s["ground"] for s in hit),
        "hit_feet_max": max(s["ground"] for s in hit),
        "end_up": samples[-1]["up"],
        "end_feet": samples[-1]["ground"],
    }


def fmt(value):
    return "なし" if value is None else f"{value:.2f}"


def main():
    base = os.path.expanduser(sys.argv[1] if len(sys.argv) > 1 else "~/musou-work/characters/jin")
    with open(os.path.expanduser(sys.argv[2] if len(sys.argv) > 2 else "~/musou-work/techniques.json"), encoding="utf-8") as f:
        techniques = json.load(f)
    rjs, _ = G.load_glb(os.path.join(base, "rig.rigged_character_glb.glb"))
    rows, top = G.skeleton(rjs)
    scale = P.HEIGHT_STUDS / top
    rest = P.pose_at(rows, {}, 0.0, "keep")
    jin_leg = (rest["Hips"][0][1] - rest_feet_of(rest)) * scale
    unit = scale * P.R15_LEG / jin_leg
    print(f"R15 の脚の長さとの比 {P.R15_LEG / jin_leg:.2f}。落ちる速さと判定の間は techniques.json（Config.luau）")
    print()
    print("| 技 | 落ち始め | 抜き方 | 着地（行動の始めから、クリップ） | 空中の足の最低 | 着地の足 | 着地後の足 最低〜最高 | 着地後の腰 上下 | 判定の間 | 判定の間の足 | 終わりの腰 |")
    print("|---|---|---|---|---|---|---|---|---|---|---|")
    for tech in techniques:
        if tech.get("fall", 0) <= 0:
            continue
        tracks = P.read_clip(os.path.join(base, "motions", f"id{tech['clip']:03d}.glb"))
        for label, start in STARTS:
            for mode in MODES:
                s = summarize(series(rows, rest, tracks, tech, mode, unit, start), tech)
                mark = "（指定）" if mode == tech["strip"] else ""
                print(
                    f"| {P.title(tech)} | {label} {start:.1f} | {P.LABELS[mode]}{mark} "
                    f"| {s['land_t']:.2f} 秒（{s['land_clip']:.2f}） "
                    f"| {fmt(s['air_low'])} | {s['land_feet']:.2f} "
                    f"| {s['ground_feet_min']:.2f}〜{s['ground_feet_max']:.2f} "
                    f"| {s['ground_up_min']:.2f}〜{s['ground_up_max']:.2f} "
                    f"| {s['hit']} | {s['hit_feet_min']:.2f}〜{s['hit_feet_max']:.2f} "
                    f"| {s['end_up']:.2f} |"
                )


if __name__ == "__main__":
    main()
