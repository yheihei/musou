--!strict
-- 出撃からロビーへ戻るまでのステージの進行。フェーズの遷移は ReplicatedStorage.Shared.StagePhase が決め、
-- PartyService.setPhase で全員に知らせる。出撃の条件は SelectionRules.checkShutsugeki、区画は KukakuService から引く。
--
-- - 出撃（Remotes.Shutsugeki）はリーダーだけが、ロビーのフェーズで、ステージと出撃する全員のキャラクターを選んだ後にできる。
--   受け付けなければ SelectionRejected で本人に理由を返す
-- - 出撃すると、待機中でない全員を区画の出撃地点へ移す（周りを読み込ませてから出現し直す）。
--   選んだキャラクターを Player の Attribute の CharacterId に書いてから出現し直すので、能力値と見た目が切り替わる
-- - イベントシーンのフェーズでは、ステージの定義のシーンを出撃して残っているメンバーに PlayEventScene で流す
--   （待機中の人には流さない）。シーンの長さが過ぎるか、見ている全員がスキップを押すと次のフェーズへ進める。
--   スキップの集計は ReplicatedStorage.Shared.SkipVote が持ち、スキップを受けるたびと人が抜けるたびに SkipCount を送る。
--   流すシーンが無いか定義に無ければ、すぐ次のフェーズへ進める（敗北のシーンが無ければリザルトへ直行する）
-- - 戦闘のフェーズには制限時間（Config.luau の Stage 節）があり、終了予定の時刻（workspace:GetServerTimeNow の時刻）を
--   workspace の Attribute の BattleDeadline に置いてクライアントへ複製する。過ぎたら時間切れで負けにする
-- - 出撃すると、出撃するメンバーの撃破数と奥義ゲージを出撃したときの値に戻す
-- - 倒れた出撃メンバーは、出撃したステージの区画の出撃地点から再出撃する（暫定。兵站線に沿った再出撃は #103 で置き換える）。
--   ロビーのフェーズの人と待機中の人はロビーに出現する
-- - finish で勝敗と理由を決め、終了のイベントシーンの後に、出撃して残っているメンバーに StageResult を送る
-- - 勝ったら、出撃して残っている全員にクリアを記録し（対象は Progress.clearTargets。抜けた人と待機中の人は入れない）、
--   新しく開放したステージを StageResult のメンバーごとに書く
-- - リザルトのフェーズでリーダーが Remotes.ReturnToLobby を送ると、選択を外して全員をロビーへ戻す
-- - リザルトのフェーズでリーダーが Remotes.Retry を送ると、ステージと選択を残して全員をロビーへ戻す。
--   残した選択は SelectionService.revalidate で確かめ直す（リーダーが代わっていたらステージを判定し直す）
-- - 出撃したメンバーが全員抜けたら、ロビーのフェーズに戻す
-- - 片付けは各サービスが started・finished・phaseChanged を受けて行う

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local EventScenes = require(ReplicatedStorage.Shared.EventScenes)
local Mejirushi = require(ReplicatedStorage.Shared.Mejirushi)
local Progress = require(ReplicatedStorage.Shared.Progress)
local RemoteSchema = require(ReplicatedStorage.Shared.RemoteSchema)
local SelectionRules = require(ReplicatedStorage.Shared.SelectionRules)
local SkipVote = require(ReplicatedStorage.Shared.SkipVote)
local StagePhase = require(ReplicatedStorage.Shared.StagePhase)
local Stages = require(ReplicatedStorage.Shared.Stages)
local DebugCommand = require(script.Parent.Parent.DebugCommand)
local KukakuService = require(script.Parent.KukakuService)
local PartyService = require(script.Parent.PartyService)
local PlayerService = require(script.Parent.PlayerService)
local ProgressService = require(script.Parent.ProgressService)
local SelectionService = require(script.Parent.SelectionService)

-- 流しているイベントシーン
type SceneRun = {
	id: string,
	vote: SkipVote.Vote,
	-- 長さが過ぎる時刻（os.clock）
	endsAt: number,
}

