# tools/qa: a monkey that plays like a hand (QA-1, #250)

A test calls functions; a player moves a mouse through a viewport while the UI rebuilds under it. Alex's MVP walk found a crash
(#249, splitting an army: signal 11 in `Viewport::_drop_mouse_over`) that 1,884 headless tests never could. The monkey plays a
default game **only through real input** (`Input.parse_input_event`, each event handled at once as the OS's event loop does), so it
finds that kind of bug. Dev tool only: it never runs in the game or the tests, and it never touches the player's settings or saves.

- `monkey.gd`: the hand (a SceneTree script, like `tools/shots/play_shots.gd`).
- `run_monkey.sh`: runs it as a child Godot and says how the run ended.
- `monkey_log.gd`: the `events.log` format, written and read in one place (`tests/test_qa_monkey.gd`).

## Run it

```sh
tools/qa/run_monkey.sh --seed=7                                   # 1600x900, 12 turns or 20 minutes
tools/qa/run_monkey.sh --seed=7 --resolution=1280x720
tools/qa/run_monkey.sh --seed=7 --ui-scale=125                    # 1600x900 laid out at 1280x720, as Settings' 125%
tools/qa/run_monkey.sh --seeds=1-20 --focus=muster --minutes=5    # a batch, one run after another (or --seeds=3,8,21)
tools/qa/run_monkey.sh --seed=7 --turns=60 --minutes=60           # a long game
```

Run `--headless --path . --import` once in a fresh worktree first. `run_monkey.sh` starts Godot as a child process:

- `nice -n 10`, so the Mac's other work keeps the CPU (`pipeline/LANES.md`); it never waits on the load.
- `--always-on-top`: an occluded window never draws. The monkey also moves the window off the real cursor (Godot sends its own
  motion at the real cursor after a drop or a cursor change, which would move the hover under the hand).
- `--log-file <run>/godot.log`: Godot's log, and a crash's backtrace, land in the run's folder, never in the user data folder.
- `--audio-driver Dummy` (a silent night) and `--fixed-fps 60`: the game's clock moves one 60th of a second per frame however slow
  the Mac is, so a seed plays the same from one try to the next. Vsync is off, so the game runs as fast as the Mac allows.

One harness window at a time; monkey runs don't take the slot. Each run gets its own folder under `/tmp/ascendant-qa`
(`--out=BASE` to change it). `GODOT` overrides the binary (default: the Mac's `/Users/coterboat/Downloads/Godot.app`).

**The runner's own options:** `--seed=N`, `--seeds=A-B` or `--seeds=A,B,C`, `--resolution=WxH` (the window, default 1600x900),
`--hang=S` (default 60), `--out=BASE`, `--replay=FILE`. **The monkey's** (passed through; `monkey.gd`'s header has them all):
`--turns=N` (default 12), `--minutes=M` (default 20), `--ui-scale=100|125`, `--fog=on|off`, `--human=kingdom|beasts` (default: the
seed picks, as Quick start does), `--focus=AREA[,AREA]`, `--pace=N` (frames between gestures, default 6), `--shots=N` (a shot every
N gestures, default 60), `--slow-ms=N` (default 400).

### `--focus`

While the area is on screen the hand aims inside it more than half the time; while it isn't, it often takes a way there: a control
whose words open it, your army or province on the board, or a scroll toward the area when the area sits below the fold of a card.

| `--focus=` | the controls inside | the way there |
| --- | --- | --- |
| `muster` | Armies here (MusterBoard), the portraits, the army card | your armies on the board; Split, Merge, New army, Swap |
| `research` | the research panel, its HUD, the paths and lock-in previews | Research, Magic, spell, path |
| `fort` | the fort panel, Fortify, the province card, Recruit at, the walls | your provinces on the board; fort, palisade, storm, recruit |
| `battles` | the battle host (3D stage and Simple view), its controls, the report | every army on the board; Watch, battle, March, and right after March a province next to the army (a garrison or a rival there: a battle) |
| `chronicle` | the Chronicle, its notices, the Plan | Chronicle, Plan, seal |
| `settings` | the settings panel | Menu, Settings |

## What the hand does

Before every gesture it reads the screen: every visible control a hand could aim at (buttons, tabs, sliders, text boxes, lists,
scroll areas, anything with a tooltip or its own input, portraits that drag, places that take a drop, open popups), with its rect in
window pixels (the root's stretch and the interface scale applied: at the start an aim check moves onto the seal and confirms the
seal is what Godot then hovers), plus the board's provinces and armies where they stand on screen that frame. It picks one
(weighted: the board, buttons and drags first, a disabled button rarely), moves the mouse there in a few steps, then clicks,
double-clicks, right-clicks (the codex), hovers long enough for the tooltip, drags (a portrait onto another army or New army, a
slider, a pan of the board, a button pressed and dragged off) or turns the wheel. Sometimes it presses a key (Esc, Space, Enter, Tab,
F1, F, C, L, WASD and the arrows held, 1 to 6, M, N, R...) or sweeps the mouse fast across the screen; after a third of its gestures
the hand keeps moving at once, across whatever the click rebuilt. After 12 to 50 gestures on a turn it ends it: the End turn seal, or
in a first game the Plan's "Seal the orders"; when something covers the seal it closes that by its Close button, or Esc.

It never presses Quit (the app would close), the window picker (a fullscreen window leaves `--always-on-top`), or Quick start, the
new game screen's Start and the build screen's Ready (a game with a random seed could not be replayed). It reads the game only to aim
and to know when to stop: no order is ever given through the API.

## What it writes (`<run>/`)

- `events.log`: every input event, written **before** it is handled and flushed line by line, so a native crash leaves the line
  that set it off: `frame <TAB> json <TAB> what it aimed at  @ the screen and panels up`. Frames count from the moment the board was
  ready. `#` lines are notes: the options and config, the aim check, turn changes, each engine or script error or warning beside the
  gesture before it (an OS logger catches them from every thread; the monkey's own are marked), slow frames, shots, STUCK, and:
  - `HOVER-FREED`: a handler the event set off (a `mouse_exited`) took out of the tree the very control the pointer moved onto, and
    Godot 4.5.1 still holds it as hovered. That is #249's class, caught the moment it happens: the next mouse event after the control
    is freed crashes the game. The run goes on, so the crash itself shows.
- `godot.log` (`--log-file`; `godot.clean.log` without colour codes) and `stdout.log`: Godot's own output, with a crash's backtrace.
- `summary.json`: the verdict, the turn reached, gestures, events, errors (and the monkey's own), HOVER-FREED count, the aim check,
  every screen seen and the ten slowest frames.
- `shots/`: `f<frame>_<why>.jpg` at the start, each new turn, each screen (set of panels) not seen before (up to 40, and past
  that a battle or the victory screen still), every N gestures and the end. Read them for clipped or overlapping UI and numbers
  that don't explain themselves.
- `settings.cfg`, `saves/`: the run's own (the player's are never read or written; with no settings file the first-game guide shows,
  as for a new player).

## How a run ends

| ending | exit | what it means | what to do |
| --- | --- | --- | --- |
| `CLEAN` | 0 | the monkey stopped by itself (turns, minutes, the game over, the replay done) and Godot logged no error line | read the shots and `summary.json`'s slow frames |
| `ERRORS` | 1 | it stopped by itself, but Godot logged `ERROR` / `SCRIPT ERROR` lines | the runner prints each distinct error with the gesture and screen before it |
| `CRASH` | 2 | Godot died on a signal | the runner prints the backtrace, the seed, the last 30 events, the last notes and the replay command |
| `HANG` | 3 | no new event for 60 s (5 minutes while the game loads; up to 5 minutes while the Mac's load is above its core count) | the runner sends SIGSEGV first, so `godot.log` holds the main thread's stack, then the last 30 events |
| `STUCK` | 4 | 40 tries at a live game's seal and the turn never ended (tries on the title or after the game is over don't count; a loaded game starts again from 0) | `events.log`'s STUCK note names the screens up; the last shot shows it |
| `EXITED` | 5 | Godot quit before the monkey's end, with no signal | the last 30 events show what closed it |

The last line of each run is `RESULT seed=N verdict=... window=WxH dir=...`; a batch lists every run and exits with its worst.

- **No backtrace on a crash:** Godot 4.5.1's macOS crash handler prints its backtraces for SIGSEGV, SIGILL, SIGFPE and SIGTRAP, not
  for SIGBUS. A use-after-free like #249's can land as SIGBUS (signal 10) instead of SIGSEGV, and then dies silently: the runner
  names the signal, and the `HOVER-FREED` note and the last events say what happened. (macOS keeps its own report of every crash;
  the harness never reads it.)
- **A teardown hang:** Godot that hangs closing its window after the monkey's own `MONKEY END` (seen on macOS) is killed after 20 s
  and judged by the monkey's verdict: that is not the game's hang.
- **A slow Mac:** frames over `--slow-ms` are noted as `SLOW` with the gesture before them; on a loaded Mac (other lanes' suites,
  Playwright) a niced frame can take tens of seconds, which is why the hang limit grows with the load.

## Replay a seed, or a crash

**The same seed plays the same events** on the same build at the same window and interface size: the hand's choices come from the
seed and from what is on screen, and the game is deterministic frame by frame (`--fixed-fps`; the board's land bakes on a worker
thread, so frames are counted from the moment it is ready). Run the seed again:

```sh
tools/qa/run_monkey.sh --seed=1 --focus=muster --turns=8 --minutes=4       # the same options as the run
```

**`--replay` sends exactly the events a run sent**, each on the frame it was sent on, without choosing anything:

```sh
tools/qa/run_monkey.sh --replay=/tmp/ascendant-qa/<run>/events.log
```

The seed, faction, fog and interface size come from the log's `options` note, and the window size too unless you give
`--resolution`. A replay ends when the log does (a log that ended in a crash crashes again there, when the build still has the bug).
On a build with the fix, a replay is the check that the very input that crashed no longer does; the layout may differ there, so the
same clicks can land on other controls. Known limits: two things in the game read the wall clock (the first-game guide's linger
after turn 1, and the board's camera shake), so a run can drift from its replay after them; a replay notes `REPLAY WINDOW DIFFERS`
when the window isn't the run's.

## Check the harness itself

`--selftest=error|hang|crash` makes the monkey raise an error, stop the main thread or crash Godot after 5 gestures, so each of
`ERRORS`, `HANG` and `CRASH` can be seen end to end:

```sh
tools/qa/run_monkey.sh --seed=4 --turns=1 --selftest=hang
```

## Filing what it finds

One GitHub issue per finding, labelled `qa` (and `P0` for a crash or a stuck game), the owning lane in the title
(`QA ui: ...`, `QA 3d: ...`, `QA rules: ...`, `QA ai: ...`, `QA art: ...`), with the seed and steps, the replay command, a shot, the
log lines and the `next` sha. Read the open `qa` issues first and never file one twice. See `pipeline/LANES.md`, "QA".
