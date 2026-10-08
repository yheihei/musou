--!strict
-- 秘計の系統ごとの熟練度と、覚えた秘計。プレイヤーごとに保存し（PlayerStore。DataStore の名前は Jukurendo）、
-- 決着したときに戦い方の数から熟練度を足す。出撃前に選べる秘計は、ここで引く覚えた秘計だけ（SelectionService）。
-- 計算は ReplicatedStorage.Shared.Jukurendo、系統と値は Config.luau の Jukurendo 節にある。
--
-- - 記録は系統ごとの熟練度（これまでに得た合計）と、覚えた秘計を持つ（どちらも増えるだけ）。
--   覚えた秘計は、記録の覚えた秘計に、熟練度が覚える値に達した秘計を合わせたもの（Jukurendo.learned）。
--   進行（ProgressService）とも特技（TokugiService）とも別の DataStore に保存する
-- - ステージが決着したら（StageService.finish が award を呼ぶ）、出撃して残っている人に、その人の撃破数・制圧数・救援数
--   （Player の Attribute の Gekihasu・Seiatsusu・Kyuensu）から系統ごとの熟練度を足してすぐ保存する（Jukurendo.gainOf）。
--   試験用ステージでも足す
-- - M1 から遊ぶ人の扱い。熟練度の記録を読めて、まだ M1 から遊ぶ人かを確かめておらず、進行も読めたら、
--   進行にクリア済みのステージがあれば M1 の8種を覚えた秘計に加える（Jukurendo.m1ChangeOf）。
--   確かめたことは記録に残すので、二度は確かめない。どちらかを読めていなければ、読めたときか次に入ったときに確かめる
-- - 記録が変わるたびに（読み込み・熟練度・M1 の扱い・保存）、本人に JukurendoState を送り、changed で知らせる

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Hikei = require(ReplicatedStorage.Shared.Hikei)
local Jukurendo = require(ReplicatedStorage.Shared.Jukurendo)
local DebugCommand = require(script.Parent.Parent.DebugCommand)
local PlayerStore = require(script.Parent.Parent.PlayerStore)
local ProgressService = require(script.Parent.ProgressService)

local JukurendoService = {}

-- 決着したときに足した熟練度
export type Award = {
	-- 系統 ID から引く、足した熟練度（上がらなかった系統は 0）
	jukurendo: { [string]: number },
	-- 新しく覚えた秘計（設計の表の順）
	newlyLearned: { string },
}

local store: PlayerStore.Store<Jukurendo.Data, Jukurendo.Change> = PlayerStore.new({
	name = "Jukurendo",
	new = Jukurendo.new,
	normalize = Jukurendo.normalize,
	apply = function(data: Jukurendo.Data, change: Jukurendo.Change): Jukurendo.Data
		return Jukurendo.apply(data, change)
	end,
})

-- 記録が変わったとき（読み込み・熟練度・M1 の扱い・保存・窓口で消したとき）に、プレイヤーで発火する
JukurendoService.changed = store.changed

-- このサーバーで M1 から遊ぶ人かを確かめ終えた（確かめなくてよくなった）プレイヤー
local m1Done: { [Player]: boolean } = {}
local stateRemote: RemoteEvent

-- 熟練度の記録を読み終えたか（読み込めなかったときも true）。読み終える前は秘計を選べない
function JukurendoService.isReady(player: Player): boolean
	return store.isReady(player)
end

-- 今の記録。記録を読む前は、読む前に受けた変更だけの記録
function JukurendoService.getData(player: Player): Jukurendo.Data
	return store.get(player)
end

-- 覚えた秘計（設計の表の順）。記録を読む前は最初から覚えている秘計
function JukurendoService.getLearned(player: Player): { string }
	return Jukurendo.learned(store.get(player))
end

-- 1回のステージの戦い方の数（Player の Attribute。出撃するときに PlayerService が 0 に戻す）
local function countsOf(player: Player): Jukurendo.Counts
	local function attributeOf(name: string): number
		local value = player:GetAttribute(name)
		return if type(value) == "number" then value else 0
	end
	return {
		gekihasu = attributeOf("Gekihasu"),
		seiatsusu = attributeOf("Seiatsusu"),
		kyuensu = attributeOf("Kyuensu"),
	}
