--!strict
-- テスト用のサーバーコマンドの窓口。ServerStorage.DebugCommand（BindableFunction）から、
-- 各サービスが登録した関数を名前で呼ぶ。テストプレイ中のコマンドバーや、
-- 開発者コンソールのサーバーのコマンドから使う。ServerStorage はクライアントへ複製されない。
--
--   game.ServerStorage.DebugCommand:Invoke("SetOugiGauge", "Player1", 100)
--   game.ServerStorage.DebugCommand:Invoke("Help")
--
-- Studio MCP の execute_luau は Invoke を呼べない（Capabilities で拒否される）ので、Studio では Attribute の入口も設ける。
-- ServerStorage.DebugCommand の Attribute の Request に、JSON で {"id": 任意の文字列, "args": [コマンド名, 引数...]} を書くと、
-- サーバーが窓口を呼び、結果を Attribute の Response に {"id": 同じ id, "results": [結果の文字列...]} で書く。
-- 命令は1つずつ書き、Response の id が変わってから次を書く（続けて書くと前の命令を読み落とす）

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

type Handler = (...any) -> ...any

type Command = {
	name: string,
	args: string,
	description: string,
	handler: Handler,
}

local DebugCommand = {}

local commands: { [string]: Command } = {}

-- コマンドを登録する。args は引数の説明（"<プレイヤー名> <値>" など）
function DebugCommand.register(name: string, args: string, description: string, handler: Handler)
	assert(commands[name] == nil, `DebugCommand: {name} は登録済み`)
	commands[name] = {
		name = name,
		args = args,
		description = description,
		handler = handler,
	}
end

-- 登録済みのコマンドの一覧を、名前の順に1行ずつ返す
function DebugCommand.list(): string
	local names = {}
	for name in commands do
		table.insert(names, name)
	end
	table.sort(names)
	local lines = {}
	for _, name in names do
		local command = commands[name]
		local args = if command.args ~= "" then " " .. command.args else ""
		table.insert(lines, `  {name}{args}  {command.description}`)
	end
	return table.concat(lines, "\n")
end

-- 名前（Name）でプレイヤーを探す。見つからなければ、いるプレイヤーの名前を添えてエラーにする
function DebugCommand.findPlayer(name: unknown): Player
	if type(name) == "string" then
		local player = Players:FindFirstChild(name)
		if player and player:IsA("Player") then
			return player
		end
	end
	local names = {}
	for _, player in Players:GetPlayers() do
		table.insert(names, player.Name)
	end
	error(`プレイヤー {tostring(name)} がいない（いるのは {table.concat(names, "、")}）`, 0)
end

-- 数値の引数を読む。開発者コンソールから文字列で渡されたときも数値にする
function DebugCommand.toNumber(value: unknown, label: string): number
	local number = tonumber(value)
	if number == nil then
		error(`{label} は数値で指定する（{tostring(value)}）`, 0)
	end
	return number
end

-- 名前でコマンドを呼ぶ。未登録なら一覧を、失敗したらエラーの内容を文字列で返す
function DebugCommand.invoke(name: unknown, ...: any): ...any
	local command = if type(name) == "string" then commands[name] else nil
	if not command then
		return `未登録のコマンド {tostring(name)}。登録済みのコマンドは次のとおり\n{DebugCommand.list()}`
	end
	local results = table.pack(pcall(command.handler, ...))
	if not results[1] then
		return `{command.name} が失敗した: {tostring(results[2])}`
	end
	return table.unpack(results, 2, results.n)
end

-- Attribute の入口の名前
DebugCommand.REQUEST_ATTRIBUTE = "Request"
DebugCommand.RESPONSE_ATTRIBUTE = "Response"

-- Attribute の Request に書かれた命令で窓口を呼び、結果を Response に書く
local function handleRequest(bindable: BindableFunction)
	local raw = bindable:GetAttribute(DebugCommand.REQUEST_ATTRIBUTE)
	if type(raw) ~= "string" then
		return
	end
	local decoded, request = pcall(function()
		return HttpService:JSONDecode(raw)
	end)
	local id = if decoded and type(request) == "table" then request.id else nil
	local args = if decoded and type(request) == "table" and type(request.args) == "table" then request.args else nil
	local results = {}
	if not args then
		table.insert(results, `命令の形が正しくない（{raw}）`)
	else
		local packed = table.pack(DebugCommand.invoke(table.unpack(args)))
		for index = 1, packed.n do
			table.insert(results, tostring(packed[index]))
		end
	end
	bindable:SetAttribute(DebugCommand.RESPONSE_ATTRIBUTE, HttpService:JSONEncode({ id = id, results = results }))
end

function DebugCommand.start()
	DebugCommand.register("Help", "", "登録済みのコマンドの一覧を返す", function()
		return DebugCommand.list()
	end)

	local bindable = ServerStorage:WaitForChild("DebugCommand") :: BindableFunction
	bindable.OnInvoke = DebugCommand.invoke
	-- Attribute の入口は Studio だけで受け付ける（公開サーバーでは開発者コンソールから Invoke を呼ぶ）
	if RunService:IsStudio() then
		bindable:GetAttributeChangedSignal(DebugCommand.REQUEST_ATTRIBUTE):Connect(function()
			task.spawn(handleRequest, bindable)
		end)
	end
end

return DebugCommand
