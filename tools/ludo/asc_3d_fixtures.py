#!/usr/bin/env python3
"""asc-3d-fixtures: fixtures on 3D models (ART-PIPE 3, issue #196): two ways to keep the Bloodsworn's forearm blades on its
strike model, tried side by side.

Alex 10-10: the Bloodsworn's arm blades keep vanishing in image-to-3D (the pose pictures draw both, the 3D step loses thin
parts, and a held sword appears in their place); the strike was rejected twice (m4_redo, m4_redo2). "We'll have to figure out a
way to address this for any models with fixtures on them." This batch tests, on that one pose:

  a) ATTACHMENTS   the blade is its own small model (a picture of one blade alone, bone-white in the Bloodsworn's style, then
                   Ludo 3D), and the figure carries it: `attachments` on a unit row of world3d/models.json (a mesh and, per
                   pose, a position, rotation and scale; world3d/models.gd bakes it into the pose's mesh), placed on the forearms
                   of the body the game has now (tools/shots/fixture_sheet.gd draws and exports it);
  b) FUSED BLADES  the strike picture re-rolled with the blades drawn thick, bone-white and grown out of the forearm (the
                   accepted march and fallen pictures draw them so), then the model from the best one.

It reuses asc_3d_factions.py's driver (credit cap, retries, ledger, picks, re-rolls) under its own batch: the manifest is
tools/ludo/batches/asc-3d-fixtures.json and every charged call is a line of studio/ledgers/asc-3d-fixtures.jsonl, tagged with
the round of #179's redo (`ROUND`, 120 credits across the batch scripts: asc_3d_grok.py has 70 of them, spent 58; the free holds
script 50, spent 3). CAP is this issue's stop line (the brief: about 25 credits, stop and report before 35).

    python3 tools/ludo/asc_3d_fixtures.py manifest           # (re)write the batch manifest
    python3 tools/ludo/asc_3d_fixtures.py cost                # what each stage plans to spend
    python3 tools/ludo/asc_3d_fixtures.py spent|account       # this batch's spend (from its ledger) | the account's balance
    python3 tools/ludo/asc_3d_fixtures.py run pictures [--only pic_blade_edit]  # the blade alone (styled / edit), the body, the fused strike
    python3 tools/ludo/asc_3d_fixtures.py pick <row> <k> [name]  # candidate k (1..n) is the pick (`pick pic_blade_edit 2 bloodsworn_blade`)
    python3 tools/ludo/asc_3d_fixtures.py reroll <row> <why>  # a new take: v+1, old candidates to old/
    python3 tools/ludo/asc_3d_fixtures.py run models [--only model_blade]   # every picked picture to a GLB
    python3 tools/ludo/asc_3d_fixtures.py stage <model row> ...   # slim + measure a raw GLB into the staging folder (_stage/)
    python3 tools/ludo/asc_3d_fixtures.py sheet <out.png> <img> ...   # candidates side by side (ffmpeg)

    ## placing a): the candidate row (assets/models/candidates/fixtures/strike_attachments.json, the format of a unit row's
    ## "attachments" in world3d/models.gd) is edited by hand; the placement sheet shows it, and the loop is edit, `place`, look
    python3 tools/ludo/asc_3d_fixtures.py place [row.json]    # the body + attachments from 7 views on a 0.1 graph paper, and forearm close-ups
    python3 tools/ludo/asc_3d_fixtures.py bake [row.json]     # the same baked into one GLB (tools/fixtures/bake.gd), slimmed and measured
    python3 tools/ludo/asc_3d_fixtures.py compare             # the board's look: in the game now / a) loader / a) baked / b) fused, 4 cameras
    python3 tools/ludo/asc_3d_fixtures.py story               # sheets of the pictures rolled and the models' snapshots
    python3 tools/ludo/asc_3d_fixtures.py batch               # review/m4_fixtures from the staged files, the row and the sheets

Nothing here installs anything: the candidates (pictures, raw GLBs, the staged and baked models) stay in the gitignored
candidates/ folders and the review batch, and the pick pictures too (PICKS is under them): no Ludo output of this batch is
committed, and no row of world3d/models.json or assets/models/models.json is written. The Bloodsworn's base is grandfathered
(Alex accepted its ready model on 10-8, base_gate.py), so the gate is open; every row still asks it before it spends.

Prompts: positive wording only (a negative is drawn, STYLE_BIBLE §3 rule 1; `check_prompt` refuses one), so "thick, fused,
no gap, no hilt" is said as what the blade IS: a slab of bone as broad as the forearm, grown out of its bone as one piece.
"""
import filecmp
import glob
import json
import os
import shutil
import subprocess
import sys

HERE =os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import asc_3d_grok as G  # noqa: E402  (the Bloodsworn's base gate, its pictures and its pose lines; it also loads the driver)
import base_gate  # noqa: E402
import glb_slim  # noqa: E402

