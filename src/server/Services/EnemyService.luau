--!strict
-- 敵兵の生成・AI・被ダメージ処理。
-- 戦闘のフェーズの間だけ、出撃したステージの区画にいるメンバーの周りに、下忍を部隊単位で湧かせ続け、
-- 一定部隊ごとに上忍を混ぜる。戦闘のフェーズが終わったら（決着・ロビーへの帰還・全員の離脱）敵を片付ける。
-- プレイヤーへの攻撃は DamageService の被ダメージの窓口に渡す。
-- 湧かせる敵は敵軍で、部隊のデータ（ButaiService）には属さない（実体化圏での出し入れは #76 で置き換える）。
-- 部隊は出撃メンバーの視界の外にだけ出す（視界は CameraViewService。どの位置も視界にかかれば、その回は見送る）。
-- 敵は近づいて攻撃するだけで、体ではプレイヤーにもほかの敵にもぶつからない（CollisionGroups の Enemy）。
-- 重ならないよう、プレイヤーの手前で止まり、ほかの敵とも離れて囲む（立ち位置の計算は EnemySpacing）。
-- プレイヤーが倒した敵は、撃破数を足し、gekiha で種類・軍・倒れた位置・倒したプレイヤーを知らせる。
--
-- 攻撃トークン（計算は KogekiToken、数値は Config.luau の KogekiToken 節）
-- - 1人のプレイヤーを同時に攻撃できる下忍は、そのプレイヤーの攻撃トークンを持つ下忍だけ（PerPlayer 体まで）
-- - 攻撃トークンを持たない下忍は、攻撃する下忍より WaitGap だけ外で囲んで待ち、攻撃しない
-- - 攻撃した下忍は攻撃トークンを返す。倒れた下忍、吹き飛んで倒れている下忍、ほかのプレイヤーを狙った下忍、
--   Range より離れた下忍、MaxHold 秒たっても攻撃しない下忍も返し、近い下忍へ渡る
-- - 攻撃トークンを持つ下忍は、待っている下忍を避けずに、攻撃が届く距離の内で止まる
-- - 上忍は攻撃トークンなしで攻撃する
--
-- 攻撃を受けた敵の反応（のけぞり・吹き飛び・打ち上げ・ダウン・起き上がり）は Combat/Hanno が動かす。
-- 上忍は Config.luau の EnemyReaction 節の JoninScale を掛けた初速で短く飛び、JoninFlinchScale を掛けた秒数だけのけぞる
-- （0 ならのけぞらない）。反応の最中は、近づくことも攻撃することもしない。
-- 上忍と首領の個体（データの上忍と首領。JoninKotaiService）とは別の、仮の湧き処理の敵である
--
-- 毒（酉花の奥義「毒手裏剣」。数値は Config.luau の Poison 節）
-- - 毒の間は Interval 秒ごとに Damage を与える。とどめは毒を付けたプレイヤーの撃破に数える
-- - 毒の間にもう一度付けると、残りの時間を Duration に戻す。毒の間は緑の煙（Fire）の仮の見た目を出す

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Appearance = require(ReplicatedStorage.Shared.Appearance)
local Characters = require(ReplicatedStorage.Shared.Characters)
local Config = require(ReplicatedStorage.Shared.Config)
local EnemySpacing = require(ReplicatedStorage.Shared.EnemySpacing)
local Ground = require(ReplicatedStorage.Shared.Ground)
local Gun = require(ReplicatedStorage.Shared.Gun)
local HitShape = require(ReplicatedStorage.Shared.HitShape)
local KogekiToken = require(ReplicatedStorage.Shared.KogekiToken)
local Mejirushi = require(ReplicatedStorage.Shared.Mejirushi)
local StagePhase = require(ReplicatedStorage.Shared.StagePhase)
local Stages = require(ReplicatedStorage.Shared.Stages)
local DebugCommand = require(script.Parent.Parent.DebugCommand)
local CameraViewService = require(script.Parent.CameraViewService)
local DamageService = require(script.Parent.DamageService)
local KukakuService = require(script.Parent.KukakuService)
local PlayerService = require(script.Parent.PlayerService)
local StageService = require(script.Parent.StageService)
local CollisionGroups = require(script.Parent.Parent.CollisionGroups)
local Hanno = require(script.Parent.Parent.Combat.Hanno)

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
	-- 同じ位置に重なったほかの敵からずらす向き（ラジアン）。敵ごとに出したときに決める
	spin: number,
	lastAttack: number,
	lastHitBy: Player?,
	-- 攻撃を受けた反応（Combat/Hanno）
	body: Hanno.Body,
	-- 出てから受けた攻撃の数（確認用）
	hits: number,
	-- 最初に攻撃を受けた時刻（os.clock。確認用）
	firstHitAt: number?,
	-- 毒の間なら、その中身
	poison: Poison?,
}

