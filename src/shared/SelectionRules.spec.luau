--!strict
local Characters = require("./Characters")
local Hikei = require("./Hikei")
local RemoteSchema = require("./RemoteSchema")
local SelectionRules = require("./SelectionRules")
local Stages = require("./Stages")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

local LEADER: SelectionRules.Requester = { phase = "Lobby", isLeader = true, waiting = false }
local MEMBER: SelectionRules.Requester = { phase = "Lobby", isLeader = false, waiting = false }
-- 秘計を全種類覚えた人の覚えた秘計
local ALL_HIKEI = Hikei.selectable()

local function at(requester: SelectionRules.Requester, changes: { [string]: any }): SelectionRules.Requester
	local copy = table.clone(requester) :: any
	for key, value in changes do
		copy[key] = value
	end
	return copy
end

test(
	"ロビーのフェーズの待機中でない人だけを受け付ける（リーダーかは見ない）",
	function()
		expect(SelectionRules.checkRequester(MEMBER)).toBe(nil)
		expect(SelectionRules.checkRequester(LEADER)).toBe(nil)
		expect(SelectionRules.checkRequester(at(MEMBER, { phase = "Battle" }))).toBe("NotLobby")
		expect(SelectionRules.checkRequester(at(MEMBER, { waiting = true }))).toBe("Waiting")
	end
)

test("リーダーはロビーで開放済みのステージを選べる", function()
	expect(SelectionRules.checkStage(LEADER, "Iga1", { "Iga1" })).toBe(nil)
end)

test("リーダー以外はステージを選べない", function()
	expect(SelectionRules.checkStage(MEMBER, "Iga1", { "Iga1" })).toBe("NotLeader")
end)

test("ロビー以外のフェーズではステージを選べない", function()
	for _, phase in { "EventScene", "Battle", "Result" } do
		expect(SelectionRules.checkStage(at(LEADER, { phase = phase }), "Iga1", { "Iga1" })).toBe("NotLobby")
	end
end)

test("待機中の人はステージを選べない", function()
	expect(SelectionRules.checkStage(at(LEADER, { waiting = true }), "Iga1", { "Iga1" })).toBe("Waiting")
end)

test("存在しないステージと、リーダーが開放していないステージは選べない", function()
	expect(SelectionRules.checkStage(LEADER, "Nowhere", { "Iga1", "Nowhere" })).toBe("UnknownStage")
	expect(SelectionRules.checkStage(LEADER, "Iga1", {})).toBe("StageLocked")
end)

test("ロビー以外の拒否はリーダーかどうかより先に返す", function()
	expect(SelectionRules.checkStage(at(MEMBER, { phase = "Battle" }), "Nowhere", {})).toBe("NotLobby")
end)

test("新しいリーダーが開放していないステージの選択は外す", function()
	expect(SelectionRules.keepsStage("Iga1", { "Iga1" })).toBe(true)
	expect(SelectionRules.keepsStage("Iga1", {})).toBe(false)
	expect(SelectionRules.keepsStage(nil, {})).toBe(true)
end)

test("ステージの選択の拒否の理由は Remote の拒否の理由に含まれる", function()
	for _, reason in { "NotLobby", "Waiting", "NotLeader", "UnknownStage", "StageLocked" } do
		expect(table.find(RemoteSchema.rejectReasons, reason :: any) ~= nil).toBe(true)
	end
end)

-- 定義表のストーリーのステージの ID をすべて返す（試験用ステージは入れない）
local function storyStageIds(): { string }
	local ids = {}
	for _, clan in Characters.clanIds do
		for _, stage in Stages.storyOf(clan) do
			table.insert(ids, stage.id)
		end
	end
	return ids
end

test("リーダーはロビーで、開放したステージのあるストーリーを選べる", function()
	expect(SelectionRules.checkStory(LEADER, "Iga", { "Iga1" })).toBe(nil)
end)

test("リーダー以外はストーリーを選べない", function()
	expect(SelectionRules.checkStory(MEMBER, "Iga", { "Iga1" })).toBe("NotLeader")
end)

