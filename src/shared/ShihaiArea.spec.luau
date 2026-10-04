--!strict
local Heitansen = require("./Heitansen")
local ShihaiArea = require("./ShihaiArea")
local Stats = require("./Stats")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

-- Config.luau の値を調整してもテストが揺れないよう、半径と倍率を固定する
local PARAMS: ShihaiArea.Params = {
	Radius = 100,
	Push = 1.5,
	Attack = 1.2,
	Defense = 1.3,
}

local function kyoten(id: string, gun: any, x: number, z: number, connected: boolean?): ShihaiArea.Kyoten
	return { id = id, gun = gun, x = x, z = z, connected = if connected == nil then true else connected }
end

test(
	"兵站線につながった拠点の中心から半径以内は、その拠点の軍の支配エリア",
	function()
		local list = { kyoten("A", "Mikatagun", 0, 0) }
		expect(ShihaiArea.gunAt(list, 0, 0, PARAMS)).toBe("Mikatagun")
		expect(ShihaiArea.gunAt(list, 60, 80, PARAMS)).toBe("Mikatagun")
		expect(ShihaiArea.gunAt(list, 61, 80, PARAMS)).toBe(nil)
	end
)

test("孤立した拠点は支配エリアを持たない", function()
	local list = { kyoten("A", "Tekigun", 0, 0, false) }
	expect(ShihaiArea.gunAt(list, 0, 0, PARAMS)).toBe(nil)
	expect(#ShihaiArea.sourcesOf(list)).toBe(0)
end)

test(
	"孤立した拠点の周りでも、ほかのつながった拠点の半径の中ならその拠点の軍になる",
	function()
		local list = {
			kyoten("Near", "Tekigun", 0, 0, false),
			kyoten("Far", "Mikatagun", 90, 0),
		}
		expect(ShihaiArea.kyotenAt(list, 10, 0, PARAMS)).toEqual(list[2])
		expect(ShihaiArea.gunAt(list, 10, 0, PARAMS)).toBe("Mikatagun")
	end
)

test("重なる地点は、中心が一番近い拠点の軍のもの", function()
	local list = {
		kyoten("Mikata", "Mikatagun", 0, 0),
		kyoten("Teki", "Tekigun", 150, 0),
	}
	expect(ShihaiArea.gunAt(list, 70, 0, PARAMS)).toBe("Mikatagun")
	expect(ShihaiArea.gunAt(list, 80, 0, PARAMS)).toBe("Tekigun")
end)

test("中心からの距離が同じなら、一覧の先の拠点の軍", function()
	local list = {
		kyoten("Teki", "Tekigun", 100, 0),
		kyoten("Mikata", "Mikatagun", -100, 0),
	}
	expect(ShihaiArea.gunAt(list, 0, 0, PARAMS)).toBe("Tekigun")
end)

test("どちらの軍にも属さない拠点は支配エリアを持たない", function()
	local list = { kyoten("A", nil, 0, 0) }
	expect(ShihaiArea.gunAt(list, 0, 0, PARAMS)).toBe(nil)
end)

-- 兵站線の計算の結果から、支配エリアの判定に渡す拠点を作る
local function fromHeitansen(kyotenList: { Heitansen.Kyoten }, tsunagari: { Heitansen.Tsunagari }, positions)
	local result = Heitansen.compute(kyotenList, tsunagari)
	local list = {}
	for _, item in kyotenList do
		local gun = item.gun :: any
		local position = positions[item.id]
		table.insert(list, kyoten(item.id, gun, position.x, position.z, result[gun].connected[item.id] == true))
	end
	return list
end

test("兵站線が切れた先の拠点は支配エリアを失い、兵糧庫は保つ", function()
	local positions = {
		Honjin = { x = 0, z = 0 },
		Mae = { x = 300, z = 0 },
		Saki = { x = 600, z = 0 },
	}
	local tsunagari: { Heitansen.Tsunagari } = {
		{ kyotenA = "Honjin", kyotenB = "Mae", blocked = { Mikatagun = true } },
		{ kyotenA = "Mae", kyotenB = "Saki" },
	}
	local cut = fromHeitansen({
		{ id = "Honjin", gun = "Mikatagun", honjin = true },
		{ id = "Mae", gun = "Mikatagun", honjin = false },
		{ id = "Saki", gun = "Mikatagun", honjin = false },
	}, tsunagari, positions)
	expect(ShihaiArea.gunAt(cut, 0, 0, PARAMS)).toBe("Mikatagun")
	expect(ShihaiArea.gunAt(cut, 300, 0, PARAMS)).toBe(nil)
	expect(ShihaiArea.gunAt(cut, 600, 0, PARAMS)).toBe(nil)

	local hyoroko = fromHeitansen({
		{ id = "Honjin", gun = "Mikatagun", honjin = true },
		{ id = "Mae", gun = "Mikatagun", honjin = false, neverIsolated = true },
		{ id = "Saki", gun = "Mikatagun", honjin = false },
	}, tsunagari, positions)
	expect(ShihaiArea.gunAt(hyoroko, 300, 0, PARAMS)).toBe("Mikatagun")
	-- 兵糧庫から先へは兵站線を延ばさない
	expect(ShihaiArea.gunAt(hyoroko, 600, 0, PARAMS)).toBe(nil)
end)

test("部隊の押す力の倍率は、自分の軍の支配エリアの中だけ上がる", function()
	expect(ShihaiArea.pushOf("Mikatagun", "Mikatagun", PARAMS)).toBe(1.5)
	expect(ShihaiArea.pushOf("Tekigun", "Mikatagun", PARAMS)).toBe(1)
	expect(ShihaiArea.pushOf(nil, "Tekigun", PARAMS)).toBe(1)
end)

test("上忍と首領は支配エリアの中で攻撃と防御だけが上がる", function()
	local base: Stats.Values = { MaxHealth = 600, Attack = 10, Defense = 20, WalkSpeed = 14, AttackSpeed = 1 }
	local inside = Stats.compute(base, ShihaiArea.modifiersOf(true, PARAMS))
	expect(inside.Attack).toBeNear(12)
	expect(inside.Defense).toBeNear(26)
	expect(inside.MaxHealth).toBe(600)
	expect(inside.WalkSpeed).toBe(14)
	expect(ShihaiArea.modifiersOf(false, PARAMS)).toEqual({})
end)