-- 毒の中身
type Poison = {
	-- 毒を付けたプレイヤー
	attacker: Player?,
	-- 次に毒のダメージを与える時刻と、毒が切れる時刻（os.clock）
	nextTick: number,
	untilTime: number,
}

-- 攻撃を当てたときの反応の中身
export type Hit = Hanno.Hit

-- 敵が考えるときに狙うプレイヤー
type Target = {
	player: Player,
	root: BasePart,
}

local EnemyService = {}

-- 湧かせる敵の軍
local ENEMY_GUN: Gun.Gun = "Tekigun"
EnemyService.GUN = ENEMY_GUN

local gekihaEvent = Instance.new("BindableEvent")
-- プレイヤーが敵を倒したときに、種類（Genin・Jonin）・軍・倒れた位置（Vector3）・倒したプレイヤーで発火する。
-- 拠点の耐久（KyotenService）はこれを受けて減る
EnemyService.gekiha = gekihaEvent.Event

local enemiesFolder: Folder
local templates: { [string]: Model } = {}
local radii: { [string]: number } = {}
local enemies: { [Model]: Enemy } = {}
local aliveCount = 0
-- 敵に振る番号。モデルの名前を種類と番号（Genin1、Jonin2…）にする
local nextNumber = 1
-- 一定間隔の湧きを続けるか。窓口の SetSpawning で切り替える
local spawning = true
-- 敵が近づいて攻撃するか。窓口の SetEnemyAI で切り替える（止めても攻撃の反応と毒は進む）
local aiEnabled = true
-- 攻撃トークン。下忍はモデルの名前、プレイヤーは UserId の文字列で引く
local tokens = KogekiToken.new()
-- 最後に考えたときの、プレイヤーのキーごとの攻撃トークンの候補（窓口の DumpKogekiToken で出す）
local lastCandidates: { [string]: { KogekiToken.Candidate } } = {}
-- 攻撃トークンの受け渡しと攻撃を出力に出すか。窓口の LogKogekiToken で切り替える
local logTokens = false
-- 部隊を出す位置を区画の中から選ぶときに試す回数
local BUTAI_CENTER_TRIES = 16
-- 部隊を出した位置と、視界の外に出せず見送ったことを出力に出すか。窓口の LogSpawn で切り替える
local logSpawns = false
-- 攻撃が届く距離より、この距離（スタッド）だけ手前で止まる
local STAND_OFF_MARGIN = 0.5
-- Humanoid:MoveTo は、止まった状態から歩かせると目標の手前（スタッド。Studio で測ると 0.7〜0.8）で止まる。
-- 攻撃トークンを持つ下忍は、この分だけ内側を目指し、攻撃が届く距離の内で止まる
local ARRIVAL_GAP = 0.8
-- プレイヤーの中心からこの距離（スタッド）より近くにいるときは、1回の判断で進む距離を STEP に抑え、
-- 囲みの輪の上を回り込む
local NEAR_RANGE = 10
local STEP = 3
-- 倒れているときの、地面から HumanoidRootPart の中心までの高さ（体の大きさの倍率を掛ける）
local LIE_HEIGHT = 1
-- 毒の間に出す緑の煙の名前と色
local POISON_NAME = "Doku"
local POISON_COLOR = Color3.fromRGB(110, 210, 70)
local POISON_SECONDARY_COLOR = Color3.fromRGB(40, 110, 30)

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

-- 攻撃トークンを持たずに待っている下忍か
local function isWaiting(enemy: Enemy): boolean
	return enemy.kind == "Genin" and KogekiToken.ownerOf(tokens, enemy.model.Name) == nil
