--!strict
-- `lune run test` で src/shared の *.spec.luau をすべて実行する。
-- `lune run test Actions` のように引数を渡すと、パスにその文字列を含む spec だけを実行する。
-- 失敗が1件でもあるか、spec が1つも見つからないときは終了コード1で終わる。

local fs = require("@lune/fs")
local process = require("@lune/process")

local testkit = require("./lib/testkit")

local ROOT = "src/shared"

local function collect(dir: string, found: { string })
	for _, name in fs.readDir(dir) do
		local path = `{dir}/{name}`
		if fs.isDir(path) then
			collect(path, found)
		elseif string.match(name, "%.spec%.luau$") then
			table.insert(found, path)
		end
	end
end

local function matchesFilter(path: string): boolean
	if #process.args == 0 then
		return true
	end
	for _, filter in process.args do
		if string.find(path, filter, 1, true) then
			return true
		end
	end
	return false
end

local specs = {}
collect(ROOT, specs)
table.sort(specs)

local ran = 0
for _, path in specs do
	if matchesFilter(path) then
		ran += 1
		print(path)
		testkit.currentFile = path
		-- require はこのスクリプトからの相対パスで解決される
		local ok, err = pcall(require, "../" .. string.gsub(path, "%.luau$", ""))
		if not ok then
			table.insert(testkit.failures, { file = path, name = "(読み込み)", message = tostring(err) })
			print(`  FAIL (読み込み)`)
			print(`       {err}`)
		end
	end
end

print("")
if ran == 0 then
	if #process.args > 0 then
		print(`{table.concat(process.args, " ")} を含む spec が {ROOT} に見つからない`)
	else
		print(`spec が {ROOT} に見つからない`)
	end
	process.exit(1)
end

print(`{testkit.passed} passed, {#testkit.failures} failed ({ran} files)`)
for _, failure in testkit.failures do
	print(`  {failure.file} > {failure.name}`)
end
process.exit(if #testkit.failures > 0 then 1 else 0)
