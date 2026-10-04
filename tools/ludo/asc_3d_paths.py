#!/usr/bin/env python3
"""asc-3d-paths: M4's art in 3D (issue #73, with #72's prompt rows; design/M4_ASCENSION.md §4 and §12,
STYLE_BIBLE.md §5): the four transformations' looks of their changed units (Sunspears, Iron Knights,
Thornthrowers, Bloodtuskers), the four new units (Seraphs, the Iron Colossus, Briarwardens, Bloodsworn),
each a four-pose model family (ready / march / strike / fallen), and the eight portraits.

It reuses tools/ludo/asc_3d_factions.py's machinery (the Ludo driver with its credit cap, retries and
ledger; picks, re-rolls, Ludo's snapshot strips; GLB measuring and slimming) under its own batch: the
generated manifest is tools/ludo/batches/asc-3d-paths.json and every charged call is a line of
studio/ledgers/asc-3d-paths.jsonl.

    python3 tools/ludo/asc_3d_paths.py manifest            # (re)write the batch manifest
    python3 tools/ludo/asc_3d_paths.py cost                # what each stage plans to spend
    python3 tools/ludo/asc_3d_paths.py run variants [--jobs 2] [--only sunspears]
    python3 tools/ludo/asc_3d_paths.py pick <row> <k> [--deshadow]     # candidate k (1..n) is the pick
    python3 tools/ludo/asc_3d_paths.py run newbases        # new units' base pictures, styled from the fork's variant
    python3 tools/ludo/asc_3d_paths.py run newposes        # their march / strike / fallen edits
    python3 tools/ludo/asc_3d_paths.py run cutouts --only cut_seraphs_ready   # removeBackground of a pick
    python3 tools/ludo/asc_3d_paths.py flatten cut_seraphs_ready              # ... laid back on plain grey
    python3 tools/ludo/asc_3d_paths.py lift pic_bloodtuskers_ready 1.5        # a dark pick's values lifted
    python3 tools/ludo/asc_3d_paths.py run portraits       # variant portraits (edits of the base portrait)
    python3 tools/ludo/asc_3d_paths.py pick-portrait <row> <k> [--zoom Z] [--dx F] [--dy F] [--top F]   # Pillow
    python3 tools/ludo/asc_3d_paths.py run portraits2      # new units' portraits, styled from the variant's
    python3 tools/ludo/asc_3d_paths.py run models          # every picked picture to a GLB
    python3 tools/ludo/asc_3d_paths.py strip <model row>   # its 4 Ludo snapshots side by side (review)
    python3 tools/ludo/asc_3d_paths.py reroll <row> <why>  # a new take: v+1, old candidates to old/
    python3 tools/ludo/asc_3d_paths.py install <model row> [--frac F | --men M | --like-base] [--notes T]
    python3 tools/ludo/asc_3d_paths.py board               # this batch's rows of world3d/models.json, surgically
    python3 tools/ludo/asc_3d_paths.py gates               # silhouette IoU of every variant picture (needs Pillow)
    python3 tools/ludo/asc_3d_paths.py texlevels [rows]    # each model's mean L* against its picture's (Pillow, numpy)
    python3 tools/ludo/asc_3d_paths.py retexture <rows> --auto | --gamma G   # lift a crushed colour map (no Ludo call)
    python3 tools/ludo/asc_3d_paths.py sheet units|portraits|silhouettes   # the sheets (Pillow; units, silhouettes: numpy)
    python3 tools/ludo/asc_3d_paths.py account

Variants are edits, so they keep the base's outline (STYLE_BIBLE §5, IoU >= 0.85): each of the base
unit's four picked pictures (assets/_concept/<faction>/<unit>_<pose>.webp, from asc-3d-factions) is
edited with the fork's transformation block, verbatim. New units are generateWithStyle with the fork's
picked variant picture as the style image (§5 rule 3), so a Crown unit is anchored to a Crown picture and
a Clans unit to a Clans one (the leak rule); their poses are edits of their picked base picture (C-pose).
Portraits: a variant is an editImage of the base portrait with the block, a new unit is generateWithStyle
from its fork's variant portrait (M4 §12.1).

Where things go:
- picks: assets/_concept/<faction>/<unit>__<transformation id>_<pose>.webp (variants) and
  <unit>_<pose>.webp (new units), committed pipeline inputs, as in asc-3d-factions;
- models: assets/models/units/<faction>/<unit>__<transformation id>_<pose>.glb (variants) and
  <unit>_<pose>.glb (new units), each with a row in assets/models/models.json (groups "variants" and
  "units");
- the board: world3d/models.json. A new unit's row gets its models like any unit's. A variant goes in an
  optional "variants" object on its base unit's row, {"<transformation id>": {"model", "height", "poses",
  "pose_size"}}, which world3d/models.gd ignores until the board swaps to it when a transformation lands.
  `board` edits only this batch's rows, line by line, so rows another job changed stay as they are;
- portraits: assets/portraits/<faction>/<unit id>.webp (new units: Art finds them by unit id) and
  assets/portraits/<faction>/<unit>__<transformation id>.webp (variants: Art.variant_portrait).

Discipline as asc-3d-factions (studio/ludo-playbook.md): the cap is checked before every submit as
`balance_before - available + planned` (CAP below is this batch's stop line, under the job's 500 cap); a
failed job is free but burns its request id, so a retry bumps `v`; candidates and raw GLBs stay in the
gitignored candidates/ folders; every input goes to Ludo as base64 from a local file.
Stdlib plus ffmpeg for generating and installing; `pick-portrait`, `gates` and `sheet` need Pillow.
"""
import json
import math
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import asc_3d_factions as F  # noqa: E402  (the driver, picks, measuring, slimming)
import glb_slim  # noqa: E402

ROOT = F.ROOT
BATCH = "asc-3d-paths"
MANIFEST = os.path.join(ROOT, "tools", "ludo", "batches", BATCH + ".json")
LEDGER = os.path.join(ROOT, "studio", "ledgers", BATCH + ".jsonl")
## The job's cap is 500 credits; the batch stops (and reports) above 450.
CAP = 450.0
PIC_CAND = "assets/_concept/candidates/paths"
GLB_CAND = "assets/models/candidates/paths"
BOARD_TABLE = os.path.join(ROOT, "world3d", "models.json")

# ------------------------------------------------------------------------------ transformation blocks
## STYLE_BIBLE §5, verbatim (T-thornwild: M4_ASCENSION §12.1).
T_BLOCKS = {
    "celestial": "Remake the armour and shield as white-gold radiant armour with a soft ring of pale light behind the "
                 "head, same pose, same outline, same weapon and shield, same coloured plume and trim.",
    "ironform": "Remake the armour, shield and skin as dark riveted living iron with thin glowing orange seams, same "
                "pose, same outline, same weapon and shield, same coloured plume and trim.",
    "thornwild": "Remake the fur, hide and armour as living bark and green moss with small thorned briars and a few "
                 "fresh leaves, same pose, same outline, same weapon, same coloured warpaint and trim.",
    "bloodpact": "Remake the skin and armour in crimson and black with small bone spurs and glowing red eyes, same "
                 "pose, same outline, same weapon and shield, same coloured plume and trim.",
}
## What a 3D concept edit keeps besides (asc-3d-factions' framing: plain light grey, room on every side).
KEEP_PIC = "Same plain flat light grey background, the whole figure in view with wide empty margin on every side."
KEEP_PORTRAIT = "Same framing, same thick clean outline and flat cel colours, same deep indigo background."
## STYLE_BIBLE §6.1 C-portrait, verbatim.
C_PORTRAIT = ("Cel-shaded portrait of bright high fantasy: head and shoulders, three-quarter view facing left, face in "
              "the upper half of the frame, thick clean dark outline, flat saturated colours with one hard shadow tone "
              "and one highlight tone, bold simple shapes, plain softly graded deep indigo background.")

