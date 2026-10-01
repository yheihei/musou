--!strict
local RemoteSchema = require("./RemoteSchema")
local SelectionRules = require("./SelectionRules")
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
