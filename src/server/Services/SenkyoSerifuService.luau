--!strict
-- 戦況の台詞。戦闘のフェーズの間、戦況の変化を ReplicatedStorage.Shared.SenkyoSerifu の Henka にして、
-- 出撃したステージの発火の表から台詞を選び、SerifuService.play で出撃メンバーの画面の端に出す。
-- どの台詞を出すか（1回のステージで1回だけ、差し込みはそのキャラクターで出撃した人がいるときだけ）は SenkyoSerifu が決め、
-- 数値は Config.luau の SenkyoSerifu 節にある。台詞の文は ReplicatedStorage.Shared.Serifu にある。
--
-- 変化の拾い方
-- - Kaishi は戦闘のフェーズに入ったとき（StageService.phaseChanged）
-- - Seiatsu は KyotenService.seiatsu、TaikyuHanbun は耐久を書き換える前（KyotenService.addTaikyuListener）。
--   拠点の担当の上忍（shubi）は、出撃したステージの配置で、その拠点から始まる部隊を率いる上忍
-- - Koritsu は兵站線を求め直したとき（HeitansenService.changed）に、新しく孤立した拠点ごとに拾う
-- - Hikei は HikeiService.activated（上忍と首領が使ったときだけ）、Kishu は FukuheiService.kishu（上忍と首領の伏兵だけ）
-- - Gekiha は JoninService.defeated（by は倒したプレイヤーが使っているキャラクター）、
--   Shutsugen は JoninService.kotaiChanged、TairyokuHanbun は JoninService.healthChanged
-- - Sekkin・Oshi・Nokori・Heiryoku は、CheckInterval 秒ごとに戦場を見回って拾う
--   - Sekkin は、まだ出していない接近の台詞があるときだけ、拠点ごとに、相手の軍の部隊（潜んでいる伏兵部隊を除く）が
--     中心から SekkinRange 以内にいれば拾う
--   - Oshi は、まだ出していない台詞があるときだけ、上忍が率いる交戦中の部隊ごとに、交戦を始めてからの交戦の損害を
--     相手の部隊と比べて拾う
--   - Nokori は残り時間（workspace の BattleDeadline）、Heiryoku は兵力（SaishutsugekiService）の、前に見たときからの変化
-- - 差し込みの判断に使う出撃したキャラクターは、台詞を選ぶときの出撃メンバーのキャラクター（PlayerService.getCharacterId）
-- - 戦闘のフェーズを抜けたら、出した台詞の記録と見回りの前の値を空にする
--
-- 窓口
-- - SetSenkyoSerifu で止める・再開する（確認用。止めている間に起きた変化の台詞は出さない）
-- - LogSenkyoSerifu で、拾った変化と出した台詞を出力に出す（見回りで拾う変化は台詞を出したときだけ）
-- - DumpSenkyoSerifu で、出撃したステージの発火の表と出したか、見回りの前の値を JSON で返す
-- - ResetSenkyoSerifu で、出した台詞の記録を空にする（同じ台詞をもう一度確かめる用）

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Butai = require(ReplicatedStorage.Shared.Butai)
local Config = require(ReplicatedStorage.Shared.Config)
local Kyoten = require(ReplicatedStorage.Shared.Kyoten)
local SenkyoSerifu = require(ReplicatedStorage.Shared.SenkyoSerifu)
local StagePhase = require(ReplicatedStorage.Shared.StagePhase)
local DebugCommand = require(script.Parent.Parent.DebugCommand)
local ButaiService = require(script.Parent.ButaiService)
local FukuheiService = require(script.Parent.FukuheiService)
local HeitansenService = require(script.Parent.HeitansenService)
local HikeiService = require(script.Parent.HikeiService)
local JoninService = require(script.Parent.JoninService)
local KyotenService = require(script.Parent.KyotenService)
local PlayerService = require(script.Parent.PlayerService)
local SaishutsugekiService = require(script.Parent.SaishutsugekiService)
local SerifuService = require(script.Parent.SerifuService)
local StageService = require(script.Parent.StageService)

local SenkyoSerifuService = {}

