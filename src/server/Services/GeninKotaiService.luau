--!strict
-- 実体化圏の下忍の個体（#76・#82）。出撃メンバーの近くに入った両軍の部隊から下忍を個体として出し、離れたら部隊に戻す。
-- 何体出すかの計算は ReplicatedStorage.Shared.GeninKotai（上限の配分は KotaiHaibun、半径は Jittaikaken）、
-- 数値は Config.luau の GeninKotai・Jittaikaken・KotaiHaibun 節にある。
-- 体（Humanoid のモデル）の生成・消去・動き・被ダメージは EnemyService が持ち、ここは部隊ごとの個体の数だけを扱う。
--
-- 兵数と個体（両軍で同じ）
-- - 兵数は部隊の下忍の全体の数のまま。個体はそのうちの何人かを姿として出したもの（借り出し）で、兵数を超えない
-- - 消した個体は部隊に戻る（兵数は変わらない。返却）
-- - 個体が倒れたら（倒した人によらず）、部隊の兵数を1減らす（ButaiService.changeHeisu）。減った兵数は拠点の耐久にも数える
--   （ButaiService.heisuLost を KyotenService が受ける）。秘計の爆破罠のとどめは、拠点の耐久に数えない（silent）
-- - 交戦などで兵数が個体の数より少なくなったら、多い分の個体をすぐに部隊へ戻す
-- - 部隊がいなくなったら（敗走など）、その部隊の個体を消す。部隊 ID を別の軍の部隊が使い直したときも、前の軍の個体を消す
--
-- 出し入れ（戦闘のフェーズの間、Interval ごと）
-- - 対象は、両軍の部隊のうち潜んでいない伏兵でないもの。半径・視界・Spread・MaxPerTick の決まりは両軍で同じ
-- - 区画の中にいる倒れていない出撃メンバーとの距離で、部隊ごとの個体の数（目標）を決める（GeninKotai.planBoth）。
--   サーバー全体の上限は MaxKotai（両軍とパーティー全体の合計で 40 体。1人あたりではない）。
--   味方軍の目標を先に MikataMaxKotai までで決め、敵軍の目標は残り（MaxKotai − 味方軍の目標の合計）で決める。
--   近くに味方軍の部隊がいなければ、敵軍は MaxKotai まで出せる
-- - 目標より多い部隊は、出撃メンバーから遠い個体から部隊へ戻す。目標に足りない部隊には、足りない数の多い部隊から順に、
--   部隊の位置の周り（Spread の円の中、区画の中、地面の上）に出す。1回の判断で出すのは MaxPerTick 体まで
-- - 出し入れする位置は、出撃メンバーの視界の外に限る（CameraViewService。#81）。ただし、出撃メンバー全員から
--   PopDistance より遠い位置なら、視界の中でも出し入れする（実体化圏の縁の遠くで、目立たないため）。
--   倒れたメンバーも、体が残っている間はカメラが戦場を映しているので、視界にも遠さの判定にも入れる。
--   出せる位置が無ければ、次の判断まで見送る（視界の中の出し入れの保留）
-- - 体の色は、出撃したステージの軍のクランの色（味方軍はストーリーのクラン、敵軍は敵軍のクラン。Stages.clanOf）
-- - 味方軍の個体はプレイヤーを狙わず、いつも部隊の位置の周りの自分の位置へ戻る（部隊について歩く。EnemyService）
-- - 戦闘のフェーズが終わったら、個体の表を空にする（体は EnemyService が片付ける）
--
-- 窓口
-- - SetSpawning で出し入れを止める・再開する。止めても出ている個体は残る（ClearEnemies で部隊へ戻す）。
--   止めている間も、兵数より多い個体を戻すことと、いなくなった部隊の個体を消すことは続ける
-- - LogSpawn で、出した・戻した・見送った・倒れて兵数を減らしたことを出力に出す
-- - DumpGeninKotai で両軍の部隊ごとの軍・兵数・個体の数・目標と軍ごとの個体の数、
--   DumpKotaiHaibun で軍ごと・まとまりごとの配分を出す

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Colors = require(ReplicatedStorage.Shared.Colors)
local Config = require(ReplicatedStorage.Shared.Config)
local GeninKotai = require(ReplicatedStorage.Shared.GeninKotai)
local Ground = require(ReplicatedStorage.Shared.Ground)
local Gun = require(ReplicatedStorage.Shared.Gun)
local KotaiHaibun = require(ReplicatedStorage.Shared.KotaiHaibun)
local Mejirushi = require(ReplicatedStorage.Shared.Mejirushi)
local StagePhase = require(ReplicatedStorage.Shared.StagePhase)
local Stages = require(ReplicatedStorage.Shared.Stages)
local DebugCommand = require(script.Parent.Parent.DebugCommand)
local ButaiService = require(script.Parent.ButaiService)
local CameraViewService = require(script.Parent.CameraViewService)
local EnemyService = require(script.Parent.EnemyService)
local KukakuService = require(script.Parent.KukakuService)
local StageService = require(script.Parent.StageService)

