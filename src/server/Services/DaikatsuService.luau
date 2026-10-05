--!strict
-- 秘計の大喝。発動者の周りの相手の強化の秘計（鬼神化）を打ち消し、相手の上忍・首領・プレイヤー・部隊を動揺させる。
-- 対象の選び方と動揺の補正は ReplicatedStorage.Shared.Daikatsu、範囲と倍率は Config.luau の Daikatsu 節、
-- 動揺の時間は Hikei 節の Duration.Daikatsu にある。発動の入口・使用記録・効果の時間管理は HikeiService にある。
--
-- - 対象は、発動者から Radius 以内の、発動者の相手の軍の上忍・首領・プレイヤー（生きている出撃メンバー）・部隊。
--   潜んでいる伏兵部隊は対象にしない。対象が1つも無ければ発動できず（NoTarget）、枚は未使用のまま残る
-- - 対象の上忍・首領・プレイヤーにかかっている、相手の軍の強化の秘計を打ち消す（HikeiService.dispelKyoka）
-- - 対象ごとに動揺の効果を足す。動揺している対象には重ねず、残っている動揺がそのまま続く
-- - 動揺した上忍と首領は攻撃と防御が下がる（JoninService.setHikeiHosei）。
--   プレイヤーも攻撃と防御が下がり（PlayerService.addModifierProvider）、頭の上に「動揺」の札を出す。
--   部隊は動揺の間だけ士気が下がる（ButaiService.setDoyo）
-- - 動揺は効果時間が過ぎるか、ステージが終わったら解く。上忍・首領・プレイヤーは倒れたときにも解く。
--   プレイヤーは、生きたまま姿が入れ替わったとき（キャラクターの変更や出現し直し）にも解く
-- - 実体化した下忍の個体（#76）はまだ無いので、部隊の動揺を個体の攻撃と防御に映すのは個体ができてから
-- - 発動者の位置から周りへ広がる仮の見た目（衝撃の輪）を出す

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Daikatsu = require(ReplicatedStorage.Shared.Daikatsu)
local Hikei = require(ReplicatedStorage.Shared.Hikei)
local Jonin = require(ReplicatedStorage.Shared.Jonin)
local Stats = require(ReplicatedStorage.Shared.Stats)
local ButaiService = require(script.Parent.ButaiService)
local HikeiService = require(script.Parent.HikeiService)
local JoninService = require(script.Parent.JoninService)
local PlayerService = require(script.Parent.PlayerService)
local StageService = require(script.Parent.StageService)

local DaikatsuService = {}

local HIKEI_ID = "Daikatsu"

-- 衝撃の輪の色・厚み・広がる秒数
local WAVE_COLOR = Color3.fromRGB(255, 240, 180)
local WAVE_THICKNESS = 0.6
local WAVE_TIME = 0.4
-- 動揺したプレイヤーの頭の上に出す札の名前と色
local LABEL_NAME = "Doyo"
local LABEL_COLOR = Color3.fromRGB(190, 120, 255)

-- 動揺させた対象
type Target = {
	kind: Daikatsu.Kind,
	id: string,
}

-- 対象の種類と ID をつないだ鍵から引く、動揺の効果
local doyoOf: { [string]: Hikei.Effect } = {}
-- 動揺の効果から引く対象
local targetOf: { [Hikei.Effect]: Target } = {}
-- 動揺したプレイヤーの、倒れたことと姿が入れ替わることを見る接続（UserId の文字列から引く）
local playerConnections: { [string]: { RBXScriptConnection } } = {}

local function keyOf(kind: Daikatsu.Kind, id: string): string
	return `{kind}:{id}`
end

local function playerOf(user: string): Player?
	local userId = tonumber(user)
	return if userId then Players:GetPlayerByUserId(userId) else nil
end

local function userIdOf(player: Player): string
	return tostring(player.UserId)
end

-- 動揺しているか
function DaikatsuService.isDoyo(kind: Daikatsu.Kind, id: string): boolean
	return doyoOf[keyOf(kind, id)] ~= nil
end

