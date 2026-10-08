#!/usr/bin/env python3
"""asc-3d-free-holds: the Free Holds' look (IND-2, issue #161; IND-1 is #142): the three garrison unit types (Free
Spears, Hill Slingers, Wildkin) and the Hold Captain (data/independents.gd), each a four-pose 3D model family
(ready / march / strike / fallen) and a portrait. Plain, local militia in the Free Holds' bone-and-grey (undyed
cream wool, slate and weathered grey), apart from the Crown's blue and gold and the Clans' tawny and moss.

It reuses tools/ludo/asc_3d_factions.py's machinery (the Ludo driver with its credit cap, retries and ledger; picks,
re-rolls, Ludo's snapshot strips; GLB measuring and slimming) under its own batch: the generated manifest is
tools/ludo/batches/asc-3d-free-holds.json and every charged call is a line of studio/ledgers/asc-3d-free-holds.jsonl.

    python3 tools/ludo/asc_3d_free_holds.py manifest            # (re)write the batch manifest
    python3 tools/ludo/asc_3d_free_holds.py cost                # what each stage plans to spend
    python3 tools/ludo/asc_3d_free_holds.py account             # the account's real balance (free)
    python3 tools/ludo/asc_3d_free_holds.py spent               # this batch's own spend, from its ledger
    python3 tools/ludo/asc_3d_free_holds.py run bases1 [--jobs 2]   # Free Spears and Wildkin (styled from greyscale anchors)
    python3 tools/ludo/asc_3d_free_holds.py pick <row> <k> [--deshadow]     # candidate k (1..n) is the pick
    python3 tools/ludo/asc_3d_free_holds.py run bases2          # Hill Slingers and the Hold Captain (styled from the Free Spears pick)
    python3 tools/ludo/asc_3d_free_holds.py run poses           # march / strike / fallen edits of each picked ready picture
    python3 tools/ludo/asc_3d_free_holds.py run portraits1|portraits2    # the four portraits (styled)
    python3 tools/ludo/asc_3d_free_holds.py pick-portrait <row> <k>      # candidate k flattened onto the portrait backdrop (ffmpeg)
    python3 tools/ludo/asc_3d_free_holds.py run models [--only ready]    # every picked picture to a GLB
    python3 tools/ludo/asc_3d_free_holds.py strip <model row>   # its Ludo snapshots side by side (review)
    python3 tools/ludo/asc_3d_free_holds.py reroll <row> <why>  # a new take: v+1, old candidates to old/
    python3 tools/ludo/asc_3d_free_holds.py batches             # write review/ind_concept/ and review/ind_models/
    python3 tools/ludo/asc_3d_free_holds.py install-accepted    # the Review Table's install action for ind_models
    python3 tools/ludo/asc_3d_free_holds.py regen               # the Review Table's redo action: re-roll what was rejected

Who is who: the pictures are made in two steps so the four stay one family. Free Spears (a Crown spearman picture
in greyscale is the style anchor, the bible's leak rule: a cross-faction anchor is greyscale) and Wildkin (a Clans
fangthrower picture in greyscale) come first; the Hill Slingers and the Hold Captain are styled from the picked Free
Spears picture, a same-faction anchor. The poses are edits of each unit's picked ready picture (C-pose), as in
asc-3d-factions. Portraits are styled the same way from greyscale portraits and the picked Free Spears portrait.

Where things go:
- picks: assets/_concept/independents/<unit>_<pose>.webp and <unit>_portrait.webp (the finished 384x512 portrait):
  committed pipeline inputs, as in asc-3d-factions, never shipped;
- portraits: assets/portraits/independents/<unit>.webp (Art finds them by unit id, ui/art.gd), written only by the
  Review Table's install action (`review.py apply ind_concept`) from the take the owner kept;
- models: assets/models/units/independents/<unit>_<pose>.glb, a row in assets/models/models.json, and the
  unit's row in world3d/models.json, which already stands with a placeholder figure (world3d/kit.gd), written only by
  `install-accepted`; the standard bearer and the musician of a garrison then stand as a Free Spear and a Hill Slinger;
- nothing is installed by generating. `batches` copies every picture and slimmed model into the Review Table
  (review/ind_concept/ in concept mode, review/ind_models/ with each model's install path as its target); the owner
  judges them there, and the batches' install actions put the accepted pictures and models in the game. A Ludo model
  comes with a floor slab (the picture's soft ground shadow fused into a pad under the feet): `trim_floor` cuts it away.

The cap: this batch stops at CAP (under the issue's 120 credits), counted from this batch's own ledger, not from the
account's balance: another builder spends from the same account at the same time, so a balance delta would charge
it to this batch. Discipline as asc-3d-factions (studio/ludo-playbook.md): a failed job is free but burns its request
id, so a retry bumps `v`; candidates and raw GLBs stay in the gitignored candidates/ folders; every input goes to
Ludo as base64 from a local file. Stdlib plus ffmpeg (the full build, for WebP).
"""
import json
import math
import os
import shutil
import struct
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import asc_3d_factions as F  # noqa: E402  (the driver, picks, measuring, slimming)
import glb_slim  # noqa: E402
import ludo  # noqa: E402

ROOT = F.ROOT
BATCH = "asc-3d-free-holds"
MANIFEST = os.path.join(ROOT, "tools", "ludo", "batches", BATCH + ".json")
LEDGER = os.path.join(ROOT, "studio", "ledgers", BATCH + ".jsonl")
## The issue's cap is 120 credits. The driver checks completed spend before each submit and a few jobs run at once
## (up to 4 credits each), so the stop line sits below it.
CAP = 111.0
JOB_CAP = 120.0
PIC_CAND = "assets/_concept/candidates/free_holds"
GLB_CAND = "assets/models/candidates/free_holds"
INPUTS = os.path.join(ROOT, "assets", "_concept", "candidates", "_inputs")
BOARD_TABLE = os.path.join(ROOT, "world3d", "models.json")
FACTION = "independents"
## The Review Table batches (review/ is gitignored: the batches are local).
CONCEPT_BATCH = "ind_concept"
MODEL_BATCH = "ind_models"

