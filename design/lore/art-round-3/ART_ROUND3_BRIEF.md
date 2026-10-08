# ASCENDANT lore room, round 6: art round 3

You are one seat of an art team (Codex and Grok this round) for ASCENDANT, a simultaneous-turn fantasy strategy game in the spirit of Dominions, in 3D. Alex, the owner, reviewed round 2 and gave direction. This round follows it.

Your images go into Alex's new **Review Table**, where he judges each one **Good**, **Good with changes** or **Bad**, **blind**: both seats make the same image slots, and he sees them side by side without knowing who made which. Make every slot your best.

## Read first
- `ref/<faction>/` for each faction below: its dossiers (round 1 and round 2), its round 1 key art, lineup and banner, and its round 2 portraits, fortress and mark-on-the-land images. Build on them; keep each faction's palette, materials and silhouette.
- `R3-synthesis.md` (the world: Halfmade, the Held Sun, Free Holds), `R4_ART_PASS_BRIEF.md` (Alex's standing direction: the Wright is a mystery, "the Making" is the world's power), `PACKET.md` §3 (the style bible) and §7 (the engine's constraints), `ref/GAME_BRIEF.md`, and `ref/M5_MAGIC_FOG.md` §2 (fog of war).
- `ref/game_portraits/`: the game's shipped portraits, for portrait framing.

## What Alex said (2026-10-06)
- He loved that most marks on the land don't vanish when land changes hands: they linger and crumble away, so **the map tells the story of the war**.
- **Paint the place, not the game piece.** In round 2, two seats drew each capital as the in-game fortress kit. That is useful, but he also wants true concept art of the fictional capital: the city as a place people live in, at its most evocative.
- **The Candlewake are now the game's third faction**, the next one to be built. Their presence turns buildings into wax: fortresses and cities that were once made by human hands come to look like half-melted wax candles.
- **The Lacquer Reed:** go beyond flutes. Use recorders and every other kind of wind instrument, and tie them to unit variety and to the leaders and generals. They must be actually cool: say what being these strange instrument-bodies *gives* them. The faction plays around building **chords**: musical combos.
- **The Kilnborn:** the Unfired is awesome. He likes the Kiln-Mothers as a concept, but the art needs to be better. He loves the in-game Great Kiln and Fired Ground.
- **The Veiled Table:** he likes the round 2 redesign. Its whole identity should centre on **guessing correctly what the other players are doing, even when those moves don't affect it**. It is the faction that makes you feel like a genius.

## Image slots (both seats make every slot)
| file | what | shape |
|---|---|---|
| `candlewake_capital.png` | **The Long Vigil as a place:** a once-human walled city taken by the Wake. Its towers, roofs and walls are half-melted into candles, wax runs down the streets, and lilac flames burn in the windows. People (living and dead) are in it. Cinematic concept art under the Held Sun's low golden light. | wide |
| `candlewake_melt.png` | **The melt:** one human fortress shown three times side by side, left to right: just taken (candles on the battlements, the first drips), held a while (towers sagging, wax over the walls) and heartland (a fortress-shaped candle). The same fortress and the same strategy camera each time, as direction for 3D building-swap variants. | wide |
| `candlewake_lineup.png` | **The host as a model sheet:** Half-Death, Mother Tallow, the Lamplighter and three or four units from the dossiers, side by side on a plain ground, readable as silhouettes from a strategy camera. Match the round 2 portraits' people. | wide |
| `candlewake_tide.png` | **The tide:** a Candlewake army deep in a campaign, burning hotter the longer it fights, crashing into a line of Aurel Crown soldiers (blue and gold), with a captured town melting behind it. | wide |
| `lacquer_reed_section.png` | **The wind section as a model sheet:** six or seven Reed unit types, each a different wind instrument made body (recorder, shawm or oboe, bassoon, bagpipe bellows, ocarina, horn, panpipes, conch, and others), plus one or two leaders or generals as grand instruments. Readable silhouettes, plain ground. | wide |
| `lacquer_reed_capital.png` | **Chimewater as a place:** the marsh capital people live in, cinematic. | wide |
| `lacquer_reed_chord.png` | **A chord struck in battle:** several Reed instrument-units sounding together, and what the chord does to the enemy. | wide |
| `kilnborn_kiln_mothers.png` | **The Kiln-Mothers, redone:** the three old women who have fired every Kilnborn child for three hundred years and speak in turn (Hest Turquoise, Calda Celadon, Brin Oxblood). Framed like the shipped portraits: head and shoulders, three-quarter view facing left, faces in the upper half, plain softly graded deep indigo background. | 3:4 |
| `kilnborn_unfired.png` | **The Unfired, full figure:** soft wet clay, a house tall, among small fired Kilnborn soldiers, with a stranger's thumbprint in it. | wide or tall |
| `kilnborn_capital.png` | **The Great Kiln as a place:** the hill-sized kiln city, cinematic. | wide |
| `veiled_table_key.png` | **The genius moment:** the Table's war room reading every rival's plan at once, under the Held Sun. | wide |

## Writing (one document per seat)
- **Codex: `veiled_table_v3.md`** (900–1,600 words). Rebuild the Veiled Table's identity around **calls**: predicting what other players will do this turn, including moves that don't touch the Table, and being rewarded for being right. Starting ideas, keep or replace them:
  - calls are collected with the orders and scored after resolution, deterministically;
  - a harder call pays more than an obvious one;
  - streaks of correct calls build toward something big;
  - the turn report has a "called it" moment, a reveal the other players see too;
  - the round 2 fog tools (Sound the Depth, Listening Posts and so on) become ways to make better calls.

  Say how it stays fair in hotseat (nothing leaks through the fog), how the computer plays it, what the counterplay is (being unpredictable should cost something), how it avoids degenerate safe calls and analysis paralysis, and what it costs to build in the engine's terms.
- **Grok: `lacquer_reed_instruments.md`** (900–1,600 words):
  - the instrument families as the roster: each unit's instrument, role, one trait in engine terms, and what that instrument-body gives it;
  - the leaders and generals as instruments;
  - the **chord** system: how units combine into chords in the autoresolved battles (which units, which ranks, what each chord does), how the player builds toward chords across turns, and how the battle log, forecast and captions explain them.

  Make it cool first, then make it explainable.

## Also write
- `prompts.json`: one entry per image, `{"<file>": {"prompt": "<the exact prompt you used>", "label": "<a short title>"}}`.
- `notes.md`: the image tool and model, anything Alex should know, and your strongest image this round.

## Rules
- **No text, letters, captions, labels, watermarks or signatures in any image.**
- The look: bright, colourful high fantasy, "dark but not grim". Cel-shaded lean (flat saturated colour, thick clean outlines, strong silhouettes), but concept art of places may be more painterly if it serves the place.
- **Original only:** no thinly veiled elves, dwarves, orcs, undead legions, Warhammer, Dominions, Elden Ring, Dark Souls or any recognisable IP. No real religious sites or symbols: in round 2, a black cube in a round court read like the Kaaba.
- Re-roll weak results; keep only your best image per slot. Save PNGs.
- Write files **only** in your seat's output folder. Read anything in this folder and `ref/`; don't open the other seat's folder. Never print secrets.
