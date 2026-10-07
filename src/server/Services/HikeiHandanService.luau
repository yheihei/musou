--!strict
-- 秘計の判断。敵軍の上忍と首領が、戦場の様子を見て、持ち込んだ秘計を使うかを決めて使う。
-- 判断は ReplicatedStorage.Shared.HikeiHandan、間隔と割合は Config.luau の HikeiHandan 節にある。
-- 持ち込みは、出撃したときに HikeiService が配置の構成（Haichi.mochikomiOf）から決める。
--
-- - 判断は JoninKotaiService.setHikeiDecider で登録する。考える間隔（Config.luau の Jittaikaken 節の Interval）ごとに、
--   倒れていない敵軍の上忍と首領ごとに呼ばれる（個体として出ていなくても呼ばれ、窓口の SetJoninAI false の間は呼ばれない）
-- - 上忍と首領ごとに Interval 秒に1回だけ判断する。敵軍のだれかが使ってから UseInterval 秒の間は、敵軍のだれも判断しない
-- - 判断するときは様子の要約（率いる部隊が交戦中か、鬼神化しているか、体力、戦場のプレイヤーとほかの上忍・首領の
--   位置と、強化の秘計の効果中か、誘い出されているか）を作り、使える秘計から条件のそろった秘計を選ぶ
-- - 伏兵・落石・大火計の判断のため、様子の要約に、戦場の部隊、中にいる拠点（拠点の中に自分の軍の伏兵部隊が潜んでいるか）、
--   一番近い落石地点（区間が入っている兵站線の軍と、岩がもうあるか）、一番近い大火計地域（中にいる相手）も入れる。
--   地点と地域は発動の処理と同じ関数（HaichiService.nearestRakusekiChiten・nearestDaikakeiChiiki）で選び、
--   地域の中かも発動と同じ判定（DaikakeiService.contains）で見る（発動の処理が、判断で見た地点と同じ地点を対象にする）
-- - 様子はどれもデータの位置から作るので、個体として出ていない上忍と首領も同じに判断する
-- - 様子の要約には、範囲の中にいる拠点（所属・本陣か・中心・兵站線の末端か・兵糧庫か・爆破罠があるか・耐久と
--   爆発する耐久）も入れる。拠点は秘計の発動と同じ KyotenService.kyotenAt でデータの位置から引き、兵糧庫か
--   （HyorokoService.isHyoroko）と爆破罠があるか（BakuhawanaService.hasTrap）も発動の確かめと同じ値を使う
-- - 使える秘計は、持ち込みのうち、まだ使っておらず、試し直しを待っていない枚。発動できなかった秘計は
--   RetryInterval 秒の間、同じ上忍か首領は選ばない
-- - 秘計は必ず秘計の入口（HikeiService.useByJonin）で使う。1戦1枚1回と、発動できなかった枚が残ることは入口が持つ。
--   使ったときと使えなかったときは、コンソールに [HikeiHandan] の行を出す
-- - 味方軍の上忍と首領は判断しない（入口が呼ばないうえに、ここと判断でも軍を確かめる）
-- - 敵軍のだれかが秘計を使ったら（HikeiService.activated。窓口の UseHikei も含む）、敵軍全体の使用間隔を始める
-- - 出撃とロビーのフェーズへの戻りで、判断の記録を空にする

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Bakuhawana = require(ReplicatedStorage.Shared.Bakuhawana)
local Config = require(ReplicatedStorage.Shared.Config)
local Gun = require(ReplicatedStorage.Shared.Gun)
local Hikei = require(ReplicatedStorage.Shared.Hikei)
local HikeiHandan = require(ReplicatedStorage.Shared.HikeiHandan)
local Jonin = require(ReplicatedStorage.Shared.Jonin)
local Kyoten = require(ReplicatedStorage.Shared.Kyoten)
local StagePhase = require(ReplicatedStorage.Shared.StagePhase)
local DebugCommand = require(script.Parent.Parent.DebugCommand)
local BakuhawanaService = require(script.Parent.BakuhawanaService)
local ButaiService = require(script.Parent.ButaiService)
local ChohatsuService = require(script.Parent.ChohatsuService)
local DaikakeiService = require(script.Parent.DaikakeiService)
local HaichiService = require(script.Parent.HaichiService)
local HeitansenService = require(script.Parent.HeitansenService)
local HikeiService = require(script.Parent.HikeiService)
local HyorokoService = require(script.Parent.HyorokoService)
local JoninKotaiService = require(script.Parent.JoninKotaiService)
local JoninService = require(script.Parent.JoninService)
local KishinkaService = require(script.Parent.KishinkaService)
local KyotenService = require(script.Parent.KyotenService)
local RakusekiService = require(script.Parent.RakusekiService)
local StageService = require(script.Parent.StageService)

