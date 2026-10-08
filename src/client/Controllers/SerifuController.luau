--!strict
-- 戦闘中の台詞。Remotes.PlaySerifu（話者のキャラクター ID・表情・台詞 ID）を受けて、画面の左側（HUD の上）に
-- 顔グラフィックと名前と台詞を出す。入力を受け取らない表示だけなので、出している間も操作・カメラ・HUD はそのまま。
-- 続けて届いた台詞は順番に出し、順番待ちの上限を超えたら古い台詞から捨てる。
-- 1本を出しておく秒数と順番待ちの上限は Config.luau の Serifu 節、文は ReplicatedStorage.Shared.Serifu にある。
--
-- - 顔は会話窓と同じ顔グラフィックの登録表から引く。登録の無い話者は顔の枠を出さない
-- - 長い台詞は折り返し、枠に収まらなければ文字を小さくする
-- - タッチの配置（スマホの戦闘の操作ボタンを出している間）では、画面の大きさに合わせて枠ごと縮める（Ui.fitTouchLayout）

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

type Line = {
	speaker: string,
	hyojo: RemoteSchema.Hyojo,
	text: string,
}

type Gui = {
	screen: ScreenGui,
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
		face,
		name,
		text,
	})
	local screen = Ui.screenGui("BattleSerifu", Ui.Layer.BattleSerifu, { panel })
	screen.Enabled = false
	Ui.fitTouchLayout(panel)
	return { screen = screen, face = face :: ImageLabel, name = name, text = text }
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
	local character = Characters.get(line.speaker)
	local image = KaoGraphic.imageOf(line.speaker, line.hyojo)
	local left = if image then PADDING * 2 + FACE_SIZE else PADDING * 2
	gui.face.Visible = image ~= nil
	gui.face.Image = image or ""
	gui.name.Text = if character then character.displayName else line.speaker
	gui.name.Position = UDim2.fromOffset(left, PADDING)
	gui.name.Size = UDim2.fromOffset(WIDTH - left - PADDING * 2, NAME_HEIGHT)
	local textWidth = WIDTH - left - PADDING * 2
	local textHeight = HEIGHT - NAME_HEIGHT - PADDING * 3
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

	local function showAll()
		while #queue > 0 do
			local line = table.remove(queue, 1) :: Line
			display(gui, line)
			task.wait(Config.Serifu.BattleTime)
		end
		gui.screen.Enabled = false
		showing = false
	end

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
