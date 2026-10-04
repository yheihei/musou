--!strict
-- 秘計の兵糧庫。発動者が中にいる味方の通常拠点を、兵站線が切れても孤立しない兵糧庫に改築する。
-- 孤立しない拠点の指定は HeitansenService.setNeverIsolated を使う。兵站線の計算は孤立しない拠点をつながった拠点として扱うので、
-- 支配エリア（ShihaiAreaService）と再出撃先（SaishutsugekiService）にもそのまま兵糧庫が入る。
-- 発動の入口・使用記録・効果の時間管理は HikeiService にある。
--
-- - 対象は、発動者が範囲の中にいる、発動者の軍の通常拠点。本陣と拠点の外では発動できず（NoTarget）、枚は未使用のまま残る
-- - すでに兵糧庫の拠点には重ねて使えない（AlreadyActive）
-- - 効果に期限は無い。拠点が制圧されると兵糧庫ではなくなる（HeitansenService が指定を外す）ので、効果を終える
-- - 兵糧庫にした拠点の中心に、両軍に見える仮の見た目（積んだ米俵と「兵糧庫」の札）を置く。高さは地面に合わせる。
--   見た目には当たり判定を付けない
-- - 効果が終わったら（制圧・ステージの終わり）、指定を外して見た目を片付ける

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Ground = require(ReplicatedStorage.Shared.Ground)
local Gun = require(ReplicatedStorage.Shared.Gun)
local Hikei = require(ReplicatedStorage.Shared.Hikei)
local HeitansenService = require(script.Parent.HeitansenService)
local HikeiService = require(script.Parent.HikeiService)
local KyotenService = require(script.Parent.KyotenService)

local HyorokoService = {}

local HIKEI_ID = "Hyoroko"

-- 米俵の大きさ（円柱の長さと直径）と色、札の高さ（スタッド）
local TAWARA_LENGTH = 4
local TAWARA_DIAMETER = 2.4
local TAWARA_COLOR = Color3.fromRGB(196, 170, 110)
local LABEL_HEIGHT = 9

-- 拠点 ID から引く、兵糧庫の効果
local active: { [string]: Hikei.Effect } = {}

local function piece(name: string, cframe: CFrame, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Cylinder
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Material = Enum.Material.Fabric
	part.Color = TAWARA_COLOR
	part.Size = Vector3.new(TAWARA_LENGTH, TAWARA_DIAMETER, TAWARA_DIAMETER)
	part.CFrame = cframe
	part.Parent = parent
	return part
end

-- 拠点の中心に、積んだ米俵と札を置く
local function buildVisual(kyotenId: string, gun: Gun.Gun)
	local center = KyotenService.centerOf(kyotenId)
	if not center then
		return
	end
	local folder = HikeiService.folderOf(HIKEI_ID)
	local old = folder:FindFirstChild(kyotenId)
	if old then
		old:Destroy()
	end
	local y = Ground.heightAt(center.x, center.z) or (KyotenService.positionOf(kyotenId) or Vector3.zero).Y
	local model = Instance.new("Model")
	model.Name = kyotenId
	model:SetAttribute("Gun", gun)
	local radius = TAWARA_DIAMETER / 2
	-- 下の段に3俵、上の段に2俵を横に寝かせて積む
	local base = CFrame.new(center.x, y + radius, center.z)
	local top: Part? = nil
	for index = -1, 1 do
		piece(`Tawara{index + 2}`, base * CFrame.new(0, 0, index * TAWARA_DIAMETER), model)
	end
	for index = 0, 1 do
		local offset = (index - 0.5) * TAWARA_DIAMETER
		top = piece(`Tawara{index + 4}`, base * CFrame.new(0, TAWARA_DIAMETER * 0.85, offset), model)
	end
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Label"
	billboard.Size = UDim2.fromOffset(120, 32)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, LABEL_HEIGHT - TAWARA_DIAMETER * 0.85, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 300
	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBold
	text.TextScaled = true
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextStrokeTransparency = 0.3
	text.Text = "兵糧庫"
	text.Parent = billboard
	billboard.Adornee = top
	billboard.Parent = model
	model.Parent = folder
end

local function removeVisual(kyotenId: string)
	local folder = HikeiService.folderOf(HIKEI_ID)
	local model = folder:FindFirstChild(kyotenId)
	if model then
		model:Destroy()
	end
end

-- 兵糧庫にした拠点か
function HyorokoService.isHyoroko(kyotenId: string): boolean
	return active[kyotenId] ~= nil
end

local function activate(context: HikeiService.Context): (boolean, Hikei.UseFailure?)
	local kyotenId = KyotenService.kyotenAt({ x = context.position.X, z = context.position.Z })
	local kyoten = if kyotenId then KyotenService.get(kyotenId) else nil
	local failure = Hikei.checkHyoroko(
		if kyotenId and kyoten
			then { gun = kyoten.gun, honjin = kyoten.honjin, active = active[kyotenId] ~= nil }
			else nil,
		context.gun
	)
	if failure or not kyotenId or not kyoten then
		return false, failure or "NoTarget"
	end
	local effect = HikeiService.addEffect({
		hikei = HIKEI_ID,
		user = context.user,
		gun = context.gun,
		target = kyotenId,
		targetGun = kyoten.gun,
		now = context.now,
		duration = nil,
	})
	if not effect then
		return false, "NoTarget"
	end
	active[kyotenId] = effect
	HeitansenService.setNeverIsolated(kyotenId, true)
	buildVisual(kyotenId, kyoten.gun)
	return true, nil
end

local function finish(effect: Hikei.Effect, _reason: HikeiService.FinishReason)
	local kyotenId = effect.target
	if active[kyotenId] == effect then
		active[kyotenId] = nil
	end
	removeVisual(kyotenId)
	-- 制圧なら HeitansenService が外し済み。ステージの終わりなど、ほかの理由でも外す（拠点が片付いていれば何もしない）
	if KyotenService.get(kyotenId) then
		HeitansenService.setNeverIsolated(kyotenId, false)
	end
end

-- 兵糧庫にした拠点が制圧されたら、効果を終える
local function onSeiatsu(kyotenId: string)
	local effect = active[kyotenId]
	if effect then
		HikeiService.finishEffect(effect, "Ended")
	end
end

function HyorokoService.start()
	HikeiService.register(HIKEI_ID, { activate = activate, finish = finish })
	KyotenService.seiatsu:Connect(onSeiatsu)
end

return HyorokoService