F = G.F
ROOT = F.ROOT
BATCH = "asc-3d-fixtures"
MANIFEST = os.path.join(ROOT, "tools", "ludo", "batches", BATCH + ".json")
LEDGER = os.path.join(ROOT, "studio", "ledgers", BATCH + ".jsonl")
ROUND = G.ROUND  ## "redo-10-8": the same round's tag as asc_3d_grok.py, so the round's spend can be added up
CAP = 35.0  ## the brief's stop line (about 25 credits planned)
SENTINEL = G.SENTINEL
RID = "ascfx"
PIC_CAND = "assets/_concept/candidates/fixtures"
GLB_CAND = "assets/models/candidates/fixtures"
PICKS = PIC_CAND + "/picks"  ## the picks are candidates too: gitignored, never committed (nothing of this batch is installed)
REVIEW_BATCH = "m4_fixtures"
FAMILY = "bloodsworn"
STRIKE = "strike"
## A fixture is drawn on every figure that wears it (two blades on each Bloodsworn of an army), so its triangles count several times.
## v1 asked for 3000 (a small prop, a bit over half a figure's 5000): two of them doubled the strike figure's faces. v2 asks for 1200
## (a third of the triangles), 4 credits more: it came back in a brighter, redder palette than the body's, so a) is placed with v1.
FACES_BLADE = 1200
FACES_FIGURE = 5000
TEX_BLADE = 512
TEX_FIGURE = 512

## The blade, alone. Styled from the Bloodsworn's ready picture (the style image), so it is bone-white with the same dark ink
## outline and red veining. Upright, root at the bottom and tip at the top, so the model's long axis is +Y and the root end
## is the one that sinks into a forearm.
BLADE_BLOCK = ("Concept picture of one game prop for a 3D model, drawn in the same detailed hand-painted inked illustration "
               "style as the reference picture, with thick dark ink outlines and the same bone-white colour with thin dark "
               "red veins and blood streaks")
BLADE_SUBJECT = ("a single curved arm blade of a werewolf warrior, a long thick blade of bone with a saw-toothed notched back "
                 "edge, a broad rounded bony base at its lower end where it grows out of an arm, the blade sweeping up from "
                 "the base in one long smooth curve to a sharp point, standing upright on its own in the middle of the "
                 "picture, seen from three-quarter view slightly from above so its flat face and its thick edge both show, "
                 "the whole blade in view with wide empty margin on every side, plain flat light grey background")
BLADE_PROMPT = "%s. Subject: %s." % (BLADE_BLOCK, BLADE_SUBJECT)

## b) the strike line. The first strike lines said "slashing with his right arm blade raised" and "his fist closed under the
## blade": the picture model drew a sword in a fist (Alex: "gave him a sword in his hand"). The accepted march and fallen
## lines say the blades GROW from the forearms and the claws are open and empty; this one says what the blade is made of
## and how wide it is, and puts both blades on both forearms with both hands open.
## v1 (three takes) drew both blades growing from the bracers with open claws and no held sword, but as thin crescents: "from each
## forearm a thick curved bone-white blade grows as one solid slab of bone as broad as the forearm itself". v2 asks harder for
## the thickness: a heavy slab as thick and as wide as the forearm, the forearm the root of the blade.
STRIKE_FUSED = ("leaping forward in a savage lunge with both arms thrown wide and both hands open, the claws spread and "
                "empty, and from each forearm grows one heavy thick curved bone-white blade with a saw-toothed back and "
                "dark red veins, a broad solid slab of bone as thick and as wide as the forearm itself along most of its "
                "length, grown out of the forearm's own bone as one piece with the arm so that the forearm is the root of "
                "the blade, running on past the wrist beside the open hand in one long curve to a sharp point, each blade "
                "swings with its arm, his right arm swung up and back with its blade high over his head, his left arm "
                "thrusting forward with its blade pointing ahead, mouth open in a snarl")

## a) the body: none of the strike models Alex saw can carry blades on top (each has a sword held in the fist or one blade lost,
## and the one the game has now is the older red-and-black Bloodsworn with daggers in its hands, another look than the accepted
## ready, march and fallen). So the body is the strike picture again with the forearms bare: spiked bone bracers and open empty
## claws, the way the ready picture's left forearm is. The blades are the attachment's job.
STRIKE_BODY = ("leaping forward in a savage lunge with both arms thrown wide and both hands open, the claws spread and "
               "empty, a spiked bone bracer wrapped round each forearm with short bone spikes along it and the forearms "
               "otherwise bare, his right arm swung up and back, his left arm thrusting forward, mouth open in a snarl")

## a) the blade alone, a second way: an edit of the ready picture that keeps only its big blade, so the blade is the accepted
## art's own (the styled blade above is a new drawing in the same style).
BLADE_EDIT = ("Only the big curved bone-white blade of this figure's arm, enlarged to fill the picture, the same saw-toothed "
              "bone blade with the same dark red veins and blood streaks exactly as drawn, standing upright on its own with "
              "its broad bony base at the bottom and its point at the top, seen from three-quarter view slightly from "
              "above, the whole blade in view with wide empty margin on every side, plain flat light grey background.")


def pick_path(name):
    return "%s/bloodsworn_%s.webp" % (PICKS, name)


def stage_dir():
    return os.path.join(ROOT, GLB_CAND, "_stage")


