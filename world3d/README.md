# 3D world map spike (`spike-3d-world`)

A real 3D world map for ascendant, built from the real rules, to judge the look and the cost before the art
budget is committed. It is a dev preview: nothing in `rules/`, `ui/` or `data/` changed, and the 2D game
still runs as before (now under Forward+).

## Run it

    godot --path . -- --world3d                          # from the normal launch (world3d/launch.gd)
    godot --path . res://world3d/world_preview.tscn      # or straight in

Options after `--`: `--look=cel|painted`, `--start` (turn 0 instead of a mid-game), `--turns=N`,
`--probe` (the Ludo probe's figures), `--primitive-fort`, `--shots=DIR` (the evidence screenshots, then quit),
`--perf=FILE [--stress=2.0] [--quick]` (fps, then quit).

Keys: **1** whole map, **2** Crownkeep, **3** Fangridge, **Space** play the next real turn, **R** reset,
**L** look A/B, **P** probe figures, **F** Ludo/primitive fortress, **Q** quality step, **E** effects,
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
