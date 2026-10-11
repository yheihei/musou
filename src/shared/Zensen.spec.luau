--!strict
local Zensen = require("./Zensen")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

local GAP, SPACING, ROW_GAP, WIDTH = 4, 4, 4, 10

local PARAMS: Zensen.Params = {
	zensen = { Gap = GAP, Spacing = SPACING, RowGap = ROW_GAP, AttackInterval = 1.5, AttackRandom = 1, AggroRange = 15 },
	zensenhaba = WIDTH,
}

-- 部隊の位置 position の周りに、count 体の個体をばらばらに置く（ID は prefix と番号）
local function crowd(prefix: string, count: number, position: Zensen.Point): { Zensen.Kotai }
	local list = {}
	for index = 1, count do
		local angle = index * 2.4
		local reach = (index % 5) * 2
		table.insert(list, {
			id = `{prefix}{index}`,
			x = position.x + math.cos(angle) * reach,
			z = position.z + math.sin(angle) * reach,
		})
	end
	return list
end

local function sideOf(prefix: string, count: number, position: Zensen.Point): Zensen.Side
	return { position = position, kotai = crowd(prefix, count, position) }
end

local function frontCount(side: Zensen.SideLayout): number
	local count = 0
	for _, slot in side.slots do
		if slot.front then
			count += 1
		end
	end
	return count
end

local function slotCount(side: Zensen.SideLayout): number
	local count = 0
	for _ in side.slots do
		count += 1
	end
	return count
end

-- 前線の中ほど center から見た、相手の部隊の方（look）への位置
local function ahead(point: Zensen.Point, center: Zensen.Point, look: Zensen.Point): number
	return (point.x - center.x) * look.x + (point.z - center.z) * look.z
end

local function distance(p: Zensen.Point, q: Zensen.Point): number
	local dx, dz = p.x - q.x, p.z - q.z
	return math.sqrt(dx * dx + dz * dz)
end

-- 並び side の個体が並ぶ位置に着いたとして、次の並びに渡す個体（removed の個体は倒れて外れる）
local function settled(side: Zensen.SideLayout, removed: { [string]: boolean }?): { Zensen.Kotai }
	local list: { Zensen.Kotai } = {}
	for id, slot in side.slots do
		if not (removed and removed[id]) then
			table.insert(list, { id = id, x = slot.point.x, z = slot.point.z, row = slot.row, column = slot.column })
		end
	end
	table.sort(list, function(p, q)
		return p.id < q.id
	end)
	return list
end

-- 並び side の、列と番号から引く個体の ID
local function cellsOf(side: Zensen.SideLayout): { [string]: string }
	local cells = {}
	for id, slot in side.slots do
		cells[`{slot.row}:{slot.column}`] = id
	end
	return cells
end

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

test(
	"前線の個体の正面は、相手の部隊の方向（自分の部隊から相手の部隊への向き）",
	function()
		local a, b = { x = 0, z = 0 }, { x = 12, z = 16 }
		local layout = Zensen.layout(sideOf("A", 12, a), sideOf("B", 12, b), PARAMS)
		expect(layout.a.look.x).toBeNear(0.6, 1e-9)
		expect(layout.a.look.z).toBeNear(0.8, 1e-9)
		expect(layout.b.look.x).toBeNear(-0.6, 1e-9)
		expect(layout.b.look.z).toBeNear(-0.8, 1e-9)
		expect(Zensen.angle(layout.a.look, Zensen.direction(a, b)) :: number).toBeNear(0, 1e-3)
		expect(Zensen.angle(layout.b.look, Zensen.direction(b, a)) :: number).toBeNear(0, 1e-3)
	end
)

test(
	"前線は2つの部隊の中点を通り、両軍の前線の列は Gap だけ離れて向かい合う",
	function()
		local layout = Zensen.layout(sideOf("A", 10, { x = 0, z = 0 }), sideOf("B", 10, { x = 20, z = 0 }), PARAMS)
		expect(layout.center.x).toBeNear(10, 1e-9)
		expect(layout.center.z).toBeNear(0, 1e-9)
		for _, slot in layout.a.slots do
			expect(slot.front).toBe(true)
			expect(slot.point.x).toBeNear(10 - GAP / 2, 1e-9)
		end
		for _, slot in layout.b.slots do
			expect(slot.front).toBe(true)
			expect(slot.point.x).toBeNear(10 + GAP / 2, 1e-9)
		end
	end
)

