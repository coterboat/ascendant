#!/usr/bin/env python3
"""asc-3d-factions: the first real 3D model batch for the Aurel Crown and the Thornmane Clans (Ludo
image to 3D). Every prompt, the order of work, the picks and the install live here; the generated
manifest is tools/ludo/batches/asc-3d-factions.json and every charged call is a line of
studio/ledgers/asc-3d-factions.jsonl.

    python3 tools/ludo/asc_3d_factions.py manifest              # (re)write the batch manifest
    python3 tools/ludo/asc_3d_factions.py cost                  # what each stage plans to spend
    python3 tools/ludo/asc_3d_factions.py run bases [--jobs 3] [--only spearmen,tuskers]
    python3 tools/ludo/asc_3d_factions.py pick <row> <k> [name] [--deshadow]  # candidate k (1..n) is the pick
    python3 tools/ludo/asc_3d_factions.py run poses             # pose edits of each picked base picture
    python3 tools/ludo/asc_3d_factions.py run models            # every picked picture to a GLB
    python3 tools/ludo/asc_3d_factions.py strip <model row>     # its 4 Ludo snapshots side by side (review)
    python3 tools/ludo/asc_3d_factions.py reroll <row> <why>    # a new take: v+1, old candidates to old/
    python3 tools/ludo/asc_3d_factions.py install <model row> [--frac F] [--yaw R] [--men M] [--hue H:part,...] [--notes T]
    python3 tools/ludo/asc_3d_factions.py board                 # fill world3d/models.json (the board's table)
    python3 tools/ludo/asc_3d_factions.py run extras|models2    # round two: ruler cheers, army extras, scenery
    python3 tools/ludo/asc_3d_factions.py sheet units|rulers|buildings   # the group's contact sheet (needs Pillow)
    python3 tools/ludo/asc_3d_factions.py account

Stages: `bases` (unit base pictures: an editImage of each unit's concept art into the 3D framing;
ruler base pictures: generateWithStyle from each ruler's portrait), `buildings` (structure
pictures, createImage), `poses` (march / strike / fallen as edits of the picked base picture, so a
unit's four poses stay one family), `models` (create3DModel of every picked picture).

Pictures roll n candidates in one call (3 for a base or a building, 2 for a pose); the pick is copied
to assets/_concept/<faction>/<name>.webp (webp q90, a pipeline input like the anchors, committed;
the folder has a .gdignore). Candidates and raw GLBs stay in gitignored candidates/ folders, and
every input goes to Ludo as base64 from a local file (Ludo URLs die after 7 days).

Discipline (studio/ludo-playbook.md): a hard credit cap checked before every submit as
`balance_before - available + planned` (holds are taken when a job is accepted); a failed job is free
but burns its request id, so a retry bumps `v`; at most --jobs jobs in flight; a rerun picks up a
job already on the server by its request id.

Install: tools/ludo/glb_slim.py --albedo-only (matte, colour map only, JPEG), a Godot .import that
embeds the texture, and a row in assets/models/models.json (assets/models/README.md has the format)
measured off the GLB: faces, extents, the courtyard of a fortress, the hue keys. `--frac` is the
reviewed share of the height (or of a lying figure's length) that is the body, read off a ruler
render, so every pose of a unit stands at the same body size; without it a measured guess stands in.
Stdlib plus ffmpeg (the full build, for WebP); `sheet` needs Pillow.
"""
import base64
import colorsys
import glob
import json
import math
import os
import shutil
import struct
import subprocess
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
import ludo  # noqa: E402  (its transport: call(), 429/5xx/OSError retries, sniff(), download())
import glb_slim  # noqa: E402

BATCH = "asc-3d-factions"
MANIFEST = os.path.join(ROOT, "tools", "ludo", "batches", BATCH + ".json")
LEDGER = os.path.join(ROOT, "studio", "ledgers", BATCH + ".jsonl")
DESCRIPTOR = os.path.join(ROOT, "assets", "models", "models.json")
PIC_CAND = "assets/_concept/candidates"   # gitignored (**/candidates/)
GLB_CAND = "assets/models/candidates"     # gitignored, with a local .gdignore
CAP = 500.0
FF = "/opt/homebrew/opt/ffmpeg-full/bin/ffmpeg" if os.path.exists("/opt/homebrew/opt/ffmpeg-full/bin/ffmpeg") else (shutil.which("ffmpeg") or "ffmpeg")

# ------------------------------------------------------------------------------------------ style
## STYLE_BIBLE §8.11 C-model, with the director's 3D figure rules (asc-3d-factions): no base (the
## game draws the team base), feet flat on the floor, A-pose with the weapon held away from the body.
C_MODEL = ("Concept picture of one game miniature for a 3D model, bright high fantasy: a single full figure standing "
           "with both feet flat on the plain floor, chunky simplified shapes and large readable forms, a bold clear "
           "silhouette, arms held a little away from the body with both hands visible, flat saturated colours with one "
           "soft shadow tone, matte painted finish, even soft studio light from the front, three-quarter view from "
           "slightly above, the whole figure centred with wide empty margin on every side and clear headroom, plain "
           "flat light grey background.")
## The same block for four-legged figures (the war bear, the Great Thornmane).
C_MODEL_BEAST = ("Concept picture of one game miniature for a 3D model, bright high fantasy: a single full four-legged "
                 "creature standing with all four feet flat on the plain floor, chunky simplified shapes and large "
                 "readable forms, a bold clear silhouette, all four legs clearly visible and apart, flat saturated "
                 "colours with one soft shadow tone, matte painted finish, even soft studio light from the front, "
                 "three-quarter view from slightly above, the whole creature centred with wide empty margin on every "
                 "side and clear headroom, plain flat light grey background.")
## STYLE_BIBLE §8.11 C-pose (an edit of the base picture), with "same round base" taken out.
C_POSE = ("The same figure, now {pose}. Same outfit, same colours, same outline style, {view}, the whole figure with "
          "wide empty margin on every side, plain flat light grey background.")
VIEW = "three-quarter view from slightly above"
VIEW_LYING = "seen from the side and a little above, the whole figure lying full length"
## STYLE_BIBLE §8.11 C-structure, verbatim.
C_STRUCTURE = ("Concept picture of one tabletop terrain model for a 3D model, bright high fantasy: a single building "
               "standing on its own with its walls meeting the floor, chunky simplified shapes, a bold clear silhouette, "
               "flat saturated colours with one soft shadow tone, matte painted finish, even soft studio light, "
               "three-quarter view from a little above, the whole building centred with clear space on every side, "
               "plain flat light grey background.")

# ------------------------------------------------------------------------------------------ units
## id: faction, concept, class, body height (men), faces, texture (px after slimming), who, outfit,
## the base pose, the three other poses. A pose is a plain line (C-pose); "lying" poses get VIEW_LYING.
UNITS = {
    "spearmen": dict(
        faction="kingdom", cls="infantry", body=1.0, faces=5000, tex=512, beast=False,
        who="Aurel Crown spearman",
        outfit="open steel helm with a blue plume, blue tabard with gold trim over mail, brown belt and boots, and the "
               "round steel shield",
        base="standing in a relaxed A-pose with his feet apart, his right arm held out from his side gripping the spear "
             "upright at arm's length with clear space between the spear and his body, the round shield on his left "
             "forearm held a little out from his side, calm steady expression, eyes ahead",
        march="marching forward with his left leg striding ahead, the spear sloped back over his right shoulder in his "
              "right hand, the round shield on his left arm, eyes ahead",
        strike="lunging forward on his bent left leg, thrusting the spear straight ahead at waist height with his right "
               "arm fully extended, the round shield raised on his left arm, a fierce shout",
        fallen="fallen in battle, lying flat on his back on the floor with his arms out to the sides, his helmet still "
               "on, the spear and the round shield lying on the floor beside him, eyes closed"),
    "crossbowmen": dict(
        faction="kingdom", cls="ranged", body=0.95, faces=5000, tex=512, beast=False,
        who="Aurel Crown crossbow soldier",
        outfit="brimmed steel kettle hat, braided grey hair, blue and white gambeson with gold trim and a steel shoulder "
               "plate, brown gloves and boots, the quiver of bolts at her hip, and the wooden crossbow",
        base="standing in a relaxed A-pose with her feet apart, holding the crossbow by its stock in her right hand, held "
             "low and out to her side with clear space between the crossbow and her legs, her left arm held a little "
             "out from her side, calm alert expression, eyes ahead",
        ## v2 of march and strike: v1 turned the crossbow into a longbow (4 of 4 candidates)
        march="walking forward with her left leg striding ahead, carrying the same crossbow, a short steel bow fixed "
              "crossways on the front end of a wooden stock, resting on her right shoulder with the stock in her right "
              "hand, her left arm swinging, eyes ahead",
        strike="aiming the same crossbow straight ahead at shoulder height, a short steel bow fixed crossways on the "
               "front end of a wooden stock, the stock held level in both hands against her right cheek, her feet "
               "planted apart, focused expression",
        fallen="fallen in battle, lying flat on her back on the floor with her arms out to the sides, her kettle hat "
               "still on, the crossbow lying on the floor beside her, eyes closed"),
    "knights": dict(
        faction="kingdom", cls="mounted", body=1.45, faces=8000, tex=512, beast=True,
        who="Aurel Crown knight on his white warhorse",
        outfit="full steel plate with gold trim and a closed great helm, the long lance, and the white horse in its "
               "blue and white caparison with gold trim",
        base="the horse standing still on all four legs, the knight sitting upright in the saddle holding the long lance "
             "straight up in his right hand, held out a little from the horse's side with clear space around it, his "
             "left hand on the reins, the horse's head raised, all four legs visible",
        march="the horse walking forward at a steady pace with its right foreleg raised, the knight upright in the saddle "
              "holding the lance straight up in his right hand",
        strike="the horse charging forward at a gallop with its forelegs reaching ahead, the knight leaning into the "
               "charge with the long lance lowered level and pointing straight ahead",
        fallen="the horse collapsed onto its belly with its legs folded under it and its head low, the knight slumped "
               "forward over its neck, the lance lying on the floor beside them, eyes closed"),
    "knight_captain": dict(
        faction="kingdom", cls="commander", body=1.1, faces=6000, tex=1024, beast=False,
        who="Aurel Crown knight-captain",
        outfit="short dark beard, polished steel plate with gold filigree and a gold sun badge on the shoulder, the long "
               "royal-blue cloak, and the longsword",
        base="standing in a relaxed A-pose with his feet apart, holding the longsword point-down in his right hand, held "
             "out to his side with clear space between the sword and his body, his left arm held a little out from his "
             "side, the blue cloak hanging behind him, confident stern expression, eyes ahead",
        march="striding forward with his left leg ahead, the longsword resting on his right shoulder, his left hand "
              "raised forward as if leading his troops, the blue cloak flowing behind him",
        strike="swinging the longsword in a big two-handed diagonal slash, lunging forward on his bent left leg, the "
               "sword raised high above his right shoulder, the blue cloak flaring, a battle cry",
        fallen="fallen in battle, lying flat on his back on the floor with his arms out to the sides, the blue cloak "
               "spread under him, the longsword lying on the floor beside him, eyes closed"),
    "tuskers": dict(
        faction="beasts", cls="heavy infantry", body=1.2, faces=6000, tex=512, beast=False,
        who="Thornmane tusker, a hulking boar-headed beastman",
        outfit="long curved tusks, tawny fur with crimson war paint, moss-green leather harness with bone plates and "
               "spiked shoulder guards, and the spiked stone-headed club",
        base="standing in a relaxed A-pose with his hoofed feet apart, gripping the stone club in his right hand, held low "
             "and out to his side with clear space between the club and his body, his left arm held a little out from "
             "his side, fierce snarling expression, eyes ahead",
        march="stomping forward with his left leg ahead, the stone club resting on his right shoulder, his left fist "
              "swinging, eyes ahead",
        strike="smashing down with the stone club held high over his head in both hands, leaning forward, mouth open in "
               "a roar",
        fallen="fallen in battle, lying flat on his back on the floor with his arms out to the sides, the stone club "
               "lying on the floor beside him, eyes closed"),
    "fangthrowers": dict(
        faction="beasts", cls="ranged", body=1.05, faces=5000, tex=512, beast=False,
        who="Thornmane fangthrower, a lean grey wolf-headed beastman",
        outfit="crimson war paint over the eyes, moss-green leather wraps and a bone necklace, a bundle of javelins on "
               "his back, and the long javelin",
        base="standing in a relaxed A-pose with his feet apart, holding one long javelin upright in his right hand at "
             "arm's length out to his side with clear space between the javelin and his body, his left arm held a "
             "little out from his side, alert expression, eyes ahead",
        march="loping forward with his left leg ahead, the javelin sloped over his right shoulder in his right hand, "
              "eyes ahead",
        strike="throwing a javelin: his right arm drawn back high behind his head holding the javelin level, ready to "
               "throw, his left arm pointing straight ahead, his left leg stepping forward, eyes on the target ahead",
        fallen="fallen in battle, lying flat on his back on the floor with his arms out to the sides, the javelins "
               "lying on the floor beside him, eyes closed"),
    "war_bear": dict(
        faction="beasts", cls="beast", body=1.3, faces=8000, tex=512, beast=True,
        ## v2 of the whole family: the v1 moss blanket (many small green tufts) came back from image-to-3D
        ## as a camouflage-like smear three times (ready v1, ready v2 near-black, march v1), so the
        ## picture is simplified into big flat areas of colour
        who="Thornmane war bear, a huge brown bear",
        outfit="thick smooth warm brown fur painted in large flat areas of colour, a simple saddle blanket of plain "
               "moss-green felt across its back held by two leather straps, two big bone shoulder plates, and three "
               "crimson war-paint stripes on its face",
        base="standing on all four legs in a calm, steady stance, its head raised and looking ahead, all four legs "
             "visible and apart",
        march="lumbering forward with its right forepaw raised mid-step, head low and looking ahead",
        strike="rearing up on its hind legs with both forepaws raised high and claws out, its mouth wide open in a roar",
        fallen="lying on its side on the floor with its legs limp and its eyes closed"),
    "warchief": dict(
        faction="beasts", cls="commander", body=1.3, faces=6000, tex=1024, beast=False,
        who="Thornmane warchief, a lion-headed beastman",
        outfit="a great orange mane, crimson war paint, a moss-green cloak with bone spikes, a leather and bone harness, "
               "and the tall staff topped with a horned skull totem",
        base="standing in a relaxed A-pose with his feet apart, holding the skull totem staff upright in his right hand at "
             "arm's length out to his side with clear space between the staff and his body, his left arm held a little "
             "out from his side, proud fierce expression, eyes ahead",
        march="striding forward with his left leg ahead, the skull totem staff held upright in his right hand, his left "
              "arm raised forward as if leading his warband, eyes ahead",
        strike="swinging the skull totem staff down in a mighty two-handed overhead blow, leaning forward, mouth open in "
               "a roar, the green cloak flaring",
        fallen="fallen in battle, lying flat on his back on the floor with his arms out to the sides, the green cloak "
               "spread under him, the skull totem staff lying on the floor beside him, eyes closed"),
}
LYING = {"fallen"}
POSES = ("ready", "march", "strike", "fallen")
RULER_POSES = POSES + ("cheer",)

