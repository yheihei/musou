--!strict
local Haichi = require("./Haichi")
local HikeiHandan = require("./HikeiHandan")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

-- Config.luau の値を調整してもテストが揺れないよう、間隔と割合と半径を固定する
local PARAMS: HikeiHandan.Params = {
	HikeiHandan = { Interval = 1, UseInterval = 30, RetryInterval = 10, ShuryoHealthRate = 0.5 },
	Daikatsu = { Radius = 40 },
	Chohatsu = { Radius = 100 },
}

local function player(id: string, x: number, z: number, kyoka: boolean?): HikeiHandan.Unit
	return {
		kind = "Player",
		id = id,
		gun = "Mikatagun",
		x = x,
		z = z,
		kyoka = kyoka == true,
		shuryo = false,
		lured = false,
	}
end

local function jonin(
	id: string,
	gun: "Mikatagun" | "Tekigun",
	x: number,
	z: number,
	options: { shuryo: boolean?, lured: boolean?, kyoka: boolean? }?
): HikeiHandan.Unit
	local o = options or {}
	return {
		kind = "Jonin",
		id = id,
		gun = gun,
		x = x,
		z = z,
		kyoka = o.kyoka == true,
		shuryo = o.shuryo == true,
		lured = o.lured == true,
	}
end

type Changes = {
	id: string?,
	gun: ("Mikatagun" | "Tekigun")?,
	shuryo: boolean?,
	health: number?,
	maxHealth: number?,
	kosen: boolean?,
	kishinka: boolean?,
	hikei: { string }?,
	units: { HikeiHandan.Unit }?,
}

-- (0, 0) にいる敵軍の上忍の様子。changes の項目だけ書き換える
local function situation(changes: Changes?): HikeiHandan.Situation
	local c = changes or {}
	return {
		id = c.id or "ShikenJonin1",
		gun = c.gun or "Tekigun",
		shuryo = c.shuryo == true,
		x = 0,
		z = 0,
		health = c.health or 600,
		maxHealth = c.maxHealth or 600,
		kosen = c.kosen == true,
		kishinka = c.kishinka == true,
		hikei = c.hikei or { "Kishinka", "Daikatsu", "Chohatsu" },
		units = c.units or {},
	}
end

test("条件がそろわなければ、どの秘計も使わない", function()
	expect(HikeiHandan.decide(situation(), PARAMS)).toBe(nil)
	local far = { player("1", 0, 50, true), jonin("ShikenJonin3", "Mikatagun", 0, 120) }
	expect(HikeiHandan.decide(situation({ units = far }), PARAMS)).toBe(nil)
end)

test("鬼神化は、率いる部隊が交戦中なら使う", function()
	expect(HikeiHandan.decide(situation({ kosen = true }), PARAMS)).toBe("Kishinka")
end)

test(
	"鬼神化は、首領の体力が上限の割合以下になったら使い、上忍は体力が減っても使わない",
	function()
		local function decideAt(shuryo: boolean, health: number): string?
			return HikeiHandan.decide(situation({ shuryo = shuryo, health = health, maxHealth = 1200 }), PARAMS)
		end
		expect(decideAt(true, 601)).toBe(nil)
		expect(decideAt(true, 600)).toBe("Kishinka")
		expect(decideAt(true, 100)).toBe("Kishinka")
		expect(decideAt(false, 100)).toBe(nil)
	end
)

test("もう鬼神化していれば、交戦中でも体力が減っても鬼神化を使わない", function()
	expect(HikeiHandan.decide(situation({ kosen = true, kishinka = true }), PARAMS)).toBe(nil)
	local weakened = situation({ shuryo = true, health = 100, maxHealth = 1200, kishinka = true })
	expect(HikeiHandan.decide(weakened, PARAMS)).toBe(nil)
end)

test(
	"大喝は、半径の中に強化の秘計の効果中の相手がいれば使う（縁ちょうども入れる）",
	function()
		expect(HikeiHandan.decide(situation({ units = { player("1", 0, 40, true) } }), PARAMS)).toBe("Daikatsu")
		expect(HikeiHandan.decide(situation({ units = { player("1", 24, -32, true) } }), PARAMS)).toBe("Daikatsu")
		expect(HikeiHandan.decide(situation({ units = { player("1", 0, 40.5, true) } }), PARAMS)).toBe(nil)
		local kyokaJonin = jonin("ShikenJonin3", "Mikatagun", 30, 0, { kyoka = true })
		expect(HikeiHandan.decide(situation({ units = { kyokaJonin } }), PARAMS)).toBe("Daikatsu")
	end
)

test(
	"大喝は、強化の秘計の効果中でない相手と、同じ軍の効果中の上忍には使わない",
	function()
		local units = {
			player("1", 0, 10, false),
			jonin("ShikenJonin2", "Tekigun", 5, 0, { kyoka = true }),
		}
		expect(HikeiHandan.decide(situation({ hikei = { "Daikatsu" }, units = units }), PARAMS)).toBe(nil)
	end
)

