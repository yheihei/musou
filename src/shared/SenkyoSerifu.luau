--!strict
-- 戦況の台詞（戦闘中に、戦況の変化をきっかけに画面の端に出す台詞）の発火の表と、出す台詞を選ぶ計算。
-- 文は Serifu.luau の表に台詞 ID で置き、ここには台詞 ID・きっかけ（kikkake）と条件・話者・表情をステージごとに置く。
-- サーバーの SenkyoSerifuService が戦況の変化を Henka にして pick に渡し、選んだ台詞を SerifuService.play で出す。
-- 数値は Config.luau の SenkyoSerifu 節にある。Roblox の API は使わない。
--
-- - どの台詞も1回のステージで1回だけ出す（played）
-- - 話者が操作キャラクターの台詞（差し込み）は、そのキャラクターで出撃している人がいるときだけ出す
-- - 1つの変化に複数の台詞が合えば、表の順にすべて出す（画面は順番待ちで1本ずつ出す）
--
-- | kikkake | 戦況の変化 | 条件に使うフィールド |
-- |---|---|---|
-- | Kaishi | 戦闘のフェーズが始まった | なし |
-- | Seiatsu | 軍 gun が拠点を制圧した | gun |
-- | Koritsu | 軍 gun の拠点が孤立した | gun |
-- | Sekkin | 相手の軍の部隊が、軍 gun の拠点に近づいた（中心から SekkinRange 以内） | gun、honjin か shubi、butaiJonin（省くとどの部隊でも） |
-- | TaikyuHanbun | 軍 gun の拠点の耐久が上限の HanbunRate を切った | gun、honjin か shubi |
-- | Oshi | 上忍 jonin が率いる部隊が交戦で押されている（交戦の損害が相手より OshiMargin 以上多い） | jonin |
-- | Hikei | 上忍か首領 jonin が秘計 hikei を使った | jonin、hikei |
-- | Kishu | 上忍か首領 jonin の伏兵部隊が奇襲した | jonin |
-- | Gekiha | 上忍か首領 jonin が倒れた。jonin の代わりに gun を置くと、軍 gun の上忍（首領を除く）が倒れたとき | jonin か gun、by（省くと倒した人によらない） |
-- | Shutsugen | 上忍か首領 jonin が個体として姿を現した | jonin |
-- | TairyokuHanbun | 上忍か首領 jonin の体力が上限の HanbunRate を切った（倒れたときは除く） | jonin |
-- | Nokori | 戦闘の残り時間が seconds 秒を切った | seconds |
-- | Heiryoku | 兵力が value まで減った | value |
--
-- - 拠点は、honjin を true にすると軍 gun の本陣、shubi に上忍のキャラクター ID を置くと、配置でその上忍の部隊が始まる拠点
--   （担当の拠点。令の守る拠点など）を指す
-- - by は、倒した出撃メンバーが使っているキャラクターの ID。操作キャラクターの差し込み（刃が敵の上忍を倒したなど）に使う

local Characters = require("./Characters")
local Config = require("./Config")
local Gun = require("./Gun")
local Hikei = require("./Hikei")
local RemoteSchema = require("./RemoteSchema")
local Serifu = require("./Serifu")
local Stages = require("./Stages")

export type Kikkake =
	"Kaishi"
	| "Seiatsu"
	| "Koritsu"
	| "Sekkin"
	| "TaikyuHanbun"
	| "Oshi"
	| "Hikei"
	| "Kishu"
	| "Gekiha"
	| "Shutsugen"
	| "TairyokuHanbun"
	| "Nokori"
	| "Heiryoku"

-- 発火の表の1行
export type Entry = {
	-- 台詞 ID（Serifu.luau の表の ID）
	id: string,
	kikkake: Kikkake,
	-- 話者のキャラクター ID と表情
	speaker: string,
	hyojo: RemoteSchema.Hyojo,
	-- 条件（kikkake ごとに使うものだけを置く。上の表）
	gun: Gun.Gun?,
	honjin: boolean?,
	shubi: string?,
	butaiJonin: string?,
	jonin: string?,
	hikei: string?,
	by: string?,
	seconds: number?,
	value: number?,
}

