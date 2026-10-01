--!strict
-- 顔グラフィックの登録表。キャラクター ID と表情から、Roblox に登録した画像のアセット ID を引く。
-- 画像は assets/faces/<キャラクター ID の小文字>/<表情の小文字>.png にあり、作り方は assets/faces/prompt.md にある。
-- 会話窓（#34）と戦闘中の台詞（#35）が引く。Roblox の API は使わない。
--
-- - 表情は通常・怒り・驚き・喜び・苦悶の5つ（RemoteSchema.hyojo）
-- - 登録表に無いキャラクターは nil を返す。画面は顔の枠を出さない
-- - アセット ID は Studio MCP の upload_image で登録したときに返った値

local RemoteSchema = require("./RemoteSchema")

export type Hyojo = RemoteSchema.Hyojo

local KaoGraphic = {}

-- 画像の1辺の大きさ（ピクセル）
KaoGraphic.SIZE = 512

local definitions: { [string]: { [Hyojo]: number } } = {
	Jin = {
		Tsujo = 119667347166445,
		Ikari = 70492578027112,
		Odoroki = 136271718831238,
		Yorokobi = 97817610100666,
		Kumon = 112857274841376,
	},
	Torika = {
		Tsujo = 82026969171918,
		Ikari = 118437542947732,
		Odoroki = 119070938502325,
		Yorokobi = 87897845512891,
		Kumon = 115212740890933,
	},
	Sekishusai = {
		Tsujo = 107125516000592,
		Ikari = 100158050095444,
		Odoroki = 107691271205626,
		Yorokobi = 114367648551421,
		Kumon = 100927867442411,
	},
	KanaOni = {
		Tsujo = 81602607214033,
		Ikari = 86227335673744,
		Odoroki = 84442008101799,
		Yorokobi = 81486463291878,
		Kumon = 78794366940724,
	},
	Hayate = {
		Tsujo = 109200682444912,
		Ikari = 110115348955101,
		Odoroki = 76308810832846,
		Yorokobi = 98856510080429,
		Kumon = 74121253873201,
	},
}

KaoGraphic.definitions = definitions

-- キャラクターの表情の画像のアセット ID。登録表に無ければ nil
function KaoGraphic.get(characterId: string, hyojo: Hyojo): number?
	local images = definitions[characterId]
	return if images then images[hyojo] else nil
end

-- ImageLabel.Image に入れる画像の ID。登録表に無ければ nil
function KaoGraphic.imageOf(characterId: string, hyojo: Hyojo): string?
	local id = KaoGraphic.get(characterId, hyojo)
	return if id then `rbxassetid://{id}` else nil
end

-- リポジトリの中の画像の置き場所
function KaoGraphic.pathOf(characterId: string, hyojo: Hyojo): string
	return `assets/faces/{string.lower(characterId)}/{string.lower(hyojo)}.png`
end

return KaoGraphic
