--!strict
-- 出撃前の画面。ロビーのフェーズで、待機中でない人に、画面の右側へ選択の欄を縦に並べて出す。
-- 上からストーリーとステージ・キャラクター・特技・秘計の欄（スクロール）、下にメンバーの準備状況と出撃ボタンの帯を置く。
-- 特技の欄からは特技ツリーの画面（Selection/TokugiWindow）を開く。
-- 選択は Remotes で送り、受け付けるかはサーバーが決める。画面は届いた PartyState（PartyClient）だけを映し、
-- 先回りして変えない。拒否の理由は SelectionRejected で届き、パネルの下に出す。
-- 欄は src/client/Selection の下にある。
--
-- - タイトル画面（TitleController）を出している間は出さない（後ろのボタンをゲームパッドで選べないように）
-- - ゲームパッドのときは、画面が開いたら最初のボタンを選ぶ（スティックと十字キーで移動、A で決定）
-- - 拒否の音は Cancel。ゲームパッドやキーの操作で選んでいるボタンが移ったら Cursor を鳴らす
-- - 小さい画面（スマホ横画面。Ui.isSmallScreen）では、文字とボタンを縮めずに、ロビーの右に高さいっぱいで置く
--   （左上の非公式の表記と横に並べる。ReplicatedStorage.Shared.SmallScreen の lobbyOf）。見出しを詰め、拒否の理由は
--   見出しに重ねて出して、その分だけ欄のスクロールを広くする。HUD はロビーでは出さない（HUDController）

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RejectMessage = require(ReplicatedStorage.Shared.RejectMessage)
local RemoteSchema = require(ReplicatedStorage.Shared.RemoteSchema)
local SmallScreen = require(ReplicatedStorage.Shared.SmallScreen)
local SoundPlayer = require(ReplicatedStorage.Shared.SoundPlayer)
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

type Gui = {
	screen: ScreenGui,
	panel: Frame,
	header: TextLabel,
	body: ScrollingFrame,
	footer: Frame,
	message: TextLabel,
}

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
	local panel = Ui.create("Frame", {
		Name = "Panel",
		BackgroundColor3 = Ui.Color.Panel,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
	}, {
		Ui.create("UICorner", { CornerRadius = UDim.new(0, 10) }),
		Ui.create("UIStroke", { Color = Ui.Color.Accent, Thickness = 1 }),
		header,
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

	local context: SectionKit.Context = {
		send = function(remoteName: string, ...: any)
			local remote = remotes:FindFirstChild(remoteName)
			if remote and remote:IsA("RemoteEvent") then
				remote:FireServer(...)
			end
		end,
		notify = showMessage,
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

	-- ゲームパッドのとき、最初のボタンを選ぶ。
	-- 入室直後に選ぶと、ゲームパッドをつないだままテストプレイを始めたときに Studio が落ちる。
	-- そのため、Ui.waitForSelectable で入室から決まった秒数たち、キャラクターが出るまで待ってから選ぶ。
	-- 待つ間に画面を閉じたら選ばない
	local selectToken = 0
	local function selectFirstButton()
		selectToken += 1
		local token = selectToken
		task.spawn(function()
			Ui.waitForSelectable()
			if token ~= selectToken or not gui.screen.Enabled or Ui.inputKind() ~= "Gamepad" then
				return
			end
			if not GuiService.SelectedObject then
				GuiService.SelectedObject = firstButton()
			end
		end)
	end

	local wasVisible = false
	local function refresh()
		local state = PartyClient.get()
		local me = PartyClient.me()
		local visible = state ~= nil
			and state.phase == "Lobby"
			and me ~= nil
			and not me.waiting
			and not TitleController.isOpen()
		gui.screen.Enabled = visible
		if state and visible then
			for _, section in sections do
				section.update(state)
			end
		end
		if visible and not wasVisible and Ui.inputKind() == "Gamepad" then
			selectFirstButton()
		elseif not visible then
			selectToken += 1
			local selected = GuiService.SelectedObject
			if selected and selected:IsDescendantOf(gui.screen) then
				GuiService.SelectedObject = nil
			end
			gui.message.Text = ""
		end
		wasVisible = visible
	end

	PartyClient.changed:Connect(refresh)
	TitleController.changed:Connect(refresh)
	local rejected = remotes:WaitForChild("SelectionRejected") :: RemoteEvent
	rejected.OnClientEvent:Connect(function(reason: RemoteSchema.RejectReason)
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
