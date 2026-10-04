--!strict
local Haichi = require("./Haichi")
local Hoshin = require("./Hoshin")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

-- Config.luau の値を調整してもテストが揺れないよう、距離と割合を固定する
local PARAMS: Hoshin.Params = {
	Interval = 2,
	GeigekiDistance = 100,
	KyuenRate = 0.8,
}

local function kyoten(id: string, gun: any, x: number, z: number): Hoshin.Kyoten
	return { id = id, gun = gun, x = x, z = z, taikyuRate = 1, kogeki = false }
end

local function butai(hoshin: Haichi.Hoshin, gun: any, kyotenId: string, tanto: string?): Hoshin.Butai
	return {
		id = "B",
		gun = gun,
		position = { x = 0, z = 0 },
		hoshin = hoshin,
		tanto = tanto or kyotenId,
		kyoten = kyotenId,
	}
end

-- 試験用ステージの配置（Haichi.luau の Test）の拠点とつながり
local function shiken(): ({ Hoshin.Kyoten }, { Hoshin.Tsunagari })
	local haichi = Haichi.get("Test") :: Haichi.Haichi
	local mejirushi = haichi.shikenMejirushi :: Haichi.ShikenMejirushi
	local kyotenList = {}
	for _, item in haichi.kyoten do
		local ichi = mejirushi.kyoten[item.id]
		table.insert(kyotenList, kyoten(item.id, item.gun, ichi.x, ichi.z))
	end
	local tsunagariList = {}
	for _, item in haichi.tsunagari do
		table.insert(tsunagariList, { kyotenA = item.kyotenA, kyotenB = item.kyotenB })
	end
	return kyotenList, tsunagariList
end

test(
	"道のりは自分の軍の拠点からだけ先へ延び、相手の軍の拠点には入るが先へは進まない",
	function()
		local kyotenList = {
			kyoten("A", "Mikatagun", 0, 0),
			kyoten("B", "Mikatagun", 100, 0),
			kyoten("C", "Tekigun", 200, 0),
			kyoten("D", "Tekigun", 300, 0),
		}
		local reach = Hoshin.reach(kyotenList, {
			{ kyotenA = "A", kyotenB = "B" },
			{ kyotenA = "B", kyotenB = "C" },
			{ kyotenA = "C", kyotenB = "D" },
		}, "Mikatagun", "A")
		expect(reach.A).toEqual({ distance = 0, next = nil })
		expect(reach.B).toEqual({ distance = 100, next = "B" })
		expect(reach.C).toEqual({ distance = 200, next = "B" })
		expect(reach.D).toBe(nil)
	end
)

test("出発する拠点は相手の軍の拠点でも先へ進める", function()
	local kyotenList = {
		kyoten("A", "Tekigun", 0, 0),
		kyoten("B", "Mikatagun", 100, 0),
	}
	local reach = Hoshin.reach(kyotenList, { { kyotenA = "A", kyotenB = "B" } }, "Mikatagun", "A")
	expect(reach.B).toEqual({ distance = 100, next = "B" })
end)

test("その軍が通れないつながりは通らず、道のりを渡されたらそれで測る", function()
	local kyotenList = {
		kyoten("A", "Mikatagun", 0, 0),
		kyoten("B", "Mikatagun", 100, 0),
		kyoten("C", "Mikatagun", 50, 80),
	}
	local tsunagariList: { Hoshin.Tsunagari } = {
		{ kyotenA = "A", kyotenB = "B", blocked = { Mikatagun = true } },
		{ kyotenA = "A", kyotenB = "C", length = 120 },
		{ kyotenA = "C", kyotenB = "B", length = 130 },
	}
	local reach = Hoshin.reach(kyotenList, tsunagariList, "Mikatagun", "A")
	expect(reach.B).toEqual({ distance = 250, next = "C" })
	local other = Hoshin.reach(kyotenList, tsunagariList, "Tekigun", "A")
	expect(other.B).toEqual({ distance = 100, next = "B" })
end)

