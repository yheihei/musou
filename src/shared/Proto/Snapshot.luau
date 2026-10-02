--!strict
-- 下忍の描き方の試作（検証用ブランチだけ）。案B で UnreliableRemoteEvent に載せる下忍の位置と状態を buffer に詰める。
-- UnreliableRemoteEvent は上限（当初 900 バイト、2025-03 から 1000 バイト）を超える送信を捨てるので、
-- 1体を 7 バイトに詰め、1回の送信を 900 バイトに収める。届く順は前後するので、送った回の番号を付ける。
--
-- | 位置 | 型 | 中身 |
-- |---|---|---|
-- | 0 | u16 | 全体の体数 |
-- | 2 | u16 | この送信の最初の番号（1から） |
-- | 4 | u16 | この送信の体数 |
-- | 6 | u16 | 送った回の番号（65536 で一周する） |
-- | 8 + 7i | i16 | x（0.1 スタッド単位） |
-- | 10 + 7i | i16 | z（0.1 スタッド単位） |
-- | 12 + 7i | u8 | 高さ y（0.1 スタッド単位、25.5 まで） |
-- | 13 + 7i | u8 | 向き（256 段階） |
-- | 14 + 7i | u8 | 状態の番号（GeninSim.codeOf） |
--
-- x と z は ±3276.7 スタッドまで。Roblox の API は使わない（buffer は Luau の標準）。

local GeninSim = require("./GeninSim")

export type Entry = {
	x: number,
	z: number,
	y: number,
	yaw: number,
	state: GeninSim.State,
}

export type Header = {
	-- 全体の体数
	total: number,
	-- この送信の最初の番号（1から）
	first: number,
	-- この送信の体数
	count: number,
	-- 送った回の番号
	sequence: number,
}

local Snapshot = {}

Snapshot.HEADER_SIZE = 8
Snapshot.ENTRY_SIZE = 7
-- UnreliableRemoteEvent に載せる大きさの上限（バイト）
Snapshot.MAX_PAYLOAD = 900
-- 送った回の番号が一周する数
Snapshot.SEQUENCE_MODULO = 65536

local TAU = math.pi * 2

local function toFixed(value: number): number
	return math.clamp(math.round(value * 10), -32768, 32767)
end

-- count 体を詰めたときの大きさ（バイト）
function Snapshot.sizeOf(count: number): number
	return Snapshot.HEADER_SIZE + Snapshot.ENTRY_SIZE * count
end

-- 一度に送れる体数の上限
function Snapshot.maxCount(): number
	return math.floor((Snapshot.MAX_PAYLOAD - Snapshot.HEADER_SIZE) / Snapshot.ENTRY_SIZE)
end

-- 送った回の番号 sequence が latest より古いか（一周を考えて、半周より後ろを古いとみなす）。同じ回は古くない
function Snapshot.isStale(sequence: number, latest: number): boolean
	local behind = (latest - sequence) % Snapshot.SEQUENCE_MODULO
	return behind > 0 and behind < Snapshot.SEQUENCE_MODULO / 2
end

-- 下忍の一覧の first から last まで（省くと全員）を buffer に詰める。sequence は送った回の番号
function Snapshot.pack(list: { GeninSim.Genin }, first: number?, last: number?, sequence: number?): buffer
	local from = first or 1
	local to = last or #list
	local count = math.max(to - from + 1, 0)
	local data = buffer.create(Snapshot.sizeOf(count))
	buffer.writeu16(data, 0, #list)
	buffer.writeu16(data, 2, from)
	buffer.writeu16(data, 4, count)
	buffer.writeu16(data, 6, (sequence or 0) % Snapshot.SEQUENCE_MODULO)
	for index = from, to do
		local genin = list[index]
		local offset = Snapshot.HEADER_SIZE + (index - from) * Snapshot.ENTRY_SIZE
		buffer.writei16(data, offset, toFixed(genin.x))
		buffer.writei16(data, offset + 2, toFixed(genin.z))
		buffer.writeu8(data, offset + 4, math.clamp(math.round(genin.y * 10), 0, 255))
		local turn = (genin.yaw % TAU) / TAU
		buffer.writeu8(data, offset + 5, math.round(turn * 256) % 256)
		buffer.writeu8(data, offset + 6, GeninSim.codeOf(genin.state))
	end
	return data
end

-- buffer から見出しと、下忍の位置と状態を読む。形が合わなければ nil と空
function Snapshot.unpack(data: buffer): (Header?, { Entry })
	local result: { Entry } = {}
	local size = buffer.len(data)
	if size < Snapshot.HEADER_SIZE then
		return nil, result
	end
	local header: Header = {
		total = buffer.readu16(data, 0),
		first = buffer.readu16(data, 2),
		count = buffer.readu16(data, 4),
		sequence = buffer.readu16(data, 6),
	}
	if size < Snapshot.sizeOf(header.count) then
		return nil, result
	end
	for index = 0, header.count - 1 do
		local offset = Snapshot.HEADER_SIZE + index * Snapshot.ENTRY_SIZE
		table.insert(result, {
			x = buffer.readi16(data, offset) / 10,
			z = buffer.readi16(data, offset + 2) / 10,
			y = buffer.readu8(data, offset + 4) / 10,
			yaw = buffer.readu8(data, offset + 5) / 256 * TAU,
			state = GeninSim.stateOf(buffer.readu8(data, offset + 6)),
		})
	end
	return header, result
end

return Snapshot
