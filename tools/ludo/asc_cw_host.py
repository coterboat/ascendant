#!/usr/bin/env python3
"""asc-cw-host: the Candlewake host's derive stage (CW-10 #261), ready to run the minute Alex approves its bases.

The bases are in the Review Table batch review/cw_base (made by tools/ludo/batches/cw-base.json): for the Wickwardens,
Half-Death, Mother Tallow and the Lamplighter a ready picture (`<id>_ready`) and its model (`<id>_model`). Nothing here is
made from a base Alex has not kept (tools/ludo/base_gate.py, the same gate as the M4 redo):

    python3 tools/ludo/asc_cw_host.py status            # every family: its base, and what derive would make
    python3 tools/ludo/asc_cw_host.py manifest          # (re)write tools/ludo/batches/cw-host.json from the bases he kept
    python3 tools/ludo/asc_cw_host.py cost              # what the manifest would spend
    python3 tools/ludo/asc_cw_host.py run [ids ...]     # the gate again, then tools/ludo/ludo.py on that manifest

Two kinds of family:
- **derived from a cw_base base** (FAMILIES with "base"): `manifest` copies the take Alex kept to
  assets/_concept/candlewake/<id>_ready.webp and writes its pose edits (march, strike, fallen; the rulers also cheer) and a
  model of every pose. The ready model is the take he kept in `<id>_model` (no call) when that item is accepted, else a new
  model of the kept picture.
- **the rest of the host** (FAMILIES with "after": Gleaners, the Hundred-Wick, the Chandler's Apprentices): their base
  pictures are made only once the Wickwarden's base is kept (the host's look is his), as Ludo edits of their canon figures
  (assets/_concept/lore/candlewake/) into review/cw_host_base for Alex. The Apprentices also wait for his pick in
  review/cw_apprentices (the concept round).

The batches are judged in the Table Alex runs, the main checkout's review/: from a worktree, point the gate at it with
`ASC_REVIEW_DIR=<main checkout>/review` (reading only). Every charged call is a line of studio/ledgers/cw-host.json; credits
in studio/CREDITS.md. Rates (10-22): an edit 0.5, a model 4.0. Stdlib plus ffmpeg.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import base_gate  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
MANIFEST = "tools/ludo/batches/cw-host.json"
LEDGER = "studio/ledgers/cw-host.json"
BASE_BATCH = "cw_base"
HOST_BASE_BATCH = "cw_host_base"
CONCEPT_BATCH = "cw_apprentices"
PICS = "assets/_concept/candlewake"
CANON = "assets/_concept/lore/candlewake"
OUT = "assets/_concept/candlewake/candidates/host"
RATE = {"edit": 0.5, "model3d": 4.0}

POSE_TAIL = (" Same outfit, same colours, same outline style, three-quarter view from slightly above, the whole figure with "
             "wide empty margin on every side, plain flat light grey background.")
FALLEN_TAIL = (" Same outfit, same colours, same outline style, seen from the side and a little above, the whole figure "
               "lying full length, the whole figure with wide empty margin on every side, plain flat light grey background.")
UNLIT = " The short black wick on top of the hood stays bare and unlit."

FAMILIES = {
    "wickwardens": {
        "name": "Wickwardens", "faces": 6000, "base": "wickwardens_ready", "model_item": "wickwardens_model",
        "poses": {
            "march": "The same figure, now marching forward with his left leg striding ahead, the spear held upright close "
                     "to his right side, the tall wax shield carried before him on his left arm, the hood bowed a little "
                     "forward." + UNLIT,
            "strike": "The same figure, now lunging forward on his bent left leg, thrusting the spear straight ahead at waist "
                      "height with his right arm fully extended, the tall wax shield braced before him on his left arm." + UNLIT,
            "fallen": "The same figure, now fallen in battle, lying flat on his back with his arms out to the sides, long wax "
                      "drips hanging from his hood and shoulders, the hood's hollow dark and empty, the spear and the tall wax "
                      "shield lying beside him." + UNLIT,
        }},
    "half_death": {
        "name": "Half-Death", "faces": 12000, "base": "half_death_ready", "model_item": "half_death_model",
        "poses": {
            "march": "The same figure, now striding forward with his left leg ahead, the crooked staff planted forward in his "
                     "right hand with the lilac lantern swinging from it, his free hand raised a little, his tattered robes "
                     "trailing behind him.",
            "strike": "The same figure, now sweeping the crooked staff in a wide low arc with both hands, the lilac lantern "
                      "swinging out at its head, leaning forward into the blow, his robes flaring.",
            "fallen": "The same figure, now fallen in battle, lying flat on his back with his arms out to the sides, his "
                      "tattered robes spread around him, the crooked staff and its lantern lying on the floor beside him, his "
                      "alabaster eye closed.",
            "cheer": "The same figure, now standing tall in victory, the crooked staff raised high above his head in his right "
                     "hand so the lilac lantern hangs above him, his left arm spread wide.",
        }},
    "mother_tallow": {
        "name": "Mother Tallow", "faces": 12000, "base": "mother_tallow_ready", "model_item": "mother_tallow_model",
        "poses": {
            "march": "The same woman, now walking forward with her left foot ahead, the lit taper held before her in her right "
                     "hand, her left hand cupped beside its gold flame to shield it.",
            "strike": "The same woman, now stepping forward on her bent left leg and raising the brass snuffing shears high in "
                      "her right hand to strike, the lit taper held back in her left hand, a fierce look.",
            "fallen": "The same woman, now fallen in battle, lying on her side with her arms before her, the taper lying on "
                      "the floor beside her hand, its flame gone out, her eyes closed.",
            "cheer": "The same woman, now cheering in victory, standing tall with the lit taper raised high above her head in "
                     "her right hand, its gold flame bright, her left fist raised.",
        }},
    "lamplighter": {
        "name": "the Lamplighter", "faces": 8000, "base": "lamplighter_ready", "model_item": "lamplighter_model",
        "poses": {
            "march": "The same figure, now marching forward with his left leg ahead, the tall brass lantern pole held upright "
                     "in his right hand so the lilac lantern rides high above his head, his cloak trailing behind him." + UNLIT,
            "strike": "The same figure, now swinging the tall brass lantern pole two-handed in a wide diagonal blow, the lilac "
                      "lantern swinging at its head, lunging forward on his bent left leg, his cloak flaring." + UNLIT,
            "fallen": "The same figure, now fallen in battle, lying flat on his back with his arms out to the sides, his cloak "
                      "spread around him, the tall lantern pole lying on the floor beside him, its lantern dark." + UNLIT,
        }},
    "gleaners": {
        "name": "Gleaners", "faces": 6000, "after": "wickwardens", "canon": "candlewake_host_war.png", "crop": (915, 1175),
        "ready": "Keep only the lean stooped hooded wax figure holding the long crescent harvesting hook, exactly as drawn: "
                 "the same swept crescent-rim ivory wax hood around a pitch-black hollow face with one small lilac light deep "
                 "inside, the same soot-black wrappings under dripping wax, the same long crescent hook with its brass blade. "
                 "The short black wick on top of the hood is bare and unlit. He stands in a crouched ready stance with his "
                 "feet apart, the hook held out at arm's length with clear space between the hook and his body, his other "
                 "hand open and held a little away from his side.",
        "poses": {
            "march": "The same figure, now stalking forward in a low crouch with his left leg ahead, the crescent hook held "
                     "low and trailing in his right hand." + UNLIT,
            "strike": "The same figure, now lunging forward and reaping with the crescent hook in a wide low sweep, both arms "
                      "extended." + UNLIT,
            "fallen": "The same figure, now fallen in battle, lying flat on his back with his arms out to the sides, the "
                      "crescent hook lying beside him, the hood's hollow dark and empty." + UNLIT,
        }},
    "hundred_wick": {
        "name": "the Hundred-Wick", "faces": 8000, "after": "wickwardens", "canon": "candlewake_hundred_wick__codex.png",
        "crop": None,
        "ready": "The same hulking monster exactly as drawn, one fused dripping mass of hooded ivory wax shells over soot, "
                 "standing alone on two massive planted legs with its long fused arms hanging a little away from its body, "
                 "a crest of many short black wicks along its top, each bare and unlit, three to five hollow hood openings "
                 "in its body each with one small lilac light inside. Three-quarter view from slightly above, the whole "
                 "figure centred with wide empty margin on every side and clear headroom, the same painted style, plain "
                 "flat light grey background everywhere else.",
        "poses": {
            "march": "The same monster, now lumbering forward with its left leg ahead, its long fused arms swinging.",
            "strike": "The same monster, now bringing both long fused arms down in a crushing overhead blow, leaning forward.",
            "fallen": "The same monster, now fallen, slumped on its side full length with its arms out before it, its hood "
                      "openings dark.",
        }},
    "chandlers_apprentices": {
        "name": "the Chandler's Apprentices", "faces": 6000, "after": "wickwardens", "concept": "apprentices",
        "ready": "The same figure exactly as drawn, standing in a relaxed ready stance with the feet apart, the glowing focus "
                 "held up in one hand with clear space between it and the body, the other arm held a little away from the "
                 "side, both hands visible.",
        "poses": {
            "march": "The same figure, now walking forward with the left foot ahead, the glowing focus carried before the "
                     "chest in both hands.",
            "strike": "The same figure, now thrusting the glowing focus forward at arm's length to cast a spell, leaning into "
                      "it on a bent left leg, the other hand raised.",
            "fallen": "The same figure, now fallen in battle, lying flat on the back with the arms out to the sides, the "
                      "focus lying on the floor beside one hand, its light gone out.",
        }},
}
READY_TAIL = (" Three-quarter view from slightly above, the whole figure centred with wide empty margin on every side and "
              "clear headroom, the same painted cel style with thick clean dark outlines, flat colours with one shadow tone "
              "and one highlight, matte finish, even soft light from the front, plain flat light grey background everywhere "
              "else.")


def gate(batch=BASE_BATCH):
    return base_gate.Gate(batch, display=lambda f: FAMILIES[f]["name"] if f in FAMILIES else f)


def check(fam):
    """The family's state: {ok, why, base_file, model_file, stage} where stage is "poses" (its base is kept), "base" (its
    base picture may be made) or None (refused, `why` says so)."""
    f = FAMILIES[fam]
    if "base" in f:
        r = gate().check(fam)
        if not r["ok"]:
            return {"ok": False, "stage": None, "why": r["message"]}
        m = base_gate.item_status(BASE_BATCH, f["model_item"])
        model = str(m["file"]) if m["state"] in ("accepted", "accepted_after_redo") and m["file"] else None
        return {"ok": True, "stage": "poses", "why": "", "base_file": str(r["file"]) if r["file"] else None, "model_file": model}
    lead = gate().check(f["after"])
    if not lead["ok"]:
        return {"ok": False, "stage": None, "why": "%s: waits for the Wickwardens' base (the host's look is his). %s"
                % (f["name"], lead["message"])}
    host = base_gate.Gate(HOST_BASE_BATCH, display=lambda x: FAMILIES[x]["name"]).check(fam)
    if host["ok"]:
        m = base_gate.item_status(HOST_BASE_BATCH, fam + "_model")
        model = str(m["file"]) if m["state"] in ("accepted", "accepted_after_redo") and m["file"] else None
        return {"ok": True, "stage": "poses", "why": "", "base_file": str(host["file"]), "model_file": model}
    if host["state"] not in ("no_batch", "no_item"):
        return {"ok": False, "stage": None, "why": host["message"]}
    if f.get("concept"):
        kept = [k for k in "abc" if base_gate.item_status(CONCEPT_BATCH, "%s_%s" % (f["concept"], k))["state"]
                in ("accepted", "accepted_after_redo")]
        if not kept:
            return {"ok": False, "stage": None, "why": "%s: waits for Alex's pick in review/%s (the concept round)."
                    % (f["name"], CONCEPT_BATCH)}
        st = base_gate.item_status(CONCEPT_BATCH, "%s_%s" % (f["concept"], kept[0]))
        return {"ok": True, "stage": "base", "why": "", "source": str(st["file"]), "note": st["note"]}
    return {"ok": True, "stage": "base", "why": "", "source": os.path.join(ROOT, CANON, f["canon"])}


def _webp(src, dst):
    """src as a webp of at most 1024 px wide, q90. Homebrew's plain ffmpeg has no WebP encoder, so cwebp writes it."""
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        png = os.path.join(tmp, "in.png")
        subprocess.run(["ffmpeg", "-nostdin", "-loglevel", "error", "-y", "-i", src, "-vf", "scale='min(1024,iw)':-2", png],
                       check=True)
        subprocess.run(["cwebp", "-quiet", "-q", "90", png, "-o", dst], check=True)


