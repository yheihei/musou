--!strict
-- 交戦中の部隊の下忍の個体の並び（前線）。2つの部隊の位置を結ぶ線の中ほどに前線を置き、両部隊の個体を向かい合わせて並べる。
-- 並ぶ位置・向き・向かい合う相手と、交戦の損害で倒れる前線の個体を決める。Roblox の API は使わない。位置は水平の (x, z)。
-- 数値は Config.luau の Zensen 節と、Kosen 節の Zensenhaba（前線幅）にある。
--
-- 並び（layout）
-- - 前線は、2つの部隊の位置の中点を通り、2つの部隊を結ぶ線に直交する。前線の個体は、中点から Gap の半分だけ
--   自分の部隊の側に横1列に並ぶ。両軍の前線の列は Gap だけ離れて向かい合う
-- - 個体はみな、相手の部隊の方（自分の部隊の位置から相手の部隊の位置への向き）を向く
-- - 列は前線幅（Zensenhaba）の数の決まった位置（列の中の位置。1 から前線幅までの番号）を持つ。列の中の位置は、
--   2つの部隊を結ぶ線を中ほどにして Spacing の間隔で横に並び、両軍の同じ番号の位置が向かい合う
-- - 前線（0 番目の列）の後ろ（自分の部隊の側）に、RowGap ずつ下がって控えの列が続く。前線に並ぶのは部隊ごとに
--   前線幅まで。控えは攻撃の動作をしない
-- - 個体は前の並びの位置（列と列の中の位置）を引き継ぐ。前の個体が倒れたら、同じ番号の位置の後ろの控えが1つずつ前へ出て、
--   ほかの個体は動かない（前線の個体が減っても、残りの個体を詰め直さない）
-- - 前線の位置が空き、その後ろに控えがいなければ、新しい個体か、一番近い控えが入る。どちらもいなければ空けたままにする
-- - 新しい個体（前の並びの位置が無い個体）は、前線に近い順に、空いた前線の位置を中ほどから埋める（選んだ個体を横の位置の
--   順に並べて、歩くときに行き違わない）。残りは、控えの少ない番号の位置の後ろに、横の位置の近い方から並ぶ
-- - 前線の個体が向かい合う相手は、相手の前線の同じ番号の位置の個体。いなければ隣の位置の個体（両隣にいれば番号の小さい方）。
--   隣にもいなければ相手はいない（前線の個体の数が違う部隊どうしでは、多い側の端の個体に相手がいない）
-- - 2つの部隊が同じ位置にいるときは、1つ目の部隊が東（+x）を向く
--
-- 倒れる個体（chooseFallen）
-- - 交戦の損害で兵数が減ったら、その部隊の前線の個体を減った数だけ選ぶ。前線の個体が足りなければ全員
-- - 並ぶ位置に着いて相手と向かい合っている個体を先にし、並ぶ位置に近い順にする

local Config = require("./Config")

export type Point = { x: number, z: number }

-- 並べる個体。row と column は前の並びの列（0 が前線）と列の中の位置の番号（1 から前線幅まで）。前の並びに無ければ nil
export type Kotai = { id: string, x: number, z: number, row: number?, column: number? }

-- 交戦する部隊の片側。position は部隊の位置
export type Side = { position: Point, kotai: { Kotai } }

-- 個体の並ぶ位置
export type Slot = {
	point: Point,
	-- 列（0 が前線、1 から後ろへ控えの列）と、列の中の位置の番号（1 から前線幅まで）
	row: number,
	column: number,
	-- 前線の個体か（row が 0）
	front: boolean,
	-- 前線の個体が向かい合う相手の個体の ID。いなければ nil
	aite: string?,
}

export type SideLayout = {
	-- 個体の ID から引く並ぶ位置
	slots: { [string]: Slot },
	-- 個体が向く向き（水平の単位ベクトル）。自分の部隊の位置から相手の部隊の位置への向き
	look: Point,
}

export type Layout = {
	-- 前線の中ほど（2つの部隊の位置の中点）
	center: Point,
	a: SideLayout,
	b: SideLayout,
}

export type Params = {
	zensen: Config.ZensenSection?,
	-- 前線幅。省くと Config.luau の Kosen 節の Zensenhaba
	zensenhaba: number?,
}

-- 交戦の損害で倒れる個体の候補（前線の個体）
export type FallCandidate = {
	id: string,
	-- 並ぶ位置に着いて、相手と向かい合っているか
	engaged: boolean,
	-- 並ぶ位置までの水平の距離
	distance: number,
}

-- 並べるときの個体。depth は前線の中ほどから自分の部隊の側への深さ（前に出ているほど小さい）、
-- lateral は前線に沿った横の位置。row と column は前の並びの位置（引き継げなければ nil）
type Entry = { id: string, depth: number, lateral: number, row: number?, column: number? }

local Zensen = {}

-- 2つの部隊が同じ位置にいるときに、1つ目の部隊が向く向き（東）
local FALLBACK_LOOK: Point = { x = 1, z = 0 }
-- 距離の比べ方の許し（同じ近さなら、ID の順に決める）
local EPSILON = 1e-9

