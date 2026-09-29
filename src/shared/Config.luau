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
	DefenseHalf: number,
	MinDamage: number,
}

export type ComboStep = {
	Damage: number,
	Range: number,
	Width: number,
	Knockback: number,
}

export type ComboSection = {
	ComboResetTime: number,
	Steps: { ComboStep },
}

export type ChargeKogekiSection = {
	Damage: number,
	Radius: number,
	Knockback: number,
}

export type OugiSection = {
	PerStock: number,
	MaxStock: number,
	InitialStock: number,
	GainPerHit: number,
	GainPerDamageTaken: number,
	Pulses: number,
	PulseInterval: number,
	Radius: number,
	DamagePerPulse: number,
	Knockback: number,
}

-- 攻撃を受けた側の反応。None は中断しない、Flinch はのけぞり、Knockback は吹き飛び、Launch は打ち上げ
export type Reaction = "None" | "Flinch" | "Knockback" | "Launch"

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
}

export type ActionSection = {
	BufferTime: number,
	Attack: { ActionTimeline },
	ChargeKogeki: ActionTimeline,
	Ougi: ActionTimeline,
	Flinch: ActionTimeline,
	Down: ActionTimeline,
	GetUp: ActionTimeline,
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

export type SpawnerSection = {
	MaxAlive: number,
	ButaiSize: number,
	ButaiInterval: number,
	JoninEvery: number,
	MinDistance: number,
	MaxDistance: number,
	AggroRange: number,
	AITickInterval: number,
	CorpseLifetime: number,
}

export type KosenSection = {
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
}

export type HikeiSection = {
	Duration: { [string]: number },
}

export type PartySection = {
	MaxMembers: number,
}

export type Config = {
	Party: PartySection,
	Stats: StatsSection,
	Combo: ComboSection,
	ChargeKogeki: ChargeKogekiSection,
	Ougi: OugiSection,
	Action: ActionSection,
	Damage: DamageSection,
	Hitbox: HitboxSection,
	Genin: EnemySection,
	Jonin: EnemySection,
	Spawner: SpawnerSection,
	Kosen: KosenSection,
	Hikei: HikeiSection,
}

local Config: Config = {
	-- パーティー。1サーバーが1パーティーにあたる。Roblox のサーバーの最大人数も同じ値にする
	Party = {
		MaxMembers = 4,
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
		DefenseHalf = 100, -- 防御がこの値のとき、受けるダメージが半分になる
		MinDamage = 1, -- 与ダメージの下限
	},

	-- 通常攻撃のコンボ。1段ずつ順に出て、ComboResetTime 秒以内に次を押すと繋がる。
	-- 段ごとの時間は Action 節の Attack にある
	Combo = {
		ComboResetTime = 0.8,
		Steps = {
			{ Damage = 12, Range = 7, Width = 8, Knockback = 10 },
			{ Damage = 12, Range = 7, Width = 8, Knockback = 10 },
			{ Damage = 16, Range = 8, Width = 10, Knockback = 14 },
			{ Damage = 28, Range = 10, Width = 14, Knockback = 45 },
		},
	},

	-- チャージ攻撃（右クリック / E）。周囲を吹き飛ばす
	ChargeKogeki = {
		Damage = 30,
		Radius = 12,
		Knockback = 60,
	},

	-- 奥義（Q）と奥義ゲージ。ストック1本で1回発動する。本数の計算は OugiGauge.luau にある
	Ougi = {
		PerStock = 100, -- 1本分の量
		MaxStock = 4, -- 本数の上限
		InitialStock = 1, -- 最初に持っている本数
		GainPerHit = 2,
		GainPerDamageTaken = 0.5,
		Pulses = 6,
		PulseInterval = 0.2,
		Radius = 18,
		DamagePerPulse = 40,
		Knockback = 30,
	},

	-- 行動のタイムライン。状態遷移は ActionState.luau が計算する
	-- Startup は判定が出るまで、Active は判定が出ている間、Recovery はその後の硬直の秒数。
	-- 開始から CancelFrom 秒たつと次の行動を受け付ける。Advance は行動中に前へ進む量。
	-- Interrupt の行動は、受付の前でも今の行動に割り込める
	Action = {
		BufferTime = 0.4, -- 受け付けられなかった入力を先行入力として持っておく秒数
		-- 通常攻撃の段ごと。Combo.Steps と同じ順に並べる
		Attack = {
			{ Startup = 0, Active = 0.08, Recovery = 0.2, CancelFrom = 0.28, Advance = 0 },
			{ Startup = 0, Active = 0.08, Recovery = 0.2, CancelFrom = 0.28, Advance = 0 },
			{ Startup = 0, Active = 0.08, Recovery = 0.24, CancelFrom = 0.32, Advance = 0 },
			{ Startup = 0, Active = 0.1, Recovery = 0.5, CancelFrom = 0.6, Advance = 0 },
		},
		ChargeKogeki = { Startup = 0, Active = 0.1, Recovery = 1.1, CancelFrom = 1.2, Advance = 0 },
		-- 持続は Ougi.Pulses × Ougi.PulseInterval と同じにする
		Ougi = { Startup = 0, Active = 1.2, Recovery = 0, CancelFrom = 1.2, Advance = 0, Interrupt = true },
		-- 被弾の反応。吹き飛びと打ち上げはダウンにし、ダウンの後は起き上がりを続ける
		Flinch = { Startup = 0, Active = 0, Recovery = 0.35, CancelFrom = 0.35, Advance = 0 },
		Down = { Startup = 0, Active = 0, Recovery = 0.8, CancelFrom = 0.8, Advance = 0, Next = "GetUp" },
		GetUp = { Startup = 0, Active = 0, Recovery = 0.5, CancelFrom = 0.5, Advance = 0 },
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

	-- 暫定の湧き処理。実体化圏での出し入れができたら置き換える
	Spawner = {
		MaxAlive = 40,
		ButaiSize = 8,
		ButaiInterval = 3,
		JoninEvery = 5, -- 何部隊ごとに上忍を出すか
		MinDistance = 60,
		MaxDistance = 140,
		AggroRange = 80,
		AITickInterval = 0.25,
		CorpseLifetime = 2,
	},

	-- 交戦。部隊どうしの押し合いの損害を Kosen.luau で計算する
	Kosen = {
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
	},
}

return Config
