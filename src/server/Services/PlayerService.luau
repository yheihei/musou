--!strict
-- プレイヤーのステータス管理。使うキャラクター・撃破数・奥義ゲージ（本数と次の1本までの量）は
-- Player の Attribute に持たせてクライアントへ自動で複製させる。出現時にキャラクターの能力値と仮の見た目を当て、
-- 使うキャラクター（CharacterId）が変わったら出現し直す。
-- 出撃では spawnAt が CharacterId を書いてから出撃地点に出現し直す（出現し直しは1回）。
-- ロビーへ戻っても CharacterId は書き換えないので、見た目は最後に出撃したキャラクターのまま残る。
-- 被弾による奥義ゲージの増加は DamageService の被ダメージの窓口が足す。
--
-- - Roblox の自動の出現（Players.CharacterAutoLoads）は止め、出現はここで行う
-- - キャラクターは衝突のグループ Player にする。敵の体とはぶつからない（CollisionGroups）
-- - 入室した人はロビーに出現する（出撃中に入った待機中の人も）
-- - 倒れた人（キャラクターが無い人を含む）は、Config.luau の Stage 節の秒数がたつと、
--   setRespawner で登録した関数で出現し直す。既定はロビー。出撃中のメンバーの行き先は StageService が決める

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Appearance = require(ReplicatedStorage.Shared.Appearance)
local Characters = require(ReplicatedStorage.Shared.Characters)
local Config = require(ReplicatedStorage.Shared.Config)
local Ground = require(ReplicatedStorage.Shared.Ground)
local OugiGauge = require(ReplicatedStorage.Shared.OugiGauge)
local Stats = require(ReplicatedStorage.Shared.Stats)
local CollisionGroups = require(script.Parent.Parent.CollisionGroups)
local DebugCommand = require(script.Parent.Parent.DebugCommand)

local PlayerService = {}

-- 出撃などで出現し直す前に、出現位置の周りを読み込ませるのを待つ秒数の上限
local STREAM_TIMEOUT = 5

-- 倒れた人を見回る間隔（秒）
local DOWN_CHECK_INTERVAL = 0.5

-- 今の姿（spawnAt で出現し直している間は、これから出現する姿）のキャラクター ID。
-- CharacterId の変化の通知は遅れて届くことがあるので、これと同じなら出現し直さない
local appliedCharacterIds: { [Player]: string } = {}
-- spawnAt か spawnInLobby で出現し直している最中の人
local spawning: { [Player]: boolean } = {}
-- 出現し直すたびに増やす番号。読み込みを待つ間に後から出現し直しが始まったら、古い方は途中でやめる
local spawnTokens: { [Player]: number } = {}
-- 倒れているのに気づいた時刻（os.clock）
local downSince: { [Player]: number } = {}
-- 倒れた人を出現し直させる関数。既定はロビー（start で入れる）
local respawner: ((Player) -> ())? = nil

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

-- 出撃したときの撃破数（0）と奥義ゲージ（OugiGauge.initial）に戻す
function PlayerService.resetForShutsugeki(player: Player)
	player:SetAttribute("Gekihasu", 0)
	setOugi(player, OugiGauge.initial())
end

-- 出現し直しを始める。番号を進めて返す
local function beginSpawn(player: Player): number
	local token = (spawnTokens[player] or 0) + 1
	spawnTokens[player] = token
	spawning[player] = true
	return token
end

-- 出現し直しを終える。後から別の出現し直しが始まっていれば、そちらに任せる
local function endSpawn(player: Player, token: number)
	if spawnTokens[player] == token then
		spawning[player] = nil
		downSince[player] = nil
	end
end

local function spawnAtNow(player: Player, cframe: CFrame, characterId: string?, token: number)
	local position = cframe.Position
	local streamed, streamError = pcall(function()
		player:RequestStreamAroundAsync(position, STREAM_TIMEOUT)
	end)
	if not streamed then
		warn(`PlayerService: {player.Name} の出現位置の周りを読み込めなかった: {streamError}`)
	end
	if not player.Parent or spawnTokens[player] ~= token then
		return
	end
	if characterId then
		appliedCharacterIds[player] = characterId
		player:SetAttribute("CharacterId", characterId)
	end
	local loaded, loadError = pcall(function()
		player:LoadCharacter()
	end)
	if spawnTokens[player] ~= token then
		return
	end
	local character = player.Character
	if not loaded or not character then
		warn(`PlayerService: {player.Name} を出現し直せなかった: {loadError}`)
		return
	end
	-- 出現し直すとロビーの SpawnLocation の ForceField が付く。出撃地点では無敵にしないので外す
	for _, child in character:GetChildren() do
		if child:IsA("ForceField") then
			child:Destroy()
		end
	end
	local look = cframe.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	local facing = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
	character:PivotTo(CFrame.lookAt(position, position + facing))
	Ground.placeCharacter(character, position.X, position.Z)
