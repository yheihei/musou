--!strict
-- ミニマップ。画面の右上に、出撃したステージの区画を北を上にして描き、拠点と本陣を軍の色で、自分と仲間の位置と向きを出す。
-- 範囲は workspace の Attribute の MinimapCenter・MinimapSize、拠点は ReplicatedStorage.Kyoten の拠点ごとの Configuration の
-- Attribute（Gun・Honjin・Position・Size）、仲間の位置と向きは Player の Attribute の MinimapPosition・MinimapFacing から読む
-- （範囲と仲間の位置はサーバーの MinimapService が書く）。自分の位置と向きは自分のキャラクターから読む。
-- 計算は ReplicatedStorage.Shared.Minimap、大きさは Ui.Minimap、描き直す間隔は Config.luau の Minimap 節にある。
--
-- - 出すのは戦闘のフェーズの出撃メンバーだけ（画面上部の戦況と同じ条件。BattleStatus.isVisible）。
--   ロビー・イベントシーン・リザルトのフェーズと、待機中の人と、イベントシーンの再生中には出さない
-- - 背景は単色で、区画の範囲を少し明るい色で塗る。北の印を上端に出す
-- - 拠点は範囲の大きさの四角を軍の色で塗る。本陣は白い縁と「本」の字で見分ける。制圧されたら次に描き直すときに色が変わる
-- - 自分は黄色の大きい丸、仲間は白い丸で、どちらも向きを示す針を付ける。範囲の外にいる仲間は地図の縁に出す
-- - 出している間は Config.luau の Minimap 節の UpdateInterval ごとに描き直す
-- - テストプレイでの確認用に、PlayerGui.Minimap.Panel.Map の下の Kyoten（拠点 ID の名前）と Members（プレイヤー名）の
--   Frame の Position・BackgroundColor3 で読める

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BattleStatus = require(ReplicatedStorage.Shared.BattleStatus)
local Colors = require(ReplicatedStorage.Shared.Colors)
local Config = require(ReplicatedStorage.Shared.Config)
local Gun = require(ReplicatedStorage.Shared.Gun)
local Minimap = require(ReplicatedStorage.Shared.Minimap)
local PartyClient = require(script.Parent.Parent.PartyClient)
local Ui = require(script.Parent.Parent.Ui)
local EventSceneController = require(script.Parent.EventSceneController)

local MinimapController = {}

local player = Players.LocalPlayer

-- 拠点の Attribute を置くフォルダ（ReplicatedStorage の下。KyotenService.FOLDER）
local KYOTEN_FOLDER = "Kyoten"
-- 枠の内側の余白と、地図の一辺（ピクセル）
local PADDING = 6
local MAP_SIZE = Ui.Minimap.Size - PADDING * 2
-- 拠点の四角の一辺の下限（ピクセル）
local KYOTEN_MIN = 8
-- 自分と仲間の丸の大きさと、向きの針の長さと太さ（ピクセル）
local SELF_DOT = 11
local MEMBER_DOT = 8
local NEEDLE_LENGTH = 10
local NEEDLE_WIDTH = 2

local BACKGROUND_COLOR = Color3.fromRGB(18, 22, 20)
local FIELD_COLOR = Color3.fromRGB(56, 66, 52)
local SELF_COLOR = Ui.Color.Selected
local MEMBER_COLOR = Color3.new(1, 1, 1)
local OUTLINE_COLOR = Color3.new(0, 0, 0)

-- 地図の層。後に並べたものほど上に重ねる
local LAYERS = { "Field", "Kyoten", "Members", "North" }
-- 描き直すたびに中身を作り直す層（北の印は作ったまま残す）
local DRAWN_LAYERS = { "Field", "Kyoten", "Members" }

-- 描くときの範囲。中心と縮尺
type View = {
	centerX: number,
	centerZ: number,
	scale: number,
}

type Gui = {
	screen: ScreenGui,
	-- 層の名前から引く、層の Frame
	layers: { [string]: Frame },
}

local gui: Gui

-- 層の下の name の Frame。無ければ create で作って置く
local function childOf(layer: Frame, name: string, create: () -> Frame): Frame
	local existing = layer:FindFirstChild(name)
	if existing and existing:IsA("Frame") then
		return existing
	end
	local created = create()
	created.Name = name
	created.Parent = layer
	return created
end

-- 層の下で、今回描かなかった Frame を消す
local function removeUnseen(layer: Frame, seen: { [string]: boolean })
	for _, child in layer:GetChildren() do
		if not seen[child.Name] then
			child:Destroy()
		end
	end
