--!strict
local Butai = require("./Butai")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

local function newButai(position: Butai.Point): Butai.Butai
	return {
		id = "Teki1",
		gun = "Tekigun",
		position = position,
		heisu = 30,
		shiki = 50,
		jonin = nil,
		mokutekichi = nil,
		keiyuten = {},
		kyoten = "Chuo",
		mokutekiKyoten = nil,
	}
end

local function rounded(point: Butai.Point): { number }
	return { math.round(point.x * 1000) / 1000, math.round(point.z * 1000) / 1000 }
end

test("最初の点へ向けて距離の分だけまっすぐ進む", function()
	local position, rest = Butai.advance({ x = 0, z = 0 }, { { x = 10, z = 0 }, { x = 10, z = 10 } }, 4)
	expect(rounded(position)).toEqual({ 4, 0 })
	expect(#rest).toBe(2)
end)

test("点にたどり着いたら外し、余った距離で次の点へ進む", function()
	local position, rest = Butai.advance({ x = 0, z = 0 }, { { x = 10, z = 0 }, { x = 10, z = 10 } }, 13)
	expect(rounded(position)).toEqual({ 10, 3 })
	expect(#rest).toBe(1)
	expect(rest[1]).toEqual({ x = 10, z = 10 })
end)

test("最後の点に着いたら、距離が余っても行き過ぎずに止まる", function()
	local position, rest = Butai.advance({ x = 0, z = 0 }, { { x = 3, z = 4 } }, 100)
	expect(rounded(position)).toEqual({ 3, 4 })
	expect(rest).toEqual({})
end)

test("距離が 0 か、たどる点が無ければ動かない", function()
	local route = { { x = 10, z = 0 } }
	local position, rest = Butai.advance({ x = 1, z = 2 }, route, 0)
	expect(rounded(position)).toEqual({ 1, 2 })
	expect(#rest).toBe(1)
	local still, none = Butai.advance({ x = 1, z = 2 }, {}, 5)
	expect(rounded(still)).toEqual({ 1, 2 })
	expect(none).toEqual({})
end)

test("たどる点の一覧と位置の表は書き換えない", function()
	local start = { x = 0, z = 0 }
	local route = { { x = 10, z = 0 }, { x = 10, z = 10 } }
	Butai.advance(start, route, 15)
	expect(start).toEqual({ x = 0, z = 0 })
	expect(route).toEqual({ { x = 10, z = 0 }, { x = 10, z = 10 } })
end)

test(
	"部隊は経由点をたどって目的地へ進み、着いたら止まって目的の拠点を今の拠点にする",
	function()
		local butai = newButai({ x = 0, z = 0 })
		Butai.setMokutekichi(butai, { x = 10, z = 10 }, { { x = 10, z = 0 } }, "Higashi")
		expect(#Butai.routeOf(butai)).toBe(2)

		expect(Butai.step(butai, 4, 2)).toBe(true)
		expect(rounded(butai.position)).toEqual({ 8, 0 })
		expect(#butai.keiyuten).toBe(1)

		Butai.step(butai, 4, 1)
		expect(rounded(butai.position)).toEqual({ 10, 2 })
		expect(butai.keiyuten).toEqual({})
		expect(butai.mokutekichi).toEqual({ x = 10, z = 10 })
		expect(butai.kyoten).toBe("Chuo")

		Butai.step(butai, 4, 10)
		expect(rounded(butai.position)).toEqual({ 10, 10 })
		expect(butai.mokutekichi).toBe(nil)
		expect(butai.kyoten).toBe("Higashi")
		expect(butai.mokutekiKyoten).toBe(nil)

		expect(Butai.step(butai, 4, 1)).toBe(false)
		expect(rounded(butai.position)).toEqual({ 10, 10 })
	end
)

test("目的地を外すとその場で止まる", function()
	local butai = newButai({ x = 0, z = 0 })
	Butai.setMokutekichi(butai, { x = 10, z = 0 }, { { x = 5, z = 5 } }, "Higashi")
	Butai.setMokutekichi(butai, nil)
	expect(butai.keiyuten).toEqual({})
	expect(butai.mokutekiKyoten).toBe(nil)
	expect(Butai.step(butai, 4, 1)).toBe(false)
	expect(rounded(butai.position)).toEqual({ 0, 0 })
end)

test("兵数は整数で増減し、0 未満にはならない", function()
	local butai = newButai({ x = 0, z = 0 })
	expect(Butai.changeHeisu(butai, -12)).toBe(18)
	expect(Butai.changeHeisu(butai, 5)).toBe(23)
	expect(Butai.changeHeisu(butai, -100)).toBe(0)
	expect(butai.heisu).toBe(0)
end)

test(
	"つながりの経由点は、たどる向きに合わせて並べ、つながっていなければ nil",
	function()
		local tsunagari: { Butai.Tsunagari } = {
			{ kyotenA = "A", kyotenB = "B", keiyuten = { { x = 1, z = 0 }, { x = 2, z = 0 } } },
			{ kyotenA = "B", kyotenB = "C", keiyuten = {} },
		}
		expect(Butai.keiyutenBetween(tsunagari, "A", "B")).toEqual({ { x = 1, z = 0 }, { x = 2, z = 0 } })
		expect(Butai.keiyutenBetween(tsunagari, "B", "A")).toEqual({ { x = 2, z = 0 }, { x = 1, z = 0 } })
		expect(Butai.keiyutenBetween(tsunagari, "C", "B")).toEqual({})
		expect(Butai.keiyutenBetween(tsunagari, "A", "C")).toBe(nil)
	end
)
