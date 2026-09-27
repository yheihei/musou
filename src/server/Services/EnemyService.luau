--!strict
-- 敵兵の生成・AI・被ダメージ処理。
-- 雑兵を部隊単位で湧かせ続け、一定部隊ごとに武将を混ぜる。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PlayerService = require(script.Parent.PlayerService)

type EnemyDef = typeof(Config.Enemies.Soldier)

type Enemy = {
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	def: EnemyDef,
	lastAttack: number,
	lastHitBy: Player?,
}

local EnemyService = {}

local enemiesFolder: Folder
local templates: { [string]: Model } = {}
local enemies: { [Model]: Enemy } = {}
local aliveCount = 0

local function buildTemplate(kind: string, def: EnemyDef): Model
	local description = Instance.new("HumanoidDescription")
	description.HeadColor = def.Color
	description.TorsoColor = def.Color
	description.LeftArmColor = def.Color
	description.RightArmColor = def.Color
	description.LeftLegColor = Color3.fromRGB(40, 40, 40)
	description.RightLegColor = Color3.fromRGB(40, 40, 40)
	description.HeightScale = def.Scale
	description.WidthScale = def.Scale
	description.DepthScale = def.Scale
	description.HeadScale = def.Scale

	local model = Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	model.Name = kind

	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.DisplayName = def.DisplayName
	humanoid.MaxHealth = def.MaxHealth
	humanoid.Health = def.MaxHealth
	humanoid.WalkSpeed = def.WalkSpeed
	humanoid.BreakJointsOnDeath = false
	-- 雑兵は頭上表示を出さず、武将だけ名前と体力バーを出す
	humanoid.DisplayDistanceType = if kind == "Officer"
		then Enum.HumanoidDisplayDistanceType.Viewer
		else Enum.HumanoidDisplayDistanceType.None

	return model
end

local function findNearestTarget(position: Vector3): (Humanoid?, BasePart?)
	local bestHumanoid, bestRoot, bestDistance = nil, nil, Config.Spawner.AggroRange
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if humanoid and root and humanoid.Health > 0 then
			local distance = (root.Position - position).Magnitude
			if distance < bestDistance then
				bestHumanoid, bestRoot, bestDistance = humanoid, root, distance
			end
		end
	end
	return bestHumanoid, bestRoot
end

local function updateEnemy(enemy: Enemy, now: number)
	local targetHumanoid, targetRoot = findNearestTarget(enemy.root.Position)
	if not targetHumanoid or not targetRoot then
		enemy.humanoid:Move(Vector3.zero)
		return
	end

	local offset = targetRoot.Position - enemy.root.Position
	if offset.Magnitude > enemy.def.AttackRange then
		enemy.humanoid:MoveTo(targetRoot.Position)
		return
	end

	enemy.humanoid:Move(Vector3.zero)
	if now - enemy.lastAttack < enemy.def.AttackCooldown then
		return
	end
	enemy.lastAttack = now

	local character = targetHumanoid.Parent
	if character and character:GetAttribute("Invulnerable") then
		return
	end
	targetHumanoid:TakeDamage(enemy.def.Damage)
end

local function onEnemyDied(enemy: Enemy)
	enemies[enemy.model] = nil
	aliveCount -= 1

	if enemy.lastHitBy and enemy.lastHitBy.Parent then
		PlayerService.addKO(enemy.lastHitBy)
	end

	task.delay(Config.Spawner.CorpseLifetime, function()
		enemy.model:Destroy()
	end)
end

local function spawnEnemy(kind: string, position: Vector3)
	local def = (Config.Enemies :: any)[kind] :: EnemyDef
	local model = templates[kind]:Clone()
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart

	model:PivotTo(CFrame.new(position + Vector3.new(0, 5, 0)))
	model.Parent = enemiesFolder
	-- ノックバックの挙動を安定させるため物理はサーバーが持つ
	root:SetNetworkOwner(nil)

	local enemy: Enemy = {
		model = model,
		humanoid = humanoid,
		root = root,
		def = def,
		lastAttack = 0,
		lastHitBy = nil,
	}
	enemies[model] = enemy
	aliveCount += 1

	humanoid.Died:Once(function()
		onEnemyDied(enemy)
	end)
end

local function pickSquadCenter(): Vector3?
	local players = Players:GetPlayers()
	local candidates = {}
	for _, player in players do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			table.insert(candidates, root.Position)
		end
	end
	if #candidates == 0 then
		return nil
	end

	local base = candidates[math.random(1, #candidates)]
	local angle = math.random() * math.pi * 2
	local distance = Config.Spawner.MinDistance
		+ math.random() * (Config.Spawner.MaxDistance - Config.Spawner.MinDistance)
	return Vector3.new(base.X + math.cos(angle) * distance, 0, base.Z + math.sin(angle) * distance)
end

local function spawnSquad(withOfficer: boolean)
	local center = pickSquadCenter()
	if not center then
		return
	end

	local count = math.min(Config.Spawner.SquadSize, Config.Spawner.MaxAlive - aliveCount)
	for i = 1, count do
		local offset = Vector3.new(math.random(-8, 8), 0, math.random(-8, 8))
		local kind = if withOfficer and i == 1 then "Officer" else "Soldier"
		spawnEnemy(kind, center + offset)
	end
end

-- 攻撃側から呼ばれる被ダメージ処理。KO はとどめを刺したプレイヤーに付く
function EnemyService.damage(model: Model, amount: number, attacker: Player, knockback: Vector3?)
	local enemy = enemies[model]
	if not enemy or enemy.humanoid.Health <= 0 then
		return false
	end

	enemy.lastHitBy = attacker
	enemy.humanoid:TakeDamage(amount)
	if knockback then
		enemy.root.AssemblyLinearVelocity = knockback
	end
	return true
end

function EnemyService.getFolder(): Folder
	return enemiesFolder
end

function EnemyService.start()
	enemiesFolder = Instance.new("Folder")
	enemiesFolder.Name = "Enemies"
	enemiesFolder.Parent = workspace

	for kind, def in Config.Enemies do
		templates[kind] = buildTemplate(kind, def)
	end

	task.spawn(function()
		local squadCount = 0
		while true do
			task.wait(Config.Spawner.SquadInterval)
			if aliveCount < Config.Spawner.MaxAlive then
				squadCount += 1
				spawnSquad(squadCount % Config.Spawner.OfficerEvery == 0)
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(Config.Spawner.AITickInterval)
			local now = os.clock()
			for _, enemy in enemies do
				updateEnemy(enemy, now)
			end
		end
	end)
end

return EnemyService
