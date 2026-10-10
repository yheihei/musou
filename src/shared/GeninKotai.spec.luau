--!strict
local Config = require("./Config")
local GeninKotai = require("./GeninKotai")
local Gun = require("./Gun")
local Jittaikaken = require("./Jittaikaken")
local KotaiHaibun = require("./KotaiHaibun")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

-- Config.luau の値を調整してもテストが揺れないよう、半径・距離・上限・割合を固定する
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
local CAP = 40
local RATE = 0.25
local STEP = 2
local MAX_PER_TICK = 8

local ONE = { { id = "A", x = 0, z = 0 } }

local function teki(id: string, x: number, z: number, heisu: number, present: number?): GeninKotai.ButaiState
	return { id = id, gun = "Tekigun", x = x, z = z, heisu = heisu, present = present or 0 }
end

local function mikata(id: string, x: number, z: number, heisu: number, present: number?): GeninKotai.ButaiState
	return { id = id, gun = "Mikatagun", x = x, z = z, heisu = heisu, present = present or 0 }
end

local function sum(values: { [any]: number }): number
	local total = 0
	for _, value in values do
		total += value
	end
	return total
end

-- 両軍の部隊ごとの目標。味方軍は計画の目標、敵軍は味方軍の押さえている数 held（省くと 0）で決めた目標
local function targetsOf(plan: GeninKotai.WakuPlan, held: { number }?): { [string]: number }
	local targets = table.clone(plan.mikataTargets)
	for id, target in GeninKotai.tekiTargets(plan, held or {}).targets do
		targets[id] = target
	end
	return targets
end

local function planOf(butai: { GeninKotai.ButaiState }, members: { KotaiHaibun.Member }?, cap: number?, rate: number?)
	return GeninKotai.planWaku(butai, members or ONE, cap or CAP, rate or RATE, PARAMS)
end

-- 種を固定した乱数（線形合同法）。0 以上 max 未満の数を返す
local function random(seed: number): (max: number) -> number
	local value = seed
	return function(max: number): number
		value = (value * 1103515245 + 12345) % 2147483648
		return value / 2147483648 * max
	end
end

-- 出す対象・半径・まとまりの数え方（#76・#85 と同じ）

test("近づいた部隊の下忍を、上限まで個体として出す", function()
	local plan = planOf({ teki("b1", 50, 0, 60) })
	expect(targetsOf(plan).b1).toBe(40)
	expect(plan.distances.b1).toBeNear(50)
end)

test("個体の数は部隊の兵数を超えない", function()
	expect(targetsOf(planOf({ teki("b1", 50, 0, 12) })).b1).toBe(12)
	expect(targetsOf(planOf({ mikata("m1", 50, 0, 3) })).m1).toBe(3)
end)

test("出現の半径の外の部隊は出さない", function()
	local plan = planOf({ teki("b1", 121, 0, 30), mikata("m1", 0, 121, 30) })
	expect(targetsOf(plan).b1).toBe(0)
	expect(plan.mikataTargets.m1).toBe(0)
	expect(plan.groupOf.b1).toBe(nil)
	expect(plan.groupOf.m1).toBe(nil)
end)

test(
	"出ている部隊は、消滅の半径より離れるまで残し、離れたら 0 に戻す（両軍）",
	function()
		local inside = planOf({ teki("b1", 150, 0, 30, 8), mikata("m1", 0, 150, 30, 6) })
		expect(inside.mikataTargets.m1).toBe(10)
		expect(targetsOf(inside, { 10 }).b1).toBe(30)
		local outside = planOf({ teki("b1", 161, 0, 30, 8), mikata("m1", 0, 161, 30, 6) })
		expect(outside.mikataTargets.m1).toBe(0)
		expect(targetsOf(outside).b1).toBe(0)
	end
)

test("半径の間を行き来しても、出入りを繰り返さない", function()
	local present = 0
	local changes = 0
	-- 外から近づいて 100 で出し、半径の間（110〜150）を往復してから 170 で離れる
	for _, x in { 170, 130, 100, 110, 150, 110, 150, 170 } do
		local next = targetsOf(planOf({ teki("b1", x, 0, 30, present) })).b1
		if (next > 0) ~= (present > 0) then
			changes += 1
		end
		present = next
	end
	expect(changes).toBe(2)
	expect(present).toBe(0)
end)

test("1人の近くの2部隊には、枠を兵数の比で分ける", function()
	local targets = targetsOf(planOf({ teki("b1", 30, 0, 30), teki("b2", -30, 0, 10) }, ONE, 20))
	expect(targets.b1).toBe(15)
	expect(targets.b2).toBe(5)
	-- 味方軍の目標も、まとまりの中の味方軍の部隊へ兵数の比で分ける（端数は残りの大きい順、同じなら先の部隊）
	local plan = planOf({ mikata("m1", 0, 30, 30), mikata("m2", 0, -30, 10), teki("t1", 30, 0, 60) })
	expect(plan.mikataTargets.m1).toBe(8)
	expect(plan.mikataTargets.m2).toBe(2)
end)

test("離れた2人には、上限を人数の比で分ける", function()
	local members = { { id = "A", x = 0, z = 0 }, { id = "B", x = 500, z = 0 } }
	local targets = targetsOf(planOf({ teki("b1", 30, 0, 50), teki("b2", 530, 0, 50) }, members))
	expect(targets.b1).toBe(20)
	expect(targets.b2).toBe(20)
end)

test("近くに部隊のいない人の分は、ほかの人の近くの部隊へ回す", function()
	local members = { { id = "A", x = 0, z = 0 }, { id = "B", x = 500, z = 0 } }
	expect(targetsOf(planOf({ teki("b1", 30, 0, 50) }, members)).b1).toBe(40)
end)

