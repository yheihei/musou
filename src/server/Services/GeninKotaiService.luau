--!strict
-- 実体化圏の下忍の個体（#76・#82）。出撃メンバーの近くに入った両軍の部隊から下忍を個体として出し、離れたら部隊に戻す。
-- 何体出すかの計算は ReplicatedStorage.Shared.GeninKotai（まとまりの分け方は KotaiHaibun、半径は Jittaikaken）、
-- 数値は Config.luau の GeninKotai・Jittaikaken・KotaiHaibun 節にある。
-- 体（Humanoid のモデル）の生成・消去・動き・被ダメージは EnemyService が持ち、ここは部隊ごとの個体の数だけを扱う。
--
-- 兵数と個体（両軍で同じ）
-- - 兵数は部隊の下忍の全体の数のまま。個体はそのうちの何人かを姿として出したもの（借り出し）で、兵数を超えない
-- - 消した個体は部隊に戻る（兵数は変わらない。返却）
-- - 個体が倒れたら（倒した人によらず）、部隊の兵数を1減らす（ButaiService.changeHeisu）。減った兵数は拠点の耐久にも数える
--   （ButaiService.heisuLost を KyotenService が受ける）。秘計の爆破罠のとどめは、拠点の耐久に数えない（silent）
-- - 交戦の損害で兵数が減ったら（ButaiService.addKosenLostListener）、その部隊の前線の個体を減った数だけ倒れさせる
--   （EnemyService.defeatZensen。出ている前線の個体が足りなければ出ている分だけ）。兵数は交戦の計算で減らし終えているので、
--   倒れさせた個体はすぐに個体の表から外し、倒れても兵数を減らさない（撃破数・拠点の耐久・救援数にも数えない）
-- - それでも兵数が個体の数より少なければ（前線の個体が足りずに倒れさせられなかった分）、多い分の個体をすぐに部隊へ戻す
-- - 部隊がいなくなったら（敗走など）、その部隊の個体を消す。部隊 ID を別の軍の部隊が使い直したときも、前の軍の個体を消す
-- - 交戦中の部隊の個体を前線と控えに並べ、動かすのは EnemyService（交戦の様子は setKosenProvider で渡す）
--
-- 出し入れ（戦闘のフェーズの間、Interval ごと）
-- - 対象は、両軍の部隊のうち潜んでいない伏兵でないもの。半径・視界・Spread・MaxPerTick の決まりは両軍で同じ
-- - 区画の中にいる倒れていない出撃メンバーとの距離で、部隊ごとの個体の数（目標）を決める（GeninKotai.planWaku）。
--   サーバー全体の上限は MaxKotai（両軍とパーティー全体の合計で 40 体。1人あたりではない）。上限を先に近いメンバーの
--   まとまりごとに人数の比で分け（#85）、まとまりの取り分の MikataRate（25%）までを味方軍の個体にする（1人なら 10 体、
--   離れた2人なら 5 体ずつ）。まとまりの枠は近くの部隊の兵数（味方軍はその上限まで）を超えず、余りはほかのまとまりへ回す
-- - 敵軍の目標は、まとまりの枠から味方軍が押さえている数（部隊ごとの max(出ている数, min(目標, 出ている数 + 返却の求め))
--   の和）を引いた残りで決める。まだ出ていない味方軍の目標だけでは、同じまとまりの敵軍を減らさない（ほかのまとまりへ回す
--   余りからは除く）。目標より多く視界の中に残る味方軍の個体は、同じまとまりの敵軍が返す（ほかのまとまりは減らさない）
-- - 返却の求めは、今出せる味方軍の部隊だけが持つ（GeninKotai.updateRequests）。今出せる = 部隊の周りに出し入れしてよい位置が
--   あり、まとまりの味方軍の予算（味方軍の目標 − まとまりの味方軍の出ている数）が 1 以上。今出せなくなったら求めを取り下げ、
--   敵軍の補充も止めない。求めは足りない数とまとまりの味方軍の予算を超えず、MikataReclaimStep 増やすのは、まとまりの前の返却が
--   済んでいるとき（敵軍の出ている数 ≤ 今の求めで決めた敵軍の目標）の1部隊だけ。目標が 0 になったら（部隊が離れたら）、
--   部隊がいなくなったら取り消し、足りたら外す。メンバーが1人も重ならないまとまりへ移ったら 0 から積み直す。
--   返却を求めている味方軍の部隊がいるまとまりでは、敵軍を補充しない
-- - 目標より多い個体は、出撃メンバーから遠い個体から部隊へ戻す（視界の中の個体は戻さないので、返せない間は味方軍が待つ）。
--   味方軍の部隊と、どのまとまりにも入らない敵軍の部隊は部隊ごとに戻す。まとまりに入る敵軍は、まとまりごとに
--   「敵軍の部隊の出ている数の合計 − 目標の合計」を、まとまりの敵軍の全部隊の個体から遠い順に戻す（returnExcess。
--   ある部隊の個体がすべて視界の中でも、ほかの部隊の視界の外の個体から返す。目標より多い部隊と少ない部隊は残ってよい）
-- - 目標に足りない部隊には、味方軍の部隊を先に、足りない数の多い部隊から順に、部隊の位置の周り（Spread の円の中、
--   区画の中、地面の上）に出す（GeninKotai.fill）。まとまりの枠の残り（味方軍は、まとまりの味方軍の目標の残りも）と、
--   MaxKotai の残りと、1回の判断の MaxPerTick 体を超えない。撃破などで空いた枠は、待っている味方軍に先に回る
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
-- - LogSpawn で、出した・戻した・見送った・倒れて兵数を減らした・交戦の損害で前線の個体を倒したことと、枠の返却を求めた・
--   減らした・取り下げた（今出せない）・外した（足りた）・取り消した（目標 0・部隊がいない・出し入れを止めた）こと、
--   まとまりの敵軍の補充を止めた・再開したことを出力に出す（返却の求めと補充の停止は変わったときだけ。メンバーが1人でも
--   重なるまとまりは同じまとまりとみなす。敵軍の個体を戻した・見送ったことは、まとまりごとに部隊ごとの数を添えて出し、
--   倒れかけの個体は見送った数に入れない）
-- - DumpGeninKotai で両軍の部隊ごとの軍・兵数・個体の数・目標・まとまりの番号・返却の求めと軍ごとの個体の数、
--   DumpKotaiHaibun でまとまりごとの取り分・枠・味方軍の上限と目標・押さえている数・敵軍の枠・補充の停止を出す
-- - DumpKosenKotai で、交戦の組ごとに両部隊の前線の個体（正面と相手の部隊の方向の角度の差）、控えの数、
--   交戦の損害の合計と、演出で倒した数を出す。SetKosenAggro で、交戦中の敵軍の個体がプレイヤーを狙うかを切り替える

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Butai = require(ReplicatedStorage.Shared.Butai)
local Colors = require(ReplicatedStorage.Shared.Colors)
local Config = require(ReplicatedStorage.Shared.Config)
local GeninKotai = require(ReplicatedStorage.Shared.GeninKotai)
local Ground = require(ReplicatedStorage.Shared.Ground)
local Gun = require(ReplicatedStorage.Shared.Gun)
local KotaiHaibun = require(ReplicatedStorage.Shared.KotaiHaibun)
local Mejirushi = require(ReplicatedStorage.Shared.Mejirushi)
local StagePhase = require(ReplicatedStorage.Shared.StagePhase)
local Stages = require(ReplicatedStorage.Shared.Stages)
local Zensen = require(ReplicatedStorage.Shared.Zensen)
local DebugCommand = require(script.Parent.Parent.DebugCommand)
local ButaiService = require(script.Parent.ButaiService)
local CameraViewService = require(script.Parent.CameraViewService)
local EnemyService = require(script.Parent.EnemyService)
local KukakuService = require(script.Parent.KukakuService)
local StageService = require(script.Parent.StageService)

