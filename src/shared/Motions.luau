--!strict
-- モーションの一覧。待機と移動は Roblox 公式の Ninja アニメーションパッケージを使い、
-- 攻撃・ガード・被弾・奥義のモーションは武器種ごとに、下忍のモーションは下忍の項目に置く。
-- ID が 0 の項目はまだモーションが無く、再生しない。Roblox の API は使わない。
--
-- - 待機と移動は、仮の見た目の HumanoidDescription に入れて当てる（Appearance.luau）。
--   アバターの読み込みを止めているので、アバターのモーションの設定には左右されない
-- - 行動のモーションは、クライアントの MotionController が行動の Attribute を見て、行動の長さに合わせた速さで再生する
-- - 上忍と首領の型（Config.luau の Kata 節）は、武器種の行動のモーションを型ごとに行動と段で引いて流用する（forKata）。
--   武器種の決まっていない NPC は KATA_BUKISHU の武器種から引く。サーバーの JoninKotaiService が個体に再生する
-- - 攻撃判定のタイミングと移動量は Config.luau に置く。モーションを差し替えても判定は変わらない

local Characters = require("./Characters")

-- 待機と移動。HumanoidDescription の *Animation に入れるカタログのアセット ID
export type Locomotion = {
	Idle: number,
	Walk: number,
	Run: number,
	Jump: number,
	Fall: number,
	Climb: number,
	Swim: number,
}

-- 武器種1つぶんの行動のモーション（アニメーションのアセット ID）
export type BukishuMotions = {
	-- 通常攻撃の1〜6段
	Attack: { number },
	-- チャージ攻撃の C1〜C6
	ChargeKogeki: { number },
	JumpAttack: number,
	Guard: number,
	GuardHit: number,
	KinkyuKaihi: number,
	Flinch: number,
	Down: number,
	GetUp: number,
}

-- 上忍と首領の型で流用する、武器種の行動のモーションの項目（行動と、通常攻撃とチャージ攻撃の段）
export type KataMotion = {
	action: string,
	step: number?,
}

-- 下忍のモーション
export type GeninMotions = {
	Idle: number,
	Run: number,
	Attack: number,
	Flinch: number,
	Down: number,
	GetUp: number,
}

local Motions = {}

-- Ninja アニメーションパッケージ（バンドル 75）のカタログのアセット ID
Motions.Locomotion = {
	Idle = 658832408,
	Walk = 658831143,
	Run = 658830056,
	Jump = 658832070,
	Fall = 658831500,
	Climb = 658833139,
	Swim = 658832807,
} :: Locomotion

-- Locomotion のアセットに入っているアニメーションの ID。再生中のモーションを確かめるときに使う
Motions.LocomotionAnimations = {
	Idle = { 10921155160, 10921155867 },
	Walk = { 10921162768 },
	Run = { 10921157929 },
	Jump = { 10921160088 },
	Fall = { 10921159222 },
	Climb = { 10921154678 },
	Swim = { 10921161002, 10922757002 },
} :: { [string]: { number } }

local function emptyBukishu(): BukishuMotions
	return {
		Attack = { 0, 0, 0, 0, 0, 0 },
		ChargeKogeki = { 0, 0, 0, 0, 0, 0 },
		JumpAttack = 0,
		Guard = 0,
		GuardHit = 0,
		KinkyuKaihi = 0,
		Flinch = 0,
		Down = 0,
		GetUp = 0,
	}
end

-- 武器種ごとの行動のモーション。モーションセット（手裏剣セット・刀セット）にあたる
Motions.Bukishu = {
	Shuriken = emptyBukishu(),
	Katana = emptyBukishu(),
} :: { [string]: BukishuMotions }

-- 奥義のモーション。キャラクター定義の ougi（忍術の英名）ごとに置く
Motions.Ougi = {
	Katon = 0,
	PoisonShuriken = 0,
	MutoDori = 0,
	Kinton = 0,
} :: { [string]: number }

