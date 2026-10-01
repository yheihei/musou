--!strict
-- パーティーとリーダーの管理。入退室をパーティーに反映し、変化のたびに全員へ、
-- 入室した人には入室直後に PartyState を送る。計算は ReplicatedStorage.Shared.Party が持つ。
-- フェーズはステージの進行の処理が setPhase で変える。
-- 選択中のステージやキャラクターなど、ほかのサービスが持つ状態は setExtraProvider で PartyState に載せる。

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

-- パーティーが変わったとき（入退室とフェーズの変化）に発火する
PartyService.changed = changed.Event

-- PartyState に載せる状態（ステージ・開放済みのステージ・キャラクター・秘計）を返す関数を登録する
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

local function registerDebugCommands()
	DebugCommand.register("DumpParty", "", "パーティーの状態を JSON で返す", function()
		return game:GetService("HttpService"):JSONEncode(PartyService.getState())
	end)
	DebugCommand.register(
		"SetPhase",
		"<" .. table.concat(RemoteSchema.phases, "|") .. ">",
		"フェーズを変える（ステージの進行の処理ができるまでの確認用）",
		function(phase)
			if not table.find(RemoteSchema.phases, phase) then
				error(
					`フェーズは {table.concat(RemoteSchema.phases, "、")} のどれか（{tostring(phase)}）`,
					0
				)
			end
			PartyService.setPhase(phase)
			return `フェーズを {phase} にした`
		end
	)
end

function PartyService.start()
	partyStateRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PartyState") :: RemoteEvent
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	registerDebugCommands()
end

return PartyService
