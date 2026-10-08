"""Builds the prompt JSON for ludo_images.py (art round 2, Claude seat). Style blocks are verbatim, one per class."""
import json
import sys

ART = ("Bright cel-shaded high fantasy strategy game concept art: thick clean dark outlines of even weight, "
       "flat saturated colours with one hard-edged shadow tone and one highlight tone, bold simple shapes and "
       "strong readable silhouettes, colourful and characterful, dark but not grim. Low warm golden-hour "
       "sunlight, long shadows. Wordless pure pictorial image.")
CAM = " High three-quarter view from above at about 45 degrees like a strategy game camera."
PORTRAIT = ("Cel-shaded portrait of bright high fantasy: head and shoulders, three-quarter view facing left, face "
            "in the upper half of the frame, thick clean dark outline, flat saturated colours with one hard "
            "shadow tone and one highlight tone, bold simple shapes, plain softly graded deep indigo background.")

P = {}  # name -> (subject, aspect, image_type, perspective)

# ---------------- portraits ----------------
def portrait(subject):
    return (subject + " No text or lettering anywhere. " + PORTRAIT, "3:4", "asset", "Any perspective")

P["candlewake_ruler1"] = portrait(
    "Half-Death, the half-made god of the dead: a tall gaunt figure with a calm long face split down the middle. "
    "One half of the face is smooth pale white alabaster with a closed eye and a faint sad smile; the other half "
    "of the face and head is not painted at all, it is only a thin glowing lilac outline line over the dark "
    "background, as if the artist stopped halfway. Long tattered ivory robes with a soot-black collar. It holds "
    "up a brass lantern hung on a tall crook, in which burns a pale lilac flame. No hood, no skull, no scythe.")
P["candlewake_ruler2"] = portrait(
    "The Chandler, a living middle-aged woman, the only warm-skinned person among the dead: warm brown skin, tired "
    "kind eyes, a strong jaw, dark hair streaked and clotted with white wax and tied up in a knot, a smear of wax "
    "on her cheek. She wears a soot-black leather apron over an ivory linen collar with brass candle-moulding "
    "tools hanging from it. She holds up one thin taper whose small flame burns bright warm gold and lights her face.")
P["candlewake_commander"] = portrait(
    "The Lamplighter, a dead commander made of melted ivory candle wax: a sad, long, human wax face with drooping "
    "cheeks, wax drips running down his brow and chin, dark tired eyes with a faint lilac glow, and one small "
    "lilac flame burning on a black wick on top of his head. He wears a high soot-black collar and a short "
    "soot-black cape with a brass clasp and a lilac ribbon, and holds up a long lamplighter's pole with a brass "
    "hook and a lit lilac flame at its tip.")
P["kilnborn_ruler1"] = portrait(
    "The Kiln-Mothers, three very old clay women who rule as one: three wise wrinkled faces with terracotta-red "
    "skin and bright turquoise eyes, their heads close together, one in front and two behind her, all looking "
    "left, all in long cream-glazed hoods, old cracks on their cheeks mended with small copper staples. The front "
    "one holds a long wooden kiln paddle upright.")
P["kilnborn_ruler2"] = portrait(
    "The Unfired, a giant soft wet-clay person who refused the kiln: a huge, sad, gentle face of wet grey-brown "
    "clay with a glistening smooth surface, visible fingerprints and thumb dents, a heavy sagging brow, slumped "
    "drooping shoulders, clay dripping slowly from the chin and fingers, and bright turquoise eyes. It holds up "
    "one big hand cupping a small unfinished lump of wet clay shaped half like a tiny person. A rough cream cloth "
    "over the shoulders, no armour.")
P["kilnborn_commander"] = portrait(
    "The Kiln-Master, a calm stern commander, a broad-shouldered man with smooth terracotta-red skin, a sculpted "
    "human face with bright turquoise eyes, no beard, and a row of copper staples mending a crack across one "
    "cheek. He wears a glossy turquoise tile helmet and a collar and shoulders of overlapping turquoise and "
    "cream roof-shingle tile armour. He holds up a tall paddle-shaped standard with a glowing orange disc on it.")

