--!strict
-- プレイヤーの行動の状態遷移。Remotes.Action の入力を受け、行動の開始・先行入力・終了と、被弾による中断を扱う。
-- 状態遷移は ReplicatedStorage.Shared.ActionState が計算し、タイムラインは Config.luau の Action 節にある。
-- 攻撃の中身は CombatService が register で行動ごとに登録する。被ダメージの窓口は DamageService にある。
-- 敵のサービスが被ダメージの窓口を呼び、CombatService が敵を攻撃できるよう、ここは敵のサービスを require しない。
--
-- - 行動と引数は Actions.validate で確かめ、不正な値は捨てる
-- - 行動を始めるたびに、キャラクターの Attribute の Action・ActionStep・ActionDuration・ActionStartedAt を書く。
--   クライアントのモーションの再生は、最後に書く ActionStartedAt の変化を見て残りを読む
-- - 攻撃の最中はジャンプを、奥義・ガード・被弾の反応の最中は歩き・ジャンプ・向きの変更を止める
-- - 空中の通常攻撃はジャンプ攻撃（JumpAttack）にし、空中のチャージ攻撃は捨てる
-- - ガードは押している間続き、離すと終わる。攻撃の最中に押したガードはキャンセル受付から始まる。
--   ほかの行動が終わったときにまだ押していれば、ガードに戻る
-- - 緊急回避はガードの最中だけ出せ、入れた方向へサーバーの拘束で動かす。続けて出すほど後隙が伸びる
--   （計算は ReplicatedStorage.Shared.KinkyuKaihi）
-- - イベントシーンのフェーズの間は行動を受け付けない。ガードを離す入力だけは受け、押したままにならないようにする

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ActionState = require(ReplicatedStorage.Shared.ActionState)
local Actions = require(ReplicatedStorage.Shared.Actions)
local Config = require(ReplicatedStorage.Shared.Config)
local KinkyuKaihi = require(ReplicatedStorage.Shared.KinkyuKaihi)
local DebugCommand = require(script.Parent.Parent.DebugCommand)
local PartyService = require(script.Parent.PartyService)
local PlayerService = require(script.Parent.PlayerService)
local Push = require(script.Parent.Parent.Combat.Push)

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

-- 空中の通常攻撃から始める行動。入力からは直接始めない
ActionService.JumpAttack = "JumpAttack"

local started = Instance.new("BindableEvent")
-- 行動を始めたとき（被弾の反応を含む）に、プレイヤー・行動・時刻で発火する
ActionService.started = started.Event

local handlers: { [string]: Handler } = {}
local machines: { [Player]: ActionState.State } = {}
-- ガードのボタンを押しているか
local guardHeld: { [Player]: boolean } = {}
-- 緊急回避で動く水平の向きと、続けて出した回数
local kaihiDirections: { [Player]: Vector3 } = {}
local kaihiChains: { [Player]: KinkyuKaihi.Chain } = {}

-- 被弾の反応の行動。入力からは始めず、interrupt と続き（Next）で始める
local REACTIONS: { [string]: ActionState.Timeline } = {
	Flinch = Config.Action.Flinch,
	Down = Config.Action.Down,
	GetUp = Config.Action.GetUp,
	GuardHit = Config.Action.GuardHit,
}

-- ガード。離すまで続き、始めから次の行動（攻撃や奥義）を受け付ける
local GUARD: ActionState.Timeline = { Startup = 0, Active = math.huge, Recovery = 0, CancelFrom = 0, Advance = 0 }

local FULL_LOCK: Lock = { walk = true, jump = true, turn = true }
local JUMP_LOCK: Lock = { walk = false, jump = true, turn = false }
-- 最中に動きを止める行動。載っていない行動は何も止めない
local LOCKS: { [string]: Lock } = {
	Attack = JUMP_LOCK,
	ChargeKogeki = JUMP_LOCK,
	JumpAttack = JUMP_LOCK,
	Ougi = FULL_LOCK,
	Guard = FULL_LOCK,
	GuardHit = FULL_LOCK,
	KinkyuKaihi = FULL_LOCK,
	Flinch = FULL_LOCK,
	Down = FULL_LOCK,
	GetUp = FULL_LOCK,
}

