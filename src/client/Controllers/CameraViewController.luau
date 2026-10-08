--!strict
-- カメラの位置・向き・縦の画角・画面の横と縦の比を、戦闘のフェーズの間だけ Config.luau の CameraView 節の Interval ごとに
-- Remotes.ReportCameraView でサーバーへ送る。サーバーはこれで下忍を出撃メンバーの視界の外に出す（CameraViewService）。
-- 待機中の人とイベントシーンの再生中は送らない（サーバーはキャラクターの向きで代える）。

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PartyClient = require(script.Parent.Parent.PartyClient)
local EventSceneController = require(script.Parent.EventSceneController)

local CameraViewController = {}

local function shouldSend(): boolean
	local state = PartyClient.get()
	local me = PartyClient.me()
	return state ~= nil
		and state.phase == "Battle"
		and me ~= nil
		and not me.waiting
		and not EventSceneController.isPlaying()
end

function CameraViewController.start()
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("ReportCameraView") :: RemoteEvent
	task.spawn(function()
		while true do
			task.wait(Config.CameraView.Interval)
			local camera = workspace.CurrentCamera
			if camera and shouldSend() then
				local size = camera.ViewportSize
				local aspect = if size.Y > 0 then size.X / size.Y else Config.CameraView.FallbackAspect
				local frame = camera.CFrame
				remote:FireServer(frame.Position, frame.LookVector, camera.FieldOfView, aspect)
			end
		end
	end)
end

return CameraViewController
