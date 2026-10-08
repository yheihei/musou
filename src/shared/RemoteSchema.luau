--!strict
-- ロビー・選択・特技・イベントシーン・台詞・結果・秘計の知らせで使う Remote の引数の型と検証関数。
-- RemoteEvent は default.project.json の ReplicatedStorage.Remotes に宣言する。
-- ハンドラは各機能で実装する。ここは型と、クライアントから届く値の検証だけを持つ。
--
-- | Remote | 向き | 引数 |
-- |---|---|---|
-- | SelectStory | C→S | ClanId（ストーリー） |
-- | SelectStage | C→S | StageId |
-- | SelectCharacter | C→S | CharacterId |
-- | SelectHikei | C→S | HikeiId、選ぶなら true・外すなら false |
-- | LearnTokugi | C→S | CharacterId、TokugiId（そのキャラクターの特技ツリーの特技） |
-- | Shutsugeki・Retry・ReturnToLobby | C→S | なし（リーダーだけ有効） |
-- | SkipEventScene | C→S | なし |
-- | PartyState | S→C | PartyState |
-- | SelectionRejected | S→C | RejectReason |
-- | PlayEventScene | S→C | EventSceneId、役者とカメラの位置（EventSceneService.Setting。作れなければ nil） |
-- | SkipCount | S→C | スキップした人数、全体の人数 |
-- | PlaySerifu | S→C | CharacterId、Hyojo、SerifuId |
-- | StageResult | S→C | StageResult |
-- | NotifyHikei | S→C | HikeiNotice.Notice（秘計の発動・打ち消し・期限切れ・失敗） |
-- | TokugiState | S→C | Tokugi.State（本人のキャラクターごとの巻物と覚えた特技） |

local Characters = require("./Characters")

local RemoteSchema = {}

-- クライアントから届く ID の長さの上限
RemoteSchema.MAX_ID_LENGTH = 64

-- ストーリーはクランごとに1本なので、クラン ID で表す
export type ClanId = Characters.ClanId
export type StageId = string
export type CharacterId = string
export type HikeiId = string
export type TokugiId = string
export type EventSceneId = string
export type SerifuId = string

export type Phase = "Lobby" | "EventScene" | "Battle" | "Result"
RemoteSchema.phases = { "Lobby", "EventScene", "Battle", "Result" } :: { Phase }

export type Hyojo = "Tsujo" | "Ikari" | "Odoroki" | "Yorokobi" | "Kumon"
RemoteSchema.hyojo = { "Tsujo", "Ikari", "Odoroki", "Yorokobi", "Kumon" } :: { Hyojo }

-- 選択と特技の習得を拒否した理由。制限ごとに別の値にする
export type RejectReason =
	"NotLobby" -- ロビーのフェーズ以外での選択
	| "NotLeader" -- リーダーだけができる操作
	| "Waiting" -- 待機中のプレイヤーの操作
	| "UnknownStory" -- 存在しないストーリー（4つのクランのどれでもない）
	| "StoryNotReady" -- ステージがまだ無いストーリー（準備中）
	| "StoryLocked" -- リーダーが開放したステージの無いストーリー
	| "UnknownStage" -- 存在しないステージ
	| "StageLocked" -- リーダーが開放していないステージ
	| "StageNotSelected" -- ステージを選ぶ前の選択
	| "UnknownCharacter" -- 存在しないキャラクター
	| "NotPlayable" -- 操作キャラクターではない
	| "OtherClan" -- ストーリーのクランに属さない
	| "NpcInStage" -- そのステージに NPC として登場する
	| "Shuryo" -- 首領
	| "CharacterTaken" -- パーティーの他のメンバーが選んでいる
	| "UnknownHikei" -- 存在しない秘計
	| "HikeiDuplicate" -- 同じ秘計を2枚持ち込もうとしている
	| "HikeiTaken" -- パーティーの他のメンバーが選んでいる
	| "HikeiLimit" -- 持ち込みの上限を超える
	| "MembersNotReady" -- キャラクターを選んでいないメンバーがいる
	| "KukakuMissing" -- ステージの区画か出撃地点がプレースに無い
	| "TokugiNotLoaded" -- 特技の記録をまだ読み込めていない
	| "UnknownTokugi" -- そのキャラクターの特技ツリーに無い特技
	| "TokugiLearned" -- もう覚えている特技
	| "TokugiZentei" -- 前提の特技をまだ覚えていない
	| "MakimonoShort" -- 巻物が足りない
