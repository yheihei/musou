--!strict
-- 画面上部の戦況の表示（軍全体の士気・残り時間・兵力）で使う判断と文。Roblox の API は使わない。
-- 表示はクライアントの BattleStatusController、残り時間の強調のしきい値は Config.luau の BattleStatus 節にある。
--
-- - 出すのは戦闘のフェーズの出撃メンバー（待機中でない人）だけ。イベントシーンの再生中は出さない
-- - 残り時間は「分:秒」で書く。書き方はリザルトの経過時間（ResultMessage.formatElapsed）に合わせる
-- - 残り時間の秒の端数は切り上げる。0:00 になるのは時間切れのときだけ
-- - 残り時間は TimeWarning 秒以下で注意、TimeDanger 秒以下で危険として強調する。画面に出す秒で比べる
-- - 兵力は「兵力 7」と書き、0 なら危険として強調する（次に誰かが倒れると負ける）
-- - 士気のゲージの長さは、Config.luau の Shiki 節の Min から Max までを 0 から 1 に直した割合

local Config = require("./Config")
local RemoteSchema = require("./RemoteSchema")

-- 強調の段階。None は強調しない、Warning は注意、Danger は危険
export type Emphasis = "None" | "Warning" | "Danger"

-- 士気の範囲。Config.luau の Shiki 節をそのまま渡せる
export type ShikiRange = {
	Min: number,
	Max: number,
}

local BattleStatus = {}

-- 残り時間が無いとき（戦闘のフェーズの外）に出す文
BattleStatus.NO_REMAINING = "--:--"

-- 画面に出す残り時間の秒数。端数は切り上げる
local function shownSeconds(seconds: number): number
	-- 数でない値（NaN）は比べると偽になるので、負の値と同じく 0 秒にする
	return if seconds > 0 then math.ceil(seconds) else 0
end

-- 画面に出す兵力。端数は切り捨てる
local function shownHeiryoku(heiryoku: number): number
	-- 数でない値（NaN）は比べると偽になるので、負の値と同じく 0 にする
	return if heiryoku > 0 then math.floor(heiryoku) else 0
end

-- 戦況を出すか。phase は PartyState のフェーズ（届く前は nil）。
-- waiting は本人が出撃メンバーでないか（待機中の人と、パーティーにいない人）、playing はイベントシーンを再生しているか
function BattleStatus.isVisible(phase: RemoteSchema.Phase?, waiting: boolean, playing: boolean): boolean
	return phase == "Battle" and not waiting and not playing
end

-- 残り時間（秒）を「分:秒」で書く。分は桁をそろえず、60 分を超えても分で数える。残り時間が無ければ NO_REMAINING
function BattleStatus.formatRemaining(seconds: number?): string
	if seconds == nil then
		return BattleStatus.NO_REMAINING
	end
	local total = shownSeconds(seconds)
	return string.format("%d:%02d", total // 60, total % 60)
end

-- 残り時間の強調。残り時間が無ければ強調しない
function BattleStatus.remainingEmphasis(seconds: number?, params: Config.BattleStatusSection?): Emphasis
	if seconds == nil then
		return "None"
	end
	local p = params or Config.BattleStatus
	local shown = shownSeconds(seconds)
	if shown <= p.TimeDanger then
		return "Danger"
	elseif shown <= p.TimeWarning then
		return "Warning"
	end
	return "None"
end

-- 兵力の文。兵力が無ければ（出撃していなければ）数の代わりに「-」を出す
function BattleStatus.heiryokuText(heiryoku: number?): string
	if heiryoku == nil then
		return "兵力 -"
	end
	return `兵力 {shownHeiryoku(heiryoku)}`
end

-- 兵力の強調。0 なら危険。兵力が無ければ強調しない
function BattleStatus.heiryokuEmphasis(heiryoku: number?): Emphasis
	if heiryoku == nil then
		return "None"
	end
	return if shownHeiryoku(heiryoku) > 0 then "None" else "Danger"
end

-- 士気のゲージの長さの割合（0 から 1）。range を省くと Config.luau の Shiki 節を使う。値が無ければ 0
function BattleStatus.shikiRatio(shiki: number?, range: ShikiRange?): number
	if shiki == nil then
		return 0
	end
	local r = range or Config.Shiki
	local ratio = (shiki - r.Min) / (r.Max - r.Min)
	-- 数でない値（NaN）は比べると偽になるので 0 にする
	return if ratio > 0 then math.min(ratio, 1) else 0
end

return BattleStatus
