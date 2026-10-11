--!strict
-- 両軍の下忍の個体と、窓口で出した敵（下忍と上忍）の体・動き・被ダメージ。体はサーバーの Humanoid のモデル
-- （#15 の案A。描き方は #15 で決める）で、使い終えたら壊さずにプールへ返して使い回す（下の「プール」）。
-- 体を出すのは、実体化圏の下忍の個体（GeninKotaiService が両軍の部隊から出す。spawnKotai）と、
-- 窓口で出した敵（SpawnEnemy・SpawnEnemies）。戦闘のフェーズが終わったら（決着・ロビーへの帰還・全員の離脱）体をプールへ返す。
-- ここは Humanoid に依存する部分（体の生成とプール、歩き、攻撃を受けた反応、倒れる）だけを持ち、部隊から何人出すか・
-- 兵数の数え方は GeninKotaiService と ReplicatedStorage.Shared.GeninKotai が持つ。描き方が変わったら、ここを差し替える。
--
-- 軍
-- - 体ごとに軍を持つ。部隊の下忍の個体は部隊の軍、窓口で出した敵は敵軍
-- - 攻撃判定の対象（getTargets）は軍で絞る。プレイヤーの攻撃と味方軍の上忍・首領の型は敵軍の体にだけ、
--   秘計（大火計・爆破罠）は使った軍の相手の軍の体にだけ当たる
-- - 体はプレイヤーにもほかの体にもぶつからない（CollisionGroups の、敵軍は Enemy、味方軍は Mikatagun）。
--   体で押したり上に乗ったりしない
--
-- 動き
-- - 敵軍の体は、近くのプレイヤー（Config.luau の EnemyAI 節の AggroRange 以内。交戦中の部隊の個体は Zensen 節の
--   AggroRange 以内）へ近づいて攻撃するだけである。
--   プレイヤーへの攻撃は DamageService の被ダメージの窓口に渡す。重ならないよう、プレイヤーの手前で止まり、
--   ほかの体とも離れて囲む（立ち位置の計算は EnemySpacing）
-- - 味方軍の下忍の個体は、プレイヤーを狙わず、プレイヤーを攻撃しない（攻撃トークンの候補にも入らない）。
--   交戦中は前線に並び、敵軍の下忍と向かい合って攻撃の動作をする（下の「交戦」）
-- - 狙う相手がいない部隊の下忍の個体（味方軍はいつも）は、交戦していなければ、部隊の位置（setHomeProvider で登録した
--   関数で引く）の周りの自分の位置へ戻り、部隊について歩く。窓口で出した敵はその場にとどまる
--
-- 交戦（#89。並びの計算は ReplicatedStorage.Shared.Zensen、数値は Config.luau の Zensen 節）
-- - 交戦中の部隊（setKosenProvider で登録した関数で引く）の個体のうち、プレイヤーを狙っていないものは、考える間隔ごとに
--   交戦の組ごとに前線と控えに並べる。並ぶ位置へ寄り、相手の部隊の方を向く。前線に並ぶのは部隊ごとに前線幅
--   （Kosen 節の Zensenhaba）体まで
-- - 並ぶ位置に着いた前線の個体は、向かい合う相手の個体へ、間隔をあけて攻撃の動作をする。当たり判定は無く、ダメージも
--   反応も起こさない。攻撃の動作は下忍の攻撃のモーション（Motions.Genin.Attack）を個体の Animator で再生する。
--   ID が 0 の間（読み込めなかったときも）は、正面に小さな斬撃の仮エフェクト（Vfx.slash。当たり判定・接触・空間クエリから
--   外したパーツ）を出す
-- - 交戦中の部隊の敵軍の個体は、Zensen 節の AggroRange 以内のプレイヤーを狙い（攻撃トークンに従う）、狙っている間は
--   並ばない。プレイヤーが離れたら前線へ戻る（窓口の SetKosenAggro false の間は狙わない。確認用）
-- - 交戦の損害の演出（defeatZensen）で、部隊の前線の個体を倒れさせる。向かい合う相手が、その時に攻撃の動作をする
-- - 交戦が決着したら（交戦の様子を引けなくなったら）、部隊について歩く動きと、プレイヤーを狙う動きに戻る
--
-- モーション（#88。項目と ID は ReplicatedStorage.Shared.Motions の Genin、数値は Config.luau の GeninMotion 節）
-- - 下忍の体（両軍の部隊の下忍の個体と、窓口で出した下忍）に、サーバーから体の Animator で流す（#15 の案A。
--   トラックはクライアントへ複製される）。ID が 0 の項目は流さない。窓口で出した上忍には流さない
-- - 待機（Idle）と移動（Run）はくり返し流す。Interval ごとに体の水平の速さを見て、MoveThreshold を超えたら移動にし、
--   止まってから IdleDelay 秒たったら待機にする（のけぞりと起き上がりの間と、止まって攻撃するときは、すぐ待機にする）。
--   移動は、歩く速さと RunSpeed の比の速さで流す
-- - 攻撃（Attack）は、プレイヤーを攻撃したときと前線の攻撃の動作で1回流す
-- - 被弾の反応（Flinch・Knockback・Launch・Down・GetUp）は、反応（Hanno）の状態が変わったとき（onStateChanged）に、
--   攻撃より上の優先度で1回流す。前の反応のモーションと攻撃のモーションは止め、反応が終わったら止める
-- - 飛んでいる間と倒れている間と倒れた後は、待機と移動を止める。倒れたら攻撃も止める（被弾の反応は続ける）。
--   体をプールへ返すときは、すべて止める（使い回した体は、何も流れていない状態から出る）
-- - 読み込んだトラックは、体ごと・項目ごとに覚えて使い回す（プールをまたいでも残し、体を壊したら手放す）。
--   ID が変わっていたら読み込み直す
-- - 窓口の SetGeninMotion で ID を差し替え（サーバーを止めるまで続く）、DumpGeninMotion で ID と、項目ごとに
--   流している体の数を確かめる
--
-- 倒れたとき
-- - プレイヤーが倒した体は、撃破数を足し、gekiha で種類・軍（倒れた体の軍）・倒れた位置・倒したプレイヤー・部隊 ID を知らせる
-- - 部隊の下忍の個体が倒れたら（倒した人によらず）、kotaiDefeated で知らせる（GeninKotaiService が部隊の兵数を1減らす）
-- - 交戦の損害の演出で倒した個体は、部隊の兵数を交戦の計算で減らし終えているので、撃破数・兵数・拠点の耐久・救援数に
--   数えない（gekiha でも kotaiDefeated でも知らせない）
-- - 個体を消す（remove。部隊へ戻す）ときは、倒れたことにしない（撃破数・兵数・知らせは動かない）
-- - 体は Humanoid の Dead の状態にしない（Dead になった Humanoid は、体力を戻しても生き返らないことがあり、使い回せない）。
--   体力が 0 になったことを HealthChanged で受けて倒れたときの処理を1回だけ走らせ、Humanoid を自分で力を出さない状態
--   （Physics）にしてその場に倒す（Dead のときと同じ倒れ方）。飛んでいる・倒れている体は、Hanno が倒れたまま残す
-- - 倒れた体は CorpseLifetime 秒だけ見せてから、プールへ返す
-- - 奈落に落ちた体は倒れたことにして、すぐにプールへ返す（部品が消えていれば壊す）。飛んでいる体は Hanno が見つけ、
--   歩いて落ちた体は、考える間隔ごとに HumanoidRootPart が workspace から外れた体を探して見つける（sweepFallen）
--
-- 攻撃トークン（計算は KogekiToken、数値は Config.luau の KogekiToken 節）
-- - 1人のプレイヤーを同時に攻撃できる敵軍の下忍は、そのプレイヤーの攻撃トークンを持つ下忍だけ（PerPlayer 体まで）
-- - 攻撃トークンを持たない下忍は、攻撃する下忍より WaitGap だけ外で囲んで待ち、攻撃しない
-- - 攻撃した下忍は攻撃トークンを返す。倒れた下忍、吹き飛んで倒れている下忍、ほかのプレイヤーを狙った下忍、
--   Range より離れた下忍、MaxHold 秒たっても攻撃しない下忍も返し、近い下忍へ渡る
-- - 攻撃トークンを持つ下忍は、待っている下忍を避けずに、攻撃が届く距離の内で止まる
-- - 上忍は攻撃トークンなしで攻撃する
--
-- 攻撃を受けた敵の反応（のけぞり・吹き飛び・打ち上げ・ダウン・起き上がり）は Combat/Hanno が動かす。
-- 上忍は Config.luau の EnemyReaction 節の JoninScale を掛けた初速で短く飛び、JoninFlinchScale を掛けた秒数だけのけぞる
-- （0 ならのけぞらない）。反応の最中は、近づくことも攻撃することもしない。
-- 上忍と首領の個体（データの上忍と首領。JoninKotaiService）とは別。窓口で出した上忍は確かめ用の仮の敵である
--
-- 毒（酉花の奥義「毒手裏剣」。数値は Config.luau の Poison 節）
-- - 毒の間は Interval 秒ごとに Damage を与える。とどめは毒を付けたプレイヤーの撃破に数える
-- - 毒の間にもう一度付けると、残りの時間を Duration に戻す。毒の間は緑の煙（Fire）の仮の見た目を出す
--
-- プール（#83。数え方は ReplicatedStorage.Shared.KotaiPool、数値は Config.luau の KotaiPool 節）
-- - 使い終えた体は、ひな形（種類・軍・色。部隊の下忍の個体は軍のクランの色）ごとのプールへ返し、次に出すときに取り出す。
--   返すのは、部隊へ戻したとき（remove・ClearEnemies）、倒れた姿を見せ終えたとき、戦闘のフェーズが終わって片付けるとき。
--   プールが MaxIdle まで埋まっていれば、返した体は壊す
-- - 取り出した体は、新しく作った体と同じ状態に戻してから出す（名前・体力・速さ・頭上の表示・Humanoid の状態・反応・毒の煙・
--   ハイライト・衝突のグループ・固定・物理の持ち主・速度。部隊の中の自分の位置は出すたびに決め直す）。
--   攻撃トークンの記録は、返すときに体の名前ごと消す（名前は出すたびに振り直す）
-- - 遅れて届く攻撃（飛び道具）が、届くまでに使い回された体に当たらないよう、体を出した回の印を useOf で引ける
-- - プールの体は workspace の KotaiPool フォルダに、区画とロビーから遠い地面の下（FallenPartsDestroyHeight より上）で
--   固定して置く。workspace の外（nil や ServerStorage）に置くと、取り出すたびに体全体をクライアントへ複製し直すため
--   （ADR 0003 の通信量）。StreamingEnabled の場所なので、プールに置いている間だけ体の ModelStreamingMode を
--   Persistent にして、遠くに置いてもクライアントの読み込みから外さない（外れると、取り出したときに体全体を送り直す）。
--   出ている間は、新しく作った体と同じ扱い（ひな形の ModelStreamingMode）に戻す
-- - プールの体は敵の表（enemies）に入れないので、攻撃判定・狙い・攻撃トークン・窓口の対象にならない。光線（Hanno）からも外す
-- - 出撃したら、そのステージの両軍の体を先読みの数（Prewarm）まで作ってプールに置く。1フレームに PrewarmPerFrame 体ずつ作る。
--   ひな形は起動時に作ってあるので、複製するだけで待たない。そのステージで使わないひな形のプールの体は壊す
-- - 窓口の DumpGeninPool で、ひな形ごとの作った数・取り出した数・返した数・壊した数・今プールにある数を確かめる

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Appearance = require(ReplicatedStorage.Shared.Appearance)
local Characters = require(ReplicatedStorage.Shared.Characters)
local Colors = require(ReplicatedStorage.Shared.Colors)
local Config = require(ReplicatedStorage.Shared.Config)
local EnemySpacing = require(ReplicatedStorage.Shared.EnemySpacing)
local Ground = require(ReplicatedStorage.Shared.Ground)
local Gun = require(ReplicatedStorage.Shared.Gun)
local HitShape = require(ReplicatedStorage.Shared.HitShape)
local KogekiToken = require(ReplicatedStorage.Shared.KogekiToken)
local KotaiPool = require(ReplicatedStorage.Shared.KotaiPool)
local Motions = require(ReplicatedStorage.Shared.Motions)
local StagePhase = require(ReplicatedStorage.Shared.StagePhase)
local Stages = require(ReplicatedStorage.Shared.Stages)
local Zensen = require(ReplicatedStorage.Shared.Zensen)
local DebugCommand = require(script.Parent.Parent.DebugCommand)
local DamageService = require(script.Parent.DamageService)
local PlayerService = require(script.Parent.PlayerService)
local StageService = require(script.Parent.StageService)
local CollisionGroups = require(script.Parent.Parent.CollisionGroups)
local Hanno = require(script.Parent.Parent.Combat.Hanno)
local Vfx = require(script.Parent.Parent.Combat.Vfx)