# ------------------------------------------------------------------------------------------ style
## STYLE_BIBLE §6.1 C-portrait, verbatim (as asc_3d_paths.py).
C_PORTRAIT = ("Cel-shaded portrait of bright high fantasy: head and shoulders, three-quarter view facing left, face in "
              "the upper half of the frame, thick clean dark outline, flat saturated colours with one hard shadow tone "
              "and one highlight tone, bold simple shapes, plain softly graded deep indigo background.")

# ------------------------------------------------------------------------------------------ units
## id: class, body height (men, the head top; a Crown spearman is 1.0), faces, texture (px after slimming), who, outfit,
## the ready pose ("base"), the three other poses, the portrait subject (after C-portrait). The Free Holds wear
## undyed cream wool and slate and weathered greys, plain and local (design/lore/writers-room/R3-synthesis.md §5:
## "a short mixed block in undyed wool under each hold's own home-stitched sign"); no blue, gold, tawny, moss or crimson.
UNITS = {
    "free_spears": dict(
        cls="infantry", body=0.95, faces=5000, tex=512, beast=False, name="Free Spears", style="grey_unit_kingdom",
        pstyle="grey_portrait_kingdom",
        who="Free Holds spearman, a plain local militia fighter of a free town",
        outfit="a plain round grey iron cap, an undyed cream wool tunic over a grey padded jerkin, a slate-grey wool "
               "hood hanging at the neck, a brown leather belt and boots, and a pale bone-white kite-shaped wooden "
               "shield with a slate-grey rim and one small stitched grey sign on its face",
        base="standing in a relaxed A-pose with his feet apart, his right arm held out from his side gripping a plain "
             "wooden spear upright with a small grey iron head, at arm's length with clear space between the spear "
             "and his body, the kite-shaped shield on his left forearm held a little out from his side, calm steady "
             "expression, eyes ahead",
        march="marching forward with his left leg striding ahead, the spear sloped back over his right shoulder in his "
              "right hand, the kite-shaped shield on his left arm, eyes ahead",
        strike="lunging forward on his bent left leg, thrusting the spear straight ahead at waist height with his right "
               "arm fully extended, the kite-shaped shield raised on his left arm, a fierce shout",
        fallen="fallen in battle, lying flat on his back on the floor with his arms out to the sides, his iron cap "
               "still on, the spear and the kite-shaped shield lying on the floor beside him, eyes closed",
        portrait="A Free Holds spearman, a plain local militia fighter of a free town, a weathered young face under a "
                 "plain round grey iron cap, an undyed cream wool collar over a grey padded jerkin, a slate-grey wool "
                 "hood at the neck, the small grey iron head of a spear at the shoulder, calm steady expression, "
                 "eyes looking to the left"),
    "hill_slingers": dict(
        cls="ranged", body=0.9, faces=5000, tex=512, beast=False, name="Hill Slingers", style="pick:free_spears",
        pstyle="pick:free_spears",
        who="Free Holds hill slinger, a lean local skirmisher of the hill holds",
        outfit="a pale bone-white wool hood and cowl, a short undyed cream wool tunic with a grey leather chest strap, "
               "grey wool leggings wrapped with brown cord, light brown boots, a leather pouch of round grey stones "
               "at the hip, and a long leather sling",
        base="standing in a relaxed A-pose with his feet apart, holding the long leather sling in his right hand with "
             "its cord hanging straight down at arm's length out to his side with clear space between the sling and "
             "his body, his left arm held a little out from his side, alert expression, eyes ahead",
        march="loping forward with his left leg ahead, the sling coiled in his right hand at his side, his left arm "
              "swinging, eyes ahead",
        strike="slinging a stone: his right arm swung forward and out at shoulder height with the sling's cord "
               "stretched straight ahead, his left arm drawn back, his left leg stepping forward, eyes on the target "
               "ahead",
        fallen="fallen in battle, lying flat on his back on the floor with his arms out to the sides, his hood still "
               "on, the sling and the pouch of stones lying on the floor beside him, eyes closed",
        portrait="A Free Holds hill slinger, a lean sharp-eyed local skirmisher in a pale bone-white wool hood and "
                 "cowl, a grey leather chest strap over an undyed cream wool tunic, a long leather sling coiled at "
                 "the shoulder, alert expression, eyes looking to the left"),
    "wildkin": dict(
        cls="beast", body=1.1, faces=6000, tex=512, beast=False, name="Wildkin", style="grey_unit_beasts",
        pstyle="grey_portrait_beasts",
        who="Free Holds wildkin, a stocky silver-grey badger-headed beastman of the deep woods, free of any clan",
        outfit="a broad grey badger head with a bold pale cream stripe down the face and dark grey eye bands, thick "
               "silver-grey fur, a loose undyed cream wool smock tied with a plain rope belt, grey bark-cloth "
               "shoulder wraps, bare clawed feet, and a long-handled woodcutter's axe with a plain grey iron head",
        base="standing in a relaxed A-pose with his clawed feet apart, gripping the long-handled axe upright in his "
             "right hand at arm's length out to his side with clear space between the axe and his body, his left arm "
             "held a little out from his side, fierce steady expression, eyes ahead",
        march="stomping forward with his left leg ahead, the axe resting on his right shoulder, his left fist "
              "swinging, eyes ahead",
        strike="chopping down with the long-handled axe held high over his head in both hands, leaning forward, mouth "
               "open in a roar",
        fallen="fallen in battle, lying flat on his back on the floor with his arms out to the sides, the axe lying on "
               "the floor beside him, eyes closed",
        portrait="A Free Holds wildkin, a stocky silver-grey badger-headed beastman of the deep woods, a bold pale "
                 "cream stripe down the face and dark grey eye bands, an undyed cream wool smock with grey bark-cloth "
                 "shoulder wraps, the grey iron head of a woodcutter's axe at the shoulder, fierce steady "
                 "expression, eyes looking to the left"),
    "hold_captain": dict(
        cls="commander", body=1.05, faces=6000, tex=1024, beast=False, name="Hold Captain", style="pick:free_spears",
        pstyle="pick:free_spears",
        who="Free Holds captain, the grey-bearded leader of a free town's militia",
        outfit="a weathered grey-bearded face, a plain grey iron helm with a short white horsehair crest, a bone-white "
               "wool cloak over a grey mail shirt, a slate-grey wool tunic, a brown belt and boots, a great curved "
               "bone-white war horn hanging at his belt, and a long-hafted bearded war axe",
        base="standing in a relaxed A-pose with his feet apart, holding the long-hafted war axe upright in his right "
             "hand at arm's length out to his side with clear space between the axe and his body, the haft rising "
             "well above his head, his left arm held a little out from his side, the cloak hanging behind him, "
             "steady stern expression, eyes ahead",
        march="striding forward with his left leg ahead, the war axe resting on his right shoulder, his left hand "
              "raised forward as if leading his townsfolk, the cloak flowing behind him",
        strike="swinging the war axe in a big two-handed diagonal chop, lunging forward on his bent left leg, the axe "
               "raised high above his right shoulder, the cloak flaring, a battle cry",
        fallen="fallen in battle, lying flat on his back on the floor with his arms out to the sides, the cloak "
               "wrapped closely around his legs, his helm still on, the war axe lying on the floor beside him, eyes "
               "closed",
        portrait="A Hold Captain of the Free Holds, a weathered grey-bearded man in a plain grey iron helm with a "
                 "short white horsehair crest, a bone-white wool cloak over a grey mail shirt, the long haft of a war "
                 "axe at the shoulder, stern steady expression, eyes looking to the left"),
}
POSES = F.POSES
LYING = F.LYING

