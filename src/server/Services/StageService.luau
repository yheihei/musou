--!strict
-- 出撃からロビーへ戻るまでのステージの進行。フェーズの遷移は ReplicatedStorage.Shared.StagePhase が決め、
-- PartyService.setPhase で全員に知らせる。出撃の条件は SelectionRules.checkShutsugeki、区画は KukakuService から引く。
--
-- - 出撃（Remotes.Shutsugeki）はリーダーだけが、ロビーのフェーズで、ステージと出撃する全員のキャラクターを選んだ後にできる。
--   受け付けなければ SelectionRejected で本人に理由を返す
-- - 出撃すると、待機中でない全員を区画の出撃地点へ移す（周りを読み込ませてから出現し直す）。
--   選んだキャラクターを Player の Attribute の CharacterId に書いてから出現し直すので、能力値と見た目が切り替わる
-- - イベントシーンのフェーズは、当面すぐ次へ進める
-- - finish で勝敗と理由を決め、出撃して残っているメンバーに StageResult を送る
-- - リザルトのフェーズでリーダーが Remotes.ReturnToLobby を送ると、選択を外して全員をロビーへ戻す
-- - 出撃したメンバーが全員抜けたら、ロビーのフェーズに戻す
-- - 片付けは各サービスが started・finished・phaseChanged を受けて行う

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Mejirushi = require(ReplicatedStorage.Shared.Mejirushi)
local RemoteSchema = require(ReplicatedStorage.Shared.RemoteSchema)
local SelectionRules = require(ReplicatedStorage.Shared.SelectionRules)
local StagePhase = require(ReplicatedStorage.Shared.StagePhase)
local Stages = require(ReplicatedStorage.Shared.Stages)
local DebugCommand = require(script.Parent.Parent.DebugCommand)
local KukakuService = require(script.Parent.KukakuService)
local PartyService = require(script.Parent.PartyService)
local PlayerService = require(script.Parent.PlayerService)
local ProgressService = require(script.Parent.ProgressService)
local SelectionService = require(script.Parent.SelectionService)

-- 出撃してから戻るまでのステージ
type Session = {
	stageId: string,
	-- 出撃したメンバー（入った順）。抜けた人も残す
	members: { Player },
	-- 戦闘のフェーズを始めた時刻（os.clock）。戦闘の前は nil
	battleStartedAt: number?,
	-- 戦闘のフェーズの経過時間（秒）。決着するまでは nil
	elapsed: number?,
}

-- 開始の通知で渡す中身
export type StartInfo = {
	stageId: string,
	members: { Player },
	count: number,
}

local StageService = {}

local phase: StagePhase.Phase = "Lobby"
local session: Session? = nil
local rejectedRemote: RemoteEvent
local resultRemote: RemoteEvent

local phaseChangedEvent = Instance.new("BindableEvent")
-- フェーズが変わったときに、新しいフェーズ（StagePhase.Phase）で発火する
StageService.phaseChanged = phaseChangedEvent.Event
local startedEvent = Instance.new("BindableEvent")
-- 出撃したメンバーを出撃地点へ移した後に、StartInfo で発火する
StageService.started = startedEvent.Event
local finishedEvent = Instance.new("BindableEvent")
-- 勝敗が決まったときに、StageResult で発火する
StageService.finished = finishedEvent.Event

function StageService.getPhase(): StagePhase.Phase
	return phase
end

-- 出撃しているステージ。ロビーでは nil
function StageService.getStage(): string?
	return if session then session.stageId else nil
end

-- 出撃して、まだパーティーにいるメンバー
function StageService.getMembers(): { Player }
	local result = {}
	if session then
		for _, member in session.members do
			if member.Parent and PartyService.isMember(member.UserId) then
				table.insert(result, member)
			end
		end
	end
	return result
end

local function transition(event: StagePhase.Event): boolean
	local next = StagePhase.next(phase, event)
	if not next then
		return false
	end
	phase = next
	PartyService.setPhase(StagePhase.toPartyPhase(next))
	phaseChangedEvent:Fire(next)
	return true
end

-- 出撃するメンバー全員がキャラクターを選んでいるか
local function membersReady(members: { Player }): boolean
	for _, member in members do
		if not SelectionService.getCharacter(member) then
			return false
		end
	end
	return true