test(
	"試験用ステージの攻略の部隊は、つながりの先の一番近い相手の拠点を目指す",
	function()
		local kyotenList, tsunagariList = shiken()
		local teki = Hoshin.decide(butai("Koryaku", "Tekigun", "Chuo"), kyotenList, tsunagariList, {}, PARAMS)
		expect(teki).toEqual({ kind = "Kyoten", kyoten = "Nishi", next = "Nishi", butai = nil, position = nil })
		local mikata = Hoshin.decide(butai("Koryaku", "Mikatagun", "Nishi"), kyotenList, tsunagariList, {}, PARAMS)
		expect(mikata.kyoten).toBe("Chuo")
		expect(mikata.next).toBe("Chuo")
	end
)

test("攻略は相手の軍の拠点を越えた先を目指さない", function()
	-- C は A から真っすぐなら近いが、つながりでは相手の軍の B の先にある
	local kyotenList = {
		kyoten("A", "Mikatagun", 0, 0),
		kyoten("B", "Tekigun", 300, 0),
		kyoten("C", "Tekigun", 0, 100),
	}
	local decision = Hoshin.decide(butai("Koryaku", "Mikatagun", "A"), kyotenList, {
		{ kyotenA = "A", kyotenB = "B" },
		{ kyotenA = "B", kyotenB = "C" },
	}, {}, PARAMS)
	expect(decision.kyoten).toBe("B")
end)

test("攻略は塞がれたつながりを避け、自分の軍の拠点を回って向かう", function()
	local kyotenList = {
		kyoten("A", "Mikatagun", 0, 0),
		kyoten("M", "Mikatagun", 0, 200),
		kyoten("T", "Tekigun", 200, 0),
	}
	local decision = Hoshin.decide(butai("Koryaku", "Mikatagun", "A"), kyotenList, {
		{ kyotenA = "A", kyotenB = "T", blocked = { Mikatagun = true } },
		{ kyotenA = "A", kyotenB = "M" },
		{ kyotenA = "M", kyotenB = "T" },
	}, {}, PARAMS)
	expect(decision).toEqual({ kind = "Kyoten", kyoten = "T", next = "M", butai = nil, position = nil })
end)

test("攻略の部隊が相手の軍の拠点に着いたら、落とすまでそこにとどまる", function()
	local kyotenList, tsunagariList = shiken()
	local decision =
		Hoshin.decide(butai("Koryaku", "Mikatagun", "Chuo", "Nishi"), kyotenList, tsunagariList, {}, PARAMS)
	expect(decision).toEqual({ kind = "Kyoten", kyoten = "Chuo", next = nil, butai = nil, position = nil })
end)

test("攻略で目指せる相手の拠点が無ければ、担当の拠点へ戻る", function()
	local kyotenList = {
		kyoten("A", "Mikatagun", 0, 0),
		kyoten("B", "Mikatagun", 100, 0),
		kyoten("T", "Tekigun", 500, 0),
	}
	local decision = Hoshin.decide(butai("Koryaku", "Mikatagun", "B", "A"), kyotenList, {
		{ kyotenA = "A", kyotenB = "B" },
	}, {}, PARAMS)
	expect(decision).toEqual({ kind = "Kyoten", kyoten = "A", next = "A", butai = nil, position = nil })
end)

test(
	"防衛の部隊は、担当の拠点に近づいた相手の部隊のうち拠点に一番近いものを迎え撃つ",
	function()
		local kyotenList = { kyoten("A", "Tekigun", 0, 0) }
		local tekiList: { Hoshin.Teki } = {
			{ id = "Far", gun = "Mikatagun", position = { x = 90, z = 0 } },
			{ id = "Near", gun = "Mikatagun", position = { x = 0, z = 60 } },
			{ id = "Ally", gun = "Tekigun", position = { x = 10, z = 0 } },
			{ id = "Outside", gun = "Mikatagun", position = { x = 101, z = 0 } },
		}
		local decision = Hoshin.decide(butai("Boei", "Tekigun", "A"), kyotenList, {}, tekiList, PARAMS)
		expect(decision).toEqual({
			kind = "Butai",
			kyoten = nil,
			next = nil,
			butai = "Near",
			position = { x = 0, z = 60 },
		})
	end
)

