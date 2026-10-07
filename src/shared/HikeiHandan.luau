--!strict
-- 秘計の判断。敵軍の上忍と首領が、戦場の様子の要約（Situation）から、持ち込んだ秘計を使うかと、どれを使うかを決める。
-- 間隔と割合は Config.luau の HikeiHandan 節、大喝と挑発の半径は Daikatsu 節と Chohatsu 節の Radius にある。
-- 時刻は引数で受け取り、Roblox の API は使わない。判断を呼んで秘計を使うのはサーバーの HikeiHandanService で、
-- 発動は秘計の入口（HikeiService.useByJonin）を通す。
--
-- - 判断するのは敵軍の上忍と首領だけ。味方軍の上忍と首領は秘計を使わない
-- - 使える秘計（持ち込みのうち、まだ使っておらず、試し直しを待っていない枚）を枚の順に見て、条件がそろった最初の秘計を使う
-- - 秘計ごとの条件は conditions に秘計 ID の鍵で並べる。条件の無い秘計は使わない
--   - 鬼神化は、率いる部隊が交戦中のときか、首領の体力が上限の ShuryoHealthRate 以下のとき。もう鬼神化していれば使わない
--   - 大喝は、大喝の半径以内に、強化の秘計の効果中の相手（プレイヤーか上忍・首領）がいるとき
--   - 挑発は、挑発の半径以内に、誘い出されていない相手の上忍（首領は除く）がいるとき
--   - 伏兵は、自分の軍の拠点の範囲の中にいて、その拠点の中心から FukuheiDistance 以内に相手の部隊かプレイヤーが
--     来たとき（迫ったとき）。その拠点の範囲の中に自分の軍の伏兵部隊がもう潜んでいれば、重ねて使わない
--   - 落石は、落石の届く距離（Hikei 節の TargetRange.Rakuseki）以内で一番近い落石地点の区間（つながり）が、
--     相手の軍の兵站線に入っているとき。その地点に岩がもうあれば使わない（重ねて落とせない）
--   - 大火計は、大火計の届く距離（TargetRange.Daikakei）以内で一番近い大火計地域の中の相手が DaikakeiAite 以上のとき
--   - 大火計の相手は、プレイヤー・上忍・首領・部隊を1つずつ数える（上忍が率いる部隊は、上忍と部隊で2つ）
--   - 伏兵と大火計は、潜んでいる伏兵部隊（見つからない）と兵数の無い部隊を相手に入れない
--   - 一番近い落石地点と大火計地域は、サーバーが発動の処理と同じ選び方で選んで様子に入れる（判断と発動が同じ地点を選ぶ）
--   - 兵糧庫は、中にいる自分の軍の通常拠点（本陣は除く）が、兵站線の末端（Heitansen.isMattan）のとき。
--     もう兵糧庫の拠点では使わない
--   - 爆破罠は、中にいる自分の軍の拠点（本陣も含む）の中心から BakuhawanaRadius 以内に、相手のプレイヤーがいるとき。
--     もう罠のある拠点と、耐久が爆発する耐久をもう下回った拠点では使わない
--   - 兵糧庫と爆破罠は、発動の確かめ（Hikei.checkHyoroko・checkBakuhawana）に同じ拠点の値を渡して決める。
--     判断で選んだ兵糧庫と爆破罠は、発動で NoTarget・AlreadyActive・LowTaikyu にならない
-- - 上忍と首領ごとに、Interval 秒に1回だけ判断する（考える間隔ごとに呼ばれるのを間引く）
-- - 敵軍のだれかが秘計を使ったら、UseInterval 秒の間は敵軍のだれも判断しない（敵軍全体の使用間隔）
-- - 発動できなかった秘計は、RetryInterval 秒の間、同じ上忍か首領は選ばない（毎回試し直さない）
-- - 位置は水平の (x, z) で扱う

local Config = require("./Config")
local Gun = require("./Gun")
local Hikei = require("./Hikei")