def rows():
    """The batch's rows in run order: two pictures, then a model of each pick."""
    ready = G.pick_of(FAMILY, "ready")
    return [
        {"id": "pic_blade", "stage": "pictures", "kind": "styled", "n": 3, "style_file": ready, "prompt": BLADE_PROMPT,
         "pick_to": pick_path("blade"), "group": "pictures", "unit": FAMILY, "pose": "blade"},
        {"id": "pic_blade_edit", "stage": "pictures", "kind": "edit", "n": 3, "from_file": ready, "prompt": BLADE_EDIT,
         "pick_to": pick_path("blade_edit"), "group": "pictures", "unit": FAMILY, "pose": "blade"},
        {"id": "pic_strike_body", "stage": "pictures", "kind": "edit", "n": 3, "from_file": ready,
         "prompt": F.C_POSE.format(pose=STRIKE_BODY, view=F.VIEW), "pick_to": pick_path("strike_body"),
         "group": "pictures", "unit": FAMILY, "pose": STRIKE},
        {"id": "pic_strike_fused", "stage": "pictures", "kind": "edit", "n": 3, "from_file": ready,
         "prompt": F.C_POSE.format(pose=STRIKE_FUSED, view=F.VIEW), "pick_to": pick_path("strike_fused"),
         "group": "pictures", "unit": FAMILY, "pose": STRIKE},
        {"id": "model_blade", "stage": "models", "kind": "model3d", "from_file": pick_path("blade"), "faces": FACES_BLADE,
         "texture_size": 1024, "texture_type": "pbr", "slim_max": TEX_BLADE, "group": "models", "unit": FAMILY,
         "pose": "blade"},
        {"id": "model_strike_body", "stage": "models", "kind": "model3d", "from_file": pick_path("strike_body"),
         "faces": FACES_FIGURE, "texture_size": 1024, "texture_type": "pbr", "slim_max": TEX_FIGURE, "group": "models",
         "unit": FAMILY, "pose": STRIKE},
        {"id": "model_strike_fused", "stage": "models", "kind": "model3d", "from_file": pick_path("strike_fused"),
         "faces": FACES_FIGURE, "texture_size": 1024, "texture_type": "pbr", "slim_max": TEX_FIGURE, "group": "models",
         "unit": FAMILY, "pose": STRIKE},
    ]


def _jload(path):
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
        "batch": BATCH, "rid_prefix": RID, "cap": CAP, "round": ROUND,
        "note": "Written by tools/ludo/asc_3d_fixtures.py (which holds the prompts; edit it, not this file). #196: the "
                "Bloodsworn strike's forearm blades, as an attachment (a picture of the blade alone, then its model) and as "
                "thick fused blades in the strike picture. balance_before is a fixed sentinel: the account is shared, the "
                "spend is counted from this batch's ledger lines tagged with the round.",
        "style": {"image": "", "art_style": "Cel-Shaded", "blocks": {"C-pose (no base)": F.C_POSE}},
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
        stem = r["id"].split("_", 1)[1]
        a["out"] = (GLB_CAND if a["kind"] == "model3d" else PIC_CAND) + "/" + stem
        man["assets"].append(a)
    os.makedirs(os.path.dirname(MANIFEST), exist_ok=True)
    with open(MANIFEST, "w") as f:
        json.dump(man, f, indent=1)
        f.write("\n")
    return man


def manifest_rows():
    return {a["id"]: a for a in _jload(MANIFEST)["assets"]}


# ---------------------------------------------------------------------------------- the driver, pointed at this batch
## asc_3d_grok.py set the driver's module globals for its own batch when it was imported; point them at this one.
F.BATCH, F.MANIFEST, F.LEDGER, F.CAP, F.RID, F.ROUND = BATCH, MANIFEST, LEDGER, CAP, RID, ROUND
F.SCRATCH = os.path.join(ROOT, GLB_CAND, "_review")
F.rows = rows
F.write_manifest = write_manifest
F.load_state = load_state


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


F.account = lambda: SENTINEL - ledger_spent(ROUND)


def round_state():
    st = load_state()
    if st.get("balance_before") != SENTINEL:
        st["balance_before"] = SENTINEL
        F.save_state(st)
    return st


def gate_row(row):
    """No row is submitted while the Bloodsworn's base is not accepted (base_gate.BaseNotAccepted: nothing is charged)."""
    G.GATE.require(row["unit"])


F.GATE_ROW = gate_row


def run(stage, only, jobs, hours):
    try:
        G.GATE.require_all([FAMILY])
    except base_gate.BaseNotAccepted as e:
        sys.exit("refused (the base comes first):\n%s" % e)
    round_state()
    F.run(stage, only, jobs, hours)


def cost():
    tot = {}
    for r in rows():
        endpoint, _ = ("/assets/3d-model", None) if r["kind"] == "model3d" else (
            "/assets/image/style" if r["kind"] == "styled" else "/assets/image/edit", None)
        tot[r["stage"]] = tot.get(r["stage"], 0.0) + F.PRICE[endpoint] * r.get("n", 1)
        print("%-20s %-10s %5.1f credits" % (r["id"], r["stage"], F.PRICE[endpoint] * r.get("n", 1)))
    print("one pass: %.1f credits; cap %.0f (the round %s; spent here so far %.2f)" % (sum(tot.values()), CAP, ROUND,
                                                                                         ledger_spent(ROUND)))


def staged_path(row_id, version=None):
    """Where a model row's staged GLB is: _stage/<stem>.glb, or _stage/<stem>_v<n>.glb for an earlier take of the row."""
    return os.path.join(stage_dir(), row_id[len("model_"):] + ("_v%d" % version if version else "") + ".glb")