-- 戦況の変化。サーバーが拾って pick に渡す
export type Henka = {
	kikkake: Kikkake,
	-- 変化の軍。Seiatsu は制圧した軍、Koritsu・Sekkin・TaikyuHanbun は拠点の軍、Gekiha は倒れた上忍の軍
	gun: Gun.Gun?,
	-- 拠点が本陣か（Sekkin・TaikyuHanbun）
	honjin: boolean?,
	-- 拠点を担当する上忍（配置でその拠点から始まる部隊を率いる上忍）のキャラクター ID（Sekkin・TaikyuHanbun）
	shubi: { string }?,
	-- 近づいた部隊を率いる上忍（Sekkin）。率いる上忍のいない部隊は nil
	butaiJonin: string?,
	-- 上忍か首領のキャラクター ID（Oshi・Hikei・Kishu・Gekiha・Shutsugen・TairyokuHanbun）
	jonin: string?,
	-- 倒れたのが首領か（Gekiha）
	shuryo: boolean?,
	-- 秘計 ID（Hikei）
	hikei: string?,
	-- 倒した出撃メンバーのキャラクター ID（Gekiha）。プレイヤーが倒していなければ nil
	by: string?,
	-- 交戦を始めてからの、自分の部隊と相手の部隊の交戦の損害（Oshi）
	songai: number?,
	aiteSongai: number?,
	-- 変わる前と後の値（TaikyuHanbun は耐久、TairyokuHanbun は体力、Nokori は残り秒数、Heiryoku は兵力）と、上限
	before: number?,
	after: number?,
	max: number?,
}

export type Params = Config.SenkyoSerifuSection

local SenkyoSerifu = {}

SenkyoSerifu.kikkakeList = {
	"Kaishi",
	"Seiatsu",
	"Koritsu",
	"Sekkin",
	"TaikyuHanbun",
	"Oshi",
	"Hikei",
	"Kishu",
	"Gekiha",
	"Shutsugen",
	"TairyokuHanbun",
	"Nokori",
	"Heiryoku",
} :: { Kikkake }

