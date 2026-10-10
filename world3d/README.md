# The 3D world (`world3d/`)

The game's map as a living 3D board (design/3D_DIRECTION.md). Since **M3a.1** it is the map of every game:
the map screen's 2D UI sits over it, every order and tooltip works through it, and each resolved turn plays
out on the land before the turn report opens. Settings → Board switches back to the 2D map. The rules
(`rules/`, `data/`, `ai/`) don't know it exists: the board only reads the state, the orders and the
resolver's events.

## The board in the game (M3a.1)

    GameScreen (ui/game_screen.gd)
      Map (MapScreen, ui/map_screen.gd): the Table (UX-1: realm plaque, system row, tray and seal, the details card,
                                         the move forecast; ui/table_hud.gd) over a full-bleed map view
        MapView
          Board3D (world3d/board3d.gd, a Control under everything else in the map view)
            World (SubViewport, own World3D, at the screen's physical pixels; renders only while live)
              WorldView (world_view.gd): land, sea, sun, woods, villages, fortresses, the camera rig
                Armies (armies.gd): formations, ghost recruits, turn playback
            BoardOverlay (board_overlay.gd): names, incomes, count plates, ghost plates, order arrows,
                                            clash markers, the playback bar, the legend: 2D, projected
          MapCanvas (the 2D regions: hidden, but kept for their tooltips and marks)
        TableHud (over MapView, under the Overlays layer: the playback bar, its caption and the close-up chip are
                  placed by it inside the board's safe area, ui/table_layout.gd; the board frames the whole map in
                  the part of the safe area right of the details card, set_fit_rect)

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
- **Measured** (Apple M4, Metal, Look A, 1600 × 900 window, 3D at 1200 × 846, rung 0, vsync off, #91's
  models, a 14-turn computer-vs-computer game, a shared machine at load average 25-30): a turn's playback
  71-85 fps with the camera on the action (404-421 draw calls, 2.2 M triangles, 134-141 figures); the
  whole map 27.5 fps (644 draw calls), where main measured 19 at the same load. Shadows are the frame's
  main cost: the model woods cast none and show only at the near zoom; figures, villages, landmarks and
  forts cast none far out; regenerated LODs on every rebuilt model. The quality ladder is unchanged.
  The headless playback step: 0.6-1.5 ms on average (design 3.5: 2 ms).
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
          "tint": 0.8, "model_tint": {"<faction id>": 0.8}
                                           // IND-2: darken a model figure (vertex colour x texture, 1 = as made); an
                                           // extra's own tint per faction. Pale undyed wool blows out to white at 1
          "fallbacks": {"<faction id>": "<Kit.figure id>"}
                                           // IND-2: the primitive an extra wears for that faction when it has no model
                                           // (the Free Holds' "free_bearer")
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

## Polish (#125)

- **Far-zoom army stands** (`stands.gd`, design 6.1): where even piece scale leaves a man-sized figure under 23 px
  on screen, every army becomes a stand: a base in its owner's colour (an ink rim, a gilt ring for a ruler's
  army), its banner, and one figure for each of its three most numerous types, sized in screen pixels (a 32 px
  base, a 38 px banner). The count plate rides over the stand. Hysteresis (on under 23 px, off over 27) and a
  0.35 s cross-blend: the figures shrink away as the stands grow in (`armies.gd set_blend`). The board's hooks
  are three lines in `board3d.gd _camera`, `army_rect` and `army_plate_point`.
- **The musician's rung**: from quality rung 2 (`Armies.MUSICIAN_OFF_RUNG`, `Board3D.set_quality_rung`) the
  musicians stand down from every colour party; the bearers stay, they carry the banners.
- **Forest trays** (`trays.gd`): in a forest province every army's blocks stand on movement trays, one per block
  and one under the command group, in the owner's colour (a little darker, so each figure's base still pops) on
  an ink rim, a gilt ring for a ruler's army. Woods-green figures (the Thorn Wild's) no longer pass for trees.
  A tray covers its block's slots; a figure WIDE times wider than its slot (a Briarwarden's canopy) widens its
  tray to its width. One mesh; hidden while a turn plays and under the stands. The hook is one line in `_camera`.
