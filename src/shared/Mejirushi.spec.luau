--!strict
local Mejirushi = require("./Mejirushi")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

test("1〜上限人数がそろっていれば、欠けも不明な名前も無い", function()
	local check = Mejirushi.checkShutsugekiChiten({ "3", "1", "4", "2" }, 4)
	expect(check.numbers).toEqual({ 1, 2, 3, 4 })
	expect(check.missing).toEqual({})
	expect(check.duplicated).toEqual({})
	expect(check.unknown).toEqual({})
end)

test("欠けた番号を返し、ある番号だけを使える地点にする", function()
	local check = Mejirushi.checkShutsugekiChiten({ "1", "3" }, 4)
	expect(check.numbers).toEqual({ 1, 3 })
	expect(check.missing).toEqual({ 2, 4 })
end)

test("上限人数を超える番号と番号でない名前は不明な名前にする", function()
	local check = Mejirushi.checkShutsugekiChiten({ "1", "2", "3", "4", "5", "Part", "01", "0" }, 4)
	expect(check.numbers).toEqual({ 1, 2, 3, 4 })
	expect(check.unknown).toEqual({ "0", "01", "5", "Part" })
end)

test("同じ番号のパーツが2つあれば重なりとして返す", function()
	local check = Mejirushi.checkShutsugekiChiten({ "1", "1", "2" }, 2)
	expect(check.numbers).toEqual({ 1, 2 })
	expect(check.duplicated).toEqual({ 1 })
end)

test("出撃地点が無ければ全部の番号が欠けている", function()
	local check = Mejirushi.checkShutsugekiChiten({}, 4)
	expect(check.numbers).toEqual({})
	expect(check.missing).toEqual({ 1, 2, 3, 4 })
end)

test("メンバーの順番に番号の順で地点を割り当て、足りなければ使い回す", function()
	expect(Mejirushi.shutsugekiNumberOf(1, { 1, 2, 3, 4 })).toBe(1)
	expect(Mejirushi.shutsugekiNumberOf(4, { 1, 2, 3, 4 })).toBe(4)
	expect(Mejirushi.shutsugekiNumberOf(1, { 2, 4 })).toBe(2)
	expect(Mejirushi.shutsugekiNumberOf(3, { 2, 4 })).toBe(2)
	expect(Mejirushi.shutsugekiNumberOf(1, {})).toBe(nil)
end)

test("経由点の名前を番号の順に並べ、番号でない名前は分ける", function()
	local numbered, unknown = Mejirushi.sortKeiyuten({ "10", "2", "1", "Part", "0" })
	expect(numbered).toEqual({ "1", "2", "10" })
	expect(unknown).toEqual({ "0", "Part" })
end)

test("区画の範囲の中かを水平の位置で判定し、縁の上は中に含める", function()
	-- 1100 × 1400 の範囲（伊賀第1ステージの区画と同じ大きさ）
	expect(Mejirushi.insideBounds(0, 0, 1100, 1400)).toBe(true)
	expect(Mejirushi.insideBounds(-549, 699, 1100, 1400)).toBe(true)
	expect(Mejirushi.insideBounds(550, -700, 1100, 1400)).toBe(true)
	expect(Mejirushi.insideBounds(551, 0, 1100, 1400)).toBe(false)
	expect(Mejirushi.insideBounds(0, -701, 1100, 1400)).toBe(false)
	-- ロビーは伊賀第1ステージの区画の中心から 3000 離れている
	expect(Mejirushi.insideBounds(-3000, 0, 1100, 1400)).toBe(false)
end)
