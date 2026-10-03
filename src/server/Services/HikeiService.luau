--!strict
-- 秘計の発動の入口。Remotes.Action の秘計の枚の番号を受けてサーバーで確かめ、秘計ごとに登録した処理を呼ぶ。
-- 発動の検証・使用記録・効果の時間管理は ReplicatedStorage.Shared.Hikei、効果時間と周期は Config.luau の Hikei 節にある。
-- 各秘計の中身（伏兵部隊や落石の岩など）は、各秘計の issue が register で処理を登録する。
--
-- - 発動者はプレイヤーと NPC の上忍・首領。プレイヤーは Remotes.Action（ActionService.onHikei）から、
--   上忍と首領は useByJonin（敵軍の AI）から使う
-- - 確かめる順は、戦闘のフェーズ、発動者が倒れていないか、枚の持ち込み、使用済み、処理の登録
-- - 処理が効果を出せなかった枚（対象が無いなど）は未使用のまま残す。処理のエラーも未使用のまま警告にする
-- - 発動したら使用済みにし、発動者の位置で、発動者の軍が得をする士気の出来事を知らせる（ShikiService）
-- - 効果は処理が addEffect で足す。期限切れは Config.luau の Hikei 節の TickInterval ごとに確かめ、
--   処理の finish を効果ごとに1回呼ぶ。打ち消し（dispelKyoka）とステージの終わりでも1回呼ぶ
-- - 出撃（StageService.started）で、ロビーで選んだ秘計を出撃メンバーの持ち込みとして決め、ステージの終わりまで変えない。
--   1枚も選んでいない人には、誰も選んでいない秘計を配る（Hikei.assignMochikomi）。上限より少なくても出撃できる
-- - 出撃で効果と使用記録を空にする。決着とロビーのフェーズへの戻りで残った効果を全部解除し、
--   ロビーのフェーズへ戻ったら持ち込みも外す
-- - プレイヤーの持ち込みと使用済みは、Player の Attribute の HikeiMochikomi・HikeiUsed（秘計 ID をカンマでつないだ文字列）で
--   クライアントへ複製する
-- - 発動・失敗・期限切れ・打ち消しは activated・failed・expired・dispelled で知らせる
-- - 同じものを Remotes.NotifyHikei（ReplicatedStorage.Shared.HikeiNotice）で画面に出させる。
--   発動・打ち消し・期限切れは出撃メンバー全員に、失敗はプレイヤーの本人だけに送る。
--   同じ発動者の同じ秘計の期限切れと打ち消しは、まとめて切れた分を1回だけ送る

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Ground = require(ReplicatedStorage.Shared.Ground)
local Gun = require(ReplicatedStorage.Shared.Gun)
local Hikei = require(ReplicatedStorage.Shared.Hikei)
local HikeiNotice = require(ReplicatedStorage.Shared.HikeiNotice)
local Jonin = require(ReplicatedStorage.Shared.Jonin)
local RemoteSchema = require(ReplicatedStorage.Shared.RemoteSchema)
local StagePhase = require(ReplicatedStorage.Shared.StagePhase)
local DebugCommand = require(script.Parent.Parent.DebugCommand)
local ActionService = require(script.Parent.ActionService)
local JoninService = require(script.Parent.JoninService)
local SelectionService = require(script.Parent.SelectionService)
local ShikiService = require(script.Parent.ShikiService)
local StageService = require(script.Parent.StageService)

-- 処理に渡す発動の中身
export type Context = {
	hikei: string,
	-- 発動者の ID（プレイヤーは UserId の文字列、上忍と首領はキャラクター ID）
	user: string,
	-- 画面に出す発動者の名前
	userName: string,
	gun: Gun.Gun,
	-- 発動者がプレイヤーなら Player、上忍か首領ならキャラクター ID
	player: Player?,
	jonin: string?,
	-- 発動者の位置
	position: Vector3,
	now: number,
}

-- 効果が終わった理由。Expired は期限切れ、Dispelled は打ち消し、StageEnd はステージの終わり、Ended は処理が自分で終えた
export type FinishReason = "Expired" | "Dispelled" | "StageEnd" | "Ended"

