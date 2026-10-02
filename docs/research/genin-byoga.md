# 下忍の描き方の調査（#5）

初期の無双シリーズは、画面の敵を数十体にとどめ、遠景を霧で隠して大軍に見せていた。
本作の、実体化圏で個体を数十体に絞る方針（[ADR 0003](../adr/0003-enemies-as-squad-data-materialized-near-players.md)）は、この手法と同じ形である。
Roblox では、サーバーは位置だけを持ち、クライアントで描く作りが大量の NPC に使われている。
どちらにするかは、試作（案A と案B）をスマホ実機で比べて決める（#15）。

## 初期の無双シリーズの大軍の見せ方

- 真・三國無双（PS2、海外名 Dynasty Warriors 2）は、遠景を灰色の霧で隠し、多くの敵を出しても処理が落ちないようにしていた
- 霧の向こうは見えず、敵が急に現れることもあった
- 真・三國無双2（PS2、海外名 Dynasty Warriors 3）も、霧や雨で描く距離の短さを隠しつつ、数十人の敵味方を同時に戦わせていた
- 画面には戦場の一部しか映らず、全体の戦況はミニマップで読ませる形だった（掲示板の利用者の意見）
- 雑兵は攻めてこずに立っていることが多い。攻めすぎる敵は、1人で大軍と戦う遊びを壊すという見方がある

出典

- [Let's… Sorta… Talk About Dynasty Warriors 2（Blimey, boyo）](https://blimeyboyo.wordpress.com/2015/08/11/lets-sorta-talk-about-dynasty-warriors-2/)
- [Dynasty Warriors 3 (PS2) review（The Pixel Empire）](https://www.thepixelempire.net/dynasty-warriors-3-ps2-review.html)
- [Why Dynasty Warriors fail to capture the feeling of an all-out war even with 100 units on screen（ResetEra）](https://www.resetera.com/threads/why-dynasty-warriors-fail-to-capture-the-feeling-of-an-all-out-war-even-with-100-units-on-screen.549454/)
- [Good idea, Bad idea: Dynasty Warriors and the hack n' slash pretenders（Destructoid）](https://www.destructoid.com/good-idea-bad-idea-dynasty-warriors-and-the-hack-n-slash-pretenders/)

## Roblox での大量の NPC

- サーバーは位置を送るだけにし、クライアントがモデルを描く作りで、100〜200 体を 60 FPS で動かせたという報告がある
- Humanoid の NPC は、動きの処理をクライアントへ寄せるほど通信と物理の負荷が下がる、という意見が多い
- UnreliableRemoteEvent は上限を超える送信を捨てる。上限は当初 900 バイトで、2025-03 に 1000 バイトへ上がった
- 試作では余裕を見て 900 バイトに収め、位置を整数に詰めた buffer で送る

出典

- [What is the most efficient way to render client sided mobs?（DevForum）](https://devforum.roblox.com/t/what-is-the-most-efficient-way-to-render-client-sided-mobs/421788)
- [Methods of reducing network and physics lag with large numbers of humanoids（DevForum）](https://devforum.roblox.com/t/methods-of-reducing-network-and-physics-lag-with-large-numbers-of-humanoids/371319)
- [Introducing UnreliableRemoteEvents（DevForum）](https://devforum.roblox.com/t/introducing-unreliableremoteevents/2724155)

## 本作への当てはめ

- 実体化圏の半径は、初期の無双シリーズの霧の距離にあたる。出す個体は数十体に絞る（#76）
- 攻撃トークン（#84）は、攻めてくるのが一部だけという作りと同じ
- 出し入れは視界の外で行う（#81）。遠景を霧（Atmosphere）で隠す手もある
- 案A と案B は、スマホ実機での FPS と受信量で決める（#15）

## 試作で比べるもの

| | 案A | 案B（Attribute） | 案B（Unreliable） |
|---|---|---|---|
| 下忍のモデル | サーバーの Humanoid 付き | クライアントが描く | クライアントが描く |
| 動きの計算 | サーバーの Humanoid と物理 | サーバーのデータ | サーバーのデータ |
| 送り方 | Roblox の複製 | 下忍ごとの Attribute | 全員分を buffer で一度に |
| 送る回数 | Roblox 任せ | 変わった値を 10 回/秒 | 10 回/秒 |

体数 30・60・100 のそれぞれで、FPS・受信量・サーバーの Heartbeat・メモリを記録する。
試作の動かし方は [proto/README.md](../../proto/README.md) にある。
