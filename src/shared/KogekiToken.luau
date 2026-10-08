--!strict
-- 攻撃トークン。1人のプレイヤーを同時に攻撃できる下忍を、プレイヤーごとに数体に絞る。
-- 攻撃トークンを持たない下忍は、周りを囲んで待つ。対象は下忍だけで、上忍と首領は攻撃トークンなしで攻撃する。
-- 数値は Config.luau の KogekiToken 節にある。時刻は呼ぶ側が渡し、Roblox の API は使わない。
--
-- - 考えるたびに、プレイヤーを狙っている下忍（候補）を渡して update を呼ぶ
-- - 候補から外れた下忍（倒れた、吹き飛んで倒れている、ほかのプレイヤーを狙った）と、
--   Range より離れた下忍は、攻撃トークンを返す。返した攻撃トークンはすぐに次の下忍へ渡る
-- - 空いた攻撃トークンは、Range の内にいて休んでいない候補のうち、プレイヤーに近い順に渡す
-- - 攻撃した下忍は攻撃トークンを返し（attacked）、Rest 秒は受け取らない。
--   返した攻撃トークンは Interval 秒たってから次の下忍へ渡る（攻撃の拍子が詰まらないように）
-- - 持っている下忍は、ほかの下忍の方が近くなっても返さない（近づく途中で入れ替わらないように）
-- - 下忍1体が持てる攻撃トークンは1つ。ほかのプレイヤーの分を持つ下忍には渡さない

local Config = require("./Config")

export type Params = Config.KogekiTokenSection

-- 攻撃トークンを受け取れる下忍。distance はプレイヤーの中心までの水平の距離（スタッド）
export type Candidate = { id: string, distance: number }

export type State = {
	-- プレイヤーのキーごとの、攻撃トークンを持つ下忍の ID と受け取った時刻
	holders: { [string]: { [string]: number } },
	-- 下忍の ID ごとの、攻撃トークンを持っている相手のプレイヤーのキー
	owners: { [string]: string },
	-- 下忍の ID ごとの、次に攻撃トークンを受け取れる時刻
	restUntil: { [string]: number },
	-- プレイヤーのキーごとの、攻撃して返された攻撃トークンを次に渡せる時刻
	cooldowns: { [string]: { number } },
}

-- update で動いた攻撃トークン。given は受け取った下忍、released は返した下忍
export type Changes = { given: { string }, released: { string } }

local KogekiToken = {}

function KogekiToken.new(): State
	return { holders = {}, owners = {}, restUntil = {}, cooldowns = {} }
end

local function holdersOf(state: State, playerKey: string): { [string]: number }
	local holders = state.holders[playerKey]
	if not holders then
		holders = {}
		state.holders[playerKey] = holders
	end
	return holders
end

local function release(state: State, playerKey: string, id: string)
	local holders = state.holders[playerKey]
	if holders then
		holders[id] = nil
	end
	if state.owners[id] == playerKey then
		state.owners[id] = nil
	end
end

-- 今、攻撃して返された攻撃トークンのうち、まだ次の下忍へ渡せないものの数。渡せるようになったものは消す
local function coolingCount(state: State, playerKey: string, now: number): number
	local cooldowns = state.cooldowns[playerKey]
	if not cooldowns then
		return 0
	end
	for index = #cooldowns, 1, -1 do
		if cooldowns[index] <= now then
			table.remove(cooldowns, index)
		end
	end
	return #cooldowns
end

-- id の下忍が playerKey のプレイヤーの攻撃トークンを持っているか
function KogekiToken.holds(state: State, playerKey: string, id: string): boolean
	return state.owners[id] == playerKey
end

-- id の下忍が攻撃トークンを持っている相手のプレイヤーのキー。持っていなければ nil
function KogekiToken.ownerOf(state: State, id: string): string?
	return state.owners[id]
end

-- playerKey のプレイヤーの攻撃トークンを持つ下忍の ID（名前の順）
function KogekiToken.holderIds(state: State, playerKey: string): { string }
	local ids = {}
	for id in state.holders[playerKey] or {} do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

