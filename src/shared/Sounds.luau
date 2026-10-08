--!strict
-- 効果音の登録表と、拠点の制圧で鳴らす場面の判断。場面の名前から、Roblox のアセット ID と配布元と使用条件を引く。
-- 鳴らすのは SoundPlayer.luau、音量は Config.luau の Sound 節にある。Roblox の API は使わない。
--
-- - M1 は仮の効果音。M2 で開発者が選び直す（#138）。差し替えはこの表の ID を直すだけで済む
-- - ガード以降の場面（#138 で足した）も仮の効果音。Creator Store の名前・説明・タグから選んだ。まだ誰も聞いていない
-- - 素材は、Roblox が Pro Sound Effects と契約して Creator Store で配布しているものだけを使う
-- - 名前（name）は Creator Store の名前のまま書く（同じ名前で ID の違う素材があるので、ID で見分ける）
-- - 拠点の制圧の音は kyotenSceneFor が、拠点の軍の変化と自分の軍から決める

local Gun = require("./Gun")

export type Definition = {
	id: number,
	-- Creator Store の素材の名前
	name: string,
	-- 長さ（秒）。読み込んだ Sound の TimeLength の値。鳴らし終えた Sound を消す時刻に使う
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
	-- プレイヤーがガードで攻撃を受けたとき（盾を剣で打つ金属音）
	Guard = proSoundEffects(9119072660, "Shield Clang As Hit Metal Sword Hubcap 1 (SFX)", 0.74),
	-- プレイヤーが緊急回避を出したとき（短い風切り）
	KinkyuKaihi = proSoundEffects(9120704940, "Whooshes Fast Wipes Quick Airy Slices 1 (SFX)", 0.35),
	-- プレイヤーがダウンしたとき（土の上に倒れる音）
	Down = proSoundEffects(9113469796, "Body Fall Dirt 4 (SFX)", 2.66),
	-- 自分の軍が拠点を制圧したとき（法螺貝）
	Seiatsu = proSoundEffects(9113890073, "Conch Shell Long Notes Steady Blows 10 (SFX)", 2.88),
	-- 自分の軍の拠点が陥落したとき（太鼓の一打）
	Kanraku = proSoundEffects(9125514393, "Drum Tom Tom Single Hits Bent Drum Head Stri (SFX)", 2.48),
	-- 秘計の発動の知らせ（銅鑼のような金属音の風切り）
	HikeiHatsudo = proSoundEffects(9114631053, "Gong Whoosh 2 (SFX)", 3.63),
	-- 画面のカーソル移動。ゲームパッドやキーの操作で、選んでいる部品が移ったとき（スイッチを押す音）
	Cursor = proSoundEffects(9119717523, "Switch Click On Or Off Toggle Button 2 (SFX)", 0.23),
}

Sounds.definitions = definitions

function Sounds.get(name: string): Definition?
	return definitions[name]
end

-- 拠点の軍が before から after に変わったときに、mine の軍の人の画面で鳴らす効果音の名前。
-- mine の軍が制圧したら Seiatsu、mine の軍の拠点が陥落したら Kanraku。
-- 軍が変わっていないときと、どちらかが軍の値でないとき（拠点を作って最初に軍が届いたときなど）は nil
function Sounds.kyotenSceneFor(before: unknown, after: unknown, mine: Gun.Gun): string?
	if not Gun.isGun(before) or not Gun.isGun(after) or before == after then
		return nil
	elseif after == mine then
		return "Seiatsu"
	elseif before == mine then
		return "Kanraku"
	end
	return nil
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
