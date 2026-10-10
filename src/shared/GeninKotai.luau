--!strict
-- 実体化圏の下忍の個体の数の計画。両軍の部隊ごとに、個体として出しておく下忍の数（目標）を決める。
-- 出す・消すの判定は Jittaikaken、まとまりの分け方と整数への分け方は KotaiHaibun、数値は Config.luau の
-- GeninKotai・Jittaikaken・KotaiHaibun 節にある。Roblox の API は使わない。位置は水平の (x, z)。
--
-- 兵数と個体の数え方
-- - 兵数は部隊の下忍の全体の数のまま持つ。個体は、そのうちの何人かを姿として出したもの（借り出し）
-- - 個体の数は兵数を超えない。消えた個体は部隊に戻る（兵数は変わらない。返却）
-- - 個体が倒れたら兵数を1減らす（呼ぶ側。ButaiService.changeHeisu）
--
-- 出す対象（両軍で同じ）
-- - 部隊が出撃メンバーの誰かから AppearRadius 以内に入ったら出す対象にし、全員から DisappearRadius より離れるまで
--   対象に残す（今の個体が1体以上いれば出ているとみなす。縁を行き来しても出入りを繰り返さない）。兵数 0 の部隊は出さない
-- - 出す対象の部隊は、一番近いメンバーのまとまりに数える（KotaiHaibun.group・assign。#85 と同じ）
--
-- 枠の分け方（planWaku）。両軍の合計の上限 cap を先にまとまりへ分け、まとまりの取り分の rate までを味方軍にする
-- - 取り分 S: cap をまとまりの人数の比で分けた数（兵数の制限なし）
-- - 味方軍の上限 c = floor(S × rate)。離れた2人なら S は 20 ずつで、味方軍は 5 ずつまで
-- - 需要 D = 敵軍の兵数の合計 E + min(味方軍の兵数の合計 A, c)
-- - 枠 Q: cap をまとまりの人数の比で、D を超えないように分けた数（#85 と同じ。余った分はほかのまとまりへ人数の比で回す。
--   味方軍だけのまとまりは味方軍の分しか取らず、残りはほかのまとまりの敵軍へ回る）
-- - 味方軍の目標の合計 a = min(A, c, Q)。まとまりの中の味方軍の部隊へ兵数の比で分ける
-- - 敵軍の枠 C = Q − h。h は味方軍が押さえている数（heldOf。0〜Q に収める）。C をまとまりの中の敵軍の部隊へ兵数の比で分ける
--   （tekiTargets）。まだ出ていない味方軍の目標は h に入らない（同じまとまりの敵軍を、味方軍の予約だけでは減らさない）。
--   目標より多く出ている味方軍の個体（視界の中で戻せない個体）は h に数え、同じまとまりの敵軍が返す（ほかのまとまりは減らない）
-- - ただし D は味方軍の上限までの兵数を含むので、まだ出ていない味方軍の分も、ほかのまとまりへ回す余りからは除く
--   （味方軍は自分のまとまりの取り分から出し、ほかのまとまりの敵軍に返させない）
-- - 端数は KotaiHaibun.split と同じく、切り捨てた残りの大きい順に1つずつ足す
-- - まとまりごとに h + 敵軍の目標の合計 ≤ Q、Q の合計 ≤ cap。味方軍の目標の合計は c と Q を超えない
--
-- 枠の返却（updateRequests・heldOf・hojuStopped・pickReturns・fill）
-- - 返却の求めは、今出せる味方軍の部隊だけが持つ。今出せる = 部隊の周りに視界の外に出せる位置があり、
--   まとまりの味方軍の予算（a − まとまりの味方軍の出ている数）が 1 以上。今出せない部隊の求めは取り下げ（予約は数えず、
--   敵軍の補充も止めない）、また出せるようになったら step から積み直す。求めは足りない数とまとまりの味方軍の予算を超えない
-- - 求めを step 増やすのは、まとまりの前の返却が済んでいる（まとまりの敵軍の出ている数の合計 ≤ 今の求めで決めた敵軍の目標の
--   合計）ときだけで、1回の判断で増やすのはまとまりの1部隊だけ（足りない数の多い部隊）。済んでいなければ増やさずに保つ。
--   出た味方軍の個体は求めから引かないので、敵軍が返し続ける間は、1回の判断で返す数は step のまま（a = 10 なら 2 体ずつ）。
--   待っている間に撃破で前の返却が済むと求めが1段増えるので、その後に返せるようになった判断では、求めの数まで返す
-- - 目標が 0 になったら（部隊が離れたら）取り消し、足りたら外す。前のまとまりとメンバーが1人も重ならないまとまりへ移ったら
--   0 から積み直す（sharesMember。移った先の敵軍に、前のまとまりで積んだ数を一度に返させない）
-- - h は、味方軍の部隊ごとの max(出ている数, min(目標, 出ている数 + 返却の求め)) の合計。求めが増えると敵軍の枠が減る
-- - 敵軍の個体は、まとまりごとにまとめて戻す。戻す数は、まとまりの敵軍の部隊の出ている数の合計 − 目標の合計。
--   まとまりの敵軍の全部隊の個体を出撃メンバーから遠い順に並べ、視界の外の個体だけを戻す（pickReturns。
--   視界の中の個体は戻さない）。片方の部隊の個体がすべて視界の中でも、ほかの部隊の視界の外の個体から返せる
-- - 敵軍の部隊ごとの目標は、出す側（fill の足りない数）にだけ使う。戻した結果、目標より多い部隊と少ない部隊が
--   残ってよい（まとまりの予算で出しすぎない）。味方軍の部隊と、どのまとまりにも入らない部隊は、部隊ごとに戻す
-- - 返却を求めている（今出せる）味方軍の部隊がいるまとまりでは、敵軍の補充を止める。空いた枠は待っている味方軍に先に回す
-- - 出す順（fill）は、味方軍の足りない部隊が先で、次に敵軍。まとまりの予算（Q − まとまりの出ている数）、味方軍の予算
--   （a − まとまりの味方軍の出ている数）、全体の予算（呼ぶ側が渡す）を超えない

