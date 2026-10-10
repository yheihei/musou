--!strict
-- 秘計の伏兵。発動者の足元に味方の部隊（伏兵部隊）を潜ませ、近づいた相手の部隊かプレイヤーを奇襲して士気を下げる。
-- 伏兵部隊は部隊のデータ（ButaiService）で持ち、潜んでいる間は印（Butai.fukuhei）を付ける。
-- 奇襲の判定は ReplicatedStorage.Shared.Fukuhei、兵数と距離は Config.luau の Fukuhei 節、潜んでいられる時間は
-- Hikei 節の Duration.Fukuhei にある。発動の入口・使用記録・効果の時間管理は HikeiService にある。
--
-- - 設計の表の「指定地点」は、発動者の足元とする
-- - 潜んでいる間は、交戦の相手を決める対象（ButaiService）にも、方針の迎え撃つ相手（HoshinService）にも、
--   拠点の守備と攻める軍（KyotenService）にもならない
-- - 部隊を進める間隔（Config.luau の Butai 節の MoveInterval）ごとに、潜んでいる伏兵部隊の KishuRadius 以内に
--   相手の部隊か、相手がプレイヤーの軍ならプレイヤーが来たかを確かめ、来たら奇襲する
-- - 奇襲すると姿を現し（ButaiService.reveal）、相手の部隊の士気を KishuShiki だけずっと下げてから、すぐ交戦を始める
--   （ButaiService.startKosen）。相手がほかの部隊と交戦中なら、近ければ相手が空いたときに交戦を始める
-- - 奇襲した伏兵部隊は効果を終え、普通の部隊として残る。方針は持たないので、その場にとどまる。奇襲したことは kishu で知らせる
-- - 奇襲せずに潜んでいられる時間が過ぎるか、ステージが終わったら、伏兵部隊は消える（兵数の減少には数えない）
-- - 潜んでいる間は、味方軍の伏兵部隊なら足元に仮の見た目（草むらと「伏兵」の札）を置く。高さは地面に合わせる。
--   敵軍の伏兵部隊はプレイヤーに見つからないよう見た目を出さない。奇襲したら見た目を片付ける

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Butai = require(ReplicatedStorage.Shared.Butai)
local Config = require(ReplicatedStorage.Shared.Config)
local Fukuhei = require(ReplicatedStorage.Shared.Fukuhei)
local Ground = require(ReplicatedStorage.Shared.Ground)
local Hikei = require(ReplicatedStorage.Shared.Hikei)
local StagePhase = require(ReplicatedStorage.Shared.StagePhase)
local ButaiService = require(script.Parent.ButaiService)
local HikeiService = require(script.Parent.HikeiService)
local StageService = require(script.Parent.StageService)

local FukuheiService = {}

local HIKEI_ID = "Fukuhei"

local kishuEvent = Instance.new("BindableEvent")
-- 伏兵部隊が奇襲したときに、伏兵を使った人の ID（プレイヤーは UserId の文字列、上忍と首領はその ID）・その軍・
-- 伏兵部隊の ID・奇襲した相手の部隊の ID（プレイヤーを奇襲したなら nil）で発火する（戦況の台詞が受ける）
FukuheiService.kishu = kishuEvent.Event

-- 草むらの玉の直径と色、札の高さ（スタッド）
local BUSH_DIAMETER = 3.5
local BUSH_COLOR = Color3.fromRGB(70, 120, 55)
local LABEL_HEIGHT = 6
-- 草むらの玉の置き方（足元からのずれ。x は東、z は南）
local BUSH_OFFSETS = {
	Vector3.new(0, 0, 0),
	Vector3.new(2.5, 0, 1),
	Vector3.new(-2.2, 0, 1.5),
	Vector3.new(0.8, 0, -2.4),
	Vector3.new(-1.6, 0, -1.8),
}

-- 潜んでいる伏兵部隊
type Entry = {
	effect: Hikei.Effect,
	butai: string,
}

-- 伏兵部隊の ID から引く、潜んでいる伏兵部隊
local hidden: { [string]: Entry } = {}
-- 伏兵部隊に振る番号
local nextNumber = 1

local function removeVisual(butaiId: string)
	local folder = HikeiService.folderOf(HIKEI_ID)
	local model = folder:FindFirstChild(butaiId)
	if model then
		model:Destroy()
	end
end

-- 足元に草むらと札を置く
local function buildVisual(butaiId: string, position: Vector3, heisu: number)
	local folder = HikeiService.folderOf(HIKEI_ID)
	removeVisual(butaiId)
	local model = Instance.new("Model")
	model.Name = butaiId
	local top: Part? = nil
	for index, offset in BUSH_OFFSETS do
		local x, z = position.X + offset.X, position.Z + offset.Z
		local y = Ground.heightAt(x, z) or position.Y
		local part = Instance.new("Part")
		part.Name = `Kusa{index}`
		part.Shape = Enum.PartType.Ball
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.Material = Enum.Material.Grass
		part.Color = BUSH_COLOR
		part.Size = Vector3.one * BUSH_DIAMETER
		part.Position = Vector3.new(x, y + BUSH_DIAMETER * 0.35, z)
		part.Parent = model
		if index == 1 then
			top = part
		end
	end
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Label"
	billboard.Size = UDim2.fromOffset(120, 32)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, LABEL_HEIGHT, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 250
	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBold
	text.TextScaled = true
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextStrokeTransparency = 0.3
	text.Text = `伏兵 {heisu}`
	text.Parent = billboard
	billboard.Adornee = top
	billboard.Parent = model
	model.Parent = folder
