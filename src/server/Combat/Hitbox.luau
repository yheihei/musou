--!strict
-- 当たり判定ヘルパー。空間クエリで範囲内の敵モデルを重複なく返す。

local Hitbox = {}

local function collectModels(parts: { BasePart }, folder: Instance): { Model }
	local seen: { [Model]: boolean } = {}
	local models = {}
	for _, part in parts do
		local model = part:FindFirstAncestorOfClass("Model")
		if model and model.Parent == folder and not seen[model] then
			seen[model] = true
			table.insert(models, model)
		end
	end
	return models
end

local function paramsFor(folder: Instance): OverlapParams
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { folder }
	return params
end

-- root の正面に奥行き range・幅 width の箱を出す
function Hitbox.front(root: BasePart, range: number, width: number, folder: Instance): { Model }
	local cframe = root.CFrame * CFrame.new(0, 0, -range / 2)
	local parts = workspace:GetPartBoundsInBox(cframe, Vector3.new(width, 8, range), paramsFor(folder))
	return collectModels(parts, folder)
end

-- center を中心とした半径 radius の球
function Hitbox.sphere(center: Vector3, radius: number, folder: Instance): { Model }
	local parts = workspace:GetPartBoundsInRadius(center, radius, paramsFor(folder))
	return collectModels(parts, folder)
end

return Hitbox