local Config = require("./Config")
local Gun = require("./Gun")
local Jittaikaken = require("./Jittaikaken")
local KotaiHaibun = require("./KotaiHaibun")

export type Params = {
	jittaikaken: Config.JittaikakenSection?,
	haibun: Config.KotaiHaibunSection?,
}

-- 部隊の今の様子。present は今出している個体の数
export type ButaiState = { id: string, gun: Gun.Gun, x: number, z: number, heisu: number, present: number }

-- まとまりの枠（窓口の確認用の値も含む）
export type WakuGroup = {
	-- まとまりのメンバーの id（名前の順）
	members: { string },
	-- 取り分 S（cap を人数の比で分けた数）
	share: number,
	-- 味方軍の上限 c = floor(S × rate)
	mikataCap: number,
	-- まとまりに数えた出す対象の部隊の兵数の合計（味方軍 A・敵軍 E）
	mikataHeisu: number,
	tekiHeisu: number,
	-- 需要 D = E + min(A, c)
	demand: number,
	-- 枠 Q
	quota: number,
	-- 味方軍の目標の合計 a = min(A, c, Q)
	mikataTarget: number,
	-- まとまりに数えた出す対象の部隊の ID（名前の順）
	mikataButai: { string },
	tekiButai: { string },
}

export type WakuPlan = {
	-- 味方軍の部隊 ID ごとの目標（出す対象でない部隊は 0）
	mikataTargets: { [string]: number },
	-- 部隊 ID ごとの、一番近いメンバーまでの水平の距離（メンバーがいなければ入らない）
	distances: { [string]: number },
	-- 出す対象の部隊 ID ごとの、まとまりの番号（groups の添字。判断ごとに変わることがある）
	groupOf: { [string]: number },
	-- 部隊 ID ごとの兵数（0 以上の整数にしたもの）
	heisuOf: { [string]: number },
	-- 敵軍の部隊 ID（出す対象でない部隊も含む。渡した順）
	tekiButai: { string },
	groups: { WakuGroup },
}

