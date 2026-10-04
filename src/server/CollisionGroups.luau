--!strict
-- キャラクターの物理の衝突のグループ。敵（仮の湧き処理の下忍と上忍）は、体ではプレイヤーにもほかの敵にもぶつからない。
-- 敵は近づいて攻撃するだけで、体で押したり上に乗ったりしない。ぶつかると、敵がプレイヤーや敵の上に積み重なり、
-- プレイヤーが囲まれて動けなくなるため。攻撃の当たりは物理でなく計算（HitShape）で決めるので、ぶつからなくても当たる。
--
-- - グループはプレイヤーのキャラクター（Player）と敵（Enemy）。地面や建物（Default）とはどちらもぶつかる
-- - プレイヤーどうしはぶつかる
-- - キャラクターに後から足した部品（武器、見た目の差し替え）も同じグループにする

local PhysicsService = game:GetService("PhysicsService")

local CollisionGroups = {}

CollisionGroups.PLAYER = "Player"
CollisionGroups.ENEMY = "Enemy"

local registered = false

-- グループを登録し、ぶつかる組み合わせを決める。2回目からは何もしない
function CollisionGroups.setup()
	if registered then
		return
	end
	registered = true
	for _, name in { CollisionGroups.PLAYER, CollisionGroups.ENEMY } do
		if not PhysicsService:IsCollisionGroupRegistered(name) then
			PhysicsService:RegisterCollisionGroup(name)
		end
	end
	PhysicsService:CollisionGroupSetCollidable(CollisionGroups.ENEMY, CollisionGroups.PLAYER, false)
	PhysicsService:CollisionGroupSetCollidable(CollisionGroups.ENEMY, CollisionGroups.ENEMY, false)
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
