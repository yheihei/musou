--!strict
local Characters = require("./Characters")
local Config = require("./Config")
local Stats = require("./Stats")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

local BASE: Stats.Values = { MaxHealth = 300, Attack = 12, Defense = 10, WalkSpeed = 24, AttackSpeed = 1 }

-- 与ダメージの計算の係数を固定する
local PARAMS: Config.StatsSection = {
	Characters = {},
	Jonin = BASE,
	Shuryo = BASE,
	DefenseHalf = 100,
	MinDamage = 1,
}

test("操作キャラクター全員に基本の能力値があり、全項目が正の数", function()
	for id, character in Characters.definitions do
		if character.playable then
			local base = Stats.baseOf(id)
			expect(base ~= nil).toBe(true)
			for _, name in Stats.names do
				local value = (base :: any)[name]
				expect(type(value)).toBe("number")
				expect(value > 0).toBe(true)
			end
		end
	end
end)

test("能力値はキャラクターの定義表にある操作キャラクターにだけ置く", function()
	for id in Config.Stats.Characters do
		local character = Characters.get(id)
		expect(character ~= nil).toBe(true)
		expect((character :: Characters.Character).playable).toBe(true)
	end
end)

test("金鬼は石舟斎より攻撃が遅く、威力が高い", function()
	local kanaOni = Stats.baseOf("KanaOni") :: Stats.Values
	local sekishusai = Stats.baseOf("Sekishusai") :: Stats.Values
	expect(kanaOni.AttackSpeed < sekishusai.AttackSpeed).toBe(true)
	expect(kanaOni.Attack > sekishusai.Attack).toBe(true)
end)

test("能力値の全部に画面に出す名前があり、名前かどうかを見分ける", function()
	for _, name in Stats.names do
		expect(#(Stats.displayNames[name] or "") > 0).toBe(true)
		expect(Stats.isName(name)).toBe(true)
	end
	expect(Stats.isName("Health")).toBe(false)
	expect(Stats.isName(nil)).toBe(false)
	expect(Stats.isName(3)).toBe(false)
end)

test("補正が無ければ基本値のまま", function()
	expect(Stats.compute(BASE, {})).toEqual(BASE)
end)

test("補正は足してから掛け、基本値の表は書き換えない", function()
	local result = Stats.compute(BASE, {
		{ stat = "Attack", add = 3 },
		{ stat = "Attack", multiply = 1.5 },
		{ stat = "Defense", multiply = 2 },
	})
	expect(result.Attack).toBeNear((12 + 3) * 1.5)
	expect(result.Defense).toBe(20)
	expect(result.MaxHealth).toBe(300)
	expect(BASE.Attack).toBe(12)
end)

test("補正の順番を入れ替えても結果は同じ", function()
	local a = Stats.compute(BASE, {
		{ stat = "WalkSpeed", multiply = 1.2 },
		{ stat = "WalkSpeed", add = -4 },
		{ stat = "WalkSpeed", multiply = 0.5 },
	})
	local b = Stats.compute(BASE, {
		{ stat = "WalkSpeed", add = -4 },
		{ stat = "WalkSpeed", multiply = 0.5 },
		{ stat = "WalkSpeed", multiply = 1.2 },
	})
	expect(a.WalkSpeed).toBeNear(b.WalkSpeed)
	expect(a.WalkSpeed).toBeNear((24 - 4) * 1.2 * 0.5)
end)

test("補正で 0 未満にはならない", function()
	local result = Stats.compute(BASE, { { stat = "Defense", add = -100 } })
	expect(result.Defense).toBe(0)
end)

test("防御が 0 なら与ダメージは技の倍率 × 攻撃", function()
	expect(Stats.damage(1, 12, 0, PARAMS)).toBe(12)
	expect(Stats.damage(2.5, 12, 0, PARAMS)).toBe(30)
end)

test("防御が DefenseHalf のとき与ダメージは半分になり、防御が高いほど小さい", function()
	expect(Stats.damage(1, 12, 100, PARAMS)).toBeNear(6)
	expect(Stats.damage(1, 12, 20, PARAMS) > Stats.damage(1, 12, 40, PARAMS)).toBe(true)
end)

test("与ダメージは下限を下回らない", function()
	expect(Stats.damage(0.01, 1, 1000, PARAMS)).toBe(1)
	expect(Stats.damage(0, 12, 0, PARAMS)).toBe(1)
end)

test("攻撃が高いほど与ダメージは大きい", function()
	expect(Stats.damage(1, 16, 10, PARAMS) > Stats.damage(1, 12, 10, PARAMS)).toBe(true)
end)
