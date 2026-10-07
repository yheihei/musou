--!strict
-- パーティーとリーダーの管理。入退室をパーティーに反映し、変化のたびに全員へ、
-- 入室した人には入室直後に PartyState を送る。計算は ReplicatedStorage.Shared.Party が持つ。
-- フェーズはステージの進行（StageService）が setPhase で変える。
-- 選択中のステージやキャラクターなど、ほかのサービスが持つ状態は setExtraProvider で PartyState に載せる。
-- プライベートサーバーでは、持ち主（game.PrivateServerOwnerId）がパーティーにいて待機中でなければ持ち主をリーダーにする。
-- PrivateServerOwnerId が 0 のサーバー（公開サーバーと予約サーバー）には持ち主がいない。
-- Studio ではプライベートサーバーを立てられないので、窓口の SetPrivateServerOwner で持ち主を上書きして確かめる

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Party = require(ReplicatedStorage.Shared.Party)
local RemoteSchema = require(ReplicatedStorage.Shared.RemoteSchema)
local DebugCommand = require(script.Parent.Parent.DebugCommand)

local PartyService = {}

local party = Party.new()
local partyStateRemote: RemoteEvent
local changed = Instance.new("BindableEvent")
-- PartyState に載せる、ほかのサービスが持つ状態を返す関数
local extraProvider: (() -> Party.Extra)? = nil
-- プライベートサーバーの持ち主の上書き（窓口の SetPrivateServerOwner。確認用）。nil なら game.PrivateServerOwnerId を使う
local ownerOverride: number? = nil

-- パーティーが変わったとき（入退室とフェーズの変化）に発火する
PartyService.changed = changed.Event

-- PartyState に載せる状態（ストーリー・ステージ・開放済みのステージ・キャラクター・秘計）を返す関数を登録する
function PartyService.setExtraProvider(provider: () -> Party.Extra)
	extraProvider = provider
end

function PartyService.getState(): RemoteSchema.PartyState
	return Party.toState(party, if extraProvider then extraProvider() else nil)
end

function PartyService.getPhase(): Party.Phase
	return party.phase
end

-- リーダーの Player。誰もいなければ nil
function PartyService.getLeader(): Player?
	local leader = Party.leader(party)
	return if leader then Players:GetPlayerByUserId(leader.userId) else nil
end

-- パーティーのメンバーか。抜けた後は false
function PartyService.isMember(userId: number): boolean
	return Party.get(party, userId) ~= nil
end

-- 出撃するメンバー（待機中でない人）の Player を入った順に返す
function PartyService.getActivePlayers(): { Player }
	local result = {}
	for _, member in Party.activeMembers(party) do
		local player = Players:GetPlayerByUserId(member.userId)
		if player then
			table.insert(result, player)
		end
	end
	return result
end

-- 出撃中に入ってロビーで待っているか
function PartyService.isWaiting(player: Player): boolean
	local member = Party.get(party, player.UserId)
	return member ~= nil and member.waiting
end

-- 全員に今の PartyState を送り直す。ほかのサービスが PartyState に載せる状態を変えたときに呼ぶ
function PartyService.refresh()
	partyStateRemote:FireAllClients(PartyService.getState())
end

local function broadcast()
	PartyService.refresh()
	changed:Fire()
end

-- フェーズを変えて全員に知らせる。ロビーに戻すと待機中の人が合流する
function PartyService.setPhase(phase: Party.Phase)
	Party.setPhase(party, phase)
	broadcast()
end

-- リーダーの決まりに使うプライベートサーバーの持ち主の UserId。持ち主がいなければ nil
local function privateServerOwnerId(): number?
	local userId = if ownerOverride ~= nil then ownerOverride else game.PrivateServerOwnerId
	return if userId ~= 0 then userId else nil
end

local function onPlayerAdded(player: Player)
	if not Party.join(party, player.UserId, player.Name) then
		player:Kick(`このサーバーは満員です（{Config.Party.MaxMembers}人まで）`)
		return
	end
	broadcast()
end

local function onPlayerRemoving(player: Player)
	if Party.leave(party, player.UserId) then
		broadcast()
	end
end

-- 窓口の引数を持ち主の UserId にする。いるプレイヤーの名前を先に探し、いなければ整数を UserId として読む
local function ownerIdOf(value: unknown): number
	if type(value) == "string" then
		local player = Players:FindFirstChild(value)
		if player and player:IsA("Player") then
			return player.UserId
		end
	end
	local userId = tonumber(value)
	if userId and userId == math.floor(userId) then
		return userId
	end
	-- いるプレイヤーの名前を添えてエラーにする
	return DebugCommand.findPlayer(value).UserId
end

-- 窓口の返す文に使う、持ち主の様子
local function describeOwner(): string
	local userId = party.privateServerOwnerId
	if not userId then
		return "なし"
	end
	local member = Party.get(party, userId)
	if not member then
		return `UserId {userId}（パーティーにいない）`
	end
	return `{member.name}（UserId {userId}{if member.waiting then "、待機中" else ""}）`
end

local function registerDebugCommands()
	DebugCommand.register(
		"DumpParty",
		"",
		"パーティーの状態を JSON で返す。privateServer に、リーダーの決まりに使うプライベートサーバーの持ち主（ownerId）、窓口で上書きしているか（override）、game.PrivateServerOwnerId を載せる",
		function()
			local dump: { [string]: any } = PartyService.getState() :: any
			dump.privateServer = {
				ownerId = party.privateServerOwnerId,
				override = ownerOverride ~= nil,
				privateServerOwnerId = game.PrivateServerOwnerId,
			}
			return HttpService:JSONEncode(dump)
		end
	)
	DebugCommand.register(
		"SetPrivateServerOwner",
		"<プレイヤー名|UserId|なし>",
		"リーダーの決まりに使うプライベートサーバーの持ち主を上書きする。なし で上書きを外し、game.PrivateServerOwnerId に戻す（Studio では 0 なので持ち主なし。確認用）",
		function(value)
			ownerOverride = if value == "なし" then nil else ownerIdOf(value)
			Party.setPrivateServerOwner(party, privateServerOwnerId())
			broadcast()
			local leader = Party.leader(party)
			local leaderName = if leader then leader.name else "なし"
			if ownerOverride == nil then
				return `プライベートサーバーの持ち主の上書きを外した（持ち主 {describeOwner()}、リーダー {leaderName}）`
			end
			return `プライベートサーバーの持ち主を {describeOwner()} に上書きした（リーダー {leaderName}）`
		end
	)
end

function PartyService.start()
	partyStateRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PartyState") :: RemoteEvent
	Party.setPrivateServerOwner(party, privateServerOwnerId())
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	registerDebugCommands()
end

return PartyService
