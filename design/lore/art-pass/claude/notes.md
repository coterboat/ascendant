# Seat notes: the Candlewake, the Stormherd, the Kilnborn and the Revel

## Tool and model
- **Tool:** Ludo.ai REST API, `POST /assets/image` (createImage), polled on `GET /assets/jobs/{id}?wait=55`. These are the same endpoints and the same auth as `tools/ludo/ludo.py`.
- **Settings:** `art_style: Cel-Shaded` and `augment_prompt: true` on every call. That is Ludo's own default, and it rewrites prompts server-side.
- **image_type:** `art` for the key art, lineups and vista; `asset` for the banners, the type the shipped banners used.
- **Model:** createImage exposes no model selector (the API's model list covers only animation and video), so the model is "Ludo createImage, current default".
- **Sizes:** native output is 1344×768 for 16:9 and 864×1152 for 3:4. Ludo has no still-image upscaler, so these are the largest sizes the tool gives.
- **No style reference (`generateWithStyle`).** It takes no aspect ratio and returns near-square images, but the brief wants wide and tall. The M1 batch also found that a style anchor leaks palette and costume across factions (8 of 9 beast portraits came back in the Crown's blue). For four peoples that must read apart, one verbatim style block per image class did the series-matching instead. The blocks are in `make_prompts.py`, and the banner block is STYLE_BIBLE's C-banner word for word.
- **Script:** `../ludo_images.py`, stdlib only and reusable by any seat:
  - Usage: `python3 ludo_images.py prompts.json outdir --budget 150 [--jobs 3] [--dry-run]`.
  - It skips names that already have candidates, uses a digest of the request body as the request id (so a resumed run never pays twice), and converts webp or jpeg to PNG.
  - It appends every charged job to `outdir/ludo_ledger.jsonl`, and the budget counts that whole ledger plus jobs in flight.
  - It reads the key from the environment or `.env.local` and never prints it.

## Credits
- **Spent: 42.0 of 150** across 24 jobs and 84 images in three rounds:
  - Round 1: 13 slots, 21.5 credits.
  - Round 2: 8 re-rolls, 15.0 credits.
  - Round 3: 3 re-rolls, 5.5 credits.
- **Balance:** 5676.6 before and 5634.6 after. The difference matches the ledger exactly, so no one else spent on the key during the run.
- **Where everything is:** all 84 candidates are in `candidates/`, the per-job ledger is `candidates/ludo_ledger.jsonl`, and the pick table is in `fill_prompts.py`.

## Picks, and what was rejected (it shows the lookalike guards working)
| final | pick | why this one / what lost |
|---|---|---|
| candlewake_key | r2 c3 | It is Alex's "shambling mass": a tide of lilac points pouring from the wax citadel, with the Hundred-Wick in front. Round 1 mostly drew walking candles (the Litwick read). |
| candlewake_lineup | r3 c1 | All wax, no skulls. Round 1's flaming skulls read as Ghost Rider, round 2 drifted to black grim reapers, and r3 c2 had candle heads. |
| candlewake_banner | r1 c2 | The drip-cut hem and the candle ringed by flames read best at 48 px. |
| stormherd_key | r3 c3 | The herd finally reads as weather: horned storm clouds walking on rain, spiralling around the High Fold. Rounds 1 and 2 kept drawing ordinary (and Wooloo-cute) sheep. |
| stormherd_lineup | r2 c2 | All five read, including the Thunderhead chained down like a balloon. r1 c4's shadowed faces under wide hats were FF9 Black Mages; r1 c1 turned the Thunderhead into a ram-man. |
| stormherd_banner | r1 c3 | The cloud whose curls are ram horns. The plain ram heads drifted toward goat and Chaos heraldry. |
| kilnborn_key | r3 c1 | The Great Kiln, chimneys, golden sky, a column leaving the kiln mouth, and a square Kiln Walker. r2 c2 was rejected for a round pot-on-legs walker: the warrior jar coming back in through the scenery. |
| kilnborn_lineup | r1 c3 | People in tile armour with kiln tools. All four candidates avoided jar bodies. |
| kilnborn_banner | r2 c3 | Tall, with a bold kiln-arch. Round 1 was squat, and one candidate had a lone chevron that read as a "V". |
| revel_key | r2 c2 | A painted castle front on scaffolding (fortress in front, stage behind), with the Puppet leading out. r2 c4 was rejected for sign lettering over a door; round 1 was Christmas red and green, with No-Face masks on black bodies. |
| revel_lineup | r1 c1 | All five read, including the Prompter's pole of spare masks and the Puppet held up by two puppeteers. |
| revel_banner | r1 c3 | The gilt swag reads as a stage curtain; in the other two it read as blond hair. |
| vista | r2 c2 | The Halfway Mountain drawn only as outline against the Held Sun, the Sun-Nail in front, a wax candle, a chained storm and kiln smoke. r2 c1 and c3 show more unpainted land, but to a blind judge they could look like a failed render. |

No final contains lettering. I zoomed into the busiest one, the Revel facade, to check.

## Things Alex should know
1. **Every faction now holds a clear and different stance on the Wright, and none is confirmed:**
   - **Candlewake:** she died mid-stroke.
   - **Stormherd:** there never was one.
   - **Kilnborn:** she was real, they resent her, and she must never return.
   - **Revel:** "the Wright" is a role anyone could wear.

   Each stance drives the people's ending and its magic, and the mystery stays a mystery.
2. **The Candlewake rule fuses Wick and Afterglow, and adds the momentum Alex asked for.**
   - **The rule:** a flame of 0–3 on each army, +1 attack per flame, rising with each win and falling when idle; at 0 the army gutters (−2 hp a turn).
   - **Cut:** the army-deletion and split/merge edge cases are gone.
   - **For the 3D team:** the flame height on the models is the counter.
3. **The Kilnborn's warrior-jar answer is in the fiction, not just the art notes.**
   - **The fiction:** they were made as jars and broke out, so a jar shape is their taboo and "vessel" their worst insult.
   - **The names:** Jarguard became Tileguard, and the banner's bottle kiln became a kiln arch.
   - **The art:** the Kiln Walker is a square brick kiln. The art also tested this: a round walker that crept into one key candidate was rejected.
4. **The Revel are back with one hidden choice a turn, faction-wide, not one per army.**
   - **The lookalikes it was parked for:** each now has a design answer (Harlequin diamonds became tent stripes, the masks from wax faces are cut, there are no shadow bodies, no sentient mask). The dossier lists them all.
   - **The trade-off:** it is the most read-heavy faction, so playtest whether three odds lines per battle feel like strategy or noise.
5. **Art gaps a portrait pass should close:**
   - **Half-Death:** its half-alabaster, half-outline face never rendered right in 12 lineup candidates, and the final shows a hooded figure with a lilac face.
   - **The Stormherd key:** it shows the Held Sun as gold light inside the fold, not as a sun disc.
   - **Model habits:** Ludo's createImage reads prompts very literally ("wax dead with flames" gives candles with legs; "a storm flock" gives sheep). Positive anatomy did the work ("human figures with arms and legs", "storm clouds floating on columns of rain").
6. **Changes to R3 inside the dossiers:**
   - **Stormherd:** Shearing now pays on a won battle, not on land the herd doesn't own. Washout touches forts only. Thundersheep became Stormwethers, the Thunder Ram a chained storm, and the Weatherwife the Rainwife.
   - **Candlewake:** Harrow became Siphon, and Black Wick became Red Wake, so no fork deletes the faction rule.
   - **Kilnborn:** Already There became Dug In.

## Strongest faction: the Candlewake
It is the one where Alex's image, the rule, the lore and the picture are the same thing:
- **The image:** a shambling mass of the dead burning the living's warmth to stay lit.
- **The rule:** a visible flame that grows with every win (the Khorne and Lu Bu momentum) and gutters when the army stops, readable on the 3D models without a tooltip.
- **The lore:** the Wright died, so death was never finished, so the dead must keep taking warmth until they can build the ending.
- **The picture:** its key art is the strongest image in the set.

Runner-up: the Kilnborn, whose lookalike problem turned into its best lore.

## The vista prompt (exact)
Pick: `vista_r2_c2` (round 2). createImage, image_type `art`, art_style `Cel-Shaded`, aspect `16:9`, perspective `Any perspective`, 4 candidates.

```
Bright cel-shaded high fantasy strategy game concept art: thick clean dark outlines of even weight, flat saturated colours with one hard-edged shadow tone and one highlight tone, bold simple shapes and strong readable silhouettes, colourful and characterful, dark but not grim. Low warm golden-hour sunlight, long shadows. Wordless pure pictorial image. Subject: Halfmade, a fantasy world that was never finished, under a huge golden sun stuck low above the horizon. A wide landscape of green fells, winding rivers, fields and roads, lit gold. The world is unfinished toward the edges: on the right the coloured land stops in a ragged edge and continues only as glowing golden line-art outlines of hills and trees over flat bare cream ground, as if the painting was left half done. A great mountain in the distance stops halfway up and its peak continues only as glowing outline lines in the air. A waterfall pours out of a round hole in the sky. A giant golden nail as tall as a tower is driven into a hill. Small distant landmarks: a black storm cloud chained over a hill, kiln smoke, a hill of melted wax with one giant candle, striped festival tents. Gold sky deepening to violet. Wide panoramic high view.
```

Round 1 (3 candidates, not picked) used the same block with the earlier subject; it is in `prompts_r1.json`.
