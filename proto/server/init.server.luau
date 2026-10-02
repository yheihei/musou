--!strict
-- 下忍の描き方の試作のサーバー（検証用ブランチだけ。main には入れない）。
-- 案A（サーバーの Humanoid）と案B（サーバーは位置と状態だけを持ち、クライアントが描く）を切り替え、
-- 同じ動き（近づく・攻撃する・吹き飛ぶ・倒れる・湧き直す）で比べる。案B は送り方を Attribute と
-- UnreliableRemoteEvent から選ぶ。体数は Config.luau の GeninProto 節の Counts から選ぶ。
--
-- - 画面のボタン（ReplicatedStorage.ProtoRemotes.SetMode）で、方式・体数・自動の薙ぎ払いを1項目ずつ切り替える
--   （引数は項目の名前 Mode・Count・AutoSweep と値）
-- - 自動の薙ぎ払いは、SweepInterval 秒ごとに全員の足元から下忍を吹き飛ばし、吹き飛びと撃破を一定の頻度で起こす
-- - 今の方式・体数・自動の薙ぎ払い、サーバーの Heartbeat の回数（1秒あたり）、直前の薙ぎ払いで当てた数を
--   workspace の Attribute に置く（ProtoMode・ProtoCount・ProtoAutoSweep・ServerHeartbeat・ProtoSweepHits）
-- - 各ループは1回の失敗を警告にして続ける

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local ModeA = require(script:WaitForChild("ModeA"))
local ModeB = require(script:WaitForChild("ModeB"))
local Template = require(script:WaitForChild("Template"))

type Mode = "A" | "BAttribute" | "BUnreliable"

local P = Config.GeninProto
local MODES: { Mode } = { "A", "BAttribute", "BUnreliable" }
-- 案A の下忍を動かす間隔（秒）。今の EnemyService と同じ
local A_TICK = 0.25

local remotes = ReplicatedStorage:WaitForChild("ProtoRemotes")
local setModeRemote = remotes:WaitForChild("SetMode") :: RemoteEvent
local snapshotRemote = remotes:WaitForChild("Snapshot") :: UnreliableRemoteEvent

local template = Template.build()
local mode: Mode = "A"
local count = P.DefaultCount
local autoSweep = true

-- 生きているプレイヤーの位置
local function playerPositions(): { Vector3 }
	local result = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if humanoid and root and humanoid.Health > 0 then
			table.insert(result, root.Position)
		end
	end
	return result
end

-- 湧かせる中心。プレイヤーがいなければ原点
local function center(): Vector3
	local positions = playerPositions()
	return if #positions > 0 then positions[math.random(1, #positions)] else Vector3.zero
end

local function publish()
	workspace:SetAttribute("ProtoMode", mode)
	workspace:SetAttribute("ProtoCount", count)
	workspace:SetAttribute("ProtoAutoSweep", autoSweep)
end

local function apply(nextMode: Mode, nextCount: number)
	ModeA.stop()
	ModeB.stop()
	mode = nextMode
	count = nextCount
	if mode == "A" then
		ModeA.start(count, template, center)
	else
		ModeB.start(count, if mode == "BAttribute" then "Attribute" else "Unreliable", center())
	end
	publish()
	print(`[GeninProto] 方式 {mode}、{count} 体`)
end

-- 1項目ずつ切り替える。続けて押されたときに、前の切り替えを古い値で戻さないため
setModeRemote.OnServerEvent:Connect(function(_player: Player, field: unknown, value: unknown)
	if field == "Mode" and type(value) == "string" and table.find(MODES, value :: any) then
		if value ~= mode then
			apply(value :: Mode, count)
		end
	elseif field == "Count" and type(value) == "number" and table.find(P.Counts, value) then
		if value ~= count then
			apply(mode, value)
		end
	elseif field == "AutoSweep" and type(value) == "boolean" then
		autoSweep = value
		publish()
	end
end)

-- ループの1回分を実行する。失敗したら警告を出して、次の回へ続ける
local function guarded(label: string, body: () -> ())
	local ok, err = pcall(body)
	if not ok then
		warn(`[GeninProto] {label}に失敗した: {err}`)
	end
end

-- サーバーの Heartbeat の回数を1秒ごとに数える
local frames = 0
local measuredAt = os.clock()
RunService.Heartbeat:Connect(function()
	frames += 1
	local now = os.clock()
	if now - measuredAt >= 1 then
		workspace:SetAttribute("ServerHeartbeat", math.round(frames / (now - measuredAt)))
		frames = 0
		measuredAt = now
	end
end)

-- 案A の下忍を動かす
task.spawn(function()
	while true do
		task.wait(A_TICK)
		if mode == "A" then
			guarded("案A の下忍の動き", function()
				ModeA.step(playerPositions())
			end)
		end
	end
end)

-- 案B の下忍を計算する
task.spawn(function()
	local last = os.clock()
	while true do
		task.wait(1 / P.SimRate)
		local now = os.clock()
		local dt = now - last
		last = now
		if mode ~= "A" then
			guarded("案B の下忍の計算", function()
				ModeB.step(dt, playerPositions())
			end)
		end
	end
end)

-- 案B の位置と状態を送る
task.spawn(function()
	while true do
		task.wait(1 / P.SendRate)
		if mode ~= "A" then
			guarded("案B の送信", function()
				ModeB.send(snapshotRemote)
			end)
		end
	end
end)

-- 自動の薙ぎ払い。当てた数を、2つの方式で撃破の頻度がそろっているかを見るために出す
task.spawn(function()
	while true do
		task.wait(P.SweepInterval)
		if autoSweep then
			guarded("薙ぎ払い", function()
				local hits = 0
				for _, position in playerPositions() do
					hits += if mode == "A" then ModeA.sweep(position) else ModeB.sweep(position)
				end
				workspace:SetAttribute("ProtoSweepHits", hits)
			end)
		end
	end
end)

-- 最初のプレイヤーが出てから湧かせる（湧かせる中心をプレイヤーの近くにするため）
task.spawn(function()
	while #playerPositions() == 0 do
		task.wait(0.5)
	end
	apply(mode, count)
end)
publish()
