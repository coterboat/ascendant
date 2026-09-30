# ASCENDANT: style bible

Status: **DRAFT. Waiting on Alex to pick a style direction.** Owner: art lead. Specs only. Asset builder generates assets from these specs; nobody else does.

Built on: the director's draft `design/GAME_BRIEF.md` (commit `e7f84ce`, "DRAFT, awaiting Alex's approval", not on `main` when this was written) and `studio/ludo-playbook.md` (30 Sep 2026). If the brief changes, this changes with it.

What the brief sets for art: an original mythic world where rival pretenders fight to ascend. **Dark but not grim, readable and characterful rather than gritty.** 2D, clean readable map, one main map screen with panels, desktop mouse and keyboard, 2–6 players, 4–6 nations, polish over breadth. Battles are resolved in rules code first, so unit art is **static** until a battle-playback milestone.

---

## 1. Palette

### 1.1 Player colours (who owns it)
Six player slots plus independents. The colour goes with the **player slot**, not the nation, so two players on the same nation still read apart. Unit art never carries player colour. Player identity is drawn in code (token ring, banner plaque, province tint).

| slot | name | hex | emblem (always drawn with the colour) |
|---|---|---|---|
| P1 | Vermilion | `#D8432C` | circle |
| P2 | Cobalt | `#2D5BD1` | square |
| P3 | Gold | `#F1C232` | triangle, point up |
| P4 | Sky | `#62C3F0` | diamond |
| P5 | Jade | `#2E9E6A` | hexagon |
| P6 | Bone | `#EFEAE0` | Greek cross |
| IND | Slate (independents) | `#5B5750` | heater shield |

How this holds up for colour-blind players (checked, Machado 2009 full-severity simulation, CIE76 ΔE between the closest pair of the 7 colours): normal 43.5, protanopia 21.1, deuteranopia 21.8, tritanopia 20.5. So every pair stays ≥ 20 ΔE in every simulation. On top of that, **colour is never the only channel**: every player mark carries its slot emblem (shape), so the game stays playable in greyscale. The known weak pairs are Vermilion/Jade (protan) and Sky/Jade (tritan). The emblem covers both.

Keylines: every player-colour mark is framed by a 1 px ink line `#1A1612` on the inside and a 1 px halo `#F4F0E8` at 70% on the outside. On every terrain anchor below, at least one of the two keylines is ≥ 3.3:1 (checked). Ink carries light terrain, halo carries dark terrain and sea.

### 1.2 Map base (terrain anchors, muted on purpose)
Terrain stays inside **L\* 30–72 and chroma ≤ 30** so player colours (chroma 45+) and icons always win. Proposed terrain set, final list waits on the director:

| terrain | hex | | terrain | hex |
|---|---|---|---|---|
| plains | `#A39C74` | | waste | `#BCA67C` |
| farmland | `#B3A56E` | | tundra | `#CDD1CB` |
| forest | `#56704A` | | sea | `#3F6070` |
| hills / highland | `#8A785C` | | deep sea | `#2C4654` |
| mountains | `#7A766F` | | parchment (off-map, fog veil) | `#E6D9BC` |
| swamp | `#5E6852` | | map ink (borders, labels) | `#2A231C` |

### 1.3 UI
| role | hex | contrast on `#1E1B18` |
|---|---|---|
| panel background | `#1E1B18` | – |
| panel raised / hover row | `#2A2622` | – |
| panel border | `#5A4E3E` | – |
| gilt accent (headings, thrones, focus frame) | `#C9A45C` | 7.3:1 |
| text primary | `#EDE6D6` | 13.8:1 |
| text secondary | `#B3A993` | 7.4:1 |
| text disabled | `#7D7465` | 3.7:1 (disabled only) |
| positive (always with `+` or ▲) | `#6FBF73` | 7.7:1 |
| negative (always with `−` or ▼) | `#E0605A` | 4.9:1 |
| warning | `#E8B04A` | 8.8:1 |
| link / codex term | `#7FB6E6` | 7.9:1 |
| selection | `#FFFFFF` outline 3 px | – |

