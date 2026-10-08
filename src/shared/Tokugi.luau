--!strict
-- 特技ツリーによる成長の計算。ツリーの定義と巻物の数は Config.luau の Tokugi 節にあり、
-- 記録の保存は TokugiService（PlayerStore）が持つ。Roblox の API は使わない。
--
-- - 記録はキャラクターごとに、これまでに得た巻物の合計（makimono）と、覚えた特技の ID（tokugi）を持つ。どちらも増えるだけ
-- - 使える巻物は、得た巻物の合計から、覚えた特技（ツリーにあるもの）の巻物の数を引いた数。0 未満にはしない
-- - 記録は変更（Change。巻物を得た、特技を覚えた）を当てて進める（apply）。保存は、保存済みの記録に保存していない変更を
--   当てて書くので、読み込みに失敗したまま保存しても記録は消えない（巻物は足し、特技は和集合になる）
-- - ツリーに無いキャラクターと特技も記録から消さない（特技を外した後に戻しても記録が残るように）。
--   ツリーに無い特技は、補正にも使った巻物にも数えない
-- - 覚えられるのは、ロビーのフェーズの待機中でない人が、記録を読めた後に、ツリーにあり、まだ覚えておらず、
--   前提をすべて覚えていて、巻物が足りる特技だけ（checkLearn）
-- - 補正は、覚えた特技の補正を能力値ごとにまとめる（足す値は合計、掛ける値は積。Stats.compute で足しても結果は同じ）
-- - 渡す巻物の数は、撃破数を Makimono.Gekihasu で割って切り捨てた数（上限 GekihasuMax）に、勝ちなら Shori を足した数
-- - Config の節は引数で差し替えられる（テスト用）。省くと Config.Tokugi を使う

local Characters = require("./Characters")
local Config = require("./Config")
local RemoteSchema = require("./RemoteSchema")
local SelectionRules = require("./SelectionRules")
local Stats = require("./Stats")

export type Definition = Config.TokugiDef
export type Tree = { Definition }

-- キャラクター1人の記録
export type CharacterRecord = {
	-- これまでに得た巻物の合計（増えるだけ）
	makimono: number,
	-- 覚えた特技の ID（ID の順。増えるだけ）
	tokugi: { string },
}

-- 保存データ
export type Data = {
	-- 保存データの版
	version: number,
	-- キャラクター ID から引く記録
	characters: { [string]: CharacterRecord },
}

-- 記録の変更。character の記録に、makimono（得た巻物の数）を足し、tokugi（覚えた特技）を加える
export type Change = {
	character: string,
	makimono: number?,
	tokugi: string?,
}

-- 本人のクライアントへ送る特技の記録（Remotes.TokugiState）
export type State = {
	-- 保存済みの記録を読めたか。読めるまで特技は覚えられない
	loaded: boolean,
	data: Data,
}

-- 特技ごとの様子
export type Status =
	"Learned" -- 覚えた
	| "Zentei" -- 前提の特技をまだ覚えていない
	| "MakimonoShort" -- 巻物が足りない
	| "Learnable" -- 覚えられる

local Tokugi = {}

-- 今の保存データの版
Tokugi.VERSION = 1

-- 特技の画面に出す名前。特技 ID で引く（同じ ID は、どのキャラクターのツリーでも同じ名前）
Tokugi.names = {
	Goriki1 = "剛力・壱",
	Goriki2 = "剛力・弐",
	Goriki3 = "剛力・参",
	Ganken1 = "頑健・壱",
	Ganken2 = "頑健・弐",
	Teppeki1 = "鉄壁・壱",
	Kenkyaku1 = "健脚・壱",
	Hayawaza1 = "早業・壱",
	Hayawaza2 = "早業・弐",
	Gokui = "極意",
} :: { [string]: string }

-- 様子ごとの、覚える要求を拒否する理由。覚えられる特技は拒否しない
local STATUS_REJECTS: { [Status]: RemoteSchema.RejectReason } = {
	Learned = "TokugiLearned",
	Zentei = "TokugiZentei",
	MakimonoShort = "MakimonoShort",
}

local function paramsOf(params: Config.TokugiSection?): Config.TokugiSection
	return params or Config.Tokugi
end

