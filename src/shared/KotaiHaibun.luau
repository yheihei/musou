--!strict
-- 下忍の個体の枠の配分。サーバー全体で個体として出せる下忍の数（上限）を、近いプレイヤーのまとまりごとに分ける。
-- プレイヤーが別々の場所にいても、上限を1か所で使い切らず、各プレイヤーの周りに偏りなく出す（#85）。
-- 数値は Config.luau の KotaiHaibun 節にある。Roblox の API は使わない。位置は水平の (x, z)。
--
-- - GroupDistance 以内のプレイヤーをたどってつなぎ、1つのまとまりにする（A と B、B と C が近ければ A・B・C で1つ）
-- - 上限は、まとまりの人数の比で分ける（離れた4人なら 1/4 ずつ、4人が1か所なら全部を1つのまとまりに）
-- - 部隊を渡すと、まとまりが使う数は近くの部隊の兵数を超えない。部隊は、Reach 以内にいる一番近いプレイヤーの
--   まとまりに数える。どのプレイヤーからも Reach より遠い部隊は数えない
-- - 兵数が足りずに使い切らなかった分は、ほかのまとまりへ人数の比で回す（近くに部隊のいないプレイヤーの分も回す）
-- - 端数は、切り捨てた残りの大きい順に1つずつ足す（同じなら先のまとまり）。合計は上限と兵数の合計の小さい方
-- - 部隊を渡さないときは、兵数の制限なしとして分ける

local Config = require("./Config")

export type Params = Config.KotaiHaibunSection

-- プレイヤー。id はプレイヤーを見分ける文字列（名前など）
export type Member = { id: string, x: number, z: number }

-- 部隊。heisu は個体として出せる兵数（借り出す元）
export type ButaiInput = { id: string, x: number, z: number, heisu: number }

export type Group = {
	-- まとまりのプレイヤーの id（名前の順）
	members: { string },
	-- 個体として出せる下忍の数（0 以上の整数）
	quota: number,
	-- 近くの部隊の兵数の合計。部隊を渡さなかったら nil（制限なし）
	demand: number?,
	-- このまとまりに数えた部隊の id（名前の順）。部隊を渡さなかったら空
	butai: { string },
}

local KotaiHaibun = {}

local function distance(ax: number, az: number, bx: number, bz: number): number
	local dx, dz = bx - ax, bz - az
	return math.sqrt(dx * dx + dz * dz)
end

-- プレイヤーを、groupDistance 以内をたどってつないだまとまりに分ける。
-- まとまりの中は id の順、まとまりどうしは先頭の id の順に並べる
function KotaiHaibun.group(members: { Member }, groupDistance: number): { { Member } }
	local sorted = table.clone(members)
	table.sort(sorted, function(a, b)
		return a.id < b.id
	end)
	local groupOf: { [number]: number } = {}
	local groups: { { Member } } = {}
	for start = 1, #sorted do
		if not groupOf[start] then
			local group = {}
			table.insert(groups, group)
			local index = #groups
			groupOf[start] = index
			local queue = { start }
			local head = 1
			while head <= #queue do
				local current = sorted[queue[head]]
				head += 1
				table.insert(group, current)
				for other = 1, #sorted do
					if
						not groupOf[other]
						and distance(current.x, current.z, sorted[other].x, sorted[other].z) <= groupDistance
					then
						groupOf[other] = index
						table.insert(queue, other)
					end
				end
			end
			table.sort(group, function(a, b)
				return a.id < b.id
			end)
		end
	end
	return groups
end

