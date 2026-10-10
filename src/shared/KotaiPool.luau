--!strict
-- 下忍の個体の体のプールの数え方（#83）。使い終えた体を壊さずにプールへ返し、次に出すときに取り出して使い回す。
-- プールは体のひな形（種類・軍・色）ごとに1つ持つ。体そのもの（サーバーの Humanoid のモデル）は呼ぶ側の EnemyService が
-- 作り・置き・壊し、ここは出し入れと数だけを扱う。数値は Config.luau の KotaiPool 節にある。Roblox の API は使わない。
--
-- - 取り出す（take）: プールに体があれば1つ渡し、取り出した数（使い回した数）に数える。無ければ渡された関数で新しく作り、
--   作った数に数える
-- - 返す（put）: 使い終えた体を、プールの数が上限（limit）より少なければ置き、返した数に数える。
--   上限に達していれば置かずに壊した数に数える（呼ぶ側が壊す）
-- - 先読み（fill）: 作ってまだ壊していない体（プールにある体と出ている体の合計）が先読みの数に足りなければ、
--   1回に budget 体まで作ってプールに置く。返した数には数えない。プールの上限を超えては作らない
-- - 片付け（drain）: プールの体をすべて外し、壊した数に数える（使わなくなったひな形の体を壊すとき）
-- - 出ている間に壊れた体は discard で壊した数に数える

export type Pool<T> = {
	-- プールにある体
	idle: { T },
	-- プールに置ける数の上限
	limit: number,
	-- 作った数
	created: number,
	-- プールから取り出した数（使い回した数。プールが空で作って渡した体は入らない）
	taken: number,
	-- 使い終えてプールへ返した数（先読みで置いた体は入らない）
	returned: number,
	-- 壊した数（上限を超えて返された体、片付けた体、出ている間に壊れた体）
	destroyed: number,
}

-- 窓口に出す数
export type Stats = {
	created: number,
	taken: number,
	returned: number,
	destroyed: number,
	-- 今プールにある数
	idle: number,
	-- 出ている数（作ってまだ壊していない体のうち、プールに無いもの）
	inUse: number,
}

local KotaiPool = {}

-- 空のプールを作る。limit はプールに置ける数の上限
function KotaiPool.new<T>(limit: number): Pool<T>
	return {
		idle = {},
		limit = math.max(math.floor(limit), 0),
		created = 0,
		taken = 0,
		returned = 0,
		destroyed = 0,
	}
end

-- 体を1つ渡す。プールにあれば取り出して、取り出した数に数える。無ければ make で作って、作った数に数える。
-- 2つ目の返り値は、プールから取り出したか（使い回した体か）
function KotaiPool.take<T>(pool: Pool<T>, make: () -> T): (T, boolean)
	local item = table.remove(pool.idle)
	if item ~= nil then
		pool.taken += 1
		return item, true
	end
	local made = make()
	pool.created += 1
	return made, false
end

-- 使い終えた体を返す。プールの数が上限より少なければ置いて true（返した数に数える）。
-- 上限に達していれば置かずに false（壊した数に数える。呼ぶ側が壊す）
function KotaiPool.put<T>(pool: Pool<T>, item: T): boolean
	if #pool.idle >= pool.limit then
		pool.destroyed += 1
		return false
	end
	table.insert(pool.idle, item)
	pool.returned += 1
	return true
end

-- 作ってまだ壊していない体の数（プールにある体と出ている体の合計）
function KotaiPool.alive<T>(pool: Pool<T>): number
	return pool.created - pool.destroyed
end

-- 先読みの数 target に足りない数。プールにある体と出ている体の両方を数える
function KotaiPool.shortage<T>(pool: Pool<T>, target: number): number
	return math.max(math.floor(target) - KotaiPool.alive(pool), 0)
end

-- 先読み。target に足りない分を、budget 体まで make で作ってプールに置く（返した数には数えない）。
-- プールの上限を超えては作らない。作った数を返す
function KotaiPool.fill<T>(pool: Pool<T>, target: number, budget: number, make: () -> T): number
	local count = math.min(KotaiPool.shortage(pool, target), math.floor(budget), pool.limit - #pool.idle)
	if count <= 0 then
		return 0
	end
	for _ = 1, count do
		table.insert(pool.idle, make())
		pool.created += 1
	end
	return count
end

-- 出ている間に壊れた体を、壊した数に数える
function KotaiPool.discard<T>(pool: Pool<T>)
	pool.destroyed += 1
end

-- プールの体をすべて外して返し、壊した数に数える（呼ぶ側が壊す）
function KotaiPool.drain<T>(pool: Pool<T>): { T }
	local items = pool.idle
	pool.idle = {}
	pool.destroyed += #items
	return items
end

function KotaiPool.stats<T>(pool: Pool<T>): Stats
	local idle = #pool.idle
	return {
		created = pool.created,
		taken = pool.taken,
		returned = pool.returned,
		destroyed = pool.destroyed,
		idle = idle,
		inUse = pool.created - pool.destroyed - idle,
	}
end

return KotaiPool
