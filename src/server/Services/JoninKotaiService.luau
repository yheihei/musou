--!strict
-- 実体化圏で、上忍と首領（両軍）の個体を出し入れし、敵軍の個体を出撃メンバーと、味方軍の個体を敵軍の下忍と戦わせる。
-- データ（体力・位置・率いる部隊）は JoninService が持ち、ここは Humanoid のモデルを出して、データの位置と体力に合わせる。
-- 半径と間隔は Config.luau の Jittaikaken 節、出す・消すの判定は ReplicatedStorage.Shared.Jittaikaken にある（下忍の個体は #76）。
-- 戦い方の判断は ReplicatedStorage.Shared.Kata、型と数値は Config.luau の Kata 節にある。
--
-- - 戦闘のフェーズの間、Interval ごとに、出撃して残っているメンバーとの水平の距離で出し入れを決める。
--   AppearRadius 以内に入ったら出し、全員から DisappearRadius より離れたら消す。戦闘のフェーズが終わったら全部消す
--   （倒れて消えるのを待つ個体は、決着の後も CorpseLifetime 秒だけ残す）
-- - 見た目は仮の見た目の共通関数（Appearance.createModel）の名札と武器に、軍の色の体力バーを足す。
--   出す位置の高さは地面の高さの共通関数（Ground.placeCharacter）で決める
-- - 体はプレイヤーにもほかの個体にもぶつからない（CollisionGroups の Enemy と Mikatagun）
-- - 体力はデータに持つ。個体の Humanoid の体力とバーは、データの体力に合わせる。消えて出直しても体力は残る
-- - 出ている間は、個体の位置をデータの位置へ写す（JoninService.setPosition。首領は本陣の範囲に収まる）。
--   戦う相手がいなければ、データが戻る位置（JoninService.homeOf。率いる部隊の位置、首領は本陣の中心）から
--   HomeRadius より離れたら歩いて戻る
-- - 攻撃を受けたら（JoninService.damaged）、反応（Combat/Hanno）を始める。上忍と首領は Config.luau の
--   EnemyReaction 節の JoninScale で短く飛び、JoninFlinchScale でのけぞりを弱める。のけぞらない状態（秘計の鬼神化）かは
--   addNoFlinchProvider で登録した関数に聞く
-- - 倒れたら（JoninService.defeated）、その場に倒れ、CorpseLifetime 秒後に消える。倒れた上忍と首領は出さない
-- - 奈落に落ちた個体は消し、データの位置を戻る位置へ戻す（近くにプレイヤーがいれば、次の間隔でそこに出直す）
-- - 毒の間（JoninService.isPoisoned）は、緑の煙（Fire）の仮の見た目を出す
-- - 攻撃判定の対象は getTargets で軍ごとに引く。対象の ref は個体のモデルで、idOf でキャラクター ID に戻す
--
-- 戦い（考える間隔は出し入れと同じ Interval）
-- - 戦う相手は軍ごとの Aite（狙う相手の候補の一覧と、攻撃の当て方）で決める。敵軍の個体の相手は出撃メンバー。
--   味方軍の個体の相手は敵軍の下忍の体（EnemyService の敵軍の下忍の個体と、窓口で出した下忍と上忍）。
--   味方軍の個体は、プレイヤーと味方軍の下忍の個体と敵軍の上忍・首領の個体を狙わず、型も当てない
--   （上忍同士は部隊の交戦でデータの上で戦う）
-- - 下忍の個体は防御を持たないので、味方軍の個体の与ダメージは 型の倍率 × 攻撃 のまま（EnemyService.damage で当てる）。
--   攻撃したプレイヤーを渡さないので、倒しても誰の撃破数にも数えない。味方軍の上忍と首領は秘計を使わない（判断を呼ばない）
-- - 狙う相手は、最後に攻撃してきた相手（Kata 節の AttackerMemory 秒以内）か、一番近い相手。間合い（Maai）まで近づく。
--   上忍は戻る位置から ChaseRadius の円の中、首領は本陣の範囲の中を追いかけ、外へは出ない（縁へ寄せる）。
--   狙える相手がいなければ、戻る位置へ戻る
-- - 型を選べる時刻になったら、間合いに入っている型から重みで1つ選ぶ（首領は首領だけの型も選ぶ）。
--   狙う相手の方を向いて止まり、予備動作の間は足元に判定の範囲を描いて体を光らせる（敵軍は赤、味方軍は青）。
--   向きは変えないので、範囲を見て避けられる
-- - 判定は攻撃判定の形（HitShape）で出し、プレイヤーへのダメージは被ダメージの窓口（DamageService.damage）を通す。
--   威力は 型の倍率 × 攻撃（支配エリアと秘計の補正込み）で、防御の軽減・無敵・ガードは窓口が決める。後隙の間も動かない
-- - 型の時間は攻撃の速さで割る。型を出し終えたら、Interval 秒（に乱数の秒数を足した後）に次の型を選ぶ
-- - 型の最中に吹き飛びか打ち上げを受けたら、型をやめる。のけぞりの攻撃（通常攻撃）ではのけぞらず、型を続ける
-- - 型のモーションは、武器種の行動のモーションを流用し（Motions.forKata）、個体の Animator で再生する（ID が 0 なら再生しない）
-- - 敵軍の上忍と首領が考えるたびに、setHikeiDecider で登録した秘計の判断を呼ぶ。個体として出ていない上忍と首領にも呼ぶ
-- - 窓口の SetJoninAI false で戦いと秘計の判断を止める（個体は戻る位置へ戻る）。UseKata で型を1回出させる

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ActionState = require(ReplicatedStorage.Shared.ActionState)
local Appearance = require(ReplicatedStorage.Shared.Appearance)
local Colors = require(ReplicatedStorage.Shared.Colors)
local Config = require(ReplicatedStorage.Shared.Config)
local Ground = require(ReplicatedStorage.Shared.Ground)
local Gun = require(ReplicatedStorage.Shared.Gun)
local HitShape = require(ReplicatedStorage.Shared.HitShape)
local Hoshin = require(ReplicatedStorage.Shared.Hoshin)
local Jittaikaken = require(ReplicatedStorage.Shared.Jittaikaken)
local Jonin = require(ReplicatedStorage.Shared.Jonin)
local Kata = require(ReplicatedStorage.Shared.Kata)
local Motions = require(ReplicatedStorage.Shared.Motions)
local SoundPlayer = require(ReplicatedStorage.Shared.SoundPlayer)
local StagePhase = require(ReplicatedStorage.Shared.StagePhase)
local Stats = require(ReplicatedStorage.Shared.Stats)
local DebugCommand = require(script.Parent.Parent.DebugCommand)
local CollisionGroups = require(script.Parent.Parent.CollisionGroups)
local Hanno = require(script.Parent.Parent.Combat.Hanno)
local Hitbox = require(script.Parent.Parent.Combat.Hitbox)
local Vfx = require(script.Parent.Parent.Combat.Vfx)
local DamageService = require(script.Parent.DamageService)
local EnemyService = require(script.Parent.EnemyService)
local JoninService = require(script.Parent.JoninService)
local KyotenService = require(script.Parent.KyotenService)
local StageService = require(script.Parent.StageService)

