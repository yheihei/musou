--!strict
-- プレイヤーごとの進行（開放済みとクリア済みのステージ）を DataStore に保存し、サーバーをまたいで引き継ぐ。
-- 計算は ReplicatedStorage.Shared.Progress が持つ。
--
-- - 入室時に読み込み、失敗したら間を空けて読み直す。読み込めないままでも新規の進行で続ける
-- - 保存は UpdateAsync で、保存済みの記録と和集合にして書く。読み込みに失敗したまま保存しても記録は消えない
-- - クリアを記録したらすぐ保存し、退室時とサーバーの終了時（BindToClose）にも保存する
-- - Studio では本番と別の DataStore に保存する
-- - DataStore が使えない環境（公開前のプレースや、Studio から API サービスへのアクセスを許していないとき）は、
--   警告を出してサーバーのメモリにだけ保存する。サーバーを閉じると消える

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Progress = require(ReplicatedStorage.Shared.Progress)
local Stages = require(ReplicatedStorage.Shared.Stages)
local DebugCommand = require(script.Parent.Parent.DebugCommand)

local ProgressService = {}

-- DataStore の名前。Studio のテストプレイの記録が本番に混ざらないよう分ける
local STORE_NAME = "Progress"
local STUDIO_STORE_NAME = "ProgressStudio"
-- 読み込みと保存を試す回数と、やり直すまでの秒数（回ごとに倍にする）
local ATTEMPTS = 3
local RETRY_WAIT = 1

type Record = {
	data: Progress.Data,
	-- DataStore から読み込めたか
	loaded: boolean,
	-- 保存していない変更があるか
	dirty: boolean,
}

local records: { [Player]: Record } = {}
-- 読み込み中のプレイヤー
local loading: { [Player]: boolean } = {}
-- 進行を保存する DataStore。使えない環境では nil
local store: DataStore? = nil
-- DataStore が使えない環境の保存先（UserId から引く）
local memory: { [number]: Progress.Data } = {}

local changed = Instance.new("BindableEvent")
-- プレイヤーの開放済みのステージが変わったとき（読み込みとクリアの記録）に、プレイヤーで発火する
ProgressService.changed = changed.Event

local function keyOf(userId: number): string
	return `Player_{userId}`
end

-- 失敗したら間を空けてやり直す。成功したら true と結果、全部失敗したら false と最後のエラーを返す
local function retry<T>(label: string, attempt: () -> T): (boolean, any)
	local wait = RETRY_WAIT
	local lastError: any = nil
	for index = 1, ATTEMPTS do
		local ok, result = pcall(attempt)
		if ok then
			return true, result
		end
		lastError = result
		warn(`ProgressService: {label} に失敗した（{index}/{ATTEMPTS}回目）: {result}`)
		if index < ATTEMPTS then
			task.wait(wait)
			wait *= 2
		end
	end
	return false, lastError
end

-- DataStore を使えるか確かめる。使えなければ警告を出してメモリに保存する
local function openStore()
	if game.GameId == 0 then
		warn(
			"ProgressService: プレースが公開されていないので DataStore を使えない。進行はこのサーバーのメモリにだけ保存する"
		)
		return
	end
	local name = if RunService:IsStudio() then STUDIO_STORE_NAME else STORE_NAME
	local ok, result = pcall(function()
		local opened = DataStoreService:GetDataStore(name)
		-- Studio で API サービスへのアクセスを許していないと、ここで失敗する
		opened:GetAsync("Probe")
		return opened
	end)
	if not ok then
		warn(
			`ProgressService: DataStore {name} を使えない（{result}）。進行はこのサーバーのメモリにだけ保存する`
		)
		return
	end
	store = result
end

local function load(player: Player): (Progress.Data, boolean)
	local opened = store
	if not opened then
		return memory[player.UserId] or Progress.new(), true
	end
	local ok, raw = retry(`{player.Name} の読み込み`, function()
		return opened:GetAsync(keyOf(player.UserId))
	end)
	if not ok then
		-- 読み込めなくても遊べるよう新規の進行で続ける。保存するときに保存済みの記録と合わせる
		return Progress.new(), false
	end
	return Progress.normalize(raw) or Progress.new(), true
end

