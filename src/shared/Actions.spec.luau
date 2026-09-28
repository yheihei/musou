--!strict
local Actions = require("./Actions")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

test("定義した行動は正しい値として受け付ける", function()
	expect(Actions.isValid(Actions.Attack)).toBe(true)
	expect(Actions.isValid(Actions.Charge)).toBe(true)
	expect(Actions.isValid(Actions.Musou)).toBe(true)
end)

test("定義にない文字列は拒否する", function()
	expect(Actions.isValid("Jump")).toBe(false)
	expect(Actions.isValid("")).toBe(false)
	expect(Actions.isValid("attack")).toBe(false)
end)

test("文字列以外の値は拒否する", function()
	expect(Actions.isValid(nil)).toBe(false)
	expect(Actions.isValid(1)).toBe(false)
	expect(Actions.isValid({ "Attack" })).toBe(false)
	expect(Actions.isValid(true)).toBe(false)
end)
