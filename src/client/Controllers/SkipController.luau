--!strict
-- イベントシーンのスキップ。再生中に画面の右上へ「スキップ 1/2」と押すボタンを出し、押したら Remotes.SkipEventScene を送る。
-- 人数はサーバーの Remotes.SkipCount（スキップした人数、全体の人数）で書き換える。割り当ては ReplicatedStorage.Shared.InputMap の Skip。
--
-- - 再生の始めと終わりは EventSceneController の started・stopped で知る
-- - スキップは1回だけ送り、取り消せない。押した後は「スキップ済み」にする
-- - 表示はボタンにもなっていて、クリックやタッチでもスキップを送れる
-- - ボタン表記は入力の種類で切り替える
-- - タッチで遊んでいる人（Ui.isTouchInput。戦闘の操作ボタンと同じ判断で、窓口の SetTouchControls で強制できる）には、
--   指で押せる大きさのボタン（Config.luau の SmallScreen 節の SkipWidth x SkipHeight）にして、押すキーを添えずに
--   安全な範囲（トップバーとノッチの内側）の右上に置く（ReplicatedStorage.Shared.SmallScreen の skipOf）。押すと同じ要求を送る

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InputMap = require(ReplicatedStorage.Shared.InputMap)
local SmallScreen = require(ReplicatedStorage.Shared.SmallScreen)
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
	elseif Ui.isTouchInput() then
		-- タッチでは押すキーを添えない（画面のボタンを押す）
		button.Text = `スキップ {people}`
		button.TextColor3 = Ui.Color.Text
	else
		button.Text = `スキップ {people}　{Ui.label(InputMap.Skip.labels)}`
		button.TextColor3 = Ui.Color.Text
	end
end

-- ボタンの大きさと位置。タッチでは指で押せる大きさにして安全な範囲の右上に、そうでなければ画面の右上の角に置く
local function place()
	if Ui.isTouchInput() then
		local size = Ui.safeAreaSize()
		local rect = SmallScreen.skipOf(size.X, size.Y)
		screen.IgnoreGuiInset = false
		button.AnchorPoint = Vector2.zero
		button.Position = UDim2.fromOffset(rect.x, rect.y)
		button.Size = UDim2.fromOffset(rect.width, rect.height)
		button.TextSize = Ui.TextSize.Large
	else
		screen.IgnoreGuiInset = true
		button.AnchorPoint = Vector2.new(1, 0)
		button.Position = UDim2.new(1, -MARGIN, 0, MARGIN)
		button.Size = UDim2.fromOffset(WIDTH, HEIGHT)
		button.TextSize = Ui.TextSize.Body
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
	-- 位置と大きさは place が入力に合わせて決める
	button = Ui.button({
		Name = "Skip",
	})
	screen = Ui.screenGui("SkipCount", Ui.Layer.SkipCount, { button })
	screen.Enabled = false
	place()
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
	-- タッチで遊んでいるかと画面の大きさが変わったら置き直す
	Ui.onTouchInputChanged(function()
		place()
		refresh()
	end)
	Ui.onSafeAreaChanged(place)
end

return SkipController
