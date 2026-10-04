--!strict
-- 上忍と首領をデータで持つ。出撃したステージの配置から作り、上忍は率いる部隊の位置に合わせ、首領は本陣の中心に置く。
-- 型と体力の計算は ReplicatedStorage.Shared.Jonin、能力値は Config.luau の Stats 節にある。
-- 個体（モデル）と、攻撃による被ダメージと撃破は #91 で作る。
--
-- - 出撃（StageService.started）で作り、決着とロビーのフェーズへの戻りで片付ける。配置の構成が無いステージでは作らない
-- - 敵軍の上忍と首領の体力は、出撃したときの人数（StartInfo.partySize）で上げる。途中で抜けても変えない
-- - 上忍の位置は、部隊を進める間隔（Config.luau の Butai 節）ごとに率いる部隊の位置へ合わせる。
--   戦闘のフェーズで部隊が消えていたら、率いる部隊を外してその場に残す
-- - 首領は本陣の範囲にとどまる。setPosition で範囲の外の位置を渡されたら、範囲の縁へ寄せる（Hoshin.clampToRange）
-- - 体力が 0 になった上忍は倒れる。率いていた部隊は残し、士気だけ下げる（ButaiService.loseJonin）
-- - 交戦中の部隊どうしが両方とも上忍に率いられていれば、部隊を進める間隔ごとに上忍同士も戦わせる
--   （ReplicatedStorage.Shared.Kosen の joninStep。味方軍の上忍は士気の差がしきい値以上のときだけ削れる）
-- - 部隊を進める間隔ごとに、上忍と首領が自分の軍の支配エリアの中かを確かめ、中なら攻撃と防御を上げる（Jonin.setShihaiArea）。
--   中かどうかは ShihaiAreaService が setShihaiAreaProvider で渡す関数で引き、関数が無ければ外とみなす
-- - 上忍と首領ごとに ReplicatedStorage.Jonin の下へキャラクター ID の名前で Configuration を置き、Attribute で
--   位置（Position。Vector2 の X と Y にワールドの X と Z）・体力（Health・MaxHealth）・軍（Gun）・
--   率いる部隊（Butai）・首領か（Shuryo）・名前（DisplayName）をクライアントへ複製する

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Butai = require(ReplicatedStorage.Shared.Butai)
local Config = require(ReplicatedStorage.Shared.Config)
local Gun = require(ReplicatedStorage.Shared.Gun)
local Haichi = require(ReplicatedStorage.Shared.Haichi)
local Hoshin = require(ReplicatedStorage.Shared.Hoshin)
local Jonin = require(ReplicatedStorage.Shared.Jonin)
local Kosen = require(ReplicatedStorage.Shared.Kosen)
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
-- 首領のキャラクター ID から引く、とどまる本陣の範囲（目印のパーツの中心・向き・大きさ）
local honjinRangeOf: { [string]: { cframe: CFrame, size: Vector3 } } = {}

-- 軍と位置を受け、その軍の支配エリアの中かを返す関数（ShihaiAreaService が渡す）
local shihaiAreaProvider: ((gun: Gun.Gun, position: Jonin.Point) -> boolean)? = nil

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

-- 軍と位置を受け、その軍の支配エリアの中かを返す関数を登録する
function JoninService.setShihaiAreaProvider(provider: (gun: Gun.Gun, position: Jonin.Point) -> boolean)
	shihaiAreaProvider = provider
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

-- 位置を書き換えて複製する。首領は本陣の範囲の外へ出さず、範囲の縁へ寄せる。いなければ false
function JoninService.setPosition(id: string, position: Jonin.Point): boolean
	local jonin = find(id)
	if not jonin then
		return false
	end
	local x, z = position.x, position.z
	local range = if jonin.shuryo then honjinRangeOf[jonin.id] else nil
	if range then
		local offset = range.cframe:PointToObjectSpace(Vector3.new(x, range.cframe.Position.Y, z))
		local localX, localZ = Hoshin.clampToRange(offset.X, offset.Z, range.size.X, range.size.Z)
		local world = range.cframe:PointToWorldSpace(Vector3.new(localX, 0, localZ))
		x, z = world.X, world.Z
	end
	jonin.position = { x = x, z = z }
	publish(jonin)
	return true
end

local function clear()
	table.clear(joninList)
	table.clear(honjinRangeOf)
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
	local ranges: { [string]: { cframe: CFrame, size: Vector3 } } = {}
	for _, kyoten in loaded.kyoten do
		local position = kyoten.cframe.Position
		centers[kyoten.id] = { x = position.X, z = position.Z }
		ranges[kyoten.id] = { cframe = kyoten.cframe, size = kyoten.size }
	end
	for _, entry in Jonin.entriesOf(haichi, stage) do
		local position = centers[entry.kyoten]
		if not position then
			warn(`JoninService: {entry.id} のいる拠点 {entry.kyoten} の目印が無いので出さない`)
			continue
		end
		local jonin = Jonin.new(entry, position, info.partySize)
		table.insert(joninList, jonin)
		if entry.shuryo then
			honjinRangeOf[entry.id] = ranges[entry.kyoten]
		end
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