## Greyscale style anchors (the bible's leak rule), made from committed pictures into the gitignored inputs folder:
## name -> the picture it is a greyscale copy of.
GREY = {
    "grey_unit_kingdom": "assets/_concept/kingdom/spearmen_ready.webp",
    "grey_unit_beasts": "assets/_concept/beasts/fangthrowers_ready.webp",
    "grey_portrait_kingdom": "assets/portraits/kingdom/spearmen.webp",
    "grey_portrait_beasts": "assets/portraits/beasts/fangthrowers.webp",
}


def pick_path(name):
    return "assets/_concept/%s/%s.webp" % (FACTION, name)


def portrait_path(uid):
    """Where the shipped portrait goes (Art finds it by unit id): written only by the Review Table's install action."""
    return "assets/portraits/%s/%s.webp" % (FACTION, uid)


def portrait_pick(uid):
    """The picked, finished portrait before it is judged: a pipeline input beside the 3D concept pictures."""
    return "assets/_concept/%s/%s_portrait.webp" % (FACTION, uid)


def model_target(uid, pose):
    return "assets/models/units/%s/%s_%s.glb" % (FACTION, uid, pose)


def style_file(spec, portrait=False):
    """A style anchor spec: a greyscale input's name, or "pick:<unit>" (that unit's picked ready picture, or its picked
    portrait for a portrait row)."""
    if spec.startswith("pick:"):
        return portrait_pick(spec[5:]) if portrait else pick_path(spec[5:] + "_ready")
    return os.path.relpath(os.path.join(INPUTS, spec + ".png"), ROOT)


# ---------------------------------------------------------------------------------------- the rows
def rows():
    """Every row of the batch in run order. Picture rows roll `n` candidates; model rows read a pick."""
    out = []
    for uid, u in UNITS.items():
        stage = "bases1" if u["style"].startswith("grey_") else "bases2"
        out.append({"id": "pic_%s_ready" % uid, "stage": stage, "kind": "styled", "n": 3,
                    "style_file": style_file(u["style"]),
                    "prompt": "%s Subject: a %s, with %s, %s." % (F.C_MODEL_BEAST if u["beast"] else F.C_MODEL,
                                                                  u["who"], u["outfit"], u["base"]),
                    "pick_to": pick_path(uid + "_ready"), "group": "units", "unit": uid, "pose": "ready"})
    for uid, u in UNITS.items():
        for pose in POSES[1:]:
            view = F.VIEW_LYING if pose in LYING else F.VIEW
            out.append({"id": "pic_%s_%s" % (uid, pose), "stage": "poses", "kind": "edit", "n": 2,
                        "from_file": pick_path(uid + "_ready"), "prompt": F.C_POSE.format(pose=u[pose], view=view),
                        "pick_to": pick_path("%s_%s" % (uid, pose)), "group": "units", "unit": uid, "pose": pose})
    for uid, u in UNITS.items():
        stage = "portraits1" if u["pstyle"].startswith("grey_") else "portraits2"
        out.append({"id": "por_" + uid, "stage": stage, "kind": "styled", "n": 3, "image_type": "portrait",
                    "style_file": style_file(u["pstyle"], True),
                    "prompt": "%s Subject: %s." % (C_PORTRAIT, u["portrait"]),
                    "pick_to": portrait_pick(uid), "group": "portraits", "unit": uid, "pose": None})
    ## models: every ready pose first (what the board shows most), then strike, march, fallen
    for pose in ("ready", "strike", "march", "fallen"):
        for uid, u in UNITS.items():
            out.append({"id": "model_%s_%s" % (uid, pose), "stage": "models", "kind": "model3d",
                        "from_file": pick_path("%s_%s" % (uid, pose)), "faces": u["faces"], "texture_size": 1024,
                        "texture_type": "pbr", "slim_max": u["tex"], "target": model_target(uid, pose),
                        "group": "units", "unit": uid, "pose": pose, "variant": None})
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
        "batch": BATCH, "rid_prefix": "ascfh", "cap": CAP, "job_cap": JOB_CAP,
        "note": "Written by tools/ludo/asc_3d_free_holds.py (which holds the prompts; edit it, not this file). The "
                "Free Holds' look (IND-2, #161): Free Spears, Hill Slingers, Wildkin and the Hold Captain, 4 poses "
                "each, and their portraits. Picture rows roll n candidates in one call; picks are copied to "
                "assets/_concept/independents/ and assets/portraits/independents/; model rows read the pick as base64. "
                "balance_before is a fixed sentinel: the cap counts this batch's own ledger (the account is shared).",
        "style": {"image": "", "art_style": "Cel-Shaded",
                  "blocks": {"C-model (3D, no base)": F.C_MODEL, "C-model-beast (3D, no base)": F.C_MODEL_BEAST,
                             "C-pose (no base)": F.C_POSE, "C-portrait": C_PORTRAIT}},
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
            suffix = "_portrait" if r["id"].startswith("por_") else ""
            a["out"] = PIC_CAND + "/" + r["id"].split("_", 1)[1] + suffix
        man["assets"].append(a)
    os.makedirs(os.path.dirname(MANIFEST), exist_ok=True)
    with open(MANIFEST, "w") as f:
        json.dump(man, f, indent=1)
        f.write("\n")
    return man