export type TekiPlan = {
	-- 敵軍の部隊 ID ごとの目標（出す対象でない部隊は 0）
	targets: { [string]: number },
	-- まとまりごとの、味方軍が押さえている数 h（0〜Q に収めたもの）
	held: { number },
	-- まとまりごとの、敵軍の枠 C = Q − h
	quotas: { number },
}

-- 味方軍の部隊ごとの返却の求め。部隊 ID で持つので、まとまりの番号が判断ごとに変わっても引き継ぐ
export type Requests = {
	-- 部隊 ID ごとの求めの数（求めていない部隊は入らない）
	counts: { [string]: number },
	-- 部隊 ID ごとの、求めたまとまりのメンバーの名前
	members: { [string]: { string } },
}

-- 1部隊の求めを決める材料（updateRequest）
export type RequestInput = {
	-- 今の求め（無ければ nil）
	prev: number?,
	target: number,
	present: number,
	-- 部隊の周りに、視界の外に出せる位置があるか
	spawnable: boolean,
	-- まとまりの味方軍の予算（a − まとまりの味方軍の出ている数）
	budget: number,
	-- この判断で求めを増やす番か（まとまりの前の返却が済んでいて、まとまりで増やす1部隊に選ばれた）
	grow: boolean,
	step: number,
}

-- 部隊ごとの求めの移り変わり（記録用）。before は前の判断の求め（別のまとまりへ移って積み直したら nil で、
-- 前の数とまとまりは movedFrom・movedCount）。spawnable は確かめたときだけ入る
export type RequestNote = {
	before: number?,
	after: number?,
	target: number,
	present: number,
	budget: number,
	spawnable: boolean?,
	movedFrom: { string }?,
	movedCount: number?,
}

local GeninKotai = {}