# ---------------- fortresses ----------------
P["candlewake_fortress"] = (
    ART + " Subject: the Long Vigil, the capital fortress of the Candlewake, shown whole and alone on its own round "
    "plot of green grass with a wide empty margin of plain grass all around it. A compact citadel made entirely of "
    "ivory candle wax: a low ring wall of fused melted candle stubs, a dark arched gate in the front, four corner "
    "towers each a stepped stack of dripping candles with a small lilac flame on top, and in the centre one "
    "enormous cream candle as tall as a castle keep burning with a tall lilac flame. Pale wax pooled and dripped "
    "over the base like a melted skirt. In front of the gate is a muster ground of trampled earth where about "
    "twenty small hunched ivory wax figures with lilac flames on their heads shuffle out of the gate carrying poles "
    "topped with brass bells and lilac ribbons." + CAM, "16:9", "art", "High Angle")
P["kilnborn_fortress"] = (
    ART + " Subject: the Great Kiln, the capital fortress of the Kilnborn, shown whole and alone on its own square "
    "plot of ground with a wide empty margin of plain grass all around it. A compact fortress of red-orange brick: "
    "a square curtain wall of glazed red brick capped with turquoise roof tiles, four square corner towers with "
    "turquoise tiled pyramid roofs, a gatehouse in the front with a huge pointed arched kiln mouth glowing orange, "
    "and in the middle a stepped brick keep of square terraces roofed in glossy turquoise shingle tile, with tall "
    "square brick chimneys trailing smoke. In front of the gate is a pale cream tiled muster floor where a neat "
    "grid of about thirty small terracotta-skinned soldiers in turquoise tile armour with tall flat slab shields "
    "gathers. All shapes are square and flat, no round jars or bottles." + CAM, "16:9", "art", "High Angle")

# ---------------- dominions ----------------
BORDER = (" Subject: a wide strategy-map view of one stretch of countryside crossing a province border that runs "
          "top to bottom through the middle of the picture, marked by a line of small grey boundary stones. The same "
          "country carries on across both halves: one dirt road, one winding blue stream, a hedge along the road, "
          "three small thatched cottages in the same places, a forest edge along the top, and green fields. ")
P["candlewake_dominion"] = (
    ART + BORDER +
    "LEFT HALF: ordinary unclaimed countryside, bright green grass and fields, a green hedge, cottages with plain "
    "dark windows, green leafy trees. RIGHT HALF: the very same road, stream, hedge, cottages and forest after long "
    "rule by the Candlewake, a people of candle wax: the grass and fields have gone pale ivory under a skin of "
    "dripping candle wax; tall slim candles burning with small lilac flames stand along both sides of the road like "
    "lamp posts; a lilac flame burns in every cottage window; wax drips hang from the roofs, the hedge and the "
    "bare pale trees; rows of candle stubs with lilac flames stand in the fields. A trickle of white wax and a few "
    "lilac candle posts creep across the border onto the green left half." + CAM, "16:9", "art", "High Angle")
P["kilnborn_dominion"] = (
    ART + BORDER +
    "LEFT HALF: ordinary unclaimed countryside, bright green grass and fields, a green hedge, cottages with "
    "thatched roofs, green leafy trees. RIGHT HALF: the very same road, stream, hedge, cottages and forest after "
    "long rule by the Kilnborn, a people of fired clay: the fields have been fired into a floor of terracotta and "
    "cream square tiles with green sprigs in the joints; the road is paved with cream glazed tiles; the stream runs "
    "between banks of turquoise glazed brick; the cottages have glossy turquoise tile roofs; the hedge is a low wall "
    "capped with turquoise tiles; small square brick kilns with chimneys send up thin smoke here and there; the "
    "trees stand in neat rows. A tongue of terracotta tiles and a few turquoise-capped boundary posts creep across "
    "the border onto the green left half." + CAM, "16:9", "art", "High Angle")


# ---------------- round 2 re-rolls ----------------
P["candlewake_ruler1_r2"] = portrait(
    "Close-up portrait of Half-Death, the half-made god of the dead, a gaunt figure whose long calm face fills the "
    "upper half of the frame, split down the middle: one half of the face is smooth pale white alabaster with a "
    "closed eye and a faint sad smile; the other half of the face is not painted at all, it is empty, drawn only as "
    "a thin glowing lilac outline with the dark background showing through it, as if the artist stopped halfway. "
    "Tattered ivory robes with a soot-black collar. It holds a brass lantern with a pale lilac flame high beside "
    "its face, hung on a tall crook. No hood, no skull, no scythe, no teeth.")
