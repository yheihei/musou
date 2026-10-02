--!strict
-- 戦場の部隊をデータで持つ（ADR 0003）。出撃したステージの配置（HaichiService）から部隊を作り、
-- 戦闘のフェーズの間、目的地へ向けて経由点をたどって位置だけを進める。下忍の個体はまだ出さない（#76）。
-- 移動の計算は ReplicatedStorage.Shared.Butai、速さ・間隔・士気の初期値は Config.luau の Butai 節にある。
--
-- - 出撃（StageService.started）で、配置の部隊を開始時の拠点の中心に作る。配置の構成が無いステージでは作らない。
--   目的地は持たせない（方針に沿って動かすのは #102）
-- - 決着（StageService.finished）とロビーのフェーズへの戻りで片付ける
-- - 部隊ごとに ReplicatedStorage.Butai の下へ部隊 ID の名前で Configuration を置き、Attribute で
--   位置（Position。Vector2 の X と Y にワールドの X と Z）・軍（Gun）・兵数（Heisu）・士気（Shiki）・
--   率いる上忍（Jonin）をクライアントへ複製する
-- - 窓口の ShowButai で、部隊の位置に軍の色の柱と、部隊 ID と兵数を出す（確認用）

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Butai = require(ReplicatedStorage.Shared.Butai)
local Colors = require(ReplicatedStorage.Shared.Colors)
local Config = require(ReplicatedStorage.Shared.Config)
local Ground = require(ReplicatedStorage.Shared.Ground)
local Gun = require(ReplicatedStorage.Shared.Gun)
local Haichi = require(ReplicatedStorage.Shared.Haichi)
local StagePhase = require(ReplicatedStorage.Shared.StagePhase)
local DebugCommand = require(script.Parent.Parent.DebugCommand)
local HaichiService = require(script.Parent.HaichiService)
local StageService = require(script.Parent.StageService)

-- 部隊を足すときの中身
export type AddSpec = {
	-- 部隊 ID。省くと Tsuika1、Tsuika2… を振る
	id: string?,
	gun: Gun.Gun,
	heisu: number,
	position: Butai.Point,
	jonin: string?,
	-- 今いる拠点
	kyoten: string?,
}

local ButaiService = {}

-- 部隊の Attribute を置くフォルダ（ReplicatedStorage の下）の名前
ButaiService.FOLDER = "Butai"

-- 確認用の柱の大きさ（スタッド）
local MARKER_HEIGHT = 14
local MARKER_WIDTH = 6

-- 足した順の部隊
local butaiList: { Butai.Butai } = {}
-- 出撃したステージの配置。拠点の中心とつながりの経由点を引く
local haichi: HaichiService.Loaded? = nil
local folder: Folder
local markerFolder: Folder? = nil
local showMarkers = false
-- 窓口で足す部隊に振る番号
local nextTsuika = 1

local function find(id: string): (Butai.Butai?, number?)
	for index, butai in butaiList do
		if butai.id == id then
			return butai, index
		end
	end
	return nil, nil
end

local function pointOf(position: Vector3): Butai.Point
	return { x = position.X, z = position.Z }
end

-- 拠点の中心。出撃したステージの配置に無ければ nil
function ButaiService.kyotenPosition(kyotenId: string): Butai.Point?
	local loaded = haichi
	if not loaded then
		return nil
	end
	for _, kyoten in loaded.kyoten do
		if kyoten.id == kyotenId then
			return pointOf(kyoten.cframe.Position)
		end
	end
	return nil
end

-- 出撃したステージのつながりを、経由点を Butai.Point にして返す
local function tsunagariList(): { Butai.Tsunagari }
	local result = {}
	local loaded = haichi
	if loaded then
		for _, tsunagari in loaded.tsunagari do
			local keiyuten = {}
			for _, point in tsunagari.keiyuten do
				table.insert(keiyuten, pointOf(point))
			end
			table.insert(result, { kyotenA = tsunagari.kyotenA, kyotenB = tsunagari.kyotenB, keiyuten = keiyuten })
		end
	end
	return result
