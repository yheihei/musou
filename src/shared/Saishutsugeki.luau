--!strict
-- 再出撃の計算。倒れたプレイヤーは、兵站線につながった自分の軍の拠点のうち、倒れた位置に一番近い拠点から再出撃する。
-- 再出撃のたびにパーティーで共有する兵力を1使う。兵力の初期値と並べる間隔は Config.luau の Stage 節にある。
-- Roblox の API は使わない。
--
-- - 再出撃する拠点の候補は、自分の軍の拠点のうち兵站線につながったものだけ（孤立した拠点と相手の軍の拠点は選ばない）
-- - 距離は拠点の中心までの水平の距離。同じ距離なら一覧の先の拠点
-- - 拠点の中では、出撃した順に東西へ間隔をあけて並べる（パーティーの上限人数で一回りする）
-- - 兵力が0のときは再出撃しない

local Config = require("./Config")
local Gun = require("./Gun")

-- 再出撃する拠点の候補
export type KyotenInput = {
	id: string,
	gun: Gun.Gun,
	-- 兵站線につながっているか
	connected: boolean,
	-- 中心の水平の位置
	x: number,
	z: number,
}

local Saishutsugeki = {}

-- 兵力を置く workspace の Attribute。出撃していないときは無い
Saishutsugeki.HEIRYOKU_ATTRIBUTE = "Heiryoku"

-- gun の軍のプレイヤーが (x, z) で倒れたときに再出撃する拠点の ID。候補が無ければ nil
function Saishutsugeki.chooseKyoten(kyotenList: { KyotenInput }, gun: Gun.Gun, x: number, z: number): string?
	local best: string? = nil
	local bestDistance = math.huge
	for _, kyoten in kyotenList do
		if kyoten.gun ~= gun or not kyoten.connected then
			continue
		end
		local dx, dz = kyoten.x - x, kyoten.z - z
		local distance = math.sqrt(dx * dx + dz * dz)
		if distance < bestDistance then
			best = kyoten.id
			bestDistance = distance
		end
	end
	return best
end

-- 出撃した順（1から）のメンバーを拠点の中心から東西へずらす量（スタッド）。東が +
function Saishutsugeki.offsetOf(index: number, spacing: number?, count: number?): number
	local slots = math.max(count or Config.Party.MaxMembers, 1)
	local slot = (math.max(math.floor(index), 1) - 1) % slots
	return (slot - (slots - 1) / 2) * (spacing or Config.Stage.SaishutsugekiSpacing)
end

-- 兵力を1使う。使えたら true と残りの兵力、0 以下なら false とそのままの兵力を返す
function Saishutsugeki.consume(heiryoku: number): (boolean, number)
	if heiryoku <= 0 then
		return false, heiryoku
	end
	return true, heiryoku - 1
end

return Saishutsugeki
