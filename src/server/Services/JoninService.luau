--!strict
-- 上忍と首領をデータで持つ。出撃したステージの配置から作り、上忍は率いる部隊の位置に合わせ、首領は本陣の中心に置く。
-- 型と体力の計算は ReplicatedStorage.Shared.Jonin、能力値は Config.luau の Stats 節にある。
-- 個体（モデル）の出し入れは JoninKotaiService が行う。体力はここに持つので、個体が消えて出直しても体力は残る。
--
-- - 出撃（StageService.started）で作り、決着とロビーのフェーズへの戻りで片付ける。配置の構成が無いステージでは作らない
-- - 敵軍の上忍と首領の体力は、出撃したときの人数（StartInfo.partySize）で上げる。途中で抜けても変えない
-- - 上忍の位置は、部隊を進める間隔（Config.luau の Butai 節）ごとに率いる部隊の位置へ合わせる。
--   戦闘のフェーズで部隊が消えていたら、率いる部隊を外してその場に残す
-- - 首領は本陣の範囲にとどまる。setPosition で範囲の外の位置を渡されたら、範囲の縁へ寄せる（Hoshin.clampToRange）
-- - 被ダメージの受け口は damage の1つ。プレイヤーの攻撃（CombatService）も秘計（大火計・爆破罠）もここを通す。
--   与ダメージは威力を防御で軽減したもの（Stats.damage）。damaged で、個体に反応（吹き飛びなど）を始めさせる
-- - 体力が 0 になった上忍は倒れる。率いていた部隊は残し、士気だけ下げる（ButaiService.loseJonin）。
--   倒したプレイヤー（攻撃した人）がいれば、その人の撃破数に1を足す。defeated で、倒した人と一緒に知らせる（両軍、首領を含む）
-- - 毒（酉花の奥義「毒手裏剣」。Config.luau の Poison 節）は、データの上で間隔ごとに体力を減らす。個体が消えても続く。
--   毒でのとどめは、毒を付けたプレイヤーの撃破に数える。毒の間にもう一度付けると、残りの時間を Duration に戻す。
--   与える回数は Duration を Interval で割った回数（8 秒・1 秒おきなら 8 回）で数える
-- - 個体として出ている上忍（setKotai）は、個体が位置を決める（JoninKotaiService が setPosition で写す）。
--   部隊への追従はしない。個体が戻る位置は homeOf（率いる部隊の位置、首領は本陣の中心、目的地を差し替えていればその目的地）
-- - 上忍の目的地は外から差し替えられる（overrideMokutekichi。秘計の挑発が使う）。差し替えている間は部隊に追従しない。
--   個体が出ていれば個体が目的地へ歩き、出ていなければデータの位置を上忍の歩く速さ（Stats 節の WalkSpeed）で、
--   部隊を進める間隔ごとに目的地へ進める。目的地から Config.luau の Jittaikaken 節の HomeRadius の距離で止める
-- - 差し替えを外したら（releaseMokutekichi）、いきなり部隊の位置へ移さず、率いる部隊へ歩いて戻る。
--   個体が出ていなければデータの位置を歩く速さで進め、部隊の位置から HomeRadius 以内に着いたら部隊への追従に戻す
-- - 交戦中の部隊どうしが両方とも上忍に率いられていれば、部隊を進める間隔ごとに上忍同士も戦わせる
--   （ReplicatedStorage.Shared.Kosen の joninStep。味方軍の上忍は士気の差がしきい値以上のときだけ削れる）。
--   目的地を差し替えている上忍と、部隊へ戻る途中の上忍は、部隊から離れているので戦わせない
-- - 部隊を進める間隔ごとに、上忍と首領が自分の軍の支配エリアの中かを確かめ、中なら攻撃と防御を上げる（Jonin.setShihaiArea）。
--   中かどうかは ShihaiAreaService が setShihaiAreaProvider で渡す関数で引き、関数が無ければ外とみなす
-- - 秘計の効果（鬼神化など）の補正は、各秘計の処理が setHikeiHosei で足し外しする
-- - 上忍と首領ごとに ReplicatedStorage.Jonin の下へキャラクター ID の名前で Configuration を置き、Attribute で
--   位置（Position。Vector2 の X と Y にワールドの X と Z）・体力（Health・MaxHealth）・軍（Gun）・
--   率いる部隊（Butai）・首領か（Shuryo）・名前（DisplayName）・個体として出ているか（Kotai）をクライアントへ複製する

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Butai = require(ReplicatedStorage.Shared.Butai)
local Config = require(ReplicatedStorage.Shared.Config)
local Ground = require(ReplicatedStorage.Shared.Ground)
local Gun = require(ReplicatedStorage.Shared.Gun)
local Haichi = require(ReplicatedStorage.Shared.Haichi)
local Hoshin = require(ReplicatedStorage.Shared.Hoshin)
local Jonin = require(ReplicatedStorage.Shared.Jonin)
local Kosen = require(ReplicatedStorage.Shared.Kosen)
local StagePhase = require(ReplicatedStorage.Shared.StagePhase)
local Stages = require(ReplicatedStorage.Shared.Stages)
local Stats = require(ReplicatedStorage.Shared.Stats)
local DebugCommand = require(script.Parent.Parent.DebugCommand)
local ButaiService = require(script.Parent.ButaiService)
local HaichiService = require(script.Parent.HaichiService)
local PlayerService = require(script.Parent.PlayerService)
local StageService = require(script.Parent.StageService)

