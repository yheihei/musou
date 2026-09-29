--!strict
-- サーバーから届く PartyState の写しを持つ。画面はここから読み、変化を購読する。
-- 入室直後の PartyState を取りこぼさないよう、クライアントの起動の最初に start を呼ぶ。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteSchema = require(ReplicatedStorage.Shared.RemoteSchema)

local PartyClient = {}

local state: RemoteSchema.PartyState? = nil
local changed = Instance.new("BindableEvent")

-- PartyState が届くたびに発火する
PartyClient.changed = changed.Event

-- 最後に届いた PartyState。まだ届いていなければ nil
function PartyClient.get(): RemoteSchema.PartyState?
	return state
end

-- 本人のメンバーの写し。まだ届いていないか、パーティーにいなければ nil
function PartyClient.me(): RemoteSchema.MemberState?
	if not state then
		return nil
	end
	for _, member in state.members do
		if member.userId == Players.LocalPlayer.UserId then
			return member
		end
	end
	return nil
end

function PartyClient.start()
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PartyState") :: RemoteEvent
	remote.OnClientEvent:Connect(function(next: RemoteSchema.PartyState)
		state = next
		changed:Fire(next)
	end)
end

return PartyClient