local GeninKotaiService = {}

-- 部隊の今の交戦で、交戦の損害の演出で倒した前線の個体の数（taoshita）と、前線の個体が出ていない・足りないので
-- 倒さなかった数（fusoku）。交戦を始めたときと、交戦の相手が替わったときに数え直す。2つの合計が、その交戦の交戦の損害の合計になる
type ZensenRecord = { aite: string, taoshita: number, fusoku: number }

-- 出す位置が視界にかかるかを確かめる高さ。地面から下忍の体の中ほどまで（スタッド）
local BODY_CENTER_HEIGHT = 3
-- 1体を出す位置を探すときに試す回数
local TRIES_PER_KOTAI = 4
-- 味方軍の部隊の周りに出し入れしてよい位置があるかを確かめるときに試す回数
local SPAWNABLE_TRIES = 8

-- 最後の判断の枠と目標（窓口の確認用）。stopped はまとまりごとの、敵軍の補充を止めているか
type LastPlan = { plan: GeninKotai.WakuPlan, teki: GeninKotai.TekiPlan, stopped: { boolean } }

-- 部隊 ID ごとの、出している個体のモデル（両軍）
local kotai: { [string]: { Model } } = {}
-- 部隊 ID ごとの、出している個体の軍（部隊 ID を別の軍の部隊が使い直したときに、前の軍の個体を見分ける）
local kotaiGun: { [string]: Gun.Gun } = {}
-- 出し入れを続けるか。窓口の SetSpawning で切り替える
local enabled = true
-- 出した・戻した・見送った・倒れて兵数を減らした・枠の返却を求めたことなどを出力に出すか。窓口の LogSpawn で切り替える
local logEnabled = false
-- 最後に決めた枠と目標（窓口の確認用）
local lastPlan: LastPlan? = nil
-- 味方軍の部隊 ID ごとの、個体を出すために敵軍の個体に枠の返却を求めている数と、求めたまとまりのメンバー
-- （部隊 ID で持つので、まとまりの番号が判断ごとに変わっても引き継ぐ。GeninKotai.updateRequests）
local requests: GeninKotai.Requests = { counts = {}, members = {} }
-- 敵軍の補充を止めているまとまりのメンバー。記録を変わったときだけ出すのに使う（メンバーが1人でも重なるまとまりは、
-- 同じまとまりが続いているとみなし、メンバーが倒れた・合流しただけでは「止めた」「再開した」を出さない）
local stoppedGroups: { { string } } = {}
-- 部隊 ID ごとの、今の交戦の演出の記録（窓口の確認用）
local zensenRecords: { [string]: ZensenRecord } = {}

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

