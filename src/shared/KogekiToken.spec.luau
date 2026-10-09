--!strict
local Config = require("./Config")
local KogekiToken = require("./KogekiToken")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

-- Config.luau の値を調整してもテストが揺れないよう、値を固定する
local PARAMS: KogekiToken.Params = {
	PerPlayer = 3,
	Range = 20,
	Interval = 1.5,
	Rest = 2,
	MaxHold = 4,
	WaitGap = 5,
}

local A, B = "1", "2"

-- 種を固定した乱数（Lune には Random が無いので、線形合同法で作る）
local function newRandom(seed: number)
	local value = seed
	local function nextNumber(min: number?, max: number?): number
		value = (value * 1103515245 + 12345) % 2147483648
		local unit = value / 2147483648
		local low, high = min or 0, max or 1
		return low + unit * (high - low)
	end
	local function nextInteger(min: number, max: number): number
		return math.min(min + math.floor(nextNumber() * (max - min + 1)), max)
	end
	return { nextNumber = nextNumber, nextInteger = nextInteger }
end

local function candidates(list: { { any } }): { KogekiToken.Candidate }
	local result = {}
	for _, item in list do
		table.insert(result, { id = item[1], distance = item[2] })
	end
	return result
end

test("空いた攻撃トークンは、近い順に PerPlayer 体まで渡す", function()
	local state = KogekiToken.new()
	local changes = KogekiToken.update(
		state,
		A,
		candidates({ { "g1", 3 }, { "g2", 8 }, { "g3", 5 }, { "g4", 12 }, { "g5", 15 } }),
		0,
		PARAMS
	)
	expect(changes.given).toEqual({ "g1", "g3", "g2" })
	expect(KogekiToken.holderIds(state, A)).toEqual({ "g1", "g2", "g3" })
	expect(KogekiToken.holds(state, A, "g4")).toBe(false)
end)

test("持っている下忍は、ほかの下忍の方が近くなっても返さない", function()
	local state = KogekiToken.new()
	KogekiToken.update(state, A, candidates({ { "g1", 6 }, { "g2", 7 }, { "g3", 8 }, { "g4", 15 } }), 0, PARAMS)
	-- 持っていない g4 が一番近くに来ても、入れ替えない
	local changes =
		KogekiToken.update(state, A, candidates({ { "g1", 9 }, { "g2", 9 }, { "g3", 9 }, { "g4", 2 } }), 0.25, PARAMS)
	expect(changes.given).toEqual({})
	expect(changes.released).toEqual({})
	expect(KogekiToken.holderIds(state, A)).toEqual({ "g1", "g2", "g3" })
end)

test("Range より遠い下忍は受け取らず、持っている下忍が離れたら返す", function()
	local state = KogekiToken.new()
	KogekiToken.update(state, A, candidates({ { "g1", 5 }, { "g2", 21 }, { "g3", 40 } }), 0, PARAMS)
	expect(KogekiToken.holderIds(state, A)).toEqual({ "g1" })
	-- g1 が吹き飛ばされて Range の外へ出たら返し、近づいてきた g2 が受け取る
	local changes = KogekiToken.update(state, A, candidates({ { "g1", 25 }, { "g2", 18 }, { "g3", 40 } }), 1, PARAMS)
	expect(changes.released).toEqual({ "g1" })
	expect(changes.given).toEqual({ "g2" })
	expect(KogekiToken.holderIds(state, A)).toEqual({ "g2" })
end)

test("攻撃した下忍は返して休み、Interval 秒たってから近い下忍へ渡る", function()
	local state = KogekiToken.new()
	local list = candidates({ { "g1", 4 }, { "g2", 4.5 }, { "g3", 5 }, { "g4", 9 }, { "g5", 9.5 } })
	KogekiToken.update(state, A, list, 0, PARAMS)
	expect(KogekiToken.attacked(state, A, "g1", 1, PARAMS)).toBe(true)
	expect(KogekiToken.holds(state, A, "g1")).toBe(false)
	expect(KogekiToken.isResting(state, "g1", 1)).toBe(true)

	-- Interval（1.5 秒）の間は誰にも渡さない
	local during = KogekiToken.update(state, A, list, 2, PARAMS)
	expect(during.given).toEqual({})
	expect(KogekiToken.count(state, A)).toBe(2)
	expect(KogekiToken.coolingCount(state, A, 2)).toBe(1)

	-- 1.5 秒たったら、休んでいる g1 を飛ばして、次に近い g4 へ渡す
	local after = KogekiToken.update(state, A, list, 2.5, PARAMS)
	expect(after.given).toEqual({ "g4" })
	expect(KogekiToken.holderIds(state, A)).toEqual({ "g2", "g3", "g4" })
end)

