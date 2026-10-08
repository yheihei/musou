--!strict
-- 特技ツリーによる成長。キャラクターごとの巻物と覚えた特技をプレイヤーごとに保存し（PlayerStore。DataStore の名前は Tokugi）、
-- 覚える要求（Remotes.LearnTokugi）を受け付け、出撃したときに覚えた特技の補正を固定して能力値に足す。
-- 計算は ReplicatedStorage.Shared.Tokugi、ツリーの定義と値は Config.luau の Tokugi 節にある。
--
-- - 記録はキャラクターごとに、これまでに得た巻物の合計と覚えた特技を持つ（どちらも増えるだけ）。
--   使える巻物は、合計から覚えた特技の巻物の数を引いて求める。進行（ProgressService）とは別の DataStore に保存する
-- - 覚えられるのは、ロビーのフェーズで、記録を読めた後、ツリーにあり、まだ覚えておらず、前提をすべて覚えていて、
--   巻物が足りる特技だけ（Tokugi.checkLearn）。受け付けなければ SelectionRejected で本人に理由を返す。覚えたらすぐ保存する
-- - 記録が変わるたびに（読み込み・巻物・習得・保存）、本人に TokugiState を送る
-- - 出撃するときに（StageService.shutsugeki が出現し直させる前に lock を呼ぶ）、使うキャラクターの覚えた特技の補正を
--   作って固定し、PlayerService.addModifierProvider で能力値に足す。体力の最大は出現したときに当てるので、出現し直す前に固定する。
--   固定したキャラクターと今のキャラクターが違うとき（窓口の SetCharacter で変えたとき）は足さない
-- - 固定は、ロビーに戻ったとき（StageService が unlockAll を呼ぶ）と退室時に外す。
--   覚えた特技が効くのは次の出撃から（特技はロビーでしか覚えられないが、固定した補正は後から覚えても変えない）
-- - ステージが決着したら（StageService.finish が awardMakimono を呼ぶ）、出撃して残っている人に、そのとき使っている
--   キャラクターの巻物を渡してすぐ保存する。数は撃破数に応じた数と、勝ちなら上乗せ（Tokugi.makimonoFor）。試験用ステージでも渡す

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local RemoteSchema = require(ReplicatedStorage.Shared.RemoteSchema)
local SelectionRules = require(ReplicatedStorage.Shared.SelectionRules)
local Stats = require(ReplicatedStorage.Shared.Stats)
local Tokugi = require(ReplicatedStorage.Shared.Tokugi)
local DebugCommand = require(script.Parent.Parent.DebugCommand)
local PlayerStore = require(script.Parent.Parent.PlayerStore)
local PartyService = require(script.Parent.PartyService)
local PlayerService = require(script.Parent.PlayerService)
local SelectionService = require(script.Parent.SelectionService)

local TokugiService = {}

-- 出撃したときに固定した特技の補正
export type Lock = {
	characterId: string,
	modifiers: { Stats.Modifier },
}

-- 決着したときに渡した巻物
export type Award = {
	characterId: string,
	makimono: number,
}

local store: PlayerStore.Store<Tokugi.Data, Tokugi.Change> = PlayerStore.new({
	name = "Tokugi",
	new = Tokugi.new,
	normalize = Tokugi.normalize,
	apply = Tokugi.apply,
})

-- プレイヤーから引く、出撃したときに固定した特技の補正
local locks: { [Player]: Lock } = {}
local stateRemote: RemoteEvent
local rejectedRemote: RemoteEvent

-- 今の記録。記録を読む前は、読む前に受けた変更だけの記録
function TokugiService.getData(player: Player): Tokugi.Data
	return store.get(player)
end

-- 出撃したときに固定した特技の補正。固定していなければ nil
function TokugiService.getLock(player: Player): Lock?
	return locks[player]
end

-- 特技ツリーの画面に出すキャラクター（選んでいるキャラクター、無ければ今のキャラクター）。窓口でキャラクターを省いたときに使う
function TokugiService.shownCharacterOf(player: Player): string
	return Tokugi.shownCharacter(SelectionService.getCharacter(player), PlayerService.getCharacterId(player))
