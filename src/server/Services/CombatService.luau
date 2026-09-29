--!strict
-- プレイヤーの攻撃処理。クライアントからは「何をしたいか」だけを受け取り、
-- 行動の状態遷移・コンボ段数・当たり判定はすべてサーバーで決める。
-- 行動と引数は Actions.validate で確かめ、不正な値は捨てる。
-- 状態遷移は ReplicatedStorage.Shared.ActionState が計算し、タイムラインは Config.luau の Action 節にある。
-- 行動を始めるたびに、キャラクターの Attribute の Action・ActionStep・ActionStartedAt を書く。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ActionState = require(ReplicatedStorage.Shared.ActionState)
local Actions = require(ReplicatedStorage.Shared.Actions)
local Config = require(ReplicatedStorage.Shared.Config)
local HitShape = require(ReplicatedStorage.Shared.HitShape)
local DebugCommand = require(script.Parent.Parent.DebugCommand)
local EnemyService = require(script.Parent.EnemyService)
local PlayerService = require(script.Parent.PlayerService)
local Hitbox = require(script.Parent.Parent.Combat.Hitbox)
local Vfx = require(script.Parent.Parent.Combat.Vfx)

type CombatState = {
	machine: ActionState.State,
	-- 最後に出した通常攻撃の段と、その開始時刻
	comboIndex: number,
	lastAttackAt: number,
}

local CombatService = {}

local states: { [Player]: CombatState } = {}

local SLASH_COLOR = Color3.fromRGB(255, 230, 150)
local CHARGE_KOGEKI_COLOR = Color3.fromRGB(120, 200, 255)
local OUGI_COLOR = Color3.fromRGB(255, 90, 40)

-- 行動の時刻。クライアントと同じ時計で Attribute に書く
local function now(): number
	return workspace:GetServerTimeNow()
end