local GeninKotaiService = {}

-- 出す位置が視界にかかるかを確かめる高さ。地面から下忍の体の中ほどまで（スタッド）
local BODY_CENTER_HEIGHT = 3
-- 1体を出す位置を探すときに試す回数
local TRIES_PER_KOTAI = 4

-- 部隊 ID ごとの、出している個体のモデル（両軍）
local kotai: { [string]: { Model } } = {}
-- 部隊 ID ごとの、出している個体の軍（部隊 ID を別の軍の部隊が使い直したときに、前の軍の個体を見分ける）
local kotaiGun: { [string]: Gun.Gun } = {}
-- 出し入れを続けるか。窓口の SetSpawning で切り替える
local enabled = true
-- 出した・戻した・見送った・倒れて兵数を減らしたことを出力に出すか。窓口の LogSpawn で切り替える
local logEnabled = false
-- 最後に決めた目標（窓口の確認用）
local lastPlan: GeninKotai.BothPlan? = nil

local function log(message: string)
	if logEnabled then
		print(`[GeninKotai] {message}`)
	end
end

-- 戦闘のフェーズなら、出撃したステージの区画の範囲の目印。戦闘のフェーズでなければ nil
local function battleBounds(): BasePart?
	if StageService.getPhase() ~= "Battle" then
		return nil
	end
	local stageId = StageService.getStage()
	local stage = if stageId then Stages.get(stageId) else nil
	if not stage then
		return nil
	end
	return KukakuService.bounds(stage.kukaku)
end

local function insideBounds(bounds: BasePart, position: Vector3): boolean
	local offset = bounds.CFrame:PointToObjectSpace(position)
	return Mejirushi.insideBounds(offset.X, offset.Z, bounds.Size.X, bounds.Size.Z)
end

-- 出撃したステージの軍 gun のクランの色（味方軍はストーリーのクラン、敵軍は敵軍のクラン）。
-- 分からなければ nil（EnemyService の既定の色）
local function kotaiColor(gun: Gun.Gun): Color3?
	local stageId = StageService.getStage()
	local stage = if stageId then Stages.get(stageId) else nil
	return if stage then Colors.Clan[Stages.clanOf(stage, gun)] else nil
end

-- 区画の中にいる、倒れていない出撃メンバーの水平位置（id は名前）。倒れている間は個体の数の計算に数えない
local function membersInBounds(bounds: BasePart): { KotaiHaibun.Member }
	local points = {}
	for _, member in StageService.getMembers() do
		local character = member.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and humanoid and humanoid.Health > 0 and insideBounds(bounds, root.Position) then
			table.insert(points, { id = member.Name, x = root.Position.X, z = root.Position.Z })
		end
	end
	return points
end

