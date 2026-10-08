--!strict
-- 能力値の計算。基本値に補正（秘計、支配エリア、特技など）を足して能力値を求め、
-- 技の倍率・攻撃・防御から与ダメージを求める。プレイヤーと上忍・首領で共通に使う。
-- 基本値と係数は Config.luau の Stats 節にある。Roblox の API は使わない。

local Config = require("./Config")

export type Values = Config.StatValues
export type StatName = "MaxHealth" | "Attack" | "Defense" | "WalkSpeed" | "AttackSpeed"

-- 能力値の補正。基本値に add を足してから multiply を掛ける
export type Modifier = {
	stat: StatName,
	add: number?,
	multiply: number?,
}

local Stats = {}

Stats.names = { "MaxHealth", "Attack", "Defense", "WalkSpeed", "AttackSpeed" } :: { StatName }

-- 能力値の画面に出す名前
Stats.displayNames = {
	MaxHealth = "体力",
	Attack = "攻撃",
	Defense = "防御",
	WalkSpeed = "移動速度",
	AttackSpeed = "攻撃の速さ",
} :: { [StatName]: string }

-- 能力値の名前（Stats.names のどれか）か
function Stats.isName(value: unknown): boolean
	return type(value) == "string" and table.find(Stats.names, value :: StatName) ~= nil
end

-- キャラクターの基本の能力値。定義が無ければ nil
function Stats.baseOf(characterId: string): Values?
	return Config.Stats.Characters[characterId]
end

-- 上忍か首領（NPC）の基本の能力値。キャラクターごとの値はまだ無く、役目（首領か）で決める
function Stats.npcBaseOf(shuryo: boolean): Values
	return if shuryo then Config.Stats.Shuryo else Config.Stats.Jonin
end

-- 基本値に補正を足した能力値を返す。
-- 能力値ごとに (基本値 + add の合計) × multiply の積 を求め、0 未満にはしない
function Stats.compute(base: Values, modifiers: { Modifier }): Values
	local adds: { [string]: number } = {}
	local multiplies: { [string]: number } = {}
	for _, modifier in modifiers do
		adds[modifier.stat] = (adds[modifier.stat] or 0) + (modifier.add or 0)
		multiplies[modifier.stat] = (multiplies[modifier.stat] or 1) * (modifier.multiply or 1)
	end
	local source: { [string]: number } = base :: any
	local result: { [string]: number } = table.clone(source)
	for _, name in Stats.names do
		local value = (source[name] + (adds[name] or 0)) * (multiplies[name] or 1)
		result[name] = math.max(value, 0)
	end
	return result :: any
end

-- 与ダメージ。技の倍率 × 攻撃 を、防御が高いほど小さくする。
-- 防御が DefenseHalf のとき半分になり、下限は MinDamage
function Stats.damage(multiplier: number, attack: number, defense: number, params: Config.StatsSection?): number
	local p = params or Config.Stats
	local reduction = p.DefenseHalf / (p.DefenseHalf + math.max(defense, 0))
	return math.max(multiplier * attack * reduction, p.MinDamage)
end

return Stats
