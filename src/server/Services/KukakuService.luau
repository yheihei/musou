--!strict
-- ロビーと区画の取得。ロビーは Workspace.Lobby、区画は Workspace.Stages の下にプレースで置き、
-- Git では管理しない（ADR 0006）。区画や目印が欠けていたら警告を出す。
-- 目印の名前と検証は ReplicatedStorage.Shared.Mejirushi にある。
--
-- - 起動時にタグ Mejirushi のパーツを透明にする（プレースには編集しやすいよう半透明で保存する）
-- - 起動時に、ロビーの SpawnLocation がプレースで唯一か、ステージの定義表の区画に出撃地点がそろっているかを確かめる

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Mejirushi = require(ReplicatedStorage.Shared.Mejirushi)
local Stages = require(ReplicatedStorage.Shared.Stages)
local DebugCommand = require(script.Parent.Parent.DebugCommand)

local KukakuService = {}

local function hide(instance: Instance)
	if instance:IsA("BasePart") then
		instance.Transparency = 1
	end
end

-- ロビーの SpawnLocation。無ければ警告を出して nil
function KukakuService.lobbySpawn(): SpawnLocation?
	local lobby = workspace:FindFirstChild(Mejirushi.LOBBY)
	local spawn = lobby and lobby:FindFirstChild(Mejirushi.LOBBY_SPAWN)
	if not spawn or not spawn:IsA("SpawnLocation") then
		warn(`KukakuService: Workspace.{Mejirushi.LOBBY}.{Mejirushi.LOBBY_SPAWN} が無い`)
		return nil
	end
	return spawn
end

-- 区画のフォルダ。無ければ警告を出して nil
function KukakuService.get(name: string): Instance?
	local stages = workspace:FindFirstChild(Mejirushi.STAGES)
	local kukaku = stages and stages:FindFirstChild(name)
	if not kukaku then
		warn(`KukakuService: 区画 {name} が Workspace.{Mejirushi.STAGES} に無い`)
		return nil
	end
	return kukaku
end

-- 区画の目印のフォルダ。区画か目印のフォルダが無ければ警告を出して nil
function KukakuService.mejirushiOf(name: string): Instance?
	local kukaku = KukakuService.get(name)
	if not kukaku then
		return nil
	end
	local folder = kukaku:FindFirstChild(Mejirushi.FOLDER)
	if not folder then
		warn(`KukakuService: 区画 {name} に目印のフォルダ {Mejirushi.FOLDER} が無い`)
		return nil
	end
	return folder
end

-- 区画の範囲のパーツ。無ければ警告を出して nil
function KukakuService.bounds(name: string): BasePart?
	local folder = KukakuService.mejirushiOf(name)
	if not folder then
		return nil
	end
	local bounds = folder:FindFirstChild(Mejirushi.BOUNDS)
	if not bounds or not bounds:IsA("BasePart") then
		warn(`KukakuService: 区画 {name} に範囲の目印 {Mejirushi.BOUNDS} が無い`)
		return nil
	end
	return bounds
end

export type ShutsugekiChiten = {
	number: number,
	cframe: CFrame,
}

