--!strict
local Config = require("./Config")
local Hikei = require("./Hikei")
local TouchLayout = require("./TouchLayout")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

-- 横画面の端末の、上のバーを除いた画面の大きさ（ピクセル）
local DEVICES = {
	{ name = "iPhone SE", width = 667, height = 317 },
	{ name = "小さい Android", width = 640, height = 302 },
	{ name = "iPhone 14（ノッチとホームバーを除く）", width = 750, height = 311 },
	{ name = "iPhone 15 Pro Max（ノッチとホームバーを除く）", width = 814, height = 351 },
	{ name = "横長の Android", width = 800, height = 302 },
	{ name = "iPad", width = 1024, height = 710 },
	{ name = "iPad mini", width = 1133, height = 666 },
	{ name = "iPad Pro 12.9", width = 1366, height = 966 },
	{ name = "Android タブレット", width = 1280, height = 742 },
	{ name = "PC の小さい窓", width = 1100, height = 550 },
	{ name = "Studio の窓", width = 1280, height = 600 },
	{ name = "フル HD", width = 1920, height = 1022 },
}

-- ボタンの範囲を、名前を添えて並べる
local function buttonsOf(layout: TouchLayout.Layout): { { name: string, rect: TouchLayout.Rect } }
	local list = {
		{ name = "Attack", rect = layout.attack },
		{ name = "ChargeKogeki", rect = layout.chargeKogeki },
		{ name = "Guard", rect = layout.guard },
		{ name = "Ougi", rect = layout.ougi },
	}
	for slot, rect in layout.hikei do
		table.insert(list, { name = `Hikei{slot}`, rect = rect })
	end
	return list
end

-- ボタンと重なってはいけない範囲（ほかの戦闘の画面の部品、ジャンプボタン、サムスティック）
local function avoidedOf(layout: TouchLayout.Layout): { { name: string, rect: TouchLayout.Rect } }
	local list = {
		{ name = "Jump", rect = layout.jump },
		{ name = "Thumbstick", rect = TouchLayout.thumbstickOf(layout.width, layout.height) },
	}
	for name, rect in TouchLayout.screensOf(layout.width, layout.height) do
		table.insert(list, { name = name, rect = rect })
	end
	return list
end

-- 重なりと画面からのはみ出しを文にして集める（無ければ空）
local function problemsOf(layout: TouchLayout.Layout): { string }
	local problems = {}
	local buttons = buttonsOf(layout)
	for index, button in buttons do
		local r = button.rect
		if r.x < 0 or r.y < 0 or r.x + r.width > layout.width or r.y + r.height > layout.height then
			table.insert(problems, `{button.name} が画面からはみ出す`)
		end
		for other = index + 1, #buttons do
			if TouchLayout.overlaps(r, buttons[other].rect) then
				table.insert(problems, `{button.name} と {buttons[other].name} が重なる`)
			end
		end
		for _, avoided in avoidedOf(layout) do
			if TouchLayout.overlaps(r, avoided.rect) then
				table.insert(problems, `{button.name} と {avoided.name} が重なる`)
			end
		end
	end
	return problems
end

test("倍率は設計の大きさに収まるように決め、大きい画面では縮めない", function()
	local p = Config.TouchControls
	expect(TouchLayout.scaleOf(667, 317)).toBeNear(317 / p.DesignHeight)
	expect(TouchLayout.scaleOf(1024, 710)).toBeNear(1024 / p.DesignWidth)
	expect(TouchLayout.scaleOf(1366, 966)).toBe(1)
	expect(TouchLayout.scaleOf(2560, 1380)).toBe(1)
	-- 大きさがまだ決まっていない画面では縮めない
	expect(TouchLayout.scaleOf(0, 0)).toBe(1)
end)

test(
	"標準のジャンプボタンは、短い辺が 500 以下なら一辺 70、それより大きければ 120 で右下に出る",
	function()
		expect(TouchLayout.jumpOf(667, 317)).toEqual({ x = 572, y = 227, width = 70, height = 70 })
		expect(TouchLayout.jumpOf(1024, 710)).toEqual({ x = 854, y = 500, width = 120, height = 120 })
	end
)

test(
	"短い辺が境目に近い画面では、大小どちらのジャンプボタンの範囲も避ける",
	function()
		-- 短い辺 480 は小さいジャンプボタンだが、ノッチやホームバーの分だけ大きく測られると大きいほうになる
		expect(TouchLayout.jumpOf(900, 480)).toEqual({ x = 730, y = 270, width = 145, height = 190 })
		expect(TouchLayout.jumpOf(900, 440)).toEqual({ x = 805, y = 350, width = 70, height = 70 })
	end
)

test(
	"どの端末でも、ボタンは画面に収まり、互いにもほかの画面の部品にも重ならない",
	function()
		for _, device in DEVICES do
			local layout = TouchLayout.compute(device.width, device.height)
			local problems = problemsOf(layout)
			if #problems > 0 then
				error(`{device.name}（{device.width}x{device.height}）: {table.concat(problems, "、")}`)
			end
			expect(layout.fits).toBe(true)
		end
	end
)

