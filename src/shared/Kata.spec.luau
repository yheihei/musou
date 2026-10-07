--!strict
local ActionState = require("./ActionState")
local Config = require("./Config")
local Kata = require("./Kata")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

-- Config.luau の値を調整してもテストが揺れないよう、距離・秒数・型を固定する
local PARAMS: Kata.Params = {
	AggroRange = 50,
	ChaseRadius = 40,
	AttackerMemory = 5,
	SwitchMargin = 6,
	Maai = 5,
	Interval = 1,
	IntervalRandom = 0.5,
	Jonin = {
		Kiri = {
			Maai = 7,
			Weight = 3,
			YobiDosa = 0.5,
			Active = 0.1,
			Recovery = 0.6,
			Hits = {
				{ Shape = { Kind = "Box", Range = 8, Width = 7 }, Power = 1.2, Reaction = "Flinch", Knockback = 8 },
			},
		},
		Nage = {
			Maai = 20,
			Weight = 1,
			YobiDosa = 0.4,
			Active = 0.1,
			Recovery = 0.5,
			Hits = {
				{
					Shape = { Kind = "Line", Length = 30, Width = 3, Speed = 90 },
					Power = 1,
					Reaction = "Flinch",
					Knockback = 6,
				},
			},
		},
	},
	Shuryo = {
		Ookiri = {
			Maai = 8,
			Weight = 2,
			YobiDosa = 1,
			Active = 0.3,
			Recovery = 1,
			Hits = {
				{
					Shape = { Kind = "Sector", Radius = 12, Angle = 360 },
					Delay = 0.1,
					Repeat = 2,
					Interval = 0.2,
					Power = 2,
					Reaction = "Launch",
					Knockback = 50,
				},
			},
		},
	},
}

-- 狙う相手の候補（個体からの距離と、追いかける範囲の外へ出ている距離）
local function candidate(key: string, distance: number, beyond: number?): Kata.Candidate<string>
	return { key = key, distance = distance, beyond = beyond or 0 }
end

-- 範囲の外へ寄せない（どこまでも追いかける）
local function unlimited(point: Kata.Point): Kata.Point
	return point
end

test(
	"狙えるのは、個体から狙う距離以内で、追いかける範囲の外へ出ている距離が間合い以内の相手",
	function()
		expect(Kata.canTarget(candidate("A", 50, 5), PARAMS)).toBe(true)
		expect(Kata.canTarget(candidate("A", 50.1, 0), PARAMS)).toBe(false)
		expect(Kata.canTarget(candidate("A", 10, 5.1), PARAMS)).toBe(false)
	end
)

test("円の追いかける範囲は、中の位置をそのまま返し、外の位置を縁へ寄せる", function()
	local clamp = Kata.circle({ x = 10, z = 0 }, 40)
	local inside = clamp({ x = 30, z = 20 })
	expect(inside.x).toBe(30)
	expect(inside.z).toBe(20)
	local outside = clamp({ x = 10, z = -60 })
	expect(outside.x).toBeNear(10, 1e-9)
	expect(outside.z).toBeNear(-40, 1e-9)
end)

test("候補は、個体からの距離と、追いかける範囲の外へ出ている距離を持つ", function()
	local clamp = Kata.circle({ x = 0, z = 0 }, 40)
	local inside = Kata.candidateOf("A", { x = 0, z = 0 }, { x = 30, z = 0 }, clamp)
	expect(inside.key).toBe("A")
	expect(inside.distance).toBeNear(30, 1e-9)
	expect(inside.beyond).toBeNear(0, 1e-9)
	local outside = Kata.candidateOf("B", { x = 0, z = 30 }, { x = 0, z = -44 }, clamp)
	expect(outside.distance).toBeNear(74, 1e-9)
	expect(outside.beyond).toBeNear(4, 1e-9)
end)

test("攻撃してきた相手がいなければ、一番近い相手を狙う", function()
	local candidates = { candidate("A", 20), candidate("B", 12), candidate("C", 30) }
	expect(Kata.chooseTarget(candidates, nil, nil, 0, PARAMS)).toBe("B")
end)

test("狙える相手がいなければ、誰も狙わない", function()
	expect(Kata.chooseTarget({}, nil, nil, 0, PARAMS)).toBe(nil)
	local far = { candidate("A", 60), candidate("B", 20, 10) }
	expect(Kata.chooseTarget(far, "A", { key = "B", at = 0 }, 1, PARAMS)).toBe(nil)
end)

