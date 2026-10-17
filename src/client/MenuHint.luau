--!strict
-- 画面の操作の案内（決定・戻るなど）。今の入力の種類に合わせて、ゲームパッドならボタンの絵（Ui.glyph。取れなければ表記の文字）と
-- 操作の名前を、キーボードとマウスならキーの表記と操作の名前を横に並べる。タッチでは出さない（画面のボタンを押せば分かるので）。
-- 表記は ReplicatedStorage.Shared.InputMap の操作から引き、表記の無い入力の種類ではその操作を出さない。
-- 入力の種類が変わったら出し直す（#131）

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InputMap = require(ReplicatedStorage.Shared.InputMap)
local Ui = require(script.Parent.Ui)

local MenuHint = {}

export type Item = {
	binding: InputMap.Binding,
	-- 操作の名前（決定・戻るなど）
	text: string,
	-- ボタンの絵を引く入力（"KeyCode.ButtonA" など）。省くと binding のゲームパッドの最初の入力
	gamepadKey: string?,
}

export type Hint = {
	frame: Frame,
	-- 入力の種類に合わせて出し直す
	refresh: () -> (),
}

-- ボタンの絵の大きさと、操作の間隔（ピクセル）
local GLYPH_SIZE = 22
local ITEM_GAP = 12

type ItemGui = {
	item: Item,
	frame: Frame,
	glyph: ImageLabel,
	key: TextLabel,
}

-- 入力の文字列（"KeyCode.ButtonA"）の KeyCode
local function keyCodeOf(input: string?): Enum.KeyCode?
	if not input then
		return nil
	end
	local kind, name = InputMap.parse(input)
	if kind ~= "KeyCode" or not name then
		return nil
	end
	local ok, value = pcall(function(): any
		return (Enum.KeyCode :: any)[name]
	end)
	return if ok then value else nil
end

local function buildItem(item: Item, order: number): ItemGui
	local glyph = Ui.create("ImageLabel", {
		Name = "Glyph",
		LayoutOrder = 1,
		Size = UDim2.fromOffset(GLYPH_SIZE, GLYPH_SIZE),
		BackgroundTransparency = 1,
		Visible = false,
	}) :: ImageLabel
	-- 絵の無いときと、キーボードとマウスのときに出すキーの表記。枠で囲んでボタンらしく見せる
	local key = Ui.text({
		Name = "Key",
		LayoutOrder = 1,
		Size = UDim2.fromOffset(0, GLYPH_SIZE),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Ui.Color.Panel,
		BackgroundTransparency = 0,
		Font = Ui.Font.Bold,
		TextSize = Ui.TextSize.Small,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "",
	})
	Ui.create("UICorner", { CornerRadius = UDim.new(0, 4), Parent = key })
	Ui.create("UIStroke", {
		Color = Ui.Color.Accent,
		Thickness = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = key,
	})
	Ui.create("UIPadding", { PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5), Parent = key })
	local text = Ui.text({
		Name = "Text",
		LayoutOrder = 2,
		Size = UDim2.fromOffset(0, GLYPH_SIZE),
		AutomaticSize = Enum.AutomaticSize.X,
		Font = Ui.Font.Bold,
		TextSize = Ui.TextSize.Small,
		Text = item.text,
	})
	local frame = Ui.create("Frame", {
		Name = `Item{order}`,
		LayoutOrder = order,
		Size = UDim2.fromOffset(0, GLYPH_SIZE),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
	}, {
		Ui.create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 4),
		}),
		glyph,
		key,
		text,
	}) :: Frame
	return { item = item, frame = frame, glyph = glyph, key = key }
end

-- 案内を作る。alignment は並びの寄せ（省くと右寄せ）。位置と大きさは呼び出し元が frame に決める
function MenuHint.build(items: { Item }, alignment: Enum.HorizontalAlignment?): Hint
	local frame = Ui.create("Frame", {
		Name = "MenuHint",
		Size = UDim2.new(1, 0, 0, GLYPH_SIZE),
		BackgroundTransparency = 1,
	}, {
		Ui.create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = alignment or Enum.HorizontalAlignment.Right,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, ITEM_GAP),
		}),
	}) :: Frame
	local guis: { ItemGui } = {}
	for order, item in items do
		local gui = buildItem(item, order)
		gui.frame.Parent = frame
		table.insert(guis, gui)
	end

	local function refresh()
		local kind = Ui.inputKind()
		frame.Visible = kind ~= "Touch"
		for _, gui in guis do
			local label = Ui.label(gui.item.binding.labels, kind)
			gui.frame.Visible = label ~= ""
			local image: string? = nil
			if kind == "Gamepad" then
				local keyCode = keyCodeOf(gui.item.gamepadKey or gui.item.binding.gamepad[1])
				image = if keyCode then Ui.glyph(keyCode) else nil
			end
			gui.glyph.Image = image or ""
			gui.glyph.Visible = image ~= nil
			gui.key.Text = label
			gui.key.Visible = image == nil
		end
	end
	Ui.onInputKindChanged(refresh)
	refresh()
	return { frame = frame, refresh = refresh }
end

-- ボタンに操作の表記を添える。ゲームパッドのときは文言の右にボタンの絵（取れなければ表記の文字）を出し、
-- ほかの入力の種類では文言だけにする。入力の種類が変わったら出し直す
function MenuHint.decorate(button: TextButton, text: string, item: Item)
	local glyph = Ui.create("ImageLabel", {
		Name = "Glyph",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(GLYPH_SIZE, GLYPH_SIZE),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = button,
	}) :: ImageLabel
	local function refresh()
		local kind = Ui.inputKind()
		local keyCode = keyCodeOf(item.gamepadKey or item.binding.gamepad[1])
		local image = if kind == "Gamepad" and keyCode then Ui.glyph(keyCode) else nil
		glyph.Image = image or ""
		glyph.Visible = image ~= nil
		button.Text = if kind == "Gamepad" and not image then `{text}　{item.binding.labels.Gamepad}` else text
	end
	Ui.onInputKindChanged(refresh)
	refresh()
end

return MenuHint
