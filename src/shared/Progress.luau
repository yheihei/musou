--!strict
-- プレイヤーごとの進行（開放済みとクリア済みのステージ）の計算。DataStore への保存は ProgressService が持つ。
-- Roblox の API は使わない。
--
-- - 新規のプレイヤーは、各ストーリーの最初のステージだけを開放している
-- - クリアすると、そのステージと次のステージを開放する
-- - 保存データは版番号を持つ。合成は開放済みとクリア済みの和集合にし、どちらの記録も失わない
--   （読み込みに失敗したまま保存しても、保存済みの記録と合わせて残す）
-- - 定義表に無いステージ ID も消さずに持つ（ステージを外した後に戻しても記録が残るように）
-- - ステージの定義表は引数で差し替えられる（テスト用）。省くと Stages.definitions を使う

local Stages = require("./Stages")

export type Data = {
	-- 保存データの版
	version: number,
	-- 開放済みのステージ ID（ID の順）
	unlocked: { string },
	-- クリア済みのステージ ID（ID の順）
	cleared: { string },
}

export type Catalog = { [string]: Stages.Stage }

local Progress = {}

-- 今の保存データの版
Progress.VERSION = 1

local function catalogOf(catalog: Catalog?): Catalog
	return catalog or Stages.definitions
end

-- 重なりを除いて ID の順に並べる
local function sorted(ids: { string }): { string }
	local seen: { [string]: boolean } = {}
	local result = {}
	for _, id in ids do
		if not seen[id] then
			seen[id] = true
			table.insert(result, id)
		end
	end
	table.sort(result)
	return result
end

local function union(a: { string }, b: { string }): { string }
	local all = table.clone(a)
	table.move(b, 1, #b, #all + 1, all)
	return sorted(all)
end

-- 各ストーリーの最初のステージの ID
function Progress.firstStages(catalog: Catalog?): { string }
	local ids = {}
	for id, stage in catalogOf(catalog) do
		if stage.order == 1 then
			table.insert(ids, id)
		end
	end
	return sorted(ids)
end

-- 新規のプレイヤーの進行
function Progress.new(catalog: Catalog?): Data
	return { version = Progress.VERSION, unlocked = Progress.firstStages(catalog), cleared = {} }
end

function Progress.isUnlocked(data: Data, stageId: string): boolean
	return table.find(data.unlocked, stageId) ~= nil
end

function Progress.isCleared(data: Data, stageId: string): boolean
	return table.find(data.cleared, stageId) ~= nil
end

-- 2つの進行を合わせる。開放済みとクリア済みは和集合、版は新しい方。引数は書き換えない
function Progress.merge(a: Data, b: Data): Data
	return {
		version = math.max(a.version, b.version),
		unlocked = union(a.unlocked, b.unlocked),
		cleared = union(a.cleared, b.cleared),
	}
end

-- stageId のクリアを記録した進行と、新しく開放したステージ ID を返す。
-- 定義表に無いステージは記録しない。引数は書き換えない
function Progress.recordClear(data: Data, stageId: string, catalog: Catalog?): (Data, { string })
	local stages = catalogOf(catalog)
	local stage = stages[stageId]
	if not stage then
		return data, {}
	end
	local opened = { stageId }
	if stage.next and stages[stage.next] then
		table.insert(opened, stage.next)
	end
	local newlyUnlocked = {}
	for _, id in opened do
		if not Progress.isUnlocked(data, id) then
			table.insert(newlyUnlocked, id)
		end
	end
	local next = Progress.merge(data, { version = Progress.VERSION, unlocked = opened, cleared = { stageId } })
	return next, sorted(newlyUnlocked)
end

local function stringsOf(value: unknown): { string }
	local result = {}
	if type(value) == "table" then
		for _, item in value :: { any } do
			if type(item) == "string" then
				table.insert(result, item)
			end
		end
	end
	return result
end

-- DataStore から読んだ値を進行にする。表でなければ nil を返す（新規として扱う）。
-- 欠けた項目は空にし、各ストーリーの最初のステージは必ず開放済みにする
function Progress.normalize(raw: unknown, catalog: Catalog?): Data?
	if type(raw) ~= "table" then
		return nil
	end
	local source = raw :: { [string]: any }
	local version = if type(source.version) == "number" then source.version else Progress.VERSION
	local stored: Data = {
		version = version,
		unlocked = sorted(stringsOf(source.unlocked)),
		cleared = sorted(stringsOf(source.cleared)),
	}
	return Progress.merge(stored, Progress.new(catalog))
end

return Progress
