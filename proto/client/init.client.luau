--!strict
-- 下忍の描き方の試作のクライアント（検証用ブランチだけ。main には入れない）。
-- 計測の画面（方式・体数・自動の薙ぎ払いの切り替えと、FPS・受信量・サーバーの Heartbeat）を出し、
-- 案B のときは下忍のモデルを自分で描く。案A の下忍はサーバーのモデルがそのまま複製される。

local Hud = require(script:WaitForChild("Hud"))
local RendererB = require(script:WaitForChild("RendererB"))

Hud.start()
RendererB.start()
