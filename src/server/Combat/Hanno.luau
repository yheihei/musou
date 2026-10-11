--!strict
-- 攻撃を受けた NPC の個体の反応。両軍の下忍の個体と窓口で出した敵（EnemyService）と、上忍・首領の個体（JoninKotaiService）が共有する。
-- 数値は Config.luau の EnemyReaction 節、吹き飛びと打ち上げの軌道は ReplicatedStorage.Shared.Trajectory にある。
--
-- - のけぞりの攻撃を地上で受けると、Flinch 秒だけ動かず攻撃もしない。秒数には個体ごとの倍率（flinchScale）を掛け、
--   0 ならのけぞらない（上忍と首領は Config.luau の JoninFlinchScale）
-- - 吹き飛びと打ち上げは、物理演算に任せず、初速と重力から決めた軌道で動かす。初速には個体ごとの倍率（scale）を掛ける。
--   飛んでいる間は HumanoidRootPart を固定し、フレームごとに軌道の位置へ置く
-- - 空中で攻撃を受けたら、その位置から軌道をやり直す（追撃で再び浮く）。空中でののけぞりは浮かせ直す
-- - 落ちている途中で足が地面（真下へ当てた光線。Ground.raycast）に届いたら着地し、仰向けに倒れる（ダウン）。
--   Down 秒たったら起き上がり、GetUp 秒たったら固定を外して動き出す。倒れている間に吹き飛びか打ち上げを受けると、また飛ぶ
-- - 飛んでいる間は、前のフレームの位置から今の位置へ光線を当て、物に当たったら手前で止める。床（上を向いた面）なら
--   そこに着地し、壁や天井なら面から少し離して、面へ向かう速さを消して面に沿って滑らせる（壁や屋根を通り抜けない）。
--   急な面（壁）の上には着地しない。床の無い急な面の間などで MAX_FLIGHT_TIME 秒たっても着地しなければ、その場に倒れる。
--   光線は当たり判定の無い部品（CanCollide が false）と、excludeFolder で渡したフォルダ（個体を置くフォルダ）には当てない
-- - 倒された個体（Humanoid の体力が 0）は、飛んでいれば着地まで飛び、倒れたまま残る。
--   倒れている間か起き上がる途中で倒されても、倒れたまま残る
-- - 奈落に落ちたら、個体の onFell を呼ぶ（無ければ体力を 0 にしてモデルを消す）
-- - 反応の最中は、近づくことも攻撃することもしない（busy で確かめる）
-- - 飛んでいる間の状態には、飛ばした攻撃の反応（吹き飛びか打ち上げ）を持たせる。空中でののけぞりで浮かせ直したときは、
--   前の飛び方を引き継ぐ
-- - 反応の状態を入れ替えたら（のけぞる・飛ぶ・倒れる・起き上がる・終わる）、個体の onStateChanged を呼ぶ
--   （下忍の個体は、被弾の反応のモーションを流す。#88）

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Ground = require(ReplicatedStorage.Shared.Ground)
local Trajectory = require(ReplicatedStorage.Shared.Trajectory)

-- 反応の種類。Flinch はのけぞり、Air は吹き飛びか打ち上げで飛んでいる間、Down は着地して倒れている間、GetUp は起き上がり
export type Kind = "Flinch" | "Air" | "Down" | "GetUp"

-- 反応の状態
export type State = {
	kind: Kind,
	-- この状態を始めた時刻（os.clock）
	startedAt: number,
	-- この状態が終わる時刻（os.clock）。Air は着地するまで続くので math.huge
	untilTime: number,
	-- 飛んでいる間の軌道
	trajectory: Trajectory.Trajectory?,
	-- 吹き飛びか打ち上げを受けた時刻（os.clock）。面に沿って滑らせても変えない
	flightStartedAt: number?,
	-- 飛んでいる間の、飛ばした攻撃の反応（Knockback か Launch）。空中でののけぞりで浮かせ直したときは、前の飛び方を引き継ぐ
	reaction: Config.Reaction?,
}

-- 反応を受ける個体
export type Body = {
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	-- 立っているときの、地面から HumanoidRootPart の中心までの高さ
	standHeight: number,
	-- 倒れているときの、地面から HumanoidRootPart の中心までの高さ
	lieHeight: number,
	-- 吹き飛び・打ち上げ・浮かせ直しの初速に掛ける倍率
	scale: number,
	-- のけぞりの秒数に掛ける倍率。0 ならのけぞらない
	flinchScale: number,
	-- 反応の最中なら、その状態
	state: State?,
	-- 飛んでいる間と倒れている間に保つ向き（回転だけの CFrame）
	facing: CFrame,
	-- 最後に着地した地面の高さ
	groundY: number?,
	-- 奈落に落ちたときに呼ぶ。nil なら体力を 0 にしてモデルを消す
	onFell: (() -> ())?,
	-- 反応の状態を入れ替えたときに、新しい状態（反応が終わったら nil）と前の状態で呼ぶ。nil なら呼ばない
	onStateChanged: ((state: State?, previous: State?) -> ())?,
}

