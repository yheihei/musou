--!strict
local Config = require("./Config")
local PartySize = require("./PartySize")
local Stats = require("./Stats")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

-- Config.luau の値を調整してもテストが揺れないよう、倍率の表を固定する
local PARAMS: PartySize.Params = {
	JoninHealth = { 1, 1.4, 1.8, 2.2 },
	Heiryoku = { 1, 1.5, 2, 2.5 },
}

test("人数ごとの倍率は表の人数の位置の値", function()
	expect(PartySize.joninHealthOf(1, PARAMS)).toBe(1)
	expect(PartySize.joninHealthOf(2, PARAMS)).toBe(1.4)
	expect(PartySize.joninHealthOf(4, PARAMS)).toBe(2.2)
end)

test("人数は 1 から表の長さまでに収める", function()
	expect(PartySize.joninHealthOf(0, PARAMS)).toBe(1)
	expect(PartySize.joninHealthOf(-3, PARAMS)).toBe(1)
	expect(PartySize.joninHealthOf(9, PARAMS)).toBe(2.2)
	expect(PartySize.multiplier({}, 3)).toBe(1)
end)

test("兵力は1人の兵力に倍率を掛け、端数を四捨五入する", function()
	expect(PartySize.heiryokuOf(10, 1, PARAMS)).toBe(10)
	expect(PartySize.heiryokuOf(10, 2, PARAMS)).toBe(15)
	expect(PartySize.heiryokuOf(10, 4, PARAMS)).toBe(25)
	expect(PartySize.heiryokuOf(7, 2, PARAMS)).toBe(11)
end)

test("敵軍の上忍と首領だけ体力の最大を上げ、味方軍と1人のときは補正しない", function()
	local base: Stats.Values = { MaxHealth = 600, Attack = 14, Defense = 12, WalkSpeed = 14, AttackSpeed = 1 }
	local teki = Stats.compute(base, PartySize.modifiersOf("Tekigun", 4, PARAMS))
	expect(teki.MaxHealth).toBeNear(1320)
	expect(teki.Attack).toBe(14)
	expect(teki.Defense).toBe(12)
	expect(PartySize.modifiersOf("Mikatagun", 4, PARAMS)).toEqual({})
	expect(PartySize.modifiersOf("Tekigun", 1, PARAMS)).toEqual({})
end)

test(
	"Config.luau の表は上限人数の分だけあり、人数が増えるほど倍率が下がらない",
	function()
		for _, list in { Config.PartySize.JoninHealth, Config.PartySize.Heiryoku } do
			expect(#list).toBe(Config.Party.MaxMembers)
			expect(list[1]).toBe(1)
			for index = 2, #list do
				expect(list[index] >= list[index - 1]).toBe(true)
			end
		end
	end
)