-- 両軍の部隊の目標を決めるための枠の計画。cap は両軍とパーティー全体の合計の上限、rate はまとまりの取り分のうち
-- 味方軍に回す割合の上限（0〜1）。敵軍の目標は、味方軍が押さえている数を渡して tekiTargets で決める
function GeninKotai.planWaku(
	butai: { ButaiState },
	members: { KotaiHaibun.Member },
	cap: number,
	rate: number,
	params: Params?
): WakuPlan
	local jittaikaken = if params and params.jittaikaken then params.jittaikaken else Config.Jittaikaken
	local haibun = if params and params.haibun then params.haibun else Config.KotaiHaibun
	local whole = math.max(math.floor(cap), 0)
	local mikataRate = math.clamp(rate, 0, 1)
	local points = {}
	for _, member in members do
		table.insert(points, { x = member.x, z = member.z })
	end

	local mikataTargets: { [string]: number } = {}
	local distances: { [string]: number } = {}
	local heisuOf: { [string]: number } = {}
	local gunOf: { [string]: Gun.Gun } = {}
	local tekiButai: { string } = {}
	local eligible: { KotaiHaibun.ButaiInput } = {}
	for _, entry in butai do
		local heisu = math.max(math.floor(entry.heisu), 0)
		heisuOf[entry.id] = heisu
		gunOf[entry.id] = entry.gun
		if entry.gun == "Mikatagun" then
			mikataTargets[entry.id] = 0
		else
			table.insert(tekiButai, entry.id)
		end
		local distance = Jittaikaken.nearestDistance({ x = entry.x, z = entry.z }, points)
		if distance then
			distances[entry.id] = distance
		end
		if heisu > 0 and Jittaikaken.shouldAppear(entry.present > 0, distance, jittaikaken) then
			table.insert(eligible, { id = entry.id, x = entry.x, z = entry.z, heisu = heisu })
		end
	end

	-- 出す対象の部隊は誰かから消滅の半径の内にいるので、数える距離にその半径を渡す
	local memberGroups = KotaiHaibun.group(members, haibun.GroupDistance)
	local groupOf = KotaiHaibun.assign(memberGroups, eligible, jittaikaken.DisappearRadius)

	local weights: { number } = {}
	local unlimited: { number } = {}
	for index, group in memberGroups do
		weights[index] = #group
		unlimited[index] = math.huge
	end
	local shares = KotaiHaibun.split(weights, unlimited, whole)

	local groups: { WakuGroup } = {}
	for index, group in memberGroups do
		local ids = {}
		for _, member in group do
			table.insert(ids, member.id)
		end
		groups[index] = {
			members = ids,
			share = shares[index],
			-- 割合の掛け算の誤差で1つ少なくならないよう、わずかに足してから切り捨てる
			mikataCap = math.floor(shares[index] * mikataRate + 1e-9),
			mikataHeisu = 0,
			tekiHeisu = 0,
			demand = 0,
			quota = 0,
			mikataTarget = 0,
			mikataButai = {},
			tekiButai = {},
		}
	end
	for _, entry in eligible do
		local index = groupOf[entry.id]
		if index then
			local group = groups[index]
			if gunOf[entry.id] == "Mikatagun" then
				group.mikataHeisu += entry.heisu
				table.insert(group.mikataButai, entry.id)
			else
				group.tekiHeisu += entry.heisu
				table.insert(group.tekiButai, entry.id)
			end
		end
	end

	local demands: { number } = {}
	for index, group in groups do
		table.sort(group.mikataButai)
		table.sort(group.tekiButai)
		group.demand = group.tekiHeisu + math.min(group.mikataHeisu, group.mikataCap)
		demands[index] = group.demand
	end
	local quotas = KotaiHaibun.split(weights, demands, whole)
	for index, group in groups do
		group.quota = quotas[index]
		group.mikataTarget = math.min(group.mikataHeisu, group.mikataCap, group.quota)
		local heisuList = {}
		for _, id in group.mikataButai do
			table.insert(heisuList, heisuOf[id])
		end
		local targets = KotaiHaibun.split(heisuList, heisuList, group.mikataTarget)
		for position, id in group.mikataButai do
			mikataTargets[id] = targets[position]
		end
	end

	return {
		mikataTargets = mikataTargets,
		distances = distances,
		groupOf = groupOf,
		heisuOf = heisuOf,
		tekiButai = tekiButai,
		groups = groups,
	}
end

-- まとまりごとの、味方軍が押さえている数。味方軍の部隊ごとの max(出ている数, min(目標, 出ている数 + 返却の求め)) の合計。
-- present と requested は部隊 ID から引く（無ければ 0）。まだ出ていない味方軍の目標は、求めた分しか数えない。
-- 目標より多く出ている部隊（視界の中で戻せない個体）は、出ている数をそのまま数える
function GeninKotai.heldOf(plan: WakuPlan, present: { [string]: number }, requested: { [string]: number }): { number }
	local result: { number } = {}
	for index, group in plan.groups do
		local total = 0
		for _, id in group.mikataButai do
			local target = plan.mikataTargets[id] or 0
			local count = present[id] or 0
			total += math.max(count, math.min(target, count + (requested[id] or 0)))
		end
		result[index] = total
	end
	return result
end

