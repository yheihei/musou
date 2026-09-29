--!strict
-- プレイヤーの攻撃の中身。通常攻撃・チャージ攻撃・奥義のタイムラインと判定を ActionService に登録する。
-- 入力の受け取りと行動の状態遷移は ActionService が持ち、コンボの段数と当たり判定はここで決める。
--
-- - 通常攻撃の段は武器種ごとに Config.luau の Bukishu 節にあり、キャラクターの武器種から引く
-- - 時間はキャラクターの攻撃の速さで伸び縮みさせる（ActionState.scale）
-- - 判定はタイムラインの Hits の時刻に出し、それまでに行動が変わっていたら出さない
-- - 前進量は、発生から持続の終わりまでにサーバーの拘束で前へ動かす
-- - 与ダメージは Stats.damage（技の倍率 × 攻撃）。敵はまだ防御を持たない

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ActionState = require(ReplicatedStorage.Shared.ActionState)
local Actions = require(ReplicatedStorage.Shared.Actions)
local Characters = require(ReplicatedStorage.Shared.Characters)
local Combo = require(ReplicatedStorage.Shared.Combo)
local Config = require(ReplicatedStorage.Shared.Config)
local HitShape = require(ReplicatedStorage.Shared.HitShape)
local Stats = require(ReplicatedStorage.Shared.Stats)
local DebugCommand = require(script.Parent.Parent.DebugCommand)
local ActionService = require(script.Parent.ActionService)
local EnemyService = require(script.Parent.EnemyService)
local PlayerService = require(script.Parent.PlayerService)
local Hitbox = require(script.Parent.Parent.Combat.Hitbox)
local Push = require(script.Parent.Parent.Combat.Push)
local Vfx = require(script.Parent.Parent.Combat.Vfx)

local CombatService = {}

local combos: { [Player]: Combo.State } = {}

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

local function comboOf(player: Player): Combo.State
	return combos[player] or Combo.new()
end

-- 使うキャラクターの武器種の技
local function bukishuOf(player: Player): Config.BukishuDef
	local character = Characters.get(PlayerService.getCharacterId(player))
	local bukishu = character and character.bukishu or "Shuriken"
	return Config.Bukishu[bukishu]
end

-- 攻撃の速さの倍率で伸び縮みさせたタイムライン
local function scaled(player: Player, timeline: ActionState.Timeline): ActionState.Timeline
	return ActionState.scale(timeline, PlayerService.getStats(player).AttackSpeed)
end

-- 反応に合わせて敵に与える速さ。吹き飛びと打ち上げの軌道を計算するまでの仮置き
local function knockbackVelocity(origin: Vector3, target: Model, reaction: Config.Reaction, force: number): Vector3?
	if reaction == "None" or force <= 0 then
		return nil
	end
	local offset = target:GetPivot().Position - origin
	local flat = Vector3.new(offset.X, 0, offset.Z)
	local direction = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
	if reaction == "Launch" then
		return direction * force * 0.2 + Vector3.new(0, force, 0)
	end
	return direction * force + Vector3.new(0, force * 0.3, 0)
end

local function hitOne(
	player: Player,
	origin: Vector3,
	model: Model,
	damage: number,
	reaction: Config.Reaction,
	force: number
)
	if EnemyService.damage(model, damage, player, knockbackVelocity(origin, model, reaction, force)) then
		Vfx.hit(model)
		PlayerService.addOugiGauge(player, Config.Ougi.GainPerHit)
	end
end

-- 形に入った敵に当てる。飛び道具のように時間差のある当たりは、その秒数だけ遅らせる
local function hitAll(
	player: Player,
	origin: HitShape.Origin,
	shape: HitShape.Shape,
	damage: number,
	reaction: Config.Reaction,
	force: number
)
	local position: Vector3 = origin.position
	for _, hit in Hitbox.query(shape, origin, EnemyService.getTargets()) do
		if hit.delay > 0 then
			task.delay(hit.delay, hitOne, player, position, hit.ref, damage, reaction, force)
		else
			hitOne(player, position, hit.ref, damage, reaction, force)
		end
	end
