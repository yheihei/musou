--!strict
-- 支配エリアを戦場に反映する。拠点の所属と兵站線（HeitansenService）から支配エリアを持つ拠点を求め直し、
-- 部隊の交戦の押す力の倍率（ButaiService.setShihaiAreaProvider）と、上忍と首領が支配エリアの中か
-- （JoninService.setShihaiAreaProvider）に使う。判定は ReplicatedStorage.Shared.ShihaiArea、
-- 半径と倍率は Config.luau の ShihaiArea 節にある。
--
-- - 兵站線を求め直したとき（HeitansenService.changed。拠点ができたとき・制圧・つながりを通れなくしたときと戻したとき・
--   兵糧庫の指定と解除）に、支配エリアを持つ拠点を求め直す。決着とロビーのフェーズへの戻りで片付ける
-- - 支配エリアを持つのは、兵站線につながった拠点。孤立した拠点は持たず、兵糧庫は孤立しないので持つ
-- - 支配エリアを持つ拠点ごとに ReplicatedStorage.ShihaiArea の下へ拠点 ID の名前で Configuration を置き、Attribute で
--   軍（Gun）・中心（Position。Vector2 の X と Y にワールドの X と Z）・半径（Radius）をクライアントへ複製する
-- - 窓口の ShowShihaiArea で、支配エリアを軍の色の薄い円で地面に出す（確認用）

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Butai = require(ReplicatedStorage.Shared.Butai)
local Colors = require(ReplicatedStorage.Shared.Colors)
local Config = require(ReplicatedStorage.Shared.Config)
local Ground = require(ReplicatedStorage.Shared.Ground)
local Gun = require(ReplicatedStorage.Shared.Gun)
local ShihaiArea = require(ReplicatedStorage.Shared.ShihaiArea)
local StagePhase = require(ReplicatedStorage.Shared.StagePhase)
local DebugCommand = require(script.Parent.Parent.DebugCommand)
local ButaiService = require(script.Parent.ButaiService)
local HeitansenService = require(script.Parent.HeitansenService)
local JoninService = require(script.Parent.JoninService)
local KyotenService = require(script.Parent.KyotenService)
local StageService = require(script.Parent.StageService)

local ShihaiAreaService = {}

-- 支配エリアの Attribute を置くフォルダ（ReplicatedStorage の下）の名前
ShihaiAreaService.FOLDER = "ShihaiArea"

-- 確認用の円の厚みと、地面から浮かせる高さ（スタッド）。重なった円がちらつかないよう、拠点ごとに少しずつ高さをずらす
local DISC_THICKNESS = 0.4
local DISC_LIFT = 0.3
local DISC_STEP = 0.1

-- 支配エリアを持つ拠点（配置の順）
local sources: { ShihaiArea.Kyoten } = {}
local folder: Folder
local discFolder: Folder? = nil
local showDiscs = false

-- 地点がどの軍の支配エリアか。どちらのものでもなければ nil
function ShihaiAreaService.gunAt(position: Butai.Point): Gun.Gun?
	return ShihaiArea.gunAt(sources, position.x, position.z)
end

-- 支配エリアを持つ拠点の一覧（配置の順。表は写し）
function ShihaiAreaService.sources(): { ShihaiArea.Kyoten }
	return table.clone(sources)
end

-- 確認用の円を描き直す
local function drawDiscs()
	local container = discFolder
	if not container then
		return
	end
	container:ClearAllChildren()
	local radius = Config.ShihaiArea.Radius
	for index, kyoten in sources do
		local gun = kyoten.gun :: Gun.Gun
		local y = Ground.heightAt(kyoten.x, kyoten.z) or 0
		local disc = Instance.new("Part")
		disc.Name = kyoten.id
		disc.Shape = Enum.PartType.Cylinder
		disc.Anchored = true
		disc.CanCollide = false
		disc.CanTouch = false
		disc.CanQuery = false
		disc.CastShadow = false
		disc.Material = Enum.Material.SmoothPlastic
		disc.Color = Colors.Gun[gun]
		disc.Transparency = 0.75
		disc.Size = Vector3.new(DISC_THICKNESS, radius * 2, radius * 2)
		-- 円柱の軸（X）を縦にして地面に寝かせる
		disc.CFrame = CFrame.new(kyoten.x, y + DISC_LIFT + index * DISC_STEP, kyoten.z)
			* CFrame.Angles(0, 0, math.rad(90))
		disc.Parent = container
	end
end