-- 攻撃を当てた結果。result は被ダメージの窓口の結果（Hit・Invulnerable・Guard）、amount は与えたダメージ、
-- health は当てた後の相手の体力
export type HitResult = {
	result: string,
	amount: number,
	health: number?,
}

-- 個体が戦う相手。軍ごとに、狙う相手の候補の一覧と、攻撃の当て方を渡す
export type Aite = {
	-- 狙う相手と、判定を当てる相手の候補（位置と体の水平の半径）。ref は相手を見分ける値（プレイヤーは Player）
	list: () -> { HitShape.Target<Instance> },
	-- 相手 ref に、攻撃元の位置 origin・防御で軽減する前の威力 power・判定 hit の攻撃を当てる。当てられなければ nil
	hit: (ref: Instance, origin: Vector3, power: number, hit: Config.HitDef) -> HitResult?,
}

-- 秘計を使う判断に渡す、考える間隔ごとの敵軍の上忍か首領の様子
export type Situation = {
	-- 上忍か首領のデータ（体力・能力値・位置・首領か・率いる部隊）
	jonin: Jonin.Jonin,
	-- 個体として出ているか
	kotai: boolean,
	-- 個体が狙っている相手。個体が出ていないか、狙う相手がいなければ nil
	target: Instance?,
	-- 考えた時刻（os.clock）
	now: number,
}

-- 出している型
type Run = {
	-- 型 ID
	id: string,
	-- 判定を出す向き（予備動作を始めたときに、狙う相手の方を向いた向き）
	look: Vector3,
	-- 予備動作の足元の範囲と体の光
	marks: { Instance },
	-- 再生しているモーション
	track: AnimationTrack?,
}

-- 最後に型の判定を当てた結果（確認用）
type HitRecord = {
	kata: string,
	-- 当てた相手の名前
	target: string,
	result: string,
	amount: number,
	health: number?,
}

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
	-- 狙っている相手（Aite の候補の ref）
	target: Instance?,
	-- 最後に攻撃してきた相手と、その時刻（os.clock）
	lastAttacker: Instance?,
	lastAttackedAt: number,
	-- 次に型を選べる時刻（os.clock）
	nextKataAt: number,
	-- 出している型
	run: Run?,
	-- 最後に型の判定を当てた結果（確認用）
	lastHit: HitRecord?,
	-- 最後に反応の最中でなく立っていた水平の位置（奈落に落ちたときに戻す先）
	groundPoint: Kata.Point?,
	-- モーションの ID から引く、読み込んだトラック
	tracks: { [number]: AnimationTrack },
}

