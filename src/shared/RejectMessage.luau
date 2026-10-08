--!strict
-- 選択・出撃・特技の習得を拒否した理由（RemoteSchema.RejectReason）の、画面に出す文。Roblox の API は使わない。

local Hikei = require("./Hikei")
local RemoteSchema = require("./RemoteSchema")

local RejectMessage = {}

local messages: { [RemoteSchema.RejectReason]: string } = {
	NotLobby = "ロビーにいる間だけ選べます",
	NotLeader = "リーダーだけができます",
	Waiting = "待機中は選べません。ステージが終わるまで待ってください",
	UnknownStory = "そのストーリーはありません",
	StoryNotReady = "このストーリーはまだ準備中です",
	StoryLocked = "リーダーがまだ開放していないストーリーです",
	UnknownStage = "そのステージはありません",
	StageLocked = "リーダーがまだ開放していないステージです",
	StageNotSelected = "先にリーダーがステージを選びます",
	UnknownCharacter = "そのキャラクターはいません",
	NotPlayable = "このキャラクターは選べません",
	OtherClan = "このストーリーのクランのキャラクターではありません",
	NpcInStage = "このステージに NPC として登場するので選べません",
	Shuryo = "首領は選べません",
	CharacterTaken = "ほかのメンバーが選んでいます",
	UnknownHikei = "その秘計はありません",
	HikeiDuplicate = "同じ秘計は2枚持ち込めません",
	HikeiTaken = "ほかのメンバーが選んでいます",
	HikeiLimit = `秘計は {Hikei.MOCHIKOMI_MAX} 枚まで持ち込めます`,
	HikeiNotLoaded = "秘計の記録を読み込んでいます。少し待ってください",
	HikeiNotLearned = "まだ覚えていない秘計です",
	MembersNotReady = "キャラクターを選んでいないメンバーがいます",
	KukakuMissing = "このステージの場所がまだプレースにありません",
	TokugiNotLoaded = "特技の記録を読み込んでいます。少し待ってください",
	UnknownTokugi = "その特技はありません",
	TokugiLearned = "その特技はもう覚えています",
	TokugiZentei = "先に前提の特技を覚えてください",
	MakimonoShort = "巻物が足りません",
}

-- 拒否の理由の文。表に無い理由はそのまま返す
function RejectMessage.of(reason: string): string
	return messages[reason :: RemoteSchema.RejectReason] or reason
end

RejectMessage.messages = messages

return RejectMessage
