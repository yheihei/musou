--!strict
-- 敵（仮の湧き処理の下忍と上忍）がプレイヤーを囲むときの立ち位置。敵は体ではプレイヤーにも敵にもぶつからないので
-- （CollisionGroups）、重ならないように立ち位置を計算で決める。Roblox の API は使わない。
--
-- - 敵はプレイヤーの中心から手前の距離（standOff）で止まる。プレイヤーの中まで入らない
-- - 止まる位置は、プレイヤーから見て今の敵の側。プレイヤーが近づいてきたら、敵は下がって間をあける
-- - 近くの敵と体（半径の和）が重なっていたら、重なった分だけ離れる向きへずらす
-- - ずらした位置がプレイヤーの中心から手前の距離より近ければ、手前の距離まで外へ押し戻す
--   （周りの敵に押されて、プレイヤーの中へ入り込まないように）
-- - まったく同じ位置に重なった敵どうしは、敵ごとに違う向き（spin）へずらす（同じ向きだと離れないため）
-- - プレイヤーの近くでは、向かう位置へ少しずつ進む（stepToward）。途中の位置も手前の距離より内側へは入れず、
--   囲みの輪の上を回り込む（2点を結ぶ弦をまっすぐ歩くと、プレイヤーの中を通るため）
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
-- standOff はプレイヤーの中心から止まる位置までの距離、neighbors はほかの敵。
-- spin は同じ位置に重なった敵からずらす向き（ラジアン）。敵ごとに違う値を渡す。省くとプレイヤーの周りの横の向き
function EnemySpacing.goal(
	enemy: Point,
	radius: number,
	target: Point,
	standOff: number,
	neighbors: { Neighbor },
	spin: number?
): Goal
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
			-- 同じ位置に重なっているときは、敵ごとの向き（無ければプレイヤーの周りの横の向き）へずらす
			local nx, nz = -awayZ, awayX
			if spin then
				nx, nz = math.cos(spin), math.sin(spin)
			end
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

-- 今の位置 enemy から向かう位置 goal へ、maxStep だけ進んだ途中の位置（goal が近ければ goal）。
-- 途中の位置がプレイヤーの中心 target から standOff より近ければ、standOff まで外へ押し出す
function EnemySpacing.stepToward(enemy: Point, goal: Point, target: Point, standOff: number, maxStep: number): Point
	local dx, dz = goal.x - enemy.x, goal.z - enemy.z
	local length = math.sqrt(dx * dx + dz * dz)
	local x, z = goal.x, goal.z
	if length > maxStep then
		x, z = enemy.x + dx / length * maxStep, enemy.z + dz / length * maxStep
	end
	local rx, rz = x - target.x, z - target.z
	local reach = math.sqrt(rx * rx + rz * rz)
	if reach < standOff and reach > 1e-6 then
		x, z = target.x + rx / reach * standOff, target.z + rz / reach * standOff
	end
	return { x = x, z = z }
end

-- 向かう位置へ歩くか。止まる位置の近くにいて、ほかの敵とも重なっていなければ歩かない
function EnemySpacing.shouldMove(goal: Goal, standOff: number, tolerance: number?): boolean
	return goal.shifted or math.abs(goal.distance - standOff) > (tolerance or EnemySpacing.TOLERANCE)
end

return EnemySpacing
