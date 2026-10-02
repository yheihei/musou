--!strict
-- 軍全体の士気と、士気を上下させる出来事を持つ。部隊の士気は、軍全体の士気に部隊ごとの補正と近くの出来事の補正を
-- 足して決める。ButaiService が部隊を進める間隔ごとに、交戦の計算の前で求め直す（ButaiService.setShikiProvider）。
-- 計算は ReplicatedStorage.Shared.Shiki、上下の量・距離・時間は Config.luau の Shiki 節にある。
--
-- - 出撃（StageService.started）で軍全体の士気を開始時の値に戻し、出来事を空にする。決着とロビーのフェーズへの戻りでも戻す
-- - 出来事は notify（種類・位置・得をする軍）で知らせる。戦闘のフェーズの外では受け付けない。
--   上忍の撃破は JoninService.defeated を受けてここで知らせる。拠点の陥落（#86・#90）と秘計（#93）は各処理が notify を呼ぶ
-- - 軍全体の士気は ReplicatedStorage.Shiki（Configuration）の Attribute の Mikatagun・Tekigun でクライアントへ複製する。
--   部隊の士気は ButaiService が部隊の Attribute の Shiki で複製する

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Butai = require(ReplicatedStorage.Shared.Butai)
local Config = require(ReplicatedStorage.Shared.Config)
local Gun = require(ReplicatedStorage.Shared.Gun)
local Shiki = require(ReplicatedStorage.Shared.Shiki)
local StagePhase = require(ReplicatedStorage.Shared.StagePhase)
local DebugCommand = require(script.Parent.Parent.DebugCommand)
local ButaiService = require(script.Parent.ButaiService)
local JoninService = require(script.Parent.JoninService)
local StageService = require(script.Parent.StageService)

local ShikiService = {}

-- 軍全体の士気を複製する Configuration（ReplicatedStorage の下）の名前
ShikiService.STATE = "Shiki"

local gunShiki: Shiki.GunShiki = Shiki.newGun()
-- 起きた順の出来事。補正の消えたものは求め直すときに外す
local dekigotoList: { Shiki.Dekigoto } = {}
local state: Configuration

local function publishGun()
	for _, gun in Gun.list do
		state:SetAttribute(gun, gunShiki[gun])
	end
end

-- 軍全体の士気
function ShikiService.ofGun(gun: Gun.Gun): number
	return gunShiki[gun]
end

-- 部隊の今の士気。補正の消えた出来事は一覧から外す
function ShikiService.ofButai(butai: Butai.Butai): number
	local now = os.clock()
	Shiki.prune(dekigotoList, now)
	return Shiki.ofButai(gunShiki, butai, dekigotoList, now)
end

-- 士気を上下させる出来事を知らせる。kind は種類、position は水平の位置、gun は得をする軍。
-- 受け付けたら true。戦闘のフェーズの外と、種類か軍が正しくないときは受け付けない
function ShikiService.notify(kind: Shiki.Kind, position: Shiki.Point, gun: Gun.Gun): boolean
	if StageService.getPhase() ~= "Battle" then
		return false
	end
	if not Shiki.isKind(kind) or not Gun.isGun(gun) then
		warn(`ShikiService: 出来事の種類 {tostring(kind)} か得をする軍 {tostring(gun)} が正しくない`)
		return false
	end
	table.insert(dekigotoList, {
		kind = kind,
		position = { x = position.x, z = position.z },
		gun = gun,
		at = os.clock(),
	})
	Shiki.applyToGun(gunShiki, kind, gun)
	publishGun()
	return true
end

-- 軍全体の士気を開始時の値に戻し、出来事を空にする
local function reset()
	gunShiki = Shiki.newGun()
	table.clear(dekigotoList)
	publishGun()
end

-- 上忍か首領が倒れたら、倒れた位置で、倒した側の軍が得をする出来事として知らせる
local function onJoninDefeated(id: string)
	local jonin = JoninService.get(id)
	if jonin then
		ShikiService.notify("JoninGekiha", jonin.position, Gun.opponentOf(jonin.gun))
	end
