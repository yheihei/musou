# ドメイン用語の識別子はローマ字にする

`CONTEXT.md` の用語は、コード上でもローマ字の識別子にする（`Genin`、`Jonin`、`Shuryo`、`Butai`、`Heisu`、`Shiki`、`Kyoten`、`Honjin`、`Heitansen`、`Heiryoku`、`Ougi`、`Hikei` など）。
カタカナ語の用語は英語にする（`Stage`、`Party`、`Leader`、`Clan`、`Story`）。
英語に訳すと訳語が揺れ、兵力と兵数のような近い語の区別も崩れやすいためである。

## 書き方

| 規則 | 例 |
|---|---|
| ヘボン式で書く | 士気 `Shiki`、出撃 `Shutsugeki`、伏兵 `Fukuhei` |
| 「おう」「うう」の長音は1字にする | 上忍 `Jonin`、兵数 `Heisu`、兵糧庫 `Hyoroko` |
| 語の頭の「おう」だけは2字で書く（1字の `O` では語が読み取れない） | 奥義 `Ougi` |
| 「えい」「いい」は2字のまま書く | 秘計 `Hikei`、大火計地域 `DaikakeiChiiki` |
| 漢字語はローマ字、カタカナ語は英語にし、つなぎ目を大文字にする | 奥義ゲージ `OugiGauge`、チャージ攻撃 `ChargeKogeki` |
| 2字以上の漢字語どうしのつなぎ目も大文字にする | 伏兵部隊 `FukuheiButai`、緊急回避 `KinkyuKaihi` |
| 1字の漢字が前後に付くだけなら区切らない | 兵站線 `Heitansen`、撃破数 `Gekihasu`、敵軍 `Tekigun` |
| 「の」は書かない | 強化の秘計 `KyokaHikei` |
| 頭を大文字にするかは Luau の慣習に従う | 型・モジュール・ID は `Gekihasu`、変数と関数は `gekihasu`・`addGekihasu` |

この書き方で、M1 の秘計8種は `Fukuhei`・`Rakuseki`・`Daikakei`・`Hyoroko`・`Bakuhawana`・`Chohatsu`・`Kishinka`・`Daikatsu` になる。
表情の5つは `Tsujo`・`Ikari`・`Odoroki`・`Yorokobi`・`Kumon` になる。

## Considered Options

- すべて英語に訳す（`Grunt`、`Commander`、`Unit`、`Base`、`SupplyLine` など）。英語話者には読みやすいが、用語集との対応表が別に要る

## Consequences

- 既存コードの `Soldier`、`Officer`、`Squad`、`Musou`、`KOs`、`Charge` は、それぞれ `Genin`、`Jonin`、`Butai`、`Ougi`、`Gekihasu`、`ChargeKogeki` に改める
- 新しい用語を足すときは、先に `CONTEXT.md` に登録してから識別子を決める
- 軍は英語の gun と同じ綴りの `Gun` になる
- 武器の銃を扱うときは `Ju` と書き、軍の `Gun` と区別する
