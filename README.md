# musou

三国無双ライクな Roblox アクションゲーム。
大量の下忍をコンボでなぎ倒し、奥義ゲージを溜めて奥義を放つ。

## 遊び方

PC・ゲームパッド・スマホ（横画面）で遊ぶ。割り当ては `src/shared/InputMap.luau` の対応表にある（スマホの操作ボタンは `src/client/Controllers/TouchControlsController.luau`）。

| 操作 | PC | ゲームパッド | スマホ |
|---|---|---|---|
| 通常攻撃（長押しで連続）。最大 6 段コンボで、段の中身は武器種ごとに違う | 左クリック・Z | X | 攻撃 |
| チャージ攻撃。それまでの通常攻撃の段数で C1〜C6 に変わる | 右クリック・X・E | Y | チャージ |
| ジャンプ | Space | A | 標準のジャンプボタン |
| ガード（ガード中に方向を入れると緊急回避） | Shift | L1 | ガード（ガード中にサムスティックを倒すと緊急回避） |
| 奥義。奥義ゲージを1本使って出す（最大4本まで溜まる）。発動中は無敵。刃の火遁、酉花の毒手裏剣、石舟斎の無刀取り、金鬼の金遁がある | Q | B | 奥義（右上の数がストックの本数） |
| 秘計 | 1〜3 | 十字キーの左・上・右 | 左上の秘計の枚 |

- 右ドラッグでカメラを回す。右クリックは、ドラッグせずに離したときだけチャージ攻撃になる
- スマホでは、移動は Roblox 標準のサムスティック、ジャンプは標準のジャンプボタンを使う。操作ボタンは戦闘中だけ、右下（秘計の枚は左上）に出る
- Studio のテストプレイでマウスのクリックがタッチとして届く環境では、Z と X で攻撃する
- ガード中は動けず、向きも変わらない。正面からの攻撃は被ダメージ 0、背後と側面からは通常どおり受ける
- 緊急回避はガード中に方向を入れた向きへ動き、動き出しは無敵。続けて出すほど後隙が伸びる
- 秘計は、持ち込んだ枚を1戦に1回ずつ使える。伏兵・落石・大火計・兵糧庫・爆破罠・挑発・鬼神化・大喝の8種がある
- 秘計は系統（武勇・知略・堅牢）ごとの熟練度で覚える。熟練度は撃破・拠点の制圧・救援で上がり、出撃前に選べるのは覚えた秘計だけ

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
テストプレイ中のコマンドバー（サーバー表示）か、公開サーバーの開発者コンソールのサーバーのコマンドから呼ぶ。
`ServerStorage` はクライアントへ複製されず、公開サーバーの開発者コンソールでサーバーのコマンドを実行できるのは所有者だけ。

```lua
local DebugCommand = game:GetService("ServerStorage").DebugCommand
print(DebugCommand:Invoke("Help")) -- 登録済みのコマンドの一覧
print(DebugCommand:Invoke("SetOugiGauge", "Player1", 100))
```

- 未登録の名前を渡すと、登録済みのコマンドの一覧が返る
- コマンドが失敗したときは、エラーを投げずに失敗の内容を文字列で返す
- プレイヤーは名前（`Player.Name`）で指定する。Studio のテストプレイでは自分のユーザー名になる

Studio MCP の `execute_luau` は `Invoke` を呼べない（2026-10-02 から Capabilities で拒否される）。
そのため Studio では、`ServerStorage.DebugCommand` の Attribute `Request` に命令を書くと、サーバーが窓口を呼んで結果を `Response` に書く。

```lua
-- execute_luau（Server）の1回目で命令を書く
local HttpService = game:GetService("HttpService")
local DebugCommand = game:GetService("ServerStorage").DebugCommand
DebugCommand:SetAttribute("Request", HttpService:JSONEncode({ id = "1", args = { "DumpParty" } }))
```

```lua
-- 2回目で結果を読む（{"id":"1","results":[...]}）
return game:GetService("ServerStorage").DebugCommand:GetAttribute("Response")
```

