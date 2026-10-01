--!strict
-- 出撃前の選択（ステージ・キャラクター・秘計）の状態を持ち、Remote の選択を受け付ける。
-- 受け付けるかは ReplicatedStorage.Shared.SelectionRules が決め、拒否したら SelectionRejected で本人に理由を返す。
-- 選択の状態は PartyService.setExtraProvider で PartyState に載せ、変わるたびに全員へ送り直す。
--
-- - ステージはリーダーだけが、ロビーのフェーズで、リーダーの開放済みのステージから選べる
-- - リーダーが代わったときと、リーダーの開放済みが変わったときに確かめ直し、開放していないステージの選択は外す

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Party = require(ReplicatedStorage.Shared.Party)
local RemoteSchema = require(ReplicatedStorage.Shared.RemoteSchema)
local SelectionRules = require(ReplicatedStorage.Shared.SelectionRules)
local DebugCommand = require(script.Parent.Parent.DebugCommand)
local PartyService = require(script.Parent.PartyService)
local ProgressService = require(script.Parent.ProgressService)

local SelectionService = {}

-- リーダーが選んでいるステージ
local selectedStage: string? = nil
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

-- ステージを選ぶ。受け付けたら nil、受け付けなければ拒否の理由を返す
function SelectionService.selectStage(player: Player, stageId: string): SelectionRules.Reject?
	local reject = SelectionRules.checkStage(requesterOf(player), stageId, leaderUnlocked())
	if reject then
		return reject
	end
	if selectedStage ~= stageId then
		selectedStage = stageId
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

local function onPartyChanged()
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
end

function SelectionService.start()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	rejectedRemote = remotes:WaitForChild("SelectionRejected") :: RemoteEvent
	local selectStage = remotes:WaitForChild("SelectStage") :: RemoteEvent
	selectStage.OnServerEvent:Connect(onSelectStage)

	PartyService.setExtraProvider(function(): Party.Extra
		return {
			stage = selectedStage,
			unlockedStages = leaderUnlocked(),
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
