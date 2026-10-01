--!strict
local Characters = require("./Characters")
local KaoGraphic = require("./KaoGraphic")
local RemoteSchema = require("./RemoteSchema")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

-- PNG の頭（IHDR）から幅・高さ・色の形式を読む。色の形式 6 は RGBA（透過あり）
local function pngHeader(data: string): (number, number, number)
	expect(string.sub(data, 1, 8)).toBe("\137PNG\r\n\26\n")
	expect(string.sub(data, 13, 16)).toBe("IHDR")
	local width, height = string.unpack(">I4>I4", data, 17)
	local colorType = string.byte(data, 26)
	return width, height, colorType
end

test(
	"登録したキャラクターは定義表にあり、5つの表情すべてに正の整数のアセット ID がある",
	function()
		local count = 0
		for characterId, images in KaoGraphic.definitions do
			count += 1
			expect(Characters.get(characterId) ~= nil).toBe(true)
			for _, hyojo in RemoteSchema.hyojo do
				local id = images[hyojo]
				expect(type(id) == "number" and id > 0 and id == math.floor(id)).toBe(true)
			end
		end
		expect(count > 0).toBe(true)
	end
)

test("M1 の操作キャラクター4人と味方軍の首領ハヤテの5表情を引ける", function()
	for _, characterId in { "Jin", "Torika", "Sekishusai", "KanaOni", "Hayate" } do
		for _, hyojo in RemoteSchema.hyojo do
			local id = KaoGraphic.get(characterId, hyojo) :: number
			expect(KaoGraphic.imageOf(characterId, hyojo)).toBe(`rbxassetid://{id}`)
		end
	end
end)

test("アセット ID は表情どうし、キャラクターどうしで重ならない", function()
	local seen: { [number]: string } = {}
	for characterId, images in KaoGraphic.definitions do
		for _, hyojo in RemoteSchema.hyojo do
			local id = images[hyojo]
			expect(seen[id]).toBe(nil)
			seen[id] = `{characterId}.{hyojo}`
		end
	end
end)

test("登録表に無いキャラクターは nil で、画面は顔の枠を出さない", function()
	expect(KaoGraphic.get("Nobody", "Tsujo")).toBe(nil)
	expect(KaoGraphic.imageOf("Nobody", "Tsujo")).toBe(nil)
end)

test("登録した画像は assets/faces にあり、512 × 512 の透過ありの PNG", function()
	for characterId in KaoGraphic.definitions do
		for _, hyojo in RemoteSchema.hyojo do
			local path = KaoGraphic.pathOf(characterId, hyojo)
			local data = testkit.readFile(path)
			expect(data ~= nil).toBe(true)
			local width, height, colorType = pngHeader(data :: string)
			expect(width).toBe(KaoGraphic.SIZE)
			expect(height).toBe(KaoGraphic.SIZE)
			expect(colorType).toBe(6)
		end
	end
end)

test("画像の置き場所はキャラクター ID と表情の小文字", function()
	expect(KaoGraphic.pathOf("KanaOni", "Yorokobi")).toBe("assets/faces/kanaoni/yorokobi.png")
end)
