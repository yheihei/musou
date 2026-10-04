--!strict
-- 人数による調整。出撃したときのパーティーの人数で、敵軍の上忍と首領の体力と、兵力を増やし、
-- 1人でも4人でも同じくらいの難しさにする。倍率の表は Config.luau の PartySize 節にある。Roblox の API は使わない。
--
-- - 人数は出撃したときのパーティーの人数で決め、途中で抜けても変えない（呼ぶ側が出撃したときの人数を渡す）
-- - 人数は 1 から表の長さまでに収める
-- - 味方軍の上忍と首領は人数で変えない
-- - 兵力は Config.luau の Stage 節の Heiryoku に倍率を掛け、端数は四捨五入する
-- - 難易度は M1 では「普通」の1つだけなので、難易度による違いは持たない

local Config = require("./Config")
local Gun = require("./Gun")
local Stats = require("./Stats")

export type Params = Config.PartySizeSection

local PartySize = {}

-- 表の人数 count の倍率。人数は 1 から表の長さまでに収める。表が空なら 1
function PartySize.multiplier(list: { number }, count: number): number
	if #list == 0 then
		return 1
	end
	local index = math.clamp(math.floor(count), 1, #list)
	return list[index]
end

-- 敵軍の上忍と首領の体力の倍率
function PartySize.joninHealthOf(count: number, params: Params?): number
	local p = params or Config.PartySize
	return PartySize.multiplier(p.JoninHealth, count)
end

-- 人数 count で出撃したときの兵力。base は 1 人のときの兵力（Stage 節の Heiryoku）
function PartySize.heiryokuOf(base: number, count: number, params: Params?): number
	local p = params or Config.PartySize
	return math.floor(base * PartySize.multiplier(p.Heiryoku, count) + 0.5)
end

-- 人数 count で出撃したときの、上忍と首領の能力値の補正。敵軍だけ体力の最大を上げ、味方軍は空
function PartySize.modifiersOf(gun: Gun.Gun, count: number, params: Params?): { Stats.Modifier }
	if gun ~= "Tekigun" then
		return {}
	end
	local multiplier = PartySize.joninHealthOf(count, params)
	if multiplier == 1 then
		return {}
	end
	return { { stat = "MaxHealth", multiply = multiplier } }
end

return PartySize
