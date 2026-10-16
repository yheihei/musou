--!strict
-- テストプレイ（F5）か実行（F8）を始めると、合成した刃の骨と R15 を並べ、往路と復路を交互に流す。
-- 取り込んだモデルで確かめるときは、コマンドバー（サーバー表示）で require(game.ServerStorage.MeshyRig).clear() を打つ

local ServerStorage = game:GetService("ServerStorage")

local MeshyRig = require(ServerStorage:WaitForChild("MeshyRig"))

print(`[MeshyRig] {MeshyRig.demo()}`)
