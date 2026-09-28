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

local Config = require("./Config")

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

return Kosen
