--!strict
-- 画面の共通部品。Instance の生成、書体と文字の大きさ、画面の配色、ボタン、
-- 入力の種類とボタン表記の切り替え、ゲームパッドでボタンを選んでよくなるまでの待ち、ゲームパッドやキーの操作で選んでいる部品の移動、
-- ScreenGui の重なり順をまとめる。
-- 軍・クラン・キャラクターの色は ReplicatedStorage.Shared.Colors に置く。

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Ui = {}

-- ScreenGui の重なり順（DisplayOrder）。後に書いたものほど上に重なる
Ui.Layer = {
	Hud = 10,
	BattleStatus = 15,
	Minimap = 20,
	BattleSerifu = 30,
	HikeiNotice = 40,
	UnofficialNotice = 50,
	Waiting = 60,
	Letterbox = 65,
	SkipCount = 70,
	Dialogue = 80,
	Selection = 90,
	Result = 100,
	Title = 110,
}

-- 右上のミニマップの一辺と、画面の上端・右端からの余白（ピクセル）。
-- 上端からの余白は、画面上部の戦況（上端から 8、高さ 68）の下にあける。狭い画面で戦況と重ならないように。
-- 秘計の知らせはミニマップの左に積む
Ui.Minimap = {
	Size = 200,
	Top = 84,
	Right = 24,
}

-- 書体の段階
Ui.Font = {
	Body = Enum.Font.Gotham,
	Bold = Enum.Font.GothamBold,
	Heavy = Enum.Font.GothamBlack,
}

-- 文字の大きさの段階
Ui.TextSize = {
	Small = 14,
	Body = 18,
	Large = 24,
	Title = 32,
	Huge = 44,
}

-- 画面の配色
Ui.Color = {
	Text = Color3.new(1, 1, 1),
	Panel = Color3.fromRGB(30, 30, 30),
	Accent = Color3.fromRGB(255, 220, 150),
	Selected = Color3.fromRGB(255, 200, 60),
	Disabled = Color3.fromRGB(90, 90, 90),
	Gauge = Color3.fromRGB(255, 140, 40),
	GaugeFull = Color3.fromRGB(255, 60, 30),
	Health = Color3.fromRGB(90, 200, 110),
	HealthLow = Color3.fromRGB(230, 70, 60),
}

-- className の Instance を作り、props を設定して children を入れる
function Ui.create<T>(className: string, props: { [string]: any }, children: { Instance }?): T
	local instance = Instance.new(className :: any)
	for key, value in props do
		(instance :: any)[key] = value
	end
	local list: { Instance } = children or {}
	for _, child in list do
		child.Parent = instance
	end
	return instance :: any
end

-- 重なり順を決めた ScreenGui を作って PlayerGui に置く。layer は Ui.Layer の値
function Ui.screenGui(name: string, layer: number, children: { Instance }?): ScreenGui
	return Ui.create("ScreenGui", {
		Name = name,
		DisplayOrder = layer,
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	}, children)
end

-- ゲームパッドで選んでいるボタンを囲む枠。ボタンの SelectionImageObject に使う
local selectionFrame: Frame? = nil
local function getSelectionFrame(): Frame
	if not selectionFrame then
		selectionFrame = Ui.create("Frame", {
			Name = "SelectionFrame",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
		}, {
			Ui.create("UICorner", { CornerRadius = UDim.new(0, 8) }),
			Ui.create("UIStroke", {
				Color = Ui.Color.Selected,
				Thickness = 3,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}),
		})
	end
	return selectionFrame :: Frame
end

-- 共通の見た目の文字。背景なし・左寄せ・本文の大きさで作り、props で上書きする
function Ui.text(props: { [string]: any }): TextLabel
	local label = Ui.create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Ui.Font.Body,
		TextSize = Ui.TextSize.Body,
		TextColor3 = Ui.Color.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
	})
	for key, value in props do
		(label :: any)[key] = value
	end
	return label :: TextLabel
end

