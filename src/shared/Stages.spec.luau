--!strict
local Characters = require("./Characters")
local Stages = require("./Stages")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

test("ステージの ID は表のキーと一致する", function()
	for key, stage in Stages.definitions do
		expect(stage.id).toBe(key)
	end
end)

test("次のステージは実在し、同じクランの次の順番になっている", function()
	for _, stage in Stages.definitions do
		if stage.next then
			local nextStage = Stages.get(stage.next)
			expect(nextStage ~= nil).toBe(true)
			local found = nextStage :: Stages.Stage
			expect(found.clan).toBe(stage.clan)
			expect(found.order).toBe(stage.order + 1)
		end
	end
end)

test("ストーリーの順番は1から欠けず、最後のステージだけが次を持たない", function()
	for _, clan in Characters.clanIds do
		local orders = {}
		for _, stage in Stages.definitions do
			if stage.clan == clan and not stage.shiken then
				expect(orders[stage.order]).toBe(nil)
				orders[stage.order] = stage
			end
		end
		local count = 0
		for _ in orders do
			count += 1
		end
		for order = 1, count do
			local stage = orders[order]
			expect(stage ~= nil).toBe(true)
			expect(stage.next == nil).toBe(order == count)
		end
	end
end)

test("首領と NPC のキャラクター ID は実在し、操作キャラクターではない", function()
	for _, stage in Stages.definitions do
		local ids = table.clone(stage.npcs)
		if stage.shuryo.mikatagun then
			table.insert(ids, stage.shuryo.mikatagun)
		end
		if stage.shuryo.tekigun then
			table.insert(ids, stage.shuryo.tekigun)
		end
		for _, id in ids do
			local character = Characters.get(id)
			expect(character ~= nil).toBe(true)
			expect((character :: Characters.Character).playable).toBe(false)
		end
	end
end)

test("首領はそれぞれの軍のクランに属する", function()
	for _, stage in Stages.definitions do
		local mikatagun = stage.shuryo.mikatagun and Characters.get(stage.shuryo.mikatagun)
		if mikatagun then
			expect(mikatagun.clan).toBe(stage.clan)
		end
		local tekigun = stage.shuryo.tekigun and Characters.get(stage.shuryo.tekigun)
		if tekigun then
			expect(tekigun.clan).toBe(stage.tekigun)
		end
	end
end)

test("敵軍はストーリーのクランと別で、区画名がある", function()
	for _, stage in Stages.definitions do
		expect(stage.tekigun ~= stage.clan).toBe(true)
		expect(#stage.kukaku > 0).toBe(true)
	end
end)

test("M1 の伊賀第1ステージは敵軍が風魔、味方軍の首領がハヤテ", function()
	local iga1 = Stages.get("Iga1") :: Stages.Stage
	expect(iga1.clan).toBe("Iga")
	expect(iga1.tekigun).toBe("Fuma")
	expect(iga1.shuryo.mikatagun).toBe("Hayate")
end)

test("最初のステージと次のステージを引ける", function()
	local first = Stages.firstOf("Iga")
	expect(first and first.id).toBe("Iga1")
	expect(Stages.firstOf("Koga")).toBe(nil)
	expect(Stages.nextOf("Iga1")).toBe(nil)
	expect(Stages.nextOf("NoSuchStage")).toBe(nil)
end)

test("試験用ステージはストーリーに属さず、順番は 0 で次を持たない", function()
	local count = 0
	for _, stage in Stages.definitions do
		if stage.shiken then
			count += 1
			expect(stage.order).toBe(0)
			expect(stage.next).toBe(nil)
		else
			expect(stage.order >= 1).toBe(true)
		end
	end
	expect(count > 0).toBe(true)
end)

test("ストーリーのステージを順番に引け、試験用ステージは入らない", function()
	local ids = {}
	for _, stage in Stages.storyOf("Iga") do
		table.insert(ids, stage.id)
	end
	expect(ids).toEqual({ "Iga1" })
	expect(Stages.storyOf("Koga")).toEqual({})
	local first = Stages.firstOf("Iga")
	expect(first and first.id).toBe("Iga1")
end)
