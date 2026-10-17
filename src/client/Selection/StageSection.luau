--!strict
-- 出撃前の画面のストーリーとステージの欄。上に4つのクランのストーリーを並べ、押すと Remotes.SelectStory で選ぶ。
-- 下に画面に出しているストーリーのステージを順に並べ、押すと Remotes.SelectStage で選ぶ。
-- 選べるのはリーダーだけで、リーダーが開放したステージのあるストーリーと、開放済みのステージに限る。判定はサーバーが行う。
--
-- - 画面に出すストーリーは、選んでいるストーリー、無ければリーダーが開放した最初のストーリー（SelectionRules.shownStory）
-- - リーダーが開放していないストーリーは暗くして「未開放」を、ステージがまだ無いストーリーは暗くして「準備中」を添える
-- - ストーリーとステージを押したら SelectionRules の判定をクライアントでも呼び、選べなければ送らずに理由を出す
--   （暗いストーリーとステージを押したときと、リーダー以外が押したとき）
-- - リーダーが開放していないステージは暗くして「未開放」を、拠点と部隊の配置がまだ無いステージは暗くして「準備中」を添える。
--   準備中のステージを押すと、理由と開発確認用の試験用ステージなら出撃できることを出す（#117）
-- - ストーリーのステージの下に「開発確認用」の欄を置き、そのストーリーのクランの試験用ステージを並べる
--   （Stages.SHIKEN_ENTRY の間。完成したステージではない旨を添える）
-- - リーダーが選んでいるストーリーとステージは金色の枠と背景で「選択中」を添える（SectionKit.paintChoice）。
--   リーダー以外にも同じ一覧を見せる
-- - ゲームパッドで画面を開いたとき、リーダーには画面に出しているストーリーを選ぶ。リーダー以外にはこの欄を飛ばす。
--   ストーリーを決めたら、選ぶボタンをステージ（出撃できる最初のステージ）へ、ステージを決めたらキャラクターの欄へ進める（#131）

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Characters = require(ReplicatedStorage.Shared.Characters)
local RejectMessage = require(ReplicatedStorage.Shared.RejectMessage)
local RemoteSchema = require(ReplicatedStorage.Shared.RemoteSchema)
local SelectionRules = require(ReplicatedStorage.Shared.SelectionRules)
local SoundPlayer = require(ReplicatedStorage.Shared.SoundPlayer)
local Stages = require(ReplicatedStorage.Shared.Stages)
local SectionKit = require(script.Parent.SectionKit)
local Ui = require(script.Parent.Parent.Ui)

local StageSection = {}

-- ストーリーのボタンの高さと間隔、ステージの行の高さ（ピクセル）
local STORY_HEIGHT = 52
local STORY_GAP = 6
local ROW_HEIGHT = 44

-- 暗くしたストーリーとステージに添える文。選べない理由（SelectionRules.checkStoryId・checkStageId）で引く
local CLOSED_LABELS: { [string]: string } = {
	StoryNotReady = "準備中",
	StoryLocked = "未開放",
	StageLocked = "未開放",
	StageNotReady = "準備中",
}

-- 開発確認用の欄の見出し
local SHIKEN_TITLE = "開発確認用（完成したステージではありません）"

type Story = {
	clan: Characters.ClanId,
	button: TextButton,
	name: TextLabel,
	status: TextLabel,
	stroke: UIStroke,
}

type Row = {
	id: string,
	clan: Characters.ClanId,
	shiken: boolean,
	button: TextButton,
	name: TextLabel,
	status: TextLabel,
	stroke: UIStroke,
}

local function buildStory(clan: Characters.ClanId, order: number, onPress: (Characters.ClanId) -> ()): Story
	local button = Ui.button({
		Name = clan,
		LayoutOrder = order,
		Text = "",
	})
	local name = Ui.text({
		Name = "ClanName",
		Position = UDim2.fromOffset(4, 6),
		Size = UDim2.new(1, -8, 0, 22),
		Font = Ui.Font.Bold,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = Characters.clanNames[clan],
		Parent = button,
	})
	local status = Ui.text({
		Name = "Status",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 4, 1, -4),
		Size = UDim2.new(1, -8, 0, 16),
		Font = Ui.Font.Bold,
		TextSize = Ui.TextSize.Small,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "",
		Parent = button,
	})
	button.Activated:Connect(function()
		onPress(clan)
	end)
	return {
		clan = clan,
		button = button,
		name = name,
		status = status,
		stroke = button:FindFirstChildOfClass("UIStroke") :: UIStroke,
	}
end