end

-- 記録に熟練度を足してすぐ保存し、新しく覚えた秘計を返す。入室していなければ何もせず false
local function addJukurendo(player: Player, gains: { [string]: number }): (boolean, { string })
	local before = Jukurendo.learned(store.get(player))
	if not store.change(player, { jukurendo = gains }) then
		return false, {}
	end
	local newly = {}
	for _, id in Jukurendo.learned(store.get(player)) do
		if not table.find(before, id) then
			table.insert(newly, id)
		end
	end
	return true, newly
end

-- 決着したときに、players（出撃して残っている人）へ、その人の撃破数・制圧数・救援数から系統ごとの熟練度を足して
-- すぐ保存する（Jukurendo.gainOf）。プレイヤーごとに足した熟練度と新しく覚えた秘計を返す
function JukurendoService.award(players: { Player }): { [Player]: Award }
	local result: { [Player]: Award } = {}
	for _, player in players do
		local gains = Jukurendo.gainOf(countsOf(player))
		local gained = false
		for _, gain in gains do
			if gain > 0 then
				gained = true
			end
		end
		local newly: { string } = {}
		if gained then
			local _, learnedNow = addJukurendo(player, gains)
			newly = learnedNow
		end
		result[player] = { jukurendo = gains, newlyLearned = newly }
	end
	return result
end

-- M1 から遊ぶ人かを確かめる。熟練度の記録と進行の両方を読めていて、まだ確かめていなければ、
-- 進行にクリア済みのステージがあれば M1 の8種を覚えた秘計に加え、確かめたことを記録に残す
local function checkM1(player: Player)
	if m1Done[player] or not player.Parent or not store.isLoaded(player) then
		return
	end
	if store.get(player).m1Checked then
		m1Done[player] = true
		return
	end
	if not ProgressService.isLoaded(player) then
		return
	end
	m1Done[player] = true
	local cleared = ProgressService.getCleared(player)
	store.change(player, Jukurendo.m1ChangeOf(cleared))
	if #cleared > 0 then
		local stages = table.concat(cleared, "、")
		print(
			`[Jukurendo] {player.Name} を M1 から遊んでいる人として、M1 の秘計8種を覚えた扱いにした（クリア済みのステージ {stages}）`
		)
	end
end

-- 本人に今の記録を送る
local function sendState(player: Player)
	if not player.Parent then
		return
	end
	local state: Jukurendo.State = { loaded = store.isLoaded(player), data = store.get(player) }
	stateRemote:FireClient(player, state)
end

local function onStoreChanged(player: Player)
	sendState(player)
	checkM1(player)
end

-- 窓口の系統の引数を読む
local function keitoOf(value: unknown): string
	if type(value) ~= "string" or not table.find(Jukurendo.keitoList, value :: Jukurendo.Keito) then
		error(`系統 ID は {table.concat(Jukurendo.keitoList, "、")} のどれか（{tostring(value)}）`, 0)
	end
	return value :: string
end

local function namesOf(ids: { string }): string
	if #ids == 0 then
		return "なし"
	end
	local names = {}
	for _, id in ids do
		local definition = Hikei.get(id)
		table.insert(names, if definition then definition.displayName else id)
	end
	return table.concat(names, "、")
end

-- 窓口の DumpJukurendo の中身
local function describe(player: Player): { [string]: any }
	local data = store.get(player)
	local keito: { [string]: any } = {}
	for _, id in Jukurendo.keitoList do
		local nextId, threshold = Jukurendo.nextOf(data, id)
		keito[id] = {
			jukurendo = Jukurendo.jukurendoOf(data, id),
			nextHikei = nextId,
			nextJukurendo = threshold,
		}
	end
	local info = store.describe(player)
	info.m1Checked = data.m1Checked
	info.keito = keito
	info.hikei = data.hikei
	info.learned = Jukurendo.learned(data)
	info.counts = countsOf(player)
	info.progress = {
		loaded = ProgressService.isLoaded(player),
		cleared = ProgressService.getCleared(player),
	}
	return info