local JoninKotaiService = {}

-- 個体を置く workspace のフォルダの名前
JoninKotaiService.FOLDER = "JoninKotai"

-- 毒の間に出す緑の煙の名前と色（下忍の個体と同じ見た目）
local POISON_NAME = "Doku"
local POISON_COLOR = Color3.fromRGB(110, 210, 70)
local POISON_SECONDARY_COLOR = Color3.fromRGB(40, 110, 30)

-- 地面が見つからず出せなかった個体を、出し直すまで待つ秒数（警告を出し続けないため）
local SPAWN_RETRY_TIME = 5

-- 予備動作で地面に描く範囲と体の光の色、判定を出したときの仮エフェクトの色。
-- 予備動作は軍で色を分ける（味方軍の型はプレイヤーに当たらないので、避ける合図の赤にしない）
local YOBIDOSA_COLORS: { [Gun.Gun]: Color3 } = {
	Tekigun = Color3.fromRGB(255, 60, 40),
	Mikatagun = Color3.fromRGB(60, 150, 255),
}
local KATA_COLOR = Color3.fromRGB(255, 160, 80)
-- プレイヤーの体の水平の半径（型の判定に使う。胴の幅の半分に少し足す）
local PLAYER_RADIUS = 1.5
-- 近づく位置からこの距離（スタッド）より離れていなければ、歩かずにその場で止まる
local STOP_TOLERANCE = 0.75
-- 止まっている間に狙う相手の方へ向き直る、向きのずれの下限（度）
local TURN_THRESHOLD = 20
-- 型のモーションを始めるときと止めるときに、重ねて移る秒数
local MOTION_FADE_TIME = 0.1

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
-- 個体が相手と戦い、敵軍の上忍と首領が秘計を判断するか（窓口の SetJoninAI で切り替える。止めても攻撃の反応と毒は進む）
local aiEnabled = true
-- 敵軍の上忍と首領が考えるたびに呼ぶ、秘計を使う判断（#128 が登録する）
local hikeiDecider: ((situation: Situation) -> ())? = nil
-- 型の選択と、次の型を選べる時刻に使う乱数
local random = Random.new()

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