local definitions: { [string]: { Entry } } = {
	-- 伊賀第1ステージ（docs/story/iga-1.md の戦闘中の台詞の下書き）。確定版（#14）で文と人選が変わったら直す。
	-- 話者と条件が NPC の上忍と首領（令・餡音・紫苑・アトザ・アウン・呂屯・断）の台詞は、人選が決まって
	-- Characters.luau に足してから置く（#117）。今はハヤテと操作キャラクターの台詞だけ
	Iga1 = {
		{ id = "Iga1B01", kikkake = "Kaishi", speaker = "Hayate", hyojo = "Tsujo" },
		{ id = "Iga1B02", kikkake = "Seiatsu", gun = "Tekigun", speaker = "Hayate", hyojo = "Ikari" },
		{ id = "Iga1B05", kikkake = "Koritsu", gun = "Mikatagun", speaker = "Hayate", hyojo = "Odoroki" },
		{ id = "Iga1B15", kikkake = "Gekiha", gun = "Tekigun", speaker = "Hayate", hyojo = "Yorokobi" },
		{
			id = "Iga1B20",
			kikkake = "Sekkin",
			gun = "Mikatagun",
			honjin = true,
			speaker = "Hayate",
			hyojo = "Odoroki",
		},
		{ id = "Iga1B21", kikkake = "TairyokuHanbun", jonin = "Hayate", speaker = "Hayate", hyojo = "Kumon" },
		{ id = "Iga1B22", kikkake = "Nokori", seconds = 600, speaker = "Hayate", hyojo = "Tsujo" },
		{ id = "Iga1B23", kikkake = "Nokori", seconds = 300, speaker = "Hayate", hyojo = "Ikari" },
		{ id = "Iga1B24", kikkake = "Heiryoku", value = 1, speaker = "Hayate", hyojo = "Kumon" },
		-- 操作キャラクターの差し込み。そのキャラクターで出撃した人が、敵軍の上忍を初めて倒したとき
		{ id = "Iga1BJ1", kikkake = "Gekiha", gun = "Tekigun", by = "Jin", speaker = "Jin", hyojo = "Tsujo" },
		{
			id = "Iga1BT1",
			kikkake = "Gekiha",
			gun = "Tekigun",
			by = "Torika",
			speaker = "Torika",
			hyojo = "Tsujo",
		},
		{
			id = "Iga1BS1",
			kikkake = "Gekiha",
			gun = "Tekigun",
			by = "Sekishusai",
			speaker = "Sekishusai",
			hyojo = "Yorokobi",
		},
		{
			id = "Iga1BK1",
			kikkake = "Gekiha",
			gun = "Tekigun",
			by = "KanaOni",
			speaker = "KanaOni",
			hyojo = "Yorokobi",
		},
	},
	-- 試験用ステージ。どのきっかけも1本ずつ確かめられるよう、伊賀第1ステージの台本のきっかけを試験用の上忍と首領に置き換えた。
	-- 味方軍は首領ハヤテと上忍3（西の Mikata1）、敵軍は首領と上忍1（中央の Teki1）・上忍2（東の Teki2）
	Test = {
		{ id = "ShikenKaishi", kikkake = "Kaishi", speaker = "Hayate", hyojo = "Tsujo" },
		{ id = "ShikenSeiatsuTeki", kikkake = "Seiatsu", gun = "Tekigun", speaker = "Hayate", hyojo = "Ikari" },
		{
			id = "ShikenSeiatsuMikata",
			kikkake = "Seiatsu",
			gun = "Mikatagun",
			speaker = "ShikenJonin3",
			hyojo = "Yorokobi",
		},
		{
			id = "ShikenRakuseki",
			kikkake = "Hikei",
			jonin = "ShikenJonin1",
			hikei = "Rakuseki",
			speaker = "ShikenJonin1",
			hyojo = "Yorokobi",
		},
		{ id = "ShikenKoritsu", kikkake = "Koritsu", gun = "Mikatagun", speaker = "Hayate", hyojo = "Odoroki" },
		{
			id = "ShikenSekkinNishi",
			kikkake = "Sekkin",
			gun = "Mikatagun",
			shubi = "ShikenJonin3",
			butaiJonin = "ShikenJonin1",
			speaker = "ShikenJonin1",
			hyojo = "Ikari",
		},
		{
			id = "ShikenTaikyuNishi",
			kikkake = "TaikyuHanbun",
			gun = "Mikatagun",
			shubi = "ShikenJonin3",
			speaker = "ShikenJonin3",
			hyojo = "Kumon",
		},
		{ id = "ShikenOshi", kikkake = "Oshi", jonin = "ShikenJonin3", speaker = "Hayate", hyojo = "Odoroki" },
		{
			id = "ShikenGekihaJonin3",
			kikkake = "Gekiha",
			jonin = "ShikenJonin3",
			speaker = "ShikenJonin3",
			hyojo = "Kumon",
		},
		{
			id = "ShikenGekihaJonin1",
			kikkake = "Gekiha",
			jonin = "ShikenJonin1",
			speaker = "ShikenJonin1",
			hyojo = "Kumon",
		},
		{
			id = "ShikenGekihaJonin2",
			kikkake = "Gekiha",
			jonin = "ShikenJonin2",
			speaker = "ShikenJonin2",
			hyojo = "Kumon",
		},
		{ id = "ShikenGekihaTeki", kikkake = "Gekiha", gun = "Tekigun", speaker = "Hayate", hyojo = "Yorokobi" },
		{
			id = "ShikenShutsugen",
			kikkake = "Shutsugen",
			jonin = "ShikenShuryo",
			speaker = "ShikenShuryo",
			hyojo = "Ikari",
		},
		{
			id = "ShikenShuryoHanbun",
			kikkake = "TairyokuHanbun",
			jonin = "ShikenShuryo",
			speaker = "ShikenShuryo",
			hyojo = "Odoroki",
		},
		{
			id = "ShikenKishinka",
			kikkake = "Hikei",
			jonin = "ShikenShuryo",
			hikei = "Kishinka",
			speaker = "ShikenShuryo",
			hyojo = "Ikari",
		},
		{
			id = "ShikenKishu",
			kikkake = "Kishu",
			jonin = "ShikenShuryo",
			speaker = "ShikenShuryo",
			hyojo = "Tsujo",
		},
		{
			id = "ShikenSekkinHonjin",
			kikkake = "Sekkin",
			gun = "Mikatagun",
			honjin = true,
			speaker = "Hayate",
			hyojo = "Odoroki",
		},
		{
			id = "ShikenHayateHanbun",
			kikkake = "TairyokuHanbun",
			jonin = "Hayate",
			speaker = "Hayate",
			hyojo = "Kumon",
		},
		{ id = "ShikenNokori10", kikkake = "Nokori", seconds = 600, speaker = "Hayate", hyojo = "Tsujo" },
		{ id = "ShikenNokori5", kikkake = "Nokori", seconds = 300, speaker = "Hayate", hyojo = "Ikari" },
		{ id = "ShikenHeiryoku", kikkake = "Heiryoku", value = 1, speaker = "Hayate", hyojo = "Kumon" },
		{ id = "ShikenGekihaJin", kikkake = "Gekiha", gun = "Tekigun", by = "Jin", speaker = "Jin", hyojo = "Tsujo" },
		{
			id = "ShikenGekihaTorika",
			kikkake = "Gekiha",
			gun = "Tekigun",
			by = "Torika",
			speaker = "Torika",
			hyojo = "Tsujo",
		},
		{
			id = "ShikenGekihaSekishusai",
			kikkake = "Gekiha",
			gun = "Tekigun",
			by = "Sekishusai",
			speaker = "Sekishusai",
			hyojo = "Yorokobi",
		},
		{
			id = "ShikenGekihaKanaOni",
			kikkake = "Gekiha",
			gun = "Tekigun",
			by = "KanaOni",
			speaker = "KanaOni",
			hyojo = "Yorokobi",
		},
	},
}

