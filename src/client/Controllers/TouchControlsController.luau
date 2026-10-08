--!strict
-- スマホ横画面の戦闘の操作ボタン（タッチの操作）。画面の右下に通常攻撃・チャージ攻撃・ガード・奥義のボタンを、
-- 左上（撃破数の下）に持ち込んだ秘計の枚のボタンを出し、押した入力を InputController の行動の入口へ渡す
-- （サーバーへは Remotes.Action だけを送り、行動を出せるかはサーバーが決める）。
-- 移動は Roblox 標準のサムスティック、ジャンプは標準のジャンプボタンを使い、ここでは作らない。
-- 出すかの判断は ReplicatedStorage.Shared.TouchControls、配置は ReplicatedStorage.Shared.TouchLayout、
-- 大きさは Config.luau の TouchControls 節にある。
--
-- - 出すのは、タッチで遊んでいる人のうち戦闘のフェーズの出撃メンバーだけ（画面上部の戦況と同じ条件）。
--   キーボードとマウスやゲームパッドに切り替えたら消す。Player の Attribute の TouchControls（窓口の SetTouchControls）で強制できる
-- - 出している間は Ui.setTouchLayout でタッチの配置にする（戦闘の画面を画面の大きさに合わせて縮め、
--   HUD の秘計の枚と操作の案内を隠し、撃破数を左上へ移す。台詞と秘計の知らせは配置の位置と倍率に置く）
-- - タッチで遊んでいるか（フェーズを問わない。TouchControls.isActive）を Ui.setTouchInput で知らせる
--   （イベントシーンのスキップのボタンなど、戦闘の外の画面が使う）
-- - ボタンは押した瞬間に送る。通常攻撃とガードは、押した指を離すまで続く（指がボタンの外へずれても続ける）。
--   ボタンを隠したら、押している指は離したことにする
-- - ガード中にサムスティックを倒すと緊急回避になる（InputController が Humanoid.MoveDirection から判定する。PC と同じ処理）
-- - 奥義のボタンにストックの本数を出し、0 本なら暗くする。秘計の枚は HUD と同じく名前を出し、使用済みの枚は暗くして
--   「使用済み」を出す。持ち込みの無い枚は出さない。暗いボタンも押せば送る（使えるかはサーバーが決める）
-- - 画面は横向きに固定する（PlayerGui.ScreenOrientation）
-- - テストプレイでの確認用に、ボタンは PlayerGui.TouchControls の Attack・ChargeKogeki・Guard・Ougi・Hikei1〜3（TextButton）で、
--   位置と大きさは AbsolutePosition・AbsoluteSize で読める

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Hikei = require(ReplicatedStorage.Shared.Hikei)
local TouchControls = require(ReplicatedStorage.Shared.TouchControls)
local TouchLayout = require(ReplicatedStorage.Shared.TouchLayout)
local PartyClient = require(script.Parent.Parent.PartyClient)
local Ui = require(script.Parent.Parent.Ui)
local EventSceneController = require(script.Parent.EventSceneController)
local InputController = require(script.Parent.InputController)

local TouchControlsController = {}

local player = Players.LocalPlayer

-- InputController に渡す、押している入力の元
local SOURCE: InputController.Source = "Touch"
-- 背景の透明度。押していないとき、押している間、使えない見た目のとき（奥義のストックが無い・秘計を使った）
local IDLE_TRANSPARENCY = 0.3
local PRESSED_TRANSPARENCY = 0.05
local DIM_TRANSPARENCY = 0.65
-- 縁の太さ。押していないときと押している間
local IDLE_STROKE = 2
local PRESSED_STROKE = 4
-- 奥義のストックの本数の札の一辺（設計の大きさのピクセル）
local STOCK_BADGE = 34

-- ボタン1つ
type View = {
	button: TextButton,
	scaler: UIScale,
	stroke: UIStroke,
	-- 押している指（マウスの左ボタンも含む）
	touches: { [InputObject]: boolean },
	-- 使えない見た目にするか
	dimmed: boolean,
	onPress: () -> (),
	-- 離したときに呼ぶ（押している間続く操作だけ）
	onRelease: (() -> ())?,
}