export type Handler = {
	-- 秘計を発動する。効果を出せたら true、出せなければ false と失敗の理由（省くと NoTarget）を返す
	activate: (context: Context) -> (boolean, Hikei.UseFailure?),
	-- 効果が終わったときに、効果ごとに1回呼ぶ
	finish: ((effect: Hikei.Effect, reason: FinishReason) -> ())?,
}

local HikeiService = {}

-- 同じ発動者の同じ秘計の期限切れと打ち消しを、まとめて1回の知らせにする秒数
local NOTICE_MERGE_TIME = 1

local handlers: { [string]: Handler } = {}
-- 窓口で登録した仮の処理の秘計
local kariHandlers: { [string]: boolean } = {}
-- 発動者の ID から引く持ち込み
local mochikomiOf: { [string]: { string } } = {}
local usage: Hikei.Usage = Hikei.newUsage()
local effects: { Hikei.Effect } = Hikei.newEffects()
local noticeRemote: RemoteEvent
-- 知らせの種類・発動者・秘計から引く、最後に送った時刻（os.clock）
local lastNotice: { [string]: number } = {}

local activatedEvent = Instance.new("BindableEvent")
-- 発動したときに、発動者の ID・発動者の名前・発動者の軍・秘計 ID で発火する
HikeiService.activated = activatedEvent.Event
local failedEvent = Instance.new("BindableEvent")
-- 発動できなかったときに、発動者の ID・秘計 ID（枚が無ければ nil）・失敗の理由で発火する
HikeiService.failed = failedEvent.Event
local expiredEvent = Instance.new("BindableEvent")
-- 効果の期限が切れたときに、発動者の ID・発動者の名前・発動者の軍・秘計 ID・対象の ID で発火する
HikeiService.expired = expiredEvent.Event
local dispelledEvent = Instance.new("BindableEvent")
-- 効果を打ち消したときに、発動者の ID・発動者の名前・発動者の軍・秘計 ID・対象の ID で発火する
HikeiService.dispelled = dispelledEvent.Event

-- 効果の時刻。クライアントと同じ時計を使う
function HikeiService.now(): number
	return workspace:GetServerTimeNow()
end

-- 秘計の処理を登録する。同じ秘計は1回だけ（窓口の仮の処理は本物の処理で置き換えられる）
function HikeiService.register(hikeiId: string, handler: Handler)
	assert(Hikei.get(hikeiId) ~= nil, `HikeiService: 秘計 {hikeiId} は定義に無い`)
	assert(handlers[hikeiId] == nil or kariHandlers[hikeiId], `HikeiService: {hikeiId} は登録済み`)
	handlers[hikeiId] = handler
	kariHandlers[hikeiId] = nil
end

local function userIdOf(player: Player): string
	return tostring(player.UserId)
end

local function playerOf(user: string): Player?
	local userId = tonumber(user)
	return if userId then Players:GetPlayerByUserId(userId) else nil
end

-- 発動者の画面に出す名前
local function nameOf(user: string): string
	local player = playerOf(user)
	if player then
		return player.DisplayName
	end
	local jonin = JoninService.get(user)
	return if jonin then jonin.displayName else user
end

-- プレイヤーの持ち込みと使用済みを Attribute に書く
local function publish(player: Player)
	local user = userIdOf(player)
	local mochikomi = mochikomiOf[user] or {}
	player:SetAttribute(Hikei.MOCHIKOMI_ATTRIBUTE, Hikei.encodeList(mochikomi))
	player:SetAttribute(Hikei.USED_ATTRIBUTE, Hikei.encodeList(Hikei.usedOf(usage, user, mochikomi)))
end

local function setMochikomiOf(user: string, ids: { string }): RemoteSchema.RejectReason?
	local reject = Hikei.checkMochikomi(ids, {})
	if reject then
		return reject
	end
	mochikomiOf[user] = table.clone(ids)
	return nil
end

-- プレイヤーの持ち込みを決める。受け付けたら nil、上限を超えるか重なりがあれば理由を返す
function HikeiService.setMochikomi(player: Player, ids: { string }): RemoteSchema.RejectReason?
	local reject = setMochikomiOf(userIdOf(player), ids)
	if not reject then
		publish(player)
	end
	return reject
