--!strict
-- プレイヤーごとの記録を DataStore に保存する共通の部品。特技の記録（TokugiService）と秘計の熟練度の記録（JukurendoService）が使う。
-- 記録の形と変更の当て方は、使う側が Spec で渡す（計算は ReplicatedStorage.Shared の純粋関数に置き、Lune でテストする）。
-- 進行（ProgressService）は保存データの形を M1 から変えないため、これを使わずに自前で保存する。
--
-- - 入室時に読み込み、失敗したら間を空けて読み直す。読み込めないままでも新規の記録で続ける（isLoaded が false）
-- - 記録を変えるときは変更（Change）を渡す。変更は書くまで溜め、今の記録は、保存済みの記録に溜めた変更を当てたものにする。
--   読み込む前に受けた変更も、読み込んだ記録に当て直す
-- - 保存は UpdateAsync で、DataStore に今ある記録に溜めた変更を当てて書く。読み込みに失敗したまま保存しても、
--   ほかのサーバーが先に書いていても、記録は消えない。書けた変更は溜めた変更から外し、書いた記録を保存済みの記録にする
-- - 保存は変更を受けたらすぐと、退室時とサーバーの終了時（BindToClose）に行う。
--   同じプレイヤーの保存は1つずつ行う（重ねると同じ変更を2回当てるため）
-- - UpdateAsync が書き終えた後にエラーを返すと、やり直しで同じ変更をもう一度当てることがある（巻物や熟練度なら多く入る）。
--   起きるのはまれなので、そのままにしている
-- - Studio では本番と別の DataStore（名前の後ろに Studio を付ける）に保存する
-- - DataStore が使えない環境（公開前のプレースや、Studio から API サービスへのアクセスを許していないとき）は、
--   警告を出してサーバーのメモリにだけ保存する。サーバーを閉じると消える

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local PlayerStore = {}

-- 読み込みと保存を試す回数と、やり直すまでの秒数（回ごとに倍にする）
local ATTEMPTS = 3
local RETRY_WAIT = 1

export type Spec<Data, Change> = {
	-- DataStore の名前。Studio では後ろに Studio を付けた名前を使う
	name: string,
	-- 新規の記録
	new: () -> Data,
	-- DataStore から読んだ値を記録にする。表でないなど読めなければ nil（新規として扱う）
	normalize: (raw: unknown) -> Data?,
	-- 記録に変更を1つ当てた記録を返す。引数は書き換えない
	apply: (data: Data, change: Change) -> Data,
}

export type Store<Data, Change> = {
	-- 記録が変わったとき（読み込み・変更・保存で書いた記録を取り込んだとき・消したとき）に、プレイヤーで発火する
	changed: RBXScriptSignal,
	-- 入退室の処理と BindToClose を始める
	start: () -> (),
	-- 読み込みを終えたか（読み込めなかったときも true）
	isReady: (player: Player) -> boolean,
	-- 保存済みの記録を読めたか。一度でも保存できたら true。DataStore が使えない環境ではメモリから読むので true
	isLoaded: (player: Player) -> boolean,
	-- 今の記録。入室していなければ新規の記録
	get: (player: Player) -> Data,
	-- 記録に変更を当て、すぐ保存する。入室していなければ何もせず false
	change: (player: Player, change: Change) -> boolean,
	-- 保存済みの記録ごと消して新規の記録にする（確認のやり直し用）。消せたら true
	reset: (player: Player) -> boolean,
	-- 保存先と、読み込みと保存の様子（窓口の確認用）
	describe: (player: Player) -> { [string]: any },
}

-- プレイヤー1人の記録の様子
type Record<Data, Change> = {
	-- 保存済みの記録（読み込んだ記録か、最後に書いた記録）。読み込む前と読めなかったときは新規の記録
	base: Data,
	-- まだ書いていない変更（受けた順）
	pending: { Change },
	-- base に pending を当てた、今の記録
	data: Data,
	ready: boolean,
	loaded: boolean,
	-- 保存している最中か
	saving: boolean,
}

local function keyOf(userId: number): string
	return `Player_{userId}`
end

