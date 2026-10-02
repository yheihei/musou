--!strict
-- 画面下部の HUD。自分の体力、奥義ゲージ（次の1本までの量とストックの本数）、撃破数、持ち込んだ秘計の残り、
-- 操作の案内を出す。体力は Humanoid から、奥義ゲージと撃破数は Player の Attribute（OugiGauge・OugiStock・Gekihasu）から、
-- 秘計は Player の Attribute（HikeiMochikomi・HikeiUsed。ReplicatedStorage.Shared.Hikei の decodeList で読む）から読む。
-- Roblox 標準の体力表示は消す。
--
-- - 左下に体力のゲージと奥義ゲージ、奥義ゲージの右にストックの本数（上限の数だけ枠を並べる）
-- - 右下に撃破数。その上に持ち込んだ秘計の枚を、枚の順に名前と切るボタンで並べ、使用済みの枚は暗くする。
--   持ち込みが無いときは出さない
-- - 体力のゲージの上に操作の案内。ボタン表記は入力の対応表から引き、入力の種類で切り替える（秘計の枚のボタンも）

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Hikei = require(ReplicatedStorage.Shared.Hikei)
local InputMap = require(ReplicatedStorage.Shared.InputMap)
local Ui = require(script.Parent.Parent.Ui)

local HUDController = {}

local player = Players.LocalPlayer

-- 画面の端からの余白と、左下の枠の大きさ（ピクセル）
local MARGIN = 24
local PANEL_WIDTH = 460
local PANEL_HEIGHT = 84
local BAR_WIDTH = 300
-- 体力の割合がこれ以下なら体力のゲージを赤くする
local LOW_HEALTH = 0.3
-- ストックの枠の大きさと間隔
local PIP_SIZE = 18
local PIP_GAP = 6
-- 撃破数の枠の高さと、秘計の枚の大きさと間隔
local GEKIHASU_HEIGHT = 72
local HIKEI_WIDTH = 112
local HIKEI_HEIGHT = 58
local HIKEI_GAP = 6

local TWEEN = TweenInfo.new(0.15)

-- 操作の案内。ボタン表の順に「ボタン 操作」を並べる
local function hintText(): string
	local parts = {}
	for _, hint in InputMap.hints() do
		table.insert(parts, `{Ui.label(hint.labels)} {hint.name}`)
	end
	return table.concat(parts, "   ")
end

local function label(props: { [string]: any }): TextLabel
	local base: { [string]: any } = {
		BackgroundTransparency = 1,
		Font = Ui.Font.Bold,
		TextSize = Ui.TextSize.Body,
		TextColor3 = Ui.Color.Text,
		TextStrokeTransparency = 0.4,
		TextXAlignment = Enum.TextXAlignment.Left,
	}
	for key, value in props do
		base[key] = value
	end
	return Ui.create("TextLabel", base)
end

-- 横長のゲージ。中身（Fill）の幅を割合で変える
local function bar(name: string, y: number, height: number, color: Color3): (Frame, Frame)
	local fill = Ui.create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
	}, { Ui.create("UICorner", { CornerRadius = UDim.new(0, 5) }) })
	local frame = Ui.create("Frame", {
		Name = name,
		Position = UDim2.fromOffset(64, y),
		Size = UDim2.fromOffset(BAR_WIDTH, height),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
	}, {
		Ui.create("UICorner", { CornerRadius = UDim.new(0, 5) }),
		Ui.create("UIStroke", { Color = Ui.Color.Accent, Thickness = 1 }),
		fill,
	})
	return frame :: Frame, fill :: Frame
end

-- 秘計の枚1つ
type HikeiSlot = {
	frame: Frame,
	-- 切るボタンの表記
	key: TextLabel,
	name: TextLabel,
	-- 使用済みの印
	used: TextLabel,
}

type Gui = {
	healthFill: Frame,
	healthText: TextLabel,
	gaugeFill: Frame,
	pips: { Frame },
	gekihasu: TextLabel,
	hint: TextLabel,
	hikeiRow: Frame,
	hikeiSlots: { HikeiSlot },
}

