--!strict
-- 敵（仮の湧き処理の下忍と上忍）がプレイヤーを囲むときの立ち位置。敵は体ではプレイヤーにも敵にもぶつからないので
-- （CollisionGroups）、重ならないように立ち位置を計算で決める。Roblox の API は使わない。
--
-- - 敵はプレイヤーの中心から手前の距離（standOff）で止まる。プレイヤーの中まで入らない
-- - 止まる位置は、プレイヤーから見て今の敵の側。プレイヤーが近づいてきたら、敵は下がって間をあける
-- - 近くの敵と体（半径の和）が重なっていたら、重なった分だけ離れる向きへずらす
-- - ずらした位置がプレイヤーの中心から手前の距離より近ければ、手前の距離まで外へ押し戻す
--   （周りの敵に押されて、プレイヤーの中へ入り込まないように）
-- - 位置は水平の (x, z) で扱う

export type Point = { x: number, z: number }

-- 近くの敵。半径は体の横幅の半分
export type Neighbor = { x: number, z: number, radius: number }

export type Goal = {
	-- 向かう位置
	point: Point,
	-- 今の敵からプレイヤーの中心までの水平の距離
	distance: number,
	-- 近くの敵と重なっていて、ずらしたか
	shifted: boolean,
}

local EnemySpacing = {}

-- 止まる位置からこの距離（スタッド）より離れていなければ、歩かずにその場で止まる（行ったり来たりしないように）
EnemySpacing.TOLERANCE = 0.75

-- 敵の今の位置 enemy（半径 radius）から、プレイヤーの中心 target を囲むときに向かう位置。
-- standOff はプレイヤーの中心から止まる位置までの距離、neighbors はほかの敵
function EnemySpacing.goal(enemy: Point, radius: number, target: Point, standOff: number, neighbors: { Neighbor }): Goal
	local dx, dz = enemy.x - target.x, enemy.z - target.z
	local distance = math.sqrt(dx * dx + dz * dz)
	-- プレイヤーと同じ位置にいるときは、決まった向き（東）へ下がる
	local awayX, awayZ = 1, 0
	if distance > 1e-6 then
		awayX, awayZ = dx / distance, dz / distance
	end
	local x, z = target.x + awayX * standOff, target.z + awayZ * standOff

	local shiftX, shiftZ = 0, 0
	for _, other in neighbors do
		local ox, oz = enemy.x - other.x, enemy.z - other.z
		local gap = math.sqrt(ox * ox + oz * oz)
		local overlap = radius + other.radius - gap
		if overlap > 0 then
			-- 同じ位置に重なっているときは、プレイヤーを中心に横（時計回りの向き）へずらす
			local nx, nz = -awayZ, awayX
			if gap > 1e-6 then
				nx, nz = ox / gap, oz / gap
			end
			shiftX += nx * overlap
			shiftZ += nz * overlap
		end
	end
	local shifted = shiftX ~= 0 or shiftZ ~= 0
	local gx, gz = x + shiftX, z + shiftZ
	local rx, rz = gx - target.x, gz - target.z
	local reach = math.sqrt(rx * rx + rz * rz)
	if reach < standOff then
		if reach > 1e-6 then
			gx, gz = target.x + rx / reach * standOff, target.z + rz / reach * standOff
		else
			gx, gz = x, z
		end
	end
	return { point = { x = gx, z = gz }, distance = distance, shifted = shifted }
end

-- 向かう位置へ歩くか。止まる位置の近くにいて、ほかの敵とも重なっていなければ歩かない
function EnemySpacing.shouldMove(goal: Goal, standOff: number, tolerance: number?): boolean
	return goal.shifted or math.abs(goal.distance - standOff) > (tolerance or EnemySpacing.TOLERANCE)
end

return EnemySpacing
