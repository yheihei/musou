--!strict
-- 出撃地点と再出撃の拠点に出現し直したら、カメラを体の後ろへ戻し、体の向き（出撃地点は敵の側）を見せる（#117）。
-- サーバーは出現し直した体を立たせた後に、体の Attribute の SpawnFacing へ立たせた向きを書く（PlayerService.spawnAt）。
-- ロビーへの出現し直し（SpawnFacing を書かない）とイベントシーンの再生中は、カメラを動かさない。
--
-- - Roblox 標準のカメラは、出現し直した体に付いたときの向き（ロビーの出現地点の向き）のまま、体を移しても向きを変えない。
--   そのままだと、敵の側に背を向けて戦場に出ることがある（2026-10-17 の Studio。試験用ステージで西を向いていた）
-- - 標準のカメラは、カメラの CFrame を書いても次のフレームで自分の向きに戻す。Scriptable にしてから向きを書き、
--   Custom に戻すと、書いた向きから続ける（2026-10-17 の Studio で確かめた）
-- - 向きは CameraView.behindLookOf（体の向きを Config.luau の CameraView 節の SpawnPitch 度だけ見下ろす）。
--   カメラと体の離れ（ズーム）は今のまま

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CameraView = require(ReplicatedStorage.Shared.CameraView)
local Config = require(ReplicatedStorage.Shared.Config)
local EventSceneController = require(script.Parent.EventSceneController)

local SpawnCameraController = {}

-- サーバーが立たせた向きを書く、体の Attribute
local ATTRIBUTE = "SpawnFacing"
-- 出現し直した体に標準のカメラが付くまで待つ秒数の上限
local SUBJECT_WAIT = 3
-- カメラと体の離れが分からないときの離れ（スタッド。Roblox 標準のカメラの初めの離れ）
local DEFAULT_DISTANCE = 12.5
-- カメラを向ける、体の中心からの高さ（スタッド）
local FOCUS_HEIGHT = 1.5

-- カメラを体 character の後ろへ戻し、向き facing を見下ろさせる
local function face(character: Model, facing: Vector3)
	local camera = workspace.CurrentCamera
	-- 出撃では、立たせた向きを書いた体がまとめて届き、届いた時点では HumanoidRootPart がまだ無いことがある
	-- （2026-10-17 の Studio）。体の部品が届くまで待つ
	local humanoid = character:WaitForChild("Humanoid", SUBJECT_WAIT)
	local root = character:WaitForChild("HumanoidRootPart", SUBJECT_WAIT)
	if not camera or not humanoid or not humanoid:IsA("Humanoid") or not root or not root:IsA("BasePart") then
		return
	end
	-- 標準のカメラが新しい体に付くまで待つ（付く前に向きを書くと、付いたときの向きに戻る）
	local waited = 0
	while camera.CameraSubject ~= humanoid and waited < SUBJECT_WAIT and character.Parent do
		waited += task.wait()
	end
	task.wait()
	if
		not character.Parent
		or camera.CameraSubject ~= humanoid
		or camera.CameraType ~= Enum.CameraType.Custom
		or EventSceneController.isPlaying()
	then
		return
	end
	local direction = CameraView.behindLookOf(facing, Config.CameraView.SpawnPitch)
	-- 今のカメラと注視点の離れ（ズーム）を保つ。ズームの範囲の外（描画が止まっていて古いときなど）は初めの離れ
	local player = Players.LocalPlayer
	local distance = (camera.CFrame.Position - camera.Focus.Position).Magnitude
	if not (distance >= player.CameraMinZoomDistance and distance <= player.CameraMaxZoomDistance) then
		distance = DEFAULT_DISTANCE
	end
	local focus = root.Position + Vector3.new(0, FOCUS_HEIGHT, 0)
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.lookAt(focus - direction * distance, focus)
	camera.Focus = CFrame.new(focus)
	task.wait()
	-- 待つ間にイベントシーンがカメラを使い始めていたら、そのままにする
	if camera.CameraType == Enum.CameraType.Scriptable and not EventSceneController.isPlaying() then
		camera.CameraType = Enum.CameraType.Custom
	end
end

local function watch(character: Model)
	local function onFacing()
		local facing = character:GetAttribute(ATTRIBUTE)
		if typeof(facing) == "Vector3" then
			task.spawn(face, character, facing)
		end
	end
	character:GetAttributeChangedSignal(ATTRIBUTE):Connect(onFacing)
	onFacing()
end

function SpawnCameraController.start()
	local player = Players.LocalPlayer
	player.CharacterAdded:Connect(watch)
	if player.Character then
		task.spawn(watch, player.Character)
	end
end

return SpawnCameraController
