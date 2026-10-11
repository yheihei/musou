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

test(
	"押さえている数は 0 からまとまりの枠 Q までに収める（味方軍の目標より多い分も数える）",
	function()
		local plan = planOf({ mikata("m1", 0, 50, 40), teki("t1", 0, -50, 60) })
		-- 味方軍の目標は 10 だが、視界の中で戻せない個体が多ければ、その分も敵軍の枠から引く
		local over = GeninKotai.tekiTargets(plan, { 25 })
		expect(over.held).toEqual({ 25 })
		expect(over.quotas).toEqual({ 15 })
		expect(over.targets.t1).toBe(15)
		local beyond = GeninKotai.tekiTargets(plan, { 99 })
		expect(beyond.held).toEqual({ 40 })
		expect(beyond.targets.t1).toBe(0)
		local under = GeninKotai.tekiTargets(plan, { -3 })
		expect(under.held).toEqual({ 0 })
		expect(under.targets.t1).toBe(40)
	end
)

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
	"押さえている数は、味方軍の部隊ごとの max(出ている数, min(目標, 出ている数 + 返却の求め)) の合計",
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
		-- 目標より多く出ている部隊（視界の中で戻せない個体）は、出ている数をそのまま数える
		expect(GeninKotai.heldOf(plan, { m1 = 12 }, {})).toEqual({ 12 })
		expect(GeninKotai.heldOf(plan, { m1 = 3, m2 = 6 }, { m1 = 2 })).toEqual({ 11 })
		-- まとまりに入らない部隊と、敵軍の部隊の数は数えない
		expect(GeninKotai.heldOf(plan, { far = 10, t1 = 30 }, { far = 10, t1 = 5 })).toEqual({ 0 })
	end
)

-- 1部隊の求めを決める材料。省いた値は、今出せて、増やす番で、まとまりの味方軍の予算 10
local function requestOf(prev: number?, target: number, present: number, overrides: { [string]: any }?): number?
	local input: GeninKotai.RequestInput = {
		prev = prev,
		target = target,
		present = present,
		spawnable = true,
		budget = 10,
		grow = true,
		step = STEP,
	}
	for key, value in overrides or {} do
		(input :: any)[key] = value
	end
	return GeninKotai.updateRequest(input)
end

test(
	"返却の求めは、今出せて増やす番なら step 増やし、番でなければ保ち、要らなくなったら外す",
	function()
		-- 目標が 0 になったら（部隊が離れたら）取り消し、足りていれば外す（目標より多く出ていても）
		expect(requestOf(4, 0, 0)).toBe(nil)
		expect(requestOf(4, 10, 10)).toBe(nil)
		expect(requestOf(4, 10, 12)).toBe(nil)
		-- 増やす番なら step 増やす
		expect(requestOf(nil, 10, 0)).toBe(2)
		expect(requestOf(2, 10, 0)).toBe(4)
		-- 番でなければ（前の返却が済んでいない・ほかの部隊が増やす）保つ。求めていなければ求めない
		expect(requestOf(4, 10, 0, { grow = false })).toBe(4)
		expect(requestOf(nil, 10, 0, { grow = false })).toBe(nil)
		expect(requestOf(4, 10, 0, { step = 0 })).toBe(4)
		-- 足りない数より多くは求めない
		expect(requestOf(8, 10, 0)).toBe(10)
		expect(requestOf(4, 10, 7)).toBe(3)
		expect(requestOf(nil, 10, 9)).toBe(1)
	end
)

test(
	"今出せない味方軍の部隊の求めは取り下げ、求めはまとまりの味方軍の予算を超えない",
	function()
		-- 周りに視界の外に出せる位置が無ければ、求めていた分も取り下げる（予約として数えない）
		expect(requestOf(4, 10, 0, { spawnable = false })).toBe(nil)
		expect(requestOf(nil, 10, 0, { spawnable = false })).toBe(nil)
		-- まとまりの味方軍の予算が 0（ほかの部隊の多い分が視界の中に残る）なら、位置があっても取り下げる
		expect(requestOf(4, 10, 0, { budget = 0 })).toBe(nil)
		-- 求めは足りない数とまとまりの味方軍の予算の小さい方まで
		expect(requestOf(4, 10, 0, { budget = 3 })).toBe(3)
		expect(requestOf(nil, 10, 0, { budget = 1 })).toBe(1)
		expect(requestOf(2, 10, 0, { budget = 1, grow = false })).toBe(1)
	end
)

test(
	"求めを増やすのは、まとまりの前の返却が済んでいるときの、足りない数の多い1部隊だけ",
	function()
		local plan = planOf({ mikata("m1", 0, 30, 30), mikata("m2", 0, -30, 10), teki("t1", 30, 0, 60) })
		-- 目標は m1 8・m2 2。敵軍の枠は 40、t1 は 40 体出ている
		local empty: GeninKotai.Requests = { counts = {}, members = {} }
		local function always(): boolean
			return true
		end
		local first, notes = GeninKotai.updateRequests(plan, { t1 = 40 }, empty, always, STEP)
		-- 足りない数の多い m1 だけが求める（1回の判断で返すのは step だけ）
		expect(first.counts).toEqual({ m1 = 2 })
		expect(first.members.m1).toEqual({ "A" })
		expect(notes.m1.budget).toBe(10)
		expect(notes.m2.after).toBe(nil)
		-- t1 がまだ返していなければ（40 体のまま）、前の返却が済んでいないので増やさない
		local waiting = GeninKotai.updateRequests(plan, { t1 = 40 }, first, always, STEP)
		expect(waiting.counts).toEqual({ m1 = 2 })
		-- 返し終えたら（38 体）、また 1 部隊だけ増やす
		local grown = GeninKotai.updateRequests(plan, { t1 = 38 }, first, always, STEP)
		expect(grown.counts).toEqual({ m1 = 4 })
		-- 出せなくなった部隊の求めは取り下げ、ほかの部隊が増やす番になる
		local _, withdrawn = GeninKotai.updateRequests(plan, { t1 = 38 }, first, function(id: string): boolean
			return id ~= "m1"
		end, STEP)
		expect(withdrawn.m1.before).toBe(2)
		expect(withdrawn.m1.after).toBe(nil)
		expect(withdrawn.m1.spawnable).toBe(false)
		expect(withdrawn.m2.after).toBe(2)
	end
)

