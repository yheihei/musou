--!strict
-- 奥義ゲージのストック。溜まった本数（stock）と、次の1本までの量（gauge）で持つ。
-- 1本分の量・本数の上限・最初の本数は Config.luau の Ougi 節にある。Roblox の API は使わない。
--
-- - 溜まった量が1本分に届くと本数を1つ増やし、あふれた分は次の1本へ繰り越す
-- - 本数が上限に届いたら、それ以上は溜まらない（次の1本までの量は 0 のまま）
-- - 奥義1回で1本使う。次の1本までの量はそのまま残る。1本も無ければ使えない

local Config = require("./Config")

export type Gauge = {
	stock: number,
	gauge: number,
}

export type Params = {
	PerStock: number,
	MaxStock: number,
	InitialStock: number,
}

local OugiGauge = {}

local function paramsOf(params: Params?): Params
	return params or Config.Ougi
end

-- 出撃したときの値
function OugiGauge.initial(params: Params?): Gauge
	return { stock = paramsOf(params).InitialStock, gauge = 0 }
end

-- 溜まっている量の合計（本数 × 1本分 + 次の1本までの量）
function OugiGauge.total(value: Gauge, params: Params?): number
	return value.stock * paramsOf(params).PerStock + value.gauge
end

-- 合計の量から本数と次の1本までの量を求める。0 から上限の本数ぶんの量までに収める
function OugiGauge.fromTotal(total: number, params: Params?): Gauge
	local p = paramsOf(params)
	local capped = math.clamp(total, 0, p.MaxStock * p.PerStock)
	local stock = math.floor(capped / p.PerStock)
	return { stock = stock, gauge = capped - stock * p.PerStock }
end

-- amount だけ溜める。負の量は足さない。引数の表は書き換えない
function OugiGauge.add(value: Gauge, amount: number, params: Params?): Gauge
	return OugiGauge.fromTotal(OugiGauge.total(value, params) + math.max(amount, 0), params)
end

-- 1本使う。使えたら true と使った後の値を、1本も無ければ false と元の値を返す
function OugiGauge.consume(value: Gauge): (boolean, Gauge)
	if value.stock < 1 then
		return false, value
	end
	return true, { stock = value.stock - 1, gauge = value.gauge }
end

return OugiGauge
