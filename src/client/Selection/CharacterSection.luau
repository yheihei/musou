--!strict
-- 出撃前の画面のキャラクターの欄。選んでいるステージのストーリーのクランの操作キャラクターを、顔・名前・武器・奥義で並べ、
-- 押すと Remotes.SelectCharacter で選ぶ。選べるか（首領、NPC、他のメンバーとの重なりなど）はサーバーが判定する。
--
-- - 選べないキャラクターは暗くして理由を添える。理由は SelectionRules.checkCharacter をクライアントでも呼んで出す
-- - 他のメンバーが選んだキャラクターには選んだ人の名前を、本人が選んだキャラクターには「選択中」を添える
-- - ステージを選ぶ前は、最初のストーリーのクランを暗くして並べる
-- - 顔は顔グラフィックの登録表（KaoGraphic）の通常の表情。登録の無いキャラクターは顔の枠を出さない

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Buki = require(ReplicatedStorage.Shared.Buki)
local Characters = require(ReplicatedStorage.Shared.Characters)
local KaoGraphic = require(ReplicatedStorage.Shared.KaoGraphic)
local RemoteSchema = require(ReplicatedStorage.Shared.RemoteSchema)
local SelectionRules = require(ReplicatedStorage.Shared.SelectionRules)
local SoundPlayer = require(ReplicatedStorage.Shared.SoundPlayer)
local Stages = require(ReplicatedStorage.Shared.Stages)
local SectionKit = require(script.Parent.SectionKit)
local Ui = require(script.Parent.Parent.Ui)

local CharacterSection = {}

-- 札の大きさと顔の大きさ（ピクセル）
local CARD_HEIGHT = 156
local CARD_GAP = 6
local FACE_SIZE = 76

-- 札に添える短い理由。載っていない理由は札には出さない（パネルの下の文で伝える）
local SHORT_REASONS: { [string]: string } = {
	Shuryo = "首領",
	NpcInStage = "NPC で登場",
	OtherClan = "別のクラン",
	NotPlayable = "選べない",
	UnknownCharacter = "選べない",
}

type Card = {
	id: string,
	button: TextButton,
	face: ImageLabel?,
	name: TextLabel,
	detail: TextLabel,
	status: TextLabel,
	stroke: UIStroke,
}