test("兵数 0 の部隊と、メンバーがいないときは出さない", function()
	expect(targetsOf(planOf({ teki("b1", 10, 0, 0) })).b1).toBe(0)
	local nobody = planOf({ teki("b1", 10, 0, 30, 5), mikata("m1", 0, 10, 30, 5) }, {})
	expect(targetsOf(nobody).b1).toBe(0)
	expect(nobody.mikataTargets.m1).toBe(0)
	expect(nobody.distances.b1).toBe(nil)
	expect(#nobody.groups).toBe(0)
end)

-- 枠の分け方

test(
	"1人なら取り分 40・味方軍の上限 10。味方軍が押さえていなければ敵軍は 40、10 体を押さえると 30",
	function()
		local plan = planOf({ mikata("m1", 0, 50, 40), teki("t1", 0, -50, 60) })
		local group = plan.groups[1]
		expect(group.members).toEqual({ "A" })
		expect(group.share).toBe(40)
		expect(group.mikataCap).toBe(10)
		expect(group.mikataHeisu).toBe(40)
		expect(group.tekiHeisu).toBe(60)
		expect(group.demand).toBe(70)
		expect(group.quota).toBe(40)
		expect(group.mikataTarget).toBe(10)
		expect(plan.mikataTargets.m1).toBe(10)
		expect(plan.groupOf).toEqual({ m1 = 1, t1 = 1 })
		expect(GeninKotai.tekiTargets(plan, { 0 }).targets.t1).toBe(40)
		expect(GeninKotai.tekiTargets(plan, { 4 }).targets.t1).toBe(36)
		local full = GeninKotai.tekiTargets(plan, { 10 })
		expect(full.targets.t1).toBe(30)
		expect(full.held).toEqual({ 10 })
		expect(full.quotas).toEqual({ 30 })
	end
)

test("押さえている数は 0 から味方軍の目標までに収める", function()
	local plan = planOf({ mikata("m1", 0, 50, 40), teki("t1", 0, -50, 60) })
	local over = GeninKotai.tekiTargets(plan, { 25 })
	expect(over.held).toEqual({ 10 })
	expect(over.targets.t1).toBe(30)
	local under = GeninKotai.tekiTargets(plan, { -3 })
	expect(under.held).toEqual({ 0 })
	expect(under.targets.t1).toBe(40)
end)

test("敵軍の兵数が足りなければ、敵軍の目標は兵数まで", function()
	local plan = planOf({ mikata("m1", 0, 50, 40), teki("t1", 0, -50, 12) })
	expect(plan.groups[1].quota).toBe(22)
	expect(plan.mikataTargets.m1).toBe(10)
	expect(targetsOf(plan, { 0 }).t1).toBe(12)
	expect(targetsOf(plan, { 10 }).t1).toBe(12)
end)

test("味方軍の部隊の兵数が味方軍の上限より少なければ、残りを敵軍へ回す", function()
	local plan = planOf({ mikata("m1", 0, 50, 4), teki("t1", 0, -50, 60) })
	expect(plan.mikataTargets.m1).toBe(4)
	expect(targetsOf(plan, { 4 }).t1).toBe(36)
	expect(targetsOf(plan, { 0 }).t1).toBe(40)
end)

test(
	"離れた2人で片方にだけ味方軍がいると、味方軍は 5 まで、もう片方の敵軍は押さえている数によらず 20",
	function()
		local members = { { id = "A", x = 0, z = 0 }, { id = "B", x = 500, z = 0 } }
		local plan = planOf({ mikata("m1", 30, 0, 40), teki("t1", -30, 0, 50), teki("t2", 530, 0, 50) }, members)
		expect(plan.groups[1].share).toBe(20)
		expect(plan.groups[2].share).toBe(20)
		expect(plan.groups[1].mikataCap).toBe(5)
		expect(plan.groups[1].quota).toBe(20)
		expect(plan.groups[2].quota).toBe(20)
		expect(plan.mikataTargets.m1).toBe(5)
		for _, held in { 0, 3, 5 } do
			local targets = targetsOf(plan, { held, 0 })
			expect(targets.t1).toBe(20 - held)
			expect(targets.t2).toBe(20)
		end
	end
)

test("片方のまとまりに味方軍だけ、もう片方に敵軍だけなら、味方軍 5・敵軍 35", function()
	local members = { { id = "A", x = 0, z = 0 }, { id = "B", x = 500, z = 0 } }
	local plan = planOf({ mikata("m1", 30, 0, 40), teki("t2", 530, 0, 50) }, members)
	expect(plan.groups[1].demand).toBe(5)
	expect(plan.groups[1].quota).toBe(5)
	expect(plan.groups[2].quota).toBe(35)
	expect(plan.mikataTargets.m1).toBe(5)
	expect(targetsOf(plan, { 5, 0 }).t2).toBe(35)
	expect(targetsOf(plan, { 0, 0 }).t2).toBe(35)
end)

test("3人で取り分が 14・13・13 なら、味方軍の上限は切り捨てで 3・3・3", function()
	local members = { { id = "A", x = 0, z = 0 }, { id = "B", x = 300, z = 0 }, { id = "C", x = 600, z = 0 } }
	local butai = {}
	for index, member in members do
		table.insert(butai, mikata(`m{index}`, member.x, 30, 40))
		table.insert(butai, teki(`t{index}`, member.x, -30, 50))
	end
	local plan = planOf(butai, members)
	local shares, caps, quotas = {}, {}, {}
	for _, group in plan.groups do
		table.insert(shares, group.share)
		table.insert(caps, group.mikataCap)
		table.insert(quotas, group.quota)
	end
	expect(shares).toEqual({ 14, 13, 13 })
	expect(caps).toEqual({ 3, 3, 3 })
	expect(quotas).toEqual({ 14, 13, 13 })
	local targets = targetsOf(plan, { 3, 3, 3 })
	expect({ targets.m1, targets.m2, targets.m3 }).toEqual({ 3, 3, 3 })
	expect({ targets.t1, targets.t2, targets.t3 }).toEqual({ 11, 10, 10 })
	expect(sum(targets)).toBe(40)
end)

test("離れた4人なら、取り分 10 ずつで味方軍の上限は 2 ずつ", function()
	local members = {
		{ id = "A", x = 0, z = 0 },
		{ id = "B", x = 300, z = 0 },
		{ id = "C", x = 0, z = 300 },
		{ id = "D", x = 300, z = 300 },
	}
	local butai = {}
	for index, member in members do
		table.insert(butai, mikata(`m{index}`, member.x + 20, member.z, 40))
	end
	local plan = planOf(butai, members)
	for index, group in plan.groups do
		expect(group.share).toBe(10)
		expect(group.mikataCap).toBe(2)
		expect(plan.mikataTargets[`m{index}`]).toBe(2)
	end
end)

test(
	"割合が 0 なら味方軍は出さない。割合が 1 なら味方軍は枠の全部までで、敵軍は押さえている数を引いた残り",
	function()
		local butai = { mikata("m1", 0, 50, 60), teki("t1", 0, -50, 60) }
		local none = planOf(butai, ONE, CAP, 0)
		expect(none.mikataTargets.m1).toBe(0)
		expect(targetsOf(none, { 0 }).t1).toBe(40)
		local all = planOf(butai, ONE, CAP, 1)
		expect(all.mikataTargets.m1).toBe(40)
		-- 味方軍が 40 体を押さえたら、両軍の目標の合計は 40
		expect(targetsOf(all, { 40 }).t1).toBe(0)
		-- まだ出ていなければ、敵軍は枠を全部使う（出ている数の合計は fill で枠を超えない）
		expect(targetsOf(all, { 0 }).t1).toBe(40)
	end
)

test(
	"まだ出ていない味方軍の分も、ほかのまとまりへ回す余りからは除く（そのまとまりの枠に残す）",
	function()
		-- A の近くの敵軍は兵数 8 しかなく、余りは B へ回る。A に味方軍が来ると、出ていなくても味方軍の上限 5 を A に残す
		local members = { { id = "A", x = 0, z = 0 }, { id = "B", x = 500, z = 0 } }
		local without = planOf({ teki("tA", 30, 0, 8), teki("tB", 530, 0, 60) }, members)
		expect(without.groups[1].quota).toBe(8)
		expect(without.groups[2].quota).toBe(32)
		local with = planOf({ mikata("mA", 0, 30, 40), teki("tA", 30, 0, 8), teki("tB", 530, 0, 60) }, members)
		expect(with.groups[1].quota).toBe(13)
		expect(with.groups[2].quota).toBe(27)
		-- 同じまとまりの敵軍は、味方軍が押さえるまで減らさない
		local targets = targetsOf(with, { 0, 0 })
		expect(targets.tA).toBe(8)
		expect(targets.tB).toBe(27)
	end
)

-- 押さえている数・返却の求め・補充の停止・出す順

test(
	"押さえている数は、味方軍の部隊ごとの min(目標, 出ている数 + 返却の求め) の合計",
	function()
		local plan = planOf({
			mikata("m1", 0, 30, 30),
			mikata("m2", 0, -30, 10),
			mikata("far", 500, 0, 40),
			teki("t1", 30, 0, 60),
		})
		-- 目標は m1 8・m2 2。遠い味方軍の部隊はまとまりに入らない
		expect(GeninKotai.heldOf(plan, {}, {})).toEqual({ 0 })
		expect(GeninKotai.heldOf(plan, { m1 = 3 }, { m1 = 2 })).toEqual({ 5 })
		expect(GeninKotai.heldOf(plan, { m1 = 6, m2 = 1 }, { m1 = 4, m2 = 4 })).toEqual({ 10 })
		-- 目標より多く出ている部隊（視界の中で戻せない個体）は、目標までしか数えない
		expect(GeninKotai.heldOf(plan, { m1 = 12 }, {})).toEqual({ 8 })
		-- まとまりに入らない部隊と、敵軍の部隊の数は数えない
		expect(GeninKotai.heldOf(plan, { far = 10, t1 = 30 }, { far = 10, t1 = 5 })).toEqual({ 0 })
	end
)

test(
	"返却の求めは、出せる位置があれば step ずつ増やし、無ければ保ち、要らなくなったら外す",
	function()
		-- 目標が 0 になったら（部隊が離れたら）取り消す
		expect(GeninKotai.updateRequest(4, 0, 0, true, STEP)).toBe(nil)
		-- 足りていれば外す（目標より多く出ていても）
		expect(GeninKotai.updateRequest(4, 10, 10, true, STEP)).toBe(nil)
		expect(GeninKotai.updateRequest(4, 10, 12, false, STEP)).toBe(nil)
		-- 出せる位置があれば step ずつ増やす
		expect(GeninKotai.updateRequest(nil, 10, 0, true, STEP)).toBe(2)
		expect(GeninKotai.updateRequest(2, 10, 0, true, STEP)).toBe(4)
		-- 足りない数より多くは求めない
		expect(GeninKotai.updateRequest(8, 10, 0, true, STEP)).toBe(10)
		expect(GeninKotai.updateRequest(4, 10, 6, true, STEP)).toBe(4)
		expect(GeninKotai.updateRequest(nil, 10, 9, true, STEP)).toBe(1)
		-- 出せる位置が無ければ増やさずに保つ（足りない数まで）。求めていなければ求めない
		expect(GeninKotai.updateRequest(4, 10, 0, false, STEP)).toBe(4)
		expect(GeninKotai.updateRequest(6, 10, 6, false, STEP)).toBe(4)
		expect(GeninKotai.updateRequest(nil, 10, 0, false, STEP)).toBe(nil)
		expect(GeninKotai.updateRequest(4, 10, 0, true, 0)).toBe(4)
	end
)

test("メンバーが1人でも重なれば、同じまとまりが続いているとみなす", function()
	expect(GeninKotai.sharesMember({ "A", "B" }, { "B" })).toBe(true)
	expect(GeninKotai.sharesMember({ "A" }, { "A", "C" })).toBe(true)
	expect(GeninKotai.sharesMember({ "A" }, { "B" })).toBe(false)
	expect(GeninKotai.sharesMember({}, { "A" })).toBe(false)
end)

test("返却を求めている味方軍の部隊がいるまとまりだけ、敵軍の補充を止める", function()
	local members = { { id = "A", x = 0, z = 0 }, { id = "B", x = 500, z = 0 } }
	local plan = planOf({ mikata("m1", 30, 0, 40), mikata("m2", 530, 0, 40) }, members)
	expect(GeninKotai.hojuStopped(plan, {})).toEqual({ false, false })
	expect(GeninKotai.hojuStopped(plan, { m1 = 2 })).toEqual({ true, false })
	expect(GeninKotai.hojuStopped(plan, { m1 = 0, m2 = 1 })).toEqual({ false, true })
	-- まとまりに入らない部隊の求めは見ない
	expect(GeninKotai.hojuStopped(plan, { other = 3 })).toEqual({ false, false })
end)

-- fill に渡す spawn。出したい数を記録し、blocked の部隊は出せない（視界の中）として 0 を返す
local function recorder(blocked: { [string]: boolean }?): ({ { id: string, want: number } }, (string, number) -> number)
	local calls = {}
	return calls,
		function(id: string, want: number): number
			table.insert(calls, { id = id, want = want })
			return if blocked and blocked[id] then 0 else want
		end
end

test("出すときは味方軍の足りない部隊が先で、全体の予算を超えない", function()
	local plan = planOf({ mikata("m1", 0, 50, 40), teki("t1", 0, -50, 60) })
	local teki0 = GeninKotai.tekiTargets(plan, { 0 })
	local calls, spawn = recorder()
	local spawned = GeninKotai.fill(plan, teki0, {}, {}, MAX_PER_TICK, spawn)
	expect(calls).toEqual({ { id = "m1", want = 8 } })
	expect(spawned).toEqual({ m1 = 8 })
	-- 予算が残れば敵軍にも出す
	local calls2, spawn2 = recorder()
	GeninKotai.fill(plan, teki0, { m1 = 8 }, {}, MAX_PER_TICK, spawn2)
	expect(calls2).toEqual({ { id = "m1", want = 2 }, { id = "t1", want = 6 } })
end)

test("まとまりの枠の残りより多くは出さず、空いた枠は味方軍に先に回す", function()
	local plan = planOf({ mikata("m1", 0, 50, 40), teki("t1", 0, -50, 60) })
	local teki0 = GeninKotai.tekiTargets(plan, { 0 })
	local calls, spawn = recorder()
	GeninKotai.fill(plan, teki0, { t1 = 38 }, {}, MAX_PER_TICK, spawn)
	expect(calls).toEqual({ { id = "m1", want = 2 } })
end)

test("返却を求めている間は、そのまとまりの敵軍を補充しない", function()
	local plan = planOf({ mikata("m1", 0, 50, 40), teki("t1", 0, -50, 60) })
	local requested = { m1 = 2 }
	local teki2 = GeninKotai.tekiTargets(plan, GeninKotai.heldOf(plan, {}, requested))
	expect(teki2.targets.t1).toBe(38)
	-- 味方軍が視界の中で出せなくても、敵軍には回さない
	local calls, spawn = recorder({ m1 = true })
	GeninKotai.fill(plan, teki2, { t1 = 30 }, requested, MAX_PER_TICK, spawn)
	expect(calls).toEqual({ { id = "m1", want = 8 } })
	-- 求めていなければ、味方軍が出せなかった分を敵軍に回す
	local teki0 = GeninKotai.tekiTargets(plan, { 0 })
	local calls2, spawn2 = recorder({ m1 = true })
	GeninKotai.fill(plan, teki0, { t1 = 30 }, {}, MAX_PER_TICK, spawn2)
	expect(calls2).toEqual({ { id = "m1", want = 8 }, { id = "t1", want = 8 } })
end)

test(
	"目標より多い味方軍の個体が残る間は、同じまとまりのほかの味方軍の部隊へ出さない",
	function()
		local plan = planOf({ mikata("m1", 0, 30, 30), mikata("m2", 0, -30, 10), teki("t1", 30, 0, 60) })
		local teki0 = GeninKotai.tekiTargets(plan, { 10 })
		-- m2 の目標は 2 だが、視界の中で戻せない個体が 10 体残っている
		local calls, spawn = recorder()
		GeninKotai.fill(plan, teki0, { m2 = 10 }, {}, MAX_PER_TICK, spawn)
		expect(calls).toEqual({ { id = "t1", want = 8 } })
		local calls2, spawn2 = recorder()
		GeninKotai.fill(plan, teki0, { m2 = 5, t1 = 30 }, {}, MAX_PER_TICK, spawn2)
		expect(calls2).toEqual({ { id = "m1", want = 5 } })
	end
)

test("予算は、spawn が出せた数だけを減らす", function()
	local members = { { id = "A", x = 0, z = 0 }, { id = "B", x = 300, z = 0 }, { id = "C", x = 600, z = 0 } }
	local plan = planOf({ teki("t1", 0, 30, 50), teki("t2", 300, 30, 50), teki("t3", 600, 30, 50) }, members)
	local teki0 = GeninKotai.tekiTargets(plan, {})
	-- t1 のまとまりは埋まっている。t2 は出せる位置が無いので、予算 3 はそのまま t3 に回る
	local calls, spawn = recorder({ t2 = true })
	local spawned = GeninKotai.fill(plan, teki0, { t1 = 14, t3 = 3 }, {}, 3, spawn)
	expect(calls).toEqual({ { id = "t2", want = 3 }, { id = "t3", want = 3 } })
	expect(spawned).toEqual({ t2 = 0, t3 = 3 })
	expect(GeninKotai.fill(plan, teki0, {}, {}, 0, spawn)).toEqual({})
end)

-- 乱数で混ぜた場面

-- 出撃メンバー 1〜4 人と、両軍の部隊（出ている数と返却の求めを含む）を作る
local function randomScene(nextNumber: (number) -> number): (
	{ KotaiHaibun.Member },
	{ GeninKotai.ButaiState },
	{ [string]: number },
	{ [string]: number }
)
	local members = {}
	for index = 1, 1 + math.floor(nextNumber(4)) do
		table.insert(members, { id = `P{index}`, x = nextNumber(600), z = nextNumber(600) })
	end
	local butai: { GeninKotai.ButaiState } = {}
	local present: { [string]: number } = {}
	local requested: { [string]: number } = {}
	for index = 1, math.floor(nextNumber(9)) do
		local gun: Gun.Gun = if nextNumber(2) < 1 then "Mikatagun" else "Tekigun"
		local id = `{if gun == "Mikatagun" then "m" else "t"}{index}`
		local count = math.floor(nextNumber(12))
		table.insert(butai, {
			id = id,
			gun = gun,
			x = nextNumber(600),
			z = nextNumber(600),
			heisu = math.floor(nextNumber(45)),
			present = count,
		})
		present[id] = count
		if gun == "Mikatagun" and nextNumber(2) < 1 then
			requested[id] = math.floor(nextNumber(12))
		end
	end
	return members, butai, present, requested
end

test(
	"どんな場面でも、両軍の目標の合計は上限以下、まとまりごとに枠以下、味方軍は上限以下、部隊は兵数以下",
	function()
		local nextNumber = random(82)
		for _ = 1, 400 do
			local members, butai, present, requested = randomScene(nextNumber)
			local cap = math.floor(nextNumber(60))
			local rate = if nextNumber(2) < 1 then RATE else nextNumber(1)
			local plan = GeninKotai.planWaku(butai, members, cap, rate, PARAMS)
			local tekiPlan = GeninKotai.tekiTargets(plan, GeninKotai.heldOf(plan, present, requested))
			local aOf = {}
			local shareSum, quotaSum, heldSum = 0, 0, 0
			for index, group in plan.groups do
				shareSum += group.share
				quotaSum += group.quota
				heldSum += tekiPlan.held[index]
				aOf[index] = group.mikataTarget
				expect(group.mikataCap).toBe(math.floor(group.share * rate + 1e-9))
				expect(group.quota <= group.demand).toBe(true)
				expect(group.demand).toBe(group.tekiHeisu + math.min(group.mikataHeisu, group.mikataCap))
				-- 味方軍の目標の合計は a で、a は味方軍の上限と枠を超えない
				local mikataSum = 0
				for _, id in group.mikataButai do
					mikataSum += plan.mikataTargets[id]
				end
				expect(mikataSum).toBe(group.mikataTarget)
				expect(group.mikataTarget <= group.mikataCap and group.mikataTarget <= group.quota).toBe(true)
				-- 押さえている数と敵軍の目標の合計は枠を超えない
				local tekiSum = 0
				for _, id in group.tekiButai do
					tekiSum += tekiPlan.targets[id]
				end
				expect(tekiPlan.held[index] >= 0 and tekiPlan.held[index] <= group.mikataTarget).toBe(true)
				expect(tekiPlan.held[index] + tekiSum <= group.quota).toBe(true)
				expect(tekiPlan.quotas[index]).toBe(group.quota - tekiPlan.held[index])
			end
			expect(shareSum).toBe(if #members > 0 then cap else 0)
			expect(quotaSum <= cap).toBe(true)
			expect(heldSum + sum(tekiPlan.targets) <= cap).toBe(true)
			-- 味方軍の目標の合計は、全体の上限 × 割合の切り捨てを超えない
			expect(sum(plan.mikataTargets) <= math.floor(cap * rate + 1e-9)).toBe(true)
			-- 味方軍が目標まで押さえたときの両軍の目標の合計は上限を超えない
			local full = GeninKotai.tekiTargets(plan, aOf)
			expect(sum(plan.mikataTargets) + sum(full.targets) <= cap).toBe(true)
			for _, entry in butai do
				local target = if entry.gun == "Mikatagun"
					then plan.mikataTargets[entry.id]
					else tekiPlan.targets[entry.id]
				expect(target >= 0 and target <= entry.heisu and target == math.floor(target)).toBe(true)
				if plan.groupOf[entry.id] == nil then
					expect(target).toBe(0)
				end
			end
		end
	end
)

test(
	"どんな場面でも、出すときは枠・味方軍の目標・全体の予算を超えず、補充を止めたまとまりの敵軍に出さない",
	function()
		local nextNumber = random(85)
		for _ = 1, 400 do
			local members, butai, present, requested = randomScene(nextNumber)
			local plan = GeninKotai.planWaku(butai, members, CAP, RATE, PARAMS)
			local tekiPlan = GeninKotai.tekiTargets(plan, GeninKotai.heldOf(plan, present, requested))
			local stopped = GeninKotai.hojuStopped(plan, requested)
			local budget = math.floor(nextNumber(12))
			local after = table.clone(present)
			local spawned = GeninKotai.fill(plan, tekiPlan, present, requested, budget, function(id, want)
				-- 出せる位置が足りないこともある
				local count = math.floor(nextNumber(want + 1))
				after[id] = (after[id] or 0) + count
				return count
			end)
			expect(sum(spawned) <= budget).toBe(true)
			for index, group in plan.groups do
				local before, now, mikataBefore, mikataNow = 0, 0, 0, 0
				for _, id in group.mikataButai do
					before += present[id] or 0
					now += after[id] or 0
					mikataBefore += present[id] or 0
					mikataNow += after[id] or 0
					expect((after[id] or 0) <= math.max(plan.mikataTargets[id], present[id] or 0)).toBe(true)
				end
				for _, id in group.tekiButai do
					before += present[id] or 0
					now += after[id] or 0
					expect((after[id] or 0) <= math.max(tekiPlan.targets[id], present[id] or 0)).toBe(true)
					if stopped[index] then
						expect(spawned[id] or 0).toBe(0)
					end
				end
				expect(now <= math.max(group.quota, before)).toBe(true)
				expect(mikataNow <= math.max(group.mikataTarget, mikataBefore)).toBe(true)
			end
		end
	end
)

test(
	"味方軍の部隊がいなければ、敵軍の目標は #85 の配分を兵数の比で分けたものと同じ",
	function()
		local nextNumber = random(76)
		local jittaikaken = PARAMS.jittaikaken :: Config.JittaikakenSection
		for _ = 1, 200 do
			local members, butai = randomScene(nextNumber)
			local tekigun = {}
			local eligible = {}
			for _, entry in butai do
				if entry.gun == "Tekigun" then
					table.insert(tekigun, entry)
					local distance = Jittaikaken.nearestDistance({ x = entry.x, z = entry.z }, members)
					if entry.heisu > 0 and Jittaikaken.shouldAppear(entry.present > 0, distance, jittaikaken) then
						table.insert(eligible, { id = entry.id, x = entry.x, z = entry.z, heisu = entry.heisu })
					end
				end
			end
			local cap = math.floor(nextNumber(60))
			local plan = GeninKotai.planWaku(tekigun, members, cap, RATE, PARAMS)
			local targets = GeninKotai.tekiTargets(plan, {}).targets
			local expected: { [string]: number } = {}
			for _, entry in tekigun do
				expected[entry.id] = 0
			end
			local heisuOf = {}
			for _, entry in eligible do
				heisuOf[entry.id] = entry.heisu
			end
			for _, group in KotaiHaibun.allocate(members, cap, eligible, { GroupDistance = 80, Reach = 160 }) do
				local weights = {}
				for _, id in group.butai do
					table.insert(weights, heisuOf[id])
				end
				for position, share in KotaiHaibun.split(weights, weights, group.quota) do
					expected[group.butai[position]] = share
				end
			end
			expect(targets).toEqual(expected)
		end
	end
)

test(
	"あるまとまりの味方軍が押さえている数は、ほかのまとまりの敵軍の目標を変えない",
	function()
		local nextNumber = random(90)
		for _ = 1, 200 do
			local members, butai = randomScene(nextNumber)
			local plan = GeninKotai.planWaku(butai, members, CAP, RATE, PARAMS)
			local base = GeninKotai.tekiTargets(plan, {}).targets
			for index, group in plan.groups do
				local held = {}
				held[index] = group.mikataTarget
				local targets = GeninKotai.tekiTargets(plan, held).targets
				for id, target in targets do
					if plan.groupOf[id] ~= index then
						expect(target).toBe(base[id])
					end
				end
			end
		end
	end
)

-- 判断を進める小さな模擬。GeninKotaiService の tick と同じ順に、計画・返却の求め・戻す・出すを進める。
-- seen の部隊は、個体と周りが出撃メンバーの視界の中（PopDistance 以内）で、戻すことも出すこともできない

type SimButai = { id: string, gun: Gun.Gun, x: number, z: number, heisu: number, present: number }

type Sim = {
	members: { KotaiHaibun.Member },
	butai: { SimButai },
	seen: { [string]: boolean },
	requests: { [string]: number },
	-- 求めたまとまりのメンバー。メンバーが重ならないまとまりへ移ったら 0 から積み直す（サービスと同じ）
	requestMembers: { [string]: { string } },
}

local function newSim(members: { KotaiHaibun.Member }, butai: { SimButai }): Sim
	return { members = members, butai = butai, seen = {}, requests = {}, requestMembers = {} }
end

local function simButai(sim: Sim, id: string): SimButai
	for _, entry in sim.butai do
		if entry.id == id then
			return entry
		end
	end
	error(`部隊 {id} がいない`)
end

local function simTotal(sim: Sim): number
	local total = 0
	for _, entry in sim.butai do
		total += entry.present
	end
	return total
end

-- 1回の判断。判断の後の計画と、まとまりごとの補充の停止を返す
local function simStep(sim: Sim): (GeninKotai.WakuPlan, { boolean })
	local states: { GeninKotai.ButaiState } = {}
	local present: { [string]: number } = {}
	for _, entry in sim.butai do
		table.insert(
			states,
			{ id = entry.id, gun = entry.gun, x = entry.x, z = entry.z, heisu = entry.heisu, present = entry.present }
		)
		present[entry.id] = entry.present
	end
	local plan = GeninKotai.planWaku(states, sim.members, CAP, RATE, PARAMS)
	local requests: { [string]: number } = {}
	local memberLists: { [string]: { string } } = {}
	for _, entry in sim.butai do
		local index = plan.groupOf[entry.id]
		if entry.gun == "Mikatagun" and index then
			local members = plan.groups[index].members
			local previous = sim.requestMembers[entry.id]
			local before = if previous and GeninKotai.sharesMember(previous, members)
				then sim.requests[entry.id]
				else nil
			local target = plan.mikataTargets[entry.id]
			local spawnable = target > entry.present and not sim.seen[entry.id]
			local request = GeninKotai.updateRequest(before, target, entry.present, spawnable, STEP)
			if request then
				requests[entry.id] = request
				memberLists[entry.id] = members
			end
		end
	end
	sim.requests = requests
	sim.requestMembers = memberLists
	local tekiPlan = GeninKotai.tekiTargets(plan, GeninKotai.heldOf(plan, present, requests))
	-- 目標より多い部隊は、視界の外なら目標まで戻す（視界の中の個体は戻さない）
	local after: { [string]: number } = {}
	for _, entry in sim.butai do
		local target = if entry.gun == "Mikatagun" then plan.mikataTargets[entry.id] else tekiPlan.targets[entry.id]
		if entry.present > target and not sim.seen[entry.id] then
			entry.present = target
		end
		after[entry.id] = entry.present
	end
	GeninKotai.fill(plan, tekiPlan, after, requests, math.min(MAX_PER_TICK, CAP - simTotal(sim)), function(id, want)
		if sim.seen[id] then
			return 0
		end
		simButai(sim, id).present += want
		return want
	end)
	expect(simTotal(sim) <= CAP).toBe(true)
	return plan, GeninKotai.hojuStopped(plan, requests)
end

local function simKill(sim: Sim, id: string, count: number)
	local entry = simButai(sim, id)
	entry.present -= count
	entry.heisu -= count
end

-- 部隊ごとの出ている数
local function presentOf(sim: Sim): { [string]: number }
	local result = {}
	for _, entry in sim.butai do
		result[entry.id] = entry.present
	end
	return result
end

test("模擬: 味方軍が視界の中で出せない間は、敵軍を減らさず 40 体まで出す", function()
	local sim = newSim(ONE, {
		{ id = "M", gun = "Mikatagun", x = 0, z = 60, heisu = 40, present = 0 },
		{ id = "T", gun = "Tekigun", x = 0, z = -60, heisu = 60, present = 0 },
	})
	sim.seen.M = true
	for _ = 1, 6 do
		local _, stopped = simStep(sim)
		expect(stopped).toEqual({ false })
	end
	expect(presentOf(sim)).toEqual({ M = 0, T = 40 })
	expect(sim.requests.M).toBe(nil)
end)

test(
	"模擬: 視界の外に出せるようになると、敵軍から少しずつ枠を返させて味方軍を出す",
	function()
		local sim = newSim(ONE, {
			{ id = "M", gun = "Mikatagun", x = 0, z = 110, heisu = 40, present = 0 },
			{ id = "T", gun = "Tekigun", x = 0, z = -110, heisu = 60, present = 40 },
		})
		local history = {}
		for _ = 1, 4 do
			simStep(sim)
			table.insert(history, presentOf(sim))
		end
		expect(history).toEqual({
			{ M = 2, T = 38 },
			{ M = 6, T = 34 },
			{ M = 10, T = 30 },
			{ M = 10, T = 30 },
		})
		expect(sim.requests.M).toBe(nil)
	end
)

-- 視界の中で戦っている T1 と、遠くで控える T2（視界によらず出し入れできる）が 20 体ずつ出たところへ、
-- 味方軍の部隊 M が近づく。T2 の分だけ枠が返り、T1 の多い分は戻せないので、味方軍は 5 体で待つ
local function waitingSim(): Sim
	local sim = newSim(ONE, {
		{ id = "M", gun = "Mikatagun", x = 0, z = 400, heisu = 40, present = 0 },
		{ id = "T1", gun = "Tekigun", x = 0, z = -30, heisu = 30, present = 0 },
		{ id = "T2", gun = "Tekigun", x = 110, z = 0, heisu = 30, present = 0 },
	})
	for _ = 1, 5 do
		simStep(sim)
	end
	expect(presentOf(sim)).toEqual({ M = 0, T1 = 20, T2 = 20 })
	sim.seen.T1 = true
	simButai(sim, "M").z = 110
	local stopped
	for _ = 1, 6 do
		_, stopped = simStep(sim)
	end
	expect(presentOf(sim)).toEqual({ M = 5, T1 = 20, T2 = 15 })
	expect(sim.requests.M).toBe(5)
	expect(stopped).toEqual({ true })
	return sim
end

test(
	"模擬: 敵軍を戻せない間は味方軍が待って補充を止め、撃破で空いた枠は味方軍に先に回り、視界の外で残りが返る",
	function()
		local sim = waitingSim()
		-- 待っている間は、判断を重ねても視界の中の敵軍を消さず、T2 も補充しない
		for _ = 1, 4 do
			simStep(sim)
		end
		expect(presentOf(sim)).toEqual({ M = 5, T1 = 20, T2 = 15 })

		-- T1 を3体倒すと、空いた枠は味方軍に回り、T2 は補充しない
		simKill(sim, "T1", 3)
		simStep(sim)
		expect(presentOf(sim)).toEqual({ M = 8, T1 = 17, T2 = 15 })

		-- 視界の外を向くと、T1 の多い分が戻り、味方軍が目標まで出てから敵軍を補充する
		sim.seen.T1 = false
		simStep(sim)
		expect(presentOf(sim)).toEqual({ M = 10, T1 = 14, T2 = 15 })
		local _, stopped = simStep(sim)
		expect(presentOf(sim)).toEqual({ M = 10, T1 = 14, T2 = 16 })
		expect(sim.requests.M).toBe(nil)
		expect(stopped).toEqual({ false })
	end
)

test(
	"模擬: 待っている間に味方軍の部隊が離れたら、求めを消して敵軍を補充する",
	function()
		local sim = waitingSim()
		simButai(sim, "M").z = 400
		local _, stopped = simStep(sim)
		expect(sim.requests.M).toBe(nil)
		expect(stopped).toEqual({ false })
		expect(presentOf(sim)).toEqual({ M = 0, T1 = 20, T2 = 20 })
	end
)

test(
	"模擬: 味方軍の部隊の兵数が減って、目標が出ている数まで下がったら求めを外す",
	function()
		local sim = waitingSim()
		-- 交戦などで兵数が出ている数まで減ると、目標も出ている数に下がり、足りない数が 0 になる
		simButai(sim, "M").heisu = 5
		local _, stopped = simStep(sim)
		expect(sim.requests.M).toBe(nil)
		expect(stopped).toEqual({ false })
		expect(presentOf(sim)).toEqual({ M = 5, T1 = 20, T2 = 15 })
	end
)

test(
	"模擬: 離れた2人で片方にだけ味方軍が来ても、もう片方の敵軍は 20 体のまま",
	function()
		local sim = newSim({ { id = "A", x = 0, z = 0 }, { id = "B", x = 500, z = 0 } }, {
			{ id = "M", gun = "Mikatagun", x = 0, z = 400, heisu = 40, present = 0 },
			{ id = "TA", gun = "Tekigun", x = 0, z = -110, heisu = 60, present = 0 },
			{ id = "TB", gun = "Tekigun", x = 500, z = -110, heisu = 60, present = 0 },
		})
		for _ = 1, 5 do
			simStep(sim)
		end
		expect(presentOf(sim)).toEqual({ M = 0, TA = 20, TB = 20 })
		simButai(sim, "M").z = 110
		for _ = 1, 5 do
			simStep(sim)
			expect(simButai(sim, "TB").present).toBe(20)
		end
		expect(presentOf(sim)).toEqual({ M = 5, TA = 15, TB = 20 })
	end
)

test(
	"模擬: 待っている味方軍の部隊がメンバーの重ならないまとまりへ移ったら、求めを 0 から積み直す",
	function()
		local sim = newSim({ { id = "A", x = 0, z = 0 }, { id = "B", x = 300, z = 0 } }, {
			{ id = "M", gun = "Mikatagun", x = -300, z = 0, heisu = 40, present = 0 },
			{ id = "TA", gun = "Tekigun", x = 0, z = -110, heisu = 60, present = 0 },
			{ id = "TB", gun = "Tekigun", x = 300, z = -110, heisu = 60, present = 0 },
		})
		for _ = 1, 5 do
			simStep(sim)
		end
		expect(presentOf(sim)).toEqual({ M = 0, TA = 20, TB = 20 })
		-- A の近くで、TA が視界の中で戻せないので待つ（求めは味方軍の上限 5 まで積む）
		sim.seen.TA = true
		local m = simButai(sim, "M")
		m.x = -110
		for _ = 1, 3 do
			simStep(sim)
		end
		expect(sim.requests.M).toBe(5)
		expect(presentOf(sim)).toEqual({ M = 0, TA = 20, TB = 20 })
		-- B の近くへ移ると、B の敵軍には 2 体から返させる（A で積んだ 5 体を一度に返させない）
		m.x = 410
		simStep(sim)
		expect(sim.requests.M).toBe(2)
		expect(presentOf(sim)).toEqual({ M = 2, TA = 20, TB = 18 })
		simStep(sim)
		expect(presentOf(sim)).toEqual({ M = 5, TA = 20, TB = 15 })
	end
)

test(
	"模擬: メンバーが合流しただけなら、待っている味方軍の求めは積み直さない",
	function()
		local sim = newSim({ { id = "A", x = 0, z = 0 } }, {
			{ id = "M", gun = "Mikatagun", x = -300, z = 0, heisu = 40, present = 0 },
			{ id = "T", gun = "Tekigun", x = 0, z = -110, heisu = 60, present = 0 },
		})
		for _ = 1, 5 do
			simStep(sim)
		end
		sim.seen.T = true
		simButai(sim, "M").x = -110
		for _ = 1, 5 do
			simStep(sim)
		end
		expect(sim.requests.M).toBe(10)
		-- B が A の近くへ来て同じまとまりになる（メンバーは A から A・B に変わる）
		table.insert(sim.members, { id = "B", x = 30, z = 0 })
		local plan = simStep(sim)
		expect(plan.groups[1].members).toEqual({ "A", "B" })
		expect(sim.requests.M).toBe(10)
		expect(presentOf(sim)).toEqual({ M = 0, T = 40 })
	end
)

test("Config の上限は数十体で、出し入れの距離は実体化圏の中", function()
	local p = Config.GeninKotai
	expect(p.MaxKotai >= 10 and p.MaxKotai <= 100).toBe(true)
	expect(p.MaxPerTick >= 1).toBe(true)
	-- 出現の半径の縁で出すときは、視界の中でも出してよい距離（遠くて目立たない）
	expect(p.PopDistance < Config.Jittaikaken.AppearRadius).toBe(true)
end)

test(
	"Config の味方軍の割合は 0 以上 1 未満で敵軍の分が残り、返却の求めは1体以上ずつ増やす",
	function()
		local p = Config.GeninKotai
		expect(p.MikataRate >= 0 and p.MikataRate < 1).toBe(true)
		expect(math.floor(p.MaxKotai * p.MikataRate) >= 1).toBe(true)
		expect(p.MikataReclaimStep >= 1 and p.MikataReclaimStep == math.floor(p.MikataReclaimStep)).toBe(true)
	end
)
