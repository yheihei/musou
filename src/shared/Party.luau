--!strict
-- パーティーとリーダーの計算。サーバーに入ったプレイヤーを入った順に並べ、
-- 一番早く入った人をリーダーにする。リーダーが抜けたら次に古い人がリーダーになる。
-- ロビー以外のフェーズで入った人は待機中にし、ロビーに戻った時点で合流させる。
-- 1サーバーが1パーティーにあたる（ADR 0002）。Roblox の API は使わない。

local Config = require("./Config")
local RemoteSchema = require("./RemoteSchema")

export type Phase = RemoteSchema.Phase

export type Member = {
	userId: number,
	name: string,
	-- サーバーに入った順（1から）。入り直した人は新しい番号になる
	joinOrder: number,
	-- 出撃中に入り、ロビーで待っているか
	waiting: boolean,
}

export type Party = {
	phase: Phase,
	-- 入った順に並べる
	members: { Member },
	-- 次に入った人に振る番号
	nextJoinOrder: number,
}

local Party = {}

function Party.new(): Party
	return { phase = "Lobby", members = {}, nextJoinOrder = 1 }
end

function Party.get(party: Party, userId: number): Member?
	for _, member in party.members do
		if member.userId == userId then
			return member
		end
	end
	return nil
end

function Party.isFull(party: Party): boolean
	return #party.members >= Config.Party.MaxMembers
end

-- パーティーに入れる。満員なら nil。ロビー以外のフェーズで入った人は待機中にする
function Party.join(party: Party, userId: number, name: string): Member?
	local existing = Party.get(party, userId)
	if existing then
		return existing
	end
	if Party.isFull(party) then
		return nil
	end
	local member: Member = {
		userId = userId,
		name = name,
		joinOrder = party.nextJoinOrder,
		waiting = party.phase ~= "Lobby",
	}
	party.nextJoinOrder += 1
	table.insert(party.members, member)
	return member
end

-- パーティーから外す。外した人を返し、いなければ nil
function Party.leave(party: Party, userId: number): Member?
	for index, member in party.members do
		if member.userId == userId then
			table.remove(party.members, index)
			return member
		end
	end
	return nil
end

-- リーダー。一番早く入った人で、誰もいなければ nil
function Party.leader(party: Party): Member?
	return party.members[1]
end

-- フェーズを変える。ロビーに戻ったら、待機中の人を合流させる
function Party.setPhase(party: Party, phase: Phase)
	party.phase = phase
	if phase == "Lobby" then
		for _, member in party.members do
			member.waiting = false
		end
	end
end

-- 出撃するメンバー（待機中でない人）を入った順に返す
function Party.activeMembers(party: Party): { Member }
	local result = {}
	for _, member in party.members do
		if not member.waiting then
			table.insert(result, member)
		end
	end
	return result
end

-- クライアントへ送る PartyState の写しを作る。
-- ストーリー・ステージ・開放済みのステージ・キャラクター・秘計は、それぞれを扱う処理が extra で渡す
export type Extra = {
	story: RemoteSchema.ClanId?,
	stage: string?,
	unlockedStages: { string }?,
	characterOf: ((userId: number) -> string?)?,
	hikeiOf: ((userId: number) -> { string })?,
}

function Party.toState(party: Party, extra: Extra?): RemoteSchema.PartyState
	local given: Extra = extra or {}
	local leader = Party.leader(party)
	local members: { RemoteSchema.MemberState } = {}
	for _, member in party.members do
		table.insert(members, {
			userId = member.userId,
			name = member.name,
			joinOrder = member.joinOrder,
			waiting = member.waiting,
			character = if given.characterOf then given.characterOf(member.userId) else nil,
			hikei = if given.hikeiOf then given.hikeiOf(member.userId) else {},
		})
	end
	return {
		phase = party.phase,
		leader = if leader then leader.userId else nil,
		story = given.story,
		stage = given.stage,
		unlockedStages = given.unlockedStages or {},
		members = members,
	}
end

return Party
