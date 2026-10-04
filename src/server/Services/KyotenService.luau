--!strict
-- 戦場の拠点の耐久と所属を持つ。出撃したステージの配置（HaichiService）から拠点を作り、
-- 範囲の中でその拠点の軍の下忍が倒れるたびに耐久を減らし、0 になったら相手の軍に制圧させる。本陣も同じ仕組みで扱う。
-- 計算は ReplicatedStorage.Shared.Kyoten、耐久の上限と制圧直後の割合は Config.luau の Kyoten 節にある。
--
-- - 出撃（StageService.started）で、配置の拠点を開始時の軍と耐久の上限で作る。配置の構成が無いステージでは作らない。
--   決着（StageService.finished）とロビーのフェーズへの戻りで片付ける
-- - 拠点の範囲は拠点の目印のパーツの中心・向き・大きさで、水平だけを見る
-- - 耐久を減らすのは、戦闘のフェーズの間に、範囲の中でその拠点の軍の下忍が倒れたとき。
--   部隊の兵数の減少（交戦など。ButaiService.heisuLost）と、仮の湧き処理の下忍の撃破（EnemyService.gekiha）の両方で減らす
-- - 仮の湧き処理の下忍は敵軍で、部隊に属さない。実体化圏の下忍の個体（#76）は撃破で部隊の兵数を減らすので、
--   置き換えたら EnemyService.gekiha の購読を外し、兵数の減少だけで数える
-- - 守備の部隊は、拠点の軍の部隊のうち範囲の中にいるもの。部隊を方針に沿って動かす処理（#102）が来るまでは、
--   配置の部隊は開始時の拠点にとどまる
-- - 耐久が 0 になったら相手の軍が制圧する。範囲の中にいた元の軍の部隊は敗走して消え、耐久は制圧直後の値になる。
--   制圧は拠点の陥落の出来事として、拠点の中心で、制圧した軍が得をする形で士気に知らせる（ShikiService.notify）
-- - 戦闘のフェーズの間、守備の兵数が上限より少なければ、間隔ごとに補充する（値は Config.luau の Kyoten 節）。
--   補充を受けるのは、拠点の守備の部隊（配置で方針が防衛のその拠点から始まる部隊か、補充で作った部隊）。
--   その部隊が範囲の中にいなければ、拠点の中心に守備の部隊（Shubi<拠点 ID>）を作る
-- - 守備のいない拠点は、攻める軍（相手の軍の部隊と、敵軍の拠点では出撃したプレイヤー）が範囲の中にいる間、
--   時間に比例して耐久が減る。仮の湧き処理の敵は攻める軍に数えない
-- - 孤立した拠点は守備を補充しない。孤立は HeitansenService が setKoritsuProvider で渡す関数で引く
-- - 拠点を作り終えたら loaded で知らせる（HeitansenService が兵站線を求め始める）
-- - 拠点ごとに ReplicatedStorage.Kyoten の下へ拠点 ID の名前で Configuration を置き、Attribute で
--   軍（Gun）・耐久（Taikyu）・耐久の上限（MaxTaikyu）・本陣か（Honjin）・
--   中心（Position。Vector2 の X と Y にワールドの X と Z）・範囲の大きさ（Size。Vector2 の X と Y に大きさの X と Z）・
--   孤立しているか（Koritsu）・孤立しない拠点か（NeverIsolated）をクライアントへ複製する
-- - 耐久が変わると taikyuChanged、制圧すると seiatsu で知らせる
-- - 窓口の ShowKyoten で、拠点の範囲に軍の色の板と、拠点 ID と耐久を出す（確認用）

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Butai = require(ReplicatedStorage.Shared.Butai)
local Colors = require(ReplicatedStorage.Shared.Colors)
local Config = require(ReplicatedStorage.Shared.Config)
local Gun = require(ReplicatedStorage.Shared.Gun)
local Haichi = require(ReplicatedStorage.Shared.Haichi)
local Kyoten = require(ReplicatedStorage.Shared.Kyoten)
local Mejirushi = require(ReplicatedStorage.Shared.Mejirushi)
local StagePhase = require(ReplicatedStorage.Shared.StagePhase)
local DebugCommand = require(script.Parent.Parent.DebugCommand)
local ButaiService = require(script.Parent.ButaiService)
local EnemyService = require(script.Parent.EnemyService)
local HaichiService = require(script.Parent.HaichiService)
local ShikiService = require(script.Parent.ShikiService)
local StageService = require(script.Parent.StageService)

