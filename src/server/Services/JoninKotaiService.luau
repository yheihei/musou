--!strict
-- 実体化圏で、上忍と首領（両軍）の個体を出し入れする。データ（体力・位置・率いる部隊）は JoninService が持ち、
-- ここは Humanoid のモデルを出して、データの位置と体力に合わせる。半径と間隔は Config.luau の Jittaikaken 節、
-- 出す・消すの判定は ReplicatedStorage.Shared.Jittaikaken にある（下忍の個体は #76）。
--
-- - 戦闘のフェーズの間、Interval ごとに、出撃して残っているメンバーとの水平の距離で出し入れを決める。
--   AppearRadius 以内に入ったら出し、全員から DisappearRadius より離れたら消す。戦闘のフェーズが終わったら全部消す
-- - 見た目は仮の見た目の共通関数（Appearance.createModel）の名札と武器に、軍の色の体力バーを足す。
--   出す位置の高さは地面の高さの共通関数（Ground.placeCharacter）で決める
-- - 体はプレイヤーにもほかの個体にもぶつからない（CollisionGroups の Enemy と Mikatagun）
-- - 体力はデータに持つ。個体の Humanoid の体力とバーは、データの体力に合わせる。消えて出直しても体力は残る
-- - 出ている間は、個体の位置をデータの位置へ写す（JoninService.setPosition。首領は本陣の範囲に収まる）。
--   データが戻る位置（JoninService.homeOf。率いる部隊の位置、首領は本陣の中心）から HomeRadius より離れたら歩いて戻る
-- - 攻撃を受けたら（JoninService.damaged）、反応（Combat/Hanno）を始める。上忍と首領は Config.luau の
--   EnemyReaction 節の JoninScale で短く飛び、JoninFlinchScale でのけぞりを弱める。のけぞらない状態（秘計の鬼神化）かは
--   addNoFlinchProvider で登録した関数に聞く
-- - 倒れたら（JoninService.defeated）、その場に倒れ、CorpseLifetime 秒後に消える。倒れた上忍と首領は出さない
-- - 奈落に落ちた個体は消し、データの位置を戻る位置へ戻す（近くにプレイヤーがいれば、次の間隔でそこに出直す）
-- - 毒の間（JoninService.isPoisoned）は、緑の煙（Fire）の仮の見た目を出す
-- - 攻撃判定の対象は getTargets で軍ごとに引く。対象の ref は個体のモデルで、idOf でキャラクター ID に戻す

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Appearance = require(ReplicatedStorage.Shared.Appearance)
local Colors = require(ReplicatedStorage.Shared.Colors)
local Config = require(ReplicatedStorage.Shared.Config)
local Ground = require(ReplicatedStorage.Shared.Ground)
local Gun = require(ReplicatedStorage.Shared.Gun)
local HitShape = require(ReplicatedStorage.Shared.HitShape)
local Jittaikaken = require(ReplicatedStorage.Shared.Jittaikaken)
local Jonin = require(ReplicatedStorage.Shared.Jonin)
local StagePhase = require(ReplicatedStorage.Shared.StagePhase)
local DebugCommand = require(script.Parent.Parent.DebugCommand)
local CollisionGroups = require(script.Parent.Parent.CollisionGroups)
local Hanno = require(script.Parent.Parent.Combat.Hanno)
local JoninService = require(script.Parent.JoninService)
local StageService = require(script.Parent.StageService)

-- 出ている個体
type Kotai = {
	id: string,
	gun: Gun.Gun,
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	-- 攻撃判定で使う水平の半径
	radius: number,
	-- 攻撃を受けた反応（Combat/Hanno）
	body: Hanno.Body,
	-- 倒れて消えるのを待っているか
	dying: boolean,
	-- 体力バーに出している残りの割合
	barRate: number?,
}

local JoninKotaiService = {}

-- 個体を置く workspace のフォルダの名前
JoninKotaiService.FOLDER = "JoninKotai"

-- 毒の間に出す緑の煙の名前と色（仮の湧き処理の敵と同じ見た目）
local POISON_NAME = "Doku"
local POISON_COLOR = Color3.fromRGB(110, 210, 70)
local POISON_SECONDARY_COLOR = Color3.fromRGB(40, 110, 30)