RemoteSchema.rejectReasons = {
	"NotLobby",
	"NotLeader",
	"Waiting",
	"UnknownStory",
	"StoryNotReady",
	"StoryLocked",
	"UnknownStage",
	"StageLocked",
	"StageNotSelected",
	"UnknownCharacter",
	"NotPlayable",
	"OtherClan",
	"NpcInStage",
	"Shuryo",
	"CharacterTaken",
	"UnknownHikei",
	"HikeiDuplicate",
	"HikeiTaken",
	"HikeiLimit",
	"MembersNotReady",
	"KukakuMissing",
	"TokugiNotLoaded",
	"UnknownTokugi",
	"TokugiLearned",
	"TokugiZentei",
	"MakimonoShort",
} :: { RejectReason }

-- パーティーのメンバーごとの写し
export type MemberState = {
	userId: number,
	name: string,
	-- サーバーに入った順（1から）
	joinOrder: number,
	-- 出撃中に入り、ロビーで待っているか
	waiting: boolean,
	character: CharacterId?,
	-- 選んだ順の秘計
	hikei: { HikeiId },
}

-- パーティー全体の写し
export type PartyState = {
	phase: Phase,
	-- リーダーの UserId。誰もいないときは nil
	leader: number?,
	-- リーダーが選んでいるストーリー
	story: ClanId?,
	-- リーダーが選んでいるステージ
	stage: StageId?,
	-- リーダーが開放済みのステージ
	unlockedStages: { StageId },
	members: { MemberState },
}

-- 勝敗の理由
export type ResultReason =
	"TekigunShuryoGekiha" -- 勝利。敵軍の首領の撃破
	| "TekigunHonjinSeiatsu" -- 勝利。敵軍の本陣の制圧
	| "MikatagunHonjinKanraku" -- 敗北。味方軍の本陣の陥落
	| "MikatagunShuryoGekiha" -- 敗北。味方軍の首領の撃破
	| "HeiryokuZero" -- 敗北。兵力0の状態でプレイヤーが倒れた
	| "TimeUp" -- 敗北。時間切れ
RemoteSchema.resultReasons = {
	"TekigunShuryoGekiha",
	"TekigunHonjinSeiatsu",
	"MikatagunHonjinKanraku",
	"MikatagunShuryoGekiha",
	"HeiryokuZero",
	"TimeUp",
} :: { ResultReason }

export type MemberResult = {
	userId: number,
	name: string,
	gekihasu: number,
	-- このクリアで新しく開放したステージ
	newlyUnlocked: { StageId },
	-- 決着したときに使っていたキャラクター（巻物を渡したキャラクター）
	character: CharacterId,
	-- このステージで得た巻物の数
	makimono: number,
}

export type StageResult = {
	victory: boolean,
	reason: ResultReason,
	-- 戦闘のフェーズの経過時間（秒）
	elapsed: number,
	members: { MemberResult },
}

-- ReplicatedStorage.Remotes に宣言する RemoteEvent の名前（Action は Actions.luau が扱う）
RemoteSchema.clientToServer = {
	"SelectStory",
	"SelectStage",
	"SelectCharacter",
	"SelectHikei",
	"LearnTokugi",
	"Shutsugeki",
	"Retry",
	"ReturnToLobby",
	"SkipEventScene",
}
RemoteSchema.serverToClient = {
	"PartyState",
	"SelectionRejected",
	"PlayEventScene",
	"SkipCount",
	"PlaySerifu",
	"StageResult",
	"NotifyHikei",
	"TokugiState",
}

-- クライアントから届いた ID を受け付けるか。英数字と _ だけで、長さは1から上限まで
function RemoteSchema.isId(value: unknown): boolean
	return type(value) == "string"
		and #value > 0
		and #value <= RemoteSchema.MAX_ID_LENGTH
		and string.match(value, "^[%w_]+$") ~= nil
end

local function noArguments(): boolean
	return true
end

-- C→S の Remote ごとの検証関数。受け付けるなら true
RemoteSchema.validate = {
	SelectStory = function(clanId: unknown): boolean
		return RemoteSchema.isId(clanId)
	end,
	SelectStage = function(stageId: unknown): boolean
		return RemoteSchema.isId(stageId)
	end,
	SelectCharacter = function(characterId: unknown): boolean
		return RemoteSchema.isId(characterId)
	end,
	SelectHikei = function(hikeiId: unknown, selected: unknown): boolean
		return RemoteSchema.isId(hikeiId) and type(selected) == "boolean"
	end,
	LearnTokugi = function(characterId: unknown, tokugiId: unknown): boolean
		return RemoteSchema.isId(characterId) and RemoteSchema.isId(tokugiId)
	end,
	Shutsugeki = noArguments,
	Retry = noArguments,
	ReturnToLobby = noArguments,
	SkipEventScene = noArguments,
}

return RemoteSchema