-- 戦場の拠点。計算の状態に、範囲（拠点の目印のパーツの中心・向き・大きさ）を添える
type Entry = {
	state: Kyoten.Kyoten,
	cframe: CFrame,
	size: Vector3,
}

local KyotenService = {}

-- 拠点の Attribute を置くフォルダ（ReplicatedStorage の下）の名前
KyotenService.FOLDER = "Kyoten"

-- 確認用の板の厚みと、名札を出す高さ（スタッド）
local MARKER_THICKNESS = 1
local LABEL_HEIGHT = 12

-- 配置の順の拠点
local entries: { Entry } = {}
-- 出撃したステージの配置。配置の構成が無いステージとロビーでは nil
local haichi: HaichiService.Loaded? = nil
-- 拠点が孤立しているかと、孤立しない拠点かを返す関数（HeitansenService が渡す）
local koritsuProvider: ((id: string) -> (boolean, boolean))? = nil
-- 拠点 ID から引く、補充を受ける守備の部隊の ID
local hojuButai: { [string]: string } = {}
-- 拠点 ID から引く、前に補充してからの秒数
local hojuElapsed: { [string]: number } = {}
local folder: Folder
local markerFolder: Folder? = nil
local showMarkers = false

local taikyuChangedEvent = Instance.new("BindableEvent")
-- 耐久が変わったときに、拠点 ID と新しい耐久で発火する
KyotenService.taikyuChanged = taikyuChangedEvent.Event
local seiatsuEvent = Instance.new("BindableEvent")
-- 拠点が制圧されたときに、拠点 ID・制圧した軍・元の軍で発火する
KyotenService.seiatsu = seiatsuEvent.Event
local loadedEvent = Instance.new("BindableEvent")
-- 出撃したステージの拠点を作り終えたときに、ステージ ID で発火する
KyotenService.loaded = loadedEvent.Event

-- 拠点が孤立しているかと、孤立しない拠点か。関数が無ければどちらも false
local function koritsuOf(id: string): (boolean, boolean)
	local provider = koritsuProvider
	if provider then
		return provider(id)
	end
	return false, false
end

local function find(id: string): Entry?
	for _, entry in entries do
		if entry.state.id == id then
			return entry
		end
	end
	return nil
end

-- 拠点の範囲の中か（水平だけを見る）
local function contains(entry: Entry, x: number, z: number): boolean
	local offset = entry.cframe:PointToObjectSpace(Vector3.new(x, entry.cframe.Position.Y, z))
	return Mejirushi.insideBounds(offset.X, offset.Z, entry.size.X, entry.size.Z)
end

local function round(value: number): number
	return math.round(value * 10) / 10
end

local function labelOf(entry: Entry): string
	local state = entry.state
	local koritsu = koritsuOf(state.id)
	local suffix = if koritsu then " 孤立" else ""
	return `{state.id} {Kyoten.displayTaikyu(state.taikyu)}/{Kyoten.maxTaikyu(state.honjin)}{suffix}`
end

local function updateMarker(entry: Entry)
	local container = markerFolder
	if not container then
		return
	end
	local marker = container:FindFirstChild(entry.state.id) :: Part?
	if not marker then
		local created = Instance.new("Part")
		created.Name = entry.state.id
		created.Anchored = true
		created.CanCollide = false
		created.CanTouch = false
		created.CanQuery = false
		created.CastShadow = false
		created.Material = Enum.Material.Neon
		created.Transparency = 0.6
		created.Size = Vector3.new(entry.size.X, MARKER_THICKNESS, entry.size.Z)
		-- 拠点の目印の底面に敷く
		created.CFrame = entry.cframe * CFrame.new(0, -entry.size.Y / 2 + MARKER_THICKNESS / 2, 0)
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "Label"
		billboard.Size = UDim2.fromOffset(200, 40)
		billboard.StudsOffsetWorldSpace = Vector3.new(0, LABEL_HEIGHT, 0)
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
	part.Color = Colors.Gun[entry.state.gun]
	local label = part:FindFirstChild("Label")
	local text = label and label:FindFirstChild("Text")
	if text and text:IsA("TextLabel") then
		text.Text = labelOf(entry)
	end
