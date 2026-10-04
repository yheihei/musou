--!strict
-- 上忍が部隊を率いて目指すこと（方針）の判断。配置で部隊ごとに決めた方針（攻略・防衛・救援）と戦況から、
-- 部隊が目指す拠点か、迎え撃つ相手の部隊を決める。距離と割合は Config.luau の Hoshin 節にある。
-- Roblox の API は使わない。
--
-- - 攻略は、今いる拠点からつながりをたどった先の、道のりが一番近い相手の軍の拠点を目指す
-- - 防衛は、担当の拠点（配置で始まる拠点）の中心から GeigekiDistance 以内に来た相手の部隊のうち、
--   拠点に一番近い部隊を迎え撃つ。いなければ担当の拠点へ戻ってとどまる
-- - 救援は、耐久が上限の KyuenRate 以下に減り、攻める軍が範囲の中にいる自分の軍の拠点のうち、
--   道のりが一番近い拠点へ向かう。なければ担当の拠点へ戻ってとどまる
-- - 攻略で目指せる相手の拠点が無いときも、担当の拠点へ戻ってとどまる
-- - 道のりは、今いる拠点からつながりに沿って測る。たどれるのは自分の軍の拠点と、自分の軍が通れるつながり
--   （落石で塞がれたつながりは通らない）。相手の軍の拠点には入れるが、その先へは進まない（落としてから次を目指す）
-- - 目指す拠点までの道筋の、次に向かう拠点（next）も返す。部隊はつながりの経由点をたどって次の拠点へ向かう
-- - 首領は本陣の範囲にとどまる。範囲の外の位置は範囲の縁へ寄せる（clampToRange）

local Config = require("./Config")
local Gun = require("./Gun")
local Haichi = require("./Haichi")

export type Params = Config.HoshinSection

-- 水平の位置。x は東、z は南が +（ワールドの座標）
export type Point = { x: number, z: number }

export type Kyoten = {
	id: string,
	-- 所属の軍。どちらにも属さない拠点は nil
	gun: Gun.Gun?,
	-- 中心の水平の位置
	x: number,
	z: number,
	-- 耐久の上限に対する割合（0〜1）
	taikyuRate: number,
	-- 範囲の中に攻める軍がいるか
	kogeki: boolean,
}

export type Tsunagari = {
	-- 両端の拠点 ID
	kyotenA: string,
	kyotenB: string,
	-- 道のり（スタッド）。省くと両端の拠点の中心の距離
	length: number?,
	-- 通れない軍（落石で塞いだ区間は、相手の軍にだけ通れない）
	blocked: { [Gun.Gun]: boolean }?,
}

-- 方針で動かす部隊
export type Butai = {
	id: string,
	gun: Gun.Gun,
	position: Point,
	hoshin: Haichi.Hoshin,
	-- 担当の拠点（配置で始まる拠点）
	tanto: string,
	-- 今いる拠点（最後に着いた拠点）。無ければ位置に一番近い拠点から測る
	kyoten: string?,
}

-- 迎え撃つ候補の部隊（潜んでいる伏兵部隊は入れない）
export type Teki = {
	id: string,
	gun: Gun.Gun,
	position: Point,
}

-- 判断の結果。Kyoten は拠点を目指す（next は次に向かう拠点。道筋の上で着いていれば nil）、
-- Butai は相手の部隊を迎え撃つ、Stay はその場にとどまる
export type Decision = {
	kind: "Kyoten" | "Butai" | "Stay",
	kyoten: string?,
	next: string?,
	butai: string?,
	position: Point?,
}

-- 拠点までの道のりと、そこへ向かう最初の一歩（次の拠点）
export type Reach = {
	distance: number,
	next: string?,
}

local Hoshin = {}

local function distance(ax: number, az: number, bx: number, bz: number): number
	local dx, dz = bx - ax, bz - az
	return math.sqrt(dx * dx + dz * dz)
end

local function indexById(kyotenList: { Kyoten }): { [string]: Kyoten }
	local byId: { [string]: Kyoten } = {}
	for _, kyoten in kyotenList do
		byId[kyoten.id] = kyoten
	end
	return byId
end

-- 位置に一番近い拠点の ID。拠点が無ければ nil
function Hoshin.nearestKyoten(kyotenList: { Kyoten }, position: Point): string?
	local best: string? = nil
	local bestDistance = math.huge
	for _, kyoten in kyotenList do
		local gap = distance(position.x, position.z, kyoten.x, kyoten.z)
		if gap < bestDistance then
			best = kyoten.id
			bestDistance = gap
		end
	end
	return best
end

