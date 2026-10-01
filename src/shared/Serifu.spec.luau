--!strict
local Config = require("./Config")
local Serifu = require("./Serifu")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

test("台詞 ID から文を引け、無い ID は nil", function()
	expect(Serifu.textOf("ShikenTanshuku")).toBe("参る！")
	expect(Serifu.textOf("Nowhere")).toBe(nil)
	for id, text in Serifu.definitions do
		expect(#id > 0 and #text > 0).toBe(true)
	end
end)

test("文の長さは日本語の1文字を1と数える", function()
	expect(Serifu.length("参る！")).toBe(3)
	expect(Serifu.length("abc")).toBe(3)
end)

test("会話窓は1文字ずつ出し、長い台詞ほど送るまで長く見せる", function()
	local short = "参る！"
	expect(Serifu.typingTime(short)).toBeNear(3 * Config.Serifu.CharInterval)
	expect(Serifu.lineTime(short)).toBeNear(
		3 * Config.Serifu.CharInterval + Config.Serifu.HoldTime + 3 * Config.Serifu.HoldPerChar
	)
	local long = Serifu.textOf("ShikenNagai") :: string
	expect(Serifu.lineTime(long) > Serifu.lineTime(short)).toBe(true)
end)

test("戦闘中の台詞の順番待ちは上限を超えると古いものから捨てる", function()
	local queue = {}
	local dropped = 0
	for index = 1, Config.Serifu.BattleQueueMax + 2 do
		dropped += Serifu.enqueue(queue, index)
	end
	expect(dropped).toBe(2)
	expect(#queue).toBe(Config.Serifu.BattleQueueMax)
	expect(queue[1]).toBe(3)
	expect(queue[#queue]).toBe(Config.Serifu.BattleQueueMax + 2)
end)
