--!strict
-- 兵站線と孤立を戦場に反映する。拠点の所属（KyotenService）とつながりから、軍ごとに兵站線につながった拠点と
-- 孤立した拠点を求め直す。計算は ReplicatedStorage.Shared.Heitansen にある。
--
-- - 出撃したステージの拠点ができたとき（KyotenService.loaded）に配置のつながりを読んで求める。
--   決着とロビーのフェーズへの戻りで片付ける
-- - 拠点が制圧されたとき（KyotenService.seiatsu）、つながりを通れなくしたときと戻したとき、
--   孤立しない拠点を指定したときと外したときに求め直す
-- - つながりは軍ごとに通れなくできる（落石は、使った軍の相手の軍にだけ通れなくする）
-- - 孤立しない拠点（兵糧庫）は、兵站線が切れても孤立しない。そこから先へは兵站線を延ばさない。
--   指定は拠点が制圧されると外れる
-- - 孤立した拠点は守備を補充しない。孤立は KyotenService.setKoritsuProvider で渡し、
--   拠点の Attribute の Koritsu・NeverIsolated で複製する
-- - 拠点が自分の軍の兵站線の末端か（Heitansen.isMattan）を isMattan で引ける（秘計の判断の兵糧庫が使う）
-- - つながりごとに ReplicatedStorage.Tsunagari の下へ Haichi.pairKey の名前（拠点A-拠点B）で Configuration を置き、
--   Attribute で両端（KyotenA・KyotenB）・入っている兵站線の軍（Heitansen。どちらにも入っていなければ無し）・
--   通れない軍（BlockedMikatagun・BlockedTekigun）・KyotenA から KyotenB へたどる経由点（KeiyutenCount と
--   Keiyuten1、Keiyuten2…。Vector2 の X と Y にワールドの X と Z）を複製する
-- - 求め直したら changed で知らせる
-- - 窓口の ShowHeitansen で、つながりの道筋を、入っている兵站線の軍の色の線で出す（確認用）

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Colors = require(ReplicatedStorage.Shared.Colors)
local Ground = require(ReplicatedStorage.Shared.Ground)
local Gun = require(ReplicatedStorage.Shared.Gun)
local Haichi = require(ReplicatedStorage.Shared.Haichi)
local Heitansen = require(ReplicatedStorage.Shared.Heitansen)
local StagePhase = require(ReplicatedStorage.Shared.StagePhase)
local DebugCommand = require(script.Parent.Parent.DebugCommand)
local KyotenService = require(script.Parent.KyotenService)
local StageService = require(script.Parent.StageService)

local HeitansenService = {}

-- つながりの Attribute を置くフォルダ（ReplicatedStorage の下）の名前
HeitansenService.FOLDER = "Tsunagari"

-- 確認用の線の太さと、地面から浮かせる高さ（スタッド）
local LINE_WIDTH = 1
local LINE_LIFT = 1
-- どちらの兵站線にも入っていないつながりの線の色
local LINE_COLOR = Color3.fromRGB(160, 160, 160)

-- 出撃したステージのつながり（通れない軍を持つ）
local tsunagariList: { Heitansen.Tsunagari } = {}
-- つながりのキー（Haichi.pairKey）から引く、kyotenA から kyotenB へたどる道筋の経由点
local keiyutenOf: { [string]: { Vector3 } } = {}
-- 孤立しない拠点
local neverIsolated: { [string]: boolean } = {}
-- 最後に求めた兵站線。出撃していなければ nil
local result: Heitansen.Result? = nil
local folder: Folder
local lineFolder: Folder? = nil
local showLines = false

local changedEvent = Instance.new("BindableEvent")
-- 兵站線を求め直したときに発火する
HeitansenService.changed = changedEvent.Event

local function findTsunagari(kyotenA: string, kyotenB: string): Heitansen.Tsunagari?
	local key = Haichi.pairKey(kyotenA, kyotenB)
	for _, tsunagari in tsunagariList do
		if Haichi.pairKey(tsunagari.kyotenA, tsunagari.kyotenB) == key then
			return tsunagari
		end
	end
	return nil
end

-- 拠点が gun の軍の兵站線につながっているか。所属が gun でない拠点と、出撃していないときは false
function HeitansenService.isConnected(gun: Gun.Gun, kyotenId: string): boolean
	local current = result
	return current ~= nil and Heitansen.isConnected(current, gun, kyotenId)
end

