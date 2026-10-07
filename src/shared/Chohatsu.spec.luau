--!strict
local Chohatsu = require("./Chohatsu")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

-- Config.luau の値を調整してもテストが揺れないよう、範囲を固定する
local PARAMS: Chohatsu.Params = {
	Radius = 100,
}

local function candidate(
	id: string,
	gun: "Mikatagun" | "Tekigun",
	x: number,
	z: number,
	options: { shuryo: boolean?, defeated: boolean?, lured: boolean? }?
): Chohatsu.Candidate
	local o = options or {}
	return {
		id = id,
		gun = gun,
		shuryo = o.shuryo == true,
		defeated = o.defeated == true,
		lured = o.lured == true,
		x = x,
		z = z,
	}
end

test("範囲の中の相手の上忍を、候補の順に選ぶ", function()
	local candidates = {
		candidate("ShikenJonin2", "Tekigun", 60, 0),
		candidate("ShikenJonin3", "Mikatagun", 5, 5),
		candidate("ShikenJonin1", "Tekigun", 0, 99),
	}
	local targets, failure = Chohatsu.targetsOf(0, 0, "Mikatagun", candidates, PARAMS)
	expect(targets).toEqual({ "ShikenJonin2", "ShikenJonin1" })
	expect(failure).toBe(nil)
end)

test("範囲の縁ちょうどは対象に入れ、外は選ばない", function()
	local candidates = {
		candidate("ShikenJonin1", "Tekigun", 60, 80),
		candidate("ShikenJonin2", "Tekigun", 0, -100.5),
	}
	local targets = Chohatsu.targetsOf(0, 0, "Mikatagun", candidates, PARAMS)
	expect(targets).toEqual({ "ShikenJonin1" })
end)

test("首領と倒れた上忍は対象にしない", function()
	local candidates = {
		candidate("ShikenShuryo", "Tekigun", 10, 0, { shuryo = true }),
		candidate("ShikenJonin1", "Tekigun", 20, 0, { defeated = true }),
		candidate("ShikenJonin2", "Tekigun", 30, 0),
	}
	local targets = Chohatsu.targetsOf(0, 0, "Mikatagun", candidates, PARAMS)
	expect(targets).toEqual({ "ShikenJonin2" })
end)

test("範囲の中に相手の上忍がいなければ NoTarget", function()
	local candidates = {
		candidate("ShikenShuryo", "Tekigun", 10, 0, { shuryo = true }),
		candidate("ShikenJonin1", "Tekigun", 20, 0, { defeated = true }),
		candidate("ShikenJonin2", "Tekigun", 150, 0),
		candidate("ShikenJonin3", "Mikatagun", 0, 0),
	}
	local targets, failure = Chohatsu.targetsOf(0, 0, "Mikatagun", candidates, PARAMS)
	expect(targets).toEqual({})
	expect(failure).toBe("NoTarget")
	local _, empty = Chohatsu.targetsOf(0, 0, "Mikatagun", {}, PARAMS)
	expect(empty).toBe("NoTarget")
end)

test("もう誘い出されている上忍には重ねず、ほかの上忍だけを選ぶ", function()
	local candidates = {
		candidate("ShikenJonin1", "Tekigun", 10, 0, { lured = true }),
		candidate("ShikenJonin2", "Tekigun", 20, 0),
	}
	local targets, failure = Chohatsu.targetsOf(0, 0, "Mikatagun", candidates, PARAMS)
	expect(targets).toEqual({ "ShikenJonin2" })
	expect(failure).toBe(nil)
end)

test("範囲の中の上忍がすべてもう誘い出されていれば AlreadyActive", function()
	local candidates = {
		candidate("ShikenJonin1", "Tekigun", 10, 0, { lured = true }),
		candidate("ShikenJonin2", "Tekigun", 200, 0),
	}
	local targets, failure = Chohatsu.targetsOf(0, 0, "Mikatagun", candidates, PARAMS)
	expect(targets).toEqual({})
	expect(failure).toBe("AlreadyActive")
end)

test("敵軍が発動したときは、範囲の中の味方軍の上忍を誘い出す", function()
	local candidates = {
		candidate("ShikenJonin3", "Mikatagun", -3080, 0),
		candidate("Hayate", "Mikatagun", -3000, 80, { shuryo = true }),
		candidate("ShikenJonin2", "Tekigun", -3010, 0),
	}
	local targets, failure = Chohatsu.targetsOf(-3000, 0, "Tekigun", candidates, PARAMS)
	expect(targets).toEqual({ "ShikenJonin3" })
	expect(failure).toBe(nil)
end)
