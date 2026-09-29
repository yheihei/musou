--!strict
-- ガードの正面の判定。受ける側の位置と向き、攻撃元の位置から、攻撃が正面から来たかを求める。
-- 正面の角度は Config.luau の Guard 節にある。位置は vector で受け取り、Roblox の API は使わない。
--
-- - 向きと攻撃元の方向は水平成分だけを使う
-- - 攻撃元が受ける側に重なっているときは正面とみなす

local Guard = {}

local EPSILON = 1e-6

local function flat(value: vector): vector
	return vector.create(value.x, 0, value.z)
end

-- 攻撃元 origin が、position に立って facing を向いている受ける側の正面 angle 度の内にあるか
function Guard.isFront(position: vector, facing: vector, origin: vector, angle: number): boolean
	local toOrigin = flat(origin - position)
	if vector.magnitude(toOrigin) < EPSILON then
		return true
	end
	local forward = flat(facing)
	if vector.magnitude(forward) < EPSILON then
		forward = vector.create(0, 0, -1)
	end
	local cosine = vector.dot(vector.normalize(toOrigin), vector.normalize(forward))
	-- 境界ちょうどを正面に含めるため、丸めの誤差の分だけ広げる
	return cosine >= math.cos(math.rad(angle / 2)) - 1e-9
end

return Guard