test("ロビー以外のフェーズと待機中の人はストーリーを選べない", function()
	for _, phase in { "EventScene", "Battle", "Result" } do
		expect(SelectionRules.checkStory(at(LEADER, { phase = phase }), "Iga", { "Iga1" })).toBe("NotLobby")
	end
	expect(SelectionRules.checkStory(at(LEADER, { waiting = true }), "Iga", { "Iga1" })).toBe("Waiting")
end)

test("4つのクランのどれでもないストーリーは選べない", function()
	for _, id in { "Nowhere", "Iga1", "Test", "iga" } do
		expect(SelectionRules.checkStory(LEADER, id, storyStageIds())).toBe("UnknownStory")
	end
end)

test("リーダーが開放したステージの無いストーリーは、未開放として選べない", function()
	expect(SelectionRules.checkStory(LEADER, "Iga", {})).toBe("StoryLocked")
	-- 試験用ステージは伊賀のストーリーに数えない
	expect(SelectionRules.checkStory(LEADER, "Iga", { "Test" })).toBe("StoryLocked")
end)

test(
	"ステージがまだ無いストーリーは、全部のステージを開放していても準備中として選べない",
	function()
		local unlocked = storyStageIds()
		for _, clan in Characters.clanIds do
			local expected = if #Stages.storyOf(clan) == 0 then "StoryNotReady" else nil
			expect(SelectionRules.checkStory(LEADER, clan, unlocked)).toBe(expected)
		end
	end
)

test("新しいリーダーが開放したステージの無いストーリーの選択は外す", function()
	expect(SelectionRules.keepsStory("Iga", { "Iga1" })).toBe(true)
	expect(SelectionRules.keepsStory("Iga", {})).toBe(false)
	expect(SelectionRules.keepsStory(nil, {})).toBe(true)
end)

test(
	"ストーリーの選択の拒否の理由は制限ごとに別の値で、Remote の拒否の理由に含まれる",
	function()
		local reasons = { "NotLobby", "Waiting", "NotLeader", "UnknownStory", "StoryNotReady", "StoryLocked" }
		local seen = {}
		for _, reason in reasons do
			expect(seen[reason]).toBe(nil)
			seen[reason] = true
			expect(table.find(RemoteSchema.rejectReasons, reason :: any) ~= nil).toBe(true)
		end
	end
)

local IGA1 = Stages.get("Iga1") :: Stages.Stage

-- 甲賀のストーリーの架空のステージ。酉花が NPC として登場する
local KOGA_TEST: Stages.Stage = {
	id = "KogaTest",
	displayName = "甲賀の試し",
	clan = "Koga",
	order = 1,
	next = nil,
	tekigun = "Iga",
	shuryo = { mikatagun = nil, tekigun = nil },
	npcs = { "Torika" },
	kukaku = "KogaTest",
	eventScenes = {},
}

test("ステージを選んだ後は、ストーリーのクランの操作キャラクターを選べる", function()
	for _, id in { "Jin", "Torika", "Sekishusai", "KanaOni" } do
		expect(SelectionRules.checkCharacter(MEMBER, id, IGA1, {})).toBe(nil)
	end
	expect(SelectionRules.checkCharacter(LEADER, "Jin", IGA1, {})).toBe(nil)
end)

test("ステージを選ぶ前はキャラクターを選べない", function()
	expect(SelectionRules.checkCharacter(MEMBER, "Jin", nil, {})).toBe("StageNotSelected")
end)

test("Iga1 では首領のハヤテを選べない", function()
	expect(SelectionRules.checkCharacter(MEMBER, "Hayate", IGA1, {})).toBe("Shuryo")
end)

test("他のメンバーが選んだキャラクターは選べない", function()
	expect(SelectionRules.checkCharacter(MEMBER, "Jin", IGA1, { "Jin" })).toBe("CharacterTaken")
	expect(SelectionRules.checkCharacter(MEMBER, "Torika", IGA1, { "Jin" })).toBe(nil)
end)

