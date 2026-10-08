--!strict
-- 効果音を名前で鳴らす。素材は Sounds.luau の登録表、音量と聞こえる距離は Config.luau の Sound 節から引く。
-- Roblox の API を使うので、Lune のテストからは読まない。
--
-- - 戦闘の効果音はサーバーの演出から playAt で鳴らす。その場所に Sound を置いて鳴らし、全員に聞かせる
-- - 画面の効果音はクライアントから playUi で鳴らす。本人にだけ聞こえる
-- - クライアントは起動時に preload で全部の効果音を読み込んでおく
-- - 登録表に無い名前は警告を出して鳴らさない
-- - setLogging(true) の間は、鳴らした効果音を [Sound] の行でコンソールに出す（テストプレイでは音を聞けないので、確認用）。
--   切り替えはこのモジュールの Attribute の Log に書き、サーバーから書けばクライアントにも複製される

local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Config = require("./Config")
local Sounds = require("./Sounds")

local SoundPlayer = {}

-- 鳴らし終えた Sound を消すまでに、効果音の長さへ足す秒数
local CLEANUP_MARGIN = 1
-- 鳴らした効果音をコンソールに出すかを書く、このモジュールの Attribute
local LOG_ATTRIBUTE = "Log"

-- クライアントで画面の効果音を鳴らすための Sound（名前から引く）
local localSounds: { [string]: Sound } = {}

-- 鳴らした効果音を、名前・鳴らした側・時刻（workspace:GetServerTimeNow）・場所の1行でコンソールに出す。
-- 時刻はキャラクターの Attribute の ActionStartedAt と同じ時計
local function log(name: string, place: string)
	if script:GetAttribute(LOG_ATTRIBUTE) ~= true then
		return
	end
	local side = if RunService:IsServer() then "サーバー" else "クライアント"
	print(string.format("[Sound] %s %s %.2f %s", name, side, workspace:GetServerTimeNow(), place))
end

-- 鳴らした効果音をコンソールに出すかを切り替える。サーバーから呼ぶと、サーバーとクライアントの両方が切り替わる
function SoundPlayer.setLogging(on: boolean)
	script:SetAttribute(LOG_ATTRIBUTE, on)
end

local function create(name: string, definition: Sounds.Definition): Sound
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = `rbxassetid://{definition.id}`
	sound.Volume = Config.Sound.Volume[name] or 0.5
	return sound
end

local function definitionOf(name: string): Sounds.Definition?
	local definition = Sounds.get(name)
	if not definition then
		warn(`SoundPlayer: 効果音 {name} は登録表に無い`)
	end
	return definition
end

-- 効果音 name を where（パーツか位置）で鳴らす。サーバーから呼ぶと全員に聞こえる
function SoundPlayer.playAt(name: string, where: BasePart | Vector3)
	local definition = definitionOf(name)
	if not definition then
		return
	end
	local sound = create(name, definition)
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = Config.Sound.RollOffMinDistance
	sound.RollOffMaxDistance = Config.Sound.RollOffMaxDistance
	local lifetime = definition.duration + CLEANUP_MARGIN
	local place: string
	if typeof(where) == "Vector3" then
		local attachment = Instance.new("Attachment")
		attachment.Name = "SoundAt"
		attachment.WorldPosition = where
		attachment.Parent = workspace.Terrain
		Debris:AddItem(attachment, lifetime)
		sound.Parent = attachment
		place = string.format("(%.1f, %.1f, %.1f)", where.X, where.Y, where.Z)
	else
		sound.Parent = where
		place = where:GetFullName()
	end
	sound:Play()
	Debris:AddItem(sound, lifetime)
	log(name, place)
end

local function localSound(name: string): Sound?
	local sound = localSounds[name]
	if sound then
		return sound
	end
	local definition = definitionOf(name)
	if not definition then
		return nil
	end
	local created = create(name, definition)
	created.Parent = SoundService
	localSounds[name] = created
	return created
end

-- 画面の効果音 name を本人にだけ鳴らす。クライアントから呼ぶ
function SoundPlayer.playUi(name: string)
	local sound = localSound(name)
	if sound then
		SoundService:PlayLocalSound(sound)
		log(name, "画面")
	end
end

-- 登録表の全部の効果音を読み込む。読み込めた数と全体の数を返す。クライアントの起動時に別スレッドで呼ぶ
function SoundPlayer.preload(): (number, number)
	local sounds = {}
	for _, name in Sounds.names() do
		local sound = localSound(name)
		if sound then
			table.insert(sounds, sound)
		end
	end
	ContentProvider:PreloadAsync(sounds)
	local loaded = 0
	for _, sound in sounds do
		if sound.IsLoaded then
			loaded += 1
		else
			warn(`SoundPlayer: 効果音 {sound.Name}（{sound.SoundId}）を読み込めなかった`)
		end
	end
	return loaded, #sounds
end

return SoundPlayer