end

local function updateMarker(butai: Butai.Butai)
	local container = markerFolder
	if not container then
		return
	end
	local marker = container:FindFirstChild(butai.id) :: Part?
	if not marker then
		local created = Instance.new("Part")
		created.Name = butai.id
		created.Shape = Enum.PartType.Cylinder
		created.Anchored = true
		created.CanCollide = false
		created.CanTouch = false
		created.CanQuery = false
		created.CastShadow = false
		created.Material = Enum.Material.Neon
		created.Transparency = 0.3
		created.Size = Vector3.new(MARKER_HEIGHT, MARKER_WIDTH, MARKER_WIDTH)
		created.Color = Colors.Gun[butai.gun]
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "Label"
		billboard.Size = UDim2.fromOffset(160, 40)
		billboard.StudsOffsetWorldSpace = Vector3.new(0, MARKER_HEIGHT / 2 + 3, 0)
		billboard.AlwaysOnTop = true
		local label = Instance.new("TextLabel")
		label.Name = "Text"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextStrokeTransparency = 0.3
		label.Parent = billboard
		billboard.Parent = created
		created.Parent = container
		marker = created
	end
	local part = marker :: Part
	local y = Ground.heightAt(butai.position.x, butai.position.z) or 0
	-- 円柱は X 軸が長さの向きなので、Z 軸まわりに 90 度回して立てる
	part.CFrame = CFrame.new(butai.position.x, y + MARKER_HEIGHT / 2, butai.position.z)
		* CFrame.Angles(0, 0, math.pi / 2)
	local label = part:FindFirstChild("Label")
	local text = label and label:FindFirstChild("Text")
	if text and text:IsA("TextLabel") then
		text.Text = `{butai.id} {butai.heisu}`
	end
end

-- 部隊の今の状態を Attribute に書いてクライアントへ複製する。確認用の柱を出していれば動かす
local function publish(butai: Butai.Butai)
	local state = folder:FindFirstChild(butai.id)
	if not state then
		local created = Instance.new("Configuration")
		created.Name = butai.id
		created.Parent = folder
		state = created
	end
	local instance = state :: Instance
	instance:SetAttribute("Gun", butai.gun)
	instance:SetAttribute("Position", Vector2.new(butai.position.x, butai.position.z))
	instance:SetAttribute("Heisu", butai.heisu)
	instance:SetAttribute("Shiki", butai.shiki)
	instance:SetAttribute("Jonin", butai.jonin)
	if showMarkers then
		updateMarker(butai)
	end
end

local function unpublish(id: string)
	local state = folder:FindFirstChild(id)
	if state then
		state:Destroy()
	end
	local container = markerFolder
	local marker = container and container:FindFirstChild(id)
	if marker then
		marker:Destroy()
	end
end

-- 部隊を足す。同じ ID の部隊がいれば足さずに nil を返す
function ButaiService.add(spec: AddSpec): Butai.Butai?
	local id = spec.id
	if not id then
		while find(`Tsuika{nextTsuika}`) do
			nextTsuika += 1
		end
		id = `Tsuika{nextTsuika}`
		nextTsuika += 1
	end
	local butaiId = id :: string
	if find(butaiId) then
		warn(`ButaiService: 部隊 {butaiId} はすでにいる`)
		return nil
	end
	local butai: Butai.Butai = {
		id = butaiId,
		gun = spec.gun,
		position = { x = spec.position.x, z = spec.position.z },
		heisu = math.max(math.floor(spec.heisu), 0),
		shiki = Config.Butai.InitialShiki,
		jonin = spec.jonin,
		mokutekichi = nil,
		keiyuten = {},
		kyoten = spec.kyoten,
		mokutekiKyoten = nil,
	}
	table.insert(butaiList, butai)
	publish(butai)
	return butai
