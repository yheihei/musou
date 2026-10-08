--!strict
local RemoteSchema = require("./RemoteSchema")
local TouchControls = require("./TouchControls")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

-- 端末の入力の様子。省いた項目は、Studio でない PC（キーボードとマウス）の値
local function device(overrides: { [string]: any }?): TouchControls.Device
	local result: { [string]: any } = {
		studio = false,
		touchEnabled = false,
		keyboardEnabled = true,
		preferredInput = "KeyboardAndMouse",
		lastInputKind = "Keyboard",
	}
	for key, value in overrides or {} do
		result[key] = value
	end
	return result :: any
end

-- PreferredInput が使えない端末（表に nil を書いても項目は消えないので、作ってから消す）
local function withoutPreferredInput(lastInputKind: TouchControls.InputKind): TouchControls.Device
	local result = device({ lastInputKind = lastInputKind })
	result.preferredInput = nil
	return result
end

local PHONE =
	device({ touchEnabled = true, keyboardEnabled = false, preferredInput = "Touch", lastInputKind = "Touch" })

test("Attribute の値は On と Off のほかは Auto とみなす", function()
	expect(TouchControls.modeOf("On")).toBe("On")
	expect(TouchControls.modeOf("Off")).toBe("Off")
	expect(TouchControls.modeOf("Auto")).toBe("Auto")
	expect(TouchControls.modeOf(nil)).toBe("Auto")
	expect(TouchControls.modeOf("on")).toBe("Auto")
	expect(TouchControls.modeOf(true)).toBe("Auto")
end)

test("窓口の on・off・auto は大文字と小文字を問わず読み、ほかの値は読まない", function()
	expect(TouchControls.parseMode("on")).toBe("On")
	expect(TouchControls.parseMode("OFF")).toBe("Off")
	expect(TouchControls.parseMode("Auto")).toBe("Auto")
	expect(TouchControls.parseMode("yes")).toBe(nil)
	expect(TouchControls.parseMode(1)).toBe(nil)
	expect(TouchControls.parseMode(nil)).toBe(nil)
end)

test("PreferredInput が使えるときは、Touch のときだけタッチで遊んでいるとみなす", function()
	expect(TouchControls.prefersTouch(PHONE)).toBe(true)
	-- スマホにゲームパッドをつないで使ったら出さない
	expect(TouchControls.prefersTouch(device({ touchEnabled = true, preferredInput = "Gamepad" }))).toBe(false)
	-- タッチの画面のある PC でも、キーボードとマウスを使っている間は出さない
	expect(TouchControls.prefersTouch(device({ touchEnabled = true, lastInputKind = "Touch" }))).toBe(false)
	expect(TouchControls.prefersTouch(device({ touchEnabled = true, preferredInput = "Touch" }))).toBe(true)
end)

test("PreferredInput が使えないときは、最後に使った入力の種類で決める", function()
	expect(TouchControls.prefersTouch(withoutPreferredInput("Touch"))).toBe(true)
	expect(TouchControls.prefersTouch(withoutPreferredInput("Gamepad"))).toBe(false)
	expect(TouchControls.prefersTouch(withoutPreferredInput("Keyboard"))).toBe(false)
end)

test(
	"Studio では、クリックがタッチとして届いても、キーボードが無いと報告されてもタッチとみなさない",
	function()
		local clickAsTouch =
			device({ studio = true, touchEnabled = true, preferredInput = "Touch", lastInputKind = "Touch" })
		expect(TouchControls.prefersTouch(clickAsTouch)).toBe(false)
		local noKeyboard = device({
			studio = true,
			touchEnabled = true,
			keyboardEnabled = false,
			preferredInput = "Touch",
			lastInputKind = "Touch",
		})
		expect(TouchControls.prefersTouch(noKeyboard)).toBe(false)
		expect(TouchControls.isActive("Auto", noKeyboard)).toBe(false)
		expect(TouchControls.isActive("On", noKeyboard)).toBe(true)
	end
)

test("On は端末を問わずタッチの操作を使い、Off は使わない", function()
	expect(TouchControls.isActive("On", device())).toBe(true)
	expect(TouchControls.isActive("Off", PHONE)).toBe(false)
	expect(TouchControls.isActive("Auto", PHONE)).toBe(true)
	expect(TouchControls.isActive("Auto", device())).toBe(false)
end)

test(
	"ボタンを出すのは、タッチの操作を使う人のうち戦闘のフェーズの出撃メンバーだけ",
	function()
		expect(TouchControls.isShown("Auto", PHONE, "Battle", false, false)).toBe(true)
		for _, phase in { "Lobby", "EventScene", "Result" } :: { RemoteSchema.Phase } do
			expect(TouchControls.isShown("Auto", PHONE, phase, false, false)).toBe(false)
			expect(TouchControls.isShown("On", device(), phase, false, false)).toBe(false)
		end
		expect(TouchControls.isShown("Auto", PHONE, nil, false, false)).toBe(false)
		-- 待機中の人と、イベントシーンの再生中には出さない
		expect(TouchControls.isShown("Auto", PHONE, "Battle", true, false)).toBe(false)
		expect(TouchControls.isShown("Auto", PHONE, "Battle", false, true)).toBe(false)
		-- PC では出さず、On にすれば出す
		expect(TouchControls.isShown("Auto", device(), "Battle", false, false)).toBe(false)
		expect(TouchControls.isShown("On", device(), "Battle", false, false)).toBe(true)
	end
)
