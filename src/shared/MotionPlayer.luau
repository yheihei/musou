--!strict
-- モーションのトラックを、取得元の区間（Motions.segmentOf）で流す。Roblox の API を使うので、Lune のテストからは読まない。
-- クライアントの MotionController（自分の行動）と、サーバーの JoninKotaiService（上忍と首領の型）・EnemyService（下忍）が使う。
--
-- - 区間の頭から、区間の長さを行動の長さに合わせた速さで流し、区間の終わりで止める。
--   hold なら終わりの姿のまま残し（トラックを止めるのは呼び出し側）、そうでなければ重ねて移りながら止める
-- - 丸ごとの区間は頭から流す（今までと同じ）。hold なら終わりの姿で残し、くり返すトラックは Looped でくり返す
-- - 丸ごとでない区間をくり返すときは、区間の終わりに着くたびに頭へ戻す
-- - 行動を始めてからの経過（elapsed）があれば、その分だけ進めた位置から流す（くり返すトラックは進めない）
-- - 読み込みが済んでおらず長さが分からなければ、分かった時点で区間と速さを決め直す。長さはフレームごとに見る
--   （AnimationTrack.Length は読み込みで変わっても GetPropertyChangedSignal の知らせが来ない。2026-10-17 に Studio で確かめた）
-- - 同じトラックを流し直したら（同じクリップの別の区間など）、前の再生の終わりの予定は捨てる
-- - 窓口の SetMotion で差し替えた行動のモーションは、Motions の ModuleScript の Attribute の Test に JSON で入る（tests で読む）。
--   サーバーで書くとクライアントにも複製されるので、自分の行動（クライアント）と上忍と首領の型（サーバー）のどちらにも効く

local HttpService = game:GetService("HttpService")

local Motions = require("./Motions")

local MotionPlayer = {}

export type Options = {
	-- 区間。nil はクリップを丸ごと流す
	source: Motions.MeshySource?,
	-- 行動の長さ（秒）。区間をこの長さで流す。nil か終わりの無い行動は等速
	duration: number?,
	-- 重ねて移る秒数
	fade: number,
	-- くり返すか
	looped: boolean?,
	-- 区間の終わりで、終わりの姿のまま止めて残すか（くり返さないときだけ）。false なら止める
	hold: boolean?,
	-- 行動を始めてからの経過（秒）。その分だけ進めた位置から流す
	elapsed: number?,
}

-- 差し替えを入れる Attribute の名前（Motions の ModuleScript に付ける）
MotionPlayer.TEST_ATTRIBUTE = "Test"

-- 終わりの姿で残すときに止める位置を、トラックの終わりからこの秒（クリップの時間）だけ手前にする
local HOLD_MARGIN = 1 / 30
-- 区間の終わりの予定を、この秒（実時間）だけ早める。予定が1フレーム遅れて呼ばれても、止める位置を通り過ぎないように
local EARLY = 1 / 30
-- 読み込みの前のトラックの長さが分かるまで待つ秒数。過ぎたら等速の丸ごとのまま
local LENGTH_WAIT = 5

-- トラックごとの再生の番号。流し直すたびに増やし、前の再生の予定を捨てる
local plays: { [AnimationTrack]: number } = setmetatable({}, { __mode = "k" }) :: any

-- 差し替えの Attribute の、前に読んだ文字列と中身
local testRaw: string? = nil
local testValue: { [string]: Motions.MotionTest }? = nil

local function motionsModule(): Instance?
	local parent = script.Parent
	return if parent then parent:FindFirstChild("Motions") else nil
end

-- 窓口の SetMotion で差し替えた行動のモーション（項目の名前ごと）。差し替えが無ければ nil
function MotionPlayer.tests(): { [string]: Motions.MotionTest }?
	local module = motionsModule()
	local raw = if module then module:GetAttribute(MotionPlayer.TEST_ATTRIBUTE) else nil
	if type(raw) ~= "string" or raw == "" then
		return nil
	end
	if raw ~= testRaw then
		testRaw = raw
		local ok, decoded = pcall(function(): any
			return HttpService:JSONDecode(raw)
		end)
		testValue = if ok and type(decoded) == "table" then decoded else nil
	end
	return testValue
end

-- 差し替えた行動のモーションを書く（サーバーの窓口から）。空なら Attribute を消す
function MotionPlayer.setTests(tests: { [string]: Motions.MotionTest })
	local module = motionsModule()
	if not module then
		return
	end
	if next(tests) == nil then
		module:SetAttribute(MotionPlayer.TEST_ATTRIBUTE, nil)
	else
		module:SetAttribute(MotionPlayer.TEST_ATTRIBUTE, HttpService:JSONEncode(tests))
	end
end

-- 区間の終わりの予定を入れる。くり返すなら頭へ戻して次の予定を入れ、hold なら終わりの姿で止め、ほかは止める
local function scheduleEnd(track: AnimationTrack, token: number, segment: Motions.Segment, options: Options)
	local looped = options.looped == true
	local hold = options.hold == true and not looped
	local target = segment.stop
	if hold then
		target = math.max(math.min(target, track.Length - HOLD_MARGIN), segment.start)
	end
	local wait = (target - track.TimePosition) / segment.speed - EARLY
	task.delay(math.max(wait, 0), function()
		if plays[track] ~= token or not track.IsPlaying then
			return
		end
		if looped then
			track.TimePosition = segment.start
			scheduleEnd(track, token, segment, options)
		elseif hold then
			track:AdjustSpeed(0)
			track.TimePosition = target
		else
			track:AdjustSpeed(0)
			track:Stop(options.fade)
		end
	end)
end

-- 今のトラックの長さで区間と速さを決め、流す位置と終わりの予定を入れる。長さが分からなければ等速のまま待つ
local function apply(track: AnimationTrack, token: number, options: Options, playedAt: number)
	if plays[track] ~= token or not track.IsPlaying then
		return
	end
	local segment = Motions.segmentOf(options.source, track.Length, options.duration)
	track:AdjustSpeed(segment.speed)
	if track.Length <= 0 then
		return
	end
	local looped = options.looped == true
	local elapsed = if looped then 0 else (options.elapsed or 0) + (os.clock() - playedAt)
	if not segment.whole or elapsed > 0 then
		track.TimePosition = Motions.segmentPosition(segment, elapsed)
	end
	if not segment.whole or (options.hold == true and not looped) then
		scheduleEnd(track, token, segment, options)
	end
end

-- トラック track を、区間と行動の長さに合わせて流す（options）。トラックの Priority は呼び出し側で決めておく
function MotionPlayer.play(track: AnimationTrack, options: Options)
	local token = (plays[track] or 0) + 1
	plays[track] = token
	-- 終わりの姿で残すトラックは、止める位置の前に終わりに着いても止まって姿が戻らないよう、くり返しにしておく
	-- （止める位置で速さを 0 にするので、くり返しはしない）
	track.Looped = options.looped == true or options.hold == true
	track:Play(options.fade)
	local playedAt = os.clock()
	apply(track, token, options, playedAt)
	if track.Length <= 0 then
		task.spawn(function()
			local waited = 0
			while track.Length <= 0 and waited < LENGTH_WAIT and plays[track] == token do
				waited += task.wait()
			end
			if track.Length > 0 then
				apply(track, token, options, playedAt)
			end
		end)
	end
end

return MotionPlayer
