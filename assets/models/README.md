# 3D models

Ludo image-to-3D models for the 3D board (`design/3D_DIRECTION.md` §9, `design/STYLE_BIBLE.md` §8).
Every model here has a row in **`models.json`**, the descriptor the world reads instead of hard-coding
paths, sizes and turns.

| folder | what | made by |
|---|---|---|
| `units/<faction>/<unit>_<pose>.glb` | the 8 unit and commander types, 4 poses each: `ready`, `march`, `strike`, `fallen` | batch `asc-3d-factions` |
| `units/<faction>/<unit>_<pose>.glb` (new units) | the 4 units the M4 transformations add (`data/paths.gd` `NEW_UNITS`): `seraphs`, `iron_colossus` (Crown), `briarwardens`, `bloodsworn` (Clans), 4 poses each | batch `asc-3d-paths` |
| `units/<faction>/<unit>__<transformation id>_<pose>.glb` | a transformation's look of the unit it changes, 4 poses each: `spearmen__crown_celestial_host` (Sunspears), `knights__crown_living_iron` (Iron Knights), `fangthrowers__beasts_thorn_wild` (Thornthrowers), `tuskers__beasts_blood_pact` (Bloodtuskers) | batch `asc-3d-paths` |
| `units/<faction>/standard_bearer.glb`, `musician.glb` | the army extras (3D_DIRECTION §6.2): a bearer with a bare pole and crossbar (the game hangs the code banner on it), a Crown drummer and a Clans war-horn | batch `asc-3d-factions` |
| `rulers/<ruler_id>_<pose>.glb` | the 4 rulers, the same 4 poses plus `cheer` (§9.3's fifth ruler pose) | batch `asc-3d-factions` |
| `buildings/<kind>[_<variant>].glb` | fortresses, forts, villages (`_a`, `_b`), the mill, the watchtower, war camps | batch `asc-3d-factions` |
| `props/<kind>.glb` | instanced scenery: broadleaf and pine trees, rocks, standing stones | batch `asc-3d-factions` |
| `probe/` | the 3D spike's three probe models (`world3d/` still loads them) | batch `asc-3d-probe` |

`<faction>` is the faction id in `data/factions.gd` (`kingdom` = the Aurel Crown, `beasts` = the
Thornmane Clans), `<unit>` the unit type id and `<ruler_id>` the id in `data/rulers.gd`.

## How they are made

`tools/ludo/asc_3d_factions.py` holds every prompt and runs the batch (manifest
`tools/ludo/batches/asc-3d-factions.json`, per-call ledger `studio/ledgers/asc-3d-factions.jsonl`):

1. **Base picture** per unit: an editImage of its concept art (`assets/concept/units/`) into the 3D
   framing (C-model block: full figure, three-quarter view, weapon held clear of the body, both feet
   flat on the floor with no base, plain light grey). Rulers: generateWithStyle from the ruler's
   portrait. Buildings: createImage with the C-structure block. 3 candidates, one picked.
2. **Pose pictures** (`march`, `strike`, `fallen`): editImage of the picked base picture (C-pose), so
   a unit's four poses are one family. 2 candidates, one picked.
3. Picks are kept as pipeline inputs in `assets/_concept/<faction>/` (`.gdignore`d); a soft ground
   shadow under the feet is painted out first (it would come back as a fused base).
4. **Model**: create3DModel from the picked picture (sent as base64), at the faces in the table below.
5. **Slim**: `tools/ludo/glb_slim.py --albedo-only`: the colour map only, as JPEG (512 px for unit
   figures, 1024 for commanders, rulers and buildings), matte (`metallicFactor 0`). The `.import`
   embeds the texture and generates LODs.
6. **Review**: Ludo's 4 snapshots side by side, looked at before install, plus a ruler render for the
   body height. Contact sheets: `studio/contact-sheets/asc-3d-{units,rulers,buildings}.png`.

| class | faces asked | texture |
|---|---|---|
| infantry, ranged | 5,000 | 512 |
| tuskers | 6,000 | 512 |
| knights (rider and horse), war bear | 8,000 | 512 |
| commanders | 6,000 | 1024 |
| rulers / the Great Thornmane | 10,000 / 12,000 | 1024 |
| fortresses / forts | 24,000 / 14,000 | 1024 |
| villages, mill, watchtower / war camps | 8,000 / 6,000 | 512 |
| army extras | 5,000-6,000 | 512 |
| trees, rocks / standing stones | 2,000-3,000 / 4,000 | 512 |

Ludo treats `target_num_faces` as a target, not a cap: models come back up to ~25% over.

### The M4 batch (`asc-3d-paths`)

`tools/ludo/asc_3d_paths.py` (manifest `tools/ludo/batches/asc-3d-paths.json`, ledger
`studio/ledgers/asc-3d-paths.jsonl`) reuses `asc_3d_factions.py`'s driver:

- **Variants** keep the base's outline (STYLE_BIBLE §5): each of the base unit's four picked pictures is
  edited with the fork's transformation block, verbatim (`gates` checks the silhouette IoU >= 0.85).
  Sized from the base pose (its size times the picture's height ratio; a lying pose its width ratio),
  or from a ruler reading where geometry falls outside the outline (the Celestial Host's halo ring).
- **New units**: generateWithStyle with the fork's picked variant picture as the style image (a Crown
  unit anchored to a Crown picture, a Clans unit to a Clans one), poses as C-pose edits. Their pictures
  come back as a soft painted render with a soft ground shadow, which image-to-3D fused into a floor
  slab, so each is cut out (Ludo removeBackground, pixels kept) and laid on plain grey before modelling.
- The Bloodtuskers' crimson and black came back near-black from image-to-3D three times; their four
  pictures are lifted (gamma 1.5) before modelling.
- **Texture levels** (`texlevels`, `retexture`): image-to-3D returns colour maps darker than their
  pictures (#91's accepted base units sit 5-24 L* under theirs). Every path model more than 5 under is
  lifted to about 5 under, the Bloodtuskers to about 4 under their original picks; each lift is recorded
  in its `tex_lift`.

## `models.json`

```json
{
 "format": 1,
 "units":     { "<unit id>":  { "<pose>": {model}, ... }, ... },
 "rulers":    { "<ruler id>": { "<pose>": {model}, ... }, ... },
 "variants":  { "<unit id>__<transformation id>": { "<pose>": {model}, ... }, ... },
 "extras":    { "standard_bearer" | "musician": { "<faction id>": {model} } },
 "buildings": { "<kind>":     { "<variant>": {model}, ... }, ... },
 "props":     { "<kind>":     { "default": {model} } }
}
```

Poses are `ready`, `march`, `strike`, `fallen` (rulers also `cheer`). A building's variant is the faction id for faction
pieces (`fortress.kingdom`, `fort.beasts`, `camp.kingdom`), `a` / `b` for interchangeable variants
(villages), or `default`. One model per line, so a diff shows which model changed.

| field | meaning |
|---|---|
| `path` | `res://` path of the GLB |
| `kind` | `unit`, `ruler`, `variant`, `extra`, `building` or `prop` |
| `base`, `transformation`, `name` | variants: the unit it is a look of, the transformation (`data/paths.gd`) and the changed unit's name ("Sunspears"); new units carry their `transformation` too |
| `id` | unit type id, ruler id, or building kind (`fortress_kingdom`, `village_plains`, ...) |
| `faction` | `kingdom`, `beasts`, or `null` for world pieces |
| `pose` / `variant` | figures / buildings |
| `class` | figures: `infantry`, `ranged`, `mounted`, `heavy infantry`, `beast`, `commander`, `ruler`, ... |
| `size` | `{"axis": "height" \| "length" \| "width", "men": M}`: scale the model so that extent is `M` men. `height` = the AABB's y size (standing figures, weapon included); `length` = the longer of x and z (a lying figure); `width` = the longer of x and z (buildings) |
| `body_men` | figures: the body's height in men (head top, weapon excluded): spearman 1.0, crossbow 0.95, tusker 1.2, knight on horse 1.45, captain 1.1, warchief 1.3, rulers 1.25-1.4, the Great Thornmane 2.8 |
| `body_share` | figures: the share of the scaled extent that is the body (read off a ruler render at review); `size.men = body_men / body_share`, so every pose of a unit stands at the same body size even when a spear or staff rises above the head. Lunges and rears are set by eye so the crouched body matches the standing one (their `notes` say so) |
| `yaw` | radians about +Y to turn the model after loading so its front faces glTF **+Z** (a figure's face and weapon, a fortress's gate). Ludo already squares figures to the axes facing +Z, so this is 0 for every figure; `fortress_kingdom` is π (Ludo put its gate on −Z) |
| `hue_keys` | `[{"hue": h, "width": w, "part": "roofs", "share": s}]`: the baked faction colours to repaint in the owner's colour, matching `world3d/shaders/model_common.gdshaderinc` (`key_hue` = h, `key_width` = w, HSV hue 0-1). The width is the widest that stays clear of the model's other big hue clusters; `share` is the part of the colour map it covers. Empty on figures: the player colour goes on the code base ring and banner (bible §8.6) |
| `courtyard` | fortresses and forts: `{"rect": [x0, z0, x1, z1], "floor": f}`, the open yard in the **turned** frame (gate on +Z), as fractions of the scaled width from the footprint centre; `floor` = the yard floor's height above the model's bottom, as a fraction of the width (sink the model by `floor x width` to put the yard flush with a stage) |
| `gate` | fortresses and forts: `[x, z]`, the outer gate point in the turned frame, fractions of the width (all four: the middle of the +Z wall) |
| `faces`, `texture`, `bytes` | triangle count, colour map size (px), file size |
| `extent` | the raw GLB AABB size `[x, y, z]` in model units (Ludo normalises to a unit cube) |
| `notes` | what a reviewer should know (a known flaw, a by-eye size) |
| `tex_lift` | when the colour map came back crushed (near-black) and was lifted (`asc_3d_paths.py retexture`, no Ludo call): `{"gamma", "lstar_before", "lstar_after", "picture_lstar", "original_pick_lstar"?}`. The model's mean L* (its colour map sampled at every triangle's UV centroid, area-weighted) is lifted with an L* gamma that keeps each texel's chromaticity, from the raw Ludo GLB before slimming, until it sits about 5 under its picture's (`original_pick_lstar` when the picture itself was lifted before modelling) |

### On the board: `world3d/models.json`

The board reads its own table, `world3d/models.json` (format in `world3d/README.md`, read by
`world3d/models.gd`). `python3 tools/ludo/asc_3d_factions.py board` fills it from this descriptor:

- **Figures** (units, commanders, rulers): `model` = the ready pose's GLB, `height` = its `size.men`
  (the AABB height, weapon included), `yaw` = 180 + this descriptor's yaw in degrees (the board turns
  glTF's +Z front to −Z), plus `poses` (`{"ready": path, "march": ..., "strike": ..., "fallen": ...}`,
  rulers also `cheer`) and `pose_size` (`{"<pose>": {"axis", "men"}}`: each pose's own scale, so a lunge
  or a lying figure keeps the ready pose's body size) for the pose swap of M3a.2.
- **Extras:** the `bearer` row gets `models` (`{"<faction>": path}`) and `model_height`; a new
  `musician` row the same.
- **Variants** (`asc_3d_paths.py board`, which edits only its own rows, line by line): the changed
  unit's row gets an optional `"variants": {"<transformation id>": {"model", "height", "yaw", "poses",
  "pose_size"}}`, the same fields as the row's own, for the board to swap to when the transformation
  lands. `world3d/models.gd` ignores it until then.
- **Fortresses** (`fortress.kingdom`, `fortress.beasts`): `model`, `side` 76, `yaw`, `key_hue` (the
  Crown's blue roofs; −1 for the Clans: their crimson banners sit too close in hue to the timber for
  the shader's fixed 0.06 key width), `tint`, and the yard, gate and banners measured off the GLB in the
  board's fortress frame (gate on −Z): `court` [x, z, w, d], `gate_z` [inner, outer], `banner_at`,
  `sink`, `floor`.
- **Forts, villages, mill, watchtower, camps, scenery:** rows with `model`, `side` (world units across)
  or `height`, `yaw`, `key_hue` where a part repaints, `variants` for villages, `court`/`gate_z` for
  forts. The board code draws primitives for these kinds today; the rows are ready for when it reads
  them.

### Loading one (what `world3d` does for the probe, data-driven)

```gdscript
var e: Dictionary = models["units"]["spearmen"]["ready"]
var mesh: Mesh = first_mesh(load(e["path"]).instantiate()).mesh
var aabb := mesh.get_aabb()
var ext := aabb.size.y if e["size"]["axis"] == "height" else maxf(aabb.size.x, aabb.size.z)
var s: float = float(e["size"]["men"]) * MAN / ext            # MAN = world units per man
var c := aabb.get_center()
## feet (the AABB bottom) at the origin, centred on x/z, then turned to face +Z
var xf := Transform3D(Basis(Vector3.UP, float(e["yaw"])).scaled(Vector3.ONE * s), Vector3.ZERO) \
	* Transform3D(Basis(), Vector3(-c.x, -aabb.position.y, -c.z))
```

Then apply the world's own frame as today: `armies.gd` turns probe figures by π and
`world_view.gd` turns the probe fortress by π so its gate is on the fortress frame's −Z; the same
turns work on these models after `yaw`. For the spike's scale, `MAN ≈ 6.6` world units reproduces
the probe spearman (7.8 units tall with his spear) and puts a 12-men fortress at ~79 units (the
spike's `FORTRESS_SIDE` is 76).

Each GLB has one mesh and one material whose albedo is the Ludo colour map; the game draws it with
its own `piece` material (bible §8.5), reading only that texture.

## Rules

- Raw GLBs, candidates and Ludo's snapshot PNGs stay in the gitignored `candidates/` folders, never
  next to a GLB here.
- Over budget means a re-model at fewer faces, never a hand edit (bible §8.4).
- A new model needs a `models.json` row; `tools/ludo/asc_3d_factions.py install <row>` writes it.
