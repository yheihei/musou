--!strict
-- 秘計の落石。発動者から Config.luau の距離（Hikei 節の TargetRange.Rakuseki）以内で一番近い落石地点に岩を落とし、
-- その落石地点が塞ぐ区間（つながり）を、発動者の相手の軍にとって通れなくする（HeitansenService.block）。
-- 発動者の軍の兵站線は変えない。発動の入口・使用記録・効果の時間管理は HikeiService にある。
--
-- - 近くに落石地点が無ければ発動できず（NoTarget）、枚は未使用のまま残る
-- - 一番近い落石地点に岩があれば、重ねて使えない（AlreadyActive）
-- - 効果時間は Config.luau の Hikei 節の Duration.Rakuseki。過ぎるかステージが終わったら、岩を消して区間を戻す。
--   同じ区間をほかの岩が同じ軍に対して塞いでいれば、その軍の通れなさは残す
-- - 相手の部隊は、塞いだ区間を経路に使わない（HoshinService の道のりは、その軍が通れないつながりを通らない）
-- - 岩は区間の向きに直角に並べ、地面の高さに合わせて置く。当たり判定は、相手の軍の下忍と上忍の個体だけを止める
--   衝突のグループにする（CollisionGroups.rakusekiGroupOf。プレイヤーは通り抜ける）。
--   当たり判定があると CanQuery が効かないので、タグ Ground.IGNORE_TAG を付けて地面の高さの計算に当てない
--   （岩の上に下忍を出したり、草むらを浮かせたりしない）

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Ground = require(ReplicatedStorage.Shared.Ground)
local Gun = require(ReplicatedStorage.Shared.Gun)
local Hikei = require(ReplicatedStorage.Shared.Hikei)
local CollisionGroups = require(script.Parent.Parent.CollisionGroups)
local HaichiService = require(script.Parent.HaichiService)
local HeitansenService = require(script.Parent.HeitansenService)
local HikeiService = require(script.Parent.HikeiService)
local KyotenService = require(script.Parent.KyotenService)

local RakusekiService = {}

local HIKEI_ID = "Rakuseki"

-- 岩の直径と、真ん中の岩から左右の岩までの間隔（スタッド）。左右の岩は少し小さくする
local ROCK_DIAMETER = 14
local SIDE_DIAMETER = 10
local SIDE_OFFSET = 11
-- 岩を地面に沈める割合（直径に対する割合）
local SINK = 0.25
local ROCK_COLOR = Color3.fromRGB(112, 104, 94)

-- 岩を落とした落石地点
type Active = {
	effect: Hikei.Effect,
	kyotenA: string,
	kyotenB: string,
	-- 通れなくした軍（発動者の相手の軍）
	blockedGun: Gun.Gun,
}

-- 落石地点 ID から引く、岩を落とした落石地点
local active: { [string]: Active } = {}

-- 区間の向きに直角な水平の向き（単位ベクトル）。両端の拠点が無ければ東西
local function acrossOf(kyotenA: string, kyotenB: string): Vector3
	local a = KyotenService.centerOf(kyotenA)
	local b = KyotenService.centerOf(kyotenB)
	if not a or not b then
		return Vector3.new(1, 0, 0)
	end
	local along = Vector3.new(b.x - a.x, 0, b.z - a.z)
	if along.Magnitude < 1e-3 then
		return Vector3.new(1, 0, 0)
	end
	local unit = along.Unit
	return Vector3.new(-unit.Z, 0, unit.X)
end

local function rock(name: string, diameter: number, position: Vector3, group: string, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Ball
	part.Anchored = true
	part.CanCollide = true
	part.CanTouch = false
	part.CanQuery = false
	part.Material = Enum.Material.Slate
	part.Color = ROCK_COLOR
	part.Size = Vector3.one * diameter
	local y = Ground.heightAt(position.X, position.Z) or position.Y
	part.Position = Vector3.new(position.X, y + diameter * (0.5 - SINK), position.Z)
	part.CollisionGroup = group
	CollectionService:AddTag(part, Ground.IGNORE_TAG)
	part.Parent = parent
	return part
end

-- 落石地点に岩を3つ並べて置く
local function buildRocks(chiten: HaichiService.LoadedRakuseki, blockedGun: Gun.Gun)
	local folder = HikeiService.folderOf(HIKEI_ID)
	local old = folder:FindFirstChild(chiten.id)
	if old then
		old:Destroy()
	end
	local model = Instance.new("Model")
	model.Name = chiten.id
	model:SetAttribute("BlockedGun", blockedGun)
	local group = CollisionGroups.rakusekiGroupOf(blockedGun)
	local across = acrossOf(chiten.kyotenA, chiten.kyotenB)
	rock("Center", ROCK_DIAMETER, chiten.position, group, model)
	rock("Left", SIDE_DIAMETER, chiten.position - across * SIDE_OFFSET, group, model)
	rock("Right", SIDE_DIAMETER, chiten.position + across * SIDE_OFFSET, group, model)
	model.Parent = folder
end

local function removeRocks(chitenId: string)
	local folder = HikeiService.folderOf(HIKEI_ID)
	local model = folder:FindFirstChild(chitenId)
	if model then
		model:Destroy()
	end
end

local function activate(context: HikeiService.Context): (boolean, Hikei.UseFailure?)
	local chiten = HaichiService.nearestRakusekiChiten(context.position)
	if not chiten then
		return false, "NoTarget"
	end
	if active[chiten.id] then
		return false, "AlreadyActive"
	end
	local effect = HikeiService.addEffect({
		hikei = HIKEI_ID,
		user = context.user,
		gun = context.gun,
		target = chiten.id,
		targetGun = nil,
		now = context.now,
		duration = nil,
	})
	if not effect then
		return false, "NoTarget"
	end
	local blockedGun = Gun.opponentOf(context.gun)
	active[chiten.id] = { effect = effect, kyotenA = chiten.kyotenA, kyotenB = chiten.kyotenB, blockedGun = blockedGun }
	HeitansenService.block(chiten.kyotenA, chiten.kyotenB, blockedGun)
	buildRocks(chiten, blockedGun)
	return true, nil
end

local function finish(effect: Hikei.Effect, _reason: HikeiService.FinishReason)
	local chitenId = effect.target
	local entry = active[chitenId]
	removeRocks(chitenId)
	if not entry or entry.effect ~= effect then
		return
	end
	active[chitenId] = nil
	-- 同じ区間をほかの岩が同じ軍に対して塞いでいれば、通れないままにする
	for _, other in active do
		local same = (other.kyotenA == entry.kyotenA and other.kyotenB == entry.kyotenB)
			or (other.kyotenA == entry.kyotenB and other.kyotenB == entry.kyotenA)
		if same and other.blockedGun == entry.blockedGun then
			return
		end
	end
	HeitansenService.unblock(entry.kyotenA, entry.kyotenB, entry.blockedGun)
end

function RakusekiService.start()
	HikeiService.register(HIKEI_ID, { activate = activate, finish = finish })
end

return RakusekiService