-- 共通の見た目のボタン。props で位置や文言を上書きする
function Ui.button(props: { [string]: any }): TextButton
	local button = Ui.create("TextButton", {
		AutoButtonColor = true,
		BackgroundColor3 = Ui.Color.Panel,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		Font = Ui.Font.Bold,
		TextSize = Ui.TextSize.Body,
		TextColor3 = Ui.Color.Text,
		Selectable = true,
		SelectionImageObject = getSelectionFrame(),
	}, {
		Ui.create("UICorner", { CornerRadius = UDim.new(0, 8) }),
		Ui.create("UIStroke", {
			Color = Ui.Color.Accent,
			Thickness = 1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
	})
	for key, value in props do
		(button :: any)[key] = value
	end
	return button :: TextButton
end

export type InputKind = "Keyboard" | "Gamepad" | "Touch"

-- 入力の種類を UserInputType から判定する。キーボードとマウスはまとめて Keyboard
local function inputKindOf(inputType: Enum.UserInputType): InputKind?
	if inputType == Enum.UserInputType.Touch then
		return "Touch"
	end
	local name = inputType.Name
	if string.sub(name, 1, 7) == "Gamepad" then
		return "Gamepad"
	end
	if inputType == Enum.UserInputType.Keyboard or string.sub(name, 1, 5) == "Mouse" then
		return "Keyboard"
	end
	return nil
end
Ui.inputKindOf = inputKindOf

local function initialKind(): InputKind
	if #UserInputService:GetConnectedGamepads() > 0 then
		return "Gamepad"
	end
	local kind: InputKind? = inputKindOf(UserInputService:GetLastInputType())
	if kind then
		return kind
	end
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "Touch"
	end
	return "Keyboard"
end

local currentKind: InputKind = initialKind()
local kindChanged = Instance.new("BindableEvent")

local function setKind(kind: InputKind)
	if kind ~= currentKind then
		currentKind = kind
		kindChanged:Fire(kind)
	end
end

-- ゲームパッドをつないだらゲームパッド、最後に使った入力が変わったらその種類にする
UserInputService.GamepadConnected:Connect(function()
	setKind("Gamepad")
end)
UserInputService.GamepadDisconnected:Connect(function()
	if #UserInputService:GetConnectedGamepads() == 0 then
		setKind(inputKindOf(UserInputService:GetLastInputType()) or "Keyboard")
	end
end)
UserInputService.LastInputTypeChanged:Connect(function(inputType)
	local kind: InputKind? = inputKindOf(inputType)
	if kind then
		setKind(kind)
	end
end)

-- 今の入力の種類
function Ui.inputKind(): InputKind
	return currentKind
end

-- 入力の種類が変わったときに呼ぶ
function Ui.onInputKindChanged(callback: (InputKind) -> ()): RBXScriptConnection
	return kindChanged.Event:Connect(callback)
end

-- ゲームパッドで画面のボタンを選べるようになる、入室からの秒数（time()）と、キャラクターの Humanoid を待つ秒数の上限
local SELECT_AFTER_START = 3
local HUMANOID_TIMEOUT = 10

-- ゲームパッドで画面のボタンを選んでよくなる（GuiService.SelectedObject を設定してよくなる）まで待つ。
-- 入室直後に選ぶと、ゲームパッドをつないだままテストプレイを始めたときに Studio が落ちる。
-- そのため、入室から SELECT_AFTER_START 秒たち、キャラクターが出るまで待つ。
-- notBefore（time() の時刻）を渡すと、その時刻になるまでも待つ。
-- 待った後に、画面を閉じていないかなどを呼び出し元で確かめてから選ぶ
function Ui.waitForSelectable(notBefore: number?)
	if not game:IsLoaded() then
		game.Loaded:Wait()
	end
	local player = Players.LocalPlayer
	local character = player.Character or player.CharacterAdded:Wait()
	character:WaitForChild("Humanoid", HUMANOID_TIMEOUT)
	local rest = math.max(SELECT_AFTER_START, notBefore or 0) - time()
	if rest > 0 then
		task.wait(rest)
	end
end

-- screen の中で、ゲームパッドやキーの操作で選んでいる部品（GuiService.SelectedObject）が別の部品へ移ったときに呼ぶ。
-- 何も選んでいない状態から選んだとき（画面を開いて最初のボタンを選んだとき）、選択を外したとき、
-- ほかの画面の部品との間で移ったときは呼ばない
function Ui.onSelectionMoved(screen: ScreenGui, callback: () -> ()): RBXScriptConnection
	local previous: GuiObject? = GuiService.SelectedObject
	return GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(function()
		local from = previous
		local to = GuiService.SelectedObject
		previous = to
		if from and to and from ~= to and from:IsDescendantOf(screen) and to:IsDescendantOf(screen) then
			callback()
		end
	end)
end

export type Labels = {
	Keyboard: string,
	Gamepad: string,
	Touch: string?,
}

-- 入力の種類に合わせたボタン表記を返す。kind を省くと今の入力の種類を使う
function Ui.label(labels: Labels, kind: InputKind?): string
	local which = kind or currentKind
	if which == "Gamepad" then
		return labels.Gamepad
	elseif which == "Touch" then
		return labels.Touch or labels.Keyboard
	end
	return labels.Keyboard
end

return Ui