-- from から to への水平の単位ベクトル。同じ位置なら東
function Zensen.direction(from: Point, to: Point): Point
	local dx, dz = to.x - from.x, to.z - from.z
	local length = math.sqrt(dx * dx + dz * dz)
	if length < 1e-6 then
		return { x = FALLBACK_LOOK.x, z = FALLBACK_LOOK.z }
	end
	return { x = dx / length, z = dz / length }
end

-- 2つの水平の向きの角度の差（度。0〜180）。どちらかの長さがほぼ 0 なら nil
function Zensen.angle(look: Point, direction: Point): number?
	local lookLength = math.sqrt(look.x * look.x + look.z * look.z)
	local directionLength = math.sqrt(direction.x * direction.x + direction.z * direction.z)
	if lookLength < 1e-6 or directionLength < 1e-6 then
		return nil
	end
	local cos = (look.x * direction.x + look.z * direction.z) / (lookLength * directionLength)
	return math.deg(math.acos(math.clamp(cos, -1, 1)))
end

local function paramsOf(params: Params?): (Config.ZensenSection, number)
	local zensen = if params and params.zensen then params.zensen else Config.Zensen
	local zensenhaba = if params and params.zensenhaba then params.zensenhaba else Config.Kosen.Zensenhaba
	return zensen, math.max(math.floor(zensenhaba), 1)
end

-- 列の中の位置の番号 column の、2つの部隊を結ぶ線からの横のずれ
local function offsetOf(column: number, width: number, spacing: number): number
	return (column - (width + 1) / 2) * spacing
end

-- 前線に近い順（同じなら ID の順）
local function byDepth(p: Entry, q: Entry): boolean
	if p.depth ~= q.depth then
		return p.depth < q.depth
	end
	return p.id < q.id
end

-- 横の位置の順（同じなら ID の順）
local function byLateral(p: Entry, q: Entry): boolean
	if p.lateral ~= q.lateral then
		return p.lateral < q.lateral
	end
	return p.id < q.id
end

-- 前の並びの位置が、今の列の中の位置に引き継げるか（0 以上の列と、1 から width までの番号の整数）
local function inheritable(row: number?, column: number?, width: number): boolean
	return row ~= nil
		and column ~= nil
		and row >= 0
		and row == math.floor(row)
		and column >= 1
		and column <= width
		and column == math.floor(column)
end

