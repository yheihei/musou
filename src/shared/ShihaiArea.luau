--!strict
-- 支配エリアの判定。兵站線でつながった拠点の周り（拠点の中心から Config.luau の ShihaiArea 節の Radius 以内）を、
-- その拠点の軍の支配エリアとする。支配エリアの中では、その軍の部隊の交戦の押す力と、上忍と首領の攻撃と防御が上がる。
-- 半径と倍率は Config.luau の ShihaiArea 節にある。Roblox の API は使わない。
--
-- - 孤立した拠点は支配エリアを持たない。兵糧庫は孤立しないので、兵站線が切れても支配エリアを保つ
-- - 2つ以上の拠点の支配エリアが重なる地点は、中心が一番近い拠点の軍のものにする。距離が同じなら一覧の先の拠点
-- - どの拠点の支配エリアにも入らない地点は、どちらの軍のものでもない
-- - 部隊は自分の軍の支配エリアの中で、交戦の押す力に Push を掛ける（Kosen.luau の支配エリアの倍率）
-- - 上忍と首領は自分の軍の支配エリアの中で、攻撃と防御に Attack・Defense を掛ける（Stats.luau の補正）

local Config = require("./Config")
local Gun = require("./Gun")
local Stats = require("./Stats")

export type Params = Config.ShihaiAreaSection

export type Kyoten = {
	id: string,
	-- 所属の軍。どちらにも属さない拠点は nil
	gun: Gun.Gun?,
	-- 中心の水平の位置
	x: number,
	z: number,
	-- 兵站線につながっているか（孤立した拠点は false。兵糧庫は孤立しないので true）
	connected: boolean,
}

local ShihaiArea = {}

-- 支配エリアを持つ拠点（どちらかの軍の、兵站線につながった拠点）を一覧の順に返す
function ShihaiArea.sourcesOf(kyotenList: { Kyoten }): { Kyoten }
	local result = {}
	for _, kyoten in kyotenList do
		if kyoten.gun ~= nil and kyoten.connected then
			table.insert(result, kyoten)
		end
	end
	return result
end

-- 地点 (x, z) を支配エリアに持つ拠点。重なる地点は中心が一番近い拠点。どの拠点の支配エリアにも入らなければ nil
function ShihaiArea.kyotenAt(kyotenList: { Kyoten }, x: number, z: number, params: Params?): Kyoten?
	local p = params or Config.ShihaiArea
	local best: Kyoten? = nil
	local bestDistance = math.huge
	for _, kyoten in ShihaiArea.sourcesOf(kyotenList) do
		local dx, dz = kyoten.x - x, kyoten.z - z
		local distance = math.sqrt(dx * dx + dz * dz)
		if distance <= p.Radius and distance < bestDistance then
			best = kyoten
			bestDistance = distance
		end
	end
	return best
end

-- 地点 (x, z) がどの軍の支配エリアか。どちらのものでもなければ nil
function ShihaiArea.gunAt(kyotenList: { Kyoten }, x: number, z: number, params: Params?): Gun.Gun?
	local kyoten = ShihaiArea.kyotenAt(kyotenList, x, z, params)
	return if kyoten then kyoten.gun else nil
end

-- 軍 gun の部隊の交戦の押す力に掛ける倍率。areaGun はその部隊のいる地点の支配エリアの軍。
-- 自分の軍の支配エリアの中なら Push、外なら 1
function ShihaiArea.pushOf(areaGun: Gun.Gun?, gun: Gun.Gun, params: Params?): number
	local p = params or Config.ShihaiArea
	return if areaGun == gun then p.Push else 1
end

-- 上忍と首領の能力値の補正。inside は自分の軍の支配エリアの中か。中なら攻撃と防御を上げる補正、外なら空
function ShihaiArea.modifiersOf(inside: boolean, params: Params?): { Stats.Modifier }
	if not inside then
		return {}
	end
	local p = params or Config.ShihaiArea
	return {
		{ stat = "Attack", multiply = p.Attack },
		{ stat = "Defense", multiply = p.Defense },
	}
end

return ShihaiArea
