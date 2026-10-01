--!strict
-- 出撃前の画面の下の帯。メンバーごとのキャラクターの選択状況と、出撃ボタンを出す。
-- 出撃ボタンは Remotes.Shutsugeki を送り、出撃できるかはサーバーが判定する。
-- 押す前にも出撃できない理由が分かるよう、SelectionRules.checkShutsugeki をクライアントでも呼んで横に出す。
--
-- - 出撃ボタンを押せるのはリーダーだけ。リーダー以外には暗いボタンと「リーダーの出撃を待つ」を出す
-- - メンバーは入った順に、リーダーの印と選んだキャラクター（未選択なら「未選択」）を並べる。待機中の人は「待機中」

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Characters = require(ReplicatedStorage.Shared.Characters)
local RejectMessage = require(ReplicatedStorage.Shared.RejectMessage)
local RemoteSchema = require(ReplicatedStorage.Shared.RemoteSchema)
local SelectionRules = require(ReplicatedStorage.Shared.SelectionRules)
local SoundPlayer = require(ReplicatedStorage.Shared.SoundPlayer)
local SectionKit = require(script.Parent.SectionKit)
local Ui = require(script.Parent.Parent.Ui)

local ShutsugekiBar = {}

-- 帯の高さと出撃ボタンの大きさ（ピクセル）
ShutsugekiBar.HEIGHT = 104
local BUTTON_WIDTH = 132
local BUTTON_HEIGHT = 48
local MEMBER_ROW = 20

-- 出撃するメンバー（待機中でない人）が全員キャラクターを選んでいるか
local function allReady(state: RemoteSchema.PartyState): boolean
	for _, member in state.members do
		if not member.waiting and not member.character then
			return false
		end
	end
	return true
end

local function characterName(id: string?): string
	local character = if id then Characters.get(id) else nil
	return if character then character.displayName else "未選択"
end

function ShutsugekiBar.build(context: SectionKit.Context): SectionKit.Section
	local members = Ui.create("Frame", {
		Name = "Members",
		Position = UDim2.fromOffset(12, 8),
		Size = UDim2.new(1, -(BUTTON_WIDTH + 36), 0, MEMBER_ROW * 4),
		BackgroundTransparency = 1,
	}, {
		Ui.create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local button = Ui.button({
		Name = "Shutsugeki",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 8),
		Size = UDim2.fromOffset(BUTTON_WIDTH, BUTTON_HEIGHT),
		Font = Ui.Font.Heavy,
		TextSize = Ui.TextSize.Large,
		Text = "出撃",
	})
	local reason = Ui.text({
		Name = "Reason",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, BUTTON_HEIGHT + 12),
		Size = UDim2.fromOffset(BUTTON_WIDTH + 60, ShutsugekiBar.HEIGHT - BUTTON_HEIGHT - 16),
		TextSize = Ui.TextSize.Small,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = "",
	})
	local frame = Ui.create("Frame", {
		Name = "ShutsugekiBar",
		Size = UDim2.new(1, 0, 0, ShutsugekiBar.HEIGHT),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.6,
		BorderSizePixel = 0,
	}, { members, button, reason })

	local isLeader = false
	button.Activated:Connect(function()
		if not isLeader then
			SoundPlayer.playUi("Cancel")
			context.notify(RejectMessage.of("NotLeader"))
			return
		end
		SoundPlayer.playUi("Confirm")
		context.send("Shutsugeki")
	end)

	local memberLabels: { TextLabel } = {}
	local function update(state: RemoteSchema.PartyState)
		isLeader = SectionKit.isLeader(state)
		for _, label in memberLabels do
			label:Destroy()
		end
		table.clear(memberLabels)
		for index, member in state.members do
			local leaderMark = if member.userId == state.leader then "（リーダー）" else ""
			local status = if member.waiting then "待機中" else characterName(member.character)
			local ready = member.waiting or member.character ~= nil
			local label = Ui.text({
				Name = `Member{index}`,
				LayoutOrder = index,
				Size = UDim2.new(1, 0, 0, MEMBER_ROW),
				TextSize = Ui.TextSize.Small,
				TextColor3 = if ready then Ui.Color.Text else Ui.Color.HealthLow,
				Text = `{member.name}{leaderMark}　{status}`,
				Parent = members,
			})
			table.insert(memberLabels, label)
		end

		local me = SectionKit.me(state)
		local reject = SelectionRules.checkShutsugeki({
			phase = state.phase,
			isLeader = isLeader,
			waiting = me ~= nil and me.waiting,
		}, state.stage, state.unlockedStages, allReady(state))
		local canGo = reject == nil
		button.BackgroundColor3 = if canGo then Ui.Color.GaugeFull else Ui.Color.Disabled
		button.TextColor3 = if isLeader then Ui.Color.Text else Ui.Color.Disabled:Lerp(Ui.Color.Text, 0.5)
		if not isLeader then
			reason.Text = "リーダーの出撃を待つ"
		elseif reject then
			reason.Text = RejectMessage.of(reject)
		else
			reason.Text = "全員の準備ができた"
		end
		reason.TextColor3 = if canGo then Ui.Color.Selected else Ui.Color.Text
	end

	return {
		frame = frame :: Frame,
		update = update,
		firstButton = function(): GuiObject?
			return button
		end,
	}
end

return ShutsugekiBar