test("ストーリーのクランに属さないキャラクターと、ステージの NPC は選べない", function()
	expect(SelectionRules.checkCharacter(MEMBER, "Jin", KOGA_TEST, {})).toBe("OtherClan")
	expect(SelectionRules.checkCharacter(MEMBER, "Torika", KOGA_TEST, {})).toBe("NpcInStage")
end)

test("首領でも NPC でもない、操作キャラクター以外は選べない", function()
	expect(SelectionRules.checkCharacter(MEMBER, "Hayate", KOGA_TEST, {})).toBe("NotPlayable")
end)

test("存在しないキャラクターは選べない", function()
	expect(SelectionRules.checkCharacter(MEMBER, "Nobody", IGA1, {})).toBe("UnknownCharacter")
end)

test("ロビー以外と待機中の人のキャラクターの選択は拒否する", function()
	expect(SelectionRules.checkCharacter(at(MEMBER, { phase = "Battle" }), "Jin", IGA1, {})).toBe("NotLobby")
	expect(SelectionRules.checkCharacter(at(MEMBER, { waiting = true }), "Jin", IGA1, {})).toBe("Waiting")
end)

test("ステージを変えたとき、新しいステージで選べないキャラクターは外す", function()
	expect(SelectionRules.keepsCharacter("Jin", IGA1)).toBe(true)
	expect(SelectionRules.keepsCharacter("Jin", KOGA_TEST)).toBe(false)
	expect(SelectionRules.keepsCharacter("Torika", KOGA_TEST)).toBe(false)
	expect(SelectionRules.keepsCharacter("Hayate", IGA1)).toBe(false)
end)

test(
	"ステージを外してストーリーを変えたとき、ストーリーのクランの操作キャラクター以外は外す",
	function()
		expect(SelectionRules.keepsCharacter("Jin", nil, "Iga")).toBe(true)
		expect(SelectionRules.keepsCharacter("Jin", nil, "Koga")).toBe(false)
		expect(SelectionRules.keepsCharacter("Hayate", nil, "Iga")).toBe(false)
		expect(SelectionRules.keepsCharacter("Nobody", nil, "Iga")).toBe(false)
	end
)

test("ストーリーもステージも選んでいなければ、キャラクターの選択は残す", function()
	expect(SelectionRules.keepsCharacter("Jin", nil, nil)).toBe(true)
end)

test(
	"画面には、選んでいるストーリーか、選んでいるステージのストーリーを出す",
	function()
		expect(SelectionRules.shownStory("Saika", KOGA_TEST, { "Iga1" })).toBe("Saika")
		expect(SelectionRules.shownStory(nil, KOGA_TEST, { "Iga1" })).toBe("Koga")
	end
)

test(
	"ストーリーもステージも選んでいなければ、リーダーが開放した最初のストーリーを画面に出す",
	function()
		expect(SelectionRules.shownStory(nil, nil, { "Iga1" })).toBe("Iga")
		expect(SelectionRules.shownStory(nil, nil, {})).toBe(Characters.clanIds[1])
	end
)

test(
	"キャラクターの選択の拒否の理由は制限ごとに別の値で、Remote の拒否の理由に含まれる",
	function()
		local reasons = {
			"StageNotSelected",
			"UnknownCharacter",
			"Shuryo",
			"NpcInStage",
			"NotPlayable",
			"OtherClan",
			"CharacterTaken",
		}
		local seen = {}
		for _, reason in reasons do
			expect(seen[reason]).toBe(nil)
			seen[reason] = true
			expect(table.find(RemoteSchema.rejectReasons, reason :: any) ~= nil).toBe(true)
		end
	end
)

test("秘計は選んだ順に上限まで選べる", function()
	local reject, mine = SelectionRules.applyHikei(MEMBER, "Kishinka", true, {}, {}, ALL_HIKEI)
	expect(reject).toBe(nil)
	reject, mine = SelectionRules.applyHikei(MEMBER, "Fukuhei", true, mine, {}, ALL_HIKEI)
	reject, mine = SelectionRules.applyHikei(MEMBER, "Daikatsu", true, mine, {}, ALL_HIKEI)
	expect(reject).toBe(nil)
	expect(mine).toEqual({ "Kishinka", "Fukuhei", "Daikatsu" })
end)