## Rulers: generateWithStyle from each ruler's portrait (the series look and the face), the subject
## as a full figure. Poses as edits of the picked base, like the units.
RULERS = {
    "aurel_king": dict(
        faction="kingdom", cls="ruler", body=1.25, faces=10000, tex=1024, beast=False,
        portrait="assets/portraits/rulers/aurel_king.webp", name="King Corvane",
        subject="King Corvane of the Aurel Crown, a broad-shouldered heroic human king in his forties with a short dark "
                "beard touched with grey, a gold crown set with one blue gem, polished steel plate armour with gold "
                "trim, a royal-blue mantle with a white fur collar and a gold crown-and-sun clasp hanging to his calves, "
                "steel greaves and boots, standing in a relaxed A-pose with his feet apart, holding a longsword with a "
                "gilded hilt point-down in his right hand, held out to his side with clear space between the sword and "
                "his body, his left arm held a little out from his side, calm resolute expression, eyes ahead",
        march="striding forward with his left leg ahead, the longsword resting on his right shoulder, his left hand "
              "raised forward, the blue mantle flowing behind him",
        strike="swinging the longsword in a mighty two-handed diagonal slash, lunging forward on his bent left leg, the "
               "sword raised high above his right shoulder, the blue mantle flaring, a battle cry",
        ## v2: the v1 mantle spread under him came back from image-to-3D as a flat slab with a black
        ## underside, twice
        fallen="fallen in battle, lying flat on his back on the floor with his arms out to the sides, his crown still "
               "on, the blue mantle wrapped closely around his legs, the longsword lying on the floor beside him, "
               "eyes closed"),
    "ever_regent": dict(
        faction="kingdom", cls="ruler (caster)", body=1.25, faces=10000, tex=1024, beast=False,
        portrait="assets/portraits/rulers/ever_regent.webp", name="the Ever-Regent",
        subject="The Ever-Regent of the Aurel Crown, a tall ageless archmage with a gaunt pale face, a long silver beard "
                "and softly glowing pale gold eyes, a tall high-collared floor-length robe of white and royal blue "
                "embroidered with gold suns, standing in a relaxed A-pose with his feet apart, holding a tall staff "
                "topped with a radiant golden sunstone upright in his right hand at arm's length out to his side, with "
                "clear space between the staff and his body, his left hand open and held a little out from his side, "
                "serene distant expression, eyes ahead",
        march="walking forward with measured steps, the sunstone staff planted ahead of him in his right hand like a "
              "walking staff, his robe trailing behind",
        strike="casting a spell: the sunstone staff raised high overhead in his right hand with the sunstone blazing "
               "golden light, his left palm thrust forward, his robe billowing",
        fallen="fallen, lying flat on his back on the floor with his arms out to the sides, his robe spread around him, "
               "the staff lying on the floor beside him with its sunstone dimmed, eyes closed"),
    "thornmane_avatar": dict(
        faction="beasts", cls="ruler (monster)", body=2.8, faces=12000, tex=1024, beast=True,
        portrait="assets/portraits/rulers/thornmane_avatar.webp", name="the Great Thornmane",
        subject="The Great Thornmane, beast-god of the Thornmane Clans, a colossal primal lion-like beast standing on "
                "four mighty legs, a broad heavy-jawed lion head with a great mane of twisting green briars and thorny "
                "vines dotted with small pale blossoms, tawny fur mottled with moss, two curling antlers of dark thorny "
                "wood, crimson war-paint marks on its brow, softly glowing jade-green eyes, thorny briars wound around "
                "its legs, a long tail ending in a tuft of leaves, its head raised, calm ancient fearsome expression, "
                "all four legs visible and apart",
        march="prowling forward with its right foreleg raised mid-stride, its head low and level, looking ahead",
        strike="rearing up on its hind legs with its forepaws raised high and claws out, its jaws wide open in a roar, "
               "its briar mane flaring",
        fallen="lying on its side on the floor with its legs limp and its eyes closed, its briar mane spread on the floor"),
    "fang_chieftain": dict(
        faction="beasts", cls="ruler", body=1.4, faces=10000, tex=1024, beast=False,
        portrait="assets/portraits/rulers/fang_chieftain.webp", name="the Ninth Fang",
        subject="The Ninth Fang, high chieftain of the Thornmane Clans, a tall grizzled black-furred wolf-headed beastman "
                "with a scarred muzzle streaked with white, a circlet of nine long bone fangs on his brow, crimson war "
                "paint across the eyes, a heavy cloak of grey wolf pelts over moss-green leather and bone armour, "
                "standing in a relaxed A-pose with his clawed feet apart, holding a broad bone-hilted greatblade "
                "point-down in his right hand, held out to his side with clear space between the blade and his body, "
                "his left arm held a little out from his side, fierce proud expression, eyes ahead",
        march="striding forward with his left leg ahead, the greatblade resting on his right shoulder, the wolf-pelt "
              "cloak flowing behind him",
        strike="swinging the greatblade in a huge two-handed horizontal sweep, lunging forward, teeth bared in a snarl, "
               "the wolf-pelt cloak flaring",
        fallen="fallen in battle, lying flat on his back on the floor with his arms out to the sides, the wolf-pelt "
               "cloak spread under him, the greatblade lying on the floor beside him, eyes closed"),
}

# -------------------------------------------------------------------------------------- buildings
## kind_variant: subject (after the C-structure block), faces, texture, width in men (the widest
## side), the hue keys to repaint in the owner's colour (measured at install), n candidates,
## variants picked from the candidates (a village keeps 2 of its 3).
BUILDINGS = {
    "fortress_beasts": dict(
        faction="beasts", faces=24000, tex=1024, men=12.0, n=3, keys=["banners"],
        subject="Fangridge, the war stronghold of the Thornmane Clans, a square fort on a low flat earthen mound: four "
                "walls of tall sharpened log palisade bound with rope, giant curved bone tusks set along the walls, four "
                "timber lookout towers with thatched roofs at the corners, a wide open gate of heavy logs framed by two "
                "huge curved tusks in the middle of the front wall, a large open bare-earth muster yard filling the "
                "inside of the walls, one long thatched longhouse with crossed horn gables against the back wall, "
                "crimson banners with a horned beast-skull emblem on the towers"),
    "fortress_kingdom": dict(
        faction="kingdom", faces=24000, tex=1024, men=12.0, n=3, keys=["roofs", "banners"],
        subject="Crownkeep, the royal fortress of the Aurel Crown, on a square of flat grass: a square curtain wall of "
                "pale cream stone with crenellations, four stout round corner towers with royal-blue conical roofs and "
                "gold finials, a large arched gatehouse with two small towers in the middle of the front wall with its "
                "gate open, a tall square keep with a royal-blue roof and a golden sun ornament built into the middle of "
                "the back wall, a large open grassy courtyard filling the space between the gate and the keep, blue "
                "banners with a gold crown hanging on the walls"),
    "fort_kingdom": dict(
        faction="kingdom", faces=14000, tex=1024, men=7.0, n=3, keys=["roofs", "banners"],
        subject="A small Aurel Crown border fort on a square of flat grass: a square curtain wall of grey and cream stone "
                "with crenellations, two round towers with royal-blue conical roofs at the back corners, a square "
                "gatehouse with an open arched gate in the middle of the front wall, an open grassy yard inside the "
                "walls, one blue banner with a gold crown over the gate"),
    "fort_beasts": dict(
        faction="beasts", faces=14000, tex=1024, men=7.0, n=3, keys=["banners"],
        subject="A small Thornmane Clans war fort on a patch of flat bare earth: a square ring of sharpened log palisade "
                "with curved bone tusks lashed to it, a wide open log gate framed by two curved tusks in the middle of "
                "the front wall, one timber lookout platform with a thatched roof at a back corner, an open bare-earth "
                "yard inside the walls, a crimson banner with a horned skull over the gate"),
    "village_plains": dict(
        faction=None, faces=8000, tex=512, men=4.5, n=3, keys=[], variants=2,
        subject="A small farmstead on a patch of green grass: a white-washed timber-framed cottage with a golden thatched "
                "roof and a brick chimney, a red timber barn, a round haystack and a short wooden fence"),
    "village_forest": dict(
        faction=None, faces=8000, tex=512, men=4.5, n=3, keys=[], variants=2,
        subject="A forest hamlet on a patch of mossy ground: two dark timber log lodges with steep green-shingled roofs "
                "and stone chimneys, a woodpile and a sawn tree stump with an axe in it"),
    "village_hills": dict(
        faction=None, faces=8000, tex=512, men=4.5, n=3, keys=[], variants=2,
        subject="A hill mining hamlet on a patch of rocky ground: a low grey stone cottage with a slate roof, a timber "
                "mine entrance dug into a small rocky mound, a wooden mine cart full of ore on short rails, a stack of "
                "timber props"),
    "mill": dict(
        faction=None, faces=8000, tex=512, men=4.0, n=3, keys=[],
        subject="A windmill on a patch of green grass: a white-washed round stone tower with a dark thatched cap, four "
                "large lattice sails with canvas, a little wooden door and a sack of flour beside it"),
    "watchtower": dict(
        faction=None, faces=8000, tex=512, men=3.0, n=3, keys=[],
        subject="A tall watchtower on a patch of green grass: a square grey stone base, a wooden upper platform with a "
                "pointed shingled roof and an iron beacon brazier, a wooden ladder up the side"),
    "camp_kingdom": dict(
        faction="kingdom", faces=6000, tex=512, men=5.0, n=3, keys=["tents"],
        subject="An Aurel Crown war camp on a patch of green grass: three white and royal-blue striped canvas pavilion "
                "tents with gold pennant tops, a campfire with a cooking pot on a tripod, a wooden rack of spears"),
    "camp_beasts": dict(
        faction="beasts", faces=6000, tex=512, men=5.0, n=3, keys=["banners"],
        subject="A Thornmane Clans war camp on a patch of bare earth: three round tents of stitched hides on bone and "
                "timber poles with antler tops, a campfire ringed by stones with a spit over it, a crimson totem banner "
                "with a horned skull"),
}