test("最後に攻撃してきた相手は、覚えている秒数の間、近い相手より先に狙う", function()
	local candidates = { candidate("A", 30), candidate("B", 5) }
	local attacker: Kata.Attacker<string> = { key = "A", at = 10 }
	expect(Kata.chooseTarget(candidates, "B", attacker, 12, PARAMS)).toBe("A")
	expect(Kata.chooseTarget(candidates, "B", attacker, 15, PARAMS)).toBe("A")
	-- 覚えている秒数を過ぎたら、一番近い相手に戻る（狙っていた A より 6 以上近い B）
	expect(Kata.chooseTarget(candidates, "A", attacker, 15.1, PARAMS)).toBe("B")
end)

test("攻撃してきた相手でも、狙えなければ一番近い相手を狙う", function()
	local candidates = { candidate("A", 20, 6), candidate("B", 15) }
	expect(Kata.chooseTarget(candidates, nil, { key = "A", at = 10 }, 11, PARAMS)).toBe("B")
end)

test(
	"狙っている相手は、一番近い相手より替える距離以上遠くなるまで替えない",
	function()
		expect(Kata.chooseTarget({ candidate("A", 15.9), candidate("B", 10) }, "A", nil, 0, PARAMS)).toBe("A")
		expect(Kata.chooseTarget({ candidate("A", 16), candidate("B", 10) }, "A", nil, 0, PARAMS)).toBe("B")
		-- 狙っている相手が狙えなくなったら、一番近い相手
		expect(Kata.chooseTarget({ candidate("A", 51), candidate("B", 40) }, "A", nil, 0, PARAMS)).toBe("B")
	end
)

test("近づく位置は、狙う相手の中心から間合いだけ手前（個体の側）", function()
	local point = Kata.approachPoint({ x = 30, z = 0 }, { x = 10, z = 0 }, unlimited, PARAMS)
	expect(point.x).toBeNear(15, 1e-9)
	expect(point.z).toBeNear(0, 1e-9)
	-- 相手の中まで入っていたら、間合いまで下がる
	local back = Kata.approachPoint({ x = 10, z = 1 }, { x = 10, z = 0 }, unlimited, PARAMS)
	expect(back.x).toBeNear(10, 1e-9)
	expect(back.z).toBeNear(5, 1e-9)
end)

test("相手と同じ位置にいたら、東へ間合いだけ離れる", function()
	local point = Kata.approachPoint({ x = 10, z = 10 }, { x = 10, z = 10 }, unlimited, PARAMS)
	expect(point.x).toBeNear(15, 1e-9)
	expect(point.z).toBeNear(10, 1e-9)
end)

test("追いかける範囲の外へは近づかず、範囲の縁で止まる", function()
	-- 相手は戻る位置から北へ 44。手前の位置は戻る位置から 49 になるので、円の縁（40）へ寄せる
	local clamp = Kata.circle({ x = 0, z = 0 }, 40)
	local point = Kata.approachPoint({ x = 0, z = -60 }, { x = 0, z = -44 }, clamp, PARAMS)
	expect(point.x).toBeNear(0, 1e-9)
	expect(point.z).toBeNear(-40, 1e-9)
	-- 首領は本陣の範囲（ここでは x と z が ±20 の四角）の縁で止まる
	local function square(p: Kata.Point): Kata.Point
		return { x = math.clamp(p.x, -20, 20), z = math.clamp(p.z, -20, 20) }
	end
	local edge = Kata.approachPoint({ x = 0, z = 0 }, { x = 30, z = 10 }, square, PARAMS)
	expect(edge.x).toBeNear(20, 1e-9)
	expect(edge.z).toBeNear(10 - 5 / math.sqrt(10), 1e-9)
end)

test("上忍は上忍の型だけを、首領は首領だけの型も、ID の順に並べる", function()
	local function idsOf(entries: { Kata.Entry }): { string }
		local ids = {}
		for _, entry in entries do
			table.insert(ids, entry.id)
		end
		return ids
	end
	expect(idsOf(Kata.listOf(false, PARAMS))).toEqual({ "Kiri", "Nage" })
	expect(idsOf(Kata.listOf(true, PARAMS))).toEqual({ "Kiri", "Nage", "Ookiri" })
	expect(Kata.listOf(true, PARAMS)[3].shuryo).toBe(true)
end)

