--!strict
-- 交戦の計算。敵味方の部隊が押し合うあいだの損害を、前線幅に上限を付けた
-- ランチェスター一次則に士気を掛ける形で求める。Roblox の API は使わない。
--
-- 1. 前線で刃を交える兵数は前線幅で頭打ちにし、前線の後ろに控える兵も重みを掛けて押す力に数える
--    押す力 = (前線の兵数 + 控えの兵数 × 控えの重み) × 軍の強さ × 支配エリアの倍率 × 士気の補正
-- 2. 士気の補正は相手との士気の差に比例させ、下限と上限で抑える
--    士気の補正 = 1 + (自分の士気 - 相手の士気) × 士気の効き方
-- 3. 1秒あたりの損害は、相手の押す力 × 損害の割合。一次則なので自分の兵数には比例しない
-- 4. 兵数は整数で持ち、1人に満たない損害は端数として次の計算へ持ち越す
--
-- 前線幅・控えの重み・士気の効き方などは引数で受け取る。値は Config.luau の Kosen 節にある。
--
-- 戦場でどの部隊どうしが交戦するかは match が決める。交戦していない敵味方の部隊が近づくと、近い組から交戦を始める。
-- 同時の相手は1部隊で、交戦中の敵の部隊に近づいた部隊はその手前で待つ。
--
-- 両軍の上忍がいる部隊どうしの交戦では、上忍同士も戦う（joninStep）。
-- 1秒あたりの与ダメージは、JoninPower を技の倍率にした Stats.damage に士気の補正を掛けたもの。
-- 味方軍の上忍は、率いる部隊の士気が相手より JoninShikiThreshold 以上高いときだけ敵の上忍を削れる。
-- 敵軍の上忍に士気の条件は無い。

local Config = require("./Config")
local Gun = require("./Gun")
local Stats = require("./Stats")

export type Params = Config.KosenSection

-- 交戦する部隊の片側
export type Side = {
	-- 兵数（整数）
	heisu: number,
	-- 前の計算から持ち越した損害の端数（0 以上 1 未満）。無ければ 0
	fraction: number?,
	shiki: number,
	-- 軍ごとの強さの倍率。無ければ 1
	strength: number?,
	-- 支配エリアの倍率。無ければ 1
	shihaiArea: number?,
}

export type SideResult = {
	-- 計算後の兵数（整数、0 以上）
	heisu: number,
	-- 次の計算へ持ち越す損害の端数
	fraction: number,
	-- この計算で減った兵数
	loss: number,
	-- 計算後の押す力
	push: number,
}

export type Winner = "A" | "B" | "Draw"

export type Result = {
	a: SideResult,
	b: SideResult,
	-- どちらかの兵数が 0 になったか
	settled: boolean,
	-- 決着したときの勝者。両方同時に 0 になったら Draw
	winner: Winner?,
}

-- 交戦の相手を決めるときの部隊。位置は水平の (x, z)
export type Unit = {
	id: string,
	gun: Gun.Gun,
	position: { x: number, z: number },
}

export type Pair = { a: string, b: string }

export type Match = {
	-- 新しく交戦を始める組（部隊 ID）
	pairs: { Pair },
	-- 交戦中の敵の部隊の手前で待つ部隊
	waiting: { [string]: boolean },
}

-- 上忍同士の戦いの片側
export type JoninSide = {
	gun: Gun.Gun,
	-- 今の体力
	health: number,
	attack: number,
	defense: number,
	-- 率いる部隊の士気
	shiki: number,
}

export type JoninResult = {
	-- 計算後の体力（0 以上）
	a: number,
	b: number,
	-- どちらかの体力が 0 になったときの勝者。両方同時に 0 になったら Draw
	winner: Winner?,
}

local Kosen = {}

-- 士気の差による押す力の倍率
function Kosen.shikiHosei(shiki: number, opponentShiki: number, params: Params?): number
	local p = params or Config.Kosen
	return math.clamp(1 + (shiki - opponentShiki) * p.ShikiEffect, p.ShikiHoseiMin, p.ShikiHoseiMax)
end

-- side が opponent を押す力
function Kosen.push(side: Side, opponent: Side, params: Params?): number
	local p = params or Config.Kosen
	local heisu = math.max(side.heisu, 0)
	local zensen = math.min(heisu, p.Zensenhaba)
	local reserve = heisu - zensen
	return (zensen + reserve * p.ReserveWeight)
		* (side.strength or 1)
		* (side.shihaiArea or 1)
		* Kosen.shikiHosei(side.shiki, opponent.shiki, p)
end

local function sideResult(side: Side, heisu: number, fraction: number, push: number): SideResult
	return {
		heisu = heisu,
		fraction = fraction,
		loss = math.max(math.floor(side.heisu), 0) - heisu,
		push = push,
	}
end

