--!strict
-- サーバーから届く本人の秘計の熟練度の記録（Remotes.JukurendoState）の写しを持つ。画面はここから読み、変化を購読する。
-- 入室直後の記録を取りこぼさないよう、クライアントの起動の最初の方で start を呼ぶ。

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Jukurendo = require(ReplicatedStorage.Shared.Jukurendo)

local JukurendoClient = {}

local state: Jukurendo.State? = nil
local changed = Instance.new("BindableEvent")

-- JukurendoState が届くたびに発火する
JukurendoClient.changed = changed.Event

-- 最後に届いた記録。まだ届いていなければ nil
function JukurendoClient.get(): Jukurendo.State?
	return state
end

function JukurendoClient.start()
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("JukurendoState") :: RemoteEvent
	remote.OnClientEvent:Connect(function(value: unknown)
		local received = Jukurendo.normalizeState(value)
		if not received then
			warn("JukurendoClient: 熟練度の記録の形が正しくない")
			return
		end
		state = received
		changed:Fire(received)
	end)
end

return JukurendoClient
