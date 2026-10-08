--!strict
local Config = require("./Config")
local SmallScreen = require("./SmallScreen")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

-- 横画面の端末の安全な範囲（上のバー・ノッチ・ホームバーを除いた画面）の大きさ（ピクセル）
local PHONES = {
	{ name = "iPhone SE", width = 667, height = 317 },
	{ name = "小さい Android", width = 640, height = 302 },
	{ name = "iPhone 14", width = 750, height = 311 },
	{ name = "iPhone 15 Pro Max", width = 814, height = 351 },
	{ name = "横長の Android", width = 800, height = 302 },
	{ name = "iPhone SE（第1世代）", width = 568, height = 262 },
}

-- 今の配置のままにする大きい画面
local LARGE = {
	{ name = "iPad", width = 1024, height = 710 },
	{ name = "iPad mini", width = 1133, height = 666 },
	{ name = "Android タブレット", width = 1280, height = 742 },
	{ name = "PC の小さい窓", width = 1100, height = 492 },
	{ name = "Studio の窓", width = 1280, height = 542 },
	{ name = "フル HD", width = 1920, height = 1022 },
}

-- 呼び出し側（クライアント）の定数。変えたらここも直す
local RESULT_PANEL_WIDTH = 520 -- ResultController の PANEL_WIDTH
local RESULT_FOOTER_HEIGHT = 52 -- ResultController の BUTTON_HEIGHT
local WINDOW_WIDTH = 760 -- TokugiWindow の WINDOW_WIDTH
local DIALOGUE_MAX_WIDTH = 920 -- Dialogue の WINDOW_MAX_WIDTH

type Rect = SmallScreen.Rect

local function inside(r: Rect, width: number, height: number): boolean
	return r.x >= 0 and r.y >= 0 and r.x + r.width <= width + 1e-9 and r.y + r.height <= height + 1e-9
end

local function overlaps(a: Rect, b: Rect): boolean
	return a.x < b.x + b.width and b.x < a.x + a.width and a.y < b.y + b.height and b.y < a.y + a.height
end

test("小さい PC の窓でも、タッチでないときは元の配置を保つ", function()
	for _, size in { { 667, 317 }, { 800, 600 }, { 1280, 400 } } do
		expect(SmallScreen.isSmall(size[1], size[2])).toBe(true)
		expect(SmallScreen.useCompactLayout(size[1], size[2], false)).toBe(false)
	end
end)

test("同じスマホの大きさでも、入力を切り替えると元の配置へ戻る", function()
	for _, phone in PHONES do
		expect(SmallScreen.useCompactLayout(phone.width, phone.height, true)).toBe(true)
		expect(SmallScreen.useCompactLayout(phone.width, phone.height, false)).toBe(false)
		expect(SmallScreen.useCompactLayout(phone.width, phone.height, true)).toBe(true)
	end
	for _, large in LARGE do
		expect(SmallScreen.useCompactLayout(large.width, large.height, true)).toBe(false)
	end
end)

test("スマホの横画面は小さい画面、PC の窓とタブレットは大きい画面", function()
	for _, phone in PHONES do
		expect(SmallScreen.isSmall(phone.width, phone.height)).toBe(true)
	end
	for _, screen in LARGE do
		if SmallScreen.isSmall(screen.width, screen.height) then
			error(`{screen.name}（{screen.width}x{screen.height}）を小さい画面とみなした`)
		end
	end
	-- 幅だけが狭い窓も小さい画面
	expect(SmallScreen.isSmall(900, 700)).toBe(true)
	-- 大きさが決まる前は大きい画面として扱う
	expect(SmallScreen.isSmall(0, 0)).toBe(false)
end)

test("窓口の SetScreenSize で決められる大きさは 200 から 4096 まで", function()
	expect(SmallScreen.isValidSize(667, 317)).toBe(true)
	expect(SmallScreen.isValidSize(200, 4096)).toBe(true)
	expect(SmallScreen.isValidSize(199, 317)).toBe(false)
	expect(SmallScreen.isValidSize(667, 4097)).toBe(false)
end)

test(
	"縮めてよい倍率の下限は、一番小さい文字が読める下限を、ボタンが押せる大きさを下回らない倍率",
	function()
		local p = Config.SmallScreen
		expect(SmallScreen.minScale(14)).toBeNear(p.MinTextSize / 14)
		expect(SmallScreen.minScale(18, 52)).toBeNear(math.max(p.MinTextSize / 18, p.MinTouchSize / 52))
		-- 下限より小さい文字やボタンでも、大きくはしない
		expect(SmallScreen.minScale(10)).toBe(1)
		expect(SmallScreen.minScale(24, 40)).toBe(1)
	end
)

test("読める下限で止めた倍率は、下限より縮めず、それ以上ならそのまま", function()
	local p = Config.SmallScreen
	expect(SmallScreen.withReadableFloor(0.5, 14)).toBeNear(p.MinTextSize / 14)
	expect(SmallScreen.withReadableFloor(0.95, 14)).toBe(0.95)
	expect(SmallScreen.withReadableFloor(1, 13)).toBe(1)
	-- 縮めたあとの一番小さい文字は読める下限以上
	for _, scale in { 0.375, 0.47, 0.5, 0.55, 0.85 } do
		expect(SmallScreen.withReadableFloor(scale, 13) * 13 >= p.MinTextSize - 1e-9).toBe(true)
	end
end)

test("収まる倍率は、収まれば 1、収まらなければ縮め、下限より縮めない", function()
	expect(SmallScreen.fitScale(280, 300, 0.8)).toBe(1)
	expect(SmallScreen.fitScale(400, 300, 0.5)).toBeNear(0.75)
	expect(SmallScreen.fitScale(400, 300, 0.85)).toBe(0.85)
	-- 高さがまだ決まっていないときは縮めない
	expect(SmallScreen.fitScale(0, 300, 0.85)).toBe(1)
end)

