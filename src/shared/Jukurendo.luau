--!strict
-- 秘計の系統と熟練度の計算。系統ごとの秘計と覚える熟練度、決着したときに足す熟練度は Config.luau の Jukurendo 節にあり、
-- 記録の保存は JukurendoService（PlayerStore）が持つ。Roblox の API は使わない。
--
-- - 系統は武勇・知略・堅牢の3つ。熟練度を上げる戦い方は、武勇が撃破（撃破数）、知略が拠点の制圧（制圧数）、
--   堅牢が救援（救援数）
-- - 記録は系統ごとの熟練度（これまでに得た合計）と、覚えた秘計の ID を持つ。どちらも増えるだけ
-- - 覚えた秘計は、記録の覚えた秘計に、熟練度が覚える値に達した秘計を合わせたもの（learned）。
--   覚える値が 0 の秘計は最初から覚えている
-- - 記録は変更（Change。熟練度を得た、秘計を覚えた、M1 から遊ぶ人かを確かめた）を当てて進める（apply）。
--   熟練度が覚える値に達した秘計は、記録の覚えた秘計にも加える（後で覚える値を上げても忘れない）
-- - 保存は、保存済みの記録に保存していない変更を当てて書くので、読み込みに失敗したまま保存しても記録は消えない
--   （熟練度は足し、覚えた秘計は和集合になる）
-- - 定義に無い系統と秘計も記録から消さない（外した後に戻しても記録が残るように）。覚えた秘計には数えない
-- - 決着したときに足す熟練度は、系統ごとに戦い方の数に Rate を掛けて切り捨て、Max までにした数（gainOf）
-- - M1 では全種類を最初から使えた。熟練度の記録がまだ無く、進行にクリア済みのステージがある人は、
--   M1 から遊んでいる人として M1 の8種を覚えている扱いにする（m1ChangeOf）。確かめたことは記録に残す
-- - Config の節は引数で差し替えられる（テスト用）。省くと Config.Jukurendo を使う

local Config = require("./Config")
local Hikei = require("./Hikei")

export type Keito = "Buyu" | "Chiryaku" | "Kenro"
export type KeitoDef = Config.KeitoDef

-- 保存データ
export type Data = {
	-- 保存データの版
	version: number,
	-- 系統 ID から引く熟練度（これまでに得た合計。増えるだけ）
	jukurendo: { [string]: number },
	-- 覚えた秘計の ID（ID の順。増えるだけ）。熟練度で覚えた秘計も入れる
	hikei: { string },
	-- M1 から遊ぶ人かを確かめたか（増えるだけ）
	m1Checked: boolean,
}

-- 記録の変更。jukurendo（系統 ID から引く、得た熟練度）を足し、hikei（覚えた秘計）を加え、
-- m1Checked が true なら M1 から遊ぶ人かを確かめたことにする
export type Change = {
	jukurendo: { [string]: number }?,
	hikei: { string }?,
	m1Checked: boolean?,
}

-- 本人のクライアントへ送る熟練度の記録（Remotes.JukurendoState）
export type State = {
	-- 保存済みの記録を読めたか
	loaded: boolean,
	data: Data,
}

-- 1回のステージの戦い方の数
export type Counts = {
	gekihasu: number,
	seiatsusu: number,
	kyuensu: number,
}

local Jukurendo = {}

-- 今の保存データの版
Jukurendo.VERSION = 1

-- 系統の並び。画面とリザルトもこの順に出す
Jukurendo.keitoList = { "Buyu", "Chiryaku", "Kenro" } :: { Keito }

-- 系統の名前
Jukurendo.names = {
	Buyu = "武勇",
	Chiryaku = "知略",
	Kenro = "堅牢",
} :: { [string]: string }

-- 系統の熟練度を上げる戦い方の名前
Jukurendo.sourceNames = {
	Buyu = "撃破",
	Chiryaku = "拠点の制圧",
	Kenro = "救援",
} :: { [string]: string }

