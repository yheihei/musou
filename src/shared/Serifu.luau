--!strict
-- 台詞の文と、会話窓・戦闘中の台詞の時間の計算。Roblox の API は使わない。
--
-- - 戦闘中の台詞は Remotes.PlaySerifu で台詞 ID を送り、クライアントがこの表から文を引く
-- - 話者（キャラクター ID）と表情は台詞とは別に送る。同じ文を別の表情で出せる
-- - 戦況に合わせて出す台詞（戦況の台詞）の、きっかけ・話者・表情は SenkyoSerifu.luau の表に台詞 ID で置く
-- - 送りの速さと表示時間は Config.luau の Serifu 節にある

local Config = require("./Config")

local Serifu = {}

local definitions: { [string]: string } = {
	-- 試験用の台詞。窓口の PlaySerifu で表示を確かめる
	ShikenTsujo = "戦の手を止めずに、この台詞を読めるか確かめる。",
	ShikenTanshuku = "参る！",
	ShikenNagai = "長い台詞が枠からはみ出さずに折り返されるか確かめるための台詞。峠を越えてきた風魔の先陣は、すでに門前の近くまで迫っている。持ちこたえろ。",

	-- 試験用ステージの戦況の台詞（SenkyoSerifu.luau の Test）。どのきっかけで出たかが分かる文にする
	ShikenKaishi = "試験の戦を始める。戦況の台詞を確かめるぞ。",
	ShikenSeiatsuTeki = "拠点を風魔に奪われた。取り返せ。",
	ShikenSeiatsuMikata = "風魔の拠点を奪ったぞ。",
	ShikenRakuseki = "落石で道を塞いでやった。",
	ShikenKoritsu = "兵站線が切れて、拠点が孤立した。救え。",
	ShikenSekkinNishi = "西の拠点はもらった！",
	ShikenTaikyuNishi = "西の拠点の耐久が半分を切った…。",
	ShikenOshi = "上忍3の部隊が交戦で押されている。助けに行け。",
	ShikenGekihaJonin3 = "不覚…。上忍3、下がります。",
	ShikenGekihaJonin1 = "上忍1、ここまでか…。",
	ShikenGekihaJonin2 = "上忍2、退く…。",
	ShikenGekihaTeki = "風魔の上忍を初めて退けたか。見事だ。",
	ShikenShutsugen = "来たか。試験の首領が相手をしてやる！",
	ShikenShuryoHanbun = "首領の体力が半分を切ったか…。",
	ShikenKishinka = "鬼神化の力、見せてやる！",
	ShikenKishu = "伏兵、今だ。奇襲せよ。",
	ShikenSekkinHonjin = "本陣に敵が迫っている！",
	ShikenHayateHanbun = "体力が半分を切った…。",
	ShikenNokori10 = "残りは10分だ。",
	ShikenNokori5 = "残りは5分だ。急げ！",
	ShikenHeiryoku = "兵力が残り1になった。無理はするな。",
	ShikenGekihaJin = "刃が敵の上忍を初めて倒した。",
	ShikenGekihaTorika = "酉花が敵の上忍を初めて倒しました。",
	ShikenGekihaSekishusai = "石舟斎が敵の上忍を初めて倒した。",
	ShikenGekihaKanaOni = "金鬼が敵の上忍を初めて倒したぞ。",

	-- 伊賀第1ステージの戦況の台詞（docs/story/iga-1.md の戦闘中の台詞の下書き）。確定版（#14）で変わったら直す。
	-- ID は Iga1 と台本の ID。NPC の上忍と首領が話す台詞は、人選が決まってから足す（#117）
	Iga1B01 = "ナルカミ、空から風魔の動きを見張れ",
	Iga1B02 = "拠点を奪われたか。取り返せ、兵站線を切らせるな",
	Iga1B05 = "兵站線が切れた！ 孤立した拠点を救え",
	Iga1B15 = "風魔の上忍を退けたか。見事だ",
	Iga1B20 = "本陣に敵が迫っている！ 誰か戻れるか",
	Iga1B21 = "くっ…ナルカミ、下がっていろ",
	Iga1B22 = "時が惜しい。峠の本陣を急げ",
	Iga1B23 = "日が高くなる前に決着をつけろ！",
	Iga1B24 = "兵が尽きかけている。無理はするな",
	Iga1BJ1 = "風は止んだ。次だ",
	Iga1BT1 = "毒は静かに効くものですよ",
	Iga1BS1 = "得物を奪うまでもなかったか",
	Iga1BK1 = "なまくらな得物だな。打ち直してから出直せ",
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