end

-- 部隊を外す。いなければ false
function ButaiService.remove(id: string): boolean
	local _, index = find(id)
	if not index then
		return false
	end
	table.remove(butaiList, index)
	unpublish(id)
	return true
end

function ButaiService.get(id: string): Butai.Butai?
	return (find(id))
end

-- 足した順の部隊の一覧（表は写し。部隊の表はそのもの）
function ButaiService.list(): { Butai.Butai }
	return table.clone(butaiList)
end

-- 兵数を delta だけ増減する。増減した後の兵数を返す。部隊がいなければ nil
function ButaiService.changeHeisu(id: string, delta: number): number?
	local butai = find(id)
	if not butai then
		return nil
	end
	local heisu = Butai.changeHeisu(butai, delta)
	publish(butai)
	return heisu
end

-- 目的地を差し替える。mokutekichi を nil にすると、その場で止まる。部隊がいなければ false
function ButaiService.setMokutekichi(
	id: string,
	mokutekichi: Butai.Point?,
	keiyuten: { Butai.Point }?,
	kyoten: string?
): boolean
	local butai = find(id)
	if not butai then
		return false
	end
	Butai.setMokutekichi(butai, mokutekichi, keiyuten, kyoten)
	return true
end

-- 拠点へ向かわせる。今いる拠点とつながりで結ばれていれば道の経由点をたどり、結ばれていなければまっすぐ向かう。
-- 部隊がいないか、拠点が出撃したステージの配置に無ければ false
function ButaiService.moveToKyoten(id: string, kyotenId: string): boolean
	local butai = find(id)
	local target = ButaiService.kyotenPosition(kyotenId)
	if not butai or not target then
		return false
	end
	local keiyuten = if butai.kyoten then Butai.keiyutenBetween(tsunagariList(), butai.kyoten, kyotenId) else nil
	Butai.setMokutekichi(butai, target, keiyuten or {}, kyotenId)
	return true
end

-- 部隊をすべて片付ける
local function clear()
	table.clear(butaiList)
	folder:ClearAllChildren()
	local container = markerFolder
	if container then
		container:ClearAllChildren()
	end
	haichi = nil
	nextTsuika = 1
end

-- 出撃したステージの配置から部隊を作る。配置の構成が無いステージでは作らない
local function onStarted(info: StageService.StartInfo)
	clear()
	if not Haichi.get(info.stageId) then
		return
	end
	local loaded = HaichiService.load(info.stageId)
	if not loaded then
		return
	end
	haichi = loaded
	for _, entry in loaded.butai do
		local position = ButaiService.kyotenPosition(entry.kyoten)
		if not position then
			warn(
				`ButaiService: 部隊 {entry.id} の開始時の拠点 {entry.kyoten} の目印が無いので出さない`
			)
			continue
		end
		ButaiService.add({
			id = entry.id,
			gun = entry.gun,
			heisu = Haichi.heisuOf(info.stageId, entry.id) or 0,
			position = position,
			jonin = entry.jonin,
			kyoten = entry.kyoten,
		})
	end
end

-- 戦闘のフェーズの間、目的地のある部隊を進める
local function moveAll(dt: number)
	if StageService.getPhase() ~= "Battle" then
		return
	end
	for _, butai in butaiList do
		if Butai.step(butai, Config.Butai.Speed, dt) then
			publish(butai)
		end
	end
end

local function round(value: number): number
	return math.round(value * 10) / 10
end

local function describe(butai: Butai.Butai): { [string]: any }
	local mokutekichi = butai.mokutekichi
	return {
		id = butai.id,
		gun = butai.gun,
		heisu = butai.heisu,
		shiki = butai.shiki,
		jonin = butai.jonin,
		position = { round(butai.position.x), round(butai.position.z) },
		kyoten = butai.kyoten,
		mokutekiKyoten = butai.mokutekiKyoten,
		mokutekichi = if mokutekichi then { round(mokutekichi.x), round(mokutekichi.z) } else nil,
		keiyuten = #butai.keiyuten,
	}
