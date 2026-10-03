--!strict
-- 敵兵の生成・AI・被ダメージ処理。
-- 戦闘のフェーズの間だけ、出撃したステージの区画にいるメンバーの周りに、下忍を部隊単位で湧かせ続け、
-- 一定部隊ごとに上忍を混ぜる。戦闘のフェーズが終わったら（決着・ロビーへの帰還・全員の離脱）敵を片付ける。
-- プレイヤーへの攻撃は DamageService の被ダメージの窓口に渡す。
-- 湧かせる敵は敵軍で、部隊のデータ（ButaiService）には属さない（実体化圏での出し入れは #76 で置き換える）。
-- プレイヤーが倒した敵は、撃破数を足し、gekiha で種類・軍・倒れた位置・倒したプレイヤーを知らせる。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Appearance = require(ReplicatedStorage.Shared.Appearance)
local Characters = require(ReplicatedStorage.Shared.Characters)
local Config = require(ReplicatedStorage.Shared.Config)
local Ground = require(ReplicatedStorage.Shared.Ground)
local Gun = require(ReplicatedStorage.Shared.Gun)
local HitShape = require(ReplicatedStorage.Shared.HitShape)
local Mejirushi = require(ReplicatedStorage.Shared.Mejirushi)
local StagePhase = require(ReplicatedStorage.Shared.StagePhase)
local Stages = require(ReplicatedStorage.Shared.Stages)
local DebugCommand = require(script.Parent.Parent.DebugCommand)
local DamageService = require(script.Parent.DamageService)
local KukakuService = require(script.Parent.KukakuService)
local PlayerService = require(script.Parent.PlayerService)
local StageService = require(script.Parent.StageService)

type EnemyDef = Config.EnemySection

-- 湧かせる敵の種類。能力値は Config.luau、見分けるための色はここに置く
local ENEMY_DEFS: { [string]: EnemyDef } = {
	Genin = Config.Genin,
	Jonin = Config.Jonin,
}
local ENEMY_COLORS: { [string]: Color3 } = {
	Genin = Color3.fromRGB(70, 90, 160),
	Jonin = Color3.fromRGB(170, 40, 40),
}

type Enemy = {
	-- 種類（Genin・Jonin）
	kind: string,
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	def: EnemyDef,
	-- 攻撃判定で使う水平の半径
	radius: number,
	lastAttack: number,
	lastHitBy: Player?,
}

local EnemyService = {}

-- 湧かせる敵の軍
local ENEMY_GUN: Gun.Gun = "Tekigun"

local gekihaEvent = Instance.new("BindableEvent")
-- プレイヤーが敵を倒したときに、種類（Genin・Jonin）・軍・倒れた位置（Vector3）・倒したプレイヤーで発火する。
-- 拠点の耐久（KyotenService）はこれを受けて減る
EnemyService.gekiha = gekihaEvent.Event

local enemiesFolder: Folder
local templates: { [string]: Model } = {}
local radii: { [string]: number } = {}
local enemies: { [Model]: Enemy } = {}
local aliveCount = 0
-- 一定間隔の湧きを続けるか。窓口の SetSpawning で切り替える
local spawning = true
-- 部隊を出す位置を区画の中から選ぶときに試す回数
local BUTAI_CENTER_TRIES = 8

local function buildTemplate(kind: string, def: EnemyDef): Model
	local color = ENEMY_COLORS[kind]
	local description = Instance.new("HumanoidDescription")
	description.HeadColor = color
	description.TorsoColor = color
	description.LeftArmColor = color
	description.RightArmColor = color
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
	-- 下忍は頭上表示を出さず、上忍だけ名前と体力バーを出す
	humanoid.DisplayDistanceType = if kind == "Jonin"
		then Enum.HumanoidDisplayDistanceType.Viewer
		else Enum.HumanoidDisplayDistanceType.None

	return model
end

local function findNearestTarget(position: Vector3): (Player?, BasePart?)
	local bestPlayer, bestRoot, bestDistance = nil, nil, Config.Spawner.AggroRange
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if humanoid and root and humanoid.Health > 0 then
			local distance = (root.Position - position).Magnitude
			if distance < bestDistance then
				bestPlayer, bestRoot, bestDistance = player, root, distance
			end
		end
	end
	return bestPlayer, bestRoot
end