-- 上忍か首領が最後に秘計を使おうとした結果（確認用）
type Attempt = {
	hikei: string,
	ok: boolean,
	-- 発動できなかった理由。発動したら nil
	reason: Hikei.UseFailure?,
	-- 使おうとした時刻（os.clock）
	at: number,
}

-- 敵軍が最後に使った秘計（確認用）
type LastUse = {
	-- 使った上忍か首領のキャラクター ID
	user: string,
	hikei: string,
	-- 使った時刻（os.clock）
	at: number,
}

local HikeiHandanService = {}

-- 判断の記録（敵軍全体の使用間隔・判断の周期・試し直しの待ち）。時刻は os.clock（考える間隔の時刻と同じ）
local state: HikeiHandan.State = HikeiHandan.newState()
-- キャラクター ID から引く、最後に秘計を使おうとした結果
local attemptOf: { [string]: Attempt } = {}
local lastUse: LastUse? = nil

-- 倒れていない人のキャラクターの HumanoidRootPart。倒れているかキャラクターが無ければ nil
local function aliveRoot(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return root
end

-- 強化の秘計の効果中の対象の ID（プレイヤーは UserId の文字列、上忍と首領はキャラクター ID）
local function kyokaTargets(): { [string]: boolean }
	local now = HikeiService.now()
	local targets: { [string]: boolean } = {}
	for _, effect in HikeiService.getEffects() do
		local definition = Hikei.get(effect.hikei)
		if definition and definition.kyoka and now < effect.expiresAt then
			targets[effect.target] = true
		end
	end
	return targets
end

-- 判断に使う、戦場のプレイヤー（倒れていない出撃メンバー）と、jonin 以外の倒れていない上忍・首領
local function unitsAround(jonin: Jonin.Jonin): { HikeiHandan.Unit }
	local kyoka = kyokaTargets()
	local units: { HikeiHandan.Unit } = {}
	for _, member in StageService.getMembers() do
		local root = aliveRoot(member)
		if root then
			local id = tostring(member.UserId)
			table.insert(units, {
				kind = "Player",
				id = id,
				gun = "Mikatagun",
				x = root.Position.X,
				z = root.Position.Z,
				kyoka = kyoka[id] == true,
				shuryo = false,
				lured = false,
			})
		end
	end
	for _, other in JoninService.list() do
		if other.id ~= jonin.id and not Jonin.isDefeated(other) then
			table.insert(units, {
				kind = "Jonin",
				id = other.id,
				gun = other.gun,
				x = other.position.x,
				z = other.position.z,
				kyoka = kyoka[other.id] == true,
				shuryo = other.shuryo,
				lured = ChohatsuService.isLured(other.id),
			})
		end
	end
	return units
end

-- 判断に使う、戦場の部隊（潜んでいる伏兵部隊も入れる）
local function butaiAround(): { HikeiHandan.Butai }
	local list: { HikeiHandan.Butai } = {}
	for _, butai in ButaiService.list() do
		table.insert(list, {
			id = butai.id,
			gun = butai.gun,
			x = butai.position.x,
			z = butai.position.z,
			heisu = butai.heisu,
			fukuhei = butai.fukuhei == true,
		})
	end
	return list
end

-- 上忍か首領が範囲の中にいる拠点の様子（伏兵・兵糧庫・爆破罠の判断に使う）。どの拠点の範囲にもいなければ nil。
-- 拠点は秘計の発動と同じ KyotenService.kyotenAt でデータの位置から引く。首領は本陣の範囲にとどまる（縁へ寄せる）ので、
-- 縁で引けなくても本陣にいるものとする。兵糧庫か・罠があるか・爆発する耐久は、秘計の発動（HyorokoService・
-- BakuhawanaService）と同じ引き方にする。fukuhei は、範囲の中に上忍か首領の軍の伏兵部隊が潜んでいるか
local function kyotenAround(jonin: Jonin.Jonin, butaiList: { HikeiHandan.Butai }): HikeiHandan.Kyoten?
	local id = KyotenService.kyotenAt(jonin.position) or (if jonin.shuryo then jonin.kyoten else nil)
	local kyoten = if id then KyotenService.get(id) else nil
	local center = if id then KyotenService.centerOf(id) else nil
	if not id or not kyoten or not center then
		return nil
	end
	local fukuhei = false
	for _, butai in butaiList do
		if butai.fukuhei and butai.gun == jonin.gun and KyotenService.contains(id, { x = butai.x, z = butai.z }) then
			fukuhei = true
			break
		end
	end
	return {
		id = id,
		gun = kyoten.gun,
		honjin = kyoten.honjin,
		x = center.x,
		z = center.z,
		mattan = HeitansenService.isMattan(id),
		hyoroko = HyorokoService.isHyoroko(id),
		bakuhawana = BakuhawanaService.hasTrap(id),
		taikyu = kyoten.taikyu,
		threshold = Bakuhawana.threshold(Kyoten.maxTaikyu(kyoten.honjin)),
		fukuhei = fukuhei,
	}
end

-- 秘計の対象の地点を選ぶ位置。発動の入口（HikeiService）と同じく、データの水平の位置を使う。
-- 落石地点も大火計地域も水平の距離で選ぶので、高さは見ない
local function chitenPositionOf(jonin: Jonin.Jonin): Vector3
	return Vector3.new(jonin.position.x, 0, jonin.position.z)
end

-- 落石の届く距離以内で一番近い落石地点（落石の発動と同じ HaichiService.nearestRakusekiChiten で選ぶ）と、
-- その区間が入っている兵站線の軍と、岩がもうあるか。無ければ nil
local function rakusekiAround(jonin: Jonin.Jonin): HikeiHandan.RakusekiChiten?
	local chiten = HaichiService.nearestRakusekiChiten(chitenPositionOf(jonin))
	if not chiten then
		return nil
	end
	return {
		id = chiten.id,
		heitansen = HeitansenService.gunOf(chiten.kyotenA, chiten.kyotenB),
		active = RakusekiService.isActive(chiten.id),
	}
end

-- 大火計の届く距離以内で一番近い大火計地域（大火計の発動と同じ HaichiService.nearestDaikakeiChiiki で選ぶ）と、
-- 地域の中にいるプレイヤーと上忍・首領と部隊（発動と同じ DaikakeiService.contains で見る）。無ければ nil
local function daikakeiAround(
	jonin: Jonin.Jonin,
	units: { HikeiHandan.Unit },
	butaiList: { HikeiHandan.Butai }
): HikeiHandan.DaikakeiChiiki?
	local chiiki = HaichiService.nearestDaikakeiChiiki(chitenPositionOf(jonin))
	if not chiiki then
		return nil
	end
	local inside: HikeiHandan.DaikakeiChiiki = { id = chiiki.id, units = {}, butai = {} }
	for _, unit in units do
		if DaikakeiService.contains(chiiki, unit.x, unit.z) then
			table.insert(inside.units, unit)
		end
	end
	for _, butai in butaiList do
		if DaikakeiService.contains(chiiki, butai.x, butai.z) then
			table.insert(inside.butai, butai)
		end
	end
	return inside
end

-- 上忍か首領の様子の要約。hikei は使える秘計（枚の順）
local function summarize(jonin: Jonin.Jonin, hikei: { string }): HikeiHandan.Situation
	local butai = jonin.butai
	local units = unitsAround(jonin)
	local butaiList = butaiAround()
	return {
		id = jonin.id,
		gun = jonin.gun,
		shuryo = jonin.shuryo,
		x = jonin.position.x,
		z = jonin.position.z,
		health = jonin.health,
		maxHealth = jonin.stats.MaxHealth,
		kosen = butai ~= nil and ButaiService.aiteOf(butai) ~= nil,
		kishinka = KishinkaService.isActive(jonin.id),
		hikei = hikei,
		units = units,
		butai = butaiList,
		kyoten = kyotenAround(jonin, butaiList),
		rakuseki = rakusekiAround(jonin),
		daikakei = daikakeiAround(jonin, units, butaiList),
	}
end

-- 使える秘計 hikei から条件のそろった秘計を選び、秘計の入口で使わせる。mochikomi は持ち込み（枚の番号を引く）。
-- 使おうとした秘計と、発動したか、発動できなかった理由を返す。条件のそろう秘計が無ければ nil。
-- 使ったときと使えなかったときは、コンソールに1行出す
local function tryUse(
	jonin: Jonin.Jonin,
	mochikomi: { string },
	hikei: { string },
	now: number
): (string?, boolean, Hikei.UseFailure?)
	local hikeiId = HikeiHandan.decide(summarize(jonin, hikei))
	local slot = if hikeiId then table.find(mochikomi, hikeiId) else nil
	if not hikeiId or not slot then
		return nil, false, nil
	end
	local ok, _, failure = HikeiService.useByJonin(jonin.id, slot)
	attemptOf[jonin.id] = { hikei = hikeiId, ok = ok, reason = failure, at = now }
	if ok then
		HikeiHandan.recordUse(state, now)
		print(`[HikeiHandan] {jonin.displayName} が {hikeiId} を使った`)
	else
		HikeiHandan.recordFailure(state, jonin.id, hikeiId, now)
		print(`[HikeiHandan] {jonin.displayName} は {hikeiId} を使えなかった（{failure}）`)
	end
	return hikeiId, ok, failure
end

-- 考える間隔ごとに呼ばれる判断。敵軍の上忍か首領の判断の周期が来ていて、敵軍全体の使用間隔が明けていれば、
-- 条件のそろった秘計を使う
local function decide(situation: JoninKotaiService.Situation)
	local jonin = situation.jonin
	if jonin.gun ~= "Tekigun" or Jonin.isDefeated(jonin) then
		return
	end
	if not HikeiHandan.isDue(state, jonin.id, situation.now) then
		return
	end
	local mochikomi, used = HikeiService.getJoninMochikomi(jonin.id)
	local hikei = HikeiHandan.usableOf(state, jonin.id, mochikomi, used, situation.now)
	if #hikei > 0 then
		tryUse(jonin, mochikomi, hikei, situation.now)
	end
end

-- 敵軍のだれかが秘計を使ったら、敵軍全体の使用間隔を始める（判断で使ったときも、窓口で使わせたときも）
local function onActivated(user: string, _userName: string, gun: Gun.Gun, hikeiId: string)
	if gun ~= "Tekigun" then
		return
	end
	local now = os.clock()
	HikeiHandan.recordUse(state, now)
	lastUse = { user = user, hikei = hikeiId, at = now }
end

-- 判断の記録を空にする
local function reset()
	state = HikeiHandan.newState()
	table.clear(attemptOf)
	lastUse = nil
end

local function round(value: number): number
	return math.round(value * 10) / 10
end

local function listOf(ids: { string }): string
	return if #ids > 0 then table.concat(ids, "、") else "なし"
end

-- 窓口に出す名前。プレイヤーは名前、上忍と首領はキャラクター ID
local function labelOf(unit: HikeiHandan.Unit): string
	if unit.kind == "Player" then
		local userId = tonumber(unit.id)
		local player = if userId then Players:GetPlayerByUserId(userId) else nil
		return if player then player.Name else unit.id
	end
	return unit.id
end

-- 窓口に出す、敵軍の上忍か首領の判断の様子
local function describe(jonin: Jonin.Jonin, now: number): { [string]: any }
	local mochikomi, used = HikeiService.getJoninMochikomi(jonin.id)
	local summary = summarize(jonin, HikeiHandan.usableOf(state, jonin.id, mochikomi, used, now))
	local retry: { [string]: number } = {}
	local waiting = false
	for _, hikeiId in mochikomi do
		local remaining = HikeiHandan.retryWaitOf(state, jonin.id, hikeiId, now)
		if remaining > 0 then
			retry[hikeiId] = round(remaining)
			waiting = true
		end
	end
	-- 大喝と挑発の半径の広い方の中にいる相手
	local radius = math.max(Config.Daikatsu.Radius, Config.Chohatsu.Radius)
	local aite = {}
	for _, unit in summary.units do
		local dx, dz = unit.x - summary.x, unit.z - summary.z
		local distance = math.sqrt(dx * dx + dz * dz)
		if unit.gun ~= jonin.gun and distance <= radius then
			table.insert(aite, {
				id = labelOf(unit),
				distance = round(distance),
				kyoka = if unit.kyoka then true else nil,
				shuryo = if unit.shuryo then true else nil,
				lured = if unit.lured then true else nil,
			})
		end
	end
	table.sort(aite, function(a, b)
		return a.distance < b.distance
	end)
	-- 伏兵・落石・大火計・兵糧庫・爆破罠の判断に使う、中にいる拠点・一番近い落石地点・一番近い大火計地域
	local kyoten, rakuseki, daikakei = summary.kyoten, summary.rakuseki, summary.daikakei
	local kyotenAite = HikeiHandan.kyotenAiteDistance(summary)
	local playerDistance = HikeiHandan.playerDistanceOf(summary)
	local nextAt = state.nextAt[jonin.id]
	local attempt = attemptOf[jonin.id]
	return {
		id = jonin.id,
		mochikomi = mochikomi,
		used = used,
		choice = HikeiHandan.decide(summary),
		kosen = summary.kosen,
		kishinka = summary.kishinka,
		health = round(jonin.health),
		maxHealth = round(jonin.stats.MaxHealth),
		nextIn = if nextAt then round(math.max(nextAt - now, 0)) else 0,
		retry = if waiting then retry else nil,
		aite = aite,
		attempt = if attempt
			then { hikei = attempt.hikei, ok = attempt.ok, reason = attempt.reason, ago = round(now - attempt.at) }
			else nil,
		kyoten = if kyoten
			then {
				id = kyoten.id,
				gun = kyoten.gun,
				honjin = kyoten.honjin,
				mattan = kyoten.mattan,
				hyoroko = kyoten.hyoroko,
				bakuhawana = kyoten.bakuhawana,
				taikyu = round(kyoten.taikyu),
				threshold = round(kyoten.threshold),
				fukuhei = if kyoten.fukuhei then true else nil,
				player = if playerDistance then round(playerDistance) else nil,
				aiteDistance = if kyotenAite then round(kyotenAite) else nil,
			}
			else nil,
		rakuseki = if rakuseki
			then {
				id = rakuseki.id,
				heitansen = rakuseki.heitansen,
				active = if rakuseki.active then true else nil,
			}
			else nil,
		daikakei = if daikakei then { id = daikakei.id, aiteCount = HikeiHandan.daikakeiAiteCount(summary) } else nil,
	}
end

local function registerDebugCommands()
	DebugCommand.register(
		"DumpHikeiHandan",
		"",
		"敵軍の上忍と首領の秘計の判断の様子を JSON で返す。敵軍全体の使用間隔の残り秒数（wait）、敵軍が最後に使った秘計（last）、"
			.. "上忍と首領ごとの持ち込み・使用済み・今の様子で選ぶ秘計（choice）・率いる部隊が交戦中か・鬼神化しているか・体力・"
			.. "中にいる拠点（kyoten。兵站線の末端か・兵糧庫か・爆破罠があるか・耐久と爆発する耐久・伏兵部隊が潜んでいるか・"
			.. "player は中心から一番近いプレイヤーまで、aiteDistance は中心から一番近い相手の部隊かプレイヤーまでの距離）・"
			.. "一番近い落石地点（rakuseki。heitansen は区間が入っている兵站線の軍、active は岩がもうあるか）・"
			.. "一番近い大火計地域（daikakei。aiteCount は中の相手の数）・"
			.. "次の判断までの秒数・試し直しを待つ秘計・周りの相手（大喝と挑発の半径の広い方の中）・最後に使おうとした結果",
		function()
			local now = os.clock()
			local list = {}
			for _, jonin in JoninService.list() do
				if jonin.gun == "Tekigun" and not Jonin.isDefeated(jonin) then
					table.insert(list, describe(jonin, now))
				end
			end
			local last = lastUse
			return HttpService:JSONEncode({
				wait = round(HikeiHandan.waitOf(state, now)),
				last = if last then { jonin = last.user, hikei = last.hikei, ago = round(now - last.at) } else nil,
				jonin = list,
			})
		end
	)
	DebugCommand.register(
		"DecideHikei",
		"<キャラクター ID>",
		"敵軍の上忍か首領に、判断の周期・敵軍全体の使用間隔・試し直しの待ちを待たずに判断させ、条件のそろった秘計を"
			.. "秘計の入口で使わせる。使ったら敵軍全体の使用間隔が始まる。SetJoninAI false でも判断させる（確認用）",
		function(id)
			local jonin = if type(id) == "string" then JoninService.get(id) else nil
			if not jonin then
				return `{tostring(id)} は出撃したステージの上忍と首領にいない`
			end
			if Jonin.isDefeated(jonin) then
				return `{jonin.displayName} は倒れている`
			end
			if jonin.gun ~= "Tekigun" then
				return `{jonin.displayName} は味方軍なので、秘計を使わない`
			end
			local mochikomi, used = HikeiService.getJoninMochikomi(jonin.id)
			local hikei = {}
			for _, hikeiId in mochikomi do
				if not table.find(used, hikeiId) then
					table.insert(hikei, hikeiId)
				end
			end
			local hikeiId, ok, failure = tryUse(jonin, mochikomi, hikei, os.clock())
			if not hikeiId then
				local usable = listOf(hikei)
				return `{jonin.displayName} は条件のそろう秘計が無いので、使わなかった（使える秘計 {usable}）`
			end
			if not ok then
				return `{jonin.displayName} は {hikeiId} を使えなかった（{failure}）`
			end
			return `{jonin.displayName} が {hikeiId} を使った`
		end
	)
	DebugCommand.register(
		"ResetHikeiHandan",
		"",
		"敵軍の秘計の判断の記録（敵軍全体の使用間隔・判断の周期・試し直しの待ち・最後の結果）を空にする。"
			.. "持ち込みと使用済みは変えない（確認用）",
		function()
			reset()
			return "敵軍の秘計の判断の記録を空にした（敵軍全体の使用間隔の待ちも外した）"
		end
	)
end

function HikeiHandanService.start()
	JoninKotaiService.setHikeiDecider(decide)
	HikeiService.activated:Connect(onActivated)
	StageService.started:Connect(reset)
	StageService.phaseChanged:Connect(function(next: StagePhase.Phase)
		if next == "Lobby" then
			reset()
		end
	end)
	registerDebugCommands()
end

return HikeiHandanService