-- 攻撃を当てたときの反応の中身
export type Hit = {
	reaction: Config.Reaction,
	-- 攻撃元の位置。吹き飛ぶ向きを決める
	origin: Vector3,
	-- 技の吹き飛ばす強さ（Config.luau の HitDef の Knockback）
	force: number,
}

-- 個体を作るときの中身
export type Options = {
	-- 倒れているときの、地面から HumanoidRootPart の中心までの高さ。省くと LIE_HEIGHT
	lieHeight: number?,
	scale: number?,
	flinchScale: number?,
	onFell: (() -> ())?,
	onStateChanged: ((state: State?, previous: State?) -> ())?,
}

local Hanno = {}

-- 飛んでいる個体が床とみなす面の向き（面の法線の上向きの成分の下限）
local FLOOR_NORMAL_Y = 0.7
-- 壁や天井に当たったとき、当たった位置から面の外へ離す距離（スタッド）。細い隙間の向こうへ押し出さないよう小さくする
local SURFACE_GAP = 0.05
-- 面の外へ離すと別の面にぶつかるとき（鋭い角）に、当たった位置から来た向きへ戻す距離（スタッド）
local CONTACT_OFFSET = 0.1
-- 面に沿って滑る速さの上限（スタッド/秒）
local MAX_SLIDE_SPEED = 150
-- 吹き飛びか打ち上げを受けてから、着地しないまま飛んでいられる秒数。過ぎたらその場に倒れる
local MAX_FLIGHT_TIME = 5
-- 足の下の地面を探す光線を、立っているときの高さより少しだけ長くする（ちょうどの長さでは当たり損ねることがあるため）
local BELOW_MARGIN = 0.1
-- 倒れているときの、地面から HumanoidRootPart の中心までの高さの既定値
local LIE_HEIGHT = 1

-- 飛んでいるか、倒れているか、起き上がっている個体。フレームごとに動かす（倒された個体も着地するまで入る）
local reacting: { [Body]: boolean } = {}
-- 光線を当てないフォルダ（個体を置くフォルダ）
local excludedFolders: { Instance } = {}
local heartbeat: RBXScriptConnection? = nil

-- 光線を当てないフォルダを足す。個体を置くフォルダを渡す（個体どうしには当てない）
function Hanno.excludeFolder(folder: Instance)
	if not table.find(excludedFolders, folder) then
		table.insert(excludedFolders, folder)
	end
end

-- 個体の反応の入れ物を作る。立っているときの高さは今の Humanoid から求める
function Hanno.newBody(model: Model, humanoid: Humanoid, root: BasePart, options: Options?): Body
	local o = options or {}
	return {
		model = model,
		humanoid = humanoid,
		root = root,
		standHeight = humanoid.HipHeight + root.Size.Y / 2,
		lieHeight = o.lieHeight or LIE_HEIGHT,
		scale = o.scale or 1,
		flinchScale = o.flinchScale or 1,
		state = nil,
		facing = root.CFrame.Rotation,
		groundY = nil,
		onFell = o.onFell,
		onStateChanged = o.onStateChanged,
	}
end

-- 反応の状態を state に入れ替え、個体の onStateChanged に知らせる。知らせた先が失敗しても反応を進められるよう、
-- 別のスレッドで呼ぶ（すぐに呼ばれる）
local function setState(body: Body, state: State?)
	local previous = body.state
	body.state = state
	local onStateChanged = body.onStateChanged
	if onStateChanged then
		task.spawn(onStateChanged, state, previous)
	end
end

-- 歩くのをやめさせる
function Hanno.stopWalking(body: Body)
	body.humanoid:MoveTo(body.root.Position)
	body.humanoid:Move(Vector3.zero)
end

-- HumanoidRootPart を固定し、軌道と倒れた姿勢をスクリプトで決められるようにする
local function anchor(body: Body)
	Hanno.stopWalking(body)
	body.root.Anchored = true
end

-- 固定を外し、物理をサーバーに持たせ直す
local function release(body: Body)
	body.root.Anchored = false
	pcall(function()
		body.root:SetNetworkOwner(nil)
	end)
end

-- 攻撃元 origin の方を向く向き（回転だけ）。向きが決まらなければ今の向き
local function facingToward(body: Body, origin: Vector3): CFrame
	local position = body.root.Position
	local back = Vector3.new(origin.X - position.X, 0, origin.Z - position.Z)
	if back.Magnitude < 0.01 then
		return body.root.CFrame.Rotation
	end
	return CFrame.lookAt(Vector3.zero, back.Unit)