-- 支配エリアを持つ拠点を複製し直す。持たなくなった拠点は外す
local function publish()
	local keep: { [string]: boolean } = {}
	for _, kyoten in sources do
		keep[kyoten.id] = true
		local instance = folder:FindFirstChild(kyoten.id)
		if not instance then
			local created = Instance.new("Configuration")
			created.Name = kyoten.id
			created.Parent = folder
			instance = created
		end
		local config = instance :: Instance
		config:SetAttribute("Gun", kyoten.gun)
		config:SetAttribute("Position", Vector2.new(kyoten.x, kyoten.z))
		config:SetAttribute("Radius", Config.ShihaiArea.Radius)
	end
	for _, child in folder:GetChildren() do
		if not keep[child.Name] then
			child:Destroy()
		end
	end
	if showDiscs then
		drawDiscs()
	end
end

-- 支配エリアを持つ拠点を、拠点の所属と兵站線から求め直す
local function recompute()
	local list: { ShihaiArea.Kyoten } = {}
	for _, kyoten in KyotenService.list() do
		local center = KyotenService.centerOf(kyoten.id)
		if center then
			table.insert(list, {
				id = kyoten.id,
				gun = kyoten.gun,
				x = center.x,
				z = center.z,
				connected = HeitansenService.isConnected(kyoten.gun, kyoten.id),
			})
		end
	end
	sources = ShihaiArea.sourcesOf(list)
	publish()
end

local function clear()
	table.clear(sources)
	folder:ClearAllChildren()
	local container = discFolder
	if container then
		container:ClearAllChildren()
	end
end

local function round(value: number): number
	return math.round(value * 10) / 10
end

local function describe(x: number?, z: number?): { [string]: any }
	local list = {}
	for _, kyoten in sources do
		table.insert(list, { id = kyoten.id, gun = kyoten.gun, center = { round(kyoten.x), round(kyoten.z) } })
	end
	local butai = {}
	for _, item in ButaiService.list() do
		table.insert(butai, {
			id = item.id,
			gun = item.gun,
			area = ShihaiAreaService.gunAt(item.position),
			push = round(ButaiService.shihaiAreaOf(item)),
		})
	end
	local jonin = {}
	for _, item in JoninService.list() do
		table.insert(jonin, { id = item.id, gun = item.gun, shihaiArea = item.shihaiArea })
	end
	return {
		radius = Config.ShihaiArea.Radius,
		sources = list,
		at = if x and z then ShihaiAreaService.gunAt({ x = x, z = z }) else nil,
		butai = butai,
		jonin = jonin,
	}
end

local function registerDebugCommands()
	DebugCommand.register(
		"DumpShihaiArea",
		"[x z]",
		"支配エリアを持つ拠点、部隊ごとのいる地点の支配エリアの軍と押す力の倍率、上忍と首領が支配エリアの中かを JSON で返す。x と z を渡すと、その地点の支配エリアの軍（at）も返す",
		function(x, z)
			local px = if x ~= nil then DebugCommand.toNumber(x, "x") else nil
			local pz = if z ~= nil then DebugCommand.toNumber(z, "z") else nil
			return HttpService:JSONEncode(describe(px, pz))
		end
	)
	DebugCommand.register(
		"ShowShihaiArea",
		"<true|false>",
		"支配エリアを拠点ごとに軍の色の薄い円で地面に出すか、消すかを切り替える。重なりは円が重なって見えるだけなので、重なる地点の軍は DumpShihaiArea <x> <z> の at で確かめる",
		function(value)
			showDiscs = value == true or value == "true"
			if showDiscs then
				if not discFolder then
					local created = Instance.new("Folder")
					created.Name = "ShihaiAreaDiscs"
					created.Parent = workspace
					discFolder = created
				end
				drawDiscs()
				return `支配エリア {#sources} 個の円を出した`
			end
			local container = discFolder
			if container then
				container:Destroy()
				discFolder = nil
			end
			return "支配エリアの円を消した"
		end
	)
end

function ShihaiAreaService.start()
	local created = Instance.new("Folder")
	created.Name = ShihaiAreaService.FOLDER
	created.Parent = ReplicatedStorage
	folder = created

	ButaiService.setShihaiAreaProvider(function(butai: Butai.Butai): number
		return ShihaiArea.pushOf(ShihaiAreaService.gunAt(butai.position), butai.gun)
	end)
	JoninService.setShihaiAreaProvider(function(gun: Gun.Gun, position: Butai.Point): boolean
		return ShihaiAreaService.gunAt(position) == gun
	end)
	HeitansenService.changed:Connect(recompute)
	StageService.finished:Connect(clear)
	StageService.phaseChanged:Connect(function(next: StagePhase.Phase)
		if next == "Lobby" then
			clear()
		end
	end)
	registerDebugCommands()
end

return ShihaiAreaService
