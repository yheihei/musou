--!strict
-- 小さい画面（スマホ横画面）の配置の計算と、読める文字の大きさの判断。Roblox の API は使わない。
-- 値は Config.luau の SmallScreen 節にある。位置と大きさは、どれも安全な範囲（Roblox のトップバーと、端末のノッチや
-- ホームバーを除いた範囲。クライアントの Ui.safeAreaSize）の左上を (0, 0) とする、実際の画面のピクセル（スマホでは端末の point）。
--
-- - 安全な範囲の幅か高さが Width x Height に満たない画面を小さい画面とする。大きい画面（PC の窓とタブレット）は今の配置のまま
-- - 小さい画面では、出撃前の画面・非公式の表記・待機中の表示・特技ツリーの窓・リザルト・タイトル画面・会話窓を、縮めずに
--   詰めて並べ、収まらない分はスクロールする。文字とボタンは大きい画面と同じ大きさのまま使うので、文字は読める下限
--   （MinTextSize）を、ボタンは指で押せる大きさ（MinTouchSize）を下回らない。高さが文の長さで決まる非公式の表記・
--   待機中の表示・タイトル画面は、収まらなければ、読める下限と押せる大きさを下回らない倍率まで縮める（fitScale）
-- - 戦闘の画面はタッチの配置（TouchLayout.luau）で画面の大きさに合わせて縮める。戦闘中の台詞と秘計の知らせのように
--   読ませる部品は、一番小さい文字が読める下限を下回るほどは縮めない（withReadableFloor）
-- - 窓口の SetScreenSize で、配置に使う画面の大きさを仮に決められる（SIZE_ATTRIBUTE。Studio でスマホの配置を確かめる用）

local Config = require("./Config")

export type Rect = {
	x: number,
	y: number,
	width: number,
	height: number,
}

-- ロビーの配置
export type Lobby = {
	-- 非公式の表記（左上）。高さは置ける上限
	notice: Rect,
	-- 出撃前の画面（右）
	panel: Rect,
	-- 出撃前の画面の中の、欄を並べてスクロールする部分の高さ（見出しと出撃の帯を除く）
	body: number,
	-- 待機中の表示。待機中の人には出撃前の画面を出さないので、同じ場所に置く。高さは置ける上限
	waiting: Rect,
}

-- リザルトの配置
export type Result = {
	-- 結果のパネル。中身が収まらなければパネルの中をスクロールする
	panel: Rect,
	-- パネルの下に出す、もう一度挑む・ロビーへ戻るのボタン（リーダー以外には待ちの文）の帯
	footer: Rect,
}

local SmallScreen = {}

-- 窓口の SetScreenSize が、配置に使う画面の大きさ（Vector2）を書く Player の Attribute
SmallScreen.SIZE_ATTRIBUTE = "ScreenSizeOverride"
-- 窓口の SetScreenSize で決められる幅と高さの範囲
SmallScreen.SIZE_MIN = 200
SmallScreen.SIZE_MAX = 4096

-- 小さい画面の出撃前の画面の見出しの高さ（SelectionController の SMALL_HEADER_HEIGHT）と、
-- 出撃の帯の高さ（ShutsugekiBar.HEIGHT）。変えたらここも直す
local LOBBY_HEADER_HEIGHT = 36
local SHUTSUGEKI_BAR_HEIGHT = 104

local function rect(x: number, y: number, width: number, height: number): Rect
	return { x = x, y = y, width = width, height = height }
end

-- 安全な範囲の大きさから、小さい画面か。大きさが決まる前（0 以下）は大きい画面として扱う
function SmallScreen.isSmall(width: number, height: number, params: Config.SmallScreenSection?): boolean
	local p = params or Config.SmallScreen
	if width <= 0 or height <= 0 then
		return false
	end
	return width < p.Width or height < p.Height
end

-- スマホの配置にするか。小さい PC の窓でも、キーボード・マウス・ゲームパッドを使っている間は元の配置を保つ。
-- touchInput は TouchControls.isActive の結果（Studio で On にしたときも含む）を渡す。
function SmallScreen.useCompactLayout(
	width: number,
	height: number,
	touchInput: boolean,
	params: Config.SmallScreenSection?
): boolean
	return touchInput and SmallScreen.isSmall(width, height, params)
end

-- 窓口の SetScreenSize で決められる大きさか
function SmallScreen.isValidSize(width: number, height: number): boolean
	return width >= SmallScreen.SIZE_MIN
		and width <= SmallScreen.SIZE_MAX
		and height >= SmallScreen.SIZE_MIN
		and height <= SmallScreen.SIZE_MAX
end

-- 部品を縮めてよい倍率の下限。一番小さい文字の大きさ smallestTextSize が読める下限を、
-- 一番小さいボタンの短い辺 smallestButton（ボタンが無ければ省く）が指で押せる大きさを下回らない倍率。1 を超えない
function SmallScreen.minScale(
	smallestTextSize: number,
	smallestButton: number?,
	params: Config.SmallScreenSection?
): number
	local p = params or Config.SmallScreen
	local scale = p.MinTextSize / smallestTextSize
	if smallestButton then
		scale = math.max(scale, p.MinTouchSize / smallestButton)
	end
	return math.min(1, scale)
