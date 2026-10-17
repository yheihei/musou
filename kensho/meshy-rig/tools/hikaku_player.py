"""操作キャラクターの技のクリップを、ゲームの行動の長さで流したときの腰と足と胴を、腰の移動の抜き方ごとに比べる（#67・#68・#120・#121）。

使い方（リポジトリの直下で）:

    lune run kensho/meshy-rig/tools/techniques > ~/musou-work/techniques.json
    python3 -I kensho/meshy-rig/tools/hikaku_player.py ~/musou-work/characters/jin ~/musou-work/techniques.json

- 骨は刃のリグの GLB（rig.rigged_character_glb.glb）、クリップは motions/idNNN.glb を使う（Meshy の出力。Git には無い）
- 技の区間・行動の長さ・判定の出る間・前進・腰の移動の抜き方は、techniques.luau が musou の src/shared から書き出した JSON から読む
- クリップの区間は、行動の長さに合わせて等速で流す（MotionPlayer.luau と同じ）。0.05 秒ごとに順運動学で骨の位置を求める
- 値は休息の姿勢（立った姿）からのずれで、刃の背丈を 5 スタッドにしてから、R15 の脚の長さとの比（LEG_RATIO）を掛けたスタッド
- ゲームの根元の部品（HumanoidRootPart）は立ったまま前進するので、腰のずれがそのまま見た目と判定のずれになる
- 抜き方は glb_to_luau.py・MeshyRig.stripRoot と同じ。xz は腰（Hips）の水平の移動、all は腰の移動をすべて、pose は腰の移動と回転を抜く

出す値:

- 命中: 判定の出ている間（Startup から Active の終わり）の腰の前後・左右のずれの最大
- 終わり: 行動の終わりの腰のずれ（前後・左右・上下）。次の行動か待機に移るとき、この分だけ体が根元へ戻って跳ねる
- 足: 区間の中の足の骨の高さ（休息の姿勢の足の骨の高さからの差）の最低と最高。負なら床に沈み、正なら浮く
- 胴: 腰から頭への向きの、鉛直からの角度の最小と最大（頭→終わり）
- 詳しい表は、引数の後ろに技の名前（techniques.json の name）を並べた技だけ、原本・水平・全軸の3通りを出す
"""

import importlib.util
import json
import math
import os
import sys

STEP = 0.05
HEIGHT_STUDS = 5.0
# R15 の脚の長さ（床から腰まで）。刃の脚の長さとの比で、刃の骨の値を R15 の大きさに直す
R15_LEG = 3.0
FEET = ("LeftFoot", "LeftToeBase", "RightFoot", "RightToeBase")
MODES = ("keep", "xz", "all")

