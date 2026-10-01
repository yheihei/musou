--!strict
-- クライアント側エントリーポイント

local Controllers = script:WaitForChild("Controllers")

local PartyClient = require(script:WaitForChild("PartyClient"))
local InputController = require(Controllers:WaitForChild("InputController"))
local HUDController = require(Controllers:WaitForChild("HUDController"))
local NoticeController = require(Controllers:WaitForChild("NoticeController"))
local PushController = require(Controllers:WaitForChild("PushController"))
local MotionController = require(Controllers:WaitForChild("MotionController"))

-- 入室直後の PartyState を受け取るため、画面より先に始める
PartyClient.start()
InputController.start()
HUDController.start()
NoticeController.start()
PushController.start()
MotionController.start()
