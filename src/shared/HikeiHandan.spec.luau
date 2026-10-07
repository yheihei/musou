--!strict
local Haichi = require("./Haichi")
local Hikei = require("./Hikei")
local HikeiHandan = require("./HikeiHandan")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

-- Config.luau の値を調整してもテストが揺れないよう、間隔と割合と半径を固定する
local PARAMS: HikeiHandan.Params = {
	HikeiHandan = { Interval = 1, UseInterval = 30, RetryInterval = 10, ShuryoHealthRate = 0.5, BakuhawanaRadius = 100 },
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

type KyotenChanges = {
	id: string?,
	gun: ("Mikatagun" | "Tekigun")?,
	honjin: boolean?,
	x: number?,
	z: number?,
	mattan: boolean?,
	hyoroko: boolean?,
	bakuhawana: boolean?,
	taikyu: number?,
}

-- (0, 0) を中心にした、敵軍の兵站線の末端の通常拠点（耐久 30、爆発する耐久 10）。changes の項目だけ書き換える
local function kyoten(changes: KyotenChanges?): HikeiHandan.Kyoten
	local c = changes or {}
	return {
		id = c.id or "Higashi",
		gun = c.gun or "Tekigun",
		honjin = c.honjin == true,
		x = c.x or 0,
		z = c.z or 0,
		mattan = c.mattan ~= false,
		hyoroko = c.hyoroko == true,
		bakuhawana = c.bakuhawana == true,
		taikyu = c.taikyu or 30,
		threshold = 10,
	}
end

-- 拠点 inside の範囲の中にいる上忍の様子。inside が nil なら拠点の外
local function inKyoten(inside: HikeiHandan.Kyoten?, changes: Changes?): HikeiHandan.Situation
	local result = situation(changes)
	result.kyoten = inside
	return result
end

-- 拠点 inside の中で、兵糧庫だけを使えるときの判断
local function decideHyoroko(inside: HikeiHandan.Kyoten?): string?
	return HikeiHandan.decide(inKyoten(inside, { hikei = { "Hyoroko" } }), PARAMS)
end

-- 拠点 inside の中で、爆破罠だけを使えるときの判断。units は戦場のプレイヤーと上忍・首領
local function decideBakuhawana(inside: HikeiHandan.Kyoten?, units: { HikeiHandan.Unit }): string?
	return HikeiHandan.decide(inKyoten(inside, { hikei = { "Bakuhawana" }, units = units }), PARAMS)
end

test("兵糧庫は、中にいる自分の軍の通常拠点が兵站線の末端なら使う", function()
	expect(decideHyoroko(kyoten())).toBe("Hyoroko")
	expect(HikeiHandan.hasCondition("Hyoroko")).toBe(true)
end)

test(
	"兵糧庫は、末端でない拠点・本陣・相手の軍の拠点・もう兵糧庫の拠点と、拠点の外では使わない",
	function()
		expect(decideHyoroko(kyoten({ mattan = false }))).toBe(nil)
		-- 本陣は末端に数えないうえ、兵糧庫の対象でもない（Hikei.checkHyoroko の NoTarget）
		expect(decideHyoroko(kyoten({ id = "TekiHonjin", honjin = true }))).toBe(nil)
		-- 中央を制圧されたあとも中にいる、相手の軍の拠点
		expect(decideHyoroko(kyoten({ id = "Chuo", gun = "Mikatagun" }))).toBe(nil)
		expect(decideHyoroko(kyoten({ hyoroko = true }))).toBe(nil)
		expect(decideHyoroko(nil)).toBe(nil)
	end
)

test(
	"爆破罠は、中にいる自分の軍の拠点の中心から半径の中にプレイヤーがいれば使う（縁ちょうども入れ、本陣も含む）",
	function()
		expect(decideBakuhawana(kyoten(), { player("1", 0, 0) })).toBe("Bakuhawana")
		expect(decideBakuhawana(kyoten(), { player("1", 60, -80) })).toBe("Bakuhawana")
		expect(decideBakuhawana(kyoten(), { player("1", 0, 100.5) })).toBe(nil)
		-- 2人のうち1人でも半径の中にいれば使う
		expect(decideBakuhawana(kyoten(), { player("1", 0, 300), player("2", 30, 40) })).toBe("Bakuhawana")
		local honjin = kyoten({ id = "TekiHonjin", honjin = true, mattan = false, taikyu = 50 })
		expect(decideBakuhawana(honjin, { player("1", 0, 50) })).toBe("Bakuhawana")
		expect(HikeiHandan.hasCondition("Bakuhawana")).toBe(true)
	end
)

test("爆破罠の距離は、上忍の位置でなく、中にいる拠点の中心から測る", function()
	-- 上忍は (0, 0)、拠点の中心は東へ 30 ずれた (30, 0)
	local shifted = kyoten({ x = 30 })
	expect(decideBakuhawana(shifted, { player("1", 130, 0) })).toBe("Bakuhawana")
	expect(decideBakuhawana(shifted, { player("1", -90, 0) })).toBe(nil)
end)

test(
	"爆破罠は、もう罠のある拠点・耐久が爆発する耐久を下回った拠点・相手の軍の拠点と、拠点の外では使わない",
	function()
		local near = { player("1", 0, 10) }
		expect(decideBakuhawana(kyoten({ bakuhawana = true }), near)).toBe(nil)
		expect(decideBakuhawana(kyoten({ taikyu = 9.9 }), near)).toBe(nil)
		-- ちょうど爆発する耐久ならまだ仕掛けられる（下回ったときに爆発する）
		expect(decideBakuhawana(kyoten({ taikyu = 10 }), near)).toBe("Bakuhawana")
		expect(decideBakuhawana(kyoten({ id = "Chuo", gun = "Mikatagun" }), near)).toBe(nil)
		expect(decideBakuhawana(nil, near)).toBe(nil)
	end
)

test(
	"爆破罠は、近くにいるのが上忍だけなら、プレイヤーが近づくまで使わない",
	function()
		local units = { jonin("ShikenJonin3", "Mikatagun", 0, 10), jonin("ShikenJonin1", "Tekigun", 5, 0) }
		expect(decideBakuhawana(kyoten(), units)).toBe(nil)
		expect(HikeiHandan.playerDistanceOf(inKyoten(kyoten(), { units = units }))).toBe(nil)
		expect(HikeiHandan.playerDistanceOf(inKyoten(nil, { units = { player("1", 0, 10) } }))).toBe(nil)
		local players = { player("1", 0, 50), player("2", 0, -30) }
		expect(HikeiHandan.playerDistanceOf(inKyoten(kyoten(), { units = players }))).toBe(30)
	end
)

test(
	"判断で兵糧庫と爆破罠を選ぶのは、発動の確かめ（Hikei.checkHyoroko・checkBakuhawana）を通る拠点のときだけ",
	function()
		local near = { player("1", 0, 10) }
		for _, gun in { "Mikatagun", "Tekigun" } :: { "Mikatagun" | "Tekigun" } do
			for _, honjin in { false, true } do
				for _, active in { false, true } do
					for _, taikyu in { 9, 10, 30 } do
						local inside = kyoten({
							gun = gun,
							honjin = honjin,
							hyoroko = active,
							bakuhawana = active,
							taikyu = taikyu,
						})
						local hyorokoOk = Hikei.checkHyoroko({ gun = gun, honjin = honjin, active = active }, "Tekigun")
							== nil
						expect(decideHyoroko(inside) == "Hyoroko").toBe(hyorokoOk)
						local bakuhawanaTarget = { gun = gun, taikyu = taikyu, threshold = 10, active = active }
						local bakuhawanaOk = Hikei.checkBakuhawana(bakuhawanaTarget, "Tekigun") == nil
						expect(decideBakuhawana(inside, near) == "Bakuhawana").toBe(bakuhawanaOk)
					end
				end
			end
		end
	end
)

test("味方軍の上忍と首領は、兵糧庫と爆破罠の条件がそろっても使わない", function()
	-- 自分の軍の兵站線の末端の通常拠点の中にいる（敵軍の上忍なら兵糧庫を使う様子）
	local nishi = kyoten({ id = "Nishi", gun = "Mikatagun" })
	local changes: Changes = {
		id = "ShikenJonin3",
		gun = "Mikatagun",
		hikei = { "Hyoroko", "Bakuhawana" },
		units = { player("1", 0, 10) },
	}
	expect(HikeiHandan.decide(inKyoten(nishi, changes), PARAMS)).toBe(nil)
end)

test(
	"試験用ステージの試験の上忍2 は、東で兵糧庫を使い、プレイヤーが東に近づいたら爆破罠を使う",
	function()
		-- 位置は区画の中心からのスタッド。東の中心は (220, -60)、出撃地点は (0, 200)
		local mejirushi = (Haichi.get("Test") :: Haichi.Haichi).shikenMejirushi :: Haichi.ShikenMejirushi
		local center = mejirushi.kyoten.Higashi
		local function decideAt(hikei: { string }, inside: HikeiHandan.Kyoten, x: number, z: number): string?
			return HikeiHandan.decide(inKyoten(inside, { hikei = hikei, units = { player("1", x, z) } }), PARAMS)
		end
		local mochikomi = Haichi.mochikomiOf("Test").ShikenJonin2
		expect(mochikomi).toEqual({ "Daikatsu", "Hyoroko", "Bakuhawana" })
		-- 開始時の東は敵軍の兵站線の末端（Heitansen.spec で確かめる）。出撃地点は東の中心から約 341 離れている
		local higashi = kyoten({ x = center.x, z = center.z })
		expect(decideAt(mochikomi, higashi, 0, 200)).toBe("Hyoroko")
		local hyoroko = kyoten({ x = center.x, z = center.z, hyoroko = true })
		expect(decideAt({ "Daikatsu", "Bakuhawana" }, hyoroko, 0, 200)).toBe(nil)
		-- プレイヤーが東の中心へ移ると爆破罠を仕掛ける。仕掛けた後は、残る大喝の条件がそろわないので何も使わない
		expect(decideAt({ "Daikatsu", "Bakuhawana" }, hyoroko, center.x, center.z)).toBe("Bakuhawana")
		local trapped = kyoten({ x = center.x, z = center.z, hyoroko = true, bakuhawana = true })
		expect(decideAt({ "Daikatsu" }, trapped, center.x, center.z)).toBe(nil)
	end
)
