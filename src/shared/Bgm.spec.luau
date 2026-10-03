--!strict
local Bgm = require("./Bgm")
local Config = require("./Config")
local RemoteSchema = require("./RemoteSchema")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

-- 場面の名前を名前の順に返す
local function sortedScenes(): { string }
	local names: { string } = {}
	for _, scene in Bgm.scenes do
		table.insert(names, scene)
	end
	table.sort(names)
	return names
end

test("ロビー・イベントシーン・戦闘・勝利・敗北の場面ごとに曲がある", function()
	expect(Bgm.scenes).toEqual({ "Lobby", "EventScene", "Battle", "Victory", "Defeat" })
	local registered: { string } = {}
	for scene in Bgm.definitions do
		table.insert(registered, scene)
	end
	table.sort(registered)
	expect(registered).toEqual(sortedScenes())
end)

test(
	"どの曲もアセット ID・素材の名前・アーティスト・アルバム・長さ・配布元・使用条件を持つ",
	function()
		for _, scene in Bgm.scenes do
			local definition = Bgm.get(scene) :: Bgm.Definition
			expect(definition.id > 0 and definition.id == math.floor(definition.id)).toBe(true)
			expect(#definition.name > 0).toBe(true)
			expect(#definition.artist > 0).toBe(true)
			expect(#definition.album > 0).toBe(true)
			expect(definition.duration > 0).toBe(true)
			expect(#definition.source > 0).toBe(true)
			expect(#definition.license > 0).toBe(true)
		end
	end
)

test("アセット ID は場面ごとに違う", function()
	local seen: { [number]: string } = {}
	for _, scene in Bgm.scenes do
		local id = (Bgm.get(scene) :: Bgm.Definition).id
		expect(seen[id]).toBe(nil)
		seen[id] = scene
	end
end)

test("音量は場面ごとに Config に置き、0 より大きく 1 以下", function()
	local scenes: { string } = {}
	for scene, volume in Config.Bgm.Volume do
		table.insert(scenes, scene)
		expect(volume > 0 and volume <= 1).toBe(true)
	end
	table.sort(scenes)
	expect(scenes).toEqual(sortedScenes())
end)

test("切り替えのフェードの長さは 0 より長い", function()
	expect(Config.Bgm.FadeTime > 0).toBe(true)
end)

test("PartyState が届く前はロビーの曲", function()
	expect(Bgm.sceneFor(nil, true, nil)).toBe("Lobby")
	expect(Bgm.sceneFor(nil, false, nil)).toBe("Lobby")
end)

test("ロビー・イベントシーン・戦闘のフェーズは、同じ名前の場面の曲", function()
	expect(Bgm.sceneFor("Lobby", false, nil)).toBe("Lobby")
	expect(Bgm.sceneFor("EventScene", false, nil)).toBe("EventScene")
	expect(Bgm.sceneFor("Battle", false, nil)).toBe("Battle")
end)

test("リザルトのフェーズは、StageResult の勝敗で勝利か敗北の曲", function()
	expect(Bgm.sceneFor("Result", false, true)).toBe("Victory")
	expect(Bgm.sceneFor("Result", false, false)).toBe("Defeat")
end)

test("リザルトのフェーズで StageResult がまだ届いていなければ、今の曲を続ける", function()
	expect(Bgm.sceneFor("Result", false, nil)).toBe(nil)
end)

test("待機中の人は、どのフェーズでもロビーの曲", function()
	for _, phase in RemoteSchema.phases do
		expect(Bgm.sceneFor(phase, true, nil)).toBe("Lobby")
		expect(Bgm.sceneFor(phase, true, true)).toBe("Lobby")
		expect(Bgm.sceneFor(phase, true, false)).toBe("Lobby")
	end
end)

test("リザルト以外のフェーズでは、StageResult の勝敗を見ない", function()
	for _, phase in { "Lobby", "EventScene", "Battle" } :: { RemoteSchema.Phase } do
		expect(Bgm.sceneFor(phase, false, true)).toBe(phase)
		expect(Bgm.sceneFor(phase, false, false)).toBe(phase)
	end
end)

test("決めた場面には、どれも登録表の曲がある", function()
	for _, phase in RemoteSchema.phases do
		for _, waiting in { true, false } do
			for _, victory in { true, false } do
				local scene = Bgm.sceneFor(phase, waiting, victory) :: Bgm.Scene
				expect(Bgm.get(scene) ~= nil).toBe(true)
			end
		end
	end
end)