-- 出撃してから戻るまでのステージ
type Session = {
	stageId: string,
	-- 出撃したメンバー（入った順）。抜けた人も残す
	members: { Player },
	-- 戦闘のフェーズを始めた時刻（os.clock）。戦闘の前は nil
	battleStartedAt: number?,
	-- 戦闘のフェーズの経過時間（秒）。決着するまでは nil
	elapsed: number?,
	-- 戦闘のフェーズの終了予定の時刻（workspace:GetServerTimeNow の時刻）。戦闘のフェーズの外では nil
	deadline: number?,
	-- 流しているイベントシーン。流していなければ nil
	scene: SceneRun?,
	-- 決着したときに作った StageResult。終了のイベントシーンの後に送る
	result: RemoteSchema.StageResult?,
}

-- 開始の通知で渡す中身
export type StartInfo = {
	stageId: string,
	members: { Player },
	count: number,
}

local StageService = {}

-- 時間切れを確かめる間隔（秒）
local DEADLINE_CHECK_INTERVAL = 0.25

local phase: StagePhase.Phase = "Lobby"
local session: Session? = nil
local rejectedRemote: RemoteEvent
local resultRemote: RemoteEvent
local playEventSceneRemote: RemoteEvent
local skipCountRemote: RemoteEvent

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

-- 戦闘のフェーズの終了予定の時刻を書き、クライアントへ複製する。nil で消す
local function setDeadline(current: Session?, deadline: number?)
	if current then
		current.deadline = deadline
	end
	workspace:SetAttribute(StagePhase.DEADLINE_ATTRIBUTE, deadline)
end

local function transition(event: StagePhase.Event): boolean
	local next = StagePhase.next(phase, event)
	if not next then
		return false
	end
	if next ~= "Battle" then
		setDeadline(session, nil)
	end
	phase = next
	PartyService.setPhase(StagePhase.toPartyPhase(next))
	phaseChangedEvent:Fire(next)
	return true
end

-- 出撃して、まだパーティーにいるメンバーの UserId
local function memberIds(): { number }
	local ids = {}
	for _, member in StageService.getMembers() do
		table.insert(ids, member.UserId)
	end
	return ids
end

local function sendSkipCount(run: SceneRun)
	local skipped, total = SkipVote.count(run.vote)
	for _, member in StageService.getMembers() do
		skipCountRemote:FireClient(member, skipped, total)
	end
end

-- イベントシーンのフェーズを抜けた後の処理。戦闘なら時間を測り始め、リザルトなら StageResult を送る
local function afterScene(current: Session)
	if phase == "Battle" then
		current.battleStartedAt = os.clock()
		setDeadline(current, workspace:GetServerTimeNow() + Config.Stage.TimeLimit)
	elseif phase == "Result" then
		local result = current.result
		if result then
			for _, member in StageService.getMembers() do
				resultRemote:FireClient(member, result)
			end
		end
	end
end

-- イベントシーンのフェーズを終えて次のフェーズへ進める。シーンを流していなければ何もしない
local function endScene(current: Session)
	if session ~= current or not current.scene then
		return
	end
	current.scene = nil
	if transition("SceneEnd") then
		afterScene(current)
	end
end

-- イベントシーンのフェーズを始める。流すシーンが無いか定義に無ければ、すぐ次のフェーズへ進める
local function beginScene(current: Session, sceneId: string?)
	local scene = EventScenes.get(sceneId)
	if not scene then
		if sceneId then
			warn(`StageService: イベントシーン {sceneId} の定義が無いので飛ばす`)
		end
		if transition("SceneEnd") then
			afterScene(current)
		end
		return
	end
	local run: SceneRun = {
		id = scene.id,
		vote = SkipVote.new(memberIds()),
		endsAt = os.clock() + scene.duration,
	}
	current.scene = run
	for _, member in StageService.getMembers() do
		playEventSceneRemote:FireClient(member, scene.id)
	end
	task.delay(scene.duration, function()
		if current.scene == run then
			endScene(current)
		end
	end)
end