-- 判断に使う Config.luau の節。HikeiHandan 節と、大喝と挑発の半径（Daikatsu 節と Chohatsu 節の Radius）。
-- 省いたときに Config をそのまま渡せるよう、節の型は Config.luau と同じにする
export type Params = {
	HikeiHandan: Config.HikeiHandanSection,
	Daikatsu: Config.DaikatsuSection,
	Chohatsu: Config.ChohatsuSection,
}

-- 判断に使う、戦場のプレイヤーと上忍・首領
export type Unit = {
	kind: "Player" | "Jonin",
	-- プレイヤーは UserId の文字列、上忍と首領はキャラクター ID
	id: string,
	gun: Gun.Gun,
	x: number,
	z: number,
	-- 強化の秘計の効果中か
	kyoka: boolean,
	-- 首領か。プレイヤーは false
	shuryo: boolean,
	-- 挑発で誘い出されているか。プレイヤーは false
	lured: boolean,
}

-- 判断に使う、戦場の部隊
export type Butai = {
	id: string,
	gun: Gun.Gun,
	x: number,
	z: number,
	heisu: number,
	-- 潜んでいる伏兵部隊か
	fukuhei: boolean,
}

-- 判断する上忍か首領が範囲の中にいる拠点（伏兵・兵糧庫・爆破罠の判断に使う）
export type Kyoten = {
	id: string,
	-- 今の所属の軍
	gun: Gun.Gun,
	honjin: boolean,
	-- 中心の水平の位置
	x: number,
	z: number,
	-- 今の所属の軍の兵站線の末端か（Heitansen.isMattan）
	mattan: boolean,
	-- 兵糧庫にした拠点か
	hyoroko: boolean,
	-- 爆破罠を仕掛けた拠点か
	bakuhawana: boolean,
	-- 今の耐久と、爆破罠が爆発する耐久（耐久の上限 × Config.luau の Bakuhawana 節の Rate）
	taikyu: number,
	threshold: number,
	-- 範囲の中に、判断する上忍か首領の軍の伏兵部隊が潜んでいるか
	fukuhei: boolean,
}

-- 判断する上忍か首領から落石の届く距離以内で一番近い落石地点
export type RakusekiChiten = {
	id: string,
	-- 塞ぐ区間（つながり）が入っている兵站線の軍。どちらの兵站線にも入っていなければ nil
	heitansen: Gun.Gun?,
	-- 岩を落としてあるか（落石の効果中）。岩のある地点には重ねて使えない
	active: boolean,
}

-- 判断する上忍か首領から大火計の届く距離以内で一番近い大火計地域
export type DaikakeiChiiki = {
	id: string,
	-- 地域の中にいるプレイヤーと上忍・首領（Situation の units のうち、地域の中のもの）
	units: { Unit },
	-- 地域の中にいる部隊（Situation の butai のうち、地域の中のもの）
	butai: { Butai },
}

-- 判断する上忍か首領の様子の要約
export type Situation = {
	-- キャラクター ID
	id: string,
	gun: Gun.Gun,
	shuryo: boolean,
	x: number,
	z: number,
	health: number,
	maxHealth: number,
	-- 率いる部隊が交戦中か。首領と、部隊を失った上忍は false
	kosen: boolean,
	-- 鬼神化の効果中か
	kishinka: boolean,
	-- 使える秘計（持ち込みのうち、まだ使っておらず、試し直しを待っていない枚）。枚の順
	hikei: { string },
	-- 戦場のプレイヤーと、ほかの上忍・首領（倒れたものは入れない）。軍は問わない
	units: { Unit },
	-- 戦場の部隊（潜んでいる伏兵部隊も入れる）。軍は問わない
	butai: { Butai },
	-- 範囲の中にいる拠点。どの拠点の範囲にもいなければ nil
	kyoten: Kyoten?,
	-- 落石の届く距離（Config.luau の Hikei 節の TargetRange.Rakuseki）以内で一番近い落石地点。無ければ nil
	rakuseki: RakusekiChiten?,
	-- 大火計の届く距離（TargetRange.Daikakei）以内で一番近い大火計地域。無ければ nil
	daikakei: DaikakeiChiiki?,
}

