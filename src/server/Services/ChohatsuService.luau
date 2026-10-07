--!strict
-- 秘計の挑発。発動者の周りの相手の上忍を、効果時間の間、発動者のもとへ誘い出して部隊から引き離す。
-- 対象の選び方は ReplicatedStorage.Shared.Chohatsu、範囲は Config.luau の Chohatsu 節、
-- 誘い出す時間は Hikei 節の Duration.Chohatsu にある。発動の入口・使用記録・効果の時間管理は HikeiService にある。
--
-- - 対象は、発動者から Radius 以内の、発動者の相手の軍の倒れていない上忍。首領は対象にしない。
--   対象が1人もいなければ発動できず（NoTarget）、枚は未使用のまま残る
-- - もう誘い出されている上忍には重ねない。範囲の中の対象がすべてもう誘い出されていれば、
--   重ねがけとして発動しない（AlreadyActive）
-- - 対象ごとに効果を足し、上忍の目的地を発動者の今の位置に差し替える（JoninService.overrideMokutekichi）。
--   上忍は部隊に付いていかず、個体が出ていれば個体が発動者のもとへ歩き、出ていなければデータの位置が歩く速さで進む。
--   部隊は誘い出さず、その場に残る（方針どおりに動く）
-- - 効果時間が過ぎるか、発動者か上忍が倒れるか、ステージが終わったら、差し替えを外す（JoninService.releaseMokutekichi）。
--   上忍は歩いて率いる部隊へ戻る。プレイヤーの発動者は、生きたまま姿が入れ替わったとき（キャラクターの変更や出現し直し）と、
--   抜けたときにも外す
-- - 敵軍の上忍と首領が使うと、味方軍の上忍を誘い出す

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Chohatsu = require(ReplicatedStorage.Shared.Chohatsu)
local Hikei = require(ReplicatedStorage.Shared.Hikei)
local Jonin = require(ReplicatedStorage.Shared.Jonin)
local HikeiService = require(script.Parent.HikeiService)
local JoninService = require(script.Parent.JoninService)

local ChohatsuService = {}

local HIKEI_ID = "Chohatsu"

-- 誘い出している上忍のキャラクター ID から引く、挑発の効果
local lured: { [string]: Hikei.Effect } = {}
-- プレイヤーの発動者の、倒れたことと姿が入れ替わることを見る接続（UserId の文字列から引く）
local playerConnections: { [string]: { RBXScriptConnection } } = {}

-- 上忍が誘い出されているか
function ChohatsuService.isLured(joninId: string): boolean
	return lured[joninId] ~= nil
end

-- 挑発の対象の候補（出撃したステージの上忍と首領）
local function candidates(): { Chohatsu.Candidate }
	local list: { Chohatsu.Candidate } = {}
	for _, jonin in JoninService.list() do
		table.insert(list, {
			id = jonin.id,
			gun = jonin.gun,
			shuryo = jonin.shuryo,
			defeated = Jonin.isDefeated(jonin),
			lured = lured[jonin.id] ~= nil,
			x = jonin.position.x,
			z = jonin.position.z,
		})
	end
	return list
end

-- 発動者の今の位置を返す関数。プレイヤーはキャラクターの位置、上忍と首領はデータの位置。
-- キャラクターがいないか、発動者が倒れていれば nil を返す（上忍はその場にとどまる）
local function positionOf(context: HikeiService.Context): () -> Jonin.Point?
	local player = context.player
	local joninId = context.jonin
	return function(): Jonin.Point?
		if player then
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			return if root then { x = root.Position.X, z = root.Position.Z } else nil
		end
		local jonin = if joninId then JoninService.get(joninId) else nil
		if not jonin or Jonin.isDefeated(jonin) then
			return nil
		end
		return { x = jonin.position.x, z = jonin.position.z }
	end
end

-- 発動者の誘い出しをすべて終える（発動者が倒れたときなど）
local function endEffectsOf(user: string)
	for _, effect in table.clone(lured) do
		if effect.user == user then
			HikeiService.finishEffect(effect, "Ended")
		end
	end
end

-- プレイヤーの発動者が倒れるか姿が入れ替わったら、誘い出しを終える
local function watchPlayer(context: HikeiService.Context)
	local player = context.player
	local user = context.user
	if not player or playerConnections[user] then
		return
	end
	local function onGone()
		endEffectsOf(user)
	end
	local connections = { player.CharacterRemoving:Once(onGone) }
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		table.insert(connections, humanoid.Died:Once(onGone))
	end
	playerConnections[user] = connections
end

local function activate(context: HikeiService.Context): (boolean, Hikei.UseFailure?)
	local targets, failure = Chohatsu.targetsOf(context.position.X, context.position.Z, context.gun, candidates())
	if failure then
		return false, failure
	end
	local mokutekichi = positionOf(context)
	local count = 0
	for _, id in targets do
		local jonin = JoninService.get(id)
		if not jonin then
			continue
		end
		local effect = HikeiService.addEffect({
			hikei = HIKEI_ID,
			user = context.user,
			gun = context.gun,
			target = id,
			targetGun = jonin.gun,
			now = context.now,
			duration = nil,
		})
		if not effect then
			continue
		end
		if not JoninService.overrideMokutekichi(id, mokutekichi) then
			-- 差し替えられなかった効果は外す（lured に入れていないので、finish は差し替えを外さない）
			HikeiService.finishEffect(effect, "Ended")
			continue
		end
		lured[id] = effect
		count += 1
	end
	if count == 0 then
		return false, "NoTarget"
	end
	watchPlayer(context)
	return true, nil
end

-- 効果が終わったら上忍の目的地の差し替えを外す。発動者の誘い出しが残っていなければ、倒れたことを見る接続も外す
local function finish(effect: Hikei.Effect, _reason: HikeiService.FinishReason)
	local id = effect.target
	if lured[id] == effect then
		lured[id] = nil
		-- 片付けた後の上忍には何もしない（JoninService.releaseMokutekichi が false を返す）
		JoninService.releaseMokutekichi(id)
	end
	for _, other in lured do
		if other.user == effect.user then
			return
		end
	end
	for _, connection in playerConnections[effect.user] or {} do
		connection:Disconnect()
	end
	playerConnections[effect.user] = nil
end

-- 誘い出されていた上忍が倒れたら、その効果を終える。誘い出していた上忍か首領が倒れたら、その誘い出しをすべて終える
local function onJoninDefeated(id: string)
	local effect = lured[id]
	if effect then
		HikeiService.finishEffect(effect, "Ended")
	end
	endEffectsOf(id)
end

function ChohatsuService.start()
	HikeiService.register(HIKEI_ID, { activate = activate, finish = finish })
	JoninService.defeated:Connect(onJoninDefeated)
	Players.PlayerRemoving:Connect(function(player)
		endEffectsOf(tostring(player.UserId))
	end)
end

return ChohatsuService