-- 地面が見つからず出せなかった個体を、出し直すまで待つ秒数（警告を出し続けないため）
local SPAWN_RETRY_TIME = 5

local folder: Folder
-- キャラクター ID から引く、個体の雛形（仮の見た目の名札と武器まで付けたもの）
local templates: { [string]: Model } = {}
-- キャラクター ID から引く、地面が見つからず出せなかった時刻（os.clock）
local spawnFailedAt: { [string]: number } = {}
-- キャラクター ID から引く、出ている個体（倒れて消えるのを待つ個体を含む）
local kotaiOf: { [string]: Kotai } = {}
-- 個体のモデルから引くキャラクター ID
local idOfModel: { [Model]: string } = {}
-- 上忍か首領がのけぞらない状態かを返す関数（秘計の鬼神化が登録する）
local noFlinchProviders: { (id: string) -> boolean } = {}

-- 上忍か首領がのけぞらない状態かを返す関数を登録する。どれかが true を返せば、のけぞりを起こさない
function JoninKotaiService.addNoFlinchProvider(provider: (id: string) -> boolean)
	table.insert(noFlinchProviders, provider)
end

local function isNoFlinch(id: string): boolean
	for _, provider in noFlinchProviders do
		if provider(id) then
			return true
		end
	end
	return false
end

-- 個体のモデルのキャラクター ID。個体でなければ nil
function JoninKotaiService.idOf(model: Model): string?
	return idOfModel[model]
end

-- 出ている個体のモデル（倒れて消えるのを待つ個体を含む）。出ていなければ nil
function JoninKotaiService.modelOf(id: string): Model?
	local kotai = kotaiOf[id]
	return if kotai then kotai.model else nil
end

-- 攻撃判定の対象にする、軍 gun の倒れていない個体の位置と半径。ref は個体のモデル
function JoninKotaiService.getTargets(gun: Gun.Gun): { HitShape.Target<Model> }
	local targets = {}
	for _, kotai in kotaiOf do
		if kotai.gun == gun and not kotai.dying and kotai.humanoid.Health > 0 then
			table.insert(targets, { ref = kotai.model, position = kotai.root.Position, radius = kotai.radius })
		end
	end
	return targets
end

-- 出撃して残っているメンバーの水平の位置
local function memberPoints(): { Jittaikaken.Point }
	local points = {}
	for _, member in StageService.getMembers() do
		local root = member.Character and member.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			table.insert(points, { x = root.Position.X, z = root.Position.Z })
		end
	end
	return points
end

local function removePoisonLook(kotai: Kotai)
	local fire = kotai.root:FindFirstChild(POISON_NAME)
	if fire then
		fire:Destroy()
	end
end

local function showPoisonLook(kotai: Kotai)
	if kotai.root:FindFirstChild(POISON_NAME) then
		return
	end
	local fire = Instance.new("Fire")
	fire.Name = POISON_NAME
	fire.Color = POISON_COLOR
	fire.SecondaryColor = POISON_SECONDARY_COLOR
	fire.Size = 3
	fire.Heat = 2
	fire.Parent = kotai.root
end

-- 個体を消す。データには、出ていないことだけを書く
local function despawn(id: string)
	local kotai = kotaiOf[id]
	if not kotai then
		return
	end
	kotaiOf[id] = nil
	idOfModel[kotai.model] = nil
	Hanno.forget(kotai.body)
	kotai.model:Destroy()
	JoninService.setKotai(id, false)
end

-- 個体の体力とバーを、データの体力に合わせる
local function syncHealth(kotai: Kotai, jonin: Jonin.Jonin)
	local maxHealth = jonin.stats.MaxHealth
	if kotai.humanoid.MaxHealth ~= maxHealth then
		kotai.humanoid.MaxHealth = maxHealth
	end
	if kotai.humanoid.Health ~= jonin.health and not kotai.dying then
		kotai.humanoid.Health = jonin.health
	end
	local rate = if maxHealth > 0 then jonin.health / maxHealth else 0
	if kotai.barRate ~= rate then
		kotai.barRate = rate
		Appearance.setHealthBar(kotai.model, rate)
	end
