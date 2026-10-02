--!strict
-- 名前を持つ上忍と首領のデータ。上忍は部隊を率いて部隊とともに動き、首領は本陣にとどまる。
-- 開始時の顔ぶれは、配置の構成（Haichi.luau の部隊の上忍）とステージの定義（Stages.luau の両軍の首領）から決める。
-- 能力値は Config.luau の Stats 節（上忍は Jonin、首領は Shuryo）に、補正を Stats.compute で足して求める。
-- 体力が 0 になると倒れる。率いていた部隊は残し、士気だけを下げる（Butai.loseJonin）。
-- 位置は水平の (x, z) で持つ。Roblox の API は使わない。

local Characters = require("./Characters")
local Gun = require("./Gun")
local Haichi = require("./Haichi")
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
	stats: Stats.Values,
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

-- 開始時の上忍か首領を作る。体力は最大の体力から始める
function Jonin.new(entry: Entry, position: Point): Jonin
	local character = Characters.get(entry.id)
	local stats = Stats.compute(Stats.npcBaseOf(entry.shuryo), {})
	return {
		id = entry.id,
		displayName = if character then character.displayName else entry.id,
		gun = entry.gun,
		stats = stats,
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

return Jonin
