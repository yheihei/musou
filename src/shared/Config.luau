--!strict
-- ゲームバランス調整用の定数。数値チューニングはこのファイルだけで完結させる。
--
-- 節の足し方
-- 1. 機能ごとに節を1つ足す。節名は CONTEXT.md の語の識別子（ADR 0005）にし、
--    CONTEXT.md に無い機能は英語にする（Player、Combo など）
-- 2. 節の型を `export type <節名>Section` で公開し、`Config` 型に同じ名前で足す
-- 3. 節の前に見出しのコメントを置き、何に使う値かを書く
-- 4. 値は数値・文字列・真偽値と、それらの表だけにする
--    Color3・Vector3・Enum など Roblox の型は、使う側のモジュールに置く（Lune のテストで読むため）
-- 5. Config.spec.luau は、節の整理で値が変わっていないことを確かめるスナップショットを持つ
--    値を調整したときは、同じ変更でスナップショットも直す

export type PlayerSection = {
	WalkSpeed: number,
	MaxHealth: number,
}

export type ComboStep = {
	Damage: number,
	Range: number,
	Width: number,
	Cooldown: number,
	Knockback: number,
}

export type ComboSection = {
	ComboResetTime: number,
	Steps: { ComboStep },
}

export type ChargeKogekiSection = {
	Damage: number,
	Radius: number,
	Cooldown: number,
	Knockback: number,
}

export type OugiSection = {
	MaxGauge: number,
	GainPerHit: number,
	GainPerDamageTaken: number,
	Pulses: number,
	PulseInterval: number,
	Radius: number,
	DamagePerPulse: number,
	Knockback: number,
}

-- 下忍と上忍で共通の敵の能力値
export type EnemySection = {
	DisplayName: string,
	MaxHealth: number,
	WalkSpeed: number,
	Damage: number,
	AttackRange: number,
	AttackCooldown: number,
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

export type Config = {
	Player: PlayerSection,
	Combo: ComboSection,
	ChargeKogeki: ChargeKogekiSection,
	Ougi: OugiSection,
	Genin: EnemySection,
	Jonin: EnemySection,
	Spawner: SpawnerSection,
	Kosen: KosenSection,
}

local Config: Config = {
	-- プレイヤーのキャラクター。移動速度と体力
	Player = {
		WalkSpeed = 24,
		MaxHealth = 300,
	},

	-- 通常攻撃のコンボ。1段ずつ順に出て、ComboResetTime 秒以内に次を押すと繋がる
	Combo = {
		ComboResetTime = 0.8,
		Steps = {
			{ Damage = 12, Range = 7, Width = 8, Cooldown = 0.28, Knockback = 10 },
			{ Damage = 12, Range = 7, Width = 8, Cooldown = 0.28, Knockback = 10 },
			{ Damage = 16, Range = 8, Width = 10, Cooldown = 0.32, Knockback = 14 },
			{ Damage = 28, Range = 10, Width = 14, Cooldown = 0.6, Knockback = 45 },
		},
	},

	-- チャージ攻撃（右クリック / E）。周囲を吹き飛ばす
	ChargeKogeki = {
		Damage = 30,
		Radius = 12,
		Cooldown = 1.2,
		Knockback = 60,
	},

	-- 奥義（Q）と奥義ゲージ。ゲージが満タンで発動する
	Ougi = {
		MaxGauge = 100,
		GainPerHit = 2,
		GainPerDamageTaken = 0.5,
		Pulses = 6,
		PulseInterval = 0.2,
		Radius = 18,
		DamagePerPulse = 40,
		Knockback = 30,
	},

	-- 下忍。色は EnemyService に置く
	Genin = {
		DisplayName = "下忍",
		MaxHealth = 30,
		WalkSpeed = 12,
		Damage = 6,
		AttackRange = 4.5,
		AttackCooldown = 1.5,
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
}

return Config