-- 軍 gun の部隊が拠点 from からつながりをたどって行ける拠点ごとの、道のりと次の拠点を返す。
-- from 自身は道のり 0 で次の拠点は nil。from 以外では、gun の拠点からだけ先へ進む（相手の軍と無所属の拠点には入れるが、
-- その先へは進まない）。gun が通れないつながりは通らない。表に無い拠点を指すつながりは無視する
function Hoshin.reach(
	kyotenList: { Kyoten },
	tsunagariList: { Tsunagari },
	gun: Gun.Gun,
	from: string
): { [string]: Reach }
	local byId = indexById(kyotenList)
	local result: { [string]: Reach } = {}
	if not byId[from] then
		return result
	end
	-- 拠点 ID から、つながった先の拠点 ID とその道のりの一覧を引く
	local neighbors: { [string]: { { id: string, length: number } } } = {}
	for _, tsunagari in tsunagariList do
		local a, b = byId[tsunagari.kyotenA], byId[tsunagari.kyotenB]
		local blocked = tsunagari.blocked
		if a and b and not (blocked and blocked[gun]) then
			local length = tsunagari.length or distance(a.x, a.z, b.x, b.z)
			neighbors[a.id] = neighbors[a.id] or {}
			neighbors[b.id] = neighbors[b.id] or {}
			table.insert(neighbors[a.id], { id = b.id, length = length })
			table.insert(neighbors[b.id], { id = a.id, length = length })
		end
	end

	-- 拠点の数は少ないので、道のりの一番短い拠点を毎回探して確定する（ダイクストラ法）
	result[from] = { distance = 0, next = nil }
	local done: { [string]: boolean } = {}
	while true do
		local current: string? = nil
		local currentDistance = math.huge
		for id, entry in result do
			if not done[id] and entry.distance < currentDistance then
				current = id
				currentDistance = entry.distance
			end
		end
		if not current then
			break
		end
		local id = current :: string
		done[id] = true
		local passable = id == from or byId[id].gun == gun
		if not passable then
			continue
		end
		for _, neighbor in neighbors[id] or {} do
			local total = currentDistance + neighbor.length
			local known = result[neighbor.id]
			if not done[neighbor.id] and (not known or total < known.distance) then
				-- from から出る最初の一歩は、その隣の拠点。そこから先は最初の一歩を受け継ぐ
				local first = if id == from then neighbor.id else result[id].next
				result[neighbor.id] = { distance = total, next = first }
			end
		end
	end
	return result
end

-- 拠点 target を目指す判断。道筋の上で着いていれば next は nil。つながりでたどれなければ、まっすぐ向かう（next は target）
local function toward(reach: { [string]: Reach }, start: string, target: string): Decision
	local entry = reach[target]
	local next = if entry then entry.next elseif target == start then nil else target
	return { kind = "Kyoten", kyoten = target, next = next, butai = nil, position = nil }
end

-- 候補の拠点のうち、道のりが一番近いもの。同じ道のりなら一覧の先の拠点。たどれる候補が無ければ nil
local function closest(kyotenList: { Kyoten }, reach: { [string]: Reach }, accept: (Kyoten) -> boolean): string?
	local best: string? = nil
	local bestDistance = math.huge
	for _, kyoten in kyotenList do
		local entry = reach[kyoten.id]
		if entry and accept(kyoten) and entry.distance < bestDistance then
			best = kyoten.id
			bestDistance = entry.distance
		end
	end
	return best
end

-- 部隊の方針から、目指す拠点か迎え撃つ相手の部隊を決める
function Hoshin.decide(
	butai: Butai,
	kyotenList: { Kyoten },
	tsunagariList: { Tsunagari },
	tekiList: { Teki },
	params: Params?
): Decision
	local p = params or Config.Hoshin
	local byId = indexById(kyotenList)
	local start = butai.kyoten
	if not start or not byId[start] then
		start = Hoshin.nearestKyoten(kyotenList, butai.position)
	end
	if not start then
		return { kind = "Stay", kyoten = nil, next = nil, butai = nil, position = nil }
	end
	local origin = start :: string
	local reach = Hoshin.reach(kyotenList, tsunagariList, butai.gun, origin)
	local opponent = Gun.opponentOf(butai.gun)

	if butai.hoshin == "Koryaku" then
		local target = closest(kyotenList, reach, function(kyoten)
			return kyoten.gun == opponent
		end)
		if target then
			return toward(reach, origin, target)
		end
	elseif butai.hoshin == "Boei" then
		local tanto = byId[butai.tanto]
		if tanto then
			local best: Teki? = nil
			local bestDistance = math.huge
			for _, teki in tekiList do
				if teki.gun == opponent then
					local gap = distance(tanto.x, tanto.z, teki.position.x, teki.position.z)
					if gap <= p.GeigekiDistance and gap < bestDistance then
						best = teki
						bestDistance = gap
					end
				end
			end
			if best then
				local target = best :: Teki
				return {
					kind = "Butai",
					kyoten = nil,
					next = nil,
					butai = target.id,
					position = { x = target.position.x, z = target.position.z },
				}
			end
		end
	elseif butai.hoshin == "Kyuen" then
		local target = closest(kyotenList, reach, function(kyoten)
			return kyoten.gun == butai.gun and kyoten.kogeki and kyoten.taikyuRate <= p.KyuenRate
		end)
		if target then
			return toward(reach, origin, target)
		end
	end

	-- 目指す先が無ければ担当の拠点へ戻ってとどまる
	if byId[butai.tanto] then
		return toward(reach, origin, butai.tanto)
	end
	return { kind = "Stay", kyoten = nil, next = nil, butai = nil, position = nil }
end

-- 範囲の目印から見た位置（localX・localZ）を、大きさ sizeX・sizeZ の範囲の中へ寄せる。中ならそのまま
function Hoshin.clampToRange(localX: number, localZ: number, sizeX: number, sizeZ: number): (number, number)
	return math.clamp(localX, -sizeX / 2, sizeX / 2), math.clamp(localZ, -sizeZ / 2, sizeZ / 2)
end

return Hoshin
