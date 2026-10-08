--!strict
-- ステージのリザルト画面。Remotes.StageResult を受けて、画面の中央に勝敗と理由、経過時間、全員の撃破数、
-- 本人が得た巻物、本人の上がった熟練度と新しく覚えた秘計、本人が新しく開放したステージを出す。
-- 文は ReplicatedStorage.Shared.ResultMessage にある。
-- 次の行動はリーダーだけが選び、Remotes.Retry か Remotes.ReturnToLobby を送る。受け付けるかはサーバーが決める。
--
-- - 出すのは StageResult を受けた人（出撃して残っているメンバー）だけ。待機中の人には届かないので出さない
-- - PartyState（PartyClient）のフェーズがリザルトでなくなったら閉じ、受けた結果を捨てる
-- - 後ろの画面は幕で暗くする。本人が開放したステージが無ければ、開放したステージの欄は出さない
-- - 得た巻物は、決着したときに使っていたキャラクターと数を出す。0 本でも出す
-- - 熟練度は系統ごと（Jukurendo.keitoList の順）に、上がった分と上げた戦い方の数を出す。上がらなかった系統も +0 で出す
-- - 新しく覚えた秘計が無ければ、その欄は出さない
-- - リーダーには「もう一度挑む」と「ロビーへ戻る」のボタン、ほかの人には待ちの文を出す。
--   リーダーかは PartyState が届くたびに確かめ直す（リザルトの途中でリーダーが抜けたら、次のリーダーにボタンを出す）
-- - 押したら両方のボタンを止めて二重に送らない。PENDING_TIME 秒たってもリザルトのままなら（受け付けられなかったら）戻す
-- - ゲームパッドのときは、画面が開いたら最初のボタンを選ぶ（スティックで左右に移動、A で決定）。
--   押したら選択を外し、ロビーに戻ったときに出撃前の画面が最初のボタンを選べるようにする
-- - 押した音は Confirm。ゲームパッドやキーの操作で選んでいるボタンが移ったら Cursor を鳴らす
-- - 中身が画面の高さに収まらなければ、パネルの中をスクロールする（applyLayout）。
--   小さい画面（スマホ横画面。Ui.isSmallScreen）では、文字とボタンを縮めずに、パネルを安全な範囲（トップバーとノッチの内側）
--   に置き、勝敗の見出しと余白を詰め、ボタンの帯をパネルの下に出す（スクロールしてもいつも押せる。
--   ReplicatedStorage.Shared.SmallScreen の resultOf）

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Jukurendo = require(ReplicatedStorage.Shared.Jukurendo)
local RemoteSchema = require(ReplicatedStorage.Shared.RemoteSchema)
local ResultMessage = require(ReplicatedStorage.Shared.ResultMessage)
local SmallScreen = require(ReplicatedStorage.Shared.SmallScreen)
local SoundPlayer = require(ReplicatedStorage.Shared.SoundPlayer)
local PartyClient = require(script.Parent.Parent.PartyClient)
local Ui = require(script.Parent.Parent.Ui)

local ResultController = {}

-- パネルの幅と内側の余白、行の高さ（熟練度は小さい文字の詰めた行）、ボタンの大きさと間隔（ピクセル）
local PANEL_WIDTH = 520
local PADDING = 20
local ROW_HEIGHT = 28
local SMALL_ROW_HEIGHT = 22
local BUTTON_WIDTH = 200
local BUTTON_HEIGHT = 52
local BUTTON_GAP = 16
-- 勝敗の見出しの文字の大きさ
local HEADLINE_SIZE = 64
-- 小さい画面での、勝敗の見出しの文字の大きさと、パネルの内側の余白
local SMALL_HEADLINE_SIZE = 44
local SMALL_PADDING = 12
-- 大きい画面で、中身が画面の高さに収まらないときに、パネルの上下に残す余白
local SCREEN_MARGIN = 16
-- 後ろの画面を暗くする幕の透明度
local BACKDROP_TRANSPARENCY = 0.45
-- 押した後、フェーズが変わらなければボタンを戻すまでの秒数
local PENDING_TIME = 3
-- ゲームパッドで最初のボタンを選ぶまでの、画面を開いてからの秒数（戦闘中に押していた A で押してしまわないように）
local SELECT_AFTER_OPEN = 1