function PlayerStore.new<Data, Change>(spec: Spec<Data, Change>): Store<Data, Change>
	local records: { [Player]: Record<Data, Change> } = {}
	-- 記録を保存する DataStore。使えない環境では nil
	local opened: DataStore? = nil
	-- 保存先の種類（窓口の確認用）。DataStore を確かめ終えるまでは Opening
	local kind = "Opening"
	-- DataStore が使えない環境の保存先（UserId から引く）
	local memory: { [number]: Data } = {}
	local changedEvent = Instance.new("BindableEvent")
	local storeName = if RunService:IsStudio() then `{spec.name}Studio` else spec.name

	-- 失敗したら間を空けてやり直す。成功したら true と結果、全部失敗したら false と最後のエラーを返す
	local function retry(label: string, attempt: () -> any): (boolean, any)
		local wait = RETRY_WAIT
		local lastError: any = nil
		for index = 1, ATTEMPTS do
			local ok, result = pcall(attempt)
			if ok then
				return true, result
			end
			lastError = result
			warn(`PlayerStore（{storeName}）: {label} に失敗した（{index}/{ATTEMPTS}回目）: {result}`)
			if index < ATTEMPTS then
				task.wait(wait)
				wait *= 2
			end
		end
		return false, lastError
	end

	local function applyAll(data: Data, changes: { Change }): Data
		local result = data
		for _, change in changes do
			result = spec.apply(result, change)
		end
		return result
	end

	-- DataStore を使えるか確かめる。使えなければ警告を出してメモリに保存する
	local function openStore()
		if game.GameId == 0 then
			warn(
				`PlayerStore: プレースが公開されていないので DataStore {storeName} を使えない。記録はこのサーバーのメモリにだけ保存する`
			)
			kind = "Memory"
			return
		end
		local ok, result = pcall(function()
			local dataStore = DataStoreService:GetDataStore(storeName)
			-- Studio で API サービスへのアクセスを許していないと、ここで失敗する
			dataStore:GetAsync("Probe")
			return dataStore
		end)
		if not ok then
			warn(
				`PlayerStore: DataStore {storeName} を使えない（{result}）。記録はこのサーバーのメモリにだけ保存する`
			)
			kind = "Memory"
			return
		end
		opened = result
		kind = "DataStore"
	end

	-- 保存済みの記録を読む。読めたら記録（無ければ nil）と true、読めなければ nil と false を返す
	local function read(player: Player): (Data?, boolean)
		local dataStore = opened
		if not dataStore then
			return memory[player.UserId], true
		end
		local ok, raw = retry(`{player.Name} の読み込み`, function()
			return dataStore:GetAsync(keyOf(player.UserId))
		end)
		if not ok then
			return nil, false
		end
		return spec.normalize(raw), true
	end

	-- 溜めた変更を書く。同じプレイヤーの保存は1つずつ行い、前の保存が終わるのを待つ
	local function save(player: Player, record: Record<Data, Change>)
		while record.saving do
			task.wait()
		end
		local count = #record.pending
		if count == 0 then
			return
		end
		record.saving = true
		local changes = table.move(record.pending, 1, count, 1, {})
		local dataStore = opened
		local ok = true
		local written: any = nil
		if dataStore then
			ok, written = retry(`{player.Name} の保存`, function()
				return dataStore:UpdateAsync(keyOf(player.UserId), function(old: unknown)
					return applyAll(spec.normalize(old) or spec.new(), changes)
				end)
			end)
		else
			local merged = applyAll(memory[player.UserId] or spec.new(), changes)
			memory[player.UserId] = merged
			written = merged
		end
		record.saving = false
		if not ok then
			return
		end
		-- 書けた変更を外し、書いた記録に、保存している間に受けた変更を当て直す
		record.pending = table.move(record.pending, count + 1, #record.pending, 1, {})
		record.base = spec.normalize(written) or applyAll(record.base, changes)
		record.loaded = true
		record.data = applyAll(record.base, record.pending)
		if records[player] == record then
			changedEvent:Fire(player)
		end
	end

	local function onPlayerAdded(player: Player)
		if records[player] then
			return
		end
		local fresh = spec.new()
		local record: Record<Data, Change> = {
			base = fresh,
			pending = {},
			data = fresh,
			ready = false,
			loaded = false,
			saving = false,
		}
		records[player] = record
		local stored, loaded = read(player)
		if records[player] ~= record then
			-- 読み込む間に抜けた
			return
		end
		-- 読み込む間に保存できていれば、書いた記録の方が新しいので読んだ記録は捨てる
		if not record.loaded then
			if stored then
				record.base = stored
			end
			record.loaded = loaded
			record.data = applyAll(record.base, record.pending)
		end
		record.ready = true
		changedEvent:Fire(player)
	end

	local function onPlayerRemoving(player: Player)
		local record = records[player]
		if not record then
			return
		end
		save(player, record)
		if records[player] == record then
			records[player] = nil
		end
	end

	local store: Store<Data, Change> = {
		changed = changedEvent.Event,
		start = function()
			Players.PlayerRemoving:Connect(onPlayerRemoving)
			-- DataStore を確かめる間、ほかのサービスの起動を待たせない
			task.spawn(function()
				openStore()
				Players.PlayerAdded:Connect(onPlayerAdded)
				for _, player in Players:GetPlayers() do
					task.spawn(onPlayerAdded, player)
				end
			end)
			-- サーバーを閉じるときに、残っている全員の変更を書き終えるまで待つ
			game:BindToClose(function()
				local remaining = 0
				for player, record in table.clone(records) do
					remaining += 1
					task.spawn(function()
						save(player, record)
						remaining -= 1
					end)
				end
				while remaining > 0 do
					task.wait()
				end
			end)
		end,
		isReady = function(player: Player): boolean
			local record = records[player]
			return record ~= nil and record.ready
		end,
		isLoaded = function(player: Player): boolean
			local record = records[player]
			return record ~= nil and record.loaded
		end,
		get = function(player: Player): Data
			local record = records[player]
			return if record then record.data else spec.new()
		end,
		change = function(player: Player, change: Change): boolean
			local record = records[player]
			if not record then
				return false
			end
			table.insert(record.pending, change)
			record.data = spec.apply(record.data, change)
			changedEvent:Fire(player)
			task.spawn(save, player, record)
			return true
		end,
		reset = function(player: Player): boolean
			local record = records[player]
			if not record then
				return false
			end
			while record.saving do
				task.wait()
			end
			record.saving = true
			local ok = true
			local dataStore = opened
			if dataStore then
				ok = retry(`{player.Name} の記録の削除`, function()
					return dataStore:RemoveAsync(keyOf(player.UserId))
				end)
			else
				memory[player.UserId] = nil
			end
			record.saving = false
			if not ok then
				return false
			end
			local fresh = spec.new()
			record.base = fresh
			record.pending = {}
			record.data = fresh
			record.ready = true
			record.loaded = true
			if records[player] == record then
				changedEvent:Fire(player)
			end
			return true
		end,
		describe = function(player: Player): { [string]: any }
			local record = records[player]
			return {
				store = kind,
				name = storeName,
				ready = record ~= nil and record.ready,
				loaded = record ~= nil and record.loaded,
				pending = if record then #record.pending else 0,
				saving = record ~= nil and record.saving,
			}
		end,
	}
	return store
end

return PlayerStore
