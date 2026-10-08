--!strict
-- 入力をサーバーへの Remotes.Action に変換する。割り当ては ReplicatedStorage.Shared.InputMap にある。
-- クライアントは入力を送るだけで、行動を出せるかはサーバーが決める。
-- 行動を送る入口（pressAttack・releaseAttack・pressGuard・releaseGuard・chargeKogeki・ougi・hikei）は、
-- キーとゲームパッド（ContextActionService）と、タッチの操作ボタン（TouchControlsController）の両方から呼ぶ。
--
-- - 通常攻撃は押しっぱなしで連打扱いにする。実際の攻撃間隔はサーバーが決める
-- - 通常攻撃とガードは、押している入力の元（キーとタッチのボタン）ごとに覚え、全部を離すまで続ける
-- - 右クリックは、ドラッグせずに離したときだけ送る（右ドラッグはカメラの回転に使う）
-- - ガードは押したときと離したときに送り、ガード中に方向を入れ始めたら緊急回避を送る。方向は Humanoid.MoveDirection から
--   読むので、キー・スティック・タッチのサムスティックのどれで方向を入れても同じに出る
-- - タッチの操作ボタンは TouchControlsController が出す。ジャンプは Roblox 標準の入力（Space・A・標準のジャンプボタン）のまま
-- - 秘計の 1〜3 キーと重なる道具の持ち物欄は消す
-- - setEnabled(false) の間（イベントシーンの再生中）は何も送らない。止めるときに押していた通常攻撃とガードは離したことにする

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Actions = require(ReplicatedStorage.Shared.Actions)
local InputMap = require(ReplicatedStorage.Shared.InputMap)

local InputController = {}

-- 押しっぱなしの通常攻撃を送り直す間隔（秒）
local HOLD_REPEAT_INTERVAL = 0.1
-- 右クリックとみなすマウスの移動量（ピクセル）と押している時間（秒）の上限
local CLICK_MAX_MOVE = 6
local CLICK_MAX_TIME = 0.35
-- 方向入力の大きさがこれを超えたら、方向を入れ始めたとみなす
local DIRECTION_THRESHOLD = 0.5

local RIGHT_CLICK = "UserInputType.MouseButton2"

-- 押している入力の元。Key はキーとゲームパッド、Touch はタッチの操作ボタン
export type Source = "Key" | "Touch"

local remote: RemoteEvent
-- 通常攻撃とガードを押している入力の元
local attackHolders: { [Source]: boolean } = {}
local guardHolders: { [Source]: boolean } = {}
-- 押しっぱなしの通常攻撃を送り直すループの番号。押し直したら前のループを止める
local attackLoop = 0
-- 入力を送るか。イベントシーンの再生中は false
local enabled = true

type InputEnum = Enum.KeyCode | Enum.UserInputType

local function send(action: Actions.Action, argument: any?)
	if enabled then
		remote:FireServer(action, argument)
	end
end

local function isHeld(holders: { [Source]: boolean }): boolean
	return next(holders) ~= nil
end

-- 通常攻撃を押す。どれかの入力の元で押している間、HOLD_REPEAT_INTERVAL ごとに送り直す
function InputController.pressAttack(source: Source)
	local wasHeld = isHeld(attackHolders)
	attackHolders[source] = true
	if wasHeld then
		return
	end
	attackLoop += 1
	local loop = attackLoop
	task.spawn(function()
		while loop == attackLoop and isHeld(attackHolders) do
			send(Actions.Attack)
			task.wait(HOLD_REPEAT_INTERVAL)
		end
	end)
end

-- 通常攻撃を離す
function InputController.releaseAttack(source: Source)
	attackHolders[source] = nil
end

-- ガードを押す。どれかの入力の元で押し始めたときに送る
function InputController.pressGuard(source: Source)
	local wasHeld = isHeld(guardHolders)
	guardHolders[source] = true
	if not wasHeld then
		send(Actions.Guard, true)
	end
end

-- ガードを離す。全部の入力の元で離したときに送る
function InputController.releaseGuard(source: Source)
	if not guardHolders[source] then
		return
	end
	guardHolders[source] = nil
	if not isHeld(guardHolders) then
		send(Actions.Guard, false)
	end
end

function InputController.chargeKogeki()
	send(Actions.ChargeKogeki)
end

function InputController.ougi()
	send(Actions.Ougi)
end

-- 秘計の枚を切る。slot は枚の番号
function InputController.hikei(slot: number)
	send(Actions.Hikei, slot)
end

-- 入力を送るかを切り替える。止めるときは、押しっぱなしの通常攻撃をやめ、押していたガードは離したことにする
function InputController.setEnabled(value: boolean)
	if not value and enabled then
		table.clear(attackHolders)
		if isHeld(guardHolders) then
			table.clear(guardHolders)
			remote:FireServer(Actions.Guard, false)
		end
	end
	enabled = value
