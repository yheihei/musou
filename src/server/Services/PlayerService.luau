--!strict
-- プレイヤーのステータス管理。KO 数と無双ゲージは Player の Attribute に持たせて
-- クライアントへ自動で複製させる。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local PlayerService = {}

function PlayerService.addKO(player: Player)
	player:SetAttribute("KOs", (player:GetAttribute("KOs") :: number? or 0) + 1)
end

function PlayerService.getMusou(player: Player): number
	return player:GetAttribute("Musou") :: number? or 0
end

function PlayerService.addMusou(player: Player, amount: number)
	local value = math.clamp(PlayerService.getMusou(player) + amount, 0, Config.Musou.MaxGauge)
	player:SetAttribute("Musou", value)
end

function PlayerService.resetMusou(player: Player)
	player:SetAttribute("Musou", 0)
end

local function onCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid.WalkSpeed = Config.Player.WalkSpeed
	humanoid.MaxHealth = Config.Player.MaxHealth
	humanoid.Health = Config.Player.MaxHealth

	local lastHealth = humanoid.Health
	humanoid.HealthChanged:Connect(function(health)
		if health < lastHealth then
			PlayerService.addMusou(player, (lastHealth - health) * Config.Musou.GainPerDamageTaken)
		end
		lastHealth = health
	end)
end

local function onPlayerAdded(player: Player)
	player:SetAttribute("KOs", 0)
	player:SetAttribute("Musou", 0)

	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		onCharacterAdded(player, player.Character)
	end
end

function PlayerService.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
end

return PlayerService
