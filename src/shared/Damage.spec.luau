--!strict
local ActionState = require("./ActionState")
local Config = require("./Config")
local Damage = require("./Damage")
local Stats = require("./Stats")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

-- 受ける側は原点に立って -Z を向き、攻撃は正面の 5 スタッド先から来る
local ORIGIN = vector.create(0, 0, -5)
local BEHIND = vector.create(0, 0, 5)

local function defender(overrides: { [string]: any }?): Damage.Defender
	local result: { [string]: any } = {
		action = nil,
		defense = 10,
		forceField = false,
		invulnerableUntil = 0,
		flinchImmuneUntil = 0,
		position = vector.create(0, 0, 0),
		facing = vector.create(0, 0, -1),
	}
	for key, value in overrides or {} do
		result[key] = value
	end
	return result :: any
end

local function attack(power: number, reaction: Damage.Reaction): Damage.Attack
	return { origin = ORIGIN, power = power, reaction = reaction }
end

test("防御の高いキャラクターほど被ダメージが小さい", function()
	local jin = Stats.baseOf("Jin") :: Stats.Values
	local kanaOni = Stats.baseOf("KanaOni") :: Stats.Values
	local toJin = Damage.resolve(defender({ defense = jin.Defense }), attack(30, "None"), 10)
	local toKanaOni = Damage.resolve(defender({ defense = kanaOni.Defense }), attack(30, "None"), 10)
	expect(toJin.result).toBe("Hit")
	expect(toJin.amount).toBeNear(Stats.damage(1, 30, jin.Defense))
	expect(toKanaOni.amount < toJin.amount).toBe(true)
end)

test("奥義の最中は無敵で、ダメージも反応もゲージの増加も無い", function()
	local outcome = Damage.resolve(defender({ action = "Ougi" }), attack(30, "Knockback"), 10)
	expect(outcome.result).toBe("Invulnerable")
	expect(outcome.amount).toBe(0)
	expect(outcome.action).toBe(nil)
	expect(outcome.gauge).toBe(0)
end)

test("ForceField を持つ間と、無敵が切れる時刻の前は無敵", function()
	expect(Damage.resolve(defender({ forceField = true }), attack(30, "Flinch"), 10).result).toBe("Invulnerable")
	expect(Damage.resolve(defender({ invulnerableUntil = 11 }), attack(30, "Flinch"), 10).result).toBe("Invulnerable")
	expect(Damage.resolve(defender({ invulnerableUntil = 10 }), attack(30, "Flinch"), 10).result).toBe("Hit")
end)

test(
	"ガードの最中は正面からの攻撃を被ダメージ 0 で受け、ガードの硬直を起こす",
	function()
		for _, action in { "Guard", "GuardHit" } do
			local outcome = Damage.resolve(defender({ action = action }), attack(30, "Knockback"), 10)
			expect(outcome.result).toBe("Guard")
			expect(outcome.amount).toBe(0)
			expect(outcome.action).toBe("GuardHit")
			expect(outcome.gauge).toBe(0)
		end
	end
)

test("ガードの最中でも背後と真横からの攻撃は通常どおり受ける", function()
	local fromBehind =
		Damage.resolve(defender({ action = "Guard" }), { origin = BEHIND, power = 30, reaction = "Flinch" }, 10)
	expect(fromBehind.result).toBe("Hit")
	expect(fromBehind.amount > 0).toBe(true)
	expect(fromBehind.action).toBe("Flinch")
	local fromSide = Damage.resolve(
		defender({ action = "Guard" }),
		{ origin = vector.create(5, 0, 0), power = 30, reaction = "Flinch" },
		10
	)
	expect(fromSide.result).toBe("Hit")
end)

test("ガードしていなければ正面からの攻撃も受ける", function()
	expect(Damage.resolve(defender(), attack(30, "Flinch"), 10).result).toBe("Hit")
end)

test("攻撃中は無敵ではない", function()
	local outcome = Damage.resolve(defender({ action = "Attack" }), attack(30, "Flinch"), 10)
	expect(outcome.result).toBe("Hit")
	expect(outcome.action).toBe("Flinch")
end)

test("のけぞりの攻撃はのけぞりを始め、明けてからしばらくはのけぞらない", function()
	local first = Damage.resolve(defender(), attack(10, "Flinch"), 10)
	expect(first.action).toBe("Flinch")
	local immuneUntil = 10 + ActionState.duration(Config.Action.Flinch) + Config.Damage.FlinchImmunity
	expect(first.flinchImmuneUntil).toBeNear(immuneUntil)

	local during = Damage.resolve(defender({ flinchImmuneUntil = first.flinchImmuneUntil }), attack(10, "Flinch"), 10.5)
	expect(during.result).toBe("Hit")
	expect(during.amount > 0).toBe(true)
	expect(during.action).toBe(nil)

	local after =
		Damage.resolve(defender({ flinchImmuneUntil = first.flinchImmuneUntil }), attack(10, "Flinch"), immuneUntil)
	expect(after.action).toBe("Flinch")
end)

test("吹き飛びと打ち上げはダウンにし、起き上がった後まで無敵にする", function()
	for _, reaction in { "Knockback", "Launch" } :: { Damage.Reaction } do
		local outcome = Damage.resolve(defender(), attack(10, reaction), 10)
		expect(outcome.action).toBe("Down")
		local getUpEnd = 10 + ActionState.duration(Config.Action.Down) + ActionState.duration(Config.Action.GetUp)
		expect(outcome.invulnerableUntil).toBeNear(getUpEnd + Config.Damage.GetUpInvulnerable)
	end
	expect(Config.Action.Down.Next).toBe("GetUp")
end)

test("のけぞらない間でもダウンは起こす", function()
	local outcome = Damage.resolve(defender({ flinchImmuneUntil = 20 }), attack(10, "Knockback"), 10)
	expect(outcome.action).toBe("Down")
end)

test("反応の無い攻撃はダメージだけで中断しない", function()
	local outcome = Damage.resolve(defender(), attack(10, "None"), 10)
	expect(outcome.result).toBe("Hit")
	expect(outcome.action).toBe(nil)
	expect(outcome.flinchImmuneUntil).toBe(0)
	expect(outcome.invulnerableUntil).toBe(0)
end)

test("奥義ゲージは受けたダメージ × GainPerDamageTaken だけ溜まる", function()
	local outcome = Damage.resolve(defender({ defense = 0 }), attack(40, "None"), 10)
	expect(outcome.amount).toBe(40)
	expect(outcome.gauge).toBeNear(40 * Config.Ougi.GainPerDamageTaken)
end)

test("引数の状態は書き換えない", function()
	local state = defender()
	Damage.resolve(state, attack(10, "Knockback"), 10)
	expect(state.invulnerableUntil).toBe(0)
	expect(state.flinchImmuneUntil).toBe(0)
end)