local function buildCard(character: Characters.Character, order: number, onPress: (string) -> ()): Card
	local button = Ui.button({
		Name = character.id,
		LayoutOrder = order,
		Text = "",
	})
	local image = KaoGraphic.imageOf(character.id, "Tsujo")
	local face: ImageLabel? = nil
	if image then
		face = Ui.create("ImageLabel", {
			Name = "Face",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 6),
			Size = UDim2.fromOffset(FACE_SIZE, FACE_SIZE),
			BackgroundTransparency = 1,
			Image = image,
			Parent = button,
		})
	end
	local top = FACE_SIZE + 10
	local name = Ui.text({
		Name = "CharacterName",
		Position = UDim2.fromOffset(4, top),
		Size = UDim2.new(1, -8, 0, 20),
		Font = Ui.Font.Bold,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = character.displayName,
		Parent = button,
	})
	local bukiName = if character.buki then Buki.names[character.buki] else nil
	local ougiName = if character.ougi then Characters.ougiNames[character.ougi] else nil
	local detail = Ui.text({
		Name = "Detail",
		Position = UDim2.fromOffset(4, top + 20),
		Size = UDim2.new(1, -8, 0, 32),
		TextSize = Ui.TextSize.Small,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = `{bukiName or ""}\n{ougiName or ""}`,
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
		onPress(character.id)
	end)
	return {
		id = character.id,
		button = button,
		face = face,
		name = name,
		detail = detail,
		status = status,
		stroke = button:FindFirstChildOfClass("UIStroke") :: UIStroke,
	}
end

-- ステージを選ぶ前に並べるクラン。ストーリーのある最初のクラン
local function defaultClan(): Characters.ClanId
	for _, clan in Characters.clanIds do
		if #Stages.storyOf(clan) > 0 then
			return clan
		end
	end
	return Characters.clanIds[1]
end

function CharacterSection.build(context: SectionKit.Context): SectionKit.Section
	local frame, content = SectionKit.section("Character", "キャラクター", 2)
	local hint = Ui.text({
		Name = "Hint",
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 18),
		TextSize = Ui.TextSize.Small,
		TextColor3 = Ui.Color.Accent,
		Text = "",
	})
	hint.Parent = frame
	Ui.create("UIGridLayout", {
		-- 4枚で幅ちょうどにすると端数で4枚目が次の行に回るので、間隔1つ分だけ余らせる
		CellSize = UDim2.new(0.25, -CARD_GAP, 0, CARD_HEIGHT),
		CellPadding = UDim2.fromOffset(CARD_GAP, CARD_GAP),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = content,
	})

	local function onPress(characterId: string)
		SoundPlayer.playUi("Confirm")
		context.send("SelectCharacter", characterId)
	end

	-- 並べているクランと、その札
	local shownClan: Characters.ClanId? = nil
	local cards: { Card } = {}
	local function showClan(clan: Characters.ClanId)
		if shownClan == clan then
			return
		end
		shownClan = clan
		for _, card in cards do
			card.button:Destroy()
		end
		table.clear(cards)
		for order, character in Characters.playableOf(clan) do
			local card = buildCard(character, order, onPress)
			card.button.Parent = content
			table.insert(cards, card)
		end
	end

	local function update(state: RemoteSchema.PartyState)
		local stage = if state.stage then Stages.get(state.stage) else nil
		showClan(if stage then stage.clan else defaultClan())
		local me = SectionKit.me(state)
		local requester: SelectionRules.Requester = {
			phase = state.phase,
			isLeader = SectionKit.isLeader(state),
			waiting = me ~= nil and me.waiting,
		}
		-- 他のメンバーが選んだキャラクターと、選んだ人の名前
		local ownerOf: { [string]: string } = {}
		local takenByOthers: { string } = {}
		for _, member in state.members do
			if member ~= me and member.character then
				ownerOf[member.character] = member.name
				table.insert(takenByOthers, member.character)
			end
		end
		hint.Text = if stage
			then `{Characters.clanNames[stage.clan]}のキャラクターから選ぶ`
			else "先にリーダーがステージを選ぶ"

		for _, card in cards do
			local mine = me ~= nil and me.character == card.id
			local reject = SelectionRules.checkCharacter(requester, card.id, stage, takenByOthers)
			local dimmed = reject ~= nil and not mine
			card.button.BackgroundColor3 = if dimmed then Ui.Color.Disabled else Ui.Color.Panel
			card.button.BackgroundTransparency = if dimmed then 0.35 else 0.1
			card.name.TextColor3 = if dimmed then Ui.Color.Disabled:Lerp(Ui.Color.Text, 0.5) else Ui.Color.Text
			card.detail.TextColor3 = card.name.TextColor3
			if card.face then
				card.face.ImageTransparency = if dimmed then 0.5 else 0
			end
			card.stroke.Color = if mine then Ui.Color.Selected else Ui.Color.Accent
			card.stroke.Thickness = if mine then 3 else 1
			if mine then
				card.status.Text = "選択中"
				card.status.TextColor3 = Ui.Color.Selected
			elseif ownerOf[card.id] then
				card.status.Text = `{ownerOf[card.id]} が選択`
				card.status.TextColor3 = Ui.Color.Text
			else
				card.status.Text = if reject then SHORT_REASONS[reject] or "" else ""
				card.status.TextColor3 = Ui.Color.HealthLow
			end
		end
	end

	return {
		frame = frame,
		update = update,
		firstButton = function(): GuiObject?
			return if cards[1] then cards[1].button else nil
		end,
	}
end

return CharacterSection
