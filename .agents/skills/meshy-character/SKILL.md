---
name: meshy-character
description: musou のキャラクター（上忍・首領・NPC・操作キャラクター）の 3D モデルを、元の絵から三面図を作って fal の Meshy でモデル・リグ・モーションまで作るときに使う。
---

# 三面図から Meshy でキャラクターを作る

元の絵 → 正面・背面・側面の図 → Meshy 7.1 でテクスチャ付きのモデル → リグとライブラリのモーション、までを Claude が自動で進める。
Studio への取り込みとモーションの公開だけは人の手が要る。

参考にした記事（開発者が購入。リンクのみ記載し、中身は書き写さない）
https://brain-market.com/u/haru_mv/a/b1ATN5QjMgoTZsNWa0JXY
記事はブラウザの Meshy で作る。ここでは同じ流れを fal の API と CLI の画像生成に置き換えている。

## 前提

- fal の呼び出しは、fal の MCP か `FAL_KEY` を使う（`docs/design.md`「Meshy と fal」）。`FAL_KEY` が無いシェルでは `zsh -ic '...'` の中で実行する
- fal での生成に、1回ごとの開発者の承認は要らない。値段の確認も挟まない
- fal の残高が尽きると、どの窓口も 403「User is locked. Reason: TOP_UP.」で止まる（2026-10-13、5体目の途中で尽きた）。
  チャージは開発者の作業で、Claude からはしない。止まった段階と request_id を issue に書いて渡す
- 作業用の場所は `$HOME/musou-work/characters/<キャラクター ID の小文字>/`。リポジトリと `~/Documents/yhei`（Obsidian の vault で、画像が外へ上がる）には置かない
- 生成物（png・glb・fbx）はリポジトリに入れない。Git で管理するかは #139 の結論に従う
- `scripts/fal_meshy.py` は標準ライブラリだけで動く。手元の画像は data URI で渡すので、アップロードは要らない

```bash
SKILL=.agents/skills/meshy-character
WORK="$HOME/musou-work/characters/<id>"
mkdir -p "$WORK"
```

## 1. 元の絵を取る

NINJAMCP の `get_character_image` を `style = 2d` で呼び、`$WORK/source.png`（jpg のままでもよい）に保存する（顔グラフィックと同じ。`assets/faces/prompt.md`）。
NINJAMCP に無いキャラクター（NPC など）は、設定の文章から先に1枚の全身の絵を作る。
NINJAMCP の絵を1枚添付し、「絵柄の参考にだけ使い、別の無名のキャラクターを描く」と書くと、同じ絵柄で描ける
（下忍は刃の絵を添付し、装束の色・頭巾と覆面・武器なしを指示した。fal の画像生成の edit を指示文と添付だけで呼ぶ）。

## 2. 三面図を作る

正面・背面・側面（左）の3枚を作る。指示文は `references/view_front.txt`・`view_back.txt`・`view_side.txt`。
背面と側面は、正面図を1枚目に添付して作り、大きさと位置をそろえる。

決まりごと

- Tポーズ（腕を水平）。全身が入り、白い無地の背景
- 手に持つ物と武器は描かない。武器は別のモデルで手に付ける（#47）
- 背中の荷物、長く垂れた布、背中の大きな結び目は省く。腕と胴、脚の間がはっきり分かれるようにする

### 作り方（どれか1つ）

1. Codex の画像生成（既定。顔グラフィックと同じ経路）

   ```bash
   { echo "画像生成で1枚作り、作業用の場所に front.png として保存する。"; cat "$SKILL/references/view_front.txt"; } > "$WORK/prompt_front.txt"
   codex exec -m <画像生成を使えるモデル> --skip-git-repo-check -C "$WORK" -s workspace-write \
     --add-dir "$HOME/.codex/generated_images" -i "$WORK/source.png" - < "$WORK/prompt_front.txt"
   ```

   - モデル名は `assets/faces/prompt.md` に書いてあるものを使う
   - 背面は `back.png`、側面は `side.png` として保存させ、`-i "$WORK/front.png" -i "$WORK/source.png"` の順で添付する

2. fal の画像生成（Google の Nano Banana 2.1。Codex が使えないとき）

   ```bash
   python3 "$SKILL/scripts/fal_meshy.py" views --source "$WORK/source.png" --out "$WORK" --side
   ```

   `view_front.images.0.png`・`view_back.images.0.png`・`view_side.images.0.png` ができる。`front.png` などに名前を変えて使う。

3. Gemini の CLI で画像を作れる環境なら、同じ指示文と添付で作ってよい

### 確かめる

Read で3枚を開いて目で見る。次のどれかに当たれば、その1枚を作り直す。

- 正面と背面・側面で、頭のてっぺんと足の裏の高さがずれている
- 腕が水平でない、指が開いている、手に物を持っている
- 服の色や髪型が元の絵と違う、背景が白でない、影や文字がある
- 側面図で、体は正面のまま（両腕が左右に水平に伸びたまま）頭だけが横を向いている。このまま使うと、モデルの頭が横を向く。
  作り直すか、側面図を外して正面と背面の2枚でモデルを作る（石舟斎は2枚で崩れずに作れた）

作り直さずに使ってよいもの

- 側面図が左右どちら向きでも、正面図の左右非対称な飾り（結び目など）と見える側が合っていればよい
- 背面図で結び目などが左右逆になったときは、背面図を左右反転して使う（`sips -f horizontal back.png`）。費用はかからない

## 3. モデルを作る

