--!strict
-- 仮エフェクト。本番アセットに差し替えるまでの目印として半透明パーツを一瞬出す。

local Debris = game:GetService("Debris")

local Vfx = {}

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

function Vfx.slash(root: BasePart, range: number, width: number, color: Color3)
	local part = Instance.new("Part")
	part.Size = Vector3.new(width, 0.4, range)
	part.CFrame = root.CFrame * CFrame.new(0, 0, -range / 2)
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

function Vfx.hit(model: Model)
	local highlight = Instance.new("Highlight")
	highlight.FillColor = Color3.new(1, 1, 1)
	highlight.FillTransparency = 0.3
	highlight.OutlineTransparency = 1
	highlight.Parent = model
	Debris:AddItem(highlight, 0.08)
end

return Vfx