end

local function registerDebugCommands()
	DebugCommand.register(
		"AddJukurendo",
		"<プレイヤー名> <系統 ID> <熟練度>",
		`系統の熟練度を足してすぐ保存する（系統 ID は {table.concat(Jukurendo.keitoList, "・")}）`,
		function(name, keitoValue, value)
			local player = DebugCommand.findPlayer(name)
			local keito = keitoOf(keitoValue)
			local amount = math.floor(DebugCommand.toNumber(value, "熟練度"))
			if amount < 1 then
				error(`熟練度は1以上で指定する（{tostring(value)}）`, 0)
			end
			local ok, newly = addJukurendo(player, { [keito] = amount })
			if not ok then
				return `{player.Name} の熟練度の記録がまだ無い（読み込みの前）`
			end
			local total = Jukurendo.jukurendoOf(store.get(player), keito)
			local learned = namesOf(newly)
			return `{player.Name} の{Jukurendo.names[keito]}（{keito}）の熟練度を {amount} 足した（熟練度 {total}、新しく覚えた秘計 {learned}）`
		end
	)
	DebugCommand.register(
		"DumpJukurendo",
		"<プレイヤー名>",
		"プレイヤーの熟練度の記録（系統ごとの熟練度と次に覚える秘計・覚えた秘計・M1 から遊ぶ人かを確かめたか）と保存先、今のステージの撃破数・制圧数・救援数、進行のクリア済みのステージを JSON で返す",
		function(name)
			local player = DebugCommand.findPlayer(name)
			return HttpService:JSONEncode(describe(player))
		end
	)
	DebugCommand.register(
		"ResetJukurendo",
		"<プレイヤー名> [m1]",
		"保存済みの記録ごと、プレイヤーの熟練度と覚えた秘計を消す（確認のやり直し用）。既定は新規の人の扱い（最初から覚えている秘計だけ）にする。m1 を渡すと記録の無い人の扱いにし、入室したときと同じく M1 から遊ぶ人かを確かめ直す（進行にクリア済みのステージがあれば M1 の8種を覚える）",
		function(name, mode)
			local player = DebugCommand.findPlayer(name)
			if mode ~= nil and mode ~= "m1" then
				error(`2つ目の引数は m1 か省く（{tostring(mode)}）`, 0)
			end
			-- 消したときの changed で M1 から遊ぶ人かを確かめないようにする
			local done = m1Done[player]
			m1Done[player] = true
			if not store.reset(player) then
				m1Done[player] = done
				return `{player.Name} の熟練度の記録を消せなかった（読み込みの前か、DataStore の削除に失敗した）`
			end
			local kind = store.describe(player).store
			if mode == "m1" then
				m1Done[player] = nil
				checkM1(player)
				local data = store.get(player)
				if not data.m1Checked then
					return `{player.Name} の熟練度の記録を消した（保存先 {kind}）。進行を読めていないので、M1 から遊ぶ人かはまだ確かめていない`
				end
				local cleared = #ProgressService.getCleared(player)
				local learned = namesOf(Jukurendo.learned(data))
				return `{player.Name} の熟練度の記録を消し、M1 から遊ぶ人かを確かめ直した（保存先 {kind}、クリア済みのステージ {cleared} 個、覚えた秘計 {learned}）`
			end
			store.change(player, { m1Checked = true })
			local learned = namesOf(Jukurendo.learned(store.get(player)))
			return `{player.Name} の熟練度の記録を消し、新規の人の扱いにした（保存先 {kind}、覚えた秘計 {learned}）`
		end
	)
end

function JukurendoService.start()
	stateRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("JukurendoState") :: RemoteEvent
	store.changed:Connect(onStoreChanged)
	-- 進行を読み終えたとき（M1 から遊ぶ人かを確かめられるようになる）
	ProgressService.changed:Connect(checkM1)
	Players.PlayerRemoving:Connect(function(player)
		m1Done[player] = nil
	end)
	registerDebugCommands()
	store.start()
end

return JukurendoService
