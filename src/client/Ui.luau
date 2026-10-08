--!strict
-- 画面の共通部品。Instance の生成、書体と文字の大きさ、画面の配色、ボタン、
-- 入力の種類とボタン表記の切り替え、ゲームパッドでボタンを選んでよくなるまでの待ち、ゲームパッドやキーの操作で選んでいる部品の移動、
-- ScreenGui の重なり順、タッチの配置、タッチで遊んでいるか、安全な範囲の大きさと小さい画面（スマホ横画面）の部品をまとめる。
-- 軍・クラン・キャラクターの色は ReplicatedStorage.Shared.Colors に置く。

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local SmallScreen = require(ReplicatedStorage.Shared.SmallScreen)
local TouchLayout = require(ReplicatedStorage.Shared.TouchLayout)

local Ui = {}

-- ScreenGui の重なり順（DisplayOrder）。後に書いたものほど上に重なる
Ui.Layer = {
	Hud = 10,
	TouchControls = 12,
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
	-- 出撃前の画面から開く窓（特技ツリーなど）
	LobbyWindow = 95,
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

-- タッチの配置。タッチの操作ボタンを出している間（TouchControlsController が決める）は、戦闘の画面を
-- 同じ倍率で縮め、縮める前の大きさの画面に置いたように並べる（計算は ReplicatedStorage.Shared.TouchLayout）
export type TouchLayout = {
	-- タッチの操作ボタンを出しているか
	active: boolean,
	-- 戦闘の画面を縮める倍率。出していないときは 1
	scale: number,
	-- 出しているときの配置（TouchLayout.compute の結果）。台詞と秘計の知らせは、ここから位置と倍率を読む
	placement: TouchLayout.Layout?,
}

local touchLayout: TouchLayout = { active = false, scale = 1, placement = nil }
local touchLayoutChanged = Instance.new("BindableEvent")

-- 今のタッチの配置
function Ui.touchLayout(): TouchLayout
	return touchLayout
end

-- タッチの配置を切り替える。placement は今の画面の大きさで決めた配置。TouchControlsController だけが呼ぶ
function Ui.setTouchLayout(active: boolean, placement: TouchLayout.Layout)
	local nextScale = if active then placement.scale else 1
	local previous = touchLayout.placement
	local samePlacement = not active
		or (previous ~= nil and previous.width == placement.width and previous.height == placement.height)
	if active == touchLayout.active and nextScale == touchLayout.scale and samePlacement then
		return
	end
	touchLayout = { active = active, scale = nextScale, placement = if active then placement else nil }
	touchLayoutChanged:Fire()
end

-- タッチの配置が変わったときに呼ぶ
function Ui.onTouchLayoutChanged(callback: (TouchLayout) -> ()): RBXScriptConnection
	return touchLayoutChanged.Event:Connect(function()
		callback(touchLayout)
	end)
end

-- 戦闘の画面の部品（ScreenGui の直下の Frame）をタッチの配置に合わせる。タッチの配置の間は、部品を倍率で縮め（UIScale）、
-- 位置の Offset も同じ倍率で縮める（縮める前の大きさの画面に置いた位置になる）。大きさは Offset で決めた部品にだけ使う。
-- touchPosition と touchAnchor を渡すと、タッチの配置の間はその位置（縮める前の値）と AnchorPoint に移す。
-- scaleOf を渡すと、タッチの配置の間の部品の倍率を、戦闘の画面の倍率から scaleOf で決める（読ませる部品を読める下限で止めるとき）。
-- 元の位置と AnchorPoint は、呼んだときの値を覚えておき、タッチの配置をやめたら戻す
function Ui.fitTouchLayout(
	object: GuiObject,
	touchPosition: UDim2?,
	touchAnchor: Vector2?,
	scaleOf: ((scale: number) -> number)?
)
	local basePosition = object.Position
	local baseAnchor = object.AnchorPoint
	local scaler = Ui.create("UIScale", { Name = "TouchScale", Parent = object }) :: UIScale
	local function apply(layout: TouchLayout)
		local position = if layout.active and touchPosition then touchPosition else basePosition
		local scale = if layout.active then layout.scale else 1
		scaler.Scale = if layout.active and scaleOf then scaleOf(scale) else scale
		object.AnchorPoint = if layout.active and touchAnchor then touchAnchor else baseAnchor
		object.Position =
			UDim2.new(position.X.Scale, position.X.Offset * scale, position.Y.Scale, position.Y.Offset * scale)
	end
	Ui.onTouchLayoutChanged(apply)
	apply(touchLayout)
end

-- タッチで遊んでいるか（フェーズを問わない）。TouchControlsController が ReplicatedStorage.Shared.TouchControls の
-- isActive で決める（戦闘の操作ボタンを出すかと同じ判断。窓口の SetTouchControls で強制できる）。
-- イベントシーンのスキップのボタンなど、戦闘の外の画面もこれでタッチの見た目にする
local touchInput = false
local touchInputChanged = Instance.new("BindableEvent")

function Ui.isTouchInput(): boolean
	return touchInput
end

-- TouchControlsController だけが呼ぶ
function Ui.setTouchInput(active: boolean)
	if active ~= touchInput then
		touchInput = active
		touchInputChanged:Fire(active)
	end
end

-- タッチで遊んでいるかが変わったときに呼ぶ
function Ui.onTouchInputChanged(callback: (boolean) -> ()): RBXScriptConnection
	return touchInputChanged.Event:Connect(callback)
end

-- 安全な範囲（Roblox のトップバーと、端末のノッチやホームバーを除いた範囲）。IgnoreGuiInset でない ScreenGui の中身が
-- 置かれる範囲で、小さい画面か（ReplicatedStorage.Shared.SmallScreen）はこの大きさで決める。
-- 窓口の SetScreenSize が Player の Attribute（SmallScreen.SIZE_ATTRIBUTE）に仮の大きさを書いたら、その大きさを使う
-- （Studio でスマホの配置を確かめる用。小さい画面の配置は、安全な範囲の左上からその大きさの中に並ぶ）
local safeAreaProbe: ScreenGui? = nil
local safeAreaChanged = Instance.new("BindableEvent")

-- 入力がタッチとキーボード・ゲームパッドの間で切り替わったときも、各画面のスマホ配置を決め直す。
touchInputChanged.Event:Connect(function()
	safeAreaChanged:Fire()
end)

-- 安全な範囲の大きさを測る、中身の無い ScreenGui。初めて使うときに作る
local function getSafeAreaProbe(): ScreenGui
	local probe = safeAreaProbe
	if probe then
		return probe
	end
	local created = Ui.screenGui("SafeArea", 0)
	created:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		safeAreaChanged:Fire()
	end)
	Players.LocalPlayer:GetAttributeChangedSignal(SmallScreen.SIZE_ATTRIBUTE):Connect(function()
		safeAreaChanged:Fire()
	end)
	safeAreaProbe = created
	return created
