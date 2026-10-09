# musou

三国無双ライクな Roblox ゲーム。Rojo でソースを管理している。

## コマンド

- `rojo serve` Studio と同期（反映を頼まれたときだけ。Studio 側で Rojo → Connect）
- `stylua src` フォーマット（`.lune` を触ったときは `stylua .lune` も）
- `selene src` Lint
- `lune run test` 単体テスト（`src/shared` の `*.spec.luau`）
- `rojo build -o musou.rbxl` ビルド確認

変更後は stylua → selene → lune → rojo build の順に通すこと。CI も同じ内容。

## Studio

- 作業の最初に `rojo serve` を起動しない（起動は `src/` の反映を頼まれたときだけ）
- 作業の最初に `lsof -nP -iTCP:34872` で ESTABLISHED を確かめる（接続済みなら、保存した時点で Edit に同期される）
- Connect は人間が Studio で押す（プラグインは自動では接続しない）
- 確認は、Rojo で同期したプレースのテストプレイ（`start_stop_play`）で行う。Rojo が接続していなければ確認を残し、手順を issue に書く
- 確認用コマンドは、`execute_luau`（Server）で `ServerStorage.DebugCommand` の Attribute `Request` に命令を書いて呼び、次の呼び出しで `Response` を読む（README「テスト用のサーバーコマンド」）
- `execute_luau` からは、窓口の `Invoke`、Remote の送信、スクリプトの付け替えができない（2026-10-02 から Capabilities で拒否）
- 編集中のプレース（Edit）にスクリプトを書き込まない（Team Create のため、クラウドに保存される）
- `list_roblox_studios` の name が null なら、プレースは開いていない（スタート画面）

## 規約

- 言語は Luau。拡張子は `.luau`、ファイル先頭に `--!strict`
- 数値バランスは `src/shared/Config.luau` にだけ書く
- Roblox に依存しない計算は `src/shared` に置き、同じ場所の `*.spec.luau` で Lune のテストを書く
- `src/shared` の中の `require` は文字列のパス（`require("./Config")`）で書く。Lune のテストからも読むため
- ゲームロジックはサーバー権威。クライアントは入力と表示だけを担当する
- RemoteEvent は `default.project.json` の ReplicatedStorage.Remotes に宣言する
- Studio で直接編集した内容は Git に残らない。必ず `src/` を編集する
- マップ（ロビー・区画・地形・建物・目印）はプレースで管理し、Git に残らない。`default.project.json` の Workspace に足さない。目印の形式は ADR 0006

## Git

- `main` に直接 commit・push する。PR は作らない
- `main` のブランチ保護を越える push の警告（Bypassed rule violations）は承知の上なので、そのまま push してよい
- 依頼がなければ作業用ブランチを新設せず、既存の作業ブランチも勝手に切り替えない
- commit message は日本語。関連 issue がある場合は `#issue番号` を含める
- 本人から依頼された musou 開発は、テスト、ローカル commit、作業ブランチへの通常 push まで進めてよい
- 無関係な既存差分を巻き込まない
- `main` への merge、公開・配信、force push、支払い、認証・権限変更、復元不能な削除は別承認
- 完了報告では、ローカルのテスト・該当 SHA の CI・Studio・多人・スマホ実機の確認範囲を区別する
