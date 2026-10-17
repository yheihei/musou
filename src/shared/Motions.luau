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
-- - 下忍のモーションは、サーバーの EnemyService が下忍の個体に再生する（#88）。待機と移動は体の速さで選び（geninLocomotionOf）、
--   被弾の反応は反応（Hanno）の状態から引く（geninReactionOf）
-- - 攻撃判定のタイミングと移動量は Config.luau に置く。モーションを差し替えても判定は変わらない
-- - 攻撃・ガード・被弾・奥義と下忍の攻撃・被弾の反応のモーションの取得元（Meshy のモーションライブラリのクリップと区間）は
--   MeshySources に置く（#67・#68・#120・#121・#88）。窓口の DumpMotions で、公開するクリップと項目ごとの ID を確かめる
-- - クリップは切らずに丸ごと公開し、項目の区間だけを流す（segmentOf）。流すのは MotionPlayer.luau で、
--   MotionController・JoninKotaiService・EnemyService が使う

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

-- 下忍のモーション（アニメーションのアセット ID）
export type GeninMotions = {
	-- 待機と移動。くり返し流す
	Idle: number,
	Run: number,
	-- 攻撃
	Attack: number,
	-- 被弾の反応。のけぞり・吹き飛び・打ち上げ・ダウン・起き上がり
	Flinch: number,
	Knockback: number,
	Launch: number,
	Down: number,
	GetUp: number,
}

-- 下忍のモーションを重ねる優先度（Enum.AnimationPriority の名前）
export type GeninPriority = "Idle" | "Movement" | "Action" | "Action2"

-- 下忍の待機と移動のモーションの流し方。体の速さで選ぶ・待機にする・流さない
export type GeninLocomotionMode = "Speed" | "Idle" | "None"

-- Meshy のモーションライブラリのクリップ。表の鍵は Meshy の番号（action_id、0〜696）。length はクリップの長さ（秒）
export type MeshyClip = {
	name: string,
	length: number,
}

-- 項目に使う Meshy のクリップの番号と、行動に合う区間（クリップの頭からの秒）
export type MeshySource = {
	clip: number,
	from: number,
	to: number,
}

-- 武器種1つぶんの取得元（BukishuMotions と同じ項目）
export type BukishuSources = {
	Attack: { MeshySource },
	ChargeKogeki: { MeshySource },
	JumpAttack: MeshySource,
	Guard: MeshySource,
	GuardHit: MeshySource,
	KinkyuKaihi: MeshySource,
	Flinch: MeshySource,
	Down: MeshySource,
	GetUp: MeshySource,
}

export type MeshySourceSection = {
	Bukishu: { [string]: BukishuSources },
	-- 奥義の ID（Motions.Ougi と同じ）ごと
	Ougi: { [string]: MeshySource },
	-- 下忍の項目（待機と移動を除く）ごと
	Genin: { [string]: MeshySource },
}

-- 取得元の項目1つ。group は武器種（Shuriken・Katana）か Ougi か Genin、item は行動・奥義・下忍の項目の名前、
-- step は通常攻撃とチャージ攻撃の段。id は今入っている Roblox のアニメーション ID（0 はまだ公開していない）
export type MeshySlot = {
	group: string,
	item: string,
	step: number?,
	source: MeshySource,
	id: number,
}

-- 区間で流すときの、流し始めの位置（start）と止める位置（stop。どちらもクリップの頭からの秒）と、その間を流す速さ（speed）。
-- whole はクリップを頭から終わりまで丸ごと流すとき
export type Segment = {
	start: number,
	stop: number,
	speed: number,
	whole: boolean,
}

