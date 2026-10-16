# Meshy のリグと R15 の往復の検証用プレース（#16）

Adaptive Animation で、Meshy のリグ（骨）と R15 のあいだのモーションの往復を確かめるプレース。
musou のプレースとは別に作る。
2026-10-16 に、刃の GLB から組んだ骨で往復とも再生できた（下の「分かったこと」）。
取り込んだ刃の FBX でも、同じ道具で確かめられる。

## 作り方

骨とクリップのデータ（`server/MeshyRig/Jin.luau`）を、刃の GLB から作ってからプレースを組む。
Meshy の出力（`~/musou-work`）は Git に入れないので、`Jin.luau` も Git には無い（`.gitignore`）。
Git で持つかは #141 で決める。

```bash
python3 -I kensho/meshy-rig/tools/glb_to_luau.py ~/musou-work/characters/jin/rig.rigged_character_glb.glb ~/musou-work/characters/jin/motions/id004.glb > kensho/meshy-rig/server/MeshyRig/Jin.luau
```

```bash
stylua kensho/meshy-rig/server
```

```bash
rojo build kensho/meshy-rig/meshy-rig.project.json -o ~/musou-work/meshy-rig/meshy-rig.rbxl
```

2026-10-16 に組んだものが `~/musou-work/meshy-rig/meshy-rig.rbxl` にある。

## 中身

| 場所 | 中身 |
|---|---|
| `ServerStorage.MeshyRig` | 往路・復路・関節の対応づけ・見本の再生の道具 |
| `ServerStorage.MeshyRig.Jin` | 刃の骨 24 本と攻撃のクリップ（id004、2.83 秒、10 コマ/秒） |
| `ServerScriptService.MeshyRigDemo` | テストプレイを始めると見本を流す |
| Workspace | 床と出現地点だけ |

musou の `default.project.json` には入れない。
CI が見る `src` の外に置いてあるので、手元で `stylua kensho/meshy-rig/server` と `selene kensho/meshy-rig/server` を通す。

## 使い方

Studio のメニューの「ファイル」→「ファイルから開く」で `~/musou-work/meshy-rig/meshy-rig.rbxl` を開く。
テストプレイを始めると、出現地点の前に左から刃の骨と R15 が出て、往路と復路を 6 秒ずつ交互に流す。
刃の骨は青い棒で、白い棒が顔の正面。

コマンドバーをサーバー表示にして（テスト > クライアント表示の切り替え）、次の行を打つ。

| 手順 | 期待動作 |
|---|---|
| `print(require(game.ServerStorage.MeshyRig).orai())` | 6 秒ほどで「往路（R15 のモーションを JinBones で流す…）」。待機は差の最大 33 度、走りは 27 度（10/16 の値） |
| `print(require(game.ServerStorage.MeshyRig).fukuro())` | 3 秒ほどで「復路（id004_Attack を R15 で流す…）」。差の最大 46 度、刃の骨の手足は最大 107 度動く |
| `print(require(game.ServerStorage.MeshyRig).map(workspace.MeshyRigCheck.JinBones))` | 「JinBones の関節を 22/22 対応づけた（足りない骨: なし）」と「体の正面は、根元の部品 Root の -Z から 2 度」 |
| `print(require(game.ServerStorage.MeshyRig).clear())` | 「MeshyRigCheck を片づけた」。刃の骨と R15 が消える |

差は、関節から関節への向き（胴・上腕・前腕・太もも・すね）の角度で、5 つの時刻の平均と最大。
体つきが違う（刃は頭が大きく脚が短い）ので、0 にはならない。

## 取り込んだ FBX で確かめる