end

local function newButaiId(): string
	while ButaiService.get(`Fukuhei{nextNumber}`) do
		nextNumber += 1
	end
	local id = `Fukuhei{nextNumber}`
	nextNumber += 1
	return id
end

local function activate(context: HikeiService.Context): (boolean, Hikei.UseFailure?)
	local butai = ButaiService.add({
		id = newButaiId(),
		gun = context.gun,
		heisu = Config.Fukuhei.Heisu,
		position = { x = context.position.X, z = context.position.Z },
		jonin = nil,
		kyoten = nil,
		fukuhei = true,
	})
	if not butai then
		return false, "NoTarget"
	end
	local effect = HikeiService.addEffect({
		hikei = HIKEI_ID,
		user = context.user,
		gun = context.gun,
		target = butai.id,
		targetGun = context.gun,
		now = context.now,
		duration = nil,
	})
	if not effect then
		ButaiService.remove(butai.id)
		return false, "NoTarget"
	end
	hidden[butai.id] = { effect = effect, butai = butai.id }
	-- 敵軍の伏兵部隊はプレイヤーに見つからないよう、見た目を出さない
	if context.gun == Fukuhei.PLAYER_GUN then
		buildVisual(butai.id, context.position, butai.heisu)
	end
	return true, nil
end

-- 効果が終わったら見た目を片付け、潜んだままなら伏兵部隊を消す（奇襲した伏兵部隊は残す）
local function finish(effect: Hikei.Effect, _reason: HikeiService.FinishReason)
	local butaiId = effect.target
	removeVisual(butaiId)
	local entry = hidden[butaiId]
	if not entry or entry.effect ~= effect then
		return
	end
	hidden[butaiId] = nil
	ButaiService.remove(butaiId)
end

-- 奇襲する。姿を現し、相手の部隊がいれば士気を下げてから交戦を始め、効果を終える
local function kishu(entry: Entry, target: string?)
	hidden[entry.butai] = nil
	ButaiService.reveal(entry.butai)
	removeVisual(entry.butai)
	if target then
		ButaiService.lowerShiki(target, Config.Fukuhei.KishuShiki)
		ButaiService.startKosen(entry.butai, target)
	end
	HikeiService.finishEffect(entry.effect, "Ended")
	kishuEvent:Fire(entry.effect.user, entry.effect.gun, entry.butai, target)
end

-- 生きている出撃メンバーの位置
local function playerPositions(): { Fukuhei.Point }
	local result = {}
	for _, member in StageService.getMembers() do
		local character = member.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if humanoid and root and humanoid.Health > 0 then
			table.insert(result, { x = root.Position.X, z = root.Position.Z })
		end
	end
	return result
end

local function unitOf(butai: Butai.Butai): Fukuhei.Unit
	return { id = butai.id, gun = butai.gun, position = butai.position, heisu = butai.heisu, fukuhei = butai.fukuhei }
end

-- 潜んでいる伏兵部隊ごとに、近づいた相手がいれば奇襲する
local function watch()
	if StageService.getPhase() ~= "Battle" or next(hidden) == nil then
		return
	end
	local units: { Fukuhei.Unit } = {}
	for _, butai in ButaiService.list() do
		table.insert(units, unitOf(butai))
	end
	local players = playerPositions()
	for id, entry in table.clone(hidden) do
		local butai = ButaiService.get(id)
		if not butai then
			-- 窓口などで外された
			hidden[id] = nil
			HikeiService.finishEffect(entry.effect, "Ended")
			continue
		end
		local found, target = Fukuhei.kishuOf(unitOf(butai), units, players)
		if found then
			kishu(entry, target)
		end
	end
end

-- 潜んでいる伏兵部隊の ID（窓口で見る）
function FukuheiService.hiddenList(): { string }
	local ids = {}
	for id in hidden do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

function FukuheiService.start()
	HikeiService.register(HIKEI_ID, { activate = activate, finish = finish })
	StageService.phaseChanged:Connect(function(nextPhase: StagePhase.Phase)
		-- 次の出撃の伏兵部隊は 1 から数え直す（部隊は ButaiService が片付ける）
		if nextPhase == "Lobby" then
			table.clear(hidden)
			nextNumber = 1
		end
	end)

	task.spawn(function()
		while true do
			task.wait(Config.Butai.MoveInterval)
			-- 1回の失敗で奇襲の確かめが止まらないよう、失敗は警告にして次の間隔で続ける
			local ok, err = pcall(watch)
			if not ok then
				warn(`FukuheiService: 伏兵部隊の奇襲を確かめられなかった: {err}`)
			end
		end
	end)
end

return FukuheiService
