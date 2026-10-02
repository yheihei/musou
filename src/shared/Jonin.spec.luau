--!strict
local Config = require("./Config")
local Haichi = require("./Haichi")
local Jonin = require("./Jonin")
local Stages = require("./Stages")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

local TEST_HAICHI = Haichi.get("Test") :: Haichi.Haichi
local TEST_STAGE = Stages.get("Test") :: Stages.Stage

local function entry(id: string, shuryo: boolean): Jonin.Entry
	return { id = id, gun = "Tekigun", butai = if shuryo then nil else "Teki1", shuryo = shuryo, kyoten = "Chuo" }
end

test("試験用ステージでは、部隊を率いる上忍3人と両軍の首領が本陣に出る", function()
	local entries = Jonin.entriesOf(TEST_HAICHI, TEST_STAGE)
	expect(entries).toEqual({
		{ id = "ShikenJonin3", gun = "Mikatagun", butai = "Mikata1", shuryo = false, kyoten = "Nishi" },
		{ id = "ShikenJonin1", gun = "Tekigun", butai = "Teki1", shuryo = false, kyoten = "Chuo" },
		{ id = "ShikenJonin2", gun = "Tekigun", butai = "Teki2", shuryo = false, kyoten = "Higashi" },
		{ id = "Hayate", gun = "Mikatagun", butai = nil, shuryo = true, kyoten = "MikataHonjin" },
		{ id = "ShikenShuryo", gun = "Tekigun", butai = nil, shuryo = true, kyoten = "TekiHonjin" },
	})
end)

test("首領の決まっていない軍の首領は出さない", function()
	local stage = table.clone(TEST_STAGE)
	stage.shuryo = { mikatagun = "Hayate", tekigun = nil }
	local ids = {}
	for _, item in Jonin.entriesOf(TEST_HAICHI, stage) do
		if item.shuryo then
			table.insert(ids, item.id)
		end
	end
	expect(ids).toEqual({ "Hayate" })
end)

test("能力値は上忍と首領の役目で決まり、体力は最大から始まる", function()
	local jonin = Jonin.new(entry("ShikenJonin1", false), { x = 1, z = 2 })
	expect(jonin.stats.MaxHealth).toBe(Config.Stats.Jonin.MaxHealth)
	expect(jonin.health).toBe(Config.Stats.Jonin.MaxHealth)
	expect(jonin.displayName).toBe("試験の上忍1")
	expect(jonin.position).toEqual({ x = 1, z = 2 })

	local shuryo = Jonin.new(entry("ShikenShuryo", true), { x = 0, z = 0 })
	expect(shuryo.stats.MaxHealth).toBe(Config.Stats.Shuryo.MaxHealth)
	expect(shuryo.butai).toBe(nil)
end)

test("体力は 0 から最大までに収め、0 になったときだけ倒れたと返す", function()
	local jonin = Jonin.new(entry("ShikenJonin1", false), { x = 0, z = 0 })
	expect(Jonin.setHealth(jonin, 99999)).toBe(false)
	expect(jonin.health).toBe(jonin.stats.MaxHealth)
	expect(Jonin.setHealth(jonin, 10)).toBe(false)
	expect(Jonin.isDefeated(jonin)).toBe(false)
	expect(Jonin.setHealth(jonin, -5)).toBe(true)
	expect(jonin.health).toBe(0)
	expect(Jonin.isDefeated(jonin)).toBe(true)
	expect(Jonin.setHealth(jonin, 0)).toBe(false)
end)

test("味方軍の上忍と首領は、体力・攻撃・防御に味方軍の倍率を掛ける", function()
	local scale = Config.Stats.MikatagunScale
	local mikata = Jonin.new(
		{ id = "ShikenJonin3", gun = "Mikatagun", butai = "Mikata1", shuryo = false, kyoten = "Nishi" },
		{ x = 0, z = 0 }
	)
	expect(mikata.stats.MaxHealth).toBeNear(Config.Stats.Jonin.MaxHealth * scale)
	expect(mikata.health).toBe(mikata.stats.MaxHealth)
	expect(mikata.stats.Attack).toBeNear(Config.Stats.Jonin.Attack * scale)
	expect(mikata.stats.Defense).toBeNear(Config.Stats.Jonin.Defense * scale)
	expect(mikata.stats.WalkSpeed).toBe(Config.Stats.Jonin.WalkSpeed)

	local hayate = Jonin.new(
		{ id = "Hayate", gun = "Mikatagun", butai = nil, shuryo = true, kyoten = "MikataHonjin" },
		{ x = 0, z = 0 }
	)
	expect(hayate.stats.MaxHealth).toBeNear(Config.Stats.Shuryo.MaxHealth * scale)
	expect(#Jonin.modifiersOf("Tekigun")).toBe(0)
end)
