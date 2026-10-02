--!strict
-- 計測の画面。方式（案A・案B の Attribute・案B の Unreliable）・体数・自動の薙ぎ払い・カメラの固定を切り替えるボタンと、
-- 計測の値（FPS、受信量、送信量、サーバーの Heartbeat、Ping、メモリ、薙ぎ払いで当てた数）を左上に出す。
-- スマホでも押せる大きさにする。
-- 切り替えは ReplicatedStorage.ProtoRemotes.SetMode で1項目ずつ送り、今の状態は workspace の Attribute から読む。
-- カメラの固定はこの画面だけで切り替える。プレイヤーの斜め上の決まった位置から見下ろし、
-- 下忍がカメラに当たって寄る動きを無くして、方式どうしの描画の量をそろえる。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")

local Config = require(ReplicatedStorage.Shared.Config)

local Hud = {}

local MODES = {
	{ id = "A", label = "案A Humanoid" },
	{ id = "BAttribute", label = "案B Attribute" },
	{ id = "BUnreliable", label = "案B Unreliable" },
}

local BUTTON_HEIGHT = 44
local SELECTED = Color3.fromRGB(255, 200, 60)
local NORMAL = Color3.fromRGB(45, 45, 45)
-- 固定したカメラの、プレイヤーから見た位置（スタッド）
local FIXED_CAMERA_OFFSET = Vector3.new(0, 45, 45)

local function button(text: string, width: number, parent: Instance): TextButton
	local created = Instance.new("TextButton")
	created.Size = UDim2.fromOffset(width, BUTTON_HEIGHT)
	created.BackgroundColor3 = NORMAL
	created.TextColor3 = Color3.new(1, 1, 1)
	created.Font = Enum.Font.GothamBold
	created.TextSize = 16
	created.Text = text
	created.AutoButtonColor = true
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = created
	created.Parent = parent
	return created
end

local function row(order: number, parent: Instance): Frame
	local frame = Instance.new("Frame")
	frame.LayoutOrder = order
	frame.Size = UDim2.new(1, 0, 0, BUTTON_HEIGHT)
	frame.BackgroundTransparency = 1
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 6)
	layout.Parent = frame
	frame.Parent = parent
	return frame
end

-- 計測の値を読む。読めない値は nil
local function read(getter: () -> number): number?
	local ok, value = pcall(getter)
	return if ok then value else nil
end

local function format(value: number?, digits: number): string
	if value == nil then
		return "-"
	end
	return string.format(`%.{digits}f`, value)
end

local function attributeText(name: string): string
	local value = workspace:GetAttribute(name)
	return if type(value) == "number" then tostring(value) else "-"
end

