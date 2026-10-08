--!strict
local RemoteSchema = require("./RemoteSchema")
local ResultMessage = require("./ResultMessage")
local Stages = require("./Stages")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

local function result(): any
	return {
		victory = true,
		reason = "TekigunShuryoGekiha",
		elapsed = 754.2,
		members = {
			{
				userId = 1,
				name = "yhei_hei",
				gekihasu = 120,
				seiatsusu = 1,
				kyuensu = 3,
				newlyUnlocked = { "Iga1" },
				character = "Jin",
				makimono = 4,
				jukurendo = { Buyu = 12, Chiryaku = 10, Kenro = 3 },
				newlyLearned = { "Daikatsu" },
			},
			{
				userId = 2,
				name = "Player2",
				gekihasu = 0,
				seiatsusu = 0,
				kyuensu = 0,
				newlyUnlocked = {},
				character = "Torika",
				makimono = 0,
				jukurendo = {},
				newlyLearned = {},
			},
		},
	}
end

test("勝敗の理由のすべてに画面に出す文がある", function()
	for _, reason in RemoteSchema.resultReasons do
		expect(#(ResultMessage.reasons[reason] or "") > 0).toBe(true)
	end
end)

test("勝敗の見出しは勝利か敗北", function()
	expect(ResultMessage.headline(true)).toBe("勝利")
	expect(ResultMessage.headline(false)).toBe("敗北")
end)

test("勝敗の理由を文にし、表に無い理由はそのまま返す", function()
	expect(ResultMessage.reasonOf("TekigunShuryoGekiha")).toBe("敵軍の首領を討ち取った")
	expect(ResultMessage.reasonOf("TimeUp")).toBe("時間切れ")
	expect(ResultMessage.reasonOf("Nowhere")).toBe("Nowhere")
end)

test("経過時間は分:秒で書き、分の桁はそろえない", function()
	expect(ResultMessage.formatElapsed(0)).toBe("0:00")
	expect(ResultMessage.formatElapsed(5)).toBe("0:05")
	expect(ResultMessage.formatElapsed(65)).toBe("1:05")
	expect(ResultMessage.formatElapsed(754)).toBe("12:34")
	expect(ResultMessage.formatElapsed(2400)).toBe("40:00")
end)

test("経過時間の秒の端数は切り捨てる", function()
	expect(ResultMessage.formatElapsed(0.9)).toBe("0:00")
	expect(ResultMessage.formatElapsed(59.99)).toBe("0:59")
	expect(ResultMessage.formatElapsed(754.9)).toBe("12:34")
end)

test("経過時間は 60 分を超えても分で数える", function()
	expect(ResultMessage.formatElapsed(3600)).toBe("60:00")
	expect(ResultMessage.formatElapsed(3725.5)).toBe("62:05")
	expect(ResultMessage.formatElapsed(4500)).toBe("75:00")
end)

test("負の経過時間と数でない経過時間は 0 秒にする", function()
	expect(ResultMessage.formatElapsed(-1)).toBe("0:00")
	expect(ResultMessage.formatElapsed(-0.5)).toBe("0:00")
	expect(ResultMessage.formatElapsed(0 / 0)).toBe("0:00")
end)

test("開放したステージは順番と表示名で書き、表に無い ID はそのまま返す", function()
	local stage = Stages.get("Iga1") :: Stages.Stage
	expect(ResultMessage.stageName("Iga1")).toBe(`第{stage.order}ステージ　{stage.displayName}`)
	expect(ResultMessage.stageName("Nowhere")).toBe("Nowhere")
end)

test(
	"得た巻物はキャラクターの表示名と数で書き、表に無いキャラクターは ID のまま書く",
	function()
		expect(ResultMessage.makimonoOf("Jin", 5)).toBe("刃の巻物　+5 本")
		expect(ResultMessage.makimonoOf("KanaOni", 0)).toBe("金鬼の巻物　+0 本")
		expect(ResultMessage.makimonoOf("Nowhere", 2)).toBe("Nowhereの巻物　+2 本")
	end
)

test(
	"上がった熟練度は系統の名前と数、上げた戦い方の数で書き、表に無い系統は ID のまま数を省く",
	function()
		expect(ResultMessage.jukurendoOf("Buyu", 12, 120)).toBe("武勇の熟練度　+12（撃破数 120）")
		expect(ResultMessage.jukurendoOf("Chiryaku", 10, 1)).toBe("知略の熟練度　+10（制圧数 1）")
		expect(ResultMessage.jukurendoOf("Kenro", 0, 0)).toBe("堅牢の熟練度　+0（救援数 0）")
		expect(ResultMessage.jukurendoOf("Nowhere", 2, 5)).toBe("Nowhereの熟練度　+2")
	end
)

test("新しく覚えた秘計は表示名で書き、定義に無い秘計は ID のまま書く", function()
	expect(ResultMessage.hikeiName("Daikatsu")).toBe("大喝")
	expect(ResultMessage.hikeiName("Nowhere")).toBe("Nowhere")
end)

test("待ちの文はリーダーの名前を入れ、名前が分からなければ省く", function()
	expect(ResultMessage.waitingFor("yhei_hei")).toBe("リーダーの yhei_hei が次の行動を選んでいます")
	expect(ResultMessage.waitingFor(nil)).toBe("リーダーが次の行動を選んでいます")
end)

test("正しい形の結果を受け付ける", function()
	expect(ResultMessage.isResult(result())).toBe(true)
	local noMembers = result()
	noMembers.members = {}
	expect(ResultMessage.isResult(noMembers)).toBe(true)
	local unknownReason = result()
	unknownReason.reason = "Nowhere"
	expect(ResultMessage.isResult(unknownReason)).toBe(true)
end)

test("形の違う結果は受け付けない", function()
	expect(ResultMessage.isResult(nil)).toBe(false)
	expect(ResultMessage.isResult("Victory")).toBe(false)
	local noVictory = result()
	noVictory.victory = nil
	expect(ResultMessage.isResult(noVictory)).toBe(false)
	local textElapsed = result()
	textElapsed.elapsed = "12:34"
	expect(ResultMessage.isResult(textElapsed)).toBe(false)
	local noMembers = result()
	noMembers.members = nil
	expect(ResultMessage.isResult(noMembers)).toBe(false)
	local noGekihasu = result()
	noGekihasu.members[2].gekihasu = nil
	expect(ResultMessage.isResult(noGekihasu)).toBe(false)
	local numberStage = result()
	numberStage.members[1].newlyUnlocked = { 1 }
	expect(ResultMessage.isResult(numberStage)).toBe(false)
	local textMember = result()
	textMember.members = { "yhei_hei" }
	expect(ResultMessage.isResult(textMember)).toBe(false)
	local noMakimono = result()
	noMakimono.members[1].makimono = nil
	expect(ResultMessage.isResult(noMakimono)).toBe(false)
	local noCharacter = result()
	noCharacter.members[2].character = nil
	expect(ResultMessage.isResult(noCharacter)).toBe(false)
end)

test("制圧数・救援数・熟練度・覚えた秘計の形が違う結果は受け付けない", function()
	local noSeiatsusu = result()
	noSeiatsusu.members[1].seiatsusu = nil
	expect(ResultMessage.isResult(noSeiatsusu)).toBe(false)
	local textKyuensu = result()
	textKyuensu.members[2].kyuensu = "3"
	expect(ResultMessage.isResult(textKyuensu)).toBe(false)
	local noJukurendo = result()
	noJukurendo.members[1].jukurendo = nil
	expect(ResultMessage.isResult(noJukurendo)).toBe(false)
	local textJukurendo = result()
	textJukurendo.members[1].jukurendo = { Buyu = "12" }
	expect(ResultMessage.isResult(textJukurendo)).toBe(false)
	local numberKey = result()
	numberKey.members[1].jukurendo = { 12 }
	expect(ResultMessage.isResult(numberKey)).toBe(false)
	local noLearned = result()
	noLearned.members[2].newlyLearned = nil
	expect(ResultMessage.isResult(noLearned)).toBe(false)
	local numberLearned = result()
	numberLearned.members[1].newlyLearned = { 1 }
	expect(ResultMessage.isResult(numberLearned)).toBe(false)
end)