test("休みが明けた下忍は、また受け取れる", function()
	local state = KogekiToken.new()
	local list = candidates({ { "g1", 4 } })
	KogekiToken.update(state, A, list, 0, PARAMS)
	KogekiToken.attacked(state, A, "g1", 1, PARAMS)
	-- 休みは攻撃してから 2 秒。ほかに候補がいなければ、攻撃トークンは空いたまま
	expect(KogekiToken.update(state, A, list, 2.9, PARAMS).given).toEqual({})
	expect(KogekiToken.update(state, A, list, 3, PARAMS).given).toEqual({ "g1" })
end)

test("MaxHold 秒たっても攻撃しない下忍は返して休み、すぐに次の下忍へ渡る", function()
	local state = KogekiToken.new()
	local list = candidates({ { "g1", 4 }, { "g2", 9 } })
	local params = table.clone(PARAMS)
	params.PerPlayer = 1
	KogekiToken.update(state, A, list, 0, params)
	expect(KogekiToken.update(state, A, list, 4, params).released).toEqual({})
	local changes = KogekiToken.update(state, A, list, 4.25, params)
	expect(changes.released).toEqual({ "g1" })
	expect(changes.given).toEqual({ "g2" })
	expect(KogekiToken.isResting(state, "g1", 4.25)).toBe(true)
	expect(KogekiToken.coolingCount(state, A, 4.25)).toBe(0)
end)

test("倒れた下忍の攻撃トークンは、すぐに次の下忍へ渡る", function()
	local state = KogekiToken.new()
	KogekiToken.update(state, A, candidates({ { "g1", 4 }, { "g2", 5 }, { "g3", 6 }, { "g4", 9 } }), 0, PARAMS)
	KogekiToken.forget(state, "g2")
	-- 倒れた g2 は候補から外れる。返した攻撃トークンは待たずに g4 へ渡る
	local changes = KogekiToken.update(state, A, candidates({ { "g1", 4 }, { "g3", 6 }, { "g4", 9 } }), 0.25, PARAMS)
	expect(changes.given).toEqual({ "g4" })
	expect(KogekiToken.holderIds(state, A)).toEqual({ "g1", "g3", "g4" })
end)

test(
	"候補から外れた下忍（倒れている、ほかのプレイヤーを狙った）は攻撃トークンを返す",
	function()
		local state = KogekiToken.new()
		KogekiToken.update(state, A, candidates({ { "g1", 4 }, { "g2", 5 } }), 0, PARAMS)
		local changes = KogekiToken.update(state, A, candidates({ { "g2", 5 } }), 0.25, PARAMS)
		expect(changes.released).toEqual({ "g1" })
		expect(KogekiToken.holds(state, A, "g1")).toBe(false)
	end
)

test("攻撃トークンの数はプレイヤーごとに独立し、下忍1体は1人分しか持たない", function()
	local state = KogekiToken.new()
	local list = candidates({ { "g1", 4 }, { "g2", 5 }, { "g3", 6 }, { "g4", 7 }, { "g5", 8 } })
	KogekiToken.update(state, A, list, 0, PARAMS)
	-- 同じ下忍が B の候補にもいるとき（狙いを替えた直後）、A の分を持つ下忍には渡さない
	KogekiToken.update(state, B, list, 0, PARAMS)
	expect(KogekiToken.holderIds(state, A)).toEqual({ "g1", "g2", "g3" })
	expect(KogekiToken.holderIds(state, B)).toEqual({ "g4", "g5" })

	-- A の下忍が攻撃しても、B の数は変わらない
	KogekiToken.attacked(state, A, "g1", 1, PARAMS)
	expect(KogekiToken.count(state, A)).toBe(2)
	expect(KogekiToken.count(state, B)).toBe(2)
end)