-- 攻撃を当てたときの反応の中身（個体が吹き飛ぶ向きと強さ）。Combat/Hanno の Hit と同じ形
export type Hit = {
	reaction: Config.Reaction,
	-- 攻撃元の位置
	origin: Vector3,
	-- 技の吹き飛ばす強さ（Config.luau の HitDef の Knockback）
	force: number,
}

-- 毒の中身
type Poison = {
	-- 毒を付けたプレイヤー
	attacker: Player?,
	-- 次に毒のダメージを与える時刻（os.clock）
	nextTick: number,
	-- 残りの毒のダメージの回数
	ticks: number,
}

local JoninService = {}

-- 上忍と首領の Attribute を置くフォルダ（ReplicatedStorage の下）の名前
JoninService.FOLDER = "Jonin"

-- 出撃したステージの上忍と首領（配置の構成の順）
local joninList: { Jonin.Jonin } = {}
local folder: Folder
-- 首領のキャラクター ID から引く、とどまる本陣の範囲（目印のパーツの中心・向き・大きさ）
local honjinRangeOf: { [string]: { cframe: CFrame, size: Vector3 } } = {}
-- 個体として出ている上忍と首領のキャラクター ID
local kotaiOf: { [string]: boolean } = {}
-- キャラクター ID から引く、毒の中身
local poisonOf: { [string]: Poison } = {}
-- キャラクター ID から引く、差し替えた目的地を返す関数（秘計の挑発で誘い出された上忍など）
local overrideOf: { [string]: () -> Jonin.Point? } = {}
-- 差し替えを外した後、率いる部隊へ歩いて戻る途中の上忍のキャラクター ID
local returningOf: { [string]: boolean } = {}

-- 軍と位置を受け、その軍の支配エリアの中かを返す関数（ShihaiAreaService が渡す）
local shihaiAreaProvider: ((gun: Gun.Gun, position: Jonin.Point) -> boolean)? = nil

local defeatedEvent = Instance.new("BindableEvent")
-- 上忍か首領が倒れたときに、そのキャラクター ID と、倒したプレイヤー（いなければ nil）で発火する。両軍、首領も含む
JoninService.defeated = defeatedEvent.Event
local damagedEvent = Instance.new("BindableEvent")
-- damage でダメージを与えたときに、キャラクター ID・与えたダメージ・反応の中身（Hit。無ければ nil）で発火する
JoninService.damaged = damagedEvent.Event

local function find(id: string): Jonin.Jonin?
	for _, jonin in joninList do
		if jonin.id == id then
			return jonin
		end
	end
	return nil