-- 判断の記録。敵軍全体で1つ持ち、ステージの開始ごとに作り直す
export type State = {
	-- 敵軍のだれかが最後に秘計を使った時刻。まだ使っていなければ nil
	lastUsedAt: number?,
	-- キャラクター ID から引く、次に判断する時刻
	nextAt: { [string]: number },
	-- キャラクター ID と秘計 ID から引く、発動できなかった時刻
	failedAt: { [string]: { [string]: number } },
}

-- 秘計を使う条件。様子の要約と Params を受け、使うなら true を返す
type Condition = (situation: Situation, params: Params) -> boolean

local HikeiHandan = {}

-- 判断する上忍か首領から、プレイヤーか上忍・首領までの水平の距離
local function distanceTo(situation: Situation, unit: Unit): number
	local dx, dz = unit.x - situation.x, unit.z - situation.z
	return math.sqrt(dx * dx + dz * dz)
end

-- 半径 radius 以内に、matches に合う相手の軍のプレイヤーか上忍・首領がいるか
local function hasAite(situation: Situation, radius: number, matches: (unit: Unit) -> boolean): boolean
	for _, unit in situation.units do
		if unit.gun ~= situation.gun and matches(unit) and distanceTo(situation, unit) <= radius then
			return true
		end
	end
	return false
end

-- 判断する上忍か首領が中にいる拠点の中心から、一番近い相手のプレイヤーまでの水平の距離（爆破罠の判断に使う）。
-- 拠点の外にいるか、相手のプレイヤーがいなければ nil
function HikeiHandan.playerDistanceOf(situation: Situation): number?
	local kyoten = situation.kyoten
	if not kyoten then
		return nil
	end
	local nearest: number? = nil
	for _, unit in situation.units do
		if unit.kind == "Player" and unit.gun ~= situation.gun then
			local dx, dz = unit.x - kyoten.x, unit.z - kyoten.z
			local distance = math.sqrt(dx * dx + dz * dz)
			if nearest == nil or distance < nearest then
				nearest = distance
			end
		end
	end
	return nearest
end

-- 部隊が、判断する上忍か首領から見て数える相手か。相手の軍の部隊のうち、兵数があり、潜んでいないもの
-- （潜んでいる伏兵部隊は見つからない）
local function isAiteButai(situation: Situation, butai: Butai): boolean
	return butai.gun ~= situation.gun and butai.heisu > 0 and not butai.fukuhei
end

-- 判断する上忍か首領が範囲の中にいる拠点の中心から、一番近い相手（部隊かプレイヤー）までの水平の距離。
-- 拠点の範囲の外にいるか、数える相手がいなければ nil
function HikeiHandan.kyotenAiteDistance(situation: Situation): number?
	local kyoten = situation.kyoten
	if kyoten == nil then
		return nil
	end
	local best = math.huge
	for _, butai in situation.butai do
		if isAiteButai(situation, butai) then
			local dx, dz = butai.x - kyoten.x, butai.z - kyoten.z
			best = math.min(best, math.sqrt(dx * dx + dz * dz))
		end
	end
	for _, unit in situation.units do
		if unit.kind == "Player" and unit.gun ~= situation.gun then
			local dx, dz = unit.x - kyoten.x, unit.z - kyoten.z
			best = math.min(best, math.sqrt(dx * dx + dz * dz))
		end
	end
	return if best < math.huge then best else nil
end

-- 判断する上忍か首領から一番近い大火計地域の中の相手の数。プレイヤー・上忍・首領・部隊を1つずつ数える
-- （潜んでいる伏兵部隊と兵数の無い部隊は数えない）。地域が無ければ 0
function HikeiHandan.daikakeiAiteCount(situation: Situation): number
	local chiiki = situation.daikakei
	if chiiki == nil then
		return 0
	end
	local count = 0
	for _, unit in chiiki.units do
		if unit.gun ~= situation.gun then
			count += 1
		end
	end
	for _, butai in chiiki.butai do
		if isAiteButai(situation, butai) then
			count += 1
		end
	end
	return count
