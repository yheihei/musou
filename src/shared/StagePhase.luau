--!strict
-- ステージの進行のフェーズの遷移。ロビー → 開始のイベントシーン → 戦闘 → 終了のイベントシーン → リザルト → ロビーの順に進む。
-- PartyState には、開始と終了のイベントシーンをまとめて EventScene として載せる。進行の状態は StageService が持つ。
-- イベントシーンのフェーズで流すシーンは、ステージの定義（Stages.luau の eventScenes）から sceneIdFor で引く。
-- Roblox の API は使わない。

local RemoteSchema = require("./RemoteSchema")
local Stages = require("./Stages")

export type Phase = "Lobby" | "StartScene" | "Battle" | "EndScene" | "Result"

export type Event =
	"Shutsugeki" -- 出撃（ロビー → 開始のイベントシーン）
	| "SceneEnd" -- イベントシーンの終わり（開始のイベントシーン → 戦闘、終了のイベントシーン → リザルト）
	| "Finish" -- 勝敗の決着（戦闘 → 終了のイベントシーン）
	| "ReturnToLobby" -- リザルトからロビーへ戻る（選択を外す）
	| "Retry" -- リザルトから、同じステージへ挑み直すためにロビーへ戻る（選択を残す）
	| "Abort" -- 出撃したメンバーが全員抜けた（ロビー以外 → ロビー）

local StagePhase = {}

-- 戦闘のフェーズの終了予定の時刻（workspace:GetServerTimeNow の時刻）を置く workspace の Attribute。戦闘の外では無い
StagePhase.DEADLINE_ATTRIBUTE = "BattleDeadline"

StagePhase.phases = { "Lobby", "StartScene", "Battle", "EndScene", "Result" } :: { Phase }
StagePhase.events = { "Shutsugeki", "SceneEnd", "Finish", "ReturnToLobby", "Retry", "Abort" } :: { Event }

local TRANSITIONS: { [Phase]: { [Event]: Phase } } = {
	Lobby = { Shutsugeki = "StartScene" },
	StartScene = { SceneEnd = "Battle", Abort = "Lobby" },
	Battle = { Finish = "EndScene", Abort = "Lobby" },
	EndScene = { SceneEnd = "Result", Abort = "Lobby" },
	Result = { ReturnToLobby = "Lobby", Retry = "Lobby", Abort = "Lobby" },
}

local PARTY_PHASES: { [Phase]: RemoteSchema.Phase } = {
	Lobby = "Lobby",
	StartScene = "EventScene",
	Battle = "Battle",
	EndScene = "EventScene",
	Result = "Result",
}

-- phase で event が起きたときの次のフェーズ。その出来事を受け付けないフェーズなら nil
function StagePhase.next(phase: Phase, event: Event): Phase?
	return TRANSITIONS[phase][event]
end

-- PartyState に載せるフェーズ
function StagePhase.toPartyPhase(phase: Phase): RemoteSchema.Phase
	return PARTY_PHASES[phase]
end

-- phase で流すイベントシーンの ID。開始のイベントシーンは scenes.start、終了は勝敗で scenes.victory か scenes.defeat。
-- イベントシーンのフェーズでないときと、登録が無いときは nil。nil ならすぐ次のフェーズへ進める
-- （敗北のシーンが無ければリザルトへ直行する）
function StagePhase.sceneIdFor(scenes: Stages.EventScenes, phase: Phase, victory: boolean?): string?
	if phase == "StartScene" then
		return scenes.start
	elseif phase == "EndScene" then
		return if victory then scenes.victory else scenes.defeat
	end
	return nil
end

return StagePhase
