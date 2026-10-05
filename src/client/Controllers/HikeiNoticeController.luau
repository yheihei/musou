--!strict
-- 秘計の知らせ。Remotes.NotifyHikei を受けて、画面の右端に秘計の名前と、誰の秘計がどうなったかを出す。
-- 発動・打ち消し・期限切れは発動者の軍の色、失敗（本人にだけ届く）は灰色の帯を付ける。
-- 文は ReplicatedStorage.Shared.HikeiNotice、出しておく秒数は Config.luau の Hikei 節の NoticeTime にある。
--
-- - 戦闘中の台詞（左下、HUD の上）と重ならないよう、右端の上寄りに縦に積む。新しい知らせを上に出す
-- - 右上のミニマップ（Ui.Minimap）と重ならないよう、ミニマップの左に、ミニマップの上端から積む
--   （ミニマップの下に積むと、低い画面で右下の HUD と重なるため）
-- - 出しておけるのは MAX_NOTICES 件まで。超えたら古いものから消す
-- - 入力を受け取らない表示だけなので、出している間も操作はそのまま

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Colors = require(ReplicatedStorage.Shared.Colors)
local Config = require(ReplicatedStorage.Shared.Config)
local HikeiNotice = require(ReplicatedStorage.Shared.HikeiNotice)
local Ui = require(script.Parent.Parent.Ui)

local HikeiNoticeController = {}

-- 画面の右端からの位置（ミニマップの左に余白をあける）と、知らせ1件の大きさ（ピクセル）
local RIGHT = Ui.Minimap.Right + Ui.Minimap.Size + 12
local WIDTH = 320
local HEIGHT = 56
local STRIPE = 6
local GAP = 6
local MAX_NOTICES = 4
-- 消えるまでの時間（秒）
local FADE_TIME = 0.3

local FAILURE_COLOR = Ui.Color.Disabled

local list: Frame
-- 出している知らせ（新しい順）
local shown: { Frame } = {}
local order = 0

local function remove(panel: Frame)
	local index = table.find(shown, panel)
	if index then
		table.remove(shown, index)
	end
	panel:Destroy()
end

local function fadeOut(panel: Frame)
	if not panel.Parent then
		return
	end
	local info = TweenInfo.new(FADE_TIME)
	TweenService:Create(panel, info, { BackgroundTransparency = 1 }):Play()
	for _, child in panel:GetDescendants() do
		if child:IsA("TextLabel") then
			TweenService:Create(child, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		elseif child:IsA("Frame") then
			TweenService:Create(child, info, { BackgroundTransparency = 1 }):Play()
		end
	end
	task.delay(FADE_TIME, function()
		if panel.Parent then
			remove(panel)
		end
	end)
end

local function show(notice: HikeiNotice.Notice)
	order -= 1
	local color = if notice.kind == "Shippai" then FAILURE_COLOR else Colors.Gun[notice.gun]
	local panel = Ui.create("Frame", {
		Name = "Notice",
		LayoutOrder = order,
		Size = UDim2.fromOffset(WIDTH, HEIGHT),
		BackgroundColor3 = Ui.Color.Panel,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
	}, {
		Ui.create("UICorner", { CornerRadius = UDim.new(0, 8) }),
		Ui.create("Frame", {
			Name = "Stripe",
			Size = UDim2.new(0, STRIPE, 1, 0),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
		}),
		Ui.text({
			Name = "Title",
			Position = UDim2.fromOffset(STRIPE + 10, 4),
			Size = UDim2.new(1, -(STRIPE + 20), 0, 26),
			Font = Ui.Font.Heavy,
			TextSize = Ui.TextSize.Large,
			TextColor3 = if notice.kind == "Shippai" then Ui.Color.Text else color:Lerp(Color3.new(1, 1, 1), 0.45),
			TextStrokeTransparency = 0.5,
			Text = HikeiNotice.titleOf(notice),
		}),
		Ui.text({
			Name = "Detail",
			Position = UDim2.fromOffset(STRIPE + 10, 30),
			Size = UDim2.new(1, -(STRIPE + 20), 0, 20),
			TextSize = Ui.TextSize.Small,
			TextStrokeTransparency = 0.6,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = HikeiNotice.detailOf(notice),
		}),
	})
	panel.Parent = list
	table.insert(shown, 1, panel)
	while #shown > MAX_NOTICES do
		remove(shown[#shown])
	end
	task.delay(Config.Hikei.NoticeTime, fadeOut, panel)
end

function HikeiNoticeController.start()
	list = Ui.create("Frame", {
		Name = "List",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -RIGHT, 0, Ui.Minimap.Top),
		Size = UDim2.fromOffset(WIDTH, (HEIGHT + GAP) * MAX_NOTICES),
		BackgroundTransparency = 1,
	}, {
		Ui.create("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, GAP),
		}),
	})
	Ui.screenGui("HikeiNotice", Ui.Layer.HikeiNotice, { list })

	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("NotifyHikei") :: RemoteEvent
	remote.OnClientEvent:Connect(function(notice: unknown)
		if not HikeiNotice.isNotice(notice) then
			warn("HikeiNoticeController: 秘計の知らせの形が正しくない")
			return
		end
		show(notice :: HikeiNotice.Notice)
	end)
end

return HikeiNoticeController
