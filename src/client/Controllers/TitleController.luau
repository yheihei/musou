--!strict
-- タイトル画面。入室するたびに、ロビーの画面より手前に出す（保存はしない）。
-- タイトル、非公式ファンゲームかつパラレル設定である旨の表記、「はじめる」のボタンを並べ、
-- はじめるを押したら閉じて、ロビーの画面（出撃前の画面と非公式の表記。待機中の人には待機中の表示）に進む。
-- タイトルは ReplicatedStorage.Shared.Title、表記の文言は ReplicatedStorage.Shared.Notice にある。
-- サーバーへは何も送らない（表示だけ）。
--
-- - 出撃前の画面と非公式の表記は、isOpen と changed を見て、タイトル画面を閉じるまで出さない
--   （後ろの出撃前の画面のボタンを、ゲームパッドで選べないように）
-- - はじめるは、クリック・タッチと、InputMap の Hajimeru（Enter と、ゲームパッドの A・B・X・Y のどれでも）で押す。
--   ゲームパッドのボタンは画面の選択を通さずに受けるので、入室してすぐに押せる（はじめるを選ぶ待ちは無い。#148）。
--   出している間は戦闘の操作を受け付けない（InputController）ので、押したボタンで後ろの奥義などは出ない
-- - 押して閉じた後の Ui.MENU_SWITCH_GUARD 秒は、同じボタンの入力を受けて捨てる（連打で次の画面のボタンを押さないように）
-- - ボタン表記は入力の種類で切り替える。キーボードでは Enter を、ゲームパッドでは A の絵（取れなければ A）を添え、タッチでは添えない
-- - 押した入力は InputLog に残す（どのボタンで進んだかの確認用）
-- - 窓口の ShowTitle が Player の Attribute（Title.REQUEST_ATTRIBUTE）を書き換えたら、もう一度出す（確認用）
-- - 出撃メンバーとしてステージに出ている間は出さない。出している間に出撃したら、押さずに閉じる（Title.canShow）
-- - 後ろの画面は幕で覆う。押した音は Confirm
-- - 小さい画面（スマホ横画面。Ui.isSmallScreen）では、中身を安全な範囲（トップバーとノッチの内側）の中央に置き、
--   行の間隔を詰める。それでも高さに収まらなければ、文字が読める下限とボタンが押せる大きさを下回らない範囲で縮める（Ui.fitHeight）

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InputMap = require(ReplicatedStorage.Shared.InputMap)
local Notice = require(ReplicatedStorage.Shared.Notice)
local SmallScreen = require(ReplicatedStorage.Shared.SmallScreen)
local SoundPlayer = require(ReplicatedStorage.Shared.SoundPlayer)
local Title = require(ReplicatedStorage.Shared.Title)
local InputLog = require(script.Parent.Parent.InputLog)
local PartyClient = require(script.Parent.Parent.PartyClient)
local Ui = require(script.Parent.Parent.Ui)

local TitleController = {}

-- キーとゲームパッドで「はじめる」を押す操作の名前と、押して閉じた後に同じ入力を捨てる操作の名前
local ACTION = "TitleHajimeru"
local GUARD_ACTION = "TitleHajimeruGuard"
-- はじめるのボタンの中に出す、ゲームパッドのボタンの絵の大きさ（ピクセル）
local GLYPH_SIZE = 28
-- はじめるのボタンの文言
local HAJIMERU_TEXT = "はじめる"
-- 中身の幅の上限と、画面の左右の端からの余白（ピクセル）。狭い画面（スマホの横画面）では、画面の幅に合わせて縮める
local CONTENT_WIDTH = 600
local MARGIN = 16
-- 中身の行の間隔と、表記の枠の内側の余白
local GAP = 12
local PADDING = 12
-- タイトルの行の高さ。文字は行の幅に収まるよう縮め、Ui.TextSize.Huge より大きくしない
local HEADLINE_HEIGHT = Ui.TextSize.Huge + 8
-- はじめるのボタンの大きさ
local BUTTON_WIDTH = 240
local BUTTON_HEIGHT = 52
-- 小さい画面での中身の行の間隔と、縮めてよい倍率の下限（一番小さい文字は Ui.TextSize.Body、ボタンははじめる）
local SMALL_GAP = 8
local MIN_SCALE = SmallScreen.minScale(Ui.TextSize.Body, BUTTON_HEIGHT)

type Gui = {
	screen: ScreenGui,
	backdrop: Frame,
	-- タイトル・表記・はじめるを縦に並べる中身と、その並び
	content: Frame,
	list: UIListLayout,
	hajimeru: TextButton,
	-- はじめるのボタンの右に出す、ゲームパッドの A の絵
	glyph: ImageLabel,
}

local gui: Gui? = nil
local open = false
local changedEvent = Instance.new("BindableEvent")

-- タイトル画面を開いたときと閉じたときに発火する
TitleController.changed = changedEvent.Event