type Gui = {
	screen: ScreenGui,
	backdrop: Frame,
	-- 結果のパネル。中身が収まらなければスクロールする
	panel: ScrollingFrame,
	-- パネルの中身を並べる UIListLayout と、内側の余白
	list: UIListLayout,
	padding: UIPadding,
	-- ボタンの帯と、小さい画面で帯をパネルの下に出す枠
	footer: Frame,
	dock: Frame,
	headline: TextLabel,
	reason: TextLabel,
	elapsed: TextLabel,
	-- 撃破数の行を入れる Frame
	members: Frame,
	-- 得た巻物の行を入れる Frame
	makimonoList: Frame,
	-- 上がった熟練度の行を入れる Frame
	jukurendoList: Frame,
	-- 新しく覚えた秘計の欄と、その行を入れる Frame
	learned: Frame,
	learnedList: Frame,
	-- 開放したステージの欄と、その行を入れる Frame
	unlocked: Frame,
	unlockedList: Frame,
	retry: TextButton,
	returnToLobby: TextButton,
	waiting: TextLabel,
}

-- 見出しの付いた欄。欄の枠と、行を入れる Frame を返す。order は欄の並び順
local function section(name: string, title: string, order: number): (Frame, Frame)
	local list = Ui.create("Frame", {
		Name = "List",
		LayoutOrder = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, {
		Ui.create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) }),
	})
	local frame = Ui.create("Frame", {
		Name = name,
		LayoutOrder = order,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, {
		Ui.create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4) }),
		Ui.text({
			Name = "Title",
			LayoutOrder = 0,
			Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
			Font = Ui.Font.Heavy,
			TextSize = Ui.TextSize.Large,
			TextColor3 = Ui.Color.Accent,
			Text = title,
		}),
		list,
	})
	return frame :: Frame, list :: Frame
end

-- 撃破数の1行。本人の行は色と背景で目立たせる
local function memberRow(index: number, member: RemoteSchema.MemberResult, isMe: boolean): Frame
	local color = if isMe then Ui.Color.Selected else Ui.Color.Text
	local row = Ui.create("Frame", {
		Name = `Member{index}`,
		LayoutOrder = index,
		Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
		BackgroundColor3 = Ui.Color.Selected,
		BackgroundTransparency = if isMe then 0.82 else 1,
		BorderSizePixel = 0,
	}, {
		Ui.create("UICorner", { CornerRadius = UDim.new(0, 6) }),
		Ui.text({
			Name = "MemberName",
			Position = UDim2.fromOffset(10, 0),
			Size = UDim2.new(1, -130, 1, 0),
			Font = if isMe then Ui.Font.Heavy else Ui.Font.Bold,
			TextColor3 = color,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = member.name,
		}),
		Ui.text({
			Name = "Gekihasu",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -10, 0, 0),
			Size = UDim2.new(0, 110, 1, 0),
			Font = Ui.Font.Heavy,
			TextColor3 = color,
			TextXAlignment = Enum.TextXAlignment.Right,
			Text = tostring(member.gekihasu),
		}),
	})
	return row :: Frame
end

-- 開放したステージの1行
local function stageRow(index: number, stageId: string): TextLabel
	return Ui.text({
		Name = `Stage{index}`,
		LayoutOrder = index,
		Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
		Font = Ui.Font.Bold,
		Text = ResultMessage.stageName(stageId),
	})
end