## Round two (budget allowing, 3D_DIRECTION §6.2 and §9.3): the rulers' fifth pose, the army extras
## and the instanced scenery.
## The rulers' victory pose (§9.3: "rulers: 5, adding cheer"), an edit of the ready picture like the rest.
CHEER = {
    "aurel_king": "cheering in victory, standing tall with the longsword raised high above his head in his right hand, "
                  "his left fist raised, his mouth open in a cheer",
    "ever_regent": "standing tall in triumph, the sunstone staff raised high above his head in his right hand with the "
                   "sunstone shining, his left hand open at his side, a calm smile",
    ## v2: v1 stood the beast up on its hind legs like a man (2 of 2)
    "thornmane_avatar": "in the same four-legged stance as before with all four paws planted on the floor, its head "
                        "raised high and thrown back in a triumphant roar, its briar mane flaring",
    "fang_chieftain": "raising the greatblade high above his head in his right hand, his head thrown back in a "
                      "triumphant howl",
}
## Army extras (§6.2): a standard bearer (the game hangs the army's code banner, in the owner's colour,
## from the crossbar) and a musician per faction, edits of a picked unit picture of the same faction
## so they stay in the series. id: faction, the source pick, the edit line, body height, faces.
EXTRAS = {
    "standard_bearer_kingdom": dict(
        faction="kingdom", extra="standard_bearer", src="spearmen_ready", body=1.0, faces=5000, tex=512,
        line="an Aurel Crown standard bearer in the same open steel helm with a blue plume and the same blue tabard "
             "with gold trim over mail, standing in a relaxed A-pose with his feet apart, holding upright in both hands "
             "a tall bare wooden banner pole with a short horizontal crossbar at the top and a small gold crown "
             "finial, the pole held a little out from his body, his round shield on his back, eyes ahead"),
    "musician_kingdom": dict(
        faction="kingdom", extra="musician", src="spearmen_ready", body=0.95, faces=5000, tex=512,
        line="a young Aurel Crown drummer in the same open steel helm with a blue plume and the same blue tabard with "
             "gold trim, standing in a relaxed A-pose with his feet apart, a round blue and gold side drum hanging at "
             "his left hip on a white strap, a wooden drumstick held in each hand above the drumhead, eyes ahead"),
    "standard_bearer_beasts": dict(
        faction="beasts", extra="standard_bearer", src="fangthrowers_ready", body=1.05, faces=5000, tex=512,
        line="a Thornmane standard bearer, the same lean grey wolf-headed beastman with the same crimson war paint and "
             "moss-green leather wraps, standing in a relaxed A-pose with his feet apart, holding upright in both hands "
             "a tall bare wooden banner pole with a short horizontal crossbar at the top and a small horned skull "
             "on its tip, the pole held a little out from his body, eyes ahead"),
    "musician_beasts": dict(
        faction="beasts", extra="musician", src="tuskers_ready", body=1.2, faces=6000, tex=512,
        line="a Thornmane war-horn blower, the same hulking boar-headed beastman with the same tusks, crimson war "
             "paint and moss-green harness with bone plates, standing in a relaxed A-pose with his hoofed feet apart, "
             "blowing a huge curved bone war horn held up to his mouth in both hands, the horn's bell pointing up "
             "and forward, eyes ahead"),
}
## Instanced scenery (bible §8.4: tree, rock at 2,000 faces), a C-prop block (C-structure reworded
## for a piece that isn't a building).
C_PROP = ("Concept picture of one tabletop scenery piece for a 3D model, bright high fantasy: a single piece standing on "
          "its own on the plain floor, chunky simplified shapes, a bold clear silhouette, flat saturated colours with "
          "one soft shadow tone, matte painted finish, even soft studio light, three-quarter view from a little above, "
          "the whole piece centred with clear space on every side, plain flat light grey background.")
PROPS = {
    ## faces 3,000 on the v2 model: at 2,000 the leaf clumps came back as loose shards with the trunk lost
    "tree_broadleaf": dict(men=3.0, axis="height", faces=3000, tex=512, n=3,
                           subject="one broadleaf oak tree with a bold rounded canopy of three big leafy clumps in "
                                   "bright green, a short sturdy brown trunk, its roots meeting the floor"),
    "tree_pine": dict(men=3.5, axis="height", faces=2000, tex=512, n=3,
                      subject="one tall pine tree made of four stacked cone-shaped tiers of deep green needles on a "
                              "short brown trunk, its roots meeting the floor"),
    "rocks": dict(men=1.5, axis="width", faces=2000, tex=512, n=3,
                  subject="a cluster of three chunky grey boulders of different sizes with a few patches of green "
                          "moss, sitting on the floor"),
    "standing_stones": dict(men=5.0, axis="width", faces=4000, tex=512, n=3,
                            subject="a ring of six tall ancient grey standing stones with patches of moss and faint "
                                    "carved spirals, one flat altar stone in the middle, on a round patch of grass"),
}

## Concept edits are fed from a light grey flattening of the cut-out concept (scratch, regenerated).
INPUTS = os.path.join(ROOT, "assets", "_concept", "candidates", "_inputs")


# --------------------------------------------------------------------------------------- manifest
def concept(unit):
    return "assets/concept/units/%s.webp" % unit


def pick_path(faction, name):
    return "assets/_concept/%s/%s.webp" % (faction or "world", name)


def rows():
    """Every row of the batch in run order. A picture row rolls `n` candidates; a model row reads
    its picture's pick (`from_file`)."""
    out = []
    for uid, u in UNITS.items():
        block = C_MODEL_BEAST if u["beast"] else C_MODEL
        out.append({"id": "pic_%s_ready" % uid, "stage": "bases", "kind": "edit", "n": 3,
                    "from_file": os.path.relpath(os.path.join(INPUTS, uid + ".png"), ROOT),
                    "prompt": "%s Subject: the same %s as in this picture, with the same face, %s, the same colours "
                              "and the same thick clean outline, now %s." % (block, u["who"], u["outfit"], u["base"]),
                    "pick_to": pick_path(u["faction"], uid + "_ready"), "group": "units", "unit": uid, "pose": "ready"})
    for rid, r in RULERS.items():
        block = C_MODEL_BEAST if r["beast"] else C_MODEL
        out.append({"id": "pic_%s_ready" % rid, "stage": "bases", "kind": "styled", "n": 3,
                    "style_file": r["portrait"], "prompt": "%s Subject: %s." % (block, r["subject"]),
                    "pick_to": pick_path(r["faction"], rid + "_ready"), "group": "rulers", "unit": rid, "pose": "ready"})
    for bid, b in BUILDINGS.items():
        out.append({"id": "pic_" + bid, "stage": "buildings", "kind": "image", "n": b["n"],
                    "prompt": "%s Subject: %s." % (C_STRUCTURE, b["subject"]),
                    "pick_to": pick_path(b["faction"], bid), "group": "buildings", "unit": bid,
                    "variants": b.get("variants", 1)})
    for table, group in ((UNITS, "units"), (RULERS, "rulers")):
        for uid, u in table.items():
            for pose in POSES[1:]:
                view = VIEW_LYING if pose in LYING else VIEW
                out.append({"id": "pic_%s_%s" % (uid, pose), "stage": "poses", "kind": "edit", "n": 2,
                            "from_file": pick_path(u["faction"], uid + "_ready"),
                            "prompt": C_POSE.format(pose=u[pose], view=view),
                            "pick_to": pick_path(u["faction"], "%s_%s" % (uid, pose)), "group": group, "unit": uid,
                            "pose": pose})
    ## models: the board's most-seen first (fortresses, every ready pose, strike, march, fallen), then the kit
    order = []
    for bid in ("fortress_beasts", "fortress_kingdom", "fort_kingdom", "fort_beasts"):
        order.append(("buildings", bid, None, None))
    for pose in POSES:
        for uid in list(UNITS) + list(RULERS):
            order.append(("units" if uid in UNITS else "rulers", uid, pose, None))
    for bid, b in BUILDINGS.items():
        if bid.startswith(("fortress", "fort_")):
            continue
        for v in range(b.get("variants", 1)):
            order.append(("buildings", bid, None, "ab"[v] if b.get("variants", 1) > 1 else None))
    for group, uid, pose, var in order:
        if group == "buildings":
            b = BUILDINGS[uid]
            name = uid + ("_" + var if var else "")
            src = pick_path(b["faction"], name)
            faces, tex = b["faces"], b["tex"]
            target = "assets/models/buildings/%s.glb" % name
        else:
            u = (UNITS if group == "units" else RULERS)[uid]
            name = "%s_%s" % (uid, pose)
            src = pick_path(u["faction"], name)
            faces, tex = u["faces"], u["tex"]
            target = ("assets/models/units/%s/%s.glb" % (u["faction"], name) if group == "units"
                      else "assets/models/rulers/%s.glb" % name)
        out.append({"id": "model_" + name, "stage": "models", "kind": "model3d", "from_file": src, "faces": faces,
                    "texture_size": 1024, "texture_type": "pbr", "slim_max": tex, "target": target, "group": group,
                    "unit": uid, "pose": pose, "variant": var})
    out += rows_round2()
    return out


