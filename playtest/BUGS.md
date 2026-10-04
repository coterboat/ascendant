# playtest bugs

running ledger kept by repo clerk from playtester's reports. one file per red run lives in `playtest/reports/`. bug ids follow playtester's A-numbers.

## open

| id | severity | title | first seen | latest report |
|---|---|---|---|---|

none.

## fixed

| id | title | fixed in | date |
|---|---|---|---|
| A-005 | the tests don't guard several documented resolver rules: 6 real rule changes still give 36 passed, 0 failed (broken; `tests/test_turn_resolver.gd:500`, first seen 3e92778, PR #15, [report](reports/2026-09-30-1752-3e92778.md)) | 1f9dd26 (PR #15, not yet on main) | 2026-09-30 |
| A-004 | a recruit that forms a new army says "They joined army X", as if X already existed (glitch; `rules/turn_resolver.gd:416-417`, first seen 3e92778, PR #15, [report](reports/2026-09-30-1752-3e92778.md)) | 1f9dd26 (PR #15, not yet on main) | 2026-09-30 |
| A-003 | deep_copy of a state with an army at an unknown province puts null in copy.armies, and copy.to_dict() then fails with a SCRIPT ERROR (glitch; `rules/game_state.gd:125`, first seen 517b025, PR #13, [report](reports/2026-09-30-1230-517b025.md)) | 84dba20 (b56d2b1) | 2026-09-30 |
| A-002 | the serialization and deep-copy tests don't check field values, so dropping gold, owner, hp, location or turn on load goes unnoticed (broken; `tests/test_rules_model.gd:114-127`, first seen 1340b25, PR #13, [report](reports/2026-09-30-1223-1340b25.md)) | 517b025 (c84cbbb) | 2026-09-30 |
| A-001 | README says every command exits non-zero on failure, but the headless boot exits 0 when the main scene has script or parse errors (glitch; `README.md:9` vs `README.md:32`, first seen 663c091, PR #11; filed from playtester's fixed notice) | 2782c55 (76290a2) | 2026-09-30 |
