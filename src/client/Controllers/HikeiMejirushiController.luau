--!strict
-- 落石地点と大火計地域の仮の目印を出す。落石地点には旗と名前、大火計地域には地面の枠と名前を出す。
-- 目印のパーツ（タグ Mejirushi。サーバーが透明にする）を CollectionService で見つけ、自分の画面にだけ見た目のパーツを作る。
-- 目印は区画の目印のフォルダの RakusekiChiten・DaikakeiChiiki の下にある（ADR 0006、ReplicatedStorage.Shared.Mejirushi）。
-- 見た目のパーツは当たり判定・接触・空間クエリの対象にしない。本番の見た目は落石（#114）と大火計（#104）で作る。
--
-- - 目印が読み込まれたら作り、読み込みから外れたか消えたら片付ける（StreamingEnabled）

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Mejirushi = require(ReplicatedStorage.Shared.Mejirushi)
local Ui = require(script.Parent.Parent.Ui)

local HikeiMejirushiController = {}

-- 旗の竿の高さと太さ、布の大きさ（スタッド）
local POLE_HEIGHT = 12
local POLE_WIDTH = 0.5
local CLOTH_SIZE = Vector3.new(5, 3, 0.2)
-- 大火計地域の枠の太さと高さ（スタッド）
local FRAME_THICKNESS = 0.8
local FRAME_HEIGHT = 0.4

local POLE_COLOR = Color3.fromRGB(90, 60, 35)
local CLOTH_COLOR = Color3.fromRGB(240, 200, 80)
local FRAME_COLOR = Color3.fromRGB(240, 90, 30)

-- 目印のパーツから、作った見た目のモデルを引く
local displays: { [BasePart]: Model } = {}
local container: Folder

local function piece(name: string, size: Vector3, cframe: CFrame, color: Color3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Parent = parent
	return part
end

local function label(text: string, adornee: BasePart, height: number)
	local billboard = Ui.create("BillboardGui", {
		Name = "Label",
		Adornee = adornee,
		Size = UDim2.fromOffset(140, 32),
		StudsOffsetWorldSpace = Vector3.new(0, height, 0),
		MaxDistance = 250,
		Parent = adornee,
	}, {
		Ui.text({
			Name = "Text",
			Size = UDim2.fromScale(1, 1),
			Font = Ui.Font.Bold,
			TextScaled = true,
			TextStrokeTransparency = 0.3,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = text,
		}),
	})
	return billboard
end

-- 目印のパーツの下面（地面）の高さ
local function groundCFrame(marker: BasePart): CFrame
	return marker.CFrame * CFrame.new(0, -marker.Size.Y / 2, 0)
end

-- 落石地点の旗。竿を地面に立て、上に布と名前を付ける
local function buildFlag(marker: BasePart): Model
	local model = Instance.new("Model")
	model.Name = `Rakuseki_{marker.Name}`
	local base = groundCFrame(marker).Position
	local pole = piece(
		"Pole",
		Vector3.new(POLE_WIDTH, POLE_HEIGHT, POLE_WIDTH),
		CFrame.new(base + Vector3.new(0, POLE_HEIGHT / 2, 0)),
		POLE_COLOR,
		model
	)
	piece(
		"Cloth",
		CLOTH_SIZE,
		CFrame.new(base + Vector3.new(CLOTH_SIZE.X / 2 + POLE_WIDTH / 2, POLE_HEIGHT - CLOTH_SIZE.Y / 2, 0)),
		CLOTH_COLOR,
		model
	)
	label(`落石 {marker.Name}`, pole, POLE_HEIGHT / 2 + 2)
	return model
end

-- 大火計地域の枠。目印の範囲の縁に沿って地面に4本の帯を置き、真ん中に名前を出す
local function buildFrame(marker: BasePart): Model
	local model = Instance.new("Model")
	model.Name = `Daikakei_{marker.Name}`
	local ground = groundCFrame(marker) * CFrame.new(0, FRAME_HEIGHT / 2, 0)
	local sizeX, sizeZ = marker.Size.X, marker.Size.Z
	local center =
		piece("Center", Vector3.new(FRAME_THICKNESS, FRAME_HEIGHT, FRAME_THICKNESS), ground, FRAME_COLOR, model)
	center.Transparency = 1
	for _, side in { -1, 1 } do
		piece(
			if side < 0 then "North" else "South",
			Vector3.new(sizeX, FRAME_HEIGHT, FRAME_THICKNESS),
			ground * CFrame.new(0, 0, side * sizeZ / 2),
			FRAME_COLOR,
			model
		)
		piece(
			if side < 0 then "West" else "East",
			Vector3.new(FRAME_THICKNESS, FRAME_HEIGHT, sizeZ),
			ground * CFrame.new(side * sizeX / 2, 0, 0),
			FRAME_COLOR,
			model
		)
	end
	label(`大火計 {marker.Name}`, center, 4)
	return model
end

local function remove(instance: Instance)
	if not instance:IsA("BasePart") then
		return
	end
	local display = displays[instance]
	if display then
		displays[instance] = nil
		display:Destroy()
	end
end

local function add(instance: Instance)
	if not instance:IsA("BasePart") or displays[instance] then
		return
	end
	local parent = instance.Parent
	local kind = if parent then parent.Name else nil
	local display: Model? = nil
	if kind == Mejirushi.RAKUSEKI_CHITEN then
		display = buildFlag(instance)
	elseif kind == Mejirushi.DAIKAKEI_CHIIKI then
		display = buildFrame(instance)
	end
	if display then
		displays[instance] = display
		display.Parent = container
	end
end

function HikeiMejirushiController.start()
	local folder = Instance.new("Folder")
	folder.Name = "HikeiMejirushi"
	folder.Parent = workspace
	container = folder

	CollectionService:GetInstanceAddedSignal(Mejirushi.TAG):Connect(add)
	CollectionService:GetInstanceRemovedSignal(Mejirushi.TAG):Connect(remove)
	for _, instance in CollectionService:GetTagged(Mejirushi.TAG) do
		add(instance)
	end
end

return HikeiMejirushiController
