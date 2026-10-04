--!strict
-- 戦場の部隊をデータで持つ（ADR 0003）。出撃したステージの配置（HaichiService）から部隊を作り、
-- 戦闘のフェーズの間、目的地へ向けて経由点をたどって位置だけを進める。下忍の個体はまだ出さない（#76）。
-- 移動の計算は ReplicatedStorage.Shared.Butai、速さ・間隔・士気の初期値は Config.luau の Butai 節にある。
--
-- - 出撃（StageService.started）で、配置の部隊を開始時の拠点の中心に作る。配置の構成が無いステージでは作らない。
--   目的地は持たせない（方針に沿って動かすのは #102）
-- - 決着（StageService.finished）とロビーのフェーズへの戻りで片付ける
-- - 部隊ごとに ReplicatedStorage.Butai の下へ部隊 ID の名前で Configuration を置き、Attribute で
--   位置（Position。Vector2 の X と Y にワールドの X と Z）・軍（Gun）・兵数（Heisu）・士気（Shiki）・
--   率いる上忍（Jonin）をクライアントへ複製する
-- - 士気は ShikiService が setShikiProvider で渡す関数で、部隊を進める間隔ごとに交戦の計算の前で求め直す。
--   関数が無ければ、Config.luau の Shiki 節の開始時の値のまま（率いる上忍を失うと下がる）
-- - 窓口の ShowButai で、部隊の位置に軍の色の柱と、部隊 ID と兵数を出す（確認用）
-- - 敵味方の部隊が Config.luau の Kosen 節の StartDistance まで近づくと交戦を始め、両部隊はその場で止まる。
--   相手は1部隊ずつで、交戦中の敵の部隊に近づいた部隊はその手前で待つ（組み方は ReplicatedStorage.Shared.Kosen の match）。
--   交戦中は部隊を進める間隔ごとに Kosen.step で押し合わせて兵数を減らし、兵数 0 の部隊は消す。
--   決着したら残った部隊は目的地へ向けて動き出す。交戦の相手は Attribute の Kosen（相手の部隊 ID）で複製する
-- - 兵数が減ったら（交戦と changeHeisu）、heisuLost で部隊 ID・軍・減った兵数・その時の位置を知らせる。
--   拠点の耐久（KyotenService）はこれを受けて減る
-- - 交戦の押す力には、部隊のいる地点の支配エリアの倍率を掛ける。倍率は ShihaiAreaService が
--   setShihaiAreaProvider で渡す関数で引き、関数が無ければ 1

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Butai = require(ReplicatedStorage.Shared.Butai)
local Colors = require(ReplicatedStorage.Shared.Colors)
local Config = require(ReplicatedStorage.Shared.Config)
local Ground = require(ReplicatedStorage.Shared.Ground)
local Gun = require(ReplicatedStorage.Shared.Gun)
local Haichi = require(ReplicatedStorage.Shared.Haichi)
local Kosen = require(ReplicatedStorage.Shared.Kosen)
local StagePhase = require(ReplicatedStorage.Shared.StagePhase)
local DebugCommand = require(script.Parent.Parent.DebugCommand)
local HaichiService = require(script.Parent.HaichiService)
local StageService = require(script.Parent.StageService)

-- 部隊を足すときの中身
export type AddSpec = {
	-- 部隊 ID。省くと Tsuika1、Tsuika2… を振る
	id: string?,
	gun: Gun.Gun,
	heisu: number,
	position: Butai.Point,
	jonin: string?,
	-- 今いる拠点
	kyoten: string?,
}

-- 交戦中の組。端数は Kosen.step が次の計算へ持ち越す損害
type KosenState = {
	a: string,
	b: string,
	fractionA: number,
	fractionB: number,
	-- 交戦を始めた時刻（os.clock）
	startedAt: number,
}

local ButaiService = {}

-- 部隊の Attribute を置くフォルダ（ReplicatedStorage の下）の名前
ButaiService.FOLDER = "Butai"

-- 確認用の柱の大きさ（スタッド）
local MARKER_HEIGHT = 14
local MARKER_WIDTH = 6
-- 士気をこれ未満しか変えないときは複製し直さない
local SHIKI_EPSILON = 0.01