# ---------------------------------------------------------------------------------------- variants
## name: the base unit (asc_3d_factions.UNITS), the transformation (data/paths.gd), its block.
VARIANTS = {
    "sunspears": dict(base="spearmen", trans="crown_celestial_host", block="celestial", name="Sunspears"),
    "iron_knights": dict(base="knights", trans="crown_living_iron", block="ironform", name="Iron Knights"),
    "thornthrowers": dict(base="fangthrowers", trans="beasts_thorn_wild", block="thornwild", name="Thornthrowers"),
    "bloodtuskers": dict(base="tuskers", trans="beasts_blood_pact", block="bloodpact", name="Bloodtuskers"),
}
for _v in VARIANTS.values():
    _u = F.UNITS[_v["base"]]
    _v.update(faction=_u["faction"], body=_u["body"], faces=_u["faces"], tex=_u["tex"], cls=_u["cls"])


def vkey(name):
    """A variant's key everywhere it is stored: "<base unit>__<transformation id>"."""
    v = VARIANTS[name]
    return "%s__%s" % (v["base"], v["trans"])


# --------------------------------------------------------------------------------------- new units
## id (data/paths.gd NEW_UNITS): faction, transformation, the variant whose picture is the style image,
## body height (men, the head top), faces, the subject (after C-model), the three other poses (C-pose),
## the portrait subject (after C-portrait). Sizes against the existing figures (world3d/models.json):
## a spearman stands 1.0 men to the head, a tusker 1.2, a knight 1.45, the Great Thornmane 2.8.
NEW = {
    "seraphs": dict(
        faction="kingdom", trans="crown_celestial_host", style="sunspears", body=1.15, faces=8000, tex=512,
        cls="infantry (winged)",
        subject="an Aurel Crown seraph of the Celestial Host, a tall winged human warrior in white-gold radiant plate "
                "armour with a soft ring of pale light behind the head, an open gold-trimmed steel helm with a blue "
                "plume, a short royal-blue tabard with gold trim, two large white feathered wings spread wide and "
                "raised up and out from his shoulders, standing in a relaxed A-pose with his feet apart, holding a "
                "gold-hilted longsword point-up in his right hand at arm's length out to his side with clear space "
                "between the sword and his body, his left arm held a little out from his side, calm fierce "
                "expression, eyes ahead",
        march="striding forward with his left leg ahead, the longsword resting on his right shoulder, the white wings "
              "half-folded behind him, eyes ahead",
        strike="lunging forward on his bent left leg, slashing the longsword in a big diagonal swing, the white wings "
               "spread wide and raised high behind him, a battle cry",
        fallen="fallen in battle, lying flat on his back on the floor with his arms out to the sides, the white wings "
               "folded closely against his sides, his helmet still on, the longsword lying on the floor beside him, "
               "eyes closed",
        portrait="A seraph of the Aurel Crown's Celestial Host, a noble human warrior in white-gold radiant armour with "
                 "a soft ring of pale light behind the head, an open gold-trimmed helm with a blue plume, large white "
                 "feathered wings rising behind the shoulders, the gold hilt of a longsword at the shoulder, calm "
                 "fierce expression, eyes looking to the left"),
    "iron_colossus": dict(
        faction="kingdom", trans="crown_living_iron", style="iron_knights", body=1.75, faces=8000, tex=512,
        cls="monster (construct)",
        subject="an Aurel Crown iron colossus of Living Iron, a towering walking giant built of dark riveted living "
                "iron plates with thin glowing orange seams between them, a broad barrel chest, massive arms and legs, "
                "a heavy great helm with a narrow glowing orange visor slit and a blue plume, a royal-blue tabard with "
                "gold trim hanging over its waist, standing in a relaxed A-pose with its feet apart, gripping a huge "
                "iron warhammer in its right hand held low and out to its side with clear space between the hammer and "
                "its body, its left arm held a little out from its side",
        march="striding forward with its left leg ahead, the iron warhammer resting on its right shoulder, its left "
              "fist swinging",
        strike="smashing down with the iron warhammer held high over its head in both hands, leaning forward",
        fallen="toppled in battle, lying flat on its back on the floor with its arms out to the sides, the iron "
               "warhammer lying on the floor beside it, the glow of its visor dimmed",
        portrait="An iron colossus of the Aurel Crown's Living Iron, a towering walking giant of dark riveted living "
                 "iron plates with thin glowing orange seams, a heavy great helm with a narrow glowing orange visor "
                 "slit and a blue plume, a royal-blue tabard with gold trim over its iron chest, the iron head of a "
                 "huge warhammer resting on its shoulder, looking to the left"),
    "briarwardens": dict(
        faction="beasts", trans="beasts_thorn_wild", style="thornthrowers", body=1.45, faces=8000, tex=512,
        cls="monster (heavy infantry)",
        subject="a Thornmane briarwarden of the Thorn Wild, a huge hulking stag-headed beastman grown from living bark "
                "and green moss, broad branching antlers of dark wood with a few fresh leaves, small thorned briars "
                "wound around its arms and legs, crimson war-paint stripes on its face and chest, a bone necklace, "
                "thick root-like feet, standing in a relaxed A-pose with its feet apart, gripping a huge gnarled "
                "tree-trunk club studded with thorns in its right hand held low and out to its side with clear space "
                "between the club and its body, its left arm held a little out from its side, calm stern expression, "
                "eyes ahead",
        march="striding forward with its left leg ahead, the tree-trunk club resting on its right shoulder, its left "
              "arm swinging, eyes ahead",
        strike="smashing down with the tree-trunk club held high over its head in both hands, leaning forward, mouth "
               "open in a roar",
        fallen="fallen in battle, lying flat on its back on the floor with its arms out to the sides, the tree-trunk "
               "club lying on the floor beside it, eyes closed",
        portrait="A briarwarden of the Thornmane Clans' Thorn Wild, a huge stag-headed beastman grown from living bark "
                 "and green moss, broad branching antlers of dark wood with a few fresh leaves, small thorned briars "
                 "wound around its shoulders, crimson war-paint stripes on its face, a bone necklace, calm stern "
                 "expression, eyes looking to the left"),
    "bloodsworn": dict(
        faction="beasts", trans="beasts_blood_pact", style="bloodtuskers", body=1.1, faces=5000, tex=512,
        cls="infantry",
        subject="a Thornmane bloodsworn of the Blood Pact, a lean savage black-furred hyena-headed beastman in crimson "
                "and black hide armour with small bone spurs on the shoulders, forearms and knees, glowing red eyes, "
                "crimson war paint across the muzzle, a ragged crimson sash, standing in a relaxed A-pose with his "
                "feet apart, holding a long curved bone blade in each hand, both held low and out to his sides with "
                "clear space between the blades and his body, snarling hungry expression, eyes ahead",
        march="loping forward with his left leg ahead, a curved bone blade in each hand held low at his sides, eyes "
              "ahead",
        strike="leaping forward in a savage lunge, slashing with both bone blades, the right blade raised high and the "
               "left blade thrust forward, mouth open in a snarl",
        fallen="fallen in battle, lying flat on his back on the floor with his arms out to the sides, the two bone "
               "blades lying on the floor beside him, eyes closed",
        portrait="A bloodsworn of the Thornmane Clans' Blood Pact, a lean savage black-furred hyena-headed beastman, "
                 "crimson and black hide armour with small bone spurs on the shoulders, glowing red eyes, crimson war "
                 "paint across the muzzle, a curved bone blade raised at the shoulder, snarling hungry expression, eyes "
                 "looking to the left"),
}
POSES = F.POSES
LYING = F.LYING

## Picture fixes: an edit of a pick, when image-to-3D turns something in it into the wrong shape (the
## Sunspears' march halo, a big soft glow, came back as a solid disc behind the back twice; the ready
## pose's thinner ring came back as a ring). row id -> (the pick's row, the edit line).
FIXES = {
    "fix_sunspears_march": ("pic_sunspears_march",
                            "Make the soft ring of pale light behind the head a thin solid gold ring around the head, "
                            "the same figure in the same pose with everything else the same."),
}


def portrait_path(faction, name):
    return "assets/portraits/%s/%s.webp" % (faction, name)