end

-- 出撃したステージの区画の範囲。まだ届いていなければ nil
local function viewOf(): View?
	local center = workspace:GetAttribute(Minimap.CENTER_ATTRIBUTE)
	local size = workspace:GetAttribute(Minimap.SIZE_ATTRIBUTE)
	if typeof(center) ~= "Vector2" or typeof(size) ~= "Vector2" then
		return nil
	end
	local scale = Minimap.scaleOf(size.X, size.Y, MAP_SIZE)
	if scale <= 0 then
		return nil
	end
	return { centerX = center.X, centerZ = center.Y, scale = scale }
end

local function drawField(view: View)
	local size = workspace:GetAttribute(Minimap.SIZE_ATTRIBUTE) :: Vector2
	local field = childOf(gui.layers.Field, "Kukaku", function()
		return Ui.create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			BackgroundColor3 = FIELD_COLOR,
			BorderSizePixel = 0,
		}, { Ui.create("UICorner", { CornerRadius = UDim.new(0, 4) }) })
	end)
	field.Size = UDim2.fromOffset(size.X * view.scale, size.Y * view.scale)
end

local function newKyoten(honjin: boolean): Frame
	local children: { Instance } = {
		Ui.create("UICorner", { CornerRadius = UDim.new(0, 2) }),
		Ui.create("UIStroke", {
			Color = if honjin then Color3.new(1, 1, 1) else OUTLINE_COLOR,
			Thickness = if honjin then 2 else 1,
			Transparency = if honjin then 0 else 0.3,
		}),
	}
	if honjin then
		table.insert(
			children,
			Ui.text({
				Name = "Label",
				Size = UDim2.fromScale(1, 1),
				Font = Ui.Font.Heavy,
				TextSize = Ui.TextSize.Small,
				TextStrokeTransparency = 0.4,
				TextXAlignment = Enum.TextXAlignment.Center,
				Text = "本",
			})
		)
	end
	return Ui.create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BorderSizePixel = 0,
		BackgroundTransparency = 0.1,
	}, children)
end

-- 拠点と本陣を軍の色で描く
local function drawKyoten(view: View)
	local layer = gui.layers.Kyoten
	local folder = ReplicatedStorage:FindFirstChild(KYOTEN_FOLDER)
	local seen: { [string]: boolean } = {}
	for _, config in if folder then folder:GetChildren() else {} do
		local gun = config:GetAttribute("Gun")
		local position = config:GetAttribute("Position")
		local size = config:GetAttribute("Size")
		if not Gun.isGun(gun) or typeof(position) ~= "Vector2" or typeof(size) ~= "Vector2" then
			continue
		end
		local honjin = config:GetAttribute("Honjin") == true
		seen[config.Name] = true
		local frame = childOf(layer, config.Name, function()
			return newKyoten(honjin)
		end)
		local px, py = Minimap.toMap(position.X, position.Y, view.centerX, view.centerZ, view.scale, MAP_SIZE)
		frame.Position = UDim2.fromOffset(px, py)
		frame.Size =
			UDim2.fromOffset(math.max(size.X * view.scale, KYOTEN_MIN), math.max(size.Y * view.scale, KYOTEN_MIN))
		frame.BackgroundColor3 = Colors.Gun[gun :: Gun.Gun]
	end
	removeUnseen(layer, seen)
end

local function newMember(isSelf: boolean): Frame
	local dot = if isSelf then SELF_DOT else MEMBER_DOT
	local color = if isSelf then SELF_COLOR else MEMBER_COLOR
	return Ui.create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(dot, dot),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		ZIndex = if isSelf then 2 else 1,
	}, {
		Ui.create("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		Ui.create("UIStroke", { Color = OUTLINE_COLOR, Thickness = 1 }),
		-- 向きの針。丸の中心から向きの方へ伸ばす（回転は針の中心で行うので、中心を針の長さの半分だけずらす）
		Ui.create("Frame", {
			Name = "Needle",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(NEEDLE_WIDTH, NEEDLE_LENGTH),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
		}),
	})
end

