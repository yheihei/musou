--!strict
-- 戦闘中の台詞を出す。話者のキャラクター ID・表情・台詞 ID を Remotes.PlaySerifu で送り、
-- クライアントが ReplicatedStorage.Shared.Serifu から文を引いて画面の端に出す。
-- 戦況に合わせて台詞を出す処理（SenkyoSerifuService）は、出撃メンバーにだけ送る（ロビーで待っている人には出さない）。
-- 窓口の PlaySerifu は全員に送る。

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteSchema = require(ReplicatedStorage.Shared.RemoteSchema)
local Serifu = require(ReplicatedStorage.Shared.Serifu)
local DebugCommand = require(script.Parent.Parent.DebugCommand)

local SerifuService = {}

local remote: RemoteEvent

-- 台詞を出す。players を渡すとその人たちにだけ、省くと全員に送る。表情か台詞 ID が正しくなければ警告を出して false
function SerifuService.play(
	characterId: string,
	hyojo: RemoteSchema.Hyojo,
	serifuId: string,
	players: { Player }?
): boolean
	if not RemoteSchema.isId(characterId) then
		warn(`SerifuService: 話者のキャラクター ID が正しくない（{tostring(characterId)}）`)
		return false
	end
	if not table.find(RemoteSchema.hyojo, hyojo) then
		warn(`SerifuService: 表情 {tostring(hyojo)} は無い`)
		return false
	end
	if not Serifu.textOf(serifuId) then
		warn(`SerifuService: 台詞 {tostring(serifuId)} は Serifu.luau の表に無い`)
		return false
	end
	if players then
		for _, player in players do
			remote:FireClient(player, characterId, hyojo, serifuId)
		end
	else
		remote:FireAllClients(characterId, hyojo, serifuId)
	end
	return true
end

local function registerDebugCommands()
	DebugCommand.register(
		"PlaySerifu",
		`<キャラクター ID> <{table.concat(RemoteSchema.hyojo, "|")}> <台詞 ID>`,
		"戦闘中の台詞を全員の画面の端に出す（台詞 ID は Serifu.luau の表の ID。ShikenTsujo・ShikenTanshuku・ShikenNagai など）",
		function(characterId, hyojo, serifuId)
			if not SerifuService.play(characterId, hyojo, serifuId) then
				return "台詞を出せなかった（警告を見る）"
			end
			return `{characterId} の台詞 {serifuId} を全員に出した`
		end
	)
end

function SerifuService.start()
	remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PlaySerifu") :: RemoteEvent
	registerDebugCommands()
end

return SerifuService