SenkyoSerifu.definitions = definitions

-- ステージの発火の表。表の無いステージは空
function SenkyoSerifu.entriesOf(stageId: string?): { Entry }
	if stageId == nil then
		return {}
	end
	return definitions[stageId] or {}
end

-- 値が before から after へ変わる間に、境 threshold を上から下へ越えたか（before は境以上、after は境より小さい）
function SenkyoSerifu.crossedBelow(before: number?, after: number?, threshold: number): boolean
	if before == nil or after == nil then
		return false
	end
	return before >= threshold and after < threshold
end

-- 拠点の条件（本陣か、担当の上忍の拠点か）が変化の拠点に合うか
local function kyotenMatches(entry: Entry, henka: Henka): boolean
	if entry.honjin then
		return henka.honjin == true
	end
	local shubi = entry.shubi
	return shubi ~= nil and henka.shubi ~= nil and table.find(henka.shubi, shubi) ~= nil
end

-- 発火の表の1行が、変化に合うか
function SenkyoSerifu.matches(entry: Entry, henka: Henka, params: Params?): boolean
	local p = params or Config.SenkyoSerifu
	local kikkake = entry.kikkake
	if kikkake ~= henka.kikkake then
		return false
	end
	if kikkake == "Kaishi" then
		return true
	elseif kikkake == "Seiatsu" or kikkake == "Koritsu" then
		return entry.gun == henka.gun
	elseif kikkake == "Sekkin" then
		if entry.gun ~= henka.gun or not kyotenMatches(entry, henka) then
			return false
		end
		return entry.butaiJonin == nil or entry.butaiJonin == henka.butaiJonin
	elseif kikkake == "TaikyuHanbun" then
		if entry.gun ~= henka.gun or not kyotenMatches(entry, henka) or henka.max == nil then
			return false
		end
		return SenkyoSerifu.crossedBelow(henka.before, henka.after, henka.max * p.HanbunRate)
	elseif kikkake == "Oshi" then
		local songai, aiteSongai = henka.songai, henka.aiteSongai
		if entry.jonin ~= henka.jonin or songai == nil or aiteSongai == nil then
			return false
		end
		return songai - aiteSongai >= p.OshiMargin
	elseif kikkake == "Hikei" then
		return entry.jonin == henka.jonin and entry.hikei == henka.hikei
	elseif kikkake == "Kishu" or kikkake == "Shutsugen" then
		return entry.jonin == henka.jonin
	elseif kikkake == "Gekiha" then
		if entry.by ~= nil and entry.by ~= henka.by then
			return false
		end
		if entry.jonin ~= nil then
			return entry.jonin == henka.jonin
		end
		return entry.gun ~= nil and entry.gun == henka.gun and henka.shuryo ~= true
	elseif kikkake == "TairyokuHanbun" then
		local after = henka.after
		if entry.jonin ~= henka.jonin or henka.max == nil or after == nil or after <= 0 then
			return false
		end
		return SenkyoSerifu.crossedBelow(henka.before, after, henka.max * p.HanbunRate)
	elseif kikkake == "Nokori" then
		local seconds = entry.seconds
		return seconds ~= nil and SenkyoSerifu.crossedBelow(henka.before, henka.after, seconds)
	elseif kikkake == "Heiryoku" then
		local value, before = entry.value, henka.before
		return value ~= nil and before ~= nil and before > value and henka.after == value
	end
	return false
