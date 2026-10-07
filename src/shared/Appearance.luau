--!strict
-- キャラクターの仮の見た目。標準の R15 体型をキャラクターの色で塗り、頭上に名札を出し、右手に武器を持たせる。
-- 待機と移動のモーションは Motions.luau の Ninja パックにする。
-- 操作キャラクターにも、NPC の上忍・首領・役者にも同じ関数を使う。M2 で本番の見た目に差し替える。
-- 戦場に出る上忍と首領の個体には、名札の下に体力バーを足す（attachHealthBar）。
-- 色は Colors.luau から、武器のモデルは ReplicatedStorage.Weapons（Buki.luau）から引く。
-- Roblox の API を使うので、Lune のテストからは読まない。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Buki = require("./Buki")
local Characters = require("./Characters")
local Colors = require("./Colors")
local Motions = require("./Motions")

local Appearance = {}

-- 顔と手足の色。体と腕はキャラクターの色で塗る
local SKIN_COLOR = Color3.fromRGB(234, 190, 150)
local LEG_SHADE = 0.45
-- 色の定義が無いキャラクターの色
local FALLBACK_COLOR = Color3.fromRGB(128, 128, 128)

local NAME_TAG = "NameTag"
-- 名札の下に足す体力バーの名前と、名札の文字の高さ・バーの大きさ（ピクセル）
local HEALTH_BAR = "HealthBar"
local HEALTH_FILL = "Fill"
local NAME_HEIGHT = 28
local BAR_WIDTH = 100
local BAR_HEIGHT = 8
local BAR_GAP = 2
local BAR_BACKGROUND = Color3.fromRGB(30, 30, 30)
-- キャラクターに付けた武器のモデルの名前
local BUKI_NAME = "Buki"
-- 武器を握る向き。右手の握りの Attachment（RightGripAttachment）は前が指先、上が手の前なので、
-- X 軸まわりに 90 度回して、武器の刃先（Grip の前）を拳の前へ、峰（Grip の上）を腕の上へ向ける
local BUKI_MOUNT = CFrame.Angles(math.rad(90), 0, 0)

-- キャラクター ID から、服も装飾も無く、待機と移動が Ninja パックの HumanoidDescription を作る
function Appearance.describe(characterId: string): HumanoidDescription
	local color = Colors.Character[characterId] or FALLBACK_COLOR
	local legColor = color:Lerp(Color3.new(0, 0, 0), LEG_SHADE)
	local description = Instance.new("HumanoidDescription")
	description.HeadColor = SKIN_COLOR
	description.TorsoColor = color
	description.LeftArmColor = color
	description.RightArmColor = color
	description.LeftLegColor = legColor
	description.RightLegColor = legColor
	local locomotion = Motions.Locomotion
	description.IdleAnimation = locomotion.Idle
	description.WalkAnimation = locomotion.Walk
	description.RunAnimation = locomotion.Run
	description.JumpAnimation = locomotion.Jump
	description.FallAnimation = locomotion.Fall
	description.ClimbAnimation = locomotion.Climb
	description.SwimAnimation = locomotion.Swim
	return description
end

-- 頭上に名札を付け、Roblox の既定の頭上表示（名前と体力）を消す。付け直すときは古い名札を外す
function Appearance.attachNameTag(model: Model, characterId: string)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	local head = model:FindFirstChild("Head") :: BasePart?
	if not head then
		return
	end
	local old = head:FindFirstChild(NAME_TAG)
	if old then
		old:Destroy()
	end

	local character = Characters.get(characterId)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 18
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.TextStrokeColor3 = Colors.Character[characterId] or FALLBACK_COLOR
	label.Text = if character then character.displayName else characterId

	local tag = Instance.new("BillboardGui")
	tag.Name = NAME_TAG
	tag.Size = UDim2.fromOffset(160, 28)
	tag.StudsOffset = Vector3.new(0, 2.4, 0)
	tag.LightInfluence = 0
	tag.MaxDistance = 120
	tag.Adornee = head
	label.Parent = tag
	tag.Parent = head
end