local function buildGui(): Gui
	local headline = Ui.text({
		Name = "Headline",
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, HEADLINE_SIZE + 8),
		Font = Ui.Font.Heavy,
		TextSize = HEADLINE_SIZE,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.4,
		Text = "",
	})
	local reason = Ui.text({
		Name = "Reason",
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
		Font = Ui.Font.Bold,
		TextSize = Ui.TextSize.Large,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "",
	})
	local elapsed = Ui.text({
		Name = "Elapsed",
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
		TextColor3 = Ui.Color.Accent,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "",
	})
	local membersFrame, members = section("Members", "撃破数", 4)
	local makimono, makimonoList = section("Makimono", "得た巻物", 5)
	local jukurendo, jukurendoList = section("Jukurendo", "秘計の熟練度", 6)
	local learned, learnedList = section("NewlyLearned", "新しく覚えた秘計", 7)
	local unlocked, unlockedList = section("NewlyUnlocked", "新しく開放したステージ", 8)
	-- 撃破数の行の名前と頭をそろえる
	for _, list in { makimonoList, jukurendoList, learnedList, unlockedList } do
		Ui.create("UIPadding", { PaddingLeft = UDim.new(0, 10), Parent = list })
	end
	learned.Visible = false
	unlocked.Visible = false

	local retry = Ui.button({
		Name = "Retry",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(0.5, -BUTTON_GAP / 2, 0, 0),
		Size = UDim2.fromOffset(BUTTON_WIDTH, BUTTON_HEIGHT),
		Font = Ui.Font.Heavy,
		TextSize = Ui.TextSize.Large,
		Text = "もう一度挑む",
	})
	local returnToLobby = Ui.button({
		Name = "ReturnToLobby",
		Position = UDim2.new(0.5, BUTTON_GAP / 2, 0, 0),
		Size = UDim2.fromOffset(BUTTON_WIDTH, BUTTON_HEIGHT),
		Font = Ui.Font.Heavy,
		TextSize = Ui.TextSize.Large,
		Text = "ロビーへ戻る",
	})
	-- ゲームパッドの左右で2つのボタンを行き来する
	retry.NextSelectionRight = returnToLobby
	returnToLobby.NextSelectionLeft = retry
	local waiting = Ui.text({
		Name = "Waiting",
		Size = UDim2.fromScale(1, 1),
		Font = Ui.Font.Bold,
		TextColor3 = Ui.Color.Selected,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = true,
		Text = "",
	})
	local footer = Ui.create("Frame", {
		Name = "Footer",
		LayoutOrder = 9,
		Size = UDim2.new(1, 0, 0, BUTTON_HEIGHT),
		BackgroundTransparency = 1,
	}, { retry, returnToLobby, waiting })

	-- 位置と高さは applyLayout が画面の大きさと中身の高さに合わせて決める
	local panel = Ui.create("ScrollingFrame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(PANEL_WIDTH, 0),
		BackgroundColor3 = Ui.Color.Panel,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		ZIndex = 2,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Ui.Color.Accent,
		Selectable = false,
	}, {
		Ui.create("UICorner", { CornerRadius = UDim.new(0, 10) }),
		Ui.create("UIStroke", { Color = Ui.Color.Accent, Thickness = 1 }),
		Ui.create("UIPadding", {
			PaddingTop = UDim.new(0, PADDING),
			PaddingBottom = UDim.new(0, PADDING),
			PaddingLeft = UDim.new(0, PADDING),
			PaddingRight = UDim.new(0, PADDING),
		}),
		Ui.create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 10) }),
		headline,
		reason,
		elapsed,
		membersFrame,
		makimono,
		jukurendo,
		learned,
		unlocked,
		footer,
	})
	local backdrop = Ui.create("Frame", {
		Name = "Backdrop",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = BACKDROP_TRANSPARENCY,
		BorderSizePixel = 0,
		ZIndex = 1,
	})
	-- 小さい画面で、ボタンの帯をパネルの下に出す枠
	local dock = Ui.create("Frame", {
		Name = "Dock",
		BackgroundTransparency = 1,
		ZIndex = 2,
		Visible = false,
	})
	local screen = Ui.screenGui("Result", Ui.Layer.Result, { backdrop, panel, dock })
	screen.IgnoreGuiInset = true
	screen.Enabled = false
	return {
		screen = screen,
		backdrop = backdrop :: Frame,
		panel = panel :: ScrollingFrame,
		list = panel:FindFirstChildOfClass("UIListLayout") :: UIListLayout,
		padding = panel:FindFirstChildOfClass("UIPadding") :: UIPadding,
		footer = footer :: Frame,
		dock = dock :: Frame,
		headline = headline,
		reason = reason,
		elapsed = elapsed,
		members = members,
		makimonoList = makimonoList,
		jukurendoList = jukurendoList,
		learned = learned,
		learnedList = learnedList,
		unlocked = unlocked,
		unlockedList = unlockedList,
		retry = retry,
		returnToLobby = returnToLobby,
		waiting = waiting,
	}