-- 上限 cap を、重み weights の比で、各要素の上限 limits を超えないように分ける（端数を含む）。
-- 上限に届いた要素の残りは、ほかの要素へ重みの比で回す
local function waterFill(weights: { number }, limits: { number }, cap: number): { number }
	local result = table.create(#weights, 0)
	local active: { [number]: boolean } = {}
	for index, weight in weights do
		if weight > 0 and limits[index] > 0 then
			active[index] = true
		end
	end
	local remaining = cap
	while remaining > 0 do
		local total = 0
		for index in active do
			total += weights[index]
		end
		if total <= 0 then
			break
		end
		local saturated = false
		for index in active do
			if limits[index] <= remaining * weights[index] / total then
				result[index] = limits[index]
				remaining -= limits[index]
				active[index] = nil
				saturated = true
			end
		end
		if not saturated then
			for index in active do
				result[index] = remaining * weights[index] / total
			end
			break
		end
	end
	return result
end

-- 上限 total を、重み weights の比で、各要素の上限 limits を超えない整数に分ける。
-- 上限に届いた要素の残りはほかの要素へ重みの比で回し、端数は切り捨てた残りの大きい順に1つずつ足す（同じなら先の要素）。
-- 合計は total（切り捨てた整数）と limits の合計の小さい方。重みが 0 か上限が 0 の要素は 0
function KotaiHaibun.split(weights: { number }, limits: { number }, total: number): { number }
	local whole = math.max(math.floor(total), 0)
	local shares = waterFill(weights, limits, whole)
	local result: { number } = {}
	local given = 0
	local totalLimit = 0
	for index, share in shares do
		local floor = math.floor(share + 1e-9)
		result[index] = floor
		given += floor
		if weights[index] > 0 then
			totalLimit += limits[index]
		end
	end
	local order = {}
	for index = 1, #weights do
		table.insert(order, index)
	end
	table.sort(order, function(a, b)
		local ra, rb = shares[a] - result[a], shares[b] - result[b]
		if math.abs(ra - rb) > 1e-9 then
			return ra > rb
		end
		return a < b
	end)
	local leftover = math.min(whole, totalLimit) - given
	while leftover > 0 do
		local progressed = false
		for _, index in order do
			if leftover <= 0 then
				break
			end
			if weights[index] > 0 and result[index] < limits[index] then
				result[index] += 1
				leftover -= 1
				progressed = true
			end
		end
		if not progressed then
			break
		end
	end
	return result
end

-- 上限 cap を、プレイヤーのまとまりごとに分ける。butai を渡すと、近くの部隊の兵数を超えない
function KotaiHaibun.allocate(members: { Member }, cap: number, butai: { ButaiInput }?, params: Params?): { Group }
	local p = params or Config.KotaiHaibun
	local groups = KotaiHaibun.group(members, p.GroupDistance)
	local groupIndexOf: { [string]: number } = {}
	for index, group in groups do
		for _, member in group do
			groupIndexOf[member.id] = index
		end
	end

	local demands: { number } = table.create(#groups, if butai then 0 else math.huge)
	local butaiOf: { { string } } = {}
	for index = 1, #groups do
		butaiOf[index] = {}
	end
	if butai then
		for _, entry in butai do
			if entry.heisu > 0 then
				-- 一番近いプレイヤーのまとまりに数える（同じ距離なら id の小さいプレイヤー）
				local best: Member? = nil
				local bestDistance = math.huge
				for _, member in members do
					local d = distance(entry.x, entry.z, member.x, member.z)
					if d < bestDistance or (d == bestDistance and best ~= nil and member.id < best.id) then
						best, bestDistance = member, d
					end
				end
				if best and bestDistance <= p.Reach then
					local index = groupIndexOf[best.id]
					demands[index] += entry.heisu
					table.insert(butaiOf[index], entry.id)
				end
			end
		end
	end

	local weights = {}
	for index, group in groups do
		weights[index] = #group
	end
	local quotas = KotaiHaibun.split(weights, demands, cap)

	local result: { Group } = {}
	for index, group in groups do
		local ids = {}
		for _, member in group do
			table.insert(ids, member.id)
		end
		local names = butaiOf[index]
		table.sort(names)
		table.insert(result, {
			members = ids,
			quota = quotas[index],
			demand = if butai then demands[index] else nil,
			butai = names,
		})
	end
	return result
end

-- 位置 (x, z) に一番近いプレイヤーのまとまりの番号（groups の添字）。まとまりが無ければ nil
function KotaiHaibun.groupIndexAt(groups: { Group }, members: { Member }, x: number, z: number): number?
	local indexOf: { [string]: number } = {}
	for index, group in groups do
		for _, id in group.members do
			indexOf[id] = index
		end
	end
	local best: number? = nil
	local bestDistance = math.huge
	for _, member in members do
		local index = indexOf[member.id]
		local d = distance(x, z, member.x, member.z)
		if index and d < bestDistance then
			best, bestDistance = index, d
		end
	end
	return best
end

return KotaiHaibun
