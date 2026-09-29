--!strict
local Config = require("./Config")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

-- 節を整理する前の Config.luau の値を書き写したもの。
-- 下忍と上忍の色（Color3）は EnemyService へ移したので含めない。
local SNAPSHOT = {
	Stats = {
		Characters = {
			Jin = { MaxHealth = 300, Attack = 12, Defense = 10, WalkSpeed = 24, AttackSpeed = 1 },
			Torika = { MaxHealth = 270, Attack = 11, Defense = 8, WalkSpeed = 26, AttackSpeed = 1.1 },
			Sekishusai = { MaxHealth = 320, Attack = 13, Defense = 12, WalkSpeed = 23, AttackSpeed = 1 },
			KanaOni = { MaxHealth = 360, Attack = 16, Defense = 14, WalkSpeed = 22, AttackSpeed = 0.8 },
		},
		DefenseHalf = 100,
		MinDamage = 1,
	},
	Combo = {
		ComboResetTime = 0.8,
		Steps = {
			{ Damage = 12, Range = 7, Width = 8, Cooldown = 0.28, Knockback = 10 },
			{ Damage = 12, Range = 7, Width = 8, Cooldown = 0.28, Knockback = 10 },
			{ Damage = 16, Range = 8, Width = 10, Cooldown = 0.32, Knockback = 14 },
			{ Damage = 28, Range = 10, Width = 14, Cooldown = 0.6, Knockback = 45 },
		},
	},
	ChargeKogeki = {
		Damage = 30,
		Radius = 12,
		Cooldown = 1.2,
		Knockback = 60,
	},
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
	Hitbox = {
		Height = 8,
		ShowShapes = false,
		ShapeLifetime = 0.3,
	},
	Genin = {
		DisplayName = "下忍",
		MaxHealth = 30,
		WalkSpeed = 12,
		Damage = 6,
		AttackRange = 4.5,
		AttackCooldown = 1.5,
		Scale = 1,
	},
	Jonin = {
		DisplayName = "上忍",
		MaxHealth = 600,
		WalkSpeed = 14,
		Damage = 20,
		AttackRange = 6,
		AttackCooldown = 1.8,
		Scale = 1.4,
	},
	Spawner = {
		MaxAlive = 40,
		ButaiSize = 8,
		ButaiInterval = 3,
		JoninEvery = 5,
		MinDistance = 60,
		MaxDistance = 140,
		AggroRange = 80,
		AITickInterval = 0.25,
		CorpseLifetime = 2,
	},
	Kosen = {
		Zensenhaba = 10,
		ReserveWeight = 0.3,
		ShikiEffect = 0.01,
		ShikiHoseiMin = 0.3,
		ShikiHoseiMax = 2,
		LossRate = 0.02,
		MaxStep = 0.5,
		GunStrength = {
			Mikatagun = 0.9,
			Tekigun = 1,
		},
	},
	Hikei = {
		Duration = {
			Fukuhei = 120,
			Rakuseki = 90,
			Chohatsu = 15,
			Kishinka = 60,
			Daikatsu = 30,
		},
	},
}

local ALLOWED_TYPES = { number = true, string = true, boolean = true, table = true }

local function collectDisallowed(value: any, path: string, found: { string })
	if not ALLOWED_TYPES[type(value)] then
		table.insert(found, `{path} ({typeof(value)})`)
		return
	end
	if type(value) == "table" then
		for key, child in value do
			collectDisallowed(child, `{path}.{key}`, found)
		end
	end
end

test("整理の前後で全ての値が一致する", function()
	expect(Config).toEqual(SNAPSHOT)
end)

test("値は数値・文字列・真偽値と表だけで、Roblox の型を含まない", function()
	local found = {}
	collectDisallowed(Config, "Config", found)
	expect(found).toEqual({})
end)