test("持っていない下忍の攻撃は、攻撃トークンを動かさない", function()
	local state = KogekiToken.new()
	KogekiToken.update(state, A, candidates({ { "g1", 4 } }), 0, PARAMS)
	expect(KogekiToken.attacked(state, A, "g9", 1, PARAMS)).toBe(false)
	expect(KogekiToken.holderIds(state, A)).toEqual({ "g1" })
	expect(KogekiToken.coolingCount(state, A, 1)).toBe(0)
end)

test("いなくなったプレイヤーの攻撃トークンは全部返す", function()
	local state = KogekiToken.new()
	KogekiToken.update(state, A, candidates({ { "g1", 4 }, { "g2", 5 } }), 0, PARAMS)
	KogekiToken.removePlayer(state, A)
	expect(KogekiToken.count(state, A)).toBe(0)
	expect(KogekiToken.holds(state, A, "g1")).toBe(false)
	-- 返した下忍は、ほかのプレイヤーの攻撃トークンを受け取れる
	expect(KogekiToken.update(state, B, candidates({ { "g1", 4 } }), 0.25, PARAMS).given).toEqual({ "g1" })
end)

test("片付けたら、攻撃トークンも休みも消える", function()
	local state = KogekiToken.new()
	KogekiToken.update(state, A, candidates({ { "g1", 4 } }), 0, PARAMS)
	KogekiToken.attacked(state, A, "g1", 1, PARAMS)
	KogekiToken.reset(state)
	expect(KogekiToken.isResting(state, "g1", 1.5)).toBe(false)
	expect(KogekiToken.coolingCount(state, A, 1.5)).toBe(0)
	expect(KogekiToken.update(state, A, candidates({ { "g1", 4 } }), 1.5, PARAMS).given).toEqual({ "g1" })
end)

test("どんな順に呼んでも、持つ下忍は PerPlayer 体以下で、1体が2人分を持たない", function()
	local state = KogekiToken.new()
	-- 乱数の種を固定して、攻撃・撃破・接近を混ぜて回す
	local random = newRandom(20261009)
	local players = { A, B }
	local alive: { [string]: boolean } = {}
	for index = 1, 12 do
		alive[`g{index}`] = true
	end
	local now = 0
	for _ = 1, 400 do
		now += 0.25
		for _, key in players do
			local list = {}
			for id in alive do
				if random.nextNumber() < 0.6 then
					table.insert(list, { id = id, distance = random.nextNumber(0, 30) })
				end
			end
			KogekiToken.update(state, key, list, now, PARAMS)
			expect(KogekiToken.count(state, key) <= PARAMS.PerPlayer).toBe(true)
			local holders = KogekiToken.holderIds(state, key)
			if #holders > 0 and random.nextNumber() < 0.3 then
				KogekiToken.attacked(state, key, holders[random.nextInteger(1, #holders)], now, PARAMS)
			end
		end
		if random.nextNumber() < 0.05 then
			local id = `g{random.nextInteger(1, 12)}`
			KogekiToken.forget(state, id)
		end
		local seen: { [string]: string } = {}
		for _, key in players do
			for _, id in KogekiToken.holderIds(state, key) do
				expect(seen[id]).toBe(nil)
				seen[id] = key
			end
		end
	end
end)

test(
	"Config の待つ位置は攻撃が届く距離の外で、攻撃トークンを受け取れる距離の内",
	function()
		local p = Config.KogekiToken
		-- 待つ下忍はプレイヤーの手前の距離（PlayerGap 以上）から WaitGap だけ外に立つ
		expect(Config.EnemyAI.PlayerGap + p.WaitGap > Config.Genin.AttackRange).toBe(true)
		-- 攻撃する下忍の止まる位置（攻撃が届く距離より手前）から WaitGap 外でも、Range の内にいる
		expect(Config.Genin.AttackRange + p.WaitGap < p.Range).toBe(true)
		expect(p.PerPlayer >= 1).toBe(true)
		expect(p.Interval >= 0 and p.Rest >= 0).toBe(true)
	end
)
