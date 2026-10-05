--!strict
-- 秘計の大火計。発動者から Config.luau の距離（Hikei 節の TargetRange.Daikakei）以内で一番近い大火計地域に火を放ち、
-- 地域の中の相手の上忍・首領・プレイヤー・下忍にダメージを与え、相手の部隊の兵数を減らす。
-- 威力と割合は Config.luau の Daikakei 節、兵数の減らし方は ReplicatedStorage.Shared.Daikakei にある。
-- 発動の入口と使用記録は HikeiService にある。効果は一度きりで、時間の残る効果は持たない。
--
-- - 近くに大火計地域が無ければ発動できず（NoTarget）、枚は未使用のまま残る。地域の中に相手がいなくても発動する
-- - 地域の中かは、地域の目印のパーツの中心・向き・大きさで水平だけを見る
-- - 上忍と首領は、威力を防御で軽減したダメージを受ける（JoninService.damage）
-- - 部隊は兵数を減らす（ButaiService.changeHeisu）。潜んでいる伏兵部隊も地域の中にいれば焼く。
--   減った兵数は拠点の耐久にも数える（ButaiService.heisuLost を KyotenService が受ける）
-- - プレイヤー（敵軍が使ったとき）は、被ダメージの窓口でガードできない吹き飛びの攻撃を受ける
-- - 仮の湧き処理の敵（味方軍が使ったとき）は、威力のダメージを受ける。とどめを刺したら発動者の撃破に数える
-- - 発動者がプレイヤーなら、倒した上忍・首領と減らした兵数を撃破数に足す
-- - 同じ軍は対象にしない（味方を巻き込まない）
-- - 地域の中に、炎の仮の見た目を FireTime 秒だけ出す

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Daikakei = require(ReplicatedStorage.Shared.Daikakei)
local Ground = require(ReplicatedStorage.Shared.Ground)
local Gun = require(ReplicatedStorage.Shared.Gun)
local Hikei = require(ReplicatedStorage.Shared.Hikei)
local Jonin = require(ReplicatedStorage.Shared.Jonin)
local Mejirushi = require(ReplicatedStorage.Shared.Mejirushi)
local Stats = require(ReplicatedStorage.Shared.Stats)
local ButaiService = require(script.Parent.ButaiService)
local DamageService = require(script.Parent.DamageService)
local EnemyService = require(script.Parent.EnemyService)
local HaichiService = require(script.Parent.HaichiService)
local HikeiService = require(script.Parent.HikeiService)
local JoninService = require(script.Parent.JoninService)
local PlayerService = require(script.Parent.PlayerService)
local StageService = require(script.Parent.StageService)

local DaikakeiService = {}

local HIKEI_ID = "Daikakei"

-- 炎の数を決める、炎1つあたりの地域の広さ（平方スタッド）と、炎の数の下限と上限
local AREA_PER_FIRE = 300
local MIN_FIRES = 6
local MAX_FIRES = 24
-- 地域に敷く焦げ跡の色と、炎の塊の色
local GROUND_COLOR = Color3.fromRGB(255, 110, 40)
local FLAME_COLORS = {
	Color3.fromRGB(255, 90, 30),
	Color3.fromRGB(255, 160, 40),
	Color3.fromRGB(255, 220, 90),
}

-- 地域の中か（水平だけを見る）
local function insideOf(chiiki: HaichiService.LoadedDaikakei, x: number, z: number): boolean
	local offset = chiiki.cframe:PointToObjectSpace(Vector3.new(x, chiiki.cframe.Position.Y, z))
	return Mejirushi.insideBounds(offset.X, offset.Z, chiiki.size.X, chiiki.size.Z)
end

