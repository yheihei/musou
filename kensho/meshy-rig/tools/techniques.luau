--!strict
-- 操作キャラクターの技（武器種の行動の項目と奥義）の区間・行動の長さ・判定の出る間・前進・落下・腰の移動の抜き方を、
-- musou の src/shared（Motions.luau・Config.luau・KinkyuKaihi.luau）から JSON で書き出す。hikaku_player.py が読む。
--
-- 使い方（リポジトリの直下で）:
--   lune run kensho/meshy-rig/tools/techniques > ~/musou-work/techniques.json
--
-- - 行動の長さは Startup + Active + Recovery（攻撃の速さ 1。刃と石舟斎）。クリップの区間をこの長さで等速に流す（MotionPlayer）
-- - 前進は、攻撃は Startup + Active の間（CombatService）、緊急回避は Active の間（ActionService）に Advance だけ動く
-- - ジャンプ攻撃は Startup の間、Config.luau の Jump 節の DiveSpeed で真下へ落ちる（Push.fall）
-- - ガードは離すまでくり返すので、区間の長さを等速で流す

local serde = require("@lune/serde")

local Config = require("../../../src/shared/Config")
local KinkyuKaihi = require("../../../src/shared/KinkyuKaihi")
local Motions = require("../../../src/shared/Motions")

type Timeline = { Startup: number, Active: number, Recovery: number, Advance: number }

local NAMES = { Shuriken = "手裏剣", Katana = "刀" }

local list = {}

local function add(name: string, source: Motions.MeshySource, timeline: Timeline, options: { [string]: any }?)
	local o = options or {}
	local duration = timeline.Startup + timeline.Active + timeline.Recovery
	table.insert(list, {
		name = name,
		clip = source.clip,
		from = source.from,
		to = source.to,
		strip = source.strip,
		duration = o.duration or duration,
		startup = timeline.Startup,
		active = timeline.Active,
		advance = timeline.Advance,
		advanceTime = o.advanceTime or (timeline.Startup + timeline.Active),
		fall = o.fall or 0,
	})
end

for _, set in { "Shuriken", "Katana" } do
	local sources = Motions.MeshySources.Bukishu[set]
	local bukishu = (Config.Bukishu :: any)[set]
	local label = NAMES[set]
	for step, source in sources.Attack do
		add(`{label} {step}段目`, source, bukishu.Attack[step])
	end
	for step, source in sources.ChargeKogeki do
		add(`{label} C{step}`, source, bukishu.ChargeKogeki[step])
	end
	add(`{label} ジャンプ攻撃`, sources.JumpAttack, bukishu.JumpAttack, { fall = Config.Jump.DiveSpeed })
	local guard = sources.Guard
	add(
		`{label} ガード`,
		guard,
		{ Startup = 0, Active = 0, Recovery = 0, Advance = 0 },
		{ duration = guard.to - guard.from }
	)
	add(`{label} ガード被弾`, sources.GuardHit, Config.Action.GuardHit :: any)
	local kaihi = KinkyuKaihi.timeline(1) :: any
	add(`{label} 緊急回避`, sources.KinkyuKaihi, kaihi, { advanceTime = kaihi.Active })
	add(`{label} のけぞり`, sources.Flinch, Config.Action.Flinch :: any)
	add(`{label} ダウン`, sources.Down, Config.Action.Down :: any)
	add(`{label} 起き上がり`, sources.GetUp, Config.Action.GetUp :: any)
end
for _, id in { "Katon", "PoisonShuriken", "MutoDori", "Kinton" } do
	add(`奥義 {id}`, Motions.MeshySources.Ougi[id], (Config.Ougi.Timelines :: any)[id])
end

print(serde.encode("json", list, true))
