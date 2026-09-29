--!strict
-- プレイヤーの攻撃の中身。通常攻撃・チャージ攻撃・奥義のタイムラインと判定を ActionService に登録する。
-- 入力の受け取りと行動の状態遷移は ActionService が持ち、コンボの段数と当たり判定はここで決める。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ActionState = require(ReplicatedStorage.Shared.ActionState)
local Actions = require(ReplicatedStorage.Shared.Actions)
local Config = require(ReplicatedStorage.Shared.Config)
local HitShape = require(ReplicatedStorage.Shared.HitShape)
local DebugCommand = require(script.Parent.Parent.DebugCommand)
local ActionService = require(script.Parent.ActionService)
local EnemyService = require(script.Parent.EnemyService)
local PlayerService = require(script.Parent.PlayerService)
local Hitbox = require(script.Parent.Parent.Combat.Hitbox)
local Vfx = require(script.Parent.Parent.Combat.Vfx)

-- 最後に出した通常攻撃の段と、その開始時刻
type ComboState = {
	comboIndex: number,
	lastAttackAt: number,
}

local CombatService = {}

local combos: { [Player]: ComboState } = {}

local SLASH_COLOR = Color3.fromRGB(255, 230, 150)
local CHARGE_KOGEKI_COLOR = Color3.fromRGB(120, 200, 255)
local OUGI_COLOR = Color3.fromRGB(255, 90, 40)

local function getRoot(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function comboOf(player: Player): ComboState
	local combo = combos[player]
	if not combo then
		combo = { comboIndex = 0, lastAttackAt = -math.huge }
		combos[player] = combo
	end
	return combo
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
local function nextComboStep(combo: ComboState, t: number): number
	if t - combo.lastAttackAt > Config.Combo.ComboResetTime or combo.comboIndex >= #Config.Combo.Steps then
		return 1
	end
	return combo.comboIndex + 1
end

-- 発生の時刻になったら fn を呼ぶ。それまでに別の行動に変わっていたら呼ばない
local function atStartup(player: Player, t: number, timeline: ActionState.Timeline, fn: () -> ())
	if timeline.Startup <= 0 then
		fn()
		return
	end
	task.delay(timeline.Startup, function()
		local _, startedAt = ActionService.current(player)
		if startedAt == t then
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

-- 奥義の攻撃を間隔ごとに出す。奥義の最中の無敵は Damage.luau が行動から判定する
local function doOugi(player: Player)
	local ougi = Config.Ougi
	PlayerService.resetOugiGauge(player)

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
	end)
end

local function registerActions()
	ActionService.register(Actions.Attack, {
		timeline = function(player, t)
			return Config.Action.Attack[nextComboStep(comboOf(player), t)]
		end,
		begin = function(player, t, timeline)
			local combo = comboOf(player)
			local step = nextComboStep(combo, t)
			combo.comboIndex = step
			combo.lastAttackAt = t
			atStartup(player, t, timeline, function()
				local root = getRoot(player)
				if root then
					doAttack(player, root, step)
				end
			end)
			return step
		end,
	})

	ActionService.register(Actions.ChargeKogeki, {
		timeline = function()
			return Config.Action.ChargeKogeki
		end,
		begin = function(player, t, timeline)
			comboOf(player).comboIndex = 0
			atStartup(player, t, timeline, function()
				local root = getRoot(player)
				if root then
					doChargeKogeki(player, root)
				end
			end)
			return nil
		end,
	})

	ActionService.register(Actions.Ougi, {
		timeline = function(player)
			if PlayerService.getOugiGauge(player) < Config.Ougi.MaxGauge then
				return nil
			end
			-- 被弾の反応の最中は出せない
			if ActionService.isReaction((ActionService.current(player))) then
				return nil
			end
			return Config.Action.Ougi
		end,
		begin = function(player)
			comboOf(player).comboIndex = 0
			-- 奥義ゲージは入力を受け付けた時点で使う
			doOugi(player)
			return nil
		end,
	})
end

function CombatService.start()
	registerActions()

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

	-- 被弾の反応で行動が途切れたら、通常攻撃の段を1段目に戻す
	ActionService.started:Connect(function(player: Player, action: string)
		if ActionService.isReaction(action) then
			comboOf(player).comboIndex = 0
		end
	end)

	-- 出現し直したら1段目から始める
	local function track(player: Player)
		player.CharacterAdded:Connect(function()
			comboOf(player).comboIndex = 0
		end)
	end
	Players.PlayerAdded:Connect(track)
	for _, player in Players:GetPlayers() do
		track(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		combos[player] = nil
	end)
end

return CombatService
