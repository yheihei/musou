--!strict
local RemoteSchema = require("./RemoteSchema")
local Shohai = require("./Shohai")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

local VICTORIES = { "TekigunShuryoGekiha", "TekigunHonjinSeiatsu" } :: { RemoteSchema.ResultReason }
local DEFEATS = { "MikatagunHonjinKanraku", "MikatagunShuryoGekiha", "HeiryokuZero" } :: { RemoteSchema.ResultReason }

test("敵軍の首領の撃破で勝つ", function()
	local condition = Shohai.shuryoGekihaOf("Tekigun")
	expect(condition).toBe("TekigunShuryoGekiha")
	expect(Shohai.judge({ condition })).toEqual({ victory = true, reason = "TekigunShuryoGekiha" })
end)

test("敵軍の本陣の制圧で勝つ", function()
	local condition = Shohai.honjinSeiatsuOf("Tekigun")
	expect(condition).toBe("TekigunHonjinSeiatsu")
	expect(Shohai.judge({ condition })).toEqual({ victory = true, reason = "TekigunHonjinSeiatsu" })
end)

test("味方軍の本陣の陥落で負ける", function()
	local condition = Shohai.honjinSeiatsuOf("Mikatagun")
	expect(condition).toBe("MikatagunHonjinKanraku")
	expect(Shohai.judge({ condition })).toEqual({ victory = false, reason = "MikatagunHonjinKanraku" })
end)

test("味方軍の首領の撃破で負ける", function()
	local condition = Shohai.shuryoGekihaOf("Mikatagun")
	expect(condition).toBe("MikatagunShuryoGekiha")
	expect(Shohai.judge({ condition })).toEqual({ victory = false, reason = "MikatagunShuryoGekiha" })
end)

test("兵力0の状態でプレイヤーが倒れると負ける", function()
	expect(Shohai.judge({ "HeiryokuZero" })).toEqual({ victory = false, reason = "HeiryokuZero" })
end)

test("時間切れで負ける", function()
	expect(Shohai.judge({ "TimeUp" })).toEqual({ victory = false, reason = "TimeUp" })
end)

test("勝ちと負けが同時に起きたら、起きた順によらず負けを優先する", function()
	for _, victory in VICTORIES do
		for _, defeat in DEFEATS do
			expect(Shohai.judge({ victory, defeat })).toEqual({ victory = false, reason = defeat })
			expect(Shohai.judge({ defeat, victory })).toEqual({ victory = false, reason = defeat })
		end
	end
	-- 勝ちが2つそろっても、負けが1つあれば負け
	local conditions =
		{ "TekigunShuryoGekiha", "TekigunHonjinSeiatsu", "HeiryokuZero" } :: { RemoteSchema.ResultReason }
	expect(Shohai.judge(conditions)).toEqual({ victory = false, reason = "HeiryokuZero" })
end)

test("勝ちどうしが同時なら、首領の撃破を理由にする", function()
	expect(Shohai.judge({ "TekigunHonjinSeiatsu", "TekigunShuryoGekiha" })).toEqual({
		victory = true,
		reason = "TekigunShuryoGekiha",
	})
end)

test(
	"負けどうしが同時なら、首領の撃破・本陣の陥落・兵力0・時間切れの順で理由を選ぶ",
	function()
		local all =
			{ "TimeUp", "HeiryokuZero", "MikatagunHonjinKanraku", "MikatagunShuryoGekiha" } :: { RemoteSchema.ResultReason }
		expect(Shohai.judge(all)).toEqual({ victory = false, reason = "MikatagunShuryoGekiha" })
		expect(Shohai.judge({ "TimeUp", "HeiryokuZero", "MikatagunHonjinKanraku" })).toEqual({
			victory = false,
			reason = "MikatagunHonjinKanraku",
		})
		expect(Shohai.judge({ "TimeUp", "HeiryokuZero" })).toEqual({ victory = false, reason = "HeiryokuZero" })
	end
)

test("同じ条件が重なっても1つとして扱う", function()
	expect(Shohai.judge({ "TekigunShuryoGekiha", "TekigunShuryoGekiha" })).toEqual({
		victory = true,
		reason = "TekigunShuryoGekiha",
	})
end)

test("条件が無ければ勝敗を決めない", function()
	expect(Shohai.judge({})).toBe(nil)
end)

test("理由を選ぶ順は、勝敗の理由をすべて1回ずつ含む", function()
	local order = table.clone(Shohai.reasonOrder)
	local reasons = table.clone(RemoteSchema.resultReasons)
	table.sort(order)
	table.sort(reasons)
	expect(order).toEqual(reasons)
end)

test("勝ちは敵軍の首領の撃破と敵軍の本陣の制圧だけ", function()
	for _, reason in RemoteSchema.resultReasons do
		expect(Shohai.isVictory(reason)).toBe(table.find(VICTORIES, reason) ~= nil)
	end
end)
