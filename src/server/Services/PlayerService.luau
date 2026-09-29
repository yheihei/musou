--!strict
-- プレイヤーのステータス管理。使うキャラクター・撃破数・奥義ゲージは Player の Attribute に
-- 持たせてクライアントへ自動で複製させる。出現時にキャラクターの能力値と仮の見た目を当て、
-- 使うキャラクター（CharacterId）が変わったら出現し直す。
-- 被弾による奥義ゲージの増加は DamageService の被ダメージの窓口が足す。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Appearance = require(ReplicatedStorage.Shared.Appearance)
local Characters = require(ReplicatedStorage.Shared.Characters)
local Config = require(ReplicatedStorage.Shared.Config)
local Stats = require(ReplicatedStorage.Shared.Stats)
local DebugCommand = require(script.Parent.Parent.DebugCommand)

local PlayerService = {}

-- 使うキャラクターの ID。Attribute が無いか操作キャラクターでなければ既定のキャラクター
function PlayerService.getCharacterId(player: Player): string
	local id = player:GetAttribute("CharacterId")
	if type(id) == "string" and Stats.baseOf(id) then
		return id
	end
	return Characters.DEFAULT_ID
end

-- 使うキャラクターの能力値。補正はまだ無い
function PlayerService.getStats(player: Player): Stats.Values
	local base = Stats.baseOf(PlayerService.getCharacterId(player)) :: Stats.Values
	return Stats.compute(base, {})
end

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
	local stats = PlayerService.getStats(player)
	humanoid.WalkSpeed = stats.WalkSpeed
	humanoid.MaxHealth = stats.MaxHealth
	humanoid.Health = stats.MaxHealth
	task.spawn(Appearance.applyToCharacter, character, PlayerService.getCharacterId(player))
end

local function onPlayerAdded(player: Player)
	if player:GetAttribute("CharacterId") == nil then
		player:SetAttribute("CharacterId", Characters.DEFAULT_ID)
	end
	player:SetAttribute("Gekihasu", 0)
	player:SetAttribute("OugiGauge", 0)

	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		onCharacterAdded(player, player.Character)
	end
	-- 使うキャラクターが変わったら、能力値と見た目を当て直すために出現し直す
	player:GetAttributeChangedSignal("CharacterId"):Connect(function()
		if player.Character then
			player:LoadCharacter()
		end
	end)
end

local function registerDebugCommands()
	DebugCommand.register(
		"SetCharacter",
		"<プレイヤー名> <キャラクター ID>",
		"使うキャラクターを変えて出現し直す",
		function(name, characterId)
			local player = DebugCommand.findPlayer(name)
			if type(characterId) ~= "string" or not Stats.baseOf(characterId) then
				local ids = {}
				for id in Config.Stats.Characters do
					table.insert(ids, id)
				end
				table.sort(ids)
				error(
					`キャラクター ID は {table.concat(ids, "、")} のどれか（{tostring(characterId)}）`,
					0
				)
			end
			-- 出現し直すのは CharacterId の変化を見ている onPlayerAdded の処理
			player:SetAttribute("CharacterId", characterId)
			local stats = PlayerService.getStats(player)
			return `{player.Name} を {characterId} にした（体力 {stats.MaxHealth}、移動速度 {stats.WalkSpeed}）`
		end
	)
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
