# ui/battle: battle playback

Everything that plays a battle back from its event log (`design/M3_BATTLES.md`, `design/3D_DIRECTION.md` §7).
Playback is a pure function of the log: nothing in this folder draws a random number or calls the rules,
and watching never changes the game (tests check this at three levels).

| file | what it is |
|---|---|
| `battle_host.gd` | `BattleHost` (M3-5): **the one place the game opens a battle.** Queue, Next/Previous, the view choice, the stings, the settings panel. |
| `battle_player.gd` | `BattlePlayer` (M3-3): the renderer-agnostic clock, beats and state. No nodes. |
| `battle_simple_view.gd/.tscn` | `BattleSimpleView` (M3-3): the 2D Simple view, a battle view (below). |
| `battle_controls.gd` | `BattleControls` (M3-4): the controls, keys, scrubber; M3-5 adds the queue row and Settings; UX-8 lays them out as the bottom bar (the scrubber's clickable moment markers replace the moment buttons), the queue row above it and the Why tab. |
| `battle_why_panel.gd`, `battle_why.gd` | the why panel and its pure model (M3-4). |
| `battle_legend.gd` | the legend (M3-4). |
| `battle_selection.gd` | Tab / click selection and pinning (M3-4). |
| `battle_fx.gd` | flash and shake limiters, pools, sounds and the `[battle]` settings (M3-3/M3-4/M3-5). |
| `battle_watch.gd/.tscn` | a standalone launcher for playtests: `godot --path . res://ui/battle/battle_watch.tscn -- --fixture king_falls_wins` |
| the rest | the Simple view's drawing helpers (cards, layout, bars, effects, backdrop, scrubber). |

## Opening a battle: `BattleHost`

```gdscript
var host := BattleHost.new()            # a full-rect Control overlay; GameScreen keeps one on its Overlays layer
host.open(events, start_index, session, viewer)   # "" or why nothing can be watched
host.next(); host.previous(); host.close()
# signals: closed, codex_requested(key), report_requested(event), battle_opened(index)
```

- `events` are battle events in report order (other events are left out). The host plays
  `events[start_index]`; **Next battle** (N) moves on, **Previous battle** (Shift+N) goes back, and the last
  battle's Next, Close or Esc closes the host, which shows whatever opened it again (the turn report).
- `session` (optional) gives the 3D stage the game state and both views the seat colours. Nothing is read
  from it but `state()` and `players()`.
- `viewer` is the faction watching: at a battle's result, its side's **victory or defeat sting** plays over
  the ducked battle music ("" for nobody in particular, e.g. watch mode: no sting).
- `host.rebuild_with = func(event) -> {"log", "errors"}` rebuilds a log that isn't kept (the game screen
  replays the game record with `BattleLog.regenerate` and checks the result against the report). Meanwhile
  the host shows "Regenerating this battle's playback from the game record…".
- Battles that can't be watched say why, both on the Watch buttons (`BattleHost.watch_problem(event)`) and in
  the host if one is opened anyway: fought with the test rules (no log), a log cut short at
  `BattleLog.MAX_EVENTS`, or a log that isn't kept and can't be rebuilt.
- **Any number of sides** (#265): a Free Holds garrison caught between two players fights a three-sided battle,
  and so will the Candlewake. Both views play it. On the Simple view's field (`BattleLayout`) the lone side (the
  defender, else side 0) holds a half alone and the others share the other half, each in its own band. The top
  bar has a side plate per side: the left half's plates, the centre, the right half's, each plate's morale tag
  under it, all in plate order for Tab (`layout.order`, `layout.groups`, `plate_of(si)`). The why panel and
  the result card name each side and when it left the field (`BattleWhy.how_it_ended`). Two sides lay out
  exactly as before. `tests/three_side_fixtures.gd` fights three of them with the real rules, and both
  launchers play them (`--fixture three_holds`, `three_fort`, `three_rivals`).