-- 重なりを除いて ID の順に並べる
local function sorted(ids: { string }): { string }
	local seen: { [string]: boolean } = {}
	local result = {}
	for _, id in ids do
		if not seen[id] then
			seen[id] = true
			table.insert(result, id)
		end
	end
	table.sort(result)
	return result
end

-- キャラクターの特技ツリー。ツリーの無いキャラクターは空
function Tokugi.treeOf(characterId: string, params: Config.TokugiSection?): Tree
	return paramsOf(params).Trees[characterId] or {}
end

-- ツリーの中の特技。無ければ nil
function Tokugi.find(tree: Tree, tokugiId: string): Definition?
	for _, definition in tree do
		if definition.Id == tokugiId then
			return definition
		end
	end
	return nil
end

-- 特技の名前。表に無い ID はそのまま返す
function Tokugi.nameOf(tokugiId: string): string
	return Tokugi.names[tokugiId] or tokugiId
end

-- 先に覚えておく特技の ID
function Tokugi.zenteiOf(definition: Definition): { string }
	return definition.Zentei or {}
end

-- 小数第1位までの数の文字列。整数なら小数点を付けない
local function formatNumber(value: number): string
	return tostring(math.round(value * 10) / 10)
end

local function signed(value: number): string
	return if value >= 0 then `+{formatNumber(value)}` else `-{formatNumber(-value)}`
end

-- 特技の効果の文（「攻撃 +3%」「防御 +2」）。足す値と掛ける値の両方があれば読点でつなぐ
function Tokugi.describe(definition: Definition): string
	local name = Stats.displayNames[definition.Stat :: Stats.StatName] or definition.Stat
	local parts = {}
	if definition.Add then
		table.insert(parts, signed(definition.Add))
	end
	if definition.Multiply then
		table.insert(parts, `{signed((definition.Multiply - 1) * 100)}%`)
	end
	return `{name} {table.concat(parts, "、")}`
end

-- 特技ごとの段（前提の深さ）。前提の無い特技が 1 で、前提のある特技は、一番深い前提の次の段。
-- ツリーに無い前提と、めぐっている前提は数えない
function Tokugi.depthsOf(tree: Tree): { [string]: number }
	local byId: { [string]: Definition } = {}
	for _, definition in tree do
		byId[definition.Id] = definition
	end
	local depths: { [string]: number } = {}
	local visiting: { [string]: boolean } = {}
	local function depthOf(id: string): number
		local known = depths[id]
		if known then
			return known
		end
		local definition = byId[id]
		if not definition or visiting[id] then
			return 0
		end
		visiting[id] = true
		local deepest = 0
		for _, zentei in Tokugi.zenteiOf(definition) do
			deepest = math.max(deepest, depthOf(zentei))
		end
		visiting[id] = nil
		depths[id] = deepest + 1
		return deepest + 1
	end
	for _, definition in tree do
		depthOf(definition.Id)
	end
	return depths
end

-- ツリーの定義の誤りを文で返す。誤りが無ければ空。
-- ID の重なり、名前の無い特技、能力値の名前、補正の無い特技、巻物の数、ツリーに無い前提、前提のめぐりを見る
function Tokugi.validateTree(tree: Tree): { string }
	local problems = {}
	local byId: { [string]: Definition } = {}
	for _, definition in tree do
		local id = definition.Id
		if byId[id] then
			table.insert(problems, `{id}: ID が重なっている`)
		end
		byId[id] = definition
		if not Tokugi.names[id] then
			table.insert(problems, `{id}: 名前が Tokugi.names に無い`)
		end
		if not Stats.isName(definition.Stat) then
			table.insert(problems, `{id}: 能力値 {definition.Stat} は Stats.names に無い`)
		end
		if definition.Add == nil and definition.Multiply == nil then
			table.insert(problems, `{id}: 補正（Add か Multiply）が無い`)
		end
		if definition.Multiply and definition.Multiply <= 0 then
			table.insert(problems, `{id}: 掛ける値 {definition.Multiply} が 0 以下`)
		end
		local makimono = definition.Makimono
		if makimono < 1 or makimono ~= math.floor(makimono) then
			table.insert(problems, `{id}: 巻物の数 {makimono} が1以上の整数でない`)
		end
	end
	for _, definition in tree do
		for _, zentei in Tokugi.zenteiOf(definition) do
			if not byId[zentei] then
				table.insert(problems, `{definition.Id}: 前提 {zentei} がツリーに無い`)
			end
		end
	end
	-- 前提をたどって、たどっている途中の特技に戻ったらめぐっている
	local VISITING, DONE = 1, 2
	local marks: { [string]: number } = {}
	local function visit(id: string)
		local definition = byId[id]
		if not definition or marks[id] == DONE then
			return
		end
		if marks[id] == VISITING then
			table.insert(problems, `{id}: 前提がめぐっている`)
			return
		end
		marks[id] = VISITING
		for _, zentei in Tokugi.zenteiOf(definition) do
			visit(zentei)
		end
		marks[id] = DONE
	end
	for _, definition in tree do
		visit(definition.Id)
	end
	return problems