def manifest_rows():
    return {a["id"]: a for a in json.load(open(MANIFEST))["assets"]}


# ------------------------------------------------------------------------------------- the cap
SENTINEL = 1000.0  ## balance_before: spend is SENTINEL - available, and available is SENTINEL - this ledger's sum


def ledger_spent():
    """Credits this batch has been charged: the sum of its own ledger."""
    total = 0.0
    if os.path.exists(LEDGER):
        for line in open(LEDGER):
            line = line.strip()
            if line:
                total += float(json.loads(line).get("credits_charged") or 0)
    return round(total, 2)


def own_balance():
    return SENTINEL - ledger_spent()


## asc_3d_factions' driver, picks and re-rolls read these module globals: point them at this batch. The driver
## computes spend as balance_before - account(); account() here is the batch's own, so the shared account's other
## spenders (M4-ART runs at the same time) never count against this cap.
F.BATCH, F.MANIFEST, F.LEDGER, F.CAP, F.RID = BATCH, MANIFEST, LEDGER, CAP, "ascfh"
F.PIC_CAND, F.GLB_CAND, F.INPUTS = PIC_CAND, GLB_CAND, INPUTS
F.SCRATCH = os.environ.get("ASC3D_SCRATCH", os.path.join(ROOT, GLB_CAND, "_review"))
F.rows = rows
## image to 3D is charged 4.0 now (3.0 in asc-3d-factions and asc-3d-paths: the first model of this batch cost 4)
F.PRICE = dict(F.PRICE, **{"/assets/3d-model": 4.0})
F.write_manifest = write_manifest
F.load_state = load_state
F.account = own_balance


def make_inputs():
    """The greyscale style anchors (GREY), as PNG in the gitignored inputs folder."""
    os.makedirs(INPUTS, exist_ok=True)
    for name, src in GREY.items():
        dst = os.path.join(INPUTS, name + ".png")
        if os.path.exists(dst):
            continue
        subprocess.run([F.FF, "-y", "-loglevel", "error", "-i", os.path.join(ROOT, src), "-vf",
                        "format=gray,format=rgb24", "-frames:v", "1", dst], check=True)
        print("input", os.path.relpath(dst, ROOT))


def run(stage, only, jobs, hours):
    make_inputs()
    state = load_state()
    if state.get("balance_before") is None:
        state["balance_before"] = SENTINEL
        state.setdefault("v", {})
        state.setdefault("picks", {})
        F.save_state(state)
    ludo.KEY = ludo.api_key()
    F.run(stage, only, jobs, hours)


# ---------------------------------------------------------------------------------------- portraits
def portrait_backdrop_filter():
    """The M1 portrait background as an ffmpeg expression: a radial #333052 -> #1C1B2A (centre at 0.5, 0.45 of the
    frame, the outer colour at the farthest corner; asc_3d_paths.py portrait_backdrop)."""
    t = "min(1,hypot(X-W*0.5,Y-H*0.45)/hypot(max(W*0.5,W*0.5),max(H*0.45,H*0.55)))"
    return ("geq=r='%d+(%d)*%s':g='%d+(%d)*%s':b='%d+(%d)*%s'" % (
        0x33, 0x1C - 0x33, t, 0x30, 0x1B - 0x30, t, 0x52, 0x2A - 0x52, t))


def finish_portrait(src, dst, zoom=1.0, dx=0.0, dy=0.0):
    """A portrait candidate (it may carry native alpha) laid on the M1 gradient, cropped to 3:4 (the full height,
    centred, `zoom` in; dx/dy shift the crop by that share of its size), 384x512 webp q90. ffmpeg only (no Pillow)."""
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    w, h = (int(x) for x in subprocess.run(
        ["sips", "-g", "pixelWidth", "-g", "pixelHeight", src], capture_output=True, text=True).stdout.split()[-3::2])
    ch = h / zoom
    cw = ch * 0.75
    if cw > w:
        cw, ch = w, w / 0.75
    x0 = min(max(0.0, (w - cw) / 2 + dx * cw), w - cw)
    y0 = min(max(0.0, dy * ch), h - ch)
    flt = ("color=c=black:s=%dx%d,%s,format=rgba[bg];[0:v]format=rgba[im];[bg][im]overlay=0:0,"
           "crop=%d:%d:%d:%d,scale=384:512:flags=lanczos,format=yuv420p" % (w, h, portrait_backdrop_filter(),
                                                                         int(cw), int(ch), int(x0), int(y0)))
    subprocess.run([F.FF, "-y", "-loglevel", "error", "-i", src, "-filter_complex", flt, "-frames:v", "1",
                    "-c:v", "libwebp", "-quality", "90", dst], check=True)
    return w, h


