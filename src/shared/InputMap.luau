--!strict
-- 操作と入力の対応表。PC（キーボードとマウス）とゲームパッドの割り当てと、画面に出すボタン表記を持つ。
-- 割り当てを変えるときは、この表だけを直す。InputController と HUD の操作の案内はここから引く。
-- 戦闘の操作（all）と画面の操作（menuAll。タイトル画面・出撃前の画面・窓）に分ける。戦闘の操作は戦闘のフェーズの出撃メンバー
-- だけが送り、それ以外の間（ロビー・タイトル画面など）は割り当てを外して画面の操作に回す（InputController。#148）。
--
-- - 入力は "KeyCode.<名前>" か "UserInputType.<名前>" の文字列で書く（Lune のテストで読むため）
-- - 右クリック（UserInputType.MouseButton2）は右ドラッグのカメラの回転と両立させるため、
--   押して離したとき（ドラッグしなかったとき）に1回だけ送る。押している間を使う操作には割り当てない
-- - ジャンプは Roblox 標準の割り当て（Space と A）のまま使うので、ここには置かない
-- - 緊急回避はボタンではなく、ガード中の方向入力で出す
-- - スマホの戦闘の操作ボタンは TouchControlsController が出す（ここには置かない。ジャンプはスマホも標準のジャンプボタン）

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

-- 画面の操作。戦闘の操作の割り当てを外している間（戦闘のフェーズの外）だけ受け付けるので、戦闘の操作と同じボタンを使ってよい。
-- ゲームパッドの決定（選んだボタンを A で押す）と選ぶボタンの移動（スティックと十字キー）は Roblox 標準の画面の操作なので、
-- 決定は表記だけを持つ。START と SELECT は Roblox のメニューと画面の操作の切り替えに使われるので割り当てない

-- タイトル画面の「はじめる」。タイトル画面を出している間だけ受け付ける。画面のボタンのクリックとタッチのほか、Enter と、
-- ゲームパッドの A・B・X・Y のどれでも押せる（決定と思って押したボタンがどれでも進めるように。#148）。表記は A
InputMap.Hajimeru = {
	trigger = "Press",
	keyboard = { "KeyCode.Return", "KeyCode.KeypadEnter" },
	gamepad = { "KeyCode.ButtonA", "KeyCode.ButtonB", "KeyCode.ButtonX", "KeyCode.ButtonY" },
	labels = { Keyboard = "Enter", Gamepad = "A" },
} :: Operation

-- 決定。表記だけを持つ（押すのは Roblox 標準の画面の操作。マウスはクリック、ゲームパッドは選んだボタンを A）
InputMap.Kettei = {
	keyboard = {},
	gamepad = {},
	labels = { Keyboard = "クリック", Gamepad = "A" },
} :: Binding

-- 戻る。出撃前の画面では選ぶボタンを前の欄へ戻し、窓（特技ツリー）では閉じる。マウスでは画面のボタンで戻るので、ゲームパッドだけ
InputMap.Modoru = {
	trigger = "Press",
	keyboard = {},
	gamepad = { "KeyCode.ButtonB" },
	labels = { Keyboard = "", Gamepad = "B" },
} :: Operation

-- 出撃前の画面で、選ぶボタンを出撃ボタンへ移す（出撃は移した後に A で押す）。ゲームパッドだけ
InputMap.ShutsugekiHe = {
	trigger = "Press",
	keyboard = {},
	gamepad = { "KeyCode.ButtonY" },
	labels = { Keyboard = "", Gamepad = "Y" },
} :: Operation

-- 窓口の SetInputKind が書く Player の Attribute（"Keyboard"・"Gamepad"・"Touch"）。書いてある間、画面のボタン表記と
-- ゲームパッドで選ぶボタンの扱いを、その入力の種類に決めて出す（Studio の模擬入力はキーボード扱いで届き、表記が切り替わらないため）
InputMap.KIND_ATTRIBUTE = "InputKind"

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

export type Entry = { name: string, device: "keyboard" | "gamepad", input: string }

local function addEntries(result: { Entry }, name: string, binding: Binding)
	for _, input in binding.keyboard do
		table.insert(result, { name = name, device = "keyboard" :: "keyboard", input = input })
	end
	for _, input in binding.gamepad do
		table.insert(result, { name = name, device = "gamepad" :: "gamepad", input = input })
	end
end

-- 戦闘の操作（とイベントシーンのスキップ）のすべての入力を、操作の名前と一緒に列挙する（テストと重なりの確認に使う）
function InputMap.all(): { Entry }
	local result = {}
	addEntries(result, "Attack", InputMap.Attack)
	addEntries(result, "ChargeKogeki", InputMap.ChargeKogeki)
	addEntries(result, "Guard", InputMap.Guard)
	addEntries(result, "Ougi", InputMap.Ougi)
	for slot, binding in InputMap.Hikei do
		addEntries(result, `Hikei{slot}`, binding)
	end
	addEntries(result, "Skip", InputMap.Skip)
	return result
end

-- 画面の操作のすべての入力を、操作の名前と一緒に列挙する（テストと重なりの確認に使う）
function InputMap.menuAll(): { Entry }
	local result = {}
	addEntries(result, "Hajimeru", InputMap.Hajimeru)
	addEntries(result, "Kettei", InputMap.Kettei)
	addEntries(result, "Modoru", InputMap.Modoru)
	addEntries(result, "ShutsugekiHe", InputMap.ShutsugekiHe)
	return result
end

return InputMap
