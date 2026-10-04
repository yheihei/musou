--!strict
local BattleStatus = require("./BattleStatus")
local Config = require("./Config")
local RemoteSchema = require("./RemoteSchema")
local ResultMessage = require("./ResultMessage")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

local PARAMS: Config.BattleStatusSection = { TimeWarning = 300, TimeDanger = 60 }

test("戦況を出すのは戦闘のフェーズの出撃メンバーだけ", function()
	expect(BattleStatus.isVisible("Battle", false, false)).toBe(true)
	for _, phase in { "Lobby", "EventScene", "Result" } :: { RemoteSchema.Phase } do
		expect(BattleStatus.isVisible(phase, false, false)).toBe(false)
	end
	expect(BattleStatus.isVisible(nil, false, false)).toBe(false)
end)

test("待機中の人とパーティーにいない人には、どのフェーズでも出さない", function()
	for _, phase in RemoteSchema.phases do
		expect(BattleStatus.isVisible(phase, true, false)).toBe(false)
	end
end)

test("イベントシーンの再生中は出さない", function()
	expect(BattleStatus.isVisible("Battle", false, true)).toBe(false)
end)

test("残り時間は分:秒で書き、分の桁はそろえない", function()
	expect(BattleStatus.formatRemaining(2400)).toBe("40:00")
	expect(BattleStatus.formatRemaining(754)).toBe("12:34")
	expect(BattleStatus.formatRemaining(599)).toBe("9:59")
	expect(BattleStatus.formatRemaining(65)).toBe("1:05")
	expect(BattleStatus.formatRemaining(5)).toBe("0:05")
	expect(BattleStatus.formatRemaining(3725)).toBe("62:05")
end)

test("残り時間の書き方は、秒が整数ならリザルトの経過時間と同じ", function()
	for _, seconds in { 0, 5, 59, 60, 65, 599, 600, 754, 2400, 3725 } do
		expect(BattleStatus.formatRemaining(seconds)).toBe(ResultMessage.formatElapsed(seconds))
	end
end)

test("残り時間の秒の端数は切り上げ、0:00 は時間切れのときだけ", function()
	expect(BattleStatus.formatRemaining(2399.2)).toBe("40:00")
	expect(BattleStatus.formatRemaining(599.5)).toBe("10:00")
	expect(BattleStatus.formatRemaining(59.01)).toBe("1:00")
	expect(BattleStatus.formatRemaining(0.1)).toBe("0:01")
	expect(BattleStatus.formatRemaining(0)).toBe("0:00")
end)

test("過ぎた残り時間と数でない残り時間は 0:00、残り時間が無ければ --:--", function()
	expect(BattleStatus.formatRemaining(-3)).toBe("0:00")
	expect(BattleStatus.formatRemaining(-0.5)).toBe("0:00")
	expect(BattleStatus.formatRemaining(0 / 0)).toBe("0:00")
	expect(BattleStatus.formatRemaining(nil)).toBe("--:--")
	expect(BattleStatus.NO_REMAINING).toBe("--:--")
end)

test("残り時間は TimeWarning 秒以下で注意、TimeDanger 秒以下で危険", function()
	expect(BattleStatus.remainingEmphasis(2400, PARAMS)).toBe("None")
	expect(BattleStatus.remainingEmphasis(301, PARAMS)).toBe("None")
	expect(BattleStatus.remainingEmphasis(300, PARAMS)).toBe("Warning")
	expect(BattleStatus.remainingEmphasis(61, PARAMS)).toBe("Warning")
	expect(BattleStatus.remainingEmphasis(60, PARAMS)).toBe("Danger")
	expect(BattleStatus.remainingEmphasis(0, PARAMS)).toBe("Danger")
	expect(BattleStatus.remainingEmphasis(-1, PARAMS)).toBe("Danger")
end)

