# ASCENDANT lore room, round 5: art round 2 for the picks

You are one seat of a three-lab art team (Claude, Codex, Grok) for ASCENDANT, a simultaneous-turn fantasy strategy game in the spirit of Dominions, now in 3D: a 3D world map where armies muster in fortresses and spill out to war, and 3D battles under a clean 2D interface. Round 4 (the art pass) gave every faction a dossier, key art, a lineup and a banner. Alex, the owner, has now picked the factions he wants to see more of. This round takes **your seat's picks** deeper: their rulers' faces, their fortress, and the mark they leave on the land.

This is concept art and lore, not game assets. Nothing here goes into the game yet.

## Read first (in this folder and your seat's `ref/` folder)
- `ref/` in your seat folder: your round 4 dossier, key art, lineup and banner for each of your picks, and your round 4 notes. Build on them; keep what worked.
- `R3-synthesis.md`: the world (Halfmade, the Held Sun, Free Holds, Noonmarks).
- `R4_ART_PASS_BRIEF.md`: Alex's 10-5 direction. It still stands (the Wright is a mystery; "the Making" is the world's one power; depth means *why* a people chose what they are).
- `PACKET.md` §3 (the style bible's key parts) and §7 (the engine's constraints).
- `../ref/game_portraits/`: the game's shipped ruler and commander portraits (the Aurel Crown and the Thornmane Clans). Your portraits must sit next to these in the same UI.
- `../ref/vistas/`: round 4's three vistas. Alex called **Vista B the most impressive** and said **A and C tell the best story**. Aim for both: spectacle *and* a story you can read in the picture.

## Alex's picks (2026-10-05)
The Candlewake, the Ember Orchard, the Lacquer Reed, the Kilnborn, the Verdigris Pans and the Glasswake Compact, plus **maybe the Veiled Table, if its mechanics land: it should play entirely differently.** The Aurel Crown and the Thornmane Clans are built and stay as they are. The MVP ships with those two; one or two of the picks may join after it.

Alex's open idea, now part of this round (his words, paraphrased): **each faction makes the land it holds**, like the dominion candles in Dominions, so the ground of the map literally changes under whoever owns it.

## Your factions
- **Claude:** the Candlewake (`candlewake`) and the Kilnborn (`kilnborn`).
- **Codex:** the Ember Orchard (`ember_orchard`) and the Glasswake Compact (`glasswake_compact`), plus the Veiled Table (`veiled_table`, your round 4 `hearthbound` rework). For the Veiled Table, the mechanics come first (deliverable 3).
- **Grok:** the Lacquer Reed (`lacquer_reed`) and the Verdigris Pans (`verdigris_pans`).

## Deliverables (all in your seat's output folder, the folder this brief told you to write in)

### 1. Five images per faction (PNG, the best size your tool gives)
| file | what | shape |
|---|---|---|
| `<slug>_ruler1.png` | the faction's first ruler | portrait, 3:4 |
| `<slug>_ruler2.png` | its second ruler | portrait, 3:4 |
| `<slug>_commander.png` | its commander | portrait, 3:4 |
| `<slug>_fortress.png` | its capital fortress | wide |
| `<slug>_dominion.png` | the mark on the land | wide |

**Portraits.** In the game a player picks one of two rulers before the game starts, so the two rulers must be different people with different reasons to rule, and must read apart at 96×128 px. Match the shipped portraits' framing so they sit in the same UI: head and shoulders, three-quarter view facing left, face in the upper half of the frame, one held item that says who they are, plain softly graded deep indigo background. End every portrait prompt with the style bible's portrait block, word for word:
> Cel-shaded portrait of bright high fantasy: head and shoulders, three-quarter view facing left, face in the upper half of the frame, thick clean dark outline, flat saturated colours with one hard shadow tone and one highlight tone, bold simple shapes, plain softly graded deep indigo background.