end

-- 上忍か首領の持ち込みを決める。受け付けたら nil、上限を超えるか重なりがあれば理由を返す
function HikeiService.setJoninMochikomi(joninId: string, ids: { string }): RemoteSchema.RejectReason?
	return setMochikomiOf(joninId, ids)
end

-- プレイヤーの持ち込み（枚の順）
function HikeiService.getMochikomi(player: Player): { string }
	return table.clone(mochikomiOf[userIdOf(player)] or {})
end

-- 使用記録を空にし、プレイヤーの使用済みの Attribute を書き直す
function HikeiService.resetUsage()
	usage = Hikei.newUsage()
	for _, player in Players:GetPlayers() do
		publish(player)
	end
end

-- 効果を足して返す。処理の activate の中で呼ぶ。足せなければ nil（Hikei.addEffect）
function HikeiService.addEffect(request: Hikei.EffectRequest): Hikei.Effect?
	return Hikei.addEffect(effects, request)
end

-- 期限内の効果の一覧（表は写し）
function HikeiService.getEffects(): { Hikei.Effect }
	return table.clone(effects)
end

local function callFinish(effect: Hikei.Effect, reason: FinishReason)
	local handler = handlers[effect.hikei]
	local finish = handler and handler.finish
	if not finish then
		return
	end
	local ok, err = pcall(finish, effect, reason)
	if not ok then
		warn(`HikeiService: {effect.hikei} の効果を終えられなかった: {err}`)
	end
end

-- 効果を一覧から外し、処理の finish を1回呼ぶ（処理が自分で効果を終えるとき）。一覧に無ければ false
function HikeiService.finishEffect(effect: Hikei.Effect, reason: FinishReason?): boolean
	local index = table.find(effects, effect)
	if not index then
		return false
	end
	table.remove(effects, index)
	callFinish(effect, reason or "Ended")
	return true
end

-- gun の相手の軍がかけた強化の秘計の効果を打ち消し、外した効果を返す（大喝）。targets を渡すと、その対象の効果だけ
function HikeiService.dispelKyoka(gun: Gun.Gun, targets: { string }?): { Hikei.Effect }
	local taken = Hikei.dispelKyoka(effects, gun, HikeiService.now(), targets)
	for _, effect in taken do
		callFinish(effect, "Dispelled")
		dispelledEvent:Fire(effect.user, nameOf(effect.user), effect.gun, effect.hikei, effect.target)
	end
	return taken
end

-- 残った効果をすべて解除する（ステージの終わり）
local function finishAll()
	local remaining = table.clone(effects)
	table.clear(effects)
	for _, effect in remaining do
		callFinish(effect, "StageEnd")
	end
end

-- 期限の切れた効果を外し、処理の finish を1回ずつ呼ぶ
local function expire()
	for _, effect in Hikei.takeExpired(effects, HikeiService.now()) do
		callFinish(effect, "Expired")
		expiredEvent:Fire(effect.user, nameOf(effect.user), effect.gun, effect.hikei, effect.target)
	end
end

type User = {
	id: string,
	name: string,
	gun: Gun.Gun,
	player: Player?,
	jonin: string?,
	-- 倒れていなければ位置。倒れていれば nil
	position: Vector3?,
}

local function playerUser(player: Player): User
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local alive = humanoid ~= nil and humanoid.Health > 0 and root ~= nil
	return {
		id = userIdOf(player),
		name = player.DisplayName,
		gun = "Mikatagun",
		player = player,
		jonin = nil,
		position = if alive and root then root.Position else nil,
	}
end

local function joninUser(jonin: Jonin.Jonin): User
	local position: Vector3? = nil
	if not Jonin.isDefeated(jonin) then
		local y = Ground.heightAt(jonin.position.x, jonin.position.z) or 0
		position = Vector3.new(jonin.position.x, y, jonin.position.z)
	end
	return {
		id = jonin.id,
		name = jonin.displayName,
		gun = jonin.gun,
		player = nil,
		jonin = jonin.id,
		position = position,
	}
end

