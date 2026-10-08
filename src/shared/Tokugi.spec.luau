--!strict
local Characters = require("./Characters")
local Config = require("./Config")
local SelectionRules = require("./SelectionRules")
local Stats = require("./Stats")
local Tokugi = require("./Tokugi")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

-- 攻撃の2段と、体力から防御へつながる2段の小さなツリー
local TREE: Tokugi.Tree = {
	{ Id = "Goriki1", Stat = "Attack", Multiply = 1.03, Makimono = 1 },
	{ Id = "Ganken1", Stat = "MaxHealth", Multiply = 1.04, Makimono = 1 },
	{ Id = "Goriki2", Stat = "Attack", Multiply = 1.05, Makimono = 2, Zentei = { "Goriki1" } },
	{ Id = "Teppeki1", Stat = "Defense", Add = 2, Makimono = 3, Zentei = { "Ganken1" } },
}

local PARAMS: Config.TokugiSection = {
	Trees = { Jin = TREE },
	Makimono = { Gekihasu = 100, GekihasuMax = 5, Shori = 3 },
}

local LOBBY: SelectionRules.Requester = { phase = "Lobby", isLeader = false, waiting = false }

local function dataOf(makimono: number, tokugi: { string }): Tokugi.Data
	return { version = Tokugi.VERSION, characters = { Jin = { makimono = makimono, tokugi = tokugi } } }
end

