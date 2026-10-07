--!strict
local ActionState = require("./ActionState")
local Characters = require("./Characters")
local Config = require("./Config")
local Motions = require("./Motions")
local Stats = require("./Stats")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

test("待機と移動は Ninja パックの7種で、どれにも中のアニメーションがある", function()
	local count = 0
	for name, id in Motions.Locomotion :: any do
		count += 1
		expect(id > 0).toBe(true)
		expect(#Motions.LocomotionAnimations[name] > 0).toBe(true)
	end
	expect(count).toBe(7)
end)

test("武器種ごとの行動の項目は、Config の武器種と段の数に合っている", function()
	for bukishu, set in Config.Bukishu :: any do
		local motions = Motions.Bukishu[bukishu]
		expect(motions ~= nil).toBe(true)
		expect(#motions.Attack).toBe(#set.Attack)
		expect(#motions.ChargeKogeki).toBe(#set.ChargeKogeki)
	end
end)

test("奥義の項目は、操作キャラクターの奥義の ID と同じ", function()
	local expected: { [string]: boolean } = {}
	for _, character in Characters.definitions do
		if character.playable and character.ougi then
			expected[character.ougi] = true
		end
	end
	local actual: { [string]: boolean } = {}
	for id in Motions.Ougi do
		actual[id] = true
	end
	expect(actual).toEqual(expected)
end)

test("行動のモーションは武器種と行動と段で引き、無い項目は 0", function()
	expect(Motions.actionOf("Shuriken", "Attack", 3)).toBe(Motions.Bukishu.Shuriken.Attack[3])
	expect(Motions.actionOf("Katana", "Guard")).toBe(Motions.Bukishu.Katana.Guard)
	expect(Motions.actionOf("Katana", "Attack", 7)).toBe(0)
	expect(Motions.actionOf("Bow", "Attack", 1)).toBe(0)
	expect(Motions.actionOf("Shuriken", "Jump")).toBe(0)
end)

-- 一覧の set[key] を value に差し替えて fn を実行し、終わったら戻す
local function withMotion(set: { [any]: number }, key: any, value: number, fn: () -> ())
	local saved = set[key]
	set[key] = value
	local ok, err = pcall(fn :: () -> any)
	set[key] = saved
	if not ok then
		error(err, 0)
	end
end

test("キャラクターの行動のモーションは武器種の項目から段で引く", function()
	withMotion(Motions.Bukishu.Katana.ChargeKogeki, 3, 111, function()
		expect(Motions.forAction("KanaOni", "ChargeKogeki", 3)).toBe(111)
		expect(Motions.forAction("Sekishusai", "ChargeKogeki", 3)).toBe(111)
		expect(Motions.forAction("Jin", "ChargeKogeki", 3)).toBe(Motions.Bukishu.Shuriken.ChargeKogeki[3])
	end)
	withMotion(Motions.Bukishu.Shuriken, "Guard", 222, function()
		expect(Motions.forAction("Torika", "Guard")).toBe(222)
	end)
end)

test("奥義のモーションはキャラクターの奥義の項目から引く", function()
	withMotion(Motions.Ougi, "Kinton", 333, function()
		expect(Motions.forAction("KanaOni", "Ougi")).toBe(333)
		expect(Motions.forAction("Sekishusai", "Ougi")).toBe(Motions.Ougi.MutoDori)
	end)
end)

test(
	"項目の無い行動と、武器種の無いキャラクターと、定義に無いキャラクターは 0",
	function()
		expect(Motions.forAction("Jin", "Jump")).toBe(0)
		expect(Motions.forAction("Hayate", "Attack", 1)).toBe(0)
		expect(Motions.forAction("Hayate", "Ougi")).toBe(0)
		expect(Motions.forAction("Nobody", "Attack", 1)).toBe(0)
	end
)

test(
	"型のモーションの項目は、Config の上忍と首領の型の ID と同じで、武器種の行動の項目を指す",
	function()
		local expected: { [string]: boolean } = {}
		for id in Config.Kata.Jonin do
			expected[id] = true
		end
		for id in Config.Kata.Shuryo do
			expected[id] = true
		end
		local actual: { [string]: boolean } = {}
		for id, entry in Motions.Kata do
			actual[id] = true
			local value = (Motions.Bukishu[Motions.KATA_BUKISHU] :: any)[entry.action]
			if type(value) == "table" then
				expect(entry.step ~= nil and value[entry.step] ~= nil).toBe(true)
			else
				expect(type(value)).toBe("number")
			end
		end
		expect(actual).toEqual(expected)
	end
)

test(
	"型のモーションは、武器種の決まっていない NPC は刀セットから、武器種のあるキャラクターはその武器種から引く",
	function()
		withMotion(Motions.Bukishu.Katana.ChargeKogeki, 6, 444, function()
			withMotion(Motions.Bukishu.Shuriken.ChargeKogeki, 6, 555, function()
				expect(Motions.forKata("ShikenShuryo", "Daichiwari")).toBe(444)
				expect(Motions.forKata("Nobody", "Daichiwari")).toBe(444)
				expect(Motions.forKata("Jin", "Daichiwari")).toBe(555)
			end)
		end)
		expect(Motions.forKata("ShikenShuryo", "Nai")).toBe(0)
	end
)

test("キャラクターのモーションの ID を重なりなく並べ、0 は含めない", function()
	withMotion(Motions.Bukishu.Katana.Attack, 1, 20, function()
		withMotion(Motions.Bukishu.Katana.Attack, 2, 20, function()
			withMotion(Motions.Bukishu.Katana, "Down", 10, function()
				withMotion(Motions.Ougi, "MutoDori", 30, function()
					expect(Motions.idsOf("Sekishusai")).toEqual({ 10, 20, 30 })
					expect(Motions.idsOf("KanaOni")).toEqual({ 10, 20 })
					expect(Motions.idsOf("Jin")).toEqual({})
				end)
			end)
		end)
	end)
end)

test("被弾の反応は攻撃より上の優先度で重ね、ガードだけをくり返す", function()
	for _, action in { "Flinch", "Down", "GetUp", "GuardHit" } do
		expect(Motions.priorityOf(action)).toBe("Action2")
	end
	for _, action in { "Attack", "ChargeKogeki", "JumpAttack", "Guard", "KinkyuKaihi", "Ougi" } do
		expect(Motions.priorityOf(action)).toBe("Action")
		expect(Motions.isLooped(action)).toBe(action == "Guard")
	end
end)

test("再生の速さはモーションの長さを行動の長さで割ったもの", function()
	expect(Motions.playbackSpeed(1.2, 0.3)).toBeNear(4)
	expect(Motions.playbackSpeed(0.5, 1)).toBeNear(0.5)
end)

test("長さの分からないモーションと終わりの無い行動は等速", function()
	expect(Motions.playbackSpeed(0, 0.3)).toBe(1)
	expect(Motions.playbackSpeed(1.2, nil)).toBe(1)
	expect(Motions.playbackSpeed(1.2, math.huge)).toBe(1)
	expect(Motions.playbackSpeed(1.2, 0)).toBe(1)
end)

test("金鬼は同じ段のモーションを石舟斎より遅く再生する", function()
	local step = Config.Bukishu.Katana.Attack[1]
	local function speedOf(characterId: string): number
		local attackSpeed = (Stats.baseOf(characterId) :: Stats.Values).AttackSpeed
		return Motions.playbackSpeed(1, ActionState.duration(ActionState.scale(step, attackSpeed)))
	end
	expect(speedOf("KanaOni") < speedOf("Sekishusai")).toBe(true)
	expect(speedOf("KanaOni") / speedOf("Sekishusai")).toBeNear(0.8)
end)