def candidate_file(a, k):
    src = [c for c in F.cand_files(a) if os.path.basename(c).startswith(os.path.basename(a["out"]) + "_c%d." % k)]
    if not src:
        sys.exit("no candidate %d for %s" % (k, a["id"]))
    return src[0]


def pick_portrait(row_id, k, zoom=1.0, dx=0.0, dy=0.0):
    """Candidate k of a portrait row becomes the row's finished pick (assets/_concept/independents/<unit>_portrait.webp,
    a pipeline input: the shipped portrait is written only by the Review Table's install, from the judged take). The
    crop is remembered, so the review batch finishes every candidate the same way."""
    a = manifest_rows()[row_id]
    w, h = finish_portrait(candidate_file(a, k), os.path.join(ROOT, a["pick_to"]), zoom, dx, dy)
    state = load_state()
    state.setdefault("picks", {})[row_id] = k
    state.setdefault("portrait_crops", {})[row_id] = {"zoom": zoom, "dx": dx, "dy": dy, "src": [w, h]}
    F.save_state(state)
    print("pick %s c%d -> %s (from %dx%d)" % (row_id, k, a["pick_to"], w, h))


# ------------------------------------------------------------------------------- review batches
def _atomic(path, data):
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=1)
        f.write("\n")
    os.replace(tmp, path)


def _copy(src, dst):
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copy2(src, dst)


def _fresh(dst, src):
    """True when `dst` was made after `src` last changed: a batch file is only rewritten when its source is newer, so
    rebuilding the batches never makes the Review Table see an unchanged item as regenerated (a newer file than the
    verdict puts the item back in the queue)."""
    return os.path.exists(dst) and os.path.getmtime(dst) >= os.path.getmtime(src)


def concept_items():
    """The concept batch's items: every picture the batch made, the picked one first (it is what the models were made
    from) and the other candidates as takes. Candidates are webp q90 copies under review/ind_concept/."""
    d = os.path.join(ROOT, "review", CONCEPT_BATCH)
    man = manifest_rows()
    state = load_state()
    items = []
    for r in rows():
        if r["kind"] not in ("styled", "edit"):
            continue
        a = man[r["id"]]
        cands = F.cand_files(a)
        if not cands:
            continue
        pick = int(state.get("picks", {}).get(r["id"], 1))
        ordered = sorted(cands)
        lead = [c for c in ordered if os.path.basename(c).split("_c")[-1].split(".")[0] == str(pick)] or ordered[:1]
        rest = [c for c in ordered if c not in lead]
        uid, pose = r["unit"], r["pose"]
        stem = r["id"].split("_", 1)[1]
        files = []
        crop = state.get("portrait_crops", {}).get(r["id"], {})
        for c in lead + rest:
            k = os.path.basename(c).rsplit("_c", 1)[1].split(".")[0]
            rel = "%s/%s_c%s.webp" % (r["group"], stem, k)
            dst = os.path.join(d, rel)
            if _fresh(dst, c):
                pass
            elif r["group"] == "portraits":
                ## the shipped form of every candidate (384x512 on the portrait backdrop): `apply` copies the take kept
                finish_portrait(c, dst, crop.get("zoom", 1.0), crop.get("dx", 0.0) if k == str(pick) else 0.0,
                                crop.get("dy", 0.0))
            elif c.endswith(".webp"):
                _copy(c, dst)
            else:
                subprocess.run([F.FF, "-y", "-loglevel", "error", "-i", c, "-c:v", "libwebp", "-quality", "90", dst],
                               check=True)
            files.append((rel, k))
        n = UNITS[uid]
        label = ("%s portrait" % n["name"]) if r["group"] == "portraits" else "%s %s" % (n["name"], pose)
        item = {"id": stem, "kind": "image", "group": ("%s" % n["name"]), "label": label, "text": r["prompt"],
                "file": files[0][0], "target": portrait_path(uid) if r["group"] == "portraits" else r["pick_to"],
                "meta": {"context": ("the picture the " + pose + " model was made from") if r["group"] == "units"
                         else "the portrait the game shows for the unit (3:4)",
                         "row": r["id"], "v": a.get("v", 1)}}
        if len(files) > 1:
            item["takes"] = [{"file": f, "label": "take %d (candidate %s)" % (i + 2, k)} for i, (f, k) in enumerate(files[1:])]
        item["take_label"] = "take 1 (candidate %s, the picked one)" % files[0][1]
        items.append(item)
    return items


def concept_batch():
    d = os.path.join(ROOT, "review", CONCEPT_BATCH)
    items = concept_items()
    data = {"batch": CONCEPT_BATCH, "title": "Free Holds: concept pictures and portraits (IND-2, #161)",
            "mode": "concept", "items": items,
            "actions": [{"id": "install", "kind": "install", "label": "Install accepted pictures",
                         "help": "Copy every Good and Good with changes picture to its target: the 3D concept pictures to "
                                 "assets/_concept/independents/, the portraits to assets/portraits/independents/ "
                                 "(review.py apply), then re-import in Godot",
                         "cmd": ["python3", "tools/review/review.py", "apply", CONCEPT_BATCH],
                         "options": [{"flag": "--dry-run", "label": "Dry run", "type": "bool", "default": False}]},
                        {"id": "regen", "kind": "regen", "label": "Redo rejected",
                         "help": "Re-roll the rejected pictures with Ludo (spends credits, this batch's cap)",
                         "cmd": ["python3", "tools/ludo/asc_3d_free_holds.py", "regen"], "spends": True}]}
    os.makedirs(d, exist_ok=True)
    _atomic(os.path.join(d, "batch.json"), data)
    print("review/%s: %d items" % (CONCEPT_BATCH, len(items)))


