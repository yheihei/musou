--!strict
local ActionState = require("./ActionState")
local Config = require("./Config")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

-- 攻撃は 0.5 秒で終わり、0.3 秒から次を受け付ける
local ATTACK: ActionState.Timeline = { Startup = 0.1, Active = 0.1, Recovery = 0.3, CancelFrom = 0.3, Advance = 0 }
local CHARGE: ActionState.Timeline = { Startup = 0.2, Active = 0.2, Recovery = 0.6, CancelFrom = 1, Advance = 0 }
local OUGI: ActionState.Timeline =
	{ Startup = 0, Active = 1, Recovery = 0, CancelFrom = 1, Advance = 0, Interrupt = true }
local HIRUMI: ActionState.Timeline = { Startup = 0, Active = 0, Recovery = 0.4, CancelFrom = 0.4, Advance = 0 }
local BUFFER_TIME = 0.4

local timelines: { [string]: ActionState.Timeline } = {
	Attack = ATTACK,
	ChargeKogeki = CHARGE,
	Ougi = OUGI,
}
local function timelineOf(action: string): ActionState.Timeline?
	return timelines[action]
end

local function step(state: ActionState.State, now: number, input: string?): (ActionState.State, string?)
	return ActionState.step(state, now, input, timelineOf, BUFFER_TIME)
end

test("待機中の入力はすぐにその行動を始める", function()
	local state, started = step(ActionState.new(), 10, "Attack")
	expect(started).toBe("Attack")
	expect(state.action).toBe("Attack")
	expect(state.startedAt).toBe(10)
end)

test("キャンセル受付の前の入力は始めず、受付の後の入力はすぐに始める", function()
	local state = step(ActionState.new(), 0, "Attack")
	local before, startedBefore = step(state, 0.29, "ChargeKogeki")
	expect(startedBefore).toBe(nil)
	expect(before.action).toBe("Attack")

	local after, startedAfter = step(state, 0.3, "ChargeKogeki")
	expect(startedAfter).toBe("ChargeKogeki")
	expect(after.action).toBe("ChargeKogeki")
	expect(after.startedAt).toBe(0.3)
end)

test("受付の前の入力は先行入力になり、受付が始まった時点で1回だけ始める", function()
	local state = step(ActionState.new(), 0, "Attack")
	state = step(state, 0.1, "Attack")
	expect(state.buffered).toBe("Attack")

	local started
	state, started = step(state, 0.2)
	expect(started).toBe(nil)
	state, started = step(state, 0.3)
	expect(started).toBe("Attack")
	expect(state.startedAt).toBe(0.3)
	expect(state.buffered).toBe(nil)
	state, started = step(state, 0.31)
	expect(started).toBe(nil)
end)

test("先行入力は1つだけ持ち、後の入力で上書きする", function()
	local state = step(ActionState.new(), 0, "Attack")
	state = step(state, 0.1, "Attack")
	state = step(state, 0.15, "ChargeKogeki")
	local _, started = step(state, 0.3)
	expect(started).toBe("ChargeKogeki")
end)

test("先行入力は BufferTime を過ぎると捨てる", function()
	local state = step(ActionState.new(), 0, "ChargeKogeki")
	state = step(state, 0.1, "Attack")
	local later, started = step(state, 1)
	expect(started).toBe(nil)
	expect(later.buffered).toBe(nil)
end)

test("行動は発生・持続・硬直を合わせた時間で終わり、待機に戻る", function()
	expect(ActionState.duration(ATTACK)).toBeNear(0.5)
	local state = step(ActionState.new(), 0, "Attack")
	expect(step(state, 0.49).action).toBe("Attack")
	expect(step(state, 0.5).action).toBe(nil)
end)

test("割り込める行動はキャンセル受付の前でも始める", function()
	local state = step(ActionState.new(), 0, "ChargeKogeki")
	local next, started = step(state, 0.1, "Ougi")
	expect(started).toBe("Ougi")
	expect(next.action).toBe("Ougi")
end)

