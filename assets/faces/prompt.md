# 顔グラフィックの作り方

会話窓（#34）と戦闘中の台詞（#35）に添える顔グラフィックを、NINJAMCP のキャラクター画像から Codex で作る手順。
刃の5表情（`jin/`）でこの手順を固めた。酉花・石舟斎・金鬼・ハヤテ（#24）も同じ手順と規格で作った。NPC（#25）も同じように作る。

## 規格

| 項目 | 値 |
|---|---|
| 形式 | PNG（RGBA、背景は透過） |
| 大きさ | 512 × 512 の正方形 |
| 範囲 | 頭のてっぺんから胸の上まで |
| 顔の位置 | 頭は左右の中央、頭のてっぺんは上から 8% 前後、目は上から 42% 前後 |
| 絵柄 | 元画像と同じ太い黒の線と平塗り。目を少し大きく丸くし、少し可愛い方向に寄せる |
| 表情 | 通常・怒り・驚き・喜び・苦悶の5つ（`Tsujo`・`Ikari`・`Odoroki`・`Yorokobi`・`Kumon`） |
| 置き場所 | `assets/faces/<キャラクター ID の小文字>/<表情の小文字>.png` |

- 髪型・服の色・小物（額当て、武器、相棒の鷹など）は元画像のまま残す
- 文字・枠・背景の絵・地面の影は入れない
- 表情を変えるときは、目と眉と小さな漫符（怒りの印、汗）だけを変え、構図は通常の画像とそろえる

## 手順

作業は、リポジトリの外の作業用の場所で行う。元画像はリポジトリに入れない。

### 1. 元画像を取る

NINJAMCP の `get_character_image` を `style = 2d` で呼び、キャラクターのイラストを取る。
返った画像を作業用の場所に `source.jpg` として保存する。
`get_character` が返す `image_url` を落としてもよい（刃は `https://cn-lore-mcp.nubonba.workers.dev/images/001.jpg`）。

### 2. 通常の表情を作る

下の「通常のプロンプト」を `prompt_tsujo.txt` に書き、Codex の画像生成で作る。

```bash
codex exec -m gpt-6-astra --skip-git-repo-check -C "$WORK" -s workspace-write --add-dir "$HOME/.codex/generated_images" -i "$WORK/source.jpg" - < "$WORK/prompt_tsujo.txt"
```

- `$WORK` は作業用の場所
- モデルは ChatGPT のアカウントで画像生成を使えるもの（2026-10-01 は `gpt-6-astra`）を `-m` で指定する
- 生成した画像は `~/.codex/generated_images` に入り、Codex が作業用の場所に `tsujo.png` として写す
- 目の位置などの構図が規格から外れていたら、Codex に直させる（刃では Codex が自分で目の高さを直した）

### 3. 残りの4表情を作る

通常の画像を土台にして、下の「残りの表情のプロンプト」で4枚を作る。

```bash
codex exec -m gpt-6-astra --skip-git-repo-check -C "$WORK" -s workspace-write --add-dir "$HOME/.codex/generated_images" -i "$WORK/tsujo.png" -i "$WORK/source.jpg" - < "$WORK/prompt_others.txt"
```

### 4. 背景を透過にして大きさをそろえる

Codex の出力は白い背景なので、ImageMagick で縁から白を抜いて透過にし、512 × 512 に縮める。
縁につながった白だけを抜くので、目の白など線で囲まれた白は残る。

```bash
for hyojo in tsujo ikari odoroki yorokobi kumon; do
  magick "$WORK/$hyojo.png" -alpha set -bordercolor white -border 1 -fill none -fuzz 8% \
    -draw "color 0,0 floodfill" -shave 1x1 -resize 512x512 -strip "PNG32:assets/faces/jin/$hyojo.png"
done
```

### 5. 規格を確かめる

`lune run test KaoGraphic` で、登録した全表情の画像が 512 × 512 の透過ありの PNG かを確かめる。
見た目は、テストプレイで5表情を並べて撮って確かめる。

### 6. Roblox に登録する

Studio MCP の `upload_image` は HTTP で配信した画像を受け取る。
リポジトリの直下でローカルの HTTP サーバーを立て、画像の URL を渡す。登録が済んだらサーバーを止める。

```bash
python3 -m http.server 8765 --bind 127.0.0.1 --directory assets/faces
```

`upload_image` に `http://localhost:8765/jin/tsujo.png` などを渡すと、`rbxassetid://…` が返る。
アップロードは開発者の Roblox アカウントの画像になり、Roblox の審査を通る。
返ったアセット ID を `src/shared/KaoGraphic.luau` の登録表に書く。

## プロンプト

### 通常のプロンプト

刃のときの全文。キャラクターの特徴の行は、キャラクターごとに書き換える。

