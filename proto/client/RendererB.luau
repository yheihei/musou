--!strict
-- 案B の下忍を描く。サーバーから届く位置と状態（Attribute か UnreliableRemoteEvent）を、描いている位置から
-- 新しい位置へ補間する。補間にかける時間は、その下忍に前の値が届いてからの間隔（送る間隔から、その3倍まで）にし、
-- 届く間隔のぶれで止まって見えないようにする。
-- モデルはサーバーが ReplicatedStorage に置いた見本（ProtoGeninTemplate）を、パーツが全部届いてから写す。
-- Humanoid を外して HumanoidRootPart だけを固定し（ほかのパーツは Motor6D でつながったまま一緒に動く）、
-- 位置は workspace:BulkMoveTo でまとめて動かす。攻撃中は胴の色を変え、倒れたら寝かせ、消えたら外す。
-- UnreliableRemoteEvent は届く順が前後するので、送った回の番号が古いものと、今の体数と合わないものは捨てる。

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local GeninSim = require(ReplicatedStorage.Shared.Proto.GeninSim)
local Snapshot = require(ReplicatedStorage.Shared.Proto.Snapshot)

local RendererB = {}

local TEMPLATE_NAME = "ProtoGeninTemplate"
local ATTRIBUTE_FOLDER = "ProtoGeninB"
local ATTACK_COLOR = Color3.fromRGB(230, 80, 80)
local BODY_COLOR = Color3.fromRGB(70, 90, 160)
local INTERVAL = 1 / Config.GeninProto.SendRate
-- 見本のパーツが全部届くまで待つ秒数の上限
local TEMPLATE_TIMEOUT = 10

type Pose = { x: number, z: number, y: number, yaw: number }

type Sample = {
	from: Pose,
	to: Pose,
	receivedAt: number,
	-- 補間にかける秒数
	duration: number,
	state: GeninSim.State,
}

type Figure = {
	model: Model,
	root: BasePart,
	torso: BasePart?,
	state: GeninSim.State?,
	shown: boolean,
}

local container: Folder
local template: Model? = nil
-- 地面から HumanoidRootPart の中心までの高さ
local rootHeight = 3
local samples: { [number]: Sample } = {}
local figures: { [number]: Figure } = {}
local attributeConnections: { RBXScriptConnection } = {}
local active = false
-- Unreliable の送り方で、最後に受け付けた送った回の番号
local latestSequence: number? = nil

local function lerpAngle(a: number, b: number, t: number): number
	local delta = (b - a + math.pi) % (math.pi * 2) - math.pi
	return a + delta * t
end

local function poseNow(sample: Sample, now: number): Pose
	local t = math.clamp((now - sample.receivedAt) / sample.duration, 0, 1)
	local from, to = sample.from, sample.to
	return {
		x = from.x + (to.x - from.x) * t,
		z = from.z + (to.z - from.z) * t,
		y = from.y + (to.y - from.y) * t,
		yaw = lerpAngle(from.yaw, to.yaw, t),
	}
end

-- index 番の下忍に新しい位置と状態が届いた。今描いている位置から新しい位置へ補間し直す
local function receive(index: number, pose: Pose, state: GeninSim.State)
	local now = os.clock()
	local previous = samples[index]
	local from = pose
	local duration = INTERVAL
	if previous then
		duration = math.clamp(now - previous.receivedAt, INTERVAL, INTERVAL * 3)
		-- 湧き直した（消えていた）下忍は、補間せずに新しい位置から描く
		if previous.state ~= "Hidden" and state ~= "Hidden" then
			from = poseNow(previous, now)
		end
	end
	samples[index] = { from = from, to = pose, receivedAt = now, duration = duration, state = state }
end

local function prepare(source: Model): Model
	local model = source:Clone()
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("LuaSourceContainer") then
			descendant:Destroy()
		end
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:Destroy()
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = descendant == root
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.Massless = true
		end
	end
	return model
end

local function figureOf(index: number): Figure?
	local figure = figures[index]
	if figure then
		return figure
	end
	local source = template
	if not source then
		return nil
	end
	local model = prepare(source)
	model.Name = `Genin{index}`
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		model:Destroy()
		return nil
	end
	local created: Figure = {
		model = model,
		root = root,
		torso = model:FindFirstChild("UpperTorso") :: BasePart?,
		state = nil,
		shown = false,
	}
	figures[index] = created
	return created
end

local function clear()
	for _, connection in attributeConnections do
		connection:Disconnect()
	end
	table.clear(attributeConnections)
	for _, figure in figures do
		figure.model:Destroy()
	end
	table.clear(figures)
	table.clear(samples)
end