- The view comes from the setting **Battle view** (`[battle] view` in `user://settings.cfg`: `3d`, the default
  since M3b, or `simple`). The 3D stage is `world3d/battle_stage.tscn` (`BattleStage3D`, see `world3d/README.md`);
  if `BattleHost.stage_3d_path` is missing, `3d` plays in the Simple view and the host shows a short note.

## The battle view contract (what the 3D stage implements)

A battle view is a **Control** (the 3D stage: a Control whose child is a `SubViewportContainer`, or any
Control root over the 3D scene) that the host adds full-rect. Kept as small as possible:

```gdscript
## Plays the battle. `state` is the game state (a copy: the province's ground, woods, village and fort for
## the 3D stage; the Simple view ignores it); `seats` is GameSession.players() for the seat colours ([] =
## the data's faction order). Returns "" when it plays, or the plain reason it can't (the host shows it).
func play(battle_log: Dictionary, report: Dictionary, state: GameState, seats: Array) -> String
func close() -> void        # stop, hide, end the battle music (GameAudio.battle(false)), emit closed
signal finished             # the result is on screen (at the end of playback, or after Skip to end)
signal closed               # the player closed the view (its Close button, Esc)
var controls: BattleControls   # the shared control bar it hosts; a BattleControls once play() has returned
```

And it hosts **the same components** on top, so the 2D overlay is identical in both views:

```gdscript
var player := BattlePlayer.new(battle_log, report)   # the clock, beats and state; the stage only draws them
controls.bind(player)            # BattleControls: scrubber, buttons, §5.3 keys; controls.fit(view_size, band, tab_right) lays it out (UX-8)
why_panel.bind(player, selection)   # BattleWhyPanel, WHY_W wide down the right edge under the side plates
legend.set_rows(BattleLegend.overlay_rows() + stage_rows)   # BattleLegend
selection.bind(player, tab_order)   # BattleSelection: a raycast pick -> selection.toggle(fid)
# every frame: player.advance(dt); controls.tick(dt); why_panel.tick(dt)
# input: if controls.handle_key(event): handled.  The view keeps Esc (legend first, then close()) and F1.
```

Optional, picked up when present: `signal codex_requested(key)` and `signal report_requested(event)` (the
result card's Full report: the host opens the battle report viewer over it), and `var reduced_motion` /
`var screen_shake` (the host sets them from the settings before each `play`).

What the host does with the contract, so the view doesn't have to:
- the queue row on `controls` (`set_queue`: "Battle 2 of 3: Battle of Thornvale", ◂ Previous battle,
  Next battle ▸ / Back to the report) and its keys (N, Shift+N); `controls.next_requested` is also what a
  result card's own Next battle button should emit;
- the Settings button on `controls` (`show_settings(true)`, S): the settings panel over the battle, with
  playback paused while it is open;
- the victory and defeat stings on `finished`, from the viewer's side;
- the fallback to the Simple view, and the messages for battles that can't be played.

**The 3D stage (M3b)** is at `res://world3d/battle_stage.tscn`: `BattleStage3D` extends `BattleSimpleView`, so it
inherits `play()`, `finished`, the result card's Next battle and every shared component, and swaps the card field
for the land. `tests/test_battle_host.gd` has a stand-in stage that shows what the host expects;
`tests/test_battle_stage3d.gd` runs the real stage through the host.

## Where battles are opened from (M3-5)

- **Turn report:** every battle row has **Watch** beside "Battle report", disabled with the reason when the
  battle can't be played back. The top of the report has **Watch your battles (N)** (your faction's battles,
  in report order; "Watch the battles (N)" when nobody in particular is at the controls).
- **Battle report viewer:** **Watch** in the header beside Close.
- **Auto-watch** (Settings > Battles > "Watch my battles": at the start of each turn, off by default): your
  battles' queue starts once the turn's playback on the board has finished and the turn report has opened,
  and only after the handoff in a hotseat game, for the player at the controls only. Esc goes to the report.
- The computer's battles are watchable exactly like a person's.