```bash
python3 "$SKILL/scripts/fal_meshy.py" model --front "$WORK/front.png" --side "$WORK/side.png" --back "$WORK/back.png" \
  --out "$WORK" --polycount 3000
```

- 窓口は `meshy/v7.1/multi-image-to-3d`。画像は最大4枚で、正面・側面・背面の順に渡す
- テクスチャ付き、三角形、Tポーズ。`model_type: lowpoly` は Meshy 7.1 では使えない
- 三角形数は Roblox の上限（メッシュ1つあたり2万）の内側で決める。指定は目安で、少し超える（刃で 10000 → 10,367）

| 対象 | `--polycount` |
|---|---|
| 下忍・NPC（同時にたくさん出る） | 3000 |
| 上忍・首領・操作キャラクター | 10000 |

`model.thumbnail.png` を Read で見て確かめる。形が崩れたら、上から順に試す。

1. 同じ入力でもう一度作る（結果は毎回変わる）
2. `--pose a-pose` にする
3. 側面図を外し、正面と背面の2枚にする
4. 正面図だけにする（`meshy/v7.1/image-to-3d`）
5. 三面図の側を直す（布や髪が腕と胴をつないでいる絵は崩れやすい）

## 4. リグとモーションを付ける

```bash
python3 "$SKILL/scripts/fal_meshy.py" rig --out "$WORK" --height 1.7 --anims 0,4,92
```

- 窓口は `fal-ai/meshy/rigging/multi-animation`。`model.json` のモデルの GLB を読み、ヒューマノイドのリグを入れる
- 1回で付けられるモーションは10個まで。歩きと走り（`basic_animations`）は別に付いてくる
- モーションの ID（0〜696）は Meshy のライブラリの表から選ぶ（https://docs.meshy.ai/en/api/animation-library）。名前と種類で探し、選んだ ID と名前を issue に残す
- ライブラリの表の各行のプレビュー（`https://cdn.meshy.ai/webapp-assets/feature-demo/animation/preview/biped/<名前>.gif`）を ffmpeg でコマに分けて並べると、動きを見比べて選べる
- musou の行動に使うクリップと区間は `src/shared/Motions.luau` の `MeshyClips`・`MeshySources` に書く。クリップの長さは応答の GLB のアニメーションの長さを読む
- できたもの: `rig.rigged_character_fbx.fbx`（Studio に取り込む本体）、`rig.animations.id<モーション ID>.animation_fbx.fbx`（モーションごと）、`rig.basic_animations.*`（歩きと走り）
- リグが入らないときは、腕と胴が離れていない三面図が多い。2 に戻って作り直す

## 5. Studio に取り込む（人の手が要る）

FBX の取り込みとモーションの公開は Studio の画面でしかできない。
Claude は、取り込むファイルのパスと手順を issue に「Studio での作業」として書いて渡す（10/27 までは週1回の Studio の確認にまとめる）。

開発者がすること

1. 「ホーム」→「インポート」で本体の FBX を取り込む（取り込み時の Roblox へのアップロードは外す）
2. 「アバター」→「クリップ編集」でモーションの FBX を読み込み、「Roblox に公開」して ID を控える。次のモーションは新規作成から同じ手順

Claude が `execute_luau` で整えること（取り込んだ後）

- FBX はそのままだと巨大なので、`Model:ScaleTo()` で縮める。記事の値は 0.038。高さを測り、R15 と同じくらい（約5スタッド）にそろえる
- `MeshPart` は `CanCollide`・`CanTouch` を false
- 不要な `InitialPoses` フォルダを消す。明るすぎるときは `SurfaceAppearance` の `Color` を 190, 190, 190 にする
- モーションはクリップを切らずに丸ごと公開する（行動に使う区間は `MeshySources` に置き、コードで切り出す）
- 公開したモーションの ID は `src/shared/Motions.luau` の、そのクリップを使う項目すべてに入れる（窓口の `DumpMotions` で項目を確かめる）

## 6. 操作キャラクターにするとき

記事の手順は `Humanoid` の無い、`AnimationController` で動かすモデルまで。上忍・首領・NPC はこれで足りる。
操作キャラクターにする（R15 にする）方法は #139 で決める。決まったら、この skill に手順を足す。
Meshy のモーションを R15 で再生できるかは #16 で確かめる。

## 実績

- 2026-10-12 刃: 三面図（fal の Nano Banana、作り直し0回、背面図は左右反転）→ 1万三角形 → リグとモーション3つ。合わせて約6分。モデルの崩れなし
- 2026-10-13 刃のリグに、手裏剣セット・刀セット・奥義・下忍のモーション 39 本（10 本ずつ4回、1回 $0.08、各2〜3分）。作業用の場所は `characters/jin/motions/`
- 2026-10-13 酉花・石舟斎・金鬼・ハヤテ: 三面図（fal、4人並行で約2分、作り直し0回）→ 1万三角形（10,329〜10,414、各3〜5分）→ リグ（24 本、各1分前後）。
  ハヤテの腕の鷹と背中の刀は、三面図の指示で外れた。金鬼の毛皮の肩掛けは残ったが、モデルとリグは崩れなかった。
  石舟斎は側面図の頭だけが横を向いていて、1回目のモデルの頭が横を向いたので、正面と背面の2枚で作り直した。
  request_id はキャラクターごとの作業用の場所の `requests.txt`

## 記録

作り終えたら、issue に次を書く。

- 使った三面図の作り方（Codex・fal・Gemini）と作り直した回数
- fal の request_id、三角形数、モーションの ID と名前
- 作業用の場所のパス（生成物そのものは貼らない）