-- 拠点が自分の軍の兵站線から孤立しているか。拠点が無いときと、出撃していないときは false
function HeitansenService.isKoritsu(kyotenId: string): boolean
	local current = result
	local kyoten = KyotenService.get(kyotenId)
	return current ~= nil and kyoten ~= nil and current[kyoten.gun].isolated[kyotenId] == true
end

-- 拠点が自分の軍の兵站線の末端か（Heitansen.isMattan）。拠点が無いときと、出撃していないときは false
function HeitansenService.isMattan(kyotenId: string): boolean
	local current = result
	local kyoten = KyotenService.get(kyotenId)
	if not current or not kyoten then
		return false
	end
	return Heitansen.isMattan(current, tsunagariList, { id = kyoten.id, gun = kyoten.gun, honjin = kyoten.honjin })
end

-- つながりを通れない軍（落石で塞いだ軍）。出撃したステージにそのつながりが無いか、どの軍も通れるなら空
function HeitansenService.blockedOf(kyotenA: string, kyotenB: string): { [Gun.Gun]: boolean }
	local tsunagari = findTsunagari(kyotenA, kyotenB)
	local blocked = tsunagari and tsunagari.blocked
	return if blocked then table.clone(blocked) else {}
end

-- gun の軍の兵站線につながった拠点の ID を、配置の順に返す
function HeitansenService.connectedOf(gun: Gun.Gun): { string }
	local ids = {}
	for _, kyoten in KyotenService.list() do
		if kyoten.gun == gun and HeitansenService.isConnected(gun, kyoten.id) then
			table.insert(ids, kyoten.id)
		end
	end
	return ids
end

-- 地面から少し浮かせた位置
local function lifted(x: number, z: number): Vector3
	return Vector3.new(x, (Ground.heightAt(x, z) or 0) + LINE_LIFT, z)
end

-- つながりの道筋の点（両端の拠点の中心と経由点）。拠点が無ければ空
local function routeOf(tsunagari: Heitansen.Tsunagari): { Vector3 }
	local from = KyotenService.centerOf(tsunagari.kyotenA)
	local to = KyotenService.centerOf(tsunagari.kyotenB)
	if not from or not to then
		return {}
	end
	local points = { lifted(from.x, from.z) }
	for _, point in keiyutenOf[Haichi.pairKey(tsunagari.kyotenA, tsunagari.kyotenB)] or {} do
		table.insert(points, lifted(point.X, point.Z))
	end
	table.insert(points, lifted(to.x, to.z))
	return points
end

-- つながりの確認用の線を引き直す
local function drawLine(tsunagari: Heitansen.Tsunagari, gun: Gun.Gun?)
	local container = lineFolder
	if not container then
		return
	end
	local key = Haichi.pairKey(tsunagari.kyotenA, tsunagari.kyotenB)
	local old = container:FindFirstChild(key)
	if old then
		old:Destroy()
	end
	local line = Instance.new("Folder")
	line.Name = key
	local blocked = tsunagari.blocked
	local anyBlocked = blocked ~= nil and next(blocked) ~= nil
	local points = routeOf(tsunagari)
	for index = 1, #points - 1 do
		local a, b = points[index], points[index + 1]
		local length = (b - a).Magnitude
		if length < 1e-3 then
			continue
		end
		local part = Instance.new("Part")
		part.Name = tostring(index)
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.CastShadow = false
		part.Material = Enum.Material.Neon
		part.Color = if gun then Colors.Gun[gun] else LINE_COLOR
		-- 通れない軍のあるつながりは薄く出す
		part.Transparency = if anyBlocked then 0.75 else 0.2
		part.Size = Vector3.new(LINE_WIDTH, LINE_WIDTH, length)
		part.CFrame = CFrame.lookAt((a + b) / 2, b)
		part.Parent = line
	end
	line.Parent = container
end

