--!strict
-- 勝敗の判定。同時に起きた勝ちと負けの条件の集まりから、勝ったかと理由を決める。
-- 条件は勝敗の理由（RemoteSchema.ResultReason）と同じ値で表す（敵軍の首領の撃破なら TekigunShuryoGekiha）。
-- Roblox の API は使わない。
--
-- - 勝ちは敵軍の首領の撃破（TekigunShuryoGekiha）と、敵軍の本陣の制圧（TekigunHonjinSeiatsu）
-- - 負けは味方軍の首領の撃破（MikatagunShuryoGekiha）、味方軍の本陣の陥落（MikatagunHonjinKanraku）、
--   兵力0の状態でプレイヤーが倒れたこと（HeiryokuZero）、時間切れ（TimeUp）
-- - 勝ちと負けが同時に起きたら負けを優先する
-- - 勝ちどうし・負けどうしが同時なら、reasonOrder の順（首領の撃破・本陣・兵力0・時間切れ）で先の理由にする

local Gun = require("./Gun")
local RemoteSchema = require("./RemoteSchema")

-- 勝敗。勝ったかと、その理由
export type Shohai = {
	victory: boolean,
	reason: RemoteSchema.ResultReason,
}

local Shohai = {}

-- 同じ勝ち負けの条件が同時に起きたときに、理由として選ぶ順
Shohai.reasonOrder = {
	"TekigunShuryoGekiha",
	"MikatagunShuryoGekiha",
	"TekigunHonjinSeiatsu",
	"MikatagunHonjinKanraku",
	"HeiryokuZero",
	"TimeUp",
} :: { RemoteSchema.ResultReason }

-- 勝ちの理由
local VICTORY: { [RemoteSchema.ResultReason]: boolean } = {
	TekigunShuryoGekiha = true,
	TekigunHonjinSeiatsu = true,
}

-- 理由が勝ちか
function Shohai.isVictory(reason: RemoteSchema.ResultReason): boolean
	return VICTORY[reason] == true
end

-- 首領が倒れたときの条件。gun は倒れた首領の軍
function Shohai.shuryoGekihaOf(gun: Gun.Gun): RemoteSchema.ResultReason
	return if gun == "Tekigun" then "TekigunShuryoGekiha" else "MikatagunShuryoGekiha"
end

-- 本陣が制圧されたときの条件。gun は制圧された本陣の元の軍
function Shohai.honjinSeiatsuOf(gun: Gun.Gun): RemoteSchema.ResultReason
	return if gun == "Tekigun" then "TekigunHonjinSeiatsu" else "MikatagunHonjinKanraku"
end

-- 同時に起きた条件の集まりから勝敗を決める。負けの条件が1つでもあれば負けにし、
-- 理由は同じ勝ち負けの条件のうち reasonOrder の順で先のもの。条件が無ければ nil
function Shohai.judge(conditions: { RemoteSchema.ResultReason }): Shohai?
	local found: Shohai? = nil
	for _, reason in Shohai.reasonOrder do
		if not table.find(conditions, reason) then
			continue
		end
		local victory = Shohai.isVictory(reason)
		if not found or (found.victory and not victory) then
			found = { victory = victory, reason = reason }
		end
	end
	return found
end

return Shohai