end

-- 拠点の今の状態を Attribute に書いてクライアントへ複製する。確認用の板を出していれば書き換える
local function publish(entry: Entry)
	local state = entry.state
	local instance = folder:FindFirstChild(state.id)
	if not instance then
		local created = Instance.new("Configuration")
		created.Name = state.id
		created.Parent = folder
		instance = created
	end
	local config = instance :: Instance
	local center = entry.cframe.Position
	config:SetAttribute("Gun", state.gun)
	config:SetAttribute("Taikyu", state.taikyu)
	config:SetAttribute("MaxTaikyu", Kyoten.maxTaikyu(state.honjin))
	config:SetAttribute("Honjin", state.honjin)
	config:SetAttribute("Position", Vector2.new(center.X, center.Z))
	config:SetAttribute("Size", Vector2.new(entry.size.X, entry.size.Z))
	local koritsu, neverIsolated = koritsuOf(state.id)
	config:SetAttribute("Koritsu", koritsu)
	config:SetAttribute("NeverIsolated", neverIsolated)
	if showMarkers then
		updateMarker(entry)
	end
end

-- 拠点が孤立しているかと、孤立しない拠点かを返す関数を登録する。孤立した拠点は守備を補充しない
function KyotenService.setKoritsuProvider(provider: (id: string) -> (boolean, boolean))
	koritsuProvider = provider
end

-- 全部の拠点を複製し直す。孤立が変わったときに HeitansenService が呼ぶ
function KyotenService.republish()
	for _, entry in entries do
		publish(entry)
	end
end

-- 出撃したステージの配置。配置の構成が無いステージとロビーでは nil
function KyotenService.getHaichi(): HaichiService.Loaded?
	return haichi
end

-- 拠点の今の状態（表はそのもの）。出撃したステージの拠点に無ければ nil
function KyotenService.get(id: string): Kyoten.Kyoten?
	local entry = find(id)
	return if entry then entry.state else nil
end

-- 配置の順の拠点の一覧（表は写し。拠点の表はそのもの）
function KyotenService.list(): { Kyoten.Kyoten }
	local result = {}
	for _, entry in entries do
		table.insert(result, entry.state)
	end
	return result
end

-- 拠点の中心。出撃したステージの拠点に無ければ nil
function KyotenService.centerOf(id: string): Butai.Point?
	local entry = find(id)
	if not entry then
		return nil
	end
	local center = entry.cframe.Position
	return { x = center.X, z = center.Z }
end

-- 拠点の目印の中心（高さも含む）。出撃したステージの拠点に無ければ nil
function KyotenService.positionOf(id: string): Vector3?
	local entry = find(id)
	return if entry then entry.cframe.Position else nil
end

-- 位置が範囲の中にある拠点の ID。どの拠点の範囲にも無ければ nil
function KyotenService.kyotenAt(position: Butai.Point): string?
	for _, entry in entries do
		if contains(entry, position.x, position.z) then
			return entry.state.id
		end
	end
	return nil
end

-- 位置が拠点の範囲の中か。拠点が無ければ false
function KyotenService.contains(id: string, position: Butai.Point): boolean
	local entry = find(id)
	return entry ~= nil and contains(entry, position.x, position.z)
end

-- 拠点の守備の部隊（拠点の軍の部隊のうち、範囲の中にいるもの）の ID を、部隊の一覧の順に返す
function KyotenService.shubiOf(id: string): { string }
	local result = {}
	local entry = find(id)
	if not entry then
		return result
	end
	for _, butai in ButaiService.list() do
		if butai.gun == entry.state.gun and contains(entry, butai.position.x, butai.position.z) then
			table.insert(result, butai.id)
		end
	end
	return result
