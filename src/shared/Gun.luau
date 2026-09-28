--!strict
-- 軍の識別子。1つのステージには味方軍と敵軍の2つがある。

export type Gun = "Mikatagun" | "Tekigun"

local Gun = {}

Gun.list = { "Mikatagun", "Tekigun" } :: { Gun }

-- 相手の軍
function Gun.opponentOf(gun: Gun): Gun
	return if gun == "Mikatagun" then "Tekigun" else "Mikatagun"
end

function Gun.isGun(value: unknown): boolean
	return value == "Mikatagun" or value == "Tekigun"
end

return Gun
