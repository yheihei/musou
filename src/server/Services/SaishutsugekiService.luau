--!strict
-- 戦闘中に倒れた出撃メンバーの再出撃と、パーティーで共有する兵力を持つ。
-- 倒れて Config.luau の Stage 節の秒数がたつと（PlayerService.setRespawner）、兵站線につながった味方軍の拠点のうち、
-- 倒れた位置に一番近い拠点から再出撃させ、兵力を1使う。拠点の選び方は ReplicatedStorage.Shared.Saishutsugeki にある。
--
-- - 出撃（StageService.started）で兵力を Config.luau の Stage 節の Heiryoku に人数の倍率を掛けた数にし
--   （ReplicatedStorage.Shared.PartySize。人数は出撃したときの人数で、途中で抜けても変えない）、
--   workspace の Attribute の Heiryoku でクライアントへ複製する。ロビーのフェーズに戻ったら消す
-- - 兵力が0の状態で出撃メンバーが倒れたら、再出撃させずに heiryokuZero で知らせ、兵力0で負けにする
--   （StageService.finish）。勝敗の判定をまとめる処理（#109）ができたら、負けにするのはそちらへ移す
-- - 拠点の中では、出撃した順に東西へ並べ、倒れた位置の方を向かせる。高さは地面に合わせる（PlayerService.spawnAt）
-- - 再出撃する拠点が無いとき（配置の構成の無いステージなど）は、出撃地点から出す。兵力は使う
-- - 兵力を使うのは、戦闘のフェーズで倒れ、戦闘のフェーズのうちに再出撃するとき。倒れた1回につき1回だけ使い、
--   出現し直しに失敗して呼び直されたときは使わない
-- - 戦闘のフェーズの外で出現し直す出撃メンバーは、兵力を使わずに出撃地点から出す。
--   兵力0の負けにした人も、すぐに出撃地点から出す
-- - ロビーのフェーズの人と、出撃したメンバーでない人（待機中の人）はロビーに出す。仲間による蘇生は無い
-- - 倒れた位置とフェーズは、倒れたとき（Humanoid.Died）に覚える。位置が分からなければ出撃地点の位置で選ぶ

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PartySize = require(ReplicatedStorage.Shared.PartySize)
local Saishutsugeki = require(ReplicatedStorage.Shared.Saishutsugeki)
local StagePhase = require(ReplicatedStorage.Shared.StagePhase)
local DebugCommand = require(script.Parent.Parent.DebugCommand)
local HeitansenService = require(script.Parent.HeitansenService)
local KyotenService = require(script.Parent.KyotenService)
local PartyService = require(script.Parent.PartyService)
local PlayerService = require(script.Parent.PlayerService)
local StageService = require(script.Parent.StageService)

local SaishutsugekiService = {}

-- Humanoid を待つ秒数の上限
local HUMANOID_TIMEOUT = 10

-- 兵力。出撃していないときは nil
local heiryoku: number? = nil
-- 出撃したときの兵力（人数で増やした数）。出撃していないときは nil
local initialHeiryoku: number? = nil
-- このステージで兵力0の負けを知らせたか
local zeroNotified = false

-- 倒れたときの記録。位置は倒れたときの HumanoidRootPart の位置（分からなければ nil）、フェーズは倒れたときのフェーズ
type Fall = {
	position: Vector3?,
	phase: StagePhase.Phase,
}

-- 倒れて、まだ出現し直していない人の記録
local falls: { [Player]: Fall } = {}

local heiryokuZeroEvent = Instance.new("BindableEvent")
-- 兵力が0の状態で出撃メンバーが倒れたときに、倒れた Player で発火する。1回のステージで1回だけ
SaishutsugekiService.heiryokuZero = heiryokuZeroEvent.Event

-- 兵力。出撃していないときは nil
function SaishutsugekiService.getHeiryoku(): number?
	return heiryoku
end

-- 兵力を書き換えてクライアントへ複製する。nil で消す
function SaishutsugekiService.setHeiryoku(value: number?)
	heiryoku = if value then math.max(math.floor(value), 0) else nil
	workspace:SetAttribute(Saishutsugeki.HEIRYOKU_ATTRIBUTE, heiryoku)
end

-- 再出撃する拠点と、そこで立つ位置と向き。index は出撃した順、position は倒れた位置。拠点が無ければ nil
local function kyotenCFrame(index: number, position: Vector3): (string?, CFrame?)
	local candidates: { Saishutsugeki.KyotenInput } = {}
	for _, kyoten in KyotenService.list() do
		local center = KyotenService.centerOf(kyoten.id)
		if center then
			table.insert(candidates, {
				id = kyoten.id,
				gun = kyoten.gun,
				connected = HeitansenService.isConnected(kyoten.gun, kyoten.id),
				x = center.x,
				z = center.z,
			})
		end
	end
	local id = Saishutsugeki.chooseKyoten(candidates, "Mikatagun", position.X, position.Z)
	local center = if id then KyotenService.positionOf(id) else nil
	if not id or not center then
		return nil, nil
	end
	-- 高さは拠点の目印に合わせる（出現の前に周りを読み込ませる位置になる。足元は PlayerService.spawnAt が地面に合わせる）
	local spot = Vector3.new(center.X + Saishutsugeki.offsetOf(index), center.Y, center.Z)
	local facing = Vector3.new(position.X - spot.X, 0, position.Z - spot.Z)
	if facing.Magnitude < 1e-3 then
		facing = Vector3.new(0, 0, -1)
	end
	return id, CFrame.lookAt(spot, spot + facing.Unit)
