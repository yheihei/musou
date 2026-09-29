--!strict
-- プレイヤーの行動の状態遷移。Remotes.Action の入力を受け、行動の開始・先行入力・終了と、被弾による中断を扱う。
-- 状態遷移は ReplicatedStorage.Shared.ActionState が計算し、タイムラインは Config.luau の Action 節にある。
-- 攻撃の中身は CombatService が register で行動ごとに登録する。被ダメージの窓口は DamageService にある。
-- 敵のサービスが被ダメージの窓口を呼び、CombatService が敵を攻撃できるよう、ここは敵のサービスを require しない。
--
-- - 行動と引数は Actions.validate で確かめ、不正な値は捨てる
-- - 行動を始めるたびに、キャラクターの Attribute の Action・ActionStep・ActionStartedAt を書く
-- - 被弾の反応の最中は、歩き・ジャンプ・向きの変更を止める

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")

local ActionState = require(ReplicatedStorage.Shared.ActionState)
local Actions = require(ReplicatedStorage.Shared.Actions)
local Config = require(ReplicatedStorage.Shared.Config)
local DebugCommand = require(script.Parent.Parent.DebugCommand)
local PlayerService = require(script.Parent.PlayerService)

export type Handler = {
	-- 行動を始めるときのタイムライン。始められないなら nil を返し、入力は捨てる
	timeline: (player: Player, t: number) -> ActionState.Timeline?,
	-- 状態遷移が行動を始めたときに呼ぶ。Attribute の ActionStep に書く段を返せる
	begin: (player: Player, t: number, timeline: ActionState.Timeline) -> number?,
}

-- 行動の最中に止める動き
type Lock = {
	walk: boolean,
	jump: boolean,
	turn: boolean,
}

local ActionService = {}

local started = Instance.new("BindableEvent")
-- 行動を始めたとき（被弾の反応を含む）に、プレイヤー・行動・時刻で発火する
ActionService.started = started.Event

local handlers: { [string]: Handler } = {}
local machines: { [Player]: ActionState.State } = {}

-- 被弾の反応の行動。入力からは始めず、interrupt と続き（Next）で始める
local REACTIONS: { [string]: ActionState.Timeline } = {
	Flinch = Config.Action.Flinch,
	Down = Config.Action.Down,
	GetUp = Config.Action.GetUp,
}

local FULL_LOCK: Lock = { walk = true, jump = true, turn = true }
-- 最中に動きを止める行動。載っていない行動は何も止めない
local LOCKS: { [string]: Lock } = {
	Flinch = FULL_LOCK,
	Down = FULL_LOCK,
	GetUp = FULL_LOCK,
}

-- 行動の時刻。クライアントと同じ時計で Attribute に書く
function ActionService.now(): number
	return workspace:GetServerTimeNow()
end

-- 行動の中身を登録する。同じ行動は1回だけ
function ActionService.register(action: string, handler: Handler)
	assert(handlers[action] == nil, `ActionService: {action} は登録済み`)
	handlers[action] = handler
end

-- 今の行動と、それを始めた時刻。待機なら nil と 0
function ActionService.current(player: Player): (string?, number)
	local machine = machines[player]
	if not machine or machine.action == nil then
		return nil, 0
	end
	return machine.action, machine.startedAt
end

-- 被弾の反応（のけぞり・ダウン・起き上がり）の行動か
function ActionService.isReaction(action: string?): boolean
	return action ~= nil and REACTIONS[action] ~= nil
end

local function getHumanoid(player: Player): Humanoid?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return humanoid
end

-- 今の行動をキャラクターの Attribute に書く。待機に戻ったときは action を nil にする
local function publish(player: Player, action: string?, step: number?, t: number)
	local character = player.Character
	if not character then
		return
	end
	character:SetAttribute("Action", action)
	character:SetAttribute("ActionStep", step)
	character:SetAttribute("ActionStartedAt", t)
end

-- 行動に合わせて歩き・ジャンプ・向きの変更を止め、待機に戻ったら元に戻す
local function applyLock(player: Player, action: string?)
	local humanoid = getHumanoid(player)
	if not humanoid then
		return
	end
	local lock = if action then LOCKS[action] else nil
	humanoid.WalkSpeed = if lock and lock.walk then 0 else PlayerService.getStats(player).WalkSpeed
	humanoid.JumpHeight = if lock and lock.jump then 0 else StarterPlayer.CharacterJumpHeight
	humanoid.AutoRotate = not (lock and lock.turn)