-- 片側の個体を、列の中の位置の番号ごとに前から並べる。forward は相手の部隊の方への向き、side は前線に沿った横の向き
-- （両側で同じ向き）。並ぶ位置と、番号ごとの前線の個体の ID を返す
local function arrange(
	kotai: { Kotai },
	center: Point,
	forward: Point,
	side: Point,
	zensen: Config.ZensenSection,
	width: number
): ({ [string]: Slot }, { [number]: string })
	-- 番号ごとの個体（前から順）
	local columns: { { Entry } } = {}
	for column = 1, width do
		columns[column] = {}
	end
	-- 前の並びの位置を引き継ぐ。同じ位置を2体が持っていたら、後の個体は新しい個体として並べる
	local taken: { [string]: boolean } = {}
	local fresh: { Entry } = {}
	for _, item in kotai do
		local dx, dz = item.x - center.x, item.z - center.z
		local entry: Entry = {
			id = item.id,
			depth = -(dx * forward.x + dz * forward.z),
			lateral = dx * side.x + dz * side.z,
			row = item.row,
			column = item.column,
		}
		local row, column = item.row, item.column
		local key = if row and column then `{row}:{column}` else ""
		if row and column and inheritable(row, column, width) and not taken[key] then
			taken[key] = true
			table.insert(columns[column], entry)
		else
			table.insert(fresh, entry)
		end
	end
	-- 番号ごとに、前の列の順に詰める（前の個体が倒れたら、後ろの控えが1つずつ前へ出る）
	for _, members in columns do
		table.sort(members, function(p: Entry, q: Entry): boolean
			local rowP, rowQ = p.row :: number, q.row :: number
			if rowP ~= rowQ then
				return rowP < rowQ
			end
			return p.id < q.id
		end)
	end

	-- 前線の位置が空いた番号（個体が1体もいない番号）を、中ほどに近い順（同じなら番号の小さい順）に
	local middle = (width + 1) / 2
	local function emptyColumns(): { number }
		local result = {}
		for column = 1, width do
			if #columns[column] == 0 then
				table.insert(result, column)
			end
		end
		table.sort(result, function(p: number, q: number): boolean
			local gapP, gapQ = math.abs(p - middle), math.abs(q - middle)
			if gapP ~= gapQ then
				return gapP < gapQ
			end
			return p < q
		end)
		return result
	end

	-- 新しい個体は、前線に近い順に、空いた前線の位置を中ほどから埋める。選んだ個体を横の位置の順に、番号の順に並べる
	table.sort(fresh, byDepth)
	local empty = emptyColumns()
	local count = math.min(#empty, #fresh)
	local chosenColumns: { number } = {}
	local chosen: { Entry } = {}
	for index = 1, count do
		table.insert(chosenColumns, empty[index])
		table.insert(chosen, fresh[index])
	end
	table.sort(chosenColumns)
	table.sort(chosen, byLateral)
	for index = 1, count do
		table.insert(columns[chosenColumns[index]], chosen[index])
	end
	local rest: { Entry } = {}
	for index = count + 1, #fresh do
		table.insert(rest, fresh[index])
	end

	-- まだ空いた前線の位置があれば、控えのうち一番近い個体を前へ出す（その個体の後ろの控えは1つずつ前へ出る）
	local frontDepth = zensen.Gap / 2
	for _, column in emptyColumns() do
		local offset = offsetOf(column, width, zensen.Spacing)
		local bestColumn, bestIndex, bestDistance, bestId = 0, 0, math.huge, ""
		for from = 1, width do
			local members = columns[from]
			for index = 2, #members do
				local member = members[index]
				local dl, dd = member.lateral - offset, member.depth - frontDepth
				local distance = math.sqrt(dl * dl + dd * dd)
				if
					distance < bestDistance - EPSILON
					or (math.abs(distance - bestDistance) <= EPSILON and member.id < bestId)
				then
					bestColumn, bestIndex, bestDistance, bestId = from, index, distance, member.id
				end
			end
		end
		if bestColumn == 0 then
			break
		end
		table.insert(columns[column], table.remove(columns[bestColumn], bestIndex) :: Entry)
	end

	-- 残りの新しい個体は控えにする。控えの少ない番号の位置の後ろに、横の位置の近い方から並べる
	for _, entry in rest do
		local bestColumn, bestCount, bestGap = 1, math.huge, math.huge
		for column = 1, width do
			local size = #columns[column]
			local gap = math.abs(offsetOf(column, width, zensen.Spacing) - entry.lateral)
			if size < bestCount or (size == bestCount and gap < bestGap - EPSILON) then
				bestColumn, bestCount, bestGap = column, size, gap
			end
		end
		table.insert(columns[bestColumn], entry)
	end

	local slots: { [string]: Slot } = {}
	local frontIds: { [number]: string } = {}
	for column, members in columns do
		local offset = offsetOf(column, width, zensen.Spacing)
		for index, member in members do
			local row = index - 1
			local back = zensen.Gap / 2 + zensen.RowGap * row
			slots[member.id] = {
				point = {
					x = center.x - forward.x * back + side.x * offset,
					z = center.z - forward.z * back + side.z * offset,
				},
				row = row,
				column = column,
				front = row == 0,
				aite = nil,
			}
		end
		local first = members[1]
		if first then
			frontIds[column] = first.id
		end
	end
	return slots, frontIds
end

-- 前線の個体ごとに、相手の前線の同じ番号の位置の個体を向かい合う相手にする。いなければ隣の位置の個体
-- （両隣にいれば番号の小さい方）。隣にもいなければ相手はいない
local function pair(slots: { [string]: Slot }, frontIds: { [number]: string }, aiteIds: { [number]: string })
	for column, id in frontIds do
		slots[id].aite = aiteIds[column] or aiteIds[column - 1] or aiteIds[column + 1]
	end
end

-- 交戦する2つの部隊 a と b の個体を、前線と控えの列に並べる。a と b の個体の ID は重ねない
function Zensen.layout(a: Side, b: Side, params: Params?): Layout
	local zensen, width = paramsOf(params)
	local look = Zensen.direction(a.position, b.position)
	local back = { x = -look.x, z = -look.z }
	local center = { x = (a.position.x + b.position.x) / 2, z = (a.position.z + b.position.z) / 2 }
	-- 前線に沿った横の向き。両側で同じ向きを使い、同じ番号の位置を向かい合わせる
	local side = { x = -look.z, z = look.x }
	local slotsA, frontA = arrange(a.kotai, center, look, side, zensen, width)
	local slotsB, frontB = arrange(b.kotai, center, back, side, zensen, width)
	pair(slotsA, frontA, frontB)
	pair(slotsB, frontB, frontA)
	return {
		center = center,
		a = { slots = slotsA, look = look },
		b = { slots = slotsB, look = back },
	}
end

-- 交戦の損害で倒れる前線の個体を、減った兵数 loss だけ選んで ID を返す（候補が足りなければ全員）。
-- 並ぶ位置に着いて相手と向かい合っている個体を先にし、並ぶ位置に近い順、同じなら ID の順にする
function Zensen.chooseFallen(candidates: { FallCandidate }, loss: number): { string }
	local order = table.clone(candidates)
	table.sort(order, function(p: FallCandidate, q: FallCandidate): boolean
		if p.engaged ~= q.engaged then
			return p.engaged
		elseif p.distance ~= q.distance then
			return p.distance < q.distance
		end
		return p.id < q.id
	end)
	local result = {}
	for index = 1, math.min(math.max(math.floor(loss), 0), #order) do
		table.insert(result, order[index].id)
	end
	return result
end

return Zensen