-- タイトル画面を出しているか
function TitleController.isOpen(): boolean
	return open
end

-- 非公式ファンゲームかつパラレル設定である旨の表記の枠。文言はロビーの表記と同じ Notice.unofficial
local function noticeBox(order: number): Frame
	local children: { Instance } = {
		Ui.create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4) }),
		Ui.create("UIPadding", {
			PaddingTop = UDim.new(0, PADDING),
			PaddingBottom = UDim.new(0, PADDING),
			PaddingLeft = UDim.new(0, PADDING),
			PaddingRight = UDim.new(0, PADDING),
		}),
		Ui.create("UICorner", { CornerRadius = UDim.new(0, 8) }),
		Ui.text({
			Name = "Heading",
			LayoutOrder = 0,
			Size = UDim2.new(1, 0, 0, Ui.TextSize.Large),
			Font = Ui.Font.Bold,
			TextSize = Ui.TextSize.Large,
			TextColor3 = Ui.Color.Accent,
			Text = Notice.unofficial.title,
		}),
	}
	for index, line in Notice.unofficial.lines do
		table.insert(
			children,
			Ui.text({
				Name = `Line{index}`,
				LayoutOrder = index,
				Size = UDim2.fromScale(1, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				TextWrapped = true,
				Text = line,
			})
		)
	end
	return Ui.create("Frame", {
		Name = "Notice",
		LayoutOrder = order,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Ui.Color.Panel,
		BorderSizePixel = 0,
	}, children)
end

local function buildGui(): Gui
	local headline = Ui.text({
		Name = "Headline",
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, HEADLINE_HEIGHT),
		Font = Ui.Font.Heavy,
		TextScaled = true,
		TextColor3 = Ui.Color.Accent,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = Title.name.ja,
	})
	Ui.create("UITextSizeConstraint", { MaxTextSize = Ui.TextSize.Huge, Parent = headline })
	local subtitle = Ui.text({
		Name = "Subtitle",
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, Ui.TextSize.Body + 4),
		Font = Ui.Font.Bold,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = Title.name.en,
	})
	local hajimeru = Ui.button({
		Name = "Hajimeru",
		LayoutOrder = 4,
		Size = UDim2.fromOffset(BUTTON_WIDTH, BUTTON_HEIGHT),
		BackgroundColor3 = Ui.Color.GaugeFull,
		Font = Ui.Font.Heavy,
		TextSize = Ui.TextSize.Large,
		Text = HAJIMERU_TEXT,
	})
	local glyph = Ui.create("ImageLabel", {
		Name = "Glyph",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.fromOffset(GLYPH_SIZE, GLYPH_SIZE),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = hajimeru,
	}) :: ImageLabel
	local list = Ui.create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, GAP),
	})
	-- 位置と幅は applyLayout が画面の大きさに合わせて決める
	local content = Ui.create("Frame", {
		Name = "Content",
		AnchorPoint = Vector2.new(0.5, 0.5),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		ZIndex = 2,
	}, {
		Ui.create("UISizeConstraint", { MaxSize = Vector2.new(CONTENT_WIDTH, math.huge) }),
		list,
		headline,
		subtitle,
		noticeBox(3),
		hajimeru,
	})
	-- 後ろのロビーと HUD を覆う幕。クリックとタッチを後ろへ通さない
	local backdrop = Ui.create("Frame", {
		Name = "Backdrop",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
		Active = true,
		ZIndex = 1,
	})
	local screen = Ui.screenGui("Title", Ui.Layer.Title, { backdrop, content })
	screen.IgnoreGuiInset = true
	screen.Enabled = false
	return {
		screen = screen,
		backdrop = backdrop :: Frame,
		content = content :: Frame,
		list = list :: UIListLayout,
		hajimeru = hajimeru,
		glyph = glyph,
	}
end

-- 小さい画面で、中身を収める高さ（大きい画面では nil）
local contentLimit: number? = nil

-- 中身の位置と幅と行の間隔を、画面の大きさに合わせる。小さい画面では安全な範囲の中央に置き、間隔を詰める
local function applyLayout(current: Gui)
	local small = Ui.isSmallScreen()
	Ui.useSafeArea(current.screen, current.backdrop, small)
	if small then
		local size = Ui.safeAreaSize()
		local inner = SmallScreen.innerOf(size.X, size.Y)
		current.content.Position = UDim2.fromOffset(inner.x + inner.width / 2, inner.y + inner.height / 2)
		current.content.Size = UDim2.fromOffset(math.min(CONTENT_WIDTH, inner.width), 0)
		current.list.Padding = UDim.new(0, SMALL_GAP)
		contentLimit = inner.height
	else
		current.content.Position = UDim2.fromScale(0.5, 0.5)
		current.content.Size = UDim2.new(1, -2 * MARGIN, 0, 0)
		current.list.Padding = UDim.new(0, GAP)
		contentLimit = nil
	end
end