end

-- 新規のプレイヤーの記録
function Tokugi.new(): Data
	return { version = Tokugi.VERSION, characters = {} }
end

-- キャラクターの記録。記録の無いキャラクターは、巻物も特技も無い記録
function Tokugi.recordOf(data: Data, characterId: string): CharacterRecord
	return data.characters[characterId] or { makimono = 0, tokugi = {} }
end

function Tokugi.isLearned(record: CharacterRecord, tokugiId: string): boolean
	return table.find(record.tokugi, tokugiId) ~= nil
end

-- 覚えた特技（ツリーにあるもの）の数
function Tokugi.learnedCount(record: CharacterRecord, tree: Tree): number
	local count = 0
	for _, definition in tree do
		if Tokugi.isLearned(record, definition.Id) then
			count += 1
		end
	end
	return count
end

-- 覚えた特技（ツリーにあるもの）に使った巻物の数
function Tokugi.spent(record: CharacterRecord, tree: Tree): number
	local total = 0
	for _, definition in tree do
		if Tokugi.isLearned(record, definition.Id) then
			total += definition.Makimono
		end
	end
	return total
end

-- 使える巻物の数。得た巻物の合計から、覚えた特技に使った数を引く。0 未満にはしない
function Tokugi.available(record: CharacterRecord, tree: Tree): number
	return math.max(record.makimono - Tokugi.spent(record, tree), 0)
end

-- 記録に変更を1つ当てた記録を返す。巻物は足し（1 未満と端数は捨てる）、特技は覚えた特技に加える。
-- 何も変わらなければ data をそのまま返す。引数は書き換えない
function Tokugi.apply(data: Data, change: Change): Data
	local before = Tokugi.recordOf(data, change.character)
	local makimono = before.makimono
	local amount = change.makimono
	if amount and amount >= 1 and amount < math.huge then
		makimono += math.floor(amount)
	end
	local tokugi = before.tokugi
	local learned = change.tokugi
	if learned and not Tokugi.isLearned(before, learned) then
		local list = table.clone(before.tokugi)
		table.insert(list, learned)
		tokugi = sorted(list)
	end
	if makimono == before.makimono and tokugi == before.tokugi then
		return data
	end
	local characters = table.clone(data.characters)
	characters[change.character] = { makimono = makimono, tokugi = table.clone(tokugi) }
	return { version = data.version, characters = characters }
end

-- 0 以上の整数にする。数でない値・NaN・無限大は 0
local function countOf(value: unknown): number
	if type(value) ~= "number" or value ~= value or value == math.huge then
		return 0
	end
	return math.max(math.floor(value), 0)
end

local function stringsOf(value: unknown): { string }
	local result = {}
	if type(value) == "table" then
		for _, item in value :: { any } do
			if type(item) == "string" then
				table.insert(result, item)
			end
		end
	end
	return result
end

-- DataStore から読んだ値を記録にする。表でなければ nil を返す（新規として扱う）。
-- 欠けた項目と形の違う項目は空にし、文字列でない特技は捨てる。ツリーに無いキャラクターと特技は残す
function Tokugi.normalize(raw: unknown): Data?
	if type(raw) ~= "table" then
		return nil
	end
	local source = raw :: { [string]: any }
	local version = if type(source.version) == "number" then source.version else Tokugi.VERSION
	local characters: { [string]: CharacterRecord } = {}
	if type(source.characters) == "table" then
		for characterId, value in source.characters :: { [any]: any } do
			if type(characterId) == "string" and type(value) == "table" then
				characters[characterId] = {
					makimono = countOf(value.makimono),
					tokugi = sorted(stringsOf(value.tokugi)),
				}
			end
		end
	end
	return { version = version, characters = characters }