-- a と b が dt 秒押し合った後の状態を返す。引数の表は書き換えない。
-- dt が長いときは MaxStep 秒ずつ刻み、減った兵数を次の刻みの押す力に反映する
function Kosen.step(a: Side, b: Side, dt: number, params: Params?): Result
	local p = params or Config.Kosen
	-- 刻みごとに兵数を書き換えるので写しを使う
	local sideA = table.clone(a)
	local sideB = table.clone(b)
	sideA.heisu = math.max(math.floor(a.heisu), 0)
	sideB.heisu = math.max(math.floor(b.heisu), 0)
	local fractionA = a.fraction or 0
	local fractionB = b.fraction or 0

	local elapsed = math.max(dt, 0)
	local steps = math.max(math.ceil(elapsed / p.MaxStep), 1)
	local h = elapsed / steps
	for _ = 1, steps do
		if sideA.heisu == 0 or sideB.heisu == 0 then
			break
		end
		-- 損害は両側同時に求める
		local lossA = fractionA + Kosen.push(sideB, sideA, p) * p.LossRate * h
		local lossB = fractionB + Kosen.push(sideA, sideB, p) * p.LossRate * h
		local wholeA = math.min(math.floor(lossA), sideA.heisu)
		local wholeB = math.min(math.floor(lossB), sideB.heisu)
		sideA.heisu -= wholeA
		sideB.heisu -= wholeB
		fractionA = if sideA.heisu == 0 then 0 else lossA - wholeA
		fractionB = if sideB.heisu == 0 then 0 else lossB - wholeB
	end

	local winner: Winner? = nil
	if sideA.heisu == 0 and sideB.heisu == 0 then
		winner = "Draw"
	elseif sideB.heisu == 0 then
		winner = "A"
	elseif sideA.heisu == 0 then
		winner = "B"
	end

	return {
		a = sideResult(a, sideA.heisu, fractionA, Kosen.push(sideA, sideB, p)),
		b = sideResult(b, sideB.heisu, fractionB, Kosen.push(sideB, sideA, p)),
		settled = winner ~= nil,
		winner = winner,
	}
end

-- 上忍 side が opponent に与える 1 秒あたりのダメージ。味方軍の上忍は、率いる部隊の士気が相手より
-- JoninShikiThreshold 以上高くなければ 0。敵軍の上忍に士気の条件は無い
function Kosen.joninDamage(side: JoninSide, opponent: JoninSide, params: Params?): number
	local p = params or Config.Kosen
	if side.gun == "Mikatagun" and side.shiki - opponent.shiki < p.JoninShikiThreshold then
		return 0
	end
	return Stats.damage(p.JoninPower, side.attack, opponent.defense) * Kosen.shikiHosei(side.shiki, opponent.shiki, p)
end

-- 両軍の上忍がいる部隊どうしの交戦で、上忍 a と b が dt 秒戦った後の体力を返す。引数の表は書き換えない
function Kosen.joninStep(a: JoninSide, b: JoninSide, dt: number, params: Params?): JoninResult
	local p = params or Config.Kosen
	local elapsed = math.max(dt, 0)
	local healthA = math.max(a.health - Kosen.joninDamage(b, a, p) * elapsed, 0)
	local healthB = math.max(b.health - Kosen.joninDamage(a, b, p) * elapsed, 0)
	local winner: Winner? = nil
	if healthA == 0 and healthB == 0 then
		winner = "Draw"
	elseif healthB == 0 then
		winner = "A"
	elseif healthA == 0 then
		winner = "B"
	end
	return { a = healthA, b = healthB, winner = winner }
end

-- 交戦を始められる敵味方の組の候補
type Candidate = { a: Unit, b: Unit, distance: number }

local function distanceOf(a: Unit, b: Unit): number
	local dx, dz = b.position.x - a.position.x, b.position.z - a.position.z
	return math.sqrt(dx * dx + dz * dz)
end

-- 交戦していない部隊（engaged に無い部隊）どうしで、距離 distance 以内の敵味方を近い組から順に交戦させる。
-- 同時の相手は1部隊。組にならなかった部隊のうち、距離 distance 以内に敵の部隊がいるもの
-- （その敵は交戦中）は、その手前で待たせる。距離が同じ組は部隊 ID の順に決める
function Kosen.match(units: { Unit }, engaged: { [string]: boolean }, distance: number): Match
	local candidates: { Candidate } = {}
	for i = 1, #units do
		for j = i + 1, #units do
			local a, b = units[i], units[j]
			if a.gun ~= b.gun and not engaged[a.id] and not engaged[b.id] then
				local gap = distanceOf(a, b)
				if gap <= distance then
					-- 組の中の順も部隊 ID の順にそろえる
					if b.id < a.id then
						a, b = b, a
					end
					table.insert(candidates, { a = a, b = b, distance = gap })
				end
			end
		end
	end
	table.sort(candidates, function(x, y)
		if x.distance ~= y.distance then
			return x.distance < y.distance
		elseif x.a.id ~= y.a.id then
			return x.a.id < y.a.id
		end
		return x.b.id < y.b.id
	end)

	local busy: { [string]: boolean } = table.clone(engaged)
	local pairs: { Pair } = {}
	for _, candidate in candidates do
		if not busy[candidate.a.id] and not busy[candidate.b.id] then
			busy[candidate.a.id] = true
			busy[candidate.b.id] = true
			table.insert(pairs, { a = candidate.a.id, b = candidate.b.id })
		end
	end

	local waiting: { [string]: boolean } = {}
	for _, unit in units do
		if not busy[unit.id] then
			for _, other in units do
				if other.gun ~= unit.gun and busy[other.id] and distanceOf(unit, other) <= distance then
					waiting[unit.id] = true
					break
				end
			end
		end
	end
	return { pairs = pairs, waiting = waiting }
end

return Kosen
