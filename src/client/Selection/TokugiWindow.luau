--!strict
-- 特技ツリーの画面。出撃前の画面の特技の欄（TokugiSection）から開く窓（LobbyWindow）に、
-- 画面に出すキャラクター（TokugiClient.shownCharacter。選んでいるキャラクター、無ければ今のキャラクター）の特技ツリーを出す。
-- 記録は TokugiClient（Remotes.TokugiState）から読み、特技を押すと Remotes.LearnTokugi を送る。
-- 覚えられるかはサーバーが決め、画面は届いた記録だけを映す（先回りして変えない）。
--
-- - 特技は段（前提の深さ。Tokugi.depthsOf）ごとに行を分け、行の中は Config.luau の並びの順に3列で並べる
-- - 特技ごとに名前・効果・巻物の数・前提と、様子（覚えた・覚えられる・巻物が足りない・前提が足りない）を出す。
--   覚えた特技は枠を光らせ、前提の足りない特技は暗くする
-- - 見出しの下に、使える巻物と得た巻物の合計、覚えた特技の数を出す。記録を読めていなければ、その旨を出す
-- - 拒否の理由は SelectionRejected で届き、開いていれば窓の下に出す（拒否の音は出撃前の画面が鳴らす）
-- - ロビーのフェーズでなくなるか、待機中になったら閉じる

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Characters = require(ReplicatedStorage.Shared.Characters)
local RejectMessage = require(ReplicatedStorage.Shared.RejectMessage)
local RemoteSchema = require(ReplicatedStorage.Shared.RemoteSchema)
local SoundPlayer = require(ReplicatedStorage.Shared.SoundPlayer)
local Tokugi = require(ReplicatedStorage.Shared.Tokugi)
local PartyClient = require(script.Parent.Parent.PartyClient)
local TokugiClient = require(script.Parent.Parent.TokugiClient)
local Ui = require(script.Parent.Parent.Ui)
local LobbyWindow = require(script.Parent.LobbyWindow)
local SectionKit = require(script.Parent.SectionKit)

local TokugiWindow = {}

-- 窓の幅の上限、特技の札の高さと間隔、1行に並べる数（ピクセル・個）
local WINDOW_WIDTH = 760
local CARD_HEIGHT = 116
local CARD_GAP = 8
local COLUMNS = 3

-- 様子ごとに札の下に添える文と色
local STATUS_TEXTS: { [Tokugi.Status]: string } = {
	Learned = "覚えた",
	Learnable = "覚えられる",
	MakimonoShort = "巻物が足りない",
	Zentei = "前提が足りない",
}
local STATUS_COLORS: { [Tokugi.Status]: Color3 } = {
	Learned = Ui.Color.Selected,
	Learnable = Ui.Color.Health,
	MakimonoShort = Ui.Color.HealthLow,
	Zentei = Ui.Color.Disabled:Lerp(Ui.Color.Text, 0.5),
}

export type Window = {
	open: () -> (),
	close: () -> (),
	isOpen: () -> boolean,
}

type Card = {
	id: string,
	button: TextButton,
	name: TextLabel,
	effect: TextLabel,
	zentei: TextLabel,
	status: TextLabel,
	stroke: UIStroke,
}

-- 前提の文。前提の無い特技は「前提なし」
local function zenteiText(definition: Tokugi.Definition): string
	local names = {}
	for _, id in Tokugi.zenteiOf(definition) do
		table.insert(names, Tokugi.nameOf(id))
	end
	return if #names > 0 then `前提　{table.concat(names, "・")}` else "前提なし"
end

local function buildCard(definition: Tokugi.Definition, order: number, onPress: (string) -> ()): Card
	local button = Ui.button({
		Name = definition.Id,
		LayoutOrder = order,
		Text = "",
	})
	local name = Ui.text({
		Name = "TokugiName",
		Position = UDim2.fromOffset(10, 6),
		Size = UDim2.new(1, -20, 0, 22),
		Font = Ui.Font.Bold,
		Text = Tokugi.nameOf(definition.Id),
		Parent = button,
	})
	Ui.text({
		Name = "Makimono",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 6),
		Size = UDim2.new(0.5, 0, 0, 22),
		Font = Ui.Font.Bold,
		TextSize = Ui.TextSize.Small,
		TextColor3 = Ui.Color.Accent,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = `巻物 {definition.Makimono} 本`,
		Parent = button,
	})
	local effect = Ui.text({
		Name = "Effect",
		Position = UDim2.fromOffset(10, 30),
		Size = UDim2.new(1, -20, 0, 22),
		Text = Tokugi.describe(definition),
		Parent = button,
	})
	local zentei = Ui.text({
		Name = "Zentei",
		Position = UDim2.fromOffset(10, 54),
		Size = UDim2.new(1, -20, 0, 34),
		TextSize = Ui.TextSize.Small,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = zenteiText(definition),
		Parent = button,
	})
	local status = Ui.text({
		Name = "Status",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 10, 1, -6),
		Size = UDim2.new(1, -20, 0, 18),
		Font = Ui.Font.Bold,
		TextSize = Ui.TextSize.Small,
		Text = "",
		Parent = button,
	})
	button.Activated:Connect(function()
		onPress(definition.Id)
	end)
	return {
		id = definition.Id,
		button = button,
		name = name,
		effect = effect,
		zentei = zentei,
		status = status,
		stroke = button:FindFirstChildOfClass("UIStroke") :: UIStroke,
	}
