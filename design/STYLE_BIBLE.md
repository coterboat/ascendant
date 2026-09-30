# ASCENDANT: style bible

Status: **DRAFT v2. Waiting on Alex to pick a style direction.** Owner: art lead. Specs only. Asset builder generates from these specs; nobody else does.

Built on: `design/GAME_BRIEF.md` (**approved v2**, 2026-09-30), `design/MILESTONES.md` (M1 approved), ticket #9, and `studio/ludo-playbook.md`.

What the brief sets for art:
- An original **high-fantasy** world where rival rulers race to ascend. **Dark but not grim, colourful and characterful.**
- Rulers can be anything, from a living god or a dragon to an ordinary king.
- Factions **transform** through lock-in forks (e.g. celestial host, living iron, blood pact), so a unit's look must be able to change within a faction.
- **Battles are worth watching:** animated sprites (idle, move, attack, hit, death) plus projectiles, impacts, screen shake and readable area markers. **Readability beats spectacle.**
- 2D, one main map screen, 2–6 players, 4–6 factions, polish over breadth.

Milestones: M1 art is static only (terrain, 2 banners, 8 portraits; ticket #9). Animation arrives in M3, transformations in M4, magic and fog of war in M5. Sound is out of M1.

v1 → v2 changes: removed dominion, pretenders and scales, and the dominion overlay. Province states now follow v2. The palette is more colourful. Added unit animation, VFX, banner and transformation specs. Replaced Woodcut Myth with Bright Cel and reworked Gilded Atlas into Illuminated Storybook (see §6).

---

## 1. Palette

### 1.1 Player colours (who owns it)
Six player slots plus independents. The colour goes with the **player slot**, not the faction, so a mirror match still reads apart. Unit, portrait and banner art never carries player colour. Player identity is drawn in code (token ring, banner plaque, province tint).

| slot | name | hex | emblem (always drawn with the colour) |
|---|---|---|---|
| P1 | Vermilion | `#D8432C` | circle |
| P2 | Cobalt | `#2D5BD1` | square |
| P3 | Gold | `#F1C232` | triangle, point up |
| P4 | Sky | `#62C3F0` | diamond |
| P5 | Jade | `#2E9E6A` | hexagon |
| P6 | Magenta | `#D14FA8` | Greek cross |
| IND | Slate (independents) | `#5B5750` | heater shield |

v2: P6 moved from Bone `#EFEAE0` to Magenta for colour. It is equally safe.

Colour-blind check: Machado 2009 full-severity simulation, CIE76 ΔE between the closest pair of the 7 colours. Normal 50.5, protanopia 21.1, deuteranopia 21.8, tritanopia 20.5, so every pair stays ≥ 20 in every simulation. **Colour is never the only channel:** every player mark carries its slot emblem, and the game stays playable in greyscale. Weakest pairs: Vermilion/Jade (protan), Sky/Jade (tritan).

Against colourful terrain, a player hue alone is not enough. In the worst simulation, Jade on hills and Magenta on mountains fall to about ΔE 4. So every player-colour mark is **keylined**: a 1 px ink line `#1A1612` inside and a 1 px halo `#F4F0E8` at 70% outside. On every terrain anchor, at least one keyline is ≥ 3.5:1 (checked).

### 1.2 Terrain anchors (colourful, but quieter than the pieces)
Land textures stay in **L\* 40–78 and chroma ≤ 42**. Values inside one texture vary by ≤ 15 L\*, so pieces and icons sit on calm ground.

M1 terrains (ticket #9):

| terrain | hex | L\* | read |
|---|---|---|---|
| plains | `#B3B86A` | 73 | light, smooth, open |
| forest | `#3F7A55` | 46 | dark, bold rounded canopies |
| hills | `#B08A5E` | 60 | mid, warm, curved ridge lines |

The three are ≥ 13 L\* apart, so they separate in greyscale.

Later (proposed): farmland `#C4B26A`, mountains `#8D88A0`, swamp `#5E7A62`, waste `#CFAA74`, tundra `#D3DEE0`, sea `#2F7A93`, deep sea `#244E6E`. Map ink (borders, labels) `#2A231C`. Fog veil `#E6D9BC`.

### 1.3 UI
| role | hex | contrast on `#1C1B2A` |
|---|---|---|
| panel background (deep indigo) | `#1C1B2A` | – |
| panel raised / hover row | `#282740` | – |
| panel border | `#4E4A70` | – |
| gilt accent (headings, ascension sites, focus frame) | `#E6B84E` | 9.1:1 |
| text primary | `#F1ECE0` | 14.4:1 |
| text secondary | `#BDB6CF` | 8.7:1 |
| text disabled | `#7E7896` | 4.0:1 (disabled only) |
| positive (always with `+` or ▲) | `#72C47A` | 8.0:1 |
| negative (always with `−` or ▼) | `#F06A64` | 5.6:1 |
| warning (always with ⚠ glyph) | `#F0913A` | 7.1:1 |
| link / codex term | `#86C1F0` | 8.8:1 |
| selection | `#FFFFFF` outline 3 px | – |

Faction material palettes (worn in art, separate from player colours):
- **Kingdom:** steel, white linen, royal blue, gold.
- **Beast tribe:** tawny fur, bone, moss green, crimson war paint.

Magic-school and VFX palettes wait on M5.

## 2. Readability rules

Map zoom levels at 1920×1080 (M1 must also read at 1600×900, per #5): **far** (province ≈ 80 px across), **default** (≈ 180 px), **near** (≈ 360 px).

### 2.1 Minimum on-screen sizes
| element | default | minimum | made by |
|---|---|---|---|
| army token (idle frame 0 of the unit sprite in a player ring) | 40 px | 28 px (below that, a 16 px emblem dot) | Ludo sprite + code ring |
| faction banner on the map plaque / in panels | 48 px tall / 192 px tall | 32 px tall | Ludo |
| map building icon (fort, capital, ascension site) | 36 px | 24 px | Ludo |
| province state glyph | 20 px | 16 px | **hand-written SVG** (playbook: AI can't make a consistent, crisp set at ≤ 40 px) |
| unit class glyph (token corner) | 14 px | 12 px | hand-written SVG |
| unit portrait (recruit panel, battle report) | 128×170 px | 96×128 px | Ludo |
| battle sprite, human-sized | 96 px tall | 72 px tall | Ludo animation |
| spell / item icon | 64 px panel, 32 px list | 32 px | Ludo |
| text body / captions / numbers | 14 / 12 / 16 px | 12 px | Godot font. Generated art never carries text |

### 2.2 Player at a glance
- **Token:** sprite inside a 3 px ring in the player colour, with keylines, and the slot emblem (12 px) at the ring's top-left.
- **Owned province:** 30% multiply tint of the player colour, a 4 px inner border in the player colour with keylines, and the emblem on the name plaque.
- **Stacks:** armies of several players side by side, overlapping ≤ 25%.
- **Battle:** each side's units stand on a 2 px ground ellipse in the player colour with keylines. Units face their enemy: art faces right, and the left side is flipped with `flip_h`. Health bars are code-drawn in the player colour.

### 2.3 Unit class at a glance
Two channels: silhouette, plus a 14 px class glyph (SVG) at the token's bottom-right.

**Silhouette gate:** fill the alpha black and scale to 32 px. A reviewer must name the class, otherwise re-roll. Width:height of the figure's box:
- infantry: upright, weapon vertical near the body, ≈ 1:2
- heavy infantry: big shield or huge weapon, broad stance, ≈ 1:1.6
- ranged: bow, crossbow or javelins angled away from the body, with a visible gap between weapon and body
- mounted: a horizontal mass with the mount's legs visible, ≈ 1.3:1
- commander: a standard, staff or raised weapon ≥ 25% of figure height above the head
- caster: a robe widening like a bell, one glowing focus
- flyer: wings wider than the figure is tall
- monster / beast: non-humanoid mass ≥ 85% of its canvas height

### 2.4 Province states (v2)
Each state uses at least two channels. All drawn in code over terrain, plus the icons listed.

| state | source | encoding |
|---|---|---|
| owned | M1 | §2.2 tint + border + emblem |
| independent | brief (independents, *Sworn Vassals*) | no tint, 2 px border in map ink at 60%, slate shield emblem on the plaque |
| capital | M1 (win condition) | capital map icon + 5-point star glyph on the plaque |
| fortified | M1 (fort flag) | fort map icon + doubled border (two 2 px lines, 2 px apart) |
| battle last turn | M1 (turn report) | crossed-swords glyph 20 px, click opens the battle report |
| besieged | brief (sieges phase) | fort icon + ring of 8 chevrons in the besieger's colour + siege glyph |
| ascension site (victory province) | brief | ascension-site map icon 36 px, name plaque in gilt `#E6B84E`, owner ring once held |
| ruler present | brief (M2) | the army token gets a second gilt ring 2 px outside the player ring |
| unscouted (fog of war) | brief (M5) | terrain desaturated 70%, fog veil at 40%, fine 45° hatching, "last seen turn N" on hover |
| selected / hover | M1 | 3 px `#FFFFFF` outline + 15% brighten / 2 px `#F1ECE0` outline |

Removed in v2: the dominion overlay, and "contested" as a standing state (now "battle last turn").

### 2.5 Outline, contrast and battle legibility
- **Sprites, banners and map icons:** painted dark outline of even weight, ≥ 4 px at master size (≥ 2 px at ship). The token shader adds a 1 px screen-space `#1A1612` outline.
- **Figures:** each has a light area (L\* > 70) and a dark area (L\* < 30). Mean L\* 40–65.
- **Terrain:** §1.2 limits. Baked light flattened in post.
- **VFX:** VFX may cover a unit at > 80% opacity only during a 2-frame flash. Area markers are code-drawn (exact geometry: caster's player colour outline with keylines, 15% fill, emblem at the centre), never generated. Screen shake is code: ≤ 6 px, ≤ 0.25 s, big hits only.
- **UI:** text ≥ 4.5:1, numbers and tooltips ≥ 7:1.

## 3. Ludo rules this bible follows (`studio/ludo-playbook.md`)
1. **No negative prompts.** "no X" gets drawn. Every block here is phrased positively, including SFX (the playbook's CS wording "no reverb…" is replaced by "dry, single isolated sound, silence after"). Asset builder should refuse prompts containing `no`, `not`, `without`, `never` or `NEGATIVE`.
2. **One verbatim style block per class,** first in the prompt, never paraphrased. To tune, change the block, bump `v`, and regenerate the class.
3. **Anchor to the same class, a prop against a prop.** The picked probe of each class is its anchor (`generateWithStyle`). A transformed variant is anchored to its **own base unit** (§5). Never anchor across classes.
4. **Pick from fresh candidates; don't revise.** Default 3 candidates, kept gitignored, with the pick recorded.
5. `image_type` always explicit. `augment_prompt: false` on still images. On `animateSprite` the API requires `margin_ratio_mode` `manual` or `none` when augment is false. We keep augment on (default) for animation, with a short named motion as the swagger advises.
6. **Room in the frame:** margin on every side and headroom for raised weapons, flames and smoke.
7. **Say what the hands hold. Name the expression and eye direction.**
8. **Transparency via `removeBackground`** (`crop: true`, `creative_edit: false`). Prompts ask for a plain flat mid-grey background (VFX: flat black).
9. **True size:** animation uses `frame_size: -9` from a trimmed base frame on the family's shared padded canvas (< 1 MP). Send `crop: false` explicitly, because the API default is `crop: true` and it gives every sheet a different size. Keyframe sheets can come back with wider cells: normalise them in post.
10. **Motion:** describe the whole motion including how it ends, pin the view ("stays facing right"), stage the outcome, not the struggle. Forge for every unit and VFX sheet (Hydra has strict violence moderation and costs 9+). Pin the model per unit set. `final_image` = the base frame for loops and for returns to rest.
11. **Re-skins** (transformations) use `editSpritesheet edit_mode: prompt` with **short** wording (a long costume list failed 4/4), within 7 days of the base sheet.
12. **Text and logos are never generated. Every emblem is invented,** and anything resembling real heraldry is re-rolled.
13. **Judge side by side** on a contact sheet. Watch loops as GIF (`gif: true`, free).
14. **Audio:** sniff headers, measure durations, crossfade ambience loops, level to slot with a limiter.
15. **Budget:** ledger every charged call, cutouts and re-rolls included. Failed jobs are free.

Tool notes for asset builder (`tools/ludo/ludo.py`, copied from CONCURRENT; art lead does not edit it):
- It appends one global `style` to `image` prompts, so set `"style": false` and carry the full prompt.
- Its `request_id` prefix is `concurrent-`, so every ASCENDANT id starts with `asc_`.
- `styled` (generateWithStyle) reads its anchor from a ledger URL, which **expires after 7 days**. Run M1 production within 7 days of the probe, or add a local-file anchor.
- `animate` only sends `crop` when the manifest entry sets it. Set `"crop": false`.
- `image` always sends `n: 1`, so 3 candidates means 3 entries or takes.

## 4. Asset classes (same in every direction)

The style block and `art_style` come from the chosen direction (§6). Credits cover 3 candidates plus the cutout of the pick.

| class | Ludo call | image_type / perspective / aspect | master → ship size, frames | format | Godot path | cr / asset |
|---|---|---|---|---|---|---|
| unit sprite (base frame) | createImage → removeBackground | `sprite` / `High Angle` / `ar_1_1` | trimmed onto the family canvas (§4.1) → ship at 50% | webp lossless, alpha | `assets/units/<faction>/<unit>/<unit>_base.webp` | 2.0 |
| unit animation | §4.1 | – | §4.1 | webp lossless sheet + `.json` | `assets/units/<faction>/<unit>/<unit>_<state>.webp` | 20.5 / unit (5 states) |
| spell / impact VFX | createImage `sprite-vfx` → forge animateSprite | `sprite-vfx` / `Any perspective` / `ar_1_1` | §4.2 | webp lossless sheet + `.json` | `assets/vfx/<vfx>/<vfx>.webp` | 5.5 |
| province / terrain tile | createImage (first), generateWithStyle (rest) | `texture` / `Top-Down` / `ar_1_1` | 1024 → 512×512 seamless, 1 frame, lighting flattened (blur subtract on a 3×3 tiling), Godot repeat on | webp q90 | `assets/terrain/<terrain>.webp` | 1.5 |
| faction banner | createImage (first), generateWithStyle (rest) → removeBackground | `asset` / `Any perspective` / `ar_3_4` | → 256×384 (hang point top-centre), 1 frame | webp lossless, alpha | `assets/banners/<faction>.webp` | 2.0 |
| map icon | createImage → removeBackground | `icon` / `High Angle` / `ar_1_1` | → 128×128, subject in the centre 112×112 | webp lossless, alpha | `assets/map_icons/<icon>.webp` | 2.0 |
| spell icon (M5) | createImage | `item-icon` / `Any perspective` / `ar_1_1` | → 128×128 full bleed, opaque | webp q92 | `assets/icons/spells/<spell>.webp` | 1.5 |
| item icon (later) | createImage → removeBackground | `item-icon` / `Any perspective` / `ar_1_1` | → 128×128, subject in the centre 112×112 | webp lossless, alpha | `assets/icons/items/<item>.webp` | 2.0 |
| UI chrome | createImage | `ui_asset` / `Any perspective` / `ar_1_1` | panel → 256×256 nine-slice, margins 64; button → 256×64 three-slice, margins 24 | webp lossless | `assets/ui/<element>.webp` | 1.5 |
| portrait | createImage (first), generateWithStyle from the first (rest) | `portrait` / `Any perspective` / `ar_3_4` | 768×1024 → 384×512, eyes at 38% from the top, 1 frame | webp q90 | `assets/portraits/<faction>/<unit>.webp` | 1.5 |
| sfx (later) | `/audio/sound-effect`, 2 takes | – | trimmed to onset, UI ≤ 0.6 s, battle ≤ 2.5 s, 20 ms fade, peak −1 dBFS | 16-bit PCM WAV 44.1 kHz mono | `assets/audio/sfx/<sfx>.wav` | 4.0 |
| ambience (later) | `/audio/ambiance` (10 s cap) | – | 8–10 s loop, 0.5 s tail→head crossfade, −22 LUFS | MP3 192 kbps, loop on | `assets/audio/ambience/<amb>.mp3` | 2.0 |
| music (later) | `/audio/music`, ask 60/120 s | – | −18 LUFS integrated, −1 dBTP | MP3 192 kbps, loop on | `assets/audio/music/<track>.mp3` | 3.0 |

Hand-written SVG (not Ludo): province state glyphs, class glyphs and slot emblems, at `assets/ui/glyphs/<glyph>.svg` (24×24 viewBox, 2 px strokes, fill `#F1ECE0`, stroke `#1A1612`).

### 4.1 Unit animation (M3; spec'd now so the base frames are right)

**Shared padded canvas per family** (playbook: one canvas per family, so every sheet lines up):

| family | master canvas | figure height | feet anchor (x, y) | ship cell (50%) | ship anchor |
|---|---|---|---|---|---|
| standard (human-sized) | 384×384 | 240 px | (176, 344) | 192×192 | (88, 172) |
| large (mounted, beasts, monsters) | 576×576 | 300–400 px | (264, 528) | 288×288 | (132, 264) |

The figure is placed with extra room on its right, because attacks reach to the right. Scale by **subject height** (human = 240 px master), not by canvas.

**Base frame:** a three-quarter view **facing right**, seen from slightly above, in a ready stance. The removeBackground cutout is trimmed, then placed on the canvas at the anchor. Real alpha, downscaled premultiplied. Idle frame 0 = the base frame = the map token.

**States.** All forge, `frame_size: -9`, `crop: false`, `image_type: sprite`:

| state | Ludo call | frames | duration → credits | loop / end | playback |
|---|---|---|---|---|---|
| idle | animateSprite, `final_image` = base | 16 | 2.0 s → 4.0 | loop; drop the duplicate last frame → 15 | 8 fps |
| move | animateSprite "walking in place, stays facing right", `final_image` = base | 16 | 2.0 s → 4.0 | loop → 15 | 12 fps; the engine moves the sprite |
| attack | animateSpriteKeyframes: first = base, **middle** = strike pose (editImage on base, 0.5), final = base | 16 | 1.5 s → 4.0 + 0.5 | one-shot, returns to base | 16 fps; `impact_frame` (melee) or `release_frame` (ranged) in the JSON |
| hit | animateSprite "flinches back once from a blow, stays facing right", `final_image` = base | 9 | 1.0 s → 4.0 | one-shot, returns to base | 12 fps |
| death | animateSprite "falls and lies still on the ground, stays facing right" | 16 | 2.0 s → 4.0 | one-shot, hold the last frame | 12 fps; the body stays inside the canvas |

That's 20.5 cr per unit for sheets, plus 2.0 for the base.

Use aliases instead of paying for duplicates (e.g. a commander without a unique move reuses its idle at a higher fps). After each sheet: strip the baked ground shadow, key plate pockets (request `spritesheet_with_background`, free), and gate for grid, alpha, corners, feet baseline (move), and loop wrap ≤ 1.5× the mean frame step (loops).

**Sheet layout (SpriteFrames-friendly):** a square grid, row-major. 16 frames = 4×4, 9 frames = 3×3. Cells are exactly the ship cell size, and unused trailing cells are transparent. Each sheet has a sidecar `<unit>_<state>.json`: `{"cell":[192,192],"cols":4,"rows":4,"frames":15,"fps":8,"loop":true,"anchor":[88,172],"impact_frame":null}`. A script builds `assets/units/<faction>/<unit>/<unit>.tres` (SpriteFrames, one animation per state) from the filenames. Nobody builds it by hand in the editor. The build fails if a required state is missing.

### 4.2 Spell and impact VFX (M3/M5)

VFX is its own class and is **untinted**, drawn on a separate layer from units. Player ownership is shown by the code-drawn area marker and the caster's ring, never by the effect's colour.

| kind | master canvas → ship cell | frames | Ludo | playback | blend |
|---|---|---|---|---|---|
| impact (hit burst, explosion) | 384×384 → 192×192 | 16 (4×4) | still n=3 → forge animateSprite 1.0 s (4.0 cr), `frame_size: -9`, `crop: false`, manual margins h 0.45 / v 0.35 | one-shot, 24 fps (0.66 s), `hit_frame` in the JSON | additive on flat black |
| projectile (bolt, arrow trail, fireball) | 256×256 → 128×128 | 9 (3×3) | still → forge 1.0 s, `final_image` = first frame | loop, 12 fps; code moves it and rotates it to its heading | additive |
| cast / channel (on the caster) | 384×384 → 192×192 | 16 | still → forge 2.0 s, `final_image` = first frame | loop, 12 fps | additive |
| smoke / dust | 384×384 → 192×192 | 16 | still → removeBackground → forge 1.5 s | one-shot, 16 fps | normal alpha |
| area marker, screen shake | – | – | **code only** | – | – |

Emissive VFX are generated on flat black and blended additively (`CanvasItemMaterial.blend_mode = ADD`), with no cutout. Path: `assets/vfx/<vfx>/<vfx>.webp` + `.json`. Credits: 1.5 still + 4.0 sheet = **5.5 per effect**.

## 5. Transformations (M4; spec'd now because they shape base art)

**Recognisability contract.** A transformed variant is the same unit in a new state of being. It keeps:
1. **Silhouette:** the alpha mask overlaps the base with IoU ≥ 0.85, and height grows ≤ +15%. Beyond that it's a new unit, not a variant.
2. **Pose, canvas and anchor:** identical base-frame pose and feet anchor, and identical animation frame counts and `impact_frame`.
3. **What the hands hold:** the same objects in the same hands with the same shapes (a spear stays a spear, even if it becomes iron or light).
4. **The class read:** the same class glyph, and the silhouette gate still passes.

It changes only:
- **material** (flesh → iron, cloth → light, skin → bark)
- **palette** (the transformation palette replaces the faction palette on the changed materials)
- **overlays** (halo, glowing seams, runes, thorns). Particle auras are a separate looping VFX layer, never baked into the sheet.

**One fixed transformation block per fork,** used verbatim as the edit instruction for every unit of that fork. Short wording, per the playbook. Candidates (the director defines the real forks in M4):
- **T-ironform (living iron):** `Remake the armour, shield and skin as dark riveted living iron with thin glowing orange seams, same pose, same outline, same weapon and shield.`
- **T-celestial (celestial host):** `Remake the armour and shield as white-gold radiant armour with a soft ring of pale light behind the head, same pose, same outline, same weapon and shield.`
- **T-bloodpact (blood pact):** `Remake the skin and armour in crimson and black with small bone spurs and glowing red eyes, same pose, same outline, same weapon and shield.`

**Generation, against the base:**
1. **Static base frame:** `editImage` with the base pick as the image, the transformation block as the prompt, n = 3 (1.5 cr), then removeBackground on the pick (0.5). Gate: IoU ≥ 0.85, same anchor. The base is the anchor: a prop against a prop, same unit, same class.
2. **Sheets:** `editSpritesheet edit_mode: prompt` on each base sheet with the same block (forge, 2 cr/s, minimum 4 → 4.0 per sheet), **within 7 days of the base sheets**. Re-check the frame count (the edit can trim the clip), re-normalise cells, and keep the base JSON timings. Fallback: re-animate from the variant base frame with the base's exact motion prompts and edited keyframes.
3. **New units of a transformed faction** (roster changes): `generateWithStyle` with `style_image` = that fork's first accepted variant.
4. **Portraits:** `editImage` of the base portrait with the same block (0.5 × 3).

Paths: `assets/units/<faction>/<unit>__<fork>/…` and `assets/portraits/<faction>/<unit>__<fork>.webp`. The fork preview UI (brief: "what your units will look like") shows base and variant side by side.

Cost per transformed unit: 2.0 static + 5 × 4.0 sheets + 1.5 portrait = **23.5 cr**.

## 6. Candidate style directions (pick one)

Re-check against v2 ("colourful high fantasy with animated battles, readability over spectacle"):
- **Gilded Atlas → reworked as Illuminated Storybook.** v1 was sepia, muted watercolour on parchment. The ink line and gilt still fit, but muted washes contradict "colourful". Soft watercolour blooms are also the kind of fine texture that's hardest to hold steady across generated frames. Kept the ink and gold, switched to saturated flat gouache.
- **Painted Tabletop → kept, pushed to vivid.** Clean volumes and chunky proportions animate well and read at small sizes. Now asks for saturated colour.
- **Woodcut Myth → replaced by Bright Cel.** Its 3–4 muted flat colours contradict "colourful". Carved interior texture is the detail most likely to shift from frame to frame, and a print look fights smooth animated battles. Bright Cel keeps the woodcut's strongest point (bold, graphic readability at 32 px) and is what forge handles best ("simple body shapes").

The block goes **first**, verbatim, followed by ` Subject: <subject>.`

### Direction A: **Illuminated Storybook** (`art_style: Inked Painterly`)
A fantasy storybook come to life. A confident dark ink line, flat opaque gouache in saturated jewel tones (ultramarine, vermilion, viridian, saffron), and gold leaf on precious things. The map feels like an illuminated atlas, and battles look like pages in motion. Mood: wondrous, a little dangerous. The most distinctive, with a strong codex/storybook tie-in. Risk: ornament can clutter at small sizes (the thick-outline and silhouette gates guard against it).

- **A-unit:** `Illuminated storybook game sprite: clean confident dark ink outline of even, heavy weight around the whole figure, flat opaque gouache in saturated jewel tones with simple two-step shading, small gold-leaf accents on metal, bright even light from the upper left. Full figure in a three-quarter view facing right, seen from slightly above, feet at the bottom of the figure, single subject centred with wide empty margin on every side and clear headroom above the tallest point, plain flat mid-grey background.`
- **A-vfx:** `Illuminated storybook spell effect sprite: bold flat shapes of glowing colour from a white-hot core out to a saturated jewel-toned rim, fine gold filigree sparks, clean graphic edges, single effect centred with wide empty margin on every side, plain flat black background.`
- **A-terrain:** `Seamless tileable top-down map texture in the manner of an illuminated storybook map: flat opaque gouache in fresh saturated colours, simple repeated painted motifs with fine ink detail, low contrast within the texture, even flat lighting, uniform density from edge to edge, pattern continues across all four edges.`
- **A-banner:** `Illuminated storybook heraldic banner: one tall cloth banner hanging from a short horizontal crossbar, one bold invented emblem in the centre readable at 48 pixels, flat opaque gouache in saturated jewel tones, clean dark ink outline, gold-leaf trim, viewed straight on, single banner centred with wide empty margin, plain flat mid-grey background.`
- **A-mapicon:** `Illuminated storybook map icon: one bold simple silhouette readable at 32 pixels, heavy even dark ink outline, flat opaque gouache in saturated jewel tones with a gold-leaf accent, seen from a high three-quarter angle, single object centred with wide empty margin, plain flat mid-grey background.`
- **A-spell:** `Illuminated storybook spell icon: square composition filling the whole frame edge to edge, one central symbol with a strong silhouette readable at 32 pixels, bright glowing symbol against a deep jewel-toned background, heavy dark ink outline around the symbol, gold-leaf highlights, wordless pure pictorial image.`
- **A-item:** `Illuminated storybook item icon: one object shown whole at a slight three-quarter angle, heavy even dark ink outline, flat opaque gouache in saturated jewel tones with a gold-leaf accent, strong silhouette readable at 32 pixels, single object centred with wide empty margin, plain flat mid-grey background.`
- **A-ui:** `Game interface element in the manner of an illuminated storybook: deep indigo panel with a gilt border of fine painted vine ornament and small jewel-coloured corner medallions, flat even lighting, symmetrical, plain dark empty centre, clean straight edges, viewed straight on.`
- **A-portrait:** `Illuminated storybook portrait: head and shoulders, three-quarter view facing left, face in the upper half of the frame, clean dark ink linework, flat opaque gouache in saturated jewel tones with simple two-step shading, gold-leaf accents, bright light from the upper left, plain softly graded deep indigo background.`
- **A-sfx:** `Crisp acoustic foley of storybook fantasy materials: wood, parchment, brass, glass, cloth, stone. Close-mic, dry, single short isolated sound, clean sharp onset, quick decay into silence.`
- **A-ambience:** `Bright calm outdoor bed for a fantasy strategy map: soft breeze over meadows, lively distant songbirds, faint wind chimes, even level from start to end, seamless loop.`
- **A-music:** `Storybook fantasy score: bright woodwinds and harp over warm strings, a hand drum, lyrical modal melody, wondrous with a hint of danger, tempo around 90 bpm, instrumental.`

### Direction B: **Vivid Tabletop** (`art_style: Hand-Painted`)
The world as a lovingly painted fantasy board game. Units look like vividly painted miniatures (about 5 heads tall) with smooth volumes and soft studio light. Terrain looks like a painted diorama board. Mood: inviting, tactile, "one more turn". The best fit for approachability and animation (clean volumes hold steady across frames). Risk: reads cosy more than dangerous.

- **B-unit:** `Hand-painted game sprite of a vividly painted tabletop miniature: chunky readable proportions about five heads tall, crisp dark outline of even heavy weight, smooth painted volumes with bright highlights and clear shadows, saturated rich colours, soft studio light from the upper left. Full figure in a three-quarter view facing right, seen from slightly above, feet at the bottom of the figure, single subject centred with wide empty margin on every side and clear headroom above the tallest point, plain flat mid-grey background.`
- **B-vfx:** `Hand-painted spell effect sprite for a tabletop fantasy game: soft glowing painted energy from a white-hot core out to rich saturated colour, gentle painterly wisps and crisp bright sparks, single effect centred with wide empty margin on every side, plain flat black background.`
- **B-terrain:** `Seamless tileable top-down map texture in the manner of a vividly painted tabletop diorama board: soft painted brushwork, fresh saturated colours with gentle variation, low contrast within the texture, even flat lighting, uniform density from edge to edge, pattern continues across all four edges.`
- **B-banner:** `Hand-painted heraldic banner for a tabletop fantasy game: one tall cloth banner hanging from a short horizontal crossbar, one bold invented emblem in the centre readable at 48 pixels, smooth painted cloth folds, saturated rich colours, crisp dark outline, viewed straight on, single banner centred with wide empty margin, plain flat mid-grey background.`
- **B-mapicon:** `Hand-painted map icon of a vividly painted tabletop game piece: one bold simple silhouette readable at 32 pixels, crisp dark outline of even heavy weight, smooth painted volumes, saturated rich colours, soft light from the upper left, seen from a high three-quarter angle, single object centred with wide empty margin, plain flat mid-grey background.`
- **B-spell:** `Hand-painted spell icon for a tabletop fantasy game: square composition filling the whole frame edge to edge, one central symbol with a strong silhouette readable at 32 pixels, bright glowing symbol against a deep saturated painted background, crisp dark outline around the symbol, smooth painted volumes, wordless pure pictorial image.`
- **B-item:** `Hand-painted item icon for a tabletop fantasy game: one object shown whole at a slight three-quarter angle, crisp dark outline of even heavy weight, smooth painted volumes with bright highlights, saturated rich colours, strong silhouette readable at 32 pixels, single object centred with wide empty margin, plain flat mid-grey background.`
- **B-ui:** `Game interface element in the manner of a premium fantasy board game: deep indigo lacquered wood panel with a bevelled brass border and small rounded brass corner caps set with coloured gems, smooth painted finish, flat even lighting, symmetrical, plain dark empty centre, clean straight edges, viewed straight on.`
- **B-portrait:** `Hand-painted portrait for a tabletop fantasy game: head and shoulders, three-quarter view facing left, face in the upper half of the frame, smooth painted volumes, saturated rich colours, soft studio light from the upper left, plain softly graded deep indigo background.`
- **B-sfx:** `Warm tactile foley of game pieces: wooden tokens, cards, brass, cloth, leather. Close-mic, dry, single short isolated sound, clean sharp onset, quick decay into silence.`
- **B-ambience:** `Warm calm bed for a fantasy strategy map: gentle breeze over fields, soft rustling grass, faint far-off birds, even level from start to end, seamless loop.`
- **B-music:** `Warm cinematic fantasy strategy score: French horn melody over pizzicato strings, harp arpeggios, light timpani, adventurous and inviting, tempo around 96 bpm, instrumental.`

### Direction C: **Bright Cel** (`art_style: Cel-Shaded`)
Bold, clean high fantasy. Thick even outlines, flat saturated colour with one hard shadow tone and one highlight tone, big readable shapes. Mood: energetic and heroic, darkness carried by subject and palette rather than texture. The most legible at 32 px, the most stable to animate, and the most consistent across a large roster. Risk: less painterly character in portraits, and it can look generic without strong shape design.

- **C-unit:** `Cel-shaded game sprite of bright high fantasy: thick clean dark outline of even weight, flat saturated colours with one hard-edged shadow tone and one highlight tone, simple bold shapes and large readable forms, bright even light from the upper left. Full figure in a three-quarter view facing right, seen from slightly above, feet at the bottom of the figure, single subject centred with wide empty margin on every side and clear headroom above the tallest point, plain flat mid-grey background.`
- **C-vfx:** `Cel-shaded spell effect sprite: hard-edged flat shapes of glowing colour in three bands from a white core to a saturated rim, bold stylised sparks and shards, single effect centred with wide empty margin on every side, plain flat black background.`
- **C-terrain:** `Seamless tileable top-down cel-shaded map texture: flat saturated colour with simple hard-edged shape motifs in two close tones, low contrast within the texture, even flat lighting, uniform density from edge to edge, pattern continues across all four edges.`
- **C-banner:** `Cel-shaded heraldic banner: one tall cloth banner hanging from a short horizontal crossbar, one bold invented emblem in the centre readable at 48 pixels, flat saturated colours with one hard shadow tone, thick clean dark outline, viewed straight on, single banner centred with wide empty margin, plain flat mid-grey background.`
- **C-mapicon:** `Cel-shaded map icon: one bold simple silhouette readable at 32 pixels, thick clean dark outline, flat saturated colours with one hard shadow tone, seen from a high three-quarter angle, single object centred with wide empty margin, plain flat mid-grey background.`
- **C-spell:** `Cel-shaded spell icon: square composition filling the whole frame edge to edge, one central symbol with a strong silhouette readable at 32 pixels, bright flat symbol against a deep saturated flat background, thick clean dark outline, hard-edged highlight, wordless pure pictorial image.`
- **C-item:** `Cel-shaded item icon: one object shown whole at a slight three-quarter angle, thick clean dark outline, flat saturated colours with one hard shadow tone, strong silhouette readable at 32 pixels, single object centred with wide empty margin, plain flat mid-grey background.`
- **C-ui:** `Cel-shaded game interface element: deep indigo panel with a thick clean gold border and simple bold geometric corner pieces each set with one coloured gem, flat colours with one hard highlight tone, flat even lighting, symmetrical, plain dark empty centre, clean straight edges, viewed straight on.`
- **C-portrait:** `Cel-shaded portrait of bright high fantasy: head and shoulders, three-quarter view facing left, face in the upper half of the frame, thick clean dark outline, flat saturated colours with one hard shadow tone and one highlight tone, bold simple shapes, plain softly graded deep indigo background.`
- **C-sfx:** `Punchy stylised game foley: wood, steel, leather, bright magical chimes. Close-mic, dry, single short isolated sound, clean sharp onset, quick decay into silence.`
- **C-ambience:** `Light airy bed for a fantasy strategy map: gentle wind, rustling leaves, far-off birds, a soft warm pad, even level from start to end, seamless loop.`
- **C-music:** `Bold heroic fantasy score: brass fanfare motifs, driving drums, soaring strings, bright and determined, tempo around 110 bpm, instrumental.`

## 7. Style probe v2 (for Alex's pick)

The same subjects in all three directions. Full prompts are in `ASSET_MANIFEST.md` (status `spec`). Probe unit: a kingdom spearman, so the probe feeds M1 directly.

| subject | ids (A / B / C) | what Alex judges |
|---|---|---|
| unit base frame | `asc_probe_{storybook,tabletop,cel}_unit` | character, silhouette at 40 px |
| unit attack, animated | `asc_probe_*_unit_attack` | does the style survive motion, is it readable at 96 px |
| transformed variant (living iron) | `asc_probe_*_unit_ironform` | same unit, clearly changed |
| forest terrain | `asc_probe_*_terrain` | colourful but calm ground under a token |
| kingdom banner | `asc_probe_*_banner` | heraldry and emblem read at 48 px |
| impact effect | `asc_probe_*_impact` | spell/impact look, readability over spectacle |
| UI panel frame | `asc_probe_*_panel` | chrome mood |

Cost (swagger prices: image, style and edit 0.5 per result, removeBackground 0.5, forge animateSprite 1.5 cr/s with a **4.0 minimum**, so 1.5 s costs 4.0):

| item | per direction | × 3 |
|---|---|---|
| unit base: 3 × 0.5 + cutout 0.5 | 2.0 | 6.0 |
| unit attack: forge 1.5 s, 16 frames, `frame_size: -9`, `crop: false`, `final_image` = base | 4.0 | 12.0 |
| ironform: editImage on base, 2 × 0.5 + cutout 0.5 | 1.5 | 4.5 |
| terrain: 2 × 0.5 | 1.0 | 3.0 |
| banner: 2 × 0.5 + cutout 0.5 | 1.5 | 4.5 |
| impact still: 2 × 0.5 (flat black, additive, no cutout) | 1.0 | 3.0 |
| UI panel: 2 × 0.5 | 1.0 | 3.0 |
| **planned** | **12.0** | **36.0** |
| re-roll reserve (one forge re-roll, or 8 image results) | | 4.0 |
| **hard cap** | | **40.0** |

Trimmed to fit: candidates cut from 3 to 2 everywhere except the unit base (the anchor for the attack and the variant). The impact effect is a still, because animating it would cost 4.0 more per direction. **Music dropped** (9.0 cr for three cues, and sound is out of M1). The spell icon was dropped in favour of the impact effect (battle pillar). The attack is a plain animateSprite rather than keyframes (saves the 0.5 strike pose). Production attacks use keyframes (§4.1).

Order: unit base → cutout → canvas placement (384×384, feet (176, 344)) → attack sheet and ironform in the same run (the 7-day edit window). Check `--account` (free) before and after, and ledger every call.

Delivery (asset builder): one review PR, `assets: style probe v2`, with outputs in `assets/_probe/<direction>/` and `assets/_probe/contact_sheet.webp`. The sheet has 3 rows (directions) and these columns:
- base at 192 and at 40 px in a Vermilion ring on the forest tile
- attack as a GIF link, plus a 4-frame strip
- base and ironform side by side, with the silhouette IoU number
- terrain with the token on it
- banner at 192 and 48 px
- impact over the unit
- panel

Add one mock 180 px province per direction: forest, 30% Cobalt tint, 4 px keylined border, banner plaque, token.

After Alex picks: the winning probes become the class anchors (`assets/_anchors/<class>.webp`), and the rest are dropped. The picked `asc_probe_*_terrain` can be installed as the M1 forest.

## 8. After the pick
Keep one direction in §6, delete the others, and set status to **ACTIVE**. Fill every `{STYLE_BLOCK:<class>}` placeholder in the manifest with the chosen literal block and bump `v`.
