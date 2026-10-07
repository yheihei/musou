--!strict
-- ステージの配置の構成（ADR 0006）。拠点の種類と開始時の軍、拠点どうしのつながり、部隊（率いる上忍・方針・開始時の拠点）を
-- ステージ ID で引く。位置と形はプレースの目印に置く。試験用ステージだけは、目印の位置もここに持つ。
-- 首領は Stages.luau の両軍の首領を引き、本陣から出す。部隊の兵数は Config.luau の Butai 節にある。
-- 敵軍の上忍と首領が持ち込む秘計も、キャラクター ID ごとにここに持つ（味方軍の上忍と首領は秘計を持ち込まない）。
-- 構成の整合の検証と、構成とプレースの目印の突き合わせもここに置く。
-- 落石地点と大火計地域は目印だけで完結させ（ADR 0006）、参照する拠点とつながりの有無を読み込み時にここで確かめる。
-- Roblox の API は使わない。

local Characters = require("./Characters")
local Config = require("./Config")
local Gun = require("./Gun")
local Heitansen = require("./Heitansen")
local Hikei = require("./Hikei")
local Stages = require("./Stages")

export type Kyoten = {
	id: string,
	-- 本陣か。本陣でなければ通常拠点
	honjin: boolean,
	-- 開始時の所属の軍
	gun: Gun.Gun,
}

export type Tsunagari = {
	-- 両端の拠点 ID
	kyotenA: string,
	kyotenB: string,
}

-- 上忍が部隊を率いて目指すこと
export type Hoshin = "Koryaku" | "Boei" | "Kyuen"

export type Butai = {
	id: string,
	gun: Gun.Gun,
	-- 率いる上忍のキャラクター ID。率いる上忍のいない部隊（本陣の守備など）は nil
	jonin: string?,
	hoshin: Hoshin,
	-- 開始時にいる拠点
	kyoten: string,
}

-- 試験用ステージの目印の位置。区画の中心からのスタッドで、X は東、Z は南が +
export type KyotenIchi = { x: number, z: number, sizeX: number, sizeZ: number }
export type Keiyuten = { x: number, z: number }
export type TsunagariIchi = {
	kyotenA: string,
	kyotenB: string,
	-- kyotenA から kyotenB へたどる順の経由点
	keiyuten: { Keiyuten },
}
-- 落石地点。kyotenA と kyotenB は塞ぐ区間（つながり）の両端の拠点
export type RakusekiIchi = { id: string, kyotenA: string, kyotenB: string, x: number, z: number }
-- 大火計地域。sizeX と sizeZ は範囲の大きさ
export type DaikakeiIchi = { id: string, x: number, z: number, sizeX: number, sizeZ: number }
-- イベントシーンのカメラのショット。カメラの位置（y は地面からの高さ）と、見る先（lookY は地面からの高さ）
export type ShotIchi = { x: number, y: number, z: number, lookX: number, lookY: number, lookZ: number }
-- イベントシーンの役者の立ち位置と向き。facing は北から時計回りの度（北は z の -）
export type YakushaIchi = { x: number, z: number, facing: number }
export type EventSceneIchi = {
	-- ショットの名前から引くカメラ
	camera: { [string]: ShotIchi },
	-- 役者の名前（キャラクター ID か Player1〜Player4）から引く立ち位置
	yakusha: { [string]: YakushaIchi },
}
export type ShikenMejirushi = {
	-- 区画の大きさ（プレースの区画の範囲の目印と同じ値にする）
	kukakuSizeX: number,
	kukakuSizeZ: number,
	kyoten: { [string]: KyotenIchi },
	tsunagari: { TsunagariIchi },
	rakusekiChiten: { RakusekiIchi },
	daikakeiChiiki: { DaikakeiIchi },
	-- シーン ID から引くイベントシーンの目印
	eventScene: { [string]: EventSceneIchi }?,
}

-- プレースから読んだ落石地点の目印。Attribute の KyotenA・KyotenB が無ければ nil
export type RakusekiMejirushi = { id: string, kyotenA: string?, kyotenB: string? }

export type Haichi = {
	stageId: string,
	kyoten: { Kyoten },
	tsunagari: { Tsunagari },
	butai: { Butai },
	-- 敵軍の上忍と首領が持ち込む秘計（枚の順）。キャラクター ID から引く。持ち込まない上忍と首領は入れない
	mochikomi: { [string]: { string } }?,
	-- 目印の位置をコードに持つ試験用ステージだけにある
	shikenMejirushi: ShikenMejirushi?,
}