end

-- 拠点の守備の兵数（拠点の軍の部隊のうち、範囲の中にいるものの兵数の和）
local function shubiHeisuOf(entry: Entry): number
	local total = 0
	for _, butai in ButaiService.list() do
		if butai.gun == entry.state.gun and contains(entry, butai.position.x, butai.position.z) then
			total += butai.heisu
		end
	end
	return total
end

-- 範囲の中にいる攻める軍の数。相手の軍の部隊と、敵軍の拠点では生きている出撃したプレイヤー
local function kogekiCountOf(entry: Entry): number
	local count = 0
	local opponent = Gun.opponentOf(entry.state.gun)
	for _, butai in ButaiService.list() do
		if butai.gun == opponent and butai.heisu > 0 and contains(entry, butai.position.x, butai.position.z) then
			count += 1
		end
	end
	if entry.state.gun == "Tekigun" then
		for _, member in StageService.getMembers() do
			local character = member.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if humanoid and root and humanoid.Health > 0 and contains(entry, root.Position.X, root.Position.Z) then
				count += 1
			end
		end
	end
	return count
end

-- 補充を受ける守備の部隊。範囲の中にいる拠点の軍の部隊でなければ nil
local function hojuTargetOf(entry: Entry): string?
	local id = hojuButai[entry.state.id]
	local butai = if id then ButaiService.get(id) else nil
	if butai and butai.gun == entry.state.gun and contains(entry, butai.position.x, butai.position.z) then
		return butai.id
	end
	return nil
end

-- 守備の兵数が上限より少なければ補充する。補充を受ける部隊がいなければ、拠点の中心に守備の部隊を作る
local function hoju(entry: Entry)
	local amount = Kyoten.hojuHeisu(shubiHeisuOf(entry), entry.state.honjin)
	if amount <= 0 then
		return
	end
	local target = hojuTargetOf(entry)
	if target then
		ButaiService.changeHeisu(target, amount)
		return
	end
	local id = `Shubi{entry.state.id}`
	local suffix = 1
	while ButaiService.get(id) do
		suffix += 1
		id = `Shubi{entry.state.id}{suffix}`
	end
	local center = entry.cframe.Position
	local created = ButaiService.add({
		id = id,
		gun = entry.state.gun,
		heisu = amount,
		position = { x = center.X, z = center.Z },
		kyoten = entry.state.id,
	})
	if created then
		hojuButai[entry.state.id] = created.id
	end
end

-- 制圧した後の片付け。範囲の中にいた元の軍の部隊を敗走させて（消して）、補充をやり直し、
-- 拠点の陥落を士気と seiatsu で知らせる
local function afterSeiatsu(entry: Entry, previous: Gun.Gun)
	for _, butai in ButaiService.list() do
		if butai.gun == previous and contains(entry, butai.position.x, butai.position.z) then
			ButaiService.remove(butai.id)
		end
	end
	hojuButai[entry.state.id] = nil
	hojuElapsed[entry.state.id] = 0
	local center = entry.cframe.Position
	ShikiService.notify("KyotenKanraku", { x = center.X, z = center.Z }, entry.state.gun)
	seiatsuEvent:Fire(entry.state.id, entry.state.gun, previous)
end

-- 耐久を書き換えた後に、複製し直して知らせる。制圧していれば片付ける
local function afterChange(entry: Entry, previous: Gun.Gun, captured: boolean)
	publish(entry)
	taikyuChangedEvent:Fire(entry.state.id, entry.state.taikyu)
	if captured then
		afterSeiatsu(entry, previous)
	end
end

-- 耐久を amount 減らす。0 になったら相手の軍に制圧させる。制圧したら true。
-- 拠点が無いか、amount が 0 以下なら何もしない
function KyotenService.damage(id: string, amount: number): boolean
	local entry = find(id)
	if not entry or amount <= 0 then
		return false
	end
	local previous = entry.state.gun
	local captured = Kyoten.damage(entry.state, amount)
	afterChange(entry, previous, captured)
	return captured
end