end

-- 段の行。札は3列で並べ、札の少ない行は中央に寄せる
local function buildRow(depth: number): Frame
	return Ui.create("Frame", {
		Name = `Dan{depth}`,
		LayoutOrder = depth,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, {
		Ui.create("UIGridLayout", {
			-- 3枚で幅ちょうどにすると端数で3枚目が次の行に回るので、間隔1つ分だけ余らせる
			CellSize = UDim2.new(1 / COLUMNS, -CARD_GAP, 0, CARD_HEIGHT),
			CellPadding = UDim2.fromOffset(CARD_GAP, CARD_GAP),
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
end

function TokugiWindow.build(context: SectionKit.Context): Window
	-- 並べているキャラクターと、その札（ツリーの並びの順）
	local shownCharacter: string? = nil
	local cards: { Card } = {}
	local rows: { Frame } = {}

	local window = LobbyWindow.build({
		name = "Tokugi",
		title = "特技ツリー",
		width = WINDOW_WIDTH,
		firstButton = function(): GuiObject?
			return if cards[1] then cards[1].button else nil
		end,
	})

	local function onPress(tokugiId: string)
		local characterId = shownCharacter
		if not characterId then
			return
		end
		SoundPlayer.playUi("Confirm")
		context.send("LearnTokugi", characterId, tokugiId)
	end

	-- キャラクターの特技ツリーの札を作り直す。同じキャラクターなら何もしない
	local function showCharacter(characterId: string)
		if shownCharacter == characterId then
			return
		end
		shownCharacter = characterId
		for _, row in rows do
			row:Destroy()
		end
		table.clear(rows)
		table.clear(cards)
		local tree = Tokugi.treeOf(characterId)
		local depths = Tokugi.depthsOf(tree)
		local rowOf: { [number]: Frame } = {}
		for order, definition in tree do
			local depth = depths[definition.Id] or 1
			local row = rowOf[depth]
			if not row then
				row = buildRow(depth)
				row.Parent = window.body
				rowOf[depth] = row
				table.insert(rows, row)
			end
			local card = buildCard(definition, order, onPress)
			card.button.Parent = row
			table.insert(cards, card)
		end
		local character = Characters.get(characterId)
		window.setTitle(`{if character then character.displayName else characterId}の特技ツリー`)
		window.reselect()
	end

	-- 届いた記録とパーティーの様子を映す
	local function render()
		local characterId = TokugiClient.shownCharacter()
		showCharacter(characterId)
		local tree = Tokugi.treeOf(characterId)
		local record = TokugiClient.recordOf(characterId)
		local state = TokugiClient.get()
		local loaded = state ~= nil and state.loaded
		local available = Tokugi.available(record, tree)
		local learnedCount = Tokugi.learnedCount(record, tree)
		local summary =
			`使える巻物 {available} 本（得た巻物の合計 {record.makimono} 本）　覚えた特技 {learnedCount}/{#tree}`
		window.hint.Text = if loaded
			then `{summary}\n押すと巻物を使って覚える。覚えた特技は次の出撃から能力値に足す`
			else `{summary}\n特技の記録を読み込んでいる。読み込むまで覚えられない`
		for _, card in cards do
			-- 札はツリーから作るので、ツリーに無い特技（nil）にはならない
			local status: Tokugi.Status = Tokugi.statusOf(record, tree, card.id) or "Zentei"
			local dimmed = status == "Zentei"
			local learned = status == "Learned"
			card.button.BackgroundColor3 = if dimmed then Ui.Color.Disabled else Ui.Color.Panel
			card.button.BackgroundTransparency = if dimmed then 0.35 else 0.1
			card.name.TextColor3 = if dimmed then Ui.Color.Disabled:Lerp(Ui.Color.Text, 0.5) else Ui.Color.Text
			card.effect.TextColor3 = card.name.TextColor3
			card.zentei.TextColor3 = card.name.TextColor3
			card.stroke.Color = if learned then Ui.Color.Selected else Ui.Color.Accent
			card.stroke.Thickness = if learned then 3 else 1
			card.status.Text = STATUS_TEXTS[status]
			card.status.TextColor3 = STATUS_COLORS[status]
		end
	end

	-- ロビーのフェーズの、待機中でない人だけが開ける
	local function canOpen(): boolean
		local state = PartyClient.get()
		local me = PartyClient.me()
		return state ~= nil and state.phase == "Lobby" and me ~= nil and not me.waiting
	end

	local function open()
		if not canOpen() then
			return
		end
		render()
		window.open()
	end

	TokugiClient.changed:Connect(render)
	PartyClient.changed:Connect(function()
		if not canOpen() then
			window.close()
			return
		end
		render()
	end)
	Players.LocalPlayer:GetAttributeChangedSignal("CharacterId"):Connect(render)
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local rejected = remotes:WaitForChild("SelectionRejected") :: RemoteEvent
	rejected.OnClientEvent:Connect(function(reason: RemoteSchema.RejectReason)
		if window.isOpen() then
			window.showMessage(RejectMessage.of(reason))
		end
	end)
	-- 札は記録が届く前にも並べておく（届いていないうちは、巻物も特技も無いものとして映す）
	render()

	return {
		open = open,
		close = window.close,
		isOpen = window.isOpen,
	}
end

return TokugiWindow
