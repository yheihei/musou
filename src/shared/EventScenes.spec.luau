--!strict
local EventScenes = require("./EventScenes")
local Haichi = require("./Haichi")
local Serifu = require("./Serifu")
local Stages = require("./Stages")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

test("シーンの ID は表のキーと一致し、長さは正の秒数で、台本に誤りが無い", function()
	for key, scene in EventScenes.definitions do
		expect(scene.id).toBe(key)
		expect(EventScenes.durationOf(scene) > 0).toBe(true)
		expect(EventScenes.check(scene)).toEqual({})
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

local SAMPLE: EventScenes.EventScene = {
	id = "Sample",
	steps = {
		{ kind = "Camera", shot = "A" },
		{ kind = "Appear", yakusha = "Hayate" },
		{ kind = "Move", yakusha = "Hayate", x = 0, z = 5, time = 3 },
		{ kind = "Wait", time = 1 },
		{ kind = "Serifu", speaker = "Hayate", hyojo = "Tsujo", text = "行くぞ。" },
		{ kind = "Camera", shot = "B", time = 2 },
		{ kind = "Exit", yakusha = "Hayate" },
	},
}

test(
	"台詞と待ちだけが次の手順を待たせ、カメラと移動は動いている間に次へ進む",
	function()
		local times = {}
		for _, item in EventScenes.schedule(SAMPLE) do
			table.insert(times, item.at)
		end
		local line = Serifu.lineTime("行くぞ。")
		expect(times).toEqual({ 0, 0, 0, 0, 1, 1 + line, 1 + line })
	end
)

test("長さは、どの手順の動きと台詞も終わる時刻", function()
	local line = Serifu.lineTime("行くぞ。")
	-- 最後のカメラは 1 + 台詞 で始まり 2 秒かかる。移動は 0 から 3 秒
	expect(EventScenes.lengthOf(SAMPLE)).toBeNear(math.max(3, 1 + line + 2))
	expect(EventScenes.durationOf(SAMPLE)).toBeNear(EventScenes.lengthOf(SAMPLE))
	local fixed = table.clone(SAMPLE)
	fixed.duration = 30
	expect(EventScenes.durationOf(fixed)).toBe(30)
	expect(EventScenes.durationOf({ id = "Empty" }) > 0).toBe(true)
	expect(EventScenes.schedule({ id = "Empty" })).toEqual({})
end)

test("姿を出す役者とカメラのショットを、初めて出る順に並べる", function()
	local scene: EventScenes.EventScene = {
		id = "Order",
		steps = {
			{ kind = "Camera", shot = "B" },
			{ kind = "Appear", yakusha = "Player1" },
			{ kind = "Serifu", speaker = "Narrator", hyojo = "Tsujo", text = "語り" },
			{ kind = "Appear", yakusha = "Hayate" },
			{ kind = "Camera", shot = "A" },
			{ kind = "Camera", shot = "B" },
		},
	}
	expect(EventScenes.yakushaOf(scene)).toEqual({ "Player1", "Hayate" })
	expect(EventScenes.shotsOf(scene)).toEqual({ "B", "A" })
end)

test("出撃したプレイヤーの役者の名前と出撃した順番を行き来できる", function()
	expect(EventScenes.playerYakusha(2)).toBe("Player2")
	expect(EventScenes.playerIndexOf("Player4")).toBe(4)
	expect(EventScenes.playerIndexOf("Hayate")).toBe(nil)
	expect(EventScenes.playerIndexOf("Player0")).toBe(nil)
	expect(EventScenes.playerIndexOf("Player")).toBe(nil)
end)

test("台本の誤りを見つける", function()
	local scene: EventScenes.EventScene = {
		id = "Broken",
		steps = {
			{ kind = "Camera" },
			{ kind = "Move", yakusha = "Hayate", x = 0, z = 1, time = 1 },
			{ kind = "Appear", yakusha = "Hayate" },
			{ kind = "Move", yakusha = "Hayate", time = 1 },
			{ kind = "Serifu", speaker = "Hayate", hyojo = "Warai" :: any, text = "はは" },
			{ kind = "Wait" },
			{ kind = "Exit", yakusha = "Hayate" },
			{ kind = "Exit", yakusha = "Hayate" },
		},
	}
	expect(EventScenes.check(scene)).toEqual({
		"Broken の 1 番目の Camera にショットが無い",
		"Broken の 2 番目の Move の役者 Hayate は出ていない",
		"Broken の 4 番目の Move に歩く先か秒数が無い",
		"Broken の 5 番目の Serifu の表情 Warai は無い",
		"Broken の 6 番目の Wait に秒数が無い",
		"Broken の 8 番目の Exit の役者 Hayate は出ていない",
	})
end)

test(
	"試験用ステージの目印に、試験用のシーンのショットと役者がそろっている",
	function()
		local mejirushi = (Haichi.get("Test") :: Haichi.Haichi).shikenMejirushi :: Haichi.ShikenMejirushi
		local scenes = mejirushi.eventScene :: { [string]: Haichi.EventSceneIchi }
		local shiken = EventScenes.get("Shiken") :: EventScenes.EventScene
		local ichi = scenes.Shiken
		expect(ichi ~= nil).toBe(true)
		for _, shot in EventScenes.shotsOf(shiken) do
			expect(ichi.camera[shot] ~= nil).toBe(true)
		end
		for _, name in EventScenes.yakushaOf(shiken) do
			expect(ichi.yakusha[name] ~= nil).toBe(true)
		end
		for sceneId in scenes do
			expect(EventScenes.get(sceneId) ~= nil).toBe(true)
		end
	end
)