-- 敵軍の部隊ごとの目標。held はまとまりごとの味方軍が押さえている数（heldOf）で、0〜Q に収めて使う。
-- 敵軍の枠 C = Q − h を、まとまりの中の敵軍の部隊へ兵数の比で分ける（部隊の目標は兵数を超えない）
function GeninKotai.tekiTargets(plan: WakuPlan, held: { number }): TekiPlan
	local targets: { [string]: number } = {}
	for _, id in plan.tekiButai do
		targets[id] = 0
	end
	local heldResult: { number } = {}
	local quotas: { number } = {}
	for index, group in plan.groups do
		local h = math.clamp(math.floor(held[index] or 0), 0, group.quota)
		local quota = group.quota - h
		heldResult[index] = h
		quotas[index] = quota
		local heisuList = {}
		for _, id in group.tekiButai do
			table.insert(heisuList, plan.heisuOf[id])
		end
		local shares = KotaiHaibun.split(heisuList, heisuList, quota)
		for position, id in group.tekiButai do
			targets[id] = shares[position]
		end
	end
	return { targets = targets, held = heldResult, quotas = quotas }
end

-- 味方軍の部隊の、返却の求めの次の数（無ければ nil）。
-- - 目標が 0 以下なら取り消し、足りない数が 0 なら外す
-- - 今出せない（出せる位置が無いか、まとまりの味方軍の予算が 0）なら取り下げる（予約は数えず、補充も止めない）
-- - 増やす番なら step 増やし、そうでなければ保つ。どちらも足りない数とまとまりの味方軍の予算を超えない
function GeninKotai.updateRequest(input: RequestInput): number?
	if input.target <= 0 then
		return nil
	end
	local short = math.max(input.target - input.present, 0)
	if short <= 0 or not input.spawnable or input.budget <= 0 then
		return nil
	end
	local limit = math.min(short, input.budget)
	local base = math.max(input.prev or 0, 0)
	local nextValue = if input.grow then math.min(limit, base + math.max(input.step, 0)) else math.min(limit, base)
	return if nextValue > 0 then nextValue else nil
end

-- 2つのまとまりのメンバー（名前の一覧）が1人でも重なるか。重なれば、味方軍の部隊は同じまとまりにいるとみなし、
-- 返却の求めを引き継ぐ（メンバーが倒れた・合流した・離れただけでは積み直さない）
function GeninKotai.sharesMember(a: { string }, b: { string }): boolean
	for _, name in a do
		if table.find(b, name) then
			return true
		end
	end
	return false
end

-- まとまりごとの、敵軍の補充を止めているか（返却を求めている味方軍の部隊がいる）
function GeninKotai.hojuStopped(plan: WakuPlan, requested: { [string]: number }): { boolean }
	local result: { boolean } = {}
	for index, group in plan.groups do
		local stopped = false
		for _, id in group.mikataButai do
			if (requested[id] or 0) > 0 then
				stopped = true
				break
			end
		end
		result[index] = stopped
	end
	return result
end