-- 倒れていない人のキャラクターの HumanoidRootPart。倒れているかキャラクターが無ければ nil
local function rootOf(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- 敵軍の個体の相手。出撃して残っているメンバーのうち倒れていない人に、被ダメージの窓口で攻撃を当てる
local MEMBER_AITE: Aite = {
	list = function(): { HitShape.Target<Instance> }
		local targets: { HitShape.Target<Instance> } = {}
		for _, member in StageService.getMembers() do
			local root = rootOf(member)
			if root then
				table.insert(targets, { ref = member, position = root.Position, radius = PLAYER_RADIUS })
			end
		end
		return targets
	end,
	hit = function(ref: Instance, origin: Vector3, power: number, hit: Config.HitDef): HitResult?
		if not ref:IsA("Player") then
			return nil
		end
		local player = ref :: Player
		local outcome = DamageService.damage(player, { origin = origin, power = power, reaction = hit.Reaction })
		if not outcome then
			return nil
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		return { result = outcome.result, amount = outcome.amount, health = if humanoid then humanoid.Health else nil }
	end,
}

-- 味方軍の個体の命中の音を最後に鳴らした時刻（os.clock）
local lastEnemyHitSoundAt = -math.huge

-- 味方軍の個体の相手。敵軍の下忍の個体と、窓口で出した敵（下忍と上忍）に攻撃を当てる。
-- プレイヤーと味方軍の下忍の個体と上忍・首領の個体は候補に入れない。下忍の個体は防御を持たないので、与ダメージは威力のまま
-- （Stats.damage の防御 0）。攻撃したプレイヤーを渡さないので、倒しても誰の撃破数にも数えない（倒れた個体は部隊の兵数を1減らす）
local ENEMY_AITE: Aite = {
	list = function(): { HitShape.Target<Instance> }
		local targets: { HitShape.Target<Instance> } = {}
		for _, target in EnemyService.getTargets(Gun.opponentOf("Mikatagun")) do
			table.insert(targets, { ref = target.ref, position = target.position, radius = target.radius })
		end
		return targets
	end,
	hit = function(ref: Instance, origin: Vector3, power: number, hit: Config.HitDef): HitResult?
		if not ref:IsA("Model") then
			return nil
		end
		local model = ref :: Model
		local amount = Stats.damage(1, power, 0)
		local reaction = { reaction = hit.Reaction, origin = origin, force = hit.Knockback }
		if not EnemyService.damage(model, amount, nil, reaction) then
			return nil
		end
		Vfx.hit(model)
		-- まとめて当てたときに重ならないよう、命中の音は間隔を空けて鳴らす
		local now = os.clock()
		if now - lastEnemyHitSoundAt >= Config.Sound.HitInterval then
			lastEnemyHitSoundAt = now
			SoundPlayer.playAt("Hit", model:GetPivot().Position)
		end
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		return { result = "Hit", amount = amount, health = if humanoid then humanoid.Health else nil }
	end,
}

-- 軍から引く、個体が戦う相手
local aiteByGun: { [Gun.Gun]: Aite } = { Tekigun = MEMBER_AITE, Mikatagun = ENEMY_AITE }

-- 軍 gun の個体が戦う相手を決める（nil で戦わせない）。相手の一覧と攻撃の当て方を渡せば、同じ戦い方を使える
function JoninKotaiService.setAite(gun: Gun.Gun, aite: Aite?)
	aiteByGun[gun] = aite
end

-- 敵軍の上忍と首領が考えるたびに呼ぶ、秘計を使う判断を登録する（nil で外す）。個体として出ていない上忍と首領にも呼ぶ。
-- 判断の中で HikeiService.useByJonin を呼んで秘計を使う（#128）
function JoninKotaiService.setHikeiDecider(decider: ((situation: Situation) -> ())?)
	hikeiDecider = decider
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

-- 出している型をやめる。予備動作の見た目とモーションを消し、次の型を選べる時刻を決め直す
local function cancelRun(kotai: Kotai, now: number)
	local run = kotai.run
	if not run then
		return
	end
	kotai.run = nil
	for _, mark in run.marks do
		mark:Destroy()
	end
	local track = run.track
	if track then
		track:Stop(MOTION_FADE_TIME)
	end
	kotai.nextKataAt = Kata.nextTime(now, random:NextNumber())
end

-- 個体を消す。データには、出ていないことだけを書く
local function despawn(id: string)
	local kotai = kotaiOf[id]
	if not kotai then
		return
	end
	kotaiOf[id] = nil
	idOfModel[kotai.model] = nil
	cancelRun(kotai, os.clock())
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

-- 奈落に落ちた個体を消し、データの位置を最後に立っていた位置（無ければ戻る位置）へ戻す。
-- 部隊を失った上忍の戻る位置は今の位置（奈落の上）なので、立っていた位置を先に使う
local function onFell(id: string)
	local kotai = kotaiOf[id]
	local point = if kotai then kotai.groundPoint else nil
	despawn(id)
	local back = point or JoninService.homeOf(id)
	if back then
		JoninService.setPosition(id, back)
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
	-- 雛形の作成（HumanoidDescription の読み込み）は失敗することがある。失敗したら間を空けて作り直す
	local ok, template = pcall(templateOf, jonin.id)
	if not ok then
		warn(`JoninKotaiService: {jonin.id} の個体の見た目を作れなかった: {template}`)
		spawnFailedAt[jonin.id] = now
		return nil
	end
	local model = (template :: Model):Clone()
	model.Name = jonin.id
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	humanoid.MaxHealth = jonin.stats.MaxHealth
	humanoid.Health = jonin.health
	humanoid.WalkSpeed = jonin.stats.WalkSpeed
	humanoid.BreakJointsOnDeath = false
	-- 名札と体力バーは、個体が消える距離まで見せる
	Appearance.attachHealthBar(model, Colors.Gun[jonin.gun], Config.Jittaikaken.DisappearRadius)
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
		target = nil,
		lastAttacker = nil,
		lastAttackedAt = -math.huge,
		-- 出てすぐには型を出さない
		nextKataAt = Kata.nextTime(now, random:NextNumber()),
		run = nil,
		lastHit = nil,
		groundPoint = nil,
		tracks = {},
	}
	kotaiOf[id] = kotai
	idOfModel[model] = id
	syncHealth(kotai, jonin)
	JoninService.setKotai(id, true)
	return kotai
end

-- 個体が追いかける範囲。上忍は戻る位置 home から Kata 節の ChaseRadius の円、首領は本陣の範囲
-- （JoninService.setPosition と同じく範囲の縁へ寄せる。本陣の範囲が分からなければ円）
local function zoneOf(jonin: Jonin.Jonin, home: Kata.Point): Kata.Clamp
	local haichi = if jonin.shuryo then KyotenService.getHaichi() else nil
	if haichi then
		for _, kyoten in haichi.kyoten do
			if kyoten.id == jonin.kyoten then
				local cframe, size = kyoten.cframe, kyoten.size
				return function(point: Kata.Point): Kata.Point
					local offset = cframe:PointToObjectSpace(Vector3.new(point.x, cframe.Position.Y, point.z))
					local x, z = Hoshin.clampToRange(offset.X, offset.Z, size.X, size.Z)
					local world = cframe:PointToWorldSpace(Vector3.new(x, 0, z))
					return { x = world.X, z = world.Z }
				end
			end
		end
	end
	return Kata.circle(home, Config.Kata.ChaseRadius)
end