# ---------------------------------------------------------------------------------------- the rows
def rows():
    """Every row of the batch in run order. Picture rows roll `n` candidates; model rows read a pick."""
    out = []
    pick = F.pick_path
    ## variants: each of the base's picked pictures edited with the fork's block
    for name, v in VARIANTS.items():
        for pose in POSES:
            out.append({"id": "pic_%s_%s" % (name, pose), "stage": "variants", "kind": "edit",
                        "n": 3 if pose == "ready" else 2,
                        "from_file": pick(v["faction"], "%s_%s" % (v["base"], pose)),
                        "prompt": "%s %s" % (T_BLOCKS[v["block"]], KEEP_PIC),
                        "pick_to": pick(v["faction"], "%s_%s" % (vkey(name), pose)), "group": "variants",
                        "unit": name, "pose": pose})
    ## new units: generateWithStyle from the fork's picked variant picture, then C-pose edits
    for uid, u in NEW.items():
        style = VARIANTS[u["style"]]
        out.append({"id": "pic_%s_ready" % uid, "stage": "newbases", "kind": "styled", "n": 3,
                    "style_file": pick(u["faction"], "%s_ready" % vkey(u["style"])),
                    "prompt": "%s Subject: %s." % (F.C_MODEL, u["subject"]),
                    "pick_to": pick(u["faction"], uid + "_ready"), "group": "units", "unit": uid, "pose": "ready",
                    "anchor": style["name"]})
        for pose in POSES[1:]:
            view = F.VIEW_LYING if pose in LYING else F.VIEW
            out.append({"id": "pic_%s_%s" % (uid, pose), "stage": "newposes", "kind": "edit", "n": 2,
                        "from_file": pick(u["faction"], uid + "_ready"),
                        "prompt": F.C_POSE.format(pose=u[pose], view=view),
                        "pick_to": pick(u["faction"], "%s_%s" % (uid, pose)), "group": "units", "unit": uid,
                        "pose": pose})
    ## fixes: an edit of a pick (FIXES), back into the same pick
    for fid, (src_row, line) in FIXES.items():
        src = next(r for r in out if r["id"] == src_row)
        out.append({"id": fid, "stage": "fixes", "kind": "edit", "n": 2, "from_file": src["pick_to"],
                    "prompt": "%s %s" % (line, KEEP_PIC), "pick_to": src["pick_to"], "group": src["group"],
                    "unit": src["unit"], "pose": src["pose"]})
    ## cutouts: the new units' pictures come back as a soft painted render with a soft ground shadow, which
    ## image-to-3D can fuse into a floor slab (Seraphs ready v1); removeBackground, then `flatten` lays
    ## the figure back on the plain grey. Run per row (--only cut_<unit>_<pose>), when a pick needs it.
    for uid, u in NEW.items():
        for pose in POSES:
            out.append({"id": "cut_%s_%s" % (uid, pose), "stage": "cutouts", "kind": "cutout", "n": 1,
                        "from_file": pick(u["faction"], "%s_%s" % (uid, pose)),
                        "pick_to": pick(u["faction"], "%s_%s" % (uid, pose)), "group": "units", "unit": uid,
                        "pose": pose})
    ## portraits: a variant edits the base portrait; a new unit is styled from its fork's variant portrait
    for name, v in VARIANTS.items():
        out.append({"id": "por_" + name, "stage": "portraits", "kind": "edit", "n": 3, "image_type": "portrait",
                    "from_file": portrait_path(v["faction"], v["base"]),
                    "prompt": "%s %s" % (T_BLOCKS[v["block"]], KEEP_PORTRAIT),
                    "pick_to": portrait_path(v["faction"], vkey(name)), "group": "portraits", "unit": name})
    for uid, u in NEW.items():
        out.append({"id": "por_" + uid, "stage": "portraits2", "kind": "styled", "n": 3, "image_type": "portrait",
                    "style_file": portrait_path(u["faction"], vkey(u["style"])),
                    "prompt": "%s Subject: %s." % (C_PORTRAIT, u["portrait"]),
                    "pick_to": portrait_path(u["faction"], uid), "group": "portraits", "unit": uid})
    ## models: every ready pose first (what the board shows most), then strike, march, fallen
    for pose in ("ready", "strike", "march", "fallen"):
        for name, v in VARIANTS.items():
            stem = "%s_%s" % (vkey(name), pose)
            out.append({"id": "model_%s_%s" % (name, pose), "stage": "models", "kind": "model3d",
                        "from_file": pick(v["faction"], stem), "faces": v["faces"], "texture_size": 1024,
                        "texture_type": "pbr", "slim_max": v["tex"],
                        "target": "assets/models/units/%s/%s.glb" % (v["faction"], stem), "group": "variants",
                        "unit": name, "pose": pose, "variant": None})
        for uid, u in NEW.items():
            stem = "%s_%s" % (uid, pose)
            out.append({"id": "model_%s_%s" % (uid, pose), "stage": "models", "kind": "model3d",
                        "from_file": pick(u["faction"], stem), "faces": u["faces"], "texture_size": 1024,
                        "texture_type": "pbr", "slim_max": u["tex"],
                        "target": "assets/models/units/%s/%s.glb" % (u["faction"], stem), "group": "units",
                        "unit": uid, "pose": pose, "variant": None})
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
        "batch": BATCH, "rid_prefix": "ascpath", "cap": CAP, "job_cap": 500.0,
        "note": "Written by tools/ludo/asc_3d_paths.py (which holds the prompts; edit it, not this file). M4's art in "
                "3D (#73, #72): the four transformations' variants of their changed units (edits of the base unit's "
                "picked pictures with the bible §5 block), the four new units (styled from the fork's variant), "
                "4 poses each, and the 8 portraits. Picture rows roll n candidates in one call; picks are copied to "
                "assets/_concept/<faction>/ and assets/portraits/<faction>/; model rows read the pick as base64.",
        "style": {"image": "", "art_style": "Cel-Shaded",
                  "blocks": {"C-model (3D, no base)": F.C_MODEL, "C-pose (no base)": F.C_POSE, "C-portrait": C_PORTRAIT,
                             "keep (3D picture edits)": KEEP_PIC, "keep (portrait edits)": KEEP_PORTRAIT,
                             "T-celestial": T_BLOCKS["celestial"], "T-ironform": T_BLOCKS["ironform"],
                             "T-thornwild": T_BLOCKS["thornwild"], "T-bloodpact": T_BLOCKS["bloodpact"]}},
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
            suffix = {"por": "_portrait", "cut": "_cut", "fix": "_fix"}.get(r["id"].split("_", 1)[0], "")
            a["out"] = PIC_CAND + "/" + r["id"].split("_", 1)[1] + suffix
        man["assets"].append(a)
    os.makedirs(os.path.dirname(MANIFEST), exist_ok=True)
    with open(MANIFEST, "w") as f:
        json.dump(man, f, indent=1)
        f.write("\n")
    return man


## asc_3d_factions' driver, picks and re-rolls read these module globals: point them at this batch.
F.BATCH, F.MANIFEST, F.LEDGER, F.CAP, F.RID = BATCH, MANIFEST, LEDGER, CAP, "ascpath"
F.SCRATCH = os.environ.get("ASC3D_SCRATCH", os.path.join(ROOT, GLB_CAND, "_review"))
F.rows = rows
F.write_manifest = write_manifest
F.load_state = load_state


def manifest_rows():
    return {a["id"]: a for a in json.load(open(MANIFEST))["assets"]}


def flatten(row_id):
    """A cutout row's result laid on the plain light grey of the C-model pictures (#D4D4D4), same canvas, as
    the pick (webp q90). The pick before is kept beside the cutout candidate (`<out>_before.webp`)."""
    a = manifest_rows()[row_id]
    cands = F.cand_files(a)
    if not cands:
        sys.exit("no cutout for %s (run it first)" % row_id)
    dst = os.path.join(ROOT, a["pick_to"])
    keep = os.path.join(ROOT, a["out"] + "_before.webp")
    if not os.path.exists(keep):
        shutil.copyfile(dst, keep)
    tmp = dst + ".tmp.webp"
    F.subprocess.run([F.FF, "-y", "-loglevel", "error", "-i", cands[0], "-filter_complex",
                      "color=c=0xD4D4D4:s=16x16[g];[g][0]scale2ref[g2][f];[g2][f]overlay=0:0:format=auto,format=rgb24",
                      "-frames:v", "1", "-c:v", "libwebp", "-quality", "90", tmp], check=True)
    os.replace(tmp, dst)
    state = load_state()
    state.setdefault("cutouts", {})[row_id] = os.path.relpath(cands[0], ROOT)
    F.save_state(state)
    print("flatten %s -> %s" % (row_id, a["pick_to"]))