-- 区画の出撃地点を番号の順に返す。欠けた番号や読めない名前があれば警告を出す。区画が無ければ空
function KukakuService.shutsugekiChiten(name: string): { ShutsugekiChiten }
	local folder = KukakuService.mejirushiOf(name)
	if not folder then
		return {}
	end
	local container = folder:FindFirstChild(Mejirushi.SHUTSUGEKI_CHITEN)
	if not container then
		warn(`KukakuService: 区画 {name} に出撃地点のフォルダ {Mejirushi.SHUTSUGEKI_CHITEN} が無い`)
		return {}
	end
	local parts: { [string]: BasePart } = {}
	local names = {}
	for _, child in container:GetChildren() do
		if child:IsA("BasePart") then
			parts[child.Name] = child
			table.insert(names, child.Name)
		end
	end
	local check = Mejirushi.checkShutsugekiChiten(names, Config.Party.MaxMembers)
	local where = `区画 {name} の出撃地点`
	if #check.missing > 0 then
		warn(`KukakuService: {where}に {table.concat(check.missing, "、")} が無い`)
	end
	if #check.duplicated > 0 then
		warn(`KukakuService: {where}の {table.concat(check.duplicated, "、")} が2つ以上ある`)
	end
	if #check.unknown > 0 then
		warn(`KukakuService: {where}の名前 {table.concat(check.unknown, "、")} は番号として読めない`)
	end
	local result = {}
	for _, number in check.numbers do
		table.insert(result, { number = number, cframe = parts[tostring(number)].CFrame })
	end
	return result
end

-- ロビーと、ステージの定義表の全区画の目印を確かめる。欠けていれば警告を出す
function KukakuService.validate()
	local lobby = KukakuService.lobbySpawn()
	local spawns = 0
	for _, descendant in workspace:GetDescendants() do
		if descendant:IsA("SpawnLocation") then
			spawns += 1
		end
	end
	if lobby and spawns > 1 then
		warn(
			`KukakuService: SpawnLocation がロビーのほかに {spawns - 1} 個ある。ロビーの1個だけにする`
		)
	end
	local names = {}
	for _, stage in Stages.definitions do
		if not table.find(names, stage.kukaku) then
			table.insert(names, stage.kukaku)
		end
	end
	table.sort(names)
	for _, name in names do
		KukakuService.bounds(name)
		KukakuService.shutsugekiChiten(name)
	end
end

local function describe(name: string): { [string]: any }
	local bounds = KukakuService.bounds(name)
	local chiten = {}
	for _, point in KukakuService.shutsugekiChiten(name) do
		local position = point.cframe.Position
		local look = point.cframe.LookVector
		table.insert(chiten, {
			number = point.number,
			position = { math.round(position.X), math.round(position.Y), math.round(position.Z) },
			look = { math.round(look.X * 100) / 100, math.round(look.Z * 100) / 100 },
		})
	end
	local result: { [string]: any } = { kukaku = name, shutsugekiChiten = chiten }
	if bounds then
		local position = bounds.Position
		result.bounds = {
			center = { math.round(position.X), math.round(position.Y), math.round(position.Z) },
			size = { bounds.Size.X, bounds.Size.Y, bounds.Size.Z },
		}
	end
	return result
end

local function registerDebugCommands()
	DebugCommand.register(
		"DumpKukaku",
		"[区画名]",
		"区画の範囲と出撃地点を JSON で返す（区画名を省くと、ロビーと区画の一覧）",
		function(name)
			if name ~= nil then
				if type(name) ~= "string" or not KukakuService.get(name) then
					return `区画 {tostring(name)} が Workspace.{Mejirushi.STAGES} に無い（警告を出した）`
				end
				return HttpService:JSONEncode(describe(name))
			end
			local stages = workspace:FindFirstChild(Mejirushi.STAGES)
			local names = {}
			for _, child in if stages then stages:GetChildren() else {} do
				table.insert(names, child.Name)
			end
			table.sort(names)
			local lobby = KukakuService.lobbySpawn()
			return HttpService:JSONEncode({
				lobby = if lobby
					then { math.round(lobby.Position.X), math.round(lobby.Position.Y), math.round(lobby.Position.Z) }
					else nil,
				kukaku = names,
			})
		end
	)
end

function KukakuService.start()
	for _, instance in CollectionService:GetTagged(Mejirushi.TAG) do
		hide(instance)
	end
	-- 窓口のコマンドがテストプレイ中に作る目印も透明にする
	CollectionService:GetInstanceAddedSignal(Mejirushi.TAG):Connect(hide)
	registerDebugCommands()
	KukakuService.validate()
end

return KukakuService
