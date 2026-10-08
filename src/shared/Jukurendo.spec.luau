--!strict
local Config = require("./Config")
local Hikei = require("./Hikei")
local Jukurendo = require("./Jukurendo")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

-- 武勇・知略・堅牢の3つの系統。武勇と堅牢は3枚、知略は2枚
local PARAMS: Config.JukurendoSection = {
	Keito = {
		Buyu = {
			Hikei = {
				{ Id = "Kishinka", Jukurendo = 0 },
				{ Id = "Daikatsu", Jukurendo = 50 },
				{ Id = "Chohatsu", Jukurendo = 150 },
			},
			Rate = 0.1,
			Max = 30,
		},
		Chiryaku = {
			Hikei = {
				{ Id = "Rakuseki", Jukurendo = 0 },
				{ Id = "Daikakei", Jukurendo = 50 },
			},
			Rate = 10,
			Max = 30,
		},
		Kenro = {
			Hikei = {
				{ Id = "Fukuhei", Jukurendo = 0 },
				{ Id = "Hyoroko", Jukurendo = 50 },
				{ Id = "Bakuhawana", Jukurendo = 150 },
			},
			Rate = 1,
			Max = 30,
		},
	},
}

local INITIAL = { "Fukuhei", "Rakuseki", "Kishinka" }

local function dataOf(jukurendo: { [string]: number }, hikei: { string }, m1Checked: boolean?): Jukurendo.Data
	return { version = Jukurendo.VERSION, jukurendo = jukurendo, hikei = hikei, m1Checked = m1Checked == true }
end

local function counts(gekihasu: number, seiatsusu: number, kyuensu: number): Jukurendo.Counts
	return { gekihasu = gekihasu, seiatsusu = seiatsusu, kyuensu = kyuensu }
end

