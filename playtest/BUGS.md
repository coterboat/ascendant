# playtest bugs

running ledger kept by repo clerk from playtester's reports. one file per red run lives in `playtest/reports/`. bug ids follow playtester's A-numbers.

## open

| id | severity | title | first seen | latest report |
|---|---|---|---|---|
| A-002 | broken | the serialization and deep-copy tests don't check field values, so dropping gold, owner, hp, location or turn on load goes unnoticed | 1340b25 (PR #13) | [2026-09-30-1223-1340b25](reports/2026-09-30-1223-1340b25.md) |

### A-002: the serialization and deep-copy tests don't check field values, so dropping gold, owner, hp, location or turn on load goes unnoticed
- repro (scratch copy only), each on its own, then `godot --headless --path . -s tests/runner.gd`: rules/faction.gd:39 `f.gold = 0`; rules/province.gd:44 `p.owner = ""`; rules/unit.gd:29 `u.current_hp = ut.hp`; rules/army.gd:34 `a.location = ""`; rules/game_state.gd:61 `"current_turn": 0,`
- error: none. each prints `9 passed, 0 failed` and exits 0
- suspect: tests/test_rules_model.gd:114-127 (the roundtrip test only compares sizes, current_turn (0 on both sides), seed, rng and provinces[0]/factions[0] ids). tests/test_rules_model.gd:137-144 (the deep-copy test only asserts the copy differs from a mutated original). the PR body claims the test shows load keeps provinces, factions, armies, turn, seed and rng.

## fixed

| id | title | fixed in | date |
|---|---|---|---|
| A-001 | README says every command exits non-zero on failure, but the headless boot exits 0 when the main scene has script or parse errors (glitch; `README.md:9` vs `README.md:32`, first seen 663c091, PR #11; filed from playtester's fixed notice) | 2782c55 (76290a2) | 2026-09-30 |
