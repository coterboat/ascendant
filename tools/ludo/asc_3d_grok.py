#!/usr/bin/env python3
"""asc-3d-grok: the M4 transformation models re-rolled from Alex's Grok Imagine concept art (issue #162).

Alex's pictures (assets/_concept/lore/crown/ and thornmane/) show the transformation looks and new units better
than the first models of asc-3d-paths did. This batch models them: for each of the eight families (Sunspears and
Seraphs, Iron Knights and the Iron Colossus, Thornthrowers and Briarwardens, Bloodtuskers and Bloodsworn) one
figure of his art is cropped out of its sheet (a crop box; the sheet's title text is outside it, or painted over),
cut out of its background by Ludo (removeBackground), laid on the plain grey of the 3D pictures, and used as the
`ready` picture; where the cutout kept scraps of the painted ground (a forest, a courtyard, soft shadows) an edit
paints them over (stage `fixes`); march / strike / fallen are pose edits of that picture (as in asc-3d-factions);
each of the four pictures goes to image-to-3D. The Thornthrowers have no art of Alex's: their ready picture is styled
from the Briarwarden's. Every picture is looked at before it goes on, and every model's snapshot strip before it goes
in the batch; a dark picture whose model came back near-black is lifted (`lift`) and the model re-rolled, a dark
colour map is lifted after the fact (`retexture`, no Ludo call).

It builds on asc_3d_paths.py (the families' names, sizes and targets, the board table) and asc_3d_factions.py (the
Ludo driver with its credit cap, picks, re-rolls, snapshot strips, GLB measuring) under its own batch: the manifest is
tools/ludo/batches/asc-3d-grok.json and every charged call is a line of studio/ledgers/asc-3d-grok.jsonl.

    python3 tools/ludo/asc_3d_grok.py manifest                 # (re)write the batch manifest
    python3 tools/ludo/asc_3d_grok.py cost                     # what each stage plans to spend
    python3 tools/ludo/asc_3d_grok.py account
    python3 tools/ludo/asc_3d_grok.py crops                    # cut the source figures out of Alex's sheets (ffmpeg, free)
    python3 tools/ludo/asc_3d_grok.py run cuts [--only seraphs]    # removeBackground of each crop
    python3 tools/ludo/asc_3d_grok.py ready <family>           # the cutout laid on grey is the family's ready picture
    python3 tools/ludo/asc_3d_grok.py run fixes                # an edit of a ready pick that paints scraps of the old ground over
    python3 tools/ludo/asc_3d_grok.py run styled               # Thornthrowers: no art of its own, styled from the Briarwarden
    python3 tools/ludo/asc_3d_grok.py run poses [--only f]     # march / strike / fallen edits of the ready picture
    python3 tools/ludo/asc_3d_grok.py pick <row> <k>           # candidate k (1..n) is the pick
    python3 tools/ludo/asc_3d_grok.py run models [--only f]    # every picked picture to a GLB
    python3 tools/ludo/asc_3d_grok.py strip <model row> | strips [--poses p,p] <family> ...   # Ludo's snapshots, for the review
    python3 tools/ludo/asc_3d_grok.py reroll <row> <why>       # a new take: v+1, old candidates to old/
    python3 tools/ludo/asc_3d_grok.py portraits [family ...]    # head-and-shoulders crops of the cutouts on the portrait backdrop
    python3 tools/ludo/asc_3d_grok.py lift <model row> <gamma>  # a dark pick's values lifted (the pick before is kept), then reroll + run
    python3 tools/ludo/asc_3d_grok.py levels [rows]            # each model's colour map lightness (L*) against its picture's
    python3 tools/ludo/asc_3d_grok.py retexture [<family:pose> ... [--gamma G]]   # lift dark colour maps (none named: all that need it; no Ludo call), then `stage`
    python3 tools/ludo/asc_3d_grok.py ruler <out.png> <family:pose> ...   # a pick with a ruler every 10%, to read the body share
    python3 tools/ludo/asc_3d_grok.py stage [family|model row ...] [--frac F]
                                                               # slim + measure a raw GLB into the review batch's file
    python3 tools/ludo/asc_3d_grok.py batch                    # build / refresh review/m4_looks (review.py from-folder)
    python3 tools/ludo/asc_3d_grok.py compare [--proj DIR] [--out DIR]   # screenshots: the game's model next to each candidate
    python3 tools/ludo/asc_3d_grok.py run portraits             # the Thornthrowers' portrait (Ludo, styled from the Briarwarden's)
    python3 tools/ludo/asc_3d_grok.py portraits-batch           # build review/m4_portraits (a concept batch; Install accepted = review.py apply)
    python3 tools/ludo/asc_3d_grok.py install [--batch m4_looks] [--dry-run] [--only id,id]
                                                               # accepted models -> their targets, descriptor, board rows

The review batch (review/m4_looks, gitignored, for Alex): one item per model, grouped by side (celestial_host,
living_iron, thorn_wild, blood_pact), the item's `target` being the model the game has now, so `0` in the Review
Table swaps the viewer to it. Nothing in assets/models/ or world3d/models.json changes until Alex accepts and runs
Install accepted, which is this script's `install` (its batch.json action): it copies each accepted GLB to its
target (the model's Godot .import kept when it has one), re-measures it, rewrites that model's row of
assets/models/models.json, and then the board rows of the eight families (asc_3d_paths.board(): only those lines
of world3d/models.json change). `--dry-run` says what it would do and writes nothing. The Review Table runs the action
from the checkout it serves, so `review/m4_looks` has to sit in the checkout this script is committed in.
The portraits are a second, concept batch, review/m4_portraits (`portraits-batch`): head and shoulders of the same
cutouts, the item targets the portraits the game has now, Install accepted = `review.py apply`.

Discipline as the other batches (studio/ludo-playbook.md): the cap is checked before every submit as
`balance_before - available + planned`, where `available` is this batch's own ledger, not the shared account (another
builder's spend is never charged to it): CAP is the budget of the round in hand (below); a failed job is free but burns
its request id, so a retry bumps `v`; candidates and raw GLBs stay in the gitignored candidates/ folders; every input goes
to Ludo as base64 from a local file; no prompt holds a negative (a negative is drawn). Stdlib plus ffmpeg.

The base-first gate and the redo (issue #179, from Alex's 10-8 notes)
---------------------------------------------------------------------
"The base model has to be nailed down before we build on it": every pose and every look is an edit of a family's ready
picture, so a wrong base spreads into all of them. A family is made in two stages (tools/ludo/base_gate.py):

    python3 tools/ludo/asc_3d_grok.py run base --only sunspears   # BASE: the ready picture, 3 takes (an edit of the current one)
    python3 tools/ludo/asc_3d_grok.py base-batch                  # review/m4_redo_base/ (a concept batch): Alex marks Good / Good with changes / Bad
    python3 tools/ludo/asc_3d_grok.py base-status                 # every family's base: accepted, waiting, refused, with why
    python3 tools/ludo/asc_3d_grok.py run poses|models --only sunspears   # DERIVE: refused, naming the family, until its base is accepted

`run poses` and `run models` read review/m4_redo_base/review.json before they submit anything, and so does every row
they would submit; a family whose base is not Good (or Good with changes, after a redo) is refused with a plain message,
and the take Alex kept is copied over the family's ready pick, so the poses are made from exactly that picture. The
families Alex accepted before the gate existed (their ready models, in review/m4_looks) are GRANDFATHERED below, with
the verdict that stands for each. `regen-base` is the batch's "Redo rejected" action; `pick` refuses a base row (the
base is picked in the Review Table, never by the script).

The redo round (`ROUND`, its own `CAP`, every ledger line of it tagged `"round"`): the poses Alex rejected on 10-8 are
made again from the accepted bases, `redo` per `family:pose` (a new request id, the old candidates and the stale pick
moved away, the colour lifts of the old model forgotten), and their models go to the model batch `review/m4_redo`
(`batch --name m4_redo --only f:pose,...`), whose item targets are the models the game has now (`0` compares):

    python3 tools/ludo/asc_3d_grok.py redo bloodsworn:march bloodsworn:strike bloodsworn:fallen briarwardens:march thornthrowers:fallen
    python3 tools/ludo/asc_3d_grok.py run poses --only bloodsworn,briarwardens,thornthrowers   # then look, `pick <row> <k>`, run models
"""
import filecmp
import glob
import json
import math
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import threading

HERE =os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import asc_3d_paths as P  # noqa: E402  (the families' tables, the board rows; it also loads the driver)
import glb_slim  # noqa: E402
import base_gate  # noqa: E402  (the base-first gate: derive only from a base Alex accepted, #179)

F = P.F
ROOT = F.ROOT
BATCH = "asc-3d-grok"
MANIFEST = os.path.join(ROOT, "tools", "ludo", "batches", BATCH + ".json")
LEDGER = os.path.join(ROOT, "studio", "ledgers", BATCH + ".jsonl")
BATCH_CAP = 250.0  ## the budget of #162 (the first round: 185 credits were spent of it)
## The redo round of #179 (Alex's 10-8 notes): 120 credits across both batch scripts, 70 of them here (asc_3d_free_holds.py
## has the other 50). Spend is counted from this batch's own ledger, the lines tagged ROUND; CAP is what the driver stops at.
ROUND = "redo-10-8"
CAP = 70.0
SENTINEL = 1000.0  ## balance_before: the driver's spend is SENTINEL - available, and available is SENTINEL - the round's spend
PIC_CAND = "assets/_concept/candidates/grok"
GLB_CAND = "assets/models/candidates/grok"
INPUTS = PIC_CAND + "/_inputs"
PICKS = "assets/_concept/grok3d"  ## committed picks: <faction>/<family>_<pose>.webp
LORE = "assets/_concept/lore"
REVIEW_BATCH = "m4_looks"
BASE_BATCH = "m4_redo_base"  ## the concept batch of base pictures (the gate reads its review.json)
REDO_BATCH = "m4_redo"  ## the model batch of the redone poses
POSES = F.POSES
LYING = F.LYING

SIDES = {"celestial_host": "Celestial Host", "living_iron": "Living Iron", "thorn_wild": "Thorn Wild",
         "blood_pact": "Blood Pact"}

