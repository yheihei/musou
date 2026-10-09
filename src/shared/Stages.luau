--!strict
-- ストーリーとステージの定義表。ステージ選択・キャラクター選択・進行の保存が共通で引く。
-- ストーリーはクランごとに1本なので、クラン ID で表す。首領はこの表にだけ持つ。
-- イベントシーンの ID は、各シーンを作る issue で登録する。
-- 試験用ステージ（shiken）はストーリーに属さず、順番を 0 にする。選択画面と進行（開放とクリア）には出さない。

local Characters = require("./Characters")
local Gun = require("./Gun")

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
	-- 選択画面に出す名前
	displayName: string,
	-- どのクランのストーリーか
	clan: ClanId,
	-- ストーリーの中の順番（1から）。試験用ステージは 0
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
	-- 試験用ステージか。ストーリーに属さず、選択画面と進行に出さない
	shiken: boolean?,
}

local Stages = {}

local definitions: { [string]: Stage } = {
	Iga1 = {
		id = "Iga1",
		-- 台本の下書き（docs/story/iga-1.md）の題。確定版（#14）で変わったら直す
		displayName = "風魔襲来",
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
	-- 試験用ステージ。拠点5つの小さな戦場で、配置は Haichi.luau にある。窓口の Shutsugeki で出撃する
	Test = {
		id = "Test",
		displayName = "試験用ステージ",
		clan = "Iga",
		order = 0,
		next = nil,
		tekigun = "Fuma",
		shuryo = {
			mikatagun = "Hayate",
			tekigun = "ShikenShuryo",
		},
		npcs = { "ShikenJonin1", "ShikenJonin2", "ShikenJonin3" },
		kukaku = "Test",
		eventScenes = {},
		shiken = true,
	},
}

Stages.definitions = definitions

function Stages.get(id: string): Stage?
	return definitions[id]
end

-- ステージの軍のクラン。味方軍はストーリーのクラン、敵軍は敵軍のクラン
function Stages.clanOf(stage: Stage, gun: Gun.Gun): ClanId
	return if gun == "Mikatagun" then stage.clan else stage.tekigun
end

-- クランのストーリーの最初のステージ
function Stages.firstOf(clan: ClanId): Stage?
	for _, stage in definitions do
		if stage.clan == clan and stage.order == 1 and not stage.shiken then
			return stage
		end
	end
	return nil
end

-- クランのストーリーのステージを順番に返す。試験用ステージは入れない
function Stages.storyOf(clan: ClanId): { Stage }
	local result = {}
	for _, stage in definitions do
		if stage.clan == clan and not stage.shiken then
			table.insert(result, stage)
		end
	end
	table.sort(result, function(a, b)
		return a.order < b.order
	end)
	return result
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