function Hud.start()
	local remote = ReplicatedStorage:WaitForChild("ProtoRemotes"):WaitForChild("SetMode") :: RemoteEvent
	local gui = Instance.new("ScreenGui")
	gui.Name = "GeninProtoHud"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 100

	local panel = Instance.new("Frame")
	panel.Position = UDim2.fromOffset(12, 12)
	panel.Size = UDim2.fromOffset(440, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	panel.BackgroundTransparency = 0.25
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = panel
	panel.Parent = gui

	local modeRow = row(1, panel)
	local countRow = row(2, panel)
	local optionRow = row(3, panel)
	local modeButtons: { [string]: TextButton } = {}
	for _, item in MODES do
		modeButtons[item.id] = button(item.label, 138, modeRow)
	end
	local countButtons: { [number]: TextButton } = {}
	for _, value in Config.GeninProto.Counts do
		countButtons[value] = button(`{value} 体`, 100, countRow)
	end
	local sweepButton = button("自動の薙ぎ払い", 210, optionRow)
	local cameraButton = button("カメラ固定", 210, optionRow)

	local statsLabel = Instance.new("TextLabel")
	statsLabel.LayoutOrder = 4
	statsLabel.Size = UDim2.fromScale(1, 0)
	statsLabel.AutomaticSize = Enum.AutomaticSize.Y
	statsLabel.BackgroundTransparency = 1
	statsLabel.TextColor3 = Color3.new(1, 1, 1)
	statsLabel.Font = Enum.Font.Code
	statsLabel.TextSize = 16
	statsLabel.TextXAlignment = Enum.TextXAlignment.Left
	statsLabel.TextYAlignment = Enum.TextYAlignment.Top
	statsLabel.Text = ""
	statsLabel.Parent = panel

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local fixedCamera = false

	local function current(): (string, number, boolean)
		local mode = workspace:GetAttribute("ProtoMode")
		local count = workspace:GetAttribute("ProtoCount")
		local autoSweep = workspace:GetAttribute("ProtoAutoSweep")
		return if type(mode) == "string" then mode else "A",
			if type(count) == "number" then count else Config.GeninProto.DefaultCount,
			autoSweep ~= false
	end

	local function refreshButtons()
		local mode, count, autoSweep = current()
		for id, target in modeButtons do
			target.BackgroundColor3 = if id == mode then SELECTED else NORMAL
		end
		for value, target in countButtons do
			target.BackgroundColor3 = if value == count then SELECTED else NORMAL
		end
		sweepButton.Text = `自動の薙ぎ払い {if autoSweep then "ON" else "OFF"}`
		sweepButton.BackgroundColor3 = if autoSweep then SELECTED else NORMAL
		cameraButton.Text = `カメラ固定 {if fixedCamera then "ON" else "OFF"}`
		cameraButton.BackgroundColor3 = if fixedCamera then SELECTED else NORMAL
	end

	-- 押したボタンの項目だけを送る
	for id, target in modeButtons do
		target.Activated:Connect(function()
			remote:FireServer("Mode", id)
		end)
	end
	for value, target in countButtons do
		target.Activated:Connect(function()
			remote:FireServer("Count", value)
		end)
	end
	sweepButton.Activated:Connect(function()
		local _, _, autoSweep = current()
		remote:FireServer("AutoSweep", not autoSweep)
	end)
	cameraButton.Activated:Connect(function()
		fixedCamera = not fixedCamera
		local camera = workspace.CurrentCamera
		if camera then
			camera.CameraType = if fixedCamera then Enum.CameraType.Scriptable else Enum.CameraType.Custom
		end
		refreshButtons()
	end)
	for _, name in { "ProtoMode", "ProtoCount", "ProtoAutoSweep" } do
		workspace:GetAttributeChangedSignal(name):Connect(refreshButtons)
	end
	refreshButtons()

	-- 描画の回数を1秒ごとに数え、計測の値を出す。カメラを固定しているときは、毎回プレイヤーの斜め上へ置く
	local frames = 0
	local measuredAt = os.clock()
	RunService.RenderStepped:Connect(function()
		if fixedCamera then
			local camera = workspace.CurrentCamera
			local character = Players.LocalPlayer.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if camera and root then
				camera.CFrame = CFrame.lookAt(root.Position + FIXED_CAMERA_OFFSET, root.Position)
			end
		end
		frames += 1
		local now = os.clock()
		if now - measuredAt < 1 then
			return
		end
		local fps = frames / (now - measuredAt)
		frames = 0
		measuredAt = now
		local mode, count = current()
		local receive = read(function()
			return Stats.DataReceiveKbps
		end)
		local send = read(function()
			return Stats.DataSendKbps
		end)
		local memory = read(function()
			return Stats:GetTotalMemoryUsageMb()
		end)
		local ping = read(function()
			return Players.LocalPlayer:GetNetworkPing() * 1000
		end)
		statsLabel.Text = table.concat({
			`方式 {mode}  体数 {count}`,
			`FPS {format(fps, 0)}`,
			`受信 {format(receive, 1)} KB/s  送信 {format(send, 1)} KB/s`,
			`サーバーの Heartbeat {attributeText("ServerHeartbeat")}`,
			`Ping {format(ping, 0)} ms  メモリ {format(memory, 0)} MB`,
			`薙ぎ払いで当てた数 {attributeText("ProtoSweepHits")}`,
		}, "\n")
	end)
end

return Hud