Magic-path colours are **not set yet**: they wait on the director's list of paths. They must not reuse a player hue; they will be picked against §1.1 with the same simulation check.

## 2. Readability rules (strategy map)

Map zoom levels, measured at 1920×1080: **far** (province ≈ 80 px across), **default** (≈ 180 px), **near** (≈ 360 px). Every rule below must hold at default zoom and degrade cleanly at far zoom.

### 2.1 Minimum on-screen sizes
| element | default | minimum | made by |
|---|---|---|---|
| army token (unit sprite in a player ring) | 40 px | 28 px (below that it collapses to a 16 px emblem dot) | Ludo sprite + code ring |
| map building icon (fort, temple, lab, throne) | 36 px | 24 px | Ludo |
| province state glyph | 20 px | 16 px | **hand-written SVG** (playbook: AI can't make a consistent set that stays crisp at ≤ 40 px) |
| unit class glyph (token corner) | 14 px | 12 px | hand-written SVG |
| spell / item icon | 64 px panel, 32 px list | 32 px | Ludo |
| unit art in panels | 128 px | 96 px | Ludo |
| body text / captions / numbers | 14 / 12 / 16 px | 12 px | Godot font. Generated art never carries text |

### 2.2 Faction (player) at a glance
- Army token: sprite inside a 3 px ring in the player colour, with the §1.1 keylines, plus the slot emblem (12 px) at the top-left of the ring.
- Owned province: 30% multiply tint of the player colour over the terrain, plus a 4 px inner border in the player colour with keylines, plus the emblem on the province name plaque.
- Stacks from several players in one province sit side by side, never overlapped by more than 25%.

### 2.3 Unit class at a glance
Two channels: silhouette and a 14 px class glyph (SVG) at the bottom-right of the token.
- **Silhouette test (a gate for every unit):** fill the alpha black and scale to 32 px. A reviewer must name the class. If they can't, re-roll.
- Class silhouettes, width:height of the figure's bounding box:
  - infantry: upright, weapon held vertical and close to the body, ≈ 1:2
  - heavy infantry: large shield facing the viewer, broad stance, ≈ 1:1.6
  - ranged: bow, sling or javelin angled away from the body, with a visible gap of background between weapon and body
  - mounted: a horizontal mass with the mount's legs visible, ≈ 1.3:1
  - commander: a standard or staff rising ≥ 25% of the figure's height above the head
  - mage / priest: a robe widening toward the ground like a bell, one glowing focus at hand or head height
  - flyer: wings spread wider than the figure is tall
  - monster / sacred: non-humanoid mass filling ≥ 85% of the canvas height
- Scale by **subject height**, not canvas (playbook): on the 256×256 canvas, human 170 px, large (mounted, ogre) 210 px, huge 236 px. Feet baseline y = 236 for all.

### 2.4 Province state at a glance
Each state uses at least two channels (fill/border plus glyph/icon). All of it is drawn in code over the terrain, plus the icons listed. This is a proposed state list: the brief names forts, sieges, thrones, dominion and supply, and "contested" and "fog" are mine.

| state | encoding |
|---|---|
| owned | §2.2 tint + border + emblem |
| neutral / independent | no tint, 2 px border in map ink at 60%, slate shield emblem on plaque |
| contested (hostile army present / battle expected) | border in 12 px alternating dashes of both players' colours, plus a crossed-swords glyph (20 px) |
| fortified | fort map icon at the province centre, plus a doubled border (two 2 px lines, 2 px apart) |
| besieged | fort icon plus a ring of 8 chevrons in the besieger's colour, plus a siege glyph |
| throne (victory province) | crown map icon 36 px, name plaque in gilt `#C9A45C`, with the owner's ring once claimed |
| capital | 5-point star glyph on the name plaque |
| unscouted / stale | terrain desaturated 70%, parchment veil `#E6D9BC` at 40%, fine 45° hatching, "last seen turn N" on hover |
| selected / hover | 3 px `#FFFFFF` outline plus 15% brighten / 2 px `#EDE6D6` outline |
| dominion overlay (a separate map mode) | player-colour 45° stripes, spacing shrinking with dominion strength. Code only, no generated art |

### 2.5 Outline and contrast
- Unit sprites and map icons: a painted dark outline of even weight, **≥ 4 px at the 256 px ship size** (= 1 px at 64 px on screen). Godot adds a 1 px screen-space `#1A1612` outline in the token shader, so every size keeps a keyline.
- Sprite values: every figure has both a light area (L\* > 70) and a dark area (L\* < 30). Mean figure L\* is 40–65.
- Terrain: L\* 30–72, chroma ≤ 30, no strong baked light (flattened in post).
- Player-colour marks: keylines as in §1.1 (≥ 3:1 against every terrain via ink or halo).
- UI text ≥ 4.5:1, numbers and tooltips ≥ 7:1 against their panel.

## 3. Ludo rules this bible follows (from `studio/ludo-playbook.md`)
1. **No negative prompts.** There is no negative field. "no X" gets drawn. Every prompt here says what should be there. This includes SFX: the playbook's CS wording "no reverb, no music, no voice" is replaced with positive wording ("dry, single isolated sound, silence after"). Asset builder should refuse any prompt containing "no ", "without", "not ", "NEGATIVE".
2. **One verbatim style block per asset class**, never paraphrased per asset. To tune, change the block, re-version (`v`), and regenerate the class.
3. **Anchor to the same class** (a prop against a prop). After the pick, the chosen probe of each class becomes that class's style anchor (`generateWithStyle`, `style_image`). Units are anchored to the unit probe, map icons to the map-icon probe, spell icons to the spell probe, portraits to the first portrait, items to the first item. **Never anchor across classes** (an anchor from a background inherited its dark outlines 3/3 times).
4. **Pick from fresh candidates, don't revise.** Default `n = 3` candidates per image. Keep candidates gitignored, record the installed pick.
5. `augment_prompt: false` on everything here (control over style is the point). `image_type` always set explicitly.
6. **Leave room in the frame:** margin on every side and headroom above raised weapons, flames and staffs.
7. **Say what the hands hold** on every unit and portrait. **Name the expression and eye direction** on portraits.
8. **Transparency** comes from `removeBackground` (`crop: true`, `creative_edit: false`), never from asking for "transparent". Prompts ask for a plain flat pale grey background to make the cutout easy.
9. **True size:** static art is downscaled from Ludo's ~1024 px webp to the ship sizes in §4. Any future animation uses `frame_size: -9` from a trimmed, padded, shared canvas under 1 MP (units: 512×512, feet at y = 472). Never `crop: true`. Pin the model per set (forge for simple loops), `final_image` = first frame for loops.
10. **Text and logos are never generated.** Wordmark, labels and numbers are set in a real font.
11. **Invent every flag and heraldry.** Re-roll anything that looks like a real flag or emblem.
12. **Judge side by side** on a contact sheet, never one at a time.
13. Audio: sniff headers (ambience arrives as WAV behind `.mp3`), `duration` doesn't bind (measure it), crossfade ambience tail into head, level each class to its slot with a limiter.
14. Budget: ledger every charged call (cutouts and re-rolls included). Failed jobs are free.

Tool notes for asset builder (repo `tools/ludo/ludo.py` is copied from CONCURRENT):
- `manifest.json` has **one global** `style` string that ludo.py *appends* to every `image` prompt. Our blocks are per class, so each manifest entry should set `"style": false` and carry the full prompt from `ASSET_MANIFEST.md` (block first, then subject).
- ludo.py builds `request_id` as `concurrent-<id>-v<N>`, and request ids are sticky on the shared key. Every ASCENDANT id starts with `asc_` so it can't collide with a CONCURRENT job.
- The `styled` kind reads `style_from` as a **ledger URL, which dies after 7 days**. Anchor chains must run within 7 days of the anchor's generation, or the tool needs a local-file anchor option (base64 `style_image` is supported by the API). That's asset builder's call.
- `image` always sends `n: 1`. Three candidates means three entries or takes. Asset builder chooses how.

## 4. Asset classes (same for every direction)

Every class uses `augment_prompt: false`. The `art_style` and style block come from the chosen direction (§5). Credits are for 3 candidates plus any cutout on the pick.

| class | Ludo call | image_type / perspective / aspect | ship size, frames | format | Godot path | cr / asset |
|---|---|---|---|---|---|---|
| unit sprite | createImage → removeBackground (pick) | `sprite` / `High Angle` / `ar_1_1` | 256×256, 1 frame (static). Feet y = 236, subject height per §2.3 | webp lossless, alpha | `assets/units/<nation>/<unit_id>.webp` | 2.0 |
| province / terrain tile | createImage | `texture` / `Top-Down` / `ar_1_1` | 512×512 seamless, 1 frame. Flatten lighting (blur subtract on a 3×3 tiling). Water motion by shader | webp q90 | `assets/terrain/<terrain_id>.webp` | 1.5 |
| map icon | createImage → removeBackground (pick) | `icon` / `High Angle` / `ar_1_1` | 128×128, subject within the centre 112×112 | webp lossless, alpha | `assets/map_icons/<icon_id>.webp` | 2.0 |
| spell icon | createImage | `item-icon` / `Any perspective` / `ar_1_1` | 128×128 full bleed, opaque. UI draws the frame and path rim in code | webp q92 | `assets/icons/spells/<spell_id>.webp` | 1.5 |
| item icon | createImage → removeBackground (pick) | `item-icon` / `Any perspective` / `ar_1_1` | 128×128, subject within the centre 112×112 | webp lossless, alpha | `assets/icons/items/<item_id>.webp` | 2.0 |
| UI chrome | createImage (→ removeBackground if the edge is irregular) | `ui_asset` / `Any perspective` / `ar_1_1` (panels), `ar_4_3` (buttons, cropped) | panel 256×256 nine-slice, patch margins 64; button 256×64 three-slice, margins 24 | webp lossless | `assets/ui/<element_id>.webp` | 1.5–2.0 |
| portrait | createImage (first), then generateWithStyle from the first | `portrait` / `Any perspective` / `ar_3_4` | 384×512, eyes at 38% from the top | webp q90 | `assets/portraits/<portrait_id>.webp` | 1.5 |
| sfx | `/audio/sound-effect`, 2 takes | – | trimmed to onset, UI ≤ 0.6 s, world ≤ 2.5 s, 20 ms fade-out, peak −1 dBFS | 16-bit PCM WAV, 44.1 kHz mono | `assets/audio/sfx/<sfx_id>.wav` | 4.0 |
| ambience | `/audio/ambiance` (10 s cap) | – | 8–10 s loop, 0.5 s tail-to-head crossfade, −22 LUFS | MP3 192 kbps stereo, loop on | `assets/audio/ambience/<amb_id>.mp3` | 2.0 |
| music | `/audio/music`, ask 60 or 120 s (you get ~48–56 for 60) | – | full track, −18 LUFS integrated, −1 dBTP limiter | MP3 192 kbps stereo, loop on | `assets/audio/music/<track_id>.mp3` | 3.0 |

Province state glyphs, class glyphs and slot emblems are **hand-written SVG** at `assets/ui/glyphs/<glyph_id>.svg` (24×24 viewBox, 2 px strokes, fill `#EDE6D6`, stroke `#1A1612`). They are not Ludo work.

## 5. Candidate style directions (pick one)

Each direction lists its `art_style` and the literal block for each class. The block goes **first** in the prompt, verbatim, followed by ` Subject: <subject>.`

### Direction A: **Gilded Atlas** (`art_style: Inked Painterly`)
The map is an illuminated atlas come to life. Sepia-black ink linework, muted watercolour washes on warm parchment, restrained gilt on sacred and royal things. Units read as painted manuscript miniatures standing on the map. Mood: mythic, scholarly, a little eerie. This one fits "dark but not grim" and the codex-heavy, everything-explained brief best. The risk is fine detail getting mushy at 32 px, which the thick-outline rule offsets.

- **A-unit:** `Inked painterly game sprite in the manner of an illuminated manuscript miniature. Confident sepia-black ink outline of even, heavy weight around the whole figure, soft watercolour washes in muted earth tones with one restrained accent colour, touches of gold leaf on metal, gentle light from the upper left. Full figure seen from a high three-quarter angle, feet at the bottom of the figure, single subject centred with wide empty margin on every side and clear headroom above the tallest point, plain flat pale grey background.`
- **A-terrain:** `Seamless tileable top-down map texture in the manner of a hand-painted antique atlas. Loose watercolour washes and fine sepia ink hatching over warm parchment grain, muted low-contrast mid-tones, even flat lighting, uniform density from edge to edge, pattern continues across all four edges.`
- **A-mapicon:** `Inked painterly map icon in the manner of an illuminated atlas. One bold simple silhouette readable at 32 pixels, heavy even sepia-black ink outline, flat watercolour fill in muted earth tones with a gold-leaf accent, seen from a high three-quarter angle, single object centred with wide empty margin, plain flat pale grey background.`
- **A-spell:** `Inked painterly spell icon in the manner of an illuminated manuscript initial. Square composition filling the whole frame edge to edge, one central symbol with a strong silhouette readable at 32 pixels, bright glowing symbol against a darker watercolour-washed background, heavy sepia ink outline around the symbol, gold-leaf highlights, wordless pure pictorial image.`
- **A-item:** `Inked painterly item icon in the manner of an illuminated manuscript miniature. One object shown whole at a slight three-quarter angle, heavy even sepia-black ink outline, watercolour washes in muted earth tones with a gold-leaf accent, strong silhouette readable at 32 pixels, single object centred with wide empty margin, plain flat pale grey background.`
- **A-ui:** `Game interface element in the manner of a gilded manuscript binding. Dark warm brown leather panel with a thin gilt tooled border and small ornamented gilt corners, fine sepia ink detail, flat even lighting, symmetrical, plain dark empty centre, clean straight edges, viewed straight on.`
- **A-portrait:** `Inked painterly portrait in the manner of an illuminated manuscript. Head and shoulders, three-quarter view facing left, face in the upper half of the frame, confident sepia ink linework, muted watercolour washes, gold-leaf halo accents, soft light from the upper left, plain dark warm parchment-brown background.`
- **A-sfx:** `Tactile acoustic foley of natural materials: parchment, wood, bronze, cloth, stone. Close-mic, dry, single short isolated sound, clean sharp onset, quick decay into silence.`
- **A-ambience:** `Quiet continuous outdoor bed for a strategy map: soft steady wind over open country, faint distant birds, a low calm drone, even level from start to end, seamless loop.`
- **A-music:** `Mythic chamber folk score: solo oud and lute melody, bowed lyra, soft cello drone, low frame drum, Dorian mode, mysterious and warm, steady tempo around 84 bpm, instrumental.`

### Direction B: **Painted Tabletop** (`art_style: Hand-Painted`)
The world is a lovingly painted board game. Units look like hand-painted resin miniatures with chunky, readable proportions (about 5 heads tall) and soft studio light. Terrain looks like a painted diorama board. Rich but controlled colour. Mood: inviting, tactile, "one more turn". This one fits approachability best and gives the strongest silhouettes and volumes at small sizes. The risk is reading as cosy rather than mythic.

- **B-unit:** `Hand-painted game sprite of a painted tabletop miniature. Chunky readable proportions about five heads tall, crisp dark outline of even heavy weight, smooth painted volumes with clear highlights and shadows, rich controlled colours, soft studio light from the upper left. Full figure seen from a high three-quarter angle, feet at the bottom of the figure, single subject centred with wide empty margin on every side and clear headroom above the tallest point, plain flat pale grey background.`
- **B-terrain:** `Seamless tileable top-down map texture in the manner of a hand-painted tabletop diorama board. Soft painted brushwork, gentle colour variation, muted low-contrast mid-tones, even flat lighting, uniform density from edge to edge, pattern continues across all four edges.`
- **B-mapicon:** `Hand-painted map icon of a painted tabletop game piece. One bold simple silhouette readable at 32 pixels, crisp dark outline of even heavy weight, smooth painted volumes, rich controlled colours, soft light from the upper left, seen from a high three-quarter angle, single object centred with wide empty margin, plain flat pale grey background.`
- **B-spell:** `Hand-painted spell icon for a tabletop strategy game. Square composition filling the whole frame edge to edge, one central symbol with a strong silhouette readable at 32 pixels, bright glowing symbol against a darker painted background, crisp dark outline around the symbol, smooth painted volumes, wordless pure pictorial image.`
- **B-item:** `Hand-painted item icon for a tabletop strategy game. One object shown whole at a slight three-quarter angle, crisp dark outline of even heavy weight, smooth painted volumes with clear highlights, rich controlled colours, strong silhouette readable at 32 pixels, single object centred with wide empty margin, plain flat pale grey background.`
- **B-ui:** `Game interface element in the manner of a premium board game component. Dark stained wood panel with a bevelled brass-trimmed border and small rounded brass corner caps, smooth painted finish, flat even lighting, symmetrical, plain dark empty centre, clean straight edges, viewed straight on.`
- **B-portrait:** `Hand-painted portrait for a tabletop strategy game. Head and shoulders, three-quarter view facing left, face in the upper half of the frame, smooth painted volumes, rich controlled colours, soft studio light from the upper left, plain dark muted background.`
- **B-sfx:** `Warm tactile foley of game pieces: wooden tokens, cards, brass, cloth, leather. Close-mic, dry, single short isolated sound, clean sharp onset, quick decay into silence.`
- **B-ambience:** `Warm calm bed for a strategy map: gentle breeze over fields, soft rustling grass, faint far-off birds, even level from start to end, seamless loop.`
- **B-music:** `Warm cinematic strategy-game score: French horn melody over pizzicato strings, harp arpeggios, light timpani, adventurous and inviting, tempo around 96 bpm, instrumental.`

### Direction C: **Woodcut Myth** (`art_style: Block Print`)
Myth told as carved prints. Bold flat shapes, 3–4 flat colours per asset plus ink black, visible carving marks and paper grain. Figures are stylised, almost glyph-like. Mood: ancient, ritual, strange. This one reads best at 32 px and makes the most consistent sets. The risk is less "character" in portraits and a flatter, colder map.

- **C-unit:** `Block print game sprite in the manner of a bold carved woodcut. Thick black carved outline and interior carving marks, three or four flat colours in muted earth tones with one strong accent, stylised simplified anatomy, strong graphic silhouette. Full figure seen from a high three-quarter angle, feet at the bottom of the figure, single subject centred with wide empty margin on every side and clear headroom above the tallest point, plain flat pale grey background.`
- **C-terrain:** `Seamless tileable top-down map texture in the manner of a carved woodcut print. Rhythmic carved line patterns in two close muted tones over soft paper grain, low contrast, even flat lighting, uniform density from edge to edge, pattern continues across all four edges.`
- **C-mapicon:** `Block print map icon in the manner of a bold carved woodcut. One bold simple silhouette readable at 32 pixels, thick black carved outline, two or three flat muted colours with one strong accent, seen from a high three-quarter angle, single object centred with wide empty margin, plain flat pale grey background.`
- **C-spell:** `Block print spell icon in the manner of a bold carved woodcut. Square composition filling the whole frame edge to edge, one central symbol with a strong silhouette readable at 32 pixels, bright flat symbol against a dark flat background, thick black carved lines, three or four flat colours, wordless pure pictorial image.`
- **C-item:** `Block print item icon in the manner of a bold carved woodcut. One object shown whole at a slight three-quarter angle, thick black carved outline, two or three flat muted colours with one strong accent, strong silhouette readable at 32 pixels, single object centred with wide empty margin, plain flat pale grey background.`
- **C-ui:** `Game interface element in the manner of a carved woodcut print. Dark charcoal panel with a thick carved border of simple repeating geometric notches and square carved corner blocks, two flat muted tones, flat even lighting, symmetrical, plain dark empty centre, clean straight edges, viewed straight on.`
- **C-portrait:** `Block print portrait in the manner of a bold carved woodcut. Head and shoulders, three-quarter view facing left, face in the upper half of the frame, thick black carved lines, three or four flat muted colours with one strong accent, stylised features, plain flat dark background.`
- **C-sfx:** `Raw archaic foley: struck wood, stone, bone, bronze, hide drum. Close-mic, dry, single short isolated sound, clean sharp onset, quick decay into silence.`
- **C-ambience:** `Sparse ancient bed for a strategy map: low steady wind across bare hills, a faint deep drone, occasional distant crow, even level from start to end, seamless loop.`
- **C-music:** `Ancient ritual score: deep frame drums and log drums, bone flute melody, bronze horn calls over a low drone, sparse and primal, tempo around 72 bpm, instrumental.`

## 6. Style probe (for Alex's pick)

Same five visual subjects in each direction, plus one music cue each. All rows are in `ASSET_MANIFEST.md` with full prompts (status `spec`).

| subject | Probe (A / B / C) | why |
|---|---|---|
| spear infantry unit | `asc_probe_{atlas,tabletop,woodcut}_unit` | silhouette and class read at 40 px on the map |
| forest terrain tile | `asc_probe_*_terrain` | map base, contrast under player tint |
| fort map icon | `asc_probe_*_mapicon` | the fortified state read at 24–36 px |
| fireball spell icon | `asc_probe_*_spell` | icon clarity at 32 px |
| UI panel frame | `asc_probe_*_panel` | chrome mood, nine-slice fit |
| main map theme | `asc_probe_*_music` | audio direction |

Cost (playbook and swagger prices: image 0.5 per result, removeBackground 0.5, music 3 per call):

| item | math | credits |
|---|---|---|
| visual probes | 5 subjects × 3 directions × 3 candidates × 0.5 | 22.5 |
| cutouts on the pick (unit + map icon) | 2 × 3 directions × 0.5 | 3.0 |
| music | 3 × 3.0 | 9.0 |
| **planned total** | | **34.5** |
| re-roll reserve (up to 11 more image results) | | 5.5 |
| **cap** | | **40.0** |

Check the balance with `--account` (free) before the run and report the spend. Failed jobs are free.

Delivery (asset builder): one PR, `assets: style probe`, with outputs at `assets/_probe/<direction>/<probe_id>.webp|.mp3` and a contact sheet `assets/_probe/contact_sheet.webp`. The sheet has 3 rows (A, B, C) and 5 columns (unit, terrain, map icon, spell, panel). Each cell shows the pick at ship size, at on-screen size (unit 40 px in a Vermilion ring on the forest tile, map icon 32 px, spell 32 px), and the 2 other candidates small. Add one 180 px mock province strip per direction: forest tile, 30% Cobalt tint, 4 px border, fort icon and unit token. That PR is for review only. After Alex picks, the winning probes move to `assets/_anchors/<class>.webp` as the style anchors and the others are dropped.

## 7. After the pick
Keep one direction in §5, delete the other two, set status to **ACTIVE**, and re-version every manifest prompt to the literal block of the chosen direction.