-- slot 番目の枚を発動する。発動したら true と秘計 ID、できなければ false と秘計 ID（枚が無ければ nil）と失敗の理由を返す
local function use(user: User, slot: number): (boolean, string?, Hikei.UseFailure?)
	local mochikomi = mochikomiOf[user.id] or {}
	local check = { battle = StageService.getPhase() == "Battle", alive = user.position ~= nil }
	local hikeiId, failure = Hikei.checkActivation(check, usage, user.id, mochikomi, slot)
	local handler = if hikeiId then handlers[hikeiId] else nil
	if hikeiId and not handler then
		failure = "NotReady"
	end
	if not hikeiId or not handler then
		local reason: Hikei.UseFailure = failure or "NoSlot"
		failedEvent:Fire(user.id, mochikomi[slot], reason)
		return false, mochikomi[slot], reason
	end
	local id = hikeiId :: string
	local position = user.position :: Vector3
	local context: Context = {
		hikei = id,
		user = user.id,
		userName = user.name,
		gun = user.gun,
		player = user.player,
		jonin = user.jonin,
		position = position,
		now = HikeiService.now(),
	}
	local ok, activated, activateFailure = pcall(handler.activate, context)
	if not ok then
		warn(`HikeiService: {id} を発動できなかった: {activated}`)
	end
	if not ok or not activated then
		local reason: Hikei.UseFailure = if ok and activateFailure then activateFailure else "NoTarget"
		failedEvent:Fire(user.id, id, reason)
		return false, id, reason
	end
	Hikei.markUsed(usage, user.id, id)
	if user.player then
		publish(user.player)
	end
	ShikiService.notify("Hikei", { x = position.X, z = position.Z }, user.gun)
	activatedEvent:Fire(user.id, user.name, user.gun, id)
	return true, id, nil
end

-- プレイヤーが slot 番目の枚を発動する。発動したら true と秘計 ID、できなければ false と秘計 ID と失敗の理由を返す
function HikeiService.useByPlayer(player: Player, slot: number): (boolean, string?, Hikei.UseFailure?)
	return use(playerUser(player), slot)
end

-- 上忍か首領が slot 番目の枚を発動する。出撃したステージにいなければ false
function HikeiService.useByJonin(joninId: string, slot: number): (boolean, string?, Hikei.UseFailure?)
	local jonin = JoninService.get(joninId)
	if not jonin then
		return false, nil, "NoSlot"
	end
	return use(joninUser(jonin), slot)
end

-- 出撃したら、前のステージの効果を解除し、ロビーで選んだ秘計を持ち込みとして決めて、使用記録を空にする。
-- 1枚も選んでいない人には、誰も選んでいない秘計を配る
local function onStarted(info: StageService.StartInfo)
	finishAll()
	table.clear(mochikomiOf)
	local selections = {}
	for index, member in info.members do
		selections[index] = SelectionService.getHikei(member)
	end
	for index, mochikomi in Hikei.assignMochikomi(selections) do
		local member = info.members[index]
		local reject = setMochikomiOf(userIdOf(member), mochikomi)
		if reject then
			warn(`HikeiService: {member.Name} の持ち込みを決められなかった（{reject}）`)
		end
	end
	HikeiService.resetUsage()
end

-- ロビーのフェーズへ戻ったら、効果を解除し、持ち込みと使用記録を外す
local function onLobby()
	finishAll()
	table.clear(mochikomiOf)
	table.clear(lastNotice)
	HikeiService.resetUsage()
end

local function onPlayerRemoving(player: Player)
	mochikomiOf[userIdOf(player)] = nil
end

-- 出撃メンバー全員に知らせを送る。merge なら、同じ種類・発動者・秘計の知らせを NOTICE_MERGE_TIME 秒に1回にする
local function notifyMembers(notice: HikeiNotice.Notice, user: string, merge: boolean)
	if merge then
		local key = `{notice.kind}|{user}|{notice.hikei}`
		local now = os.clock()
		local last = lastNotice[key]
		if last and now - last < NOTICE_MERGE_TIME then
			return
		end
		lastNotice[key] = now
	end
	for _, member in StageService.getMembers() do
		noticeRemote:FireClient(member, notice)
	end
end

