--!strict
-- 出撃前の選択（ステージ・キャラクター・秘計）の状態を持ち、Remote の選択を受け付ける。
-- 受け付けるかは ReplicatedStorage.Shared.SelectionRules が決め、拒否したら SelectionRejected で本人に理由を返す。
-- 選択の状態は PartyService.setExtraProvider で PartyState に載せ、変わるたびに全員へ送り直す。
--
-- - ステージはリーダーだけが、ロビーのフェーズで、リーダーの開放済みのステージから選べる
-- - リーダーが代わったときと、リーダーの開放済みが変わったときに確かめ直し、開放していないステージの選択は外す
-- - キャラクターはステージを選んだ後に、ストーリーのクランの操作キャラクターから、他のメンバーと重ならずに選べる
-- - ステージが変わったら、新しいステージで選べなくなったキャラクターの選択を外す
-- - 抜けた人の選択は外し、ほかの人が選べるようにする

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Party = require(ReplicatedStorage.Shared.Party)
local RemoteSchema = require(ReplicatedStorage.Shared.RemoteSchema)
local SelectionRules = require(ReplicatedStorage.Shared.SelectionRules)
local Stages = require(ReplicatedStorage.Shared.Stages)
local DebugCommand = require(script.Parent.Parent.DebugCommand)
local PartyService = require(script.Parent.PartyService)
local ProgressService = require(script.Parent.ProgressService)

local SelectionService = {}

-- リーダーが選んでいるステージ
local selectedStage: string? = nil
-- メンバーの UserId から引く、選んだキャラクター
local characters: { [number]: string } = {}
-- 最後に確かめたときのリーダー
local lastLeader: Player? = nil
local rejectedRemote: RemoteEvent

local function requesterOf(player: Player): SelectionRules.Requester
	return {
		phase = PartyService.getPhase(),
		isLeader = PartyService.getLeader() == player,
		waiting = PartyService.isWaiting(player),
	}
end

-- リーダーの開放済みのステージ。誰もいなければ空
local function leaderUnlocked(): { string }
	local leader = PartyService.getLeader()
	return if leader then ProgressService.getUnlocked(leader) else {}
end

-- 選んでいるステージ。選んでいなければ nil
function SelectionService.getStage(): string?
	return selectedStage
end

-- 選んだキャラクター。選んでいなければ nil
function SelectionService.getCharacter(player: Player): string?
	return characters[player.UserId]
end

-- 新しいステージで選べなくなったキャラクターの選択を外す
local function releaseInvalidCharacters()
	local stage = if selectedStage then Stages.get(selectedStage) else nil
	if not stage then
		return
	end
	for userId, characterId in characters do
		if not SelectionRules.keepsCharacter(characterId, stage) then
			characters[userId] = nil
		end
	end
end

-- ステージを選ぶ。受け付けたら nil、受け付けなければ拒否の理由を返す
function SelectionService.selectStage(player: Player, stageId: string): SelectionRules.Reject?
	local reject = SelectionRules.checkStage(requesterOf(player), stageId, leaderUnlocked())
	if reject then
		return reject
	end
	if selectedStage ~= stageId then
		selectedStage = stageId
		releaseInvalidCharacters()
		PartyService.refresh()
	end
	return nil
end

-- キャラクターを選ぶ。受け付けたら nil、受け付けなければ拒否の理由を返す。前に選んでいたキャラクターは外れる
function SelectionService.selectCharacter(player: Player, characterId: string): SelectionRules.Reject?
	local takenByOthers = {}
	for userId, id in characters do
		if userId ~= player.UserId then
			table.insert(takenByOthers, id)
		end
	end
	local stage = if selectedStage then Stages.get(selectedStage) else nil
	local reject = SelectionRules.checkCharacter(requesterOf(player), characterId, stage, takenByOthers)
	if reject then
		return reject
	end
	if characters[player.UserId] ~= characterId then
		characters[player.UserId] = characterId
		PartyService.refresh()
	end
	return nil
