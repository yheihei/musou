--!strict
local Config = require("./Config")
local Haichi = require("./Haichi")
local Jonin = require("./Jonin")
local Kishinka = require("./Kishinka")
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

test(
	"支配エリアの中では攻撃と防御が上がり、外へ出ると戻る。体力はそのまま",
	function()
		local area = Config.ShihaiArea
		local jonin = Jonin.new(entry("ShikenJonin1", false), { x = 0, z = 0 })
		Jonin.setHealth(jonin, 300)
		expect(jonin.shihaiArea).toBe(false)
		expect(Jonin.setShihaiArea(jonin, true)).toBe(true)
		expect(jonin.stats.Attack).toBeNear(Config.Stats.Jonin.Attack * area.Attack)
		expect(jonin.stats.Defense).toBeNear(Config.Stats.Jonin.Defense * area.Defense)
		expect(jonin.stats.MaxHealth).toBe(Config.Stats.Jonin.MaxHealth)
		expect(jonin.health).toBe(300)
		expect(Jonin.setShihaiArea(jonin, true)).toBe(false)
		expect(Jonin.setShihaiArea(jonin, false)).toBe(true)
		expect(jonin.stats.Attack).toBe(Config.Stats.Jonin.Attack)
		expect(jonin.stats.Defense).toBe(Config.Stats.Jonin.Defense)
	end
)

test("味方軍の上忍は、味方軍の倍率に支配エリアの倍率を重ねる", function()
	local mikata = Jonin.new(
		{ id = "ShikenJonin3", gun = "Mikatagun", butai = "Mikata1", shuryo = false, kyoten = "Nishi" },
		{ x = 0, z = 0 }
	)
	Jonin.setShihaiArea(mikata, true)
	local scale = Config.Stats.MikatagunScale
	expect(mikata.stats.Attack).toBeNear(Config.Stats.Jonin.Attack * scale * Config.ShihaiArea.Attack)
	expect(mikata.stats.MaxHealth).toBeNear(Config.Stats.Jonin.MaxHealth * scale)
end)

test(
	"敵軍の上忍と首領は、出撃したときの人数で体力の最大が上がり、体力は最大から始まる",
	function()
		local scale = Config.PartySize.JoninHealth[4]
		local jonin = Jonin.new(entry("ShikenJonin1", false), { x = 0, z = 0 }, 4)
		expect(jonin.stats.MaxHealth).toBeNear(Config.Stats.Jonin.MaxHealth * scale)
		expect(jonin.health).toBe(jonin.stats.MaxHealth)
		expect(jonin.stats.Attack).toBe(Config.Stats.Jonin.Attack)
		local shuryo = Jonin.new(entry("ShikenShuryo", true), { x = 0, z = 0 }, 4)
		expect(shuryo.stats.MaxHealth).toBeNear(Config.Stats.Shuryo.MaxHealth * scale)
		-- 支配エリアで能力値を求め直しても、人数による体力は残る
		Jonin.setShihaiArea(jonin, true)
		expect(jonin.stats.MaxHealth).toBeNear(Config.Stats.Jonin.MaxHealth * scale)
	end
)

test("味方軍の上忍と首領は人数で体力が変わらない", function()
	local mikata = Jonin.new(
		{ id = "Hayate", gun = "Mikatagun", butai = nil, shuryo = true, kyoten = "MikataHonjin" },
		{ x = 0, z = 0 },
		4
	)
	expect(mikata.stats.MaxHealth).toBeNear(Config.Stats.Shuryo.MaxHealth * Config.Stats.MikatagunScale)
end)

test(
	"秘計の効果の補正は足すと能力値に掛かり、外すと戻る。支配エリアの補正とも重なる",
	function()
		local jonin = Jonin.new(entry("ShikenJonin1", false), { x = 0, z = 0 })
		Jonin.setHealth(jonin, 300)
		Jonin.setHikeiHosei(jonin, "Kishinka", Kishinka.modifiers())
		expect(jonin.stats.Attack).toBeNear(Config.Stats.Jonin.Attack * Config.Kishinka.Attack)
		expect(jonin.stats.Defense).toBeNear(Config.Stats.Jonin.Defense * Config.Kishinka.Defense)
		expect(jonin.stats.MaxHealth).toBe(Config.Stats.Jonin.MaxHealth)
		expect(jonin.health).toBe(300)

		Jonin.setShihaiArea(jonin, true)
		expect(jonin.stats.Attack).toBeNear(
			Config.Stats.Jonin.Attack * Config.ShihaiArea.Attack * Config.Kishinka.Attack
		)
		Jonin.setShihaiArea(jonin, false)
		expect(jonin.stats.Attack).toBeNear(Config.Stats.Jonin.Attack * Config.Kishinka.Attack)

		Jonin.setHikeiHosei(jonin, "Kishinka", nil)
		expect(jonin.stats.Attack).toBe(Config.Stats.Jonin.Attack)
		expect(jonin.stats.Defense).toBe(Config.Stats.Jonin.Defense)
		expect(jonin.hikeiHosei.Kishinka).toBe(nil)
	end
)