# ----------------------------------------------------------------------------------------- the families
## name (the asc-3d-paths family: P.VARIANTS or P.NEW), side, the source sheet, the ffmpeg filters that cut one
## figure out of it (the sheet's title text painted over with the ground colour where a crop alone can't avoid
## it), the pose lines (C-pose: "The same figure, now ...": positive wording only), and a note on the source.
FAMILIES = {
    ## Alex 10-8 (m4_looks): "good but let's get rid of the halo, and the random spikes coming out of him"; "his spear
    ## should be held by the low end". The halo becomes an effect later, so no pose draws it; the glow around the figure
    ## (rays at the shoulders and sides) came back from image-to-3D as spikes. The poses below are made only from a base
    ## Alex has accepted (BASE_REDO has the base's edit): a ready picture with the halo, so these never see it again.
    "sunspears": dict(
        side="celestial_host", art="crown/celestial_transformation_ex1.jpg", crop="crop=560:830:1150:56",
        note="the right figure of 'Aurel Crown Spearman / Transitional Armour / Celestial Sunspear', redone on Alex's 10-8 "
             "notes (the halo and the spikes taken away, the spear held by its low end)",
        march="marching forward with his left leg striding ahead, his right hand gripping the golden spear by its low end "
              "beside his hip, the spearhead sloping up and back over his right shoulder, his left arm swinging, eyes ahead",
        strike="lunging forward on his bent left leg, thrusting the golden spear straight ahead at waist height, his right "
               "arm fully extended and gripping the spear by its low end, his left hand open at his side, a fierce shout",
        fallen="fallen in battle, lying flat on his back on the floor with his arms out to the sides, his helmet still on, "
               "the golden spear lying on the floor beside him, eyes closed"),
    "seraphs": dict(
        side="celestial_host", art="crown/seraph.jpg",
        crop="drawbox=x=560:y=15:w=600:h=130:color=0x13161f:t=fill,crop=950:830:845:50",
        note="Variant II, the Guardian Seraph, of 'Celestial Host Seraphs'",
        march="walking forward with his left leg ahead, the big stained-glass shield held at his side, the wings half-folded "
              "behind him, the halo glowing behind his helm, eyes ahead",
        strike="lunging forward on his bent left leg in a shield bash, the big stained-glass shield thrust forward, his free "
               "hand clenched back at his side, the wings swept up high and wide behind him, a battle cry",
        fallen="fallen in battle, lying flat on his back on the floor with his arms out to the sides, the stained-glass "
               "wings folded closely against his sides, his helm still on, the big stained-glass shield lying on the "
               "floor beside him, eyes closed"),
    "iron_knights": dict(
        side="living_iron", art="crown/horseman_transformed_iron.jpg", crop="crop=1330:1152:290:0",
        note="the Living Iron horseman: black iron knight and horse with orange seams and violet crystals",
        march="the iron horse walking forward at a steady pace with its right foreleg raised, the knight upright in the "
              "saddle holding the same spiked iron lance in his right hand, its tip pointing forward and down",
        strike="the iron horse charging forward at a gallop with its forelegs reaching ahead, the knight leaning into the "
               "charge with the same spiked iron lance lowered level and pointing straight ahead",
        fallen="the iron horse collapsed onto its belly with its legs folded under it and its head low, the knight slumped "
               "forward over its neck, the spiked iron lance lying on the floor beside them"),
    "iron_colossus": dict(
        side="living_iron", art="crown/iron_colossus.jpg", crop="crop=940:970:320:0",
        note="the colossus of the courtyard scene: black crystal-plated body, orange seams, a rose window on its chest",
        march="striding forward with its left leg ahead, its arms swinging, its fists clenched, the orange glow of its "
              "cracks bright",
        strike="smashing both fists down in front of it in a crushing double blow, leaning forward, the orange glow of its "
               "cracks bright and its eyes burning",
        fallen="toppled in battle, lying flat on its back on the floor with its arms out to the sides, the orange glow of "
               "its cracks dimmed"),
    "thornthrowers": dict(
        side="thorn_wild", art=None, crop=None,
        note="no art of its own: styled from the Briarwarden picture (the Thorn Wild look of thornmane_transformations.jpg)",
        march=None, strike=None, fallen=None),
    "briarwardens": dict(
        side="thorn_wild", art="thornmane/thornmane_transformations.jpg", crop="crop=840:1008:70:0",
        note="the left figure of the Thorn Wild / Blood Pact pair: living bark and moss, red glyphs, spiked club and shield",
        ## Alex 10-8: "needs to be holding the club" (v1 drew the club on the shoulder with both hands empty)
        march="striding forward with its left leg ahead, its right hand gripping the handle of the spiked tree-trunk club "
              "and resting the club on its right shoulder, the thorned bark shield strapped to its left arm, its eyes "
              "glowing green ahead",
        strike="smashing down with the spiked tree-trunk club held high over its head in both hands, leaning forward, the "
               "thorned bark shield strapped to its left arm, its eyes glowing bright green",
        fallen="toppled in battle, lying flat on its back on the floor with its arms out to the sides, the spiked "
               "tree-trunk club and the thorned bark shield lying on the floor beside it, the green glow of its eyes "
               "dimmed"),
    "bloodtuskers": dict(
        side="blood_pact", art="thornmane/thornmane_bloodgod.jpg", crop="crop=860:760:920:222",
        note="the right figure of 'Thornmane Clans Tuskers': Bloodtusker of the Blood Pact, crimson hide and bone spikes",
        march="stomping forward with his left leg ahead, the spiked bone-and-stone mace resting on his right shoulder, "
              "his left fist swinging, eyes ahead",
        strike="smashing down with the spiked bone-and-stone mace held high over his head in both hands, leaning forward, "
               "mouth open in a roar",
        fallen="fallen in battle, lying flat on his back on the floor with his arms out to the sides, the spiked "
               "bone-and-stone mace lying on the floor beside him, eyes closed"),
    "bloodsworn": dict(
        side="blood_pact", art="thornmane/thornmane_transformations.jpg", crop="crop=830:920:890:80",
        note="the right figure of the Thorn Wild / Blood Pact pair: black-furred wolf, bone spikes, bone scythe blade",
        ## Alex 10-8: "his arm blades are dropped as weapons, they should be still attached to him" (fallen); "it keeps
        ## thinking he's holding the weapons instead of them being attached to his arms" (march); his own edit of the
        ## strike line: "slashing with his arm blade raised". The blades are part of his arms: the ready picture draws
        ## the curved bone blade growing out of the right forearm and bone spikes along the left.
        march="loping forward with his left leg ahead, his arms swinging at his sides, the curved bone blade growing out "
              "of his right forearm as part of the arm and the bone spikes along his left forearm, the blades grow from "
              "the forearms and swing with the arms, his claws open and empty, eyes ahead",
        ## v2 of the strike picture: the first three takes all drew a hilt, a separate sword raised in his fist.
        strike="leaping forward in a savage lunge, slashing with his arm blade raised high: the curved bone blade grows out "
               "of his right forearm as one piece with the arm, running from the elbow past the wrist, his fist closed "
               "under the blade, the blades grow from the forearms as part of his arms, and his left claws thrust "
               "forward, mouth open in a snarl",
        fallen="fallen in battle, lying flat on his back on the floor with his arms out to the sides, the curved bone "
               "blades still growing from his forearms as part of his arms, his claws open and empty, eyes closed"),
}
## The reviewed share of each model's height (a lying figure: of its length) that is the body, READING[(family, pose)]: the
## head top against the figure's top, read off a ruler render of the pose's picked picture (`ruler`; the picture's
## outline is the model's, image-to-3D keeps it), so every pose of a family stands at the same body size. Left out, the
## measured guess (asc_3d_factions.measure) stands in. A model's yaw is 0 as in asc-3d-paths: Ludo's GLBs face +Z, which
## the board's yaw 180 turns to -Z (the game reads only a GLB's first mesh, so a turn baked into a node would be lost).
READING = {
    ("sunspears", "ready"): 0.85, ("sunspears", "march"): 0.88, ("sunspears", "strike"): 0.87,
    ("seraphs", "ready"): 0.89, ("seraphs", "march"): 0.87, ("seraphs", "strike"): 0.69,
    ("iron_knights", "ready"): 0.92, ("iron_knights", "march"): 0.94, ("iron_knights", "strike"): 0.93,
    ("iron_colossus", "ready"): 0.96, ("iron_colossus", "march"): 0.96, ("iron_colossus", "strike"): 0.93,
    ("thornthrowers", "ready"): 0.86, ("thornthrowers", "march"): 0.87, ("thornthrowers", "strike"): 0.89,
    ("briarwardens", "ready"): 0.95, ("briarwardens", "march"): 0.86, ("briarwardens", "strike"): 0.72,
    ("bloodtuskers", "ready"): 0.95, ("bloodtuskers", "march"): 0.75, ("bloodtuskers", "strike"): 0.61,
    ("bloodsworn", "ready"): 0.90, ("bloodsworn", "march"): 0.87, ("bloodsworn", "strike"): 0.72,
    ## fallen: head (or horns) to feet against the figure's longest side, read off the ruler sheet's vertical lines where the
    ## measured share (the bulk of the mesh along that side, asc_3d_factions.measure) takes the arms or a weapon as body;
    ## the others stand at the measured share (0.78 to 0.90). The #179 redo's Bloodsworn march / strike / fallen were read off
## the new pictures' rulers (0.87, 0.72, 0.88); the Briarwarden's march and the Thornthrowers' fallen stand as they were.
    ("iron_colossus", "fallen"): 0.85, ("thornthrowers", "fallen"): 0.85, ("briarwardens", "fallen"): 0.85,
    ("bloodtuskers", "fallen"): 0.80, ("bloodsworn", "fallen"): 0.88,
}
## A cutout of a busy painted ground (a forest, a courtyard) keeps scraps of it (haze, branches, wall, ground) and the
## cast shadows of a dark ground; an edit of the ready picture paints those over with the plain grey and keeps the figure.
CLEAN_LINE = ("The same figure alone on a plain flat light grey background: every leftover scrap of the old background "
              "(haze, ground, branches, rocks, walls, tiny soldiers and cast shadows) painted over with the same flat "
              "light grey, the figure itself exactly as it is, the whole figure in view with wide empty margin on "
              "every side.")
CLEAN = ("seraphs", "iron_colossus", "briarwardens", "bloodtuskers", "bloodsworn")

## ------------------------------------------------------------------------------------ the base gate and the redo (#179)
## The base redo: an edit of the family's current ready picture, 3 takes, into the concept batch BASE_BATCH. Alex's notes
## ride in the prompt in his own words (a negative is drawn, so each is said as what to do).
BASE_REDO = {
    ## m4_looks, the Sunspears' ready model: "good but let's get rid of the halo, and the random spikes coming out of him."
    ## (the picture's halo and the rays of glow around the figure; image-to-3D made the rays into spikes) and, on the
    ## strike: "His spear should be held by the low end."
    ## v1 ("redrawn as a clean game miniature") came back as plain gold-and-blue plate: the stained-glass pattern of his armour,
    ## the thing Alex liked ("good but ..."), was lost. v2 names what stays and changes only the three things he asked for.
    "sunspears": ("The same figure exactly as drawn, with the same ornate stained-glass pattern of gold, blue and red "
                  "panels on every piece of his armour, the same gold helmet and blue plume, the same face and the same "
                  "inked painted style, with three changes only. First, get rid of the halo behind his helmet. Second, get "
                  "rid of the random spikes and rays of light coming out of him, so the glow around his chest and "
                  "shoulders and sides is gone and the edges of his armour are clean. Third, his right hand holds the "
                  "long golden spear by its low end, just above the butt, so the spearhead rises far above his head. "
                  "He stands in a relaxed A-pose with his feet apart, the spear at arm's length out to his side with "
                  "clear space between the spear and his body, his left arm held a little out from his side. Three-quarter "
                  "view from slightly above, the whole figure with wide empty margin on every side, plain flat light "
                  "grey background."),
}
BASE_TAKES = 3
## The families whose base Alex accepted before the gate existed: his Good on the ready model in the batch that built it
## (review/m4_looks, 10-8; PR #178 installed them). The ready picture is the one that model was made from, so the base
## was seen and accepted. If that batch's review.json is here and says otherwise, base_gate refuses the family.
GRANDFATHERED = {
    "seraphs": {"batch": "m4_looks", "item": "celestial_host_seraphs_ready", "at": "2026-10-08T18:49:47"},
    "iron_knights": {"batch": "m4_looks", "item": "living_iron_iron_knights_ready", "at": "2026-10-08T18:51:02"},
    "iron_colossus": {"batch": "m4_looks", "item": "living_iron_iron_colossus_ready", "at": "2026-10-08T18:50:56"},
    "thornthrowers": {"batch": "m4_looks", "item": "thorn_wild_thornthrowers_ready", "at": "2026-10-08T18:51:19"},
    "briarwardens": {"batch": "m4_looks", "item": "thorn_wild_briarwardens_ready", "at": "2026-10-08T18:51:10"},
    "bloodtuskers": {"batch": "m4_looks", "item": "blood_pact_bloodtuskers_ready", "at": "2026-10-08T18:49:33"},
    "bloodsworn": {"batch": "m4_looks", "item": "blood_pact_bloodsworn_ready", "at": "2026-10-08T18:47:55"},
}
DERIVE_STAGES = ("poses", "models")  ## made only from an accepted base (the gate)
## What the redo round makes again: (family, pose) -> Alex's 10-8 note in m4_looks (the models he rejected; their targets
## are the models the game has now). The Sunspears wait for their base.
REDO = {
    ("bloodsworn", "march"): "same problem, it keeps thinking he's holding the weapons instead of them being attached to his arms",
    ("bloodsworn", "strike"): "rejected with his edit: slashing with his arm blade raised",
    ("bloodsworn", "fallen"): "his arm blades are dropped as weapons, they should be still attached to him",
    ("briarwardens", "march"): "needs to be holding the club",
    ("thornthrowers", "fallen"): "scatter the spears",
}
REDO_TAKES = 3  ## pictures per redone pose (0.5 credit each)

