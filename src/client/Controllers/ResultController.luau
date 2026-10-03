--!strict
-- ステージのリザルト画面。Remotes.StageResult を受けて、画面の中央に勝敗と理由、経過時間、全員の撃破数、
-- 本人が新しく開放したステージを出す。文は ReplicatedStorage.Shared.ResultMessage にある。
-- 次の行動はリーダーだけが選び、Remotes.Retry か Remotes.ReturnToLobby を送る。受け付けるかはサーバーが決める。
--
-- - 出すのは StageResult を受けた人（出撃して残っているメンバー）だけ。待機中の人には届かないので出さない
-- - PartyState（PartyClient）のフェーズがリザルトでなくなったら閉じ、受けた結果を捨てる
-- - 後ろの画面は幕で暗くする。本人が開放したステージが無ければ、開放したステージの欄は出さない
-- - リーダーには「もう一度挑む」と「ロビーへ戻る」のボタン、ほかの人には待ちの文を出す。
--   リーダーかは PartyState が届くたびに確かめ直す（リザルトの途中でリーダーが抜けたら、次のリーダーにボタンを出す）
-- - 押したら両方のボタンを止めて二重に送らない。PENDING_TIME 秒たってもリザルトのままなら（受け付けられなかったら）戻す
-- - ゲームパッドのときは、画面が開いたら最初のボタンを選ぶ（スティックで左右に移動、A で決定）。
--   押したら選択を外し、ロビーに戻ったときに出撃前の画面が最初のボタンを選べるようにする
-- - 押した音は Confirm

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteSchema = require(ReplicatedStorage.Shared.RemoteSchema)
local ResultMessage = require(ReplicatedStorage.Shared.ResultMessage)
local SoundPlayer = require(ReplicatedStorage.Shared.SoundPlayer)
local PartyClient = require(script.Parent.Parent.PartyClient)
local Ui = require(script.Parent.Parent.Ui)

local ResultController = {}

-- パネルの幅と内側の余白、行の高さ、ボタンの大きさと間隔（ピクセル）
local PANEL_WIDTH = 520
local PADDING = 20
local ROW_HEIGHT = 28
local BUTTON_WIDTH = 200
local BUTTON_HEIGHT = 52
local BUTTON_GAP = 16
-- 勝敗の見出しの文字の大きさ
local HEADLINE_SIZE = 64
-- 後ろの画面を暗くする幕の透明度
local BACKDROP_TRANSPARENCY = 0.45
-- 押した後、フェーズが変わらなければボタンを戻すまでの秒数
local PENDING_TIME = 3
-- ゲームパッドで最初のボタンを選べるようになる、入室からの秒数（time()）
local SELECT_AFTER_START = 3
-- ゲームパッドで最初のボタンを選ぶまでの、画面を開いてからの秒数（戦闘中に押していた A で押してしまわないように）
local SELECT_AFTER_OPEN = 1
-- キャラクターの Humanoid を待つ秒数の上限
local HUMANOID_TIMEOUT = 10

type Gui = {
	screen: ScreenGui,
	headline: TextLabel,
	reason: TextLabel,
	elapsed: TextLabel,
	-- 撃破数の行を入れる Frame
	members: Frame,
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
	local unlocked, unlockedList = section("NewlyUnlocked", "新しく開放したステージ", 5)
	-- 撃破数の行の名前と頭をそろえる
	Ui.create("UIPadding", { PaddingLeft = UDim.new(0, 10), Parent = unlockedList })
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
		LayoutOrder = 6,
		Size = UDim2.new(1, 0, 0, BUTTON_HEIGHT),
		BackgroundTransparency = 1,
	}, { retry, returnToLobby, waiting })

	local panel = Ui.create("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(PANEL_WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Ui.Color.Panel,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		ZIndex = 2,
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
	local screen = Ui.screenGui("Result", Ui.Layer.Result, { backdrop, panel })
	screen.IgnoreGuiInset = true
	screen.Enabled = false
	return {
		screen = screen,
		headline = headline,
		reason = reason,
		elapsed = elapsed,
		members = members,
		unlocked = unlocked,
		unlockedList = unlockedList,
		retry = retry,
		returnToLobby = returnToLobby,
		waiting = waiting,
	}
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

-- 結果を画面に書く。開放したステージは本人の分だけ出す
local function fill(gui: Gui, received: RemoteSchema.StageResult)
	gui.headline.Text = ResultMessage.headline(received.victory)
	gui.headline.TextColor3 = if received.victory then Ui.Color.Selected else Ui.Color.HealthLow
	gui.reason.Text = ResultMessage.reasonOf(received.reason)
	gui.elapsed.Text = `経過時間　{ResultMessage.formatElapsed(received.elapsed)}`
	clearRows(gui.members)
	clearRows(gui.unlockedList)
	local myId = Players.LocalPlayer.UserId
	local unlocked: { string } = {}
	for index, member in received.members do
		local isMe = member.userId == myId
		memberRow(index, member, isMe).Parent = gui.members
		if isMe then
			unlocked = member.newlyUnlocked
		end
	end
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
	-- そのため、入室から SELECT_AFTER_START 秒たち、キャラクターが出てから選ぶ。
	-- 画面を開いてからも SELECT_AFTER_OPEN 秒待つ。待つ間に画面を閉じたか、ボタンを押したら選ばない
	local selectToken = 0
	local function selectFirstButton()
		selectToken += 1
		local token = selectToken
		task.spawn(function()
			if not game:IsLoaded() then
				game.Loaded:Wait()
			end
			local player = Players.LocalPlayer
			local character = player.Character or player.CharacterAdded:Wait()
			character:WaitForChild("Humanoid", HUMANOID_TIMEOUT)
			local rest = math.max(SELECT_AFTER_START, openedAt + SELECT_AFTER_OPEN) - time()
			if rest > 0 then
				task.wait(rest)
			end
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
	paintButtons()
	refresh()
end

return ResultController