-- 部隊の位置 center の周り（Spread の円の中）から、個体を出す位置を1か所選ぶ。区画の外か、地面が無ければ nil。
-- 返す位置の高さは、視界にかかるかを確かめる高さ（地面から体の中ほど）
local function pickSpot(center: { x: number, z: number }, bounds: BasePart): Vector3?
	local angle = math.random() * math.pi * 2
	local reach = math.sqrt(math.random()) * Config.GeninKotai.Spread
	local x, z = center.x + math.cos(angle) * reach, center.z + math.sin(angle) * reach
	local groundY = if insideBounds(bounds, Vector3.new(x, 0, z)) then Ground.heightAt(x, z) else nil
	return if groundY then Vector3.new(x, groundY + BODY_CENTER_HEIGHT, z) else nil
end

-- 部隊の位置 center の周りに、個体を出し入れしてよい位置があるか（materialize と同じ選び方で数か所を試すだけで、出さない）。
-- 味方軍の部隊が、個体を出すために敵軍の個体に枠の返却を求めるかを決めるのに使う
local function canMaterialize(
	center: { x: number, z: number },
	watchers: { KotaiHaibun.Member },
	bounds: BasePart
): boolean
	for _ = 1, SPAWNABLE_TRIES do
		local spot = pickSpot(center, bounds)
		if spot and popSafe(spot, watchers) then
			return true
		end
	end
	return false
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
		local spot = pickSpot(center, bounds)
		if spot then
			if popSafe(spot, watchers) then
				local model = EnemyService.spawnKotai(butaiId, gun, spot.X, spot.Z, color)
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

-- まとまりの印（メンバーの名前を名前の順につないだもの）。まとまりの番号は判断ごとに変わるので、記録はこの印で出す
local function groupKey(group: GeninKotai.WakuGroup): string
	return table.concat(group.members, "、")
end

-- 返却の求めと補充の停止を忘れる（出し入れを止めたとき、戦闘のフェーズが終わったとき）。
-- 求めていた数と、補充を止めていたまとまりは、変わったこととして記録に出す
local function forgetRequests(reason: string)
	if next(requests.counts) ~= nil then
		log(`{reason}ので、枠の返却の求めをすべて取り消した`)
	end
	for _, members in stoppedGroups do
		log(`まとまり（{table.concat(members, "、")}）の敵軍の補充を再開した（{reason}）`)
	end
	requests = { counts = {}, members = {} }
	stoppedGroups = {}
end

