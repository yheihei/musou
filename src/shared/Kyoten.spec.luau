--!strict
local Config = require("./Config")
local Kyoten = require("./Kyoten")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

-- Config.luau の値を調整してもテストが揺れないよう、計算の引数を固定する
local PARAMS: Kyoten.Params = {
	Taikyu = { Kyoten = 20, Honjin = 40 },
	SeiatsuRate = 0.5,
	GeninGekiha = 1,
	Shubi = { Kyoten = 10, Honjin = 25 },
	HojuInterval = 10,
	HojuHeisu = 3,
	MushubiGensho = 2,
	TickInterval = 0.5,
}

test("開始時の耐久は上限で、本陣は通常拠点より高い", function()
	local kyoten = Kyoten.new("Chuo", false, "Tekigun", PARAMS)
	local honjin = Kyoten.new("TekiHonjin", true, "Tekigun", PARAMS)
	expect(kyoten).toEqual({ id = "Chuo", honjin = false, gun = "Tekigun", taikyu = 20 })
	expect(honjin.taikyu).toBe(40)
	expect(Config.Kyoten.Taikyu.Honjin > Config.Kyoten.Taikyu.Kyoten).toBe(true)
end)

test("下忍が倒れた数だけ耐久が減り、0 になるまでは所属が変わらない", function()
	local kyoten = Kyoten.new("Chuo", false, "Tekigun", PARAMS)
	expect(Kyoten.damage(kyoten, Kyoten.gekihaDamage(3, PARAMS), PARAMS)).toBe(false)
	expect(kyoten.taikyu).toBe(17)
	expect(Kyoten.damage(kyoten, 16, PARAMS)).toBe(false)
	expect(kyoten.taikyu).toBe(1)
	expect(kyoten.gun).toBe("Tekigun")
end)

test("耐久が 0 になると相手の軍に制圧され、耐久は制圧直後の値になる", function()
	local kyoten = Kyoten.new("Chuo", false, "Tekigun", PARAMS)
	expect(Kyoten.damage(kyoten, 20, PARAMS)).toBe(true)
	expect(kyoten.gun).toBe("Mikatagun")
	expect(kyoten.taikyu).toBe(10)

	local honjin = Kyoten.new("MikataHonjin", true, "Mikatagun", PARAMS)
	expect(Kyoten.damage(honjin, 100, PARAMS)).toBe(true)
	expect(honjin.gun).toBe("Tekigun")
	expect(honjin.taikyu).toBe(20)
end)

test("減らしきって余った分は制圧した後の耐久へ持ち越さない", function()
	local kyoten = Kyoten.new("Chuo", false, "Tekigun", PARAMS)
	Kyoten.damage(kyoten, 15, PARAMS)
	expect(Kyoten.damage(kyoten, 12, PARAMS)).toBe(true)
	expect(kyoten.taikyu).toBe(10)
end)

test("0 以下の量では耐久は変わらない", function()
	local kyoten = Kyoten.new("Chuo", false, "Tekigun", PARAMS)
	expect(Kyoten.damage(kyoten, 0, PARAMS)).toBe(false)
	expect(Kyoten.damage(kyoten, -5, PARAMS)).toBe(false)
	expect(kyoten.taikyu).toBe(20)
	expect(Kyoten.gekihaDamage(-2, PARAMS)).toBe(0)
end)

test("端数のある量でも減り、0 になった時点で制圧される", function()
	local kyoten = Kyoten.new("Chuo", false, "Tekigun", PARAMS)
	Kyoten.setTaikyu(kyoten, 0.75, PARAMS)
	expect(Kyoten.damage(kyoten, 0.5, PARAMS)).toBe(false)
	expect(kyoten.taikyu).toBeNear(0.25, 1e-9)
	expect(Kyoten.damage(kyoten, 0.5, PARAMS)).toBe(true)
	expect(kyoten.gun).toBe("Mikatagun")
end)

test("耐久の書き換えは上限までに収め、0 にすると制圧になる", function()
	local kyoten = Kyoten.new("Chuo", false, "Tekigun", PARAMS)
	expect(Kyoten.setTaikyu(kyoten, 99, PARAMS)).toBe(false)
	expect(kyoten.taikyu).toBe(20)
	expect(Kyoten.setTaikyu(kyoten, 5, PARAMS)).toBe(false)
	expect(kyoten.taikyu).toBe(5)
	expect(Kyoten.setTaikyu(kyoten, -1, PARAMS)).toBe(true)
	expect(kyoten.gun).toBe("Mikatagun")
	expect(kyoten.taikyu).toBe(10)
end)

test("制圧させると、所属と耐久が制圧直後の値になる", function()
	local kyoten = Kyoten.new("Chuo", false, "Tekigun", PARAMS)
	Kyoten.damage(kyoten, 4, PARAMS)
	Kyoten.seiatsu(kyoten, "Mikatagun", PARAMS)
	expect(kyoten.gun).toBe("Mikatagun")
	expect(kyoten.taikyu).toBe(10)
end)

test("画面に出す耐久は端数を切り上げ、0 は制圧した瞬間だけ", function()
	expect(Kyoten.displayTaikyu(20)).toBe(20)
	expect(Kyoten.displayTaikyu(19.2)).toBe(20)
	expect(Kyoten.displayTaikyu(0.01)).toBe(1)
	expect(Kyoten.displayTaikyu(0)).toBe(0)
end)

test("守備は上限まで1回に決まった兵数ずつ補充し、上限を超えない", function()
	expect(Kyoten.hojuHeisu(0, false, PARAMS)).toBe(3)
	expect(Kyoten.hojuHeisu(8, false, PARAMS)).toBe(2)
	expect(Kyoten.hojuHeisu(10, false, PARAMS)).toBe(0)
	expect(Kyoten.hojuHeisu(15, false, PARAMS)).toBe(0)
	expect(Kyoten.hojuHeisu(20, true, PARAMS)).toBe(3)
	expect(Kyoten.shubiMax(true, PARAMS)).toBe(25)
end)

test("守備のいない拠点は、攻める軍がいる間だけ時間に比例して耐久が減る", function()
	expect(Kyoten.mushubiDamage(0, 1, 0.5, PARAMS)).toBe(1)
	expect(Kyoten.mushubiDamage(0, 3, 2, PARAMS)).toBe(4)
	expect(Kyoten.mushubiDamage(0, 0, 2, PARAMS)).toBe(0)
	expect(Kyoten.mushubiDamage(1, 3, 2, PARAMS)).toBe(0)
end)

test("守備のいない拠点の減少でも、耐久が 0 になれば攻めた軍が制圧する", function()
	local kyoten = Kyoten.new("Chuo", false, "Tekigun", PARAMS)
	local captured = false
	for _ = 1, 20 do
		captured = Kyoten.damage(kyoten, Kyoten.mushubiDamage(0, 1, 0.5, PARAMS), PARAMS)
		if captured then
			break
		end
	end
	expect(captured).toBe(true)
	expect(kyoten.gun).toBe("Mikatagun")
end)