local function buildRow(stage: Stages.Stage, order: number, onPress: (string) -> ()): Row
	local name = Ui.text({
		Name = "StageName",
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.new(1, -120, 1, 0),
		Font = Ui.Font.Bold,
		Text = if stage.shiken then stage.displayName else `第{stage.order}ステージ　{stage.displayName}`,
	})
	local status = Ui.text({
		Name = "Status",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 0),
		Size = UDim2.new(0, 100, 1, 0),
		Font = Ui.Font.Bold,
		TextSize = Ui.TextSize.Small,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "",
	})
	local button = Ui.button({
		Name = stage.id,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
		Text = "",
	})
	name.Parent = button
	status.Parent = button
	button.Activated:Connect(function()
		onPress(stage.id)
	end)
	return {
		id = stage.id,
		clan = stage.clan,
		shiken = stage.shiken == true,
		button = button,
		name = name,
		status = status,
		stroke = button:FindFirstChildOfClass("UIStroke") :: UIStroke,
	}
end

-- ボタンを、選べなければ暗くし、選んでいれば金色の枠と背景にする
local function paint(button: TextButton, name: TextLabel, stroke: UIStroke, open: boolean, selected: boolean)
	SectionKit.paintChoice(button, stroke, selected, not open)
	name.TextColor3 = if open or selected then Ui.Color.Text else Ui.Color.Disabled:Lerp(Ui.Color.Text, 0.5)
end

-- ボタンに添える文。暗くした理由（closed）を先に出し、無ければ選んでいるときに「選択中」
local function setStatus(status: TextLabel, closed: string?, selected: boolean)
	if closed then
		status.Text = closed
		status.TextColor3 = Ui.Color.Text
	elseif selected then
		status.Text = "選択中"
		status.TextColor3 = Ui.Color.Selected
	else
		status.Text = ""
	end
end

