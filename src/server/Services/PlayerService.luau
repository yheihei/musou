--!strict
-- プレイヤーのステータス管理。撃破数と奥義ゲージは Player の Attribute に持たせて
-- クライアントへ自動で複製させる。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DebugCommand = require(script.Parent.Parent.DebugCommand)

local PlayerService = {}

function PlayerService.addGekihasu(player: Player)
	player:SetAttribute("Gekihasu", (player:GetAttribute("Gekihasu") :: number? or 0) + 1)
end

function PlayerService.getOugiGauge(player: Player): number
	return player:GetAttribute("OugiGauge") :: number? or 0
end

function PlayerService.addOugiGauge(player: Player, amount: number)
	local value = math.clamp(PlayerService.getOugiGauge(player) + amount, 0, Config.Ougi.MaxGauge)
	player:SetAttribute("OugiGauge", value)
end

function PlayerService.resetOugiGauge(player: Player)
	player:SetAttribute("OugiGauge", 0)
end

local function onCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid.WalkSpeed = Config.Player.WalkSpeed
	humanoid.MaxHealth = Config.Player.MaxHealth
	humanoid.Health = Config.Player.MaxHealth

	local lastHealth = humanoid.Health
	humanoid.HealthChanged:Connect(function(health)
		if health < lastHealth then
			PlayerService.addOugiGauge(player, (lastHealth - health) * Config.Ougi.GainPerDamageTaken)
		end
		lastHealth = health
	end)
end

local function onPlayerAdded(player: Player)
	player:SetAttribute("Gekihasu", 0)
	player:SetAttribute("OugiGauge", 0)

	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		onCharacterAdded(player, player.Character)
	end
end

local function registerDebugCommands()
	DebugCommand.register(
		"SetGekihasu",
		"<プレイヤー名> <撃破数>",
		"撃破数を書き換える",
		function(name, value)
			local player = DebugCommand.findPlayer(name)
			local count = math.max(0, math.floor(DebugCommand.toNumber(value, "撃破数")))
			player:SetAttribute("Gekihasu", count)
			return `{player.Name} の撃破数を {count} にした`
		end
	)
	DebugCommand.register(
		"SetOugiGauge",
		"<プレイヤー名> <量>",
		`奥義ゲージを書き換える（0〜{Config.Ougi.MaxGauge}）`,
		function(name, value)
			local player = DebugCommand.findPlayer(name)
			local amount = math.clamp(DebugCommand.toNumber(value, "量"), 0, Config.Ougi.MaxGauge)
			player:SetAttribute("OugiGauge", amount)
			return `{player.Name} の奥義ゲージを {amount} にした`
		end
	)
end

function PlayerService.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	registerDebugCommands()
end

return PlayerService
