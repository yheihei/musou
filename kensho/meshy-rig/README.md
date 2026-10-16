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
python3 -I kensho/meshy-rig/tools/glb_to_luau.py ~/musou-work/characters/jin/rig.rigged_character_glb.glb ~/musou-work/characters/jin/motions/id004.glb ~/musou-work/characters/jin/motions/id219.glb ~/musou-work/characters/jin/motions/id179.glb ~/musou-work/characters/jin/motions/id182.glb ~/musou-work/characters/jin/motions/id007.glb ~/musou-work/characters/jin/motions/id189.glb ~/musou-work/characters/jin/motions/id003.glb ~/musou-work/characters/jin/motions/id219.glb@xz ~/musou-work/characters/jin/motions/id179.glb@xz ~/musou-work/characters/jin/motions/id182.glb@all ~/musou-work/characters/jin/motions/id007.glb@all ~/musou-work/characters/jin/motions/id189.glb@xz ~/musou-work/characters/jin/motions/id003.glb@xz > kensho/meshy-rig/server/MeshyRig/Jin.luau
```

腰の移動を抜く指定は、#88 の PM判断（2026-10-17）の案（吹き飛び・打ち上げは全軸、ほかの4項目は水平だけ）に合わせてある。

クリップのパスの後ろの `@xz` は腰の水平の移動を、`@all` は腰の移動をすべて抜く。
抜いたクリップの名前は `id182_all` のように後ろに付く（抜く前と並べて比べられる）。

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
| `ServerStorage.MeshyRig.Jin` | 刃の骨 24 本と、クリップ 13 本（刃の攻撃 id004、下忍の6項目 id219・id179・id182・id007・id189・id003、腰の移動を抜いた id219_xz・id179_xz・id182_all・id007_all・id189_xz・id003_xz。10 コマ/秒） |
| `ReplicatedStorage.Shared` | musou の `src/shared`。比較（`hikaku`）が、下忍の区間（`Motions.luau`）・反応の秒数と軌道（`Config.luau`・`Trajectory.luau`）をゲームと同じ定義から引く |
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
| `print(require(game.ServerStorage.MeshyRig).fukuro(nil, "id182"))` | 「復路（id182_Shot_and_Blown_Back を R15 で流す…）」。R15 が後ろへ吹き飛ばされて倒れ、体が 17 スタッドほどずれる。クリップ名は `Jin` の 11 本のどれか |
| `print(require(game.ServerStorage.MeshyRig).fukuro(nil, "id182_all"))` | 同じ吹き飛びを、腰の移動を抜いて流す。R15 はその場で吹き飛ばされる姿を取り、体はずれない |
| `print(require(game.ServerStorage.MeshyRig).map(workspace.MeshyRigCheck.JinBones))` | 「JinBones の関節を 22/22 対応づけた（足りない骨: なし）」と「体の正面は、根元の部品 Root の -Z から 2 度」 |
| `print(require(game.ServerStorage.MeshyRig).hikaku("Knockback"))` | 下の「下忍の6項目をゲームの体の扱いで比べる」 |
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

## 下忍の6項目をゲームの体の扱いで比べる（#88）

`hikaku(項目)` は、下忍の項目のクリップを、左に原本、右に腰の移動を抜いた版の R15 で流し、ゲームの体の扱い（`Hanno`）と時間どおりに比べる。
吹き飛びと打ち上げは、手裏剣セットの C1・C2 の強さで軌道を飛び、着地したら倒れて起き上がる。
倒れている間は根元の部品を仰向けに 90 度回し、起き上がりでは立った高さへ戻す（`Hanno` と同じ）。
クリップは区間の頭から等速で流し、区間の終わりの姿で残す（`EnemyService` の被弾の反応と同じ）。

段ごとに3つの時刻で、次の値を測る。

| 値 | 意味 | 印 |
|---|---|---|
| 腰のずれ | 腰（LowerTorso）の、根元の部品（当たり判定の位置）からの離れ。水平と縦 | 水平 1 スタッドを超えると「二重移動」 |
| 床から | 体の最も低い点の、床の上の面からの高さ | -0.3 より下で「沈む」、飛んでいないのに 0.5 より上で「浮く」 |
| 胴の傾き | 腰から頭への向きの、鉛直からの角度 | 135 度を超えると「二重回転」 |

| 手順 | 期待動作 |
|---|---|
| `print(require(game.ServerStorage.MeshyRig).hikaku("Knockback"))` | 10 秒ほどで、流れ（飛ぶ 0.26 秒 → 倒れる 1.00 秒 → 起き上がる 0.50 秒 → 待機）と段ごとの値。2体が同じ流れを繰り返す |
| `print(require(game.ServerStorage.MeshyRig).hikaku("Down", nil, { Down = "pose" }))` | 倒れる段の除去版を、腰の移動と回転を抜いた形で比べる。抜き方は `xz`・`all`・`pose` |
| `print(require(game.ServerStorage.MeshyRig).hikaku("Knockback", workspace.Jin))` | 取り込んだ刃（クリップ編集で読み込んだクリップを名前で探し、無ければ Jin.luau の値）で比べる |

### 結果（2026-10-17、合成した刃の骨、GLB の値を 5 コマ/秒にしたもの）

musou のテストプレイの中に道具を読み込んで測った（プレースは変えていない）。

| 段 | 原本 | 除去版（PM の案） |
|---|---|---|
| 吹き飛びで飛ぶ 0.26 秒（id182 の 0.60〜0.86 秒） | 腰が水平に最大 2.31 ずれる（二重移動）。胴の傾き 2〜11 度 | 全軸を抜くと 0.06。胴の傾き 2〜11 度 |
| 打ち上げで飛ぶ 0.83 秒（id007 の 0.00〜0.83 秒） | 腰が縦に -3.19〜+3.33 ずれる（軌道と二重）。胴の傾き 56〜91 度 | 全軸を抜くと縦 -0.22〜-0.10 |
| 倒れる 1.00 秒（id189 の 1.40〜2.23 秒） | 胴の傾き 174〜177 度（二重回転）、床から -5.7（沈む） | 水平だけ抜いても 174〜177 度（二重回転）、床から -2.3、水平のずれ 3.4 |
| 起き上がる 0.50 秒（id003 の 0.00〜0.50 秒） | 0.5 秒で切れた時点で胴が 47〜74 度傾いたまま。床から -1.8（沈む） | 同じ |

- 吹き飛びは、軌道が 0.26 秒で着地するので、クリップの 0.60〜0.86 秒しか流れない（後ろへ倒れる 1.0 秒より後は見えない）
- 倒れる段は、クリップ自体が胴を後ろへ約 90 度倒す（GLB の順運動学で 91〜95 度）ので、`Hanno` の仰向けの 90 度と重なる。
  縦の移動は、根元の部品が寝ているので水平の移動になる
- 腰の移動と回転を両方抜く（`pose`）と、倒れる段は水平のずれ 0.00、床から 0.11〜0.21、胴の傾き 78〜85 度になった
- 起き上がりは、ゲームの起き上がりの 0.5 秒に対してクリップが 1.87 秒あり、等速で流すと 27% で切れて待機へ戻る

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

### 下忍の6項目（`Motions.luau` の `MeshySources.Genin`）

同じ形で、刃の骨で取った下忍のクリップを、`MeshySources.Genin` の区間の中の5つの時刻で R15 と比べた。

| 項目 | クリップ | 区間（秒） | 骨の手足の動きの最大 | 差の平均 / 最大 | 腰の移動（刃の骨 / R15） |
|---|---|---|---|---|---|
| Attack | 219 Right_Hand_Sword_Slash | 0〜1.533 | 141 度 | 3〜39 / 45 度 | 0.69 / 1.05 スタッド |
| Flinch | 179 Hit_Reaction_1 | 0〜0.6 | 101 度 | 5〜31 / 36 度 | 0.33 / 0.51 スタッド |
| Knockback | 182 Shot_and_Blown_Back | 0.6〜2 | 168 度 | 2〜25 / 36 度 | 11.34 / 17.15 スタッド |
| Launch | 7 BeHit_FlyUp | 0〜1 | 131 度 | 4〜30 / 48 度 | 2.99 / 4.53 スタッド |
| Down | 189 dying_backwards | 1.4〜2.2 | 26 度 | 5〜28 / 29 度 | 3.12 / 4.71 スタッド |
| GetUp | 3 Arise | 0〜1.867 | 143 度 | 4〜27 / 57 度 | 2.13 / 3.23 スタッド |

6本とも R15 に移った。
腰の移動（クリップの中で体が動く分）も R15 に移り、脚の長さの比で約 1.5 倍になる。
吹き飛びは R15 で 17 スタッド後ろへ動く。
ゲームでは吹き飛びと打ち上げの軌道をサーバーが決める（#99）ので、公開するクリップは腰の移動を抜く必要がある。
腰の移動を抜いた吹き飛び（`id182_all`）は、R15 でも腰の関節が動かず（0.00 スタッド）、手足の差は抜く前と同じ（最大 36 度）だった。

ゲームで流すには、`AnimationRigData` を付けたクリップを公開して ID を入れる。
公開は開発者のアカウントで行う。