-- 部隊の個体の表から、消えた個体と、倒れたことを知らせ終えた個体を外して、残っている個体の数を返す。
-- 体力が 0 になってから倒れたことを知らせる（兵数を1減らす）までの個体は数に入れる（個体の数と兵数をずらさないため）
local function prune(butaiId: string): number
	local list = kotai[butaiId]
	if not list then
		return 0
	end
	for index = #list, 1, -1 do
		if not EnemyService.isPresent(list[index]) then
			table.remove(list, index)
		end
	end
	if #list == 0 then
		kotai[butaiId] = nil
		kotaiGun[butaiId] = nil
		return 0
	end
	return #list
end

local function totalCount(): number
	local total = 0
	for id in table.clone(kotai) do
		total += prune(id)
	end
	return total
end

-- 軍 gun の、今出している個体の数
local function countOfGun(gun: Gun.Gun): number
	local total = 0
	for id in table.clone(kotai) do
		local count = prune(id)
		if kotaiGun[id] == gun then
			total += count
		end
	end
	return total
end

-- 部隊の、今出している個体の数（秘計が部隊の兵数を割合で減らすとき、個体として出ていない分だけに掛けるのに使う。両軍）
function GeninKotaiService.countOf(butaiId: string): number
	return prune(butaiId)
end

-- 戦場を見ている出撃メンバーの体の水平位置。倒れていても、体が残っている間はカメラが戦場を映しているので入れる
local function watchersOf(): { KotaiHaibun.Member }
	local points = {}
	for _, member in StageService.getMembers() do
		local character = member.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			table.insert(points, { id = member.Name, x = root.Position.X, z = root.Position.Z })
		end
	end
	return points
end

-- 出し入れしてよい位置か。戦場を見ているメンバー（watchers）全員から PopDistance より遠いか、誰の視界にもかからない
local function popSafe(position: Vector3, watchers: { KotaiHaibun.Member }): boolean
	local near = false
	for _, point in watchers do
		local dx, dz = point.x - position.X, point.z - position.Z
		if dx * dx + dz * dz <= Config.GeninKotai.PopDistance * Config.GeninKotai.PopDistance then
			near = true
			break
		end
	end
	if not near then
		return true
	end
	-- 視界は倒れているメンバーのカメラも含めて見る
	return not CameraViewService.seenByAny(StageService.getMembers(), position, Config.GeninKotai.ViewMargin)
end

local function nearestDistance(position: Vector3, points: { KotaiHaibun.Member }): number
	local best = math.huge
	for _, point in points do
		local dx, dz = point.x - position.X, point.z - position.Z
		best = math.min(best, math.sqrt(dx * dx + dz * dz))
	end
	return best
end

-- 部隊の個体を count 体まで部隊へ戻す。戦場を見ているメンバー（watchers）から遠い個体から戻す。
-- force なら視界によらず戻す（兵数が個体の数より少なくなったとき、部隊がいなくなったとき）。
-- 戻した数と、視界にかかって残した数を返す
local function dematerialize(
	butaiId: string,
	count: number,
	watchers: { KotaiHaibun.Member },
	force: boolean
): (number, number)
	local list = kotai[butaiId]
	if not list or count <= 0 then
		return 0, 0
	end
	local order = {}
	for _, model in list do
		local position = EnemyService.positionOf(model)
		if position then
			table.insert(order, { model = model, position = position, distance = nearestDistance(position, watchers) })
		end
	end
	table.sort(order, function(a, b)
		return a.distance > b.distance
	end)
	local removed, kept = 0, 0
	for _, entry in order do
		if removed >= count then
			break
		end
		if force or popSafe(entry.position, watchers) then
			if EnemyService.remove(entry.model) then
				removed += 1
			end
		else
			kept += 1
		end
	end
	prune(butaiId)
	return removed, kept
end