test("系統は武勇・知略・堅牢の3つで、名前と熟練度を上げる戦い方がある", function()
	expect(Jukurendo.keitoList).toEqual({ "Buyu", "Chiryaku", "Kenro" })
	for _, keito in Jukurendo.keitoList do
		expect(#(Jukurendo.names[keito] or "") > 0).toBe(true)
		expect(#(Jukurendo.sourceNames[keito] or "") > 0).toBe(true)
		expect(#(Jukurendo.countNames[keito] or "") > 0).toBe(true)
	end
	expect(Jukurendo.names.Buyu).toBe("武勇")
	expect(Jukurendo.countNames.Chiryaku).toBe("制圧数")
	expect(Jukurendo.countNames.Kenro).toBe("救援数")
end)

test("系統の熟練度を上げる数は、武勇が撃破数、知略が制圧数、堅牢が救援数", function()
	local value = counts(120, 2, 7)
	expect(Jukurendo.countOf(value, "Buyu")).toBe(120)
	expect(Jukurendo.countOf(value, "Chiryaku")).toBe(2)
	expect(Jukurendo.countOf(value, "Kenro")).toBe(7)
	expect(Jukurendo.countOf(value, "Nowhere")).toBe(0)
end)

test("秘計の系統と覚える熟練度を引き、どの系統にも無い秘計は nil", function()
	local keito, threshold = Jukurendo.keitoOf("Daikatsu", PARAMS)
	expect(keito).toBe("Buyu")
	expect(threshold).toBe(50)
	keito, threshold = Jukurendo.keitoOf("Fukuhei", PARAMS)
	expect(keito).toBe("Kenro")
	expect(threshold).toBe(0)
	keito, threshold = Jukurendo.keitoOf("Musou", PARAMS)
	expect(keito).toBe(nil)
	expect(threshold).toBe(nil)
end)

test("M1 の8種は定義にある秘計のすべて", function()
	expect(Jukurendo.M1_HIKEI).toEqual(Hikei.selectable())
end)

test(
	"新規の記録は熟練度も覚えた秘計も無く、覚える熟練度が 0 の秘計だけを覚えている",
	function()
		local data = Jukurendo.new()
		expect(data).toEqual({ version = Jukurendo.VERSION, jukurendo = {}, hikei = {}, m1Checked = false })
		expect(Jukurendo.jukurendoOf(data, "Buyu")).toBe(0)
		expect(Jukurendo.learned(data, PARAMS)).toEqual(INITIAL)
		expect(Jukurendo.initialHikei(PARAMS)).toEqual(INITIAL)
		expect(Jukurendo.isLearned(data, "Kishinka", PARAMS)).toBe(true)
		expect(Jukurendo.isLearned(data, "Daikatsu", PARAMS)).toBe(false)
	end
)

test(
	"熟練度が覚える値に達した秘計を覚え、覚えた秘計は設計の表の順に並べる",
	function()
		local data = dataOf({ Buyu = 50, Kenro = 149 }, {})
		expect(Jukurendo.learned(data, PARAMS)).toEqual({ "Fukuhei", "Rakuseki", "Hyoroko", "Kishinka", "Daikatsu" })
		local all = dataOf({ Buyu = 150, Chiryaku = 50, Kenro = 150 }, {})
		expect(Jukurendo.learned(all, PARAMS)).toEqual(Hikei.selectable())
	end
)

test(
	"記録の覚えた秘計は熟練度が足りなくても覚えていて、定義に無い秘計は入れない",
	function()
		local data = dataOf({}, { "Bakuhawana", "Chohatsu", "Removed" })
		expect(Jukurendo.learned(data, PARAMS)).toEqual({
			"Fukuhei",
			"Rakuseki",
			"Bakuhawana",
			"Chohatsu",
			"Kishinka",
		})
		expect(Jukurendo.isLearned(data, "Removed", PARAMS)).toBe(false)
	end
)

test(
	"次に覚える秘計は、系統の中で覚える順に見て、まだ覚えていない最初の秘計",
	function()
		local data = dataOf({ Buyu = 45 }, {})
		local nextId, threshold = Jukurendo.nextOf(data, "Buyu", PARAMS)
		expect(nextId).toBe("Daikatsu")
		expect(threshold).toBe(50)
		-- 記録で覚えた秘計は飛ばす
		nextId, threshold = Jukurendo.nextOf(dataOf({ Buyu = 45 }, { "Daikatsu" }), "Buyu", PARAMS)
		expect(nextId).toBe("Chohatsu")
		expect(threshold).toBe(150)
		-- すべて覚えていれば nil
		nextId, threshold = Jukurendo.nextOf(dataOf({ Chiryaku = 80 }, {}), "Chiryaku", PARAMS)
		expect(nextId).toBe(nil)
		expect(threshold).toBe(nil)
		nextId = Jukurendo.nextOf(data, "Nowhere", PARAMS)
		expect(nextId).toBe(nil)
	end
)

test(
	"決着したときに足す熟練度は、戦い方の数に Rate を掛けて切り捨て、Max までにする",
	function()
		expect(Jukurendo.gainOf(counts(129, 1, 7), PARAMS)).toEqual({ Buyu = 12, Chiryaku = 10, Kenro = 7 })
		expect(Jukurendo.gainOf(counts(9, 0, 0), PARAMS)).toEqual({ Buyu = 0, Chiryaku = 0, Kenro = 0 })
		expect(Jukurendo.gainOf(counts(5000, 4, 31), PARAMS)).toEqual({ Buyu = 30, Chiryaku = 30, Kenro = 30 })
		expect(Jukurendo.gainOf(counts(300, 3, 30), PARAMS)).toEqual({ Buyu = 30, Chiryaku = 30, Kenro = 30 })
	end
)

test("戦い方の数が負か数でないか無限大のときは、0 か上限にする", function()
	expect(Jukurendo.gainOf(counts(-100, -1, 0 / 0), PARAMS)).toEqual({ Buyu = 0, Chiryaku = 0, Kenro = 0 })
	expect(Jukurendo.gainOf(counts(math.huge, 0, 0), PARAMS)).toEqual({ Buyu = 30, Chiryaku = 0, Kenro = 0 })
end)

test(
	"変更は熟練度を足し、覚えた秘計を加え、熟練度で覚えた秘計も記録に加える。引数は書き換えない",
	function()
		local data = dataOf({ Buyu = 40 }, { "Fukuhei", "Kishinka", "Rakuseki" })
		local next = Jukurendo.apply(data, { jukurendo = { Buyu = 12, Kenro = 3 } }, PARAMS)
		expect(next.jukurendo).toEqual({ Buyu = 52, Kenro = 3 })
		expect(next.hikei).toEqual({ "Daikatsu", "Fukuhei", "Kishinka", "Rakuseki" })
		expect(next.m1Checked).toBe(false)
		expect(data).toEqual(dataOf({ Buyu = 40 }, { "Fukuhei", "Kishinka", "Rakuseki" }))
		local learned = Jukurendo.apply(next, { hikei = { "Hyoroko" } }, PARAMS)
		expect(learned.hikei).toEqual({ "Daikatsu", "Fukuhei", "Hyoroko", "Kishinka", "Rakuseki" })
	end
)

test(
	"1 未満と端数の熟練度は捨て、覚えた秘計を重ねても、確かめ済みを重ねても変わらない",
	function()
		local data = dataOf({ Buyu = 10 }, { "Fukuhei", "Kishinka", "Rakuseki" }, true)
		expect(Jukurendo.apply(data, { jukurendo = { Buyu = 0 } }, PARAMS)).toBe(data)
		expect(Jukurendo.apply(data, { jukurendo = { Buyu = -5 } }, PARAMS)).toBe(data)
		expect(Jukurendo.apply(data, { jukurendo = { Buyu = 0 / 0 } }, PARAMS)).toBe(data)
		expect(Jukurendo.apply(data, { jukurendo = { Buyu = math.huge } }, PARAMS)).toBe(data)
		expect(Jukurendo.apply(data, { hikei = { "Kishinka" } }, PARAMS)).toBe(data)
		expect(Jukurendo.apply(data, { m1Checked = true }, PARAMS)).toBe(data)
		expect(Jukurendo.apply(data, { jukurendo = { Buyu = 2.7 } }, PARAMS).jukurendo.Buyu).toBe(12)
	end
)

test("熟練度で覚えた秘計は、後で覚える熟練度を上げても忘れない", function()
	local data = Jukurendo.apply(Jukurendo.new(), { jukurendo = { Buyu = 60 } }, PARAMS)
	expect(Jukurendo.isLearned(data, "Daikatsu", PARAMS)).toBe(true)
	-- 大喝を覚える熟練度を 100 に上げた定義でも覚えている
	local raised = table.clone(PARAMS.Keito)
	raised.Buyu = {
		Hikei = {
			{ Id = "Kishinka", Jukurendo = 0 },
			{ Id = "Daikatsu", Jukurendo = 100 },
			{ Id = "Chohatsu", Jukurendo = 150 },
		},
		Rate = 0.1,
		Max = 30,
	}
	expect(Jukurendo.isLearned(data, "Daikatsu", { Keito = raised })).toBe(true)
end)

test(
	"読み込みに失敗したまま得た熟練度と覚えた秘計は、保存済みの記録に当てると両方残る",
	function()
		-- 保存済みの記録は、武勇 40 と知略 50（大火計まで覚えた）。読み込めなかったサーバーは新規の記録から始め、
		-- 武勇を 12 と堅牢を 3 得た
		local stored = Jukurendo.apply(dataOf({ Buyu = 40, Chiryaku = 50 }, {}, true), {}, PARAMS)
		local changes: { Jukurendo.Change } = {
			{ jukurendo = { Buyu = 12, Chiryaku = 0, Kenro = 3 } },
		}
		local saved = stored
		for _, change in changes do
			saved = Jukurendo.apply(saved, change, PARAMS)
		end
		expect(saved.jukurendo).toEqual({ Buyu = 52, Chiryaku = 50, Kenro = 3 })
		expect(saved.m1Checked).toBe(true)
		expect(Jukurendo.learned(saved, PARAMS)).toEqual({
			"Fukuhei",
			"Rakuseki",
			"Daikakei",
			"Kishinka",
			"Daikatsu",
		})
	end
)

test(
	"M1 から遊ぶ人（進行にクリア済みのステージがある）は M1 の8種を覚え、確かめたことを残す",
	function()
		local change = Jukurendo.m1ChangeOf({ "Iga1" })
		expect(change.m1Checked).toBe(true)
		local data = Jukurendo.apply(Jukurendo.new(), change, PARAMS)
		expect(data.m1Checked).toBe(true)
		expect(Jukurendo.learned(data, PARAMS)).toEqual(Jukurendo.M1_HIKEI)
		-- 熟練度は 0 のまま
		expect(Jukurendo.jukurendoOf(data, "Buyu")).toBe(0)
		expect(Jukurendo.progressOf(data, "Buyu", PARAMS)).toBe("熟練度 0　すべて覚えた")
	end
)

test(
	"進行にクリア済みのステージが無い人は、最初の秘計だけのまま確かめたことを残す",
	function()
		local change = Jukurendo.m1ChangeOf({})
		expect(change).toEqual({ m1Checked = true })
		local data = Jukurendo.apply(Jukurendo.new(), change, PARAMS)
		expect(data.m1Checked).toBe(true)
		expect(Jukurendo.learned(data, PARAMS)).toEqual(INITIAL)
	end
)

test(
	"M1 の8種を加えた記録に、読み込みに失敗したサーバーの熟練度を当てても8種が残る",
	function()
		local stored = Jukurendo.apply(Jukurendo.new(), Jukurendo.m1ChangeOf({ "Iga1" }), PARAMS)
		local saved = Jukurendo.apply(stored, { jukurendo = { Kenro = 5 } }, PARAMS)
		expect(Jukurendo.learned(saved, PARAMS)).toEqual(Jukurendo.M1_HIKEI)
		expect(saved.jukurendo).toEqual({ Kenro = 5 })
	end
)

test("DataStore から読んだ値が表でなければ新規として扱う", function()
	expect(Jukurendo.normalize(nil)).toBe(nil)
	expect(Jukurendo.normalize("Buyu")).toBe(nil)
	expect(Jukurendo.normalize(3)).toBe(nil)
end)

test(
	"読んだ値の欠けた項目と形の違う項目は空にし、文字列でない秘計とキーが文字列でない熟練度は捨てる",
	function()
		local data = Jukurendo.normalize({
			jukurendo = { Buyu = 12.7, Chiryaku = -3, Kenro = "x", [2] = 5 },
			hikei = { "Kishinka", 4, "Daikatsu", "Kishinka" },
			m1Checked = "yes",
		}) :: Jukurendo.Data
		expect(data).toEqual({
			version = Jukurendo.VERSION,
			jukurendo = { Buyu = 12, Chiryaku = 0, Kenro = 0 },
			hikei = { "Daikatsu", "Kishinka" },
			m1Checked = false,
		})
		expect(Jukurendo.normalize({}) :: Jukurendo.Data).toEqual(Jukurendo.new())
	end
)

test("読んだ値の定義に無い系統と秘計、新しい版、確かめ済みはそのまま残す", function()
	local data = Jukurendo.normalize({
		version = 2,
		jukurendo = { Ninpo = 30 },
		hikei = { "Removed" },
		m1Checked = true,
	}) :: Jukurendo.Data
	expect(data.version).toBe(2)
	expect(data.jukurendo).toEqual({ Ninpo = 30 })
	expect(data.hikei).toEqual({ "Removed" })
	expect(data.m1Checked).toBe(true)
end)

test("届いた JukurendoState を読み、形が違えば nil", function()
	local state =
		Jukurendo.normalizeState({ loaded = true, data = dataOf({ Buyu = 3 }, { "Kishinka" }) }) :: Jukurendo.State
	expect(state.loaded).toBe(true)
	expect(state.data.jukurendo).toEqual({ Buyu = 3 })
	local notLoaded = Jukurendo.normalizeState({ loaded = "yes", data = {} }) :: Jukurendo.State
	expect(notLoaded.loaded).toBe(false)
	expect(Jukurendo.normalizeState(nil)).toBe(nil)
	expect(Jukurendo.normalizeState({ loaded = true })).toBe(nil)
end)

test("秘計の欄の系統の見出しは、系統の名前と熟練度を上げる戦い方", function()
	expect(Jukurendo.titleOf("Buyu")).toBe("武勇（撃破で上がる）")
	expect(Jukurendo.titleOf("Chiryaku")).toBe("知略（拠点の制圧で上がる）")
	expect(Jukurendo.titleOf("Kenro")).toBe("堅牢（救援で上がる）")
	expect(Jukurendo.titleOf("Nowhere")).toBe("Nowhere")
end)

test("系統の熟練度と、次に覚える秘計まであといくつかを書く", function()
	expect(Jukurendo.progressOf(dataOf({ Buyu = 45 }, {}), "Buyu", PARAMS)).toBe("熟練度 45　あと 5 で大喝")
	expect(Jukurendo.progressOf(dataOf({ Buyu = 50 }, {}), "Buyu", PARAMS)).toBe("熟練度 50　あと 100 で挑発")
	expect(Jukurendo.progressOf(Jukurendo.new(), "Kenro", PARAMS)).toBe("熟練度 0　あと 50 で兵糧庫")
	expect(Jukurendo.progressOf(dataOf({ Chiryaku = 70 }, {}), "Chiryaku", PARAMS)).toBe(
		"熟練度 70　すべて覚えた"
	)
end)

test("正しい系統の定義には誤りが無い", function()
	expect(Jukurendo.validate(PARAMS)).toEqual({})
end)

test(
	"系統の定義の誤り（系統の欠けと余り・秘計の重なりと漏れ・覚える熟練度・Rate と Max）を見つける",
	function()
		local problems = Jukurendo.validate({
			Keito = {
				Buyu = {
					Hikei = {
						{ Id = "Kishinka", Jukurendo = 10 },
						{ Id = "Daikatsu", Jukurendo = 5 },
						{ Id = "Musou", Jukurendo = 20 },
					},
					Rate = 0,
					Max = 1.5,
				},
				Chiryaku = {
					Hikei = {
						{ Id = "Rakuseki", Jukurendo = 0 },
						{ Id = "Kishinka", Jukurendo = 50 },
					},
					Rate = 10,
					Max = 30,
				},
				Ninpo = { Hikei = {}, Rate = 1, Max = 1 },
			},
		})
		expect(problems).toEqual({
			"Ninpo: 系統の並び（keitoList）に無い",
			"Buyu: 最初の秘計 Kishinka の熟練度が 0 でない",
			"Buyu: 秘計 Daikatsu の熟練度 5 が前の秘計より大きくない",
			"Buyu: 秘計 Musou は定義に無い",
			"Buyu: Rate 0 が 0 より大きくない",
			"Buyu: Max 1.5 が 0 以上の整数でない",
			"Chiryaku: 秘計 Kishinka は Buyu にもある",
			"Kenro: Config に系統が無い",
			"Fukuhei: どの系統にも無い",
			"Daikakei: どの系統にも無い",
			"Hyoroko: どの系統にも無い",
			"Bakuhawana: どの系統にも無い",
			"Chohatsu: どの系統にも無い",
		})
	end
)
