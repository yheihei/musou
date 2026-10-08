--!strict
-- ステージの結果（Remotes.StageResult）を、リザルト画面に出す文に直す。Roblox の API は使わない。
-- 勝敗の見出し、勝敗の理由（RemoteSchema.ResultReason）の文、経過時間、開放したステージの名前、得た巻物、
-- リーダー以外への待ちの文を作り、届いた値の形を確かめる。
--
-- - 経過時間は「分:秒」で書く。分は桁をそろえず、60 分を超えても分で数える（0:05、12:34、75:00）
-- - 秒の端数は切り捨てる。負の値と数でない値は 0 秒にする

local Characters = require("./Characters")
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

local function isMemberResult(value: unknown): boolean
	if type(value) ~= "table" then
		return false
	end
	local member = value :: { [string]: unknown }
	return type(member.userId) == "number"
		and type(member.name) == "string"
		and type(member.gekihasu) == "number"
		and isStringList(member.newlyUnlocked)
		and type(member.character) == "string"
		and type(member.makimono) == "number"
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
