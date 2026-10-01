--!strict
-- ロビーと区画の目印の置き場所・名前と、目印の検証（ADR 0006）。
-- 目印はプレースに置き、Git では管理しない。プレースから読むのはサーバーの KukakuService。
-- Roblox の API は使わない。
--
-- | 目印 | 置き場所 | 名前 |
-- |---|---|---|
-- | ロビー | Workspace.Lobby | SpawnLocation（プレースで唯一） |
-- | 区画 | Workspace.Stages の下のフォルダ | 区画名（Iga1、Test など） |
-- | 区画の範囲 | <区画>.Mejirushi.Bounds | Bounds |
-- | 出撃地点 | <区画>.Mejirushi.ShutsugekiChiten | 1〜パーティーの上限人数 |
--
-- - 目印のパーツにはタグ Mejirushi を付け、Anchored を true、CanCollide・CanTouch・CanQuery を false にする
-- - プレースには編集しやすいよう半透明で保存し、サーバーが起動時に透明にする
-- - 出撃地点のパーツの向き（LookVector）が、出撃したプレイヤーの向きになる

local Mejirushi = {}

-- 目印のパーツに付けるタグ
Mejirushi.TAG = "Mejirushi"

-- Workspace の下のロビーと、ロビーへの出現位置
Mejirushi.LOBBY = "Lobby"
Mejirushi.LOBBY_SPAWN = "SpawnLocation"

-- Workspace の下の区画の置き場所
Mejirushi.STAGES = "Stages"

-- 区画のフォルダの下の、目印をまとめるフォルダ
Mejirushi.FOLDER = "Mejirushi"

-- 目印のフォルダの下の、区画の範囲と出撃地点
Mejirushi.BOUNDS = "Bounds"
Mejirushi.SHUTSUGEKI_CHITEN = "ShutsugekiChiten"

export type ShutsugekiCheck = {
	-- 使える出撃地点の番号（1から上限人数まで、番号の順）
	numbers: { number },
	-- 1〜上限人数のうち欠けている番号
	missing: { number },
	-- 同じ番号のパーツが2つ以上ある番号
	duplicated: { number },
	-- 1〜上限人数の番号として読めない名前（名前の順）
	unknown: { string },
}

-- 出撃地点のパーツの名前を調べる。names は ShutsugekiChiten の子の名前、count はパーティーの上限人数
function Mejirushi.checkShutsugekiChiten(names: { string }, count: number): ShutsugekiCheck
	local seen: { [number]: number } = {}
	local unknown = {}
	for _, name in names do
		local number = if string.match(name, "^[1-9]%d*$") then tonumber(name) else nil
		if number and number <= count then
			seen[number] = (seen[number] or 0) + 1
		else
			table.insert(unknown, name)
		end
	end
	local numbers, missing, duplicated = {}, {}, {}
	for number = 1, count do
		local found = seen[number]
		if found then
			table.insert(numbers, number)
			if found > 1 then
				table.insert(duplicated, number)
			end
		else
			table.insert(missing, number)
		end
	end
	table.sort(unknown)
	return { numbers = numbers, missing = missing, duplicated = duplicated, unknown = unknown }
end

-- 出撃するメンバーの順番（1から）に使う出撃地点の番号。available は使える番号（番号の順）。
-- 地点がメンバーより少ないときは、1つ目の地点から順に使い回す。地点が無ければ nil
function Mejirushi.shutsugekiNumberOf(memberIndex: number, available: { number }): number?
	if #available == 0 then
		return nil
	end
	return available[(memberIndex - 1) % #available + 1]
end

return Mejirushi