-- 持ち込んだ秘計の枚を並べる。枚は秘計のボタンの数だけ作り、持ち込みの無い枚は隠す
local function buildHikeiRow(): (Frame, { HikeiSlot })
	local slots: { HikeiSlot } = {}
	local children: { Instance } = {
		Ui.create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, HIKEI_GAP),
		}),
	}
	for slot = 1, #InputMap.Hikei do
		local key = label({
			Name = "Key",
			Position = UDim2.fromOffset(8, 4),
			Size = UDim2.new(1, -16, 0, 18),
			TextSize = Ui.TextSize.Small,
			TextColor3 = Ui.Color.Accent,
		})
		local name = label({
			Name = "HikeiName",
			Position = UDim2.fromOffset(8, 22),
			Size = UDim2.new(1, -16, 0, 30),
			Font = Ui.Font.Heavy,
			TextSize = Ui.TextSize.Large,
		})
		local used = label({
			Name = "Used",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0, 4),
			Size = UDim2.fromOffset(60, 18),
			TextSize = Ui.TextSize.Small,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = Ui.Color.Disabled,
			Text = "使用済み",
			Visible = false,
		})
		local frame = Ui.create("Frame", {
			Name = `Hikei{slot}`,
			LayoutOrder = slot,
			Size = UDim2.fromOffset(HIKEI_WIDTH, HIKEI_HEIGHT),
			BackgroundColor3 = Ui.Color.Panel,
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			Visible = false,
		}, {
			Ui.create("UICorner", { CornerRadius = UDim.new(0, 8) }),
			Ui.create("UIStroke", { Color = Ui.Color.Accent, Thickness = 1 }),
			key,
			name,
			used,
		})
		table.insert(slots, { frame = frame :: Frame, key = key, name = name, used = used })
		table.insert(children, frame)
	end
	local row = Ui.create("Frame", {
		Name = "Hikei",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -MARGIN, 1, -(MARGIN + GEKIHASU_HEIGHT + 10)),
		Size = UDim2.fromOffset((HIKEI_WIDTH + HIKEI_GAP) * #InputMap.Hikei, HIKEI_HEIGHT),
		BackgroundTransparency = 1,
		Visible = false,
	}, children)
	return row :: Frame, slots
end

local function buildGui(): Gui
	local healthBar, healthFill = bar("Health", 14, 20, Ui.Color.Health)
	local gaugeBar, gaugeFill = bar("OugiGauge", 50, 14, Ui.Color.Gauge)
	local healthText = label({
		Name = "HealthText",
		Position = UDim2.fromOffset(64 + BAR_WIDTH + 10, 12),
		Size = UDim2.fromOffset(90, 24),
		Font = Ui.Font.Heavy,
		Text = "0",
	})

	local pips: { Frame } = {}
	local pipChildren: { Instance } = {
		Ui.create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, PIP_GAP),
			VerticalAlignment = Enum.VerticalAlignment.Center,
		}),
	}
	for index = 1, Config.Ougi.MaxStock do
		local pip = Ui.create("Frame", {
			Name = `Stock{index}`,
			LayoutOrder = index,
			Size = UDim2.fromOffset(PIP_SIZE, PIP_SIZE),
			BackgroundColor3 = Ui.Color.Disabled,
			BorderSizePixel = 0,
		}, {
			Ui.create("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
			Ui.create("UIStroke", { Color = Ui.Color.Accent, Thickness = 1 }),
		})
		table.insert(pips, pip :: Frame)
		table.insert(pipChildren, pip)
	end
	local stock = Ui.create("Frame", {
		Name = "OugiStock",
		Position = UDim2.fromOffset(64 + BAR_WIDTH + 10, 48),
		Size = UDim2.fromOffset((PIP_SIZE + PIP_GAP) * Config.Ougi.MaxStock, PIP_SIZE),
		BackgroundTransparency = 1,
	}, pipChildren)

	local panel = Ui.create("Frame", {
		Name = "Status",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, MARGIN, 1, -MARGIN),
		Size = UDim2.fromOffset(PANEL_WIDTH, PANEL_HEIGHT),
		BackgroundColor3 = Ui.Color.Panel,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
	}, {
		Ui.create("UICorner", { CornerRadius = UDim.new(0, 8) }),
		label({
			Name = "HealthLabel",
			Position = UDim2.fromOffset(12, 12),
			Size = UDim2.fromOffset(48, 24),
			Text = "体力",
		}),
		label({
			Name = "OugiLabel",
			Position = UDim2.fromOffset(12, 45),
			Size = UDim2.fromOffset(48, 24),
			Text = "奥義",
		}),
		healthBar,
		healthText,
		gaugeBar,
		stock,
	})

	local hint = label({
		Name = "Hint",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, MARGIN, 1, -(MARGIN + PANEL_HEIGHT + 8)),
		Size = UDim2.fromOffset(820, 20),
		Font = Ui.Font.Bold,
		TextSize = Ui.TextSize.Small,
		TextStrokeTransparency = 0.5,
		Text = hintText(),
	})

	local gekihasu = Ui.create("Frame", {
		Name = "Gekihasu",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -MARGIN, 1, -MARGIN),
		Size = UDim2.fromOffset(240, GEKIHASU_HEIGHT),
		BackgroundTransparency = 1,
	}, {
		label({
			Name = "Title",
			Size = UDim2.new(1, 0, 0, 22),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = Ui.Color.Accent,
			Text = "撃破数",
		}),
		label({
			Name = "Count",
			Position = UDim2.fromOffset(0, 20),
			Size = UDim2.new(1, 0, 0, 52),
			Font = Ui.Font.Heavy,
			TextSize = Ui.TextSize.Huge,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextStrokeTransparency = 0.3,
			Text = "0",
		}),
	})

	local hikeiRow, hikeiSlots = buildHikeiRow()

	Ui.screenGui("HUD", Ui.Layer.Hud, { panel, hint, gekihasu, hikeiRow })

	return {
		healthFill = healthFill,
		healthText = healthText,
		gaugeFill = gaugeFill,
		pips = pips,
		gekihasu = gekihasu:FindFirstChild("Count") :: TextLabel,
		hint = hint,
		hikeiRow = hikeiRow,
		hikeiSlots = hikeiSlots,
	}
