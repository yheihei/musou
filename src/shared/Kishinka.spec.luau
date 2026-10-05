--!strict
local Config = require("./Config")
local Kishinka = require("./Kishinka")
local Stats = require("./Stats")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

test(
	"鬼神化の補正は攻撃と防御に Config.luau の倍率を掛け、体力と移動速度は変えない",
	function()
		local base = Stats.baseOf("Jin") :: Stats.Values
		local stats = Stats.compute(base, Kishinka.modifiers())
		expect(stats.Attack).toBeNear(base.Attack * Config.Kishinka.Attack)
		expect(stats.Defense).toBeNear(base.Defense * Config.Kishinka.Defense)
		expect(stats.MaxHealth).toBe(base.MaxHealth)
		expect(stats.WalkSpeed).toBe(base.WalkSpeed)
	end
)

test("鬼神化の効果中は与ダメージが増え、被ダメージが減る", function()
	local base = Stats.baseOf("Jin") :: Stats.Values
	local stats = Stats.compute(base, Kishinka.modifiers())
	expect(Stats.damage(1, stats.Attack, 0) > Stats.damage(1, base.Attack, 0)).toBe(true)
	expect(Stats.damage(1, 20, stats.Defense) < Stats.damage(1, 20, base.Defense)).toBe(true)
end)

test("倍率は引数の値を使える", function()
	local modifiers = Kishinka.modifiers({ Attack = 2, Defense = 3 })
	expect(modifiers).toEqual({
		{ stat = "Attack", multiply = 2 },
		{ stat = "Defense", multiply = 3 },
	})
end)