-- イベントシーンのスキップを数える。数えたら true と、スキップした人数・全体の人数を返す。
-- 全員がスキップしたら次のフェーズへ進める。シーンを流していないときと、見ていない人・押し済みの人は数えない
function StageService.skipEventScene(player: Player): (boolean, number, number)
	local current = session
	local run = if current then current.scene else nil
	if not current or not run then
		return false, 0, 0
	end
	local counted = SkipVote.skip(run.vote, player.UserId)
	local skipped, total = SkipVote.count(run.vote)
	if counted then
		sendSkipCount(run)
		if SkipVote.isComplete(run.vote) then
			endScene(current)
		end
	end
	return counted, skipped, total
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

-- 出撃した順番（1から）のメンバーが立つ出撃地点。地点が無ければ nil
local function chitenFor(chiten: { KukakuService.ShutsugekiChiten }, index: number): CFrame?
	local numbers = {}
	local cframes: { [number]: CFrame } = {}
	for _, point in chiten do
		table.insert(numbers, point.number)
		cframes[point.number] = point.cframe
	end
	local number = Mejirushi.shutsugekiNumberOf(index, numbers)
	return if number then cframes[number] else nil
end

-- メンバーを入った順に出撃地点へ移し、全員が出現し直すまで待つ
local function moveToShutsugekiChiten(members: { Player }, chiten: { KukakuService.ShutsugekiChiten })
	local pending = #members
	for index, member in members do
		local cframe = chitenFor(chiten, index) :: CFrame
		-- キャラクターを選んでいない人（窓口でステージを指定した出撃）は、今のキャラクターのまま出る
		local characterId = SelectionService.getCharacter(member)
		task.spawn(function()
			PlayerService.spawnAt(member, cframe, characterId)
			pending -= 1
		end)
	end
	while pending > 0 do
		task.wait()
	end
end

-- 倒れた人を出現し直させる。出撃して残っているメンバーは、出撃したステージの区画の出撃地点から再出撃する
-- （暫定。兵站線に沿った再出撃は #103 で置き換える）。ロビーのフェーズの人と待機中の人はロビーに出す
local function respawn(player: Player)
	local current = session
	local index = if current and phase ~= "Lobby" then table.find(current.members, player) else nil
	if current and index and PartyService.isMember(player.UserId) then
		local stage = Stages.get(current.stageId) :: Stages.Stage
		local cframe = chitenFor(KukakuService.shutsugekiChiten(stage.kukaku), index)
		if cframe then
			PlayerService.spawnAt(player, cframe)
			return
		end
	end
	PlayerService.spawnInLobby(player)
end

-- 戦闘のフェーズで終了予定の時刻を過ぎていたら、時間切れで負けにする
local function checkDeadline()
	local current = session
	local deadline = if current then current.deadline else nil
	if phase == "Battle" and deadline and workspace:GetServerTimeNow() >= deadline then
		StageService.finish(false, "TimeUp")
	end
end

