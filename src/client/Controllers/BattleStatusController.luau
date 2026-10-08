--!strict
-- 画面上部の戦況の表示。中央に戦闘の残り時間とその下に兵力、左に味方軍・右に敵軍の軍全体の士気のゲージを出す。
-- 士気は ReplicatedStorage.Shiki（ShikiService が作る Configuration）の Attribute の Mikatagun・Tekigun、
-- 残り時間は workspace の Attribute の BattleDeadline（workspace:GetServerTimeNow の時刻）、
-- 兵力は workspace の Attribute の Heiryoku から読む。判断と文は ReplicatedStorage.Shared.BattleStatus にある。
--
-- - 出すのは戦闘のフェーズの出撃メンバーだけ。ロビー・イベントシーン・リザルトのフェーズと、待機中の人には出さない
-- - イベントシーンの再生中も隠す。EventSceneController の started・stopped を受け、フェーズと合わせて決める
--   （HUD のように再生の終わりで出し直すと、終了のイベントシーンの後のリザルトで出てしまう）
-- - 士気のゲージは中央の側を根元にして外へ伸ばし、値が変わったら長さを Tween で変える
-- - 残り時間は、出している間は毎フレーム数え直す
-- - 残り時間はしきい値（Config.luau の BattleStatus 節）以下で黄色、さらに下で赤にする。兵力0は赤で出す
-- - 拠点の軍が変わったら（ReplicatedStorage.Kyoten の拠点ごとの Attribute の Gun）、戦況を出している間だけ、
--   自分の軍（味方軍）が制圧したときは Seiatsu、自分の軍の拠点が陥落したときは Kanraku の効果音を本人に鳴らす
--   （判断は ReplicatedStorage.Shared.Sounds の kyotenSceneFor）。出撃で拠点を作ったときと、途中で読み込んだときは鳴らさない
-- - タッチの配置（スマホの戦闘の操作ボタンを出している間）では、画面の大きさに合わせて縮める（Ui.fitTouchLayout）
-- - テストプレイでの確認用に、文は PlayerGui.BattleStatus.Panel の Remaining と Heiryoku、
--   ゲージは Mikatagun と Tekigun の Gauge.Fill（Size の X の Scale が長さの割合）で読める

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local BattleStatus = require(ReplicatedStorage.Shared.BattleStatus)
local Colors = require(ReplicatedStorage.Shared.Colors)
local Gun = require(ReplicatedStorage.Shared.Gun)
local Saishutsugeki = require(ReplicatedStorage.Shared.Saishutsugeki)
local SoundPlayer = require(ReplicatedStorage.Shared.SoundPlayer)
local Sounds = require(ReplicatedStorage.Shared.Sounds)
local StagePhase = require(ReplicatedStorage.Shared.StagePhase)
local PartyClient = require(script.Parent.Parent.PartyClient)
local Ui = require(script.Parent.Parent.Ui)
local EventSceneController = require(script.Parent.EventSceneController)

local BattleStatusController = {}

-- 軍全体の士気を複製する Configuration の名前（ShikiService.STATE）
local SHIKI_STATE = "Shiki"
-- 拠点ごとの Configuration を置くフォルダの名前（KyotenService.FOLDER）
local KYOTEN_FOLDER = "Kyoten"
-- プレイヤーの軍。出撃メンバーはいつも味方軍
local PLAYER_GUN: Gun.Gun = "Mikatagun"
-- 画面の上端（Roblox のトップバーの下）からの余白と、枠の大きさ（ピクセル）
local TOP = 8
local PANEL_WIDTH = 560
local PANEL_HEIGHT = 68
-- 中央の列（残り時間と兵力）の幅。両脇の士気の欄は残りを半分ずつ使う
local CENTER_WIDTH = 120
local SIDE_WIDTH = (PANEL_WIDTH - CENTER_WIDTH) / 2
-- 士気の欄の内側の余白と、ゲージの高さ
local SIDE_PADDING = 12
local GAUGE_HEIGHT = 16
-- 1段目（残り時間とゲージ）と2段目（兵力と軍の名前）の位置と高さ
local ROW1_Y = 4
local ROW1_HEIGHT = 36
local ROW2_Y = 42
local ROW2_HEIGHT = 22

-- 士気のゲージの長さを変える時間
local GAUGE_TWEEN = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- 強調の段階ごとの文字の色
local EMPHASIS_COLORS: { [BattleStatus.Emphasis]: Color3 } = {
	None = Ui.Color.Text,
	Warning = Ui.Color.Selected,
	Danger = Ui.Color.HealthLow,
}

