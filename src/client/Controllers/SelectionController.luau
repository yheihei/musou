--!strict
-- 出撃前の画面。ロビーのフェーズで、待機中でない人に、画面の右側へ選択の欄を縦に並べて出す。
-- 上からストーリーとステージ・キャラクター・特技・秘計の欄（スクロール）、下にメンバーの準備状況と出撃ボタンの帯を置く。
-- 特技の欄からは特技ツリーの画面（Selection/TokugiWindow）を開く。
-- 選択は Remotes で送り、受け付けるかはサーバーが決める。画面は届いた PartyState（PartyClient）だけを映し、
-- 先回りして変えない。拒否の理由は SelectionRejected で届き、パネルの下に出す。
-- 欄は src/client/Selection の下にある。
--
-- - タイトル画面（TitleController）を出している間は出さない（後ろのボタンをゲームパッドで選べないように）
-- - ゲームパッドのときは、画面が開いたら最初のボタンを選ぶ（スティックと十字キーで移動、A で決定）。
--   タイトル画面を閉じた直後は Ui.MENU_SWITCH_GUARD 秒あけ、A を離してから選ぶ（連打と長押しで最初のボタンを押さないように）
-- - 欄のステップ（SectionKit.Step）を上から並べ、決定して選択が通ったら選ぶボタンを次の欄へ進める
--   （ストーリー → ステージ → キャラクター → 秘計 → 出撃。特技は飛ばす）。B（InputMap の Modoru）で前の欄へ戻し、
--   Y（ShutsugekiHe）で出撃ボタンへ移す。どちらも出している間だけ割り当てる（#131）
-- - 見出しの右に、今の入力の種類の決定・戻る・出撃への操作を出す（MenuHint。タッチでは出さない）
-- - 拒否の音は Cancel。ゲームパッドやキーの操作で選んでいるボタンが移ったら Cursor を鳴らす
-- - 小さい画面（スマホ横画面。Ui.isSmallScreen）では、文字とボタンを縮めずに、ロビーの右に高さいっぱいで置く
--   （左上の非公式の表記と横に並べる。ReplicatedStorage.Shared.SmallScreen の lobbyOf）。見出しを詰め、拒否の理由は
--   見出しに重ねて出して、その分だけ欄のスクロールを広くする。HUD はロビーでは出さない（HUDController）

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InputMap = require(ReplicatedStorage.Shared.InputMap)
local RejectMessage = require(ReplicatedStorage.Shared.RejectMessage)
local RemoteSchema = require(ReplicatedStorage.Shared.RemoteSchema)
local SmallScreen = require(ReplicatedStorage.Shared.SmallScreen)
local SoundPlayer = require(ReplicatedStorage.Shared.SoundPlayer)
local InputLog = require(script.Parent.Parent.InputLog)
local MenuHint = require(script.Parent.Parent.MenuHint)
local PartyClient = require(script.Parent.Parent.PartyClient)
local Ui = require(script.Parent.Parent.Ui)
local TitleController = require(script.Parent.TitleController)
local SelectionFolder = script.Parent.Parent:WaitForChild("Selection")
local SectionKit = require(SelectionFolder:WaitForChild("SectionKit"))
local StageSection = require(SelectionFolder:WaitForChild("StageSection"))
local CharacterSection = require(SelectionFolder:WaitForChild("CharacterSection"))
local TokugiSection = require(SelectionFolder:WaitForChild("TokugiSection"))
local HikeiSection = require(SelectionFolder:WaitForChild("HikeiSection"))
local ShutsugekiBar = require(SelectionFolder:WaitForChild("ShutsugekiBar"))

local SelectionController = {}

