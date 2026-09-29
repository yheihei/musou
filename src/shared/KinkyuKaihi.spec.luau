--!strict
local ActionState = require("./ActionState")
local Config = require("./Config")
local KinkyuKaihi = require("./KinkyuKaihi")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

local PARAMS: KinkyuKaihi.Params = {
	Distance = 14,
	Duration = 0.3,
	Invulnerable = 0.3,
	Recovery = 0.1,
	RecoveryPerChain = 0.15,
	MaxRecovery = 0.4,
	ChainDecay = 0.6,
}

test("1回目の後隙は Recovery", function()
	local count = KinkyuKaihi.nextCount(KinkyuKaihi.newChain(), 10, PARAMS)
	expect(count).toBe(1)
	expect(KinkyuKaihi.recovery(count, PARAMS)).toBeNear(0.1)
end)

test("続けて出すほど後隙が伸び、上限で止まる", function()
	local chain = KinkyuKaihi.newChain()
	local recoveries = {}
	local t = 10
	for _ = 1, 4 do
		local count = KinkyuKaihi.nextCount(chain, t, PARAMS)
		table.insert(recoveries, KinkyuKaihi.recovery(count, PARAMS))
		chain = KinkyuKaihi.record(chain, t, PARAMS)
		-- 後隙が明けた直後に次を出す
		t += PARAMS.Duration + KinkyuKaihi.recovery(count, PARAMS) - 0.3
	end
	expect(recoveries[1]).toBeNear(0.1)
	expect(recoveries[2]).toBeNear(0.25)
	expect(recoveries[3]).toBeNear(0.4)
	expect(recoveries[4]).toBeNear(0.4)
end)

test("時間がたつと続けた回数が減り、後隙が戻る", function()
	local chain = KinkyuKaihi.record(KinkyuKaihi.record(KinkyuKaihi.newChain(), 10, PARAMS), 10.5, PARAMS)
	expect(chain.count).toBe(2)
	-- 前の回避から ChainDecay 秒の手前ならまだ3回目
	expect(KinkyuKaihi.nextCount(chain, 11.09, PARAMS)).toBe(3)
	-- ChainDecay 秒ごとに1つ減る
	expect(KinkyuKaihi.nextCount(chain, 11.1, PARAMS)).toBe(2)
	expect(KinkyuKaihi.nextCount(chain, 11.7, PARAMS)).toBe(1)
	expect(KinkyuKaihi.nextCount(chain, 20, PARAMS)).toBe(1)
end)

test(
	"タイムラインは動いている間と後隙で、明けるまで次の行動を受け付けない",
	function()
		local timeline = KinkyuKaihi.timeline(2, PARAMS)
		expect(timeline.Startup).toBe(0)
		expect(timeline.Active).toBeNear(0.3)
		expect(timeline.Recovery).toBeNear(0.25)
		expect(timeline.CancelFrom).toBeNear(ActionState.duration(timeline))
		expect(timeline.Advance).toBe(14)
		expect(timeline.Next).toBe("Guard")
	end
)

test("Config の無敵の秒数は動いている間より長くない", function()
	local p = Config.KinkyuKaihi
	expect(p.Invulnerable > 0).toBe(true)
	expect(p.Invulnerable <= p.Duration + 1e-9).toBe(true)
	expect(p.MaxRecovery >= p.Recovery).toBe(true)
end)