-- 足した順の部隊
local butaiList: { Butai.Butai } = {}
-- 出撃したステージの配置。拠点の中心とつながりの経由点を引く
local haichi: HaichiService.Loaded? = nil
local folder: Folder
local markerFolder: Folder? = nil
local showMarkers = false
-- 窓口で足す部隊に振る番号
local nextTsuika = 1
-- 交戦中の組と、部隊 ID から引く交戦の相手
local kosenList: { KosenState } = {}
local aiteOf: { [string]: string } = {}
-- 交戦中の敵の部隊の手前で待っている部隊
local waiting: { [string]: boolean } = {}
-- 部隊の今の士気を返す関数（ShikiService が渡す）
local shikiProvider: ((Butai.Butai) -> number)? = nil
-- 部隊の交戦の押す力に掛ける支配エリアの倍率を返す関数（ShihaiAreaService が渡す）
local shihaiAreaProvider: ((Butai.Butai) -> number)? = nil

local kosenStartedEvent = Instance.new("BindableEvent")
-- 交戦を始めたときに、2つの部隊 ID で発火する
ButaiService.kosenStarted = kosenStartedEvent.Event
local kosenSettledEvent = Instance.new("BindableEvent")
-- 交戦が決着したときに、2つの部隊 ID と勝者（Kosen.Winner の A・B・Draw）で発火する。
-- 兵数 0 の部隊は同じ間隔のうちに消すので、受け取った時点で ButaiService.get が nil を返すことがある
ButaiService.kosenSettled = kosenSettledEvent.Event
local heisuLostEvent = Instance.new("BindableEvent")
-- 部隊の兵数が減ったときに、部隊 ID・軍・減った兵数・減ったときの位置（Butai.Point）で発火する。
-- 兵数 0 になった部隊は同じ間隔のうちに消すので、受け取った時点で ButaiService.get が nil を返すことがある
ButaiService.heisuLost = heisuLostEvent.Event

local function find(id: string): (Butai.Butai?, number?)
	for index, butai in butaiList do
		if butai.id == id then
			return butai, index
		end
	end
	return nil, nil
end

local function pointOf(position: Vector3): Butai.Point
	return { x = position.X, z = position.Z }
end

-- 拠点の中心。出撃したステージの配置に無ければ nil
function ButaiService.kyotenPosition(kyotenId: string): Butai.Point?
	local loaded = haichi
	if not loaded then
		return nil
	end
	for _, kyoten in loaded.kyoten do
		if kyoten.id == kyotenId then
			return pointOf(kyoten.cframe.Position)
		end
	end
	return nil
end

-- 出撃したステージのつながりを、経由点を Butai.Point にして返す
local function tsunagariList(): { Butai.Tsunagari }
	local result = {}
	local loaded = haichi
	if loaded then
		for _, tsunagari in loaded.tsunagari do
			local keiyuten = {}
			for _, point in tsunagari.keiyuten do
				table.insert(keiyuten, pointOf(point))
			end
			table.insert(result, { kyotenA = tsunagari.kyotenA, kyotenB = tsunagari.kyotenB, keiyuten = keiyuten })
		end
	end
	return result
end

local function updateMarker(butai: Butai.Butai)
	local container = markerFolder
	if not container then
		return
	end
	local marker = container:FindFirstChild(butai.id) :: Part?
	if not marker then
		local created = Instance.new("Part")
		created.Name = butai.id
		created.Anchored = true
		created.CanCollide = false
		created.CanTouch = false
		created.CanQuery = false
		created.CastShadow = false
		created.Material = Enum.Material.Neon
		created.Transparency = 0.3
		created.Size = Vector3.new(MARKER_WIDTH, MARKER_HEIGHT, MARKER_WIDTH)
		created.Color = Colors.Gun[butai.gun]
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "Label"
		billboard.Size = UDim2.fromOffset(160, 40)
		billboard.StudsOffsetWorldSpace = Vector3.new(0, MARKER_HEIGHT / 2 + 3, 0)
		billboard.AlwaysOnTop = true
		local label = Instance.new("TextLabel")
		label.Name = "Text"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextStrokeTransparency = 0.3
		label.Parent = billboard
		billboard.Parent = created
		created.Parent = container
		marker = created
	end
	local part = marker :: Part
	local y = Ground.heightAt(butai.position.x, butai.position.z) or 0
	-- 回さずに立てる（BillboardGui の StudsOffsetWorldSpace をパーツの向きに左右されないようにする）
	part.CFrame = CFrame.new(butai.position.x, y + MARKER_HEIGHT / 2, butai.position.z)
	local label = part:FindFirstChild("Label")
	local text = label and label:FindFirstChild("Text")
	if text and text:IsA("TextLabel") then
		text.Text = `{butai.id} {butai.heisu}`
	end
