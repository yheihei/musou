--!strict
-- 出撃前の選択（ストーリー・ステージ・キャラクター・秘計）の状態を持ち、Remote の選択を受け付ける。
-- 受け付けるかは ReplicatedStorage.Shared.SelectionRules が決め、拒否したら SelectionRejected で本人に理由を返す。
-- 選択の状態は PartyService.setExtraProvider で PartyState に載せ、変わるたびに全員へ送り直す。
--
-- - ストーリーはリーダーだけが、ロビーのフェーズで、リーダーが開放したステージのあるストーリーから選べる
-- - ステージはリーダーだけが、ロビーのフェーズで、リーダーの開放済みのステージから選べる
-- - ステージを選ぶと、ストーリーもそのステージのクランにする。選んでいるストーリーと別のストーリーのステージでも
--   拒否せず、ストーリーを切り替える（後から押した方を通す）
-- - 別のストーリーを選んだら、ステージの選択を外す
-- - リーダーが代わったときと、リーダーの開放済みが変わったときに確かめ直し、開放していないステージの選択と、
--   開放したステージの無いストーリーの選択を外す。進行を読み終える前の人がリーダーになったら
--   （プライベートサーバーの持ち主が入ったときなど）、読み終えてから確かめ直す
-- - キャラクターはステージを選んだ後に、ストーリーのクランの操作キャラクターから、他のメンバーと重ならずに選べる
-- - ストーリーかステージが変わったら、選べなくなったキャラクターの選択を外す
-- - 秘計は1枚ずつ選ぶか外し、本人が覚えた秘計（JukurendoService）から、持ち込みの上限まで、
--   他のメンバーと重ならずに選べる（先に選んだ人のもの）。熟練度の記録を読み終える前は選べない。
--   秘計の枚数は出撃の条件にしない
-- - 覚えた秘計の記録が変わったら（窓口で記録を消したときなど）、覚えていない秘計の選択を外す
-- - 抜けた人の選択は外し、ほかの人が選べるようにする
-- - リザルトからロビーへ戻ったら、StageService が clear でストーリー以外の選択を外す。
--   続けて同じストーリーを遊べるよう、ストーリーは残す
-- - リザルトからリトライでロビーへ戻ったら、選択は残し、StageService が revalidate で確かめ直す

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Party = require(ReplicatedStorage.Shared.Party)
local RemoteSchema = require(ReplicatedStorage.Shared.RemoteSchema)
local SelectionRules = require(ReplicatedStorage.Shared.SelectionRules)
local Stages = require(ReplicatedStorage.Shared.Stages)
local DebugCommand = require(script.Parent.Parent.DebugCommand)
local JukurendoService = require(script.Parent.JukurendoService)
local PartyService = require(script.Parent.PartyService)
local ProgressService = require(script.Parent.ProgressService)

local SelectionService = {}

-- リーダーが選んでいるストーリー
local selectedStory: Stages.ClanId? = nil
-- リーダーが選んでいるステージ。選んでいるときは、ストーリーもこのステージのクランにしている
local selectedStage: string? = nil
-- メンバーの UserId から引く、選んだキャラクター
local characters: { [number]: string } = {}
-- メンバーの UserId から引く、選んだ順の秘計
local hikei: { [number]: { string } } = {}
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

-- 選んでいるステージ（選んでいなければストーリー）で選べなくなったキャラクターの選択を外す
local function releaseInvalidCharacters()
	local stage = if selectedStage then Stages.get(selectedStage) else nil
	for userId, characterId in characters do
		if not SelectionRules.keepsCharacter(characterId, stage, selectedStory) then
			characters[userId] = nil
		end
	end
end

-- ストーリーを選ぶ。受け付けたら nil、受け付けなければ拒否の理由を返す。
-- 別のストーリーを選んだら、ステージの選択と、そのストーリーで選べないキャラクターの選択を外す
function SelectionService.selectStory(player: Player, clanId: string): SelectionRules.Reject?
	local reject = SelectionRules.checkStory(requesterOf(player), clanId, leaderUnlocked())
	if reject then
		return reject
	end
	if selectedStory ~= clanId then
		selectedStory = clanId :: Stages.ClanId
		local stage = if selectedStage then Stages.get(selectedStage) else nil
		if stage and stage.clan ~= clanId then
			selectedStage = nil
		end
		releaseInvalidCharacters()
		PartyService.refresh()
	end
	return nil
end

