--!strict
-- 秘計の爆破罠。発動者が中にいる自分の軍の拠点に罠を仕掛け、耐久が上限の割合（Config.luau の Bakuhawana 節の Rate）を
-- 上から下へ越えた瞬間に1回だけ爆発させて、拠点の中の相手を吹き飛ばす。
-- 爆発の判定と兵数の減らし方は ReplicatedStorage.Shared.Bakuhawana、発動できるかの確かめは Hikei.checkBakuhawana、
-- 威力は Config.luau の Bakuhawana 節にある。発動の入口・使用記録・効果の管理は HikeiService にある。
--
-- - 対象は、発動者が範囲の中にいる、発動者の軍の拠点（本陣も含む）。拠点の外と相手の拠点では発動できず（NoTarget）、
--   もう罠を仕掛けた拠点には重ねて使えず（AlreadyActive）、耐久が割合をもう下回った拠点にも使えない（LowTaikyu）。
--   発動できなかった枚は未使用のまま残る
-- - 効果に期限は無い。爆発するか、拠点が制圧されるか、ステージが終わったら罠を外す
-- - 耐久が割合を上から下へ越えるとき、耐久を書き換える前に爆発する（KyotenService.addTaikyuListener）。
--   一度に 0 まで減って制圧されるときも、制圧の前に爆発する
-- - 爆発で減らした部隊の兵数は、拠点の耐久に数えない（ButaiService.changeHeisu の silent）。
--   割合は、個体として出ていない分（兵数 − 個体の数。GeninKotaiService.countOf）に掛ける。下忍の個体は爆発のダメージで
--   1体ずつ倒れて兵数を減らし、これも拠点の耐久に数えない（EnemyService.damage の silent）
--   兵数の減少の知らせは遅れて届くことがあり、制圧した軍の拠点の耐久に数えると、その場で取り返してしまうため
-- - 割合を越えずに制圧されたとき（窓口の SetKyotenGun など）は、爆発せずに罠を外す
-- - 爆発は、拠点の範囲の中の相手の上忍・首領（被ダメージの受け口 JoninService.damage。個体は吹き飛ぶ）・
--   プレイヤー（ガードできない吹き飛びの攻撃）・相手の軍の下忍の体（下忍の個体。味方軍が仕掛けた罠なら窓口で出した敵も。
--   ダメージと吹き飛び。EnemyService.getTargets に相手の軍を渡して引く）にダメージを与え、
--   相手の部隊の兵数を割合で減らす（潜んでいる伏兵部隊も含む）。同じ軍は無傷
-- - 発動者がプレイヤーなら、減らした兵数を撃破数に足す。倒した上忍・首領は受け口が、下忍の個体と窓口で出した敵はとどめとして、
--   発動者の撃破に数える
-- - 罠の目印（樽と「爆破罠」の札）は、仕掛けた軍にだけ見せる。プレイヤーは味方軍なので、味方軍が仕掛けた罠だけ置く
-- - 爆発の仮の見た目（Explosion と広がる火の玉）を拠点の中心に出す
-- - 罠を仕掛けた拠点かを hasTrap で引ける（秘計の判断が、もう罠のある拠点に使わないために引く）

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Bakuhawana = require(ReplicatedStorage.Shared.Bakuhawana)
local Config = require(ReplicatedStorage.Shared.Config)
local Ground = require(ReplicatedStorage.Shared.Ground)
local Gun = require(ReplicatedStorage.Shared.Gun)
local Hikei = require(ReplicatedStorage.Shared.Hikei)
local Jonin = require(ReplicatedStorage.Shared.Jonin)
local Kyoten = require(ReplicatedStorage.Shared.Kyoten)
local Stats = require(ReplicatedStorage.Shared.Stats)
local ButaiService = require(script.Parent.ButaiService)
local DamageService = require(script.Parent.DamageService)
local EnemyService = require(script.Parent.EnemyService)
local GeninKotaiService = require(script.Parent.GeninKotaiService)
local HikeiService = require(script.Parent.HikeiService)
local JoninService = require(script.Parent.JoninService)
local KyotenService = require(script.Parent.KyotenService)
local PlayerService = require(script.Parent.PlayerService)
local StageService = require(script.Parent.StageService)

local BakuhawanaService = {}

local HIKEI_ID = "Bakuhawana"

-- 罠の目印を拠点の中心からずらす量（兵糧庫の米俵と重ならないよう東へ）と、樽の大きさと色、札の高さ（スタッド）
local MARKER_OFFSET = 8
local BARREL_HEIGHT = 3
local BARREL_DIAMETER = 2.4
local BARREL_COLOR = Color3.fromRGB(70, 50, 40)
local BAND_COLOR = Color3.fromRGB(200, 40, 30)
local LABEL_HEIGHT = 6
-- 爆発の火の玉の色と、広がる秒数
local BLAST_COLOR = Color3.fromRGB(255, 140, 40)
local BLAST_TIME = 0.5
-- 拠点の範囲の大きさが分からないときの火の玉の半径（スタッド）
local DEFAULT_BLAST_RADIUS = 24