-- 個体を、位置 position の方へ水平に向ける。threshold を渡すと、向きのずれがその角度（度）より小さければ向き直さない
local function faceToward(kotai: Kotai, position: Vector3, threshold: number?)
	local here = kotai.root.Position
	local flat = Vector3.new(position.X - here.X, 0, position.Z - here.Z)
	if flat.Magnitude < 1e-3 then
		return
	end
	local look = flat.Unit
	if threshold and kotai.root.CFrame.LookVector:Dot(look) >= math.cos(math.rad(threshold)) then
		return
	end
	kotai.root.CFrame = CFrame.lookAt(here, here + look)
end

-- 型のモーションを個体に再生する。武器種の行動のモーションを流用し（Motions.forKata）、型の長さ duration に合わせた速さにする。
-- モーションの無い型（ID が 0）は再生しない
local function playMotion(kotai: Kotai, kataId: string, duration: number): AnimationTrack?
	local motionId = Motions.forKata(kotai.id, kataId)
	if motionId <= 0 then
		return nil
	end
	local track = kotai.tracks[motionId]
	if not track then
		local animator = kotai.humanoid:FindFirstChildOfClass("Animator")
		if not animator then
			local created = Instance.new("Animator")
			created.Parent = kotai.humanoid
			animator = created
		end
		local animation = Instance.new("Animation")
		animation.AnimationId = `rbxassetid://{motionId}`
		local loaded = (animator :: Animator):LoadAnimation(animation)
		kotai.tracks[motionId] = loaded
		track = loaded
	end
	local playing = track :: AnimationTrack
	playing.Priority = Enum.AnimationPriority.Action
	playing.Looped = false
	playing:Play(MOTION_FADE_TIME)
	playing:AdjustSpeed(Motions.playbackSpeed(playing.Length, duration))
	-- まだ読み込めておらず長さが分からなければ、分かった時点で合わせ直す
	if playing.Length <= 0 then
		playing:GetPropertyChangedSignal("Length"):Once(function()
			if playing.IsPlaying then
				playing:AdjustSpeed(Motions.playbackSpeed(playing.Length, duration))
			end
		end)
	end
	return playing
end

-- 予備動作が明けたら、型を振る音を鳴らす（型をやめていたら鳴らさない）
local function swing(kotai: Kotai, run: Run)
	if kotai.run == run then
		SoundPlayer.playAt("Swing", kotai.root)
	end
end

-- 相手 ref に型の判定を当て、結果を覚える（確認用）
local function applyHit(
	kotai: Kotai,
	kataId: string,
	ref: Instance,
	origin: Vector3,
	power: number,
	hit: Config.HitDef,
	aite: Aite
)
	-- 飛び道具の当たりは遅れて届く。決着して戦闘のフェーズが終わっていたら当てない
	if StageService.getPhase() ~= "Battle" then
		return
	end
	local result = aite.hit(ref, origin, power, hit)
	if result then
		kotai.lastHit = {
			kata = kataId,
			target = ref.Name,
			result = result.result,
			amount = result.amount,
			health = result.health,
		}
	end
end

-- 型の判定を1つ出し、形に入った相手に当てる。型をやめていたら出さない。
-- 直線（飛び道具）は、届くまでの秒数だけ遅らせて当てる（投げた後に型をやめても届く）。
-- 届くまでに下忍の個体の体が使い回されたら当てない
local function fireHit(kotai: Kotai, run: Run, hit: Config.HitDef, aite: Aite)
	if kotai.run ~= run or kotai.dying or kotaiOf[kotai.id] ~= kotai or Hanno.busy(kotai.body, os.clock()) then
		return
	end
	local jonin = JoninService.get(kotai.id)
	if not jonin or Jonin.isDefeated(jonin) then
		return
	end
	local shape = HitShape.fromDef(hit.Shape, Config.Hitbox.Height)
	local origin = HitShape.rotate({ position = kotai.root.Position, look = run.look }, hit.Yaw or 0)
	Vfx.shape(shape, origin, KATA_COLOR)
	local position: Vector3 = origin.position
	local power = hit.Power * jonin.stats.Attack
	for _, target in Hitbox.query(shape, origin, aite.list()) do
		if target.delay > 0 then
			-- 届くまでに体が使い回されたら（下忍の個体を部隊へ戻し、同じ体を別の場所に出し直していたら）当てない
			local use = EnemyService.useOf(target.ref)
			task.delay(target.delay, function()
				if EnemyService.useOf(target.ref) == use then
					applyHit(kotai, run.id, target.ref, position, power, hit, aite)
				end
			end)
		else
			applyHit(kotai, run.id, target.ref, position, power, hit, aite)
		end
	end
end

-- 後隙が明けたら型を終え、次の型を選べる時刻を決める
local function finishRun(kotai: Kotai, run: Run)
	if kotai.run ~= run then
		return
	end
	kotai.run = nil
	kotai.nextKataAt = Kata.nextTime(os.clock(), random:NextNumber())
end

