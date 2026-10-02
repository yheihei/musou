--!strict
-- イベントシーンのスキップ。再生中に画面の右上へ「スキップ 1/2」と押すボタンを出し、押したら Remotes.SkipEventScene を送る。
-- 人数はサーバーの Remotes.SkipCount（スキップした人数、全体の人数）で書き換える。割り当ては ReplicatedStorage.Shared.InputMap の Skip。
--
-- - 再生の始めと終わりは EventSceneController の started・stopped で知る
-- - スキップは1回だけ送り、取り消せない。押した後は「スキップ済み」にする
-- - 表示はボタンにもなっていて、クリックやタッチでもスキップを送れる
-- - ボタン表記は入力の種類で切り替える

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InputMap = require(ReplicatedStorage.Shared.InputMap)
local Ui = require(script.Parent.Parent.Ui)
local EventSceneController = require(script.Parent.EventSceneController)

local SkipController = {}

-- スキップの操作の名前
local ACTION = "EventSceneSkip"
-- 画面の端からの余白と、ボタンの大きさ（ピクセル）
local MARGIN = 16
local WIDTH = 260
local HEIGHT = 44
-- 再生を始める前に届いた人数を、この秒数以内なら使う
local COUNT_FRESH_TIME = 1

local remote: RemoteEvent
local button: TextButton
local screen: ScreenGui
local playing = false
local skipped = false
local count = 0
local total: number? = nil
-- 再生していないときに届いた人数と、届いた時刻（os.clock）
local pending: { count: number, total: number, at: number }? = nil

local function refresh()
	local people = `{count}/{if total then tostring(total) else "-"}`
	if skipped then
		button.Text = `スキップ済み {people}`
		button.TextColor3 = Ui.Color.Disabled
	else
		button.Text = `スキップ {people}　{Ui.label(InputMap.Skip.labels)}`
		button.TextColor3 = Ui.Color.Text
	end
end

local function skip()
	if not playing or skipped then
		return
	end
	skipped = true
	remote:FireServer()
	refresh()
end

local function toEnums(): { Enum.KeyCode }
	local enums = {}
	for _, list in { InputMap.Skip.keyboard, InputMap.Skip.gamepad } do
		for _, input in list do
			local kind, name = InputMap.parse(input)
			if kind == "KeyCode" and name then
				local ok, value = pcall(function(): any
					return (Enum.KeyCode :: any)[name]
				end)
				if ok and value then
					table.insert(enums, value)
				end
			end
		end
	end
	return enums
end

local function onStarted()
	playing = true
	skipped = false
	count = 0
	total = nil
	local fresh = pending
	pending = nil
	if fresh and os.clock() - fresh.at <= COUNT_FRESH_TIME then
		count, total = fresh.count, fresh.total
	end
	refresh()
	screen.Enabled = true
	ContextActionService:BindActionAtPriority(ACTION, function(_, state)
		if state == Enum.UserInputState.Begin then
			skip()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value + 1, table.unpack(toEnums()))
end

local function onStopped()
	playing = false
	screen.Enabled = false
	ContextActionService:UnbindAction(ACTION)
end

function SkipController.start()
	button = Ui.button({
		Name = "Skip",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -MARGIN, 0, MARGIN),
		Size = UDim2.fromOffset(WIDTH, HEIGHT),
		TextSize = Ui.TextSize.Body,
	})
	screen = Ui.screenGui("SkipCount", Ui.Layer.SkipCount, { button })
	screen.IgnoreGuiInset = true
	screen.Enabled = false
	button.Activated:Connect(skip)

	remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("SkipEventScene") :: RemoteEvent
	local countRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("SkipCount") :: RemoteEvent
	countRemote.OnClientEvent:Connect(function(skippedCount: unknown, totalCount: unknown)
		if type(skippedCount) ~= "number" or type(totalCount) ~= "number" then
			return
		end
		if not playing then
			pending = { count = skippedCount, total = totalCount, at = os.clock() }
			return
		end
		count, total = skippedCount, totalCount
		refresh()
	end)
	EventSceneController.started:Connect(onStarted)
	EventSceneController.stopped:Connect(onStopped)
	Ui.onInputKindChanged(function()
		if playing then
			refresh()
		end
	end)
end

return SkipController
