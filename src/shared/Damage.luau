--!strict
-- プレイヤーの被ダメージの判定。受ける側の状態と攻撃から、無敵・防御の軽減・反応・奥義ゲージの増加を決める。
-- サーバーの被ダメージの窓口（DamageService）が使う。時刻は引数で受け取り、Roblox の API は使わない。
--
-- - 奥義の最中と、出現直後の ForceField を持つ間は無敵で、何も起きない
-- - 与ダメージは Stats.damage で求め、威力を受ける側の防御で軽減する
-- - のけぞりは、明けてから FlinchImmunity 秒の間は起こさない（ダメージは受ける）
-- - 吹き飛びと打ち上げはダウンにする。ダウンと起き上がりの間と、その後の GetUpInvulnerable 秒は無敵
-- - 奥義ゲージは、受けたダメージ × GainPerDamageTaken だけ溜まる
-- 数値は Config.luau の Damage 節と Action 節にある。

local ActionState = require("./ActionState")
local Config = require("./Config")
local Stats = require("./Stats")

export type Reaction = Config.Reaction

-- 攻撃1回ぶん
export type Attack = {
	-- 攻撃元の位置
	origin: vector,
	-- 受ける側の防御で軽減する前のダメージ
	power: number,
	reaction: Reaction,
}

-- 受ける側の状態
export type Defender = {
	-- 今の行動。nil は待機
	action: string?,
	defense: number,
	-- 出現直後の ForceField を持っているか
	forceField: boolean,
	-- 無敵が切れる時刻
	invulnerableUntil: number,
	-- のけぞらない間が切れる時刻
	flinchImmuneUntil: number,
}

export type Result = "Hit" | "Invulnerable"

export type Outcome = {
	result: Result,
	-- 体力から引く量
	amount: number,
	-- 反応として始める行動（Flinch か Down）。中断しないなら nil
	action: string?,
	-- 奥義ゲージの増加
	gauge: number,
	-- この攻撃を受けた後の、無敵とのけぞらない間が切れる時刻
	invulnerableUntil: number,
	flinchImmuneUntil: number,
}

local Damage = {}

Damage.reactions = { "None", "Flinch", "Knockback", "Launch" } :: { Reaction }

-- 最中は無敵になる行動
local INVULNERABLE_ACTIONS: { [string]: boolean } = {
	Ougi = true,
}

-- 攻撃を受け付けない状態か
function Damage.isInvulnerable(defender: Defender, now: number): boolean
	if defender.forceField or now < defender.invulnerableUntil then
		return true
	end
	return defender.action ~= nil and INVULNERABLE_ACTIONS[defender.action] == true
end

-- 攻撃を受けた結果。引数の表は書き換えない
function Damage.resolve(defender: Defender, attack: Attack, now: number): Outcome
	local outcome: Outcome = {
		result = "Invulnerable",
		amount = 0,
		action = nil,
		gauge = 0,
		invulnerableUntil = defender.invulnerableUntil,
		flinchImmuneUntil = defender.flinchImmuneUntil,
	}
	if Damage.isInvulnerable(defender, now) then
		return outcome
	end

	outcome.result = "Hit"
	outcome.amount = Stats.damage(1, attack.power, defender.defense)
	outcome.gauge = outcome.amount * Config.Ougi.GainPerDamageTaken

	local reaction = attack.reaction
	if reaction == "Flinch" then
		if now >= defender.flinchImmuneUntil then
			outcome.action = "Flinch"
			outcome.flinchImmuneUntil = now + ActionState.duration(Config.Action.Flinch) + Config.Damage.FlinchImmunity
		end
	elseif reaction == "Knockback" or reaction == "Launch" then
		outcome.action = "Down"
		outcome.invulnerableUntil = now
			+ ActionState.duration(Config.Action.Down)
			+ ActionState.duration(Config.Action.GetUp)
			+ Config.Damage.GetUpInvulnerable
	end
	return outcome
end

return Damage