-- 型 entry を出す。狙う相手の位置 targetPosition の方を向いて止まり、予備動作の間は足元に判定の範囲を描いて体を光らせる。
-- 判定の時刻ごとに相手 aite へ判定を当て、後隙が明けたら次の型を選べる時刻を決める
local function startRun(
	kotai: Kotai,
	jonin: Jonin.Jonin,
	entry: Kata.Entry,
	targetPosition: Vector3,
	aite: Aite,
	now: number
)
	cancelRun(kotai, now)
	Hanno.stopWalking(kotai.body)
	faceToward(kotai, targetPosition)
	local timeline = Kata.timelineOf(entry.def, jonin.stats.AttackSpeed)
	local duration = ActionState.duration(timeline)
	local yobiDosa = timeline.Startup
	local origin = Hitbox.originOf(kotai.root)
	local look: Vector3 = origin.look
	local run: Run = { id = entry.id, look = look, marks = {}, track = nil }
	kotai.run = run
	-- 見た目やモーションの用意で失敗しても型の最中のまま残らないよう、終わりは先に予約する
	task.delay(duration, finishRun, kotai, run)
	-- 予備動作の見た目。判定ごとに足元へ範囲を描き、体を光らせる
	local color = YOBIDOSA_COLORS[kotai.gun]
	local groundY = kotai.root.Position.Y - kotai.body.standHeight
	for _, hit in entry.def.Hits do
		local shape = HitShape.fromDef(hit.Shape, Config.Hitbox.Height)
		local rotated = HitShape.rotate(origin, hit.Yaw or 0)
		for _, part in Vfx.area(shape, rotated, groundY, color, yobiDosa) do
			table.insert(run.marks, part)
		end
	end
	table.insert(run.marks, Vfx.glow(kotai.model, color, yobiDosa))
	run.track = playMotion(kotai, entry.id, duration)
	task.delay(yobiDosa, swing, kotai, run)
	for _, scheduled in ActionState.hits(timeline) do
		task.delay(scheduled.at, fireHit, kotai, run, scheduled.hit, aite)
	end
end

-- 相手 aite と戦う。狙う相手を選んで間合いまで近づき、型を選べる時刻なら型を出す。狙える相手がいなければ false を返す
local function fight(kotai: Kotai, jonin: Jonin.Jonin, home: Kata.Point, aite: Aite, now: number): boolean
	local position = kotai.root.Position
	local here: Kata.Point = { x = position.X, z = position.Z }
	local zone = zoneOf(jonin, home)
	local candidates: { Kata.Candidate<Instance> } = {}
	local positionOf: { [Instance]: Vector3 } = {}
	for _, target in aite.list() do
		local at: Vector3 = target.position
		positionOf[target.ref] = at
		table.insert(candidates, Kata.candidateOf(target.ref, here, { x = at.X, z = at.Z }, zone))
	end
	local attacker = kotai.lastAttacker
	local remembered: Kata.Attacker<Instance>? = if attacker then { key = attacker, at = kotai.lastAttackedAt } else nil
	local chosen = Kata.chooseTarget(candidates, kotai.target, remembered, now)
	kotai.target = chosen
	local targetPosition = if chosen then positionOf[chosen] else nil
	if not targetPosition then
		return false
	end
	local center: Kata.Point = { x = targetPosition.X, z = targetPosition.Z }
	local goal = Kata.approachPoint(here, center, zone)
	if Kata.distance(here, goal) > STOP_TOLERANCE then
		kotai.humanoid:MoveTo(Vector3.new(goal.x, position.Y, goal.z))
	else
		Hanno.stopWalking(kotai.body)
		faceToward(kotai, targetPosition, TURN_THRESHOLD)
	end
	if now >= kotai.nextKataAt then
		local kataId = Kata.choose(Kata.listOf(jonin.shuryo), Kata.distance(here, center), random:NextNumber())
		local entry = if kataId then Kata.get(kataId) else nil
		if entry then
			startRun(kotai, jonin, entry, targetPosition, aite, now)
		end
	end
	return true
end

-- 出ている個体の位置をデータへ写し、相手と戦う。戦う相手がいなければ、戻る位置から離れていたら歩いて戻る。
-- 体力と毒の見た目もデータに合わせる
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
		-- 飛んでいる・倒れている・起き上がる間は、型をやめて動かない
		cancelRun(kotai, now)
		return
	end
	kotai.groundPoint = { x = position.X, z = position.Z }
	if kotai.run then
		-- 型の最中は動かない
		return
	end
	local home = JoninService.homeOf(kotai.id)
	if not home then
		return
	end
	local aite = if aiEnabled then aiteByGun[kotai.gun] else nil
	if aite and fight(kotai, jonin, home, aite, now) then
		return
	end
	kotai.target = nil
	local dx, dz = home.x - position.X, home.z - position.Z
	if dx * dx + dz * dz > Config.Jittaikaken.HomeRadius ^ 2 then
		kotai.humanoid:MoveTo(Vector3.new(home.x, position.Y, home.z))
	else
		-- 追いかけていた位置へ歩き続けないよう、歩く先も外す
		Hanno.stopWalking(kotai.body)
	end
