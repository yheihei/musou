--!strict
-- 自分のキャラクターに、行動に合わせたモーションを再生する。
-- サーバーは行動を始めるたびにキャラクターの Attribute（Action・ActionStep・ActionDuration・ActionStartedAt）を書く。
-- その変化を見て ReplicatedStorage.Shared.Motions からモーションを引き、行動の長さに合わせた速さで再生する。
--
-- - キャラクターの持ち主はクライアントなので、ここで再生したモーションはサーバーとほかのクライアントへ複製される
-- - 攻撃判定の時刻と前進量はサーバーが Config.luau の値で決める。モーションは見た目だけで、判定は変わらない
-- - ID が 0 の行動は再生しない。前の行動のモーションは止め、待機と移動のモーションに戻す
-- - 行動のモーションは、待機と移動（Animate の Idle・Movement）より上の優先度で重ねる
-- - サーバーが行動を始めてから届くまでの遅れの分だけ、モーションを進めた位置から再生する

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Characters = require(ReplicatedStorage.Shared.Characters)
local Motions = require(ReplicatedStorage.Shared.Motions)

local MotionController = {}

-- モーションを切り替えるときに重ねて移る秒数
local FADE_TIME = 0.1

local PRIORITIES: { [Motions.Priority]: Enum.AnimationPriority } = {
	Action = Enum.AnimationPriority.Action,
	Action2 = Enum.AnimationPriority.Action2,
}

type Rig = {
	character: Model,
	animator: Animator,
	-- モーションの ID から引く、読み込んだトラック
	tracks: { [number]: AnimationTrack },
	-- 再生中の行動のトラック
	current: AnimationTrack?,
}

-- キャラクターの ID。見た目を当てた後はキャラクターの Attribute に、その前は Player の Attribute にある
local function characterIdOf(character: Model): string
	for _, source in { character, Players.LocalPlayer } :: { Instance } do
		local id = source:GetAttribute("CharacterId")
		if type(id) == "string" and Characters.get(id) then
			return id
		end
	end
	return Characters.DEFAULT_ID
end

local function trackOf(rig: Rig, motionId: number): AnimationTrack
	local track = rig.tracks[motionId]
	if track then
		return track
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = `rbxassetid://{motionId}`
	local loaded = rig.animator:LoadAnimation(animation)
	rig.tracks[motionId] = loaded
	return loaded
end

local function numberAttribute(instance: Instance, name: string): number?
	local value = instance:GetAttribute(name)
	return if type(value) == "number" then value else nil
end

-- 行動の長さに合わせて速さを決め、行動を始めてからの経過の分だけ進める
local function fit(track: AnimationTrack, duration: number?, startedAt: number?)
	local speed = Motions.playbackSpeed(track.Length, duration)
	track:AdjustSpeed(speed)
	if track.Length > 0 and not track.Looped and startedAt then
		local elapsed = workspace:GetServerTimeNow() - startedAt
		if elapsed > 0 then
			track.TimePosition = math.min(elapsed * speed, track.Length)
		end
	end
end

-- キャラクターの今の行動のモーションを再生する。待機に戻ったか、モーションの無い行動なら止める
local function play(rig: Rig)
	local character = rig.character
	local previous = rig.current
	rig.current = nil
	local action = character:GetAttribute("Action")
	local motionId = 0
	if type(action) == "string" then
		motionId = Motions.forAction(characterIdOf(character), action, numberAttribute(character, "ActionStep"))
	end
	if previous then
		previous:Stop(FADE_TIME)
	end
	if type(action) ~= "string" or motionId <= 0 then
		return
	end

	local track = trackOf(rig, motionId)
	local duration = numberAttribute(character, "ActionDuration")
	local startedAt = numberAttribute(character, "ActionStartedAt")
	track.Priority = PRIORITIES[Motions.priorityOf(action)]
	track.Looped = Motions.isLooped(action)
	track:Play(FADE_TIME)
	fit(track, duration, startedAt)
	rig.current = track
	-- まだ読み込めておらず長さが分からなければ、分かった時点で合わせ直す
	if track.Length <= 0 then
		track:GetPropertyChangedSignal("Length"):Once(function()
			if rig.current == track then
				fit(track, duration, startedAt)
			end
		end)
	end
end

local function watch(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	local animator = humanoid and humanoid:WaitForChild("Animator", 10) :: Animator?
	if not animator then
		return
	end
	local rig: Rig = { character = character, animator = animator, tracks = {}, current = nil }
	-- 待機に戻ったとき（Action が nil になったとき）も ActionStartedAt は変わる
	character:GetAttributeChangedSignal("ActionStartedAt"):Connect(function()
		play(rig)
	end)
	-- 使うモーションを先に読み込み、最初の再生から長さが分かるようにする
	for _, motionId in Motions.idsOf(characterIdOf(character)) do
		trackOf(rig, motionId)
	end
	if character:GetAttribute("Action") ~= nil then
		play(rig)
	end
end

function MotionController.start()
	local player = Players.LocalPlayer
	player.CharacterAdded:Connect(watch)
	if player.Character then
		task.spawn(watch, player.Character)
	end
end

return MotionController
