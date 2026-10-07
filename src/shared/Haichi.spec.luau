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
		mochikomi = Haichi.mochikomiOf(source.stageId),
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

test("向きの度を水平の向きにする（北は z の -、東は x の +）", function()
	local function rounded(degrees: number): { number }
		local x, z = Haichi.facingOf(degrees)
		return { math.round(x * 1000) / 1000, math.round(z * 1000) / 1000 }
	end
	expect(rounded(0)).toEqual({ 0, -1 })
	expect(rounded(90)).toEqual({ 1, 0 })
	expect(rounded(180)).toEqual({ 0, 1 })
	expect(rounded(270)).toEqual({ -1, 0 })
end)

test("区画からはみ出すイベントシーンの目印を見つける", function()
	local haichi = testHaichi(function(copy)
		local source = (Haichi.get("Test") :: Haichi.Haichi).shikenMejirushi :: Haichi.ShikenMejirushi
		local shikenMejirushi = table.clone(source)
		shikenMejirushi.eventScene = {
			Shiken = {
				camera = { Zenkei = { x = 0, y = 10, z = 450, lookX = 0, lookY = 0, lookZ = 0 } },
				yakusha = { Hayate = { x = -500, z = 0, facing = 0 } },
			},
		}
		copy.shikenMejirushi = shikenMejirushi
	end)
	local problems = Haichi.validate(haichi, TEST_STAGE)
	expect(contains(problems, "イベントシーン Shiken のカメラ Zenkei が区画の範囲からはみ出す")).toBe(
		true
	)
	expect(contains(problems, "イベントシーン Shiken の役者 Hayate が区画の範囲からはみ出す")).toBe(
		true
	)
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
			rakusekiChiten = source.rakusekiChiten,
			daikakeiChiiki = source.daikakeiChiiki,
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

test("落石地点の目印は、つながりで結ばれた区間を指すものだけ使える", function()
	local haichi = Haichi.get("Test") :: Haichi.Haichi
	local usable, problems = Haichi.checkRakusekiChiten(haichi, {
		{ id = "R1", kyotenA = "Chuo", kyotenB = "Higashi" },
		-- 目印の向きは逆でもよい
		{ id = "R2", kyotenA = "Nishi", kyotenB = "MikataHonjin" },
	})
	expect(usable).toEqual({ R1 = true, R2 = true })
	expect(problems).toEqual({})
end)

test(
	"落石地点の ID の重複、存在しない拠点、結ばれていない区間、Attribute の欠けを見つける",
	function()
		local haichi = Haichi.get("Test") :: Haichi.Haichi
		local usable, problems = Haichi.checkRakusekiChiten(haichi, {
			{ id = "R1", kyotenA = "Chuo", kyotenB = "Higashi" },
			{ id = "R1", kyotenA = "Chuo", kyotenB = "TekiHonjin" },
			{ id = "R2", kyotenA = "Chuo", kyotenB = "Nowhere" },
			{ id = "R3", kyotenA = "Higashi", kyotenB = "TekiHonjin" },
			{ id = "R4", kyotenA = "Chuo", kyotenB = nil },
		})
		expect(usable).toEqual({ R1 = true })
		expect(problems).toEqual({
			"落石地点 R1 が2つある",
			"落石地点 R2 の拠点 Nowhere が無い",
			"落石地点 R3 の区間 Higashi-TekiHonjin はつながりで結ばれていない",
			"落石地点 R4 に Attribute の KyotenA・KyotenB が無い",
		})
	end
)

test("大火計地域の ID の重複を見つけ、2つ目は使わない", function()
	local usable, problems = Haichi.checkDaikakeiChiiki({ "D1", "D2", "D1" })
	expect(usable).toEqual({ D1 = true, D2 = true })
	expect(problems).toEqual({ "大火計地域 D1 が2つある" })
end)

test(
	"試験用ステージの落石地点と大火計地域の位置を見つけ、区画からはみ出すものを見つける",
	function()
		local mejirushi = (Haichi.get("Test") :: Haichi.Haichi).shikenMejirushi :: Haichi.ShikenMejirushi
		expect(#mejirushi.rakusekiChiten > 0).toBe(true)
		expect(#mejirushi.daikakeiChiiki > 0).toBe(true)
		local haichi = testHaichi(function(copy)
			local source = (Haichi.get("Test") :: Haichi.Haichi).shikenMejirushi :: Haichi.ShikenMejirushi
			copy.shikenMejirushi = {
				kukakuSizeX = source.kukakuSizeX,
				kukakuSizeZ = source.kukakuSizeZ,
				kyoten = source.kyoten,
				tsunagari = source.tsunagari,
				rakusekiChiten = { { id = "R9", kyotenA = "Chuo", kyotenB = "Higashi", x = 500, z = 0 } },
				daikakeiChiiki = { { id = "D9", x = 380, z = 0, sizeX = 60, sizeZ = 60 } },
			}
		end)
		local problems = Haichi.validate(haichi, TEST_STAGE)
		expect(contains(problems, "落石地点 R9 が区画の範囲からはみ出す")).toBe(true)
		expect(contains(problems, "大火計地域 D9 が区画の範囲からはみ出す")).toBe(true)
	end
)

test("試験用ステージの敵軍の上忍と首領は、鬼神化・大喝・挑発を持ち込む", function()
	expect(Haichi.mochikomiOf("Test")).toEqual({
		ShikenJonin1 = { "Kishinka", "Chohatsu" },
		ShikenJonin2 = { "Daikatsu" },
		ShikenShuryo = { "Kishinka", "Daikatsu" },
	})
end)

test(
	"持ち込みは写しで返し、配置の構成の無いステージは空。持ち込みが無くても検証は通る",
	function()
		local first = Haichi.mochikomiOf("Test")
		table.insert(first.ShikenJonin2, "Kishinka")
		first.ShikenJonin3 = { "Kishinka" }
		expect(Haichi.mochikomiOf("Test").ShikenJonin2).toEqual({ "Daikatsu" })
		expect(Haichi.mochikomiOf("Test").ShikenJonin3).toBe(nil)
		expect(Haichi.mochikomiOf("Nowhere")).toEqual({})
		local haichi = testHaichi(function(copy)
			copy.mochikomi = nil
		end)
		expect(Haichi.validate(haichi, TEST_STAGE)).toEqual({})
	end
)

test(
	"秘計を持ち込む味方軍の上忍と首領、配置にいないキャラクターを見つける",
	function()
		local haichi = testHaichi(function(copy)
			local mochikomi = copy.mochikomi :: { [string]: { string } }
			mochikomi.ShikenJonin3 = { "Kishinka" }
			mochikomi.Hayate = { "Daikatsu" }
			mochikomi.Jin = { "Chohatsu" }
		end)
		expect(Haichi.validate(haichi, TEST_STAGE)).toEqual({
			"秘計を持ち込む Hayate は敵軍の上忍でも首領でもない",
			"秘計を持ち込む Jin は敵軍の上忍でも首領でもない",
			"秘計を持ち込む ShikenJonin3 は敵軍の上忍でも首領でもない",
		})
	end
)

test("上限を超える持ち込み、重なり、定義に無い秘計を見つける", function()
	local haichi = testHaichi(function(copy)
		local mochikomi = copy.mochikomi :: { [string]: { string } }
		mochikomi.ShikenJonin1 = { "Kishinka", "Chohatsu", "Daikatsu", "Fukuhei" }
		mochikomi.ShikenJonin2 = { "Daikatsu", "Daikatsu" }
		mochikomi.ShikenShuryo = { "Kishinka", "Nowhere" }
	end)
	expect(Haichi.validate(haichi, TEST_STAGE)).toEqual({
		"ShikenJonin1 の秘計の持ち込みを受け付けない（HikeiLimit）",
		"ShikenJonin2 の秘計の持ち込みを受け付けない（HikeiDuplicate）",
		"ShikenShuryo の秘計の持ち込みを受け付けない（UnknownHikei）",
	})
end)
