--!strict
-- 出撃前の選択（ステージ・キャラクター・秘計）を受け付けるかの判定。選択の状態は SelectionService が持つ。
-- 受け付けるなら nil、受け付けないなら拒否の理由（RemoteSchema.RejectReason）を返す。Roblox の API は使わない。
--
-- - 選択はロビーのフェーズでだけ受け付け、待機中の人からは受け付けない
-- - ステージはリーダーだけが、リーダーの開放済みのステージから選べる
-- - キャラクターはステージを選んだ後に、そのストーリーのクランの操作キャラクターから選べる。
--   そのステージの首領と NPC、パーティーの他のメンバーが選んだキャラクターは選べない
-- - 秘計は1枚ずつ選ぶか外す。持ち込みの上限まで、パーティーの他のメンバーと重ならずに選べる。
--   選んだ順が戦闘中のボタン（1〜3、十字キーの左・上・右）の順になる

local Characters = require("./Characters")
local Hikei = require("./Hikei")
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

-- ステージで選べるキャラクターか。選べなければ理由を返す（他のメンバーとの重なりは見ない）
local function checkCharacterInStage(characterId: string, stage: Stages.Stage): Reject?
	local character = Characters.get(characterId)
	if not character then
		return "UnknownCharacter"
	end
	if characterId == stage.shuryo.mikatagun or characterId == stage.shuryo.tekigun then
		return "Shuryo"
	end
	if table.find(stage.npcs, characterId) then
		return "NpcInStage"
	end
	if not character.playable then
		return "NotPlayable"
	end
	if character.clan ~= stage.clan then
		return "OtherClan"
	end
	return nil
end

-- キャラクターの選択。stage は選んでいるステージの定義（選んでいなければ nil）、
-- takenByOthers はパーティーの他のメンバーが選んだキャラクター
function SelectionRules.checkCharacter(
	requester: Requester,
	characterId: string,
	stage: Stages.Stage?,
	takenByOthers: { string }
): Reject?
	local reject = checkRequester(requester)
	if reject then
		return reject
	end
	if not stage then
		return "StageNotSelected"
	end
	reject = checkCharacterInStage(characterId, stage)
	if reject then
		return reject
	end
	if table.find(takenByOthers, characterId) then
		return "CharacterTaken"
	end
	return nil
end

-- ステージが変わったとき、選んでいるキャラクターを残すか。新しいステージで選べなければ外す
function SelectionRules.keepsCharacter(characterId: string, stage: Stages.Stage): boolean
	return checkCharacterInStage(characterId, stage) == nil
end

-- 秘計を1枚選ぶ（selected が true）か外す（false）。mine は本人が選んだ順の秘計、
-- takenByOthers はパーティーの他のメンバーが選んだ秘計。
-- 受け付けたら nil と選んだ後の秘計を、受け付けなければ理由と mine をそのまま返す。引数は書き換えない
function SelectionRules.applyHikei(
	requester: Requester,
	hikeiId: string,
	selected: boolean,
	mine: { string },
	takenByOthers: { string }
): (Reject?, { string })
	local reject = checkRequester(requester)
	if reject then
		return reject, mine
	end
	if not Hikei.get(hikeiId) then
		return "UnknownHikei", mine
	end
	local index = table.find(mine, hikeiId)
	if not selected then
		local next = table.clone(mine)
		if index then
			table.remove(next, index)
		end
		return nil, next
	end
	if index then
		return nil, table.clone(mine)
	end
	local next = table.clone(mine)
	table.insert(next, hikeiId)
	reject = Hikei.checkMochikomi(next, takenByOthers)
	if reject then
		return reject, mine
	end
	return nil, next
end

return SelectionRules
