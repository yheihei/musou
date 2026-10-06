--!strict
-- 敵兵の生成・AI・被ダメージ処理。
-- 戦闘のフェーズの間だけ、出撃したステージの区画にいるメンバーの周りに、下忍を部隊単位で湧かせ続け、
-- 一定部隊ごとに上忍を混ぜる。戦闘のフェーズが終わったら（決着・ロビーへの帰還・全員の離脱）敵を片付ける。
-- プレイヤーへの攻撃は DamageService の被ダメージの窓口に渡す。
-- 湧かせる敵は敵軍で、部隊のデータ（ButaiService）には属さない（実体化圏での出し入れは #76 で置き換える）。
-- 敵は近づいて攻撃するだけで、体ではプレイヤーにもほかの敵にもぶつからない（CollisionGroups の Enemy）。
-- 重ならないよう、プレイヤーの手前で止まり、ほかの敵とも離れて囲む（立ち位置の計算は EnemySpacing）。
-- プレイヤーが倒した敵は、撃破数を足し、gekiha で種類・軍・倒れた位置・倒したプレイヤーを知らせる。
--
-- 攻撃を受けた敵の反応（数値は Config.luau の EnemyReaction 節）
-- - のけぞりの攻撃を地上で受けると、Flinch 秒だけ動かず攻撃もしない。上忍は JoninFlinchScale を掛けた秒数（0 ならのけぞらない）
-- - 吹き飛びと打ち上げは、物理演算に任せず、初速と重力から決めた軌道（ReplicatedStorage.Shared.Trajectory）で動かす。
--   飛んでいる間は HumanoidRootPart を固定し、フレームごとに軌道の位置へ置く。上忍は JoninScale を掛けた初速で短く飛ぶ
-- - 空中で攻撃を受けたら、その位置から軌道をやり直す（追撃で再び浮く）。空中でののけぞりは浮かせ直す
-- - 落ちている途中で足が地面（真下へ当てた光線。Ground.raycast）に届いたら着地し、仰向けに倒れる（ダウン）。
--   Down 秒たったら起き上がり、GetUp 秒たったら固定を外して動き出す。倒れている間に吹き飛びか打ち上げを受けると、また飛ぶ
-- - 飛んでいる間は、前のフレームの位置から今の位置へ光線を当て、物に当たったら手前で止める。床（上を向いた面）なら
--   そこに着地し、壁や天井なら来た向きへ少し戻って、面へ向かう速さを消して面に沿って滑らせる（壁や屋根を通り抜けない）。
--   急な面（壁）の上には着地しない。
--   光線は当たり判定の無い部品（CanCollide が false）には当てない
-- - 倒された敵は、飛んでいれば着地まで飛び、倒れたまま残る。倒れている間か起き上がる途中で倒されても、倒れたまま残る
-- - 反応の最中は、近づくことも攻撃することもしない
--
-- 毒（酉花の奥義「毒手裏剣」。数値は Config.luau の Poison 節）
-- - 毒の間は Interval 秒ごとに Damage を与える。とどめは毒を付けたプレイヤーの撃破に数える
-- - 毒の間にもう一度付けると、残りの時間を Duration に戻す。毒の間は緑の煙（Fire）の仮の見た目を出す

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Appearance = require(ReplicatedStorage.Shared.Appearance)
local Characters = require(ReplicatedStorage.Shared.Characters)
local Config = require(ReplicatedStorage.Shared.Config)
local EnemySpacing = require(ReplicatedStorage.Shared.EnemySpacing)
local Ground = require(ReplicatedStorage.Shared.Ground)
local Gun = require(ReplicatedStorage.Shared.Gun)
local HitShape = require(ReplicatedStorage.Shared.HitShape)
local Mejirushi = require(ReplicatedStorage.Shared.Mejirushi)
local StagePhase = require(ReplicatedStorage.Shared.StagePhase)
local Stages = require(ReplicatedStorage.Shared.Stages)
local Trajectory = require(ReplicatedStorage.Shared.Trajectory)
local DebugCommand = require(script.Parent.Parent.DebugCommand)
local DamageService = require(script.Parent.DamageService)
local KukakuService = require(script.Parent.KukakuService)
local PlayerService = require(script.Parent.PlayerService)
local StageService = require(script.Parent.StageService)
local CollisionGroups = require(script.Parent.Parent.CollisionGroups)

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