P["kilnborn_ruler1_r2"] = portrait(
    "The Kiln-Mothers, three very old clay women who rule as one, shown as three different faces side by side in a "
    "row, one in front and two behind, all looking left, the faces large in the frame: warm terracotta "
    "orange-brown clay skin, not bright red, deep wrinkles, bright turquoise eyes, long cream-glazed hoods, and "
    "old cracks on their cheeks mended with small copper staples. One has a long nose, one a broad flat face, one "
    "a pointed chin. The front one holds a long wooden kiln paddle upright.")
P["kilnborn_ruler2_r2"] = portrait(
    "The Unfired, a giant person made of soft wet clay who refused the kiln: a huge, sad, gentle face of "
    "grey-brown wet clay with a glossy wet shine and bright white highlights, deep thumbprints and finger dents, a "
    "heavy sagging brow and cheeks, slumped drooping shoulders, thick drips of wet clay sliding down the chin, "
    "neck and arms, and bright turquoise eyes. One big hand held up cupping a small half-made clay figure. A rough "
    "cream cloth over the shoulders, no armour.")
CROSS = (" Subject: a wide strategy-map view of one stretch of countryside crossing a province border that runs "
         "top to bottom through the middle of the picture, marked by a line of small grey boundary stones. One "
         "dirt road and one winding blue stream both run from the left edge to the right edge of the picture and "
         "cross the border, so the same road and the same stream continue on both sides. On each side of the "
         "border stand the same three small thatched cottages with a hedge along the road, and a forest edge "
         "runs along the top. ")
P["candlewake_dominion_r2"] = (
    ART + CROSS +
    "LEFT HALF: ordinary unclaimed countryside, bright green grass and fields, a green hedge, cottages with plain "
    "dark windows, green leafy trees. RIGHT HALF: the very same road, stream, hedge, cottages and forest after long "
    "rule by the Candlewake, a people of candle wax: the ground itself is covered in a smooth skin of pale ivory "
    "candle wax, as if melted wax had been poured over the grass and fields and set hard, with a few green tufts "
    "poking through; tall slim candles burning with small lilac flames stand along both sides of the road like "
    "lamp posts; the stream runs between banks of white wax; a lilac flame burns in every cottage window and "
    "long white wax drips hang from the thatch; the hedge is a wall of dripping white wax; the trees are bare and "
    "pale ivory with wax drips; rows of small candle stubs with lilac flames stand in the pale fields. A tongue of "
    "white wax and a few lilac candles creep across the border onto the green left half." + CAM,
    "16:9", "art", "High Angle")
P["kilnborn_dominion_r2"] = (
    ART + CROSS +
    "LEFT HALF: ordinary unclaimed countryside, bright green grass and fields, a green hedge, cottages with "
    "thatched roofs, green leafy trees. RIGHT HALF: the very same road, stream, hedge, cottages and forest after "
    "long rule by the Kilnborn, a people of fired clay: the fields have been fired into a floor of terracotta and "
    "cream square tiles with green sprigs in the joints; the road is paved with cream glazed tiles; the stream runs "
    "between banks of turquoise glazed brick; the cottages have glossy turquoise tile roofs; the hedge is a low wall "
    "capped with turquoise tiles; small square brick kilns with chimneys send up thin smoke here and there; the "
    "trees stand in neat rows. A tongue of terracotta tiles and a few turquoise-capped boundary posts creep across "
    "the border onto the green left half." + CAM, "16:9", "art", "High Angle")


# ---------------- round 3 re-rolls ----------------
P["candlewake_commander_r2"] = portrait(
    "The Lamplighter, a dead commander made of melted ivory candle wax, seen in three-quarter view looking left: a "
    "long sad human face of cream-coloured wax with drooping cheeks and heavy eyelids, a fringe of wax dripping "
    "over his forehead, wax drips on his chin, dark tired eyes with a faint lilac glow, and one small lilac flame "
    "burning on a black wick on top of his head. High soot-black collar, short soot-black cape, brass clasp, lilac "
    "ribbon. He holds a long lamplighter's pole with a brass hook and a lit lilac lantern flame high on the left "
    "of the picture.")