end

-- 部隊の今の状態を Attribute に書いてクライアントへ複製する。確認用の柱を出していれば動かす
local function publish(butai: Butai.Butai)
	local state = folder:FindFirstChild(butai.id)
	if not state then
		local created = Instance.new("Configuration")
		created.Name = butai.id
		created.Parent = folder
		state = created
	end
	local instance = state :: Instance
	instance:SetAttribute("Gun", butai.gun)
	instance:SetAttribute("Position", Vector2.new(butai.position.x, butai.position.z))
	instance:SetAttribute("Heisu", butai.heisu)
	instance:SetAttribute("Shiki", butai.shiki)
	instance:SetAttribute("Jonin", butai.jonin)
	instance:SetAttribute("Kosen", aiteOf[butai.id])
	if showMarkers then
		updateMarker(butai)
	end
end

local function unpublish(id: string)
	local state = folder:FindFirstChild(id)
	if state then
		state:Destroy()
	end
	local container = markerFolder
	local marker = container and container:FindFirstChild(id)
	if marker then
		marker:Destroy()
	end
end

-- 部隊を足す。同じ ID の部隊がいれば足さずに nil を返す
function ButaiService.add(spec: AddSpec): Butai.Butai?
	local id = spec.id
	if not id then
		while find(`Tsuika{nextTsuika}`) do
			nextTsuika += 1
		end
		id = `Tsuika{nextTsuika}`
		nextTsuika += 1
	end
	local butaiId = id :: string
	if find(butaiId) then
		warn(`ButaiService: 部隊 {butaiId} はすでにいる`)
		return nil
	end
	local butai: Butai.Butai = {
		id = butaiId,
		gun = spec.gun,
		position = { x = spec.position.x, z = spec.position.z },
		heisu = math.max(math.floor(spec.heisu), 0),
		shiki = Config.Shiki.Initial,
		shikiHosei = 0,
		jonin = spec.jonin,
		mokutekichi = nil,
		keiyuten = {},
		kyoten = spec.kyoten,
		mokutekiKyoten = nil,
	}
	local provider = shikiProvider
	if provider then
		butai.shiki = provider(butai)
	end
	table.insert(butaiList, butai)
	publish(butai)
	return butai
end

-- 部隊の今の士気を返す関数を登録する。部隊を進める間隔ごとに、交戦の計算の前で全部隊の士気を求め直す
function ButaiService.setShikiProvider(provider: (Butai.Butai) -> number)
	shikiProvider = provider
end

-- 部隊の交戦の押す力に掛ける支配エリアの倍率を返す関数を登録する
function ButaiService.setShihaiAreaProvider(provider: (Butai.Butai) -> number)
	shihaiAreaProvider = provider
end

-- 部隊の交戦の押す力に掛ける支配エリアの倍率。関数が無ければ 1
function ButaiService.shihaiAreaOf(butai: Butai.Butai): number
	local provider = shihaiAreaProvider
	return if provider then provider(butai) else 1
end

-- 部隊 ID の交戦をやめさせる。相手の部隊は交戦していない状態に戻す
local function stopKosen(id: string)
	for index = #kosenList, 1, -1 do
		local state = kosenList[index]
		if state.a == id or state.b == id then
			table.remove(kosenList, index)
			aiteOf[state.a] = nil
			aiteOf[state.b] = nil
			local other = find(if state.a == id then state.b else state.a)
			if other then
				publish(other)
			end
		end
	end
	waiting[id] = nil
end

-- 部隊を外す。交戦中なら相手の部隊を交戦していない状態に戻す。いなければ false
function ButaiService.remove(id: string): boolean
	local _, index = find(id)
	if not index then
		return false
	end
	table.remove(butaiList, index)
	stopKosen(id)
	unpublish(id)
	return true
end

-- 交戦の相手の部隊 ID。交戦していなければ nil
function ButaiService.aiteOf(id: string): string?
	return aiteOf[id]
end

function ButaiService.get(id: string): Butai.Butai?
	return (find(id))
end

-- 足した順の部隊の一覧（表は写し。部隊の表はそのもの）
function ButaiService.list(): { Butai.Butai }
	return table.clone(butaiList)
end

-- 兵数が減ったことを知らせる
local function notifyLost(butai: Butai.Butai, loss: number)
	if loss > 0 then
		heisuLostEvent:Fire(butai.id, butai.gun, loss, { x = butai.position.x, z = butai.position.z })
	end
end

