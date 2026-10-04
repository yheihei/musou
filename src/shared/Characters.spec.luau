--!strict
local Buki = require("./Buki")
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

test("操作キャラクターは武器種と武器と奥義を持つ", function()
	for _, character in Characters.definitions do
		if character.playable then
			expect(character.bukishu ~= nil).toBe(true)
			expect(character.buki ~= nil).toBe(true)
			expect(character.ougi ~= nil).toBe(true)
		end
	end
end)

test("武器はモデルのある武器で、武器種はキャラクターの武器種と同じ", function()
	for _, character in Characters.definitions do
		local buki = character.buki
		if buki then
			expect(Buki.isBuki(buki)).toBe(true)
			expect(Buki.bukishuOf[buki]).toBe(character.bukishu)
		end
	end
end)

test("M1 の4人の武器は刃と酉花が手裏剣、石舟斎が大典太、金鬼が牛刀", function()
	local bukiOf = {}
	for _, id in { "Jin", "Torika", "Sekishusai", "KanaOni" } do
		bukiOf[id] = (Characters.get(id) :: Characters.Character).buki
	end
	expect(bukiOf).toEqual({ Jin = "Shuriken", Torika = "Shuriken", Sekishusai = "Oodenta", KanaOni = "Gyuto" })
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

test("4つのクランに画面に出す名前がある", function()
	for _, clan in Characters.clanIds do
		expect(#(Characters.clanNames[clan] or "") > 0).toBe(true)
	end
end)

test("操作キャラクターの武器と奥義には画面に出す名前がある", function()
	for _, character in Characters.definitions do
		if character.playable then
			expect(#(Buki.names[character.buki :: string] or "") > 0).toBe(true)
			expect(#(Characters.ougiNames[character.ougi :: string] or "") > 0).toBe(true)
		end
	end
	expect(Buki.names.Oodenta).toBe("大典太")
	expect(Characters.ougiNames.MutoDori).toBe("無刀取り")
end)

test("ミニマップの頭文字は、定義の頭文字か表示名の1文字目", function()
	expect(Characters.initialOf("Hayate")).toBe("ハ")
	expect(Characters.initialOf("Jin")).toBe("刃")
	expect(Characters.initialOf("ShikenJonin1")).toBe("一")
	expect(Characters.initialOf("ShikenShuryo")).toBe("首")
	expect(Characters.initialOf("Nobody")).toBe("N")
end)
