--!strict
local Characters = require("./Characters")
local Config = require("./Config")
local Motions = require("./Motions")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

test("待機と移動は Ninja パックの7種で、どれにも中のアニメーションがある", function()
	local count = 0
	for name, id in Motions.Locomotion :: any do
		count += 1
		expect(id > 0).toBe(true)
		expect(#Motions.LocomotionAnimations[name] > 0).toBe(true)
	end
	expect(count).toBe(7)
end)

test("武器種ごとの行動の項目は、Config の武器種と段の数に合っている", function()
	for bukishu, set in Config.Bukishu :: any do
		local motions = Motions.Bukishu[bukishu]
		expect(motions ~= nil).toBe(true)
		expect(#motions.Attack).toBe(#set.Attack)
		expect(#motions.ChargeKogeki).toBe(#set.ChargeKogeki)
	end
end)

test("奥義の項目は、操作キャラクターの奥義の ID と同じ", function()
	local expected: { [string]: boolean } = {}
	for _, character in Characters.definitions do
		if character.playable and character.ougi then
			expected[character.ougi] = true
		end
	end
	local actual: { [string]: boolean } = {}
	for id in Motions.Ougi do
		actual[id] = true
	end
	expect(actual).toEqual(expected)
end)

test("行動のモーションは武器種と行動と段で引き、無い項目は 0", function()
	expect(Motions.actionOf("Shuriken", "Attack", 3)).toBe(Motions.Bukishu.Shuriken.Attack[3])
	expect(Motions.actionOf("Katana", "Guard")).toBe(Motions.Bukishu.Katana.Guard)
	expect(Motions.actionOf("Katana", "Attack", 7)).toBe(0)
	expect(Motions.actionOf("Bow", "Attack", 1)).toBe(0)
	expect(Motions.actionOf("Shuriken", "Jump")).toBe(0)
end)