end

-- 出現し直して、cframe の位置に cframe の向き（水平の成分）で立たせる。高さは地面に合わせる。
-- characterId を渡すと、使うキャラクターをそれに変えてから出現し直す。
-- StreamingEnabled なので、先に出現位置の周りをクライアントへ読み込ませる。出現し直すまで待つ
function PlayerService.spawnAt(player: Player, cframe: CFrame, characterId: string?)
	local token = beginSpawn(player)
	local ok, err = pcall(spawnAtNow, player, cframe, characterId, token)
	endSpawn(player, token)
	if not ok then
		warn(`PlayerService: {player.Name} を出現し直せなかった: {err}`)
	end
end

-- ロビーの SpawnLocation に出現し直す。出現し直すまで待つ
function PlayerService.spawnInLobby(player: Player)
	if not player.Parent then
		return
	end
	local token = beginSpawn(player)
	local ok, err = pcall(function()
		player:LoadCharacter()
	end)
	endSpawn(player, token)
	if not ok then
		warn(`PlayerService: {player.Name} をロビーに出現し直せなかった: {err}`)
	end
end

-- 倒れた人を出現し直させる関数を登録する。登録した関数は、spawnAt か spawnInLobby で出現し直させる
function PlayerService.setRespawner(fn: (Player) -> ())
	respawner = fn
end

-- 倒れているか。キャラクターが無いか、体力が 0 か、Humanoid が Dead の状態か、HumanoidRootPart が無ければ
-- 倒れている（奈落に落ちて体の部品が消えた場合も含める）
local function isDown(player: Player): boolean
	local character = player.Character
	if not character or not character.Parent then
		return true
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil or humanoid.Health <= 0 or humanoid:GetState() == Enum.HumanoidStateType.Dead then
		return true
	end
	return character:FindFirstChild("HumanoidRootPart") == nil
end

-- 倒れてから Config.Stage.SaishutsugekiDelay 秒たった人を出現し直させる
local function checkDown()
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		if spawning[player] or not isDown(player) then
			downSince[player] = nil
			continue
		end
		local since = downSince[player]
		if not since then
			downSince[player] = now
		elseif now - since >= Config.Stage.SaishutsugekiDelay then
			downSince[player] = nil
			task.spawn(respawner or PlayerService.spawnInLobby, player)
		end
	end
end

local function onCharacterAdded(player: Player, character: Model)
	-- 敵の体とぶつからないグループにする（敵が上に乗って動けなくならないように）
	CollisionGroups.apply(character, CollisionGroups.PLAYER)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local stats = PlayerService.getStats(player)
	humanoid.WalkSpeed = stats.WalkSpeed
	humanoid.UseJumpPower = false
	humanoid.JumpHeight = Config.Jump.Height
	humanoid.MaxHealth = stats.MaxHealth
	humanoid.Health = stats.MaxHealth
	local characterId = PlayerService.getCharacterId(player)
	appliedCharacterIds[player] = characterId
	task.spawn(Appearance.applyToCharacter, character, characterId)
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
	else
		-- 自動の出現を止めているので、入室した人をロビーに出す（出撃中に入った待機中の人も）
		task.spawn(PlayerService.spawnInLobby, player)
	end
	-- 使うキャラクターが変わったら、能力値と見た目を当て直すために出現し直す。
	-- 今の姿がすでにそのキャラクターのとき（spawnAt が出現し直すときを含む）は何もしない
	player:GetAttributeChangedSignal("CharacterId"):Connect(function()
		if not player.Character or appliedCharacterIds[player] == PlayerService.getCharacterId(player) then
			return
		end
		player:LoadCharacter()
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
	-- 出現の場所とタイミングはここで決める。止める前に入室して自動で出現した人は、そのまま続ける
	Players.CharacterAutoLoads = false
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		appliedCharacterIds[player] = nil
		spawning[player] = nil
		spawnTokens[player] = nil
		downSince[player] = nil
	end)
	registerDebugCommands()
	task.spawn(function()
		while true do
			task.wait(DOWN_CHECK_INTERVAL)
			checkDown()
		end
	end)
end

return PlayerService