local function render()
	if not active then
		return
	end
	local now = os.clock()
	local roots: { BasePart } = {}
	local cframes: { CFrame } = {}
	for index, sample in samples do
		local figure = figureOf(index)
		if not figure then
			continue
		end
		local state = sample.state
		if state == "Hidden" then
			if figure.shown then
				figure.model.Parent = nil
				figure.shown = false
			end
			continue
		end
		if not figure.shown then
			figure.model.Parent = container
			figure.shown = true
		end
		if figure.state ~= state then
			figure.state = state
			local torso = figure.torso
			if torso then
				torso.Color = if state == "Attack" then ATTACK_COLOR else BODY_COLOR
			end
		end
		local pose = poseNow(sample, now)
		local cframe = CFrame.new(pose.x, rootHeight + pose.y, pose.z) * CFrame.Angles(0, pose.yaw, 0)
		if state == "Down" then
			-- 仰向けに寝かせ、地面まで下げる
			cframe = CFrame.new(pose.x, 1, pose.z) * CFrame.Angles(0, pose.yaw, 0) * CFrame.Angles(math.pi / 2, 0, 0)
		end
		table.insert(roots, figure.root)
		table.insert(cframes, cframe)
	end
	if #roots > 0 then
		workspace:BulkMoveTo(roots, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

local function watchAttributes()
	local folder = ReplicatedStorage:FindFirstChild(ATTRIBUTE_FOLDER)
	if not folder then
		return
	end
	local function watch(state: Instance)
		local index = tonumber(state.Name)
		if not index then
			return
		end
		local function update()
			local position = state:GetAttribute("P")
			local yaw = state:GetAttribute("Yaw")
			local code = state:GetAttribute("S")
			if typeof(position) ~= "Vector3" then
				return
			end
			local p = position :: Vector3
			receive(
				index :: number,
				{ x = p.X, z = p.Z, y = p.Y, yaw = if type(yaw) == "number" then yaw else 0 },
				GeninSim.stateOf(if type(code) == "number" then code else 0)
			)
		end
		table.insert(attributeConnections, state.AttributeChanged:Connect(update))
		update()
	end
	for _, child in folder:GetChildren() do
		watch(child)
	end
	table.insert(attributeConnections, folder.ChildAdded:Connect(watch))
end

-- 方式か体数が変わったら描いていた下忍を片付け、案B なら描き始める
local function onModeChanged()
	clear()
	local mode = workspace:GetAttribute("ProtoMode")
	active = mode == "BAttribute" or mode == "BUnreliable"
	if mode == "BAttribute" then
		-- フォルダはサーバーが方式を切り替えた直後に作るので、少し待ってから見る
		task.spawn(function()
			local folder = ReplicatedStorage:WaitForChild(ATTRIBUTE_FOLDER, 5)
			if folder and workspace:GetAttribute("ProtoMode") == "BAttribute" then
				watchAttributes()
			end
		end)
	end
end

-- Unreliable の送り方で届いたものを受け付けるか。送った回の番号が古いものと、今の体数と合わないものは捨てる
local function accepts(header: Snapshot.Header): boolean
	if header.total ~= workspace:GetAttribute("ProtoCount") then
		return false
	end
	local latest = latestSequence
	if latest and Snapshot.isStale(header.sequence, latest) then
		return false
	end
	latestSequence = header.sequence
	return true
end

-- 見本のパーツが全部届くまで待ってから使う
local function loadTemplate()
	local source = ReplicatedStorage:WaitForChild(TEMPLATE_NAME) :: Model
	local expected = source:GetAttribute("PartCount")
	local deadline = os.clock() + TEMPLATE_TIMEOUT
	while type(expected) == "number" and os.clock() < deadline do
		local parts = 0
		for _, descendant in source:GetDescendants() do
			if descendant:IsA("BasePart") then
				parts += 1
			end
		end
		if parts >= expected then
			break
		end
		task.wait(0.1)
	end
	local humanoid = source:FindFirstChildOfClass("Humanoid")
	local root = source:FindFirstChild("HumanoidRootPart") :: BasePart?
	if humanoid and root then
		rootHeight = humanoid.HipHeight + root.Size.Y / 2
	end
	template = source
end

function RendererB.start()
	local created = Instance.new("Folder")
	created.Name = "ProtoGeninB"
	created.Parent = workspace
	container = created

	task.spawn(loadTemplate)

	local remote = ReplicatedStorage:WaitForChild("ProtoRemotes"):WaitForChild("Snapshot") :: UnreliableRemoteEvent
	remote.OnClientEvent:Connect(function(data: buffer)
		if workspace:GetAttribute("ProtoMode") ~= "BUnreliable" or typeof(data) ~= "buffer" then
			return
		end
		local header, entries = Snapshot.unpack(data)
		if not header or not accepts(header) then
			return
		end
		for offset, entry in entries do
			local index = header.first + offset - 1
			if index <= header.total then
				receive(index, { x = entry.x, z = entry.z, y = entry.y, yaw = entry.yaw }, entry.state)
			end
		end
	end)

	workspace:GetAttributeChangedSignal("ProtoMode"):Connect(onModeChanged)
	workspace:GetAttributeChangedSignal("ProtoCount"):Connect(onModeChanged)
	onModeChanged()
	RunService.RenderStepped:Connect(render)
end

return RendererB