-- 軍ごとの欄。味方軍を左、敵軍を右に置く
local SIDES: { [Gun.Gun]: { left: boolean, title: string } } = {
	Mikatagun = { left = true, title = "味方軍の士気" },
	Tekigun = { left = false, title = "敵軍の士気" },
}

type Gui = {
	screen: ScreenGui,
	remaining: TextLabel,
	heiryoku: TextLabel,
	-- 軍ごとの士気のゲージの中身
	fills: { [Gun.Gun]: Frame },
}

-- 軍1つぶんの士気の欄。上の段にゲージ、下の段に軍の名前を置く。欄の Frame とゲージの中身（Fill）を返す
local function side(gun: Gun.Gun): (Frame, Frame)
	local layout = SIDES[gun]
	-- ゲージの根元。左の欄は右端（中央の側）、右の欄は左端
	local root = if layout.left then 1 else 0
	local outer = 1 - root
	local fill: Frame = Ui.create("Frame", {
		Name = "Fill",
		AnchorPoint = Vector2.new(root, 0),
		Position = UDim2.fromScale(root, 0),
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Colors.Gun[gun],
		BorderSizePixel = 0,
	}, { Ui.create("UICorner", { CornerRadius = UDim.new(0, 4) }) })
	local gauge = Ui.create("Frame", {
		Name = "Gauge",
		Position = UDim2.fromOffset(SIDE_PADDING, ROW1_Y + (ROW1_HEIGHT - GAUGE_HEIGHT) / 2),
		Size = UDim2.new(1, -SIDE_PADDING * 2, 0, GAUGE_HEIGHT),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
	}, {
		Ui.create("UICorner", { CornerRadius = UDim.new(0, 4) }),
		Ui.create("UIStroke", { Color = Ui.Color.Accent, Thickness = 1 }),
		fill,
	})
	local title = Ui.text({
		Name = "Title",
		Position = UDim2.fromOffset(SIDE_PADDING, ROW2_Y),
		Size = UDim2.new(1, -SIDE_PADDING * 2, 0, ROW2_HEIGHT),
		Font = Ui.Font.Bold,
		TextSize = Ui.TextSize.Small,
		TextColor3 = Colors.Gun[gun]:Lerp(Color3.new(1, 1, 1), 0.45),
		TextStrokeTransparency = 0.5,
		TextXAlignment = if layout.left then Enum.TextXAlignment.Left else Enum.TextXAlignment.Right,
		Text = layout.title,
	})
	local frame: Frame = Ui.create("Frame", {
		Name = gun,
		AnchorPoint = Vector2.new(outer, 0),
		Position = UDim2.fromScale(outer, 0),
		Size = UDim2.new(0, SIDE_WIDTH, 1, 0),
		BackgroundTransparency = 1,
	}, { gauge, title })
	return frame, fill
end

local function buildGui(): Gui
	local remaining = Ui.text({
		Name = "Remaining",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, ROW1_Y),
		Size = UDim2.fromOffset(CENTER_WIDTH, ROW1_HEIGHT),
		Font = Ui.Font.Heavy,
		TextSize = Ui.TextSize.Title,
		TextStrokeTransparency = 0.3,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = BattleStatus.NO_REMAINING,
	})
	local heiryoku = Ui.text({
		Name = "Heiryoku",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, ROW2_Y),
		Size = UDim2.fromOffset(CENTER_WIDTH, ROW2_HEIGHT),
		Font = Ui.Font.Bold,
		TextStrokeTransparency = 0.4,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = BattleStatus.heiryokuText(nil),
	})
	local children: { Instance } = {
		Ui.create("UICorner", { CornerRadius = UDim.new(0, 8) }),
		remaining,
		heiryoku,
	}
	local fills: { [Gun.Gun]: Frame } = {}
	for _, gun in Gun.list do
		local frame, fill = side(gun)
		fills[gun] = fill
		table.insert(children, frame)
	end
	local panel = Ui.create("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, TOP),
		Size = UDim2.fromOffset(PANEL_WIDTH, PANEL_HEIGHT),
		BackgroundColor3 = Ui.Color.Panel,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
	}, children)
	local screen = Ui.screenGui("BattleStatus", Ui.Layer.BattleStatus, { panel })
	screen.Enabled = false
	Ui.fitTouchLayout(panel)
	return { screen = screen, remaining = remaining, heiryoku = heiryoku, fills = fills }
end