end

-- 攻撃を受けたら、体力を合わせてから反応を始める。攻撃したプレイヤーを覚え（狙う相手の選択に使う）、
-- 吹き飛びか打ち上げで飛んだら出している型をやめる
local function onDamaged(id: string, _amount: number, hit: JoninService.Hit?, attacker: Player?)
	local kotai = kotaiOf[id]
	local jonin = JoninService.get(id)
	if not kotai or not jonin then
		return
	end
	local now = os.clock()
	if not kotai.dying then
		syncHealth(kotai, jonin)
		if attacker then
			kotai.lastAttacker = attacker
			kotai.lastAttackedAt = now
		end
	end
	-- 止めの一撃（倒れた後に届く）でも飛ばす。倒れた個体は着地して倒れたまま残る（Combat/Hanno）
	if hit then
		Hanno.react(kotai.body, hit, now, isNoFlinch(id))
		if Hanno.busy(kotai.body, now) then
			cancelRun(kotai, now)
		end
	end
end

-- 倒れたら、出している型をやめ、その場に倒し、しばらくして消す
local function onDefeated(id: string)
	local kotai = kotaiOf[id]
	if not kotai or kotai.dying then
		return
	end
	kotai.dying = true
	cancelRun(kotai, os.clock())
	kotai.target = nil
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

-- 戦闘のフェーズが終わったら、倒れていない個体を消す。倒れて消えるのを待つ個体は、止めの一撃の演出を見せるため
-- CorpseLifetime の後に消す（onDefeated の予約）
local function despawnStanding()
	for id, kotai in table.clone(kotaiOf) do
		if not kotai.dying then
			despawn(id)
		end
	end
end

-- 敵軍の上忍か首領が考えるたびに、登録した秘計の判断を呼ぶ。個体として出ていなくても呼ぶ。AI を止めている間は呼ばない
local function decideHikei(jonin: Jonin.Jonin, kotai: Kotai?, now: number)
	local decider = hikeiDecider
	if not decider or not aiEnabled or jonin.gun ~= "Tekigun" then
		return
	end
	local present = kotai ~= nil and not kotai.dying
	local situation: Situation = {
		jonin = jonin,
		kotai = present,
		target = if kotai and present then kotai.target else nil,
		now = now,
	}
	-- 1つの判断の失敗で、ほかの上忍と首領の判断と個体の出し入れが止まらないよう、失敗は警告にする
	local ok, err = pcall(decider, situation)
	if not ok then
		warn(`JoninKotaiService: {jonin.id} の秘計の判断が失敗した: {err}`)
	end
end

-- 上忍か首領の個体を出し入れし、出ていれば進め、敵軍なら秘計の判断を呼ぶ。points は出撃メンバーの水平の位置
local function step(jonin: Jonin.Jonin, points: { Jittaikaken.Point }, now: number)
	local kotai: Kotai? = kotaiOf[jonin.id]
	if Jonin.isDefeated(jonin) then
		if kotai and not kotai.dying then
			onDefeated(jonin.id)
		end
		return
	end
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
	decideHikei(jonin, kotai, now)
end

-- 戦闘のフェーズの間、上忍と首領の個体を出し入れし、出ている個体を進め、敵軍の秘計の判断を呼ぶ
local function tick()
	if StageService.getPhase() ~= "Battle" then
		despawnStanding()
		return
	end
	local now = os.clock()
	local points = memberPoints()
	local alive: { [string]: boolean } = {}
	for _, jonin in JoninService.list() do
		if not Jonin.isDefeated(jonin) then
			alive[jonin.id] = true
		end
		-- 1人の失敗で、ほかの上忍と首領の出し入れが止まらないよう、失敗は警告にして次へ進む
		local ok, err = pcall(step, jonin, points, now)
		if not ok then
			warn(`JoninKotaiService: {jonin.id} の個体を進められなかった: {err}`)
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

-- 型 ID を ID の順に並べる（首領だけの型も含む）
local function kataIds(): { string }
	local ids = {}
	for _, entry in Kata.listOf(true) do
		table.insert(ids, entry.id)
	end
	return ids
end

