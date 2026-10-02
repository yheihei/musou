--!strict
-- ステージの配置を、構成（ReplicatedStorage.Shared.Haichi）とプレースの目印から読み込む（ADR 0006）。
-- 拠点の目印は <区画>.Mejirushi.Kyoten の下に拠点 ID の名前で、つながりの道筋は <区画>.Mejirushi.Tsunagari の下の
-- フォルダ（Attribute の KyotenA・KyotenB）に経由点 1、2… を置く。構成と目印の食い違いは警告を出す。
--
-- - 構成にあって目印が無い拠点は読み込まない。目印が無いつながりは、拠点の間をまっすぐ結ぶ
-- - 試験用ステージの目印は構成に位置を持ち、テストプレイ中に作る（プレースには保存しない）。
--   目印が無ければ読み込むときに作り、窓口の PlaceShikenMejirushi でも作り直せる。
--   イベントシーンのカメラと役者の目印（<区画>.Mejirushi.EventScene）も一緒に作る
-- - 首領は Stages.luau の両軍の首領を、その軍の本陣から出す
-- - 落石地点と大火計地域は目印だけで完結させる（<区画>.Mejirushi.RakusekiChiten・DaikakeiChiiki）。
--   出撃したときに出撃したステージの区画の目印だけを読み、参照する拠点とつながりを構成と突き合わせて警告を出す。
--   使えない地点（ID の重複、無い拠点、結ばれていない区間）は読み込まない。目印は透明にし、当たり判定・接触・空間クエリから外す
-- - 秘計の発動者から Config.luau の距離（Hikei 節の TargetRange）以内で一番近い落石地点と大火計地域を返す

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Colors = require(ReplicatedStorage.Shared.Colors)
local Gun = require(ReplicatedStorage.Shared.Gun)
local Ground = require(ReplicatedStorage.Shared.Ground)
local Haichi = require(ReplicatedStorage.Shared.Haichi)
local Hikei = require(ReplicatedStorage.Shared.Hikei)
local Mejirushi = require(ReplicatedStorage.Shared.Mejirushi)
local StagePhase = require(ReplicatedStorage.Shared.StagePhase)
local Stages = require(ReplicatedStorage.Shared.Stages)
local DebugCommand = require(script.Parent.Parent.DebugCommand)
local KukakuService = require(script.Parent.KukakuService)
local StageService = require(script.Parent.StageService)

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

export type LoadedRakuseki = {
	id: string,
	-- 塞ぐ区間（つながり）の両端の拠点 ID
	kyotenA: string,
	kyotenB: string,
	-- 岩を落とす位置
	position: Vector3,
}

export type LoadedDaikakei = {
	id: string,
	-- 範囲の中心と向き、大きさ
	cframe: CFrame,
	size: Vector3,
}

