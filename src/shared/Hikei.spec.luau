--!strict
local Config = require("./Config")
local Hikei = require("./Hikei")
local RemoteSchema = require("./RemoteSchema")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

local M1_HIKEI = { "Fukuhei", "Rakuseki", "Daikakei", "Hyoroko", "Bakuhawana", "Chohatsu", "Kishinka", "Daikatsu" }

test("M1 の秘計8種を設計の表の順に選べる", function()
	expect(Hikei.selectable()).toEqual(M1_HIKEI)
end)

test("定義の ID は表のキーと一致し、表示名がある", function()
	local count = 0
	for key, definition in Hikei.definitions do
		count += 1
		expect(definition.id).toBe(key)
		expect(#definition.displayName > 0).toBe(true)
	end
	expect(count).toBe(#M1_HIKEI)
end)

test("強化の秘計は鬼神化だけで、発動者自身にかかる", function()
	for id, definition in Hikei.definitions do
		expect(definition.kyoka).toBe(id == "Kishinka")
	end
	local kishinka = Hikei.get("Kishinka") :: Hikei.Definition
	expect(kishinka.target).toBe("Self")
	expect(kishinka.affects).toBe("Own")
end)

test("秘計ごとの対象の取り方", function()
	local targets = {}
	for _, id in M1_HIKEI do
		targets[id] = (Hikei.get(id) :: Hikei.Definition).target
	end
	expect(targets).toEqual({
		Fukuhei = "Underfoot",
		Rakuseki = "RakusekiChiten",
		Daikakei = "DaikakeiChiiki",
		Hyoroko = "OwnKyoten",
		Bakuhawana = "OwnKyoten",
		Chohatsu = "Nearby",
		Kishinka = "Self",
		Daikatsu = "Nearby",
	})
end)

test("持ち込みの上限は3枚", function()
	expect(Hikei.MOCHIKOMI_MAX).toBe(3)
end)

test("上限以下で重なりの無い持ち込みは受け付ける", function()
	expect(Hikei.checkMochikomi({ "Fukuhei", "Rakuseki", "Kishinka" }, { "Daikatsu" })).toBe(nil)
	expect(Hikei.checkMochikomi({ "Fukuhei" }, {})).toBe(nil)
	expect(Hikei.checkMochikomi({}, {})).toBe(nil)
end)

test("上限を超える持ち込みは拒否する", function()
	expect(Hikei.checkMochikomi({ "Fukuhei", "Rakuseki", "Kishinka", "Daikatsu" }, {})).toBe("HikeiLimit")
end)

test("本人の重複と存在しない秘計は拒否する", function()
	expect(Hikei.checkMochikomi({ "Fukuhei", "Fukuhei" }, {})).toBe("HikeiDuplicate")
	expect(Hikei.checkMochikomi({ "Fukuhei", "Musou" }, {})).toBe("UnknownHikei")
end)

test("パーティーの他のメンバーの秘計を含む持ち込みは拒否する", function()
	expect(Hikei.checkMochikomi({ "Fukuhei", "Kishinka" }, { "Rakuseki", "Kishinka" })).toBe("HikeiTaken")
end)

test("検証の理由は Remote の拒否の理由に含まれる", function()
	for _, reason in { "UnknownHikei", "HikeiDuplicate", "HikeiTaken", "HikeiLimit" } do
		expect(table.find(RemoteSchema.rejectReasons, reason :: any) ~= nil).toBe(true)
	end
end)

test("ステージ開始の使用記録は空で、どの枚も使える", function()
	local usage = Hikei.newUsage()
	local mochikomi = { "Fukuhei", "Kishinka" }
	for slot, id in mochikomi do
		expect(Hikei.isUsed(usage, "1", id)).toBe(false)
		expect(Hikei.checkUse(usage, "1", mochikomi, slot)).toBe(id)
	end
end)

test("使用済みの枚の2回目は失敗する", function()
	local usage = Hikei.newUsage()
	local mochikomi = { "Fukuhei", "Kishinka" }
	local id = Hikei.checkUse(usage, "1", mochikomi, 2)
	expect(id).toBe("Kishinka")
	expect(Hikei.markUsed(usage, "1", "Kishinka")).toBe(true)

	local again, failure = Hikei.checkUse(usage, "1", mochikomi, 2)
	expect(again).toBe(nil)
	expect(failure).toBe("Used")
	expect(Hikei.markUsed(usage, "1", "Kishinka")).toBe(false)
	-- 他の枚と他の発動者には影響しない
	expect(Hikei.checkUse(usage, "1", mochikomi, 1)).toBe("Fukuhei")
	expect(Hikei.checkUse(usage, "2", { "Kishinka" }, 1)).toBe("Kishinka")
end)

test("持ち込んでいない番号の枚は使えない", function()
	local usage = Hikei.newUsage()
	local id, failure = Hikei.checkUse(usage, "1", { "Fukuhei" }, 2)
	expect(id).toBe(nil)
	expect(failure).toBe("NoSlot")
	local _, zero = Hikei.checkUse(usage, "1", { "Fukuhei" }, 0)
	expect(zero).toBe("NoSlot")
end)

test("使わずに失敗した枚は未使用のまま残る", function()
	local usage = Hikei.newUsage()
	Hikei.checkUse(usage, "1", { "Rakuseki" }, 1)
	expect(Hikei.isUsed(usage, "1", "Rakuseki")).toBe(false)
end)

local BATTLE: Hikei.ActivationCheck = { battle = true, alive = true }

test("発動は戦闘のフェーズ、生存、持ち込み、使用済みの順に確かめる", function()
	local usage = Hikei.newUsage()
	local mochikomi = { "Fukuhei", "Kishinka" }
	expect(Hikei.checkActivation(BATTLE, usage, "1", mochikomi, 2)).toBe("Kishinka")

	local _, outside = Hikei.checkActivation({ battle = false, alive = true }, usage, "1", mochikomi, 2)
	expect(outside).toBe("NotBattle")
	local _, down = Hikei.checkActivation({ battle = true, alive = false }, usage, "1", mochikomi, 2)
	expect(down).toBe("Down")
	-- 戦闘の外なら、倒れていても戦闘の外を理由にする
	local _, both = Hikei.checkActivation({ battle = false, alive = false }, usage, "1", mochikomi, 9)
	expect(both).toBe("NotBattle")

	local _, noSlot = Hikei.checkActivation(BATTLE, usage, "1", mochikomi, 3)
	expect(noSlot).toBe("NoSlot")
	local _, huge = Hikei.checkActivation(BATTLE, usage, "1", mochikomi, 1e9)
	expect(huge).toBe("NoSlot")

	Hikei.markUsed(usage, "1", "Kishinka")
	local _, used = Hikei.checkActivation(BATTLE, usage, "1", mochikomi, 2)
	expect(used).toBe("Used")
end)

test("使用済みの秘計を持ち込みの順に返す", function()
	local usage = Hikei.newUsage()
	local mochikomi = { "Fukuhei", "Kishinka", "Daikatsu" }
	expect(Hikei.usedOf(usage, "1", mochikomi)).toEqual({})
	Hikei.markUsed(usage, "1", "Daikatsu")
	Hikei.markUsed(usage, "1", "Fukuhei")
	Hikei.markUsed(usage, "2", "Kishinka")
	expect(Hikei.usedOf(usage, "1", mochikomi)).toEqual({ "Fukuhei", "Daikatsu" })
end)

test(
	"Attribute の文字列と秘計 ID の一覧を行き来でき、定義に無い ID と文字列でない値は捨てる",
	function()
		local ids = { "Fukuhei", "Kishinka", "Daikatsu" }
		expect(Hikei.encodeList(ids)).toBe("Fukuhei,Kishinka,Daikatsu")
		expect(Hikei.decodeList(Hikei.encodeList(ids))).toEqual(ids)
		expect(Hikei.encodeList({})).toBe("")
		expect(Hikei.decodeList("")).toEqual({})
		expect(Hikei.decodeList("Fukuhei,Musou,,Rakuseki")).toEqual({ "Fukuhei", "Rakuseki" })
		expect(Hikei.decodeList(nil)).toEqual({})
		expect(Hikei.decodeList(3)).toEqual({})
	end
)

test("失敗の理由の一覧は重ならない", function()
	local seen = {}
	for _, failure in Hikei.useFailures do
		expect(seen[failure]).toBe(nil)
		seen[failure] = true
	end
	expect(#Hikei.useFailures).toBe(6)
end)

local function request(hikei: string, target: string, now: number): Hikei.EffectRequest
	return { hikei = hikei, user = "1", gun = "Mikatagun", target = target, targetGun = nil, now = now }
end

test("効果は効果時間のあいだだけ有効で、期限切れは取り出せる", function()
	local effects = Hikei.newEffects()
	local duration = Config.Hikei.Duration.Kishinka
	local effect = Hikei.addEffect(effects, request("Kishinka", "Player1", 100))
	expect(effect ~= nil).toBe(true)
	expect((effect :: Hikei.Effect).expiresAt).toBe(100 + duration)

	expect(Hikei.isActive(effects, "Player1", "Kishinka", 100 + duration - 0.01)).toBe(true)
	expect(Hikei.takeExpired(effects, 100 + duration - 0.01)).toEqual({})
	expect(Hikei.isActive(effects, "Player1", "Kishinka", 100 + duration)).toBe(false)

	local expired = Hikei.takeExpired(effects, 100 + duration)
	expect(#expired).toBe(1)
	expect(expired[1].hikei).toBe("Kishinka")
	expect(#effects).toBe(0)
	-- 取り出した効果は2回目には出てこない
	expect(Hikei.takeExpired(effects, 100 + duration + 1)).toEqual({})
end)

test("効果時間を渡すと、Config.luau の効果時間の代わりに使う", function()
	local effects = Hikei.newEffects()
	local custom = request("Hyoroko", "Kyoten1", 10)
	custom.duration = 5
	local effect = Hikei.addEffect(effects, custom) :: Hikei.Effect
	expect(effect.expiresAt).toBe(15)
	expect(#Hikei.takeExpired(effects, 15)).toBe(1)
end)

test("効果時間の無い秘計の効果は期限なしで残る", function()
	local effects = Hikei.newEffects()
	local effect = Hikei.addEffect(effects, request("Hyoroko", "Kyoten1", 0)) :: Hikei.Effect
	expect(effect.expiresAt).toBe(math.huge)
	expect(Hikei.takeExpired(effects, 1e9)).toEqual({})
	expect(Hikei.isActive(effects, "Kyoten1", "Hyoroko", 1e9)).toBe(true)
end)

test("対象にかかっている効果を引ける", function()
	local effects = Hikei.newEffects()
	Hikei.addEffect(effects, request("Kishinka", "Player1", 0))
	Hikei.addEffect(effects, request("Hyoroko", "Kyoten1", 0))
	local active = Hikei.activeOn(effects, "Player1", 1)
	expect(#active).toBe(1)
	expect(active[1].hikei).toBe("Kishinka")
	expect(Hikei.activeOn(effects, "Player1", 1000)).toEqual({})
end)

test("発動者の軍への妨害と、相手の軍への強化は足さない", function()
	local effects = Hikei.newEffects()
	local onOwn = request("Daikatsu", "Player2", 0)
	onOwn.targetGun = "Mikatagun"
	expect(Hikei.addEffect(effects, onOwn)).toBe(nil)

	local onOpponent = request("Kishinka", "Jonin1", 0)
	onOpponent.targetGun = "Tekigun"
	expect(Hikei.addEffect(effects, onOpponent)).toBe(nil)

	local valid = request("Daikatsu", "Jonin1", 0)
	valid.targetGun = "Tekigun"
	expect(Hikei.addEffect(effects, valid) ~= nil).toBe(true)
	expect(#effects).toBe(1)
end)

test("大喝は相手の軍の強化の秘計だけを打ち消し、ほかの効果は残す", function()
	local effects = Hikei.newEffects()
	-- 敵の上忍が自分に鬼神化、味方のプレイヤーが自分に鬼神化、敵の上忍が味方のプレイヤーを動揺させた
	Hikei.addEffect(effects, {
		hikei = "Kishinka",
		user = "Jonin1",
		gun = "Tekigun",
		target = "Jonin1",
		targetGun = "Tekigun",
		now = 0,
	})
	Hikei.addEffect(effects, {
		hikei = "Kishinka",
		user = "1",
		gun = "Mikatagun",
		target = "Player1",
		targetGun = "Mikatagun",
		now = 0,
	})
	Hikei.addEffect(effects, {
		hikei = "Daikatsu",
		user = "Jonin1",
		gun = "Tekigun",
		target = "Player1",
		targetGun = "Mikatagun",
		now = 0,
	})

	local dispelled = Hikei.dispelKyoka(effects, "Mikatagun", 10)
	expect(#dispelled).toBe(1)
	expect(dispelled[1].target).toBe("Jonin1")
	expect(Hikei.isActive(effects, "Jonin1", "Kishinka", 10)).toBe(false)
	expect(Hikei.isActive(effects, "Player1", "Kishinka", 10)).toBe(true)
	expect(Hikei.isActive(effects, "Player1", "Daikatsu", 10)).toBe(true)
end)

test("打ち消す対象を絞ると、その対象の効果だけを打ち消す", function()
	local effects = Hikei.newEffects()
	for _, jonin in { "Jonin1", "Jonin2" } do
		Hikei.addEffect(effects, {
			hikei = "Kishinka",
			user = jonin,
			gun = "Tekigun",
			target = jonin,
			targetGun = "Tekigun",
			now = 0,
		})
	end
	local dispelled = Hikei.dispelKyoka(effects, "Mikatagun", 1, { "Jonin2" })
	expect(#dispelled).toBe(1)
	expect(dispelled[1].target).toBe("Jonin2")
	expect(Hikei.isActive(effects, "Jonin1", "Kishinka", 1)).toBe(true)
end)

test("効果の説明があり、{秒} は Config.luau の効果時間に置き換わる", function()
	for _, id in M1_HIKEI do
		local text = Hikei.describe(id)
		expect(#text > 0).toBe(true)
		expect(string.find(text, "{", 1, true)).toBe(nil)
	end
	expect(Hikei.describe("Kishinka")).toBe(
		`{Config.Hikei.Duration.Kishinka}秒、自分の攻撃と防御が上がり、のけぞらなくなる`
	)
	expect(Hikei.describe("Nowhere")).toBe("")
end)

test("{秒} を使う説明の秘計には効果時間がある", function()
	for id, definition in Hikei.definitions do
		if string.find(definition.description, "{秒}", 1, true) then
			expect(Config.Hikei.Duration[id] ~= nil).toBe(true)
		end
	end
end)

test("大火計地域までの距離は、範囲の中なら 0、外なら縁までの距離", function()
	expect(Hikei.distanceToArea(0, 0, 60, 80)).toBe(0)
	expect(Hikei.distanceToArea(30, -40, 60, 80)).toBe(0)
	expect(Hikei.distanceToArea(40, 0, 60, 80)).toBeNear(10)
	expect(Hikei.distanceToArea(0, -50, 60, 80)).toBeNear(10)
	expect(Hikei.distanceToArea(33, 44, 60, 80)).toBeNear(5)
end)

test("距離の上限以内で一番近い地点を返し、上限を超えたら nil を返す", function()
	local candidates = {
		{ id = "R2", distance = 40 },
		{ id = "R1", distance = 25 },
		{ id = "R3", distance = 80 },
	}
	expect(Hikei.nearest(candidates, 60)).toBe("R1")
	expect(Hikei.nearest(candidates, 20)).toBe(nil)
	expect(Hikei.nearest({}, 60)).toBe(nil)
	expect(Hikei.nearest({ { id = "R1", distance = 60 } }, 60)).toBe("R1")
end)

test("距離が同じ地点は ID の順に選ぶ", function()
	expect(Hikei.nearest({ { id = "D2", distance = 0 }, { id = "D1", distance = 0 } }, 60)).toBe("D1")
end)

test("落石と大火計には対象の地点までの距離の上限がある", function()
	expect(Hikei.targetRangeOf("Rakuseki")).toBe(Config.Hikei.TargetRange.Rakuseki)
	expect(Hikei.targetRangeOf("Daikakei")).toBe(Config.Hikei.TargetRange.Daikakei)
	expect(Hikei.targetRangeOf("Kishinka")).toBe(nil)
end)
