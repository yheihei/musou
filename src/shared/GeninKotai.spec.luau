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

test("味方軍の目標は味方軍の上限で止まり、敵軍は全体の上限の残りを使う", function()
	local plan = GeninKotai.planBoth(
		{ { id = "m1", x = 0, z = 50, heisu = 40, present = 0 } },
		{ { id = "t1", x = 0, z = -50, heisu = 60, present = 0 } },
		ONE,
		40,
		10,
		PARAMS
	)
	expect(plan.targets.m1).toBe(10)
	expect(plan.targets.t1).toBe(30)
	expect(plan.mikatagunCap).toBe(10)
	expect(plan.tekigunCap).toBe(30)
	expect(plan.mikatagun.targets.m1).toBe(10)
	expect(plan.tekigun.targets.t1).toBe(30)
	expect(plan.distances.m1).toBeNear(50)
	expect(plan.distances.t1).toBeNear(50)
end)

test("近くに味方軍の部隊がいなければ、敵軍が全体の上限まで使う", function()
	local far = GeninKotai.planBoth(
		{ { id = "m1", x = 0, z = 300, heisu = 40, present = 0 } },
		{ { id = "t1", x = 0, z = -50, heisu = 60, present = 0 } },
		ONE,
		40,
		10,
		PARAMS
	)
	expect(far.targets.m1).toBe(0)
	expect(far.targets.t1).toBe(40)
	expect(far.tekigunCap).toBe(40)
	local none = GeninKotai.planBoth(
		{},
		{ { id = "t1", x = 0, z = -50, heisu = 60, present = 0 } },
		ONE,
		40,
		10,
		PARAMS
	)
	expect(none.targets.t1).toBe(40)
end)

test("味方軍の部隊の兵数が味方軍の上限より少なければ、残りを敵軍へ回す", function()
	local plan = GeninKotai.planBoth(
		{ { id = "m1", x = 0, z = 50, heisu = 4, present = 0 } },
		{ { id = "t1", x = 0, z = -50, heisu = 60, present = 0 } },
		ONE,
		40,
		10,
		PARAMS
	)
	expect(plan.targets.m1).toBe(4)
	expect(plan.targets.t1).toBe(36)
end)

test("両軍とも、部隊の目標は兵数を超えない", function()
	local plan = GeninKotai.planBoth(
		{ { id = "m1", x = 0, z = 50, heisu = 3, present = 0 } },
		{ { id = "t1", x = 0, z = -50, heisu = 12, present = 0 } },
		ONE,
		40,
		10,
		PARAMS
	)
	expect(plan.targets.m1).toBe(3)
	expect(plan.targets.t1).toBe(12)
end)

test(
	"味方軍の上限が全体の上限より大きくても、両軍の目標の合計は全体の上限を超えない",
	function()
		local plan = GeninKotai.planBoth(
			{ { id = "m1", x = 0, z = 50, heisu = 60, present = 0 } },
			{ { id = "t1", x = 0, z = -50, heisu = 60, present = 0 } },
			ONE,
			40,
			50,
			PARAMS
		)
		expect(plan.mikatagunCap).toBe(40)
		expect(plan.targets.m1).toBe(40)
		expect(plan.targets.t1).toBe(0)
		local zero = GeninKotai.planBoth(
			{ { id = "m1", x = 0, z = 50, heisu = 60, present = 0 } },
			{ { id = "t1", x = 0, z = -50, heisu = 60, present = 0 } },
			ONE,
			40,
			0,
			PARAMS
		)
		expect(zero.targets.m1).toBe(0)
		expect(zero.targets.t1).toBe(40)
	end
)

test("離れた2人には、両軍とも軍に回した上限を人数の比で分ける", function()
	local members = { { id = "A", x = 0, z = 0 }, { id = "B", x = 500, z = 0 } }
	local plan = GeninKotai.planBoth({
		{ id = "m1", x = 30, z = 0, heisu = 50, present = 0 },
		{ id = "m2", x = 530, z = 0, heisu = 50, present = 0 },
	}, {
		{ id = "t1", x = -30, z = 0, heisu = 50, present = 0 },
		{ id = "t2", x = 470, z = 0, heisu = 50, present = 0 },
	}, members, 40, 10, PARAMS)
	expect(plan.targets.m1).toBe(5)
	expect(plan.targets.m2).toBe(5)
	expect(plan.targets.t1).toBe(15)
	expect(plan.targets.t2).toBe(15)
end)

