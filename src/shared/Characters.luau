--!strict
-- キャラクターの定義表。ID は NINJAMCP の英名、奥義の ID は NINJAMCP の忍術の英名を使う。
-- 能力値は Config.luau にキャラクター ID ごとに置く。
-- NPC の上忍と首領は、ステージの人選が決まったら足す。

export type ClanId = "Iga" | "Koga" | "Fuma" | "Saika"
export type Bukishu = "Shuriken" | "Katana"

export type Character = {
	id: string,
	displayName: string,
	clan: ClanId,
	-- 操作キャラクターかどうか。false は NPC としてだけ登場する
	playable: boolean,
	-- 武器種と奥義は操作キャラクターには必ず持たせる
	bukishu: Bukishu?,
	ougi: string?,
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
		ougi = "Katon",
	},
	Torika = {
		id = "Torika",
		displayName = "酉花",
		clan = "Iga",
		playable = true,
		bukishu = "Shuriken",
		ougi = "PoisonShuriken",
	},
	Sekishusai = {
		id = "Sekishusai",
		displayName = "石舟斎",
		clan = "Iga",
		playable = true,
		bukishu = "Katana",
		ougi = "MutoDori",
	},
	KanaOni = {
		id = "KanaOni",
		displayName = "金鬼",
		clan = "Iga",
		playable = true,
		bukishu = "Katana",
		ougi = "Kinton",
	},
	Hayate = {
		id = "Hayate",
		displayName = "ハヤテ",
		clan = "Iga",
		playable = false,
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