-- 軍 gun の部隊の位置の周りに個体を count 体まで出す。出した数と、視界にかかって見送った位置の数を返す
local function materialize(
	butaiId: string,
	gun: Gun.Gun,
	center: { x: number, z: number },
	count: number,
	watchers: { KotaiHaibun.Member },
	bounds: BasePart,
	color: Color3?
): (number, number)
	local spawned, seen = 0, 0
	for _ = 1, count * TRIES_PER_KOTAI do
		if spawned >= count then
			break
		end
		local angle = math.random() * math.pi * 2
		local reach = math.sqrt(math.random()) * Config.GeninKotai.Spread
		local x, z = center.x + math.cos(angle) * reach, center.z + math.sin(angle) * reach
		local groundY = if insideBounds(bounds, Vector3.new(x, 0, z)) then Ground.heightAt(x, z) else nil
		if groundY then
			if popSafe(Vector3.new(x, groundY + BODY_CENTER_HEIGHT, z), watchers) then
				local model = EnemyService.spawnKotai(butaiId, gun, x, z, color)
				if model then
					local list = kotai[butaiId]
					if not list then
						list = {}
						kotai[butaiId] = list
						kotaiGun[butaiId] = gun
					end
					table.insert(list, model)
					spawned += 1
				end
			else
				seen += 1
			end
		end
	end
	return spawned, seen
end

-- 出し入れを1回決める
local function tick()
	local bounds = battleBounds()
	if not bounds then
		return
	end
	local watchers = watchersOf()
	-- いなくなった部隊の個体は消す（部隊 ID を別の軍の部隊が使い直していたら、前の軍の個体も消す）
	for id in table.clone(kotai) do
		local butai = ButaiService.get(id)
		if prune(id) > 0 and (not butai or butai.gun ~= kotaiGun[id]) then
			dematerialize(id, math.huge, watchers, true)
			if butai then
				-- 倒れかけ（体力 0 で、倒れたことを知らせる前）の前の軍の個体は消せずに残るので、表から外す。
				-- 残すと、使い直した部隊の個体の数に混ざり、新しい軍の個体が前の軍の表に入る。
				-- 外した個体が倒れても、軍が違うので兵数は減らさない（kotaiDefeated）
				kotai[id] = nil
				kotaiGun[id] = nil
				log(`部隊 ID {id} を別の軍の部隊が使い直したので、前の軍の個体を消した`)
			else
				log(`部隊 {id} がいなくなったので、個体を消した`)
			end
		end
	end
	-- 交戦などで兵数が個体の数より少なくなったら、多い分をすぐに部隊へ戻す（出し入れを止めている間も行う）
	local butaiList = {}
	for _, butai in ButaiService.list() do
		if not butai.fukuhei then
			table.insert(butaiList, butai)
			local present = prune(butai.id)
			if present > butai.heisu then
				local removed = dematerialize(butai.id, present - butai.heisu, watchers, true)
				log(
					`部隊 {butai.id} の兵数 {butai.heisu} が個体の数より少ないので、{removed} 体を部隊へ戻した`
				)
			end
		end
	end
	if not enabled then
		lastPlan = nil
		return
	end

	-- 個体の数は、区画の中にいる倒れていないメンバーとの距離で決める。味方軍の目標を先に決め、敵軍は残りを使う
	local points = membersInBounds(bounds)
	local mikatagun: { GeninKotai.ButaiState } = {}
	local tekigun: { GeninKotai.ButaiState } = {}
	local positions: { [string]: { x: number, z: number } } = {}
	for _, butai in butaiList do
		positions[butai.id] = { x = butai.position.x, z = butai.position.z }
		local states = if butai.gun == "Mikatagun" then mikatagun else tekigun
		table.insert(states, {
			id = butai.id,
			x = butai.position.x,
			z = butai.position.z,
			heisu = butai.heisu,
			present = prune(butai.id),
		})
	end
	local plan =
		GeninKotai.planBoth(mikatagun, tekigun, points, Config.GeninKotai.MaxKotai, Config.GeninKotai.MikataMaxKotai)
	lastPlan = plan

	-- 目標より多い部隊から戻す（戻した分がほかの部隊の枠になる）
	for _, butai in butaiList do
		local present = prune(butai.id)
		local target = plan.targets[butai.id] or 0
		if present > target then
			local removed, kept = dematerialize(butai.id, present - target, watchers, false)
			if removed > 0 then
				log(`部隊 {butai.id} の個体を {removed} 体部隊へ戻した（目標 {target}）`)
			end
			if kept > 0 then
				log(`部隊 {butai.id} の個体 {kept} 体は視界の中なので、戻すのを見送った`)
			end
		end
	end

	-- 目標に足りない部隊へ、足りない数の多い順に出す（全体の上限と、1回の判断の上限まで）
	local needs = {}
	for _, butai in butaiList do
		local missing = (plan.targets[butai.id] or 0) - prune(butai.id)
		if missing > 0 then
			table.insert(needs, { id = butai.id, gun = butai.gun, missing = missing })
		end
	end
	table.sort(needs, function(a, b)
		if a.missing ~= b.missing then
			return a.missing > b.missing
		end
		return a.id < b.id
	end)
	local budget = math.min(Config.GeninKotai.MaxPerTick, Config.GeninKotai.MaxKotai - totalCount())
	-- 味方軍は、目標が減った部隊の個体が視界の中で戻せずに残っている間も、味方軍の上限を超えて出さない
	local mikataBudget = math.max(Config.GeninKotai.MikataMaxKotai - countOfGun("Mikatagun"), 0)
	for _, need in needs do
		if budget <= 0 then
			break
		end
		local want = math.min(need.missing, budget)
		if need.gun == "Mikatagun" then
			want = math.min(want, mikataBudget)
		end
		if want <= 0 then
			continue
		end
		local spawned, seen =
			materialize(need.id, need.gun, positions[need.id], want, watchers, bounds, kotaiColor(need.gun))
		budget -= spawned
		if need.gun == "Mikatagun" then
			mikataBudget -= spawned
		end
		if spawned > 0 then
			log(`部隊 {need.id} から個体を {spawned} 体出した（出している数 {prune(need.id)}）`)
		end
		if spawned < want and seen > 0 then
			log(`部隊 {need.id} の周りは視界の中なので、{seen} か所で出すのを見送った`)
		end
	end
