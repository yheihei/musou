--!strict
-- 戦闘中の台詞。Remotes.PlaySerifu（話者のキャラクター ID・表情・台詞 ID）を受けて、画面の左側（HUD の上）に
-- 顔グラフィックと名前と台詞を出す。入力を受け取らない表示だけなので、出している間も操作・カメラ・HUD はそのまま。
-- 続けて届いた台詞は順番に出し、順番待ちの上限を超えたら古い台詞から捨てる。
-- 1本を出しておく秒数と順番待ちの上限は Config.luau の Serifu 節、文は ReplicatedStorage.Shared.Serifu にある。
--
-- - 顔は会話窓と同じ顔グラフィックの登録表から引く。登録の無い話者は顔の枠を出さない
-- - 長い台詞は折り返し、枠に収まらなければ文字を小さくする（TEXT_SIZE_MIN まで）
-- - タッチの配置（スマホの戦闘の操作ボタンを出している間）では、枠を少し狭く高くし（TOUCH_WIDTH x TOUCH_HEIGHT）、
--   ReplicatedStorage.Shared.TouchLayout が決めた位置（ボタンと秘計の知らせを避ける）に、決めた倍率で縮めて出す。
--   倍率は戦闘の画面の倍率より大きく、一番小さい文字（TEXT_SIZE_MIN）が読める下限（Config.luau の SmallScreen 節の
--   MinTextSize）を下回らない（Ui.touchLayout の placement の serifu と serifuScale）

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Characters = require(ReplicatedStorage.Shared.Characters)
local Config = require(ReplicatedStorage.Shared.Config)
local KaoGraphic = require(ReplicatedStorage.Shared.KaoGraphic)
local RemoteSchema = require(ReplicatedStorage.Shared.RemoteSchema)
local Serifu = require(ReplicatedStorage.Shared.Serifu)
local Ui = require(script.Parent.Parent.Ui)

local SerifuController = {}

-- 画面の端からの余白、HUD（左下の枠と操作の案内）の上に置くための下の余白、枠と顔の大きさ（ピクセル）
local MARGIN = 24
local BOTTOM = 148
local WIDTH = 440
local HEIGHT = 96
local FACE_SIZE = 84
local PADDING = 6
local NAME_HEIGHT = 24
local TEXT_SIZE_MAX = Ui.TextSize.Body
local TEXT_SIZE_MIN = 13
-- タッチの配置での枠と顔の大きさ（縮める前のピクセル）。スマホでボタンと秘計の知らせを避けて置けるよう幅を狭め、
-- 同じ長さの台詞が入るよう高さを足す（ReplicatedStorage.Shared.TouchLayout の SERIFU_WIDTH・SERIFU_HEIGHT と同じ値）
local TOUCH_WIDTH = 360
local TOUCH_HEIGHT = 108
local TOUCH_FACE_SIZE = 72

-- 枠と顔の大きさの組
type FrameSize = {
	width: number,
	height: number,
	face: number,
}

local NORMAL_SIZE: FrameSize = { width = WIDTH, height = HEIGHT, face = FACE_SIZE }
local TOUCH_SIZE: FrameSize = { width = TOUCH_WIDTH, height = TOUCH_HEIGHT, face = TOUCH_FACE_SIZE }

type Line = {
	speaker: string,
	hyojo: RemoteSchema.Hyojo,
	text: string,
}

type Gui = {
	screen: ScreenGui,
	panel: Frame,
	scaler: UIScale,
	face: ImageLabel,
	name: TextLabel,
	text: TextLabel,
}