def lift(row_id, gamma):
    """A picture pick's values lifted by a gamma (ffmpeg eq, hue kept, saturation +5%), in place, the pick
    before kept beside its candidates (`<out>_before_lift.webp`). For a dark palette that image-to-3D
    crushes to near-black (Bloodtuskers: crimson and black came back at texture mean L* 2-6 against the
    base tusker's 22, three takes): the lifted picture gives the texture back its crimson and grey."""
    a = manifest_rows()[row_id]
    dst = os.path.join(ROOT, a["pick_to"])
    keep = os.path.join(ROOT, a["out"] + "_before_lift.webp")
    if not os.path.exists(keep):
        shutil.copyfile(dst, keep)
    ## a second lift starts again from the kept original, so gammas never stack
    tmp = dst + ".tmp.webp"
    F.subprocess.run([F.FF, "-y", "-loglevel", "error", "-i", keep, "-vf", "eq=gamma=%.2f:saturation=1.05" % gamma,
                      "-c:v", "libwebp", "-quality", "90", tmp], check=True)
    os.replace(tmp, dst)
    state = load_state()
    state.setdefault("lifts", {})[row_id] = gamma
    F.save_state(state)
    print("lift %s gamma %.2f -> %s" % (row_id, gamma, a["pick_to"]))


# ---------------------------------------------------------------------------------------- portraits
## The M1 portrait background (radial #333052 -> #1C1B2A, refit from the shipped portraits: centre at
## (0.5, 0.45) of the frame, the outer colour at the corners).
GRAD_IN, GRAD_OUT = (0x33, 0x30, 0x52), (0x1C, 0x1B, 0x2A)


def portrait_backdrop(w, h):
    from PIL import Image
    cx, cy = 0.5 * w, 0.45 * h
    r = math.hypot(max(cx, w - cx), max(cy, h - cy))
    im = Image.new("RGB", (w, h))
    px = im.load()
    for y in range(h):
        for x in range(w):
            t = min(1.0, math.hypot(x - cx, y - cy) / r)
            px[x, y] = tuple(int(round(GRAD_IN[i] + (GRAD_OUT[i] - GRAD_IN[i]) * t)) for i in range(3))
    return im


def pick_portrait(row_id, k, zoom=1.0, dx=0.0, dy=0.0, top=0.0):
    """Candidate k of a portrait row becomes the shipped portrait: flattened onto the M1 gradient (portrait
    images come back with native alpha), cropped to 3:4 (the full height, centred on the subject, `zoom`
    in about the top-middle, shifted by dx/dy of the crop's size), 384x512 webp q90. `top` adds that share
    of the height as empty headroom first (a styled portrait frames the face high; the series has the
    eyes at 35-41%), only when nothing in the picture touches its top edge."""
    from PIL import Image
    a = manifest_rows()[row_id]
    src = [c for c in F.cand_files(a) if os.path.basename(c).startswith(os.path.basename(a["out"]) + "_c%d." % k)]
    if not src:
        sys.exit("no candidate %d for %s" % (k, row_id))
    im = Image.open(src[0]).convert("RGBA")
    if top > 0.0:
        box0 = im.getchannel("A").getbbox()
        if box0 is None or box0[1] < 3:
            sys.exit("%s touches its top edge: no headroom can be added" % row_id)
        pad = Image.new("RGBA", (im.width, int(round(im.height * (1.0 + top)))), (0, 0, 0, 0))
        pad.paste(im, (0, pad.height - im.height))
        im = pad
    w, h = im.size
    bg = portrait_backdrop(w, h).convert("RGBA")
    bg.alpha_composite(im)
    ## the subject's columns (alpha), for centring a crop from a square picture
    box = im.getchannel("A").getbbox() or (0, 0, w, h)
    ch = h / zoom
    cw = ch * 0.75
    if cw > w:
        cw, ch = w, w / 0.75
    cx = (box[0] + box[2]) / 2 if w / h > 0.8 else w / 2
    x0 = min(max(0, cx - cw / 2 + dx * cw), w - cw)
    y0 = min(max(0, dy * ch), h - ch)
    out = bg.crop((int(x0), int(y0), int(x0 + cw), int(y0 + ch))).convert("RGB").resize((384, 512), Image.LANCZOS)
    dst = os.path.join(ROOT, a["pick_to"])
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    out.save(dst, "WEBP", quality=90)
    state = load_state()
    state.setdefault("picks", {})[row_id] = k
    state.setdefault("portrait_crops", {})[row_id] = {"zoom": zoom, "dx": dx, "dy": dy, "top": top, "src": list(im.size)}
    F.save_state(state)
    print("pick %s c%d -> %s (from %dx%d)" % (row_id, k, a["pick_to"], w, h))


# ------------------------------------------------------------------------------------------ install
def like_base(row_id):
    """A variant pose's size in men: its base pose's reviewed size (asc-3d-factions) times the picked
    variant picture's height against the base picture's (the `gates` ratio; an edit keeps the canvas's
    scale; a lying pose: its width, for the length). Geometry outside the outline the gate measures (the
    Celestial Host's halo ring) needs a ruler reading instead."""
    a = manifest_rows()[row_id]
    v = VARIANTS[a["unit"]]
    base = F.load_descriptor()["units"][v["base"]][a["pose"]]
    g = load_state().get("gates", {}).get("%s_%s" % (a["unit"], a["pose"]))
    if not g:
        sys.exit("run `gates` first")
    ## a lying figure is sized by its length, which the picture's width shows (its height is a plume)
    key = "width" if a["pose"] in LYING else "height"
    return round(base["size"]["men"] * g[key], 3), "sized as the base's %s pose (%.3f men) x the picture's %s " \
        "ratio %.3f" % (a["pose"], base["size"]["men"], key, g[key])


def install(row_id, men=None, frac=None, notes="", like=False):
    """A model row's GLB slimmed (glb_slim --albedo-only), imported, measured and recorded in
    assets/models/models.json: new units in "units", variants in "variants" (keyed "<unit>__<transformation>").
    `frac` is the reviewed share of the height (a lying figure: of its length) that is the body; `men` sets
    the size outright; `like` sizes a variant pose from its base pose (like_base)."""
    if like:
        men, why = like_base(row_id)
        notes = (notes + "; " if notes else "") + why
    a = manifest_rows()[row_id]
    src = os.path.join(ROOT, a["out"] + ".glb")
    dst = os.path.join(ROOT, a["target"])
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    before, after = glb_slim.slim(src, dst, 3, a["slim_max"], True)
    glb_slim.write_import(a["target"], ROOT)
    m = F.measure(dst)
    d = F.load_descriptor()
    pose = a["pose"]
    if a["group"] == "variants":
        v = VARIANTS[a["unit"]]
        key, body = vkey(a["unit"]), v["body"]
        entry = {"path": "res://" + a["target"], "kind": "variant", "id": key, "base": v["base"],
                 "transformation": v["trans"], "name": v["name"], "faction": v["faction"], "class": v["cls"],
                 "pose": pose}
    else:
        u = NEW[a["unit"]]
        key, body = a["unit"], u["body"]
        entry = {"path": "res://" + a["target"], "kind": "unit", "id": key, "faction": u["faction"],
                 "class": u["cls"], "pose": pose, "transformation": u["trans"]}
    if pose in LYING:
        f = frac or m["long_frac"]
        entry["size"] = {"axis": "length", "men": men if men else round(body / f, 3)}
    else:
        f = frac or m["body_frac"]
        entry["size"] = {"axis": "height", "men": men if men else round(body / f, 3)}
    entry["body_share"] = round(f, 3)
    entry["body_men"] = body
    entry["yaw"] = 0.0
    entry["hue_keys"] = []
    entry["faces"] = m["faces"]
    entry["texture"] = a["slim_max"]
    entry["bytes"] = after
    entry["extent"] = m["size"]
    if notes:
        entry["notes"] = notes
    d.setdefault(a["group"], {}).setdefault(key, {})[pose] = entry
    F.dump_descriptor(d)
    print("installed %s: %.2f -> %.2f MB, %d faces, extent %s, body %.2f of height (long %.2f), %s %.3f men" % (
        a["target"], before / 1e6, after / 1e6, m["faces"], m["size"], m["body_frac"], m["long_frac"],
        entry["size"]["axis"], entry["size"]["men"]))
    return entry