end

-- 奈落に落ちた個体を消し、データの位置を戻る位置へ戻す
local function onFell(id: string)
	despawn(id)
	local home = JoninService.homeOf(id)
	if home then
		JoninService.setPosition(id, home)
	end
end

-- キャラクターの個体の雛形。初めて出すときに作る
local function templateOf(id: string): Model
	local template = templates[id]
	if not template then
		template = Appearance.createModel(id)
		templates[id] = template
	end
	return template :: Model
end

-- データの上忍か首領の個体を、データの位置の地面の上に出す。地面が無ければ出さずに nil を返す
local function spawn(jonin: Jonin.Jonin, now: number): Kotai?
	local failedAt = spawnFailedAt[jonin.id]
	if failedAt and now - failedAt < SPAWN_RETRY_TIME then
		return nil
	end
	local model = templateOf(jonin.id):Clone()
	model.Name = jonin.id
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	humanoid.MaxHealth = jonin.stats.MaxHealth
	humanoid.Health = jonin.health
	humanoid.WalkSpeed = jonin.stats.WalkSpeed
	humanoid.BreakJointsOnDeath = false
	Appearance.attachHealthBar(model, Colors.Gun[jonin.gun])
	model:SetAttribute("Gun", jonin.gun)
	CollisionGroups.apply(model, CollisionGroups.kotaiGroupOf(jonin.gun))
	if not Ground.placeCharacter(model, jonin.position.x, jonin.position.z) then
		model:Destroy()
		spawnFailedAt[jonin.id] = now
		return nil
	end
	spawnFailedAt[jonin.id] = nil
	model.Parent = folder
	-- 吹き飛びの挙動を安定させるため物理はサーバーが持つ
	root:SetNetworkOwner(nil)

	local size = model:GetExtentsSize()
	local reaction = Config.EnemyReaction
	local id = jonin.id
	local kotai: Kotai = {
		id = id,
		gun = jonin.gun,
		model = model,
		humanoid = humanoid,
		root = root,
		radius = math.max(size.X, size.Z) / 2,
		body = Hanno.newBody(model, humanoid, root, {
			scale = reaction.JoninScale,
			flinchScale = reaction.JoninFlinchScale,
			onFell = function()
				onFell(id)
			end,
		}),
		dying = false,
		barRate = nil,
	}
	kotaiOf[id] = kotai
	idOfModel[model] = id
	syncHealth(kotai, jonin)
	JoninService.setKotai(id, true)
	return kotai
end

-- 出ている個体の位置をデータへ写し、戻る位置から離れていたら歩いて戻る。体力と毒の見た目もデータに合わせる
local function updateKotai(kotai: Kotai, jonin: Jonin.Jonin, now: number)
	syncHealth(kotai, jonin)
	if JoninService.isPoisoned(kotai.id) then
		showPoisonLook(kotai)
	else
		removePoisonLook(kotai)
	end
	local position = kotai.root.Position
	if position.X ~= jonin.position.x or position.Z ~= jonin.position.z then
		JoninService.setPosition(kotai.id, { x = position.X, z = position.Z })
	end
	if Hanno.busy(kotai.body, now) then
		return
	end
	local home = JoninService.homeOf(kotai.id)
	if not home then
		return
	end
	local dx, dz = home.x - position.X, home.z - position.Z
	if dx * dx + dz * dz > Config.Jittaikaken.HomeRadius ^ 2 then
		kotai.humanoid:MoveTo(Vector3.new(home.x, position.Y, home.z))
	else
		kotai.humanoid:Move(Vector3.zero)
	end
end

-- 攻撃を受けたら、体力を合わせてから反応を始める
local function onDamaged(id: string, _amount: number, hit: JoninService.Hit?)
	local kotai = kotaiOf[id]
	local jonin = JoninService.get(id)
	if not kotai or kotai.dying or not jonin then
		return
	end
	syncHealth(kotai, jonin)
	if hit then
		Hanno.react(kotai.body, hit, os.clock(), isNoFlinch(id))
	end
