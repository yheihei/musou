--!strict
local Kosen = require("./Kosen")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

-- Config.luau の値を調整してもテストが揺れないよう、計算の引数を固定する
local PARAMS: Kosen.Params = {
	Zensenhaba = 10,
	ReserveWeight = 0.5,
	ShikiEffect = 0.01,
	ShikiHoseiMin = 0.5,
	ShikiHoseiMax = 1.5,
	LossRate = 0.1,
	MaxStep = 0.5,
	GunStrength = { Mikatagun = 0.9, Tekigun = 1 },
}

local function side(heisu: number, shiki: number?): Kosen.Side
	return { heisu = heisu, shiki = shiki or 50 }
end

test("同じ条件の部隊は損害が等しい", function()
	local result = Kosen.step(side(30), side(30), 5, PARAMS)
	expect(result.a.loss > 0).toBe(true)
	expect(result.a.loss).toBe(result.b.loss)
	expect(result.a.heisu).toBe(result.b.heisu)
	expect(result.a.push).toBeNear(result.b.push)
end)

test("士気の高い側は損害が少ない", function()
	local result = Kosen.step(side(30, 70), side(30, 50), 5, PARAMS)
	expect(result.a.loss < result.b.loss).toBe(true)
	expect(result.a.push > result.b.push).toBe(true)
end)

test("士気の差による倍率は下限と上限で止まる", function()
	expect(Kosen.shikiHosei(50, 50, PARAMS)).toBe(1)
	expect(Kosen.shikiHosei(70, 50, PARAMS)).toBeNear(1.2)
	expect(Kosen.shikiHosei(200, 0, PARAMS)).toBe(1.5)
	expect(Kosen.shikiHosei(0, 200, PARAMS)).toBe(0.5)
end)

test("強さの倍率と支配エリアの倍率が高い側は損害が少ない", function()
	local strong = side(30)
	strong.strength = 1.2
	local result = Kosen.step(strong, side(30), 5, PARAMS)
	expect(result.a.loss < result.b.loss).toBe(true)

	local inArea = side(30)
	inArea.shihaiArea = 1.2
	local areaResult = Kosen.step(inArea, side(30), 5, PARAMS)
	expect(areaResult.a.loss < areaResult.b.loss).toBe(true)
end)

test("前線の後ろに控える兵の多い側は損害が少ない", function()
	local result = Kosen.step(side(40), side(20), 5, PARAMS)
	expect(result.a.push > result.b.push).toBe(true)
	expect(result.a.loss < result.b.loss).toBe(true)
end)

test("前線幅までは押す力が兵数に比例する", function()
	local enemy = side(10)
	expect(Kosen.push(side(10), enemy, PARAMS)).toBeNear(Kosen.push(side(5), enemy, PARAMS) * 2)
end)

test("前線幅を超えた兵数では、兵数を倍にしても相手の損害は倍にならない", function()
	-- 相手は兵数が多く、こちらをほとんど削らない部隊にする
	local enemy = side(1000)
	enemy.strength = 0.0001
	local double = Kosen.step(side(20), enemy, 10, PARAMS).b.loss
	local quadruple = Kosen.step(side(40), enemy, 10, PARAMS).b.loss
	expect(double).toBe(15)
	expect(quadruple).toBe(25)
	expect(quadruple < double * 2).toBe(true)
	-- 押す力は 10 + 控え × 0.5 なので、20人は 15、40人は 25
	expect(Kosen.push(side(20), enemy, PARAMS)).toBeNear(15)
	expect(Kosen.push(side(40), enemy, PARAMS)).toBeNear(25)
end)

test("兵数は負にならず、0 になった側が負ける", function()
	local result = Kosen.step(side(1), side(50), 100, PARAMS)
	expect(result.a.heisu).toBe(0)
	expect(result.a.loss).toBe(1)
	expect(result.b.heisu > 0).toBe(true)
	expect(result.settled).toBe(true)
	expect(result.winner).toBe("B")
	expect(result.a.push).toBe(0)
end)

test("両方同時に 0 になったら引き分け", function()
	local result = Kosen.step(side(3), side(3), 1000, PARAMS)
	expect(result.a.heisu).toBe(0)
	expect(result.b.heisu).toBe(0)
	expect(result.winner).toBe("Draw")
end)

test("決着していなければ勝者はいない", function()
	local result = Kosen.step(side(30), side(30), 1, PARAMS)
	expect(result.settled).toBe(false)
	expect(result.winner).toBe(nil)
end)

test("1人に満たない損害は端数として持ち越す", function()
	-- 押す力 10 × 0.1 = 1秒に1人。0.3秒では1人に満たない
	local first = Kosen.step(side(10), side(10), 0.3, PARAMS)
	expect(first.a.loss).toBe(0)
	expect(first.a.fraction).toBeNear(0.3)

	local carried = side(10)
	carried.fraction = first.a.fraction
	local second = Kosen.step(carried, side(10), 0.8, PARAMS)
	expect(second.a.loss).toBe(1)
	expect(second.a.fraction).toBeNear(0.1)
end)

test("長い経過時間を一度に計算しても、刻んで計算した結果と同じになる", function()
	local once = Kosen.step(side(30, 60), side(25, 50), 6, PARAMS)

	local a, b = side(30, 60), side(25, 50)
	for _ = 1, 12 do
		local r = Kosen.step(a, b, 0.5, PARAMS)
		a = { heisu = r.a.heisu, fraction = r.a.fraction, shiki = 60 }
		b = { heisu = r.b.heisu, fraction = r.b.fraction, shiki = 50 }
	end
	expect(once.a.heisu).toBe(a.heisu)
	expect(once.b.heisu).toBe(b.heisu)
	expect(once.a.fraction).toBeNear(a.fraction :: number)
end)

test("経過時間が 0 なら何も変わらず、引数の表も書き換えない", function()
	local a = side(30)
	local result = Kosen.step(a, side(30), 0, PARAMS)
	expect(result.a.heisu).toBe(30)
	expect(result.a.loss).toBe(0)
	expect(result.settled).toBe(false)
	Kosen.step(a, side(30), 10, PARAMS)
	expect(a.heisu).toBe(30)
	expect(a.fraction).toBe(nil)
end)

test("引数を省くと Config.luau の値で計算する", function()
	local result = Kosen.step(side(30), side(30), 5)
	expect(result.a.loss).toBe(result.b.loss)
end)
