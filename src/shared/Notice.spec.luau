--!strict
local Notice = require("./Notice")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

local function contains(text: string, word: string): boolean
	return string.find(text, word, 1, true) ~= nil
end

test(
	"非公式の表記は、非公式であること・公式と無関係であること・パラレル設定であることを書く",
	function()
		local all = Notice.unofficial.title .. table.concat(Notice.unofficial.lines)
		expect(contains(all, "非公式")).toBe(true)
		expect(contains(all, "CryptoNinja 公式とは関係ありません")).toBe(true)
		expect(contains(all, "パラレル設定")).toBe(true)
	end
)

test("待機中の表示には見出しと本文がある", function()
	expect(#Notice.waiting.title > 0).toBe(true)
	expect(#Notice.waiting.body > 0).toBe(true)
end)
