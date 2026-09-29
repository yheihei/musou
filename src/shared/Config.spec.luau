--!strict
local Config = require("./Config")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

-- 節を整理する前の Config.luau の値を書き写したもの。
-- 下忍と上忍の色（Color3）は EnemyService へ移したので含めない。
local SNAPSHOT = {
	Party = {
		MaxMembers = 4,
	},
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
		ComboResetTime = 0.5,
	},
	Bukishu = {
		Shuriken = {
			Attack = {
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
		},
		Katana = {
			Attack = {
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
		},
	},
	ChargeKogeki = {
		Damage = 30,
		Radius = 12,
		Knockback = 60,
	},
	Ougi = {
		PerStock = 100,
		MaxStock = 4,
		InitialStock = 1,
		GainPerHit = 2,
		GainPerDamageTaken = 0.5,
		Pulses = 6,
		PulseInterval = 0.2,
		Radius = 18,
		DamagePerPulse = 40,
		Knockback = 30,
	},
	Action = {
		BufferTime = 0.4,
		ChargeKogeki = { Startup = 0, Active = 0.1, Recovery = 1.1, CancelFrom = 1.2, Advance = 0 },
		Ougi = { Startup = 0, Active = 1.2, Recovery = 0, CancelFrom = 1.2, Advance = 0, Interrupt = true },
		Flinch = { Startup = 0, Active = 0, Recovery = 0.35, CancelFrom = 0.35, Advance = 0 },
		Down = { Startup = 0, Active = 0, Recovery = 0.8, CancelFrom = 0.8, Advance = 0, Next = "GetUp" },
		GetUp = { Startup = 0, Active = 0, Recovery = 0.5, CancelFrom = 0.5, Advance = 0 },
	},
	Damage = {
		FlinchImmunity = 1,
		GetUpInvulnerable = 0.8,
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
		Reaction = "Flinch",
		Scale = 1,
	},
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
