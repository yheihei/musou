--!strict
-- キャラクターの仮の見た目。標準の R15 体型をキャラクターの色で塗り、頭上に名札を出す。
-- 操作キャラクターにも、NPC の上忍・首領・役者にも同じ関数を使う。M2 で本番の見た目に差し替える。
-- 色は Colors.luau から引く。Roblox の API を使うので、Lune のテストからは読まない。

local Players = game:GetService("Players")

local Characters = require("./Characters")
local Colors = require("./Colors")

local Appearance = {}

-- 顔と手足の色。体と腕はキャラクターの色で塗る
local SKIN_COLOR = Color3.fromRGB(234, 190, 150)
local LEG_SHADE = 0.45
-- 色の定義が無いキャラクターの色
local FALLBACK_COLOR = Color3.fromRGB(128, 128, 128)

local NAME_TAG = "NameTag"

-- キャラクター ID から、服も装飾も無い HumanoidDescription を作る
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

-- NPC（上忍・首領・役者）のモデルを作る。置き場所は呼び出し側が決める
function Appearance.createModel(characterId: string): Model
	local model = Players:CreateHumanoidModelFromDescription(Appearance.describe(characterId), Enum.HumanoidRigType.R15)
	model.Name = characterId
	model:SetAttribute("CharacterId", characterId)
	Appearance.attachNameTag(model, characterId)
	return model
end

-- 出現した操作キャラクターに見た目を当てる。アバターの服と装飾は外れる。
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
end

return Appearance