# ------------------------------------------------------------------------------- texture levels
## Image-to-3D sometimes returns a colour map far darker than its picture (the Bloodtuskers' crimson and
## black, near-black after three takes). The model is right, only its values are crushed: `retexture` lifts
## the embedded colour map's lightness (CIE L*) with a gamma curve, keeping each texel's chromaticity
## (hue and saturation, in linear light), so the model's mean L* comes back near its picture's. It always
## starts again from the raw Ludo GLB, so it is repeatable, and records what it did in the descriptor
## (`tex_lift`). No Ludo call. Needs Pillow and numpy.
TEX_TOLERANCE = 8.0  ## a model's mean L* may sit this far under its picture's before it is lifted


def _lstar(rgb):
    """CIE L* (D65) of sRGB values in 0..1 (numpy, any shape ending in 3)."""
    import numpy as np
    c = np.asarray(rgb, dtype=np.float64)
    lin = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    y = lin @ np.array([0.2126, 0.7152, 0.0722])
    return np.where(y > 216 / 24389, 116 * np.cbrt(y) - 16, y * 24389 / 27)


def tex_lstar(path):
    """A model's mean L* as it is drawn: its colour map sampled at every triangle's UV centroid, weighted by
    the triangle's surface area, so unused atlas space never counts."""
    import numpy as np
    V, T, C = _glb_faces(path)
    tri = V[T]
    area = np.linalg.norm(np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0]), axis=1)
    return float((_lstar(C) * area).sum() / max(area.sum(), 1e-12))


def pic_lstar(path):
    """A concept picture's mean L* over the figure (the gate's mask: inside the ink outline)."""
    import numpy as np
    from PIL import Image
    m = np.asarray(_mask(path, 256)) > 0
    im = np.asarray(Image.open(path).convert("RGB").resize((256, 256), Image.LANCZOS), dtype=np.float64) / 255.0
    return float(_lstar(im[m]).mean())


def _lift_rgb(rgb, gamma):
    """L' = 100 (L / 100) ^ (1 / gamma) per texel, the texel's linear RGB scaled by Y'/Y, so its chromaticity
    (hue, saturation) is kept; a channel that would pass 1 scales the texel back down."""
    import numpy as np
    c = np.asarray(rgb, dtype=np.float64)
    lin = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    y = lin @ np.array([0.2126, 0.7152, 0.0722])
    L = np.where(y > 216 / 24389, 116 * np.cbrt(y) - 16, y * 24389 / 27)
    L2 = 100.0 * np.clip(L / 100.0, 0, 1) ** (1.0 / gamma)
    f = (L2 + 16) / 116
    y2 = np.where(L2 > 8.0, f ** 3, L2 * 27 / 24389)
    k = np.where(y > 1e-6, y2 / np.maximum(y, 1e-6), 1.0)
    lin2 = lin * k[..., None]
    peak = lin2.max(axis=-1, keepdims=True)
    with np.errstate(divide="ignore", invalid="ignore"):
        lin2 = np.where(peak > 1.0, lin2 / np.maximum(peak, 1e-12), lin2)
    lin2 = np.where(y[..., None] <= 1e-6, y2[..., None], lin2)  ## pure black: a neutral grey of L2
    out = np.where(lin2 <= 0.0031308, lin2 * 12.92, 1.055 * np.power(np.clip(lin2, 0, 1), 1 / 2.4) - 0.055)
    return np.clip(out, 0, 1)


def _gamma_for(colours, weights, target):
    """The gamma that brings the weighted mean L* of `colours` (lifted) to `target` (bisection)."""
    import numpy as np
    lo, hi = 1.0, 4.0
    for _ in range(30):
        mid = (lo + hi) / 2
        L = float((_lstar(_lift_rgb(colours, mid)) * weights).sum() / weights.sum())
        lo, hi = (mid, hi) if L < target else (lo, mid)
    return round((lo + hi) / 2, 3)


def _replace_image(path, out_path, fn):
    """The GLB's base colour image decoded, passed through fn (an RGB uint8 array -> RGB uint8 array) and
    written to out_path as a lossless PNG, every buffer view repacked (glb_slim then encodes it as JPEG)."""
    import io
    import numpy as np
    from PIL import Image
    js, binc = glb_slim.read_glb(path)
    views = js["bufferViews"]
    mat = js["materials"][0]["pbrMetallicRoughness"]["baseColorTexture"]["index"]
    img = js["images"][js["textures"][mat]["source"]]
    vi = img["bufferView"]
    v = views[vi]
    src = binc[v.get("byteOffset", 0):v.get("byteOffset", 0) + v["byteLength"]]
    arr = np.asarray(Image.open(io.BytesIO(src)).convert("RGB"))
    buf = io.BytesIO()
    Image.fromarray(fn(arr)).save(buf, "PNG")
    new = buf.getvalue()
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
    glb_slim.write_glb(out_path, js, bytes(out))


def reference_lstar(a):
    """The L* a model is held to: its picked picture's, or, where that picture was lifted before modelling
    (`lift`, state "lifts"), the original pick's, which the lift would otherwise inflate (kept beside the
    candidates as <out>_before_lift.webp; the descriptor records it). Returns (L*, which)."""
    st = load_state()
    pic_row = "pic_" + a["id"][len("model_"):]
    man = manifest_rows()
    if pic_row in st.get("lifts", {}) and pic_row in man:
        orig = os.path.join(ROOT, man[pic_row]["out"] + "_before_lift.webp")
        if os.path.exists(orig):
            return pic_lstar(orig), "original pick (before its gamma %.1f lift)" % st["lifts"][pic_row]
        d, e = _entry_of(a)
        if "original_pick_lstar" in e.get("tex_lift", {}):
            return float(e["tex_lift"]["original_pick_lstar"]), "original pick (recorded)"
    return pic_lstar(os.path.join(ROOT, a["from_file"])), "picked picture"


def _entry_of(a):
    d = F.load_descriptor()
    key = vkey(a["unit"]) if a["group"] == "variants" else a["unit"]
    return d, d[a["group"]][key][a["pose"]]


def texlevels(rows_only=None):
    """Every installed model of this batch: its mean L* against its picture's (and the base unit's models
    from asc-3d-factions, for calibration), and the gamma `retexture --auto` would use."""
    import numpy as np
    man = manifest_rows()
    out = {}
    ids = [r for r in man if r.startswith("model_") and (not rows_only or r in rows_only)]
    for rid in ids:
        a = man[rid]
        dst = os.path.join(ROOT, a["target"])
        if not os.path.exists(dst):
            continue
        tl, (pl, which) = tex_lstar(dst), reference_lstar(a)
        out[rid] = (tl, pl)
        print("%-30s model L* %5.1f  picture L* %5.1f  gap %+5.1f%s%s" % (rid, tl, pl, tl - pl,
              "  LIFT" if tl < pl - TEX_TOLERANCE else "", "" if which == "picked picture" else "  (" + which + ")"))
    if not rows_only:
        print("calibration (asc-3d-factions, accepted as they are):")
        d = F.load_descriptor()
        for u in ("spearmen", "knights", "fangthrowers", "tuskers"):
            for pose in POSES:
                e = d["units"][u][pose]
                pic = os.path.join(ROOT, F.pick_path(e["faction"], "%s_%s" % (u, pose)))
                tl, pl = tex_lstar(os.path.join(ROOT, e["path"][6:])), pic_lstar(pic)
                print("  %-26s model L* %5.1f  picture L* %5.1f  gap %+5.1f" % (u + " " + pose, tl, pl, tl - pl))
    return out


