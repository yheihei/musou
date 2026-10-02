--!strict
local Config = require("../Config")
local GeninSim = require("./GeninSim")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

local P = Config.GeninProto

-- 毎回同じ数を返す乱数（角度 0、半径は下限と上限の中間）
local function fixedRand(): number
	return 0.5
end

local function one(x: number, z: number): GeninSim.Genin
	local list = GeninSim.create(1, { x = 0, z = 0 }, fixedRand)
	local genin = list[1]
	genin.x, genin.z = x, z
	return genin
end

test("指定した数を、中心から湧かせる距離の輪の上に作る", function()
	local list = GeninSim.create(30, { x = 100, z = -50 }, math.random)
	expect(#list).toBe(30)
	for _, genin in list do
		local dx, dz = genin.x - 100, genin.z + 50
		local distance = math.sqrt(dx * dx + dz * dz)
		expect(distance >= P.SpawnRadiusMin - 1e-6 and distance <= P.SpawnRadiusMax + 1e-6).toBe(true)
		expect(genin.state).toBe("Move")
	end
end)

test("目標へ歩く速さで近づき、攻撃の間合いで止まる", function()
	local genin = one(0, 50)
	GeninSim.stepOne(genin, { { x = 0, z = 0 } }, 1, 0, fixedRand)
	expect(genin.z).toBeNear(50 - P.WalkSpeed)
	expect(genin.state).toBe("Move")
	GeninSim.stepOne(genin, { { x = 0, z = 0 } }, 100, 1, fixedRand)
	expect(genin.z).toBeNear(P.AttackRange)
end)

test(
	"間合いに入ったら攻撃し、攻撃の長さが過ぎたら戻り、間隔をあけて次を出す",
	function()
		local genin = one(0, P.AttackRange)
		GeninSim.stepOne(genin, { { x = 0, z = 0 } }, 0.1, 10, fixedRand)
		expect(genin.state).toBe("Attack")
		GeninSim.stepOne(genin, { { x = 0, z = 0 } }, P.AttackTime, 10 + P.AttackTime, fixedRand)
		expect(genin.state).toBe("Move")
		GeninSim.stepOne(genin, { { x = 0, z = 0 } }, 0.1, 10.5, fixedRand)
		expect(genin.state).toBe("Move")
		GeninSim.stepOne(genin, { { x = 0, z = 0 } }, 0.1, 10 + P.AttackCooldown, fixedRand)
		expect(genin.state).toBe("Attack")
	end
)

test("薙ぎ払いの半径の中の下忍だけを外へ吹き飛ばす", function()
	local near = one(0, 5)
	local far = one(0, P.SweepRadius + 5)
	expect(GeninSim.sweep({ near, far }, { x = 0, z = 0 })).toBe(1)
	expect(near.state).toBe("Knockback")
	expect(far.state).toBe("Move")
	GeninSim.stepOne(near, {}, P.KnockbackTime / 2, 0, fixedRand)
	expect(near.z).toBeNear(5 + P.KnockbackDistance / 2)
	expect(near.y).toBeNear(P.KnockbackHeight)
	GeninSim.stepOne(near, {}, P.KnockbackTime, 0, fixedRand)
	expect(near.z).toBeNear(5 + P.KnockbackDistance)
	expect(near.y).toBe(0)
	expect(near.state).toBe("Move")
end)

test(
	"当たった回数が上限に届くと、吹き飛んだ後に倒れ、消えてから目標の近くに湧き直す",
	function()
		local genin = one(0, 5)
		genin.hits = P.MaxHits - 1
		GeninSim.sweep({ genin }, { x = 0, z = 0 })
		GeninSim.stepOne(genin, {}, P.KnockbackTime, 0, fixedRand)
		expect(genin.state).toBe("Down")
		GeninSim.stepOne(genin, {}, P.DownTime, 0, fixedRand)
		expect(genin.state).toBe("Hidden")
		GeninSim.stepOne(genin, { { x = 300, z = 0 } }, P.RespawnDelay, 0, fixedRand)
		expect(genin.state).toBe("Move")
		expect(genin.hits).toBe(0)
		local dx = genin.x - 300
		local distance = math.sqrt(dx * dx + genin.z * genin.z)
		expect(distance).toBeNear((P.SpawnRadiusMin + P.SpawnRadiusMax) / 2)
	end
)

test("吹き飛んでいる下忍と倒れた下忍には、薙ぎ払いが当たらない", function()
	local flying = one(0, 5)
	GeninSim.sweep({ flying }, { x = 0, z = 0 })
	expect(GeninSim.sweep({ flying }, { x = 0, z = 0 })).toBe(0)
	expect(flying.hits).toBe(1)
end)

test("状態と番号は行き来できる", function()
	for _, state in GeninSim.states do
		expect(GeninSim.stateOf(GeninSim.codeOf(state))).toBe(state)
	end
	expect(GeninSim.stateOf(99)).toBe("Hidden")
end)
