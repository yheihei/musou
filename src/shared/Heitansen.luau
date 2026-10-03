--!strict
-- 兵站線のつながり判定。本陣から同じ軍の拠点をつながりに沿ってたどり、
-- たどり着いた拠点を兵站線につながった拠点、たどり着けない拠点を孤立した拠点とする。
-- Roblox の API は使わない。
--
-- - 相手の軍の拠点と、その軍が通れないつながり（落石で塞いだ区間）の先へは進まない
-- - 孤立しない拠点（兵糧庫）は、たどり着けなくても孤立に数えず、つながった拠点に数える。
--   ただし、そこから先の拠点へは兵站線を延ばさない
-- - どちらの軍にも属さない拠点は、どちらの軍の結果にも入れない
-- - 表に無い拠点を指すつながりは無視する（目印との突き合わせは読み込み時に行う）

local Gun = require("./Gun")

export type Kyoten = {
	id: string,
	-- 所属の軍。どちらにも属さない拠点は nil
	gun: Gun.Gun?,
	honjin: boolean,
	-- 兵站線が切れても孤立しないか（兵糧庫）
	neverIsolated: boolean?,
}

export type Tsunagari = {
	-- 両端の拠点 ID
	kyotenA: string,
	kyotenB: string,
	-- 通れない軍。落石で塞いだ区間は、相手の軍にだけ通れなくする
	blocked: { [Gun.Gun]: boolean }?,
}

export type GunResult = {
	-- 兵站線につながった拠点
	connected: { [string]: boolean },
	-- 孤立した拠点
	isolated: { [string]: boolean },
}

export type Result = { [Gun.Gun]: GunResult }

local Heitansen = {}

-- 軍ごとに、兵站線につながった拠点と孤立した拠点を求める
function Heitansen.compute(kyotenList: { Kyoten }, tsunagariList: { Tsunagari }): Result
	local byId: { [string]: Kyoten } = {}
	for _, kyoten in kyotenList do
		byId[kyoten.id] = kyoten
	end

	-- 拠点 ID から、つながった先の拠点 ID とそのつながりの一覧を引く
	local neighbors: { [string]: { { id: string, tsunagari: Tsunagari } } } = {}
	for _, tsunagari in tsunagariList do
		if byId[tsunagari.kyotenA] and byId[tsunagari.kyotenB] then
			for _, pair in { { tsunagari.kyotenA, tsunagari.kyotenB }, { tsunagari.kyotenB, tsunagari.kyotenA } } do
				local from, to = pair[1], pair[2]
				neighbors[from] = neighbors[from] or {}
				table.insert(neighbors[from], { id = to, tsunagari = tsunagari })
			end
		end
	end

	local result = {} :: Result
	for _, gun in Gun.list do
		local connected: { [string]: boolean } = {}
		local queue: { string } = {}
		for _, kyoten in kyotenList do
			if kyoten.gun == gun and kyoten.honjin and not connected[kyoten.id] then
				connected[kyoten.id] = true
				table.insert(queue, kyoten.id)
			end
		end

		-- 本陣から幅優先でたどる。たどった拠点は connected に入れるので、環があっても止まる
		local head = 1
		while head <= #queue do
			local from = queue[head]
			head += 1
			for _, neighbor in neighbors[from] or {} do
				local blocked = neighbor.tsunagari.blocked
				local passable = not (blocked and blocked[gun])
				if passable and not connected[neighbor.id] and byId[neighbor.id].gun == gun then
					connected[neighbor.id] = true
					table.insert(queue, neighbor.id)
				end
			end
		end

		local isolated: { [string]: boolean } = {}
		for _, kyoten in kyotenList do
			if kyoten.gun == gun and not connected[kyoten.id] then
				if kyoten.neverIsolated then
					connected[kyoten.id] = true
				else
					isolated[kyoten.id] = true
				end
			end
		end
		result[gun] = { connected = connected, isolated = isolated }
	end
	return result
end

-- 拠点が兵站線につながっているか。所属が gun でない拠点は false
function Heitansen.isConnected(result: Result, gun: Gun.Gun, kyotenId: string): boolean
	return result[gun].connected[kyotenId] == true
end

-- つながりが入っている兵站線の軍。両端がその軍の兵站線につながった拠点で、その軍が通れるつながりなら、その軍。
-- どちらの兵站線にも入っていなければ nil
function Heitansen.gunOf(result: Result, tsunagari: Tsunagari): Gun.Gun?
	for _, gun in Gun.list do
		local blocked = tsunagari.blocked
		local passable = not (blocked and blocked[gun])
		local connected = result[gun].connected
		if passable and connected[tsunagari.kyotenA] and connected[tsunagari.kyotenB] then
			return gun
		end
	end
	return nil
end

return Heitansen