test(
	"残り時間の強調は画面に出す秒（切り上げ）で決め、文と色の変わり目をそろえる",
	function()
		-- 300.5 秒は 5:01 と出すので、まだ強調しない
		expect(BattleStatus.formatRemaining(300.5)).toBe("5:01")
		expect(BattleStatus.remainingEmphasis(300.5, PARAMS)).toBe("None")
		expect(BattleStatus.formatRemaining(299.5)).toBe("5:00")
		expect(BattleStatus.remainingEmphasis(299.5, PARAMS)).toBe("Warning")
		expect(BattleStatus.remainingEmphasis(60.5, PARAMS)).toBe("Warning")
		expect(BattleStatus.remainingEmphasis(59.5, PARAMS)).toBe("Danger")
	end
)

test("残り時間が無ければ強調しない", function()
	expect(BattleStatus.remainingEmphasis(nil, PARAMS)).toBe("None")
	expect(BattleStatus.remainingEmphasis(nil)).toBe("None")
end)

test("Config のしきい値は、注意が危険より長く、制限時間より短い", function()
	local p = Config.BattleStatus
	expect(p.TimeDanger > 0).toBe(true)
	expect(p.TimeWarning > p.TimeDanger).toBe(true)
	expect(p.TimeWarning < Config.Stage.TimeLimit).toBe(true)
	expect(BattleStatus.remainingEmphasis(Config.Stage.TimeLimit)).toBe("None")
	expect(BattleStatus.remainingEmphasis(p.TimeWarning)).toBe("Warning")
	expect(BattleStatus.remainingEmphasis(p.TimeDanger)).toBe("Danger")
end)

test("兵力は「兵力 7」と書く", function()
	expect(BattleStatus.heiryokuText(7)).toBe("兵力 7")
	expect(BattleStatus.heiryokuText(Config.Stage.Heiryoku)).toBe(`兵力 {Config.Stage.Heiryoku}`)
	expect(BattleStatus.heiryokuText(0)).toBe("兵力 0")
end)

test("兵力が無ければ数の代わりに - を出す", function()
	expect(BattleStatus.heiryokuText(nil)).toBe("兵力 -")
end)

test("兵力の端数は切り捨て、負の値と数でない値は 0 と書く", function()
	expect(BattleStatus.heiryokuText(2.7)).toBe("兵力 2")
	expect(BattleStatus.heiryokuText(-1)).toBe("兵力 0")
	expect(BattleStatus.heiryokuText(0 / 0)).toBe("兵力 0")
end)

test("兵力0は危険として強調し、1 以上と兵力が無いときは強調しない", function()
	expect(BattleStatus.heiryokuEmphasis(0)).toBe("Danger")
	expect(BattleStatus.heiryokuEmphasis(-1)).toBe("Danger")
	expect(BattleStatus.heiryokuEmphasis(0.5)).toBe("Danger")
	expect(BattleStatus.heiryokuEmphasis(1)).toBe("None")
	expect(BattleStatus.heiryokuEmphasis(Config.Stage.Heiryoku)).toBe("None")
	expect(BattleStatus.heiryokuEmphasis(nil)).toBe("None")
end)

test("士気のゲージは Min で空、Max で満タン、その間は割合で伸びる", function()
	local shiki = Config.Shiki
	expect(BattleStatus.shikiRatio(shiki.Min)).toBe(0)
	expect(BattleStatus.shikiRatio(shiki.Max)).toBe(1)
	expect(BattleStatus.shikiRatio(shiki.Initial)).toBeNear((shiki.Initial - shiki.Min) / (shiki.Max - shiki.Min))
	expect(BattleStatus.shikiRatio(70, { Min = 20, Max = 120 })).toBeNear(0.5)
	expect(BattleStatus.shikiRatio(45, { Min = 20, Max = 120 })).toBeNear(0.25)
end)

test("士気のゲージは範囲の外の値を 0 から 1 に収め、値が無ければ空", function()
	local range = { Min = 0, Max = 100 }
	expect(BattleStatus.shikiRatio(-10, range)).toBe(0)
	expect(BattleStatus.shikiRatio(150, range)).toBe(1)
	expect(BattleStatus.shikiRatio(0 / 0, range)).toBe(0)
	expect(BattleStatus.shikiRatio(nil, range)).toBe(0)
	expect(BattleStatus.shikiRatio(nil)).toBe(0)
end)