local Haichi = {}

Haichi.hoshinList = { "Koryaku", "Boei", "Kyuen" } :: { Hoshin }

local definitions: { [string]: Haichi } = {
	-- 試験用ステージ。南に味方軍の本陣、北に敵軍の本陣を置き、中央・東・西に通常拠点を置く。
	-- 東は中央とだけつながるので、中央を制圧すると敵軍の東が孤立する
	Test = {
		stageId = "Test",
		kyoten = {
			{ id = "MikataHonjin", honjin = true, gun = "Mikatagun" },
			{ id = "Nishi", honjin = false, gun = "Mikatagun" },
			{ id = "Chuo", honjin = false, gun = "Tekigun" },
			{ id = "Higashi", honjin = false, gun = "Tekigun" },
			{ id = "TekiHonjin", honjin = true, gun = "Tekigun" },
		},
		tsunagari = {
			{ kyotenA = "MikataHonjin", kyotenB = "Nishi" },
			{ kyotenA = "MikataHonjin", kyotenB = "Chuo" },
			{ kyotenA = "Nishi", kyotenB = "Chuo" },
			{ kyotenA = "Chuo", kyotenB = "Higashi" },
			{ kyotenA = "Chuo", kyotenB = "TekiHonjin" },
			{ kyotenA = "Nishi", kyotenB = "TekiHonjin" },
		},
		butai = {
			{ id = "Mikata1", gun = "Mikatagun", jonin = "ShikenJonin3", hoshin = "Koryaku", kyoten = "Nishi" },
			{ id = "Mikata2", gun = "Mikatagun", jonin = nil, hoshin = "Boei", kyoten = "MikataHonjin" },
			{ id = "Teki1", gun = "Tekigun", jonin = "ShikenJonin1", hoshin = "Koryaku", kyoten = "Chuo" },
			{ id = "Teki2", gun = "Tekigun", jonin = "ShikenJonin2", hoshin = "Boei", kyoten = "Higashi" },
			{ id = "Teki3", gun = "Tekigun", jonin = nil, hoshin = "Boei", kyoten = "TekiHonjin" },
		},
		-- 秘計の判断を確かめる持ち込み。試験の上忍1 は Teki1 が交戦したら鬼神化、味方軍の上忍が近づいたら挑発、
		-- 区間が味方軍の兵站線に入っている落石地点に近づいたら落石、試験の上忍2 は鬼神化したプレイヤーが近づいたら大喝、
		-- 東（敵軍の兵站線の末端）で兵糧庫、プレイヤーが東に近づいたら爆破罠、
		-- 試験の首領は体力が減ったら鬼神化、本陣に味方軍の部隊かプレイヤーが迫ったら伏兵を使う
		mochikomi = {
			ShikenJonin1 = { "Kishinka", "Chohatsu", "Rakuseki" },
			ShikenJonin2 = { "Daikatsu", "Hyoroko", "Bakuhawana" },
			ShikenShuryo = { "Kishinka", "Daikatsu", "Fukuhei" },
		},
		shikenMejirushi = {
			kukakuSizeX = 800,
			kukakuSizeZ = 800,
			kyoten = {
				MikataHonjin = { x = 0, z = 280, sizeX = 110, sizeZ = 110 },
				Nishi = { x = -220, z = 60, sizeX = 80, sizeZ = 80 },
				Chuo = { x = 0, z = 0, sizeX = 80, sizeZ = 80 },
				Higashi = { x = 220, z = -60, sizeX = 80, sizeZ = 80 },
				TekiHonjin = { x = 0, z = -280, sizeX = 110, sizeZ = 110 },
			},
			tsunagari = {
				{ kyotenA = "MikataHonjin", kyotenB = "Nishi", keiyuten = { { x = -150, z = 220 } } },
				{ kyotenA = "MikataHonjin", kyotenB = "Chuo", keiyuten = {} },
				{ kyotenA = "Nishi", kyotenB = "Chuo", keiyuten = {} },
				{ kyotenA = "Chuo", kyotenB = "Higashi", keiyuten = {} },
				{ kyotenA = "Chuo", kyotenB = "TekiHonjin", keiyuten = {} },
				{
					kyotenA = "Nishi",
					kyotenB = "TekiHonjin",
					keiyuten = { { x = -260, z = -100 }, { x = -180, z = -240 } },
				},
			},
			-- 中央と東の間を塞ぐと敵軍の東が、本陣と西の間を塞ぐと味方軍の西が孤立する
			rakusekiChiten = {
				{ id = "R1", kyotenA = "Chuo", kyotenB = "Higashi", x = 110, z = -30 },
				{ id = "R2", kyotenA = "MikataHonjin", kyotenB = "Nishi", x = -150, z = 220 },
			},
			-- 中央から敵軍の本陣へ上る道と、味方軍の本陣の北の口の前
			daikakeiChiiki = {
				{ id = "D1", x = 0, z = -140, sizeX = 60, sizeZ = 80 },
				{ id = "D2", x = 0, z = 180, sizeX = 100, sizeZ = 40 },
			},
			-- 試験用のシーン（EventScenes.luau の Shiken）。出撃地点（z = 200）の北で、ハヤテと1人目のプレイヤーが
			-- 北を向いて並び、北から試験の上忍1が歩いてくる
			eventScene = {
				Shiken = {
					camera = {
						Zenkei = { x = 24, y = 16, z = 198, lookX = 0, lookY = 3, lookZ = 168 },
						Hayate = { x = -5, y = 6, z = 174, lookX = -5, lookY = 5, lookZ = 182 },
						Teki = { x = 0, y = 6, z = 171, lookX = 0, lookY = 5, lookZ = 162 },
						Player = { x = 5, y = 6, z = 174, lookX = 5, lookY = 5, lookZ = 182 },
					},
					yakusha = {
						Hayate = { x = -5, z = 182, facing = 0 },
						Player1 = { x = 5, z = 182, facing = 0 },
						ShikenJonin1 = { x = 0, z = 150, facing = 180 },
					},
				},
			},
		},
	},
}

