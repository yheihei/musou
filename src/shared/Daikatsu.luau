--!strict
-- 秘計の大喝の対象と動揺の補正。発動者から Radius 以内の相手（上忍・首領・プレイヤー・部隊）を選び、
-- 相手の強化の秘計を打ち消して動揺させる。範囲と倍率は Config.luau の Daikatsu 節、動揺の時間は Hikei 節の
-- Duration.Daikatsu にある。位置は水平の (x, z) で受け取る。Roblox の API は使わない。
--
-- - 対象は発動者の相手の軍のものだけ。同じ軍は対象にしない
-- - 潜んでいる伏兵部隊は、奇襲するまで見つからないので対象にしない
-- - 動揺した上忍・首領・プレイヤーは、攻撃と防御に倍率を掛ける（Stats.luau の補正）
-- - 動揺した部隊は、動揺の間だけ士気を Shiki 下げる（Shiki.luau の doyo）

local Config = require("./Config")
local Gun = require("./Gun")
local Stats = require("./Stats")

export type Params = Config.DaikatsuSection

-- 対象の種類。プレイヤー、上忍か首領、部隊
export type Kind = "Player" | "Jonin" | "Butai"

-- 大喝の対象の候補
export type Candidate = {
	kind: Kind,
	-- プレイヤーは UserId の文字列、上忍と首領はキャラクター ID、部隊は部隊 ID
	id: string,
	gun: Gun.Gun,
	x: number,
	z: number,
	-- 相手から見えない（潜んでいる伏兵部隊）か
	hidden: boolean?,
}

local Daikatsu = {}

-- 候補のうち、(x, z) にいる gun の軍の発動者の大喝の対象になるものを、候補の順に返す
function Daikatsu.targetsOf(
	x: number,
	z: number,
	gun: Gun.Gun,
	candidates: { Candidate },
	params: Params?
): { Candidate }
	local p = params or Config.Daikatsu
	local result = {}
	for _, candidate in candidates do
		if candidate.gun == gun or candidate.hidden then
			continue
		end
		local dx, dz = candidate.x - x, candidate.z - z
		if math.sqrt(dx * dx + dz * dz) <= p.Radius then
			table.insert(result, candidate)
		end
	end
	return result
end

-- 動揺した上忍・首領・プレイヤーの能力値へ足す補正
function Daikatsu.doyoModifiers(params: Params?): { Stats.Modifier }
	local p = params or Config.Daikatsu
	return {
		{ stat = "Attack", multiply = p.Attack },
		{ stat = "Defense", multiply = p.Defense },
	}
end

-- 動揺した部隊の士気を下げる量
function Daikatsu.doyoShiki(params: Params?): number
	local p = params or Config.Daikatsu
	return p.Shiki
end

return Daikatsu
