# Ludo credit ledger

One line per batch. Credits = balance delta from `GET /assets/account` (`credits.available`), before vs after, cutouts and re-rolls included. Per-call detail lives in the batch ledger named in the line.

| date | batch | credits spent | balance after | notes |
|---|---|---|---|---|
| 2026-09-30 | asc-style-probe | 40.0 | 6850.1 | before 6890.1; cap 40.0 (36.0 planned + one 4.0 forge re-roll of the cel attack); PR #12 (closed unmerged, superseded by the M1 PR); per-call ledger `assets/_probe/asc-style-probe_ledger.json` on branch `assets/asc-style-probe` |
| 2026-09-30 | asc-m1-batch1 (#10) | 28.0 | 6822.1 | before 6850.1; hard cap 32.5; **13 of 13 rows shipped**. Includes the 1.5 cr text-only crossbowmen re-roll `asc_m1_portrait_kingdom_crossbowmen_v30` (13:51 ET, re-roll cap 3.0; balance 6823.6 → 6822.1; 0/3 passed, v21_c1 kept). Recovery after Ludo outage (plains health-check v20 succeeded 13:37 ET). Charged calls include 6 prior + recovery styled sets + 1 crossbowmen gender re-roll + 2 beast-banner cutouts. Per-call ledger `studio/ledgers/asc-m1-batch1.jsonl` |
| 2026-10-04 | asc-3d-probe (3D world spike, branch `spike-3d-world`) | 10.5 | 6275.1 | cap 20.0; 3 `image` reference pictures (0.5 each) + 3 `model3d` (3.0 each: spearman, tusker, Crownkeep), all succeeded first try, no re-rolls. Summed from the per-call ledger `studio/ledgers/asc-3d-probe.jsonl`, because the account delta (6301.1 before, 6275.1 after = 26.0) also holds the parallel generation job's calls on the same key |