-- 画面の端からの余白と、パネルの幅（左上の非公式の表記と重ならない幅）、
-- 右下の撃破数の表示を避ける下の余白（ピクセル）
local MARGIN = 16
local PANEL_WIDTH = 460
local BOTTOM_CLEARANCE = 112
-- 見出しと、下の拒否の理由の欄の高さ
local HEADER_HEIGHT = 40
local MESSAGE_HEIGHT = 40
-- 小さい画面の見出しの高さ（ReplicatedStorage.Shared.SmallScreen の LOBBY_HEADER_HEIGHT と同じ値）。
-- 拒否の理由は見出しに重ねるので、下の欄は設けない
local SMALL_HEADER_HEIGHT = 36
-- 拒否の理由を出しておく秒数
local MESSAGE_TIME = 4
-- 決定して送った選択が通るのを待つ秒数の上限（過ぎたら次の欄へ進めない）
local PENDING_TIME = 3
-- 戻る（B）と出撃へ（Y）の操作の名前
local MODORU_ACTION = "SelectionModoru"
local SHUTSUGEKI_HE_ACTION = "SelectionShutsugekiHe"
-- 見出しの右の操作の案内の幅（ピクセル）
local HINT_WIDTH = 260

type Gui = {
	screen: ScreenGui,
	panel: Frame,
	header: TextLabel,
	-- 見出しの右の操作の案内
	hint: MenuHint.Hint,
	body: ScrollingFrame,
	footer: Frame,
	message: TextLabel,
}

-- 決定して送り、通るのを待っている選択。step はステップの名前
type Pending = {
	step: string,
	done: (state: RemoteSchema.PartyState) -> boolean,
	at: number,
}

-- 押した入力の KeyCode の名前（記録用）
local function keyNameOf(input: InputObject?): string
	return if input then input.KeyCode.Name else "?"
end

local function buildGui(): Gui
	-- 位置と大きさは applyLayout が画面の大きさに合わせて決める
	local body = Ui.create("ScrollingFrame", {
		Name = "Body",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Ui.Color.Accent,
		Selectable = false,
	}, {
		Ui.create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 14) }),
		Ui.create("UIPadding", {
			PaddingTop = UDim.new(0, 4),
			PaddingBottom = UDim.new(0, 12),
			PaddingLeft = UDim.new(0, 12),
			PaddingRight = UDim.new(0, 16),
		}),
	})
	local footer = Ui.create("Frame", {
		Name = "Footer",
		AnchorPoint = Vector2.new(0, 1),
		Size = UDim2.new(1, 0, 0, ShutsugekiBar.HEIGHT),
		BackgroundTransparency = 1,
	})
	-- 小さい画面では見出しに重ねて出すので、文の後ろを塗れるようにし、見出しより上に重ねる
	local message = Ui.text({
		Name = "Message",
		ZIndex = 2,
		BackgroundColor3 = Ui.Color.Panel,
		Font = Ui.Font.Bold,
		TextColor3 = Ui.Color.HealthLow,
		TextWrapped = true,
		Text = "",
	})
	local header = Ui.text({
		Name = "Header",
		Position = UDim2.fromOffset(12, 0),
		Font = Ui.Font.Heavy,
		TextSize = Ui.TextSize.Title - 4,
		Text = "出撃の準備",
	})
	local hint = MenuHint.build({
		{ binding = InputMap.Kettei, text = "決定", gamepadKey = "KeyCode.ButtonA" },
		{ binding = InputMap.Modoru, text = "戻る" },
		{ binding = InputMap.ShutsugekiHe, text = "出撃へ" },
	})
	hint.frame.AnchorPoint = Vector2.new(1, 0.5)
	hint.frame.Size = UDim2.fromOffset(HINT_WIDTH, 22)
	local panel = Ui.create("Frame", {
		Name = "Panel",
		BackgroundColor3 = Ui.Color.Panel,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
	}, {
		Ui.create("UICorner", { CornerRadius = UDim.new(0, 10) }),
		Ui.create("UIStroke", { Color = Ui.Color.Accent, Thickness = 1 }),
		header,
		hint.frame,
		body,
		footer,
		message,
	})
	local screen = Ui.screenGui("Selection", Ui.Layer.Selection, { panel })
	screen.Enabled = false
	return {
		screen = screen,
		panel = panel :: Frame,
		header = header,
		hint = hint,
		body = body :: ScrollingFrame,
		footer = footer :: Frame,
		message = message,
	}