BLADE_USED = "model_blade"  ## the blade a) is placed with ...
BLADE_USED_VERSION = 1  ## ... its first take (3000 faces): the 1200-face re-roll came back in a brighter palette than the body's


def stage(row_id, version=None):
    """A model row's raw Ludo GLB slimmed (glb_slim --albedo-only: the colour map only, JPEG, at most `slim_max` px) into the
    staging folder, and measured. What the review batch and the placement sheets load. `version`: an earlier take of the row
    (a re-roll moves the old GLB to old/v<n>_<name>.glb)."""
    a = manifest_rows()[row_id]
    src = os.path.join(ROOT, a["out"] + ".glb")
    if version:
        src = os.path.join(os.path.dirname(src), "old", "v%d_%s.glb" % (version, os.path.basename(src)[:-4]))
    if not os.path.exists(src):
        sys.exit("no GLB for %s (run `run models --only %s`)" % (row_id, row_id))
    dst = staged_path(row_id, version)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    before, after = glb_slim.slim(src, dst, 3, a["slim_max"], True)
    m = F.measure(dst)
    print("stage %-20s %.2f -> %.2f MB, %d faces, extent %s -> %s" % (row_id, before / 1e6, after / 1e6, m["faces"], m["size"],
                                                                      os.path.relpath(dst, ROOT)))
    return m


# ------------------------------------------------------------------------------------ sizes, sheets, the combined model
GODOT = G.GODOT
BOARD_TABLE = os.path.join(ROOT, "world3d", "models.json")
STAGE_RES = "res://" + GLB_CAND + "/_stage/"
GAME_STRIKE = "assets/models/units/beasts/bloodsworn_strike.glb"  ## what the game has now (the review items' target)
SHEETS = os.path.join(ROOT, GLB_CAND, "_review")
FONT = "/System/Library/Fonts/Supplemental/Arial.ttf"
## The share of each model's own box height (head top to feet) that is the body, read off a front view of the model with the
## 0.1 graph paper of `place` (the head top at y = 0.31 and the feet at -0.411 in the body's space; 0.33 and -0.488 in the fused
## one): the reviewed reading of asc_3d_grok.READING, to about 2%. The game sizes a pose from it: men = body / share.
BODY_SHARE = {"strike_body": 0.87, "strike_fused": 0.83}
BODY_MEN = G.body_of_family(FAMILY)  ## the Bloodsworn's body in men, as every pose of it is sized


def attachments_path():
    """The candidate row of a): {"attachments": [...]}, the format of a figure row of world3d/models.json (world3d/models.gd)."""
    return os.path.join(ROOT, GLB_CAND, "strike_attachments.json")


def men_for(name, box_y=None):
    """The size in men a pose model stands at so its body is the Bloodsworn's: BODY_MEN over the body's share of the model's box.
    `box_y` is a bigger box (the body with its blades added): the same scale over the taller box."""
    men = BODY_MEN / BODY_SHARE[name]
    if box_y:
        men *= box_y / F.measure(staged_path("model_" + name))["size"][1]
    return round(men, 3)


def _run_godot(args, windowed=False, timeout=900):
    """One Godot process (the repo's rule: one at a time on this Mac), imported first so new GLBs are known. Windowed runs are
    always on top: an occluded window never draws and the run hangs."""
    imp = subprocess.run([GODOT, "--headless", "--path", ROOT, "--import"], capture_output=True, text=True, timeout=timeout)
    if imp.returncode != 0:
        sys.exit("godot --import failed:\n%s" % imp.stdout[-800:])
    cmd = [GODOT, "--always-on-top" if windowed else "--headless", "--path", ROOT] + args
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)


def bake(row_file=None):
    """The combined strike model of a): the strike body and the attachments of the row file baked into one mesh and one colour map
    (tools/fixtures/bake.gd, headless), slimmed to a GLB the Review Table shows and the game loads like any model. Its size in
    men is the body's (the blades add to the box, so it is taller than the body's: men_for)."""
    row_file = row_file or attachments_path()
    raw = os.path.join(ROOT, GLB_CAND, "baked", "strike_attach_raw.glb")
    os.makedirs(os.path.dirname(raw), exist_ok=True)
    r = _run_godot(["-s", "res://tools/fixtures/bake.gd", "--", "--body=" + STAGE_RES + "strike_body.glb", "--pose=strike",
                    "--row=" + os.path.abspath(row_file), "--out=" + raw])
    if not os.path.exists(raw) or "baked " not in r.stdout:
        sys.exit("bake failed:\n%s%s" % (r.stdout[-1500:], r.stderr[-800:]))
    dst = staged_path("model_strike_attach")
    before, after = glb_slim.slim(raw, dst, 3, 1024, True)  ## the stack is two maps tall: 1024 keeps both at 512
    m = F.measure(dst)
    rec = {"men": men_for("strike_body", m["size"][1]), "axis": "height", "faces": m["faces"], "bytes": after, "extent": m["size"]}
    save_records("strike_attach", rec)
    print("bake %s: %.2f -> %.2f MB, %d faces, extent %s, %.3f men" % (os.path.relpath(dst, ROOT), before / 1e6, after / 1e6,
                                                                       m["faces"], m["size"], rec["men"]))
    return rec