def retexture(row_id, gamma=None, auto=False, target_gap=-4.0):
    """The model re-slimmed from its raw Ludo GLB, its colour map lifted by `gamma` (or, with auto, the gamma
    that brings its mean L* to its picture's + target_gap), re-imported, and the descriptor entry updated
    (`bytes`, and `tex_lift`: gamma, L* before and after, the picture's L*). gamma 1 undoes a lift."""
    import numpy as np
    a = manifest_rows()[row_id]
    src = os.path.join(ROOT, a["out"] + ".glb")
    dst = os.path.join(ROOT, a["target"])
    glb_slim.slim(src, dst, 3, a["slim_max"], True)
    before = tex_lstar(dst)
    pic, which = reference_lstar(a)
    picked = pic_lstar(os.path.join(ROOT, a["from_file"]))
    if auto:
        V, T, C = _glb_faces(dst)
        tri = V[T]
        w = np.linalg.norm(np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0]), axis=1)
        gamma = _gamma_for(C, w, pic + target_gap) if before < pic + target_gap else 1.0
    gamma = float(gamma or 1.0)
    if gamma != 1.0:
        ## lift the raw, lossless colour map, then slim it as usual (a lifted JPEG would show its blocks)
        tmp = dst + ".lift.glb"
        _replace_image(src, tmp, lambda arr: (_lift_rgb(arr / 255.0, gamma) * 255.0 + 0.5).astype("uint8"))
        glb_slim.slim(tmp, dst, 3, a["slim_max"], True)
        os.remove(tmp)
    if not os.path.exists(dst + ".import"):  ## keep the model's import (and its uid) when it has one
        glb_slim.write_import(a["target"], ROOT)
    after = tex_lstar(dst)
    d, e = _entry_of(a)
    e["bytes"] = os.path.getsize(dst)
    if gamma != 1.0:
        e["tex_lift"] = {"gamma": round(gamma, 3), "lstar_before": round(before, 1), "lstar_after": round(after, 1),
                         "picture_lstar": round(picked, 1)}
        if which != "picked picture":
            e["tex_lift"]["original_pick_lstar"] = round(pic, 1)
    else:
        e.pop("tex_lift", None)
    F.dump_descriptor(d)
    print("retexture %-28s gamma %.3f  L* %5.1f -> %5.1f  (picture %5.1f)" % (row_id, gamma, before, after, pic))
    return before, after, pic


# -------------------------------------------------------------------------------- the board's table
## A new unit's block spacing comes from its row's fallback figure x "scale" (world3d/armies.gd _spacing):
## sized here so a block of the installed figures doesn't overlap. "large" spaces it like a mounted unit.
NEW_ROW = {
    "seraphs": {"scale": 1.9, "large": True},  ## the wings spread 1.8 men: wider apart, so they don't merge
    "iron_colossus": {"scale": 1.7, "large": True},
    "briarwardens": {"scale": 1.45, "large": True},
    "bloodsworn": {"scale": 1.1},
}


def _row_of(poses):
    ready = poses["ready"]
    out = {"model": ready["path"], "height": ready["size"]["men"], "yaw": round(180.0 + math.degrees(ready["yaw"]), 1),
           "poses": {p: poses[p]["path"] for p in POSES if p in poses},
           "pose_size": {p: {"axis": poses[p]["size"]["axis"], "men": poses[p]["size"]["men"]} for p in POSES if p in poses}}
    return out


def board(write=True):
    """This batch's rows of world3d/models.json, and only those: each new unit's row gets its models (and the
    block spacing in NEW_ROW); each changed unit's row gets "variants": {"<transformation id>": {"model",
    "height", "yaw", "poses", "pose_size"}}. Every other line of the file stays byte for byte."""
    d = F.load_descriptor()
    text = open(BOARD_TABLE).read()
    tb = json.loads(text)
    figs = tb["figures"]
    new_rows = {}
    for uid in NEW:
        poses = d.get("units", {}).get(uid, {})
        if "ready" not in poses:
            continue
        row = dict(figs[uid])
        row.update(_row_of(poses))
        row.update(NEW_ROW.get(uid, {}))
        new_rows[uid] = row
    for name, v in VARIANTS.items():
        poses = d.get("variants", {}).get(vkey(name), {})
        if "ready" not in poses:
            continue
        row = dict(new_rows.get(v["base"], figs[v["base"]]))
        vs = dict(row.get("variants", {}))
        vs[v["trans"]] = _row_of(poses)
        row["variants"] = vs
        new_rows[v["base"]] = row
    lines = text.split("\n")
    seen = set()
    in_figs = False
    for i, line in enumerate(lines):
        if line.startswith('\t"figures": {'):
            in_figs = True
            continue
        if in_figs and line.startswith("\t}"):
            break
        if not in_figs:
            continue
        for rid, row in new_rows.items():
            head = '\t\t"%s": ' % rid
            if line.startswith(head):
                comma = "," if line.rstrip().endswith(",") else ""
                lines[i] = head + json.dumps(row, ensure_ascii=False) + comma
                seen.add(rid)
    missing = set(new_rows) - seen
    if missing:
        sys.exit("rows not found in %s: %s" % (BOARD_TABLE, sorted(missing)))
    out = "\n".join(lines)
    json.loads(out)  ## still a valid table
    if write:
        with open(BOARD_TABLE, "w") as f:
            f.write(out)
    for rid in sorted(new_rows):
        print("board row", rid)
    return new_rows


# ------------------------------------------------------------------------------------------- gates
def _mask(path, size=256):
    """The subject's mask of a concept picture (plain light grey ground), at size x size: the figure inside
    its ink outline. Pixels darker than the ground or clearly coloured, with the holes they enclose filled,
    so a soft glow outside the outline (the Celestial Host's halo, a VFX layer in the bible's terms) and
    the ground's grey don't count, and white plate inside the outline does."""
    from PIL import Image, ImageDraw, ImageFilter
    im = Image.open(path).convert("RGB").resize((size, size), Image.LANCZOS)
    w, h = im.size
    bg = tuple(sum(im.getpixel(c)[i] for c in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1))) // 4 for i in range(3))
    bgv = sum(bg) / 3.0
    m = Image.new("L", (w + 2, h + 2), 0)
    px, mp = im.load(), m.load()
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y]
            mx, mn = max(r, g, b), min(r, g, b)
            if (r + g + b) / 3.0 < bgv - 28 or (mx - mn) > 0.35 * mx + 12:
                mp[x + 1, y + 1] = 255
    m = m.filter(ImageFilter.MaxFilter(3))
    ImageDraw.floodfill(m, (0, 0), 128)
    return m.point(lambda v: 0 if v == 128 else 255).crop((1, 1, w + 1, h + 1))


def iou(a, b):
    ma, mb = _mask(a), _mask(b)
    pa, pb = ma.load(), mb.load()
    inter = union = 0
    for y in range(ma.height):
        for x in range(ma.width):
            i, j = pa[x, y] > 0, pb[x, y] > 0
            inter += i and j
            union += i or j
    ba, bb = ma.getbbox(), mb.getbbox()
    hgt = (bb[3] - bb[1]) / max(1, ba[3] - ba[1]) if ba and bb else 0.0
    wid = (bb[2] - bb[0]) / max(1, ba[2] - ba[0]) if ba and bb else 0.0
    return inter / max(1, union), hgt, wid


def gates():
    """STYLE_BIBLE §5's silhouette gate on every picked variant picture against its base: alpha IoU >= 0.85,
    height <= +15%."""
    out = {}
    for name, v in VARIANTS.items():
        for pose in POSES:
            base = os.path.join(ROOT, F.pick_path(v["faction"], "%s_%s" % (v["base"], pose)))
            var = os.path.join(ROOT, F.pick_path(v["faction"], "%s_%s" % (vkey(name), pose)))
            if not os.path.exists(var):
                continue
            j, hgt, wid = iou(base, var)
            out["%s_%s" % (name, pose)] = {"iou": round(j, 3), "height": round(hgt, 3), "width": round(wid, 3),
                                           "pass": j >= 0.85 and hgt <= 1.15}
            print("%-24s IoU %.3f  height %+.1f%%  %s" % ("%s %s" % (name, pose), j, 100 * (hgt - 1),
                                                         "pass" if j >= 0.85 and hgt <= 1.15 else "FAIL"))
    state = load_state()
    state["gates"] = out
    F.save_state(state)
    return out


