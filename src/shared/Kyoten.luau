--!strict
-- 拠点の耐久と制圧の計算。拠点は耐久を持ち、範囲の中でその拠点の軍の下忍が倒れると減る。
-- 耐久が 0 になると相手の軍に制圧され、耐久は制圧直後の値になる。本陣も同じ仕組みで扱う。
-- 耐久の上限・制圧直後の割合・下忍1人ぶんの減り方は Config.luau の Kyoten 節にある。Roblox の API は使わない。
--
-- - 耐久は 0 から上限までの数で持つ。時間とともに減らすときのために端数も持つ
-- - 制圧したら所属を相手の軍に変え、耐久を上限 × 制圧直後の割合にする。減らしきって余った分は持ち越さない
-- - 画面と窓口に出す耐久は端数を切り上げる

local Config = require("./Config")
local Gun = require("./Gun")

export type Params = Config.KyotenSection

export type Kyoten = {
	id: string,
	-- 本陣か。本陣でなければ通常拠点
	honjin: boolean,
	-- 今の所属の軍
	gun: Gun.Gun,
	-- 今の耐久
	taikyu: number,
}

local Kyoten = {}

-- 耐久の上限
function Kyoten.maxTaikyu(honjin: boolean, params: Params?): number
	local p = params or Config.Kyoten
	return if honjin then p.Taikyu.Honjin else p.Taikyu.Kyoten
end

-- 制圧した直後の耐久
function Kyoten.seiatsuTaikyu(honjin: boolean, params: Params?): number
	local p = params or Config.Kyoten
	return Kyoten.maxTaikyu(honjin, p) * p.SeiatsuRate
end

-- 開始時の拠点。耐久は上限から始まる
function Kyoten.new(id: string, honjin: boolean, gun: Gun.Gun, params: Params?): Kyoten
	return { id = id, honjin = honjin, gun = gun, taikyu = Kyoten.maxTaikyu(honjin, params) }
end

-- 所属を gun に変え、耐久を制圧直後の値にする。kyoten を書き換える
function Kyoten.seiatsu(kyoten: Kyoten, gun: Gun.Gun, params: Params?)
	kyoten.gun = gun
	kyoten.taikyu = Kyoten.seiatsuTaikyu(kyoten.honjin, params)
end

-- 耐久を amount 減らす。0 になったら相手の軍に制圧させ、true を返す。kyoten を書き換える。
-- amount が 0 以下なら何もしない
function Kyoten.damage(kyoten: Kyoten, amount: number, params: Params?): boolean
	if amount <= 0 then
		return false
	end
	kyoten.taikyu = math.max(kyoten.taikyu - amount, 0)
	if kyoten.taikyu > 0 then
		return false
	end
	Kyoten.seiatsu(kyoten, Gun.opponentOf(kyoten.gun), params)
	return true
end

-- 耐久を value にする（0 から上限までに収める）。0 にしたら相手の軍に制圧させ、true を返す。kyoten を書き換える
function Kyoten.setTaikyu(kyoten: Kyoten, value: number, params: Params?): boolean
	local clamped = math.clamp(value, 0, Kyoten.maxTaikyu(kyoten.honjin, params))
	if clamped > 0 then
		kyoten.taikyu = clamped
		return false
	end
	Kyoten.seiatsu(kyoten, Gun.opponentOf(kyoten.gun), params)
	return true
end

-- 範囲の中でその拠点の軍の下忍が count 人倒れたときに減る耐久
function Kyoten.gekihaDamage(count: number, params: Params?): number
	local p = params or Config.Kyoten
	return math.max(count, 0) * p.GeninGekiha
end

-- 画面と窓口に出す耐久。端数は切り上げる（残りがわずかでも 0 とは出さない）
function Kyoten.displayTaikyu(taikyu: number): number
	if taikyu <= 0 then
		return 0
	end
	return math.ceil(taikyu)
end

return Kyoten