test(
	"前線に並ぶのは前線幅まで。残りは前線の後ろの控えの列に前線幅ずつ並ぶ",
	function()
		local layout = Zensen.layout(sideOf("A", 25, { x = 0, z = 0 }), sideOf("B", 3, { x = 20, z = 0 }), PARAMS)
		expect(slotCount(layout.a)).toBe(25)
		expect(frontCount(layout.a)).toBe(WIDTH)
		local rows: { [number]: number } = {}
		for _, slot in layout.a.slots do
			local back = 10 - GAP / 2 - slot.point.x
			local row = math.round(back / ROW_GAP)
			expect(back).toBeNear(row * ROW_GAP, 1e-9)
			expect(slot.front).toBe(row == 0)
			rows[row] = (rows[row] or 0) + 1
		end
		expect(rows).toEqual({ [0] = 10, [1] = 10, [2] = 5 })
		-- 前線幅より少ない部隊は、全員が前線に並ぶ
		expect(frontCount(layout.b)).toBe(3)
	end
)

test("列の中は Spacing の間隔で、2つの部隊を結ぶ線を中ほどにして横に並ぶ", function()
	local layout = Zensen.layout(sideOf("A", 4, { x = 0, z = 0 }), sideOf("B", 4, { x = 20, z = 0 }), PARAMS)
	local lateral = {}
	for _, slot in layout.a.slots do
		table.insert(lateral, slot.point.z)
	end
	table.sort(lateral)
	expect(lateral[1]).toBeNear(-6, 1e-9)
	expect(lateral[2]).toBeNear(-2, 1e-9)
	expect(lateral[3]).toBeNear(2, 1e-9)
	expect(lateral[4]).toBeNear(6, 1e-9)
end)

test(
	"両軍の並ぶ位置は重ならない（前線の中ほどを境に、それぞれ自分の部隊の側に並ぶ）",
	function()
		local a, b = { x = -30, z = 40 }, { x = -10, z = 25 }
		local layout = Zensen.layout(sideOf("A", 30, a), sideOf("B", 18, b), PARAMS)
		local look = layout.a.look
		for _, slot in layout.a.slots do
			expect(ahead(slot.point, layout.center, look) <= -GAP / 2 + 1e-9).toBe(true)
		end
		for _, slot in layout.b.slots do
			expect(ahead(slot.point, layout.center, look) >= GAP / 2 - 1e-9).toBe(true)
		end
		-- どの2体の並ぶ位置も、両軍をまたいでも、Gap・Spacing・RowGap の小さい方より近くならない
		local points = {}
		for _, side in { layout.a, layout.b } do
			for _, slot in side.slots do
				table.insert(points, slot.point)
			end
		end
		for i = 1, #points do
			for j = i + 1, #points do
				expect(distance(points[i], points[j]) >= math.min(GAP, SPACING, ROW_GAP) - 1e-9).toBe(true)
			end
		end
	end
)

test("前線の個体は、横の位置が同じ相手の前線の個体と向かい合う", function()
	local layout = Zensen.layout(sideOf("A", 10, { x = 0, z = 0 }), sideOf("B", 10, { x = 0, z = 20 }), PARAMS)
	for id, slot in layout.a.slots do
		local aite = slot.aite :: string
		expect(aite ~= nil).toBe(true)
		local other = layout.b.slots[aite]
		expect(other.front).toBe(true)
		-- 向かい合う2体の間は、相手の部隊の方へ Gap だけ
		expect(other.point.x).toBeNear(slot.point.x, 1e-9)
		expect(other.point.z - slot.point.z).toBeNear(GAP, 1e-9)
		-- 相手からも向かい合う
		expect(other.aite).toBe(id)
	end
end)

test(
	"前線の個体の数が違うときは、横のずれが Spacing までの相手と向かい合い、多い側の端の個体は相手がいない",
	function()
		local layout = Zensen.layout(sideOf("A", 10, { x = 0, z = 0 }), sideOf("B", 4, { x = 20, z = 0 }), PARAMS)
		local paired = 0
		for _, slot in layout.a.slots do
			local aite = slot.aite
			if aite then
				paired += 1
				expect(math.abs(layout.b.slots[aite].point.z - slot.point.z) <= SPACING + 1e-9).toBe(true)
			else
				-- 相手のいない個体は、前線の端（相手の前線の外）にいる
				expect(math.abs(slot.point.z) > 6 + 1e-9).toBe(true)
			end
		end
		-- 横の位置 -10・-6・-2・2・6・10 の6体が向かい合う
		expect(paired).toBe(6)
		for _, slot in layout.b.slots do
			expect(slot.aite ~= nil).toBe(true)
		end
	end
)

