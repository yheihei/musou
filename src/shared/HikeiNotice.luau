--!strict
-- 秘計の知らせ（Remotes.NotifyHikei）の中身と、画面に出す文。Roblox の API は使わない。
--
-- - 発動・打ち消し・期限切れは出撃メンバー全員に、失敗は発動しようとした本人だけに送る
-- - 画面には秘計の名前を見出しに、誰の秘計がどうなったかを添える。色は発動者の軍の色にする（失敗は灰色）

local Gun = require("./Gun")
local Hikei = require("./Hikei")

-- 知らせの種類。発動、打ち消し、期限切れ、失敗
export type Kind = "Hatsudo" | "Uchikeshi" | "Kigengire" | "Shippai"

export type Notice = {
	kind: Kind,
	-- 秘計 ID。持ち込んでいない番号の失敗では nil
	hikei: string?,
	-- 画面に出す発動者の名前
	userName: string,
	-- 発動者の軍
	gun: Gun.Gun,
	-- 失敗の理由。失敗のときだけある
	reason: Hikei.UseFailure?,
}

local HikeiNotice = {}

HikeiNotice.kinds = { "Hatsudo", "Uchikeshi", "Kigengire", "Shippai" } :: { Kind }

-- 失敗の理由の文
local failureMessages: { [Hikei.UseFailure]: string } = {
	NoSlot = "その番号の秘計は持ち込んでいません",
	Used = "この戦いで使用済みです",
	NotBattle = "戦闘中だけ使えます",
	Down = "倒れている間は使えません",
	NotReady = "この秘計はまだ使えません",
	NoTarget = "近くに対象がありません",
	AlreadyActive = "すでに効果が出ています",
}

HikeiNotice.failureMessages = failureMessages

-- 届いた値を知らせとして受け付けるか
function HikeiNotice.isNotice(value: unknown): boolean
	if type(value) ~= "table" then
		return false
	end
	local notice = value :: { [string]: unknown }
	if not table.find(HikeiNotice.kinds, notice.kind :: any) or not Gun.isGun(notice.gun) then
		return false
	end
	if type(notice.userName) ~= "string" then
		return false
	end
	if notice.hikei ~= nil and (type(notice.hikei) ~= "string" or not Hikei.get(notice.hikei :: string)) then
		return false
	end
	if notice.kind == "Shippai" then
		return table.find(Hikei.useFailures, notice.reason :: any) ~= nil
	end
	return notice.hikei ~= nil
end

-- 見出しに出す秘計の名前。秘計の無い失敗は「秘計」
function HikeiNotice.titleOf(notice: Notice): string
	local definition = if notice.hikei then Hikei.get(notice.hikei) else nil
	return if definition then definition.displayName else "秘計"
end

-- 見出しに添える文
function HikeiNotice.detailOf(notice: Notice): string
	if notice.kind == "Hatsudo" then
		return `{notice.userName}が発動`
	elseif notice.kind == "Uchikeshi" then
		return `{notice.userName}の効果が打ち消された`
	elseif notice.kind == "Kigengire" then
		return `{notice.userName}の効果が切れた`
	end
	local reason = notice.reason
	return if reason then failureMessages[reason] or reason else "使えません"
end

return HikeiNotice