-- 窓口で止めていないか
local enabled = true
-- 拾った変化と出した台詞を出力に出すか（窓口の LogSenkyoSerifu）
local logEnabled = false
-- 戦闘のフェーズの間か
local active = false
-- 出撃したステージ ID と、その発火の表
local stageId: string? = nil
local entries: { SenkyoSerifu.Entry } = {}
-- このステージで出した台詞 ID
local played: { [string]: boolean } = {}
-- 拠点 ID から引く、配置でその拠点から始まる部隊を率いる上忍のキャラクター ID
local shubiOf: { [string]: { string } } = {}
-- 孤立している拠点 ID（新しく孤立した拠点だけを拾うため）
local koritsu: { [string]: boolean } = {}
-- 見回りで前に見た残り時間（秒）と兵力
local lastRemaining: number? = nil
local lastHeiryoku: number? = nil

local function log(message: string)
	if logEnabled then
		print(`[SenkyoSerifu] {message}`)
	end
end

-- 変化を短い文にする（記録用）
local function describe(henka: SenkyoSerifu.Henka): string
	local parts = {}
	for _, key in
		{
			"gun",
			"honjin",
			"jonin",
			"shuryo",
			"butaiJonin",
			"hikei",
			"by",
			"songai",
			"aiteSongai",
			"before",
			"after",
			"max",
		}
	do
		local value = (henka :: any)[key]
		if value ~= nil then
			if type(value) == "number" then
				value = math.round(value * 10) / 10
			end
			table.insert(parts, `{key} {tostring(value)}`)
		end
	end
	local shubi = henka.shubi
	if shubi and #shubi > 0 then
		table.insert(parts, `shubi {table.concat(shubi, "・")}`)
	end
	if #parts == 0 then
		return henka.kikkake
	end
	return `{henka.kikkake}（{table.concat(parts, "、")}）`
end

-- 出撃メンバーが使っているキャラクター ID
local function sortiedCharacters(members: { Player }): { [string]: boolean }
	local result: { [string]: boolean } = {}
	for _, member in members do
		result[PlayerService.getCharacterId(member)] = true
	end
	return result
end

-- 変化に合う台詞を出す。patrol は見回りで拾った変化（台詞を出さなければ記録しない）
local function handle(henka: SenkyoSerifu.Henka, patrol: boolean?)
	if not active or not enabled or StageService.getPhase() ~= "Battle" then
		return
	end
	local members = StageService.getMembers()
	local picked = SenkyoSerifu.pick(entries, henka, played, sortiedCharacters(members))
	if #picked == 0 then
		if not patrol then
			log(`{describe(henka)} に合う台詞は無かった`)
		end
		return
	end
	for _, entry in picked do
		played[entry.id] = true
		if SerifuService.play(entry.speaker, entry.hyojo, entry.id, members) then
			log(`{describe(henka)} で、{entry.speaker} の台詞 {entry.id} を出した`)
		end
	end
end

-- 配置から、拠点ごとの担当の上忍を引く表を作る
local function buildShubi(): { [string]: { string } }
	local result: { [string]: { string } } = {}
	local haichi = KyotenService.getHaichi()
	if not haichi then
		return result
	end
	for _, butai in haichi.butai do
		local jonin = butai.jonin
		if jonin then
			local list = result[butai.kyoten]
			if not list then
				list = {}
				result[butai.kyoten] = list
			end
			table.insert(list, jonin)
		end
	end
	return result
end

-- 戦闘のフェーズの残り時間（秒）。戦闘のフェーズの外では nil
local function remainingTime(): number?
	local deadline = workspace:GetAttribute(StagePhase.DEADLINE_ATTRIBUTE)
	if type(deadline) ~= "number" then
		return nil
	end
	return math.max(deadline - workspace:GetServerTimeNow(), 0)
end

local function begin()
	stageId = StageService.getStage()
	entries = SenkyoSerifu.entriesOf(stageId)
	table.clear(played)
	shubiOf = buildShubi()
	-- 戦闘のフェーズの前から孤立している拠点は、新しく孤立したとみなさない
	table.clear(koritsu)
	for _, kyoten in KyotenService.list() do
		if HeitansenService.isKoritsu(kyoten.id) then
			koritsu[kyoten.id] = true
		end
	end
	lastRemaining = remainingTime()
	lastHeiryoku = SaishutsugekiService.getHeiryoku()
	active = true
	handle({ kikkake = "Kaishi" })
