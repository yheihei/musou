--!strict
-- クライアント側エントリーポイント

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SoundPlayer = require(ReplicatedStorage.Shared.SoundPlayer)

local Controllers = script:WaitForChild("Controllers")

local PartyClient = require(script:WaitForChild("PartyClient"))
local TokugiClient = require(script:WaitForChild("TokugiClient"))
local TitleController = require(Controllers:WaitForChild("TitleController"))
local InputController = require(Controllers:WaitForChild("InputController"))
local HUDController = require(Controllers:WaitForChild("HUDController"))
local BattleStatusController = require(Controllers:WaitForChild("BattleStatusController"))
local MinimapController = require(Controllers:WaitForChild("MinimapController"))
local NoticeController = require(Controllers:WaitForChild("NoticeController"))
local SelectionController = require(Controllers:WaitForChild("SelectionController"))
local ResultController = require(Controllers:WaitForChild("ResultController"))
local SerifuController = require(Controllers:WaitForChild("SerifuController"))
local EventSceneController = require(Controllers:WaitForChild("EventSceneController"))
local SkipController = require(Controllers:WaitForChild("SkipController"))
local PushController = require(Controllers:WaitForChild("PushController"))
local MotionController = require(Controllers:WaitForChild("MotionController"))
local HikeiMejirushiController = require(Controllers:WaitForChild("HikeiMejirushiController"))
local HikeiNoticeController = require(Controllers:WaitForChild("HikeiNoticeController"))
local TouchControlsController = require(Controllers:WaitForChild("TouchControlsController"))
local BgmController = require(Controllers:WaitForChild("BgmController"))

-- 入室直後の PartyState と特技の記録を受け取るため、画面より先に始める
PartyClient.start()
TokugiClient.start()
-- 入室したらタイトル画面を出す。出撃前の画面と非公式の表記は、タイトル画面を閉じるまで出さないので、それらより先に始める
TitleController.start()
InputController.start()
HUDController.start()
BattleStatusController.start()
MinimapController.start()
NoticeController.start()
SelectionController.start()
ResultController.start()
SerifuController.start()
EventSceneController.start()
SkipController.start()
PushController.start()
MotionController.start()
HikeiMejirushiController.start()
HikeiNoticeController.start()
-- スマホの戦闘の操作ボタン。出している間は戦闘の画面をタッチの配置にする（Ui.setTouchLayout）
TouchControlsController.start()
-- BGM は PartyState と StageResult から場面を決めて流す。曲の読み込みは BgmController が別スレッドで行う
BgmController.start()
-- 効果音を先に読み込み、最初に鳴らすときの遅れを無くす
task.spawn(SoundPlayer.preload)