end

local function requesterOf(player: Player): SelectionRules.Requester
	return {
		phase = PartyService.getPhase(),
		isLeader = PartyService.getLeader() == player,
		waiting = PartyService.isWaiting(player),
	}
end

-- 特技を覚える。受け付けたら nil、受け付けなければ拒否の理由を返す。覚えたらすぐ保存する
function TokugiService.learn(player: Player, characterId: string, tokugiId: string): RemoteSchema.RejectReason?
	local reject =
		Tokugi.checkLearn(requesterOf(player), store.isLoaded(player), store.get(player), characterId, tokugiId)
	if reject then
		return reject
	end
	store.change(player, { character = characterId, tokugi = tokugiId })
	return nil
end

-- キャラクターの巻物を amount 本足してすぐ保存する（窓口の確認用）。入室していなければ false
function TokugiService.addMakimono(player: Player, characterId: string, amount: number): boolean
	return store.change(player, { character = characterId, makimono = amount })
end

-- 決着したときに、players（出撃して残っている人）へ、そのとき使っているキャラクターの巻物を渡してすぐ保存する。
-- 数は撃破数に応じた数と、勝ちなら上乗せ（Tokugi.makimonoFor）。プレイヤーごとに渡したキャラクターと数を返す
function TokugiService.awardMakimono(players: { Player }, victory: boolean): { [Player]: Award }
	local result: { [Player]: Award } = {}
	for _, player in players do
		local characterId = PlayerService.getCharacterId(player)
		local gekihasu = player:GetAttribute("Gekihasu")
		local makimono = Tokugi.makimonoFor(if type(gekihasu) == "number" then gekihasu else 0, victory)
		if makimono > 0 then
			store.change(player, { character = characterId, makimono = makimono })
		end
		result[player] = { characterId = characterId, makimono = makimono }
	end
	return result
end

-- 出撃するときに、characterId の覚えた特技の補正を作って固定する。ロビーに戻るまで（unlockAll）変えない。
-- 体力の最大は出現したときに当てるので、StageService.shutsugeki が出現し直させる前に呼ぶ
function TokugiService.lock(player: Player, characterId: string)
	local record = Tokugi.recordOf(store.get(player), characterId)
	locks[player] = {
		characterId = characterId,
		modifiers = Tokugi.modifiersOf(record, Tokugi.treeOf(characterId)),
	}
end

-- 全員の固定を外す。ロビーに戻ったときに StageService が呼ぶ
function TokugiService.unlockAll()
	table.clear(locks)
end

-- 本人に今の記録を送る
local function sendState(player: Player)
	if not player.Parent then
		return
	end
	local state: Tokugi.State = { loaded = store.isLoaded(player), data = store.get(player) }
	stateRemote:FireClient(player, state)
end

local function onLearnTokugi(player: Player, characterId: unknown, tokugiId: unknown)
	if not RemoteSchema.validate.LearnTokugi(characterId, tokugiId) then
		return
	end
	local reason = TokugiService.learn(player, characterId :: string, tokugiId :: string)
	if reason then
		rejectedRemote:FireClient(player, reason)
	end
end

-- 窓口のキャラクターの引数を読む。省くと特技ツリーの画面に出すキャラクター
local function characterIdOf(player: Player, value: unknown): string
	if value == nil then
		return TokugiService.shownCharacterOf(player)
	end
	if type(value) ~= "string" or #Tokugi.treeOf(value) == 0 then
		local ids = {}
		for id in Config.Tokugi.Trees do
			table.insert(ids, id)
		end
		table.sort(ids)
		error(`キャラクター ID は {table.concat(ids, "、")} のどれか（{tostring(value)}）`, 0)
	end
	return value :: string
end

-- 窓口の DumpTokugi の中身。記録のあるキャラクターごとに、得た巻物の合計・使える巻物・覚えた特技を出す
local function describe(player: Player): { [string]: any }
	local data = store.get(player)
	local characters: { [string]: any } = {}
	for characterId, record in data.characters do
		characters[characterId] = {
			makimono = record.makimono,
			available = Tokugi.available(record, Tokugi.treeOf(characterId)),
			tokugi = record.tokugi,
		}
	end
	local info = store.describe(player)
	info.shownCharacter = TokugiService.shownCharacterOf(player)
	info.characters = characters
	info.lock = locks[player]
	return info
