# musou

三国無双ライクな Roblox アクションゲーム。
大量の下忍をコンボでなぎ倒し、奥義ゲージを溜めて奥義を放つ。

## 遊び方

PC とゲームパッドで遊ぶ。割り当ては `src/shared/InputMap.luau` の対応表にある。

| 操作 | PC | ゲームパッド |
|---|---|---|
| 通常攻撃（長押しで連続）。最大 6 段コンボで、段の中身は武器種ごとに違う | 左クリック・Z | X |
| チャージ攻撃。それまでの通常攻撃の段数で C1〜C6 に変わる | 右クリック・X・E | Y |
| ジャンプ | Space | A |
| ガード（ガード中に方向を入れると緊急回避） | Shift | L1 |
| 奥義。奥義ゲージを1本使って出す（最大4本まで溜まる）。発動中は無敵。いまは刃の火遁だけ | Q | B |
| 秘計 | 1〜3 | 十字キーの左・上・右 |

- 右ドラッグでカメラを回す。右クリックは、ドラッグせずに離したときだけチャージ攻撃になる
- Studio のテストプレイでマウスのクリックがタッチとして届く環境では、Z と X で攻撃する
- ガード中は動けず、向きも変わらない。正面からの攻撃は被ダメージ 0、背後と側面からは通常どおり受ける
- 緊急回避はガード中に方向を入れた向きへ動き、動き出しは無敵。続けて出すほど後隙が伸びる
- 秘計は、入力をサーバーへ送るところまで。効果はまだ無い

## 開発環境

ソースは Rojo で管理し、Roblox Studio へ同期する。
Studio 上で直接スクリプトを編集しても Git には残らないので、必ず `src/` を編集する。

### ツールのインストール

