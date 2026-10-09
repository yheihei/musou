--!strict
-- キャラクターの物理の衝突のグループ。NPC の個体（敵軍の下忍の個体と窓口で出した敵、両軍の上忍と首領の個体）は、
-- 体ではプレイヤーにもほかの個体にもぶつからない。
-- 個体は近づいて攻撃するだけで、体で押したり上に乗ったりしない。ぶつかると、個体がプレイヤーや個体の上に積み重なり、
-- プレイヤーが囲まれて動けなくなるため。攻撃の当たりは物理でなく計算（HitShape）で決めるので、ぶつからなくても当たる。
--
-- - グループはプレイヤーのキャラクター（Player）、敵軍の個体（Enemy）、味方軍の個体（Mikatagun）。
--   地面や建物（Default）とはどれもぶつかる
-- - プレイヤーどうしはぶつかる
-- - キャラクターに後から足した部品（武器、見た目の差し替え）も同じグループにする
-- - 秘計の落石の岩は、使った軍の相手の軍の下忍と上忍の個体だけを止める。プレイヤーは通り抜ける。
--   敵軍の個体を止める岩は RakusekiTekigun（Enemy とだけぶつかる）、味方軍の個体を止める岩は RakusekiMikatagun
--   （Mikatagun とだけぶつかる）。味方軍の個体は、上忍と首領の個体（#91）だけがいる（下忍は #82）

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PhysicsService = game:GetService("PhysicsService")

local Gun = require(ReplicatedStorage.Shared.Gun)

local CollisionGroups = {}

CollisionGroups.PLAYER = "Player"
CollisionGroups.ENEMY = "Enemy"
CollisionGroups.MIKATAGUN = "Mikatagun"
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
			CollisionGroups.MIKATAGUN,
			CollisionGroups.RAKUSEKI_TEKIGUN,
			CollisionGroups.RAKUSEKI_MIKATAGUN,
		}
	do
		if not PhysicsService:IsCollisionGroupRegistered(name) then
			PhysicsService:RegisterCollisionGroup(name)
		end
	end
	-- 個体は、プレイヤーにも、軍に関係なくほかの個体にもぶつからない
	for _, kotai in { CollisionGroups.ENEMY, CollisionGroups.MIKATAGUN } do
		PhysicsService:CollisionGroupSetCollidable(kotai, CollisionGroups.PLAYER, false)
		PhysicsService:CollisionGroupSetCollidable(kotai, CollisionGroups.ENEMY, false)
		PhysicsService:CollisionGroupSetCollidable(kotai, CollisionGroups.MIKATAGUN, false)
	end
	-- 落石の岩はプレイヤーを止めない。敵軍の個体を止める岩は Enemy とだけ、味方軍の個体を止める岩は Mikatagun とだけぶつかる
	for _, rock in { CollisionGroups.RAKUSEKI_TEKIGUN, CollisionGroups.RAKUSEKI_MIKATAGUN } do
		PhysicsService:CollisionGroupSetCollidable(rock, CollisionGroups.PLAYER, false)
	end
	PhysicsService:CollisionGroupSetCollidable(CollisionGroups.RAKUSEKI_MIKATAGUN, CollisionGroups.ENEMY, false)
	PhysicsService:CollisionGroupSetCollidable(CollisionGroups.RAKUSEKI_TEKIGUN, CollisionGroups.MIKATAGUN, false)
end

-- 軍 gun の NPC の個体のグループ
function CollisionGroups.kotaiGroupOf(gun: Gun.Gun): string
	return if gun == "Tekigun" then CollisionGroups.ENEMY else CollisionGroups.MIKATAGUN
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