-- 味方軍の部隊ごとの返却の求めを、1回の判断ぶん進める。present は部隊 ID ごとの今出ている数、prev は前の判断の求め、
-- spawnable(id) はその部隊の周りに視界の外に出せる位置があるか（足りない数があり、まとまりの味方軍の予算が 1 以上で、
-- 求めているか、まとまりの前の返却が済んでいる部隊についてだけ呼ぶ）、step は増やす数。
-- - メンバーが1人も重ならないまとまりへ移った部隊は、前の求めを 0 から積み直す
-- - まとまりの前の返却が済んでいれば（まとまりの敵軍の出ている数の合計 ≤ 前の求めで決めた敵軍の目標の合計）、
--   増やせる部隊のうち足りない数の多い1部隊（同じなら ID の順）だけを step 増やす
-- - 出す対象でない部隊（目標 0）と、いなくなった部隊の求めは残さない
-- 次の求めと、味方軍の部隊ごとの移り変わり（記録用）を返す
function GeninKotai.updateRequests(
	plan: WakuPlan,
	present: { [string]: number },
	prev: Requests,
	spawnable: (id: string) -> boolean,
	step: number
): (Requests, { [string]: RequestNote })
	-- 前のまとまりとメンバーが重ならないまとまりへ移った部隊は、前の求めを数えない
	local base: { [string]: number } = {}
	local movedFrom: { [string]: { string } } = {}
	for id, count in prev.counts do
		local index = plan.groupOf[id]
		local previous = prev.members[id]
		if index and plan.mikataTargets[id] then
			if previous and not GeninKotai.sharesMember(previous, plan.groups[index].members) then
				movedFrom[id] = previous
			else
				base[id] = count
			end
		end
	end
	local done = {}
	local before = GeninKotai.tekiTargets(plan, GeninKotai.heldOf(plan, present, base))
	for index, group in plan.groups do
		local tekiPresent, tekiTarget = 0, 0
		for _, id in group.tekiButai do
			tekiPresent += present[id] or 0
			tekiTarget += before.targets[id] or 0
		end
		done[index] = tekiPresent <= tekiTarget
	end

	local counts: { [string]: number } = {}
	local members: { [string]: { string } } = {}
	local notes: { [string]: RequestNote } = {}
	for id, target in plan.mikataTargets do
		notes[id] = {
			-- まとまりに入らない部隊（目標 0）の前の求めも、取り消したことが分かるよう入れる
			before = if movedFrom[id] then nil else prev.counts[id],
			after = nil,
			target = target,
			present = present[id] or 0,
			budget = 0,
			spawnable = nil,
			movedFrom = movedFrom[id],
			movedCount = if movedFrom[id] then prev.counts[id] else nil,
		}
	end
	for index, group in plan.groups do
		local mikataPresent = 0
		for _, id in group.mikataButai do
			mikataPresent += present[id] or 0
		end
		local budget = math.max(group.mikataTarget - mikataPresent, 0)
		-- 今出せる部隊を確かめ、まとまりで増やす1部隊を選ぶ
		local grower: string? = nil
		local growerShort = 0
		for _, id in group.mikataButai do
			local note = notes[id]
			note.budget = budget
			local short = math.max(note.target - note.present, 0)
			-- 求めていない部隊は、前の返却が済んでいなければ求めを始められないので、位置を確かめない
			if note.target > 0 and short > 0 and budget > 0 and (base[id] ~= nil or done[index]) then
				note.spawnable = spawnable(id)
				local room = math.min(short, budget) > (base[id] or 0)
				if note.spawnable and room and done[index] then
					if grower == nil or short > growerShort or (short == growerShort and id < (grower :: string)) then
						grower, growerShort = id, short
					end
				end
			end
		end
		for _, id in group.mikataButai do
			local note = notes[id]
			note.after = GeninKotai.updateRequest({
				prev = base[id],
				target = note.target,
				present = note.present,
				spawnable = note.spawnable == true,
				budget = budget,
				grow = grower == id,
				step = step,
			})
			local after = note.after
			if after then
				counts[id] = after
				members[id] = group.members
			end
		end
	end
	return { counts = counts, members = members }, notes
end

-- 目標より多い個体を戻すときの候補。item は呼ぶ側の個体（体のモデルなど）、butai はその部隊 ID、
-- distance は戦場を見ている出撃メンバーまでの一番近い水平の距離
export type ReturnCandidate<T> = { item: T, butai: string, distance: number }

