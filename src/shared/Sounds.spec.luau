--!strict
local Config = require("./Config")
local Sounds = require("./Sounds")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

test(
	"攻撃の空振りと命中、チャージ攻撃、奥義、被弾、画面の決定と取り消しの効果音がある",
	function()
		expect(Sounds.names()).toEqual({ "Cancel", "ChargeKogeki", "Confirm", "Hit", "Hurt", "Ougi", "Swing" })
	end
)

test("どの効果音もアセット ID・素材の名前・長さ・配布元・使用条件を持つ", function()
	for _, name in Sounds.names() do
		local definition = Sounds.get(name) :: Sounds.Definition
		expect(definition.id > 0 and definition.id == math.floor(definition.id)).toBe(true)
		expect(#definition.name > 0).toBe(true)
		expect(definition.duration > 0).toBe(true)
		expect(#definition.source > 0).toBe(true)
		expect(#definition.license > 0).toBe(true)
	end
end)

test("アセット ID は効果音ごとに違う", function()
	local seen: { [number]: string } = {}
	for _, name in Sounds.names() do
		local id = (Sounds.get(name) :: Sounds.Definition).id
		expect(seen[id]).toBe(nil)
		seen[id] = name
	end
end)

test("音量は登録表の効果音ごとに Config に置き、0 より大きく 1 以下", function()
	local volumes: { string } = {}
	for name, volume in Config.Sound.Volume do
		table.insert(volumes, name)
		expect(volume > 0 and volume <= 1).toBe(true)
	end
	table.sort(volumes)
	expect(volumes).toEqual(Sounds.names())
end)

test(
	"聞こえる距離は、小さくなり始める距離より聞こえなくなる距離の方が遠い",
	function()
		expect(Config.Sound.RollOffMinDistance > 0).toBe(true)
		expect(Config.Sound.RollOffMaxDistance > Config.Sound.RollOffMinDistance).toBe(true)
	end
)
