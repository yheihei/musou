--!strict
local Buki = require("./Buki")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

type Node = {
	Name: string?,
	ClassName: string,
	Properties: { [string]: any }?,
	Children: { Node }?,
	attributes: { [string]: any }?,
}

local PART_CLASSES = { Part = true, WedgePart = true, MeshPart = true }
local SCRIPT_CLASSES = { Script = true, LocalScript = true, ModuleScript = true }

local function load(id: string): Node
	return testkit.readJson(`assets/weapons/{id}.model.json`)
end

local function each(node: Node, visit: (Node) -> ())
	visit(node)
	for _, child in node.Children or {} do
		each(child, visit)
	end
end

local function childNamed(node: Node, name: string): Node?
	for _, child in node.Children or {} do
		if child.Name == name then
			return child
		end
	end
	return nil
end

test("武器のモデルは assets/weapons にあり、ReplicatedStorage.Weapons に置かれる", function()
	local project = testkit.readJson("default.project.json")
	local folder = project.tree.ReplicatedStorage[Buki.FOLDER]
	expect(folder ~= nil).toBe(true)
	expect(folder["$path"]).toBe("assets/weapons")
	for _, id in Buki.ids do
		expect(load(id).ClassName).toBe("Model")
	end
end)

test("どのモデルも Handle の中に握りの Attachment の Grip を持ち、PrimaryPart は Handle", function()
	for _, id in Buki.ids do
		local model = load(id)
		local handle = childNamed(model, Buki.HANDLE) :: Node
		expect(handle ~= nil).toBe(true)
		local grip = childNamed(handle, Buki.GRIP) :: Node
		expect(grip ~= nil).toBe(true)
		expect(grip.ClassName).toBe("Attachment")
		expect((model.attributes :: any).Rojo_Target_PrimaryPart).toBe((handle.attributes :: any).Rojo_Id)
	end
end)

test("全部品は当たらず、重さを持たず、固定しない", function()
	for _, id in Buki.ids do
		local count = 0
		each(load(id), function(node)
			if PART_CLASSES[node.ClassName] then
				count += 1
				local properties = node.Properties :: { [string]: any }
				expect(properties.CanCollide).toBe(false)
				expect(properties.CanQuery).toBe(false)
				expect(properties.CanTouch).toBe(false)
				expect(properties.Massless).toBe(true)
				expect(properties.Anchored).toBe(false)
			end
		end)
		expect(count > 1).toBe(true)
	end
end)

test("Handle 以外の部品は Weld で Handle に溶接してある", function()
	for _, id in Buki.ids do
		local model = load(id)
		local handleId = ((childNamed(model, Buki.HANDLE) :: Node).attributes :: any).Rojo_Id
		for _, part in model.Children or {} do
			if part.Name ~= Buki.HANDLE then
				local weld = childNamed(part, "Weld") :: Node
				expect(weld ~= nil).toBe(true)
				expect(weld.ClassName).toBe("Weld")
				local attributes = weld.attributes :: { [string]: any }
				expect(attributes.Rojo_Target_Part0).toBe(handleId)
				expect(attributes.Rojo_Target_Part1).toBe((part.attributes :: any).Rojo_Id)
			end
		end
	end
end)

test("モデルはスクリプトを含まない", function()
	for _, id in Buki.ids do
		each(load(id), function(node)
			expect(SCRIPT_CLASSES[node.ClassName] == nil).toBe(true)
		end)
	end
end)

test("武器の ID を見分ける", function()
	expect(Buki.isBuki("Oodenta")).toBe(true)
	expect(Buki.isBuki("Katana")).toBe(false)
end)
