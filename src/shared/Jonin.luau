--!strict
-- 名前を持つ上忍と首領のデータ。上忍は部隊を率いて部隊とともに動き、首領は本陣にとどまる。
-- 開始時の顔ぶれは、配置の構成（Haichi.luau の部隊の上忍）とステージの定義（Stages.luau の両軍の首領）から決める。
-- 能力値は Config.luau の Stats 節（上忍は Jonin、首領は Shuryo）に、補正を Stats.compute で足して求める。
-- 味方軍の上忍と首領は、体力・攻撃・防御に Stats 節の MikatagunScale を掛けて敵軍よりやや弱くする。
-- 自分の軍の支配エリアの中では、攻撃と防御が上がる（ShihaiArea.modifiersOf）。
-- 敵軍の上忍と首領の体力は、出撃したときのパーティーの人数で上げる（PartySize.modifiersOf）。
-- 体力が 0 になると倒れる。率いていた部隊は残し、士気だけを下げる（Butai.loseJonin）。
-- 位置は水平の (x, z) で持つ。Roblox の API は使わない。

local Characters = require("./Characters")
local Config = require("./Config")
local Gun = require("./Gun")
local Haichi = require("./Haichi")
local PartySize = require("./PartySize")
local ShihaiArea = require("./ShihaiArea")
local Stages = require("./Stages")
local Stats = require("./Stats")

export type Point = { x: number, z: number }

-- 開始時の上忍か首領の顔ぶれ
export type Entry = {
	-- キャラクター ID
	id: string,
	gun: Gun.Gun,
	-- 率いる部隊の ID。首領は nil
	butai: string?,
	shuryo: boolean,
	-- 開始時にいる拠点（首領は本陣）
	kyoten: string,
}

export type Jonin = {
	-- キャラクター ID
	id: string,
	displayName: string,
	gun: Gun.Gun,
	-- 今の能力値。軍の補正と、支配エリアの中なら支配エリアの補正を足したもの
	stats: Stats.Values,
	-- 支配エリアの補正を除いた補正（軍の補正と人数による調整）
	modifiers: { Stats.Modifier },
	-- 自分の軍の支配エリアの中か
	shihaiArea: boolean,
	-- 今の体力。0 なら倒れている
	health: number,
	-- 率いる部隊の ID。首領と、部隊を失った上忍は nil
	butai: string?,
	shuryo: boolean,
	-- 開始時にいた拠点（首領がとどまる本陣）
	kyoten: string,
	position: Point,
}

local Jonin = {}

-- 配置の構成とステージの定義から、開始時の上忍と首領を並べる。上忍は構成の部隊の順、首領は味方軍・敵軍の順。
-- 本陣の無い軍の首領と、ステージに首領の決まっていない軍は入れない
function Jonin.entriesOf(haichi: Haichi.Haichi, stage: Stages.Stage): { Entry }
	local entries: { Entry } = {}
	for _, butai in haichi.butai do
		local jonin = butai.jonin
		if jonin then
			table.insert(
				entries,
				{ id = jonin, gun = butai.gun, butai = butai.id, shuryo = false, kyoten = butai.kyoten }
			)
		end
	end
	for _, gun in Gun.list do
		local shuryo = if gun == "Mikatagun" then stage.shuryo.mikatagun else stage.shuryo.tekigun
		local honjin = Haichi.honjinOf(haichi, gun)
		if shuryo and honjin then
			table.insert(entries, { id = shuryo, gun = gun, butai = nil, shuryo = true, kyoten = honjin })
		end
	end
	return entries
end

-- 軍ごとの能力値の補正。味方軍は体力・攻撃・防御に MikatagunScale を掛ける
function Jonin.modifiersOf(gun: Gun.Gun): { Stats.Modifier }
	if gun ~= "Mikatagun" then
		return {}
	end
	local scale = Config.Stats.MikatagunScale
	return {
		{ stat = "MaxHealth", multiply = scale },
		{ stat = "Attack", multiply = scale },
		{ stat = "Defense", multiply = scale },
	}
end

-- 能力値。modifiers は支配エリアの補正を除いた補正、shihaiArea は自分の軍の支配エリアの中か
local function statsOf(shuryo: boolean, modifiers: { Stats.Modifier }, shihaiArea: boolean): Stats.Values
	local list = table.clone(modifiers)
	for _, modifier in ShihaiArea.modifiersOf(shihaiArea) do
		table.insert(list, modifier)
	end
	return Stats.compute(Stats.npcBaseOf(shuryo), list)
end

-- 開始時の上忍か首領を作る。体力は最大の体力から始める。支配エリアの外にいるものとして作る。
-- partySize は出撃したときのパーティーの人数（省くと 1）。敵軍は人数で体力の最大を上げる
function Jonin.new(entry: Entry, position: Point, partySize: number?): Jonin
	local character = Characters.get(entry.id)
	local modifiers = Jonin.modifiersOf(entry.gun)
	for _, modifier in PartySize.modifiersOf(entry.gun, partySize or 1) do
		table.insert(modifiers, modifier)
	end
	local stats = statsOf(entry.shuryo, modifiers, false)
	return {
		id = entry.id,
		displayName = if character then character.displayName else entry.id,
		gun = entry.gun,
		stats = stats,
		modifiers = modifiers,
		shihaiArea = false,
		health = stats.MaxHealth,
		butai = entry.butai,
		shuryo = entry.shuryo,
		kyoten = entry.kyoten,
		position = { x = position.x, z = position.z },
	}
end

function Jonin.isDefeated(jonin: Jonin): boolean
	return jonin.health <= 0
end

-- 体力を value にする（0 から最大の体力までに収める）。これで倒れたら true（倒れていた上忍は false）
function Jonin.setHealth(jonin: Jonin, value: number): boolean
	local wasDefeated = Jonin.isDefeated(jonin)
	jonin.health = math.clamp(value, 0, jonin.stats.MaxHealth)
	return not wasDefeated and Jonin.isDefeated(jonin)
end

-- 自分の軍の支配エリアの中かを書き換え、能力値を求め直す。変わったら true。
-- 支配エリアの補正は体力の最大を変えないので、今の体力はそのまま
function Jonin.setShihaiArea(jonin: Jonin, inside: boolean): boolean
	if jonin.shihaiArea == inside then
		return false
	end
	jonin.shihaiArea = inside
	jonin.stats = statsOf(jonin.shuryo, jonin.modifiers, inside)
	return true
end

return Jonin
