--!strict
-- ステージの配置を、構成（ReplicatedStorage.Shared.Haichi）とプレースの目印から読み込む（ADR 0006）。
-- 拠点の目印は <区画>.Mejirushi.Kyoten の下に拠点 ID の名前で、つながりの道筋は <区画>.Mejirushi.Tsunagari の下の
-- フォルダ（Attribute の KyotenA・KyotenB）に経由点 1、2… を置く。構成と目印の食い違いは警告を出す。
--
-- - 構成にあって目印が無い拠点は読み込まない。目印が無いつながりは、拠点の間をまっすぐ結ぶ
-- - 試験用ステージの目印は構成に位置を持ち、テストプレイ中に作る（プレースには保存しない）。
--   目印が無ければ読み込むときに作り、窓口の PlaceShikenMejirushi でも作り直せる
-- - 首領は Stages.luau の両軍の首領を、その軍の本陣から出す

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Colors = require(ReplicatedStorage.Shared.Colors)
local Gun = require(ReplicatedStorage.Shared.Gun)
local Ground = require(ReplicatedStorage.Shared.Ground)
local Haichi = require(ReplicatedStorage.Shared.Haichi)
local Mejirushi = require(ReplicatedStorage.Shared.Mejirushi)
local Stages = require(ReplicatedStorage.Shared.Stages)
local DebugCommand = require(script.Parent.Parent.DebugCommand)
local KukakuService = require(script.Parent.KukakuService)

export type LoadedKyoten = {
	id: string,
	honjin: boolean,
	gun: Gun.Gun,
	-- 拠点の範囲の中心と向き、大きさ
	cframe: CFrame,
	size: Vector3,
}

export type LoadedTsunagari = {
	kyotenA: string,
	kyotenB: string,
	-- kyotenA から kyotenB へたどる順の経由点（両端の拠点は含まない）
	keiyuten: { Vector3 },
}

export type LoadedShuryo = {
	gun: Gun.Gun,
	characterId: string,
	-- 出す本陣の拠点 ID
	kyoten: string,
}

export type Loaded = {
	stageId: string,
	kyoten: { LoadedKyoten },
	tsunagari: { LoadedTsunagari },
	butai: { Haichi.Butai },
	shuryo: { LoadedShuryo },
	-- 構成と目印の食い違い（警告に出したもの）
	warnings: { string },
}

local HaichiService = {}

-- 試験用ステージの拠点の目印の高さと、経由点の目印の大きさ（スタッド）
local KYOTEN_HEIGHT = 30
local KEIYUTEN_SIZE = 2
local KEIYUTEN_COLOR = Color3.fromRGB(255, 255, 255)

