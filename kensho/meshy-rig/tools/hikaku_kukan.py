"""終わりに腰が下がったままの技の区間を、立ち上がるところまで延ばす候補と、今の区間を比べる（#67・#68・#120）。

使い方（リポジトリの直下で）:

    lune run kensho/meshy-rig/tools/techniques > ~/musou-work/techniques.json
    python3 -I kensho/meshy-rig/tools/hikaku_kukan.py ~/musou-work/characters/jin ~/musou-work/techniques.json

- 対象は PM判断（2026-10-17）の5つの技（手裏剣 C4・刀 C4・毒手裏剣・刀 6段目・刀 C3）。技の名前を引数の後ろに並べると差し替える
- 行動の長さ・判定の出る間・前進は変えない（PM判断）。候補は区間の終わりだけを延ばし、同じ行動の長さで速く流す（等速換算）
- 候補の区間の終わりは、今の区間の終わりより後で、腰の上下（休息の姿勢からの差）が THRESHOLD より上に戻る最初の時刻。
  戻らなければクリップの終わり
- 命中の姿: 区間の中で、手と足の骨のうちいちばん速く動く時刻（クリップの時刻。打つ・投げる・蹴る瞬間とみなす）。
  判定の出る間（Startup〜Startup+Active）に流れるクリップの時刻と比べ、命中の姿が判定の間に入るかと、ずれ（秒、ゲームの時間）を出す
- 腰は抜き方 xz（縦は残す）の値。単位は hikaku_player.py と同じ（R15 の脚の長さとの比を掛けたスタッド）
"""

import importlib.util
import json
import math
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
# 立ち上がったとみなす腰の上下（休息の姿勢からの差、スタッド）
THRESHOLD = -0.5
TARGETS = ("手裏剣 C4", "刀 C4", "奥義 PoisonShuriken", "刀 6段目", "刀 C3")
NAMES = {"奥義 PoisonShuriken": "毒手裏剣"}
EFFECTORS = ("LeftHand", "RightHand", "LeftFoot", "RightFoot")


def up_at(rows, rest, tracks, clip_t, unit):
    world = P.pose_at(rows, tracks, clip_t, "xz")
    return (world["Hips"][0][1] - rest["Hips"][0][1]) * unit


def feet_at(rows, rest, tracks, clip_t, unit):
    world = P.pose_at(rows, tracks, clip_t, "xz")
    rest_feet = min(rest[f][0][1] for f in P.FEET if f in rest)
    return (min(world[f][0][1] for f in P.FEET if f in world) - rest_feet) * unit


def clip_length(tracks):
    return max(max(times) for tr in tracks.values() for (times, _vals) in tr.values())


def stand_up_time(rows, rest, tracks, tech, unit, length):
    t = tech["to"]
    while t <= length + 1e-9:
        if up_at(rows, rest, tracks, t, unit) >= THRESHOLD:
            return t, True
        t += STEP
    return length, False


def strike_time(rows, tracks, start, stop, unit):
    """区間の中で、手と足の骨のうちいちばん速く動く時刻と、その速さ（スタッド/秒、クリップの時間）"""
    best_t, best_v = start, -1.0
    prev = None
    t = start
    while t <= stop + 1e-9:
        world = P.pose_at(rows, tracks, t, "xz")
        hips = world["Hips"][0]
        # 腰からの位置で測る（体ごとの移動を除く）
        now = {e: tuple(world[e][0][k] - hips[k] for k in range(3)) for e in EFFECTORS if e in world}
        if prev:
            for e, p in now.items():
                q = prev[e]
                v = math.sqrt(sum((p[k] - q[k]) ** 2 for k in range(3))) * unit / STEP
                if v > best_v:
                    best_t, best_v = t - STEP / 2, v
        prev = now
        t += STEP
    return best_t, best_v


def hit_clip_range(tech, to):
    span = to - tech["from"]
    a = tech["from"] + span * tech["startup"] / tech["duration"]
    b = tech["from"] + span * (tech["startup"] + tech["active"]) / tech["duration"]
    return a, b


def game_time_of(tech, to, clip_t):
    return (clip_t - tech["from"]) / (to - tech["from"]) * tech["duration"]


def main():
    base = os.path.expanduser(sys.argv[1] if len(sys.argv) > 1 else "~/musou-work/characters/jin")
    with open(os.path.expanduser(sys.argv[2] if len(sys.argv) > 2 else "~/musou-work/techniques.json"), encoding="utf-8") as f:
        techniques = {t["name"]: t for t in json.load(f)}
    targets = tuple(sys.argv[3:]) or TARGETS
    rjs, _ = G.load_glb(os.path.join(base, "rig.rigged_character_glb.glb"))
    rows, top = G.skeleton(rjs)
    scale = P.HEIGHT_STUDS / top
    rest = P.pose_at(rows, {}, 0.0, "keep")
    jin_leg = (rest["Hips"][0][1] - min(rest[f][0][1] for f in P.FEET)) * scale
    unit = scale * P.R15_LEG / jin_leg
    print(f"立ち上がったとみなす腰の上下 {THRESHOLD}。行動の長さ・判定の出る間は今のまま（techniques.json）")
    print()
    print("| 技 | 区間 | 速さ（今の何倍） | 終わりの腰 | 区間の中の足の最低 | 判定の間に流れるクリップ | 命中の姿（クリップ） | 命中の姿は判定の間に | ずれ（ゲームの秒） |")
    print("|---|---|---|---|---|---|---|---|---|")
    for name in targets:
        tech = techniques.get(name)
        if not tech:
            print(f"| {name} | 一覧に無い | | | | | | | |")
            continue
        tracks = P.read_clip(os.path.join(base, "motions", f"id{tech['clip']:03d}.glb"))
        length = clip_length(tracks)
        to2, stood = stand_up_time(rows, rest, tracks, tech, unit, length)
        label = NAMES.get(name, name)
        strike_t, strike_v = strike_time(rows, tracks, tech["from"], tech["to"], unit)
        for kind, to in (("今", tech["to"]), ("候補", to2)):
            a, b = hit_clip_range(tech, to)
            inside = a - 1e-6 <= strike_t <= b + 1e-6
            strike_game = game_time_of(tech, to, strike_t)
            hit_from, hit_to = tech["startup"], tech["startup"] + tech["active"]
            if inside:
                shift = 0.0
            elif strike_game < hit_from:
                shift = strike_game - hit_from
            else:
                shift = strike_game - hit_to
            feet_min = min(feet_at(rows, rest, tracks, tech["from"] + i * STEP, unit) for i in range(int((to - tech["from"]) / STEP) + 1))
            ratio = (to - tech["from"]) / (tech["to"] - tech["from"])
            note = "" if kind == "今" else ("" if stood else "（立ち上がらない。クリップの終わり）")
            print(
                f"| {label}（id{tech['clip']}、{tech['duration']:.2f} 秒） | {kind} {tech['from']:g}〜{to:.2f}{note} "
                f"| {ratio:.2f} | {up_at(rows, rest, tracks, to, unit):.2f} | {feet_min:.2f} "
                f"| {a:.2f}〜{b:.2f} | {strike_t:.2f}（{strike_v:.0f}/秒） | {'入る' if inside else '入らない'} "
                f"| {shift:+.2f} |"
            )


if __name__ == "__main__":
    main()
