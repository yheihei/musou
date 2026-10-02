--!strict
-- 案B。下忍の位置と状態だけを ReplicatedStorage.Shared.Proto.GeninSim で持ち、クライアントへ送る。モデルはクライアントが描く。
-- 送り方は2つから選ぶ。
--
-- - Attribute: 下忍ごとに ReplicatedStorage.ProtoGeninB の下へ番号の名前で Configuration を置き、
--   Attribute の P（Vector3 の x・高さ・z）・Yaw（向き）・S（状態の番号）を、変わったものだけ書く
-- - Unreliable: 全員を ReplicatedStorage.Shared.Proto.Snapshot で buffer に詰め、UnreliableRemoteEvent で全員へ送る
--   （1回に詰めきれない体数は分けて送る。引数は最初の番号と buffer）

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GeninSim = require(ReplicatedStorage.Shared.Proto.GeninSim)
local Snapshot = require(ReplicatedStorage.Shared.Proto.Snapshot)

export type Sync = "Attribute" | "Unreliable"

-- Attribute の送り方で使うフォルダの名前（ReplicatedStorage の下）
local FOLDER = "ProtoGeninB"
-- 変わったとみなす位置と向きの差（これより小さい差は送らない）
local POSITION_EPSILON = 0.05
local YAW_EPSILON = 0.02

-- 最後に書いた値。書いた項目だけを更新する（少しずつの変化を取りこぼさないため）
type Sent = { x: number, y: number, z: number, yaw: number, code: number }

local ModeB = {}

local list: { GeninSim.Genin } = {}
local sync: Sync = "Unreliable"
local folder: Folder? = nil
-- Attribute の送り方で、最後に書いた値
local sent: { [number]: Sent } = {}
-- Unreliable の送り方で、送った回の番号
local sequence = 0

local function rand(): number
	return math.random()
end

-- count 体を center の周りに作り、sync の送り方で送り始める
function ModeB.start(count: number, syncMode: Sync, center: Vector3)
	ModeB.stop()
	sync = syncMode
	list = GeninSim.create(count, { x = center.X, z = center.Z }, rand)
	if sync == "Attribute" then
		local created = Instance.new("Folder")
		created.Name = FOLDER
		for index = 1, count do
			local state = Instance.new("Configuration")
			state.Name = tostring(index)
			state.Parent = created
		end
		created.Parent = ReplicatedStorage
		folder = created
	end
end

function ModeB.stop()
	list = {}
	table.clear(sent)
	local container = folder
	if container then
		container:Destroy()
	end
	folder = nil
end

-- 全員を dt 秒進める。targets はプレイヤーの位置
function ModeB.step(dt: number, targets: { Vector3 })
	local points = {}
	for _, target in targets do
		table.insert(points, { x = target.X, z = target.Z })
	end
	GeninSim.step(list, points, dt, os.clock(), rand)
end

-- center からの薙ぎ払い。当てた数を返す
function ModeB.sweep(center: Vector3): number
	return GeninSim.sweep(list, { x = center.X, z = center.Z })
end

local function sendAttributes()
	local container = folder
	if not container then
		return
	end
	for index, genin in list do
		local state = container:FindFirstChild(tostring(index))
		if not state then
			continue
		end
		local code = GeninSim.codeOf(genin.state)
		local last = sent[index]
		if not last then
			state:SetAttribute("P", Vector3.new(genin.x, genin.y, genin.z))
			state:SetAttribute("Yaw", genin.yaw)
			state:SetAttribute("S", code)
			sent[index] = { x = genin.x, y = genin.y, z = genin.z, yaw = genin.yaw, code = code }
			continue
		end
		if
			math.abs(last.x - genin.x) > POSITION_EPSILON
			or math.abs(last.z - genin.z) > POSITION_EPSILON
			or math.abs(last.y - genin.y) > POSITION_EPSILON
		then
			state:SetAttribute("P", Vector3.new(genin.x, genin.y, genin.z))
			last.x, last.y, last.z = genin.x, genin.y, genin.z
		end
		if math.abs(last.yaw - genin.yaw) > YAW_EPSILON then
			state:SetAttribute("Yaw", genin.yaw)
			last.yaw = genin.yaw
		end
		if last.code ~= code then
			state:SetAttribute("S", code)
			last.code = code
		end
	end
end

local function sendUnreliable(remote: UnreliableRemoteEvent)
	sequence = (sequence + 1) % Snapshot.SEQUENCE_MODULO
	local chunk = Snapshot.maxCount()
	local first = 1
	while first <= #list do
		local last = math.min(first + chunk - 1, #list)
		remote:FireAllClients(Snapshot.pack(list, first, last, sequence))
		first = last + 1
	end
end

-- 今の位置と状態をクライアントへ送る
function ModeB.send(remote: UnreliableRemoteEvent)
	if sync == "Attribute" then
		sendAttributes()
	else
		sendUnreliable(remote)
	end
end

function ModeB.count(): number
	return #list
end

return ModeB