def rows_round2():
    """Round two: ruler cheers, army extras, scenery (pictures in stage `extras`, models in `models2`)."""
    out = []
    for rid, line in CHEER.items():
        r = RULERS[rid]
        out.append({"id": "pic_%s_cheer" % rid, "stage": "extras", "kind": "edit", "n": 2,
                    "from_file": pick_path(r["faction"], rid + "_ready"), "prompt": C_POSE.format(pose=line, view=VIEW),
                    "pick_to": pick_path(r["faction"], rid + "_cheer"), "group": "rulers", "unit": rid, "pose": "cheer"})
    for xid, x in EXTRAS.items():
        out.append({"id": "pic_" + xid, "stage": "extras", "kind": "edit", "n": 3,
                    "from_file": pick_path(x["faction"], x["src"]),
                    "prompt": "%s Subject: in the same style, colours and thick clean outline as this picture, %s." % (
                        C_MODEL, x["line"]),
                    "pick_to": pick_path(x["faction"], xid), "group": "extras", "unit": xid})
    for pid, pr in PROPS.items():
        out.append({"id": "pic_" + pid, "stage": "extras", "kind": "image", "n": pr["n"],
                    "prompt": "%s Subject: %s." % (C_PROP, pr["subject"]), "pick_to": pick_path(None, pid),
                    "group": "props", "unit": pid})
    for rid, r in RULERS.items():
        out.append({"id": "model_%s_cheer" % rid, "stage": "models2", "kind": "model3d",
                    "from_file": pick_path(r["faction"], rid + "_cheer"), "faces": r["faces"], "texture_size": 1024,
                    "texture_type": "pbr", "slim_max": r["tex"], "target": "assets/models/rulers/%s_cheer.glb" % rid,
                    "group": "rulers", "unit": rid, "pose": "cheer", "variant": None})
    for xid, x in EXTRAS.items():
        out.append({"id": "model_" + xid, "stage": "models2", "kind": "model3d", "from_file": pick_path(x["faction"], xid),
                    "faces": x["faces"], "texture_size": 1024, "texture_type": "pbr", "slim_max": x["tex"],
                    "target": "assets/models/units/%s/%s.glb" % (x["faction"], x["extra"]), "group": "extras",
                    "unit": xid, "pose": None, "variant": x["faction"]})
    for pid, pr in PROPS.items():
        out.append({"id": "model_" + pid, "stage": "models2", "kind": "model3d", "from_file": pick_path(None, pid),
                    "faces": pr["faces"], "texture_size": 1024, "texture_type": "pbr", "slim_max": pr["tex"],
                    "target": "assets/models/props/%s.glb" % pid, "group": "props", "unit": pid, "pose": None,
                    "variant": None})
    return out


def load_state():
    if os.path.exists(MANIFEST):
        return json.load(open(MANIFEST)).get("state", {})
    return {}


def write_manifest(state=None):
    if state is None:
        state = load_state()
    state.setdefault("balance_before", None)
    state.setdefault("v", {})
    state.setdefault("picks", {})
    man = {
        "batch": BATCH, "rid_prefix": "asc3d", "cap": CAP,
        "note": "Written by tools/ludo/asc_3d_factions.py (which holds the prompts; edit it, not this file). The "
                "first real 3D batch for the Aurel Crown (kingdom) and the Thornmane Clans (beasts): 8 unit types x 4 "
                "poses, 4 rulers x 4 poses, fortresses, forts and a world kit. Picture rows roll n candidates in one "
                "call; picks are copied to assets/_concept/<faction>/; model rows read the pick as base64. Rows also "
                "run through ludo.py's kinds (edit / styled / image / model3d) one candidate at a time.",
        "style": {"image": "", "art_style": "Cel-Shaded",
                  "blocks": {"C-model (3D, no base)": C_MODEL, "C-model-beast (3D, no base)": C_MODEL_BEAST,
                             "C-pose (no base)": C_POSE, "C-structure": C_STRUCTURE}},
        "state": state,
        "assets": [],
    }
    for r in rows():
        a = dict(r)
        a["v"] = state["v"].get(r["id"], 1)
        if r["id"] in state["picks"]:
            a["pick"] = state["picks"][r["id"]]
        if a["kind"] == "image":
            a.update({"type": "asset", "art_style": "Cel-Shaded", "style": False, "augment": False,
                      "perspective": "High Angle", "aspect": "ar_1_1"})
        elif a["kind"] in ("edit", "styled"):
            a["augment"] = False
        if a["kind"] == "model3d":
            a["out"] = GLB_CAND + "/" + r["id"][len("model_"):]
        else:
            a["out"] = PIC_CAND + "/" + r["id"][len("pic_"):]
        man["assets"].append(a)
    os.makedirs(os.path.dirname(MANIFEST), exist_ok=True)
    with open(MANIFEST, "w") as f:
        json.dump(man, f, indent=1)
        f.write("\n")
    return man


def save_state(state):
    """Merged with what is on disk, so two runs (pictures and models) can share the manifest: picks
    are a union (this run's win), versions the higher of the two."""
    import fcntl
    with open(MANIFEST + ".lock", "w") as lk:
        fcntl.flock(lk, fcntl.LOCK_EX)
        disk = load_state()
        for k, v in disk.get("v", {}).items():
            state.setdefault("v", {})[k] = max(v, state["v"].get(k, 1))
        for k, v in disk.get("picks", {}).items():
            state.setdefault("picks", {}).setdefault(k, v)
        for k, v in disk.get("rerolls", {}).items():
            if len(v) > len(state.setdefault("rerolls", {}).get(k, [])):
                state["rerolls"][k] = v
        if state.get("balance_before") is None:
            state["balance_before"] = disk.get("balance_before")
        write_manifest(state)


# ------------------------------------------------------------------------------------------ inputs
def make_inputs():
    """Each unit's cut-out concept flattened on light grey and padded to a 1024 square (the figure
    about 80% tall), so the edit has room for the A-pose and returns a plain grey ground."""
    os.makedirs(INPUTS, exist_ok=True)
    for uid in UNITS:
        dst = os.path.join(INPUTS, uid + ".png")
        if os.path.exists(dst):
            continue
        src = os.path.join(ROOT, concept(uid))
        ## alpha-composite the cut-out over a light grey canvas
        subprocess.run([FF, "-y", "-loglevel", "error", "-f", "lavfi", "-i", "color=c=0xD4D4D4:s=1024x1024",
                        "-i", src, "-filter_complex",
                        "[1]scale=820:820:force_original_aspect_ratio=decrease[f];[0][f]overlay=(W-w)/2:(H-h)/2:format=auto,format=rgb24",
                        "-frames:v", "1", dst], check=True)
        print("input", os.path.relpath(dst, ROOT))


# ------------------------------------------------------------------------------------------ ledger
_led_lock = threading.Lock()
_submit_lock = threading.Lock()


def short(v):
    if isinstance(v, str) and v.startswith("data:"):
        return "%s...(base64 %d chars)" % (v[:30], len(v))
    return v


def ledger_line(entry):
    with _led_lock:
        os.makedirs(os.path.dirname(LEDGER), exist_ok=True)
        with open(LEDGER, "a") as f:
            f.write(json.dumps(entry) + "\n")


def account():
    return float(ludo.account().get("available", 0.0))


class BudgetStop(Exception):
    pass


PRICE = {"/assets/image": 0.5, "/assets/image/edit": 0.5, "/assets/image/style": 0.5, "/assets/3d-model": 3.0}


def local_b64(rel):
    path = os.path.join(ROOT, rel)
    mime = ludo.MIME.get(os.path.splitext(path)[1].lower(), "image/webp")
    return "data:%s;base64,%s" % (mime, base64.b64encode(open(path, "rb").read()).decode())


NEGATIVE = ("no", "not", "without", "never", "negative")


def check_prompt(text):
    """STYLE_BIBLE §3 rule 1: a negative is drawn, so a prompt holding one is refused."""
    import re
    bad = re.findall(r"\b(%s)\b" % "|".join(NEGATIVE), text or "", re.I)
    if bad:
        raise ValueError("negative wording %s in: %s" % (bad, text[:80]))


def body_of(row):
    k = row["kind"]
    check_prompt(row.get("prompt"))
    if k == "edit":
        return "/assets/image/edit", {"image": local_b64(row["from_file"]), "prompt": row["prompt"], "n": row["n"],
                                      "image_type": "asset", "augment_prompt": False}
    if k == "styled":
        return "/assets/image/style", {"style_image": local_b64(row["style_file"]), "prompt": row["prompt"],
                                       "image_type": "asset", "n": row["n"], "augment_prompt": False}
    if k == "image":
        return "/assets/image", {"image_type": "asset", "prompt": row["prompt"], "art_style": "Cel-Shaded",
                                 "perspective": "High Angle", "aspect_ratio": "ar_1_1", "n": row["n"],
                                 "augment_prompt": False}
    if k == "model3d":
        return "/assets/3d-model", {"image": local_b64(row["from_file"]), "target_num_faces": row["faces"],
                                    "texture_size": row["texture_size"], "texture_type": row["texture_type"]}
    raise ValueError(k)


def cand_files(row):
    base = os.path.join(ROOT, row["out"])
    if row["kind"] == "model3d":
        return [base + ".glb"] if os.path.exists(base + ".glb") else []
    return sorted(glob.glob(base + "_c[0-9].*"))


def run_row(row, state, deadline):
    """Submit one row (with retries that bump v), download its results. Returns True on success."""
    endpoint, body = body_of(row)
    n = row.get("n", 1)
    planned = PRICE[endpoint] * n
    for attempt in range(4):
        if time.time() > deadline:
            raise RuntimeError("deadline")
        v = state["v"].get(row["id"], 1)
        rid = "asc3d-%s-v%d" % (row["id"], v)
        with _submit_lock:
            avail = account()
            spent = state["balance_before"] - avail
            if spent + planned > CAP:
                raise BudgetStop("cap: spent %.1f + %.1f > %.1f" % (spent, planned, CAP))
            b = dict(body)
            b["request_id"] = rid
            job = ludo.call("POST", endpoint, b)
        t0 = time.time()
        jid = job.get("id")
        while job.get("status") not in ("succeeded", "failed", "canceled"):
            job = ludo.call("GET", "/assets/jobs/%s?wait=55" % jid, timeout=90)
        secs = round(time.time() - t0)
        entry = {"t": time.strftime("%Y-%m-%d %H:%M:%S"), "row": row["id"], "request_id": rid, "endpoint": endpoint,
                 "body": {k: short(x) for k, x in body.items()}, "job": jid, "status": job.get("status"),
                 "credits_charged": job.get("credits_charged") or 0, "planned": planned, "secs": secs,
                 "result": None, "files": [], "side_files": [], "error": job.get("error")}
        if job.get("status") != "succeeded":
            entry["spent_after"] = round(state["balance_before"] - account(), 2)
            ledger_line(entry)
            ludo.log("FAIL %s v%d: %s" % (row["id"], v, str(job.get("error"))[:200]))
            with _submit_lock:
                state["v"][row["id"]] = v + 1
                save_state(state)
            continue
        res = job.get("result")
        base = os.path.join(ROOT, row["out"])
        os.makedirs(os.path.dirname(base), exist_ok=True)
        files, side = [], []
        if row["kind"] == "model3d":
            url = res["model_url"]
            ludo.download(url, base + ".glb")
            files.append(base + ".glb")
            for i, u in enumerate(res.get("snapshots") or []):
                p = "%s_snap%d%s" % (base, i, ludo.ext_of(u, ".png"))
                try:
                    ludo.download(u, p)
                    side.append(p)
                except Exception as e:  # a snapshot must not lose the model
                    ludo.log("  snapshot failed", str(e)[:100])
            entry["result"] = {"model_url": url, "snapshots": res.get("snapshots")}
        else:
            urls = ludo.result_urls(res)
            for old in cand_files(row):
                os.remove(old)
            for k, u in enumerate(urls):
                p = "%s_c%d%s" % (base, k + 1, ludo.ext_of(u, ".webp"))
                ludo.download(u, p)
                real = ludo.sniff(p)
                if real and not p.endswith(real):
                    os.replace(p, p.rsplit(".", 1)[0] + real)
                    p = p.rsplit(".", 1)[0] + real
                files.append(p)
            entry["result"] = [{"url": u} for u in urls]
        entry["files"] = [os.path.relpath(p, ROOT) for p in files]
        entry["side_files"] = [os.path.relpath(p, ROOT) for p in side]
        entry["spent_after"] = round(state["balance_before"] - account(), 2)
        ledger_line(entry)
        ludo.log("done %-34s %4ds  %.1f cr  (batch spent %.1f)" % (row["id"], secs, entry["credits_charged"],
                                                                   entry["spent_after"]))
        return True
    return False


