--!strict
local HitShape = require("./HitShape")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

local v = vector.create

-- 原点に立って -Z を向いている
local ORIGIN: HitShape.Origin = { position = v(0, 0, 0), look = v(0, 0, -1) }

local function inside(shape: HitShape.Shape, origin: HitShape.Origin, position: vector, radius: number?): boolean
	local result = HitShape.test(shape, origin, position, radius)
	return result
end

local BOX: HitShape.Shape = { kind = "Box", range = 10, width = 4, height = 6 }

test("箱は前方の奥行きと幅と高さの中に当たる", function()
	expect(inside(BOX, ORIGIN, v(0, 0, -5))).toBe(true)
	expect(inside(BOX, ORIGIN, v(1.9, 2.9, -9.9))).toBe(true)
end)

test("箱の境界ちょうどは当たり、外は当たらない", function()
	expect(inside(BOX, ORIGIN, v(2, 0, -10))).toBe(true)
	expect(inside(BOX, ORIGIN, v(2.01, 0, -5))).toBe(false)
	expect(inside(BOX, ORIGIN, v(0, 0, -10.01))).toBe(false)
	expect(inside(BOX, ORIGIN, v(0, 3.01, -5))).toBe(false)
end)

test("箱は背後に当たらない", function()
	expect(inside(BOX, ORIGIN, v(0, 0, 1))).toBe(false)
end)

test("対象の半径の分だけはみ出していても当たる", function()
	expect(inside(BOX, ORIGIN, v(3, 0, -5))).toBe(false)
	expect(inside(BOX, ORIGIN, v(3, 0, -5), 1)).toBe(true)
	expect(inside(BOX, ORIGIN, v(0, 0, 0.5), 1)).toBe(true)
end)

test("向きを変えると箱も回る", function()
	local facingX: HitShape.Origin = { position = v(0, 0, 0), look = v(1, 0, 0) }
	expect(inside(BOX, facingX, v(5, 0, 0))).toBe(true)
	expect(inside(BOX, facingX, v(0, 0, -5))).toBe(false)
	-- 右は +Z になる。幅の中なら左右どちらも当たる
	expect(inside(BOX, facingX, v(5, 0, 1.9))).toBe(true)
end)

test("向きの上下の成分は無視し、真上を向いても -Z を前とする", function()
	local lookingDown: HitShape.Origin = { position = v(0, 0, 0), look = v(0, -0.9, -0.1) }
	expect(inside(BOX, lookingDown, v(0, 0, -5))).toBe(true)
	local lookingUp: HitShape.Origin = { position = v(0, 0, 0), look = v(0, 1, 0) }
	expect(inside(BOX, lookingUp, v(0, 0, -5))).toBe(true)
end)

test("原点が動くと箱も動く", function()
	local moved: HitShape.Origin = { position = v(100, 10, 100), look = v(0, 0, -1) }
	expect(inside(BOX, moved, v(100, 10, 95))).toBe(true)
	expect(inside(BOX, moved, v(0, 0, -5))).toBe(false)
end)

local SECTOR: HitShape.Shape = { kind = "Sector", radius = 10, angle = 90, height = 6 }

test("扇は開きの中の半径以内に当たる", function()
	expect(inside(SECTOR, ORIGIN, v(0, 0, -9))).toBe(true)
	expect(inside(SECTOR, ORIGIN, v(3, 0, -5))).toBe(true)
end)

test("扇の開きの境界ちょうどは当たり、外は当たらない", function()
	-- 開き 90 度なので左右 45 度まで
	local d = 5 / math.sqrt(2)
	expect(inside(SECTOR, ORIGIN, v(d, 0, -d))).toBe(true)
	expect(inside(SECTOR, ORIGIN, v(5, 0, -4.9))).toBe(false)
	expect(inside(SECTOR, ORIGIN, v(0, 0, -10))).toBe(true)
	expect(inside(SECTOR, ORIGIN, v(0, 0, -10.01))).toBe(false)
end)

test("扇は横と背後に当たらず、原点に重なる対象には当たる", function()
	expect(inside(SECTOR, ORIGIN, v(5, 0, 0))).toBe(false)
	expect(inside(SECTOR, ORIGIN, v(0, 0, 5))).toBe(false)
	expect(inside(SECTOR, ORIGIN, v(0, 0, 0.5), 1)).toBe(true)
end)

