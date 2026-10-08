--!strict
-- プレイヤーの視界（カメラの位置・向き・画角）と、点が視界に入るかの判定。
-- クライアントはカメラを Remotes.ReportCameraView で送り、サーバーは下忍を視界の外にだけ出す（#81）。
-- 届いた値の検証もここに置く。数値は Config.luau の CameraView 節にある。Roblox の API は使わない（位置と向きは vector）。
--
-- - 視界は、カメラの位置から向きの方向へ広がる四角錐。縦の画角 fovY（度）と、画面の横と縦の比 aspect で決める
-- - 点の周りの半径 margin の球が視界に少しでもかかれば、見えているとみなす（部隊の広がりと体の大きさの分）
-- - 地形や建物で隠れることと、遠くて見えないことは考えない（見えている側に倒す）

local Config = require("./Config")

export type Params = Config.CameraViewSection

export type View = {
	-- カメラの位置
	position: vector,
	-- カメラの向き（長さ 1）
	look: vector,
	-- 縦の画角（度）
	fovY: number,
	-- 画面の横と縦の比
	aspect: number,
}

local CameraView = {}

-- 受け付ける縦の画角（度）と、画面の横と縦の比の範囲。Roblox のカメラの画角は 1〜120 度
CameraView.MIN_FOV = 1
CameraView.MAX_FOV = 120
CameraView.MIN_ASPECT = 0.2
CameraView.MAX_ASPECT = 5

local UP = vector.create(0, 1, 0)
local RIGHT = vector.create(1, 0, 0)

local function isFinite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

local function isFiniteVector(value: vector): boolean
	return isFinite(value.x) and isFinite(value.y) and isFinite(value.z)
end

-- クライアントから届いた値を視界にする。型・有限の値・向きの長さ・画角と比の範囲のどれかが合わなければ nil
function CameraView.validate(position: unknown, look: unknown, fovY: unknown, aspect: unknown): View?
	if type(position) ~= "vector" or type(look) ~= "vector" or type(fovY) ~= "number" or type(aspect) ~= "number" then
		return nil
	end
	local p, l = position :: vector, look :: vector
	if not isFiniteVector(p) or not isFiniteVector(l) then
		return nil
	end
	if vector.magnitude(l) < 1e-3 then
		return nil
	end
	-- 比べられない値（NaN）は範囲の比べ方で外れる
	if not (fovY >= CameraView.MIN_FOV and fovY <= CameraView.MAX_FOV) then
		return nil
	end
	if not (aspect >= CameraView.MIN_ASPECT and aspect <= CameraView.MAX_ASPECT) then
		return nil
	end
	return { position = p, look = vector.normalize(l), fovY = fovY, aspect = aspect }
end

-- カメラの報告が無いときの視界。キャラクターの頭の高さから、体の向き（水平）を見ているとみなす
function CameraView.fromFacing(position: vector, facing: vector, params: Params?): View
	local p = params or Config.CameraView
	local flat = vector.create(facing.x, 0, facing.z)
	local look = if vector.magnitude(flat) > 1e-6 then vector.normalize(flat) else vector.create(0, 0, -1)
	return {
		position = position + vector.create(0, p.FallbackHeight, 0),
		look = look,
		fovY = p.FallbackFov,
		aspect = p.FallbackAspect,
	}
end

-- point の周りの半径 margin の球が、視界に少しでもかかるか
function CameraView.sees(view: View, point: vector, margin: number): boolean
	local offset = point - view.position
	local forward = view.look
	local depth = vector.dot(offset, forward)
	-- カメラの後ろに球が丸ごと出ていれば見えない
	if depth + margin <= 0 then
		return false
	end
	-- 右と上の向き。真上か真下を向いているときは右を決められないので、東を右にする
	local side = vector.cross(forward, UP)
	local right = if vector.magnitude(side) > 1e-6 then vector.normalize(side) else RIGHT
	local up = vector.cross(right, forward)
	local x = math.abs(vector.dot(offset, right))
	local y = math.abs(vector.dot(offset, up))
	local tanY = math.tan(math.rad(view.fovY / 2))
	local tanX = tanY * view.aspect
	-- 視界の横と縦の面から球の中心までの距離。margin より外なら、球は面の外に丸ごと出ている
	local outsideX = (x - depth * tanX) / math.sqrt(1 + tanX * tanX)
	local outsideY = (y - depth * tanY) / math.sqrt(1 + tanY * tanY)
	return outsideX <= margin and outsideY <= margin
end

-- 視界のどれかに point の周りの半径 margin の球がかかるか
function CameraView.seenByAny(views: { View }, point: vector, margin: number): boolean
	for _, view in views do
		if CameraView.sees(view, point, margin) then
			return true
		end
	end
	return false
end

return CameraView
