--!strict
-- 出撃前の画面のステージの欄。ストーリー（クラン）ごとにステージを順に並べ、押すと Remotes.SelectStage で選ぶ。
-- 選べるのはリーダーだけで、リーダーが開放済みのステージに限る。判定はサーバーが行う。
--
-- - リーダーが開放していないステージは暗くして「未開放」を添える
-- - リーダーが選んでいるステージは枠を光らせて「選択中」を添える。リーダー以外にも同じ一覧を見せる
-- - 試験用ステージは出さない

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Characters = require(ReplicatedStorage.Shared.Characters)
local RemoteSchema = require(ReplicatedStorage.Shared.RemoteSchema)
local SoundPlayer = require(ReplicatedStorage.Shared.SoundPlayer)
local Stages = require(ReplicatedStorage.Shared.Stages)
local SectionKit = require(script.Parent.SectionKit)
local Ui = require(script.Parent.Parent.Ui)

local StageSection = {}

local ROW_HEIGHT = 44

type Row = {
	id: string,
	button: TextButton,
	name: TextLabel,
	status: TextLabel,
	stroke: UIStroke,
}

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
		button = button,
		name = name,
		status = status,
		stroke = button:FindFirstChildOfClass("UIStroke") :: UIStroke,
	}
end

function StageSection.build(context: SectionKit.Context): SectionKit.Section
	local frame, content = SectionKit.section("Stage", "ステージ", 1)
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

	local rows: { Row } = {}
	local function onPress(stageId: string)
		SoundPlayer.playUi("Confirm")
		context.send("SelectStage", stageId)
	end
	local order = 0
	for _, clan in Characters.clanIds do
		local stages = Stages.storyOf(clan)
		if #stages == 0 then
			continue
		end
		order += 1
		Ui.text({
			Name = `{clan}Story`,
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, 20),
			Font = Ui.Font.Bold,
			TextSize = Ui.TextSize.Small,
			Text = `{Characters.clanNames[clan]}のストーリー`,
			Parent = content,
		})
		for _, stage in stages do
			order += 1
			local row = buildRow(stage, order, onPress)
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
		hint.Text = if SectionKit.isLeader(state)
			then "あなたがリーダー。挑むステージを選ぶ"
			else `リーダーの {leaderName} がステージを選ぶ`
		for _, row in rows do
			local unlocked = table.find(state.unlockedStages, row.id) ~= nil
			local selected = state.stage == row.id
			row.button.BackgroundColor3 = if unlocked then Ui.Color.Panel else Ui.Color.Disabled
			row.button.BackgroundTransparency = if unlocked then 0.1 else 0.35
			row.name.TextColor3 = if unlocked then Ui.Color.Text else Ui.Color.Disabled:Lerp(Ui.Color.Text, 0.5)
			row.stroke.Color = if selected then Ui.Color.Selected else Ui.Color.Accent
			row.stroke.Thickness = if selected then 3 else 1
			if not unlocked then
				row.status.Text = "未開放"
				row.status.TextColor3 = Ui.Color.Text
			elseif selected then
				row.status.Text = "選択中"
				row.status.TextColor3 = Ui.Color.Selected
			else
				row.status.Text = ""
			end
		end
	end

	return {
		frame = frame,
		update = update,
		firstButton = function(): GuiObject?
			return if rows[1] then rows[1].button else nil
		end,
	}
end

return StageSection
