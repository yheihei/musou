--!strict
-- ゲームパッドの入力の記録（#148 の確認用）。本人のゲームパッドのどのボタンが、Roblox にどの KeyCode として届いたかと、
-- そのときに選んでいた画面の部品を、新しい順に覚える。画面の操作（はじめる・戻るなど）が受けた入力も note で残す。
-- 記録は LocalPlayer の Attribute に書き、テストプレイ中のコマンドバー（クライアント表示）で読む。
--
-- - GamepadLog: 新しい順の記録を改行でつないだ文。1件は「入室からの秒 KeyCode（入力の種類） 選んでいた部品 タイトル画面 戦闘の操作」
--   か「入室からの秒 note の文」。ゲームパッドのボタンと十字キーの KeyCode を記録する（Studio の模擬入力は Keyboard の種類で届く）
-- - GamepadType: Roblox がボタンの絵に使うゲームパッドの種類（ボタンの絵の名前から決める。Xbox・PlayStation・不明）
-- - 送り先はクライアントの中だけ（サーバーへは送らない）

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local InputLog = {}

-- 覚えておく件数
local MAX_ENTRIES = 20
local LOG_ATTRIBUTE = "GamepadLog"
local TYPE_ATTRIBUTE = "GamepadType"

local entries: { string } = {}
-- 記録に添える、タイトル画面を出しているかと戦闘の操作を受け付けているかを返す関数（start で受け取る）
local stateOf: (() -> (boolean, boolean))? = nil

local function publish()
	Players.LocalPlayer:SetAttribute(LOG_ATTRIBUTE, table.concat(entries, "\n"))
end

local function add(line: string)
	table.insert(entries, 1, `{string.format("%.1f", time())} {line}`)
	while #entries > MAX_ENTRIES do
		table.remove(entries)
	end
	publish()
end

-- 画面の操作が受けた入力などを残す
function InputLog.note(text: string)
	add(text)
end

-- Roblox がボタンの絵に使うゲームパッドの種類。A の絵の名前（XboxController・PlayStationController）で決める
local function gamepadType(): string
	if #UserInputService:GetConnectedGamepads() == 0 then
		return "なし"
	end
	local ok, image = pcall(function()
		return UserInputService:GetImageForKeyCode(Enum.KeyCode.ButtonA)
	end)
	local name = if ok then tostring(image) else ""
	if string.find(name, "PlayStation", 1, true) then
		return "PlayStation"
	elseif string.find(name, "Xbox", 1, true) then
		return "Xbox"
	end
	return `不明（{name}）`
end

local function refreshType()
	Players.LocalPlayer:SetAttribute(TYPE_ATTRIBUTE, gamepadType())
end

-- state は、タイトル画面を出しているかと戦闘の操作を受け付けているかを返す
function InputLog.start(state: () -> (boolean, boolean))
	stateOf = state
	UserInputService.InputBegan:Connect(function(input, processed)
		local name = input.KeyCode.Name
		if string.sub(name, 1, 6) ~= "Button" and string.sub(name, 1, 4) ~= "DPad" then
			return
		end
		local selected = GuiService.SelectedObject
		local titleOpen, combatActive = false, false
		local current = stateOf
		if current then
			titleOpen, combatActive = current()
		end
		add(
			`{name}（{input.UserInputType.Name}） 選択={if selected then selected.Name else "なし"} タイトル={if titleOpen
				then "表示"
				else "なし"} 戦闘の操作={if combatActive then "受付" else "停止"}{if processed
				then " 処理済み"
				else ""}`
		)
	end)
	UserInputService.GamepadConnected:Connect(refreshType)
	UserInputService.GamepadDisconnected:Connect(refreshType)
	refreshType()
	publish()
end

return InputLog
