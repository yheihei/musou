--!strict
-- 仮エフェクト。本番アセットに差し替えるまでの目印として半透明パーツを一瞬出す。

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local HitShape = require(ReplicatedStorage.Shared.HitShape)

local Vfx = {}

-- 扇を描く板の間隔（度）
local SECTOR_STEP = 20
-- 飛び道具の大きさ（スタッド）
local PROJECTILE_SIZE = Vector3.new(1.4, 0.2, 1.4)
-- 炎の塊の数と色
local FLAME_COUNT = 7
local FLAME_COLORS = {
	Color3.fromRGB(255, 90, 30),
	Color3.fromRGB(255, 160, 40),
	Color3.fromRGB(255, 220, 90),
}

local function flash(part: BasePart, lifetime: number)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Material = Enum.Material.Neon
	part.Transparency = 0.4
	part.Parent = workspace
	Debris:AddItem(part, lifetime)
end

-- 原点から direction の向きに length だけ延びる板
local function bar(from: Vector3, direction: Vector3, length: number, width: number, color: Color3)
	local center = from + direction * (length / 2)
	local part = Instance.new("Part")
	part.Size = Vector3.new(width, 0.4, length)
	part.CFrame = CFrame.lookAt(center, center + direction)
	part.Color = color
	flash(part, 0.12)
end

function Vfx.ring(center: Vector3, radius: number, color: Color3)
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(0.4, radius * 2, radius * 2)
	part.CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90))
	part.Color = color
	flash(part, 0.18)
end

-- 原点の向きの水平成分
local function forwardOf(origin: HitShape.Origin): Vector3
	local flat = Vector3.new(origin.look.X, 0, origin.look.Z)
	return if flat.Magnitude > 1e-6 then flat.Unit else Vector3.new(0, 0, -1)
end

-- 判定の形に合わせた仮エフェクト。直線は飛び道具が前へ飛ぶ
function Vfx.shape(shape: HitShape.Shape, origin: HitShape.Origin, color: Color3)
	local position: Vector3 = origin.position
	local forward = forwardOf(origin)

	if shape.kind == "Box" then
		bar(position, forward, shape.range, shape.width, color)
	elseif shape.kind == "Sphere" then
		Vfx.ring(position, shape.radius, color)
	elseif shape.kind == "Sector" then
		local steps = math.max(math.ceil(shape.angle / SECTOR_STEP), 2)
		for i = 0, steps do
			local angle = math.rad(-shape.angle / 2 + shape.angle * i / steps)
			local direction = CFrame.fromAxisAngle(Vector3.yAxis, angle):VectorToWorldSpace(forward)
			bar(position, direction, shape.radius, 0.6, color)
		end
	else
		local projectile = Instance.new("Part")
		projectile.Size = PROJECTILE_SIZE
		projectile.CFrame = CFrame.lookAt(position, position + forward)
		projectile.Color = color
		local seconds = shape.length / shape.speed
		flash(projectile, seconds)
		TweenService:Create(projectile, TweenInfo.new(seconds, Enum.EasingStyle.Linear), {
			CFrame = CFrame.lookAt(position + forward * shape.length, position + forward * (shape.length + 1))
				* CFrame.Angles(0, math.rad(720), 0),
		}):Play()
	end
end

-- 炎の仮エフェクト。扇の中に炎の塊を散らす。扇でない形は形のとおりに描く
function Vfx.flame(shape: HitShape.Shape, origin: HitShape.Origin)
	if shape.kind ~= "Sector" then
		Vfx.shape(shape, origin, FLAME_COLORS[1])
		return
	end
	local position: Vector3 = origin.position
	local forward = forwardOf(origin)
	for _ = 1, FLAME_COUNT do
		local angle = math.rad((math.random() - 0.5) * shape.angle)
		local distance = shape.radius * (0.3 + 0.7 * math.random())
		local direction = CFrame.fromAxisAngle(Vector3.yAxis, angle):VectorToWorldSpace(forward)
		local size = 2 + distance * 0.25
		local part = Instance.new("Part")
		part.Shape = Enum.PartType.Ball
		part.Size = Vector3.new(size, size, size)
		part.CFrame = CFrame.new(position + direction * distance)
		part.Color = FLAME_COLORS[math.random(1, #FLAME_COLORS)]
		local fire = Instance.new("Fire")
		fire.Size = size * 1.5
		fire.Heat = 8
		fire.Parent = part
		flash(part, 0.2)
	end
end

function Vfx.hit(model: Model)
	local highlight = Instance.new("Highlight")
	highlight.FillColor = Color3.new(1, 1, 1)
	highlight.FillTransparency = 0.3
	highlight.OutlineTransparency = 1
	highlight.Parent = model
	Debris:AddItem(highlight, 0.08)
end

return Vfx
