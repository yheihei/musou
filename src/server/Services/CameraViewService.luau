--!strict
-- プレイヤーの視界。クライアントが Remotes.ReportCameraView で送るカメラの位置・向き・画角を検証して持ち、
-- 下忍を出す処理が「出撃メンバーの誰かに見える位置か」を引く（判定は CameraView、数値は Config.luau の CameraView 節）。
--
-- - 届いた値は CameraView.validate で確かめ、キャラクターから MaxDistance より遠いカメラと、Interval より短い間隔で
--   届いた分は捨てる（不正な値ではエラーを出さず、何もしない）
-- - 最後に届いてから Stale 秒を過ぎたカメラと、まだ届いていない人は、キャラクターの頭の高さから体の向きを見ているとみなす
-- - 倒れた人も、体が残っている間はカメラが戦場を映しているので、同じように扱う
-- - キャラクターがいない人（体が片付いて再出撃を待つ人など）は、何も見ていないとみなす
-- - カメラから FarDistance より遠い位置は、見えないとみなす

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CameraView = require(ReplicatedStorage.Shared.CameraView)
local Config = require(ReplicatedStorage.Shared.Config)
local DebugCommand = require(script.Parent.Parent.DebugCommand)

-- 最後に受け付けたカメラと、受け付けた時刻（os.clock）
type Report = {
	view: CameraView.View,
	receivedAt: number,
}

local CameraViewService = {}

local reports: { [Player]: Report } = {}
-- 不正な値を捨てた回数（確認用）
local rejected: { [Player]: number } = {}

-- キャラクターの体の HumanoidRootPart。倒れていても体が残っていれば返す
local function rootOf(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function onReport(player: Player, position: unknown, look: unknown, fovY: unknown, aspect: unknown)
	local view = CameraView.validate(position, look, fovY, aspect)
	local root = rootOf(player)
	if not view or (root and vector.magnitude(view.position - root.Position) > Config.CameraView.MaxDistance) then
		rejected[player] = (rejected[player] or 0) + 1
		return
	end
	local now = os.clock()
	local last = reports[player]
	-- 送る間隔より短い間隔で届いた分は捨てる（少し早く届くことがあるので半分まで許す）
	if last and now - last.receivedAt < Config.CameraView.Interval / 2 then
		return
	end
	reports[player] = { view = view, receivedAt = now }
end

-- プレイヤーの今の視界と、その出どころ（"Report" は届いたカメラ、"Facing" はキャラクターの向き）。
-- キャラクターがいなければ nil
function CameraViewService.viewOf(player: Player): (CameraView.View?, string?)
	local root = rootOf(player)
	if not root then
		return nil, nil
	end
	local report = reports[player]
	if report and os.clock() - report.receivedAt <= Config.CameraView.Stale then
		return report.view, "Report"
	end
	return CameraView.fromFacing(root.Position, root.CFrame.LookVector), "Facing"
end

-- players の誰かの視界に、point の周りの半径 margin（省くと Config の Margin）の球がかかるか
function CameraViewService.seenByAny(players: { Player }, point: Vector3, margin: number?): boolean
	local views = {}
	for _, player in players do
		local view = CameraViewService.viewOf(player)
		if view then
			table.insert(views, view)
		end
	end
	return CameraView.seenByAny(views, point, margin or Config.CameraView.Margin, Config.CameraView.FarDistance)
end

local function round(value: number): number
	return math.round(value * 10) / 10
end

local function registerDebugCommands()
	DebugCommand.register(
		"DumpCameraView",
		"<プレイヤー名>",
		"サーバーが使うプレイヤーの視界（出どころ・最後に届いてからの秒数・カメラの位置と向き・縦の画角・横と縦の比・捨てた回数）を JSON で返す",
		function(name)
			local player = DebugCommand.findPlayer(name)
			local view, source = CameraViewService.viewOf(player)
			local report = reports[player]
			return HttpService:JSONEncode({
				player = player.Name,
				source = source,
				age = if report then round(os.clock() - report.receivedAt) else nil,
				position = if view
					then { round(view.position.x), round(view.position.y), round(view.position.z) }
					else nil,
				look = if view
					then {
						math.round(view.look.x * 100) / 100,
						math.round(view.look.y * 100) / 100,
						math.round(view.look.z * 100) / 100,
					}
					else nil,
				fovY = if view then round(view.fovY) else nil,
				aspect = if view then math.round(view.aspect * 100) / 100 else nil,
				rejected = rejected[player] or 0,
			})
		end
	)

	DebugCommand.register(
		"CheckCameraView",
		"<プレイヤー名> [距離] [半径]",
		"プレイヤーの周り（既定は 80 スタッド）の8方向（視界の向きから見た前・右前・右・右後ろ・後ろ・左後ろ・左・左前）の地点が、"
			.. "半径（既定は Config の Margin）を含めて視界にかかるかを返す。高さはプレイヤーの足元",
		function(name, distanceValue, radius)
			local player = DebugCommand.findPlayer(name)
			local root = rootOf(player)
			local view, source = CameraViewService.viewOf(player)
			if not root or not view then
				return `{player.Name} のキャラクターがいない`
			end
			local distance = if distanceValue ~= nil then DebugCommand.toNumber(distanceValue, "距離") else 80
			local margin = if radius ~= nil then DebugCommand.toNumber(radius, "半径") else Config.CameraView.Margin
			-- 視界の向きを水平にしたものを前とする。真上か真下を向いていれば北を前とする
			local flat = Vector3.new(view.look.x, 0, view.look.z)
			local front = if flat.Magnitude > 1e-6 then flat.Unit else Vector3.new(0, 0, -1)
			local names = { "前", "右前", "右", "右後ろ", "後ろ", "左後ろ", "左", "左前" }
			local seen, unseen = {}, {}
			for index, label in names do
				-- 前から時計回りに 45 度ずつ回す（上から見て右回り）
				local angle = math.rad((index - 1) * 45)
				local direction = CFrame.Angles(0, -angle, 0):VectorToWorldSpace(front)
				local point = root.Position + direction * distance
				if CameraViewService.seenByAny({ player }, point, margin) then
					table.insert(seen, label)
				else
					table.insert(unseen, label)
				end
			end
			return string.format(
				"距離 %.0f・半径 %.0f で %s の視界にかかる向き %s、かからない向き %s（視界の出どころ %s）",
				distance,
				margin,
				player.Name,
				if #seen > 0 then table.concat(seen, "・") else "なし",
				if #unseen > 0 then table.concat(unseen, "・") else "なし",
				tostring(source)
			)
		end
	)
end

function CameraViewService.start()
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("ReportCameraView") :: RemoteEvent
	remote.OnServerEvent:Connect(onReport)
	Players.PlayerRemoving:Connect(function(player)
		reports[player] = nil
		rejected[player] = nil
	end)
	registerDebugCommands()
end

return CameraViewService