end

-- パネルと、中の見出し・欄・出撃の帯・拒否の理由の位置と大きさを、画面の大きさに合わせる。small は小さい画面か
local function applyLayout(gui: Gui, small: boolean)
	local header = if small then SMALL_HEADER_HEIGHT else HEADER_HEIGHT
	local message = if small then 0 else MESSAGE_HEIGHT
	if small then
		-- ロビーの右に高さいっぱいで置く（左上の非公式の表記と並べる）
		local size = Ui.safeAreaSize()
		local rect = SmallScreen.lobbyOf(size.X, size.Y).panel
		gui.panel.AnchorPoint = Vector2.zero
		gui.panel.Position = UDim2.fromOffset(rect.x, rect.y)
		gui.panel.Size = UDim2.fromOffset(rect.width, rect.height)
		-- 拒否の理由は見出しに重ねる。長い文は折り返して下へ伸びる
		gui.message.AnchorPoint = Vector2.zero
		gui.message.Position = UDim2.fromOffset(12, 0)
		gui.message.Size = UDim2.new(1, -24, 0, header)
		gui.message.AutomaticSize = Enum.AutomaticSize.Y
	else
		-- 画面の右側。右下の撃破数の表示を避けて下をあける
		gui.panel.AnchorPoint = Vector2.new(1, 0)
		gui.panel.Position = UDim2.new(1, -MARGIN, 0, MARGIN)
		gui.panel.Size = UDim2.new(0, PANEL_WIDTH, 1, -(MARGIN + BOTTOM_CLEARANCE))
		gui.message.AnchorPoint = Vector2.new(0, 1)
		gui.message.Position = UDim2.new(0, 12, 1, -6)
		gui.message.Size = UDim2.new(1, -24, 0, MESSAGE_HEIGHT - 8)
		gui.message.AutomaticSize = Enum.AutomaticSize.None
	end
	gui.header.Size = UDim2.new(1, -24, 0, header)
	gui.hint.frame.Position = UDim2.new(1, -12, 0, header / 2)
	gui.body.Position = UDim2.fromOffset(0, header)
	gui.body.Size = UDim2.new(1, 0, 1, -(header + ShutsugekiBar.HEIGHT + message))
	gui.footer.Position = UDim2.new(0, 0, 1, -message)
	-- 見出しに重ねた拒否の理由は、出している間だけ後ろを塗って見出しを隠す
	gui.message.BackgroundTransparency = if small and gui.message.Text ~= "" then 0 else 1
end

