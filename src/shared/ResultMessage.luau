--!strict
-- ステージの結果（Remotes.StageResult）を、リザルト画面に出す文に直す。Roblox の API は使わない。
-- 勝敗の見出し、勝敗の理由（RemoteSchema.ResultReason）の文、経過時間、開放したステージの名前、得た巻物、
-- 上がった熟練度、新しく覚えた秘計の名前、リーダー以外への待ちの文を作り、届いた値の形を確かめる。
--
-- - 経過時間は「分:秒」で書く。分は桁をそろえず、60 分を超えても分で数える（0:05、12:34、75:00）
-- - 秒の端数は切り捨てる。負の値と数でない値は 0 秒にする

local Characters = require("./Characters")
local Hikei = require("./Hikei")
local Jukurendo = require("./Jukurendo")
local RemoteSchema = require("./RemoteSchema")
local Stages = require("./Stages")

local ResultMessage = {}

-- 勝敗の理由の文
local reasons: { [RemoteSchema.ResultReason]: string } = {
	TekigunShuryoGekiha = "敵軍の首領を討ち取った",
	TekigunHonjinSeiatsu = "敵軍の本陣を制圧した",
	MikatagunHonjinKanraku = "味方軍の本陣が陥落した",
	MikatagunShuryoGekiha = "味方軍の首領が討たれた",
	HeiryokuZero = "兵力が尽きた",
	TimeUp = "時間切れ",
}

ResultMessage.reasons = reasons

-- 勝敗の見出し
function ResultMessage.headline(victory: boolean): string
	return if victory then "勝利" else "敗北"
end

-- 勝敗の理由の文。表に無い理由はそのまま返す
function ResultMessage.reasonOf(reason: string): string
	return reasons[reason :: RemoteSchema.ResultReason] or reason
end

-- 経過時間（秒）を「分:秒」で書く
function ResultMessage.formatElapsed(seconds: number): string
	-- 数でない値（NaN）は比べると偽になるので、負の値と同じく 0 秒にする
	local total = if seconds > 0 then math.floor(seconds) else 0
	return string.format("%d:%02d", total // 60, total % 60)
end

-- 開放したステージの名前（「第1ステージ　風魔襲来」）。表に無い ID はそのまま返す
function ResultMessage.stageName(stageId: string): string
	local stage = Stages.get(stageId)
	return if stage then `第{stage.order}ステージ　{stage.displayName}` else stageId
end

-- 得た巻物の文（「刃の巻物　+5 本」）。表に無いキャラクターは ID のまま書く
function ResultMessage.makimonoOf(characterId: string, count: number): string
	local character = Characters.get(characterId)
	local name = if character then character.displayName else characterId
	return `{name}の巻物　+{count} 本`
end

-- 上がった熟練度の文（「武勇の熟練度　+12（撃破数 120）」）。表に無い系統は ID のまま書き、数を省く
function ResultMessage.jukurendoOf(keito: string, gain: number, count: number): string
	local name = Jukurendo.names[keito] or keito
	local countName = Jukurendo.countNames[keito]
	local suffix = if countName then `（{countName} {count}）` else ""
	return `{name}の熟練度　+{gain}{suffix}`
end

-- 新しく覚えた秘計の名前。定義に無い秘計は ID のまま書く
function ResultMessage.hikeiName(hikeiId: string): string
	local definition = Hikei.get(hikeiId)
	return if definition then definition.displayName else hikeiId
end

-- リーダー以外に出す待ちの文。リーダーの名前が分からなければ名前を省く
function ResultMessage.waitingFor(leaderName: string?): string
	if leaderName then
		return `リーダーの {leaderName} が次の行動を選んでいます`
	end
	return "リーダーが次の行動を選んでいます"
end

local function isStringList(value: unknown): boolean
	if type(value) ~= "table" then
		return false
	end
	for _, item in value :: { [unknown]: unknown } do
		if type(item) ~= "string" then
			return false
		end
	end
	return true
end

-- 文字列のキーから数を引く表か
local function isNumberMap(value: unknown): boolean
	if type(value) ~= "table" then
		return false
	end
	for key, item in value :: { [unknown]: unknown } do
		if type(key) ~= "string" or type(item) ~= "number" then
			return false
		end
	end
	return true
end

local function isMemberResult(value: unknown): boolean
	if type(value) ~= "table" then
		return false
	end
	local member = value :: { [string]: unknown }
	return type(member.userId) == "number"
		and type(member.name) == "string"
		and type(member.gekihasu) == "number"
		and type(member.seiatsusu) == "number"
		and type(member.kyuensu) == "number"
		and isStringList(member.newlyUnlocked)
		and type(member.character) == "string"
		and type(member.makimono) == "number"
		and isNumberMap(member.jukurendo)
		and isStringList(member.newlyLearned)
end

-- 届いた値をステージの結果として受け付けるか。理由は表に無い文字列も受け付ける（そのまま出す）
function ResultMessage.isResult(value: unknown): boolean
	if type(value) ~= "table" then
		return false
	end
	local result = value :: { [string]: unknown }
	if type(result.victory) ~= "boolean" or type(result.reason) ~= "string" or type(result.elapsed) ~= "number" then
		return false
	end
	if type(result.members) ~= "table" then
		return false
	end
	for _, member in result.members :: { [unknown]: unknown } do
		if not isMemberResult(member) then
			return false
		end
	end
	return true
end

return ResultMessage
