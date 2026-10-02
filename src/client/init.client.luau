--!strict
-- クライアント側エントリーポイント

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SoundPlayer = require(ReplicatedStorage.Shared.SoundPlayer)

local Controllers = script:WaitForChild("Controllers")

local PartyClient = require(script:WaitForChild("PartyClient"))
local InputController = require(Controllers:WaitForChild("InputController"))
local HUDController = require(Controllers:WaitForChild("HUDController"))
local NoticeController = require(Controllers:WaitForChild("NoticeController"))
local SelectionController = require(Controllers:WaitForChild("SelectionController"))
local SerifuController = require(Controllers:WaitForChild("SerifuController"))
local PushController = require(Controllers:WaitForChild("PushController"))
local MotionController = require(Controllers:WaitForChild("MotionController"))
local HikeiMejirushiController = require(Controllers:WaitForChild("HikeiMejirushiController"))
local HikeiNoticeController = require(Controllers:WaitForChild("HikeiNoticeController"))

-- 入室直後の PartyState を受け取るため、画面より先に始める
PartyClient.start()
InputController.start()
HUDController.start()
NoticeController.start()
SelectionController.start()
SerifuController.start()
PushController.start()
MotionController.start()
HikeiMejirushiController.start()
HikeiNoticeController.start()
-- 効果音を先に読み込み、最初に鳴らすときの遅れを無くす
task.spawn(SoundPlayer.preload)