function SelectionController.start()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local gui = buildGui()
	local small = Ui.isSmallScreen()
	applyLayout(gui, small)
	Ui.onSafeAreaChanged(function()
		small = Ui.isSmallScreen()
		applyLayout(gui, small)
	end)
	gui.message:GetPropertyChangedSignal("Text"):Connect(function()
		gui.message.BackgroundTransparency = if small and gui.message.Text ~= "" then 0 else 1
	end)

	-- 拒否の理由を出す。続けて届いたら新しい方を出し、古い方の消す予定は取り消す
	local messageToken = 0
	local function showMessage(text: string)
		messageToken += 1
		local token = messageToken
		gui.message.Text = text
		task.delay(MESSAGE_TIME, function()
			if messageToken == token then
				gui.message.Text = ""
			end
		end)
	end

	-- 決定して送り、通るのを待っている選択と、通ったら次の欄へ進める関数（後で決める）
	local pending: Pending? = nil
	local advancePending: (state: RemoteSchema.PartyState) -> () = function() end
	local context: SectionKit.Context = {
		send = function(remoteName: string, ...: any)
			local remote = remotes:FindFirstChild(remoteName)
			if remote and remote:IsA("RemoteEvent") then
				remote:FireServer(...)
			end
		end,
		notify = showMessage,
		pressed = function(step: string, done: (state: RemoteSchema.PartyState) -> boolean)
			local next: Pending = { step = step, done = done, at = os.clock() }
			pending = next
			-- 選んでいるものをもう一度決めたときは PartyState が変わらず届かないので、今の PartyState でも確かめる
			task.defer(function()
				local state = PartyClient.get()
				if pending == next and state then
					advancePending(state)
				end
			end)
		end,
	}
	local bar = ShutsugekiBar.build(context)
	bar.frame.Parent = gui.footer
	local sections: { SectionKit.Section } = {
		StageSection.build(context),
		CharacterSection.build(context),
		TokugiSection.build(context),
		HikeiSection.build(context),
		bar,
	}
	for _, section in sections do
		if section ~= bar then
			section.frame.Parent = gui.body
		end
	end

	local function firstButton(): GuiObject?
		for _, section in sections do
			local button = section.firstButton()
			if button then
				return button
			end
		end
		return nil
	end

	-- 欄のステップを上から順に並べたもの
	local steps: { SectionKit.Step } = {}
	for _, section in sections do
		for _, step in section.steps do
			table.insert(steps, step)
		end
	end

	-- 今選んでいるボタンのステップの番号。この画面のボタンを選んでいなければ nil
	local function currentStep(): number?
		local selected = GuiService.SelectedObject
		if not selected or not selected:IsDescendantOf(gui.screen) then
			return nil
		end
		for index, step in steps do
			if step.owns(selected) then
				return index
			end
		end
		return nil
	end

	-- from の番号から direction（1 か -1）の向きにたどり、選ぶボタンのある最初のステップのボタン。飛ばす欄は飛ばす
	local function stepButton(from: number, direction: number): GuiObject?
		local index = from + direction
		while steps[index] do
			local step = steps[index]
			if not step.optional then
				local button = step.focus()
				if button then
					return button
				end
			end
			index += direction
		end
		return nil
	end

	local function indexOf(name: string): number?
		for index, step in steps do
			if step.name == name then
				return index
			end
		end
		return nil
	end

	-- ゲームパッドで選ぶボタンを移す。ゲームパッドで、この画面のボタンを選んでいるか何も選んでいないときだけ。
	-- 入室直後（Ui.canSelectNow でない間）は選ばない（Studio が落ちるのを避ける）
	local function focusTo(button: GuiObject?)
		if not button or Ui.inputKind() ~= "Gamepad" or not gui.screen.Enabled or not Ui.canSelectNow() then
			return
		end
		local selected = GuiService.SelectedObject
		if selected and not selected:IsDescendantOf(gui.screen) then
			return
		end
		GuiService.SelectedObject = button
	end

	-- 決定して送った選択が通ったら、選ぶボタンを次の欄へ進める
	function advancePending(state: RemoteSchema.PartyState)
		local current = pending
		if not current then
			return
		end
		if os.clock() - current.at > PENDING_TIME then
			pending = nil
			return
		end
		if not current.done(state) then
			return
		end
		pending = nil
		local index = indexOf(current.step)
		if index then
			focusTo(stepButton(index, 1))
		end
	end

	-- 戻る（B）。選ぶボタンを前の欄へ戻す。この画面のボタンを選んでいなければ最初のボタンを選ぶ
	local function modoru()
		local index = currentStep()
		if not index then
			focusTo(firstButton())
			return
		end
		local target = stepButton(index, -1)
		if target then
			SoundPlayer.playUi("Cursor")
			focusTo(target)
		end
	end

	-- 出撃へ（Y）。選ぶボタンを出撃ボタンへ移す
	local function shutsugekiHe()
		local index = indexOf("Shutsugeki")
		local step = if index then steps[index] else nil
		local target = if step then step.focus() else nil
		if target and GuiService.SelectedObject ~= target then
			SoundPlayer.playUi("Cursor")
			focusTo(target)
		end
	end

	-- 戻ると出撃へを、画面を出している間だけ割り当てる。特技ツリーの窓（LobbyWindow）は、より高い優先度で戻るを受ける
	local bound = false
	local function bindMenu(value: boolean)
		if value == bound then
			return
		end
		bound = value
		if not value then
			ContextActionService:UnbindAction(MODORU_ACTION)
			ContextActionService:UnbindAction(SHUTSUGEKI_HE_ACTION)
			return
		end
		ContextActionService:BindActionAtPriority(MODORU_ACTION, function(_, state, input)
			if state == Enum.UserInputState.Begin then
				InputLog.note(`戻る（{keyNameOf(input)}）`)
				modoru()
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.ButtonB)
		ContextActionService:BindActionAtPriority(SHUTSUGEKI_HE_ACTION, function(_, state, input)
			if state == Enum.UserInputState.Begin then
				InputLog.note(`出撃へ（{keyNameOf(input)}）`)
				shutsugekiHe()
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.ButtonY)
	end

	-- ゲームパッドのとき、最初のボタンを選ぶ。
	-- 入室直後に選ぶと、ゲームパッドをつないだままテストプレイを始めたときに Studio が落ちる。
	-- そのため、Ui.waitForSelectable で入室から決まった秒数たち、キャラクターが出るまで待ってから選ぶ。
	-- notBefore（time() の時刻）を渡すと、その時刻まで待つ（タイトル画面を閉じた直後）。待つ間に画面を閉じたら選ばない
	local selectToken = 0
	local function selectFirstButton(notBefore: number?)
		selectToken += 1
		local token = selectToken
		task.spawn(function()
			Ui.waitForSelectable(notBefore)
			if token ~= selectToken or not gui.screen.Enabled or Ui.inputKind() ~= "Gamepad" then
				return
			end
			if not GuiService.SelectedObject then
				GuiService.SelectedObject = firstButton()
			end
		end)
	end

	local wasVisible = false
	-- タイトル画面を出していたか（閉じた直後に開いたかを見分ける）
	local titleWasOpen = TitleController.isOpen()
	local function refresh()
		local state = PartyClient.get()
		local me = PartyClient.me()
		local titleOpen = TitleController.isOpen()
		local visible = state ~= nil and state.phase == "Lobby" and me ~= nil and not me.waiting and not titleOpen
		gui.screen.Enabled = visible
		bindMenu(visible)
		if state and visible then
			for _, section in sections do
				section.update(state)
			end
			advancePending(state)
		end
		if visible and not wasVisible and Ui.inputKind() == "Gamepad" then
			-- タイトル画面を閉じた直後は、連打した A を受けないように少しあけてから選ぶ
			selectFirstButton(if titleWasOpen then time() + Ui.MENU_SWITCH_GUARD else nil)
		elseif not visible then
			selectToken += 1
			pending = nil
			local selected = GuiService.SelectedObject
			if selected and selected:IsDescendantOf(gui.screen) then
				GuiService.SelectedObject = nil
			end
			gui.message.Text = ""
		end
		wasVisible = visible
		titleWasOpen = titleOpen
	end

	PartyClient.changed:Connect(refresh)
	TitleController.changed:Connect(refresh)
	local rejected = remotes:WaitForChild("SelectionRejected") :: RemoteEvent
	rejected.OnClientEvent:Connect(function(reason: RemoteSchema.RejectReason)
		pending = nil
		SoundPlayer.playUi("Cancel")
		showMessage(RejectMessage.of(reason))
	end)
	Ui.onInputKindChanged(function(kind)
		if kind == "Gamepad" and gui.screen.Enabled and not GuiService.SelectedObject then
			selectFirstButton()
		end
	end)
	Ui.onSelectionMoved(gui.screen, function()
		SoundPlayer.playUi("Cursor")
	end)
	refresh()
end

return SelectionController