## Thornthrowers' ready picture is generateWithStyle from the Briarwarden's, with the fork's subject (as asc-3d-paths'
## new units are); its poses are the base fangthrower's, which the fork's looks already follow.
## v1 used F.C_MODEL ("chunky simplified shapes ... matte painted finish"): the three takes came back as soft toy renders
## that kept the Briarwarden's colours but none of its ink-outlined painted look.
THORNTHROWERS_BLOCK = ("Concept picture of one game miniature for a 3D model, drawn in the same detailed hand-painted "
                       "illustration style as the reference picture, with thick dark ink outlines and rich painted "
                       "textures of bark and moss, a single full figure standing with both feet flat on the plain floor, "
                       "arms held a little away from the body with both hands visible, a bold clear silhouette, three-quarter "
                       "view from slightly above, the whole figure centred with wide empty margin on every side and clear "
                       "headroom, plain flat light grey background.")
THORNTHROWERS_SUBJECT = (
    "a Thornmane thornthrower of the Thorn Wild, a lean wolf-headed beastman grown over with living bark and green moss, "
    "small thorned briars wound around his arms and legs, a few fresh leaves, red glyph war-paint across his chest and "
    "eyes, a bone necklace, a bundle of javelins on his back, standing in a relaxed A-pose with his feet apart, holding "
    "one long thorned wooden javelin upright in his right hand at arm's length out to his side with clear space between "
    "the javelin and his body, his left arm held a little out from his side, alert expression, eyes ahead")
for _p in ("march", "strike", "fallen"):
    FAMILIES["thornthrowers"][_p] = F.UNITS["fangthrowers"][_p].replace("the javelin", "the thorned wooden javelin")
## Alex 10-8: "scatter the spears" (the v1 fallen picture laid three javelins in a tidy bundle beside him)
FAMILIES["thornthrowers"]["fallen"] = (
    "fallen in battle, lying flat on his back on the floor with his arms out to the sides, his hands open and empty, "
    "the thorned wooden javelins scattered across the floor around him, one near his head, one by his feet and one far "
    "to his side, each pointing a different way, eyes closed")

## The portrait block: the series' C-portrait framing (STYLE_BIBLE 6.1) in the painted hand of the reference picture.
PORTRAIT_BLOCK = ("Portrait drawn in the same detailed hand-painted illustration style as the reference picture: head and "
                  "shoulders, three-quarter view facing left, face in the upper half of the frame, thick dark ink outlines "
                  "and rich painted textures, a plain softly graded deep indigo background.")
THORNTHROWERS_PORTRAIT = ("A thornthrower of the Thorn Wild, a lean wolf-headed beastman grown over with living bark and green "
                          "moss, small thorned briars around his shoulders, a few fresh leaves, red glyph war-paint across "
                          "his chest and eyes, a bone necklace, the tips of javelins rising behind his shoulder, alert "
                          "expression, eyes looking to the left")
PORTRAIT_DIR = "assets/_concept/candidates/grok/portraits"

# the pairs of (family -> its asc-3d-paths entry): a variant of a base unit, or a new unit
def entry_of(name):
    return P.VARIANTS[name] if name in P.VARIANTS else P.NEW[name]


def faction_of(name):
    return entry_of(name)["faction"]


def stem_of(name):
    """What the family's models are called in assets/models/units/<faction>/ (P: <unit>__<transformation id> for a
    variant, the unit id for a new unit)."""
    return P.vkey(name) if name in P.VARIANTS else name


def pick_of(name, pose):
    return "%s/%s/%s_%s.webp" % (PICKS, faction_of(name), name, pose)


def model_target(name, pose):
    return "assets/models/units/%s/%s_%s.glb" % (faction_of(name), stem_of(name), pose)


def body_of_family(name):
    return entry_of(name)["body"]


def group_of(name):
    return "variants" if name in P.VARIANTS else "units"


# ---------------------------------------------------------------------------------------------- the rows
def rows():
    """Every row of the batch in run order. Picture rows roll `n` candidates; model rows read a pick."""
    out = []
    for name, fam in FAMILIES.items():
        if fam["art"]:
            out.append({"id": "cut_%s" % name, "stage": "cuts", "kind": "cutout", "n": 1,
                        "from_file": "%s/%s.png" % (INPUTS, name), "pick_to": pick_of(name, "ready"), "group": "cuts",
                        "unit": name, "pose": "ready"})
    ## Thornthrowers: no art of its own, so its ready picture is styled from the Briarwarden's
    e = P.VARIANTS["thornthrowers"]
    out.append({"id": "pic_thornthrowers_ready", "stage": "styled", "kind": "styled", "n": 3,
                "style_file": pick_of("briarwardens", "ready"),
                "prompt": "%s Subject: %s." % (THORNTHROWERS_BLOCK, THORNTHROWERS_SUBJECT),
                "pick_to": pick_of("thornthrowers", "ready"), "group": "pictures", "unit": "thornthrowers",
                "pose": "ready", "anchor": "Briarwardens"})
    ## fixes: an edit of the ready pick back into the same pick (the pick before is kept beside the candidates)
    for name in CLEAN:
        out.append({"id": "fix_%s_ready" % name, "stage": "fixes", "kind": "edit", "n": 2,
                    "from_file": pick_of(name, "ready"), "prompt": CLEAN_LINE, "pick_to": pick_of(name, "ready"),
                    "group": "pictures", "unit": name, "pose": "ready"})
    ## base: the redo of a ready picture, 3 takes, an edit of the current one (stage `base`: the gate's input, so nothing
    ## gates it). Its candidates go to the concept batch BASE_BATCH, never to the pick: `pick` refuses a base row.
    for name, prompt in BASE_REDO.items():
        out.append({"id": "base_%s_ready" % name, "stage": "base", "kind": "edit", "n": BASE_TAKES,
                    "from_file": pick_of(name, "ready"), "prompt": prompt, "pick_to": pick_of(name, "ready"),
                    "group": "pictures", "unit": name, "pose": "ready"})
    for name, fam in FAMILIES.items():
        for pose in POSES[1:]:
            view = F.VIEW_LYING if pose in LYING else F.VIEW
            out.append({"id": "pic_%s_%s" % (name, pose), "stage": "poses", "kind": "edit",
                        "n": REDO_TAKES if (name, pose) in REDO else 2,
                        "from_file": pick_of(name, "ready"), "prompt": F.C_POSE.format(pose=fam[pose], view=view),
                        "pick_to": pick_of(name, pose), "group": "pictures", "unit": name, "pose": pose})
    ## the Thornthrowers' portrait: no art of Alex's, so styled from the Briarwarden's (his art's head and shoulders)
    out.append({"id": "por_thornthrowers", "stage": "portraits", "kind": "styled", "n": 3, "image_type": "portrait",
                "style_file": "%s/briarwardens_crop.webp" % PORTRAIT_DIR,
                "prompt": "%s Subject: %s." % (PORTRAIT_BLOCK, THORNTHROWERS_PORTRAIT),
                "pick_to": "%s/thornthrowers_ludo.webp" % PORTRAIT_DIR, "group": "portraits", "unit": "thornthrowers",
                "pose": "ready"})
    for pose in ("ready", "strike", "march", "fallen"):
        for name in FAMILIES:
            e = entry_of(name)
            out.append({"id": "model_%s_%s" % (name, pose), "stage": "models", "kind": "model3d",
                        "from_file": pick_of(name, pose), "faces": e["faces"], "texture_size": 1024,
                        "texture_type": "pbr", "slim_max": e["tex"], "target": model_target(name, pose),
                        "group": group_of(name), "unit": name, "pose": pose, "side": FAMILIES[name]["side"]})
    return out


def _jload(path):
    """json.load of a file, closed after."""
    with open(path) as f:
        return json.load(f)


def load_state():
    if os.path.exists(MANIFEST):
        return _jload(MANIFEST).get("state", {})
    return {}


def write_manifest(state=None):
    if state is None:
        state = load_state()
    state.setdefault("balance_before", None)
    state.setdefault("v", {})
    state.setdefault("picks", {})
    man = {
        "batch": BATCH, "rid_prefix": "ascgrok", "cap": CAP, "round": ROUND, "batch_cap": BATCH_CAP,
        "note": "Written by tools/ludo/asc_3d_grok.py (which holds the prompts; edit it, not this file). #162: the M4 "
                "transformation models re-rolled from Alex's Grok Imagine concept art. cut rows are removeBackground "
                "of a crop of his sheet; ready pictures are the cutout laid on grey (Thornthrowers: styled from the "
                "Briarwarden); march / strike / fallen are pose edits; model rows read the pick as base64. #179: base "
                "rows redo a ready picture into review/m4_redo_base (derive stages need Alex's Good on it), and the "
                "poses Alex rejected on 10-8 are redone in the round `round` (cap `cap`, counted from the ledger lines "
                "tagged with it; balance_before is a fixed sentinel, the account is shared).",
        "style": {"image": "", "art_style": "Cel-Shaded",
                  "blocks": {"C-model (3D, no base)": F.C_MODEL, "C-pose (no base)": F.C_POSE}},
        "state": state,
        "assets": [],
    }
    for r in rows():
        a = dict(r)
        a["v"] = state["v"].get(r["id"], 1)
        if r["id"] in state["picks"]:
            a["pick"] = state["picks"][r["id"]]
        if a["kind"] in ("edit", "styled"):
            a["augment"] = False
        if a["kind"] == "model3d":
            a["out"] = GLB_CAND + "/" + r["id"][len("model_"):]
        else:
            suffix = {"cut": "_cut", "fix": "_fix", "por": "_portrait", "base": "_base"}.get(r["id"].split("_", 1)[0], "")
            a["out"] = PIC_CAND + "/" + r["id"].split("_", 1)[1] + suffix
        man["assets"].append(a)
    os.makedirs(os.path.dirname(MANIFEST), exist_ok=True)
    with open(MANIFEST, "w") as f:
        json.dump(man, f, indent=1)
        f.write("\n")
    return man


def manifest_rows():
    return {a["id"]: a for a in _jload(MANIFEST)["assets"]}


## the driver (asc_3d_factions.py) reads these module globals: point them at this batch
F.BATCH, F.MANIFEST, F.LEDGER, F.CAP, F.RID = BATCH, MANIFEST, LEDGER, CAP, "ascgrok"
F.PRICE["/assets/3d-model"] = 4.0  ## measured: the ledger shows 4 credits charged per model (1024 px pbr), not 3
F.SCRATCH = os.environ.get("ASC3D_SCRATCH", os.path.join(ROOT, GLB_CAND, "_review"))
F.rows = rows
F.write_manifest = write_manifest
F.load_state = load_state

_driver_body_of = F.body_of


def _body_of(row):
    """A cutout here is removeBackground with the pixels exact and the canvas cropped to the figure (a crop of a
    sheet has wide empty ground around the figure)."""
    if row["kind"] == "cutout":
        return "/assets/image/remove-background", {"image": F.local_b64(row["from_file"]), "crop": True,
                                                   "creative_edit": False}
    return _driver_body_of(row)


F.body_of = _body_of


# ----------------------------------------------------------------------------------- the round's cap and the gate
## The driver counts spend as balance_before - account(). The account is shared (another builder spends from it at the same
## time), so here account() is this batch's own: SENTINEL less what its ledger says this round was charged.
F.ROUND = ROUND


def ledger_spent(round_tag=None):
    """Credits this batch's ledger says it was charged: every line, or only those tagged with one round."""
    total = 0.0
    if os.path.exists(LEDGER):
        with open(LEDGER) as f:
            for line in f:
                line = line.strip()
                if line:
                    e = json.loads(line)
                    if round_tag is None or e.get("round") == round_tag:
                        total += float(e.get("credits_charged") or 0)
    return round(total, 2)


def own_balance():
    return SENTINEL - ledger_spent(ROUND)


F.account = own_balance


def round_state():
    """balance_before is the SENTINEL for this round (it was the real account's balance when the first round began); the
    old value is kept as balance_before_162."""
    st = load_state()
    if st.get("balance_before") != SENTINEL:
        if st.get("balance_before") is not None:
            st.setdefault("balance_before_162", st["balance_before"])
        st["balance_before"] = SENTINEL
        F.save_state(st)
    return st


GATE = base_gate.Gate(BASE_BATCH, display=lambda name: name.replace("_", " ").title(), grandfathered=GRANDFATHERED)
_adopt_lock = threading.Lock()


