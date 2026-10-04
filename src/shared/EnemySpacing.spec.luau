--!strict
local EnemySpacing = require("./EnemySpacing")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

local PLAYER = { x = 0, z = 0 }

test("遠くの敵は、プレイヤーから見て自分の側の、手前の距離の位置へ向かう", function()
	local goal = EnemySpacing.goal({ x = 20, z = 0 }, 2, PLAYER, 4, {})
	expect(goal.point.x).toBeNear(4, 1e-9)
	expect(goal.point.z).toBeNear(0, 1e-9)
	expect(goal.distance).toBeNear(20, 1e-9)
	expect(goal.shifted).toBe(false)
	expect(EnemySpacing.shouldMove(goal, 4)).toBe(true)
end)

test("プレイヤーの中に入った敵は、手前の距離まで下がる", function()
	local goal = EnemySpacing.goal({ x = 0, z = 1 }, 2, PLAYER, 4, {})
	expect(goal.point.x).toBeNear(0, 1e-9)
	expect(goal.point.z).toBeNear(4, 1e-9)
	expect(EnemySpacing.shouldMove(goal, 4)).toBe(true)
end)

test("プレイヤーとまったく同じ位置の敵も、手前の距離まで下がる", function()
	local goal = EnemySpacing.goal({ x = 0, z = 0 }, 2, PLAYER, 4, {})
	local dx, dz = goal.point.x, goal.point.z
	expect(math.sqrt(dx * dx + dz * dz)).toBeNear(4, 1e-9)
end)

test("止まる位置の近くにいて、ほかの敵と重なっていなければ歩かない", function()
	local goal = EnemySpacing.goal({ x = 4.5, z = 0 }, 2, PLAYER, 4, { { x = -4, z = 0, radius = 2 } })
	expect(goal.shifted).toBe(false)
	expect(EnemySpacing.shouldMove(goal, 4)).toBe(false)
end)

test("近くの敵と体が重なっていたら、重なった分だけ離れる向きへずらす", function()
	local goal = EnemySpacing.goal({ x = 4, z = 1 }, 2, PLAYER, 4, { { x = 4, z = -1, radius = 2 } })
	expect(goal.shifted).toBe(true)
	-- 半径の和 4、間 2 なので、2 だけ +z へずらす
	local standX = 4 / math.sqrt(17) * 4
	local standZ = 1 / math.sqrt(17) * 4
	expect(goal.point.x).toBeNear(standX, 1e-9)
	expect(goal.point.z).toBeNear(standZ + 2, 1e-9)
	expect(EnemySpacing.shouldMove(goal, 4)).toBe(true)
end)

test("同じ位置に重なった敵どうしは、プレイヤーの周りを横へずれる", function()
	local goal = EnemySpacing.goal({ x = 4, z = 0 }, 2, PLAYER, 4, { { x = 4, z = 0, radius = 2 } })
	expect(goal.shifted).toBe(true)
	expect(goal.point.x).toBeNear(4, 1e-9)
	expect(math.abs(goal.point.z)).toBeNear(4, 1e-9)
end)

test(
	"ほかの敵に内側へ押されても、プレイヤーの中心から手前の距離より内側へは行かない",
	function()
		-- 外側の敵が、プレイヤーの方へ押す位置にいる
		local goal = EnemySpacing.goal({ x = 4, z = 0 }, 2, PLAYER, 4, { { x = 6, z = 0, radius = 2 } })
		expect(goal.shifted).toBe(true)
		local dx, dz = goal.point.x, goal.point.z
		expect(math.sqrt(dx * dx + dz * dz) >= 4 - 1e-9).toBe(true)
	end
)

test("プレイヤーの中の敵が周りの敵に押されても、手前の距離まで外へ出る", function()
	local goal = EnemySpacing.goal(
		{ x = 1, z = 0 },
		2,
		PLAYER,
		4,
		{ { x = 3, z = 0, radius = 2 }, { x = 1, z = 2, radius = 2 } }
	)
	local dx, dz = goal.point.x, goal.point.z
	expect(math.sqrt(dx * dx + dz * dz) >= 4 - 1e-9).toBe(true)
end)
