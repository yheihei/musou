--!strict
-- 秘計の爆破罠の計算。仕掛けた拠点の耐久が、上限の Rate を上から下へ越えた瞬間に1回だけ爆発する。
-- 割合と威力は Config.luau の Bakuhawana 節にある。発動できるかの確かめは Hikei.checkBakuhawana にある。
-- Roblox の API は使わない。
--
-- - 爆発する耐久は、耐久の上限 × Rate。ちょうどその値はまだ爆発しない（下回ったときに爆発する）
-- - 拠点の中の相手の部隊の兵数は、今の兵数に HeisuRate を掛けた数だけ減らす。端数は切り上げる

local Config = require("./Config")

export type Params = Config.BakuhawanaSection

local Bakuhawana = {}

-- 爆発する耐久
function Bakuhawana.threshold(maxTaikyu: number, params: Params?): number
	local p = params or Config.Bakuhawana
	return maxTaikyu * p.Rate
end

-- 耐久が before から after に変わったときに、爆発する耐久を上から下へ越えたか
function Bakuhawana.crossed(before: number, after: number, maxTaikyu: number, params: Params?): boolean
	local threshold = Bakuhawana.threshold(maxTaikyu, params)
	return before >= threshold and after < threshold
end

-- 兵数 heisu の部隊から減らす兵数
function Bakuhawana.heisuLoss(heisu: number, params: Params?): number
	local p = params or Config.Bakuhawana
	if heisu <= 0 then
		return 0
	end
	return math.min(math.ceil(heisu * p.HeisuRate), heisu)
end

return Bakuhawana
