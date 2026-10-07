--!strict
local Jittaikaken = require("./Jittaikaken")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

-- Config.luau の値を調整してもテストが揺れないよう、半径を固定する
local PARAMS: Jittaikaken.Params = {
	AppearRadius = 100,
	DisappearRadius = 140,
	Interval = 0.25,
	HomeRadius = 6,
	CorpseLifetime = 3,
}

test("一番近いプレイヤーまでの水平の距離を返す", function()
	local players = { { x = 30, z = 40 }, { x = -6, z = 8 }, { x = 100, z = 0 } }
	expect(Jittaikaken.nearestDistance({ x = 0, z = 0 }, players)).toBeNear(10)
end)

test("プレイヤーがいなければ距離は無い", function()
	expect(Jittaikaken.nearestDistance({ x = 0, z = 0 }, {})).toBe(nil)
end)

test("出ていない個体は、出現の半径の内に入ったら出す", function()
	expect(Jittaikaken.shouldAppear(false, 100, PARAMS)).toBe(true)
	expect(Jittaikaken.shouldAppear(false, 100.1, PARAMS)).toBe(false)
end)

test("出ている個体は、消滅の半径より離れるまで残す", function()
	expect(Jittaikaken.shouldAppear(true, 120, PARAMS)).toBe(true)
	expect(Jittaikaken.shouldAppear(true, 140, PARAMS)).toBe(true)
	expect(Jittaikaken.shouldAppear(true, 140.1, PARAMS)).toBe(false)
end)

test("半径の間を行き来しても、出入りを繰り返さない", function()
	local present = false
	local changes = 0
	-- 外から近づいて出現し、半径の間（110〜130）を往復してから離れる
	for _, distance in { 150, 120, 100, 110, 130, 110, 130, 150 } do
		local next = Jittaikaken.shouldAppear(present, distance, PARAMS)
		if next ~= present then
			changes += 1
		end
		present = next
	end
	-- 100 で出て、150 で消える2回だけ
	expect(changes).toBe(2)
	expect(present).toBe(false)
end)

test("プレイヤーがいなければ出さず、出ていれば消す", function()
	expect(Jittaikaken.shouldAppear(false, nil, PARAMS)).toBe(false)
	expect(Jittaikaken.shouldAppear(true, nil, PARAMS)).toBe(false)
end)
