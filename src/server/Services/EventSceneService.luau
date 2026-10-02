--!strict
-- イベントシーンの役者とカメラの位置を区画の目印から読み、PlayEventScene に添えてクライアントへ渡す（ADR 0006）。
-- 役者の見た目の雛形（Appearance の仮の見た目のモデル）を ReplicatedStorage.Yakusha に置き、クライアントが写して動かす。
-- 台本は ReplicatedStorage.Shared.EventScenes、再生はクライアントの EventSceneController が行う。
--
-- - 目印は <区画>.Mejirushi.EventScene.<シーン ID> の Camera（ショットの名前）と Yakusha（役者の名前）のパーツ
-- - 試験用ステージは目印の位置をコードに持ち（Haichi.luau）、シーンの目印が無ければ流す前に作る
-- - 目印の無い役者は、プレイヤーは出撃地点に、NPC は1番の出撃地点の前に並べる。
--   目印の無いショットは、1番の出撃地点の後ろの上から前を見る位置にする（どちらも警告を出す）
-- - 出撃したプレイヤーの役者（Player1〜Player4）は、出撃した順のメンバーが今使っているキャラクターを演じる
-- - 雛形は起動時に全キャラクターの分を作る。台本に出る NPC の雛形が無ければ流す前に作る

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Appearance = require(ReplicatedStorage.Shared.Appearance)
local Characters = require(ReplicatedStorage.Shared.Characters)
local EventScenes = require(ReplicatedStorage.Shared.EventScenes)
local Haichi = require(ReplicatedStorage.Shared.Haichi)
local Mejirushi = require(ReplicatedStorage.Shared.Mejirushi)
local Stages = require(ReplicatedStorage.Shared.Stages)
local HaichiService = require(script.Parent.HaichiService)
local KukakuService = require(script.Parent.KukakuService)
local PlayerService = require(script.Parent.PlayerService)
local StageService = require(script.Parent.StageService)

-- PlayEventScene に添える中身
export type Setting = {
	-- 再生を始める時刻（workspace:GetServerTimeNow の時刻）
	startedAt: number,
	-- ショットの名前から引くカメラの位置と向き
	camera: { [string]: CFrame },
	-- 役者の名前から引く立ち位置と向き
	yakusha: { [string]: CFrame },
	-- 役者と話者の名前から引く、演じるキャラクター ID。出撃した人数より後ろのプレイヤーの役者は入れない
	characters: { [string]: string },
}

local EventSceneService = {}

-- 役者の雛形を置くフォルダ（ReplicatedStorage の下）の名前
EventSceneService.FOLDER = "Yakusha"

-- 目印の無い NPC を並べる、1番の出撃地点からの前の距離と横の間隔（スタッド）
local FALLBACK_FRONT = 12
local FALLBACK_SPACING = 6
-- 目印の無いショットの、1番の出撃地点からの後ろの距離と高さ、見る先の前の距離と高さ（スタッド）
local FALLBACK_CAMERA_BACK = 16
local FALLBACK_CAMERA_UP = 8
local FALLBACK_LOOK_FRONT = 10
local FALLBACK_LOOK_UP = 3

local folder: Folder

-- 役者の雛形を返す。無ければ作る
local function ensureTemplate(characterId: string): Model?
	local existing = folder:FindFirstChild(characterId)
	if existing and existing:IsA("Model") then
		return existing
	end
	if not Characters.get(characterId) then
		warn(`EventSceneService: 役者 {characterId} はキャラクターの定義表に無い`)
		return nil
	end
	local ok, model = pcall(Appearance.createModel, characterId)
	if not ok then
		warn(`EventSceneService: 役者 {characterId} の雛形を作れなかった: {model}`)
		return nil
	end
	if folder:FindFirstChild(characterId) then
		-- 作っている間に別のスレッドが作った
		model:Destroy()
		return folder:FindFirstChild(characterId) :: Model
	end
	model.Parent = folder
	return model
end

-- 目印のフォルダの下のパーツの CFrame を名前で引く
local function readMarkers(container: Instance?): { [string]: CFrame }
	local result: { [string]: CFrame } = {}
	for _, child in if container then container:GetChildren() else {} do
		if child:IsA("BasePart") then
			result[child.Name] = child.CFrame
		end
	end
	return result
end

