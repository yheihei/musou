--!strict
-- サーバーが自分のキャラクターに置いた前進や緊急回避の拘束（HumanoidRootPart の子の Push）を、
-- 届いてから Attribute の Duration 秒で外す。サーバーから届く時刻がずれても、動く時間を同じにするため。
-- 拘束の中身は ServerScriptService.Server.Combat.Push が作る。

local Players = game:GetService("Players")

local PushController = {}

local NAME = "Push"

local function watch(character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root then
		return
	end
	root.ChildAdded:Connect(function(child)
		if child.Name ~= NAME then
			return
		end
		local duration = child:GetAttribute("Duration")
		if type(duration) ~= "number" then
			return
		end
		task.delay(duration, function()
			if child.Parent then
				child:Destroy()
			end
		end)
	end)
end

function PushController.start()
	local player = Players.LocalPlayer
	player.CharacterAdded:Connect(watch)
	if player.Character then
		task.spawn(watch, player.Character)
	end
end

return PushController