local function getRoot(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function knockbackFrom(origin: Vector3, target: Model, force: number): Vector3
	local direction = target:GetPivot().Position - origin
	direction = Vector3.new(direction.X, 0, direction.Z)
	if direction.Magnitude < 0.01 then
		direction = Vector3.new(0, 0, -1)
	end
	return direction.Unit * force + Vector3.new(0, force * 0.3, 0)
end

local function hitOne(player: Player, origin: Vector3, model: Model, damage: number, knockback: number)
	if EnemyService.damage(model, damage, player, knockbackFrom(origin, model, knockback)) then
		Vfx.hit(model)
		PlayerService.addOugiGauge(player, Config.Ougi.GainPerHit)
	end
end

-- 形に入った敵に当てる。飛び道具のように時間差のある当たりは、その秒数だけ遅らせる
local function hitAll(player: Player, root: BasePart, shape: HitShape.Shape, damage: number, knockback: number)
	local origin = Hitbox.originOf(root)
	local position = root.Position
	for _, hit in Hitbox.query(shape, origin, EnemyService.getTargets()) do
		if hit.delay > 0 then
			task.delay(hit.delay, hitOne, player, position, hit.ref, damage, knockback)
		else
			hitOne(player, position, hit.ref, damage, knockback)
		end
	end
end

-- 次に出す通常攻撃の段。最後の段の後と、途切れる時間を超えた後は1段目に戻る
local function nextComboStep(state: CombatState, t: number): number
	if t - state.lastAttackAt > Config.Combo.ComboResetTime or state.comboIndex >= #Config.Combo.Steps then
		return 1
	end
	return state.comboIndex + 1
end

-- 行動を始めるときのタイムライン。始められない行動は nil
local function timelineFor(player: Player, state: CombatState, t: number): ActionState.TimelineOf
	return function(action: string): ActionState.Timeline?
		if action == Actions.Attack then
			return Config.Action.Attack[nextComboStep(state, t)]
		elseif action == Actions.ChargeKogeki then
			return Config.Action.ChargeKogeki
		elseif action == Actions.Ougi then
			if PlayerService.getOugiGauge(player) < Config.Ougi.MaxGauge then
				return nil
			end
			return Config.Action.Ougi
		end
		return nil
	end
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

-- 発生の時刻になったら fn を呼ぶ。それまでに別の行動に変わっていたら呼ばない
local function atStartup(player: Player, t: number, timeline: ActionState.Timeline, fn: () -> ())
	if timeline.Startup <= 0 then
		fn()
		return
	end
	task.delay(timeline.Startup, function()
		local state = states[player]
		if state and state.machine.startedAt == t then
			fn()
		end
	end)
end

local function doAttack(player: Player, root: BasePart, step: number)
	local combo = Config.Combo.Steps[step]
	Vfx.slash(root, combo.Range, combo.Width, SLASH_COLOR)
	local shape: HitShape.Shape =
		{ kind = "Box", range = combo.Range, width = combo.Width, height = Config.Hitbox.Height }
	hitAll(player, root, shape, combo.Damage, combo.Knockback)
end

local function doChargeKogeki(player: Player, root: BasePart)
	local chargeKogeki = Config.ChargeKogeki
	Vfx.ring(root.Position, chargeKogeki.Radius, CHARGE_KOGEKI_COLOR)
	hitAll(player, root, { kind = "Sphere", radius = chargeKogeki.Radius }, chargeKogeki.Damage, chargeKogeki.Knockback)
end

local function doOugi(player: Player)
	local ougi = Config.Ougi
	PlayerService.resetOugiGauge(player)

	local character = player.Character
	if character then
		character:SetAttribute("Invulnerable", true)
	end

	task.spawn(function()
		for _ = 1, ougi.Pulses do
			local root = getRoot(player)
			if not root then
				break
			end
			Vfx.ring(root.Position, ougi.Radius, OUGI_COLOR)
			local shape: HitShape.Shape = { kind = "Sphere", radius = ougi.Radius }
			for _, hit in Hitbox.query(shape, Hitbox.originOf(root), EnemyService.getTargets()) do
				local model = hit.ref
				if
					EnemyService.damage(
						model,
						ougi.DamagePerPulse,
						player,
						knockbackFrom(root.Position, model, ougi.Knockback)
					)
				then
					Vfx.hit(model)
				end
			end
			task.wait(ougi.PulseInterval)
		end

		if character then
			character:SetAttribute("Invulnerable", nil)
		end
	end)
end

-- 状態遷移が行動を始めたときに、その行動の中身を出す
local function begin(player: Player, state: CombatState, action: string, t: number)
	local root = getRoot(player)
	local timeline = state.machine.timeline
	if not root or not timeline then
		return
	end
	local step: number? = nil
	if action == Actions.Attack then
		local comboStep = nextComboStep(state, t)
		step = comboStep
		state.comboIndex = comboStep
		state.lastAttackAt = t
		atStartup(player, t, timeline, function()
			local current = getRoot(player)
			if current then
				doAttack(player, current, comboStep)
			end
		end)
	elseif action == Actions.ChargeKogeki then
		state.comboIndex = 0
		atStartup(player, t, timeline, function()
			local current = getRoot(player)
			if current then
				doChargeKogeki(player, current)
			end
		end)
	elseif action == Actions.Ougi then
		state.comboIndex = 0
		-- 奥義ゲージは入力を受け付けた時点で使う
		doOugi(player)
	end
	publish(player, action, step, t)
end

-- 入力（無ければ nil）で状態を1つ進める
local function advance(player: Player, state: CombatState, input: string?)
	local t = now()
	local before = state.machine.action
	local machine, started = ActionState.step(state.machine, t, input, timelineFor(player, state, t))
	state.machine = machine
	if started then
		begin(player, state, started, t)
	elseif before ~= nil and machine.action == nil then
		publish(player, nil, nil, t)
	end
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
	local state = states[player]
	if not state or not getRoot(player) then
		return
	end
	advance(player, state, action :: string)
end

local function track(player: Player)
	local state: CombatState = { machine = ActionState.new(), comboIndex = 0, lastAttackAt = -math.huge }
	states[player] = state
	-- 出現し直したら待機から始める
	player.CharacterAdded:Connect(function()
		state.machine = ActionState.new()
		state.comboIndex = 0
	end)
end

function CombatService.start()
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Action") :: RemoteEvent
	remote.OnServerEvent:Connect(onAction)

	DebugCommand.register(
		"ShowHitbox",
		"<true|false> [残す秒数]",
		"攻撃判定の形のデバッグ表示を切り替える",
		function(value, lifetime)
			local on = value == true or value == "true"
			local seconds = if lifetime ~= nil then DebugCommand.toNumber(lifetime, "残す秒数") else nil
			Hitbox.setShowShapes(on, seconds)
			return `攻撃判定の形の表示を{if on then "オン" else "オフ"}にした`
		end
	)

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

	Players.PlayerAdded:Connect(track)
	for _, player in Players:GetPlayers() do
		track(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)

	-- 終わった行動を待機に戻し、先行入力を受付の開始と同時に出す
	RunService.Heartbeat:Connect(function()
		for player, state in states do
			if state.machine.action ~= nil or state.machine.buffered ~= nil then
				advance(player, state, nil)
			end
		end
	end)
end

return CombatService