-- 出撃する。受け付けたら nil、受け付けなければ拒否の理由を返す。
-- stageOverride を渡すと、選択を問わずそのステージへ出撃する（窓口の確認用）。ロビーのフェーズだけは確かめる。
-- startScene を渡すと、ステージの定義の代わりにそのシーンを開始のイベントシーンとして流す（窓口の確認用）
function StageService.shutsugeki(player: Player, stageOverride: string?, startScene: string?): SelectionRules.Reject?
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
	local current: Session = {
		stageId = stage.id,
		members = members,
		battleStartedAt = nil,
		elapsed = nil,
		deadline = nil,
		scene = nil,
		result = nil,
	}
	session = current
	for _, member in members do
		PlayerService.resetForShutsugeki(member)
	end
	moveToShutsugekiChiten(members, chiten)
	if session ~= current then
		-- 移している間に全員が抜けた
		return nil
	end
	startedEvent:Fire({ stageId = stage.id, members = members, count = #members } :: StartInfo)
	beginScene(current, startScene or StagePhase.sceneIdFor(stage.eventScenes, "StartScene"))
	return nil
end

-- 出撃したメンバーの、決着したときの様子（抜けたか、入り直して待っているか）
local function participantsOf(current: Session): { Progress.Participant }
	local result: { Progress.Participant } = {}
	for _, member in current.members do
		local present = member.Parent ~= nil and PartyService.isMember(member.UserId)
		table.insert(result, {
			userId = member.UserId,
			sortied = true,
			left = not present,
			waiting = present and PartyService.isWaiting(member),
		})
	end
	return result
end

-- 勝ったときに、出撃して残っている全員にクリアを記録する。プレイヤーごとに新しく開放したステージを返す
local function recordClear(current: Session, victory: boolean): { [Player]: { string } }
	local targets = Progress.clearTargets(participantsOf(current), victory)
	local players = {}
	for _, member in current.members do
		if member.Parent and table.find(targets, member.UserId) then
			table.insert(players, member)
		end
	end
	if #players == 0 then
		return {}
	end
	return ProgressService.recordClear(players, current.stageId)
end

-- 勝敗を決めて終了のイベントシーンへ進める。勝ったら出撃して残っている全員にクリアを記録する。
-- StageResult は決着の時点で作り、終了のイベントシーンの後に出撃して残っているメンバーへ送る。戦闘のフェーズでなければ false
function StageService.finish(victory: boolean, reason: RemoteSchema.ResultReason): boolean
	local current = session
	if phase ~= "Battle" or not current then
		return false
	end
	local elapsed = if current.battleStartedAt then os.clock() - current.battleStartedAt else 0
	current.elapsed = elapsed
	local newlyUnlocked = recordClear(current, victory)
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
			newlyUnlocked = newlyUnlocked[member] or {},
		})
	end
	current.result = result
	transition("Finish")
	finishedEvent:Fire(result)
	local stage = Stages.get(current.stageId) :: Stages.Stage
	beginScene(current, StagePhase.sceneIdFor(stage.eventScenes, "EndScene", victory))
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

-- リザルトから同じステージへ挑み直すためにロビーへ戻る。リーダーがリザルトのフェーズで送ったときだけ受け付ける。
-- ステージと選択（キャラクター・秘計）は残し、今のリーダーで確かめ直す。待機中だった人は選択の無いまま合流する
function StageService.retry(player: Player): boolean
	if phase ~= "Result" or PartyService.getLeader() ~= player then
		return false
	end
	local members = StageService.getMembers()
	session = nil
	transition("Retry")
	SelectionService.revalidate()
	for _, member in members do
		task.spawn(PlayerService.spawnInLobby, member)
	end
	return true
end

-- 出撃したメンバーが全員抜けたら、ロビーのフェーズに戻す。
-- イベントシーンの途中で抜けた人はスキップの人数から外し、残りの全員がスキップ済みなら次のフェーズへ進める
local function onPartyChanged()
	local current = session
	if not current or phase == "Lobby" then
		return
	end
	if #StageService.getMembers() == 0 then
		session = nil
		transition("Abort")
		return
	end
	local run = current.scene
	if run and SkipVote.retain(run.vote, memberIds()) then
		sendSkipCount(run)
		if SkipVote.isComplete(run.vote) then
			endScene(current)
		end
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

local function onRetry(player: Player)
	StageService.retry(player)
end

