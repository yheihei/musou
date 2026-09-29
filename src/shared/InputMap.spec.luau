--!strict
local Hikei = require("./Hikei")
local InputMap = require("./InputMap")
local testkit = require("@testkit")

local test, expect = testkit.test, testkit.expect

test("入力はすべて KeyCode か UserInputType の名前で書く", function()
	for _, entry in InputMap.all() do
		local kind, name = InputMap.parse(entry.input)
		expect(kind ~= nil and name ~= nil).toBe(true)
	end
	expect(InputMap.parse("E")).toBe(nil)
	expect(InputMap.parse("Enum.KeyCode.E")).toBe(nil)
end)

test("どの操作にも PC とゲームパッドの入力と表記がある", function()
	local bindings = { InputMap.Attack, InputMap.ChargeKogeki, InputMap.Guard, InputMap.Ougi }
	for _, binding in InputMap.Hikei do
		table.insert(bindings, binding :: any)
	end
	for _, binding in bindings do
		expect(#binding.keyboard > 0).toBe(true)
		expect(#binding.gamepad > 0).toBe(true)
		expect(#binding.labels.Keyboard > 0).toBe(true)
		expect(#binding.labels.Gamepad > 0).toBe(true)
	end
end)

test("1つの入力を2つの操作に割り当てない", function()
	local owner: { [string]: string } = {}
	local duplicates = {}
	for _, entry in InputMap.all() do
		if owner[entry.input] and owner[entry.input] ~= entry.name then
			table.insert(duplicates, entry.input)
		end
		owner[entry.input] = entry.name
	end
	expect(duplicates).toEqual({})
end)

test(
	"PC の入力はキーボードとマウス、ゲームパッドの入力はゲームパッドのボタン",
	function()
		for _, entry in InputMap.all() do
			local kind, name = InputMap.parse(entry.input)
			local isGamepad = kind == "KeyCode"
				and (string.sub(name :: string, 1, 6) == "Button" or string.sub(name :: string, 1, 4) == "DPad")
			expect(isGamepad).toBe(entry.device == "gamepad")
		end
	end
)

test("移動・ジャンプ・カメラの標準の入力は使わない", function()
	local reserved = {
		"KeyCode.W",
		"KeyCode.A",
		"KeyCode.S",
		"KeyCode.D",
		"KeyCode.Space",
		"KeyCode.ButtonA",
		"KeyCode.Thumbstick1",
		"KeyCode.Thumbstick2",
		"KeyCode.ButtonSelect",
		"KeyCode.ButtonStart",
	}
	for _, entry in InputMap.all() do
		expect(table.find(reserved, entry.input)).toBe(nil)
	end
end)

test("右クリックは押したときに1回送る操作にだけ割り当てる", function()
	local bindings = {
		Attack = InputMap.Attack,
		ChargeKogeki = InputMap.ChargeKogeki,
		Guard = InputMap.Guard,
		Ougi = InputMap.Ougi,
	}
	for _, operation in bindings do
		if table.find(operation.keyboard, "UserInputType.MouseButton2") then
			expect(operation.trigger).toBe("Press")
		end
	end
	for _, binding in InputMap.Hikei do
		expect(table.find(binding.keyboard, "UserInputType.MouseButton2")).toBe(nil)
	end
end)

test("秘計のボタンの数は持ち込みの上限枚数と同じ", function()
	expect(#InputMap.Hikei).toBe(Hikei.MOCHIKOMI_MAX)
end)

test("設計のボタン表どおりの割り当て", function()
	expect(InputMap.Attack.keyboard).toEqual({ "UserInputType.MouseButton1", "KeyCode.Z" })
	expect(InputMap.Attack.gamepad).toEqual({ "KeyCode.ButtonX" })
	expect(InputMap.ChargeKogeki.keyboard).toEqual({ "UserInputType.MouseButton2", "KeyCode.X", "KeyCode.E" })
	expect(InputMap.ChargeKogeki.gamepad).toEqual({ "KeyCode.ButtonY" })
	expect(InputMap.Guard.gamepad).toEqual({ "KeyCode.ButtonL1" })
	expect(InputMap.Ougi.keyboard).toEqual({ "KeyCode.Q" })
	expect(InputMap.Ougi.gamepad).toEqual({ "KeyCode.ButtonB" })
	expect(InputMap.Hikei[1].gamepad).toEqual({ "KeyCode.DPadLeft" })
	expect(InputMap.Hikei[2].gamepad).toEqual({ "KeyCode.DPadUp" })
	expect(InputMap.Hikei[3].gamepad).toEqual({ "KeyCode.DPadRight" })
end)

test(
	"画面の操作の案内は設計のボタン表と同じ順で、どれにも PC とゲームパッドの表記がある",
	function()
		local names = {}
		for _, hint in InputMap.hints() do
			table.insert(names, hint.name)
			expect(#hint.labels.Keyboard > 0).toBe(true)
			expect(#hint.labels.Gamepad > 0).toBe(true)
		end
		expect(names).toEqual({ "通常攻撃", "チャージ攻撃", "ジャンプ", "ガード", "奥義", "秘計" })
	end
)

test("秘計の案内の表記は、枚ごとの表記と合っている", function()
	expect(InputMap.HikeiLabels.Keyboard).toBe(
		`{InputMap.Hikei[1].labels.Keyboard}〜{InputMap.Hikei[#InputMap.Hikei].labels.Keyboard}`
	)
	for _, binding in InputMap.Hikei do
		expect(string.find(binding.labels.Gamepad, InputMap.HikeiLabels.Gamepad, 1, true) ~= nil).toBe(true)
	end
end)
