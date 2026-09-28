--!strict
-- 秘計の定義と使用のルール。持ち込みの検証、1戦1枚1回の使用記録、効果の時間管理を持つ。
-- 各秘計の中身（伏兵部隊や落石の岩など）は、サーバーの秘計の処理が作る。
-- 時刻は引数で受け取り、効果時間は Config.luau の Hikei 節から引く。Roblox の API は使わない。

local Config = require("./Config")
local Gun = require("./Gun")
local RemoteSchema = require("./RemoteSchema")

-- 対象の取り方
export type TargetKind =
	"Self" -- 発動者自身
	| "Nearby" -- 発動者の周囲
	| "Underfoot" -- 発動者の足元
	| "RakusekiChiten" -- 近くの落石地点
	| "DaikakeiChiiki" -- 近くの大火計地域
	| "OwnKyoten" -- 発動者が中にいる、発動者の軍の拠点

-- 効果を受ける側。Own は発動者の軍のもの、Opponent は相手の軍のもの
export type Affects = "Own" | "Opponent"

export type Definition = {
	id: string,
	displayName: string,
	-- 強化の秘計か。大喝で打ち消せる
	kyoka: boolean,
	target: TargetKind,
	affects: Affects,
}

-- 使用の失敗の理由
export type UseFailure =
	"NoSlot" -- その番号の枚を持ち込んでいない
	| "Used" -- この戦いで使用済み

-- 秘計の効果。1つの対象に1つずつ持つ
export type Effect = {
	hikei: string,
	-- 発動者の ID（プレイヤーは UserId の文字列、上忍と首領はその ID）
	user: string,
	-- 発動者の軍
	gun: Gun.Gun,
	-- 効果を受ける対象の ID（プレイヤー・上忍・首領・部隊・拠点など）
	target: string,
	startedAt: number,
	-- 期限の時刻。期限の無い効果は math.huge
	expiresAt: number,
}

-- 発動者の ID から、使用済みの秘計を引く表
export type Usage = { [string]: { [string]: boolean } }

local Hikei = {}

-- 持ち込みの上限枚数。秘計のボタン（1〜3、十字キーの左・上・右）の数に合わせた仕様値
Hikei.MOCHIKOMI_MAX = 3

-- 設計の表の順。選択画面もこの順に並べる
local ORDER = { "Fukuhei", "Rakuseki", "Daikakei", "Hyoroko", "Bakuhawana", "Chohatsu", "Kishinka", "Daikatsu" }

local definitions: { [string]: Definition } = {
	Fukuhei = {
		id = "Fukuhei",
		displayName = "伏兵",
		kyoka = false,
		target = "Underfoot",
		affects = "Own",
	},
	Rakuseki = {
		id = "Rakuseki",
		displayName = "落石",
		kyoka = false,
		target = "RakusekiChiten",
		affects = "Opponent",
	},
	Daikakei = {
		id = "Daikakei",
		displayName = "大火計",
		kyoka = false,
		target = "DaikakeiChiiki",
		affects = "Opponent",
	},
	Hyoroko = {
		id = "Hyoroko",
		displayName = "兵糧庫",
		kyoka = false,
		target = "OwnKyoten",
		affects = "Own",
	},
	Bakuhawana = {
		id = "Bakuhawana",
		displayName = "爆破罠",
		kyoka = false,
		target = "OwnKyoten",
		affects = "Own",
	},
	Chohatsu = {
		id = "Chohatsu",
		displayName = "挑発",
		kyoka = false,
		target = "Nearby",
		affects = "Opponent",
	},
	Kishinka = {
		id = "Kishinka",
		displayName = "鬼神化",
		kyoka = true,
		target = "Self",
		affects = "Own",
	},
	Daikatsu = {
		id = "Daikatsu",
		displayName = "大喝",
		kyoka = false,
		target = "Nearby",
		affects = "Opponent",
	},
}

Hikei.definitions = definitions

function Hikei.get(id: string): Definition?
	return definitions[id]
end

-- 選べる秘計の ID を設計の表の順に返す。M1 は全種類を最初から選べる
function Hikei.selectable(): { string }
	return table.clone(ORDER)
end

-- 持ち込みの検証。受け付けるなら nil、受け付けないなら理由を返す。
-- others は、パーティーの他のメンバーが選んでいる秘計。上限より少ない枚数は受け付ける
function Hikei.checkMochikomi(mochikomi: { string }, others: { string }): RemoteSchema.RejectReason?
	local seen: { [string]: boolean } = {}
	for _, id in mochikomi do
		if not definitions[id] then
			return "UnknownHikei"
		end
		if seen[id] then
			return "HikeiDuplicate"
		end
		seen[id] = true
	end
	for _, id in others do
		if seen[id] then
			return "HikeiTaken"
		end
	end
	if #mochikomi > Hikei.MOCHIKOMI_MAX then
		return "HikeiLimit"
	end
	return nil