function StageSection.build(context: SectionKit.Context): SectionKit.Section
	local frame, content = SectionKit.section("Stage", "ストーリーとステージ", 1)
	local hint = Ui.text({
		Name = "Hint",
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 18),
		TextSize = Ui.TextSize.Small,
		TextColor3 = Ui.Color.Accent,
		Text = "",
	})
	hint.Parent = frame
	Ui.create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 6),
		Parent = content,
	})

	-- 本人がリーダーか、画面に出しているストーリー、ストーリーとステージを押したときに選べない理由、
	-- 選んでいるストーリーとステージ。届いた PartyState で決める
	local isLeader = false
	local shown: Characters.ClanId? = nil
	local storyRejects: { [string]: SelectionRules.Reject? } = {}
	local stageRejects: { [string]: SelectionRules.Reject? } = {}
	local selectedStory: Characters.ClanId? = nil
	local selectedStage: string? = nil

	local function onPressStory(clan: Characters.ClanId)
		local reject = storyRejects[clan]
		if reject then
			SoundPlayer.playUi("Cancel")
			context.notify(RejectMessage.of(reject))
			return
		end
		SoundPlayer.playUi("Confirm")
		context.send("SelectStory", clan)
		context.pressed("Story", function(state)
			return state.story == clan
		end)
	end
	local function onPressStage(stageId: string)
		local reject = stageRejects[stageId]
		if reject then
			SoundPlayer.playUi("Cancel")
			context.notify(RejectMessage.of(reject))
			return
		end
		SoundPlayer.playUi("Confirm")
		context.send("SelectStage", stageId)
		context.pressed("Stage", function(state)
			return state.stage == stageId
		end)
	end

	local storyFrame: Frame = Ui.create("Frame", {
		Name = "Stories",
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, STORY_HEIGHT),
		BackgroundTransparency = 1,
		Parent = content,
	}, {
		-- 4つで幅ちょうどにすると端数で4つ目が次の行に回るので、間隔1つ分だけ余らせる
		Ui.create("UIGridLayout", {
			CellSize = UDim2.new(0.25, -STORY_GAP, 0, STORY_HEIGHT),
			CellPadding = UDim2.fromOffset(STORY_GAP, 0),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local stories: { Story } = {}
	for order, clan in Characters.clanIds do
		local story = buildStory(clan, order, onPressStory)
		story.button.Parent = storyFrame
		table.insert(stories, story)
	end

	local storyName = Ui.text({
		Name = "StoryName",
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 20),
		Font = Ui.Font.Bold,
		TextSize = Ui.TextSize.Small,
		Text = "",
		Parent = content,
	})

	-- 全部のストーリーのステージを作っておき、画面に出しているストーリーのものだけを見せる。
	-- その下に、開発確認用の欄の見出しと試験用ステージを置く
	local rows: { Row } = {}
	local order = 2
	for _, clan in Characters.clanIds do
		for _, stage in Stages.storyOf(clan) do
			order += 1
			local row = buildRow(stage, order, onPressStage)
			row.button.Parent = content
			table.insert(rows, row)
		end
	end
	order += 1
	local shikenTitle = Ui.text({
		Name = "ShikenTitle",
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 20),
		Font = Ui.Font.Bold,
		TextSize = Ui.TextSize.Small,
		TextColor3 = Ui.Color.Accent,
		Text = SHIKEN_TITLE,
		Visible = false,
		Parent = content,
	})
	if Stages.SHIKEN_ENTRY then
		for _, clan in Characters.clanIds do
			for _, stage in Stages.shikenOf(clan) do
				order += 1
				local row = buildRow(stage, order, onPressStage)
				row.button.Parent = content
				table.insert(rows, row)
			end
		end
	end
	local storyButtons: { GuiObject } = {}
	for _, item in stories do
		table.insert(storyButtons, item.button)
	end
	local rowButtons: { GuiObject } = {}
	for _, row in rows do
		table.insert(rowButtons, row.button)
	end

	local function update(state: RemoteSchema.PartyState)
		local leaderName = "リーダー"
		for _, member in state.members do
			if member.userId == state.leader then
				leaderName = member.name
			end
		end
		isLeader = SectionKit.isLeader(state)
		hint.Text = if isLeader
			then "あなたがリーダー。ストーリーとステージを選ぶ"
			else `リーダーの {leaderName} がストーリーとステージを選ぶ`
		local me = SectionKit.me(state)
		local requester: SelectionRules.Requester = {
			phase = state.phase,
			isLeader = isLeader,
			waiting = me ~= nil and me.waiting,
		}
		local stage = if state.stage then Stages.get(state.stage) else nil
		local story = SelectionRules.shownStory(state.story, stage, state.unlockedStages)
		shown = story
		selectedStory = state.story
		selectedStage = state.stage
		storyName.Text = `{Characters.clanNames[story]}のストーリー`

		for _, item in stories do
			local closed = SelectionRules.checkStoryId(item.clan, state.unlockedStages)
			local selected = state.story == item.clan
			storyRejects[item.clan] = SelectionRules.checkStory(requester, item.clan, state.unlockedStages)
			paint(item.button, item.name, item.stroke, closed == nil, selected)
			setStatus(item.status, if closed then CLOSED_LABELS[closed] or "" else nil, selected)
		end
		local shikenShown = false
		for _, row in rows do
			local closed = SelectionRules.checkStageId(row.id, state.unlockedStages)
			local selected = state.stage == row.id
			stageRejects[row.id] = SelectionRules.checkStage(requester, row.id, state.unlockedStages)
			row.button.Visible = row.clan == story
			shikenShown = shikenShown or (row.shiken and row.button.Visible)
			paint(row.button, row.name, row.stroke, closed == nil, selected)
			setStatus(row.status, if closed then CLOSED_LABELS[closed] or "" else nil, selected)
		end
		shikenTitle.Visible = shikenShown
	end

	-- ストーリーのステップで選ぶボタン。選んでいるストーリー、無ければ画面に出しているストーリー
	local function storyFocus(): GuiObject?
		if not isLeader then
			return nil
		end
		local target = selectedStory or shown
		for _, item in stories do
			if item.clan == target then
				return item.button
			end
		end
		return if stories[1] then stories[1].button else nil
	end

	-- ステージのステップで選ぶボタン。選んでいるステージ、無ければ出撃できる最初のステージ（試験用ステージを含む）
	local function stageFocus(): GuiObject?
		if not isLeader then
			return nil
		end
		local first: GuiObject? = nil
		for _, row in rows do
			if SectionKit.isVisible(row.button) then
				if row.id == selectedStage then
					return row.button
				end
				if not first and stageRejects[row.id] == nil then
					first = row.button
				end
			end
		end
		return first
	end

	return {
		frame = frame,
		update = update,
		firstButton = storyFocus,
		steps = {
			{
				name = "Story",
				focus = storyFocus,
				owns = function(object: GuiObject): boolean
					return SectionKit.ownsAny(storyButtons, object)
				end,
			},
			{
				name = "Stage",
				focus = stageFocus,
				owns = function(object: GuiObject): boolean
					return SectionKit.ownsAny(rowButtons, object)
				end,
			},
		},
	}
end

return StageSection