test(
	"ほかの味方軍の部隊の多い分が残り、まとまりの味方軍の予算が 0 なら、求めも補充の停止も無い",
	function()
		local plan = planOf({ mikata("m1", 0, 30, 30), mikata("m2", 0, -30, 10), teki("t1", 30, 0, 60) })
		-- m2 の目標は 2 だが、視界の中で戻せない個体が 10 体残っている（まとまりの味方軍の予算 10 − 10 = 0）
		local requests, notes = GeninKotai.updateRequests(plan, { m2 = 10, t1 = 30 }, {
			counts = { m1 = 4 },
			members = { m1 = { "A" } },
		}, function(): boolean
			return true
		end, STEP)
		expect(requests.counts).toEqual({})
		expect(notes.m1.before).toBe(4)
		expect(notes.m1.budget).toBe(0)
		expect(GeninKotai.hojuStopped(plan, requests.counts)).toEqual({ false })
		-- 多い分は押さえている数に数え、同じまとまりの敵軍の枠から引く
		local tekiPlan = GeninKotai.tekiTargets(plan, GeninKotai.heldOf(plan, { m2 = 10 }, requests.counts))
		expect(tekiPlan.held).toEqual({ 10 })
		expect(tekiPlan.targets.t1).toBe(30)
	end
)