end

function JoninService.get(id: string): Jonin.Jonin?
	return find(id)
end

-- 出撃したステージの上忍と首領の一覧（表は写し。上忍の表はそのもの）
function JoninService.list(): { Jonin.Jonin }
	return table.clone(joninList)
end

-- 今の状態を Attribute に書いてクライアントへ複製する
local function publish(jonin: Jonin.Jonin)
	local state = folder:FindFirstChild(jonin.id)
	if not state then
		local created = Instance.new("Configuration")
		created.Name = jonin.id
		created.Parent = folder
		state = created
	end
	local instance = state :: Instance
	instance:SetAttribute("DisplayName", jonin.displayName)
	instance:SetAttribute("Gun", jonin.gun)
	instance:SetAttribute("Shuryo", jonin.shuryo)
	instance:SetAttribute("Butai", jonin.butai)
	instance:SetAttribute("Position", Vector2.new(jonin.position.x, jonin.position.z))
	instance:SetAttribute("Health", jonin.health)
	instance:SetAttribute("MaxHealth", jonin.stats.MaxHealth)
	instance:SetAttribute("Kotai", kotaiOf[jonin.id] == true)
end

-- 軍と位置を受け、その軍の支配エリアの中かを返す関数を登録する
function JoninService.setShihaiAreaProvider(provider: (gun: Gun.Gun, position: Jonin.Point) -> boolean)
	shihaiAreaProvider = provider
end

-- 体力を書き換える。倒れたら、率いていた部隊は残して士気だけ下げ、毒と目的地の差し替えを外す。
-- attacker を渡すと、倒れたときにその人の撃破数に1を足す。いなければ false
function JoninService.setHealth(id: string, value: number, attacker: Player?): boolean
	local jonin = find(id)
	if not jonin then
		return false
	end
	local defeated = Jonin.setHealth(jonin, value)
	if defeated then
		local butai = jonin.butai
		jonin.butai = nil
		poisonOf[jonin.id] = nil
		overrideOf[jonin.id] = nil
		returningOf[jonin.id] = nil
		if butai then
			ButaiService.loseJonin(butai)
		end
	end
	publish(jonin)
	if defeated then
		local credited = if attacker and attacker.Parent then attacker else nil
		if credited then
			PlayerService.addGekihasu(credited)
		end
		defeatedEvent:Fire(jonin.id, credited)
	end
	return true
end

-- 上忍か首領の被ダメージの受け口。プレイヤーの攻撃も秘計もここを通す。
-- power は防御で軽減する前の威力（技の倍率 × 攻撃。秘計は Config.luau の威力）。与ダメージは Stats.damage で防御で軽減する。
-- attacker は攻撃したプレイヤー（倒したら撃破数に数える。NPC の秘計などは nil）、hit を渡すと個体が反応する。
-- 与えたダメージと、これで倒れたかを返す。いないか倒れていれば 0 と false
function JoninService.damage(id: string, power: number, attacker: Player?, hit: Hit?): (number, boolean)
	local jonin = find(id)
	if not jonin or Jonin.isDefeated(jonin) or power <= 0 then
		return 0, false
	end
	local amount = Stats.damage(1, power, jonin.stats.Defense)
	JoninService.setHealth(id, jonin.health - amount, attacker)
	damagedEvent:Fire(id, amount, hit)
	return amount, Jonin.isDefeated(jonin)
end

-- 毒にする。毒の間は Config.luau の Poison 節の間隔ごとに Damage を与え、とどめは attacker の撃破に数える。
-- 毒の間にもう一度付けたら、残りの時間を Duration に戻す。いないか倒れていれば false
function JoninService.poison(id: string, attacker: Player?): boolean
	local jonin = find(id)
	if not jonin or Jonin.isDefeated(jonin) then
		return false
	end
	-- 時刻の足し算の誤差で回数がぶれないよう、回数で数える
	local ticks = math.max(math.round(Config.Poison.Duration / Config.Poison.Interval), 1)
	local current = poisonOf[id]
	if current then
		current.ticks = ticks
		current.attacker = attacker or current.attacker
		return true
	end
	poisonOf[id] = {
		attacker = attacker,
		nextTick = os.clock() + Config.Poison.Interval,
		ticks = ticks,
	}
	return true
