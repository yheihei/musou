--!strict
-- プレイヤーの攻撃の中身。通常攻撃・チャージ攻撃・ジャンプ攻撃・奥義のタイムラインと判定を ActionService に登録する。
-- 入力の受け取りと行動の状態遷移は ActionService が持ち、コンボの段数と当たり判定はここで決める。
--
-- - 通常攻撃の段とチャージ攻撃 C1〜C6 は武器種ごとに Config.luau の Bukishu 節にあり、キャラクターの武器種から引く
-- - Attribute の ActionStep には、通常攻撃は段、チャージ攻撃は C の番号を書く
-- - 時間はキャラクターの攻撃の速さで伸び縮みさせる（ActionState.scale）
-- - 判定はタイムラインの Hits の時刻に出し、それまでに行動が変わっていたら出さない
-- - 前進量は、発生から持続の終わりまでにサーバーの拘束で前へ動かす
-- - 攻撃を当てる相手は、仮の湧き処理の敵（EnemyService）と、敵軍の上忍・首領の個体（JoninKotaiService）。
--   味方軍の上忍・首領の個体とほかのプレイヤーには当てない
-- - 与ダメージは Stats.damage（技の倍率 × 攻撃）。仮の湧き処理の敵はまだ防御を持たない。
--   上忍と首領は被ダメージの受け口（JoninService.damage）が防御で軽減し、倒したら撃破数に数える
-- - 奥義はキャラクター定義の ougi から、registerOugi で登録した中身と Config.luau の Ougi 節の技を引く。
--   ストックを1本使い、発動中は無敵（Damage.luau が行動から判定する）。奥義の命中では奥義ゲージは溜まらない
-- - 奥義は刃の火遁、酉花の毒手裏剣、石舟斎の無刀取り、金鬼の金遁。毒手裏剣は、当てた敵を毒にする
--   （仮の湧き処理の敵は EnemyService.poison、上忍と首領は JoninService.poison）
-- - 効果音は、技を出したときに技の音（通常攻撃とジャンプ攻撃は Swing、チャージ攻撃は ChargeKogeki、
--   奥義は Ougi）を、当てたときに Hit を鳴らす。命中の音は1人の攻撃につき Config.Sound.HitInterval 秒に1回まで

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ActionState = require(ReplicatedStorage.Shared.ActionState)
local Actions = require(ReplicatedStorage.Shared.Actions)
local Characters = require(ReplicatedStorage.Shared.Characters)
local Combo = require(ReplicatedStorage.Shared.Combo)
local Config = require(ReplicatedStorage.Shared.Config)
local Gun = require(ReplicatedStorage.Shared.Gun)
local HitShape = require(ReplicatedStorage.Shared.HitShape)
local SoundPlayer = require(ReplicatedStorage.Shared.SoundPlayer)
local Sounds = require(ReplicatedStorage.Shared.Sounds)
local Stats = require(ReplicatedStorage.Shared.Stats)
local DebugCommand = require(script.Parent.Parent.DebugCommand)
local ActionService = require(script.Parent.ActionService)
local EnemyService = require(script.Parent.EnemyService)
local JoninKotaiService = require(script.Parent.JoninKotaiService)
local JoninService = require(script.Parent.JoninService)
local PlayerService = require(script.Parent.PlayerService)
local Hitbox = require(script.Parent.Parent.Combat.Hitbox)
local Push = require(script.Parent.Parent.Combat.Push)
local Vfx = require(script.Parent.Parent.Combat.Vfx)

-- 判定の形の仮エフェクトの描き方
export type Draw = (shape: HitShape.Shape, origin: HitShape.Origin) -> ()

-- 当てた敵に付ける追加の中身（毒など）
export type OnHit = (player: Player, model: Model) -> ()

-- 奥義の中身。仮エフェクトの描き方と、判定のほかに出す中身（追撃など）と、当てた敵に付ける中身（毒など）
export type OugiEntry = {
	draw: Draw,
	perform: ((player: Player, t: number, timeline: ActionState.Timeline) -> ())?,
	onHit: OnHit?,
}

-- 技の見せ方。仮エフェクトの描き方、当てたときに奥義ゲージを溜めるか、出したときに鳴らす効果音、当てた敵に付ける中身
type Style = {
	draw: Draw,
	gauge: boolean,
	sound: string?,
	onHit: OnHit?,
}

local CombatService = {}

-- プレイヤー（味方軍）の攻撃を当てる、上忍と首領の個体の軍
local AITE_GUN: Gun.Gun = "Tekigun"

