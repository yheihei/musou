--!strict
-- 秘計の鬼神化。発動者自身の攻撃と防御を上げ、のけぞらなくする強化の秘計（大喝で打ち消せる）。
-- 倍率は ReplicatedStorage.Shared.Kishinka と Config.luau の Kishinka 節、効果時間は Hikei 節の Duration.Kishinka にある。
-- 発動の入口・使用記録・効果の時間管理は HikeiService にある。
--
-- - 対象は発動者自身。プレイヤーにも、敵軍の上忍と首領（#128 の AI）にも同じ倍率を使う
-- - プレイヤーは、能力値の補正（PlayerService.addModifierProvider）で攻撃と防御を上げ、
--   被ダメージの窓口（DamageService.addNoFlinchProvider）でのけぞらなくする。吹き飛びと打ち上げはダウンになる
-- - 上忍と首領は、能力値の補正（JoninService.setHikeiHosei）で攻撃と防御を上げる。
--   上忍と首領の個体（#91）はまだ無いので、のけぞらないことは個体ができてから isActive で引いて使う
-- - 同じ発動者にはもう効果が出ていれば重ねて使えない（AlreadyActive）
-- - 効果時間が過ぎるか、発動者が倒れるか、大喝で打ち消されるか、ステージが終わったら解除する
-- - 効果中のプレイヤーには、赤い縁取り（Highlight）の仮の見た目を付ける

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Hikei = require(ReplicatedStorage.Shared.Hikei)
local Kishinka = require(ReplicatedStorage.Shared.Kishinka)
local Stats = require(ReplicatedStorage.Shared.Stats)
local DamageService = require(script.Parent.DamageService)
local HikeiService = require(script.Parent.HikeiService)
local JoninService = require(script.Parent.JoninService)
local PlayerService = require(script.Parent.PlayerService)

local KishinkaService = {}

local HIKEI_ID = "Kishinka"

-- 効果中のプレイヤーに付ける仮の見た目の名前と色
local HIGHLIGHT_NAME = "Kishinka"
local HIGHLIGHT_COLOR = Color3.fromRGB(255, 60, 40)

-- 発動者の ID（プレイヤーは UserId の文字列、上忍と首領はキャラクター ID）から引く、鬼神化の効果
local active: { [string]: Hikei.Effect } = {}
-- 効果中のプレイヤーの、倒れたことを見る接続
local diedConnections: { [string]: RBXScriptConnection } = {}

-- 発動者の ID の鬼神化の効果が出ているか（上忍と首領の個体ののけぞりにも使う）
function KishinkaService.isActive(user: string): boolean
	return active[user] ~= nil
end

local function playerOf(user: string): Player?
	local userId = tonumber(user)
	return if userId then Players:GetPlayerByUserId(userId) else nil
end

local function addHighlight(player: Player)
	local character = player.Character
	if not character or character:FindFirstChild(HIGHLIGHT_NAME) then
		return
	end
	local highlight = Instance.new("Highlight")
	highlight.Name = HIGHLIGHT_NAME
	highlight.FillColor = HIGHLIGHT_COLOR
	highlight.FillTransparency = 0.75
	highlight.OutlineColor = HIGHLIGHT_COLOR
	highlight.OutlineTransparency = 0
	highlight.Parent = character
end

local function removeHighlight(player: Player)
	local character = player.Character
	local highlight = character and character:FindFirstChild(HIGHLIGHT_NAME)
	if highlight then
		highlight:Destroy()
	end
end

-- 発動者が倒れたら効果を終える
local function endEffectOf(user: string)
	local effect = active[user]
	if effect then
		HikeiService.finishEffect(effect, "Ended")
	end
end

local function activate(context: HikeiService.Context): (boolean, Hikei.UseFailure?)
	if active[context.user] then
		return false, "AlreadyActive"
	end
	local effect = HikeiService.addEffect({
		hikei = HIKEI_ID,
		user = context.user,
		gun = context.gun,
		target = context.user,
		targetGun = context.gun,
		now = context.now,
		duration = nil,
	})
	if not effect then
		return false, "NoTarget"
	end
	active[context.user] = effect
	local player = context.player
	local jonin = context.jonin
	if player then
		addHighlight(player)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			diedConnections[context.user] = humanoid.Died:Once(function()
				endEffectOf(context.user)
			end)
		end
	elseif jonin then
		JoninService.setHikeiHosei(jonin, HIKEI_ID, Kishinka.modifiers())
	end
	return true, nil
end

local function finish(effect: Hikei.Effect, _reason: HikeiService.FinishReason)
	local user = effect.target
	if active[user] == effect then
		active[user] = nil
	end
	local connection = diedConnections[user]
	if connection then
		connection:Disconnect()
		diedConnections[user] = nil
	end
	local player = playerOf(user)
	if player then
		removeHighlight(player)
	else
		-- 片付けた後の上忍と首領には何もしない（JoninService.setHikeiHosei が false を返す）
		JoninService.setHikeiHosei(user, HIKEI_ID, nil)
	end
end

local function userIdOf(player: Player): string
	return tostring(player.UserId)
end

function KishinkaService.start()
	HikeiService.register(HIKEI_ID, { activate = activate, finish = finish })
	PlayerService.addModifierProvider(function(player: Player): { Stats.Modifier }
		return if active[userIdOf(player)] then Kishinka.modifiers() else {}
	end)
	DamageService.addNoFlinchProvider(function(player: Player): boolean
		return active[userIdOf(player)] ~= nil
	end)
	JoninService.defeated:Connect(endEffectOf)
	Players.PlayerRemoving:Connect(function(player)
		endEffectOf(userIdOf(player))
	end)
end

return KishinkaService