-- 戻す個体を、出撃メンバーから遠い順に count 体まで選ぶ（同じ距離なら部隊 ID の順、同じ部隊なら渡した順）。
-- canReturn が false の候補（視界の中で、メンバーから PopDistance 以内の個体）は飛ばして、次に遠い候補を見る。
-- 戻せる候補が足りなければ、戻せる分だけを選ぶ。count 体を選び終えたら canReturn を呼ばない。選んだ候補を遠い順に返す
function GeninKotai.pickReturns<T>(
	candidates: { ReturnCandidate<T> },
	count: number,
	canReturn: (ReturnCandidate<T>) -> boolean
): { ReturnCandidate<T> }
	local order = {}
	for index, candidate in candidates do
		table.insert(order, { candidate = candidate, index = index })
	end
	table.sort(order, function(a, b)
		if a.candidate.distance ~= b.candidate.distance then
			return a.candidate.distance > b.candidate.distance
		end
		if a.candidate.butai ~= b.candidate.butai then
			return a.candidate.butai < b.candidate.butai
		end
		return a.index < b.index
	end)
	local limit = math.max(math.floor(count), 0)
	local picked: { ReturnCandidate<T> } = {}
	for _, entry in order do
		if #picked >= limit then
			break
		end
		if canReturn(entry.candidate) then
			table.insert(picked, entry.candidate)
		end
	end
	return picked
end

type Need = { id: string, group: number, mikata: boolean, missing: number }

-- 目標に足りない部隊へ出す数を決め、spawn(部隊 ID, 出したい数) を呼ぶ。spawn は実際に出した数を返す
-- （視界の外に出せる位置が無ければ少ない）。present は部隊 ID ごとの今出ている数、budget は全体の予算
-- （1回の判断の上限と、cap − 出ている総数の小さい方）。
-- 味方軍の足りない部隊を先に（足りない数の多い順、同じなら ID の順）、次に敵軍の足りない部隊を同じ順に回る。
-- まとまりの予算（Q − まとまりの出ている数）、味方軍の予算（a − まとまりの味方軍の出ている数）、全体の予算を超えない。
-- 補充を止めているまとまり（hojuStopped）の敵軍には出さない。部隊 ID ごとに出した数を返す
function GeninKotai.fill(
	plan: WakuPlan,
	teki: TekiPlan,
	present: { [string]: number },
	requested: { [string]: number },
	budget: number,
	spawn: (id: string, want: number) -> number
): { [string]: number }
	local stopped = GeninKotai.hojuStopped(plan, requested)
	local groupBudget: { number } = {}
	local mikataBudget: { number } = {}
	local needs: { Need } = {}
	for index, group in plan.groups do
		local mikataPresent, tekiPresent = 0, 0
		for _, id in group.mikataButai do
			mikataPresent += present[id] or 0
			local missing = (plan.mikataTargets[id] or 0) - (present[id] or 0)
			if missing > 0 then
				table.insert(needs, { id = id, group = index, mikata = true, missing = missing })
			end
		end
		for _, id in group.tekiButai do
			tekiPresent += present[id] or 0
			local missing = (teki.targets[id] or 0) - (present[id] or 0)
			if missing > 0 and not stopped[index] then
				table.insert(needs, { id = id, group = index, mikata = false, missing = missing })
			end
		end
		groupBudget[index] = math.max(group.quota - mikataPresent - tekiPresent, 0)
		-- 目標が減った味方軍の部隊の個体が視界の中で戻せずに残る間は、ほかの味方軍の部隊へ出さない
		mikataBudget[index] = math.max(group.mikataTarget - mikataPresent, 0)
	end
	table.sort(needs, function(a, b)
		if a.mikata ~= b.mikata then
			return a.mikata
		end
		if a.missing ~= b.missing then
			return a.missing > b.missing
		end
		return a.id < b.id
	end)

	local remaining = math.max(math.floor(budget), 0)
	local spawnedOf: { [string]: number } = {}
	for _, need in needs do
		if remaining <= 0 then
			break
		end
		local want = math.min(need.missing, groupBudget[need.group], remaining)
		if need.mikata then
			want = math.min(want, mikataBudget[need.group])
		end
		if want > 0 then
			local spawned = math.clamp(math.floor(spawn(need.id, want)), 0, want)
			spawnedOf[need.id] = spawned
			groupBudget[need.group] -= spawned
			remaining -= spawned
			if need.mikata then
				mikataBudget[need.group] -= spawned
			end
		end
	end
	return spawnedOf
end

return GeninKotai
