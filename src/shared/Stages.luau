--!strict
-- ストーリーとステージの定義表。ステージ選択・キャラクター選択・進行の保存が共通で引く。
-- ストーリーはクランごとに1本なので、クラン ID で表す。首領はこの表にだけ持つ。
-- イベントシーンの ID は、各シーンを作る issue で登録する。
-- 試験用ステージ（shiken）はストーリーに属さず、順番を 0 にする。進行（開放とクリア）には出さない。
-- 出撃前の画面には、SHIKEN_ENTRY の間だけ「開発確認用」として出す（#117。ストーリーのステージとは分けて並べる）。

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
	-- 試験用ステージか。ストーリーに属さず、進行に出さない。出撃前の画面には開発確認用として出す（SHIKEN_ENTRY）
	shiken: boolean?,
	-- 拠点の範囲に軍の色の板と、拠点の名前と耐久を出すか（建物の無い区画で、拠点を見て分かるように）
	kyotenBan: boolean?,
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
		-- 区画は平らな床だけなので、拠点の範囲を板で見せる
		kyotenBan = true,
	},
}

Stages.definitions = definitions

-- 出撃前の画面に、試験用ステージを「開発確認用」として出すか（#117）。
-- 配置の準備ができたストーリーのステージが無い間、敵と拠点のある戦場へ通常の入口から出られるようにする。
-- 選べるのはリーダーで、開放の有無を問わない。一般公開（#163）の前に false にする
Stages.SHIKEN_ENTRY = true

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

-- クランの試験用ステージ（出撃前の画面の開発確認用の欄に、そのクランのストーリーと一緒に出す）。ID の順
function Stages.shikenOf(clan: ClanId): { Stage }
	local result = {}
	for _, stage in definitions do
		if stage.clan == clan and stage.shiken then
			table.insert(result, stage)
		end
	end
	table.sort(result, function(a, b)
		return a.id < b.id
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