test("扇は対象の半径の分だけ開きの外にはみ出していても当たる", function()
	expect(inside(SECTOR, ORIGIN, v(5, 0, -4))).toBe(false)
	expect(inside(SECTOR, ORIGIN, v(5, 0, -4), 1)).toBe(true)
end)

test("扇は高さの外に当たらない", function()
	expect(inside(SECTOR, ORIGIN, v(0, 3.01, -5))).toBe(false)
end)

local SPHERE: HitShape.Shape = { kind = "Sphere", radius = 8 }

test("球は向きによらず半径以内に当たる", function()
	expect(inside(SPHERE, ORIGIN, v(0, 0, 7.9))).toBe(true)
	expect(inside(SPHERE, ORIGIN, v(0, 8, 0))).toBe(true)
	expect(inside(SPHERE, ORIGIN, v(8.01, 0, 0))).toBe(false)
	expect(inside(SPHERE, ORIGIN, v(9, 0, 0), 1)).toBe(true)
end)

local LINE: HitShape.Shape = { kind = "Line", length = 40, width = 2, speed = 80 }

test("直線は前方の細い範囲に当たる", function()
	expect(inside(LINE, ORIGIN, v(0, 0, -30))).toBe(true)
	expect(inside(LINE, ORIGIN, v(0.9, 0, -30))).toBe(true)
	expect(inside(LINE, ORIGIN, v(1.1, 0, -30))).toBe(false)
	expect(inside(LINE, ORIGIN, v(0, 0, -40.1))).toBe(false)
	expect(inside(LINE, ORIGIN, v(0, 0, 5))).toBe(false)
end)

test("直線は距離に応じた時間差で当たる", function()
	local hits = HitShape.query(LINE, ORIGIN, {
		{ ref = "far", position = v(0, 0, -40) },
		{ ref = "near", position = v(0, 0, -8) },
	})
	expect(#hits).toBe(2)
	expect(hits[1].ref).toBe("near")
	expect(hits[1].delay).toBeNear(8 / 80)
	expect(hits[2].delay).toBeNear(40 / 80)
end)

test("当たった対象だけを原点に近い順に返し、直線以外は時間差 0", function()
	local hits = HitShape.query(BOX, ORIGIN, {
		{ ref = 3, position = v(0, 0, -9) },
		{ ref = 1, position = v(0, 0, -1) },
		{ ref = 2, position = v(1, 0, -4) },
		{ ref = 4, position = v(0, 0, 5) },
	})
	local refs = {}
	for _, hit in hits do
		table.insert(refs, hit.ref)
		expect(hit.delay).toBe(0)
	end
	expect(refs).toEqual({ 1, 2, 3 })
end)

test("対象が無ければ空を返す", function()
	expect(HitShape.query(SPHERE, ORIGIN, {})).toEqual({})
end)

test("Config の形の定義を判定の形にし、高さを省いた形は既定の高さにする", function()
	expect(HitShape.fromDef({ Kind = "Box", Range = 7, Width = 8 }, 8)).toEqual({
		kind = "Box",
		range = 7,
		width = 8,
		height = 8,
	})
	expect(HitShape.fromDef({ Kind = "Sector", Radius = 9, Angle = 140, Height = 4 }, 8)).toEqual({
		kind = "Sector",
		radius = 9,
		angle = 140,
		height = 4,
	})
	expect(HitShape.fromDef({ Kind = "Sphere", Radius = 9 }, 8)).toEqual({ kind = "Sphere", radius = 9 })
	expect(HitShape.fromDef({ Kind = "Line", Length = 30, Width = 3, Speed = 120 }, 8)).toEqual({
		kind = "Line",
		length = 30,
		width = 3,
		speed = 120,
	})
end)

test("向きを回すと、上から見て時計回りが正になる", function()
	local right = HitShape.rotate(ORIGIN, 90)
	expect(right.look.x).toBeNear(1)
	expect(right.look.z).toBeNear(0)
	local left = HitShape.rotate(ORIGIN, -90)
	expect(left.look.x).toBeNear(-1)
	expect(HitShape.rotate(ORIGIN, 0)).toBe(ORIGIN)
	-- 右へ 15 度回した直線は、右前の対象に当たる
	local line: HitShape.Shape = { kind = "Line", length = 20, width = 1, speed = 100 }
	local target = v(math.sin(math.rad(15)) * 10, 0, -math.cos(math.rad(15)) * 10)
	expect(inside(line, ORIGIN, target)).toBe(false)
	expect(inside(line, HitShape.rotate(ORIGIN, 15), target)).toBe(true)
end)