-- はじめるのボタン表記。キーボードでは Enter を、ゲームパッドでは A の絵（取れなければ A の文字）を添え、タッチでは添えない
local function refreshLabel(current: Gui)
	local kind = Ui.inputKind()
	local image = if kind == "Gamepad" then Ui.glyph(Enum.KeyCode.ButtonA) else nil
	current.glyph.Image = image or ""
	current.glyph.Visible = image ~= nil
	current.hajimeru.Text = if kind == "Touch" or image
		then HAJIMERU_TEXT
		else `{HAJIMERU_TEXT}　{Ui.label(InputMap.Hajimeru.labels, kind)}`
end

-- はじめるを押す入力（InputMap の Hajimeru のキーボードとゲームパッドの入力）
local function keyCodes(): { Enum.KeyCode }
	local result = {}
	for _, list in { InputMap.Hajimeru.keyboard, InputMap.Hajimeru.gamepad } do
		for _, input in list do
			local kind, name = InputMap.parse(input)
			local value: Enum.KeyCode? = nil
			if kind == "KeyCode" and name then
				local ok, found = pcall(function(): any
					return (Enum.KeyCode :: any)[name]
				end)
				value = if ok then found else nil
			end
			if value then
				table.insert(result, value)
			else
				warn(`TitleController: 対応表の入力 {input} は KeyCode に無い`)
			end
		end
	end
	return result
end

-- 本人が今タイトル画面を出せるか（出撃メンバーとしてステージに出ていないか）
local function canShowNow(): boolean
	local state = PartyClient.get()
	local me = PartyClient.me()
	return Title.canShow(if state then state.phase else nil, me ~= nil and not me.waiting)
end

-- 押して閉じた後、Ui.MENU_SWITCH_GUARD 秒だけ、はじめるの入力を受けて捨てる（連打した入力を次の画面に渡さない）。
-- 次の画面の操作（出撃前の画面の戻るなど。優先度 High）より先に受けるよう、優先度を上げる
local GUARD_PRIORITY = Enum.ContextActionPriority.High.Value + 10
local guardToken = 0
local function guardAfterClose()
	guardToken += 1
	local token = guardToken
	ContextActionService:BindActionAtPriority(GUARD_ACTION, function()
		return Enum.ContextActionResult.Sink
	end, false, GUARD_PRIORITY, table.unpack(keyCodes()))
	task.delay(Ui.MENU_SWITCH_GUARD, function()
		if token == guardToken then
			ContextActionService:UnbindAction(GUARD_ACTION)
		end
	end)
end

-- 閉じる。pressed なら押して閉じた（連打の入力を捨てる）
local function close(pressed: boolean)
	local current = gui
	if not open or not current then
		return
	end
	open = false
	ContextActionService:UnbindAction(ACTION)
	if pressed then
		guardAfterClose()
	end
	-- 選択を外しておき、出撃前の画面が最初のボタンを選べるようにする
	local selected = GuiService.SelectedObject
	if selected and selected:IsDescendantOf(current.screen) then
		GuiService.SelectedObject = nil
	end
	current.screen.Enabled = false
	changedEvent:Fire()
end

-- はじめるを押す。source は押した入力（記録用）
local function press(source: string)
	if not open then
		return
	end
	InputLog.note(`はじめる（{source}）`)
	SoundPlayer.playUi("Confirm")
	close(true)
end

local function openTitle()
	local current = gui
	if open or not current then
		return
	end
	open = true
	guardToken += 1
	ContextActionService:UnbindAction(GUARD_ACTION)
	refreshLabel(current)
	current.screen.Enabled = true
	ContextActionService:BindActionAtPriority(ACTION, function(_, state, input)
		if state == Enum.UserInputState.Begin then
			press(input.KeyCode.Name)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value, table.unpack(keyCodes()))
	changedEvent:Fire()
end

function TitleController.start()
	local current = buildGui()
	gui = current
	-- 小さい画面で高さに収まらなければ縮める
	local refit = Ui.fitHeight(current.content, function()
		return contentLimit, MIN_SCALE
	end)
	local function relayout()
		applyLayout(current)
		refit()
	end
	Ui.onSafeAreaChanged(relayout)
	relayout()
	current.hajimeru.Activated:Connect(function(input)
		press(if input then `ボタン {input.UserInputType.Name}` else "ボタン")
	end)
	PartyClient.changed:Connect(function()
		-- 出している間に出撃メンバーとしてステージに出たら（窓口で出し直した後に出撃したときなど）、押さずに閉じる
		if open and not canShowNow() then
			close(false)
		end
	end)
	Players.LocalPlayer:GetAttributeChangedSignal(Title.REQUEST_ATTRIBUTE):Connect(function()
		if canShowNow() then
			openTitle()
		end
	end)
	Ui.onInputKindChanged(function()
		if open then
			refreshLabel(current)
		end
	end)
	-- 入室したら、PartyState が届く前でも出す（出撃中に入った待機中の人も）
	openTitle()
end

return TitleController
