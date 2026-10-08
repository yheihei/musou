--!strict
-- スマホ横画面のタッチの配置の計算。Roblox の API は使わない。
-- タッチの操作ボタンを出している間（TouchControlsController）は、戦闘の画面（HUD・戦況・ミニマップ・台詞・秘計の知らせと
-- タッチの操作ボタン）を同じ倍率で縮め、縮める前の大きさ（設計の大きさ）の画面に置いたように並べる。
-- 大きさと余白は Config.luau の TouchControls 節にある。位置と大きさは、どれも画面の左上を (0, 0) とするピクセル。
--
-- - 倍率は、設計の大きさが DesignWidth x DesignHeight 以上になるように決める。大きい画面では 1 のまま
-- - 右下には Roblox 標準のジャンプボタンが出る。位置は PlayerModule の TouchJump と同じ計算で求め、
--   その左上から画面の右下の角までにはボタンを置かない
-- - 下の段は、ジャンプボタンの左に通常攻撃、その左にチャージ攻撃。通常攻撃の上端はジャンプボタンの上端にそろえる
--   （下の余白に収まらなければ上げる）
-- - 上の段は、右からガードと奥義。ジャンプボタンの上（ミニマップの下）に置き、入らなければ通常攻撃の上に置く
-- - 秘計の枚は、左上へ移した撃破数（HUD）の下に、枚の順に横に並べる
-- - ほかの戦闘の画面の部品（screensOf）と、標準のサムスティックを出す範囲とは Gap 以上あける
-- - 戦闘中の台詞と秘計の知らせは、文字が読める下限（SmallScreen.withReadableFloor）を下回るほどは縮めないので、
--   ほかの部品より大きく出る。秘計の知らせは、ミニマップの左に HikeiNoticeMax 件まで積み、左の秘計の枚に重なるなら
--   重ならない幅まで狭める。ボタンは秘計の知らせも避ける
-- - 台詞は、ボタンを置いた後に、左下の HUD の上（既定の位置）に置く。ボタンや秘計の知らせに重なるときは、
--   重ならない高さのうち既定の位置に一番近い高さへずらす（スマホより正方形に近い小さい画面で、それでも置けなければ、
--   読める下限の倍率から縮める）。サムスティックの範囲には重ねてよい（入力を受け取らない表示だけ）

local Config = require("./Config")
local Hikei = require("./Hikei")
local SmallScreen = require("./SmallScreen")

export type Rect = {
	x: number,
	y: number,
	width: number,
	height: number,
}

export type Layout = {
	-- 戦闘の画面を縮める倍率
	scale: number,
	-- 設計の大きさ（実際の画面の大きさを倍率で割った値）
	width: number,
	height: number,
	-- 標準のジャンプボタンの範囲（設計の大きさ）
	jump: Rect,
	attack: Rect,
	chargeKogeki: Rect,
	guard: Rect,
	ougi: Rect,
	-- 秘計の枚。枚の順
	hikei: { Rect },
	-- 戦闘中の台詞の枠の範囲（設計の大きさ）と、枠を縮める倍率（読める下限で止めた倍率）
	serifu: Rect,
	serifuScale: number,
	-- 秘計の知らせの並びの範囲（設計の大きさ。積める件数のすべて）と、並びを縮める倍率（読める下限で止めた倍率）と、
	-- 知らせ1件の幅（縮める前）
	hikeiNotice: Rect,
	hikeiNoticeScale: number,
	hikeiNoticeWidth: number,
	-- 全部のボタンと台詞が画面に収まり、ほかの部品と重ならないか
	fits: boolean,
}

local TouchLayout = {}

