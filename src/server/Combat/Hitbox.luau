--!strict
-- 攻撃判定を戦場の対象に当てる。形の計算は ReplicatedStorage.Shared.HitShape が持つ。
-- ここは判定の原点を作り、デバッグ表示がオンなら判定の形を半透明のパーツで描く。

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local HitShape = require(ReplicatedStorage.Shared.HitShape)

local Hitbox = {}

local DEBUG_COLOR = Color3.fromRGB(255, 0, 200)
local DEBUG_TRANSPARENCY = 0.7
-- 扇を描く線の間隔（度）
local SECTOR_STEP = 15

local showShapes = Config.Hitbox.ShowShapes
local shapeLifetime = Config.Hitbox.ShapeLifetime
local debugFolder: Folder? = nil

-- 判定の形のデバッグ表示を切り替える。lifetime を渡すと、その秒数だけ形を残す
function Hitbox.setShowShapes(on: boolean, lifetime: number?)
	showShapes = on
	shapeLifetime = lifetime or Config.Hitbox.ShapeLifetime
end

function Hitbox.isShowingShapes(): boolean
	return showShapes
end

-- root の位置と向きを判定の原点にする
function Hitbox.originOf(root: BasePart): HitShape.Origin
	return { position = root.Position, look = root.CFrame.LookVector }
end

local function getDebugFolder(): Folder
	local folder = debugFolder
	if folder and folder.Parent then
		return folder
	end
	local created = Instance.new("Folder")
	created.Name = "HitboxDebug"
	created.Parent = workspace
	debugFolder = created
	return created
end

local function debugPart(size: Vector3, cframe: CFrame, shape: Enum.PartType?)
	local part = Instance.new("Part")
	part.Shape = shape or Enum.PartType.Block
	part.Size = size
	part.CFrame = cframe
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = DEBUG_COLOR
	part.Transparency = DEBUG_TRANSPARENCY
	part.Parent = getDebugFolder()
	Debris:AddItem(part, shapeLifetime)
end

-- 原点から direction の向きに length だけ延びる棒を描く
local function drawBar(from: Vector3, direction: Vector3, length: number, width: number, height: number)
	local center = from + direction * (length / 2)
	debugPart(Vector3.new(width, height, length), CFrame.lookAt(center, center + direction))
end

local function drawShape(shape: HitShape.Shape, origin: HitShape.Origin)
	local position: Vector3 = origin.position
	local flat = Vector3.new(origin.look.X, 0, origin.look.Z)
	local forward = if flat.Magnitude > 1e-6 then flat.Unit else Vector3.new(0, 0, -1)

	if shape.kind == "Box" then
		drawBar(position, forward, shape.range, shape.width, shape.height)
	elseif shape.kind == "Sphere" then
		local diameter = shape.radius * 2
		debugPart(Vector3.new(diameter, diameter, diameter), CFrame.new(position), Enum.PartType.Ball)
	elseif shape.kind == "Sector" then
		local steps = math.max(math.ceil(shape.angle / SECTOR_STEP), 2)
		for i = 0, steps do
			local angle = math.rad(-shape.angle / 2 + shape.angle * i / steps)
			local direction = CFrame.fromAxisAngle(Vector3.yAxis, angle):VectorToWorldSpace(forward)
			drawBar(position, direction, shape.radius, 0.2, shape.height)
		end
	else
		drawBar(position, forward, shape.length, shape.width, shape.width)
	end
end

-- 形に入った対象を原点に近い順に返す。デバッグ表示がオンなら形を描く
function Hitbox.query<T>(
	shape: HitShape.Shape,
	origin: HitShape.Origin,
	targets: { HitShape.Target<T> }
): { HitShape.Hit<T> }
	if showShapes then
		drawShape(shape, origin)
	end
	return HitShape.query(shape, origin, targets)
end

return Hitbox