end

-- 倍率 scale で縮める部品の倍率を、一番小さい文字の大きさ smallestTextSize が読める下限を下回らない倍率で止める
function SmallScreen.withReadableFloor(
	scale: number,
	smallestTextSize: number,
	params: Config.SmallScreenSection?
): number
	return math.max(scale, SmallScreen.minScale(smallestTextSize, nil, params))
end

-- 縮める前の高さが height の部品を、高さ maxHeight に収める倍率。minScale より小さくせず、1 を超えない
function SmallScreen.fitScale(height: number, maxHeight: number, minScale: number): number
	if height <= 0 or height <= maxHeight then
		return 1
	end
	return math.clamp(maxHeight / height, math.min(minScale, 1), 1)
end

-- 小さい画面の、画面の端の余白の内側
function SmallScreen.innerOf(width: number, height: number, params: Config.SmallScreenSection?): Rect
	local p = params or Config.SmallScreen
	return rect(p.Margin, p.Margin, width - p.Margin * 2, height - p.Margin * 2)
end

-- 小さい画面のロビー。左上に非公式の表記、右に出撃前の画面（高さいっぱい）を並べる。
-- 出撃前の画面の幅は PanelMinWidth から PanelMaxWidth の間で、表記に NoticeMinWidth を残す（画面の幅が
-- 余白と両方の下限の和に満たなければ、表記を狭くする）。左下は標準のサムスティックのために空ける
function SmallScreen.lobbyOf(width: number, height: number, params: Config.SmallScreenSection?): Lobby
	local p = params or Config.SmallScreen
	local m = p.Margin
	local panelWidth = math.clamp(width - m * 3 - p.NoticeMinWidth, p.PanelMinWidth, p.PanelMaxWidth)
	local inner = height - m * 2
	return {
		notice = rect(m, m, width - m * 3 - panelWidth, inner),
		panel = rect(width - m - panelWidth, m, panelWidth, inner),
		body = inner - LOBBY_HEADER_HEIGHT - SHUTSUGEKI_BAR_HEIGHT,
		waiting = rect(width - m - panelWidth, m, panelWidth, inner),
	}
end

-- 小さい画面の、出撃前の画面から開く窓（特技ツリー）。幅 maxWidth までで余白の内側いっぱいに置き、横は中央にそろえる
function SmallScreen.windowOf(width: number, height: number, maxWidth: number, params: Config.SmallScreenSection?): Rect
	local inner = SmallScreen.innerOf(width, height, params)
	local windowWidth = math.min(maxWidth, inner.width)
	return rect((width - windowWidth) / 2, inner.y, windowWidth, inner.height)
end

-- 小さい画面のリザルト。幅 panelWidth までのパネル（中身の高さ contentHeight）と、その下に高さ footerHeight の
-- ボタンの帯を置き、まとめて縦の中央にそろえる。中身が収まらなければ、パネルを余白の内側に収まる高さにする
-- （パネルの中をスクロールし、ボタンの帯はいつも見える）
function SmallScreen.resultOf(
	width: number,
	height: number,
	panelWidth: number,
	contentHeight: number,
	footerHeight: number,
	params: Config.SmallScreenSection?
): Result
	local p = params or Config.SmallScreen
	local inner = SmallScreen.innerOf(width, height, p)
	local panelW = math.min(panelWidth, inner.width)
	local panelH = math.max(0, math.min(contentHeight, inner.height - p.Gap - footerHeight))
	local total = panelH + p.Gap + footerHeight
	local top = math.max(inner.y, (height - total) / 2)
	local x = (width - panelW) / 2
	return {
		panel = rect(x, top, panelW, panelH),
		footer = rect(x, top + panelH + p.Gap, panelW, footerHeight),
	}
end

-- 小さい画面の会話窓。余白の内側の下に、幅 maxWidth まで、高さ DialogueHeight で置き、横は中央にそろえる
function SmallScreen.dialogueOf(
	width: number,
	height: number,
	maxWidth: number,
	params: Config.SmallScreenSection?
): Rect
	local p = params or Config.SmallScreen
	local inner = SmallScreen.innerOf(width, height, p)
	local windowWidth = math.min(maxWidth, inner.width)
	return rect((width - windowWidth) / 2, inner.y + inner.height - p.DialogueHeight, windowWidth, p.DialogueHeight)
end

-- タッチの端末のイベントシーンのスキップのボタン。安全な範囲の右上に置く（会話窓は下に出る）
function SmallScreen.skipOf(width: number, _height: number, params: Config.SmallScreenSection?): Rect
	local p = params or Config.SmallScreen
	return rect(width - p.Margin - p.SkipWidth, p.Margin, p.SkipWidth, p.SkipHeight)
end

return SmallScreen