- 入口は Studio だけで受け付ける
- `execute_luau` の中で結果を待つとタイムアウトするので、書く呼び出しと読む呼び出しを分ける
- 命令は1つずつ書き、`Response` の `id` が変わってから次を書く

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
    CollisionGroups  キャラクターの物理の衝突のグループ（敵はプレイヤーにもほかの敵にもぶつからない）
    PlayerStore  プレイヤーごとの記録を DataStore に保存する共通の部品（読み込みのやり直し、変更を保存済みの記録に当てて書く UpdateAsync、退室時と BindToClose の保存、DataStore を使えないときのメモリ）。特技と秘計の熟練度の記録が使う
    Services/  KukakuService / HaichiService / PartyService / ProgressService / JukurendoService / SelectionService / TokugiService / StageService / ButaiService / KyotenService / HeitansenService / SaishutsugekiService / JoninService / JoninKotaiService / ShohaiService / ShihaiAreaService / HoshinService / MinimapService / SerifuService / PlayerService / ActionService / DamageService / CameraViewService / EnemyService / GeninKotaiService / CombatService / HikeiService / HyorokoService / RakusekiService / FukuheiService / KishinkaService / DaikatsuService / DaikakeiService / BakuhawanaService / ChohatsuService / HikeiHandanService
      KukakuService  ロビーと区画（Workspace.Lobby・Workspace.Stages）の目印の取得と、欠けたときの警告
      HaichiService  ステージの配置（拠点・つながり・部隊・首領）を構成と目印から読み込む。試験用ステージの目印を作る
      ProgressService  プレイヤーごとの進行（開放済みとクリア済みのステージ）の DataStore への保存
      JukurendoService  秘計の系統ごとの熟練度と覚えた秘計の保存（PlayerStore）、決着したときの熟練度、M1 から遊ぶ人の扱い
      SelectionService  出撃前の選択（ストーリー・ステージ・キャラクター・秘計）の受け付けと PartyState への反映。秘計は覚えた秘計だけ
      TokugiService  特技ツリーによる成長。キャラクターごとの巻物と覚えた特技の保存（PlayerStore）、覚える要求の検証、出撃したときの補正の固定、決着したときの巻物
      StageService  出撃からロビー帰還までのステージの進行（フェーズ、出撃地点への移動、イベントシーンの同期とスキップ、勝敗の結果）
      ButaiService  戦場の部隊のデータ（位置・兵数・士気）と部隊どうしの交戦。配置から作り、目的地へ位置だけを進め、ReplicatedStorage.Butai の Attribute で複製する
      KyotenService  戦場の拠点の耐久と所属と守備。範囲の中で拠点の軍の下忍が倒れると耐久を減らし、0 で相手の軍に制圧させる。守備を補充し、守備のいない拠点は攻める軍がいる間に耐久を減らす。プレイヤーの制圧数と救援数を数える。ReplicatedStorage.Kyoten の Attribute で複製する
      HeitansenService  兵站線と孤立。拠点の所属とつながりから軍ごとの兵站線を求め直し、孤立した拠点の補充を止める。つながりを通れなくする API と、孤立しない拠点の指定の API と、兵站線の末端の拠点かを引く API を持つ。ReplicatedStorage.Tsunagari の Attribute で複製する
      SaishutsugekiService  兵力と再出撃。倒れた出撃メンバーを兵站線につながった最寄りの味方の拠点から再出撃させ、兵力を1使う。兵力0で倒れたら heiryokuZero で知らせる
      JoninService  上忍と首領のデータ（能力値・体力・率いる部隊）と被ダメージの受け口。上忍は部隊とともに動き（目的地を差し替えると部隊を離れて歩く）、首領は本陣にとどまる。ReplicatedStorage.Jonin の Attribute で複製する
      JoninKotaiService  実体化圏で上忍と首領（両軍）の個体を出し入れする。個体は名札と体力バーを付け、データの位置と体力に合わせる。敵軍の個体は出撃メンバーを、味方軍の個体は敵の下忍を狙い、予備動作の後に型を出して戦う
      ShohaiService  勝敗の判定。首領の撃破・本陣の制圧・兵力0で倒れたことを受け、同じ再開の中で起きた条件をまとめて判定してステージを終える（同時なら負けを優先）
      HoshinService  上忍が部隊を率いて、配置で決めた方針（攻略・防衛・救援）に沿って部隊の目的地を決める
      MinimapService  ミニマップに出す区画の範囲と、出撃メンバーの位置と向きを Attribute で複製する
      ShihaiAreaService  支配エリア。兵站線につながった拠点の周りを支配エリアとし、その軍の部隊の交戦の押す力と、上忍と首領の攻撃と防御を上げる。ReplicatedStorage.ShihaiArea の Attribute で複製する
      SerifuService  戦闘中の台詞を全員の画面の端に出す
      HikeiService  秘計の発動の入口（持ち込み・使用記録・効果の時間管理）。秘計ごとの処理は各サービスが register で登録する。敵軍の上忍と首領の持ち込みは配置の構成から決める
      HyorokoService  秘計の兵糧庫。中にいる味方の通常拠点を、兵站線が切れても孤立しない拠点にする
      RakusekiService  秘計の落石。近くの落石地点に岩を落とし、その区間を相手の軍にとって通れなくする
      FukuheiService  秘計の伏兵。足元に伏兵部隊を潜ませ、近づいた相手を奇襲して士気を下げる
      KishinkaService  秘計の鬼神化。発動者の攻撃と防御を上げ、のけぞらなくする
      DaikatsuService  秘計の大喝。周りの相手の強化の秘計を打ち消し、相手を動揺させる
      DaikakeiService  秘計の大火計。近くの大火計地域に火を放ち、地域の中の相手にまとめてダメージを与える
      BakuhawanaService  秘計の爆破罠。中にいる味方の拠点に罠を仕掛け、耐久が3分の1を下回ったら爆発させて拠点の中の相手を吹き飛ばす
      ChohatsuService  秘計の挑発。周りの相手の上忍を、効果時間の間、発動者のもとへ誘い出して部隊から引き離す
      HikeiHandanService  秘計の判断。敵軍の上忍と首領が、戦場の様子を見て持ち込んだ秘計を使う（味方軍は使わない）
      ActionService  行動の状態遷移（入力、先行入力、被弾による中断）
      DamageService  プレイヤーの被ダメージの窓口
      CameraViewService  クライアントが送るカメラ（視界）の検証と保持。下忍を出撃メンバーの視界の外に出すために引く
      EnemyService  敵の下忍（と窓口で出した上忍）の体（Humanoid）・動き・攻撃トークン・被ダメージ。描き方が変わったらここを差し替える
      GeninKotaiService  実体化圏で敵軍の部隊の下忍を個体として出し入れする。部隊ごとの個体の数（兵数からの借り出しと返却）、撃破での兵数の減少、全体の上限
      CombatService  攻撃の中身と当たり判定
    Combat/    当たり判定・攻撃を受けた個体の反応（Hanno）・仮エフェクト
  client/   StarterPlayerScripts.Client 入力・HUD・モーションの再生・画面・BGM
    Selection/  出撃前の画面（ストーリーとステージ・キャラクター・特技・秘計の選択と出撃ボタン）の欄と、そこから開く窓（特技ツリー）
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
- 敵（下忍の個体と窓口で出した敵）と、両軍の上忍・首領の個体は、体ではプレイヤーにもほかの個体にもぶつからない（`src/server/CollisionGroups.luau` の衝突のグループ。敵軍は Enemy、味方軍は Mikatagun）。敵は近づいて攻撃するだけである。敵が上に積み重なってプレイヤーが動けなくなるのを防ぐ。重ならないよう、敵はプレイヤーの手前（`Config.luau` の EnemyAI 節の `PlayerGap`）で止まり、ほかの敵とも離れて囲む（立ち位置の計算は `src/shared/EnemySpacing.luau`）。攻撃の当たりは計算で決めるので影響しない
- 敵軍の部隊の下忍は、実体化圏で個体として出し入れする（GeninKotaiService。数の計算は `src/shared/GeninKotai.luau`、数値は `Config.luau` の GeninKotai 節、半径は Jittaikaken 節）。体はサーバーの Humanoid（#15 の案A。描き方は #15 で決める）で、体の生成・消去・動き・被ダメージは EnemyService が持つ。兵数は部隊の下忍の全体の数のままで、個体はそのうちの何人かを姿として出したもの（借り出し）。個体の数は兵数を超えず、消した個体は部隊に戻る（兵数は変わらない）。個体が倒れたら（倒した人によらず）兵数を1減らし（`EnemyService.kotaiDefeated`）、拠点の耐久にも数える（爆破罠のとどめは数えない）。部隊が出撃メンバーの誰かから AppearRadius 以内に入ったら出す対象にし、全員から DisappearRadius より離れるまで残す。サーバー全体の上限 MaxKotai（パーティー全体で 40 体）を、近いメンバーのまとまりごとに人数の比で分け（KotaiHaibun）、まとまりの中の部隊へ兵数の比で分けた数を目標にする。目標より多い部隊は遠い個体から戻し、足りない部隊には部隊の位置の周り（Spread の円の中）に、1回の判断で MaxPerTick 体まで出す。交戦で兵数が個体の数より少なくなったら多い分をすぐに戻し、部隊がいなくなったら個体を消す。体の色は敵軍のクランの色。戦う相手（EnemyAI 節の AggroRange 以内のプレイヤー）がいない個体は、部隊の位置の周りの自分の位置へ戻り、部隊について歩く。大火計と爆破罠は、部隊の兵数の割合を個体として出ていない分にだけ掛け、個体は1体ずつダメージで倒す（二重に数えない）。窓口の `DumpGeninKotai`（部隊ごとの兵数・個体の数・目標）・`DumpKotaiHaibun`・`SetSpawning`（出し入れを止める）・`ClearEnemies`（個体を部隊へ戻す）・`LogSpawn` で確かめる
- 下忍の個体の出し入れは、出撃メンバーの視界の外で行う（#81）。クライアントは戦闘の間、カメラの位置・向き・縦の画角・画面の横と縦の比を `Remotes.ReportCameraView` で送り（`src/client/Controllers/CameraViewController.luau`、間隔は `Config.luau` の CameraView 節の Interval）、サーバーの CameraViewService が検証して持つ（判定は `src/shared/CameraView.luau`）。型・有限の値・向きの長さ・画角と比の範囲が合わない値と、キャラクターから MaxDistance より遠いカメラは捨てる。最後に届いてから Stale 秒を過ぎたら、キャラクターの頭の高さから体の向きを見ているとみなす。倒れた人も、体が残っている間は視界に数える。カメラから FarDistance より遠い位置は見えないとみなす。個体を出し入れする位置（地面の高さ）の周りの半径 GeninKotai 節の ViewMargin が誰かの視界にかかれば、その位置では出し入れしない。ただし、出撃メンバー全員から PopDistance より遠い位置（実体化圏の縁の遠く）なら、視界の中でも出し入れする。出せる位置が無ければ次の判断まで見送る。窓口の `DumpCameraView`・`CheckCameraView`（8方向の地点が視界にかかるか）・`LogSpawn` で確かめる
- 下忍の個体の上限（`Config.luau` の GeninKotai 節の MaxKotai）は、近い出撃メンバーのまとまりごとに人数の比で分ける（#85。計算は `src/shared/KotaiHaibun.luau`、距離は KotaiHaibun 節）。GroupDistance 以内のメンバーをたどってつないだものを1つのまとまりにする。離れた4人なら 1/4 ずつ、4人が1か所なら全部を1つのまとまりに使う。部隊は一番近いメンバーのまとまりに数え、まとまりの配分は近くの部隊の兵数の合計を超えず、余った分はほかのまとまりへ回す。倒れているメンバーは配分に数えない。窓口の `DumpKotaiHaibun` で確かめる
- 敵の下忍（下忍の個体と窓口で出した下忍）は、狙うプレイヤーの攻撃トークン（計算は `src/shared/KogekiToken.luau`、数値は `Config.luau` の KogekiToken 節）を持つときだけ攻撃する。1人のプレイヤーの攻撃トークンは PerPlayer 個で、Range の内にいる下忍に近い順で渡す。持たない下忍は、攻撃する下忍より WaitGap だけ外で囲んで待つ。攻撃した下忍は攻撃トークンを返して Rest 秒休み、返した攻撃トークンは Interval 秒後に次の下忍へ渡る。倒れた下忍、吹き飛んで倒れている下忍、ほかのプレイヤーを狙った下忍、Range より離れた下忍も返す（すぐ次の下忍へ渡る）。受け取ってから MaxHold 秒たっても攻撃しない下忍は返して休む。攻撃する下忍は、待っている下忍を避けずに、Humanoid が目標の手前で止まる分（約 0.8 スタッド）だけ内側を目指し、攻撃が届く距離の内で止まる。上忍は攻撃トークンなしで攻撃する。窓口の `SpawnEnemies` で下忍を囲ませ、`DumpKogekiToken`・`LogKogekiToken`・`DefeatEnemy` と `DumpEnemies` の `token` で確かめる
- 攻撃を受けた敵（下忍の個体と窓口で出した敵と、上忍・首領の個体）の反応は `src/server/Combat/Hanno.luau` が決める（数値は `Config.luau` の EnemyReaction 節）。吹き飛びと打ち上げは物理演算に任せず、技の吹き飛ばす強さ（`Knockback`）から決めた初速と重力の軌道（`src/shared/Trajectory.luau`）で、HumanoidRootPart を固定してフレームごとに動かす。空中で受けた攻撃は軌道をやり直し（追撃で浮き直す）、足が地面（`Ground.raycast`）に届いたら仰向けに倒れ（ダウン）、しばらくして起き上がる。飛んでいる間は前のフレームの位置から光線を当て、壁や天井に当たったら面へ向かう速さを消して、面に沿って滑らせる（壁や屋根を通り抜けない。当たり判定の無い部品には当てない）。急な面には着地せず、5 秒たっても着地できなければその場に倒れる。地上でののけぞりは短く止まるだけ。上忍は反応を弱める倍率で短く飛び、のけぞらない。窓口の `DumpEnemies` で受けた攻撃の数（`hits`）と反応の状態（`hanno`）を確かめる。`SetEnemyAI false` で敵の動きと攻撃を止めると、決めた位置の敵に技を当てて確かめられる
- 奥義の中身は CombatService.registerOugi でキャラクター定義の `ougi` ごとに登録し、技（判定と時間）は `Config.luau` の Ougi 節の Timelines に置く。酉花の毒手裏剣は周りの12方向へ毒手裏剣を撒き、当てた敵を毒にする（`EnemyService.poison`、数値は `Config.luau` の Poison 節）。近くでは直線が重なるので、技の `HitOnce` で同じ時刻の判定を1体に1回だけ当てる。毒の間は間隔ごとにダメージを与え、とどめは酉花の撃破に数える。窓口の `DumpEnemies` の `poison`（毒の残り秒数）で確かめる。石舟斎の無刀取りは、周りを打ち上げてから高さのある円柱の判定で空中の敵を斬り続け（空中で当たるたびに浮き直す）、最後の一撃で吹き飛ばす。空中への斬撃の段数は Timelines.MutoDori の2つ目の判定の `Repeat` で、`DumpEnemies` の `hits` で数える。金鬼の金遁は、長い溜めの後、輪の判定（`HitShape` の Ring。内側と外側の半径の間に当たる）を内側から外へ広げて打ち上げ、最後の輪で周り全体を吹き飛ばす。`DumpEnemies` の `firstHitAgo`（最初に当たってからの秒数）で、内側の敵ほど先に当たったことを確かめる
- 撃破数・制圧数・救援数と奥義ゲージは Player の Attribute（`Gekihasu`・`Seiatsusu`・`Kyuensu`、本数の `OugiStock`、次の1本までの量の `OugiGauge`）に持たせ、HUD は撃破数と奥義ゲージの変更を購読する。どれも出撃したときに 0（奥義ゲージは初めの値）に戻す。窓口の `SetGekihasu`・`SetSeiatsusu`・`SetKyuensu` で書き換える
- 数値調整は `src/shared/Config.luau` に集約している
- ステージの配置は、構成（拠点の種類と軍、つながり、部隊、敵軍の上忍と首領の秘計の持ち込み）を `src/shared/Haichi.luau` に、位置をプレースの目印に置く（ADR 0006）。試験用ステージ `Test` は目印の位置もコードに持ち、テストプレイ中に目印を作る。窓口の `Shutsugeki <プレイヤー名> Test` で出撃し、`DumpHaichi Test` で読み込んだ配置を見る
- ステージの進行は StageService が持つ。フェーズはロビー → 開始のイベントシーン → 戦闘 → 終了のイベントシーン → リザルト → ロビーの順に進み、遷移は `src/shared/StagePhase.luau` が決める。ほかのサービスは `StageService.started`・`finished`・`phaseChanged` を受けて、始める処理と片付けをする
- 戦場の部隊は ButaiService がデータで持ち（ADR 0003）、目的地へ経由点をたどって位置だけを進める（計算は `src/shared/Butai.luau`）。クライアントは `ReplicatedStorage.Butai` の部隊ごとの Configuration の Attribute（`Position`・`Gun`・`Heisu`・`Shiki`・`Jonin`、交戦の相手の `Kosen`）を読む。窓口の `DumpButai`・`AddButai`・`MoveButai`・`SetButaiPosition`・`ShowButai`・`DumpKosen` で確かめる
- 拠点は KyotenService がデータで持つ（計算は `src/shared/Kyoten.luau`、耐久の値は `Config.luau` の Kyoten 節）。範囲の中でその拠点の軍の下忍が倒れると耐久が減り、0 で相手の軍が制圧する。減らすのは部隊の兵数の減少（`ButaiService.heisuLost`。下忍の個体の撃破も兵数を減らす）と、窓口で出した部隊に属さない下忍の撃破（`EnemyService.gekiha`）。クライアントは `ReplicatedStorage.Kyoten` の拠点ごとの Configuration の Attribute（`Gun`・`Taikyu`・`MaxTaikyu`・`Honjin`・`Position`・`Size`）を読む。窓口の `DumpKyoten`・`SetKyotenTaikyu`・`SetKyotenGun`・`ShowKyoten`・`DefeatEnemies` で確かめる
- 拠点の守備（範囲の中にいるその拠点の軍の部隊）は、耐久が残る間、`Config.luau` の Kyoten 節の上限まで間隔ごとに補充する。守備のいない拠点は、攻める軍（相手の軍の部隊と、敵軍の拠点では出撃したプレイヤー）が範囲の中にいる間に耐久が減る。制圧は拠点の陥落として `ShikiService.notify` で士気に知らせる。窓口の `RemoveButai` で守備を外して確かめる
- 兵站線は HeitansenService が、拠点の制圧・つながりを通れなくしたとき・戻したとき・孤立しない拠点の指定のたびに求め直す（計算は `src/shared/Heitansen.luau`）。孤立した拠点は守備を補充しない。落石は `HeitansenService.block`、兵糧庫は `setNeverIsolated` を使う。兵站線の末端（本陣でない拠点のうち、兵站線に入っているつながりが1本だけの拠点。判定は `Heitansen.isMattan`）は `HeitansenService.isMattan` で引く。クライアントは拠点の Attribute の `Koritsu`・`NeverIsolated` と、`ReplicatedStorage.Tsunagari` のつながりごとの Configuration の Attribute（`KyotenA`・`KyotenB`・`Heitansen`・`BlockedMikatagun`・`BlockedTekigun`）を読む。窓口の `DumpHeitansen`・`BlockTsunagari`・`UnblockTsunagari`・`SetNeverIsolated`・`ShowHeitansen` で確かめる
- 落石地点と大火計地域は、区画の目印（`Mejirushi.RakusekiChiten`・`DaikakeiChiiki`）だけで完結させる。出撃したときに HaichiService が読み、構成の拠点とつながりと突き合わせて警告を出す。秘計の発動者から `Config.luau` の Hikei 節の `TargetRange` 以内で一番近い地点は `HaichiService.nearestRakusekiChiten`・`nearestDaikakeiChiiki` で引く。クライアントは仮の目印（旗と地面の枠）を出す。窓口の `DumpHikeiMejirushi`・`FindHikeiChiten` で確かめる
- 支配エリアは ShihaiAreaService が、兵站線を求め直すたびに求め直す（判定は `src/shared/ShihaiArea.luau`、半径と倍率は `Config.luau` の ShihaiArea 節）。兵站線につながった拠点の中心から半径以内がその拠点の軍の支配エリアで、重なる地点は中心が近い拠点の軍のものにする。孤立した拠点は持たない。自分の軍の支配エリアの中では、部隊の交戦の押す力と、上忍と首領の攻撃と防御が上がる。クライアントは `ReplicatedStorage.ShihaiArea` の拠点ごとの Configuration の Attribute（`Gun`・`Position`・`Radius`）を読む。窓口の `DumpShihaiArea`・`ShowShihaiArea` で確かめる。交戦の押す力と倍率は `DumpKosen`、上忍の攻撃と防御は `DumpJonin` に出る
- 上忍と首領は JoninService がデータで持つ（計算は `src/shared/Jonin.luau`）。上忍は率いる部隊の位置に合わせ、首領は本陣の中心に置く。能力値は `Config.luau` の Stats 節の Jonin・Shuryo。クライアントは `ReplicatedStorage.Jonin` のキャラクター ID ごとの Configuration の Attribute（`Position`・`Health`・`MaxHealth`・`Gun`・`Butai`・`Shuryo`・`DisplayName`・`Kotai`）を読む。窓口の `DumpJonin`・`SetJoninHealth` で確かめる。上忍の目的地は外から差し替えられる（`JoninService.overrideMokutekichi`。挑発が使う）。差し替えている間は部隊に合わせず、個体が出ていれば個体が目的地へ歩き、出ていなければデータの位置を上忍の歩く速さ（Stats 節の WalkSpeed）で部隊を進める間隔ごとに進める（計算は `Jonin.approach`）。目的地からは `Config.luau` の Jittaikaken 節の HomeRadius の距離で止まる。差し替えを外すと（`releaseMokutekichi`）、いきなり部隊の位置へ移さず、歩いて部隊へ戻ってから合わせ直す。差し替えている間と部隊へ戻る途中の上忍は、部隊の交戦で上忍同士の戦いに加わらない。`DumpJonin` の `mokutekichi`（差し替えた目的地）と `returning`（部隊へ戻る途中）で確かめる
- 上忍と首領の被ダメージの受け口は `JoninService.damage`（威力・攻撃したプレイヤー・反応）の1つで、プレイヤーの攻撃（CombatService）も秘計（大火計・爆破罠）もここを通す。与ダメージは威力を防御で軽減した値（`Stats.damage`）。倒れたら、率いていた部隊の士気を下げ、攻撃したプレイヤーの撃破数に1を足し、`JoninService.defeated`（キャラクター ID と倒したプレイヤー）で知らせる。士気の出来事（上忍の撃破）はこれを受けて ShikiService が知らせる。毒手裏剣の毒もデータの上で進む（`JoninService.poison`）。窓口の `DamageJonin`・`PoisonJonin` で確かめる
- 上忍と首領（両軍）の個体は JoninKotaiService が実体化圏で出し入れする（判定は `src/shared/Jittaikaken.luau`、半径は `Config.luau` の Jittaikaken 節）。出撃メンバーの誰かが AppearRadius 以内に近づくと、仮の見た目（`Appearance.createModel`）に軍の色の体力バーを付けて地面の高さ（`Ground.placeCharacter`）に出し、全員が DisappearRadius より離れると消す。体力はデータに残るので、離れて戻っても同じ体力で出直す。出ている間は個体の位置をデータへ写し、戦う相手がいなければ、戻る位置（`JoninService.homeOf`。率いる部隊の位置、首領は本陣の中心、目的地を差し替えた上忍はその目的地）から離れたら歩いて向かう。倒れた個体はその場に倒れ、CorpseLifetime 秒後に消える。敵軍の個体はプレイヤーの攻撃判定の対象になる（`JoninKotaiService.getTargets`）。窓口の `DumpJoninKotai` で確かめる
- 敵軍の上忍と首領の個体は、出撃メンバーと戦う（判断は `src/shared/Kata.luau`、型と数値は `Config.luau` の Kata 節）。考える間隔（Jittaikaken 節の Interval）ごとに、狙う相手（最後に攻撃してきた相手か、一番近い相手）を選んで間合いまで近づく。上忍は率いる部隊の位置から ChaseRadius の円の中、首領は本陣の範囲の中を追いかけ、外へは出ない。型を選べる時刻になったら、間合いに入っている型から重みで1つ選んで出す（首領は首領だけの型も選ぶ）。予備動作の間は狙う相手の方を向いて止まり、足元に判定の範囲を赤く描いて体を光らせる（`Vfx.area`・`Vfx.glow`）。判定は攻撃判定の形（HitShape）で出し、プレイヤーへのダメージは被ダメージの窓口（`DamageService.damage`。威力は 型の倍率 × 攻撃）を通すので、無敵・ガード・防御の軽減はほかの被ダメージと同じに決まる。型の最中も通常攻撃ではのけぞらず、吹き飛びと打ち上げを受けると型をやめる。型のモーションは武器種の行動のモーションを流用する（`Motions.forKata`）。戦う相手は軍ごとの相手（候補の一覧と攻撃の当て方。`JoninKotaiService.setAite`）で渡す。敵軍の上忍と首領が考えるたびに、`JoninKotaiService.setHikeiDecider` で登録した秘計の判断を呼ぶ（個体として出ていなくても呼ぶ）。窓口の `SetJoninAI false` で戦いと秘計の判断を止め、`UseKata` で型を1回出させ、`DumpJoninKotai` の `target`・`kata`・`lastHit` で確かめる
- 味方軍の上忍と首領の個体は、敵の下忍を狙い、敵軍の個体と同じ戦い方（狙う相手の選択・間合い・型）で戦う。敵の下忍の個体と窓口で出した敵（`EnemyService.getTargets`）を狙う。プレイヤーと敵軍の上忍・首領の個体は狙わず、型の判定も当てない（上忍同士は部隊の交戦でデータの上で戦う）。下忍の個体は防御を持たないので、与ダメージは 型の倍率 × 攻撃 のまま。`EnemyService.damage` に攻撃したプレイヤーを渡さないので、倒しても誰の撃破数にも数えない（倒れた下忍の個体は部隊の兵数を1減らす）。予備動作の範囲と体の光は青で描き、敵軍の赤と見分ける。能力値は Stats 節の MikatagunScale で敵軍より低い。味方軍の上忍と首領は秘計を使わない（秘計の判断を呼ばない）。窓口の `UseKata` に敵の下忍の名前（`SpawnEnemy` が返す名前か `DumpEnemies` の `name`）を渡して型を出させ、`DumpEnemies` の `health` と `DumpJoninKotai` の `lastHit` で確かめる
- 部隊の目的地は HoshinService が、配置で部隊ごとに決めた方針（攻略・防衛・救援）に沿って `Config.luau` の Hoshin 節の間隔ごとに決め直す（判断は `src/shared/Hoshin.luau`）。攻略はつながりの先の道のりが一番近い相手の拠点、防衛は担当の拠点に近づいた相手の部隊、救援は耐久が減って攻められている自分の軍の拠点を目指し、目指す先が無ければ担当の拠点へ戻る。つながりの経由点をたどり、その軍が通れないつながりは通らない。外から目的地を差し替える API（`HoshinService.overrideKyoten`・`overridePosition`・`release`）を持つ。首領は本陣の範囲にとどまる（`JoninService.setPosition` が範囲の縁へ寄せる）。窓口の `DumpHoshin`・`SetHoshinAI`・`SetHoshin`・`OverrideMokutekichi`・`SetJoninPosition` で確かめる。`SetHoshinAI false` で判断を止めると、方針で動く部隊はその場で止まる。方針で動く部隊を窓口で動かすときは `OverrideMokutekichi` を使う（`MoveButai` は次の判断で目的地が戻る）
- 敵味方の部隊が近づくと交戦を始め、決着までその場にとどまる。相手は1部隊ずつで、交戦中の敵の手前に来た部隊は待つ。組み方と損害の計算は `src/shared/Kosen.luau`、距離と係数は `Config.luau` の Kosen 節
- 戦闘のフェーズには制限時間（`Config.luau` の Stage 節）があり、終了予定の時刻を workspace の Attribute `BattleDeadline`（`workspace:GetServerTimeNow` の時刻）に置く。過ぎると時間切れで負ける。窓口の `SetDeadline <残り秒数>` で縮められる
- 勝敗は ShohaiService が判定する（計算は `src/shared/Shohai.luau`）。勝ちは敵軍の首領の撃破と敵軍の本陣の制圧、負けは味方軍の首領の撃破と本陣の陥落と、兵力0で倒れたこと。条件は `JoninService.defeated`・`KyotenService.seiatsu`・`SaishutsugekiService.heiryokuZero` で受けて溜め、`task.defer` で今の再開の終わりにまとめて判定し、`StageService.finish` を1回だけ呼ぶ。同じ再開の中で起きた条件は同時とみなして負けを優先し、勝ちどうし・負けどうしは首領の撃破・本陣・兵力0・時間切れの順で理由を選ぶ。時間切れは StageService が決め、先に決着していれば finish を受け付けない。決着すると、部隊（ButaiService）・上忍と首領（JoninService）・その個体（JoninKotaiService）・下忍の個体（EnemyService・GeninKotaiService）を各サービスが片付ける。窓口の `DumpStage` の `result` で勝敗と理由を確かめる
- 人数による調整は、出撃したときのメンバーの数で決める（計算は `src/shared/PartySize.luau`、倍率は `Config.luau` の PartySize 節）。敵軍の上忍と首領の体力の最大（JoninService）と、出撃したときの兵力（SaishutsugekiService）に倍率を掛け、途中で抜けても変えない。味方軍の上忍と首領には掛けない。人数は `StageService.started` の `partySize` で渡す。窓口の `SetPartySize <人数>` で次の出撃から使う人数を上書きし、`DumpJonin`・`DumpHeiryoku`・`DumpStage` で確かめる
- プレイヤーの出現は PlayerService が行い、Roblox の自動の出現（`Players.CharacterAutoLoads`）は止めている。入室した人はロビーに出る。倒れた人は同じ節の秒数の後に、SaishutsugekiService が出現し直させる。戦闘中の出撃メンバーは、兵站線につながった味方の拠点のうち倒れた位置に一番近い拠点から出て、パーティーで共有する兵力を1使う（計算は `src/shared/Saishutsugeki.luau`）。兵力0で倒れたら負ける。戦闘の外の出撃メンバーは出撃地点から、ほかの人はロビーから出る。兵力は workspace の Attribute `Heiryoku` で複製し、窓口の `SetHeiryoku`・`DumpHeiryoku` で確かめる
- 画面上部の戦況の表示（BattleStatusController）は、戦闘のフェーズの出撃メンバーにだけ、中央に残り時間と兵力、左右に味方軍と敵軍の軍全体の士気のゲージを出す。値は `ReplicatedStorage.Shiki` の Attribute（`Mikatagun`・`Tekigun`）と workspace の Attribute（`BattleDeadline`・`Heiryoku`）から読む。残り時間は `Config.luau` の BattleStatus 節のしきい値以下で黄色と赤、兵力0は赤で出す（判断と文は `src/shared/BattleStatus.luau`）。窓口の `SetGunShiki`・`SetDeadline`・`SetHeiryoku` で確かめる
- イベントシーンは、サーバーが出撃メンバーに `PlayEventScene` で流し、長さが過ぎるか全員がスキップを押すと次のフェーズへ進める。シーンの ID と長さは `src/shared/EventScenes.luau`、スキップの集計は `src/shared/SkipVote.luau` にある。窓口の `StartEventScene Shiken` で、試験用のシーンを流して出撃する
- パーティーとリーダーは PartyService が持つ（計算は `src/shared/Party.luau`）。リーダーは一番早く入った人で、プライベートサーバーでは、持ち主（`game.PrivateServerOwnerId`）がパーティーにいて待機中でなければ持ち主にする。出撃中に入った持ち主は待機中なので、リザルトのリトライとロビーへ戻る操作は出撃したリーダーが続け、ロビーに戻って合流した時点で持ち主がリーダーになる。進行を読み終える前の人がリーダーになったときは、読み終えてから選択を確かめ直す（SelectionService）。Studio ではプライベートサーバーを立てられないので、窓口の `SetPrivateServerOwner <プレイヤー名|UserId|なし>` で持ち主を上書きし（`なし` で上書きを外す）、`DumpParty` の `leader` と `privateServer`（`ownerId`・`override`・`privateServerOwnerId`）で確かめる。パーティーにいない UserId を渡すと、持ち主がいないときの決まりを1人で確かめられる
- タイトル画面（TitleController）は、入室するたびにロビーの画面より手前に出す（保存はしない）。タイトル（`src/shared/Title.luau`。今は仮で、決まったらここだけを直す）、非公式ファンゲームかつパラレル設定である旨（文言はロビーの表記と同じ `src/shared/Notice.luau`）、「はじめる」のボタンを並べる。はじめるはクリック・タッチ・Enter（`InputMap.luau` の Hajimeru）と、ゲームパッドで選んだボタンの A で押し、押すとロビーの画面に進む。サーバーへは何も送らない。出撃前の画面と非公式の表記は、タイトル画面を閉じるまで出さない（後ろのボタンをゲームパッドで選べないように）。ゲームパッドのときは、はじめるを選ぶ。入室直後に選ぶと Studio が落ちるので、どの画面も `Ui.waitForSelectable` で入室から3秒たってキャラクターが出るまで待ってから選ぶ。窓口の `ShowTitle <プレイヤー名>` で、入り直さずにもう一度出せる（Player の Attribute の `TitleRequest` を書き換え、本人のクライアントが見て出す。出撃メンバーがステージに出ている間は出さない）
- 出撃前は、リーダーがストーリー（クラン）を選び、そのストーリーのステージを選ぶ（`SelectStory`・`SelectStage`）。選べるのはリーダーが開放したステージのあるストーリーだけで、判定は `src/shared/SelectionRules.luau` の `checkStory`。ステージを選ぶとストーリーもそのクランになり、別のストーリーを選ぶとステージの選択が外れる。窓口の `SelectStory <プレイヤー名> <クラン ID>` で確かめる
- 勝ったら、出撃して残っている全員にクリアを記録し、新しく開放したステージを `StageResult` に載せる（対象は `src/shared/Progress.luau` の `clearTargets`）。リザルトでリーダーが `ReturnToLobby` を送るとストーリー以外の選択を外してロビーへ、`Retry` を送るとステージと選択を残してロビーへ戻る
- ミニマップ（MinimapController）は、戦闘のフェーズの出撃メンバーにだけ、画面の右上（戦況の表示の下）に出撃したステージの区画を北を上にして出す（出す条件は戦況の表示と同じ）。出している間は Roblox 標準のプレイヤー一覧を消す。支配エリア（軍の色の薄い円）、兵站線（入っている兵站線の軍の色の線。どちらにも入っていなければ灰色、塞がれたつながりは薄く）、拠点と本陣（軍の色。本陣は「本」、兵糧庫は「糧」、孤立した拠点は薄く「孤」）、部隊（軍の色の点。交戦中は黄色い縁、潜んでいる伏兵部隊は味方軍のものだけ薄く）、上忍と首領（軍の色の丸に頭文字。`Characters.initialOf`）、自分（黄色）と仲間（白）の位置と向き（針付きの丸）を描く。戦場の様子は `ReplicatedStorage` の ShihaiArea・Tsunagari・Kyoten・Butai・Jonin の Attribute から読み、部隊は下忍の個体を見ずに部隊のデータから描く。つながりの経由点は Tsunagari の Attribute（`KeiyutenCount`・`Keiyuten1`…）で複製する。範囲は workspace の Attribute（`MinimapCenter`・`MinimapSize`）、仲間の位置と向きは Player の Attribute（`MinimapPosition`・`MinimapFacing`）から読む。StreamingEnabled のため、どちらもサーバーの MinimapService が書く。描き直す間隔は `Config.luau` の Minimap 節、計算は `src/shared/Minimap.luau`、大きさと位置は `Ui.Minimap`。範囲は区画の範囲の目印を囲むワールドの軸にそろえた四角で、拠点は目印の向き（拠点の Attribute の `Yaw`）に回して描く。秘計の知らせはミニマップの左に積む
- スマホ横画面の戦闘の操作ボタン（TouchControlsController）は、タッチで遊んでいる人のうち戦闘のフェーズの出撃メンバーにだけ出す（出す条件は戦況の表示と同じ。判断は `src/shared/TouchControls.luau`）。タッチで遊んでいるかは `UserInputService.PreferredInput`（使えなければ最後の入力の種類）で決め、キーボードとマウスやゲームパッドに切り替えたら消す。Studio のテストプレイでは、マウスのクリックがタッチとして届き、キーボードの無い端末と報告する環境があるので、Auto ではタッチとみなさない（Studio で確かめるときは `SetTouchControls` で On にする）。押した入力は InputController の行動の入口（キーとゲームパッドと同じ関数）を通し、Remotes.Action だけを送る。ジャンプは標準のジャンプボタンで、ガード中にサムスティックを倒すと緊急回避になる（PC と同じく `Humanoid.MoveDirection` から判定する）。出している間は戦闘の画面をタッチの配置にする（`Ui.setTouchLayout`）。戦闘の画面を、縮める前の大きさが `Config.luau` の TouchControls 節の DesignWidth x DesignHeight 以上になる倍率で縮め、HUD の秘計の枚と操作の案内を隠して撃破数を左上へ移す。ボタンの配置は `src/shared/TouchLayout.luau` が、標準のジャンプボタン・標準のサムスティックの範囲・ほかの戦闘の画面の部品を避けて決める（ほかの部品の位置は各コントローラーの定数を写している）。画面は横向きに固定する。窓口の `SetTouchControls <プレイヤー名> <on|off|auto>` で出すかを強制し（Player の Attribute の `TouchControls`）、`DumpAction <プレイヤー名>` でサーバーが受け取った行動を確かめる。ボタンは PlayerGui.TouchControls の Attack・ChargeKogeki・Guard・Ougi・Hikei1〜3 で読める
- リザルト画面（ResultController）は、`StageResult` を受けた人にだけ、勝敗と理由・経過時間・全員の撃破数・本人が得た巻物・本人の上がった熟練度と新しく覚えた秘計・本人が開放したステージを出す。`Retry` と `ReturnToLobby` のボタンはリーダーにだけ出し、ほかの人には待ちの文を出す。文は `src/shared/ResultMessage.luau` にある。窓口の `SendStageResult Iga1` で、開放したステージを差し替えた結果を送り直して確かめる
- 進行は DataStore に UserId ごとに保存し、保存済みの記録と和集合にして書く（計算は `src/shared/Progress.luau`）。Studio のテストプレイは本番と別の DataStore（`ProgressStudio`）を使う。DataStore を使えないとき（Studio から API サービスへのアクセスを許していないときなど）は、警告を出してサーバーのメモリにだけ保存する
- 特技ツリーによる成長は TokugiService が持つ（計算は `src/shared/Tokugi.luau`、ツリーの形と値と巻物の数は `Config.luau` の Tokugi 節、特技の名前は `Tokugi.names`）。記録はプレイヤーごと・キャラクターごとの、得た巻物の合計と覚えた特技（どちらも増えるだけ）で、使える巻物は合計から覚えた特技の巻物の数を引いて求める。進行とは別の DataStore（Studio は `TokugiStudio`）に、共通の部品 `src/server/PlayerStore.luau` で保存する。PlayerStore は記録の変更（巻物を得た・特技を覚えた）を溜め、UpdateAsync で保存済みの記録に当てて書くので、読み込みに失敗したまま保存しても記録は消えない。DataStore を使えないときはメモリにだけ保存する。特技は、出撃前の画面の特技の欄から開く特技ツリーの画面（`src/client/Selection/TokugiWindow.luau`）で押して覚える（`Remotes.LearnTokugi`）。覚えられるのはロビーのフェーズで、記録を読めた後、まだ覚えておらず、前提を覚えていて、巻物が足りる特技だけ（`Tokugi.checkLearn`）。拒否の理由は `SelectionRejected` で返す。本人の記録は `TokugiState` で本人にだけ送る（クライアントは `src/client/TokugiClient.luau` で持つ）。出撃するときに StageService が、使うキャラクターの覚えた特技の補正を固定し（`TokugiService.lock`。体力の最大は出現したときに当てるので、出現し直させる前に呼ぶ）、`PlayerService.addModifierProvider` で能力値に足す。ロビーのフェーズに戻ると固定を外す。決着したときは、勝ち負けによらず出撃して残っている全員（`Progress.remaining`）に、そのとき使っているキャラクターの巻物（撃破数に応じた数と、勝ちなら上乗せ。`Tokugi.makimonoFor`）を渡し、`StageResult` のメンバーごとの `character`・`makimono` に書いてリザルトに出す。試験用ステージでも渡す。窓口の `AddMakimono`・`LearnTokugi`・`DumpTokugi`・`ResetTokugi` と、能力値の `DumpPlayerStats` で確かめる
- 秘計の系統と熟練度は JukurendoService が持つ（計算は `src/shared/Jukurendo.luau`、系統ごとの秘計と覚える熟練度・倍率・上限は `Config.luau` の Jukurendo 節）。系統は武勇（鬼神化・大喝・挑発）・知略（落石・大火計）・堅牢（伏兵・兵糧庫・爆破罠）で、熟練度を上げる戦い方はそれぞれ撃破数・制圧数・救援数。記録はプレイヤーごとの、系統ごとの熟練度と覚えた秘計（どちらも増えるだけ）で、覚えた秘計は記録の覚えた秘計に熟練度が覚える値に達した秘計を合わせたもの（`Jukurendo.learned`。覚える値が 0 の各系統の最初の1枚は最初から覚えている）。進行とも特技とも別の DataStore（Studio は `JukurendoStudio`）に PlayerStore で保存するので、読み込みに失敗したまま保存しても記録は消えない。決着したときは、勝ち負けによらず出撃して残っている全員に、Player の Attribute の撃破数・制圧数・救援数に倍率を掛けた熟練度（1回のステージの上限あり。`Jukurendo.gainOf`）を足し（`JukurendoService.award`）、`StageResult` のメンバーごとの `seiatsusu`・`kyuensu`・`jukurendo`・`newlyLearned` に書いてリザルトに出す。試験用ステージでも足す。制圧数は、味方軍が拠点を制圧したときに範囲の中にいた倒れていない出撃メンバーに、救援数は、救援が要る味方軍の拠点（耐久が Hoshin 節の KyuenRate 以下に減り、攻める軍が範囲の中にいる拠点。`Hoshin.needsKyuen`）の範囲の中で敵軍の下忍・上忍・首領を倒したプレイヤーに、KyotenService が足す。出撃前に選べるのは覚えた秘計だけで、覚えていない秘計の `SelectHikei` は `HikeiNotLearned`、熟練度の記録を読み終える前は `HikeiNotLoaded` で拒否する（`SelectionRules.applyHikei`）。1枚も選ばずに出撃した人に配る秘計も、その人が覚えた秘計だけから選ぶ（`Hikei.assignMochikomi`）。敵軍の上忍と首領の持ち込みは変えない。M1 から遊ぶ人の扱いとして、熟練度の記録を読めて、まだ確かめておらず、進行も読めたら、進行にクリア済みのステージがある人に M1 の8種を覚えた秘計に加え、確かめたことを記録に残す（`Jukurendo.m1ChangeOf`）。本人の記録は `JukurendoState` で本人にだけ送り（クライアントは `src/client/JukurendoClient.luau` で持つ）、出撃前の画面の秘計の欄（`src/client/Selection/HikeiSection.luau`）が系統ごとの熟練度と次に覚える秘計までの値を見出しに出し、覚えた秘計だけを並べる。窓口の `AddJukurendo`・`DumpJukurendo`・`ResetJukurendo`（`m1` を付けると記録の無い人の扱いにして M1 から遊ぶ人かを確かめ直す）と、`SelectHikei`、`SetSeiatsusu`・`SetKyuensu`、拠点の救援が要るかを出す `DumpKyoten` の `kyuen` で確かめる
- 秘計の中身は秘計ごとのサービスが `HikeiService.register` で登録する（兵糧庫は HyorokoService）。発動できないとき（対象が無い、重ねがけなど）は失敗の理由を返し、枚は使わずに残る。見た目は `workspace.Hikei` の下の秘計ごとのフォルダ（`HikeiService.folderOf`）に置く。兵糧庫は、発動者が中にいる味方の通常拠点を孤立しない拠点にし（`HeitansenService.setNeverIsolated`）、拠点の中心に米俵と札を置く。制圧されると効果を終える。落石は、発動者から `Config.luau` の Hikei 節の TargetRange.Rakuseki 以内で一番近い落石地点に岩を落とし、その区間を相手の軍にとって通れなくする（`HeitansenService.block`）。岩は相手の軍の下忍と上忍の個体だけを止める衝突のグループ（`CollisionGroups.rakusekiGroupOf`）で、プレイヤーは通り抜ける。効果時間が過ぎると岩が消えて区間が戻る。伏兵は、発動者の足元に伏兵部隊（兵数は `Config.luau` の Fukuhei 節）を潜ませる。潜んでいる部隊は Butai の `fukuhei` の印を持ち、交戦の相手・方針の迎え撃つ相手・拠点の守備と攻める軍に数えない（部隊の Attribute の `Fukuhei`）。相手が KishuRadius 以内に来たら奇襲し（判定は `src/shared/Fukuhei.luau`）、相手の部隊の士気を KishuShiki だけずっと下げて交戦を始める。鬼神化は、効果時間（Hikei 節の Duration.Kishinka）の間、発動者の攻撃と防御に `Config.luau` の Kishinka 節の倍率を掛け、のけぞらなくする（吹き飛びと打ち上げはダウンになる）。プレイヤーは能力値の補正（`PlayerService.addModifierProvider`）とのけぞらない状態（`DamageService.addNoFlinchProvider`）、上忍と首領は能力値の補正（`JoninService.setHikeiHosei`）で効かせ、倒れたら解除する。大喝は、発動者から `Config.luau` の Daikatsu 節の Radius 以内の相手の上忍・首領・プレイヤー・部隊（潜んでいる伏兵部隊を除く。選び方は `src/shared/Daikatsu.luau`）を対象にし、上忍・首領・プレイヤーにかかった強化の秘計を打ち消して（`HikeiService.dispelKyoka`）、効果時間（Hikei 節の Duration.Daikatsu）の間、動揺させる。対象が1つも無ければ NoTarget、対象がすべてもう動揺していて打ち消すものも無ければ AlreadyActive で、枚は使わない。動揺した上忍・首領・プレイヤーは攻撃と防御が下がり、部隊は士気が下がる（`ButaiService.setDoyo`、部隊の Attribute の `Doyo`）。窓口の `WarpToJonin` で上忍のいる位置へ移って、上忍に使わせた秘計を確かめる。大火計は、発動者から Hikei 節の TargetRange.Daikakei 以内で一番近い大火計地域の中の相手の上忍・首領（`JoninService.damage`）・プレイヤー（ガードできない攻撃。`Damage.Attack` の `guardable`）・敵の下忍の個体に `Config.luau` の Daikakei 節の威力のダメージを与え、部隊の兵数を、個体として出ていない分の HeisuRate の割合だけ減らす（個体はダメージで1体ずつ倒れ、兵数を1ずつ減らす）。発動者がプレイヤーなら、倒した数を撃破数に足す。窓口の `DumpEnemies` で下忍の個体の体力を確かめる。爆破罠は、発動者が中にいる自分の軍の拠点（本陣も含む）に罠を仕掛け、耐久が上限の `Config.luau` の Bakuhawana 節の Rate を上から下へ越えるとき、耐久を書き換える前（一度に 0 まで減るときは制圧の前）に1回だけ爆発させる（判定は `src/shared/Bakuhawana.luau`、`KyotenService.addTaikyuListener`）。爆発は拠点の範囲の中の相手の上忍・首領・プレイヤー（ガードできない吹き飛び）・敵の下忍の個体にダメージを与えて吹き飛ばし、部隊の兵数を、個体として出ていない分の割合だけ減らす（爆発で倒れた個体の分も、拠点の耐久には数えない）。罠の目印は仕掛けた軍にだけ見せ、耐久が割合をもう下回った拠点には仕掛けられない（`LowTaikyu`）。挑発は、発動者から `Config.luau` の Chohatsu 節の Radius 以内の相手の上忍（首領は除く。選び方は `src/shared/Chohatsu.luau`）の目的地を、効果時間（Hikei 節の Duration.Chohatsu）の間、発動者の今の位置に差し替える（`JoninService.overrideMokutekichi`）。部隊は誘い出さず、方針どおりに動く。対象が無ければ NoTarget、範囲の中の上忍がすべてもう誘い出されていれば AlreadyActive で、枚は使わない。効果時間が過ぎるか、発動者か上忍が倒れるか、プレイヤーの発動者の姿が入れ替わったら差し替えを外し（`releaseMokutekichi`）、上忍は歩いて部隊へ戻る。敵軍の上忍と首領が使うと、味方軍の上忍を誘い出す。窓口の `SetHikeiMochikomi`・`UseHikei`・`WarpToKyoten`・`WarpToHikeiChiten`・`SetHikeiRemaining`・`DumpPlayerStats` で確かめる
- 敵軍の上忍と首領は、秘計の判断（HikeiHandanService。判断は `src/shared/HikeiHandan.luau`、間隔と割合は `Config.luau` の HikeiHandan 節）で秘計を使う。持ち込みは配置の構成（`Haichi.luau` の `mochikomi`。キャラクター ID から引く）に置き、出撃したときに HikeiService が持ち込みを空にした後で決める。持ち込めるのは敵軍の上忍と首領だけで、上限と重なりはプレイヤーと同じ検証（`Hikei.checkMochikomi`）を `Haichi.validate` で通す。判断は JoninKotaiService の考える間隔ごとに呼ばれ（`setHikeiDecider`）、上忍と首領ごとに Interval 秒に1回、使える秘計（まだ使っておらず、試し直しを待っていない枚）を枚の順に見て、条件のそろった最初の秘計を秘計の入口（`HikeiService.useByJonin`）で使う。鬼神化は率いる部隊が交戦中か首領の体力が上限の ShuryoHealthRate 以下のとき、大喝は Daikatsu 節の Radius 以内に強化の秘計の効果中の相手がいるとき、挑発は Chohatsu 節の Radius 以内に誘い出されていない相手の上忍（首領は除く）がいるときに使う。敵軍のだれかが使ったら（`HikeiService.activated`。窓口の `UseHikei` も含む）、UseInterval 秒の間は敵軍のだれも判断しない。発動できなかった秘計は、RetryInterval 秒の間、同じ上忍か首領は選ばない。味方軍の上忍と首領は使わない。使ったときと使えなかったときは、コンソールに `[HikeiHandan]` の行を出す。窓口の `DumpHikeiHandan`（判断の様子）・`DecideHikei`（間隔を待たずに判断させる）・`ResetHikeiHandan`（使用間隔の待ちを外す）で確かめる
- 秘計の判断の伏兵は、自分の軍の拠点の範囲の中にいて、その拠点の中心から `Config.luau` の HikeiHandan 節の FukuheiDistance 以内に相手の部隊かプレイヤーが来たときに使う。その拠点の範囲の中に自分の軍の伏兵部隊がもう潜んでいれば重ねない。落石は、落石の発動と同じ選び方（`HaichiService.nearestRakusekiChiten`）で選んだ一番近い落石地点の区間が、相手の軍の兵站線に入っているとき（`HeitansenService.gunOf`）に使う。岩がもうある地点（`RakusekiService.isActive`）には使わない。大火計は、大火計の発動と同じ選び方（`HaichiService.nearestDaikakeiChiiki`）で選んだ一番近い大火計地域の中の相手が DaikakeiAite 以上のときに使う。相手はプレイヤー・上忍・首領・部隊を1つずつ数え（地域の中かは発動と同じ `DaikakeiService.contains`）、伏兵と大火計のどちらも、潜んでいる伏兵部隊と兵数の無い部隊は相手に入れない。様子はデータの位置から作るので、個体として出ていない上忍と首領も同じに判断する。窓口の `DumpHikeiHandan` の `kyoten`（`aiteDistance` は拠点の中心から一番近い相手までの距離）・`rakuseki`・`daikakei`（`aiteCount` は中の相手の数）で確かめる
- 拠点を使う秘計の判断は、上忍か首領が範囲の中にいる拠点（秘計の発動と同じ `KyotenService.kyotenAt` でデータの位置から引く）の様子で決める。兵糧庫は、その拠点が自分の軍の通常拠点で、兵站線の末端（`HeitansenService.isMattan`）のときに使う。爆破罠は、その拠点が自分の軍の拠点（本陣も含む）で、拠点の中心から `Config.luau` の HikeiHandan 節の BakuhawanaRadius 以内にプレイヤーがいるときに使う。もう兵糧庫の拠点（`HyorokoService.isHyoroko`）、もう罠のある拠点（`BakuhawanaService.hasTrap`）、耐久が爆発する割合をもう下回った拠点では使わない。どちらも発動の確かめ（`Hikei.checkHyoroko`・`checkBakuhawana`）に同じ値を渡すので、判断で選んだら発動できる。試験用ステージでは、試験の上忍2 が東（敵軍の兵站線の末端）で兵糧庫を使い、プレイヤーが東に近づいたら爆破罠を使う。`DumpHikeiHandan` の `kyoten`（中にいる拠点の末端か・兵糧庫か・罠があるか・耐久・中心から一番近いプレイヤーまでの距離）で確かめる
- 効果音は `src/shared/Sounds.luau` の登録表に置き、`src/shared/SoundPlayer.luau` で名前を指定して鳴らす。戦闘の音はサーバーが場所を指定して鳴らし、画面の音はクライアントが本人にだけ鳴らす。音量は `Config.luau` の Sound 節。戦闘の音は、技（`Swing`・`ChargeKogeki`・`Ougi`）と命中（`Hit`）を CombatService、プレイヤーの被弾（`Hurt`）・ガードで受けたとき（`Guard`）・ダウン（`Down`）を DamageService、緊急回避（`KinkyuKaihi`）を ActionService が鳴らす。敵のダウンには鳴らさない（まとめて吹き飛ばした敵の着地が続けて重なるため）。画面の音は、決定（`Confirm`）・取り消し（`Cancel`）を出撃前の画面とリザルト、ゲームパッドやキーの操作で選んでいるボタンが移ったとき（`Cursor`）を出撃前の画面とリザルト（`Ui.onSelectionMoved`）、自分の軍の拠点の制圧（`Seiatsu`）と陥落（`Kanraku`）を戦況の表示（拠点の Attribute の `Gun` の変化。判断は `Sounds.kyotenSceneFor`）、秘計の発動（`HikeiHatsudo`）を秘計の知らせ（`NotifyHikei` の発動）が鳴らす。窓口の `PlaySound <効果音の名前> <プレイヤー名>` で鳴らし、`LogSound true` で鳴らした効果音（名前・鳴らした側・`workspace:GetServerTimeNow` の時刻・場所）をサーバーとクライアントのコンソールに `[Sound]` の行で出す（テストプレイでは音を聞けないので、鳴ったかはこれで確かめる）
- BGM は `src/shared/Bgm.luau` の登録表に場面（ロビー・イベントシーン・戦闘・勝利・敗北）ごとに置き、クライアントの BgmController が本人にだけ流す。場面は `Bgm.sceneFor` が PartyState のフェーズと StageResult の勝敗から決め、待機中の人はロビーの曲にする。切り替えはフェードで、音量とフェードの長さは `Config.luau` の Bgm 節。流している場面は `SoundService.Bgm` の Attribute `Scene` で確かめる
- 武器は `src/shared/Appearance.luau` が、キャラクター定義の武器のモデルを右手の握りの Attachment に溶接して持たせる。見た目専用で、当たり判定は持たない
- モーションの ID は `src/shared/Motions.luau` の一覧に置く。待機と移動は Roblox 公式の Ninja パックで、仮の見た目の HumanoidDescription に入れて当てる
- 行動のモーションは、クライアントの MotionController が自分のキャラクターの Attribute（`Action`・`ActionStep`・`ActionDuration`・`ActionStartedAt`）を見て、行動の長さに合わせた速さで再生する。判定の時刻と移動量は `Config.luau` のままで、モーションには左右されない