| 手順 | 期待動作 |
|---|---|
| 編集中に、ホーム > インポートで `~/musou-work/characters/jin/rig.rigged_character_fbx.fbx` を Rig Type Custom で取り込む（Roblox へのアップロードは外す） | workspace に刃の Model ができる。名前を `Jin` にする |
| コマンドバー（編集中）で `local m = workspace.Jin m:ScaleTo(m:GetScale() * 5 / m:GetExtentsSize().Y) m:PivotTo(CFrame.new(-12, 0, -12) * CFrame.Angles(0, math.pi, 0)) local cf, size = m:GetBoundingBox() m:PivotTo(m:GetPivot() + Vector3.new(0, size.Y / 2 - cf.Position.Y, 0)) print(m:GetExtentsSize())` | 高さ（Y）が 5。刃が見本の左に、こちらを向いて立つ |
| アバター > クリップ編集で `Jin` を選び、「⋯」→「インポート」→「次のファイルから...」で `~/musou-work/characters/jin/motions/id004.fbx` を読み込む（「休息ポーズのリソース」は「アニメーション編集用リグ」） | 2.83 秒の Attack が入り、刃が両手で振りかぶって斬り下ろす |
| テストプレイを始め、サーバー表示で `print(require(game.ServerStorage.MeshyRig).map(workspace.Jin))` | 「Jin の関節を 22/22 対応づけた」。体の正面のずれが 45 度以下 |
| `print(require(game.ServerStorage.MeshyRig).orai(workspace.Jin))` | 刃のメッシュが Ninja の待機（構えて体を揺らす）と走りを流す。差の最大は合成した骨（待機 33 度・走り 27 度）に近い。脚が後ろへ曲がると太ももの差が 100 度を超える |
| `print(require(game.ServerStorage.MeshyRig).fukuro(workspace.Jin))` | R15 が刃の攻撃（両手で振りかぶって斬り下ろす）を流す。差の最大は合成した骨（46 度）に近い |

`fukuro(workspace.Jin)` は、クリップ編集で読み込んだクリップ（`ServerStorage.RBX_ANIMSAVES.Jin` のいちばん長いもの）を使う。
読み込んでいなければ `Jin.luau` の id004 を使うが、GLB の値なので、取り込んだ骨の向きが GLB と違うと刃の姿が崩れる。

## 分かったこと（2026-10-16）

musou のテストプレイの中で、刃の GLB から骨 24 本を組んで確かめた（スキンのメッシュは無い）。

| 項目 | 結果 |
|---|---|
| 往路（R15 の Ninja の待機・走りを骨で） | 骨に移る。差の最大は待機 33 度、走り 27 度。胴 5 度、脚 18 度以内 |
| 復路（刃の攻撃を R15 で） | `AnimationRigData` を付けると R15 に移る。差の平均 3〜30 度、最大 46 度 |
| 動かす入れ物 | `AnimationController` でも `Humanoid` でも同じ値 |
| 関節の対応づけ | `HumanoidRigDescription` をスクリプトで作り、22 関節に骨を入れれば足りる（Remap Rig の画面と T ポーズの調整は要らなかった） |
| 体の正面 | 根元の部品（骨の親の部品）の -Z が正面として扱われる。根元の部品だけを 180 度回すと、脚が後ろへ曲がる（差 150 度） |
| 骨の名前のクリップ | `HumanoidRigDescription` の有無によらず骨にそのまま効く。R15 には効かない |
| `AnimationRigData` | `AnimationRigData:LoadFromModel(骨のモデル)` で作れる。公開済みの R15 のモーションには `AnimationRigDataBlocky` が入っている |
| 公開 | `KeyframeSequenceProvider:RegisterKeyframeSequence` の一時 ID でも、`AnimationRigData` があれば移る。確かめるだけなら公開は要らない |
| 混ぜて流す | 待機（R15）の上に、骨の名前のクリップを Action で重ねると、そのクリップの骨だけが上書きされる |
| 止めたとき | トラックを止めても骨の姿勢は残る。次のトラックが流れると戻る |

ゲームで流すには、`AnimationRigData` を付けたクリップを公開して ID を入れる。
公開は開発者のアカウントで行う。