-- 系統の熟練度を上げる戦い方の数の名前
Jukurendo.countNames = {
	Buyu = "撃破数",
	Chiryaku = "制圧数",
	Kenro = "救援数",
} :: { [string]: string }

-- M1 で最初から使えた秘計（M1 の8種）。M1 から遊んでいる人が覚えている扱いにする秘計で、後から秘計を足しても変えない
Jukurendo.M1_HIKEI = {
	"Fukuhei",
	"Rakuseki",
	"Daikakei",
	"Hyoroko",
	"Bakuhawana",
	"Chohatsu",
	"Kishinka",
	"Daikatsu",
} :: { string }

local function paramsOf(params: Config.JukurendoSection?): Config.JukurendoSection
	return params or Config.Jukurendo
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

-- 系統の定義。定義に無い系統は nil
function Jukurendo.keitoDef(keito: string, params: Config.JukurendoSection?): KeitoDef?
	return paramsOf(params).Keito[keito]
end

-- 秘計の系統と、覚える熟練度。どの系統にも無い秘計は nil
function Jukurendo.keitoOf(hikeiId: string, params: Config.JukurendoSection?): (string?, number?)
	for _, keito in Jukurendo.keitoList do
		local def = Jukurendo.keitoDef(keito, params)
		if def then
			for _, entry in def.Hikei do
				if entry.Id == hikeiId then
					return keito, entry.Jukurendo
				end
			end
		end
	end
	return nil, nil
end

-- 系統の熟練度を上げる戦い方の数
function Jukurendo.countOf(counts: Counts, keito: string): number
	if keito == "Buyu" then
		return counts.gekihasu
	elseif keito == "Chiryaku" then
		return counts.seiatsusu
	elseif keito == "Kenro" then
		return counts.kyuensu
	end
	return 0
end

-- 新規のプレイヤーの記録
function Jukurendo.new(): Data
	return { version = Jukurendo.VERSION, jukurendo = {}, hikei = {}, m1Checked = false }
end

-- 系統の熟練度。記録の無い系統は 0
function Jukurendo.jukurendoOf(data: Data, keito: string): number
	return data.jukurendo[keito] or 0
end

-- 熟練度が覚える値に達した秘計（ID の順）
local function reachedOf(jukurendo: { [string]: number }, params: Config.JukurendoSection?): { string }
	local result = {}
	for _, keito in Jukurendo.keitoList do
		local def = Jukurendo.keitoDef(keito, params)
		if def then
			local value = jukurendo[keito] or 0
			for _, entry in def.Hikei do
				if entry.Jukurendo <= value then
					table.insert(result, entry.Id)
				end
			end
		end
	end
	return sorted(result)
end

-- 覚えた秘計を設計の表の順（Hikei.selectable）に返す。記録の覚えた秘計と、熟練度が覚える値に達した秘計を合わせる。
-- 定義に無い秘計は入れない
function Jukurendo.learned(data: Data, params: Config.JukurendoSection?): { string }
	local set: { [string]: boolean } = {}
	for _, id in data.hikei do
		set[id] = true
	end
	for _, id in reachedOf(data.jukurendo, params) do
		set[id] = true
	end
	local result = {}
	for _, id in Hikei.selectable() do
		if set[id] then
			table.insert(result, id)
		end
	end
	return result
end

function Jukurendo.isLearned(data: Data, hikeiId: string, params: Config.JukurendoSection?): boolean
	return table.find(Jukurendo.learned(data, params), hikeiId) ~= nil
end

-- 最初から覚えている秘計（覚える熟練度が 0 の秘計）を設計の表の順に返す
function Jukurendo.initialHikei(params: Config.JukurendoSection?): { string }
	return Jukurendo.learned(Jukurendo.new(), params)
end

