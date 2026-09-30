# Ludo credit ledger

One line per batch. Credits = balance delta from `GET /assets/account` (`credits.available`), before vs after, cutouts and re-rolls included. Per-call detail lives in the batch ledger named in the line.

| date | batch | credits spent | balance after | notes |
|---|---|---|---|---|
| 2026-09-30 | asc-style-probe | 40.0 | 6850.1 | before 6890.1; cap 40.0 (36.0 planned + one 4.0 forge re-roll of the cel attack); PR #12 (closed unmerged, superseded by the M1 PR); per-call ledger `assets/_probe/asc-style-probe_ledger.json` on branch `assets/asc-style-probe` |
| 2026-09-30 | asc-m1-batch1 (#10) | 13.5 | 6836.6 | before 6850.1; estimate 20.5 (26 with re-rolls), hard cap 32.5; **6 of 13 rows shipped**. 9 charged calls × 1.5. 6.0 of the 13.5 bought sets rejected for anchor palette leak (beast banner v1, war bear v1, fangthrowers v1, warchief v1). 33 of 42 jobs failed with Ludo 500 "AI server timeout" (all refunded, 0 cr). Kingdom banner installed from probe c2 for 0 cr. Per-call ledger `studio/ledgers/asc-m1-batch1.jsonl` |