end

local function registerDebugCommands()
	DebugCommand.register(
		"SetSpawning",
		"<true|false>",
		"実体化圏の両軍の下忍の個体の出し入れを止める・再開する。止めても出ている個体は残る（ClearEnemies で部隊へ戻す）（確認用）",
		function(value)
			enabled = value == true or value == "true"
			return `実体化圏の下忍の出し入れを{if enabled then "再開した" else "止めた"}`
		end
	)

	DebugCommand.register(
		"LogSpawn",
		"<true|false>",
		"実体化圏の下忍の個体を出した・部隊へ戻した・視界の中で見送った・倒れて部隊の兵数を減らしたことを出力に出す（確認用）",
		function(value)
			logEnabled = value == true or value == "true"
			return `実体化圏の下忍の出し入れの記録を{if logEnabled then "出す" else "止めた"}`
		end
	)

	DebugCommand.register(
		"DumpGeninKotai",
		"",
		"両軍の部隊ごとの軍・兵数・出している個体の数・目標・一番近い出撃メンバーまでの距離と、全体の個体の数（total）・"
			.. "上限（cap）・味方軍の上限（mikataCap）・最後の判断で敵軍に回した上限（tekiCap）・軍ごとの個体の数（totals）を JSON で返す",
		function()
			local plan = lastPlan
			local list = {}
			for _, butai in ButaiService.list() do
				local distance = if plan then plan.distances[butai.id] else nil
				table.insert(list, {
					id = butai.id,
					gun = butai.gun,
					heisu = butai.heisu,
					kotai = prune(butai.id),
					target = if plan then plan.targets[butai.id] else nil,
					distance = if distance then math.round(distance) else nil,
					fukuhei = butai.fukuhei,
				})
			end
			table.sort(list, function(a, b)
				if a.gun ~= b.gun then
					return a.gun < b.gun
				end
				return a.id < b.id
			end)
			local mikataTotal, tekiTotal = 0, 0
			for id in table.clone(kotai) do
				local count = prune(id)
				if kotaiGun[id] == "Mikatagun" then
					mikataTotal += count
				else
					tekiTotal += count
				end
			end
			return HttpService:JSONEncode({
				enabled = enabled,
				cap = Config.GeninKotai.MaxKotai,
				mikataCap = Config.GeninKotai.MikataMaxKotai,
				tekiCap = if plan then plan.tekigunCap else nil,
				total = totalCount(),
				totals = { Mikatagun = mikataTotal, Tekigun = tekiTotal },
				butai = list,
			})
		end
	)

	DebugCommand.register(
		"DumpKotaiHaibun",
		"",
		"実体化圏の下忍の個体の上限を、軍ごとに出撃メンバーのまとまりに分けた結果（軍・メンバー・配分・近くの部隊の兵数の合計・"
			.. "部隊・出している個体の数）と、軍ごとに回した上限（味方軍は mikataCap、敵軍は tekiCap）を JSON で返す",
		function()
			local plan = lastPlan
			if not plan then
				return if enabled
					then "まだ出し入れを決めていない（戦闘のフェーズでない）"
					else "出し入れを止めている（SetSpawning false）"
			end
			local groups = {}
			for _, entry in { { gun = "Mikatagun", plan = plan.mikatagun }, { gun = "Tekigun", plan = plan.tekigun } } do
				for _, group in entry.plan.groups do
					local present = 0
					for _, id in group.butai do
						present += prune(id)
					end
					table.insert(groups, {
						gun = entry.gun,
						members = group.members,
						quota = group.quota,
						demand = group.demand,
						butai = group.butai,
						kotai = present,
					})
				end
			end
			return HttpService:JSONEncode({
				enabled = enabled,
				cap = Config.GeninKotai.MaxKotai,
				mikataCap = plan.mikatagunCap,
				tekiCap = plan.tekigunCap,
				total = totalCount(),
				groups = groups,
			})
		end
	)
