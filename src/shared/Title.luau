--!strict
-- ゲームのタイトルと、タイトル画面を出せるかの判断。タイトルの文字はここにだけ書き、
-- タイトル画面（クライアントの TitleController）はここから引く。
-- 非公式ファンゲームかつパラレル設定である旨の表記の文言は Notice.luau にある（タイトル画面もそこから引く）。
-- Roblox の API は使わない。

local RemoteSchema = require("./RemoteSchema")

local Title = {}

-- ゲームのタイトル。仮。#148 で開発者が決める。決まったら、ここだけを直す。
-- 仮の日本語は Studio のプレース名と同じ。英語は副題として小さく出す（英語対応は #162）
Title.name = {
	ja = "クリプト忍者バトルロイヤル",
	en = "Crypto Ninja Battle Royale",
}

-- 窓口の ShowTitle が書き換える Player の Attribute（数）。書き換わるたびに、本人の画面にタイトル画面をもう一度出す（確認用）
Title.REQUEST_ATTRIBUTE = "TitleRequest"

-- タイトル画面を出せるか。出撃メンバーとしてステージに出ている間（ロビー以外のフェーズで、待機中でないメンバー）は出さない。
-- phase は PartyState のフェーズ（届く前は nil）。active は本人が出撃するメンバー（パーティーにいて、待機中でない人）か
function Title.canShow(phase: RemoteSchema.Phase?, active: boolean): boolean
	return phase == nil or phase == "Lobby" or not active
end

return Title
