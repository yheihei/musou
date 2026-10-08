--!strict
-- 出撃前の画面から開く窓の共通部品。画面の中央に幕と窓を出し、上に見出しと閉じるボタン、その下に案内の文、
-- 中に縦にスクロールする中身、下に文の欄を置く。特技ツリーの画面（TokugiWindow）が使う。
--
-- - 開いている間は幕で後ろの画面を暗くし、後ろの画面のボタンを押せなくする。幕を押しても閉じる
-- - 開いている間は、ゲームパッドの選択を窓の中に閉じ込める（SelectionGroup と、上下左右の SelectionBehavior を Stop）。
--   ほかの画面が後ろの画面のボタンを選んだら、窓の中の最初のボタンに戻す
-- - 開いたとき、ゲームパッドなら firstButton（無ければ閉じるボタン）を選ぶ。
--   閉じたとき、開く前に選んでいたボタンがまだ見えていればそれに戻す
-- - 閉じるボタンは、マウス・タッチ・ゲームパッド（A）で押せる。閉じる音は Cancel
-- - 小さい画面（スマホ横画面。Ui.isSmallScreen）では、文字とボタンを縮めずに、窓を安全な範囲（トップバーとノッチの内側）
--   いっぱいに置き（ReplicatedStorage.Shared.SmallScreen の windowOf）、閉じるボタンを指で押せる高さにする。
--   下の文は案内の文に重ねて出し、その分だけ中身のスクロールを広くする

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SmallScreen = require(ReplicatedStorage.Shared.SmallScreen)
local SoundPlayer = require(ReplicatedStorage.Shared.SoundPlayer)
local Ui = require(script.Parent.Parent.Ui)

local LobbyWindow = {}

-- 窓の高さ（画面の高さに対する割合）と、幅の画面の幅に対する割合の上限
local HEIGHT_SCALE = 0.84
local WIDTH_SCALE = 0.94
-- 見出し・案内・下の文の欄の高さ、内側の余白、閉じるボタンの幅（ピクセル）
local HEADER_HEIGHT = 52
local HINT_HEIGHT = 44
local MESSAGE_HEIGHT = 36
local PADDING = 16
local CLOSE_WIDTH = 104
-- 小さい画面での閉じるボタンの高さ（指で押せる大きさ。Config.luau の SmallScreen 節の MinTouchSize 以上）
local SMALL_CLOSE_HEIGHT = 44
-- 後ろの画面を暗くする幕の透明度
local BACKDROP_TRANSPARENCY = 0.45
-- 下の文を出しておく秒数
local MESSAGE_TIME = 4

export type Options = {
	-- ScreenGui の名前
	name: string,
	title: string,
	-- 窓の幅の上限（ピクセル）。狭い画面では画面の幅に合わせて縮める
	width: number,
	-- ゲームパッドで開いたときに選ぶボタン。nil なら閉じるボタンを選ぶ
	firstButton: () -> GuiObject?,
}

export type Window = {
	screen: ScreenGui,
	-- 中身を入れる ScrollingFrame。子は UIListLayout で LayoutOrder の順に縦に並ぶ
	body: ScrollingFrame,
	-- 見出しの下の案内の文
	hint: TextLabel,
	open: () -> (),
	close: () -> (),
	isOpen: () -> boolean,
	setTitle: (text: string) -> (),
	-- 下の文の欄に、少しの間だけ文を出す
	showMessage: (text: string) -> (),
	-- 中身を作り直した後に呼ぶ。開いていて、ゲームパッドで何も選んでいなければ（選んでいたボタンが消えたら）最初のボタンを選ぶ
	reselect: () -> (),
}

-- 見えているか（自分と親の GuiObject がすべて Visible で、ScreenGui が Enabled）
local function isShown(object: GuiObject): boolean
	if not object:IsDescendantOf(game) then
		return false
	end
	local current: Instance? = object
	while current do
		if current:IsA("GuiObject") and not (current :: GuiObject).Visible then
			return false
		end
		if current:IsA("ScreenGui") then
			return (current :: ScreenGui).Enabled
		end
		current = current.Parent
	end
	return false
end

