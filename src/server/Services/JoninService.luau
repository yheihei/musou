--!strict
-- 上忍と首領をデータで持つ。出撃したステージの配置から作り、上忍は率いる部隊の位置に合わせ、首領は本陣の中心に置く。
-- 型と体力の計算は ReplicatedStorage.Shared.Jonin、能力値は Config.luau の Stats 節にある。
-- 個体（モデル）と、攻撃による被ダメージと撃破は #91 で作る。
--
-- - 出撃（StageService.started）で作り、決着とロビーのフェーズへの戻りで片付ける。配置の構成が無いステージでは作らない
-- - 上忍の位置は、部隊を進める間隔（Config.luau の Butai 節）ごとに率いる部隊の位置へ合わせる。
--   戦闘のフェーズで部隊が消えていたら、率いる部隊を外してその場に残す
-- - 体力が 0 になった上忍は倒れる。率いていた部隊は残し、士気だけ下げる（ButaiService.loseJonin）
-- - 上忍と首領ごとに ReplicatedStorage.Jonin の下へキャラクター ID の名前で Configuration を置き、Attribute で
--   位置（Position。Vector2 の X と Y にワールドの X と Z）・体力（Health・MaxHealth）・軍（Gun）・
--   率いる部隊（Butai）・首領か（Shuryo）・名前（DisplayName）をクライアントへ複製する

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Haichi = require(ReplicatedStorage.Shared.Haichi)
local Jonin = require(ReplicatedStorage.Shared.Jonin)
local StagePhase = require(ReplicatedStorage.Shared.StagePhase)
local Stages = require(ReplicatedStorage.Shared.Stages)
local DebugCommand = require(script.Parent.Parent.DebugCommand)
local ButaiService = require(script.Parent.ButaiService)
local HaichiService = require(script.Parent.HaichiService)
local StageService = require(script.Parent.StageService)

local JoninService = {}

-- 上忍と首領の Attribute を置くフォルダ（ReplicatedStorage の下）の名前
JoninService.FOLDER = "Jonin"

-- 出撃したステージの上忍と首領（配置の構成の順）
local joninList: { Jonin.Jonin } = {}
local folder: Folder

local defeatedEvent = Instance.new("BindableEvent")
-- 上忍か首領が倒れたときに、そのキャラクター ID で発火する
JoninService.defeated = defeatedEvent.Event

local function find(id: string): Jonin.Jonin?
	for _, jonin in joninList do
		if jonin.id == id then
			return jonin
		end
	end
	return nil
end

function JoninService.get(id: string): Jonin.Jonin?
	return find(id)
end

-- 出撃したステージの上忍と首領の一覧（表は写し。上忍の表はそのもの）
function JoninService.list(): { Jonin.Jonin }
	return table.clone(joninList)
end

-- 今の状態を Attribute に書いてクライアントへ複製する
local function publish(jonin: Jonin.Jonin)
	local state = folder:FindFirstChild(jonin.id)
	if not state then
		local created = Instance.new("Configuration")
		created.Name = jonin.id
		created.Parent = folder
		state = created
	end
	local instance = state :: Instance
	instance:SetAttribute("DisplayName", jonin.displayName)
	instance:SetAttribute("Gun", jonin.gun)
	instance:SetAttribute("Shuryo", jonin.shuryo)
	instance:SetAttribute("Butai", jonin.butai)
	instance:SetAttribute("Position", Vector2.new(jonin.position.x, jonin.position.z))
	instance:SetAttribute("Health", jonin.health)
	instance:SetAttribute("MaxHealth", jonin.stats.MaxHealth)
end

-- 体力を書き換える。倒れたら、率いていた部隊は残して士気だけ下げる。いなければ false
function JoninService.setHealth(id: string, value: number): boolean
	local jonin = find(id)
	if not jonin then
		return false
	end
	local defeated = Jonin.setHealth(jonin, value)
	if defeated then
		local butai = jonin.butai
		jonin.butai = nil
		if butai then
			ButaiService.loseJonin(butai)
		end
	end
	publish(jonin)
	if defeated then
		defeatedEvent:Fire(jonin.id)
	end
	return true