test("上限を超える秘計は選べず、選んだ秘計はそのまま", function()
	local mine = { "Kishinka", "Fukuhei", "Daikatsu" }
	local reject, after = SelectionRules.applyHikei(MEMBER, "Rakuseki", true, mine, {}, ALL_HIKEI)
	expect(reject).toBe("HikeiLimit")
	expect(after).toEqual({ "Kishinka", "Fukuhei", "Daikatsu" })
end)

test("他のメンバーが選んだ秘計は選べない", function()
	local reject, after = SelectionRules.applyHikei(MEMBER, "Rakuseki", true, { "Fukuhei" }, { "Rakuseki" }, ALL_HIKEI)
	expect(reject).toBe("HikeiTaken")
	expect(after).toEqual({ "Fukuhei" })
end)

test("外した秘計は詰めて並べ、外した後は選び直せる", function()
	local reject, mine = SelectionRules.applyHikei(
		MEMBER,
		"Fukuhei",
		false,
		{ "Kishinka", "Fukuhei", "Daikatsu" },
		{},
		ALL_HIKEI
	)
	expect(reject).toBe(nil)
	expect(mine).toEqual({ "Kishinka", "Daikatsu" })
	reject, mine = SelectionRules.applyHikei(MEMBER, "Rakuseki", true, mine, {}, ALL_HIKEI)
	expect(reject).toBe(nil)
	expect(mine).toEqual({ "Kishinka", "Daikatsu", "Rakuseki" })
end)

test(
	"選んでいる秘計をもう一度選んでも、選んでいない秘計を外しても変わらない",
	function()
		local _, again = SelectionRules.applyHikei(MEMBER, "Fukuhei", true, { "Fukuhei" }, {}, ALL_HIKEI)
		expect(again).toEqual({ "Fukuhei" })
		local _, removed = SelectionRules.applyHikei(MEMBER, "Kishinka", false, { "Fukuhei" }, {}, ALL_HIKEI)
		expect(removed).toEqual({ "Fukuhei" })
	end
)

test("存在しない秘計と、ロビー以外と待機中の人の秘計の選択は拒否する", function()
	expect((SelectionRules.applyHikei(MEMBER, "Musou", true, {}, {}, ALL_HIKEI))).toBe("UnknownHikei")
	expect((SelectionRules.applyHikei(at(MEMBER, { phase = "Battle" }), "Fukuhei", true, {}, {}, ALL_HIKEI))).toBe(
		"NotLobby"
	)
	expect((SelectionRules.applyHikei(at(MEMBER, { waiting = true }), "Fukuhei", false, {}, {}, ALL_HIKEI))).toBe(
		"Waiting"
	)
end)

test("秘計の選択は引数の秘計を書き換えない", function()
	local mine = { "Fukuhei" }
	SelectionRules.applyHikei(MEMBER, "Kishinka", true, mine, {}, ALL_HIKEI)
	SelectionRules.applyHikei(MEMBER, "Fukuhei", false, mine, {}, ALL_HIKEI)
	expect(mine).toEqual({ "Fukuhei" })
end)

test("覚えた秘計だけを選べ、覚えていない秘計は HikeiNotLearned で拒否する", function()
	local learned = { "Fukuhei", "Rakuseki", "Kishinka" }
	local reject, mine = SelectionRules.applyHikei(MEMBER, "Kishinka", true, {}, {}, learned)
	expect(reject).toBe(nil)
	reject, mine = SelectionRules.applyHikei(MEMBER, "Fukuhei", true, mine, {}, learned)
	reject, mine = SelectionRules.applyHikei(MEMBER, "Rakuseki", true, mine, {}, learned)
	expect(reject).toBe(nil)
	expect(mine).toEqual({ "Kishinka", "Fukuhei", "Rakuseki" })
	local rejected, after = SelectionRules.applyHikei(MEMBER, "Daikatsu", true, { "Kishinka" }, {}, learned)
	expect(rejected).toBe("HikeiNotLearned")
	expect(after).toEqual({ "Kishinka" })
end)

