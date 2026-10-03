--!strict
local Gun = require("./Gun")
local Heitansen = require("./Heitansen")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

-- 試験用の戦場
--
--   MikataHonjin ─ A ─ B ─ C ─ TekiHonjin
--                  │
--                  D
--
-- A・B・D は味方軍、C は敵軍の拠点
local function kyotenList(): { Heitansen.Kyoten }
	return {
		{ id = "MikataHonjin", gun = "Mikatagun", honjin = true },
		{ id = "A", gun = "Mikatagun", honjin = false },
		{ id = "B", gun = "Mikatagun", honjin = false },
		{ id = "C", gun = "Tekigun", honjin = false },
		{ id = "D", gun = "Mikatagun", honjin = false },
		{ id = "TekiHonjin", gun = "Tekigun", honjin = true },
	}
end

local function tsunagariList(): { Heitansen.Tsunagari }
	return {
		{ kyotenA = "MikataHonjin", kyotenB = "A" },
		{ kyotenA = "A", kyotenB = "B" },
		{ kyotenA = "B", kyotenB = "C" },
		{ kyotenA = "C", kyotenB = "TekiHonjin" },
		{ kyotenA = "A", kyotenB = "D" },
	}
end

local function find(list: { Heitansen.Kyoten }, id: string): Heitansen.Kyoten
	for _, kyoten in list do
		if kyoten.id == id then
			return kyoten
		end
	end
	error(`拠点 {id} が無い`)
end

test("本陣から一続きの同じ軍の拠点は兵站線につながる", function()
	local result = Heitansen.compute(kyotenList(), tsunagariList())
	expect(result.Mikatagun.connected).toEqual({ MikataHonjin = true, A = true, B = true, D = true })
	expect(result.Mikatagun.isolated).toEqual({})
	expect(result.Tekigun.connected).toEqual({ TekiHonjin = true, C = true })
	expect(result.Tekigun.isolated).toEqual({})
	expect(Heitansen.isConnected(result, "Mikatagun", "B")).toBe(true)
	expect(Heitansen.isConnected(result, "Mikatagun", "C")).toBe(false)
end)

test("中間の拠点を相手の軍に取られると、その先の拠点は孤立する", function()
	local list = kyotenList()
	find(list, "A").gun = "Tekigun"
	local result = Heitansen.compute(list, tsunagariList())
	expect(result.Mikatagun.connected).toEqual({ MikataHonjin = true })
	expect(result.Mikatagun.isolated).toEqual({ B = true, D = true })
	-- 敵軍も味方軍の拠点 B を越えては A にたどり着けない
	expect(result.Tekigun.isolated).toEqual({ A = true })
end)

test("取り返すと孤立が解ける", function()
	local list = kyotenList()
	find(list, "A").gun = "Tekigun"
	Heitansen.compute(list, tsunagariList())
	find(list, "A").gun = "Mikatagun"
	local result = Heitansen.compute(list, tsunagariList())
	expect(result.Mikatagun.isolated).toEqual({})
end)

test("通れないつながりの先は、その軍にとってだけ孤立する", function()
	local tsunagari = tsunagariList()
	tsunagari[1].blocked = { Mikatagun = true }
	local result = Heitansen.compute(kyotenList(), tsunagari)
	expect(result.Mikatagun.connected).toEqual({ MikataHonjin = true })
	expect(result.Mikatagun.isolated).toEqual({ A = true, B = true, D = true })

	-- 敵軍だけを塞いだつながりは、味方軍には影響しない
	local forTekigun = tsunagariList()
	forTekigun[1].blocked = { Tekigun = true }
	local other = Heitansen.compute(kyotenList(), forTekigun)
	expect(other.Mikatagun.isolated).toEqual({})
end)

test(
	"孤立しない拠点はたどり着けなくても孤立せず、その先へは兵站線を延ばさない",
	function()
		local list = kyotenList()
		find(list, "A").neverIsolated = true
		local tsunagari = tsunagariList()
		tsunagari[1].blocked = { Mikatagun = true }
		local result = Heitansen.compute(list, tsunagari)
		expect(result.Mikatagun.connected).toEqual({ MikataHonjin = true, A = true })
		expect(result.Mikatagun.isolated).toEqual({ B = true, D = true })
	end
)

