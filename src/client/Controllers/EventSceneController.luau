--!strict
-- イベントシーンの再生。Remotes.PlayEventScene（シーン ID と、役者とカメラの位置）を受けて、台本どおりにカメラを動かし、
-- 役者を出し入れして歩かせ、会話窓に台詞を出す。台本は ReplicatedStorage.Shared.EventScenes、
-- 役者とカメラの位置はサーバーの EventSceneService が区画の目印から作る。
--
-- - 全クライアントが、サーバーの時刻で同じ開始時刻から同じ手順を進める（遅れて届いたら、過ぎた手順をすぐに進める）
-- - 役者は ReplicatedStorage.Yakusha の雛形を自分の画面だけに写して動かす。雛形の Animate にある待機と歩きの
--   モーションを流し、位置を動かして歩かせる（新しいモーションは作らない）
-- - 再生中は、操作（移動・ジャンプ・攻撃・秘計）を止め、HUD を隠し、上下に黒帯を出し、
--   プレイヤーのキャラクターと名札を自分の画面で隠す。移動とジャンプは、入力を高い優先度で吸い取り、
--   自分のキャラクターの歩く速さと跳ぶ高さを 0 にして止める（PlayerModule は StarterPlayer の下にあり、
--   require すると別の実体を作るおそれがあるので触らない）
-- - フェーズがイベントシーンでなくなったら（長さが過ぎたか全員がスキップした）、すぐに片付けて元に戻す。
--   台本を終えてもフェーズが変わらなければ、シーンの長さに END_TIMEOUT 秒を足した時刻で元に戻す
-- - 途中で人が抜けても、写した役者で最後まで進める

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local EventScenes = require(ReplicatedStorage.Shared.EventScenes)
local Ground = require(ReplicatedStorage.Shared.Ground)
local RemoteSchema = require(ReplicatedStorage.Shared.RemoteSchema)
local Dialogue = require(script.Parent.Parent.Dialogue)
local PartyClient = require(script.Parent.Parent.PartyClient)
local Ui = require(script.Parent.Parent.Ui)
local HUDController = require(script.Parent.HUDController)
local InputController = require(script.Parent.InputController)

local EventSceneController = {}

-- 役者の雛形が届くのを待つ秒数の上限
local TEMPLATE_TIMEOUT = 5
-- 黒帯の高さ（画面の高さの割合）と、出し入れにかける秒数
local LETTERBOX_HEIGHT = 0.11
local LETTERBOX_TIME = 0.4
-- 台本を終えてからフェーズが変わるのを待つ秒数の上限（シーンの長さに足す）
local END_TIMEOUT = 5
-- 役者を地面に合わせるとき、目印の高さのどれだけ上から地面を探すか（スタッド）
local GROUND_SEARCH = 3
-- 移動とジャンプの入力を止める操作の名前と入力
local FREEZE_ACTION = "EventSceneFreeze"
local FREEZE_INPUTS: { Enum.KeyCode } = {
	Enum.KeyCode.W,
	Enum.KeyCode.A,
	Enum.KeyCode.S,
	Enum.KeyCode.D,
	Enum.KeyCode.Up,
	Enum.KeyCode.Down,
	Enum.KeyCode.Left,
	Enum.KeyCode.Right,
	Enum.KeyCode.Space,
	Enum.KeyCode.Thumbstick1,
	Enum.KeyCode.ButtonA,
}
-- プレイヤーのキャラクターを毎フレーム隠し直す処理の名前
local HIDE_STEP = "EventSceneHide"

-- PlayEventScene に添えて届く役者とカメラの位置（サーバーの EventSceneService.Setting）
type Setting = {
	startedAt: number,
	camera: { [string]: CFrame },
	yakusha: { [string]: CFrame },
	characters: { [string]: string },
}

type Actor = {
	model: Model,
	root: BasePart,
	-- 立ち位置（目印の位置と向き。高さは地面に合わせた HumanoidRootPart の高さ）
	home: CFrame,
	idleId: string?,
	walkId: string?,
	idle: AnimationTrack?,
	walk: AnimationTrack?,
	tween: Tween?,
}

type Playback = {
	token: number,
	scene: EventScenes.EventScene,
	setting: Setting?,
	actors: { [string]: Actor },
	folder: Folder,
	cameraTween: Tween?,
	-- 隠したプレイヤーの名札
	hiddenTags: { BillboardGui },
}

type Letterbox = {
	screen: ScreenGui,
	top: Frame,
	bottom: Frame,
}

-- 止める前の自分のキャラクターの歩く速さと跳ぶ高さ
type Frozen = {
	humanoid: Humanoid,
	walkSpeed: number,
	jumpHeight: number,
}

local current: Playback? = nil
local token = 0
local letterbox: Letterbox? = nil
local frozen: Frozen? = nil