-- シーンの目印のフォルダ。試験用ステージで無ければ作る
local function sceneFolderOf(stage: Stages.Stage, sceneId: string): Instance?
	local function find(): Instance?
		local mejirushi = KukakuService.mejirushiOf(stage.kukaku)
		local eventScene = mejirushi and mejirushi:FindFirstChild(Mejirushi.EVENT_SCENE)
		return eventScene and eventScene:FindFirstChild(sceneId)
	end
	local found = find()
	if found then
		return found
	end
	local haichi = Haichi.get(stage.id)
	local shiken = haichi and haichi.shikenMejirushi
	if shiken and shiken.eventScene and shiken.eventScene[sceneId] then
		HaichiService.placeShikenMejirushi(stage.id)
		return find()
	end
	return nil
end

-- PlayEventScene に添える中身を作る。members は出撃して残っているメンバー（出撃した順）
local function settingFor(stageId: string, sceneId: string, members: { Player }): Setting?
	local stage = Stages.get(stageId)
	local scene = EventScenes.get(sceneId)
	if not stage or not scene then
		return nil
	end
	local sceneFolder = sceneFolderOf(stage, sceneId)
	local camera = readMarkers(sceneFolder and sceneFolder:FindFirstChild(Mejirushi.CAMERA))
	local yakusha = readMarkers(sceneFolder and sceneFolder:FindFirstChild(Mejirushi.YAKUSHA))
	local chiten: { [number]: CFrame } = {}
	for _, point in KukakuService.shutsugekiChiten(stage.kukaku) do
		chiten[point.number] = point.cframe
	end
	local base = chiten[1] or CFrame.new()
	local where = `区画 {stage.kukaku} のイベントシーン {sceneId} に`

	local characters: { [string]: string } = {}
	local npcIndex = 0
	local names = EventScenes.yakushaOf(scene)
	for _, name in names do
		local playerIndex = EventScenes.playerIndexOf(name)
		if playerIndex then
			local member = members[playerIndex]
			if member then
				characters[name] = PlayerService.getCharacterId(member)
			end
		else
			characters[name] = name
		end
		if not yakusha[name] and characters[name] then
			warn(`EventSceneService: {where}役者 {name} の目印が無いので、出撃地点の近くに出す`)
			if playerIndex and chiten[playerIndex] then
				yakusha[name] = chiten[playerIndex]
			else
				npcIndex += 1
				local offset = (npcIndex - 1) * FALLBACK_SPACING
				-- 1番の出撃地点の前に、出撃地点の方を向けて並べる
				yakusha[name] = base * CFrame.new(offset, 0, -FALLBACK_FRONT) * CFrame.Angles(0, math.pi, 0)
			end
		end
	end
	-- 姿を出さずに台詞だけ言うプレイヤーの役者も、演じるキャラクターを決める
	for _, step in scene.steps or {} do
		local speaker = step.speaker
		local playerIndex = if speaker then EventScenes.playerIndexOf(speaker) else nil
		local member = if playerIndex then members[playerIndex] else nil
		if speaker and member and not characters[speaker] then
			characters[speaker] = PlayerService.getCharacterId(member)
		end
	end
	for _, shot in EventScenes.shotsOf(scene) do
		if not camera[shot] then
			warn(
				`EventSceneService: {where}カメラ {shot} の目印が無いので、出撃地点の後ろから映す`
			)
			local eye = base * Vector3.new(0, FALLBACK_CAMERA_UP, FALLBACK_CAMERA_BACK)
			local look = base * Vector3.new(0, FALLBACK_LOOK_UP, -FALLBACK_LOOK_FRONT)
			camera[shot] = CFrame.lookAt(eye, look)
		end
	end
	for _, characterId in characters do
		if not folder:FindFirstChild(characterId) then
			task.spawn(ensureTemplate, characterId)
		end
	end
	return {
		startedAt = workspace:GetServerTimeNow(),
		camera = camera,
		yakusha = yakusha,
		characters = characters,
	}
end

function EventSceneService.start()
	local created = Instance.new("Folder")
	created.Name = EventSceneService.FOLDER
	created.Parent = ReplicatedStorage
	folder = created

	StageService.setSceneSettingProvider(settingFor)
	-- 雛形は作るのに時間がかかるので、起動時に全キャラクターの分を作っておく
	task.spawn(function()
		local ids = {}
		for id in Characters.definitions do
			table.insert(ids, id)
		end
		table.sort(ids)
		for _, id in ids do
			ensureTemplate(id)
		end
	end)
end

return EventSceneService