end

local function round(value: number): number
	return math.round(value * 10) / 10
end

local function registerDebugCommands()
	DebugCommand.register(
		"ShikiDekigoto",
		`<{table.concat(Shiki.kinds, "|")}> <得をする軍> <部隊 ID か x z>`,
		"士気を上下させる出来事を知らせる。位置は部隊 ID（その部隊の位置）か、ワールドの x と z で渡す（確認用）",
		function(kind, gun, first, second)
			if not Shiki.isKind(kind) then
				error(`種類は {table.concat(Shiki.kinds, "、")} のどれか（{tostring(kind)}）`, 0)
			end
			if not Gun.isGun(gun) then
				error("得をする軍は Mikatagun か Tekigun で指定する", 0)
			end
			local position: Shiki.Point
			local butai = if type(first) == "string" then ButaiService.get(first) else nil
			if butai then
				position = { x = butai.position.x, z = butai.position.z }
			else
				position = { x = DebugCommand.toNumber(first, "x"), z = DebugCommand.toNumber(second, "z") }
			end
			if not ShikiService.notify(kind, position, gun) then
				return `出来事を受け付けなかった（戦闘のフェーズだけ受け付ける。フェーズ {StageService.getPhase()}）`
			end
			local where = `({round(position.x)}, {round(position.z)})`
			local gunText = `味方軍 {round(gunShiki.Mikatagun)}、敵軍 {round(gunShiki.Tekigun)}`
			return `{kind}（得をする軍 {gun}）を {where} で知らせた。軍全体の士気は {gunText}`
		end
	)
	DebugCommand.register(
		"SetGunShiki",
		"<Mikatagun|Tekigun> <士気>",
		`軍全体の士気を書き換える（{Config.Shiki.Min}〜{Config.Shiki.Max}。確認用）`,
		function(gun, value)
			if not Gun.isGun(gun) then
				error("軍は Mikatagun か Tekigun で指定する", 0)
			end
			local shiki = math.clamp(DebugCommand.toNumber(value, "士気"), Config.Shiki.Min, Config.Shiki.Max)
			gunShiki[gun :: Gun.Gun] = shiki
			publishGun()
			return `{gun} の軍全体の士気を {shiki} にした（部隊の士気は次の間隔で求め直す）`
		end
	)
	DebugCommand.register(
		"DumpShiki",
		"",
		"軍全体の士気、補正の残っている出来事（経過秒数つき）、部隊ごとの士気を JSON で返す",
		function()
			local now = os.clock()
			Shiki.prune(dekigotoList, now)
			local dekigoto = {}
			for _, item in dekigotoList do
				table.insert(dekigoto, {
					kind = item.kind,
					gun = item.gun,
					position = { round(item.position.x), round(item.position.z) },
					elapsed = round(now - item.at),
				})
			end
			local butai = {}
			for _, item in ButaiService.list() do
				table.insert(butai, {
					id = item.id,
					gun = item.gun,
					shiki = round(Shiki.ofButai(gunShiki, item, dekigotoList, now)),
					shikiHosei = item.shikiHosei,
				})
			end
			return HttpService:JSONEncode({
				gun = { Mikatagun = round(gunShiki.Mikatagun), Tekigun = round(gunShiki.Tekigun) },
				dekigoto = dekigoto,
				butai = butai,
			})
		end
	)
end

function ShikiService.start()
	local created = Instance.new("Configuration")
	created.Name = ShikiService.STATE
	created.Parent = ReplicatedStorage
	state = created
	publishGun()

	ButaiService.setShikiProvider(ShikiService.ofButai)
	JoninService.defeated:Connect(onJoninDefeated)
	StageService.started:Connect(reset)
	StageService.finished:Connect(reset)
	StageService.phaseChanged:Connect(function(next: StagePhase.Phase)
		if next == "Lobby" then
			reset()
		end
	end)
	registerDebugCommands()
end

return ShikiService