end

-- 倒れたら、その場に倒し、しばらくして消す
local function onDefeated(id: string)
	local kotai = kotaiOf[id]
	if not kotai or kotai.dying then
		return
	end
	kotai.dying = true
	removePoisonLook(kotai)
	kotai.barRate = 0
	Appearance.setHealthBar(kotai.model, 0)
	kotai.humanoid.Health = 0
	task.delay(Config.Jittaikaken.CorpseLifetime, function()
		if kotaiOf[id] == kotai then
			despawn(id)
		end
	end)
end

-- 戦闘のフェーズの間、上忍と首領の個体を出し入れし、出ている個体を進める
local function tick()
	if StageService.getPhase() ~= "Battle" then
		for id in table.clone(kotaiOf) do
			despawn(id)
		end
		return
	end
	local now = os.clock()
	local points = memberPoints()
	local alive: { [string]: boolean } = {}
	for _, jonin in JoninService.list() do
		local kotai = kotaiOf[jonin.id]
		if Jonin.isDefeated(jonin) then
			if kotai and not kotai.dying then
				onDefeated(jonin.id)
			end
			continue
		end
		alive[jonin.id] = true
		local present = kotai ~= nil and not kotai.dying
		local distance = Jittaikaken.nearestDistance(jonin.position, points)
		local appear = Jittaikaken.shouldAppear(present, distance)
		if appear and not kotai then
			kotai = spawn(jonin, now)
		elseif not appear and kotai and not kotai.dying then
			despawn(jonin.id)
			kotai = nil
		end
		if kotai and not kotai.dying then
			updateKotai(kotai, jonin, now)
		end
	end
	-- データから消えた上忍と首領の個体を消す（倒れて消えるのを待つ個体は残す）
	for id, kotai in table.clone(kotaiOf) do
		if not alive[id] and not kotai.dying then
			despawn(id)
		end
	end
end

local function round(value: number): number
	return math.round(value * 10) / 10
end

local function registerDebugCommands()
	DebugCommand.register(
		"DumpJoninKotai",
		"",
		"出ている上忍と首領の個体（軍・体力・反応の状態・倒れて消えるのを待つか・位置・一番近いメンバーまでの距離）を JSON で返す",
		function()
			local points = memberPoints()
			local list = {}
			for id, kotai in kotaiOf do
				local position = kotai.root.Position
				local distance = Jittaikaken.nearestDistance({ x = position.X, z = position.Z }, points)
				table.insert(list, {
					id = id,
					gun = kotai.gun,
					health = round(kotai.humanoid.Health),
					maxHealth = round(kotai.humanoid.MaxHealth),
					hanno = Hanno.kindOf(kotai.body),
					dying = if kotai.dying then true else nil,
					position = { round(position.X), round(position.Y), round(position.Z) },
					distance = if distance then round(distance) else nil,
				})
			end
			table.sort(list, function(a, b)
				return a.id < b.id
			end)
			return HttpService:JSONEncode(list)
		end
	)
end

function JoninKotaiService.start()
	local created = Instance.new("Folder")
	created.Name = JoninKotaiService.FOLDER
	created.Parent = workspace
	folder = created
	-- 飛んでいる個体の光線を、ほかの個体に当てない
	Hanno.excludeFolder(folder)

	JoninService.damaged:Connect(onDamaged)
	JoninService.defeated:Connect(onDefeated)
	StageService.phaseChanged:Connect(function(next: StagePhase.Phase)
		if next ~= "Battle" then
			for id in table.clone(kotaiOf) do
				despawn(id)
			end
			table.clear(spawnFailedAt)
		end
	end)
	registerDebugCommands()

	task.spawn(function()
		while true do
			task.wait(Config.Jittaikaken.Interval)
			-- 1回の失敗で出し入れが止まらないよう、失敗は警告にして次の間隔で続ける
			local ok, err = pcall(tick)
			if not ok then
				warn(`JoninKotaiService: 上忍と首領の個体を出し入れできなかった: {err}`)
			end
		end
	end)
end

return JoninKotaiService