test(
	"スマホのロビーは、左上に非公式の表記、右に出撃前の画面を、重ねずに画面の中へ並べる",
	function()
		local p = Config.SmallScreen
		for _, phone in PHONES do
			local lobby = SmallScreen.lobbyOf(phone.width, phone.height)
			local where = `{phone.name}（{phone.width}x{phone.height}）`
			for name, r in { notice = lobby.notice, panel = lobby.panel, waiting = lobby.waiting } do
				if not inside(r, phone.width, phone.height) then
					error(`{where}: {name} が画面からはみ出す`)
				end
			end
			if overlaps(lobby.notice, lobby.panel) or overlaps(lobby.notice, lobby.waiting) then
				error(`{where}: 非公式の表記と出撃前の画面が重なる`)
			end
			expect(lobby.notice.x).toBe(p.Margin)
			expect(lobby.panel.x + lobby.panel.width).toBe(phone.width - p.Margin)
			expect(lobby.panel.width >= p.PanelMinWidth and lobby.panel.width <= p.PanelMaxWidth).toBe(true)
			-- 出撃前の画面の欄のスクロールに 100 以上残る（見出しと出撃の帯を除く）
			if lobby.body < 100 then
				error(`{where}: 欄のスクロールが {lobby.body} しかない`)
			end
		end
	end
)

test(
	"非公式の表記は、見出しが収まる幅を残す（余白と両方の幅の下限が入る画面）",
	function()
		local p = Config.SmallScreen
		for width = p.Margin * 3 + p.NoticeMinWidth + p.PanelMinWidth, p.Width - 1, 25 do
			local lobby = SmallScreen.lobbyOf(width, 317)
			expect(lobby.notice.width >= p.NoticeMinWidth).toBe(true)
			-- 間は余白と同じ
			expect(lobby.panel.x - (lobby.notice.x + lobby.notice.width)).toBe(p.Margin)
		end
		-- 広い小さい画面では、出撃前の画面は大きい画面と同じ幅にし、残りを表記に使う
		local wide = SmallScreen.lobbyOf(990, 400)
		expect(wide.panel.width).toBe(p.PanelMaxWidth)
		expect(wide.notice.width > p.NoticeMinWidth).toBe(true)
	end
)

test("特技ツリーの窓は、余白の内側いっぱいに置き、横は中央にそろえる", function()
	local p = Config.SmallScreen
	for _, phone in PHONES do
		local window = SmallScreen.windowOf(phone.width, phone.height, WINDOW_WIDTH)
		expect(inside(window, phone.width, phone.height)).toBe(true)
		expect(window.y).toBe(p.Margin)
		expect(window.height).toBe(phone.height - p.Margin * 2)
		expect(window.width <= WINDOW_WIDTH).toBe(true)
		expect(window.x).toBeNear(phone.width - (window.x + window.width))
	end
end)

test(
	"リザルトは、パネルとその下のボタンの帯を画面に収め、収まらない中身はパネルの中でスクロールする",
	function()
		local p = Config.SmallScreen
		for _, phone in PHONES do
			for _, content in { 200, 354, 444, 900 } do
				local result =
					SmallScreen.resultOf(phone.width, phone.height, RESULT_PANEL_WIDTH, content, RESULT_FOOTER_HEIGHT)
				local where = `{phone.name} の中身 {content}`
				if not inside(result.panel, phone.width, phone.height) then
					error(`{where}: パネルが画面からはみ出す`)
				end
				if not inside(result.footer, phone.width, phone.height) then
					error(`{where}: ボタンの帯が画面からはみ出す`)
				end
				-- ボタンの帯はパネルの下に間隔をあけて置く
				expect(result.footer.y).toBeNear(result.panel.y + result.panel.height + p.Gap)
				expect(result.footer.height).toBe(RESULT_FOOTER_HEIGHT)
				expect(result.panel.height <= content).toBe(true)
				expect(
					result.panel.y >= p.Margin
						and result.footer.y + result.footer.height <= phone.height - p.Margin + 1e-9
				).toBe(true)
			end
		end
		-- 中身が収まれば、パネルは中身の高さで、まとめて縦の中央に置く
		local fits = SmallScreen.resultOf(667, 317, RESULT_PANEL_WIDTH, 200, RESULT_FOOTER_HEIGHT)
		expect(fits.panel.height).toBe(200)
		expect(fits.panel.y).toBeNear(317 - (fits.footer.y + fits.footer.height))
		expect(fits.panel.width).toBe(RESULT_PANEL_WIDTH)
	end
)

test(
	"会話窓は下に、タッチの端末のスキップのボタンは右上に置き、画面に収めて重ねない",
	function()
		local p = Config.SmallScreen
		for _, phone in PHONES do
			local dialogue = SmallScreen.dialogueOf(phone.width, phone.height, DIALOGUE_MAX_WIDTH)
			local skip = SmallScreen.skipOf(phone.width, phone.height)
			expect(inside(dialogue, phone.width, phone.height)).toBe(true)
			expect(inside(skip, phone.width, phone.height)).toBe(true)
			expect(overlaps(dialogue, skip)).toBe(false)
			expect(dialogue.y + dialogue.height).toBe(phone.height - p.Margin)
			expect(dialogue.height).toBe(p.DialogueHeight)
			expect(skip.x + skip.width).toBe(phone.width - p.Margin)
			expect(skip.y).toBe(p.Margin)
		end
	end
)

test("スキップのボタンは指で押せる大きさ", function()
	local p = Config.SmallScreen
	expect(math.min(p.SkipWidth, p.SkipHeight) >= p.MinTouchSize).toBe(true)
end)
