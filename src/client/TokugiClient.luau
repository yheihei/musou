--!strict
-- サーバーから届く本人の特技の記録（Remotes.TokugiState）の写しを持つ。画面はここから読み、変化を購読する。
-- 入室直後の記録を取りこぼさないよう、クライアントの起動の最初の方で start を呼ぶ。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tokugi = require(ReplicatedStorage.Shared.Tokugi)
local PartyClient = require(script.Parent.PartyClient)

local TokugiClient = {}

local state: Tokugi.State? = nil
local changed = Instance.new("BindableEvent")

-- TokugiState が届くたびに発火する
TokugiClient.changed = changed.Event

-- 最後に届いた記録。まだ届いていなければ nil
function TokugiClient.get(): Tokugi.State?
	return state
end

-- キャラクターの記録。記録がまだ届いていなければ、巻物も特技も無い記録
function TokugiClient.recordOf(characterId: string): Tokugi.CharacterRecord
	return Tokugi.recordOf(if state then state.data else Tokugi.new(), characterId)
end

-- 特技ツリーの画面に出すキャラクター（Tokugi.shownCharacter）。
-- 選んでいるキャラクター、無ければ今のキャラクター（Player の Attribute の CharacterId。最後に出撃したキャラクター）
function TokugiClient.shownCharacter(): string
	local me = PartyClient.me()
	local current = Players.LocalPlayer:GetAttribute("CharacterId")
	return Tokugi.shownCharacter(if me then me.character else nil, if type(current) == "string" then current else nil)
end

function TokugiClient.start()
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("TokugiState") :: RemoteEvent
	remote.OnClientEvent:Connect(function(value: unknown)
		local received = Tokugi.normalizeState(value)
		if not received then
			warn("TokugiClient: 特技の記録の形が正しくない")
			return
		end
		state = received
		changed:Fire(received)
	end)
end

return TokugiClient
