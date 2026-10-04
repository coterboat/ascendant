# ascendant (working title)

A more approachable Dominions 6: deep simultaneous-turn strategy, huge depth, polished UI/UX, and no study-the-guide friction. Complex, but approachable. Godot 4.5.

Built by a bot studio with Alex as creative director and final QA. See `STUDIO.md`.

## play

From the repo root, with the local Godot on the Mac, or on the build box:

```sh
/Users/coterboat/Downloads/Godot.app/Contents/MacOS/Godot --path .
/home/box/playtester/godot/godot --path .
```

- **Title screen:** **Continue** (only when there is a save) picks up your latest save. **New game** sets up a game: by default you (Player 1) play against the computer at Normal, with **Rulers** on, so Start first opens the build screen where you pick your ruler and mandates. Untick Rulers for the simpler game. **Load game** lists every save. **Quick start** goes straight in: a random faction against the computer, rulers on (your ruler gets its balanced build), a random seed. **Codex**, **Settings** (window or fullscreen, interface size 100% or 125%) and **Quit**. Player 1 is Vermilion with a circle emblem, Player 2 Cobalt with a square, whichever faction they pick.
- **Against the computer:** select an army, then click a neighboring province to move it; select your capital to recruit. Press **End turn**: the computer gives its orders from the same start-of-turn map without seeing yours, everything resolves at once, and the turn report (with what the computer was thinking) opens. Capture the enemy capital to win.
- **Hotseat:** on the new game screen, set Player 2 to **Human**. Both players share one computer: the map is covered between players until the next one presses **Ready**. **New game** on the victory screen sets up a rematch: same seats, players and rulers, new seed.
- **Saving:** the game saves itself at the start of every turn (the last three autosaves are kept). **Menu** in the top bar (or Esc) has **Save game** (name it, or keep the date-and-time name), **Load game**, **Settings** and **Quit to title**. A save is the game as it stood when the turn began: orders you gave during the turn are not saved, and loading starts that turn again. A loaded hotseat game opens on the handoff cover. Saves live in Godot's user folder (`user://saves`, on a Mac `~/Library/Application Support/Godot/app_userdata/Ascendant/saves`); settings in `user://settings.cfg`.
- **Codex:** every rule in plain words. Open it with the **Codex** button (title screen or top bar), or jump to the rule behind any number: right-click it, or hover it and press **F1**. Esc closes it.

## running and checking the project

All commands run from the repo root. Each exits 0 on success and non-zero on failure.

First run after a fresh clone (builds the `.godot/` import and class cache):

```sh
/home/box/playtester/godot/godot --headless --path . --import
```

Run the tests (`tests/runner.gd` runs every `test_*` method in `tests/**/test_*.gd`; add `-- --only=test_save,test_m1` to run only the files whose names contain those texts). Tests save to a temporary folder, never to your real saves:

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