end

-- 今のリーダーが開放していないステージの選択を外し、全員に送り直す
local function recheckStage()
	if not SelectionRules.keepsStage(selectedStage, leaderUnlocked()) then
		selectedStage = nil
	end
	PartyService.refresh()
end

-- 抜けた人の選択を外す
local function releaseLeftMembers()
	for userId in characters do
		if not PartyService.isMember(userId) then
			characters[userId] = nil
		end
	end
end

-- 入退室とフェーズの変化のたびに呼ぶ。抜けた人の選択は PartyState に載らないので、送り直すのはリーダーが代わったときだけ
local function onPartyChanged()
	releaseLeftMembers()
	local leader = PartyService.getLeader()
	if leader ~= lastLeader then
		lastLeader = leader
		recheckStage()
	end
end

local function reject(player: Player, reason: SelectionRules.Reject)
	rejectedRemote:FireClient(player, reason)
end

local function onSelectStage(player: Player, stageId: unknown)
	if not RemoteSchema.validate.SelectStage(stageId) then
		return
	end
	local reason = SelectionService.selectStage(player, stageId :: string)
	if reason then
		reject(player, reason)
	end
end

local function onSelectCharacter(player: Player, characterId: unknown)
	if not RemoteSchema.validate.SelectCharacter(characterId) then
		return
	end
	local reason = SelectionService.selectCharacter(player, characterId :: string)
	if reason then
		reject(player, reason)
	end
end

local function registerDebugCommands()
	DebugCommand.register(
		"SelectStage",
		"<プレイヤー名> <ステージ ID>",
		"Remotes.SelectStage と同じ処理でステージを選ぶ",
		function(name, stageId)
			local player = DebugCommand.findPlayer(name)
			if not RemoteSchema.validate.SelectStage(stageId) then
				error(`ステージ ID の形が正しくない（{tostring(stageId)}）`, 0)
			end
			local reason = SelectionService.selectStage(player, stageId)
			if reason then
				return `{player.Name} の {stageId} の選択を拒否した（{reason}）`
			end
			return `{player.Name} が {stageId} を選んだ`
		end
	)
	DebugCommand.register(
		"SelectCharacter",
		"<プレイヤー名> <キャラクター ID>",
		"Remotes.SelectCharacter と同じ処理でキャラクターを選ぶ",
		function(name, characterId)
			local player = DebugCommand.findPlayer(name)
			if not RemoteSchema.validate.SelectCharacter(characterId) then
				error(`キャラクター ID の形が正しくない（{tostring(characterId)}）`, 0)
			end
			local reason = SelectionService.selectCharacter(player, characterId)
			if reason then
				return `{player.Name} の {characterId} の選択を拒否した（{reason}）`
			end
			return `{player.Name} が {characterId} を選んだ`
		end
	)
end

function SelectionService.start()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	rejectedRemote = remotes:WaitForChild("SelectionRejected") :: RemoteEvent
	local selectStage = remotes:WaitForChild("SelectStage") :: RemoteEvent
	selectStage.OnServerEvent:Connect(onSelectStage)
	local selectCharacter = remotes:WaitForChild("SelectCharacter") :: RemoteEvent
	selectCharacter.OnServerEvent:Connect(onSelectCharacter)

	PartyService.setExtraProvider(function(): Party.Extra
		return {
			stage = selectedStage,
			unlockedStages = leaderUnlocked(),
			characterOf = function(userId: number): string?
				return characters[userId]
			end,
		}
	end)
	PartyService.changed:Connect(onPartyChanged)
	-- リーダーの進行を読み終えたときや、クリアで開放済みが増えたとき
	ProgressService.changed:Connect(function(player: Player)
		if player == PartyService.getLeader() then
			recheckStage()
		end
	end)
	registerDebugCommands()
	onPartyChanged()
end

return SelectionService
