--!strict
local RemoteSchema = require("./RemoteSchema")
local Title = require("./Title")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

test("タイトルは日本語と英語の両方がある", function()
	expect(#Title.name.ja > 0).toBe(true)
	expect(#Title.name.en > 0).toBe(true)
end)

test("PartyState が届く前とロビーのフェーズでは、タイトル画面を出せる", function()
	expect(Title.canShow(nil, true)).toBe(true)
	expect(Title.canShow(nil, false)).toBe(true)
	expect(Title.canShow("Lobby", true)).toBe(true)
	expect(Title.canShow("Lobby", false)).toBe(true)
end)

test(
	"ロビー以外のフェーズでは、出撃メンバーには出さず、待機中の人とパーティーにいない人には出せる",
	function()
		for _, phase in RemoteSchema.phases do
			if phase ~= "Lobby" then
				expect(Title.canShow(phase, true)).toBe(false)
				expect(Title.canShow(phase, false)).toBe(true)
			end
		end
	end
)