end

local function clear()
	table.clear(joninList)
	folder:ClearAllChildren()
end

-- 出撃したステージの配置から上忍と首領を作る。配置の構成が無いステージでは作らない
local function onStarted(info: StageService.StartInfo)
	clear()
	local stage = Stages.get(info.stageId)
	local haichi = Haichi.get(info.stageId)
	if not stage or not haichi then
		return
	end
	local loaded = HaichiService.load(info.stageId)
	if not loaded then
		return
	end
	local centers: { [string]: Jonin.Point } = {}
	for _, kyoten in loaded.kyoten do
		local position = kyoten.cframe.Position
		centers[kyoten.id] = { x = position.X, z = position.Z }
	end
	for _, entry in Jonin.entriesOf(haichi, stage) do
		local position = centers[entry.kyoten]
		if not position then
			warn(`JoninService: {entry.id} のいる拠点 {entry.kyoten} の目印が無いので出さない`)
			continue
		end
		local jonin = Jonin.new(entry, position)
		table.insert(joninList, jonin)
		publish(jonin)
	end
end

-- 倒れていない上忍を、率いる部隊の位置へ合わせる。戦闘のフェーズで部隊が消えていたら、率いる部隊を外してその場に残す
local function follow()
	local battle = StageService.getPhase() == "Battle"
	for _, jonin in joninList do
		local id = jonin.butai
		if not id or Jonin.isDefeated(jonin) then
			continue
		end
		local butai = ButaiService.get(id)
		if not butai then
			if battle then
				jonin.butai = nil
				publish(jonin)
			end
		elseif butai.position.x ~= jonin.position.x or butai.position.z ~= jonin.position.z then
			jonin.position = { x = butai.position.x, z = butai.position.z }
			publish(jonin)
		end
	end
end

local function round(value: number): number
	return math.round(value * 10) / 10
end

local function registerDebugCommands()
	DebugCommand.register("DumpJonin", "", "出撃したステージの上忍と首領を JSON で返す", function()
		local result = {}
		for _, jonin in joninList do
			table.insert(result, {
				id = jonin.id,
				name = jonin.displayName,
				gun = jonin.gun,
				shuryo = jonin.shuryo,
				butai = jonin.butai,
				kyoten = jonin.kyoten,
				health = jonin.health,
				maxHealth = jonin.stats.MaxHealth,
				position = { round(jonin.position.x), round(jonin.position.z) },
			})
		end
		return HttpService:JSONEncode(result)
	end)
	DebugCommand.register(
		"SetJoninHealth",
		"<キャラクター ID> <体力>",
		"上忍か首領の体力を書き換える。0 にすると倒れ、率いていた部隊の士気が下がる（確認用）",
		function(id, value)
			local health = DebugCommand.toNumber(value, "体力")
			if type(id) ~= "string" or not JoninService.setHealth(id, health) then
				return `{tostring(id)} は出撃したステージの上忍と首領にいない`
			end
			local jonin = find(id) :: Jonin.Jonin
			local state = if Jonin.isDefeated(jonin) then "（倒れた）" else ""
			return `{jonin.displayName} の体力を {jonin.health} / {jonin.stats.MaxHealth} にした{state}`
		end
	)
end

function JoninService.start()
	local created = Instance.new("Folder")
	created.Name = JoninService.FOLDER
	created.Parent = ReplicatedStorage
	folder = created

	StageService.started:Connect(onStarted)
	StageService.finished:Connect(clear)
	StageService.phaseChanged:Connect(function(next: StagePhase.Phase)
		if next == "Lobby" then
			clear()
		end
	end)
	registerDebugCommands()

	task.spawn(function()
		while true do
			task.wait(Config.Butai.MoveInterval)
			-- 1回の失敗で追従が止まらないよう、失敗は警告にして次の間隔で続ける
			local ok, err = pcall(follow)
			if not ok then
				warn(`JoninService: 上忍を部隊に合わせられなかった: {err}`)
			end
		end
	end)
end

return JoninService
