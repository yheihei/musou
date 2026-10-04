--!strict
local Fukuhei = require("./Fukuhei")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

-- Config.luau の値を調整してもテストが揺れないよう、距離を固定する
local PARAMS: Fukuhei.Params = {
	Heisu = 20,
	KishuRadius = 40,
	KishuShiki = 15,
}

local function unit(id: string, gun: any, x: number, z: number, heisu: number?, fukuhei: boolean?): Fukuhei.Unit
	return { id = id, gun = gun, position = { x = x, z = z }, heisu = heisu or 30, fukuhei = fukuhei }
end

local MIKATA_FUKUHEI = unit("Fukuhei1", "Mikatagun", 0, 0, 20, true)

test("半径の中に来た相手の部隊のうち、一番近い部隊を奇襲する", function()
	local units = {
		unit("Far", "Tekigun", 35, 0),
		unit("Near", "Tekigun", 0, 20),
		unit("Outside", "Tekigun", 41, 0),
	}
	local kishu, target = Fukuhei.kishuOf(MIKATA_FUKUHEI, units, {}, PARAMS)
	expect(kishu).toBe(true)
	expect(target).toBe("Near")
end)

test(
	"味方の部隊、潜んでいる相手の伏兵部隊、兵数の無い部隊、半径の外の部隊では奇襲しない",
	function()
		local units = {
			unit("Ally", "Mikatagun", 5, 0),
			unit("HiddenTeki", "Tekigun", 5, 0, 20, true),
			unit("Empty", "Tekigun", 5, 0, 0),
			unit("Outside", "Tekigun", 50, 0),
		}
		local kishu, target = Fukuhei.kishuOf(MIKATA_FUKUHEI, units, {}, PARAMS)
		expect(kishu).toBe(false)
		expect(target).toBe(nil)
	end
)

test("味方軍の伏兵部隊は、プレイヤーが近づいても奇襲しない", function()
	local kishu = Fukuhei.kishuOf(MIKATA_FUKUHEI, {}, { { x = 1, z = 1 } }, PARAMS)
	expect(kishu).toBe(false)
end)

test(
	"敵軍の伏兵部隊は、近づいたプレイヤーを奇襲する（交戦する部隊は無い）",
	function()
		local teki = unit("Fukuhei2", "Tekigun", 0, 0, 20, true)
		local kishu, target = Fukuhei.kishuOf(teki, {}, { { x = 100, z = 0 }, { x = 30, z = 10 } }, PARAMS)
		expect(kishu).toBe(true)
		expect(target).toBe(nil)
		local far = Fukuhei.kishuOf(teki, {}, { { x = 100, z = 0 } }, PARAMS)
		expect(far).toBe(false)
	end
)

test("敵軍の伏兵部隊は、プレイヤーより相手の部隊を交戦の相手にする", function()
	local teki = unit("Fukuhei2", "Tekigun", 0, 0, 20, true)
	local kishu, target = Fukuhei.kishuOf(teki, { unit("Mikata1", "Mikatagun", 30, 0) }, { { x = 1, z = 0 } }, PARAMS)
	expect(kishu).toBe(true)
	expect(target).toBe("Mikata1")
end)
