--!strict
-- キャラクターの物理の衝突のグループ。敵（仮の湧き処理の下忍と上忍）は、体ではプレイヤーにもほかの敵にもぶつからない。
-- 敵は近づいて攻撃するだけで、体で押したり上に乗ったりしない。ぶつかると、敵がプレイヤーや敵の上に積み重なり、
-- プレイヤーが囲まれて動けなくなるため。攻撃の当たりは物理でなく計算（HitShape）で決めるので、ぶつからなくても当たる。
--
-- - グループはプレイヤーのキャラクター（Player）と敵（Enemy）。地面や建物（Default）とはどちらもぶつかる
-- - プレイヤーどうしはぶつかる
-- - キャラクターに後から足した部品（武器、見た目の差し替え）も同じグループにする
-- - 秘計の落石の岩は、使った軍の相手の軍の下忍と上忍の個体だけを止める。プレイヤーは通り抜ける。
--   敵軍の個体を止める岩は RakusekiTekigun（Enemy とだけぶつかる）、味方軍の個体を止める岩は RakusekiMikatagun。
--   味方軍の個体はまだいない（#82）ので、RakusekiMikatagun が止めるキャラクターは今は無い

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PhysicsService = game:GetService("PhysicsService")

local Gun = require(ReplicatedStorage.Shared.Gun)

local CollisionGroups = {}

CollisionGroups.PLAYER = "Player"
CollisionGroups.ENEMY = "Enemy"
CollisionGroups.RAKUSEKI_TEKIGUN = "RakusekiTekigun"
CollisionGroups.RAKUSEKI_MIKATAGUN = "RakusekiMikatagun"

local registered = false

-- グループを登録し、ぶつかる組み合わせを決める。2回目からは何もしない
function CollisionGroups.setup()
	if registered then
		return
	end
	registered = true
	for _, name in
		{
			CollisionGroups.PLAYER,
			CollisionGroups.ENEMY,
			CollisionGroups.RAKUSEKI_TEKIGUN,
			CollisionGroups.RAKUSEKI_MIKATAGUN,
		}
	do
		if not PhysicsService:IsCollisionGroupRegistered(name) then
			PhysicsService:RegisterCollisionGroup(name)
		end
	end
	PhysicsService:CollisionGroupSetCollidable(CollisionGroups.ENEMY, CollisionGroups.PLAYER, false)
	PhysicsService:CollisionGroupSetCollidable(CollisionGroups.ENEMY, CollisionGroups.ENEMY, false)
	-- 落石の岩はプレイヤーを止めない。敵軍の個体を止める岩だけが Enemy とぶつかる
	for _, rock in { CollisionGroups.RAKUSEKI_TEKIGUN, CollisionGroups.RAKUSEKI_MIKATAGUN } do
		PhysicsService:CollisionGroupSetCollidable(rock, CollisionGroups.PLAYER, false)
	end
	PhysicsService:CollisionGroupSetCollidable(CollisionGroups.RAKUSEKI_MIKATAGUN, CollisionGroups.ENEMY, false)
end

-- 軍 blockedGun の個体だけを止める落石の岩のグループ
function CollisionGroups.rakusekiGroupOf(blockedGun: Gun.Gun): string
	return if blockedGun == "Tekigun" then CollisionGroups.RAKUSEKI_TEKIGUN else CollisionGroups.RAKUSEKI_MIKATAGUN
end

local function assign(instance: Instance, group: string)
	if instance:IsA("BasePart") then
		instance.CollisionGroup = group
	end
end

-- model の部品をすべて group にする。後から足した部品も同じグループにする
function CollisionGroups.apply(model: Model, group: string)
	CollisionGroups.setup()
	for _, descendant in model:GetDescendants() do
		assign(descendant, group)
	end
	model.DescendantAdded:Connect(function(descendant)
		assign(descendant, group)
	end)
end

return CollisionGroups
