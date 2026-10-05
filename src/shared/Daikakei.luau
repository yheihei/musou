--!strict
-- 秘計の大火計の計算。大火計地域の中の相手の部隊の兵数をどれだけ減らすかを決める。
-- 威力・割合は Config.luau の Daikakei 節、地域を選ぶ距離は Hikei 節の TargetRange.Daikakei にある。Roblox の API は使わない。
--
-- - 部隊の兵数は、今の兵数に HeisuRate を掛けた数だけ減らす。端数は切り上げ、兵数より多くは減らさない

local Config = require("./Config")

export type Params = Config.DaikakeiSection

local Daikakei = {}

-- 兵数 heisu の部隊から減らす兵数
function Daikakei.heisuLoss(heisu: number, params: Params?): number
	local p = params or Config.Daikakei
	if heisu <= 0 then
		return 0
	end
	return math.min(math.ceil(heisu * p.HeisuRate), heisu)
end

return Daikakei
