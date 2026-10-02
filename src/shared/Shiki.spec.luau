--!strict
local Kosen = require("./Kosen")
local Shiki = require("./Shiki")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

-- Config.luau の値を調整してもテストが揺れないよう、計算の引数を固定する
local PARAMS: Shiki.Params = {
	Initial = 50,
	Min = 0,
	Max = 100,
	Radius = 100,
	Duration = 60,
	Dekigoto = {
		JoninGekiha = { Gun = 5, Butai = 20 },
		KyotenKanraku = { Gun = 10, Butai = 30 },
		Hikei = { Gun = 2, Butai = 10 },
	},
}

local KOSEN_PARAMS: Kosen.Params = {
	StartDistance = 30,
	Zensenhaba = 10,
	ReserveWeight = 0.5,
	ShikiEffect = 0.01,
	ShikiHoseiMin = 0.5,
	ShikiHoseiMax = 1.5,
	LossRate = 0.1,
	MaxStep = 0.5,
	GunStrength = { Mikatagun = 1, Tekigun = 1 },
}

local function dekigoto(kind: Shiki.Kind, gun: "Mikatagun" | "Tekigun", x: number, z: number, at: number)
	return { kind = kind, gun = gun, position = { x = x, z = z }, at = at } :: Shiki.Dekigoto
end

local function butai(gun: "Mikatagun" | "Tekigun", x: number, z: number, shikiHosei: number?): Shiki.ButaiInput
	return { gun = gun, position = { x = x, z = z }, shikiHosei = shikiHosei or 0 }
end

test("出来事が無ければ、部隊の士気は軍全体の士気と同じ", function()
	local gun = Shiki.newGun(PARAMS)
	expect(gun).toEqual({ Mikatagun = 50, Tekigun = 50 })
	expect(Shiki.ofButai(gun, butai("Mikatagun", 0, 0), {}, 0, PARAMS)).toBe(50)
	expect(Shiki.ofButai(gun, butai("Tekigun", 0, 0, -15), {}, 0, PARAMS)).toBe(35)
end)

test("出来事の補正は近くの部隊だけにかかり、距離が離れるほど小さい", function()
	local gun = Shiki.newGun(PARAMS)
	local list = { dekigoto("JoninGekiha", "Mikatagun", 0, 0, 0) }
	expect(Shiki.ofButai(gun, butai("Mikatagun", 0, 0), list, 0, PARAMS)).toBe(70)
	expect(Shiki.ofButai(gun, butai("Mikatagun", 50, 0), list, 0, PARAMS)).toBe(60)
	expect(Shiki.ofButai(gun, butai("Mikatagun", 0, 100), list, 0, PARAMS)).toBe(50)
	expect(Shiki.ofButai(gun, butai("Mikatagun", 300, 300), list, 0, PARAMS)).toBe(50)
end)

test("得をする軍の部隊は上がり、相手の軍の部隊は下がる", function()
	local gun = Shiki.newGun(PARAMS)
	local list = { dekigoto("KyotenKanraku", "Tekigun", 0, 0, 0) }
	expect(Shiki.ofButai(gun, butai("Tekigun", 0, 0), list, 0, PARAMS)).toBe(80)
	expect(Shiki.ofButai(gun, butai("Mikatagun", 0, 0), list, 0, PARAMS)).toBe(20)
end)

test("出来事の補正は時間で小さくなり、Duration 秒で消える", function()
	local gun = Shiki.newGun(PARAMS)
	local list = { dekigoto("JoninGekiha", "Mikatagun", 0, 0, 10) }
	expect(Shiki.ofButai(gun, butai("Mikatagun", 0, 0), list, 10, PARAMS)).toBe(70)
	expect(Shiki.ofButai(gun, butai("Mikatagun", 0, 0), list, 40, PARAMS)).toBe(60)
	expect(Shiki.ofButai(gun, butai("Mikatagun", 0, 0), list, 70, PARAMS)).toBe(50)
	expect(Shiki.ofButai(gun, butai("Mikatagun", 0, 0), list, 100, PARAMS)).toBe(50)
end)

test("出来事の補正は足し合わせ、部隊の士気は上限と下限で止まる", function()
	local gun = Shiki.newGun(PARAMS)
	local list = {
		dekigoto("KyotenKanraku", "Mikatagun", 0, 0, 0),
		dekigoto("KyotenKanraku", "Mikatagun", 0, 0, 0),
		dekigoto("JoninGekiha", "Mikatagun", 0, 0, 0),
	}
	expect(Shiki.ofButai(gun, butai("Mikatagun", 0, 0), list, 0, PARAMS)).toBe(100)
	expect(Shiki.ofButai(gun, butai("Tekigun", 0, 0), list, 0, PARAMS)).toBe(0)
	local one = { dekigoto("KyotenKanraku", "Mikatagun", 0, 0, 0) }
	expect(Shiki.ofButai(gun, butai("Mikatagun", 0, 0, 10), one, 0, PARAMS)).toBe(90)
end)

test(
	"軍全体の士気は、得をする軍が上がり相手の軍が下がって、上限と下限で止まる",
	function()
		local gun = Shiki.newGun(PARAMS)
		Shiki.applyToGun(gun, "KyotenKanraku", "Mikatagun", PARAMS)
		expect(gun).toEqual({ Mikatagun = 60, Tekigun = 40 })
		Shiki.applyToGun(gun, "Hikei", "Tekigun", PARAMS)
		expect(gun).toEqual({ Mikatagun = 58, Tekigun = 42 })
		for _ = 1, 10 do
			Shiki.applyToGun(gun, "KyotenKanraku", "Mikatagun", PARAMS)
		end
		expect(gun).toEqual({ Mikatagun = 100, Tekigun = 0 })
	end
)

test("補正の消えた出来事だけを一覧から外す", function()
	local list = {
		dekigoto("JoninGekiha", "Mikatagun", 0, 0, 0),
		dekigoto("Hikei", "Tekigun", 0, 0, 30),
		dekigoto("KyotenKanraku", "Mikatagun", 0, 0, 50),
	}
	expect(Shiki.prune(list, 59, PARAMS)).toBe(0)
	expect(#list).toBe(3)
	expect(Shiki.prune(list, 95, PARAMS)).toBe(2)
	expect(#list).toBe(1)
	expect(list[1].kind).toBe("KyotenKanraku")
end)

test("出来事の種類を見分ける", function()
	for _, kind in Shiki.kinds do
		expect(Shiki.isKind(kind)).toBe(true)
	end
	expect(Shiki.isKind("Gekiha")).toBe(false)
	expect(Shiki.isKind(nil)).toBe(false)
end)

test("出来事で士気の差が付くと、交戦の損害が変わる", function()
	local gun = Shiki.newGun(PARAMS)
	local mikata = butai("Mikatagun", 0, 0)
	local teki = butai("Tekigun", 20, 0)
	local function fight(list: { Shiki.Dekigoto }): Kosen.Result
		local a = { heisu = 30, shiki = Shiki.ofButai(gun, mikata, list, 0, PARAMS) }
		local b = { heisu = 30, shiki = Shiki.ofButai(gun, teki, list, 0, PARAMS) }
		return Kosen.step(a, b, 10, KOSEN_PARAMS)
	end
	local even = fight({})
	expect(even.a.loss).toBe(even.b.loss)
	local boosted = fight({ dekigoto("JoninGekiha", "Mikatagun", 10, 0, 0) })
	expect(boosted.a.loss < even.a.loss).toBe(true)
	expect(boosted.b.loss > even.b.loss).toBe(true)
	expect(boosted.a.loss < boosted.b.loss).toBe(true)
end)