test("割り込める行動も同じ行動には割り込まない", function()
	local state = step(ActionState.new(), 0, "Ougi")
	local next, started = step(state, 0.5, "Ougi")
	expect(started).toBe(nil)
	expect(next.startedAt).toBe(0)
end)

test("始められない行動の入力は捨てる", function()
	local state, started = step(ActionState.new(), 0, "Jump")
	expect(started).toBe(nil)
	expect(state.action).toBe(nil)
	expect(state.buffered).toBe(nil)
end)

test("先行入力が始められなくなっていたら捨てる", function()
	local canOugi = true
	local function gated(action: string): ActionState.Timeline?
		if action == "Ougi" and not canOugi then
			return nil
		end
		return timelines[action]
	end
	local state = ActionState.step(ActionState.new(), 0, "Ougi", gated, BUFFER_TIME)
	state = ActionState.step(state, 0.5, "Ougi", gated, BUFFER_TIME)
	expect(state.buffered).toBe("Ougi")
	canOugi = false
	local next, started = ActionState.step(state, 1, nil, gated, BUFFER_TIME)
	expect(started).toBe(nil)
	expect(next.buffered).toBe(nil)
	expect(next.action).toBe(nil)
end)

test("被弾で今の行動と先行入力を捨てて中断する", function()
	local state = step(ActionState.new(), 0, "ChargeKogeki")
	state = step(state, 0.1, "Attack")
	local hit = ActionState.interrupt("Hirumi", 0.2, HIRUMI)
	expect(hit.action).toBe("Hirumi")
	expect(hit.buffered).toBe(nil)
	-- のけぞりの間の入力は先行入力になり、のけぞりが明けてから始まる
	local during = step(hit, 0.3, "Attack")
	expect(during.action).toBe("Hirumi")
	local _, started = step(during, 0.61)
	expect(started).toBe("Attack")
end)

test("続きのある行動は、終わった時点で続きの行動を始める", function()
	local down: ActionState.Timeline =
		{ Startup = 0, Active = 0, Recovery = 0.8, CancelFrom = 0.8, Advance = 0, Next = "GetUp" }
	local getUp: ActionState.Timeline = { Startup = 0, Active = 0, Recovery = 0.5, CancelFrom = 0.5, Advance = 0 }
	local function chainOf(action: string): ActionState.Timeline?
		if action == "GetUp" then
			return getUp
		end
		return timelines[action]
	end
	local state = ActionState.interrupt("Down", 0, down)
	local during, startedDuring = ActionState.step(state, 0.79, nil, chainOf, BUFFER_TIME)
	expect(startedDuring).toBe(nil)
	expect(during.action).toBe("Down")

	-- ダウンの間の入力は、起き上がりより後に回る
	local buffered = ActionState.step(state, 0.7, "Attack", chainOf, BUFFER_TIME)
	local next, started = ActionState.step(buffered, 0.8, nil, chainOf, BUFFER_TIME)
	expect(started).toBe("GetUp")
	expect(next.action).toBe("GetUp")
	expect(next.startedAt).toBe(0.8)
	local later, startedLater = ActionState.step(next, 1.3, "Attack", chainOf, BUFFER_TIME)
	expect(startedLater).toBe("Attack")
	expect(later.action).toBe("Attack")
end)

test("続きの行動を始められないときは待機に戻る", function()
	local down: ActionState.Timeline =
		{ Startup = 0, Active = 0, Recovery = 0.8, CancelFrom = 0.8, Advance = 0, Next = "GetUp" }
	local state = ActionState.interrupt("Down", 0, down)
	local next, started = step(state, 0.8)
	expect(started).toBe(nil)
	expect(next.action).toBe(nil)
end)