-- playerKey のプレイヤーの攻撃トークンを持つ下忍の数
function KogekiToken.count(state: State, playerKey: string): number
	return #KogekiToken.holderIds(state, playerKey)
end

-- playerKey のプレイヤーの、攻撃して返されてまだ次の下忍へ渡せない攻撃トークンの数
function KogekiToken.coolingCount(state: State, playerKey: string, now: number): number
	return coolingCount(state, playerKey, now)
end

-- id の下忍が攻撃したあとで休んでいて、攻撃トークンを受け取れないか
function KogekiToken.isResting(state: State, id: string, now: number): boolean
	local untilTime = state.restUntil[id]
	return untilTime ~= nil and now < untilTime
end

-- playerKey のプレイヤーの攻撃トークンを、候補に合わせて返したり渡したりする。candidates はそのプレイヤーを狙っている下忍
function KogekiToken.update(
	state: State,
	playerKey: string,
	candidates: { Candidate },
	now: number,
	params: Params?
): Changes
	local p = params or Config.KogekiToken
	local holders = holdersOf(state, playerKey)
	local byId: { [string]: Candidate } = {}
	for _, candidate in candidates do
		byId[candidate.id] = candidate
	end

	local released = {}
	for id in holders do
		local candidate = byId[id]
		if not candidate or candidate.distance > p.Range then
			table.insert(released, id)
		end
	end
	table.sort(released)
	for _, id in released do
		release(state, playerKey, id)
	end

	local given = {}
	local free = p.PerPlayer - KogekiToken.count(state, playerKey) - coolingCount(state, playerKey, now)
	if free > 0 then
		local waiting = {}
		for _, candidate in candidates do
			local id = candidate.id
			if
				state.owners[id] == nil
				and candidate.distance <= p.Range
				and not KogekiToken.isResting(state, id, now)
			then
				table.insert(waiting, candidate)
			end
		end
		-- 近い順。同じ距離なら ID の順にして、呼ぶたびに結果が揺れないようにする
		table.sort(waiting, function(a, b)
			if a.distance ~= b.distance then
				return a.distance < b.distance
			end
			return a.id < b.id
		end)
		for index = 1, math.min(free, #waiting) do
			local id = waiting[index].id
			holders[id] = now
			state.owners[id] = playerKey
			table.insert(given, id)
		end
	end
	return { given = given, released = released }
end

-- id の下忍が playerKey のプレイヤーを攻撃した。攻撃トークンを返し、Rest 秒は受け取らない。
-- 返した攻撃トークンは Interval 秒たってから次の下忍へ渡る。攻撃トークンを持っていたら true
function KogekiToken.attacked(state: State, playerKey: string, id: string, now: number, params: Params?): boolean
	local p = params or Config.KogekiToken
	state.restUntil[id] = now + p.Rest
	if state.owners[id] ~= playerKey then
		return false
	end
	release(state, playerKey, id)
	local cooldowns = state.cooldowns[playerKey]
	if not cooldowns then
		cooldowns = {}
		state.cooldowns[playerKey] = cooldowns
	end
	table.insert(cooldowns, now + p.Interval)
	return true
end

-- id の下忍がいなくなった（倒れて片付けた）。持っていた攻撃トークンは次の update で次の下忍へ渡る
function KogekiToken.forget(state: State, id: string)
	local owner = state.owners[id]
	if owner then
		release(state, owner, id)
	end
	state.restUntil[id] = nil
end

-- playerKey のプレイヤーがいなくなった。そのプレイヤーの攻撃トークンを全部返す
function KogekiToken.removePlayer(state: State, playerKey: string)
	for id in state.holders[playerKey] or {} do
		if state.owners[id] == playerKey then
			state.owners[id] = nil
		end
	end
	state.holders[playerKey] = nil
	state.cooldowns[playerKey] = nil
end

-- 全部の攻撃トークンと休みを消す（敵を片付けたとき）
function KogekiToken.reset(state: State)
	table.clear(state.holders)
	table.clear(state.owners)
	table.clear(state.restUntil)
	table.clear(state.cooldowns)
end

return KogekiToken
