--!strict
local Progress = require("./Progress")
local Stages = require("./Stages")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

local function stage(id: string, clan: any, order: number, next: string?): Stages.Stage
	return {
		id = id,
		displayName = id,
		clan = clan,
		order = order,
		next = next,
		tekigun = "Fuma",
		shuryo = {},
		npcs = {},
		kukaku = id,
		eventScenes = {},
	}
end

-- 伊賀の3ステージと甲賀の1ステージの定義表
local CATALOG: Progress.Catalog = {
	Iga1 = stage("Iga1", "Iga", 1, "Iga2"),
	Iga2 = stage("Iga2", "Iga", 2, "Iga3"),
	Iga3 = stage("Iga3", "Iga", 3, nil),
	Koga1 = stage("Koga1", "Koga", 1, nil),
}

test(
	"新規のプレイヤーは各ストーリーの最初のステージだけを開放し、クリアは無い",
	function()
		local data = Progress.new(CATALOG)
		expect(data.version).toBe(Progress.VERSION)
		expect(data.unlocked).toEqual({ "Iga1", "Koga1" })
		expect(data.cleared).toEqual({})
	end
)

test("今の定義表の新規のプレイヤーは Iga1 を開放している", function()
	local data = Progress.new()
	expect(Progress.isUnlocked(data, "Iga1")).toBe(true)
	expect(data.unlocked).toEqual(Progress.firstStages())
end)

test(
	"クリアするとそのステージと次のステージを開放し、新しく開放したステージを返す",
	function()
		local data, newly = Progress.recordClear(Progress.new(CATALOG), "Iga1", CATALOG)
		expect(data.cleared).toEqual({ "Iga1" })
		expect(data.unlocked).toEqual({ "Iga1", "Iga2", "Koga1" })
		expect(newly).toEqual({ "Iga2" })
		expect(Progress.isCleared(data, "Iga1")).toBe(true)
		expect(Progress.isUnlocked(data, "Iga3")).toBe(false)
	end
)

test("同じステージを2回クリアしても、新しく開放するステージは無い", function()
	local once = Progress.recordClear(Progress.new(CATALOG), "Iga1", CATALOG)
	local twice, newly = Progress.recordClear(once, "Iga1", CATALOG)
	expect(newly).toEqual({})
	expect(twice).toEqual(once)
end)

test("ストーリーの最後のステージのクリアは、次を開放しない", function()
	local data = { version = 1, unlocked = { "Iga1", "Iga2", "Iga3", "Koga1" }, cleared = { "Iga1", "Iga2" } }
	local next, newly = Progress.recordClear(data, "Iga3", CATALOG)
	expect(newly).toEqual({})
	expect(next.cleared).toEqual({ "Iga1", "Iga2", "Iga3" })
	expect(next.unlocked).toEqual(data.unlocked)
end)

test("開放していないステージのクリアは、そのステージと次を開放する", function()
	local _, newly = Progress.recordClear(Progress.new(CATALOG), "Iga2", CATALOG)
	expect(newly).toEqual({ "Iga2", "Iga3" })
end)

test("定義表に無いステージのクリアは記録しない", function()
	local data = Progress.new(CATALOG)
	local next, newly = Progress.recordClear(data, "Saika9", CATALOG)
	expect(next).toEqual(data)
	expect(newly).toEqual({})
end)

test("記録は引数の進行を書き換えない", function()
	local data = Progress.new(CATALOG)
	Progress.recordClear(data, "Iga1", CATALOG)
	expect(data).toEqual(Progress.new(CATALOG))
end)

test("合成は開放済みとクリア済みの和集合で、版は新しい方", function()
	local a = { version = 1, unlocked = { "Iga1", "Iga2" }, cleared = { "Iga1" } }
	local b = { version = 2, unlocked = { "Koga1", "Iga1" }, cleared = { "Koga1" } }
	local merged = Progress.merge(a, b)
	expect(merged).toEqual({ version = 2, unlocked = { "Iga1", "Iga2", "Koga1" }, cleared = { "Iga1", "Koga1" } })
	expect(a.unlocked).toEqual({ "Iga1", "Iga2" })
end)

