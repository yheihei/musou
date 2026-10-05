--!strict
local Daikakei = require("./Daikakei")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

-- Config.luau の値を調整してもテストが揺れないよう、割合を固定する
local PARAMS: Daikakei.Params = { Power = 100, HeisuRate = 0.5, FireTime = 3 }

test("部隊の兵数は割合を掛けた数だけ減らし、端数は切り上げる", function()
	expect(Daikakei.heisuLoss(30, PARAMS)).toBe(15)
	expect(Daikakei.heisuLoss(31, PARAMS)).toBe(16)
	expect(Daikakei.heisuLoss(1, PARAMS)).toBe(1)
end)

test("兵数より多くは減らさず、兵数 0 の部隊は減らさない", function()
	expect(Daikakei.heisuLoss(10, { Power = 100, HeisuRate = 2, FireTime = 3 })).toBe(10)
	expect(Daikakei.heisuLoss(0, PARAMS)).toBe(0)
end)
