--!strict
-- 水平位置の真下にある地面の高さを求める。
-- キャラクターや部隊を出現させる処理は、固定の高さを使わずこの関数で高さを決める。
-- キャラクター（Humanoid を持つモデル）と目印には当てない。
-- 目印は CanQuery を false にして置くので光線は当たらないが、念のためタグ Mejirushi でも除く。
-- 当たり判定のある見た目（秘計の落石の岩など）は CanQuery が効かないので、タグ NotGround（IGNORE_TAG）を付けて除く。

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local Mejirushi = require("./Mejirushi")

local Ground = {}

-- 地面の高さの計算で当てない部品に付けるタグ（当たり判定があっても地面に数えない）
Ground.IGNORE_TAG = "NotGround"

-- 上から下へ当てる光線の開始の高さと長さ（スタッド）
local RAY_TOP = 1000
local RAY_LENGTH = 2000
-- キャラクターに当たって除外し直す回数の上限
local MAX_RETRIES = 8

local function characterOf(part: BasePart): Model?
	local model = part:FindFirstAncestorOfClass("Model")
	while model do
		if model:FindFirstChildOfClass("Humanoid") then
			return model
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end

-- (x, z) の真下の地面の高さを返す。見つからなければ警告を出して nil を返す。
-- fromY を渡すと、その高さから下へ探す（屋根の下に出したいときなど）。
-- exclude を渡すと、その中の部品にも当てない（飛んでいる敵のフォルダなど）
function Ground.heightAt(x: number, z: number, fromY: number?, exclude: { Instance }?): number?
	local excluded: { Instance } = CollectionService:GetTagged(Mejirushi.TAG)
	for _, instance in exclude or {} do
		table.insert(excluded, instance)
	end
	for _, instance in CollectionService:GetTagged(Ground.IGNORE_TAG) do
		table.insert(excluded, instance)
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(excluded, player.Character)
		end
	end

	local top = fromY or RAY_TOP
	local origin = Vector3.new(x, top, z)
	local direction = Vector3.new(0, -RAY_LENGTH, 0)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude

	for _ = 1, MAX_RETRIES do
		params.FilterDescendantsInstances = excluded
		local result = workspace:Raycast(origin, direction, params)
		if not result then
			break
		end
		local character = if result.Instance:IsA("BasePart") then characterOf(result.Instance) else nil
		if not character then
			return result.Position.Y
		end
		table.insert(excluded, character)
	end

	warn(`Ground.heightAt: ({x}, {z}) の真下に地面が見つからない（y = {top} から探した）`)
	return nil
end

-- Humanoid を持つモデルを、足が地面に付く高さで (x, z) に置く。地面が無ければ置かずに false を返す
function Ground.placeCharacter(model: Model, x: number, z: number, fromY: number?): boolean
	local groundY = Ground.heightAt(x, z, fromY)
	if not groundY then
		return false
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model.PrimaryPart
	if not humanoid or not root then
		model:PivotTo(CFrame.new(x, groundY + model:GetExtentsSize().Y / 2, z))
		return true
	end
	-- R15 の HipHeight は HumanoidRootPart の下面から地面までの高さ
	local rootY = groundY + humanoid.HipHeight + root.Size.Y / 2
	model:PivotTo(CFrame.new(x, rootY, z) * model:GetPivot().Rotation)
	return true
end

return Ground