end

local function stop()
	active = false
	stageId = nil
	entries = {}
	table.clear(played)
	shubiOf = {}
	table.clear(koritsu)
	lastRemaining = nil
	lastHeiryoku = nil
end

local function onPhaseChanged(phase: StagePhase.Phase)
	if phase == "Battle" then
		begin()
	elseif active then
		stop()
	end
end

-- 拠点の変化に、拠点の軍・本陣か・担当の上忍を添える
local function kyotenHenka(kikkake: SenkyoSerifu.Kikkake, kyoten: Kyoten.Kyoten): SenkyoSerifu.Henka
	return { kikkake = kikkake, gun = kyoten.gun, honjin = kyoten.honjin, shubi = shubiOf[kyoten.id] or {} }
end

local function onTaikyuChanging(id: string, before: number, after: number)
	if not active then
		return
	end
	local kyoten = KyotenService.get(id)
	if not kyoten then
		return
	end
	local henka = kyotenHenka("TaikyuHanbun", kyoten)
	henka.before = before
	henka.after = after
	henka.max = Kyoten.maxTaikyu(kyoten.honjin)
	handle(henka, true)
end

local function onHeitansenChanged()
	if not active then
		return
	end
	for _, kyoten in KyotenService.list() do
		local isolated = HeitansenService.isKoritsu(kyoten.id)
		if isolated and not koritsu[kyoten.id] then
			koritsu[kyoten.id] = true
			log(`拠点 {kyoten.id}（{kyoten.gun}）が孤立した`)
			handle({ kikkake = "Koritsu", gun = kyoten.gun })
		elseif not isolated then
			koritsu[kyoten.id] = nil
		end
	end
end

local function onDefeated(id: string, player: Player?)
	local jonin = JoninService.get(id)
	if not jonin then
		return
	end
	local by = if player and player.Parent then PlayerService.getCharacterId(player) else nil
	handle({ kikkake = "Gekiha", jonin = id, gun = jonin.gun, shuryo = jonin.shuryo, by = by })
end

-- 相手の軍の部隊が拠点に近づいたかを見回る
local function patrolSekkin()
	local range = Config.SenkyoSerifu.SekkinRange
	local butaiList = ButaiService.list()
	for _, kyoten in KyotenService.list() do
		local center = KyotenService.centerOf(kyoten.id)
		if center then
			for _, butai in butaiList do
				if
					butai.gun ~= kyoten.gun
					and not butai.fukuhei
					and Butai.distance(butai.position, center) <= range
				then
					local henka = kyotenHenka("Sekkin", kyoten)
					henka.butaiJonin = butai.jonin
					handle(henka, true)
				end
			end
		end
	end
end

-- 上忍が率いる交戦中の部隊が押されているかを見回る
local function patrolOshi()
	for _, butai in ButaiService.list() do
		local jonin = butai.jonin
		local aite = ButaiService.aiteOf(butai.id)
		if jonin and aite then
			local songai = ButaiService.kosenLoss(butai.id)
			local aiteSongai = ButaiService.kosenLoss(aite)
			if songai and aiteSongai then
				handle({ kikkake = "Oshi", jonin = jonin, songai = songai, aiteSongai = aiteSongai }, true)
			end
		end
	end
end

local function patrol()
	if not active then
		return
	end
	if SenkyoSerifu.hasPending(entries, "Sekkin", played) then
		patrolSekkin()
	end
	if SenkyoSerifu.hasPending(entries, "Oshi", played) then
		patrolOshi()
	end
	local remaining = remainingTime()
	if remaining and lastRemaining then
		handle({ kikkake = "Nokori", before = lastRemaining, after = remaining }, true)
	end
	lastRemaining = remaining
	local heiryoku = SaishutsugekiService.getHeiryoku()
	if heiryoku and lastHeiryoku and heiryoku ~= lastHeiryoku then
		handle({ kikkake = "Heiryoku", before = lastHeiryoku, after = heiryoku }, true)
	end
	lastHeiryoku = heiryoku