local function registerDebugCommands()
	DebugCommand.register(
		"DumpJoninKotai",
		"",
		"出ている上忍と首領の個体（軍・体力・反応の状態・倒れて消えるのを待つか・位置・一番近いメンバーまでの距離・"
			.. "狙っている相手・出している型・最後に当てた型の結果）を JSON で返す",
		function()
			local points = memberPoints()
			local list = {}
			for id, kotai in kotaiOf do
				local position = kotai.root.Position
				local distance = Jittaikaken.nearestDistance({ x = position.X, z = position.Z }, points)
				local lastHit = kotai.lastHit
				table.insert(list, {
					id = id,
					gun = kotai.gun,
					health = round(kotai.humanoid.Health),
					maxHealth = round(kotai.humanoid.MaxHealth),
					hanno = Hanno.kindOf(kotai.body),
					dying = if kotai.dying then true else nil,
					position = { round(position.X), round(position.Y), round(position.Z) },
					distance = if distance then round(distance) else nil,
					target = if kotai.target then kotai.target.Name else nil,
					kata = if kotai.run then kotai.run.id else nil,
					lastHit = if lastHit
						then {
							kata = lastHit.kata,
							target = lastHit.target,
							result = lastHit.result,
							amount = round(lastHit.amount),
							health = if lastHit.health then round(lastHit.health) else nil,
						}
						else nil,
				})
			end
			table.sort(list, function(a, b)
				return a.id < b.id
			end)
			return HttpService:JSONEncode(list)
		end
	)
	DebugCommand.register(
		"SetJoninAI",
		"<true|false>",
		"上忍と首領の個体が狙う相手に近づいて型を出すかと、敵軍の上忍と首領の秘計の判断を呼ぶかを切り替える。"
			.. "止めると出している型をやめ、個体は戻る位置へ戻る。止めても攻撃の反応と毒は進み、UseKata の型は出る（確認用）",
		function(value)
			aiEnabled = value == true or value == "true"
			if not aiEnabled then
				local now = os.clock()
				for _, kotai in kotaiOf do
					cancelRun(kotai, now)
					kotai.target = nil
				end
			end
			return `上忍と首領の AI を{if aiEnabled then "再開した" else "止めた"}`
		end
	)
	DebugCommand.register(
		"UseKata",
		"<キャラクター ID> <型 ID> [相手の名前]",
		"上忍か首領の個体に型を1回出させる。相手の名前（敵軍はプレイヤー名、味方軍は敵軍の下忍の名前）を渡すと"
			.. "その相手へ、省くと一番近い相手へ向けて出す。首領だけの型は首領だけが出せる。SetJoninAI false でも出す（確認用）",
		function(id, kataId, aiteName)
			local jonin = if type(id) == "string" then JoninService.get(id) else nil
			if not jonin then
				return `{tostring(id)} は出撃したステージの上忍と首領にいない`
			end
			local entry = if type(kataId) == "string" then Kata.get(kataId) else nil
			if not entry then
				error(`型 ID は {table.concat(kataIds(), "、")} のどれか（{tostring(kataId)}）`, 0)
			end
			if entry.shuryo and not jonin.shuryo then
				return `{entry.id} は首領だけの型なので、{jonin.displayName} は出せない`
			end
			local aite = aiteByGun[jonin.gun]
			if not aite then
				return `{jonin.displayName} の軍の個体には戦う相手がいない`
			end
			local kotai = kotaiOf[jonin.id]
			if not kotai or kotai.dying then
				return `{jonin.displayName} の個体が出ていない`
			end
			local now = os.clock()
			if Hanno.busy(kotai.body, now) then
				return `{jonin.displayName} は攻撃を受けた反応の最中（{Hanno.kindOf(kotai.body)}）`
			end
			local running = kotai.run
			if running then
				return `{jonin.displayName} は型 {running.id} を出している最中`
			end
			local name = if aiteName ~= nil then tostring(aiteName) else nil
			local here = kotai.root.Position
			local chosen: HitShape.Target<Instance>? = nil
			local best = math.huge
			for _, target in aite.list() do
				local at: Vector3 = target.position
				local distance = Vector3.new(at.X - here.X, 0, at.Z - here.Z).Magnitude
				if (name == nil or target.ref.Name == name) and distance < best then
					chosen, best = target, distance
				end
			end
			if not chosen then
				return if name
					then `{name} は {jonin.displayName} の戦う相手にいないか、倒れている`
					else `{jonin.displayName} の戦う相手がいない`
			end
			kotai.target = chosen.ref
			startRun(kotai, jonin, entry, chosen.position, aite, now)
			local yobiDosa = round(Kata.timelineOf(entry.def, jonin.stats.AttackSpeed).Startup)
			local away = round(best)
			return `{jonin.displayName} が {chosen.ref.Name} へ型 {entry.id} を出した（予備動作 {yobiDosa} 秒、{away} スタッド先）`
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
	-- 出撃したら、上忍と首領の個体の雛形を先に作っておく（初めて出すときに出し入れを待たせない）
	StageService.started:Connect(function()
		task.spawn(function()
			for _, jonin in JoninService.list() do
				local ok, err = pcall(templateOf, jonin.id)
				if not ok then
					warn(`JoninKotaiService: {jonin.id} の個体の見た目を作れなかった: {err}`)
				end
			end
		end)
	end)
	StageService.phaseChanged:Connect(function(next: StagePhase.Phase)
		if next ~= "Battle" then
			despawnStanding()
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