def adopt_base(name):
    """The base gate for one family (base_gate.BaseNotAccepted when Alex has not accepted it), and the take he kept
    copied over the family's ready pick when it is not that picture already: the poses and the ready model are made from
    exactly the picture he accepted. A grandfathered family keeps the pick it has."""
    r = GATE.require(name)
    if r["file"]:
        dst = os.path.join(ROOT, pick_of(name, "ready"))
        with _adopt_lock:
            if not (os.path.exists(dst) and filecmp.cmp(str(r["file"]), dst, shallow=False)):
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                tmp = dst + ".tmp.webp"
                shutil.copyfile(str(r["file"]), tmp)
                os.replace(tmp, dst)
                print("adopted the base Alex accepted for %s: %s -> %s" % (name, r["file"], pick_of(name, "ready")))
    return r


def gate_row(row):
    """No derived row is submitted for a family whose base is not accepted, whichever way it was asked for (the driver
    calls this before each row: F.GATE_ROW)."""
    if row["stage"] in DERIVE_STAGES:
        adopt_base(row["unit"])


F.GATE_ROW = gate_row


def _row_matches(r, only):
    """F.run's --only: a row id, a family, a pose or a family inside the id."""
    return any(r["id"] == o or r["unit"] == o or r["id"].endswith("_" + o) or ("_%s_" % o) in r["id"] for o in only)


def run(stage, only, jobs, hours):
    """F.run behind the gate: a derive stage first checks the base of every family it would touch, and stops with a plain
    message (naming each family) before any Ludo call when one is not accepted."""
    if stage in DERIVE_STAGES:
        fams = [r["unit"] for r in rows() if r["stage"] == stage and (not only or _row_matches(r, only))]
        try:
            GATE.require_all(fams)
        except base_gate.BaseNotAccepted as e:
            sys.exit("refused (the base comes first):\n%s" % e)
    round_state()
    F.run(stage, only, jobs, hours)


def base_status():
    """Every family's base for the gate: accepted (and which take), grandfathered, or refused (and why)."""
    for name in FAMILIES:
        r = GATE.check(name)
        print("%-14s %-20s %s" % (name, r["state"], ("-> %s" % r["file"]) if r["file"] else r["message"]))


# --------------------------------------------------------------------------------------------- pictures
def _ffmpeg(*args):
    r = subprocess.run([F.FF, "-y", "-loglevel", "error", *args], capture_output=True, text=True)
    if r.returncode:
        sys.exit("ffmpeg failed: %s" % r.stderr.strip()[-400:])


def crops():
    """The source figures, cut out of Alex's sheets (a crop box; a family's title text painted over where the crop
    alone can't avoid it) into the gitignored candidates/ folder. No Ludo call."""
    os.makedirs(os.path.join(ROOT, INPUTS), exist_ok=True)
    for name, fam in FAMILIES.items():
        if not fam["art"]:
            continue
        dst = os.path.join(ROOT, INPUTS, name + ".png")
        _ffmpeg("-i", os.path.join(ROOT, LORE, fam["art"]), "-vf", fam["crop"], "-frames:v", "1", dst)
        print("crop %-14s %s -> %s" % (name, fam["art"], os.path.relpath(dst, ROOT)))


def ready(name, k=1):
    """A family's ready picture: the cutout laid on the plain light grey (#D4D4D4) of the 3D pictures, the
    figure fitted into 860 px of a 1024 canvas (webp q90, as the other picks). The cutout candidate is kept."""
    a = manifest_rows()["cut_" + name]
    cands = F.cand_files(a)
    if not cands:
        sys.exit("no cutout for %s (run `run cuts --only %s` first)" % (name, name))
    dst = os.path.join(ROOT, a["pick_to"])
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    gd = os.path.join(ROOT, "assets", "_concept", ".gdignore")
    if not os.path.exists(gd):
        open(gd, "w").close()
    tmp = dst + ".tmp.webp"
    _ffmpeg("-i", cands[k - 1], "-filter_complex",
            "[0]scale=860:860:force_original_aspect_ratio=decrease[f];color=c=0xD4D4D4:s=1024x1024[g];"
            "[g][f]overlay=(W-w)/2:(H-h)/2:format=auto,format=rgb24", "-frames:v", "1", "-c:v", "libwebp", "-quality",
            "90", tmp)
    os.replace(tmp, dst)
    state = load_state()
    state.setdefault("picks", {})["cut_" + name] = k
    F.save_state(state)
    print("ready %s <- %s -> %s" % (name, os.path.relpath(cands[k - 1], ROOT), a["pick_to"]))


def pick(row_id, k, clean=False):
    """F.pick (candidate k of a picture row becomes the pick); a fix row first keeps the pick it replaces beside its
    candidates (`<out>_before.webp`), so the cutout it cleaned is never lost."""
    if row_id.startswith("base_"):
        sys.exit("%s is a base picture: Alex picks it in the Review Table (%s), the poses adopt the take he accepted "
                 "(`base-batch` builds the batch)" % (row_id, BASE_BATCH))
    a = manifest_rows()[row_id]
    dst = os.path.join(ROOT, a["pick_to"])
    keep = os.path.join(ROOT, a["out"] + "_before.webp")
    if row_id.startswith("fix_") and os.path.exists(dst) and not os.path.exists(keep):
        shutil.copyfile(dst, keep)
    F.pick(row_id, k, None, clean)


def lift_pick(row_id, gamma):
    """A model row's picked picture lifted by a gamma (ffmpeg eq, saturation x1.05), in place; the pick before is kept
    beside the candidates (`<name>_<pose>_before_lift.webp`), and a second lift starts again from it, so gammas never
    stack (gamma 1 puts the original back). For a dark picture whose model came back near-black (asc-3d-paths' lift):
    the lifted picture gives image-to-3D's colour map its colours back. The row is then re-rolled and run again."""
    a = manifest_rows()[row_id]
    dst = os.path.join(ROOT, a["from_file"])
    keep = os.path.join(ROOT, PIC_CAND, "%s_%s_before_lift.webp" % (a["unit"], a["pose"]))
    if not os.path.exists(keep):
        shutil.copyfile(dst, keep)
    tmp = dst + ".tmp.webp"
    if gamma == 1.0:
        shutil.copyfile(keep, tmp)
    else:
        _ffmpeg("-i", keep, "-vf", "eq=gamma=%.2f:saturation=1.05" % gamma, "-c:v", "libwebp", "-quality", "90", tmp)
    os.replace(tmp, dst)
    st = load_state()
    if gamma == 1.0:
        st.get("pic_lifts", {}).pop(row_id, None)
    else:
        st.setdefault("pic_lifts", {})[row_id] = gamma
    F.save_state(st)
    print("lift %s gamma %.2f -> %s (L* %.1f, was %.1f)" % (row_id, gamma, a["from_file"], pic_lstar(dst), pic_lstar(keep)))


