# musou

三国無双ライクな Roblox ゲーム。Rojo でソースを管理している。

## コマンド

- `rojo serve` Studio と同期（Studio 側で Rojo → Connect）
- `stylua src` フォーマット（`.lune` を触ったときは `stylua .lune` も）
- `selene src` Lint
- `lune run test` 単体テスト（`src/shared` の `*.spec.luau`）
- `rojo build -o musou.rbxl` ビルド確認

変更後は stylua → selene → lune → rojo build の順に通すこと。CI も同じ内容。

## 規約

- 言語は Luau。拡張子は `.luau`、ファイル先頭に `--!strict`
- 数値バランスは `src/shared/Config.luau` にだけ書く
- Roblox に依存しない計算は `src/shared` に置き、同じ場所の `*.spec.luau` で Lune のテストを書く
- `src/shared` の中の `require` は文字列のパス（`require("./Config")`）で書く。Lune のテストからも読むため
- ゲームロジックはサーバー権威。クライアントは入力と表示だけを担当する
- RemoteEvent は `default.project.json` の ReplicatedStorage.Remotes に宣言する
- Studio で直接編集した内容は Git に残らない。必ず `src/` を編集する