local function connectNotices()
	HikeiService.activated:Connect(function(user: string, userName: string, gun: Gun.Gun, hikeiId: string)
		notifyMembers({ kind = "Hatsudo", hikei = hikeiId, userName = userName, gun = gun, reason = nil }, user, false)
	end)
	HikeiService.expired:Connect(function(user: string, userName: string, gun: Gun.Gun, hikeiId: string)
		notifyMembers({ kind = "Kigengire", hikei = hikeiId, userName = userName, gun = gun, reason = nil }, user, true)
	end)
	HikeiService.dispelled:Connect(function(user: string, userName: string, gun: Gun.Gun, hikeiId: string)
		notifyMembers({ kind = "Uchikeshi", hikei = hikeiId, userName = userName, gun = gun, reason = nil }, user, true)
	end)
	HikeiService.failed:Connect(function(user: string, hikeiId: string?, reason: Hikei.UseFailure)
		local player = playerOf(user)
		if not player then
			return
		end
		noticeRemote:FireClient(
			player,
			{
				kind = "Shippai",
				hikei = hikeiId,
				userName = player.DisplayName,
				gun = "Mikatagun",
				reason = reason,
			} :: HikeiNotice.Notice
		)
	end)
end

-- 窓口で渡された名前を、プレイヤーか上忍・首領の発動者の ID にする
local function findUser(name: unknown): (Player?, string?)
	if type(name) ~= "string" then
		return nil, nil
	end
	local player = Players:FindFirstChild(name)
	if player and player:IsA("Player") then
		return player, nil
	end
	if JoninService.get(name) then
		return nil, name
	end
	return nil, nil
end

-- 窓口の引数の秘計 ID を並べる。カンマでつないだ1つの文字列でも、別々の引数でもよい
local function idsFromArgs(...: any): { string }
	local ids = {}
	for _, value in { ... } do
		if type(value) == "string" then
			for id in string.gmatch(value, "[^,%s]+") do
				table.insert(ids, id)
			end
		end
	end
	return ids
end

local function round(value: number): number
	return math.round(value * 10) / 10
end

