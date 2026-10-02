--!strict
-- 下忍の描き方の試作（検証用ブランチだけ）。案B のサーバーが持つ下忍のデータと、その動きの計算。
-- サーバーは位置と状態だけを持ち、クライアントがモデルを描く。案A（サーバーの Humanoid）と同じ動き
-- （近づく・攻撃する・吹き飛ぶ・倒れる・湧き直す）をデータだけで再現する。
-- 値は Config.luau の GeninProto 節にある。乱数は引数で受け取る。Roblox の API は使わない。

local Config = require("../Config")

export type Params = Config.GeninProtoSection

export type State = "Move" | "Attack" | "Knockback" | "Down" | "Hidden"

-- クライアントへ送る状態の番号
local STATE_CODES: { [State]: number } = { Move = 0, Attack = 1, Knockback = 2, Down = 3, Hidden = 4 }
local STATES: { State } = { "Move", "Attack", "Knockback", "Down", "Hidden" }

export type Point = { x: number, z: number }

export type Genin = {
	x: number,
	z: number,
	-- 地面からの高さ（吹き飛びの放物線）
	y: number,
	-- 向き（ラジアン。0 で -Z、正で左回り）
	yaw: number,
	state: State,
	-- 今の状態に入ってからの秒数
	stateTime: number,
	-- 薙ぎ払いに当たった回数
	hits: number,
	-- 最後に攻撃を始めた時刻
	lastAttack: number,
	-- 吹き飛びの始点と向き（単位ベクトル）
	fromX: number,
	fromZ: number,
	dirX: number,
	dirZ: number,
}

local GeninSim = {}

GeninSim.states = STATES

function GeninSim.codeOf(state: State): number
	return STATE_CODES[state]
end

function GeninSim.stateOf(code: number): State
	return STATES[code + 1] or "Hidden"
end

local function paramsOf(params: Params?): Params
	return params or Config.GeninProto
end

-- 2点の向き（0 で -Z）。同じ点なら 0
function GeninSim.yawTo(fromX: number, fromZ: number, toX: number, toZ: number): number
	local dx, dz = toX - fromX, toZ - fromZ
	if dx == 0 and dz == 0 then
		return 0
	end
	return math.atan2(-dx, -dz)
end

-- center の周りの、SpawnRadiusMin から SpawnRadiusMax の輪の上の位置に置き直し、Move から始める
function GeninSim.respawn(genin: Genin, center: Point, rand: () -> number, params: Params?)
	local p = paramsOf(params)
	local angle = rand() * math.pi * 2
	local radius = p.SpawnRadiusMin + rand() * (p.SpawnRadiusMax - p.SpawnRadiusMin)
	genin.x = center.x + math.cos(angle) * radius
	genin.z = center.z + math.sin(angle) * radius
	genin.y = 0
	genin.yaw = GeninSim.yawTo(genin.x, genin.z, center.x, center.z)
	genin.state = "Move"
	genin.stateTime = 0
	genin.hits = 0
	genin.lastAttack = -math.huge
end

-- count 体の下忍を center の周りに作る
function GeninSim.create(count: number, center: Point, rand: () -> number, params: Params?): { Genin }
	local list = {}
	for _ = 1, count do
		local genin: Genin = {
			x = 0,
			z = 0,
			y = 0,
			yaw = 0,
			state = "Move",
			stateTime = 0,
			hits = 0,
			lastAttack = -math.huge,
			fromX = 0,
			fromZ = 0,
			dirX = 0,
			dirZ = 0,
		}
		GeninSim.respawn(genin, center, rand, params)
		table.insert(list, genin)
	end
	return list
end

local function setState(genin: Genin, state: State)
	genin.state = state
	genin.stateTime = 0
end

-- 一番近い目標。目標が無ければ nil
local function nearest(genin: Genin, targets: { Point }): (Point?, number)
	local best: Point? = nil
	local bestDistance = math.huge
	for _, target in targets do
		local dx, dz = target.x - genin.x, target.z - genin.z
		local distance = math.sqrt(dx * dx + dz * dz)
		if distance < bestDistance then
			best, bestDistance = target, distance
		end
	end
	return best, bestDistance
end

-- 1体を dt 秒進める。targets は追う目標（プレイヤーの位置）、now は今の時刻（秒）
function GeninSim.stepOne(
	genin: Genin,
	targets: { Point },
	dt: number,
	now: number,
	rand: () -> number,
	params: Params?
)
	local p = paramsOf(params)
	genin.stateTime += dt
	if genin.state == "Hidden" then
		if genin.stateTime >= p.RespawnDelay then
			local target = nearest(genin, targets)
			if target then
				GeninSim.respawn(genin, target, rand, p)
			end
		end
		return
	elseif genin.state == "Down" then
		if genin.stateTime >= p.DownTime then
			setState(genin, "Hidden")
		end
		return
	elseif genin.state == "Knockback" then
		local t = math.min(genin.stateTime / p.KnockbackTime, 1)
		genin.x = genin.fromX + genin.dirX * p.KnockbackDistance * t
		genin.z = genin.fromZ + genin.dirZ * p.KnockbackDistance * t
		genin.y = 4 * p.KnockbackHeight * t * (1 - t)
		if t >= 1 then
			genin.y = 0
			setState(genin, if genin.hits >= p.MaxHits then "Down" else "Move")
		end
		return
	elseif genin.state == "Attack" then
		if genin.stateTime >= p.AttackTime then
			setState(genin, "Move")
		end
		return
	end

	local target, distance = nearest(genin, targets)
	if not target then
		return
	end
	genin.yaw = GeninSim.yawTo(genin.x, genin.z, target.x, target.z)
	if distance > p.AttackRange then
		local stepDistance = math.min(p.WalkSpeed * dt, distance - p.AttackRange)
		genin.x += (target.x - genin.x) / distance * stepDistance
		genin.z += (target.z - genin.z) / distance * stepDistance
	elseif now - genin.lastAttack >= p.AttackCooldown then
		genin.lastAttack = now
		setState(genin, "Attack")
	end
end

-- 全員を dt 秒進める
function GeninSim.step(
	list: { Genin },
	targets: { Point },
	dt: number,
	now: number,
	rand: () -> number,
	params: Params?
)
	for _, genin in list do
		GeninSim.stepOne(genin, targets, dt, now, rand, params)
	end
end

-- center からの薙ぎ払い。SweepRadius 以内の、近づくか攻撃している下忍を外へ吹き飛ばし、当たった回数を増やす。
-- 当てた数を返す。MaxHits 回当たった下忍は、吹き飛んだ後に倒れる
function GeninSim.sweep(list: { Genin }, center: Point, params: Params?): number
	local p = paramsOf(params)
	local count = 0
	for _, genin in list do
		if genin.state == "Move" or genin.state == "Attack" then
			local dx, dz = genin.x - center.x, genin.z - center.z
			local distance = math.sqrt(dx * dx + dz * dz)
			if distance <= p.SweepRadius then
				count += 1
				genin.hits += 1
				if distance > 1e-3 then
					genin.dirX, genin.dirZ = dx / distance, dz / distance
				else
					genin.dirX, genin.dirZ = 0, 1
				end
				genin.fromX, genin.fromZ = genin.x, genin.z
				genin.yaw = GeninSim.yawTo(genin.x, genin.z, center.x, center.z)
				setState(genin, "Knockback")
			end
		end
	end
	return count
end

return GeninSim