end

local function registerDebugCommands()
	DebugCommand.register(
		"SetSenkyoSerifu",
		"<true|false>",
		"戦況の台詞（戦況の変化をきっかけに出す戦闘中の台詞）を止める・再開する（確認用。止めている間の変化の台詞は出さない）",
		function(value)
			enabled = value == true or value == "true"
			return `戦況の台詞を{if enabled then "再開した" else "止めた"}`
		end
	)
	DebugCommand.register(
		"LogSenkyoSerifu",
		"<true|false>",
		"戦況の台詞で、拾った変化と出した台詞を出力に出す（見回りで拾う接近・押され方・残り時間・兵力は、台詞を出したときだけ）",
		function(value)
			logEnabled = value == true or value == "true"
			return `戦況の台詞の記録を{if logEnabled then "出す" else "止めた"}`
		end
	)
	DebugCommand.register(
		"DumpSenkyoSerifu",
		"",
		"戦況の台詞の様子（止めていないか enabled、戦闘のフェーズの間か active、ステージ、発火の表の台詞ごとのきっかけ・話者・"
			.. "出したか played、孤立している拠点、見回りで前に見た残り時間 remaining と兵力 heiryoku）を JSON で返す",
		function()
			local list = {}
			for _, entry in entries do
				table.insert(list, {
					id = entry.id,
					kikkake = entry.kikkake,
					speaker = entry.speaker,
					played = played[entry.id] == true,
				})
			end
			local isolated = {}
			for id in koritsu do
				table.insert(isolated, id)
			end
			table.sort(isolated)
			return HttpService:JSONEncode({
				enabled = enabled,
				active = active,
				stage = stageId,
				entries = list,
				koritsu = isolated,
				remaining = if lastRemaining then math.round(lastRemaining) else nil,
				heiryoku = lastHeiryoku,
			})
		end
	)
	DebugCommand.register(
		"ResetSenkyoSerifu",
		"",
		"戦況の台詞の、このステージで出した台詞の記録を空にする（同じ台詞をもう一度確かめる用）",
		function()
			local count = 0
			for _ in played do
				count += 1
			end
			table.clear(played)
			return `出した台詞の記録 {count} 本を空にした`
		end
	)
end

function SenkyoSerifuService.start()
	StageService.phaseChanged:Connect(onPhaseChanged)
	KyotenService.seiatsu:Connect(function(_id: string, gun, _previous)
		handle({ kikkake = "Seiatsu", gun = gun })
	end)
	KyotenService.addTaikyuListener(onTaikyuChanging)
	HeitansenService.changed:Connect(onHeitansenChanged)
	HikeiService.activated:Connect(function(userId: string, _name: string, _gun, hikeiId: string)
		if JoninService.get(userId) then
			handle({ kikkake = "Hikei", jonin = userId, hikei = hikeiId })
		end
	end)
	FukuheiService.kishu:Connect(function(userId: string)
		if JoninService.get(userId) then
			handle({ kikkake = "Kishu", jonin = userId })
		end
	end)
	JoninService.defeated:Connect(onDefeated)
	JoninService.kotaiChanged:Connect(function(id: string, present: boolean)
		if present then
			handle({ kikkake = "Shutsugen", jonin = id })
		end
	end)
	JoninService.healthChanged:Connect(function(id: string, before: number, after: number, max: number)
		handle({ kikkake = "TairyokuHanbun", jonin = id, before = before, after = after, max = max }, true)
	end)
	registerDebugCommands()
	task.spawn(function()
		while true do
			task.wait(Config.SenkyoSerifu.CheckInterval)
			-- 1回の失敗で見回りが止まらないよう、失敗は警告にして次の間隔で続ける
			local ok, err = pcall(patrol)
			if not ok then
				warn(`SenkyoSerifuService: 戦場を見回れなかった: {err}`)
			end
		end
	end)
end

return SenkyoSerifuService
