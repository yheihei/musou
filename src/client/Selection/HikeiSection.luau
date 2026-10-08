--!strict
-- 出撃前の画面の秘計の欄。系統（Jukurendo.keitoList の順）ごとに、見出し（系統の名前と熟練度を上げる戦い方、熟練度、
-- 次に覚える秘計まであといくつか）と、本人が覚えた秘計の名前と効果を2列に並べ、押すと選ぶ・外す（Remotes.SelectHikei）。
-- 覚えていない秘計は出さない（次に覚える秘計の名前は見出しに出す）。熟練度と覚えた秘計は JukurendoClient から読む。
-- 覚えた秘計か、持ち込みの上限、パーティーで重ならないかはサーバーが判定する。
--
-- - 系統の中の秘計は、覚える順（Config.luau の Jukurendo 節の並び）に並べる
-- - 本人が選んだ秘計は枠を光らせ、選んだ順に戦闘中のボタン（1〜3、十字キーの左・上・右）を添える
-- - 他のメンバーが選んだ秘計は暗くし、選んだ人の名前を添える
-- - 熟練度の記録が届くまでは、読み込んでいる旨だけを出す。保存済みの記録を読めなかったときは、その旨を添える
-- - ボタン表記は入力の種類（キーボードかゲームパッド）で切り替える

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Hikei = require(ReplicatedStorage.Shared.Hikei)
local InputMap = require(ReplicatedStorage.Shared.InputMap)
local Jukurendo = require(ReplicatedStorage.Shared.Jukurendo)
local RemoteSchema = require(ReplicatedStorage.Shared.RemoteSchema)
local SoundPlayer = require(ReplicatedStorage.Shared.SoundPlayer)
local JukurendoClient = require(script.Parent.Parent.JukurendoClient)
local SectionKit = require(script.Parent.SectionKit)
local Ui = require(script.Parent.Parent.Ui)

local HikeiSection = {}

-- 枚の大きさと間隔、系統の見出しの高さ（ピクセル）
local CARD_HEIGHT = 84
local CARD_GAP = 8
local KEITO_HEADER_HEIGHT = 20

type Card = {
	id: string,
	button: TextButton,
	name: TextLabel,
	description: TextLabel,
	badge: TextLabel,
	stroke: UIStroke,
}

-- 系統1つの見出しと枚
type KeitoBlock = {
	keito: string,
	frame: Frame,
	progress: TextLabel,
	cards: { Card },
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

-- 系統1つの見出しと、系統の秘計の枚（覚える順）を作る
local function buildKeito(keito: string, order: number, onPress: (string) -> ()): KeitoBlock
	local title = Ui.text({
		Name = "KeitoName",
		Size = UDim2.fromScale(0.45, 1),
		Font = Ui.Font.Bold,
		TextSize = Ui.TextSize.Small,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = Jukurendo.titleOf(keito),
	})
	local progress = Ui.text({
		Name = "Progress",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromScale(0.55, 1),
		TextSize = Ui.TextSize.Small,
		TextColor3 = Ui.Color.Accent,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = "",
	})
	local header = Ui.create("Frame", {
		Name = "Header",
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, KEITO_HEADER_HEIGHT),
		BackgroundTransparency = 1,
	}, { title, progress })
	local grid = Ui.create("Frame", {
		Name = "Cards",
		LayoutOrder = 2,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, {
		Ui.create("UIGridLayout", {
			CellSize = UDim2.new(0.5, -CARD_GAP / 2, 0, CARD_HEIGHT),
			CellPadding = UDim2.fromOffset(CARD_GAP, CARD_GAP),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local frame = Ui.create("Frame", {
		Name = keito,
		LayoutOrder = order,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, {
		Ui.create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4) }),
		header,
		grid,
	})
	local cards: { Card } = {}
	local def = Jukurendo.keitoDef(keito)
	if def then
		for index, entry in def.Hikei do
			if Hikei.get(entry.Id) then
				local card = buildCard(entry.Id, index, onPress)
				card.button.Parent = grid
				table.insert(cards, card)
			end
		end
	end
	return { keito = keito, frame = frame :: Frame, progress = progress, cards = cards }
end

function HikeiSection.build(context: SectionKit.Context): SectionKit.Section
	local frame, content = SectionKit.section("Hikei", "秘計", 4)
	local hint = Ui.text({
		Name = "Hint",
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 18),
		TextSize = Ui.TextSize.Small,
		TextColor3 = Ui.Color.Accent,
		Text = hintText(),
	})
	hint.Parent = frame
	Ui.create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 10),
		Parent = content,
	})
	-- 熟練度の記録を読み込んでいる間と、読めなかったときの文
	local status = Ui.text({
		Name = "Status",
		LayoutOrder = 0,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextSize = Ui.TextSize.Small,
		TextWrapped = true,
		Text = "",
		Parent = content,
	})

	-- 本人が選んだ順の秘計。押したときに選ぶか外すかを決めるのに使う
	local mine: { string } = {}
	local blocks: { KeitoBlock } = {}
	local function onPress(id: string)
		local selected = table.find(mine, id) == nil
		SoundPlayer.playUi(if selected then "Confirm" else "Cancel")
		context.send("SelectHikei", id, selected)
	end
	for order, keito in Jukurendo.keitoList do
		local block = buildKeito(keito, order, onPress)
		block.frame.Parent = content
		table.insert(blocks, block)
	end

	local lastState: RemoteSchema.PartyState? = nil
	local function render()
		local received = JukurendoClient.get()
		local data = if received then received.data else Jukurendo.new()
		local learned = if received then Jukurendo.learned(data) else {}
		if not received then
			status.Text = "秘計の記録を読み込んでいます"
		elseif not received.loaded then
			status.Text =
				"秘計の記録を読み込めませんでした。覚えた秘計の一部が出ていないことがあります"
		end
		status.Visible = received == nil or not received.loaded
		local me = if lastState then SectionKit.me(lastState) else nil
		mine = if me then me.hikei else {}
		-- 他のメンバーが選んだ秘計と、選んだ人の名前
		local ownerOf: { [string]: string } = {}
		if lastState then
			for _, member in lastState.members do
				if member.userId ~= Players.LocalPlayer.UserId then
					for _, id in member.hikei do
						ownerOf[id] = member.name
					end
				end
			end
		end
		for _, block in blocks do
			block.frame.Visible = received ~= nil
			block.progress.Text = Jukurendo.progressOf(data, block.keito)
			for _, card in block.cards do
				card.button.Visible = table.find(learned, card.id) ~= nil
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
	end

	JukurendoClient.changed:Connect(render)
	Ui.onInputKindChanged(function()
		hint.Text = hintText()
		render()
	end)
	render()

	return {
		frame = frame,
		update = function(state: RemoteSchema.PartyState)
			lastState = state
			render()
		end,
		firstButton = function(): GuiObject?
			for _, block in blocks do
				for _, card in block.cards do
					if block.frame.Visible and card.button.Visible then
						return card.button
					end
				end
			end
			return nil
		end,
	}
end

return HikeiSection