end

-- 空の使用記録。ステージの開始ごとに作り直す
function Hikei.newUsage(): Usage
	return {}
end

function Hikei.isUsed(usage: Usage, user: string, hikeiId: string): boolean
	local used = usage[user]
	return used ~= nil and used[hikeiId] == true
end

-- slot 番目の枚を使えるか。使えるならその秘計の ID、使えないなら nil と理由を返す。
-- 使用済みにはしない。効果を出せたときだけ markUsed を呼び、失敗した枚は未使用のまま残す
function Hikei.checkUse(usage: Usage, user: string, mochikomi: { string }, slot: number): (string?, UseFailure?)
	local hikeiId = mochikomi[slot]
	if hikeiId == nil then
		return nil, "NoSlot"
	end
	if Hikei.isUsed(usage, user, hikeiId) then
		return nil, "Used"
	end
	return hikeiId, nil
end

-- 使用済みにする。すでに使用済みなら false
function Hikei.markUsed(usage: Usage, user: string, hikeiId: string): boolean
	if Hikei.isUsed(usage, user, hikeiId) then
		return false
	end
	usage[user] = usage[user] or {}
	usage[user][hikeiId] = true
	return true
end

-- 効果時間（秒）。期限の無い秘計は math.huge
function Hikei.durationOf(hikeiId: string): number
	return Config.Hikei.Duration[hikeiId] or math.huge
end

-- 空の効果の一覧。ステージの開始ごとに作り直す
function Hikei.newEffects(): { Effect }
	return {}
end

export type EffectRequest = {
	hikei: string,
	user: string,
	gun: Gun.Gun,
	target: string,
	-- 対象の軍。落石地点のようにどちらにも属さない対象は nil
	targetGun: Gun.Gun?,
	now: number,
}

-- 効果を足して返す。受ける側が秘計の定義と合わない対象（相手の軍への強化や、
-- 発動者の軍への妨害）には足さずに nil を返す
function Hikei.addEffect(effects: { Effect }, request: EffectRequest): Effect?
	local definition = definitions[request.hikei]
	if not definition then
		return nil
	end
	if request.targetGun ~= nil then
		local own = request.targetGun == request.gun
		if (definition.affects == "Own") ~= own then
			return nil
		end
	end
	local effect: Effect = {
		hikei = request.hikei,
		user = request.user,
		gun = request.gun,
		target = request.target,
		startedAt = request.now,
		expiresAt = request.now + Hikei.durationOf(request.hikei),
	}
	table.insert(effects, effect)
	return effect
end

local function isLive(effect: Effect, now: number): boolean
	return now < effect.expiresAt
end

-- 対象にかかっている、期限内の効果
function Hikei.activeOn(effects: { Effect }, target: string, now: number): { Effect }
	local result = {}
	for _, effect in effects do
		if effect.target == target and isLive(effect, now) then
			table.insert(result, effect)
		end
	end
	return result
end

-- 対象に hikeiId の効果が期限内でかかっているか
function Hikei.isActive(effects: { Effect }, target: string, hikeiId: string, now: number): boolean
	for _, effect in effects do
		if effect.target == target and effect.hikei == hikeiId and isLive(effect, now) then
			return true
		end
	end
	return false
end

-- predicate に合う効果を一覧から外し、外した効果を足した順に返す
local function takeWhere(effects: { Effect }, predicate: (Effect) -> boolean): { Effect }
	local taken = {}
	local kept = {}
	for _, effect in effects do
		table.insert(if predicate(effect) then taken else kept, effect)
	end
	table.clear(effects)
	table.move(kept, 1, #kept, 1, effects)
	return taken
end

-- 期限切れの効果を一覧から外して返す。終了の処理は返した効果ごとに1回ずつ呼ぶ
function Hikei.takeExpired(effects: { Effect }, now: number): { Effect }
	return takeWhere(effects, function(effect)
		return not isLive(effect, now)
	end)
end

-- gun の相手の軍がかけた強化の秘計の効果を打ち消し、外した効果を返す（大喝）。
-- targets を渡すと、その対象にかかっている効果だけを打ち消す
function Hikei.dispelKyoka(effects: { Effect }, gun: Gun.Gun, now: number, targets: { string }?): { Effect }
	local only: { [string]: boolean }? = nil
	if targets then
		local set = {}
		for _, target in targets do
			set[target] = true
		end
		only = set
	end
	return takeWhere(effects, function(effect)
		local definition = definitions[effect.hikei]
		return definition ~= nil
			and definition.kyoka
			and effect.gun ~= gun
			and isLive(effect, now)
			and (only == nil or only[effect.target] == true)
	end)
end

return Hikei