[Rokit](https://github.com/rojo-rbx/rokit) でバージョンを固定している。

```bash
rokit install
```

Homebrew で入れる場合は `brew install rojo selene stylua lune`（バージョンは `rokit.toml` に合わせる）。

### Studio と同期する

1. Rojo プラグインを Studio に入れる（初回のみ）

   ```bash
   rojo plugin install
   ```

2. 同期サーバーを起動する

   ```bash
   rojo serve
   ```

3. Studio でプレースを開き、プラグインタブの Rojo → Connect を押す

### Lint・フォーマット・テスト・ビルド

```bash
stylua src
selene src
lune run test
rojo build -o musou.rbxl
```

`.lune` を触ったときは `stylua .lune` も通す。
CI（`.github/workflows/ci.yml`）で同じチェックを main への push ごとに実行する。

### 単体テスト

Roblox に依存しない計算は `src/shared` に置き、[Lune](https://lune-org.github.io/docs) でテストする。

- テストは対象と同じ場所に `*.spec.luau` で置く（`Actions.luau` なら `Actions.spec.luau`）
- spec は `default.project.json` の `globIgnorePaths` で同期とビルドから外している
- `test` と `expect` は `require("@testkit")` で読む（中身は `.lune/lib/testkit.luau`）
- `expect` で使えるのは `toBe`・`toEqual`・`toBeNear`・`toThrow`
- `src/shared` の中の `require` は文字列のパス（`require("./Config")`）で書く
- 文字列のパスは Roblox と Lune のどちらでも同じモジュールを指す
- `lune run test Actions` のように引数を渡すと、パスにその文字列を含む spec だけを実行する

```lua
--!strict
local Actions = require("./Actions")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

test("定義にない文字列は拒否する", function()
	expect(Actions.isValid("Jump")).toBe(false)
end)
```

### テスト用のサーバーコマンド

動いているサーバーのサービスを、`ServerStorage.DebugCommand`（BindableFunction）から操作できる。
Studio MCP の `execute_luau`（Server）、テストプレイ中のコマンドバー、公開サーバーの開発者コンソールのサーバーのコマンドから呼ぶ。
`ServerStorage` はクライアントへ複製されず、公開サーバーの開発者コンソールでサーバーのコマンドを実行できるのは所有者だけ。

```lua
local DebugCommand = game:GetService("ServerStorage").DebugCommand
print(DebugCommand:Invoke("Help")) -- 登録済みのコマンドの一覧
print(DebugCommand:Invoke("SetOugiGauge", "Player1", 100))
```

- 未登録の名前を渡すと、登録済みのコマンドの一覧が返る
- コマンドが失敗したときは、エラーを投げずに失敗の内容を文字列で返す
- プレイヤーは名前（`Player.Name`）で指定する

コマンドは各サービスが `DebugCommand.register(名前, 引数の説明, 説明, 関数)` で登録する（`src/server/DebugCommand.luau`）。

- 名前は動詞から始める PascalCase にする（`SetOugiGauge`、`DumpParty`）
- Remote と同じ処理を呼ぶコマンドは、Remote と同じ名前にする（`SelectStage`、`Shutsugeki`）
- プレイヤーを対象にするコマンドは、1つ目の引数をプレイヤーの名前にする
- 戻り値は、何をしたかが読める文字列か、`HttpService:JSONEncode` で文字列にできる表にする

## ディレクトリ構成

```
src/
  shared/   ReplicatedStorage.Shared    サーバー・クライアント共通（Config など）
  server/   ServerScriptService.Server  ゲームロジック本体
    DebugCommand  テスト用のサーバーコマンドの窓口
    Services/  KukakuService / HaichiService / PartyService / ProgressService / SelectionService / StageService / SerifuService / PlayerService / ActionService / DamageService / EnemyService / CombatService
      KukakuService  ロビーと区画（Workspace.Lobby・Workspace.Stages）の目印の取得と、欠けたときの警告
      HaichiService  ステージの配置（拠点・つながり・部隊・首領）を構成と目印から読み込む。試験用ステージの目印を作る
      ProgressService  プレイヤーごとの進行（開放済みとクリア済みのステージ）の DataStore への保存
      SelectionService  出撃前の選択（ステージ・キャラクター・秘計）の受け付けと PartyState への反映
      StageService  出撃からロビー帰還までのステージの進行（フェーズ、出撃地点への移動、イベントシーンの同期とスキップ、勝敗の結果）
      SerifuService  戦闘中の台詞を全員の画面の端に出す
      ActionService  行動の状態遷移（入力、先行入力、被弾による中断）
      DamageService  プレイヤーの被ダメージの窓口
      CombatService  攻撃の中身と当たり判定
    Combat/    当たり判定と仮エフェクト
  client/   StarterPlayerScripts.Client 入力・HUD・モーションの再生・画面
    Selection/  出撃前の画面（ステージ・キャラクター・秘計の選択と出撃ボタン）の欄
    Dialogue    イベントシーンの会話窓
assets/
  weapons/  武器の仮のモデル（Rojo の JSON モデル）。ReplicatedStorage.Weapons に置く
.lune/      Lune のスクリプト（test.luau がテストの実行、lib/testkit.luau が test と expect）
default.project.json  Rojo のインスタンスツリー定義（Remotes・ServerStorage.DebugCommand もここ）
```

マップ（ロビー・区画・地形・建物・目印）は Rojo の管理外で、プレースに保存する。Git には残らない。
ロビーは `Workspace.Lobby`、区画は `Workspace.Stages` の下に置き、目印の形式は [ADR 0006](docs/adr/0006-positions-as-markers-composition-in-code.md) に従う。
`default.project.json` の Workspace にはパーツを足さない。

## 設計メモ

- クライアントは Remotes.Action で「攻撃したい」だけを送る。クールダウン・コンボ・当たり判定はサーバーが決める
- プレイヤーへのダメージは DamageService.damage（攻撃元の位置・威力・反応の種類）を通す。無敵・防御の軽減・のけぞりとダウン・奥義ゲージの増加はそこで決まる
- 行動の種類と引数の検証は `src/shared/Actions.luau` にあり、不正な値はサーバーが捨てる
- 撃破数と奥義ゲージは Player の Attribute（`Gekihasu`、本数の `OugiStock`、次の1本までの量の `OugiGauge`）に持たせ、HUD はその変更を購読する
- 数値調整は `src/shared/Config.luau` に集約している
- ステージの配置は、構成（拠点の種類と軍、つながり、部隊）を `src/shared/Haichi.luau` に、位置をプレースの目印に置く（ADR 0006）。試験用ステージ `Test` は目印の位置もコードに持ち、テストプレイ中に目印を作る。窓口の `Shutsugeki <プレイヤー名> Test` で出撃し、`DumpHaichi Test` で読み込んだ配置を見る
- ステージの進行は StageService が持つ。フェーズはロビー → 開始のイベントシーン → 戦闘 → 終了のイベントシーン → リザルト → ロビーの順に進み、遷移は `src/shared/StagePhase.luau` が決める。ほかのサービスは `StageService.started`・`finished`・`phaseChanged` を受けて、始める処理と片付けをする
- イベントシーンは、サーバーが出撃メンバーに `PlayEventScene` で流し、長さが過ぎるか全員がスキップを押すと次のフェーズへ進める。シーンの ID と長さは `src/shared/EventScenes.luau`、スキップの集計は `src/shared/SkipVote.luau` にある。窓口の `StartEventScene Shiken` で、試験用のシーンを流して出撃する
- 進行は DataStore に UserId ごとに保存し、保存済みの記録と和集合にして書く（計算は `src/shared/Progress.luau`）。Studio のテストプレイは本番と別の DataStore（`ProgressStudio`）を使う。DataStore を使えないとき（Studio から API サービスへのアクセスを許していないときなど）は、警告を出してサーバーのメモリにだけ保存する
- 効果音は `src/shared/Sounds.luau` の登録表に置き、`src/shared/SoundPlayer.luau` で名前を指定して鳴らす。戦闘の音はサーバーが場所を指定して鳴らし、画面の音はクライアントが本人にだけ鳴らす。音量は `Config.luau` の Sound 節
- 武器は `src/shared/Appearance.luau` が、キャラクター定義の武器のモデルを右手の握りの Attachment に溶接して持たせる。見た目専用で、当たり判定は持たない
- モーションの ID は `src/shared/Motions.luau` の一覧に置く。待機と移動は Roblox 公式の Ninja パックで、仮の見た目の HumanoidDescription に入れて当てる
- 行動のモーションは、クライアントの MotionController が自分のキャラクターの Attribute（`Action`・`ActionStep`・`ActionDuration`・`ActionStartedAt`）を見て、行動の長さに合わせた速さで再生する。判定の時刻と移動量は `Config.luau` のままで、モーションには左右されない