-- ほかの戦闘の画面の部品の位置と大きさ（設計の大きさのピクセル）。各コントローラーの定数と同じ値にする（変えたらここも直す）
local SCREEN_MARGIN = 24 -- HUDController・SerifuController の MARGIN と、Ui.Minimap の Right
local STATUS_WIDTH = 460 -- HUDController の PANEL_WIDTH（左下の体力と奥義ゲージの枠）
local STATUS_HEIGHT = 84 -- HUDController の PANEL_HEIGHT
local GEKIHASU_WIDTH = 240 -- HUDController の撃破数の枠
local GEKIHASU_HEIGHT = 72 -- HUDController の GEKIHASU_HEIGHT
local BATTLE_STATUS_TOP = 8 -- BattleStatusController の TOP
local BATTLE_STATUS_WIDTH = 560 -- BattleStatusController の PANEL_WIDTH
local BATTLE_STATUS_HEIGHT = 68 -- BattleStatusController の PANEL_HEIGHT
local MINIMAP_TOP = 84 -- Ui.Minimap の Top
local MINIMAP_SIZE = 200 -- Ui.Minimap の Size
local NOTICE_RIGHT = 236 -- HikeiNoticeController の RIGHT（ミニマップの左）
local NOTICE_WIDTH = 320 -- HikeiNoticeController の WIDTH（知らせ1件の幅の上限）
local NOTICE_ITEM_HEIGHT = 56 + 6 -- HikeiNoticeController の HEIGHT + GAP（知らせ1件。積む数は HikeiNoticeMax）
local NOTICE_TEXT_MIN = 14 -- HikeiNoticeController の知らせの一番小さい文字（Detail の Ui.TextSize.Small）
local SERIFU_BOTTOM = 148 -- SerifuController の BOTTOM（既定の位置の、画面の下端から枠の下端まで）
local SERIFU_WIDTH = 360 -- SerifuController の TOUCH_WIDTH（タッチの配置での枠の幅）
local SERIFU_HEIGHT = 108 -- SerifuController の TOUCH_HEIGHT（タッチの配置での枠の高さ）
local SERIFU_TEXT_MIN = 13 -- SerifuController の TEXT_SIZE_MIN（長い台詞を縮めて収めるときの一番小さい文字）
-- 台詞を読める下限の倍率で置けないときに、戦闘の画面の倍率へ近づける段階の数
local SERIFU_SHRINK_STEPS = 8

-- 標準のサムスティック（PlayerModule の DynamicThumbstick）を出す範囲。横画面では、左から幅の 4 割、上から高さの 3 分の 1 より下
local THUMBSTICK_WIDTH = 0.4
local THUMBSTICK_TOP = 1 / 3

-- 標準のジャンプボタン（PlayerModule の TouchJump）。画面の短い辺が JUMP_SMALL_SCREEN 以下なら一辺 70、それより大きければ 120
local JUMP_SMALL_SCREEN = 500
local JUMP_SMALL_SIZE = 70
local JUMP_LARGE_SIZE = 120
-- ジャンプボタンの画面（TouchGui）は端末の安全な範囲（ノッチやホームバー）の外まで広がることがあり、
-- こちらの画面より短い辺が長く測られる。短い辺が境目からこの幅の内なら、大きいほうのジャンプボタンの範囲も避ける
local JUMP_SLACK = 40

local function rect(x: number, y: number, width: number, height: number): Rect
	return { x = x, y = y, width = width, height = height }
end

local function rightOf(r: Rect): number
	return r.x + r.width
end

local function bottomOf(r: Rect): number
	return r.y + r.height
end

-- 2つの四角を囲む四角
local function union(a: Rect, b: Rect): Rect
	local x = math.min(a.x, b.x)
	local y = math.min(a.y, b.y)
	return rect(x, y, math.max(rightOf(a), rightOf(b)) - x, math.max(bottomOf(a), bottomOf(b)) - y)
end

-- 2つの四角が重なるか。gap を渡すと、間が gap より狭いときも重なるとみなす（ちょうど gap なら重ならない）
function TouchLayout.overlaps(a: Rect, b: Rect, gap: number?): boolean
	local g = gap or 0
	return a.x < rightOf(b) + g and b.x < rightOf(a) + g and a.y < bottomOf(b) + g and b.y < bottomOf(a) + g
end

-- 実際の画面の大きさから、戦闘の画面を縮める倍率を決める。params を省くと Config.luau の TouchControls 節を使う
function TouchLayout.scaleOf(width: number, height: number, params: Config.TouchControlsSection?): number
	local p = params or Config.TouchControls
	if width <= 0 or height <= 0 then
		return 1
	end
	return math.min(1, width / p.DesignWidth, height / p.DesignHeight)
end

-- 戦闘の画面を倍率 scale で縮めるときの、戦闘中の台詞の枠の倍率（一番小さい文字が読める下限を下回らない倍率）
function TouchLayout.serifuScaleOf(scale: number): number
	return SmallScreen.withReadableFloor(scale, SERIFU_TEXT_MIN)
end

