--!strict
-- 士気の計算。軍全体の士気を軍ごとに1本持ち、部隊の士気はそれを基準に近くの出来事で上下させる。
-- 出来事は上忍の撃破・拠点の陥落・秘計の発動の3種類で、種類・位置・得をする軍・起きた時刻を持つ。
--
-- - 出来事が起きると、軍全体の士気は得をする軍が上がり、相手の軍が下がる（applyToGun）
-- - 部隊の士気 = 軍全体の士気 + 部隊ごとの補正（率いる上忍を失ったときの下げ幅）+ 出来事の補正の和
--   − 大喝による動揺の下げ幅（ofButai）
-- - 出来事の補正は、得をする軍の部隊では上げ、相手の軍の部隊では下げる。
--   出来事の位置で最大になり、距離に比例して減って Radius で 0 になり、時間に比例して減って Duration で消える
-- - 軍全体の士気と部隊の士気は Min から Max までに収める
--
-- 上下の量・距離・時間は Config.luau の Shiki 節にある。時刻は引数で受け取る。Roblox の API は使わない。

local Config = require("./Config")
local Gun = require("./Gun")

export type Params = Config.ShikiSection

-- 出来事の種類。上忍の撃破、拠点の陥落、秘計の発動
export type Kind = "JoninGekiha" | "KyotenKanraku" | "Hikei"

-- 水平の位置。x は東、z は南が +（ワールドの座標）
export type Point = { x: number, z: number }

export type Dekigoto = {
	kind: Kind,
	position: Point,
	-- 得をする軍
	gun: Gun.Gun,
	-- 起きた時刻
	at: number,
}

-- 軍全体の士気。軍ごとに1本
export type GunShiki = { Mikatagun: number, Tekigun: number }

-- 士気を求める部隊。Butai.luau の部隊をそのまま渡せる
export type ButaiInput = {
	gun: Gun.Gun,
	position: Point,
	-- 部隊ごとの補正。軍全体の士気に足す
	shikiHosei: number,
	-- 大喝で動揺している間、士気から引く量。動揺していなければ nil
	doyo: number?,
}

local Shiki = {}

Shiki.kinds = { "JoninGekiha", "KyotenKanraku", "Hikei" } :: { Kind }

function Shiki.isKind(value: unknown): boolean
	return table.find(Shiki.kinds, value :: any) ~= nil
end

local function clamp(value: number, p: Params): number
	return math.clamp(value, p.Min, p.Max)
end

-- 開始時の軍全体の士気
function Shiki.newGun(params: Params?): GunShiki
	local p = params or Config.Shiki
	return { Mikatagun = p.Initial, Tekigun = p.Initial }
end

-- 出来事を軍全体の士気に反映する。得をする軍は上がり、相手の軍は下がる。gunShiki を書き換える
function Shiki.applyToGun(gunShiki: GunShiki, kind: Kind, gun: Gun.Gun, params: Params?)
	local p = params or Config.Shiki
	local amount = p.Dekigoto[kind].Gun
	local opponent = Gun.opponentOf(gun)
	gunShiki[gun] = clamp(gunShiki[gun] + amount, p)
	gunShiki[opponent] = clamp(gunShiki[opponent] - amount, p)
end

-- 1つの出来事が、gun の軍の位置 position にいる部隊の士気に足す補正
function Shiki.hosei(dekigoto: Dekigoto, gun: Gun.Gun, position: Point, now: number, params: Params?): number
	local p = params or Config.Shiki
	local age = math.max(now - dekigoto.at, 0)
	if age >= p.Duration then
		return 0
	end
	local dx, dz = position.x - dekigoto.position.x, position.z - dekigoto.position.z
	local distance = math.sqrt(dx * dx + dz * dz)
	if distance >= p.Radius then
		return 0
	end
	local amount = p.Dekigoto[dekigoto.kind].Butai * (1 - distance / p.Radius) * (1 - age / p.Duration)
	return if dekigoto.gun == gun then amount else -amount
end

-- 部隊の士気。軍全体の士気に、部隊ごとの補正と出来事の補正の和を足し、動揺の下げ幅を引いて、下限と上限に収める
function Shiki.ofButai(
	gunShiki: GunShiki,
	butai: ButaiInput,
	dekigotoList: { Dekigoto },
	now: number,
	params: Params?
): number
	local p = params or Config.Shiki
	local total = gunShiki[butai.gun] + butai.shikiHosei - (butai.doyo or 0)
	for _, dekigoto in dekigotoList do
		total += Shiki.hosei(dekigoto, butai.gun, butai.position, now, p)
	end
	return clamp(total, p)
end

-- 補正の消えた（起きてから Duration 秒たった）出来事を一覧から外し、外した数を返す。dekigotoList を書き換える
function Shiki.prune(dekigotoList: { Dekigoto }, now: number, params: Params?): number
	local p = params or Config.Shiki
	local removed = 0
	for index = #dekigotoList, 1, -1 do
		if now - dekigotoList[index].at >= p.Duration then
			table.remove(dekigotoList, index)
			removed += 1
		end
	end
	return removed
end

return Shiki
