--!strict
-- 上忍と首領の個体の戦い方の判断。狙う相手の選択・間合いまで近づく位置・型の選択・型の判定の時刻を決める。
-- 型と数値は Config.luau の Kata 節にある。時刻と乱数は引数で受け取り、Roblox の API は使わない。
-- 個体を動かして判定を当てるのはサーバーの JoninKotaiService で、相手の一覧を渡せばどちらの軍の個体にも使える。
--
-- - 個体は追いかける範囲の中で戦う。上忍は戻る位置（率いる部隊の位置）から ChaseRadius の円（circle）、
--   首領は本陣の範囲。範囲は、外の位置を範囲の縁へ寄せる関数（Clamp）で渡す
-- - 狙える相手は、個体から AggroRange 以内で、追いかける範囲の外へ出ている距離が Maai 以内の相手
--   （範囲の縁まで追いかければ、間合いで届く相手）
-- - 狙う相手は、最後に攻撃してきた相手が AttackerMemory 秒以内に攻撃していて狙えるなら、その相手。
--   そうでなければ一番近い相手。今狙っている相手は、一番近い相手より SwitchMargin 以上遠くなるまで替えない
-- - 近づく位置は、狙う相手の中心から Maai だけ手前（個体の側）。追いかける範囲の外なら、範囲の縁へ寄せる
-- - 型は、間合い（型の Maai）に入っている型から、重み（Weight）に比例した確率で1つ選ぶ。首領は首領だけの型も選ぶ
-- - 型は、予備動作（YobiDosa）の後に判定を出し（Active）、後隙（Recovery）の間は動かない。時間は攻撃の速さで割る
-- - 型を出し終えたら、Interval 秒に 0〜IntervalRandom 秒を足した後に、次の型を選ぶ
-- - 位置は水平の (x, z) で扱う

local ActionState = require("./ActionState")
local Config = require("./Config")

export type Params = Config.KataSection
export type Def = Config.KataDef

-- 水平の位置。x は東、z は南が +（ワールドの座標）
export type Point = { x: number, z: number }

-- 追いかける範囲に位置を収める関数。範囲の中の位置はそのまま返し、外の位置は範囲の縁へ寄せる
export type Clamp = (point: Point) -> Point

-- 型1つ。id は Config.luau の Kata 節の型 ID、shuryo は首領だけの型か
export type Entry = {
	id: string,
	def: Def,
	shuryo: boolean,
}

-- 狙う相手の候補。key は相手を見分ける値
export type Candidate<K> = {
	key: K,
	-- 個体から相手までの水平の距離
	distance: number,
	-- 相手が追いかける範囲の外へ出ている水平の距離（範囲の中なら 0）
	beyond: number,
}

-- 最後に攻撃してきた相手と、攻撃してきた時刻
export type Attacker<K> = {
	key: K,
	at: number,
}

local Kata = {}

-- 2点の水平の距離
function Kata.distance(a: Point, b: Point): number
	local dx, dz = a.x - b.x, a.z - b.z
	return math.sqrt(dx * dx + dz * dz)
end

-- 中心 center から半径 radius の円を、追いかける範囲にする関数（上忍の戻る位置の周り）
function Kata.circle(center: Point, radius: number): Clamp
	return function(point: Point): Point
		local dx, dz = point.x - center.x, point.z - center.z
		local reach = math.sqrt(dx * dx + dz * dz)
		if reach <= radius then
			return { x = point.x, z = point.z }
		end
		return { x = center.x + dx / reach * radius, z = center.z + dz / reach * radius }
	end
end

-- 位置 point にいる相手 key の、狙う相手の候補。here は個体の位置、clamp は追いかける範囲
function Kata.candidateOf<K>(key: K, here: Point, point: Point, clamp: Clamp): Candidate<K>
	return { key = key, distance = Kata.distance(here, point), beyond = Kata.distance(point, clamp(point)) }
end

-- 狙える相手か。個体から AggroRange 以内で、追いかける範囲の外へ出ている距離が Maai 以内
function Kata.canTarget<K>(candidate: Candidate<K>, params: Params?): boolean
	local p = params or Config.Kata
	return candidate.distance <= p.AggroRange and candidate.beyond <= p.Maai
end