-- SkipEventScene は引数を持たない。届いた引数は読まない
local function onSkipEventScene(player: Player)
	StageService.skipEventScene(player)
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
	DebugCommand.register(
		"Retry",
		"<プレイヤー名>",
		"Remotes.Retry と同じ処理で、リザルトから同じステージへ挑み直すためにロビーへ戻る（ステージと選択を残す）",
		function(name)
			local player = DebugCommand.findPlayer(name)
			if not StageService.retry(player) then
				return `{player.Name} の Retry を受け付けなかった（リーダーがリザルトのフェーズで送ったときだけ受け付ける。フェーズ {phase}）`
			end
			return `ロビーへ戻した（ステージ {tostring(SelectionService.getStage())} と選択を残した）`
		end
	)
	DebugCommand.register(
		"StartEventScene",
		"<シーン ID> [ステージ ID]",
		"出撃するメンバー全員でステージ（既定は Test）へ出撃し、そのシーンを開始のイベントシーンとして流す（確認用）",
		function(sceneId, stageId)
			if type(sceneId) ~= "string" or not EventScenes.get(sceneId) then
				local ids = {}
				for id in EventScenes.definitions do
					table.insert(ids, id)
				end
				table.sort(ids)
				error(`シーン ID は {table.concat(ids, "、")} のどれか（{tostring(sceneId)}）`, 0)
			end
			local id = if stageId ~= nil then stageId else "Test"
			if not RemoteSchema.isId(id) then
				error(`ステージ ID の形が正しくない（{tostring(id)}）`, 0)
			end
			local leader = PartyService.getLeader()
			if not leader then
				return "パーティーに誰もいない"
			end
			local reason = StageService.shutsugeki(leader, id, sceneId)
			if reason then
				return `{id} への出撃を拒否した（{reason}）`
			end
			return `{id} に出撃し、イベントシーン {sceneId} を流した（フェーズ {phase}）`
		end
	)
	DebugCommand.register(
		"SkipEventScene",
		"<プレイヤー名>",
		"Remotes.SkipEventScene と同じ処理で、イベントシーンのスキップを押す",
		function(name)
			local player = DebugCommand.findPlayer(name)
			local counted, skipped, total = StageService.skipEventScene(player)
			if not counted then
				return `{player.Name} のスキップを数えなかった（シーンを流していないか、見ていないか、押し済み。フェーズ {phase}）`
			end
			return `{player.Name} のスキップを数えた（{skipped}/{total}、フェーズ {phase}）`
		end
	)
	DebugCommand.register(
		"SetDeadline",
		"<残り秒数>",
		"戦闘のフェーズの残り時間を書き換える。0 にすると時間切れで負ける（確認用）",
		function(value)
			local seconds = math.max(DebugCommand.toNumber(value, "残り秒数"), 0)
			local current = session
			if phase ~= "Battle" or not current then
				return `戦闘のフェーズでないので書き換えなかった（フェーズ {phase}）`
			end
			setDeadline(current, workspace:GetServerTimeNow() + seconds)
			return `戦闘のフェーズの残り時間を {seconds} 秒にした`
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
		local run = if current then current.scene else nil
		local scene: { [string]: any }? = nil
		if run then
			local skipped, total = SkipVote.count(run.vote)
			scene = {
				id = run.id,
				skipped = skipped,
				total = total,
				remaining = math.max(run.endsAt - os.clock(), 0),
			}
		end
		local deadline = if current then current.deadline else nil
		return HttpService:JSONEncode({
			phase = phase,
			stage = StageService.getStage(),
			members = names,
			elapsed = elapsed,
			remaining = if deadline then math.max(deadline - workspace:GetServerTimeNow(), 0) else nil,
			scene = scene,
		})
	end)
end

function StageService.start()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	rejectedRemote = remotes:WaitForChild("SelectionRejected") :: RemoteEvent
	resultRemote = remotes:WaitForChild("StageResult") :: RemoteEvent
	playEventSceneRemote = remotes:WaitForChild("PlayEventScene") :: RemoteEvent
	skipCountRemote = remotes:WaitForChild("SkipCount") :: RemoteEvent
	local shutsugekiRemote = remotes:WaitForChild("Shutsugeki") :: RemoteEvent
	shutsugekiRemote.OnServerEvent:Connect(onShutsugeki)
	local returnRemote = remotes:WaitForChild("ReturnToLobby") :: RemoteEvent
	returnRemote.OnServerEvent:Connect(onReturnToLobby)
	local retryRemote = remotes:WaitForChild("Retry") :: RemoteEvent
	retryRemote.OnServerEvent:Connect(onRetry)
	local skipRemote = remotes:WaitForChild("SkipEventScene") :: RemoteEvent
	skipRemote.OnServerEvent:Connect(onSkipEventScene)
	PartyService.changed:Connect(onPartyChanged)
	PlayerService.setRespawner(respawn)
	registerDebugCommands()
	task.spawn(function()
		while true do
			task.wait(DEADLINE_CHECK_INTERVAL)
			checkDeadline()
		end
	end)
end

return StageService
