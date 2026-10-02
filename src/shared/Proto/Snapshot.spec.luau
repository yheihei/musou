--!strict
local GeninSim = require("./GeninSim")
local Snapshot = require("./Snapshot")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

local function genin(x: number, z: number, y: number, yaw: number, state: GeninSim.State): GeninSim.Genin
	return {
		x = x,
		z = z,
		y = y,
		yaw = yaw,
		state = state,
		stateTime = 0,
		hits = 0,
		lastAttack = 0,
		fromX = 0,
		fromZ = 0,
		dirX = 0,
		dirZ = 0,
	}
end

test("詰めて読み戻すと、位置は 0.1 スタッド、向きは 256 段階の誤差に収まる", function()
	local list = {
		genin(12.34, -56.78, 3.21, 1.5, "Attack"),
		genin(-3000, 3000, 0, -0.5, "Knockback"),
	}
	local header, entries = Snapshot.unpack(Snapshot.pack(list, nil, nil, 7))
	expect(header).toEqual({ total = 2, first = 1, count = 2, sequence = 7 })
	expect(#entries).toBe(2)
	expect(entries[1].x).toBeNear(12.3, 0.051)
	expect(entries[1].z).toBeNear(-56.8, 0.051)
	expect(entries[1].y).toBeNear(3.2, 0.051)
	expect(entries[1].yaw).toBeNear(1.5, math.pi * 2 / 256)
	expect(entries[1].state).toBe("Attack")
	expect(entries[2].x).toBeNear(-3000, 0.051)
	expect(entries[2].z).toBeNear(3000, 0.051)
	expect(entries[2].yaw).toBeNear(math.pi * 2 - 0.5, math.pi * 2 / 256)
	expect(entries[2].state).toBe("Knockback")
end)

test("100体を詰めても UnreliableRemoteEvent の上限に収まる", function()
	local list = GeninSim.create(100, { x = 0, z = 0 }, math.random)
	local data = Snapshot.pack(list)
	expect(buffer.len(data)).toBe(Snapshot.sizeOf(100))
	expect(buffer.len(data) <= Snapshot.MAX_PAYLOAD).toBe(true)
	expect(Snapshot.maxCount() >= 100).toBe(true)
end)

test("範囲を指定して一部だけを詰められる", function()
	local list = {
		genin(1, 0, 0, 0, "Move"),
		genin(2, 0, 0, 0, "Move"),
		genin(3, 0, 0, 0, "Move"),
	}
	local header, entries = Snapshot.unpack(Snapshot.pack(list, 2, 3, 70000))
	expect(header).toEqual({ total = 3, first = 2, count = 2, sequence = 70000 % 65536 })
	expect(#entries).toBe(2)
	expect(entries[1].x).toBeNear(2)
	expect(entries[2].x).toBeNear(3)
end)

test("形の合わない buffer からは何も読まない", function()
	local header, entries = Snapshot.unpack(buffer.create(1))
	expect(header).toBe(nil)
	expect(entries).toEqual({})
	local short = buffer.create(10)
	buffer.writeu16(short, 4, 5)
	local shortHeader, shortEntries = Snapshot.unpack(short)
	expect(shortHeader).toBe(nil)
	expect(shortEntries).toEqual({})
end)

test("送った回の番号は、一周をまたいでも新しいか古いかを見分ける", function()
	expect(Snapshot.isStale(9, 10)).toBe(true)
	expect(Snapshot.isStale(10, 10)).toBe(false)
	expect(Snapshot.isStale(11, 10)).toBe(false)
	expect(Snapshot.isStale(65535, 2)).toBe(true)
	expect(Snapshot.isStale(2, 65535)).toBe(false)
end)