type EnemyDef = Config.EnemySection

-- 敵の種類。能力値は Config.luau、窓口で出した敵を見分けるための色はここに置く（部隊の下忍の個体はクランの色）
local ENEMY_DEFS: { [string]: EnemyDef } = {
	Genin = Config.Genin,
	Jonin = Config.Jonin,
}
local ENEMY_COLORS: { [string]: Color3 } = {
	Genin = Color3.fromRGB(70, 90, 160),
	Jonin = Color3.fromRGB(170, 40, 40),
}

type Enemy = {
	-- 種類（Genin・Jonin）
	kind: string,
	-- 軍。部隊の下忍の個体は部隊の軍、窓口で出した敵は敵軍
	gun: Gun.Gun,
	-- 体の色（部隊の下忍の個体はクランの色。確認用）
	color: Color3,
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	def: EnemyDef,
	-- 攻撃判定で使う水平の半径
	radius: number,
	-- 同じ位置に重なったほかの敵からずらす向き（ラジアン）。敵ごとに出したときに決める
	spin: number,
	lastAttack: number,
	lastHitBy: Player?,
	-- 攻撃を受けた反応（Combat/Hanno）
	body: Hanno.Body,
	-- 出てから受けた攻撃の数（確認用）
	hits: number,
	-- 最初に攻撃を受けた時刻（os.clock。確認用）
	firstHitAt: number?,
	-- 毒の間なら、その中身
	poison: Poison?,
	-- 部隊の下忍の個体なら、その部隊 ID。窓口で出した敵は nil
	butai: string?,
	-- 部隊の位置から、戦う相手がいないときに戻る自分の位置までのずれ
	offset: Vector3,
	-- とどめが、兵数の減少を拠点の耐久に数えない攻撃（秘計の爆破罠）だったか
	lastHitSilent: boolean,
	-- 交戦中の部隊の個体を前線か控えに並べたなら、最後の判断で決めた並ぶ位置（プレイヤーを狙っていれば nil）
	zensen: ZensenOrder?,
	-- 前線で次に攻撃の動作をする時刻（os.clock）。並ぶ位置に着くまでは nil
	swingAt: number?,
	-- 最後の判断で狙ったプレイヤー（確認用）
	target: Player?,
	-- 交戦の損害の演出で倒したか（部隊の兵数は交戦の計算で減らし終えているので、倒れても知らせない）
	kosenSongai: boolean?,
}

-- 交戦中の部隊の個体の並ぶ位置（Zensen の並び）
type ZensenOrder = {
	-- 並ぶ位置（水平。高さは問わない）
	point: Vector3,
	-- 向く向き（水平の単位ベクトル。自分の部隊から相手の部隊への向き）
	look: Vector3,
	-- 列（0 が前線、1 から後ろへ控えの列）と、列の中の位置の番号。次の並びに引き継ぐ
	row: number,
	column: number,
	-- 前線の個体か（false なら控え）
	front: boolean,
	-- 前線の個体が向かい合う相手の個体
	aite: Model?,
}

-- 交戦中の部隊の様子（setKosenProvider で登録した関数が返す）
export type KosenInfo = {
	-- 交戦の相手の部隊 ID
	aite: string,
	-- 自分の部隊と相手の部隊の水平の位置
	position: Zensen.Point,
	aitePosition: Zensen.Point,
}

-- 交戦中の部隊の個体の様子（窓口の確認用。kosenKotaiOf）
export type KosenKotai = {
	name: string,
	-- 前線の個体か（控えは false）。前線にも控えにも並べていなければ nil
	front: boolean?,
	-- 前線の個体が向かい合う相手の個体の名前
	aite: string?,
	-- 個体の正面（水平の向き）。倒れているなど、正面が水平に近くなければ nil
	look: Zensen.Point?,
	-- 並ぶ位置までの水平の距離（スタッド）。並べていなければ nil
	distance: number?,
	-- 並ぶ位置に着いているか（着いた個体が相手の部隊の方を向く）。並べていなければ nil
	arrived: boolean?,
	-- 最後の判断で狙ったプレイヤー
	player: Player?,
}

-- 種類・軍・色ごとの体のひな形と、そのひな形の体のプール
type Template = {
	key: string,
	kind: string,
	gun: Gun.Gun,
	color: Color3,
	model: Model,
	-- 体の衝突のグループ
	group: string,
	pool: KotaiPool.Pool<Model>,
}

-- 作った体。壊すまで、プール（KotaiPool フォルダ）と、出ている間（enemies と corpses）を行き来する
type Rig = {
	template: Template,
	humanoid: Humanoid,
	root: BasePart,
	-- 出した回数（窓口の確認用。2 以上なら使い回した体）
	uses: number,
	-- 下忍のモーションを流している様子。体を壊すまで、出し入れをまたいで使い回す
	motion: MotionState,
}

-- 体に読み込んだ、下忍のモーションの項目1つのトラック
type LoadedTrack = {
	-- 読み込んだときの ID（窓口で差し替えたら読み込み直す）
	id: number,
	track: AnimationTrack,
}

-- 体ごとの、下忍のモーションを流している様子（ヘッダーの「モーション」）
type MotionState = {
	-- 項目ごとに読み込んだトラック
	tracks: { [string]: LoadedTrack },
	-- 流す待機か移動の項目（Idle・Run）。止めている間（倒れた後・飛んでいる間・倒れている間・プール）は nil
	locomotion: string?,
	-- 流している待機か移動のトラック（ID が 0 なら nil）
	locomotionTrack: AnimationTrack?,
	-- 体の水平の速さが MoveThreshold 以下になった時刻（os.clock）。動いている間は nil
	stillSince: number?,
	-- 流している攻撃のトラック
	attackTrack: AnimationTrack?,
	-- 流している被弾の反応のトラック
	reactionTrack: AnimationTrack?,
}

-- 毒の中身
type Poison = {
	-- 毒を付けたプレイヤー
	attacker: Player?,
	-- 次に毒のダメージを与える時刻と、毒が切れる時刻（os.clock）
	nextTick: number,
	untilTime: number,
}

-- 攻撃を当てたときの反応の中身
export type Hit = Hanno.Hit

-- 敵が考えるときに狙うプレイヤー
type Target = {
	player: Player,
	root: BasePart,
}

local EnemyService = {}

-- プレイヤー（味方軍）を狙って攻撃する体の軍。窓口で出した敵もこの軍にする
local AITE_GUN: Gun.Gun = "Tekigun"

local gekihaEvent = Instance.new("BindableEvent")
-- プレイヤーが体を倒したときに、種類（Genin・Jonin）・倒れた体の軍・倒れた位置（Vector3）・倒したプレイヤー・部隊 ID
-- （部隊の下忍の個体なら。窓口で出した敵は nil）で発火する。救援数と、窓口で出した下忍の拠点の耐久（KyotenService）が受ける
EnemyService.gekiha = gekihaEvent.Event

local kotaiDefeatedEvent = Instance.new("BindableEvent")
-- 部隊の下忍の個体が倒れたときに、モデル・部隊 ID・軍・倒れた位置（Vector3）・とどめを刺したプレイヤー（いなければ nil）・
-- 兵数の減少を拠点の耐久に数えないか（silent）で発火する。倒した人によらず発火する（GeninKotaiService が兵数を1減らす）
EnemyService.kotaiDefeated = kotaiDefeatedEvent.Event

local enemiesFolder: Folder
-- プールの体を置くフォルダと位置（start で決める）
local poolFolder: Folder
local parkCFrame = CFrame.identity
-- 種類・軍・色ごとの体のひな形とプール。色を渡さなければ ENEMY_COLORS の色
local templates: { [string]: Template } = {}
-- 作って、まだ壊していない体
local rigs: { [Model]: Rig } = {}
local radii: { [string]: number } = {}
-- 部隊 ID から部隊の位置を引く関数（GeninKotaiService が登録する）
local homeProvider: ((butaiId: string) -> Vector3?)? = nil
-- 部隊 ID から交戦中の部隊の様子を引く関数（GeninKotaiService が登録する）。交戦していなければ nil を返す
local kosenProvider: ((butaiId: string) -> KosenInfo?)? = nil
-- 交戦中の部隊の敵軍の個体がプレイヤーを狙うか。窓口の SetKosenAggro で切り替える（確認用）
local kosenAggro = true
local enemies: { [Model]: Enemy } = {}
-- 倒れた姿を見せている体（倒れたときの処理を終え、プールへ返すのを待つ）
local corpses: { [Model]: Enemy } = {}
local aliveCount = 0
-- 先読み。最後に先読みしたステージ ID、ひな形ごとの先読みの数、作っている途中か（窓口の確認用）と、
-- 出撃し直したら前の先読みをやめるための番号
local prewarmStage: string? = nil
local prewarmTargets: { [Template]: number } = {}
local prewarming = false
local prewarmRun = 0
-- 敵に振る番号。モデルの名前を種類と番号（Genin1、Jonin2…）にする
local nextNumber = 1
-- 体が動くか（敵軍の体はプレイヤーに近づいて攻撃し、部隊の下忍の個体は部隊について歩く）。
-- 窓口の SetEnemyAI で切り替える（止めても攻撃の反応と毒は進む）
local aiEnabled = true
-- 攻撃トークン。下忍はモデルの名前、プレイヤーは UserId の文字列で引く
local tokens = KogekiToken.new()
-- 最後に考えたときの、プレイヤーのキーごとの攻撃トークンの候補（窓口の DumpKogekiToken で出す）
local lastCandidates: { [string]: { KogekiToken.Candidate } } = {}
-- 攻撃トークンの受け渡しと攻撃を出力に出すか。窓口の LogKogekiToken で切り替える
local logTokens = false
-- 攻撃が届く距離より、この距離（スタッド）だけ手前で止まる
local STAND_OFF_MARGIN = 0.5
-- Humanoid:MoveTo は、止まった状態から歩かせると目標の手前（スタッド。Studio で測ると 0.7〜0.8）で止まる。
-- 攻撃トークンを持つ下忍は、この分だけ内側を目指し、攻撃が届く距離の内で止まる
local ARRIVAL_GAP = 0.8
-- プレイヤーの中心からこの距離（スタッド）より近くにいるときは、1回の判断で進む距離を STEP に抑え、
-- 囲みの輪の上を回り込む
local NEAR_RANGE = 10
local STEP = 3
-- 倒れているときの、地面から HumanoidRootPart の中心までの高さ（体の大きさの倍率を掛ける）
local LIE_HEIGHT = 1
-- 交戦中の個体は、前線か控えの並ぶ位置からこの距離（スタッド）より離れていなければ、着いたとみなして止まる
-- （Humanoid:MoveTo は目標の 0.7〜0.8 スタッド手前で止まるので、それより広くする）
local ZENSEN_TOLERANCE = 1.5
-- 並ぶ位置に着いた個体は、正面と相手の部隊の方の向きのずれがこの角度（度）より大きければ向き直す
local TURN_THRESHOLD = 5
-- 窓口で正面の向きを出すときに、正面が水平に近いとみなす HumanoidRootPart の LookVector の上下の成分の上限
-- （倒れている個体の正面は出さない）
local UPRIGHT_LIMIT = 0.7
-- 下忍のモーションの優先度の名前（Motions.geninPriorityOf）から引く、トラックの優先度
local MOTION_PRIORITIES: { [Motions.GeninPriority]: Enum.AnimationPriority } = {
	Idle = Enum.AnimationPriority.Idle,
	Movement = Enum.AnimationPriority.Movement,
	Action = Enum.AnimationPriority.Action,
	Action2 = Enum.AnimationPriority.Action2,
}
-- 毒の間に出す緑の煙の名前と色
local POISON_NAME = "Doku"
local POISON_COLOR = Color3.fromRGB(110, 210, 70)
local POISON_SECONDARY_COLOR = Color3.fromRGB(40, 110, 30)
-- プールの体を置く水平の位置（区画とロビーから遠い位置）と、FallenPartsDestroyHeight から上げる高さ（スタッド）。
-- 地面の下の、体が消える高さより上に置く
local POOL_X = -20000
local POOL_Z = -20000
local POOL_LIFT = 100