-- 秘計の枚1つ
type HikeiCard = {
	view: View,
	name: TextLabel,
	used: TextLabel,
}

local screen: ScreenGui
local views: { View } = {}
local attack: View
local chargeKogeki: View
local guard: View
local ougi: View
local ougiStock: TextLabel
local hikeiCards: { HikeiCard } = {}
-- 収まらないと警告した画面の大きさ。同じ大きさで何度も警告しない
local warnedSize: Vector2? = nil

local function refreshLook(view: View)
	local pressed = next(view.touches) ~= nil
	view.button.BackgroundTransparency = if pressed
		then PRESSED_TRANSPARENCY
		elseif view.dimmed then DIM_TRANSPARENCY
		else IDLE_TRANSPARENCY
	view.button.TextColor3 = if view.dimmed and not pressed then Ui.Color.Disabled else Ui.Color.Text
	view.stroke.Color = if pressed then Ui.Color.Selected elseif view.dimmed then Ui.Color.Disabled else Ui.Color.Accent
	view.stroke.Thickness = if pressed then PRESSED_STROKE else IDLE_STROKE
end

-- 指を離した（離したことにする）。全部の指を離したら onRelease を呼ぶ
local function release(view: View, input: InputObject)
	if not view.touches[input] then
		return
	end
	view.touches[input] = nil
	if next(view.touches) == nil and view.onRelease then
		view.onRelease()
	end
	refreshLook(view)
end

local function isEnded(input: InputObject): boolean
	return input.UserInputState == Enum.UserInputState.End or input.UserInputState == Enum.UserInputState.Cancel
end

-- 押したら onPress を呼び、押した指を離すまで見張る。ボタンの外で離しても受け取れるよう、入力そのものの状態を見る
local function bind(view: View)
	view.button.InputBegan:Connect(function(input: InputObject)
		local kind = input.UserInputType
		if kind ~= Enum.UserInputType.Touch and kind ~= Enum.UserInputType.MouseButton1 then
			return
		end
		if view.touches[input] then
			return
		end
		local first = next(view.touches) == nil
		view.touches[input] = true
		if first then
			view.onPress()
		end
		refreshLook(view)
		-- 届くのが遅れて、もう離していることがある
		if isEnded(input) then
			release(view, input)
			return
		end
		local connection: RBXScriptConnection
		connection = input.Changed:Connect(function()
			if isEnded(input) then
				connection:Disconnect()
				release(view, input)
			end
		end)
	end)
end