test("相手の部隊に個体がいなくても並べられ、前線の個体の相手はいない", function()
	local layout = Zensen.layout(sideOf("A", 5, { x = 0, z = 0 }), sideOf("B", 0, { x = 20, z = 0 }), PARAMS)
	expect(frontCount(layout.a)).toBe(5)
	expect(slotCount(layout.b)).toBe(0)
	for _, slot in layout.a.slots do
		expect(slot.aite).toBe(nil)
	end
end)

test("前線に近い個体から前線に並ぶ", function()
	local kotai: { Zensen.Kotai } = {}
	-- 部隊の位置（x = 0）から前線（x = 8）へ向けて 12 体を縦に並べる。前線に近い 10 体が前線に並ぶ
	for index = 1, 12 do
		table.insert(kotai, { id = `A{index}`, x = index * 0.5, z = 0 })
	end
	local layout =
		Zensen.layout({ position = { x = 0, z = 0 }, kotai = kotai }, sideOf("B", 10, { x = 20, z = 0 }), PARAMS)
	expect(layout.a.slots.A1.front).toBe(false)
	expect(layout.a.slots.A2.front).toBe(false)
	for index = 3, 12 do
		expect(layout.a.slots[`A{index}`].front).toBe(true)
	end
end)

test(
	"前の並びで前線にいた個体は、後ろへ下がっていても前線に残る（前線と控えを入れ替え続けない）",
	function()
		local kotai: { Zensen.Kotai } = {}
		for index = 1, 12 do
			table.insert(kotai, { id = `A{index}`, x = index * 0.5, z = 0 })
		end
		-- 一番後ろの A1 は、前の並びで前線の 5 番の位置にいた
		kotai[1].row = 0
		kotai[1].column = 5
		local layout =
			Zensen.layout({ position = { x = 0, z = 0 }, kotai = kotai }, sideOf("B", 10, { x = 20, z = 0 }), PARAMS)
		expect(layout.a.slots.A1.front).toBe(true)
		expect(layout.a.slots.A1.column).toBe(5)
		expect(frontCount(layout.a)).toBe(WIDTH)
		-- 代わりに、前の並びで前線にいなかった個体のうち一番後ろの2体が控えになる
		expect(layout.a.slots.A2.front).toBe(false)
		expect(layout.a.slots.A3.front).toBe(false)
	end
)

test("列の中の並びは横の位置の順（並ぶ位置へ歩くときに行き違わない）", function()
	local kotai: { Zensen.Kotai } = {
		{ id = "A1", x = 2, z = 9 },
		{ id = "A2", x = 2, z = -7 },
		{ id = "A3", x = 2, z = 1 },
		{ id = "A4", x = 2, z = -2 },
	}
	local layout =
		Zensen.layout({ position = { x = 0, z = 0 }, kotai = kotai }, sideOf("B", 4, { x = 20, z = 0 }), PARAMS)
	expect(layout.a.slots.A2.point.z).toBeNear(-6, 1e-9)
	expect(layout.a.slots.A4.point.z).toBeNear(-2, 1e-9)
	expect(layout.a.slots.A3.point.z).toBeNear(2, 1e-9)
	expect(layout.a.slots.A1.point.z).toBeNear(6, 1e-9)
end)

test("2つの部隊が同じ位置にいても向かい合って並ぶ（1つ目の部隊が東を向く）", function()
	local layout = Zensen.layout(sideOf("A", 3, { x = 5, z = 5 }), sideOf("B", 3, { x = 5, z = 5 }), PARAMS)
	expect(layout.a.look).toEqual({ x = 1, z = 0 })
	expect(layout.b.look).toEqual({ x = -1, z = 0 })
	for _, slot in layout.a.slots do
		expect(slot.point.x).toBeNear(5 - GAP / 2, 1e-9)
		expect(slot.aite ~= nil).toBe(true)
	end
	for _, slot in layout.b.slots do
		expect(slot.point.x).toBeNear(5 + GAP / 2, 1e-9)
	end
end)

