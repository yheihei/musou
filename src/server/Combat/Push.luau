--!strict
-- プレイヤーのキャラクターを、サーバーから拘束（LinearVelocity）で動かす。攻撃の前進量、緊急回避、
-- ジャンプ攻撃の落下に使う。
-- キャラクターの物理の持ち主はクライアントなので、速さを直接書かずに拘束を置き、クライアントの物理で動かす。
-- 水平に動かすときは上下の速さを縛らないので、落下とジャンプはそのまま続く。
--
-- 拘束を置く Attachment（名前 Push）の Attribute の Duration に動かす秒数を書く。
-- クライアントの PushController が、届いてから Duration 秒で外す（複製の遅れで動く時間がぶれないため）。
-- サーバーは Duration に余裕を足した秒数で消す。

local Debris = game:GetService("Debris")

local Push = {}

local NAME = "Push"
-- 動かす時間の下限（秒）
local MIN_DURATION = 0.05
-- サーバーで消すまでに Duration へ足す秒数。クライアントに届くまでの遅れより長くする
local SERVER_MARGIN = 0.5
-- 拘束の力の上限。上限が無いと、地面や壁へ押し付けたときに跳ね返って吹き飛ぶ
local MAX_FORCE = 20000

-- 動かしている拘束を外す
function Push.stop(root: BasePart)
	local attachment = root:FindFirstChild(NAME)
	if attachment then
		attachment:Destroy()
	end
end

-- 拘束を Attachment の子に置いて root に付ける。Attachment ごと消す
local function attach(root: BasePart, constraint: LinearVelocity, seconds: number)
	local attachment = Instance.new("Attachment")
	attachment.Name = NAME
	attachment:SetAttribute("Duration", seconds)
	constraint.Attachment0 = attachment
	constraint.RelativeTo = Enum.ActuatorRelativeTo.World
	constraint.MaxForce = MAX_FORCE
	constraint.Parent = attachment
	attachment.Parent = root
	Debris:AddItem(attachment, seconds + SERVER_MARGIN)
end

-- root を水平の向き direction へ、duration 秒で distance スタッド動かす。前の動きは止める
function Push.move(root: BasePart, direction: Vector3, distance: number, duration: number)
	Push.stop(root)
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if distance <= 0 or flat.Magnitude < 1e-6 then
		return
	end
	local seconds = math.max(duration, MIN_DURATION)
	local velocity = flat.Unit * (distance / seconds)
	local constraint = Instance.new("LinearVelocity")
	constraint.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	constraint.PrimaryTangentAxis = Vector3.xAxis
	constraint.SecondaryTangentAxis = Vector3.zAxis
	constraint.PlaneVelocity = Vector2.new(velocity.X, velocity.Z)
	attach(root, constraint, seconds)
end

-- root を duration 秒、speed スタッド/秒で真下へ落とす（ジャンプ攻撃の叩きつけ）。水平の動きは縛らない
function Push.fall(root: BasePart, speed: number, duration: number)
	Push.stop(root)
	if speed <= 0 then
		return
	end
	local constraint = Instance.new("LinearVelocity")
	constraint.VelocityConstraintMode = Enum.VelocityConstraintMode.Line
	constraint.LineDirection = Vector3.new(0, -1, 0)
	constraint.LineVelocity = speed
	attach(root, constraint, math.max(duration, MIN_DURATION))
end

return Push
