--!strict
local Config = require("./Config")
local Saishutsugeki = require("./Saishutsugeki")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

-- 試験用ステージに近い戦場。南に味方軍の本陣、北に敵軍の本陣
local function kyotenList(): { Saishutsugeki.KyotenInput }
	return {
		{ id = "MikataHonjin", gun = "Mikatagun", connected = true, x = 0, z = 280 },
		{ id = "Nishi", gun = "Mikatagun", connected = true, x = -220, z = 60 },
		{ id = "Chuo", gun = "Tekigun", connected = true, x = 0, z = 0 },
		{ id = "Higashi", gun = "Mikatagun", connected = false, x = 220, z = -60 },
		{ id = "TekiHonjin", gun = "Tekigun", connected = true, x = 0, z = -280 },
	}
end

test(
	"兵站線につながった自分の軍の拠点のうち、倒れた位置に一番近い拠点を選ぶ",
	function()
		local list = kyotenList()
		expect(Saishutsugeki.chooseKyoten(list, "Mikatagun", -200, 0)).toBe("Nishi")
		expect(Saishutsugeki.chooseKyoten(list, "Mikatagun", 10, 250)).toBe("MikataHonjin")
	end
)

test("孤立した拠点は、近くても選ばない", function()
	expect(Saishutsugeki.chooseKyoten(kyotenList(), "Mikatagun", 220, -60)).toBe("MikataHonjin")
end)

test("相手の軍の拠点は、近くても選ばない", function()
	expect(Saishutsugeki.chooseKyoten(kyotenList(), "Mikatagun", 0, -270)).toBe("Nishi")
	expect(Saishutsugeki.chooseKyoten(kyotenList(), "Tekigun", 0, 270)).toBe("Chuo")
end)

test("候補が無ければ選ばない", function()
	local list = kyotenList()
	for _, kyoten in list do
		if kyoten.gun == "Mikatagun" then
			kyoten.connected = false
		end
	end
	expect(Saishutsugeki.chooseKyoten(list, "Mikatagun", 0, 0)).toBe(nil)
	expect(Saishutsugeki.chooseKyoten({}, "Mikatagun", 0, 0)).toBe(nil)
end)

test("同じ距離なら一覧の先の拠点を選ぶ", function()
	local list: { Saishutsugeki.KyotenInput } = {
		{ id = "A", gun = "Mikatagun", connected = true, x = -10, z = 0 },
		{ id = "B", gun = "Mikatagun", connected = true, x = 10, z = 0 },
	}
	expect(Saishutsugeki.chooseKyoten(list, "Mikatagun", 0, 0)).toBe("A")
end)

test("拠点の中では、出撃した順に間隔をあけて並べ、上限人数で一回りする", function()
	expect(Saishutsugeki.offsetOf(1, 6, 4)).toBe(-9)
	expect(Saishutsugeki.offsetOf(2, 6, 4)).toBe(-3)
	expect(Saishutsugeki.offsetOf(3, 6, 4)).toBe(3)
	expect(Saishutsugeki.offsetOf(4, 6, 4)).toBe(9)
	expect(Saishutsugeki.offsetOf(5, 6, 4)).toBe(-9)
	expect(Saishutsugeki.offsetOf(1, 6, 1)).toBe(0)
	expect(Saishutsugeki.offsetOf(1)).toBe(-1.5 * Config.Stage.SaishutsugekiSpacing)
end)

test("兵力は1ずつ使い、0 になったら使えない", function()
	expect({ Saishutsugeki.consume(2) }).toEqual({ true, 1 })
	expect({ Saishutsugeki.consume(1) }).toEqual({ true, 0 })
	expect({ Saishutsugeki.consume(0) }).toEqual({ false, 0 })
	expect(Config.Stage.Heiryoku > 0).toBe(true)
end)
