--!strict
-- 出撃前の画面の秘計の欄。秘計8種の名前と効果を2列に並べ、押すと選ぶ・外す（Remotes.SelectHikei）。
-- 持ち込みの上限と、パーティーで重ならないかはサーバーが判定する。
--
-- - 本人が選んだ秘計は枠を光らせ、選んだ順に戦闘中のボタン（1〜3、十字キーの左・上・右）を添える
-- - 他のメンバーが選んだ秘計は暗くし、選んだ人の名前を添える
-- - ボタン表記は入力の種類（キーボードかゲームパッド）で切り替える

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Hikei = require(ReplicatedStorage.Shared.Hikei)
local InputMap = require(ReplicatedStorage.Shared.InputMap)
local RemoteSchema = require(ReplicatedStorage.Shared.RemoteSchema)
local SoundPlayer = require(ReplicatedStorage.Shared.SoundPlayer)
local SectionKit = require(script.Parent.SectionKit)
local Ui = require(script.Parent.Parent.Ui)

local HikeiSection = {}

-- 枚の大きさと間隔（ピクセル）
local CARD_HEIGHT = 84
local CARD_GAP = 8

type Card = {
	id: string,
	button: TextButton,
	name: TextLabel,
	description: TextLabel,
	badge: TextLabel,
	stroke: UIStroke,
}

-- 戦闘中に slot 番目の枚を使うボタンの表記
local function slotLabel(slot: number): string
	local binding = InputMap.Hikei[slot]
	return if binding then Ui.label(binding.labels) else tostring(slot)
end

-- 「選んだ順に 1・2・3 で使う」の案内
local function hintText(): string
	local labels = {}
	for slot = 1, Hikei.MOCHIKOMI_MAX do
		table.insert(labels, slotLabel(slot))
	end
	return `{Hikei.MOCHIKOMI_MAX}枚まで。選んだ順に、戦闘中は {table.concat(labels, "・")} で使う`
end

local function buildCard(id: string, order: number, onPress: (string) -> ()): Card
	local definition = Hikei.get(id) :: Hikei.Definition
	local name = Ui.text({
		Name = "HikeiName",
		Position = UDim2.fromOffset(10, 6),
		Size = UDim2.new(1, -20, 0, 22),
		Font = Ui.Font.Bold,
		Text = definition.displayName,
	})
	local badge = Ui.text({
		Name = "Badge",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 6),
		Size = UDim2.new(0.6, 0, 0, 22),
		Font = Ui.Font.Bold,
		TextSize = Ui.TextSize.Small,
		TextColor3 = Ui.Color.Selected,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "",
	})
	local description = Ui.text({
		Name = "Description",
		Position = UDim2.fromOffset(10, 30),
		Size = UDim2.new(1, -20, 1, -34),
		TextSize = Ui.TextSize.Small,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = Hikei.describe(id),
	})
	local button = Ui.button({
		Name = id,
		LayoutOrder = order,
		Text = "",
	})
	name.Parent = button
	badge.Parent = button
	description.Parent = button
	button.Activated:Connect(function()
		onPress(id)
	end)
	return {
		id = id,
		button = button,
		name = name,
		description = description,
		badge = badge,
		stroke = button:FindFirstChildOfClass("UIStroke") :: UIStroke,
	}
end

function HikeiSection.build(context: SectionKit.Context): SectionKit.Section
	local frame, content = SectionKit.section("Hikei", "秘計", 3)
	local hint = Ui.text({
		Name = "Hint",
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 18),
		TextSize = Ui.TextSize.Small,
		TextColor3 = Ui.Color.Accent,
		Text = hintText(),
	})
	hint.Parent = frame
	Ui.create("UIGridLayout", {
		CellSize = UDim2.new(0.5, -CARD_GAP / 2, 0, CARD_HEIGHT),
		CellPadding = UDim2.fromOffset(CARD_GAP, CARD_GAP),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = content,
	})

	-- 本人が選んだ順の秘計。押したときに選ぶか外すかを決めるのに使う
	local mine: { string } = {}
	local cards: { Card } = {}
	local function onPress(id: string)
		local selected = table.find(mine, id) == nil
		SoundPlayer.playUi(if selected then "Confirm" else "Cancel")
		context.send("SelectHikei", id, selected)
	end
	for order, id in Hikei.selectable() do
		local card = buildCard(id, order, onPress)
		card.button.Parent = content
		table.insert(cards, card)
	end

	local lastState: RemoteSchema.PartyState? = nil
	local function update(state: RemoteSchema.PartyState)
		lastState = state
		local me = SectionKit.me(state)
		mine = if me then me.hikei else {}
		-- 他のメンバーが選んだ秘計と、選んだ人の名前
		local ownerOf: { [string]: string } = {}
		for _, member in state.members do
			if member.userId ~= Players.LocalPlayer.UserId then
				for _, id in member.hikei do
					ownerOf[id] = member.name
				end
			end
		end
		for _, card in cards do
			local slot = table.find(mine, card.id)
			local owner = ownerOf[card.id]
			local dimmed = owner ~= nil
			card.button.BackgroundColor3 = if dimmed then Ui.Color.Disabled else Ui.Color.Panel
			card.button.BackgroundTransparency = if dimmed then 0.35 else 0.1
			card.name.TextColor3 = if dimmed then Ui.Color.Disabled:Lerp(Ui.Color.Text, 0.5) else Ui.Color.Text
			card.description.TextColor3 = card.name.TextColor3
			card.stroke.Color = if slot then Ui.Color.Selected else Ui.Color.Accent
			card.stroke.Thickness = if slot then 3 else 1
			if slot then
				card.badge.Text = `{slot}枚目  {slotLabel(slot)}`
				card.badge.TextColor3 = Ui.Color.Selected
			elseif owner then
				card.badge.Text = `{owner} が選択`
				card.badge.TextColor3 = Ui.Color.Text
			else
				card.badge.Text = ""
			end
		end
	end

	Ui.onInputKindChanged(function()
		hint.Text = hintText()
		if lastState then
			update(lastState)
		end
	end)

	return {
		frame = frame,
		update = update,
		firstButton = function(): GuiObject?
			return if cards[1] then cards[1].button else nil
		end,
	}
end

return HikeiSection
