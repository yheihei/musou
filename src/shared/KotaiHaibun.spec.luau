--!strict
local Config = require("./Config")
local KotaiHaibun = require("./KotaiHaibun")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

-- Config.luau の値を調整してもテストが揺れないよう、値を固定する
local PARAMS: KotaiHaibun.Params = {
	GroupDistance = 80,
	Reach = 120,
}

local function quotasOf(groups: { KotaiHaibun.Group }): { number }
	local result = {}
	for _, group in groups do
		table.insert(result, group.quota)
	end
	return result
end

local function sum(values: { number }): number
	local total = 0
	for _, value in values do
		total += value
	end
	return total
end

-- 4 隅に 300 ずつ離れた4人
local SCATTERED: { KotaiHaibun.Member } = {
	{ id = "A", x = 0, z = 0 },
	{ id = "B", x = 300, z = 0 },
	{ id = "C", x = 0, z = 300 },
	{ id = "D", x = 300, z = 300 },
}

test("離れた4人には、上限を均等に分ける", function()
	local groups = KotaiHaibun.allocate(SCATTERED, 40, nil, PARAMS)
	expect(#groups).toBe(4)
	expect(quotasOf(groups)).toEqual({ 10, 10, 10, 10 })
	expect(groups[1].members).toEqual({ "A" })
	expect(groups[1].demand).toBe(nil)
end)

test("1か所に集まった4人は、上限をまとめて使う", function()
	local members = {
		{ id = "A", x = 0, z = 0 },
		{ id = "B", x = 10, z = 0 },
		{ id = "C", x = 0, z = 15 },
		{ id = "D", x = -20, z = 5 },
	}
	local groups = KotaiHaibun.allocate(members, 40, nil, PARAMS)
	expect(#groups).toBe(1)
	expect(groups[1].members).toEqual({ "A", "B", "C", "D" })
	expect(groups[1].quota).toBe(40)
end)

test("3人と1人に分かれたら、人数の比で分ける", function()
	local members = {
		{ id = "A", x = 0, z = 0 },
		{ id = "B", x = 10, z = 0 },
		{ id = "C", x = 20, z = 0 },
		{ id = "D", x = 400, z = 0 },
	}
	local groups = KotaiHaibun.allocate(members, 40, nil, PARAMS)
	expect(quotasOf(groups)).toEqual({ 30, 10 })
end)

test("近いプレイヤーをたどってつなぐ（A と B、B と C が近ければ1つ）", function()
	local members = {
		{ id = "A", x = 0, z = 0 },
		{ id = "B", x = 70, z = 0 },
		{ id = "C", x = 140, z = 0 },
	}
	local groups = KotaiHaibun.group(members, 80)
	expect(#groups).toBe(1)
	expect(#KotaiHaibun.group(members, 60)).toBe(3)
end)

test("1人なら、上限をそのまま使う", function()
	local groups = KotaiHaibun.allocate({ { id = "A", x = 5, z = 5 } }, 40, nil, PARAMS)
	expect(quotasOf(groups)).toEqual({ 40 })
end)

test("端数は、切り捨てた残りの大きい順に足し、合計を上限にそろえる", function()
	local members = { { id = "A", x = 0, z = 0 }, { id = "B", x = 300, z = 0 }, { id = "C", x = 600, z = 0 } }
	local groups = KotaiHaibun.allocate(members, 40, nil, PARAMS)
	expect(quotasOf(groups)).toEqual({ 14, 13, 13 })
end)

test("近くに部隊のいないプレイヤーの分は、ほかのまとまりへ回す", function()
	local butai = {
		{ id = "b1", x = 10, z = 0, heisu = 50 },
		{ id = "b2", x = 300, z = 30, heisu = 50 },
	}
	-- C と D の近くには部隊がいない
	local groups = KotaiHaibun.allocate(SCATTERED, 40, butai, PARAMS)
	expect(quotasOf(groups)).toEqual({ 20, 20, 0, 0 })
	expect(groups[1].demand).toBe(50)
	expect(groups[1].butai).toEqual({ "b1" })
	expect(groups[3].demand).toBe(0)
end)

test("兵数が足りないまとまりの残りは、ほかのまとまりへ回す", function()
	local members = { { id = "A", x = 0, z = 0 }, { id = "B", x = 400, z = 0 } }
	local butai = {
		{ id = "b1", x = 0, z = 20, heisu = 5 },
		{ id = "b2", x = 400, z = 20, heisu = 100 },
	}
	local groups = KotaiHaibun.allocate(members, 40, butai, PARAMS)
	expect(quotasOf(groups)).toEqual({ 5, 35 })
end)

test("兵数の合計が上限より少なければ、合計は兵数の合計", function()
	local butai = {
		{ id = "b1", x = 0, z = 20, heisu = 3 },
		{ id = "b2", x = 300, z = 20, heisu = 4 },
	}
	local groups = KotaiHaibun.allocate(SCATTERED, 40, butai, PARAMS)
	expect(quotasOf(groups)).toEqual({ 3, 4, 0, 0 })
end)

test("どのプレイヤーからも Reach より遠い部隊と、兵数 0 の部隊は数えない", function()
	local butai = {
		{ id = "far", x = 150, z = 150, heisu = 100 },
		{ id = "empty", x = 0, z = 10, heisu = 0 },
	}
	local groups = KotaiHaibun.allocate({ { id = "A", x = 0, z = 0 } }, 40, butai, PARAMS)
	expect(groups[1].quota).toBe(0)
	expect(groups[1].butai).toEqual({})
end)

test("部隊は一番近いプレイヤーのまとまりに数える", function()
	local members = { { id = "A", x = 0, z = 0 }, { id = "B", x = 200, z = 0 } }
	local groups = KotaiHaibun.allocate(members, 40, { { id = "b1", x = 120, z = 0, heisu = 30 } }, PARAMS)
	expect(groups[1].butai).toEqual({})
	expect(groups[2].butai).toEqual({ "b1" })
	expect(quotasOf(groups)).toEqual({ 0, 30 })
end)

test(
	"整数に分ける: 重みの比で分け、上限に届いた分はほかへ回し、端数は残りの大きい順",
	function()
		expect(KotaiHaibun.split({ 1, 1, 1 }, { math.huge, math.huge, math.huge }, 40)).toEqual({ 14, 13, 13 })
		expect(KotaiHaibun.split({ 30, 10 }, { 30, 10 }, 20)).toEqual({ 15, 5 })
		expect(KotaiHaibun.split({ 2, 1 }, { 1, 100 }, 10)).toEqual({ 1, 9 })
		-- 上限の合計が total より小さければ、合計は上限の合計
		expect(KotaiHaibun.split({ 30, 10 }, { 30, 10 }, 100)).toEqual({ 30, 10 })
		-- 重みが 0 の要素には分けない
		expect(KotaiHaibun.split({ 1, 0, 1 }, { 5, 5, 5 }, 10)).toEqual({ 5, 0, 5 })
		expect(KotaiHaibun.split({}, {}, 10)).toEqual({})
		expect(KotaiHaibun.split({ 1 }, { 5 }, 0)).toEqual({ 0 })
	end
)

test("プレイヤーがいなければ、まとまりは無い", function()
	expect(#KotaiHaibun.allocate({}, 40, nil, PARAMS)).toBe(0)
end)

test("位置から一番近いプレイヤーのまとまりを引く", function()
	local groups = KotaiHaibun.allocate(SCATTERED, 40, nil, PARAMS)
	expect(KotaiHaibun.groupIndexAt(groups, SCATTERED, 290, 20)).toBe(2)
	expect(KotaiHaibun.groupIndexAt(groups, SCATTERED, 10, 280)).toBe(3)
	expect(KotaiHaibun.groupIndexAt({}, {}, 0, 0)).toBe(nil)
end)

test("どんな位置と兵数でも、合計は上限以下で、各まとまりは兵数を超えない", function()
	-- 種を固定した乱数（線形合同法）
	local value = 1009
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
		for index = 1, math.floor(nextNumber(6)) do
			table.insert(
				butai,
				{ id = `b{index}`, x = nextNumber(600), z = nextNumber(600), heisu = math.floor(nextNumber(30)) }
			)
		end
		local cap = math.floor(nextNumber(60))
		local groups = KotaiHaibun.allocate(members, cap, butai, PARAMS)
		local quotas = quotasOf(groups)
		local totalDemand = 0
		for _, group in groups do
			expect(group.quota >= 0 and group.quota == math.floor(group.quota)).toBe(true)
			expect(group.quota <= (group.demand :: number)).toBe(true)
			totalDemand += group.demand :: number
		end
		expect(sum(quotas)).toBe(math.min(cap, totalDemand))
		-- 兵数の制限なしなら、合計は上限
		expect(sum(quotasOf(KotaiHaibun.allocate(members, cap, nil, PARAMS)))).toBe(cap)
	end
end)

test("Config のまとまりの距離は、実体化圏の出現の半径より短い", function()
	local p = Config.KotaiHaibun
	expect(p.GroupDistance > 0).toBe(true)
	expect(p.GroupDistance < Config.Jittaikaken.AppearRadius).toBe(true)
	expect(p.Reach > 0).toBe(true)
end)