- **Path-unit variants** (#126): a unit row's `variants` entry for a faction's transformation is merged over the
  row (`Models.figure_row(type, variant)`, `variant_of(type, AscensionRules.transformation(state, faction))`), and
  every mesh cache, MultiMesh and stand key carries the variant. The board reads the transformation from its
  state; the 3D stage from the state `play()` is given (with a log alone, from the people its log records).
- **The camera dives from the board** into a battle: `Board3D.view_rig` is where the board's camera stood; the
  stage, opened over it, eases from there onto its framing in 1 s (any key or click lands it; a cut with
  reduced motion). The stage still builds its own copy of the world: the dive is the camera, not the scene.
- **M3's files** (`BattleFormation.groups_of`): a battle of more than 280 fighters stands one figure for a file
  of up to k fighters of the same side, army, type and rank (k the smallest from 2 that fits 280; leaders stand
  alone). A file's figure falls with its last fighter; its plate sums its fighters with a "×n" badge of those
  standing; its tooltip lists each one. `--fixture massive` (322 fighters) shows it.

## Forts and sieges on the board (M3c S-4, #102)

design/M3C_SIEGES.md §10.1 and §10.2, in a game with sieges. Without sieges nothing changes: the map's forts stand
as M3a placed them and every M3a test passes unmodified.

- **The pure part** (`siege_board.gd`): the forts part of the board model (`model_of`: each fort's level, walls,
  damage look and kit, the construction sites, each siege's besieger and camps), how a turn's fort events move it
  (`apply_events`, one event at a time with `apply_one`), and the table the board draws (`board_table`: kit by
  level, look, scaffold and how far the next level has risen, the chevrons' faction). `playback.gd` folds it into
  the board model, so playback = state covers it, and its plan carries each fort beat with the report's own line.
- **Forts from the state** (`world_view.gd show_forts`, `fort_table()` says what it drew): a palisade (`palisade.
  <faction>`, primitive: a stake ring round a small yard), a keep (`fort.<faction>`), a citadel (the capital's
  fortress); a built fort wears its builder's kit, a map fort the nearest capital's, a captured one keeps its look.
  Every fort's gate faces its stage. **Damage looks**: the look's model when the table has one, else the code
  fallback through the close-up's `cut_plane` dither: one step lost knocks the gate-side corner down, two
  (battered) knock it lower with rubble, smoke and fire, the breach takes the whole gate side down to its footing
  with rubble in the gap. **Construction**: a timber scaffold with the site's materials, the next level's model
  solid up to the work done and faint above. **Sieges**: 8 chevron banners in the besieger's colour round the walls.
- **Yards at every fort** (`world_view.gd yard_of`, `muster.gd packed`): a fort's owner's armies pack into its
  yard, tighter the bigger the garrison (down to `Muster.PACK_MIN`); the rest muster in the war camp outside its
  gate, or, besieged, pack at the gate. A besieged capital packs its garrison the same way. Recruits at any fort
  march in through its gate; marches leave by it.
- **The camp ring** (`armies.gd _layout_ring`): one camp per besieging army round the walls (slots from
  `SiegeBoard.ring_angles`, beside the gate first, skipping ground that isn't the province's), each army facing
  the walls with its tent and fire behind it; the besieger's siege works before the gate and the engines its armies
  carry at the walls (`siege_works.<faction>`, `siege_engine.<faction>`; primitives until S-9's models).
- **The beats** (`armies.gd play`, the Sieges phase between Battles and Captures): the camps go up and the chevrons
  rise, the camp and the engines strike the walls (dust bursts, `shaders/dust.gdshader`) and the look changes at
  the end of the beat, a breach collapses the gate side with a rubble burst and a rule-bound shake (off with reduced
  motion or screen shake off), a lifted siege folds its camps, masons repair; scaffolding goes up in Recruits and a
  razed site collapses in Captures. In Battles a sally's armies file out of the gate two abreast and form up facing
  the camps (and walk back in by it), a storm meets at the walls, a breach battle in the gap. Each beat names
  itself in the caption, and its turn report line is the caption's tooltip.
- **Planning, private**: a queued recruit at a fort stands as a ghost in that fort's yard; a queued Fortify stands
  as a ghost scaffold with a plate, only in its owner's view and never while the board is covered or hidden.
- **Explanations**: each plate carries S-3's fort chip; a province's tooltip says what the board shows at its
  fort (`SiegeBoard.describe`); the legend has a forts and sieges section; the Sieges caption explains itself.
- **Tests**: `tests/test_board3d_sieges.gd` (the board model of a state and what the board draws of it, playback =
  state over 5 seeds x 15 autoplayed turns and a scripted siege with every fort event, a played board standing as
  one built from the state after with the states deep-equal, the sally out of the gate, recruits by a fort's gate,
  the model table's siege kinds, the explanations, no dice or resolver anywhere in `world3d/`, and no private
  scaffold ghost on a covered hotseat screen).

### Measuring the minimum-spec rung (3D_DIRECTION 3.5, #62)

The budget is p95 ≤ 33.3 ms at 1920×1080 on a 2020+ integrated GPU (Iris Xe, Vega 7/680M, M1) at its Auto
rung. The studio has no such machine, so the method is fixed and the number waits for one:

1. On the machine, plugged in, nothing else running: `godot --path . -- --battle3d --fixture biggest
   --window=1920x1080 --rung 3 --quit-at-end`. It plays the 277-fighter battle at 1× to the result and prints
   `fps`, `frame time p95`, `max`, the draw calls and the rung (`battle_watch3d.gd`).
2. Again with `--rung 4`, then without `--rung` (the Auto ladder: it starts at 0 and steps down after 3 s under
   40 fps; the printout names the rung it ended on).
3. Pass: p95 ≤ 33.3 ms at the Auto rung, no frame over 50 ms after the first second. Report the three lines,
   the machine, its driver and the build's commit in the PR or the issue.
4. The board: start a game, `F` for the whole map with every army visible, and read the board's fps over
   10 s at the same rungs (Settings has no rung switch yet; the ladder steps down by itself).

Alex's Mac (Apple M4, the reference row) runs step 1 at rung 0 for the numbers in M3b's PR (#109).

## Fog of war on the board (M5-3, #114)

design/M5_MAGIC_FOG.md §2, §12.1; 3D_DIRECTION §6.3, §6.6, §10.2. In a fog game the map screen holds the viewer's view
(`GameSession.state_for`, M5-2), and the board draws only that: it has no way to the truth (`tests/test_fog_board.gd`
scans every `world3d/` script for a truth accessor and checks that changing anything hidden from the viewer,
`FogTestKit.perturb_hidden`, changes nothing the board builds or plays). With fog off, none of this exists: the vision
switch is off, every older board test holds unchanged.

- **The vision texture** (`vision.gd` pure, `world_view.gd set_vision`): a 16 × 1 R8 texture beside `owner_tex`, one
  texel per province index: 0 never seen, 85 remembered, 170 glimpsed, 255 in clear sight. The board rewrites it
  whenever a state is stood (a new turn, a handoff): 16 bytes and one `ImageTexture.update`.
- **The ground** (`ground_common.gdshaderinc`, both looks): out of sight, the terrain is desaturated 70% under a cool
  veil at 40% with 45° hatching at a constant screen size (kept off the owner's inner band); never seen adds slow clouds
  (`fog_drift`, standing still from rung 3, `WorldView.FOG_STILL_RUNG`); glimpsed has a faint veil (13%, 12% drained: 10% did
  not read at the whole-map zoom). The owner's wash goes on after the veil and stays true. One uniform branch
  (`fog_on`) and one texture fetch; the trees and rocks are geometry and stay as they are (the spec's "terrain still reads
  from its geometry").
- **Armies are the view's armies**: a rival's stand-ins draw as blocks from the shown counts under a "≈20" plate (the 2D
  badge's words, `FogView.badge_text`); a ruler stand-in is its ruler; a rival's yard shows its stand-in or ghost blocks,
  or stands empty under the veil. **Remembered armies** are grey-blue translucent ghosts in their own material
  (`shaders/memory_ghost.gdshader`, parented under `armies.memory_root`, no banner, tent, fire, tray or shadow), a step
  fainter every 2 turns of age (`Vision.ghost_step`, `ghost_alpha`), plate "≈10 · 3 turns ago"; at the far zoom their stand is
  grey with no banner. `ghost_count()` stays the queued recruits' ghosts only (`memory_list()` is the memories).
- **The playback** is built from `view_before` and the viewer's own report, synthetic events included
  (`playback.gd`): a rebuilt rival move (pooled, rounded, no true ids) becomes a seen march of its stand-in's block
  (alias `~seen~<id>`), walking to the border and fading when the road led out of sight; a stand-in that appears or
  grows fades in where it stands (it never marches in through a gate, as a recruit does, and plays no recruit sound);
  `sighting_changed`, `memory_added` and `sighting_lost` fold into the board model exactly as
  `FogRules.apply_view_events` does. The ground's veil follows: the turn's start until the re-form, then the state after's.
  A ritual's beat (`plan["rituals"]`, `Armies.ritual_beat`) starts at its caster only for the viewer's own cast; one from
  a hidden caster starts at the target. M5-9 draws the effects there.
- **Sound only for what the viewer sees**: a march or battle in the viewer's own report is heard; a capture or fort the
  viewer was only told of (a rebuilt event) is heard only when the province was in sight at the start or end of the turn
  (`Board3D.sound_seen`).
- **Hotseat**: `stand()` rewrites the vision texture and every army at once, so the handoff's rebuild under the cover is
  the next seat's; a change of viewer also puts the camera on the new seat's capital (`_new_seat`), so the first frame never
  shows where the last seat was looking.
- **Explained**: the legend has a fog section; a plate that isn't in clear sight says so under it ("glimpsed", "out of
  sight / seen 3 turns ago", "never seen") with the level's words and the province's fog paragraph on hover; a province's
  tooltip says how the ground shows its level; a stand-in's tooltip says its blocks are an estimate, a ghost's how old it is
  and that it fades a step every 2 turns.
- **Cost** (Apple M4, Metal, 1600 × 900 window, the whole map with half of it never seen: veil, hatching and clouds all
  on, a shared machine). Metal gives no GPU timestamps through `viewport_get_measured_render_time_gpu` (it reads 0), so the
  veil was measured as frame time, switched off and on in turn: within the noise at 1× (rung 0: -0.03 ms, rung 3: +0.06 ms),
  and +0.32 ms at four times the pixels (the viewport's 3D scale 2.0, six interleaved pairs, every pair the same way): about
  **0.08 ms a frame at rung 0**, under the 0.2 ms budget. CPU: `Vision.levels` 0.06 ms and `set_vision` 0.003 ms a turn; a
  whole fog `stand()` (armies, plates, sight) 6 ms (`tests/test_fog_board.gd` checks the three with `--perf`).

## The Free Holds' look (IND-2, #161)

The independents' garrisons (`data/independents.gd`, IND-1 #142) stand on the 3D board and fight on the 3D stage in their own
look: plain local militia in undyed bone-cream wool and weathered grey, apart from the Crown's blue and gold and the Clans'
tawny and moss (STYLE_BIBLE: slate is the independents' colour, `UiPalette.NEUTRAL`).

- **The kit's independents style** (`kit.gd`): a figure for each unit id, `free_spears`, `hill_slingers`, `wildkin` (a silver-grey
  badger of the deep woods) and `hold_captain` (`Kit.INDEPENDENTS`), plus the colour party's `free_bearer`
  (`Kit.INDEPENDENTS_PARTY`) and a plain wool war tent (`Kit.tent("independents")`). Palette: `WOOL`, `SLATE`, `GREY`, `IRON`,
  `BADGER`; never blue, gold, tawny, moss or crimson (`tests/test_free_holds_look.gd` checks it against the Crown's and the
  Clans' signature colours). Kept a little under white on purpose: the cel light blows anything lighter out to a ghost.
- **The model table** has a row per unit id with `"model": ""`: the board and the stage draw the kit figure until the Ludo
  model is installed, and the row then names the GLB, its height and its poses like any unit's. The bearer and the musician rows
  carry `"fallbacks": {"independents": "free_bearer"}`: the primitive a faction's army wears when it has no model of its
  own, so a garrison's colour party is not a Crown man with a blue plume.
- **The banner** of an army that belongs to nobody (a garrison, `seat < 0`) carries the independents' heater shield
  (`Kit.EMBLEM_SHIELD`, drawn by `banner.gdshader`), where it used to borrow Player 1's circle; the plate keeps the shield
  glyph the 2D map uses. The bases stand on slate.
- **Portraits** are found by unit id under `assets/portraits/independents/<id>.webp` (`Art.unit_faction`).
- **Where the art comes from:** `tools/ludo/asc_3d_free_holds.py` (batch `asc-3d-free-holds`, ledger
  `studio/ledgers/asc-3d-free-holds.jsonl`): concept pictures, poses and portraits go into the Review Table batch
  `review/ind_concept/` and the slimmed models into `review/ind_models/` (each model's target is its install path); the owner
  judges them there and the batch's install action (`install-accepted`) puts the accepted models in
  `assets/models/units/independents/` with their `models.json` rows and the unit rows of this table, so the placeholders swap
  out. A Ludo model carries a floor slab (the picture's soft ground shadow fused into a plate under the feet): the script cuts
  it away before slimming (`trim_floor`).

## Battles on the land (M3b)

A battle is played back in 3D on the province where it happened (design/3D_DIRECTION.md 7), driven entirely by
the renderer-agnostic `BattlePlayer` (ui/battle/). `BattleHost` loads it as the "3D on the land" battle view, the
default (Settings > Battle view keeps Simple).

    BattleStage3D (world3d/battle_stage.gd/.tscn: extends BattleSimpleView, so the top bar, strength bars,
      |             caption strip, result card, BattleControls, BattleWhyPanel, BattleLegend and BattleSelection
      |             are the Simple view's own, unchanged)
      Frame > Field
        Land (draws the World SubViewport: 1600 x 600 at the window's physical pixels)
          World (own World3D): WorldView on Board3D.terrain_now() (the board's baked land), Fighters, Projectiles
        StageOverlay: hp plates, ruler plates, glyphs, ground rings, impacts, dust, sparks, bursts, numbers (2D)

- **Where it stands** (`battle_formation.gd`, pure): the defender holds the stage facing the border the attacker
  came by (the first road toward the attacker's capital), before its own gate at a fortress, its fort behind it
  (the world's, or one the stage puts up when the log has a fort the world doesn't draw); nobody defending: each
  side toward its home; a border battle on the crossing. It turns up to 60 degrees until nobody stands in the sea.
  Ranks as the log has them: front rank, second rank, back line; types in roster order; a ruler mid front line,
  the commander mid back line with the side's standard bearer and musician (cosmetic). Every fighter its own
  figure. The file count is the one that frames the battle biggest. The woods, rocks, villages and cottages on
  its ground are lifted off the table and put back after (`clear_for`).
- **Figures** (`battle_figures.gd`): one MultiMesh per unit type and pose mesh (both sides share it: the base's
  colour and a hit's red tint ride in the instance custom data), a desaturated copy for the fallen. Motions keyed
  to the player's clock: deploy step, lunge and strike pose, release, Wings dive, recoil, topple then fallen
  pose, rout run and shrink, aftermath fade, winners' cheer. The sync is incremental: only moving figures are
  posed again.
- **Camera** (`battle_camera.gd`, pure): flank yaws (and up to 24 degrees off), pitch raised until no hill or wall
  hides anyone, fitted and centred in the band the 2D leaves clear; a little in favour of the sun behind the
  camera and the defender on the right. A key-moment jump frames the moment's camera hint and rises back after
  FOCUS_HOLD. F reframes (BattleControls.reframe_requested), right-drag turns, middle-drag pans, the wheel zooms.
  Moves are at most 1 s, cuts with reduced motion; shake per M3 4.5 through BattleFx.ShakeLimiter.
- **Effects**: 3D projectiles (bolt, javelin, arcane bolt: code meshes with trails, arcs from BattlePlayer's
  PROJECTILES); impacts, dust, sparks, heals and the ruler's burst drawn camera-facing in the overlay by the
  Simple view's own BattleEffects functions where they exist; numbers by BattleEffects.draw_number. The flash
  limiter, sound gate and reduced motion are BattleFx's. Legend rows: `BattleStage3D.stage_rows()`.
- **Budget**: the woods round the battle are model trees in 28-unit cells (each its own LOD), primitives beyond;
  the fighters' ink width follows their size on screen. Quality ladder: `set_quality` (world_view.gd's rungs,
  then the fighters' shadows, the woods as primitives, no sun shadows).
- **Run it**: `godot --path . -- --battle3d --fixture biggest` (or `path_wings`, `path_lifedrinker`, ...).
- **Tests**: `tests/test_battle_stage3d.gd` (every fixture to the timeline's final state, beats to actions, seek
  and skip, the game unchanged, hover and click selection, raw ids, reduced motion, the flash limiter, the ground
  plan, the camera, the legend rows, the creature scale, the host contract, the CPU budget).

## Battles at walls (M3c S-5, #103)

A battle whose log has a `siege` block (a game with sieges, at a fort) stands at the walls instead of on the open
ground (design/M3C_SIEGES.md 10.3). The stage only shows: nothing here changes a result, draws a random number or
calls the rules. Everything it needs is in the log's `siege` block (kind, why, fort, walls, from_inside, garrison)
and, for the engines, the game `play()` was given.

- **The fort on the land** (`BattleStage3D._dress_forts`): the stage's own WorldView draws the fort the log
  describes through the board's own `show_forts` rows (the kit of its level and builder, the damage look of its
  walls: intact, damaged, battered, breached), over the map's; with no siege block the map's forts come back.
- **Where everyone stands** (`battle_walls.gd`, pure; `BattleWalls.plan`, same result shape as `BattleFormation.plan`):
  - *storm*: the garrison on the wall walk (its Volley tier and mages along the gate-side wall, the commander and
    ruler on the gatehouse, then the side walls, then the yard); in the Clans' kit and the palisade there is no walk,
    so it stands in the yard behind the stakes. The stormers form up at the foot, facing the wall, with ladders
    leaning on it (the Crown) or the trunk before the gate (the Clans).
  - *breach*: the gate-side wall is down (the breached look): the garrison's front rank in the gap, the rest behind
    it in the yard, then on the stubs of the side walls; the attackers form up before the gap.
  - *open* (a sally, a relief, a relief with a sally, the gate battle): both lines form up before the gate, the side
    with fighters from inside nearest it, and exactly those fighters (`from_inside`) march out of the gate in a column
    during the deploy beat (`march_out` in `battle_figures.gd`).
  - A table of each model's walls (`BattleWalls.SPECS`: deck heights, the gatehouse, the yard's floor, what a
    fighter must not stand inside) was measured off the models; a model row's own `walls` group overrides it, and
    `tests/test_battle_stage_walls.gd` checks the table against the models, so an art pass that swaps one says so.
- **Scenery** (`battle_scenery.gd`): ladders or the trunk at the wall, and the besiegers' camp beside their lines: a
  tent to an army with a fire, the siege works and the engines the besiegers still carry (from the game `play()` was
  given: an army lost in the battle took its engines with it, and the log does not keep them). Models from the table
  where there are any (`camp.<faction>`, `siege_works`, `siege_engine`), else the code primitives of `kit.gd`.
- **The walls' +N reads before the first hit**: the caption strip's second line says what the walls (or their lack)
  mean for the fight about to be played, a plate hangs over the gate-side wall for the whole battle (with the
  wall-strength cells in the steps a storm counts), and both explain themselves on hover and link to the codex.
  The top bar's chip (M3c S-3) is unchanged.
- **Run it**: `godot --path . -- --battle3d --fixture siege_storm_keep` (any case of `tests/walls_stage_fixtures.gd`
  with `siege_` in front: `siege_breach`, `siege_sally`, `siege_storm_capital_beasts`, ...).
- **Tests**: `tests/test_battle_stage_walls.gd` (the storm, breach and open placements, nobody inside a wall, the table
  against the models, the walls' defense on screen before the first hit, the fort on the land, the camp and its
  engines, a fighter on a wall, the camera, determinism, files, the stage only shows).

## Magic in 3D (M5-9, #120)

design/M5_MAGIC_FOG.md §5, §6, §12.2, §12.3, §15.3; 3D_DIRECTION §3.4. The battle stage draws every battle spell and the board
draws rituals and enchantments, as **code placeholders** (rings, beams, billboards, motes: the VFX sheets of §15 replace them
without code changes elsewhere), on the quality ladder, in a few draw calls. Effects only read: a cast beat is the log's own event,
a ritual beat is the viewer's own report, and nothing here changes a state, rolls a die or looks a hidden caster up.

- **Files.** `spell_plan.gd` (pure: what each effect draws on each rung, as lists of marks; every number of the ladder is here),
  `spell_fx.gd` (the node: three MultiMeshes, the pool, the flash limiter), `shaders/spell_fx*.gdshader*` (every mark in one
  shader: ground decals depth-tested so a figure hides a ring at its feet, sprites and beams over the figures),
  `battle_spells.gd` (a `cast` beat to a plan, the legend rows), `enchant_decals.gd` (the board), `magic_beats.gd` (which ritual beats
  play before the marches and which after the battles), `spell_figures.gd` (the four new figures). The stage's, the board's and
  `Armies`' edits are small hooks (`_cast_beat`, `_moon_heal`, `_spells_seeked`, `decals.sync`, `magic_beat`).
- **The ladder** (`SpellPlan`, thinned and never dropped: `tests/test_spell_fx.gd` checks every effect on every rung, still and
  moving). Bolts (Sunlance's gilt beam, Bloodbolt's crimson one): beam, trail and glow on rung 0-1, no glow on 2, a plain beam on 3,
  a straight line on 4-5, the impact sheet half size from 4. Briar Snare: a ring of thorns under each snared unit on every rung,
  vines and briars and 32 particles on 0-1 (16 on 2), one briar each on 3, the ring alone from 4. Shield of Law: a translucent
  shield before each covered unit on 0-3 (the rim pulses on 0-2), a ▲ under it from 4. Sunburst: the glare ring sweeping the enemy
  front on every rung, the flare sheet to 3, the bloom and a 4 px shake on 0-1 (the shake to 2), the ring alone from 4. The Blood
  Moon's heal: 24 rising motes, 12 on 2, the number alone from 3. On the map: a ritual cast is a pillar at a visible caster and a mote
  along the roads, then the decal (no mote on 3, the decal alone from 4); enchantments are animated decals on 0-1 and still from 2; a
  summoning's ring and a raised fort fade in on 3 and pop in from 4.
- **Pools, the flash limiter, reduced motion.** At most 32 effects alive (`SpellPlan.POOL_CAP`); a full pool SKIPS a new effect,
  it is never queued (the caption and the bars carry the facts). A bolt or Sunburst asks `BattleFx.FlashLimiter` once (Sunburst
  counts as a flash); refused, it plays without bright frames (its bright marks stay at or under 80%); allowed, a bright mark is above
  80% for at most `BattleFx.BRIGHT_FRAMES` real frames. Sunburst's shake goes through the stage's own `ShakeLimiter`. Reduced motion
  plays every effect as a still mark (no sweep, travel, pulse, particles, shake or flash) and the standing decals do not animate.
- **The battle stage.** A `cast` beat becomes an effect on the caster and its targets, the spell's name and numbers float over
  the caster ("Sunlance 4", "Briar Snare -2 attack", "Bloodbolt 5" with "-2 hp"), a bolt makes `battle_arcane`'s sound, and the bars
  and glyphs refresh (a bolt's damage is pending). A hex or shield lasts to its round's `round_end` beat; a seek rebuilds the ones the
  state still has (`BattleSpells.standing`). The effect's colour is the school's, "effects are untinted": ownership is the ring under
  the caster and under a snared or shielded unit, in its side's colour. The legend has a row for each spell (`BattleSpells.legend_rows`).
- **The board.** `Playback.plan`'s "rituals" now carry every event of §12.3 (`SpellPlan.EARLY_EVENTS` before the marches, which then
  start after the rituals phase; `LATE_EVENTS` after the battles); `Armies.magic_beat` hands each whole to `EnchantDecals`, and the
  playback bar gains the Rituals and Enchantments phases (captions and help in `Choreo`). A cast the viewer sees starts at its caster;
  one from a caster it can't see (the beat's `from` is "") arrives at its target with no direction, and a heralded global ritual is a
  moon over the map. Standing decals come from the state the board stands (under fog the viewer's view): a gilt ring under each blessed
  army, a blue band on a warded province, crimson veins on a cursed one, an eye over a province in Far Sight. A summoning's creatures
  step out of a briar ring as the armies re-form (a new army in the state after is a recruit to the board); a Bastion rises behind
  scaffolding (the board's own `_rising` piece), and its fort stands from the state in a game without sieges
  (`WorldView.set_raised_forts`: the baked map has none there). `Playback.apply_events` follows `summoned` and `summon_faded`.
- **Figures.** `adepts`, `shamans`, `thornwolves` and `greenwrath` have rows in `models.json` (`"model": ""`, the fallback is the
  Kit figure of the same name, `spell_figures.gd`: a robed caster with a sunstone staff, a furred caster with antlers and a skull
  staff, a low four-legged wolf wider than it is tall, a tall thicket with a stag's skull). `kit.gd` gained one arm in `figure()`, one in
  `_base()` and `has_figure()` knows them; the GLBs drop in by filling the row.
- **Run it.** `godot --path . -- --battle3d --fixture magic_all` (every battle spell in round 1), `magic_sunburst`, `magic_shield`,
  `magic_snare`, `magic_bloodbolt`, `magic_moon`, `magic_pack` (the four new figures), `magic_big` (280 fighters, 6 casters), with
  `--rung N` and `--reduced-motion` (`tests/magic_stage_fixtures.gd`).
- **Cost.** Spells add three draw calls to a battle (ground decals, sprites, beams; the budget is 150), never more however many
  effects are alive, and at most 32 effects. Measured on Alex's Mac (Apple M4, Metal, Forward+, a 1600 x 900 window, a shared machine, no
  GPU timestamps on Metal): `godot --path . -- --battle3d --fixture magic_big --quit-at-end --rung 0 --window=1600x900` (280 fighters, 6
  casters) 101.6 fps, frame time p95 10.85 ms, draw calls max 845, against the plain `biggest` battle's 100.4 fps, p95 11.14 ms, draw
  calls 808 (the extra figures account for the rest); rung 3: 102.2 fps, p95 10.85 ms against 100.8 fps, p95 11.29 ms. The stage's CPU
  with effects on, headless at 4x: about 0.2-0.4 ms a frame more than without (`tests/test_spell_fx.gd` prints it, and checks the
  2.0 / 4.0 ms budget under `-- --perf`). The shaders' pipelines are warmed in the node's first frames (`SpellFx.WARM_FRAMES`), so the
  first Sunburst of a battle does not hitch it.
- **Tests.** `tests/test_spell_fx.gd` (see its header).

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
