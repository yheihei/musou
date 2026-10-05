--!strict
-- 攻撃判定の形。前方の箱・扇・球・直線・輪と、判定の原点・対象の位置から当たった対象を求める。
-- 位置は vector（Roblox では Vector3 と同じ値）で受け取り、Instance には触らない。
-- 部隊データの下忍の位置にも、個体の位置にも同じ関数を使う。
--
-- - 箱・扇・直線は原点の向きの水平成分を前とし、高さは原点を中心に上下へ広げる
-- - 対象は半径を持つ円柱として扱い、半径の分だけ形からはみ出していても当てる
-- - 直線は飛び道具用。前へ進んだ距離を速さで割った秒数を、当たるまでの時間差として返す
-- - 輪は原点を中心に、水平の距離が内側と外側の半径の間に入る対象に当てる（向きは見ない。金遁の外へ広がる輪）
-- - 技の形は Config.luau の ShapeDef で書き、fromDef でこの形にする

local Config = require("./Config")

export type Box = {
	kind: "Box",
	-- 奥行き・幅・高さ（スタッド）
	range: number,
	width: number,
	height: number,
}

export type Sector = {
	kind: "Sector",
	radius: number,
	-- 扇の開き（度）。左右に半分ずつ開く
	angle: number,
	height: number,
}

export type Sphere = {
	kind: "Sphere",
	radius: number,
}

export type Line = {
	kind: "Line",
	length: number,
	-- 太さ（直径）
	width: number,
	-- 飛ぶ速さ（スタッド/秒）
	speed: number,
}

export type Ring = {
	kind: "Ring",
	-- 内側と外側の半径（水平。スタッド）
	inner: number,
	outer: number,
	height: number,
}

export type Shape = Box | Sector | Sphere | Line | Ring

-- 判定の原点。look は向きで、水平成分だけを使う
export type Origin = {
	position: vector,
	look: vector,
}

export type Target<T> = {
	ref: T,
	position: vector,
	-- 対象の水平の半径。無ければ 0
	radius: number?,
}

export type Hit<T> = {
	ref: T,
	-- 原点からの距離。箱と直線は前への距離、扇は水平の距離、球は直線距離
	distance: number,
	-- 当たるまでの時間差（秒）。直線以外は 0
	delay: number,
}

local HitShape = {}

local DEFAULT_FORWARD = vector.create(0, 0, -1)
local UP = vector.create(0, 1, 0)

-- 向きの水平成分の単位ベクトル。真上や真下を向いているときは -Z を前とする
local function forwardOf(look: vector): vector
	local flat = vector.create(look.x, 0, look.z)
	if vector.magnitude(flat) < 1e-6 then
		return DEFAULT_FORWARD
	end
	return vector.normalize(flat)
end

-- 対象の位置を原点から見た前・右・上の成分に分ける
local function localOf(origin: Origin, position: vector): (number, number, number)
	local forward = forwardOf(origin.look)
	local right = vector.cross(forward, UP)
	local offset = position - origin.position
	return vector.dot(offset, forward), vector.dot(offset, right), offset.y
end

-- Config.luau の形の定義を判定の形にする。高さを省いた形は defaultHeight を使う
function HitShape.fromDef(def: Config.ShapeDef, defaultHeight: number): Shape
	local height = def.Height or defaultHeight
	if def.Kind == "Box" then
		return { kind = "Box", range = def.Range :: number, width = def.Width :: number, height = height }
	elseif def.Kind == "Sector" then
		return { kind = "Sector", radius = def.Radius :: number, angle = def.Angle :: number, height = height }
	elseif def.Kind == "Sphere" then
		return { kind = "Sphere", radius = def.Radius :: number }
	elseif def.Kind == "Ring" then
		return { kind = "Ring", inner = def.Inner or 0, outer = def.Radius :: number, height = height }
	end
	return { kind = "Line", length = def.Length :: number, width = def.Width :: number, speed = def.Speed :: number }
end

-- 原点の向きを水平に yaw 度だけ回す。上から見て時計回り（右）が正
function HitShape.rotate(origin: Origin, yaw: number): Origin
	if yaw == 0 then
		return origin
	end
	local forward = forwardOf(origin.look)
	local right = vector.cross(forward, UP)
	local radians = math.rad(yaw)
	return { position = origin.position, look = forward * math.cos(radians) + right * math.sin(radians) }
end

-- 対象が形に入っているか。入っていれば true と原点からの距離を返す
function HitShape.test(shape: Shape, origin: Origin, position: vector, radius: number?): (boolean, number)
	local r = radius or 0
	if shape.kind == "Sphere" then
		local distance = vector.magnitude(position - origin.position)
		return distance <= shape.radius + r, distance
	end

	local forward, side, up = localOf(origin, position)
	if shape.kind == "Ring" then
		local distance = math.sqrt(forward * forward + side * side)
		local inside = distance + r >= shape.inner
			and distance - r <= shape.outer
			and math.abs(up) <= shape.height / 2 + r
		return inside, distance
	elseif shape.kind == "Box" then
		local inside = forward >= -r
			and forward <= shape.range + r
			and math.abs(side) <= shape.width / 2 + r
			and math.abs(up) <= shape.height / 2 + r
		return inside, math.max(forward, 0)
	elseif shape.kind == "Sector" then
		local distance = math.sqrt(forward * forward + side * side)
		if distance > shape.radius + r or math.abs(up) > shape.height / 2 + r then
			return false, distance
		end
		if distance <= r then
			-- 原点に重なっている対象は向きによらず当てる
			return true, distance
		end
		local angle = math.deg(math.atan2(math.abs(side), forward))
		local margin = math.deg(math.asin(math.min(r / distance, 1)))
		return angle <= shape.angle / 2 + margin, distance
	else
		local across = math.sqrt(side * side + up * up)
		local inside = forward >= -r and forward <= shape.length + r and across <= shape.width / 2 + r
		return inside, math.max(forward, 0)
	end
end

-- 形に入った対象を、原点に近い順に返す
function HitShape.query<T>(shape: Shape, origin: Origin, targets: { Target<T> }): { Hit<T> }
	local hits: { Hit<T> } = {}
	for _, target in targets do
		local inside, distance = HitShape.test(shape, origin, target.position, target.radius)
		if inside then
			local delay = if shape.kind == "Line" then distance / shape.speed else 0
			table.insert(hits, { ref = target.ref, distance = distance, delay = delay })
		end
	end
	table.sort(hits, function(a, b)
		return a.distance < b.distance
	end)
	return hits
end

return HitShape