-- 種類の能力値と頭上の表示を Humanoid に当てる（ひな形を作るときと、体を出すとき）
local function applyDef(humanoid: Humanoid, kind: string, def: EnemyDef)
	humanoid.DisplayName = def.DisplayName
	humanoid.MaxHealth = def.MaxHealth
	humanoid.Health = def.MaxHealth
	humanoid.WalkSpeed = def.WalkSpeed
	-- 下忍は頭上表示を出さず、上忍だけ名前と体力バーを出す
	humanoid.DisplayDistanceType = if kind == "Jonin"
		then Enum.HumanoidDisplayDistanceType.Viewer
		else Enum.HumanoidDisplayDistanceType.None
end

local function buildTemplate(kind: string, def: EnemyDef, color: Color3): Model
	local description = Instance.new("HumanoidDescription")
	description.HeadColor = color
	description.TorsoColor = color
	description.LeftArmColor = color
	description.RightArmColor = color
	description.LeftLegColor = Color3.fromRGB(40, 40, 40)
	description.RightLegColor = Color3.fromRGB(40, 40, 40)
	description.HeightScale = def.Scale
	description.WidthScale = def.Scale
	description.DepthScale = def.Scale
	description.HeadScale = def.Scale

	local model = Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	model.Name = kind

	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	applyDef(humanoid, kind, def)
	humanoid.BreakJointsOnDeath = false

	return model
end

-- 種類・軍・色の体のひな形。初めて使う組み合わせなら、ひな形と空のプールを作って覚える
local function templateFor(kind: string, gun: Gun.Gun, color: Color3?): Template
	local paint = color or ENEMY_COLORS[kind]
	local key = `{kind}/{gun}/{paint:ToHex()}`
	local existing = templates[key]
	if existing then
		return existing
	end
	local model = buildTemplate(kind, ENEMY_DEFS[kind], paint)
	-- 体はプレイヤーにもほかの体にもぶつからない。軍のグループにするのは、秘計の落石の岩が相手の軍の体だけを止めるため。
	-- 複製した体もこのグループになる
	local group = CollisionGroups.kotaiGroupOf(gun)
	CollisionGroups.apply(model, group)
	local template: Template = {
		key = key,
		kind = kind,
		gun = gun,
		color = paint,
		model = model,
		group = group,
		pool = KotaiPool.new(Config.KotaiPool.MaxIdle[gun]),
	}
	templates[key] = template
	return template
end

-- position から range（スタッド）以内で一番近い、倒れていないプレイヤー
local function findNearestTarget(position: Vector3, range: number): (Player?, BasePart?)
	local bestPlayer, bestRoot, bestDistance = nil, nil, range
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if humanoid and root and humanoid.Health > 0 then
			local distance = (root.Position - position).Magnitude
			if distance < bestDistance then
				bestPlayer, bestRoot, bestDistance = player, root, distance
			end
		end
	end
	return bestPlayer, bestRoot
end

-- 攻撃トークンを持たずに待っている下忍か（味方軍の下忍の個体は攻撃トークンを持たないので、いつも true）
local function isWaiting(enemy: Enemy): boolean
	return enemy.kind == "Genin" and KogekiToken.ownerOf(tokens, enemy.model.Name) == nil
end

-- 立ち位置を決めるときの近くの体（体が重なりうる距離にいる、生きている体。軍によらない）。
-- attackersOnly なら待っている下忍を除く（攻撃する下忍が、外側で待つ下忍や味方軍の下忍の個体にずらされて
-- 攻撃が届かなくならないように）
local function neighborsOf(enemy: Enemy, attackersOnly: boolean): { EnemySpacing.Neighbor }
	local list = {}
	local position = enemy.root.Position
	for _, other in enemies do
		if other ~= enemy and other.humanoid.Health > 0 and not (attackersOnly and isWaiting(other)) then
			local p = other.root.Position
			local reach = enemy.radius + other.radius
			if math.abs(p.X - position.X) < reach and math.abs(p.Z - position.Z) < reach then
				table.insert(list, { x = p.X, z = p.Z, radius = other.radius })
			end
		end
	end
	return list
end

local function removePoisonLook(enemy: Enemy)
	local fire = enemy.root:FindFirstChild(POISON_NAME)
	if fire then
		fire:Destroy()
	end
end

-- 毒の間なら、間隔ごとに毒のダメージを与える。毒が切れたら見た目を外す
local function updatePoison(enemy: Enemy, now: number)
	local poison = enemy.poison
	if not poison then
		return
	end
	while now >= poison.nextTick and poison.nextTick <= poison.untilTime and enemy.humanoid.Health > 0 do
		poison.nextTick += Config.Poison.Interval
		if poison.attacker and poison.attacker.Parent then
			enemy.lastHitBy = poison.attacker
		end
		enemy.lastHitSilent = false
		enemy.humanoid:TakeDamage(Config.Poison.Damage)
	end
	if now >= poison.untilTime or enemy.humanoid.Health <= 0 then
		enemy.poison = nil
		removePoisonLook(enemy)
	end
end

-- 攻撃トークンで引くプレイヤーのキー
local function keyOf(player: Player): string
	return tostring(player.UserId)
end

