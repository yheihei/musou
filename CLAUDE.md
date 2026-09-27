# musou

三国無双ライクな Roblox ゲーム。Rojo でソースを管理している。

## コマンド

- `rojo serve` Studio と同期（Studio 側で Rojo → Connect）
- `stylua src` フォーマット
- `selene src` Lint
- `rojo build -o musou.rbxl` ビルド確認

変更後は stylua → selene → rojo build の順に通すこと。CI も同じ内容。

## 規約

- 言語は Luau。拡張子は `.luau`、ファイル先頭に `--!strict`
- 数値バランスは `src/shared/Config.luau` にだけ書く
- ゲームロジックはサーバー権威。クライアントは入力と表示だけを担当する
- RemoteEvent は `default.project.json` の ReplicatedStorage.Remotes に宣言する
- Studio で直接編集した内容は Git に残らない。必ず `src/` を編集する
