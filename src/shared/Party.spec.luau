--!strict
local Config = require("./Config")
local Party = require("./Party")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

local function names(members: { Party.Member }): { string }
	local result = {}
	for _, member in members do
		table.insert(result, member.name)
	end
	return result
end

test("最初はロビーで、誰もいない", function()
	local party = Party.new()
	expect(party.phase).toBe("Lobby")
	expect(Party.leader(party)).toBe(nil)
end)

test("2人目が入ってもリーダーは1人目", function()
	local party = Party.new()
	Party.join(party, 1, "A")
	Party.join(party, 2, "B")
	expect((Party.leader(party) :: Party.Member).name).toBe("A")
	expect(names(party.members)).toEqual({ "A", "B" })
end)

test("リーダーが抜けると2番目に入った人がリーダーになる", function()
	local party = Party.new()
	Party.join(party, 1, "A")
	Party.join(party, 2, "B")
	Party.join(party, 3, "C")
	local left = Party.leave(party, 1)
	expect(left and left.name).toBe("A")
	expect((Party.leader(party) :: Party.Member).name).toBe("B")
end)

test("入り直した人は一番新しい人になる", function()
	local party = Party.new()
	Party.join(party, 1, "A")
	Party.join(party, 2, "B")
	Party.leave(party, 1)
	local rejoined = Party.join(party, 1, "A") :: Party.Member
	expect(rejoined.joinOrder).toBe(3)
	expect(names(party.members)).toEqual({ "B", "A" })
	expect((Party.leader(party) :: Party.Member).name).toBe("B")
end)

test("同じ人が二重に入ろうとしても1人のまま", function()
	local party = Party.new()
	Party.join(party, 1, "A")
	local again = Party.join(party, 1, "A") :: Party.Member
	expect(again.joinOrder).toBe(1)
	expect(#party.members).toBe(1)
end)

test("上限人数を超えては入れない", function()
	local party = Party.new()
	for userId = 1, Config.Party.MaxMembers do
		expect(Party.join(party, userId, `P{userId}`) ~= nil).toBe(true)
	end
	expect(Party.isFull(party)).toBe(true)
	expect(Party.join(party, 99, "Late")).toBe(nil)
	expect(#party.members).toBe(Config.Party.MaxMembers)
end)

test("いない人を外しても何も起きない", function()
	local party = Party.new()
	Party.join(party, 1, "A")
	expect(Party.leave(party, 42)).toBe(nil)
	expect(#party.members).toBe(1)
end)

test(
	"ロビー以外のフェーズで入った人は待機中になり、ロビーに戻ると合流する",
	function()
		local party = Party.new()
		Party.join(party, 1, "A")
		Party.setPhase(party, "Battle")
		local late = Party.join(party, 2, "B") :: Party.Member
		expect(late.waiting).toBe(true)
		expect((Party.get(party, 1) :: Party.Member).waiting).toBe(false)
		expect(names(Party.activeMembers(party))).toEqual({ "A" })

		Party.setPhase(party, "Result")
		expect(late.waiting).toBe(true)
		Party.setPhase(party, "Lobby")
		expect(late.waiting).toBe(false)
		expect(names(Party.activeMembers(party))).toEqual({ "A", "B" })
	end
)

test("イベントシーンの最中に入った人も待機中になる", function()
	local party = Party.new()
	Party.setPhase(party, "EventScene")
	expect((Party.join(party, 1, "A") :: Party.Member).waiting).toBe(true)
end)

test("PartyState の写しにフェーズ・リーダー・メンバーを載せる", function()
	local party = Party.new()
	Party.join(party, 10, "A")
	Party.setPhase(party, "Battle")
	Party.join(party, 20, "B")
	local state = Party.toState(party)
	expect(state.phase).toBe("Battle")
	expect(state.leader).toBe(10)
	expect(state.story).toBe(nil)
	expect(state.stage).toBe(nil)
	expect(state.unlockedStages).toEqual({})
	expect(state.members).toEqual({
		{ userId = 10, name = "A", joinOrder = 1, waiting = false, hikei = {} },
		{ userId = 20, name = "B", joinOrder = 2, waiting = true, hikei = {} },
	})
end)

test("ストーリー・ステージ・キャラクター・秘計は渡された値を載せる", function()
	local party = Party.new()
	Party.join(party, 10, "A")
	local state = Party.toState(party, {
		story = "Iga",
		stage = "Iga1",
		unlockedStages = { "Iga1" },
		characterOf = function(userId)
			return if userId == 10 then "Jin" else nil
		end,
		hikeiOf = function()
			return { "Fukuhei" }
		end,
	})
	expect(state.story).toBe("Iga")
	expect(state.stage).toBe("Iga1")
	expect(state.unlockedStages).toEqual({ "Iga1" })
	expect(state.members[1].character).toBe("Jin")
	expect(state.members[1].hikei).toEqual({ "Fukuhei" })
end)

test("誰もいなければリーダーは nil", function()
	local state = Party.toState(Party.new())
	expect(state.leader).toBe(nil)
	expect(state.members).toEqual({})
end)
