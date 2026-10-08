--!strict
local CameraView = require("./CameraView")
local Config = require("./Config")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

-- Config.luau の値を調整してもテストが揺れないよう、値を固定する
local PARAMS: CameraView.Params = {
	Interval = 0.5,
	Stale = 3,
	Margin = 12,
	MaxDistance = 200,
	FallbackHeight = 2,
	FallbackFov = 70,
	FallbackAspect = 16 / 9,
}

-- 原点から北（z の -）を見るカメラ。縦の画角 70 度、横と縦の比 16:9（横の半分の角は約 51 度）
local NORTH: CameraView.View = {
	position = vector.create(0, 0, 0),
	look = vector.create(0, 0, -1),
	fovY = 70,
	aspect = 16 / 9,
}

test("正しい値は視界にし、向きを長さ 1 にする", function()
	local view = CameraView.validate(vector.create(1, 2, 3), vector.create(0, 0, -5), 70, 1.6)
	expect(view ~= nil).toBe(true)
	if view then
		expect(vector.magnitude(view.look)).toBeNear(1)
		expect(view.look.z).toBeNear(-1)
		expect(view.fovY).toBe(70)
		expect(view.aspect).toBe(1.6)
	end
end)

test("型が違う値・有限でない値・長さ 0 の向きは受け付けない", function()
	local p, l = vector.create(0, 0, 0), vector.create(0, 0, -1)
	expect(CameraView.validate("p", l, 70, 1.6)).toBe(nil)
	expect(CameraView.validate(p, { x = 0, y = 0, z = -1 }, 70, 1.6)).toBe(nil)
	expect(CameraView.validate(p, l, "70", 1.6)).toBe(nil)
	expect(CameraView.validate(p, l, 70, nil)).toBe(nil)
	expect(CameraView.validate(vector.create(0 / 0, 0, 0), l, 70, 1.6)).toBe(nil)
	expect(CameraView.validate(vector.create(math.huge, 0, 0), l, 70, 1.6)).toBe(nil)
	expect(CameraView.validate(p, vector.create(0, 0, 0), 70, 1.6)).toBe(nil)
	expect(CameraView.validate(p, vector.create(0, -math.huge, 0), 70, 1.6)).toBe(nil)
end)

test("画角と比は範囲の外と NaN を受け付けない", function()
	local p, l = vector.create(0, 0, 0), vector.create(0, 0, -1)
	expect(CameraView.validate(p, l, 0.5, 1.6)).toBe(nil)
	expect(CameraView.validate(p, l, 121, 1.6)).toBe(nil)
	expect(CameraView.validate(p, l, 0 / 0, 1.6)).toBe(nil)
	expect(CameraView.validate(p, l, 70, 0.1)).toBe(nil)
	expect(CameraView.validate(p, l, 70, 6)).toBe(nil)
	expect(CameraView.validate(p, l, 70, 0 / 0)).toBe(nil)
	expect(CameraView.validate(p, l, 1, 0.2) ~= nil).toBe(true)
	expect(CameraView.validate(p, l, 120, 5) ~= nil).toBe(true)
end)

test("正面の点は見え、後ろの点は見えない", function()
	expect(CameraView.sees(NORTH, vector.create(0, 0, -50), 0)).toBe(true)
	expect(CameraView.sees(NORTH, vector.create(0, 0, 50), 0)).toBe(false)
	-- 後ろでも、球がカメラの前へかかれば見える
	expect(CameraView.sees(NORTH, vector.create(0, 0, 5), 10)).toBe(true)
	expect(CameraView.sees(NORTH, vector.create(0, 0, 10), 10)).toBe(false)
end)

test("横は画角と比で決まる広さの内だけ見え、margin の分だけ広く見る", function()
	-- 50 先では横に 62.2 まで見える（tan 35° × 16/9 × 50）
	expect(CameraView.sees(NORTH, vector.create(60, 0, -50), 0)).toBe(true)
	expect(CameraView.sees(NORTH, vector.create(-60, 0, -50), 0)).toBe(true)
	expect(CameraView.sees(NORTH, vector.create(70, 0, -50), 0)).toBe(false)
	-- 70 の点は横の面から 4.9 外。半径 5 の球は面にかかる
	expect(CameraView.sees(NORTH, vector.create(70, 0, -50), 4.8)).toBe(false)
	expect(CameraView.sees(NORTH, vector.create(70, 0, -50), 5)).toBe(true)
	-- 真横は見えない
	expect(CameraView.sees(NORTH, vector.create(80, 0, 0), 12)).toBe(false)
end)

test("縦は縦の画角の内だけ見える", function()
	-- 50 先では上下に 35.0 まで見える（tan 35° × 50）
	expect(CameraView.sees(NORTH, vector.create(0, 34, -50), 0)).toBe(true)
	expect(CameraView.sees(NORTH, vector.create(0, 40, -50), 0)).toBe(false)
	expect(CameraView.sees(NORTH, vector.create(0, -40, -50), 0)).toBe(false)
	expect(CameraView.sees(NORTH, vector.create(0, 40, -50), 5)).toBe(true)
end)

test("真下を向いたカメラでも判定できる", function()
	local down: CameraView.View = {
		position = vector.create(0, 50, 0),
		look = vector.create(0, -1, 0),
		fovY = 70,
		aspect = 16 / 9,
	}
	expect(CameraView.sees(down, vector.create(0, 0, 0), 0)).toBe(true)
	expect(CameraView.sees(down, vector.create(0, 100, 0), 0)).toBe(false)
	expect(CameraView.sees(down, vector.create(200, 0, 0), 0)).toBe(false)
end)

test("報告が無いときは、頭の高さから体の向きの水平を見る", function()
	local view = CameraView.fromFacing(vector.create(10, 3, 10), vector.create(0, 0.5, -2), PARAMS)
	expect(view.position.y).toBeNear(5)
	expect(view.look.y).toBeNear(0)
	expect(view.look.z).toBeNear(-1)
	expect(view.fovY).toBe(70)
	-- 向きが真上なら、北を見ているとみなす
	local up = CameraView.fromFacing(vector.create(0, 0, 0), vector.create(0, 1, 0), PARAMS)
	expect(up.look.z).toBeNear(-1)
end)

test("どれかの視界に入れば見えている", function()
	local south: CameraView.View = {
		position = vector.create(0, 0, 0),
		look = vector.create(0, 0, 1),
		fovY = 70,
		aspect = 16 / 9,
	}
	expect(CameraView.seenByAny({ NORTH, south }, vector.create(0, 0, 50), 0)).toBe(true)
	expect(CameraView.seenByAny({ NORTH }, vector.create(0, 0, 50), 0)).toBe(false)
	expect(CameraView.seenByAny({}, vector.create(0, 0, 50), 0)).toBe(false)
end)

test("Config の値は受け付ける範囲に収まる", function()
	local p = Config.CameraView
	expect(p.FallbackFov >= CameraView.MIN_FOV and p.FallbackFov <= CameraView.MAX_FOV).toBe(true)
	expect(p.FallbackAspect >= CameraView.MIN_ASPECT and p.FallbackAspect <= CameraView.MAX_ASPECT).toBe(true)
	-- 報告が古くなる前に、次の報告が届く
	expect(p.Interval < p.Stale).toBe(true)
	expect(p.Margin >= 0).toBe(true)
end)
