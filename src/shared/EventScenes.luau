--!strict
-- イベントシーンの定義表。ID と長さを持つ。カメラ・役者・台詞の台本は、クライアントで再生する処理（#72）が足す。
-- ステージの前後にどのシーンを流すかは Stages.luau の eventScenes にある。
-- 長さが過ぎるか、シーンを見ている出撃メンバー全員がスキップを押すと、サーバーが次のフェーズへ進める。
-- 試験用のシーン（shiken）はストーリーのステージに登録せず、窓口の StartEventScene で流す。
-- Roblox の API は使わない。

export type EventScene = {
	id: string,
	-- 長さ（秒）。全員がスキップしなければ、この時間がたつと次のフェーズへ進む
	duration: number,
	-- 試験用のシーンか
	shiken: boolean?,
}

local EventScenes = {}

local definitions: { [string]: EventScene } = {
	-- 試験用のシーン。中身は無く、同期とスキップの集計を確かめるために流す
	Shiken = { id = "Shiken", duration = 20, shiken = true },
}

EventScenes.definitions = definitions

-- シーンの定義。ID が nil か定義が無ければ nil
function EventScenes.get(id: string?): EventScene?
	if id == nil then
		return nil
	end
	return definitions[id]
end

return EventScenes
