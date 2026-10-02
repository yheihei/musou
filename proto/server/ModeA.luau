--!strict
-- 案A。下忍を Humanoid 付きのモデルでサーバーに置き、サーバーが動かす（今の EnemyService と同じ作り）。
-- 近づくのは Humanoid:MoveTo、攻撃は体の色を変えて前へ踏み込み、吹き飛びはサーバーが速度を与え、
-- 倒れたら DownTime 秒後に消して RespawnDelay 秒後に湧き直す。値は Config.luau の GeninProto 節にある。

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Ground = require(ReplicatedStorage.Shared.Ground)

local P = Config.GeninProto

type Entry = {
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	torso: BasePart?,
	hits: number,
	lastAttack: number,
	-- 攻撃の色を戻す時刻（os.clock）。攻撃していなければ nil
	attackUntil: number?,
}

local ModeA = {}

local ATTACK_COLOR = Color3.fromRGB(230, 80, 80)
local BODY_COLOR = Color3.fromRGB(70, 90, 160)
-- 攻撃で前へ踏み込む速さ（スタッド/秒）
local LUNGE_SPEED = 15

local entries: { Entry } = {}
local folder: Folder? = nil
local template: Model? = nil
-- 湧かせる中心（プレイヤーの位置）を返す関数
local centerOf: () -> Vector3 = function()
	return Vector3.zero
end
-- 止めるたびに増やす。湧き直しの予約が、止めた後や切り替えた後に動かないようにする
local generation = 0

local function ringPosition(center: Vector3): (number, number)
	local angle = math.random() * math.pi * 2
	local radius = P.SpawnRadiusMin + math.random() * (P.SpawnRadiusMax - P.SpawnRadiusMin)
	return center.X + math.cos(angle) * radius, center.Z + math.sin(angle) * radius
end

local function spawnOne()
	local container = folder
	local source = template
	if not container or not source then
		return
	end
	local model = source:Clone()
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	local x, z = ringPosition(centerOf())
	if not Ground.placeCharacter(model, x, z) then
		-- 床の外を選んだら、少し待って別の位置で出し直す（案B と体数をそろえる）
		model:Destroy()
		local current = generation
		task.delay(1, function()
			if generation == current then
				spawnOne()
			end
		end)
		return
	end
	humanoid.WalkSpeed = P.WalkSpeed
	model.Parent = container
	root:SetNetworkOwner(nil)
	local entry: Entry = {
		model = model,
		humanoid = humanoid,
		root = root,
		torso = model:FindFirstChild("UpperTorso") :: BasePart?,
		hits = 0,
		lastAttack = -math.huge,
		attackUntil = nil,
	}
	table.insert(entries, entry)
	local current = generation
	humanoid.Died:Once(function()
		task.delay(P.DownTime, function()
			local index = table.find(entries, entry)
			if index then
				table.remove(entries, index)
			end
			model:Destroy()
			task.delay(P.RespawnDelay, function()
				if generation == current then
					spawnOne()
				end
			end)
		end)
	end)
end

-- count 体を、center が返す位置（プレイヤーの位置）の周りに出す。倒れた下忍もその時点の center の周りに湧き直す
function ModeA.start(count: number, source: Model, center: () -> Vector3)
	ModeA.stop()
	template = source
	centerOf = center
	local created = Instance.new("Folder")
	created.Name = "ProtoGeninA"
	created.Parent = workspace
	folder = created
	for _ = 1, count do
		spawnOne()
	end
end

function ModeA.stop()
	generation += 1
	table.clear(entries)
	local container = folder
	if container then
		container:Destroy()
	end
	folder = nil
end

local function nearestTarget(position: Vector3, targets: { Vector3 }): (Vector3?, number)
	local best: Vector3? = nil
	local bestDistance = math.huge
	for _, target in targets do
		local distance = (Vector3.new(target.X, position.Y, target.Z) - position).Magnitude
		if distance < bestDistance then
			best, bestDistance = target, distance
		end
	end
	return best, bestDistance
end

-- 近づき、間合いに入ったら攻撃する。targets はプレイヤーの位置
function ModeA.step(targets: { Vector3 })
	local now = os.clock()
	for _, entry in entries do
		if entry.humanoid.Health <= 0 then
			continue
		end
		local torso = entry.torso
		local attackUntil = entry.attackUntil
		if attackUntil and now >= attackUntil then
			entry.attackUntil = nil
			if torso then
				torso.Color = BODY_COLOR
			end
		end
		local target, distance = nearestTarget(entry.root.Position, targets)
		if not target then
			entry.humanoid:Move(Vector3.zero)
		elseif distance > P.AttackRange then
			entry.humanoid:MoveTo(target)
		else
			entry.humanoid:Move(Vector3.zero)
			if now - entry.lastAttack >= P.AttackCooldown then
				entry.lastAttack = now
				entry.attackUntil = now + P.AttackTime
				if torso then
					torso.Color = ATTACK_COLOR
				end
				local flat = Vector3.new(target.X - entry.root.Position.X, 0, target.Z - entry.root.Position.Z)
				if flat.Magnitude > 1e-3 then
					entry.root.AssemblyLinearVelocity = flat.Unit * LUNGE_SPEED
				end
			end
		end
	end
end

-- center からの薙ぎ払い。半径の中の下忍を外へ吹き飛ばし、MaxHits 回当たったら倒す。当てた数を返す
function ModeA.sweep(center: Vector3): number
	local count = 0
	local up = math.sqrt(2 * workspace.Gravity * P.KnockbackHeight)
	local outward = P.KnockbackDistance / P.KnockbackTime
	for _, entry in entries do
		if entry.humanoid.Health > 0 then
			local offset = Vector3.new(entry.root.Position.X - center.X, 0, entry.root.Position.Z - center.Z)
			if offset.Magnitude <= P.SweepRadius then
				count += 1
				entry.hits += 1
				local direction = if offset.Magnitude > 1e-3 then offset.Unit else Vector3.new(0, 0, 1)
				entry.root.AssemblyLinearVelocity = direction * outward + Vector3.new(0, up, 0)
				if entry.hits >= P.MaxHits then
					entry.humanoid.Health = 0
				end
			end
		end
	end
	return count
end

-- 出している体数（倒れて消える前のものを含む）
function ModeA.count(): number
	return #entries
end

return ModeA