**Fortress.** The capital fortress at its fullest, seen from the strategy camera (a high three-quarter view, about 45° down), whole, on its own plot of ground with empty margin around it, under the Held Sun's low golden light. Show its muster ground with a few troops gathering, for scale. Clear massing that reads from far away. It is direction for a modular 3D fortress kit, so favour a few strong, repeatable parts (wall, tower, gate, keep, the faction's signature building) over fussy detail.

**Dominion (the mark on the land).** A wide strategy-camera view across one province border. On one side is ordinary unclaimed Halfmade country: green fields, a hedge, a road, a stream, a few cottages, a forest edge. On the other side is the **same** country after long rule by your faction: the same road, stream, cottages and forest carry on across the border, but your faction's mark has changed the ground itself. Show the mark creeping across the seam. Make the change the only difference, so it reads at a glance as "this land belongs to them now".

### 2. A second dossier per faction: `dossier2_<slug>.md` (500–900 words)
1. **What changed** since round 4, in two or three lines (or "nothing").
2. **The two rulers:** name, who they are, why they rule, and what they want. Say what kind of game a player gets by picking one over the other, using the engine's terms (PACKET §5 and §7: rulers fight, can die and pass the throne on, hold mandates, and can be sacrificed for power).
3. **The commander:** one paragraph.
4. **The fortress and capital:** what it is, who built it and how, its muster ground, and how it grows. In the game, forts can be built and upgraded, so give it two or three tiers.
5. **The mark on the land:**
   - in story, what this people does to land it holds, and why;
   - how it looks in three stages: newly taken, held a while, and heartland;
   - what happens when they lose the land: does the mark linger, scar, fade or fight the new owner's mark?
   - how the 3D board could show it cheaply: a ground texture or tint, scattered props, a border-edge treatment, light or particles. All of it must thin out on low quality settings;
   - an optional rule seed in engine terms: at most one small effect. Design owns every number.
6. **Its sharpest rivalry and its unlikeliest ally** among the other picks, the Crown and the Clans, in one or two lines each.
7. **The exact image prompts you used.**

### 3. Codex only: `veiled_table_mechanics.md` (800–1,500 words)
Alex wants the Veiled Table to **play entirely differently**: a diplomacy and espionage, big-brain faction. Round 4's Whispered Terms is another plus-two modifier, so it doesn't yet meet that bar. Redesign how a Veiled Table turn plays, so it feels like a different game from the Crown's and the Clans'.
- The game now has **fog of war** (`../ref/M5_MAGIC_FOG.md` §2) and **Free Holds**, neutral provinces with garrisons you must beat to take them. The fog is a lens: the resolver never reads it, and each player sees a view state built from sight, estimates, memory and intel. That makes intelligence, deception and turning holds without a battle possible. Use it.
- Keep the engine's rules (PACKET §7, `../ref/GAME_BRIEF.md`). Turns are simultaneous and resolved deterministically from a seed. Hotseat must stay fair: nothing on one player's screen may leak what the fog hides from them. Every effect must be explainable in a forecast or a tooltip.
- Give its turn loop, its 3–5 signature actions, how it wins fights it can't win by force, what beats it (counterplay), how the computer would play it, and which existing systems each piece touches (to show the build cost).
- Say honestly where it might be no fun, and how you'd guard against that.

### 4. `notes.md`
Which image tool and model you used, anything Alex should know, and which of your factions came out strongest this round, and why.

## Rules for the images
- **No text, letters, captions, labels, watermarks or signatures anywhere in any image.**
- The look: bright, colourful high fantasy, "dark but not grim". The game's style is cel-shaded: flat saturated colour, thick clean outlines, strong silhouettes. Lean toward it, and keep each faction's round 4 identity (palette, materials, silhouette) so the set reads as one people.
- **Original only:** no thinly veiled elves, dwarves, orcs, undead legions, Warhammer, Dominions, Elden Ring, Dark Souls or any recognisable IP. Each faction must read apart from the others at a glance.
- If a result is weak, re-roll it. Keep only your best image per slot.

## Rules for the work
- Write files **only** in your seat's output folder. Read anything in this folder and your own `ref/`; don't open the other seats' folders, and don't edit anything else.
- Never print secrets.