test("横画面のどの大きさでも、ボタンは収まって重ならない", function()
	local failures = {}
	for width = 560, 2600, 40 do
		for height = 240, 1100, 20 do
			if width >= height then
				local layout = TouchLayout.compute(width, height)
				if not layout.fits or #problemsOf(layout) > 0 then
					table.insert(failures, `{width}x{height}`)
				end
			end
		end
	end
	expect(failures).toEqual({})
end)

test("通常攻撃はジャンプボタンの左、チャージ攻撃は通常攻撃の左に並ぶ", function()
	for _, device in DEVICES do
		local layout = TouchLayout.compute(device.width, device.height)
		local gap = Config.TouchControls.Gap
		expect(layout.attack.x + layout.attack.width + gap).toBeNear(layout.jump.x)
		expect(layout.chargeKogeki.x + layout.chargeKogeki.width + gap).toBeNear(layout.attack.x)
		expect(layout.chargeKogeki.y + layout.chargeKogeki.height / 2).toBeNear(
			layout.attack.y + layout.attack.height / 2
		)
	end
end)

test(
	"スマホでは、ガードと奥義をジャンプボタンの上に、通常攻撃の上端をジャンプボタンの上端にそろえて置く",
	function()
		local p = Config.TouchControls
		for _, size in { { 667, 317 }, { 640, 302 }, { 750, 311 }, { 814, 351 } } do
			local layout = TouchLayout.compute(size[1], size[2])
			expect(layout.attack.y).toBeNear(layout.jump.y)
			expect(layout.guard.x + layout.guard.width).toBeNear(layout.width - p.Margin)
			expect(layout.guard.y + layout.guard.height + p.Gap).toBeNear(layout.jump.y)
			expect(layout.ougi.x + layout.ougi.width + p.Gap).toBeNear(layout.guard.x)
		end
	end
)

test(
	"ジャンプボタンの上に入らない画面では、ガードと奥義を通常攻撃の上に置く",
	function()
		local p = Config.TouchControls
		local layout = TouchLayout.compute(1100, 550)
		expect(layout.fits).toBe(true)
		expect(layout.guard.x + layout.guard.width + p.Gap).toBeNear(layout.jump.x)
		expect(layout.guard.y + layout.guard.height + p.Gap).toBeNear(layout.attack.y)
		-- 秘計の知らせの下に入れる
		local notice = TouchLayout.screensOf(layout.width, layout.height).HikeiNotice
		expect(layout.ougi.y >= notice.y + notice.height + p.Gap).toBe(true)
	end
)

test(
	"秘計の枚は、左上の撃破数の下に枚の順に並び、サムスティックの範囲より上にある",
	function()
		local p = Config.TouchControls
		local layout = TouchLayout.compute(667, 317)
		local gekihasu = TouchLayout.gekihasuOf()
		expect(#layout.hikei).toBe(Hikei.MOCHIKOMI_MAX)
		for slot, rect in layout.hikei do
			expect(rect.y).toBe(gekihasu.y + gekihasu.height + p.Gap)
			expect(rect.x).toBe(p.Margin + (slot - 1) * (p.HikeiWidth + p.Gap))
		end
		local thumbstick = TouchLayout.thumbstickOf(layout.width, layout.height)
		expect(layout.hikei[1].y + layout.hikei[1].height < thumbstick.y).toBe(true)
	end
)

test("スマホでも、ボタンは指で押せる大きさ（44 ピクセル）を下回らない", function()
	for _, size in { { 667, 317 }, { 640, 302 }, { 750, 311 }, { 800, 302 } } do
		local layout = TouchLayout.compute(size[1], size[2])
		for _, button in buttonsOf(layout) do
			local shortSide = math.min(button.rect.width, button.rect.height) * layout.scale
			if shortSide < 44 then
				error(`{size[1]}x{size[2]} の {button.name} は {shortSide} ピクセル`)
			end
		end
	end
end)

test("撃破数は左上の、画面上部の戦況と重ならない位置に移す", function()
	local layout = TouchLayout.compute(667, 317)
	local screens = TouchLayout.screensOf(layout.width, layout.height)
	expect(TouchLayout.overlaps(screens.Gekihasu, screens.BattleStatus)).toBe(false)
	expect(TouchLayout.overlaps(screens.Gekihasu, screens.Serifu)).toBe(false)
	expect(screens.Gekihasu.x).toBe(Config.TouchControls.Margin)
end)

test(
	"重なりは、間が gap より狭いときに重なるとみなし、ちょうど gap あいていれば重ならない",
	function()
		local a = { x = 0, y = 0, width = 10, height = 10 }
		expect(TouchLayout.overlaps(a, { x = 10, y = 0, width = 5, height = 5 })).toBe(false)
		expect(TouchLayout.overlaps(a, { x = 9, y = 9, width = 5, height = 5 })).toBe(true)
		expect(TouchLayout.overlaps(a, { x = 22, y = 0, width = 5, height = 5 }, 12)).toBe(false)
		expect(TouchLayout.overlaps(a, { x = 21, y = 0, width = 5, height = 5 }, 12)).toBe(true)
	end
)
