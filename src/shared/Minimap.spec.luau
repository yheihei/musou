--!strict
local Minimap = require("./Minimap")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

test("長い辺を地図の一辺に合わせ、縦横の縮尺をそろえる", function()
	expect(Minimap.scaleOf(800, 800, 200)).toBe(0.25)
	expect(Minimap.scaleOf(1100, 1400, 280)).toBe(0.2)
	expect(Minimap.scaleOf(0, 0, 200)).toBe(0)
end)

test("範囲の中心は地図の真ん中、北は上で東は右", function()
	local scale = Minimap.scaleOf(800, 800, 200)
	local cx, cy = Minimap.toMap(-3000, 0, -3000, 0, scale, 200)
	expect(cx).toBe(100)
	expect(cy).toBe(100)
	-- 北（z の -）へ 280 スタッドは上へ 70 ピクセル
	local nx, ny = Minimap.toMap(-3000, -280, -3000, 0, scale, 200)
	expect(nx).toBe(100)
	expect(ny).toBe(30)
	-- 東（x の +）へ 220 スタッドは右へ 55 ピクセル
	local ex, ey = Minimap.toMap(-2780, 0, -3000, 0, scale, 200)
	expect(ex).toBe(155)
	expect(ey).toBe(100)
end)

test("範囲の外の位置は地図の縁に寄せる", function()
	local x, y = Minimap.clampToMap(-20, 230, 200)
	expect(x).toBe(0)
	expect(y).toBe(200)
	local insideX, insideY = Minimap.clampToMap(50, 60, 200)
	expect(insideX).toBe(50)
	expect(insideY).toBe(60)
end)

test("向きは北から時計回りの度", function()
	expect(Minimap.facingOf(0, -1)).toBeNear(0)
	expect(Minimap.facingOf(1, 0)).toBeNear(90)
	expect(Minimap.facingOf(0, 1)).toBeNear(180)
	expect(Minimap.facingOf(-1, 0)).toBeNear(270)
	expect(Minimap.facingOf(0, 0)).toBe(0)
end)
