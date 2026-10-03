--!strict
-- 場面ごとの BGM を本人の画面で流す。場面は ReplicatedStorage.Shared.Bgm の sceneFor が、
-- PartyState のフェーズと本人が待機中かと、最後に届いた StageResult の勝敗から決める。
-- 曲は同じモジュールの登録表、音量とフェードの長さは Config.luau の Bgm 節にある。
--
-- - 場面ごとにループする Sound を1つずつ作り、SoundService の Bgm フォルダに置く
-- - 起動時に別スレッドで全部の曲を読み込み、読み込めなかった曲ごとに警告を出す
-- - 場面が変わったら、前の曲を音量 0 まで下げて止め、次の曲を音量 0 から上げる。両方を同時に進める
-- - 切り替えの途中でまた変わったら、それぞれの曲を今の音量から下げるか上げる
-- - PartyState が届く前と、待機中の人（出撃中に入った人）はロビーの曲
-- - サーバーはリザルトのフェーズの PartyState を StageResult より先に送る。勝敗が届くまでは前の曲を続ける
-- - 覚えた勝敗は、PartyState が届いたときに最新のフェーズがリザルトでなければ忘れる
-- - 流している場面を Bgm フォルダの Attribute の Scene に書く（テストプレイでの確認用）

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Bgm = require(ReplicatedStorage.Shared.Bgm)
local Config = require(ReplicatedStorage.Shared.Config)
local PartyClient = require(script.Parent.Parent.PartyClient)

local BgmController = {}

-- 流している場面を書く、Bgm フォルダの Attribute
local SCENE_ATTRIBUTE = "Scene"

-- 場面1つぶんの曲
type Track = {
	sound: Sound,
	-- フェードで向かっている音量
	target: number,
	tween: Tween?,
}

local folder: Folder
local tracks: { [Bgm.Scene]: Track } = {}
-- 流している場面。まだ決めていなければ nil
local current: Bgm.Scene? = nil
-- 最後に届いた StageResult の勝敗。届いていないか忘れた後は nil
local victory: boolean? = nil

-- track の音量を FadeTime 秒かけて volume にする。0 まで下げきったら止める
local function fade(track: Track, volume: number)
	if track.target == volume then
		return
	end
	track.target = volume
	local previous = track.tween
	if previous then
		previous:Cancel()
	end
	local tween = TweenService:Create(
		track.sound,
		TweenInfo.new(Config.Bgm.FadeTime, Enum.EasingStyle.Linear),
		{ Volume = volume }
	)
	track.tween = tween
	tween.Completed:Connect(function(state: Enum.PlaybackState)
		if track.tween ~= tween then
			return
		end
		track.tween = nil
		if state == Enum.PlaybackState.Completed and volume == 0 then
			track.sound:Stop()
		end
	end)
	tween:Play()
end

-- scene の曲に切り替える。止まっていれば頭から流し、ほかの曲は下げて止める
local function switchTo(scene: Bgm.Scene)
	if scene == current then
		return
	end
	current = scene
	folder:SetAttribute(SCENE_ATTRIBUTE, scene)
	for name, track in tracks do
		if name == scene then
			if not track.sound.Playing then
				track.sound.Volume = 0
				track.sound:Play()
			end
			fade(track, Config.Bgm.Volume[name])
		else
			fade(track, 0)
		end
	end
end

local function refresh()
	local state = PartyClient.get()
	local me = PartyClient.me()
	-- PartyState が届く前とパーティーにいないときも、待機中の人と同じくロビーの曲にする
	local waiting = me == nil or me.waiting
	local scene = Bgm.sceneFor(if state then state.phase else nil, waiting, victory)
	if scene then
		switchTo(scene)
	end
end

-- 全部の曲を読み込み、読み込めなかった曲ごとに警告を出す
local function preload()
	local sounds = {}
	for _, scene in Bgm.scenes do
		local track = tracks[scene]
		if track then
			table.insert(sounds, track.sound)
		end
	end
	ContentProvider:PreloadAsync(sounds)
	for _, sound in sounds do
		if not sound.IsLoaded then
			warn(`BgmController: 曲 {sound.Name}（{sound.SoundId}）を読み込めなかった`)
		end
	end
end

function BgmController.start()
	folder = Instance.new("Folder")
	folder.Name = "Bgm"
	for _, scene in Bgm.scenes do
		local definition = Bgm.get(scene)
		if definition then
			local sound = Instance.new("Sound")
			sound.Name = scene
			sound.SoundId = `rbxassetid://{definition.id}`
			sound.Looped = true
			sound.Volume = 0
			sound.Parent = folder
			tracks[scene] = { sound = sound, target = 0, tween = nil }
		end
	end
	folder.Parent = SoundService
	task.spawn(preload)

	local resultRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("StageResult") :: RemoteEvent
	resultRemote.OnClientEvent:Connect(function(result: unknown)
		local outcome = if type(result) == "table" then (result :: any).victory else nil
		if type(outcome) ~= "boolean" then
			warn("BgmController: StageResult に勝敗が無い")
			return
		end
		victory = outcome
		refresh()
	end)
	-- 渡される PartyState は、続けて届いたときに最新でないことがあるので、最新の写しで決める
	PartyClient.changed:Connect(function()
		local state = PartyClient.get()
		if not state or state.phase ~= "Result" then
			victory = nil
		end
		refresh()
	end)
	refresh()
end

return BgmController