local combos: { [Player]: Combo.State } = {}
-- 命中の音を最後に鳴らした時刻
local lastHitSound: { [Player]: number } = {}
-- 今の空中でジャンプ攻撃を出したか。着地で消す
local jumpAttacked: { [Player]: boolean } = {}
-- 奥義の ID（キャラクター定義の ougi）から引く中身
local ougiEntries: { [string]: OugiEntry } = {}

local function colored(color: Color3): Draw
	return function(shape, origin)
		Vfx.shape(shape, origin, color)
	end
end

-- 毒手裏剣と無刀取りの仮エフェクトの色
local POISON_COLOR = Color3.fromRGB(150, 230, 90)
local MUTODORI_COLOR = Color3.fromRGB(220, 235, 255)

local SLASH: Style = { draw = colored(Color3.fromRGB(255, 230, 150)), gauge = true, sound = "Swing" }
local CHARGE_KOGEKI: Style = { draw = colored(Color3.fromRGB(120, 200, 255)), gauge = true, sound = "ChargeKogeki" }

local function getRoot(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function comboOf(player: Player): Combo.State
	return combos[player] or Combo.new()
end

-- 使うキャラクターの武器種の技
local function bukishuOf(player: Player): Config.BukishuDef
	local character = Characters.get(PlayerService.getCharacterId(player))
	local bukishu = character and character.bukishu or "Shuriken"
	return Config.Bukishu[bukishu]
end

-- 攻撃の速さの倍率で伸び縮みさせたタイムライン
local function scaled(player: Player, timeline: ActionState.Timeline): ActionState.Timeline
	return ActionState.scale(timeline, PlayerService.getStats(player).AttackSpeed)
end

-- 命中の音を鳴らす。まとめて当てたときに重ならないよう、1人の攻撃につき間隔を空ける
local function playHitSound(player: Player, model: Model)
	local now = os.clock()
	if now - (lastHitSound[player] or -math.huge) < Config.Sound.HitInterval then
		return
	end
	lastHitSound[player] = now
	SoundPlayer.playAt("Hit", model:GetPivot().Position)
end

-- 攻撃を1体に当てる。attack は攻撃したプレイヤーの攻撃の能力値
local function hitOne(player: Player, origin: Vector3, model: Model, attack: number, hit: Config.HitDef, style: Style)
	-- 吹き飛びと打ち上げの軌道は、仮の湧き処理の敵と上忍・首領の個体が、技の吹き飛ばす強さから決める（Combat/Hanno）
	local reaction = { reaction = hit.Reaction, origin = origin, force = hit.Knockback }
	local joninId = JoninKotaiService.idOf(model)
	local landed
	if joninId then
		-- 上忍と首領は、威力（技の倍率 × 攻撃）を被ダメージの受け口が防御で軽減する
		local amount = JoninService.damage(joninId, hit.Power * attack, player, reaction)
		landed = amount > 0
	else
		landed = EnemyService.damage(model, Stats.damage(hit.Power, attack, 0), player, reaction)
	end
	if landed then
		Vfx.hit(model)
		playHitSound(player, model)
		if style.gauge then
			PlayerService.addOugiGauge(player, Config.Ougi.GainPerHit)
		end
		local onHit = style.onHit
		if onHit then
			onHit(player, model)
		end
	end
end

-- 技の判定を1つ出し、形に入った敵に当てる。飛び道具のように時間差のある当たりは、その秒数だけ遅らせる。
-- once を渡すと、そこに入っている敵には当てず、当てた敵を入れる（同じ時刻の判定を1体に1回だけ当てる技）
local function doHit(player: Player, root: BasePart, hit: Config.HitDef, style: Style, once: { [Model]: boolean }?)
	local shape = HitShape.fromDef(hit.Shape, Config.Hitbox.Height)
	local origin = HitShape.rotate(Hitbox.originOf(root), hit.Yaw or 0)
	style.draw(shape, origin)
	local attack = PlayerService.getStats(player).Attack
	local position: Vector3 = origin.position
	local targets = EnemyService.getTargets()
	for _, target in JoninKotaiService.getTargets(AITE_GUN) do
		table.insert(targets, target)
	end
	for _, target in Hitbox.query(shape, origin, targets) do
		if once then
			if once[target.ref] then
				continue
			end
			once[target.ref] = true
		end
		if target.delay > 0 then
			task.delay(target.delay, hitOne, player, position, target.ref, attack, hit, style)
		else
			hitOne(player, position, target.ref, attack, hit, style)
		end
	end
end

-- 時刻 t に始めた行動の前進と判定を出し、技の効果音を鳴らす。判定の時刻までに別の行動に変わっていたら出さない
local function perform(player: Player, t: number, timeline: ActionState.Timeline, style: Style)
	local root = getRoot(player)
	if root and style.sound then
		SoundPlayer.playAt(style.sound, root)
	end
	if root and timeline.Advance > 0 then
		Push.move(root, root.CFrame.LookVector, timeline.Advance, timeline.Startup + timeline.Active)
	end
	-- 同じ時刻の判定を1体に1回だけ当てる技（HitOnce）は、時刻ごとに当てた敵を覚える
	local hitOnce: { [number]: { [Model]: boolean } }? = if timeline.HitOnce then {} else nil
	for _, scheduled in ActionState.hits(timeline) do
		local once: { [Model]: boolean }? = nil
		if hitOnce then
			once = hitOnce[scheduled.at] or {}
			hitOnce[scheduled.at] = once
		end
		local function fire()
			local _, startedAt = ActionService.current(player)
			local current = getRoot(player)
			if startedAt == t and current then
				doHit(player, current, scheduled.hit, style, once)
			end
		end
		if scheduled.at <= 0 then
			fire()
		else
			task.delay(scheduled.at, fire)
		end
	end
end

-- 奥義の中身を登録する。id はキャラクター定義の ougi（忍術の英名）で、技は Config.luau の Ougi 節の Timelines に置く
function CombatService.registerOugi(id: string, entry: OugiEntry)
	assert(ougiEntries[id] == nil, `CombatService: 奥義 {id} は登録済み`)
	ougiEntries[id] = entry
end

-- 使うキャラクターの奥義の ID とタイムライン。中身か技の無い奥義は nil
local function ougiOf(player: Player): (string?, ActionState.Timeline?)
	local character = Characters.get(PlayerService.getCharacterId(player))
	local id = character and character.ougi
	if not id or not ougiEntries[id] then
		return nil, nil
	end
	return id, Config.Ougi.Timelines[id]
end

local function registerActions()
	-- 通常攻撃。武器種の段を1段目から順に出す
	ActionService.register(Actions.Attack, {
		timeline = function(player, t)
			local steps = bukishuOf(player).Attack
			return scaled(player, steps[Combo.count(comboOf(player), t, #steps) + 1])
		end,
		begin = function(player, t, timeline)
			local steps = bukishuOf(player).Attack
			local step = Combo.count(comboOf(player), t, #steps) + 1
			combos[player] = Combo.advance(step, t, timeline.CancelFrom)
			perform(player, t, timeline, SLASH)
			return step
		end,
	})

	-- チャージ攻撃。それまでに出した通常攻撃の段数で C1〜C6 に分かれ、出した後はコンボが途切れる
	ActionService.register(Actions.ChargeKogeki, {
		timeline = function(player, t)
			local set = bukishuOf(player)
			return scaled(player, set.ChargeKogeki[Combo.chargeIndex(comboOf(player), t, #set.Attack)])
		end,
		begin = function(player, t, timeline)
			local set = bukishuOf(player)
			local index = Combo.chargeIndex(comboOf(player), t, #set.Attack)
			combos[player] = Combo.new()
			perform(player, t, timeline, CHARGE_KOGEKI)
			return index
		end,
	})

	-- ジャンプ攻撃。空中の通常攻撃で、着地まで1回だけ出せる。発生までの間に真下へ落とす
	ActionService.register(ActionService.JumpAttack, {
		timeline = function(player)
			if jumpAttacked[player] or not ActionService.isAirborne(player) then
				return nil
			end
			return scaled(player, bukishuOf(player).JumpAttack)
		end,
		begin = function(player, t, timeline)
			jumpAttacked[player] = true
			combos[player] = Combo.new()
			local root = getRoot(player)
			if root then
				Push.fall(root, Config.Jump.DiveSpeed, timeline.Startup)
			end
			perform(player, t, timeline, SLASH)
			return nil
		end,
	})

	-- 奥義。ストックが1本以上あり、被弾の反応の最中でなく、中身を登録した奥義のときだけ出せる
	ActionService.register(Actions.Ougi, {
		timeline = function(player)
			if PlayerService.getOugi(player).stock < 1 then
				return nil
			end
			if ActionService.isReaction((ActionService.current(player))) then
				return nil
			end
			local _, timeline = ougiOf(player)
			return timeline
		end,
		begin = function(player, t, timeline)
			combos[player] = Combo.new()
			-- 奥義ゲージは入力を受け付けた時点で1本使う
			PlayerService.consumeOugiStock(player)
			local id = ougiOf(player)
			local entry = if id then ougiEntries[id] else nil
			if entry then
				perform(player, t, timeline, { draw = entry.draw, gauge = false, sound = "Ougi", onHit = entry.onHit })
				if entry.perform then
					entry.perform(player, t, timeline)
				end
			end
			return nil
		end,
	})
end

function CombatService.start()
	registerActions()
	-- 刃の火遁。前方の扇に炎を吐く
	CombatService.registerOugi("Katon", { draw = Vfx.flame })
	-- 酉花の毒手裏剣。周りへ毒手裏剣を撒き、当たった敵を毒にする
	CombatService.registerOugi("PoisonShuriken", {
		draw = colored(POISON_COLOR),
		onHit = function(player: Player, model: Model)
			local joninId = JoninKotaiService.idOf(model)
			if joninId then
				JoninService.poison(joninId, player)
			else
				EnemyService.poison(model, player)
			end
		end,
	})
	-- 石舟斎の無刀取り。周りを打ち上げ、空中の敵をまとめて斬る
	CombatService.registerOugi("MutoDori", { draw = colored(MUTODORI_COLOR) })
	-- 金鬼の金遁。地面から金属の刃を突き出す輪を外へ広げる
	CombatService.registerOugi("Kinton", { draw = Vfx.blades })

	DebugCommand.register(
		"PlaySound",
		"<効果音の名前> <プレイヤー名>",
		"効果音をプレイヤーの位置で鳴らす（登録表は ReplicatedStorage.Shared.Sounds）",
		function(name, playerName)
			local player = DebugCommand.findPlayer(playerName)
			if type(name) ~= "string" or not Sounds.get(name) then
				error(`効果音は {table.concat(Sounds.names(), "、")} のどれか（{tostring(name)}）`, 0)
			end
			local root = getRoot(player)
			if not root then
				return `{player.Name} のキャラクターがいない`
			end
			SoundPlayer.playAt(name, root)
			return `{player.Name} の位置で {name} を鳴らした`
		end
	)
	DebugCommand.register(
		"LogSound",
		"<true|false>",
		"鳴らした効果音（名前・鳴らした側・時刻・場所）を、サーバーとクライアントのコンソールに [Sound] の行で出すかを切り替える（確認用）",
		function(value)
			local on = value == true or value == "true"
			SoundPlayer.setLogging(on)
			return `鳴らした効果音の表示を{if on then "オン" else "オフ"}にした`
		end
	)
	DebugCommand.register(
		"ShowHitbox",
		"<true|false> [残す秒数]",
		"攻撃判定の形のデバッグ表示を切り替える",
		function(value, lifetime)
			local on = value == true or value == "true"
			local seconds = if lifetime ~= nil then DebugCommand.toNumber(lifetime, "残す秒数") else nil
			Hitbox.setShowShapes(on, seconds)
			return `攻撃判定の形の表示を{if on then "オン" else "オフ"}にした`
		end
	)

	-- 被弾の反応で行動が途切れたら、前進を止め、通常攻撃の段を1段目に戻す
	ActionService.started:Connect(function(player: Player, action: string)
		if ActionService.isReaction(action) then
			combos[player] = Combo.new()
			local root = getRoot(player)
			if root then
				Push.stop(root)
			end
		end
	end)

	-- 出現し直したら1段目から始める。着地したらジャンプ攻撃をまた出せる
	local function watch(player: Player, character: Model)
		combos[player] = Combo.new()
		jumpAttacked[player] = nil
		local humanoid = character:WaitForChild("Humanoid") :: Humanoid
		humanoid.StateChanged:Connect(function(_, state)
			if state ~= Enum.HumanoidStateType.Jumping and state ~= Enum.HumanoidStateType.Freefall then
				jumpAttacked[player] = nil
			end
		end)
	end
	local function track(player: Player)
		player.CharacterAdded:Connect(function(character)
			watch(player, character)
		end)
		if player.Character then
			task.spawn(watch, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(track)
	for _, player in Players:GetPlayers() do
		track(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		combos[player] = nil
		jumpAttacked[player] = nil
		lastHitSound[player] = nil
	end)
end

return CombatService
