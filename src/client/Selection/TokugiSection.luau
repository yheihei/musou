--!strict
-- 出撃前の画面の特技の欄。画面に出すキャラクター（TokugiClient.shownCharacter。選んでいるキャラクター、
-- 無ければ今のキャラクター）の使える巻物と覚えた特技の数を出し、「特技ツリーを開く」で特技ツリーの画面（TokugiWindow）を開く。
-- 記録は TokugiClient から読み、PartyState と記録が届いたときと、今のキャラクターが変わったときに映し直す。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Characters = require(ReplicatedStorage.Shared.Characters)
local RemoteSchema = require(ReplicatedStorage.Shared.RemoteSchema)
local SoundPlayer = require(ReplicatedStorage.Shared.SoundPlayer)
local Tokugi = require(ReplicatedStorage.Shared.Tokugi)
local TokugiClient = require(script.Parent.Parent.TokugiClient)
local Ui = require(script.Parent.Parent.Ui)
local SectionKit = require(script.Parent.SectionKit)
local TokugiWindow = require(script.Parent.TokugiWindow)

local TokugiSection = {}

-- 開くボタンの高さ（ピクセル）
local BUTTON_HEIGHT = 44

function TokugiSection.build(context: SectionKit.Context): SectionKit.Section
	local frame, content = SectionKit.section("Tokugi", "特技", 3)
	local summary = Ui.text({
		Name = "Summary",
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 18),
		TextSize = Ui.TextSize.Small,
		TextColor3 = Ui.Color.Accent,
		Text = "",
	})
	summary.Parent = frame
	Ui.create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = content,
	})
	local button = Ui.button({
		Name = "OpenTokugi",
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, BUTTON_HEIGHT),
		Text = "特技ツリーを開く",
		Parent = content,
	})
	local window = TokugiWindow.build(context)
	button.Activated:Connect(function()
		SoundPlayer.playUi("Confirm")
		window.open()
	end)

	local function render()
		local characterId = TokugiClient.shownCharacter()
		local character = Characters.get(characterId)
		local tree = Tokugi.treeOf(characterId)
		local record = TokugiClient.recordOf(characterId)
		local name = if character then character.displayName else characterId
		local available = Tokugi.available(record, tree)
		local learned = Tokugi.learnedCount(record, tree)
		summary.Text = `{name}　使える巻物 {available} 本　覚えた特技 {learned}/{#tree}`
	end
	TokugiClient.changed:Connect(render)
	-- 出撃すると今のキャラクターが変わる
	Players.LocalPlayer:GetAttributeChangedSignal("CharacterId"):Connect(render)

	return {
		frame = frame,
		update = function(_state: RemoteSchema.PartyState)
			-- 画面に出すキャラクターは PartyClient の写しから決める（届いた PartyState と同じもの）
			render()
		end,
		firstButton = function(): GuiObject?
			return button
		end,
	}
end

return TokugiSection