end

-- 対応表の入力を Enum に直す。右クリックは別に扱うので、含まれていたかを2つ目に返す
local function toEnums(binding: InputMap.Binding): ({ InputEnum }, boolean)
	local enums: { InputEnum } = {}
	local rightClick = false
	for _, list in { binding.keyboard, binding.gamepad } do
		for _, input in list do
			if input == RIGHT_CLICK then
				rightClick = true
				continue
			end
			local kind, name = InputMap.parse(input)
			local ok, value = pcall(function(): any
				return (Enum :: any)[kind :: string][name :: string]
			end)
			if ok and value then
				table.insert(enums, value)
			else
				warn(`InputController: 対応表の入力 {input} は Enum に無い`)
			end
		end
	end
	return enums, rightClick
end

-- 右クリックでドラッグしなかったときに onClick を呼ぶ
local rightClickHandlers: { () -> () } = {}
local function watchRightClick()
	local pressedAt: number? = nil
	local moved = 0
	UserInputService.InputBegan:Connect(function(input, processed)
		if input.UserInputType == Enum.UserInputType.MouseButton2 and not processed then
			pressedAt = os.clock()
			moved = 0
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if pressedAt and input.UserInputType == Enum.UserInputType.MouseMovement then
			moved += input.Delta.Magnitude
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton2 or not pressedAt then
			return
		end
		local isClick = moved <= CLICK_MAX_MOVE and os.clock() - (pressedAt :: number) <= CLICK_MAX_TIME
		pressedAt = nil
		if isClick then
			for _, handler in rightClickHandlers do
				handler()
			end
		end
	end)
end

-- 押したときに1回だけ onPress を呼ぶ操作を割り当てる
local function bindPress(name: string, binding: InputMap.Binding, onPress: () -> ())
	local enums, rightClick = toEnums(binding)
	ContextActionService:BindAction(name, function(_, state)
		if state == Enum.UserInputState.Begin then
			onPress()
		end
		return Enum.ContextActionResult.Sink
	end, false, table.unpack(enums))
	if rightClick then
		table.insert(rightClickHandlers, onPress)
	end
end

local function bindAttack()
	local enums = toEnums(InputMap.Attack)
	ContextActionService:BindAction("Attack", function(_, state)
		if state == Enum.UserInputState.Begin then
			InputController.pressAttack("Key")
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			InputController.releaseAttack("Key")
		end
		-- マウスの左ボタンは画面の操作にも渡す
		return Enum.ContextActionResult.Pass
	end, false, table.unpack(enums))
end

local function bindGuard()
	local enums = toEnums(InputMap.Guard)
	ContextActionService:BindAction("Guard", function(_, state)
		if state == Enum.UserInputState.Begin then
			InputController.pressGuard("Key")
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			InputController.releaseGuard("Key")
		end
		return Enum.ContextActionResult.Sink
	end, false, table.unpack(enums))
end

-- ガード中に方向を入れ始めたら、その水平の方向で緊急回避を送る。
-- 方向は Humanoid.MoveDirection（移動の入力をカメラの向きでワールドの向きにしたもの）から読む。
-- キー・ゲームパッドのスティック・タッチのサムスティックのどれも、Roblox 標準の操作が MoveDirection に書く
local function watchKinkyuKaihi()
	local wasMoving = false
	RunService.RenderStepped:Connect(function()
		local character = Players.LocalPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local move = if humanoid then humanoid.MoveDirection else Vector3.zero
		local flat = Vector3.new(move.X, 0, move.Z)
		local moving = flat.Magnitude > DIRECTION_THRESHOLD
		if isHeld(guardHolders) and moving and not wasMoving then
			send(Actions.KinkyuKaihi, flat.Unit)
		end
		wasMoving = moving
	end)
end

-- 秘計の 1〜3 キーと重なるので、道具の持ち物欄（Backpack）を消す。このゲームは道具を使わない。
-- 読み込み直後は失敗することがあるので、通るまでやり直す
local function disableBackpack()
	for _ = 1, 20 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		end)
		if ok then
			return
		end
		task.wait(0.5)
	end
	warn("InputController: 持ち物欄を消せなかった")
end

function InputController.start()
	remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Action") :: RemoteEvent

	bindAttack()
	bindGuard()
	bindPress("ChargeKogeki", InputMap.ChargeKogeki, InputController.chargeKogeki)
	bindPress("Ougi", InputMap.Ougi, InputController.ougi)
	for slot, binding in InputMap.Hikei do
		bindPress(`Hikei{slot}`, binding, function()
			InputController.hikei(slot)
		end)
	end
	watchRightClick()
	watchKinkyuKaihi()
	task.spawn(disableBackpack)
end

return InputController
