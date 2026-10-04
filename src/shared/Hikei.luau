--!strict
-- 秘計の定義と使用のルール。持ち込みの検証、発動の検証、1戦1枚1回の使用記録、効果の時間管理を持つ。
-- 各秘計の中身（伏兵部隊や落石の岩など）は、サーバーの秘計の処理（HikeiService に登録）が作る。
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
	-- 選択画面に出す効果の説明。{秒} は Config.luau の効果時間に置き換える（describe）
	description: string,
	-- 強化の秘計か。大喝で打ち消せる
	kyoka: boolean,
	target: TargetKind,
	affects: Affects,
}

-- 使用の失敗の理由
export type UseFailure =
	"NoSlot" -- その番号の枚を持ち込んでいない
	| "Used" -- この戦いで使用済み
	| "NotBattle" -- 戦闘のフェーズでない
	| "Down" -- 発動者が倒れている
	| "NotReady" -- その秘計の処理がまだ無い
	| "NoTarget" -- 対象（近くの落石地点、中にいる味方の拠点など）が無い
	| "AlreadyActive" -- 対象にもう同じ秘計の効果が出ている（重ねがけはできない）

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

-- プレイヤーの持ち込みと使用済みの秘計を複製する Player の Attribute。秘計 ID をカンマでつないだ文字列（encodeList）
Hikei.MOCHIKOMI_ATTRIBUTE = "HikeiMochikomi"
Hikei.USED_ATTRIBUTE = "HikeiUsed"

Hikei.useFailures = { "NoSlot", "Used", "NotBattle", "Down", "NotReady", "NoTarget", "AlreadyActive" } :: { UseFailure }

-- 設計の表の順。選択画面もこの順に並べる
local ORDER = { "Fukuhei", "Rakuseki", "Daikakei", "Hyoroko", "Bakuhawana", "Chohatsu", "Kishinka", "Daikatsu" }

local definitions: { [string]: Definition } = {
	Fukuhei = {
		id = "Fukuhei",
		displayName = "伏兵",
		description = "足元に味方の部隊を{秒}秒潜ませ、近づいた敵の部隊を奇襲して士気を下げる",
		kyoka = false,
		target = "Underfoot",
		affects = "Own",
	},
	Rakuseki = {
		id = "Rakuseki",
		displayName = "落石",
		description = "決められた地点の道を岩で塞ぎ、敵の兵站線を{秒}秒切る",
		kyoka = false,
		target = "RakusekiChiten",
		affects = "Opponent",
	},
	Daikakei = {
		id = "Daikakei",
		displayName = "大火計",
		description = "決められた地域にいる敵へ、まとめて大ダメージを与える",
		kyoka = false,
		target = "DaikakeiChiiki",
		affects = "Opponent",
	},
	Hyoroko = {
		id = "Hyoroko",
		displayName = "兵糧庫",
		description = "中にいる味方の拠点を改築する。兵站線が切れても孤立しない",
		kyoka = false,
		target = "OwnKyoten",
		affects = "Own",
	},
	Bakuhawana = {
		id = "Bakuhawana",
		displayName = "爆破罠",
		description = "中にいる味方の拠点に仕掛ける。耐久が3分の1まで減ると爆発し、拠点内の敵を吹き飛ばす",
		kyoka = false,
		target = "OwnKyoten",
		affects = "Own",
	},
	Chohatsu = {
		id = "Chohatsu",
		displayName = "挑発",
		description = "近くの敵の上忍を、{秒}秒自分のところへ誘い出す",
		kyoka = false,
		target = "Nearby",
		affects = "Opponent",
	},
	Kishinka = {
		id = "Kishinka",
		displayName = "鬼神化",
		description = "{秒}秒、自分の攻撃と防御が上がり、のけぞらなくなる",
		kyoka = true,
		target = "Self",
		affects = "Own",
	},
	Daikatsu = {
		id = "Daikatsu",
		displayName = "大喝",
		description = "敵の強化の秘計を打ち消し、周りの敵を{秒}秒動揺させる",
		kyoka = false,
		target = "Nearby",
		affects = "Opponent",
	},
}

Hikei.definitions = definitions

function Hikei.get(id: string): Definition?
	return definitions[id]
end

-- 選択画面に出す効果の説明。{秒} を Config.luau の効果時間に置き換える。定義に無い秘計は空
function Hikei.describe(id: string): string
	local definition = definitions[id]
	if not definition then
		return ""
	end
	local duration = Config.Hikei.Duration[id]
	local text = definition.description
	if duration then
		text = string.gsub(text, "{秒}", tostring(duration))
	end
	return text
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