-- 攻撃を受けた反応の状態。Flinch はのけぞり、Air は吹き飛びか打ち上げで飛んでいる間、
-- Down は着地して倒れている間、GetUp は起き上がり
type Hanno = {
	kind: "Flinch" | "Air" | "Down" | "GetUp",
	-- この状態を始めた時刻（os.clock）
	startedAt: number,
	-- この状態が終わる時刻（os.clock）。Air は着地するまで続くので math.huge
	untilTime: number,
	-- 飛んでいる間の軌道
	trajectory: Trajectory.Trajectory?,
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
	-- 立っているときの、地面から HumanoidRootPart の中心までの高さ
	standHeight: number,
	-- 攻撃を受けた反応の最中なら、その状態
	hanno: Hanno?,
	-- 飛んでいる間と倒れている間に保つ向き（回転だけの CFrame）
	facing: CFrame,
	-- 最後に着地した地面の高さ
	groundY: number?,
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
export type Hit = {
	reaction: Config.Reaction,
	-- 攻撃元の位置。吹き飛ぶ向きを決める
	origin: Vector3,
	-- 技の吹き飛ばす強さ（Config.luau の HitDef の Knockback）
	force: number,
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
-- 飛んでいるか、倒れているか、起き上がっている敵。フレームごとに動かす（倒された敵も着地するまで入る）
local reacting: { [Model]: Enemy } = {}
-- 一定間隔の湧きを続けるか。窓口の SetSpawning で切り替える
local spawning = true
-- 敵が近づいて攻撃するか。窓口の SetEnemyAI で切り替える（止めても攻撃の反応と毒は進む）
local aiEnabled = true
-- 部隊を出す位置を区画の中から選ぶときに試す回数
local BUTAI_CENTER_TRIES = 8
-- 攻撃が届く距離より、この距離（スタッド）だけ手前で止まる
local STAND_OFF_MARGIN = 0.5
-- プレイヤーの中心からこの距離（スタッド）より近くにいるときは、1回の判断で進む距離を STEP に抑え、
-- 囲みの輪の上を回り込む
local NEAR_RANGE = 10
local STEP = 3
-- 飛んでいる敵が床とみなす面の向き（面の法線の上向きの成分の下限）
local FLOOR_NORMAL_Y = 0.7
-- 壁や天井に当たったとき、当たった位置から来た向きへ戻す距離（スタッド）。細い隙間の向こうへ押し出さないよう小さくする
local CONTACT_OFFSET = 0.1
-- 足の下の地面を探す光線を、立っているときの高さより少しだけ長くする（ちょうどの長さでは当たり損ねることがあるため）
local BELOW_MARGIN = 0.1
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

-- 立ち位置を決めるときの近くの敵（体が重なりうる距離にいる、生きている敵）
local function neighborsOf(enemy: Enemy): { EnemySpacing.Neighbor }
	local list = {}
	local position = enemy.root.Position
	for _, other in enemies do
		if other ~= enemy and other.humanoid.Health > 0 then
			local p = other.root.Position
			local reach = enemy.radius + other.radius
			if math.abs(p.X - position.X) < reach and math.abs(p.Z - position.Z) < reach then
				table.insert(list, { x = p.X, z = p.Z, radius = other.radius })
			end
		end
	end
	return list
end

-- 歩くのをやめさせる
local function stopWalking(enemy: Enemy)
	enemy.humanoid:MoveTo(enemy.root.Position)
	enemy.humanoid:Move(Vector3.zero)
end

-- HumanoidRootPart を固定し、軌道と倒れた姿勢をスクリプトで決められるようにする
local function anchor(enemy: Enemy)
	stopWalking(enemy)
	enemy.root.Anchored = true
end

-- 固定を外し、物理をサーバーに持たせ直す
local function release(enemy: Enemy)
	enemy.root.Anchored = false
	pcall(function()
		enemy.root:SetNetworkOwner(nil)
	end)
end

-- 攻撃元 origin の方を向く向き（回転だけ）。向きが決まらなければ今の向き
local function facingToward(enemy: Enemy, origin: Vector3): CFrame
	local position = enemy.root.Position
	local back = Vector3.new(origin.X - position.X, 0, origin.Z - position.Z)
	if back.Magnitude < 0.01 then
		return enemy.root.CFrame.Rotation
	end
	return CFrame.lookAt(Vector3.zero, back.Unit)
end

-- position から初速 velocity で飛ばす
local function startFlight(enemy: Enemy, velocity: vector, position: Vector3, attackOrigin: Vector3, now: number)
	enemy.facing = facingToward(enemy, attackOrigin)
	anchor(enemy)
	enemy.hanno = {
		kind = "Air",
		startedAt = now,
		untilTime = math.huge,
		trajectory = Trajectory.new(position, velocity),
	}
	enemy.root.CFrame = CFrame.new(position) * enemy.facing
	reacting[enemy.model] = enemy
end

-- 攻撃を受けた反応を始める
local function react(enemy: Enemy, hit: Hit, now: number)
	local state = enemy.hanno
	local airborne = state ~= nil and state.kind == "Air"
	local params = Config.EnemyReaction
	local scale = if enemy.kind == "Jonin" then params.JoninScale else 1
	local position = enemy.root.Position
	local velocity = Trajectory.initialVelocity(hit.reaction, position - hit.origin, hit.force, airborne, scale)
	if velocity then
		-- 倒れているところから飛ばすときは、立っているときの高さから飛ばす
		local lying = state ~= nil and (state.kind == "Down" or state.kind == "GetUp")
		local from = if lying
			then Vector3.new(position.X, (enemy.groundY or position.Y) + enemy.standHeight, position.Z)
			else position
		startFlight(enemy, velocity, from, hit.origin, now)
		return
	end
	if hit.reaction ~= "Flinch" or enemy.humanoid.Health <= 0 then
		return
	end
	if state ~= nil and state.kind ~= "Flinch" then
		return
	end
	local seconds = params.Flinch * (if enemy.kind == "Jonin" then params.JoninFlinchScale else 1)
	if seconds > 0 then
		enemy.hanno = { kind = "Flinch", startedAt = now, untilTime = now + seconds, trajectory = nil }
		stopWalking(enemy)
	end
end

-- 地面の高さ groundY の (x, z) に仰向けに寝かせる
local function lieDown(enemy: Enemy, x: number, groundY: number, z: number)
	enemy.groundY = groundY
	local scale = enemy.def.Scale
	enemy.root.CFrame = CFrame.new(x, groundY + LIE_HEIGHT * scale, z)
		* enemy.facing
		* CFrame.Angles(math.rad(90), 0, 0)
end

-- 倒された敵を倒れたまま残し、消えるのを待つ
local function stayDown(enemy: Enemy, now: number)
	enemy.hanno = { kind = "Down", startedAt = now, untilTime = math.huge, trajectory = nil }
	reacting[enemy.model] = nil
end

-- 着地して仰向けに倒れる
local function land(enemy: Enemy, x: number, groundY: number, z: number, now: number)
	lieDown(enemy, x, groundY, z)
	if enemy.humanoid.Health <= 0 then
		stayDown(enemy, now)
		return
	end
	enemy.hanno = { kind = "Down", startedAt = now, untilTime = now + Config.EnemyReaction.Down, trajectory = nil }
end

-- 足の下（HumanoidRootPart の中心から立っているときの高さまで）に床（上を向いた面）があれば着地させ、true を返す。
-- 壁のような急な面には着地しない
local function landIfGrounded(enemy: Enemy, position: vector, now: number, excluded: { Instance }): boolean
	local below = Ground.raycast(position, vector.create(0, -(enemy.standHeight + BELOW_MARGIN), 0), excluded, true)
	if not below or below.Normal.Y < FLOOR_NORMAL_Y then
		return false
	end
	land(enemy, position.x, below.Position.Y, position.z, now)
	return true
end

-- 飛んでいる途中で壁か天井に当たったら、当たった位置から来た向きへ少し戻り、面へ向かう速さを消して面に沿って滑らせ直す。
-- 面の向き（法線）でなく来た向きへ戻すので、鋭い角でも反対の壁の中へ入らない。heading は動いてきた向きの単位ベクトル
local function slide(enemy: Enemy, state: Hanno, hit: RaycastResult, heading: Vector3, velocity: vector, now: number)
	local normal = hit.Normal
	local position = hit.Position - heading * CONTACT_OFFSET
	local into = velocity:Dot(normal)
	local along = if into < 0 then velocity - normal * into else velocity
	state.trajectory = Trajectory.new(position, along)
	state.startedAt = now
	enemy.root.CFrame = CFrame.new(position) * enemy.facing
end

-- 飛んでいる敵を軌道の位置へ置く。途中で物に当たったら止め、落ちている途中で足が地面に届いたら着地させる。
-- excluded は光線を当てない部品（Ground.excludedOf）
local function updateFlight(enemy: Enemy, state: Hanno, now: number, excluded: { Instance })
	local trajectory = state.trajectory :: Trajectory.Trajectory
	local elapsed = now - state.startedAt
	local position = Trajectory.positionAt(trajectory, elapsed)
	local velocity = Trajectory.velocityAt(trajectory, elapsed)
	local from = enemy.root.Position
	local step = position - from
	if step.Magnitude > 1e-3 then
		local hit = Ground.raycast(from, step, excluded, true)
		if hit then
			if hit.Normal.Y >= FLOOR_NORMAL_Y then
				land(enemy, hit.Position.X, hit.Position.Y, hit.Position.Z, now)
				return
			end
			slide(enemy, state, hit, step.Unit, velocity, now)
			-- 滑らせた先の足の下に地面があれば、そこで着地する（斜めの天井と床の間で床を抜けない）
			landIfGrounded(enemy, enemy.root.Position, now, excluded)
			return
		end
	end
	if velocity.y <= 0 then
		if landIfGrounded(enemy, position, now, excluded) then
			return
		end
		if position.y < workspace.FallenPartsDestroyHeight then
			-- 奈落に落ちた
			reacting[enemy.model] = nil
			enemy.humanoid.Health = 0
			enemy.model:Destroy()
			return
		end
	end
	enemy.root.CFrame = CFrame.new(position) * enemy.facing
end

-- 飛んでいる・倒れている・起き上がっている敵を進める。excluded は光線を当てない部品（Ground.excludedOf）
local function updateReaction(enemy: Enemy, now: number, excluded: { Instance })
	local state = enemy.hanno
	if not state then
		reacting[enemy.model] = nil
		return
	end
	if state.kind ~= "Air" and enemy.humanoid.Health <= 0 then
		-- 倒れている間か起き上がる途中で倒された敵は、寝かせ直して倒れたまま残す
		if state.kind == "GetUp" then
			local position = enemy.root.Position
			lieDown(enemy, position.X, enemy.groundY or (position.Y - enemy.standHeight), position.Z)
		end
		stayDown(enemy, now)
		return
	end
	if state.kind == "Air" then
		updateFlight(enemy, state, now, excluded)
	elseif state.kind == "Down" and now >= state.untilTime then
		-- 起き上がる
		local position = enemy.root.Position
		local groundY = enemy.groundY or position.Y
		enemy.root.CFrame = CFrame.new(position.X, groundY + enemy.standHeight, position.Z) * enemy.facing
		enemy.hanno =
			{ kind = "GetUp", startedAt = now, untilTime = now + Config.EnemyReaction.GetUp, trajectory = nil }
	elseif state.kind == "GetUp" and now >= state.untilTime then
		enemy.hanno = nil
		reacting[enemy.model] = nil
		release(enemy)
	end
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

local function updateEnemy(enemy: Enemy, now: number)
	updatePoison(enemy, now)
	if enemy.humanoid.Health <= 0 then
		return
	end
	if not aiEnabled then
		if not enemy.hanno then
			enemy.humanoid:Move(Vector3.zero)
		end
		return
	end
	local hanno = enemy.hanno
	if hanno then
		-- のけぞりが明けたら動き出す。飛んでいる・倒れている・起き上がっている間は updateReaction が進める
		if hanno.kind ~= "Flinch" or now < hanno.untilTime then
			return
		end
		enemy.hanno = nil
	end
	local targetPlayer, targetRoot = findNearestTarget(enemy.root.Position)
	if not targetPlayer or not targetRoot then
		enemy.humanoid:Move(Vector3.zero)
		return
	end

	-- プレイヤーの手前で止まり、ほかの敵とも重ならない位置へ向かう
	local standOff = math.min(enemy.radius + Config.Spawner.PlayerGap, enemy.def.AttackRange - STAND_OFF_MARGIN)
	local position = enemy.root.Position
	local target = targetRoot.Position
	local here = { x = position.X, z = position.Z }
	local center = { x = target.X, z = target.Z }
	local goal = EnemySpacing.goal(here, enemy.radius, center, standOff, neighborsOf(enemy), enemy.spin)
	if EnemySpacing.shouldMove(goal, standOff) then
		local point = goal.point
		if goal.distance < NEAR_RANGE then
			point = EnemySpacing.stepToward(here, point, center, standOff, STEP)
		end
		enemy.humanoid:MoveTo(Vector3.new(point.x, position.Y, point.z))
	else
		enemy.humanoid:Move(Vector3.zero)
	end

	if goal.distance > enemy.def.AttackRange then
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
end

local function onEnemyDied(enemy: Enemy)
	-- 片付けで先に表から外した敵は数え直さない
	if enemies[enemy.model] == nil then
		return
	end
	enemies[enemy.model] = nil
	aliveCount -= 1
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
		standHeight = humanoid.HipHeight + root.Size.Y / 2,
		hanno = nil,
		facing = root.CFrame.Rotation,
		groundY = nil,
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

-- 攻撃側から呼ばれる被ダメージ処理。撃破数はとどめを刺したプレイヤーに付く。
-- hit を渡すと、反応（のけぞり・吹き飛び・打ち上げ）を始める。当てたら true
function EnemyService.damage(model: Model, amount: number, attacker: Player?, hit: Hit?): boolean
	local enemy = enemies[model]
	if not enemy or enemy.humanoid.Health <= 0 then
		return false
	end

	-- とどめを刺した人の撃破に数える。攻撃した人がいなければ（NPC の秘計など）、前に攻撃した人の撃破にもしない
	enemy.lastHitBy = attacker
	enemy.hits += 1
	enemy.firstHitAt = enemy.firstHitAt or os.clock()
	enemy.humanoid:TakeDamage(amount)
	if hit then
		react(enemy, hit, os.clock())
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
	for model in enemies do
		model:Destroy()
	end
	table.clear(enemies)
	table.clear(reacting)
	aliveCount = 0
	enemiesFolder:ClearAllChildren()
	nextNumber = 1
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
		"生きている仮の湧き処理の敵（名前・種類・体力・受けた攻撃の数・最初に受けてからの秒数・反応の状態・毒の残り秒数・位置）を JSON で返す",
		function()
			local list = {}
			local now = os.clock()
			for model, enemy in enemies do
				if enemy.humanoid.Health > 0 then
					local position = enemy.root.Position
					local poison = enemy.poison
					local firstHitAt = enemy.firstHitAt
					table.insert(list, {
						name = model.Name,
						kind = enemy.kind,
						health = math.round(enemy.humanoid.Health * 10) / 10,
						hits = enemy.hits,
						firstHitAgo = if firstHitAt then math.round((now - firstHitAt) * 100) / 100 else nil,
						hanno = if enemy.hanno then enemy.hanno.kind else nil,
						poison = if poison then math.max(math.round((poison.untilTime - now) * 10) / 10, 0) else nil,
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
					if not enemy.hanno then
						stopWalking(enemy)
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

	-- 飛んでいる・倒れている・起き上がっている敵は、フレームごとに進める
	RunService.Heartbeat:Connect(function()
		if next(reacting) == nil then
			return
		end
		local now = os.clock()
		-- 光線を当てない部品の一覧はフレームごとに1回だけ作る。敵どうしには当てない
		local excluded = Ground.excludedOf({ enemiesFolder })
		for model, enemy in reacting do
			if not model.Parent then
				reacting[model] = nil
				continue
			end
			local ok, err = pcall(updateReaction, enemy, now, excluded)
			if not ok then
				reacting[model] = nil
				enemy.hanno = nil
				release(enemy)
				warn(`EnemyService: {model.Name} の反応を進められなかった: {err}`)
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
