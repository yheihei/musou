--!strict
local Characters = require("./Characters")
local Config = require("./Config")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

test("キャラクターの ID は表のキーと一致し、表示名がある", function()
	for key, character in Characters.definitions do
		expect(character.id).toBe(key)
		expect(#character.displayName > 0).toBe(true)
	end
end)

test("クランは4つのクランのどれか", function()
	for _, character in Characters.definitions do
		expect(table.find(Characters.clanIds, character.clan) ~= nil).toBe(true)
	end
end)

test("操作キャラクターは武器種と奥義を持つ", function()
	for _, character in Characters.definitions do
		if character.playable then
			expect(character.bukishu ~= nil).toBe(true)
			expect(character.ougi ~= nil).toBe(true)
		end
	end
end)

test("M1 の操作キャラクター4人は伊賀に属する", function()
	for _, id in { "Jin", "Torika", "Sekishusai", "KanaOni" } do
		local character = Characters.get(id)
		expect(character ~= nil).toBe(true)
		expect((character :: Characters.Character).clan).toBe("Iga")
		expect((character :: Characters.Character).playable).toBe(true)
	end
end)

test("選ぶ前のプレイヤーが使うキャラクターは操作キャラクター", function()
	local character = Characters.get(Characters.DEFAULT_ID)
	expect(character ~= nil).toBe(true)
	expect((character :: Characters.Character).playable).toBe(true)
end)

test("クランの操作キャラクターを ID の順に引ける", function()
	local ids = {}
	for _, character in Characters.playableOf("Iga") do
		table.insert(ids, character.id)
	end
	expect(ids).toEqual({ "Jin", "KanaOni", "Sekishusai", "Torika" })
	expect(Characters.playableOf("Koga")).toEqual({})
end)

test("奥義の技は、キャラクター定義の奥義の ID で置く", function()
	local ougiIds: { [string]: boolean } = {}
	for _, character in Characters.definitions do
		if character.ougi then
			ougiIds[character.ougi] = true
		end
	end
	for id in Config.Ougi.Timelines do
		expect(ougiIds[id]).toBe(true)
	end
	expect(Config.Ougi.Timelines[(Characters.get("Jin") :: Characters.Character).ougi :: string] ~= nil).toBe(true)
end)
