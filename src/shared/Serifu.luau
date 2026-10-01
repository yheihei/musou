--!strict
-- 台詞の文と、会話窓・戦闘中の台詞の時間の計算。Roblox の API は使わない。
--
-- - 戦闘中の台詞は Remotes.PlaySerifu で台詞 ID を送り、クライアントがこの表から文を引く
-- - 話者（キャラクター ID）と表情は台詞とは別に送る。同じ文を別の表情で出せる
-- - ステージの台詞は、各ステージの台詞を作る issue（伊賀第1ステージは #125）で足す
-- - 送りの速さと表示時間は Config.luau の Serifu 節にある

local Config = require("./Config")

local Serifu = {}

local definitions: { [string]: string } = {
	-- 試験用の台詞。窓口の PlaySerifu で表示を確かめる
	ShikenTsujo = "戦の手を止めずに、この台詞を読めるか確かめる。",
	ShikenTanshuku = "参る！",
	ShikenNagai = "長い台詞が枠からはみ出さずに折り返されるか確かめるための台詞。峠を越えてきた風魔の先陣は、すでに門前の近くまで迫っている。持ちこたえろ。",
}

Serifu.definitions = definitions

-- 台詞 ID の文。表に無ければ nil
function Serifu.textOf(id: string): string?
	return definitions[id]
end

-- 文の長さ（文字の数）。日本語の1文字を1と数える
function Serifu.length(text: string): number
	return utf8.len(text) or #text
end

-- 会話窓で、文を全部出し終えるまでの秒数
function Serifu.typingTime(text: string): number
	return Serifu.length(text) * Config.Serifu.CharInterval
end

-- 会話窓で、文を出し始めてから次の台詞へ送るまでの秒数
function Serifu.lineTime(text: string): number
	return Serifu.typingTime(text) + Config.Serifu.HoldTime + Serifu.length(text) * Config.Serifu.HoldPerChar
end

-- 戦闘中の台詞の順番待ちに台詞を足す。上限を超えたら古いものから捨て、捨てた数を返す。queue を書き換える
function Serifu.enqueue<T>(queue: { T }, item: T): number
	table.insert(queue, item)
	local dropped = 0
	while #queue > Config.Serifu.BattleQueueMax do
		table.remove(queue, 1)
		dropped += 1
	end
	return dropped
end

return Serifu