end

function GeninKotaiService.start()
	-- 戦う相手がいない個体は、部隊の位置の周りへ戻る
	EnemyService.setHomeProvider(function(butaiId: string): Vector3?
		local butai = ButaiService.get(butaiId)
		return if butai then Vector3.new(butai.position.x, 0, butai.position.z) else nil
	end)

	-- 個体が倒れたら、部隊の兵数を1減らす（部隊 ID を別の軍の部隊が使い直していたら減らさない）
	EnemyService.kotaiDefeated:Connect(
		function(model: Model, butaiId: string, gun: Gun.Gun, _position: Vector3, _attacker: Player?, silent: boolean)
			local list = kotai[butaiId]
			if list then
				local index = table.find(list, model)
				if index then
					table.remove(list, index)
				end
			end
			local butai = ButaiService.get(butaiId)
			local heisu = if butai and butai.gun == gun then ButaiService.changeHeisu(butaiId, -1, silent) else nil
			if heisu then
				log(
					`部隊 {butaiId} の個体 {model.Name} が倒れたので、兵数を1減らした（兵数 {heisu}）`
				)
			elseif butai and butai.gun ~= gun then
				log(
					`部隊 ID {butaiId} の前の軍の個体 {model.Name} が倒れた（別の軍の部隊が使い直したので、兵数は減らさない）`
				)
			else
				log(`部隊 {butaiId} の個体 {model.Name} が倒れた（部隊はもういない）`)
			end
		end
	)

	-- 戦闘のフェーズが終わったら、個体の表を空にする（体は EnemyService が片付ける）
	StageService.phaseChanged:Connect(function(next: StagePhase.Phase)
		if next ~= "Battle" then
			table.clear(kotai)
			table.clear(kotaiGun)
			lastPlan = nil
		end
	end)

	registerDebugCommands()

	task.spawn(function()
		while true do
			task.wait(Config.GeninKotai.Interval)
			-- 1回の失敗で出し入れが止まらないよう、失敗は警告にして次の間隔で続ける
			local ok, err = pcall(tick)
			if not ok then
				warn(`GeninKotaiService: 下忍の個体を出し入れできなかった: {err}`)
			end
		end
	end)
end

return GeninKotaiService
