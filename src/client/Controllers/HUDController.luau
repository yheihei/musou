--!strict
-- 撃破数と奥義ゲージの表示。値は Player の Attribute から読む。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Ui = require(script.Parent.Parent.Ui)

local HUDController = {}

local player = Players.LocalPlayer

-- 操作の案内。ボタン表記は入力の種類で切り替える（割り当ては InputController と合わせる）
local ATTACK_LABELS: Ui.Labels = { Keyboard = "左クリック", Gamepad = "R2" }
local CHARGE_KOGEKI_LABELS: Ui.Labels = { Keyboard = "E", Gamepad = "X" }
local OUGI_LABELS: Ui.Labels = { Keyboard = "Q", Gamepad = "Y" }

local function hintText(full: boolean): string
	local ougi = Ui.label(OUGI_LABELS)
	if full then
		return `奥義ゲージ MAX！ {ougi} で奥義`
	end
	local attack = Ui.label(ATTACK_LABELS)
	local chargeKogeki = Ui.label(CHARGE_KOGEKI_LABELS)
	return `{attack}: 攻撃   {chargeKogeki}: チャージ攻撃   {ougi}: 奥義`
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
	})

	local hint = Ui.create("TextLabel", {
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -56),
		Size = UDim2.fromOffset(420, 20),
		BackgroundTransparency = 1,
		Font = Ui.Font.Bold,
		TextSize = Ui.TextSize.Small,
		TextColor3 = Ui.Color.Text,
		TextStrokeTransparency = 0.5,
		Text = hintText(false),
	})

	Ui.screenGui("HUD", Ui.Layer.Hud, { gekihasuLabel, gauge, hint })

	return gekihasuLabel :: TextLabel, gaugeFill :: Frame, hint :: TextLabel
end

function HUDController.start()
	local gekihasuLabel, gaugeFill, hint = buildGui()

	local function refreshGekihasu()
		gekihasuLabel.Text = `撃破数 {player:GetAttribute("Gekihasu") or 0}`
	end

	local gaugeFull = false
	local function refreshHint()
		hint.Text = hintText(gaugeFull)
	end

	local function refreshOugiGauge()
		local ratio = (player:GetAttribute("OugiGauge") :: number? or 0) / Config.Ougi.MaxGauge
		TweenService:Create(gaugeFill, TweenInfo.new(0.15), { Size = UDim2.fromScale(ratio, 1) }):Play()
		gaugeFull = ratio >= 1
		gaugeFill.BackgroundColor3 = if gaugeFull then Ui.Color.GaugeFull else Ui.Color.Gauge
		refreshHint()
	end

	player:GetAttributeChangedSignal("Gekihasu"):Connect(refreshGekihasu)
	player:GetAttributeChangedSignal("OugiGauge"):Connect(refreshOugiGauge)
	Ui.onInputKindChanged(refreshHint)
	refreshGekihasu()
	refreshOugiGauge()
end

return HUDController
