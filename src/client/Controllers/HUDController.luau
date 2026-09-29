--!strict
-- 撃破数と奥義ゲージ（本数と次の1本までの量）の表示。値は Player の Attribute から読む。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local InputMap = require(ReplicatedStorage.Shared.InputMap)
local Ui = require(script.Parent.Parent.Ui)

local HUDController = {}

local player = Players.LocalPlayer

-- 操作の案内。ボタン表記は入力の対応表から引き、入力の種類で切り替える
local function hintText(stock: number): string
	local ougi = Ui.label(InputMap.Ougi.labels)
	if stock >= 1 then
		return `奥義ゲージ {stock} 本！ {ougi} で奥義`
	end
	local attack = Ui.label(InputMap.Attack.labels)
	local chargeKogeki = Ui.label(InputMap.ChargeKogeki.labels)
	local guard = Ui.label(InputMap.Guard.labels)
	return `{attack}: 攻撃   {chargeKogeki}: チャージ攻撃   {guard}: ガード   {ougi}: 奥義`
end

local function buildGui()
	local gekihasuLabel = Ui.create("TextLabel", {
		Name = "Gekihasu",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -24, 0, 24),
		Size = UDim2.fromOffset(260, 64),
		BackgroundTransparency = 1,
		Font = Ui.Font.Heavy,
		TextSize = Ui.TextSize.Huge,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Ui.Color.Text,
		TextStrokeTransparency = 0.3,
		Text = "撃破数 0",
	})

	local gaugeFill = Ui.create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Ui.Color.Gauge,
		BorderSizePixel = 0,
	}, { Ui.create("UICorner", { CornerRadius = UDim.new(0, 6) }) })

	-- 溜まった本数。ゲージの右に出す
	local stockLabel = Ui.create("TextLabel", {
		Name = "Stock",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(1, 10, 0.5, 0),
		Size = UDim2.fromOffset(80, 24),
		BackgroundTransparency = 1,
		Font = Ui.Font.Heavy,
		TextSize = Ui.TextSize.Large,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Ui.Color.Text,
		TextStrokeTransparency = 0.3,
		Text = "×0",
	})

	local gauge = Ui.create("Frame", {
		Name = "OugiGauge",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -32),
		Size = UDim2.fromOffset(420, 18),
		BackgroundColor3 = Ui.Color.Panel,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
	}, {
		Ui.create("UICorner", { CornerRadius = UDim.new(0, 6) }),
		Ui.create("UIStroke", { Color = Ui.Color.Accent, Thickness = 2 }),
		gaugeFill,
		stockLabel,
	})

	local hint = Ui.create("TextLabel", {
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -56),
		Size = UDim2.fromOffset(520, 20),
		BackgroundTransparency = 1,
		Font = Ui.Font.Bold,
		TextSize = Ui.TextSize.Small,
		TextColor3 = Ui.Color.Text,
		TextStrokeTransparency = 0.5,
		Text = hintText(0),
	})

	Ui.screenGui("HUD", Ui.Layer.Hud, { gekihasuLabel, gauge, hint })

	return gekihasuLabel :: TextLabel, gaugeFill :: Frame, stockLabel :: TextLabel, hint :: TextLabel
end

function HUDController.start()
	local gekihasuLabel, gaugeFill, stockLabel, hint = buildGui()

	local function refreshGekihasu()
		gekihasuLabel.Text = `撃破数 {player:GetAttribute("Gekihasu") or 0}`
	end

	local stock = 0
	local function refreshHint()
		hint.Text = hintText(stock)
	end

	-- ゲージは次の1本までの量を出す。本数が上限なら満タンで出す
	local function refreshOugiGauge()
		stock = player:GetAttribute("OugiStock") :: number? or 0
		local amount = player:GetAttribute("OugiGauge") :: number? or 0
		local full = stock >= Config.Ougi.MaxStock
		local ratio = if full then 1 else math.clamp(amount / Config.Ougi.PerStock, 0, 1)
		TweenService:Create(gaugeFill, TweenInfo.new(0.15), { Size = UDim2.fromScale(ratio, 1) }):Play()
		gaugeFill.BackgroundColor3 = if full then Ui.Color.GaugeFull else Ui.Color.Gauge
		stockLabel.Text = `×{stock}`
		stockLabel.TextColor3 = if stock >= 1 then Ui.Color.GaugeFull else Ui.Color.Text
		refreshHint()
	end

	player:GetAttributeChangedSignal("Gekihasu"):Connect(refreshGekihasu)
	player:GetAttributeChangedSignal("OugiStock"):Connect(refreshOugiGauge)
	player:GetAttributeChangedSignal("OugiGauge"):Connect(refreshOugiGauge)
	Ui.onInputKindChanged(refreshHint)
	refreshGekihasu()
	refreshOugiGauge()
end

return HUDController
