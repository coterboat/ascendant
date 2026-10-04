# ASCENDANT: style bible

Status: **FINAL. Direction: Bright Cel, picked by Alex on 2026-09-30** from the style probe (PR #12, review only, not merged). Owner: art lead. Specs only. Asset builder generates from these specs; nobody else does. Changing a style block needs art lead to change it here and bump `v` on the affected manifest rows.

**3D (2026-10-04).** The game is now 3D with a 2D interface (Alex's call; see `design/3D_DIRECTION.md`). §1–§7 still govern all 2D art, and now also govern **concept art (the input pictures for 3D models) and portraits**, as well as lore art, the UI, icons and banners. §8 governs the 3D world. The director proposed it, and the art lead adopts or changes it after the 3D spike.

Built on: `design/GAME_BRIEF.md` (approved v2), `design/MILESTONES.md` (M1 approved), ticket #9, `studio/ludo-playbook.md` §1–9, and the probe findings in playbook §10 (on the PR #12 ref, `probe12`).

What the brief sets for art:
- Original **high fantasy**, dark but not grim, **colourful and characterful**.
- Rulers can be anything. Factions **transform** through lock-in forks.
- **Battles are worth watching:** animated sprites (idle, move, attack, hit, death), projectiles, impacts, screen shake and readable area markers. **Readability beats spectacle.**
- 2D, one main map screen, 2–6 players.

Milestones:
- **M1 (now):** static only. Terrain, 2 banners, 8 portraits (#9 → #10).
- **Later:** M3 animation and VFX, M4 transformations, M5 magic and fog. Sound isn't scheduled yet.

Directions probed and rejected on 2026-09-30: Illuminated Storybook and Vivid Tabletop.

---

## 1. Palette

### 1.1 Player colours (who owns it)
Six slots plus independents. The colour goes with the **player slot**, not the faction. Unit, portrait and banner art never carries player colour. Player identity is drawn in code (token ring, banner plaque, province tint).

| slot | name | hex | emblem (always drawn with the colour) |
|---|---|---|---|
| P1 | Vermilion | `#D8432C` | circle |
| P2 | Cobalt | `#2D5BD1` | square |
| P3 | Gold | `#F1C232` | triangle, point up |
| P4 | Sky | `#62C3F0` | diamond |
| P5 | Jade | `#2E9E6A` | hexagon |
| P6 | Magenta | `#D14FA8` | Greek cross |
| IND | Slate (independents) | `#5B5750` | heater shield |

**Colour-blind check** (Machado 2009 full-severity simulation, CIE76 ΔE between the closest pair): normal 50.5, protanopia 21.1, deuteranopia 21.8, tritanopia 20.5. Colour is never the only channel: the slot emblem always goes with it, so the game stays playable in greyscale.

**Keylines.** Every player-colour mark gets a 1 px ink line `#1A1612` inside and a 1 px halo `#F4F0E8` at 70% outside. At least one of the two is ≥ 3.5:1 on every terrain anchor. This matters because hue alone can drop to ΔE ≈ 4 on some terrain in the worst simulation.

### 1.2 Terrain anchors (colourful, but quieter than the pieces)
Land textures: **mean L\* within ±6 of the anchor**, overall L\* 40–78, chroma ≤ 42, and **≤ 15 L\* variation inside a texture**. Variation is measured as the range (max − min) of the 64×64 block-mean L\* over the 512×512 tile, an 8×8 grid of blocks. Reference: the shipped M1 forest measures 12.2.

| terrain (M1) | hex | target mean L\* | read |
|---|---|---|---|
| plains | `#B3B86A` | 73 | light, smooth, open |
| forest | `#3F7A55` | 46 | the darkest terrain, but still mid-tone: bold rounded canopies |
| hills | `#B08A5E` | 60 | mid, warm, curved ridge lines |

Later (proposed): farmland `#C4B26A`, mountains `#8D88A0`, swamp `#5E7A62`, waste `#CFAA74`, tundra `#D3DEE0`, sea `#2F7A93`, deep sea `#244E6E`. Map ink `#2A231C`. Fog veil `#E6D9BC`.

**Probe finding:** Ludo's `texture` renders forest far too dark (all 6 candidates had mean L\* 27–30, cel pick 29.4). The cel terrain block (§6) is reworded toward light, sunlit values, and §4 adds a lightness gate with a post-process correction.

### 1.3 UI
| role | hex | contrast on `#1C1B2A` |
|---|---|---|
| panel background (deep indigo) | `#1C1B2A` | – |
| panel raised / hover row | `#282740` | – |
| panel border | `#4E4A70` | – |
| gilt accent | `#E6B84E` | 9.1:1 |
| text primary | `#F1ECE0` | 14.4:1 |
| text secondary | `#BDB6CF` | 8.7:1 |
| text disabled | `#7E7896` | 4.0:1 (disabled only) |
| positive (with `+`/▲) | `#72C47A` | 8.0:1 |
| negative (with `−`/▼) | `#F06A64` | 5.6:1 |
| warning (with ⚠) | `#F0913A` | 7.1:1 |
| link / codex term | `#86C1F0` | 8.8:1 |
| selection | `#FFFFFF` outline 3 px | – |

Faction material palettes, worn in art and independent of player colour:
- **Kingdom (`kingdom`):** steel, white linen, royal blue, gold.
- **Beast tribe (`beasts`):** tawny fur, bone, moss green, crimson war paint.

## 2. Readability rules

Map zoom levels at 1920×1080 (also check 1600×900): **far** (province ≈ 80 px), **default** (≈ 180 px), **near** (≈ 360 px).

### 2.1 Minimum on-screen sizes
| element | default | minimum | made by |
|---|---|---|---|
| army token (idle frame 0 in a player ring) | 40 px | 28 px (below that, a 16 px emblem dot) | Ludo + code ring |
| faction banner (map plaque / panels) | 48 / 192 px tall | 32 px tall | Ludo |
| map building icon | 36 px | 24 px | Ludo |
| province state glyph | 20 px | 16 px | hand-written SVG |
| unit class glyph | 14 px | 12 px | hand-written SVG |
| unit portrait (recruit panel, battle report) | 128×170 px | 96×128 px | Ludo |
| battle sprite, human-sized | 96 px tall | 72 px tall | Ludo animation |
| spell / item icon | 64 / 32 px | 32 px | Ludo |
| text body / captions / numbers | 14 / 12 / 16 px | 12 px | Godot font. Art never carries text |

### 2.2 Player at a glance
- **Token:** a 3 px ring in the player colour with keylines, and the slot emblem at top-left.
- **Owned province:** 30% multiply tint, a 4 px keylined inner border, and the emblem on the plaque.
- **Stacks:** overlap ≤ 25%.
- **Battle:** a keylined 2 px ground ellipse in the player colour. Art faces right, and the left side flips with `flip_h`. Health bars are code-drawn.

### 2.3 Unit class at a glance
Silhouette plus a 14 px class glyph. **Gate:** fill the alpha black at 32 px, and a reviewer must name the class. Width:height of the figure's box:
- infantry: weapon upright near the body, ≈ 1:2
- heavy infantry: big shield or weapon, ≈ 1:1.6
- ranged: weapon angled away with a visible gap
- mounted: ≈ 1.3:1 with the mount's legs visible
- commander: a standard, staff or raised weapon ≥ 25% of figure height above the head
- caster: a bell-shaped robe plus a glowing focus
- flyer: wings wider than tall
- monster / beast: ≥ 85% of its canvas height

### 2.4 Province states (v2)
| state | source | encoding |
|---|---|---|
| owned | M1 | tint + keylined border + emblem |
| independent | brief | no tint, 2 px map-ink border at 60%, slate shield emblem |
| capital | M1 | capital map icon + 5-point star glyph |
| fortified | M1 | fort map icon + doubled border |
| battle last turn | M1 | crossed-swords glyph 20 px, opens the battle report |
| besieged | brief | fort icon + 8 chevrons in the besieger's colour + siege glyph |
| ascension site | brief | ascension-site icon 36 px, gilt name plaque, owner ring once held |
| ruler present | M2 | second gilt ring outside the token's player ring |
| unscouted (fog) | M5 | terrain desaturated 70%, fog veil at 40%, 45° hatching, "last seen turn N" |
| selected / hover | M1 | 3 px `#FFFFFF` + 15% brighten / 2 px `#F1ECE0` |

### 2.5 Outline, contrast, battle legibility
- **Sprites, banners, map icons:** thick even dark outline (≥ 4 px at master, ≥ 2 px at ship). The token shader adds a 1 px screen-space `#1A1612` outline.
- **Figures:** have both a light area (L\* > 70) and a dark area (L\* < 30). Mean figure L\* 40–65.
- **Terrain:** the §1.2 limits and the lightness gate.
- **VFX:** above 80% opacity over a unit only during a 2-frame flash. Area markers are code-drawn (caster colour, keylines, 15% fill, emblem). Screen shake is code: ≤ 6 px, ≤ 0.25 s, big hits only.
- **UI:** text ≥ 4.5:1, numbers and tooltips ≥ 7:1.

## 3. Ludo rules this bible follows

From `studio/ludo-playbook.md` §1–9:
1. **No negative prompts.** Every block is phrased positively. Refuse any prompt containing `no`, `not`, `without`, `never` or `NEGATIVE`.
2. **One verbatim style block per class** (§6), first in the prompt, then ` Subject: …`. Tune the block, never an individual prompt.
3. **Anchor to the same class, a prop against a prop** (§6.2). A transformed variant is anchored to its own base unit. **A cross-faction style anchor must be desaturated to greyscale, or be a same-faction asset,** because colour and costume leak through style matching. On PR #14 the spearman anchor put the kingdom's blue tabard, gold trim and human faces into 8 of 9 beast portrait candidates, and the kingdom banner anchor put blue into all 3 beast banners.
4. **Pick from fresh candidates; don't revise.** 3 candidates by default. The pick is recorded, and candidates are never committed (§3, rule 16).
5. `image_type` always explicit. `augment_prompt: false` on stills and edits. Animation keeps augment on with short named motions.
6. **Room in the frame.** Say what the hands hold. Name the expression and eye direction.
7. **True size:** `frame_size: -9` from a trimmed base on the family canvas (< 1 MP). Always send `crop: false`. Normalise keyframe cells in post.
8. **Forge** for every unit and VFX sheet. Pin the model per set. `final_image` = base for loops and returns to rest.
9. **Re-skins:** `editSpritesheet edit_mode: prompt` with short wording, within 7 days of the base sheet.
10. **No generated text or logos. Every emblem is invented.**
11. **Judge side by side** (§7). Watch every sheet as a GIF.
12. **Ledger every charged call.** Failed and canceled jobs are free.

From the probe (playbook §10, PR #12):

13. **Native alpha.** `sprite`, `sprite-vfx` and `ui_asset` come back as RGBA with a transparent background at about 768 px, even though prompts ask for grey or black. `texture` and `asset` come back opaque (1024², and 864×1152 for `ar_3_4`).
    - A removeBackground cutout on a `sprite` pick is close to a no-op (alpha differs by 1–4 levels). **Cutouts are only for opaque types** (`asset` banners, map icons that come back opaque), or when native alpha fails its gate.
    - `sprite-vfx` needs no cutout. **Flatten it onto `#000`** for additive use.
    - `ui_asset` can key out a panel's own dark centre. **Gate: panel centre alpha = 255.**
14. **Forge trims every sheet**, even with `loop: false`, and frame 0 isn't guaranteed to be your input. **Gate every sheet: frame 0 matches the base** (bbox offset ≤ 2 px, mean alpha difference ≤ 3%) before use.
15. **One-phrase attacks fail** (1 clean take in 4, and the cel re-roll lost the spearhead in frames 4–8). Attacks are **always keyframed** (§4.1). Pole-arms get the **reach canvas**.
16. **Candidates never go into git.** PR #12 committed about 26 MB of `candidates/` plus a `.pyc`. Every batch PR keeps `**/candidates/`, raw masters, `__pycache__/` and `.env*` gitignored.
17. **Feet anchor** = the bbox midpoint of the bottom 15% of the alpha (the bottom 6% catches only the rear boot on a three-quarter figure).
18. **Canceling a queued job refunds it,** but its `request_id` stays bound to the canceled job. Bump `v` before resubmitting.
19. **Budget guard** = `balance_before − credits.available` (holds are taken when a job is accepted) plus the next call's cost. Don't add an in-flight tally on top.

ludo.py (asset builder's tool; art lead doesn't edit it):
- Set **both** `"style": false` and an explicit `art_style` per entry (the global `art_style` still applies otherwise).
- Its request ids are `concurrent-…`. It always sends `n: 1`.
- `cutout: true` cuts out every take, not just the pick.
- `fit` shells out to macOS `sips` and fails on the Linux box.
- `styled` reads its anchor from a ledger URL that expires after 7 days (§6.2).

## 4. Asset classes

Style blocks are in §6. `art_style: Cel-Shaded` everywhere. The credits column assumes 3 candidates.

| class | Ludo call | image_type / perspective / aspect | master → ship size, frames | format | Godot path | gates | cr / asset |
|---|---|---|---|---|---|---|---|
| unit base frame | createImage (native alpha) | `sprite` / `High Angle` / `ar_1_1` | trimmed onto the family canvas (§4.1) → ship at 50% | webp lossless, alpha | `assets/units/<faction>/<unit>/<unit>_base.webp` | silhouette gate, feet anchor, figure L\* 40–65 | 1.5 |
| unit animation | §4.1 | – | §4.1 | webp lossless sheet + `.json` | `assets/units/<faction>/<unit>/<unit>_<state>.webp` | frame-0 gate, weapon present in every frame, loop wrap | 21.5 / unit |
| spell / impact VFX | createImage (native alpha) → flatten on black → forge | `sprite-vfx` / `Any perspective` / `ar_1_1` | §4.2 | webp lossless (on black) + `.json` | `assets/vfx/<vfx>/<vfx>.webp` | frame-0 gate, ≤ 2 flash frames above 80% | 5.5 |
| terrain | createImage (anchor), generateWithStyle (rest) | `texture` / `Top-Down` / `ar_1_1` | 1024 → 512×512 seamless | webp q90 | `assets/terrain/<terrain>.webp` | **lightness gate** (below), seams on a 3×3 tile, ≥ 12 L\* between M1 terrains | 1.5 |
| faction banner | createImage (anchor), generateWithStyle (rest) → removeBackground | `asset` / `Any perspective` / `ar_3_4` | 864×1152 → 256×384, hang point top-centre | webp lossless, alpha | `assets/banners/<faction>.webp` | emblem readable at 48 px and in greyscale, clean alpha | 2.0 |
| map icon | createImage (+ cutout if opaque) | `icon` / `High Angle` / `ar_1_1` | → 128×128, subject in the centre 112 | webp lossless, alpha | `assets/map_icons/<icon>.webp` | readable at 24 px | 1.5–2.0 |
| spell icon (M5) | createImage | `item-icon` / – / `ar_1_1` | → 128×128 opaque | webp q92 | `assets/icons/spells/<spell>.webp` | readable at 32 px | 1.5 |
| item icon (later) | createImage (+ cutout if opaque) | `item-icon` / – / `ar_1_1` | → 128×128 | webp lossless, alpha | `assets/icons/items/<item>.webp` | readable at 32 px | 1.5–2.0 |
| UI chrome | createImage (native alpha) | `ui_asset` / – / `ar_1_1` | panel → 256×256 nine-slice, margins 64; button → 256×64 three-slice, margins 24 | webp lossless | `assets/ui/<element>.webp` | **centre alpha = 255**, corners match | 1.5 |
| portrait | createImage (anchor), generateWithStyle (rest) | `portrait` / – / `ar_3_4` | → 384×512, eyes at 35–41% from the top | webp q90 | `assets/portraits/<faction>/<unit>.webp` | named held item visible, faction read at 96×128 | 1.5 |
| sfx / ambience / music | `/audio/*` | – | as in playbook §7 | WAV 16-bit mono / MP3 192k | `assets/audio/{sfx,ambience,music}/<id>` | onset, loop seam, loudness | 4.0 / 2.0 / 3.0 |

Hand-written SVG (not Ludo): state glyphs, class glyphs and slot emblems at `assets/ui/glyphs/<glyph>.svg`. 24×24 viewBox, 2 px strokes, fill `#F1ECE0`, stroke `#1A1612`.

**Terrain lightness gate** (post-process, free):
1. Measure the mean L\* of the 512 texture.
2. Within ±6 of the target (forest 46, plains 73, hills 60): pass.
3. Off by up to 15: shift L\* in Lab and keep a/b, so hue and chroma stay put, then re-check seams and the internal variation. That is ≤ 15 L\*, measured as max − min of the 64×64 block-mean L\* on the 8×8 grid of the 512×512 tile (shipped forest: 12.2).
4. Off by more than 15: re-roll instead (0.5 per result).

Record the measured and corrected L\* in the batch notes.

### 4.1 Unit animation (M3)

Family canvases (masters stay < 1 MP):

| family | master canvas (w×h) | figure height | feet anchor (x, y) | ship cell (50%) | ship anchor |
|---|---|---|---|---|---|
| standard (human-sized, short weapons) | 384×384 | 240 px | (176, 344) | 192×192 | (88, 172) |
| **reach** (human-sized pole-arms: spears, pikes, lances on foot) | **512×384** | 240 px | (176, 344) | 256×192 | (88, 172) |
| large (mounted, beasts, monsters) | 576×576 | 300–400 px | (264, 528) | 288×288 | (132, 264) |

The reach canvas keeps the standard feet anchor, so reach and standard units line up in formation. The extra 128 px is all on the right, for the thrust. `frame_size: -9` returns the input canvas. Asset builder should confirm on the first reach sheet that non-square canvases come back unchanged; if not, fall back to 512×512 with the feet at (176, 472). Probe evidence: a level spear is about 1.4× figure height and rested at x ≈ 351–359 on the 384 canvas.

**Base frame:** three-quarter view **facing right**, seen from slightly above, ready stance. **Pole-arms are held upright in the base frame** (it reads as infantry per §2.3, keeps the rest pose inside any canvas, and serves as the token). Idle frame 0 = base = map token.

**States.** All forge, `frame_size: -9`, `crop: false`, `image_type: sprite`. Every sheet passes the frame-0 gate:

| state | Ludo call | frames | duration → cr | loop / end | playback |
|---|---|---|---|---|---|
| idle | animateSprite, `final_image` = base | 16 | 2.0 s → 4.0 | loop; drop the duplicate last frame → 15 | 8 fps |
| move | animateSprite "walking in place, stays facing right", `final_image` = base | 16 | 2.0 s → 4.0 | loop → 15 | 12 fps; the engine translates |
| attack | **keyframed, below** | 16 | 1.5 s → 4.0 + 1.5 strike pose | one-shot, returns to base | 16 fps; `impact_frame` / `release_frame` |
| hit | animateSprite "flinches back once from a blow, stays facing right", `final_image` = base | 9 | 1.0 s → 4.0 | one-shot, returns to base | 12 fps |
| death | animateSprite "falls and lies still on the ground, stays facing right" | 16 | 2.0 s → 4.0 | one-shot, hold the last frame, body inside the canvas | 12 fps |

**Attack, always keyframed:**
1. **Start** = the base frame.
2. **Strike** = `editImage` on the base, n = 3 (1.5 cr): *"The same figure at the moment of the strike: <one plain line of the pose, e.g. lunging forward with the spear thrust fully level to the right>, same outfit, same outline style, stays facing right."* Pick the candidate whose weapon is whole and inside the canvas. Place it on the same canvas with the same feet anchor.
3. **End** = the base frame.
4. `animateSpriteKeyframes` with `initial_image` = start, `middle_image` = strike, `final_image` = end, `model: forge`, `duration: 1.5`, `frames: 16`, `frame_size: -9`, `crop: false`, `loop: false`. The motion prompt is one short phrase ("strikes, then returns to the ready stance").
5. Gates: frame 0 = base, the weapon is whole in every frame (review the GIF), and the cells are normalised back to the canvas.

Per unit: 1.5 base + 4 + 4 + 5.5 + 4 + 4 = **23.0 cr**. Plan **×1.5 for re-rolls** (the probe re-rolled 1 of 4 sheets and still wasn't clean).

**Sheet layout (SpriteFrames-friendly):** square grid, row-major (16 = 4×4, 9 = 3×3). Cells are exactly the ship cell, and unused cells are transparent. Each sheet has a sidecar `<unit>_<state>.json`, e.g. `{"cell":[192,192],"cols":4,"rows":4,"frames":15,"fps":8,"loop":true,"anchor":[88,172],"impact_frame":null}`. `impact_frame` is measured, not guessed: the frame of furthest reach, with a `_why` line. A script builds `assets/units/<faction>/<unit>/<unit>.tres` from the filenames and fails if a state is missing. Use aliases instead of duplicate generations.

### 4.2 Spell and impact VFX (M3/M5)
VFX are untinted, on their own layer. Ownership comes from the code-drawn area marker and the caster's ring.

| kind | master → ship cell | frames | Ludo | playback | blend |
|---|---|---|---|---|---|
| impact | 384×384 → 192×192 | 16 | still n=3 (native alpha, flattened onto `#000`) → forge 1.0 s (4.0), `frame_size: -9`, `crop: false`, manual margins h 0.45 / v 0.35 | one-shot, 24 fps, `hit_frame` | additive |
| projectile | 256×256 → 128×128 | 9 | still → forge 1.0 s, `final_image` = first frame | loop, 12 fps; code moves and rotates it | additive |
| cast / channel | 384×384 → 192×192 | 16 | still → forge 2.0 s, `final_image` = first frame | loop, 12 fps | additive |
| smoke / dust | 384×384 → 192×192 | 16 | still (keep native alpha) → forge 1.5 s | one-shot, 16 fps | normal alpha |
| area marker, screen shake | – | – | code only | – | – |

## 5. Transformations (M4)

**Recognisability contract.** A variant keeps:
1. **Silhouette:** alpha IoU ≥ 0.85 against the base, height ≤ +15%. The probe got 0.96–0.995 on all 6 candidates.
2. **Pose, canvas, anchor and animation timings.**
3. **What the hands hold:** same objects, same hands, same shapes.
4. **The class read.**
5. **One faction accent keeps its hue** (plume, tabard trim or banner cloth), so the faction still reads. The probe's iron-plume candidate lost the kingdom read.

It changes only material, the palette of the changed materials, and overlays. Auras are a separate looping VFX layer.

**Transformation blocks** (edit instructions, verbatim for every unit of a fork; the director fixes the real forks in M4):
- **T-ironform:** `Remake the armour, shield and skin as dark riveted living iron with thin glowing orange seams, same pose, same outline, same weapon and shield, same coloured plume and trim.`
- **T-celestial:** `Remake the armour and shield as white-gold radiant armour with a soft ring of pale light behind the head, same pose, same outline, same weapon and shield, same coloured plume and trim.`
- **T-bloodpact:** `Remake the skin and armour in crimson and black with small bone spurs and glowing red eyes, same pose, same outline, same weapon and shield, same coloured plume and trim.`

v2 → final: added the accent clause. Probe ironform edits sometimes turned the spear and plume to iron, or left the face as flesh. Check both at pick time.

**Generation against the base:**
1. **Static:** `editImage` on the base pick with the block, n = 3 (1.5 cr). Native alpha from edits wasn't measured, so cut out only if the alpha fails. Gates: IoU ≥ 0.85, same anchor, accent kept.
2. **Sheets:** `editSpritesheet edit_mode: prompt` on each base sheet, same block, forge (4.0 per sheet), within 7 days of the base sheets. Re-check frames and frame 0, and keep the base JSON timings. Fallback: re-animate from the variant base with the base's keyframes edited the same way.
3. **New units of a transformed faction:** `generateWithStyle` with `style_image` = the fork's first accepted variant.
4. **Portraits:** `editImage` of the base portrait with the block (1.5).

Paths: `assets/units/<faction>/<unit>__<fork>/…`, `assets/portraits/<faction>/<unit>__<fork>.webp`. About 23.5 cr per unit per fork.

## 6. Direction: Bright Cel (`art_style: Cel-Shaded`)

Bold, clean high fantasy. Thick even outlines, flat saturated colour with one hard shadow tone and one highlight tone, and big readable shapes. Darkness comes from subject and palette, not texture. The most legible at 32 px and the most stable to animate.

### 6.1 Style blocks (one per class, verbatim, first in the prompt)
- **C-unit:** `Cel-shaded game sprite of bright high fantasy: thick clean dark outline of even weight, flat saturated colours with one hard-edged shadow tone and one highlight tone, simple bold shapes and large readable forms, bright even light from the upper left. Full figure in a three-quarter view facing right, seen from slightly above, feet at the bottom of the figure, single subject centred with wide empty margin on every side and clear headroom above the tallest point, plain flat mid-grey background.`
- **C-vfx:** `Cel-shaded spell effect sprite: hard-edged flat shapes of glowing colour in three bands from a white core to a saturated rim, bold stylised sparks and shards, single effect centred with wide empty margin on every side, plain flat black background.`
- **C-terrain (v2, lighter):** `Seamless tileable top-down cel-shaded map texture in bright sunlit daylight: light mid-tone colours, flat saturated colour with simple hard-edged shape motifs in two close light tones, soft pale highlights, low contrast within the texture, even flat lighting, uniform density from edge to edge, pattern continues across all four edges.`
- **C-banner:** `Cel-shaded heraldic banner: one tall cloth banner hanging from a short horizontal crossbar, one bold invented emblem in the centre readable at 48 pixels, flat saturated colours with one hard shadow tone, thick clean dark outline, viewed straight on, single banner centred with wide empty margin, plain flat mid-grey background.`
- **C-mapicon:** `Cel-shaded map icon: one bold simple silhouette readable at 32 pixels, thick clean dark outline, flat saturated colours with one hard shadow tone, seen from a high three-quarter angle, single object centred with wide empty margin, plain flat mid-grey background.`
- **C-spell:** `Cel-shaded spell icon: square composition filling the whole frame edge to edge, one central symbol with a strong silhouette readable at 32 pixels, bright flat symbol against a deep saturated flat background, thick clean dark outline, hard-edged highlight, wordless pure pictorial image.`
- **C-item:** `Cel-shaded item icon: one object shown whole at a slight three-quarter angle, thick clean dark outline, flat saturated colours with one hard shadow tone, strong silhouette readable at 32 pixels, single object centred with wide empty margin, plain flat mid-grey background.`
- **C-ui:** `Cel-shaded game interface element: deep indigo panel with a thick clean gold border and simple bold geometric corner pieces each set with one coloured gem, solid opaque deep indigo centre, flat colours with one hard highlight tone, flat even lighting, symmetrical, clean straight edges, viewed straight on.`
- **C-portrait:** `Cel-shaded portrait of bright high fantasy: head and shoulders, three-quarter view facing left, face in the upper half of the frame, thick clean dark outline, flat saturated colours with one hard shadow tone and one highlight tone, bold simple shapes, plain softly graded deep indigo background.`
- **C-sfx:** `Punchy stylised game foley: wood, steel, leather, bright magical chimes. Close-mic, dry, single short isolated sound, clean sharp onset, quick decay into silence.`
- **C-ambience:** `Light airy bed for a fantasy strategy map: gentle wind, rustling leaves, far-off birds, a soft warm pad, even level from start to end, seamless loop.`
- **C-music:** `Bold heroic fantasy score: brass fanfare motifs, driving drums, soaring strings, bright and determined, tempo around 110 bpm, instrumental.`

Changed after the probe:
- **C-terrain** now asks for bright sunlit light values (the probe forest came out at L\* 29).
- **C-ui** now asks for a "solid opaque deep indigo centre" (the probe showed `ui_asset` can key out a dark centre). It was "plain dark empty centre".

Everything else is exactly as probed.

### 6.2 Style anchors (the picked cel probe candidates)

| class | anchor (pick) | file on the PR #12 ref (`git fetch origin pull/12/head:probe12`) | use |
|---|---|---|---|
| unit | unit base **c3** | `assets/_probe/cel/candidates/asc_probe_cel_unit_v1_c3.webp` (raw 768), `…/asc_probe_cel_unit_c3_cut.png` (cutout), `…/asc_probe_cel_unit_canvas384.png` (on canvas) | `style_image` for new unit base frames. Keyframe base for the probe spearman |
| terrain | forest **c1** | `assets/_probe/cel/candidates/asc_probe_cel_terrain_v1_c1.webp` | **too dark (L\* 29.4).** Style reference only after a Lab lift to L\* 46. The working terrain anchor is the M1 forest generated from the v2 block, once it passes the lightness gate |
| banner | kingdom banner **c2** | `assets/_probe/cel/candidates/asc_probe_cel_banner_v1_c2.webp` (raw), `…/asc_probe_cel_banner_c2_cut.png` (cutout) | `style_image` for other banners. Same subject as `asc_m1_banner_kingdom` |
| VFX | impact **c1** | `assets/_probe/cel/candidates/asc_probe_cel_impact_v1_c1.webp` | `style_image` for VFX stills |
| UI | panel **c2** | `assets/_probe/cel/candidates/asc_probe_cel_panel_v1_c2.webp` | `style_image` for UI chrome |
| portrait (kingdom) | none probed | M1 `asc_m1_portrait_kingdom_spearmen` pick (PR #14, `assets/portraits/kingdom/spearmen.webp`) | anchors the kingdom portraits. It also anchored tuskers before the leak was found |
| portrait (beasts) | tuskers **c2** | M1 `asc_m1_portrait_beasts_tuskers` pick (PR #14, `assets/portraits/beasts/tuskers.webp`) | anchors fangthrowers, war bear and warchief (a same-faction anchor) |
| banner (cross-faction) | banner **c2, greyscale** | a greyscale copy of `asc_probe_cel_banner_v1_c2.webp`, made locally (e.g. `assets/_anchors/banner_grey.webp`) | anchors the beast banner and any other faction's banner. The colour c2 anchors only kingdom assets |

**Anchors come from local files, not Ludo URLs.** Ludo result URLs expire after 7 days (the probe ran on 2026-09-30 01:24–01:56 ET, so they die around 2026-10-07). ludo.py's `styled` kind reads the anchor from a ledger URL. So:
- Asset builder copies these files out of `probe12` into `assets/_anchors/<class>.<ext>` (with a `.gdignore`, so Godot doesn't import them).
- Every `generateWithStyle` call sends the anchor as a **base64 `style_image`** from that local file (the API accepts URL or base64, max 15 MB).
- The anchors are pipeline inputs and small (≤ 1024 px each), so they're committed in the #10 PR. Candidates are not.

## 7. Contact sheets

- **Probe (multi-direction, done):** rows were subjects and columns were directions, with every candidate shown and a green frame on the pick. That's what PR #12 did, and it worked. Use it again for any future multi-direction probe.
- **Single-direction batch (every production batch from now on, e.g. #10):**
  - One image `studio/contact-sheets/<batch>.png`, ≤ 3000 px wide, ≤ 3 MB. It's linked in the PR description, and asset builder decides whether to commit it.
  - Background `#1C1B2A`, labels in `#F1ECE0`.
  - **Rows = asset groups in manifest order, columns = the assets of that group.** For M1: row 1 is terrains (3), row 2 is banners (2), row 3 is kingdom portraits (4), row 4 is beast portraits (4).
  - Each cell shows the pick at ship size with a green frame, the other candidates small beneath it, and the id and measured gate numbers under it.
  - **Per-group extras:**
    - terrain: a 3×3 tile at 50%, a greyscale strip of all three, and an 80 px province mock of each with a 40 px token and a 30% Cobalt tint
    - banners: 192 px, 48 px, and 48 px greyscale
    - portraits: 384×512 and 96×128
  - GIFs for animated rows go next to the sheet as `studio/contact-sheets/<batch>-<id>.gif`.

## 8. 3D (proposed by the director, 2026-10-04)

Status: **PROPOSED.** The direction and its reasons are in `design/3D_DIRECTION.md` (§3-§4, §9). The 3D spike's screenshots settle the look A/B (§8.3), and the art lead then adopts or changes this section and bumps `v` on any model rows. §1-§7 keep governing every 2D asset, including the concept pictures that 3D models are made from.

What carries over unchanged: the player colours, emblems and keylines (§1.1), the terrain anchors and their lightness gate (§1.2, now measured on the rendered ground), the UI palette (§1.3), the class silhouettes (§2.3), the figure value rules (§2.5), the Ludo rules (§3), the transformation contract (§5), and Bright Cel's intent (§6): bold, clean, saturated, readable, with darkness from subject and palette.

### 8.1 readability: minimum on-screen sizes in 3D
At 1920×1080, also checked at 1600×900. The map zooms are in `3D_DIRECTION.md` §8.1.

| element | minimum | made by |
|---|---|---|
| human-sized figure on the map | 24 px tall (piece scale grows as the camera rises; below 24 px the army becomes a stand) | Ludo model + code scale |
| army stand (far zoom) | banner 32 px tall, base ring 28 px across | code |
| human-sized figure in a battle | 48 px tall up to 40 a side; 32 px at the largest (150 a side); beyond that, M3's files | the auto-framing camera |
| fortress at the strategic zoom | 48 px across | Ludo kit + code walls |
| base ring stroke | 3 px in screen space, with the §1.1 keylines | code |
| owned-province inner band | 4 px in screen space, keylined; doubled when fortified | ground shader |
| count plate | emblem 16 px, number 16 px | 2D overlay. Art never carries text, and neither does the 3D |
| selection / hover | 3 px `#FFFFFF` / 2 px `#F1ECE0` screen-space outline | code (stencil) |

### 8.2 silhouette
- **The class gate in 3D:** render the figure filled black at 24 px tall from the default map pitch (about 50°), and a reviewer must name the class. §2.3's shape rules apply as seen from that camera: infantry with weapon upright near the body, mounted longer than tall with the mount's legs visible, a commander's standard ≥ 25% of figure height above the head, a caster's bell robe and glowing focus, a flyer's wings wider than tall, and a monster ≥ 1.5 men tall.
- **The block gate:** a block of 8 of one unit at the default zoom is told apart from the faction's other blocks by shape alone, in greyscale.
- **Concept pictures:** arms a little away from the body, both hands and what they hold visible (§3 rule 6). Image-to-3D separates limbs better, and the class read survives the turn to 3D.

### 8.3 outline, and the cel-or-painted A/B
Both looks share the §6 intent and these rules: no outline on terrain or water, the outline colour is ink `#1A1612`, and selection and occlusion outlines are code (§8.1, §8.6).

| | **A: cel** | **B: painted-lit** |
|---|---|---|
| shading | toon ramp: lit, shadow (55% of lit) and highlight bands, with hard band edges; a rim band at grazing angles | wrap Lambert (wrap 0.3) over the painted albedo, with a soft rim of 0.1 |
| outline | inverted hull on every piece (figures, buildings, trees): 1.5 px at 1080p, constant in screen space | the same hull on figures, fortresses and hero buildings only |
| concept `art_style` | `Cel-Shaded` | `Hand-Painted` |

The spike renders one scene in both looks at three zooms, in colour and greyscale. Alex picks. The director's lean is B with outlines on pieces.

### 8.4 model budgets
`target_num_faces` is the value sent to Ludo `create3DModel` (minimum 1,000) and the import's LOD0. LODs are generated on import (about 25% and about 6% of LOD0); figures draw at the smallest LOD at the strategic zoom. Slimmed textures are JPEG embedded in the GLB.

| class | faces (LOD0) | texture | slimmed GLB | height (men) |
|---|---|---|---|---|
| regular figure, human-sized (and army extras) | 6,000 | 512 | ≤ 0.5 MB | 1.0 |
| large figure (mounted, beast) | 8,000 | 512 | ≤ 0.6 MB | 1.3-2.0 |
| commander | 8,000 | 1024 | ≤ 0.9 MB | 1.1 |
| ruler, human-sized | 12,000 | 1024 | ≤ 1.2 MB | 1.25 |
| ruler, monster (for example the Great Thornmane) | 15,000 | 1024 | ≤ 1.5 MB | 2.5-3.5 |
| fortress hero piece (gatehouse, keep) | 14,000 | 1024 | ≤ 1.0 MB | 6-10 |
| corner tower | 8,000 | 1024 | ≤ 0.7 MB | 5-7 |
| capital hall | 16,000 | 1024 | ≤ 1.2 MB | 6-9 |
| building (house, barracks, landmark) | 8,000-10,000 | 512 | ≤ 0.5 MB | 2-6 |
| prop (rack, post, tents) | 3,000 | 512 | ≤ 0.3 MB | 0.5-2 |
| tree, rock (instanced) | 2,000 | 512 | ≤ 0.3 MB | 2-4 |

Over budget means re-model at fewer faces (failed jobs are free; a re-roll is 3), never a hand edit.

### 8.5 materials: Ludo's PBR is always replaced
- Ludo GLBs come with PBR materials that render too shiny and differ from model to model. **Every Ludo mesh is drawn with the game's `piece` material instead** (a `material_override`, or the MultiMesh's material). It keeps only Ludo's base colour texture.
- `piece`: metallic 0, roughness 0.8, specular 0.3; the §8.3 lighting model and outline. Emission is reserved for code effects (transformation shimmer, flashes). Ludo's normal and metallic-roughness maps are dropped when the GLB is slimmed.
- **Shine gate:** under the default light, no highlight on a piece is more than 10 L\* above its lit albedo.
- **Value gate:** rendered under the default light, a figure's mean L\* is 40-65 with a light area (L\* > 70) and a dark area (L\* < 30), as §2.5. A model off by up to 15 L\* gets a per-model Lab correction (a and b kept) in its model-table row. Off by more is re-rolled.
- One material family for every piece, so models from different jobs read as one set.

### 8.6 player identity, in code only
§1.1's rule holds in 3D: **model art never carries player colour.** The faction's palette is worn in the art; the player's colour is drawn by code:
- **Base ring** under every block, stand and battle fighter: the slot colour with keylines, and the slot emblem on its front edge. It replaces §2.2's battle ground ellipse.
- **Banners:** a code cloth mesh with a ripple shader in the slot colour, with the emblem as a decal. Carried by every army's standard bearer and flown by every owned fortress, capital and village.
- **Territory wash:** §2.2's 30% multiply tint on the ground, plus the keylined inner band (§8.1).
- **Pennants** on fortress towers in the slot colour.
- **Occluded armies:** a keylined silhouette in the slot colour at 60% through terrain and buildings.
- Hue-key repainting of a model's own colour (CONCURRENT's `tin.gdshader`) is used only if the director calls for it after the spike. Six faction palettes make a keyed hue collide.

### 8.7 faction palettes in 3D
- §1.3's faction material palettes extend to every faction the lore room defines: 4 named materials per faction, worn at moderate chroma (≤ 45), so the slot colour stays the loudest, keylined colour on a piece.
- **Gate before any model is made:** all faction palettes on one sheet in colour and greyscale. Each faction differs from every other by value pattern as well as hue.
- The Crown keeps steel, white linen, royal blue and gold. The Clans keep tawny fur, bone, moss green and crimson war paint. A cross-faction anchor is always greyscale (§3 rule 3).

### 8.8 lighting, time of day and seasons
- One key sun from the upper left of the default view, at about 50° elevation, warm; a cool sky fill. Shadowed ground keeps L\* ≥ 30.
- Planning is bright midday. Turn playback uses a warm late-afternoon grade.
- Seasons swap the ground grade and tree canopies (spring green, summer gold, autumn rust, winter snow) and never touch the code colours.
- **Gate under every lighting and season preset:** the terrain anchors keep their §1.2 bands at the default zoom, and every player mark keeps ≥ 3.5:1 through its keylines on every terrain.

### 8.9 camera and readability gates (every model batch and every world PR)
1. The silhouette gate and the block gate (§8.2).
2. The owner gate: at the strategic, default and near zooms, in greyscale, every army's owner reads from its ring, emblem and banner.
3. The value and shine gates (§8.5), rendered.
4. The contrast gate under every preset (§8.8).
5. The occlusion gate: no army is fully hidden at any zoom.
6. The label gate: no label overlaps another label or a plate at the default zoom on the largest map.
7. The family gate: a unit's pose models are within ΔE 8 of the base pose on their shared materials.
8. Turntable, zoom and silhouette renders on the batch's model sheet (§7's format, one row per unit with its poses as columns), and a human look at every model. No gate replaces looking (playbook §8).

### 8.10 3D asset classes
3.5 cr a piece = a 0.5 picture + a 3.0 model. Base pictures take 3 candidates (1.5).

| class | Ludo call | image_type / view / aspect | ship | path | gates | cr |
|---|---|---|---|---|---|---|
| concept picture, figure (base pose) | createImage, n = 3, C-model block | `asset` / `High Angle` / `ar_1_1` | the pick as webp q90, ≤ 1024 px (a pipeline input, like the anchors) | `assets/_concept/<faction>/<unit>.webp` (with `.gdignore`) | class read, palette, hands and held items visible | 1.5 |
| pose picture | editImage on the base pick, C-pose template | – | as above | `assets/_concept/<faction>/<unit>_<pose>.webp` | same outfit, base and palette | 0.5 |
| figure model | create3DModel, `texture_size` 1024, `texture_type` pbr | – | slimmed GLB | `assets/models/<faction>/<unit>/<unit>_<pose>.glb` | §8.9 | 3.0 |
| structure picture | createImage, n = 3, C-structure block | `asset` / `High Angle` / `ar_1_1` or `ar_4_3` | as figure pictures | `assets/_concept/<faction>/fortress/<piece>.webp`, `assets/_concept/world/<piece>.webp` | walls meet the floor, footprint as planned | 1.5 |
| structure model | create3DModel | – | slimmed GLB | `assets/models/<faction>/fortress/<piece>.glb`, `assets/models/world/<piece>_<a\|b>.glb` | §8.4, §8.9 | 3.0 |
| wall mat | createImage, 2 takes, C-wallmat block | `texture` / `Top-Down` / `ar_1_1` | 512 seamless webp q90 | `assets/tex/walls/<faction>.webp` | seams on 3×3, the §4 lightness gate against the faction stone's target | 0.5 each |
| ground mat | createImage, 2 takes, C-terrain v2 | `texture` / `Top-Down` / `ar_1_1` | 512 seamless webp q90 | `assets/tex/ground/<terrain>.webp` | §4 lightness gate | 0.5 each |
| battle effect | §4.2, shown as a billboard | – | §4.2 | `assets/vfx/<vfx>/` | §4.2 | 5.5 |

Every model has a row in the model table (`data/models.gd`: height in men, yaw, long axis for lying or long pieces, LOD bias, collider). A test fails on any GLB without one. Candidates and raw GLBs stay gitignored (§3 rule 16). Every input goes to Ludo as base64 from a local file.

### 8.11 style blocks (drafts; the spike tunes them, then they're verbatim as in §6.1)
- **C-model:** `Concept picture of one game miniature for a 3D model, bright high fantasy: a single full figure standing on a small plain round base, chunky simplified shapes and large readable forms, a bold clear silhouette, arms held a little away from the body with both hands visible, flat saturated colours with one soft shadow tone, matte painted finish, even soft studio light from the front, three-quarter view from slightly above, the whole figure centred with wide empty margin on every side and clear headroom, plain flat light grey background.`
- **C-structure:** `Concept picture of one tabletop terrain model for a 3D model, bright high fantasy: a single building standing on its own with its walls meeting the floor, chunky simplified shapes, a bold clear silhouette, flat saturated colours with one soft shadow tone, matte painted finish, even soft studio light, three-quarter view from a little above, the whole building centred with clear space on every side, plain flat light grey background.`
- **C-pose** (an edit instruction on the base picture): `The same figure, now <one plain line of the pose>. Same outfit, same colours, same round base, same outline style, three-quarter view from slightly above.`
- **C-wallmat:** `Seamless tileable cel-shaded stone wall texture viewed straight on in bright sunlit daylight: <the faction's stone and mortar>, simple bold block shapes in two close light tones, low contrast within the texture, even flat lighting, pattern continues across all four edges.`
