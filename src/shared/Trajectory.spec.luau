--!strict
local Trajectory = require("./Trajectory")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

local v = vector.create

-- Config.luau の値を調整してもテストが揺れないよう、重力と倍率を固定する
local PARAMS: Trajectory.Params = {
	Gravity = 100,
	KnockbackLift = 0.5,
	LaunchLift = 1,
	LaunchDrift = 0.1,
	AirLift = 20,
	AirDrift = 5,
	Flinch = 0.35,
	Down = 1,
	GetUp = 0.5,
	JoninScale = 0.5,
	JoninFlinchScale = 0,
}

local EAST = v(1, 0, 0)

local function near(a: vector, b: vector)
	expect(a.x).toBeNear(b.x)
	expect(a.y).toBeNear(b.y)
	expect(a.z).toBeNear(b.z)
end

test("同じ初速なら、同じ経過時間で同じ位置を返す", function()
	local velocity = Trajectory.initialVelocity("Knockback", EAST, 40, false, 1, PARAMS) :: vector
	local a = Trajectory.new(v(0, 3, 0), velocity, PARAMS)
	local b = Trajectory.new(v(0, 3, 0), velocity, PARAMS)
	for _, t in { 0, 0.1, 0.25, 0.4 } do
		near(Trajectory.positionAt(a, t), Trajectory.positionAt(b, t))
	end
end)

test("位置は初速と重力で決まり、0 秒は飛び始めた位置", function()
	local trajectory = Trajectory.new(v(1, 2, 3), v(10, 20, 0), PARAMS)
	near(Trajectory.positionAt(trajectory, 0), v(1, 2, 3))
	-- 0.2 秒後: x = 1 + 10 × 0.2、y = 2 + 20 × 0.2 - 100 × 0.04 / 2
	near(Trajectory.positionAt(trajectory, 0.2), v(3, 4, 3))
	expect(Trajectory.velocityAt(trajectory, 0.2).y).toBeNear(0)
end)

test("吹き飛びは攻撃元から離れる向きへ飛び、少し浮く", function()
	local velocity = Trajectory.initialVelocity("Knockback", v(0, 5, -3), 40, false, 1, PARAMS) :: vector
	near(velocity, v(0, 20, -40))
end)

test("打ち上げは真上へ浮き、横へは少しだけ流れる", function()
	local velocity = Trajectory.initialVelocity("Launch", EAST, 50, false, 1, PARAMS) :: vector
	near(velocity, v(5, 50, 0))
end)

test("地上でののけぞりと反応の無い攻撃は軌道を作らない", function()
	expect(Trajectory.initialVelocity("Flinch", EAST, 8, false, 1, PARAMS)).toBe(nil)
	expect(Trajectory.initialVelocity("None", EAST, 8, true, 1, PARAMS)).toBe(nil)
	expect(Trajectory.initialVelocity("Knockback", EAST, 0, false, 1, PARAMS)).toBe(nil)
end)

test("打ち上げた敵に追撃すると、その位置から浮き直す", function()
	local launched =
		Trajectory.new(v(0, 0, 0), Trajectory.initialVelocity("Launch", EAST, 50, false, 1, PARAMS) :: vector, PARAMS)
	-- 頂点を過ぎて落ち始めたところで、のけぞりの攻撃を当てる
	local hitAt = 0.7
	expect(Trajectory.velocityAt(launched, hitAt).y < 0).toBe(true)
	local position = Trajectory.positionAt(launched, hitAt)
	local juggle =
		Trajectory.new(position, Trajectory.initialVelocity("Flinch", EAST, 8, true, 1, PARAMS) :: vector, PARAMS)
	near(Trajectory.positionAt(juggle, 0), position)
	expect(Trajectory.velocityAt(juggle, 0).y > 0).toBe(true)
	expect(Trajectory.positionAt(juggle, 0.1).y > position.y).toBe(true)
end)

test("平らな地面では、初めと同じ高さに戻ったときに着地する", function()
	local trajectory = Trajectory.new(v(0, 0, 0), v(10, 20, 0), PARAMS)
	expect(Trajectory.landingTime(trajectory, 0) :: number).toBeNear(0.4)
	expect(Trajectory.hasLanded(trajectory, 0.39, 0)).toBe(false)
	expect(Trajectory.hasLanded(trajectory, 0.4, 0)).toBe(true)
end)

test("上っている間は地面より低くても着地しない（段差の手前で止まらない）", function()
	local trajectory = Trajectory.new(v(0, 0, 0), v(10, 20, 0), PARAMS)
	expect(Trajectory.hasLanded(trajectory, 0.05, 5)).toBe(false)
	-- 頂点（高さ 2）を過ぎて落ちてくると、高さ 1 の段の上に着地する
	expect(Trajectory.hasLanded(trajectory, 0.3, 1)).toBe(false)
	expect(Trajectory.hasLanded(trajectory, 0.35, 1)).toBe(true)
end)

test("高い段には早く、低い地面には遅く着地する", function()
	local trajectory = Trajectory.new(v(0, 0, 0), v(10, 20, 0), PARAMS)
	local flat = Trajectory.landingTime(trajectory, 0) :: number
	local step = Trajectory.landingTime(trajectory, 1) :: number
	local slope = Trajectory.landingTime(trajectory, -2) :: number
	expect(step < flat).toBe(true)
	expect(slope > flat).toBe(true)
end)

test("上忍は反応を弱める倍率で、下忍より短く飛ぶ", function()
	local function distance(scale: number): number
		local velocity = Trajectory.initialVelocity("Knockback", EAST, 40, false, scale, PARAMS) :: vector
		local trajectory = Trajectory.new(v(0, 0, 0), velocity, PARAMS)
		local landing = Trajectory.landingTime(trajectory, 0) :: number
		return Trajectory.positionAt(trajectory, landing).x
	end
	local genin = distance(1)
	local jonin = distance(PARAMS.JoninScale)
	expect(jonin < genin).toBe(true)
	expect(jonin).toBeNear(genin * PARAMS.JoninScale * PARAMS.JoninScale)
end)
