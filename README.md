# musou

三国無双ライクな Roblox アクションゲーム。
大量の下忍をコンボでなぎ倒し、奥義ゲージを溜めて奥義を放つ。

## 遊び方

- 左クリック（長押し可）: 通常攻撃。最大 4 段コンボ
- E: チャージ攻撃。周囲を吹き飛ばす
- Q: 奥義。奥義ゲージが満タンのときだけ出せ、発動中は無敵

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
    Services/  PlayerService / EnemyService / CombatService
    Combat/    当たり判定と仮エフェクト
  client/   StarterPlayerScripts.Client 入力と HUD
.lune/      Lune のスクリプト（test.luau がテストの実行、lib/testkit.luau が test と expect）
default.project.json  Rojo のインスタンスツリー定義（Remotes・ServerStorage.DebugCommand・地形もここ）
```

## 設計メモ

- クライアントは Remotes.Action で「攻撃したい」だけを送る。クールダウン・コンボ・当たり判定はサーバーが決める
- 撃破数と奥義ゲージは Player の Attribute（`Gekihasu`・`OugiGauge`）に持たせ、HUD はその変更を購読する
- 数値調整は `src/shared/Config.luau` に集約している