end

-- 安全な範囲の大きさ（窓口の SetScreenSize で決めた仮の大きさがあれば、その大きさ）
function Ui.safeAreaSize(): Vector2
	local override = Players.LocalPlayer:GetAttribute(SmallScreen.SIZE_ATTRIBUTE)
	if typeof(override) == "Vector2" then
		return override
	end
	return getSafeAreaProbe().AbsoluteSize
end

-- 小さい画面でタッチを使っているか（スマホ横画面の配置にするか）
function Ui.isSmallScreen(): boolean
	local size = Ui.safeAreaSize()
	return SmallScreen.useCompactLayout(size.X, size.Y, touchInput)
end

-- 安全な範囲の大きさかタッチ入力が変わったとき（窓口で仮の大きさを決めたときも）に呼ぶ
function Ui.onSafeAreaChanged(callback: () -> ()): RBXScriptConnection
	getSafeAreaProbe()
	return safeAreaChanged.Event:Connect(callback)
end

-- 幕で画面全体を覆う画面（タイトル画面・特技ツリーの窓・リザルト）の、中身を置く範囲を切り替える。
-- safe なら、中身を安全な範囲に置き（小さい画面。トップバーとノッチに掛けない）、幕は画面の外まで広げて全体を覆う。
-- safe でなければ、今までどおり画面全体（IgnoreGuiInset）に置き、幕も画面全体にする
local BACKDROP_BLEED = 200
function Ui.useSafeArea(screen: ScreenGui, backdrop: GuiObject, safe: boolean)
	screen.IgnoreGuiInset = not safe
	-- 安全な範囲の外へ広げた幕を、ノッチの側で切らない
	screen.ClipToDeviceSafeArea = not safe
	backdrop.Position = if safe then UDim2.fromOffset(-BACKDROP_BLEED, -BACKDROP_BLEED) else UDim2.new()
	backdrop.Size = if safe then UDim2.new(1, BACKDROP_BLEED * 2, 1, BACKDROP_BLEED * 2) else UDim2.fromScale(1, 1)
end

-- object（AutomaticSize の Y で高さが文の長さで決まる部品）を、limit が返す高さに収まるよう UIScale（FitScale）で縮める。
-- limit は収める高さと縮めてよい倍率の下限（SmallScreen.minScale）を返す。高さが nil なら縮めない。
-- 部品の大きさが変わるたびに決め直す。返り値は、limit の値が変わったとき（配置を変えたとき）に呼ぶ決め直しの関数
function Ui.fitHeight(object: GuiObject, limit: () -> (number?, number)): () -> ()
	local scaler = Ui.create("UIScale", { Name = "FitScale", Parent = object }) :: UIScale
	local function refresh()
		local maxHeight, minScale = limit()
		local scale = 1
		if maxHeight then
			-- AbsoluteSize は縮めた後の大きさなので、今の倍率で割って縮める前の高さにする
			scale = SmallScreen.fitScale(object.AbsoluteSize.Y / scaler.Scale, maxHeight, minScale)
		end
		-- 測り直した高さの端数で倍率が行き来しないよう、小さな違いでは変えない
		if math.abs(scaler.Scale - scale) > 1e-3 then
			scaler.Scale = scale
		end
	end
	object:GetPropertyChangedSignal("AbsoluteSize"):Connect(refresh)
	refresh()
	return refresh
end

return Ui
