--!strict
-- 入力をサーバーへの Action に変換する。
-- 通常攻撃は押しっぱなしで連打扱いにし、実際の攻撃間隔はサーバー側のクールダウンで決まる。

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Actions = require(ReplicatedStorage.Shared.Actions)

local InputController = {}

local HOLD_REPEAT_INTERVAL = 0.1

local remote: RemoteEvent
local attackHeld = false

local function onAttack(_name: string, state: Enum.UserInputState)
	if state == Enum.UserInputState.Begin then
		attackHeld = true
		task.spawn(function()
			while attackHeld do
				remote:FireServer(Actions.Attack)
				task.wait(HOLD_REPEAT_INTERVAL)
			end
		end)
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		attackHeld = false
	end
	return Enum.ContextActionResult.Pass
end

local function fireOnBegin(action: Actions.Action)
	return function(_name: string, state: Enum.UserInputState)
		if state == Enum.UserInputState.Begin then
			remote:FireServer(action)
		end
		return Enum.ContextActionResult.Sink
	end
end

function InputController.start()
	remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Action") :: RemoteEvent

	ContextActionService:BindAction(
		Actions.Attack,
		onAttack,
		true,
		Enum.UserInputType.MouseButton1,
		Enum.KeyCode.ButtonR2
	)
	ContextActionService:BindAction(
		Actions.ChargeKogeki,
		fireOnBegin(Actions.ChargeKogeki),
		true,
		Enum.KeyCode.E,
		Enum.KeyCode.ButtonX
	)
	ContextActionService:BindAction(Actions.Ougi, fireOnBegin(Actions.Ougi), true, Enum.KeyCode.Q, Enum.KeyCode.ButtonY)

	ContextActionService:SetTitle(Actions.Attack, "攻撃")
	ContextActionService:SetTitle(Actions.ChargeKogeki, "チャージ")
	ContextActionService:SetTitle(Actions.Ougi, "奥義")
end

return InputController