def run(stage, only, jobs, hours):
    ludo.KEY = ludo.api_key()
    state = load_state()
    if state.get("balance_before") is None:
        state["balance_before"] = account()
        state.setdefault("v", {})
        state.setdefault("picks", {})
    save_state(state)
    if stage == "bases":
        make_inputs()
    todo = []
    for r in rows():
        if r["stage"] != stage:
            continue
        if only and not any(r["id"] == o or r["unit"] == o or r["id"].endswith("_" + o) or ("_%s_" % o) in r["id"]
                            for o in only):
            continue
        man = {a["id"]: a for a in json.load(open(MANIFEST))["assets"]}
        a = man[r["id"]]
        if cand_files(a):
            continue
        src = a.get("from_file") or a.get("style_file")
        if src and not os.path.exists(os.path.join(ROOT, src)):
            ludo.log("skip %s: no input %s (pick it first)" % (r["id"], src))
            continue
        todo.append(a)
    ludo.log("%s: %d rows, balance before %.1f, cap %.0f" % (stage, len(todo), state["balance_before"], CAP))
    deadline = time.time() + hours * 3600
    failures = []
    stop = threading.Event()

    def work(a):
        if stop.is_set():
            return
        try:
            if not run_row(a, state, deadline):
                failures.append(a["id"])
        except BudgetStop as e:
            stop.set()
            ludo.log("BUDGET STOP", str(e))
            failures.append(a["id"])
        except Exception as e:
            failures.append(a["id"])
            ludo.log("ERROR", a["id"], str(e)[:300])
    with ThreadPoolExecutor(max_workers=jobs) as ex:
        list(ex.map(work, todo))
    ludo.log("finished %s; failed: %s" % (stage, failures or "none"))


