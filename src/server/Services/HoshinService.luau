--!strict
-- 上忍が部隊を率いて、配置で決めた方針（攻略・防衛・救援）に沿って部隊の目的地を決める。
-- 判断は ReplicatedStorage.Shared.Hoshin、間隔と距離は Config.luau の Hoshin 節にある。
--
-- - 動かすのは、配置の構成で方針を決めた部隊（率いる上忍のいない守備の部隊も含む）。
--   補充で作った守備の部隊、秘計や窓口で足した部隊は動かさない
-- - 担当の拠点は、配置で部隊が始まる拠点
-- - 戦闘のフェーズの間、Config.luau の Hoshin 節の Interval ごとに判断し直す
-- - 拠点を目指すときは、つながりの経由点をたどって道筋の次の拠点へ向かう（ButaiService.moveToKyoten）。
--   着いたら判断し直して、その次の拠点へ向かう。道筋の上で着いていても拠点の範囲の外にいれば、拠点の中心へ戻る
-- - 迎え撃つときは、相手の部隊の今の位置へまっすぐ向かう。判断し直すたびに向かう先を相手の位置に合わせる
-- - 交戦中と、交戦中の敵の手前で待っている間、部隊は動かない（ButaiService）。目的地だけを決めておく
-- - 道のりはつながりの経由点を含めた長さで測る。その軍が通れないつながり（落石）は通らない
-- - 外から目的地を差し替えた部隊（override）は、差し替えている間は判断で目的地を変えない（挑発などに使う）
-- - 首領は動かさない。本陣の範囲にとどまる（JoninService.setPosition）
-- - 窓口の SetHoshinAI で判断を止められる（確認用）。止めても部隊は今の目的地へ進む

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Butai = require(ReplicatedStorage.Shared.Butai)
local Config = require(ReplicatedStorage.Shared.Config)
local Haichi = require(ReplicatedStorage.Shared.Haichi)
local Hoshin = require(ReplicatedStorage.Shared.Hoshin)
local Kyoten = require(ReplicatedStorage.Shared.Kyoten)
local StagePhase = require(ReplicatedStorage.Shared.StagePhase)
local DebugCommand = require(script.Parent.Parent.DebugCommand)
local ButaiService = require(script.Parent.ButaiService)
local HeitansenService = require(script.Parent.HeitansenService)
local KyotenService = require(script.Parent.KyotenService)
local StageService = require(script.Parent.StageService)

-- 方針で動かす部隊の、配置で決めた方針と担当の拠点
type Entry = {
	hoshin: Haichi.Hoshin,
	tanto: string,
}

-- 外から差し替えた目的地。拠点か位置のどちらか。untilTime（os.clock）を過ぎたら方針の判断に戻す
type Override = {
	kyoten: string?,
	position: Butai.Point?,
	untilTime: number?,
}

local HoshinService = {}

-- 部隊 ID から引く、方針と担当の拠点
local entries: { [string]: Entry } = {}
-- 部隊 ID から引く、外から差し替えた目的地
local overrides: { [string]: Override } = {}
-- 部隊 ID から引く、最後の判断（窓口で見る）
local decisions: { [string]: Hoshin.Decision } = {}
local enabled = true

-- 部隊の方針。方針で動かさない部隊は nil
function HoshinService.hoshinOf(butaiId: string): Haichi.Hoshin?
	local entry = entries[butaiId]
	return if entry then entry.hoshin else nil
end

-- 方針の判断に渡す拠点の一覧
local function kyotenInputs(): { Hoshin.Kyoten }
	local result = {}
	for _, kyoten in KyotenService.list() do
		local center = KyotenService.centerOf(kyoten.id)
		if center then
			table.insert(result, {
				id = kyoten.id,
				gun = kyoten.gun,
				x = center.x,
				z = center.z,
				taikyuRate = kyoten.taikyu / Kyoten.maxTaikyu(kyoten.honjin),
				kogeki = KyotenService.kogekiOf(kyoten.id) > 0,
			})
		end
	end
	return result
end

-- 方針の判断に渡すつながりの一覧。道のりは両端の拠点の中心と経由点をたどった長さ
local function tsunagariInputs(): { Hoshin.Tsunagari }
	local result = {}
	local loaded = KyotenService.getHaichi()
	if not loaded then
		return result
	end
	for _, tsunagari in loaded.tsunagari do
		local from = KyotenService.centerOf(tsunagari.kyotenA)
		local to = KyotenService.centerOf(tsunagari.kyotenB)
		if not from or not to then
			continue
		end
		local length = 0
		local previous = Vector2.new(from.x, from.z)
		for _, point in tsunagari.keiyuten do
			local current = Vector2.new(point.X, point.Z)
			length += (current - previous).Magnitude
			previous = current
		end
		length += (Vector2.new(to.x, to.z) - previous).Magnitude
		table.insert(result, {
			kyotenA = tsunagari.kyotenA,
			kyotenB = tsunagari.kyotenB,
			length = length,
			blocked = HeitansenService.blockedOf(tsunagari.kyotenA, tsunagari.kyotenB),
		})
	end
	return result