function LobbyWindow.build(options: Options): Window
	local title = Ui.text({
		Name = "Title",
		Position = UDim2.fromOffset(PADDING, 0),
		Size = UDim2.new(1, -(PADDING * 3 + CLOSE_WIDTH), 0, HEADER_HEIGHT),
		Font = Ui.Font.Heavy,
		TextSize = Ui.TextSize.Title - 4,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = options.title,
	})
	-- 閉じるボタン・中身・下の文の位置と大きさ、窓の位置と大きさは applyLayout が画面の大きさに合わせて決める
	local closeButton = Ui.button({
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Text = "閉じる",
	})
	local hint = Ui.text({
		Name = "Hint",
		Position = UDim2.fromOffset(PADDING, HEADER_HEIGHT),
		Size = UDim2.new(1, -PADDING * 2, 0, HINT_HEIGHT),
		TextSize = Ui.TextSize.Small,
		TextColor3 = Ui.Color.Accent,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = "",
	})
	local body: ScrollingFrame = Ui.create("ScrollingFrame", {
		Name = "Body",
		Position = UDim2.fromOffset(0, HEADER_HEIGHT + HINT_HEIGHT),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Ui.Color.Accent,
		Selectable = false,
	}, {
		Ui.create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 10) }),
		Ui.create("UIPadding", {
			PaddingTop = UDim.new(0, 4),
			PaddingBottom = UDim.new(0, 12),
			PaddingLeft = UDim.new(0, PADDING),
			PaddingRight = UDim.new(0, PADDING + 4),
		}),
	})
	-- 小さい画面では案内の文に重ねて出すので、文の後ろを塗れるようにし、案内の文より上に重ねる
	local message = Ui.text({
		Name = "Message",
		ZIndex = 2,
		BackgroundColor3 = Ui.Color.Panel,
		Font = Ui.Font.Bold,
		TextColor3 = Ui.Color.HealthLow,
		TextWrapped = true,
		Text = "",
	})
	local panel: Frame = Ui.create("Frame", {
		Name = "Window",
		BackgroundColor3 = Ui.Color.Panel,
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
		ZIndex = 2,
		-- ゲームパッドの選択を窓の中に閉じ込める
		SelectionGroup = true,
		SelectionBehaviorUp = Enum.SelectionBehavior.Stop,
		SelectionBehaviorDown = Enum.SelectionBehavior.Stop,
		SelectionBehaviorLeft = Enum.SelectionBehavior.Stop,
		SelectionBehaviorRight = Enum.SelectionBehavior.Stop,
	}, {
		Ui.create("UICorner", { CornerRadius = UDim.new(0, 10) }),
		Ui.create("UIStroke", { Color = Ui.Color.Accent, Thickness = 1 }),
		Ui.create("UISizeConstraint", { MaxSize = Vector2.new(options.width, math.huge) }),
		title,
		closeButton,
		hint,
		body,
		message,
	})
	-- 後ろの画面を暗くし、押せなくする幕。押したら閉じる
	local backdrop: TextButton = Ui.create("TextButton", {
		Name = "Backdrop",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = BACKDROP_TRANSPARENCY,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Selectable = false,
		Text = "",
		ZIndex = 1,
	})
	local screen = Ui.screenGui(options.name, Ui.Layer.LobbyWindow, { backdrop, panel })
	screen.IgnoreGuiInset = true
	screen.Enabled = false

	local small = false
	-- 小さい画面で案内の文に重ねた下の文は、出している間だけ後ろを塗って案内の文を隠す
	local function paintMessage()
		message.BackgroundTransparency = if small and message.Text ~= "" then 0 else 1
	end
	-- 窓と、閉じるボタン・中身・下の文の位置と大きさを、画面の大きさに合わせる
	local function applyLayout()
		small = Ui.isSmallScreen()
		Ui.useSafeArea(screen, backdrop, small)
		if small then
			local size = Ui.safeAreaSize()
			local rect = SmallScreen.windowOf(size.X, size.Y, options.width)
			panel.AnchorPoint = Vector2.zero
			panel.Position = UDim2.fromOffset(rect.x, rect.y)
			panel.Size = UDim2.fromOffset(rect.width, rect.height)
			closeButton.Position = UDim2.new(1, -PADDING, 0, (HEADER_HEIGHT - SMALL_CLOSE_HEIGHT) / 2)
			closeButton.Size = UDim2.fromOffset(CLOSE_WIDTH, SMALL_CLOSE_HEIGHT)
			-- 下の文は案内の文に重ねる。長い文は折り返して下へ伸びる
			message.AnchorPoint = Vector2.zero
			message.Position = UDim2.fromOffset(PADDING, HEADER_HEIGHT)
			message.Size = UDim2.new(1, -PADDING * 2, 0, HINT_HEIGHT)
			message.AutomaticSize = Enum.AutomaticSize.Y
			body.Size = UDim2.new(1, 0, 1, -(HEADER_HEIGHT + HINT_HEIGHT))
		else
			panel.AnchorPoint = Vector2.new(0.5, 0.5)
			panel.Position = UDim2.fromScale(0.5, 0.5)
			panel.Size = UDim2.fromScale(WIDTH_SCALE, HEIGHT_SCALE)
			closeButton.Position = UDim2.new(1, -PADDING, 0, 8)
			closeButton.Size = UDim2.fromOffset(CLOSE_WIDTH, HEADER_HEIGHT - 12)
			message.AnchorPoint = Vector2.new(0, 1)
			message.Position = UDim2.new(0, PADDING, 1, -4)
			message.Size = UDim2.new(1, -PADDING * 2, 0, MESSAGE_HEIGHT - 8)
			message.AutomaticSize = Enum.AutomaticSize.None
			body.Size = UDim2.new(1, 0, 1, -(HEADER_HEIGHT + HINT_HEIGHT + MESSAGE_HEIGHT))
		end
		paintMessage()
	end
	applyLayout()
	Ui.onSafeAreaChanged(applyLayout)
	message:GetPropertyChangedSignal("Text"):Connect(paintMessage)

	local opened = false
	-- 開く前に選んでいたボタン
	local previous: GuiObject? = nil
	local messageToken = 0

	local function showMessage(text: string)
		messageToken += 1
		local token = messageToken
		message.Text = text
		task.delay(MESSAGE_TIME, function()
			if messageToken == token then
				message.Text = ""
			end
		end)
	end

	local function selectFirst()
		GuiService.SelectedObject = options.firstButton() or closeButton
	end

	local function open()
		if opened then
			return
		end
		opened = true
		local selected = GuiService.SelectedObject
		previous = if selected and not selected:IsDescendantOf(screen) then selected else nil
		messageToken += 1
		message.Text = ""
		screen.Enabled = true
		-- 後ろの画面のボタンを選んだままにしない
		if Ui.inputKind() == "Gamepad" or previous then
			selectFirst()
		end
	end

	local function close()
		if not opened then
			return
		end
		opened = false
		messageToken += 1
		message.Text = ""
		screen.Enabled = false
		local selected = GuiService.SelectedObject
		if selected and selected:IsDescendantOf(screen) then
			local back = previous
			GuiService.SelectedObject = if back and Ui.inputKind() == "Gamepad" and isShown(back) then back else nil
		end
		previous = nil
	end

	closeButton.Activated:Connect(function()
		SoundPlayer.playUi("Cancel")
		close()
	end)
	backdrop.Activated:Connect(function()
		SoundPlayer.playUi("Cancel")
		close()
	end)
	-- 開いている間に、ほかの画面が後ろの画面のボタンを選んだら（ゲームパッドにつなぎ替えたときなど）、窓の中へ戻す
	local function keepSelectionInside()
		local selected = GuiService.SelectedObject
		if opened and selected and not selected:IsDescendantOf(screen) then
			selectFirst()
		end
	end
	GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(keepSelectionInside)
	Ui.onInputKindChanged(function(kind)
		if kind == "Gamepad" and opened and not GuiService.SelectedObject then
			selectFirst()
		else
			keepSelectionInside()
		end
	end)

	return {
		screen = screen,
		body = body :: ScrollingFrame,
		hint = hint,
		open = open,
		close = close,
		isOpen = function(): boolean
			return opened
		end,
		setTitle = function(text: string)
			title.Text = text
		end,
		showMessage = showMessage,
		reselect = function()
			local selected = GuiService.SelectedObject
			if opened and Ui.inputKind() == "Gamepad" and not (selected and selected:IsDescendantOf(screen)) then
				selectFirst()
			end
		end,
	}
end

return LobbyWindow