test(
	"挑発は、半径の中に誘い出されていない相手の上忍がいれば使う（縁ちょうども入れる）",
	function()
		local near = { jonin("ShikenJonin3", "Mikatagun", 100, 0) }
		expect(HikeiHandan.decide(situation({ units = near }), PARAMS)).toBe("Chohatsu")
		local far = { jonin("ShikenJonin3", "Mikatagun", 100.5, 0) }
		expect(HikeiHandan.decide(situation({ units = far }), PARAMS)).toBe(nil)
	end
)

test(
	"挑発は、誘い出されている上忍、首領、プレイヤー、同じ軍の上忍には使わない",
	function()
		local units = {
			jonin("ShikenJonin3", "Mikatagun", 10, 0, { lured = true }),
			jonin("Hayate", "Mikatagun", 20, 0, { shuryo = true }),
			player("1", 5, 0),
			jonin("ShikenJonin2", "Tekigun", 5, 0),
		}
		expect(HikeiHandan.decide(situation({ hikei = { "Chohatsu" }, units = units }), PARAMS)).toBe(nil)
	end
)

test("条件のそろった秘計が2枚以上あれば、枚の順で先の秘計を使う", function()
	local units = { jonin("ShikenJonin3", "Mikatagun", 20, 0) }
	local first = situation({ kosen = true, hikei = { "Kishinka", "Chohatsu" }, units = units })
	expect(HikeiHandan.decide(first, PARAMS)).toBe("Kishinka")
	local reversed = situation({ kosen = true, hikei = { "Chohatsu", "Kishinka" }, units = units })
	expect(HikeiHandan.decide(reversed, PARAMS)).toBe("Chohatsu")
end)

test("使える秘計に無い秘計と、使う条件の無い秘計は使わない", function()
	expect(HikeiHandan.decide(situation({ kosen = true, hikei = { "Chohatsu" } }), PARAMS)).toBe(nil)
	expect(HikeiHandan.decide(situation({ kosen = true, hikei = {} }), PARAMS)).toBe(nil)
	local skipped = situation({ kosen = true, hikei = { "Rakuseki", "Kishinka" } })
	expect(HikeiHandan.decide(skipped, PARAMS)).toBe("Kishinka")
	expect(HikeiHandan.hasCondition("Kishinka")).toBe(true)
	expect(HikeiHandan.hasCondition("Daikatsu")).toBe(true)
	expect(HikeiHandan.hasCondition("Chohatsu")).toBe(true)
	expect(HikeiHandan.hasCondition("Rakuseki")).toBe(false)
end)

test("味方軍の上忍と首領は、条件がそろっても秘計を使わない", function()
	-- 交戦中で、近くに強化の秘計の効果中の相手の上忍がいる（敵軍の上忍なら、3枚のどれでも使う様子）
	local units = { jonin("ShikenJonin1", "Tekigun", 10, 0, { kyoka = true }) }
	local mikata = situation({ id = "ShikenJonin3", gun = "Mikatagun", kosen = true, units = units })
	expect(HikeiHandan.decide(mikata, PARAMS)).toBe(nil)
	for _, hikeiId in { "Kishinka", "Daikatsu", "Chohatsu" } do
		local mirrored = { jonin("ShikenJonin3", "Mikatagun", 10, 0, { kyoka = true }) }
		local enemy = situation({ kosen = true, hikei = { hikeiId }, units = mirrored })
		expect(HikeiHandan.decide(enemy, PARAMS)).toBe(hikeiId)
	end
	local weakened = situation({ id = "Hayate", gun = "Mikatagun", shuryo = true, health = 100, maxHealth = 1080 })
	expect(HikeiHandan.decide(weakened, PARAMS)).toBe(nil)
end)

test("試験用ステージで持ち込む秘計には、どれも使う条件がある", function()
	for _, mochikomi in Haichi.mochikomiOf("Test") do
		for _, hikeiId in mochikomi do
			expect(HikeiHandan.hasCondition(hikeiId)).toBe(true)
		end
	end
end)

test("上忍と首領ごとに、判断の周期に1回だけ判断する", function()
	local state = HikeiHandan.newState()
	expect(HikeiHandan.isDue(state, "ShikenJonin1", 0, PARAMS)).toBe(true)
	expect(HikeiHandan.isDue(state, "ShikenJonin1", 0.25, PARAMS)).toBe(false)
	expect(HikeiHandan.isDue(state, "ShikenJonin1", 0.75, PARAMS)).toBe(false)
	expect(HikeiHandan.isDue(state, "ShikenJonin2", 0.75, PARAMS)).toBe(true)
	expect(HikeiHandan.isDue(state, "ShikenJonin1", 1, PARAMS)).toBe(true)
	expect(HikeiHandan.isDue(state, "ShikenJonin1", 1.25, PARAMS)).toBe(false)
	expect(HikeiHandan.isDue(state, "ShikenJonin2", 1.5, PARAMS)).toBe(false)
	expect(HikeiHandan.isDue(state, "ShikenJonin2", 1.75, PARAMS)).toBe(true)
end)