P["candlewake_ruler2_r2"] = portrait(
    "The Chandler, a living woman of about fifty, the only warm-skinned person among the dead: warm brown skin, "
    "tired kind eyes with dark rings and deep laugh lines, a strong jaw, dark hair streaked with white wax and tied "
    "up in a knot, a smear of wax on her cheek. A soot-black leather apron over an ivory linen collar, with brass "
    "wick-trimming scissors hanging from it. She holds up a thin ivory taper whose small flame burns warm gold and "
    "lights her face.")
P["candlewake_dominion_r3"] = (
    ART + CROSS +
    "LEFT HALF: ordinary unclaimed countryside, bright green grass and fields, a green hedge, cottages with plain "
    "dark windows, green leafy trees. RIGHT HALF: the very same road, stream, hedge, cottages and forest after long "
    "rule by the Candlewake, a people of candle wax: the ground itself is covered in a thick glossy skin of cream "
    "candle wax poured over the grass and fields, with pools and ridges of wax and a few green tufts poking "
    "through; tall slim candles burning with lilac flames stand along both sides of the road like lamp posts; the "
    "stream runs between banks of white wax; every cottage has a lilac flame in its windows and long white wax "
    "drips running down its thatch; the hedge has become a wall of dripping white wax; the trees are pale ivory "
    "and dripping; rows of small candle stubs with lilac flames stand in the fields where crops were. A tongue of "
    "white wax and a few lilac candles creep across the border onto the green left half." + CAM,
    "16:9", "art", "High Angle")


# ---------------- round 4 re-rolls ----------------
P["candlewake_commander_r3"] = portrait(
    "The Lamplighter, a dead commander whose whole body is melted ivory wax, seen in three-quarter view looking "
    "left: a human head with a round skull, ears, a long nose and a sad lined face of cream wax, hair made of "
    "hardened wax drips falling to his collar, wax drips on his brow and chin, dark tired eyes with a faint lilac "
    "glow; a short black wick rises from the crown of his head with one small lilac flame. High soot-black "
    "collar, short soot-black cape, brass clasp, lilac ribbon. He holds a long lamplighter's pole topped with a "
    "brass hook and a lit lilac lantern at the left of the picture.")
P["candlewake_dominion_r4"] = (
    ART + CROSS +
    "LEFT HALF: ordinary unclaimed countryside, bright green grass and fields, a green hedge, cottages with plain "
    "dark windows, green leafy trees. RIGHT HALF: the very same road, stream, hedge, cottages and forest after long "
    "rule by the Candlewake, a people of candle wax: the ground itself is covered in a smooth skin of pale ivory "
    "candle wax, as if melted wax had been poured over the grass and fields and set hard, with a few green tufts "
    "poking through; tall slim candles burning with small lilac flames stand along both sides of the road like "
    "lamp posts; the stream runs between banks of white wax; a lilac flame burns in every cottage window and "
    "long white wax drips hang from the thatch; the hedge is a wall of dripping white wax; the trees are bare and "
    "pale ivory with wax drips; rows of small candle stubs with lilac flames stand in the pale fields. Pools of "
    "melted wax and long drips run over the stream banks and down the roofs. A tongue of white wax and a few "
    "lilac candles creep across the border onto the green left half." + CAM, "16:9", "art", "High Angle")


# ---------------- round 6 re-roll ----------------
P["candlewake_dominion_r6"] = (
    ART + CROSS +
    "LEFT HALF: ordinary unclaimed countryside, bright green grass and fields, a green hedge, cottages with plain "
    "dark windows, green leafy trees. RIGHT HALF: the very same road, stream, hedge, cottages and forest after long "
    "rule by the Candlewake, a people of candle wax: the ground itself is covered in a smooth skin of pale ivory "
    "candle wax, as if melted wax had been poured over the grass and fields and set hard, ending in a ragged edge "
    "at the border with a few green tufts poking through; tall slim candles stand along both sides of the road "
    "like lamp posts; the stream runs between banks of white wax; a flame burns in every cottage window and long "
    "white wax drips hang from the thatch; the hedge is a wall of dripping white wax; the trees are bare and pale "
    "ivory with wax drips; rows of small candle stubs stand in the pale fields. Every flame in the picture is a "
    "pale lilac-violet colour, none is orange or yellow. A tongue of white wax and a few lilac candles creep "
    "across the border onto the green left half." + CAM, "16:9", "art", "High Angle")