test(
	"読み込みに失敗したまま記録したクリアは、保存済みの記録と合わせても両方残る",
	function()
		-- 保存済みの記録は Iga1 のクリアと Iga2 の開放。読み込めなかったサーバーは新規として Koga1 をクリアした
		local stored = { version = 1, unlocked = { "Iga1", "Iga2", "Koga1" }, cleared = { "Iga1" } }
		local local_ = Progress.recordClear(Progress.new(CATALOG), "Koga1", CATALOG)
		local saved = Progress.merge(stored, local_)
		expect(saved.unlocked).toEqual({ "Iga1", "Iga2", "Koga1" })
		expect(saved.cleared).toEqual({ "Iga1", "Koga1" })
	end
)

test("DataStore から読んだ値が表でなければ新規として扱う", function()
	expect(Progress.normalize(nil, CATALOG)).toBe(nil)
	expect(Progress.normalize("Iga1", CATALOG)).toBe(nil)
	expect(Progress.normalize(3, CATALOG)).toBe(nil)
end)

test(
	"読んだ値の欠けた項目と文字列でない要素は捨て、最初のステージは必ず開放する",
	function()
		local data = Progress.normalize({ cleared = { "Iga1", 5, "Iga1" } }, CATALOG) :: Progress.Data
		expect(data).toEqual({ version = Progress.VERSION, unlocked = { "Iga1", "Koga1" }, cleared = { "Iga1" } })
	end
)

test("読んだ値の定義表に無いステージと新しい版はそのまま残す", function()
	local data =
		Progress.normalize({ version = 2, unlocked = { "Fuma9" }, cleared = { "Fuma9" } }, CATALOG) :: Progress.Data
	expect(data.version).toBe(2)
	expect(data.unlocked).toEqual({ "Fuma9", "Iga1", "Koga1" })
	expect(data.cleared).toEqual({ "Fuma9" })
end)

test("M1 の保存データは、版と開放とクリアの記録を変えずに読み込める", function()
	-- M1 で伊賀第1ステージをクリアした人の保存データ
	local data = Progress.normalize({ version = 1, unlocked = { "Iga1" }, cleared = { "Iga1" } }) :: Progress.Data
	expect(Progress.VERSION).toBe(1)
	expect(data.version).toBe(1)
	expect(Progress.isUnlocked(data, "Iga1")).toBe(true)
	expect(data.cleared).toEqual({ "Iga1" })
end)

test("試験用ステージは最初から開放せず、クリアしても記録しない", function()
	local data = Progress.new()
	expect(Progress.isUnlocked(data, "Test")).toBe(false)
	local next, newly = Progress.recordClear(data, "Test")
	expect(next).toBe(data)
	expect(newly).toEqual({})
	expect(Progress.isCleared(next, "Test")).toBe(false)
end)

local function participant(userId: number, sortied: boolean, left: boolean, waiting: boolean): Progress.Participant
	return { userId = userId, sortied = sortied, left = left, waiting = waiting }
end

test("勝ったときは、出撃して残っている人だけにクリアを記録する", function()
	local participants = {
		participant(1, true, false, false),
		participant(2, true, true, false), -- 出撃した後に抜けた
		participant(3, false, false, true), -- 出撃中に入って待っている
		participant(4, true, false, false),
	}
	expect(Progress.clearTargets(participants, true)).toEqual({ 1, 4 })
end)

test("負けたときは誰にもクリアを記録しない", function()
	local participants = { participant(1, true, false, false), participant(2, true, false, false) }
	expect(Progress.clearTargets(participants, false)).toEqual({})
end)

test("抜けて入り直し、待っている人には記録しない", function()
	-- 同じ人が出撃した後に抜け、入り直して待機中になった
	local participants = { participant(5, true, false, true) }
	expect(Progress.clearTargets(participants, true)).toEqual({})
end)