-- ステージを選ぶ。受け付けたら nil、受け付けなければ拒否の理由を返す。ストーリーもステージのクランにする
function SelectionService.selectStage(player: Player, stageId: string): SelectionRules.Reject?
	local reject = SelectionRules.checkStage(requesterOf(player), stageId, leaderUnlocked())
	if reject then
		return reject
	end
	local stage = Stages.get(stageId) :: Stages.Stage
	if selectedStage ~= stageId or selectedStory ~= stage.clan then
		selectedStage = stageId
		selectedStory = stage.clan
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

-- 選んだ順の秘計
function SelectionService.getHikei(player: Player): { string }
	return table.clone(hikei[player.UserId] or {})
end

-- 秘計を1枚選ぶ（selected が true）か外す（false）。受け付けたら nil、受け付けなければ拒否の理由を返す。
-- 選べるのは覚えた秘計だけで、熟練度の記録を読み終える前は選べない
function SelectionService.selectHikei(player: Player, hikeiId: string, selected: boolean): SelectionRules.Reject?
	local takenByOthers = {}
	for userId, ids in hikei do
		if userId ~= player.UserId then
			table.move(ids, 1, #ids, #takenByOthers + 1, takenByOthers)
		end
	end
	local mine = hikei[player.UserId] or {}
	local learned = if JukurendoService.isReady(player) then JukurendoService.getLearned(player) else nil
	local reject, next = SelectionRules.applyHikei(requesterOf(player), hikeiId, selected, mine, takenByOthers, learned)
	if reject then
		return reject
	end
	if table.concat(next, ",") ~= table.concat(mine, ",") then
		hikei[player.UserId] = if #next > 0 then next else nil
		PartyService.refresh()
	end
	return nil
end

-- 覚えていない秘計の選択を外す（窓口で熟練度の記録を消したときなど）。外したら全員に送り直す
local function releaseUnlearnedHikei(player: Player)
	local mine = hikei[player.UserId]
	if not mine or not JukurendoService.isReady(player) then
		return
	end
	local learned = JukurendoService.getLearned(player)
	local kept = {}
	for _, id in mine do
		if table.find(learned, id) then
			table.insert(kept, id)
		end
	end
	if #kept ~= #mine then
		hikei[player.UserId] = if #kept > 0 then kept else nil
		PartyService.refresh()
	end
end

-- ステージ・キャラクター・秘計の選択を外し、全員に送り直す（リザルトからロビーへ戻ったとき）。
-- 続けて同じストーリーを遊べるよう、ストーリーは残す
function SelectionService.clear()
	selectedStage = nil
	table.clear(characters)
	table.clear(hikei)
	PartyService.refresh()
end

-- 今のリーダーが開放していないステージの選択と、開放したステージの無いストーリーの選択を外す
local function releaseLockedSelection()
	local unlocked = leaderUnlocked()
	if not SelectionRules.keepsStage(selectedStage, unlocked) then
		selectedStage = nil
	end
	if not SelectionRules.keepsStory(selectedStory, unlocked) then
		selectedStory = nil
	end
end

-- 今のリーダーでストーリーとステージの選択を確かめ直し、全員に送り直す
local function recheckSelection()
	releaseLockedSelection()
	PartyService.refresh()
end

-- 抜けた人の選択を外す
local function releaseLeftMembers()
	for _, selections in { characters, hikei } :: { { [number]: any } } do
		for userId in selections do
			if not PartyService.isMember(userId) then
				selections[userId] = nil
			end
		end
	end
end

-- リトライでロビーへ戻ったときに、残した選択を確かめ直して全員に送り直す。
-- 抜けた人の選択を外し、今のリーダーが開放していないステージとストーリーの選択と、選べなくなったキャラクターの選択を外す
function SelectionService.revalidate()
	releaseLeftMembers()
	lastLeader = PartyService.getLeader()
	releaseLockedSelection()
	releaseInvalidCharacters()
	PartyService.refresh()
end

-- 入退室とフェーズの変化のたびに呼ぶ。抜けた人の選択は PartyState に載らないので、送り直すのはリーダーが代わったときだけ。
-- 進行を読み終える前の人がリーダーになったとき（プライベートサーバーの持ち主が入ったときなど）は、送り直すだけにし、
-- 読み終えたとき（ProgressService.changed）に確かめ直す。読み終える前は新規の進行とみなされ、開放済みのステージの選択まで外れるため
local function onPartyChanged()
	releaseLeftMembers()
	local leader = PartyService.getLeader()
	if leader ~= lastLeader then
		lastLeader = leader
		if leader and not ProgressService.isReady(leader) then
			PartyService.refresh()
		else
			recheckSelection()
		end
	end
end

local function reject(player: Player, reason: SelectionRules.Reject)
	rejectedRemote:FireClient(player, reason)
end

local function onSelectStory(player: Player, clanId: unknown)
	if not RemoteSchema.validate.SelectStory(clanId) then
		return
	end
	local reason = SelectionService.selectStory(player, clanId :: string)
	if reason then
		reject(player, reason)
	end
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

local function onSelectHikei(player: Player, hikeiId: unknown, selected: unknown)
	if not RemoteSchema.validate.SelectHikei(hikeiId, selected) then
		return
	end
	local reason = SelectionService.selectHikei(player, hikeiId :: string, selected :: boolean)
	if reason then
		reject(player, reason)
	end
end

local function registerDebugCommands()
	DebugCommand.register(
		"SelectStory",
		"<プレイヤー名> <クラン ID>",
		"Remotes.SelectStory と同じ処理でストーリーを選ぶ",
		function(name, clanId)
			local player = DebugCommand.findPlayer(name)
			if not RemoteSchema.validate.SelectStory(clanId) then
				error(`クラン ID の形が正しくない（{tostring(clanId)}）`, 0)
			end
			local reason = SelectionService.selectStory(player, clanId)
			if reason then
				return `{player.Name} の {clanId} のストーリーの選択を拒否した（{reason}）`
			end
			return `{player.Name} が {clanId} のストーリーを選んだ（ステージ {selectedStage or "未選択"}）`
		end
	)
	DebugCommand.register(
		"SelectStage",
		"<プレイヤー名> <ステージ ID>",
		"Remotes.SelectStage と同じ処理でステージを選ぶ（ストーリーもステージのクランになる）",
		function(name, stageId)
			local player = DebugCommand.findPlayer(name)
			if not RemoteSchema.validate.SelectStage(stageId) then
				error(`ステージ ID の形が正しくない（{tostring(stageId)}）`, 0)
			end
			local reason = SelectionService.selectStage(player, stageId)
			if reason then
				return `{player.Name} の {stageId} の選択を拒否した（{reason}）`
			end
			return `{player.Name} が {stageId} を選んだ（ストーリー {tostring(selectedStory)}）`
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
	DebugCommand.register(
		"SelectHikei",
		"<プレイヤー名> <秘計 ID> [true|false]",
		"Remotes.SelectHikei と同じ処理で秘計を選ぶ（false で外す、既定は true）",
		function(name, hikeiId, value)
			local player = DebugCommand.findPlayer(name)
			local selected = not (value == false or value == "false")
			if not RemoteSchema.validate.SelectHikei(hikeiId, selected) then
				error(`秘計 ID の形が正しくない（{tostring(hikeiId)}）`, 0)
			end
			local verb = if selected then "選択" else "取り外し"
			local reason = SelectionService.selectHikei(player, hikeiId, selected)
			if reason then
				return `{player.Name} の {hikeiId} の{verb}を拒否した（{reason}）`
			end
			local list = SelectionService.getHikei(player)
			local chosen = if #list > 0 then table.concat(list, "、") else "なし"
			return `{player.Name} の {hikeiId} の{verb}を受け付けた（選んだ秘計: {chosen}）`
		end
	)
end

function SelectionService.start()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	rejectedRemote = remotes:WaitForChild("SelectionRejected") :: RemoteEvent
	local selectStory = remotes:WaitForChild("SelectStory") :: RemoteEvent
	selectStory.OnServerEvent:Connect(onSelectStory)
	local selectStage = remotes:WaitForChild("SelectStage") :: RemoteEvent
	selectStage.OnServerEvent:Connect(onSelectStage)
	local selectCharacter = remotes:WaitForChild("SelectCharacter") :: RemoteEvent
	selectCharacter.OnServerEvent:Connect(onSelectCharacter)
	local selectHikei = remotes:WaitForChild("SelectHikei") :: RemoteEvent
	selectHikei.OnServerEvent:Connect(onSelectHikei)

	PartyService.setExtraProvider(function(): Party.Extra
		return {
			story = selectedStory,
			stage = selectedStage,
			unlockedStages = leaderUnlocked(),
			characterOf = function(userId: number): string?
				return characters[userId]
			end,
			hikeiOf = function(userId: number): { string }
				return table.clone(hikei[userId] or {})
			end,
		}
	end)
	PartyService.changed:Connect(onPartyChanged)
	JukurendoService.changed:Connect(releaseUnlearnedHikei)
	-- リーダーの進行を読み終えたときや、クリアで開放済みが増えたとき
	ProgressService.changed:Connect(function(player: Player)
		if player == PartyService.getLeader() then
			recheckSelection()
		end
	end)
	registerDebugCommands()
	onPartyChanged()
end

return SelectionService