# ----------------------------------------------------------------------------------- contact sheets
def _glb_faces(path):
    """An installed GLB as numpy arrays for the review renders: vertex positions (node transforms applied),
    triangles, and each triangle's colour (its colour map at the triangle's UV centroid). Needs numpy, Pillow."""
    import io
    import struct
    import numpy as np
    from PIL import Image
    pos, tris, img = F.glb_mesh(path)
    js, binc = glb_slim.read_glb(path)
    views, accs = js["bufferViews"], js["accessors"]
    uvs = []
    for mesh in js["meshes"]:
        for prim in mesh["primitives"]:
            a = accs[prim["attributes"]["TEXCOORD_0"]]
            v = views[a["bufferView"]]
            off = v.get("byteOffset", 0) + a.get("byteOffset", 0)
            stride = v.get("byteStride", 8)
            uvs += [struct.unpack_from("<2f", binc, off + k * stride) for k in range(a["count"])]
    V, T, UV = np.array(pos), np.array(tris), np.array(uvs)
    tex = np.asarray(Image.open(io.BytesIO(img)).convert("RGB"), dtype=np.float32) / 255.0
    h, w = tex.shape[:2]
    fuv = UV[T].mean(axis=1)
    x = np.clip((fuv[:, 0] % 1.0) * (w - 1), 0, w - 1).astype(int)
    y = np.clip((fuv[:, 1] % 1.0) * (h - 1), 0, h - 1).astype(int)
    return V, T, tex[y, x]


def _render(path, men, axis, ppm, yaw=30.0, pitch=20.0, silhouette=False):
    """An orthographic, z-buffered render of an installed GLB at `ppm` pixels per man (sized like the board:
    its `axis` extent is `men` men), turned by `yaw` and seen from `pitch` above; RGBA. Lambert shading of the
    per-face colour, or flat black for the silhouette gate."""
    import math
    import numpy as np
    from PIL import Image
    V, T, C = _glb_faces(path)
    lo, hi = V.min(0), V.max(0)
    ext = {"height": hi[1] - lo[1], "length": max(hi[0] - lo[0], hi[2] - lo[2]),
           "width": max(hi[0] - lo[0], hi[2] - lo[2])}[axis]
    scale = men * ppm / ext
    ry, rp = math.radians(yaw), math.radians(pitch)
    Ry = np.array([[math.cos(ry), 0, math.sin(ry)], [0, 1, 0], [-math.sin(ry), 0, math.cos(ry)]])
    Rx = np.array([[1, 0, 0], [0, math.cos(rp), -math.sin(rp)], [0, math.sin(rp), math.cos(rp)]])
    P = (V - (lo + hi) / 2) @ Ry.T @ Rx.T
    plo, phi = P.min(0), P.max(0)
    W, H = int((phi[0] - plo[0]) * scale) + 6, int((phi[1] - plo[1]) * scale) + 6
    sx, sy, z = (P[:, 0] - plo[0]) * scale + 3, (phi[1] - P[:, 1]) * scale + 3, P[:, 2]
    img = np.zeros((H, W, 4), dtype=np.float32)
    zb = np.full((H, W), -1e9, dtype=np.float32)
    tri = P[T]
    n = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
    n /= np.linalg.norm(n, axis=1, keepdims=True) + 1e-12
    L = np.array([-0.5, 0.8, 0.6]) / np.linalg.norm([-0.5, 0.8, 0.6])
    shade = 0.5 + 0.5 * np.abs(n @ L)
    for k in range(len(T)):
        i0, i1, i2 = T[k]
        xs, ys = np.array([sx[i0], sx[i1], sx[i2]]), np.array([sy[i0], sy[i1], sy[i2]])
        x0, x1 = max(int(xs.min()), 0), min(int(xs.max()) + 1, W - 1)
        y0, y1 = max(int(ys.min()), 0), min(int(ys.max()) + 1, H - 1)
        if x1 < x0 or y1 < y0:
            continue
        gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        d = (ys[1] - ys[2]) * (xs[0] - xs[2]) + (xs[2] - xs[1]) * (ys[0] - ys[2])
        if abs(d) < 1e-9:
            continue
        a = ((ys[1] - ys[2]) * (gx - xs[2]) + (xs[2] - xs[1]) * (gy - ys[2])) / d
        b = ((ys[2] - ys[0]) * (gx - xs[2]) + (xs[0] - xs[2]) * (gy - ys[2])) / d
        m = (a >= -1e-4) & (b >= -1e-4) & (1 - a - b >= -1e-4)
        zz = a * z[i0] + b * z[i1] + (1 - a - b) * z[i2]
        sub = zb[y0:y1 + 1, x0:x1 + 1]
        upd = m & (zz > sub)
        sub[upd] = zz[upd]
        img[y0:y1 + 1, x0:x1 + 1][upd] = (0.08, 0.08, 0.08, 1.0) if silhouette else np.append(np.clip(C[k] * shade[k], 0, 1), 1)
    return Image.fromarray((img * 255).astype(np.uint8), "RGBA")


def silhouette_sheet(out):
    """STYLE_BIBLE §8.2's class gate: every unit of each faction (the base units, the variants, the new units)
    in its ready pose, filled black at 24 px for a man-sized figure from the board's default pitch (about 50°),
    each shown at 1x and blown up 4x (nearest) so it can be read; a reviewer names the class."""
    from PIL import Image, ImageDraw, ImageFont
    BG, INK = (0x1C, 0x1B, 0x2A), (0xF1, 0xEC, 0xE0)
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 14)
        big = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 18)
    except OSError:
        font = big = ImageFont.load_default()
    d = F.load_descriptor()
    rows_ = []
    for fac, units in (("kingdom", ["spearmen", "crossbowmen", "knights", "knight_captain"]),
                       ("beasts", ["tuskers", "fangthrowers", "war_bear", "warchief"])):
        cells = [(u, d["units"][u]["ready"]) for u in units]
        cells += [(VARIANTS[n]["name"], d["variants"][vkey(n)]["ready"]) for n in VARIANTS if VARIANTS[n]["faction"] == fac]
        cells += [(u, d["units"][u]["ready"]) for u in NEW if NEW[u]["faction"] == fac]
        rows_.append((fac, cells))
    renders = [[(name, _render(os.path.join(ROOT, e["path"][6:]), e["size"]["men"], e["size"]["axis"], 24.0, yaw=20.0,
                               pitch=50.0, silhouette=True)) for name, e in cells] for _, cells in rows_]
    cw = max(im.width for row in renders for _, im in row) * 4 + 16
    chh = max(im.height for row in renders for _, im in row) * 4
    W = 14 + max(len(r) for r in renders) * cw
    H = 60 + len(rows_) * (chh + 70)
    sheet = Image.new("RGB", (W, H), BG)
    dr = ImageDraw.Draw(sheet)
    dr.text((14, 14), "asc-3d-paths · the 24 px silhouette gate (bible §8.2): ready poses filled black at 24 px a man, "
                      "50° pitch; each at 1x (left) and 4x", fill=INK, font=big)
    y = 50
    for (fac, _), row in zip(rows_, renders):
        dr.text((14, y), fac, fill=INK, font=big)
        x = 14
        for name, im in row:
            box = Image.new("RGBA", (cw - 8, chh), (0xD8, 0xD8, 0xD8, 255))
            box.alpha_composite(im, (2, chh - im.height - 2))
            big4 = im.resize((im.width * 4, im.height * 4), Image.NEAREST)
            box.alpha_composite(big4, (min(cw - 8 - big4.width, im.width + 8), chh - big4.height))
            sheet.paste(box.convert("RGB"), (x, y + 24))
            dr.text((x, y + 28 + chh), name, fill=INK, font=font)
            x += cw
        y += chh + 70
    sheet.save(out, optimize=True)
    print("%s: %dx%d, %.2f MB" % (out, W, H, os.path.getsize(out) / 1e6))