FIGURE_TINT = 0.75 ## world3d/models.json "tint" of an installed Free Holds figure: undyed wool blows out to white at 1.0
FLOOR_FRAC = 0.012 ## triangles lying entirely in the bottom 1.2% of a model's height are the fused ground slab
FLOOR_ZONE = 0.06   ## the slab (a pad that can tilt and swell under a lunging foot) lies in the bottom 6%
FLAT_NY = 0.8       ## a triangle this flat (|normal y|) in that zone is the pad's top or underside, or a sole


def floor_triangles(pos, tris, lo, h):
    """The indices of the triangles of the fused ground slab. The pad's flat top and underside and the soles in the
    bottom FLOOR_ZONE of the height go (a flat triangle there is never a boot's side), and so does anything entirely in
    the bottom FLOOR_FRAC; then every connected piece left wholly inside the zone is cut away too (the pad's thin rim,
    which no foot touches). The figure above stands as it was: the shoes keep their sides."""
    zone = lo + FLOOR_ZONE * h
    thin = lo + FLOOR_FRAC * h
    drop = set()
    for k, (a, b, c) in enumerate(tris):
        pa, pb, pc = pos[a], pos[b], pos[c]
        top = max(pa[1], pb[1], pc[1])
        if top < thin:
            drop.add(k)
            continue
        if top >= zone:
            continue
        u = (pb[0] - pa[0], pb[1] - pa[1], pb[2] - pa[2])
        v = (pc[0] - pa[0], pc[1] - pa[1], pc[2] - pa[2])
        n = (u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0])
        length = (n[0] ** 2 + n[1] ** 2 + n[2] ** 2) ** 0.5
        if length > 0.0 and abs(n[1]) / length > FLAT_NY:
            drop.add(k)
    ## connected pieces of what is left (by shared vertices); a piece that never rises out of the zone is slab
    parent = {}

    def find(x):
        while parent.setdefault(x, x) != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x
    for k, t in enumerate(tris):
        if k in drop:
            continue
        ra = find(t[0])
        for i in t[1:]:
            rb = find(i)
            if rb != ra:
                parent[rb] = ra
    top_of = {}
    for k, t in enumerate(tris):
        if k in drop:
            continue
        r = find(t[0])
        top_of[r] = max(top_of.get(r, lo), max(pos[i][1] for i in t))
    for k, t in enumerate(tris):
        if k not in drop and top_of[find(t[0])] < zone:
            drop.add(k)
    return drop


def trim_floor(src, dst):
    """The raw Ludo GLB with its floor slab cut away: image-to-3D fuses a picture's soft ground shadow into a flat
    plate under the feet (a black-undersided square in the board's light; asc-3d-factions had `--deshadow` for the
    pictures, asc-3d-paths cut shadows out). Every triangle whose three vertices all lie within `frac` of the model's
    height above its lowest point is dropped from the index buffer (the soles of the shoes go with them: nobody sees
    them). One mesh, one primitive, as Ludo writes them. Returns (triangles before, after)."""
    js, binc = glb_slim.read_glb(src)
    pos, tris, _img = F.glb_mesh(src)
    prims = [p for m in js["meshes"] for p in m["primitives"]]
    if len(prims) != 1 or "indices" not in prims[0]:
        sys.exit("trim_floor: %s has %d primitives (one expected, indexed)" % (src, len(prims)))
    ys = [p[1] for p in pos]
    lo, hi = min(ys), max(ys)
    gone = floor_triangles(pos, tris, lo, hi - lo)
    keep = [t for k, t in enumerate(tris) if k not in gone]
    ## the vertices no kept triangle uses go too (the importer's bounding box would still hold them), indices remapped
    used = sorted({i for t in keep for i in t})
    remap = {old: new for new, old in enumerate(used)}
    b = bytearray(binc)

    def rewrite(acc_index, rows_data, fmt):
        acc = js["accessors"][acc_index]
        view = js["bufferViews"][acc["bufferView"]]
        data = struct.pack("<%d%s" % (len(rows_data), fmt), *rows_data)
        off = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
        b[off:off + len(data)] = data
        view.pop("byteStride", None)
        view["byteLength"] = acc.get("byteOffset", 0) + len(data)
        return acc

    comp = {5126: ("f", 4), 5125: ("I", 4), 5123: ("H", 2), 5121: ("B", 1)}
    ncomp = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}
    for name, ai in prims[0]["attributes"].items():
        acc = js["accessors"][ai]
        view = js["bufferViews"][acc["bufferView"]]
        fmt, csize = comp[acc["componentType"]]
        n = ncomp[acc["type"]]
        stride = view.get("byteStride", n * csize)
        if acc.get("normalized") or acc["count"] != len(pos):
            sys.exit("trim_floor: %s's %s accessor is not a plain per-vertex array" % (src, name))
        base = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
        flat = []
        for v in used:
            flat += struct.unpack_from("<%d%s" % (n, fmt), binc, base + v * stride)
        rewrite(ai, flat, fmt)
        acc["count"] = len(used)
        if name == "POSITION":
            acc["min"] = [min(flat[k::n]) for k in range(n)]
            acc["max"] = [max(flat[k::n]) for k in range(n)]
    iacc = js["accessors"][prims[0]["indices"]]
    ifmt = {5125: "I", 5123: "H"}[iacc["componentType"]]
    if ifmt == "H" and len(used) > 65535:
        sys.exit("trim_floor: too many vertices for 16-bit indices")
    rewrite(prims[0]["indices"], [remap[i] for t in keep for i in t], ifmt)
    iacc["count"] = len(keep) * 3
    glb_slim.write_glb(dst, js, bytes(b))
    return len(tris), len(keep)