# ---------------- round 7 re-rolls ----------------
P["candlewake_commander_r4"] = portrait(
    "The Lamplighter, a dead commander made entirely of melted ivory wax, in three-quarter view looking left. His "
    "skin is cream-coloured glossy wax with a soft sheen. He has a human head: a round skull, ears, a long straight "
    "nose, a sad tired face with heavy-lidded eyes that glow faintly lilac, and short hair made of hardened wax "
    "strands. Long drips of wax have run down from his hairline over his temple and cheek, and down his neck onto "
    "his collar. From the crown of his head grows one short black wick burning with a small lilac flame. High "
    "soot-black collar, short soot-black cape with a brass clasp and a lilac ribbon. He holds up a long "
    "lamplighter's pole with a brass hook and a lantern with a lilac flame, at the left of the picture. His head is "
    "an ordinary human head, not a skull and not shaped like a candle.")
P["candlewake_dominion_r7"] = (
    ART + " Subject: a wide strategy-map view of countryside, as two copies of the same landscape side by side, "
    "split by a province border that runs top to bottom through the middle, marked by small grey boundary stones. "
    "Both halves have the same layout: a dirt road running left to right across the whole picture, a winding blue "
    "stream running left to right across the whole picture beside it, three small thatched cottages with a hedge "
    "behind the road, a forest edge along the top, and open fields below. LEFT HALF: ordinary green grass and "
    "fields, green hedges, plain cottages, green trees. RIGHT HALF: the same road, stream, hedge and cottages "
    "after long rule by the Candlewake, a people of candle wax: the grass and fields are covered in a smooth skin "
    "of pale ivory candle wax with a few green tufts poking through; tall slim ivory candles with pale lilac "
    "flames stand along the road like lamp posts; a pale lilac flame glows in every cottage window and long white "
    "wax drips hang from the thatch; the hedge is white and dripping; the trees are bare and ivory; rows of small "
    "candle stubs with lilac flames stand in the pale fields. Every flame in the picture is pale lilac-violet, "
    "none is orange. White wax and a few lilac candles creep across the border onto the green left half, along "
    "the road and the stream." + CAM, "16:9", "art", "High Angle")


# ---------------- round 8 re-roll ----------------
P["candlewake_dominion_r8"] = (
    ART + CROSS +
    "LEFT HALF: ordinary unclaimed countryside, bright green grass and fields, a green hedge, cottages with plain "
    "dark windows, green leafy trees; the left half has no candles and no lilac light at all. RIGHT HALF: the very "
    "same road, stream, hedge, cottages and forest after long rule by the Candlewake, a people of candle wax: the "
    "ground itself is covered in a smooth skin of pale ivory candle wax, as if melted wax had been poured over the "
    "grass and fields and set hard, with a few green tufts poking through; tall slim candles burning with small "
    "lilac flames stand along both sides of the road like lamp posts; the stream runs between banks of white wax; a "
    "lilac flame burns in every cottage window and long white wax drips hang from the thatch; the hedge is a wall "
    "of dripping white wax; the trees are bare and pale ivory with wax drips; rows of small candle stubs with "
    "lilac flames stand in the pale fields. Along the border seam only, a tongue of white wax and a few lilac "
    "candles creep across onto the green left half." + CAM, "16:9", "art", "High Angle")


