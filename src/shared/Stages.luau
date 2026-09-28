--!strict
-- ストーリーとステージの定義表。ステージ選択・キャラクター選択・進行の保存が共通で引く。
-- ストーリーはクランごとに1本なので、クラン ID で表す。首領はこの表にだけ持つ。
-- イベントシーンの ID は、各シーンを作る issue で登録する。

local Characters = require("./Characters")

export type ClanId = Characters.ClanId

export type EventScenes = {
	-- 開始のイベントシーン
	start: string?,
	-- 勝利時の終了のイベントシーン
	victory: string?,
	-- 敗北時のイベントシーン。無ければリザルトへ直行する
	defeat: string?,
}

export type Stage = {
	id: string,
	-- どのクランのストーリーか
	clan: ClanId,
	-- ストーリーの中の順番（1から）
	order: number,
	-- 次のステージ ID。ストーリーの最後は nil
	next: string?,
	-- 敵軍のクラン
	tekigun: ClanId,
	-- 両軍の首領のキャラクター ID。人選の確定前は nil
	shuryo: {
		mikatagun: string?,
		tekigun: string?,
	},
	-- 首領以外に NPC として登場するキャラクター ID。操作キャラクターとしては選べない
	npcs: { string },
	-- 区画名（Workspace.Stages の下のフォルダ名）
	kukaku: string,
	eventScenes: EventScenes,
}

local Stages = {}

local definitions: { [string]: Stage } = {
	Iga1 = {
		id = "Iga1",
		clan = "Iga",
		order = 1,
		next = nil,
		tekigun = "Fuma",
		shuryo = {
			mikatagun = "Hayate",
			tekigun = nil,
		},
		npcs = {},
		kukaku = "Iga1",
		eventScenes = {},
	},
}

Stages.definitions = definitions

function Stages.get(id: string): Stage?
	return definitions[id]
end

-- クランのストーリーの最初のステージ
function Stages.firstOf(clan: ClanId): Stage?
	for _, stage in definitions do
		if stage.clan == clan and stage.order == 1 then
			return stage
		end
	end
	return nil
end

-- 次のステージ。ストーリーの最後のステージと存在しない ID では nil
function Stages.nextOf(id: string): Stage?
	local stage = definitions[id]
	if not stage or not stage.next then
		return nil
	end
	return definitions[stage.next]
end

return Stages
