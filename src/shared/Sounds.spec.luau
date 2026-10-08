--!strict
local Config = require("./Config")
local Gun = require("./Gun")
local Sounds = require("./Sounds")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

test(
	"攻撃の空振りと命中、チャージ攻撃、奥義、被弾、画面の決定と取り消しの効果音がある",
	function()
		for _, name in { "Swing", "Hit", "ChargeKogeki", "Ougi", "Hurt", "Confirm", "Cancel" } do
			expect(Sounds.get(name) ~= nil).toBe(true)
		end
	end
)

test(
	"ガード、緊急回避、ダウン、拠点の制圧と陥落、秘計の発動、カーソル移動の効果音がある",
	function()
		for _, name in { "Guard", "KinkyuKaihi", "Down", "Seiatsu", "Kanraku", "HikeiHatsudo", "Cursor" } do
			expect(Sounds.get(name) ~= nil).toBe(true)
		end
	end
)

test("登録表には、決めた場面の効果音だけがある", function()
	expect(Sounds.names()).toEqual({
		"Cancel",
		"ChargeKogeki",
		"Confirm",
		"Cursor",
		"Down",
		"Guard",
		"HikeiHatsudo",
		"Hit",
		"Hurt",
		"Kanraku",
		"KinkyuKaihi",
		"Ougi",
		"Seiatsu",
		"Swing",
	})
end)

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

test("自分の軍が拠点を制圧したら Seiatsu、自分の軍の拠点が陥落したら Kanraku", function()
	expect(Sounds.kyotenSceneFor("Tekigun", "Mikatagun", "Mikatagun")).toBe("Seiatsu")
	expect(Sounds.kyotenSceneFor("Mikatagun", "Tekigun", "Mikatagun")).toBe("Kanraku")
	-- 自分の軍が敵軍でも、自分の側から見て決める
	expect(Sounds.kyotenSceneFor("Mikatagun", "Tekigun", "Tekigun")).toBe("Seiatsu")
	expect(Sounds.kyotenSceneFor("Tekigun", "Mikatagun", "Tekigun")).toBe("Kanraku")
end)

test("拠点の軍が変わっていなければ鳴らさない", function()
	expect(Sounds.kyotenSceneFor("Mikatagun", "Mikatagun", "Mikatagun")).toBe(nil)
	expect(Sounds.kyotenSceneFor("Tekigun", "Tekigun", "Mikatagun")).toBe(nil)
end)

test("前か後の軍が届いていないか、軍の値でなければ鳴らさない", function()
	-- 出撃で拠点を作って、最初に軍が届いたとき
	expect(Sounds.kyotenSceneFor(nil, "Mikatagun", "Mikatagun")).toBe(nil)
	expect(Sounds.kyotenSceneFor(nil, "Tekigun", "Mikatagun")).toBe(nil)
	expect(Sounds.kyotenSceneFor("Tekigun", nil, "Mikatagun")).toBe(nil)
	expect(Sounds.kyotenSceneFor("Tekigun", "Butai", "Mikatagun")).toBe(nil)
	expect(Sounds.kyotenSceneFor(1, "Mikatagun", "Mikatagun")).toBe(nil)
end)

test("拠点の制圧で決めた効果音は、どれも登録表にある", function()
	for _, mine in Gun.list do
		for _, before in Gun.list do
			for _, after in Gun.list do
				local scene = Sounds.kyotenSceneFor(before, after, mine)
				if scene then
					expect(Sounds.get(scene) ~= nil).toBe(true)
				end
			end
		end
	end
end)
