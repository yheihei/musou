--!strict
-- 出撃前の選択（ストーリー・ステージ・キャラクター・秘計）を受け付けるかの判定。選択の状態は SelectionService が持つ。
-- 受け付けるなら nil、受け付けないなら拒否の理由（RemoteSchema.RejectReason）を返す。Roblox の API は使わない。
--
-- - 選択はロビーのフェーズでだけ受け付け、待機中の人からは受け付けない
-- - ストーリーはリーダーだけが、4つのクランのストーリーのうち、リーダーが開放したステージのあるものから選べる。
--   ステージがまだ無いストーリーは準備中として選べない
-- - ステージはリーダーだけが、リーダーの開放済みのステージから選べる
-- - キャラクターはステージを選んだ後に、そのストーリーのクランの操作キャラクターから選べる。
--   そのステージの首領と NPC、パーティーの他のメンバーが選んだキャラクターは選べない
-- - 秘計は1枚ずつ選ぶか外す。本人が覚えた秘計から、持ち込みの上限まで、パーティーの他のメンバーと重ならずに選べる。
--   覚えた秘計の記録を読み終える前は選べない。外すのはいつでもできる。
--   選んだ順が戦闘中のボタン（1〜3、十字キーの左・上・右）の順になる
-- - 出撃はリーダーだけが、開放済みのステージを選び、出撃するメンバー全員がキャラクターを選んだ後にできる。
--   秘計の枚数は出撃の条件にしない

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

-- ロビーのフェーズの、待機中でないメンバーか。特技の習得（Tokugi.checkLearn）も同じ決まりで確かめる
function SelectionRules.checkRequester(requester: Requester): Reject?
	if requester.phase ~= "Lobby" then
		return "NotLobby"
	end
	if requester.waiting then
		return "Waiting"
	end
	return nil
end
local checkRequester = SelectionRules.checkRequester

-- 4つのクランのどれかか
local function isClanId(value: string): boolean
	for _, clan in Characters.clanIds do
		if clan == value then
			return true
		end
	end
	return false
end

-- ストーリーそのものを選べるか。リーダーかどうかとフェーズは見ない。unlocked はリーダーの開放済みのステージ。
-- 画面でストーリーを暗くするか（準備中か未開放か）を決めるのにも使う
function SelectionRules.checkStoryId(clanId: string, unlocked: { string }): Reject?
	if not isClanId(clanId) then
		return "UnknownStory"
	end
	local stages = Stages.storyOf(clanId :: Characters.ClanId)
	if #stages == 0 then
		return "StoryNotReady"
	end
	for _, stage in stages do
		if table.find(unlocked, stage.id) then
			return nil
		end
	end
	return "StoryLocked"
end

-- ストーリーの選択。clanId はストーリーのクラン、unlocked はリーダーの開放済みのステージ
function SelectionRules.checkStory(requester: Requester, clanId: string, unlocked: { string }): Reject?
	local reject = checkRequester(requester)
	if reject then
		return reject
	end
	if not requester.isLeader then
		return "NotLeader"
	end
	return SelectionRules.checkStoryId(clanId, unlocked)
end

-- リーダーが代わったときなどに、選んでいるストーリーを残すか。リーダーが開放したステージが無ければ外す
function SelectionRules.keepsStory(clanId: Characters.ClanId?, unlocked: { string }): boolean
	return clanId == nil or SelectionRules.checkStoryId(clanId, unlocked) == nil
end

-- 出撃前の画面に出すストーリー。選んでいるストーリー、無ければ選んでいるステージ（定義）のストーリー、
-- それも無ければリーダーが開放した最初のストーリー（Characters.clanIds の順）。どれも無ければ最初のクラン
function SelectionRules.shownStory(
	story: Characters.ClanId?,
	stage: Stages.Stage?,
	unlocked: { string }
): Characters.ClanId
	if story then
		return story
	end
	if stage then
		return stage.clan
	end
	for _, clan in Characters.clanIds do
		if SelectionRules.checkStoryId(clan, unlocked) == nil then
			return clan
		end
	end
	return Characters.clanIds[1]
end

-- 定義表にあり、リーダーが開放済みのステージか
local function checkStageId(stageId: string, unlocked: { string }): Reject?
	if not Stages.get(stageId) then
		return "UnknownStage"
	end
	if not table.find(unlocked, stageId) then
		return "StageLocked"
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
	return checkStageId(stageId, unlocked)
end

-- リーダーが代わったときなどに、選んでいるステージを残すか。リーダーが開放していなければ外す
function SelectionRules.keepsStage(stageId: string?, unlocked: { string }): boolean
	return stageId == nil or table.find(unlocked, stageId) ~= nil
end

-- ストーリーのクランで選べるキャラクターか。選べなければ理由を返す（ステージの首領と NPC、他のメンバーとの重なりは見ない）
local function checkCharacterInStory(character: Characters.Character, clan: Characters.ClanId): Reject?
	if not character.playable then
		return "NotPlayable"
	end
	if character.clan ~= clan then
		return "OtherClan"
	end
	return nil
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
	return checkCharacterInStory(character, stage.clan)
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

-- ストーリーかステージが変わったとき、選んでいるキャラクターを残すか。ステージを選んでいればそのステージで、
-- 選んでいなければストーリーのクランで選べないキャラクターを外す。どちらも選んでいなければ残す
function SelectionRules.keepsCharacter(characterId: string, stage: Stages.Stage?, story: Characters.ClanId?): boolean
	if stage then
		return checkCharacterInStage(characterId, stage) == nil
	end
	if story then
		local character = Characters.get(characterId)
		return character ~= nil and checkCharacterInStory(character, story) == nil
	end
	return true
end

-- 秘計を1枚選ぶ（selected が true）か外す（false）。mine は本人が選んだ順の秘計、
-- takenByOthers はパーティーの他のメンバーが選んだ秘計、learned は本人が覚えた秘計（記録を読み終える前は nil）。
-- 選べるのは覚えた秘計だけで、読み終える前は選べない（HikeiNotLoaded）。外すのはいつでもできる。
-- 受け付けたら nil と選んだ後の秘計を、受け付けなければ理由と mine をそのまま返す。引数は書き換えない
function SelectionRules.applyHikei(
	requester: Requester,
	hikeiId: string,
	selected: boolean,
	mine: { string },
	takenByOthers: { string },
	learned: { string }?
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
	if not learned then
		return "HikeiNotLoaded", mine
	end
	if not table.find(learned, hikeiId) then
		return "HikeiNotLearned", mine
	end
	local next = table.clone(mine)
	table.insert(next, hikeiId)
	reject = Hikei.checkMochikomi(next, takenByOthers)
	if reject then
		return reject, mine
	end
	return nil, next
end

-- 出撃。stageId はリーダーが選んでいるステージ（選んでいなければ nil）、unlocked はリーダーの開放済みのステージ、
-- ready は出撃するメンバー（待機中でない人）が全員キャラクターを選んでいるか
function SelectionRules.checkShutsugeki(
	requester: Requester,
	stageId: string?,
	unlocked: { string },
	ready: boolean
): Reject?
	local reject = checkRequester(requester)
	if reject then
		return reject
	end
	if not requester.isLeader then
		return "NotLeader"
	end
	if not stageId then
		return "StageNotSelected"
	end
	reject = checkStageId(stageId, unlocked)
	if reject then
		return reject
	end
	if not ready then
		return "MembersNotReady"
	end
	return nil
end

return SelectionRules