end

-- 迎え撃つ候補の部隊（兵数のある部隊）
local function tekiInputs(): { Hoshin.Teki }
	local result = {}
	for _, butai in ButaiService.list() do
		if butai.heisu > 0 then
			table.insert(result, { id = butai.id, gun = butai.gun, position = butai.position })
		end
	end
	return result
end

-- 判断に沿って部隊の目的地を決める。同じ先へ向かっている間は決め直さない（経由点をたどり直さない）
local function apply(butai: Butai.Butai, decision: Hoshin.Decision)
	if decision.kind == "Kyoten" then
		local target = decision.kyoten :: string
		local next = decision.next
		if next then
			if butai.mokutekiKyoten ~= next then
				ButaiService.moveToKyoten(butai.id, next)
			end
		elseif not KyotenService.contains(target, butai.position) then
			-- 道筋の上では着いているが、迎え撃った帰りなどで拠点の範囲の外にいる
			if butai.mokutekiKyoten ~= target then
				ButaiService.moveToKyoten(butai.id, target)
			end
		elseif butai.mokutekichi then
			ButaiService.setMokutekichi(butai.id, nil)
		end
	elseif decision.kind == "Butai" then
		ButaiService.setMokutekichi(butai.id, decision.position)
	elseif butai.mokutekichi then
		ButaiService.setMokutekichi(butai.id, nil)
	end
end

-- 差し替えた目的地へ向かわせる。期限を過ぎていたら外して false
local function applyOverride(butai: Butai.Butai, override: Override, now: number): boolean
	local untilTime = override.untilTime
	if untilTime and now >= untilTime then
		overrides[butai.id] = nil
		return false
	end
	local kyoten = override.kyoten
	if kyoten then
		if butai.mokutekiKyoten ~= kyoten and not KyotenService.contains(kyoten, butai.position) then
			ButaiService.moveToKyoten(butai.id, kyoten)
		end
	elseif override.position then
		local position = override.position :: Butai.Point
		local mokutekichi = butai.mokutekichi
		if not mokutekichi or mokutekichi.x ~= position.x or mokutekichi.z ~= position.z then
			ButaiService.setMokutekichi(butai.id, position)
		end
	end
	return true
end

-- 方針で動かす部隊の目的地を決め直す
local function think()
	if not enabled or StageService.getPhase() ~= "Battle" then
		return
	end
	local kyotenList = kyotenInputs()
	local tsunagariList = tsunagariInputs()
	local tekiList = tekiInputs()
	local now = os.clock()
	for _, butai in ButaiService.list() do
		local entry = entries[butai.id]
		if not entry then
			continue
		end
		local override = overrides[butai.id]
		if override and applyOverride(butai, override, now) then
			continue
		end
		local decision = Hoshin.decide({
			id = butai.id,
			gun = butai.gun,
			position = butai.position,
			hoshin = entry.hoshin,
			tanto = entry.tanto,
			kyoten = butai.kyoten,
		}, kyotenList, tsunagariList, tekiList)
		decisions[butai.id] = decision
		apply(butai, decision)
	end
end

-- 部隊を拠点へ向かわせ、seconds 秒（省くと release まで）方針の判断で目的地を変えない。
-- 方針で動かさない部隊にも使える。部隊がいないか、拠点が配置に無ければ false
function HoshinService.overrideKyoten(butaiId: string, kyotenId: string, seconds: number?): boolean
	if not ButaiService.get(butaiId) or not KyotenService.get(kyotenId) then
		return false
	end
	overrides[butaiId] = {
		kyoten = kyotenId,
		position = nil,
		untilTime = if seconds then os.clock() + seconds else nil,
	}
	ButaiService.moveToKyoten(butaiId, kyotenId)
	return true
end

-- 部隊を位置へまっすぐ向かわせ、seconds 秒（省くと release まで）方針の判断で目的地を変えない。部隊がいなければ false
function HoshinService.overridePosition(butaiId: string, position: Butai.Point, seconds: number?): boolean
	if not ButaiService.get(butaiId) then
		return false
	end
	local target = { x = position.x, z = position.z }
	overrides[butaiId] = { kyoten = nil, position = target, untilTime = if seconds then os.clock() + seconds else nil }
	ButaiService.setMokutekichi(butaiId, target)
	return true
end

-- 差し替えた目的地を外し、次の判断から方針に戻す。差し替えていなければ false
function HoshinService.release(butaiId: string): boolean
	if not overrides[butaiId] then
		return false
	end
	overrides[butaiId] = nil
	return true
end

local function clear()
	table.clear(entries)
	table.clear(overrides)
	table.clear(decisions)
end

-- 出撃したステージの配置から、方針で動かす部隊と担当の拠点を読む
local function onStarted(info: StageService.StartInfo)
	clear()
	local haichi = Haichi.get(info.stageId)
	if not haichi then
		return
	end
	for _, butai in haichi.butai do
		entries[butai.id] = { hoshin = butai.hoshin, tanto = butai.kyoten }
	end
end

local function round(value: number): number
	return math.round(value * 10) / 10
end

