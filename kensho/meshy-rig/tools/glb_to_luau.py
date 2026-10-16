"""Meshy のリグとクリップの GLB から、検証用プレースの骨とクリップのデータ（Luau）を作る。

使い方（リポジトリの直下で）:

    python3 -I kensho/meshy-rig/tools/glb_to_luau.py \
        ~/musou-work/characters/jin/rig.rigged_character_glb.glb \
        ~/musou-work/characters/jin/motions/id004.glb \
        > kensho/meshy-rig/server/MeshyRig/Jin.luau

- 骨は、リグの GLB の休息の姿勢（ノードの既定の値）から作る。背丈（頭の先の骨の高さ）を 5 スタッドにそろえる
- glTF の正面は +Z、Roblox の正面は -Z なので、腰の骨（Hips）に Y 軸まわりの 180 度を入れる。
  根元の部品の -Z が体の正面になる（Adaptive Animation は根元の部品の向きを正面として扱う）
- クリップは 10 コマ/秒で取り出し、骨ごとに休息の姿勢からの差（Bone.Transform と同じ形）にする
- クリップのパスの後ろに @xz を付けると腰（Hips）の水平の移動を、@all を付けると腰の移動をすべて抜く。
  名前は id182_all のように後ろに付ける（同じクリップの抜いたものと抜かないものを並べて比べられる）
"""

import json
import math
import os
import struct
import sys

HEIGHT_STUDS = 5.0
FPS = 10.0
SKIP_IN_CLIP = ("head_end", "headfront")


def load_glb(path):
    with open(path, "rb") as f:
        data = f.read()
    magic, _version, length = struct.unpack_from("<4sII", data, 0)
    if magic != b"glTF":
        raise ValueError(f"{path} は GLB ではない")
    off = 12
    js = None
    binc = b""
    while off < length:
        clen, ctype = struct.unpack_from("<I4s", data, off)
        chunk = data[off + 8 : off + 8 + clen]
        if ctype == b"JSON":
            js = json.loads(chunk)
        elif ctype == b"BIN\x00":
            binc = chunk
        off += 8 + clen
    return js, binc


NCOMP = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def accessor(js, binc, idx):
    a = js["accessors"][idx]
    bv = js["bufferViews"][a["bufferView"]]
    if a["componentType"] != 5126:
        raise ValueError("float32 以外の accessor は扱わない")
    n = NCOMP[a["type"]]
    base = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    stride = bv.get("byteStride", 4 * n)
    return [struct.unpack_from(f"<{n}f", binc, base + i * stride) for i in range(a["count"])]


def qnorm(q):
    length = math.sqrt(sum(c * c for c in q)) or 1.0
    return tuple(c / length for c in q)


def qmul(a, b):
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return (
        aw * bx + ax * bw + ay * bz - az * by,
        aw * by - ax * bz + ay * bw + az * bx,
        aw * bz + ax * by - ay * bx + az * bw,
        aw * bw - ax * bx - ay * by - az * bz,
    )


def qinv(q):
    x, y, z, w = q
    return (-x, -y, -z, w)


def qrot(q, v):
    r = qmul(qmul(q, (v[0], v[1], v[2], 0.0)), qinv(q))
    return r[:3]


def slerp(a, b, t):
    d = sum(x * y for x, y in zip(a, b))
    if d < 0:
        b = tuple(-c for c in b)
        d = -d
    if d > 0.9995:
        return qnorm(tuple(x + (y - x) * t for x, y in zip(a, b)))
    th = math.acos(d)
    s = math.sin(th)
    wa = math.sin((1 - t) * th) / s
    wb = math.sin(t * th) / s
    return tuple(wa * x + wb * y for x, y in zip(a, b))


def sample(times, values, t, is_rot):
    if t <= times[0]:
        return values[0]
    if t >= times[-1]:
        return values[-1]
    lo, hi = 0, len(times) - 1
    while hi - lo > 1:
        mid = (lo + hi) // 2
        if times[mid] <= t:
            lo = mid
        else:
            hi = mid
    f = (t - times[lo]) / (times[hi] - times[lo])
    a, b = values[lo], values[hi]
    if is_rot:
        return slerp(a, b, f)
    return tuple(x + (y - x) * f for x, y in zip(a, b))


def skeleton(js):
    nodes = js["nodes"]
    joints = js["skins"][0]["joints"]
    parent = {}
    for i, n in enumerate(nodes):
        for c in n.get("children", []):
            parent[c] = i
    joint_set = set(joints)

    world = {}

    def world_of(i):
        if i in world:
            return world[i]
        n = nodes[i]
        t = tuple(n.get("translation", [0, 0, 0]))
        r = qnorm(tuple(n.get("rotation", [0, 0, 0, 1])))
        if i in parent and parent[i] in joint_set:
            pp, pq = world_of(parent[i])
            rt = qrot(pq, t)
            world[i] = (tuple(pp[k] + rt[k] for k in range(3)), qmul(pq, r))
        else:
            world[i] = (t, r)
        return world[i]

    order = []
    seen = set()

    def visit(i):
        if i in seen:
            return
        if i in parent and parent[i] in joint_set:
            visit(parent[i])
        seen.add(i)
        order.append(i)

    for j in joints:
        visit(j)
    top = max(world_of(j)[0][1] for j in joints)
    rows = []
    for i in order:
        n = nodes[i]
        pname = nodes[parent[i]]["name"] if (i in parent and parent[i] in joint_set) else ""
        rows.append(
            {
                "name": n["name"],
                "parent": pname,
                "t": tuple(n.get("translation", [0, 0, 0])),
                "r": qnorm(tuple(n.get("rotation", [0, 0, 0, 1]))),
            }
        )
    return rows, top