-- 兵数を delta だけ増減する。増減した後の兵数を返す。部隊がいなければ nil。減ったら heisuLost で知らせる
function ButaiService.changeHeisu(id: string, delta: number): number?
	local butai = find(id)
	if not butai then
		return nil
	end
	local before = butai.heisu
	local heisu = Butai.changeHeisu(butai, delta)
	publish(butai)
	notifyLost(butai, before - heisu)
	return heisu
end

-- 率いる上忍を失わせる。部隊は残し、士気だけを Config.luau の Butai 節の JoninGekihaShiki 下げる。部隊がいなければ false
function ButaiService.loseJonin(id: string): boolean
	local butai = find(id)
	if not butai then
		return false
	end
	Butai.loseJonin(butai, Config.Butai.JoninGekihaShiki)
	publish(butai)
	return true
end

-- 目的地を差し替える。mokutekichi を nil にすると、その場で止まる。部隊がいなければ false
function ButaiService.setMokutekichi(
	id: string,
	mokutekichi: Butai.Point?,
	keiyuten: { Butai.Point }?,
	kyoten: string?
): boolean
	local butai = find(id)
	if not butai then
		return false
	end
	Butai.setMokutekichi(butai, mokutekichi, keiyuten, kyoten)
	return true
end

-- 拠点へ向かわせる。今いる拠点とつながりで結ばれていれば道の経由点をたどり、結ばれていなければまっすぐ向かう。
-- 部隊がいないか、拠点が出撃したステージの配置に無ければ false
function ButaiService.moveToKyoten(id: string, kyotenId: string): boolean
	local butai = find(id)
	local target = ButaiService.kyotenPosition(kyotenId)
	if not butai or not target then
		return false
	end
	local keiyuten = if butai.kyoten then Butai.keiyutenBetween(tsunagariList(), butai.kyoten, kyotenId) else nil
	Butai.setMokutekichi(butai, target, keiyuten or {}, kyotenId)
	return true
end

-- 部隊をすべて片付ける
local function clear()
	table.clear(butaiList)
	table.clear(kosenList)
	table.clear(aiteOf)
	table.clear(waiting)
	folder:ClearAllChildren()
	local container = markerFolder
	if container then
		container:ClearAllChildren()
	end
	haichi = nil
	nextTsuika = 1
end

-- 出撃したステージの配置から部隊を作る。配置の構成が無いステージでは作らない
local function onStarted(info: StageService.StartInfo)
	clear()
	if not Haichi.get(info.stageId) then
		return
	end
	local loaded = HaichiService.load(info.stageId)
	if not loaded then
		return
	end
	haichi = loaded
	for _, entry in loaded.butai do
		local position = ButaiService.kyotenPosition(entry.kyoten)
		if not position then
			warn(
				`ButaiService: 部隊 {entry.id} の開始時の拠点 {entry.kyoten} の目印が無いので出さない`
			)
			continue
		end
		local heisu = Haichi.heisuOf(info.stageId, entry.id)
		if not heisu or heisu <= 0 then
			warn(`ButaiService: 部隊 {entry.id} の兵数が Config.Butai.Heisu に無いので出さない`)
			continue
		end
		ButaiService.add({
			id = entry.id,
			gun = entry.gun,
			heisu = heisu,
			position = position,
			jonin = entry.jonin,
			kyoten = entry.kyoten,
		})
	end
end

local function sideOf(butai: Butai.Butai, fraction: number): Kosen.Side
	return {
		heisu = butai.heisu,
		fraction = fraction,
		shiki = butai.shiki,
		strength = Config.Kosen.GunStrength[butai.gun],
		shihaiArea = ButaiService.shihaiAreaOf(butai),
	}
end

-- 交戦中の組を dt 秒押し合わせ、兵数に反映する。決着した組は交戦をやめさせ、
-- 兵数の減少と決着は一覧を回し終えてから知らせる
local function fightAll(dt: number)
	local settled: { { a: string, b: string, winner: Kosen.Winner? } } = {}
	local losses: { { butai: Butai.Butai, loss: number } } = {}
	for _, state in table.clone(kosenList) do
		local a, b = find(state.a), find(state.b)
		if not a or not b then
			continue
		end
		local result = Kosen.step(sideOf(a, state.fractionA), sideOf(b, state.fractionB), dt)
		a.heisu = result.a.heisu
		b.heisu = result.b.heisu
		table.insert(losses, { butai = a, loss = result.a.loss })
		table.insert(losses, { butai = b, loss = result.b.loss })
		state.fractionA = result.a.fraction
		state.fractionB = result.b.fraction
		if result.settled then
			local index = table.find(kosenList, state)
			if index then
				table.remove(kosenList, index)
			end
			aiteOf[a.id] = nil
			aiteOf[b.id] = nil
			table.insert(settled, { a = a.id, b = b.id, winner = result.winner })
		end
		publish(a)
		publish(b)
	end
	for _, item in losses do
		notifyLost(item.butai, item.loss)
	end
	for _, item in settled do
		kosenSettledEvent:Fire(item.a, item.b, item.winner)
	end