end

-- 立ち位置を決めるときの近くの敵（体が重なりうる距離にいる、生きている敵）。
-- attackersOnly なら待っている下忍を除く（攻撃する下忍が、外側で待つ下忍にずらされて攻撃が届かなくならないように）
local function neighborsOf(enemy: Enemy, attackersOnly: boolean): { EnemySpacing.Neighbor }
	local list = {}
	local position = enemy.root.Position
	for _, other in enemies do
		if other ~= enemy and other.humanoid.Health > 0 and not (attackersOnly and isWaiting(other)) then
			local p = other.root.Position
			local reach = enemy.radius + other.radius
			if math.abs(p.X - position.X) < reach and math.abs(p.Z - position.Z) < reach then
				table.insert(list, { x = p.X, z = p.Z, radius = other.radius })
			end
		end
	end
	return list
end

local function removePoisonLook(enemy: Enemy)
	local fire = enemy.root:FindFirstChild(POISON_NAME)
	if fire then
		fire:Destroy()
	end
end

-- 毒の間なら、間隔ごとに毒のダメージを与える。毒が切れたら見た目を外す
local function updatePoison(enemy: Enemy, now: number)
	local poison = enemy.poison
	if not poison then
		return
	end
	while now >= poison.nextTick and poison.nextTick <= poison.untilTime and enemy.humanoid.Health > 0 do
		poison.nextTick += Config.Poison.Interval
		if poison.attacker and poison.attacker.Parent then
			enemy.lastHitBy = poison.attacker
		end
		enemy.humanoid:TakeDamage(Config.Poison.Damage)
	end
	if now >= poison.untilTime or enemy.humanoid.Health <= 0 then
		enemy.poison = nil
		removePoisonLook(enemy)
	end
end

-- 攻撃トークンで引くプレイヤーのキー
local function keyOf(player: Player): string
	return tostring(player.UserId)
end