end

local function onStarted(player: Player, action: string, t: number, timeline: ActionState.Timeline)
	local handler = handlers[action]
	local step = if handler then handler.begin(player, t, timeline) else nil
	publish(player, action, step, t)
	applyLock(player, action)
	started:Fire(player, action, t)
end

-- 行動を始めるときのタイムライン。被弾の反応は Config から、ほかは登録した中身から引く
local function timelineFor(player: Player, t: number): ActionState.TimelineOf
	return function(action: string): ActionState.Timeline?
		local reaction = REACTIONS[action]
		if reaction then
			return reaction
		end
		local handler = handlers[action]
		return if handler then handler.timeline(player, t) else nil
	end
end

-- 入力（無ければ nil）で状態を1つ進める
local function advance(player: Player, input: string?)
	local machine = machines[player]
	if not machine then
		return
	end
	local t = ActionService.now()
	local before = machine.action
	local next, startedAction = ActionState.step(machine, t, input, timelineFor(player, t))
	machines[player] = next
	if startedAction and next.timeline then
		onStarted(player, startedAction, t, next.timeline)
	elseif before ~= nil and next.action == nil then
		publish(player, nil, nil, t)
		applyLock(player, nil)
	end
end

-- 被弾の反応の行動を、今の行動と先行入力を捨てて始める
function ActionService.interrupt(player: Player, action: string)
	local timeline = REACTIONS[action]
	if not machines[player] or not timeline or not getHumanoid(player) then
		return
	end
	local t = ActionService.now()
	machines[player] = ActionState.interrupt(action, t, timeline)
	onStarted(player, action, t, timeline)
end

-- 受け取った行動をコンソールに出すか。窓口の LogAction で切り替える
local logActions = false

local function onAction(player: Player, action: unknown, argument: unknown)
	local valid = Actions.validate(action, argument)
	if logActions then
		print(`[Action] {player.Name} {tostring(action)} {tostring(argument)}{if valid then "" else " 拒否"}`)
	end
	if not valid then
		return
	end
	-- ガード・緊急回避・秘計は受け取るだけで、まだ何もしない（#56・#64・#93 で作る）
	if action == Actions.Guard or action == Actions.KinkyuKaihi or action == Actions.Hikei then
		return
	end
	if not getHumanoid(player) then
		return
	end
	advance(player, action :: string)
end

local function track(player: Player)
	machines[player] = ActionState.new()
	-- 出現し直したら待機から始める
	player.CharacterAdded:Connect(function()
		machines[player] = ActionState.new()
	end)
end

local function registerDebugCommands()
	DebugCommand.register(
		"Action",
		"<プレイヤー名> <行動> [引数]",
		"Remotes.Action と同じ処理に行動を渡す（Guard は true か false、KinkyuKaihi は x と z、Hikei は枚の番号）",
		function(name, action, first, second)
			local player = DebugCommand.findPlayer(name)
			local argument: any = first
			if action == Actions.Guard and type(first) == "string" then
				argument = first == "true"
			elseif action == Actions.KinkyuKaihi and typeof(first) ~= "Vector3" then
				argument = Vector3.new(DebugCommand.toNumber(first, "x"), 0, DebugCommand.toNumber(second, "z"))
			elseif action == Actions.Hikei and type(first) == "string" then
				argument = tonumber(first)
			end
			onAction(player, action, argument)
			local valid = Actions.validate(action, argument)
			return `{player.Name} の {tostring(action)} を{if valid then "受け付けた" else "拒否した"}`
		end
	)
	DebugCommand.register(
		"LogAction",
		"<true|false>",
		"受け取った行動をコンソールに出すかを切り替える",
		function(value)
			logActions = value == true or value == "true"
			return `受け取った行動の表示を{if logActions then "オン" else "オフ"}にした`
		end
	)
end

function ActionService.start()
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Action") :: RemoteEvent
	remote.OnServerEvent:Connect(onAction)
	registerDebugCommands()

	Players.PlayerAdded:Connect(track)
	for _, player in Players:GetPlayers() do
		track(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		machines[player] = nil
	end)

	-- 終わった行動を待機に戻し、続きの行動と先行入力を始める
	RunService.Heartbeat:Connect(function()
		for player, machine in machines do
			if machine.action ~= nil or machine.buffered ~= nil then
				advance(player, nil)
			end
		end
	end)
end

return ActionService
