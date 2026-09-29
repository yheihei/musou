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

-- 判定の形に合わせた仮エフェクト。直線は飛び道具が前へ飛ぶ
function Vfx.shape(shape: HitShape.Shape, origin: HitShape.Origin, color: Color3)
	local position: Vector3 = origin.position
	local flat = Vector3.new(origin.look.X, 0, origin.look.Z)
	local forward = if flat.Magnitude > 1e-6 then flat.Unit else Vector3.new(0, 0, -1)

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

function Vfx.hit(model: Model)
	local highlight = Instance.new("Highlight")
	highlight.FillColor = Color3.new(1, 1, 1)
	highlight.FillTransparency = 0.3
	highlight.OutlineTransparency = 1
	highlight.Parent = model
	Debris:AddItem(highlight, 0.08)
end

return Vfx
