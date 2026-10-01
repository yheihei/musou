--!strict
-- 効果音の登録表。場面の名前から、Roblox のアセット ID と配布元と使用条件を引く。
-- 鳴らすのは SoundPlayer.luau、音量は Config.luau の Sound 節にある。Roblox の API は使わない。
--
-- - M1 は仮の効果音。M2 で開発者が選び直す（#138）。差し替えはこの表の ID を直すだけで済む
-- - 素材は、Roblox が Pro Sound Effects と契約して Creator Store で配布しているものだけを使う
-- - 名前（name）は Creator Store の名前のまま書く（同じ名前で ID の違う素材があるので、ID で見分ける）

export type Definition = {
	id: number,
	-- Creator Store の素材の名前
	name: string,
	-- 長さ（秒）。読み込んだ Sound の TimeLength の値
	duration: number,
	-- 配布元
	source: string,
	-- 使用条件
	license: string,
}

local Sounds = {}

local PRO_SOUND_EFFECTS = "Pro Sound Effects（Roblox の Creator Store、作成者 ProSoundEffects）"
local PRO_SOUND_EFFECTS_LICENSE =
	"Roblox が Pro Sound Effects と契約して配布する効果音。Roblox の体験の中でだけ無料で使える"

local function proSoundEffects(id: number, name: string, duration: number): Definition
	return {
		id = id,
		name = name,
		duration = duration,
		source = PRO_SOUND_EFFECTS,
		license = PRO_SOUND_EFFECTS_LICENSE,
	}
end

local definitions: { [string]: Definition } = {
	-- 攻撃の空振り（通常攻撃とジャンプ攻撃を出したとき）
	Swing = proSoundEffects(9126013776, "Swish Med High End Sharp Swords Fast Punches (SFX)", 0.44),
	-- 攻撃が当たったとき
	Hit = proSoundEffects(9113520887, "Body Hit With Rubber Glove 7 (SFX)", 0.45),
	-- チャージ攻撃を出したとき
	ChargeKogeki = proSoundEffects(9120728815, "Whoosh Heavy Punches 1 (SFX)", 0.67),
	-- 奥義を出したとき
	Ougi = proSoundEffects(9117984812, "Pyro Fire Ball Burst 1 (SFX)", 3),
	-- プレイヤーが攻撃を受けたとき
	Hurt = proSoundEffects(9114739086, "Gut Hit 7 (SFX)", 0.48),
	-- 画面の決定
	Confirm = proSoundEffects(9126035527, "Switch Tones Single Percussive Hits Hard Att (SFX)", 0.36),
	-- 画面の取り消し
	Cancel = proSoundEffects(9119976843, "Temple Blocks Impact Single Soft Strikes 11 (SFX)", 0.74),
}

Sounds.definitions = definitions

function Sounds.get(name: string): Definition?
	return definitions[name]
end

-- 登録した効果音の名前を名前の順に返す
function Sounds.names(): { string }
	local names = {}
	for name in definitions do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

return Sounds