test("攻撃の速さで時間を割り、前進量はそのまま", function()
	local timeline: ActionState.Timeline = {
		Startup = 0.1,
		Active = 0.2,
		Recovery = 0.4,
		CancelFrom = 0.5,
		Advance = 2,
		Hits = {
			{
				Shape = { Kind = "Sphere", Radius = 5 },
				Power = 1,
				Reaction = "Flinch",
				Knockback = 0,
				Delay = 0.1,
				Repeat = 2,
				Interval = 0.05,
			},
		},
	}
	local slow = ActionState.scale(timeline, 0.8)
	expect(slow.Startup).toBeNear(0.125)
	expect(ActionState.duration(slow)).toBeNear(0.7 / 0.8)
	expect(slow.CancelFrom).toBeNear(0.625)
	expect(slow.Advance).toBe(2)
	local hit = (slow.Hits :: { any })[1]
	expect(hit.Delay).toBeNear(0.125)
	expect(hit.Interval).toBeNear(0.0625)
	-- 元の表は書き換えない
	expect(timeline.Startup).toBe(0.1)
	expect(((timeline.Hits :: { any })[1]).Delay).toBe(0.1)
	expect(ActionState.scale(timeline, 1)).toBe(timeline)
end)

test("判定は発生から Delay 秒後に出て、繰り返す判定は Interval ごとに並ぶ", function()
	local timeline: ActionState.Timeline = {
		Startup = 0.1,
		Active = 0.5,
		Recovery = 0.2,
		CancelFrom = 0.8,
		Advance = 0,
		Hits = {
			{
				Shape = { Kind = "Sphere", Radius = 5 },
				Power = 2,
				Reaction = "Knockback",
				Knockback = 30,
				Delay = 0.4,
			},
			{
				Shape = { Kind = "Sphere", Radius = 3 },
				Power = 0.5,
				Reaction = "Flinch",
				Knockback = 0,
				Repeat = 3,
				Interval = 0.1,
			},
		},
	}
	local times = {}
	local powers = {}
	for _, scheduled in ActionState.hits(timeline) do
		table.insert(times, math.floor(scheduled.at * 100 + 0.5) / 100)
		table.insert(powers, scheduled.hit.Power)
	end
	expect(times).toEqual({ 0.1, 0.2, 0.3, 0.5 })
	expect(powers).toEqual({ 0.5, 0.5, 0.5, 2 })
	expect(#ActionState.hits(ATTACK)).toBe(0)
end)

test("引数の状態は書き換えない", function()
	local state = ActionState.new()
	step(state, 0, "Attack")
	expect(state.action).toBe(nil)
	local attacking = step(state, 0, "Attack")
	step(attacking, 0.1, "Attack")
	expect(attacking.buffered).toBe(nil)
end)

test("Config の行動のタイムラインは長さが正で、受付は行動の中にある", function()
	local all = {}
	for _, set in { Config.Bukishu.Shuriken, Config.Bukishu.Katana } do
		for _, timeline in set.Attack do
			table.insert(all, timeline)
		end
		for _, timeline in set.ChargeKogeki do
			table.insert(all, timeline)
		end
	end
	for _, name in { "Ougi", "Flinch", "Down", "GetUp" } do
		table.insert(all, (Config.Action :: any)[name])
	end
	for _, timeline in all do
		expect(ActionState.duration(timeline) > 0).toBe(true)
		expect(timeline.CancelFrom >= 0).toBe(true)
		expect(timeline.CancelFrom <= ActionState.duration(timeline) + 1e-9).toBe(true)
	end
end)

test("被弾の反応の行動は、終わるまで次の行動を受け付けない", function()
	for _, name in { "Flinch", "Down", "GetUp" } do
		local timeline = (Config.Action :: any)[name] :: ActionState.Timeline
		expect(timeline.CancelFrom).toBeNear(ActionState.duration(timeline))
	end
end)

test("奥義の持続は奥義の攻撃の回数 × 間隔と同じ", function()
	expect(Config.Action.Ougi.Active).toBeNear(Config.Ougi.Pulses * Config.Ougi.PulseInterval)
	expect(Config.Action.Ougi.Interrupt).toBe(true)
end)