end

-- パネルの大きさと位置を、画面の大きさと中身の高さに合わせる。中身が画面に収まらなければパネルの中をスクロールする。
-- 小さい画面では、中身を安全な範囲に置き、勝敗の見出しと余白を詰め、ボタンの帯をパネルの下の枠へ移す
local function applyLayout(gui: Gui)
	local small = Ui.isSmallScreen()
	Ui.useSafeArea(gui.screen, gui.backdrop, small)
	local padding = if small then SMALL_PADDING else PADDING
	gui.padding.PaddingTop = UDim.new(0, padding)
	gui.padding.PaddingBottom = UDim.new(0, padding)
	gui.padding.PaddingLeft = UDim.new(0, padding)
	gui.padding.PaddingRight = UDim.new(0, padding)
	local headline = if small then SMALL_HEADLINE_SIZE else HEADLINE_SIZE
	gui.headline.TextSize = headline
	gui.headline.Size = UDim2.new(1, 0, 0, headline + 8)
	gui.footer.Parent = if small then gui.dock else gui.panel
	gui.dock.Visible = small
	local content = gui.list.AbsoluteContentSize.Y + padding * 2
	if small then
		local size = Ui.safeAreaSize()
		local layout = SmallScreen.resultOf(size.X, size.Y, PANEL_WIDTH, content, BUTTON_HEIGHT)
		gui.panel.AnchorPoint = Vector2.zero
		gui.panel.Position = UDim2.fromOffset(layout.panel.x, layout.panel.y)
		gui.panel.Size = UDim2.fromOffset(layout.panel.width, layout.panel.height)
		gui.dock.Position = UDim2.fromOffset(layout.footer.x, layout.footer.y)
		gui.dock.Size = UDim2.fromOffset(layout.footer.width, layout.footer.height)
	else
		-- 画面の中央。中身が画面の高さに収まるうちは中身の高さ（スクロールしない）
		local maxHeight = gui.screen.AbsoluteSize.Y - SCREEN_MARGIN * 2
		gui.panel.AnchorPoint = Vector2.new(0.5, 0.5)
		gui.panel.Position = UDim2.fromScale(0.5, 0.5)
		gui.panel.Size = UDim2.fromOffset(PANEL_WIDTH, if maxHeight > 0 then math.min(content, maxHeight) else content)
	end
end

-- PartyState の中のリーダーの名前。リーダーがいないか、メンバーに見つからなければ nil
local function leaderNameOf(state: RemoteSchema.PartyState): string?
	for _, member in state.members do
		if member.userId == state.leader then
			return member.name
		end
	end
	return nil
end

-- 行を入れる Frame の中の行を消す（UIListLayout などは残す）
local function clearRows(list: Frame)
	for _, child in list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

-- 得た巻物の1行
local function makimonoRow(member: RemoteSchema.MemberResult): TextLabel
	return Ui.text({
		Name = "Makimono",
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
		Font = Ui.Font.Bold,
		Text = ResultMessage.makimonoOf(member.character, member.makimono),
	})
end

-- 上がった熟練度の行（系統の順）
local function jukurendoRows(member: RemoteSchema.MemberResult): { TextLabel }
	local counts = { gekihasu = member.gekihasu, seiatsusu = member.seiatsusu, kyuensu = member.kyuensu }
	local rows = {}
	for index, keito in Jukurendo.keitoList do
		table.insert(
			rows,
			Ui.text({
				Name = keito,
				LayoutOrder = index,
				Size = UDim2.new(1, 0, 0, SMALL_ROW_HEIGHT),
				TextSize = Ui.TextSize.Small,
				Font = Ui.Font.Bold,
				Text = ResultMessage.jukurendoOf(keito, member.jukurendo[keito] or 0, Jukurendo.countOf(counts, keito)),
			})
		)
	end
	return rows