-- 空中にいるとみなす Humanoid の状態。クライアントの状態がサーバーへ複製される
local AIR_STATES: { [Enum.HumanoidStateType]: boolean } = {
	[Enum.HumanoidStateType.Jumping] = true,
	[Enum.HumanoidStateType.Freefall] = true,
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

-- 被弾の反応（のけぞり・ダウン・起き上がり・ガードで受けた硬直）の行動か
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

-- ジャンプや落下で空中にいるか
function ActionService.isAirborne(player: Player): boolean
	local humanoid = getHumanoid(player)
	return humanoid ~= nil and AIR_STATES[humanoid:GetState()] == true
end

-- 今の行動をキャラクターの Attribute に書く。待機に戻ったときは action を nil にする。
-- duration は行動の長さ（秒）で、終わりの決まっていない行動（ガード）は nil。ActionStartedAt は最後に書く
local function publish(player: Player, action: string?, step: number?, t: number, duration: number?)
	local character = player.Character
	if not character then
		return
	end
	character:SetAttribute("Action", action)
	character:SetAttribute("ActionStep", step)
	character:SetAttribute("ActionDuration", duration)
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
	humanoid.JumpHeight = if lock and lock.jump then 0 else Config.Jump.Height
	humanoid.AutoRotate = not (lock and lock.turn)
end

local function chainOf(player: Player): KinkyuKaihi.Chain
	return kaihiChains[player] or KinkyuKaihi.newChain()
end

-- 緊急回避を始める。動いている間に入れた方向へ前進量だけ動かし、Attribute の ActionStep に続けた回数を書く
local function beginKinkyuKaihi(player: Player, t: number, timeline: ActionState.Timeline): number
	local chain = KinkyuKaihi.record(chainOf(player), t)
	kaihiChains[player] = chain
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local direction = kaihiDirections[player]
	if root and direction then
		Push.move(root, direction, timeline.Advance, timeline.Active)
	end
	return chain.count
end

local function onStarted(player: Player, action: string, t: number, timeline: ActionState.Timeline)
	local handler = handlers[action]
	local step = if handler then handler.begin(player, t, timeline) else nil
	if action == Actions.KinkyuKaihi then
		step = beginKinkyuKaihi(player, t, timeline)
	end
	local duration = ActionState.duration(timeline)
	publish(player, action, step, t, if duration < math.huge then duration else nil)
	applyLock(player, action)
	started:Fire(player, action, t)
end

-- 行動を始めるときのタイムライン。被弾の反応は Config から、ガードはここで、ほかは登録した中身から引く
local function timelineFor(player: Player, t: number): ActionState.TimelineOf
	return function(action: string): ActionState.Timeline?
		local reaction = REACTIONS[action]
		if reaction then
			return reaction
		end
		if action == Actions.Guard then
			-- 空中では始めない。押したままなら着地した後に始まる
			if not guardHeld[player] or ActionService.isAirborne(player) then
				return nil
			end
			return GUARD
		elseif action == Actions.KinkyuKaihi then
			-- ガードの最中だけ出せる
			local machine = machines[player]
			if not machine or machine.action ~= Actions.Guard or not kaihiDirections[player] then
				return nil
			end
			return KinkyuKaihi.timeline(KinkyuKaihi.nextCount(chainOf(player), t))
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

-- ガードを離す。ガードの最中なら待機に戻し、先行入力のガードは捨てる
local function releaseGuard(player: Player)
	guardHeld[player] = false
	local machine = machines[player]
	if not machine then
		return
	end
	local next = ActionState.finish(machine, Actions.Guard)
	machines[player] = next
	if machine.action == Actions.Guard and next.action == nil then
		publish(player, nil, nil, ActionService.now())
		applyLock(player, nil)
	end
end

-- ガードを押している間か
function ActionService.isGuardHeld(player: Player): boolean
	return guardHeld[player] == true
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
	local releasing = action == Actions.Guard and argument == false
	if PartyService.getPhase() == "EventScene" and not releasing then
		return
	end
	-- 秘計は受け取るだけで、まだ何もしない（#93 で作る）
	if action == Actions.Hikei then
		return
	end
	if releasing then
		releaseGuard(player)
		return
	end
	if not getHumanoid(player) then
		return
	end
	if action == Actions.Guard then
		guardHeld[player] = true
	elseif action == Actions.KinkyuKaihi then
		kaihiDirections[player] = Actions.horizontal(argument :: any)
	end
	local input = action :: string
	if ActionService.isAirborne(player) then
		if input == Actions.ChargeKogeki then
			return
		elseif input == Actions.Attack then
			input = ActionService.JumpAttack
		end
	end
	advance(player, input)
end

local function track(player: Player)
	machines[player] = ActionState.new()
	-- 出現し直したら待機から始める
	player.CharacterAdded:Connect(function()
		machines[player] = ActionState.new()
		guardHeld[player] = false
		kaihiChains[player] = nil
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
		guardHeld[player] = nil
		kaihiDirections[player] = nil
		kaihiChains[player] = nil
	end)

	-- 終わった行動を待機に戻し、続きの行動と先行入力を始める。待機でガードを押したままならガードに戻る
	RunService.Heartbeat:Connect(function()
		for player, machine in machines do
			if machine.action ~= nil or machine.buffered ~= nil then
				advance(player, nil)
			elseif guardHeld[player] and getHumanoid(player) then
				advance(player, Actions.Guard)
			end
		end
	end)
end

return ActionService