local function save(player: Player)
	local record = records[player]
	if not record or not record.dirty then
		return
	end
	local current = record.data
	local opened = store
	if not opened then
		memory[player.UserId] = Progress.merge(memory[player.UserId] or Progress.new(), current)
		record.dirty = false
		return
	end
	local ok, saved = retry(`{player.Name} の保存`, function()
		return opened:UpdateAsync(keyOf(player.UserId), function(old: unknown)
			return Progress.merge(Progress.normalize(old) or Progress.new(), current)
		end)
	end)
	if not ok then
		return
	end
	-- 保存している間に別のクリアを記録していたら、その保存に任せて dirty は残す
	if record.data == current then
		record.dirty = false
	end
	-- 保存したもの（保存済みの記録を合わせたもの）を今の進行に取り込む
	local merged = Progress.normalize(saved)
	if merged then
		local before = record.data.unlocked
		record.data = Progress.merge(record.data, merged)
		record.loaded = true
		if #record.data.unlocked ~= #before and records[player] == record then
			changed:Fire(player)
		end
	end
end

local function onPlayerAdded(player: Player)
	if records[player] or loading[player] then
		return
	end
	loading[player] = true
	local data, loaded = load(player)
	loading[player] = nil
	if not player.Parent then
		return
	end
	records[player] = { data = data, loaded = loaded, dirty = false }
	changed:Fire(player)
end

local function onPlayerRemoving(player: Player)
	save(player)
	records[player] = nil
end

-- 進行を読み終えたか
function ProgressService.isReady(player: Player): boolean
	return records[player] ~= nil
end

-- 保存済みの進行を読めたか。一度でも保存できたら true。DataStore が使えない環境ではメモリから読むので true
function ProgressService.isLoaded(player: Player): boolean
	local record = records[player]
	return record ~= nil and record.loaded
end

-- クリア済みのステージ ID（ID の順）。読み終える前は空
function ProgressService.getCleared(player: Player): { string }
	local record = records[player]
	return if record then table.clone(record.data.cleared) else {}
end

-- 開放済みのステージ ID（ID の順）。読み終える前は新規の進行とみなす
function ProgressService.getUnlocked(player: Player): { string }
	local record = records[player]
	return table.clone(if record then record.data.unlocked else Progress.new().unlocked)
end

function ProgressService.isUnlocked(player: Player, stageId: string): boolean
	return table.find(ProgressService.getUnlocked(player), stageId) ~= nil
end

-- 参加者全員に stageId のクリアを記録してすぐ保存する。プレイヤーごとに新しく開放したステージ ID を返す
function ProgressService.recordClear(players: { Player }, stageId: string): { [Player]: { string } }
	local result: { [Player]: { string } } = {}
	for _, player in players do
		local record = records[player]
		if record then
			local data, newly = Progress.recordClear(record.data, stageId)
			result[player] = newly
			if data ~= record.data then
				record.data = data
				record.dirty = true
				task.spawn(save, player)
				changed:Fire(player)
			end
		end
	end
	return result
end

local function registerDebugCommands()
	DebugCommand.register(
		"RecordClear",
		"<プレイヤー名> <ステージ ID>",
		"ステージのクリアを記録してすぐ保存する（勝利の処理と同じ関数）",
		function(name, stageId)
			local player = DebugCommand.findPlayer(name)
			if type(stageId) ~= "string" or not Stages.get(stageId) then
				error(`ステージ ID {tostring(stageId)} は定義表に無い`, 0)
			end
			local newly = ProgressService.recordClear({ player }, stageId)[player]
			if not newly then
				return `{player.Name} の進行をまだ読み込んでいない`
			end
			local opened = if #newly > 0 then table.concat(newly, "、") else "なし"
			return `{player.Name} の {stageId} のクリアを記録した（新しく開放: {opened}）`
		end
	)
	DebugCommand.register(
		"DumpProgress",
		"<プレイヤー名>",
		"プレイヤーの進行と保存先を JSON で返す",
		function(name)
			local player = DebugCommand.findPlayer(name)
			local record = records[player]
			return HttpService:JSONEncode({
				store = if store then "DataStore" else "Memory",
				ready = record ~= nil,
				loaded = record and record.loaded,
				dirty = record and record.dirty,
				data = record and record.data,
			})
		end
	)
end

function ProgressService.start()
	registerDebugCommands()
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	-- DataStore を確かめる間、ほかのサービスの起動を待たせない
	task.spawn(function()
		openStore()
		Players.PlayerAdded:Connect(onPlayerAdded)
		for _, player in Players:GetPlayers() do
			task.spawn(onPlayerAdded, player)
		end
	end)
	-- サーバーを閉じるときに、残っている全員の進行を保存し終えるまで待つ
	game:BindToClose(function()
		local pending = 0
		for player in records do
			pending += 1
			task.spawn(function()
				save(player)
				pending -= 1
			end)
		end
		while pending > 0 do
			task.wait()
		end
	end)
end

return ProgressService