local function updateEnemy(enemy: Enemy, now: number)
	local targetPlayer, targetRoot = findNearestTarget(enemy.root.Position)
	if not targetPlayer or not targetRoot then
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

	DamageService.damage(targetPlayer, {
		origin = enemy.root.Position,
		power = enemy.def.Damage,
		reaction = enemy.def.Reaction,
	})
end

local function onEnemyDied(enemy: Enemy)
	-- 片付けで先に表から外した敵は数え直さない
	if enemies[enemy.model] == nil then
		return
	end
	enemies[enemy.model] = nil
	aliveCount -= 1

	local attacker = enemy.lastHitBy
	if attacker and attacker.Parent then
		PlayerService.addGekihasu(attacker)
		gekihaEvent:Fire(enemy.kind, ENEMY_GUN, enemy.root.Position, attacker)
	end

	task.delay(Config.Spawner.CorpseLifetime, function()
		enemy.model:Destroy()
	end)
end

-- (x, z) の地面の上に敵を1体出す。地面が無ければ出さずに nil を返す
local function spawnEnemy(kind: string, x: number, z: number): Model?
	local def = ENEMY_DEFS[kind]
	local model = templates[kind]:Clone()
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart

	if not Ground.placeCharacter(model, x, z) then
		model:Destroy()
		return nil
	end
	model.Parent = enemiesFolder
	-- ノックバックの挙動を安定させるため物理はサーバーが持つ
	root:SetNetworkOwner(nil)

	local enemy: Enemy = {
		kind = kind,
		model = model,
		humanoid = humanoid,
		root = root,
		def = def,
		radius = radii[kind],
		lastAttack = 0,
		lastHitBy = nil,
	}
	enemies[model] = enemy
	aliveCount += 1

	humanoid.Died:Once(function()
		onEnemyDied(enemy)
	end)
	return model
end

-- 戦闘のフェーズなら、出撃したステージの区画の範囲の目印。戦闘のフェーズでなければ nil
local function battleBounds(): BasePart?
	if StageService.getPhase() ~= "Battle" then
		return nil
	end
	local stageId = StageService.getStage()
	local stage = if stageId then Stages.get(stageId) else nil
	if not stage then
		return nil
	end
	return KukakuService.bounds(stage.kukaku)
end

local function insideBounds(bounds: BasePart, position: Vector3): boolean
	local offset = bounds.CFrame:PointToObjectSpace(position)
	return Mejirushi.insideBounds(offset.X, offset.Z, bounds.Size.X, bounds.Size.Z)
end