Haichi.definitions = definitions

-- ステージの配置の構成。まだ無いステージは nil
function Haichi.get(stageId: string): Haichi?
	return definitions[stageId]
end

-- つながりを向きに関係なく見分けるためのキー
function Haichi.pairKey(kyotenA: string, kyotenB: string): string
	if kyotenA < kyotenB then
		return `{kyotenA}-{kyotenB}`
	end
	return `{kyotenB}-{kyotenA}`
end

-- 軍の本陣の拠点 ID。無ければ nil
function Haichi.honjinOf(haichi: Haichi, gun: Gun.Gun): string?
	for _, kyoten in haichi.kyoten do
		if kyoten.honjin and kyoten.gun == gun then
			return kyoten.id
		end
	end
	return nil
end

-- 部隊の開始時の兵数。Config.luau の Butai 節に無ければ nil
function Haichi.heisuOf(stageId: string, butaiId: string): number?
	local stage = Config.Butai.Heisu[stageId]
	return if stage then stage[butaiId] else nil
end

-- 敵軍の上忍と首領が持ち込む秘計を、キャラクター ID から引く表で返す（表は写し）。配置の構成か持ち込みが無ければ空
function Haichi.mochikomiOf(stageId: string): { [string]: { string } }
	local haichi = definitions[stageId]
	local result: { [string]: { string } } = {}
	for id, ids in (if haichi then haichi.mochikomi else nil) or {} do
		result[id] = table.clone(ids)
	end
	return result
end

local function clanOf(stage: Stages.Stage, gun: Gun.Gun): Characters.ClanId
	return if gun == "Mikatagun" then stage.clan else stage.tekigun
end

