--!strict
-- タイトル画面。入室するたびに、ロビーの画面より手前に出す（保存はしない）。
-- タイトル、非公式ファンゲームかつパラレル設定である旨の表記、「はじめる」のボタンを並べ、
-- はじめるを押したら閉じて、ロビーの画面（出撃前の画面と非公式の表記。待機中の人には待機中の表示）に進む。
-- タイトルは ReplicatedStorage.Shared.Title、表記の文言は ReplicatedStorage.Shared.Notice にある。
-- サーバーへは何も送らない（表示だけ）。
--
-- - 出撃前の画面と非公式の表記は、isOpen と changed を見て、タイトル画面を閉じるまで出さない
--   （後ろの出撃前の画面のボタンを、ゲームパッドで選べないように）
-- - はじめるは、クリック・タッチ・Enter（InputMap の Hajimeru）と、ゲームパッドで選んだボタンの A で押す
-- - ゲームパッドのときは、はじめるを選ぶ。入室直後に選ぶと Studio が落ちるので、Ui.waitForSelectable で待ってから選ぶ
-- - ボタン表記は入力の種類で切り替える。キーボードとゲームパッドでは押すキーを添え、タッチでは添えない
-- - 窓口の ShowTitle が Player の Attribute（Title.REQUEST_ATTRIBUTE）を書き換えたら、もう一度出す（確認用）
-- - 出撃メンバーとしてステージに出ている間は出さない。出している間に出撃したら、押さずに閉じる（Title.canShow）
-- - 後ろの画面は幕で覆う。押した音は Confirm

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InputMap = require(ReplicatedStorage.Shared.InputMap)
local Notice = require(ReplicatedStorage.Shared.Notice)
local SoundPlayer = require(ReplicatedStorage.Shared.SoundPlayer)
local Title = require(ReplicatedStorage.Shared.Title)
local PartyClient = require(script.Parent.Parent.PartyClient)
local Ui = require(script.Parent.Parent.Ui)

local TitleController = {}

-- Enter で「はじめる」を押す操作の名前
local ACTION = "TitleHajimeru"
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

type Gui = {
	screen: ScreenGui,
	hajimeru: TextButton,
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
	local content = Ui.create("Frame", {
		Name = "Content",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -2 * MARGIN, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		ZIndex = 2,
	}, {
		Ui.create("UISizeConstraint", { MaxSize = Vector2.new(CONTENT_WIDTH, math.huge) }),
		Ui.create("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, GAP),
		}),
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
	return { screen = screen, hajimeru = hajimeru }
end

-- はじめるのボタン表記。キーボードとゲームパッドでは押すキーを添え、タッチでは添えない
local function refreshLabel(current: Gui)
	local kind = Ui.inputKind()
	current.hajimeru.Text = if kind == "Touch"
		then HAJIMERU_TEXT
		else `{HAJIMERU_TEXT}　{Ui.label(InputMap.Hajimeru.labels, kind)}`
end

-- はじめるを押すキー（InputMap の Hajimeru のキーボードの入力）
local function keyCodes(): { Enum.KeyCode }
	local result = {}
	for _, input in InputMap.Hajimeru.keyboard do
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
	return result
end

-- 本人が今タイトル画面を出せるか（出撃メンバーとしてステージに出ていないか）
local function canShowNow(): boolean
	local state = PartyClient.get()
	local me = PartyClient.me()
	return Title.canShow(if state then state.phase else nil, me ~= nil and not me.waiting)
end

-- ゲームパッドのとき、はじめるを選ぶ。入室直後は Ui.waitForSelectable で待ってから選び、待つ間に閉じたら選ばない。
-- タイトル画面の間はほかの画面のボタンを選ばせないので、ほかのボタンを選んでいても、はじめるに合わせる
local selectToken = 0
local function selectHajimeru()
	selectToken += 1
	local token = selectToken
	task.spawn(function()
		Ui.waitForSelectable()
		local current = gui
		if token ~= selectToken or not open or not current or Ui.inputKind() ~= "Gamepad" then
			return
		end
		if GuiService.SelectedObject ~= current.hajimeru then
			GuiService.SelectedObject = current.hajimeru
		end
	end)
end

local function close()
	local current = gui
	if not open or not current then
		return
	end
	open = false
	selectToken += 1
	ContextActionService:UnbindAction(ACTION)
	-- 選択を外しておき、出撃前の画面が最初のボタンを選べるようにする
	local selected = GuiService.SelectedObject
	if selected and selected:IsDescendantOf(current.screen) then
		GuiService.SelectedObject = nil
	end
	current.screen.Enabled = false
	changedEvent:Fire()
end

local function press()
	if not open then
		return
	end
	SoundPlayer.playUi("Confirm")
	close()
end

local function openTitle()
	local current = gui
	if open or not current then
		return
	end
	open = true
	refreshLabel(current)
	current.screen.Enabled = true
	ContextActionService:BindActionAtPriority(ACTION, function(_, state)
		if state == Enum.UserInputState.Begin then
			press()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value, table.unpack(keyCodes()))
	changedEvent:Fire()
	if Ui.inputKind() == "Gamepad" then
		selectHajimeru()
	end
end

function TitleController.start()
	local current = buildGui()
	gui = current
	current.hajimeru.Activated:Connect(press)
	PartyClient.changed:Connect(function()
		-- 出している間に出撃メンバーとしてステージに出たら（窓口で出し直した後に出撃したときなど）、押さずに閉じる
		if open and not canShowNow() then
			close()
		end
	end)
	Players.LocalPlayer:GetAttributeChangedSignal(Title.REQUEST_ATTRIBUTE):Connect(function()
		if canShowNow() then
			openTitle()
		end
	end)
	Ui.onInputKindChanged(function(kind)
		if not open then
			return
		end
		refreshLabel(current)
		if kind == "Gamepad" and GuiService.SelectedObject ~= current.hajimeru then
			selectHajimeru()
		end
	end)
	-- 入室したら、PartyState が届く前でも出す（出撃中に入った待機中の人も）
	openTitle()
end

return TitleController