test(
	"目標が 0 になった部隊と、メンバーの重ならないまとまりへ移った部隊は、前の求めを残さない",
	function()
		local members = { { id = "A", x = 0, z = 0 }, { id = "B", x = 500, z = 0 } }
		local plan =
			planOf({ mikata("m1", 530, 0, 40), mikata("far", 250, 400, 40), teki("t2", 500, -30, 60) }, members)
		local function always(): boolean
			return true
		end
		-- m1 は A のまとまりで 4 体を求めていたが、B のまとまりへ移った。far は離れて目標 0 になった
		local requests, notes = GeninKotai.updateRequests(plan, { t2 = 20 }, {
			counts = { m1 = 4, far = 2 },
			members = { m1 = { "A" }, far = { "A" } },
		}, always, STEP)
		expect(notes.m1.before).toBe(nil)
		expect(notes.m1.movedFrom).toEqual({ "A" })
		expect(notes.m1.movedCount).toBe(4)
		expect(requests.counts.m1).toBe(2)
		expect(requests.members.m1).toEqual({ "B" })
		expect(notes.far.before).toBe(2)
		expect(notes.far.target).toBe(0)
		expect(notes.far.after).toBe(nil)
		expect(requests.counts.far).toBe(nil)
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

-- 戻す個体の候補。item は「部隊 ID@距離」の文字列
local function candidateOf(butai: string, distance: number, label: string?): GeninKotai.ReturnCandidate<string>
	return { item = label or `{butai}@{distance}`, butai = butai, distance = distance }
end

local function itemsOf(picked: { GeninKotai.ReturnCandidate<string> }): { string }
	local result = {}
	for _, candidate in picked do
		table.insert(result, candidate.item)
	end
	return result
end

test(
	"戻す個体は、まとまりの全部隊の個体から遠い順に、戻せる個体だけを数まで選ぶ",
	function()
		local candidates = {
			candidateOf("t1", 30),
			candidateOf("t1", 35),
			candidateOf("t1", 50),
			candidateOf("t2", 40),
			candidateOf("t2", 45),
			candidateOf("t2", 20),
		}
		-- t1 の個体はすべて視界の中でも、t2 の視界の外の個体から遠い順に戻す
		local function outOfView(candidate: GeninKotai.ReturnCandidate<string>): boolean
			return candidate.butai ~= "t1"
		end
		expect(itemsOf(GeninKotai.pickReturns(candidates, 2, outOfView))).toEqual({ "t2@45", "t2@40" })
		-- 戻せる個体が足りなければ、戻せた分だけ
		expect(itemsOf(GeninKotai.pickReturns(candidates, 5, outOfView))).toEqual({ "t2@45", "t2@40", "t2@20" })
		-- すべて戻せるときも、数を超えない
		local function always(): boolean
			return true
		end
		expect(itemsOf(GeninKotai.pickReturns(candidates, 3, always))).toEqual({ "t1@50", "t2@45", "t2@40" })
		expect(#GeninKotai.pickReturns(candidates, 0, always)).toBe(0)
		expect(#GeninKotai.pickReturns({}, 3, always)).toBe(0)
		-- 数だけ選んだら、それより近い個体の判定はしない
		local calls = 0
		GeninKotai.pickReturns(candidates, 1, function(): boolean
			calls += 1
			return true
		end)
		expect(calls).toBe(1)
		-- 同じ距離なら部隊 ID の順、同じ部隊なら渡した順
		local ties = { candidateOf("b", 10), candidateOf("a", 10, "a-1"), candidateOf("a", 10, "a-2") }
		expect(itemsOf(GeninKotai.pickReturns(ties, 3, always))).toEqual({ "a-1", "a-2", "b@10" })
	end
)

test(
	"どんな候補でも、選ぶのは戻せる個体だけで、数を超えず、遠い順で、足りなければ戻せる個体をすべて選ぶ",
	function()
		local nextNumber = random(93)
		for _ = 1, 300 do
			local candidates = {}
			local returnable: { [string]: boolean } = {}
			for index = 1, math.floor(nextNumber(12)) do
				local label = `c{index}`
				table.insert(
					candidates,
					candidateOf(`b{math.floor(nextNumber(3))}`, math.floor(nextNumber(100)), label)
				)
				returnable[label] = nextNumber(2) < 1
			end
			local count = math.floor(nextNumber(10))
			local picked = GeninKotai.pickReturns(candidates, count, function(candidate): boolean
				return returnable[candidate.item]
			end)
			local available = 0
			for _, candidate in candidates do
				if returnable[candidate.item] then
					available += 1
				end
			end
			expect(#picked).toBe(math.min(count, available))
			for index, candidate in picked do
				expect(returnable[candidate.item]).toBe(true)
				if index > 1 then
					expect(picked[index - 1].distance >= candidate.distance).toBe(true)
				end
			end
		end
	end
)

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
				expect(tekiPlan.held[index] >= 0 and tekiPlan.held[index] <= group.quota).toBe(true)
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

-- 判断を進める小さな模擬。GeninKotaiService の tick と同じ順に、計画・返却の求め・戻す・出すを進め、
-- 出し入れしてよいか・味方軍の枠のために戻してよいかは、サービスと同じ GeninKotai の関数（canPop・returnCounts・
-- pickGroupReturns）で決める。
-- - seen の部隊は、個体と周りが出撃メンバーの視界の中で、メンバーから PopDistance 以内（戻すことも出すこともできない）
-- - farSeen の部隊は、視界の中だが、メンバー全員から PopDistance より遠い（出し入れの決まりでは出し入れできるが、
--   味方軍の枠を空けるためには戻さない）

type SimButai = { id: string, gun: Gun.Gun, x: number, z: number, heisu: number, present: number }

type Sim = {
	members: { KotaiHaibun.Member },
	butai: { SimButai },
	seen: { [string]: boolean },
	farSeen: { [string]: boolean },
	requests: GeninKotai.Requests,
}

-- 1回の判断で、まとまりの敵軍の個体を戻したときの様子（模擬の確かめ用）
type SimReturn = {
	normal: number,
	reclaim: number,
	-- 戻した数と、そのうち reclaim で戻した数
	picked: number,
	reclaimed: number,
	-- 戻した個体のうち、視界の中（seen か farSeen）の個体の数と、視界の中で近い（seen）個体の数
	onScreen: number,
	near: number,
}

local function newSim(members: { KotaiHaibun.Member }, butai: { SimButai }): Sim
	return { members = members, butai = butai, seen = {}, farSeen = {}, requests = { counts = {}, members = {} } }
end

-- 部隊の個体と周りが、出撃メンバーの視界にかかるか
local function simSeen(sim: Sim, id: string): boolean
	return sim.seen[id] == true or sim.farSeen[id] == true
end

-- 部隊の個体と周りが、メンバー全員から PopDistance より遠いか（視界の外の部隊は、遠さによらず出し入れできる）
local function simFar(sim: Sim, id: string): boolean
	return not sim.seen[id]
end

-- 出し入れしてよいか（サービスの popSafe と同じ決まり）
local function simCanPop(sim: Sim, id: string): boolean
	return GeninKotai.canPop(simSeen(sim, id), simFar(sim, id))
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

-- 1回の判断。判断の後の計画と、まとまりごとの補充の停止と、まとまりごとの敵軍の個体を戻した様子を返す
local function simStep(sim: Sim): (GeninKotai.WakuPlan, { boolean }, { SimReturn })
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
	-- 出せる位置は、出し入れしてよい部隊にだけある（視界の中で近い部隊には無い）
	sim.requests = GeninKotai.updateRequests(plan, present, sim.requests, function(id: string): boolean
		return simCanPop(sim, id)
	end, STEP)
	local requests = sim.requests.counts
	local tekiPlan = GeninKotai.tekiTargets(plan, GeninKotai.heldOf(plan, present, requests))
	-- 目標より多い個体を戻す（サービスの returnExcess と同じ）。味方軍の部隊と、まとまりに入らない敵軍の部隊は、部隊ごとに
	-- 出し入れの決まり（canPop）で戻す。まとまりに入る敵軍は、まとまりの全部隊の個体を遠い順に並べ、味方軍によらない分は
	-- canPop で、味方軍の枠を空ける分は視界の外の個体だけを戻す（returnCounts・pickGroupReturns）。
	-- 模擬の個体は、部隊の位置にいるとみなす
	for _, entry in sim.butai do
		if entry.gun == "Mikatagun" or plan.groupOf[entry.id] == nil then
			local target = if entry.gun == "Mikatagun" then plan.mikataTargets[entry.id] else tekiPlan.targets[entry.id]
			if entry.present > target and simCanPop(sim, entry.id) then
				entry.present = target
			end
		end
	end
	local returns: { SimReturn } = {}
	for index, group in plan.groups do
		local groupPresent = 0
		local candidates: { GeninKotai.ReturnCandidate<SimButai> } = {}
		for _, id in group.tekiButai do
			local entry = simButai(sim, id)
			groupPresent += entry.present
			for _ = 1, entry.present do
				table.insert(candidates, { item = entry, butai = id, distance = plan.distances[id] })
			end
		end
		local normal, reclaim = GeninKotai.returnCounts(plan, tekiPlan, index, groupPresent, 0)
		local picked, reclaimed = GeninKotai.pickGroupReturns(candidates, normal, reclaim, function(candidate): boolean
			return simSeen(sim, candidate.butai)
		end, function(candidate): boolean
			return simFar(sim, candidate.butai)
		end)
		local report: SimReturn =
			{ normal = normal, reclaim = reclaim, picked = #picked, reclaimed = reclaimed, onScreen = 0, near = 0 }
		for _, candidate in picked do
			candidate.item.present -= 1
			if simSeen(sim, candidate.butai) then
				report.onScreen += 1
			end
			if sim.seen[candidate.butai] then
				report.near += 1
			end
		end
		returns[index] = report
	end
	local after: { [string]: number } = {}
	for _, entry in sim.butai do
		after[entry.id] = entry.present
	end
	GeninKotai.fill(plan, tekiPlan, after, requests, math.min(MAX_PER_TICK, CAP - simTotal(sim)), function(id, want)
		if not simCanPop(sim, id) then
			return 0
		end
		simButai(sim, id).present += want
		return want
	end)
	expect(simTotal(sim) <= CAP).toBe(true)
	return plan, GeninKotai.hojuStopped(plan, requests), returns
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
	expect(sim.requests.counts.M).toBe(nil)
end)

test(
	"模擬: 視界の外に出せるようになると、敵軍から step ずつ枠を返させて味方軍を出す",
	function()
		local sim = newSim(ONE, {
			{ id = "M", gun = "Mikatagun", x = 0, z = 110, heisu = 40, present = 0 },
			{ id = "T", gun = "Tekigun", x = 0, z = -110, heisu = 60, present = 40 },
		})
		local history = {}
		for _ = 1, 6 do
			simStep(sim)
			table.insert(history, presentOf(sim))
		end
		-- 求めは 2 のまま。出た味方軍の分だけ押さえている数が増えるので、1回の判断で返すのは 2 体ずつ
		expect(history).toEqual({
			{ M = 2, T = 38 },
			{ M = 4, T = 36 },
			{ M = 6, T = 34 },
			{ M = 8, T = 32 },
			{ M = 10, T = 30 },
			{ M = 10, T = 30 },
		})
		expect(sim.requests.counts.M).toBe(nil)
	end
)

test(
	"模擬: 片方の敵軍の部隊だけが視界の中なら、もう片方の視界の外の個体から返し、味方軍は待たずに出る",
	function()
		-- T1 は視界の中で戦っていて、T2 は遠くで控える（視界によらず出し入れできる）
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
		local history = {}
		for _ = 1, 6 do
			simStep(sim)
			table.insert(history, presentOf(sim))
		end
		-- T1 の目標は 15 まで下がるが、視界の中の T1 は消さず、T2 から目標より多く返す
		expect(history).toEqual({
			{ M = 2, T1 = 20, T2 = 18 },
			{ M = 4, T1 = 20, T2 = 16 },
			{ M = 6, T1 = 20, T2 = 14 },
			{ M = 8, T1 = 20, T2 = 12 },
			{ M = 10, T1 = 20, T2 = 10 },
			{ M = 10, T1 = 20, T2 = 10 },
		})
		expect(sim.requests.counts.M).toBe(nil)
	end
)

-- 視界の中で戦っている T1 と T2 が 20 体ずつ出たところへ、味方軍の部隊 M が近づく。
-- まとまりの敵軍の個体はすべて視界の中で戻せないので、味方軍は出られずに待つ。求めは 2 のまま増えない
local function waitingSim(): Sim
	local sim = newSim(ONE, {
		{ id = "M", gun = "Mikatagun", x = 0, z = 400, heisu = 40, present = 0 },
		{ id = "T1", gun = "Tekigun", x = 0, z = -30, heisu = 30, present = 0 },
		{ id = "T2", gun = "Tekigun", x = 30, z = -30, heisu = 30, present = 0 },
	})
	for _ = 1, 5 do
		simStep(sim)
	end
	expect(presentOf(sim)).toEqual({ M = 0, T1 = 20, T2 = 20 })
	sim.seen.T1 = true
	sim.seen.T2 = true
	simButai(sim, "M").z = 110
	local stopped
	for _ = 1, 6 do
		_, stopped = simStep(sim)
		expect(sim.requests.counts.M).toBe(2)
	end
	expect(presentOf(sim)).toEqual({ M = 0, T1 = 20, T2 = 20 })
	expect(stopped).toEqual({ true })
	return sim
end

test(
	"模擬: 敵軍を戻せない間は味方軍が待って補充を止め、撃破で空いた枠は味方軍に先に回り、視界の外で残りが返る",
	function()
		local sim = waitingSim()
		-- 待っている間は、判断を重ねても視界の中の敵軍を消さず、求めも増やさない
		for _ = 1, 4 do
			simStep(sim)
		end
		expect(presentOf(sim)).toEqual({ M = 0, T1 = 20, T2 = 20 })
		expect(sim.requests.counts.M).toBe(2)

		-- T1 を3体倒すと、空いた枠は味方軍に回り、敵軍は補充しない。倒して前の返却が済んだので、求めは1段だけ増える
		simKill(sim, "T1", 3)
		local _, stopped = simStep(sim)
		expect(presentOf(sim)).toEqual({ M = 3, T1 = 17, T2 = 20 })
		expect(sim.requests.counts.M).toBe(4)
		expect(stopped).toEqual({ true })
		simStep(sim)
		expect(presentOf(sim)).toEqual({ M = 3, T1 = 17, T2 = 20 })
		expect(sim.requests.counts.M).toBe(4)

		-- 視界の外を向くと、遠い T2 の個体から返し、味方軍が目標まで出る。部隊ごとの目標とずれても補充はしない
		sim.seen.T1 = false
		sim.seen.T2 = false
		simStep(sim)
		expect(presentOf(sim)).toEqual({ M = 7, T1 = 17, T2 = 16 })
		simStep(sim)
		expect(presentOf(sim)).toEqual({ M = 10, T1 = 17, T2 = 13 })
		_, stopped = simStep(sim)
		expect(presentOf(sim)).toEqual({ M = 10, T1 = 17, T2 = 13 })
		expect(sim.requests.counts.M).toBe(nil)
		expect(stopped).toEqual({ false })
	end
)

test(
	"模擬: 待っている間に味方軍の部隊が離れたら、求めを消し、視界の外になった敵軍を補充する",
	function()
		local sim = waitingSim()
		simKill(sim, "T1", 3)
		simStep(sim)
		expect(presentOf(sim)).toEqual({ M = 3, T1 = 17, T2 = 20 })
		simButai(sim, "M").z = 400
		local _, stopped = simStep(sim)
		expect(sim.requests.counts.M).toBe(nil)
		expect(stopped).toEqual({ false })
		expect(presentOf(sim)).toEqual({ M = 0, T1 = 17, T2 = 20 })
		-- 視界の中の間は出せず、視界の外になったら枠まで補充する
		sim.seen.T1 = false
		sim.seen.T2 = false
		simStep(sim)
		expect(presentOf(sim)).toEqual({ M = 0, T1 = 19, T2 = 21 })
	end
)

test(
	"模擬: 味方軍の部隊の兵数が減って、目標が出ている数まで下がったら求めを外す",
	function()
		local sim = waitingSim()
		simKill(sim, "T1", 3)
		simStep(sim)
		expect(presentOf(sim)).toEqual({ M = 3, T1 = 17, T2 = 20 })
		-- 交戦などで兵数が出ている数まで減ると、目標も出ている数に下がり、足りない数が 0 になる
		simButai(sim, "M").heisu = 3
		local _, stopped = simStep(sim)
		expect(sim.requests.counts.M).toBe(nil)
		expect(stopped).toEqual({ false })
		expect(presentOf(sim)).toEqual({ M = 3, T1 = 17, T2 = 20 })
	end
)

test(
	"模擬: 求めた後に味方軍の周りが視界の中になると求めを取り下げ、倒された敵軍を補充する（減り続けない）",
	function()
		local sim = newSim(ONE, {
			{ id = "M", gun = "Mikatagun", x = 0, z = 110, heisu = 40, present = 0 },
			{ id = "T", gun = "Tekigun", x = 0, z = -110, heisu = 200, present = 40 },
		})
		simStep(sim)
		expect(presentOf(sim)).toEqual({ M = 2, T = 38 })
		expect(sim.requests.counts.M).toBe(2)
		-- M の周りが視界の中になり、出せなくなる。その後も T を 2 体ずつ倒し続ける
		sim.seen.M = true
		for _ = 1, 6 do
			simKill(sim, "T", 2)
			local _, stopped = simStep(sim)
			expect(sim.requests.counts.M).toBe(nil)
			expect(stopped).toEqual({ false })
			expect(presentOf(sim)).toEqual({ M = 2, T = 38 })
		end
		-- また出せるようになったら、step から積み直す
		sim.seen.M = false
		simStep(sim)
		expect(sim.requests.counts.M).toBe(2)
		expect(presentOf(sim)).toEqual({ M = 4, T = 36 })
	end
)

test(
	"模擬: 同じまとまりのほかの味方軍の多い分が視界の中に残る間は、求めを出さず、敵軍の補充も止めない",
	function()
		-- m2 の目標は 2 だが、10 体が視界の中で戻せない。m1 は出せる位置があっても、まとまりの味方軍の枠に空きが無い
		local sim = newSim(ONE, {
			{ id = "m1", gun = "Mikatagun", x = 0, z = 110, heisu = 30, present = 0 },
			{ id = "m2", gun = "Mikatagun", x = 0, z = 30, heisu = 10, present = 10 },
			{ id = "T", gun = "Tekigun", x = 0, z = -110, heisu = 200, present = 30 },
		})
		sim.seen.m2 = true
		for round = 1, 6 do
			if round > 2 then
				simKill(sim, "T", 2)
			end
			local _, stopped = simStep(sim)
			expect(sim.requests.counts.m1).toBe(nil)
			expect(stopped).toEqual({ false })
			-- 多い分は押さえている数に数え、T は枠 30 まで補充する
			expect(presentOf(sim)).toEqual({ m1 = 0, m2 = 10, T = 30 })
		end
	end
)

test(
	"模擬: 視界の中に多い味方軍が残っても、同じまとまりの敵軍が返し、ほかのまとまりの敵軍は枠まで出る",
	function()
		local sim = newSim({ { id = "A", x = 0, z = 0 } }, {
			{ id = "M", gun = "Mikatagun", x = 0, z = 30, heisu = 40, present = 0 },
			{ id = "TA", gun = "Tekigun", x = 0, z = -110, heisu = 60, present = 0 },
			{ id = "TB", gun = "Tekigun", x = 500, z = -110, heisu = 60, present = 0 },
		})
		for _ = 1, 8 do
			simStep(sim)
		end
		expect(presentOf(sim)).toEqual({ M = 10, TA = 30, TB = 0 })
		-- 離れた B が入ると A の取り分は 20、味方軍の目標は 5 に下がるが、M の 10 体は視界の中で戻せない
		table.insert(sim.members, { id = "B", x = 500, z = 0 })
		sim.seen.M = true
		local plan
		for _ = 1, 3 do
			plan = simStep(sim)
		end
		expect(plan.mikataTargets.M).toBe(5)
		-- A の視界の外の TA が多い分も返し（敵軍の枠 20 − 10）、B の TB は枠 20 まで出る
		expect(presentOf(sim)).toEqual({ M = 10, TA = 10, TB = 20 })
	end
)

test(
	"模擬: 敵軍を返せない間に待った後、返せるようになっても1回の判断で返すのは step ずつ",
	function()
		local sim = newSim(ONE, {
			{ id = "M", gun = "Mikatagun", x = 0, z = 110, heisu = 40, present = 0 },
			{ id = "T", gun = "Tekigun", x = 0, z = -30, heisu = 60, present = 40 },
		})
		sim.seen.T = true
		for _ = 1, 6 do
			simStep(sim)
		end
		expect(sim.requests.counts.M).toBe(2)
		expect(presentOf(sim)).toEqual({ M = 0, T = 40 })
		sim.seen.T = false
		local returned = {}
		for _ = 1, 6 do
			local before = simButai(sim, "T").present
			simStep(sim)
			table.insert(returned, before - simButai(sim, "T").present)
		end
		expect(returned).toEqual({ 2, 2, 2, 2, 2, 0 })
		expect(presentOf(sim)).toEqual({ M = 10, T = 30 })
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
	"模擬: 待っている味方軍の部隊が別のまとまりへ移っても、移った先の敵軍は step ずつ返す",
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
		-- A の近くで、TA が視界の中で戻せないので待つ
		sim.seen.TA = true
		local m = simButai(sim, "M")
		m.x = -110
		for _ = 1, 3 do
			simStep(sim)
		end
		expect(sim.requests.counts.M).toBe(2)
		expect(sim.requests.members.M).toEqual({ "A" })
		expect(presentOf(sim)).toEqual({ M = 0, TA = 20, TB = 20 })
		-- B の近くへ移ると、B の敵軍が 2 体ずつ返す
		m.x = 410
		local history = {}
		for _ = 1, 4 do
			simStep(sim)
			table.insert(history, presentOf(sim))
		end
		expect(sim.requests.members.M).toBe(nil)
		expect(history).toEqual({
			{ M = 2, TA = 20, TB = 18 },
			{ M = 4, TA = 20, TB = 16 },
			{ M = 5, TA = 20, TB = 15 },
			{ M = 5, TA = 20, TB = 15 },
		})
	end
)

test(
	"模擬: メンバーが合流しただけなら、待っている味方軍の求めと補充の停止は続く",
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
		expect(sim.requests.counts.M).toBe(2)
		-- B が A の近くへ来て同じまとまりになる（メンバーは A から A・B に変わる）
		table.insert(sim.members, { id = "B", x = 30, z = 0 })
		local plan, stopped = simStep(sim)
		expect(plan.groups[1].members).toEqual({ "A", "B" })
		expect(sim.requests.counts.M).toBe(2)
		expect(sim.requests.members.M).toEqual({ "A", "B" })
		expect(stopped).toEqual({ true })
		expect(presentOf(sim)).toEqual({ M = 0, T = 40 })
	end
)

test(
	"模擬: どんな場面でも、出ている総数は 40 以下で、視界の中の近い部隊の個体は判断で増えも減りもせず、求めも持たず、"
		.. "味方軍の枠を空けるためには視界の中の個体を戻さない",
	function()
		local nextNumber = random(91)
		for _ = 1, 60 do
			local members = {}
			for index = 1, 1 + math.floor(nextNumber(3)) do
				table.insert(members, { id = `P{index}`, x = nextNumber(400), z = nextNumber(400) })
			end
			local butai: { SimButai } = {}
			for index = 1, 2 + math.floor(nextNumber(5)) do
				local gun: Gun.Gun = if nextNumber(3) < 1 then "Mikatagun" else "Tekigun"
				table.insert(butai, {
					id = `b{index}`,
					gun = gun,
					x = nextNumber(400),
					z = nextNumber(400),
					heisu = 10 + math.floor(nextNumber(50)),
					present = 0,
				})
			end
			local sim = newSim(members, butai)
			for _ = 1, 30 do
				-- 視界と位置をときどき変え、ときどき倒す
				for _, entry in sim.butai do
					if nextNumber(5) < 1 then
						sim.seen[entry.id] = not sim.seen[entry.id]
					end
					if nextNumber(5) < 1 then
						sim.farSeen[entry.id] = not sim.farSeen[entry.id]
					end
					if nextNumber(10) < 1 then
						entry.x, entry.z = nextNumber(400), nextNumber(400)
					end
					if entry.present > 0 and nextNumber(6) < 1 then
						simKill(sim, entry.id, 1)
					end
				end
				local before = presentOf(sim)
				-- simStep は、判断の後の総数が 40 以下かも確かめる
				local _, _, returns = simStep(sim)
				for _, report in returns do
					-- 視界の中で近い個体は戻さない。視界の中の遠い個体を戻すのは、味方軍によらない分（normal）だけ
					expect(report.near).toBe(0)
					expect(report.reclaimed <= report.reclaim).toBe(true)
					expect(report.picked - report.reclaimed <= report.normal).toBe(true)
					expect(report.onScreen <= report.picked - report.reclaimed).toBe(true)
				end
				for _, entry in sim.butai do
					if sim.seen[entry.id] then
						expect(entry.present).toBe(before[entry.id])
						-- 今出せない（周りが視界の中の）味方軍の部隊は、求めを持たない
						expect(sim.requests.counts[entry.id]).toBe(nil)
					end
				end
			end
		end
	end
)

-- 枠の返却で、遠くても視界の中の敵軍の個体を消さない（#82 の承認済みの仕様。canPop・canReclaim・returnCounts・pickGroupReturns）

test(
	"出し入れの決まりは、視界の外か遠ければよく、味方軍の枠のための返却は視界の外だけ",
	function()
		expect(GeninKotai.canPop(false, false)).toBe(true)
		expect(GeninKotai.canPop(false, true)).toBe(true)
		expect(GeninKotai.canPop(true, true)).toBe(true)
		expect(GeninKotai.canPop(true, false)).toBe(false)
		expect(GeninKotai.canReclaim(false)).toBe(true)
		-- 遠くても視界の中なら、味方軍の枠のためには戻さない
		expect(GeninKotai.canReclaim(true)).toBe(false)
	end
)

-- 1人の近くに味方軍の部隊 M と敵軍の部隊 T がいるまとまり。M の出ている数と返却の求め、T の出ている数で計画を作る
local function reclaimPlan(mikataPresent: number, request: number?): (GeninKotai.WakuPlan, GeninKotai.TekiPlan)
	local plan = planOf({ mikata("M", 0, 60, 40, mikataPresent), teki("T", 0, -110, 60) })
	local held = GeninKotai.heldOf(plan, { M = mikataPresent }, { M = request })
	return plan, GeninKotai.tekiTargets(plan, held)
end

test(
	"戻す数は、味方軍によらない分（normal）と、味方軍の枠を空ける分（reclaim）に分け、倒れかけは normal から先に引く",
	function()
		-- 味方軍が押さえていなければ、枠 40 を超えた分だけが normal
		local plan, tekiPlan = reclaimPlan(0, nil)
		expect(tekiPlan.targets.T).toBe(40)
		expect({ GeninKotai.returnCounts(plan, tekiPlan, 1, 40, 0) }).toEqual({ 0, 0 })
		expect({ GeninKotai.returnCounts(plan, tekiPlan, 1, 45, 0) }).toEqual({ 5, 0 })
		-- 返却の求め 2 で敵軍の目標が 38 になった分は reclaim
		plan, tekiPlan = reclaimPlan(0, 2)
		expect(tekiPlan.targets.T).toBe(38)
		expect({ GeninKotai.returnCounts(plan, tekiPlan, 1, 40, 0) }).toEqual({ 0, 2 })
		-- 両方が重なれば、枠を超えた分が normal、残りが reclaim
		expect({ GeninKotai.returnCounts(plan, tekiPlan, 1, 45, 0) }).toEqual({ 5, 2 })
		-- 倒れかけ 3 体は normal から先に引く
		expect({ GeninKotai.returnCounts(plan, tekiPlan, 1, 45, 3) }).toEqual({ 2, 2 })
		-- normal を超える倒れかけは reclaim を減らす
		expect({ GeninKotai.returnCounts(plan, tekiPlan, 1, 41, 2) }).toEqual({ 0, 1 })
		-- 目標以下なら戻さない。まとまりが無ければ 0
		expect({ GeninKotai.returnCounts(plan, tekiPlan, 1, 30, 0) }).toEqual({ 0, 0 })
		expect({ GeninKotai.returnCounts(plan, tekiPlan, 2, 40, 0) }).toEqual({ 0, 0 })
	end
)

-- 視界と遠さを添えた候補。seen は視界の中、far はメンバー全員から PopDistance より遠い
type Looked = { label: string, seen: boolean, far: boolean }

local function lookedOf(
	label: string,
	distance: number,
	seen: boolean,
	far: boolean
): GeninKotai.ReturnCandidate<Looked>
	return { item = { label = label, seen = seen, far = far }, butai = "T", distance = distance }
end

local function labelsOf(picked: { GeninKotai.ReturnCandidate<Looked> }): { string }
	local labels = {}
	for _, candidate in picked do
		table.insert(labels, candidate.item.label)
	end
	return labels
end

test(
	"味方軍の枠を空ける分は、遠くても視界の中の個体を選ばず、視界の外の個体から遠い順に選ぶ。味方軍によらない分は遠ければ視界の中でも選ぶ",
	function()
		local candidates = {
			lookedOf("遠い視界の中", 110, true, true),
			lookedOf("視界の外60", 60, false, false),
			lookedOf("近い視界の中", 20, true, false),
			lookedOf("視界の外10", 10, false, false),
		}
		local seenCalls, farCalls = 0, 0
		local function isSeen(candidate: GeninKotai.ReturnCandidate<Looked>): boolean
			seenCalls += 1
			return candidate.item.seen
		end
		local function isFar(candidate: GeninKotai.ReturnCandidate<Looked>): boolean
			farCalls += 1
			return candidate.item.far
		end
		-- 味方軍の枠を空ける分だけ。一番遠い個体は視界の中なので選ばない（直す前は、遠いので選んでいた）
		local picked, reclaimed = GeninKotai.pickGroupReturns(candidates, 0, 2, isSeen, isFar)
		expect(labelsOf(picked)).toEqual({ "視界の外60", "視界の外10" })
		expect(reclaimed).toBe(2)
		-- 視界の外の個体が足りなければ、選べる分だけ（残りは味方軍が待つ）
		picked, reclaimed = GeninKotai.pickGroupReturns(candidates, 0, 3, isSeen, isFar)
		expect(labelsOf(picked)).toEqual({ "視界の外60", "視界の外10" })
		expect(reclaimed).toBe(2)
		-- 味方軍によらない分だけなら、出し入れの決まりで、遠い視界の中の個体から選ぶ
		picked, reclaimed = GeninKotai.pickGroupReturns(candidates, 2, 0, isSeen, isFar)
		expect(labelsOf(picked)).toEqual({ "遠い視界の中", "視界の外60" })
		expect(reclaimed).toBe(0)
		-- 両方なら、味方軍の枠を空ける分を先に視界の外から選び、味方軍によらない分に遠い視界の中の個体を回す
		picked, reclaimed = GeninKotai.pickGroupReturns(candidates, 1, 1, isSeen, isFar)
		expect(labelsOf(picked)).toEqual({ "遠い視界の中", "視界の外60" })
		expect(reclaimed).toBe(1)
		picked, reclaimed = GeninKotai.pickGroupReturns(candidates, 1, 3, isSeen, isFar)
		expect(labelsOf(picked)).toEqual({ "遠い視界の中", "視界の外60", "視界の外10" })
		expect(reclaimed).toBe(2)
		-- 近い視界の中の個体は、どちらでも選ばない
		picked = GeninKotai.pickGroupReturns(candidates, 4, 0, isSeen, isFar)
		expect(labelsOf(picked)).toEqual({ "遠い視界の中", "視界の外60", "視界の外10" })
		-- 視界は候補ごとに1回だけ確かめ、遠さは視界の中の候補にだけ確かめる
		seenCalls, farCalls = 0, 0
		GeninKotai.pickGroupReturns(candidates, 4, 4, isSeen, isFar)
		expect(seenCalls).toBe(4)
		expect(farCalls).toBe(2)
		expect(#GeninKotai.pickGroupReturns(candidates, 0, 0, isSeen, isFar)).toBe(0)
	end
)

test(
	"模擬: 味方軍が来ても、遠く（PopDistance より先）で視界の中の敵軍の個体は枠のために消さず、視界の外になってから2体ずつ返す",
	function()
		-- T はメンバーから 110 先で、視界の中（遠いので、出し入れの決まりでは出せる）
		local sim = newSim(ONE, {
			{ id = "M", gun = "Mikatagun", x = 0, z = 400, heisu = 40, present = 0 },
			{ id = "T", gun = "Tekigun", x = 0, z = -110, heisu = 60, present = 0 },
		})
		sim.farSeen.T = true
		for _ = 1, 5 do
			simStep(sim)
		end
		expect(presentOf(sim)).toEqual({ M = 0, T = 40 })
		-- 味方軍の部隊が近づき、視界の外に出せるので、枠の返却を求める
		simButai(sim, "M").z = 60
		for _ = 1, 6 do
			local _, stopped, returns = simStep(sim)
			-- 求めは 2 のまま。敵軍の補充を止めて待ち、遠い視界の中の T は消さない
			expect(sim.requests.counts.M).toBe(2)
			expect(stopped).toEqual({ true })
			expect(returns[1].reclaim).toBe(2)
			expect(returns[1].normal).toBe(0)
			expect(returns[1].picked).toBe(0)
		end
		expect(presentOf(sim)).toEqual({ M = 0, T = 40 })
		-- T が視界の外になれば、2体ずつ返して味方軍を出す
		sim.farSeen.T = false
		local history = {}
		for _ = 1, 6 do
			simStep(sim)
			table.insert(history, presentOf(sim))
		end
		expect(history).toEqual({
			{ M = 2, T = 38 },
			{ M = 4, T = 36 },
			{ M = 6, T = 34 },
			{ M = 8, T = 32 },
			{ M = 10, T = 30 },
			{ M = 10, T = 30 },
		})
		expect(sim.requests.counts.M).toBe(nil)
	end
)

test(
	"模擬: 味方軍によらない返却（まとまりの枠が減った分）は、今までどおり遠ければ視界の中でも戻し、近い視界の中は戻さない",
	function()
		local function run(farSeen: boolean): { [string]: number }
			local sim = newSim({ { id = "A", x = 0, z = 0 } }, {
				{ id = "TA", gun = "Tekigun", x = 0, z = -110, heisu = 60, present = 0 },
				{ id = "TB", gun = "Tekigun", x = 500, z = -110, heisu = 60, present = 0 },
			})
			for _ = 1, 5 do
				simStep(sim)
			end
			expect(presentOf(sim)).toEqual({ TA = 40, TB = 0 })
			-- 離れた2人目が来て取り分が 20 ずつになる。TA の 20 体は味方軍によらない返却
			table.insert(sim.members, { id = "B", x = 500, z = 0 })
			if farSeen then
				sim.farSeen.TA = true
			else
				sim.seen.TA = true
			end
			local _, _, returns = simStep(sim)
			expect(returns[1].normal + returns[2].normal).toBe(20)
			expect(returns[1].reclaim + returns[2].reclaim).toBe(0)
			return presentOf(sim)
		end
		-- 遠い視界の中の TA は、出し入れの決まりで1回の判断で 20 体戻る
		expect(run(true).TA).toBe(20)
		-- 近い視界の中なら戻さない
		expect(run(false).TA).toBe(40)
	end
)

test(
	"サービスの returnExcess と popSafe は、この決まりの関数（returnCounts・pickGroupReturns・canPop）で決めている",
	function()
		-- 実サービス（GeninKotaiService.luau）が、ここで確かめた関数を通して個体を戻していることを確かめる。
		-- 味方軍の枠のための返却に、遠ければ視界の中でも戻す popSafe を直接使っていた不具合を防ぐ
		local source = testkit.readFile("src/server/Services/GeninKotaiService.luau") :: string
		expect(source ~= nil).toBe(true)
		local function bodyOf(name: string): string
			local start = string.find(source, `local function {name}(`, 1, true)
			expect(start ~= nil).toBe(true)
			local finish = string.find(source, "\nlocal function ", (start :: number) + 1, true) or #source
			return string.sub(source, start :: number, finish)
		end
		local returnExcess = bodyOf("returnExcess")
		expect(string.find(returnExcess, "GeninKotai.returnCounts(", 1, true) ~= nil).toBe(true)
		expect(string.find(returnExcess, "GeninKotai.pickGroupReturns(", 1, true) ~= nil).toBe(true)
		expect(string.find(returnExcess, "GeninKotai.pickReturns(", 1, true)).toBe(nil)
		expect(string.find(returnExcess, "popSafe(candidate", 1, true)).toBe(nil)
		expect(string.find(bodyOf("popSafe"), "GeninKotai.canPop(", 1, true) ~= nil).toBe(true)
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
