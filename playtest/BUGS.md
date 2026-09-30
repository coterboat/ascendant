# playtest bugs

running ledger kept by repo clerk from playtester's reports. one file per red run lives in `playtest/reports/`. bug ids follow playtester's A-numbers.

## open

| id | severity | title | first seen | latest report |
|---|---|---|---|---|
| A-005 | broken | the tests don't guard several documented resolver rules: 6 real rule changes still give 36 passed, 0 failed | 3e92778 (PR #15) | [2026-09-30-1752-3e92778](reports/2026-09-30-1752-3e92778.md) |
| A-004 | glitch | a recruit that forms a new army says "They joined army X", as if X already existed | 3e92778 (PR #15) | [2026-09-30-1752-3e92778](reports/2026-09-30-1752-3e92778.md) |

### A-005: the tests don't guard several documented resolver rules: 6 real rule changes still give 36 passed, 0 failed
- repro:
  1. in a scratch copy, apply one at a time and run tests/runner.gd; each gives `36 passed, 0 failed`:
     - m28: rules/game_state.gd:156 `"seed_value": seed_value` (no str). JSON turns 9007199254740993 into 9007199254740992 and INT64_MAX into INT64_MIN. the test seed -8070450532247928832 is double-exact
     - m20: rules/turn_resolver.gd:67-69 with province battles before border battles. the probe shows wrong outcomes plus `SCRIPT ERROR: Invalid access to property or key 'units' on a base object of type 'Nil'.` at rules/stub_battle_resolver.gd:13
     - m21: rules/turn_resolver.gd:252 without `a.faction != b.faction`, so a same-faction swap fights
     - m34: data/map.gd with an extra ironspike<->blackwood link, so the mirror breaks
     - m02/m06: move sort (turn_resolver.gd:222) or army sort (:531) removed, so the event order depends on the order list or array order
- error: none. each prints `36 passed, 0 failed`
- suspect: tests/test_turn_resolver.gd:500 (double-exact seed), :151-175 (the only swap test: 1v1, cross-faction, nobody at either end), :588-599 (mirror test checks only capital degree and 3 distances), :446-466 (only faction key order is shuffled)

### A-004: a recruit that forms a new army says "They joined army X", as if X already existed
- repro:
  1. `var s := GameState.new(1); TurnResolver.resolve(s, {"kingdom": [MoveOrder.new("kingdom-1", "westwatch"), RecruitOrder.new("spearmen"), RecruitOrder.new("spearmen")]}, 1)`. crownkeep is empty after the move, so the first recruit forms kingdom-3
- error: both events read `Aurel Crown recruited Spearmen at Crownkeep for 8 gold (42 gold left). They joined army kingdom-3.` (the 2nd has 34 left). also in the playtest fixture: events 11 (beasts-3) and 12 (kingdom-4)
- suspect: rules/turn_resolver.gd:416-417 (the text) and :429-434 (_add_recruit creates the army without telling the caller)

## fixed

| id | title | fixed in | date |
|---|---|---|---|
| A-003 | deep_copy of a state with an army at an unknown province puts null in copy.armies, and copy.to_dict() then fails with a SCRIPT ERROR (glitch; `rules/game_state.gd:125`, first seen 517b025, PR #13, [report](reports/2026-09-30-1230-517b025.md)) | 84dba20 (b56d2b1) | 2026-09-30 |
| A-002 | the serialization and deep-copy tests don't check field values, so dropping gold, owner, hp, location or turn on load goes unnoticed (broken; `tests/test_rules_model.gd:114-127`, first seen 1340b25, PR #13, [report](reports/2026-09-30-1223-1340b25.md)) | 517b025 (c84cbbb) | 2026-09-30 |
| A-001 | README says every command exits non-zero on failure, but the headless boot exits 0 when the main scene has script or parse errors (glitch; `README.md:9` vs `README.md:32`, first seen 663c091, PR #11; filed from playtester's fixed notice) | 2782c55 (76290a2) | 2026-09-30 |