-- 上忍と首領が自分の軍の支配エリアの中かを確かめ、変わったら能力値を求め直す。倒れた上忍は外にいるものとする
local function refreshShihaiArea()
	local provider = shihaiAreaProvider
	for _, jonin in joninList do
		local inside = not Jonin.isDefeated(jonin) and provider ~= nil and provider(jonin.gun, jonin.position)
		Jonin.setShihaiArea(jonin, inside)
	end
end

local function joninSide(jonin: Jonin.Jonin, butai: Butai.Butai): Kosen.JoninSide
	return {
		gun = jonin.gun,
		health = jonin.health,
		attack = jonin.stats.Attack,
		defense = jonin.stats.Defense,
		shiki = butai.shiki,
	}
end

-- 交戦中の部隊どうしが両方とも上忍に率いられていれば、上忍同士を dt 秒戦わせる。戦闘のフェーズの外では戦わせない
local function fightJonin(dt: number)
	if StageService.getPhase() ~= "Battle" or dt <= 0 then
		return
	end
	local fought: { [string]: boolean } = {}
	for _, jonin in table.clone(joninList) do
		local butaiId = jonin.butai
		if not butaiId or fought[jonin.id] or Jonin.isDefeated(jonin) then
			continue
		end
		local butai = ButaiService.get(butaiId)
		local aiteId = ButaiService.aiteOf(butaiId)
		local aite = if aiteId then ButaiService.get(aiteId) else nil
		local other = if aite and aite.jonin then find(aite.jonin) else nil
		if not butai or not aite or not other or other.butai ~= aite.id or Jonin.isDefeated(other) then
			continue
		end
		fought[jonin.id] = true
		fought[other.id] = true
		local result = Kosen.joninStep(joninSide(jonin, butai), joninSide(other, aite), dt)
		if result.a ~= jonin.health then
			JoninService.setHealth(jonin.id, result.a)
		end
		if result.b ~= other.health then
			JoninService.setHealth(other.id, result.b)
		end
	end
end

local function round(value: number): number
	return math.round(value * 10) / 10
end

local function registerDebugCommands()
	DebugCommand.register(
		"DumpJonin",
		"",
		"出撃したステージの上忍と首領（体力・攻撃・防御・支配エリアの中か・位置）を JSON で返す",
		function()
			local result = {}
			for _, jonin in joninList do
				table.insert(result, {
					id = jonin.id,
					name = jonin.displayName,
					gun = jonin.gun,
					shuryo = jonin.shuryo,
					butai = jonin.butai,
					kyoten = jonin.kyoten,
					health = round(jonin.health),
					maxHealth = round(jonin.stats.MaxHealth),
					attack = round(jonin.stats.Attack),
					defense = round(jonin.stats.Defense),
					shihaiArea = jonin.shihaiArea,
					position = { round(jonin.position.x), round(jonin.position.z) },
				})
			end
			return HttpService:JSONEncode(result)
		end
	)
	DebugCommand.register(
		"SetJoninPosition",
		"<キャラクター ID> <x> <z>",
		"上忍か首領の位置を書き換える。首領は本陣の範囲の外へ出さず、範囲の縁へ寄せる。上忍は次の間隔で率いる部隊の位置へ戻る（確認用）",
		function(id, x, z)
			local position = { x = DebugCommand.toNumber(x, "x"), z = DebugCommand.toNumber(z, "z") }
			if type(id) ~= "string" or not JoninService.setPosition(id, position) then
				return `{tostring(id)} は出撃したステージの上忍と首領にいない`
			end
			local jonin = find(id) :: Jonin.Jonin
			return `{jonin.displayName} の位置を ({round(jonin.position.x)}, {round(jonin.position.z)}) にした`
		end
	)
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
		local last = os.clock()
		while true do
			task.wait(Config.Butai.MoveInterval)
			local now = os.clock()
			-- 1回の失敗で追従と戦いが止まらないよう、失敗は警告にして次の間隔で続ける
			local ok, err = pcall(follow)
			if not ok then
				warn(`JoninService: 上忍を部隊に合わせられなかった: {err}`)
			end
			local areaOk, areaErr = pcall(refreshShihaiArea)
			if not areaOk then
				warn(`JoninService: 支配エリアの補正を求め直せなかった: {areaErr}`)
			end
			local fightOk, fightErr = pcall(fightJonin, now - last)
			if not fightOk then
				warn(`JoninService: 上忍同士を戦わせられなかった: {fightErr}`)
			end
			last = now
		end
	end)
end

return JoninService
