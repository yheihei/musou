--!strict
-- サーバー側エントリーポイント。各サービスを初期化して起動する。

local Services = script:WaitForChild("Services")

local DebugCommand = require(script:WaitForChild("DebugCommand"))
local PartyService = require(Services:WaitForChild("PartyService"))
local ProgressService = require(Services:WaitForChild("ProgressService"))
local SelectionService = require(Services:WaitForChild("SelectionService"))
local PlayerService = require(Services:WaitForChild("PlayerService"))
local ActionService = require(Services:WaitForChild("ActionService"))
local DamageService = require(Services:WaitForChild("DamageService"))
local EnemyService = require(Services:WaitForChild("EnemyService"))
local CombatService = require(Services:WaitForChild("CombatService"))

DebugCommand.start()
PartyService.start()
ProgressService.start()
SelectionService.start()
PlayerService.start()
ActionService.start()
DamageService.start()
EnemyService.start()
CombatService.start()
