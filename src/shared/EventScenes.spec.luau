--!strict
local EventScenes = require("./EventScenes")
local Stages = require("./Stages")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

test("シーンの ID は表のキーと一致し、長さは正の秒数", function()
	for key, scene in EventScenes.definitions do
		expect(scene.id).toBe(key)
		expect(scene.duration > 0).toBe(true)
	end
end)

test(
	"ステージに登録したシーンは定義表にあり、ストーリーのステージには試験用のシーンを登録しない",
	function()
		for _, stage in Stages.definitions do
			for _, id in { stage.eventScenes.start, stage.eventScenes.victory, stage.eventScenes.defeat } do
				if id then
					local scene = EventScenes.get(id)
					expect(scene ~= nil).toBe(true)
					if not stage.shiken then
						expect((scene :: EventScenes.EventScene).shiken).toBe(nil)
					end
				end
			end
		end
	end
)

test("試験用のシーンがあり、ID が無いか定義に無いシーンは nil", function()
	local shiken = EventScenes.get("Shiken")
	expect(shiken ~= nil and shiken.shiken).toBe(true)
	expect(EventScenes.get(nil)).toBe(nil)
	expect(EventScenes.get("NoSuchScene")).toBe(nil)
end)
