--!strict
-- 秘計の挑発の対象の選び方。発動者から Radius 以内の相手の上忍を、効果時間の間、発動者のもとへ誘い出す。
-- 範囲は Config.luau の Chohatsu 節、誘い出す時間は Hikei 節の Duration.Chohatsu にある。
-- 位置は水平の (x, z) で受け取る。Roblox の API は使わない。
--
-- - 対象は発動者の相手の軍の、倒れていない上忍だけ。首領と、発動者と同じ軍の上忍は対象にしない
-- - もう誘い出されている上忍には重ねない（誘い出した発動者と残りの時間はそのまま）
-- - 範囲の中に対象が1人もいなければ NoTarget、範囲の中の対象がすべてもう誘い出されていれば AlreadyActive

local Config = require("./Config")
local Gun = require("./Gun")
local Hikei = require("./Hikei")

export type Params = Config.ChohatsuSection

-- 挑発の対象の候補（出撃したステージの上忍と首領）
export type Candidate = {
	-- キャラクター ID
	id: string,
	gun: Gun.Gun,
	shuryo: boolean,
	-- 倒れているか
	defeated: boolean,
	-- もう誘い出されているか
	lured: boolean,
	x: number,
	z: number,
}

local Chohatsu = {}

-- (x, z) にいる gun の軍の発動者が誘い出す上忍のキャラクター ID を、候補の順に返す。
-- 誘い出せなければ空の一覧と失敗の理由（NoTarget か AlreadyActive）を返す
function Chohatsu.targetsOf(
	x: number,
	z: number,
	gun: Gun.Gun,
	candidates: { Candidate },
	params: Params?
): ({ string }, Hikei.UseFailure?)
	local p = params or Config.Chohatsu
	local result = {}
	local inRange = 0
	for _, candidate in candidates do
		if candidate.gun == gun or candidate.shuryo or candidate.defeated then
			continue
		end
		local dx, dz = candidate.x - x, candidate.z - z
		if math.sqrt(dx * dx + dz * dz) > p.Radius then
			continue
		end
		inRange += 1
		if not candidate.lured then
			table.insert(result, candidate.id)
		end
	end
	if inRange == 0 then
		return result, "NoTarget"
	elseif #result == 0 then
		return result, "AlreadyActive"
	end
	return result, nil
end

return Chohatsu
