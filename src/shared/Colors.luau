--!strict
-- 軍・クラン・キャラクターの色。画面、下忍、仮置きの見た目は色をここから引く。
-- Color3 を使うので、Lune のテストからは読まない。

local Characters = require("./Characters")

local Colors = {}

-- 味方軍と敵軍。ミニマップや HUD で軍を見分ける
Colors.Gun = {
	Mikatagun = Color3.fromRGB(60, 130, 230),
	Tekigun = Color3.fromRGB(220, 60, 50),
}

-- クランの色。下忍の見た目など、クランを見分けるところで使う
Colors.Clan = {
	Iga = Color3.fromRGB(40, 60, 130),
	Koga = Color3.fromRGB(80, 130, 60),
	Fuma = Color3.fromRGB(100, 50, 120),
	Saika = Color3.fromRGB(200, 120, 40),
} :: { [Characters.ClanId]: Color3 }

-- キャラクターの色。仮置きの見た目の色分けに使う。NINJAMCP のイラストの背景色に合わせた
Colors.Character = {
	Jin = Color3.fromRGB(139, 30, 35),
	Torika = Color3.fromRGB(106, 46, 122),
	Sekishusai = Color3.fromRGB(43, 138, 150),
	KanaOni = Color3.fromRGB(190, 100, 45),
	Hayate = Color3.fromRGB(52, 140, 90),
	-- 試験用の NPC。敵軍は風魔に近い紫、味方軍は伊賀に近い青
	ShikenShuryo = Color3.fromRGB(90, 40, 100),
	ShikenJonin1 = Color3.fromRGB(130, 70, 140),
	ShikenJonin2 = Color3.fromRGB(150, 95, 165),
	ShikenJonin3 = Color3.fromRGB(70, 110, 180),
} :: { [string]: Color3 }

return Colors
