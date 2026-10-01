--!strict
-- 出撃前の画面の欄に共通する型と部品。欄は見出しと中身を持ち、PartyState が届くたびに update で映し直す。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteSchema = require(ReplicatedStorage.Shared.RemoteSchema)
local Ui = require(script.Parent.Parent.Ui)

-- 欄が使う、画面の側の機能
export type Context = {
	-- Remotes の名前と引数で、選択をサーバーへ送る
	send: (remoteName: string, ...any) -> (),
}

export type Section = {
	frame: Frame,
	-- 届いた PartyState を映す
	update: (state: RemoteSchema.PartyState) -> (),
	-- ゲームパッドで画面を開いたときに選ぶボタン
	firstButton: () -> GuiObject?,
}

local SectionKit = {}

-- 見出しの付いた欄の枠を作り、枠と中身を入れる Frame を返す。order は欄の並び順
function SectionKit.section(name: string, title: string, order: number): (Frame, Frame)
	local content = Ui.create("Frame", {
		Name = "Content",
		LayoutOrder = 2,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	})
	local frame = Ui.create("Frame", {
		Name = name,
		LayoutOrder = order,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, {
		Ui.create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }),
		Ui.text({
			Name = "Title",
			LayoutOrder = 0,
			Size = UDim2.new(1, 0, 0, Ui.TextSize.Large + 4),
			Font = Ui.Font.Heavy,
			TextSize = Ui.TextSize.Large,
			TextColor3 = Ui.Color.Accent,
			Text = title,
		}),
		content,
	})
	return frame :: Frame, content :: Frame
end

-- PartyState の中の本人
function SectionKit.me(state: RemoteSchema.PartyState): RemoteSchema.MemberState?
	for _, member in state.members do
		if member.userId == Players.LocalPlayer.UserId then
			return member
		end
	end
	return nil
end

-- 本人がリーダーか
function SectionKit.isLeader(state: RemoteSchema.PartyState): boolean
	return state.leader == Players.LocalPlayer.UserId
end

return SectionKit