local function flamePart(position: Vector3, size: number, parent: Instance)
	local part = Instance.new("Part")
	part.Name = "Flame"
	part.Shape = Enum.PartType.Ball
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Transparency = 0.4
	part.Color = FLAME_COLORS[math.random(1, #FLAME_COLORS)]
	part.Size = Vector3.new(size, size, size)
	part.Position = position
	local fire = Instance.new("Fire")
	fire.Size = size * 2
	fire.Heat = 12
	fire.Parent = part
	part.Parent = parent
end

-- 地域の中に炎を散らし、地面を赤く塗る。FireTime 秒で消す
local function showFire(chiiki: HaichiService.LoadedDaikakei)
	local model = Instance.new("Model")
	model.Name = chiiki.id
	local center = chiiki.cframe.Position
	local groundY = Ground.heightAt(center.X, center.Z) or center.Y
	local slab = Instance.new("Part")
	slab.Name = "Yake"
	slab.Anchored = true
	slab.CanCollide = false
	slab.CanTouch = false
	slab.CanQuery = false
	slab.CastShadow = false
	slab.Material = Enum.Material.Neon
	slab.Color = GROUND_COLOR
	slab.Transparency = 0.6
	slab.Size = Vector3.new(chiiki.size.X, 0.4, chiiki.size.Z)
	slab.CFrame = CFrame.new(center.X, groundY + 0.3, center.Z) * chiiki.cframe.Rotation
	slab.Parent = model
	local count = math.clamp(math.floor(chiiki.size.X * chiiki.size.Z / AREA_PER_FIRE), MIN_FIRES, MAX_FIRES)
	for _ = 1, count do
		local localX = (math.random() - 0.5) * chiiki.size.X
		local localZ = (math.random() - 0.5) * chiiki.size.Z
		local world = chiiki.cframe:PointToWorldSpace(Vector3.new(localX, 0, localZ))
		local y = Ground.heightAt(world.X, world.Z) or groundY
		local size = 3 + math.random() * 3
		flamePart(Vector3.new(world.X, y + size / 2, world.Z), size, model)
	end
	model.Parent = HikeiService.folderOf(HIKEI_ID)
	Debris:AddItem(model, Config.Daikakei.FireTime)
end

local function activate(context: HikeiService.Context): (boolean, Hikei.UseFailure?)
	local chiiki = HaichiService.nearestDaikakeiChiiki(context.position)
	if not chiiki then
		return false, "NoTarget"
	end
	local opponent = Gun.opponentOf(context.gun)
	local power = Config.Daikakei.Power
	local kills = 0

	for _, jonin in JoninService.list() do
		if
			jonin.gun == opponent
			and not Jonin.isDefeated(jonin)
			and insideOf(chiiki, jonin.position.x, jonin.position.z)
		then
			local _, defeated = JoninService.damage(jonin.id, power)
			if defeated then
				kills += 1
			end
		end
	end

	for _, butai in ButaiService.list() do
		if butai.gun == opponent and insideOf(chiiki, butai.position.x, butai.position.z) then
			local loss = Daikakei.heisuLoss(butai.heisu)
			if loss > 0 then
				ButaiService.changeHeisu(butai.id, -loss)
				kills += loss
			end
		end
	end

	if opponent == "Mikatagun" then
		for _, member in StageService.getMembers() do
			local character = member.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root and insideOf(chiiki, root.Position.X, root.Position.Z) then
				DamageService.damage(member, {
					origin = root.Position,
					power = power,
					reaction = "Knockback",
					guardable = false,
				})
			end
		end
	end

	local player = context.player
	if opponent == EnemyService.GUN and player then
		local amount = Stats.damage(1, power, 0)
		for _, target in EnemyService.getTargets() do
			local position: Vector3 = target.position
			if insideOf(chiiki, position.X, position.Z) then
				EnemyService.damage(target.ref, amount, player, nil)
			end
		end
	end

	if player and kills > 0 then
		PlayerService.addGekihasu(player, kills)
	end
	showFire(chiiki)
	return true, nil
end

function DaikakeiService.start()
	HikeiService.register(HIKEI_ID, { activate = activate })
end

return DaikakeiService
