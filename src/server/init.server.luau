--!strict
-- サーバー側エントリーポイント。各サービスを初期化して起動する。

local Services = script:WaitForChild("Services")

local PlayerService = require(Services:WaitForChild("PlayerService"))
local EnemyService = require(Services:WaitForChild("EnemyService"))
local CombatService = require(Services:WaitForChild("CombatService"))

PlayerService.start()
EnemyService.start()
CombatService.start()