def rows_for(fam, st, prepare=True):
    """The manifest rows of one family in the state check() gave. With prepare, copies the kept picture into place."""
    f = FAMILIES[fam]
    rows = []
    if st["stage"] == "base":
        src = st["source"]
        rel = "%s/candidates/src/%s_src.png" % (PICS, fam)
        if prepare:
            os.makedirs(os.path.dirname(os.path.join(ROOT, rel)), exist_ok=True)
            vf = "scale=-1:920:flags=lanczos,pad=1024:1024:(ow-iw)/2:(oh-ih)/2:color=0xd6d6d6"
            if f.get("crop"):
                vf = "crop=%d:ih:%d:0," % (f["crop"][1] - f["crop"][0], f["crop"][0]) + vf
            subprocess.run(["ffmpeg", "-nostdin", "-loglevel", "error", "-y", "-i", src, "-vf", vf, os.path.join(ROOT, rel)],
                           check=True)
        prompt = f["ready"] + ("" if "Three-quarter" in f["ready"] else READY_TAIL)
        for take in ("a", "b"):
            rows.append({"id": "cw_host_ready_%s_%s" % (fam, take), "kind": "edit", "from_file": rel, "augment": False,
                         "v": 1, "family": fam, "stage": "base",
                         "out": "%s/ready_%s_%s" % (OUT, fam, take), "prompt": prompt})
        return rows
    ready = "%s/%s_ready.webp" % (PICS, fam)
    if prepare and st.get("base_file"):
        _webp(st["base_file"], os.path.join(ROOT, ready))
    if not st.get("model_file"):
        rows.append({"id": "cw_host_model_%s_ready" % fam, "kind": "model3d", "from_file": ready, "faces": f["faces"],
                     "texture_size": 1024, "texture_type": "pbr", "v": 1, "family": fam, "pose": "ready",
                     "out": "%s/models/%s_ready" % (OUT, fam)})
    for pose, line in f["poses"].items():
        pid = "cw_host_pic_%s_%s" % (fam, pose)
        rows.append({"id": pid, "kind": "edit", "from_file": ready, "augment": False, "v": 1, "family": fam,
                     "pose": pose, "out": "%s/%s_%s" % (OUT, fam, pose),
                     "prompt": line + (FALLEN_TAIL if pose == "fallen" else POSE_TAIL)})
        rows.append({"id": "cw_host_model_%s_%s" % (fam, pose), "kind": "model3d", "from": pid, "faces": f["faces"],
                     "texture_size": 1024, "texture_type": "pbr", "v": 1, "family": fam, "pose": pose,
                     "out": "%s/models/%s_%s" % (OUT, fam, pose)})
    return rows