end

-- 秘計ごとの使う条件。秘計 ID の鍵で並べる
local conditions: { [string]: Condition } = {
	-- 鬼神化は、率いる部隊が交戦中のときか、首領の体力が上限の ShuryoHealthRate 以下のとき。もう鬼神化していれば使わない
	Kishinka = function(situation: Situation, params: Params): boolean
		if situation.kishinka then
			return false
		end
		local weakened = situation.shuryo
			and situation.health <= situation.maxHealth * params.HikeiHandan.ShuryoHealthRate
		return situation.kosen or weakened
	end,
	-- 大喝は、大喝の半径以内に、強化の秘計の効果中の相手がいるとき
	Daikatsu = function(situation: Situation, params: Params): boolean
		return hasAite(situation, params.Daikatsu.Radius, function(unit: Unit): boolean
			return unit.kyoka
		end)
	end,
	-- 挑発は、挑発の半径以内に、誘い出されていない相手の上忍（首領は除く）がいるとき
	Chohatsu = function(situation: Situation, params: Params): boolean
		return hasAite(situation, params.Chohatsu.Radius, function(unit: Unit): boolean
			return unit.kind == "Jonin" and not unit.shuryo and not unit.lured
		end)
	end,
	-- 伏兵は、自分の軍の拠点の範囲の中にいて、その拠点の中心から FukuheiDistance 以内に相手の部隊かプレイヤーが来たとき。
	-- その拠点の範囲の中に自分の軍の伏兵部隊がもう潜んでいれば、重ねて使わない
	Fukuhei = function(situation: Situation, params: Params): boolean
		local kyoten = situation.kyoten
		if kyoten == nil or kyoten.gun ~= situation.gun or kyoten.fukuhei then
			return false
		end
		local distance = HikeiHandan.kyotenAiteDistance(situation)
		return distance ~= nil and distance <= params.HikeiHandan.FukuheiDistance
	end,
	-- 落石は、一番近い落石地点の区間が相手の軍の兵站線に入っているとき。岩がもうあれば使わない
	Rakuseki = function(situation: Situation, _params: Params): boolean
		local chiten = situation.rakuseki
		return chiten ~= nil and not chiten.active and chiten.heitansen == Gun.opponentOf(situation.gun)
	end,
	-- 大火計は、一番近い大火計地域の中の相手が DaikakeiAite 以上のとき
	Daikakei = function(situation: Situation, params: Params): boolean
		return situation.daikakei ~= nil and HikeiHandan.daikakeiAiteCount(situation) >= params.HikeiHandan.DaikakeiAite
	end,
	-- 兵糧庫は、中にいる自分の軍の通常拠点が兵站線の末端のとき。本陣・拠点の外・もう兵糧庫の拠点では使わない
	-- （発動の確かめ Hikei.checkHyoroko と同じ決め方）
	Hyoroko = function(situation: Situation, _params: Params): boolean
		local kyoten = situation.kyoten
		if not kyoten or not kyoten.mattan then
			return false
		end
		local target: Hikei.HyorokoTarget = { gun = kyoten.gun, honjin = kyoten.honjin, active = kyoten.hyoroko }
		return Hikei.checkHyoroko(target, situation.gun) == nil
	end,
	-- 爆破罠は、中にいる自分の軍の拠点（本陣も含む）の中心から BakuhawanaRadius 以内に、相手のプレイヤーがいるとき。
	-- もう罠のある拠点と、耐久が爆発する耐久をもう下回った拠点では使わない（発動の確かめ Hikei.checkBakuhawana と同じ決め方）
	Bakuhawana = function(situation: Situation, params: Params): boolean
		local kyoten = situation.kyoten
		if not kyoten then
			return false
		end
		local target: Hikei.BakuhawanaTarget = {
			gun = kyoten.gun,
			taikyu = kyoten.taikyu,
			threshold = kyoten.threshold,
			active = kyoten.bakuhawana,
		}
		if Hikei.checkBakuhawana(target, situation.gun) ~= nil then
			return false
		end
		local distance = HikeiHandan.playerDistanceOf(situation)
		return distance ~= nil and distance <= params.HikeiHandan.BakuhawanaRadius
	end,
}