end

local function spawnAtOrLobby(player: Player, cframe: CFrame?)
	if cframe then
		PlayerService.spawnAt(player, cframe)
	else
		PlayerService.spawnInLobby(player)
	end
end

-- 兵力0で倒れたら知らせて負けにする（1回のステージで1回だけ）
local function onHeiryokuZero(player: Player)
	if zeroNotified then
		return
	end
	zeroNotified = true
	heiryokuZeroEvent:Fire(player)
	-- 勝敗の判定をまとめる処理（#109）ができるまでは、ここで兵力0の負けにする
	StageService.finish(false, "HeiryokuZero")
end

-- 倒れた人を出現し直させる（PlayerService.setRespawner で登録する）
local function respawn(player: Player)
	-- 倒れた記録は1回だけ使う。出現し直しに失敗して呼び直されたときは記録が無いので、兵力を使わない
	local fall = falls[player]
	falls[player] = nil
	local phase = StageService.getPhase()
	local index = table.find(StageService.getMembers(), player)
	if phase == "Lobby" or not index or PartyService.isWaiting(player) then
		PlayerService.spawnInLobby(player)
		return
	end
	local shutsugekiChiten = StageService.shutsugekiCFrameOf(player)
	if phase ~= "Battle" then
		spawnAtOrLobby(player, shutsugekiChiten)
		return
	end
	if fall and fall.phase == "Battle" then
		local ok, rest = Saishutsugeki.consume(heiryoku or 0)
		if not ok then
			onHeiryokuZero(player)
			-- 負けにしたらイベントシーンとリザルトに出られるよう、出撃地点から出す
			if StageService.getPhase() ~= "Battle" then
				spawnAtOrLobby(player, shutsugekiChiten)
			end
			return
		end
		SaishutsugekiService.setHeiryoku(rest)
	end
	local position = (if fall then fall.position else nil)
		or (if shutsugekiChiten then shutsugekiChiten.Position else nil)
	local _, cframe = kyotenCFrame(index, position or Vector3.zero)
	spawnAtOrLobby(player, cframe or shutsugekiChiten)
end

-- 倒れたときの位置とフェーズを覚える
local function watchCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", HUMANOID_TIMEOUT) :: Humanoid?
	if not humanoid then
		return
	end
	humanoid.Died:Once(function()
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		falls[player] = { position = if root then root.Position else nil, phase = StageService.getPhase() }
	end)
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		watchCharacter(player, character)
	end)
	if player.Character then
		task.spawn(watchCharacter, player, player.Character)
	end
end

local function registerDebugCommands()
	DebugCommand.register(
		"SetHeiryoku",
		"<兵力>",
		"出撃中の兵力を書き換える（確認用）",
		function(value)
			if heiryoku == nil then
				return `出撃していないので書き換えなかった（フェーズ {StageService.getPhase()}）`
			end
			SaishutsugekiService.setHeiryoku(DebugCommand.toNumber(value, "兵力"))
			return `兵力を {heiryoku} にした`
		end
	)
	DebugCommand.register(
		"DumpHeiryoku",
		"[プレイヤー名]",
		"兵力と、プレイヤーを渡すと今の位置で倒れたときに再出撃する拠点を JSON で返す",
		function(name)
			local kyoten: string? = nil
			if name ~= nil then
				local player = DebugCommand.findPlayer(name)
				local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
				local index = table.find(StageService.getMembers(), player)
				if root and index then
					kyoten = kyotenCFrame(index, root.Position)
				end
			end
			return HttpService:JSONEncode({
				heiryoku = heiryoku,
				initial = initialHeiryoku,
				kyoten = kyoten,
				zero = zeroNotified,
			})
		end
	)
end

function SaishutsugekiService.start()
	PlayerService.setRespawner(respawn)
	StageService.started:Connect(function(info: StageService.StartInfo)
		zeroNotified = false
		table.clear(falls)
		initialHeiryoku = PartySize.heiryokuOf(Config.Stage.Heiryoku, info.partySize)
		SaishutsugekiService.setHeiryoku(initialHeiryoku)
	end)
	StageService.phaseChanged:Connect(function(next: StagePhase.Phase)
		if next == "Lobby" then
			initialHeiryoku = nil
			SaishutsugekiService.setHeiryoku(nil)
		end
	end)
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		falls[player] = nil
	end)
	registerDebugCommands()
end

return SaishutsugekiService