local function checkShikenMejirushi(haichi: Haichi, mejirushi: ShikenMejirushi, problems: { string })
	local halfX, halfZ = mejirushi.kukakuSizeX / 2, mejirushi.kukakuSizeZ / 2
	local function inside(x: number, z: number, sizeX: number, sizeZ: number): boolean
		return x - sizeX / 2 >= -halfX and x + sizeX / 2 <= halfX and z - sizeZ / 2 >= -halfZ and z + sizeZ / 2 <= halfZ
	end
	local ids: { [string]: boolean } = {}
	for _, kyoten in haichi.kyoten do
		ids[kyoten.id] = true
		local ichi = mejirushi.kyoten[kyoten.id]
		if not ichi then
			table.insert(problems, `拠点 {kyoten.id} の目印の位置が無い`)
		elseif not inside(ichi.x, ichi.z, ichi.sizeX, ichi.sizeZ) then
			table.insert(problems, `拠点 {kyoten.id} の目印が区画の範囲からはみ出す`)
		end
	end
	for id in mejirushi.kyoten do
		if not ids[id] then
			table.insert(problems, `目印の位置の拠点 {id} は構成に無い`)
		end
	end
	local defined: { [string]: boolean } = {}
	for _, tsunagari in haichi.tsunagari do
		defined[Haichi.pairKey(tsunagari.kyotenA, tsunagari.kyotenB)] = true
	end
	local seen: { [string]: boolean } = {}
	for _, ichi in mejirushi.tsunagari do
		local key = Haichi.pairKey(ichi.kyotenA, ichi.kyotenB)
		seen[key] = true
		if not defined[key] then
			table.insert(problems, `目印の位置のつながり {key} は構成に無い`)
		end
		for _, point in ichi.keiyuten do
			if not inside(point.x, point.z, 0, 0) then
				table.insert(problems, `つながり {key} の経由点が区画の範囲からはみ出す`)
			end
		end
	end
	for key in defined do
		if not seen[key] then
			table.insert(problems, `つながり {key} の目印の位置が無い`)
		end
	end
	local rakuseki: { RakusekiMejirushi } = {}
	for _, chiten in mejirushi.rakusekiChiten do
		table.insert(rakuseki, { id = chiten.id, kyotenA = chiten.kyotenA, kyotenB = chiten.kyotenB })
		if not inside(chiten.x, chiten.z, 0, 0) then
			table.insert(problems, `落石地点 {chiten.id} が区画の範囲からはみ出す`)
		end
	end
	local _, rakusekiProblems = Haichi.checkRakusekiChiten(haichi, rakuseki)
	table.move(rakusekiProblems, 1, #rakusekiProblems, #problems + 1, problems)
	local daikakeiIds = {}
	for _, chiiki in mejirushi.daikakeiChiiki do
		table.insert(daikakeiIds, chiiki.id)
		if not inside(chiiki.x, chiiki.z, chiiki.sizeX, chiiki.sizeZ) then
			table.insert(problems, `大火計地域 {chiiki.id} が区画の範囲からはみ出す`)
		end
	end
	local _, daikakeiProblems = Haichi.checkDaikakeiChiiki(daikakeiIds)
	table.move(daikakeiProblems, 1, #daikakeiProblems, #problems + 1, problems)
	for sceneId, scene in mejirushi.eventScene or {} do
		for name, shot in scene.camera do
			if not inside(shot.x, shot.z, 0, 0) or not inside(shot.lookX, shot.lookZ, 0, 0) then
				table.insert(
					problems,
					`イベントシーン {sceneId} のカメラ {name} が区画の範囲からはみ出す`
				)
			end
		end
		for name, ichi in scene.yakusha do
			if not inside(ichi.x, ichi.z, 0, 0) then
				table.insert(
					problems,
					`イベントシーン {sceneId} の役者 {name} が区画の範囲からはみ出す`
				)
			end
		end
	end
end

-- 向き（北から時計回りの度）の水平の向き。北は z の -、東は x の +
function Haichi.facingOf(degrees: number): (number, number)
	local angle = math.rad(degrees)
	return math.sin(angle), -math.cos(angle)
end

-- 落石地点の目印を確かめ、使える地点の ID と、問題を日本語の文で返す。
-- ID の重複（2つ目からは使わない）、両端の拠点の Attribute の欠け、構成に無い拠点、つながりで結ばれていない区間を見つける
function Haichi.checkRakusekiChiten(haichi: Haichi, chiten: { RakusekiMejirushi }): ({ [string]: boolean }, { string })
	local usable: { [string]: boolean } = {}
	local problems: { string } = {}
	local kyotenIds: { [string]: boolean } = {}
	for _, kyoten in haichi.kyoten do
		kyotenIds[kyoten.id] = true
	end
	local connected: { [string]: boolean } = {}
	for _, tsunagari in haichi.tsunagari do
		connected[Haichi.pairKey(tsunagari.kyotenA, tsunagari.kyotenB)] = true
	end
	local seen: { [string]: boolean } = {}
	for _, item in chiten do
		if seen[item.id] then
			table.insert(problems, `落石地点 {item.id} が2つある`)
			continue
		end
		seen[item.id] = true
		local kyotenA, kyotenB = item.kyotenA, item.kyotenB
		if not kyotenA or not kyotenB then
			table.insert(problems, `落石地点 {item.id} に Attribute の KyotenA・KyotenB が無い`)
			continue
		end
		local ok = true
		for _, id in { kyotenA, kyotenB } do
			if not kyotenIds[id] then
				table.insert(problems, `落石地点 {item.id} の拠点 {id} が無い`)
				ok = false
			end
		end
		if ok and not connected[Haichi.pairKey(kyotenA, kyotenB)] then
			table.insert(
				problems,
				`落石地点 {item.id} の区間 {Haichi.pairKey(kyotenA, kyotenB)} はつながりで結ばれていない`
			)
			ok = false
		end
		if ok then
			usable[item.id] = true
		end
	end
	return usable, problems
end

-- 大火計地域の目印の ID を確かめ、使える地域の ID と、問題を日本語の文で返す（ID の重複は2つ目から使わない）
function Haichi.checkDaikakeiChiiki(ids: { string }): ({ [string]: boolean }, { string })
	local usable: { [string]: boolean } = {}
	local problems: { string } = {}
	for _, id in ids do
		if usable[id] then
			table.insert(problems, `大火計地域 {id} が2つある`)
		else
			usable[id] = true
		end
	end
	return usable, problems
end

-- 配置の構成の整合を確かめ、問題を日本語の文で返す。問題が無ければ空。
-- stage はその配置のステージの定義（首領と NPC と敵軍のクランを引く）
function Haichi.validate(haichi: Haichi, stage: Stages.Stage): { string }
	local problems: { string } = {}
	local byId: { [string]: Kyoten } = {}
	for _, kyoten in haichi.kyoten do
		if byId[kyoten.id] then
			table.insert(problems, `拠点 {kyoten.id} が2つある`)
		end
		byId[kyoten.id] = kyoten
	end
	for _, gun in Gun.list do
		local count = 0
		for _, kyoten in haichi.kyoten do
			if kyoten.honjin and kyoten.gun == gun then
				count += 1
			end
		end
		if count ~= 1 then
			table.insert(problems, `{gun} の本陣が {count} 個ある（1個にする）`)
		end
	end

	local seenPairs: { [string]: boolean } = {}
	for _, tsunagari in haichi.tsunagari do
		local key = Haichi.pairKey(tsunagari.kyotenA, tsunagari.kyotenB)
		if tsunagari.kyotenA == tsunagari.kyotenB then
			table.insert(problems, `つながり {key} の両端が同じ拠点`)
		end
		for _, id in { tsunagari.kyotenA, tsunagari.kyotenB } do
			if not byId[id] then
				table.insert(problems, `つながり {key} の拠点 {id} が無い`)
			end
		end
		if seenPairs[key] then
			table.insert(problems, `つながり {key} が2つある`)
		end
		seenPairs[key] = true
	end

	local butaiIds: { [string]: boolean } = {}
	local joninOf: { [string]: string } = {}
	for _, butai in haichi.butai do
		if butaiIds[butai.id] then
			table.insert(problems, `部隊 {butai.id} が2つある`)
		end
		butaiIds[butai.id] = true
		local kyoten = byId[butai.kyoten]
		if not kyoten then
			table.insert(problems, `部隊 {butai.id} の拠点 {butai.kyoten} が無い`)
		elseif kyoten.gun ~= butai.gun then
			table.insert(
				problems,
				`部隊 {butai.id}（{butai.gun}）が {kyoten.gun} の拠点 {kyoten.id} から始まる`
			)
		end
		if not table.find(Haichi.hoshinList, butai.hoshin) then
			table.insert(problems, `部隊 {butai.id} の方針 {butai.hoshin} は無い`)
		end
		local heisu = Haichi.heisuOf(haichi.stageId, butai.id)
		if not heisu or heisu <= 0 then
			table.insert(problems, `部隊 {butai.id} の兵数が Config.Butai.Heisu.{haichi.stageId} に無い`)
		end
		local jonin = butai.jonin
		if jonin then
			local character = Characters.get(jonin)
			if not character then
				table.insert(problems, `部隊 {butai.id} の上忍 {jonin} はキャラクターの定義表に無い`)
			else
				if character.playable then
					table.insert(problems, `部隊 {butai.id} の上忍 {jonin} は操作キャラクター`)
				end
				if character.clan ~= clanOf(stage, butai.gun) then
					table.insert(
						problems,
						`部隊 {butai.id} の上忍 {jonin} のクランが {butai.gun} のクランと違う`
					)
				end
			end
			if not table.find(stage.npcs, jonin) then
				table.insert(problems, `部隊 {butai.id} の上忍 {jonin} がステージの NPC に無い`)
			end
			if jonin == stage.shuryo.mikatagun or jonin == stage.shuryo.tekigun then
				table.insert(problems, `部隊 {butai.id} の上忍 {jonin} は首領（首領は本陣から出す）`)
			end
			if joninOf[jonin] then
				table.insert(problems, `上忍 {jonin} が部隊 {joninOf[jonin]} と {butai.id} を率いている`)
			end
			joninOf[jonin] = butai.id
		end
	end

	-- 秘計を持ち込めるのは敵軍の上忍と首領だけ。上限と重なりは持ち込みの検証（Hikei.checkMochikomi）で確かめる
	local tekigunIds: { [string]: boolean } = {}
	for _, butai in haichi.butai do
		local jonin = butai.jonin
		if butai.gun == "Tekigun" and jonin then
			tekigunIds[jonin] = true
		end
	end
	local tekigunShuryo = stage.shuryo.tekigun
	if tekigunShuryo then
		tekigunIds[tekigunShuryo] = true
	end
	local mochikomi = haichi.mochikomi or {}
	local mochikomiIds = {}
	for id in mochikomi do
		table.insert(mochikomiIds, id)
	end
	table.sort(mochikomiIds)
	for _, id in mochikomiIds do
		if not tekigunIds[id] then
			table.insert(problems, `秘計を持ち込む {id} は敵軍の上忍でも首領でもない`)
		end
		local reject = Hikei.checkMochikomi(mochikomi[id], {})
		if reject then
			table.insert(problems, `{id} の秘計の持ち込みを受け付けない（{reject}）`)
		end
	end

	local heitansenKyoten: { Heitansen.Kyoten } = {}
	for _, kyoten in haichi.kyoten do
		table.insert(heitansenKyoten, { id = kyoten.id, gun = kyoten.gun, honjin = kyoten.honjin })
	end
	local result = Heitansen.compute(heitansenKyoten, haichi.tsunagari)
	for _, gun in Gun.list do
		local isolated = {}
		for id in result[gun].isolated do
			table.insert(isolated, id)
		end
		table.sort(isolated)
		for _, id in isolated do
			table.insert(problems, `開始時に {gun} の拠点 {id} が孤立している`)
		end
	end

	local mejirushi = haichi.shikenMejirushi
	if mejirushi then
		checkShikenMejirushi(haichi, mejirushi, problems)
	end
	return problems
end

-- 構成とプレースの目印を突き合わせ、食い違いを日本語の文で返す。
-- kyotenNames は拠点の目印の名前、tsunagariPairs はつながりの目印のフォルダの両端
function Haichi.compareMejirushi(haichi: Haichi, kyotenNames: { string }, tsunagariPairs: { Tsunagari }): { string }
	local warnings: { string } = {}
	local placed: { [string]: boolean } = {}
	for _, name in kyotenNames do
		placed[name] = true
	end
	local defined: { [string]: boolean } = {}
	for _, kyoten in haichi.kyoten do
		defined[kyoten.id] = true
		if not placed[kyoten.id] then
			table.insert(warnings, `拠点 {kyoten.id} の目印が無い`)
		end
	end
	local extra = {}
	for name in placed do
		if not defined[name] then
			table.insert(extra, name)
		end
	end
	table.sort(extra)
	for _, name in extra do
		table.insert(warnings, `目印の拠点 {name} は構成に無い`)
	end

	local placedPairs: { [string]: boolean } = {}
	for _, pair in tsunagariPairs do
		placedPairs[Haichi.pairKey(pair.kyotenA, pair.kyotenB)] = true
	end
	local definedPairs: { [string]: boolean } = {}
	for _, tsunagari in haichi.tsunagari do
		local key = Haichi.pairKey(tsunagari.kyotenA, tsunagari.kyotenB)
		definedPairs[key] = true
		if not placedPairs[key] then
			table.insert(warnings, `つながり {key} の目印が無い（拠点の間をまっすぐ結ぶ）`)
		end
	end
	local extraPairs = {}
	for key in placedPairs do
		if not definedPairs[key] then
			table.insert(extraPairs, key)
		end
	end
	table.sort(extraPairs)
	for _, key in extraPairs do
		table.insert(warnings, `目印のつながり {key} は構成に無い`)
	end
	return warnings
end

return Haichi
