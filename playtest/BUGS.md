# playtest bugs

running ledger kept by repo clerk from playtester's reports. one file per red run lives in `playtest/reports/`. bug ids follow playtester's A-numbers where free; a number already used gets the next free id.

## open

| id | severity | title | first seen | latest report |
|---|---|---|---|---|
| A-006 | glitch | cast dialog's deferred fit lambda runs after the dialog is freed (SCRIPT ERROR in tests) | 59066e7 | [2026-11-15-0034-59066e7](reports/2026-11-15-0034-59066e7.md) |

### A-006: cast dialog's deferred fit lambda runs after the dialog is freed (SCRIPT ERROR in tests)
- note: playtester numbered this A4; A-004 was already used, so it is A-006 here
- repro:
  1. tests/runner.gd full run (godot --headless --path . -s tests/runner.gd); errors print near the end of the run, in the cast-dialog tests
- error: `SCRIPT ERROR: Bad address index.` at ArmyCard.<anonymous lambda> (res://ui/cast_dialog.gd:164) and PortraitCard.<anonymous lambda> (res://ui/cast_dialog.gd:164), each preceded by `ERROR: Condition "slot >= slot_max" is true. Returning: nullptr`. also `1 RID of type "Canvas" was leaked`
- suspect: ui/cast_dialog.gd:158-166 (_queue_fit lambda via call_deferred reads _fit_queued / panel after the dialog is freed). file last touched by bf85684 (UI-POLISH-1)

## fixed

| id | title | fixed in | date |
|---|---|---|---|
| A-005 | the tests don't guard several documented resolver rules: 6 real rule changes still give 36 passed, 0 failed (broken; `tests/test_turn_resolver.gd:500`, first seen 3e92778, PR #15, [report](reports/2026-09-30-1752-3e92778.md)) | 1f9dd26 (PR #15, not yet on main) | 2026-09-30 |
| A-004 | a recruit that forms a new army says "They joined army X", as if X already existed (glitch; `rules/turn_resolver.gd:416-417`, first seen 3e92778, PR #15, [report](reports/2026-09-30-1752-3e92778.md)) | 1f9dd26 (PR #15, not yet on main) | 2026-09-30 |
| A-003 | deep_copy of a state with an army at an unknown province puts null in copy.armies, and copy.to_dict() then fails with a SCRIPT ERROR (glitch; `rules/game_state.gd:125`, first seen 517b025, PR #13, [report](reports/2026-09-30-1230-517b025.md)) | 84dba20 (b56d2b1) | 2026-09-30 |
| A-002 | the serialization and deep-copy tests don't check field values, so dropping gold, owner, hp, location or turn on load goes unnoticed (broken; `tests/test_rules_model.gd:114-127`, first seen 1340b25, PR #13, [report](reports/2026-09-30-1223-1340b25.md)) | 517b025 (c84cbbb) | 2026-09-30 |
| A-001 | README says every command exits non-zero on failure, but the headless boot exits 0 when the main scene has script or parse errors (glitch; `README.md:9` vs `README.md:32`, first seen 663c091, PR #11; filed from playtester's fixed notice) | 2782c55 (76290a2) | 2026-09-30 |