# ---------------- round 9 re-rolls ----------------
P["candlewake_fortress_r2"] = (
    ART + " Subject: the Long Vigil, the capital fortress of the Candlewake, shown whole and small in the middle of "
    "the picture on its own round green mound, with a very wide margin of plain empty grass on all four sides, "
    "nothing touching the edges of the picture. A compact citadel made entirely of ivory candle wax: a low ring "
    "wall of fused melted candle stubs, a dark arched gate in the front, four corner towers each a stepped stack "
    "of dripping candles with a small lilac flame on top, and in the centre one enormous cream candle as tall as "
    "a castle keep burning with a tall lilac flame. Pale wax pooled and dripped over the base like a melted skirt. "
    "In front of the gate is a small muster ground of trampled earth where about twenty small hunched ivory wax "
    "figures with lilac flames on their heads gather in a loose crowd, the whole crowd fully inside the picture, "
    "carrying poles topped with brass bells and lilac ribbons." + CAM, "16:9", "art", "High Angle")
P["candlewake_commander_r5"] = portrait(
    "The Lamplighter, a dead commander of ivory candle wax, in three-quarter view looking left, drawn with bold "
    "flat colour shapes and thick black outlines. A gaunt human face with a long nose and a stern mouth, skin the "
    "colour of pale cream wax, a few wax drips on the cheek, dark eye sockets with glowing lilac pupils, grey wax "
    "hair swept back. On the top of his head sits a small black wick holder with one small lilac flame. High "
    "soot-black collar, short soot-black cape, brass clasp, a lilac ribbon. He holds a tall lamplighter's pole "
    "with a brass hook and a lit lilac lantern, on the left of the picture.")


# ---------------- round 10 re-roll (augment_prompt off, a more literal read) ----------------
P["candlewake_dominion_r10"] = (
    ART + CROSS +
    "The LEFT HALF is ordinary unclaimed countryside with no candles at all and no lights: bright green grass and "
    "fields, a green hedge along the road, three cottages with plain dark windows, green leafy trees. The RIGHT "
    "HALF is the very same road, stream, hedge, cottages and forest after long rule by the Candlewake, a people of "
    "candle wax: the ground itself is covered in a smooth skin of pale ivory candle wax, as if melted wax had been "
    "poured over the grass and fields and set hard, with a few green tufts poking through; tall slim candles "
    "burning with small lilac flames stand along both sides of the road like lamp posts; the stream runs between "
    "banks of white wax; a lilac flame burns in every cottage window and long white wax drips hang from the "
    "thatch; the hedge is a wall of dripping white wax; the trees are bare and pale ivory with wax drips; rows of "
    "small candle stubs with lilac flames stand in the pale fields. A tongue of white wax and a few lilac candles "
    "creep across the border onto the green left half." + CAM, "16:9", "art", "High Angle")


# ---------------- round 11 re-roll (Kilnborn fortress: muster ground outside the gate) ----------------
P["kilnborn_fortress_r2"] = (
    ART + " Subject: the Great Kiln, the capital fortress of the Kilnborn, shown whole in the middle of the picture "
    "on its own square plot of ground, with a wide margin of plain empty grass on every side, nothing cropped at the "
    "edges of the picture. A compact fortress of red-orange brick: a square curtain wall capped with turquoise roof "
    "tiles, four square corner towers with turquoise tiled pyramid roofs, a gatehouse in the front with a huge "
    "pointed arched kiln mouth glowing orange, and behind the gate a stepped brick keep of square terraces roofed in "
    "glossy turquoise shingle tile, with two tall square brick chimneys trailing smoke. In front of the gate, "
    "outside the wall, is a large pale cream tiled muster floor where a neat square grid of about thirty small "
    "terracotta-skinned soldiers in turquoise tile armour with tall flat slab shields stands in ranks. All shapes "
    "are square and flat, no round jars or bottles." + CAM, "16:9", "art", "High Angle")


def build(names, count):
    out = []
    for n in names:
        subj, aspect, itype, persp = P[n]
        c = count(n) if callable(count) else count
        out.append({"name": n, "prompt": subj, "aspect": aspect, "image_type": itype,
                    "perspective": persp, "candidates": c})
    return out


if __name__ == "__main__":
    # usage: make_prompts.py out.json name[:n] ...
    out = sys.argv[1]
    items = []
    for a in sys.argv[2:]:
        n, _, c = a.partition(":")
        items += build([n], int(c or 3))
    json.dump(items, open(out, "w"), indent=1)
    print(len(items), "entries,", sum(i["candidates"] for i in items), "images")
