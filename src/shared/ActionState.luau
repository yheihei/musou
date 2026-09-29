--!strict
-- 行動の状態遷移。攻撃・ガード・緊急回避・奥義・被弾を1つの状態で扱う。
-- 行動ごとのタイムライン（発生・持続・硬直・キャンセル受付・前進量）は Config.luau の Action 節にある。
-- 時刻は引数で受け取り、Roblox の API は使わない。
--
-- - 待機中の入力と、キャンセル受付が始まった後の入力は、すぐにその行動を始める
-- - 受付の前の入力は先行入力として1つだけ持ち（後の入力で上書き）、受付が始まった時点で1回だけ始める
-- - 先行入力は BufferTime 秒たつと捨てる
-- - 割り込める行動（Interrupt）は受付の前でも始める。同じ行動には割り込まない
-- - 被弾は interrupt で、今の行動と先行入力を捨てて始める
-- - 続き（Next）のある行動は、終わったときに先行入力より先に続きの行動を始める（ダウンの後の起き上がりなど）
-- - 行動を始められるかは呼び出し側が timelineOf で決める。nil を返した入力は捨てる

local Config = require("./Config")

export type Timeline = Config.ActionTimeline

export type State = {
	-- 今の行動。nil は待機
	action: string?,
	startedAt: number,
	timeline: Timeline?,
	-- 先行入力
	buffered: string?,
	bufferedAt: number,
}

-- 行動を始めるときにタイムラインを引く関数。始められないなら nil を返す
export type TimelineOf = (action: string) -> Timeline?

local ActionState = {}

function ActionState.new(): State
	return { action = nil, startedAt = 0, timeline = nil, buffered = nil, bufferedAt = 0 }
end

-- 行動の全体の長さ（発生 + 持続 + 硬直）
function ActionState.duration(timeline: Timeline): number
	return timeline.Startup + timeline.Active + timeline.Recovery
end

-- 次の行動を受け付けるか。待機中か、キャンセル受付が始まっていれば true
function ActionState.isCancelable(state: State, now: number): boolean
	local timeline = state.timeline
	if state.action == nil or timeline == nil then
		return true
	end
	return now - state.startedAt >= timeline.CancelFrom
end

local function start(action: string, timeline: Timeline, now: number): State
	return { action = action, startedAt = now, timeline = timeline, buffered = nil, bufferedAt = 0 }
end

-- 終わった行動を待機に戻し、古い先行入力を捨てる
local function expire(state: State, now: number, bufferTime: number): State
	local next = state
	local timeline = state.timeline
	if state.action ~= nil and timeline ~= nil and now - state.startedAt >= ActionState.duration(timeline) then
		next = table.clone(next)
		next.action = nil
		next.timeline = nil
	end
	if next.buffered ~= nil and now - next.bufferedAt > bufferTime then
		next = if next == state then table.clone(next) else next
		next.buffered = nil
	end
	return next
end

-- 時刻 now に入力 input が届いた（または届かなかった）ときの次の状態と、始めた行動を返す。
-- 入力が無くても毎フレーム呼び、終わった行動を待機に戻して先行入力を始める。引数の状態は書き換えない
function ActionState.step(
	state: State,
	now: number,
	input: string?,
	timelineOf: TimelineOf,
	bufferTime: number?
): (State, string?)
	local next = expire(state, now, bufferTime or Config.Action.BufferTime)

	-- 終わった行動に続きがあれば、先行入力より先に始める
	local chained: string? = nil
	local finished = state.timeline
	if next.action == nil and state.action ~= nil and finished and finished.Next then
		local timeline = timelineOf(finished.Next)
		if timeline then
			chained = finished.Next
			next = start(finished.Next, timeline, now)
		end
	end

	if input ~= nil then
		local timeline = timelineOf(input)
		if timeline == nil then
			return next, chained
		end
		local interrupts = timeline.Interrupt == true and next.action ~= input
		if ActionState.isCancelable(next, now) or interrupts then
			return start(input, timeline, now), input
		end
		next = table.clone(next)
		next.buffered = input
		next.bufferedAt = now
		return next, chained
	end

	if chained then
		return next, chained
	end
	local buffered = next.buffered
	if buffered ~= nil and ActionState.isCancelable(next, now) then
		local timeline = timelineOf(buffered)
		if timeline == nil then
			next = table.clone(next)
			next.buffered = nil
			return next, nil
		end
		return start(buffered, timeline, now), buffered
	end
	return next, nil
end

-- 被弾などで今の行動と先行入力を捨て、action を始めた状態を返す
function ActionState.interrupt(action: string, now: number, timeline: Timeline): State
	return start(action, timeline, now)
end

-- 押している間だけ続く行動（ガード）を終える。今の行動が action なら待機に戻し、
-- 先行入力が action なら捨てる。ほかの行動と先行入力はそのまま
function ActionState.finish(state: State, action: string): State
	local next = state
	if state.action == action then
		next = table.clone(next)
		next.action = nil
		next.timeline = nil
	end
	if next.buffered == action then
		next = if next == state then table.clone(next) else next
		next.buffered = nil
	end
	return next
end

-- 攻撃の速さの倍率 speed で時間を割ったタイムライン。1 より小さいと遅くなる。前進量は変えない
function ActionState.scale(timeline: Timeline, speed: number): Timeline
	if speed == 1 then
		return timeline
	end
	local scaled = table.clone(timeline)
	scaled.Startup = timeline.Startup / speed
	scaled.Active = timeline.Active / speed
	scaled.Recovery = timeline.Recovery / speed
	scaled.CancelFrom = timeline.CancelFrom / speed
	local hits = timeline.Hits
	if hits then
		local scaledHits = {}
		for index, hit in hits do
			local copy = table.clone(hit)
			copy.Delay = if hit.Delay then hit.Delay / speed else nil
			copy.Interval = if hit.Interval then hit.Interval / speed else nil
			scaledHits[index] = copy
		end
		scaled.Hits = scaledHits
	end
	return scaled
end

export type ScheduledHit = {
	-- 行動の開始から判定が出るまでの秒数
	at: number,
	hit: Config.HitDef,
}

-- 判定を、行動の開始から出るまでの秒数と組にして、出る順に並べる。繰り返す判定は回数だけ並べる
function ActionState.hits(timeline: Timeline): { ScheduledHit }
	local list: { ScheduledHit } = {}
	for _, hit in timeline.Hits or {} do
		for index = 1, hit.Repeat or 1 do
			local at = timeline.Startup + (hit.Delay or 0) + (index - 1) * (hit.Interval or 0)
			table.insert(list, { at = at, hit = hit })
		end
	end
	table.sort(list, function(a, b)
		return a.at < b.at
	end)
	return list
end

return ActionState