-- 味方軍の部隊ごとの返却の求めを、計画 plan と部隊の様子 states（present は今出ている数）で1回の判断ぶん進める
-- （規則は GeninKotai.updateRequests）。出せる位置は materialize と同じ選び方で確かめる。
-- 求めが変わったとき（増やした・減らした・取り下げた・外した・取り消した・積み直した）だけ記録を出す
local function updateRequests(
	states: { GeninKotai.ButaiState },
	plan: GeninKotai.WakuPlan,
	watchers: { KotaiHaibun.Member },
	bounds: BasePart
)
	local present: { [string]: number } = {}
	local centers: { [string]: { x: number, z: number } } = {}
	for _, state in states do
		present[state.id] = state.present
		centers[state.id] = { x = state.x, z = state.z }
	end
	local nextRequests, notes = GeninKotai.updateRequests(plan, present, requests, function(id: string): boolean
		return canMaterialize(centers[id], watchers, bounds)
	end, Config.GeninKotai.MikataReclaimStep)

	for id, note in notes do
		local index = plan.groupOf[id]
		local key = if index then groupKey(plan.groups[index]) else nil
		local before, after = note.before, note.after
		local movedFrom = note.movedFrom
		if movedFrom then
			log(
				`部隊 {id} がまとまり（{table.concat(movedFrom, "、")}）から（{key or "なし"}）へ移ったので、`
					.. `枠の返却の求め（{note.movedCount or 0} 体）を 0 から積み直す`
			)
		end
		if after and (before == nil or after > before) then
			log(
				`部隊 {id} の個体を出すために、まとまり（{key or "なし"}）の敵軍の個体に枠の返却を求めた`
					.. `（求め {after} 体、目標 {note.target}、出している数 {note.present}）`
			)
		elseif after and before and after < before then
			log(
				`部隊 {id} の枠の返却の求めを {after} 体に減らした`
					.. `（目標 {note.target}、出している数 {note.present}、まとまりの味方軍の空き {note.budget}）`
			)
		elseif before and not after then
			if note.target <= 0 then
				log(
					`部隊 {id} の目標が 0 になったので、枠の返却の求め（{before} 体）を取り消した`
				)
			elseif note.present >= note.target then
				log(
					`部隊 {id} は目標まで個体を出したので、枠の返却の求めを外した`
						.. `（目標 {note.target}、出している数 {note.present}）`
				)
			elseif note.budget <= 0 then
				log(
					`部隊 {id} はまとまりの味方軍の枠に空きが無く、今は個体を出せないので、`
						.. `枠の返却の求め（{before} 体）を取り下げた`
				)
			else
				log(
					`部隊 {id} は周りが視界の中で、今は個体を出せないので、枠の返却の求め（{before} 体）を取り下げた`
				)
			end
		end
	end
	for id, request in requests.counts do
		if notes[id] == nil then
			log(
				`味方軍の部隊 {id} がいなくなったので、枠の返却の求め（{request} 体）を取り消した`
			)
		end
	end
	requests = nextRequests
end

-- まとまりごとの敵軍の補充の停止が変わったときだけ、記録を出す。前の判断で止めていたまとまりとメンバーが1人でも重なる
-- まとまりは、同じまとまりが続いているとみなす（メンバーが倒れた・合流しただけでは出さない）
local function logStopped(plan: GeninKotai.WakuPlan, stopped: { boolean })
	local current: { { string } } = {}
	for index, group in plan.groups do
		if stopped[index] then
			table.insert(current, group.members)
			local continued = false
			for _, members in stoppedGroups do
				if GeninKotai.sharesMember(members, group.members) then
					continued = true
					break
				end
			end
			if not continued then
				local ids = {}
				for _, id in group.mikataButai do
					if (requests.counts[id] or 0) > 0 then
						table.insert(ids, id)
					end
				end
				local names = table.concat(ids, "、")
				log(
					`まとまり（{groupKey(group)}）の敵軍の補充を止めた（味方軍の部隊 {names} が枠の返却を求めている）`
				)
			end
		end
	end
	for _, members in stoppedGroups do
		local continued = false
		for _, now in current do
			if GeninKotai.sharesMember(members, now) then
				continued = true
				break
			end
		end
		if not continued then
			log(`まとまり（{table.concat(members, "、")}）の敵軍の補充を再開した`)
		end
	end
	stoppedGroups = current
end

