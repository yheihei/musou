--!strict
-- イベントシーンの会話窓。話者・表情・台詞を say に渡すと、画面の下に顔グラフィックと名前と台詞を出し、
-- 1文字ずつ表示して、表示時間がたったら戻る。全員が同じ進行で見るよう、ボタンでなく時間で送る。
-- 送りの速さと表示時間は Config.luau の Serifu 節にあり、秒数の計算は ReplicatedStorage.Shared.Serifu が持つ。
--
-- - 話者はキャラクター ID。名前はキャラクターの定義表から引き、無ければ渡した文字列をそのまま名前にする
-- - 顔は顔グラフィックの登録表（KaoGraphic）から引く。登録の無い話者は顔の枠を出さず、台詞を左へ広げる
-- - 長い台詞は折り返し、枠に収まらなければ文字を小さくする
-- - say を続けて呼ぶと、前の台詞を打ち切って新しい台詞を出す

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")

local Characters = require(ReplicatedStorage.Shared.Characters)
local KaoGraphic = require(ReplicatedStorage.Shared.KaoGraphic)
local RemoteSchema = require(ReplicatedStorage.Shared.RemoteSchema)
local Serifu = require(ReplicatedStorage.Shared.Serifu)
local Ui = require(script.Parent.Ui)

local Dialogue = {}

-- 窓の大きさと顔の大きさ（ピクセル）
local WINDOW_HEIGHT = 168
local WINDOW_MAX_WIDTH = 920
local FACE_SIZE = 148
local PADDING = 12
local NAME_HEIGHT = 30
-- 台詞の文字の大きさの上限と下限。収まらなければ上限から2ずつ小さくする
local TEXT_SIZE_MAX = Ui.TextSize.Large
local TEXT_SIZE_MIN = 14

type Gui = {
	screen: ScreenGui,
	face: ImageLabel,
	name: TextLabel,
	text: TextLabel,
}

local gui: Gui? = nil
-- 今出している台詞の番号。say を続けて呼んだら前の台詞を打ち切るのに使う
local current = 0

local function build(): Gui
	local face = Ui.create("ImageLabel", {
		Name = "Face",
		Position = UDim2.fromOffset(PADDING, (WINDOW_HEIGHT - FACE_SIZE) / 2),
		Size = UDim2.fromOffset(FACE_SIZE, FACE_SIZE),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.5,
	}, {
		Ui.create("UICorner", { CornerRadius = UDim.new(0, 8) }),
	})
	local name = Ui.text({
		Name = "SpeakerName",
		Size = UDim2.new(1, 0, 0, NAME_HEIGHT),
		Font = Ui.Font.Heavy,
		TextSize = Ui.TextSize.Large,
		TextColor3 = Ui.Color.Accent,
	})
	local text = Ui.text({
		Name = "Line",
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextSize = TEXT_SIZE_MAX,
		Font = Ui.Font.Body,
	})
	local window = Ui.create("Frame", {
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.new(0.8, 0, 0, WINDOW_HEIGHT),
		BackgroundColor3 = Ui.Color.Panel,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
	}, {
		Ui.create("UICorner", { CornerRadius = UDim.new(0, 10) }),
		Ui.create("UIStroke", { Color = Ui.Color.Accent, Thickness = 2 }),
		Ui.create("UISizeConstraint", { MaxSize = Vector2.new(WINDOW_MAX_WIDTH, WINDOW_HEIGHT) }),
		face,
		name,
		text,
	})
	local screen = Ui.screenGui("Dialogue", Ui.Layer.Dialogue, { window })
	screen.Enabled = false
	return { screen = screen, face = face :: ImageLabel, name = name, text = text }
end

local function getGui(): Gui
	if not gui then
		gui = build()
	end
	return gui :: Gui
end

-- 顔の有無で、名前と台詞の左端を決める
local function layout(view: Gui, hasFace: boolean)
	local left = if hasFace then PADDING * 2 + FACE_SIZE else PADDING * 2
	view.face.Visible = hasFace
	view.name.Position = UDim2.fromOffset(left, PADDING)
	view.name.Size = UDim2.new(1, -(left + PADDING * 2), 0, NAME_HEIGHT)
	view.text.Position = UDim2.fromOffset(left, PADDING + NAME_HEIGHT + 4)
	view.text.Size = UDim2.new(1, -(left + PADDING * 2), 1, -(PADDING * 2 + NAME_HEIGHT + 4))
end

-- 台詞が枠に収まる文字の大きさ。上限から2ずつ小さくし、下限でも収まらなければ下限にする
local function fitTextSize(label: TextLabel, text: string): number
	local width = label.AbsoluteSize.X
	local height = label.AbsoluteSize.Y
	if width <= 0 or height <= 0 then
		return TEXT_SIZE_MAX
	end
	local size = TEXT_SIZE_MAX
	while size > TEXT_SIZE_MIN do
		local bounds = TextService:GetTextSize(text, size, label.Font, Vector2.new(width, math.huge))
		if bounds.Y <= height then
			break
		end
		size -= 2
	end
	return size
end

-- 会話窓に台詞を出し、1文字ずつ表示して、表示時間がたったら戻る（その間は待つ）。
-- 戻った後も窓は残る。閉じるのは close
function Dialogue.say(speaker: string, hyojo: RemoteSchema.Hyojo, line: string)
	current += 1
	local token = current
	local view = getGui()
	local character = Characters.get(speaker)
	local image = KaoGraphic.imageOf(speaker, hyojo)
	view.name.Text = if character then character.displayName else speaker
	view.face.Image = image or ""
	layout(view, image ~= nil)
	view.screen.Enabled = true
	view.text.Text = line
	-- 位置と大きさが決まってから文字の大きさを合わせる
	RunService.Heartbeat:Wait()
	if token ~= current then
		return
	end
	view.text.TextSize = fitTextSize(view.text, line)

	local count = Serifu.length(line)
	local typing = Serifu.typingTime(line)
	local started = os.clock()
	view.text.MaxVisibleGraphemes = 0
	while token == current do
		local elapsed = os.clock() - started
		if elapsed >= typing then
			break
		end
		view.text.MaxVisibleGraphemes = math.floor(elapsed / typing * count)
		RunService.Heartbeat:Wait()
	end
	if token ~= current then
		return
	end
	view.text.MaxVisibleGraphemes = -1
	local hold = Serifu.lineTime(line) - typing
	local holdUntil = os.clock() + hold
	while token == current and os.clock() < holdUntil do
		RunService.Heartbeat:Wait()
	end
end

-- 会話窓を閉じる。出している途中の台詞は打ち切る
function Dialogue.close()
	current += 1
	if gui then
		gui.screen.Enabled = false
	end
end

-- 会話窓を出しているか
function Dialogue.isOpen(): boolean
	return gui ~= nil and gui.screen.Enabled
end

return Dialogue