def load_tools():
    here = os.path.dirname(os.path.abspath(__file__))
    spec = importlib.util.spec_from_file_location("glb_to_luau", os.path.join(here, "glb_to_luau.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


G = load_tools()


def read_clip(path):
    js, binc = G.load_glb(path)
    anim = js["animations"][0]
    tracks = {}
    for ch in anim["channels"]:
        node = js["nodes"][ch["target"]["node"]]
        smp = anim["samplers"][ch["sampler"]]
        times = [v[0] for v in G.accessor(js, binc, smp["input"])]
        vals = G.accessor(js, binc, smp["output"])
        tracks.setdefault(node["name"], {})[ch["target"]["path"]] = (times, vals)
    return tracks


def pose_at(rows, tracks, t, mode):
    """t 秒の骨のワールドの位置（GLB の単位、Y が上）"""
    world = {}
    for row in rows:
        name = row["name"]
        t0, r0 = row["t"], row["r"]
        tr = tracks.get(name, {})
        tt = G.sample(*tr["translation"], t, False) if "translation" in tr else t0
        rr = G.qnorm(G.sample(*tr["rotation"], t, True)) if "rotation" in tr else r0
        if name == "Hips":
            if mode == "xz":
                tt = (t0[0], tt[1], t0[2])
            elif mode in ("all", "pose"):
                tt = t0
            if mode == "pose":
                rr = r0
        parent = row["parent"]
        if parent:
            pp, pq = world[parent]
            rt = G.qrot(pq, tt)
            world[name] = (tuple(pp[k] + rt[k] for k in range(3)), G.qmul(pq, rr))
        else:
            world[name] = (tuple(tt), rr)
    return world


def tilt_of(world):
    hips = world["Hips"][0]
    head = world["Head"][0]
    v = [head[k] - hips[k] for k in range(3)]
    length = math.sqrt(sum(c * c for c in v)) or 1.0
    return math.degrees(math.acos(max(-1.0, min(1.0, v[1] / length))))


def measure(rows, rest, tracks, tech, mode, unit):
    rest_hips = rest["Hips"][0]
    rest_feet = min(rest[f][0][1] for f in FEET if f in rest)
    samples = []
    steps = int(round(tech["duration"] / STEP))
    span = tech["to"] - tech["from"]
    for i in range(steps + 1):
        game_t = min(i * STEP, tech["duration"])
        clip_t = tech["from"] + span * game_t / tech["duration"] if tech["duration"] > 0 else tech["from"]
        world = pose_at(rows, tracks, clip_t, mode)
        hips = world["Hips"][0]
        # 刃の正面は glTF の +Z。前後は +Z が前、左右は +X が体の左
        forward = (hips[2] - rest_hips[2]) * unit
        lateral = (hips[0] - rest_hips[0]) * unit
        up = (hips[1] - rest_hips[1]) * unit
        feet = (min(world[f][0][1] for f in FEET if f in world) - rest_feet) * unit
        samples.append({"t": game_t, "forward": forward, "lateral": lateral, "up": up, "feet": feet, "tilt": tilt_of(world)})
    hit = [s for s in samples if tech["startup"] - 1e-6 <= s["t"] <= tech["startup"] + tech["active"] + 1e-6] or samples
    end = samples[-1]
    return {
        "hit_forward": max(abs(s["forward"]) for s in hit),
        "hit_lateral": max(abs(s["lateral"]) for s in hit),
        "end_forward": end["forward"],
        "end_lateral": end["lateral"],
        "end_up": end["up"],
        "feet_min": min(s["feet"] for s in samples),
        "feet_max": max(s["feet"] for s in samples),
        "up_min": min(s["up"] for s in samples),
        "up_max": max(s["up"] for s in samples),
        "tilt_min": min(s["tilt"] for s in samples),
        "tilt_max": max(s["tilt"] for s in samples),
        "start_tilt": samples[0]["tilt"],
        "end_tilt": end["tilt"],
        "start_up": samples[0]["up"],
    }


# 詳しい表を出す技の既定（PM判断 2026-10-17 の代表技。#67）
DETAIL = (
    "手裏剣 6段目",
    "刀 C4",
    "手裏剣 緊急回避",
    "刀 緊急回避",
    "手裏剣 ジャンプ攻撃",
    "刀 ジャンプ攻撃",
    "手裏剣 ダウン",
    "刀 ダウン",
    "刀 起き上がり",
)
LABELS = {"keep": "原本", "xz": "水平", "all": "全軸", "pose": "移動と回転"}


def title(tech):
    return f"{tech['name']}（id{tech['clip']} {tech['from']:g}〜{tech['to']:g}、{tech['duration']:.2f} 秒）"


def main():
    base = os.path.expanduser(sys.argv[1] if len(sys.argv) > 1 else "~/musou-work/characters/jin")
    with open(os.path.expanduser(sys.argv[2] if len(sys.argv) > 2 else "~/musou-work/techniques.json"), encoding="utf-8") as f:
        techniques = json.load(f)
    detail = tuple(sys.argv[3:]) or DETAIL
    rjs, _ = G.load_glb(os.path.join(base, "rig.rigged_character_glb.glb"))
    rows, top = G.skeleton(rjs)
    scale = HEIGHT_STUDS / top
    rest = pose_at(rows, {}, 0.0, "keep")
    jin_leg = (rest["Hips"][0][1] - min(rest[f][0][1] for f in FEET)) * scale
    ratio = R15_LEG / jin_leg
    unit = scale * ratio
    print(f"刃の脚の長さ {jin_leg:.2f} スタッド（背丈 5）、R15 の脚 {R15_LEG} との比 {ratio:.2f}")
    print()
    print("## 一覧（指定の抜き方）")
    print()
    print("| 技 | 抜き方 | 原本の終わりの水平のずれ 前後・左右 | 終わりの上下 | 足 最低〜最高 | 全軸にしたときの足 | 胴 最小〜最大（頭→終わり） |")
    print("|---|---|---|---|---|---|---|")
    cache = {}
    results = {}
    for tech in techniques:
        if tech["clip"] not in cache:
            cache[tech["clip"]] = read_clip(os.path.join(base, "motions", f"id{tech['clip']:03d}.glb"))
        tracks = cache[tech["clip"]]
        per = {mode: measure(rows, rest, tracks, tech, mode, unit) for mode in ("keep", "xz", "all")}
        results[tech["name"]] = (tech, per)
        chosen = per.get(tech["strip"]) or measure(rows, rest, tracks, tech, tech["strip"], unit)
        keep = per["keep"]
        alt = per["all"] if tech["strip"] != "all" else per["xz"]
        alt_label = "全軸" if tech["strip"] != "all" else "水平"
        print(
            f"| {title(tech)} | {LABELS[tech['strip']]} "
            f"| {keep['end_forward']:.2f}・{keep['end_lateral']:.2f} "
            f"| {chosen['end_up']:.2f} "
            f"| {chosen['feet_min']:.2f}〜{chosen['feet_max']:.2f} "
            f"| {alt_label} {alt['feet_min']:.2f}〜{alt['feet_max']:.2f} "
            f"| {chosen['tilt_min']:.0f}〜{chosen['tilt_max']:.0f}（{chosen['start_tilt']:.0f}→{chosen['end_tilt']:.0f}） |"
        )
    print()
    print("## 代表技（原本・水平・全軸）")
    print()
    print("| 技 | 抜き方 | 命中 前後・左右 | 終わり 前後・左右・上下 | 足 最低〜最高 | 腰 上下 | 胴 最小〜最大（頭→終わり） |")
    print("|---|---|---|---|---|---|---|")
    for name in detail:
        if name not in results:
            print(f"| {name} | 一覧に無い | | | | | |")
            continue
        tech, per = results[name]
        for mode in ("keep", "xz", "all"):
            m = per[mode]
            print(
                f"| {title(tech)} | {LABELS[mode]} "
                f"| {m['hit_forward']:.2f}・{m['hit_lateral']:.2f} "
                f"| {m['end_forward']:.2f}・{m['end_lateral']:.2f}・{m['end_up']:.2f} "
                f"| {m['feet_min']:.2f}〜{m['feet_max']:.2f} "
                f"| {m['up_min']:.2f}〜{m['up_max']:.2f} "
                f"| {m['tilt_min']:.0f}〜{m['tilt_max']:.0f}（{m['start_tilt']:.0f}→{m['end_tilt']:.0f}） |"
            )


if __name__ == "__main__":
    main()
