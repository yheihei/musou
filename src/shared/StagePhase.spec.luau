--!strict
local RemoteSchema = require("./RemoteSchema")
local StagePhase = require("./StagePhase")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

test("出撃から順に進むと、リザルトを経てロビーに戻る", function()
	local phase: StagePhase.Phase = "Lobby"
	local visited = {}
	for _, event in { "Shutsugeki", "SceneEnd", "Finish", "SceneEnd", "ReturnToLobby" } :: { StagePhase.Event } do
		phase = StagePhase.next(phase, event) :: StagePhase.Phase
		table.insert(visited, phase)
	end
	expect(visited).toEqual({ "StartScene", "Battle", "EndScene", "Result", "Lobby" })
end)

test("出撃はロビーでだけ受け付ける", function()
	expect(StagePhase.next("Lobby", "Shutsugeki")).toBe("StartScene")
	for _, phase in { "StartScene", "Battle", "EndScene", "Result" } :: { StagePhase.Phase } do
		expect(StagePhase.next(phase, "Shutsugeki")).toBe(nil)
	end
end)

test("決着は戦闘でだけ、ロビーへ戻るのはリザルトでだけ受け付ける", function()
	for _, phase in StagePhase.phases do
		expect(StagePhase.next(phase, "Finish") ~= nil).toBe(phase == "Battle")
		expect(StagePhase.next(phase, "ReturnToLobby") ~= nil).toBe(phase == "Result")
	end
end)

test("イベントシーンの終わりは、開始なら戦闘へ、終了ならリザルトへ進む", function()
	expect(StagePhase.next("StartScene", "SceneEnd")).toBe("Battle")
	expect(StagePhase.next("EndScene", "SceneEnd")).toBe("Result")
	expect(StagePhase.next("Lobby", "SceneEnd")).toBe(nil)
	expect(StagePhase.next("Battle", "SceneEnd")).toBe(nil)
	expect(StagePhase.next("Result", "SceneEnd")).toBe(nil)
end)

test("全員が抜けたら、ロビー以外のどのフェーズからもロビーへ戻る", function()
	expect(StagePhase.next("Lobby", "Abort")).toBe(nil)
	for _, phase in { "StartScene", "Battle", "EndScene", "Result" } :: { StagePhase.Phase } do
		expect(StagePhase.next(phase, "Abort")).toBe("Lobby")
	end
end)

test("PartyState には開始と終了のイベントシーンを EventScene として載せる", function()
	expect(StagePhase.toPartyPhase("Lobby")).toBe("Lobby")
	expect(StagePhase.toPartyPhase("StartScene")).toBe("EventScene")
	expect(StagePhase.toPartyPhase("Battle")).toBe("Battle")
	expect(StagePhase.toPartyPhase("EndScene")).toBe("EventScene")
	expect(StagePhase.toPartyPhase("Result")).toBe("Result")
	for _, phase in StagePhase.phases do
		expect(table.find(RemoteSchema.phases, StagePhase.toPartyPhase(phase)) ~= nil).toBe(true)
	end
end)

test("開始のイベントシーンのフェーズでは、ステージの開始のシーンを流す", function()
	local scenes = { start = "A", victory = "B", defeat = "C" }
	expect(StagePhase.sceneIdFor(scenes, "StartScene")).toBe("A")
	expect(StagePhase.sceneIdFor({}, "StartScene")).toBe(nil)
end)

test("終了のイベントシーンのフェーズでは、勝敗に合ったシーンを流す", function()
	local scenes = { start = "A", victory = "B", defeat = "C" }
	expect(StagePhase.sceneIdFor(scenes, "EndScene", true)).toBe("B")
	expect(StagePhase.sceneIdFor(scenes, "EndScene", false)).toBe("C")
end)

test("敗北のシーンが無ければ、敗北では何も流さずリザルトへ直行する", function()
	local scenes = { start = "A", victory = "B" }
	expect(StagePhase.sceneIdFor(scenes, "EndScene", false)).toBe(nil)
	expect(StagePhase.sceneIdFor(scenes, "EndScene", true)).toBe("B")
end)

test("イベントシーンのフェーズでなければ何も流さない", function()
	local scenes = { start = "A", victory = "B", defeat = "C" }
	for _, phase in { "Lobby", "Battle", "Result" } :: { StagePhase.Phase } do
		expect(StagePhase.sceneIdFor(scenes, phase, true)).toBe(nil)
	end
end)

test("リトライはリザルトでだけ受け付け、ロビーへ戻る", function()
	for _, phase in StagePhase.phases do
		local next = StagePhase.next(phase, "Retry")
		expect(next ~= nil).toBe(phase == "Result")
		if next then
			expect(next).toBe("Lobby")
		end
	end
end)