-- 仕掛けた罠
type Trap = {
	effect: Hikei.Effect,
	-- 仕掛けた軍
	gun: Gun.Gun,
	-- 発動者がプレイヤーならその Player
	player: Player?,
}

-- 拠点 ID から引く、仕掛けた罠
local traps: { [string]: Trap } = {}

local function markerFolder(): Folder
	return HikeiService.folderOf(HIKEI_ID)
end

-- 罠の目印（樽と札）を拠点の中心の東に置く
local function buildMarker(kyotenId: string)
	local center = KyotenService.centerOf(kyotenId)
	if not center then
		return
	end
	local old = markerFolder():FindFirstChild(kyotenId)
	if old then
		old:Destroy()
	end
	local x, z = center.x + MARKER_OFFSET, center.z
	local y = Ground.heightAt(x, z) or (KyotenService.positionOf(kyotenId) or Vector3.zero).Y
	local model = Instance.new("Model")
	model.Name = kyotenId
	local barrel = Instance.new("Part")
	barrel.Name = "Taru"
	barrel.Shape = Enum.PartType.Cylinder
	barrel.Anchored = true
	barrel.CanCollide = false
	barrel.CanTouch = false
	barrel.CanQuery = false
	barrel.Material = Enum.Material.Wood
	barrel.Color = BARREL_COLOR
	barrel.Size = Vector3.new(BARREL_HEIGHT, BARREL_DIAMETER, BARREL_DIAMETER)
	-- 円柱の軸（X）を縦にして立てる
	barrel.CFrame = CFrame.new(x, y + BARREL_HEIGHT / 2, z) * CFrame.Angles(0, 0, math.rad(90))
	barrel.Parent = model
	local band = barrel:Clone()
	band.Name = "Obi"
	band.Material = Enum.Material.SmoothPlastic
	band.Color = BAND_COLOR
	band.Size = Vector3.new(0.5, BARREL_DIAMETER + 0.1, BARREL_DIAMETER + 0.1)
	band.Parent = model
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Label"
	billboard.Size = UDim2.fromOffset(120, 32)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, LABEL_HEIGHT - BARREL_HEIGHT / 2, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 300
	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBold
	text.TextScaled = true
	text.TextColor3 = Color3.fromRGB(255, 200, 190)
	text.TextStrokeTransparency = 0.3
	text.Text = "爆破罠"
	text.Parent = billboard
	billboard.Adornee = barrel
	billboard.Parent = model
	model.Parent = markerFolder()
end

local function removeMarker(kyotenId: string)
	local model = markerFolder():FindFirstChild(kyotenId)
	if model then
		model:Destroy()
	end
end

-- 拠点の中心に爆発の見た目を出す。radius は火の玉が広がる半径
local function showBlast(position: Vector3, radius: number)
	local explosion = Instance.new("Explosion")
	explosion.Position = position
	explosion.BlastRadius = radius
	-- 見た目だけにする（物を飛ばさず、関節も壊さない）
	explosion.BlastPressure = 0
	explosion.DestroyJointRadiusPercent = 0
	explosion.ExplosionType = Enum.ExplosionType.NoCraters
	explosion.Parent = workspace
	local ball = Instance.new("Part")
	ball.Name = "Bakuhatsu"
	ball.Shape = Enum.PartType.Ball
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanTouch = false
	ball.CanQuery = false
	ball.CastShadow = false
	ball.Material = Enum.Material.Neon
	ball.Color = BLAST_COLOR
	ball.Transparency = 0.2
	ball.Size = Vector3.one * 2
	ball.Position = position
	ball.Parent = markerFolder()
	TweenService:Create(ball, TweenInfo.new(BLAST_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.one * radius * 2,
		Transparency = 1,
	}):Play()
	Debris:AddItem(ball, BLAST_TIME + 0.1)
end

-- 爆発の火の玉が広がる半径。拠点の範囲の大きさの半分
local function blastRadiusOf(kyotenId: string): number
	local haichi = KyotenService.getHaichi()
	if haichi then
		for _, kyoten in haichi.kyoten do
			if kyoten.id == kyotenId then
				return math.max(kyoten.size.X, kyoten.size.Z) / 2
			end
		end
	end
	return DEFAULT_BLAST_RADIUS
end