end

-- 新しく覚えた秘計の1行
local function learnedRow(index: number, hikeiId: string): TextLabel
	return Ui.text({
		Name = hikeiId,
		LayoutOrder = index,
		Size = UDim2.new(1, 0, 0, SMALL_ROW_HEIGHT),
		Font = Ui.Font.Bold,
		TextColor3 = Ui.Color.Selected,
		Text = ResultMessage.hikeiName(hikeiId),
	})
end

-- 結果を画面に書く。得た巻物・熟練度・覚えた秘計・開放したステージは本人の分だけ出す
local function fill(gui: Gui, received: RemoteSchema.StageResult)
	gui.headline.Text = ResultMessage.headline(received.victory)
	gui.headline.TextColor3 = if received.victory then Ui.Color.Selected else Ui.Color.HealthLow
	gui.reason.Text = ResultMessage.reasonOf(received.reason)
	gui.elapsed.Text = `経過時間　{ResultMessage.formatElapsed(received.elapsed)}`
	clearRows(gui.members)
	clearRows(gui.makimonoList)
	clearRows(gui.jukurendoList)
	clearRows(gui.learnedList)
	clearRows(gui.unlockedList)
	local myId = Players.LocalPlayer.UserId
	local unlocked: { string } = {}
	local learned: { string } = {}
	for index, member in received.members do
		local isMe = member.userId == myId
		memberRow(index, member, isMe).Parent = gui.members
		if isMe then
			unlocked = member.newlyUnlocked
			learned = member.newlyLearned
			makimonoRow(member).Parent = gui.makimonoList
			for _, row in jukurendoRows(member) do
				row.Parent = gui.jukurendoList
			end
		end
	end
	for index, hikeiId in learned do
		learnedRow(index, hikeiId).Parent = gui.learnedList
	end
	gui.learned.Visible = #learned > 0
	for index, stageId in unlocked do
		stageRow(index, stageId).Parent = gui.unlockedList
	end
	gui.unlocked.Visible = #unlocked > 0
end

