--!strict
-- プレイヤーの攻撃処理。クライアントからは「何をしたいか」だけを受け取り、
-- クールダウン・コンボ段数・当たり判定はすべてサーバーで決める。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Actions = require(ReplicatedStorage.Shared.Actions)
local Config = require(ReplicatedStorage.Shared.Config)
local EnemyService = require(script.Parent.EnemyService)
local PlayerService = require(script.Parent.PlayerService)
local Hitbox = require(script.Parent.Parent.Combat.Hitbox)
local Vfx = require(script.Parent.Parent.Combat.Vfx)

type CombatState = {
	comboIndex: number,
	lastAttack: number,
	busyUntil: number,
	musouActive: boolean,
}

local CombatService = {}

local states: { [Player]: CombatState } = {}

local SLASH_COLOR = Color3.fromRGB(255, 230, 150)
local CHARGE_COLOR = Color3.fromRGB(120, 200, 255)
local MUSOU_COLOR = Color3.fromRGB(255, 90, 40)

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

local function hitAll(player: Player, origin: Vector3, targets: { Model }, damage: number, knockback: number)
	for _, model in targets do
		if EnemyService.damage(model, damage, player, knockbackFrom(origin, model, knockback)) then
			Vfx.hit(model)
			PlayerService.addMusou(player, Config.Musou.GainPerHit)
		end
	end
end

local function doAttack(player: Player, state: CombatState, root: BasePart, now: number)
	local steps = Config.Combo.Steps
	if now - state.lastAttack > Config.Combo.ComboResetTime or state.comboIndex >= #steps then
		state.comboIndex = 0
	end
	state.comboIndex += 1
	state.lastAttack = now

	local step = steps[state.comboIndex]
	state.busyUntil = now + step.Cooldown

	Vfx.slash(root, step.Range, step.Width, SLASH_COLOR)
	local targets = Hitbox.front(root, step.Range, step.Width, EnemyService.getFolder())
	hitAll(player, root.Position, targets, step.Damage, step.Knockback)
end

local function doCharge(player: Player, state: CombatState, root: BasePart, now: number)
	local charge = Config.Charge
	state.comboIndex = 0
	state.busyUntil = now + charge.Cooldown

	Vfx.ring(root.Position, charge.Radius, CHARGE_COLOR)
	local targets = Hitbox.sphere(root.Position, charge.Radius, EnemyService.getFolder())
	hitAll(player, root.Position, targets, charge.Damage, charge.Knockback)
end

local function doMusou(player: Player, state: CombatState, now: number)
	local musou = Config.Musou
	if PlayerService.getMusou(player) < musou.MaxGauge then
		return
	end

	PlayerService.resetMusou(player)
	state.musouActive = true
	state.comboIndex = 0
	state.busyUntil = now + musou.Pulses * musou.PulseInterval

	local character = player.Character
	if character then
		character:SetAttribute("Invulnerable", true)
	end

	task.spawn(function()
		for _ = 1, musou.Pulses do
			local root = getRoot(player)
			if not root then
				break
			end
			Vfx.ring(root.Position, musou.Radius, MUSOU_COLOR)
			local targets = Hitbox.sphere(root.Position, musou.Radius, EnemyService.getFolder())
			for _, model in targets do
				if
					EnemyService.damage(
						model,
						musou.DamagePerPulse,
						player,
						knockbackFrom(root.Position, model, musou.Knockback)
					)
				then
					Vfx.hit(model)
				end
			end
			task.wait(musou.PulseInterval)
		end

		state.musouActive = false
		if character then
			character:SetAttribute("Invulnerable", nil)
		end
	end)
end

local function onAction(player: Player, action: unknown)
	if not Actions.isValid(action) then
		return
	end
	local state = states[player]
	local root = getRoot(player)
	if not state or not root or state.musouActive then
		return
	end

	local now = os.clock()
	-- 無双乱舞は攻撃の硬直中でも割り込める
	if action == Actions.Musou then
		doMusou(player, state, now)
		return
	end
	if now < state.busyUntil then
		return
	end

	if action == Actions.Attack then
		doAttack(player, state, root, now)
	elseif action == Actions.Charge then
		doCharge(player, state, root, now)
	end
end

function CombatService.start()
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Action") :: RemoteEvent
	remote.OnServerEvent:Connect(onAction)

	local function track(player: Player)
		states[player] = { comboIndex = 0, lastAttack = 0, busyUntil = 0, musouActive = false }
	end
	Players.PlayerAdded:Connect(track)
	for _, player in Players:GetPlayers() do
		track(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
end

return CombatService
