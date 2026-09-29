--!strict
-- 通常攻撃のコンボ。ここまでに続けて出した通常攻撃の段数を求める。
-- 次の通常攻撃は（段数 + 1）段目、チャージ攻撃は C（段数 + 1）になる。
-- 途切れる時間は Config.luau の Combo 節にある。時刻は引数で受け取り、Roblox の API は使わない。
--
-- - 前の段のキャンセル受付が始まってから ComboResetTime 秒を超えると、コンボは途切れる
-- - 最後の段の後と、途切れた後は段数 0（次は1段目、チャージ攻撃は C1）

local Config = require("./Config")

export type State = {
	-- 最後に出した通常攻撃の段。0 はまだ出していないか、ほかの行動で途切れた
	step: number,
	-- 最後に出した段のキャンセル受付が始まる時刻
	cancelableAt: number,
}

local Combo = {}

function Combo.new(): State
	return { step = 0, cancelableAt = -math.huge }
end

-- 時刻 now に続けて出したことになっている通常攻撃の段数。stepCount は通常攻撃の段の数
function Combo.count(state: State, now: number, stepCount: number, resetTime: number?): number
	if state.step <= 0 or state.step >= stepCount then
		return 0
	end
	if now - state.cancelableAt > (resetTime or Config.Combo.ComboResetTime) then
		return 0
	end
	return state.step
end

-- 時刻 now に出すチャージ攻撃の番号（C1〜C6 の数字）。0〜5段の後は C1〜C6、6段目の後と途切れた後は C1
function Combo.chargeIndex(state: State, now: number, stepCount: number, resetTime: number?): number
	return Combo.count(state, now, stepCount, resetTime) + 1
end

-- 通常攻撃の step 段目を時刻 startedAt に始め、startedAt + cancelFrom から次を受け付けるときの状態
function Combo.advance(step: number, startedAt: number, cancelFrom: number): State
	return { step = step, cancelableAt = startedAt + cancelFrom }
end

return Combo