end

-- 毒の間か
function JoninService.isPoisoned(id: string): boolean
	return poisonOf[id] ~= nil
end

-- 毒の間の上忍と首領に、間隔ごとに毒のダメージを与える。切れた毒は外す
local function updatePoison(now: number)
	for id, poison in table.clone(poisonOf) do
		local jonin = find(id)
		while jonin and not Jonin.isDefeated(jonin) and poison.ticks > 0 and now >= poison.nextTick do
			poison.nextTick += Config.Poison.Interval
			poison.ticks -= 1
			local attacker = if poison.attacker and poison.attacker.Parent then poison.attacker else nil
			JoninService.setHealth(id, jonin.health - Config.Poison.Damage, attacker)
		end
		if not jonin or Jonin.isDefeated(jonin) or poison.ticks <= 0 then
			poisonOf[id] = nil
		end
	end
end

-- 個体として出ているかを書く（JoninKotaiService が呼ぶ）。出ている間は部隊に追従させず、個体の位置を写してもらう
function JoninService.setKotai(id: string, present: boolean)
	local jonin = find(id)
	if present then
		kotaiOf[id] = true
	else
		kotaiOf[id] = nil
	end
	if jonin then
		publish(jonin)
	end
end

-- 個体として出ているか
function JoninService.isKotai(id: string): boolean
	return kotaiOf[id] == true
end

-- 個体が戻る位置。目的地を差し替えていればその目的地（関数が nil を返したら今の位置）、率いる部隊があればその位置、
-- 首領は本陣の中心、部隊を失った上忍は今の位置。いなければ nil
function JoninService.homeOf(id: string): Jonin.Point?
	local jonin = find(id)
	if not jonin then
		return nil
	end
	local override = overrideOf[id]
	if override then
		local target = override()
		return if target then { x = target.x, z = target.z } else { x = jonin.position.x, z = jonin.position.z }
	end
	local butai = if jonin.butai then ButaiService.get(jonin.butai) else nil
	if butai then
		return { x = butai.position.x, z = butai.position.z }
	end
	local range = if jonin.shuryo then honjinRangeOf[jonin.id] else nil
	if range then
		local center = range.cframe.Position
		return { x = center.X, z = center.Z }
	end
	return { x = jonin.position.x, z = jonin.position.z }
end

-- 上忍の目的地を差し替える（秘計の挑発）。mokutekichi は今の目的地を返す関数で、nil を返したら今の位置にとどまる。
-- 差し替えている間は部隊に追従せず、目的地へ歩く。首領と、いないか倒れた上忍は差し替えずに false
function JoninService.overrideMokutekichi(id: string, mokutekichi: () -> Jonin.Point?): boolean
	local jonin = find(id)
	if not jonin or jonin.shuryo or Jonin.isDefeated(jonin) then
		return false
	end
	overrideOf[id] = mokutekichi
	returningOf[id] = nil
	return true
end

-- 差し替えた目的地を外す。率いる部隊があれば、歩いて部隊へ戻ってから追従に戻る。差し替えていなければ false
function JoninService.releaseMokutekichi(id: string): boolean
	if not overrideOf[id] then
		return false
	end
	overrideOf[id] = nil
	local jonin = find(id)
	if jonin and jonin.butai and not Jonin.isDefeated(jonin) then
		returningOf[id] = true
	end
	return true
end

-- 部隊から離れているか（目的地を差し替えているか、部隊へ戻る途中か）
local function isAway(id: string): boolean
	return overrideOf[id] ~= nil or returningOf[id] == true
end

