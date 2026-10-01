--!strict
local Haichi = require("./Haichi")
local Stages = require("./Stages")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

local TEST_STAGE = Stages.get("Test") :: Stages.Stage

-- 試験用ステージの配置を写し、changes で一部を書き換えたもの
local function testHaichi(changes: ((Haichi.Haichi) -> ())?): Haichi.Haichi
	local source = Haichi.get("Test") :: Haichi.Haichi
	local copy: Haichi.Haichi = {
		stageId = source.stageId,
		kyoten = table.clone(source.kyoten),
		tsunagari = table.clone(source.tsunagari),
		butai = {},
		shikenMejirushi = nil,
	}
	for _, butai in source.butai do
		table.insert(copy.butai, table.clone(butai))
	end
	if changes then
		changes(copy)
	end
	return copy
end

local function contains(problems: { string }, fragment: string): boolean
	for _, problem in problems do
		if string.find(problem, fragment, 1, true) then
			return true
		end
	end
	return false
end

test("定義表の配置はステージの定義表にあり、検証の問題が無い", function()
	for stageId, haichi in Haichi.definitions do
		expect(haichi.stageId).toBe(stageId)
		local stage = Stages.get(stageId)
		expect(stage ~= nil).toBe(true)
		expect(Haichi.validate(haichi, stage :: Stages.Stage)).toEqual({})
	end
end)

