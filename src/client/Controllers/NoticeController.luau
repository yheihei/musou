--!strict
-- 出撃メンバーでない人（ロビーのフェーズの全員と、出撃中に入った待機中の人）に、
-- 画面の隅へ非公式ファンゲームの表記を出す。待機中の人には待機中であることも出す。
-- 文言は ReplicatedStorage.Shared.Notice にある。
-- タイトル画面（TitleController）を出している間は、どちらも出さない（タイトル画面に同じ表記を出す）。
--
-- - 小さい画面（スマホ横画面。Ui.isSmallScreen）では、文字を縮めずに、表記をロビーの左上（出撃前の画面の左）に、
--   待機中の表示を出撃前の画面の場所（右）に置く（ReplicatedStorage.Shared.SmallScreen の lobbyOf）。
--   高さに収まらなければ、文字が読める下限を下回らない範囲で縮める（Ui.fitHeight）

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Notice = require(ReplicatedStorage.Shared.Notice)
local SmallScreen = require(ReplicatedStorage.Shared.SmallScreen)
local PartyClient = require(script.Parent.Parent.PartyClient)
local Ui = require(script.Parent.Parent.Ui)
local TitleController = require(script.Parent.TitleController)

local NoticeController = {}

-- 大きい画面での、表記の位置と幅、待機中の表示の位置（画面の幅と高さの割合）と幅（ピクセル）
local UNOFFICIAL_MARGIN = 16
local UNOFFICIAL_WIDTH = 480
local WAITING_TOP = 0.22
local WAITING_WIDTH = 560
-- 小さい画面で縮めてよい倍率の下限。どちらも一番小さい文字は Ui.TextSize.Body
local MIN_SCALE = SmallScreen.minScale(Ui.TextSize.Body)

local function buildUnofficial(): (ScreenGui, Frame)
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
	-- 位置と幅は applyLayout が画面の大きさに合わせて決める
	local panel = Ui.create("Frame", {
		Name = "Panel",
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Ui.Color.Panel,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
	}, lines)
	return Ui.screenGui("UnofficialNotice", Ui.Layer.UnofficialNotice, { panel }), panel :: Frame
end

local function buildWaiting(): (ScreenGui, Frame)
	-- 大きい画面では、左上の非公式の表記と重ならないよう、画面の上から2割ほど下げて中央に出す（applyLayout）
	local banner = Ui.create("Frame", {
		Name = "Banner",
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
	return Ui.screenGui("Waiting", Ui.Layer.Waiting, { banner }), banner :: Frame
end

function NoticeController.start()
	local unofficial, panel = buildUnofficial()
	local waiting, banner = buildWaiting()

	-- 小さい画面で、表記と待機中の表示を収める高さ（大きい画面では nil）
	local panelLimit: number? = nil
	local bannerLimit: number? = nil
	local refitPanel = Ui.fitHeight(panel, function()
		return panelLimit, MIN_SCALE
	end)
	local refitBanner = Ui.fitHeight(banner, function()
		return bannerLimit, MIN_SCALE
	end)

	-- 表記と待機中の表示の位置と幅を、画面の大きさに合わせる
	local function applyLayout()
		if Ui.isSmallScreen() then
			local size = Ui.safeAreaSize()
			local lobby = SmallScreen.lobbyOf(size.X, size.Y)
			panel.Position = UDim2.fromOffset(lobby.notice.x, lobby.notice.y)
			panel.Size = UDim2.fromOffset(lobby.notice.width, 0)
			banner.AnchorPoint = Vector2.zero
			banner.Position = UDim2.fromOffset(lobby.waiting.x, lobby.waiting.y)
			banner.Size = UDim2.fromOffset(lobby.waiting.width, 0)
			panelLimit = lobby.notice.height
			bannerLimit = lobby.waiting.height
		else
			panel.Position = UDim2.fromOffset(UNOFFICIAL_MARGIN, UNOFFICIAL_MARGIN)
			panel.Size = UDim2.fromOffset(UNOFFICIAL_WIDTH, 0)
			banner.AnchorPoint = Vector2.new(0.5, 0)
			banner.Position = UDim2.fromScale(0.5, WAITING_TOP)
			banner.Size = UDim2.fromOffset(WAITING_WIDTH, 0)
			panelLimit = nil
			bannerLimit = nil
		end
		refitPanel()
		refitBanner()
	end
	Ui.onSafeAreaChanged(applyLayout)
	applyLayout()

	local function refresh()
		local state = PartyClient.get()
		local me = PartyClient.me()
		local isWaiting = me ~= nil and me.waiting
		-- PartyState が届く前はロビーにいるものとして表記を出す
		local inLobby = state == nil or state.phase == "Lobby"
		local titleOpen = TitleController.isOpen()
		unofficial.Enabled = (inLobby or isWaiting) and not titleOpen
		waiting.Enabled = isWaiting and not titleOpen
	end

	PartyClient.changed:Connect(refresh)
	TitleController.changed:Connect(refresh)
	refresh()
end

return NoticeController