-- 秘計 hikeiId の効果の補正を足すか（modifiers を渡す）、外す（nil を渡す）。いなければ false
function JoninService.setHikeiHosei(id: string, hikeiId: string, modifiers: { Stats.Modifier }?): boolean
	local jonin = find(id)
	if not jonin then
		return false
	end
	Jonin.setHikeiHosei(jonin, hikeiId, modifiers)
	return true
end

-- 位置を書き換えて複製する。首領は本陣の範囲の外へ出さず、範囲の縁へ寄せる。いなければ false
function JoninService.setPosition(id: string, position: Jonin.Point): boolean
	local jonin = find(id)
	if not jonin then
		return false
	end
	local x, z = position.x, position.z
	local range = if jonin.shuryo then honjinRangeOf[jonin.id] else nil
	if range then
		local offset = range.cframe:PointToObjectSpace(Vector3.new(x, range.cframe.Position.Y, z))
		local localX, localZ = Hoshin.clampToRange(offset.X, offset.Z, range.size.X, range.size.Z)
		local world = range.cframe:PointToWorldSpace(Vector3.new(localX, 0, localZ))
		x, z = world.X, world.Z
	end
	jonin.position = { x = x, z = z }
	publish(jonin)
	return true
end

local function clear()
	table.clear(joninList)
	table.clear(honjinRangeOf)
	table.clear(kotaiOf)
	table.clear(poisonOf)
	table.clear(overrideOf)
	table.clear(returningOf)
	folder:ClearAllChildren()
end

-- 出撃したステージの配置から上忍と首領を作る。配置の構成が無いステージでは作らない
local function onStarted(info: StageService.StartInfo)
	clear()
	local stage = Stages.get(info.stageId)
	local haichi = Haichi.get(info.stageId)
	if not stage or not haichi then
		return
	end
	local loaded = HaichiService.load(info.stageId)
	if not loaded then
		return
	end
	local centers: { [string]: Jonin.Point } = {}
	local ranges: { [string]: { cframe: CFrame, size: Vector3 } } = {}
	for _, kyoten in loaded.kyoten do
		local position = kyoten.cframe.Position
		centers[kyoten.id] = { x = position.X, z = position.Z }
		ranges[kyoten.id] = { cframe = kyoten.cframe, size = kyoten.size }
	end
	for _, entry in Jonin.entriesOf(haichi, stage) do
		local position = centers[entry.kyoten]
		if not position then
			warn(`JoninService: {entry.id} のいる拠点 {entry.kyoten} の目印が無いので出さない`)
			continue
		end
		local jonin = Jonin.new(entry, position, info.partySize)
		table.insert(joninList, jonin)
		if entry.shuryo then
			honjinRangeOf[entry.id] = ranges[entry.kyoten]
		end
		publish(jonin)
	end
end

-- データの位置を、上忍の歩く速さで dt 秒ぶん target へ進める。target から HomeRadius 以内に着いたら true
local function walk(jonin: Jonin.Jonin, target: Jonin.Point, dt: number): boolean
	local position, arrived =
		Jonin.approach(jonin.position, target, jonin.stats.WalkSpeed * dt, Config.Jittaikaken.HomeRadius)
	if position.x ~= jonin.position.x or position.z ~= jonin.position.z then
		JoninService.setPosition(jonin.id, position)
	end
	return arrived
end

-- 部隊へ戻る途中の上忍を進める。個体が出ていなければデータの位置を dt 秒ぶん歩かせる（個体は JoninKotaiService が歩かせる）。
-- 部隊の位置から HomeRadius 以内に着いたら戻る途中を終え、true を返す（部隊への追従に戻る）
local function walkBack(jonin: Jonin.Jonin, butai: Butai.Butai, dt: number): boolean
	local arrived: boolean
	if kotaiOf[jonin.id] then
		local dx, dz = butai.position.x - jonin.position.x, butai.position.z - jonin.position.z
		arrived = dx * dx + dz * dz <= Config.Jittaikaken.HomeRadius ^ 2
	else
		arrived = walk(jonin, butai.position, dt)
	end
	if arrived then
		returningOf[jonin.id] = nil
	end
	return arrived
