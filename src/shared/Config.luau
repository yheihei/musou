--!strict
-- ゲームバランス調整用の定数。数値チューニングはこのファイルだけで完結させる。
--
-- 節の足し方
-- 1. 機能ごとに節を1つ足す。節名は CONTEXT.md の語の識別子（ADR 0005）にし、
--    CONTEXT.md に無い機能は英語にする（Stats、Combo など）
-- 2. 節の型を `export type <節名>Section` で公開し、`Config` 型に同じ名前で足す
-- 3. 節の前に見出しのコメントを置き、何に使う値かを書く
-- 4. 値は数値・文字列・真偽値と、それらの表だけにする
--    Color3・Vector3・Enum など Roblox の型は、使う側のモジュールに置く（Lune のテストで読むため）
-- 5. Config.spec.luau は、節の整理で値が変わっていないことを確かめるスナップショットを持つ
--    値を調整したときは、同じ変更でスナップショットも直す

-- キャラクター1人の能力値
export type StatValues = {
	MaxHealth: number,
	Attack: number,
	Defense: number,
	WalkSpeed: number,
	AttackSpeed: number,
}

export type StatsSection = {
	Characters: { [string]: StatValues },
	Jonin: StatValues,
	Shuryo: StatValues,
	MikatagunScale: number,
	DefenseHalf: number,
	MinDamage: number,
}

-- 特技1つ。覚えると、そのキャラクターで出撃したときに能力値（Stat。Stats.luau の StatName）へ補正を足す。
-- 補正は Stats.luau と同じく、基本値に Add を足してから Multiply を掛ける。
-- Makimono は覚えるのに使う巻物の数、Zentei は先に覚えておく特技（同じツリーの ID）
export type TokugiDef = {
	Id: string,
	Stat: string,
	Add: number?,
	Multiply: number?,
	Makimono: number,
	Zentei: { string }?,
}

-- 特技ツリーによる成長。キャラクターごとの特技ツリーと、巻物の得かた
export type TokugiSection = {
	Trees: { [string]: { TokugiDef } },
	Makimono: {
		Gekihasu: number,
		GekihasuMax: number,
		Shori: number,
	},
}

-- 毒。酉花の奥義「毒手裏剣」で敵に付ける
export type PoisonSection = {
	Interval: number,
	Damage: number,
	Duration: number,
}

export type ComboSection = {
	ComboResetTime: number,
}

export type OugiSection = {
	PerStock: number,
	MaxStock: number,
	InitialStock: number,
	GainPerHit: number,
	GainPerDamageTaken: number,
	-- 奥義の技。キャラクター定義の ougi（忍術の英名）ごとに置く
	Timelines: { [string]: ActionTimeline },
}

-- 攻撃を受けた側の反応。None は中断しない、Flinch はのけぞり、Knockback は吹き飛び、Launch は打ち上げ
export type Reaction = "None" | "Flinch" | "Knockback" | "Launch"

-- 攻撃判定の形。HitShape.luau の形に直して使う。Kind ごとに使う寸法（スタッド）が違う
-- Box は Range・Width・Height、Sector は Radius・Angle（度）・Height、Sphere は Radius、
-- Line は Length・Width・Speed（スタッド/秒）、Ring は Inner（内側の半径。省くと 0）・Radius（外側の半径）・Height。
-- Height を省くと Hitbox 節の Height を使う
export type ShapeDef = {
	Kind: "Box" | "Sector" | "Sphere" | "Line" | "Ring",
	Range: number?,
	Width: number?,
	Height: number?,
	Radius: number?,
	Inner: number?,
	Angle: number?,
	Length: number?,
	Speed: number?,
}

-- 技の判定1つ。発生（Startup）から Delay 秒後に出て、Repeat 回を Interval 秒ごとに繰り返す
export type HitDef = {
	Shape: ShapeDef,
	-- 判定の向きを右へ回す角度（度）
	Yaw: number?,
	-- 技の倍率。与ダメージは 倍率 × 攻撃 を、受ける側の防御で軽減したもの
	Power: number,
	Reaction: Reaction,
	-- 吹き飛ばす強さ。吹き飛びと打ち上げの初速を決める（Trajectory.luau、EnemyReaction 節）
	Knockback: number,
	Delay: number?,
	Repeat: number?,
	Interval: number?,
}

-- 行動1回ぶんのタイムライン（秒）と前進量（スタッド）
export type ActionTimeline = {
	Startup: number,
	Active: number,
	Recovery: number,
	CancelFrom: number,
	Advance: number,
	Interrupt: boolean?,
	-- この行動が終わったときに続けて始める行動
	Next: string?,
	-- 同じ時刻に出る判定を、1体に1回だけ当てるか（放射状に重なる直線の多重の命中を防ぐ）
	HitOnce: boolean?,
	-- 攻撃の判定。攻撃でない行動には無い
	Hits: { HitDef }?,
}

-- 武器種1つぶんの技
export type BukishuDef = {
	-- 通常攻撃の段。1段目から順に並べる
	Attack: { ActionTimeline },
	-- チャージ攻撃。C1 から順に並べる。通常攻撃を n 段出した後は C(n+1) になる
	ChargeKogeki: { ActionTimeline },
	-- ジャンプ攻撃。空中の通常攻撃で、着地まで1回だけ出せる叩きつけ
	JumpAttack: ActionTimeline,
}

export type BukishuSection = {
	Shuriken: BukishuDef,
	Katana: BukishuDef,
}

export type ActionSection = {
	BufferTime: number,
	Flinch: ActionTimeline,
	Down: ActionTimeline,
	GetUp: ActionTimeline,
	GuardHit: ActionTimeline,
}

export type GuardSection = {
	Angle: number,
}

export type KinkyuKaihiSection = {
	Distance: number,
	Duration: number,
	Invulnerable: number,
	Recovery: number,
	RecoveryPerChain: number,
	MaxRecovery: number,
	ChainDecay: number,
}

export type JumpSection = {
	Height: number,
	DiveSpeed: number,
}

export type DamageSection = {
	FlinchImmunity: number,
	GetUpInvulnerable: number,
}

export type HitboxSection = {
	Height: number,
	ShowShapes: boolean,
	ShapeLifetime: number,
}

-- 下忍と上忍で共通の敵の能力値
export type EnemySection = {
	DisplayName: string,
	MaxHealth: number,
	WalkSpeed: number,
	Damage: number,
	AttackRange: number,
	AttackCooldown: number,
	-- 攻撃を受けたプレイヤーの反応
	Reaction: Reaction,
	Scale: number,
}

-- 敵が攻撃を受けたときの反応（のけぞり・吹き飛び・打ち上げ・ダウン・起き上がり）
export type EnemyReactionSection = {
	Gravity: number,
	KnockbackLift: number,
	LaunchLift: number,
	LaunchDrift: number,
	AirLift: number,
	AirDrift: number,
	Flinch: number,
	Down: number,
	GetUp: number,
	JoninScale: number,
	JoninFlinchScale: number,
}

-- 下忍の体（実体化圏の両軍の下忍の個体と、窓口で出した敵）の動き
export type EnemyAISection = {
	AggroRange: number,
	AITickInterval: number,
	CorpseLifetime: number,
	PlayerGap: number,
}

-- 実体化圏の下忍の個体。サーバー全体の上限と味方軍の上限と、出し入れの間隔と位置
export type GeninKotaiSection = {
	MaxKotai: number,
	MikataMaxKotai: number,
	Interval: number,
	MaxPerTick: number,
	Spread: number,
	PopDistance: number,
	ViewMargin: number,
	HomeRadius: number,
}

-- 下忍の個体の体のプール。出撃したときに先に作る体の数と、プールに置ける体の数の上限（軍ごと。ひな形ごとに数える）
export type KotaiPoolSection = {
	Prewarm: {
		Mikatagun: number,
		Tekigun: number,
	},
	MaxIdle: {
		Mikatagun: number,
		Tekigun: number,
	},
	PrewarmPerFrame: number,
}

-- 攻撃トークン。1人のプレイヤーを同時に攻撃できる下忍の数と、渡し方
export type KogekiTokenSection = {
	PerPlayer: number,
	Range: number,
	Interval: number,
	Rest: number,
	MaxHold: number,
	WaitGap: number,
}

-- プレイヤーの視界。クライアントがカメラを送る間隔と、下忍を視界の外に出すときの判定
export type CameraViewSection = {
	Interval: number,
	Stale: number,
	Margin: number,
	FarDistance: number,
	MaxDistance: number,
	FallbackHeight: number,
	FallbackFov: number,
	FallbackAspect: number,
}

-- 下忍の個体の枠の配分。近いプレイヤーのまとまりにする距離
export type KotaiHaibunSection = {
	GroupDistance: number,
}

-- 実体化圏。プレイヤーの周りで、上忍と首領を個体として出す範囲と、個体の動き
export type JittaikakenSection = {
	AppearRadius: number,
	DisappearRadius: number,
	Interval: number,
	HomeRadius: number,
	CorpseLifetime: number,
}

-- 上忍と首領の型1つ。予備動作（YobiDosa 秒）の後に判定を出し（Active 秒）、後隙（Recovery 秒）の間は動かない。
-- 判定は予備動作の後 Delay 秒で出る。形・威力・反応の書き方はプレイヤーの技の判定と同じで、威力は 倍率 × 上忍の攻撃
export type KataDef = {
	-- 型を出し始める、狙う相手の中心までの水平の距離の上限（間合い。スタッド）
	Maai: number,
	-- 型を選ぶ重み。間合いに入っている型の重みの合計に対する割合が、選ぶ確率になる
	Weight: number,
	YobiDosa: number,
	Active: number,
	Recovery: number,
	Hits: { HitDef },
}

-- 上忍と首領の個体の戦い方。狙う相手を選んで間合いまで近づき、型を出す
export type KataSection = {
	AggroRange: number,
	ChaseRadius: number,
	AttackerMemory: number,
	SwitchMargin: number,
	Maai: number,
	Interval: number,
	IntervalRandom: number,
	-- 上忍と首領が出す型。型 ID ごとに置く
	Jonin: { [string]: KataDef },
	-- 首領だけが出す型。型 ID は Jonin と重ねない
	Shuryo: { [string]: KataDef },
}

export type KosenSection = {
	StartDistance: number,
	Zensenhaba: number,
	ReserveWeight: number,
	ShikiEffect: number,
	ShikiHoseiMin: number,
	ShikiHoseiMax: number,
	LossRate: number,
	MaxStep: number,
	GunStrength: {
		Mikatagun: number,
		Tekigun: number,
	},
	JoninPower: number,
	JoninShikiThreshold: number,
}

-- 交戦中の部隊の下忍の個体の見せ方。前線に向かい合って並ぶ間合いと間隔、攻撃の動作の間隔、プレイヤーを狙う距離
export type ZensenSection = {
	Gap: number,
	Spacing: number,
	RowGap: number,
	AttackInterval: number,
	AttackRandom: number,
	AggroRange: number,
}

export type ButaiSection = {
	-- 部隊の開始時の兵数。ステージ ID と部隊 ID（Haichi.luau の構成）で引く
	Heisu: { [string]: { [string]: number } },
	Speed: number,
	MoveInterval: number,
	JoninGekihaShiki: number,
}

-- 上忍が部隊を率いて方針（攻略・防衛・救援）に沿って動くときの間隔と距離
export type HoshinSection = {
	Interval: number,
	GeigekiDistance: number,
	KyuenRate: number,
}

export type KyotenSection = {
	-- 耐久の上限。通常拠点と本陣で分ける
	Taikyu: {
		Kyoten: number,
		Honjin: number,
	},
	SeiatsuRate: number,
	GeninGekiha: number,
	-- 守備の兵数の上限。通常拠点と本陣で分ける
	Shubi: {
		Kyoten: number,
		Honjin: number,
	},
	HojuInterval: number,
	HojuHeisu: number,
	MushubiGensho: number,
	TickInterval: number,
}