-- 耐久を value にする（0 から上限までに収める）。0 にしたら相手の軍に制圧させ、true を返す。拠点が無ければ false
function KyotenService.setTaikyu(id: string, value: number): boolean
	local entry = find(id)
	if not entry then
		return false
	end
	local previous = entry.state.gun
	local captured = Kyoten.setTaikyu(entry.state, value)
	afterChange(entry, previous, captured)
	return captured
end

-- gun の軍に制圧させる。すでに gun の拠点か、拠点が無ければ false
function KyotenService.seiatsuBy(id: string, gun: Gun.Gun): boolean
	local entry = find(id)
	if not entry or entry.state.gun == gun then
		return false
	end
	local previous = entry.state.gun
	Kyoten.seiatsu(entry.state, gun)
	afterChange(entry, previous, true)
	return true
end

-- 範囲の中で gun の軍の下忍が count 人倒れたら、その拠点が gun の拠点なら耐久を減らす
local function onGeninLost(gun: Gun.Gun, count: number, x: number, z: number)
	if StageService.getPhase() ~= "Battle" then
		return
	end
	for _, entry in entries do
		if entry.state.gun == gun and contains(entry, x, z) then
			KyotenService.damage(entry.state.id, Kyoten.gekihaDamage(count))
			return
		end
	end
end

local function onHeisuLost(_id: string, gun: Gun.Gun, loss: number, position: Butai.Point)
	onGeninLost(gun, loss, position.x, position.z)
end

-- 仮の湧き処理の下忍の撃破。部隊に属さないので、兵数の減少とは別に数える（#76 で外す）
local function onGekiha(kind: string, gun: Gun.Gun, position: Vector3)
	if kind == "Genin" then
		onGeninLost(gun, 1, position.X, position.Z)
	end
end

-- 戦闘のフェーズの間、守備を補充し、守備のいない拠点の耐久を減らす
local function tick(dt: number)
	if StageService.getPhase() ~= "Battle" then
		return
	end
	for _, entry in table.clone(entries) do
		local id = entry.state.id
		-- 孤立した拠点は補充しない。兵站線がつながったら、そこから間隔を数え直す
		local koritsu = koritsuOf(id)
		local elapsed = if koritsu then 0 else (hojuElapsed[id] or 0) + dt
		if elapsed >= Config.Kyoten.HojuInterval then
			elapsed -= Config.Kyoten.HojuInterval
			hoju(entry)
		end
		hojuElapsed[id] = elapsed
		local amount = Kyoten.mushubiDamage(shubiHeisuOf(entry), kogekiCountOf(entry), dt)
		if amount > 0 then
			KyotenService.damage(id, amount)
		end
	end
end

-- 拠点をすべて片付ける
local function clear()
	table.clear(entries)
	table.clear(hojuButai)
	table.clear(hojuElapsed)
	haichi = nil
	folder:ClearAllChildren()
	local container = markerFolder
	if container then
		container:ClearAllChildren()
	end
end

-- 出撃したステージの配置から拠点を作る。配置の構成が無いステージでは作らない
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
	for _, kyoten in loaded.kyoten do
		local entry: Entry = {
			state = Kyoten.new(kyoten.id, kyoten.honjin, kyoten.gun),
			cframe = kyoten.cframe,
			size = kyoten.size,
		}
		table.insert(entries, entry)
		hojuElapsed[kyoten.id] = 0
		publish(entry)
	end
	-- 配置で方針が防衛の、その拠点から始まる部隊が守備の補充を受ける（1拠点に1部隊）
	for _, butai in loaded.butai do
		if butai.hoshin == "Boei" and find(butai.kyoten) and not hojuButai[butai.kyoten] then
			hojuButai[butai.kyoten] = butai.id
		end
	end
	loadedEvent:Fire(info.stageId)
end

