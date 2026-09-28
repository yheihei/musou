--!strict
-- テスト用のサーバーコマンドの窓口。ServerStorage.DebugCommand（BindableFunction）から、
-- 各サービスが登録した関数を名前で呼ぶ。Studio MCP の execute_luau（Server）や
-- 開発者コンソールのサーバーのコマンドから使う。ServerStorage はクライアントへ複製されない。
--
--   game.ServerStorage.DebugCommand:Invoke("SetOugiGauge", "Player1", 100)
--   game.ServerStorage.DebugCommand:Invoke("Help")

local Players = game:GetService("Players")
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

function DebugCommand.start()
	DebugCommand.register("Help", "", "登録済みのコマンドの一覧を返す", function()
		return DebugCommand.list()
	end)

	local bindable = ServerStorage:WaitForChild("DebugCommand") :: BindableFunction
	bindable.OnInvoke = DebugCommand.invoke
end

return DebugCommand