-- 出来事1種類ぶんの士気の上下の量
export type DekigotoShiki = {
	-- 軍全体の士気。得をする軍は上がり、相手の軍は下がる
	Gun: number,
	-- 近くの部隊の士気に足す補正の最大値。出来事の位置で最大になり、距離と時間で減る
	Butai: number,
}

-- 支配エリアの中で、その軍の部隊と上忍・首領に掛ける倍率
export type ShihaiAreaSection = {
	Radius: number,
	Push: number,
	Attack: number,
	Defense: number,
}

export type ShikiSection = {
	Initial: number,
	Min: number,
	Max: number,
	Radius: number,
	Duration: number,
	Dekigoto: {
		JoninGekiha: DekigotoShiki,
		KyotenKanraku: DekigotoShiki,
		Hikei: DekigotoShiki,
	},
}

export type HikeiSection = {
	Duration: { [string]: number },
	TargetRange: { [string]: number },
	TickInterval: number,
	NoticeTime: number,
}

-- 秘計の伏兵。潜ませる伏兵部隊の兵数と奇襲
export type FukuheiSection = {
	Heisu: number,
	KishuRadius: number,
	KishuShiki: number,
}

-- 秘計の鬼神化。効果中の発動者の能力値に掛ける倍率
export type KishinkaSection = {
	Attack: number,
	Defense: number,
}

-- 秘計の大喝。周りの相手の強化の秘計を打ち消し、動揺させる
export type DaikatsuSection = {
	Radius: number,
	Attack: number,
	Defense: number,
	Shiki: number,
}

-- 秘計の大火計。大火計地域の中の相手に与えるダメージ
export type DaikakeiSection = {
	Power: number,
	HeisuRate: number,
	FireTime: number,
}

-- 秘計の爆破罠。拠点の耐久が割合を下回ったときの爆発
export type BakuhawanaSection = {
	Rate: number,
	Power: number,
	HeisuRate: number,
	Knockback: number,
}

-- 秘計の挑発。発動者の周りの相手の上忍を、発動者のもとへ誘い出す
export type ChohatsuSection = {
	Radius: number,
}

-- 秘計の判断。敵軍の上忍と首領が秘計を使うかを決める間隔と条件
export type HikeiHandanSection = {
	Interval: number,
	UseInterval: number,
	RetryInterval: number,
	ShuryoHealthRate: number,
	BakuhawanaRadius: number,
	FukuheiDistance: number,
	DaikakeiAite: number,
}

-- 系統の秘計1つ。熟練度が Jukurendo に達すると覚える（0 なら最初から覚えている）
export type KeitoHikeiDef = {
	Id: string,
	Jukurendo: number,
}

-- 秘計の系統1つ。Hikei は覚える順の秘計。決着したときに、熟練度を上げる戦い方の数に Rate を掛けて切り捨て、
-- Max までを熟練度に足す
export type KeitoDef = {
	Hikei: { KeitoHikeiDef },
	Rate: number,
	Max: number,
}

-- 秘計の系統と熟練度。系統 ID（Jukurendo.luau の keitoList）ごとに置く
export type JukurendoSection = {
	Keito: { [string]: KeitoDef },
}

export type PartySection = {
	MaxMembers: number,
}

-- 人数による調整。パーティーの人数ごとの倍率を、1人から順に並べる
export type PartySizeSection = {
	JoninHealth: { number },
	Heiryoku: { number },
}

export type StageSection = {
	TimeLimit: number,
	SaishutsugekiDelay: number,
	Heiryoku: number,
	SaishutsugekiSpacing: number,
}

export type SerifuSection = {
	CharInterval: number,
	HoldTime: number,
	HoldPerChar: number,
	BattleTime: number,
	BattleQueueMax: number,
}

export type SoundSection = {
	Volume: { [string]: number },
	RollOffMinDistance: number,
	RollOffMaxDistance: number,
	HitInterval: number,
}

export type BgmSection = {
	Volume: { [string]: number },
	FadeTime: number,
}

export type BattleStatusSection = {
	TimeWarning: number,
	TimeDanger: number,
}

export type MinimapSection = {
	UpdateInterval: number,
}

export type TouchControlsSection = {
	DesignWidth: number,
	DesignHeight: number,
	Margin: number,
	Gap: number,
	AttackSize: number,
	ChargeKogekiSize: number,
	GuardSize: number,
	OugiSize: number,
	HikeiWidth: number,
	HikeiHeight: number,
	HikeiNoticeMax: number,
}

export type SmallScreenSection = {
	Width: number,
	Height: number,
	Margin: number,
	Gap: number,
	MinTextSize: number,
	MinTouchSize: number,
	NoticeMinWidth: number,
	PanelMinWidth: number,
	PanelMaxWidth: number,
	DialogueHeight: number,
	DialogueFaceSize: number,
	SkipWidth: number,
	SkipHeight: number,
}

export type Config = {
	Party: PartySection,
	PartySize: PartySizeSection,
	Stage: StageSection,
	Stats: StatsSection,
	Tokugi: TokugiSection,
	Combo: ComboSection,
	Bukishu: BukishuSection,
	Ougi: OugiSection,
	Poison: PoisonSection,
	Action: ActionSection,
	Jump: JumpSection,
	Guard: GuardSection,
	KinkyuKaihi: KinkyuKaihiSection,
	Damage: DamageSection,
	Hitbox: HitboxSection,
	Genin: EnemySection,
	Jonin: EnemySection,
	EnemyReaction: EnemyReactionSection,
	EnemyAI: EnemyAISection,
	KogekiToken: KogekiTokenSection,
	CameraView: CameraViewSection,
	KotaiHaibun: KotaiHaibunSection,
	GeninKotai: GeninKotaiSection,
	KotaiPool: KotaiPoolSection,
	Jittaikaken: JittaikakenSection,
	Kata: KataSection,
	Kosen: KosenSection,
	Zensen: ZensenSection,
	Butai: ButaiSection,
	Hoshin: HoshinSection,
	Kyoten: KyotenSection,
	ShihaiArea: ShihaiAreaSection,
	Shiki: ShikiSection,
	Hikei: HikeiSection,
	Fukuhei: FukuheiSection,
	Kishinka: KishinkaSection,
	Daikatsu: DaikatsuSection,
	Daikakei: DaikakeiSection,
	Bakuhawana: BakuhawanaSection,
	Chohatsu: ChohatsuSection,
	HikeiHandan: HikeiHandanSection,
	Jukurendo: JukurendoSection,
	Serifu: SerifuSection,
	Sound: SoundSection,
	Bgm: BgmSection,
	BattleStatus: BattleStatusSection,
	Minimap: MinimapSection,
	TouchControls: TouchControlsSection,
	SmallScreen: SmallScreenSection,
}

