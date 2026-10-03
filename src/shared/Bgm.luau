--!strict
-- BGM の登録表と、流す場面の判断。場面の名前から、Roblox のアセット ID と配布元と使用条件を引く。
-- 流すのはクライアントの BgmController、音量とフェードの長さは Config.luau の Bgm 節にある。
-- Roblox の API は使わない。
--
-- - M1 は仮の曲。M2 で開発者が選び直す（#138）。差し替えはこの表の ID を直すだけで済む
-- - 曲は、Roblox が APM Music と契約して Creator Store で配布しているものだけを使う
-- - 曲は Creator Store の題名・アルバム・説明・タグから選んだ。まだ誰も聞いていない
-- - 名前・アーティスト・アルバム・長さは、Creator Store の素材の詳細のまま書く
-- - 流す場面は sceneFor が、PartyState のフェーズと本人が待機中かと StageResult の勝敗から決める

local RemoteSchema = require("./RemoteSchema")

-- BGM を流す場面
export type Scene = "Lobby" | "EventScene" | "Battle" | "Victory" | "Defeat"

export type Definition = {
	id: number,
	-- Creator Store の素材の名前
	name: string,
	-- Creator Store の Artist（作曲者か演奏者の名義）
	artist: string,
	-- Creator Store の Album
	album: string,
	-- 長さ（秒）。Creator Store の素材の詳細の値
	duration: number,
	-- 配布元
	source: string,
	-- 使用条件
	license: string,
}

local Bgm = {}

-- 場面の一覧
Bgm.scenes = { "Lobby", "EventScene", "Battle", "Victory", "Defeat" } :: { Scene }

local APM_MUSIC = "APM Music（Roblox の Creator Store、作成者 APMOfficial）"
local APM_MUSIC_LICENSE =
	"Roblox が APM Music と契約して配布する曲。Roblox の体験の中でだけ無料で使える"

local function apmMusic(id: number, name: string, artist: string, album: string, duration: number): Definition
	return {
		id = id,
		name = name,
		artist = artist,
		album = album,
		duration = duration,
		source = APM_MUSIC,
		license = APM_MUSIC_LICENSE,
	}
end

local definitions: { [string]: Definition } = {
	-- ロビー。箏の曲（Creator Store のタグは Zither）
	Lobby = apmMusic(1845854732, "Plum Blossoms", "Tadao Sawai", "Authentic Japan", 165),
	-- イベントシーン。笛の曲（タグは Flute）
	EventScene = apmMusic(1845854778, "Gathering Clouds", "Seizan Ishigaki", "Authentic Japan", 207),
	-- 戦闘。太鼓の合奏（Creator Store の説明から）
	Battle = apmMusic(9038213241, "Gekido", "Seventh Sense", "Taikoso", 139),
	-- 勝利。戦闘と同じ太鼓のアルバムの曲
	Victory = apmMusic(9038213244, "Shori", "Seventh Sense", "Taikoso", 141),
	-- 敗北。尺八のアルバムの曲
	Defeat = apmMusic(1838864669, "Kioku", "Yoofu", "Japanese Shakuhachi", 83),
}

Bgm.definitions = definitions

function Bgm.get(scene: string): Definition?
	return definitions[scene]
end

-- 本人の画面で流す場面を返す。nil なら今の曲を続ける。
-- phase は PartyState のフェーズ（届く前は nil）。
-- waiting は本人がロビーで待っているか（出撃中に入った人と、パーティーにいない人）。
-- victory は最後に届いた StageResult の勝敗（届いていなければ nil）。
-- サーバーはリザルトのフェーズの PartyState を StageResult より先に送るので、
-- 勝敗が届くまでは前の曲（終了のイベントシーンか戦闘の曲）を続ける
function Bgm.sceneFor(phase: RemoteSchema.Phase?, waiting: boolean, victory: boolean?): Scene?
	if waiting or phase == nil or phase == "Lobby" then
		return "Lobby"
	elseif phase == "EventScene" then
		return "EventScene"
	elseif phase == "Battle" then
		return "Battle"
	elseif victory == nil then
		return nil
	end
	return if victory then "Victory" else "Defeat"
end

return Bgm
