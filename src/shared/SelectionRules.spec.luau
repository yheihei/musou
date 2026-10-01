--!strict
local RemoteSchema = require("./RemoteSchema")
local SelectionRules = require("./SelectionRules")
local Stages = require("./Stages")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

local LEADER: SelectionRules.Requester = { phase = "Lobby", isLeader = true, waiting = false }
local MEMBER: SelectionRules.Requester = { phase = "Lobby", isLeader = false, waiting = false }

local function at(requester: SelectionRules.Requester, changes: { [string]: any }): SelectionRules.Requester
	local copy = table.clone(requester) :: any
	for key, value in changes do
		copy[key] = value
	end
	return copy
end

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

local IGA1 = Stages.get("Iga1") :: Stages.Stage

-- 甲賀のストーリーの架空のステージ。酉花が NPC として登場する
local KOGA_TEST: Stages.Stage = {
	id = "KogaTest",
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
	local reject, mine = SelectionRules.applyHikei(MEMBER, "Kishinka", true, {}, {})
	expect(reject).toBe(nil)
	reject, mine = SelectionRules.applyHikei(MEMBER, "Fukuhei", true, mine, {})
	reject, mine = SelectionRules.applyHikei(MEMBER, "Daikatsu", true, mine, {})
	expect(reject).toBe(nil)
	expect(mine).toEqual({ "Kishinka", "Fukuhei", "Daikatsu" })
end)

test("上限を超える秘計は選べず、選んだ秘計はそのまま", function()
	local mine = { "Kishinka", "Fukuhei", "Daikatsu" }
	local reject, after = SelectionRules.applyHikei(MEMBER, "Rakuseki", true, mine, {})
	expect(reject).toBe("HikeiLimit")
	expect(after).toEqual({ "Kishinka", "Fukuhei", "Daikatsu" })
end)

test("他のメンバーが選んだ秘計は選べない", function()
	local reject, after = SelectionRules.applyHikei(MEMBER, "Rakuseki", true, { "Fukuhei" }, { "Rakuseki" })
	expect(reject).toBe("HikeiTaken")
	expect(after).toEqual({ "Fukuhei" })
end)

test("外した秘計は詰めて並べ、外した後は選び直せる", function()
	local reject, mine = SelectionRules.applyHikei(MEMBER, "Fukuhei", false, { "Kishinka", "Fukuhei", "Daikatsu" }, {})
	expect(reject).toBe(nil)
	expect(mine).toEqual({ "Kishinka", "Daikatsu" })
	reject, mine = SelectionRules.applyHikei(MEMBER, "Rakuseki", true, mine, {})
	expect(reject).toBe(nil)
	expect(mine).toEqual({ "Kishinka", "Daikatsu", "Rakuseki" })
end)

test(
	"選んでいる秘計をもう一度選んでも、選んでいない秘計を外しても変わらない",
	function()
		local _, again = SelectionRules.applyHikei(MEMBER, "Fukuhei", true, { "Fukuhei" }, {})
		expect(again).toEqual({ "Fukuhei" })
		local _, removed = SelectionRules.applyHikei(MEMBER, "Kishinka", false, { "Fukuhei" }, {})
		expect(removed).toEqual({ "Fukuhei" })
	end
)

test("存在しない秘計と、ロビー以外と待機中の人の秘計の選択は拒否する", function()
	expect((SelectionRules.applyHikei(MEMBER, "Musou", true, {}, {}))).toBe("UnknownHikei")
	expect((SelectionRules.applyHikei(at(MEMBER, { phase = "Battle" }), "Fukuhei", true, {}, {}))).toBe("NotLobby")
	expect((SelectionRules.applyHikei(at(MEMBER, { waiting = true }), "Fukuhei", false, {}, {}))).toBe("Waiting")
end)

test("秘計の選択は引数の秘計を書き換えない", function()
	local mine = { "Fukuhei" }
	SelectionRules.applyHikei(MEMBER, "Kishinka", true, mine, {})
	SelectionRules.applyHikei(MEMBER, "Fukuhei", false, mine, {})
	expect(mine).toEqual({ "Fukuhei" })
end)