-- 部隊を出す水平位置。Vector2 の X と Y にワールドの X と Z を入れる。高さは spawnEnemy が地面に合わせる。
-- 戦闘のフェーズで、区画の中にいるメンバーの周りの、区画の中の位置を選ぶ。選べなければ nil
local function pickButaiCenter(): Vector2?
	local bounds = battleBounds()
	if not bounds then
		return nil
	end
	local candidates = {}
	for _, member in StageService.getMembers() do
		local root = member.Character and member.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and insideBounds(bounds, root.Position) then
			table.insert(candidates, root.Position)
		end
	end
	if #candidates == 0 then
		return nil
	end

	local base = candidates[math.random(1, #candidates)]
	for _ = 1, BUTAI_CENTER_TRIES do
		local angle = math.random() * math.pi * 2
		local distance = Config.Spawner.MinDistance
			+ math.random() * (Config.Spawner.MaxDistance - Config.Spawner.MinDistance)
		local center = base + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		if insideBounds(bounds, center) then
			return Vector2.new(center.X, center.Z)
		end
	end
	return nil
end

local function spawnButai(center: Vector2, withJonin: boolean)
	local count = math.min(Config.Spawner.ButaiSize, Config.Spawner.MaxAlive - aliveCount)
	for i = 1, count do
		local kind = if withJonin and i == 1 then "Jonin" else "Genin"
		spawnEnemy(kind, center.X + math.random(-8, 8), center.Y + math.random(-8, 8))
	end
end

-- 攻撃側から呼ばれる被ダメージ処理。撃破数はとどめを刺したプレイヤーに付く
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

-- 攻撃判定の対象にする、生きている敵の位置と半径
function EnemyService.getTargets(): { HitShape.Target<Model> }
	local targets = {}
	for model, enemy in enemies do
		if enemy.humanoid.Health > 0 then
			table.insert(targets, { ref = model, position = enemy.root.Position, radius = enemy.radius })
		end
	end
	return targets
end

-- 敵をすべて消す。倒れて消える前の敵も消し、撃破数には数えない
local function removeAll()
	for model in enemies do
		model:Destroy()
	end
	table.clear(enemies)
	aliveCount = 0
	enemiesFolder:ClearAllChildren()
end

function EnemyService.start()
	enemiesFolder = Instance.new("Folder")
	enemiesFolder.Name = "Enemies"
	enemiesFolder.Parent = workspace

	-- 戦闘のフェーズが終わったら片付ける
	StageService.phaseChanged:Connect(function(next: StagePhase.Phase)
		if next ~= "Battle" then
			removeAll()
		end
	end)

	for kind, def in ENEMY_DEFS do
		local template = buildTemplate(kind, def)
		templates[kind] = template
		-- 腕まで含めた横幅の半分を半径にする（空間クエリで体のパーツに当てていたときと同じ広さ）
		local size = template:GetExtentsSize()
		radii[kind] = math.max(size.X, size.Z) / 2
	end

	DebugCommand.register(
		"SpawnEnemy",
		"<Genin|Jonin> <x> <z>",
		"地面の高さに合わせて敵を1体出す",
		function(kind, x, z)
			if type(kind) ~= "string" or not ENEMY_DEFS[kind] then
				error("種類は Genin か Jonin で指定する", 0)
			end
			local model = spawnEnemy(kind, DebugCommand.toNumber(x, "x"), DebugCommand.toNumber(z, "z"))
			if not model then
				return "地面が見つからず出せなかった"
			end
			local position = model:GetPivot().Position
			return string.format("%s を (%.1f, %.1f, %.1f) に出した", kind, position.X, position.Y, position.Z)
		end
	)

	DebugCommand.register(
		"SetSpawning",
		"<true|false>",
		"一定間隔の敵の湧きを止める・再開する（プレイヤーの動きを確かめるときの確認用）",
		function(value)
			spawning = value == true or value == "true"
			return `敵の湧きを{if spawning then "再開した" else "止めた"}`
		end
	)

	DebugCommand.register(
		"ClearEnemies",
		"",
		"生きている敵をすべて倒す（撃破数には数えない）",
		function()
			local count = 0
			for _, enemy in enemies do
				if enemy.humanoid.Health > 0 then
					enemy.lastHitBy = nil
					enemy.humanoid.Health = 0
					count += 1
				end
			end
			return `敵を {count} 体倒した`
		end
	)

	DebugCommand.register(
		"DefeatEnemies",
		"<プレイヤー名> [半径]",
		"プレイヤーの周り（既定は半径 30 スタッド）の生きている敵を倒し、そのプレイヤーの撃破に数える（確認用）",
		function(name, radius)
			local player = DebugCommand.findPlayer(name)
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not root then
				return `{player.Name} のキャラクターがいない`
			end
			local range = if radius ~= nil then DebugCommand.toNumber(radius, "半径") else 30
			local count = 0
			for _, enemy in enemies do
				if enemy.humanoid.Health > 0 and (enemy.root.Position - root.Position).Magnitude <= range then
					enemy.lastHitBy = player
					enemy.humanoid.Health = 0
					count += 1
				end
			end
			return `{player.Name} の周り {range} スタッドの敵を {count} 体倒した`
		end
	)

	DebugCommand.register(
		"SpawnNpc",
		"<キャラクター ID> <x> <z>",
		"仮の見た目の NPC を地面の高さに合わせて1体出す（上忍・首領・役者の見た目の確認用）",
		function(characterId, x, z)
			if type(characterId) ~= "string" or not Characters.get(characterId) then
				error(`キャラクター ID {tostring(characterId)} は定義表に無い`, 0)
			end
			local model = Appearance.createModel(characterId)
			if not Ground.placeCharacter(model, DebugCommand.toNumber(x, "x"), DebugCommand.toNumber(z, "z")) then
				model:Destroy()
				return "地面が見つからず出せなかった"
			end
			local folder = workspace:FindFirstChild("Npcs") or Instance.new("Folder")
			folder.Name = "Npcs"
			folder.Parent = workspace
			model.Parent = folder
			return `{characterId} を出した`
		end
	)

	task.spawn(function()
		local butaiCount = 0
		while true do
			task.wait(Config.Spawner.ButaiInterval)
			if spawning and aliveCount < Config.Spawner.MaxAlive then
				local center = pickButaiCenter()
				if center then
					butaiCount += 1
					spawnButai(center, butaiCount % Config.Spawner.JoninEvery == 0)
				end
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