-- 窓口の SetMotion で差し替えた行動のモーション1つ。from と to があればその区間を流し、無ければ丸ごと流す
export type MotionTest = {
	id: number,
	from: number?,
	to: number?,
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

-- 下忍の共通のモーション（#88）。ID が 0 の項目は再生しない。
-- - 待機と移動は Ninja アニメーションパッケージのアニメーション（LocomotionAnimations）を使う。持ち主が Roblox なので、
--   どの体験でも再生できる。待機は Locomotion_Ninja_Idle（見回す IdleAlt は混ぜない）
-- - 移動は Locomotion_Ninja_Walk でなく Locomotion_Ninja_Run にする。下忍の歩く速さ（Config.luau の Genin 節の WalkSpeed、
--   12 スタッド/秒）はプレイヤー（22〜26）の半分ほどで、歩きには速く、走りには遅い。斬り込んでくる下忍には走る姿が
--   合うので走りにし、歩く速さに合わせて遅めに流す（Config.luau の GeninMotion 節の RunSpeed との比）
-- - 攻撃と被弾の反応は、モーションの経路の検証（#16）の後に調達する
Motions.Genin = {
	Idle = 10921155160,
	Run = 10921157929,
	Attack = 0,
	Flinch = 0,
	Knockback = 0,
	Launch = 0,
	Down = 0,
	GetUp = 0,
} :: GeninMotions

-- 下忍のモーションの項目の並び（Motions.Genin の項目と同じ。窓口で項目を確かめて並べるときに使う）
Motions.GENIN_ITEMS = { "Idle", "Run", "Attack", "Flinch", "Knockback", "Launch", "Down", "GetUp" } :: { string }

-- 下忍のモーションの項目ごとの優先度。待機と移動（Idle・Movement）の上に攻撃（Action）を重ね、
-- 被弾の反応は攻撃より上（Action2）にする（プレイヤーの行動のモーションと同じ順）
local GENIN_PRIORITIES: { [string]: GeninPriority } = {
	Idle = "Idle",
	Run = "Movement",
	Attack = "Action",
	Flinch = "Action2",
	Knockback = "Action2",
	Launch = "Action2",
	Down = "Action2",
	GetUp = "Action2",
}

-- 使う Meshy のモーションライブラリのクリップ。名前と長さは、fal の rigging/multi-animation の応答の GLB から読んだ値（2026-10-13）
Motions.MeshyClips = {
	[3] = { name = "Arise", length = 1.867 },
	[4] = { name = "Attack", length = 2.833 },
	[7] = { name = "BeHit_FlyUp", length = 1.533 },
	[91] = { name = "Double_Blade_Spin", length = 5.7 },
	[97] = { name = "Left_Slash", length = 3.2 },
	[99] = { name = "Reaping_Swing", length = 5.933 },
	[102] = { name = "Sword_Judgment", length = 4.367 },
	[105] = { name = "Triple_Combo_Attack", length = 4.367 },
	[125] = { name = "Charged_Spell_Cast", length = 2.7 },
	[127] = { name = "Charged_Ground_Slam", length = 3.033 },
	[128] = { name = "Heavy_Hammer_Swing", length = 1.867 },
	[132] = { name = "mage_soell_cast_3", length = 3.367 },
	[133] = { name = "mage_soell_cast_4", length = 2.233 },
	[138] = { name = "Block1", length = 3.5 },
	[140] = { name = "Block3", length = 1.533 },
	[148] = { name = "Sword_Parry_Backward", length = 1.367 },
	[149] = { name = "Two_Handed_Parry", length = 1.367 },
	[157] = { name = "Stand_Dodge_1", length = 1.3 },
	[178] = { name = "Hit_Reaction", length = 1.667 },
	[179] = { name = "Hit_Reaction_1", length = 1.233 },
	[182] = { name = "Shot_and_Blown_Back", length = 2.7 },
	[189] = { name = "dying_backwards", length = 2.233 },
	[190] = { name = "Knock_Down_1", length = 3.3 },
	[200] = { name = "Punch_Combo_1", length = 2.233 },
	[202] = { name = "Weapon_Combo_1", length = 3.533 },
	[206] = { name = "Spartan_Kick", length = 1.433 },
	[216] = { name = "Lunge_Spin_Kick", length = 1.667 },
	[218] = { name = "Step_in_High_Kick", length = 1.333 },
	[219] = { name = "Right_Hand_Sword_Slash", length = 1.533 },
	[221] = { name = "Charged_Upward_Slash", length = 3.2 },
	[238] = { name = "Axe_Spin_Attack", length = 2.533 },
	[240] = { name = "Thrust_Slash", length = 3.033 },
	[241] = { name = "Weapon_Combo_2", length = 4.533 },
	[242] = { name = "Charged_Slash", length = 2.233 },
	[384] = { name = "Quick_Step_and_Spin_Dodge", length = 1.2 },
	[393] = { name = "baseball_pitching", length = 4 },
	[397] = { name = "360_Power_Spin_Jump", length = 3.067 },
	[422] = { name = "Rising_Flying_Kick", length = 1.533 },
	[508] = { name = "Dive_Down_and_Land_2", length = 3.1 },
} :: { [number]: MeshyClip }

local function meshy(clip: number, from: number, to: number): MeshySource
	return { clip = clip, from = from, to = to }
end

-- 項目ごとの取得元（Meshy のクリップと区間）。区間は Meshy のプレビューを見て決めた目安で、公開したモーションを Studio で見て詰める。
-- - クリップは fal で刃のモデルにリグを入れて付けた。Meshy のリグの動きを R15 で流す経路は #16 で決める
-- - Roblox へはクリップを切らずに丸ごと公開し、同じクリップを使う項目には同じ ID を入れる。区間はコードで切り出して流す
--   （MotionPlayer.luau。項目の ID が入れば、その項目の区間を行動の長さに合わせて流す）
-- - 項目に入れる ID は、ここのクリップを丸ごと公開したものにする。切って公開したものや別のモーションを入れるときは、
--   区間もその長さに合わせて直す（丸ごと流すなら from 0、to にそのモーションの長さ）
-- - 下忍の待機と移動は Ninja パックなので、ここには無い
Motions.MeshySources = {
	Bukishu = {
		-- 手裏剣セット（刃・酉花）。#67（攻撃）・#120（防御・被弾）
		Shuriken = {
			Attack = {
				meshy(219, 0.15, 1), -- 斬り払い。右手で踏み込んで斬る
				meshy(240, 1.3, 2.2), -- 斬り返し。振り返りながら逆手で払う後半
				meshy(393, 1, 2.4), -- 手裏剣を1枚投げる。振りかぶってから投げ終えるまで
				meshy(216, 0.4, 1.4), -- 回し蹴り
				meshy(133, 0.3, 1.3), -- 手裏剣を3枚、扇に投げる。踏み込んで腕を横に払う
				meshy(397, 0.6, 2.1), -- 宙返りして周りを斬る。屈んで跳び、回って着地する
			},
			ChargeKogeki = {
				meshy(206, 0.2, 1.1), -- C1 踏み込んで蹴り飛ばす（前蹴り）
				meshy(218, 0.1, 1), -- C2 蹴り上げて打ち上げる
				meshy(422, 0, 1.2), -- C3 跳び上がって蹴る
				meshy(127, 1.2, 2.4), -- C4 煙玉を地面に叩きつける。腕を上げてから膝をついて叩く
				meshy(238, 0.2, 1.6), -- C5 回って八方へ撒く
				meshy(200, 0.2, 1.9), -- C6 手裏剣の雨。両手を交互に前へ突き出す
			},
			JumpAttack = meshy(508, 0.3, 1.5), -- 急降下して着地する。着地の構えまで
			Guard = meshy(138, 0, 3.5), -- 両腕を上げた構え（くり返す）
			GuardHit = meshy(140, 0.4, 1.1), -- 構えたまま受けてのけぞる
			KinkyuKaihi = meshy(384, 0, 1.2), -- 素早く踏み出して回る（向きを変えずに方向へ動くので転がらない）
			Flinch = meshy(179, 0, 0.8),
			Down = meshy(190, 0.5, 2.4), -- 蹴られて仰向けに倒れる
			GetUp = meshy(3, 0, 1.867), -- 仰向けから起き上がる
		},
		-- 刀セット（石舟斎・金鬼）。#68（攻撃）・#121（防御・被弾）
		Katana = {
			Attack = {
				meshy(97, 0.3, 1.4), -- 袈裟斬り。振りかぶって斜めに斬り下ろす
				meshy(97, 1.9, 2.8), -- 逆袈裟。同じクリップの斬り返し
				meshy(99, 3.3, 4.3), -- 横薙ぎ。クリップの終わりの横の払い
				meshy(240, 0.1, 0.9), -- 踏み込んで突く。同じクリップの前半の突き
				meshy(105, 1.2, 2.2), -- 回転斬り。跳んで回って斬る
				meshy(4, 0.3, 1.7), -- 唐竹割り。両手で振りかぶって真下へ斬る
			},
			ChargeKogeki = {
				meshy(242, 0.2, 1.7), -- C1 溜めてから斬る
				meshy(221, 0.3, 2), -- C2 屈んで溜めてから斬り上げる
				meshy(102, 0.3, 2), -- C3 跳び上がってから斬り下ろして着地する
				meshy(91, 0.3, 1.9), -- C4 跳んで回る回転斬り
				meshy(241, 0.4, 4), -- C5 乱れ斬りの後に斬り払う
				meshy(128, 0, 1.867), -- C6 大上段から地面まで振り下ろす
			},
			JumpAttack = meshy(102, 0.9, 1.9), -- 落ちながら斬り下ろして着地する（C3 と同じクリップの後半）
			Guard = meshy(149, 0, 1.367), -- 両手で刀を横に構える（くり返す）
			GuardHit = meshy(148, 0, 1.367),
			KinkyuKaihi = meshy(157, 0, 1.3), -- 横へ踏み出してかわす
			Flinch = meshy(178, 0, 0.9),
			Down = meshy(189, 0.3, 2.2), -- 後ろへ倒れて仰向けになる
			GetUp = meshy(3, 0, 1.867),
		},
	},
	-- 奥義。#120（火遁・毒手裏剣）・#121（無刀取り・金遁）
	Ougi = {
		Katon = meshy(132, 0.6, 2.6), -- 踏み込んで両手を前へ突き出したまま保つ（炎を吐く間）
		PoisonShuriken = meshy(91, 1.5, 4.9), -- 屈んで回りながら刃を振り回す後半（12 方向へ撒く）
		MutoDori = meshy(202, 0.2, 3.2), -- 斬って蹴り上げ、膝をついて叩きつける
		Kinton = meshy(125, 0, 2.7), -- 屈んで溜めてから両腕を上げる（地面から刃が出る）
	},
	-- 下忍（#88）。被弾の反応は反応の状態の間だけ等速で流れる（のけぞり 0.35 秒、ダウン 1 秒、起き上がり 0.5 秒）。
	-- 吹き飛びと起き上がりの区間は、その状態の長さに収まる所を選んだ（2026-10-17、検証用のプレースの MeshyRig.hikaku で確かめた）
	Genin = {
		Attack = meshy(219, 0, 1.533), -- 右手で踏み込んで斬る（攻撃の間隔 1.5 秒に収まる長さ）
		Flinch = meshy(179, 0, 0.6),
		Knockback = meshy(182, 0.95, 1.25), -- 後ろへ倒れていく所（C1 の軌道は 0.26 秒で着地する）
		Launch = meshy(7, 0, 1), -- 打ち上げられて回る
		Down = meshy(189, 1.4, 2.233), -- 仰向けに倒れている終わりの部分
		GetUp = meshy(3, 1.2, 1.7), -- しゃがんだ所から立つ所（仰向けから座る前半は起き上がりの 0.5 秒に入らない）
	},
} :: MeshySourceSection

-- 取得元を並べる順。武器種の項目、奥義、下忍の項目（待機と移動を除く）
local MESHY_BUKISHU = { "Shuriken", "Katana" }
local BUKISHU_ITEMS =
	{ "Attack", "ChargeKogeki", "JumpAttack", "Guard", "GuardHit", "KinkyuKaihi", "Flinch", "Down", "GetUp" }
local MESHY_OUGI = { "Katon", "PoisonShuriken", "MutoDori", "Kinton" }
local MESHY_GENIN = { "Attack", "Flinch", "Knockback", "Launch", "Down", "GetUp" }

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

-- 上忍か首領の型のモーションを引く武器種。キャラクターの武器種（無ければ KATA_BUKISHU）
local function kataBukishuOf(characterId: string): string
	local character = Characters.get(characterId)
	return if character and character.bukishu then character.bukishu else Motions.KATA_BUKISHU
end

-- 上忍か首領の型で再生するモーションの ID。キャラクターの武器種（無ければ KATA_BUKISHU）の行動の項目から、
-- 型の行動と段で引く。項目の無い型は 0
function Motions.forKata(characterId: string, kataId: string): number
	local entry = Motions.Kata[kataId]
	if not entry then
		return 0
	end
	return Motions.actionOf(kataBukishuOf(characterId), entry.action, entry.step)
end

-- 武器種の行動の項目の取得元（区間）。通常攻撃とチャージ攻撃は step（段か C の番号。省くと1）で引く。無ければ nil
function Motions.sourceOf(bukishu: string, action: string, step: number?): MeshySource?
	local sources = Motions.MeshySources.Bukishu[bukishu]
	local value = if sources then (sources :: any)[action] else nil
	if type(value) ~= "table" then
		return nil
	end
	if value.clip == nil then
		return value[step or 1]
	end
	return value
end

-- キャラクターの行動のモーションの取得元。forAction と同じ項目（奥義はキャラクターの奥義、ほかは武器種の項目）を引く。無ければ nil
function Motions.sourceForAction(characterId: string, action: string, step: number?): MeshySource?
	local character = Characters.get(characterId)
	if not character then
		return nil
	end
	if action == "Ougi" then
		return if character.ougi then Motions.MeshySources.Ougi[character.ougi] else nil
	end
	if not character.bukishu then
		return nil
	end
	return Motions.sourceOf(character.bukishu, action, step)
end

-- 上忍か首領の型のモーションの取得元。forKata と同じ項目（流用する武器種の行動の項目）を引く。無ければ nil
function Motions.sourceForKata(characterId: string, kataId: string): MeshySource?
	local entry = Motions.Kata[kataId]
	if not entry then
		return nil
	end
	return Motions.sourceOf(kataBukishuOf(characterId), entry.action, entry.step)
end

-- 武器種の行動の項目の名前（取得元の項目の名前と同じ。"Shuriken Attack 1"・"Katana Guard"）。
-- 通常攻撃とチャージ攻撃は段（省くと1）を付ける。項目が無ければ nil
function Motions.labelOf(bukishu: string, action: string, step: number?): string?
	local sources = Motions.MeshySources.Bukishu[bukishu]
	local value = if sources then (sources :: any)[action] else nil
	if type(value) ~= "table" then
		return nil
	end
	if value.clip == nil then
		local index = step or 1
		return if value[index] then `{bukishu} {action} {index}` else nil
	end
	return `{bukishu} {action}`
end

-- キャラクターの行動の項目の名前。奥義は "Ougi <奥義の ID>"、ほかは武器種の項目の名前（labelOf）。項目が無ければ nil
function Motions.actionLabelOf(characterId: string, action: string, step: number?): string?
	local character = Characters.get(characterId)
	if not character then
		return nil
	end
	if action == "Ougi" then
		local ougi = character.ougi
		return if ougi and Motions.MeshySources.Ougi[ougi] then `Ougi {ougi}` else nil
	end
	if not character.bukishu then
		return nil
	end
	return Motions.labelOf(character.bukishu, action, step)
end

-- 上忍か首領の型が流用する、武器種の行動の項目の名前。項目の無い型は nil
function Motions.kataLabelOf(characterId: string, kataId: string): string?
	local entry = Motions.Kata[kataId]
	if not entry then
		return nil
	end
	return Motions.labelOf(kataBukishuOf(characterId), entry.action, entry.step)
end

-- 窓口の SetMotion で差し替えた行動のモーション tests（項目の名前ごと）を、項目 label の ID id と取得元 source に当てる。
-- 差し替えた項目なら差し替えの ID と区間（from と to が無ければ丸ごとの nil）を返し、ほかの項目はそのまま返す
function Motions.withTest(
	tests: { [string]: MotionTest }?,
	label: string?,
	id: number,
	source: MeshySource?
): (number, MeshySource?)
	local test = if tests and label then tests[label] else nil
	if not test then
		return id, source
	end
	local from, to = test.from, test.to
	if from and to then
		return test.id, { clip = 0, from = from, to = to }
	end
	return test.id, nil
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

-- 区間の端（クリップの頭と終わり）とみなす幅（秒）。取得元の長さ（Meshy の GLB から読んだ値）と、
-- Roblox に公開したトラックの長さのずれを吸収する
local SEGMENT_EDGE = 0.05

-- 長さ length（秒）のトラックを、取得元の区間 source（nil は丸ごと）で、長さ duration（秒）の行動に合わせて流すときの区間と速さ。
-- 区間はトラックの長さに収め、端から SEGMENT_EDGE 以内はクリップの端にそろえる。区間の長さが 0 になれば丸ごとにする。
-- 速さは区間の長さを行動の長さで割ったもの（playbackSpeed。行動の長さが分からないときと終わりの無い行動は等速）。
-- 長さの分からないトラック（読み込みの前）は丸ごとの等速とし、長さが分かってから決め直す
function Motions.segmentOf(source: MeshySource?, length: number, duration: number?): Segment
	if length <= 0 then
		return { start = 0, stop = 0, speed = 1, whole = true }
	end
	local start, stop = 0, length
	if source then
		start = math.clamp(source.from, 0, length)
		stop = math.clamp(source.to, start, length)
		if start <= SEGMENT_EDGE then
			start = 0
		end
		if stop >= length - SEGMENT_EDGE then
			stop = length
		end
		if stop <= start then
			start, stop = 0, length
		end
	end
	return {
		start = start,
		stop = stop,
		speed = Motions.playbackSpeed(stop - start, duration),
		whole = start == 0 and stop == length,
	}
end

-- 区間 segment を流し始めてから elapsed 秒（実時間）たった位置（クリップの頭からの秒）。区間の頭から速さの分だけ進め、終わりで止める
function Motions.segmentPosition(segment: Segment, elapsed: number): number
	return math.min(segment.start + math.max(elapsed, 0) * segment.speed, segment.stop)
end

-- 下忍のモーションの項目か
function Motions.isGeninItem(item: unknown): boolean
	return type(item) == "string" and table.find(Motions.GENIN_ITEMS, item) ~= nil
end

-- 下忍のモーションの項目の ID。項目でなければ 0
function Motions.geninIdOf(item: string): number
	if not Motions.isGeninItem(item) then
		return 0
	end
	local id = (Motions.Genin :: any)[item]
	return if type(id) == "number" then id else 0
end

-- 窓口の SetGeninMotion で差し替えた下忍の項目の区間（項目ごと）。false は丸ごと流す。
-- 差し替えていない項目は取得元（MeshySources.Genin）の区間で流す
Motions.GeninTests = {} :: { [string]: MeshySource | false }

-- 窓口の SetGeninMotion で一時 ID に差し替えた下忍の項目（項目ごと）。公開していないクリップを
-- KeyframeSequenceProvider:RegisterKeyframeSequence で登録した一時 ID で試す用。あれば項目の ID より先に使う
Motions.GeninTestContents = {} :: { [string]: string }

-- 下忍のモーションの項目の ID を差し替える（窓口の SetGeninMotion。サーバーを止めるまで続く）。
-- 差し替えた項目は区間 source（省くと丸ごと）で流し、一時 ID の差し替えは外す。項目でなければ false
function Motions.setGeninId(item: string, id: number, source: MeshySource?): boolean
	if not Motions.isGeninItem(item) then
		return false
	end
	(Motions.Genin :: any)[item] = id
	Motions.GeninTestContents[item] = nil
	Motions.GeninTests[item] = if source then source else false
	return true
end

-- 一時 ID か。RegisterKeyframeSequence が返す 32 桁の16進の文字列（2026-10-17 の Studio）と、rbxtemp:// と数字の形を受け付ける
function Motions.isTempContent(value: unknown): boolean
	if type(value) ~= "string" then
		return false
	end
	return (#value == 32 and string.match(value, "^%x+$") ~= nil) or string.match(value, "^rbxtemp://%d+$") ~= nil
end

-- 下忍のモーションの項目を一時 ID content に差し替える（窓口の SetGeninMotion。サーバーを止めるまで続く）。
-- 区間 source（省くと丸ごと）で流す。項目でないか一時 ID でなければ false
function Motions.setGeninContent(item: string, content: string, source: MeshySource?): boolean
	if not Motions.isGeninItem(item) or not Motions.isTempContent(content) then
		return false
	end
	Motions.GeninTestContents[item] = content
	Motions.GeninTests[item] = if source then source else false
	return true
end

-- 下忍のモーションの項目の Animation.AnimationId に入れる文字列。一時 ID に差し替えた項目はその一時 ID、
-- ほかは項目の ID（rbxassetid://）。ID が 0 か項目でなければ nil
function Motions.geninContentOf(item: string): string?
	local temp = Motions.GeninTestContents[item]
	if temp then
		return temp
	end
	local id = Motions.geninIdOf(item)
	return if id > 0 then `rbxassetid://{id}` else nil
end

-- 下忍のモーションの項目の取得元（区間）。窓口で差し替えた項目は差し替えの区間（丸ごとなら nil）。
-- 待機と移動（Ninja パック）と、項目でなければ nil
function Motions.geninSourceOf(item: string): MeshySource?
	local test = Motions.GeninTests[item]
	if test ~= nil then
		return if test then test else nil
	end
	return Motions.MeshySources.Genin[item]
end

-- 下忍のモーションの項目を重ねる優先度
function Motions.geninPriorityOf(item: string): GeninPriority
	return GENIN_PRIORITIES[item] or "Action"
end

-- 待機と移動の項目か（くり返し流す）
function Motions.isGeninLocomotion(item: string): boolean
	return item == "Idle" or item == "Run"
end

-- 下忍の体に流す待機か移動の項目。今流している項目 current（止めていれば nil）と、体の水平の速さ speed（スタッド/秒）、
-- 止まってからの秒数 stillFor で決める。speed が threshold を超えたら移動にする。超えなければ待機にするが、移動を流している体は、
-- 止まってから delay 秒たつまで移動のままにする（考える間隔ごとの歩き直しの間の短い止まりで、走りを流し直さないように）
function Motions.geninLocomotionOf(
	current: string?,
	speed: number,
	stillFor: number,
	threshold: number,
	delay: number
): string
	if speed > threshold then
		return "Run"
	end
	if current == "Run" and stillFor < delay then
		return "Run"
	end
	return "Idle"
end

-- 移動のモーションを流す速さ。体の歩く速さ walkSpeed を、モーションを等速で流したときに見合う速さ runSpeed で割る。
-- どちらかが 0 以下なら等速
function Motions.geninRunPlaybackOf(walkSpeed: number, runSpeed: number): number
	if walkSpeed <= 0 or runSpeed <= 0 then
		return 1
	end
	return walkSpeed / runSpeed
end

-- 反応（Hanno）の状態の種類 kind（Flinch・Air・Down・GetUp。反応の最中でなければ nil）と、飛んでいる間の反応 reaction
-- （Config.luau の Reaction）から引く、下忍の被弾の反応のモーションの項目。打ち上げで飛んでいれば Launch、
-- ほかの飛び方は Knockback。反応の最中でなければ nil
function Motions.geninReactionOf(kind: string?, reaction: string?): string?
	if kind == "Flinch" then
		return "Flinch"
	elseif kind == "Air" then
		return if reaction == "Launch" then "Launch" else "Knockback"
	elseif kind == "Down" then
		return "Down"
	elseif kind == "GetUp" then
		return "GetUp"
	end
	return nil
end

-- 反応の状態の種類が previousKind から kind に変わったときに、被弾の反応のモーションを流し直すか。
-- のけぞりと飛んでいる間は、状態が変わるたび（攻撃を受けるたび）に流し直す。ダウン・起き上がり・反応の終わりは、
-- 種類が変わったときだけにする（倒れている間に倒されて倒れたまま残すときは、ダウンのモーションを続ける）
function Motions.geninReactionRestarts(previousKind: string?, kind: string?): boolean
	if kind == "Flinch" or kind == "Air" then
		return true
	end
	return kind ~= previousKind
end

-- 反応の状態の種類 kind のときの、待機と移動のモーションの流し方。反応の最中でなければ体の速さで選ぶ（Speed）。
-- のけぞりと起き上がりの間は、その場で止めているので待機にする（Idle）。飛んでいる間と倒れている間は流さない（None）
function Motions.geninLocomotionMode(kind: string?): GeninLocomotionMode
	if kind == nil then
		return "Speed"
	elseif kind == "Air" or kind == "Down" then
		return "None"
	end
	return "Idle"
end

-- 取得元の項目を、武器種（MESHY_BUKISHU の順）の行動の項目と段、奥義、下忍の項目の順に並べて返す。
-- group（武器種の名前・Ougi・Genin）を渡すとその項目だけにする（知らない名前なら空）。id は今の一覧（Bukishu・Ougi・Genin）の ID
function Motions.meshySlots(group: string?): { MeshySlot }
	local slots: { MeshySlot } = {}
	local function add(slotGroup: string, item: string, step: number?, source: MeshySource?, id: number)
		if source and (group == nil or group == slotGroup) then
			table.insert(slots, { group = slotGroup, item = item, step = step, source = source, id = id })
		end
	end
	for _, bukishu in MESHY_BUKISHU do
		local sources = Motions.MeshySources.Bukishu[bukishu]
		if not sources then
			continue
		end
		for _, item in BUKISHU_ITEMS do
			local value = (sources :: any)[item]
			if type(value) == "table" and value.clip == nil then
				-- 通常攻撃とチャージ攻撃は段ごと
				for step, source in value do
					add(bukishu, item, step, source, Motions.actionOf(bukishu, item, step))
				end
			else
				add(bukishu, item, nil, value, Motions.actionOf(bukishu, item))
			end
		end
	end
	for _, ougi in MESHY_OUGI do
		add("Ougi", ougi, nil, Motions.MeshySources.Ougi[ougi], Motions.Ougi[ougi] or 0)
	end
	for _, item in MESHY_GENIN do
		add("Genin", item, nil, Motions.MeshySources.Genin[item], Motions.geninIdOf(item))
	end
	return slots
end

-- 取得元の項目の名前（"Shuriken Attack 1"・"Ougi Katon"・"Genin Down"）
function Motions.meshySlotLabel(slot: MeshySlot): string
	local label = `{slot.group} {slot.item}`
	return if slot.step then `{label} {slot.step}` else label
end

-- 窓口の SetMotion で差し替えられる項目の名前か。武器種の行動の項目と奥義（下忍の項目は SetGeninMotion で差し替える）
function Motions.isTestLabel(label: unknown): boolean
	if type(label) ~= "string" then
		return false
	end
	for _, slot in Motions.meshySlots() do
		if slot.group ~= "Genin" and Motions.meshySlotLabel(slot) == label then
			return true
		end
	end
	return false
end

-- 取得元で使う Meshy のクリップの番号を、重なりなく小さい順に返す（Roblox へ公開するクリップの一覧）
function Motions.meshyClipIds(): { number }
	local found: { [number]: boolean } = {}
	for _, slot in Motions.meshySlots() do
		found[slot.source.clip] = true
	end
	local ids = {}
	for id in found do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

return Motions