-- プレイヤーの位置と向き。自分は自分のキャラクターから、仲間はサーバーが書いた Attribute から読む。無ければ nil
local function memberPose(target: Player): (Vector2?, number)
	if target == player then
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if humanoid and root and humanoid.Health > 0 then
			local look = root.CFrame.LookVector
			return Vector2.new(root.Position.X, root.Position.Z), Minimap.facingOf(look.X, look.Z)
		end
		return nil, 0
	end
	local position = target:GetAttribute(Minimap.POSITION_ATTRIBUTE)
	local facing = target:GetAttribute(Minimap.FACING_ATTRIBUTE)
	if typeof(position) ~= "Vector2" then
		return nil, 0
	end
	return position, if type(facing) == "number" then facing else 0
end

-- 自分と仲間の位置と向きを描く
local function drawMembers(view: View)
	local layer = gui.layers.Members
	local seen: { [string]: boolean } = {}
	for _, target in Players:GetPlayers() do
		local position, facing = memberPose(target)
		if not position then
			continue
		end
		local isSelf = target == player
		seen[target.Name] = true
		local frame = childOf(layer, target.Name, function()
			return newMember(isSelf)
		end)
		local px, py = Minimap.toMap(position.X, position.Y, view.centerX, view.centerZ, view.scale, MAP_SIZE)
		px, py = Minimap.clampToMap(px, py, MAP_SIZE)
		frame.Position = UDim2.fromOffset(px, py)
		local needle = frame:FindFirstChild("Needle") :: Frame?
		if needle then
			local angle = math.rad(facing)
			needle.Rotation = facing
			needle.Position =
				UDim2.new(0.5, math.sin(angle) * NEEDLE_LENGTH / 2, 0.5, -math.cos(angle) * NEEDLE_LENGTH / 2)
		end
	end
	removeUnseen(layer, seen)
end

local function redraw()
	local view = viewOf()
	if not view then
		for _, name in DRAWN_LAYERS do
			gui.layers[name]:ClearAllChildren()
		end
		return
	end
	drawField(view)
	drawKyoten(view)
	drawMembers(view)
end

local function buildGui(): Gui
	local layers: { [string]: Frame } = {}
	local layerFrames: { Instance } = {}
	for index, name in LAYERS do
		local layer: Frame = Ui.create("Frame", {
			Name = name,
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = index,
		})
		layers[name] = layer
		table.insert(layerFrames, layer)
	end
	local map = Ui.create("Frame", {
		Name = "Map",
		Position = UDim2.fromOffset(PADDING, PADDING),
		Size = UDim2.fromOffset(MAP_SIZE, MAP_SIZE),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
	}, layerFrames)
	-- 北の印。地図の上端の真ん中に出す
	Ui.text({
		Name = "Label",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(20, 16),
		Font = Ui.Font.Bold,
		TextSize = Ui.TextSize.Small,
		TextStrokeTransparency = 0.3,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "北",
		Parent = layers.North,
	})
	local panel = Ui.create("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -Ui.Minimap.Right, 0, Ui.Minimap.Top),
		Size = UDim2.fromOffset(Ui.Minimap.Size, Ui.Minimap.Size),
		BackgroundColor3 = BACKGROUND_COLOR,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
	}, {
		Ui.create("UICorner", { CornerRadius = UDim.new(0, 8) }),
		Ui.create("UIStroke", { Color = Ui.Color.Accent, Thickness = 1 }),
		map,
	})
	local screen = Ui.screenGui("Minimap", Ui.Layer.Minimap, { panel })
	screen.Enabled = false
	return { screen = screen, layers = layers }
end

function MinimapController.start()
	gui = buildGui()

	-- 渡される PartyState は、続けて届いたときに最新でないことがあるので、最新の写しで決める
	local function refreshVisible()
		local state = PartyClient.get()
		local me = PartyClient.me()
		local visible = BattleStatus.isVisible(
			if state then state.phase else nil,
			me == nil or me.waiting,
			EventSceneController.isPlaying()
		)
		if visible and not gui.screen.Enabled then
			-- 出す前に描き直し、前のステージの地図を一瞬でも見せない
			redraw()
		end
		gui.screen.Enabled = visible
	end

	PartyClient.changed:Connect(refreshVisible)
	EventSceneController.started:Connect(refreshVisible)
	EventSceneController.stopped:Connect(refreshVisible)
	refreshVisible()

	task.spawn(function()
		while true do
			task.wait(Config.Minimap.UpdateInterval)
			if gui.screen.Enabled then
				-- 1回の失敗で描き直しが止まらないよう、失敗は警告にして次の間隔で続ける
				local ok, err = pcall(redraw)
				if not ok then
					warn(`MinimapController: ミニマップを描き直せなかった: {err}`)
				end
			end
		end
	end)
end

return MinimapController