test(
	"操作キャラクター全員に特技ツリーがあり、ツリーの無いキャラクターは空",
	function()
		for id, character in Characters.definitions do
			if character.playable then
				expect(#Tokugi.treeOf(id) > 0).toBe(true)
			end
		end
		expect(Tokugi.treeOf("Hayate")).toEqual({})
		expect(Tokugi.treeOf("Nowhere")).toEqual({})
	end
)

test("特技の名前は表から引き、表に無い ID はそのまま返す", function()
	expect(Tokugi.nameOf("Goriki1")).toBe("剛力・壱")
	expect(Tokugi.nameOf("Nowhere")).toBe("Nowhere")
end)

test("効果の文は能力値の名前と、掛ける値の百分率か足す値", function()
	expect(Tokugi.describe(TREE[1])).toBe("攻撃 +3%")
	expect(Tokugi.describe(TREE[2])).toBe("体力 +4%")
	expect(Tokugi.describe(TREE[4])).toBe("防御 +2")
	expect(Tokugi.describe({ Id = "X", Stat = "WalkSpeed", Multiply = 1.045, Makimono = 1 })).toBe("移動速度 +4.5%")
	expect(Tokugi.describe({ Id = "X", Stat = "AttackSpeed", Multiply = 0.95, Makimono = 1 })).toBe(
		"攻撃の速さ -5%"
	)
	expect(Tokugi.describe({ Id = "X", Stat = "Defense", Add = 1, Multiply = 1.1, Makimono = 1 })).toBe(
		"防御 +1、+10%"
	)
end)

test("段は前提の無い特技が 1 で、前提のある特技は一番深い前提の次", function()
	local depths = Tokugi.depthsOf({
		{ Id = "A", Stat = "Attack", Multiply = 1.01, Makimono = 1 },
		{ Id = "B", Stat = "Attack", Multiply = 1.01, Makimono = 1, Zentei = { "A" } },
		{ Id = "C", Stat = "Attack", Multiply = 1.01, Makimono = 1 },
		{ Id = "D", Stat = "Attack", Multiply = 1.01, Makimono = 1, Zentei = { "B", "C" } },
	})
	expect(depths).toEqual({ A = 1, B = 2, C = 1, D = 3 })
end)

test("段の計算は、めぐっている前提とツリーに無い前提で止まらない", function()
	local depths = Tokugi.depthsOf({
		{ Id = "A", Stat = "Attack", Multiply = 1.01, Makimono = 1, Zentei = { "B" } },
		{ Id = "B", Stat = "Attack", Multiply = 1.01, Makimono = 1, Zentei = { "A" } },
		{ Id = "C", Stat = "Attack", Multiply = 1.01, Makimono = 1, Zentei = { "Nowhere" } },
	})
	expect(depths.C).toBe(1)
	expect(depths.A ~= nil and depths.B ~= nil).toBe(true)
end)

test("正しいツリーには誤りが無い", function()
	expect(Tokugi.validateTree(TREE)).toEqual({})
end)

test("ツリーの誤り（重なり・名前・能力値・補正・巻物・前提）を見つける", function()
	local problems = Tokugi.validateTree({
		{ Id = "Goriki1", Stat = "Attack", Multiply = 1.03, Makimono = 1 },
		{ Id = "Goriki1", Stat = "Attack", Multiply = 1.03, Makimono = 1 },
		{ Id = "Nameless", Stat = "Attack", Multiply = 1.03, Makimono = 1 },
		{ Id = "Ganken1", Stat = "Health", Multiply = 1.03, Makimono = 1 },
		{ Id = "Ganken2", Stat = "MaxHealth", Makimono = 1 },
		{ Id = "Teppeki1", Stat = "Defense", Add = 1, Makimono = 0 },
		{ Id = "Kenkyaku1", Stat = "WalkSpeed", Multiply = 1.03, Makimono = 1.5 },
		{ Id = "Hayawaza1", Stat = "AttackSpeed", Multiply = 1.03, Makimono = 1, Zentei = { "Nowhere" } },
		{ Id = "Hayawaza2", Stat = "AttackSpeed", Multiply = 0, Makimono = 1 },
	})
	expect(problems).toEqual({
		"Goriki1: ID が重なっている",
		"Nameless: 名前が Tokugi.names に無い",
		"Ganken1: 能力値 Health は Stats.names に無い",
		"Ganken2: 補正（Add か Multiply）が無い",
		"Teppeki1: 巻物の数 0 が1以上の整数でない",
		"Kenkyaku1: 巻物の数 1.5 が1以上の整数でない",
		"Hayawaza2: 掛ける値 0 が 0 以下",
		"Hayawaza1: 前提 Nowhere がツリーに無い",
	})
end)

test("前提のめぐりと、自分を前提にした特技を見つける", function()
	local cycle = Tokugi.validateTree({
		{ Id = "Goriki1", Stat = "Attack", Multiply = 1.03, Makimono = 1, Zentei = { "Goriki2" } },
		{ Id = "Goriki2", Stat = "Attack", Multiply = 1.03, Makimono = 1, Zentei = { "Goriki1" } },
	})
	expect(cycle).toEqual({ "Goriki1: 前提がめぐっている" })
	local ownZentei = Tokugi.validateTree({
		{ Id = "Goriki1", Stat = "Attack", Multiply = 1.03, Makimono = 1, Zentei = { "Goriki1" } },
	})
	expect(ownZentei).toEqual({ "Goriki1: 前提がめぐっている" })
end)

test("新規の記録は巻物も特技も無い", function()
	local data = Tokugi.new()
	expect(data).toEqual({ version = Tokugi.VERSION, characters = {} })
	local record = Tokugi.recordOf(data, "Jin")
	expect(record).toEqual({ makimono = 0, tokugi = {} })
	expect(Tokugi.available(record, TREE)).toBe(0)
end)

test("使える巻物は、得た巻物の合計から覚えた特技の巻物の数を引いた数", function()
	local record = Tokugi.recordOf(dataOf(10, { "Ganken1", "Goriki1", "Goriki2" }), "Jin")
	expect(Tokugi.spent(record, TREE)).toBe(4)
	expect(Tokugi.available(record, TREE)).toBe(6)
	expect(Tokugi.learnedCount(record, TREE)).toBe(3)
end)

test("ツリーに無い特技は使った巻物に数えず、使える巻物は 0 未満にならない", function()
	local record = Tokugi.recordOf(dataOf(1, { "Goriki1", "Goriki2", "Removed" }), "Jin")
	expect(Tokugi.spent(record, TREE)).toBe(3)
	expect(Tokugi.available(record, TREE)).toBe(0)
	expect(Tokugi.learnedCount(record, TREE)).toBe(2)
end)

test("変更は巻物を足し、特技を加える。引数は書き換えない", function()
	local data = dataOf(2, { "Goriki1" })
	local next = Tokugi.apply(data, { character = "Jin", makimono = 3 })
	next = Tokugi.apply(next, { character = "Jin", tokugi = "Ganken1" })
	expect(next.characters.Jin).toEqual({ makimono = 5, tokugi = { "Ganken1", "Goriki1" } })
	expect(data.characters.Jin).toEqual({ makimono = 2, tokugi = { "Goriki1" } })
end)

test(
	"記録の無いキャラクターへの変更は、そのキャラクターの記録を作り、ほかのキャラクターは変えない",
	function()
		local data = dataOf(2, { "Goriki1" })
		local next = Tokugi.apply(data, { character = "KanaOni", makimono = 4 })
		expect(next.characters.KanaOni).toEqual({ makimono = 4, tokugi = {} })
		expect(next.characters.Jin).toEqual({ makimono = 2, tokugi = { "Goriki1" } })
	end
)

test("1 未満と端数の巻物は捨て、覚えた特技を重ねても変わらない", function()
	local data = dataOf(2, { "Goriki1" })
	expect(Tokugi.apply(data, { character = "Jin", makimono = 0 })).toBe(data)
	expect(Tokugi.apply(data, { character = "Jin", makimono = -3 })).toBe(data)
	expect(Tokugi.apply(data, { character = "Jin", makimono = 0 / 0 })).toBe(data)
	expect(Tokugi.apply(data, { character = "Jin", makimono = math.huge })).toBe(data)
	expect(Tokugi.apply(data, { character = "Jin", tokugi = "Goriki1" })).toBe(data)
	expect(Tokugi.apply(data, { character = "Jin", makimono = 2.7 }).characters.Jin.makimono).toBe(4)
end)

test(
	"読み込みに失敗したまま得た巻物と覚えた特技は、保存済みの記録に当てると両方残る",
	function()
		-- 保存済みの記録は、刃の巻物 10 本と剛力・壱。読み込めなかったサーバーは新規の記録から始め、巻物を得て頑健・壱を覚えた
		local stored = dataOf(10, { "Goriki1" })
		local changes: { Tokugi.Change } = {
			{ character = "Jin", makimono = 4 },
			{ character = "Jin", tokugi = "Ganken1" },
			{ character = "Torika", makimono = 2 },
		}
		local saved = stored
		for _, change in changes do
			saved = Tokugi.apply(saved, change)
		end
		expect(saved.characters.Jin).toEqual({ makimono = 14, tokugi = { "Ganken1", "Goriki1" } })
		expect(saved.characters.Torika).toEqual({ makimono = 2, tokugi = {} })
	end
)

test("DataStore から読んだ値が表でなければ新規として扱う", function()
	expect(Tokugi.normalize(nil)).toBe(nil)
	expect(Tokugi.normalize("Jin")).toBe(nil)
	expect(Tokugi.normalize(3)).toBe(nil)
end)

test(
	"読んだ値の欠けた項目と形の違う項目は空にし、文字列でない特技は捨てる",
	function()
		local data = Tokugi.normalize({
			characters = {
				Jin = { makimono = 3.6, tokugi = { "Goriki1", 5, "Goriki1", "Ganken1" } },
				Torika = { makimono = -2 },
				KanaOni = "broken",
				[3] = { makimono = 1 },
			},
		}) :: Tokugi.Data
		expect(data).toEqual({
			version = Tokugi.VERSION,
			characters = {
				Jin = { makimono = 3, tokugi = { "Ganken1", "Goriki1" } },
				Torika = { makimono = 0, tokugi = {} },
			},
		})
		expect(Tokugi.normalize({}) :: Tokugi.Data).toEqual(Tokugi.new())
	end
)

test("読んだ値のツリーに無いキャラクターと特技、新しい版はそのまま残す", function()
	local data = Tokugi.normalize({
		version = 2,
		characters = { Saika9 = { makimono = 4, tokugi = { "Removed" } } },
	}) :: Tokugi.Data
	expect(data.version).toBe(2)
	expect(data.characters.Saika9).toEqual({ makimono = 4, tokugi = { "Removed" } })
end)

test("覚えられるのは、前提を覚えていて巻物が足りる、まだ覚えていない特技", function()
	local data = dataOf(3, { "Goriki1" })
	expect(Tokugi.checkLearn(LOBBY, true, data, "Jin", "Goriki2", PARAMS)).toBe(nil)
	expect(Tokugi.checkLearn(LOBBY, true, data, "Jin", "Ganken1", PARAMS)).toBe(nil)
	expect(Tokugi.statusOf(Tokugi.recordOf(data, "Jin"), TREE, "Goriki2")).toBe("Learnable")
end)

test(
	"前提の足りない特技は TokugiZentei、巻物の足りない特技は MakimonoShort で拒否する",
	function()
		-- 巻物は 3 本得て、剛力・壱（1本）に使ったので 2 本残っている
		local data = dataOf(3, { "Goriki1" })
		expect(Tokugi.checkLearn(LOBBY, true, data, "Jin", "Teppeki1", PARAMS)).toBe("TokugiZentei")
		local withGanken = dataOf(3, { "Ganken1", "Goriki1" })
		-- 鉄壁・壱は 3 本要るが、残りは 1 本
		expect(Tokugi.checkLearn(LOBBY, true, withGanken, "Jin", "Teppeki1", PARAMS)).toBe("MakimonoShort")
		expect(Tokugi.checkLearn(LOBBY, true, Tokugi.new(), "Jin", "Goriki1", PARAMS)).toBe("MakimonoShort")
	end
)

test("前提と巻物がどちらも足りないときは前提を先に伝える", function()
	expect(Tokugi.checkLearn(LOBBY, true, Tokugi.new(), "Jin", "Goriki2", PARAMS)).toBe("TokugiZentei")
end)

test("覚えた特技とツリーに無い特技は拒否する", function()
	local data = dataOf(10, { "Goriki1" })
	expect(Tokugi.checkLearn(LOBBY, true, data, "Jin", "Goriki1", PARAMS)).toBe("TokugiLearned")
	expect(Tokugi.checkLearn(LOBBY, true, data, "Jin", "Nowhere", PARAMS)).toBe("UnknownTokugi")
	expect(Tokugi.checkLearn(LOBBY, true, data, "Hayate", "Goriki1", PARAMS)).toBe("UnknownTokugi")
end)

test(
	"ロビーのフェーズの外と待機中の人と、記録を読めていない人は覚えられない",
	function()
		local data = dataOf(10, {})
		local battle: SelectionRules.Requester = { phase = "Battle", isLeader = false, waiting = false }
		local waiting: SelectionRules.Requester = { phase = "Result", isLeader = false, waiting = true }
		expect(Tokugi.checkLearn(battle, true, data, "Jin", "Goriki1", PARAMS)).toBe("NotLobby")
		expect(Tokugi.checkLearn(waiting, true, data, "Jin", "Goriki1", PARAMS)).toBe("NotLobby")
		expect(
			Tokugi.checkLearn(
				{ phase = "Lobby", isLeader = false, waiting = true },
				true,
				data,
				"Jin",
				"Goriki1",
				PARAMS
			)
		).toBe("Waiting")
		expect(Tokugi.checkLearn(LOBBY, false, data, "Jin", "Goriki1", PARAMS)).toBe("TokugiNotLoaded")
		-- 記録を読めていなければ、ツリーに無い特技でも読み込みを待たせる
		expect(Tokugi.checkLearn(LOBBY, false, data, "Jin", "Nowhere", PARAMS)).toBe("TokugiNotLoaded")
	end
)

test(
	"補正は覚えた特技の分を能力値ごとにまとめ、ツリーに無い特技は数えない",
	function()
		local record = Tokugi.recordOf(dataOf(10, { "Ganken1", "Goriki1", "Goriki2", "Removed", "Teppeki1" }), "Jin")
		local modifiers = Tokugi.modifiersOf(record, TREE)
		expect(#modifiers).toBe(3)
		expect(modifiers[1]).toEqual({ stat = "MaxHealth", multiply = 1.04 })
		expect(modifiers[2].stat).toBe("Attack")
		expect(modifiers[2].multiply).toBeNear(1.03 * 1.05)
		expect(modifiers[2].add).toBe(nil)
		expect(modifiers[3]).toEqual({ stat = "Defense", add = 2 })
		expect(Tokugi.modifiersOf(Tokugi.recordOf(Tokugi.new(), "Jin"), TREE)).toEqual({})
	end
)

test("まとめた補正を足した能力値は、特技ごとに足した能力値と同じ", function()
	local base: Stats.Values = { MaxHealth = 300, Attack = 12, Defense = 10, WalkSpeed = 24, AttackSpeed = 1 }
	local record = Tokugi.recordOf(dataOf(10, { "Ganken1", "Goriki1", "Goriki2", "Teppeki1" }), "Jin")
	local each: { Stats.Modifier } = {
		{ stat = "Attack", multiply = 1.03 },
		{ stat = "MaxHealth", multiply = 1.04 },
		{ stat = "Attack", multiply = 1.05 },
		{ stat = "Defense", add = 2 },
	}
	local merged = Stats.compute(base, Tokugi.modifiersOf(record, TREE))
	local separate = Stats.compute(base, each)
	for _, name in Stats.names do
		expect((merged :: any)[name]).toBeNear((separate :: any)[name])
	end
	expect(merged.Defense).toBe(12)
end)

test("渡す巻物は撃破数を割って切り捨てた数（上限あり）に、勝ちなら上乗せ", function()
	expect(Tokugi.makimonoFor(0, false, PARAMS)).toBe(0)
	expect(Tokugi.makimonoFor(99, false, PARAMS)).toBe(0)
	expect(Tokugi.makimonoFor(250, false, PARAMS)).toBe(2)
	expect(Tokugi.makimonoFor(250, true, PARAMS)).toBe(5)
	expect(Tokugi.makimonoFor(0, true, PARAMS)).toBe(3)
	expect(Tokugi.makimonoFor(5000, false, PARAMS)).toBe(5)
	expect(Tokugi.makimonoFor(5000, true, PARAMS)).toBe(8)
end)

test("撃破数が負の値か数でないときは、撃破の分を 0 にする", function()
	expect(Tokugi.makimonoFor(-100, false, PARAMS)).toBe(0)
	expect(Tokugi.makimonoFor(0 / 0, true, PARAMS)).toBe(3)
end)

test(
	"画面に出すキャラクターは、選んでいるキャラクター、今のキャラクター、既定のキャラクターの順",
	function()
		expect(Tokugi.shownCharacter("KanaOni", "Torika")).toBe("KanaOni")
		expect(Tokugi.shownCharacter(nil, "Torika")).toBe("Torika")
		expect(Tokugi.shownCharacter(nil, nil)).toBe(Characters.DEFAULT_ID)
		-- 特技ツリーの無いキャラクターは飛ばす
		expect(Tokugi.shownCharacter("Hayate", "Nowhere")).toBe(Characters.DEFAULT_ID)
		expect(Tokugi.shownCharacter("Hayate", "Sekishusai")).toBe("Sekishusai")
	end
)

test("届いた TokugiState を読み、形が違えば nil", function()
	local state = Tokugi.normalizeState({ loaded = true, data = dataOf(3, { "Goriki1" }) }) :: Tokugi.State
	expect(state.loaded).toBe(true)
	expect(state.data.characters.Jin).toEqual({ makimono = 3, tokugi = { "Goriki1" } })
	local notLoaded = Tokugi.normalizeState({ loaded = "yes", data = {} }) :: Tokugi.State
	expect(notLoaded.loaded).toBe(false)
	expect(Tokugi.normalizeState(nil)).toBe(nil)
	expect(Tokugi.normalizeState({ loaded = true })).toBe(nil)
end)