local startedEvent = Instance.new("BindableEvent")
-- 再生を始めたときに、シーン ID で発火する
EventSceneController.started = startedEvent.Event
local stoppedEvent = Instance.new("BindableEvent")
-- 再生を終えて元に戻したときに発火する
EventSceneController.stopped = stoppedEvent.Event

-- 再生しているか
function EventSceneController.isPlaying(): boolean
	return current ~= nil
end

local function getLetterbox(): Letterbox
	if letterbox then
		return letterbox
	end
	local function bar(name: string, anchorY: number): Frame
		return Ui.create("Frame", {
			Name = name,
			AnchorPoint = Vector2.new(0, anchorY),
			Position = UDim2.fromScale(0, anchorY),
			Size = UDim2.fromScale(1, 0),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BorderSizePixel = 0,
		})
	end
	local top = bar("Top", 0)
	local bottom = bar("Bottom", 1)
	local screen = Ui.screenGui("Letterbox", Ui.Layer.Letterbox, { top, bottom })
	screen.IgnoreGuiInset = true
	screen.Enabled = false
	local created: Letterbox = { screen = screen, top = top, bottom = bottom }
	letterbox = created
	return created
end

-- 上下の黒帯を出し入れする
local function showLetterbox(visible: boolean)
	local view = getLetterbox()
	if visible then
		view.screen.Enabled = true
	end
	local info = TweenInfo.new(LETTERBOX_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	local size = UDim2.fromScale(1, if visible then LETTERBOX_HEIGHT else 0)
	local tween = TweenService:Create(view.top, info, { Size = size })
	TweenService:Create(view.bottom, info, { Size = size }):Play()
	tween:Play()
	if not visible then
		tween.Completed:Once(function(state)
			if state == Enum.PlaybackState.Completed and not current then
				view.screen.Enabled = false
			end
		end)
	end
end

-- 自分のキャラクターの歩く速さと跳ぶ高さを 0 にするか、止める前の値に戻す。
-- 戻すのは、止めている間にサーバーが値を変えていない（0 のまま）ときだけ
local function setMovementFrozen(freeze: boolean)
	if freeze then
		local character = Players.LocalPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and not frozen then
			frozen = { humanoid = humanoid, walkSpeed = humanoid.WalkSpeed, jumpHeight = humanoid.JumpHeight }
			humanoid.WalkSpeed = 0
			humanoid.JumpHeight = 0
		end
		return
	end
	local saved = frozen
	frozen = nil
	if saved and saved.humanoid.Parent then
		if saved.humanoid.WalkSpeed == 0 then
			saved.humanoid.WalkSpeed = saved.walkSpeed
		end
		if saved.humanoid.JumpHeight == 0 then
			saved.humanoid.JumpHeight = saved.jumpHeight
		end
	end
end

-- 操作を止めるか戻す。攻撃などの入力を送らないようにし、移動とジャンプの入力を吸い取って止める
local function setControlsEnabled(enabled: boolean)
	InputController.setEnabled(enabled)
	setMovementFrozen(not enabled)
	if enabled then
		ContextActionService:UnbindAction(FREEZE_ACTION)
	else
		ContextActionService:BindActionAtPriority(FREEZE_ACTION, function()
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value, table.unpack(FREEZE_INPUTS))
	end
end

-- プレイヤーのキャラクターと名札を自分の画面で隠す。名札は隠したものを覚えておき、元に戻すときに出し直す
local function hideCharacters(playback: Playback)
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if not character then
			continue
		end
		for _, descendant in character:GetDescendants() do
			if descendant:IsA("BasePart") or descendant:IsA("Decal") then
				descendant.LocalTransparencyModifier = 1
			elseif descendant:IsA("BillboardGui") and descendant.Enabled then
				descendant.Enabled = false
				table.insert(playback.hiddenTags, descendant)
			end
		end
	end
end

local function showCharacters(playback: Playback)
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if not character then
			continue
		end
		for _, descendant in character:GetDescendants() do
			if descendant:IsA("BasePart") or descendant:IsA("Decal") then
				descendant.LocalTransparencyModifier = 0
			end
		end
	end
	for _, tag in playback.hiddenTags do
		if tag.Parent then
			tag.Enabled = true
		end
	end
	table.clear(playback.hiddenTags)
end

-- 雛形の Animate にあるモーションの ID。folderName は Animate の下のフォルダ（idle、walk）
local function animationIdOf(model: Model, folderName: string): string?
	local animate = model:FindFirstChild("Animate")
	local holder = animate and animate:FindFirstChild(folderName)
	local animation = holder and holder:FindFirstChildOfClass("Animation")
	return if animation then animation.AnimationId else nil
end

local function loadTrack(model: Model, animationId: string?): AnimationTrack?
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid or not animationId then
		return nil
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		local created = Instance.new("Animator")
		created.Parent = humanoid
		animator = created
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = animationId
	local ok, track = pcall(function()
		return (animator :: Animator):LoadAnimation(animation)
	end)
	if not ok then
		return nil
	end
	track.Looped = true
	return track
end

-- 雛形を写して役者を作る。まだ出さない
local function createActor(characterId: string): Actor?
	local templates = ReplicatedStorage:WaitForChild("Yakusha", TEMPLATE_TIMEOUT)
	local template = templates and templates:WaitForChild(characterId, TEMPLATE_TIMEOUT)
	if not template or not template:IsA("Model") then
		warn(`EventSceneController: 役者 {characterId} の雛形が ReplicatedStorage.Yakusha に無い`)
		return nil
	end
	local model = template:Clone()
	local root = model:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		model:Destroy()
		return nil
	end
	local animate = model:FindFirstChild("Animate")
	if animate and animate:IsA("LocalScript") then
		animate.Enabled = false
	end
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
		end
	end
	root.Anchored = true
	model.PrimaryPart = root
	return {
		model = model,
		root = root,
		home = root.CFrame,
		idleId = animationIdOf(model, "idle"),
		walkId = animationIdOf(model, "walk"),
		idle = nil,
		walk = nil,
		tween = nil,
	}
end

-- 水平の向き。上下の成分しか無ければ北
local function flatten(direction: Vector3): Vector3
	local flat = Vector3.new(direction.X, 0, direction.Z)
	return if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
end

-- 地面から HumanoidRootPart の中心までの高さ
local function liftOf(actor: Actor): number
	local humanoid = actor.model:FindFirstChildOfClass("Humanoid")
	return (if humanoid then humanoid.HipHeight else 2) + actor.root.Size.Y / 2
end

local function appear(playback: Playback, name: string)
	local actor = playback.actors[name]
	local setting = playback.setting
	local mark = if setting then setting.yakusha[name] else nil
	if not actor or not mark then
		return
	end
	local position = mark.Position
	actor.model:PivotTo(CFrame.lookAt(position, position + flatten(mark.LookVector)))
	actor.model.Parent = playback.folder
	Ground.placeCharacter(actor.model, position.X, position.Z, position.Y + GROUND_SEARCH)
	actor.home = actor.root.CFrame
	if not actor.idle then
		actor.idle = loadTrack(actor.model, actor.idleId)
		actor.walk = loadTrack(actor.model, actor.walkId)
	end
	if actor.idle then
		actor.idle:Play()
	end
end

local function exit(playback: Playback, name: string)
	local actor = playback.actors[name]
	if not actor then
		return
	end
	if actor.tween then
		actor.tween:Cancel()
	end
	actor.model.Parent = nil
end

-- 役者を、立ち位置から見て右へ x・前へ z スタッドの位置へ time 秒で歩かせる
local function move(playback: Playback, step: EventScenes.Step)
	local actor = playback.actors[step.yakusha or ""]
	if not actor or not actor.model.Parent then
		return
	end
	local from = actor.root.Position
	local target = (actor.home * CFrame.new(step.x or 0, 0, -(step.z or 0))).Position
	local lift = liftOf(actor)
	local groundY = Ground.heightAt(target.X, target.Z, target.Y + GROUND_SEARCH) or (from.Y - lift)
	local destination = Vector3.new(target.X, groundY + lift, target.Z)
	local facing = flatten(destination - from)
	actor.root.CFrame = CFrame.lookAt(from, from + facing)
	if actor.tween then
		actor.tween:Cancel()
	end
	local tween = TweenService:Create(
		actor.root,
		TweenInfo.new(math.max(step.time or 0, 0.01), Enum.EasingStyle.Linear),
		{ CFrame = CFrame.lookAt(destination, destination + facing) }
	)
	actor.tween = tween
	local walk = actor.walk
	if walk then
		walk:Play()
	end
	tween.Completed:Once(function()
		if walk then
			walk:Stop()
		end
	end)
	tween:Play()
end

local function moveCamera(playback: Playback, step: EventScenes.Step)
	local setting = playback.setting
	local target = if setting and step.shot then setting.camera[step.shot] else nil
	if not target then
		return
	end
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	if playback.cameraTween then
		playback.cameraTween:Cancel()
		playback.cameraTween = nil
	end
	local time = step.time or 0
	if time > 0 then
		local tween = TweenService:Create(
			camera,
			TweenInfo.new(time, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
			{ CFrame = target }
		)
		playback.cameraTween = tween
		tween:Play()
	else
		camera.CFrame = target
	end
end

-- 会話窓に台詞を出す。出撃した人数より後ろのプレイヤーの台詞は出さない
local function say(playback: Playback, step: EventScenes.Step)
	local speaker = step.speaker
	local text = step.text
	if not speaker or not text then
		return
	end
	local characterId: string? = speaker
	if EventScenes.playerIndexOf(speaker) then
		characterId = if playback.setting then playback.setting.characters[speaker] else nil
	end
	if not characterId then
		return
	end
	local hyojo: RemoteSchema.Hyojo = step.hyojo or "Tsujo"
	task.spawn(Dialogue.say, characterId, hyojo, text)
end

local function execute(playback: Playback, step: EventScenes.Step)
	if step.kind == "Camera" then
		moveCamera(playback, step)
	elseif step.kind == "Appear" then
		appear(playback, step.yakusha or "")
	elseif step.kind == "Exit" then
		exit(playback, step.yakusha or "")
	elseif step.kind == "Move" then
		move(playback, step)
	elseif step.kind == "Serifu" then
		say(playback, step)
	end
end

local function stop()
	local playback = current
	if not playback then
		return
	end
	current = nil
	token += 1
	Dialogue.close()
	if playback.cameraTween then
		playback.cameraTween:Cancel()
	end
	for _, actor in playback.actors do
		if actor.tween then
			actor.tween:Cancel()
		end
		actor.model:Destroy()
	end
	playback.folder:Destroy()
	RunService:UnbindFromRenderStep(HIDE_STEP)
	showCharacters(playback)
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end
	showLetterbox(false)
	HUDController.setVisible(true)
	setControlsEnabled(true)
	stoppedEvent:Fire()
end

-- 役者を用意して、台本の手順を開始時刻からの時刻どおりに進める
local function run(playback: Playback)
	local myToken = playback.token
	local setting = playback.setting
	for _, name in EventScenes.yakushaOf(playback.scene) do
		local characterId = if setting then setting.characters[name] else nil
		if characterId then
			local actor = createActor(characterId)
			if token ~= myToken then
				if actor then
					actor.model:Destroy()
				end
				return
			end
			if actor then
				playback.actors[name] = actor
			end
		end
	end
	local startedAt = if setting then setting.startedAt else workspace:GetServerTimeNow()
	for _, item in EventScenes.schedule(playback.scene) do
		local delay = startedAt + item.at - workspace:GetServerTimeNow()
		if delay > 0 then
			task.wait(delay)
		end
		if token ~= myToken then
			return
		end
		local ok, err = pcall(execute, playback, item.step)
		if not ok then
			warn(`EventSceneController: {playback.scene.id} の {item.step.kind} を進められなかった: {err}`)
		end
	end
	-- 台本を終えたら、フェーズが変わるまで最後の画面のまま待つ
	local remaining = startedAt + EventScenes.durationOf(playback.scene) + END_TIMEOUT - workspace:GetServerTimeNow()
	if remaining > 0 then
		task.wait(remaining)
	end
	if token == myToken then
		stop()
	end
end

local function start(sceneId: string, setting: Setting?)
	stop()
	local scene = EventScenes.get(sceneId)
	if not scene then
		warn(`EventSceneController: イベントシーン {sceneId} は EventScenes.luau の表に無い`)
		return
	end
	token += 1
	local folder = Instance.new("Folder")
	folder.Name = "EventSceneYakusha"
	folder.Parent = workspace
	local playback: Playback = {
		token = token,
		scene = scene,
		setting = setting,
		actors = {},
		folder = folder,
		cameraTween = nil,
		hiddenTags = {},
	}
	current = playback
	setControlsEnabled(false)
	HUDController.setVisible(false)
	showLetterbox(true)
	if scene.steps and setting then
		workspace.CurrentCamera.CameraType = Enum.CameraType.Scriptable
		hideCharacters(playback)
		RunService:BindToRenderStep(HIDE_STEP, Enum.RenderPriority.Camera.Value + 1, function()
			if current == playback then
				hideCharacters(playback)
			end
		end)
	end
	task.spawn(run, playback)
	startedEvent:Fire(sceneId)
end

-- 届いた役者とカメラの位置を確かめる。形が違えば nil
local function toSetting(value: unknown): Setting?
	if type(value) ~= "table" then
		return nil
	end
	local setting = value :: { [string]: any }
	if
		type(setting.startedAt) ~= "number"
		or type(setting.camera) ~= "table"
		or type(setting.yakusha) ~= "table"
		or type(setting.characters) ~= "table"
	then
		return nil
	end
	return setting :: any
end

function EventSceneController.start()
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PlayEventScene") :: RemoteEvent
	remote.OnClientEvent:Connect(function(sceneId: unknown, setting: unknown)
		if type(sceneId) ~= "string" then
			return
		end
		start(sceneId, toSetting(setting))
	end)
	PartyClient.changed:Connect(function(state: RemoteSchema.PartyState)
		if current and state.phase ~= "EventScene" then
			stop()
		end
	end)
end

return EventSceneController