-- ボタンを作る。round なら丸いボタンにする
local function newView(
	name: string,
	text: string,
	textSize: number,
	round: boolean,
	onPress: () -> (),
	onRelease: (() -> ())?
): View
	local stroke: UIStroke = Ui.create("UIStroke", {
		Color = Ui.Color.Accent,
		Thickness = IDLE_STROKE,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
	local scaler: UIScale = Ui.create("UIScale", { Name = "TouchScale" })
	local button: TextButton = Ui.create("TextButton", {
		Name = name,
		AutoButtonColor = false,
		Selectable = false,
		BackgroundColor3 = Ui.Color.Panel,
		BackgroundTransparency = IDLE_TRANSPARENCY,
		BorderSizePixel = 0,
		Font = Ui.Font.Heavy,
		TextSize = textSize,
		TextColor3 = Ui.Color.Text,
		TextStrokeTransparency = 0.5,
		Text = text,
		Parent = screen,
	}, {
		Ui.create("UICorner", { CornerRadius = if round then UDim.new(0.5, 0) else UDim.new(0, 10) }),
		stroke,
		scaler,
	})
	local view: View = {
		button = button,
		scaler = scaler,
		stroke = stroke,
		touches = {},
		dimmed = false,
		onPress = onPress,
		onRelease = onRelease,
	}
	bind(view)
	table.insert(views, view)
	return view
end

local function buildGui()
	screen = Ui.screenGui("TouchControls", Ui.Layer.TouchControls)
	screen.Enabled = false

	attack = newView("Attack", "攻撃", Ui.TextSize.Huge, true, function()
		InputController.pressAttack(SOURCE)
	end, function()
		InputController.releaseAttack(SOURCE)
	end)
	chargeKogeki = newView("ChargeKogeki", "チャージ", Ui.TextSize.Large, true, InputController.chargeKogeki)
	guard = newView("Guard", "ガード", Ui.TextSize.Large, true, function()
		InputController.pressGuard(SOURCE)
	end, function()
		InputController.releaseGuard(SOURCE)
	end)
	ougi = newView("Ougi", "奥義", Ui.TextSize.Large, true, InputController.ougi)
	-- 奥義のストックの本数の札。右上の角に重ねる
	ougiStock = Ui.text({
		Name = "Stock",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 4, 0, -4),
		Size = UDim2.fromOffset(STOCK_BADGE, STOCK_BADGE),
		BackgroundTransparency = 0,
		BackgroundColor3 = Ui.Color.GaugeFull,
		Font = Ui.Font.Heavy,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.5,
		Text = "0",
		Parent = ougi.button,
	})
	Ui.create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = ougiStock })

	for slot = 1, Hikei.MOCHIKOMI_MAX do
		local view = newView(`Hikei{slot}`, "", Ui.TextSize.Title, false, function()
			InputController.hikei(slot)
		end)
		view.button.Visible = false
		local name = Ui.text({
			Name = "HikeiName",
			Position = UDim2.fromOffset(6, 10),
			Size = UDim2.new(1, -12, 0, 44),
			Font = Ui.Font.Heavy,
			TextSize = Ui.TextSize.Title,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextStrokeTransparency = 0.5,
			Parent = view.button,
		})
		local used = Ui.text({
			Name = "Used",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 6, 1, -8),
			Size = UDim2.new(1, -12, 0, 24),
			Font = Ui.Font.Bold,
			TextColor3 = Ui.Color.Disabled,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = "使用済み",
			Visible = false,
			Parent = view.button,
		})
		table.insert(hikeiCards, { view = view, name = name, used = used })
	end
end

-- UserInputService.PreferredInput の名前。使えない Roblox では nil
local function preferredInputName(): string?
	local ok, value = pcall(function(): any
		return (UserInputService :: any).PreferredInput
	end)
	if ok and typeof(value) == "EnumItem" then
		return value.Name
	end
	return nil
end

local function deviceOf(): TouchControls.Device
	return {
		studio = RunService:IsStudio(),
		touchEnabled = UserInputService.TouchEnabled,
		keyboardEnabled = UserInputService.KeyboardEnabled,
		preferredInput = preferredInputName(),
		lastInputKind = Ui.inputKind(),
	}
end

-- ボタンを設計の大きさの位置 rect に置く。縮めた後の位置へ移し、大きさは UIScale で縮める
local function place(view: View, rect: TouchLayout.Rect, scale: number)
	view.scaler.Scale = scale
	view.button.Position = UDim2.fromOffset(rect.x * scale, rect.y * scale)
	view.button.Size = UDim2.fromOffset(rect.width, rect.height)
end

-- 画面の大きさから配置を決めてボタンを置き、配置を返す
local function applyLayout(): TouchLayout.Layout
	local size = screen.AbsoluteSize
	local layout = TouchLayout.compute(size.X, size.Y)
	place(attack, layout.attack, layout.scale)
	place(chargeKogeki, layout.chargeKogeki, layout.scale)
	place(guard, layout.guard, layout.scale)
	place(ougi, layout.ougi, layout.scale)
	for slot, card in hikeiCards do
		place(card.view, layout.hikei[slot], layout.scale)
	end
	if not layout.fits and size.X > 0 and size.Y > 0 and warnedSize ~= size then
		warnedSize = size
		warn(`TouchControlsController: タッチの操作ボタンが画面（{size.X}x{size.Y}）に収まらない`)
	end
	return layout
end