-- 目標より多い個体を部隊へ戻す。視界の外か、戦場を見ているメンバー全員から PopDistance より遠い個体だけを戻す（force なし）。
-- - 味方軍の部隊と、どのまとまりにも入らない敵軍の部隊（目標 0）は、部隊ごとに遠い個体から戻す
-- - まとまりに入る敵軍は、まとまりごとに「敵軍の部隊の出ている数の合計 − 目標の合計」を、まとまりの敵軍の全部隊の個体から
--   遠い順に戻す（GeninKotai.pickReturns）。部隊の個体がすべて視界の中でも、ほかの部隊の視界の外の個体から返せる
local function returnExcess(
	butaiList: { Butai.Butai },
	plan: GeninKotai.WakuPlan,
	teki: GeninKotai.TekiPlan,
	watchers: { KotaiHaibun.Member }
)
	for _, butai in butaiList do
		local grouped = butai.gun ~= "Mikatagun" and plan.groupOf[butai.id] ~= nil
		if not grouped then
			local count = prune(butai.id)
			local target = if butai.gun == "Mikatagun"
				then plan.mikataTargets[butai.id] or 0
				else teki.targets[butai.id] or 0
			if count > target then
				local removed, kept = dematerialize(butai.id, count - target, watchers, false)
				if removed > 0 then
					log(`部隊 {butai.id} の個体を {removed} 体部隊へ戻した（目標 {target}）`)
				end
				if kept > 0 then
					log(`部隊 {butai.id} の個体 {kept} 体は視界の中なので、戻すのを見送った`)
				end
			end
		end
	end

	for index, group in plan.groups do
		local present, target = 0, 0
		for _, id in group.tekiButai do
			present += prune(id)
			target += teki.targets[id] or 0
		end
		local excess = present - target
		if excess > 0 then
			local candidates: { GeninKotai.ReturnCandidate<{ model: Model, position: Vector3 }> } = {}
			for _, id in group.tekiButai do
				for _, model in kotai[id] or {} do
					local position = EnemyService.positionOf(model)
					if position then
						table.insert(candidates, {
							item = { model = model, position = position },
							butai = id,
							distance = nearestDistance(position, watchers),
						})
					end
				end
			end
			-- 倒れかけ（体力 0 で、倒れたことを知らせる前）の個体は数に入っているが、すぐに表から外れるので戻さない。
			-- その分を戻す数から引く（見送った数にも混ぜない）
			local dying = present - #candidates
			local count = math.max(excess - dying, 0)
			local picked = GeninKotai.pickReturns(candidates, count, function(candidate): boolean
				return popSafe(candidate.item.position, watchers)
			end)
			local removedOf: { [string]: number } = {}
			local removed = 0
			for _, candidate in picked do
				if EnemyService.remove(candidate.item.model) then
					removedOf[candidate.butai] = (removedOf[candidate.butai] or 0) + 1
					removed += 1
				end
			end
			for _, id in group.tekiButai do
				prune(id)
			end
			local key = groupKey(group)
			local quota = teki.quotas[index]
			if removed > 0 then
				local parts = {}
				for _, id in group.tekiButai do
					local fromButai = removedOf[id]
					if fromButai then
						table.insert(parts, `{id} から {fromButai} 体`)
					end
				end
				log(
					`まとまり（{key}）の敵軍の個体を {removed} 体部隊へ戻した`
						.. `（部隊 {table.concat(parts, "、")}。敵軍の枠 {quota}）`
				)
			end
			if removed < count then
				log(
					`まとまり（{key}）の敵軍の個体 {count - removed} 体は視界の中なので、戻すのを見送った`
						.. `（敵軍の枠 {quota}）`
				)
			end
		end
	end
end

-- 部隊の今の交戦の演出の記録。交戦の相手が替わっていたら数え直す
local function zensenRecordOf(butaiId: string, aiteId: string): ZensenRecord
	local record = zensenRecords[butaiId]
	if not record or record.aite ~= aiteId then
		record = { aite = aiteId, taoshita = 0, fusoku = 0 }
		zensenRecords[butaiId] = record
	end
	return record
end