local function publishTsunagari(tsunagari: Heitansen.Tsunagari, gun: Gun.Gun?)
	local key = Haichi.pairKey(tsunagari.kyotenA, tsunagari.kyotenB)
	local instance = folder:FindFirstChild(key)
	if not instance then
		local created = Instance.new("Configuration")
		created.Name = key
		created.Parent = folder
		instance = created
	end
	local config = instance :: Instance
	local blocked = tsunagari.blocked or {}
	config:SetAttribute("KyotenA", tsunagari.kyotenA)
	config:SetAttribute("KyotenB", tsunagari.kyotenB)
	config:SetAttribute("Heitansen", gun)
	config:SetAttribute("BlockedMikatagun", blocked.Mikatagun == true)
	config:SetAttribute("BlockedTekigun", blocked.Tekigun == true)
	local keiyuten = keiyutenOf[key] or {}
	config:SetAttribute("KeiyutenCount", #keiyuten)
	for index, point in keiyuten do
		config:SetAttribute(`Keiyuten{index}`, Vector2.new(point.X, point.Z))
	end
	if showLines then
		drawLine(tsunagari, gun)
	end
end

-- 兵站線と孤立を求め直し、つながりと拠点を複製し直して知らせる
local function recompute()
	local kyotenList: { Heitansen.Kyoten } = {}
	for _, kyoten in KyotenService.list() do
		table.insert(kyotenList, {
			id = kyoten.id,
			gun = kyoten.gun,
			honjin = kyoten.honjin,
			neverIsolated = neverIsolated[kyoten.id],
		})
	end
	local current = Heitansen.compute(kyotenList, tsunagariList)
	result = current
	for _, tsunagari in tsunagariList do
		publishTsunagari(tsunagari, Heitansen.gunOf(current, tsunagari))
	end
	KyotenService.republish()
	changedEvent:Fire()
end

-- つながりを gun の軍にとって通れなくする（落石）。出撃したステージにそのつながりが無ければ false
function HeitansenService.block(kyotenA: string, kyotenB: string, gun: Gun.Gun): boolean
	local tsunagari = findTsunagari(kyotenA, kyotenB)
	if not tsunagari then
		return false
	end
	local blocked = tsunagari.blocked or {}
	blocked[gun] = true
	tsunagari.blocked = blocked
	recompute()
	return true
end

-- 通れなくしたつながりを戻す。gun を省くと両軍とも通れるようにする。出撃したステージにそのつながりが無ければ false
function HeitansenService.unblock(kyotenA: string, kyotenB: string, gun: Gun.Gun?): boolean
	local tsunagari = findTsunagari(kyotenA, kyotenB)
	if not tsunagari then
		return false
	end
	local blocked = tsunagari.blocked
	if blocked and gun then
		blocked[gun] = nil
	else
		tsunagari.blocked = nil
	end
	recompute()
	return true
end

-- 拠点を孤立しない拠点（兵糧庫）にするか、戻す。出撃したステージにその拠点が無ければ false
function HeitansenService.setNeverIsolated(kyotenId: string, value: boolean): boolean
	if not KyotenService.get(kyotenId) then
		return false
	end
	neverIsolated[kyotenId] = if value then true else nil
	recompute()
	return true
end

-- 片付ける
local function clear()
	table.clear(tsunagariList)
	table.clear(keiyutenOf)
	table.clear(neverIsolated)
	result = nil
	folder:ClearAllChildren()
	local container = lineFolder
	if container then
		container:ClearAllChildren()
	end
end

-- 出撃したステージの拠点ができたら、配置のつながりを読んで求める
local function onLoaded()
	clear()
	local loaded = KyotenService.getHaichi()
	if not loaded then
		return
	end
	for _, tsunagari in loaded.tsunagari do
		table.insert(tsunagariList, { kyotenA = tsunagari.kyotenA, kyotenB = tsunagari.kyotenB, blocked = nil })
		keiyutenOf[Haichi.pairKey(tsunagari.kyotenA, tsunagari.kyotenB)] = table.clone(tsunagari.keiyuten)
	end
	recompute()
end

-- 拠点が制圧されたら、兵糧庫の指定を外して求め直す
local function onSeiatsu(kyotenId: string)
	if not result then
		return
	end
	neverIsolated[kyotenId] = nil
	recompute()
end

local function sortedKeys(set: { [string]: boolean }): { string }
	local keys = {}
	for key in set do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

local function describe(): { [string]: any }
	local current = result
	local guns = {}
	for _, gun in Gun.list do
		guns[gun] = if current
			then { connected = sortedKeys(current[gun].connected), isolated = sortedKeys(current[gun].isolated) }
			else nil
	end
	local tsunagari = {}
	for _, item in tsunagariList do
		local blocked = {}
		for _, gun in Gun.list do
			if item.blocked and item.blocked[gun] then
				table.insert(blocked, gun)
			end
		end
		table.insert(tsunagari, {
			pair = Haichi.pairKey(item.kyotenA, item.kyotenB),
			heitansen = if current then Heitansen.gunOf(current, item) else nil,
			blocked = blocked,
		})
	end
	return {
		Mikatagun = guns.Mikatagun,
		Tekigun = guns.Tekigun,
		tsunagari = tsunagari,
		neverIsolated = sortedKeys(neverIsolated),
	}
end

local function readGun(value: unknown): Gun.Gun
	if not Gun.isGun(value) then
		error("軍は Mikatagun か Tekigun で指定する", 0)
	end
	return value :: Gun.Gun
end

local function registerDebugCommands()
	DebugCommand.register(
		"DumpHeitansen",
		"",
		"軍ごとの兵站線につながった拠点と孤立した拠点、つながりの状態、孤立しない拠点を JSON で返す",
		function()
			return HttpService:JSONEncode(describe())
		end
	)
	DebugCommand.register(
		"BlockTsunagari",
		"<拠点 A> <拠点 B> <通れなくする軍>",
		"つながりをその軍にとって通れなくし、兵站線を求め直す（落石の確認用）",
		function(kyotenA, kyotenB, gun)
			local target = readGun(gun)
			if type(kyotenA) ~= "string" or type(kyotenB) ~= "string" then
				error("つながりの両端の拠点 ID を指定する", 0)
			end
			if not HeitansenService.block(kyotenA, kyotenB, target) then
				return `つながり {kyotenA}-{kyotenB} が出撃したステージに無い`
			end
			return `つながり {Haichi.pairKey(kyotenA, kyotenB)} を {target} にとって通れなくした`
		end
	)
	DebugCommand.register(
		"UnblockTsunagari",
		"<拠点 A> <拠点 B> [軍]",
		"通れなくしたつながりを戻し、兵站線を求め直す。軍を省くと両軍とも通れるようにする（確認用）",
		function(kyotenA, kyotenB, gun)
			local target = if gun ~= nil then readGun(gun) else nil
			if type(kyotenA) ~= "string" or type(kyotenB) ~= "string" then
				error("つながりの両端の拠点 ID を指定する", 0)
			end
			if not HeitansenService.unblock(kyotenA, kyotenB, target) then
				return `つながり {kyotenA}-{kyotenB} が出撃したステージに無い`
			end
			return `つながり {Haichi.pairKey(kyotenA, kyotenB)} を戻した`
		end
	)
	DebugCommand.register(
		"SetNeverIsolated",
		"<拠点 ID> <true|false>",
		"拠点を孤立しない拠点（兵糧庫）にするか戻し、兵站線を求め直す（確認用）",
		function(kyotenId, value)
			local enabled = value == true or value == "true"
			if type(kyotenId) ~= "string" or not HeitansenService.setNeverIsolated(kyotenId, enabled) then
				return `拠点 {tostring(kyotenId)} が出撃したステージに無い`
			end
			return `{kyotenId} を{if enabled
				then "孤立しない拠点にした"
				else "孤立する拠点に戻した"}`
		end
	)
	DebugCommand.register(
		"ShowHeitansen",
		"<true|false>",
		"つながりの道筋を、入っている兵站線の軍の色の線で出すか、消すかを切り替える（灰色はどちらにも入っていない）",
		function(value)
			showLines = value == true or value == "true"
			if showLines then
				if not lineFolder then
					local created = Instance.new("Folder")
					created.Name = "HeitansenLines"
					created.Parent = workspace
					lineFolder = created
				end
				local current = result
				for _, tsunagari in tsunagariList do
					drawLine(tsunagari, if current then Heitansen.gunOf(current, tsunagari) else nil)
				end
				return `つながり {#tsunagariList} 本の線を出した`
			end
			local container = lineFolder
			if container then
				container:Destroy()
				lineFolder = nil
			end
			return "つながりの線を消した"
		end
	)
end

function HeitansenService.start()
	local created = Instance.new("Folder")
	created.Name = HeitansenService.FOLDER
	created.Parent = ReplicatedStorage
	folder = created

	KyotenService.setKoritsuProvider(function(kyotenId: string): (boolean, boolean)
		return HeitansenService.isKoritsu(kyotenId), neverIsolated[kyotenId] == true
	end)
	KyotenService.loaded:Connect(onLoaded)
	KyotenService.seiatsu:Connect(onSeiatsu)
	StageService.finished:Connect(clear)
	StageService.phaseChanged:Connect(function(next: StagePhase.Phase)
		if next == "Lobby" then
			clear()
		end
	end)
	registerDebugCommands()
end

return HeitansenService