-- 狙う相手を選ぶ。current は今狙っている相手、attacker は最後に攻撃してきた相手。狙える相手がいなければ nil
function Kata.chooseTarget<K>(
	candidates: { Candidate<K> },
	current: K?,
	attacker: Attacker<K>?,
	now: number,
	params: Params?
): K?
	local p = params or Config.Kata
	local nearest: Candidate<K>? = nil
	local kept: Candidate<K>? = nil
	local attacked: Candidate<K>? = nil
	for _, candidate in candidates do
		if Kata.canTarget(candidate, p) then
			if nearest == nil or candidate.distance < nearest.distance then
				nearest = candidate
			end
			if current ~= nil and candidate.key == current then
				kept = candidate
			end
			if attacker and candidate.key == attacker.key then
				attacked = candidate
			end
		end
	end
	if attacker and attacked and now - attacker.at <= p.AttackerMemory then
		return attacked.key
	end
	if kept and nearest and kept.distance - nearest.distance < p.SwitchMargin then
		return kept.key
	end
	return if nearest then nearest.key else nil
end

-- 個体の今の位置 here から、狙う相手の中心 target へ近づいて止まる位置。相手から Maai だけ手前（個体の側）で、
-- 追いかける範囲 clamp の外なら範囲の縁へ寄せる。相手と同じ位置にいるときは、東へ Maai だけ離れる
function Kata.approachPoint(here: Point, target: Point, clamp: Clamp, params: Params?): Point
	local p = params or Config.Kata
	local dx, dz = here.x - target.x, here.z - target.z
	local distance = math.sqrt(dx * dx + dz * dz)
	local awayX, awayZ = 1, 0
	if distance > 1e-6 then
		awayX, awayZ = dx / distance, dz / distance
	end
	return clamp({ x = target.x + awayX * p.Maai, z = target.z + awayZ * p.Maai })
end

-- 出せる型を ID の順に並べる。上忍は Jonin の型だけ、首領は Shuryo の型も足す
function Kata.listOf(shuryo: boolean, params: Params?): { Entry }
	local p = params or Config.Kata
	local entries: { Entry } = {}
	for id, def in p.Jonin do
		table.insert(entries, { id = id, def = def, shuryo = false })
	end
	if shuryo then
		for id, def in p.Shuryo do
			table.insert(entries, { id = id, def = def, shuryo = true })
		end
	end
	table.sort(entries, function(a, b)
		return a.id < b.id
	end)
	return entries
end

-- 型 ID の型。無い ID は nil
function Kata.get(id: string, params: Params?): Entry?
	local p = params or Config.Kata
	local jonin = p.Jonin[id]
	if jonin then
		return { id = id, def = jonin, shuryo = false }
	end
	local shuryo = p.Shuryo[id]
	if shuryo then
		return { id = id, def = shuryo, shuryo = true }
	end
	return nil
end

-- 狙う相手までの水平の距離 distance で、間合い（型の Maai）に入っている型から、重みに比例して1つ選んで型 ID を返す。
-- roll は 0 以上 1 未満の乱数。間合いに入っている型が無ければ nil
function Kata.choose(entries: { Entry }, distance: number, roll: number): string?
	local usable: { Entry } = {}
	local total = 0
	for _, entry in entries do
		if distance <= entry.def.Maai and entry.def.Weight > 0 then
			table.insert(usable, entry)
			total += entry.def.Weight
		end
	end
	if #usable == 0 then
		return nil
	end
	local remaining = roll * total
	for _, entry in usable do
		remaining -= entry.def.Weight
		if remaining < 0 then
			return entry.id
		end
	end
	-- 浮動小数の端数で選び切れなかったら、最後の型
	return usable[#usable].id
end

-- 型を行動のタイムラインにする。発生（Startup）が予備動作で、判定（Hits）は予備動作の後 Delay 秒で出る。
-- 時間は攻撃の速さ attackSpeed（省くと 1）で割る。判定の時刻は ActionState.hits、全体の長さは ActionState.duration で求める
function Kata.timelineOf(def: Def, attackSpeed: number?): ActionState.Timeline
	local timeline: ActionState.Timeline = {
		Startup = def.YobiDosa,
		Active = def.Active,
		Recovery = def.Recovery,
		CancelFrom = def.YobiDosa + def.Active + def.Recovery,
		Advance = 0,
		Hits = def.Hits,
	}
	return ActionState.scale(timeline, attackSpeed or 1)
end

-- 型を出し終えた時刻 finishedAt から、次の型を選べる時刻。Interval 秒に roll（0 以上 1 未満の乱数）× IntervalRandom 秒を足す
function Kata.nextTime(finishedAt: number, roll: number, params: Params?): number
	local p = params or Config.Kata
	return finishedAt + p.Interval + roll * p.IntervalRandom
end

return Kata