```text
Use your image generation tool to create ONE dialogue portrait ("face graphic") of the ninja character in the attached image (source.jpg). It will be shown next to dialogue text in a game.

Keep the character's identity exactly:
- dark navy ninja hood with the knot tails sticking out on the left side of the head
- dark navy mask covering the nose and mouth (the lower face stays hidden)
- gray forehead plate with three black diamond studs
- skin visible only around the eyes
- black ninja outfit with the net undershirt at the collar
- the sword hilt with the black-and-white wrapped grip sticking up behind the right shoulder

Style:
- the same flat cel-shaded look as the source: thick black outlines, flat colors, simple shading
- make it slightly cuter than the source: a bit bigger, rounder eyes and softer shapes, but do not change the design or colors

Composition (must be followed exactly, other expressions will be drawn on top of the same framing):
- square image, character facing the viewer (very slight three-quarter turn is fine), from the top of the head down to the upper chest
- head centered horizontally
- top of the head at about 8% from the top edge of the image
- eyes at about 42% from the top edge
- the upper chest is cut off by the bottom edge
- plain solid pure white background (#FFFFFF) with nothing else: no scenery, no floor shadow, no frame, no text, no signature

Expression: calm and neutral (eyes open, relaxed brows).

After the image is generated, copy the generated PNG file into the current working directory as tsujo.png (look in ~/.codex/generated_images for the newest file if needed). Reply with the path of the saved file.
```

### 残りの表情のプロンプト

刃のときの全文。覆面で口元が隠れるキャラクター向けに、目と眉と漫符で表情を出す。
口元の見えるキャラクターは、口の形も変えてよいと書き足す。

```text
Use your image generation tool to create FOUR more dialogue portraits of the same ninja, one image per expression, by editing the attached base portrait tsujo.png (source.jpg is the original character art for reference).

Every image must keep exactly the same framing, size, position, outfit, colors, line style and plain pure white background (#FFFFFF) as tsujo.png. Change ONLY the eyes, the eyebrows drawn on the skin above the eyes, and small manga symbols near the head. The mask always keeps covering the nose and mouth. No text, no frame, no scenery.

1. ikari.png (angry): sharp narrowed eyes, brows slanted down toward the center, a small red anger mark (cross-shaped vein) on the hood near the forehead plate
2. odoroki.png (surprised): wide round eyes with small pupils, brows raised high, one small blue sweat drop beside the head
3. yorokobi.png (happy): eyes closed in happy arcs like ^ ^, light pink blush on the skin under the eyes
4. kumon.png (pained, anguished): eyes squeezed shut like > <, brows tilted up toward the center, two small blue sweat drops

After each image is generated, copy the generated PNG into the current working directory with the file name above (look in ~/.codex/generated_images for the newest files if needed). Reply with the list of saved paths.
```

## キャラクターごとの特徴の行

通常のプロンプトの「Keep the character's identity exactly」の行と、表情の書き分けの違いを、キャラクターごとに残す。
元画像は NINJAMCP の画像（括弧内は ID）。

### 酉花（#012）

```text
- short dusty rose (reddish pink) bob hair with spiky ends and bangs over the forehead
- black headband with the knot tails sticking out on the left side of the head (left side of the image)
- gray forehead plate shaped like two downward-pointing triangles, each with one black diamond stud
- pinkish violet eyes, two tiny dark beauty marks under the eyes, soft pink blush on the cheeks
- the face is NOT masked: the mouth is visible
- black short-sleeved ninja top with gold stripes on the shoulders, a gold diagonal line along the crossed collar, and a small gold cross mark on the chest
- the sword hilt with the black-and-white wrapped grip and gold end sticking up behind the shoulder on the right side of the image
```

口元が見えるので、残りの表情では口の形も変える（怒りは歯を食いしばって叫ぶ、驚きは丸く開ける、喜びは大きく開けて笑う、苦悶は波線で食いしばる）。

### 石舟斎（#038）

```text
- spiky black hair gathered into a tall spiky topknot, with an orange hair tie
- a white streak in the front bangs, falling over the right side of the image
- sharp orange-amber eyes with dark brows
- a small black goatee on the chin; the face is NOT masked, the mouth is visible
- black kimono coat (haori) with a stiff white stand-up collar, gray crest marks on the shoulder and red flame patterns on the sleeves
- black inner kimono crossed at the chest
```

通常の表情は、元画像に合わせて自信のある小さな笑みにした。喜びは元画像の大きく開けた笑い。

### 金鬼（#005）

```text
- a red oni (demon) mask covers the whole face: two ivory horns on the forehead, thick angry brows carved on the mask, a big nose, a wide mouth with gray-white fangs and teeth
- the eyes seen through the mask: round pale yellow eyes with small glowing red pupils
- dark teal ninja hood over the head
- the mask is tied with a red-brown cloth band whose knot tails stick out on the left side of the head (left side of the image)
- shaggy light brown fur collar over both shoulders
- net undershirt at the neck, dark teal ninja outfit, a tan rope tied at the chest
```

鬼の面は形を変えず、面の穴から見える目と、その上の彫りの眉と、漫符だけで表情を出す。
怒りは湯気、喜びはきらめきを足した。

### ハヤテ（#014）

```text
- messy dark gray spiky hair swept to the side
- golden yellow eyes with sharp brows
- a thin scar on the cheek under the eye on the right side of the image
- dark navy mask covering the nose and mouth (the lower face stays hidden)
- navy blue ninja outfit with the net undershirt at the collar and a small gray four-pointed star mark on the chest
- the sword hilt with the black-and-white wrapped grip and gold end sticking up behind the shoulder on the right side of the image
- his brown hawk partner "Narukami" (brown feathers, gray chest, yellow beak and eyes) perched on his shoulder on the left side of the image, small enough that the whole hawk fits inside the image and does not cover his face
```

相棒の鷹ナルカミを肩に乗せ、表情に合わせて鷹の目と翼も少し変える（怒りは翼を広げてにらむ、驚きは驚く、喜びは落ち着く、苦悶は心配そうにする）。

