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

local function leaderName(party: Party.Party): string?
	local leader = Party.leader(party)
	return if leader then leader.name else nil
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

test("プライベートサーバーでは、後から入った持ち主がリーダーになる", function()
	local party = Party.new()
	Party.setPrivateServerOwner(party, 2)
	Party.join(party, 1, "A")
	expect(leaderName(party)).toBe("A")
	Party.join(party, 2, "Owner")
	expect(leaderName(party)).toBe("Owner")
	expect(names(party.members)).toEqual({ "A", "Owner" })
	expect(Party.toState(party).leader).toBe(2)
end)

test(
	"プライベートサーバーでも、持ち主がいなければ一番早く入った人がリーダー",
	function()
		local party = Party.new()
		Party.setPrivateServerOwner(party, 99)
		Party.join(party, 1, "A")
		Party.join(party, 2, "B")
		expect(leaderName(party)).toBe("A")
		expect(Party.toState(party).leader).toBe(1)
	end
)

test(
	"持ち主が抜けると一番早く入った人に移り、ロビーで入り直すと持ち主に戻る",
	function()
		local party = Party.new()
		Party.setPrivateServerOwner(party, 1)
		Party.join(party, 1, "Owner")
		Party.join(party, 2, "B")
		Party.join(party, 3, "C")
		Party.leave(party, 1)
		expect(leaderName(party)).toBe("B")
		Party.join(party, 1, "Owner")
		expect(names(party.members)).toEqual({ "B", "C", "Owner" })
		expect(leaderName(party)).toBe("Owner")
	end
)

test(
	"出撃中に入った持ち主は待機中になり、戦闘とリザルトの間は出撃したリーダーのまま",
	function()
		local party = Party.new()
		Party.setPrivateServerOwner(party, 2)
		Party.join(party, 1, "A")
		Party.setPhase(party, "Battle")
		local owner = Party.join(party, 2, "Owner") :: Party.Member
		expect(owner.waiting).toBe(true)
		expect(leaderName(party)).toBe("A")
		expect(names(Party.activeMembers(party))).toEqual({ "A" })

		-- リザルトのリトライとロビーへ戻る操作は、出撃したリーダーが続ける
		Party.setPhase(party, "Result")
		expect(leaderName(party)).toBe("A")
		expect(Party.toState(party).leader).toBe(1)

		-- ロビーに戻って合流した時点で持ち主がリーダーになる
		Party.setPhase(party, "Lobby")
		expect(owner.waiting).toBe(false)
		expect(leaderName(party)).toBe("Owner")
		expect(names(Party.activeMembers(party))).toEqual({ "A", "Owner" })
	end
)

test(
	"出撃中に抜けて入り直した持ち主も、ロビーに戻るまでリーダーにならない",
	function()
		local party = Party.new()
		Party.setPrivateServerOwner(party, 1)
		Party.join(party, 1, "Owner")
		Party.join(party, 2, "B")
		Party.setPhase(party, "Battle")
		expect(leaderName(party)).toBe("Owner")
		Party.leave(party, 1)
		expect(leaderName(party)).toBe("B")
		Party.join(party, 1, "Owner")
		expect(leaderName(party)).toBe("B")
		Party.setPhase(party, "Lobby")
		expect(leaderName(party)).toBe("Owner")
	end
)

test(
	"出撃中に持ち主を決めても、待機中でない持ち主はそのままリーダーになる",
	function()
		local party = Party.new()
		Party.join(party, 1, "A")
		Party.join(party, 2, "B")
		Party.setPhase(party, "Battle")
		Party.setPrivateServerOwner(party, 2)
		expect(leaderName(party)).toBe("B")
	end
)

test("持ち主を外すと、一番早く入った人がリーダーに戻る", function()
	local party = Party.new()
	Party.setPrivateServerOwner(party, 2)
	Party.join(party, 1, "A")
	Party.join(party, 2, "Owner")
	expect(leaderName(party)).toBe("Owner")
	Party.setPrivateServerOwner(party, nil)
	expect(leaderName(party)).toBe("A")
end)

test(
	"プライベートサーバーでも、出撃中に入った人は持ち主でなくても待機中になる",
	function()
		local party = Party.new()
		Party.setPrivateServerOwner(party, 1)
		Party.join(party, 1, "Owner")
		Party.setPhase(party, "EventScene")
		local late = Party.join(party, 2, "B") :: Party.Member
		expect(late.waiting).toBe(true)
		expect(names(Party.activeMembers(party))).toEqual({ "Owner" })
		expect(leaderName(party)).toBe("Owner")
	end
)

test("プライベートサーバーでも上限人数を超えては入れない（持ち主も）", function()
	local party = Party.new()
	Party.setPrivateServerOwner(party, 99)
	for userId = 1, Config.Party.MaxMembers do
		expect(Party.join(party, userId, `P{userId}`) ~= nil).toBe(true)
	end
	expect(Party.join(party, 99, "Owner")).toBe(nil)
	expect(#party.members).toBe(Config.Party.MaxMembers)
	expect(leaderName(party)).toBe("P1")
end)
