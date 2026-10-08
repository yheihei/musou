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
-- - 発動の知らせ（どちらの軍の秘計でも）には、秘計の発動の効果音（HikeiHatsudo）を添える。ほかの知らせは鳴らさない
-- - タッチの配置（スマホの戦闘の操作ボタンを出している間）では、画面の大きさに合わせて並びごと縮める（Ui.fitTouchLayout）。
--   ただし一番小さい文字（Detail の Ui.TextSize.Small）が読める下限（Config.luau の SmallScreen 節の MinTextSize）を
--   下回るほどは縮めず（TouchLayout.hikeiNoticeScaleOf）、その分、出しておく件数を Config.luau の TouchControls 節の
--   HikeiNoticeMax までにし、左の秘計の枚に近づく画面では幅を狭める（Ui.touchLayout の placement の hikeiNoticeWidth）。
--   操作ボタンは並びの下に置く（ReplicatedStorage.Shared.TouchLayout）

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Colors = require(ReplicatedStorage.Shared.Colors)
local Config = require(ReplicatedStorage.Shared.Config)
local HikeiNotice = require(ReplicatedStorage.Shared.HikeiNotice)
local SoundPlayer = require(ReplicatedStorage.Shared.SoundPlayer)
local TouchLayout = require(ReplicatedStorage.Shared.TouchLayout)
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

-- 出しておける件数と、知らせ1件の幅。タッチの配置では読める大きさで出すので、件数を減らし、狭い画面では幅も狭める
local function maxNotices(): number
	return if Ui.touchLayout().active then Config.TouchControls.HikeiNoticeMax else MAX_NOTICES
end

local function noticeWidth(): number
	local layout = Ui.touchLayout()
	local placement = layout.placement
	return if layout.active and placement then placement.hikeiNoticeWidth else WIDTH
end

-- 並びの幅と、出している知らせの幅と件数を、今の配置に合わせる
local function applyLayout()
	local width = noticeWidth()
	list.Size = UDim2.fromOffset(width, (HEIGHT + GAP) * MAX_NOTICES)
	for _, panel in shown do
		panel.Size = UDim2.fromOffset(width, HEIGHT)
	end
	while #shown > maxNotices() do
		remove(shown[#shown])
	end
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
		Size = UDim2.fromOffset(noticeWidth(), HEIGHT),
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
	while #shown > maxNotices() do
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
	Ui.fitTouchLayout(list, nil, nil, TouchLayout.hikeiNoticeScaleOf)
	Ui.onTouchLayoutChanged(applyLayout)
	applyLayout()

	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("NotifyHikei") :: RemoteEvent
	remote.OnClientEvent:Connect(function(notice: unknown)
		if not HikeiNotice.isNotice(notice) then
			warn("HikeiNoticeController: 秘計の知らせの形が正しくない")
			return
		end
		local received = notice :: HikeiNotice.Notice
		show(received)
		if received.kind == "Hatsudo" then
			SoundPlayer.playUi("HikeiHatsudo")
		end
	end)
end

return HikeiNoticeController
