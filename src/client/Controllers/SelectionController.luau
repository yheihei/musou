--!strict
-- 出撃前の画面。ロビーのフェーズで、待機中でない人に、画面の右側へ選択の欄を縦に並べて出す。
-- 上からステージ・秘計の欄（スクロール）、下にメンバーの準備状況と出撃ボタンの帯を置く。
-- 選択は Remotes で送り、受け付けるかはサーバーが決める。画面は届いた PartyState（PartyClient）だけを映し、
-- 先回りして変えない。拒否の理由は SelectionRejected で届き、パネルの下に出す。
-- 欄は src/client/Selection の下にある。
--
-- - ゲームパッドのときは、画面が開いたら最初のボタンを選ぶ（スティックと十字キーで移動、A で決定）
-- - 拒否の音は Cancel

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RejectMessage = require(ReplicatedStorage.Shared.RejectMessage)
local RemoteSchema = require(ReplicatedStorage.Shared.RemoteSchema)
local SoundPlayer = require(ReplicatedStorage.Shared.SoundPlayer)
local PartyClient = require(script.Parent.Parent.PartyClient)
local Ui = require(script.Parent.Parent.Ui)
local SelectionFolder = script.Parent.Parent:WaitForChild("Selection")
local SectionKit = require(SelectionFolder:WaitForChild("SectionKit"))
local StageSection = require(SelectionFolder:WaitForChild("StageSection"))
local HikeiSection = require(SelectionFolder:WaitForChild("HikeiSection"))
local ShutsugekiBar = require(SelectionFolder:WaitForChild("ShutsugekiBar"))

local SelectionController = {}

-- 画面の端からの余白と、パネルの幅（左上の非公式の表記と重ならない幅）、
-- 右下の撃破数の表示を避ける下の余白（ピクセル）
local MARGIN = 16
local PANEL_WIDTH = 460
local BOTTOM_CLEARANCE = 112
-- 見出しと、下の拒否の理由の欄の高さ
local HEADER_HEIGHT = 40
local MESSAGE_HEIGHT = 40
-- 拒否の理由を出しておく秒数
local MESSAGE_TIME = 4

type Gui = {
	screen: ScreenGui,
	body: ScrollingFrame,
	footer: Frame,
	message: TextLabel,
}

local function buildGui(): Gui
	local body = Ui.create("ScrollingFrame", {
		Name = "Body",
		Position = UDim2.fromOffset(0, HEADER_HEIGHT),
		Size = UDim2.new(1, 0, 1, -(HEADER_HEIGHT + ShutsugekiBar.HEIGHT + MESSAGE_HEIGHT)),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Ui.Color.Accent,
		Selectable = false,
	}, {
		Ui.create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 14) }),
		Ui.create("UIPadding", {
			PaddingTop = UDim.new(0, 4),
			PaddingBottom = UDim.new(0, 12),
			PaddingLeft = UDim.new(0, 12),
			PaddingRight = UDim.new(0, 16),
		}),
	})
	local footer = Ui.create("Frame", {
		Name = "Footer",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, -MESSAGE_HEIGHT),
		Size = UDim2.new(1, 0, 0, ShutsugekiBar.HEIGHT),
		BackgroundTransparency = 1,
	})
	local message = Ui.text({
		Name = "Message",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 12, 1, -6),
		Size = UDim2.new(1, -24, 0, MESSAGE_HEIGHT - 8),
		Font = Ui.Font.Bold,
		TextColor3 = Ui.Color.HealthLow,
		TextWrapped = true,
		Text = "",
	})
	local panel = Ui.create("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -MARGIN, 0, MARGIN),
		Size = UDim2.new(0, PANEL_WIDTH, 1, -(MARGIN + BOTTOM_CLEARANCE)),
		BackgroundColor3 = Ui.Color.Panel,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
	}, {
		Ui.create("UICorner", { CornerRadius = UDim.new(0, 10) }),
		Ui.create("UIStroke", { Color = Ui.Color.Accent, Thickness = 1 }),
		Ui.text({
			Name = "Header",
			Position = UDim2.fromOffset(12, 0),
			Size = UDim2.new(1, -24, 0, HEADER_HEIGHT),
			Font = Ui.Font.Heavy,
			TextSize = Ui.TextSize.Title - 4,
			Text = "出撃の準備",
		}),
		body,
		footer,
		message,
	})
	local screen = Ui.screenGui("Selection", Ui.Layer.Selection, { panel })
	screen.Enabled = false
	return { screen = screen, body = body :: ScrollingFrame, footer = footer :: Frame, message = message }
end

function SelectionController.start()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local gui = buildGui()

	-- 拒否の理由を出す。続けて届いたら新しい方を出し、古い方の消す予定は取り消す
	local messageToken = 0
	local function showMessage(text: string)
		messageToken += 1
		local token = messageToken
		gui.message.Text = text
		task.delay(MESSAGE_TIME, function()
			if messageToken == token then
				gui.message.Text = ""
			end
		end)
	end

	local context: SectionKit.Context = {
		send = function(remoteName: string, ...: any)
			local remote = remotes:FindFirstChild(remoteName)
			if remote and remote:IsA("RemoteEvent") then
				remote:FireServer(...)
			end
		end,
		notify = showMessage,
	}
	local bar = ShutsugekiBar.build(context)
	bar.frame.Parent = gui.footer
	local sections: { SectionKit.Section } = {
		StageSection.build(context),
		HikeiSection.build(context),
		bar,
	}
	for _, section in sections do
		if section ~= bar then
			section.frame.Parent = gui.body
		end
	end

	local function firstButton(): GuiObject?
		for _, section in sections do
			local button = section.firstButton()
			if button then
				return button
			end
		end
		return nil
	end

	local wasVisible = false
	local function refresh()
		local state = PartyClient.get()
		local me = PartyClient.me()
		local visible = state ~= nil and state.phase == "Lobby" and me ~= nil and not me.waiting
		gui.screen.Enabled = visible
		if state and visible then
			for _, section in sections do
				section.update(state)
			end
		end
		if visible and not wasVisible and Ui.inputKind() == "Gamepad" then
			GuiService.SelectedObject = firstButton()
		elseif not visible then
			local selected = GuiService.SelectedObject
			if selected and selected:IsDescendantOf(gui.screen) then
				GuiService.SelectedObject = nil
			end
			gui.message.Text = ""
		end
		wasVisible = visible
	end

	PartyClient.changed:Connect(refresh)
	local rejected = remotes:WaitForChild("SelectionRejected") :: RemoteEvent
	rejected.OnClientEvent:Connect(function(reason: RemoteSchema.RejectReason)
		SoundPlayer.playUi("Cancel")
		showMessage(RejectMessage.of(reason))
	end)
	Ui.onInputKindChanged(function(kind)
		if kind == "Gamepad" and gui.screen.Enabled and not GuiService.SelectedObject then
			GuiService.SelectedObject = firstButton()
		end
	end)
	refresh()
end

return SelectionController
