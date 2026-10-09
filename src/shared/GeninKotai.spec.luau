--!strict
local Config = require("./Config")
local GeninKotai = require("./GeninKotai")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

-- Config.luau の値を調整してもテストが揺れないよう、半径と距離を固定する
local PARAMS: GeninKotai.Params = {
	jittaikaken = {
		AppearRadius = 120,
		DisappearRadius = 160,
		Interval = 0.25,
		HomeRadius = 6,
		CorpseLifetime = 3,
	},
	haibun = { GroupDistance = 80 },
}

local ONE = { { id = "A", x = 0, z = 0 } }

local function sum(targets: { [string]: number }): number
	local total = 0
	for _, count in targets do
		total += count
	end
	return total
end

test("近づいた部隊の下忍を、上限まで個体として出す", function()
	local plan = GeninKotai.plan({ { id = "b1", x = 50, z = 0, heisu = 60, present = 0 } }, ONE, 40, PARAMS)
	expect(plan.targets.b1).toBe(40)
	expect(plan.distances.b1).toBeNear(50)
end)

test("個体の数は部隊の兵数を超えない", function()
	local plan = GeninKotai.plan({ { id = "b1", x = 50, z = 0, heisu = 12, present = 0 } }, ONE, 40, PARAMS)
	expect(plan.targets.b1).toBe(12)
end)

test("出現の半径の外の部隊は出さない", function()
	local plan = GeninKotai.plan({ { id = "b1", x = 121, z = 0, heisu = 30, present = 0 } }, ONE, 40, PARAMS)
	expect(plan.targets.b1).toBe(0)
end)

test("出ている部隊は、消滅の半径より離れるまで残し、離れたら 0 に戻す", function()
	local inside = GeninKotai.plan({ { id = "b1", x = 150, z = 0, heisu = 30, present = 8 } }, ONE, 40, PARAMS)
	expect(inside.targets.b1).toBe(30)
	local outside = GeninKotai.plan({ { id = "b1", x = 161, z = 0, heisu = 30, present = 8 } }, ONE, 40, PARAMS)
	expect(outside.targets.b1).toBe(0)
end)

test("半径の間を行き来しても、出入りを繰り返さない", function()
	local present = 0
	local changes = 0
	-- 外から近づいて 100 で出し、半径の間（110〜150）を往復してから 170 で離れる
	for _, x in { 170, 130, 100, 110, 150, 110, 150, 170 } do
		local plan = GeninKotai.plan({ { id = "b1", x = x, z = 0, heisu = 30, present = present } }, ONE, 40, PARAMS)
		local next = plan.targets.b1
		if (next > 0) ~= (present > 0) then
			changes += 1
		end
		present = next
	end
	expect(changes).toBe(2)
	expect(present).toBe(0)
end)

test("1人の近くの2部隊には、上限を兵数の比で分ける", function()
	local plan = GeninKotai.plan({
		{ id = "b1", x = 30, z = 0, heisu = 30, present = 0 },
		{ id = "b2", x = -30, z = 0, heisu = 10, present = 0 },
	}, ONE, 20, PARAMS)
	expect(plan.targets.b1).toBe(15)
	expect(plan.targets.b2).toBe(5)
end)

test("離れた2人には、上限を人数の比で分ける", function()
	local members = { { id = "A", x = 0, z = 0 }, { id = "B", x = 500, z = 0 } }
	local plan = GeninKotai.plan({
		{ id = "b1", x = 30, z = 0, heisu = 50, present = 0 },
		{ id = "b2", x = 530, z = 0, heisu = 50, present = 0 },
	}, members, 40, PARAMS)
	expect(plan.targets.b1).toBe(20)
	expect(plan.targets.b2).toBe(20)
end)

test("近くに部隊のいない人の分は、ほかの人の近くの部隊へ回す", function()
	local members = { { id = "A", x = 0, z = 0 }, { id = "B", x = 500, z = 0 } }
	local plan = GeninKotai.plan({ { id = "b1", x = 30, z = 0, heisu = 50, present = 0 } }, members, 40, PARAMS)
	expect(plan.targets.b1).toBe(40)
end)

test("兵数 0 の部隊と、メンバーがいないときは出さない", function()
	local plan = GeninKotai.plan({ { id = "b1", x = 10, z = 0, heisu = 0, present = 0 } }, ONE, 40, PARAMS)
	expect(plan.targets.b1).toBe(0)
	local nobody = GeninKotai.plan({ { id = "b1", x = 10, z = 0, heisu = 30, present = 5 } }, {}, 40, PARAMS)
	expect(nobody.targets.b1).toBe(0)
	expect(nobody.distances.b1).toBe(nil)
end)

test("どんな位置と兵数でも、目標の合計は上限以下で、各部隊は兵数以下", function()
	-- 種を固定した乱数（線形合同法）
	local value = 76
	local function nextNumber(max: number): number
		value = (value * 1103515245 + 12345) % 2147483648
		return value / 2147483648 * max
	end
	for _ = 1, 200 do
		local members = {}
		for index = 1, 1 + math.floor(nextNumber(4)) do
			table.insert(members, { id = `P{index}`, x = nextNumber(600), z = nextNumber(600) })
		end
		local butai = {}
		for index = 1, math.floor(nextNumber(8)) do
			table.insert(butai, {
				id = `b{index}`,
				x = nextNumber(600),
				z = nextNumber(600),
				heisu = math.floor(nextNumber(40)),
				present = math.floor(nextNumber(5)),
			})
		end
		local cap = math.floor(nextNumber(60))
		local plan = GeninKotai.plan(butai, members, cap, PARAMS)
		expect(sum(plan.targets) <= cap).toBe(true)
		for _, entry in butai do
			local target = plan.targets[entry.id]
			expect(target >= 0 and target <= entry.heisu and target == math.floor(target)).toBe(true)
		end
	end
end)

test("Config の上限は数十体で、出し入れの距離は実体化圏の中", function()
	local p = Config.GeninKotai
	expect(p.MaxKotai >= 10 and p.MaxKotai <= 100).toBe(true)
	expect(p.MaxPerTick >= 1).toBe(true)
	-- 出現の半径の縁で出すときは、視界の中でも出してよい距離（遠くて目立たない）
	expect(p.PopDistance < Config.Jittaikaken.AppearRadius).toBe(true)
end)