end

local function registerDebugCommands()
	DebugCommand.register(
		"AddButai",
		"<Mikatagun|Tekigun> <兵数> <拠点 ID> [目的地の拠点 ID]",
		"出撃したステージの拠点の中心に部隊を足す。目的地を渡すと、その拠点へ向かわせる（確認用）",
		function(gun, heisu, kyotenId, mokutekiKyoten)
			if not Gun.isGun(gun) then
				error("軍は Mikatagun か Tekigun で指定する", 0)
			end
			local count = DebugCommand.toNumber(heisu, "兵数")
			local position = if type(kyotenId) == "string" then ButaiService.kyotenPosition(kyotenId) else nil
			if not position then
				return `拠点 {tostring(kyotenId)} が出撃したステージの配置に無い（出撃してから足す）`
			end
			local butai = ButaiService.add({ gun = gun, heisu = count, position = position, kyoten = kyotenId })
			if not butai then
				return "部隊を足せなかった（警告を見る）"
			end
			if mokutekiKyoten ~= nil then
				if type(mokutekiKyoten) ~= "string" or not ButaiService.moveToKyoten(butai.id, mokutekiKyoten) then
					return `部隊 {butai.id} を足したが、目的地の拠点 {tostring(mokutekiKyoten)} が配置に無い`
				end
				return `部隊 {butai.id} を {kyotenId} に足し、{mokutekiKyoten} へ向かわせた`
			end
			return `部隊 {butai.id} を {kyotenId} に足した`
		end
	)
	DebugCommand.register(
		"MoveButai",
		"<部隊 ID> <目的地の拠点 ID>",
		"部隊を拠点へ向かわせる。今いる拠点とつながっていれば道の経由点をたどる（確認用）",
		function(id, kyotenId)
			if type(id) ~= "string" or not ButaiService.get(id) then
				return `部隊 {tostring(id)} がいない`
			end
			if type(kyotenId) ~= "string" or not ButaiService.moveToKyoten(id, kyotenId) then
				return `拠点 {tostring(kyotenId)} が出撃したステージの配置に無い`
			end
			return `部隊 {id} を {kyotenId} へ向かわせた`
		end
	)
	DebugCommand.register("DumpButai", "", "部隊の一覧を JSON で返す", function()
		local result = {}
		for _, butai in butaiList do
			table.insert(result, describe(butai))
		end
		return HttpService:JSONEncode(result)
	end)
	DebugCommand.register(
		"ShowButai",
		"<true|false>",
		"部隊の位置に軍の色の柱と、部隊 ID と兵数を出すか、消すかを切り替える",
		function(value)
			showMarkers = value == true or value == "true"
			if showMarkers then
				if not markerFolder then
					local created = Instance.new("Folder")
					created.Name = "ButaiMarkers"
					created.Parent = workspace
					markerFolder = created
				end
				for _, butai in butaiList do
					updateMarker(butai)
				end
				return `部隊 {#butaiList} 個の柱を出した`
			end
			local container = markerFolder
			if container then
				container:Destroy()
				markerFolder = nil
			end
			return "部隊の柱を消した"
		end
	)
end

function ButaiService.start()
	local created = Instance.new("Folder")
	created.Name = ButaiService.FOLDER
	created.Parent = ReplicatedStorage
	folder = created

	StageService.started:Connect(onStarted)
	StageService.finished:Connect(clear)
	StageService.phaseChanged:Connect(function(next: StagePhase.Phase)
		if next == "Lobby" then
			clear()
		end
	end)
	registerDebugCommands()

	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(Config.Butai.MoveInterval)
			local now = os.clock()
			moveAll(now - last)
			last = now
		end
	end)
end

return ButaiService
