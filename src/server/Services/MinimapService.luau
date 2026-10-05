--!strict
-- ミニマップに出す範囲と、出撃メンバーの位置と向きをクライアントへ複製する。描くのはクライアントの MinimapController。
-- Attribute の名前と計算は ReplicatedStorage.Shared.Minimap、複製の間隔は Config.luau の Minimap 節にある。
-- StreamingEnabled のため、クライアントには離れた区画の目印や仲間のキャラクターが読み込まれていないことがある。
-- そのため範囲と仲間の位置はサーバーが書く。
--
-- - 出撃（StageService.started）で、出撃したステージの区画の範囲の目印（KukakuService.bounds）の中心と、
--   目印を囲むワールドの軸にそろえた四角の大きさ（Minimap.boundsOf）を、workspace の Attribute の
--   MinimapCenter・MinimapSize に書く。ロビーのフェーズへ戻ったら消す
-- - ロビーのフェーズの外では、Config.luau の Minimap 節の UpdateInterval ごとに、出撃して残っているメンバーの
--   HumanoidRootPart の位置と向きを、Player の Attribute の MinimapPosition・MinimapFacing に書く。
--   倒れていて位置が無い人と、出撃メンバーでない人の Attribute は消す

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Minimap = require(ReplicatedStorage.Shared.Minimap)
local StagePhase = require(ReplicatedStorage.Shared.StagePhase)
local Stages = require(ReplicatedStorage.Shared.Stages)
local KukakuService = require(script.Parent.KukakuService)
local StageService = require(script.Parent.StageService)

local MinimapService = {}

local function clearPlayer(player: Player)
	player:SetAttribute(Minimap.POSITION_ATTRIBUTE, nil)
	player:SetAttribute(Minimap.FACING_ATTRIBUTE, nil)
end

-- 出撃したステージの区画の範囲を書く。区画か範囲の目印が無ければ消す（KukakuService が警告を出す）
local function publishBounds(stageId: string)
	local stage = Stages.get(stageId)
	local bounds = if stage then KukakuService.bounds(stage.kukaku) else nil
	if not bounds then
		workspace:SetAttribute(Minimap.CENTER_ATTRIBUTE, nil)
		workspace:SetAttribute(Minimap.SIZE_ATTRIBUTE, nil)
		return
	end
	-- 範囲の目印が回っていても収まるよう、目印を囲むワールドの軸にそろえた四角の大きさを書く
	local cframe, size = bounds.CFrame, bounds.Size
	local extentX, extentZ = Minimap.boundsOf(
		cframe.XVector.X,
		cframe.XVector.Z,
		cframe.YVector.X,
		cframe.YVector.Z,
		cframe.ZVector.X,
		cframe.ZVector.Z,
		size.X,
		size.Y,
		size.Z
	)
	workspace:SetAttribute(Minimap.CENTER_ATTRIBUTE, Vector2.new(bounds.Position.X, bounds.Position.Z))
	workspace:SetAttribute(Minimap.SIZE_ATTRIBUTE, Vector2.new(extentX, extentZ))
end

-- 出撃して残っているメンバーの位置と向きを書き、ほかの人の Attribute を消す
local function publishMembers()
	local members: { [Player]: boolean } = {}
	if StageService.getPhase() ~= "Lobby" then
		for _, member in StageService.getMembers() do
			members[member] = true
		end
	end
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not members[player] or not humanoid or humanoid.Health <= 0 or not root then
			if player:GetAttribute(Minimap.POSITION_ATTRIBUTE) ~= nil then
				clearPlayer(player)
			end
			continue
		end
		local look = root.CFrame.LookVector
		player:SetAttribute(Minimap.POSITION_ATTRIBUTE, Vector2.new(root.Position.X, root.Position.Z))
		player:SetAttribute(Minimap.FACING_ATTRIBUTE, Minimap.facingOf(look.X, look.Z))
	end
end

function MinimapService.start()
	StageService.started:Connect(function(info: StageService.StartInfo)
		publishBounds(info.stageId)
	end)
	StageService.phaseChanged:Connect(function(next: StagePhase.Phase)
		if next == "Lobby" then
			workspace:SetAttribute(Minimap.CENTER_ATTRIBUTE, nil)
			workspace:SetAttribute(Minimap.SIZE_ATTRIBUTE, nil)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(Config.Minimap.UpdateInterval)
			-- 1回の失敗で複製が止まらないよう、失敗は警告にして次の間隔で続ける
			local ok, err = pcall(publishMembers)
			if not ok then
				warn(`MinimapService: 出撃メンバーの位置を複製できなかった: {err}`)
			end
		end
	end)
end

return MinimapService
