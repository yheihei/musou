--!strict
-- イベントシーンのスキップの集計。シーンを見ている出撃メンバー全員がスキップを押したら飛ばす。
-- 同じ人の二重押しは1回に数え、途中で抜けた人は全体の人数から外す。
-- シーンを見るメンバーはシーンの開始時に決め、後から入った人（待機中の人）は数えない。
-- Roblox の API は使わない。

export type Vote = {
	-- シーンを見ているメンバーの UserId（入った順）
	voters: { number },
	-- スキップを押したメンバーの UserId
	skipped: { [number]: boolean },
}

local SkipVote = {}

-- voters はシーンを見るメンバーの UserId
function SkipVote.new(voters: { number }): Vote
	return { voters = table.clone(voters), skipped = {} }
end

-- userId のスキップを数える。数えたら true。シーンを見ていない人と、押し済みの人は数えない
function SkipVote.skip(vote: Vote, userId: number): boolean
	if not table.find(vote.voters, userId) or vote.skipped[userId] then
		return false
	end
	vote.skipped[userId] = true
	return true
end

-- 抜けた人を全体の人数から外す。外したら true
function SkipVote.leave(vote: Vote, userId: number): boolean
	local index = table.find(vote.voters, userId)
	if not index then
		return false
	end
	table.remove(vote.voters, index)
	vote.skipped[userId] = nil
	return true
end

-- present に無い人をすべて抜けたものとして外す。外した人がいれば true
function SkipVote.retain(vote: Vote, present: { number }): boolean
	local changed = false
	for _, userId in table.clone(vote.voters) do
		if not table.find(present, userId) then
			changed = SkipVote.leave(vote, userId) or changed
		end
	end
	return changed
end

-- スキップした人数と全体の人数
function SkipVote.count(vote: Vote): (number, number)
	local skipped = 0
	for _, userId in vote.voters do
		if vote.skipped[userId] then
			skipped += 1
		end
	end
	return skipped, #vote.voters
end

-- 全員がスキップしたか。見ている人がいなければ false（全員が抜けたときはステージの進行がロビーへ戻す）
function SkipVote.isComplete(vote: Vote): boolean
	local skipped, total = SkipVote.count(vote)
	return total > 0 and skipped == total
end

return SkipVote
