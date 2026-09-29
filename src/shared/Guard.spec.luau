--!strict
local Config = require("./Config")
local Guard = require("./Guard")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

local v = vector.create
-- 原点に立って -Z を向いている
local POSITION = v(0, 0, 0)
local FACING = v(0, 0, -1)

local function at(degrees: number): vector
	-- 正面から右へ degrees 度の方向に 5 スタッド離れた攻撃元
	local radians = math.rad(degrees)
	return v(math.sin(radians) * 5, 0, -math.cos(radians) * 5)
end

test("正面からの攻撃は正面、背後からの攻撃は正面ではない", function()
	expect(Guard.isFront(POSITION, FACING, at(0), 140)).toBe(true)
	expect(Guard.isFront(POSITION, FACING, at(180), 140)).toBe(false)
end)

test("正面の角度の半分までが正面で、それを超えると正面ではない", function()
	expect(Guard.isFront(POSITION, FACING, at(69), 140)).toBe(true)
	expect(Guard.isFront(POSITION, FACING, at(-70), 140)).toBe(true)
	expect(Guard.isFront(POSITION, FACING, at(71), 140)).toBe(false)
	expect(Guard.isFront(POSITION, FACING, at(-90), 140)).toBe(false)
end)

test("高さの違いと向きの上下の成分は見ない", function()
	expect(Guard.isFront(POSITION, v(0, 5, -1), at(0) + v(0, 30, 0), 140)).toBe(true)
end)

test("攻撃元が重なっているときは正面とみなす", function()
	expect(Guard.isFront(POSITION, FACING, POSITION, 140)).toBe(true)
end)

test("Config の正面の角度は 0 より大きく 360 以下", function()
	expect(Config.Guard.Angle > 0).toBe(true)
	expect(Config.Guard.Angle <= 360).toBe(true)
end)
