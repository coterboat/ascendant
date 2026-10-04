# The 3D world (`world3d/`)

The game's map as a living 3D board (design/3D_DIRECTION.md). Since **M3a.1** it is the map of every game:
the map screen's 2D UI sits over it, every order and tooltip works through it, and each resolved turn plays
out on the land before the turn report opens. Settings → Board switches back to the 2D map. The rules
(`rules/`, `data/`, `ai/`) don't know it exists: the board only reads the state, the orders and the
resolver's events.

## The board in the game (M3a.1)

    GameScreen (ui/game_screen.gd)
      Map (MapScreen, ui/map_screen.gd): top bar, side panel, orders, hover preview: unchanged 2D
        MapView
          Board3D (world3d/board3d.gd, a Control under everything else in the map view)
            World (SubViewport, own World3D, at the screen's physical pixels; renders only while live)
              WorldView (world_view.gd): land, sea, sun, woods, villages, fortresses, the camera rig
                Armies (armies.gd): formations, ghost recruits, turn playback
            BoardOverlay (board_overlay.gd): names, incomes, count plates, ghost plates, order arrows,
                                            clash markers, the playback bar, the legend: 2D, projected
          MapCanvas (the 2D regions: hidden, but kept for their tooltips and marks), HoverPreview

- **Who knows the game:** the map screen. The board picks what is under the mouse (the territory id of
  the land at the unprojected point; an army whose figures' screen box holds the point) and calls the
  map's own `select_province`, `select_army`, `preview_move`, `request_codex`, so the signals, two-click
  moves, King's Roads, forecasts and the codex work exactly as on the 2D map. The map calls
  `board.sync()` whenever its state, selection or orders change; the board mirrors them: owners
  (`set_owners`), the ground's highlights (`set_highlights`, `set_marks`), the armies, ghost recruits.
- **Picking and projection** are computed in `world_view.gd` (`project3`, `screen_ray`, `unproject`) from
  the rig, not asked of the Camera3D, so they work headless (tests) exactly as windowed.
- **Highlights on the ground** (ground shader, constant screen width): the selected province's white band,
  the hovered one's cream band, a gilt glow inside the provinces the selected army can march to, a dashed
  gilt band on King's Roads destinations, a white flash when the camera glides to a province (a turn
  report line). The owner's wash (a 30% multiply) and a keylined 4 px inner band in the owner's colour.
- **The 2D over it** stays minimal (the 3D armies are the markers): a name plate per province (crown on a
  capital, tower on a fort) with its income (breakdown and codex link on hover), a count plate per army
  (emblem and units, the 2D badge's tooltip; a click selects), a "+N queued" plate over ghost recruits,
  the order arrows (each queued move drawn along the roads it marches, a King's Roads move through its
  middle province's centre, ringed in gilt; a dashed gilt preview of the move a click would order), Sworn
  Vassals pennants and heir countdowns mirrored from the map's regions, and the legend (its tooltip
  explains every mark on the land).
- **Turn playback** (`GameScreen._play_on_board`, `Board3D.play_turn`): from the start-of-turn state,
  through the report's events, to the state after. `playback.gd` turns the events into beats: marches
  (out of the gate two abreast, along the roads, a road move through its middle province), border
  battles' losers marching to the crossing, battles (a clash marker at the site; the losers topple),
  captures (the land recolours as the new owner's column arrives), recruits and new rulers (they fade
  in as everyone re-forms in their place of the state after). The camera frames the battles (or the
  player's own columns). Space or a click skips; 1×/2×/4× on the playback bar, remembered in the
  settings. The report opens after it. Every hotseat player sees it once, behind their own handoff.
- **Covered, it stops rendering:** the SubViewport updates only while the board is visible and no
  handoff cover or modal overlay is up (`cover_check`); it then keeps its last frame.
- **The quality ladder** (`world_view.gd set_quality`) steps down after 3 s under 40 fps. The woods drop
  their ink outline beyond the near zoom (the spike's dearest whole-map pass), and the overlay re-places
  its plates only when the camera moves, a turn plays or the map changes.
- **Measured** (Apple M4, Metal, Look A, 1600 × 900 window, 3D at 1200 × 838, rung 0, vsync off, a shared
  machine): orders 74 fps over the whole map, 96 panning at the default zoom, 85 close on a capital; a
  turn's playback 61; 240-360 draw calls.
- **Built off the main thread:** `Board3D.prebake()` (started by the `World3DLaunch` autoload at boot when
  the board is 3D) bakes the land, plans its trees and cottages (`WorldView.plan_of`) and loads the model
  table's meshes on a worker; the world's nodes are built in one go when the game screen shows it.

## The armies (M3a.2)

The goal: watch each turn resolve on the land and predict the next battle from what mustered.

- **Pose swaps** (`models.gd`, `choreo.gd`): a figure stands in one of four poses, each its own GLB when the
  row has one: `ready` (standing, holding, re-forming), `march` (filing out, on the road, marching in,
  gathered), `strike` (a clash's blow), `fallen` (the dead). Procedural motion goes on top: a march hops
  and sways, a strike lunges a quarter of the gap and back, a struck figure recoils, the dead topple
  about the feet and then lie in the fallen pose, winners cheer. A pose with no model shares the ready
  mesh. Each army draws **one MultiMesh per unit type and distinct pose mesh**, compacted every sync
  (`visible_instance_count`), so a pose draws only its own figures. Variety comes from hashes of ids.
- **Muster yards** (`muster.gd`, pure): a capital's yard is a grid of block slots sized from its
  courtyard (3 across, 2 deep: 6 blocks of up to 8 at drill spacing; a big or large block takes the next
  slots). An army takes its slots in id order, whole: its **colour party** (ruler or commander, the
  standard bearer, the musician) first, then its blocks by battle rank. Only the owner's armies use the
  yard. Every army the yard can't hold musters in the **war camp** outside the gate, beside the road: a
  tent behind every block (the row `camp.<faction>`'s model, else a primitive tent), a fire and its smoke
  for every army there (`shaders/smoke.gdshader`, billboards rising by TIME and instance hash).
- **Planning cues, the viewing player's own orders only** (`Board3D.plan_of_orders`, `Armies.show_plan`):
  each queued recruit stands as a ghost in the slot it will take (the next place in its army's block, or
  a slot of its own, or the camp when the yard is full); an army ordered to march **gathers in a column at
  its gate** (or its stage's edge), banner at the head, facing its road, with a gilt arrow on its plate;
  the rest of the yard closes ranks. Another seat's orders never reach the board (tested: seat 2's board
  is identical whatever seat 1 queued).
- **The fortress close-up** (`Board3D.enter_closeup`): View fortress in the recruit panel (or a
  double-click on a fortress) swoops the camera into the yard, turned to look in through the gate, with
  a compass. The gate side's walls turn into a sparse dither and cast no shadow (`model_common`
  `cut_plane`), so every block reads; the yard gets a little more ambient light. The recruit panel stays
  2D and each queued recruit appears at once. Esc, zooming out, F, C, selecting another province or a
  playback leaves it.
- **Turn playback in the report's phases** (`armies.play`): **Movement** (columns file out of the gate
  and march; armies bound for a battle stop at its front), **Battles** (in the report's order: defenders
  step out to their line, before their gate at a fortress; a side's armies stand shoulder to shoulder; the
  lines trade alternating volleys of strike poses and lunges, the struck recoil, the dead topple and lie,
  the winners cheer; a border battle's winners then march on), **Captures** (the new owner's colour
  sweeps out from the arriving column with a gilt front, `ground_common` `sweep_a`), **Recruits**
  (recruits march in through the gate, or appear at the edge of the formation elsewhere, and everyone
  settles). Each phase shows a caption with what is happening and pips on the playback bar; empty phases
  are skipped. The camera leans in on each battle.
- **Sounds at their beats** (`Board3D._on_beat`, `Choreo.sound_for`): march, battle_clash, strikes
  alternating battle_hit and battle_clash by the beat's index, unit_fall, the capture fanfare
  (capital_captured) and recruit, through `GameAudio.sfx`. Never an RNG; sound never changes anything.
- **Watch this turn again**: the turn report's button replays the turn on the board, then reopens the
  report. The game screen keeps the turn's start with its report, so every hotseat seat sees the
  playback behind its own handoff.
- **The world from the model table**: forts (the nearest capital's faction's `fort.<faction>`, beside the
  stage, roofs in the owner's colour), a village per province (`village_<terrain>`, the variant by a hash
  of the province id) and landmarks (a mill on the plains, a watchtower in the hills, standing stones in
  the woods, on two provinces in three by hash), the trees and rocks as models close in (normalised to
  their primitives' size, in 200-unit chunks the camera culls; the primitives stay the far LOD and the
  quality ladder's fallback from rung 2), the standard bearer and musician per faction (`models`,
  `model_height`).
- **Readability**: a man-sized figure never stands under 26 px on the board (piece scale grows as the
  camera rises, `Board3D.MIN_FIG_PX`); figures get a higher shadow floor and a soft rim (`fig_lift` in
  `model_cel`), so a face under a brim stays readable; pale near-neutral stone on every building is
  pulled to a warm grey of compressed lightness (`stone_grade`), so Look A's sun neither blows it out
  nor tints it pink. Figures cast shadows only from the default zoom in.
- **Tests**: `tests/test_armies3d.gd` (poses and motion, pose models and their MultiMeshes, the muster
  layout's determinism, fit and overflow, ghosts' slots, the board's camps, gather cues, hotseat privacy,
  the close-up, phases, captions and beats, the battle exchange, sound never changing anything, capture
  sweeps, every seat's playback and Watch again, no random numbers in `world3d/`, the playback's CPU),
  and `test_board3d.gd`'s playback = state over three games with a plan standing before each turn.

### Camera and keys

Drag (or the middle button) pans with the ground under the hand; the wheel (or + and -) zooms to the
cursor, the pitch easing from 60° over the whole map to 42° close in; WASD or the arrows pan;
double-click glides to a province; **C** (or Home) your capital; **F** the whole map; **L** Look A (Bright
Cel, the default) or Look B (lit painted). Look A borrows Look B's glossy sea close in. The whole map is
framed on start. Figures stand up to 2.4× taller far out (toy scale), so every army reads as a marker.

### The model table (`world3d/models.json`)

One descriptor table maps every unit type and building kind to a model or a primitive piece, so the
generation job's GLBs drop in without code changes (`world3d/models.gd` reads it; `tests/test_board3d.gd`
fails on a unit type without a row or a row whose model is missing).

    {
      "block": {"per_unit": 1.0, "min": 2, "max": 8},
      "figures": {
        "<unit type id>": {
          "faction": "kingdom",            // for the path convention below
          "model": "res://assets/models/kingdom/spearmen/spearmen_ready.glb",   // "" = primitive
          "height": 1.3,                   // the model's full height (AABB, weapon included) in men; a man is 6 world units
          "yaw": 180,                      // degrees to turn it to face -Z (glTF faces +Z: 180)
          "fallback": "spearmen",          // the Kit.figure drawn when there is no model
          "scale": 1.0,                    // scales the fallback (a ruler or a monster stands bigger)
          "rank": 0,                       // the block's battle rank: 0 front, 1 second (Volley), 2 back (commanders)
          "large": false,                  // mounted or beast: wider spacing
          "ruler": false                   // a ruler: the gilt ring round its base
        }
      },
          // M3a.2, optional:
          "poses": {"ready": "res://...", "march": "...", "strike": "...", "fallen": "..."},
                                           // a GLB per pose (or {"model": path}); a pose without one draws the
                                           // ready model; rulers may add "cheer" (shown as ready for now)
          "pose_size": {"<pose>": {"axis": "height" | "length" | "width", "men": 1.1}},
                                           // each pose's own scale (a lunge or a lying figure keeps the ready
                                           // pose's body size); without it: the row's height (fallen: its length)
          "models": {"<faction id>": "res://..."}, "model_height": {"<faction id>": 1.2}
                                           // army extras (bearer, musician): the model per owner's faction
        }
      },
      "buildings": {
        "<kind>[.<faction id>]": {         // "fortress.beasts" is the Clans' kit variant of "fortress"
          "model": "res://assets/models/probe/crownkeep.glb", "fallback": "fortress",   // fortress, fort, cottage, broadleaf, pine, rock
          "side": 76.0, "yaw": 180, "sink": 2.0,       // footprint (world units), turn, how far its slab sinks into the stage
          "key_hue": 0.62,                 // the hue repainted in the owner's colour (the roofs); -1 none
          "tint": 0.86,                    // whole-model brightness (keeps pale stone from blowing out in Look A)
          "stone": "#C98F5E",              // multiplies the texture (not the keyed roofs): a kit variant's stone
          "palisade": true,                // a ring of stakes round the walls (the Clans' variant)
          "court": [x, z, w, d], "gate_z": [inner, outer], "banner_at": [x, height], "floor": 0.25,  // the yard, in the model's frame
          // M3a.2, optional:
          "muster": {"slots": 6},          // a fortress yard's block slots (default 6, or what the court fits)
          "grade": 1.0,                    // pale stone pulled to a warm grey (0 off; buildings default 1)
          "variants": ["res://..._a.glb", "res://..._b.glb"]   // interchangeable models (villages): one per
                                           // province by a hash of its id
        }
      }
    }

- **Lookup order for a figure:** the row's `model` (or `poses.ready`) if the file exists; else the bible's
  path convention `assets/models/<faction>/<unit>/<unit>_<pose>.glb` (STYLE_BIBLE.md 8.10); else the
  primitive `fallback`. An extra (bearer, musician) uses `models[<owner's faction>]` first.
- **Kinds the board reads (M3a.2):** `fortress[.<faction>]`, `fort.<faction>`, `camp.<faction>`,
  `village_<plains|forest|hills>` (with `variants`), `mill`, `watchtower`, `standing_stones`,
  `tree_broadleaf`, `tree_pine`, `rock`. A missing model always falls back to the primitive.
  A unit type with no row stands as Kit's generic figure.
- A model is normalised from its AABB (feet at y = 0, facing -Z, `height` men tall), keeps only its base
  colour texture (drawn with the game's cel or lit material and the ink outline), and gets a base in the
  player's colour (and a gilt ring for a ruler): identity is drawn in code, never in the art.
- **Blocks:** one block per unit type in an army, `ceil(count × per_unit)` figures between `min` and
  `max` (the direction doc proposes one figure per two units; the table ships one per unit, at least 2,
  so an early army of 3 units reads as an army). The plate carries the exact count.

### Tests

`tests/test_board3d.gd`: the model table; project/unproject round trips and a click on every province and
army at three zooms; selection through the board driving the map screen's signals, two-click move, hover
preview, tooltips and codex; owners, armies and ghost recruits following the state and the orders; the
handoff and overlays covering it; the 2D board setting; **playback = state** (applying each turn's events to
the board model of the state before gives the board model of the state after, 5 seeds × 12 turns with and
without rulers; a played board stands exactly as one built from the state after; the states are deep-equal
before and after); a game where the report waits for the playback; and a static check that the board's
code never rolls dice or resolves a turn. `tests/test_world3d.gd` keeps the spike's land tests.

# The spike (PR #81, `spike-3d-world`)

A real 3D world map for ascendant, built from the real rules, to judge the look and the cost before the art
budget is committed. It was a dev preview; the preview scene is still there for looking at the land on its
own.

## Run it

    godot --path . -- --world3d                          # from the normal launch (world3d/launch.gd)
    godot --path . res://world3d/world_preview.tscn      # or straight in

Options after `--`: `--look=cel|painted`, `--start` (turn 0 instead of a mid-game), `--turns=N`,
`--primitive` (primitive figures instead of the model table's GLBs), `--primitive-fort`, `--shots=DIR` (the evidence screenshots, then quit),
`--perf=FILE [--stress=2.0] [--quick]` (fps, then quit).

Keys: **1** whole map, **2** Crownkeep, **3** Fangridge, **Space** play the next real turn, **R** reset,
**L** look A/B, **P** model table figures or primitives, **F** Ludo/primitive fortress, **Q** quality step, **E** effects,
**O** orbit (then right-drag turns), **Esc** title. Drag pans (the ground stays under the hand), the wheel
zooms to the cursor.

## What's in it

| File | What it does |
|---|---|
| `terrain3d.gd` | Pure: bakes the land from `MapLayout` centres and `MapData` (territories, coast, borders, walls, heights, stages, roads). Seeded, mirror-symmetric, ~0.6–1.4 s, built on a worker thread. Unit-tested. |
| `world_view.gd` | The world: ground, sea, sun, sky, fog, woods and cottages (MultiMesh), fortresses and forts, the camera rig, `project` / `unproject`, the two looks, the quality ladder. |
| `armies.gd` | The armies as formations of miniatures (one MultiMesh per army and unit type), mustering in the courtyard, turn playback (march-out, column, hop, re-form, topple). |
| `kit.gd` | Placeholder pieces from primitives (a figure per M1 unit type, a fortress, a fort, cottages, trees) with vertex colours and a team mask; formations (pure). |
| `scenario.gd` | Pure: the real `GameState`, autoplayed by the real `AIPlayer` through the real `TurnResolver`; a turn's `army_moved` events. |
| `overlay.gd` | The 2D overlay test: province names and army count plates (emblem, units, a tooltip) on 3D points. |
| `world_preview.gd/.tscn` | The preview: build, camera input, dev keys, HUD, `--shots`, `--perf`. |
| `launch.gd` | Autoload: `-- --world3d` opens the preview; does nothing otherwise. |
| `shaders/` | `ground_cel` / `ground_lit` (+ `ground_common` include), `model_cel` / `model_lit` (+ `model_common`), `outline` (inverted hull), `water`, `banner`. |
| `tools/terrain_dump.gd` | Headless: the baked land as pictures (relief, territories, ground). |

### Scene tree

    WorldPreview (Node, world_preview.gd)
      CanvasLayer
        Overlay (Control, overlay.gd)    names + army plates, projected every frame
        HUD labels
      World (Node3D, world_view.gd)
        Ground (MeshInstance3D, PlaneMesh 480x320 cells, raised in the vertex shader)
        Sea (MeshInstance3D, 12 000-unit plane at y = 0)
        Sun (DirectionalLight3D, 4 splits), WorldEnvironment, Camera3D
        Props (MultiMeshInstance3D x3: broadleaf, pines, rocks)
        Buildings (Fortress_<capital> nodes, Fort_<id> meshes, cottages x3 MultiMesh)
        Armies (Node3D, armies.gd)
          <army>_<type> (MultiMeshInstance3D per army and unit type), a banner per army

### The data image (`terrain3d.gd`)

World units are `MapLayout` design units (1000 × 600) with a 100-unit sea margin: a 1200 × 800 rect baked
on a **2.5-unit grid (480 × 320 = 154k cells/vertices)**.

1. **Territories**: a jittered Voronoi of the 14 centres (domain-warped by two noises; capitals hold a
   little more land). The warp is read mirrored across x = 500, so the land is as symmetric as the rules
   (`test_land_is_mirror_symmetric`).
2. **Coast**: a smooth union (log-sum-exp) of discs round the centres plus noise is the continent; its
   signed distance is the coast distance.
3. **Borders**: distance to the nearest other territory. A border between provinces that are **not
   neighbours** in `data/map.gd` is a **wall**, raised into a rocky ridge, so the land itself shows which
   moves are legal (the Voronoi makes Westwatch/Highcrag and Highcrag/Rivermarch touch; the rules don't).
4. **Heights**: plains low and gentle, forest a little higher, hills raised and craggy (terrain weights
   blurred across borders), a shelf into the sea.
5. **Stages**: a level stage round every centre (48 units for a capital's fortress, 24 elsewhere).
6. **Roads**: centre → middle of the shared border → neighbour's centre, carved into the land; one per
   neighbour pair (19), `test_every_neighbour_pair_has_a_crossing_and_a_road`.

Images handed to the shaders: `height_image` (RF), `data_image` (RGBA8: r province index, g coast distance,
b a **signed** border distance so bilinear filtering crosses zero on the border and the ink line is crisp,
a wall), `ground_image` (bare ground + woods), `weights_image` (terrain blend). The owner wash is a 16 × 1
texture rewritten on capture: the player's colour is drawn in code, never baked.

## The two looks (L toggles)

- **Look A, Bright Cel**: stepped light (one hard shadow tone with a cool tint, one highlight), ink
  outlines on every model (inverted hull, ~2 px, thinner far away), ink keylines on every province border
  and the coast, toon sea (flat bands, white foam line), linear tonemap, no SSAO.
- **Look B, lit painted** (CONCURRENT-like): the same meshes and ground under ordinary lighting, SSAO,
  filmic tonemap, glossy rippled sea, soft seams instead of keylines.

Both use the bible's terrain tiles (`assets/terrain/*.webp`) as grain over the painted ground colour; the
forest tile is laid under the trees so a wood reads as dense from far away.

## Fortresses and mustering

Each capital has the **Ludo probe's Crownkeep model** (F swaps to the primitive fortress): its blue roofs are
keyed by hue and repainted in the owner's colour (`model_common.gdshaderinc` `key_hue`), so one model serves
every seat. Its gate faces the mean direction of the capital's roads; its courtyard (measured from the
model's vertices) is where the capital's armies muster facing the gate, and the rows that don't fit stand
ready outside the gate. Armies elsewhere stand in formation on the province's stage, facing its roads.

A formation is one company block per unit (6 figures for spearmen, crossbowmen and fangthrowers, 4 tuskers,
3 knights, 1 war bear), packed into rows (melee in front, then ranged, then the big and mounted), with the
commander and a banner bearer in front. Every base is painted in the owner's colour, and the banner carries
the owner's colour and seat emblem. Far out, the figures stand up to 1.8× taller (toy scale), so an army
stays a readable marker over the whole map.

**Turn playback** (Space): the preview autoplays a real game (seed 4242, 7 turns, the real AI and rules) and
shows the turn whose moves include an army leaving a capital. Every `army_moved` event files out of the gate
(or off the stage), nearest figures first, two abreast, with a toy's hop and sway, marches the road over the
border crossing, then walks to its place in the after-state formation; armies that fell topple and shrink;
armies that stayed re-form; the land's owner wash changes when the columns arrive.

## Camera

A rig dict (target, pitch, yaw, fov 30°, span) eased each frame. Zoom is log-space from a 600-unit span to
70; the pitch eases with it from **58° far to 42° near**. Wheel zooms to the cursor (the ground under the
cursor stays put, refined over the hills), drag pans with the ground under the hand, WASD pans, yaw is fixed
(O toggles an orbit), 2 and 3 frame a capital close up.

## The Ludo `model3d` probe (10.5 credits)

No full-body concept art existed in `assets/concept/`, so each model got a reference picture first
(`image`, `asset` type, Bright Cel unit wording reworded for 3D: relaxed A-pose, front three-quarter, plain
light grey ground; 0.5 cr each), then `model3d` (3 cr each, about 2 minutes each, faster than the 4–25
minutes expected). All six calls succeeded first try. Manifest `tools/ludo/batches/asc-3d-probe.json`,
ledger `studio/ledgers/asc-3d-probe.jsonl`.

| Model | Faces / texture | Slimmed | What survived | What didn't |
|---|---|---|---|---|
| Kingdom spearman | 12k / 1024 | 1.77 → 0.83 MB | The whole figure: helm, plume, tabard trim, round shield, **the thin spear and its head** (in the mesh, not just the texture), boots; the painted ink lines are baked into the texture | Base-less (we add one); fixed pose; it reads as a spearman only from about mid zoom in |
| Tusker | 12k / 1024 | 2.01 → 0.81 MB | Boar head, tusks, war paint, harness, the stone club | The club is fused to the hand (no swap) |
| Crownkeep fortress | 34k / 2048 | 5.81 → 2.56 MB | Walls, 8 towers, keep, **an open courtyard and an arched gate you can march through**, a grass slab | The roofs are baked royal blue (keyed and repainted in code: works); the slab is square (sunk 2 units into the stage) |

Pipeline notes:
- Ludo ships `metallicFactor 1.0`: `tools/ludo/glb_slim.py --albedo-only` (new) keeps only the colour map,
  makes the material matte and halves the file; the game overrides the materials anyway.
- glTF front is +Z: figures are turned PI; the fortress gate is on the model's +Z wall.
- Scale is normalised from the AABB (a figure to 7.4–7.8 units including the spear, the fortress to 76
  units square).
- The inverted-hull outline works on the probe meshes (smooth normals); the texture's own painted ink
  doubles it up close, which reads as heavier line work, close to the bible's.
- Not tried: rigging (CONCURRENT's rig failed on a fused pose); pose-swapped statics + procedural motion
  (hop, sway, topple) are what the spike uses.

## Performance (this Mac: Apple M4, Metal, Forward+)

Measured by `--perf` (vsync off, 2.5 s a cell after a settle; 184 figures, ~1,500 trees and rocks, 2
fortresses, 34k-triangle Ludo fortress ×2). "Effects" = 4-split shadows, MSAA 2×, FXAA, glow, fog (and SSAO
in Look B). The window is 1600 × 900 on a 2× display; Godot draws the 3D at 1600 × 900, so the second table
renders it at **2× scale (3200 × 1800, what a full-retina 1600 × 900 window costs)** to find the headroom.
Frames above ~85–100 fps are capped by the display's pacing on Metal (effects off, everything sits at the
cap), so a cell at the cap means "has headroom", not a cost. CPU render time is 0.15–0.7 ms in every cell.
GPU timing isn't reported on Metal (0.0).

**1600 × 900 render (fps):**

| look | quality | effects | whole map | zoomed (Crownkeep) | marching |
|---|---|---|---|---|---|
| A cel | 0 | on | 66 | 93 | 65 |
| A cel | 0 | off | 85 (cap) | 87 (cap) | 84 (cap) |
| A cel | 3 (ladder bottom) | on | 69 | 90 | 91 |
| B painted | 0 | on | 82 | 99 | 94 |
| B painted | 0 | off | 91 (cap) | 82 (cap) | 85 (cap) |
| B painted | 3 | on | 94 | 85 | 87 |

**3200 × 1800 render, the retina cost (fps):**

| look | quality | effects | whole map | zoomed | marching |
|---|---|---|---|---|---|
| A cel | 0 | on | 40 | 56 | 43 |
| A cel | 0 | off | 96 | 99 | 95 |
| A cel | 3 | on | 50 | 85 | 73 |
| B painted | 0 | on | 42 | 58 | 52 |
| B painted | 0 | off | 91 | 92 | 81 |
| B painted | 3 | on | 78 | 94 | 94 |

Reading it: the land, trees and figures are cheap; the **effects** are the cost at retina resolution, and
the whole map is the dearest view (the most shadow casters and, in Look A, the outline pass over every tree).
The quality ladder (`world_view.gd set_quality`: 1 SSAO off → 2 two shadow splits, shorter, the woods cast no
shadow → 3 the 3D at 0.75 scale) recovers 25–90%; the preview steps down by itself after 3 s under 40 fps.
Bake: 0.6–1.8 s on a worker thread (the window stays live); build of the scene ~0.3 s.

## Reusable vs placeholder

**Reusable as is or nearly:** `terrain3d.gd` (any `MapLayout`; the walls-from-adjacency rule), the ground and
water shaders, the camera rig and zoom-to-cursor/pan, `project`/`unproject`, the owner wash texture, the
team-mask and hue-key repaint (identity in code), the outline pass, the MultiMesh army renderer, the
courtyard muster and spill-out, the march-out playback from real `army_moved` events, the quality ladder,
`--shots`/`--perf`, `glb_slim.py --albedo-only`.

**Placeholder:** every primitive figure, the primitive fortress (F; its pale stone blows out under Look A's
light, see `08_primitive_fortress`) and fort, cottages and trees; the courtyard
rect is hand-measured for one model; battles are only a topple; recruits pop in at the end of a turn; no
selection, orders or UI integration (the overlay is a proof).

## Recommendations

1. **Look: A, Bright Cel**, with two things borrowed from B: soft shadows from the sun (already on) and
   B's sea (glossy, lighter) for close views. A keeps the bible (flat colour, one hard shadow tone, ink
   lines, keylined borders), reads better at the whole-map zoom (keylines carry the provinces), and the Ludo
   models' painted ink already matches it. B looks richer close up but muddier far out and fights the 2D
   UI's flat style. The director's call: see `01_whole_*`, `03_crownkeep_close_*` and `06_stand_*`.
2. **The 3D armies are the markers.** Keep one company block per unit, the owner's colour on every base and
   on the banner, the seat emblem on the banner and the count plate, and toy scale (1.8× at the whole map).
   Budget: **≤ 6 figures per unit, ≤ ~60 per army, ≤ ~400 on the map** before LOD. At the whole map a figure
   is ~15–20 px tall; detail past that is wasted there.
3. **MultiMesh everything repeated** (figures per army × type, trees, cottages) as now; add a 2-step LOD for
   figures (the 12k-face Ludo mesh close, a ~1–2k decimated or impostor far: `generate_lods` is on in the
   import) and drop the outline pass on trees past mid zoom (it is the Look A whole-map cost).
4. **Asset pipeline from the probe: go.** Picture (0.5) → `model3d` (3) → `glb_slim.py --albedo-only` → AABB
   normalise → our cel material + outline, hue-key repaint for the player's colour. 3.5 cr and ~2.5 min a
   model, first try 3 for 3; thin spears survive. Ask for figures **in an A-pose with the weapon held away
   from the body** (rigging later needs it), **on no base** (we add the team base), and name the faction
   palette in the prompt. Fortress-class models should be asked for **with an open courtyard and gate**
   and their courtyard measured (as here) so armies muster inside. Budget ~4 cr per unit (×1.5 re-rolls),
   so a faction of 6 units + commander + capital ≈ 35–45 cr.
5. **Animation:** pose-swap (3–4 Ludo poses per unit made from edited pictures: stand, march, strike, fallen)
   plus procedural hop/sway/topple, as CONCURRENT does; don't plan on Ludo rigging.
6. **Integration next:** the 2D map screen over this world through `project`/`unproject` (CONCURRENT's
   `land_board.gd` pattern, a SubViewport host rendering on demand), the order arrows drawn on the ground,
   and the turn report driving `play_turn`. Keep the rules untouched: playback reads only events.
7. **Before committing:** decide 1600 × 900 vs full retina for the 3D (retina with effects is ~40–55 fps on
   an M4; render scale 0.75 is nearly invisible in Look A), and whether the wall ridges (non-neighbour
   borders) should become rivers or cliffs per terrain.