test("環を含むつながりでも止まり、片側を塞いでも反対側からつながる", function()
	local tsunagari = tsunagariList()
	table.insert(tsunagari, { kyotenA = "D", kyotenB = "B" })
	table.insert(tsunagari, { kyotenA = "D", kyotenB = "MikataHonjin" })
	local result = Heitansen.compute(kyotenList(), tsunagari)
	expect(result.Mikatagun.connected).toEqual({ MikataHonjin = true, A = true, B = true, D = true })

	tsunagari[1].blocked = { Mikatagun = true }
	tsunagari[2].blocked = { Mikatagun = true }
	local blocked = Heitansen.compute(kyotenList(), tsunagari)
	expect(blocked.Mikatagun.connected).toEqual({ MikataHonjin = true, A = true, B = true, D = true })
	expect(blocked.Mikatagun.isolated).toEqual({})
end)

test("本陣の無い軍の拠点はすべて孤立する", function()
	local list = kyotenList()
	find(list, "TekiHonjin").gun = "Mikatagun"
	find(list, "TekiHonjin").honjin = false
	local result = Heitansen.compute(list, tsunagariList())
	expect(result.Tekigun.connected).toEqual({})
	expect(result.Tekigun.isolated).toEqual({ C = true })
end)

test("どちらにも属さない拠点は結果に入らず、その先へは進まない", function()
	local list = kyotenList()
	find(list, "B").gun = nil
	local result = Heitansen.compute(list, tsunagariList())
	for _, gun in Gun.list do
		expect(result[gun].connected.B).toBe(nil)
		expect(result[gun].isolated.B).toBe(nil)
	end
	expect(result.Mikatagun.isolated).toEqual({})
	expect(result.Tekigun.connected).toEqual({ TekiHonjin = true, C = true })
end)

test("表に無い拠点を指すつながりは無視する", function()
	local tsunagari = tsunagariList()
	table.insert(tsunagari, { kyotenA = "A", kyotenB = "NoSuchKyoten" })
	local result = Heitansen.compute(kyotenList(), tsunagari)
	expect(result.Mikatagun.connected).toEqual({ MikataHonjin = true, A = true, B = true, D = true })
end)

test("相手の軍は Gun.opponentOf で引ける", function()
	expect(Gun.opponentOf("Mikatagun")).toBe("Tekigun")
	expect(Gun.opponentOf("Tekigun")).toBe("Mikatagun")
	expect(Gun.isGun("Mikatagun")).toBe(true)
	expect(Gun.isGun("mikatagun")).toBe(false)
	expect(Gun.isGun(nil)).toBe(false)
end)

test("両端が同じ軍の兵站線につながったつながりは、その軍の兵站線に入る", function()
	local result = Heitansen.compute(kyotenList(), tsunagariList())
	expect(Heitansen.gunOf(result, { kyotenA = "MikataHonjin", kyotenB = "A" })).toBe("Mikatagun")
	expect(Heitansen.gunOf(result, { kyotenA = "A", kyotenB = "D" })).toBe("Mikatagun")
	expect(Heitansen.gunOf(result, { kyotenA = "C", kyotenB = "TekiHonjin" })).toBe("Tekigun")
	-- 両軍の境目のつながりは、どちらの兵站線にも入らない
	expect(Heitansen.gunOf(result, { kyotenA = "B", kyotenB = "C" })).toBe(nil)
end)

test("通れないつながりと、孤立した拠点へのつながりは兵站線に入らない", function()
	local list = tsunagariList()
	list[1].blocked = { Mikatagun = true }
	local result = Heitansen.compute(kyotenList(), list)
	expect(Heitansen.gunOf(result, list[1])).toBe(nil)
	expect(Heitansen.gunOf(result, list[2])).toBe(nil)
	expect(Heitansen.isConnected(result, "Mikatagun", "B")).toBe(false)
end)