def plan(prepare=False):
    """{family: (state, rows)} for every family."""
    out = {}
    for fam in FAMILIES:
        st = check(fam)
        out[fam] = (st, rows_for(fam, st, prepare) if st["ok"] else [])
    return out


def cost(rows):
    return sum(RATE[r["kind"]] for r in rows)


def write_manifest(prepare=True):
    p = plan(prepare)
    rows = [r for _st, rs in p.values() for r in rs]
    man = {"batch": "cw-host", "rid_prefix": "asc-cw-host",
           "note": "CW-10 (#261): the Candlewake host derived from the bases Alex kept (tools/ludo/asc_cw_host.py writes it; "
                   "do not edit by hand). Run it with `asc_cw_host.py run`, which checks the gate again first.",
           "style": {"image": "", "art_style": "Cel-Shaded"}, "assets": rows}
    with open(os.path.join(ROOT, MANIFEST), "w") as fh:
        json.dump(man, fh, indent=1)
    return p, rows


TARGET = {"ready": "%s/%s_ready.webp", "model": "assets/models/units/candlewake/%s_%s.glb",
          "ruler_model": "assets/models/rulers/%s_%s.glb"}
RULERS = ("half_death", "mother_tallow")
TEX = {6000: 512, 8000: 1024, 12000: 1024}  ## slimmed texture size by class (STYLE_BIBLE §8.4)


