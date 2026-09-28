--!strict
-- 撃破数と奥義ゲージの表示。値は Player の Attribute から読む。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)

local HUDController = {}

local player = Players.LocalPlayer

local function create<T>(className: string, props: { [string]: any }, children: { Instance }?): T
	local instance = Instance.new(className :: any)
	for key, value in props do
		(instance :: any)[key] = value
	end
	for _, child in children or {} do
		child.Parent = instance
	end
	return instance :: any
end

local function buildGui()
	local gekihasuLabel = create("TextLabel", {
		Name = "Gekihasu",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -24, 0, 24),
		Size = UDim2.fromOffset(260, 64),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		TextSize = 44,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Color3.new(1, 1, 1),
		TextStrokeTransparency = 0.3,
		Text = "撃破数 0",
	})

	local gaugeFill = create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Color3.fromRGB(255, 140, 40),
		BorderSizePixel = 0,
	}, { create("UICorner", { CornerRadius = UDim.new(0, 6) }) })

	local gauge = create("Frame", {
		Name = "OugiGauge",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -32),
		Size = UDim2.fromOffset(420, 18),
		BackgroundColor3 = Color3.fromRGB(30, 30, 30),
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
	}, {
		create("UICorner", { CornerRadius = UDim.new(0, 6) }),
		create("UIStroke", { Color = Color3.fromRGB(255, 220, 150), Thickness = 2 }),
		gaugeFill,
	})

	local hint = create("TextLabel", {
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -56),
		Size = UDim2.fromOffset(420, 20),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		TextColor3 = Color3.new(1, 1, 1),
		TextStrokeTransparency = 0.5,
		Text = "左クリック: 攻撃   E: チャージ攻撃   Q: 奥義",
	})

	create("ScreenGui", {
		Name = "HUD",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		Parent = player:WaitForChild("PlayerGui"),
	}, { gekihasuLabel, gauge, hint })

	return gekihasuLabel :: TextLabel, gaugeFill :: Frame, hint :: TextLabel
end

function HUDController.start()
	local gekihasuLabel, gaugeFill, hint = buildGui()

	local function refreshGekihasu()
		gekihasuLabel.Text = `撃破数 {player:GetAttribute("Gekihasu") or 0}`
	end

	local function refreshOugiGauge()
		local ratio = (player:GetAttribute("OugiGauge") :: number? or 0) / Config.Ougi.MaxGauge
		TweenService:Create(gaugeFill, TweenInfo.new(0.15), { Size = UDim2.fromScale(ratio, 1) }):Play()
		local full = ratio >= 1
		gaugeFill.BackgroundColor3 = if full then Color3.fromRGB(255, 60, 30) else Color3.fromRGB(255, 140, 40)
		hint.Text = if full
			then "奥義ゲージ MAX！ Q で奥義"
			else "左クリック: 攻撃   E: チャージ攻撃   Q: 奥義"
	end

	player:GetAttributeChangedSignal("Gekihasu"):Connect(refreshGekihasu)
	player:GetAttributeChangedSignal("OugiGauge"):Connect(refreshOugiGauge)
	refreshGekihasu()
	refreshOugiGauge()
end

return HUDController