function BattleStatusController.start()
	local gui = buildGui()
	-- 最後に書いた残り時間の文。変わったときだけ書き直す
	local shownRemaining = ""

	local function refreshRemaining()
		local deadline = workspace:GetAttribute(StagePhase.DEADLINE_ATTRIBUTE)
		local seconds = if type(deadline) == "number" then deadline - workspace:GetServerTimeNow() else nil
		local text = BattleStatus.formatRemaining(seconds)
		if text == shownRemaining then
			return
		end
		shownRemaining = text
		gui.remaining.Text = text
		gui.remaining.TextColor3 = EMPHASIS_COLORS[BattleStatus.remainingEmphasis(seconds)]
	end

	local function refreshHeiryoku()
		local value = workspace:GetAttribute(Saishutsugeki.HEIRYOKU_ATTRIBUTE)
		local heiryoku = if type(value) == "number" then value else nil
		local emphasis = BattleStatus.heiryokuEmphasis(heiryoku)
		gui.heiryoku.Text = BattleStatus.heiryokuText(heiryoku)
		gui.heiryoku.TextColor3 = EMPHASIS_COLORS[emphasis]
		gui.heiryoku.Font = if emphasis == "None" then Ui.Font.Bold else Ui.Font.Heavy
	end

	-- 軍全体の士気をゲージの長さにする。animate なら Tween で変える
	local function refreshShiki(shikiState: Instance, gun: Gun.Gun, animate: boolean)
		local value = shikiState:GetAttribute(gun)
		local size = UDim2.fromScale(BattleStatus.shikiRatio(if type(value) == "number" then value else nil), 1)
		local fill = gui.fills[gun]
		if animate then
			TweenService:Create(fill, GAUGE_TWEEN, { Size = size }):Play()
		else
			fill.Size = size
		end
	end

	-- 渡される PartyState は、続けて届いたときに最新でないことがあるので、最新の写しで決める
	local function refreshVisible()
		local state = PartyClient.get()
		local me = PartyClient.me()
		local visible = BattleStatus.isVisible(
			if state then state.phase else nil,
			me == nil or me.waiting,
			EventSceneController.isPlaying()
		)
		if visible and not gui.screen.Enabled then
			-- 出す前に数え直し、前に出していた残り時間を一瞬でも見せない
			refreshRemaining()
		end
		gui.screen.Enabled = visible
	end

	PartyClient.changed:Connect(refreshVisible)
	EventSceneController.started:Connect(refreshVisible)
	EventSceneController.stopped:Connect(refreshVisible)
	workspace:GetAttributeChangedSignal(Saishutsugeki.HEIRYOKU_ATTRIBUTE):Connect(refreshHeiryoku)
	RunService.Heartbeat:Connect(function()
		if gui.screen.Enabled then
			refreshRemaining()
		end
	end)
	-- 拠点の軍が変わったら、制圧か陥落の効果音を鳴らす。拠点ごとに最後に見た軍を覚えておき、比べる。
	-- 最初に見た軍（出撃で拠点を作ったときと、途中で読み込んだとき）は覚えるだけで鳴らさない。
	-- 拠点の Configuration は決着とロビーへの戻りで消えるので、つないだ接続も一緒に切れる
	local function watchKyoten(kyoten: Instance)
		local known = kyoten:GetAttribute("Gun")
		kyoten:GetAttributeChangedSignal("Gun"):Connect(function()
			local gun = kyoten:GetAttribute("Gun")
			local scene = Sounds.kyotenSceneFor(known, gun, PLAYER_GUN)
			known = gun
			if scene and gui.screen.Enabled then
				SoundPlayer.playUi(scene)
			end
		end)
	end

	-- 士気と拠点の Configuration はサーバーが起動したときに作る。届くまで待つ間も、ほかの画面の起動を止めない
	task.spawn(function()
		local shikiState = ReplicatedStorage:WaitForChild(SHIKI_STATE)
		for _, gun in Gun.list do
			shikiState:GetAttributeChangedSignal(gun):Connect(function()
				refreshShiki(shikiState, gun, true)
			end)
			refreshShiki(shikiState, gun, false)
		end
	end)
	task.spawn(function()
		local kyotenFolder = ReplicatedStorage:WaitForChild(KYOTEN_FOLDER)
		kyotenFolder.ChildAdded:Connect(watchKyoten)
		for _, kyoten in kyotenFolder:GetChildren() do
			watchKyoten(kyoten)
		end
	end)
	refreshHeiryoku()
	refreshVisible()
end

return BattleStatusController