ROOT_BONE = "Hips"
ROOT_MODES = ("keep", "xz", "all")


def clip_frames(rig_rows, js, binc, scale, root_mode="keep"):
    rest = {row["name"]: (row["t"], row["r"]) for row in rig_rows}
    anim = js["animations"][0]
    tracks = {}
    tmax = 0.0
    for ch in anim["channels"]:
        node = js["nodes"][ch["target"]["node"]]
        smp = anim["samplers"][ch["sampler"]]
        times = [v[0] for v in accessor(js, binc, smp["input"])]
        vals = accessor(js, binc, smp["output"])
        tracks.setdefault(node["name"], {})[ch["target"]["path"]] = (times, vals)
        tmax = max(tmax, times[-1])
    order = [row["name"] for row in rig_rows if row["name"] in tracks and row["name"] not in SKIP_IN_CLIP]
    nframes = int(round(tmax * FPS)) + 1
    frames = []
    for fi in range(nframes):
        t = min(fi / FPS, tmax)
        values = [t]
        for name in order:
            t0, r0 = rest[name]
            tr = tracks[name]
            tt = sample(*tr["translation"], t, False) if "translation" in tr else t0
            rr = qnorm(sample(*tr["rotation"], t, True)) if "rotation" in tr else r0
            r0i = qinv(r0)
            dq = qnorm(qmul(r0i, rr))
            # 移動は親（Armature）の向きで抜いてから、休息の姿勢の向きへ直す（親の Y が上）
            moved = [tt[k] - t0[k] for k in range(3)]
            if name == ROOT_BONE and root_mode == "xz":
                moved = [0.0, moved[1], 0.0]
            elif name == ROOT_BONE and root_mode == "all":
                moved = [0.0, 0.0, 0.0]
            dt = qrot(r0i, tuple(moved))
            values += [dt[0] * scale, dt[1] * scale, dt[2] * scale, dq[0], dq[1], dq[2], dq[3]]
        frames.append(values)
    return anim.get("name", ""), tmax, order, frames


def fmt(v, digits):
    s = f"{v:.{digits}f}"
    if s.startswith("-") and float(s) == 0:
        s = s[1:]
    return s


def main():
    rig_path = sys.argv[1]
    clip_paths = sys.argv[2:]
    rjs, _ = load_glb(rig_path)
    rows, top = skeleton(rjs)
    scale = HEIGHT_STUDS / top
    out = []
    out.append("--!strict")
    out.append("-- 刃の Meshy のリグ（骨）とクリップ。kensho/meshy-rig/tools/glb_to_luau.py で作った。手で直さない")
    out.append(f"-- リグ: {os.path.basename(rig_path)}、背丈 {top:.2f}（GLB の単位）を {HEIGHT_STUDS:g} スタッドにした")
    out.append("")
    out.append("local Jin = {}")
    out.append("")
    out.append("-- { 名前, 親の骨の名前（\"\" は根元の部品）, x, y, z, qx, qy, qz, qw }。休息の姿勢（T ポーズ）。")
    out.append("-- 親から見た位置と向き（Bone.CFrame）。根元の部品の -Z が体の正面になるよう、Hips に Y 軸まわりの 180 度を入れてある")
    out.append("Jin.bones = {")
    ry = (0.0, 1.0, 0.0, 0.0)
    for row in rows:
        t = row["t"]
        r = row["r"]
        t = (t[0] * scale, t[1] * scale, t[2] * scale)
        if row["parent"] == "":
            t = qrot(ry, t)
            r = qnorm(qmul(ry, r))
        nums = ", ".join([fmt(t[0], 4), fmt(t[1], 4), fmt(t[2], 4), fmt(r[0], 6), fmt(r[1], 6), fmt(r[2], 6), fmt(r[3], 6)])
        out.append(f'\t{{ "{row["name"]}", "{row["parent"]}", {nums} }},')
    out.append("}")
    out.append("")
    out.append("-- クリップ。frames は1コマ1行の文字列で、時刻のあとに order の骨ごとの x, y, z, qx, qy, qz, qw（Bone.Transform）")
    out.append("Jin.clips = {")
    for arg in clip_paths:
        path, _, root_mode = arg.partition("@")
        root_mode = root_mode or "keep"
        if root_mode not in ROOT_MODES:
            raise ValueError(f"{arg} の @ の後ろは xz か all")
        cjs, cbin = load_glb(path)
        name, length, order, frames = clip_frames(rows, cjs, cbin, scale, root_mode)
        key = os.path.splitext(os.path.basename(path))[0]
        if root_mode != "keep":
            key = f"{key}_{root_mode}"
        for f in frames:
            if len(f) != 1 + 7 * len(order):
                raise ValueError("コマの値の数が合わない")
        label = name.split("|")[1] if "|" in name else name
        out.append(f"\t{key} = {{")
        out.append(f'\t\tname = "{label}",')
        out.append(f"\t\tlength = {length:.4f},")
        out.append("\t\torder = {")
        for bone in order:
            out.append(f'\t\t\t"{bone}",')
        out.append("\t\t},")
        out.append("\t\tframes = {")
        for f in frames:
            nums = [fmt(f[0], 3)] + [fmt(v, 3) for v in f[1:]]
            out.append(f'\t\t\t"{",".join(nums)}",')
        out.append("\t\t},")
        out.append("\t},")
    out.append("}")
    out.append("")
    out.append("return Jin")
    sys.stdout.write("\n".join(out) + "\n")


main()
