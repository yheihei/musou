--!strict
-- 武器のモデルの名前と組み立ての決まり。モデルは assets/weapons にあり、Rojo が ReplicatedStorage.Weapons に置く。
-- Roblox の API は使わない。
--
-- - モデルは Part を組んだ仮のもの。M2 で本番の見た目に差し替える
-- - 見た目専用で、当たらず重さも持たない。攻撃判定はスクリプトと Config.luau が持つ
-- - どのモデルも、握りの部品 Handle と、その中の Attachment の Grip を持つ。Grip の前（-Z）が刃先、上（+Y）が峰
--   （手裏剣は前が先端の1つで、上と前で張る面に刃が並ぶ）
-- - Handle 以外の部品は Weld で Handle に溶接してあり、モデルの PrimaryPart は Handle

local Buki = {}

-- モデルを置く ReplicatedStorage のフォルダ
Buki.FOLDER = "Weapons"
Buki.HANDLE = "Handle"
Buki.GRIP = "Grip"

-- 武器のモデルの ID。NINJAMCP の武器の英名にする
Buki.ids = { "Shuriken", "Oodenta", "Gyuto" }

function Buki.isBuki(id: string): boolean
	return table.find(Buki.ids, id) ~= nil
end

return Buki