-- 戦闘の画面を倍率 scale で縮めるときの、秘計の知らせの並びの倍率（一番小さい文字が読める下限を下回らない倍率）
function TouchLayout.hikeiNoticeScaleOf(scale: number): number
	return SmallScreen.withReadableFloor(scale, NOTICE_TEXT_MIN)
end

-- 一辺の大きさを決めた標準のジャンプボタンの範囲（実際の画面のピクセル）
local function jumpFor(width: number, height: number, small: boolean): Rect
	local size = if small then JUMP_SMALL_SIZE else JUMP_LARGE_SIZE
	local x = width - (size * 1.5 - 10)
	local y = if small then height - size - 20 else height - size * 1.75
	return rect(x, y, size, size)
end

-- 標準のジャンプボタンが出る範囲（実際の画面のピクセル）。短い辺が境目に近ければ、大小のどちらも囲む
function TouchLayout.jumpOf(width: number, height: number): Rect
	local shortSide = math.min(width, height)
	local small = shortSide <= JUMP_SMALL_SCREEN
	local result = jumpFor(width, height, small)
	if small and shortSide > JUMP_SMALL_SCREEN - JUMP_SLACK then
		result = union(result, jumpFor(width, height, false))
	end
	return result
end

-- タッチの配置での撃破数（HUD）の範囲（設計の大きさ）。左上の、画面上部の戦況と同じ高さに置く
function TouchLayout.gekihasuOf(params: Config.TouchControlsSection?): Rect
	local p = params or Config.TouchControls
	return rect(p.Margin, BATTLE_STATUS_TOP, GEKIHASU_WIDTH, GEKIHASU_HEIGHT)
end

-- タッチの配置での秘計の枚の範囲（設計の大きさ）。左上の撃破数の下に、枚の順に横に並べる
local function hikeiOf(p: Config.TouchControlsSection): { Rect }
	local gekihasu = TouchLayout.gekihasuOf(p)
	local result: { Rect } = {}
	for slot = 1, Hikei.MOCHIKOMI_MAX do
		table.insert(
			result,
			rect(
				p.Margin + (slot - 1) * (p.HikeiWidth + p.Gap),
				bottomOf(gekihasu) + p.Gap,
				p.HikeiWidth,
				p.HikeiHeight
			)
		)
	end
	return result
end