end

-- Roblox 標準の体力表示を消す。読み込み直後は失敗することがあるので、通るまでやり直す
local function disableCoreHealth()
	for _ = 1, 20 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
		end)
		if ok then
			return
		end
		task.wait(0.5)
	end
	warn("HUDController: 標準の体力表示を消せなかった")
end

function HUDController.start()
	local gui = buildGui()
	task.spawn(disableCoreHealth)

	local function refreshGekihasu()
		gui.gekihasu.Text = tostring(player:GetAttribute("Gekihasu") or 0)
	end

	-- ゲージは次の1本までの量を出す。本数が上限なら満タンで出す
	local function refreshOugi()
		local stock = player:GetAttribute("OugiStock") :: number? or 0
		local amount = player:GetAttribute("OugiGauge") :: number? or 0
		local full = stock >= Config.Ougi.MaxStock
		local ratio = if full then 1 else math.clamp(amount / Config.Ougi.PerStock, 0, 1)
		TweenService:Create(gui.gaugeFill, TWEEN, { Size = UDim2.fromScale(ratio, 1) }):Play()
		gui.gaugeFill.BackgroundColor3 = if full then Ui.Color.GaugeFull else Ui.Color.Gauge
		for index, pip in gui.pips do
			pip.BackgroundColor3 = if index <= stock then Ui.Color.GaugeFull else Ui.Color.Disabled
		end
	end

	-- 持ち込んだ秘計の枚に、名前と切るボタンを出す。使用済みの枚は暗くする
	local function refreshHikei()
		local mochikomi = Hikei.decodeList(player:GetAttribute(Hikei.MOCHIKOMI_ATTRIBUTE))
		local used = Hikei.decodeList(player:GetAttribute(Hikei.USED_ATTRIBUTE))
		gui.hikeiRow.Visible = #mochikomi > 0
		for slot, view in gui.hikeiSlots do
			local id = mochikomi[slot]
			local definition = if id then Hikei.get(id) else nil
			view.frame.Visible = definition ~= nil
			if definition then
				local isUsed = table.find(used, definition.id) ~= nil
				view.key.Text = Ui.label(InputMap.Hikei[slot].labels)
				view.name.Text = definition.displayName
				view.frame.BackgroundTransparency = if isUsed then 0.75 else 0.35
				view.key.TextColor3 = if isUsed then Ui.Color.Disabled else Ui.Color.Accent
				view.name.TextColor3 = if isUsed then Ui.Color.Disabled else Ui.Color.Text
				view.used.Visible = isUsed
			end
		end
	end

	local healthConnections: { RBXScriptConnection } = {}
	local function watchHealth(character: Model)
		for _, connection in healthConnections do
			connection:Disconnect()
		end
		table.clear(healthConnections)
		local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
		if not humanoid then
			return
		end
		local function refresh()
			local ratio = if humanoid.MaxHealth > 0 then math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1) else 0
			TweenService:Create(gui.healthFill, TWEEN, { Size = UDim2.fromScale(ratio, 1) }):Play()
			gui.healthFill.BackgroundColor3 = if ratio <= LOW_HEALTH then Ui.Color.HealthLow else Ui.Color.Health
			gui.healthText.Text = `{math.ceil(humanoid.Health)} / {math.ceil(humanoid.MaxHealth)}`
		end
		table.insert(healthConnections, humanoid.HealthChanged:Connect(refresh))
		table.insert(healthConnections, humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(refresh))
		refresh()
	end

	player:GetAttributeChangedSignal("Gekihasu"):Connect(refreshGekihasu)
	player:GetAttributeChangedSignal("OugiStock"):Connect(refreshOugi)
	player:GetAttributeChangedSignal("OugiGauge"):Connect(refreshOugi)
	player:GetAttributeChangedSignal(Hikei.MOCHIKOMI_ATTRIBUTE):Connect(refreshHikei)
	player:GetAttributeChangedSignal(Hikei.USED_ATTRIBUTE):Connect(refreshHikei)
	player.CharacterAdded:Connect(watchHealth)
	if player.Character then
		task.spawn(watchHealth, player.Character)
	end
	Ui.onInputKindChanged(function()
		gui.hint.Text = hintText()
		refreshHikei()
	end)
	refreshGekihasu()
	refreshOugi()
	refreshHikei()
end

return HUDController