def slim_model(row):
    """A model row's raw Ludo GLB with its floor slab cut away, then slimmed the way install does (matte, colour map
    only, JPEG), into the model batch; returns the path."""
    src = os.path.join(ROOT, row["out"] + ".glb")
    d = os.path.join(ROOT, "review", MODEL_BATCH, "units")
    os.makedirs(d, exist_ok=True)
    dst = os.path.join(d, "%s_%s.glb" % (row["unit"], row["pose"]))
    if _fresh(dst, src):
        return dst
    trimmed = dst + ".trim.glb"
    before, after = trim_floor(src, trimmed)
    glb_slim.slim(trimmed, dst, 3, row["slim_max"], True)
    os.remove(trimmed)
    print("  %s: floor slab cut, %d -> %d triangles" % (os.path.basename(dst), before, after))
    return dst


def model_batch():
    d = os.path.join(ROOT, "review", MODEL_BATCH)
    man = manifest_rows()
    items = []
    for r in rows():
        if r["kind"] != "model3d":
            continue
        a = man[r["id"]]
        if not os.path.exists(os.path.join(ROOT, a["out"] + ".glb")):
            continue
        slim_model(a)
        u = UNITS[r["unit"]]
        pic = os.path.join(ROOT, r["from_file"])
        items.append({"id": "%s_%s" % (r["unit"], r["pose"]), "kind": "model", "group": u["name"],
                      "label": "%s %s" % (u["name"], r["pose"]),
                      "text": "A %s, the %s pose, from its concept picture (%s); %d faces, %d px texture." % (
                          u["who"], r["pose"], os.path.basename(r["from_file"]), a["faces"], a["slim_max"]),
                      "file": "units/%s_%s.glb" % (r["unit"], r["pose"]), "target": r["target"],
                      "meta": {"context": "the 3D board and the 3D battle stage (the game stands a kit figure there until "
                                          "an accepted model is installed)",
                               "row": r["id"], "v": a.get("v", 1), "install": [["units/%s_%s.glb" % (r["unit"], r["pose"]),
                                                                                  r["target"]]]}})
    data = {"batch": MODEL_BATCH, "title": "Free Holds: unit models (IND-2, #161)", "items": items,
            "actions": [{"id": "install", "kind": "install", "label": "Install accepted models",
                         "help": "Copy each accepted model to assets/models/units/independents/, write its Godot import, "
                                 "its row in assets/models/models.json and the unit's row in world3d/models.json, so "
                                 "the board and the stage swap the placeholder figure for it",
                         "cmd": ["python3", "tools/ludo/asc_3d_free_holds.py", "install-accepted"],
                         "options": [{"flag": "--dry-run", "label": "Dry run", "type": "bool", "default": False}]},
                        {"id": "regen", "kind": "regen", "label": "Redo rejected",
                         "help": "Re-roll the rejected models with Ludo (spends 4 credits each, this batch's cap)",
                         "cmd": ["python3", "tools/ludo/asc_3d_free_holds.py", "regen"], "spends": True}]}
    os.makedirs(d, exist_ok=True)
    _atomic(os.path.join(d, "batch.json"), data)
    print("review/%s: %d models" % (MODEL_BATCH, len(items)))


def batches():
    concept_batch()
    model_batch()


# ------------------------------------------------------------------------------------------ install
def _review_module():
    sys.path.insert(0, os.path.join(ROOT, "tools", "review"))
    import review  # noqa: E402
    return review


def entry_for(uid, pose, dst, after, m, body, frac=None, men=None, notes=""):
    """A models.json entry for an installed pose (asc_3d_paths.install's shape)."""
    u = UNITS[uid]
    entry = {"path": "res://" + os.path.relpath(dst, ROOT), "kind": "unit", "id": uid, "faction": FACTION,
             "class": u["cls"], "pose": pose}
    if pose in LYING:
        f = frac or m["long_frac"]
        entry["size"] = {"axis": "length", "men": men if men else round(body / f, 3)}
    else:
        f = frac or m["body_frac"]
        entry["size"] = {"axis": "height", "men": men if men else round(body / f, 3)}
    entry.update({"body_share": round(f, 3), "body_men": body, "yaw": 0.0, "hue_keys": [], "faces": m["faces"],
                  "texture": u["tex"], "bytes": after, "extent": m["size"]})
    if notes:
        entry["notes"] = notes
    return entry


def install_model(uid, pose, src, dry=False):
    """One accepted model: its slim GLB to the install path, the Godot import, the descriptor row."""
    dst = os.path.join(ROOT, model_target(uid, pose))
    if dry:
        print("  [dry-run] + %s" % os.path.relpath(dst, ROOT))
        return None
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copy2(src, dst)
    glb_slim.write_import(os.path.relpath(dst, ROOT), ROOT)
    m = F.measure(dst)
    d = F.load_descriptor()
    e = entry_for(uid, pose, dst, os.path.getsize(dst), m, UNITS[uid]["body"],
                  notes="size measured off the GLB (body_frac), not yet read off a ruler render")
    d.setdefault("units", {}).setdefault(uid, {})[pose] = e
    F.dump_descriptor(d)
    print("  + %s: %d faces, extent %s, %s %.3f men" % (os.path.relpath(dst, ROOT), m["faces"], m["size"],
                                                        e["size"]["axis"], e["size"]["men"]))
    return e


