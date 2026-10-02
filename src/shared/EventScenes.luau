--!strict
-- イベントシーンの定義表。ID と台本（カメラ、役者の出し入れと移動、台詞、待ち）を持つ。
-- ステージの前後にどのシーンを流すかは Stages.luau の eventScenes にある。
-- 長さが過ぎるか、シーンを見ている出撃メンバー全員がスキップを押すと、サーバーが次のフェーズへ進める。
-- 試験用のシーン（shiken）はストーリーのステージに登録せず、窓口の StartEventScene で流す。
-- Roblox の API は使わない。
--
-- 台本は手順を順に並べる。手順の始まる時刻は schedule が決め、全クライアントが同じ時刻に同じ手順を始める。
--
-- | 手順 | 中身 | 次の手順を待たせる秒数 |
-- |---|---|---|
-- | Camera | 目印のショット（shot）へカメラを動かす。time 秒かけて動かし、省くと切り替える | 0 |
-- | Appear | 役者（yakusha）を目印の立ち位置に出す | 0 |
-- | Exit | 役者を下げる | 0 |
-- | Move | 役者を、立ち位置から見て右へ x・前へ z スタッドの位置へ time 秒で歩かせる | 0 |
-- | Serifu | 会話窓に話者（speaker）・表情（hyojo）・文（text）を出す | 文を送るまで（Serifu.lineTime） |
-- | Wait | 待つ | time |
--
-- - 役者の名前は、NPC はキャラクター ID、出撃したプレイヤーは出撃した順に Player1〜Player4（ADR 0006 の目印の名前）
-- - 位置とカメラの向きは、区画の目印（<区画>.Mejirushi.EventScene.<シーン ID> の Camera と Yakusha）から引く
-- - 台本に出る役者のうち出撃した人数より後ろのプレイヤーは出さず、その台詞は会話窓に出さない

local RemoteSchema = require("./RemoteSchema")
local Serifu = require("./Serifu")

export type StepKind = "Camera" | "Appear" | "Exit" | "Move" | "Serifu" | "Wait"

export type Step = {
	kind: StepKind,
	-- Camera のショットの名前（目印の Camera の下のパーツの名前）
	shot: string?,
	-- Appear・Exit・Move の役者の名前
	yakusha: string?,
	-- Move で歩く先。役者の立ち位置から見て右へ x、前へ z スタッド
	x: number?,
	z: number?,
	-- Camera と Move にかける秒数、Wait で待つ秒数
	time: number?,
	-- Serifu の話者（役者の名前）・表情・文
	speaker: string?,
	hyojo: RemoteSchema.Hyojo?,
	text: string?,
}

export type EventScene = {
	id: string,
	-- 長さ（秒）。省くと台本の長さ（lengthOf）
	duration: number?,
	-- 試験用のシーンか
	shiken: boolean?,
	-- 台本。無ければ何も映さず、長さだけ流す
	steps: { Step }?,
}

-- 始める時刻（シーンの開始からの秒）を付けた手順
export type Scheduled = {
	step: Step,
	at: number,
}

local EventScenes = {}

-- 出撃したプレイヤーの役者の名前の頭
local PLAYER_PREFIX = "Player"
-- 台本の無いシーンの長さ（秒）
local DEFAULT_DURATION = 5

EventScenes.stepKinds = { "Camera", "Appear", "Exit", "Move", "Serifu", "Wait" } :: { StepKind }

local definitions: { [string]: EventScene } = {
	-- 試験用のシーン。試験用ステージ（Test）の区画で、カメラの切り替えと移動、役者の出し入れと移動、
	-- NPC と出撃したプレイヤーの台詞を確かめる。目印の位置は Haichi.luau の試験用ステージにある
	Shiken = {
		id = "Shiken",
		shiken = true,
		steps = {
			{ kind = "Camera", shot = "Zenkei" },
			{ kind = "Appear", yakusha = "Hayate" },
			{ kind = "Appear", yakusha = "Player1" },
			{ kind = "Appear", yakusha = "ShikenJonin1" },
			{ kind = "Wait", time = 1.5 },
			{ kind = "Camera", shot = "Hayate", time = 1.5 },
			{
				kind = "Serifu",
				speaker = "Hayate",
				hyojo = "Tsujo",
				text = "試験の寸劇を始める。カメラと役者の動きを確かめる。",
			},
			{ kind = "Camera", shot = "Teki", time = 1 },
			{ kind = "Move", yakusha = "ShikenJonin1", x = 0, z = 12, time = 2.5 },
			{ kind = "Wait", time = 2.5 },
			{
				kind = "Serifu",
				speaker = "ShikenJonin1",
				hyojo = "Ikari",
				text = "風魔の試験の上忍、参る！",
			},
			{ kind = "Camera", shot = "Player", time = 1 },
			{
				kind = "Serifu",
				speaker = "Player1",
				hyojo = "Tsujo",
				text = "出撃した一人目も役者になる。",
			},
			{ kind = "Exit", yakusha = "ShikenJonin1" },
			{ kind = "Camera", shot = "Zenkei", time = 1.5 },
			{ kind = "Wait", time = 2 },
		},
	},
}