local function describe(): { [string]: any }
	local now = os.clock()
	local list = {}
	for _, butai in ButaiService.list() do
		local entry = entries[butai.id]
		local override = overrides[butai.id]
		if not entry and not override then
			continue
		end
		local decision = decisions[butai.id]
		local overrideText: string? = nil
		if override then
			local target = override.kyoten
				or (if override.position then `({round(override.position.x)}, {round(override.position.z)})` else "?")
			local untilTime = override.untilTime
			overrideText = if untilTime
				then `{target}（残り {round(math.max(untilTime - now, 0))} 秒）`
				else target
		end
		table.insert(list, {
			id = butai.id,
			gun = butai.gun,
			hoshin = if entry then entry.hoshin else nil,
			tanto = if entry then entry.tanto else nil,
			kyoten = butai.kyoten,
			mokutekiKyoten = butai.mokutekiKyoten,
			decision = if decision
				then {
					kind = decision.kind,
					kyoten = decision.kyoten,
					next = decision.next,
					butai = decision.butai,
				}
				else nil,
			override = overrideText,
			position = { round(butai.position.x), round(butai.position.z) },
			kosen = ButaiService.aiteOf(butai.id),
		})
	end
	return { enabled = enabled, butai = list }
end

local function registerDebugCommands()
	DebugCommand.register(
		"DumpHoshin",
		"",
		"方針で動く部隊ごとの方針・担当の拠点・今いる拠点・向かっている拠点・最後の判断・差し替えた目的地・位置を JSON で返す",
		function()
			return HttpService:JSONEncode(describe())
		end
	)
	DebugCommand.register(
		"SetHoshinAI",
		"<true|false>",
		"方針の判断を止めるか、再開するかを切り替える。止めても部隊は今の目的地へ進む（確認用）",
		function(value)
			enabled = value == true or value == "true"
			return if enabled then "方針の判断を再開した" else "方針の判断を止めた"
		end
	)
	DebugCommand.register(
		"SetHoshin",
		"<部隊 ID> <Koryaku|Boei|Kyuen> [担当の拠点 ID]",
		"部隊の方針（と担当の拠点）を書き換え、次の判断から使う。方針で動かさない部隊も方針で動かすようになる（確認用）",
		function(butaiId, hoshin, tanto)
			if type(butaiId) ~= "string" or not ButaiService.get(butaiId) then
				return `部隊 {tostring(butaiId)} がいない`
			end
			if not table.find(Haichi.hoshinList, hoshin) then
				error(`方針は {table.concat(Haichi.hoshinList, "、")} のどれか（{tostring(hoshin)}）`, 0)
			end
			local butai = ButaiService.get(butaiId) :: Butai.Butai
			local entry = entries[butaiId]
			local kyoten = if type(tanto) == "string" then tanto elseif entry then entry.tanto else butai.kyoten
			if type(kyoten) ~= "string" or not KyotenService.get(kyoten) then
				return `担当の拠点 {tostring(kyoten)} が出撃したステージに無い`
			end
			entries[butaiId] = { hoshin = hoshin :: Haichi.Hoshin, tanto = kyoten }
			return `部隊 {butaiId} の方針を {hoshin}（担当の拠点 {kyoten}）にした`
		end
	)
	DebugCommand.register(
		"OverrideMokutekichi",
		"<部隊 ID> <拠点 ID|off> [秒数]",
		"部隊を拠点へ向かわせ、その間は方針の判断で目的地を変えない（秒数を省くと off まで）。off で方針に戻す（確認用）",
		function(butaiId, kyotenId, seconds)
			if type(butaiId) ~= "string" or not ButaiService.get(butaiId) then
				return `部隊 {tostring(butaiId)} がいない`
			end
			if kyotenId == "off" then
				if not HoshinService.release(butaiId) then
					return `部隊 {butaiId} の目的地は差し替えていない`
				end
				return `部隊 {butaiId} の目的地の差し替えを外した（次の判断から方針に戻る）`
			end
			local duration = if seconds ~= nil then DebugCommand.toNumber(seconds, "秒数") else nil
			if type(kyotenId) ~= "string" or not HoshinService.overrideKyoten(butaiId, kyotenId, duration) then
				return `拠点 {tostring(kyotenId)} が出撃したステージに無い`
			end
			local length = if duration then `{duration} 秒` else "off まで"
			return `部隊 {butaiId} を {kyotenId} へ向かわせた（{length}は方針で目的地を変えない）`
		end
	)
end

function HoshinService.start()
	StageService.started:Connect(onStarted)
	StageService.finished:Connect(function()
		table.clear(overrides)
	end)
	StageService.phaseChanged:Connect(function(next: StagePhase.Phase)
		if next == "Lobby" then
			clear()
		end
	end)
	registerDebugCommands()

	task.spawn(function()
		while true do
			task.wait(Config.Hoshin.Interval)
			-- 1回の失敗で判断が止まらないよう、失敗は警告にして次の間隔で続ける
			local ok, err = pcall(think)
			if not ok then
				warn(`HoshinService: 方針を判断できなかった: {err}`)
			end
		end
	end)
end

return HoshinService