end

-- 台詞を出してよいか。このステージでまだ出しておらず、話者が操作キャラクターなら、そのキャラクターで出撃した人がいる
function SenkyoSerifu.canPlay(entry: Entry, played: { [string]: boolean }, sortied: { [string]: boolean }): boolean
	if played[entry.id] then
		return false
	end
	local speaker = Characters.get(entry.speaker)
	if speaker and speaker.playable then
		return sortied[entry.speaker] == true
	end
	return true
end

-- 変化に合い、出してよい台詞を表の順に返す。played は書き換えない
function SenkyoSerifu.pick(
	entries: { Entry },
	henka: Henka,
	played: { [string]: boolean },
	sortied: { [string]: boolean },
	params: Params?
): { Entry }
	local result = {}
	for _, entry in entries do
		if SenkyoSerifu.matches(entry, henka, params) and SenkyoSerifu.canPlay(entry, played, sortied) then
			table.insert(result, entry)
		end
	end
	return result
end

-- 表の kikkake の台詞のうち、まだ出していないものがあるか（見回りで確かめるきっかけを省くのに使う）
function SenkyoSerifu.hasPending(entries: { Entry }, kikkake: Kikkake, played: { [string]: boolean }): boolean
	for _, entry in entries do
		if entry.kikkake == kikkake and not played[entry.id] then
			return true
		end
	end
	return false
end

-- kikkake ごとに、置かなければならない条件
local REQUIRED: { [Kikkake]: { string } } = {
	Kaishi = {},
	Seiatsu = { "gun" },
	Koritsu = { "gun" },
	Sekkin = { "gun" },
	TaikyuHanbun = { "gun" },
	Oshi = { "jonin" },
	Hikei = { "jonin", "hikei" },
	Kishu = { "jonin" },
	Gekiha = {},
	Shutsugen = { "jonin" },
	TairyokuHanbun = { "jonin" },
	Nokori = { "seconds" },
	Heiryoku = { "value" },
}