-- 罠を爆発させ、拠点の中の相手にダメージを与える。罠の効果は終える
local function explode(kyotenId: string, trap: Trap)
	if traps[kyotenId] == trap then
		traps[kyotenId] = nil
	end
	local opponent = Gun.opponentOf(trap.gun)
	local power = Config.Bakuhawana.Power
	local center = KyotenService.positionOf(kyotenId)
	local player = trap.player
	local attacker = if player and player.Parent then player else nil
	local kills = 0

	for _, jonin in JoninService.list() do
		if
			jonin.gun == opponent
			and not Jonin.isDefeated(jonin)
			and KyotenService.contains(kyotenId, jonin.position)
		then
			-- 個体として出ていれば、拠点の中心から吹き飛ぶ。倒した上忍と首領は、受け口が発動者の撃破数に数える
			local hit = if center
				then { reaction = "Knockback" :: Config.Reaction, origin = center, force = Config.Bakuhawana.Knockback }
				else nil
			JoninService.damage(jonin.id, power, attacker, hit)
		end
	end

	for _, butai in ButaiService.list() do
		if butai.gun == opponent and KyotenService.contains(kyotenId, butai.position) then
			local loss = Bakuhawana.heisuLoss(butai.heisu - GeninKotaiService.countOf(butai.id))
			if loss > 0 and ButaiService.changeHeisu(butai.id, -loss, true) then
				kills += loss
			end
		end
	end

	if opponent == "Mikatagun" and center then
		for _, member in StageService.getMembers() do
			local character = member.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root and KyotenService.contains(kyotenId, { x = root.Position.X, z = root.Position.Z }) then
				DamageService.damage(member, {
					origin = center,
					power = power,
					reaction = "Knockback",
					guardable = false,
				})
			end
		end
	end

	if center then
		local amount = Stats.damage(1, power, 0)
		for _, target in EnemyService.getTargets(opponent) do
			local position: Vector3 = target.position
			if KyotenService.contains(kyotenId, { x = position.X, z = position.Z }) then
				EnemyService.damage(target.ref, amount, attacker, {
					reaction = "Knockback",
					origin = center,
					force = Config.Bakuhawana.Knockback,
				}, true)
			end
		end
	end

	if player and player.Parent and kills > 0 then
		PlayerService.addGekihasu(player, kills)
	end
	if center then
		showBlast(center, blastRadiusOf(kyotenId))
	end
	HikeiService.finishEffect(trap.effect, "Ended")
end

-- 爆破罠を仕掛けた拠点か（発動の確かめの AlreadyActive と同じ見方）
function BakuhawanaService.hasTrap(kyotenId: string): boolean
	return traps[kyotenId] ~= nil
end

local function activate(context: HikeiService.Context): (boolean, Hikei.UseFailure?)
	local kyotenId = KyotenService.kyotenAt({ x = context.position.X, z = context.position.Z })
	local kyoten = if kyotenId then KyotenService.get(kyotenId) else nil
	local failure = Hikei.checkBakuhawana(
		if kyotenId and kyoten
			then {
				gun = kyoten.gun,
				taikyu = kyoten.taikyu,
				threshold = Bakuhawana.threshold(Kyoten.maxTaikyu(kyoten.honjin)),
				active = traps[kyotenId] ~= nil,
			}
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
	traps[kyotenId] = { effect = effect, gun = context.gun, player = context.player }
	-- 目印は仕掛けた軍にだけ見せる。プレイヤーは味方軍なので、敵軍の罠の目印は置かない
	if context.gun == "Mikatagun" then
		buildMarker(kyotenId)
	end
	return true, nil
end

local function finish(effect: Hikei.Effect, _reason: HikeiService.FinishReason)
	local kyotenId = effect.target
	local trap = traps[kyotenId]
	if trap and trap.effect == effect then
		traps[kyotenId] = nil
	end
	removeMarker(kyotenId)
end

-- 耐久が割合を上から下へ越えるなら、書き換える前（制圧の前）に爆発させる
local function onTaikyuChanging(kyotenId: string, before: number, after: number)
	local trap = traps[kyotenId]
	local kyoten = KyotenService.get(kyotenId)
	if not trap or not kyoten or kyoten.gun ~= trap.gun then
		return
	end
	if Bakuhawana.crossed(before, after, Kyoten.maxTaikyu(kyoten.honjin)) then
		explode(kyotenId, trap)
	end
end

-- 割合を越えずに制圧されたら（窓口の SetKyotenGun など）、爆発させずに罠を外す
local function onSeiatsu(kyotenId: string, _gun: Gun.Gun, previous: Gun.Gun)
	local trap = traps[kyotenId]
	if trap and trap.gun == previous then
		traps[kyotenId] = nil
		HikeiService.finishEffect(trap.effect, "Ended")
	end
end

function BakuhawanaService.start()
	HikeiService.register(HIKEI_ID, { activate = activate, finish = finish })
	KyotenService.addTaikyuListener(onTaikyuChanging)
	KyotenService.seiatsu:Connect(onSeiatsu)
end

return BakuhawanaService
