# ドメイン用語の識別子はローマ字にする

`CONTEXT.md` の用語は、コード上でもローマ字の識別子にする（`Genin`、`Jonin`、`Shuryo`、`Butai`、`Heisu`、`Shiki`、`Kyoten`、`Honjin`、`Heitansen`、`Heiryoku`、`Ougi`、`Hikei` など）。
カタカナ語の用語は英語にする（`Stage`、`Party`、`Leader`、`Clan`、`Story`）。
英語に訳すと訳語が揺れ、兵力と兵数のような近い語の区別も崩れやすいためである。

## Considered Options

- すべて英語に訳す（`Grunt`、`Commander`、`Unit`、`Base`、`SupplyLine` など）。英語話者には読みやすいが、用語集との対応表が別に要る

## Consequences

- 既存コードの `Soldier`、`Officer`、`Squad`、`Musou` は、それぞれ `Genin`、`Jonin`、`Butai`、`Ougi` に改める
- 新しい用語を足すときは、先に `CONTEXT.md` に登録してから識別子を決める
