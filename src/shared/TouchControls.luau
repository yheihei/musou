--!strict
-- スマホ横画面の戦闘の操作ボタン（タッチの操作）を出すかの判断。Roblox の API は使わない。
-- 表示はクライアントの TouchControlsController、配置の計算は TouchLayout.luau にある。
--
-- - 出すのは、タッチで遊んでいる人のうち、戦闘のフェーズの出撃メンバーだけ（画面上部の戦況と同じ条件。BattleStatus.isVisible）
-- - タッチで遊んでいるかは、UserInputService.PreferredInput が Touch か（使えなければ最後の入力の種類が Touch か）で決める。
--   ゲームパッドやキーボードとマウスに切り替えたら出さない
-- - Studio のテストプレイでは、Auto ならタッチとみなさない。マウスのクリックがタッチとして届き、キーボードも無い端末と
--   報告する環境がある（開発者の Studio は TouchEnabled が true、KeyboardEnabled が false）。PC の開発者に出し続けないため。
--   デバイスエミュレーターや Studio で確かめるときは、窓口の SetTouchControls で On にする
-- - Player の Attribute の TouchControls（窓口の SetTouchControls が書く）で、On なら端末を問わずタッチとみなし、
--   Off なら出さない。Auto か無ければ端末で決める

local BattleStatus = require("./BattleStatus")
local RemoteSchema = require("./RemoteSchema")

-- 出すかの決め方。On は端末を問わずタッチとみなす、Off は出さない、Auto は端末の入力の種類で決める
export type Mode = "On" | "Off" | "Auto"

-- 入力の種類（クライアントの Ui.inputKind と同じ）
export type InputKind = "Keyboard" | "Gamepad" | "Touch"

-- 端末の入力の様子
export type Device = {
	-- Studio のテストプレイか
	studio: boolean,
	-- UserInputService の TouchEnabled と KeyboardEnabled
	touchEnabled: boolean,
	keyboardEnabled: boolean,
	-- UserInputService.PreferredInput の名前（Touch・KeyboardAndMouse・Gamepad）。使えなければ nil
	preferredInput: string?,
	-- 最後に使った入力の種類
	lastInputKind: InputKind,
}

local TouchControls = {}

-- 出すかの決め方を置く Player の Attribute。値は Mode の文字列
TouchControls.ATTRIBUTE = "TouchControls"

TouchControls.modes = { "On", "Off", "Auto" } :: { Mode }

-- Attribute の値を決め方にする。On と Off 以外（無いときを含む）は Auto
function TouchControls.modeOf(value: unknown): Mode
	if value == "On" or value == "Off" then
		return value :: Mode
	end
	return "Auto"
end

-- 窓口に渡された文字列（on・off・auto。大文字と小文字は問わない）を決め方にする。どれでもなければ nil
function TouchControls.parseMode(text: unknown): Mode?
	if type(text) ~= "string" then
		return nil
	end
	local lower = string.lower(text)
	for _, mode in TouchControls.modes do
		if string.lower(mode) == lower then
			return mode
		end
	end
	return nil
end

-- 端末の入力の様子から、タッチで遊んでいるとみなすか
function TouchControls.prefersTouch(device: Device): boolean
	if device.studio then
		return false
	end
	if device.preferredInput ~= nil then
		return device.preferredInput == "Touch"
	end
	return device.lastInputKind == "Touch"
end

-- タッチの操作を使うか（戦闘のフェーズかは問わない）
function TouchControls.isActive(mode: Mode, device: Device): boolean
	if mode == "On" then
		return true
	elseif mode == "Off" then
		return false
	end
	return TouchControls.prefersTouch(device)
end

-- タッチの操作ボタンを出すか。phase・waiting・playing は BattleStatus.isVisible と同じ
function TouchControls.isShown(
	mode: Mode,
	device: Device,
	phase: RemoteSchema.Phase?,
	waiting: boolean,
	playing: boolean
): boolean
	return TouchControls.isActive(mode, device) and BattleStatus.isVisible(phase, waiting, playing)
end

return TouchControls
