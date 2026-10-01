--!strict
-- ステージの進行のフェーズの遷移。ロビー → 開始のイベントシーン → 戦闘 → 終了のイベントシーン → リザルト → ロビーの順に進む。
-- PartyState には、開始と終了のイベントシーンをまとめて EventScene として載せる。進行の状態は StageService が持つ。
-- Roblox の API は使わない。

local RemoteSchema = require("./RemoteSchema")

export type Phase = "Lobby" | "StartScene" | "Battle" | "EndScene" | "Result"

export type Event =
	"Shutsugeki" -- 出撃（ロビー → 開始のイベントシーン）
	| "SceneEnd" -- イベントシーンの終わり（開始のイベントシーン → 戦闘、終了のイベントシーン → リザルト）
	| "Finish" -- 勝敗の決着（戦闘 → 終了のイベントシーン）
	| "ReturnToLobby" -- リザルトからロビーへ戻る
	| "Abort" -- 出撃したメンバーが全員抜けた（ロビー以外 → ロビー）

local StagePhase = {}

StagePhase.phases = { "Lobby", "StartScene", "Battle", "EndScene", "Result" } :: { Phase }
StagePhase.events = { "Shutsugeki", "SceneEnd", "Finish", "ReturnToLobby", "Abort" } :: { Event }

local TRANSITIONS: { [Phase]: { [Event]: Phase } } = {
	Lobby = { Shutsugeki = "StartScene" },
	StartScene = { SceneEnd = "Battle", Abort = "Lobby" },
	Battle = { Finish = "EndScene", Abort = "Lobby" },
	EndScene = { SceneEnd = "Result", Abort = "Lobby" },
	Result = { ReturnToLobby = "Lobby", Abort = "Lobby" },
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

return StagePhase
