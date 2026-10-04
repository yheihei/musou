--!strict
-- 秘計の伏兵の奇襲の判定。潜んでいる伏兵部隊に、相手の部隊かプレイヤーが近づいたら奇襲する。
-- 距離は Config.luau の Fukuhei 節にある。Roblox の API は使わない。
--
-- - 奇襲の相手は、伏兵部隊から KishuRadius 以内にいる相手の軍の部隊のうち、一番近いもの。
--   潜んでいる部隊（相手の伏兵部隊）と、兵数の無い部隊は数えない。距離が同じなら一覧の先の部隊
-- - 相手の部隊がいなくても、伏兵部隊の相手の軍がプレイヤーの軍（味方軍）で、KishuRadius 以内に
--   生きているプレイヤーがいれば奇襲する（交戦する部隊は無い）

local Config = require("./Config")
local Gun = require("./Gun")

export type Params = Config.FukuheiSection

-- 水平の位置。x は東、z は南が +（ワールドの座標）
export type Point = { x: number, z: number }

export type Unit = {
	id: string,
	gun: Gun.Gun,
	position: Point,
	heisu: number,
	-- 潜んでいる伏兵部隊か
	fukuhei: boolean?,
}

local Fukuhei = {}

-- プレイヤーの軍
Fukuhei.PLAYER_GUN = "Mikatagun" :: Gun.Gun

local function distance(a: Point, b: Point): number
	local dx, dz = b.x - a.x, b.z - a.z
	return math.sqrt(dx * dx + dz * dz)
end

-- 伏兵部隊 fukuhei が奇襲するか。奇襲するなら true と、交戦する相手の部隊の ID（プレイヤーだけなら nil）を返す。
-- units は戦場の部隊、players は生きているプレイヤーの位置
function Fukuhei.kishuOf(fukuhei: Unit, units: { Unit }, players: { Point }, params: Params?): (boolean, string?)
	local p = params or Config.Fukuhei
	local opponent = Gun.opponentOf(fukuhei.gun)
	local best: string? = nil
	local bestDistance = math.huge
	for _, unit in units do
		if unit.gun == opponent and unit.heisu > 0 and not unit.fukuhei then
			local gap = distance(fukuhei.position, unit.position)
			if gap <= p.KishuRadius and gap < bestDistance then
				best = unit.id
				bestDistance = gap
			end
		end
	end
	if best then
		return true, best
	end
	if opponent == Fukuhei.PLAYER_GUN then
		for _, position in players do
			if distance(fukuhei.position, position) <= p.KishuRadius then
				return true, nil
			end
		end
	end
	return false, nil
end

return Fukuhei
