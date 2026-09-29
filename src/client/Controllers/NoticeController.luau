--!strict
-- 出撃メンバーでない人（ロビーのフェーズの全員と、出撃中に入った待機中の人）に、
-- 画面の隅へ非公式ファンゲームの表記を出す。待機中の人には待機中であることも出す。
-- 文言は ReplicatedStorage.Shared.Notice にある。

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Notice = require(ReplicatedStorage.Shared.Notice)
local PartyClient = require(script.Parent.Parent.PartyClient)
local Ui = require(script.Parent.Parent.Ui)

local NoticeController = {}

local function buildUnofficial(): ScreenGui
	local lines: { Instance } = {
		Ui.create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4) }),
		Ui.create("UIPadding", {
			PaddingTop = UDim.new(0, 10),
			PaddingBottom = UDim.new(0, 10),
			PaddingLeft = UDim.new(0, 12),
			PaddingRight = UDim.new(0, 12),
		}),
		Ui.create("UICorner", { CornerRadius = UDim.new(0, 8) }),
		Ui.create("TextLabel", {
			Name = "Title",
			LayoutOrder = 0,
			Size = UDim2.new(1, 0, 0, Ui.TextSize.Large),
			BackgroundTransparency = 1,
			Font = Ui.Font.Bold,
			TextSize = Ui.TextSize.Large,
			TextColor3 = Ui.Color.Accent,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = Notice.unofficial.title,
		}),
	}
	for index, line in Notice.unofficial.lines do
		table.insert(
			lines,
			Ui.create("TextLabel", {
				Name = `Line{index}`,
				LayoutOrder = index,
				Size = UDim2.fromScale(1, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				Font = Ui.Font.Body,
				TextSize = Ui.TextSize.Body,
				TextColor3 = Ui.Color.Text,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextWrapped = true,
				Text = line,
			})
		)
	end
	local panel = Ui.create("Frame", {
		Name = "Panel",
		Position = UDim2.fromOffset(16, 16),
		Size = UDim2.fromOffset(480, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Ui.Color.Panel,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
	}, lines)
	return Ui.screenGui("UnofficialNotice", Ui.Layer.UnofficialNotice, { panel })
end

local function buildWaiting(): ScreenGui
	-- 左上の非公式の表記と重ならないよう、画面の上から2割ほど下げて中央に出す
	local banner = Ui.create("Frame", {
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.22),
		Size = UDim2.fromOffset(560, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Ui.Color.Panel,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
	}, {
		Ui.create("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 4),
		}),
		Ui.create("UIPadding", {
			PaddingTop = UDim.new(0, 10),
			PaddingBottom = UDim.new(0, 10),
			PaddingLeft = UDim.new(0, 12),
			PaddingRight = UDim.new(0, 12),
		}),
		Ui.create("UICorner", { CornerRadius = UDim.new(0, 8) }),
		Ui.create("TextLabel", {
			Name = "Title",
			LayoutOrder = 0,
			Size = UDim2.new(1, 0, 0, Ui.TextSize.Title),
			BackgroundTransparency = 1,
			Font = Ui.Font.Heavy,
			TextSize = Ui.TextSize.Title,
			TextColor3 = Ui.Color.Selected,
			Text = Notice.waiting.title,
		}),
		Ui.create("TextLabel", {
			Name = "Body",
			LayoutOrder = 1,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Font = Ui.Font.Body,
			TextSize = Ui.TextSize.Body,
			TextColor3 = Ui.Color.Text,
			TextWrapped = true,
			Text = Notice.waiting.body,
		}),
	})
	return Ui.screenGui("Waiting", Ui.Layer.Waiting, { banner })
end

function NoticeController.start()
	local unofficial = buildUnofficial()
	local waiting = buildWaiting()

	local function refresh()
		local state = PartyClient.get()
		local me = PartyClient.me()
		local isWaiting = me ~= nil and me.waiting
		-- PartyState が届く前はロビーにいるものとして表記を出す
		local inLobby = state == nil or state.phase == "Lobby"
		unofficial.Enabled = inLobby or isWaiting
		waiting.Enabled = isWaiting
	end

	PartyClient.changed:Connect(refresh)
	refresh()
end

return NoticeController