test("出ている味方軍の部隊は、消滅の半径より離れるまで残す", function()
	local plan = GeninKotai.planBoth(
		{ { id = "m1", x = 150, z = 0, heisu = 30, present = 6 } },
		{ { id = "t1", x = -50, z = 0, heisu = 60, present = 0 } },
		ONE,
		40,
		10,
		PARAMS
	)
	expect(plan.targets.m1).toBe(10)
	expect(plan.targets.t1).toBe(30)
end)

-- 種を固定した乱数（線形合同法）で、出撃メンバーと両軍の部隊と上限を作る
local function randomCases(
	seed: number,
	count: number,
	each: (
		members: { { id: string, x: number, z: number } },
		mikatagun: { GeninKotai.ButaiState },
		tekigun: { GeninKotai.ButaiState },
		cap: number,
		mikataCap: number
	) -> ()
)
	local value = seed
	local function nextNumber(max: number): number
		value = (value * 1103515245 + 12345) % 2147483648
		return value / 2147483648 * max
	end
	local function randomButai(prefix: string): { GeninKotai.ButaiState }
		local butai = {}
		for index = 1, math.floor(nextNumber(6)) do
			table.insert(butai, {
				id = `{prefix}{index}`,
				x = nextNumber(600),
				z = nextNumber(600),
				heisu = math.floor(nextNumber(40)),
				present = math.floor(nextNumber(5)),
			})
		end
		return butai
	end
	for _ = 1, count do
		local members = {}
		for index = 1, 1 + math.floor(nextNumber(4)) do
			table.insert(members, { id = `P{index}`, x = nextNumber(600), z = nextNumber(600) })
		end
		local mikatagun = randomButai("m")
		local tekigun = randomButai("t")
		each(members, mikatagun, tekigun, math.floor(nextNumber(60)), math.floor(nextNumber(20)))
	end
end

test(
	"どんな位置と兵数でも、両軍の目標の合計は全体の上限以下、味方軍は味方軍の上限以下",
	function()
		randomCases(82, 200, function(members, mikatagun, tekigun, cap, mikataCap)
			local plan = GeninKotai.planBoth(mikatagun, tekigun, members, cap, mikataCap, PARAMS)
			expect(sum(plan.targets) <= cap).toBe(true)
			expect(sum(plan.mikatagun.targets) <= mikataCap).toBe(true)
			expect(plan.tekigunCap).toBe(cap - sum(plan.mikatagun.targets))
			for _, list in { mikatagun, tekigun } do
				for _, entry in list do
					local target = plan.targets[entry.id]
					expect(target >= 0 and target <= entry.heisu and target == math.floor(target)).toBe(true)
				end
			end
		end)
	end
)

test(
	"味方軍の部隊がいなければ、敵軍の目標は敵軍だけで決めた計画（plan）と同じ",
	function()
		randomCases(76, 200, function(members, _mikatagun, tekigun, cap, mikataCap)
			local both = GeninKotai.planBoth({}, tekigun, members, cap, mikataCap, PARAMS)
			local alone = GeninKotai.plan(tekigun, members, cap, PARAMS)
			expect(both.tekigunCap).toBe(cap)
			expect(both.tekigun.targets).toEqual(alone.targets)
			expect(both.targets).toEqual(alone.targets)
		end)
	end
)

test("Config の上限は数十体で、出し入れの距離は実体化圏の中", function()
	local p = Config.GeninKotai
	expect(p.MaxKotai >= 10 and p.MaxKotai <= 100).toBe(true)
	expect(p.MaxPerTick >= 1).toBe(true)
	-- 出現の半径の縁で出すときは、視界の中でも出してよい距離（遠くて目立たない）
	expect(p.PopDistance < Config.Jittaikaken.AppearRadius).toBe(true)
end)

test("Config の味方軍の上限は全体の上限の内数で、敵軍の分が残る", function()
	local p = Config.GeninKotai
	expect(p.MikataMaxKotai >= 0 and p.MikataMaxKotai == math.floor(p.MikataMaxKotai)).toBe(true)
	expect(p.MikataMaxKotai < p.MaxKotai).toBe(true)
end)
