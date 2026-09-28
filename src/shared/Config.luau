--!strict
-- ゲームバランス調整用の定数。数値チューニングはこのファイルだけで完結させる。

local Config = {}

Config.Player = {
	WalkSpeed = 24,
	MaxHealth = 300,
}

-- 通常攻撃コンボ。1段ずつ順に出て、ComboResetTime 以内に次を押すと繋がる
Config.Combo = {
	ComboResetTime = 0.8,
	Steps = {
		{ Damage = 12, Range = 7, Width = 8, Cooldown = 0.28, Knockback = 10 },
		{ Damage = 12, Range = 7, Width = 8, Cooldown = 0.28, Knockback = 10 },
		{ Damage = 16, Range = 8, Width = 10, Cooldown = 0.32, Knockback = 14 },
		{ Damage = 28, Range = 10, Width = 14, Cooldown = 0.6, Knockback = 45 },
	},
}

-- チャージ攻撃（右クリック / E）。周囲を吹き飛ばす
Config.ChargeKogeki = {
	Damage = 30,
	Radius = 12,
	Cooldown = 1.2,
	Knockback = 60,
}

-- 奥義（Q）。奥義ゲージが満タンで発動
Config.Ougi = {
	MaxGauge = 100,
	GainPerHit = 2,
	GainPerDamageTaken = 0.5,
	Pulses = 6,
	PulseInterval = 0.2,
	Radius = 18,
	DamagePerPulse = 40,
	Knockback = 30,
}

Config.Enemies = {
	Genin = {
		DisplayName = "下忍",
		MaxHealth = 30,
		WalkSpeed = 12,
		Damage = 6,
		AttackRange = 4.5,
		AttackCooldown = 1.5,
		Scale = 1,
		Color = Color3.fromRGB(70, 90, 160),
	},
	Jonin = {
		DisplayName = "上忍",
		MaxHealth = 600,
		WalkSpeed = 14,
		Damage = 20,
		AttackRange = 6,
		AttackCooldown = 1.8,
		Scale = 1.4,
		Color = Color3.fromRGB(170, 40, 40),
	},
}

Config.Spawner = {
	MaxAlive = 40,
	ButaiSize = 8,
	ButaiInterval = 3,
	JoninEvery = 5, -- 何部隊ごとに上忍を出すか
	MinDistance = 60,
	MaxDistance = 140,
	AggroRange = 80,
	AITickInterval = 0.25,
	CorpseLifetime = 2,
}

return Config