local function horizontalDistance(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- 吹き飛んで飛んでいる・倒れている・起き上がっている下忍は、攻撃トークンを持たない（のけぞりの間は持ったまま）
local function isDowned(enemy: Enemy): boolean
	local kind = Hanno.kindOf(enemy.body)
	return kind == "Air" or kind == "Down" or kind == "GetUp"
end

local function logToken(message: string)
	if logTokens then
		print(`[KogekiToken] {message}`)
	end
end

-- center から point までの水平の距離が maxReach より遠ければ、同じ向きで maxReach の位置へ寄せる
local function clampReach(point: EnemySpacing.Point, center: EnemySpacing.Point, maxReach: number): EnemySpacing.Point
	local dx, dz = point.x - center.x, point.z - center.z
	local reach = math.sqrt(dx * dx + dz * dz)
	if reach <= maxReach or reach < 1e-6 then
		return point
	end
	return { x = center.x + dx / reach * maxReach, z = center.z + dz / reach * maxReach }
end

-- 攻撃トークンを、各プレイヤーを狙っている下忍に合わせて返したり渡したりする
local function updateTokens(candidates: { [Player]: { KogekiToken.Candidate } }, now: number)
	table.clear(lastCandidates)
	for _, player in Players:GetPlayers() do
		local key = keyOf(player)
		local list = candidates[player] or {}
		lastCandidates[key] = list
		local changes = KogekiToken.update(tokens, key, list, now)
		local parts = {}
		if #changes.released > 0 then
			table.insert(parts, `{table.concat(changes.released, "、")} が返した`)
		end
		if #changes.given > 0 then
			table.insert(parts, `{table.concat(changes.given, "、")} が受け取った`)
		end
		if #parts > 0 then
			local count = KogekiToken.count(tokens, key)
			logToken(`{player.Name}: {table.concat(parts, "、")}（持っている {count} 体）`)
		end
	end
end

local function updateEnemy(enemy: Enemy, now: number, aim: Target?)
	updatePoison(enemy, now)
	if enemy.humanoid.Health <= 0 then
		return
	end
	if not aiEnabled then
		if not enemy.body.state then
			enemy.humanoid:Move(Vector3.zero)
		end
		return
	end
	-- のけぞりが明けたら動き出す。飛んでいる・倒れている・起き上がっている間は Hanno が進める
	if Hanno.busy(enemy.body, now) then
		return
	end
	if not aim then
		enemy.humanoid:Move(Vector3.zero)
		return
	end
	local targetPlayer, targetRoot = aim.player, aim.root
	-- 下忍は、狙うプレイヤーの攻撃トークンを持つときだけ攻撃する。持たなければ外側で囲んで待つ
	local key = keyOf(targetPlayer)
	local mayAttack = enemy.kind ~= "Genin" or KogekiToken.holds(tokens, key, enemy.model.Name)

	-- プレイヤーの手前で止まり、ほかの敵とも重ならない位置へ向かう
	local standOff = math.min(enemy.radius + Config.Spawner.PlayerGap, enemy.def.AttackRange - STAND_OFF_MARGIN)
	-- 攻撃トークンを持つ下忍は、待っている下忍を避けずに、歩いて止まっても攻撃が届く位置を目指す
	local attacking = enemy.kind == "Genin" and mayAttack
	if attacking then
		standOff = math.min(standOff, enemy.def.AttackRange - STAND_OFF_MARGIN - ARRIVAL_GAP)
	elseif not mayAttack then
		standOff += Config.KogekiToken.WaitGap
	end
	local position = enemy.root.Position
	local target = targetRoot.Position
	local here = { x = position.X, z = position.Z }
	local center = { x = target.X, z = target.Z }
	local goal = EnemySpacing.goal(here, enemy.radius, center, standOff, neighborsOf(enemy, attacking), enemy.spin)
	if EnemySpacing.shouldMove(goal, standOff) then
		local point = goal.point
		if attacking then
			-- ほかの攻撃する敵とずらしても、目指す位置は手前の距離より外へ出さない
			point = clampReach(point, center, standOff)
		end
		if goal.distance < NEAR_RANGE then
			point = EnemySpacing.stepToward(here, point, center, standOff, STEP)
		end
		enemy.humanoid:MoveTo(Vector3.new(point.x, position.Y, point.z))
	else
		enemy.humanoid:Move(Vector3.zero)
	end

	if not mayAttack or goal.distance > enemy.def.AttackRange then
		return
	end
	if now - enemy.lastAttack < enemy.def.AttackCooldown then
		return
	end
	enemy.lastAttack = now

	DamageService.damage(targetPlayer, {
		origin = enemy.root.Position,
		power = enemy.def.Damage,
		reaction = enemy.def.Reaction,
	})
	-- 攻撃した下忍は攻撃トークンを返し、しばらく休む
	if enemy.kind == "Genin" and KogekiToken.attacked(tokens, key, enemy.model.Name, now) then
		local count = KogekiToken.count(tokens, key)
		logToken(`{targetPlayer.Name}: {enemy.model.Name} が攻撃して返した（持っている {count} 体）`)
	end
end

-- 考える間隔ごとに、敵ごとに狙うプレイヤーを決め、攻撃トークンを渡してから動かす
local function think(now: number)
	local aims: { [Enemy]: Target } = {}
	local candidates: { [Player]: { KogekiToken.Candidate } } = {}
	if aiEnabled then
		for _, enemy in enemies do
			if enemy.humanoid.Health > 0 then
				local player, root = findNearestTarget(enemy.root.Position)
				if player and root then
					aims[enemy] = { player = player, root = root }
					if enemy.kind == "Genin" and not isDowned(enemy) then
						local list = candidates[player]
						if not list then
							list = {}
							candidates[player] = list
						end
						table.insert(list, {
							id = enemy.model.Name,
							distance = horizontalDistance(enemy.root.Position, root.Position),
						})
					end
				end
			end
		end
		updateTokens(candidates, now)
	end
	for _, enemy in enemies do
		updateEnemy(enemy, now, aims[enemy])
	end
end

local function onEnemyDied(enemy: Enemy)
	-- 片付けで先に表から外した敵は数え直さない
	if enemies[enemy.model] == nil then
		return
	end
	enemies[enemy.model] = nil
	aliveCount -= 1
	-- 持っていた攻撃トークンは、次に考えるときに近い下忍へ渡る
	local owner = KogekiToken.ownerOf(tokens, enemy.model.Name)
	KogekiToken.forget(tokens, enemy.model.Name)
	if owner then
		local holder = Players:GetPlayerByUserId(tonumber(owner) or 0)
		local count = KogekiToken.count(tokens, owner)
		logToken(
			`{if holder then holder.Name else owner}: {enemy.model.Name} が倒れて返した（持っている {count} 体）`
		)
	end
	-- 毒の間に倒れたら、毒の煙を消す
	enemy.poison = nil
	removePoisonLook(enemy)

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
	model.Name = `{kind}{nextNumber}`
	nextNumber += 1
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart

	if not Ground.placeCharacter(model, x, z) then
		model:Destroy()
		return nil
	end
	model.Parent = enemiesFolder
	-- ノックバックの挙動を安定させるため物理はサーバーが持つ
	root:SetNetworkOwner(nil)

	local reaction = Config.EnemyReaction
	local enemy: Enemy = {
		kind = kind,
		model = model,
		humanoid = humanoid,
		root = root,
		def = def,
		radius = radii[kind],
		spin = math.random() * math.pi * 2,
		lastAttack = 0,
		lastHitBy = nil,
		body = Hanno.newBody(model, humanoid, root, {
			lieHeight = LIE_HEIGHT * def.Scale,
			scale = if kind == "Jonin" then reaction.JoninScale else 1,
			flinchScale = if kind == "Jonin" then reaction.JoninFlinchScale else 1,
		}),
		hits = 0,
		firstHitAt = nil,
		poison = nil,
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

local function logSpawn(message: string)
	if logSpawns then
		print(`[Spawner] {message}`)
	end
end

-- 部隊を出す水平位置。Vector2 の X と Y にワールドの X と Z を入れる。高さは spawnEnemy が地面に合わせる。
-- 戦闘のフェーズで、区画の中にいるメンバーの周りの、区画の中の位置を選ぶ。
-- 出撃メンバーの誰かの視界にかかる位置は選ばない（CameraViewService）。選べなければ nil（次の湧きで選び直す）
local function pickButaiCenter(): Vector2?
	local bounds = battleBounds()
	if not bounds then
		return nil
	end
	local members = StageService.getMembers()
	local candidates = {}
	for _, member in members do
		local root = member.Character and member.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and insideBounds(bounds, root.Position) then
			table.insert(candidates, root.Position)
		end
	end
	if #candidates == 0 then
		return nil
	end

	local base = candidates[math.random(1, #candidates)]
	local seen = 0
	for _ = 1, BUTAI_CENTER_TRIES do
		local angle = math.random() * math.pi * 2
		local distance = Config.Spawner.MinDistance
			+ math.random() * (Config.Spawner.MaxDistance - Config.Spawner.MinDistance)
		local center = base + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		if insideBounds(bounds, center) then
			if not CameraViewService.seenByAny(members, center) then
				logSpawn(
					string.format(
						"部隊を (%.0f, %.0f) に出した（出撃メンバーの視界の外）",
						center.X,
						center.Z
					)
				)
				return Vector2.new(center.X, center.Z)
			end
			seen += 1
		end
	end
	if seen > 0 then
		logSpawn(`視界の外に出せる位置が無く、見送った（{seen} か所が視界にかかった）`)
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

-- 攻撃側から呼ばれる被ダメージ処理。撃破数はとどめを刺したプレイヤーに付く。
-- hit を渡すと、反応（のけぞり・吹き飛び・打ち上げ）を始める。当てたら true
function EnemyService.damage(model: Model, amount: number, attacker: Player?, hit: Hit?): boolean
	local enemy = enemies[model]
	if not enemy or enemy.humanoid.Health <= 0 then
		return false
	end

	-- とどめを刺した人の撃破に数える。攻撃した人がいなければ（NPC の秘計、味方軍の上忍と首領の型など）、
	-- 前に攻撃した人の撃破にもしない
	enemy.lastHitBy = attacker
	enemy.hits += 1
	enemy.firstHitAt = enemy.firstHitAt or os.clock()
	enemy.humanoid:TakeDamage(amount)
	if hit then
		Hanno.react(enemy.body, hit, os.clock())
	end
	return true
end

-- 毒にする。毒の間は Config.luau の Poison 節の間隔ごとにダメージを与え、とどめは attacker の撃破に数える。
-- 毒の間にもう一度付けたら、残りの時間を Duration に戻す。倒れた敵は毒にしない（false）
function EnemyService.poison(model: Model, attacker: Player?): boolean
	local enemy = enemies[model]
	if not enemy or enemy.humanoid.Health <= 0 then
		return false
	end
	local now = os.clock()
	local current = enemy.poison
	if current then
		current.untilTime = now + Config.Poison.Duration
		current.attacker = attacker or current.attacker
		return true
	end
	enemy.poison = {
		attacker = attacker,
		nextTick = now + Config.Poison.Interval,
		untilTime = now + Config.Poison.Duration,
	}
	if not enemy.root:FindFirstChild(POISON_NAME) then
		local fire = Instance.new("Fire")
		fire.Name = POISON_NAME
		fire.Color = POISON_COLOR
		fire.SecondaryColor = POISON_SECONDARY_COLOR
		fire.Size = 3 * enemy.def.Scale
		fire.Heat = 2
		fire.Parent = enemy.root
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
	for model, enemy in enemies do
		Hanno.forget(enemy.body)
		model:Destroy()
	end
	table.clear(enemies)
	aliveCount = 0
	enemiesFolder:ClearAllChildren()
	nextNumber = 1
	KogekiToken.reset(tokens)
	table.clear(lastCandidates)
end

function EnemyService.start()
	enemiesFolder = Instance.new("Folder")
	enemiesFolder.Name = "Enemies"
	enemiesFolder.Parent = workspace
	-- 飛んでいる敵の光線を、ほかの敵に当てない
	Hanno.excludeFolder(enemiesFolder)

	-- 戦闘のフェーズが終わったら片付ける
	StageService.phaseChanged:Connect(function(next: StagePhase.Phase)
		if next ~= "Battle" then
			removeAll()
		end
	end)

	for kind, def in ENEMY_DEFS do
		local template = buildTemplate(kind, def)
		-- 敵は体ではプレイヤーにもほかの敵にもぶつからない。複製した敵もこのグループになる
		CollisionGroups.apply(template, CollisionGroups.ENEMY)
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
			return string.format(
				"%s を (%.1f, %.1f, %.1f) に出した",
				model.Name,
				position.X,
				position.Y,
				position.Z
			)
		end
	)

	DebugCommand.register(
		"DumpEnemies",
		"",
		"生きている仮の湧き処理の敵（名前・種類・体力・受けた攻撃の数・最初に受けてからの秒数・反応の状態・毒の残り秒数・"
			.. "攻撃トークンを持っている相手のプレイヤー・位置）を JSON で返す",
		function()
			local list = {}
			local now = os.clock()
			for model, enemy in enemies do
				if enemy.humanoid.Health > 0 then
					local position = enemy.root.Position
					local poison = enemy.poison
					local firstHitAt = enemy.firstHitAt
					local owner = KogekiToken.ownerOf(tokens, model.Name)
					local holder = if owner then Players:GetPlayerByUserId(tonumber(owner) or 0) else nil
					table.insert(list, {
						name = model.Name,
						kind = enemy.kind,
						health = math.round(enemy.humanoid.Health * 10) / 10,
						hits = enemy.hits,
						firstHitAgo = if firstHitAt then math.round((now - firstHitAt) * 100) / 100 else nil,
						hanno = Hanno.kindOf(enemy.body),
						poison = if poison then math.max(math.round((poison.untilTime - now) * 10) / 10, 0) else nil,
						token = if holder then holder.Name else nil,
						position = { math.round(position.X), math.round(position.Y), math.round(position.Z) },
					})
				end
			end
			table.sort(list, function(a, b)
				return a.name < b.name
			end)
			return HttpService:JSONEncode(list)
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
		"SetEnemyAI",
		"<true|false>",
		"仮の湧き処理の敵が近づいて攻撃するかを切り替える。止めてもその場で攻撃の反応（吹き飛び・ダウン）と毒は進む（確認用）",
		function(value)
			aiEnabled = value == true or value == "true"
			if not aiEnabled then
				for _, enemy in enemies do
					if not enemy.body.state then
						Hanno.stopWalking(enemy.body)
					end
				end
			end
			return `敵の動きと攻撃を{if aiEnabled then "再開した" else "止めた"}`
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
		"DefeatEnemy",
		"<敵の名前>",
		"仮の湧き処理の敵を名前（DumpEnemies の name）で1体倒す。撃破数には数えない（確認用）",
		function(enemyName)
			for model, enemy in enemies do
				if model.Name == enemyName and enemy.humanoid.Health > 0 then
					enemy.lastHitBy = nil
					enemy.humanoid.Health = 0
					return `{model.Name} を倒した`
				end
			end
			return `生きている敵 {tostring(enemyName)} はいない`
		end
	)

	DebugCommand.register(
		"SpawnEnemies",
		"<プレイヤー名> <数> [距離]",
		"プレイヤーの周りの円（既定は半径 20 スタッド）に、下忍を等しい間隔で出す（確認用）",
		function(name, countValue, distanceValue)
			local player = DebugCommand.findPlayer(name)
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not root then
				return `{player.Name} のキャラクターがいない`
			end
			local count = math.floor(DebugCommand.toNumber(countValue, "数"))
			local distance = if distanceValue ~= nil then DebugCommand.toNumber(distanceValue, "距離") else 20
			local names = {}
			for index = 1, count do
				local angle = (index - 1) / count * math.pi * 2
				local model = spawnEnemy(
					"Genin",
					root.Position.X + math.cos(angle) * distance,
					root.Position.Z + math.sin(angle) * distance
				)
				if model then
					table.insert(names, model.Name)
				end
			end
			local list = table.concat(names, "、")
			return `{player.Name} の周り {distance} スタッドに下忍を {#names} 体出した（{list}）`
		end
	)

	DebugCommand.register(
		"DumpKogekiToken",
		"",
		"プレイヤーごとの攻撃トークン（持っている下忍の名前と距離、待っている下忍の数、攻撃して休んでいる下忍の数、"
			.. "攻撃して返されてまだ渡せない攻撃トークンの数）を JSON で返す",
		function()
			local now = os.clock()
			local result = {}
			for _, player in Players:GetPlayers() do
				local key = keyOf(player)
				local distances: { [string]: number } = {}
				local waiting, resting = 0, 0
				for _, candidate in lastCandidates[key] or {} do
					distances[candidate.id] = candidate.distance
					if not KogekiToken.holds(tokens, key, candidate.id) then
						if KogekiToken.isResting(tokens, candidate.id, now) then
							resting += 1
						else
							waiting += 1
						end
					end
				end
				local holders = {}
				for _, id in KogekiToken.holderIds(tokens, key) do
					local distance = distances[id]
					table.insert(holders, {
						name = id,
						distance = if distance then math.round(distance * 10) / 10 else nil,
					})
				end
				table.insert(result, {
					player = player.Name,
					perPlayer = Config.KogekiToken.PerPlayer,
					holders = holders,
					waiting = waiting,
					resting = resting,
					cooling = KogekiToken.coolingCount(tokens, key, now),
				})
			end
			return HttpService:JSONEncode(result)
		end
	)

	DebugCommand.register(
		"LogSpawn",
		"<true|false>",
		"一定間隔の湧きで部隊を出した位置と、出撃メンバーの視界の外に出せず見送ったことを出力に出す（確認用）",
		function(value)
			logSpawns = value == true or value == "true"
			return `湧きの記録を{if logSpawns then "出す" else "止めた"}`
		end
	)

	DebugCommand.register(
		"LogKogekiToken",
		"<true|false>",
		"攻撃トークンの受け渡しと、攻撃トークンを持つ下忍の攻撃を出力に出す（確認用）",
		function(value)
			logTokens = value == true or value == "true"
			return `攻撃トークンの記録を{if logTokens then "出す" else "止めた"}`
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

	-- いなくなったプレイヤーの攻撃トークンを返す
	Players.PlayerRemoving:Connect(function(player)
		KogekiToken.removePlayer(tokens, keyOf(player))
		lastCandidates[keyOf(player)] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(Config.Spawner.AITickInterval)
			think(os.clock())
		end
	end)
end

return EnemyService
