# ASCENDANT: 3D direction

Status: **The 3D call is Alex's (2026-10-04). Everything in this document is PROPOSED by the director (Claude session, 2026-10-04) and needs Alex's OK.** The 3D spike now running in parallel and the lore writers' room (6 factions) feed into it. Where the spike's screenshots or measurements decide something, this document says so.

Built on: `design/GAME_BRIEF.md`, `design/MILESTONES.md`, `design/STYLE_BIBLE.md`, `design/M2_RULER.md`, `design/M3_BATTLES.md`, `design/M4_ASCENSION.md`, `design/ASSET_MANIFEST.md` and `studio/ludo-playbook.md`. Lessons (not a template) come from Alex's CONCURRENT v2.0 and v2.0.1: `tools/spike/README.md`, `docs/CHANGELOG.md`, `docs/ASSETS.md` ("3D models"), `docs/LUDO_CAPABILITIES.md`, `game/world3d/*.gd`, `tools/ludo/v20_content.py`, and the play critic's review of e5764ba.

**Alex: read §14 (director's calls) first.**

## Alex's call
> "we're going 3d because fuck it look how good our concurrent game is going. we need a world where we see armies mustering on the map in a fortress ready to spill out for war. we're not settling here"

> "that game is obviously not done, we are not married to the exact engine, it is far more simplistic than what we would be creating. scope expansion is obviously required"

> "not saying there's no benefit in 2d art: it can be perfect for concept art and lore/portraits/etc"

## the short version
- **The vision:** the map is a living 3D board. Fortresses fill with recruits who form up in their yards. Each turn, the columns march out along the roads, clash at borders, lay siege to walls, and fight their battles on the province's own ground.
- **The rules don't change.** Rules, AI, saves and tests stay pure GDScript with no renderer dependency. The 3D world reads the game state and the resolver's events and never writes to them. That is M3's "playback never changes the outcome", applied to the whole world view (§2).
- **Tech:** stay on Godot 4.5 (pinned at 4.5.1). Switch to **Forward+**. The 3D world draws in one SubViewport under the existing 2D UI. A 6-rung quality ladder steps down on its own on a slow machine. Minimum: a 2020+ integrated GPU (Iris Xe, Radeon Vega 7, Apple M1) at reduced quality, 30 fps. Full quality: a mid-range discrete GPU (GTX 1660 or RTX 2060 class), 60 fps (§3).
- **The look:** stylized 3D that keeps Bright Cel's values. Cel ramp with outlines against a painted-lit look is an A/B that the spike's screenshots decide. Either look must pass four rules: player identity drawn in code (banners, base rings, territory wash), silhouettes that read from the strategy camera, a palette per faction, and lighting and seasons that never cost readability (§4).
- **The 3D army is the marker.** No 2D token covers the land. A unit type shows as a block of its own figures, so the army's make-up reads at a glance. A small 2D plate carries the exact count (§6).
- **Fortresses are kits:** Ludo hero pieces (gatehouse, towers, keep) around a code-built, open **muster yard**. Recruits appear in the yard and fall in by type. A big muster spills out into a camp outside the walls (§5.3, §6.3).
- **Battles:** M3's event log (#56), timeline, captions, controls, why panel and approachability all carry over unchanged. The 2D field becomes a 3D stage on the province itself, with an auto-framing camera. M3-3, M3-6, M3-7, M3-8 and M3-9 are re-scoped (§7.6).
- **The asset pipeline:** 2D concept picture → Ludo `create3DModel` → slim → import → our material in place of Ludo's PBR → scale normalisation → review. Poses are edits of one base picture. Motion is pose swap plus procedural movement, and rigging is one experiment (§9).
- **Art budget:** about **200 Ludo credits per faction planned (about 300 with the re-roll reserve)**. With 6 factions, the shared world and the spikes, that is about **1,465 planned and 2,170 with reserve**. A 3D unit (4 poses at 3.5) costs 14 credits, against 23 for a 5-state sprite figure (§9.5).
- **Scope expansion, six proposals:** forts and sieges as real gameplay, fog of war, bigger maps with more players, seasons (only with a rule you can plan around), building and upgrading fortresses, and independents garrisoning the world (§10).
- **Milestones:** M3a.1 the world → M3a.2 the armies and turn playback → M3b battles on the land → forts and sieges → M4's art in 3D → M5 magic and fog → M6 six factions and bigger maps. Each step ends in something Alex can play (§11).

---

## 1. the vision

You open your capital and the camera comes down over its walls. The yard is full: last turn's spearmen stand in blocks under your banner, this turn's recruits file out of the barracks to join them, and the tents outside the gate show that the muster has outgrown the fortress. Across the map, through a gap in the fog your scouts opened, an enemy keep is filling up too. You give your orders on the same board, and they show on the land: a route ribbon along the road and ghost recruits in the yard. Then everyone commits, and the turn plays out on the land. Columns leave by the gate, march down the roads, and meet at a bridge on the border. A siege camp rings a rival's walls. Captured provinces take your colour as your banner goes up over them. Every battle can be watched where it was fought, on that province's hills, woods and walls, and it plays exactly what the rules decided. The world is a living board, and every piece on it is a piece of information.

The fog and the siege camp in this picture are proposals (§10.1, §10.2). Everything else works under today's rules.

## 2. what changes and what doesn't

**Unchanged:**
- All rules, the turn resolver, the AI, saves and the game record, determinism from the seed, and every existing test.
- The approachability rules: tooltips with breakdowns, forecasts, previews, the codex, and plain-language reports.
- The 2D UI: panels, HUD, turn report, battle report viewer, build screen, research panel and codex. It stays on top of the world.
- M3's battle event log and its pure helpers.
- Bright Cel as the language of all 2D art.

**Changed:**
- The renderer: Forward+.
- The map screen: a 3D world under the UI.
- Battle playback: a 3D stage.
- The art pipeline: `create3DModel` joins it.
- The art budget, the milestone plan, and five scope proposals.

**The one invariant.** Presentation is a pure function of the game state, the resolver's events and a clock. Code under `ui/world3d/` and `world/` never calls `TurnResolver`, `AutoBattleResolver` or any `GameSession` method that changes state, and never creates a `SeededRNG` or `RandomNumberGenerator`. Cosmetic variety (idle phase, which village variant, tree placement) comes from a hash of ids and the map seed. Three levels of tests, as in M3 §2.1:
- **rules:** unchanged. The resolver doesn't know the world exists.
- **world:** `GameState.to_dict()`, the turn report and `GameSession.record()` are deep-equal before and after building the world, playing a turn's playback and watching a battle.
- **static:** no RNG or resolver calls in `ui/world3d/` or `world/`.

---

## 3. tech

### 3.1 engine: stay on Godot (4.5, pinned at 4.5.1)
Alex isn't married to the engine, so this was a real question. We stay on Godot because:
- **Everything we have is Godot.** The rules, AI, saves and over 400 test functions in `tests/` are pure GDScript, run headless on the build box by `tests/runner.gd` and `tools/compile_check.gd`. Another engine means rewriting all of it, and the deterministic resolver is the hardest part of the game.
- **CONCURRENT proved this exact look in Godot 4.5.1 on Alex's Mac:** a generated heightfield, Ludo models, a SubViewport under a 2D UI, and 74-89 fps with a quality ladder. What we're building is more ambitious, but the risks are content and readability, not engine capability.
- **Godot 4.5 brings what we need:** Forward+ on Vulkan, D3D12 and Metal; MultiMesh instancing; mesh LODs generated on import; visibility ranges (HLOD); FSR scaling; the stencil buffer (useful for showing units hidden behind hills); and the shader baker (pre-compiled shaders, so no stutter the first time an effect plays).
- **The alternatives cost more than they give.** Unreal would bring rendering headroom we don't need for a stylized board, plus C++/Blueprint, a heavy build box and a rewrite. Unity would bring a rewrite and licence risk.

**Version:** pin 4.5.1, the version on Alex's Mac and in CONCURRENT. Re-evaluate 4.6 only at a milestone boundary, and only if it brings something on this list. Never upgrade mid-milestone.

### 3.2 renderer: Forward+
- `project.godot`: `renderer/rendering_method="forward_plus"`, replacing `gl_compatibility`. Keep `rendering/rendering_device/fallback_to_opengl3` on, so a machine without Vulkan, D3D12 or Metal still starts under Compatibility. That is the ladder's bottom rung (§3.4), and CONCURRENT showed its land draws there.
- **M3 §8.1's target (Intel UHD 620, GL Compatibility) is dropped.** It was the director's assumption, not Alex's.
- Headless tests don't render, so the switch doesn't touch them. Visual probes (screenshots, perf) run on Alex's Mac, or on the Linux build box under software Vulkan for screenshots only.
- **Probes cap at 60 fps.** CONCURRENT's lesson: Forward+ on Metal runs at the display's rate (120 Hz on ProMotion), and frame-counting probes failed until capped.

### 3.3 architecture: one world, in a SubViewport, under the 2D UI
```
GameScreen (Control, the 2D UI: HUD, panels, tooltips, reports, codex, battle controls)
 ├─ WorldView (SubViewportContainer, full rect, drawn first, under everything)
 │    └─ SubViewport (own_world_3d, physical resolution × render scale)
 │         └─ World3D: terrain, water, sky and sun, borders and wash, roads, sites, villages,
 │                     fortresses, armies, the battle stage, effects
 └─ WorldOverlay (Control): names, count plates, floating numbers, hp bars and glyphs,
                            projected from 3D every frame and drawn in 2D at native resolution
```
- **One world per game.** It is built in a background thread when the map loads (`WorkerThreadPool`, as CONCURRENT's `land.gd`). Both the board and the battles look at it through one camera: a battle is the camera diving onto a province, not a separate scene.
- **The world plan is pure** (`world/`, no nodes). From the map data and its seed, `WorldPlan.build(map, seed)` returns heights, province shapes, border lines, road paths, river courses, the fortress yard and its muster slots, village and landmark spots, and the battle stage of every province. It is deterministic, headless and tested: every touching pair of provinces has its crossing and its road, every fort province has a yard that fits its muster slots, and nothing stands in water or inside a wall. CONCURRENT's equivalent took 6-26 ms a map.
- **The view is nodes** (`ui/world3d/`): terrain chunks, MultiMesh figures, the pieces, and shaders. They read the plan, the state and events, and never write.
- **Text is never in 3D.** Names, plates, numbers and glyphs are 2D Controls projected from world points, at native resolution, so they stay crisp at any render scale. A declutter pass keeps them off each other (CONCURRENT v2.0.1's crowding fixes: crowns, bonuses and tips that hid names).
- **Picking:** a ray from the camera hits the ground, and the province-id texture under the hit gives the province. Pieces have simple colliders, so a click on an army or fortress picks it even where a hill stands in front of its ground. Probe, as CONCURRENT's `v20b`: a click on every province and every army returns its own id, at every zoom (0 wrong).
- **The existing 2D map screen stays as a setting** ("Map: 3D / 2D") until M3a.1 is accepted, then it retires. The strategic top-down zoom replaces it (§8.1).

### 3.4 the quality ladder
The world drops a rung on its own when it runs under 40 fps for 3 seconds, as CONCURRENT's `land.gd` does. It never climbs back by itself. Settings → Graphics: Auto (default), or a fixed rung. The UI is outside the SubViewport and always renders at native resolution.

| rung | name | what it gives up (on top of everything the rungs above gave up) |
|---|---|---|
| 0 | Full | nothing: 4 shadow splits, SSAO, MSAA 2× + FXAA, full figure density, water reflections of the sky |
| 1 | High | 2 shadow splits, no SSAO |
| 2 | Medium | woods and props cast no shadows, MSAA off (FXAA stays), weather particles halved |
| 3 | Low | no real-time shadows: blob shadows under figures and pieces keep them grounded; no weather particles |
| 4 | Minimum | render scale 0.75 (FSR 1), map figure density halved (blocks keep at least one figure per unit type, §6.1), far villages as simple shapes |
| 5 | Compatibility | the automatic fallback renderer: rung 4 with simple water and no FSR. Readable and playable, not pretty |

Never on any rung: SDFGI, SSR, volumetric fog or SSIL. The stylized look doesn't need them, and they cost the most.

### 3.5 target hardware and performance budgets
| tier | hardware | target |
|---|---|---|
| **minimum** | a 2020+ integrated GPU: Intel Iris Xe (11th gen), AMD Radeon Vega 7 / 680M class, Apple M1; 8 GB RAM; Vulkan 1.2, D3D12 or Metal | 1920×1080 at rung 3-4, **30 fps p95** on the map and in battles |
| **recommended (full)** | a mid-range discrete GPU: GTX 1660, RTX 2060, RX 5600 XT or better; Apple M1 Pro / M2 or better; 16 GB RAM | 1920×1080 at rung 0, **60 fps p95**; 2560×1440 at rung 0-1 on an RTX 3060 class card |
| **reference** | Alex's Mac (CONCURRENT's numbers: 74-89 fps for its land at 1440×900 @2×) | every perf PR reports its numbers here |

The studio has no minimum-spec machine. Call 3 (§14) asks for an Iris Xe laptop.

| what | budget |
|---|---|
| frame time, map and battle | p95 ≤ 16.7 ms on recommended at rung 0; p95 ≤ 33.3 ms on minimum at its Auto rung; no frame above 50 ms outside loading |
| draw calls (`RENDER_TOTAL_DRAW_CALLS_IN_FRAME`) | ≤ 1,500 on the map, ≤ 2,000 in a battle (MultiMesh per pose and LOD, one material family) |
| triangles on screen | ≤ 1.5 M at rung 0, ≤ 600 k at rung 4 (mesh LODs do most of the work, §9.5) |
| figures on screen | up to 600 on the map, up to 300 in a battle (M3's biggest battle has 277 fighters, each its own figure) |
| VRAM | ≤ 1.5 GB on minimum (shared memory), ≤ 3 GB at rung 0 |
| world build | ≤ 3 s for the largest map on minimum, in the background; the first turn's board ≤ 5 s after New game |
| battle dive | Watch to first framed frame ≤ 1.0 s |
| playback CPU per frame (headless, fixed 1/60 s steps) | ≤ 2.0 ms average, ≤ 4.0 ms max on the build box, as M3 §8.2 |

---

## 4. the look

### 4.1 stylized 3D that keeps Bright Cel
Bright Cel's values carry over to 3D: bold readable shapes, saturated colour, darkness from subject and palette rather than murk, the player colours with their emblems and keylines, and the terrain anchors and their lightness limits (bible §1-§2). How the 3D surfaces are lit is an A/B:

| | **A: cel** | **B: painted-lit** |
|---|---|---|
| shading | a toon ramp: 2-3 hard bands per light, a rim band | soft Lambert over the painted texture, a gentle rim light |
| outline | inverted hull on pieces, 1.5-2 px at 1080p, ink `#1A1612`; none on terrain | none on terrain; the same outline on units and hero buildings only |
| risk | Ludo's textures have painted light in them, so a hard ramp can shade twice | can drift toward "realistic" and lose the cel read |

**How it is decided:** the spike renders the same scene (a capital with a muster, a village, a border clash, a forest battle) at the strategic, default and close zooms, in both looks and in greyscale. Alex picks from the screenshots against the §4.2 rules and the cost on rung 3. **The director's lean is B with outlines on pieces** (units, fortresses, hero buildings), because Ludo's painted textures already carry shading. The screenshots decide.

### 4.2 the rules any look must meet
1. **Player identity is drawn in code, never in art.** Bible §1.1 holds in 3D: unit, building and banner art never carries player colour.
   - **Base rings:** a keylined ring in the slot colour under every army block and stand, with the slot emblem on the ring's front.
   - **Banners:** a code cloth mesh with a ripple shader, in the slot colour, with the emblem as a decal. Each army carries one, and every owned fortress and capital flies them.
   - **Territory wash:** the ground under an owned province takes the bible's 30% multiply tint, plus a keylined inner border band of constant screen width.
   - Repainting a coat by hue key (CONCURRENT's `tin.gdshader`) is only a fallback, if the spike shows the first three aren't enough at the strategic zoom. With 6 faction palettes, a keyed hue would collide with some faction's own colours.
2. **Silhouettes read from the strategy camera.** The bible §2.3 class gate in 3D: render each figure filled black at its smallest map size (24 px tall), and a reviewer must name the class. A block's shape reads too: spears upright, horses longer than tall, wings wider than tall.
3. **A palette per faction.** Every faction gets a material palette: 4 named materials, like the Crown's steel, white linen, royal blue and gold. Palettes are worn at moderate chroma. Player colour is the only high-chroma, keylined colour on a piece. Gates:
   - the 6 palettes side by side, also in greyscale, where each faction differs by value pattern, not just hue
   - no faction's dominant material within ΔE 15 of the player slot colour it is most likely to play (checked against all 6 slots, with the emblem as the backstop)
4. **Lighting, time of day and seasons never cost readability.**
   - One key sun from the upper left of the default camera view (the bible's "bright even light from the upper left"), at about 50° elevation, with a cool sky fill.
   - Shadowed ground keeps L\* ≥ 30.
   - Time of day: bright midday while planning, and a warm late-afternoon grade during the turn's playback, which also tells you that you're watching, not ordering.
   - Seasons: a grade plus ground and tree swaps (spring green, summer gold, autumn rust, winter snow).
   - Gate: under every lighting and season preset, the terrain anchors keep their bible L\* bands at the default zoom, and every player colour keeps ≥ 3.5:1 against the ground through its keylines (bible §1.1). Night is never darker than that.

### 4.3 what 2D art still does
Alex's point stands: 2D is the right tool for a lot of the game. It makes:
- **Concept art:** the input pictures for every 3D model (§9.1). These follow the bible's Bright Cel blocks, so the 3D inherits the look.
- Portraits, lore art, codex illustrations, loading screens and the victory screen.
- UI chrome, spell and item icons, faction banners in panels, and the SVG glyphs and emblems.
- Battle effects as billboards: M3's 7 effect sheets work as camera-facing sprites in 3D.

---

## 5. the world map

### 5.1 terrain generation
- **A map is still data.** Provinces keep their id, terrain, income, neighbours, fort and capital. Each map adds one authored **province image**: a flat-coloured region map, one colour per province, plus sea. M1's map gets one painted to match its current layout. Later, generated maps make their own (§5.6).
- **The heightfield is baked from data images,** CONCURRENT's way. The generator turns the province image into distance fields (to the coast, to each border). It raises ground by terrain type:
  - plains: gentle swells
  - hills: rolling ridges
  - forest: low rolls
  - mountains: ridged ranges with foothills
  It cuts river valleys along chosen borders, beaches and cliffs at the coasts, a level **stage** at each province's heart (where battles happen and armies stand) and a level **yard** where a fort stands. It then bakes:
  - `height` (RF)
  - `ground` (RGBA terrain weights)
  - `province` (the id per texel)
  - `owner`: one texel per province, rewritten each turn for the territory wash
- **Deterministic and seeded by the map id,** so a map always has the same land. Shipped maps bake at build time into `assets/maps/<map>/`. Generated maps build in the background at load (CONCURRENT: 0.5-2 s).
- **Ground:** the bible's terrain anchors are the base colour, so the §1.2 lightness gates hold on the rendered ground at the default zoom. Ludo seamless textures add grain as a ratio over that colour, from a `Texture2DArray`, as in CONCURRENT.
- **Forests are trees, not textures:** instanced stylized trees with bold rounded canopies (the bible's forest read), dense in forest provinces and scattered elsewhere, kept off roads, stages and yards.
- **The land must show the rules.** The critic warned that 3D land that does nothing is a backdrop. Ascendant's terrain already matters (forest +2 defense to the defender; hills +1 defense and +1 attack), so a forest province must read as woods and a hill province as high ground at the default zoom. Hovering the ground gives the same terrain tooltip as the 2D map today.

### 5.2 provinces, borders, roads, rivers, coasts and seas
- **Borders:** drawn in the ground shader from the border field, at a constant screen width at every zoom: a thin map-ink line between provinces, the owner's keylined inner band, and the bible's doubled border for a fortified province.
- **Territory wash:** the bible's 30% multiply in the owner's colour. Capture plays as the wash flowing out from the stage over the province (§6.4).
- **Roads:** from each province's heart over the middle of every border it shares, with a pass through the hills (CONCURRENT). Roads are the marching paths. A King's Roads or Forest Stride double move marches along two road segments. Roads have no rule of their own yet; seasons could give them one (§10.4).
- **Rivers:** along authored borders between lowland provinces, with a bridge wherever a road crosses. They're scenery until a rule uses them (§10.4).
- **Coasts and seas:** beaches, and cliffs where hills meet the sea. Water is coloured by depth (the bible's sea `#2F7A93` and deep sea `#244E6E`), with surf at the shore. Seas are impassable until naval rules exist.
- **The stage:** the level heart of each province. Armies stand on it, battles are fought on it (§7.2), and its centre is the province's anchor for names and plates.

### 5.3 fortresses and capitals as hero models
The fortress is the most-seen object in the game, and the place where Alex's "armies mustering in a fortress ready to spill out for war" happens. It must have a real, open yard, and a single Ludo model can't promise one (a Ludo GLB is one fused mesh, with no open courtyard guaranteed). So **a fortress is a kit:**
- **Ludo hero pieces at the joints:** a gatehouse, corner towers and a keep (and in a capital, the hall or palace). Towers hide the joints.
- **Code-built walls between them:** an extruded crenellated wall along the plan's outline, textured with the faction's seamless stone mat.
- **A code-built yard floor** of a fixed size, sized to its muster slots (§6.3), with the gate facing the road toward the nearest border.
- **Per faction:** each of the 6 factions has its own kit (Crown: white stone and blue slate; Clans: timber palisade, bone and earthworks; the lore room sets the other four). Capitals use their owner's kit plus the hall, with a town of the faction's houses around the walls.
- **Forts that aren't capitals:** M1's Stonegate and Blackwood. They start in the independents' kit (slate grey, heater-shield pennants). A captured fort keeps its look, because someone built it, and flies its new owner's banners. With fortress building (§10.5), a fort you build uses your kit.
- **The fort bonus is visible:** the fort's walls stand behind the defender in battle (§7.2), and the province chip still says "Fort: +2 defense".

### 5.4 villages, landmarks and sites
- **A village on every province,** styled by terrain (plains farms, forest lodges, hill crofts, and later desert, snow and swamp). It stands off the stage and roads, on the side away from the borders a battle can come from (CONCURRENT's placement test). **Its size shows the income:** income 5-6 is 2 buildings, 7-9 is 3-4, and a capital's 12 is a town. The land shows the numbers, and hovering the village shows the income breakdown.
- **Landmarks** where a province's name calls for one: Westwatch gets a watchtower and Stonegate a gate. Each is an optional `landmark` field in the map data.
- **Ascension sites** (the brief's victory provinces) are unique hero landmarks, visible from the strategic zoom, with the gilt plaque from bible §2.4 and their holder's banner once held.
- **Buildings in the way of a battle** shrink off the table as the camera comes down and come back after (CONCURRENT's "the table is cleared").

### 5.5 weather
- **Cosmetic first:** cloud shadows drifting over the land, rain or snow particles at the near zoom, and mist in valleys at dawn during playback. The state comes from a hash of (map seed, turn, province), never from the game's RNG, so it can't touch the rules.
- **It never hides information:** particles stay off labels and plates, never drop a piece's contrast below the §4.2 gate, and turn off at rung 3.
- **If weather becomes a rule** (§10.4), the resolver rolls it from the turn's seed, it shows a turn ahead as a forecast, and the world shows that forecast. Nothing in the world decides it.

### 5.6 scale: bigger maps and 2 to 6 players
- **Tabletop scale:** distances are compressed like a wargame table. A human figure is 1 "man" tall, a province is about 70 men across and its stage about 30. M1's 14-province map is about 420 × 280 men. A house is about 3 men tall.
- **Map sizes (proposal):**

| players | provinces | world size (men) |
|---|---|---|
| 2 | 14-20 | 420 × 280 (M1) to 500 × 350 |
| 4 | 30-40 | 750 × 500 |
| 6 | 50-60 | 950 × 650 |

- **Generated maps** (M6): a province graph with Lloyd-relaxed shapes rendered into the province image, then the same generator as above. Every map passes `WorldPlan`'s tests.
- **Performance at scale:**
  - terrain in 64×64-cell chunks with LODs
  - one MultiMesh per (faction, pose, LOD) for figures and per (piece, LOD) for props
  - visibility ranges, so far villages become simple shapes at the strategic zoom
  - armies are never culled while on screen
- **Six players:** the bible's six slot colours and emblems already exist, and the colour-blind check covers all six.

---

## 6. armies on the map

### 6.1 figure abstraction
In the rules an army is a list of fighters: units, a commander and maybe a ruler, up to about 150 on one side in M2's games. On the map:
- **A block per unit type.** Each type in the army stands as its own block of that type's figures, in formation. Block size is **ceil(count ÷ 2) figures, at most 8**, so the make-up reads at a glance ("lots of spears, a few crossbows, two knights") and the blocks' relative sizes stay honest.
- **The commander and the ruler** each stand as one figure: the commander with a raised standard, the ruler bigger and with the bible's second gilt ring (§2.4). A ruler travelling alone (M2 §1.5) stands with a small retinue of cosmetic guards.
- **Piece scale.** On the map, figures are drawn at piece scale, which grows as the camera rises, so a human figure never drops below **24 px tall at 1920×1080** (CONCURRENT drew its board garrisons 2.4× larger than its battle figures for the same reason). In the fortress close-up and in battles, figures are at true stage scale. Buildings never scale.
- **Far zoom:** when blocks would be under 24 px even at piece scale, the army collapses to a **stand**: its banner, its base ring, and one figure for each of its 3 most numerous types. Bible §2.1's 16 px emblem-dot fallback becomes the stand. The switch uses hysteresis, so it never flickers mid-pan.
- **The count plate:** a small 2D plate above the army with the emblem and the exact fighter count, the only 2D on top of an army. The plate is authoritative; the figures show the make-up. Hovering the army gives the full breakdown, as the 2D map does today.
- **The critic's warning, answered:** no token covers the land, and the figures are the marker. Gate: at the default zoom, a reviewer finds every army, its owner and its main unit type in a screenshot with the plates hidden.

### 6.2 formations
- **Formations follow the battle ranks.** Front-rank (tier 0) blocks lead, facing the army's heading. Second-rank (tier 1: Volley, the Ever-Regent) stands behind them, and the commander's tier 2 at the back. Front-rank rulers stand with the front. The map teaches the battle formation before the first battle.
- **Cosmetic extras, as CONCURRENT learned:** an officer, a drummer and the colours are what made its formations read as armies. In Ascendant the commander is a real officer, so every army adds a **standard bearer** (carrying the army's code banner in the slot colour) and a **musician** in the faction's style (a Crown drummer, a Clans war-horn). They never count. They stand apart, behind the blocks, and the plate's number leaves them out.
- **Large figures** (Knights, War Bear, the Great Thornmane) take double width in a block.
- **Marching columns:** when moving, blocks fold into a column two figures wide along the road, with the banner at the head and the musician behind it.

### 6.3 mustering in fortress yards
- **Muster slots:** every fortress yard has a fixed grid of slots in `WorldPlan`, sized to the fort: a capital holds 6 blocks of 8, a fort 4 blocks of 8.
- **Planning:** a recruit order shows its recruits at once as **ghost figures** in the yard: translucent, with a dashed ring, and the order's forecast beside them ("2 Spearmen arrive at the end of the turn · 14 gold left"). Cancel the order and they fade. Ghosts are private: only the ordering player sees them, and the handoff cover hides the whole world (§6.6).
- **Playback:** at the recruitment phase, recruits file out of the barracks door and fall into their block's slots, a short beat per block. A recruit joins its army as the rules say (M2 §1.5), so the yard shows armies as they will be.
- **Garrisons:** armies standing in a fort province stand in its yard while they fit. **Overflow forms a war camp** of the faction's tents outside the gate. A big muster visibly outgrows its fortress, and that is the signal of a coming war.
- **Warband Muster** (the Ninth Fang) gathers its recruits in a war camp around the Fang, wherever it stands, and they join at the end of the turn, as the rule says.
- **With fog of war** (§10.2), an enemy yard shows only what your vision reaches: an unscouted yard is veiled, and a scouted one shows "last seen turn N". Seeing a rival's muster is earned.

### 6.4 the turn's playback: march-out and arrival
After everyone commits and the turn resolves, the world plays the resolver's events in phase order. It is a pure function of (the state before, the events, the state after) and it never changes the outcome.

| phase (M4 order) | what plays on the land |
|---|---|
| sacrifice | the ruler's banner flares; the mandate's chip appears on the HUD |
| movement | columns leave by the gate or the stage, march the road to the border, cross, and fan out on the destination's stage. Swaps on a border halt both columns at the crossing |
| battles | each battle is marked where it happens, with a short clash beat (2 s). Watch opens the full 3D battle (§7). Losers' armies topple and fade as the aftermath says |
| capture | the wash flows out from the stage; banners change on the fort and in the village |
| recruitment | recruits muster in yards and camps (§6.3) |
| income, research | the HUD as today; a transformation (M4) swaps the faction's figures to their new models with a code shimmer |
| rulers | successions and returns at the capital |

- **Length:** about 15-20 s at 1× for a typical two-player turn. 1×, 2× and 4×, pause, skip phase, skip all. The last speed is remembered.
- **The turn report is linked:** the line describing what's playing lights up, and clicking a report line jumps the camera and the playback to it.
- **Tests:** the world after playing a turn's events equals the world built directly from the next state, for every turn of 20 autoplay games (positions, owners, blocks, banners and yards). The game state is deep-equal before and after.
- **One small rules addition (M3a.2):** move events carry their full step list (for two-step road moves), added without changing any outcome, under M3-1's "byte-identical report" rule.

### 6.5 border clashes and sieges at walls
- **Border clashes:** two armies swapping across a border meet at the road's crossing point, on a bridge if a river runs there. The battle is staged on the border ground (M3's "border battle": nobody defends, no terrain bonus).
- **Fort battles today:** under today's rules, a fort only gives its defender +2 defense in battle. In 3D, the defender's ranks form before their own gate, with the walls behind them (§7.2).
- **With siege rules** (§10.1), a besieged fort shows the besiegers' camp ringing the walls, siege works in the besieger's faction style (ladders and a ram for the Crown, a battering trunk for the Clans) and wall damage in three states. The bible's "besieged" marker (fort icon plus 8 chevrons in the besieger's colour) becomes chevron banners planted around the walls.

### 6.6 hotseat and privacy
- **The handoff cover hides the world as well as the panels.** Ghost recruits, route ribbons and queued orders are drawn only in their owner's view.
- **Battles are public today** (M2 and M3 have no fog). With fog (§10.2), each player's playback shows only what their vision saw, so in hotseat the playback runs per player after the handoff.

---

## 7. battles in 3D

### 7.1 what carries over from M3
M3 was written for a 2D field, but most of it is renderer-agnostic and carries over unchanged:
- **The battle event log** (#56): recording in the resolver, `BattleLog`, `verify_draws`, `regenerate`, size caps, and keeping logs only with the last turn's report.
- **The pure helpers:** `BattleTimeline`, `display_order`, `statuses`, `BattleMoments`, `BattleCaptions` and `BattleExplain` (#57).
- **The readability layer:** strength bars with break notches, round captions, the result card, and hover explanations from the same numbers the rules used.
- **The controls:** speeds, pause, skip, key-moment jumps, the scrubber and the keyboard map.
- **The why panel, the legend, the codex entries, the entry points and the settings file.**
- **Accessibility:** colour plus shape, the flash limiter, reduced motion, text sizes and keyboard reach.
- **Truthful simultaneity:** staggered alternating attacks, with damage landing at the end of the round.
- **The beats and timing** (M3 §4.1), and the three levels of "playback never changes the outcome" tests.

What changes is the field (a 3D stage, not a 2D layout), the figures (3D models, not sprite sheets), the camera (auto-framing, not fixed), the effects (3D and billboards), the budgets (§3.5) and the art (§9).

### 7.2 the stage
- **The battlefield is the province.** Watch dives the camera from wherever the board is onto the province's stage, as CONCURRENT does from its board to its land. You see that province's ground, its woods and hills, its village pushed aside, and its fort. At the end the camera rises back to the board.
- **Who stands where:** the defender holds the stage, facing the border the attacker crossed. The attacker forms up at that border's road and advances. With no defender (both arrived, or a border battle), side 0 takes the end nearer its own territory. Geography decides facing instead of M3's left and right. It also lets the stage hold more than two sides later (CONCURRENT stages any number), which is one reason M3's two-side limit can lift in M6.
- **Ranks as the rules have them:** tier 0 in front, tier 1 behind, commanders at the back (tier 2), as blocks by unit type, as in M3 §3.2. Rulers stand in their tier with the gilt ring and a 2D name plate.
- **Every fighter is its own figure,** 1:1, up to M3's 280-fighter case. Above that, M3's "files" rule applies: one figure for k fighters, with a ×k badge.
- **The fort:** when the defender holds a fort, its walls and gatehouse stand behind the defender's ranks, and its Volley tier (crossbowmen, the Ever-Regent) stands on the wall walk. That's cosmetic, but it makes the "+2 defense" visible. Without a defender, the fort stands empty and its bonus chip says why.

### 7.3 figures and motion: pose swap plus procedural
Each unit has 4 posed models (§9.3): ready, march, strike and fallen. Motion is code:

| log beat | motion |
|---|---|
| deploy, rout | march pose with a step bob; a rout turns the figures and runs them at 1.5× to the back edge, then they fade |
| idle | ready pose with a subtle breathe (±1.5% height), its phase from a hash of the fighter id |
| attack | swap to the strike pose at the impact time, with a lunge of 25% of the distance toward the target and back (melee); ranged releases its projectile at the swap |
| hit | a 0.15 s knockback and the negative tint from M3 §4.1 |
| death | a topple about the feet, then a swap to the fallen pose; the fallen stay down (desaturated 30%), so losses can be counted |
| victory | the winners raise weapons: a hop in the ready pose, or a cheer pose for rulers |

### 7.4 the camera, auto-framed
- **Framing:** it picks the yaw from which the two sides spread across the screen rather than towards it. It raises the pitch until a line-of-sight check against the terrain and the buildings sees every fighter (CONCURRENT counts a church as a hill). Then it fits the formations into the band the UI leaves clear (M3's 1600×600 field) and centres the fight.
- **Free look is allowed:** orbit and zoom while playing or paused; F reframes. Key-moment jumps keep the whole battle framed by default. "Follow the action" is a setting, off by default, because readability means seeing both bars' story at once.
- **Moves:** camera moves are ≤ 1.2 s and skippable. With reduced motion they're cuts.

### 7.5 effects
- **Projectiles:** code meshes with trails (bolt, javelin, arcane bolt), M3 §4.4's speeds and arcs.
- **Impacts, dust and the ruler-fall burst:** M3's 7 Ludo `sprite-vfx` sheets as camera-facing billboards, additive. Placeholders are code stars and puffs, as in M3 §4.2.
- **Auras:** ground decals (▲ and ▼ rings in the side's colour, keylined), M3 §4.6.
- **Floating numbers, hp bars and glyphs:** 2D, projected.
- **Screen shake:** camera shake with M3 §4.5's triggers, spacing and limits (an offset of up to 6 px of screen motion).
- **The flash limiter and reduced motion:** as M3 §7.4.

### 7.6 the M3 tickets: what changes
| ticket | issue | change |
|---|---|---|
| M3-1 event log | #56 | **none.** Keep building. |
| M3-2 moments, captions, explanations | #57 | **none.** |
| M3-3 battle screen | #58 | **re-scoped.** Build the renderer-agnostic `BattlePlayer` (clock, beats, speeds, state per beat) and the 2D overlay the 3D stage also uses (top bar, strength bars, caption strip, result card). The card field stays as the **Simple view** (a setting, and the headless test harness). The 3D stage is a new M3b ticket. |
| M3-4 controls, hover, why panel | #59 | small additions: hover picks through the 3D stage; camera controls and F. |
| M3-5 entry points | #60 | small additions: the dive from the board and back. |
| M3-6 animation and effects | #61 | **rewritten:** pose swap and procedural motion on 3D figures, 3D projectiles, billboard impacts, aura decals, camera shake. The flash limiter and reduced motion carry over. |
| M3-7 big battles and performance | #62 | **re-scoped:** §3.5's budgets on Forward+, MultiMesh, LODs and the quality ladder. M3 §3.4's scale steps are replaced by the camera; massed-battle thinning stays. |
| M3-8 art lead | #63 | **rewritten:** model rows (concept picture, poses, faces, texture size, height) instead of sprite-sheet rows; the bible's §8. |
| M3-9 asset builder | #64 | **rewritten:** a `create3DModel` batch instead of sprite sheets. Only the 7 effect sheets survive from M3 §9. |
| M4-8 phase 2 (battle figures) | #73 | becomes transformed model families (§9.3), after M3a.2's base families. |

M3's 2D sprite plan (321 cr planned, 482 with reserve) and M4's phase-2 battle figures (178 / 267) are replaced by the 3D budget in §9.5.

---

## 8. the camera

### 8.1 one continuous zoom
| zoom | what fills a 1920×1080 screen | pitch | figures |
|---|---|---|---|
| strategic | the whole map; top-down and flat-lit at the far end (the "chart", replacing the 2D map) | 90° → 60° | stands (§6.1) |
| default | 3-4 provinces | about 50° | blocks at piece scale |
| near | one province and its neighbours' edges | about 42° | blocks at piece scale |
| fortress close-up | one yard (§8.3) | about 35° | true stage scale |
| battle | auto-framed (§7.4) | 36-70° | true stage scale, 1:1 |

Pitch follows height, as CONCURRENT goes from 58° over the whole map to 42° zoomed in, so a zoom is one gesture. **Map modes** (ownership, income, terrain, and later vision) work at every zoom and are clearest at the strategic end.

### 8.2 the rules
- **North up by default.** Q and E rotate, N resets, and a compass shows north whenever the view is rotated.
- **Pan and zoom:** pan with WASD, edge scroll or a drag (the ground stays under the hand). Zoom toward the cursor (the ground under the cursor stays put, as in CONCURRENT).
- **The camera never goes below the terrain or into a building,** and never shows the world's edge. A sea and haze skirt surrounds the map.
- **Nothing hides an army.** Buildings between the camera and a piece dither out. An army behind a hill is drawn as a keylined silhouette through it (the stencil buffer).
- **Labels** follow a priority (selected, then capitals, then provinces with armies, then the rest) and never overlap.
- **Orders on the board:** click a province or army to select. Drag from an army to a province to move: a route ribbon follows the road, with the ETA chip and the forecast tooltip from today's orders UI. Common actions stay within two clicks (brief).
- **Cinematic moves** (dives, the rise back, report jumps) are ≤ 1.2 s, skippable by any input, and cuts with reduced motion.
- **Anything you can see, you can hover.** Every piece gives the same tooltip and codex link the 2D map does today, and the world gets its own **Legend** (rings, wash, borders, plates, ghosts, banners, stands, camps, fog) in the M3 §7.1 style.

### 8.3 the fortress close-up
Double-click a fortress, or press "View fortress" in the province panel, and the camera swoops down into the yard. The recruit panel opens beside it. Every unit you queue appears at once as ghosts in its slots, with the cost and gold left. Garrison blocks stand in their slots, with their hover breakdowns, and the gate faces the road they'll take. This is Alex's sentence as a screen: recruitment happens in the place where the army gathers. A fill light keeps the yard bright, so the walls never shade a block into unreadability.

---

## 9. the asset pipeline

### 9.1 the chain
1. **Concept picture (2D):** `createImage`, `image_type: asset`, with the bible's C-model or C-structure block (§8 of the bible), a full figure in three-quarter view on plain light grey with room on every side, and arms a little away from the body (image-to-3D separates the limbs better). Pick from 3 candidates for every base picture.
2. **Picture review (cheap gate):** silhouette, palette and class read in 2D, at 0.5 a picture, before 3 credits are spent on a model.
3. **Model:** `create3DModel` with `target_num_faces` from bible §8's budget, `texture_size` 1024, `texture_type` pbr. 3 credits, 4-25 minutes. Download at once (URLs die in 7 days).
4. **Slim:** `glb_slim` (CONCURRENT's tool, ported). Textures become JPEG at 512 for regular figures and props and 1024 for rulers and hero buildings. Normal and ORM maps are dropped, and images are embedded on import (`gltf/embedded_image_handling`). A figure ends up around 0.4-0.9 MB, a building around 0.5.
5. **Import:** mesh compression on, LODs generated on import, and a collider shape for the pieces that need picking.
6. **Material override:** every mesh gets our `piece` shader in place of Ludo's PBR, which comes out "too shiny". The shader uses the Ludo base colour as albedo, metallic 0, a high roughness and low specular, plus the A/B lighting model and the outline (bible §8). Every piece becomes one material family, whichever generation it came from.
7. **Scale normalisation:** feet at the origin, facing +Z, height in men (1.0 for a human), from one data table per model (height, yaw, long-axis sizing for lying or long pieces, as CONCURRENT's `MODELS` and `LONG`). A test fails on any model without its row.
8. **Gates, then review** (§9.2).

**Send inputs from local files (base64), never Ludo URLs.** Pose edits of a base picture then work after 7 days too.

### 9.2 the review loop
- **A model sheet:** `tools/model_sheet.tscn` renders every model of a batch:
  - at three sizes: strategic (24 px tall), default and close
  - as a 4-view turntable
  - as a greyscale silhouette at 24 px
  - next to a reference human figure and the faction's other models
  - in both looks while the A/B is open
  It writes `studio/contact-sheets/<batch>.png` in the bible §7 style.
- **Automatic gates:**
  - faces within budget and texture within size
  - lowest vertex at the origin within 1% of height, facing +Z
  - no floating islands (connected components)
  - mean figure L\* 40-65 under the default light (the bible §2.5 values, rendered)
  - pose models of one unit within ΔE 8 of the base on their shared materials
- **Human review:** pick or reject with notes in a review batch (CONCURRENT's review table), tracking the first-take rate by kind. Alex makes art verdicts. Bots never do (playbook §8).
- **Ledger** every charged call (playbook §2).

### 9.3 pose families
- **One base picture per unit** (the ready pose). Every other pose is an `editImage` of that picture: "The same figure, now …", with the same outfit, palette and base, as CONCURRENT's `POSES`. Each pose picture then becomes its own model. A unit's poses are one family because they come from one picture.
- **Poses per unit:**
  - regular units and commanders: 4 (ready, march, strike, fallen). A rout reuses march, turned around and sped up.
  - rulers: 5 (adding cheer, or cast for casters)
  - extras (standard bearer, musician): 1 each
- **Transformations (M4):** the unit's base picture edited with the bible §5 transformation block, then its 3 other poses edited from that variant picture. Bible §5's recognisability contract applies to the pictures (silhouette IoU ≥ 0.85, same hands, class read, one faction accent kept).
- **Cross-faction leaks** (bible §3 rule 3): concept pictures anchor only to same-faction pictures, or to a greyscale anchor.

### 9.4 animation
- **The baseline is pose swap plus procedural motion** (§7.3): step bob, lunge, recoil, topple, flee, breathe, cheer hop, banner ripple (shader) and gallop bob. It is cheap, deterministic, and works with every Ludo model.
- **Rigging is one experiment, not a dependency.** CONCURRENT's rig put an arm bone outside the body, because the figure's arms were at its sides and it was fused to its base, and Ludo's docs ask for an A-pose or T-pose. So the experiment starts from an **A-pose concept picture**: model (3), `rigModel` humanoid_template with Godot joint names (1), and 3 `animate3DModel` clips (0.6), about 10 credits for two tries.
  - Pass: no bone outside the mesh, and a walk and a strike with no visible tearing at the near zoom.
  - If it passes, rulers (the heroes, seen closest) may get skinned motion. Everything else stays pose swap.

### 9.5 budgets per faction, and the bill
**Per faction,** at today's roster shape: 3 units, 1 commander, 2 rulers, and 2 forks with a changed unit and a new unit each. The lore room may change the counts. The method holds.

| group | pieces | credits at 3.5 a piece |
|---|---|---|
| units: 3 × 4 poses | 12 | 42.0 |
| commander: 1 × 4 poses | 4 | 14.0 |
| rulers: 2 × 5 poses | 10 | 35.0 |
| army extras: standard bearer, musician | 2 | 7.0 |
| fortress kit: gatehouse, corner tower, keep | 3 | 10.5 |
| capital hall | 1 | 3.5 |
| barracks, war-camp tents, siege works | 3 | 10.5 |
| yard props: weapon rack, banner post | 2 | 7.0 |
| wall mat: seamless stone texture, 2 takes | – | 1.0 |
| extra candidates: 2 more pictures for each of the 10 base pictures | – | 10.0 |
| **base faction** | **37** | **140.5** |
| transformations: 4 units × 4 poses, plus 4 base-picture candidates | 16 | 60.0 |
| **faction total** | **53** | **200.5 planned, about 301 with the ×1.5 reserve** |

**Shared (all factions):**

| group | pieces | credits |
|---|---|---|
| villages: 3 terrains × small and large × 2 variants | 12 | 42.0 |
| landmarks: watchtower, gate, shrine, mill, standing stones, bridge, mine, ruin | 8 | 28.0 |
| ascension sites | 2 | 7.0 |
| independents: fort kit (gate, tower, hall) | 3 | 10.5 |
| independents: 3 garrison units × 4 poses | 12 | 42.0 |
| trees and rocks | 8 | 28.0 |
| ground mats: 10 textures × 2 takes | – | 10.0 |
| battle effects: M3's 7 sheets × 5.5 | – | 38.5 |
| **shared total** | **45** | **206.0 planned, about 309 with reserve** |

**Spikes and experiments:** the look A/B and pose-family test (10 pieces, 35.0), the fortress kit test (10.5) and rigging (about 10): **about 56**.

**The bill:** six factions (1,203) + shared (206) + spikes (56) = **about 1,465 planned, about 2,170 with reserve.**
- That is spread across M3a to M6, with about 540 in the M3 steps (§11). Forts and sieges add about 20 for fort-level kit variants, outside this total.
- For scale: the balance was 6,850 after the style probe (ASSET_MANIFEST). Check `getAccount` before each batch.
- **A 3D unit is cheaper than a sprite unit:** 4 poses × 3.5 = 14 credits, against 23.0 for a 5-state sprite figure (bible §4.1).
- **Model budgets** (faces, textures, sizes) are in bible §8.4.

### 9.6 batches and throughput
- **About 2 jobs at a time** run on the account, whatever the worker count. Pictures take about 1 minute, figures 4-11 minutes and buildings 9-25 minutes. Plan on about 12 models an hour when it's healthy.
- **One faction's 53 models take about 4.5 hours** of generation, plus about 35 minutes of pictures first. Six factions plus the shared set come to about 30 hours. Plan for double that with outages (M1 saw 31 failures in a row): **about one faction a day,** unattended.
- **Order of work** (CONCURRENT's `--make ordered`):
  1. every picture first (cheap and fast), then the picture review
  2. models in order of what the board shows most: the fortress kit, every ready pose, then strike, march, fallen, the rulers' extra poses, the extras and the props
  3. a model's worker waits for its picture, so pictures and models run in separate passes, or waiting models starve the pictures
- **Discipline from the playbook:**
  - a retry driver with at most 2 jobs in flight that bumps `v` on failure and stops at a deadline
  - one cheap real job to probe an outage, never parallel retries
  - two worktrees on one key buy nothing, so the spike and the asset builder never generate at the same time
- **One batch per faction per milestone,** with a contact sheet and a ledger. Candidates and raw GLBs stay gitignored.
- **Repo size:** about 30 MB of slimmed models per faction, about 210 MB for six factions and the shared set. CONCURRENT's rule applies: plain git now, and a planned LFS move only when the history nears 1 GB, with Alex's go-ahead.

---

## 10. scope expansion (proposals for Alex)
Alex: "scope expansion is obviously required." Each item below is a **proposal for Alex**, with why it earns its place, what it touches, and where it would land. Each would get its own spec with exact numbers before any tickets are cut.

### 10.1 forts and sieges as real gameplay. Proposal for Alex.
- **Rule sketch:**
  - Every fort has **walls** (2 for a fort, 3 for a capital).
  - An army entering an enemy fort province whose defenders stand inside may **assault**: a battle with the fort bonus plus a walls part.
  - Or it may **besiege**: no battle. Each turn, the walls lose the besieger's siege strength, the province yields no income or recruits to its owner, and the defenders can sally out.
  - At 0 walls the fort bonus is gone. The new **sieges** phase goes after battles, as the brief's turn order already lists.
  - Every number is forecast: "walls fall in 2 turns · assault odds now: poor".
- **Why:** the brief already has sieges in its resolution order, and M2 deferred them. The fortress becomes the 3D hero, so it should be a decision: storm it now and bleed, or starve it and give the defender time. It gives a turtling player a clock and makes the yard worth defending.
- **Touches:** rules (a phase, walls state, a siege order), the battle log (the walls part), AI, forecasts, the turn report, codex, and the §6.5 visuals.
- **Where:** a forts-and-sieges step after M3b (§11), paired with §10.5.

### 10.2 fog of war. Proposal for Alex.
- **Rule sketch:**
  - Each faction sees its own provinces, its armies' provinces and their neighbours.
  - A fort's towers see 2 provinces.
  - Everything else shows its last-seen state, with "last seen turn N" (bible §2.4 has the look).
  - Battle odds and forecasts count only what you can see, and say so.
- **Why:** mustering is only exciting if the other side can't count your army for free. Seeing an enemy muster must be earned. Simultaneous orders get better guessing and counterplay, the brief's pillar 5.
- **Touches:** a pure per-faction vision rule, filtered reports and playback (§6.6), the AI (it must see only its own vision, the biggest cost), and forecasts.
- **Where:** M5, as now. But the world carries a vision mask from M3a.1, so fog is a data switch and needs no rework.

### 10.3 bigger maps and more players. Proposal for Alex.
- **What:** maps for 2-6 players (§5.6), a map generator, hotseat and AI for 3-6 seats, and battles with more than two sides (the 3D stage stages them by geography, §7.2).
- **Why:** the brief's 1.0 target is maps for 2 to 6 players. A living world at scale is the spectacle Alex is asking for, and the lore room's six factions need room.
- **Touches:** map data and the generator, the AI (several rivals), the battle rules (more than two sides), the turn report at scale, and performance (§3.5).
- **Where:** M6, with the factions.

### 10.4 weather and seasons, only if they earn a gameplay effect. Proposal for Alex.
- **Rule sketch:** a fixed calendar, shown in the HUD with the turns left in the season:
  - spring: rivers in flood, crossable only at bridges
  - summer: no effect
  - autumn: +10% income (the harvest)
  - winter: armies outside your territory and off the roads lose 1 hp per fighter a turn
- **Why:** the calendar gives the 3D roads, rivers and bridges a rule (the critic: make the land matter) and creates timing decisions ("strike before winter"). It's predictable, so it's planning, not dice: the brief's "nothing hidden that matters".
- **Recommendation:** seasons with this rule, yes. Random per-turn weather stays cosmetic (§5.5), unless it shows a turn ahead as a forecast.
- **Touches:** rules (calendar effects), forecasts, the AI, codex, and the §4.2 season grades.
- **Where:** M5.

### 10.5 building and upgrading fortresses. Proposal for Alex.
- **Rule sketch:** a **Fortify** order in a province you own costs gold over several turns:
  - level 1, palisade: +1 defense, walls 1, recruits regular units
  - level 2, stone: +2 defense, walls 2, recruits commanders
  - capitals are level 3
- **Why:** players choose where their armies muster, with forward bases near the front. The brief keeps Dominions' "forts that gate recruitment". And the investment shows in 3D: scaffolding, then walls rising over the turns.
- **Fit:** good only together with sieges (§10.1). Each makes the other matter.
- **Touches:** rules (an order, fort levels, recruitment sites), economy balance, AI, forecasts, and the §5.3 kits (the levels as kit variants).
- **Where:** the forts-and-sieges step.

### 10.6 independents: neutral garrisons in the world. Proposal for Alex.
- **Rule sketch:**
  - Every unowned province starts with an independent garrison sized by its income: slate colour, heater-shield emblem (bible §1.1).
  - Garrisons never move. Taking a province means beating its garrison.
  - Each region's independents have a unit you can recruit once you hold it, as in Dominions.
  - Sworn Vassals already exists for this.
- **Why:** the early game gets real choices (which neighbour first, with what), the world feels inhabited before the players arrive, and armies fight the land, not just each other. The rules cost is small: garrisons are armies with no orders.
- **Touches:** map data, battles against independents, M1/M2 pacing and balance bands, Sworn Vassals' wording, codex, and the shared independents art (§9.5).
- **Where:** M3a.2, if approved. It's cheap, and it fills the board the camera now shows off.

---

## 11. milestone restructure
Every step ends in something Alex can play. Rules work that doesn't depend on the renderer goes on in parallel: M3-1/M3-2 now, and M4's rules as built. The step names follow the director's suggested order.

| step | goal (what Alex plays) | in it | art (planned cr) |
|---|---|---|---|
| **now** | (no change) | #56 event log and #57 captions continue; the 3D spike; the lore room; the look A/B | spikes, about 56 |
| **M3a.1 the world** | an M2 game (rulers on) played on the 3D board, with every order, forecast and tooltip working as on the 2D map | Forward+ and the quality ladder; the SubViewport world; the M1 map's province image and terrain; borders, wash, roads, rivers; Crown and Clans fortress kits; villages; the camera ladder; picking and orders; labels; the world legend; perf probe; armies as blocks of **ready poses only**; the 2D map as a fallback setting | both factions' fortress kits and wall mats, 12 ready poses (every unit, commander and ruler), villages (one variant), trees, ground mats, base candidates: about 150 |
| **M3a.2 the armies** | you watch each turn resolve on the land, and you can predict the next battle from what you saw muster | full pose families for both factions; formations and extras; muster yards, ghosts and war camps; the fortress close-up; the turn playback with its controls and report links; border clashes as clash beats; move step lists; **independents** if approved (§10.6) | both factions' remaining 54 pieces (189), village variants, landmarks, ascension sites (56), independents if approved (52.5): about 300 |
| **M3b battles on the land** | M3's own goals: from the bars alone you can tell who is winning, and you can say why from what you watched | #58 re-scoped (BattlePlayer, 2D overlay, Simple view); the 3D stage; #59, #60 additions; #61, #62 rewritten (§7.6) | 7 effect sheets: 38.5 |
| **forts and sieges** (if approved) | storm or starve a fortress, and fortify a forward base | §10.1 and §10.5: rules, AI, forecasts, siege visuals, fort levels | siege works are in the faction sets; fort-level kit variants: about 20 |
| **M4 in 3D** | M4's goals, plus a 3D turntable of your transformed units in the lock-in preview | the M4 rules as built; the transformed model families; the preview turntable | 2 × 60: 120 |
| **M5 magic and fog** | M5 as outlined, plus fog: seeing a rival's muster is earned | magic; fog of war (§10.2) on the vision mask; seasons (§10.4) if approved | spell effects (to be specced) |
| **M6 six factions and bigger maps** | a 4-6 player game on a generated map with the lore room's factions | factions 3-6 (rules and art); the map generator; 3-6 seats; battles with more than two sides (§10.3) | 4 × 200.5: about 800, plus villages for any new terrains |

- **Lore first, then figure families.** The Crown's and Clans' full pose families (M3a.2) wait for the lore room to lock each faction's look, palette and silhouette language, so no faction is modelled twice. M3a.1 needs only fortresses and one ready pose per unit, which survive small lore changes.
- **The 2D map stays a setting until M3a.1 is accepted.** The 2D card battle view stays as Simple view for good.
- **Realism:** M3a.1 is about as big as M1 (around 10 tickets). M3a.2 and M3b are about as big as M3 (8-9 tickets each, much of M3b already specced). Each gets a full spec in the M2/M3 format before tickets are cut.

---

## 12. risks, and how to retire them
| risk | why it matters | the spike or test that retires it | when |
|---|---|---|---|
| Ludo pose families don't hold together | blocks look like a crowd of strangers | the pose-family spike: 1 unit × 4 poses on the model sheet; pass when a reviewer can't tell the poses are separate generations at the default zoom, and shared materials are within ΔE 8 | the spike |
| figures don't read from the strategy camera | the 3D becomes noise, not information | the 24 px silhouette gate on every model; the "find every army, owner and main type with plates hidden" screenshot test; fallbacks: larger piece scale, the far-zoom stand | the spike, then every batch |
| the cel ramp shades Ludo's painted textures twice | muddy pieces | the look A/B screenshots, with Alex picking | the spike |
| performance on minimum spec | the game is unplayable on a common laptop | `--perf` probe scenes (the largest map, 600 figures, the 280-fighter battle) at every rung; measured on an Iris Xe laptop and Alex's Mac; fail means cut density or effects until rung 4 holds 30 fps | the spike, then M3a.1 |
| 3D hides information (or adds none) | the critic's "backdrop" warning, or worse | the click-every-province-and-army probe (0 wrong); the occlusion silhouette; a timed read with Alex: "who owns what, where are the armies" on the 3D board against the 2D map | M3a.1 acceptance |
| the fortress kit pieces don't join | gaps in the hero model | the kit spike: one fortress from gatehouse, towers and keep plus code walls; pass with no gap at the close-up, and the yard holds its slots | the spike |
| rigging fails | none: nothing depends on it | the one A-pose experiment (§9.4) | after the spike |
| presentation leaks into the rules | lost determinism, desyncs later online | static tests (no RNG or resolver calls in `ui/world3d/` or `world/`); "the world never changes the game" deep-equal tests | every PR |
| playback and the state disagree | the board lies | "play the events = build from the next state" on 20 autoplay games | M3a.2 |
| six factions blur together | factions 3-6 are hard to tell apart | the lore room delivers palettes and silhouette language; the 6-palette greyscale sheet passes before any model is made | before M3a.2's art |
| Ludo outages and throughput | art stalls milestones | placeholders first (code blocks, the Simple view), so nothing waits for art; the retry driver; one faction a day | always |
| repo growth from GLBs | slow clones for the bots | slimming, texture budgets, `repo_size` per batch; the LFS decision at about 1 GB history | every batch |
| drivers: old Intel, Linux without Vulkan | crashes on start | the automatic Compatibility fallback is tested as rung 5 on the build box | M3a.1 |
| hotseat leaks through the world | the other player sees ghosts or routes | the handoff hides the world; a test that a covered screen draws no private node | M3a.2 |
| new visuals arrive without explanations | broken approachability promise | the world legend and codex entries ship in the same PR as each visual (brief rule 1) | every PR |

---

## 13. not decided here
- Sound in 3D: positional ambience (wind, surf, a busy yard) is a natural fit (CONCURRENT's `land_bed`), but sound isn't scheduled.
- Naval rules and sea provinces.
- Online play: the "world never changes the game" rule keeps that door open.
- Replays and sharing battles (M3 §10 holds).
- Mod support.

---

## 14. director's calls (review these first)
1. **Stay on Godot 4.5, pinned at 4.5.1.** No engine change. Everything we have is pure GDScript, and CONCURRENT proved this look in this version on your Mac.
2. **Forward+, with a 6-rung quality ladder** that steps down on its own and falls back to Compatibility as the floor. M3 §8.1's UHD 620 / GL Compatibility target is dropped.
3. **Hardware.** Minimum: a 2020+ integrated GPU (Iris Xe, Radeon Vega 7, Apple M1) at 30 fps on rungs 3-4. Full: a GTX 1660 / RTX 2060 class GPU at 60 fps on rung 0. **We need an Iris Xe laptop to measure on (about $500-700). Buy or borrow one?**
4. **One world, in a SubViewport under the 2D UI.** The board and the battles share it. All text, plates and numbers are 2D, projected from the world.
5. **The 3D army is the marker.** A block per unit type (ceil(count ÷ 2), at most 8 figures), piece scale on the map (never under 24 px), a stand at the far zoom, and one small count plate.
6. **Fortresses are kits** (Ludo gatehouse, towers and keep, code walls, an open yard with fixed muster slots). Overflow becomes a war camp outside the walls.
7. **The look is an A/B the spike's screenshots decide.** The director's lean is painted-lit with outlines on pieces only.
8. **Player colour only in code:** base rings, banners, territory wash and fortress pennants. Hue-key repainting only if the spike shows it's needed.
9. **Motion is pose swap plus procedural movement,** with 4 poses per unit and 5 per ruler. Rigging is one A-pose experiment of about 10 credits.
10. **Art budget:** about 200 credits per faction planned (about 300 with reserve). About 1,465 planned and 2,170 with reserve for six factions, the shared world and the spikes. It replaces M3's sprite plan and M4's phase-2 figures.
11. **M3 tickets:** #56 and #57 continue unchanged. #58 is re-scoped. #59 and #60 get small additions. #61, #62, #63 and #64 are rewritten for 3D after the spike (§7.6).
12. **The order:** M3a.1 world → M3a.2 armies and turn playback → M3b battles → forts and sieges → M4 in 3D → M5 magic and fog → M6 six factions and bigger maps.
13. **The scope proposals:**
    - independents: yes, early (M3a.2)
    - forts, sieges and fortress building: together, after M3b
    - fog: stays in M5, with a vision mask in the world from M3a.1
    - seasons: only with a rule you can plan around; random weather stays cosmetic
    - bigger maps and 6 players: M6
14. **The 2D map stays a setting until M3a.1 is accepted,** then retires. The 2D card battle view stays as Simple view and as the test harness.
15. **The lore room locks a faction's look before its full model family is generated.** M3a.1 uses only fortresses and ready poses.
16. **All on-screen names are proposals:** "muster yard", "war camp", "stand", "piece scale", "Simple view", "View fortress".
