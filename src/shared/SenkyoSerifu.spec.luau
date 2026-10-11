--!strict
local Config = require("./Config")
local SenkyoSerifu = require("./SenkyoSerifu")
local Serifu = require("./Serifu")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

type Entry = SenkyoSerifu.Entry
type Henka = SenkyoSerifu.Henka

local PARAMS: Config.SenkyoSerifuSection = {
	CheckInterval = 1,
	SekkinRange = 80,
	HanbunRate = 0.5,
	OshiMargin = 5,
}

local function entry(fields: { [string]: any }): Entry
	local result: { [string]: any } = { id = "X", speaker = "Hayate", hyojo = "Tsujo" }
	for key, value in fields do
		result[key] = value
	end
	return result :: any
end

local function matches(e: Entry, d: { [string]: any }): boolean
	return SenkyoSerifu.matches(e, d :: any, PARAMS)
end

test("発火の表に誤りが無い（文・話者・表情・条件・ステージの NPC）", function()
	expect(SenkyoSerifu.check()).toEqual({})
end)

test("発火の表の誤りを見つける", function()
	local original = SenkyoSerifu.definitions.Test
	local broken = table.clone(original)
	table.insert(broken, entry({ id = "NoText", kikkake = "Kaishi" }))
	table.insert(broken, entry({ id = "ShikenKaishi", kikkake = "Kaishi" }))
	table.insert(broken, entry({ id = "ShikenOshi", kikkake = "Oshi" }))
	table.insert(broken, entry({ id = "ShikenTanshuku", kikkake = "Sekkin", gun = "Mikatagun" }))
	table.insert(broken, entry({ id = "ShikenNagai", kikkake = "Hikei", jonin = "Atoza", hikei = "Nanika" }))
	table.insert(broken, entry({ id = "ShikenTsujo", kikkake = "Gekiha", speaker = "Atoza" }))
	SenkyoSerifu.definitions.Test = broken
	local problems = SenkyoSerifu.check()
	SenkyoSerifu.definitions.Test = original
	local joined = table.concat(problems, "\n")
	expect(string.find(joined, "NoText） の文が Serifu.luau に無い", 1, true) ~= nil).toBe(true)
	expect(string.find(joined, "ShikenKaishi） の台詞 ID は Test と重なる", 1, true) ~= nil).toBe(true)
	expect(string.find(joined, "ShikenOshi） に jonin が無い", 1, true) ~= nil).toBe(true)
	expect(string.find(joined, "ShikenTanshuku） に拠点の条件（honjin か shubi）が無い", 1, true) ~= nil).toBe(
		true
	)
	expect(string.find(joined, "ShikenNagai） の jonin Atoza はこのステージの NPC に無い", 1, true) ~= nil).toBe(
		true
	)
	expect(string.find(joined, "ShikenNagai） の秘計 Nanika は無い", 1, true) ~= nil).toBe(true)
	expect(string.find(joined, "ShikenTsujo） の話者 Atoza はこのステージに出ない", 1, true) ~= nil).toBe(
		true
	)
	expect(
		string.find(joined, "ShikenTsujo） に倒れる上忍の条件（jonin か gun）が無い", 1, true) ~= nil
	).toBe(true)
	expect(SenkyoSerifu.check()).toEqual({})
end)

