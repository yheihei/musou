--!strict
local SkipVote = require("./SkipVote")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

local function counts(vote: SkipVote.Vote): { number }
	local skipped, total = SkipVote.count(vote)
	return { skipped, total }
end

test("押した人数と全体の人数を数え、全員が押したら完了する", function()
	local vote = SkipVote.new({ 1, 2, 3 })
	expect(counts(vote)).toEqual({ 0, 3 })
	expect(SkipVote.skip(vote, 1)).toBe(true)
	expect(SkipVote.skip(vote, 2)).toBe(true)
	expect(counts(vote)).toEqual({ 2, 3 })
	expect(SkipVote.isComplete(vote)).toBe(false)
	expect(SkipVote.skip(vote, 3)).toBe(true)
	expect(counts(vote)).toEqual({ 3, 3 })
	expect(SkipVote.isComplete(vote)).toBe(true)
end)

test("同じ人の二重押しは1回に数える", function()
	local vote = SkipVote.new({ 1, 2 })
	expect(SkipVote.skip(vote, 1)).toBe(true)
	expect(SkipVote.skip(vote, 1)).toBe(false)
	expect(counts(vote)).toEqual({ 1, 2 })
	expect(SkipVote.isComplete(vote)).toBe(false)
end)

test("シーンを見ていない人（待機中の人）のスキップは数えない", function()
	local vote = SkipVote.new({ 1, 2 })
	expect(SkipVote.skip(vote, 9)).toBe(false)
	expect(counts(vote)).toEqual({ 0, 2 })
end)

test("途中で抜けた人は全体の人数から外し、押していた分も外す", function()
	local vote = SkipVote.new({ 1, 2, 3 })
	SkipVote.skip(vote, 1)
	SkipVote.skip(vote, 2)
	expect(SkipVote.leave(vote, 2)).toBe(true)
	expect(counts(vote)).toEqual({ 1, 2 })
	expect(SkipVote.leave(vote, 2)).toBe(false)
	expect(SkipVote.skip(vote, 2)).toBe(false)
end)

test("押していない人が抜けて、残りの全員が押していれば完了する", function()
	local vote = SkipVote.new({ 1, 2, 3 })
	SkipVote.skip(vote, 1)
	SkipVote.skip(vote, 2)
	expect(SkipVote.isComplete(vote)).toBe(false)
	SkipVote.leave(vote, 3)
	expect(counts(vote)).toEqual({ 2, 2 })
	expect(SkipVote.isComplete(vote)).toBe(true)
end)

test("残っている人の一覧に無い人をまとめて外す", function()
	local vote = SkipVote.new({ 1, 2, 3, 4 })
	SkipVote.skip(vote, 4)
	expect(SkipVote.retain(vote, { 1, 3 })).toBe(true)
	expect(vote.voters).toEqual({ 1, 3 })
	expect(counts(vote)).toEqual({ 0, 2 })
	expect(SkipVote.retain(vote, { 1, 3, 5 })).toBe(false)
end)

test("見ている人が1人もいなければ完了にしない", function()
	local vote = SkipVote.new({ 1 })
	SkipVote.leave(vote, 1)
	expect(counts(vote)).toEqual({ 0, 0 })
	expect(SkipVote.isComplete(vote)).toBe(false)
	expect(SkipVote.isComplete(SkipVote.new({}))).toBe(false)
end)

test("渡したメンバーの一覧は書き換えない", function()
	local voters = { 1, 2 }
	local vote = SkipVote.new(voters)
	SkipVote.leave(vote, 1)
	expect(voters).toEqual({ 1, 2 })
end)
