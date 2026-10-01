--!strict
-- 出撃前の選択（ステージ・キャラクター・秘計）を受け付けるかの判定。選択の状態は SelectionService が持つ。
-- 受け付けるなら nil、受け付けないなら拒否の理由（RemoteSchema.RejectReason）を返す。Roblox の API は使わない。
--
-- - 選択はロビーのフェーズでだけ受け付け、待機中の人からは受け付けない
-- - ステージはリーダーだけが、リーダーの開放済みのステージから選べる

local RemoteSchema = require("./RemoteSchema")
local Stages = require("./Stages")

export type Reject = RemoteSchema.RejectReason

-- 選択を送ったメンバーの立場
export type Requester = {
	phase: RemoteSchema.Phase,
	isLeader: boolean,
	-- 出撃中に入り、ロビーで待っているか
	waiting: boolean,
}

local SelectionRules = {}

-- ロビーのフェーズの、待機中でないメンバーか
local function checkRequester(requester: Requester): Reject?
	if requester.phase ~= "Lobby" then
		return "NotLobby"
	end
	if requester.waiting then
		return "Waiting"
	end
	return nil
end

-- ステージの選択。unlocked はリーダーの開放済みのステージ
function SelectionRules.checkStage(requester: Requester, stageId: string, unlocked: { string }): Reject?
	local reject = checkRequester(requester)
	if reject then
		return reject
	end
	if not requester.isLeader then
		return "NotLeader"
	end
	if not Stages.get(stageId) then
		return "UnknownStage"
	end
	if not table.find(unlocked, stageId) then
		return "StageLocked"
	end
	return nil
end

-- リーダーが代わったときなどに、選んでいるステージを残すか。リーダーが開放していなければ外す
function SelectionRules.keepsStage(stageId: string?, unlocked: { string }): boolean
	return stageId == nil or table.find(unlocked, stageId) ~= nil
end

return SelectionRules
