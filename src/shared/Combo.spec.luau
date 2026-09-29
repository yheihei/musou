--!strict
local ActionState = require("./ActionState")
local Characters = require("./Characters")
local Combo = require("./Combo")
local Config = require("./Config")
local Stats = require("./Stats")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

local STEPS = 6
local RESET = 0.5

test("最初の通常攻撃は1段目", function()
	expect(Combo.count(Combo.new(), 10, STEPS, RESET) + 1).toBe(1)
end)

test("途切れる時間の内に押すと次の段に進む", function()
	local state = Combo.advance(2, 10, 0.3)
	expect(Combo.count(state, 10.3, STEPS, RESET)).toBe(2)
	expect(Combo.count(state, 10.8, STEPS, RESET)).toBe(2)
end)

test("キャンセル受付が始まってから途切れる時間を超えると1段目に戻る", function()
	local state = Combo.advance(2, 10, 0.3)
	expect(Combo.count(state, 10.81, STEPS, RESET)).toBe(0)
end)

test("最後の段の後は1段目に戻る", function()
	local state = Combo.advance(STEPS, 10, 0.7)
	expect(Combo.count(state, 10.7, STEPS, RESET)).toBe(0)
end)

test("1段目から6段目まで順に進み、7回目は1段目", function()
	local state = Combo.new()
	local t = 0
	local steps = {}
	for _ = 1, STEPS + 1 do
		local step = Combo.count(state, t, STEPS, RESET) + 1
		table.insert(steps, step)
		state = Combo.advance(step, t, 0.3)
		t += 0.3
	end
	expect(steps).toEqual({ 1, 2, 3, 4, 5, 6, 1 })
end)

-- 武器種の技の定義

local function bukishuOf(characterId: string): Config.BukishuDef
	local character = Characters.get(characterId) :: Characters.Character
	return (Config.Bukishu :: any)[character.bukishu :: string]
end

-- 通常攻撃の6段を続けて出したときの、1段目の開始から6段目の終わりまでの秒数
local function comboDuration(characterId: string): number
	local speed = (Stats.baseOf(characterId) :: Stats.Values).AttackSpeed
	local total = 0
	local steps = bukishuOf(characterId).Attack
	for index, step in steps do
		local timeline = ActionState.scale(step, speed)
		total += if index < #steps then timeline.CancelFrom else ActionState.duration(timeline)
	end
	return total
end

test("どの武器種も通常攻撃は6段", function()
	for _, bukishu in { "Shuriken", "Katana" } do
		expect(#(Config.Bukishu :: any)[bukishu].Attack).toBe(6)
	end
end)

test("操作キャラクターはみな武器種の技を持つ", function()
	for id, character in Characters.definitions do
		if character.playable then
			expect(#bukishuOf(id).Attack > 0).toBe(true)
		end
	end
end)

test("刃と石舟斎では判定の形が違う段がある", function()
	local jin = bukishuOf("Jin").Attack
	local sekishusai = bukishuOf("Sekishusai").Attack
	local differs = false
	for index, step in jin do
		local a = (step.Hits :: { Config.HitDef })[1].Shape
		local b = (sekishusai[index].Hits :: { Config.HitDef })[1].Shape
		if a.Kind ~= b.Kind then
			differs = true
		end
	end
	expect(differs).toBe(true)
end)

test("手裏剣セットには飛び道具（直線）の段がある", function()
	local found = false
	for _, step in Config.Bukishu.Shuriken.Attack do
		for _, hit in step.Hits or {} do
			if hit.Shape.Kind == "Line" then
				found = true
			end
		end
	end
	expect(found).toBe(true)
end)

test("金鬼の6段は石舟斎の6段より長くかかる", function()
	expect(comboDuration("KanaOni") > comboDuration("Sekishusai")).toBe(true)
end)

test("段の判定は形ごとの寸法を持ち、持続の間に出て、受付は行動の中にある", function()
	local required = {
		Box = { "Range", "Width" },
		Sector = { "Radius", "Angle" },
		Sphere = { "Radius" },
		Line = { "Length", "Width", "Speed" },
	}
	for _, bukishu in { "Shuriken", "Katana" } do
		for _, step in (Config.Bukishu :: any)[bukishu].Attack :: { Config.ActionTimeline } do
			expect(step.CancelFrom <= ActionState.duration(step) + 1e-9).toBe(true)
			local hits = ActionState.hits(step)
			expect(#hits > 0).toBe(true)
			for _, scheduled in hits do
				-- 判定が出終わる前に次の段を受け付けない
				expect(scheduled.at <= step.Startup + step.Active + 1e-9).toBe(true)
				expect(scheduled.at <= step.CancelFrom).toBe(true)
				for _, field in required[scheduled.hit.Shape.Kind] do
					expect(type((scheduled.hit.Shape :: any)[field])).toBe("number")
				end
			end
		end
	end
end)