# ------------------------------------------------------------------------------------------- picks
def deshadow(path):
    """Paint out the soft grey ground shadow a picture sometimes draws under the feet (it would come
    back from image-to-3D as a fused base): a flood fill from the border over grey pixels (low
    saturation, lighter than the ink), set to the background grey. The figure's own steel and greys
    sit inside its ink outline, so the fill can't reach them. Returns the share of pixels changed."""
    w, h = (int(x) for x in subprocess.run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", path], capture_output=True,
                                           text=True).stdout.split()[-3::2])
    raw = bytearray(subprocess.run([FF, "-loglevel", "error", "-i", path, "-f", "rawvideo", "-pix_fmt", "rgb24",
                                    "pipe:1"], capture_output=True, check=True).stdout)
    corners = [raw[0:3], raw[(w - 1) * 3:(w - 1) * 3 + 3]]
    bg = tuple(sum(c[i] for c in corners) // len(corners) for i in range(3))

    bgv = max(bg)
    y_top = int(h * 0.6)  ## a ground shadow lies under the feet: only the lower 40% of the frame

    def greyish(i):
        r, g, b = raw[i], raw[i + 1], raw[i + 2]
        mx, mn = max(r, g, b), min(r, g, b)
        ## grey, lighter than the ink, never lighter than the background (steel highlights stop it)
        return 70 < mx <= bgv + 6 and (mx - mn) <= 0.12 * mx + 4
    seen = bytearray(w * h)
    stack = [(x, h - 1) for x in range(w)] + [(x, y) for y in range(y_top, h) for x in (0, w - 1)]
    changed = 0
    while stack:
        x, y = stack.pop()
        if x < 0 or y < y_top or x >= w or y >= h:
            continue
        q = y * w + x
        if seen[q]:
            continue
        seen[q] = 1
        i = q * 3
        if not greyish(i):
            continue
        if tuple(raw[i:i + 3]) != bg:
            if abs(raw[i] - bg[0]) + abs(raw[i + 1] - bg[1]) + abs(raw[i + 2] - bg[2]) > 12:
                changed += 1
            raw[i:i + 3] = bytes(bg)
        stack.extend(((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)))
    tmp = path + ".raw.png"
    subprocess.run([FF, "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", "%dx%d" % (w, h),
                    "-i", "pipe:0", tmp], input=bytes(raw), check=True)
    subprocess.run([FF, "-y", "-loglevel", "error", "-i", tmp, "-c:v", "libwebp", "-quality", "90", path], check=True)
    os.remove(tmp)
    return changed / float(w * h)


def reroll(row_id, why=""):
    """A new take of a row: its version goes up (a new request id) and its candidates move to old/."""
    man = {a["id"]: a for a in json.load(open(MANIFEST))["assets"]}
    a = man[row_id]
    olddir = os.path.join(ROOT, os.path.dirname(a["out"]), "old")
    os.makedirs(olddir, exist_ok=True)
    v = a.get("v", 1)
    for f in cand_files(a) + glob.glob(os.path.join(ROOT, a["out"] + "_snap*")):
        os.replace(f, os.path.join(olddir, "v%d_%s" % (v, os.path.basename(f))))
    state = load_state()
    state["v"][row_id] = v + 1
    state.setdefault("rerolls", {})[row_id] = state.get("rerolls", {}).get(row_id, []) + ["v%d: %s" % (v, why)]
    state["picks"].pop(row_id, None)
    save_state(state)
    print("reroll %s -> v%d (%s)" % (row_id, v + 1, why))


def pick(row_id, k, name=None, clean=False):
    """Candidate k of a picture row becomes the pick (webp q90, at most 1024 px)."""
    man = {a["id"]: a for a in json.load(open(MANIFEST))["assets"]}
    a = man[row_id]
    cands = cand_files(a)
    src = [c for c in cands if os.path.basename(c).startswith(os.path.basename(a["out"]) + "_c%d." % k)]
    if not src:
        sys.exit("no candidate %d for %s (%s)" % (k, row_id, cands))
    dst = os.path.join(ROOT, a["pick_to"] if not name else os.path.join(os.path.dirname(a["pick_to"]), name + ".webp"))
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    gd = os.path.join(ROOT, "assets", "_concept", ".gdignore")
    if not os.path.exists(gd):
        open(gd, "w").close()
    subprocess.run([FF, "-y", "-loglevel", "error", "-i", src[0], "-vf",
                    "scale='min(1024,iw)':'min(1024,ih)':force_original_aspect_ratio=decrease",
                    "-c:v", "libwebp", "-quality", "90", dst], check=True)
    if clean:
        print("deshadow: %.2f%% of pixels repainted" % (100 * deshadow(dst)))
    state = load_state()
    state.setdefault("picks", {})
    key = row_id if not name else "%s:%s" % (row_id, name)
    state["picks"][key] = k
    save_state(state)
    print("pick %s c%d -> %s" % (row_id, k, os.path.relpath(dst, ROOT)))


# ------------------------------------------------------------------------------------------ review
SCRATCH = os.environ.get("ASC3D_SCRATCH", os.path.join(ROOT, GLB_CAND, "_review"))


def strip(row_id):
    """Ludo's 4 snapshots of a model side by side, for the review (outside the install folders)."""
    man = {a["id"]: a for a in json.load(open(MANIFEST))["assets"]}
    a = man[row_id]
    snaps = sorted(glob.glob(os.path.join(ROOT, a["out"] + "_snap*.*")))
    if not snaps:
        sys.exit("no snapshots for " + row_id)
    os.makedirs(SCRATCH, exist_ok=True)
    out = os.path.join(SCRATCH, row_id[len("model_"):] + "_strip.png")
    ins = []
    for s in snaps[:4]:
        ins += ["-i", s]
    n = min(4, len(snaps))
    ## each snapshot (transparent ground) over light grey, 400 px tall, side by side
    flt = "".join("[%d]scale=-2:400,format=rgba[a%d];color=c=0xC8C8C8:s=400x400[g%d];[g%d][a%d]overlay=(W-w)/2:0:"
                  "shortest=1[s%d];" % (i, i, i, i, i, i) for i in range(n)) + "".join("[s%d]" % i for i in range(n)) \
        + "hstack=%d" % n
    subprocess.run([FF, "-y", "-loglevel", "error", *ins, "-filter_complex", flt, out], check=True)
    print(out)
    return out


def contact_sheet(group, out):
    """studio/contact-sheets/asc-3d-<group>.png (STYLE_BIBLE §7): rows = units (or rulers, or
    building kinds), columns = their installed models; each cell is the picked picture, then two of
    Ludo's snapshots (front three-quarter and side), with the id, faces and file size. Palette-
    reduced, at most 3000 px wide. Needs Pillow (python3 -m pip install pillow)."""
    from PIL import Image, ImageDraw, ImageFont
    d = load_descriptor()
    man = {a["id"]: a for a in json.load(open(MANIFEST))["assets"]}
    BG, INK = (0x1C, 0x1B, 0x2A), (0xF1, 0xEC, 0xE0)
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 15)
        big = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 19)
    except OSError:
        font = big = ImageFont.load_default()
    rows = []
    if group in ("units", "rulers"):
        for uid in (UNITS if group == "units" else RULERS):
            cells = [("model_%s_%s" % (uid, p), d[group].get(uid, {}).get(p))
                     for p in (POSES if group == "units" else RULER_POSES)]
            rows.append((uid, cells))
        if group == "units":
            cells = [("model_" + xid, d.get("extras", {}).get(x["extra"], {}).get(x["faction"]))
                     for xid, x in EXTRAS.items()]
            rows.append(("army extras", cells))
    else:
        for bid, b in BUILDINGS.items():
            vs = ["a", "b"][:b.get("variants", 1)] if b.get("variants", 1) > 1 else [None]
            cells = []
            for v in vs:
                key = v or (b["faction"] or "default")
                cells.append(("model_%s" % (bid + ("_" + v if v else "")), d["buildings"].get(bid, {}).get(key)))
            rows.append((bid, cells))
        rows.append(("scenery", [("model_" + pid, d.get("props", {}).get(pid, {}).get("default")) for pid in PROPS]))
    ncol = max(len(c) for _, c in rows)
    PW = 150
    CH = min(230, int(((2980 - 14) / ncol - 10 - PW - 16) / 2))  ## at most 3000 px wide
    cw = PW + 2 * CH + 16
    if group == "buildings":  ## two kinds to a row, so the sheet stays under 3000 px wide
        merged = []
        for i in range(0, len(rows), 2):
            pair = rows[i:i + 2]
            merged.append((" / ".join(r[0] for r in pair), [c for r in pair for c in r[1]]))
        rows = merged
        ncol = max(len(c) for _, c in rows)
        CH = min(230, int(((2980 - 14) / ncol - 10 - PW - 16) / 2))
        cw = PW + 2 * CH + 16
    W = min(3000, 20 + ncol * (cw + 10))
    H = 70 + len(rows) * (CH + 60)
    sheet = Image.new("RGB", (W, H), BG)
    dr = ImageDraw.Draw(sheet)
    dr.text((14, 14), "asc-3d-factions · %s · picked picture | Ludo snapshots (front, side) · faces · MB" % group,
            fill=INK, font=big)
    y = 56
    for name, cells in rows:
        dr.text((14, y), name, fill=INK, font=big)
        x = 14
        for row_id, e in cells:
            a = man.get(row_id)
            if a is None:
                continue
            pic = os.path.join(ROOT, a["from_file"])
            snaps = sorted(glob.glob(os.path.join(ROOT, a["out"] + "_snap*.*")))
            box = Image.new("RGB", (cw, CH), (0x28, 0x27, 0x40))
            if os.path.exists(pic):
                im = Image.open(pic).convert("RGB")
                im.thumbnail((PW, CH))
                box.paste(im, (0, (CH - im.height) // 2))
            for k, si in enumerate([0, 1]):
                if si < len(snaps):
                    im = Image.open(snaps[si]).convert("RGBA")
                    im.thumbnail((CH, CH))
                    g = Image.new("RGBA", (CH, CH), (0xC8, 0xC8, 0xC8, 255))
                    g.alpha_composite(im, ((CH - im.width) // 2, (CH - im.height) // 2))
                    box.paste(g.convert("RGB"), (PW + 8 + k * (CH + 8), 0))
            sheet.paste(box, (x, y + 24))
            label = (a.get("pose") or a.get("variant") or a["unit"]) + "  "
            if e:
                label += "%d faces · %.2f MB · %s %.2f men" % (e["faces"], e["bytes"] / 1e6, e["size"]["axis"], e["size"]["men"])
            else:
                label += "(not installed)"
            dr.text((x, y + 26 + CH), label, fill=INK, font=font)
            x += cw + 10
        y += CH + 60
    sheet = sheet.quantize(colors=256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    sheet.save(out, optimize=True)
    print("%s: %dx%d, %.2f MB" % (out, W, H, os.path.getsize(out) / 1e6))


# ------------------------------------------------------------------------------------- GLB measure
def glb_mesh(path):
    """Positions and triangle indices of every primitive (node transforms applied), the base colour
    image bytes, and the face count. Stdlib."""
    js, binc = glb_slim.read_glb(path)
    views, accs = js.get("bufferViews", []), js.get("accessors", [])

    def acc_data(i):
        a = accs[i]
        v = views[a["bufferView"]]
        off = v.get("byteOffset", 0) + a.get("byteOffset", 0)
        comp = {5126: "f", 5125: "I", 5123: "H", 5121: "B"}[a["componentType"]]
        ncomp = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[a["type"]]
        size = struct.calcsize("<" + comp)
        stride = v.get("byteStride", size * ncomp)
        out = []
        for k in range(a["count"]):
            out.append(struct.unpack_from("<%d%s" % (ncomp, comp), binc, off + k * stride))
        return out

    def node_mats():
        mats = {}

        def mul(a, b):
            return [[sum(a[i][k] * b[k][j] for k in range(4)) for j in range(4)] for i in range(4)]

        def local(n):
            if "matrix" in n:
                m = n["matrix"]
                return [[m[c * 4 + r] for c in range(4)] for r in range(4)]
            t = n.get("translation", [0, 0, 0])
            q = n.get("rotation", [0, 0, 0, 1])
            s = n.get("scale", [1, 1, 1])
            x, y, z, w = q
            r = [[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                 [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                 [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]]
            return [[r[i][0] * s[0], r[i][1] * s[1], r[i][2] * s[2], t[i]] for i in range(3)] + [[0, 0, 0, 1]]

        def walk(i, parent):
            m = mul(parent, local(js["nodes"][i]))
            mats.setdefault(i, m)
            for c in js["nodes"][i].get("children", []):
                walk(c, m)
        ident = [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]]
        roots = js.get("scenes", [{}])[js.get("scene", 0)].get("nodes", list(range(len(js.get("nodes", [])))))
        for r in roots:
            walk(r, ident)
        return mats
    pos, tris = [], []
    for ni, m in node_mats().items():
        node = js["nodes"][ni]
        if "mesh" not in node:
            continue
        for prim in js["meshes"][node["mesh"]]["primitives"]:
            base = len(pos)
            for p in acc_data(prim["attributes"]["POSITION"]):
                pos.append(tuple(m[i][0] * p[0] + m[i][1] * p[1] + m[i][2] * p[2] + m[i][3] for i in range(3)))
            idx = [i[0] for i in acc_data(prim["indices"])] if "indices" in prim else list(range(len(pos) - base))
            for k in range(0, len(idx) - 2, 3):
                tris.append((base + idx[k], base + idx[k + 1], base + idx[k + 2]))
    img = None
    for mat in js.get("materials", []):
        bct = mat.get("pbrMetallicRoughness", {}).get("baseColorTexture")
        if bct is not None:
            im = js["images"][js["textures"][bct["index"]]["source"]]
            v = views[im["bufferView"]]
            img = binc[v.get("byteOffset", 0):v.get("byteOffset", 0) + v["byteLength"]]
            break
    return pos, tris, img


def texture_rgb(img, size=128):
    """The colour map decoded to size x size RGB bytes (ffmpeg)."""
    p = subprocess.run([FF, "-loglevel", "error", "-i", "pipe:0", "-vf", "scale=%d:%d" % (size, size), "-f",
                        "rawvideo", "-pix_fmt", "rgb24", "pipe:1"], input=img, capture_output=True, check=True)
    return p.stdout


def hue_clusters(img):
    """Saturated hues of the colour map: [(hue 0..1, share of the saturated pixels)], biggest first."""
    raw = texture_rgb(img)
    bins = [0] * 36
    tot = 0
    for i in range(0, len(raw), 3):
        r, g, b = raw[i] / 255.0, raw[i + 1] / 255.0, raw[i + 2] / 255.0
        h, s, v = colorsys.rgb_to_hsv(r, g, b)
        if s > 0.45 and v > 0.18:
            bins[int(h * 36) % 36] += 1
            tot += 1
    out = []
    for k in sorted(range(36), key=lambda k: -bins[k]):
        if bins[k] and tot:
            out.append((round((k + 0.5) / 36, 3), round(bins[k] / tot, 3)))
    return out[:6], tot / max(1, len(raw) // 3)


def _samples(pos, tris):
    """Points on the surface: every vertex plus each triangle's centroid and edge midpoints."""
    pts = list(pos)
    for a, b, c in tris:
        pa, pb, pc = pos[a], pos[b], pos[c]
        pts.append(tuple((pa[i] + pb[i] + pc[i]) / 3 for i in range(3)))
        pts.append(tuple((pa[i] + pb[i]) / 2 for i in range(3)))
        pts.append(tuple((pb[i] + pc[i]) / 2 for i in range(3)))
    return pts


def _bulk(pts, axis, lo, hi, cross, nb=50, grid=72, keep=0.12):
    """Slices along `axis`; each slice's bulk is the number of grid cells its surface points fill on
    the two `cross` axes (a head fills a ring of cells, a spear shaft one or two). Returns the first
    and last slice (as fractions) whose bulk is at least `keep` of the biggest slice's."""
    ln = hi[axis] - lo[axis]
    span = max(hi[cross[0]] - lo[cross[0]], hi[cross[1]] - lo[cross[1]])
    cells = [set() for _ in range(nb)]
    for p in pts:
        k = min(nb - 1, int((p[axis] - lo[axis]) / ln * nb))
        cells[k].add((int((p[cross[0]] - lo[cross[0]]) / span * grid), int((p[cross[1]] - lo[cross[1]]) / span * grid)))
    bulk = [len(c) for c in cells]
    big = max(bulk) or 1
    ks = [k for k in range(nb) if bulk[k] >= keep * big]
    return (ks[0] / nb, (ks[-1] + 1) / nb, bulk) if ks else (0.0, 1.0, bulk)


def refine_hue(img, approx, win=0.04):
    """The mean hue (circular) of the colour map's saturated pixels within `win` of `approx`, the
    share of the map they cover, and how far the nearest other big hue cluster (3%+ of the
    saturated pixels, from hue_clusters' 10-degree bins) lies: how wide a key can be before it
    catches the model's own colours."""
    raw = texture_rgb(img, 256)
    sx = sy = 0.0
    n = 0
    for i in range(0, len(raw), 3):
        h, s, v = colorsys.rgb_to_hsv(raw[i] / 255.0, raw[i + 1] / 255.0, raw[i + 2] / 255.0)
        if s < 0.30 or v < 0.12:
            continue
        d = abs(h - approx)
        if min(d, 1 - d) <= win:
            sx += math.cos(h * 2 * math.pi)
            sy += math.sin(h * 2 * math.pi)
            n += 1
    hue = (math.atan2(sy, sx) / (2 * math.pi)) % 1.0 if n else approx
    near = 0.5
    for ch, share in hue_clusters(img)[0]:
        d = abs(ch - hue)
        d = min(d, 1 - d)
        if share >= 0.03 and d > 0.045:
            near = min(near, d)
    return round(hue, 3), round(n / (len(raw) / 3.0), 4), round(near, 3)


def measure(path):
    """Extents, faces, and how much of the height (or of a lying figure's length) is the body rather
    than a thin weapon reaching past it: the highest slice with at least 20% of the biggest slice's
    surface bulk is the top of the head. Used for scale normalisation; reviewed on a lineup."""
    pos, tris, img = glb_mesh(path)
    xs, ys, zs = [p[0] for p in pos], [p[1] for p in pos], [p[2] for p in pos]
    lo = (min(xs), min(ys), min(zs))
    hi = (max(xs), max(ys), max(zs))
    pts = _samples(pos, tris)
    _, top, bulk = _bulk(pts, 1, lo, hi, (0, 2))
    ax = 0 if hi[0] - lo[0] >= hi[2] - lo[2] else 2
    a0, a1, _ = _bulk(pts, ax, lo, hi, (1, 2 - ax if ax == 0 else 0))
    return {"faces": len(tris), "verts": len(pos), "aabb_min": [round(c, 4) for c in lo],
            "aabb_max": [round(c, 4) for c in hi], "size": [round(hi[i] - lo[i], 4) for i in range(3)],
            "body_frac": round(top, 3), "long_frac": round(a1 - a0, 3), "long_axis": "xz"[ax // 2],
            "bulk": bulk, "img": img, "pos": pos, "tris": tris}


def heightmap(pos, tris, lo, hi, n=96):
    """Max height over an n x n grid of the x/z footprint (triangles rasterised by their vertices
    and centroid, enough for a courtyard)."""
    hm = [[lo[1]] * n for _ in range(n)]
    sx, sz = (hi[0] - lo[0]) / n, (hi[2] - lo[2]) / n

    def put(x, y, z):
        i = min(n - 1, max(0, int((x - lo[0]) / sx)))
        j = min(n - 1, max(0, int((z - lo[2]) / sz)))
        if y > hm[j][i]:
            hm[j][i] = y
    for a, b, c in tris:
        pa, pb, pc = pos[a], pos[b], pos[c]
        for t in ((1, 0, 0), (0, 1, 0), (0, 0, 1), (1 / 3, 1 / 3, 1 / 3), (0.5, 0.5, 0), (0, 0.5, 0.5), (0.5, 0, 0.5)):
            put(*(pa[i] * t[0] + pb[i] * t[1] + pc[i] * t[2] for i in range(3)))
    return hm


def courtyard(m):
    """The open yard of a fortress-class model: the biggest rectangle of grid cells no higher than
    the floor + 4% of the height, in the model's own frame as fractions of the widest side, centred
    on the footprint centre (x right, z toward the model's front)."""
    lo, hi = m["aabb_min"], m["aabb_max"]
    n = 96
    hm = heightmap(m["pos"], m["tris"], lo, hi, n)
    hs = sorted(v for row in hm for v in row)
    floor = hs[int(len(hs) * 0.25)]
    tol = floor + 0.04 * (hi[1] - lo[1])
    open_ = [[hm[j][i] <= tol for i in range(n)] for j in range(n)]
    ## the yard must sit inside the walls: drop cells reachable from the border along open cells
    ## except through the gate... simpler: keep the largest rectangle that doesn't touch the border
    best = (0, None)
    hist = [0] * n
    for j in range(n):
        for i in range(n):
            hist[i] = hist[i] + 1 if open_[j][i] and 0 < i < n - 1 and 0 < j < n - 1 else 0
        stack = []
        for i in range(n + 1):
            hgt = hist[i] if i < n else 0
            start = i
            while stack and stack[-1][1] >= hgt:
                s, sh = stack.pop()
                area = sh * (i - s)
                if area > best[0]:
                    best = (area, (s, j - sh + 1, i - 1, j))
                start = s
            stack.append((start, hgt))
    if best[1] is None:
        return None
    i0, j0, i1, j1 = best[1]
    inside = sorted(hm[j][i] for j in range(j0, j1 + 1) for i in range(i0, i1 + 1))
    floor = inside[len(inside) // 2]
    w = max(hi[0] - lo[0], hi[2] - lo[2])
    cx, cz = (lo[0] + hi[0]) / 2, (lo[2] + hi[2]) / 2
    x0 = lo[0] + (hi[0] - lo[0]) * i0 / n
    x1 = lo[0] + (hi[0] - lo[0]) * (i1 + 1) / n
    z0 = lo[2] + (hi[2] - lo[2]) * j0 / n
    z1 = lo[2] + (hi[2] - lo[2]) * (j1 + 1) / n
    return {"rect": [round((x0 - cx) / w, 3), round((z0 - cz) / w, 3), round((x1 - cx) / w, 3), round((z1 - cz) / w, 3)],
            "floor": round((floor - lo[1]) / w, 4)}


# ------------------------------------------------------------------------------------------ install
GROUP_ORDER = ("units", "rulers", "extras", "buildings", "props")
POSE_ORDER = {p: i for i, p in enumerate(RULER_POSES)}
KIND = {"units": "unit", "rulers": "ruler", "extras": "extra", "buildings": "building", "props": "prop"}


def dump_descriptor(d):
    """models.json: one model per line, grouped and ordered (units and rulers in data order, poses
    ready / march / strike / fallen), so a diff shows which model changed."""
    order = {k: i for i, k in enumerate(list(UNITS) + list(RULERS) + ["standard_bearer", "musician"] + list(BUILDINGS)
                                          + list(PROPS))}
    lines = ["{", ' "format": %d,' % d.get("format", 1)]
    groups = [g for g in GROUP_ORDER if d.get(g)]
    for gi, g in enumerate(groups):
        lines.append(' "%s": {' % g)
        ids = sorted(d[g], key=lambda k: order.get(k, 999))
        for ii, i in enumerate(ids):
            lines.append('  "%s": {' % i)
            keys = sorted(d[g][i], key=lambda k: (POSE_ORDER.get(k, 9), k))
            for ki, k in enumerate(keys):
                lines.append('   "%s": %s%s' % (k, json.dumps(d[g][i][k], sort_keys=True), "," if ki < len(keys) - 1 else ""))
            lines.append("  }" + ("," if ii < len(ids) - 1 else ""))
        lines.append(" }" + ("," if gi < len(groups) - 1 else ""))
    lines.append("}")
    with open(DESCRIPTOR, "w") as f:
        f.write("\n".join(lines) + "\n")


def load_descriptor():
    if os.path.exists(DESCRIPTOR):
        return json.load(open(DESCRIPTOR))
    return {"format": 1, "units": {}, "rulers": {}, "buildings": {}}


def install(row_id, yaw=0.0, men=None, hues=None, notes="", sink=None, court=True, frac=None, gate=None):
    man = {a["id"]: a for a in json.load(open(MANIFEST))["assets"]}
    a = man[row_id]
    src = os.path.join(ROOT, a["out"] + ".glb")
    dst = os.path.join(ROOT, a["target"])
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    before, after = glb_slim.slim(src, dst, 3, a["slim_max"], True)
    glb_slim.write_import(a["target"], ROOT)
    m = measure(dst)
    d = load_descriptor()
    group = a["group"]
    entry = {"path": "res://" + a["target"], "kind": KIND[group], "id": a["unit"]}
    if group == "extras":
        x = EXTRAS[a["unit"]]
        entry.update({"id": x["extra"], "faction": x["faction"], "variant": x["faction"], "class": "army extra"})
        f = frac or m["body_frac"]
        entry["size"] = {"axis": "height", "men": men if men else round(x["body"] / f, 3)}
        entry["body_share"] = round(f, 3)
        entry["body_men"] = x["body"]
    elif group == "props":
        pr = PROPS[a["unit"]]
        entry.update({"faction": None, "variant": None})
        entry["size"] = {"axis": pr["axis"], "men": men if men else pr["men"]}
    elif group in ("units", "rulers"):
        u = (UNITS if group == "units" else RULERS)[a["unit"]]
        pose = a["pose"]
        entry.update({"faction": u["faction"], "class": u["cls"], "pose": pose})
        ## `frac` is the reviewed share of the extent that is the body (the head top, or a lying
        ## body's length, read off a ruler render); the measured guess stands in when it is not given
        if pose in LYING:
            ## a lying figure is sized by its length (the longer side of its footprint), the body
            ## lying about as long as it stands tall
            f = frac or m["long_frac"]
            entry["size"] = {"axis": "length", "men": men if men else round(u["body"] / f, 3)}
        else:
            f = frac or m["body_frac"]
            entry["size"] = {"axis": "height", "men": men if men else round(u["body"] / f, 3)}
        entry["body_share"] = round(f, 3)
        entry["body_men"] = u["body"]
    else:
        b = BUILDINGS[a["unit"]]
        entry.update({"faction": b["faction"], "variant": a["variant"]})
        entry["size"] = {"axis": "width", "men": men if men else b["men"]}
        if court and a["unit"].startswith(("fortress", "fort_")):
            c = courtyard(m)
            if c:
                ## into the turned frame (gate on +Z): rotate the rect's corners by the yaw
                x0, z0, x1, z1 = c["rect"]
                cs, sn = math.cos(yaw), math.sin(yaw)
                pts = [(x * cs + z * sn, -x * sn + z * cs) for x, z in ((x0, z0), (x1, z1))]
                c["rect"] = [round(min(p[0] for p in pts), 3), round(min(p[1] for p in pts), 3),
                             round(max(p[0] for p in pts), 3), round(max(p[1] for p in pts), 3)]
                entry["courtyard"] = c
            ## the outer gate point in the turned frame (reviewed on a top render: the middle of the
            ## +Z wall for all four)
            entry["gate"] = list(gate) if gate else [0.0, 0.5]
        if sink is not None:
            entry["sink"] = sink
    entry["yaw"] = round(yaw, 4)
    clusters, sat_share = hue_clusters(m["img"]) if m["img"] else ([], 0)
    keys = []
    for h, part in (hues or []):
        hue, share, near = refine_hue(m["img"], h)
        ## model_common.gdshaderinc keys |dh| < width fully and fades out by 1.8 x width: keep that
        ## edge clear of the model's other saturated colours
        width = round(max(0.015, min(0.06, near / 1.8 - 0.005)), 3)
        keys.append({"hue": hue, "width": width, "part": part, "share": share})
        print("  hue key %s: %.3f (asked %.3f), %.1f%% of the map, nearest other hue %.3f away -> width %.3f" % (
            part, hue, h, 100 * share, near, width))
    entry["hue_keys"] = keys
    entry["faces"] = m["faces"]
    entry["texture"] = a["slim_max"]
    entry["bytes"] = after
    entry["extent"] = m["size"]
    if notes:
        entry["notes"] = notes
    if group == "buildings":
        d["buildings"].setdefault(a["unit"], {})[a["variant"] or (entry["faction"] or "default")] = entry
    elif group == "extras":
        d.setdefault("extras", {}).setdefault(entry["id"], {})[entry["faction"]] = entry
    elif group == "props":
        d.setdefault("props", {}).setdefault(a["unit"], {})["default"] = entry
    else:
        d[group].setdefault(a["unit"], {})[a["pose"]] = entry
    dump_descriptor(d)
    print("installed %s: %.2f -> %.2f MB, %d faces, extent %s, body %.2f of height, hues %s" % (
        a["target"], before / 1e6, after / 1e6, m["faces"], m["size"], m["body_frac"], clusters[:4]))
    return entry


# ------------------------------------------------------------------------------- the board's table
BOARD_TABLE = os.path.join(ROOT, "world3d", "models.json")
MAN = 6.0  ## world3d/kit.gd FIG: a man is 6 world units on the board


def fortress_frame(path, yaw_rad, side):
    """A fortress-class model measured in the board's fortress frame (world3d/world_view.gd
    _place_fortress: the gate on local -Z after the row's yaw, `side` world units across, the
    footprint centred): the yard, the front wall, the gate opening and its towers' height."""
    m = measure(os.path.join(ROOT, path))
    lo, hi = m["aabb_min"], m["aabb_max"]
    s = side / max(hi[0] - lo[0], hi[2] - lo[2])
    cx, cz = (lo[0] + hi[0]) / 2, (lo[2] + hi[2]) / 2
    cs, sn = math.cos(yaw_rad), math.sin(yaw_rad)
    ## Basis(UP, yaw): x' = x cos + z sin, z' = -x sin + z cos
    pos = [(((p[0] - cx) * cs + (p[2] - cz) * sn) * s, (p[1] - lo[1]) * s, (-(p[0] - cx) * sn + (p[2] - cz) * cs) * s)
           for p in m["pos"]]
    xs, zs = [p[0] for p in pos], [p[2] for p in pos]
    blo, bhi = (min(xs), 0.0, min(zs)), (max(xs), max(p[1] for p in pos), max(zs))
    n = 96
    hm = heightmap(pos, m["tris"], blo, bhi, n)
    cell_x, cell_z = (bhi[0] - blo[0]) / n, (bhi[2] - blo[2]) / n
    top = bhi[1]
    yard = courtyard(dict(m, aabb_min=list(blo), aabb_max=list(bhi), pos=pos))
    w = max(bhi[0] - blo[0], bhi[2] - blo[2])
    x0, z0, x1, z1 = [v * w for v in yard["rect"]]
    floor = yard["floor"] * w
    ## the front wall: scanning from the front edge (-Z) toward the middle, in the columns a quarter of
    ## the way out on either side, the first row of cells at least a fifth of the model's height
    tall = 0.2 * top
    walls = []
    for xq in (-0.25, 0.25):
        i = int((xq * w - blo[0]) / cell_x)
        for j in range(n // 2):
            if hm[j][i] > tall:
                walls.append(blo[2] + (j + 0.5) * cell_z)
                break
    wall_z = sum(walls) / len(walls) if walls else -side * 0.4
    j = int((wall_z - blo[2]) / cell_z)
    ## the gate: the open run of that wall row round x = 0, and the towers either side of it
    i0 = int((0.0 - blo[0]) / cell_x)
    rows = [hm[k] for k in range(max(0, j - 1), min(n, j + 2))]
    low = lambda i: min(r[i] for r in rows) <= floor + 0.12 * top
    a = b = i0
    while a > 0 and low(a - 1):
        a -= 1
    while b < n - 1 and low(b + 1):
        b += 1
    half = max(abs(blo[0] + a * cell_x), abs(blo[0] + (b + 1) * cell_x))
    ii = [k for k in range(max(0, a - 6), a)] + [k for k in range(b + 1, min(n, b + 7))]
    tower = max((max(r[k] for r in rows) for k in ii), default=0.3 * top)
    return {"court": [round(x0, 1), round(z0, 1), round(x1 - x0, 1), round(z1 - z0, 1)],
            "floor": round(floor, 2), "wall_z": round(wall_z, 1), "front_z": round(blo[2], 1),
            "gate_half": round(half, 1), "tower": round(tower, 1), "top": round(top, 1)}


def board(write=True):
    """Fills world3d/models.json (the board's model table, world3d/README.md) from models.json: every
    figure's row gets its ready model, height and yaw, and its poses; the fortresses, forts, villages,
    landmarks, camps and scenery get rows. Other fields (fallback, rank, large, ruler, scale) stay."""
    d = load_descriptor()
    text = open(BOARD_TABLE).read()
    tb = json.loads(text)
    figs = tb.setdefault("figures", {})
    for group in ("units", "rulers"):
        for uid, poses in d.get(group, {}).items():
            row = figs.setdefault(uid, {"faction": poses["ready"]["faction"], "fallback": uid, "rank": 0})
            ready = poses.get("ready")
            if not ready:
                continue
            row["model"] = ready["path"]
            row["height"] = ready["size"]["men"]
            row["yaw"] = round(180.0 + math.degrees(ready["yaw"]), 1)
            row["poses"] = {p: poses[p]["path"] for p in RULER_POSES if p in poses}
            row["pose_size"] = {p: {"axis": poses[p]["size"]["axis"], "men": poses[p]["size"]["men"]}
                                for p in RULER_POSES if p in poses}
            row.pop("scale", None) if False else None
    ex = d.get("extras", {})
    if ex:
        b = figs.setdefault("bearer", {"faction": "", "model": "", "height": 1.0, "fallback": "bearer", "rank": 2})
        b["models"] = {f: e["path"] for f, e in ex.get("standard_bearer", {}).items()}
        b["model_height"] = {f: e["size"]["men"] for f, e in ex.get("standard_bearer", {}).items()}
        if ex.get("musician"):
            mu = figs.setdefault("musician", {"faction": "", "model": "", "height": 1.0, "fallback": "bearer", "rank": 2})
            mu["models"] = {f: e["path"] for f, e in ex["musician"].items()}
            mu["model_height"] = {f: e["size"]["men"] for f, e in ex["musician"].items()}
    blds = tb.setdefault("buildings", {})
    bd = d.get("buildings", {})
    for kind, side in (("fortress", 76.0),):
        for fac in ("kingdom", "beasts"):
            e = bd.get("%s_%s" % (kind, fac), {}).get(fac)
            if not e:
                continue
            ## the board turns the model by the row's yaw so its gate is on -Z; ours face +Z after
            ## our yaw, so the board's yaw is ours + 180
            yaw_deg = (180.0 + math.degrees(e["yaw"])) % 360.0
            fr = fortress_frame(e["path"][len("res://"):], math.radians(yaw_deg), side)
            row = blds.get("%s.%s" % (kind, fac), {})
            for k in ("stone", "palisade"):
                row.pop(k, None)
            keys = e.get("hue_keys", [])
            roof = [k for k in keys if k["part"] in ("roofs", "tents")]
            row.update({"model": e["path"], "fallback": kind, "side": side, "yaw": round(yaw_deg, 1),
                        "key_hue": roof[0]["hue"] if roof else -1.0, "tint": 0.86 if fac == "kingdom" else 1.0,
                        "court": fr["court"], "gate_z": [round(fr["wall_z"] + 8.0, 1), round(fr["front_z"] - 2.0, 1)],
                        "sink": round(max(0.0, fr["floor"] - 0.25), 2), "floor": 0.25 if fr["floor"] > 0.25 else round(fr["floor"], 2),
                        ## the gate's own towers stand about 9 units either side of the gate (read off
                        ## the top renders; the measured opening is narrower than the towers' spacing)
                        "banner_at": [9.0, round(fr["tower"] * 0.85, 1)]})
            if roof and roof[0]["width"] < 0.06:
                row["key_width"] = roof[0]["width"]
            blds["%s.%s" % (kind, fac)] = row
            print(kind, fac, fr)
    for fac in ("kingdom", "beasts"):
        e = bd.get("fort_" + fac, {}).get(fac)
        if e:
            yaw_deg = (180.0 + math.degrees(e["yaw"])) % 360.0
            roof = [k for k in e.get("hue_keys", []) if k["part"] == "roofs"]
            blds["fort." + fac] = {"model": e["path"], "fallback": "fort", "side": round(e["size"]["men"] * MAN, 1),
                                   "yaw": round(yaw_deg, 1), "key_hue": roof[0]["hue"] if roof else -1.0,
                                   "tint": 0.9, "court": None,
                                   ## the gate is the middle of the front wall (gate on -Z in the board's frame)
                                   "gate_z": [round(-e["size"]["men"] * MAN * 0.5 + 4.0, 1),
                                              round(-e["size"]["men"] * MAN * 0.5 - 4.0, 1)]}
            c = e.get("courtyard")
            if c:
                sd = e["size"]["men"] * MAN
                x0, z0, x1, z1 = c["rect"]
                ## ours has the gate on +Z; the board's frame has it on -Z
                blds["fort." + fac]["court"] = [round(-x1 * sd, 1), round(-z1 * sd, 1), round((x1 - x0) * sd, 1),
                                                round((z1 - z0) * sd, 1)]
    for kind in ("village_plains", "village_forest", "village_hills", "mill", "watchtower"):
        vs = bd.get(kind, {})
        if not vs:
            continue
        paths = [vs[k]["path"] for k in sorted(vs)]
        first = vs[sorted(vs)[0]]
        row = {"model": paths[0], "fallback": "cottage", "side": round(first["size"]["men"] * MAN, 1), "yaw": 180.0}
        if len(paths) > 1:
            row["variants"] = paths
        blds[kind] = row
    for fac in ("kingdom", "beasts"):
        e = bd.get("camp_" + fac, {}).get(fac)
        if e:
            tents = [k for k in e.get("hue_keys", []) if k["part"] == "tents"]
            blds["camp." + fac] = {"model": e["path"], "fallback": "cottage", "side": round(e["size"]["men"] * MAN, 1),
                                   "yaw": 180.0, "key_hue": tents[0]["hue"] if tents else -1.0}
    pr = d.get("props", {})
    for kind, board_kind, fb in (("tree_broadleaf", "tree_broadleaf", "broadleaf"), ("tree_pine", "tree_pine", "pine"),
                                 ("rocks", "rock", "rock"), ("standing_stones", "standing_stones", "rock")):
        e = pr.get(kind, {}).get("default")
        if not e:
            continue
        row = blds.get(board_kind, {"fallback": fb})
        row["model"] = e["path"]
        row["yaw"] = 180.0
        if e["size"]["axis"] == "height":
            row["height"] = e["size"]["men"]
        else:
            row["side"] = round(e["size"]["men"] * MAN, 1)
        blds[board_kind] = row
    if write:
        write_board_table(tb)
    return tb


def write_board_table(tb):
    """Keeps world3d/models.json's hand layout: one row per line, tabs."""
    def row_line(k, v, last):
        return '\t\t"%s": %s%s' % (k, json.dumps(v, ensure_ascii=False), "" if last else ",")
    out = ["{"]
    keys = list(tb.keys())
    for ki, k in enumerate(keys):
        v = tb[k]
        last = ki == len(keys) - 1
        if k in ("figures", "buildings") and isinstance(v, dict):
            out.append('\t"%s": {' % k)
            ids = list(v.keys())
            for ii, i in enumerate(ids):
                out.append(row_line(i, v[i], ii == len(ids) - 1))
            out.append("\t}" + ("" if last else ","))
        else:
            out.append('\t"%s": %s%s' % (k, json.dumps(v, ensure_ascii=False), "" if last else ","))
    out.append("}")
    with open(BOARD_TABLE, "w") as f:
        f.write("\n".join(out) + "\n")


def cost():
    tot = {}
    for r in rows():
        endpoint = {"edit": "/assets/image/edit", "styled": "/assets/image/style", "image": "/assets/image",
                    "model3d": "/assets/3d-model"}[r["kind"]]
        tot[r["stage"]] = tot.get(r["stage"], 0) + PRICE[endpoint] * r.get("n", 1)
    for k, v in tot.items():
        print("%-10s %6.1f credits" % (k, v))
    print("%-10s %6.1f credits (cap %.0f)" % ("total", sum(tot.values()), CAP))


def main(argv):
    if not argv:
        print(__doc__)
        return
    cmd = argv[0]
    opt = {}
    rest = []
    i = 1
    while i < len(argv):
        if argv[i].startswith("--"):
            opt[argv[i][2:]] = argv[i + 1] if i + 1 < len(argv) and not argv[i + 1].startswith("--") else True
            i += 2 if opt[argv[i][2:]] is not True else 1
        else:
            rest.append(argv[i])
            i += 1
    if cmd == "manifest":
        write_manifest()
    elif cmd == "cost":
        cost()
    elif cmd == "account":
        ludo.KEY = ludo.api_key()
        print("credits available %.1f" % account())
    elif cmd == "run":
        only = opt.get("only", "").split(",") if opt.get("only") else []
        run(rest[0], only, int(opt.get("jobs", 3)), float(opt.get("hours", 6)))
    elif cmd == "pick":
        pick(rest[0], int(rest[1]), rest[2] if len(rest) > 2 else None, bool(opt.get("deshadow")))
    elif cmd == "reroll":
        reroll(rest[0], " ".join(rest[1:]))
    elif cmd == "strip":
        strip(rest[0])
    elif cmd == "install":
        hues = []
        for hspec in (opt.get("hue") or "").split(",") if opt.get("hue") else []:
            h, part = hspec.split(":")
            hues.append((float(h), part))
        install(rest[0], float(opt.get("yaw", 0.0)), float(opt["men"]) if "men" in opt else None, hues,
                opt.get("notes", ""), float(opt["sink"]) if "sink" in opt else None,
                frac=float(opt["frac"]) if "frac" in opt else None,
                gate=[float(x) for x in opt["gate"].split(",")] if "gate" in opt else None)
    elif cmd == "board":
        board()
    elif cmd == "sheet":
        contact_sheet(rest[0], os.path.join(ROOT, "studio", "contact-sheets", "asc-3d-%s.png" % rest[0]))
    elif cmd == "measure":
        m = measure(rest[0])
        print(json.dumps({k: v for k, v in m.items() if k not in ("img", "pos", "tris")}))
    else:
        print(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