local function horizontalDistance(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- 吹き飛んで飛んでいる・倒れている・起き上がっている下忍は、攻撃トークンを持たない（のけぞりの間は持ったまま）
local function isDowned(enemy: Enemy): boolean
	local kind = Hanno.kindOf(enemy.body)
	return kind == "Air" or kind == "Down" or kind == "GetUp"
end

local function logToken(message: string)
	if logTokens then
		print(`[KogekiToken] {message}`)
	end
end

-- center から point までの水平の距離が maxReach より遠ければ、同じ向きで maxReach の位置へ寄せる
local function clampReach(point: EnemySpacing.Point, center: EnemySpacing.Point, maxReach: number): EnemySpacing.Point
	local dx, dz = point.x - center.x, point.z - center.z
	local reach = math.sqrt(dx * dx + dz * dz)
	if reach <= maxReach or reach < 1e-6 then
		return point
	end
	return { x = center.x + dx / reach * maxReach, z = center.z + dz / reach * maxReach }
end

-- 攻撃トークンを、各プレイヤーを狙っている下忍に合わせて返したり渡したりする
local function updateTokens(candidates: { [Player]: { KogekiToken.Candidate } }, now: number)
	table.clear(lastCandidates)
	for _, player in Players:GetPlayers() do
		local key = keyOf(player)
		local list = candidates[player] or {}
		lastCandidates[key] = list
		local changes = KogekiToken.update(tokens, key, list, now)
		local parts = {}
		if #changes.released > 0 then
			table.insert(parts, `{table.concat(changes.released, "、")} が返した`)
		end
		if #changes.given > 0 then
			table.insert(parts, `{table.concat(changes.given, "、")} が受け取った`)
		end
		if #parts > 0 then
			local count = KogekiToken.count(tokens, key)
			logToken(`{player.Name}: {table.concat(parts, "、")}（持っている {count} 体）`)
		end
	end
end

-- 個体を水平の向き look（単位ベクトル）へ向ける。向きのずれが TURN_THRESHOLD（度）より小さければ向き直さない
local function faceToward(enemy: Enemy, look: Vector3)
	local current = enemy.root.CFrame.LookVector
	local flat = Vector3.new(current.X, 0, current.Z)
	if flat.Magnitude > 1e-3 and flat.Unit:Dot(look) >= math.cos(math.rad(TURN_THRESHOLD)) then
		return
	end
	local here = enemy.root.Position
	enemy.root.CFrame = CFrame.lookAt(here, here + look)
end

-- 体の Animator に、下忍のモーションの項目 item の今の ID のトラックを読み込む。読み込んだものは体ごと・項目ごとに
-- 使い回し（プールをまたいでも残す）、ID が変わっていたら前のトラックを捨てて読み込み直す。ID が 0 か、読み込めなければ nil
local function trackFor(rig: Rig, item: string): AnimationTrack?
	local id = Motions.geninIdOf(item)
	local tracks = rig.motion.tracks
	local loaded = tracks[item]
	if loaded then
		if loaded.id == id then
			return loaded.track
		end
		tracks[item] = nil
		loaded.track:Stop(0)
		loaded.track:Destroy()
	end
	if id <= 0 then
		return nil
	end
	local animator = rig.humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		local created = Instance.new("Animator")
		created.Parent = rig.humanoid
		animator = created
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = `rbxassetid://{id}`
	local ok, result = pcall(function(): AnimationTrack
		return (animator :: Animator):LoadAnimation(animation)
	end)
	if not ok then
		warn(`EnemyService: 下忍のモーション {item}（{id}）を読み込めなかった: {result}`)
		return nil
	end
	local track = result :: AnimationTrack
	tracks[item] = { id = id, track = track }
	return track
end

-- 待機か移動のモーション item をくり返し流す（nil なら止める）。同じ項目を流していれば何もしない（restart なら流し直す）。
-- 移動は、歩く速さと GeninMotion 節の RunSpeed の比の速さで流す。ID が 0 の項目は流さない
local function setLocomotion(rig: Rig, item: string?, restart: boolean?)
	local motion = rig.motion
	if motion.locomotion == item and not restart then
		return
	end
	local fade = Config.GeninMotion.LocomotionFade
	local previous = motion.locomotionTrack
	motion.locomotion = item
	motion.locomotionTrack = nil
	if previous then
		previous:Stop(fade)
	end
	if not item then
		return
	end
	local track = trackFor(rig, item)
	if not track then
		return
	end
	track.Priority = MOTION_PRIORITIES[Motions.geninPriorityOf(item)]
	track.Looped = true
	local speed = if item == "Run"
		then Motions.geninRunPlaybackOf(rig.humanoid.WalkSpeed, Config.GeninMotion.RunSpeed)
		else 1
	track:Play(fade, 1, speed)
	motion.locomotionTrack = track
end

-- 体の水平の速さ（スタッド/秒）。固定している体（飛んでいる間・倒れている間・起き上がっている間）は止まっているとみなす
local function horizontalSpeedOf(root: BasePart): number
	if root.Anchored then
		return 0
	end
	local velocity = root.AssemblyLinearVelocity
	return math.sqrt(velocity.X * velocity.X + velocity.Z * velocity.Z)
end

-- 体の水平の速さで、待機と移動のどちらを流すかを選び直す（Motions.geninLocomotionOf）。
-- 移動を流している体は、止まってから GeninMotion 節の IdleDelay 秒たつまで移動のまま
local function chooseLocomotion(rig: Rig, now: number)
	local params = Config.GeninMotion
	local motion = rig.motion
	local speed = horizontalSpeedOf(rig.root)
	if speed > params.MoveThreshold then
		motion.stillSince = nil
	elseif not motion.stillSince then
		motion.stillSince = now
	end
	local stillSince = motion.stillSince
	local stillFor = if stillSince then now - stillSince else 0
	setLocomotion(
		rig,
		Motions.geninLocomotionOf(motion.locomotion, speed, stillFor, params.MoveThreshold, params.IdleDelay)
	)
end

-- 下忍の体の待機と移動のモーションを、今の様子で決め直す（Motions.geninLocomotionMode）。倒れた体と、飛んでいる間・
-- 倒れている間は止める。のけぞりと起き上がりの間はその場で止めているので待機にし、反応の最中でなければ体の速さで選ぶ
local function refreshLocomotion(enemy: Enemy, now: number)
	local rig = rigs[enemy.model]
	if not rig then
		return
	end
	local alive = enemies[enemy.model] == enemy and enemy.humanoid.Health > 0
	local mode = if alive then Motions.geninLocomotionMode(Hanno.kindOf(enemy.body)) else "None"
	if mode == "Speed" then
		chooseLocomotion(rig, now)
	elseif mode == "Idle" then
		setLocomotion(rig, "Idle")
	else
		setLocomotion(rig, nil)
	end
end

-- 間隔ごとに、出ている下忍の体の待機と移動を選び直す
local function updateLocomotion(now: number)
	for _, enemy in enemies do
		if enemy.kind == "Genin" then
			refreshLocomotion(enemy, now)
		end
	end
end

-- 下忍の攻撃のモーション（Motions.Genin.Attack）を1回流す。流したら true（下忍でない体と、ID が 0 か読み込めなければ false）
local function playAttack(enemy: Enemy): boolean
	local rig = rigs[enemy.model]
	if enemy.kind ~= "Genin" or not rig then
		return false
	end
	-- 止まって攻撃する体は、止まってからの IdleDelay 秒を待たずに待機にする（走る足のまま攻撃しないように）
	if rig.motion.locomotion == "Run" and horizontalSpeedOf(rig.root) <= Config.GeninMotion.MoveThreshold then
		setLocomotion(rig, "Idle")
	end
	local track = trackFor(rig, "Attack")
	if not track then
		return false
	end
	track.Priority = MOTION_PRIORITIES[Motions.geninPriorityOf("Attack")]
	track.Looped = false
	track:Play(Config.GeninMotion.ActionFade)
	rig.motion.attackTrack = track
	return true
end

-- 被弾の反応のモーション item を、攻撃より上の優先度で1回流す（nil なら止める）。前の反応のモーションは止め、
-- 反応を始めたら攻撃のモーションも止める。ID が 0 の項目は流さない
local function playReaction(rig: Rig, item: string?)
	local motion = rig.motion
	local fade = Config.GeninMotion.ActionFade
	local previous = motion.reactionTrack
	motion.reactionTrack = nil
	if previous then
		previous:Stop(fade)
	end
	if not item then
		return
	end
	local attack = motion.attackTrack
	motion.attackTrack = nil
	if attack then
		attack:Stop(fade)
	end
	local track = trackFor(rig, item)
	if not track then
		return
	end
	track.Priority = MOTION_PRIORITIES[Motions.geninPriorityOf(item)]
	track.Looped = false
	track:Play(fade)
	motion.reactionTrack = track
end

-- 反応（Hanno）の状態が変わったら、被弾の反応のモーションを流し（反応が終わったら止め）、待機と移動を決め直す。
-- のけぞりと飛ぶ反応は攻撃を受けるたびに流し直し、ダウンと起き上がりは種類が変わったときだけ流す
local function onHannoChanged(enemy: Enemy, state: Hanno.State?, previous: Hanno.State?)
	local model = enemy.model
	local rig = rigs[model]
	-- プールへ返した体には流さない（倒れた姿を見せている間は流す）
	if not rig or (enemies[model] ~= enemy and corpses[model] ~= enemy) then
		return
	end
	local kind = if state then state.kind else nil
	if Motions.geninReactionRestarts(if previous then previous.kind else nil, kind) then
		playReaction(rig, Motions.geninReactionOf(kind, if state then state.reaction else nil))
	end
	refreshLocomotion(enemy, os.clock())
end

-- 倒れた体の、待機と移動と攻撃のモーションを止める（被弾の反応のモーションは、倒れたまま残す間も続ける）
local function stopActing(rig: Rig)
	setLocomotion(rig, nil)
	local motion = rig.motion
	local attack = motion.attackTrack
	motion.attackTrack = nil
	if attack then
		attack:Stop(Config.GeninMotion.ActionFade)
	end
end

-- 体のモーションをすべてすぐに止める（体をプールへ返すとき）。使い回した体は、何も流れていない状態から出る
local function stopMotions(rig: Rig)
	local motion = rig.motion
	motion.locomotion = nil
	motion.locomotionTrack = nil
	motion.stillSince = nil
	motion.attackTrack = nil
	motion.reactionTrack = nil
	for _, loaded in motion.tracks do
		loaded.track:Stop(0)
	end
end

-- 交戦の前線の個体の攻撃の動作。下忍の攻撃のモーション（Motions.Genin.Attack）を個体の Animator で再生する。
-- モーションがまだ無い（ID が 0 か、読み込めない）間は、正面 look に小さな斬撃の仮エフェクトを出す。
-- どちらも見た目だけで、当たり判定は無い（プレイヤーにも個体にも当たらず、ダメージも反応も起こさない）
local function swing(enemy: Enemy, look: Vector3)
	if not playAttack(enemy) then
		Vfx.slash(enemy.root.Position, look)
	end
end

-- 次に攻撃の動作をする時刻。Zensen 節の間隔に、乱数の秒数を足す（前線の個体がそろって振らないように）
local function nextSwingTime(now: number): number
	return now + Config.Zensen.AttackInterval + math.random() * Config.Zensen.AttackRandom
end

-- 交戦中の部隊の個体を、前線か控えの並ぶ位置へ寄せ、相手の部隊の方を向かせる。並ぶ位置に着いた前線の個体は、
-- 向かい合う相手の個体がいれば、間隔をあけて攻撃の動作をする（当たり判定は無い）
local function holdZensen(enemy: Enemy, order: ZensenOrder, now: number)
	local position = enemy.root.Position
	if horizontalDistance(position, order.point) > ZENSEN_TOLERANCE then
		enemy.humanoid:MoveTo(Vector3.new(order.point.X, position.Y, order.point.Z))
		enemy.swingAt = nil
		return
	end
	enemy.humanoid:Move(Vector3.zero)
	faceToward(enemy, order.look)
	local aite = if order.front and order.aite then enemies[order.aite] else nil
	if not aite or aite.humanoid.Health <= 0 then
		enemy.swingAt = nil
		return
	end
	local swingAt = enemy.swingAt
	if not swingAt then
		-- 着いたら、間隔の中のばらけた時刻に最初の攻撃の動作をする
		enemy.swingAt = now + math.random() * (Config.Zensen.AttackInterval + Config.Zensen.AttackRandom)
	elseif now >= swingAt then
		swing(enemy, order.look)
		enemy.swingAt = nextSwingTime(now)
	end
end

local function updateEnemy(enemy: Enemy, now: number, aim: Target?)
	updatePoison(enemy, now)
	if enemy.humanoid.Health <= 0 then
		return
	end
	if not aiEnabled then
		if not enemy.body.state then
			enemy.humanoid:Move(Vector3.zero)
		end
		return
	end
	-- のけぞりが明けたら動き出す。飛んでいる・倒れている・起き上がっている間は Hanno が進める
	if Hanno.busy(enemy.body, now) then
		return
	end
	if not aim then
		-- 交戦中の部隊の個体は、前線か控えに並ぶ
		local order = enemy.zensen
		if order then
			holdZensen(enemy, order, now)
			return
		end
		-- 狙う相手がいない（味方軍の下忍の個体はいつも）部隊の下忍の個体は、部隊の位置の周りの自分の位置へ戻る
		-- （部隊について歩く）。窓口で出した敵はその場にとどまる
		local home = if enemy.butai and homeProvider then homeProvider(enemy.butai) else nil
		if home then
			local goal = home + enemy.offset
			local position = enemy.root.Position
			if horizontalDistance(position, goal) > Config.GeninKotai.HomeRadius then
				enemy.humanoid:MoveTo(Vector3.new(goal.X, position.Y, goal.Z))
				return
			end
		end
		enemy.humanoid:Move(Vector3.zero)
		return
	end
	local targetPlayer, targetRoot = aim.player, aim.root
	-- 下忍は、狙うプレイヤーの攻撃トークンを持つときだけ攻撃する。持たなければ外側で囲んで待つ
	local key = keyOf(targetPlayer)
	local mayAttack = enemy.kind ~= "Genin" or KogekiToken.holds(tokens, key, enemy.model.Name)

	-- プレイヤーの手前で止まり、ほかの敵とも重ならない位置へ向かう
	local standOff = math.min(enemy.radius + Config.EnemyAI.PlayerGap, enemy.def.AttackRange - STAND_OFF_MARGIN)
	-- 攻撃トークンを持つ下忍は、待っている下忍を避けずに、歩いて止まっても攻撃が届く位置を目指す
	local attacking = enemy.kind == "Genin" and mayAttack
	if attacking then
		standOff = math.min(standOff, enemy.def.AttackRange - STAND_OFF_MARGIN - ARRIVAL_GAP)
	elseif not mayAttack then
		standOff += Config.KogekiToken.WaitGap
	end
	local position = enemy.root.Position
	local target = targetRoot.Position
	local here = { x = position.X, z = position.Z }
	local center = { x = target.X, z = target.Z }
	local goal = EnemySpacing.goal(here, enemy.radius, center, standOff, neighborsOf(enemy, attacking), enemy.spin)
	if EnemySpacing.shouldMove(goal, standOff) then
		local point = goal.point
		if attacking then
			-- ほかの攻撃する敵とずらしても、目指す位置は手前の距離より外へ出さない
			point = clampReach(point, center, standOff)
		end
		if goal.distance < NEAR_RANGE then
			point = EnemySpacing.stepToward(here, point, center, standOff, STEP)
		end
		enemy.humanoid:MoveTo(Vector3.new(point.x, position.Y, point.z))
	else
		enemy.humanoid:Move(Vector3.zero)
	end

	if not mayAttack or goal.distance > enemy.def.AttackRange then
		return
	end
	if now - enemy.lastAttack < enemy.def.AttackCooldown then
		return
	end
	enemy.lastAttack = now
	-- 下忍は攻撃のモーションを流す（ID が 0 なら流さない）
	playAttack(enemy)

	DamageService.damage(targetPlayer, {
		origin = enemy.root.Position,
		power = enemy.def.Damage,
		reaction = enemy.def.Reaction,
	})
	-- 攻撃した下忍は攻撃トークンを返し、しばらく休む
	if enemy.kind == "Genin" and KogekiToken.attacked(tokens, key, enemy.model.Name, now) then
		local count = KogekiToken.count(tokens, key)
		logToken(`{targetPlayer.Name}: {enemy.model.Name} が攻撃して返した（持っている {count} 体）`)
	end
end

-- 交戦の組の片側の個体を、並びの計算に渡す形にする。前の並びの位置（列と列の中の位置の番号）も渡して引き継ぐ
local function zensenSideOf(position: Zensen.Point, list: { Enemy }): Zensen.Side
	local kotai: { Zensen.Kotai } = {}
	for _, enemy in list do
		local p = enemy.root.Position
		local previous = enemy.zensen
		table.insert(kotai, {
			id = enemy.model.Name,
			x = p.X,
			z = p.Z,
			row = if previous then previous.row else nil,
			column = if previous then previous.column else nil,
		})
	end
	return { position = position, kotai = kotai }
end

-- 並びの計算の結果を、片側の個体の並ぶ位置にする。byName は両側の個体を名前で引く表（向かい合う相手を引く）
local function applyZensen(list: { Enemy }, layout: Zensen.SideLayout, byName: { [string]: Model })
	local look = Vector3.new(layout.look.x, 0, layout.look.z)
	for _, enemy in list do
		local slot = layout.slots[enemy.model.Name]
		if slot then
			enemy.zensen = {
				point = Vector3.new(slot.point.x, 0, slot.point.z),
				look = look,
				row = slot.row,
				column = slot.column,
				front = slot.front,
				aite = if slot.aite then byName[slot.aite] else nil,
			}
		else
			enemy.zensen = nil
		end
	end
end

-- 交戦中の部隊の個体のうち、プレイヤーを狙っていない生きている個体を、交戦の組ごとに前線と控えに並べる（Zensen.layout）。
-- 交戦していない個体と、プレイヤーを狙っている個体は並べない
local function arrangeZensen(aims: { [Enemy]: Target }, kosenOf: (butaiId: string?) -> KosenInfo?)
	local byButai: { [string]: { Enemy } } = {}
	for _, enemy in enemies do
		local butaiId = enemy.butai
		if butaiId and enemy.humanoid.Health > 0 and not aims[enemy] and kosenOf(butaiId) then
			local list = byButai[butaiId]
			if not list then
				list = {}
				byButai[butaiId] = list
			end
			table.insert(list, enemy)
		else
			enemy.zensen = nil
		end
	end
	local done: { [string]: boolean } = {}
	for butaiId in byButai do
		local info = kosenOf(butaiId)
		if done[butaiId] or not info then
			continue
		end
		done[butaiId] = true
		done[info.aite] = true
		-- 組の中の順は部隊 ID の順にそろえる（2つの部隊が同じ位置にいるときの向きを、どちらから並べても同じにする）
		local firstId, secondId = butaiId, info.aite
		local firstPosition, secondPosition = info.position, info.aitePosition
		if secondId < firstId then
			firstId, secondId = secondId, firstId
			firstPosition, secondPosition = secondPosition, firstPosition
		end
		local firstList, secondList = byButai[firstId] or {}, byButai[secondId] or {}
		local byName: { [string]: Model } = {}
		for _, list in { firstList, secondList } do
			for _, enemy in list do
				byName[enemy.model.Name] = enemy.model
			end
		end
		local layout = Zensen.layout(zensenSideOf(firstPosition, firstList), zensenSideOf(secondPosition, secondList))
		applyZensen(firstList, layout.a, byName)
		applyZensen(secondList, layout.b, byName)
	end
end

-- 考える間隔ごとに、敵軍の体ごとに狙うプレイヤーを決め、攻撃トークンを渡し、交戦中の部隊の個体を前線と控えに並べてから動かす。
-- 味方軍の下忍の個体はプレイヤーを狙わず、攻撃トークンの候補にも入らない（部隊について歩くか、交戦中なら前線と控えに並ぶ）。
-- 交戦中の部隊の敵軍の個体は、Zensen 節の AggroRange 以内のプレイヤーだけを狙い、狙っている間は並ばない
local function thinkOnce(now: number)
	local aims: { [Enemy]: Target } = {}
	local candidates: { [Player]: { KogekiToken.Candidate } } = {}
	-- 部隊 ID ごとの交戦の様子。この判断の中で部隊ごとに1回だけ引く（交戦していなければ false）
	local kosenCache: { [string]: KosenInfo | false } = {}
	local function kosenOf(butaiId: string?): KosenInfo?
		local provider = kosenProvider
		if not butaiId or not provider then
			return nil
		end
		local cached = kosenCache[butaiId]
		if cached == nil then
			cached = provider(butaiId) or false
			kosenCache[butaiId] = cached
		end
		return if cached then cached else nil
	end
	if aiEnabled then
		for _, enemy in enemies do
			if enemy.gun == AITE_GUN and enemy.humanoid.Health > 0 then
				-- 交戦中の部隊の個体は、近くのプレイヤーだけを狙う（窓口の SetKosenAggro false の間は狙わない）
				local range = Config.EnemyAI.AggroRange
				if kosenOf(enemy.butai) then
					range = if kosenAggro then Config.Zensen.AggroRange else 0
				end
				local player, root = findNearestTarget(enemy.root.Position, range)
				if player and root then
					aims[enemy] = { player = player, root = root }
					if enemy.kind == "Genin" and not isDowned(enemy) then
						local list = candidates[player]
						if not list then
							list = {}
							candidates[player] = list
						end
						table.insert(list, {
							id = enemy.model.Name,
							distance = horizontalDistance(enemy.root.Position, root.Position),
						})
					end
				end
			end
		end
		updateTokens(candidates, now)
		arrangeZensen(aims, kosenOf)
	end
	for _, enemy in enemies do
		local aim = aims[enemy]
		enemy.target = if aim then aim.player else nil
		updateEnemy(enemy, now, aim)
	end
end

-- 考える間隔ごとに呼ぶ。1回の失敗で体の動きが止まらないよう、失敗は警告にして次の間隔で続ける
local function think(now: number)
	local ok, err = pcall(thinkOnce, now)
	if not ok then
		warn(`EnemyService: 体の動きを決められなかった: {err}`)
	end
end

-- 体をプールのフォルダに、戦場から離れた位置で固定して置く。Humanoid は自分で力を出さない状態（Physics）にして、
-- 置いている間は歩かせず、状態も変えさせない
local function park(model: Model)
	local rig = rigs[model] :: Rig
	-- プールの間は、遠くに置いてもクライアントの読み込みから外さない（外れると、取り出したときに体全体を送り直す）。
	-- 遠くへ移す前に切り替える
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	rig.root.Anchored = true
	model:PivotTo(parkCFrame)
	model.Parent = poolFolder
	rig.humanoid:ChangeState(Enum.HumanoidStateType.Physics)
end

-- 体が壊されていないか（奈落の下で部品が消えた体や、ほかで壊された体は false）。
-- 作ったばかりで親の無い体は true
local function isIntact(model: Model, rig: Rig): boolean
	return rig.root.Parent == model and rig.humanoid.Parent == model
end

-- 体を壊し、作った体の表から外す
local function destroyBody(model: Model)
	rigs[model] = nil
	model:Destroy()
end

-- 使い終えた体をプールへ返す。プールが上限（MaxIdle）まで埋まっていれば壊す。
-- 出ている間に壊された体（部品が消えた体）は、壊した数に数えて表から外す
local function putBack(model: Model)
	local rig = rigs[model]
	if not rig then
		return
	end
	if not isIntact(model, rig) then
		rigs[model] = nil
		KotaiPool.discard(rig.template.pool)
		model:Destroy()
		return
	end
	-- 次に出すときに何も流れていない状態から始めるよう、モーションをすべて止める
	stopMotions(rig)
	if KotaiPool.put(rig.template.pool, model) then
		park(model)
	else
		destroyBody(model)
	end
end

-- 出していた体を使い終える。反応（Hanno）を止め、毒の煙を消してから、プールへ返す
local function recycle(enemy: Enemy)
	Hanno.forget(enemy.body)
	removePoisonLook(enemy)
	putBack(enemy.model)
end

local function onEnemyDied(enemy: Enemy)
	-- 片付けで先に表から外した敵と、倒れたときの処理を終えた敵は数え直さない
	if enemies[enemy.model] ~= enemy then
		return
	end
	enemies[enemy.model] = nil
	aliveCount -= 1
	-- 持っていた攻撃トークンは、次に考えるときに近い下忍へ渡る
	local owner = KogekiToken.ownerOf(tokens, enemy.model.Name)
	KogekiToken.forget(tokens, enemy.model.Name)
	if owner then
		local holder = Players:GetPlayerByUserId(tonumber(owner) or 0)
		local count = KogekiToken.count(tokens, owner)
		logToken(
			`{if holder then holder.Name else owner}: {enemy.model.Name} が倒れて返した（持っている {count} 体）`
		)
	end
	-- 毒の間に倒れたら、毒の煙を消す
	enemy.poison = nil
	removePoisonLook(enemy)

	local attacker = enemy.lastHitBy
	local living = if attacker and attacker.Parent then attacker else nil
	local position = enemy.root.Position
	if living then
		PlayerService.addGekihasu(living)
		gekihaEvent:Fire(enemy.kind, enemy.gun, position, living, enemy.butai)
	end
	-- 部隊の下忍の個体は、倒した人によらず知らせる（兵数を1減らす）。交戦の損害の演出で倒した個体は、
	-- 兵数を交戦の計算で減らし終えているので知らせない（倒した人もいないので、上の撃破にも数えない）
	if enemy.butai and not enemy.kosenSongai then
		kotaiDefeatedEvent:Fire(enemy.model, enemy.butai, enemy.gun, position, living, enemy.lastHitSilent)
	end

	-- Humanoid を自分で力を出さない状態にして、その場に倒す（Dead の状態にしない体を、Dead のときと同じように倒す）。
	-- 待機と移動と攻撃のモーションは止める（被弾の反応のモーションは、倒れたまま残す間も続ける）
	local rig = rigs[enemy.model]
	if rig and isIntact(enemy.model, rig) then
		stopActing(rig)
		enemy.humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	end
	-- 倒れた姿を CorpseLifetime 秒だけ見せてから、プールへ返す（片付けや奈落で先に返していたら何もしない）
	corpses[enemy.model] = enemy
	task.delay(Config.EnemyAI.CorpseLifetime, function()
		if corpses[enemy.model] == enemy then
			corpses[enemy.model] = nil
			recycle(enemy)
		end
	end)
end

-- 奈落に落ちた体（飛んでいる体は Hanno が、歩いて落ちた体は sweepFallen が呼ぶ）。倒れたことにして
-- （倒れたときの処理は1回だけ）、倒れた姿を見せずにすぐプールへ返す（部品が消えていれば壊す）
local function onFell(enemy: Enemy)
	if enemies[enemy.model] == enemy then
		local rig = rigs[enemy.model]
		if rig and isIntact(enemy.model, rig) then
			enemy.humanoid.Health = 0
		end
		onEnemyDied(enemy)
	end
	if corpses[enemy.model] == enemy then
		corpses[enemy.model] = nil
		recycle(enemy)
	end
end

-- ひな形から体を1つ作る（プールが空のときと、先読み）。体力が 0 になっても Dead の状態にしない
local function createBody(template: Template): Model
	local model = template.model:Clone()
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
	-- Dead の状態にしないので Died は来ない。倒れたことは体力で見る（出ている間、つまり敵の表にある間だけ受ける）。
	-- 知らせが遅れて届いても使い回した後の体を倒さないよう、知らせの値でなく今の体力を見る
	humanoid.HealthChanged:Connect(function()
		local enemy = enemies[model]
		if enemy and humanoid.Health <= 0 then
			onEnemyDied(enemy)
		end
	end)
	local motion: MotionState = {
		tracks = {},
		locomotion = nil,
		locomotionTrack = nil,
		stillSince = nil,
		attackTrack = nil,
		reactionTrack = nil,
	}
	rigs[model] = { template = template, humanoid = humanoid, root = root, uses = 0, motion = motion }
	-- 体を壊したら、読み込んだトラックを手放す
	model.Destroying:Once(function()
		table.clear(motion.tracks)
	end)
	return model
end

-- ひな形のプールから体を1つ取り出す（無ければ作る）。2つ目の返り値は、プールから取り出したか。
-- プールに置いている間に壊された体（部品が消えた体）は使わずに、壊した数に数えて次の体を取り出す
local function takeBody(template: Template): (Model, boolean)
	local function make(): Model
		return createBody(template)
	end
	local model, reused = KotaiPool.take(template.pool, make)
	while reused and not isIntact(model, rigs[model] :: Rig) do
		rigs[model] = nil
		KotaiPool.discard(template.pool)
		model:Destroy()
		model, reused = KotaiPool.take(template.pool, make)
	end
	return model, reused
end

-- 使い回した体から、前に出ていたときに付けたもの（攻撃を当てたときのハイライト・毒の煙）を外し、
-- 部品の衝突のグループをひな形のグループにそろえる
local function cleanBody(model: Model, group: string)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			if descendant.CollisionGroup ~= group then
				descendant.CollisionGroup = group
			end
		elseif descendant:IsA("Highlight") or (descendant:IsA("Fire") and descendant.Name == POISON_NAME) then
			descendant:Destroy()
		end
	end
end

-- (x, z) の地面の上に、軍 gun の体を1体出す。体はひな形のプールから取り出し、無ければ作る。
-- 地面が無ければ出さずに nil を返す。
-- butai を渡すと部隊の下忍の個体にする（戦う相手がいなければ部隊の位置の周りへ戻る）。color は体の色
local function spawnEnemy(kind: string, gun: Gun.Gun, x: number, z: number, butai: string?, color: Color3?): Model?
	-- 地面が無ければ、体を取り出さない
	if not Ground.heightAt(x, z) then
		return nil
	end
	local def = ENEMY_DEFS[kind]
	local template = templateFor(kind, gun, color)
	local model, reused = takeBody(template)
	local rig = rigs[model] :: Rig
	local humanoid, root = rig.humanoid, rig.root
	if not Ground.placeCharacter(model, x, z) then
		putBack(model)
		return nil
	end
	model.Name = `{kind}{nextNumber}`
	nextNumber += 1

	-- 新しく作った体と同じ状態にする（使い回した体に、前に出ていたときの状態を残さない）
	applyDef(humanoid, kind, def)
	if reused then
		cleanBody(model, template.group)
		-- プールへ返すときに止めたモーションが、残っていないようにする
		stopMotions(rig)
	end
	model.Parent = enemiesFolder
	-- 出ている間の読み込みの扱いは、新しく作った体と同じに戻す（Persistent はプールの間だけ）
	model.ModelStreamingMode = template.model.ModelStreamingMode
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
	root.Anchored = false
	-- ノックバックの挙動を安定させるため物理はサーバーが持つ
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	-- 倒れたときや吹き飛んだときの速さを残さない
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	if reused then
		-- プールでは自分で力を出さない状態（Physics）にしてあるので、固定を外してから立たせる
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
	-- 出すたびに変わる印（useOf）
	rig.uses += 1

	local reaction = Config.EnemyReaction
	local body = Hanno.newBody(model, humanoid, root, {
		lieHeight = LIE_HEIGHT * def.Scale,
		scale = if kind == "Jonin" then reaction.JoninScale else 1,
		flinchScale = if kind == "Jonin" then reaction.JoninFlinchScale else 1,
	})
	local enemy: Enemy = {
		kind = kind,
		gun = gun,
		color = template.color,
		model = model,
		humanoid = humanoid,
		root = root,
		def = def,
		radius = radii[kind],
		spin = math.random() * math.pi * 2,
		lastAttack = 0,
		lastHitBy = nil,
		body = body,
		hits = 0,
		firstHitAt = nil,
		poison = nil,
		butai = butai,
		offset = Vector3.zero,
		lastHitSilent = false,
	}
	-- 奈落に落ちたら、倒れたことにしてプールへ返す
	body.onFell = function()
		onFell(enemy)
	end
	if reused then
		-- 前に出ていたときの歩く先を消す
		Hanno.stopWalking(body)
	end
	if butai then
		-- 部隊の位置の周り（GeninKotai 節の Spread の円の中）に、戦う相手がいないときに戻る自分の位置を決める
		local angle = math.random() * math.pi * 2
		local reach = math.sqrt(math.random()) * Config.GeninKotai.Spread
		enemy.offset = Vector3.new(math.cos(angle) * reach, 0, math.sin(angle) * reach)
	end
	enemies[model] = enemy
	aliveCount += 1
	if kind == "Genin" then
		-- 下忍は、反応の状態が変わったら被弾の反応のモーションを流し、待機のモーションから始める
		body.onStateChanged = function(state, previous)
			onHannoChanged(enemy, state, previous)
		end
		refreshLocomotion(enemy, os.clock())
	end
	return model
end

-- 敵を1体消す（部隊の下忍の個体を部隊へ戻すとき）。倒れたことにしない（撃破数・兵数・知らせは動かない）。体はプールへ返す
local function removeEnemy(enemy: Enemy)
	if enemies[enemy.model] ~= enemy then
		return
	end
	enemies[enemy.model] = nil
	aliveCount -= 1
	KogekiToken.forget(tokens, enemy.model.Name)
	recycle(enemy)
end

-- 軍 gun の部隊の下忍の個体を1体、(x, z) の地面の上に出す。color は体の色（クランの色）。地面が無ければ出さずに nil
function EnemyService.spawnKotai(butaiId: string, gun: Gun.Gun, x: number, z: number, color: Color3?): Model?
	return spawnEnemy("Genin", gun, x, z, butaiId, color)
end

-- 生きている敵を消す（部隊の下忍の個体を部隊へ戻す）。倒れたことにしない。消したら true
function EnemyService.remove(model: Model): boolean
	local enemy = enemies[model]
	if not enemy or enemy.humanoid.Health <= 0 then
		return false
	end
	removeEnemy(enemy)
	return true
end

-- 生きている敵か（消えた・倒れた敵は false）
function EnemyService.isAlive(model: Model): boolean
	local enemy = enemies[model]
	return enemy ~= nil and enemy.humanoid.Health > 0
end

-- まだ敵の表にいるか。倒れた敵は、倒れたことを知らせる（kotaiDefeated）ときに表から外れる。
-- 体力が 0 になってから倒れたことを知らせるまでの間も true（部隊の個体の数と兵数をずらさないため）
function EnemyService.isPresent(model: Model): boolean
	return enemies[model] ~= nil
end

-- 体を出した回の印（体を出すたびに変わる）。出ていない体と、ここの体でないもの（プレイヤー、上忍と首領の個体）は nil。
-- 遅れて届く攻撃（飛び道具）は、判定を出したときの印を覚えておき、届いたときに印が変わっていたら当てない
-- （届くまでに体を部隊へ戻して、使い回した体を別の場所に出し直していることがある）
function EnemyService.useOf(ref: Instance): number?
	if not ref:IsA("Model") then
		return nil
	end
	local rig = rigs[ref]
	return if rig and enemies[ref] then rig.uses else nil
end

-- 生きている敵の位置。いなければ nil
function EnemyService.positionOf(model: Model): Vector3?
	local enemy = enemies[model]
	if not enemy or enemy.humanoid.Health <= 0 then
		return nil
	end
	return enemy.root.Position
end

-- 部隊 ID から部隊の位置（水平。高さは問わない）を引く関数を登録する。戦う相手がいない部隊の下忍の個体はそこへ戻る
function EnemyService.setHomeProvider(provider: (butaiId: string) -> Vector3?)
	homeProvider = provider
end

-- 部隊 ID から交戦中の部隊の様子（交戦の相手の部隊 ID と両部隊の位置）を引く関数を登録する。交戦していなければ nil を返す。
-- 交戦中の部隊の個体は、交戦の組ごとに前線と控えに並ぶ
function EnemyService.setKosenProvider(provider: (butaiId: string) -> KosenInfo?)
	kosenProvider = provider
end

-- 交戦中の部隊の敵軍の個体が、近くのプレイヤーを狙うかを切り替える（確認用。止めると、前線の攻撃の動作が
-- プレイヤーに当たらないことを、攻撃トークンの攻撃と分けて確かめられる）
function EnemyService.setKosenAggro(enabled: boolean)
	kosenAggro = enabled
end

-- 交戦の損害の演出で、部隊の前線の個体を count 体まで倒れさせ、倒れさせた個体のモデルを返す（前線の個体が足りなければ全員）。
-- 前線の個体は最後の判断で並べたもの。相手と向かい合って並ぶ位置に着いている個体を先に選び（Zensen.chooseFallen）、
-- 並ぶ位置に着いている向かい合う相手に、その時に攻撃の動作をさせる。部隊の兵数は交戦の計算で減らし終えているので、
-- 倒れても撃破数・兵数・拠点の耐久・救援数に数えない（倒した人を持たせず、kotaiDefeated でも知らせない）
function EnemyService.defeatZensen(butaiId: string, count: number): { Model }
	local candidates: { Zensen.FallCandidate } = {}
	local byName: { [string]: Enemy } = {}
	for model, enemy in enemies do
		local order = enemy.zensen
		if enemy.butai == butaiId and enemy.humanoid.Health > 0 and order and order.front then
			local distance = horizontalDistance(enemy.root.Position, order.point)
			byName[model.Name] = enemy
			table.insert(candidates, {
				id = model.Name,
				engaged = order.aite ~= nil and distance <= ZENSEN_TOLERANCE,
				distance = distance,
			})
		end
	end
	local now = os.clock()
	local fallen = {}
	for _, id in Zensen.chooseFallen(candidates, count) do
		local enemy = byName[id]
		local order = enemy.zensen
		-- 向かい合う相手が斬ったように、並ぶ位置に着いている相手に、その時に攻撃の動作をさせる
		local aite = if order and order.aite then enemies[order.aite] else nil
		local aiteOrder = if aite then aite.zensen else nil
		if
			aite
			and aiteOrder
			and aite.humanoid.Health > 0
			and horizontalDistance(aite.root.Position, aiteOrder.point) <= ZENSEN_TOLERANCE
			and not Hanno.busy(aite.body, now)
		then
			swing(aite, aiteOrder.look)
			aite.swingAt = nextSwingTime(now)
		end
		Vfx.hit(enemy.model)
		enemy.kosenSongai = true
		enemy.lastHitBy = nil
		enemy.lastHitSilent = false
		enemy.humanoid.Health = 0
		table.insert(fallen, enemy.model)
	end
	return fallen
end

-- 部隊の生きている個体の、交戦中の様子（前線か控えか・向かい合う相手・正面の向き・並ぶ位置までの距離と着いたか・
-- 狙ったプレイヤー）を名前の順に返す（窓口の確認用）
function EnemyService.kosenKotaiOf(butaiId: string): { KosenKotai }
	local list: { KosenKotai } = {}
	for model, enemy in enemies do
		if enemy.butai == butaiId and enemy.humanoid.Health > 0 then
			local order = enemy.zensen
			local facing = enemy.root.CFrame.LookVector
			local upright = math.abs(facing.Y) <= UPRIGHT_LIMIT
			local distance = if order then horizontalDistance(enemy.root.Position, order.point) else nil
			table.insert(list, {
				name = model.Name,
				front = if order then order.front else nil,
				aite = if order and order.aite then order.aite.Name else nil,
				look = if upright then { x = facing.X, z = facing.Z } else nil,
				distance = distance,
				arrived = if distance then distance <= ZENSEN_TOLERANCE else nil,
				player = enemy.target,
			})
		end
	end
	table.sort(list, function(a, b)
		return a.name < b.name
	end)
	return list
end

-- 攻撃側から呼ばれる被ダメージ処理。撃破数はとどめを刺したプレイヤーに付く。
-- hit を渡すと、反応（のけぞり・吹き飛び・打ち上げ）を始める。当てたら true。
-- silent なら、とどめになったときの部隊の兵数の減少を拠点の耐久に数えない（秘計の爆破罠。ButaiService.changeHeisu の silent）
function EnemyService.damage(model: Model, amount: number, attacker: Player?, hit: Hit?, silent: boolean?): boolean
	local enemy = enemies[model]
	if not enemy or enemy.humanoid.Health <= 0 then
		return false
	end

	-- とどめを刺した人の撃破に数える。攻撃した人がいなければ（NPC の秘計、味方軍の上忍と首領の型など）、
	-- 前に攻撃した人の撃破にもしない
	enemy.lastHitBy = attacker
	enemy.lastHitSilent = silent == true
	enemy.hits += 1
	enemy.firstHitAt = enemy.firstHitAt or os.clock()
	enemy.humanoid:TakeDamage(amount)
	if hit then
		Hanno.react(enemy.body, hit, os.clock())
	end
	return true
end

-- 毒にする。毒の間は Config.luau の Poison 節の間隔ごとにダメージを与え、とどめは attacker の撃破に数える。
-- 毒の間にもう一度付けたら、残りの時間を Duration に戻す。倒れた敵は毒にしない（false）
function EnemyService.poison(model: Model, attacker: Player?): boolean
	local enemy = enemies[model]
	if not enemy or enemy.humanoid.Health <= 0 then
		return false
	end
	local now = os.clock()
	local current = enemy.poison
	if current then
		current.untilTime = now + Config.Poison.Duration
		current.attacker = attacker or current.attacker
		return true
	end
	enemy.poison = {
		attacker = attacker,
		nextTick = now + Config.Poison.Interval,
		untilTime = now + Config.Poison.Duration,
	}
	if not enemy.root:FindFirstChild(POISON_NAME) then
		local fire = Instance.new("Fire")
		fire.Name = POISON_NAME
		fire.Color = POISON_COLOR
		fire.SecondaryColor = POISON_SECONDARY_COLOR
		fire.Size = 3 * enemy.def.Scale
		fire.Heat = 2
		fire.Parent = enemy.root
	end
	return true
end

-- 攻撃判定の対象にする、軍 gun の生きている体の位置と半径。当てる側が、相手の軍を渡す
function EnemyService.getTargets(gun: Gun.Gun): { HitShape.Target<Model> }
	local targets = {}
	for model, enemy in enemies do
		if enemy.gun == gun and enemy.humanoid.Health > 0 then
			table.insert(targets, { ref = model, position = enemy.root.Position, radius = enemy.radius })
		end
	end
	return targets
end

-- Hanno を通らずに奈落へ落ちた体（歩いて区画の端から落ちた体など）を、奈落に落ちたときと同じ扱いにする。
-- 体が消える高さ（FallenPartsDestroyHeight）の下でエンジンに workspace から外された体（HumanoidRootPart が
-- workspace に無い体）と、部品が消えた体を見る
local function sweepFallen()
	for model, enemy in table.clone(enemies) do
		local rig = rigs[model]
		if not rig or not isIntact(model, rig) or not rig.root:IsDescendantOf(workspace) then
			onFell(enemy)
		end
	end
end

-- 出ている敵をすべて片付けて、体をプールへ返す。倒れた姿を見せている体も返し、撃破数には数えない
local function removeAll()
	for _, enemy in enemies do
		recycle(enemy)
	end
	table.clear(enemies)
	for _, enemy in corpses do
		recycle(enemy)
	end
	table.clear(corpses)
	aliveCount = 0
	-- 表に無いものがフォルダに残っていれば消す
	enemiesFolder:ClearAllChildren()
	nextNumber = 1
	KogekiToken.reset(tokens)
	table.clear(lastCandidates)
end

-- 出撃したステージの両軍の下忍の個体の体を、先読みの数（Prewarm）まで作ってプールに置く。
-- まとめて作って負荷の山を作らないよう、1フレームに PrewarmPerFrame 体ずつ作る。ひな形は起動時に作ってあるので、
-- 複製するだけで待たない。出し入れの判断が先に体を使っても、作ってまだ壊していない体を数えて足りない分だけ作る。
-- そのステージで使わないひな形（ほかのクランの色や窓口で出した敵）のプールの体は壊す
local function prewarm(stageId: string)
	local stage = Stages.get(stageId)
	if not stage then
		return
	end
	prewarmRun += 1
	local run = prewarmRun
	prewarmStage = stageId
	local targets: { [Template]: number } = {}
	for _, gun in Gun.list do
		local template = templateFor("Genin", gun, Colors.Clan[Stages.clanOf(stage, gun)])
		targets[template] = Config.KotaiPool.Prewarm[gun]
	end
	prewarmTargets = targets
	for _, template in templates do
		if not targets[template] then
			for _, model in KotaiPool.drain(template.pool) do
				destroyBody(model)
			end
		end
	end
	prewarming = true
	task.spawn(function()
		local ok, err = pcall(function()
			-- 出撃し直したら（run が変わったら）、前のステージの先読みはやめる
			while run == prewarmRun do
				local made = 0
				for template, target in targets do
					local budget = Config.KotaiPool.PrewarmPerFrame - made
					made += KotaiPool.fill(template.pool, target, budget, function()
						local model = createBody(template)
						park(model)
						return model
					end)
				end
				if made == 0 then
					break
				end
				task.wait()
			end
		end)
		if not ok then
			warn(`EnemyService: 下忍の個体の体を先に作れなかった: {err}`)
		end
		if run == prewarmRun then
			prewarming = false
		end
	end)
end

function EnemyService.start()
	enemiesFolder = Instance.new("Folder")
	enemiesFolder.Name = "Enemies"
	enemiesFolder.Parent = workspace
	-- 使い終えた体を置くフォルダ。区画とロビーから遠い地面の下で、体が消える高さ（FallenPartsDestroyHeight）より上に置く
	poolFolder = Instance.new("Folder")
	poolFolder.Name = "KotaiPool"
	poolFolder.Parent = workspace
	parkCFrame = CFrame.new(POOL_X, workspace.FallenPartsDestroyHeight + POOL_LIFT, POOL_Z)
	-- 飛んでいる敵の光線を、ほかの敵とプールの体に当てない
	Hanno.excludeFolder(enemiesFolder)
	Hanno.excludeFolder(poolFolder)

	-- 戦闘のフェーズが終わったら片付ける（体はプールへ返す）
	StageService.phaseChanged:Connect(function(next: StagePhase.Phase)
		if next ~= "Battle" then
			removeAll()
		end
	end)
	-- 出撃したら、そのステージの両軍の体を先に作っておく（開始のイベントシーンの間に作り終える）
	StageService.started:Connect(function(info: StageService.StartInfo)
		prewarm(info.stageId)
	end)

	for kind in ENEMY_DEFS do
		-- 腕まで含めた横幅の半分を半径にする（空間クエリで体のパーツに当てていたときと同じ広さ。軍と色によらない）
		local size = templateFor(kind, AITE_GUN).model:GetExtentsSize()
		radii[kind] = math.max(size.X, size.Z) / 2
	end
	-- 部隊の下忍の個体の体のひな形（ステージごとの両軍のクランの色）を先に作る
	-- （ひな形を作る処理は待つことがあり、出し入れの判断と先読みの途中で待たないように）
	for _, stage in Stages.definitions do
		for _, gun in Gun.list do
			templateFor("Genin", gun, Colors.Clan[Stages.clanOf(stage, gun)])
		end
	end

	DebugCommand.register(
		"SpawnEnemy",
		"<Genin|Jonin> <x> <z>",
		"地面の高さに合わせて敵（敵軍。部隊に属さない）を1体出す",
		function(kind, x, z)
			if type(kind) ~= "string" or not ENEMY_DEFS[kind] then
				error("種類は Genin か Jonin で指定する", 0)
			end
			local model = spawnEnemy(kind, AITE_GUN, DebugCommand.toNumber(x, "x"), DebugCommand.toNumber(z, "z"))
			if not model then
				return "地面が見つからず出せなかった"
			end
			local position = model:GetPivot().Position
			return string.format(
				"%s を (%.1f, %.1f, %.1f) に出した",
				model.Name,
				position.X,
				position.Y,
				position.Z
			)
		end
	)

	DebugCommand.register(
		"DumpEnemies",
		"",
		"生きている体（両軍の下忍の個体と窓口で出した敵。名前・種類・軍・体の色の RGB・部隊の下忍の個体なら部隊 ID・体力・"
			.. "受けた攻撃の数・最初に受けてからの秒数・反応の状態・毒の残り秒数・攻撃トークンを持っている相手のプレイヤー・位置・"
			.. "体を出した回数（uses。2 以上ならプールから使い回した体）・Humanoid の状態（state）・固定しているか（anchored））を"
			.. " JSON で返す",
		function()
			local list = {}
			local now = os.clock()
			for model, enemy in enemies do
				if enemy.humanoid.Health > 0 then
					local position = enemy.root.Position
					local poison = enemy.poison
					local firstHitAt = enemy.firstHitAt
					local owner = KogekiToken.ownerOf(tokens, model.Name)
					local holder = if owner then Players:GetPlayerByUserId(tonumber(owner) or 0) else nil
					local color = enemy.color
					local rig = rigs[model]
					table.insert(list, {
						name = model.Name,
						kind = enemy.kind,
						gun = enemy.gun,
						color = { math.round(color.R * 255), math.round(color.G * 255), math.round(color.B * 255) },
						butai = enemy.butai,
						health = math.round(enemy.humanoid.Health * 10) / 10,
						hits = enemy.hits,
						firstHitAgo = if firstHitAt then math.round((now - firstHitAt) * 100) / 100 else nil,
						hanno = Hanno.kindOf(enemy.body),
						poison = if poison then math.max(math.round((poison.untilTime - now) * 10) / 10, 0) else nil,
						token = if holder then holder.Name else nil,
						position = { math.round(position.X), math.round(position.Y), math.round(position.Z) },
						uses = if rig then rig.uses else nil,
						state = enemy.humanoid:GetState().Name,
						anchored = enemy.root.Anchored,
					})
				end
			end
			table.sort(list, function(a, b)
				return a.name < b.name
			end)
			return HttpService:JSONEncode(list)
		end
	)
	DebugCommand.register(
		"DumpGeninPool",
		"",
		"下忍の個体の体のプールを、ひな形（種類・軍・体の色の RGB）ごとに、先読みの数（prewarm）・置ける数の上限（limit）・"
			.. "作った数（created）・取り出した数（taken。使い回した数）・返した数（returned）・壊した数（destroyed）・"
			.. "今プールにある数（idle）・出ている数（inUse。倒れた姿を見せている体も入る）で返す。先読みしたステージ（prewarmStage）・"
			.. "先読みの途中か（prewarming）・プールのフォルダに置いている体の数（parked）を添えて JSON で返す",
		function()
			local pools = {}
			for key, template in templates do
				local stats = KotaiPool.stats(template.pool)
				local color = template.color
				table.insert(pools, {
					key = key,
					kind = template.kind,
					gun = template.gun,
					color = { math.round(color.R * 255), math.round(color.G * 255), math.round(color.B * 255) },
					prewarm = prewarmTargets[template] or 0,
					limit = template.pool.limit,
					created = stats.created,
					taken = stats.taken,
					returned = stats.returned,
					destroyed = stats.destroyed,
					idle = stats.idle,
					inUse = stats.inUse,
				})
			end
			table.sort(pools, function(a, b)
				return a.key < b.key
			end)
			return HttpService:JSONEncode({
				prewarmStage = prewarmStage,
				prewarming = prewarming,
				parked = #poolFolder:GetChildren(),
				pools = pools,
			})
		end
	)
	local geninItems = table.concat(Motions.GENIN_ITEMS, "・")
	DebugCommand.register(
		"SetGeninMotion",
		"<項目> <アニメーション ID|0>",
		`下忍のモーションの項目（{geninItems}）のアニメーション ID を差し替える。0 にするとその項目は流さない。`
			.. "差し替えはサーバーを止めるまで続き、Motions.luau は変わらない。待機と移動は流している体もすぐ流し直し、"
			.. "攻撃と被弾の反応は次に流すときから使う（Studio で候補のモーションを試す用。確認用）",
		function(item, value)
			if type(item) ~= "string" or not Motions.isGeninItem(item) then
				error(`項目は {geninItems} のどれかで指定する（{tostring(item)}）`, 0)
			end
			local id = DebugCommand.toNumber(value, "アニメーション ID")
			if id < 0 or id ~= math.floor(id) then
				error(`アニメーション ID は 0 以上の整数で指定する（{tostring(value)}）`, 0)
			end
			local previous = Motions.geninIdOf(item)
			Motions.setGeninId(item, id)
			if Motions.isGeninLocomotion(item) then
				-- その項目を流している体は、新しい ID で流し直す（0 なら止める）
				for model in enemies do
					local rig = rigs[model]
					if rig and rig.motion.locomotion == item then
						setLocomotion(rig, item, true)
					end
				end
			end
			return `下忍のモーション {item} を {id} にした（前は {previous}）`
		end
	)
	DebugCommand.register(
		"DumpGeninMotion",
		"",
		"下忍のモーションの項目ごとの ID（ids。0 は流さない）と、その項目を今流している下忍の体の数（playing）を JSON で返す。"
			.. "出ている下忍の体の数（bodies。倒れた姿を見せている体も入る）・そのうち生きている数（alive）・"
			.. "待機と移動を止めている数（locomotionStopped。倒れた後・飛んでいる間・倒れている間）・"
			.. "プールにある下忍の体の数（pooled）とそのうち何かを流している数（pooledPlaying。0 になる）・"
			.. "下忍の移動のモーションを流す速さ（runPlayback）を添える",
		function()
			local ids: { [string]: number } = {}
			local playing: { [string]: number } = {}
			for _, item in Motions.GENIN_ITEMS do
				ids[item] = Motions.geninIdOf(item)
				playing[item] = 0
			end
			local bodies, alive, stopped, pooled, pooledPlaying = 0, 0, 0, 0, 0
			for model, rig in rigs do
				if rig.template.kind ~= "Genin" then
					continue
				end
				local enemy = enemies[model] or corpses[model]
				local busy = false
				for item, loaded in rig.motion.tracks do
					if loaded.track.IsPlaying then
						busy = true
						if enemy then
							playing[item] = (playing[item] or 0) + 1
						end
					end
				end
				if enemy then
					bodies += 1
					if enemy.humanoid.Health > 0 then
						alive += 1
					end
					if rig.motion.locomotion == nil then
						stopped += 1
					end
				else
					pooled += 1
					if busy then
						pooledPlaying += 1
					end
				end
			end
			return HttpService:JSONEncode({
				ids = ids,
				playing = playing,
				bodies = bodies,
				alive = alive,
				locomotionStopped = stopped,
				pooled = pooled,
				pooledPlaying = pooledPlaying,
				runPlayback = Motions.geninRunPlaybackOf(Config.Genin.WalkSpeed, Config.GeninMotion.RunSpeed),
			})
		end
	)
	DebugCommand.register(
		"SetEnemyAI",
		"<true|false>",
		"体（両軍の下忍の個体と窓口で出した敵）が動くか（敵軍の体はプレイヤーに近づいて攻撃するか、部隊の下忍の個体は"
			.. "部隊について歩くか）を切り替える。止めてもその場で攻撃の反応（吹き飛び・ダウン）と毒は進む（確認用）",
		function(value)
			aiEnabled = value == true or value == "true"
			if not aiEnabled then
				for _, enemy in enemies do
					if not enemy.body.state then
						Hanno.stopWalking(enemy.body)
					end
				end
			end
			return `敵の動きと攻撃を{if aiEnabled then "再開した" else "止めた"}`
		end
	)
	DebugCommand.register(
		"ClearEnemies",
		"",
		"生きている体を片付ける。両軍の部隊の下忍の個体は部隊へ戻し（兵数は変わらない）、窓口で出した敵は倒す（撃破数には数えない）。"
			.. "出し入れを続けていると個体はまた出るので、先に SetSpawning false を打つ",
		function()
			local returned, defeated = 0, 0
			for _, enemy in table.clone(enemies) do
				if enemy.humanoid.Health > 0 then
					if enemy.butai then
						removeEnemy(enemy)
						returned += 1
					else
						enemy.lastHitBy = nil
						enemy.humanoid.Health = 0
						defeated += 1
					end
				end
			end
			return `敵を {defeated} 体倒し、部隊の下忍の個体を {returned} 体部隊へ戻した`
		end
	)

	DebugCommand.register(
		"DefeatEnemies",
		"<プレイヤー名> [半径]",
		"プレイヤーの周り（既定は半径 30 スタッド）の生きている敵軍の体を倒し、そのプレイヤーの撃破に数える。"
			.. "味方軍の下忍の個体は倒さない（確認用）",
		function(name, radius)
			local player = DebugCommand.findPlayer(name)
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not root then
				return `{player.Name} のキャラクターがいない`
			end
			local range = if radius ~= nil then DebugCommand.toNumber(radius, "半径") else 30
			local count = 0
			for _, enemy in enemies do
				if
					enemy.gun == AITE_GUN
					and enemy.humanoid.Health > 0
					and (enemy.root.Position - root.Position).Magnitude <= range
				then
					enemy.lastHitBy = player
					enemy.humanoid.Health = 0
					count += 1
				end
			end
			return `{player.Name} の周り {range} スタッドの敵を {count} 体倒した`
		end
	)

	DebugCommand.register(
		"DefeatEnemy",
		"<敵の名前>",
		"体を名前（DumpEnemies の name）で1体倒す。味方軍の下忍の個体も倒せる。撃破数には数えない。"
			.. "部隊の下忍の個体なら兵数を1減らす（確認用）",
		function(enemyName)
			for model, enemy in enemies do
				if model.Name == enemyName and enemy.humanoid.Health > 0 then
					enemy.lastHitBy = nil
					enemy.humanoid.Health = 0
					return `{model.Name} を倒した`
				end
			end
			return `生きている敵 {tostring(enemyName)} はいない`
		end
	)

	DebugCommand.register(
		"SpawnEnemies",
		"<プレイヤー名> <数> [距離]",
		"プレイヤーの周りの円（既定は半径 20 スタッド）に、敵軍の下忍（部隊に属さない）を等しい間隔で出す（確認用）",
		function(name, countValue, distanceValue)
			local player = DebugCommand.findPlayer(name)
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not root then
				return `{player.Name} のキャラクターがいない`
			end
			local count = math.floor(DebugCommand.toNumber(countValue, "数"))
			local distance = if distanceValue ~= nil then DebugCommand.toNumber(distanceValue, "距離") else 20
			local names = {}
			for index = 1, count do
				local angle = (index - 1) / count * math.pi * 2
				local model = spawnEnemy(
					"Genin",
					AITE_GUN,
					root.Position.X + math.cos(angle) * distance,
					root.Position.Z + math.sin(angle) * distance
				)
				if model then
					table.insert(names, model.Name)
				end
			end
			local list = table.concat(names, "、")
			return `{player.Name} の周り {distance} スタッドに下忍を {#names} 体出した（{list}）`
		end
	)

	DebugCommand.register(
		"DumpKogekiToken",
		"",
		"プレイヤーごとの攻撃トークン（持っている下忍の名前と距離、待っている下忍の数、攻撃して休んでいる下忍の数、"
			.. "攻撃して返されてまだ渡せない攻撃トークンの数）を JSON で返す",
		function()
			local now = os.clock()
			local result = {}
			for _, player in Players:GetPlayers() do
				local key = keyOf(player)
				local distances: { [string]: number } = {}
				local waiting, resting = 0, 0
				for _, candidate in lastCandidates[key] or {} do
					distances[candidate.id] = candidate.distance
					if not KogekiToken.holds(tokens, key, candidate.id) then
						if KogekiToken.isResting(tokens, candidate.id, now) then
							resting += 1
						else
							waiting += 1
						end
					end
				end
				local holders = {}
				for _, id in KogekiToken.holderIds(tokens, key) do
					local distance = distances[id]
					table.insert(holders, {
						name = id,
						distance = if distance then math.round(distance * 10) / 10 else nil,
					})
				end
				table.insert(result, {
					player = player.Name,
					perPlayer = Config.KogekiToken.PerPlayer,
					holders = holders,
					waiting = waiting,
					resting = resting,
					cooling = KogekiToken.coolingCount(tokens, key, now),
				})
			end
			return HttpService:JSONEncode(result)
		end
	)

	DebugCommand.register(
		"LogKogekiToken",
		"<true|false>",
		"攻撃トークンの受け渡しと、攻撃トークンを持つ下忍の攻撃を出力に出す（確認用）",
		function(value)
			logTokens = value == true or value == "true"
			return `攻撃トークンの記録を{if logTokens then "出す" else "止めた"}`
		end
	)

	DebugCommand.register(
		"SpawnNpc",
		"<キャラクター ID> <x> <z>",
		"仮の見た目の NPC を地面の高さに合わせて1体出す（上忍・首領・役者の見た目の確認用）",
		function(characterId, x, z)
			if type(characterId) ~= "string" or not Characters.get(characterId) then
				error(`キャラクター ID {tostring(characterId)} は定義表に無い`, 0)
			end
			local model = Appearance.createModel(characterId)
			if not Ground.placeCharacter(model, DebugCommand.toNumber(x, "x"), DebugCommand.toNumber(z, "z")) then
				model:Destroy()
				return "地面が見つからず出せなかった"
			end
			local folder = workspace:FindFirstChild("Npcs") or Instance.new("Folder")
			folder.Name = "Npcs"
			folder.Parent = workspace
			model.Parent = folder
			return `{characterId} を出した`
		end
	)

	-- いなくなったプレイヤーの攻撃トークンを返す
	Players.PlayerRemoving:Connect(function(player)
		KogekiToken.removePlayer(tokens, keyOf(player))
		lastCandidates[keyOf(player)] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(Config.EnemyAI.AITickInterval)
			think(os.clock())
		end
	end)

	-- 歩いて奈落へ落ちた体を、考える間隔ごとに見つける（1回の失敗で止まらないよう、失敗は警告にする）
	task.spawn(function()
		while true do
			task.wait(Config.EnemyAI.AITickInterval)
			local ok, err = pcall(sweepFallen)
			if not ok then
				warn(`EnemyService: 奈落に落ちた体を片付けられなかった: {err}`)
			end
		end
	end)

	-- 下忍の体の待機と移動のモーションを、間隔ごとに体の速さで選び直す（1回の失敗で止まらないよう、失敗は警告にする）
	task.spawn(function()
		while true do
			task.wait(Config.GeninMotion.Interval)
			local ok, err = pcall(updateLocomotion, os.clock())
			if not ok then
				warn(`EnemyService: 下忍の待機と移動のモーションを選べなかった: {err}`)
			end
		end
	end)
end

return EnemyService
