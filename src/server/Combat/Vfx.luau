--!strict
-- 仮エフェクト。本番アセットに差し替えるまでの目印として半透明パーツを一瞬出す。
-- 上忍と首領の型の予備動作（地面に描く判定の範囲と、体の光）も、予備動作の間だけ出す。
-- パーツはどれも固定し、当たり判定・接触・空間クエリから外す（プレイヤーにも個体にも当たらない）。

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Ground = require(ReplicatedStorage.Shared.Ground)
local HitShape = require(ReplicatedStorage.Shared.HitShape)

local Vfx = {}

-- 扇を描く板の間隔（度）
local SECTOR_STEP = 20
-- 飛び道具の大きさ（スタッド）
local PROJECTILE_SIZE = Vector3.new(1.4, 0.2, 1.4)
-- 金属の刃の色・太さ・高さの範囲・並べる間隔（スタッド）・突き出す秒数・残す秒数
local BLADE_COLOR = Color3.fromRGB(200, 200, 215)
local BLADE_WIDTH = 0.8
local BLADE_MIN_HEIGHT = 3
local BLADE_MAX_HEIGHT = 6
local BLADE_SPACING = 2.5
local BLADE_RISE_TIME = 0.1
local BLADE_LIFETIME = 0.5
-- 刃を出す地面が見つからないとき、判定の原点から下げる高さ（スタッド）
local BLADE_FALLBACK_DROP = 3
-- 予備動作で地面に描く判定の範囲の板の厚み・地面から浮かせる高さ（スタッド）・透明度
local AREA_THICKNESS = 0.2
local AREA_LIFT = 0.15
local AREA_TRANSPARENCY = 0.55
-- 予備動作で扇と輪の範囲を描く棒の間隔（度）と太さ（スタッド）
local AREA_STEP = 10
local AREA_BAR_WIDTH = 0.5
-- 予備動作で光らせる体の塗りの透明度
local GLOW_FILL_TRANSPARENCY = 0.45
-- 斬撃の色・長さ・太さ（スタッド）・体の中心から正面へ離す距離（スタッド）・傾き（度）・残す秒数
-- （交戦の前線の下忍の攻撃の動作。モーションが無い間の仮の見た目）
local SLASH_COLOR = Color3.fromRGB(235, 235, 245)
local SLASH_LENGTH = 3
local SLASH_WIDTH = 0.25
local SLASH_FORWARD = 2
local SLASH_TILT = 40
local SLASH_LIFETIME = 0.15
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
	elseif shape.kind == "Ring" then
		Vfx.ring(position, shape.outer, color)
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

-- 予備動作の範囲の板を1枚置く。lifetime 秒で消える
local function plate(size: Vector3, cframe: CFrame, color: Color3, lifetime: number, shape: Enum.PartType?): BasePart
	local part = Instance.new("Part")
	part.Shape = shape or Enum.PartType.Block
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.CastShadow = false
	flash(part, lifetime)
	part.Transparency = AREA_TRANSPARENCY
	return part
end

-- 判定の範囲を地面に描く（上忍と首領の型の予備動作）。高さ groundY の地面に薄い板で描き、lifetime 秒で消す。
-- 箱と直線は前へ延びる板、球と周り全体の扇は円板、扇は原点から放射状の棒、輪は内側から外側への棒で描く。描いた板を返す
function Vfx.area(
	shape: HitShape.Shape,
	origin: HitShape.Origin,
	groundY: number,
	color: Color3,
	lifetime: number
): { BasePart }
	local position: Vector3 = origin.position
	local center = Vector3.new(position.X, groundY + AREA_LIFT, position.Z)
	local forward = forwardOf(origin)
	local parts: { BasePart } = {}
	-- from から direction の向きに length だけ延びる板
	local function strip(from: Vector3, direction: Vector3, length: number, width: number)
		local middle = from + direction * (length / 2)
		local size = Vector3.new(width, AREA_THICKNESS, length)
		table.insert(parts, plate(size, CFrame.lookAt(middle, middle + direction), color, lifetime))
	end
	local function disc(radius: number)
		local size = Vector3.new(AREA_THICKNESS, radius * 2, radius * 2)
		local cframe = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90))
		table.insert(parts, plate(size, cframe, color, lifetime, Enum.PartType.Cylinder))
	end
	-- 原点の周りの from 度から to 度まで、inner から outer までの棒を並べる
	local function spokes(from: number, to: number, inner: number, outer: number)
		local steps = math.max(math.ceil((to - from) / AREA_STEP), 1)
		local length = math.max(outer - inner, AREA_BAR_WIDTH)
		for index = 0, steps do
			local angle = math.rad(from + (to - from) * index / steps)
			local direction = CFrame.fromAxisAngle(Vector3.yAxis, angle):VectorToWorldSpace(forward)
			strip(center + direction * inner, direction, length, AREA_BAR_WIDTH)
		end
	end

	if shape.kind == "Box" then
		strip(center, forward, shape.range, shape.width)
	elseif shape.kind == "Line" then
		strip(center, forward, shape.length, shape.width)
	elseif shape.kind == "Ring" then
		if shape.inner <= 0 then
			disc(shape.outer)
		else
			spokes(0, 360 - AREA_STEP, shape.inner, shape.outer)
		end
	elseif shape.kind == "Sector" and shape.angle < 360 then
		spokes(-shape.angle / 2, shape.angle / 2, 0, shape.radius)
	else
		-- 球と、周り全体の扇
		disc(shape.radius)
	end
	return parts