-- 交戦の損害で部隊の兵数が loss 減ったら、その部隊の前線の個体を loss 体倒れさせる（出ている前線の個体が足りなければ
-- 出ている分だけ）。兵数は交戦の計算で減らし終えているので、倒れさせた個体はすぐに個体の表から外す（兵数と比べる
-- 個体の数に入れず、多い分を部隊へ戻す処理に回さない）。倒れても兵数は減らさない（EnemyService が kotaiDefeated で知らせない）
local function onKosenLost(butaiId: string, gun: Gun.Gun, loss: number, aiteId: string)
	local record = zensenRecordOf(butaiId, aiteId)
	-- 個体の出ていない部隊（出撃メンバーから遠い交戦）は、数えるだけにする。
	-- 部隊 ID を別の軍の部隊が使い直していたら、前の軍の個体は倒さない（次の判断で消す）
	if prune(butaiId) == 0 or kotaiGun[butaiId] ~= gun then
		record.fusoku += loss
		return
	end
	local fallen = EnemyService.defeatZensen(butaiId, loss)
	local list = kotai[butaiId]
	local names = {}
	for _, model in fallen do
		local index = if list then table.find(list, model) else nil
		if list and index then
			table.remove(list, index)
		end
		table.insert(names, model.Name)
	end
	prune(butaiId)
	record.taoshita += #fallen
	record.fusoku += loss - #fallen
	local butai = ButaiService.get(butaiId)
	local heisu = if butai then butai.heisu else 0
	local total = record.taoshita + record.fusoku
	if #fallen > 0 then
		log(
			`部隊 {butaiId} の交戦の損害 {loss} で、前線の個体 {table.concat(names, "、")} を倒した`
				.. `（兵数 {heisu}、この交戦で演出で倒した数 {record.taoshita}、交戦の損害の合計 {total}）`
		)
	end
	if #fallen < loss then
		log(
			`部隊 {butaiId} の交戦の損害 {loss} のうち {loss - #fallen} は、出ている前線の個体が足りないので倒さなかった`
				.. `（兵数 {heisu}、この交戦で演出で倒した数 {record.taoshita}、交戦の損害の合計 {total}）`
		)
	end
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
	-- 兵数が個体の数より少なくなったら、多い分をすぐに部隊へ戻す（出し入れを止めている間も行う）。
	-- 交戦の損害は前線の個体を倒れさせて数を合わせる（onKosenLost）ので、ここで戻すのは、前線の個体が足りずに
	-- 倒れさせられなかった分（プレイヤーを狙っていて前線にいなかった個体など）
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
		forgetRequests("出し入れを止めた")
		return
	end

	-- 個体の数は、区画の中にいる倒れていないメンバーとの距離で決める。両軍の合計の上限を先にまとまりへ分け、
	-- まとまりの取り分の MikataRate までを味方軍にする（敵軍の目標は、味方軍が押さえている数を引いた残り）
	local points = membersInBounds(bounds)
	local states: { GeninKotai.ButaiState } = {}
	local positions: { [string]: { x: number, z: number } } = {}
	local gunOf: { [string]: Gun.Gun } = {}
	local present: { [string]: number } = {}
	for _, butai in butaiList do
		local count = prune(butai.id)
		positions[butai.id] = { x = butai.position.x, z = butai.position.z }
		gunOf[butai.id] = butai.gun
		present[butai.id] = count
		table.insert(states, {
			id = butai.id,
			gun = butai.gun,
			x = butai.position.x,
			z = butai.position.z,
			heisu = butai.heisu,
			present = count,
		})
	end
	local plan = GeninKotai.planWaku(states, points, Config.GeninKotai.MaxKotai, Config.GeninKotai.MikataRate)
	-- 味方軍の部隊の返却の求めを増やし（減らし）てから、押さえている数で敵軍の目標を決める
	updateRequests(states, plan, watchers, bounds)
	local teki = GeninKotai.tekiTargets(plan, GeninKotai.heldOf(plan, present, requests.counts))
	local stopped = GeninKotai.hojuStopped(plan, requests.counts)
	logStopped(plan, stopped)
	lastPlan = { plan = plan, teki = teki, stopped = stopped }

	-- 目標より多い個体を戻す（遠い個体から、視界の外の個体だけ。敵軍はまとまりごと。戻した分が枠の空きになる）
	returnExcess(butaiList, plan, teki, watchers)

	-- 目標に足りない部隊へ出す。味方軍の部隊が先で、まとまりの枠の残りと、全体の上限と、1回の判断の上限まで。
	-- 返却を求めている味方軍の部隊がいるまとまりの敵軍には出さない
	local after: { [string]: number } = {}
	for _, butai in butaiList do
		after[butai.id] = prune(butai.id)
	end
	local budget = math.min(Config.GeninKotai.MaxPerTick, Config.GeninKotai.MaxKotai - totalCount())
	GeninKotai.fill(plan, teki, after, requests.counts, budget, function(id: string, want: number): number
		local gun = gunOf[id]
		local spawned, seen = materialize(id, gun, positions[id], want, watchers, bounds, kotaiColor(gun))
		if spawned > 0 then
			log(`部隊 {id} から個体を {spawned} 体出した（出している数 {prune(id)}）`)
		end
		if spawned < want and seen > 0 then
			log(`部隊 {id} の周りは視界の中なので、{seen} か所で出すのを見送った`)
		end
		return spawned
	end)
end

local function round(value: number): number
	return math.round(value * 10) / 10
end