test("型 ID から型と首領だけの型かを引き、無い ID は nil", function()
	local kiri = Kata.get("Kiri", PARAMS) :: Kata.Entry
	expect(kiri.def.Maai).toBe(7)
	expect(kiri.shuryo).toBe(false)
	expect((Kata.get("Ookiri", PARAMS) :: Kata.Entry).shuryo).toBe(true)
	expect(Kata.get("Nai", PARAMS)).toBe(nil)
end)

test("間合いに入っている型から、重みに比例して選ぶ", function()
	-- 距離 5 では Kiri（重み 3）と Nage（重み 1）が入る。乱数の 0〜0.75 が Kiri、0.75〜1 が Nage
	local entries = Kata.listOf(false, PARAMS)
	expect(Kata.choose(entries, 5, 0)).toBe("Kiri")
	expect(Kata.choose(entries, 5, 0.74)).toBe("Kiri")
	expect(Kata.choose(entries, 5, 0.75)).toBe("Nage")
	expect(Kata.choose(entries, 5, 0.999)).toBe("Nage")
end)

test("間合いの外の型は選ばず、どれも外なら選ばない", function()
	local entries = Kata.listOf(false, PARAMS)
	expect(Kata.choose(entries, 7, 0)).toBe("Kiri")
	expect(Kata.choose(entries, 7.1, 0)).toBe("Nage")
	expect(Kata.choose(entries, 20.1, 0)).toBe(nil)
end)

test("首領は首領だけの型も重みで選ぶ", function()
	-- 距離 5 の重みは Kiri 3・Nage 1・Ookiri 2（合計 6）。乱数 0.9 は 5.4 で Ookiri
	local entries = Kata.listOf(true, PARAMS)
	expect(Kata.choose(entries, 5, 0.9)).toBe("Ookiri")
	expect(Kata.choose(entries, 5, 0.6)).toBe("Nage")
	-- 距離 8 では Kiri が外れ、Nage 1・Ookiri 2 から選ぶ
	expect(Kata.choose(entries, 8, 0.3)).toBe("Nage")
	expect(Kata.choose(entries, 8, 0.4)).toBe("Ookiri")
end)

test("型の判定は、予備動作の後に Delay 秒で出て、Interval 秒ごとに繰り返す", function()
	local def = (Kata.get("Ookiri", PARAMS) :: Kata.Entry).def
	local timeline = Kata.timelineOf(def)
	local hits = ActionState.hits(timeline)
	expect(#hits).toBe(2)
	expect(hits[1].at).toBeNear(1.1, 1e-9)
	expect(hits[2].at).toBeNear(1.3, 1e-9)
	expect(timeline.Startup).toBe(1)
	expect(ActionState.duration(timeline)).toBeNear(2.3, 1e-9)
end)

test("型の時間は攻撃の速さで割る", function()
	local def = (Kata.get("Ookiri", PARAMS) :: Kata.Entry).def
	local timeline = Kata.timelineOf(def, 2)
	local hits = ActionState.hits(timeline)
	expect(timeline.Startup).toBeNear(0.5, 1e-9)
	expect(hits[1].at).toBeNear(0.55, 1e-9)
	expect(hits[2].at).toBeNear(0.65, 1e-9)
	expect(ActionState.duration(timeline)).toBeNear(1.15, 1e-9)
end)

test("次の型は、出し終えてから間隔に乱数の秒数を足した時刻に選ぶ", function()
	expect(Kata.nextTime(10, 0, PARAMS)).toBeNear(11, 1e-9)
	expect(Kata.nextTime(10, 0.5, PARAMS)).toBeNear(11.25, 1e-9)
end)

test(
	"Config の型は、上忍と首領で ID が重ならず、止まる距離から出せて、判定が予備動作と持続の間に出る",
	function()
		local params = Config.Kata
		for id in params.Shuryo do
			expect(params.Jonin[id]).toBe(nil)
		end
		for _, entry in Kata.listOf(true, params) do
			local def = entry.def
			expect(def.Maai > params.Maai).toBe(true)
			expect(def.Weight > 0).toBe(true)
			local hits = ActionState.hits(Kata.timelineOf(def))
			expect(#hits > 0).toBe(true)
			for _, scheduled in hits do
				expect(scheduled.at >= def.YobiDosa).toBe(true)
				expect(scheduled.at <= def.YobiDosa + def.Active + 1e-9).toBe(true)
			end
		end
	end
)
