--!strict
-- クライアント → サーバーの Remotes.Action で送る行動の種類と引数の検証。
-- クライアントは入力を送るだけで、行動を出せるかはサーバーが決める。
--
-- | 行動 | 引数 |
-- |---|---|
-- | Attack・ChargeKogeki・Ougi | なし |
-- | Guard | 押したら true、離したら false |
-- | KinkyuKaihi | 水平の方向（vector、長さ0は不可、上下の成分は読まない） |
-- | Hikei | 秘計の枚の番号（正の整数。持ち込みの範囲かは秘計の処理で判定する） |

export type Action = "Attack" | "ChargeKogeki" | "Guard" | "KinkyuKaihi" | "Ougi" | "Hikei"

local Actions = {
	Attack = "Attack" :: Action,
	ChargeKogeki = "ChargeKogeki" :: Action,
	Guard = "Guard" :: Action,
	KinkyuKaihi = "KinkyuKaihi" :: Action,
	Ougi = "Ougi" :: Action,
	Hikei = "Hikei" :: Action,
}

-- 方向の水平の長さがこれ未満なら、長さ0とみなす
local MIN_DIRECTION = 1e-3

local function isFinite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

function Actions.isValid(value: unknown): boolean
	return value == Actions.Attack
		or value == Actions.ChargeKogeki
		or value == Actions.Guard
		or value == Actions.KinkyuKaihi
		or value == Actions.Ougi
		or value == Actions.Hikei
end

-- 緊急回避の方向として受け付けるか。有限の値で、水平の長さが0でない vector
function Actions.isDirection(value: unknown): boolean
	if type(value) ~= "vector" then
		return false
	end
	local direction = value :: vector
	if not (isFinite(direction.x) and isFinite(direction.y) and isFinite(direction.z)) then
		return false
	end
	return math.sqrt(direction.x * direction.x + direction.z * direction.z) >= MIN_DIRECTION
end

-- 秘計の枚の番号として受け付けるか。正の整数
function Actions.isSlot(value: unknown): boolean
	return type(value) == "number" and isFinite(value) and value >= 1 and value == math.floor(value)
end

-- 行動と引数の組を受け付けるか。引数の無い行動は、余分な引数が来ても受け付ける（読まないだけ）
function Actions.validate(action: unknown, argument: unknown): boolean
	if action == Actions.Attack or action == Actions.ChargeKogeki or action == Actions.Ougi then
		return true
	elseif action == Actions.Guard then
		return type(argument) == "boolean"
	elseif action == Actions.KinkyuKaihi then
		return Actions.isDirection(argument)
	elseif action == Actions.Hikei then
		return Actions.isSlot(argument)
	end
	return false
end

-- 方向の上下の成分を捨てて長さ1にする。isDirection で確かめた値に使う
function Actions.horizontal(direction: vector): vector
	return vector.normalize(vector.create(direction.x, 0, direction.z))
end

return Actions