test(
	"伊賀第1ステージの文と話者と表情は、台本の下書き（docs/story/iga-1.md）の同じ ID の行と同じ",
	function()
		local doc = testkit.readFile("docs/story/iga-1.md") :: string
		expect(doc ~= nil).toBe(true)
		-- 台本の表の行（| ID | 発火する出来事 | 話者 | 表情 | 台詞 |）を ID で引く
		local rows: { [string]: { string } } = {}
		for line in string.gmatch(doc, "[^\n]+") do
			local cells = {}
			for cell in string.gmatch(line, "|([^|]*)") do
				table.insert(cells, (string.gsub(cell, "^%s*(.-)%s*$", "%1")))
			end
			if #cells >= 5 and string.match(cells[1], "^B[%w]+$") then
				rows[cells[1]] = cells
			end
		end
		local names =
			{ Hayate = "ハヤテ", Jin = "刃", Torika = "酉花", Sekishusai = "石舟斎", KanaOni = "金鬼" }
		local hyojo = { Tsujo = "通常", Ikari = "怒り", Odoroki = "驚き", Yorokobi = "喜び", Kumon = "苦悶" }
		local entries = SenkyoSerifu.entriesOf("Iga1")
		expect(#entries > 0).toBe(true)
		for _, e in entries do
			local scriptId = string.sub(e.id, #"Iga1" + 1)
			local row = rows[scriptId]
			expect(row ~= nil).toBe(true)
			expect(row[3]).toBe(names[e.speaker])
			expect(row[4]).toBe(hyojo[e.hyojo])
			expect(row[5]).toBe(Serifu.textOf(e.id))
		end
	end
)

test("戦闘のフェーズの開始には Kaishi だけが合う", function()
	expect(matches(entry({ kikkake = "Kaishi" }), { kikkake = "Kaishi" })).toBe(true)
	expect(matches(entry({ kikkake = "Kaishi" }), { kikkake = "Seiatsu", gun = "Tekigun" })).toBe(false)
end)

test("制圧と孤立は軍で絞る", function()
	local teki = entry({ kikkake = "Seiatsu", gun = "Tekigun" })
	expect(matches(teki, { kikkake = "Seiatsu", gun = "Tekigun" })).toBe(true)
	expect(matches(teki, { kikkake = "Seiatsu", gun = "Mikatagun" })).toBe(false)
	local koritsu = entry({ kikkake = "Koritsu", gun = "Mikatagun" })
	expect(matches(koritsu, { kikkake = "Koritsu", gun = "Mikatagun" })).toBe(true)
	expect(matches(koritsu, { kikkake = "Koritsu", gun = "Tekigun" })).toBe(false)
end)

test("接近は拠点の軍と、本陣か担当の上忍と、近づいた部隊の上忍で絞る", function()
	local honjin = entry({ kikkake = "Sekkin", gun = "Mikatagun", honjin = true })
	expect(matches(honjin, { kikkake = "Sekkin", gun = "Mikatagun", honjin = true, shubi = {} })).toBe(true)
	expect(matches(honjin, { kikkake = "Sekkin", gun = "Mikatagun", honjin = false, shubi = {} })).toBe(false)
	expect(matches(honjin, { kikkake = "Sekkin", gun = "Tekigun", honjin = true, shubi = {} })).toBe(false)
	local nishi = entry({ kikkake = "Sekkin", gun = "Mikatagun", shubi = "Rei", butaiJonin = "Aun" })
	local base = { kikkake = "Sekkin", gun = "Mikatagun", honjin = false, shubi = { "Rei" }, butaiJonin = "Aun" }
	expect(matches(nishi, base)).toBe(true)
	expect(matches(nishi, { kikkake = "Sekkin", gun = "Mikatagun", honjin = false, shubi = { "Rei" } })).toBe(false)
	expect(matches(nishi, { kikkake = "Sekkin", gun = "Mikatagun", honjin = false, shubi = { "Anne" } })).toBe(false)
	-- 近づいた部隊の上忍を置かなければ、どの部隊でも合う
	local any = entry({ kikkake = "Sekkin", gun = "Mikatagun", shubi = "Rei" })
	expect(matches(any, { kikkake = "Sekkin", gun = "Mikatagun", honjin = false, shubi = { "Rei" } })).toBe(true)
end)

test("耐久が半分を切ったのは、半分以上から半分より下へ変わったときだけ", function()
	local e = entry({ kikkake = "TaikyuHanbun", gun = "Mikatagun", shubi = "Rei" })
	local function d(before: number, after: number, gun: string?): { [string]: any }
		return {
			kikkake = "TaikyuHanbun",
			gun = gun or "Mikatagun",
			honjin = false,
			shubi = { "Rei" },
			before = before,
			after = after,
			max = 30,
		}
	end
	expect(matches(e, d(16, 14))).toBe(true)
	expect(matches(e, d(15, 14))).toBe(true)
	expect(matches(e, d(15, 15))).toBe(false)
	expect(matches(e, d(14, 13))).toBe(false)
	expect(matches(e, d(13, 20))).toBe(false)
	expect(matches(e, d(16, 14, "Tekigun"))).toBe(false)
end)

test("押されているのは、交戦の損害が相手より OshiMargin 以上多いとき", function()
	local e = entry({ kikkake = "Oshi", jonin = "Anne" })
	expect(matches(e, { kikkake = "Oshi", jonin = "Anne", songai = 8, aiteSongai = 3 })).toBe(true)
	expect(matches(e, { kikkake = "Oshi", jonin = "Anne", songai = 7, aiteSongai = 3 })).toBe(false)
	expect(matches(e, { kikkake = "Oshi", jonin = "Shion", songai = 8, aiteSongai = 3 })).toBe(false)
	expect(matches(e, { kikkake = "Oshi", jonin = "Anne" })).toBe(false)
end)

test("秘計と奇襲と姿を現したのは、上忍と秘計で絞る", function()
	local rakuseki = entry({ kikkake = "Hikei", jonin = "Roton", hikei = "Rakuseki" })
	expect(matches(rakuseki, { kikkake = "Hikei", jonin = "Roton", hikei = "Rakuseki" })).toBe(true)
	expect(matches(rakuseki, { kikkake = "Hikei", jonin = "Roton", hikei = "Daikakei" })).toBe(false)
	expect(matches(rakuseki, { kikkake = "Hikei", jonin = "Dan", hikei = "Rakuseki" })).toBe(false)
	expect(matches(entry({ kikkake = "Kishu", jonin = "Dan" }), { kikkake = "Kishu", jonin = "Dan" })).toBe(true)
	expect(matches(entry({ kikkake = "Kishu", jonin = "Dan" }), { kikkake = "Kishu", jonin = "Roton" })).toBe(false)
	local shutsugen = entry({ kikkake = "Shutsugen", jonin = "Atoza" })
	expect(matches(shutsugen, { kikkake = "Shutsugen", jonin = "Atoza" })).toBe(true)
	expect(matches(shutsugen, { kikkake = "Shutsugen", jonin = "Aun" })).toBe(false)
end)

test(
	"撃破は上忍で絞るか、軍の上忍（首領を除く）で絞り、by で倒した人のキャラクターを絞る",
	function()
		local aun = entry({ kikkake = "Gekiha", jonin = "Aun" })
		expect(matches(aun, { kikkake = "Gekiha", jonin = "Aun", gun = "Tekigun", shuryo = false })).toBe(true)
		expect(matches(aun, { kikkake = "Gekiha", jonin = "Dan", gun = "Tekigun", shuryo = false })).toBe(false)
		local teki = entry({ kikkake = "Gekiha", gun = "Tekigun" })
		expect(matches(teki, { kikkake = "Gekiha", jonin = "Dan", gun = "Tekigun", shuryo = false })).toBe(true)
		expect(matches(teki, { kikkake = "Gekiha", jonin = "Atoza", gun = "Tekigun", shuryo = true })).toBe(false)
		expect(matches(teki, { kikkake = "Gekiha", jonin = "Rei", gun = "Mikatagun", shuryo = false })).toBe(false)
		local jin = entry({ kikkake = "Gekiha", gun = "Tekigun", by = "Jin" })
		expect(matches(jin, { kikkake = "Gekiha", jonin = "Dan", gun = "Tekigun", shuryo = false, by = "Jin" })).toBe(
			true
		)
		expect(matches(jin, { kikkake = "Gekiha", jonin = "Dan", gun = "Tekigun", shuryo = false, by = "Torika" })).toBe(
			false
		)
		expect(matches(jin, { kikkake = "Gekiha", jonin = "Dan", gun = "Tekigun", shuryo = false })).toBe(false)
	end
)

test(
	"体力が半分を切ったのは、半分以上から半分より下へ変わったときで、倒れたときは除く",
	function()
		local e = entry({ kikkake = "TairyokuHanbun", jonin = "Hayate" })
		local function d(before: number, after: number): { [string]: any }
			return { kikkake = "TairyokuHanbun", jonin = "Hayate", before = before, after = after, max = 1000 }
		end
		expect(matches(e, d(520, 480))).toBe(true)
		expect(matches(e, d(500, 499))).toBe(true)
		expect(matches(e, d(480, 400))).toBe(false)
		expect(matches(e, d(600, 0))).toBe(false)
		expect(matches(e, d(600, 550))).toBe(false)
	end
)

test(
	"残り時間は境を上から越えたときだけ、兵力はちょうどその値まで減ったときだけ",
	function()
		local nokori = entry({ kikkake = "Nokori", seconds = 600 })
		expect(matches(nokori, { kikkake = "Nokori", before = 600.5, after = 599.5 })).toBe(true)
		expect(matches(nokori, { kikkake = "Nokori", before = 599, after = 598 })).toBe(false)
		expect(matches(nokori, { kikkake = "Nokori", before = 700, after = 650 })).toBe(false)
		expect(matches(nokori, { kikkake = "Nokori", after = 500 })).toBe(false)
		local heiryoku = entry({ kikkake = "Heiryoku", value = 1 })
		expect(matches(heiryoku, { kikkake = "Heiryoku", before = 2, after = 1 })).toBe(true)
		expect(matches(heiryoku, { kikkake = "Heiryoku", before = 5, after = 1 })).toBe(true)
		expect(matches(heiryoku, { kikkake = "Heiryoku", before = 1, after = 1 })).toBe(false)
		expect(matches(heiryoku, { kikkake = "Heiryoku", before = 0, after = 1 })).toBe(false)
		expect(matches(heiryoku, { kikkake = "Heiryoku", before = 2, after = 0 })).toBe(false)
	end
)

test(
	"出した台詞は2回目を出さず、操作キャラクターの差し込みはそのキャラクターで出撃したときだけ",
	function()
		local npc = entry({ id = "A", kikkake = "Kaishi", speaker = "Hayate" })
		local jin = entry({ id = "B", kikkake = "Kaishi", speaker = "Jin" })
		expect(SenkyoSerifu.canPlay(npc, {}, {})).toBe(true)
		expect(SenkyoSerifu.canPlay(npc, { A = true }, {})).toBe(false)
		expect(SenkyoSerifu.canPlay(jin, {}, {})).toBe(false)
		expect(SenkyoSerifu.canPlay(jin, {}, { Torika = true })).toBe(false)
		expect(SenkyoSerifu.canPlay(jin, {}, { Jin = true })).toBe(true)
		expect(SenkyoSerifu.canPlay(jin, { B = true }, { Jin = true })).toBe(false)
	end
)

test("変化に合う台詞を表の順にすべて選ぶ", function()
	local entries = {
		entry({ id = "First", kikkake = "Gekiha", gun = "Tekigun", speaker = "Hayate" }),
		entry({ id = "Other", kikkake = "Kaishi", speaker = "Hayate" }),
		entry({ id = "JinLine", kikkake = "Gekiha", gun = "Tekigun", by = "Jin", speaker = "Jin" }),
		entry({ id = "TorikaLine", kikkake = "Gekiha", gun = "Tekigun", by = "Torika", speaker = "Torika" }),
	}
	local d: Henka = { kikkake = "Gekiha", jonin = "Dan", gun = "Tekigun", shuryo = false, by = "Jin" }
	local picked = SenkyoSerifu.pick(entries, d, {}, { Jin = true, Torika = true }, PARAMS)
	expect(#picked).toBe(2)
	expect(picked[1].id).toBe("First")
	expect(picked[2].id).toBe("JinLine")
	-- 出した台詞は外れる
	local again = SenkyoSerifu.pick(entries, d, { First = true }, { Jin = true }, PARAMS)
	expect(#again).toBe(1)
	expect(again[1].id).toBe("JinLine")
end)

test("まだ出していないきっかけの台詞があるかを数える", function()
	local entries = {
		entry({ id = "A", kikkake = "Nokori", seconds = 600 }),
		entry({ id = "B", kikkake = "Nokori", seconds = 300 }),
	}
	expect(SenkyoSerifu.hasPending(entries, "Nokori", {})).toBe(true)
	expect(SenkyoSerifu.hasPending(entries, "Nokori", { A = true })).toBe(true)
	expect(SenkyoSerifu.hasPending(entries, "Nokori", { A = true, B = true })).toBe(false)
	expect(SenkyoSerifu.hasPending(entries, "Sekkin", {})).toBe(false)
end)

test("ステージの表を引き、表の無いステージは空", function()
	expect(#SenkyoSerifu.entriesOf("Test") > 0).toBe(true)
	expect(#SenkyoSerifu.entriesOf("Nowhere")).toBe(0)
	expect(#SenkyoSerifu.entriesOf(nil)).toBe(0)
end)

test("試験用ステージの表は、どのきっかけも1本以上ある", function()
	local found: { [string]: boolean } = {}
	for _, e in SenkyoSerifu.entriesOf("Test") do
		found[e.kikkake] = true
	end
	for _, kikkake in SenkyoSerifu.kikkakeList do
		expect(found[kikkake] == true).toBe(true)
	end
end)

test("戦況の台詞の数値の範囲", function()
	local p = Config.SenkyoSerifu
	expect(p.CheckInterval > 0).toBe(true)
	expect(p.SekkinRange > 0).toBe(true)
	expect(p.HanbunRate > 0 and p.HanbunRate < 1).toBe(true)
	expect(p.OshiMargin >= 1).toBe(true)
end)
