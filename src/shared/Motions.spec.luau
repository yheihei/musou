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
		expect(Motions.setGeninId("Jump", 1)).toBe(false)
		expect((Motions.Genin :: any).Jump).toBe(nil)
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