export type LoadedHikeiMejirushi = {
	stageId: string,
	rakuseki: { LoadedRakuseki },
	daikakei: { LoadedDaikakei },
	-- 使えない地点（警告に出したもの）
	warnings: { string },
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
-- 試験用ステージの落石地点の目印の大きさと、大火計地域の目印の厚み（スタッド）
local RAKUSEKI_SIZE = 4
local DAIKAKEI_THICKNESS = 2
local RAKUSEKI_COLOR = Color3.fromRGB(150, 110, 70)
local DAIKAKEI_COLOR = Color3.fromRGB(230, 90, 30)
-- 試験用ステージのイベントシーンのカメラと役者の目印の大きさ（スタッド）
local CAMERA_SIZE = Vector3.new(1, 1, 2)
local YAKUSHA_SIZE = Vector3.new(2, 5, 1)
local CAMERA_COLOR = Color3.fromRGB(80, 200, 240)
local YAKUSHA_COLOR = Color3.fromRGB(240, 240, 120)

-- 出撃しているステージの落石地点と大火計地域。ロビーでは nil
local currentHikei: LoadedHikeiMejirushi? = nil

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
	for _, name in
		{
			Mejirushi.KYOTEN,
			Mejirushi.TSUNAGARI,
			Mejirushi.RAKUSEKI_CHITEN,
			Mejirushi.DAIKAKEI_CHIIKI,
			Mejirushi.EVENT_SCENE,
		}
	do
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
	local rakusekiFolder = Instance.new("Folder")
	rakusekiFolder.Name = Mejirushi.RAKUSEKI_CHITEN
	for _, chiten in mejirushi.rakusekiChiten do
		local ground = groundPoint(center, chiten.x, chiten.z)
		local part = makeMarker(
			chiten.id,
			Vector3.one * RAKUSEKI_SIZE,
			CFrame.new(ground + Vector3.new(0, RAKUSEKI_SIZE / 2, 0)),
			RAKUSEKI_COLOR,
			rakusekiFolder
		)
		part:SetAttribute(Mejirushi.KYOTEN_A, chiten.kyotenA)
		part:SetAttribute(Mejirushi.KYOTEN_B, chiten.kyotenB)
	end
	local daikakeiFolder = Instance.new("Folder")
	daikakeiFolder.Name = Mejirushi.DAIKAKEI_CHIIKI
	for _, chiiki in mejirushi.daikakeiChiiki do
		local ground = groundPoint(center, chiiki.x, chiiki.z)
		makeMarker(
			chiiki.id,
			Vector3.new(chiiki.sizeX, DAIKAKEI_THICKNESS, chiiki.sizeZ),
			CFrame.new(ground + Vector3.new(0, DAIKAKEI_THICKNESS / 2, 0)),
			DAIKAKEI_COLOR,
			daikakeiFolder
		)
	end
	local eventSceneFolder = Instance.new("Folder")
	eventSceneFolder.Name = Mejirushi.EVENT_SCENE
	for sceneId, scene in mejirushi.eventScene or {} do
		local sceneFolder = Instance.new("Folder")
		sceneFolder.Name = sceneId
		local cameraFolder = Instance.new("Folder")
		cameraFolder.Name = Mejirushi.CAMERA
		for name, shot in scene.camera do
			local position = groundPoint(center, shot.x, shot.z) + Vector3.new(0, shot.y, 0)
			local look = groundPoint(center, shot.lookX, shot.lookZ) + Vector3.new(0, shot.lookY, 0)
			makeMarker(name, CAMERA_SIZE, CFrame.lookAt(position, look), CAMERA_COLOR, cameraFolder)
		end
		local yakushaFolder = Instance.new("Folder")
		yakushaFolder.Name = Mejirushi.YAKUSHA
		for name, ichi in scene.yakusha do
			local standing = groundPoint(center, ichi.x, ichi.z) + Vector3.new(0, YAKUSHA_SIZE.Y / 2, 0)
			local facingX, facingZ = Haichi.facingOf(ichi.facing)
			makeMarker(
				name,
				YAKUSHA_SIZE,
				CFrame.lookAt(standing, standing + Vector3.new(facingX, 0, facingZ)),
				YAKUSHA_COLOR,
				yakushaFolder
			)
		end
		cameraFolder.Parent = sceneFolder
		yakushaFolder.Parent = sceneFolder
		sceneFolder.Parent = eventSceneFolder
	end
	kyotenFolder.Parent = folder
	tsunagariFolder.Parent = folder
	rakusekiFolder.Parent = folder
	daikakeiFolder.Parent = folder
	eventSceneFolder.Parent = folder
	return true
end

-- 目印のパーツを、透明（KukakuService がタグで透明にする）で当たり判定・接触・空間クエリの外に置き直す
local function settleMarker(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	if not CollectionService:HasTag(part, Mejirushi.TAG) then
		CollectionService:AddTag(part, Mejirushi.TAG)
	end
end

-- 目印のフォルダの下のパーツを名前の順に返す
local function markerParts(folder: Instance?): { BasePart }
	local parts = {}
	for _, child in if folder then folder:GetChildren() else {} do
		if child:IsA("BasePart") then
			table.insert(parts, child)
		end
	end
	table.sort(parts, function(a, b)
		return a.Name < b.Name
	end)
	return parts
end

-- ステージの落石地点と大火計地域を、出撃したステージの区画の目印だけから読み込む。
-- 構成と突き合わせて使えない地点は外し、警告を出す。構成か区画が無いステージでは nil（警告は出さない）
function HaichiService.loadHikeiMejirushi(stageId: string): LoadedHikeiMejirushi?
	local stage = Stages.get(stageId)
	local haichi = Haichi.get(stageId)
	if not stage or not haichi then
		return nil
	end
	local folder = KukakuService.mejirushiOf(stage.kukaku)
	if not folder then
		return nil
	end
	if haichi.shikenMejirushi and not folder:FindFirstChild(Mejirushi.RAKUSEKI_CHITEN) then
		HaichiService.placeShikenMejirushi(stageId)
	end
	local where = `ステージ {stageId} の`
	local loaded: LoadedHikeiMejirushi = { stageId = stageId, rakuseki = {}, daikakei = {}, warnings = {} }

	local rakusekiParts = markerParts(folder:FindFirstChild(Mejirushi.RAKUSEKI_CHITEN))
	local rakusekiMarks: { Haichi.RakusekiMejirushi } = {}
	for _, part in rakusekiParts do
		settleMarker(part)
		local kyotenA = part:GetAttribute(Mejirushi.KYOTEN_A)
		local kyotenB = part:GetAttribute(Mejirushi.KYOTEN_B)
		table.insert(rakusekiMarks, {
			id = part.Name,
			kyotenA = if type(kyotenA) == "string" then kyotenA else nil,
			kyotenB = if type(kyotenB) == "string" then kyotenB else nil,
		})
	end
	local usableRakuseki, rakusekiProblems = Haichi.checkRakusekiChiten(haichi, rakusekiMarks)
	for index, mark in rakusekiMarks do
		if usableRakuseki[mark.id] then
			usableRakuseki[mark.id] = nil
			table.insert(loaded.rakuseki, {
				id = mark.id,
				kyotenA = mark.kyotenA :: string,
				kyotenB = mark.kyotenB :: string,
				position = rakusekiParts[index].Position,
			})
		end
	end

	local daikakeiParts = markerParts(folder:FindFirstChild(Mejirushi.DAIKAKEI_CHIIKI))
	local daikakeiIds = {}
	for _, part in daikakeiParts do
		settleMarker(part)
		table.insert(daikakeiIds, part.Name)
	end
	local usableDaikakei, daikakeiProblems = Haichi.checkDaikakeiChiiki(daikakeiIds)
	for _, part in daikakeiParts do
		if usableDaikakei[part.Name] then
			usableDaikakei[part.Name] = nil
			table.insert(loaded.daikakei, { id = part.Name, cframe = part.CFrame, size = part.Size })
		end
	end

	for _, problems in { rakusekiProblems, daikakeiProblems } do
		for _, message in problems do
			table.insert(loaded.warnings, message)
			warn(`HaichiService: {where}秘計の目印: {message}`)
		end
	end
	return loaded
end

-- 出撃しているステージの落石地点と大火計地域。ロビーでは nil
function HaichiService.getHikeiMejirushi(): LoadedHikeiMejirushi?
	return currentHikei
end

-- 出撃しているステージの落石地点のうち、position から距離の上限（Config.luau の Hikei 節の TargetRange.Rakuseki）以内で
-- 一番近いもの。無ければ nil
function HaichiService.nearestRakusekiChiten(position: Vector3): LoadedRakuseki?
	local current = currentHikei
	if not current then
		return nil
	end
	local candidates = {}
	for _, chiten in current.rakuseki do
		local dx, dz = chiten.position.X - position.X, chiten.position.Z - position.Z
		table.insert(candidates, { id = chiten.id, distance = math.sqrt(dx * dx + dz * dz) })
	end
	local id = Hikei.nearest(candidates, Hikei.targetRangeOf("Rakuseki") or 0)
	for _, chiten in current.rakuseki do
		if chiten.id == id then
			return chiten
		end
	end
	return nil
end

-- 出撃しているステージの大火計地域のうち、position から距離の上限（TargetRange.Daikakei）以内で一番近いもの。
-- 距離は地域の縁までで、地域の中なら 0。無ければ nil
function HaichiService.nearestDaikakeiChiiki(position: Vector3): LoadedDaikakei?
	local current = currentHikei
	if not current then
		return nil
	end
	local candidates = {}
	for _, chiiki in current.daikakei do
		local offset = chiiki.cframe:PointToObjectSpace(position)
		table.insert(
			candidates,
			{ id = chiiki.id, distance = Hikei.distanceToArea(offset.X, offset.Z, chiiki.size.X, chiiki.size.Z) }
		)
	end
	local id = Hikei.nearest(candidates, Hikei.targetRangeOf("Daikakei") or 0)
	for _, chiiki in current.daikakei do
		if chiiki.id == id then
			return chiiki
		end
	end
	return nil
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

local function describeHikei(loaded: LoadedHikeiMejirushi): { [string]: any }
	local rakuseki = {}
	for _, chiten in loaded.rakuseki do
		table.insert(rakuseki, {
			id = chiten.id,
			kukan = `{chiten.kyotenA}-{chiten.kyotenB}`,
			position = { round(chiten.position.X), round(chiten.position.Y), round(chiten.position.Z) },
		})
	end
	local daikakei = {}
	for _, chiiki in loaded.daikakei do
		local position = chiiki.cframe.Position
		table.insert(daikakei, {
			id = chiiki.id,
			center = { round(position.X), round(position.Y), round(position.Z) },
			size = { round(chiiki.size.X), round(chiiki.size.Z) },
		})
	end
	return { stageId = loaded.stageId, rakuseki = rakuseki, daikakei = daikakei, warnings = loaded.warnings }
end

local function registerDebugCommands()
	DebugCommand.register(
		"DumpHikeiMejirushi",
		"[ステージ ID]",
		"落石地点と大火計地域を JSON で返す（ステージ ID を省くと、出撃しているステージの読み込み済みのもの）",
		function(stageId)
			local loaded = if type(stageId) == "string" then HaichiService.loadHikeiMejirushi(stageId) else currentHikei
			if not loaded then
				return "落石地点と大火計地域を読み込めなかった（出撃していないか、配置の構成が無い）"
			end
			return HttpService:JSONEncode(describeHikei(loaded))
		end
	)
	DebugCommand.register(
		"FindHikeiChiten",
		"<プレイヤー名>",
		"プレイヤーから距離の上限以内で一番近い落石地点と大火計地域を返す（出撃しているステージ）",
		function(name)
			local player = DebugCommand.findPlayer(name)
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not root then
				return `{player.Name} のキャラクターがいない`
			end
			if not currentHikei then
				return "出撃していないか、出撃したステージに配置の構成が無い"
			end
			local rakuseki = HaichiService.nearestRakusekiChiten(root.Position)
			local daikakei = HaichiService.nearestDaikakeiChiiki(root.Position)
			local position = root.Position
			return HttpService:JSONEncode({
				position = { round(position.X), round(position.Y), round(position.Z) },
				rakuseki = if rakuseki then rakuseki.id else nil,
				daikakei = if daikakei then daikakei.id else nil,
			})
		end
	)
	DebugCommand.register(
		"PlaceShikenMejirushi",
		"[ステージ ID]",
		"試験用ステージの拠点・つながり・落石地点・大火計地域の目印を、構成の位置からテストプレイ中だけ作り直す（既定は Test）",
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
	-- 出撃したステージの区画の落石地点と大火計地域を読み、ロビーへ戻ったら手放す
	StageService.started:Connect(function(info: StageService.StartInfo)
		currentHikei = HaichiService.loadHikeiMejirushi(info.stageId)
	end)
	StageService.phaseChanged:Connect(function(next: StagePhase.Phase)
		if next == "Lobby" then
			currentHikei = nil
		end
	end)
end

return HaichiService