local function makeMarker(name: string, size: Vector3, cframe: CFrame, color: Color3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Transparency = 0.5
	CollectionService:AddTag(part, Mejirushi.TAG)
	part.Parent = parent
	return part
end

-- 区画の中心からの (x, z) の、ワールドでの地面の位置
local function groundPoint(center: Vector3, x: number, z: number): Vector3
	local worldX, worldZ = center.X + x, center.Z + z
	local y = Ground.heightAt(worldX, worldZ) or center.Y
	return Vector3.new(worldX, y, worldZ)
end

-- 試験用ステージの目印を、構成の位置から作り直す。作ったら true
function HaichiService.placeShikenMejirushi(stageId: string): boolean
	local stage = Stages.get(stageId)
	local haichi = Haichi.get(stageId)
	local mejirushi = haichi and haichi.shikenMejirushi
	if not stage or not haichi or not mejirushi then
		warn(`HaichiService: {stageId} は目印の位置をコードに持つ試験用ステージではない`)
		return false
	end
	local folder = KukakuService.mejirushiOf(stage.kukaku)
	local bounds = KukakuService.bounds(stage.kukaku)
	if not folder or not bounds then
		return false
	end
	if
		math.abs(bounds.Size.X - mejirushi.kukakuSizeX) > 0.5
		or math.abs(bounds.Size.Z - mejirushi.kukakuSizeZ) > 0.5
	then
		warn(
			`HaichiService: 区画 {stage.kukaku} の範囲（{bounds.Size.X} × {bounds.Size.Z}）が構成の大きさ（{mejirushi.kukakuSizeX} × {mejirushi.kukakuSizeZ}）と違う`
		)
	end
	for _, name in { Mejirushi.KYOTEN, Mejirushi.TSUNAGARI } do
		local old = folder:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	local center = bounds.Position
	local kyotenFolder = Instance.new("Folder")
	kyotenFolder.Name = Mejirushi.KYOTEN
	for _, kyoten in haichi.kyoten do
		local ichi = mejirushi.kyoten[kyoten.id]
		if ichi then
			local ground = groundPoint(center, ichi.x, ichi.z)
			makeMarker(
				kyoten.id,
				Vector3.new(ichi.sizeX, KYOTEN_HEIGHT, ichi.sizeZ),
				CFrame.new(ground + Vector3.new(0, KYOTEN_HEIGHT / 2, 0)),
				Colors.Gun[kyoten.gun],
				kyotenFolder
			)
		end
	end
	local tsunagariFolder = Instance.new("Folder")
	tsunagariFolder.Name = Mejirushi.TSUNAGARI
	for _, tsunagari in mejirushi.tsunagari do
		local route = Instance.new("Folder")
		route.Name = `{tsunagari.kyotenA}-{tsunagari.kyotenB}`
		route:SetAttribute(Mejirushi.KYOTEN_A, tsunagari.kyotenA)
		route:SetAttribute(Mejirushi.KYOTEN_B, tsunagari.kyotenB)
		for index, point in tsunagari.keiyuten do
			local ground = groundPoint(center, point.x, point.z)
			makeMarker(
				tostring(index),
				Vector3.one * KEIYUTEN_SIZE,
				CFrame.new(ground + Vector3.new(0, KEIYUTEN_SIZE / 2, 0)),
				KEIYUTEN_COLOR,
				route
			)
		end
		route.Parent = tsunagariFolder
	end
	kyotenFolder.Parent = folder
	tsunagariFolder.Parent = folder
	return true
end

-- つながりの道筋の目印。フォルダごとに両端と経由点を返す
local function readTsunagari(folder: Instance?, where: string): { LoadedTsunagari }
	local result = {}
	if not folder then
		return result
	end
	for _, route in folder:GetChildren() do
		local kyotenA = route:GetAttribute(Mejirushi.KYOTEN_A)
		local kyotenB = route:GetAttribute(Mejirushi.KYOTEN_B)
		if type(kyotenA) ~= "string" or type(kyotenB) ~= "string" then
			warn(
				`HaichiService: {where}のつながりの目印 {route.Name} に Attribute の {Mejirushi.KYOTEN_A}・{Mejirushi.KYOTEN_B} が無い`
			)
			continue
		end
		local parts: { [string]: BasePart } = {}
		local names = {}
		for _, child in route:GetChildren() do
			if child:IsA("BasePart") then
				parts[child.Name] = child
				table.insert(names, child.Name)
			end
		end
		local numbered, unknown = Mejirushi.sortKeiyuten(names)
		if #unknown > 0 then
			warn(
				`HaichiService: {where}のつながりの目印 {route.Name} の経由点の名前 {table.concat(
					unknown,
					"、"
				)} は番号として読めない`
			)
		end
		local keiyuten = {}
		for _, name in numbered do
			table.insert(keiyuten, parts[name].Position)
		end
		table.insert(result, { kyotenA = kyotenA, kyotenB = kyotenB, keiyuten = keiyuten })
	end
	return result
end

-- ステージの配置を読み込む。構成か区画が無ければ警告を出して nil
function HaichiService.load(stageId: string): Loaded?
	local stage = Stages.get(stageId)
	local haichi = Haichi.get(stageId)
	if not stage or not haichi then
		warn(`HaichiService: ステージ {stageId} の配置の構成が無い`)
		return nil
	end
	local folder = KukakuService.mejirushiOf(stage.kukaku)
	if not folder then
		return nil
	end
	if haichi.shikenMejirushi and not folder:FindFirstChild(Mejirushi.KYOTEN) then
		HaichiService.placeShikenMejirushi(stageId)
	end
	local where = `ステージ {stageId} の`
	local kyotenParts: { [string]: BasePart } = {}
	local kyotenNames = {}
	local kyotenFolder = folder:FindFirstChild(Mejirushi.KYOTEN)
	for _, child in if kyotenFolder then kyotenFolder:GetChildren() else {} do
		if child:IsA("BasePart") then
			kyotenParts[child.Name] = child
			table.insert(kyotenNames, child.Name)
		end
	end
	local routes = readTsunagari(folder:FindFirstChild(Mejirushi.TSUNAGARI), where)
	local warnings = Haichi.compareMejirushi(haichi, kyotenNames, routes)
	for _, message in warnings do
		warn(`HaichiService: {where}配置: {message}`)
	end

	local loaded: Loaded = {
		stageId = stageId,
		kyoten = {},
		tsunagari = {},
		butai = table.clone(haichi.butai),
		shuryo = {},
		warnings = warnings,
	}
	for _, kyoten in haichi.kyoten do
		local part = kyotenParts[kyoten.id]
		if part then
			table.insert(loaded.kyoten, {
				id = kyoten.id,
				honjin = kyoten.honjin,
				gun = kyoten.gun,
				cframe = part.CFrame,
				size = part.Size,
			})
		end
	end
	local routeOf: { [string]: LoadedTsunagari } = {}
	for _, route in routes do
		routeOf[Haichi.pairKey(route.kyotenA, route.kyotenB)] = route
	end
	for _, tsunagari in haichi.tsunagari do
		local route = routeOf[Haichi.pairKey(tsunagari.kyotenA, tsunagari.kyotenB)]
		local keiyuten = {}
		if route then
			keiyuten = table.clone(route.keiyuten)
			-- 目印のフォルダが逆向きなら、経由点も逆にたどる
			if route.kyotenA ~= tsunagari.kyotenA then
				local reversed = {}
				for index = #keiyuten, 1, -1 do
					table.insert(reversed, keiyuten[index])
				end
				keiyuten = reversed
			end
		end
		table.insert(
			loaded.tsunagari,
			{ kyotenA = tsunagari.kyotenA, kyotenB = tsunagari.kyotenB, keiyuten = keiyuten }
		)
	end
	for _, gun in Gun.list do
		local characterId = if gun == "Mikatagun" then stage.shuryo.mikatagun else stage.shuryo.tekigun
		local honjin = Haichi.honjinOf(haichi, gun)
		if characterId and honjin then
			table.insert(loaded.shuryo, { gun = gun, characterId = characterId, kyoten = honjin })
		end
	end
	return loaded
end

local function round(value: number): number
	return math.round(value * 10) / 10
end

local function summarize(loaded: Loaded): { [string]: any }
	local kyoten = {}
	for _, item in loaded.kyoten do
		local position = item.cframe.Position
		table.insert(kyoten, {
			id = item.id,
			honjin = item.honjin,
			gun = item.gun,
			center = { round(position.X), round(position.Y), round(position.Z) },
			size = { round(item.size.X), round(item.size.Z) },
		})
	end
	local tsunagari = {}
	for _, item in loaded.tsunagari do
		table.insert(tsunagari, { pair = `{item.kyotenA}-{item.kyotenB}`, keiyuten = #item.keiyuten })
	end
	local butai = {}
	for _, item in loaded.butai do
		table.insert(butai, {
			id = item.id,
			gun = item.gun,
			jonin = item.jonin,
			hoshin = item.hoshin,
			kyoten = item.kyoten,
			heisu = Haichi.heisuOf(loaded.stageId, item.id),
		})
	end
	return {
		stageId = loaded.stageId,
		kyoten = kyoten,
		tsunagari = tsunagari,
		butai = butai,
		shuryo = loaded.shuryo,
		warnings = loaded.warnings,
	}
end

local function registerDebugCommands()
	DebugCommand.register(
		"PlaceShikenMejirushi",
		"[ステージ ID]",
		"試験用ステージの拠点とつながりの目印を、構成の位置からテストプレイ中だけ作り直す（既定は Test）",
		function(stageId)
			local id = if type(stageId) == "string" then stageId else "Test"
			if not HaichiService.placeShikenMejirushi(id) then
				return `{id} の目印を作れなかった（警告を見る）`
			end
			return `{id} の目印を作った`
		end
	)
	DebugCommand.register(
		"DumpHaichi",
		"<ステージ ID>",
		"ステージの配置を構成と目印から読み込み、拠点・つながり・部隊・首領を JSON で返す",
		function(stageId)
			if type(stageId) ~= "string" then
				error("ステージ ID を指定する", 0)
			end
			local loaded = HaichiService.load(stageId)
			if not loaded then
				return `{stageId} の配置を読み込めなかった（警告を見る）`
			end
			return HttpService:JSONEncode(summarize(loaded))
		end
	)
end

function HaichiService.start()
	registerDebugCommands()
end

return HaichiService