-- 系統で次に覚える秘計と、それを覚える熟練度。系統の秘計を覚える順に見て、まだ覚えていない最初の秘計。
-- すべて覚えていれば nil
function Jukurendo.nextOf(data: Data, keito: string, params: Config.JukurendoSection?): (string?, number?)
	local def = Jukurendo.keitoDef(keito, params)
	if not def then
		return nil, nil
	end
	local learned = Jukurendo.learned(data, params)
	for _, entry in def.Hikei do
		if not table.find(learned, entry.Id) then
			return entry.Id, entry.Jukurendo
		end
	end
	return nil, nil
end

-- 決着したときに系統へ足す熟練度（系統 ID から引く。すべての系統を入れ、上がらない系統は 0）。
-- 系統ごとに、戦い方の数に Rate を掛けて切り捨て、Max までにする。数が 0 以下か数でなければ 0
function Jukurendo.gainOf(counts: Counts, params: Config.JukurendoSection?): { [string]: number }
	local result: { [string]: number } = {}
	for _, keito in Jukurendo.keitoList do
		local def = Jukurendo.keitoDef(keito, params)
		local count = Jukurendo.countOf(counts, keito)
		local gain = 0
		-- 数でない値（NaN）は比べると偽になるので、0 以下と同じく 0 にする
		if def and count > 0 then
			gain = math.max(math.min(math.floor(count * def.Rate), def.Max), 0)
		end
		result[keito] = gain
	end
	return result
end

