--!strict
-- プレイヤーのキャラクターを、サーバーから拘束（LinearVelocity）で水平に動かす。攻撃の前進量や緊急回避に使う。
-- キャラクターの物理の持ち主はクライアントなので、速さを直接書かずに拘束を置き、クライアントの物理で動かす。
-- 上下の速さは縛らないので、落下とジャンプはそのまま続く。
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

-- 動かしている拘束を外す
function Push.stop(root: BasePart)
	local attachment = root:FindFirstChild(NAME)
	if attachment then
		attachment:Destroy()
	end
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

	-- 拘束は Attachment の子に置き、Attachment ごと消す
	local attachment = Instance.new("Attachment")
	attachment.Name = NAME
	attachment:SetAttribute("Duration", seconds)
	local constraint = Instance.new("LinearVelocity")
	constraint.Attachment0 = attachment
	constraint.RelativeTo = Enum.ActuatorRelativeTo.World
	constraint.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	constraint.PrimaryTangentAxis = Vector3.xAxis
	constraint.SecondaryTangentAxis = Vector3.zAxis
	constraint.PlaneVelocity = Vector2.new(velocity.X, velocity.Z)
	constraint.MaxForce = math.huge
	constraint.Parent = attachment
	attachment.Parent = root
	Debris:AddItem(attachment, seconds + SERVER_MARGIN)
end

return Push