end

-- 体を光らせる（上忍と首領の型の予備動作）。lifetime 秒で消す。付けた Highlight を返す
function Vfx.glow(model: Model, color: Color3, lifetime: number): Highlight
	local highlight = Instance.new("Highlight")
	highlight.FillColor = color
	highlight.FillTransparency = GLOW_FILL_TRANSPARENCY
	highlight.OutlineColor = color
	highlight.OutlineTransparency = 0
	highlight.Parent = model
	Debris:AddItem(highlight, lifetime)
	return highlight
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

-- 金属の刃の仮エフェクト（金遁）。輪の内側と外側の半径の間に、地面から刃を突き出す。輪でない形は形のとおりに描く
function Vfx.blades(shape: HitShape.Shape, origin: HitShape.Origin)
	if shape.kind ~= "Ring" then
		Vfx.shape(shape, origin, BLADE_COLOR)
		return
	end
	local position: Vector3 = origin.position
	local middle = (shape.inner + shape.outer) / 2
	local count = math.clamp(math.floor(2 * math.pi * math.max(middle, 1) / BLADE_SPACING), 6, 48)
	-- 地面の高さは刃ごとに光線を当てて引く。地面が無ければ警告を出さずに判定の原点の下に置く
	local excluded = Ground.excludedOf()
	for index = 1, count do
		local angle = (index + math.random() * 0.5) * 2 * math.pi / count
		local distance = shape.inner + math.random() * (shape.outer - shape.inner)
		local x = position.X + math.cos(angle) * distance
		local z = position.Z + math.sin(angle) * distance
		local hit = Ground.raycast(Vector3.new(x, position.Y + 5, z), Vector3.new(0, -50, 0), excluded)
		local groundY = if hit then hit.Position.Y else position.Y - BLADE_FALLBACK_DROP
		local height = BLADE_MIN_HEIGHT + math.random() * (BLADE_MAX_HEIGHT - BLADE_MIN_HEIGHT)
		local blade = Instance.new("Part")
		blade.Size = Vector3.new(BLADE_WIDTH, height, BLADE_WIDTH)
		-- 外へ少し傾けて、地面の下から突き出す
		local tilt = CFrame.Angles(0, -angle, 0) * CFrame.Angles(0, 0, math.rad(-12))
		local up = CFrame.new(x, groundY + height / 2, z) * tilt
		blade.CFrame = up - Vector3.new(0, height, 0)
		blade.Color = BLADE_COLOR
		flash(blade, BLADE_LIFETIME)
		blade.Material = Enum.Material.Metal
		blade.Transparency = 0
		TweenService:Create(blade, TweenInfo.new(BLADE_RISE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = up,
		}):Play()
	end
end

-- 斬撃の仮エフェクト（交戦の前線の下忍の攻撃の動作）。体の中心 position から水平の向き look へ少し離した位置に、
-- 斜めの細い板を一瞬出す。見た目だけで、当たり判定は持たない
function Vfx.slash(position: Vector3, look: Vector3)
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-6 then
		return
	end
	local forward = flat.Unit
	local center = position + forward * SLASH_FORWARD
	local part = Instance.new("Part")
	part.Size = Vector3.new(SLASH_LENGTH, SLASH_WIDTH, SLASH_WIDTH)
	-- 正面を向けた横長の板を、正面の軸の周りに傾けて斜めにする
	part.CFrame = CFrame.lookAt(center, center + forward) * CFrame.Angles(0, 0, math.rad(SLASH_TILT))
	part.Color = SLASH_COLOR
	part.CastShadow = false
	flash(part, SLASH_LIFETIME)
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