-- 上忍と首領の型のモーション。型 ID（Config.luau の Kata 節）ごとに、流用する武器種の行動の項目を置く。
-- 行の終わりは、試験用の上忍と首領が使う刀セットの技
Motions.Kata = {
	Kesagiri = { action = "Attack", step = 1 }, -- 袈裟斬り
	Renzan = { action = "ChargeKogeki", step = 5 }, -- 乱れ斬りの後に斬り払う
	Senpu = { action = "ChargeKogeki", step = 4 }, -- 回転斬り
	Shurikenuchi = { action = "Attack", step = 3 }, -- 横薙ぎ（手裏剣セットは手裏剣を投げる段）
	Daichiwari = { action = "ChargeKogeki", step = 6 }, -- 大上段から斬り下ろす
	Shogekiha = { action = "ChargeKogeki", step = 1 }, -- 溜めてから突進して斬る
} :: { [string]: KataMotion }

-- 武器種の決まっていない NPC（試験用の上忍と首領など）が、型のモーションを引く武器種
Motions.KATA_BUKISHU = "Katana"

-- 下忍の共通のモーション
Motions.Genin = {
	Idle = 0,
	Run = 0,
	Attack = 0,
	Flinch = 0,
	Down = 0,
	GetUp = 0,
} :: GeninMotions

-- 行動のモーションの ID。通常攻撃とチャージ攻撃は step（段か C の番号）で引く。無ければ 0
function Motions.actionOf(bukishu: string, action: string, step: number?): number
	local motions = Motions.Bukishu[bukishu]
	if not motions then
		return 0
	end
	local value = (motions :: any)[action]
	if type(value) == "table" then
		return value[step or 1] or 0
	end
	return if type(value) == "number" then value else 0
end

-- 行動のモーションを重ねる優先度（Enum.AnimationPriority の名前）。
-- 待機と移動（Animate の Idle・Movement）より上にし、被弾の反応は攻撃より上にする
export type Priority = "Action" | "Action2"

-- 被弾の反応の行動
local REACTIONS = { Flinch = true, Down = true, GetUp = true, GuardHit = true }
-- 行動が続く間くり返すモーション。ガードは離すまで続く
local LOOPED = { Guard = true }

-- キャラクターの行動で再生するモーションの ID。奥義（Ougi）はキャラクターの奥義の項目から、
-- ほかはキャラクターの武器種の項目から step で引く。無ければ 0
function Motions.forAction(characterId: string, action: string, step: number?): number
	local character = Characters.get(characterId)
	if not character then
		return 0
	end
	if action == "Ougi" then
		return if character.ougi then Motions.Ougi[character.ougi] or 0 else 0
	end
	if not character.bukishu then
		return 0
	end
	return Motions.actionOf(character.bukishu, action, step)
end

-- 上忍か首領の型で再生するモーションの ID。キャラクターの武器種（無ければ KATA_BUKISHU）の行動の項目から、
-- 型の行動と段で引く。項目の無い型は 0
function Motions.forKata(characterId: string, kataId: string): number
	local entry = Motions.Kata[kataId]
	if not entry then
		return 0
	end
	local character = Characters.get(characterId)
	local bukishu = if character and character.bukishu then character.bukishu else Motions.KATA_BUKISHU
	return Motions.actionOf(bukishu, entry.action, entry.step)
end

-- キャラクターが行動で使うモーションの ID を、重なりなく小さい順に返す（読み込みの先回りに使う）
function Motions.idsOf(characterId: string): { number }
	local character = Characters.get(characterId)
	local found: { [number]: boolean } = {}
	local function add(id: number?)
		if id and id > 0 then
			found[id] = true
		end
	end
	if character and character.bukishu then
		for _, value in (Motions.Bukishu[character.bukishu] or {}) :: any do
			if type(value) == "table" then
				for _, id in value do
					add(id)
				end
			else
				add(value)
			end
		end
	end
	if character and character.ougi then
		add(Motions.Ougi[character.ougi])
	end
	local ids = {}
	for id in found do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

function Motions.priorityOf(action: string): Priority
	return if REACTIONS[action] then "Action2" else "Action"
end

function Motions.isLooped(action: string): boolean
	return LOOPED[action] == true
end

-- 長さ length（秒）のモーションを、長さ duration（秒）の行動に合わせる再生の速さ。
-- 長さの分からないモーションと、終わりの決まっていない行動（ガード）は 1
function Motions.playbackSpeed(length: number, duration: number?): number
	if length <= 0 or duration == nil or duration <= 0 or duration == math.huge then
		return 1
	end
	return length / duration
end

return Motions
