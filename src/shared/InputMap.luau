--!strict
-- 操作と入力の対応表。PC（キーボードとマウス）とゲームパッドの割り当てと、画面に出すボタン表記を持つ。
-- 割り当てを変えるときは、この表だけを直す。InputController と HUD の操作の案内はここから引く。
--
-- - 入力は "KeyCode.<名前>" か "UserInputType.<名前>" の文字列で書く（Lune のテストで読むため）
-- - 右クリック（UserInputType.MouseButton2）は右ドラッグのカメラの回転と両立させるため、
--   押して離したとき（ドラッグしなかったとき）に1回だけ送る。押している間を使う操作には割り当てない
-- - ジャンプは Roblox 標準の割り当て（Space と A）のまま使うので、ここには置かない
-- - 緊急回避はボタンではなく、ガード中の方向入力で出す

export type Labels = {
	Keyboard: string,
	Gamepad: string,
}

export type Binding = {
	keyboard: { string },
	gamepad: { string },
	-- 画面に出すボタン表記
	labels: Labels,
}

-- 押している間の扱い。Press は押したときに1回、Repeat は押している間くり返し、Hold は押したときと離したとき
export type Trigger = "Press" | "Repeat" | "Hold"

export type Operation = Binding & {
	trigger: Trigger,
}

local InputMap = {}

-- Z と X は、矢印キーで動く人と、マウスのクリックがタッチとして届く環境（Studio のテストプレイなど）向け
InputMap.Attack = {
	trigger = "Repeat",
	keyboard = { "UserInputType.MouseButton1", "KeyCode.Z" },
	gamepad = { "KeyCode.ButtonX" },
	labels = { Keyboard = "左クリック・Z", Gamepad = "X" },
} :: Operation

InputMap.ChargeKogeki = {
	trigger = "Press",
	keyboard = { "UserInputType.MouseButton2", "KeyCode.X", "KeyCode.E" },
	gamepad = { "KeyCode.ButtonY" },
	labels = { Keyboard = "右クリック・X・E", Gamepad = "Y" },
} :: Operation

InputMap.Guard = {
	trigger = "Hold",
	keyboard = { "KeyCode.LeftShift", "KeyCode.RightShift" },
	gamepad = { "KeyCode.ButtonL1" },
	labels = { Keyboard = "Shift", Gamepad = "L1" },
} :: Operation

InputMap.Ougi = {
	trigger = "Press",
	keyboard = { "KeyCode.Q" },
	gamepad = { "KeyCode.ButtonB" },
	labels = { Keyboard = "Q", Gamepad = "B" },
} :: Operation

-- 秘計の枚ごとの割り当て。何枚目の枚かは配列の番号
InputMap.Hikei = {
	{
		keyboard = { "KeyCode.One" },
		gamepad = { "KeyCode.DPadLeft" },
		labels = { Keyboard = "1", Gamepad = "十字キー左" },
	},
	{
		keyboard = { "KeyCode.Two" },
		gamepad = { "KeyCode.DPadUp" },
		labels = { Keyboard = "2", Gamepad = "十字キー上" },
	},
	{
		keyboard = { "KeyCode.Three" },
		gamepad = { "KeyCode.DPadRight" },
		labels = { Keyboard = "3", Gamepad = "十字キー右" },
	},
} :: { Binding }

-- イベントシーンのスキップ。再生中だけ受け付け、押したら取り消せない。
-- Space と A は標準のジャンプと重なるので使わず、左手で押せる F と、戦闘で使わない R1 にする
InputMap.Skip = {
	trigger = "Press",
	keyboard = { "KeyCode.F" },
	gamepad = { "KeyCode.ButtonR1" },
	labels = { Keyboard = "F", Gamepad = "R1" },
} :: Operation

-- ジャンプと秘計の表記。ジャンプは Roblox 標準の割り当てなので表記だけを持つ。秘計は枚をまとめて出す
InputMap.JumpLabels = { Keyboard = "Space", Gamepad = "A" } :: Labels
InputMap.HikeiLabels = { Keyboard = "1〜3", Gamepad = "十字キー" } :: Labels

export type Hint = {
	name: string,
	labels: Labels,
}

-- 画面の操作の案内。設計のボタン表と同じ順に、戦闘の操作の名前とボタン表記を並べる（スキップはイベントシーンの画面に出す）
function InputMap.hints(): { Hint }
	return {
		{ name = "通常攻撃", labels = InputMap.Attack.labels },
		{ name = "チャージ攻撃", labels = InputMap.ChargeKogeki.labels },
		{ name = "ジャンプ", labels = InputMap.JumpLabels },
		{ name = "ガード", labels = InputMap.Guard.labels },
		{ name = "奥義", labels = InputMap.Ougi.labels },
		{ name = "秘計", labels = InputMap.HikeiLabels },
	}
end

-- 入力の文字列を Enum の種類と名前に分ける。形が違えば nil
function InputMap.parse(input: string): (("KeyCode" | "UserInputType")?, string?)
	local kind, name = string.match(input, "^(%a+)%.(%w+)$")
	if kind == "KeyCode" or kind == "UserInputType" then
		return kind :: any, name
	end
	return nil, nil
end

-- 割り当てのすべての入力を、操作の名前と一緒に列挙する（テストと重なりの確認に使う）
function InputMap.all(): { { name: string, device: "keyboard" | "gamepad", input: string } }
	local result = {}
	local function add(name: string, binding: Binding)
		for _, input in binding.keyboard do
			table.insert(result, { name = name, device = "keyboard" :: "keyboard", input = input })
		end
		for _, input in binding.gamepad do
			table.insert(result, { name = name, device = "gamepad" :: "gamepad", input = input })
		end
	end
	add("Attack", InputMap.Attack)
	add("ChargeKogeki", InputMap.ChargeKogeki)
	add("Guard", InputMap.Guard)
	add("Ougi", InputMap.Ougi)
	for slot, binding in InputMap.Hikei do
		add(`Hikei{slot}`, binding)
	end
	add("Skip", InputMap.Skip)
	return result
end

return InputMap