def build_batches(review_dir):
    """review/cw_host_base (the rest of the host's base pictures, a concept batch: Good opens their poses) and review/cw_host
    (every pose picture and its slimmed model, for Alex's verdicts), from what the manifest's run made. Returns {batch: n}."""
    import glb_slim
    man = json.load(open(os.path.join(ROOT, MANIFEST)))

    def made(r):
        d, b = os.path.split(os.path.join(ROOT, r["out"]))
        hits = [f for f in os.listdir(d) if f.startswith(b + ".") and not f.endswith((".json", ".part"))] if os.path.isdir(d) else []
        return os.path.join(d, hits[0]) if hits else None

    out = {}
    base_items, host_items = {}, []
    for r in man["assets"]:
        src = made(r)
        if not src:
            continue
        fam = r["family"]
        if r.get("stage") == "base":
            rel = "ready/%s" % os.path.basename(src)
            it = base_items.setdefault(fam, {"id": fam + "_ready", "kind": "image", "group": "cw_host_base",
                                             "label": FAMILIES[fam]["name"] + ": the ready picture (the base)",
                                             "text": r["prompt"], "file": rel, "target": TARGET["ready"] % (PICS, fam),
                                             "meta": {"family": fam}})
            if it["file"] != rel:
                it.setdefault("takes", []).append({"file": rel, "prompt": r["prompt"]})
        elif r["kind"] == "model3d":
            rel = "models/%s_%s.glb" % (fam, r["pose"])
            dst = os.path.join(review_dir, "cw_host", rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            glb_slim.slim(src, dst, max_size=TEX[r["faces"]], albedo=True)
            host_items.append({"id": "%s_%s_model" % (fam, r["pose"]), "kind": "model", "group": fam, "file": rel,
                               "label": "%s, %s: the model" % (FAMILIES[fam]["name"], r["pose"]),
                               "text": "Ludo image-to-3D of the %s picture, slimmed to the game's budget" % r["pose"],
                               "target": (TARGET["ruler_model"] if fam in RULERS else TARGET["model"]) % (fam, r["pose"]),
                               "meta": {"family": fam, "pose": r["pose"]}})
        else:
            rel = "pictures/%s" % os.path.basename(src)
            host_items.append({"id": "%s_%s_picture" % (fam, r["pose"]), "kind": "image", "group": fam, "file": rel,
                               "label": "%s, %s: the picture" % (FAMILIES[fam]["name"], r["pose"]), "text": r["prompt"],
                               "target": "%s/%s_%s.webp" % (PICS, fam, r["pose"]), "meta": {"family": fam, "pose": r["pose"]}})
        if r["kind"] != "model3d":
            batch = "cw_host_base" if r.get("stage") == "base" else "cw_host"
            dst = os.path.join(review_dir, batch, rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copy2(src, dst)
    for name, items, mode in (("cw_host_base", list(base_items.values()), "concept"), ("cw_host", host_items, "standard")):
        if not items:
            continue
        title = {"cw_host_base": "Candlewake host, base pictures", "cw_host": "Candlewake host, poses and models"}[name]
        with open(os.path.join(review_dir, name, "batch.json"), "w") as fh:
            json.dump({"batch": name, "mode": mode, "title": title, "items": items}, fh, indent=1)
        out[name] = len(items)
    return out


def main(argv):
    cmd = argv[0] if argv else "status"
    if cmd == "batch":
        print(build_batches(argv[1] if len(argv) > 1 else str(base_gate.review_root())))
        return 0
    if cmd == "status":
        for fam, (st, rows) in plan(prepare=False).items():
            if st["ok"]:
                print("%-22s %s: %d rows, %.1f cr" % (fam, "base pictures" if st["stage"] == "base" else "poses and models",
                                                     len(rows), cost(rows)))
            else:
                print("%-22s refused: %s" % (fam, st["why"]))
        return 0
    if cmd == "manifest":
        p, rows = write_manifest()
        print("%s: %d rows, %.1f cr (%s)" % (MANIFEST, len(rows), cost(rows),
                                            ", ".join(f for f, (st, _r) in p.items() if st["ok"]) or "no family passes"))
        return 0
    if cmd == "cost":
        man = json.load(open(os.path.join(ROOT, MANIFEST)))
        print("%.1f cr in %d rows" % (cost(man["assets"]), len(man["assets"])))
        return 0
    if cmd == "run":
        man = json.load(open(os.path.join(ROOT, MANIFEST)))
        wanted = set(argv[1:])
        for r in man["assets"]:
            if wanted and r["id"] not in wanted:
                continue
            st = check(r["family"])
            if not st["ok"] or st["stage"] != r.get("stage", "poses"):
                sys.exit("refused: %s (re-run `manifest`)" % (st["why"] or "%s's base changed since the manifest"
                                                              % FAMILIES[r["family"]]["name"]))
        return subprocess.call([sys.executable, os.path.join(HERE, "ludo.py"), "--manifest", MANIFEST, "--ledger", LEDGER]
                               + sorted(wanted), cwd=ROOT)
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
