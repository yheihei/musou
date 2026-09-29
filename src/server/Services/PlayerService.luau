--!strict
-- プレイヤーのステータス管理。使うキャラクター・撃破数・奥義ゲージ（本数と次の1本までの量）は
-- Player の Attribute に持たせてクライアントへ自動で複製させる。出現時にキャラクターの能力値と仮の見た目を当て、
-- 使うキャラクター（CharacterId）が変わったら出現し直す。
-- 被弾による奥義ゲージの増加は DamageService の被ダメージの窓口が足す。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Appearance = require(ReplicatedStorage.Shared.Appearance)
local Characters = require(ReplicatedStorage.Shared.Characters)
local Config = require(ReplicatedStorage.Shared.Config)
local OugiGauge = require(ReplicatedStorage.Shared.OugiGauge)
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

-- 奥義ゲージ。溜まった本数は Attribute の OugiStock、次の1本までの量は OugiGauge に持つ
function PlayerService.getOugi(player: Player): OugiGauge.Gauge
	return {
		stock = player:GetAttribute("OugiStock") :: number? or 0,
		gauge = player:GetAttribute("OugiGauge") :: number? or 0,
	}
end

local function setOugi(player: Player, value: OugiGauge.Gauge)
	player:SetAttribute("OugiStock", value.stock)
	player:SetAttribute("OugiGauge", value.gauge)
end

function PlayerService.addOugiGauge(player: Player, amount: number)
	setOugi(player, OugiGauge.add(PlayerService.getOugi(player), amount))
end

-- 奥義のために1本使う。1本も無ければ使わずに false を返す
function PlayerService.consumeOugiStock(player: Player): boolean
	local ok, next = OugiGauge.consume(PlayerService.getOugi(player))
	if ok then
		setOugi(player, next)
	end
	return ok
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
	setOugi(player, OugiGauge.initial())

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
		`奥義ゲージの合計の量を書き換える（1本 {Config.Ougi.PerStock}、0〜{Config.Ougi.PerStock * Config.Ougi.MaxStock}）`,
		function(name, value)
			local player = DebugCommand.findPlayer(name)
			local ougi = OugiGauge.fromTotal(DebugCommand.toNumber(value, "量"))
			setOugi(player, ougi)
			return `{player.Name} の奥義ゲージを {ougi.stock} 本と {ougi.gauge} にした`
		end
	)
	DebugCommand.register(
		"SetOugiStock",
		"<プレイヤー名> <本数>",
		`奥義ゲージの本数を書き換え、次の1本までの量を 0 にする（0〜{Config.Ougi.MaxStock}）`,
		function(name, value)
			local player = DebugCommand.findPlayer(name)
			local stock = math.clamp(math.floor(DebugCommand.toNumber(value, "本数")), 0, Config.Ougi.MaxStock)
			setOugi(player, { stock = stock, gauge = 0 })
			return `{player.Name} の奥義ゲージを {stock} 本にした`
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