-- 出撃するメンバーの持ち込みを決める。selections は出撃するメンバーごとに選んだ秘計（入った順）。
-- 選んだメンバーの持ち込みは選んだまま（上限より少なくても足さない）。
-- 1枚も選んでいないメンバーには、誰も選んでいない秘計を設計の表の順に、選んでいないメンバーへ1枚ずつ順に配る。
-- 上限に達するか、配る秘計が無くなったら終える。返す一覧は selections と同じ順
function Hikei.assignMochikomi(selections: { { string } }): { { string } }
	local taken: { [string]: boolean } = {}
	local result: { { string } } = {}
	local empty: { number } = {}
	for index, selection in selections do
		result[index] = table.clone(selection)
		for _, id in selection do
			taken[id] = true
		end
		if #selection == 0 then
			table.insert(empty, index)
		end
	end
	local pool = {}
	for _, id in ORDER do
		if not taken[id] then
			table.insert(pool, id)
		end
	end
	local next = 1
	for _ = 1, Hikei.MOCHIKOMI_MAX do
		for _, index in empty do
			if next > #pool then
				return result
			end
			table.insert(result[index], pool[next])
			next += 1
		end
	end
	return result
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

export type ActivationCheck = {
	-- 戦闘のフェーズか
	battle: boolean,
	-- 発動者が倒れていないか
	alive: boolean,
}

-- slot 番目の枚を発動できるか。発動できるならその秘計の ID、できないなら nil と理由を返す。
-- 戦闘のフェーズ、発動者が倒れていないか、枚の持ち込み、使用済みの順に確かめる。使用済みにはしない
function Hikei.checkActivation(
	check: ActivationCheck,
	usage: Usage,
	user: string,
	mochikomi: { string },
	slot: number
): (string?, UseFailure?)
	if not check.battle then
		return nil, "NotBattle"
	end
	if not check.alive then
		return nil, "Down"
	end
	return Hikei.checkUse(usage, user, mochikomi, slot)
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

-- 持ち込みのうち使用済みの秘計を、持ち込みの順に返す
function Hikei.usedOf(usage: Usage, user: string, mochikomi: { string }): { string }
	local result = {}
	for _, hikeiId in mochikomi do
		if Hikei.isUsed(usage, user, hikeiId) then
			table.insert(result, hikeiId)
		end
	end
	return result
end

-- 秘計 ID の一覧を Attribute に書く文字列にする（カンマでつなぐ）
function Hikei.encodeList(ids: { string }): string
	return table.concat(ids, ",")
end

-- Attribute の文字列を秘計 ID の一覧に戻す。文字列でない値と空の文字列は空の一覧、定義に無い ID は捨てる
function Hikei.decodeList(value: unknown): { string }
	local result = {}
	if type(value) ~= "string" then
		return result
	end
	for id in string.gmatch(value, "[^,]+") do
		if definitions[id] then
			table.insert(result, id)
		end
	end
	return result
end

-- 範囲の目印（大火計地域）までの水平の距離。localX・localZ は目印から見た位置（CFrame:PointToObjectSpace の X と Z）、
-- sizeX・sizeZ は目印の大きさ。範囲の中なら 0
function Hikei.distanceToArea(localX: number, localZ: number, sizeX: number, sizeZ: number): number
	local dx = math.max(math.abs(localX) - sizeX / 2, 0)
	local dz = math.max(math.abs(localZ) - sizeZ / 2, 0)
	return math.sqrt(dx * dx + dz * dz)
end

-- 秘計の対象にする地点（落石地点や大火計地域）の候補から、距離が maxDistance 以内で一番近いものの ID を返す。
-- 距離が同じなら ID の順。maxDistance 以内に無ければ nil
function Hikei.nearest(candidates: { { id: string, distance: number } }, maxDistance: number): string?
	local bestId: string? = nil
	local bestDistance = math.huge
	for _, candidate in candidates do
		if candidate.distance <= maxDistance then
			local closer = candidate.distance < bestDistance
			local tie = candidate.distance == bestDistance and bestId ~= nil and candidate.id < (bestId :: string)
			if closer or tie then
				bestId = candidate.id
				bestDistance = candidate.distance
			end
		end
	end
	return bestId
end

-- 発動者から対象の地点までの距離の上限（Config.luau の Hikei 節の TargetRange）。上限の無い秘計は nil
function Hikei.targetRangeOf(hikeiId: string): number?
	return Config.Hikei.TargetRange[hikeiId]
end

-- 兵糧庫の対象にする拠点。発動者が範囲の中にいる拠点の、今の所属と本陣か、もう兵糧庫か
export type HyorokoTarget = {
	gun: Gun.Gun,
	honjin: boolean,
	-- もう兵糧庫にした拠点か
	active: boolean,
}

-- 兵糧庫を発動できるか。kyoten は発動者が範囲の中にいる拠点（どの拠点の範囲にもいなければ nil）、gun は発動者の軍。
-- 発動できるなら nil、できなければ失敗の理由を返す。対象は自分の軍の通常拠点だけで、本陣と拠点の外は NoTarget、
-- もう兵糧庫の拠点は AlreadyActive
function Hikei.checkHyoroko(kyoten: HyorokoTarget?, gun: Gun.Gun): UseFailure?
	if not kyoten or kyoten.gun ~= gun or kyoten.honjin then
		return "NoTarget"
	end
	if kyoten.active then
		return "AlreadyActive"
	end
	return nil
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
	-- 効果時間（秒）。省くと Config.luau の効果時間（durationOf）
	duration: number?,
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
		expiresAt = request.now + (request.duration or Hikei.durationOf(request.hikei)),
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
