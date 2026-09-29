--!strict
local Config = require("./Config")
local OugiGauge = require("./OugiGauge")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

-- 1本 100、上限 4 本、最初は 1 本
local PARAMS: OugiGauge.Params = { PerStock = 100, MaxStock = 4, InitialStock = 1 }

local function gauge(stock: number, amount: number): OugiGauge.Gauge
	return { stock = stock, gauge = amount }
end

test("出撃したときは最初の本数で、次の1本までの量は 0", function()
	expect(OugiGauge.initial(PARAMS)).toEqual(gauge(1, 0))
end)

test("1本分に届くと本数が増え、あふれた分は次の1本へ繰り越す", function()
	expect(OugiGauge.add(gauge(0, 90), 25, PARAMS)).toEqual(gauge(1, 15))
	expect(OugiGauge.add(gauge(1, 0), 100, PARAMS)).toEqual(gauge(2, 0))
end)

test("1度に2本分より多く溜まれば、その本数だけ増える", function()
	expect(OugiGauge.add(gauge(0, 50), 230, PARAMS)).toEqual(gauge(2, 80))
end)

test("本数は上限で頭打ちになり、それ以上は溜まらない", function()
	expect(OugiGauge.add(gauge(3, 90), 25, PARAMS)).toEqual(gauge(4, 0))
	expect(OugiGauge.add(gauge(4, 0), 100, PARAMS)).toEqual(gauge(4, 0))
end)

test("負の量は足さない", function()
	expect(OugiGauge.add(gauge(1, 30), -50, PARAMS)).toEqual(gauge(1, 30))
end)

test("奥義1回で1本使い、次の1本までの量は残る", function()
	local ok, next = OugiGauge.consume(gauge(2, 40))
	expect(ok).toBe(true)
	expect(next).toEqual(gauge(1, 40))
end)

test("1本も無ければ使えず、値は変わらない", function()
	local ok, next = OugiGauge.consume(gauge(0, 99))
	expect(ok).toBe(false)
	expect(next).toEqual(gauge(0, 99))
end)

test("合計の量との行き来で値が変わらない", function()
	local value = gauge(2, 35)
	expect(OugiGauge.total(value, PARAMS)).toBe(235)
	expect(OugiGauge.fromTotal(235, PARAMS)).toEqual(value)
end)

test("Config の本数は上限が最初の本数以上で、1本分の量は正", function()
	expect(Config.Ougi.PerStock > 0).toBe(true)
	expect(Config.Ougi.MaxStock >= Config.Ougi.InitialStock).toBe(true)
	expect(Config.Ougi.InitialStock >= 0).toBe(true)
end)