end

-- メンバーを入った順に出撃地点へ移し、全員が出現し直すまで待つ
local function moveToShutsugekiChiten(members: { Player }, chiten: { KukakuService.ShutsugekiChiten })
	local numbers = {}
	local cframes: { [number]: CFrame } = {}
	for _, point in chiten do
		table.insert(numbers, point.number)
		cframes[point.number] = point.cframe
	end
	local pending = #members
	for index, member in members do
		local number = Mejirushi.shutsugekiNumberOf(index, numbers) :: number
		-- キャラクターを選んでいない人（窓口でステージを指定した出撃）は、今のキャラクターのまま出る
		local characterId = SelectionService.getCharacter(member)
		task.spawn(function()
			PlayerService.spawnAt(member, cframes[number], characterId)
			pending -= 1
		end)
	end
	while pending > 0 do
		task.wait()
	end
end

-- 出撃する。受け付けたら nil、受け付けなければ拒否の理由を返す。
-- stageOverride を渡すと、選択を問わずそのステージへ出撃する（窓口の確認用）。ロビーのフェーズだけは確かめる
function StageService.shutsugeki(player: Player, stageOverride: string?): SelectionRules.Reject?
	local members = PartyService.getActivePlayers()
	local stageId = stageOverride or SelectionService.getStage()
	if stageOverride then
		if phase ~= "Lobby" then
			return "NotLobby"
		end
		if not Stages.get(stageOverride) then
			return "UnknownStage"
		end
	else
		local leader = PartyService.getLeader()
		local reject = SelectionRules.checkShutsugeki({
			phase = PartyService.getPhase(),
			isLeader = leader == player,
			waiting = PartyService.isWaiting(player),
		}, stageId, if leader then ProgressService.getUnlocked(leader) else {}, membersReady(members))
		if reject then
			return reject
		end
	end
	local stage = Stages.get(stageId :: string) :: Stages.Stage
	local chiten = KukakuService.shutsugekiChiten(stage.kukaku)
	if #chiten == 0 then
		return "KukakuMissing"
	end
	if #members == 0 or not transition("Shutsugeki") then
		return "NotLobby"
	end
	local current: Session = { stageId = stage.id, members = members, battleStartedAt = nil, elapsed = nil }
	session = current
	moveToShutsugekiChiten(members, chiten)
	if session ~= current then
		-- 移している間に全員が抜けた
		return nil
	end
	startedEvent:Fire({ stageId = stage.id, members = members, count = #members } :: StartInfo)
	-- 開始のイベントシーンは、当面すぐ次へ進める
	transition("SceneEnd")
	current.battleStartedAt = os.clock()
	return nil
end

-- 勝敗を決めてリザルトへ進め、出撃して残っているメンバーに StageResult を送る。戦闘のフェーズでなければ false
function StageService.finish(victory: boolean, reason: RemoteSchema.ResultReason): boolean
	local current = session
	if phase ~= "Battle" or not current then
		return false
	end
	local elapsed = if current.battleStartedAt then os.clock() - current.battleStartedAt else 0
	current.elapsed = elapsed
	transition("Finish")
	-- 終了のイベントシーンは、当面すぐ次へ進める
	transition("SceneEnd")
	local members = StageService.getMembers()
	local result: RemoteSchema.StageResult = {
		victory = victory,
		reason = reason,
		elapsed = elapsed,
		members = {},
	}
	for _, member in members do
		table.insert(result.members, {
			userId = member.UserId,
			name = member.Name,
			gekihasu = member:GetAttribute("Gekihasu") :: number? or 0,
			newlyUnlocked = {},
		})
	end
	finishedEvent:Fire(result)
	for _, member in members do
		resultRemote:FireClient(member, result)
	end
	return true
end

-- リザルトからロビーへ戻る。リーダーがリザルトのフェーズで送ったときだけ受け付け、選択を外して全員をロビーへ戻す
function StageService.returnToLobby(player: Player): boolean
	if phase ~= "Result" or PartyService.getLeader() ~= player then
		return false
	end
	local members = StageService.getMembers()
	session = nil
	SelectionService.clear()
	transition("ReturnToLobby")
	for _, member in members do
		task.spawn(PlayerService.spawnInLobby, member)
	end
	return true
end

-- 出撃したメンバーが全員抜けたら、ロビーのフェーズに戻す
local function onPartyChanged()
	if session and phase ~= "Lobby" and #StageService.getMembers() == 0 then
		session = nil
		transition("Abort")
	end
end

-- Shutsugeki と ReturnToLobby は引数を持たない。届いた引数は読まない
local function onShutsugeki(player: Player)
	local reason = StageService.shutsugeki(player)
	if reason then
		rejectedRemote:FireClient(player, reason)
	end
end

local function onReturnToLobby(player: Player)
	StageService.returnToLobby(player)
end

local function registerDebugCommands()
	DebugCommand.register(
		"Shutsugeki",
		"<プレイヤー名> [ステージ ID]",
		"Remotes.Shutsugeki と同じ処理で出撃する。ステージ ID を渡すと、選択を問わずそのステージへ出撃する（確認用）",
		function(name, stageId)
			local player = DebugCommand.findPlayer(name)
			if stageId ~= nil and not RemoteSchema.isId(stageId) then
				error(`ステージ ID の形が正しくない（{tostring(stageId)}）`, 0)
			end
			local reason = StageService.shutsugeki(player, stageId)
			if reason then
				return `{player.Name} の出撃を拒否した（{reason}）`
			end
			local names = {}
			for _, member in StageService.getMembers() do
				table.insert(names, member.Name)
			end
			return `{StageService.getStage()} に出撃した（{table.concat(names, "、")}、フェーズ {phase}）`
		end
	)
	DebugCommand.register(
		"Finish",
		`<victory|defeat> [{table.concat(RemoteSchema.resultReasons, "|")}]`,
		"勝敗を決めてリザルトへ進める。理由の既定は、勝利が TekigunShuryoGekiha、敗北が TimeUp",
		function(outcome, reason)
			if outcome ~= "victory" and outcome ~= "defeat" then
				error("勝敗は victory か defeat で指定する", 0)
			end
			local victory = outcome == "victory"
			local why = reason or (if victory then "TekigunShuryoGekiha" else "TimeUp")
			if not table.find(RemoteSchema.resultReasons, why) then
				error(
					`理由は {table.concat(RemoteSchema.resultReasons, "、")} のどれか（{tostring(why)}）`,
					0
				)
			end
			if not StageService.finish(victory, why) then
				return `戦闘のフェーズでないので決着させなかった（フェーズ {phase}）`
			end
			return `{if victory then "勝利" else "敗北"}（{why}）でリザルトへ進めた`
		end
	)
	DebugCommand.register(
		"ReturnToLobby",
		"<プレイヤー名>",
		"Remotes.ReturnToLobby と同じ処理で、リザルトからロビーへ戻る",
		function(name)
			local player = DebugCommand.findPlayer(name)
			if not StageService.returnToLobby(player) then
				return `{player.Name} の ReturnToLobby を受け付けなかった（リーダーがリザルトのフェーズで送ったときだけ受け付ける。フェーズ {phase}）`
			end
			return "ロビーへ戻した"
		end
	)
	DebugCommand.register("DumpStage", "", "ステージの進行の状態を JSON で返す", function()
		local names = {}
		for _, member in StageService.getMembers() do
			table.insert(names, member.Name)
		end
		local current = session
		local elapsed = if current
			then current.elapsed or (if current.battleStartedAt then os.clock() - current.battleStartedAt else nil)
			else nil
		return HttpService:JSONEncode({
			phase = phase,
			stage = StageService.getStage(),
			members = names,
			elapsed = elapsed,
		})
	end)
end

function StageService.start()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	rejectedRemote = remotes:WaitForChild("SelectionRejected") :: RemoteEvent
	resultRemote = remotes:WaitForChild("StageResult") :: RemoteEvent
	local shutsugekiRemote = remotes:WaitForChild("Shutsugeki") :: RemoteEvent
	shutsugekiRemote.OnServerEvent:Connect(onShutsugeki)
	local returnRemote = remotes:WaitForChild("ReturnToLobby") :: RemoteEvent
	returnRemote.OnServerEvent:Connect(onReturnToLobby)
	PartyService.changed:Connect(onPartyChanged)
	registerDebugCommands()
end

return StageService