-- 交戦中の部隊の片側の様子（窓口の DumpKosenKotai）。角度の差は、個体の正面と、自分の部隊の位置から相手の部隊の位置への向き。
-- 角度の差の最大は、並ぶ位置に着いた前線の個体（歩いている途中の個体は歩く向きを向いている）で求める
local function describeZensen(butai: Butai.Butai, aite: Butai.Butai): { [string]: any }
	local direction = Zensen.direction(
		{ x = butai.position.x, z = butai.position.z },
		{ x = aite.position.x, z = aite.position.z }
	)
	local zensen = {}
	local maxAngle: number? = nil
	local hikae, player = 0, 0
	for _, entry in EnemyService.kosenKotaiOf(butai.id) do
		if entry.front then
			local look = entry.look
			local angle = if look then Zensen.angle(look, direction) else nil
			if angle and entry.arrived then
				maxAngle = math.max(maxAngle or 0, angle)
			end
			local distance = entry.distance
			table.insert(zensen, {
				name = entry.name,
				angle = if angle then round(angle) else nil,
				aite = entry.aite,
				distance = if distance then round(distance) else nil,
			})
		elseif entry.front == false then
			hikae += 1
		elseif entry.player then
			player += 1
		end
	end
	local record = zensenRecords[butai.id]
	local current = if record and record.aite == aite.id then record else nil
	return {
		id = butai.id,
		gun = butai.gun,
		heisu = butai.heisu,
		kotai = prune(butai.id),
		songai = ButaiService.kosenLoss(butai.id) or 0,
		taoshita = if current then current.taoshita else 0,
		fusoku = if current then current.fusoku else 0,
		zensen = zensen,
		maxAngle = if maxAngle then round(maxAngle) else nil,
		hikae = hikae,
		player = player,
	}
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
		"実体化圏の下忍の個体を出した・部隊へ戻した・視界の中で見送った・倒れて部隊の兵数を減らした・交戦の損害で前線の個体を倒したことと、"
			.. "味方軍の部隊が敵軍の個体に枠の返却を求めた・求めを減らした・今出せないので取り下げた・取り消した（外した）こと、"
			.. "まとまりの敵軍の補充を止めた・再開したことを出力に出す（返却の求めと補充の停止は変わったときだけ）（確認用）",
		function(value)
			logEnabled = value == true or value == "true"
			return `実体化圏の下忍の出し入れの記録を{if logEnabled then "出す" else "止めた"}`
		end
	)

	DebugCommand.register(
		"DumpGeninKotai",
		"",
		"両軍の部隊ごとの軍・兵数・出している個体の数（kotai）・目標（target）・一番近い出撃メンバーまでの距離（distance）・"
			.. "最後の判断で数えたまとまりの番号（group。DumpKotaiHaibun の group）・味方軍の部隊が敵軍の個体に求めている"
			.. "枠の返却の数（request）と、全体の個体の数（total）・上限（cap）・まとまりの取り分のうち味方軍に回す割合（mikataRate）・"
			.. "軍ごとの個体の数（totals）を JSON で返す",
		function()
			local last = lastPlan
			local list = {}
			for _, butai in ButaiService.list() do
				local distance = if last then last.plan.distances[butai.id] else nil
				local target: number? = nil
				if last then
					target = if butai.gun == "Mikatagun"
						then last.plan.mikataTargets[butai.id]
						else last.teki.targets[butai.id]
				end
				table.insert(list, {
					id = butai.id,
					gun = butai.gun,
					heisu = butai.heisu,
					kotai = prune(butai.id),
					target = target,
					distance = if distance then math.round(distance) else nil,
					group = if last then last.plan.groupOf[butai.id] else nil,
					request = if butai.gun == "Mikatagun" then requests.counts[butai.id] or 0 else nil,
					fukuhei = butai.fukuhei,
				})
			end
			table.sort(list, function(a, b)
				if a.gun ~= b.gun then
					return a.gun < b.gun
				end
				return a.id < b.id
			end)
			return HttpService:JSONEncode({
				enabled = enabled,
				cap = Config.GeninKotai.MaxKotai,
				mikataRate = Config.GeninKotai.MikataRate,
				total = totalCount(),
				totals = { Mikatagun = countOfGun("Mikatagun"), Tekigun = countOfGun("Tekigun") },
				butai = list,
			})
		end
	)

	DebugCommand.register(
		"DumpKotaiHaibun",
		"",
		"実体化圏の下忍の個体の枠を、最後の判断で出撃メンバーのまとまりに分けた結果を JSON で返す。まとまりごとに、"
			.. "番号（group）・メンバー（members）・人数の比の取り分（share）・味方軍の上限（mikataCap。share × mikataRate の切り捨て）・"
			.. "近くの部隊の兵数（mikataHeisu・tekiHeisu）・需要（demand。tekiHeisu + min(mikataHeisu, mikataCap)）・枠（quota）・"
			.. "味方軍の目標（mikataTarget）・味方軍が押さえている数（held）・敵軍の枠（tekiQuota。quota − held）・"
			.. "返却の求めの合計（request）・敵軍の補充を止めているか（tekiHojuStopped）・出している個体の数（kotai・"
			.. "mikataKotai・tekiKotai）・部隊（mikataButai・tekiButai）",
		function()
			local last = lastPlan
			if not last then
				return if enabled
					then "まだ出し入れを決めていない（戦闘のフェーズでない）"
					else "出し入れを止めている（SetSpawning false）"
			end
			local groups = {}
			for index, group in last.plan.groups do
				local mikataKotai, tekiKotai, request = 0, 0, 0
				for _, id in group.mikataButai do
					mikataKotai += prune(id)
					request += requests.counts[id] or 0
				end
				for _, id in group.tekiButai do
					tekiKotai += prune(id)
				end
				table.insert(groups, {
					group = index,
					members = group.members,
					share = group.share,
					mikataCap = group.mikataCap,
					mikataHeisu = group.mikataHeisu,
					tekiHeisu = group.tekiHeisu,
					demand = group.demand,
					quota = group.quota,
					mikataTarget = group.mikataTarget,
					held = last.teki.held[index],
					tekiQuota = last.teki.quotas[index],
					request = request,
					tekiHojuStopped = last.stopped[index],
					kotai = mikataKotai + tekiKotai,
					mikataKotai = mikataKotai,
					tekiKotai = tekiKotai,
					mikataButai = group.mikataButai,
					tekiButai = group.tekiButai,
				})
			end
			return HttpService:JSONEncode({
				enabled = enabled,
				cap = Config.GeninKotai.MaxKotai,
				mikataRate = Config.GeninKotai.MikataRate,
				total = totalCount(),
				groups = groups,
			})
		end
	)

	DebugCommand.register(
		"DumpKosenKotai",
		"",
		"交戦中の組ごとに、両部隊の部隊 ID・軍・兵数・出している個体の数（kotai）・前線の個体（zensen。名前、個体の正面と"
			.. "自分の部隊から相手の部隊への向きの角度の差 angle（度）、向かい合う相手 aite、並ぶ位置までの距離 distance）・"
			.. "並ぶ位置に着いた前線の個体の angle の最大（maxAngle）・控えの個体の数（hikae）・プレイヤーを狙っている個体の数（player）・"
			.. "交戦を始めてからの交戦の損害の合計（songai）・交戦の損害の演出で倒した前線の個体の数（taoshita）・"
			.. "前線の個体が出ていない・足りないので倒さなかった数（fusoku。taoshita との和が songai）を JSON で返す",
		function()
			local result = {}
			local seen: { [string]: boolean } = {}
			for _, butai in ButaiService.list() do
				local aiteId = ButaiService.aiteOf(butai.id)
				local aite = if aiteId then ButaiService.get(aiteId) else nil
				if not aite or seen[butai.id] then
					continue
				end
				seen[butai.id] = true
				seen[aite.id] = true
				-- 組の中の順は部隊 ID の順
				local first, second = butai, aite
				if second.id < first.id then
					first, second = second, first
				end
				table.insert(result, { butai = { describeZensen(first, second), describeZensen(second, first) } })
			end
			return HttpService:JSONEncode({ kosen = result })
		end
	)

	DebugCommand.register(
		"SetKosenAggro",
		"<true|false>",
		"交戦中の部隊の敵軍の個体が、近く（Config.luau の Zensen 節の AggroRange）のプレイヤーを狙うかを切り替える。"
			.. "止めると、前線の攻撃の動作がプレイヤーに当たらないことを、攻撃トークンの攻撃と分けて確かめられる（確認用）",
		function(value)
			local aggro = value == true or value == "true"
			EnemyService.setKosenAggro(aggro)
			local result = if aggro then "再開した" else "止めた"
			return `交戦中の敵軍の個体がプレイヤーを狙うのを{result}`
		end
	)