local function buildGui(): Gui
	local face = Ui.create("ImageLabel", {
		Name = "Face",
		Position = UDim2.fromOffset(PADDING, PADDING),
		Size = UDim2.fromOffset(FACE_SIZE, FACE_SIZE),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.5,
	}, {
		Ui.create("UICorner", { CornerRadius = UDim.new(0, 6) }),
	})
	local name = Ui.text({
		Name = "SpeakerName",
		Font = Ui.Font.Heavy,
		TextColor3 = Ui.Color.Accent,
	})
	local text = Ui.text({
		Name = "Line",
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	-- タッチの配置で縮める倍率
	local scaler = Ui.create("UIScale", { Name = "TouchScale" })
	local panel = Ui.create("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, MARGIN, 1, -BOTTOM),
		Size = UDim2.fromOffset(WIDTH, HEIGHT),
		BackgroundColor3 = Ui.Color.Panel,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
	}, {
		Ui.create("UICorner", { CornerRadius = UDim.new(0, 8) }),
		Ui.create("UIStroke", { Color = Ui.Color.Accent, Thickness = 1 }),
		scaler,
		face,
		name,
		text,
	})
	local screen = Ui.screenGui("BattleSerifu", Ui.Layer.BattleSerifu, { panel })
	screen.Enabled = false
	return {
		screen = screen,
		panel = panel :: Frame,
		scaler = scaler :: UIScale,
		face = face :: ImageLabel,
		name = name,
		text = text,
	}
end

-- タッチの配置で出すか（TouchLayout の配置が届いているか）
local function isTouchPlacement(): boolean
	local layout = Ui.touchLayout()
	return layout.active and layout.placement ~= nil
end

-- 今の枠と顔の大きさ。タッチの配置では狭く高い枠にする
local function frameSize(): FrameSize
	return if isTouchPlacement() then TOUCH_SIZE else NORMAL_SIZE
end

-- 枠の大きさと位置と倍率を決める。タッチの配置では TouchLayout が決めた位置（設計の大きさに戦闘の画面の倍率を掛ける）と
-- 倍率（読める下限で止めた倍率）、そうでなければ左下の HUD の上に縮めずに出す
local function place(gui: Gui)
	local size = frameSize()
	gui.panel.Size = UDim2.fromOffset(size.width, size.height)
	local placement = Ui.touchLayout().placement
	if isTouchPlacement() and placement then
		gui.panel.AnchorPoint = Vector2.zero
		gui.panel.Position =
			UDim2.fromOffset(placement.serifu.x * placement.scale, placement.serifu.y * placement.scale)
		gui.scaler.Scale = placement.serifuScale
	else
		gui.panel.AnchorPoint = Vector2.new(0, 1)
		gui.panel.Position = UDim2.new(0, MARGIN, 1, -BOTTOM)
		gui.scaler.Scale = 1
	end
end

-- 台詞が枠に収まる文字の大きさ
local function fitTextSize(text: string, width: number, height: number): number
	local size = TEXT_SIZE_MAX
	while size > TEXT_SIZE_MIN do
		local bounds = TextService:GetTextSize(text, size, Ui.Font.Body, Vector2.new(width, math.huge))
		if bounds.Y <= height then
			break
		end
		size -= 1
	end
	return size
end

local function display(gui: Gui, line: Line)
	local size = frameSize()
	local character = Characters.get(line.speaker)
	local image = KaoGraphic.imageOf(line.speaker, line.hyojo)
	local left = if image then PADDING * 2 + size.face else PADDING * 2
	gui.face.Visible = image ~= nil
	gui.face.Image = image or ""
	gui.face.Size = UDim2.fromOffset(size.face, size.face)
	gui.name.Text = if character then character.displayName else line.speaker
	gui.name.Position = UDim2.fromOffset(left, PADDING)
	gui.name.Size = UDim2.fromOffset(size.width - left - PADDING * 2, NAME_HEIGHT)
	local textWidth = size.width - left - PADDING * 2
	local textHeight = size.height - NAME_HEIGHT - PADDING * 3
	gui.text.Position = UDim2.fromOffset(left, PADDING + NAME_HEIGHT + 2)
	gui.text.Size = UDim2.fromOffset(textWidth, textHeight)
	gui.text.TextSize = fitTextSize(line.text, textWidth, textHeight)
	gui.text.Text = line.text
	gui.screen.Enabled = true
end

function SerifuController.start()
	local gui = buildGui()
	local queue: { Line } = {}
	local showing = false
	-- 出している台詞
	local current: Line? = nil

	local function showAll()
		while #queue > 0 do
			local line = table.remove(queue, 1) :: Line
			current = line
			display(gui, line)
			task.wait(Config.Serifu.BattleTime)
		end
		current = nil
		gui.screen.Enabled = false
		showing = false
	end

	-- タッチの配置が変わったら置き直し、出している台詞は新しい枠の大きさで出し直す
	Ui.onTouchLayoutChanged(function()
		place(gui)
		local line = current
		if line then
			display(gui, line)
		end
	end)
	place(gui)

	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PlaySerifu") :: RemoteEvent
	remote.OnClientEvent:Connect(function(speaker: unknown, hyojo: unknown, serifuId: unknown)
		if type(speaker) ~= "string" or type(serifuId) ~= "string" then
			return
		end
		if not table.find(RemoteSchema.hyojo, hyojo :: any) then
			return
		end
		local text = Serifu.textOf(serifuId)
		if not text then
			warn(`SerifuController: 台詞 {serifuId} は Serifu.luau の表に無い`)
			return
		end
		Serifu.enqueue(queue, { speaker = speaker, hyojo = hyojo :: RemoteSchema.Hyojo, text = text })
		if not showing then
			showing = true
			task.spawn(showAll)
		end
	end)
end

return SerifuController
