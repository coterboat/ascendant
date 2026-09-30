# ascendant (working title)

A more approachable Dominions 6: deep simultaneous-turn strategy, huge depth, polished UI/UX, and no study-the-guide friction. Complex, but approachable. Godot 4.5.

Built by a bot studio with Alex as creative director and final QA. See `STUDIO.md`.

## running and checking the project

All commands run from the repo root. Each exits 0 on success and non-zero on failure.

First run after a fresh clone (builds the `.godot/` import and class cache):

```sh
/home/box/playtester/godot/godot --headless --path . --import
```

Run the tests (`tests/runner.gd` runs every `test_*` method in `tests/**/test_*.gd`):

```sh
/home/box/playtester/godot/godot --headless --path . -s tests/runner.gd
```

Compile check (parses every project `.gd` file, skipping `.godot/` and other hidden or `.gdignore` folders):

```sh
/home/box/playtester/godot/godot --headless --path . -s tools/compile_check.gd
```

Headless boot of the main scene. Godot itself exits 0 even when a script fails to parse or errors at runtime, so use the wrapper: it runs `godot --headless --path . --quit-after 120`, shows the output, and exits non-zero if Godot exits non-zero, times out (60s), or prints any `ERROR` / `SCRIPT ERROR` line:

```sh
tools/boot_check.sh
```

Run it windowed to see the title screen:

```sh
/home/box/playtester/godot/godot --path .
```

### layout

- `rules/`: pure game-rules code. No `Node`, scene, or UI dependencies, so it can be unit-tested and replayed from a seed.
- `ui/`: scenes and UI scripts. The main scene is `ui/title_screen.tscn`.
- `data/`: content definitions (factions, units, maps).
- `tests/`: tests. Add a `test_*.gd` file that `extends "res://tests/test_case.gd"` and give it `test_*` methods. A failed assertion or a script error fails the test.
- `tools/`: dev tools, including `compile_check.gd`.