local Config: Config = {
	-- パーティー。1サーバーが1パーティーにあたる。Roblox のサーバーの最大人数も同じ値にする
	Party = {
		MaxMembers = 4,
	},

	-- 人数による調整。出撃したときのパーティーの人数で、敵軍の上忍と首領の体力と兵力を増やす。計算は PartySize.luau にある。
	-- 倍率は1人から上限人数まで人数の順に並べる。味方軍の上忍と首領には掛けない
	PartySize = {
		JoninHealth = { 1, 1.5, 2, 2.5 }, -- 敵軍の上忍と首領の体力の倍率
		Heiryoku = { 1, 1.5, 2, 2.5 }, -- 兵力の倍率。Stage 節の Heiryoku に掛け、端数は四捨五入する
	},

	-- ステージの進行。戦闘のフェーズの制限時間と、倒れたプレイヤーの再出撃
	Stage = {
		TimeLimit = 2400, -- 戦闘のフェーズの制限時間（秒）。過ぎると時間切れで負ける
		SaishutsugekiDelay = 5, -- 倒れてから再出撃するまでの秒数
		Heiryoku = 10, -- 出撃したときの兵力（パーティーで共有する再出撃の残り回数）
		SaishutsugekiSpacing = 6, -- 拠点から再出撃するときに、出撃した順に横へ並べる間隔（スタッド）
	},

	-- 能力値と与ダメージの計算。能力値の補正は Stats.luau が足す
	Stats = {
		-- 操作キャラクターの基本の能力値。キャラクター ID ごとに置く
		-- AttackSpeed は攻撃の速さの倍率で、1 が標準、小さいほど遅い
		Characters = {
			Jin = { MaxHealth = 300, Attack = 12, Defense = 10, WalkSpeed = 24, AttackSpeed = 1 },
			Torika = { MaxHealth = 270, Attack = 11, Defense = 8, WalkSpeed = 26, AttackSpeed = 1.1 },
			Sekishusai = { MaxHealth = 320, Attack = 13, Defense = 12, WalkSpeed = 23, AttackSpeed = 1 },
			-- 金鬼は重く遅い。攻撃の速さを落とし、威力を上げる
			KanaOni = { MaxHealth = 360, Attack = 16, Defense = 14, WalkSpeed = 22, AttackSpeed = 0.8 },
		},
		-- 上忍と首領（NPC）の基本の能力値。キャラクターごとの値はまだ無く、役目で決める
		Jonin = { MaxHealth = 600, Attack = 14, Defense = 12, WalkSpeed = 14, AttackSpeed = 1 },
		Shuryo = { MaxHealth = 1200, Attack = 16, Defense = 16, WalkSpeed = 14, AttackSpeed = 1 },
		MikatagunScale = 0.9, -- 味方軍の上忍と首領の体力・攻撃・防御に掛ける倍率。味方軍は敵軍よりやや弱くする
		DefenseHalf = 100, -- 防御がこの値のとき、受けるダメージが半分になる
		MinDamage = 1, -- 与ダメージの下限
	},

	-- 特技ツリーによる成長。キャラクターごとの特技ツリーの特技を、そのキャラクターの巻物を使って覚える。計算は Tokugi.luau にある。
	-- 覚えた特技の補正は、出撃したときにそのキャラクターの分を固定して能力値に足し、ロビーに戻るまで変えない
	Tokugi = {
		-- キャラクター ID ごとの特技ツリー。並びは画面の段（前提の深さ）の中の順。特技の名前は Tokugi.luau にある。
		-- 4人とも同じ形（攻撃、体力と防御、移動と攻撃の速さの3本と、3本の先の極意）を使い回し、極意だけを持ち味に合わせる。
		-- 補正は掛け算（防御だけ足し算）なので、全部覚えてもキャラクターごとの基本値の差（金鬼は重く遅い）は残る。
		-- 1つで数％にし、全部覚えても基本値の 1.2 倍まで（防御は +5 まで）に収める
		Trees = {
			-- 刃。極意は攻撃
			Jin = {
				{ Id = "Goriki1", Stat = "Attack", Multiply = 1.03, Makimono = 1 },
				{ Id = "Ganken1", Stat = "MaxHealth", Multiply = 1.04, Makimono = 1 },
				{ Id = "Kenkyaku1", Stat = "WalkSpeed", Multiply = 1.03, Makimono = 1 },
				{ Id = "Goriki2", Stat = "Attack", Multiply = 1.03, Makimono = 2, Zentei = { "Goriki1" } },
				{ Id = "Teppeki1", Stat = "Defense", Add = 2, Makimono = 2, Zentei = { "Ganken1" } },
				{ Id = "Hayawaza1", Stat = "AttackSpeed", Multiply = 1.03, Makimono = 2, Zentei = { "Kenkyaku1" } },
				{ Id = "Goriki3", Stat = "Attack", Multiply = 1.04, Makimono = 3, Zentei = { "Goriki2" } },
				{ Id = "Ganken2", Stat = "MaxHealth", Multiply = 1.06, Makimono = 3, Zentei = { "Teppeki1" } },
				{ Id = "Hayawaza2", Stat = "AttackSpeed", Multiply = 1.03, Makimono = 3, Zentei = { "Hayawaza1" } },
				{
					Id = "Gokui",
					Stat = "Attack",
					Multiply = 1.04,
					Makimono = 5,
					Zentei = { "Goriki3", "Ganken2", "Hayawaza2" },
				},
			},
			-- 酉花。軽く速いので、極意は攻撃の速さ
			Torika = {
				{ Id = "Goriki1", Stat = "Attack", Multiply = 1.03, Makimono = 1 },
				{ Id = "Ganken1", Stat = "MaxHealth", Multiply = 1.04, Makimono = 1 },
				{ Id = "Kenkyaku1", Stat = "WalkSpeed", Multiply = 1.03, Makimono = 1 },
				{ Id = "Goriki2", Stat = "Attack", Multiply = 1.03, Makimono = 2, Zentei = { "Goriki1" } },
				{ Id = "Teppeki1", Stat = "Defense", Add = 2, Makimono = 2, Zentei = { "Ganken1" } },
				{ Id = "Hayawaza1", Stat = "AttackSpeed", Multiply = 1.03, Makimono = 2, Zentei = { "Kenkyaku1" } },
				{ Id = "Goriki3", Stat = "Attack", Multiply = 1.04, Makimono = 3, Zentei = { "Goriki2" } },
				{ Id = "Ganken2", Stat = "MaxHealth", Multiply = 1.06, Makimono = 3, Zentei = { "Teppeki1" } },
				{ Id = "Hayawaza2", Stat = "AttackSpeed", Multiply = 1.03, Makimono = 3, Zentei = { "Hayawaza1" } },
				{
					Id = "Gokui",
					Stat = "AttackSpeed",
					Multiply = 1.04,
					Makimono = 5,
					Zentei = { "Goriki3", "Ganken2", "Hayawaza2" },
				},
			},
			-- 石舟斎。守りの剣なので、極意は防御
			Sekishusai = {
				{ Id = "Goriki1", Stat = "Attack", Multiply = 1.03, Makimono = 1 },
				{ Id = "Ganken1", Stat = "MaxHealth", Multiply = 1.04, Makimono = 1 },
				{ Id = "Kenkyaku1", Stat = "WalkSpeed", Multiply = 1.03, Makimono = 1 },
				{ Id = "Goriki2", Stat = "Attack", Multiply = 1.03, Makimono = 2, Zentei = { "Goriki1" } },
				{ Id = "Teppeki1", Stat = "Defense", Add = 2, Makimono = 2, Zentei = { "Ganken1" } },
				{ Id = "Hayawaza1", Stat = "AttackSpeed", Multiply = 1.03, Makimono = 2, Zentei = { "Kenkyaku1" } },
				{ Id = "Goriki3", Stat = "Attack", Multiply = 1.04, Makimono = 3, Zentei = { "Goriki2" } },
				{ Id = "Ganken2", Stat = "MaxHealth", Multiply = 1.06, Makimono = 3, Zentei = { "Teppeki1" } },
				{ Id = "Hayawaza2", Stat = "AttackSpeed", Multiply = 1.03, Makimono = 3, Zentei = { "Hayawaza1" } },
				{
					Id = "Gokui",
					Stat = "Defense",
					Add = 3,
					Makimono = 5,
					Zentei = { "Goriki3", "Ganken2", "Hayawaza2" },
				},
			},
			-- 金鬼。重く遅い分、打たれ強いので、極意は体力
			KanaOni = {
				{ Id = "Goriki1", Stat = "Attack", Multiply = 1.03, Makimono = 1 },
				{ Id = "Ganken1", Stat = "MaxHealth", Multiply = 1.04, Makimono = 1 },
				{ Id = "Kenkyaku1", Stat = "WalkSpeed", Multiply = 1.03, Makimono = 1 },
				{ Id = "Goriki2", Stat = "Attack", Multiply = 1.03, Makimono = 2, Zentei = { "Goriki1" } },
				{ Id = "Teppeki1", Stat = "Defense", Add = 2, Makimono = 2, Zentei = { "Ganken1" } },
				{ Id = "Hayawaza1", Stat = "AttackSpeed", Multiply = 1.03, Makimono = 2, Zentei = { "Kenkyaku1" } },
				{ Id = "Goriki3", Stat = "Attack", Multiply = 1.04, Makimono = 3, Zentei = { "Goriki2" } },
				{ Id = "Ganken2", Stat = "MaxHealth", Multiply = 1.06, Makimono = 3, Zentei = { "Teppeki1" } },
				{ Id = "Hayawaza2", Stat = "AttackSpeed", Multiply = 1.03, Makimono = 3, Zentei = { "Hayawaza1" } },
				{
					Id = "Gokui",
					Stat = "MaxHealth",
					Multiply = 1.05,
					Makimono = 5,
					Zentei = { "Goriki3", "Ganken2", "Hayawaza2" },
				},
			},
		},
		-- 巻物の得かた。ステージが決着したとき（勝ちも負けも）に、出撃して残っている人へ、そのとき使っているキャラクターの巻物を渡す。
		-- 試験用ステージでも渡す（確認のため。試験用ステージは選択画面に出さないので、遊ぶ人は得られない）。
		-- ツリーを全部覚えるには 23 本要る
		Makimono = {
			Gekihasu = 100, -- 撃破数この数ごとに1本渡す（端数は切り捨て）
			GekihasuMax = 5, -- 撃破数で渡す数の上限
			Shori = 3, -- 勝ったときに上乗せする数
		},
	},

	-- 通常攻撃のコンボ。1段ずつ順に出て、前の段のキャンセル受付が始まってから
	-- ComboResetTime 秒以内に次を押すと繋がる。段の中身は Bukishu 節にある
	Combo = {
		ComboResetTime = 0.5,
	},

	-- 武器種ごとの技（通常攻撃6段、チャージ攻撃 C1〜C6、ジャンプ攻撃）。同じ武器種のキャラクターで共有する（ADR 0004）。
	-- 行動のタイムラインに判定（Hits）を足したもの。時間はキャラクターの攻撃の速さ（Stats 節の AttackSpeed）で割る
	Bukishu = {
		-- 手裏剣セット（刃・酉花）。近くを斬り、ときどき手裏剣を投げる
		Shuriken = {
			Attack = {
				-- 1段目 斬り払い
				{
					Startup = 0.05,
					Active = 0.08,
					Recovery = 0.17,
					CancelFrom = 0.26,
					Advance = 1,
					Hits = {
						{
							Shape = { Kind = "Box", Range = 7, Width = 8 },
							Power = 1,
							Reaction = "Flinch",
							Knockback = 8,
						},
					},
				},
				-- 2段目 斬り返し
				{
					Startup = 0.05,
					Active = 0.08,
					Recovery = 0.17,
					CancelFrom = 0.26,
					Advance = 1,
					Hits = {
						{
							Shape = { Kind = "Box", Range = 7, Width = 8 },
							Power = 1,
							Reaction = "Flinch",
							Knockback = 8,
						},
					},
				},
				-- 3段目 手裏剣を1枚投げる
				{
					Startup = 0.08,
					Active = 0.1,
					Recovery = 0.17,
					CancelFrom = 0.3,
					Advance = 0,
					Hits = {
						{
							Shape = { Kind = "Line", Length = 30, Width = 3, Speed = 120 },
							Power = 0.9,
							Reaction = "Flinch",
							Knockback = 6,
						},
					},
				},
				-- 4段目 回し蹴り
				{
					Startup = 0.06,
					Active = 0.1,
					Recovery = 0.2,
					CancelFrom = 0.32,
					Advance = 1,
					Hits = {
						{
							Shape = { Kind = "Sector", Radius = 8, Angle = 180 },
							Power = 1.1,
							Reaction = "Flinch",
							Knockback = 10,
						},
					},
				},
				-- 5段目 手裏剣を3枚、扇に投げる
				{
					Startup = 0.08,
					Active = 0.1,
					Recovery = 0.22,
					CancelFrom = 0.36,
					Advance = 0,
					Hits = {
						{
							Shape = { Kind = "Line", Length = 28, Width = 3, Speed = 120 },
							Yaw = -15,
							Power = 0.8,
							Reaction = "Flinch",
							Knockback = 6,
						},
						{
							Shape = { Kind = "Line", Length = 28, Width = 3, Speed = 120 },
							Power = 0.8,
							Reaction = "Flinch",
							Knockback = 6,
						},
						{
							Shape = { Kind = "Line", Length = 28, Width = 3, Speed = 120 },
							Yaw = 15,
							Power = 0.8,
							Reaction = "Flinch",
							Knockback = 6,
						},
					},
				},
				-- 6段目 宙返りして周りを斬る。締めで吹き飛ばす
				{
					Startup = 0.12,
					Active = 0.12,
					Recovery = 0.46,
					CancelFrom = 0.68,
					Advance = 2,
					Hits = {
						{
							Shape = { Kind = "Sphere", Radius = 9 },
							Power = 2.2,
							Reaction = "Knockback",
							Knockback = 45,
						},
					},
				},
			},
			ChargeKogeki = {
				-- C1 踏み込んで蹴り飛ばす
				{
					Startup = 0.18,
					Active = 0.1,
					Recovery = 0.42,
					CancelFrom = 0.7,
					Advance = 2,
					Hits = {
						{
							Shape = { Kind = "Box", Range = 9, Width = 8 },
							Power = 2,
							Reaction = "Knockback",
							Knockback = 40,
						},
					},
				},
				-- C2 蹴り上げて打ち上げる
				{
					Startup = 0.14,
					Active = 0.1,
					Recovery = 0.46,
					CancelFrom = 0.7,
					Advance = 1,
					Hits = {
						{
							Shape = { Kind = "Sector", Radius = 8, Angle = 120 },
							Power = 1.6,
							Reaction = "Launch",
							Knockback = 50,
						},
					},
				},
				-- C3 蹴り上げてから跳んで追い打ちする
				{
					Startup = 0.14,
					Active = 0.5,
					Recovery = 0.4,
					CancelFrom = 1.04,
					Advance = 0,
					Hits = {
						{
							Shape = { Kind = "Box", Range = 8, Width = 8 },
							Power = 1.2,
							Reaction = "Launch",
							Knockback = 45,
						},
						{
							Shape = { Kind = "Box", Range = 10, Width = 8, Height = 18 },
							Delay = 0.12,
							Repeat = 3,
							Interval = 0.12,
							Power = 0.5,
							Reaction = "Launch",
							Knockback = 20,
						},
					},
				},
				-- C4 煙玉を炸裂させて周りを吹き飛ばす
				{
					Startup = 0.2,
					Active = 0.1,
					Recovery = 0.5,
					CancelFrom = 0.8,
					Advance = 0,
					Hits = {
						{
							Shape = { Kind = "Sphere", Radius = 11 },
							Power = 1.8,
							Reaction = "Knockback",
							Knockback = 55,
						},
					},
				},
				-- C5 八方へ手裏剣を3回撒く
				{
					Startup = 0.12,
					Active = 0.45,
					Recovery = 0.4,
					CancelFrom = 0.97,
					Advance = 0,
					Hits = {
						{
							Shape = { Kind = "Line", Length = 26, Width = 3, Speed = 120 },
							Yaw = 0,
							Repeat = 3,
							Interval = 0.15,
							Power = 0.5,
							Reaction = "Flinch",
							Knockback = 6,
						},
						{
							Shape = { Kind = "Line", Length = 26, Width = 3, Speed = 120 },
							Yaw = 45,
							Repeat = 3,
							Interval = 0.15,
							Power = 0.5,
							Reaction = "Flinch",
							Knockback = 6,
						},
						{
							Shape = { Kind = "Line", Length = 26, Width = 3, Speed = 120 },
							Yaw = 90,
							Repeat = 3,
							Interval = 0.15,
							Power = 0.5,
							Reaction = "Flinch",
							Knockback = 6,
						},
						{
							Shape = { Kind = "Line", Length = 26, Width = 3, Speed = 120 },
							Yaw = 135,
							Repeat = 3,
							Interval = 0.15,
							Power = 0.5,
							Reaction = "Flinch",
							Knockback = 6,
						},
						{
							Shape = { Kind = "Line", Length = 26, Width = 3, Speed = 120 },
							Yaw = 180,
							Repeat = 3,
							Interval = 0.15,
							Power = 0.5,
							Reaction = "Flinch",
							Knockback = 6,
						},
						{
							Shape = { Kind = "Line", Length = 26, Width = 3, Speed = 120 },
							Yaw = 225,
							Repeat = 3,
							Interval = 0.15,
							Power = 0.5,
							Reaction = "Flinch",
							Knockback = 6,
						},
						{
							Shape = { Kind = "Line", Length = 26, Width = 3, Speed = 120 },
							Yaw = 270,
							Repeat = 3,
							Interval = 0.15,
							Power = 0.5,
							Reaction = "Flinch",
							Knockback = 6,
						},
						{
							Shape = { Kind = "Line", Length = 26, Width = 3, Speed = 120 },
							Yaw = 315,
							Repeat = 3,
							Interval = 0.15,
							Power = 0.5,
							Reaction = "Flinch",
							Knockback = 6,
						},
					},
				},
				-- C6 手裏剣の雨を前へ浴びせ、最後に周りを吹き飛ばす
				{
					Startup = 0.15,
					Active = 0.6,
					Recovery = 0.55,
					CancelFrom = 1.3,
					Advance = 0,
					Hits = {
						{
							Shape = { Kind = "Line", Length = 34, Width = 3, Speed = 120 },
							Yaw = -30,
							Repeat = 3,
							Interval = 0.1,
							Power = 0.7,
							Reaction = "Flinch",
							Knockback = 8,
						},
						{
							Shape = { Kind = "Line", Length = 34, Width = 3, Speed = 120 },
							Yaw = -15,
							Repeat = 3,
							Interval = 0.1,
							Power = 0.7,
							Reaction = "Flinch",
							Knockback = 8,
						},
						{
							Shape = { Kind = "Line", Length = 34, Width = 3, Speed = 120 },
							Yaw = 0,
							Repeat = 3,
							Interval = 0.1,
							Power = 0.7,
							Reaction = "Flinch",
							Knockback = 8,
						},
						{
							Shape = { Kind = "Line", Length = 34, Width = 3, Speed = 120 },
							Yaw = 15,
							Repeat = 3,
							Interval = 0.1,
							Power = 0.7,
							Reaction = "Flinch",
							Knockback = 8,
						},
						{
							Shape = { Kind = "Line", Length = 34, Width = 3, Speed = 120 },
							Yaw = 30,
							Repeat = 3,
							Interval = 0.1,
							Power = 0.7,
							Reaction = "Flinch",
							Knockback = 8,
						},
						{
							Shape = { Kind = "Sphere", Radius = 12 },
							Delay = 0.5,
							Power = 3,
							Reaction = "Knockback",
							Knockback = 60,
						},
					},
				},
			},
			-- ジャンプ攻撃 急降下して着地の衝撃で周りを吹き飛ばす
			JumpAttack = {
				Startup = 0.12,
				Active = 0.1,
				Recovery = 0.3,
				CancelFrom = 0.45,
				Advance = 0,
				Hits = {
					{ Shape = { Kind = "Sphere", Radius = 8 }, Power = 1.5, Reaction = "Knockback", Knockback = 30 },
				},
			},
		},
		-- 刀セット（石舟斎・金鬼）。前方の箱と扇で斬る。金鬼の重さは攻撃の速さで出す
		Katana = {
			Attack = {
				-- 1段目 袈裟斬り
				{
					Startup = 0.06,
					Active = 0.08,
					Recovery = 0.2,
					CancelFrom = 0.3,
					Advance = 1.5,
					Hits = {
						{
							Shape = { Kind = "Box", Range = 8, Width = 8 },
							Power = 1,
							Reaction = "Flinch",
							Knockback = 8,
						},
					},
				},
				-- 2段目 逆袈裟
				{
					Startup = 0.06,
					Active = 0.08,
					Recovery = 0.2,
					CancelFrom = 0.3,
					Advance = 1.5,
					Hits = {
						{
							Shape = { Kind = "Box", Range = 8, Width = 9 },
							Power = 1,
							Reaction = "Flinch",
							Knockback = 8,
						},
					},
				},
				-- 3段目 横薙ぎ
				{
					Startup = 0.08,
					Active = 0.1,
					Recovery = 0.22,
					CancelFrom = 0.34,
					Advance = 1,
					Hits = {
						{
							Shape = { Kind = "Sector", Radius = 9, Angle = 140 },
							Power = 1.1,
							Reaction = "Flinch",
							Knockback = 10,
						},
					},
				},
				-- 4段目 踏み込んで突く
				{
					Startup = 0.1,
					Active = 0.08,
					Recovery = 0.24,
					CancelFrom = 0.36,
					Advance = 3,
					Hits = {
						{
							Shape = { Kind = "Box", Range = 12, Width = 4 },
							Power = 1.2,
							Reaction = "Flinch",
							Knockback = 12,
						},
					},
				},
				-- 5段目 回転斬り
				{
					Startup = 0.08,
					Active = 0.12,
					Recovery = 0.24,
					CancelFrom = 0.4,
					Advance = 1,
					Hits = {
						{
							Shape = { Kind = "Sector", Radius = 9, Angle = 360 },
							Power = 1.2,
							Reaction = "Flinch",
							Knockback = 12,
						},
					},
				},
				-- 6段目 唐竹割り。締めで吹き飛ばす
				{
					Startup = 0.14,
					Active = 0.1,
					Recovery = 0.5,
					CancelFrom = 0.72,
					Advance = 2,
					Hits = {
						{
							Shape = { Kind = "Box", Range = 10, Width = 10 },
							Power = 2.4,
							Reaction = "Knockback",
							Knockback = 45,
						},
					},
				},
			},
			ChargeKogeki = {
				-- C1 溜めてから突進して斬る
				{
					Startup = 0.2,
					Active = 0.1,
					Recovery = 0.45,
					CancelFrom = 0.75,
					Advance = 4,
					Hits = {
						{
							Shape = { Kind = "Box", Range = 11, Width = 6 },
							Power = 2.2,
							Reaction = "Knockback",
							Knockback = 45,
						},
					},
				},
				-- C2 斬り上げて打ち上げる
				{
					Startup = 0.15,
					Active = 0.1,
					Recovery = 0.5,
					CancelFrom = 0.75,
					Advance = 1,
					Hits = {
						{
							Shape = { Kind = "Sector", Radius = 9, Angle = 100 },
							Power = 1.7,
							Reaction = "Launch",
							Knockback = 55,
						},
					},
				},
				-- C3 斬り上げてから跳んで追い打ち
				{
					Startup = 0.14,
					Active = 0.5,
					Recovery = 0.4,
					CancelFrom = 1.04,
					Advance = 1,
					Hits = {
						{
							Shape = { Kind = "Box", Range = 8, Width = 8 },
							Power = 1.3,
							Reaction = "Launch",
							Knockback = 45,
						},
						{
							Shape = { Kind = "Box", Range = 9, Width = 9, Height = 18 },
							Delay = 0.12,
							Repeat = 3,
							Interval = 0.12,
							Power = 0.5,
							Reaction = "Launch",
							Knockback = 20,
						},
					},
				},
				-- C4 回転斬りで周りを吹き飛ばす
				{
					Startup = 0.2,
					Active = 0.12,
					Recovery = 0.5,
					CancelFrom = 0.82,
					Advance = 0,
					Hits = {
						{
							Shape = { Kind = "Sector", Radius = 11, Angle = 360 },
							Power = 1.9,
							Reaction = "Knockback",
							Knockback = 55,
						},
					},
				},
				-- C5 乱れ斬りの後に斬り払う
				{
					Startup = 0.12,
					Active = 0.6,
					Recovery = 0.4,
					CancelFrom = 1.12,
					Advance = 2,
					Hits = {
						{
							Shape = { Kind = "Box", Range = 10, Width = 10 },
							Repeat = 5,
							Interval = 0.1,
							Power = 0.5,
							Reaction = "Flinch",
							Knockback = 5,
						},
						{
							Shape = { Kind = "Box", Range = 10, Width = 10 },
							Delay = 0.55,
							Power = 1.4,
							Reaction = "Knockback",
							Knockback = 45,
						},
					},
				},
				-- C6 大上段から斬り下ろし、衝撃波で周りも吹き飛ばす
				{
					Startup = 0.3,
					Active = 0.2,
					Recovery = 0.6,
					CancelFrom = 1.1,
					Advance = 3,
					Hits = {
						{
							Shape = { Kind = "Box", Range = 14, Width = 12 },
							Power = 3.2,
							Reaction = "Knockback",
							Knockback = 65,
						},
						{
							Shape = { Kind = "Sphere", Radius = 13 },
							Delay = 0.1,
							Power = 1.5,
							Reaction = "Knockback",
							Knockback = 50,
						},
					},
				},
			},
			-- ジャンプ攻撃 落ちながら前へ斬り下ろす
			JumpAttack = {
				Startup = 0.14,
				Active = 0.1,
				Recovery = 0.34,
				CancelFrom = 0.5,
				Advance = 0,
				Hits = {
					{
						Shape = { Kind = "Box", Range = 9, Width = 8, Height = 12 },
						Power = 1.8,
						Reaction = "Knockback",
						Knockback = 35,
					},
				},
			},
		},
	},

	-- 奥義（Q）と奥義ゲージ。ストック1本で1回発動し、発動中は無敵。本数の計算は OugiGauge.luau にある
	Ougi = {
		PerStock = 100, -- 1本分の量
		MaxStock = 4, -- 本数の上限
		InitialStock = 1, -- 最初に持っている本数
		GainPerHit = 2, -- 奥義以外の攻撃を1体に当てるたびに溜まる量
		GainPerDamageTaken = 0.5,
		-- 奥義の技。攻撃の速さでは伸び縮みさせない。Interrupt で攻撃の硬直にも割り込める
		Timelines = {
			-- 刃の火遁。前方の扇に炎を6回吐き、最後に大きな炎で吹き飛ばす
			Katon = {
				Startup = 0.25,
				Active = 1.15,
				Recovery = 0.3,
				CancelFrom = 1.7,
				Advance = 0,
				Interrupt = true,
				Hits = {
					{
						Shape = { Kind = "Sector", Radius = 16, Angle = 90, Height = 10 },
						Repeat = 6,
						Interval = 0.15,
						Power = 2,
						Reaction = "Flinch",
						Knockback = 5,
					},
					{
						Shape = { Kind = "Sector", Radius = 18, Angle = 100, Height = 10 },
						Delay = 1,
						Power = 5,
						Reaction = "Knockback",
						Knockback = 60,
					},
				},
			},
			-- 酉花の毒手裏剣。周りの12方向へ毒手裏剣を3回撒き、当たった敵を毒にする（毒は Poison 節）。
			-- 近くでは直線が重なるので、1回の撒き（同じ時刻の12本）は1体に1回だけ当てる
			PoisonShuriken = {
				Startup = 0.2,
				Active = 0.8,
				Recovery = 0.3,
				CancelFrom = 1.3,
				Advance = 0,
				Interrupt = true,
				HitOnce = true,
				Hits = {
					{
						Shape = { Kind = "Line", Length = 30, Width = 3, Speed = 120 },
						Yaw = 0,
						Repeat = 3,
						Interval = 0.3,
						Power = 1.2,
						Reaction = "Flinch",
						Knockback = 6,
					},
					{
						Shape = { Kind = "Line", Length = 30, Width = 3, Speed = 120 },
						Yaw = 30,
						Repeat = 3,
						Interval = 0.3,
						Power = 1.2,
						Reaction = "Flinch",
						Knockback = 6,
					},
					{
						Shape = { Kind = "Line", Length = 30, Width = 3, Speed = 120 },
						Yaw = 60,
						Repeat = 3,
						Interval = 0.3,
						Power = 1.2,
						Reaction = "Flinch",
						Knockback = 6,
					},
					{
						Shape = { Kind = "Line", Length = 30, Width = 3, Speed = 120 },
						Yaw = 90,
						Repeat = 3,
						Interval = 0.3,
						Power = 1.2,
						Reaction = "Flinch",
						Knockback = 6,
					},
					{
						Shape = { Kind = "Line", Length = 30, Width = 3, Speed = 120 },
						Yaw = 120,
						Repeat = 3,
						Interval = 0.3,
						Power = 1.2,
						Reaction = "Flinch",
						Knockback = 6,
					},
					{
						Shape = { Kind = "Line", Length = 30, Width = 3, Speed = 120 },
						Yaw = 150,
						Repeat = 3,
						Interval = 0.3,
						Power = 1.2,
						Reaction = "Flinch",
						Knockback = 6,
					},
					{
						Shape = { Kind = "Line", Length = 30, Width = 3, Speed = 120 },
						Yaw = 180,
						Repeat = 3,
						Interval = 0.3,
						Power = 1.2,
						Reaction = "Flinch",
						Knockback = 6,
					},
					{
						Shape = { Kind = "Line", Length = 30, Width = 3, Speed = 120 },
						Yaw = 210,
						Repeat = 3,
						Interval = 0.3,
						Power = 1.2,
						Reaction = "Flinch",
						Knockback = 6,
					},
					{
						Shape = { Kind = "Line", Length = 30, Width = 3, Speed = 120 },
						Yaw = 240,
						Repeat = 3,
						Interval = 0.3,
						Power = 1.2,
						Reaction = "Flinch",
						Knockback = 6,
					},
					{
						Shape = { Kind = "Line", Length = 30, Width = 3, Speed = 120 },
						Yaw = 270,
						Repeat = 3,
						Interval = 0.3,
						Power = 1.2,
						Reaction = "Flinch",
						Knockback = 6,
					},
					{
						Shape = { Kind = "Line", Length = 30, Width = 3, Speed = 120 },
						Yaw = 300,
						Repeat = 3,
						Interval = 0.3,
						Power = 1.2,
						Reaction = "Flinch",
						Knockback = 6,
					},
					{
						Shape = { Kind = "Line", Length = 30, Width = 3, Speed = 120 },
						Yaw = 330,
						Repeat = 3,
						Interval = 0.3,
						Power = 1.2,
						Reaction = "Flinch",
						Knockback = 6,
					},
				},
			},
			-- 石舟斎の無刀取り。短く構えてから周りを打ち上げ、空中の敵へ斬撃を重ね、最後の一撃で吹き飛ばす。
			-- 空中への斬撃の段数は2つ目の判定の Repeat。高さ 30・半径 18 の円柱で、打ち上げて外へ流れた敵にも届かせる
			MutoDori = {
				Startup = 0.3,
				Active = 1.1,
				Recovery = 0.35,
				CancelFrom = 1.75,
				Advance = 0,
				Interrupt = true,
				Hits = {
					{
						Shape = { Kind = "Sector", Radius = 12, Angle = 360, Height = 10 },
						Power = 2,
						Reaction = "Launch",
						Knockback = 45,
					},
					{
						Shape = { Kind = "Sector", Radius = 18, Angle = 360, Height = 30 },
						Delay = 0.25,
						Repeat = 5,
						Interval = 0.14,
						Power = 1.2,
						Reaction = "Flinch",
						Knockback = 5,
					},
					{
						Shape = { Kind = "Sector", Radius = 18, Angle = 360, Height = 30 },
						Delay = 1,
						Power = 4,
						Reaction = "Knockback",
						Knockback = 60,
					},
				},
			},
			-- 金鬼の金遁。長く溜めてから、地面から金属の刃を突き出す輪を内側から外へ広げて打ち上げ、
			-- 最後の輪（周り全体）で吹き飛ばす。輪は 0.15 秒おきに 6 スタッドずつ外へ広がる
			Kinton = {
				Startup = 0.6,
				Active = 0.9,
				Recovery = 0.4,
				CancelFrom = 1.9,
				Advance = 0,
				Interrupt = true,
				Hits = {
					{
						Shape = { Kind = "Ring", Inner = 0, Radius = 6, Height = 10 },
						Power = 3,
						Reaction = "Launch",
						Knockback = 45,
					},
					{
						Shape = { Kind = "Ring", Inner = 6, Radius = 12, Height = 10 },
						Delay = 0.15,
						Power = 3,
						Reaction = "Launch",
						Knockback = 45,
					},
					{
						Shape = { Kind = "Ring", Inner = 12, Radius = 18, Height = 10 },
						Delay = 0.3,
						Power = 3,
						Reaction = "Launch",
						Knockback = 45,
					},
					{
						Shape = { Kind = "Ring", Inner = 18, Radius = 24, Height = 10 },
						Delay = 0.45,
						Power = 3,
						Reaction = "Launch",
						Knockback = 45,
					},
					{
						Shape = { Kind = "Ring", Inner = 0, Radius = 26, Height = 30 },
						Delay = 0.8,
						Power = 4,
						Reaction = "Knockback",
						Knockback = 70,
					},
				},
			},
		},
	},

	-- 毒。酉花の奥義「毒手裏剣」が当たった敵に付け、毒の間は Interval 秒ごとに Damage を与える（防御で軽減しない）。
	-- 毒の間にもう一度当たると、残りの時間を Duration に戻す。毒でのとどめは毒を付けたプレイヤーの撃破に数える
	Poison = {
		Interval = 1, -- 毒のダメージを与える間隔（秒）
		Damage = 8, -- 1回の毒のダメージ
		Duration = 8, -- 毒が続く秒数
	},

	-- 行動のタイムライン。状態遷移は ActionState.luau が計算する
	-- Startup は判定が出るまで、Active は判定が出ている間、Recovery はその後の硬直の秒数。
	-- 開始から CancelFrom 秒たつと次の行動を受け付ける。Advance は発生と持続の間に前へ進む量。
	-- Interrupt の行動は、受付の前でも今の行動に割り込める。
	-- 通常攻撃・チャージ攻撃・ジャンプ攻撃は Bukishu 節、奥義は Ougi 節の Timelines にある
	Action = {
		BufferTime = 0.4, -- 受け付けられなかった入力を先行入力として持っておく秒数
		-- 被弾の反応。吹き飛びと打ち上げはダウンにし、ダウンの後は起き上がりを続ける
		Flinch = { Startup = 0, Active = 0, Recovery = 0.35, CancelFrom = 0.35, Advance = 0 },
		Down = { Startup = 0, Active = 0, Recovery = 0.8, CancelFrom = 0.8, Advance = 0, Next = "GetUp" },
		GetUp = { Startup = 0, Active = 0, Recovery = 0.5, CancelFrom = 0.5, Advance = 0 },
		-- ガードで受けたときの短い硬直。ガードは続いていて、押したままならガードに戻る
		GuardHit = { Startup = 0, Active = 0, Recovery = 0.25, CancelFrom = 0.25, Advance = 0, Next = "Guard" },
	},

	-- ジャンプ。操作は Roblox 標準の Space と A
	Jump = {
		Height = 7.2, -- ジャンプの高さ（スタッド）。攻撃・ガード・奥義・被弾の最中は 0 にして跳べなくする
		DiveSpeed = 90, -- ジャンプ攻撃で真下へ落ちる速さ（スタッド/秒）。発生までの間だけ落とす
	},

	-- ガード（Shift / L1）。押している間は動けず、向きも変わらない。正面の判定は Guard.luau が計算する
	Guard = {
		Angle = 140, -- 正面とみなす角度（度）。この内からの攻撃は被ダメージ 0 になる
	},

	-- 緊急回避。ガード中に方向を入れて出す。後隙の計算は KinkyuKaihi.luau にある
	KinkyuKaihi = {
		Distance = 14, -- 動く距離（スタッド）
		Duration = 0.3, -- 動いている秒数
		Invulnerable = 0.3, -- 始めてから無敵の秒数
		Recovery = 0.1, -- 1回目の後隙（秒）
		RecoveryPerChain = 0.15, -- 続けて出すたびに後隙へ足す秒数
		MaxRecovery = 0.55, -- 後隙の上限（秒）
		ChainDecay = 0.6, -- 続けた回数が1つ減るまでの秒数（前の回避を始めてから数える）
	},

	-- プレイヤーの被ダメージ。無敵・反応・防御の軽減の判定は Damage.luau が計算する
	Damage = {
		FlinchImmunity = 1, -- のけぞりが明けてから、次の攻撃でのけぞらない秒数（囲まれての連続ののけぞりを防ぐ）
		GetUpInvulnerable = 0.8, -- 起き上がった後の無敵の秒数。ダウンと起き上がりの間も無敵
	},

	-- 攻撃判定の形。形の計算は HitShape.luau にある
	Hitbox = {
		Height = 8, -- 通常攻撃の箱の高さ（スタッド）
		ShowShapes = false, -- 判定の形をデバッグ表示するか。窓口の ShowHitbox でも切り替えられる
		ShapeLifetime = 0.3, -- デバッグ表示を残す秒数
	},

	-- 下忍。色は EnemyService に置く
	Genin = {
		DisplayName = "下忍",
		MaxHealth = 30,
		WalkSpeed = 12,
		Damage = 6,
		AttackRange = 4.5,
		AttackCooldown = 1.5,
		Reaction = "Flinch",
		Scale = 1,
	},

	-- 上忍。色は EnemyService に置く
	Jonin = {
		DisplayName = "上忍",
		MaxHealth = 600,
		WalkSpeed = 14,
		Damage = 20,
		AttackRange = 6,
		AttackCooldown = 1.8,
		Reaction = "Knockback",
		Scale = 1.4,
	},

	-- 敵が攻撃を受けたときの反応。吹き飛びと打ち上げは物理演算に任せず、初速と重力から軌道を決める（Trajectory.luau）。
	-- 着地したらダウンし、しばらくして起き上がる。上忍は反応を弱める倍率で短く飛び、のけぞりにくい
	EnemyReaction = {
		Gravity = 120, -- 吹き飛びと打ち上げで落ちる加速度（スタッド/秒²）
		KnockbackLift = 0.4, -- 吹き飛びの上向きの初速。技の吹き飛ばす強さ（Knockback）に掛ける
		LaunchLift = 1, -- 打ち上げの上向きの初速。技の Knockback に掛ける
		LaunchDrift = 0.15, -- 打ち上げの横向きの初速。技の Knockback に掛ける
		AirLift = 16, -- 空中でのけぞりの攻撃を受けたときに浮かせ直す上向きの初速（スタッド/秒）。追撃で浮かせ続ける
		AirDrift = 3, -- 空中でのけぞりの攻撃を受けたときの横向きの初速（スタッド/秒）
		Flinch = 0.35, -- 地上でのけぞって、動けず攻撃もしない秒数
		Down = 1, -- 着地してから起き上がり始めるまでの秒数
		GetUp = 0.5, -- 起き上がりの秒数
		JoninScale = 0.5, -- 上忍の吹き飛び・打ち上げ・浮かせ直しの初速に掛ける倍率（飛ぶ距離は下忍の 0.25 倍）
		JoninFlinchScale = 0, -- 上忍ののけぞりの秒数に掛ける倍率。0 なら通常攻撃ではのけぞらない
	},

	-- 下忍の体（実体化圏の両軍の下忍の個体と、窓口で出した敵）の動き。敵軍の体は近くのプレイヤーへ近づいて攻撃する。
	-- 味方軍の下忍の個体はプレイヤーを狙わず、部隊について歩く
	EnemyAI = {
		AggroRange = 80, -- 敵軍の体は、この距離（スタッド）までのプレイヤーを狙う。狙う相手がいなければ、下忍の個体は部隊へ戻る
		AITickInterval = 0.25, -- 考える間隔（秒）
		CorpseLifetime = 2, -- 倒れた体を見せておく秒数。過ぎたら体をプール（KotaiPool 節）へ返す
		-- 敵がプレイヤーの手前で止まるときの、敵の体の縁からプレイヤーの中心までの距離（スタッド）。
		-- 敵はプレイヤーと重ならずに周りを囲む（攻撃が届く距離より手前で止まる）
		PlayerGap = 2,
	},

	-- 攻撃トークン。1人のプレイヤーを同時に攻撃できる下忍を絞り、攻撃トークンを持たない下忍は周りを囲んで待つ。
	-- 対象は敵軍の下忍だけ（上忍と首領は攻撃トークンなしで攻撃する。味方軍の下忍は攻撃しない）。計算は KogekiToken.luau にある
	KogekiToken = {
		PerPlayer = 3, -- 1人のプレイヤーを同時に攻撃できる下忍の数（攻撃トークンの数）
		Range = 20, -- プレイヤーからこの距離（スタッド）より近い下忍だけが受け取る。持っている下忍が離れたら返す
		Interval = 1.5, -- 攻撃して返された攻撃トークンを、次の下忍へ渡すまでの秒数
		Rest = 2, -- 攻撃して攻撃トークンを返した下忍が、次に受け取れるまでの秒数
		MaxHold = 4, -- 受け取ってからこの秒数たっても攻撃しない下忍は返す（のけぞらされ続けた、近づけない）
		WaitGap = 5, -- 攻撃トークンを持たない下忍が囲んで待つ位置。攻撃する下忍が止まる位置より、この距離（スタッド）だけ外
	},

	-- プレイヤーの視界。クライアントがカメラの位置・向き・画角を送り、サーバーは下忍を出撃メンバーの視界の外に出す。
	-- 判定は CameraView.luau にある
	CameraView = {
		Interval = 0.5, -- クライアントがカメラを送る間隔（秒）。サーバーはこれより短い間隔で届いた分を捨てる
		Stale = 3, -- 最後に届いてからこの秒数を過ぎたカメラは使わず、キャラクターの向きで代える
		Margin = 14, -- 下忍の部隊を出す位置の周りのこの半径（スタッド）が視界に少しでもかかれば、見えているとみなす（部隊の広がり ±8 と体の大きさ）
		FarDistance = 250, -- カメラからこの距離（スタッド）より遠い位置は、見えないとみなす
		MaxDistance = 200, -- キャラクターからこの距離（スタッド）より遠いカメラは受け付けない
		FallbackHeight = 2, -- カメラが届いていないときに見る位置の、キャラクターの中心からの高さ（スタッド）
		FallbackFov = 70, -- カメラが届いていないときの縦の画角（度）
		FallbackAspect = 1.78, -- カメラが届いていないときの画面の横と縦の比（16:9）
	},

	-- 下忍の個体の枠の配分。個体として出せる下忍の上限（GeninKotai 節の MaxKotai）を、
	-- 近いプレイヤーのまとまりごとに人数の比で分ける。計算は KotaiHaibun.luau にある
	KotaiHaibun = {
		GroupDistance = 80, -- この距離（スタッド）以内のプレイヤーをたどってつなぎ、1つのまとまりにする
	},

	-- 実体化圏の下忍の個体。出撃メンバーの近くに入った両軍の部隊から、下忍を個体として出し、離れたら部隊に戻す。
	-- 出す・消すの半径は Jittaikaken 節、上限の配分は KotaiHaibun 節、数の計算は GeninKotai.luau にある
	GeninKotai = {
		MaxKotai = 40, -- サーバー全体で個体として出す下忍の上限（両軍とパーティー全体の合計。1人あたりではない）
		-- 味方軍の個体の上限（MaxKotai の内数）。味方軍の目標を先にこの数までで決め、敵軍は MaxKotai の残りを使う
		MikataMaxKotai = 10,
		Interval = 0.5, -- 出し入れを決める間隔（秒）
		MaxPerTick = 8, -- 1回の判断で出す個体の上限（まとめて出して負荷の山を作らないように）
		Spread = 10, -- 部隊の位置からこの半径（スタッド）の中に個体を出し、戦う相手がいない個体はこの中へ戻る
		PopDistance = 100, -- 出撃メンバー全員からこの距離（スタッド）より遠い位置なら、視界の中でも出し入れしてよい
		ViewMargin = 3, -- 個体を出し入れする位置の周りのこの半径（スタッド。体の大きさ）が視界にかかれば、見えているとみなす
		HomeRadius = 4, -- 戦う相手がいない個体は、部隊の中の自分の位置からこの距離（スタッド）より離れたら歩いて戻る
	},

	-- 下忍の個体の体のプール（#83）。使い終えた体を壊さずに、ひな形（種類・軍・色）ごとのプールへ返して使い回す。
	-- 数え方は KotaiPool.luau、体の出し入れは EnemyService にある
	KotaiPool = {
		-- 先読みの数。出撃したときに先に作っておく体の数（そのステージの軍のひな形ごと）。個体の上限と同数にする
		-- （敵軍は GeninKotai 節の MaxKotai、味方軍は MikataMaxKotai。近くに味方軍の部隊がいなければ、敵軍は MaxKotai まで出す）
		Prewarm = {
			Mikatagun = 10,
			Tekigun = 40,
		},
		-- プールに置ける体の数の上限（ひな形ごと）。超えて返された体は壊す。倒れた体を見せている間に出し直した分を
		-- 作り直さずに済むよう、先読みの数より多くする
		MaxIdle = {
			Mikatagun = 15,
			Tekigun = 60,
		},
		PrewarmPerFrame = 2, -- 先読みで1フレームに作る体の数（まとめて作って負荷の山を作らないように）
	},

	-- 実体化圏。プレイヤーの周りに入った上忍と首領（両軍）と両軍の部隊の下忍を個体として出し、全員のプレイヤーから離れたら
	-- データに戻す。出現と消滅の半径に差を付け、縁を行き来しても出入りを繰り返さない。判定は Jittaikaken.luau にある
	Jittaikaken = {
		AppearRadius = 120, -- プレイヤーからこの距離（スタッド）まで近づいた上忍と首領を個体で出す
		DisappearRadius = 160, -- 全員のプレイヤーからこの距離より離れた個体を消す。体力はデータに残る
		Interval = 0.25, -- 出し入れを確かめ、個体の位置をデータへ写し、上忍と首領が考える（Kata 節の戦い方と秘計の判断）間隔（秒）
		HomeRadius = 6, -- 個体が戻る位置（率いる部隊の位置、首領は本陣）からこの距離（スタッド）より離れたら歩いて戻る
		CorpseLifetime = 3, -- 倒れた個体を消すまでの秒数
	},

	-- 上忍と首領の個体の戦い方（敵軍は出撃メンバー、味方軍は敵軍の下忍を狙う）。狙う相手を選んで間合いまで近づき、型を出す。
	-- 判断は Kata.luau にある。
	-- 型は予備動作（足元に判定の範囲が出て、体が光る）の後に判定を出し、後隙の間は動かない。時間は上忍の攻撃の速さで割る。
	-- 考える間隔は Jittaikaken 節の Interval
	Kata = {
		AggroRange = 50, -- 個体からこの距離（スタッド）までの相手を狙う
		-- 上忍が戻る位置（率いる部隊の位置）から、追いかけて離れてよい距離（スタッド）。首領は本陣の範囲の中を追いかける
		ChaseRadius = 40,
		AttackerMemory = 5, -- 最後に攻撃してきた相手を、ほかの相手より先に狙う秒数
		SwitchMargin = 6, -- 狙っている相手より、この距離（スタッド）以上近い相手がいたら狙いを替える
		Maai = 5, -- 狙う相手の中心からこの距離（スタッド）の位置まで近づいて止まる。型の Maai はこれより長くする
		Interval = 1.2, -- 型を出し終えてから、次の型を選ぶまでの秒数
		IntervalRandom = 0.8, -- 次の型を選ぶまでの秒数に、0 からこの秒数までを乱数で足す（型を出す拍子を読ませない）
		-- 上忍と首領が出す型
		Jonin = {
			-- 袈裟斬り。素早く前を斬る
			Kesagiri = {
				Maai = 7,
				Weight = 4,
				YobiDosa = 0.5,
				Active = 0.1,
				Recovery = 0.6,
				Hits = {
					{
						Shape = { Kind = "Box", Range = 8, Width = 7 },
						Power = 1.2,
						Reaction = "Flinch",
						Knockback = 8,
					},
				},
			},
			-- 連斬。前を2回斬り、3回目で吹き飛ばす
			Renzan = {
				Maai = 7,
				Weight = 3,
				YobiDosa = 0.6,
				Active = 0.5,
				Recovery = 0.7,
				Hits = {
					{
						Shape = { Kind = "Box", Range = 8, Width = 8 },
						Repeat = 2,
						Interval = 0.2,
						Power = 0.8,
						Reaction = "Flinch",
						Knockback = 6,
					},
					{
						Shape = { Kind = "Box", Range = 9, Width = 9 },
						Delay = 0.45,
						Power = 1.5,
						Reaction = "Knockback",
						Knockback = 40,
					},
				},
			},
			-- 旋風。長く構えてから周りを斬って吹き飛ばす
			Senpu = {
				Maai = 6,
				Weight = 2,
				YobiDosa = 0.9,
				Active = 0.1,
				Recovery = 0.8,
				Hits = {
					{
						Shape = { Kind = "Sector", Radius = 9, Angle = 360 },
						Power = 1.8,
						Reaction = "Knockback",
						Knockback = 45,
					},
				},
			},
			-- 手裏剣打ち。離れた相手へ手裏剣を1枚投げる
			Shurikenuchi = {
				Maai = 24,
				Weight = 2,
				YobiDosa = 0.6,
				Active = 0.1,
				Recovery = 0.6,
				Hits = {
					{
						Shape = { Kind = "Line", Length = 30, Width = 3, Speed = 90 },
						Power = 1,
						Reaction = "Flinch",
						Knockback = 6,
					},
				},
			},
		},
		-- 首領だけが出す型
		Shuryo = {
			-- 大地割り。長く構えてから地面を割り、周りをまとめて打ち上げる
			Daichiwari = {
				Maai = 8,
				Weight = 3,
				YobiDosa = 1.2,
				Active = 0.1,
				Recovery = 1,
				Hits = {
					{
						Shape = { Kind = "Sector", Radius = 14, Angle = 360, Height = 10 },
						Power = 2.2,
						Reaction = "Launch",
						Knockback = 50,
					},
				},
			},
			-- 衝撃波。前へ遠くまで届く衝撃波で吹き飛ばす
			Shogekiha = {
				Maai = 18,
				Weight = 2,
				YobiDosa = 0.9,
				Active = 0.2,
				Recovery = 0.9,
				Hits = {
					{
						Shape = { Kind = "Box", Range = 22, Width = 6 },
						Power = 2,
						Reaction = "Knockback",
						Knockback = 55,
					},
				},
			},
		},
	},

	-- 交戦。部隊どうしの押し合いの損害を Kosen.luau で計算する
	Kosen = {
		StartDistance = 30, -- 敵味方の部隊がこの距離（スタッド）まで近づくと交戦を始める
		Zensenhaba = 10, -- 一度に刃を交えられる兵数の上限
		ReserveWeight = 0.3, -- 前線の後ろに控える兵1人が押す力に加わる割合
		ShikiEffect = 0.01, -- 士気の差 1 あたりの押す力の増減の割合
		ShikiHoseiMin = 0.3, -- 士気の差による押す力の倍率の下限
		ShikiHoseiMax = 2, -- 士気の差による押す力の倍率の上限
		LossRate = 0.02, -- 押す力 1 が相手に与える 1 秒あたりの損害（兵数）
		MaxStep = 0.5, -- 1 回に進める時間の上限（秒）。長い経過時間はこの幅に刻んで計算する
		-- 軍ごとの強さの倍率。味方軍は敵軍よりやや弱くする
		GunStrength = {
			Mikatagun = 0.9,
			Tekigun = 1,
		},
		-- 両軍の上忍がいる部隊どうしの交戦では、上忍同士も戦う
		JoninPower = 0.6, -- 上忍同士の戦いで、1秒あたりに与えるダメージの技の倍率（攻撃を相手の防御で軽減し、士気の差の倍率を掛ける）
		JoninShikiThreshold = 20, -- 味方軍の上忍が敵の上忍を削れる、部隊の士気の差の下限。敵軍の上忍に条件は無い
	},

	-- 交戦中の部隊の下忍の個体の見せ方。2つの部隊の位置を結ぶ線の中ほど（前線）に、部隊ごとに前線幅（Kosen 節の Zensenhaba）
	-- までの個体が向かい合って並び、残りは後ろに控える。前線の個体は向かい合う相手へ攻撃の動作をするが、当たり判定は無い
	-- （勝敗と損害は交戦の計算に従う）。並びの計算は Zensen.luau にある
	Zensen = {
		Gap = 4, -- 向かい合う両軍の前線の列の間（スタッド）。下忍の攻撃が届く距離（Genin 節の AttackRange）より短くする
		Spacing = 4, -- 列の中で隣り合う個体の間隔（スタッド）。腕まで含めた体の横幅に合わせる
		RowGap = 4, -- 前線の後ろに控える列の間隔（スタッド）
		AttackInterval = 1.5, -- 前線の個体が攻撃の動作をする間隔（秒）
		AttackRandom = 1, -- 攻撃の動作の間隔に、0 からこの秒数までを乱数で足す（前線の個体がそろって振らないように）
		-- 交戦中の敵軍の個体は、この距離（スタッド。個体の位置から測る）までのプレイヤーを狙う（攻撃トークンに従う）。
		-- 追ってくる個体からこの距離より離れると、前線へ戻る。攻撃トークンを受け取れる距離（KogekiToken 節の Range）以下にする
		AggroRange = 15,
	},

	-- 部隊。配置の構成（拠点・つながり・部隊）は Haichi.luau にあり、移動の計算は Butai.luau にある
	Butai = {
		Speed = 12, -- 部隊が目的地へ進む速さ（スタッド/秒）。下忍の歩く速さに合わせる
		MoveInterval = 0.5, -- 部隊の位置を進める間隔（秒）
		JoninGekihaShiki = 15, -- 率いる上忍が倒されたときに、残った部隊の士気をずっと下げる量
		Heisu = {
			-- 試験用ステージ。率いる上忍のいる部隊は 30、本陣の守備は 40
			Test = {
				Mikata1 = 30,
				Mikata2 = 40,
				Teki1 = 30,
				Teki2 = 30,
				Teki3 = 40,
			},
		},
	},

	-- 方針。上忍が部隊を率いて、配置で決めた方針（攻略・防衛・救援）に沿って目的地を決める。判断は Hoshin.luau にある
	Hoshin = {
		Interval = 2, -- 方針を判断し直す間隔（秒）
		GeigekiDistance = 120, -- 防衛の部隊が迎え撃つ相手の部隊の、担当の拠点の中心からの距離の上限（スタッド）
		-- 救援が要る拠点（攻める軍がいる自分の軍の拠点）の、耐久の上限に対する割合の上限。
		-- 救援の部隊が向かう拠点と、プレイヤーの救援数を数える拠点に使う
		KyuenRate = 0.8,
	},

	-- 拠点の耐久と制圧。範囲の中でその拠点の軍の下忍が倒れると耐久が減り、0 で相手の軍に制圧される。計算は Kyoten.luau にある
	Kyoten = {
		Taikyu = {
			Kyoten = 30, -- 通常拠点の耐久の上限。守備の下忍30体ほどを倒しきると制圧できる
			Honjin = 50, -- 本陣の耐久の上限
		},
		SeiatsuRate = 0.5, -- 制圧した直後の耐久。上限に掛ける割合
		GeninGekiha = 1, -- 範囲の中でその拠点の軍の下忍が1人倒れたときに減る耐久
		-- 守備の補充。耐久が残る間、守備の兵数が上限より少なければ、間隔ごとに守備の部隊へ足す
		Shubi = {
			Kyoten = 30, -- 通常拠点の守備の兵数の上限
			Honjin = 40, -- 本陣の守備の兵数の上限
		},
		HojuInterval = 10, -- 守備を補充する間隔（秒）
		HojuHeisu = 2, -- 1回に補充する兵数
		MushubiGensho = 1, -- 守備のいない拠点で、攻める軍が範囲の中にいる間に1秒あたり減る耐久
		TickInterval = 0.5, -- 補充と守備のいない拠点の減少を進める間隔（秒）
	},

	-- 支配エリア。兵站線でつながった拠点の周りは、その拠点の軍の支配エリアになり、その軍の部隊と上忍・首領の能力が上がる。
	-- 判定は ShihaiArea.luau にある
	ShihaiArea = {
		Radius = 120, -- 拠点の中心からこの距離（スタッド）までが、その拠点の軍の支配エリア
		Push = 1.2, -- 支配エリアの中の部隊の、交戦の押す力の倍率（Kosen.luau の押す力に掛ける）
		Attack = 1.2, -- 支配エリアの中の上忍と首領の攻撃の倍率
		Defense = 1.2, -- 支配エリアの中の上忍と首領の防御の倍率
	},

	-- 士気。軍全体の士気を軍ごとに1本持ち、部隊の士気はそれに近くの出来事の補正を足して決める。計算は Shiki.luau にある。
	-- 交戦の押し合いは部隊どうしの士気の差で決まる（Kosen 節の ShikiEffect）
	Shiki = {
		Initial = 50, -- 軍全体の士気の開始時の値。部隊の士気も同じ値から始まる
		Min = 0, -- 軍全体と部隊の士気の下限
		Max = 100, -- 軍全体と部隊の士気の上限
		Radius = 150, -- 出来事の補正が届く距離（スタッド）。出来事の位置で最大、この距離で 0 になる
		Duration = 60, -- 出来事の補正が消えるまでの秒数。同じ速さで 0 へ戻る
		-- 出来事の種類ごとの上下の量
		Dekigoto = {
			JoninGekiha = { Gun = 5, Butai = 15 }, -- 上忍の撃破。得をするのは倒した側の軍
			KyotenKanraku = { Gun = 5, Butai = 15 }, -- 拠点の陥落。得をするのは制圧した側の軍
			Hikei = { Gun = 2, Butai = 10 }, -- 秘計の発動。得をするのは使った側の軍
		},
	},

	-- 秘計。持ち込みの上限枚数はボタンの数に合わせた仕様値なので Hikei.luau に置く
	Hikei = {
		-- 効果時間（秒）。ここに無い秘計の効果は期限なし（兵糧庫と爆破罠は拠点を失うまで残る）
		Duration = {
			Fukuhei = 120, -- 伏兵部隊が潜んでいられる時間
			Rakuseki = 90, -- 岩が道を塞いでいる時間
			Chohatsu = 15, -- 相手の上忍を誘い出す時間
			Kishinka = 60,
			Daikatsu = 30, -- 動揺させる時間
		},
		-- 発動者から対象の地点までの距離の上限（スタッド）。これより遠い地点しか無ければ発動できない
		TargetRange = {
			Rakuseki = 60, -- 落石地点まで
			Daikakei = 60, -- 大火計地域の縁まで（中にいれば 0）
		},
		TickInterval = 0.5, -- 効果の期限切れを確かめる間隔（秒）
		NoticeTime = 4, -- 秘計の発動・打ち消し・期限切れ・失敗の知らせを画面に出しておく秒数
	},

	-- 秘計の伏兵。発動者の足元に潜ませる伏兵部隊と、近づいた相手への奇襲。判定は Fukuhei.luau にある。
	-- 潜んでいられる時間は Hikei 節の Duration.Fukuhei
	Fukuhei = {
		Heisu = 20, -- 伏兵部隊の兵数
		KishuRadius = 40, -- 相手の部隊かプレイヤーがこの距離（スタッド）まで近づくと奇襲する
		KishuShiki = 15, -- 奇襲された相手の部隊の士気をずっと下げる量
	},

	-- 秘計の鬼神化。効果中は発動者の攻撃と防御が上がり、のけぞらない（吹き飛びと打ち上げのダウンは受ける）。
	-- 効果時間は Hikei 節の Duration.Kishinka。補正は Kishinka.luau が作る
	Kishinka = {
		Attack = 1.5, -- 攻撃の倍率
		Defense = 1.5, -- 防御の倍率。今の防御の値（10 前後）では、受けるダメージは 5% ほどしか減らない
	},

	-- 秘計の大喝。発動者から Radius 以内の相手の強化の秘計（鬼神化）を打ち消し、相手の上忍・首領・プレイヤー・部隊を動揺させる。
	-- 動揺の時間は Hikei 節の Duration.Daikatsu。対象の選び方と補正は Daikatsu.luau にある
	Daikatsu = {
		Radius = 40, -- 発動者からこの距離（スタッド）までの相手が対象
		Attack = 0.7, -- 動揺した上忍・首領・プレイヤーの攻撃の倍率
		Defense = 0.7, -- 動揺した上忍・首領・プレイヤーの防御の倍率
		Shiki = 15, -- 動揺した部隊の士気を下げる量（動揺の間だけ）
	},

	-- 秘計の大火計。発動者から Hikei 節の TargetRange.Daikakei 以内で一番近い大火計地域に火を放ち、
	-- 地域の中の相手の上忍・首領・プレイヤー・下忍にダメージを与え、部隊の兵数を減らす。計算は Daikakei.luau にある
	Daikakei = {
		Power = 120, -- 上忍・首領・プレイヤー・下忍の個体に与えるダメージの威力（受ける側の防御で軽減する前）
		HeisuRate = 0.5, -- 地域の中の部隊の兵数を減らす割合（端数は切り上げる）
		FireTime = 3, -- 地域に炎の仮の見た目を出しておく秒数
	},

	-- 秘計の爆破罠。発動者が中にいる自分の軍の拠点に仕掛け、耐久が上限の Rate を上から下へ越えた瞬間に1回だけ爆発して、
	-- 拠点の中の相手の上忍・首領・プレイヤー・下忍を吹き飛ばし、部隊の兵数を減らす。計算は Bakuhawana.luau にある
	Bakuhawana = {
		Rate = 1 / 3, -- 爆発する耐久の、耐久の上限に対する割合
		Power = 80, -- 上忍・首領・プレイヤー・下忍の個体に与えるダメージの威力（受ける側の防御で軽減する前）
		HeisuRate = 0.5, -- 拠点の中の相手の部隊の兵数を減らす割合（端数は切り上げる）
		Knockback = 60, -- 下忍の個体を吹き飛ばす強さ（技の Knockback と同じ。EnemyReaction 節で軌道にする）
	},

	-- 秘計の挑発。発動者から Radius 以内の相手の上忍（首領は除く）を、効果時間の間、発動者のもとへ誘い出す。
	-- 誘い出す時間は Hikei 節の Duration.Chohatsu。対象の選び方は Chohatsu.luau にある。
	-- 誘い出された上忍は、上忍の歩く速さ（Stats 節の WalkSpeed）で発動者へ向かい、
	-- Jittaikaken 節の HomeRadius の距離で止まる
	Chohatsu = {
		Radius = 100, -- 発動者からこの距離（スタッド）までの相手の上忍が対象（実体化圏の AppearRadius より内）
	},

	-- 秘計の判断。敵軍の上忍と首領が、考える間隔（Jittaikaken 節の Interval）ごとに秘計を使うかを決める。
	-- 判断は HikeiHandan.luau にある。鬼神化は率いる部隊が交戦中か首領の体力が減ったとき、
	-- 大喝は Daikatsu 節の Radius 以内に強化の秘計の効果中の相手がいるとき、
	-- 挑発は Chohatsu 節の Radius 以内に誘い出されていない相手の上忍がいるときに使う。
	-- 伏兵は中にいる拠点に相手が FukuheiDistance まで迫ったとき、落石は一番近い落石地点の区間が相手の軍の兵站線にあるとき、
	-- 大火計は一番近い大火計地域の中の相手が DaikakeiAite 以上のときに使う（地点と地域を選ぶ距離は Hikei 節の TargetRange）
	HikeiHandan = {
		Interval = 1, -- 上忍と首領ごとに、秘計を使うかを判断する間隔（秒）。考える間隔ごとに呼ばれるのを間引く
		UseInterval = 30, -- 敵軍のだれかが秘計を使ってから、敵軍のだれかが次の秘計を使えるまでの秒数（敵軍全体の使用間隔）
		RetryInterval = 10, -- 発動できなかった秘計を、同じ上忍か首領が試し直すまでの秒数
		ShuryoHealthRate = 0.5, -- 首領が鬼神化を使う、体力の上限に対する割合の上限（これ以下で使う）
		-- 爆破罠は、中にいる自分の軍の拠点の中心からこの距離（スタッド）以内にプレイヤーが来たら使う。
		-- 本陣（110 × 110）の隅（約 78）より遠くし、プレイヤーが拠点に入る前に仕掛ける
		BakuhawanaRadius = 100,
		-- 伏兵を使う、中にいる自分の軍の拠点に迫った相手（部隊かプレイヤー）の、拠点の中心からの距離の上限（スタッド）。
		-- 伏兵部隊が奇襲する距離（Fukuhei 節の KishuRadius）より遠くで潜ませる
		FukuheiDistance = 100,
		-- 大火計を使う、一番近い大火計地域の中の相手の数の下限（これ以上で使う）。
		-- プレイヤー・上忍・首領・部隊を1つずつ数える（上忍が率いる部隊は、上忍と部隊で2つ）
		DaikakeiAite = 3,
	},

	-- 秘計の系統と熟練度。プレイヤーは系統ごとに熟練度を持ち、覚える値に達した系統の秘計を順に覚える。
	-- 出撃前に選べるのは覚えた秘計だけ。計算は Jukurendo.luau にある。
	-- 熟練度を上げる戦い方は、武勇（Buyu）が撃破数、知略（Chiryaku）が制圧数、堅牢（Kenro）が救援数。
	-- ステージが決着したとき（勝ちも負けも）に、出撃して残っている人へ足す。試験用ステージでも足す（確認のため）。
	-- 覚える値が 0 の秘計（各系統の最初の1枚）は最初から覚えている。新規の人も持ち込みの上限まで選べる数にする。
	-- 1回のステージで上限（Max）まで上げると、2枚目は1回、3枚目は4回で覚える
	Jukurendo = {
		Keito = {
			-- 武勇。自分で戦う秘計
			Buyu = {
				Hikei = {
					{ Id = "Kishinka", Jukurendo = 0 },
					{ Id = "Daikatsu", Jukurendo = 30 },
					{ Id = "Chohatsu", Jukurendo = 100 },
				},
				Rate = 0.1, -- 撃破数1あたりの熟練度（撃破数 10 で 1）
				Max = 30, -- 1回のステージで足す熟練度の上限（撃破数 300）
			},
			-- 知略。相手の拠点と兵站線を攻める秘計
			Chiryaku = {
				Hikei = {
					{ Id = "Rakuseki", Jukurendo = 0 },
					{ Id = "Daikakei", Jukurendo = 30 },
				},
				Rate = 10, -- 制圧数1あたりの熟練度
				Max = 30, -- 1回のステージで足す熟練度の上限（制圧数 3）
			},
			-- 堅牢。味方の拠点を守る秘計
			Kenro = {
				Hikei = {
					{ Id = "Fukuhei", Jukurendo = 0 },
					{ Id = "Hyoroko", Jukurendo = 30 },
					{ Id = "Bakuhawana", Jukurendo = 100 },
				},
				Rate = 1, -- 救援数1あたりの熟練度
				Max = 30, -- 1回のステージで足す熟練度の上限（救援数 30）
			},
		},
	},

	-- 台詞。イベントシーンの会話窓と、戦闘中に画面の端へ出す台詞。台詞の文は Serifu.luau にある
	Serifu = {
		-- 会話窓は全員が同じ進行で見るよう、ボタンでなく時間で送る
		CharInterval = 0.04, -- 会話窓に1文字ずつ出す間隔（秒）
		HoldTime = 1.5, -- 全部出し終えてから次の台詞へ送るまでの秒数
		HoldPerChar = 0.03, -- 長い台詞ほど長く見せるため、1文字ごとに送るまでの秒数へ足す秒数
		BattleTime = 4, -- 戦闘中の台詞を1本出しておく秒数
		BattleQueueMax = 3, -- 戦闘中の台詞の順番待ちの上限。超えたら古い台詞から捨てる
	},

	-- 効果音。素材は Sounds.luau の登録表にあり、SoundPlayer.luau が鳴らす
	Sound = {
		-- 効果音ごとの音量（Sound.Volume）。登録表の名前ごとに置く。Guard 以降は音を聞いて合わせる前の仮の値
		Volume = {
			Swing = 0.5,
			Hit = 0.6,
			ChargeKogeki = 0.6,
			Ougi = 0.8,
			Hurt = 0.7,
			Confirm = 0.5,
			Cancel = 0.5,
			Guard = 0.6,
			KinkyuKaihi = 0.5,
			Down = 0.7, -- 被弾（Hurt）と同じ大きさ
			Seiatsu = 0.6,
			Kanraku = 0.6,
			HikeiHatsudo = 0.6,
			Cursor = 0.4, -- 続けて何度も鳴るので、決定と取り消し（0.5）より下げる
		},
		RollOffMinDistance = 10, -- 戦闘の効果音が小さくなり始める距離（スタッド）
		RollOffMaxDistance = 150, -- 戦闘の効果音が聞こえなくなる距離（スタッド）
		HitInterval = 0.06, -- 1人の攻撃の命中の音を続けて鳴らす最短の間隔（秒）。まとめて当てたときに重ならないように
	},

	-- BGM。曲は Bgm.luau の登録表にあり、クライアントの BgmController が場面に合わせて流す
	Bgm = {
		-- 場面ごとの音量（Sound.Volume）。登録表の場面ごとに置く。曲を聞いて合わせる前の仮の値
		Volume = {
			Lobby = 0.3,
			EventScene = 0.25, -- 会話窓を読む間なので少し下げる
			Battle = 0.3, -- 戦闘の効果音（Sound 節の 0.5〜0.8）が聞こえるよう、効果音より下げる
			Victory = 0.35,
			Defeat = 0.3,
		},
		FadeTime = 1.5, -- 場面が変わったときに、前の曲を下げきって次の曲を上げきるまでの秒数（両方を同時に進める）
	},

	-- 画面上部の戦況の表示（軍全体の士気・残り時間・兵力）。強調の判断は BattleStatus.luau にある
	BattleStatus = {
		TimeWarning = 300, -- 戦闘の残り時間がこの秒数以下になったら、残り時間を黄色で出す
		TimeDanger = 60, -- 戦闘の残り時間がこの秒数以下になったら、残り時間を赤で出す
	},

	-- ミニマップ。描き方の計算は Minimap.luau にある
	Minimap = {
		UpdateInterval = 0.25, -- 自分と仲間の位置を描き直す間隔（秒）。サーバーが出撃メンバーの位置を複製する間隔も同じ
	},

	-- スマホ横画面の戦闘の操作ボタン（タッチの操作）。配置の計算は TouchLayout.luau、出すかの判断は TouchControls.luau にある。
	-- 大きさと余白は、戦闘の画面を縮める前の大きさ（設計の大きさ）のピクセル。実際の画面では倍率を掛けた大きさになる
	TouchControls = {
		-- 戦闘の画面を縮めて、縮める前の大きさの画面がこの幅と高さ以上になるようにする（大きい画面では縮めない）。
		-- 高さは、スマホでジャンプボタンの上にガードと奥義が入るように決める
		DesignWidth = 1120,
		DesignHeight = 640,
		Margin = 24, -- 画面の端からの余白（HUD と同じ）
		Gap = 12, -- ボタンどうしと、ほかの画面の部品との間隔
		AttackSize = 140, -- 通常攻撃のボタンの直径。ジャンプボタンの左に置く
		ChargeKogekiSize = 110, -- チャージ攻撃のボタンの直径。通常攻撃の左に置く
		-- ガードと奥義のボタンの直径。ジャンプボタンの上（ミニマップの下）に、ミニマップの幅に収まるように並べる。
		-- スマホでも指で押せる大きさ（44 ピクセル）を下回らないようにする
		GuardSize = 94,
		OugiSize = 94,
		-- 秘計の枚のボタンの幅と高さ。左上の撃破数の下に横に並べる
		HikeiWidth = 140,
		HikeiHeight = 96,
		-- タッチの配置で積む秘計の知らせの数の上限（超えたら古いものから消す）。知らせは文字が読めるよう
		-- ほかの部品ほど縮めないので（SmallScreen 節の MinTextSize）、積む数を減らしてボタンと重ねない
		HikeiNoticeMax = 1,
	},

	-- 小さい画面（スマホ横画面）の配置と、読める文字の大きさ。計算は SmallScreen.luau にある。
	-- 大きさは実際の画面のピクセル（スマホでは端末の point。iPhone SE の横画面は 667x375）
	SmallScreen = {
		-- 安全な範囲（Roblox のトップバーと、端末のノッチやホームバーを除いた範囲）の幅か高さがこれに満たない画面を
		-- 小さい画面とし、出撃前の画面・特技ツリーの窓・リザルト・タイトル画面・会話窓を詰めて並べる。
		-- 幅はロビーの非公式の表記と出撃前の画面が横に並ぶ幅（16 + 480 + 16 + 460 + 16）、高さは出撃前の画面の欄の
		-- スクロールに 160 ほど残る高さ。PC の窓（1280x600 で安全な範囲は 1280x542）とタブレットは大きい画面のまま
		Width = 1000,
		Height = 480,
		Margin = 8, -- 小さい画面での、画面の端と部品の間の余白
		Gap = 8, -- 小さい画面での、部品どうしの間隔
		-- 読める文字の下限。スマホで漢字の線がつぶれずに読める大きさとして 12 にする。小さい画面では文字を縮めずに使い
		-- （一番小さい Ui.TextSize.Small は 14）、戦闘の画面を縮めるときも、台詞と秘計の知らせはこれを下回るほど縮めない
		MinTextSize = 12,
		MinTouchSize = 44, -- 指で押せるボタンの短い辺の下限（TouchLayout の操作ボタンと同じ 44）
		-- ロビー。左上に非公式の表記、右に出撃前の画面を並べる。出撃前の画面の幅は下限と上限の間で、表記に NoticeMinWidth を残す。
		-- NoticeMinWidth は、表記の見出し（Ui.TextSize.Large で9文字）が内側の余白を除いて収まる幅
		NoticeMinWidth = 248,
		PanelMinWidth = 360,
		PanelMaxWidth = 460, -- 大きい画面の出撃前の画面の幅（SelectionController の PANEL_WIDTH）
		-- 会話窓（イベントシーン）の高さと、顔グラフィックの一辺。台詞は Ui.TextSize.Large から 14 まで縮めて収める
		DialogueHeight = 128,
		DialogueFaceSize = 104,
		-- タッチの端末のイベントシーンのスキップのボタンの幅と高さ。安全な範囲の右上に置く
		SkipWidth = 220,
		SkipHeight = 52,
	},
}

return Config
