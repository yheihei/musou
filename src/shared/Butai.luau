--!strict
-- 戦場の部隊のデータ（ADR 0003）。部隊は位置・兵数・士気を持つデータで、視界の外では位置だけを動かす。
-- 開始時の部隊の構成は Haichi.luau、兵数と速さは Config.luau の Butai 節にある。
-- 士気は軍全体の士気に部隊ごとの補正と近くの出来事の補正を足して求める（Shiki.luau）。
-- 位置は水平の (x, z) で持ち、高さは持たない（出現させるときに地面の高さに合わせる）。
-- Roblox の API は使わない。

local Gun = require("./Gun")

-- 水平の位置。x は東、z は南が +（ワールドの座標）
export type Point = { x: number, z: number }

export type Butai = {
	id: string,
	gun: Gun.Gun,
	position: Point,
	-- 兵数（0 以上の整数）
	heisu: number,
	-- 今の士気。交戦の計算に使う
	shiki: number,
	-- 部隊ごとの士気の補正。軍全体の士気に足す（率いる上忍を失うと下がる）
	shikiHosei: number,
	-- 率いる上忍のキャラクター ID。率いる上忍のいない部隊は nil
	jonin: string?,
	-- 目指す位置。着いたか、目指す位置が無ければ nil
	mokutekichi: Point?,
	-- 目的地までにたどる経由点（先頭から順に）。たどり着いた点は外す
	keiyuten: { Point },
	-- 最後にいた拠点（開始時の拠点か、着いた拠点）。拠点の外へ出た後も残す
	kyoten: string?,
	-- 目的地が拠点なら、その拠点 ID。着いたら kyoten に移す
	mokutekiKyoten: string?,
	-- 潜んでいる伏兵部隊か。奇襲するまでは交戦の相手を決める対象にも、拠点の守備と攻める軍にも数えない
	fukuhei: boolean?,
}

export type Tsunagari = {
	kyotenA: string,
	kyotenB: string,
	-- kyotenA から kyotenB へたどる順の経由点（両端の拠点は含まない）
	keiyuten: { Point },
}

local Butai = {}

-- 2点の水平の距離
function Butai.distance(a: Point, b: Point): number
	local dx, dz = b.x - a.x, b.z - a.z
	return math.sqrt(dx * dx + dz * dz)
end

-- 経由点と目的地をたどる順に並べる。目的地が無ければ空
function Butai.routeOf(butai: Butai): { Point }
	local mokutekichi = butai.mokutekichi
	if not mokutekichi then
		return {}
	end
	local route = table.clone(butai.keiyuten)
	table.insert(route, mokutekichi)
	return route
end

-- position から route の点を順にたどり、distance スタッド進んだ位置と、まだたどり着いていない点を返す。
-- 点にたどり着いたら次の点へ向かい、余った距離はそのまま次の点へ持ち越す。最後の点に着いたら止まる。
-- 引数の表は書き換えない
function Butai.advance(position: Point, route: { Point }, distance: number): (Point, { Point })
	local current = { x = position.x, z = position.z }
	local remaining = math.max(distance, 0)
	local index = 1
	while index <= #route do
		local target = route[index]
		local gap = Butai.distance(current, target)
		if gap > remaining then
			local ratio = remaining / gap
			current = {
				x = current.x + (target.x - current.x) * ratio,
				z = current.z + (target.z - current.z) * ratio,
			}
			break
		end
		remaining -= gap
		current = { x = target.x, z = target.z }
		index += 1
	end
	local rest = {}
	for i = index, #route do
		table.insert(rest, route[i])
	end
	return current, rest
end

-- 部隊を dt 秒ぶん、速さ speed（スタッド/秒）で目的地へ向けて動かす。目的地に着いたら目的地を外して止まる。
-- 動かしたら true。目的地が無ければ何もしない
function Butai.step(butai: Butai, speed: number, dt: number): boolean
	local route = Butai.routeOf(butai)
	if #route == 0 then
		return false
	end
	local position, rest = Butai.advance(butai.position, route, speed * dt)
	butai.position = position
	if #rest == 0 then
		butai.mokutekichi = nil
		butai.keiyuten = {}
		if butai.mokutekiKyoten then
			butai.kyoten = butai.mokutekiKyoten
			butai.mokutekiKyoten = nil
		end
	else
		butai.mokutekichi = rest[#rest]
		table.remove(rest, #rest)
		butai.keiyuten = rest
	end
	return true
end

-- 目的地を差し替える。keiyuten は目的地までにたどる経由点、kyoten は目的地が拠点ならその拠点 ID。
-- mokutekichi を nil にすると、その場で止まる
function Butai.setMokutekichi(butai: Butai, mokutekichi: Point?, keiyuten: { Point }?, kyoten: string?)
	butai.mokutekichi = if mokutekichi then { x = mokutekichi.x, z = mokutekichi.z } else nil
	butai.keiyuten = if mokutekichi and keiyuten then table.clone(keiyuten) else {}
	butai.mokutekiKyoten = if mokutekichi then kyoten else nil
end

-- 率いる上忍を失った部隊を残し、士気だけを shikiLoss 下げる（0 未満にはしない）。
-- 下げた分は部隊ごとの補正にも残し、軍全体の士気から士気を求め直しても下がったままにする
function Butai.loseJonin(butai: Butai, shikiLoss: number)
	butai.jonin = nil
	butai.shiki = math.max(butai.shiki - shikiLoss, 0)
	butai.shikiHosei -= shikiLoss
end

-- 士気を amount だけずっと下げる（奇襲されたときなど）。下げた分は部隊ごとの補正にも残し、
-- 軍全体の士気から士気を求め直しても下がったままにする。今の士気は 0 未満にはしない
function Butai.lowerShiki(butai: Butai, amount: number)
	butai.shiki = math.max(butai.shiki - amount, 0)
	butai.shikiHosei -= amount
end

-- 兵数を delta だけ増減する。0 未満にはしない。増減した後の兵数を返す
function Butai.changeHeisu(butai: Butai, delta: number): number
	butai.heisu = math.max(math.floor(butai.heisu + delta), 0)
	return butai.heisu
end

-- 拠点 from から拠点 to へ、つながりの道をたどるときの経由点（from → to の順）。
-- 2つの拠点が1本のつながりで結ばれていなければ nil
function Butai.keiyutenBetween(tsunagariList: { Tsunagari }, from: string, to: string): { Point }?
	for _, tsunagari in tsunagariList do
		if tsunagari.kyotenA == from and tsunagari.kyotenB == to then
			return table.clone(tsunagari.keiyuten)
		elseif tsunagari.kyotenA == to and tsunagari.kyotenB == from then
			local reversed = {}
			for index = #tsunagari.keiyuten, 1, -1 do
				table.insert(reversed, tsunagari.keiyuten[index])
			end
			return reversed
		end
	end
	return nil
end

return Butai