-- ステージの NPC（首領と NPC の上忍）のキャラクター ID
local function npcsOf(stage: Stages.Stage): { [string]: boolean }
	local result: { [string]: boolean } = {}
	for _, id in stage.npcs do
		result[id] = true
	end
	if stage.shuryo.mikatagun then
		result[stage.shuryo.mikatagun] = true
	end
	if stage.shuryo.tekigun then
		result[stage.shuryo.tekigun] = true
	end
	return result
end

-- 発火の表の誤りを並べる。誤りが無ければ空
function SenkyoSerifu.check(): { string }
	local problems = {}
	local seen: { [string]: string } = {}
	for stageId, entries in definitions do
		local stage = Stages.get(stageId)
		if not stage then
			table.insert(problems, `ステージ {stageId} は Stages.luau に無い`)
			continue
		end
		local npcs = npcsOf(stage)
		-- ステージに出る人（NPC と、そのストーリーのクランの操作キャラクター）か
		local function appears(id: string): boolean
			local character = Characters.get(id)
			if not character then
				return false
			end
			return npcs[id] == true or (character.playable and character.clan == stage.clan)
		end
		for index, entry in entries do
			local where = `{stageId} の {index} 行目（{entry.id}）`
			if seen[entry.id] then
				table.insert(problems, `{where} の台詞 ID は {seen[entry.id]} と重なる`)
			end
			seen[entry.id] = stageId
			if not Serifu.textOf(entry.id) then
				table.insert(problems, `{where} の文が Serifu.luau に無い`)
			end
			if not table.find(SenkyoSerifu.kikkakeList, entry.kikkake) then
				table.insert(problems, `{where} のきっかけ {tostring(entry.kikkake)} は無い`)
				continue
			end
			if not appears(entry.speaker) then
				table.insert(problems, `{where} の話者 {entry.speaker} はこのステージに出ない`)
			end
			if not table.find(RemoteSchema.hyojo, entry.hyojo) then
				table.insert(problems, `{where} の表情 {tostring(entry.hyojo)} は無い`)
			end
			for _, field in REQUIRED[entry.kikkake] do
				if (entry :: any)[field] == nil then
					table.insert(problems, `{where} に {field} が無い`)
				end
			end
			if entry.gun ~= nil and not table.find(Gun.list, entry.gun) then
				table.insert(problems, `{where} の軍 {tostring(entry.gun)} は無い`)
			end
			if
				(entry.kikkake == "Sekkin" or entry.kikkake == "TaikyuHanbun")
				and not entry.honjin
				and not entry.shubi
			then
				table.insert(problems, `{where} に拠点の条件（honjin か shubi）が無い`)
			end
			if entry.kikkake == "Gekiha" and entry.jonin == nil and entry.gun == nil then
				table.insert(problems, `{where} に倒れる上忍の条件（jonin か gun）が無い`)
			end
			for _, field in { "jonin", "shubi", "butaiJonin" } do
				local id = (entry :: any)[field]
				if id ~= nil and not npcs[id] then
					table.insert(problems, `{where} の {field} {id} はこのステージの NPC に無い`)
				end
			end
			if entry.by ~= nil then
				local character = Characters.get(entry.by)
				if not character or not character.playable or character.clan ~= stage.clan then
					table.insert(
						problems,
						`{where} の by {entry.by} はこのストーリーの操作キャラクターでない`
					)
				end
			end
			if entry.hikei ~= nil and not Hikei.get(entry.hikei) then
				table.insert(problems, `{where} の秘計 {entry.hikei} は無い`)
			end
		end
	end
	return problems
end

return SenkyoSerifu