def sheet(names, out, cols=4, size=420):
    """A contact sheet of pictures (ffmpeg xstack), for looking at a stage's candidates side by side."""
    ins, flt, layout = [], "", []
    for i, p in enumerate(names):
        ins += ["-i", p]
        flt += ("[%d]scale=%d:%d:force_original_aspect_ratio=decrease,pad=%d:%d:(ow-iw)/2:(oh-ih)/2:color=0x808080[s%d];"
                % (i, size, size, size, size, i))
        layout.append("%d_%d" % ((i % cols) * size, (i // cols) * size))
    flt += "".join("[s%d]" % i for i in range(len(names)))
    flt += "xstack=inputs=%d:layout=%s:fill=0x808080" % (len(names), "|".join(layout)) if len(names) > 1 else "null"
    _ffmpeg(*ins, "-filter_complex", flt, "-frames:v", "1", out)
    return out


def strips(names, poses=POSES, out=None, h=300):
    """Ludo's four snapshots of each model (rows: the families' poses) side by side, `h` px tall, for the review."""
    man = manifest_rows()
    rows_ = []
    for name in names:
        for pose in poses:
            snaps = sorted(glob.glob(os.path.join(ROOT, man["model_%s_%s" % (name, pose)]["out"] + "_snap*.*")))
            if snaps:
                rows_.append(snaps[:4])
    if not rows_:
        sys.exit("no snapshots for %s" % names)
    os.makedirs(F.SCRATCH, exist_ok=True)
    out = out or os.path.join(F.SCRATCH, "_".join(names)[:60] + "_" + "_".join(poses) + "_strips.png")
    ins, flt, rowl = [], "", []
    n = 0
    for ri, snaps in enumerate(rows_):
        parts = []
        for s_ in snaps:
            ins += ["-i", s_]
            flt += ("[%d]scale=-2:%d,format=rgba[a%d];color=c=0xC8C8C8:s=%dx%d[g%d];[g%d][a%d]overlay=(W-w)/2:0:"
                    "shortest=1[s%d];" % (n, h, n, h, h, n, n, n, n))
            parts.append("[s%d]" % n)
            n += 1
        flt += "".join(parts) + "hstack=%d[row%d];" % (len(snaps), ri)
        rowl.append("[row%d]" % ri)
    flt += "".join(rowl) + ("vstack=%d" % len(rowl) if len(rowl) > 1 else "null")
    _ffmpeg(*ins, "-filter_complex", flt, "-frames:v", "1", out)
    print(out)
    return out


def figure_box(path, size=256, tol=34):
    """The figure's bounding box in a pick (plain light grey ground): (x0, y0, x1, y1) in the picture's own pixels."""
    raw = subprocess.run([F.FF, "-loglevel", "error", "-i", path, "-vf", "scale=%d:%d" % (size, size), "-f", "rawvideo",
                          "-pix_fmt", "rgb24", "pipe:1"], capture_output=True, check=True).stdout
    w0 = h0 = None
    probe = subprocess.run([F.FF, "-i", path], capture_output=True, text=True).stderr
    import re
    m = re.search(r"(\d{3,5})x(\d{3,5})", probe.split("Video:")[-1])
    w0, h0 = int(m.group(1)), int(m.group(2))
    xs0, ys0, xs1, ys1 = size, size, -1, -1
    for y in range(size):
        row = raw[y * size * 3:(y + 1) * size * 3]
        for x in range(size):
            r, g, b = row[x * 3], row[x * 3 + 1], row[x * 3 + 2]
            if abs(r - 212) + abs(g - 212) + abs(b - 212) > tol:
                if x < xs0:
                    xs0 = x
                if x > xs1:
                    xs1 = x
                if y < ys0:
                    ys0 = y
                if y > ys1:
                    ys1 = y
    return (int(xs0 * w0 / size), int(ys0 * h0 / size), int((xs1 + 1) * w0 / size), int((ys1 + 1) * h0 / size))


def ruler(pairs, out, cols=4, size=420, vertical=True):
    """The picks of (family, pose) pairs, each cropped to the figure's bounding box with a line at every 10% of its
    height (a lying pose: of its length, vertical lines) numbered 0 at the top / left, for reading off where the head
    top sits (the staging's READING table). Needs ffmpeg with drawtext."""
    ins, flt, layout = [], "", []
    font = "/System/Library/Fonts/Supplemental/Arial.ttf"
    for i, (name, pose) in enumerate(pairs):
        pth = os.path.join(ROOT, pick_of(name, pose))
        x0, y0, x1, y1 = figure_box(pth)
        w, h = x1 - x0, y1 - y0
        lying = pose in LYING
        ins += ["-i", pth]
        lines = ""
        for k in range(1, 10):
            if lying:
                lines += ",drawbox=x=iw*%.1f:y=0:w=2:h=ih:color=red@0.7:t=fill,drawtext=fontfile=%s:text=%d:x=w*%.1f+3:y=4:fontsize=22:fontcolor=red" % (
                    k / 10.0, font, k, k / 10.0)
            else:
                lines += ",drawbox=x=0:y=ih*%.1f:w=iw:h=2:color=red@0.7:t=fill,drawtext=fontfile=%s:text=%d:x=4:y=h*%.1f-24:fontsize=22:fontcolor=red" % (
                    k / 10.0, font, k, k / 10.0)
        flt += "[%d]crop=%d:%d:%d:%d%s,scale=%d:%d:force_original_aspect_ratio=decrease,pad=%d:%d:(ow-iw)/2:(oh-ih)/2:color=0x808080[s%d];" % (
            i, w, h, x0, y0, lines, size, size, size, size, i)
        layout.append("%d_%d" % ((i % cols) * size, (i // cols) * size))
    flt += "".join("[s%d]" % i for i in range(len(pairs)))
    flt += "xstack=inputs=%d:layout=%s:fill=0x808080" % (len(pairs), "|".join(layout)) if len(pairs) > 1 else "null"
    _ffmpeg(*ins, "-filter_complex", flt, "-frames:v", "1", out)
    return out


# -------------------------------------------------------------------------------------------- portraits
## Alex's art is already a portrait at the head: each family's portrait is the head and shoulders of its cutout
## (exact pixels, no Ludo call), laid on the M1 portrait backdrop (radial #333052 -> #1C1B2A, as asc-3d-paths'
## portrait_backdrop) and fitted to 384x512 like the shipped portraits. name: (x, y, w, h of the crop in the cutout, 3:4;
## flip: the figure looks right, the series looks left).
PORTRAIT_CROPS = {
    "sunspears": (10, 0, 340, 453, True),
    "seraphs": (110, 0, 540, 720, False),
    "iron_knights": (190, 0, 380, 507, True),
    "iron_colossus": (320, 0, 360, 480, False),
    "briarwardens": (330, 0, 440, 587, False),
    "bloodtuskers": (200, 0, 440, 587, True),
    "bloodsworn": (40, 0, 430, 573, False),
}
def portrait_path(name):
    """Where the family's portrait goes in the game: the transformation's variant portrait (Art.variant_portrait) or
    the new unit's own (Art finds it by unit id)."""
    return P.portrait_path(faction_of(name), P.vkey(name) if name in P.VARIANTS else name)


def crop_portrait(name):
    """The family's cutout cropped, flipped when it looks right, fitted to 384x512 over the M1 backdrop, as webp q90:
    PORTRAIT_DIR/<name>_crop.webp. The cutout must be there (`run cuts`)."""
    x, y, w, h, flip = PORTRAIT_CROPS[name]
    src = os.path.join(ROOT, PIC_CAND, name + "_cut_c1.png")
    if not os.path.exists(src):
        sys.exit("no cutout for %s (run `run cuts --only %s`)" % (name, name))
    dst = os.path.join(ROOT, PORTRAIT_DIR, name + "_crop.webp")
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    cx, cy = 192, 0.45 * 512  ## the backdrop's centre; its outer colour at the farthest corner
    rr = math.hypot(max(cx, 384 - cx), max(cy, 512 - cy))
    d = "min(1,hypot(X-%.1f,Y-%.1f)/%.1f)" % (cx, cy, rr)
    geq = "geq=r='%d+(%d-%d)*%s':g='%d+(%d-%d)*%s':b='%d+(%d-%d)*%s'" % (
        P.GRAD_IN[0], P.GRAD_OUT[0], P.GRAD_IN[0], d, P.GRAD_IN[1], P.GRAD_OUT[1], P.GRAD_IN[1], d,
        P.GRAD_IN[2], P.GRAD_OUT[2], P.GRAD_IN[2], d)
    _ffmpeg("-f", "lavfi", "-i", "color=c=black:s=384x512,format=rgb24", "-i", src, "-filter_complex",
            "[0]%s[bg];[1]format=rgba,crop=%d:%d:%d:%d%s,scale=384:512:flags=lanczos[fg];[bg][fg]overlay=0:0:format=auto,"
            "format=rgb24" % (geq, w, h, x, y, ",hflip" if flip else ""), "-frames:v", "1", "-c:v", "libwebp", "-quality",
            "90", dst)
    print("portrait %-14s %s" % (name, os.path.relpath(dst, ROOT)))
    return dst


# ----------------------------------------------------------------------------------------- texture levels
## Image-to-3D bakes a colour map that is darker than its picture when the picture is dark (Alex's art is: black crystal
## stone, a black wolf, crimson hide), and the board's cel shader (fig_lift aside) shows a dark map as a black shape.
## asc-3d-paths measured it (`texlevels`) and lifted a crushed map with a gamma curve (`retexture`): the same here, in
## stdlib and ffmpeg (no Pillow, no numpy). L* is CIE lightness; a model's is its colour map sampled at each triangle's UV
## centroid, weighted by the triangle's area (so unused atlas space never counts); a picture's is its figure's.
TEX_TOLERANCE = 8.0  ## a model's mean L* may sit this far under its picture's before it is lifted
TEX_TARGET_GAP = -4.0  ## a lifted model lands this far under its picture's (as asc-3d-paths' retexture --auto)
TEX_DARK = 30.0  ## only a dark model is lifted: a bright one (the gold armour) is as Ludo drew it, however far under its picture


def _lstar_rgb(rgb):
    lin = [(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4) for c in rgb]
    y = 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2]
    return 116 * y ** (1.0 / 3.0) - 16 if y > 216 / 24389 else y * 24389 / 27


def _raw_rgb(path, size, extra=""):
    return subprocess.run([F.FF, "-loglevel", "error", "-i", path, "-vf", "scale=%d:%d%s" % (size, size, extra), "-f",
                           "rawvideo", "-pix_fmt", "rgb24", "pipe:1"], capture_output=True, check=True).stdout


def glb_uvs(path):
    """Every vertex's first UV set of a GLB (stdlib), in the order F.glb_mesh gives its positions."""
    js, binc = glb_slim.read_glb(path)
    out = []
    for mesh in js["meshes"]:
        for prim in mesh["primitives"]:
            a = js["accessors"][prim["attributes"]["TEXCOORD_0"]]
            v = js["bufferViews"][a["bufferView"]]
            off = v.get("byteOffset", 0) + a.get("byteOffset", 0)
            stride = v.get("byteStride", 8)
            out += [struct.unpack_from("<2f", binc, off + k * stride) for k in range(a["count"])]
    return out


def tex_lstar(path, gamma=None, tmp=None):
    """A model's mean L* as it is drawn (see above). With `gamma`, as it would be drawn with its colour map lifted by it
    (ffmpeg eq gamma, the map decoded at 512 px)."""
    pos, tris, img = F.glb_mesh(path)
    uvs = glb_uvs(path)
    tmp = tmp or (path + ".lstar.tmp")
    with open(tmp, "wb") as f:
        f.write(img)
    try:
        raw = _raw_rgb(tmp, 512, (",eq=gamma=%.4f:saturation=%.2f" % (gamma, LIFT_SATURATION)) if gamma else "")
    finally:
        os.remove(tmp)
    w = 512
    tot = wsum = 0.0
    for a, b, c in tris:
        pa, pb, pc = pos[a], pos[b], pos[c]
        u = (pb[0] - pa[0], pb[1] - pa[1], pb[2] - pa[2])
        v = (pc[0] - pa[0], pc[1] - pa[1], pc[2] - pa[2])
        cr = (u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0])
        area = math.sqrt(cr[0] ** 2 + cr[1] ** 2 + cr[2] ** 2)
        x = min(w - 1, max(0, int((((uvs[a][0] + uvs[b][0] + uvs[c][0]) / 3.0) % 1.0) * (w - 1))))
        y = min(w - 1, max(0, int((((uvs[a][1] + uvs[b][1] + uvs[c][1]) / 3.0) % 1.0) * (w - 1))))
        i = (y * w + x) * 3
        tot += _lstar_rgb((raw[i] / 255.0, raw[i + 1] / 255.0, raw[i + 2] / 255.0)) * area
        wsum += area
    return tot / max(wsum, 1e-12)


def pic_lstar(path, size=256):
    """A pick's mean L* over the figure: the pixels a flood fill from the border cannot reach through ground-grey ones
    (a pixel is ground when it is within 40 of the corner colour, summed over r, g, b), so a white armour inside its
    outline counts and the grey around it does not."""
    raw = _raw_rgb(path, size)
    px = lambda x, y: raw[(y * size + x) * 3:(y * size + x) * 3 + 3]  # noqa: E731
    corners = [px(0, 0), px(size - 1, 0), px(0, size - 1), px(size - 1, size - 1)]
    bg = [sum(c[i] for c in corners) / 4.0 for i in range(3)]

    def ground(x, y):
        q = px(x, y)
        return abs(q[0] - bg[0]) + abs(q[1] - bg[1]) + abs(q[2] - bg[2]) <= 40

    seen = bytearray(size * size)
    stack = [(x, 0) for x in range(size)] + [(x, size - 1) for x in range(size)] + [(0, y) for y in range(size)] + \
        [(size - 1, y) for y in range(size)]
    while stack:
        x, y = stack.pop()
        if x < 0 or y < 0 or x >= size or y >= size or seen[y * size + x]:
            continue
        if not ground(x, y):
            continue
        seen[y * size + x] = 1
        stack += [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
    tot = n = 0
    for y in range(size):
        for x in range(size):
            if not seen[y * size + x]:
                q = px(x, y)
                tot += _lstar_rgb((q[0] / 255.0, q[1] / 255.0, q[2] / 255.0))
                n += 1
    return tot / max(n, 1)


LIFT_SATURATION = 1.1


def _lift_gamma_for(src, target, tmp):
    """The gamma (1..4) that brings a raw GLB's mean L* to `target` (bisection over tex_lstar)."""
    lo, hi = 1.0, 4.0
    for _ in range(9):
        mid = (lo + hi) / 2.0
        if tex_lstar(src, mid, tmp) < target:
            lo = mid
        else:
            hi = mid
    return round((lo + hi) / 2.0, 3)


def lift_glb(src, dst, gamma):
    """The GLB's base colour image passed through ffmpeg's eq (gamma, saturation LIFT_SATURATION) into dst as a
    lossless PNG, every buffer view repacked (glb_slim then encodes the map as JPEG). The geometry is untouched."""
    js, binc = glb_slim.read_glb(src)
    views = js["bufferViews"]
    ti = js["materials"][0]["pbrMetallicRoughness"]["baseColorTexture"]["index"]
    img = js["images"][js["textures"][ti]["source"]]
    vi = img["bufferView"]
    v = views[vi]
    data = binc[v.get("byteOffset", 0):v.get("byteOffset", 0) + v["byteLength"]]
    with tempfile.TemporaryDirectory() as td:
        a, b = os.path.join(td, "in.img"), os.path.join(td, "out.png")
        with open(a, "wb") as f:
            f.write(data)
        _ffmpeg("-i", a, "-vf", "eq=gamma=%.4f:saturation=%.2f" % (gamma, LIFT_SATURATION), "-frames:v", "1", b)
        with open(b, "rb") as f:
            new = f.read()
    img["mimeType"] = "image/png"
    out = bytearray()
    for i, view in enumerate(views):
        start = view.get("byteOffset", 0)
        piece = new if i == vi else binc[start:start + view["byteLength"]]
        while len(out) % 4:
            out.append(0)
        view["byteOffset"] = len(out)
        view["byteLength"] = len(piece)
        out += piece
    if js.get("buffers"):
        js["buffers"][0]["byteLength"] = len(out)
    glb_slim.write_glb(dst, js, bytes(out))


def reference_pick(a):
    """The picture a model is held to: its pick, or, where the pick was lifted before modelling (`lift`), the original
    kept beside the candidates (the lift would otherwise inflate the target)."""
    keep = os.path.join(ROOT, PIC_CAND, "%s_%s_before_lift.webp" % (a["unit"], a["pose"]))
    return keep if os.path.exists(keep) else os.path.join(ROOT, a["from_file"])


def needs_lift(model_lstar, picture_lstar):
    """A dark model well under its picture (see TEX_*)."""
    return model_lstar < TEX_DARK and model_lstar < picture_lstar - TEX_TOLERANCE


def levels(only=None):
    """Every model row with a GLB: its mean L* against its picture's (and the lift `retexture --auto` would give it)."""
    man = manifest_rows()
    lifts = load_state().get("lifts", {})
    for rid, a in man.items():
        if a["kind"] != "model3d" or (only and not any(o in rid for o in only)):
            continue
        src = os.path.join(ROOT, a["out"] + ".glb")
        pick = os.path.join(ROOT, a["from_file"])
        if not (os.path.exists(src) and os.path.exists(pick)):
            continue
        key = "%s_%s" % (a["unit"], a["pose"])
        tl, pl = tex_lstar(src), pic_lstar(reference_pick(a))
        note = ""
        if key in lifts:
            note = "  lifted gamma %.2f" % lifts[key]
        elif needs_lift(tl, pl):
            note = "  LIFT (auto gamma %.2f)" % _lift_gamma_for(src, pl + TEX_TARGET_GAP, src + ".lstar.tmp")
        print("%-26s model L* %5.1f  picture L* %5.1f  gap %+5.1f%s" % (rid, tl, pl, tl - pl, note))


def retexture_auto(only=None):
    """`retexture` for every model row with a GLB that needs_lift (and undoes the lift of one that no longer does)."""
    for rid, a in manifest_rows().items():
        if a["kind"] != "model3d" or (only and not any(o in rid for o in only)):
            continue
        src = os.path.join(ROOT, a["out"] + ".glb")
        if not os.path.exists(src):
            continue
        if needs_lift(tex_lstar(src), pic_lstar(reference_pick(a))):
            retexture(a["unit"], a["pose"])
        elif "%s_%s" % (a["unit"], a["pose"]) in load_state().get("lifts", {}):
            retexture(a["unit"], a["pose"], 1.0)


def retexture(name, pose, gamma=None):
    """Lift a model's colour map (the raw Ludo GLB's, always from the start, so it is repeatable): `gamma` (1 undoes a
    lift), or by default the gamma that brings its mean L* to its picture's + TEX_TARGET_GAP. Recorded in the state
    (`lifts`) so `stage` applies it; run `stage` after."""
    a = manifest_rows()["model_%s_%s" % (name, pose)]
    src = os.path.join(ROOT, a["out"] + ".glb")
    pl = pic_lstar(reference_pick(a))
    before = tex_lstar(src)
    if gamma is None:
        gamma = _lift_gamma_for(src, pl + TEX_TARGET_GAP, src + ".lstar.tmp") if before < pl + TEX_TARGET_GAP else 1.0
    st = load_state()
    if gamma == 1.0:
        st.get("lifts", {}).pop("%s_%s" % (name, pose), None)
    else:
        st.setdefault("lifts", {})["%s_%s" % (name, pose)] = gamma
    F.save_state(st)
    print("retexture %s %s: gamma %.3f, L* %.1f -> %.1f (picture %.1f)" % (
        name, pose, gamma, before, tex_lstar(src, gamma if gamma != 1.0 else None, src + ".lstar.tmp"), pl))


# --------------------------------------------------------------------------------------------- staging
def stage_dir():
    return os.path.join(ROOT, GLB_CAND, "_stage")


def staged_path(name, pose):
    return os.path.join(stage_dir(), FAMILIES[name]["side"], "%s_%s.glb" % (name, pose))


def stage_records_path():
    return os.path.join(stage_dir(), "stage.json")


def load_stage_state():
    p = stage_records_path()
    return _jload(p) if os.path.exists(p) else {}


def save_stage_state(rec):
    os.makedirs(stage_dir(), exist_ok=True)
    tmp = stage_records_path() + ".tmp"
    with open(tmp, "w") as f:
        json.dump(rec, f, indent=1, sort_keys=True)
    os.replace(tmp, stage_records_path())


def stage(name, pose, frac=None):
    """A model row's raw Ludo GLB slimmed (glb_slim --albedo-only) and measured, into the review batch's staging
    folder; what the install will put in the game (size and all) is recorded with it (stage.json). `frac` is the
    reviewed share of the height (a lying figure: of its length) that is the body, as P.install's; READING has it."""
    a = manifest_rows()["model_%s_%s" % (name, pose)]
    src = os.path.join(ROOT, a["out"] + ".glb")
    if not os.path.exists(src):
        sys.exit("no GLB for %s (run `run models --only %s`)" % (a["id"], name))
    dst = staged_path(name, pose)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    gamma = load_state().get("lifts", {}).get("%s_%s" % (name, pose))
    if gamma:  ## a dark colour map lifted first (`retexture`), from the raw GLB every time
        lifted = dst + ".lift.glb"
        lift_glb(src, lifted, gamma)
        before, after = glb_slim.slim(lifted, dst, 3, a["slim_max"], True)
        os.remove(lifted)
    else:
        before, after = glb_slim.slim(src, dst, 3, a["slim_max"], True)
    st = load_stage_state()
    if frac is None:
        frac = READING.get((name, pose))
    m = F.measure(dst)
    lying = pose in LYING
    f = frac or (m["long_frac"] if lying else m["body_frac"])
    body = body_of_family(name)
    rec = {"lift": gamma or 1.0, "frac": round(f, 3), "men": round(body / f, 3), "axis": "length" if lying else "height",
           "faces": m["faces"], "bytes": after, "extent": m["size"], "measured_frac": m["long_frac"] if lying else m["body_frac"]}
    st.setdefault(name, {})[pose] = rec
    save_stage_state(st)
    print("stage %-26s %.2f -> %.2f MB, %d faces, extent %s, body %.3f (measured %.3f) -> %s %.3f men" % (
        a["id"], before / 1e6, after / 1e6, m["faces"], m["size"], f, rec["measured_frac"], rec["axis"], rec["men"]))
    return rec


# ------------------------------------------------------------------------------------------ the batch
def _side_title(name):
    return SIDES[FAMILIES[name]["side"]]


def display_name(name):
    return entry_of(name)["name"] if name in P.VARIANTS else name.replace("_", " ").title()


def pick_text(name, pose):
    """What the item's text says about where its model came from: Alex's art (or the Briarwarden's picture, for the
    Thornthrowers) for the ready pose, the pose line the picture was edited with for the others."""
    fam = FAMILIES[name]
    if pose == "ready":
        if fam["art"]:
            return "Modelled from Alex's art, assets/_concept/lore/%s: %s." % (fam["art"], fam["note"])
        return "No art of Alex's for this one: %s." % fam["note"]
    text = "Ready picture edited to: the same figure, now %s." % fam[pose]
    if (name, pose) in REDO:
        text += " Redone on Alex's 10-8 note: \"%s\"." % REDO[(name, pose)]
    return text


def build_sidecar(only=None):
    """review.py from-folder's prompts.json for every staged model: group (the side), label, the text (where the
    picture came from), the target (what the game has now) and the meta Install accepted reads. `only`: a set of
    (family, pose)."""
    side = {}
    for name in FAMILIES:
        for pose in POSES:
            p = staged_path(name, pose)
            if not os.path.exists(p) or (only is not None and (name, pose) not in only):
                continue
            rec = load_stage_state()[name][pose]
            rel = "%s/%s_%s.glb" % (FAMILIES[name]["side"], name, pose)
            side[rel] = {
                "group": FAMILIES[name]["side"],
                "label": "%s · %s" % (display_name(name), pose),
                "prompt": pick_text(name, pose),
                "target": model_target(name, pose),
                "meta": {"row": "model_%s_%s" % (name, pose), "family": name, "pose": pose,
                         "descriptor_group": group_of(name), "side": _side_title(name),
                         "size": {"axis": rec["axis"], "men": rec["men"]}, "body_share": rec["frac"],
                         "art": FAMILIES[name]["art"], "faces": rec["faces"]},
            }
    return side


ACTIONS = [
    {"id": "install", "kind": "install", "label": "Install accepted",
     "help": "Copy the accepted models into assets/models/, update assets/models/models.json and the board rows of "
             "world3d/models.json, then re-import in Godot",
     "cmd": ["python3", "tools/ludo/asc_3d_grok.py", "install", "--batch", REVIEW_BATCH],
     "options": [{"flag": "--dry-run", "label": "Dry run", "type": "bool", "default": False,
                  "help": "say what would change and write nothing"}]},
]


def batch(name=REVIEW_BATCH, title="M4 looks: transformation models from Alex's Grok art", only=None):
    """review/<name> from the staged models: review.py from-folder (grouped by side, the item targets the current
    model paths), then the install action added to its batch.json. Run again after more models are staged: new files
    are added, changed files are refreshed in place (their verdicts then ask for another look), verdicts are kept.
    The `install` action's batch argument is `name`. `only` (a set of (family, pose)) makes a batch of just those
    models, from a folder of copies of them (the redo's review/m4_redo)."""
    rv = os.path.join(ROOT, "tools", "review", "review.py")
    bdir = os.path.join(ROOT, "review", name)
    side = build_sidecar(only)
    if not side:
        sys.exit("nothing staged yet (run `stage <family>`)")
    folder = stage_dir()
    if only is not None:
        folder = os.path.join(os.path.dirname(stage_dir()), "_stage_" + name)
        shutil.rmtree(folder, ignore_errors=True)
        for rel in side:
            os.makedirs(os.path.dirname(os.path.join(folder, rel)), exist_ok=True)
            shutil.copy2(os.path.join(stage_dir(), rel), os.path.join(folder, rel))
    sc = os.path.join(folder, "prompts.json")
    with open(sc, "w") as f:
        json.dump(side, f, indent=1)
    cmd = [sys.executable, rv, "from-folder", folder, name, "--title", title, "--group-by", "folder",
           "--recursive", "--sidecar", sc]
    if os.path.exists(os.path.join(bdir, "batch.json")):
        cmd.append("--add")
    subprocess.run(cmd, check=True, cwd=ROOT)
    ## refresh what changed since the batch copied it, and rewrite the items' text / meta from the sidecar
    bj = os.path.join(bdir, "batch.json")
    data = _jload(bj)
    for it in data["items"]:
        rel = it["file"]
        src = os.path.join(folder, rel)
        dst = os.path.join(bdir, rel)
        if os.path.exists(src) and (not os.path.exists(dst) or not filecmp.cmp(src, dst, shallow=False)):
            shutil.copy2(src, dst)
            print("refreshed", rel)
        e = side.get(rel)
        if e:
            it["meta"] = e["meta"]
            it["target"] = e["target"]
            it["text"] = e["prompt"]
            it["label"] = e["label"]
    data["actions"] = [dict(a, cmd=a["cmd"][:-1] + [name]) for a in ACTIONS]
    tmp = bj + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    os.replace(tmp, bj)
    print("batch %s: %d items, actions %s" % (name, len(data["items"]), [a["id"] for a in data["actions"]]))


# ------------------------------------------------------------------------------------- the base batch and the redo (#179)
BASE_ACTIONS = [
    {"id": "install", "kind": "install", "label": "Install accepted bases",
     "help": "Copy the base pictures you marked Good (or Good with changes) over the ready pictures the poses are made "
             "from (assets/_concept/grok3d/, review.py apply)",
     "cmd": ["python3", "tools/review/review.py", "apply", BASE_BATCH],
     "options": [{"flag": "--dry-run", "label": "Dry run", "type": "bool", "default": False}]},
    {"id": "regen", "kind": "regen", "label": "Redo rejected",
     "help": "Redo the rejected base pictures with Ludo (0.5 credit a take, this round's cap); the poses and models of "
             "a family wait until its base is Good",
     "cmd": ["python3", "tools/ludo/asc_3d_grok.py", "regen-base"], "spends": True},
]


def base_items():
    """One item per base row that has candidates: the family's ready picture, the takes of the redo."""
    man = manifest_rows()
    items = []
    for r in rows():
        if r["stage"] != "base":
            continue
        a = man[r["id"]]
        cands = F.cand_files(a)
        if not cands:
            continue
        name = r["unit"]
        title = display_name(name)
        items.append({"id": "%s_ready" % name, "label": "%s ready (the base)" % title, "group": title,
                      "text": r["prompt"], "target": r["pick_to"], "sources": sorted(cands),
                      "meta": {"row": r["id"], "family": name, "v": a.get("v", 1),
                               "context": "the base picture every %s pose and model is made from: Good only when it is "
                                          "right (nothing is built on it before)" % title}})
    return items


def _to_webp(src, dst):
    _ffmpeg("-i", src, "-vf", "scale='min(1024,iw)':'min(1024,ih)':force_original_aspect_ratio=decrease", "-frames:v", "1",
            "-c:v", "libwebp", "-quality", "90", dst)


def base_batch(name=BASE_BATCH):
    """review/<name>: a concept batch of the base pictures (Good / Good with changes / Bad), built from the candidates of
    the base rows. The gate reads its review.json; Install accepted = review.py apply (the take he kept to the ready pick)."""
    items = base_items()
    if not items:
        sys.exit("no base candidates yet (run `run base --only <family>`)")
    n = base_gate.write_base_batch(name, "M4 redo: the base pictures (#179), Good before anything is built on them", items,
                                   [dict(a, cmd=a["cmd"][:]) for a in BASE_ACTIONS], _to_webp, root=os.path.join(ROOT, "review"))
    print("review/%s: %d base item(s)" % (name, n))


def regen_base():
    """The base batch's Redo rejected: every rejected (or Good with changes) base is rolled again with its prompt as it is
    now (the notes are printed: edit BASE_REDO with them first), then the batch is rebuilt."""
    sys.path.insert(0, os.path.join(ROOT, "tools", "review"))
    import review as R
    F.ludo.KEY = F.ludo.api_key()
    R.write_rejected(BASE_BATCH)
    rj = _jload(os.path.join(ROOT, "review", BASE_BATCH, "rejected.json"))
    todo = []
    for e in rj:
        row = (e.get("meta") or {}).get("row")
        if row:
            print("rejected %s: %s" % (e["id"], e.get("note") or "(no note)"))
            todo.append(row)
    if not todo:
        print("nothing rejected")
        return
    round_state()
    for row in todo:
        F.reroll(row, "rejected in the Review Table")
    run("base", todo, 2, 2.0)
    base_batch()


def _ledger_max_v(row_id):
    """The highest request-id version this batch's ledger has used for a row (0 when never)."""
    best = 0
    prefix = "ascgrok-%s-v" % row_id
    if os.path.exists(LEDGER):
        with open(LEDGER) as f:
            for line in f:
                line = line.strip()
                if line:
                    rid = json.loads(line).get("request_id") or ""
                    if rid.startswith(prefix) and rid[len(prefix):].isdigit():
                        best = max(best, int(rid[len(prefix):]))
    return best


def _move_to_old(a):
    """A row's candidates (and a model's snapshots) into old/ beside them, as F.reroll does."""
    files = F.cand_files(a) + glob.glob(os.path.join(ROOT, a["out"] + "_snap*"))
    if files:
        olddir = os.path.join(ROOT, os.path.dirname(a["out"]), "old")
        os.makedirs(olddir, exist_ok=True)
        for f in files:
            os.replace(f, os.path.join(olddir, "v%d_%s" % (a.get("v", 1), os.path.basename(f))))


def redo(pairs, why=None):
    """Start a pose over: for each (family, pose) the picture row and the model row get a version no request id has used
    (a new job, not the old one handed back), their candidates and the stale pick go to old/, and what hung on the old
    model is forgotten (its pick, its colour lifts). The new pictures come from `run poses`, which is gated. Safe to run
    again: a version already ahead of the ledger stays."""
    man = manifest_rows()
    st = load_state()
    keep_old = os.path.join(ROOT, PIC_CAND, "old")
    for name, pose in pairs:
        key = "%s_%s" % (name, pose)
        for rid in ("pic_%s" % key, "model_%s" % key):
            a = man[rid]
            st["v"][rid] = max(st["v"].get(rid, 1), _ledger_max_v(rid) + 1)
            st["picks"].pop(rid, None)
            notes = st.setdefault("rerolls", {}).setdefault(rid, [])
            notes.append("redo: %s" % (why or REDO.get((name, pose), "redone")))
            _move_to_old(a)
            if rid.startswith("pic_"):
                stale = os.path.join(ROOT, a["pick_to"])
                if os.path.exists(stale):  ## the pick the rejected model came from: kept beside the candidates, not left to be reused
                    os.makedirs(keep_old, exist_ok=True)
                    shutil.move(stale, os.path.join(keep_old, "%s_before_redo.webp" % key))
        st.get("lifts", {}).pop(key, None)
        st.get("pic_lifts", {}).pop("model_%s" % key, None)
        print("redo %s %s: picture v%d, model v%d" % (name, pose, st["v"]["pic_" + key], st["v"]["model_" + key]))
    F.save_state(st)
    ## F.save_state keeps what is on disk beside what it is given (picks are a union): write the cleared state through
    disk = load_state()
    disk["picks"] = {k: v for k, v in disk.get("picks", {}).items() if k in st["picks"]}
    for k in ("lifts", "pic_lifts"):
        if k in st:
            disk[k] = st[k]
    write_manifest(disk)


def ludo_portrait(k):
    """Candidate k of the Thornthrowers' portrait row fitted to 384x512 (the middle 3:4 of the square picture, scaled),
    PORTRAIT_DIR/thornthrowers_ludo_t<k>.webp. The picture comes back with its own indigo backdrop."""
    src = [c for c in F.cand_files(manifest_rows()["por_thornthrowers"]) if "_c%d." % k in os.path.basename(c)]
    if not src:
        sys.exit("no candidate %d for por_thornthrowers" % k)
    dst = os.path.join(ROOT, PORTRAIT_DIR, "thornthrowers_ludo_t%d.webp" % k)
    _ffmpeg("-i", src[0], "-vf", "crop=iw*0.75:ih:iw*0.09:0,scale=384:512:flags=lanczos", "-frames:v", "1", "-c:v", "libwebp",
            "-quality", "90", dst)
    return dst


PORTRAIT_BATCH = "m4_portraits"
PORTRAIT_ACTIONS = [
    {"id": "install", "kind": "install", "label": "Install accepted",
     "help": "Copy the portraits you marked Good (or Good with changes) over the ones the game has now (assets/portraits/), "
             "then re-import in Godot",
     "cmd": ["python3", "tools/review/review.py", "apply", PORTRAIT_BATCH],
     "options": [{"flag": "--dry-run", "label": "Dry run", "type": "bool", "default": False}]},
]


def portraits_batch(name=PORTRAIT_BATCH):
    """review/<name>: a concept batch of the eight portraits, grouped by side, each item's target the portrait the game
    has now (`0` shows it). Seven are the head and shoulders of Alex's art (crop_portrait); the Thornthrowers, which has
    no art of Alex's, has three Ludo takes styled from the Briarwarden's. Install accepted is review.py apply."""
    rv = os.path.join(ROOT, "tools", "review", "review.py")
    stage_p = os.path.join(ROOT, PORTRAIT_DIR, "_stage")
    shutil.rmtree(stage_p, ignore_errors=True)
    side = {}
    for fam in FAMILIES:
        if fam in PORTRAIT_CROPS:
            files = [(crop_portrait(fam), "")]
        else:
            if not F.cand_files(manifest_rows()["por_thornthrowers"]):
                print("skipped %s: no portrait candidates (run `run portraits`)" % fam)
                continue
            files = [(ludo_portrait(k), "_t%d" % k) for k in (1, 2, 3)]
        for i, (src, suffix) in enumerate(files):
            rel = "%s/%s%s.webp" % (FAMILIES[fam]["side"], fam, suffix)
            dst = os.path.join(stage_p, rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copyfile(src, dst)
            art = FAMILIES[fam]["art"]
            side[rel] = {
                "item": fam, "group": FAMILIES[fam]["side"], "label": display_name(fam),
                "prompt": ("Head and shoulders of Alex's art, assets/_concept/lore/%s (%s), on the portrait backdrop%s." % (
                    art, FAMILIES[fam]["note"], ", turned to face left" if PORTRAIT_CROPS.get(fam, (0, 0, 0, 0, False))[4] else ""))
                if art else ("Ludo, styled from the Briarwarden portrait (no art of Alex's): take %d of 3." % (i + 1)),
                "target": portrait_path(fam),
                "meta": {"family": fam, "art": art, "side": _side_title(fam)}}
    sc = os.path.join(stage_p, "prompts.json")
    with open(sc, "w") as f:
        json.dump(side, f, indent=1)
    bdir = os.path.join(ROOT, "review", name)
    cmd = [sys.executable, rv, "from-folder", stage_p, name, "--title", "M4 portraits: transformation looks from Alex's Grok art",
           "--mode", "concept", "--group-by", "folder", "--recursive", "--sidecar", sc]
    if os.path.exists(os.path.join(bdir, "batch.json")):
        cmd.append("--add")
    subprocess.run(cmd, check=True, cwd=ROOT)
    bj = os.path.join(bdir, "batch.json")
    data = _jload(bj)
    for it in data["items"]:
        for rel in [it["file"]] + [t["file"] for t in it.get("takes", [])]:
            src = os.path.join(stage_p, rel)
            dst = os.path.join(bdir, rel)
            if os.path.exists(src) and (not os.path.exists(dst) or not filecmp.cmp(src, dst, shallow=False)):
                shutil.copy2(src, dst)
                print("refreshed", rel)
    data["actions"] = [dict(a, cmd=a["cmd"][:-1] + [name]) for a in PORTRAIT_ACTIONS]
    tmp = bj + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    os.replace(tmp, bj)
    print("batch %s: %d items" % (name, len(data["items"])))


# ------------------------------------------------------------------------------------------- install
def accepted_items(bdir):
    """The batch's accepted items (review.json verdict `accept`, not regenerated since: the file is no newer than
    when the verdict was given), each with the file the verdict is about (a take's, when one was picked)."""
    data = _jload(os.path.join(bdir, "batch.json"))
    rp = os.path.join(bdir, "review.json")
    rev = _jload(rp).get("items", {}) if os.path.exists(rp) else {}
    out, stale = [], []
    for it in data["items"]:
        e = rev.get(it["id"])
        if not isinstance(e, dict) or e.get("verdict") != "accept":
            continue
        rel = e.get("pick") or it["file"]
        p = os.path.join(bdir, rel)
        if not os.path.exists(p):
            continue
        if e.get("file_mtime") and os.path.getmtime(p) > float(e["file_mtime"]) + 1e-6:
            stale.append(it["id"])
            continue
        out.append((it, p))
    return out, stale


def descriptor_entry(old, it, dst_rel, m, nbytes):
    """The model's row of assets/models/models.json after the install: the old row's identity (path, kind, id, base,
    transformation, name, faction, class, pose) with the new model's size, share, faces, extent and bytes."""
    meta = it["meta"]
    e = dict(old) if old else {}
    for k in ("tex_lift", "notes"):
        e.pop(k, None)
    e["path"] = "res://" + dst_rel
    e["size"] = dict(meta["size"])
    e["body_share"] = meta["body_share"]
    e["body_men"] = body_of_family(meta["family"])
    e["yaw"] = 0.0
    e["hue_keys"] = []
    e["faces"] = m["faces"]
    e["texture"] = entry_of(meta["family"])["tex"]
    e["bytes"] = nbytes
    e["extent"] = m["size"]
    e["notes"] = "Grok art re-roll (#162, %s): %s; sized %s %.3f men (body %.0f%% of it)" % (
        meta.get("art") or "styled from the Briarwarden", it.get("id"), meta["size"]["axis"], meta["size"]["men"],
        100 * meta["body_share"])
    return e


def install(batch_name=REVIEW_BATCH, dry=False, only=None, root=None):
    """Accepted models of review/<batch> into the game. Nothing is touched when `dry`; with `only` (item ids) just
    those. Returns the list of (item id, target) installed (or that would be)."""
    root = root or ROOT
    bdir = os.path.join(root, "review", batch_name)
    items, stale = accepted_items(bdir)
    if only:
        items = [(it, p) for it, p in items if it["id"] in only]
    tag = "[dry-run] " if dry else ""
    for s in stale:
        print("  ! %s was regenerated after its verdict: look at it again, not installed" % s)
    d = F.load_descriptor()
    done = []
    for it, src in items:
        meta = it.get("meta") or {}
        dst_rel = it.get("target")
        if not dst_rel or not meta.get("family"):
            print("  ! %s: no target / family, skipped" % it["id"])
            continue
        dst = os.path.join(root, dst_rel)
        name, pose = meta["family"], meta["pose"]
        key = P.vkey(name) if name in P.VARIANTS else name
        grp = group_of(name)
        old = d.get(grp, {}).get(key, {}).get(pose)
        same = os.path.exists(dst) and filecmp.cmp(src, dst, shallow=False)
        m = F.measure(src)
        old_men = old["size"]["men"] if old else None
        print("  %s%s  %s -> %s%s  %d faces, %s %.3f men%s" % (
            tag, "=" if same else "+", it["id"], dst_rel, "  (unchanged)" if same else "",
            m["faces"], meta["size"]["axis"], meta["size"]["men"],
            "  (was %.3f)" % old_men if old_men is not None else ""))
        if dry:
            done.append((it["id"], dst_rel))
            continue
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        tmp = dst + ".tmp"
        shutil.copyfile(src, tmp)
        os.replace(tmp, dst)
        if not os.path.exists(dst + ".import"):  ## keep an existing model's import (and its uid)
            glb_slim.write_import(dst_rel, root)
        d.setdefault(grp, {}).setdefault(key, {})[pose] = descriptor_entry(old, it, dst_rel, m, os.path.getsize(dst))
        done.append((it["id"], dst_rel))
    if done and not dry:
        F.dump_descriptor(d)
        P.board()
    print("%s%d model(s) %s; %d regenerated since their verdict (not installed)" % (
        tag, len(done), "would be installed" if dry else "installed", len(stale)))
    if done and not dry:
        print("re-import in Godot: $GODOT --headless --path . --import")
    return done


# ------------------------------------------------------------------------------------------------ compare
## Screenshots of every staged model next to the one the game has now, as the board draws figures. The install is tried on
## a scratch copy of the project (the real assets/models/ and world3d/models.json never change): the copy gets
## review/<batch> with every item marked accepted (in the copy only: these are not Alex's verdicts), runs this script's own
## `install` there, and tools/shots/model_compare.gd draws the old model (a copy of what the game had, built by the same
## Models._glb_figure from the old table's row) beside Models.figure_mesh from the installed table.
GODOT = os.environ.get("GODOT", "/Users/coterboat/Downloads/Godot.app/Contents/MacOS/Godot")
COMPARE_EXCLUDE = ("/.git", "/.claude", "/review", "/assets/_concept", "/assets/models/candidates", "*.log")


def merged_row(tb, type_id, variant):
    """world3d/models.gd figure_row(): the row with the variant entry merged over it."""
    row = dict(tb["figures"][type_id])
    v = (row.pop("variants", {}) or {}).get(variant) if variant else None
    if v:
        row.update(v)
    return row


def compare_plan(proj, batch_dir):
    """The shots model_compare.gd draws: one per item of the batch, in the family / pose order."""
    items = {it["meta"]["row"]: it for it in _jload(os.path.join(batch_dir, "batch.json"))["items"]}
    tb = _jload(P.BOARD_TABLE)
    d = F.load_descriptor()
    plan = []
    for name in FAMILIES:
        for pose in POSES:
            it = items.get("model_%s_%s" % (name, pose))
            if not it:
                continue
            v = P.VARIANTS.get(name)
            type_id = v["base"] if v else name
            variant = v["trans"] if v else ""
            row = merged_row(tb, type_id, variant)
            cur_rel = model_target(name, pose)
            key = P.vkey(name) if v else name
            old = d[group_of(name)][key][pose]
            plan.append({"file": "%s_%s.png" % (name, pose), "title": "%s · %s  (%s)" % (
                             display_name(name), pose, SIDES[FAMILIES[name]["side"]]),
                         "type": type_id, "variant": variant, "pose": pose, "faction": faction_of(name),
                         "current_men": old["size"]["men"], "candidate_men": it["meta"]["size"]["men"],
                         "current": {"path": "res://assets/models/_current/%s_%s.glb" % (stem_of(name), pose), "row": row}})
    return plan


def compare(proj=None, out=None, batch_name=REVIEW_BATCH, import_first=True):
    """Scratch copy of the project with the batch installed, then the shots (see above). Returns the output folder."""
    proj = proj or os.path.join(tempfile.gettempdir(), "asc_grok_compare")
    out = out or os.path.join(proj, "shots")
    bdir = os.path.join(ROOT, "review", batch_name)
    if not os.path.exists(os.path.join(bdir, "batch.json")):
        sys.exit("no review batch %s (run `batch`)" % batch_name)
    if os.path.realpath(proj) == os.path.realpath(ROOT) or os.path.realpath(proj).startswith(os.path.realpath(ROOT) + os.sep):
        sys.exit("the scratch project must be outside the repo")
    os.makedirs(proj, exist_ok=True)
    cmd = ["rsync", "-a", "--delete"] + sum((["--exclude", e] for e in COMPARE_EXCLUDE), []) + [ROOT + "/", proj + "/"]
    subprocess.run(cmd, check=True)
    ## what the game has now, kept as _current/ (the installs below overwrite the real names in the copy)
    cur = os.path.join(proj, "assets", "models", "_current")
    shutil.rmtree(cur, ignore_errors=True)
    os.makedirs(cur)
    data = _jload(os.path.join(bdir, "batch.json"))
    for it in data["items"]:
        fam, pose = it["meta"]["family"], it["meta"]["pose"]
        shutil.copyfile(os.path.join(ROOT, it["target"]), os.path.join(cur, "%s_%s.glb" % (stem_of(fam), pose)))
    ## the batch with every item accepted, in the copy only
    pb = os.path.join(proj, "review", batch_name)
    shutil.rmtree(pb, ignore_errors=True)
    shutil.copytree(bdir, pb, ignore=shutil.ignore_patterns("review.json", "runs.log", "rejected.json"))
    rev = {}
    for it in data["items"]:
        rev[it["id"]] = {"verdict": "accept", "note": "", "file_mtime": os.path.getmtime(os.path.join(pb, it["file"]))}
    with open(os.path.join(pb, "review.json"), "w") as f:
        json.dump({"items": rev}, f)
    ## the install, run by the copy's own script (its ROOT is the copy)
    subprocess.run([sys.executable, os.path.join(proj, "tools", "ludo", "asc_3d_grok.py"), "install", "--batch", batch_name],
                   check=True, cwd=proj)
    plan = compare_plan(proj, bdir)
    plan_path = os.path.join(proj, "compare_plan.json")
    with open(plan_path, "w") as f:
        json.dump(plan, f, indent=1)
    if import_first:
        subprocess.run([GODOT, "--headless", "--path", proj, "--import"], check=True, capture_output=True)
    os.makedirs(out, exist_ok=True)
    subprocess.run([GODOT, "--path", proj, "--always-on-top", "--resolution", "1600x800", "-s",
                    "res://tools/shots/model_compare.gd", "--", "--plan=" + plan_path, "--out=" + out], check=True)
    print("compare shots in", out)
    return out


def compare_sheets(shots, outdir=None):
    """One sheet per side (its two families x four poses), 2 columns of 800 px shots, from compare's output."""
    outdir = outdir or shots
    for side in SIDES:
        files = [os.path.join(shots, "%s_%s.png" % (n, pose)) for n, f in FAMILIES.items() if f["side"] == side
                 for pose in POSES]
        files = [f for f in files if os.path.exists(f)]
        if not files:
            continue
        ins, flt, layout = [], "", []
        for i, f in enumerate(files):
            ins += ["-i", f]
            flt += "[%d]scale=800:400[s%d];" % (i, i)
            layout.append("%d_%d" % ((i % 2) * 800, (i // 2) * 400))
        flt += "".join("[s%d]" % i for i in range(len(files))) + "xstack=inputs=%d:layout=%s" % (len(files), "|".join(layout))
        out = os.path.join(outdir, "sheet_%s.png" % side)
        _ffmpeg(*ins, "-filter_complex", flt, "-frames:v", "1", out)
        print(out)


# --------------------------------------------------------------------------------------------- cost / cli
def cost():
    tot = {}
    for r in rows():
        endpoint = {"edit": "/assets/image/edit", "styled": "/assets/image/style", "image": "/assets/image",
                    "model3d": "/assets/3d-model", "cutout": "/assets/image/remove-background"}[r["kind"]]
        tot[r["stage"]] = tot.get(r["stage"], 0) + F.PRICE[endpoint] * r.get("n", 1)
    for k, v in tot.items():
        print("%-8s %6.1f credits" % (k, v))
    print("%-8s %6.1f credits (a full pass of every row; the round %s stops at %.0f, the batch's #162 budget was %.0f)" % (
        "total", sum(tot.values()), ROUND, CAP, BATCH_CAP))


def _opts(argv):
    opt, rest = {}, []
    i = 0
    while i < len(argv):
        if argv[i].startswith("--"):
            nxt = argv[i + 1] if i + 1 < len(argv) and not argv[i + 1].startswith("--") else None
            opt[argv[i][2:]] = nxt if nxt is not None else True
            i += 2 if nxt is not None else 1
        else:
            rest.append(argv[i])
            i += 1
    return opt, rest


def main(argv):
    if not argv:
        print(__doc__)
        return
    cmd = argv[0]
    opt, rest = _opts(argv[1:])
    if cmd == "manifest":
        write_manifest()
    elif cmd == "cost":
        cost()
    elif cmd == "account":
        F.ludo.KEY = F.ludo.api_key()
        print("account credits available %.1f (shared); this batch has spent %.2f in all, %.2f of the round %s's %.0f" % (
            float(F.ludo.account().get("available", 0.0)), ledger_spent(), ledger_spent(ROUND), ROUND, CAP))
    elif cmd == "spent":
        print("%.2f of the round %s's %.0f credits (the batch in all: %.2f)" % (ledger_spent(ROUND), ROUND, CAP, ledger_spent()))
    elif cmd == "crops":
        crops()
    elif cmd == "ready":
        ready(rest[0], int(opt.get("k", 1)))
    elif cmd == "run":
        if not os.path.exists(MANIFEST):
            write_manifest()
        only = opt.get("only", "").split(",") if opt.get("only") else []
        run(rest[0], only, int(opt.get("jobs", 2)), float(opt.get("hours", 6)))
    elif cmd == "pick":
        pick(rest[0], int(rest[1]), bool(opt.get("deshadow")))
    elif cmd == "reroll":
        F.reroll(rest[0], " ".join(rest[1:]))
    elif cmd == "strip":
        F.strip(rest[0])
    elif cmd == "strips":
        ## strips [--poses ready,march] [--out file] <family> ...
        strips(rest, tuple(opt["poses"].split(",")) if "poses" in opt else POSES, opt.get("out"))
    elif cmd == "lift":
        lift_pick(rest[0], float(rest[1]))
    elif cmd == "levels":
        levels(rest or None)
    elif cmd == "retexture":
        if not rest:
            retexture_auto()
        for r in rest:
            retexture(r.split(":")[0], r.split(":")[1], float(opt["gamma"]) if "gamma" in opt else None)
    elif cmd == "portraits":
        for n in (rest or PORTRAIT_CROPS):
            crop_portrait(n)
    elif cmd == "ruler":
        ## ruler <out.png> <family:pose> ...
        ruler([tuple(x.split(":")) for x in rest[1:]], rest[0], int(opt.get("cols", 4)))
    elif cmd == "sheet":
        sheet(rest[1:], rest[0])
    elif cmd == "stage":
        for r in rest:
            if r.startswith("model_"):
                a = manifest_rows()[r]
                stage(a["unit"], a["pose"], float(opt["frac"]) if "frac" in opt else None)
            else:
                for pose in POSES:
                    stage(r, pose)
    elif cmd == "compare":
        sh = compare(opt.get("proj"), opt.get("out"), opt.get("batch", REVIEW_BATCH), "no-import" not in opt)
        compare_sheets(sh)
    elif cmd == "portraits-batch":
        portraits_batch(opt.get("batch", PORTRAIT_BATCH))
    elif cmd == "batch":
        ## batch [--name N] [--title T] [--only family:pose,...]
        only = {tuple(x.split(":")) for x in opt["only"].split(",")} if opt.get("only") else None
        batch(opt.get("name", REVIEW_BATCH), opt.get("title", "M4 looks: transformation models from Alex's Grok art"), only)
    elif cmd == "base-batch":
        base_batch(opt.get("name", BASE_BATCH))
    elif cmd == "base-status":
        base_status()
    elif cmd == "regen-base":
        regen_base()
    elif cmd == "redo":
        ## redo family:pose ...  (a pose started over, see redo())
        redo([tuple(x.split(":")) for x in rest], opt.get("why") if isinstance(opt.get("why"), str) else None)
    elif cmd == "install":
        install(opt.get("batch", REVIEW_BATCH), bool(opt.get("dry-run")),
                set(opt["only"].split(",")) if opt.get("only") else None)
    else:
        print(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
