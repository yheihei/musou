--!strict
-- プレイヤーの被ダメージの窓口。敵・秘計など、プレイヤーにダメージを与える処理はすべて damage を通す。
-- 無敵・ガード・防御の軽減・反応・奥義ゲージの増加は ReplicatedStorage.Shared.Damage が決める。
-- ここは体力を減らし、奥義ゲージを足し、のけぞり・ダウン・ガードの硬直を ActionService で始める。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Damage = require(ReplicatedStorage.Shared.Damage)
local DebugCommand = require(script.Parent.Parent.DebugCommand)
local ActionService = require(script.Parent.ActionService)
local PlayerService = require(script.Parent.PlayerService)

-- 無敵とのけぞらない間が切れる時刻
type Record = {
	invulnerableUntil: number,
	flinchImmuneUntil: number,
}

local DamageService = {}

local records: { [Player]: Record } = {}

-- 窓口の Damage で攻撃元を置く、プレイヤーからの距離（スタッド）
local DEBUG_ORIGIN_DISTANCE = 5

-- 攻撃をプレイヤーに当てて、その結果を返す。倒れているかキャラクターが無ければ nil
function DamageService.damage(player: Player, attack: Damage.Attack): Damage.Outcome?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local record = records[player]
	if not character or not humanoid or humanoid.Health <= 0 or not record then
		return nil
	end

	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return nil
	end

	local t = ActionService.now()
	local action, startedAt = ActionService.current(player)
	local outcome = Damage.resolve({
		action = action,
		startedAt = startedAt,
		defense = PlayerService.getStats(player).Defense,
		forceField = character:FindFirstChildOfClass("ForceField") ~= nil,
		invulnerableUntil = record.invulnerableUntil,
		flinchImmuneUntil = record.flinchImmuneUntil,
		position = root.Position,
		facing = root.CFrame.LookVector,
	}, attack, t)
	record.invulnerableUntil = outcome.invulnerableUntil
	record.flinchImmuneUntil = outcome.flinchImmuneUntil

	if outcome.amount > 0 then
		humanoid.Health = math.max(humanoid.Health - outcome.amount, 0)
	end
	if outcome.gauge > 0 then
		PlayerService.addOugiGauge(player, outcome.gauge)
	end
	if outcome.action and humanoid.Health > 0 then
		ActionService.interrupt(player, outcome.action)
	end
	return outcome
end

local function track(player: Player)
	records[player] = { invulnerableUntil = 0, flinchImmuneUntil = 0 }
	-- 出現し直したら、無敵とのけぞらない間を消す
	player.CharacterAdded:Connect(function()
		records[player] = { invulnerableUntil = 0, flinchImmuneUntil = 0 }
	end)
end

local function registerDebugCommands()
	DebugCommand.register(
		"Damage",
		`<プレイヤー名> <威力> [{table.concat(Damage.reactions, "|")}] [Front|Back|Left|Right]`,
		`被ダメージの窓口で攻撃を当てる。反応の既定は Flinch、攻撃元はプレイヤーの向きから見た方向へ {DEBUG_ORIGIN_DISTANCE} スタッド（既定は Front）`,
		function(name, power, reaction, side)
			local player = DebugCommand.findPlayer(name)
			local amount = DebugCommand.toNumber(power, "威力")
			local kind = reaction or "Flinch"
			if not table.find(Damage.reactions, kind) then
				error(`反応は {table.concat(Damage.reactions, "、")} のどれか（{tostring(kind)}）`, 0)
			end
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if not root or not humanoid then
				return `{player.Name} のキャラクターがいない`
			end
			local frame = root.CFrame
			local directions: { [string]: Vector3 } = {
				Front = frame.LookVector,
				Back = -frame.LookVector,
				Right = frame.RightVector,
				Left = -frame.RightVector,
			}
			local direction = directions[side or "Front"]
			if not direction then
				error(`向きは Front、Back、Left、Right のどれか（{tostring(side)}）`, 0)
			end

			local before = humanoid.Health
			local outcome = DamageService.damage(player, {
				origin = root.Position + direction * DEBUG_ORIGIN_DISTANCE,
				power = amount,
				reaction = kind :: Damage.Reaction,
			})
			if not outcome then
				return `{player.Name} は倒れている`
			end
			return string.format(
				"%s: %s（ダメージ %.2f、反応 %s、体力 %.1f → %.1f、行動 %s）",
				player.Name,
				outcome.result,
				outcome.amount,
				outcome.action or "なし",
				before,
				humanoid.Health,
				tostring(ActionService.current(player))
			)
		end
	)
end

function DamageService.start()
	Players.PlayerAdded:Connect(track)
	for _, player in Players:GetPlayers() do
		track(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		records[player] = nil
	end)
	registerDebugCommands()
end

return DamageService
