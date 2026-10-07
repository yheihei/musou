--!strict
-- 実体化圏の判定。プレイヤーの周りに入った上忍と首領を個体として出し、離れたらデータに戻す（下忍は #76）。
-- 出現と消滅の半径に差を付け、縁を行き来しても出入りを繰り返さないようにする。
-- 半径は Config.luau の Jittaikaken 節にある。位置は水平の (x, z) で持ち、Roblox の API は使わない。
--
-- - まだ出ていなければ、一番近いプレイヤーが AppearRadius 以内に入ったら出す
-- - 出ていれば、一番近いプレイヤーが DisappearRadius より離れるまで残す
-- - プレイヤーが1人もいなければ出さない（出ていれば消す）

local Config = require("./Config")

export type Params = Config.JittaikakenSection

-- 水平の位置。x は東、z は南が +（ワールドの座標）
export type Point = { x: number, z: number }

local Jittaikaken = {}

-- position から一番近いプレイヤーまでの水平の距離。players が空なら nil
function Jittaikaken.nearestDistance(position: Point, players: { Point }): number?
	local best: number? = nil
	for _, player in players do
		local dx, dz = player.x - position.x, player.z - position.z
		local distance = math.sqrt(dx * dx + dz * dz)
		if best == nil or distance < best then
			best = distance
		end
	end
	return best
end

-- 個体を出しておくか。present は今出ているか、distance は一番近いプレイヤーまでの水平の距離（いなければ nil）
function Jittaikaken.shouldAppear(present: boolean, distance: number?, params: Params?): boolean
	local p = params or Config.Jittaikaken
	if distance == nil then
		return false
	end
	if present then
		return distance <= p.DisappearRadius
	end
	return distance <= p.AppearRadius
end

return Jittaikaken