test("試験用ステージは拠点5つで、両軍に本陣が1つずつある", function()
	local haichi = Haichi.get("Test") :: Haichi.Haichi
	expect(#haichi.kyoten).toBe(5)
	expect(Haichi.honjinOf(haichi, "Mikatagun")).toBe("MikataHonjin")
	expect(Haichi.honjinOf(haichi, "Tekigun")).toBe("TekiHonjin")
	expect(TEST_STAGE.shiken).toBe(true)
end)

test("試験用ステージの目印の位置は、すべて試験用区画の範囲に収まる", function()
	local haichi = Haichi.get("Test") :: Haichi.Haichi
	local mejirushi = haichi.shikenMejirushi :: Haichi.ShikenMejirushi
	local halfX, halfZ = mejirushi.kukakuSizeX / 2, mejirushi.kukakuSizeZ / 2
	for _, ichi in mejirushi.kyoten do
		expect(math.abs(ichi.x) + ichi.sizeX / 2 <= halfX).toBe(true)
		expect(math.abs(ichi.z) + ichi.sizeZ / 2 <= halfZ).toBe(true)
	end
	for _, tsunagari in mejirushi.tsunagari do
		for _, point in tsunagari.keiyuten do
			expect(math.abs(point.x) <= halfX and math.abs(point.z) <= halfZ).toBe(true)
		end
	end
end)

test("区画からはみ出す目印の位置を見つける", function()
	local haichi = testHaichi(function(copy)
		local source = (Haichi.get("Test") :: Haichi.Haichi).shikenMejirushi :: Haichi.ShikenMejirushi
		local kyoten = table.clone(source.kyoten)
		kyoten.Higashi = { x = 380, z = 0, sizeX = 80, sizeZ = 80 }
		copy.shikenMejirushi = {
			kukakuSizeX = source.kukakuSizeX,
			kukakuSizeZ = source.kukakuSizeZ,
			kyoten = kyoten,
			tsunagari = source.tsunagari,
		}
	end)
	expect(
		contains(Haichi.validate(haichi, TEST_STAGE), "拠点 Higashi の目印が区画の範囲からはみ出す")
	).toBe(true)
end)

test("存在しない拠点を指すつながりと部隊を見つける", function()
	local haichi = testHaichi(function(copy)
		table.insert(copy.tsunagari, { kyotenA = "Chuo", kyotenB = "Nowhere" })
		copy.butai[1].kyoten = "Nowhere"
	end)
	local problems = Haichi.validate(haichi, TEST_STAGE)
	expect(contains(problems, "つながり Chuo-Nowhere の拠点 Nowhere が無い")).toBe(true)
	expect(contains(problems, "部隊 Mikata1 の拠点 Nowhere が無い")).toBe(true)
end)

test("重複した拠点 ID・つながり・部隊 ID を見つける", function()
	local haichi = testHaichi(function(copy)
		table.insert(copy.kyoten, { id = "Chuo", honjin = false, gun = "Tekigun" })
		table.insert(copy.tsunagari, { kyotenA = "Nishi", kyotenB = "MikataHonjin" })
		table.insert(copy.butai, table.clone(copy.butai[2]))
	end)
	local problems = Haichi.validate(haichi, TEST_STAGE)
	expect(contains(problems, "拠点 Chuo が2つある")).toBe(true)
	expect(contains(problems, "つながり MikataHonjin-Nishi が2つある")).toBe(true)
	expect(contains(problems, "部隊 Mikata2 が2つある")).toBe(true)
end)

test("本陣が1つでない軍と、開始時に孤立した拠点を見つける", function()
	local haichi = testHaichi(function(copy)
		copy.kyoten[1] = { id = "MikataHonjin", honjin = false, gun = "Mikatagun" }
	end)
	local problems = Haichi.validate(haichi, TEST_STAGE)
	expect(contains(problems, "Mikatagun の本陣が 0 個ある")).toBe(true)
	expect(contains(problems, "開始時に Mikatagun の拠点 Nishi が孤立している")).toBe(true)
end)

test("相手の軍の拠点から始まる部隊を見つける", function()
	local haichi = testHaichi(function(copy)
		copy.butai[1].kyoten = "Chuo"
	end)
	expect(
		contains(
			Haichi.validate(haichi, TEST_STAGE),
			"部隊 Mikata1（Mikatagun）が Tekigun の拠点 Chuo から始まる"
		)
	).toBe(true)
end)

test(
	"上忍の誤り（NPC に無い、操作キャラクター、首領、2つの部隊を率いる、クラン違い）を見つける",
	function()
		local haichi = testHaichi(function(copy)
			copy.butai[1].jonin = "Jin"
			copy.butai[3].jonin = "ShikenShuryo"
			copy.butai[4].jonin = "ShikenJonin3"
			copy.butai[5].jonin = "ShikenJonin3"
		end)
		local problems = Haichi.validate(haichi, TEST_STAGE)
		expect(contains(problems, "部隊 Mikata1 の上忍 Jin は操作キャラクター")).toBe(true)
		expect(contains(problems, "部隊 Mikata1 の上忍 Jin がステージの NPC に無い")).toBe(true)
		expect(contains(problems, "部隊 Teki1 の上忍 ShikenShuryo は首領")).toBe(true)
		expect(contains(problems, "上忍 ShikenJonin3 が部隊 Teki2 と Teki3 を率いている")).toBe(true)
		expect(contains(problems, "部隊 Teki2 の上忍 ShikenJonin3 のクランが Tekigun のクランと違う")).toBe(
			true
		)
	end
)

test("兵数が Config.Butai.Heisu に無い部隊を見つける", function()
	local haichi = testHaichi(function(copy)
		copy.butai[1].id = "Mikata9"
	end)
	expect(
		contains(Haichi.validate(haichi, TEST_STAGE), "部隊 Mikata9 の兵数が Config.Butai.Heisu.Test に無い")
	).toBe(true)
	expect(Haichi.heisuOf("Test", "Mikata1")).toBe(30)
	expect(Haichi.heisuOf("Nowhere", "Mikata1")).toBe(nil)
end)

test("つながりは向きに関係なく同じキーになる", function()
	expect(Haichi.pairKey("Nishi", "Chuo")).toBe(Haichi.pairKey("Chuo", "Nishi"))
	expect(Haichi.pairKey("Chuo", "Nishi")).toBe("Chuo-Nishi")
end)

test("構成と目印がそろっていれば食い違いは無い", function()
	local haichi = Haichi.get("Test") :: Haichi.Haichi
	local names = {}
	for _, kyoten in haichi.kyoten do
		table.insert(names, kyoten.id)
	end
	local tsunagariPairs = {}
	for _, tsunagari in haichi.tsunagari do
		-- 目印のフォルダの向きは逆でもよい
		table.insert(tsunagariPairs, { kyotenA = tsunagari.kyotenB, kyotenB = tsunagari.kyotenA })
	end
	expect(Haichi.compareMejirushi(haichi, names, tsunagariPairs)).toEqual({})
end)

test("構成にあって目印が無いもの、目印にあって構成に無いものを返す", function()
	local haichi = Haichi.get("Test") :: Haichi.Haichi
	local names = { "MikataHonjin", "Nishi", "Chuo", "Higashi", "Extra" }
	local tsunagariPairs = {
		{ kyotenA = "MikataHonjin", kyotenB = "Nishi" },
		{ kyotenA = "MikataHonjin", kyotenB = "Chuo" },
		{ kyotenA = "Nishi", kyotenB = "Chuo" },
		{ kyotenA = "Chuo", kyotenB = "Higashi" },
		{ kyotenA = "Chuo", kyotenB = "TekiHonjin" },
		{ kyotenA = "Higashi", kyotenB = "TekiHonjin" },
	}
	expect(Haichi.compareMejirushi(haichi, names, tsunagariPairs)).toEqual({
		"拠点 TekiHonjin の目印が無い",
		"目印の拠点 Extra は構成に無い",
		"つながり Nishi-TekiHonjin の目印が無い（拠点の間をまっすぐ結ぶ）",
		"目印のつながり Higashi-TekiHonjin は構成に無い",
	})
end)