end

-- 兵数 0 の部隊を消す
local function removeDefeated()
	local defeated = {}
	for _, butai in butaiList do
		if butai.heisu <= 0 then
			table.insert(defeated, butai.id)
		end
	end
	for _, id in defeated do
		ButaiService.remove(id)
	end
end

-- 全部隊の士気を求め直し、変わった部隊を複製する
local function refreshShiki()
	local provider = shikiProvider
	if not provider then
		return
	end
	for _, butai in butaiList do
		local shiki = provider(butai)
		if math.abs(shiki - butai.shiki) >= SHIKI_EPSILON then
			butai.shiki = shiki
			publish(butai)
		end
	end
end

-- 交戦していない部隊どうしで、近づいた敵味方に交戦を始めさせ、交戦中の敵の手前の部隊を待たせる
local function matchAll()
	local units: { Kosen.Unit } = {}
	local engaged: { [string]: boolean } = {}
	for _, butai in butaiList do
		table.insert(units, { id = butai.id, gun = butai.gun, position = butai.position })
		if aiteOf[butai.id] then
			engaged[butai.id] = true
		end
	end
	local match = Kosen.match(units, engaged, Config.Kosen.StartDistance)
	waiting = match.waiting
	for _, pair in match.pairs do
		local a, b = find(pair.a), find(pair.b)
		if a and b then
			aiteOf[a.id] = b.id
			aiteOf[b.id] = a.id
			table.insert(kosenList, { a = a.id, b = b.id, fractionA = 0, fractionB = 0, startedAt = os.clock() })
			publish(a)
			publish(b)
			kosenStartedEvent:Fire(a.id, b.id)
		end
	end
end

-- 戦闘のフェーズの間、交戦を進め、交戦していない部隊を目的地へ進める
local function tick(dt: number)
	if StageService.getPhase() ~= "Battle" then
		return
	end
	refreshShiki()
	fightAll(dt)
	removeDefeated()
	matchAll()
	for _, butai in butaiList do
		if not aiteOf[butai.id] and not waiting[butai.id] and Butai.step(butai, Config.Butai.Speed, dt) then
			publish(butai)
		end
	end
end

local function round(value: number): number
	return math.round(value * 10) / 10
end

local function describe(butai: Butai.Butai): { [string]: any }
	local mokutekichi = butai.mokutekichi
	local shihaiArea = ButaiService.shihaiAreaOf(butai)
	return {
		id = butai.id,
		gun = butai.gun,
		heisu = butai.heisu,
		shiki = round(butai.shiki),
		shikiHosei = butai.shikiHosei,
		jonin = butai.jonin,
		position = { round(butai.position.x), round(butai.position.z) },
		kyoten = butai.kyoten,
		mokutekiKyoten = butai.mokutekiKyoten,
		mokutekichi = if mokutekichi then { round(mokutekichi.x), round(mokutekichi.z) } else nil,
		keiyuten = #butai.keiyuten,
		kosen = aiteOf[butai.id],
		taiki = if waiting[butai.id] then true else nil,
		-- 交戦の押す力に掛ける支配エリアの倍率。1 のときは出さない
		shihaiArea = if shihaiArea ~= 1 then round(shihaiArea) else nil,
	}
end