local function registerDebugCommands()
	DebugCommand.register(
		"SetHikeiMochikomi",
		"<プレイヤー名かキャラクター ID> [秘計 ID...]",
		"プレイヤーか上忍・首領の持ち込みを決める（カンマでつないでもよい。何も渡さなければ空にする）",
		function(name, ...)
			local player, joninId = findUser(name)
			if not player and not joninId then
				error(
					`{tostring(name)} はプレイヤーにも出撃したステージの上忍と首領にもいない`,
					0
				)
			end
			local ids = idsFromArgs(...)
			local reject = if player
				then HikeiService.setMochikomi(player, ids)
				else HikeiService.setJoninMochikomi(joninId :: string, ids)
			local who = if player then player.Name else joninId
			if reject then
				return `{who} の持ち込みを拒否した（{reject}）`
			end
			return `{who} の持ち込みを {if #ids > 0 then table.concat(ids, "、") else "なし"} にした`
		end
	)
	DebugCommand.register("ResetHikeiUsage", "", "秘計の使用記録を空にする（確認用）", function()
		HikeiService.resetUsage()
		return "秘計の使用記録を空にした"
	end)
	DebugCommand.register(
		"UseHikei",
		"<プレイヤー名かキャラクター ID> <枚の番号>",
		"プレイヤーか上忍・首領に、持ち込んだ秘計の枚を発動させる",
		function(name, value)
			local player, joninId = findUser(name)
			if not player and not joninId then
				error(
					`{tostring(name)} はプレイヤーにも出撃したステージの上忍と首領にもいない`,
					0
				)
			end
			local slot = DebugCommand.toNumber(value, "枚の番号")
			local ok, hikeiId, failure
			if player then
				ok, hikeiId, failure = HikeiService.useByPlayer(player, slot)
			else
				ok, hikeiId, failure = HikeiService.useByJonin(joninId :: string, slot)
			end
			local who = if player then player.Name else joninId
			if not ok then
				return `{who} の {slot} 枚目（{tostring(hikeiId)}）は発動しなかった（{failure}）`
			end
			return `{who} が {hikeiId} を発動した`
		end
	)
	DebugCommand.register(
		"RegisterKariHikei",
		"<秘計 ID> [効果の秒数]",
		"秘計に仮の処理を登録する。発動者自身に効果を足し、期限で解除したらコンソールに出す（確認用。本物の処理があれば登録しない）",
		function(hikeiId, value)
			if type(hikeiId) ~= "string" or not Hikei.get(hikeiId) then
				error(
					`秘計 ID は {table.concat(Hikei.selectable(), "、")} のどれか（{tostring(hikeiId)}）`,
					0
				)
			end
			if handlers[hikeiId] and not kariHandlers[hikeiId] then
				return `{hikeiId} には本物の処理があるので、仮の処理は登録しなかった`
			end
			local duration = if value ~= nil then DebugCommand.toNumber(value, "効果の秒数") else nil
			handlers[hikeiId] = {
				activate = function(context: Context): (boolean, Hikei.UseFailure?)
					local effect = HikeiService.addEffect({
						hikei = context.hikei,
						user = context.user,
						gun = context.gun,
						target = context.user,
						targetGun = nil,
						now = context.now,
						duration = duration,
					})
					print(`[Hikei] {context.userName} が仮の処理の {context.hikei} を発動した`)
					return effect ~= nil, nil
				end,
				finish = function(effect: Hikei.Effect, reason: FinishReason)
					print(
						`[Hikei] 仮の処理の {effect.hikei}（{nameOf(effect.user)}）の効果を解除した（{reason}）`
					)
				end,
			}
			kariHandlers[hikeiId] = true
			local seconds = duration or Hikei.durationOf(hikeiId)
			local length = if seconds == math.huge then "期限なし" else `{seconds} 秒`
			return `{hikeiId} に仮の処理を登録した（効果 {length}）`
		end
	)
	DebugCommand.register(
		"DispelKyoka",
		"<打ち消す側の軍>",
		"相手の軍がかけた強化の秘計の効果を打ち消す（大喝の打ち消しだけ。確認用）",
		function(gun)
			if not Gun.isGun(gun) then
				error("打ち消す側の軍は Mikatagun か Tekigun で指定する", 0)
			end
			local taken = HikeiService.dispelKyoka(gun :: Gun.Gun)
			return `強化の秘計の効果を {#taken} 個打ち消した`
		end
	)
	DebugCommand.register(
		"DumpHikei",
		"",
		"秘計の持ち込み・使用済み・効果・登録済みの処理を JSON で返す",
		function()
			local now = HikeiService.now()
			local users = {}
			for user, mochikomi in mochikomiOf do
				table.insert(users, {
					user = user,
					name = nameOf(user),
					mochikomi = mochikomi,
					used = Hikei.usedOf(usage, user, mochikomi),
				})
			end
			local list = {}
			for _, effect in effects do
				table.insert(list, {
					hikei = effect.hikei,
					user = effect.user,
					gun = effect.gun,
					target = effect.target,
					remaining = if effect.expiresAt == math.huge then "期限なし" else round(effect.expiresAt - now),
				})
			end
			local registered = {}
			for id in handlers do
				table.insert(registered, if kariHandlers[id] then `{id}（仮）` else id)
			end
			table.sort(registered)
			return HttpService:JSONEncode({ mochikomi = users, effects = list, handlers = registered })
		end
	)
end

function HikeiService.start()
	noticeRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("NotifyHikei") :: RemoteEvent
	connectNotices()
	ActionService.onHikei(function(player: Player, slot: number)
		HikeiService.useByPlayer(player, slot)
	end)
	StageService.started:Connect(onStarted)
	StageService.finished:Connect(finishAll)
	StageService.phaseChanged:Connect(function(next: StagePhase.Phase)
		if next == "Lobby" then
			onLobby()
		end
	end)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	registerDebugCommands()

	task.spawn(function()
		while true do
			task.wait(Config.Hikei.TickInterval)
			-- 1回の失敗で期限の確認が止まらないよう、失敗は警告にして次の間隔で続ける
			local ok, err = pcall(expire)
			if not ok then
				warn(`HikeiService: 秘計の効果の期限を確かめられなかった: {err}`)
			end
		end
	end)
end

return HikeiService