-- タッチの配置での秘計の知らせの並びの範囲（設計の大きさ）。width と height は設計の大きさ、scale は戦闘の画面を
-- 縮める倍率。ミニマップの左（右上の角を固定）から下へ HikeiNoticeMax 件を積む。読める下限で止めた倍率で縮めるので
-- 設計の大きさではほかの部品より大きく、左の秘計の枚に Gap より近づく幅なら、近づかない幅まで狭める
function TouchLayout.hikeiNoticeOf(
	width: number,
	_height: number,
	params: Config.TouchControlsSection?,
	scale: number?
): Rect
	local p = params or Config.TouchControls
	local s = scale or 1
	-- 読める下限で止めた倍率の、ほかの部品の倍率に対する比
	local ratio = TouchLayout.hikeiNoticeScaleOf(s) / s
	local right = width - NOTICE_RIGHT
	local hikei = hikeiOf(p)
	local left = math.max(right - NOTICE_WIDTH * ratio, rightOf(hikei[#hikei]) + p.Gap)
	return rect(left, MINIMAP_TOP, right - left, NOTICE_ITEM_HEIGHT * p.HikeiNoticeMax * ratio)
end

-- タッチの配置での、ほかの戦闘の画面の部品の範囲（設計の大きさ）。width と height は設計の大きさ、
-- scale は戦闘の画面を縮める倍率（省くと 1）。秘計の知らせは出ていないときも、出たときの範囲（積める件数のすべて）を返す。
-- 台詞はボタンを置いてから置くので含めない（compute の serifu）。HUD の秘計の枚と操作の案内はタッチの配置では隠すので含めない
function TouchLayout.screensOf(
	width: number,
	height: number,
	params: Config.TouchControlsSection?,
	scale: number?
): { [string]: Rect }
	return {
		Status = rect(SCREEN_MARGIN, height - SCREEN_MARGIN - STATUS_HEIGHT, STATUS_WIDTH, STATUS_HEIGHT),
		Gekihasu = TouchLayout.gekihasuOf(params),
		BattleStatus = rect(
			(width - BATTLE_STATUS_WIDTH) / 2,
			BATTLE_STATUS_TOP,
			BATTLE_STATUS_WIDTH,
			BATTLE_STATUS_HEIGHT
		),
		Minimap = rect(width - SCREEN_MARGIN - MINIMAP_SIZE, MINIMAP_TOP, MINIMAP_SIZE, MINIMAP_SIZE),
		HikeiNotice = TouchLayout.hikeiNoticeOf(width, height, params, scale),
	}
end

-- 標準のサムスティックを出す範囲（設計の大きさ）
function TouchLayout.thumbstickOf(width: number, height: number): Rect
	return rect(0, height * THUMBSTICK_TOP, width * THUMBSTICK_WIDTH, height * (1 - THUMBSTICK_TOP))
end

-- 横の範囲が x から x + w で高さ h の四角を、上端 minY から下端 maxY の間に、obstacles と gap 以上あけて置けるときの上端のうち、
-- preferred に一番近いもの。置けなければ nil
local function verticalSlot(
	obstacles: { Rect },
	x: number,
	w: number,
	h: number,
	preferred: number,
	minY: number,
	maxY: number,
	gap: number
): number?
	-- 横の範囲に掛かる部品が塞ぐ縦の範囲（間隔を含める）
	local blocked: { { number } } = {}
	for _, obstacle in obstacles do
		if obstacle.x < x + w + gap and x < rightOf(obstacle) + gap then
			table.insert(blocked, { obstacle.y - gap, bottomOf(obstacle) + gap })
		end
	end
	table.sort(blocked, function(a, b)
		return a[1] < b[1]
	end)
	local best: number? = nil
	-- 空いている縦の範囲 [from, to] に置けるなら、preferred に一番近い上端を候補にする
	local function consider(from: number, to: number)
		if to - from < h then
			return
		end
		local y = math.clamp(preferred, from, to - h)
		if best == nil or math.abs(y - preferred) < math.abs(best - preferred) then
			best = y
		end
	end
	local cursor = minY
	for _, range in blocked do
		if range[1] > cursor then
			consider(cursor, math.min(range[1], maxY))
		end
		cursor = math.max(cursor, range[2])
	end
	consider(cursor, maxY)
	return best
end

-- 実際の画面の大きさ（realWidth x realHeight）から、タッチの配置を決める。params を省くと Config.luau の TouchControls 節を使う
function TouchLayout.compute(realWidth: number, realHeight: number, params: Config.TouchControlsSection?): Layout
	local p = params or Config.TouchControls
	local scale = TouchLayout.scaleOf(realWidth, realHeight, p)
	local width, height = realWidth / scale, realHeight / scale
	local realJump = TouchLayout.jumpOf(realWidth, realHeight)
	local jump = rect(realJump.x / scale, realJump.y / scale, realJump.width / scale, realJump.height / scale)
	local gap = p.Gap

	-- ほかの戦闘の画面の部品。上の段を通常攻撃の上に置くときは、上の段の横の範囲にある部品の下に入れる
	local screens: { Rect } = {}
	for _, screen in TouchLayout.screensOf(width, height, p, scale) do
		table.insert(screens, screen)
	end
	-- 避ける範囲。ジャンプボタンは左上から画面の右下の角まで
	local jumpArea = rect(jump.x, jump.y, width - jump.x, height - jump.y)
	local obstacles: { Rect } = table.clone(screens)
	table.insert(obstacles, jumpArea)
	table.insert(obstacles, TouchLayout.thumbstickOf(width, height))

	local function fits(r: Rect): boolean
		if r.x < p.Margin or r.y < 0 or rightOf(r) > width - p.Margin or bottomOf(r) > height - p.Margin then
			return false
		end
		for _, obstacle in obstacles do
			if TouchLayout.overlaps(r, obstacle, gap) then
				return false
			end
		end
		return true
	end

	-- 下の段。通常攻撃の上端を y にしてジャンプボタンの左に置き、チャージ攻撃をその左に、中心の高さをそろえて置く
	local function lowerRow(y: number): (Rect, Rect)
		local attack = rect(jump.x - gap - p.AttackSize, y, p.AttackSize, p.AttackSize)
		local charge = rect(
			attack.x - gap - p.ChargeKogekiSize,
			y + (p.AttackSize - p.ChargeKogekiSize) / 2,
			p.ChargeKogekiSize,
			p.ChargeKogekiSize
		)
		return attack, charge
	end
	-- 上の段。右端を rowRight、下端を rowBottom にして、右にガード、その左に奥義を置く
	local function upperRow(rowRight: number, rowBottom: number): (Rect, Rect)
		local guard = rect(rowRight - p.GuardSize, rowBottom - p.GuardSize, p.GuardSize, p.GuardSize)
		local ougi = rect(guard.x - gap - p.OugiSize, rowBottom - p.OugiSize, p.OugiSize, p.OugiSize)
		return guard, ougi
	end

	-- 通常攻撃の上端の下限（下の余白に収まる一番下）
	local lowest = height - p.Margin - p.AttackSize
	local attack, charge = lowerRow(math.min(jump.y, lowest))
	local guard, ougi = upperRow(width - p.Margin, attack.y - gap)
	if not (fits(guard) and fits(ougi)) then
		-- ジャンプボタンの上に入らないときは、通常攻撃の上に置く。上の段の横の範囲で一番下にある部品の下に入るまで、下の段を下げる
		local rowRight = jump.x - gap
		local rowLeft = rowRight - p.GuardSize - gap - p.OugiSize
		local above = 0
		for _, screen in screens do
			if screen.y < attack.y and screen.x < rowRight + gap and rowLeft < rightOf(screen) + gap then
				above = math.max(above, bottomOf(screen))
			end
		end
		local rowHeight = math.max(p.GuardSize, p.OugiSize)
		attack, charge = lowerRow(math.min(math.max(attack.y, above + gap + rowHeight + gap), lowest))
		guard, ougi = upperRow(rowRight, attack.y - gap)
	end

	local hikei = hikeiOf(p)
	local placed = { attack, charge, guard, ougi }
	for _, r in hikei do
		table.insert(placed, r)
	end
	local ok = true
	for index, r in placed do
		if not fits(r) then
			ok = false
		end
		for other = index + 1, #placed do
			if TouchLayout.overlaps(r, placed[other], gap) then
				ok = false
			end
		end
	end

	-- 台詞。既定の位置は左下の HUD の上。ボタン・ジャンプボタン・ほかの部品と重ならない高さのうち、既定の位置に一番近い高さに置く。
	-- 読める下限で止めた倍率ではどこにも置けない画面（スマホより正方形に近い、小さい画面）では、置けるまで倍率を
	-- 戦闘の画面の倍率へ近づける
	local serifuObstacles: { Rect } = table.clone(screens)
	table.insert(serifuObstacles, jumpArea)
	for _, r in placed do
		table.insert(serifuObstacles, r)
	end
	local readable = TouchLayout.serifuScaleOf(scale)
	local serifu: Rect? = nil
	local serifuScale = scale
	for step = 0, SERIFU_SHRINK_STEPS do
		local candidate = readable + (scale - readable) * step / SERIFU_SHRINK_STEPS
		local serifuWidth = SERIFU_WIDTH * candidate / scale
		local serifuHeight = SERIFU_HEIGHT * candidate / scale
		local preferred = height - SERIFU_BOTTOM - serifuHeight
		local y = verticalSlot(serifuObstacles, SCREEN_MARGIN, serifuWidth, serifuHeight, preferred, 0, height, gap)
		if y and SCREEN_MARGIN + serifuWidth <= width then
			serifu = rect(SCREEN_MARGIN, y, serifuWidth, serifuHeight)
			serifuScale = candidate
			break
		end
	end
	if not serifu then
		ok = false
	end
	local serifuRect = serifu
		or rect(SCREEN_MARGIN, height - SERIFU_BOTTOM - SERIFU_HEIGHT, SERIFU_WIDTH, SERIFU_HEIGHT)

	local noticeScale = TouchLayout.hikeiNoticeScaleOf(scale)
	local notice = TouchLayout.hikeiNoticeOf(width, height, p, scale)
	return {
		scale = scale,
		width = width,
		height = height,
		jump = jump,
		attack = attack,
		chargeKogeki = charge,
		guard = guard,
		ougi = ougi,
		hikei = hikei,
		serifu = serifuRect,
		serifuScale = serifuScale,
		hikeiNotice = notice,
		hikeiNoticeScale = noticeScale,
		hikeiNoticeWidth = notice.width * scale / noticeScale,
		fits = ok,
	}
end

return TouchLayout