end

-- 特技の様子（覚えたか、前提と巻物が足りるか）。ツリーに無い特技は nil
function Tokugi.statusOf(record: CharacterRecord, tree: Tree, tokugiId: string): Status?
	local definition = Tokugi.find(tree, tokugiId)
	if not definition then
		return nil
	end
	if Tokugi.isLearned(record, tokugiId) then
		return "Learned"
	end
	for _, zentei in Tokugi.zenteiOf(definition) do
		if not Tokugi.isLearned(record, zentei) then
			return "Zentei"
		end
	end
	if Tokugi.available(record, tree) < definition.Makimono then
		return "MakimonoShort"
	end
	return "Learnable"
end

-- 特技を覚えられるか。覚えられるなら nil、覚えられないなら拒否の理由を返す。
-- requester は覚える人の立場、loaded は保存済みの記録を読めたか、data はその人の記録。
-- 立場（ロビーのフェーズの待機中でない人か）、記録を読めたか、ツリーにあるか、まだ覚えていないか、前提、巻物の順に確かめる
function Tokugi.checkLearn(
	requester: SelectionRules.Requester,
	loaded: boolean,
	data: Data,
	characterId: string,
	tokugiId: string,
	params: Config.TokugiSection?
): RemoteSchema.RejectReason?
	local reject = SelectionRules.checkRequester(requester)
	if reject then
		return reject
	end
	if not loaded then
		return "TokugiNotLoaded"
	end
	local status = Tokugi.statusOf(Tokugi.recordOf(data, characterId), Tokugi.treeOf(characterId, params), tokugiId)
	if not status then
		return "UnknownTokugi"
	end
	return STATUS_REJECTS[status]
end

-- 覚えた特技（ツリーにあるもの）の補正を、能力値ごとにまとめて Stats.names の順に返す。
-- 足す値は合計、掛ける値は積にする
function Tokugi.modifiersOf(record: CharacterRecord, tree: Tree): { Stats.Modifier }
	local adds: { [string]: number } = {}
	local multiplies: { [string]: number } = {}
	for _, definition in tree do
		local stat = definition.Stat
		if Tokugi.isLearned(record, definition.Id) and Stats.isName(stat) then
			if definition.Add then
				adds[stat] = (adds[stat] or 0) + definition.Add
			end
			if definition.Multiply then
				multiplies[stat] = (multiplies[stat] or 1) * definition.Multiply
			end
		end
	end
	local modifiers: { Stats.Modifier } = {}
	for _, stat in Stats.names do
		local add = adds[stat]
		local multiply = multiplies[stat]
		if add or multiply then
			table.insert(modifiers, { stat = stat, add = add, multiply = multiply })
		end
	end
	return modifiers
end

-- 決着したときに渡す巻物の数。撃破数を Gekihasu で割って切り捨てた数（上限 GekihasuMax）に、勝ちなら Shori を足す
function Tokugi.makimonoFor(gekihasu: number, victory: boolean, params: Config.TokugiSection?): number
	local makimono = paramsOf(params).Makimono
	-- 数でない値（NaN）は比べると偽になるので、負の値と同じく 0 にする
	local count = if gekihasu > 0 then math.floor(gekihasu / makimono.Gekihasu) else 0
	count = math.min(count, makimono.GekihasuMax)
	if victory then
		count += makimono.Shori
	end
	return count
end

-- 特技ツリーの画面に出すキャラクター。選んでいるキャラクター、無ければ今のキャラクター（最後に出撃したキャラクター）の
-- うち、特技ツリーのあるもの。どちらも無ければ既定のキャラクター
function Tokugi.shownCharacter(selected: string?, current: string?, params: Config.TokugiSection?): string
	if selected and #Tokugi.treeOf(selected, params) > 0 then
		return selected
	end
	if current and #Tokugi.treeOf(current, params) > 0 then
		return current
	end
	return Characters.DEFAULT_ID
end

-- 届いた TokugiState を読む。形が違えば nil
function Tokugi.normalizeState(value: unknown): State?
	if type(value) ~= "table" then
		return nil
	end
	local source = value :: { [string]: unknown }
	local data = Tokugi.normalize(source.data)
	if not data then
		return nil
	end
	return { loaded = source.loaded == true, data = data }
end

return Tokugi