def contact_sheet(group, out):
    """studio/contact-sheets/asc-3d-paths-<group>.png (STYLE_BIBLE §7).
    units: per fork, the base unit's row then its variant's row (picked picture | a render of the installed
    GLB at the board's size, one scale for every cell, so sizes compare), then the new unit's row; faces, MB,
    size in men and the variant pictures' silhouette IoU under each. Needs Pillow and numpy.
    portraits: per fork, the base portrait | the variant | the new unit, at 384x512 and 96x128."""
    from PIL import Image, ImageDraw, ImageFont
    BG, INK, CELL = (0x1C, 0x1B, 0x2A), (0xF1, 0xEC, 0xE0), (0x28, 0x27, 0x40)
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 15)
        big = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 19)
    except OSError:
        font = big = ImageFont.load_default()
    d = F.load_descriptor()
    man = manifest_rows()
    gate = load_state().get("gates", {})
    forks = [("sunspears", "seraphs"), ("iron_knights", "iron_colossus"), ("thornthrowers", "briarwardens"),
             ("bloodtuskers", "bloodsworn")]
    if group == "portraits":
        W, H = 14 + 3 * (384 + 100 + 30), 70 + len(forks) * (512 + 60)
        sheet = Image.new("RGB", (W, H), BG)
        dr = ImageDraw.Draw(sheet)
        dr.text((14, 14), "asc-3d-paths · portraits · base | variant (editImage + T-block) | new unit (styled from the "
                          "variant) · 384x512 and 96x128", fill=INK, font=big)
        y = 56
        for vname, uid in forks:
            v = VARIANTS[vname]
            cells = [(v["base"], portrait_path(v["faction"], v["base"])), (v["name"], portrait_path(v["faction"], vkey(vname))),
                     (uid, portrait_path(NEW[uid]["faction"], uid))]
            x = 14
            for label, rel in cells:
                p = os.path.join(ROOT, rel)
                if os.path.exists(p):
                    im = Image.open(p).convert("RGB")
                    sheet.paste(im.resize((384, 512)), (x, y + 24))
                    sheet.paste(im.resize((96, 128), Image.LANCZOS), (x + 394, y + 24))
                dr.text((x, y), label, fill=INK, font=big)
                x += 384 + 100 + 30
            y += 512 + 60
        sheet.save(out, optimize=True)
        print("%s: %dx%d, %.2f MB" % (out, W, H, os.path.getsize(out) / 1e6))
        return
    rows_ = []
    for vname, uid in forks:
        v = VARIANTS[vname]
        cells = []
        for pose in POSES:
            e = d.get("units", {}).get(v["base"], {}).get(pose)
            a = {"from_file": F.pick_path(v["faction"], "%s_%s" % (v["base"], pose)), "pose": pose}
            cells.append((a, e, ""))
        rows_.append((v["base"] + " (base)", cells))
        cells = []
        for pose in POSES:
            a = man.get("model_%s_%s" % (vname, pose))
            e = d.get("variants", {}).get(vkey(vname), {}).get(pose)
            g = gate.get("%s_%s" % (vname, pose))
            cells.append((a, e, ("IoU %.2f" % g["iou"]) if g else ""))
        rows_.append(("%s (%s)" % (v["name"], v["trans"]), cells))
        cells = []
        for pose in POSES:
            a = man.get("model_%s_%s" % (uid, pose))
            e = d.get("units", {}).get(uid, {}).get(pose)
            cells.append((a, e, ""))
        rows_.append(("%s (new, styled from %s)" % (uid, v["name"]), cells))
    PW, CH, PPM = 200, 250, 100.0  ## the render: 100 px a man for every cell (a 2.4-men figure fills it)
    cw = PW + CH + 12
    W = 14 + 4 * (cw + 12)
    H = 70 + len(rows_) * (CH + 62)
    sheet = Image.new("RGB", (W, H), BG)
    dr = ImageDraw.Draw(sheet)
    dr.text((14, 14), "asc-3d-paths · units · picked picture | the installed model at the board's size (100 px a man, "
                      "line = 1 man) · faces · MB · size in men", fill=INK, font=big)
    y = 56
    for name, cells in rows_:
        dr.text((14, y), name, fill=INK, font=big)
        x = 14
        for a, e, extra in cells:
            box = Image.new("RGB", (cw, CH), CELL)
            if a is not None:
                pic = os.path.join(ROOT, a["from_file"])
                if os.path.exists(pic):
                    im = Image.open(pic).convert("RGB")
                    im.thumbnail((PW, CH))
                    box.paste(im, ((PW - im.width) // 2, (CH - im.height) // 2))
            if e is not None:
                im = _render(os.path.join(ROOT, e["path"][6:]), e["size"]["men"], e["size"]["axis"], PPM)
                if im.width > CH or im.height > CH:
                    im.thumbnail((CH, CH))
                g = Image.new("RGBA", (CH, CH), (0xC8, 0xC8, 0xC8, 255))
                g.alpha_composite(im, ((CH - im.width) // 2, CH - im.height - 4))
                gd = ImageDraw.Draw(g)
                gd.line([(4, CH - 4 - PPM), (14, CH - 4 - PPM)], fill=(200, 30, 30, 255), width=2)
                box.paste(g.convert("RGB"), (PW + 12, 0))
            sheet.paste(box, (x, y + 26))
            label = (a or {}).get("pose") or ""
            if e:
                label += "  %d faces · %.2f MB · %s %.2f" % (e["faces"], e["bytes"] / 1e6, e["size"]["axis"][0], e["size"]["men"])
            else:
                label += "  (not installed)"
            if extra:
                label += " · " + extra
            dr.text((x, y + 30 + CH), label, fill=INK, font=font)
            x += cw + 12
        y += CH + 62
    sheet = sheet.quantize(colors=256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    sheet.save(out, optimize=True)
    print("%s: %dx%d, %.2f MB" % (out, W, H, os.path.getsize(out) / 1e6))


def cost():
    tot = {}
    for r in rows():
        endpoint = {"edit": "/assets/image/edit", "styled": "/assets/image/style", "image": "/assets/image",
                    "model3d": "/assets/3d-model", "cutout": "/assets/image/remove-background"}[r["kind"]]
        tot[r["stage"]] = tot.get(r["stage"], 0) + F.PRICE[endpoint] * r.get("n", 1)
    for k, v in tot.items():
        print("%-10s %6.1f credits" % (k, v))
    print("%-10s %6.1f credits (stop line %.0f, job cap 500)" % ("total", sum(tot.values()), CAP))


def main(argv):
    if not argv:
        print(__doc__)
        return
    cmd = argv[0]
    opt, rest = {}, []
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
        F.ludo.KEY = F.ludo.api_key()
        print("credits available %.1f" % F.account())
    elif cmd == "run":
        if not os.path.exists(MANIFEST):
            write_manifest()
        only = opt.get("only", "").split(",") if opt.get("only") else []
        F.run(rest[0], only, int(opt.get("jobs", 2)), float(opt.get("hours", 6)))
    elif cmd == "pick":
        F.pick(rest[0], int(rest[1]), None, bool(opt.get("deshadow")))
    elif cmd == "pick-portrait":
        pick_portrait(rest[0], int(rest[1]), float(opt.get("zoom", 1.0)), float(opt.get("dx", 0.0)),
                      float(opt.get("dy", 0.0)), float(opt.get("top", 0.0)))
    elif cmd == "flatten":
        flatten(rest[0])
    elif cmd == "lift":
        lift(rest[0], float(rest[1]))
    elif cmd == "reroll":
        F.reroll(rest[0], " ".join(rest[1:]))
    elif cmd == "strip":
        F.strip(rest[0])
    elif cmd == "install":
        install(rest[0], float(opt["men"]) if "men" in opt else None, float(opt["frac"]) if "frac" in opt else None,
                opt.get("notes", ""), bool(opt.get("like-base")))
    elif cmd == "board":
        board()
    elif cmd == "gates":
        gates()
    elif cmd == "texlevels":
        texlevels(rest or None)
    elif cmd == "retexture":
        for rid in rest:
            retexture(rid, float(opt["gamma"]) if "gamma" in opt else None, bool(opt.get("auto")),
                      float(opt.get("gap", -4.0)))
    elif cmd == "sheet":
        out = os.path.join(ROOT, "studio", "contact-sheets", "asc-3d-paths-%s.png" % rest[0])
        silhouette_sheet(out) if rest[0] == "silhouettes" else contact_sheet(rest[0], out)
    else:
        print(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