end

-- 倒れていない上忍を、率いる部隊の位置へ合わせる。戦闘のフェーズで部隊が消えていたら、率いる部隊を外してその場に残す。
-- 目的地を差し替えた上忍と部隊へ戻る途中の上忍は、合わせずに dt 秒ぶん歩かせる。
-- 個体として出ている上忍は、個体が位置を決めるので合わせない
local function follow(dt: number)
	local battle = StageService.getPhase() == "Battle"
	for _, jonin in joninList do
		if Jonin.isDefeated(jonin) then
			continue
		end
		local id = jonin.butai
		local butai = if id then ButaiService.get(id) else nil
		if id and not butai and battle then
			jonin.butai = nil
			returningOf[jonin.id] = nil
			publish(jonin)
		end
		local override = overrideOf[jonin.id]
		if override then
			local target = if kotaiOf[jonin.id] then nil else override()
			if target then
				walk(jonin, target, dt)
			end
			continue
		end
		if not butai or kotaiOf[jonin.id] then
			if butai and returningOf[jonin.id] then
				walkBack(jonin, butai, dt)
			end
			continue
		end
		if returningOf[jonin.id] and not walkBack(jonin, butai, dt) then
			continue
		end
		if butai.position.x ~= jonin.position.x or butai.position.z ~= jonin.position.z then
			jonin.position = { x = butai.position.x, z = butai.position.z }
			publish(jonin)
		end
	end
end

-- 上忍と首領が自分の軍の支配エリアの中かを確かめ、変わったら能力値を求め直す。倒れた上忍は外にいるものとする
local function refreshShihaiArea()
	local provider = shihaiAreaProvider
	for _, jonin in joninList do
		local inside = not Jonin.isDefeated(jonin) and provider ~= nil and provider(jonin.gun, jonin.position)
		Jonin.setShihaiArea(jonin, inside)
	end
end

local function joninSide(jonin: Jonin.Jonin, butai: Butai.Butai): Kosen.JoninSide
	return {
		gun = jonin.gun,
		health = jonin.health,
		attack = jonin.stats.Attack,
		defense = jonin.stats.Defense,
		shiki = butai.shiki,
	}
end

-- 交戦中の部隊どうしが両方とも上忍に率いられていれば、上忍同士を dt 秒戦わせる。戦闘のフェーズの外では戦わせない。
-- 部隊から離れている上忍（目的地を差し替えているか、部隊へ戻る途中）は戦わせない
local function fightJonin(dt: number)
	if StageService.getPhase() ~= "Battle" or dt <= 0 then
		return
	end
	local fought: { [string]: boolean } = {}
	for _, jonin in table.clone(joninList) do
		local butaiId = jonin.butai
		if not butaiId or fought[jonin.id] or Jonin.isDefeated(jonin) or isAway(jonin.id) then
			continue
		end
		local butai = ButaiService.get(butaiId)
		local aiteId = ButaiService.aiteOf(butaiId)
		local aite = if aiteId then ButaiService.get(aiteId) else nil
		local other = if aite and aite.jonin then find(aite.jonin) else nil
		if
			not butai
			or not aite
			or not other
			or other.butai ~= aite.id
			or Jonin.isDefeated(other)
			or isAway(other.id)
		then
			continue
		end
		fought[jonin.id] = true
		fought[other.id] = true
		local result = Kosen.joninStep(joninSide(jonin, butai), joninSide(other, aite), dt)
		if result.a ~= jonin.health then
			JoninService.setHealth(jonin.id, result.a)
		end
		if result.b ~= other.health then
			JoninService.setHealth(other.id, result.b)
		end
	end
end

local function round(value: number): number
	return math.round(value * 10) / 10
end

-- 窓口の DamageJonin で反応を付けるときの、吹き飛ばす強さ（技の Knockback と同じ。刀セットの C1 ほど）
local DEBUG_KNOCKBACK = 50

