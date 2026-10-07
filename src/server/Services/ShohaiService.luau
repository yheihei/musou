--!strict
-- 勝敗を判定してステージを終える。勝ちと負けの条件を各サービスのシグナルで受け、
-- 同じ再開の中で起きた条件をまとめて ReplicatedStorage.Shared.Shohai で判定し、StageService.finish を1回だけ呼ぶ。
--
-- - 首領の撃破は JoninService.defeated で受ける。倒れたのが敵軍の首領なら勝ち、味方軍の首領なら負け。上忍は関わらない
-- - 本陣の制圧は KyotenService.seiatsu で受ける。制圧されたのが敵軍の本陣なら勝ち、味方軍の本陣なら負け（陥落）
-- - 兵力0の状態でプレイヤーが倒れたことは SaishutsugekiService.heiryokuZero で受け、負けにする
-- - 時間切れは StageService が制限時間の処理で決める（ここを通さない）
-- - 条件は戦闘のフェーズの間だけ受け付ける。受けたら溜めて、task.defer で今の再開の終わりにまとめて判定する。
--   同じ再開の中で起きた条件（同じ間隔の中で両軍の本陣が落ちたときなど）は同時とみなし、負けを優先する。
--   先に時間切れなどで決着していれば、finish は受け付けられず、先の勝敗が残る
-- - 決着した後の片付け（部隊・上忍と首領・個体・仮の湧き処理の敵）は、各サービスが StageService.finished・phaseChanged で行う

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Gun = require(ReplicatedStorage.Shared.Gun)
local RemoteSchema = require(ReplicatedStorage.Shared.RemoteSchema)
local Shohai = require(ReplicatedStorage.Shared.Shohai)
local JoninService = require(script.Parent.JoninService)
local KyotenService = require(script.Parent.KyotenService)
local SaishutsugekiService = require(script.Parent.SaishutsugekiService)
local StageService = require(script.Parent.StageService)

local ShohaiService = {}

-- 今の再開の中で受けて、まだ判定していない条件（受けた順）
local pending: { RemoteSchema.ResultReason } = {}
-- 今の再開の終わりの判定を予約したか
local scheduled = false

-- 溜めた条件をまとめて判定し、勝敗が決まったらステージを終える
local function judge()
	scheduled = false
	local conditions = pending
	pending = {}
	local shohai = Shohai.judge(conditions)
	if shohai and StageService.finish(shohai.victory, shohai.reason) then
		local headline = if shohai.victory then "勝利" else "敗北"
		print(
			`[Shohai] {headline}（{shohai.reason}）で決着した（受けた条件 {table.concat(conditions, "、")}）`
		)
	end
end

-- 条件を溜め、今の再開の終わりの判定を予約する。戦闘のフェーズの外では受け付けない
local function report(condition: RemoteSchema.ResultReason)
	if StageService.getPhase() ~= "Battle" then
		return
	end
	table.insert(pending, condition)
	if not scheduled then
		scheduled = true
		task.defer(judge)
	end
end

-- 首領が倒れたら、倒れた首領の軍で勝ちか負けの条件にする
local function onJoninDefeated(id: string)
	local jonin = JoninService.get(id)
	if jonin and jonin.shuryo then
		report(Shohai.shuryoGekihaOf(jonin.gun))
	end
end

-- 本陣が制圧されたら、制圧された本陣の元の軍で勝ちか負けの条件にする
local function onSeiatsu(id: string, _gun: Gun.Gun, previous: Gun.Gun)
	local kyoten = KyotenService.get(id)
	if kyoten and kyoten.honjin then
		report(Shohai.honjinSeiatsuOf(previous))
	end
end

local function onHeiryokuZero()
	report("HeiryokuZero")
end

function ShohaiService.start()
	JoninService.defeated:Connect(onJoninDefeated)
	KyotenService.seiatsu:Connect(onSeiatsu)
	SaishutsugekiService.heiryokuZero:Connect(onHeiryokuZero)
end

return ShohaiService