test("敵軍のだれかが使ったら、使用間隔の間は敵軍のだれも判断しない", function()
	local state = HikeiHandan.newState()
	expect(HikeiHandan.waitOf(state, 0, PARAMS)).toBe(0)
	HikeiHandan.recordUse(state, 10)
	expect(HikeiHandan.waitOf(state, 10, PARAMS)).toBe(30)
	expect(HikeiHandan.isDue(state, "ShikenJonin1", 10, PARAMS)).toBe(false)
	expect(HikeiHandan.isDue(state, "ShikenJonin2", 25, PARAMS)).toBe(false)
	expect(HikeiHandan.waitOf(state, 39.5, PARAMS)).toBe(0.5)
	expect(HikeiHandan.isDue(state, "ShikenShuryo", 39.5, PARAMS)).toBe(false)
	expect(HikeiHandan.waitOf(state, 40, PARAMS)).toBe(0)
	expect(HikeiHandan.isDue(state, "ShikenJonin1", 40, PARAMS)).toBe(true)
	expect(HikeiHandan.isDue(state, "ShikenJonin2", 40, PARAMS)).toBe(true)
end)

test(
	"条件がそろい続けても、敵軍は使用間隔ごとに1枚ずつ使い、使った枚は2度使わない",
	function()
		local state = HikeiHandan.newState()
		local mochikomi = { ShikenJonin1 = { "Kishinka", "Chohatsu" }, ShikenJonin2 = { "Kishinka" } }
		local used = { ShikenJonin1 = {}, ShikenJonin2 = {} }
		local units = { jonin("ShikenJonin3", "Mikatagun", 50, 0) }
		local log = {}
		-- 考える間隔（0.25 秒）ごとに、2人の上忍が順に判断する。どちらの部隊も交戦し続けている
		for step = 0, 400 do
			local now = step * 0.25
			for _, id in { "ShikenJonin1", "ShikenJonin2" } do
				if HikeiHandan.isDue(state, id, now, PARAMS) then
					local hikei = HikeiHandan.usableOf(state, id, mochikomi[id], used[id], now, PARAMS)
					local chosen = HikeiHandan.decide(situation({ kosen = true, hikei = hikei, units = units }), PARAMS)
					if chosen then
						table.insert(used[id], chosen)
						HikeiHandan.recordUse(state, now)
						table.insert(log, `{now} {id} {chosen}`)
					end
				end
			end
		end
		expect(log).toEqual({
			"0 ShikenJonin1 Kishinka",
			"30 ShikenJonin1 Chohatsu",
			"60 ShikenJonin2 Kishinka",
		})
	end
)

test("使える秘計は、持ち込みから使用済みの秘計を除いて枚の順に並べる", function()
	local state = HikeiHandan.newState()
	local mochikomi = { "Kishinka", "Daikatsu", "Chohatsu" }
	expect(HikeiHandan.usableOf(state, "ShikenJonin1", mochikomi, {}, 0, PARAMS)).toEqual(mochikomi)
	expect(HikeiHandan.usableOf(state, "ShikenJonin1", mochikomi, { "Daikatsu" }, 0, PARAMS)).toEqual({
		"Kishinka",
		"Chohatsu",
	})
	expect(HikeiHandan.usableOf(state, "ShikenJonin1", {}, {}, 0, PARAMS)).toEqual({})
end)

test(
	"発動できなかった秘計は、試し直しの間だけ選ばず、ほかの秘計とほかの上忍は変わらない",
	function()
		local state = HikeiHandan.newState()
		local mochikomi = { "Kishinka", "Chohatsu" }
		HikeiHandan.recordFailure(state, "ShikenJonin1", "Kishinka", 5)
		expect(HikeiHandan.retryWaitOf(state, "ShikenJonin1", "Kishinka", 5, PARAMS)).toBe(10)
		expect(HikeiHandan.retryWaitOf(state, "ShikenJonin1", "Chohatsu", 5, PARAMS)).toBe(0)
		expect(HikeiHandan.usableOf(state, "ShikenJonin1", mochikomi, {}, 5, PARAMS)).toEqual({ "Chohatsu" })
		expect(HikeiHandan.usableOf(state, "ShikenJonin1", mochikomi, {}, 14.75, PARAMS)).toEqual({ "Chohatsu" })
		expect(HikeiHandan.usableOf(state, "ShikenJonin1", mochikomi, {}, 15, PARAMS)).toEqual(mochikomi)
		expect(HikeiHandan.usableOf(state, "ShikenJonin2", mochikomi, {}, 5, PARAMS)).toEqual(mochikomi)
		-- もう一度発動できなければ、その時刻から試し直しを待つ
		HikeiHandan.recordFailure(state, "ShikenJonin1", "Kishinka", 15)
		expect(HikeiHandan.usableOf(state, "ShikenJonin1", mochikomi, {}, 20, PARAMS)).toEqual({ "Chohatsu" })
	end
)