def records_path():
    return os.path.join(stage_dir(), "fixtures.json")


def load_records():
    return _jload(records_path()) if os.path.exists(records_path()) else {}


def save_records(name, rec):
    st = load_records()
    st[name] = rec
    os.makedirs(stage_dir(), exist_ok=True)
    with open(records_path(), "w") as f:
        json.dump(st, f, indent=1, sort_keys=True)


def _unit_row():
    with open(BOARD_TABLE) as f:
        return json.load(f)["figures"][FAMILY]


def _row_with(men, extra=None):
    """The Bloodsworn's row as it stands in world3d/models.json, its strike pose sized `men`, and `extra` set over it: a candidate
    row, built in memory (the installed table is never written)."""
    row = json.loads(json.dumps(_unit_row()))
    row["pose_size"][STRIKE] = {"axis": "height", "men": men}
    row.update(extra or {})
    return row


def _xstack(cells, out, cols, w, h, labels=None):
    """Pictures side by side (ffmpeg xstack), each fitted to w x h on grey, with a label in its corner when given."""
    ins, flt, layout = [], "", []
    for i, p in enumerate(cells):
        ins += ["-i", p]
        lab = ""
        if labels and labels[i]:
            lab = (",drawtext=fontfile=%s:text='%s':x=8:y=8:fontsize=22:fontcolor=0x1a1a22:box=1:boxcolor=white@0.75:boxborderw=4"
                   % (FONT, labels[i].replace("'", "").replace(":", " -")))
        flt += ("color=c=0xC8C8C8:s=%dx%d[g%d];[%d]scale=%d:%d:force_original_aspect_ratio=decrease,format=rgba[a%d];"
                "[g%d][a%d]overlay=(W-w)/2:(H-h)/2:shortest=1%s[s%d];" % (w, h, i, i, w, h, i, i, i, lab, i))
        layout.append("%d_%d" % ((i % cols) * w, (i // cols) * h))
    flt += "".join("[s%d]" % i for i in range(len(cells)))
    flt += ("xstack=inputs=%d:layout=%s:fill=0x808080" % (len(cells), "|".join(layout))) if len(cells) > 1 else "null"
    os.makedirs(os.path.dirname(out), exist_ok=True)
    subprocess.run([F.FF, "-y", "-loglevel", "error", *ins, "-filter_complex", flt, "-frames:v", "1", out], check=True)
    return out


def _shoot(plan, subdir, res="640x640"):
    """tools/fixtures/sheet.gd over a plan (a list of shots), one windowed Godot: the pictures land in SHEETS/<subdir>/."""
    out = os.path.join(SHEETS, subdir)
    os.makedirs(out, exist_ok=True)
    pf = os.path.join(SHEETS, subdir + "_plan.json")
    with open(pf, "w") as f:
        json.dump(plan, f)
    r = _run_godot(["--resolution", res, "-s", "res://tools/fixtures/sheet.gd", "--", "--plan=" + pf, "--out=" + out], windowed=True)
    done = [s["file"] for s in plan if ("shot " + s["file"]) in r.stdout]
    if len(done) != len(plan):
        sys.exit("the sheet run drew %d of %d shots:\n%s%s" % (len(done), len(plan), r.stdout[-1500:], r.stderr[-800:]))
    return out


RAW_VIEWS = (("front", dict(view="front")), ("right", dict(view="right")), ("back", dict(view="back")), ("left", dict(view="left")),
             ("top", dict(view="top")), ("3/4", dict(yaw=35, pitch=12)), ("3/4 other side", dict(yaw=-40, pitch=12)))
ZOOMS = (("right forearm", [-0.30, 0.30, 0.0], 0, 0), ("right forearm 3/4", [-0.30, 0.30, 0.0], 50, 25),
         ("left forearm", [0.30, 0.12, 0.0], 0, 0), ("left forearm 3/4", [0.30, 0.12, 0.0], -50, 25))


def place_plan(row, body="strike_body"):
    """The shots of the placement sheet: seven views of the body with the row's attachments, then four forearm close-ups (the first
    len(RAW_VIEWS) are the views). Pure: the plan tools/fixtures/sheet.gd reads."""
    path = STAGE_RES + body + ".glb"
    plan = []
    for name, v in RAW_VIEWS:
        plan.append(dict({"file": "p_%s.png" % name.replace("/", "q").replace(" ", "_"), "title": name, "mode": "raw", "extent": 0.62,
                          "center": [0, 0, 0], "items": [{"path": path, "pose": STRIKE, "row": row}]}, **v))
    for name, c, yaw, pitch in ZOOMS:
        plan.append({"file": "z_%s.png" % name.replace(" ", "_").replace("/", "q"), "title": name, "mode": "raw", "yaw": yaw, "pitch": pitch,
                     "extent": 0.2, "center": c, "items": [{"path": path, "pose": STRIKE, "row": row}]})
    return plan


def place(row_file=None, out=None, body="strike_body"):
    """The placement sheet (the numbers to tune): the body with the attachments of the row file, in the body's OWN space, from seven
    views with a graph paper of 0.1 along the edges (the numbers a row's pos takes), then four close-ups of the forearms. Edit the
    row file, run this, look, repeat: the tool of a). Writes SHEETS/a_placement.png and SHEETS/a_placement_zoom.png."""
    row_file = row_file or attachments_path()
    with open(row_file) as f:
        row = json.load(f)
    plan = place_plan(row, body)
    d = _shoot(plan, "placement")
    files = [os.path.join(d, s["file"]) for s in plan]
    o = out or os.path.join(SHEETS, "a_placement.png")
    _xstack(files[:7], o, 4, 480, 480)
    _xstack(files[7:], o.replace(".png", "_zoom.png"), 4, 480, 480)
    print(o)
    return o


CAMERAS = (("near", 22, 42), ("side", 75, 30), ("back", 165, 42), ("low", 20, 12))  ## name, the figures' turn, the camera's pitch


def compare_plan(att, baked_men):
    """The shots of the board comparison: four figures as the board draws them, from each camera. The first is what the game has now
    (its row exactly as world3d/models.json holds it); a) the strike body with `att` (the row's attachments: the loader) and the same
    baked into one GLB (sized `baked_men`); b) the fused-blades model. Pure: rows are built in memory, the table is never written."""
    items = [
        {"label": "in the game now", "path": "res://" + GAME_STRIKE, "type": FAMILY, "pose": STRIKE, "row": _unit_row(), "faction": "beasts"},
        {"label": "a) attachments (loader)", "path": STAGE_RES + "strike_body.glb", "type": FAMILY, "pose": STRIKE,
         "row": _row_with(men_for("strike_body"), {"attachments": att}), "faction": "beasts"},
        {"label": "a) baked in one GLB", "path": STAGE_RES + "strike_attach.glb", "type": FAMILY, "pose": STRIKE,
         "row": _row_with(baked_men), "faction": "beasts"},
        {"label": "b) fused blades", "path": STAGE_RES + "strike_fused.glb", "type": FAMILY, "pose": STRIKE,
         "row": _row_with(men_for("strike_fused")), "faction": "beasts"},
    ]
    return [{"file": "board_%s.png" % n, "title": "Bloodsworn strike: %s" % n, "mode": "board", "yaw": y, "pitch": p, "items": items}
            for n, y, p in CAMERAS]


def compare(out=None):
    """The board's look of the strike pose, four figures side by side as the board draws them (Models._glb_figure through a row: the
    sizing, the turn, the team base, Look A): what the game has now; a) the body with its attachments (the loader, from a row
    that names them); a) the same baked into one GLB (what the Review Table shows); b) the fused-blades model. Four cameras:
    the board's near one, from the side, from behind, and low. Writes SHEETS/compare_board.png."""
    with open(attachments_path()) as f:
        att = json.load(f)["attachments"]
    plan = compare_plan(att, load_records()["strike_attach"]["men"])
    d = _shoot(plan, "board", "1280x720")
    o = out or os.path.join(SHEETS, "compare_board.png")
    _xstack([os.path.join(d, s["file"]) for s in plan], o, 2, 1280, 720)
    print(o)
    return o


def candidate_files(stem, folder=PIC_CAND):
    return sorted(glob.glob(os.path.join(ROOT, folder, "%s_c[0-9].*" % stem)))


def story_sheets(outdir=None):
    """Sheets of how each candidate was made, from the files the batch keeps: the pictures rolled (each round's takes, the pick)
    and the models' own snapshots. a_pictures: the blade alone (styled, edit) and the body without blades; b_pictures: the
    fused strike's two rounds (the first round's takes are in old/) and its model."""
    outdir = outdir or SHEETS
    old = os.path.join(ROOT, PIC_CAND, "old")
    snap = lambda stem: sorted(glob.glob(os.path.join(ROOT, GLB_CAND, stem + "_snap*.png")))[:4]  # noqa: E731
    picks = load_state().get("picks", {})

    def mark(row_id, k):  ## " [PICK]" on the take the batch went on with (state picks: "<row>" or "<row>:<name>")
        return " [PICK]" if any(key.split(":")[0] == row_id and v == k for key, v in picks.items()) else ""
    cells, labels = [], []
    for stem, row_id, what in (("blade", "pic_blade", "blade (styled)"), ("blade_edit", "pic_blade_edit", "blade (edit)"),
                               ("strike_body", "pic_strike_body", "a) body, forearms bare")):
        for k, p in enumerate(candidate_files(stem), 1):
            cells.append(p)
            labels.append("%s take %d%s" % (what, k, mark(row_id, k)))
    a1 = _xstack(cells, os.path.join(outdir, "a_pictures.png"), 3, 460, 460, labels)
    cells, labels = [], []
    for k in (1, 2, 3):
        p = os.path.join(old, "v1_strike_fused_c%d.webp" % k)
        if os.path.exists(p):
            cells.append(p)
            labels.append("b) round 1 take %d" % k)
    for k, p in enumerate(candidate_files("strike_fused"), 1):
        cells.append(p)
        labels.append("b) round 2 take %d%s" % (k, mark("pic_strike_fused", k)))
    for i, p in enumerate(snap("strike_fused")):
        cells.append(p)
        labels.append("b) the model, snapshot %d" % (i + 1))
    b1 = _xstack(cells, os.path.join(outdir, "b_pictures.png"), 3, 460, 460, labels)
    cells, labels = [], []
    old_snaps = sorted(glob.glob(os.path.join(ROOT, GLB_CAND, "old", "v1_blade_snap*.png")))[:4]
    for what, snaps in (("a) blade, 3000 faces (used)", old_snaps), ("blade re-roll, 1200 faces", snap("blade")),
                        ("a) the body model", snap("strike_body"))):
        for i, p in enumerate(snaps):
            cells.append(p)
            labels.append("%s, snapshot %d" % (what, i + 1))
    a2 = _xstack(cells, os.path.join(outdir, "a_models.png"), 4, 380, 380, labels)
    print(a1)
    print(a2)
    print(b1)
    return a1, a2, b1


def build_sidecar():
    """review.py from-folder's prompts.json for the batch: group, label, what it is (the text), the target (what the game has now) and
    the meta Install accepted reads (the size in men, so a model that is accepted stands at the Bloodsworn's size)."""
    rec = load_records()
    fused = F.measure(staged_path("model_strike_fused"))
    meta = {"row": "model_bloodsworn_strike", "family": FAMILY, "pose": STRIKE, "descriptor_group": "units", "side": "Blood Pact",
            "art": G.FAMILIES[FAMILY]["art"]}
    return {
        "strike/bloodsworn_strike_attach.glb": {
            "group": "strike", "label": "Bloodsworn · strike · a) attachments", "target": GAME_STRIKE,
            "prompt": "a) ATTACHMENTS: the strike body modelled with bare forearms (a spiked bone bracer on each), and the blade, a "
                      "small model of its own (%d faces), attached to each forearm. In the game the blades are two entries of an "
                      "`attachments` list on the unit's row (world3d/models.gd draws them; see attachments.json and sheets/); here "
                      "the same figure is baked into one mesh so it shows in this viewer and could be installed as it is."
                      % F.measure(staged_path(BLADE_USED, BLADE_USED_VERSION))["faces"],
            "meta": dict(meta, size={"axis": "height", "men": rec["strike_attach"]["men"]}, body_share=BODY_SHARE["strike_body"],
                         faces=rec["strike_attach"]["faces"])},
        "strike/bloodsworn_strike_fused.glb": {
            "group": "strike", "label": "Bloodsworn · strike · b) fused blades", "target": GAME_STRIKE,
            "prompt": "b) FUSED BLADES: the ready picture edited to: the same figure, now %s. The second round's take 2 (both blades "
                      "thick, bone-white and grown out of the forearm, the hands open, no hilt and no grip), then image-to-3D: one "
                      "model, nothing attached." % STRIKE_FUSED,
            "meta": dict(meta, size={"axis": "height", "men": men_for("strike_fused")}, body_share=BODY_SHARE["strike_fused"],
                         faces=fused["faces"])},
        "parts/bloodsworn_blade.glb": {
            "group": "parts", "label": "The blade alone (the fixture of a)",
            "prompt": "The blade of a): an edit of the ready picture that keeps only its big blade (take 2 of 3), then image-to-3D at "
                      "3000 faces (first take of the model). Not for the game on its own: it is what the strike's two blades are "
                      "made of."},
        "parts/bloodsworn_blade_1200.glb": {
            "group": "parts", "label": "The blade at 1200 faces (a lighter fixture)",
            "prompt": "The same picture to image-to-3D again at 1200 faces, 4 more credits: a third of the triangles for each blade "
                      "(a fixture is drawn on every figure that wears it), but the colour map came back brighter and redder than "
                      "the body's, so a) is placed with the 3000-face take."},
        "parts/bloodsworn_strike_body.glb": {
            "group": "parts", "label": "The strike body, forearms bare (a)",
            "prompt": "The body of a): the ready picture edited to: the same figure, now %s. No blade is drawn at all; image-to-3D "
                      "made the model, and the attachments put the blades on it." % STRIKE_BODY},
    }


def batch(name=REVIEW_BATCH, title="M4 fixtures: the Bloodsworn strike with its forearm blades, two ways"):
    """review/<name> from the staged models: review.py from-folder (the strike items' target is the game's own strike model, so `0`
    compares), the candidate row (attachments.json) and the sheets copied in. No install action: nothing here is installed, and
    the verdicts are the owner's. Run again after a model changes: changed files are refreshed in place, verdicts are kept."""
    rv = os.path.join(ROOT, "tools", "review", "review.py")
    bdir = os.path.join(ROOT, "review", name)
    folder = os.path.join(ROOT, GLB_CAND, "_stage_" + name)
    shutil.rmtree(folder, ignore_errors=True)
    side = build_sidecar()
    for rel, src in (("strike/bloodsworn_strike_attach.glb", staged_path("model_strike_attach")),
                     ("strike/bloodsworn_strike_fused.glb", staged_path("model_strike_fused")),
                     ("parts/bloodsworn_blade.glb", staged_path(BLADE_USED, BLADE_USED_VERSION)),
                     ("parts/bloodsworn_blade_1200.glb", staged_path("model_blade")),
                     ("parts/bloodsworn_strike_body.glb", staged_path("model_strike_body"))):
        os.makedirs(os.path.dirname(os.path.join(folder, rel)), exist_ok=True)
        shutil.copy2(src, os.path.join(folder, rel))
    with open(os.path.join(folder, "prompts.json"), "w") as f:
        json.dump(side, f, indent=1)
    cmd = [sys.executable, rv, "from-folder", folder, name, "--title", title, "--recursive", "--sidecar",
           os.path.join(folder, "prompts.json")]
    if os.path.exists(os.path.join(bdir, "batch.json")):
        cmd.append("--add")
    subprocess.run(cmd, check=True, cwd=ROOT)
    bj = os.path.join(bdir, "batch.json")
    data = _jload(bj)
    for it in data["items"]:
        rel = it["file"]
        src, dst = os.path.join(folder, rel), os.path.join(bdir, rel)
        if os.path.exists(src) and (not os.path.exists(dst) or not filecmp.cmp(src, dst, shallow=False)):
            shutil.copy2(src, dst)
            print("refreshed", rel)
        e = side.get(rel)
        if e:
            it["meta"] = e.get("meta") or it.get("meta")
            it["label"], it["text"], it["group"] = e["label"], e["prompt"], e["group"]
            if e.get("target"):
                it["target"] = e["target"]
    data.pop("actions", None)
    data["items"].sort(key=lambda it: (0 if it.get("group") == "strike" else 1, it["id"]))  ## the two candidates first, the parts after
    tmp = bj + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    os.replace(tmp, bj)
    ## the candidate row, and the sheets (plain files in the batch folder: no item lists them)
    with open(attachments_path()) as f:
        row = json.load(f)
    row["_note"] = ("a) as a row of world3d/models.json would hold it: the unit's own `attachments` list (not installed; the installed "
                    "rows have none). mesh is the blade GLB of this batch (parts/bloodsworn_blade.glb); installed it would be a model "
                    "under assets/models/ and the path would say so. pos/rot/scale are in the strike body's own space "
                    "(parts/bloodsworn_strike_body.glb), pivot is the blade's root; pose_size.strike.men sizes the BODY (%.3f), so "
                    "a row that draws the attachments sizes the pose by this, not by the baked strike_attach model's %.3f."
                    % (men_for("strike_body"), load_records()["strike_attach"]["men"]))
    with open(os.path.join(bdir, "attachments.json"), "w") as f:
        json.dump(row, f, indent=1)
        f.write("\n")
    os.makedirs(os.path.join(bdir, "sheets"), exist_ok=True)
    for p in glob.glob(os.path.join(SHEETS, "*.png")):
        shutil.copy2(p, os.path.join(bdir, "sheets", os.path.basename(p)))
    print("batch %s: %d items, no actions; sheets: %s" % (name, len(data["items"]), sorted(os.listdir(os.path.join(bdir, "sheets")))))


def sheet(out, names):
    """Pictures side by side: sheet <out.png> <img> ... (a quick look at candidates, ffmpeg)."""
    _xstack(names, out, min(4, len(names)), 520, 520)
    print(out)


def reroll(row_id, why):
    """A new take of a row (v+1, the old candidates to old/): the driver's reroll, on this batch's manifest."""
    F.reroll(row_id, why)


def pick(row_id, k, name=None):
    """Candidate k of a picture row is the pick (webp, at most 1024 px). `name` writes it as another pick: the blade's model
    reads PICKS/bloodsworn_blade.webp, so `pick pic_blade_edit 2 bloodsworn_blade` makes the edit's take 2 the blade."""
    F.pick(row_id, k, name)


def _opts(argv):
    opt, rest, i = {}, [], 0
    while i < len(argv):
        a = argv[i]
        if a.startswith("--"):
            if i + 1 < len(argv) and not argv[i + 1].startswith("--"):
                opt[a[2:]] = argv[i + 1]
                i += 1
            else:
                opt[a[2:]] = True
        else:
            rest.append(a)
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
    elif cmd == "spent":
        print("%.2f of the round %s's credits spent by this batch (its cap %.0f)" % (ledger_spent(ROUND), ROUND, CAP))
    elif cmd == "account":
        F.ludo.KEY = F.ludo.api_key()
        print("account credits available %.1f (shared); this batch has spent %.2f of its cap %.0f" % (
            float(F.ludo.account().get("available", 0.0)), ledger_spent(ROUND), CAP))
    elif cmd == "run":
        if not os.path.exists(MANIFEST):
            write_manifest()
        only = opt.get("only", "").split(",") if opt.get("only") else []
        run(rest[0], only, int(opt.get("jobs", 2)), float(opt.get("hours", 3)))
    elif cmd == "pick":
        pick(rest[0], int(rest[1]), rest[2] if len(rest) > 2 else None)
    elif cmd == "reroll":
        reroll(rest[0], " ".join(rest[1:]))
    elif cmd == "stage":
        for r in rest:
            stage(r, int(opt["v"]) if opt.get("v") else None)
    elif cmd == "bake":
        bake(rest[0] if rest else None)
    elif cmd == "place":
        place(rest[0] if rest else None, opt.get("out"), opt.get("body", "strike_body"))
    elif cmd == "compare":
        compare(opt.get("out"))
    elif cmd == "story":
        story_sheets(opt.get("out"))
    elif cmd == "batch":
        batch(opt.get("name", REVIEW_BATCH))
    elif cmd == "sheet":
        sheet(rest[0], rest[1:])
    else:
        print(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
