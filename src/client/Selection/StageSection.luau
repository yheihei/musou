--!strict
-- 出撃前の画面のストーリーとステージの欄。上に4つのクランのストーリーを並べ、押すと Remotes.SelectStory で選ぶ。
-- 下に画面に出しているストーリーのステージを順に並べ、押すと Remotes.SelectStage で選ぶ。
-- 選べるのはリーダーだけで、リーダーが開放したステージのあるストーリーと、開放済みのステージに限る。判定はサーバーが行う。
--
-- - 画面に出すストーリーは、選んでいるストーリー、無ければリーダーが開放した最初のストーリー（SelectionRules.shownStory）
-- - リーダーが開放していないストーリーは暗くして「未開放」を、ステージがまだ無いストーリーは暗くして「準備中」を添える
-- - ストーリーを押したら SelectionRules.checkStory をクライアントでも呼び、選べなければ送らずに理由を出す
--   （暗いストーリーを押したときと、リーダー以外が押したとき）
-- - リーダーが開放していないステージは暗くして「未開放」を添える
-- - リーダーが選んでいるストーリーとステージは枠を光らせて「選択中」を添える。リーダー以外にも同じ一覧を見せる
-- - ゲームパッドで画面を開いたとき、リーダーには画面に出しているストーリーを選ぶ。リーダー以外にはこの欄を飛ばす
-- - 試験用ステージは出さない

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

-- 暗くしたストーリーに添える文。選べない理由（SelectionRules.checkStoryId）で引く
local CLOSED_LABELS: { [string]: string } = {
	StoryNotReady = "準備中",
	StoryLocked = "未開放",
}

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
		Text = `第{stage.order}ステージ　{stage.displayName}`,
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
		button = button,
		name = name,
		status = status,
		stroke = button:FindFirstChildOfClass("UIStroke") :: UIStroke,
	}
end

-- ボタンを、選べなければ暗くし、選んでいれば枠を光らせる
local function paint(button: TextButton, name: TextLabel, stroke: UIStroke, open: boolean, selected: boolean)
	button.BackgroundColor3 = if open then Ui.Color.Panel else Ui.Color.Disabled
	button.BackgroundTransparency = if open then 0.1 else 0.35
	name.TextColor3 = if open then Ui.Color.Text else Ui.Color.Disabled:Lerp(Ui.Color.Text, 0.5)
	stroke.Color = if selected then Ui.Color.Selected else Ui.Color.Accent
	stroke.Thickness = if selected then 3 else 1
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

	-- 本人がリーダーか、画面に出しているストーリー、ストーリーを押したときに選べない理由。届いた PartyState で決める
	local isLeader = false
	local shown: Characters.ClanId? = nil
	local storyRejects: { [string]: SelectionRules.Reject? } = {}

	local function onPressStory(clan: Characters.ClanId)
		local reject = storyRejects[clan]
		if reject then
			SoundPlayer.playUi("Cancel")
			context.notify(RejectMessage.of(reject))
			return
		end
		SoundPlayer.playUi("Confirm")
		context.send("SelectStory", clan)
	end
	local function onPressStage(stageId: string)
		SoundPlayer.playUi("Confirm")
		context.send("SelectStage", stageId)
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

	-- 全部のストーリーのステージを作っておき、画面に出しているストーリーのものだけを見せる
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
		storyName.Text = `{Characters.clanNames[story]}のストーリー`

		for _, item in stories do
			local closed = SelectionRules.checkStoryId(item.clan, state.unlockedStages)
			local selected = state.story == item.clan
			storyRejects[item.clan] = SelectionRules.checkStory(requester, item.clan, state.unlockedStages)
			paint(item.button, item.name, item.stroke, closed == nil, selected)
			setStatus(item.status, if closed then CLOSED_LABELS[closed] or "" else nil, selected)
		end
		for _, row in rows do
			local unlocked = table.find(state.unlockedStages, row.id) ~= nil
			local selected = state.stage == row.id
			row.button.Visible = row.clan == story
			paint(row.button, row.name, row.stroke, unlocked, selected)
			setStatus(row.status, if unlocked then nil else "未開放", selected)
		end
	end

	return {
		frame = frame,
		update = update,
		firstButton = function(): GuiObject?
			if not isLeader then
				return nil
			end
			for _, item in stories do
				if item.clan == shown then
					return item.button
				end
			end
			return if stories[1] then stories[1].button else nil
		end,
	}
end

return StageSection
