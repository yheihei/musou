--!strict
local RejectMessage = require("./RejectMessage")
local RemoteSchema = require("./RemoteSchema")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

test("拒否の理由のすべてに画面に出す文がある", function()
	for _, reason in RemoteSchema.rejectReasons do
		expect(#(RejectMessage.messages[reason] or "") > 0).toBe(true)
	end
end)

test("ストーリーの選択の拒否は、準備中と未開放を別の文で伝える", function()
	expect(RejectMessage.of("StoryNotReady")).toBe("このストーリーはまだ準備中です")
	expect(RejectMessage.of("StoryLocked")).toBe("リーダーがまだ開放していないストーリーです")
end)

test("表に無い理由はそのまま返す", function()
	expect(RejectMessage.of("Nowhere")).toBe("Nowhere")
	expect(RejectMessage.of("HikeiLimit")).toBe("秘計は 3 枚まで持ち込めます")
end)
