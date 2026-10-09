--!strict
-- 実体化圏の下忍の個体の数の計画。敵軍の部隊ごとに、個体として出しておく下忍の数（目標）を決める。
-- 出す・消すの判定は Jittaikaken、上限のまとまりごとの配分は KotaiHaibun、数値は Config.luau の
-- GeninKotai・Jittaikaken・KotaiHaibun 節にある。Roblox の API は使わない。位置は水平の (x, z)。
--
-- 兵数と個体の数え方
-- - 兵数は部隊の下忍の全体の数のまま持つ。個体は、そのうちの何人かを姿として出したもの（借り出し）
-- - 個体の数は兵数を超えない。消えた個体は部隊に戻る（兵数は変わらない。返却）
-- - 個体が倒れたら兵数を1減らす（呼ぶ側。ButaiService.changeHeisu）
--
-- 目標の決め方
-- - 部隊が出撃メンバーの誰かから AppearRadius 以内に入ったら出す対象にし、全員から DisappearRadius より離れるまで
--   対象に残す（今の個体が1体以上いれば出ているとみなす。縁を行き来しても出入りを繰り返さない）
-- - 出す対象の部隊を一番近いメンバーのまとまりに数え、上限（MaxKotai）をまとまりごとに人数の比で分ける。
--   まとまりの配分は、その部隊の兵数の合計を超えない（余った分はほかのまとまりへ回す）
-- - まとまりの配分を、まとまりの中の部隊へ兵数の比で分ける。部隊の目標は兵数を超えない
-- - 目標の合計は上限を超えない。出す対象でない部隊の目標は 0

local Config = require("./Config")
local Jittaikaken = require("./Jittaikaken")
local KotaiHaibun = require("./KotaiHaibun")

export type Params = {
	jittaikaken: Config.JittaikakenSection?,
	haibun: Config.KotaiHaibunSection?,
}

-- 部隊の今の様子。present は今出している個体の数
export type ButaiState = { id: string, x: number, z: number, heisu: number, present: number }

export type Plan = {
	-- 部隊 ID ごとの、個体として出しておく数
	targets: { [string]: number },
	-- 部隊 ID ごとの、一番近いメンバーまでの水平の距離（メンバーがいなければ入らない）
	distances: { [string]: number },
	-- 出す対象の部隊で分けたまとまりの配分（窓口の確認用）
	groups: { KotaiHaibun.Group },
}

local GeninKotai = {}

-- 部隊ごとの、個体として出しておく数を決める。cap はサーバー全体の上限
function GeninKotai.plan(butai: { ButaiState }, members: { KotaiHaibun.Member }, cap: number, params: Params?): Plan
	local jittaikaken = if params and params.jittaikaken then params.jittaikaken else Config.Jittaikaken
	local haibun = if params and params.haibun then params.haibun else Config.KotaiHaibun
	local points = {}
	for _, member in members do
		table.insert(points, { x = member.x, z = member.z })
	end

	local targets: { [string]: number } = {}
	local distances: { [string]: number } = {}
	local eligible: { KotaiHaibun.ButaiInput } = {}
	local heisuOf: { [string]: number } = {}
	for _, entry in butai do
		targets[entry.id] = 0
		local distance = Jittaikaken.nearestDistance({ x = entry.x, z = entry.z }, points)
		if distance then
			distances[entry.id] = distance
		end
		local heisu = math.max(math.floor(entry.heisu), 0)
		heisuOf[entry.id] = heisu
		if heisu > 0 and Jittaikaken.shouldAppear(entry.present > 0, distance, jittaikaken) then
			table.insert(eligible, { id = entry.id, x = entry.x, z = entry.z, heisu = heisu })
		end
	end

	-- 出す対象の部隊は、一番近いメンバーのまとまりに数える。対象の部隊は誰かから消滅の半径の内にいるので、
	-- 数える距離にその半径を渡す
	local groups = KotaiHaibun.allocate(
		members,
		cap,
		eligible,
		{ GroupDistance = haibun.GroupDistance, Reach = jittaikaken.DisappearRadius }
	)
	for _, group in groups do
		local weights = {}
		for _, id in group.butai do
			table.insert(weights, heisuOf[id])
		end
		local shares = KotaiHaibun.split(weights, weights, group.quota)
		for index, id in group.butai do
			targets[id] = shares[index]
		end
	end
	return { targets = targets, distances = distances, groups = groups }
end

return GeninKotai