end

function GeninKotaiService.start()
	-- 戦う相手がいない個体は、部隊の位置の周りへ戻る
	EnemyService.setHomeProvider(function(butaiId: string): Vector3?
		local butai = ButaiService.get(butaiId)
		return if butai then Vector3.new(butai.position.x, 0, butai.position.z) else nil
	end)

	-- 交戦中の部隊の個体は、交戦の組ごとに前線と控えに並ぶ（交戦が決着したら、部隊について歩く動きに戻る）
	EnemyService.setKosenProvider(function(butaiId: string): EnemyService.KosenInfo?
		local aiteId = ButaiService.aiteOf(butaiId)
		local butai = ButaiService.get(butaiId)
		local aite = if aiteId then ButaiService.get(aiteId) else nil
		if not butai or not aite then
			return nil
		end
		return {
			aite = aite.id,
			position = { x = butai.position.x, z = butai.position.z },
			aitePosition = { x = aite.position.x, z = aite.position.z },
		}
	end)

	-- 交戦の損害で兵数が減ったら、その部隊の前線の個体を減った数だけ倒れさせる
	ButaiService.addKosenLostListener(onKosenLost)
	-- 交戦を始めたら、両部隊の演出の記録を数え直す（部隊 ID を使い直した部隊が同じ相手と交戦しても前の数が混ざらない。
	-- 交戦の損害は次の部隊の間隔から出るので、知らせが後の再開に回っても間に合う）
	ButaiService.kosenStarted:Connect(function(a: string, b: string)
		zensenRecords[a] = nil
		zensenRecords[b] = nil
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
			table.clear(zensenRecords)
			forgetRequests("戦闘のフェーズが終わった")
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
