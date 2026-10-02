--!strict
-- 下忍の見本のモデル。案A はこれをサーバーで写し、案B はクライアントが ReplicatedStorage の写しを使う。
-- 見た目は今の EnemyService の下忍と同じ（R15、仮の色）。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Template = {}

-- クライアントが写す見本の名前（ReplicatedStorage の下）
Template.NAME = "ProtoGeninTemplate"

local BODY_COLOR = Color3.fromRGB(70, 90, 160)
local LEG_COLOR = Color3.fromRGB(40, 40, 40)

-- R15 の下忍の見本を作り、クライアント用の写しを ReplicatedStorage に置く。
-- 写しの Attribute の PartCount にパーツの数を書き、クライアントは全部届くまで待ってから写す
function Template.build(): Model
	local description = Instance.new("HumanoidDescription")
	description.HeadColor = BODY_COLOR
	description.TorsoColor = BODY_COLOR
	description.LeftArmColor = BODY_COLOR
	description.RightArmColor = BODY_COLOR
	description.LeftLegColor = LEG_COLOR
	description.RightLegColor = LEG_COLOR
	local model = Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	model.Name = "Genin"
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.BreakJointsOnDeath = false

	local copy = model:Clone()
	copy.Name = Template.NAME
	local parts = 0
	for _, descendant in copy:GetDescendants() do
		if descendant:IsA("BasePart") then
			parts += 1
		end
	end
	copy:SetAttribute("PartCount", parts)
	copy.Parent = ReplicatedStorage
	return model
end

return Template