end

-- 地面の高さ groundY の (x, z) に仰向けに寝かせる
local function lieDown(body: Body, x: number, groundY: number, z: number)
	body.groundY = groundY
	body.root.CFrame = CFrame.new(x, groundY + body.lieHeight, z) * body.facing * CFrame.Angles(math.rad(90), 0, 0)
end

-- 倒された個体を倒れたまま残し、消えるのを待つ
local function stayDown(body: Body, now: number)
	setState(body, { kind = "Down", startedAt = now, untilTime = math.huge, trajectory = nil })
	reacting[body] = nil
end

-- 着地して仰向けに倒れる
local function land(body: Body, x: number, groundY: number, z: number, now: number)
	lieDown(body, x, groundY, z)
	if body.humanoid.Health <= 0 then
		stayDown(body, now)
		return
	end
	setState(body, { kind = "Down", startedAt = now, untilTime = now + Config.EnemyReaction.Down, trajectory = nil })
end

-- 足の下（HumanoidRootPart の中心から立っているときの高さまで）に床（上を向いた面）があれば着地させ、true を返す。
-- 壁のような急な面には着地しない
local function landIfGrounded(body: Body, position: vector, now: number, excluded: { Instance }): boolean
	local below = Ground.raycast(position, vector.create(0, -(body.standHeight + BELOW_MARGIN), 0), excluded, true)
	if not below or below.Normal.Y < FLOOR_NORMAL_Y then
		return false
	end
	land(body, position.x, below.Position.Y, position.z, now)
	return true
end

-- 飛んでいる途中で壁か天井に当たったら、面から少し離し、面へ向かう速さを消して面に沿って滑らせ直す。
-- 面の外へ離すと別の面にぶつかるとき（鋭い角）は、代わりに来た向きへ少し戻す。heading は動いてきた向きの単位ベクトル
local function slide(
	body: Body,
	state: State,
	hit: RaycastResult,
	heading: Vector3,
	velocity: vector,
	now: number,
	excluded: { Instance }
)
	local normal = hit.Normal
	local before = hit.Position - heading * 0.01
	local position = hit.Position + normal * SURFACE_GAP
	if Ground.raycast(before, position - before, excluded, true) then
		position = hit.Position - heading * CONTACT_OFFSET
	end
	local into = velocity:Dot(normal)
	local along = if into < 0 then velocity - normal * into else velocity
	if along.Magnitude > MAX_SLIDE_SPEED then
		along = along.Unit * MAX_SLIDE_SPEED
	end
	state.trajectory = Trajectory.new(position, along)
	state.startedAt = now
	body.root.CFrame = CFrame.new(position) * body.facing
end

-- 奈落に落ちた個体を片付ける
local function fell(body: Body)
	reacting[body] = nil
	local onFell = body.onFell
	if onFell then
		onFell()
		return
	end
	body.humanoid.Health = 0
	body.model:Destroy()
end

-- 飛んでいる個体を軌道の位置へ置く。途中で物に当たったら止め、落ちている途中で足が地面に届いたら着地させる
local function updateFlight(body: Body, state: State, now: number, excluded: { Instance })
	local from = body.root.Position
	if now - (state.flightStartedAt or state.startedAt) > MAX_FLIGHT_TIME then
		-- 床の無い急な面の間などで着地できないまま時間が過ぎたら、その場（今の高さのまま）に倒れる
		land(body, from.X, from.Y - body.lieHeight, from.Z, now)
		return
	end
	local trajectory = state.trajectory :: Trajectory.Trajectory
	local elapsed = now - state.startedAt
	local position = Trajectory.positionAt(trajectory, elapsed)
	local velocity = Trajectory.velocityAt(trajectory, elapsed)
	local step = position - from
	if step.Magnitude > 1e-3 then
		local hit = Ground.raycast(from, step, excluded, true)
		if hit then
			if hit.Normal.Y >= FLOOR_NORMAL_Y then
				land(body, hit.Position.X, hit.Position.Y, hit.Position.Z, now)
				return
			end
			slide(body, state, hit, step.Unit, velocity, now, excluded)
			-- 滑らせた先の足の下に地面があれば、そこで着地する（斜めの天井と床の間で床を抜けない）
			landIfGrounded(body, body.root.Position, now, excluded)
			return
		end
	end
	if velocity.y <= 0 then
		if landIfGrounded(body, position, now, excluded) then
			return
		end
		if position.y < workspace.FallenPartsDestroyHeight then
			fell(body)
			return
		end
	end
	body.root.CFrame = CFrame.new(position) * body.facing
end