EventScenes.definitions = definitions

-- シーンの定義。ID が nil か定義が無ければ nil
function EventScenes.get(id: string?): EventScene?
	if id == nil then
		return nil
	end
	return definitions[id]
end

-- 出撃した順番（1から）のプレイヤーの役者の名前
function EventScenes.playerYakusha(index: number): string
	return `{PLAYER_PREFIX}{index}`
end

-- プレイヤーの役者の名前なら出撃した順番、NPC の名前なら nil
function EventScenes.playerIndexOf(name: string): number?
	local digits = string.match(name, `^{PLAYER_PREFIX}([1-9]%d*)$`)
	return if digits then tonumber(digits) else nil
end

-- 手順が始まってから、その手順の動きや台詞が終わるまでの秒数
local function spanOf(step: Step): number
	if step.kind == "Serifu" then
		return Serifu.lineTime(step.text or "")
	elseif step.kind == "Wait" or step.kind == "Camera" or step.kind == "Move" then
		return math.max(step.time or 0, 0)
	end
	return 0
end

-- 手順が次の手順を待たせる秒数
local function holdOf(step: Step): number
	if step.kind == "Serifu" or step.kind == "Wait" then
		return spanOf(step)
	end
	return 0
end

-- 台本の手順を、始める時刻（シーンの開始からの秒）とともに順に並べる
function EventScenes.schedule(scene: EventScene): { Scheduled }
	local result: { Scheduled } = {}
	local at = 0
	for _, step in scene.steps or {} do
		table.insert(result, { step = step, at = at })
		at += holdOf(step)
	end
	return result
end

-- 台本が終わるまでの秒数。どの手順の動きと台詞も終わる時刻
function EventScenes.lengthOf(scene: EventScene): number
	local length = 0
	for _, item in EventScenes.schedule(scene) do
		length = math.max(length, item.at + spanOf(item.step))
	end
	return length
end

-- サーバーがシーンを流す長さ（秒）。duration があればそれ、無ければ台本の長さ（台本も無ければ既定の秒数）
function EventScenes.durationOf(scene: EventScene): number
	if scene.duration then
		return scene.duration
	end
	if scene.steps then
		return EventScenes.lengthOf(scene)
	end
	return DEFAULT_DURATION
end

-- 台本で姿を出す役者の名前（初めて出る順）。台詞だけの話者は入れない
function EventScenes.yakushaOf(scene: EventScene): { string }
	local result = {}
	for _, step in scene.steps or {} do
		local name = step.yakusha
		if name and not table.find(result, name) then
			table.insert(result, name)
		end
	end
	return result
end

-- 台本が使うカメラのショットの名前（初めて使う順）
function EventScenes.shotsOf(scene: EventScene): { string }
	local result = {}
	for _, step in scene.steps or {} do
		if step.kind == "Camera" and step.shot and not table.find(result, step.shot) then
			table.insert(result, step.shot)
		end
	end
	return result
end

-- 台本の誤りを並べる。誤りが無ければ空
function EventScenes.check(scene: EventScene): { string }
	local problems = {}
	local appeared: { [string]: boolean } = {}
	for index, step in scene.steps or {} do
		local where = `{scene.id} の {index} 番目の {step.kind}`
		if not table.find(EventScenes.stepKinds, step.kind) then
			table.insert(problems, `{where} は手順の種類に無い`)
		elseif step.kind == "Camera" then
			if not step.shot then
				table.insert(problems, `{where} にショットが無い`)
			end
		elseif step.kind == "Appear" or step.kind == "Exit" or step.kind == "Move" then
			local name = step.yakusha
			if not name then
				table.insert(problems, `{where} に役者が無い`)
			elseif step.kind == "Appear" then
				appeared[name] = true
			elseif not appeared[name] then
				table.insert(problems, `{where} の役者 {name} は出ていない`)
			elseif step.kind == "Exit" then
				appeared[name] = nil
			end
			if step.kind == "Move" and (step.x == nil or step.z == nil or (step.time or 0) <= 0) then
				table.insert(problems, `{where} に歩く先か秒数が無い`)
			end
		elseif step.kind == "Serifu" then
			if not step.speaker or not step.text or #step.text == 0 then
				table.insert(problems, `{where} に話者か文が無い`)
			end
			if not table.find(RemoteSchema.hyojo, step.hyojo :: any) then
				table.insert(problems, `{where} の表情 {tostring(step.hyojo)} は無い`)
			end
		elseif step.kind == "Wait" then
			if (step.time or 0) <= 0 then
				table.insert(problems, `{where} に秒数が無い`)
			end
		end
	end
	return problems
end

return EventScenes
