--!strict
local KotaiPool = require("./KotaiPool")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

-- 体の代わりに番号を作る。作った番号の数を数える
local function counter(): (() -> number, () -> number)
	local made = 0
	return function()
		made += 1
		return made
	end, function()
		return made
	end
end

-- 先読みの数まで、1回に budget 体ずつ作る。作り終えるまでの回数を返す
local function prewarm(pool: KotaiPool.Pool<number>, target: number, budget: number, make: () -> number): number
	local rounds = 0
	while KotaiPool.fill(pool, target, budget, make) > 0 do
		rounds += 1
	end
	return rounds
end

test("先読みは1回に budget 体ずつ作ってプールに置き、先読みの数で止まる", function()
	local pool = KotaiPool.new(60)
	local make, made = counter()
	expect(KotaiPool.fill(pool, 40, 2, make)).toBe(2)
	expect(#pool.idle).toBe(2)
	expect(prewarm(pool, 40, 2, make)).toBe(19)
	expect(made()).toBe(40)
	expect(KotaiPool.stats(pool)).toEqual({
		created = 40,
		taken = 0,
		returned = 0,
		destroyed = 0,
		idle = 40,
		inUse = 0,
	})
	expect(KotaiPool.fill(pool, 40, 2, make)).toBe(0)
end)

test("先読みで作った数を超えずに、出入りを繰り返せる", function()
	local pool = KotaiPool.new(60)
	local make, made = counter()
	prewarm(pool, 40, 2, make)
	-- 東の部隊の 30 体と、本陣の部隊の 10 体を交互に出し入れする
	for _ = 1, 5 do
		for _, count in { 30, 10 } do
			local out = {}
			for _ = 1, count do
				local item, reused = KotaiPool.take(pool, make)
				expect(reused).toBe(true)
				table.insert(out, item)
			end
			for _, item in out do
				expect(KotaiPool.put(pool, item)).toBe(true)
			end
		end
	end
	expect(made()).toBe(40)
	expect(KotaiPool.stats(pool)).toEqual({
		created = 40,
		taken = 200,
		returned = 200,
		destroyed = 0,
		idle = 40,
		inUse = 0,
	})
end)

test(
	"乱数で出入りを 200 回混ぜても、出ている数が先読みの数以下なら作り足さない",
	function()
		-- 種を固定した乱数（線形合同法）
		local value = 83
		local function nextNumber(max: number): number
			value = (value * 1103515245 + 12345) % 2147483648
			return math.floor(value / 2147483648 * max)
		end
		local pool = KotaiPool.new(60)
		local make, made = counter()
		prewarm(pool, 40, 2, make)
		local out: { number } = {}
		for _ = 1, 200 do
			-- 出ている数が 40 を超えない範囲で取り出し、出ている体のうち何体かを返す
			for _ = 1, nextNumber(41 - #out) do
				table.insert(out, (KotaiPool.take(pool, make)))
			end
			for _ = 1, nextNumber(#out + 1) do
				expect(KotaiPool.put(pool, table.remove(out, 1 + nextNumber(#out)) :: number)).toBe(true)
			end
			local stats = KotaiPool.stats(pool)
			expect(stats.created).toBe(40)
			expect(stats.inUse).toBe(#out)
			expect(stats.idle + stats.inUse).toBe(40)
			-- 先読みし直しても、出ている体を数えるので作り足さない
			expect(KotaiPool.fill(pool, 40, 2, make)).toBe(0)
		end
		expect(made()).toBe(40)
		expect(pool.destroyed).toBe(0)
	end
)

test(
	"プールが空なら作って渡し、作った数に数える（取り出した数には数えない）",
	function()
		local pool = KotaiPool.new(10)
		local make, made = counter()
		local first, reused = KotaiPool.take(pool, make)
		expect(first).toBe(1)
		expect(reused).toBe(false)
		expect(pool.created).toBe(1)
		expect(pool.taken).toBe(0)
		expect(KotaiPool.put(pool, first)).toBe(true)
		local again, reusedAgain = KotaiPool.take(pool, make)
		expect(again).toBe(1)
		expect(reusedAgain).toBe(true)
		expect(made()).toBe(1)
		expect(pool.taken).toBe(1)
		expect(pool.returned).toBe(1)
	end
)

test("上限を超えて返した体は置かずに、壊した数に数える", function()
	local pool = KotaiPool.new(3)
	local make = counter()
	local out = {}
	for _ = 1, 5 do
		table.insert(out, (KotaiPool.take(pool, make)))
	end
	local kept = 0
	for _, item in out do
		if KotaiPool.put(pool, item) then
			kept += 1
		end
	end
	expect(kept).toBe(3)
	expect(KotaiPool.stats(pool)).toEqual({
		created = 5,
		taken = 0,
		returned = 3,
		destroyed = 2,
		idle = 3,
		inUse = 0,
	})
end)

test("先読みは、出ている体も数えて足りない分だけ作る", function()
	local pool = KotaiPool.new(60)
	local make, made = counter()
	-- 先読みが終わる前に 6 体を出した（プールが空なので作って渡した）
	for _ = 1, 6 do
		KotaiPool.take(pool, make)
	end
	expect(KotaiPool.shortage(pool, 10)).toBe(4)
	prewarm(pool, 10, 3, make)
	expect(made()).toBe(10)
	expect(#pool.idle).toBe(4)
	expect(KotaiPool.stats(pool).inUse).toBe(6)
end)

test("先読みは、プールの上限を超えては作らない", function()
	local pool = KotaiPool.new(5)
	local make, made = counter()
	prewarm(pool, 10, 4, make)
	expect(made()).toBe(5)
	expect(#pool.idle).toBe(5)
	expect(KotaiPool.shortage(pool, 10)).toBe(5)
end)

test(
	"片付けはプールの体をすべて外して壊した数に数え、次の先読みで作り直す",
	function()
		local pool = KotaiPool.new(60)
		local make, made = counter()
		prewarm(pool, 10, 2, make)
		local drained = KotaiPool.drain(pool)
		expect(#drained).toBe(10)
		expect(#pool.idle).toBe(0)
		expect(pool.destroyed).toBe(10)
		expect(KotaiPool.shortage(pool, 10)).toBe(10)
		prewarm(pool, 10, 2, make)
		expect(made()).toBe(20)
		expect(KotaiPool.alive(pool)).toBe(10)
	end
)

test("出ている間に壊れた体は壊した数に数え、先読みで作り足す", function()
	local pool = KotaiPool.new(60)
	local make, made = counter()
	prewarm(pool, 4, 4, make)
	KotaiPool.take(pool, make)
	KotaiPool.discard(pool)
	expect(KotaiPool.stats(pool)).toEqual({
		created = 4,
		taken = 1,
		returned = 0,
		destroyed = 1,
		idle = 3,
		inUse = 0,
	})
	expect(KotaiPool.fill(pool, 4, 4, make)).toBe(1)
	expect(made()).toBe(5)
end)

test("上限と先読みの数と budget は整数に切り捨て、負の数は 0 にする", function()
	local pool = KotaiPool.new(-3)
	local make = counter()
	expect(pool.limit).toBe(0)
	expect(KotaiPool.fill(pool, 5, 2, make)).toBe(0)
	local other = KotaiPool.new(4.9)
	expect(other.limit).toBe(4)
	expect(KotaiPool.fill(other, 3.7, 2.5, make)).toBe(2)
	expect(KotaiPool.shortage(other, 3.7)).toBe(1)
	expect(KotaiPool.shortage(other, -1)).toBe(0)
end)
