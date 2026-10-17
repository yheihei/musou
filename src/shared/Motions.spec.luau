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

test(
	"下忍のモーションの項目の並びは、Motions.Genin の項目と同じで、ID は 0 以上の整数",
	function()
		local expected: { [string]: boolean } = {}
		for item, id in Motions.Genin :: any do
			expected[item] = true
			expect(id >= 0 and id == math.floor(id)).toBe(true)
		end
		local actual: { [string]: boolean } = {}
		for _, item in Motions.GENIN_ITEMS do
			actual[item] = true
		end
		expect(actual).toEqual(expected)
		expect(#Motions.GENIN_ITEMS).toBe(8)
	end
)

test("下忍の待機と移動は、Ninja パックのアニメーション", function()
	local ninja: { [number]: boolean } = {}
	for _, ids in Motions.LocomotionAnimations do
		for _, id in ids do
			ninja[id] = true
		end
	end
	expect(ninja[Motions.Genin.Idle]).toBe(true)
	expect(ninja[Motions.Genin.Run]).toBe(true)
end)

test("下忍のモーションの ID は項目で引き、項目でなければ 0", function()
	expect(Motions.geninIdOf("Run")).toBe(Motions.Genin.Run)
	withMotion(Motions.Genin :: any, "Launch", 666, function()
		expect(Motions.geninIdOf("Launch")).toBe(666)
	end)
	expect(Motions.geninIdOf("Jump")).toBe(0)
	expect(Motions.isGeninItem("Knockback")).toBe(true)
	expect(Motions.isGeninItem("knockback")).toBe(false)
	expect(Motions.isGeninItem(3)).toBe(false)
end)

test(
	"下忍のモーションの ID は項目ごとに差し替えられ、項目でなければ差し替えない",
	function()
		withMotion(Motions.Genin :: any, "Attack", Motions.Genin.Attack, function()
			expect(Motions.setGeninId("Attack", 507770239)).toBe(true)
			expect(Motions.Genin.Attack).toBe(507770239)
			expect(Motions.geninIdOf("Attack")).toBe(507770239)
		end)
		Motions.GeninTests.Attack = nil
		expect(Motions.setGeninId("Jump", 1)).toBe(false)
		expect((Motions.Genin :: any).Jump).toBe(nil)
		expect(Motions.GeninTests.Jump).toBe(nil)
	end
)

test(
	"下忍のモーションは一時 ID にも差し替えられ、ID の差し替えで一時 ID は外れる",
	function()
		local temp = "f25413323a93d8928c155abc5c7b6abd"
		expect(Motions.isTempContent(temp)).toBe(true)
		expect(Motions.isTempContent("rbxtemp://12")).toBe(true)
		expect(Motions.isTempContent("f25413323a93d8928c155abc5c7b6ab")).toBe(false)
		expect(Motions.isTempContent("rbxassetid://12")).toBe(false)
		expect(Motions.isTempContent("rbxtemp://")).toBe(false)
		expect(Motions.isTempContent(12)).toBe(false)
		withMotion(Motions.Genin :: any, "Knockback", Motions.Genin.Knockback, function()
			expect(Motions.geninContentOf("Knockback")).toBe(nil)
			expect(Motions.setGeninContent("Knockback", temp, { clip = 0, from = 0.95, to = 1.25 })).toBe(true)
			expect(Motions.geninContentOf("Knockback")).toBe(temp)
			expect(Motions.geninSourceOf("Knockback")).toEqual({ clip = 0, from = 0.95, to = 1.25 })
			expect(Motions.geninIdOf("Knockback")).toBe(0)
			expect(Motions.setGeninId("Knockback", 507770677)).toBe(true)
			expect(Motions.geninContentOf("Knockback")).toBe("rbxassetid://507770677")
			expect(Motions.GeninTestContents.Knockback).toBe(nil)
		end)
		Motions.GeninTests.Knockback = nil
		expect(Motions.setGeninContent("Knockback", "rbxassetid://1")).toBe(false)
		expect(Motions.setGeninContent("Jump", temp)).toBe(false)
		expect(Motions.geninContentOf("Idle")).toBe(`rbxassetid://{Motions.Genin.Idle}`)
		expect(Motions.geninContentOf("Jump")).toBe(nil)
	end
)

test(
	"下忍のモーションは、待機・移動・攻撃・被弾の反応の順に上の優先度で重ね、待機と移動だけをくり返す",
	function()
		expect(Motions.geninPriorityOf("Idle")).toBe("Idle")
		expect(Motions.geninPriorityOf("Run")).toBe("Movement")
		expect(Motions.geninPriorityOf("Attack")).toBe("Action")
		for _, item in { "Flinch", "Knockback", "Launch", "Down", "GetUp" } do
			expect(Motions.geninPriorityOf(item)).toBe("Action2")
		end
		for _, item in Motions.GENIN_ITEMS do
			expect(Motions.isGeninLocomotion(item)).toBe(item == "Idle" or item == "Run")
		end
	end
)

test("下忍は速さが閾値を超えたら移動、閾値以下なら待機のモーションにする", function()
	expect(Motions.geninLocomotionOf(nil, 12, 0, 1, 0.3)).toBe("Run")
	expect(Motions.geninLocomotionOf("Idle", 1.5, 0, 1, 0.3)).toBe("Run")
	expect(Motions.geninLocomotionOf(nil, 0, 0, 1, 0.3)).toBe("Idle")
	expect(Motions.geninLocomotionOf("Idle", 1, 5, 1, 0.3)).toBe("Idle")
end)

test("移動のモーションの下忍は、止まってから決めた秒数たつまで移動のまま", function()
	expect(Motions.geninLocomotionOf("Run", 0, 0, 1, 0.3)).toBe("Run")
	expect(Motions.geninLocomotionOf("Run", 0.5, 0.29, 1, 0.3)).toBe("Run")
	expect(Motions.geninLocomotionOf("Run", 0, 0.3, 1, 0.3)).toBe("Idle")
	-- 待機の下忍は、止まっている秒数によらず待機のまま
	expect(Motions.geninLocomotionOf("Idle", 0, 0, 1, 0.3)).toBe("Idle")
end)

test(
	"移動のモーションは、歩く速さと等速の速さの比で流し、速さが無ければ等速",
	function()
		expect(Motions.geninRunPlaybackOf(12, 16)).toBeNear(0.75)
		expect(Motions.geninRunPlaybackOf(24, 16)).toBeNear(1.5)
		expect(Motions.geninRunPlaybackOf(0, 16)).toBe(1)
		expect(Motions.geninRunPlaybackOf(12, 0)).toBe(1)
	end
)

test(
	"被弾の反応のモーションは反応の状態から引き、打ち上げで飛んでいれば打ち上げ、ほかの飛び方は吹き飛び",
	function()
		expect(Motions.geninReactionOf("Flinch", nil)).toBe("Flinch")
		expect(Motions.geninReactionOf("Air", "Knockback")).toBe("Knockback")
		expect(Motions.geninReactionOf("Air", "Launch")).toBe("Launch")
		expect(Motions.geninReactionOf("Air", nil)).toBe("Knockback")
		expect(Motions.geninReactionOf("Down", "Launch")).toBe("Down")
		expect(Motions.geninReactionOf("GetUp", nil)).toBe("GetUp")
		expect(Motions.geninReactionOf(nil, nil)).toBe(nil)
	end
)

test(
	"のけぞりと飛ぶ反応は状態が変わるたびに流し直し、ダウンと起き上がりと反応の終わりは種類が変わったときだけ",
	function()
		expect(Motions.geninReactionRestarts(nil, "Flinch")).toBe(true)
		expect(Motions.geninReactionRestarts("Flinch", "Flinch")).toBe(true)
		expect(Motions.geninReactionRestarts("Air", "Air")).toBe(true)
		expect(Motions.geninReactionRestarts("Down", "Air")).toBe(true)
		expect(Motions.geninReactionRestarts("Air", "Down")).toBe(true)
		expect(Motions.geninReactionRestarts("Down", "Down")).toBe(false)
		expect(Motions.geninReactionRestarts("Down", "GetUp")).toBe(true)
		expect(Motions.geninReactionRestarts("GetUp", "Down")).toBe(true)
		expect(Motions.geninReactionRestarts("GetUp", nil)).toBe(true)
		expect(Motions.geninReactionRestarts(nil, nil)).toBe(false)
	end
)

test(
	"待機と移動は、反応の最中でなければ速さで選び、のけぞりと起き上がりの間は待機、飛んでいる間と倒れている間は流さない",
	function()
		expect(Motions.geninLocomotionMode(nil)).toBe("Speed")
		expect(Motions.geninLocomotionMode("Flinch")).toBe("Idle")
		expect(Motions.geninLocomotionMode("GetUp")).toBe("Idle")
		expect(Motions.geninLocomotionMode("Air")).toBe("None")
		expect(Motions.geninLocomotionMode("Down")).toBe("None")
	end
)

test(
	"取得元は、武器種の行動の項目と段・奥義・下忍の攻撃と被弾の反応をすべて持つ",
	function()
		for bukishu, motions in Motions.Bukishu :: any do
			local sources = Motions.MeshySources.Bukishu[bukishu]
			expect(sources ~= nil).toBe(true)
			for item, value in motions do
				local source = (sources :: any)[item]
				if type(value) == "table" then
					expect(#source).toBe(#value)
				else
					expect(type(source)).toBe("table")
					expect(type(source.clip)).toBe("number")
				end
			end
		end
		local ougi: { [string]: boolean } = {}
		for id in Motions.Ougi do
			ougi[id] = true
		end
		local ougiSources: { [string]: boolean } = {}
		for id in Motions.MeshySources.Ougi do
			ougiSources[id] = true
		end
		expect(ougiSources).toEqual(ougi)
		local genin: { [string]: boolean } = {}
		for _, item in Motions.GENIN_ITEMS do
			if not Motions.isGeninLocomotion(item) then
				genin[item] = true
			end
		end
		local geninSources: { [string]: boolean } = {}
		for item in Motions.MeshySources.Genin do
			geninSources[item] = true
		end
		expect(geninSources).toEqual(genin)
	end
)

test("取得元の項目は、武器種の項目と段・奥義・下忍の数だけ並ぶ", function()
	local expected = 0
	for _, motions in Motions.Bukishu :: any do
		for _, value in motions do
			expected += if type(value) == "table" then #value else 1
		end
	end
	for _ in Motions.Ougi do
		expected += 1
	end
	expected += #Motions.GENIN_ITEMS - 2
	expect(#Motions.meshySlots()).toBe(expected)
	expect(#Motions.meshySlots("Shuriken")).toBe(19)
	expect(#Motions.meshySlots("Katana")).toBe(19)
	expect(#Motions.meshySlots("Ougi")).toBe(4)
	expect(#Motions.meshySlots("Genin")).toBe(6)
	expect(#Motions.meshySlots("Bow")).toBe(0)
end)

test("取得元のクリップは一覧にあり、区間はクリップの長さの中に収まる", function()
	for _, slot in Motions.meshySlots() do
		local source = slot.source
		local clip = Motions.MeshyClips[source.clip]
		expect(clip ~= nil).toBe(true)
		expect(source.clip >= 0 and source.clip <= 696 and source.clip == math.floor(source.clip)).toBe(true)
		expect(source.from >= 0).toBe(true)
		expect(source.from < source.to).toBe(true)
		expect(source.to <= (clip :: Motions.MeshyClip).length).toBe(true)
	end
end)

test("一覧のクリップは、どれも取得元の項目で使う", function()
	local listed = {}
	for id in Motions.MeshyClips do
		table.insert(listed, id)
	end
	table.sort(listed)
	expect(Motions.meshyClipIds()).toEqual(listed)
end)

test(
	"同じクリップを使う項目には、同じ ID を入れる（0 はまだ公開していない）",
	function()
		local byClip: { [number]: number } = {}
		for _, slot in Motions.meshySlots() do
			if slot.id > 0 then
				local seen = byClip[slot.source.clip]
				if seen then
					expect(slot.id).toBe(seen)
				end
				byClip[slot.source.clip] = slot.id
			end
		end
	end
)

test("取得元の項目は、今入っている ID と名前を持つ", function()
	withMotion(Motions.Bukishu.Katana.Attack, 2, 777, function()
		withMotion(Motions.Genin :: any, "Down", 888, function()
			local katana = Motions.meshySlots("Katana")
			expect(Motions.meshySlotLabel(katana[1])).toBe("Katana Attack 1")
			expect(katana[2].id).toBe(777)
			expect(katana[2].source.clip).toBe(97)
			expect(Motions.meshySlotLabel(katana[13])).toBe("Katana JumpAttack")
			local genin = Motions.meshySlots("Genin")
			expect(Motions.meshySlotLabel(genin[5])).toBe("Genin Down")
			expect(genin[5].id).toBe(888)
		end)
	end)
	local ougi = Motions.meshySlots("Ougi")
	expect(Motions.meshySlotLabel(ougi[1])).toBe("Ougi Katon")
	expect(ougi[1].id).toBe(Motions.Ougi.Katon)
end)

-- 区間 segment の値を、小数のずれを許して比べる
local function expectSegment(segment: Motions.Segment, start: number, stop: number, speed: number, whole: boolean)
	expect(math.abs(segment.start - start) < 1e-9).toBe(true)
	expect(math.abs(segment.stop - stop) < 1e-9).toBe(true)
	expect(math.abs(segment.speed - speed) < 1e-9).toBe(true)
	expect(segment.whole).toBe(whole)
end

local function meshy(from: number, to: number): Motions.MeshySource
	return { clip = 0, from = from, to = to }
end

test(
	"区間は取得元の頭から終わりまでで、区間の長さを行動の長さで割った速さで流す",
	function()
		expectSegment(Motions.segmentOf(meshy(0.3, 1.4), 3.2, 0.55), 0.3, 1.4, 2, false)
		expectSegment(Motions.segmentOf(meshy(1.9, 2.8), 3.2, 0.45), 1.9, 2.8, 2, false)
		-- 行動の長さが分からないときと、終わりの無い行動は等速
		expectSegment(Motions.segmentOf(meshy(1.4, 2), 2.7, nil), 1.4, 2, 1, false)
		expectSegment(Motions.segmentOf(meshy(1.4, 2), 2.7, math.huge), 1.4, 2, 1, false)
	end
)

test("取得元の無い項目と、クリップの頭から終わりまでの区間は丸ごと流す", function()
	expectSegment(Motions.segmentOf(nil, 2, 0.5), 0, 2, 4, true)
	expectSegment(Motions.segmentOf(meshy(0, 1.867), 1.867, 0.5), 0, 1.867, 1.867 / 0.5, true)
	-- 取得元の長さ（GLB）と公開したトラックの長さが少しずれていても、端は端にそろえる
	expectSegment(Motions.segmentOf(meshy(0.03, 1.867), 1.9, nil), 0, 1.9, 1, true)
	expectSegment(Motions.segmentOf(meshy(1.4, 2.233), 2.2667, nil), 1.4, 2.2667, 1, false)
end)

test("区間はトラックの長さに収め、長さが 0 になる区間は丸ごとにする", function()
	expectSegment(Motions.segmentOf(meshy(0.5, 4), 2, nil), 0.5, 2, 1, false)
	expectSegment(Motions.segmentOf(meshy(3, 4), 2, 1), 0, 2, 2, true)
	expectSegment(Motions.segmentOf(meshy(1, 1), 2, nil), 0, 2, 1, true)
end)

test("長さの分からないトラックは、丸ごとの等速にしておく", function()
	expectSegment(Motions.segmentOf(meshy(0.3, 1.4), 0, 0.5), 0, 0, 1, true)
end)

test(
	"流し始めてからの位置は、区間の頭から速さの分だけ進み、区間の終わりで止まる",
	function()
		local segment = Motions.segmentOf(meshy(0.3, 1.4), 3.2, 0.55)
		expect(Motions.segmentPosition(segment, 0)).toBe(0.3)
		expect(math.abs(Motions.segmentPosition(segment, 0.25) - 0.8) < 1e-9).toBe(true)
		expect(Motions.segmentPosition(segment, 1)).toBe(1.4)
		expect(Motions.segmentPosition(segment, -0.2)).toBe(0.3)
	end
)

test(
	"行動の取得元は、行動のモーションと同じ項目（武器種の項目と段、奥義）を引く",
	function()
		local shuriken = Motions.MeshySources.Bukishu.Shuriken
		local katana = Motions.MeshySources.Bukishu.Katana
		expect(Motions.sourceForAction("Jin", "Attack", 3)).toBe(shuriken.Attack[3])
		expect(Motions.sourceForAction("Torika", "ChargeKogeki", 6)).toBe(shuriken.ChargeKogeki[6])
		expect(Motions.sourceForAction("KanaOni", "Guard")).toBe(katana.Guard)
		expect(Motions.sourceForAction("Sekishusai", "Attack")).toBe(katana.Attack[1])
		expect(Motions.sourceForAction("Jin", "Ougi")).toBe(Motions.MeshySources.Ougi.Katon)
		expect(Motions.sourceForAction("KanaOni", "Ougi")).toBe(Motions.MeshySources.Ougi.Kinton)
	end
)

test(
	"取得元の無い行動・段と、武器種の無いキャラクターと、定義に無いキャラクターの取得元は nil",
	function()
		expect(Motions.sourceForAction("Jin", "Jump")).toBe(nil)
		expect(Motions.sourceForAction("Jin", "Attack", 7)).toBe(nil)
		expect(Motions.sourceForAction("Hayate", "Attack", 1)).toBe(nil)
		expect(Motions.sourceForAction("Hayate", "Ougi")).toBe(nil)
		expect(Motions.sourceForAction("Nobody", "Attack", 1)).toBe(nil)
		expect(Motions.sourceOf("Bow", "Attack", 1)).toBe(nil)
	end
)

test(
	"型の取得元は、型が流用する武器種の行動の項目（武器種の無い NPC は刀セット）を引く",
	function()
		local katana = Motions.MeshySources.Bukishu.Katana
		expect(Motions.sourceForKata("ShikenShuryo", "Daichiwari")).toBe(katana.ChargeKogeki[6])
		expect(Motions.sourceForKata("Hayate", "Kesagiri")).toBe(katana.Attack[1])
		expect(Motions.sourceForKata("Jin", "Shurikenuchi")).toBe(Motions.MeshySources.Bukishu.Shuriken.Attack[3])
		expect(Motions.sourceForKata("ShikenJonin1", "Nai")).toBe(nil)
	end
)

test("行動と型の項目の名前は、取得元の項目の名前と同じ形", function()
	expect(Motions.actionLabelOf("Jin", "Attack", 1)).toBe("Shuriken Attack 1")
	expect(Motions.actionLabelOf("Sekishusai", "ChargeKogeki", 5)).toBe("Katana ChargeKogeki 5")
	expect(Motions.actionLabelOf("KanaOni", "Guard")).toBe("Katana Guard")
	expect(Motions.actionLabelOf("Torika", "Ougi")).toBe("Ougi PoisonShuriken")
	expect(Motions.actionLabelOf("Jin", "Attack")).toBe("Shuriken Attack 1")
	expect(Motions.actionLabelOf("Jin", "Attack", 7)).toBe(nil)
	expect(Motions.actionLabelOf("Jin", "Jump")).toBe(nil)
	expect(Motions.actionLabelOf("Hayate", "Attack", 1)).toBe(nil)
	expect(Motions.actionLabelOf("Nobody", "Ougi")).toBe(nil)
	expect(Motions.kataLabelOf("ShikenJonin2", "Senpu")).toBe("Katana ChargeKogeki 4")
	expect(Motions.kataLabelOf("Torika", "Kesagiri")).toBe("Shuriken Attack 1")
	expect(Motions.kataLabelOf("ShikenJonin2", "Nai")).toBe(nil)
end)

test(
	"操作キャラクターの行動の項目の名前は、どれも取得元の項目にあり、窓口で差し替えられる",
	function()
		local labels: { [string]: boolean } = {}
		for _, slot in Motions.meshySlots() do
			labels[Motions.meshySlotLabel(slot)] = true
		end
		for _, character in Characters.definitions do
			if not character.playable then
				continue
			end
			for action, value in Motions.Bukishu[character.bukishu :: string] :: any do
				local steps = if type(value) == "table" then #value else 1
				for step = 1, steps do
					local label = Motions.actionLabelOf(character.id, action, step)
					expect(label ~= nil and labels[label :: string] == true).toBe(true)
					expect(Motions.isTestLabel(label)).toBe(true)
				end
			end
			local ougi = Motions.actionLabelOf(character.id, "Ougi")
			expect(ougi ~= nil and labels[ougi :: string] == true).toBe(true)
		end
		expect(Motions.isTestLabel("Genin Down")).toBe(false)
		expect(Motions.isTestLabel("Shuriken Attack 7")).toBe(false)
		expect(Motions.isTestLabel(3)).toBe(false)
	end
)

test(
	"窓口の差し替えは、差し替えた項目だけ ID と区間（区間が無ければ丸ごと）を置き換える",
	function()
		local source = Motions.MeshySources.Bukishu.Shuriken.Attack[1]
		local tests: { [string]: Motions.MotionTest } = {
			["Shuriken Attack 1"] = { id = 507770239, from = 0.5, to = 1.2 },
			["Ougi Katon"] = { id = 507770453 },
		}
		local id, replaced = Motions.withTest(tests, "Shuriken Attack 1", 0, source)
		expect(id).toBe(507770239)
		expect(replaced).toEqual({ clip = 0, from = 0.5, to = 1.2 })
		local ougiId, ougiSource = Motions.withTest(tests, "Ougi Katon", 0, Motions.MeshySources.Ougi.Katon)
		expect(ougiId).toBe(507770453)
		expect(ougiSource).toBe(nil)
		local keptId, kept = Motions.withTest(tests, "Shuriken Attack 2", 12, source)
		expect(keptId).toBe(12)
		expect(kept).toBe(source)
		local noneId, none = Motions.withTest(nil, "Shuriken Attack 1", 34, source)
		expect(noneId).toBe(34)
		expect(none).toBe(source)
		local unlabeledId = Motions.withTest(tests, nil, 56, nil)
		expect(unlabeledId).toBe(56)
	end
)

test(
	"下忍の取得元は項目の区間で、窓口で差し替えた項目は差し替えの区間（無ければ丸ごと）",
	function()
		expect(Motions.geninSourceOf("Down")).toBe(Motions.MeshySources.Genin.Down)
		expect(Motions.geninSourceOf("Idle")).toBe(nil)
		expect(Motions.geninSourceOf("Run")).toBe(nil)
		expect(Motions.geninSourceOf("Jump")).toBe(nil)
		withMotion(Motions.Genin :: any, "Flinch", Motions.Genin.Flinch, function()
			withMotion(Motions.Genin :: any, "Down", Motions.Genin.Down, function()
				expect(Motions.setGeninId("Flinch", 507770453)).toBe(true)
				expect(Motions.geninSourceOf("Flinch")).toBe(nil)
				expect(Motions.setGeninId("Down", 507770239, meshy(0.5, 1))).toBe(true)
				expect(Motions.geninSourceOf("Down")).toEqual(meshy(0.5, 1))
				expect(Motions.geninSourceOf("Knockback")).toBe(Motions.MeshySources.Genin.Knockback)
			end)
		end)
		Motions.GeninTests.Flinch = nil
		Motions.GeninTests.Down = nil
		expect(Motions.geninSourceOf("Flinch")).toBe(Motions.MeshySources.Genin.Flinch)
	end
)