-- 名札の下に体力バーを足す。color はバーの色（軍の色など）。名札が無ければ何もしない。付け直すときは古いバーを外す
function Appearance.attachHealthBar(model: Model, color: Color3)
	local head = model:FindFirstChild("Head")
	local tag = head and head:FindFirstChild(NAME_TAG) :: BillboardGui?
	if not tag then
		return
	end
	local old = tag:FindFirstChild(HEALTH_BAR)
	if old then
		old:Destroy()
	end
	-- 名札の文字を上に寄せ、その下にバーを置く
	tag.Size = UDim2.fromOffset(tag.Size.X.Offset, NAME_HEIGHT + BAR_GAP + BAR_HEIGHT)
	local label = tag:FindFirstChildOfClass("TextLabel")
	if label then
		label.Size = UDim2.new(1, 0, 0, NAME_HEIGHT)
	end
	local bar = Instance.new("Frame")
	bar.Name = HEALTH_BAR
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Position = UDim2.new(0.5, 0, 0, NAME_HEIGHT + BAR_GAP)
	bar.Size = UDim2.fromOffset(BAR_WIDTH, BAR_HEIGHT)
	bar.BackgroundColor3 = BAR_BACKGROUND
	bar.BorderSizePixel = 0
	local fill = Instance.new("Frame")
	fill.Name = HEALTH_FILL
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Parent = bar
	bar.Parent = tag
end

-- 体力バーの残りを rate（0〜1）にする。バーが無ければ何もしない
function Appearance.setHealthBar(model: Model, rate: number)
	local head = model:FindFirstChild("Head")
	local tag = head and head:FindFirstChild(NAME_TAG)
	local bar = tag and tag:FindFirstChild(HEALTH_BAR)
	local fill = bar and bar:FindFirstChild(HEALTH_FILL) :: Frame?
	if fill then
		fill.Size = UDim2.fromScale(math.clamp(rate, 0, 1), 1)
	end
end

-- キャラクターの武器のモデルを右手に溶接する。付け直すときは古い武器を外す。武器の無いキャラクターには付けない
function Appearance.attachBuki(model: Model, characterId: string)
	local old = model:FindFirstChild(BUKI_NAME)
	if old then
		old:Destroy()
	end
	local character = Characters.get(characterId)
	local bukiId = character and character.buki
	local hand = model:FindFirstChild("RightHand") :: BasePart?
	local handGrip = hand and hand:FindFirstChild("RightGripAttachment") :: Attachment?
	if not bukiId or not hand or not handGrip then
		return
	end
	local folder = ReplicatedStorage:FindFirstChild(Buki.FOLDER)
	local template = folder and folder:FindFirstChild(bukiId)
	if not template or not template:IsA("Model") then
		warn(`Appearance: 武器のモデル {bukiId} が ReplicatedStorage.{Buki.FOLDER} に無い`)
		return
	end
	local buki = template:Clone()
	local handle = buki:FindFirstChild(Buki.HANDLE) :: BasePart?
	local grip = handle and handle:FindFirstChild(Buki.GRIP) :: Attachment?
	if not handle or not grip then
		warn(`Appearance: 武器のモデル {bukiId} に {Buki.HANDLE} と {Buki.GRIP} が無い`)
		buki:Destroy()
		return
	end
	buki.Name = BUKI_NAME
	buki.PrimaryPart = handle
	buki:SetAttribute("BukiId", bukiId)
	-- 先に握る位置へ動かしてから溶接する
	local mount = handGrip.CFrame * BUKI_MOUNT
	buki:PivotTo(hand.CFrame * mount * grip.CFrame:Inverse() * handle.CFrame:ToObjectSpace(buki:GetPivot()))
	local weld = Instance.new("Weld")
	weld.Name = "BukiWeld"
	weld.Part0 = hand
	weld.Part1 = handle
	weld.C0 = mount
	weld.C1 = grip.CFrame
	weld.Parent = handle
	buki.Parent = model
end

-- NPC（上忍・首領・役者）のモデルを作る。置き場所は呼び出し側が決める
function Appearance.createModel(characterId: string): Model
	local model = Players:CreateHumanoidModelFromDescription(Appearance.describe(characterId), Enum.HumanoidRigType.R15)
	model.Name = characterId
	model:SetAttribute("CharacterId", characterId)
	Appearance.attachNameTag(model, characterId)
	Appearance.attachBuki(model, characterId)
	return model
end

-- 出現した操作キャラクターに見た目を当て、武器を持たせる。アバターの服と装飾は外れる。
-- ApplyDescription は待つことがあるので、呼び出し側は別スレッドで呼ぶ
function Appearance.applyToCharacter(model: Model, characterId: string)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	if not model:IsDescendantOf(workspace) then
		model.AncestryChanged:Wait()
	end
	local ok, err = pcall(function()
		humanoid:ApplyDescription(Appearance.describe(characterId))
	end)
	if not ok then
		warn(`Appearance: {characterId} の見た目を当てられなかった: {err}`)
	end
	model:SetAttribute("CharacterId", characterId)
	Appearance.attachNameTag(model, characterId)
	Appearance.attachBuki(model, characterId)
end

return Appearance