test(
	"乱数で混ぜても、どの個体にも並ぶ位置があり、前線幅を超えず、両軍は重ならず、相手は相手の前線の個体",
	function()
		local random = newRandom(20261010)
		for _ = 1, 200 do
			local a = { x = random.nextNumber(-100, 100), z = random.nextNumber(-100, 100) }
			local angle = random.nextNumber(0, math.pi * 2)
			local gap = random.nextNumber(0, 30)
			local b = { x = a.x + math.cos(angle) * gap, z = a.z + math.sin(angle) * gap }
			local countA, countB = random.nextInteger(0, 40), random.nextInteger(0, 40)
			local layout = Zensen.layout(sideOf("A", countA, a), sideOf("B", countB, b), PARAMS)
			expect(slotCount(layout.a)).toBe(countA)
			expect(slotCount(layout.b)).toBe(countB)
			expect(frontCount(layout.a)).toBe(math.min(countA, WIDTH))
			expect(frontCount(layout.b)).toBe(math.min(countB, WIDTH))
			expect(layout.a.look.x * layout.b.look.x + layout.a.look.z * layout.b.look.z).toBeNear(-1, 1e-9)
			for _, entry in
				{ { mine = layout.a, other = layout.b, sign = -1 }, { mine = layout.b, other = layout.a, sign = 1 } }
			do
				for _, slot in entry.mine.slots do
					local position = ahead(slot.point, layout.center, layout.a.look) * entry.sign
					expect(position >= GAP / 2 - 1e-9).toBe(true)
					local aite = slot.aite
					if aite then
						expect(slot.front).toBe(true)
						local other = entry.other.slots[aite]
						expect(other.front).toBe(true)
						-- 向かい合う相手との横のずれは Spacing まで
						local side = { x = -layout.a.look.z, z = layout.a.look.x }
						local dx, dz = other.point.x - slot.point.x, other.point.z - slot.point.z
						expect(math.abs(dx * side.x + dz * side.z) <= SPACING + 1e-9).toBe(true)
					end
				end
			end
		end
	end
)

