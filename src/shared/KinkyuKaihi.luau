--!strict
-- 緊急回避。ガード中に方向を入れて出す回避の、続けて出した回数と後隙とタイムラインを求める。
-- 数値は Config.luau の KinkyuKaihi 節にある。時刻は引数で受け取り、Roblox の API は使わない。
--
-- - 続けて出すほど後隙が伸び、上限で止まる
-- - 続けた回数は、前の回避を始めてから ChainDecay 秒ごとに1つ減る
-- - 動いている間（Active）の前半 Invulnerable 秒は無敵にする（無敵の判定は Damage.luau）

local Config = require("./Config")

export type Params = Config.KinkyuKaihiSection

-- 続けて出した回数と、最後に回避を始めた時刻
export type Chain = {
	count: number,
	lastAt: number,
}

local KinkyuKaihi = {}

local function paramsOf(params: Params?): Params
	return params or Config.KinkyuKaihi
end

function KinkyuKaihi.newChain(): Chain
	return { count = 0, lastAt = -math.huge }
end

-- 時刻 now に出す回避が、続けて何回目か（1から）
function KinkyuKaihi.nextCount(chain: Chain, now: number, params: Params?): number
	local p = paramsOf(params)
	-- 境界ちょうどで減らすため、時刻の引き算の丸めの誤差の分だけ足す
	local decayed = math.floor((math.max(now - chain.lastAt, 0) + 1e-9) / p.ChainDecay)
	return math.max(chain.count - decayed, 0) + 1
end

-- 続けて count 回目の回避の後隙（秒）
function KinkyuKaihi.recovery(count: number, params: Params?): number
	local p = paramsOf(params)
	return math.min(p.Recovery + (math.max(count, 1) - 1) * p.RecoveryPerChain, p.MaxRecovery)
end

-- 続けて count 回目の回避のタイムライン。動き終わって後隙が明けるまで次の行動を受け付けない
function KinkyuKaihi.timeline(count: number, params: Params?): Config.ActionTimeline
	local p = paramsOf(params)
	local recovery = KinkyuKaihi.recovery(count, p)
	return {
		Startup = 0,
		Active = p.Duration,
		Recovery = recovery,
		CancelFrom = p.Duration + recovery,
		Advance = p.Distance,
		-- ガードを押したままならガードに戻る
		Next = "Guard",
	}
end

-- 時刻 now に回避を始めた後の続けた回数
function KinkyuKaihi.record(chain: Chain, now: number, params: Params?): Chain
	return { count = KinkyuKaihi.nextCount(chain, now, params), lastAt = now }
end

return KinkyuKaihi
