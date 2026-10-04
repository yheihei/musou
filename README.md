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
    Services/  KukakuService / HaichiService / PartyService / ProgressService / SelectionService / StageService / ButaiService / KyotenService / HeitansenService / SaishutsugekiService / JoninService / ShihaiAreaService / HoshinService / MinimapService / SerifuService / PlayerService / ActionService / DamageService / EnemyService / CombatService / HikeiService / HyorokoService / RakusekiService / FukuheiService
      KukakuService  ロビーと区画（Workspace.Lobby・Workspace.Stages）の目印の取得と、欠けたときの警告
      HaichiService  ステージの配置（拠点・つながり・部隊・首領）を構成と目印から読み込む。試験用ステージの目印を作る
      ProgressService  プレイヤーごとの進行（開放済みとクリア済みのステージ）の DataStore への保存
      SelectionService  出撃前の選択（ストーリー・ステージ・キャラクター・秘計）の受け付けと PartyState への反映
      StageService  出撃からロビー帰還までのステージの進行（フェーズ、出撃地点への移動、イベントシーンの同期とスキップ、勝敗の結果）
      ButaiService  戦場の部隊のデータ（位置・兵数・士気）と部隊どうしの交戦。配置から作り、目的地へ位置だけを進め、ReplicatedStorage.Butai の Attribute で複製する
      KyotenService  戦場の拠点の耐久と所属と守備。範囲の中で拠点の軍の下忍が倒れると耐久を減らし、0 で相手の軍に制圧させる。守備を補充し、守備のいない拠点は攻める軍がいる間に耐久を減らす。ReplicatedStorage.Kyoten の Attribute で複製する
      HeitansenService  兵站線と孤立。拠点の所属とつながりから軍ごとの兵站線を求め直し、孤立した拠点の補充を止める。つながりを通れなくする API と、孤立しない拠点の指定の API を持つ。ReplicatedStorage.Tsunagari の Attribute で複製する
      SaishutsugekiService  兵力と再出撃。倒れた出撃メンバーを兵站線につながった最寄りの味方の拠点から再出撃させ、兵力を1使う。兵力0で倒れたら負けにする
      JoninService  上忍と首領のデータ（能力値・体力・率いる部隊）。上忍は部隊とともに動き、首領は本陣にとどまる。ReplicatedStorage.Jonin の Attribute で複製する
      HoshinService  上忍が部隊を率いて、配置で決めた方針（攻略・防衛・救援）に沿って部隊の目的地を決める
      MinimapService  ミニマップに出す区画の範囲と、出撃メンバーの位置と向きを Attribute で複製する
      ShihaiAreaService  支配エリア。兵站線につながった拠点の周りを支配エリアとし、その軍の部隊の交戦の押す力と、上忍と首領の攻撃と防御を上げる。ReplicatedStorage.ShihaiArea の Attribute で複製する
      SerifuService  戦闘中の台詞を全員の画面の端に出す
      HikeiService  秘計の発動の入口（持ち込み・使用記録・効果の時間管理）。秘計ごとの処理は各サービスが register で登録する
      HyorokoService  秘計の兵糧庫。中にいる味方の通常拠点を、兵站線が切れても孤立しない拠点にする
      RakusekiService  秘計の落石。近くの落石地点に岩を落とし、その区間を相手の軍にとって通れなくする
      FukuheiService  秘計の伏兵。足元に伏兵部隊を潜ませ、近づいた相手を奇襲して士気を下げる
      ActionService  行動の状態遷移（入力、先行入力、被弾による中断）
      DamageService  プレイヤーの被ダメージの窓口
      CombatService  攻撃の中身と当たり判定
    Combat/    当たり判定と仮エフェクト
  client/   StarterPlayerScripts.Client 入力・HUD・モーションの再生・画面・BGM
    Selection/  出撃前の画面（ストーリーとステージ・キャラクター・秘計の選択と出撃ボタン）の欄
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
- 敵（仮の湧き処理の下忍と上忍）は近づいて攻撃するだけで、体ではプレイヤーにもほかの敵にもぶつからない（`src/server/CollisionGroups.luau` の衝突のグループ）。敵が上に積み重なってプレイヤーが動けなくなるのを防ぐ。重ならないよう、敵はプレイヤーの手前（`Config.luau` の Spawner 節の `PlayerGap`）で止まり、ほかの敵とも離れて囲む（立ち位置の計算は `src/shared/EnemySpacing.luau`）。攻撃の当たりは計算で決めるので影響しない
- 撃破数と奥義ゲージは Player の Attribute（`Gekihasu`、本数の `OugiStock`、次の1本までの量の `OugiGauge`）に持たせ、HUD はその変更を購読する
- 数値調整は `src/shared/Config.luau` に集約している
- ステージの配置は、構成（拠点の種類と軍、つながり、部隊）を `src/shared/Haichi.luau` に、位置をプレースの目印に置く（ADR 0006）。試験用ステージ `Test` は目印の位置もコードに持ち、テストプレイ中に目印を作る。窓口の `Shutsugeki <プレイヤー名> Test` で出撃し、`DumpHaichi Test` で読み込んだ配置を見る
- ステージの進行は StageService が持つ。フェーズはロビー → 開始のイベントシーン → 戦闘 → 終了のイベントシーン → リザルト → ロビーの順に進み、遷移は `src/shared/StagePhase.luau` が決める。ほかのサービスは `StageService.started`・`finished`・`phaseChanged` を受けて、始める処理と片付けをする
- 戦場の部隊は ButaiService がデータで持ち（ADR 0003）、目的地へ経由点をたどって位置だけを進める（計算は `src/shared/Butai.luau`）。クライアントは `ReplicatedStorage.Butai` の部隊ごとの Configuration の Attribute（`Position`・`Gun`・`Heisu`・`Shiki`・`Jonin`、交戦の相手の `Kosen`）を読む。窓口の `DumpButai`・`AddButai`・`MoveButai`・`ShowButai`・`DumpKosen` で確かめる
- 拠点は KyotenService がデータで持つ（計算は `src/shared/Kyoten.luau`、耐久の値は `Config.luau` の Kyoten 節）。範囲の中でその拠点の軍の下忍が倒れると耐久が減り、0 で相手の軍が制圧する。減らすのは部隊の兵数の減少（`ButaiService.heisuLost`）と、仮の湧き処理の下忍の撃破（`EnemyService.gekiha`）。クライアントは `ReplicatedStorage.Kyoten` の拠点ごとの Configuration の Attribute（`Gun`・`Taikyu`・`MaxTaikyu`・`Honjin`・`Position`・`Size`）を読む。窓口の `DumpKyoten`・`SetKyotenTaikyu`・`SetKyotenGun`・`ShowKyoten`・`DefeatEnemies` で確かめる
- 拠点の守備（範囲の中にいるその拠点の軍の部隊）は、耐久が残る間、`Config.luau` の Kyoten 節の上限まで間隔ごとに補充する。守備のいない拠点は、攻める軍（相手の軍の部隊と、敵軍の拠点では出撃したプレイヤー）が範囲の中にいる間に耐久が減る。制圧は拠点の陥落として `ShikiService.notify` で士気に知らせる。窓口の `RemoveButai` で守備を外して確かめる
- 兵站線は HeitansenService が、拠点の制圧・つながりを通れなくしたとき・戻したとき・孤立しない拠点の指定のたびに求め直す（計算は `src/shared/Heitansen.luau`）。孤立した拠点は守備を補充しない。落石は `HeitansenService.block`、兵糧庫は `setNeverIsolated` を使う。クライアントは拠点の Attribute の `Koritsu`・`NeverIsolated` と、`ReplicatedStorage.Tsunagari` のつながりごとの Configuration の Attribute（`KyotenA`・`KyotenB`・`Heitansen`・`BlockedMikatagun`・`BlockedTekigun`）を読む。窓口の `DumpHeitansen`・`BlockTsunagari`・`UnblockTsunagari`・`SetNeverIsolated`・`ShowHeitansen` で確かめる
- 落石地点と大火計地域は、区画の目印（`Mejirushi.RakusekiChiten`・`DaikakeiChiiki`）だけで完結させる。出撃したときに HaichiService が読み、構成の拠点とつながりと突き合わせて警告を出す。秘計の発動者から `Config.luau` の Hikei 節の `TargetRange` 以内で一番近い地点は `HaichiService.nearestRakusekiChiten`・`nearestDaikakeiChiiki` で引く。クライアントは仮の目印（旗と地面の枠）を出す。窓口の `DumpHikeiMejirushi`・`FindHikeiChiten` で確かめる
- 支配エリアは ShihaiAreaService が、兵站線を求め直すたびに求め直す（判定は `src/shared/ShihaiArea.luau`、半径と倍率は `Config.luau` の ShihaiArea 節）。兵站線につながった拠点の中心から半径以内がその拠点の軍の支配エリアで、重なる地点は中心が近い拠点の軍のものにする。孤立した拠点は持たない。自分の軍の支配エリアの中では、部隊の交戦の押す力と、上忍と首領の攻撃と防御が上がる。クライアントは `ReplicatedStorage.ShihaiArea` の拠点ごとの Configuration の Attribute（`Gun`・`Position`・`Radius`）を読む。窓口の `DumpShihaiArea`・`ShowShihaiArea` で確かめる。交戦の押す力と倍率は `DumpKosen`、上忍の攻撃と防御は `DumpJonin` に出る
- 上忍と首領は JoninService がデータで持つ（計算は `src/shared/Jonin.luau`）。上忍は率いる部隊の位置に合わせ、首領は本陣の中心に置く。能力値は `Config.luau` の Stats 節の Jonin・Shuryo。クライアントは `ReplicatedStorage.Jonin` のキャラクター ID ごとの Configuration の Attribute（`Position`・`Health`・`MaxHealth`・`Gun`・`Butai`・`Shuryo`・`DisplayName`）を読む。窓口の `DumpJonin`・`SetJoninHealth` で確かめる
- 部隊の目的地は HoshinService が、配置で部隊ごとに決めた方針（攻略・防衛・救援）に沿って `Config.luau` の Hoshin 節の間隔ごとに決め直す（判断は `src/shared/Hoshin.luau`）。攻略はつながりの先の道のりが一番近い相手の拠点、防衛は担当の拠点に近づいた相手の部隊、救援は耐久が減って攻められている自分の軍の拠点を目指し、目指す先が無ければ担当の拠点へ戻る。つながりの経由点をたどり、その軍が通れないつながりは通らない。外から目的地を差し替える API（`HoshinService.overrideKyoten`・`overridePosition`・`release`）を持つ。首領は本陣の範囲にとどまる（`JoninService.setPosition` が範囲の縁へ寄せる）。窓口の `DumpHoshin`・`SetHoshinAI`・`SetHoshin`・`OverrideMokutekichi`・`SetJoninPosition` で確かめる。`SetHoshinAI false` で判断を止めると、方針で動く部隊はその場で止まる。方針で動く部隊を窓口で動かすときは `OverrideMokutekichi` を使う（`MoveButai` は次の判断で目的地が戻る）
- 敵味方の部隊が近づくと交戦を始め、決着までその場にとどまる。相手は1部隊ずつで、交戦中の敵の手前に来た部隊は待つ。組み方と損害の計算は `src/shared/Kosen.luau`、距離と係数は `Config.luau` の Kosen 節
- 戦闘のフェーズには制限時間（`Config.luau` の Stage 節）があり、終了予定の時刻を workspace の Attribute `BattleDeadline`（`workspace:GetServerTimeNow` の時刻）に置く。過ぎると時間切れで負ける。窓口の `SetDeadline <残り秒数>` で縮められる
- 人数による調整は、出撃したときのメンバーの数で決める（計算は `src/shared/PartySize.luau`、倍率は `Config.luau` の PartySize 節）。敵軍の上忍と首領の体力の最大（JoninService）と、出撃したときの兵力（SaishutsugekiService）に倍率を掛け、途中で抜けても変えない。味方軍の上忍と首領には掛けない。人数は `StageService.started` の `partySize` で渡す。窓口の `SetPartySize <人数>` で次の出撃から使う人数を上書きし、`DumpJonin`・`DumpHeiryoku`・`DumpStage` で確かめる
- プレイヤーの出現は PlayerService が行い、Roblox の自動の出現（`Players.CharacterAutoLoads`）は止めている。入室した人はロビーに出る。倒れた人は同じ節の秒数の後に、SaishutsugekiService が出現し直させる。戦闘中の出撃メンバーは、兵站線につながった味方の拠点のうち倒れた位置に一番近い拠点から出て、パーティーで共有する兵力を1使う（計算は `src/shared/Saishutsugeki.luau`）。兵力0で倒れたら負ける。戦闘の外の出撃メンバーは出撃地点から、ほかの人はロビーから出る。兵力は workspace の Attribute `Heiryoku` で複製し、窓口の `SetHeiryoku`・`DumpHeiryoku` で確かめる
- 画面上部の戦況の表示（BattleStatusController）は、戦闘のフェーズの出撃メンバーにだけ、中央に残り時間と兵力、左右に味方軍と敵軍の軍全体の士気のゲージを出す。値は `ReplicatedStorage.Shiki` の Attribute（`Mikatagun`・`Tekigun`）と workspace の Attribute（`BattleDeadline`・`Heiryoku`）から読む。残り時間は `Config.luau` の BattleStatus 節のしきい値以下で黄色と赤、兵力0は赤で出す（判断と文は `src/shared/BattleStatus.luau`）。窓口の `SetGunShiki`・`SetDeadline`・`SetHeiryoku` で確かめる
- イベントシーンは、サーバーが出撃メンバーに `PlayEventScene` で流し、長さが過ぎるか全員がスキップを押すと次のフェーズへ進める。シーンの ID と長さは `src/shared/EventScenes.luau`、スキップの集計は `src/shared/SkipVote.luau` にある。窓口の `StartEventScene Shiken` で、試験用のシーンを流して出撃する
- 出撃前は、リーダーがストーリー（クラン）を選び、そのストーリーのステージを選ぶ（`SelectStory`・`SelectStage`）。選べるのはリーダーが開放したステージのあるストーリーだけで、判定は `src/shared/SelectionRules.luau` の `checkStory`。ステージを選ぶとストーリーもそのクランになり、別のストーリーを選ぶとステージの選択が外れる。窓口の `SelectStory <プレイヤー名> <クラン ID>` で確かめる
- 勝ったら、出撃して残っている全員にクリアを記録し、新しく開放したステージを `StageResult` に載せる（対象は `src/shared/Progress.luau` の `clearTargets`）。リザルトでリーダーが `ReturnToLobby` を送るとストーリー以外の選択を外してロビーへ、`Retry` を送るとステージと選択を残してロビーへ戻る
- ミニマップ（MinimapController）は、戦闘のフェーズの出撃メンバーにだけ、画面の右上に出撃したステージの区画を北を上にして出す（出す条件は戦況の表示と同じ）。支配エリア（軍の色の薄い円）、兵站線（入っている兵站線の軍の色の線。どちらにも入っていなければ灰色、塞がれたつながりは薄く）、拠点と本陣（軍の色。本陣は「本」、兵糧庫は「糧」、孤立した拠点は薄く「孤」）、部隊（軍の色の点。交戦中は黄色い縁、潜んでいる伏兵部隊は味方軍のものだけ薄く）、上忍と首領（軍の色の丸に頭文字。`Characters.initialOf`）、自分（黄色）と仲間（白）の位置と向き（針付きの丸）を描く。戦場の様子は `ReplicatedStorage` の ShihaiArea・Tsunagari・Kyoten・Butai・Jonin の Attribute から読み、部隊は下忍の個体を見ずに部隊のデータから描く。つながりの経由点は Tsunagari の Attribute（`KeiyutenCount`・`Keiyuten1`…）で複製する。範囲は workspace の Attribute（`MinimapCenter`・`MinimapSize`）、仲間の位置と向きは Player の Attribute（`MinimapPosition`・`MinimapFacing`）から読む。StreamingEnabled のため、どちらもサーバーの MinimapService が書く。描き直す間隔は `Config.luau` の Minimap 節、計算は `src/shared/Minimap.luau`、大きさは `Ui.Minimap`。秘計の知らせはミニマップの下に積む
- リザルト画面（ResultController）は、`StageResult` を受けた人にだけ、勝敗と理由・経過時間・全員の撃破数・本人が開放したステージを出す。`Retry` と `ReturnToLobby` のボタンはリーダーにだけ出し、ほかの人には待ちの文を出す。文は `src/shared/ResultMessage.luau` にある。窓口の `SendStageResult Iga1` で、開放したステージを差し替えた結果を送り直して確かめる
- 進行は DataStore に UserId ごとに保存し、保存済みの記録と和集合にして書く（計算は `src/shared/Progress.luau`）。Studio のテストプレイは本番と別の DataStore（`ProgressStudio`）を使う。DataStore を使えないとき（Studio から API サービスへのアクセスを許していないときなど）は、警告を出してサーバーのメモリにだけ保存する
- 秘計の中身は秘計ごとのサービスが `HikeiService.register` で登録する（兵糧庫は HyorokoService）。発動できないとき（対象が無い、重ねがけなど）は失敗の理由を返し、枚は使わずに残る。見た目は `workspace.Hikei` の下の秘計ごとのフォルダ（`HikeiService.folderOf`）に置く。兵糧庫は、発動者が中にいる味方の通常拠点を孤立しない拠点にし（`HeitansenService.setNeverIsolated`）、拠点の中心に米俵と札を置く。制圧されると効果を終える。落石は、発動者から `Config.luau` の Hikei 節の TargetRange.Rakuseki 以内で一番近い落石地点に岩を落とし、その区間を相手の軍にとって通れなくする（`HeitansenService.block`）。岩は相手の軍の下忍と上忍の個体だけを止める衝突のグループ（`CollisionGroups.rakusekiGroupOf`）で、プレイヤーは通り抜ける。効果時間が過ぎると岩が消えて区間が戻る。伏兵は、発動者の足元に伏兵部隊（兵数は `Config.luau` の Fukuhei 節）を潜ませる。潜んでいる部隊は Butai の `fukuhei` の印を持ち、交戦の相手・方針の迎え撃つ相手・拠点の守備と攻める軍に数えない（部隊の Attribute の `Fukuhei`）。相手が KishuRadius 以内に来たら奇襲し（判定は `src/shared/Fukuhei.luau`）、相手の部隊の士気を KishuShiki だけずっと下げて交戦を始める。窓口の `SetHikeiMochikomi`・`UseHikei`・`WarpToKyoten`・`WarpToHikeiChiten`・`SetHikeiRemaining` で確かめる
- 効果音は `src/shared/Sounds.luau` の登録表に置き、`src/shared/SoundPlayer.luau` で名前を指定して鳴らす。戦闘の音はサーバーが場所を指定して鳴らし、画面の音はクライアントが本人にだけ鳴らす。音量は `Config.luau` の Sound 節
- BGM は `src/shared/Bgm.luau` の登録表に場面（ロビー・イベントシーン・戦闘・勝利・敗北）ごとに置き、クライアントの BgmController が本人にだけ流す。場面は `Bgm.sceneFor` が PartyState のフェーズと StageResult の勝敗から決め、待機中の人はロビーの曲にする。切り替えはフェードで、音量とフェードの長さは `Config.luau` の Bgm 節。流している場面は `SoundService.Bgm` の Attribute `Scene` で確かめる
- 武器は `src/shared/Appearance.luau` が、キャラクター定義の武器のモデルを右手の握りの Attachment に溶接して持たせる。見た目専用で、当たり判定は持たない
- モーションの ID は `src/shared/Motions.luau` の一覧に置く。待機と移動は Roblox 公式の Ninja パックで、仮の見た目の HumanoidDescription に入れて当てる
- 行動のモーションは、クライアントの MotionController が自分のキャラクターの Attribute（`Action`・`ActionStep`・`ActionDuration`・`ActionStartedAt`）を見て、行動の長さに合わせた速さで再生する。判定の時刻と移動量は `Config.luau` のままで、モーションには左右されない
