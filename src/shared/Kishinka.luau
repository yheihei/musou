--!strict
-- 秘計の鬼神化の補正。効果中の発動者（プレイヤー・上忍・首領）の攻撃と防御を上げ、のけぞらなくする。
-- 倍率は Config.luau の Kishinka 節、効果時間は Hikei 節の Duration.Kishinka にある。Roblox の API は使わない。
--
-- - 補正は能力値の補正（Stats.luau）として足す。プレイヤーにも上忍・首領にも同じ倍率を使う
-- - のけぞらないのは、のけぞり（Flinch）の反応だけ。吹き飛びと打ち上げはダウンになる

local Config = require("./Config")
local Stats = require("./Stats")

export type Params = Config.KishinkaSection

local Kishinka = {}

-- 効果中に能力値へ足す補正
function Kishinka.modifiers(params: Params?): { Stats.Modifier }
	local p = params or Config.Kishinka
	return {
		{ stat = "Attack", multiply = p.Attack },
		{ stat = "Defense", multiply = p.Defense },
	}
end

return Kishinka
