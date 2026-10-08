# Seat notes: art round 2, the Candlewake and the Kilnborn

## Tool and settings
- **Tool:** Ludo.ai REST API, `POST /assets/image` (createImage), through `../ludo_images.py`. Same endpoints and auth as round 4.
- **Model:** createImage has no model selector, so it is "Ludo createImage, current default".
- **Settings:** `art_style` Cel-Shaded and `augment_prompt` true on every pick (one unpicked re-roll, `candlewake_dominion_r10`, ran with augmentation off).
  - Portraits: `image_type` asset, 3:4, 864×1152. Every prompt ends with the brief's portrait block, word for word (checked by script).
  - Fortress and dominion: `image_type` art, 16:9, perspective High Angle, 1344×768.
  - No style reference. Ludo has no still upscaler, so these are the largest sizes it gives.
- **Files:** the ten finals sit in this folder. `candidates/` holds all 97 candidates and `ludo_ledger.jsonl`. `work/` holds `make_prompts.py` (every prompt, exact), the per-round prompt JSON and the run logs.
- **Review:** I looked at every candidate, and checked all six portraits at 96×128 (they read apart). No final shows text or letters.

## Credits
- **Spent: 48.5 of 60**, across 29 jobs and 97 images in 11 runs. A job costs 0.5 credit an image.
- **Balance:** 5545.1 before, 5496.6 after. The difference is exactly the ledger, so no one else spent on the key.
- **By slot:**

| faction | slot | jobs | credits |
|---|---|---|---|
| Candlewake | ruler1 (Half-Death) | 2 | 3.0 |
| Candlewake | ruler2 (Chandler) | 2 | 3.0 |
| Candlewake | commander | 5 | 7.5 |
| Candlewake | fortress | 2 | 3.0 |
| Candlewake | dominion | 9 | 18.0 |
| Kilnborn | ruler1 (Kiln-Mothers) | 2 | 3.0 |
| Kilnborn | ruler2 (Unfired) | 2 | 3.0 |
| Kilnborn | commander | 1 | 1.5 |
| Kilnborn | fortress | 2 | 3.0 |
| Kilnborn | dominion | 2 | 3.5 |

## Picks, and what lost
| final | pick | why this one | what lost |
|---|---|---|---|
| `candlewake_ruler1` | `candlewake_ruler1_r2_c3` | Half-Death: smooth alabaster half, the other half only a lilac outline, lantern on a crook. No hood, skull or scythe. | Round 1 and the other round 2 drew hooded masks, a tiny face, and two skulls (Ghost Rider, grim reaper). |
| `candlewake_ruler2` | `candlewake_ruler2_r2_c1` | The Chandler: the one warm face, wax-streaked hair, a gold taper against the dead's lilac. Cel-flat like the shipped set. | r2 c3 is good (more wax in the hair) but painterly. Round 1 gave a smiling woman and one with no candle. |
| `candlewake_commander` | `candlewake_commander_r3_c3` | The Lamplighter: gaunt waxen face, lilac eyes, wick in a brass cap, lantern pole. Reads as dead wax. | Candle-heads (Litwick), skulls in berets (Ghost Rider), living pink men. Runner-up r4 c3 is flatter but reads as a living priest. Shading is softer than the shipped set. |
| `candlewake_fortress` | `candlewake_fortress_r2_c3` | Ring of candle towers round a mound and one great candle, a wide grass margin, and a flame on every figure in the muster. | Round 1 c1 has better wax massing, but its muster runs off the frame and the troops have no flames. |
| `candlewake_dominion` | `candlewake_dominion_r2_c4` | Green left, pale wax right, candles in the fields. The road, hedges, cottages and stream cross the border. The strongest ground change of nine rounds. | Later rounds lost the stream or road, looked like sand not wax, or dropped the candles. Flaw: lilac window light and a few candles leak onto the unclaimed side. |
| `kilnborn_ruler1` | `kilnborn_ruler1_r2_c1` | Three old faces in a row read as one body: orange-brown clay, turquoise eyes, cream hoods, a kiln paddle. | Round 1 gave red faces with blank eyes and three small figures. |
| `kilnborn_ruler2` | `kilnborn_ruler2_r2_c3` | The Unfired: grey-brown wet clay with a visible surface, long clay hair, a half-made figure in its hand. Reads as clay, not skin. | Bald giants whose clay read as skin, and a smiling Buddha. |
| `kilnborn_commander` | `kilnborn_commander_c2` | The Kiln-Master: flat square tile slabs, turquoise helm, paddle standard with a glowing disc. Stays square, never round. | c1 and c3 had round scale collars and domed helmets that drift to Aztec armour. |
| `kilnborn_fortress` | `kilnborn_fortress_r2_c3` | Brick walls, turquoise tile roofs, a glowing arched gate, two chimneys, and a grid of troops on a tile floor outside the gate. Wide margin, all square. | Round 1 and r2 c1, c2 crop the plot or smoke, or have little margin, or hide the muster in the courtyard. |
| `kilnborn_dominion` | `kilnborn_dominion_r2_c1` | Gold light, a clear line of boundary stones, road and stream crossing it. Tiled fields, turquoise roofs, small kilns and capped walls on one side. | Round 1 changed more ground but bent the road or stream. r2 c2 is the runner-up (more tile, flat light, diagonal border). |

## Things Alex should know
1. **The Candlewake mark is the Wake.**
   - The land "sits up": every household keeps a candle in its window, and the host takes a little warmth as it passes. The wax is the receipt.
   - It keeps Alex's image (the dead must keep taking warmth to stay lit) and it is gentle, which fits their sorrow.
   - The Wake-line rule seed makes a held province count as a fort for Wick. That ties the mark to the momentum rule.
2. **The Kilnborn mark is Fired Ground.**
   - They fire what they hold into squares, with no hollows and no vessels, so it keeps the jar taboo.
   - A lost province keeps its tile and scars. It does not fight.
3. **Both marks are buildable.** Each is one ground texture, a few instanced props and a seam decal, and each thins out on low quality (see section 5 of each dossier).
4. **The Candlewake dominion is the weakest image of the ten.** If it matters, a hand-edit to remove the lilac on the unclaimed cottages is the cheap fix.
5. **Ludo reads prompts literally.** "Wax figures with flames" gave candles with legs. "Candle-headed" gave Litwick. Positive anatomy ("a human head with a wick cap") did the work. Models also drift to skulls for anything dead.
6. **Early picks:** my image viewer dropped many images at the start of the session. I re-viewed all 97 candidates before settling the picks, and the dossiers' "not picked" notes come from that pass.

## Strongest faction: the Kilnborn, this round
- **The art:** all five slots are clean. The fortress and the dominion are the clearest direction for a modular 3D kit (square wall, tower, gate, keep, chimney, tile ground, capped posts). The Kiln-Mothers and the Unfired are the most different pair of rulers: three old faces as one body, and one wet soft giant.
- **The idea:** the jar taboo turned a lookalike problem into the mark itself (no hollows, only squares).
- **Runner-up: the Candlewake.** It has the best ruler pair (Half-Death and the Chandler read apart even at 96×128) and the more original mark. It loses on the commander's softer shading and the dominion's lilac leak.
