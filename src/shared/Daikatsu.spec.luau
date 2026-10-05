--!strict
local Config = require("./Config")
local Daikatsu = require("./Daikatsu")
local Stats = require("./Stats")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

-- Config.luau の値を調整してもテストが揺れないよう、範囲と倍率を固定する
local PARAMS: Daikatsu.Params = {
	Radius = 40,
	Attack = 0.5,
	Defense = 0.8,
	Shiki = 20,
}

local function candidate(
	kind: Daikatsu.Kind,
	id: string,
	gun: "Mikatagun" | "Tekigun",
	x: number,
	z: number,
	hidden: boolean?
): Daikatsu.Candidate
	return { kind = kind, id = id, gun = gun, x = x, z = z, hidden = hidden }
end

local function idsOf(list: { Daikatsu.Candidate }): { string }
	local ids = {}
	for _, item in list do
		table.insert(ids, item.id)
	end
	return ids
end

test("範囲の中の相手の上忍・プレイヤー・部隊だけを、候補の順に選ぶ", function()
	local candidates = {
		candidate("Jonin", "ShikenJonin1", "Tekigun", 10, 0),
		candidate("Butai", "Teki1", "Tekigun", 0, 39),
		candidate("Butai", "Teki2", "Tekigun", 41, 0),
		candidate("Jonin", "ShikenJonin3", "Mikatagun", 5, 5),
		candidate("Player", "1001", "Mikatagun", 0, 0),
		candidate("Butai", "Mikata1", "Mikatagun", 1, 1),
	}
	expect(idsOf(Daikatsu.targetsOf(0, 0, "Mikatagun", candidates, PARAMS))).toEqual({ "ShikenJonin1", "Teki1" })
end)

test("範囲の縁ちょうどは対象に入れる", function()
	local candidates = { candidate("Jonin", "ShikenJonin1", "Tekigun", 0, 40) }
	expect(#Daikatsu.targetsOf(0, 0, "Mikatagun", candidates, PARAMS)).toBe(1)
end)

test("潜んでいる伏兵部隊は対象にしない", function()
	local candidates = {
		candidate("Butai", "Fukuhei1", "Tekigun", 0, 10, true),
		candidate("Butai", "Teki1", "Tekigun", 0, 10, false),
	}
	expect(idsOf(Daikatsu.targetsOf(0, 0, "Mikatagun", candidates, PARAMS))).toEqual({ "Teki1" })
end)

test("敵軍が発動したときは、範囲の中のプレイヤーと味方軍が対象になる", function()
	local candidates = {
		candidate("Player", "1001", "Mikatagun", 3, 4),
		candidate("Player", "1002", "Mikatagun", 100, 0),
		candidate("Jonin", "ShikenJonin1", "Tekigun", 0, 0),
		candidate("Butai", "Mikata1", "Mikatagun", -20, 0),
	}
	expect(idsOf(Daikatsu.targetsOf(0, 0, "Tekigun", candidates, PARAMS))).toEqual({ "1001", "Mikata1" })
end)

test("動揺の補正は攻撃と防御を下げ、体力は変えない", function()
	local base = Stats.baseOf("Jin") :: Stats.Values
	local stats = Stats.compute(base, Daikatsu.doyoModifiers(PARAMS))
	expect(stats.Attack).toBeNear(base.Attack * 0.5)
	expect(stats.Defense).toBeNear(base.Defense * 0.8)
	expect(stats.MaxHealth).toBe(base.MaxHealth)
	expect(Daikatsu.doyoShiki(PARAMS)).toBe(20)
	expect(Daikatsu.doyoShiki()).toBe(Config.Daikatsu.Shiki)
end)