test("防衛の部隊は、近づいた相手がいなければ担当の拠点へ戻ってとどまる", function()
	local kyotenList = {
		kyoten("A", "Tekigun", 0, 0),
		kyoten("B", "Tekigun", 200, 0),
	}
	local tekiList: { Hoshin.Teki } = {
		{ id = "Outside", gun = "Mikatagun", position = { x = 150, z = 0 } },
	}
	local tsunagariList = { { kyotenA = "A", kyotenB = "B" } }
	local away = Hoshin.decide(butai("Boei", "Tekigun", "B", "A"), kyotenList, tsunagariList, tekiList, PARAMS)
	expect(away).toEqual({ kind = "Kyoten", kyoten = "A", next = "A", butai = nil, position = nil })
	local home = Hoshin.decide(butai("Boei", "Tekigun", "A"), kyotenList, tsunagariList, tekiList, PARAMS)
	expect(home).toEqual({ kind = "Kyoten", kyoten = "A", next = nil, butai = nil, position = nil })
end)

test(
	"救援の部隊は、耐久が減って攻められている自分の軍の拠点のうち、道のりが一番近い拠点へ向かう",
	function()
		local kyotenList = {
			kyoten("Home", "Mikatagun", 0, 0),
			kyoten("Damaged", "Mikatagun", 100, 0),
			kyoten("Attacked", "Mikatagun", 0, 100),
			kyoten("Both", "Mikatagun", 0, 300),
			kyoten("Both2", "Mikatagun", 0, 400),
		}
		kyotenList[2].taikyuRate = 0.5
		kyotenList[3].kogeki = true
		kyotenList[4].taikyuRate = 0.8
		kyotenList[4].kogeki = true
		kyotenList[5].taikyuRate = 0.1
		kyotenList[5].kogeki = true
		local tsunagariList = {
			{ kyotenA = "Home", kyotenB = "Damaged" },
			{ kyotenA = "Home", kyotenB = "Attacked" },
			{ kyotenA = "Attacked", kyotenB = "Both" },
			{ kyotenA = "Both", kyotenB = "Both2" },
		}
		local decision = Hoshin.decide(butai("Kyuen", "Mikatagun", "Home"), kyotenList, tsunagariList, {}, PARAMS)
		expect(decision).toEqual({ kind = "Kyoten", kyoten = "Both", next = "Attacked", butai = nil, position = nil })
	end
)

test("救援の部隊は、向かう拠点が無ければ担当の拠点にとどまる", function()
	local kyotenList = {
		kyoten("Home", "Mikatagun", 0, 0),
		kyoten("Teki", "Tekigun", 100, 0),
	}
	kyotenList[2].taikyuRate = 0.1
	kyotenList[2].kogeki = true
	local decision = Hoshin.decide(
		butai("Kyuen", "Mikatagun", "Home"),
		kyotenList,
		{ { kyotenA = "Home", kyotenB = "Teki" } },
		{},
		PARAMS
	)
	expect(decision).toEqual({ kind = "Kyoten", kyoten = "Home", next = nil, butai = nil, position = nil })
end)

test("今いる拠点が分からなければ、位置に一番近い拠点から測る", function()
	local kyotenList, tsunagariList = shiken()
	local item = butai("Koryaku", "Tekigun", "Chuo")
	item.kyoten = nil
	item.position = { x = 210, z = -50 }
	local decision = Hoshin.decide(item, kyotenList, tsunagariList, {}, PARAMS)
	-- 東から中央を通り、一番近い西を目指す
	expect(decision.kyoten).toBe("Nishi")
	expect(decision.next).toBe("Chuo")
end)

test("範囲の外の位置は範囲の縁へ寄せ、中はそのまま", function()
	local x, z = Hoshin.clampToRange(80, -10, 100, 60)
	expect(x).toBe(50)
	expect(z).toBe(-10)
	local insideX, insideZ = Hoshin.clampToRange(-20, 25, 100, 60)
	expect(insideX).toBe(-20)
	expect(insideZ).toBe(25)
end)