-- 記録に変更を1つ当てた記録を返す。熟練度は足し（1 未満と端数は捨てる）、秘計は覚えた秘計に加え、
-- 熟練度が覚える値に達した秘計も覚えた秘計に加える。M1 から遊ぶ人かを確かめたことは残す。
-- 何も変わらなければ data をそのまま返す。引数は書き換えない
function Jukurendo.apply(data: Data, change: Change, params: Config.JukurendoSection?): Data
	local jukurendo = data.jukurendo
	local gained = false
	for keito, amount in change.jukurendo or {} do
		if type(keito) == "string" and type(amount) == "number" and amount >= 1 and amount < math.huge then
			if not gained then
				jukurendo = table.clone(data.jukurendo)
				gained = true
			end
			jukurendo[keito] = (jukurendo[keito] or 0) + math.floor(amount)
		end
	end
	local added = {}
	local candidates = table.clone(change.hikei or {})
	local reached = reachedOf(jukurendo, params)
	table.move(reached, 1, #reached, #candidates + 1, candidates)
	for _, id in candidates do
		if type(id) == "string" and not table.find(data.hikei, id) then
			table.insert(added, id)
		end
	end
	local hikei = data.hikei
	if #added > 0 then
		local list = table.clone(data.hikei)
		table.move(added, 1, #added, #list + 1, list)
		hikei = sorted(list)
	end
	local m1Checked = data.m1Checked or change.m1Checked == true
	if not gained and hikei == data.hikei and m1Checked == data.m1Checked then
		return data
	end
	return { version = data.version, jukurendo = jukurendo, hikei = hikei, m1Checked = m1Checked }
end

-- 熟練度の記録がまだ無い人の、M1 から遊ぶ人かを確かめた変更。cleared は進行のクリア済みのステージで、
-- 1つでもあれば M1 から遊んでいる人として、M1 の8種を覚えた秘計に加える
function Jukurendo.m1ChangeOf(cleared: { string }): Change
	if #cleared > 0 then
		return { m1Checked = true, hikei = table.clone(Jukurendo.M1_HIKEI) }
	end
	return { m1Checked = true }
end

-- 0 以上の整数にする。数でない値・NaN・無限大は 0
local function toCount(value: unknown): number
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
-- 欠けた項目と形の違う項目は空にし、文字列でない秘計と、キーが文字列でない熟練度は捨てる。定義に無い系統と秘計は残す
function Jukurendo.normalize(raw: unknown): Data?
	if type(raw) ~= "table" then
		return nil
	end
	local source = raw :: { [string]: any }
	local version = if type(source.version) == "number" then source.version else Jukurendo.VERSION
	local jukurendo: { [string]: number } = {}
	if type(source.jukurendo) == "table" then
		for keito, value in source.jukurendo :: { [any]: any } do
			if type(keito) == "string" then
				jukurendo[keito] = toCount(value)
			end
		end
	end
	return {
		version = version,
		jukurendo = jukurendo,
		hikei = sorted(stringsOf(source.hikei)),
		m1Checked = source.m1Checked == true,
	}
end

-- 届いた JukurendoState を読む。形が違えば nil
function Jukurendo.normalizeState(value: unknown): State?
	if type(value) ~= "table" then
		return nil
	end
	local source = value :: { [string]: unknown }
	local data = Jukurendo.normalize(source.data)
	if not data then
		return nil
	end
	return { loaded = source.loaded == true, data = data }
end

-- 秘計の欄の系統の見出し（「武勇（撃破で上がる）」）。表に無い系統は ID のまま書く
function Jukurendo.titleOf(keito: string): string
	local name = Jukurendo.names[keito] or keito
	local source = Jukurendo.sourceNames[keito]
	return if source then `{name}（{source}で上がる）` else name
end

-- 秘計の欄の系統の熟練度と、次に覚える秘計までの値（「熟練度 45　あと 5 で大喝」「熟練度 160　すべて覚えた」）
function Jukurendo.progressOf(data: Data, keito: string, params: Config.JukurendoSection?): string
	local value = Jukurendo.jukurendoOf(data, keito)
	local nextId, threshold = Jukurendo.nextOf(data, keito, params)
	if not nextId or not threshold then
		return `熟練度 {value}　すべて覚えた`
	end
	local definition = Hikei.get(nextId)
	local name = if definition then definition.displayName else nextId
	return `熟練度 {value}　あと {math.max(threshold - value, 0)} で{name}`
end

-- 系統の定義の誤りを文で返す。誤りが無ければ空。
-- 系統がそろっているか、秘計が定義にあり、どれか1つの系統にだけあるか、覚える熟練度が 0 から始まって増えていくか、
-- Rate と Max を見る
function Jukurendo.validate(params: Config.JukurendoSection?): { string }
	local p = paramsOf(params)
	local problems = {}
	for keito in p.Keito do
		if not table.find(Jukurendo.keitoList, keito :: Keito) then
			table.insert(problems, `{keito}: 系統の並び（keitoList）に無い`)
		end
	end
	local owner: { [string]: string } = {}
	for _, keito in Jukurendo.keitoList do
		local def = p.Keito[keito]
		if not def then
			table.insert(problems, `{keito}: Config に系統が無い`)
			continue
		end
		if #def.Hikei == 0 then
			table.insert(problems, `{keito}: 秘計が無い`)
		end
		local previous: number? = nil
		for index, entry in def.Hikei do
			local id = entry.Id
			if not Hikei.get(id) then
				table.insert(problems, `{keito}: 秘計 {id} は定義に無い`)
			end
			if owner[id] then
				table.insert(problems, `{keito}: 秘計 {id} は {owner[id]} にもある`)
			end
			owner[id] = keito
			local value = entry.Jukurendo
			if index == 1 and value ~= 0 then
				table.insert(problems, `{keito}: 最初の秘計 {id} の熟練度が 0 でない`)
			end
			if value < 0 or value ~= math.floor(value) then
				table.insert(problems, `{keito}: 秘計 {id} の熟練度 {value} が 0 以上の整数でない`)
			end
			if previous and value <= previous then
				table.insert(problems, `{keito}: 秘計 {id} の熟練度 {value} が前の秘計より大きくない`)
			end
			previous = value
		end
		if not (def.Rate > 0) then
			table.insert(problems, `{keito}: Rate {def.Rate} が 0 より大きくない`)
		end
		if not (def.Max >= 0) or def.Max ~= math.floor(def.Max) then
			table.insert(problems, `{keito}: Max {def.Max} が 0 以上の整数でない`)
		end
	end
	for _, id in Hikei.selectable() do
		if not owner[id] then
			table.insert(problems, `{id}: どの系統にも無い`)
		end
	end
	return problems
end

return Jukurendo
