# playtest bugs

running ledger kept by repo clerk from playtester's reports. one file per red run lives in `playtest/reports/`. bug ids follow playtester's A-numbers.

## open

| id | severity | title | first seen | latest report |
|---|---|---|---|---|
| A-003 | glitch | deep_copy of a state with an army at an unknown province puts null in copy.armies, and copy.to_dict() then fails with a SCRIPT ERROR | 517b025 (PR #13) | [2026-09-30-1230-517b025](reports/2026-09-30-1230-517b025.md) |

### A-003: deep_copy of a state with an army at an unknown province puts null in copy.armies, and copy.to_dict() then fails with a SCRIPT ERROR
- repro (scratch): `var s := GameState.new(3); s.armies[0].location = "nowhere"; var c := s.deep_copy(); c.to_dict()`
- error: `ERROR: unknown province 'nowhere'` (rules/army.gd:38), then copy.armies.size=2 with copy.armies[0]=<null>, then `SCRIPT ERROR: Invalid call. Nonexistent function 'to_dict' in base 'Nil'.` at res://rules/game_state.gd:55
- suspect: rules/game_state.gd:125 appends the Army.from_dict result without the null check that from_dict has at game_state.gd:98

## fixed

| id | title | fixed in | date |
|---|---|---|---|
| A-002 | the serialization and deep-copy tests don't check field values, so dropping gold, owner, hp, location or turn on load goes unnoticed (broken; `tests/test_rules_model.gd:114-127`, first seen 1340b25, PR #13, [report](reports/2026-09-30-1223-1340b25.md)) | 517b025 (c84cbbb) | 2026-09-30 |
| A-001 | README says every command exits non-zero on failure, but the headless boot exits 0 when the main scene has script or parse errors (glitch; `README.md:9` vs `README.md:32`, first seen 663c091, PR #11; filed from playtester's fixed notice) | 2782c55 (76290a2) | 2026-09-30 |
