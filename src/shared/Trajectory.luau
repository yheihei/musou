--!strict
-- 吹き飛びと打ち上げの軌道。物理演算に任せず、初速と重力と経過時間から位置を決める。
-- 下忍にも上忍・首領にも同じ関数を使い、上忍・首領は反応を弱める倍率で短く飛ばす。
-- 初速の決め方と重力は Config.luau の EnemyReaction 節にある。位置は vector で受け取り、Roblox の API は使わない。
--
-- - 吹き飛びは、攻撃元から離れる向きへ技の吹き飛ばす強さ（Knockback）で飛ばし、少し浮かせる
-- - 打ち上げは、真上へ技の Knockback で浮かせ、横へは少しだけ流す
-- - 空中で攻撃を受けたら、その位置から軌道をやり直す（追撃で再び浮く）。空中でののけぞりは AirLift で浮かせ直す
-- - 地上でののけぞりと、反応の無い攻撃は軌道を作らない
-- - 着地は、落ちている途中で地面の高さ以下になったとき。地面の高さは呼ぶ側が地点ごとに渡す（傾斜と段差に合わせる）

local Config = require("./Config")

export type Params = Config.EnemyReactionSection

export type Trajectory = {
	-- 飛び始めた位置
	origin: vector,
	-- 初速（スタッド/秒）
	velocity: vector,
	-- 下向きの加速度（スタッド/秒²）
	gravity: number,
}

local Trajectory = {}

local ZERO = vector.create(0, 0, 0)

-- 向きの水平成分の単位ベクトル。長さが無ければ 0
local function flatUnit(direction: vector): vector
	local flat = vector.create(direction.x, 0, direction.z)
	if vector.magnitude(flat) < 1e-6 then
		return ZERO
	end
	return vector.normalize(flat)
end

-- 反応と吹き飛ばす強さから初速を決める。軌道を作らない反応なら nil。
-- direction は攻撃元から受ける側への向き（水平成分だけを使う）、force は技の Knockback、
-- airborne は受ける側が空中にいるか、scale は反応を弱める倍率（上忍と首領は JoninScale）
function Trajectory.initialVelocity(
	reaction: Config.Reaction,
	direction: vector,
	force: number,
	airborne: boolean,
	scale: number?,
	params: Params?
): vector?
	local p = params or Config.EnemyReaction
	local s = scale or 1
	local away = flatUnit(direction)
	if reaction == "Knockback" and force > 0 then
		return away * (force * s) + vector.create(0, force * p.KnockbackLift * s, 0)
	elseif reaction == "Launch" and force > 0 then
		return away * (force * p.LaunchDrift * s) + vector.create(0, force * p.LaunchLift * s, 0)
	elseif reaction == "Flinch" and airborne then
		return away * (p.AirDrift * s) + vector.create(0, p.AirLift * s, 0)
	end
	return nil
end

-- 位置 origin から初速 velocity で飛び始める軌道
function Trajectory.new(origin: vector, velocity: vector, params: Params?): Trajectory
	local p = params or Config.EnemyReaction
	return { origin = origin, velocity = velocity, gravity = p.Gravity }
end

-- 飛び始めてから elapsed 秒後の位置
function Trajectory.positionAt(trajectory: Trajectory, elapsed: number): vector
	local t = math.max(elapsed, 0)
	local drop = 0.5 * trajectory.gravity * t * t
	return trajectory.origin + trajectory.velocity * t - vector.create(0, drop, 0)
end

-- 飛び始めてから elapsed 秒後の速さ
function Trajectory.velocityAt(trajectory: Trajectory, elapsed: number): vector
	local t = math.max(elapsed, 0)
	return trajectory.velocity - vector.create(0, trajectory.gravity * t, 0)
end

-- 落ちている途中で高さが groundY 以下になったか（着地したか）。上っている間は地面より下でも着地しない
function Trajectory.hasLanded(trajectory: Trajectory, elapsed: number, groundY: number): boolean
	if Trajectory.velocityAt(trajectory, elapsed).y > 0 then
		return false
	end
	return Trajectory.positionAt(trajectory, elapsed).y <= groundY
end

-- 高さ groundY の平らな地面に着地するまでの秒数。重力が無いなど、着地しなければ nil
function Trajectory.landingTime(trajectory: Trajectory, groundY: number): number?
	local g = trajectory.gravity
	local vy = trajectory.velocity.y
	local height = trajectory.origin.y - groundY
	if g <= 0 then
		return nil
	end
	-- height + vy t - g t² / 2 = 0 の大きい方の解
	local discriminant = vy * vy + 2 * g * height
	if discriminant < 0 then
		return nil
	end
	local t = (vy + math.sqrt(discriminant)) / g
	return if t >= 0 then t else nil
end

return Trajectory