test(
	"覚えていない秘計は、ほかのメンバーが選んでいても上限に達していても HikeiNotLearned",
	function()
		local learned = { "Fukuhei", "Rakuseki", "Kishinka" }
		expect((SelectionRules.applyHikei(MEMBER, "Daikatsu", true, {}, { "Daikatsu" }, learned))).toBe(
			"HikeiNotLearned"
		)
		expect(
			(SelectionRules.applyHikei(MEMBER, "Daikatsu", true, { "Fukuhei", "Rakuseki", "Kishinka" }, {}, learned))
		).toBe("HikeiNotLearned")
		-- 覚えた秘計でも、ほかのメンバーが選んでいれば今までどおり HikeiTaken
		expect((SelectionRules.applyHikei(MEMBER, "Rakuseki", true, {}, { "Rakuseki" }, learned))).toBe("HikeiTaken")
	end
)

test(
	"熟練度の記録を読み終える前は選べず、外すのと選んでいる秘計の選び直しはできる",
	function()
		local reject, after = SelectionRules.applyHikei(MEMBER, "Fukuhei", true, {}, {}, nil)
		expect(reject).toBe("HikeiNotLoaded")
		expect(after).toEqual({})
		local _, removed = SelectionRules.applyHikei(MEMBER, "Fukuhei", false, { "Kishinka", "Fukuhei" }, {}, nil)
		expect(removed).toEqual({ "Kishinka" })
		local again, kept = SelectionRules.applyHikei(MEMBER, "Kishinka", true, { "Kishinka" }, {}, nil)
		expect(again).toBe(nil)
		expect(kept).toEqual({ "Kishinka" })
		-- 立場の拒否が先
		expect((SelectionRules.applyHikei(at(MEMBER, { phase = "Battle" }), "Fukuhei", true, {}, {}, nil))).toBe(
			"NotLobby"
		)
	end
)

test("覚えていない秘計の拒否の理由は Remote の拒否の理由に含まれる", function()
	for _, reason in { "HikeiNotLoaded", "HikeiNotLearned" } do
		expect(table.find(RemoteSchema.rejectReasons, reason :: any) ~= nil).toBe(true)
	end
end)

test(
	"リーダーは、開放済みのステージを選び、全員がキャラクターを選んだ後に出撃できる",
	function()
		expect(SelectionRules.checkShutsugeki(LEADER, "Iga1", { "Iga1" }, true)).toBe(nil)
	end
)

test("リーダー以外は出撃できない", function()
	expect(SelectionRules.checkShutsugeki(MEMBER, "Iga1", { "Iga1" }, true)).toBe("NotLeader")
end)

test("キャラクターを選んでいないメンバーがいると出撃できない", function()
	expect(SelectionRules.checkShutsugeki(LEADER, "Iga1", { "Iga1" }, false)).toBe("MembersNotReady")
end)

test("ステージを選ぶ前と、開放していないステージには出撃できない", function()
	expect(SelectionRules.checkShutsugeki(LEADER, nil, { "Iga1" }, true)).toBe("StageNotSelected")
	expect(SelectionRules.checkShutsugeki(LEADER, "Iga1", {}, true)).toBe("StageLocked")
	expect(SelectionRules.checkShutsugeki(LEADER, "Nowhere", { "Nowhere" }, true)).toBe("UnknownStage")
end)

test("ロビー以外のフェーズと待機中の人は出撃できない", function()
	expect(SelectionRules.checkShutsugeki(at(LEADER, { phase = "Battle" }), "Iga1", { "Iga1" }, true)).toBe("NotLobby")
	expect(SelectionRules.checkShutsugeki(at(LEADER, { waiting = true }), "Iga1", { "Iga1" }, true)).toBe("Waiting")
end)

test("出撃の拒否の理由は Remote の拒否の理由に含まれる", function()
	for _, reason in { "NotLeader", "StageNotSelected", "StageLocked", "UnknownStage", "MembersNotReady" } do
		expect(table.find(RemoteSchema.rejectReasons, reason :: any) ~= nil).toBe(true)
	end
end)
