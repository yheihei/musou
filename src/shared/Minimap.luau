--!strict
-- ミニマップの描き方の計算と、サーバーが複製する Attribute の名前。描くのはクライアントの MinimapController、
-- 範囲と出撃メンバーの位置の複製はサーバーの MinimapService。Roblox の API は使わない。
--
-- - 北（ワールドの z の -）を上にする。地図の座標は左上が (0, 0) のピクセルで、右が x の +、下が y の +
-- - 範囲は出撃したステージの区画の範囲の目印。長い辺を地図の一辺に合わせ、縦横の縮尺はそろえる
-- - 範囲の外の位置は地図の縁に寄せて出す（clampToMap）
-- - 向きは北から時計回りの度（東が 90）

local Minimap = {}

-- 出撃したステージの区画の範囲の中心と大きさ。workspace の Attribute で、Vector2 の X と Y にワールドの X と Z
Minimap.CENTER_ATTRIBUTE = "MinimapCenter"
Minimap.SIZE_ATTRIBUTE = "MinimapSize"
-- 出撃メンバーの位置（Vector2 の X と Y にワールドの X と Z）と向き（北から時計回りの度）。Player の Attribute
Minimap.POSITION_ATTRIBUTE = "MinimapPosition"
Minimap.FACING_ATTRIBUTE = "MinimapFacing"

-- 範囲の大きさ sizeX・sizeZ（スタッド）を一辺 mapSize（ピクセル）の地図に収める縮尺（1 スタッドあたりのピクセル）
function Minimap.scaleOf(sizeX: number, sizeZ: number, mapSize: number): number
	local longest = math.max(sizeX, sizeZ)
	if longest <= 0 then
		return 0
	end
	return mapSize / longest
end

-- ワールドの (x, z) を地図のピクセルの位置にする。centerX・centerZ は範囲の中心、scale は縮尺、mapSize は地図の一辺
function Minimap.toMap(
	x: number,
	z: number,
	centerX: number,
	centerZ: number,
	scale: number,
	mapSize: number
): (number, number)
	return mapSize / 2 + (x - centerX) * scale, mapSize / 2 + (z - centerZ) * scale
end

-- 地図のピクセルの位置を地図の中に収める。範囲の外にいる仲間を地図の縁に出すときに使う
function Minimap.clampToMap(px: number, py: number, mapSize: number): (number, number)
	return math.clamp(px, 0, mapSize), math.clamp(py, 0, mapSize)
end

-- 水平の向き (lookX, lookZ) を、北から時計回りの度（0 以上 360 未満）にする。向きが無ければ 0
function Minimap.facingOf(lookX: number, lookZ: number): number
	if lookX == 0 and lookZ == 0 then
		return 0
	end
	local degrees = math.deg(math.atan2(lookX, -lookZ))
	return degrees % 360
end

return Minimap
