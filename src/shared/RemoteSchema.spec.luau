--!strict
local RemoteSchema = require("./RemoteSchema")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

test("表の全 Remote が ReplicatedStorage.Remotes に RemoteEvent として宣言されている", function()
	local project = testkit.readJson("default.project.json")
	local remotes = project.tree.ReplicatedStorage.Remotes
	local names = table.clone(RemoteSchema.clientToServer)
	table.move(RemoteSchema.serverToClient, 1, #RemoteSchema.serverToClient, #names + 1, names)
	expect(#names).toBe(17)
	local missing = {}
	for _, name in names do
		local node = remotes[name]
		if not node or node["$className"] ~= "RemoteEvent" then
			table.insert(missing, name)
		end
	end
	expect(missing).toEqual({})
end)

test("C→S の Remote にはすべて検証関数がある", function()
	for _, name in RemoteSchema.clientToServer do
		expect(type((RemoteSchema.validate :: any)[name])).toBe("function")
	end
end)

test("ID は英数字と _ の1文字以上、上限の長さまで受け付ける", function()
	expect(RemoteSchema.isId("Iga1")).toBe(true)
	expect(RemoteSchema.isId("KanaOni")).toBe(true)
	expect(RemoteSchema.isId(string.rep("a", RemoteSchema.MAX_ID_LENGTH))).toBe(true)
end)

test("ID の型違い・空・長すぎる文字列・記号入りを拒否する", function()
	expect(RemoteSchema.isId(nil)).toBe(false)
	expect(RemoteSchema.isId(1)).toBe(false)
	expect(RemoteSchema.isId({ "Iga1" })).toBe(false)
	expect(RemoteSchema.isId("")).toBe(false)
	expect(RemoteSchema.isId(string.rep("a", RemoteSchema.MAX_ID_LENGTH + 1))).toBe(false)
	expect(RemoteSchema.isId("Iga 1")).toBe(false)
	expect(RemoteSchema.isId("../Iga1")).toBe(false)
end)

test("SelectStory・SelectStage・SelectCharacter は ID を1つ受け取る", function()
	expect(RemoteSchema.validate.SelectStory("Koga")).toBe(true)
	expect(RemoteSchema.validate.SelectStory()).toBe(false)
	expect(RemoteSchema.validate.SelectStory(42)).toBe(false)
	expect(RemoteSchema.validate.SelectStage("Iga1")).toBe(true)
	expect(RemoteSchema.validate.SelectStage()).toBe(false)
	expect(RemoteSchema.validate.SelectCharacter("Jin")).toBe(true)
	expect(RemoteSchema.validate.SelectCharacter(42)).toBe(false)
end)

test("SelectHikei は秘計 ID と真偽値を受け取り、欠けたら拒否する", function()
	expect(RemoteSchema.validate.SelectHikei("Fukuhei", true)).toBe(true)
	expect(RemoteSchema.validate.SelectHikei("Fukuhei", false)).toBe(true)
	expect(RemoteSchema.validate.SelectHikei("Fukuhei")).toBe(false)
	expect(RemoteSchema.validate.SelectHikei("Fukuhei", "true")).toBe(false)
	expect(RemoteSchema.validate.SelectHikei(nil, true)).toBe(false)
end)

test("LearnTokugi はキャラクター ID と特技 ID を受け取り、欠けたら拒否する", function()
	expect(RemoteSchema.validate.LearnTokugi("Jin", "Goriki1")).toBe(true)
	expect(RemoteSchema.validate.LearnTokugi("Jin")).toBe(false)
	expect(RemoteSchema.validate.LearnTokugi(nil, "Goriki1")).toBe(false)
	expect(RemoteSchema.validate.LearnTokugi("Jin", 1)).toBe(false)
	expect(RemoteSchema.validate.LearnTokugi("Jin", "Goriki 1")).toBe(false)
end)

local function expectUnique(list: { any })
	local seen = {}
	for _, value in list do
		expect(seen[value]).toBe(nil)
		seen[value] = true
	end
end

test("列挙の値は重ならない", function()
	expectUnique(RemoteSchema.phases)
	expectUnique(RemoteSchema.hyojo)
	expectUnique(RemoteSchema.rejectReasons)
	expectUnique(RemoteSchema.resultReasons)
end)
