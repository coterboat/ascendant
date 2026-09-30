# Ludo credit ledger

One line per batch. Credits = balance delta from `GET /assets/account` (`credits.available`), before vs after, cutouts and re-rolls included. Per-call detail lives in the batch ledger named in the line.

| date | batch | credits spent | balance after | notes |
|---|---|---|---|---|
| 2026-09-30 | asc-style-probe | 40.0 | 6850.1 | before 6890.1; cap 40.0 (36.0 planned + one 4.0 forge re-roll of the cel attack); per-call ledger `assets/_probe/asc-style-probe_ledger.json` |