local function registerDebugCommands()
	DebugCommand.register(
		"AddButai",
		"<Mikatagun|Tekigun> <兵数> <拠点 ID> [目的地の拠点 ID]",
		"出撃したステージの拠点の中心に部隊を足す。目的地を渡すと、その拠点へ向かわせる（確認用）",
		function(gun, heisu, kyotenId, mokutekiKyoten)
			if not Gun.isGun(gun) then
				error("軍は Mikatagun か Tekigun で指定する", 0)
			end
			local count = DebugCommand.toNumber(heisu, "兵数")
			local position = if type(kyotenId) == "string" then ButaiService.kyotenPosition(kyotenId) else nil
			if not position then
				return `拠点 {tostring(kyotenId)} が出撃したステージの配置に無い（出撃してから足す）`
			end
			local butai = ButaiService.add({ gun = gun, heisu = count, position = position, kyoten = kyotenId })
			if not butai then
				return "部隊を足せなかった（警告を見る）"
			end
			if mokutekiKyoten ~= nil then
				if type(mokutekiKyoten) ~= "string" or not ButaiService.moveToKyoten(butai.id, mokutekiKyoten) then
					return `部隊 {butai.id} を足したが、目的地の拠点 {tostring(mokutekiKyoten)} が配置に無い`
				end
				return `部隊 {butai.id} を {kyotenId} に足し、{mokutekiKyoten} へ向かわせた`
			end
			return `部隊 {butai.id} を {kyotenId} に足した`
		end
	)
	DebugCommand.register(
		"MoveButai",
		"<部隊 ID> <目的地の拠点 ID>",
		"部隊を拠点へ向かわせる。今いる拠点とつながっていれば道の経由点をたどる（確認用）",
		function(id, kyotenId)
			if type(id) ~= "string" or not ButaiService.get(id) then
				return `部隊 {tostring(id)} がいない`
			end
			if type(kyotenId) ~= "string" or not ButaiService.moveToKyoten(id, kyotenId) then
				return `拠点 {tostring(kyotenId)} が出撃したステージの配置に無い`
			end
			return `部隊 {id} を {kyotenId} へ向かわせた`
		end
	)
	DebugCommand.register(
		"DumpKosen",
		"",
		"交戦中の組（両部隊の兵数と端数、押す力、支配エリアの倍率、経過秒数）と、手前で待っている部隊を JSON で返す",
		function()
			local now = os.clock()
			local list = {}
			for _, state in kosenList do
				local a, b = find(state.a), find(state.b)
				local push, shihaiArea = nil, nil
				if a and b then
					local sideA, sideB = sideOf(a, state.fractionA), sideOf(b, state.fractionB)
					push = { round(Kosen.push(sideA, sideB)), round(Kosen.push(sideB, sideA)) }
					shihaiArea = { round(sideA.shihaiArea or 1), round(sideB.shihaiArea or 1) }
				end
				table.insert(list, {
					a = state.a,
					b = state.b,
					heisu = { if a then a.heisu else 0, if b then b.heisu else 0 },
					fraction = { round(state.fractionA), round(state.fractionB) },
					push = push,
					shihaiArea = shihaiArea,
					elapsed = round(now - state.startedAt),
				})
			end
			local taiki = {}
			for id in waiting do
				table.insert(taiki, id)
			end
			table.sort(taiki)
			return HttpService:JSONEncode({ kosen = list, taiki = taiki })
		end
	)
	DebugCommand.register(
		"RemoveButai",
		"<部隊 ID>",
		"部隊を外す。兵数の減少には数えないので、拠点の耐久は変わらない（確認用）",
		function(id)
			if type(id) ~= "string" or not ButaiService.remove(id) then
				return `部隊 {tostring(id)} がいない`
			end
			return `部隊 {id} を外した`
		end
	)
	DebugCommand.register("DumpButai", "", "部隊の一覧を JSON で返す", function()
		local result = {}
		for _, butai in butaiList do
			table.insert(result, describe(butai))
		end
		return HttpService:JSONEncode(result)
	end)
	DebugCommand.register(
		"ShowButai",
		"<true|false>",
		"部隊の位置に軍の色の柱と、部隊 ID と兵数を出すか、消すかを切り替える",
		function(value)
			showMarkers = value == true or value == "true"
			if showMarkers then
				if not markerFolder then
					local created = Instance.new("Folder")
					created.Name = "ButaiMarkers"
					created.Parent = workspace
					markerFolder = created
				end
				for _, butai in butaiList do
					updateMarker(butai)
				end
				return `部隊 {#butaiList} 個の柱を出した`
			end
			local container = markerFolder
			if container then
				container:Destroy()
				markerFolder = nil
			end
			return "部隊の柱を消した"
		end
	)
end

function ButaiService.start()
	local created = Instance.new("Folder")
	created.Name = ButaiService.FOLDER
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
			-- 1回の失敗で部隊が止まらないよう、失敗は警告にして次の間隔で続ける
			local ok, err = pcall(tick, now - last)
			if not ok then
				warn(`ButaiService: 部隊を進められなかった: {err}`)
			end
			last = now
		end
	end)
end

return ButaiService