local function describe(entry: Entry): { [string]: any }
	local state = entry.state
	local center = entry.cframe.Position
	return {
		id = state.id,
		honjin = state.honjin,
		gun = state.gun,
		taikyu = Kyoten.displayTaikyu(state.taikyu),
		taikyuExact = round(state.taikyu),
		maxTaikyu = Kyoten.maxTaikyu(state.honjin),
		center = { round(center.X), round(center.Z) },
		size = { round(entry.size.X), round(entry.size.Z) },
		shubi = KyotenService.shubiOf(state.id),
		shubiHeisu = shubiHeisuOf(entry),
		shubiMax = Kyoten.shubiMax(state.honjin),
		hojuButai = hojuTargetOf(entry),
		hojuIn = round(math.max(Config.Kyoten.HojuInterval - (hojuElapsed[state.id] or 0), 0)),
		kogeki = kogekiCountOf(entry),
		koritsu = (koritsuOf(state.id)),
	}
end

local function registerDebugCommands()
	DebugCommand.register(
		"DumpKyoten",
		"",
		"拠点の一覧（軍・耐久・範囲・守備の部隊）を JSON で返す",
		function()
			local result = {}
			for _, entry in entries do
				table.insert(result, describe(entry))
			end
			return HttpService:JSONEncode(result)
		end
	)
	DebugCommand.register(
		"SetKyotenTaikyu",
		"<拠点 ID> <耐久>",
		"拠点の耐久を書き換える。0 にすると相手の軍が制圧する（確認用）",
		function(id, value)
			if type(id) ~= "string" or not find(id) then
				return `拠点 {tostring(id)} が出撃したステージに無い（出撃してから使う）`
			end
			local captured = KyotenService.setTaikyu(id, DebugCommand.toNumber(value, "耐久"))
			local entry = find(id) :: Entry
			if captured then
				return `{id} は {entry.state.gun} が制圧した（{labelOf(entry)}）`
			end
			return `{id} の耐久を書き換えた（{labelOf(entry)}）`
		end
	)
	DebugCommand.register(
		"SetKyotenGun",
		"<拠点 ID> <Mikatagun|Tekigun>",
		"拠点をその軍に制圧させる。範囲の中の元の軍の部隊は敗走して消える（確認用）",
		function(id, gun)
			if type(id) ~= "string" or not find(id) then
				return `拠点 {tostring(id)} が出撃したステージに無い（出撃してから使う）`
			end
			if not Gun.isGun(gun) then
				error("軍は Mikatagun か Tekigun で指定する", 0)
			end
			if not KyotenService.seiatsuBy(id, gun :: Gun.Gun) then
				return `{id} はすでに {gun} の拠点`
			end
			return `{id} を {gun} に制圧させた（{labelOf(find(id) :: Entry)}）`
		end
	)
	DebugCommand.register(
		"ShowKyoten",
		"<true|false>",
		"拠点の範囲に軍の色の板と、拠点 ID と耐久を出すか、消すかを切り替える",
		function(value)
			showMarkers = value == true or value == "true"
			if showMarkers then
				if not markerFolder then
					local created = Instance.new("Folder")
					created.Name = "KyotenMarkers"
					created.Parent = workspace
					markerFolder = created
				end
				for _, entry in entries do
					updateMarker(entry)
				end
				return `拠点 {#entries} 個の範囲を出した`
			end
			local container = markerFolder
			if container then
				container:Destroy()
				markerFolder = nil
			end
			return "拠点の範囲を消した"
		end
	)
end

function KyotenService.start()
	local created = Instance.new("Folder")
	created.Name = KyotenService.FOLDER
	created.Parent = ReplicatedStorage
	folder = created

	StageService.started:Connect(onStarted)
	StageService.finished:Connect(clear)
	StageService.phaseChanged:Connect(function(next: StagePhase.Phase)
		if next == "Lobby" then
			clear()
		end
	end)
	ButaiService.heisuLost:Connect(onHeisuLost)
	EnemyService.gekiha:Connect(onGekiha)
	registerDebugCommands()

	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(Config.Kyoten.TickInterval)
			local now = os.clock()
			-- 1回の失敗で補充が止まらないよう、失敗は警告にして次の間隔で続ける
			local ok, err = pcall(tick, now - last)
			if not ok then
				warn(`KyotenService: 拠点の補充と減少を進められなかった: {err}`)
			end
			last = now
		end
	end)
end

return KyotenService