end

local function registerDebugCommands()
	DebugCommand.register(
		"AddMakimono",
		"<プレイヤー名> <数> [キャラクター ID]",
		"キャラクターの巻物を足してすぐ保存する。キャラクターを省くと、特技ツリーの画面に出すキャラクター（選んでいるキャラクター、無ければ今のキャラクター）",
		function(name, value, characterValue)
			local player = DebugCommand.findPlayer(name)
			local amount = math.floor(DebugCommand.toNumber(value, "数"))
			if amount < 1 then
				error(`数は1以上で指定する（{tostring(value)}）`, 0)
			end
			local characterId = characterIdOf(player, characterValue)
			if not TokugiService.addMakimono(player, characterId, amount) then
				return `{player.Name} の特技の記録がまだ無い（読み込みの前）`
			end
			local record = Tokugi.recordOf(store.get(player), characterId)
			local available = Tokugi.available(record, Tokugi.treeOf(characterId))
			return `{player.Name} の {characterId} の巻物を {amount} 本足した（使える巻物 {available} 本、得た巻物の合計 {record.makimono} 本）`
		end
	)
	DebugCommand.register(
		"LearnTokugi",
		"<プレイヤー名> <キャラクター ID> <特技 ID>",
		"Remotes.LearnTokugi と同じ処理で特技を覚える",
		function(name, characterId, tokugiId)
			local player = DebugCommand.findPlayer(name)
			if not RemoteSchema.validate.LearnTokugi(characterId, tokugiId) then
				local given = `{tostring(characterId)}、{tostring(tokugiId)}`
				error(`キャラクター ID か特技 ID の形が正しくない（{given}）`, 0)
			end
			local reason = TokugiService.learn(player, characterId, tokugiId)
			if reason then
				return `{player.Name} の {characterId} の {tokugiId} の習得を拒否した（{reason}）`
			end
			local record = Tokugi.recordOf(store.get(player), characterId)
			local available = Tokugi.available(record, Tokugi.treeOf(characterId))
			return `{player.Name} が {characterId} の {Tokugi.nameOf(tokugiId)}（{tokugiId}）を覚えた（使える巻物 {available} 本）`
		end
	)
	DebugCommand.register(
		"DumpTokugi",
		"<プレイヤー名>",
		"プレイヤーの特技の記録（キャラクターごとの得た巻物の合計・使える巻物・覚えた特技）と保存先、出撃したときに固定した補正を JSON で返す",
		function(name)
			local player = DebugCommand.findPlayer(name)
			return HttpService:JSONEncode(describe(player))
		end
	)
	DebugCommand.register(
		"ResetTokugi",
		"<プレイヤー名>",
		"保存済みの記録ごと、プレイヤーの特技の記録（巻物と覚えた特技）を消す（確認のやり直し用）",
		function(name)
			local player = DebugCommand.findPlayer(name)
			if not store.reset(player) then
				return `{player.Name} の特技の記録を消せなかった（読み込みの前か、DataStore の削除に失敗した）`
			end
			return `{player.Name} の特技の記録を消した（保存先 {store.describe(player).store}）`
		end
	)
end

function TokugiService.start()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	stateRemote = remotes:WaitForChild("TokugiState") :: RemoteEvent
	rejectedRemote = remotes:WaitForChild("SelectionRejected") :: RemoteEvent
	local learnRemote = remotes:WaitForChild("LearnTokugi") :: RemoteEvent
	learnRemote.OnServerEvent:Connect(onLearnTokugi)
	store.changed:Connect(sendState)
	PlayerService.addModifierProvider(function(player: Player): { Stats.Modifier }
		local lock = locks[player]
		if lock and PlayerService.getCharacterId(player) == lock.characterId then
			return lock.modifiers
		end
		return {}
	end)
	Players.PlayerRemoving:Connect(function(player)
		locks[player] = nil
	end)
	registerDebugCommands()
	store.start()
end

return TokugiService
