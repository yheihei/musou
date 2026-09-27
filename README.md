# musou

三国無双ライクな Roblox アクションゲーム。
大量の雑兵をコンボでなぎ倒し、ゲージを溜めて無双乱舞を放つ。

## 遊び方

- 左クリック（長押し可）: 通常攻撃。最大 4 段コンボ
- E: チャージ攻撃。周囲を吹き飛ばす
- Q: 無双乱舞。ゲージ満タン時のみ、発動中は無敵

## 開発環境

ソースは Rojo で管理し、Roblox Studio へ同期する。
Studio 上で直接スクリプトを編集しても Git には残らないので、必ず `src/` を編集する。

### ツールのインストール

[Rokit](https://github.com/rojo-rbx/rokit) でバージョンを固定している。

```bash
rokit install
```

Homebrew で入れる場合は `brew install rojo selene stylua`（バージョンは `rokit.toml` に合わせる）。

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

### Lint・フォーマット・ビルド

```bash
stylua src
selene src
rojo build -o musou.rbxl
```

CI（`.github/workflows/ci.yml`）で同じチェックを PR ごとに実行する。

## ディレクトリ構成

```
src/
  shared/   ReplicatedStorage.Shared    サーバー・クライアント共通（Config など）
  server/   ServerScriptService.Server  ゲームロジック本体
    Services/  PlayerService / EnemyService / CombatService
    Combat/    当たり判定と仮エフェクト
  client/   StarterPlayerScripts.Client 入力と HUD
default.project.json  Rojo のインスタンスツリー定義（Remotes・地形もここ）
```

## 設計メモ

- クライアントは Remotes.Action で「攻撃したい」だけを送る。クールダウン・コンボ・当たり判定はサーバーが決める
- KO 数と無双ゲージは Player の Attribute に持たせ、HUD はその変更を購読する
- 数値調整は `src/shared/Config.luau` に集約している