local function registerDebugCommands()
	DebugCommand.register(
		"DumpJonin",
		"",
		"出撃したステージの上忍と首領（体力・攻撃・防御・支配エリアの中か・秘計の効果の補正・個体として出ているか・毒の残り秒数・"
			.. "差し替えた目的地・部隊へ戻る途中か・位置）を JSON で返す",
		function()
			local result = {}
			for _, jonin in joninList do
				local hikeiHosei = {}
				for hikeiId in jonin.hikeiHosei do
					table.insert(hikeiHosei, hikeiId)
				end
				table.sort(hikeiHosei)
				local poison = poisonOf[jonin.id]
				local mokutekichi = if overrideOf[jonin.id] then JoninService.homeOf(jonin.id) else nil
				table.insert(result, {
					id = jonin.id,
					name = jonin.displayName,
					gun = jonin.gun,
					shuryo = jonin.shuryo,
					butai = jonin.butai,
					kyoten = jonin.kyoten,
					health = round(jonin.health),
					maxHealth = round(jonin.stats.MaxHealth),
					attack = round(jonin.stats.Attack),
					defense = round(jonin.stats.Defense),
					shihaiArea = jonin.shihaiArea,
					hikeiHosei = if #hikeiHosei > 0 then hikeiHosei else nil,
					kotai = if kotaiOf[jonin.id] then true else nil,
					poison = if poison
						then math.max(
							round(poison.nextTick - os.clock() + (poison.ticks - 1) * Config.Poison.Interval),
							0
						)
						else nil,
					mokutekichi = if mokutekichi then { round(mokutekichi.x), round(mokutekichi.z) } else nil,
					returning = if returningOf[jonin.id] then true else nil,
					position = { round(jonin.position.x), round(jonin.position.z) },
				})
			end
			return HttpService:JSONEncode(result)
		end
	)
	DebugCommand.register(
		"SetJoninPosition",
		"<キャラクター ID> <x> <z>",
		"上忍か首領の位置を書き換える。首領は本陣の範囲の外へ出さず、範囲の縁へ寄せる。上忍は次の間隔で率いる部隊の位置へ戻る（確認用）",
		function(id, x, z)
			local position = { x = DebugCommand.toNumber(x, "x"), z = DebugCommand.toNumber(z, "z") }
			if type(id) ~= "string" or not JoninService.setPosition(id, position) then
				return `{tostring(id)} は出撃したステージの上忍と首領にいない`
			end
			local jonin = find(id) :: Jonin.Jonin
			return `{jonin.displayName} の位置を ({round(jonin.position.x)}, {round(jonin.position.z)}) にした`
		end
	)
	DebugCommand.register(
		"WarpToJonin",
		"<プレイヤー名> <キャラクター ID>",
		"プレイヤーを上忍か首領のいる位置（南へ 5 スタッドずらす）へ移す（上忍や首領が使う秘計の確認用）",
		function(name, id)
			local player = DebugCommand.findPlayer(name)
			local jonin = if type(id) == "string" then find(id) else nil
			if not jonin then
				return `{tostring(id)} は出撃したステージの上忍と首領にいない`
			end
			local character = player.Character
			if not character or not character:FindFirstChild("HumanoidRootPart") then
				return `{player.Name} のキャラクターがいない`
			end
			local x, z = jonin.position.x, jonin.position.z + 5
			local y = Ground.heightAt(x, z) or 0
			character:PivotTo(CFrame.new(x, y + 5, z))
			return `{player.Name} を {jonin.displayName} のいる ({round(x)}, {round(z)}) へ移した`
		end
	)
	DebugCommand.register(
		"SetJoninHealth",
		"<キャラクター ID> <体力>",
		"上忍か首領の体力を書き換える。0 にすると倒れ、率いていた部隊の士気が下がる（確認用）",
		function(id, value)
			local health = DebugCommand.toNumber(value, "体力")
			if type(id) ~= "string" or not JoninService.setHealth(id, health) then
				return `{tostring(id)} は出撃したステージの上忍と首領にいない`
			end
			local jonin = find(id) :: Jonin.Jonin
			local state = if Jonin.isDefeated(jonin) then "（倒れた）" else ""
			return `{jonin.displayName} の体力を {jonin.health} / {jonin.stats.MaxHealth} にした{state}`
		end
	)
	DebugCommand.register(
		"DamageJonin",
		`<キャラクター ID> <威力> [プレイヤー名] [{table.concat(
			{ "None", "Flinch", "Knockback", "Launch" },
			"|"
		)}]`,
		"被ダメージの受け口（damage）で上忍か首領に攻撃を当てる。威力は防御で軽減する前の値。プレイヤー名を渡すと、その人の攻撃として"
			.. "撃破数に数え、反応（既定は None）の攻撃元をその人の位置にする（確認用）",
		function(id, value, playerName, reaction)
			local power = DebugCommand.toNumber(value, "威力")
			local jonin = if type(id) == "string" then find(id) else nil
			if not jonin then
				return `{tostring(id)} は出撃したステージの上忍と首領にいない`
			end
			local player = if playerName ~= nil then DebugCommand.findPlayer(playerName) else nil
			local kind = reaction or "None"
			if not table.find({ "None", "Flinch", "Knockback", "Launch" }, kind) then
				error(`反応は None、Flinch、Knockback、Launch のどれか（{tostring(kind)}）`, 0)
			end
			local hit: Hit? = nil
			local root = player
				and player.Character
				and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if kind ~= "None" then
				local origin = if root then root.Position else Vector3.new(jonin.position.x, 0, jonin.position.z + 5)
				hit = { reaction = kind :: Config.Reaction, origin = origin, force = DEBUG_KNOCKBACK }
			end
			local before = jonin.health
			local amount, defeated = JoninService.damage(jonin.id, power, player, hit)
			local state = if defeated then "（倒れた）" else ""
			return `{jonin.displayName} に {round(amount)} のダメージ（体力 {round(before)} → {round(
				jonin.health
			)}）{state}`
		end
	)
	DebugCommand.register(
		"PoisonJonin",
		"<キャラクター ID> [プレイヤー名]",
		"上忍か首領を毒にする。プレイヤー名を渡すと、毒でのとどめをその人の撃破に数える（確認用）",
		function(id, playerName)
			local player = if playerName ~= nil then DebugCommand.findPlayer(playerName) else nil
			if type(id) ~= "string" or not JoninService.poison(id, player) then
				return `{tostring(id)} は出撃したステージの上忍と首領にいないか、倒れている`
			end
			local jonin = find(id) :: Jonin.Jonin
			return `{jonin.displayName} を毒にした（{Config.Poison.Duration} 秒）`
		end
	)