end

-- 技の判定を1つ出す
local function doHit(player: Player, root: BasePart, hit: Config.HitDef, color: Color3)
	local shape = HitShape.fromDef(hit.Shape, Config.Hitbox.Height)
	local origin = HitShape.rotate(Hitbox.originOf(root), hit.Yaw or 0)
	Vfx.shape(shape, origin, color)
	local damage = Stats.damage(hit.Power, PlayerService.getStats(player).Attack, 0)
	hitAll(player, origin, shape, damage, hit.Reaction, hit.Knockback)
end

-- 時刻 t に始めた行動の前進と判定を出す。判定の時刻までに別の行動に変わっていたら出さない
local function perform(player: Player, t: number, timeline: ActionState.Timeline, color: Color3)
	local root = getRoot(player)
	if root and timeline.Advance > 0 then
		Push.move(root, root.CFrame.LookVector, timeline.Advance, timeline.Startup + timeline.Active)
	end
	for _, scheduled in ActionState.hits(timeline) do
		local function fire()
			local _, startedAt = ActionService.current(player)
			local current = getRoot(player)
			if startedAt == t and current then
				doHit(player, current, scheduled.hit, color)
			end
		end
		if scheduled.at <= 0 then
			fire()
		else
			task.delay(scheduled.at, fire)
		end
	end
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

local function doChargeKogeki(player: Player, root: BasePart)
	local chargeKogeki = Config.ChargeKogeki
	Vfx.ring(root.Position, chargeKogeki.Radius, CHARGE_KOGEKI_COLOR)
	local shape: HitShape.Shape = { kind = "Sphere", radius = chargeKogeki.Radius }
	hitAll(player, Hitbox.originOf(root), shape, chargeKogeki.Damage, "Knockback", chargeKogeki.Knockback)
end

-- 奥義の攻撃を間隔ごとに出す。奥義の最中の無敵は Damage.luau が行動から判定する
local function doOugi(player: Player)
	local ougi = Config.Ougi

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
				local velocity = knockbackVelocity(root.Position, model, "Knockback", ougi.Knockback)
				if EnemyService.damage(model, ougi.DamagePerPulse, player, velocity) then
					Vfx.hit(model)
				end
			end
			task.wait(ougi.PulseInterval)
		end
	end)
end

local function registerActions()
	-- 通常攻撃。武器種の段を1段目から順に出す
	ActionService.register(Actions.Attack, {
		timeline = function(player, t)
			local steps = bukishuOf(player).Attack
			return scaled(player, steps[Combo.count(comboOf(player), t, #steps) + 1])
		end,
		begin = function(player, t, timeline)
			local steps = bukishuOf(player).Attack
			local step = Combo.count(comboOf(player), t, #steps) + 1
			combos[player] = Combo.advance(step, t, timeline.CancelFrom)
			perform(player, t, timeline, SLASH_COLOR)
			return step
		end,
	})

	ActionService.register(Actions.ChargeKogeki, {
		timeline = function()
			return Config.Action.ChargeKogeki
		end,
		begin = function(player, t, timeline)
			combos[player] = Combo.new()
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
			if PlayerService.getOugi(player).stock < 1 then
				return nil
			end
			-- 被弾の反応の最中は出せない
			if ActionService.isReaction((ActionService.current(player))) then
				return nil
			end
			return Config.Action.Ougi
		end,
		begin = function(player)
			combos[player] = Combo.new()
			-- 奥義ゲージは入力を受け付けた時点で1本使う
			PlayerService.consumeOugiStock(player)
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

	-- 被弾の反応で行動が途切れたら、前進を止め、通常攻撃の段を1段目に戻す
	ActionService.started:Connect(function(player: Player, action: string)
		if ActionService.isReaction(action) then
			combos[player] = Combo.new()
			local root = getRoot(player)
			if root then
				Push.stop(root)
			end
		end
	end)

	-- 出現し直したら1段目から始める
	local function track(player: Player)
		player.CharacterAdded:Connect(function()
			combos[player] = Combo.new()
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