-- 飛んでいる・倒れている・起き上がっている個体を進める
local function update(body: Body, now: number, excluded: { Instance })
	local state = body.state
	if not state then
		reacting[body] = nil
		return
	end
	if state.kind ~= "Air" and body.humanoid.Health <= 0 then
		-- 倒れている間か起き上がる途中で倒された個体は、寝かせ直して倒れたまま残す
		if state.kind == "GetUp" then
			local position = body.root.Position
			lieDown(body, position.X, body.groundY or (position.Y - body.standHeight), position.Z)
		end
		stayDown(body, now)
		return
	end
	if state.kind == "Air" then
		updateFlight(body, state, now, excluded)
	elseif state.kind == "Down" and now >= state.untilTime then
		-- 起き上がる
		local position = body.root.Position
		local groundY = body.groundY or position.Y
		body.root.CFrame = CFrame.new(position.X, groundY + body.standHeight, position.Z) * body.facing
		setState(
			body,
			{ kind = "GetUp", startedAt = now, untilTime = now + Config.EnemyReaction.GetUp, trajectory = nil }
		)
	elseif state.kind == "GetUp" and now >= state.untilTime then
		setState(body, nil)
		reacting[body] = nil
		release(body)
	end
end

local function onHeartbeat()
	if next(reacting) == nil then
		return
	end
	local now = os.clock()
	-- 光線を当てない部品の一覧はフレームごとに1回だけ作る。個体どうしには当てない
	local excluded = Ground.excludedOf(excludedFolders)
	for body in reacting do
		if not body.model.Parent then
			reacting[body] = nil
			continue
		end
		local ok, err = pcall(update, body, now, excluded)
		if not ok then
			reacting[body] = nil
			setState(body, nil)
			release(body)
			warn(`Hanno: {body.model.Name} の反応を進められなかった: {err}`)
		end
	end
end

-- position から初速 velocity で飛ばす。reaction は飛ばした攻撃の反応（吹き飛びか打ち上げ）
local function startFlight(
	body: Body,
	velocity: vector,
	position: Vector3,
	attackOrigin: Vector3,
	now: number,
	reaction: Config.Reaction
)
	body.facing = facingToward(body, attackOrigin)
	anchor(body)
	body.root.CFrame = CFrame.new(position) * body.facing
	setState(body, {
		kind = "Air",
		startedAt = now,
		untilTime = math.huge,
		trajectory = Trajectory.new(position, velocity),
		flightStartedAt = now,
		reaction = reaction,
	})
	reacting[body] = true
	if not heartbeat then
		heartbeat = RunService.Heartbeat:Connect(onHeartbeat)
	end
end

-- 攻撃を受けた反応を始める。noFlinch なら、のけぞりの反応だけ起こさない（吹き飛びと打ち上げは受ける）
function Hanno.react(body: Body, hit: Hit, now: number, noFlinch: boolean?)
	local state = body.state
	local airborne = state ~= nil and state.kind == "Air"
	local params = Config.EnemyReaction
	local position = body.root.Position
	local velocity = Trajectory.initialVelocity(hit.reaction, position - hit.origin, hit.force, airborne, body.scale)
	if velocity then
		-- 倒れているところから飛ばすときは、立っているときの高さから飛ばす
		local lying = state ~= nil and (state.kind == "Down" or state.kind == "GetUp")
		local from = if lying
			then Vector3.new(position.X, (body.groundY or position.Y) + body.standHeight, position.Z)
			else position
		-- 空中でののけぞりで浮かせ直すときは、前の飛び方（吹き飛びか打ち上げ）を引き継ぐ
		local reaction = hit.reaction
		if airborne and reaction == "Flinch" and state and state.reaction then
			reaction = state.reaction
		end
		startFlight(body, velocity, from, hit.origin, now, reaction)
		return
	end
	if hit.reaction ~= "Flinch" or noFlinch or body.humanoid.Health <= 0 then
		return
	end
	if state ~= nil and state.kind ~= "Flinch" then
		return
	end
	local seconds = params.Flinch * body.flinchScale
	if seconds > 0 then
		Hanno.stopWalking(body)
		setState(body, { kind = "Flinch", startedAt = now, untilTime = now + seconds, trajectory = nil })
	end
end

-- 反応の最中か（近づくことも攻撃することもしない）。のけぞりが明けていたら外して false を返す
function Hanno.busy(body: Body, now: number): boolean
	local state = body.state
	if not state then
		return false
	end
	if state.kind ~= "Flinch" or now < state.untilTime then
		return true
	end
	setState(body, nil)
	return false
end

-- 反応の種類。反応の最中でなければ nil
function Hanno.kindOf(body: Body): Kind?
	local state = body.state
	return if state then state.kind else nil
end

-- フレームごとに動かす対象から外す（個体を消すとき）
function Hanno.forget(body: Body)
	reacting[body] = nil
end

return Hanno
