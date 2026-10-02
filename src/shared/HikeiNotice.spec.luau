--!strict
local Hikei = require("./Hikei")
local HikeiNotice = require("./HikeiNotice")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

local function notice(kind: HikeiNotice.Kind, hikei: string?, reason: Hikei.UseFailure?): HikeiNotice.Notice
	return { kind = kind, hikei = hikei, userName = "刃", gun = "Mikatagun", reason = reason }
end

test("失敗の理由のすべてに画面に出す文がある", function()
	for _, failure in Hikei.useFailures do
		expect(#(HikeiNotice.failureMessages[failure] or "") > 0).toBe(true)
	end
end)

test("見出しは秘計の名前で、秘計の無い失敗は「秘計」", function()
	expect(HikeiNotice.titleOf(notice("Hatsudo", "Kishinka"))).toBe("鬼神化")
	expect(HikeiNotice.titleOf(notice("Shippai", nil, "NoSlot"))).toBe("秘計")
end)

test("発動・打ち消し・期限切れは発動者の名前を、失敗は理由を添える", function()
	expect(HikeiNotice.detailOf(notice("Hatsudo", "Kishinka"))).toBe("刃が発動")
	expect(HikeiNotice.detailOf(notice("Uchikeshi", "Kishinka"))).toBe("刃の効果が打ち消された")
	expect(HikeiNotice.detailOf(notice("Kigengire", "Kishinka"))).toBe("刃の効果が切れた")
	expect(HikeiNotice.detailOf(notice("Shippai", "Kishinka", "NotBattle"))).toBe("戦闘中だけ使えます")
end)

test("正しい形の知らせだけを受け付ける", function()
	expect(HikeiNotice.isNotice(notice("Hatsudo", "Kishinka"))).toBe(true)
	expect(HikeiNotice.isNotice(notice("Shippai", nil, "NoSlot"))).toBe(true)
	expect(HikeiNotice.isNotice(nil)).toBe(false)
	expect(HikeiNotice.isNotice("Hatsudo")).toBe(false)
	expect(HikeiNotice.isNotice(notice("Hatsudo", nil))).toBe(false)
	expect(HikeiNotice.isNotice(notice("Hatsudo", "Musou"))).toBe(false)
	expect(HikeiNotice.isNotice(notice("Shippai", "Kishinka"))).toBe(false)
	local wrongGun = notice("Hatsudo", "Kishinka") :: any
	wrongGun.gun = "Igagun"
	expect(HikeiNotice.isNotice(wrongGun)).toBe(false)
	local noName = notice("Hatsudo", "Kishinka") :: any
	noName.userName = nil
	expect(HikeiNotice.isNotice(noName)).toBe(false)
end)
