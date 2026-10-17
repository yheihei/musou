--!strict
-- 出撃前の画面の欄に共通する型と部品。欄は見出しと中身を持ち、PartyState が届くたびに update で映し直す。
-- 欄はゲームパッドで選ぶボタンのまとまり（ステップ）を持つ。画面はステップの並びで、決定の後に選ぶボタンを次の欄へ進め、
-- 戻る（B）で前の欄へ戻す（SelectionController。#131）。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteSchema = require(ReplicatedStorage.Shared.RemoteSchema)
local Ui = require(script.Parent.Parent.Ui)

-- 欄が使う、画面の側の機能
export type Context = {
	-- Remotes の名前と引数で、選択をサーバーへ送る
	send: (remoteName: string, ...any) -> (),
	-- パネルの下に文を出す（サーバーへ送る前に分かる理由を出すとき）
	notify: (text: string) -> (),
	-- ボタンを押して選択を送ったことを知らせる。step はステップの名前、done は届いた PartyState で選択が通ったかを返す。
	-- 通ったら、ゲームパッドで選ぶボタンを次の欄へ進める
	pressed: (step: string, done: (state: RemoteSchema.PartyState) -> boolean) -> (),
}

-- ゲームパッドで選ぶボタンのまとまり。画面は欄のステップを上から順に並べる
export type Step = {
	name: string,
	-- このステップへ移ったときに選ぶボタン（確定した選択、無ければ最初に選べるボタン）。選べるボタンが無ければ nil
	focus: () -> GuiObject?,
	-- object がこのステップのボタン（の中の部品）か
	owns: (object: GuiObject) -> boolean,
	-- 決定の後に次の欄へ進めるとき、戻るときに飛ばすか（特技のように選ばなくてよい欄）
	optional: boolean?,
}

export type Section = {
	frame: Frame,
	-- 届いた PartyState を映す
	update: (state: RemoteSchema.PartyState) -> (),
	-- ゲームパッドで画面を開いたときに選ぶボタン
	firstButton: () -> GuiObject?,
	-- ゲームパッドで選ぶボタンのまとまり（上から順）
	steps: { Step },
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

-- 見えているボタンか（自分と親の GuiObject がすべて Visible）。ステップの選ぶボタンを決めるのに使う
function SectionKit.isVisible(object: GuiObject): boolean
	local current: Instance? = object
	while current and current:IsA("GuiObject") do
		if not (current :: GuiObject).Visible then
			return false
		end
		current = current.Parent
	end
	return true
end

-- buttons のどれか（の中の部品）か
function SectionKit.ownsAny(buttons: { GuiObject }, object: GuiObject): boolean
	for _, button in buttons do
		if object == button or object:IsDescendantOf(button) then
			return true
		end
	end
	return false
end

-- 確定した選択のボタンの見た目。金色の枠と背景で、ゲームパッドで選んでいる枠（水色。Ui の選択の枠）と見分ける。
-- dimmed は選べないボタンを暗くするか
function SectionKit.paintChoice(button: GuiObject, stroke: UIStroke, chosen: boolean, dimmed: boolean)
	button.BackgroundColor3 = if chosen
		then Ui.Color.SelectedFill
		elseif dimmed then Ui.Color.Disabled
		else Ui.Color.Panel
	button.BackgroundTransparency = if dimmed and not chosen then 0.35 else 0.1
	stroke.Color = if chosen then Ui.Color.Selected else Ui.Color.Accent
	stroke.Thickness = if chosen then 3 else 1
end

return SectionKit