-- 使う条件のある秘計か。条件の無い秘計は、持ち込んでも判断で使わない
function HikeiHandan.hasCondition(hikeiId: string): boolean
	return conditions[hikeiId] ~= nil
end

-- 様子の要約から、使う秘計の ID を返す。使える秘計を枚の順に見て、条件がそろった最初の秘計を選ぶ。
-- 敵軍でないか、条件がそろう秘計が無ければ nil
function HikeiHandan.decide(situation: Situation, params: Params?): string?
	local p: Params = params or Config
	if situation.gun ~= "Tekigun" then
		return nil
	end
	for _, hikeiId in situation.hikei do
		local condition = conditions[hikeiId]
		if condition and condition(situation, p) then
			return hikeiId
		end
	end
	return nil
end

-- 空の判断の記録。ステージの開始ごとに作り直す
function HikeiHandan.newState(): State
	return { lastUsedAt = nil, nextAt = {}, failedAt = {} }
end

-- 敵軍全体の使用間隔の残り秒数。間隔が明けていれば 0
function HikeiHandan.waitOf(state: State, now: number, params: Params?): number
	local p: Params = params or Config
	local lastUsedAt = state.lastUsedAt
	if lastUsedAt == nil then
		return 0
	end
	return math.max(lastUsedAt + p.HikeiHandan.UseInterval - now, 0)
end

-- 上忍か首領 id が now に判断するか。敵軍全体の使用間隔の間は判断しない。
-- 判断の周期（Interval）に1回だけ true を返し、次に判断する時刻を進める
function HikeiHandan.isDue(state: State, id: string, now: number, params: Params?): boolean
	local p: Params = params or Config
	if HikeiHandan.waitOf(state, now, p) > 0 then
		return false
	end
	local nextAt = state.nextAt[id]
	if nextAt ~= nil and now < nextAt then
		return false
	end
	state.nextAt[id] = now + p.HikeiHandan.Interval
	return true
end

-- 敵軍のだれかが秘計を使ったことを記録する。now から UseInterval 秒の間、敵軍のだれも判断しない
function HikeiHandan.recordUse(state: State, now: number)
	state.lastUsedAt = now
end

-- 上忍か首領 id が秘計 hikeiId を発動できなかったことを記録する。now から RetryInterval 秒の間、その秘計を選ばない
function HikeiHandan.recordFailure(state: State, id: string, hikeiId: string, now: number)
	local failed = state.failedAt[id] or {}
	failed[hikeiId] = now
	state.failedAt[id] = failed
end

-- 上忍か首領 id が、発動できなかった秘計 hikeiId を試し直すまでの残り秒数。待っていなければ 0
function HikeiHandan.retryWaitOf(state: State, id: string, hikeiId: string, now: number, params: Params?): number
	local p: Params = params or Config
	local failed = state.failedAt[id]
	local failedAt = if failed then failed[hikeiId] else nil
	if failedAt == nil then
		return 0
	end
	return math.max(failedAt + p.HikeiHandan.RetryInterval - now, 0)
end

-- 上忍か首領 id の使える秘計を枚の順に返す。持ち込み mochikomi のうち、使用済みの秘計 used と、
-- 試し直しを待っている秘計を除く
function HikeiHandan.usableOf(
	state: State,
	id: string,
	mochikomi: { string },
	used: { string },
	now: number,
	params: Params?
): { string }
	local result = {}
	for _, hikeiId in mochikomi do
		if not table.find(used, hikeiId) and HikeiHandan.retryWaitOf(state, id, hikeiId, now, params) <= 0 then
			table.insert(result, hikeiId)
		end
	end
	return result
end

return HikeiHandan