local function aliveRoot(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return root
end

-- 大喝の対象の候補（倒れていない上忍と首領、生きている出撃メンバー、部隊）
local function candidates(): { Daikatsu.Candidate }
	local list: { Daikatsu.Candidate } = {}
	for _, jonin in JoninService.list() do
		if not Jonin.isDefeated(jonin) then
			table.insert(
				list,
				{ kind = "Jonin", id = jonin.id, gun = jonin.gun, x = jonin.position.x, z = jonin.position.z }
			)
		end
	end
	for _, member in StageService.getMembers() do
		local root = aliveRoot(member)
		if root then
			table.insert(list, {
				kind = "Player",
				id = userIdOf(member),
				gun = "Mikatagun",
				x = root.Position.X,
				z = root.Position.Z,
			})
		end
	end
	for _, butai in ButaiService.list() do
		table.insert(list, {
			kind = "Butai",
			id = butai.id,
			gun = butai.gun,
			x = butai.position.x,
			z = butai.position.z,
			hidden = butai.fukuhei == true,
		})
	end
	return list
end

local function addLabel(player: Player)
	local character = player.Character
	local head = character and character:FindFirstChild("Head") :: BasePart?
	if not head or head:FindFirstChild(LABEL_NAME) then
		return
	end
	local billboard = Instance.new("BillboardGui")
	billboard.Name = LABEL_NAME
	billboard.Size = UDim2.fromOffset(80, 28)
	billboard.StudsOffset = Vector3.new(0, 2.5, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 150
	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBold
	text.TextScaled = true
	text.TextColor3 = LABEL_COLOR
	text.TextStrokeTransparency = 0.3
	text.Text = "動揺"
	text.Parent = billboard
	billboard.Parent = head
end

local function removeLabel(player: Player)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	local label = head and head:FindFirstChild(LABEL_NAME)
	if label then
		label:Destroy()
	end
end

-- 発動者の位置から周りへ広がる衝撃の輪
local function showWave(position: Vector3)
	local part = Instance.new("Part")
	part.Name = "Wave"
	part.Shape = Enum.PartType.Cylinder
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = WAVE_COLOR
	part.Transparency = 0.3
	part.Size = Vector3.new(WAVE_THICKNESS, 2, 2)
	part.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	part.Parent = HikeiService.folderOf(HIKEI_ID)
	local diameter = Config.Daikatsu.Radius * 2
	TweenService:Create(part, TweenInfo.new(WAVE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(WAVE_THICKNESS, diameter, diameter),
		Transparency = 0.9,
	}):Play()
	Debris:AddItem(part, WAVE_TIME + 0.1)
end

-- 動揺を解く
local function endDoyo(effect: Hikei.Effect)
	HikeiService.finishEffect(effect, "Ended")
end

-- 対象を動揺させる。もう動揺していれば何もしない
local function shake(context: HikeiService.Context, target: Daikatsu.Candidate)
	local key = keyOf(target.kind, target.id)
	if doyoOf[key] then
		return
	end
	local effect = HikeiService.addEffect({
		hikei = HIKEI_ID,
		user = context.user,
		gun = context.gun,
		target = target.id,
		targetGun = target.gun,
		now = context.now,
		duration = nil,
	})
	if not effect then
		return
	end
	doyoOf[key] = effect
	targetOf[effect] = { kind = target.kind, id = target.id }
	if target.kind == "Jonin" then
		JoninService.setHikeiHosei(target.id, HIKEI_ID, Daikatsu.doyoModifiers())
	elseif target.kind == "Butai" then
		ButaiService.setDoyo(target.id, Daikatsu.doyoShiki())
	else
		local player = playerOf(target.id)
		if player then
			addLabel(player)
			local function onGone()
				local current = doyoOf[key]
				if current then
					endDoyo(current)
				end
			end
			local connections = { player.CharacterRemoving:Once(onGone) }
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				table.insert(connections, humanoid.Died:Once(onGone))
			end
			playerConnections[target.id] = connections
		end
	end
end

local function activate(context: HikeiService.Context): (boolean, Hikei.UseFailure?)
	local targets = Daikatsu.targetsOf(context.position.X, context.position.Z, context.gun, candidates())
	if #targets == 0 then
		return false, "NoTarget"
	end
	-- 上忍・首領・プレイヤーにかかっている相手の強化の秘計を打ち消す
	local dispelTargets = {}
	for _, target in targets do
		if target.kind ~= "Butai" then
			table.insert(dispelTargets, target.id)
		end
	end
	if #dispelTargets > 0 then
		HikeiService.dispelKyoka(context.gun, dispelTargets)
	end
	for _, target in targets do
		shake(context, target)
	end
	showWave(context.position)
	return true, nil
end

local function finish(effect: Hikei.Effect, _reason: HikeiService.FinishReason)
	local target = targetOf[effect]
	targetOf[effect] = nil
	if not target then
		return
	end
	local key = keyOf(target.kind, target.id)
	if doyoOf[key] ~= effect then
		return
	end
	doyoOf[key] = nil
	if target.kind == "Jonin" then
		JoninService.setHikeiHosei(target.id, HIKEI_ID, nil)
	elseif target.kind == "Butai" then
		ButaiService.setDoyo(target.id, nil)
	else
		for _, connection in playerConnections[target.id] or {} do
			connection:Disconnect()
		end
		playerConnections[target.id] = nil
		local player = playerOf(target.id)
		if player then
			removeLabel(player)
		end
	end
end

-- 倒れた上忍と首領の動揺を解く
local function onJoninDefeated(id: string)
	local effect = doyoOf[keyOf("Jonin", id)]
	if effect then
		endDoyo(effect)
	end
end

function DaikatsuService.start()
	HikeiService.register(HIKEI_ID, { activate = activate, finish = finish })
	PlayerService.addModifierProvider(function(player: Player): { Stats.Modifier }
		return if doyoOf[keyOf("Player", userIdOf(player))] then Daikatsu.doyoModifiers() else {}
	end)
	JoninService.defeated:Connect(onJoninDefeated)
	Players.PlayerRemoving:Connect(function(player)
		local effect = doyoOf[keyOf("Player", userIdOf(player))]
		if effect then
			endDoyo(effect)
		end
	end)
end

return DaikatsuService