end

function JoninService.start()
	local created = Instance.new("Folder")
	created.Name = JoninService.FOLDER
	created.Parent = ReplicatedStorage
	folder = created

	StageService.started:Connect(onStarted)
	StageService.finished:Connect(clear)
	StageService.phaseChanged:Connect(function(next: StagePhase.Phase)
		if next == "Lobby" then
			clear()
		end
	end)
	registerDebugCommands()

	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(Config.Butai.MoveInterval)
			local now = os.clock()
			-- 1回の失敗で追従と戦いが止まらないよう、失敗は警告にして次の間隔で続ける
			local ok, err = pcall(follow, now - last)
			if not ok then
				warn(`JoninService: 上忍を部隊に合わせられなかった: {err}`)
			end
			local areaOk, areaErr = pcall(refreshShihaiArea)
			if not areaOk then
				warn(`JoninService: 支配エリアの補正を求め直せなかった: {areaErr}`)
			end
			local fightOk, fightErr = pcall(fightJonin, now - last)
			if not fightOk then
				warn(`JoninService: 上忍同士を戦わせられなかった: {fightErr}`)
			end
			local poisonOk, poisonErr = pcall(updatePoison, now)
			if not poisonOk then
				warn(`JoninService: 毒のダメージを与えられなかった: {poisonErr}`)
			end
			last = now
		end
	end)
end

return JoninService