test(
	"交戦の損害で倒れる前線の個体は、減った兵数だけ選ぶ（前線の個体が足りなければ全員）",
	function()
		local candidates: { Zensen.FallCandidate } = {
			{ id = "A1", engaged = true, distance = 0.5 },
			{ id = "A2", engaged = true, distance = 0.2 },
			{ id = "A3", engaged = true, distance = 0.8 },
		}
		expect(#Zensen.chooseFallen(candidates, 2)).toBe(2)
		expect(Zensen.chooseFallen(candidates, 5)).toEqual({ "A2", "A1", "A3" })
		expect(Zensen.chooseFallen(candidates, 0)).toEqual({})
		expect(Zensen.chooseFallen({}, 3)).toEqual({})
	end
)

test("相手と向かい合って並ぶ位置に着いている個体を先に倒す", function()
	local candidates: { Zensen.FallCandidate } = {
		{ id = "A1", engaged = false, distance = 0.1 },
		{ id = "A2", engaged = true, distance = 1.2 },
		{ id = "A3", engaged = false, distance = 6 },
		{ id = "A4", engaged = true, distance = 0.4 },
	}
	expect(Zensen.chooseFallen(candidates, 3)).toEqual({ "A4", "A2", "A1" })
end)

test("2つの水平の向きの角度の差（度）", function()
	expect(Zensen.angle({ x = 1, z = 0 }, { x = 0, z = 1 }) :: number).toBeNear(90, 1e-9)
	expect(Zensen.angle({ x = 1, z = 0 }, { x = -2, z = 0 }) :: number).toBeNear(180, 1e-9)
	expect(Zensen.angle({ x = 3, z = 3 }, { x = 1, z = 0 }) :: number).toBeNear(45, 1e-9)
	expect(Zensen.angle({ x = 0, z = 0 }, { x = 1, z = 0 })).toBe(nil)
end)

test(
	"前線の個体が倒れたら、同じ番号の位置の後ろの控えが1つずつ前へ出て、ほかの個体は動かない",
	function()
		local a, b = { x = 0, z = 0 }, { x = 20, z = 0 }
		local first = Zensen.layout(sideOf("A", 25, a), sideOf("B", 10, b), PARAMS)
		local cells = cellsOf(first.a)
		-- 後ろに控えが2体いる番号の位置を探し、その前線の個体を倒す
		local column = 0
		for candidate = 1, WIDTH do
			if cells[`2:{candidate}`] then
				column = candidate
				break
			end
		end
		expect(column > 0).toBe(true)
		local fallen = cells[`0:{column}`]
		local second = Zensen.layout(
			{ position = a, kotai = settled(first.a, { [fallen] = true }) },
			{ position = b, kotai = settled(first.b) },
			PARAMS
		)
		local stepped = second.a.slots[cells[`1:{column}`]]
		expect(stepped.row).toBe(0)
		expect(stepped.column).toBe(column)
		expect(second.a.slots[cells[`2:{column}`]].row).toBe(1)
		for id, slot in first.a.slots do
			if id ~= fallen and slot.column ~= column then
				expect(second.a.slots[id].point.x).toBeNear(slot.point.x, 1e-9)
				expect(second.a.slots[id].point.z).toBeNear(slot.point.z, 1e-9)
			end
		end
		expect(frontCount(second.a)).toBe(WIDTH)
	end
)

test(
	"控えがいなければ、前線の個体が減っても残りの個体は動かず、空いた位置の向かいの個体は隣の位置の個体と向かい合う",
	function()
		local a, b = { x = 0, z = 0 }, { x = 20, z = 0 }
		local first = Zensen.layout(sideOf("A", 10, a), sideOf("B", 10, b), PARAMS)
		local cells = cellsOf(first.a)
		local fallen = cells["0:4"]
		local second = Zensen.layout(
			{ position = a, kotai = settled(first.a, { [fallen] = true }) },
			{ position = b, kotai = settled(first.b) },
			PARAMS
		)
		expect(frontCount(second.a)).toBe(9)
		for id, slot in first.a.slots do
			if id ~= fallen then
				expect(second.a.slots[id].column).toBe(slot.column)
				expect(second.a.slots[id].point.z).toBeNear(slot.point.z, 1e-9)
			end
		end
		-- 4 番の向かいの個体は、隣の 3 番の位置の個体と向かい合う
		local facing = cellsOf(second.b)["0:4"]
		expect(second.b.slots[facing].aite).toBe(cells["0:3"])
		for _, slot in second.b.slots do
			expect(slot.aite ~= nil).toBe(true)
		end
	end
)

test(
	"前線の位置が空き、その後ろに控えがいなければ、一番近い控えが前へ出る",
	function()
		local a, b = { x = 0, z = 0 }, { x = 20, z = 0 }
		local first = Zensen.layout(sideOf("A", 12, a), sideOf("B", 10, b), PARAMS)
		local cells = cellsOf(first.a)
		-- 控えのいない番号の位置の前線の個体を倒す
		local column = 0
		for candidate = 1, WIDTH do
			if not cells[`1:{candidate}`] then
				column = candidate
				break
			end
		end
		local reserves = {}
		for id, slot in first.a.slots do
			if not slot.front then
				reserves[id] = true
			end
		end
		local fallen = cells[`0:{column}`]
		local second = Zensen.layout(
			{ position = a, kotai = settled(first.a, { [fallen] = true }) },
			{ position = b, kotai = settled(first.b) },
			PARAMS
		)
		expect(frontCount(second.a)).toBe(WIDTH)
		local filled = cellsOf(second.a)[`0:{column}`]
		expect(reserves[filled]).toBe(true)
		-- 前へ出た控えのほかは動かない
		for id, slot in first.a.slots do
			if id ~= fallen and id ~= filled then
				expect(second.a.slots[id].row).toBe(slot.row)
				expect(second.a.slots[id].column).toBe(slot.column)
			end
		end
	end
)

test(
	"後から来た個体は、空いた前線の位置を中ほどから埋め、残りは控えに並ぶ（前からいた個体は動かない）",
	function()
		local a, b = { x = 0, z = 0 }, { x = 20, z = 0 }
		local first = Zensen.layout(sideOf("A", 8, a), sideOf("B", 10, b), PARAMS)
		-- 8 体は中ほどの 2〜9 番に並ぶ
		expect(cellsOf(first.a)["0:1"]).toBe(nil)
		expect(cellsOf(first.a)["0:10"]).toBe(nil)
		local kotai = settled(first.a)
		for index = 1, 3 do
			table.insert(kotai, { id = `New{index}`, x = -index, z = 0 })
		end
		local second = Zensen.layout(
			{ position = a, kotai = kotai },
			{ position = b, kotai = settled(first.b) },
			PARAMS
		)
		expect(frontCount(second.a)).toBe(WIDTH)
		local cells = cellsOf(second.a)
		expect(string.sub(cells["0:1"], 1, 3)).toBe("New")
		expect(string.sub(cells["0:10"], 1, 3)).toBe("New")
		-- 前線に近い New1 と New2 が前線へ、New3 は控えになる
		expect(second.a.slots.New3.front).toBe(false)
		for id, slot in first.a.slots do
			expect(second.a.slots[id].row).toBe(slot.row)
			expect(second.a.slots[id].column).toBe(slot.column)
		end
	end
)

test(
	"前線の個体の数が1つ違うときは、向かいのいない端の個体が隣の位置の個体と向かい合う",
	function()
		local layout = Zensen.layout(sideOf("A", 10, { x = 0, z = 0 }), sideOf("B", 9, { x = 20, z = 0 }), PARAMS)
		local cellsA, cellsB = cellsOf(layout.a), cellsOf(layout.b)
		-- B の 9 体は中ほどから並び、10 番が空く
		expect(cellsB["0:10"]).toBe(nil)
		for _, slot in layout.a.slots do
			expect(slot.aite ~= nil).toBe(true)
		end
		expect(layout.a.slots[cellsA["0:10"]].aite).toBe(cellsB["0:9"])
		expect(layout.a.slots[cellsA["0:9"]].aite).toBe(cellsB["0:9"])
	end
)

test("倒れる前線の個体が同じ近さなら、ID の順に選ぶ", function()
	local candidates: { Zensen.FallCandidate } = {
		{ id = "A3", engaged = true, distance = 0.5 },
		{ id = "A1", engaged = true, distance = 0.5 },
		{ id = "A2", engaged = true, distance = 0.5 },
	}
	expect(Zensen.chooseFallen(candidates, 2)).toEqual({ "A1", "A2" })
end)

test(
	"倒れたり後から来たりを乱数で繰り返しても、前線幅を超えず、並ぶ位置は重ならず、前からいた個体は後ろへ下がらない",
	function()
		local random = newRandom(89)
		local a, b = { x = 0, z = 0 }, { x = 0, z = 24 }
		local layout = Zensen.layout(sideOf("A", 30, a), sideOf("B", 12, b), PARAMS)
		local next = 1
		for _ = 1, 150 do
			-- 前線の個体を 0〜2 体倒し、0〜2 体を部隊の位置の周りに足す
			local removed: { [string]: boolean } = {}
			local front = {}
			for id, slot in layout.a.slots do
				if slot.front then
					table.insert(front, id)
				end
			end
			table.sort(front)
			for _ = 1, random.nextInteger(0, 2) do
				if #front > 0 then
					removed[table.remove(front, random.nextInteger(1, #front)) :: string] = true
				end
			end
			local kotai = settled(layout.a, removed)
			for _ = 1, random.nextInteger(0, 2) do
				table.insert(kotai, { id = `N{next}`, x = random.nextNumber(-8, 8), z = random.nextNumber(-8, 8) })
				next += 1
			end
			local before = layout.a
			layout = Zensen.layout({ position = a, kotai = kotai }, { position = b, kotai = settled(layout.b) }, PARAMS)
			expect(slotCount(layout.a)).toBe(#kotai)
			expect(frontCount(layout.a)).toBe(math.min(#kotai, WIDTH))
			local cells: { [string]: boolean } = {}
			local deepest: { [number]: number } = {}
			for id, slot in layout.a.slots do
				local key = `{slot.row}:{slot.column}`
				expect(cells[key]).toBe(nil)
				cells[key] = true
				deepest[slot.column] = math.max(deepest[slot.column] or -1, slot.row)
				-- 前からいた個体は、同じ番号の位置で前へ出るか、空いた前線の位置へ入るだけ
				local previous = before.slots[id]
				if previous then
					if slot.column == previous.column then
						expect(slot.row <= previous.row).toBe(true)
					else
						expect(slot.row).toBe(0)
					end
				end
			end
			-- 番号ごとの列は前から詰まっている（途中が空かない）
			for column, row in deepest do
				for index = 0, row do
					expect(cells[`{index}:{column}`]).toBe(true)
				end
			end
		end
	end
)
