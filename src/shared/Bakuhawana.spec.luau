--!strict
local Bakuhawana = require("./Bakuhawana")
local Config = require("./Config")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

-- Config.luau の値を調整してもテストが揺れないよう、割合を固定する
local PARAMS: Bakuhawana.Params = { Rate = 1 / 3, Power = 80, HeisuRate = 0.5, Knockback = 60 }

test("爆発する耐久は、耐久の上限の3分の1", function()
	expect(Bakuhawana.threshold(30, PARAMS)).toBeNear(10)
	expect(Bakuhawana.threshold(50, PARAMS)).toBeNear(50 / 3)
	expect(Config.Bakuhawana.Rate).toBeNear(1 / 3)
end)

test("上から下へ越えた瞬間だけ爆発する", function()
	expect(Bakuhawana.crossed(11, 9, 30, PARAMS)).toBe(true)
	expect(Bakuhawana.crossed(10, 9, 30, PARAMS)).toBe(true)
	expect(Bakuhawana.crossed(30, 0, 30, PARAMS)).toBe(true)
end)

test(
	"ちょうど割合の耐久や、越えない減り方と、下回った後の減り方では爆発しない",
	function()
		expect(Bakuhawana.crossed(11, 10, 30, PARAMS)).toBe(false)
		expect(Bakuhawana.crossed(30, 20, 30, PARAMS)).toBe(false)
		expect(Bakuhawana.crossed(9, 8, 30, PARAMS)).toBe(false)
		-- 補充などで耐久が増えても爆発しない
		expect(Bakuhawana.crossed(9, 12, 30, PARAMS)).toBe(false)
	end
)

test("拠点の中の部隊の兵数は割合を掛けた数だけ減らし、端数は切り上げる", function()
	expect(Bakuhawana.heisuLoss(30, PARAMS)).toBe(15)
	expect(Bakuhawana.heisuLoss(7, PARAMS)).toBe(4)
	expect(Bakuhawana.heisuLoss(0, PARAMS)).toBe(0)
end)
