--!strict
-- 最小のテスト用ライブラリ。spec から `require("@testkit")` で読む。
-- test は登録と同時に実行し、結果を集計する。集計は .lune/test.luau が読む。

export type Expectation = {
	toBe: (expected: any) -> (),
	toEqual: (expected: any) -> (),
	toBeNear: (expected: number, tolerance: number?) -> (),
	toThrow: (pattern: string?) -> (),
}

type Failure = {
	file: string,
	name: string,
	message: string,
}

local testkit = {
	passed = 0,
	failures = {} :: { Failure },
	currentFile = "",
}

local function format(value: any, depth: number?): string
	local level = depth or 0
	if type(value) == "string" then
		return string.format("%q", value)
	elseif type(value) ~= "table" then
		return tostring(value)
	elseif level >= 3 then
		return "{...}"
	end
	local parts = {}
	if #value > 0 then
		for _, item in ipairs(value) do
			table.insert(parts, format(item, level + 1))
		end
		return "{ " .. table.concat(parts, ", ") .. " }"
	end
	local keys = {}
	for key in value do
		table.insert(keys, key)
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)
	for _, key in keys do
		local label = if type(key) == "string" and string.match(key, "^[%a_][%w_]*$")
			then key
			else `[{format(key, level + 1)}]`
		table.insert(parts, `{label} = {format(value[key], level + 1)}`)
	end
	return "{ " .. table.concat(parts, ", ") .. " }"
end

-- 最初に食い違った場所のパスを返す。一致したら nil
local function firstDifference(actual: any, expected: any, path: string): string?
	if actual == expected then
		return nil
	end
	if type(actual) ~= "table" or type(expected) ~= "table" then
		return path
	end
	for key, value in expected do
		local found = firstDifference(actual[key], value, `{path}.{tostring(key)}`)
		if found then
			return found
		end
	end
	for key in actual do
		if expected[key] == nil then
			return `{path}.{tostring(key)}`
		end
	end
	return nil
end

local function valueAt(root: any, path: string): any
	local value = root
	for key in string.gmatch(path, "%.([^%.]+)") do
		if type(value) ~= "table" then
			return nil
		end
		value = if value[key] ~= nil then value[key] else value[tonumber(key)]
	end
	return value
end

function testkit.expect(actual: any): Expectation
	return {
		toBe = function(expected: any)
			if actual ~= expected then
				error(`expected {format(expected)}, got {format(actual)}`, 2)
			end
		end,
		toEqual = function(expected: any)
			local path = firstDifference(actual, expected, "")
			if path == "" then
				error(`expected {format(expected)}, got {format(actual)}`, 2)
			elseif path then
				local where = string.sub(path, 2)
				error(
					`differs at {where}: expected {format(valueAt(expected, path))}, got {format(valueAt(actual, path))}`,
					2
				)
			end
		end,
		toBeNear = function(expected: number, tolerance: number?)
			local limit = tolerance or 1e-6
			if type(actual) ~= "number" or math.abs(actual - expected) > limit then
				error(`expected {expected} ± {limit}, got {format(actual)}`, 2)
			end
		end,
		toThrow = function(pattern: string?)
			local ok, err = pcall(actual)
			if ok then
				error("expected an error, but none was raised", 2)
			end
			if pattern and not string.find(tostring(err), pattern, 1, true) then
				error(`expected an error containing {format(pattern)}, got {format(tostring(err))}`, 2)
			end
		end,
	}
end

-- リポジトリの直下からの相対パスで JSON を読む（default.project.json との突き合わせなどに使う）。
-- ファイルの読み込みは .lune/test.luau が差し込む
function testkit.readJson(_path: string): any
	error("testkit.readJson は lune run test から実行したときだけ使える")
end

-- リポジトリの直下からの相対パスでファイルを読み、中身をそのまま返す。無ければ nil。
-- 画像の大きさの確かめなどに使う。ファイルの読み込みは .lune/test.luau が差し込む
function testkit.readFile(_path: string): string?
	error("testkit.readFile は lune run test から実行したときだけ使える")
end

function testkit.test(name: string, fn: () -> ())
	-- fn は値を返さないので、エラーの値を受け取れるよう any を返す関数として扱う
	local ok, err = pcall(fn :: () -> any)
	if ok then
		testkit.passed += 1
		print(`  PASS {name}`)
	else
		table.insert(testkit.failures, { file = testkit.currentFile, name = name, message = tostring(err) })
		print(`  FAIL {name}`)
		print(`       {err}`)
	end
end

return testkit