def board(write=True):
    """The four units' rows of world3d/models.json from the descriptor, and only those lines: a unit with a ready
    model gets "model", "height", "yaw", "poses" and "pose_size"; every other line stays byte for byte."""
    d = F.load_descriptor()
    text = open(BOARD_TABLE).read()
    tb = json.loads(text)
    figs = tb["figures"]
    new_rows = {}
    for uid in UNITS:
        poses = d.get("units", {}).get(uid, {})
        if "ready" not in poses or uid not in figs:
            continue
        row = dict(figs[uid])
        ready = poses["ready"]
        row["model"] = ready["path"]
        row["height"] = ready["size"]["men"]
        row["yaw"] = round(180.0 + math.degrees(ready["yaw"]), 1)
        row["poses"] = {p: poses[p]["path"] for p in F.RULER_POSES if p in poses}
        row["pose_size"] = {p: {"axis": poses[p]["size"]["axis"], "men": poses[p]["size"]["men"]}
                            for p in F.RULER_POSES if p in poses}
        row["tint"] = FIGURE_TINT
        new_rows[uid] = row
    ## the colour party: the Free Holds have no extras models of their own, so the standard bearer stands as a Free
    ## Spear (the army's banner hangs from its own staff beside him) and the musician as a Hill Slinger
    for extra, unit in (("bearer", "free_spears"), ("musician", "hill_slingers")):
        ready = d.get("units", {}).get(unit, {}).get("ready")
        if ready and extra in figs:
            row = dict(figs[extra])
            row["models"] = dict(row.get("models", {}), **{FACTION: ready["path"]})
            row["model_height"] = dict(row.get("model_height", {}), **{FACTION: ready["size"]["men"]})
            row["model_tint"] = dict(row.get("model_tint", {}), **{FACTION: FIGURE_TINT})
            new_rows[extra] = row
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
    json.loads(out)  # still a valid table
    if write:
        with open(BOARD_TABLE, "w") as f:
            f.write(out)
    for rid in sorted(new_rows):
        print("board row", rid)
    return new_rows


def install_accepted(dry=False):
    review = _review_module()
    mb = review.merged_batch(MODEL_BATCH)
    d, _ = review.load_batch(MODEL_BATCH)
    n = 0
    for it in mb["items"]:
        if it["status"] not in review.KEPT:
            continue
        uid, pose = it["id"].rsplit("_", 1)
        if uid not in UNITS or pose not in POSES:
            continue
        src = (d / it["src"]).resolve() if it.get("src") else review.item_path(d, it)
        install_model(uid, pose, str(src), dry)
        n += 1
    if not dry and n:
        board()
    review.write_rejected(MODEL_BATCH)
    print("installed %d model(s)%s" % (n, " (dry run)" if dry else ""))


def regen():
    """The Review Table's redo action: every rejected item of the two batches is re-rolled (a new request id, the old
    candidates to old/) and made again, then the batches are rewritten. A rejected concept picture is one new roll;
    a rejected model is one new model. The notes are printed for the next prompt edit, never fed into a prompt."""
    review = _review_module()
    ludo.KEY = ludo.api_key()
    todo = []
    for name in (CONCEPT_BATCH, MODEL_BATCH):
        if not os.path.exists(os.path.join(ROOT, "review", name, "batch.json")):
            continue
        review.write_rejected(name)
        rj = json.load(open(os.path.join(ROOT, "review", name, "rejected.json")))
        for e in rj:
            row = (e.get("meta") or {}).get("row")
            if row:
                print("rejected %s/%s: %s" % (name, e["id"], e.get("note") or "(no note)"))
                todo.append(row)
    if not todo:
        print("nothing rejected")
        return
    state = load_state()
    if state.get("balance_before") is None:
        state["balance_before"] = SENTINEL
        F.save_state(state)
    for row in todo:
        F.reroll(row, "rejected in the Review Table")
    for stage in ("bases1", "bases2", "poses", "portraits1", "portraits2", "models"):
        F.run(stage, [r for r in todo], 2, 2.0)
    batches()


def cost():
    tot = {}
    for r in rows():
        endpoint = {"edit": "/assets/image/edit", "styled": "/assets/image/style", "image": "/assets/image",
                    "model3d": "/assets/3d-model"}[r["kind"]]
        tot[r["stage"]] = tot.get(r["stage"], 0) + F.PRICE[endpoint] * r.get("n", 1)
    for k, v in tot.items():
        print("%-10s %6.1f credits" % (k, v))
    print("%-10s %6.1f credits (cap %.0f, issue cap %.0f)" % ("total", sum(tot.values()), CAP, JOB_CAP))


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
        print("account credits available %.1f (shared); this batch has spent %.2f" % (
            float(ludo.account().get("available", 0.0)), ledger_spent()))
    elif cmd == "spent":
        print("%.2f of %.0f credits (stop line %.0f)" % (ledger_spent(), JOB_CAP, CAP))
    elif cmd == "run":
        only = opt.get("only", "").split(",") if opt.get("only") else []
        run(rest[0], only, int(opt.get("jobs", 2)), float(opt.get("hours", 3)))
    elif cmd == "pick":
        F.pick(rest[0], int(rest[1]), rest[2] if len(rest) > 2 else None, bool(opt.get("deshadow")))
    elif cmd == "pick-portrait":
        pick_portrait(rest[0], int(rest[1]), float(opt.get("zoom", 1.0)), float(opt.get("dx", 0.0)),
                      float(opt.get("dy", 0.0)))
    elif cmd == "reroll":
        F.reroll(rest[0], " ".join(rest[1:]))
    elif cmd == "strip":
        F.strip(rest[0])
    elif cmd == "batches":
        batches()
    elif cmd == "install-accepted":
        install_accepted(bool(opt.get("dry-run")))
    elif cmd == "regen":
        regen()
    elif cmd == "board":
        board()
    else:
        print(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
