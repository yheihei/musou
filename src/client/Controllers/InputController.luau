--!strict
-- 入力をサーバーへの Remotes.Action に変換する。割り当ては ReplicatedStorage.Shared.InputMap にある。
-- クライアントは入力を送るだけで、行動を出せるかはサーバーが決める。
--
-- - 通常攻撃は押しっぱなしで連打扱いにする。実際の攻撃間隔はサーバーが決める
-- - 右クリックは、ドラッグせずに離したときだけ送る（右ドラッグはカメラの回転に使う）
-- - ガードは押したときと離したときに送り、ガード中に方向を入れ始めたら緊急回避を送る
-- - タッチ用のボタンは出さない（スマホの操作は M2 で作る）
-- - 秘計の 1〜3 キーと重なる道具の持ち物欄は消す

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

local remote: RemoteEvent
local attackHeld = false
local guardHeld = false

type InputEnum = Enum.KeyCode | Enum.UserInputType

local function send(action: Actions.Action, argument: any?)
	remote:FireServer(action, argument)
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
			attackHeld = true
			task.spawn(function()
				while attackHeld do
					send(Actions.Attack)
					task.wait(HOLD_REPEAT_INTERVAL)
				end
			end)
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			attackHeld = false
		end
		-- マウスの左ボタンは画面の操作にも渡す
		return Enum.ContextActionResult.Pass
	end, false, table.unpack(enums))
end

local function bindGuard()
	local enums = toEnums(InputMap.Guard)
	ContextActionService:BindAction("Guard", function(_, state)
		if state == Enum.UserInputState.Begin and not guardHeld then
			guardHeld = true
			send(Actions.Guard, true)
		elseif (state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel) and guardHeld then
			guardHeld = false
			send(Actions.Guard, false)
		end
		return Enum.ContextActionResult.Sink
	end, false, table.unpack(enums))
end

-- ガード中に方向を入れ始めたら、その水平の方向で緊急回避を送る。
-- 方向は Humanoid.MoveDirection（移動の入力をカメラの向きでワールドの向きにしたもの）から読む
local function watchKinkyuKaihi()
	local wasMoving = false
	RunService.RenderStepped:Connect(function()
		local character = Players.LocalPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local move = if humanoid then humanoid.MoveDirection else Vector3.zero
		local flat = Vector3.new(move.X, 0, move.Z)
		local moving = flat.Magnitude > DIRECTION_THRESHOLD
		if guardHeld and moving and not wasMoving then
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
	bindPress("ChargeKogeki", InputMap.ChargeKogeki, function()
		send(Actions.ChargeKogeki)
	end)
	bindPress("Ougi", InputMap.Ougi, function()
		send(Actions.Ougi)
	end)
	for slot, binding in InputMap.Hikei do
		bindPress(`Hikei{slot}`, binding, function()
			send(Actions.Hikei, slot)
		end)
	end
	watchRightClick()
	watchKinkyuKaihi()
	task.spawn(disableBackpack)
end

return InputController
