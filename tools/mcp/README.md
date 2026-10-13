# MCP toolkit: let an agent drive and inspect the running game (TOOL-3, #210)

[godot-mcp-toolkit](https://github.com/NPGameDev/godot-mcp-toolkit) is a Godot editor plugin plus an npm bridge that
speaks the Model Context Protocol. With it an agent can start the game from the editor, click and type in it, read any
node, run an expression in the live game, read the game's log and take screenshots, where `tools/shots` can only run a
script and photograph the result.

Nothing here changes how the game, the tests or a shipped build run. The plugin is **off in the committed
`project.godot`** and `tools/mcp/editor.sh` switches it on for one editor session (see "Why the plugin is off").

## What is installed (supply chain)

| Part | Where | Pinned to |
| --- | --- | --- |
| Editor plugin | `addons/godot_mcp_toolkit/` (MIT, license inside) | release **v1.0.3** (2026-10-05), commit `db005fc054155a0f977868fdfa34220b347fa8aa` |
| Bridge | `.mcp.json` runs `npx -y @npgamedev/godot-mcp-server@1.0.3` | exact version 1.0.3, published 2026-10-05, tarball sha1 `133499c6b9a0c0bc93bb077190418c99d4b96f13` |

- The tag `v1.0.3` is an annotated tag (object `14b68784546c161abac0b757bfe78d669bdde5f2`, not GPG-signed). The release zip's
  sha256 is `01f9aea9ef48ebf748d3073fed8ec1b42b251f5533e615caf1acaefcd8271c77`, which is the digest GitHub shows for it.
- The addon folder is the release unmodified, plus `icon.svg.import` (the import record Godot writes for the addon's icon, as
  for every asset in this repo). Check it: unzip the release and run
  `diff -r --strip-trailing-cr addons/godot_mcp_toolkit <unzipped>/addons/godot_mcp_toolkit`; only that file differs. Ten
  files carry CRLF line endings upstream; this repo's `.gitattributes` (`* text=auto eol=lf`) stores them with LF.
- The bridge's own dependencies are exact (`ws 8.21.0`, `zod 4.3.6`, `@modelcontextprotocol/sdk 1.29.0`), but the SDK's
  dependencies float, because the package ships no lockfile: 97 packages are installed in all, none with an install
  script. `npm audit` reports one high advisory on that SDK version (its OAuth *client* sending credentials to a server
  chosen by the remote MCP server); the bridge uses only the SDK's stdio *server* side, so it does not apply. To freeze the
  whole tree, install the bridge into a folder with a lockfile and point `.mcp.json` at its `dist/index.js`.
- Bumping: change the version in `.mcp.json`, replace the addon folder from the new release, update this file (the test
  `tests/test_mcp_toolkit.gd` checks that this file names the addon's version and the pinned bridge).
- Godot: the toolkit supports 4.2 to 4.7 and has its full tool set from 4.5. This project is on 4.5.1; nothing here needs 4.7.
- Node 22 or newer is needed (`npx` fetches the bridge on first use, then runs from its cache).

### Network skim (step 7)

Read the addon's `.gd` files and the bridge's published JavaScript (unpacked in a temp folder, not committed):

- Both WebSocket servers (editor, running game) bind `127.0.0.1` only (`BIND := "127.0.0.1"` in the addon, no setting
  changes it). Checked live: `lsof` shows `127.0.0.1:6550` listening, nothing on `*`.
- The bridge dials `ws://127.0.0.1:<port>` and, for the GDScript language server, `127.0.0.1:6005`. It contains no
  `fetch`, no `http(s)` module and no telemetry or analytics code. Its only web address is a "download Node.js" message.
- The one outbound call is in the addon: the dock's **Extensions** dialog downloads a catalog (`catalog.json` from a
  GitHub gist of the toolkit's author) when someone clicks that button. It sends nothing but the request, is never run by
  an agent session or at startup, and the dialog opens a repo link only after a user click and only for `https://`. Do not
  click it, or block the editor's outbound network, if that matters.
- Per-start auth: every connection must present the 64-hex session token, which lives in `user://` (never in a repo file).
- The plugin sets one machine-wide Editor Setting while a client is connected (`interface/editor/unfocused_low_processor_mode_sleep_usec`,
  so an unfocused editor answers at about 60 fps), and puts the previous value back on the last disconnect.
- It also keeps a machine-wide registry (`~/Library/Application Support/godot-mcp-toolkit/projects.json` on macOS) and
  never prunes it: entries of closed editors and removed worktrees pile up, and are ignored when their pid is dead.

## Setup

1. Node 22+ (`node --version`). Nothing to install by hand: `.mcp.json` starts the bridge through `npx`.
2. Your agent (Claude Code) asks once whether to trust the project's MCP server `godot-mcp-toolkit`; say yes.
   Restart the agent session after pulling this change so it loads the server.
3. Start the editor with the plugin:

```sh
tools/mcp/editor.sh              # windowed, always on top (an occluded window never draws)
tools/mcp/editor.sh --headless   # headless editor, see "Headless" below
tools/mcp/editor.sh --status     # what project.godot holds of the toolkit right now
tools/mcp/editor.sh --strip      # clean project.godot after an editor opened some other way, or a killed session
```

The script sets `GODOT` from your PATH or the usual Mac locations (override with `GODOT=/path/to/godot`). It prints the
editor's pid; close the editor or `kill <pid>` it when done. It stops only that editor. A fresh worktree needs
`godot --headless --path . --import` once first, as for everything else in this repo.

4. In the agent: the 36 startup tools are there. Ask it to play: *"start the game with seed 4242, order the Crown's 1st army
   to Westwatch, end the turn and tell me how the battle went"*. Or run the recorded walk yourself (below).

### Why the plugin is off in the committed `project.godot`

The issue assumed the plugin's runtime autoload is injected only during editor playtests. It is not: while the plugin is
enabled, **every time the editor loads it** (and on `godot --import` and `--export-pack`, which load plugins too) the
plugin writes `MCPRuntimeServer="*res://addons/godot_mcp_toolkit/runtime/mcp_runtime_server.gd"` into `[autoload]` and
saves `project.godot` (upstream's ADR 0013, "self-heal"; there is no switch to turn it off). The game reads
`project.godot` at F5, so that is how the runtime server gets into a playtest.

Measured here: with that line present, a plain `godot --headless --path . --quit-after 120` (no editor, no MCP) starts a
WebSocket server on `127.0.0.1:6570` and registers it in the machine-wide registry, because the Mac's Godot app is an
editor build (`OS.has_feature("editor")` is true). Tests, boot checks, autoplay workers and screenshot runs would all do
that, and the band holds only 16 listeners, so a busy machine (the autoplay matrix, several builders) can run it dry. If the plugin were enabled in the committed
file, the first `--import` in every fresh worktree would write the line and dirty `project.godot`.

So the committed file is untouched. `editor.sh` calls `tools/mcp/project_plugin.mjs enable` before the editor starts and
`strip` when it exits: strip removes the plugin entry, the autoload line and any `[mcp_toolkit]` settings, and keeps every
other edit made meanwhile. `tests/test_mcp_toolkit.gd` fails while any of them is left in `project.godot`.
If the team prefers the plugin on for everyone, add `enabled=PackedStringArray("res://addons/godot_mcp_toolkit/plugin.cfg")`
under `[editor_plugins]`, and expect to run `editor.sh --strip` before commits.

## Which tools an agent gets (step 3)

The bridge already loads its surface lazily: a session starts with **36 tools** (34 always-on plus `discover_tools` and
`extensions_refresh`; upstream measures about 8,800 tokens), and 78 more sit in 28 groups that an agent switches on with
`discover_tools({request: ["group", ...]})`. Measured with `node tools/mcp/mcp_call.mjs counts`:

| Profile | Tools | How |
| --- | --- | --- |
| Everything (28 groups on) | 114 | `counts --activate all` (the toolkit's "112" plus its two meta tools) |
| **Walk (recommended)** | **42** | the 36 at startup plus `discover_tools({request: ["runtime_advanced", "editor_advanced"]})` |
| Inspect only | 16 | `GODOT_MCP_READ_ONLY=1` in `.mcp.json`'s `env`: no `game_start`, no `input_simulate`, no `execute_code`, so it cannot walk |

The two groups for a walk: `runtime_advanced` (`runtime_get_node_state`, `runtime_set_property`, `animation_player_control`)
and `editor_advanced` (`editor_screenshot`, `editor_refresh`, `editor_wait_for_idle`). Everything else a walk needs is in the
startup set: `game_start`/`game_stop`, `input_simulate`, `runtime_screenshot`, `execute_code`, `runtime_get_script_vars`,
`debugger_get_log`, `editor_get_console`, `scene_get_tree`/`scene_query`/`node_get_property` (editor scene). Leave the other
26 groups (tilemaps, audio, animation authoring, LSP, `user_data` and so on) alone. Groups are per bridge process: a new
agent session starts with 36 again.

Risky tools in the startup set: `execute_code` and `node_call_method` run code, `script_write`/`script_edit` and
`scene_*`/`node_*` edit files, `project_set_setting` and `autoload_manage` write `project.godot`. Block what an agent should not
touch in `.claude/settings.json`, for example
`{"permissions": {"deny": ["mcp__godot-mcp-toolkit__autoload_manage", "mcp__godot-mcp-toolkit__project_set_setting"]}}`.

## The walk recipe

`tools/mcp/mcp_call.mjs` is a small JSON-RPC-over-stdio client. It starts the bridge exactly as `.mcp.json` says, then runs
`initialize`, `tools/list` and `tools/call`; it is how this was proven without loading a new MCP server into an agent session.

```sh
node tools/mcp/mcp_call.mjs list                              # the startup tools
node tools/mcp/mcp_call.mjs counts --activate all             # 36 at startup, 114 with every group
node tools/mcp/mcp_call.mjs call editor_get_console '{"limit": 5}'
node tools/mcp/mcp_call.mjs run tools/mcp/walk_turn1.json     # the recorded walk, 53 steps
```

Options: `--project <dir>` (the bridge's cwd; this is how it finds that project's editor), `--env K=V`, `--out <dir>`,
`--full`, `--timeout <ms>`. Any 64-hex string in output is replaced with `<redacted-64hex>`. A recipe step can `capture` a
result for later `${name}` use, `expect` text, or repeat `until` text shows up.

`walk_turn1.json` (editor running, game not required) does this, all through the real UI:

1. `game_stop`, `game_start`, wait until the new game answers (the first poll can read the previous game's registry entry).
2. Title: `click_node` New game. Seed: empty the box, `send_text` `4242`, read the config back (`"seed":4242`).
3. `click_node` Choose builds, then Lock in build (the balanced preset is already picked). Wait for the GameScreen and for
   the 3D board to stop saying "Raising the land...", and switch the autosave off.
4. Turn 1: `click_node` the army's row, `mouse_motion` over Westwatch (the army card shows the march forecast), `click` the
   province: the session reports `Move the Crown's 1st (...) from Crownkeep to Westwatch.`
5. `click_node` End turn. Wait for the battle host; read the battle (`BattleHost.current_event()`: strengths 82 against 48,
   `held_vs_arrival`, winner Aurel Crown after 2 rounds, with the rules' own "why" text); `click_node` Skip to end, then Close.
6. Read the board back from the game state (Westwatch owner `kingdom`, the army at `westwatch`) and from the map's own
   nodes; read the game's log and the editor console; `game_stop`; `editor_screenshot`.

Seven screenshots (title, turn 1, hover forecast, order placed, battle deployed, battle result, map after the turn) come back
as files (`image_response_mode: "disk"`; a 1600x900 3D screenshot is about 1 MB, too much to carry inline, see Gotchas).
On the author's Mac (a busy one, with other builders' Godot runs going) the whole recipe, game start included, took 93 s.

### Driving the running game: what works

- `input_simulate` with `click_node` (finds the node, grabs focus, emits `pressed`), `click`/`mouse_motion` at viewport
  coordinates, `send_text` into a LineEdit. Ask the game for coordinates: `execute_code` with
  `get_tree().current_scene.get_node('Map').regions['westwatch'].get_global_rect().get_center()`.
- Read the live scene tree: `execute_code` with `get_tree().current_scene.get_tree_string_pretty()` (the 3D board makes it long:
  add `.substr(0, 3000)`), or `find_children('Name', '', true, false)` for a path. `scene_get_tree`/`scene_query` read the
  *edited* scene, not the running game.
- Read game objects through the nodes: `get_tree().current_scene.session.state()`, `.session.current_order_texts()`,
  `get_node('Overlays/BattleHost').current_event()`.

## Compared with `tools/shots`

| | `tools/shots` (`play_shots.gd`) | MCP walk |
| --- | --- | --- |
| Drives the game by | its API (a second AI gives the person's orders), UI input switched off | real clicks, typing and hover on the real screens |
| Shape | one scripted, deterministic batch: 40 turns, a shot every few turns, `walk.md` | closed loop: an agent looks, decides the next click, looks again |
| Same turn, same seed | 59 s for 1 turn and 4 shots here | 93 s for 1 turn, 7 shots and the battle, warm |
| Inspect | what a PNG shows | any node, any property, the session's state, the battle event, the log |
| Where it runs | a scratch SceneTree, its own saves folder | the editor-launched game, the player's own `user://` |

New: it catches what only real input shows (wiring, hover forecasts, clicks landing on the wrong node: the walk found the
"Raising the land..." window where clicks land on nothing), it needs no script per scenario, an agent can look at a result and
try something else, and the editor side (scene tree, `script_check`, console) comes with it.

Worse: a tool call per click (about 50 for one turn) instead of one script; slower and chattier for long runs; not
deterministic by itself (the real title flow, the real settings, a random first seed unless typed); needs a window on a
display (the headless editor cannot start a game); one game per editor and 16 per machine (ports 6570-6585); and it shares
`user://` with the player (see Gotchas). Recommendation: keep `tools/shots` and the playtest bots for long, repeatable
runs; use MCP when a human or an agent wants to *try* something on the real screens. Moving the bots onto MCP would trade
their speed and determinism for nothing, so it is not worth it.

## Headless

`tools/mcp/editor.sh --headless` (`godot --headless --editor`) works on the Mac: the plugin loads, the server listens, and
`project_get_settings`, `scene_open`, `scene_get_tree`, `node_get_property`, `classdb_get_info`, `editor_get_console` and
`script_check` answer. `editor_screenshot` and `game_start` return `HEADLESS_UNSUPPORTED` (no display, no game), so no
runtime tool works. Use it for file, scene and node work only.

## Parallel worktrees (step 6)

Each editor binds the first free port of 6550-6560, writes its own session token under `user://.../project_instance_<hash>/`
(the hash is of the project path) and records `{port, token path, pid}` under its absolute project path in the machine-wide
registry. The bridge finds its editor by looking up **its own working directory** (or `GODOT_MCP_PROJECT_PATH`) in that
registry: no port scan. Tried with two worktrees: A (windowed) on 6550 and B (headless) on 6551, different tokens; a bridge
started in A answered with A's console (`registered .../agent-afb2b0abc679af02e on port 6550`), one started in B with B's
(`registered .../tool3-b on port 6551`).

Cross-connection was tried and refused: a bridge whose project has no editor falls back to **port 6550**, connects (that is
another worktree's editor) and is turned away at authentication, because the token it can read is not that editor's; a bridge
pinned with `GODOT_MCP_EDITOR_PORT=6550` from B is refused the same way. Two things to know: the bridge must run with the
worktree root as its cwd (a subfolder gets "no registry entry"), and two editors on the *same* path are not supported.

## Gotchas

- **Saves and settings.** The editor-launched game uses the player's real `user://` (`~/Library/Application Support/Godot/app_userdata/Ascendant`):
  it autosaves a new game at once (rotating the player's three autosaves out) and writes hint flags to `settings.cfg`. The recipe
  switches `autosave_enabled` off right after the game screen appears, but the very first autosave still lands: back up
  `saves/` and `settings.cfg` first (or restore them after, as was done here).
- **Unsaved edits** (from the issue; not exercised in this walk). The plugin's file tools write to disk and the editor
  reloads them: an agent that writes a script the editor has open drops that script's unsaved edits. Save in the editor
  first, or keep the agent off open files.
- **Big 3D screenshots.** `runtime_screenshot` and `editor_screenshot` take `image_response_mode: "disk"` (the file lands in
  `user://screenshots/` at full size, the reply is just the path); inline PNGs of the 3D board eat the context. `image_detail`
  `low` or `mid` shrinks an inline one.
- **`--always-on-top`.** `editor.sh` passes it. An occluded window never draws, so a windowed run behind other windows hangs
  or returns blank frames. A game started from a minimized editor leaves it minimized; `editor_screenshot` needs
  `force_foreground_editor: true`, `runtime_screenshot` has `force_foreground_game`.
- **Cold start.** `game_start` waits 10 s for the game; a cold 3D start takes longer. Poll with
  `game_start({if_running: "return", runtime_poll: true})`, and prove the game is up with a call that reaches it: the poll can
  read the registry entry of the game that just stopped.
- **The 3D board needs a moment.** The game screen appears while the board still shows "Raising the land..."; orders clicked
  then land on nothing. Wait for `Map/MapView/Board3D.prepared`.
- **`execute_code` is an expression, not a script.** No statements, no lambdas, no assignment, and no singletons, autoloads or
  `class_name`s: reach everything through nodes (`get_tree().current_scene`...). `str(...)` what you return.
- **Generated node names** (`@VBoxContainer@235`, `@Button@1116`) change between runs: find the node (`find_children`) and
  use the path it returns. `send_text` types at the caret: empty the box first. In this walk `key` events (Space, End) did not
  reach the battle controls; `click_node` on the button did.
- **`script_check` is not this project's compile check.** It compiles one script alone, so any script that names a
  `class_name` of the project comes back as a compile error (seen on `rules/game_session.gd` and `rules/army.gd`, which
  compile fine). Use `tools/compile_check.gd`, or the LSP tools
  (`discover_tools({request: ["lsp_code_analysis"]})`) with the editor's language server on port 6005 (one per machine: only the
  first editor gets it).
- **Logs are shared.** Worktrees share one `user://logs/` (same project name), so `source: "file"` mixes sessions; use
  `source: "buffer"`.
- **Editor console noise.** `send_text failed ... response not delivered` warnings appear when a short-lived client
  disconnects before an answer is sent. Once per editor session, the first `extensions_refresh` printed a burst of Godot
  errors from the toolkit's filesystem rescan (`Do not use progress dialog ... while flushing the message queue`); harmless.
- **The dock's "Write .mcp.json" button writes `npx -y @npgamedev/godot-mcp-server` with no version.** Do not click it; the
  committed file is the pinned one and the test checks it.
- **Only editor-launched games.** The runtime server starts only when `OS.has_feature("editor")`, so an exported build cannot
  be driven, by design.
- A hard kill of `editor.sh` (SIGKILL, a crash) skips the clean-up: run `tools/mcp/editor.sh --strip`.

## Exports (step 5)

`export_presets.cfg` has one preset, `macOS`, with `exclude_filter="addons/godot_mcp_toolkit/*"`. The addon folder is not
needed in a game and its scripts would otherwise ship as compiled `.gdc` files (the toolkit warns about this itself).
`tests/test_mcp_toolkit.gd` checks that **every** preset leaves out every file under the addon folder (the folder is found
from `plugin.cfg`, not named). No export templates are needed to prove it:

```sh
godot --headless --path . --export-pack "macOS" /tmp/test.pck
node tools/mcp/pck_check.mjs /tmp/test.pck       # 0 paths under the addon, no .mcp.json, no toolkit autoload
```

With the filter: 0 files under the addon, the autoloads in `project.binary` are `World3DLaunch, Audio` only. Without it (a
control preset made for the check): 252 addon files in the pack. With the plugin enabled and the autoload present at export
time, the toolkit's own export plugin takes the autoload out of the bake (the check passes in that state too).

## Not in scope

`tools/shots` and the playtest bots are untouched; see the comparison for why they stay.
