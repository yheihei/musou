--!strict
local Actions = require("./Actions")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

test("定義した行動は正しい値として受け付ける", function()
	for _, action in { "Attack", "ChargeKogeki", "Guard", "KinkyuKaihi", "Ougi", "Hikei" } do
		expect(Actions.isValid(action)).toBe(true)
	end
end)

test("定義にない文字列は拒否する", function()
	expect(Actions.isValid("Jump")).toBe(false)
	expect(Actions.isValid("")).toBe(false)
	expect(Actions.isValid("attack")).toBe(false)
end)

test("改名前の行動名は拒否する", function()
	expect(Actions.isValid("Charge")).toBe(false)
	expect(Actions.isValid("Musou")).toBe(false)
end)

test("文字列以外の値は拒否する", function()
	expect(Actions.isValid(nil)).toBe(false)
	expect(Actions.isValid(1)).toBe(false)
	expect(Actions.isValid({ "Attack" })).toBe(false)
	expect(Actions.isValid(true)).toBe(false)
end)

test("引数の無い行動は、余分な引数が来ても受け付ける", function()
	expect(Actions.validate("Attack")).toBe(true)
	expect(Actions.validate("ChargeKogeki", "extra")).toBe(true)
	expect(Actions.validate("Ougi", { 1 })).toBe(true)
end)

test("ガードは押したか離したかの真偽値だけを受け付ける", function()
	expect(Actions.validate("Guard", true)).toBe(true)
	expect(Actions.validate("Guard", false)).toBe(true)
	expect(Actions.validate("Guard")).toBe(false)
	expect(Actions.validate("Guard", "true")).toBe(false)
	expect(Actions.validate("Guard", 1)).toBe(false)
end)

test("緊急回避は水平の長さのある方向を受け付ける", function()
	expect(Actions.validate("KinkyuKaihi", vector.create(1, 0, 0))).toBe(true)
	expect(Actions.validate("KinkyuKaihi", vector.create(0.3, 5, -0.2))).toBe(true)
end)

test("緊急回避の不正な型と長さ0の方向は拒否する", function()
	expect(Actions.validate("KinkyuKaihi")).toBe(false)
	expect(Actions.validate("KinkyuKaihi", "forward")).toBe(false)
	expect(Actions.validate("KinkyuKaihi", { x = 1, y = 0, z = 0 })).toBe(false)
	expect(Actions.validate("KinkyuKaihi", vector.create(0, 0, 0))).toBe(false)
	expect(Actions.validate("KinkyuKaihi", vector.create(0, 1, 0))).toBe(false)
	expect(Actions.validate("KinkyuKaihi", vector.create(0 / 0, 0, 1))).toBe(false)
	expect(Actions.validate("KinkyuKaihi", vector.create(math.huge, 0, 0))).toBe(false)
end)

test("緊急回避の方向は上下の成分を捨てて長さ1にする", function()
	local direction = Actions.horizontal(vector.create(3, 7, 4))
	expect(direction.x).toBeNear(0.6)
	expect(direction.y).toBe(0)
	expect(direction.z).toBeNear(0.8)
end)

test("秘計は正の整数の枚の番号を受け付け、範囲は見ない", function()
	expect(Actions.validate("Hikei", 1)).toBe(true)
	expect(Actions.validate("Hikei", 3)).toBe(true)
	expect(Actions.validate("Hikei", 99)).toBe(true)
end)

test("秘計の不正な枚の番号は拒否する", function()
	expect(Actions.validate("Hikei")).toBe(false)
	expect(Actions.validate("Hikei", 0)).toBe(false)
	expect(Actions.validate("Hikei", -1)).toBe(false)
	expect(Actions.validate("Hikei", 1.5)).toBe(false)
	expect(Actions.validate("Hikei", "1")).toBe(false)
	expect(Actions.validate("Hikei", math.huge)).toBe(false)
	expect(Actions.validate("Hikei", 0 / 0)).toBe(false)
end)

test("定義にない行動は引数によらず拒否する", function()
	expect(Actions.validate("Jump", true)).toBe(false)
	expect(Actions.validate(nil, nil)).toBe(false)
end)
