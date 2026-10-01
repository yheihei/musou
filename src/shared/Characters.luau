--!strict
-- キャラクターの定義表。ID は NINJAMCP の英名、奥義の ID は NINJAMCP の忍術の英名、
-- 武器の ID は NINJAMCP の武器の英名（武器のモデルの名前。Buki.luau）を使う。
-- 能力値は Config.luau にキャラクター ID ごとに置く。
-- NPC の上忍と首領は、ステージの人選が決まったら足す。
-- 試験用ステージ（Test）にだけ出る本作の試験用の NPC は、ID を Shiken で始め、shiken を true にする。

export type ClanId = "Iga" | "Koga" | "Fuma" | "Saika"
export type Bukishu = "Shuriken" | "Katana"

export type Character = {
	id: string,
	displayName: string,
	clan: ClanId,
	-- 操作キャラクターかどうか。false は NPC としてだけ登場する
	playable: boolean,
	-- 武器種・武器・奥義は操作キャラクターには必ず持たせる
	bukishu: Bukishu?,
	buki: string?,
	ougi: string?,
	-- 試験用ステージにだけ出る試験用の NPC か
	shiken: boolean?,
}

local Characters = {}

Characters.clanIds = { "Iga", "Koga", "Fuma", "Saika" } :: { ClanId }

-- キャラクターを選ぶ前のプレイヤーが使うキャラクター
Characters.DEFAULT_ID = "Jin"

local definitions: { [string]: Character } = {
	Jin = {
		id = "Jin",
		displayName = "刃",
		clan = "Iga",
		playable = true,
		bukishu = "Shuriken",
		buki = "Shuriken",
		ougi = "Katon",
	},
	Torika = {
		id = "Torika",
		displayName = "酉花",
		clan = "Iga",
		playable = true,
		bukishu = "Shuriken",
		buki = "Shuriken",
		ougi = "PoisonShuriken",
	},
	Sekishusai = {
		id = "Sekishusai",
		displayName = "石舟斎",
		clan = "Iga",
		playable = true,
		bukishu = "Katana",
		buki = "Oodenta",
		ougi = "MutoDori",
	},
	KanaOni = {
		id = "KanaOni",
		displayName = "金鬼",
		clan = "Iga",
		playable = true,
		bukishu = "Katana",
		buki = "Gyuto",
		ougi = "Kinton",
	},
	Hayate = {
		id = "Hayate",
		displayName = "ハヤテ",
		clan = "Iga",
		playable = false,
	},
	-- 試験用ステージの敵軍の首領と上忍、味方軍の上忍
	ShikenShuryo = {
		id = "ShikenShuryo",
		displayName = "試験の首領",
		clan = "Fuma",
		playable = false,
		shiken = true,
	},
	ShikenJonin1 = {
		id = "ShikenJonin1",
		displayName = "試験の上忍1",
		clan = "Fuma",
		playable = false,
		shiken = true,
	},
	ShikenJonin2 = {
		id = "ShikenJonin2",
		displayName = "試験の上忍2",
		clan = "Fuma",
		playable = false,
		shiken = true,
	},
	ShikenJonin3 = {
		id = "ShikenJonin3",
		displayName = "試験の上忍3",
		clan = "Iga",
		playable = false,
		shiken = true,
	},
}

Characters.definitions = definitions

function Characters.get(id: string): Character?
	return definitions[id]
end

-- クランの操作キャラクターを ID の順に返す
function Characters.playableOf(clan: ClanId): { Character }
	local result = {}
	for _, character in definitions do
		if character.playable and character.clan == clan then
			table.insert(result, character)
		end
	end
	table.sort(result, function(a, b)
		return a.id < b.id
	end)
	return result
end

return Characters
