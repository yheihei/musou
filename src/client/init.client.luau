--!strict
-- クライアント側エントリーポイント

local Controllers = script:WaitForChild("Controllers")

local InputController = require(Controllers:WaitForChild("InputController"))
local HUDController = require(Controllers:WaitForChild("HUDController"))

InputController.start()
HUDController.start()