-- 押している指を全部離したことにする
local function releaseAll()
	for _, view in views do
		if next(view.touches) == nil then
			continue
		end
		table.clear(view.touches)
		if view.onRelease then
			view.onRelease()
		end
		refreshLook(view)
	end
end

-- 出すかを決め直し、出すならボタンを置き直してタッチの配置にする。タッチで遊んでいるか（フェーズを問わない）も
-- Ui.setTouchInput で知らせる（イベントシーンのスキップのボタンなど、戦闘の外の画面が使う）。
-- 渡される PartyState は、続けて届いたときに最新でないことがあるので、最新の写しで決める
local function refresh()
	local state = PartyClient.get()
	local me = PartyClient.me()
	local mode = TouchControls.modeOf(player:GetAttribute(TouchControls.ATTRIBUTE))
	local device = deviceOf()
	local shown = TouchControls.isShown(
		mode,
		device,
		if state then state.phase else nil,
		me == nil or me.waiting,
		EventSceneController.isPlaying()
	)
	local layout = applyLayout()
	if not shown then
		releaseAll()
	end
	screen.Enabled = shown
	Ui.setTouchInput(TouchControls.isActive(mode, device))
	Ui.setTouchLayout(shown, layout)
end

-- 奥義のボタンにストックの本数を出し、0 本なら暗くする
local function refreshOugi()
	local value = player:GetAttribute("OugiStock")
	local stock = if type(value) == "number" then value else 0
	ougiStock.Text = tostring(stock)
	ougiStock.BackgroundColor3 = if stock > 0 then Ui.Color.GaugeFull else Ui.Color.Disabled
	ougi.dimmed = stock <= 0
	refreshLook(ougi)
end

-- 持ち込んだ秘計の枚に名前を出す。使用済みの枚は暗くして「使用済み」を出し、持ち込みの無い枚は隠す
local function refreshHikei()
	local mochikomi = Hikei.decodeList(player:GetAttribute(Hikei.MOCHIKOMI_ATTRIBUTE))
	local used = Hikei.decodeList(player:GetAttribute(Hikei.USED_ATTRIBUTE))
	for slot, card in hikeiCards do
		local id = mochikomi[slot]
		local definition = if id then Hikei.get(id) else nil
		card.view.button.Visible = definition ~= nil
		if definition then
			local isUsed = table.find(used, definition.id) ~= nil
			card.name.Text = definition.displayName
			card.name.TextColor3 = if isUsed then Ui.Color.Disabled else Ui.Color.Text
			card.used.Visible = isUsed
			card.view.dimmed = isUsed
			refreshLook(card.view)
		end
	end
end

-- 画面を横向きに固定する（向きを変えられるスマホで縦にしない）
local function lockLandscape()
	local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
	playerGui.ScreenOrientation = Enum.ScreenOrientation.LandscapeSensor
end

function TouchControlsController.start()
	buildGui()
	lockLandscape()

	PartyClient.changed:Connect(refresh)
	EventSceneController.started:Connect(refresh)
	EventSceneController.stopped:Connect(refresh)
	player:GetAttributeChangedSignal(TouchControls.ATTRIBUTE):Connect(refresh)
	Ui.onInputKindChanged(refresh)
	-- PreferredInput の無い Roblox では、変化の通知を作れない（最後の入力の種類の変化で決め直す）
	local ok, signal = pcall(function()
		return UserInputService:GetPropertyChangedSignal("PreferredInput")
	end)
	if ok then
		signal:Connect(refresh)
	end
	screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(refresh)

	-- 指を離した通知を、ボタンの見張りとは別にも受け、押したままにならないようにする
	UserInputService.TouchEnded:Connect(function(input)
		for _, view in views do
			release(view, input)
		end
	end)

	player:GetAttributeChangedSignal("OugiStock"):Connect(refreshOugi)
	player:GetAttributeChangedSignal(Hikei.MOCHIKOMI_ATTRIBUTE):Connect(refreshHikei)
	player:GetAttributeChangedSignal(Hikei.USED_ATTRIBUTE):Connect(refreshHikei)
	refreshOugi()
	refreshHikei()
	refresh()
end

return TouchControlsController