function ResultController.start()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local resultRemote = remotes:WaitForChild("StageResult") :: RemoteEvent
	local retryRemote = remotes:WaitForChild("Retry") :: RemoteEvent
	local returnRemote = remotes:WaitForChild("ReturnToLobby") :: RemoteEvent
	local gui = buildGui()
	local buttons = { gui.retry, gui.returnToLobby }
	-- 中身の高さ（結果を書いたとき）と画面の大きさが変わるたびに、パネルの大きさを決め直す
	gui.list:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		applyLayout(gui)
	end)
	Ui.onSafeAreaChanged(function()
		applyLayout(gui)
	end)
	applyLayout(gui)

	-- 受けた結果。フェーズがリザルトでなくなったら捨てる
	local result: RemoteSchema.StageResult? = nil
	local isLeader = false
	-- ボタンを押して、フェーズが変わるのを待っているか
	local pending = false
	local pendingToken = 0
	-- 画面を開いた時刻（time()）
	local openedAt = 0
	local wasVisible = false

	-- 選んでいるのがこの画面のボタンなら選択を外す
	local function clearSelection()
		local selected = GuiService.SelectedObject
		if selected and selected:IsDescendantOf(gui.screen) then
			GuiService.SelectedObject = nil
		end
	end

	-- ゲームパッドのとき、最初のボタンを選ぶ。
	-- 入室直後に選ぶと、ゲームパッドをつないだままテストプレイを始めたときに Studio が落ちる（出撃前の画面と同じ）。
	-- そのため、Ui.waitForSelectable で入室から決まった秒数たち、キャラクターが出るまで待ってから選ぶ。
	-- 画面を開いてからも SELECT_AFTER_OPEN 秒待つ。待つ間に画面を閉じたか、ボタンを押したら選ばない
	local selectToken = 0
	local function selectFirstButton()
		selectToken += 1
		local token = selectToken
		task.spawn(function()
			Ui.waitForSelectable(openedAt + SELECT_AFTER_OPEN)
			if
				token ~= selectToken
				or not gui.screen.Enabled
				or not isLeader
				or pending
				or Ui.inputKind() ~= "Gamepad"
			then
				return
			end
			if not GuiService.SelectedObject then
				GuiService.SelectedObject = gui.retry
			end
		end)
	end

	-- ボタンの見た目を、押した後の待ちに合わせる
	local function paintButtons()
		for _, button in buttons do
			button.AutoButtonColor = not pending
			button.BackgroundColor3 = if pending then Ui.Color.Disabled else Ui.Color.Panel
			button.TextColor3 = if pending then Ui.Color.Disabled:Lerp(Ui.Color.Text, 0.5) else Ui.Color.Text
		end
	end

	-- 押した後の待ちをやめ、ボタンを押せるように戻す
	local function cancelPending()
		pendingToken += 1
		if pending then
			pending = false
			paintButtons()
		end
	end

	local function press(remote: RemoteEvent)
		if pending or not gui.screen.Enabled or not isLeader then
			return
		end
		pending = true
		pendingToken += 1
		local token = pendingToken
		SoundPlayer.playUi("Confirm")
		-- 選択を外しておき、ロビーに戻ったときに出撃前の画面が最初のボタンを選べるようにする
		selectToken += 1
		clearSelection()
		paintButtons()
		remote:FireServer()
		task.delay(PENDING_TIME, function()
			if token ~= pendingToken then
				return
			end
			-- フェーズが変わらなかった（受け付けられなかった）ので、押し直せるようにする
			pending = false
			paintButtons()
			if gui.screen.Enabled and isLeader and Ui.inputKind() == "Gamepad" and not GuiService.SelectedObject then
				selectFirstButton()
			end
		end)
	end

	local function refresh()
		local state = PartyClient.get()
		local visible = result ~= nil and state ~= nil and state.phase == "Result"
		local wasLeader = isLeader
		isLeader = state ~= nil and state.leader == Players.LocalPlayer.UserId
		gui.screen.Enabled = visible
		gui.waiting.Text = ResultMessage.waitingFor(if state then leaderNameOf(state) else nil)
		gui.waiting.Visible = not isLeader
		for _, button in buttons do
			button.Visible = isLeader
		end
		if not visible or not wasVisible then
			-- 閉じたときと開いたときは、押した後の待ちを持ち越さない
			cancelPending()
		end
		if visible and not wasVisible then
			openedAt = time()
		end
		if visible and isLeader then
			if (not wasVisible or not wasLeader) and Ui.inputKind() == "Gamepad" then
				selectFirstButton()
			end
		else
			selectToken += 1
			clearSelection()
		end
		wasVisible = visible
	end

	resultRemote.OnClientEvent:Connect(function(value: unknown)
		if not ResultMessage.isResult(value) then
			warn("ResultController: ステージの結果の形が正しくない")
			return
		end
		local received = value :: RemoteSchema.StageResult
		result = received
		fill(gui, received)
		refresh()
	end)
	-- 渡される PartyState は、続けて届いたときに最新でないことがある（決着から結果までが同じフレームに届く）。
	-- 古い写しで結果を捨てないよう、最新の写しで決める
	PartyClient.changed:Connect(function()
		local state = PartyClient.get()
		if not state or state.phase ~= "Result" then
			result = nil
		end
		refresh()
	end)
	gui.retry.Activated:Connect(function()
		press(retryRemote)
	end)
	gui.returnToLobby.Activated:Connect(function()
		press(returnRemote)
	end)
	Ui.onInputKindChanged(function(kind)
		if kind == "Gamepad" and gui.screen.Enabled and isLeader and not pending and not GuiService.SelectedObject then
			selectFirstButton()
		end
	end)
	Ui.onSelectionMoved(gui.screen, function()
		SoundPlayer.playUi("Cursor")
	end)
	paintButtons()
	refresh()
end

return ResultController
