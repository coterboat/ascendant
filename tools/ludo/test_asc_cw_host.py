#!/usr/bin/env python3
"""Tests for the Candlewake host's derive stage (tools/ludo/asc_cw_host.py, CW-10 #261), in stdlib unittest:

    python3 tools/ludo/test_asc_cw_host.py

They never call Ludo or ffmpeg (plans are built with prepare=False) and never touch assets/ or review/: the batches are
throwaway ones in a temporary folder (ASC_REVIEW_DIR), their verdicts written by the Review Table's own `decide`.
"""
import json
import os
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

HERE = os.path.dirname(os.path.abspath(__file__))
sys.dont_write_bytecode = True
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "review"))
import asc_cw_host as H  # noqa: E402
import review as R  # noqa: E402

BASE_FAMILIES = [f for f, d in H.FAMILIES.items() if "base" in d]


class Throwaway(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="cw_host_test_"))
        self.review = self.tmp / "review"
        self.review.mkdir()
        self._old_review = R.REVIEW
        self._old_env = os.environ.get("ASC_REVIEW_DIR")
        R.REVIEW = self.review
        os.environ["ASC_REVIEW_DIR"] = str(self.review)

    def tearDown(self):
        R.REVIEW = self._old_review
        if self._old_env is None:
            os.environ.pop("ASC_REVIEW_DIR", None)
        else:
            os.environ["ASC_REVIEW_DIR"] = self._old_env
        shutil.rmtree(self.tmp, ignore_errors=True)

    def batch(self, name, ids):
        """A concept batch with one item per id, two takes each (as cw_base is built)."""
        d = self.review / name
        items = []
        for iid in ids:
            ext = "glb" if iid.endswith("_model") else "png"
            for seat in ("codex", "grok"):
                p = d / seat / ("%s.%s" % (iid, ext))
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_bytes(("%s %s" % (iid, seat)).encode())
            items.append({"id": iid, "kind": "model" if ext == "glb" else "image", "group": name, "label": iid,
                          "text": "prompt", "file": "codex/%s.%s" % (iid, ext), "seat": "codex",
                          "takes": [{"file": "grok/%s.%s" % (iid, ext), "seat": "grok"}]})
        d.mkdir(parents=True, exist_ok=True)
        (d / "batch.json").write_text(json.dumps({"batch": name, "mode": "concept", "title": name, "items": items}))

    def cw_base(self):
        self.batch(H.BASE_BATCH, [i for f in BASE_FAMILIES for i in (H.FAMILIES[f]["base"], H.FAMILIES[f]["model_item"])])


class NothingBeforeAVerdict(Throwaway):
    def test_no_batch_refuses_every_family(self):
        p = H.plan(prepare=False)
        self.assertTrue(all(not st["ok"] for st, _rows in p.values()))
        self.assertEqual(sum(len(r) for _st, r in p.values()), 0)

    def test_pending_bases_refuse_with_the_name(self):
        self.cw_base()
        p = H.plan(prepare=False)
        for fam in H.FAMILIES:
            st, rows = p[fam]
            self.assertFalse(st["ok"], fam)
            self.assertEqual(rows, [])
        self.assertIn("Wickwardens", p["wickwardens"][0]["why"])
        self.assertIn("waits for the Wickwardens' base", p["gleaners"][0]["why"])

    def test_bad_base_refuses(self):
        self.cw_base()
        R.decide(H.BASE_BATCH, "wickwardens_ready", verdict="reject", note="too white")
        st = H.check("wickwardens")
        self.assertFalse(st["ok"])
        self.assertIn("Bad", st["why"])


class DeriveFromTheKeptTake(Throwaway):
    def test_kept_wickwarden_opens_its_poses_and_the_host_bases(self):
        self.cw_base()
        R.decide(H.BASE_BATCH, "wickwardens_ready", verdict="accept", take="grok/wickwardens_ready.png")
        p = H.plan(prepare=False)
        st, rows = p["wickwardens"]
        self.assertTrue(st["ok"])
        self.assertTrue(st["base_file"].endswith("grok/wickwardens_ready.png"))  # the take he kept, not the first
        poses = H.FAMILIES["wickwardens"]["poses"]
        edits = [r for r in rows if r["kind"] == "edit"]
        models = [r for r in rows if r["kind"] == "model3d"]
        self.assertEqual(sorted(r["pose"] for r in edits), sorted(poses))
        self.assertEqual(len(models), len(poses) + 1)  # the model item has no verdict: the ready pose gets a new model
        self.assertTrue(all(r["from_file"].endswith("wickwardens_ready.webp") for r in edits))
        self.assertTrue(all("unlit" in r["prompt"] for r in edits))  # the code draws the flame
        # the rest of the host may have its base pictures now; the rulers still wait for theirs
        for fam in ("gleaners", "hundred_wick"):
            self.assertEqual(p[fam][0]["stage"], "base", fam)
            self.assertEqual(len(p[fam][1]), 2)
        self.assertFalse(p["half_death"][0]["ok"])
        self.assertFalse(p["chandlers_apprentices"][0]["ok"])  # no concept pick yet
        self.assertIn(H.CONCEPT_BATCH, p["chandlers_apprentices"][0]["why"])

    def test_kept_model_is_not_made_again(self):
        self.cw_base()
        R.decide(H.BASE_BATCH, "half_death_ready", verdict="accept")
        R.decide(H.BASE_BATCH, "half_death_model", verdict="accept", take="grok/half_death_model.glb")
        st, rows = H.plan(prepare=False)["half_death"]
        self.assertTrue(st["model_file"].endswith("grok/half_death_model.glb"))
        self.assertNotIn("ready", [r.get("pose") for r in rows if r["kind"] == "model3d"])
        self.assertEqual(len([r for r in rows if r["kind"] == "edit"]), 4)  # march, strike, fallen, cheer

    def test_revise_without_redo_refuses(self):
        self.cw_base()
        R.decide(H.BASE_BATCH, "mother_tallow_ready", verdict="revise", note="no brass saucer under the taper")
        st = H.check("mother_tallow")
        self.assertFalse(st["ok"])
        self.assertIn("no brass saucer", st["why"])

    def test_costs_follow_the_rates(self):
        self.cw_base()
        R.decide(H.BASE_BATCH, "wickwardens_ready", verdict="accept")
        st, rows = H.plan(prepare=False)["wickwardens"]
        n = len(H.FAMILIES["wickwardens"]["poses"])
        self.assertEqual(H.cost(rows), n * H.RATE["edit"] + (n + 1) * H.RATE["model3d"])

    def test_apprentices_base_from_the_concept_pick(self):
        self.cw_base()
        R.decide(H.BASE_BATCH, "wickwardens_ready", verdict="accept")
        self.batch(H.CONCEPT_BATCH, ["apprentices_a", "apprentices_b", "apprentices_c"])
        R.decide(H.CONCEPT_BATCH, "apprentices_c", verdict="accept")
        st = H.check("chandlers_apprentices")
        self.assertEqual(st["stage"], "base")
        self.assertTrue(st["source"].endswith("codex/apprentices_c.png"))


class Batches(Throwaway):
    def test_base_takes_and_pose_pictures_go_to_their_batches(self):
        root = self.tmp / "repo"
        rows = [{"id": "cw_host_ready_gleaners_%s" % t, "kind": "edit", "family": "gleaners", "stage": "base",
                 "out": "c/ready_gleaners_%s" % t, "prompt": "p"} for t in "ab"]
        rows.append({"id": "cw_host_pic_wickwardens_march", "kind": "edit", "family": "wickwardens", "pose": "march",
                     "out": "c/wickwardens_march", "prompt": "march"})
        rows.append({"id": "cw_host_pic_wickwardens_strike", "kind": "edit", "family": "wickwardens", "pose": "strike",
                     "out": "c/wickwardens_strike", "prompt": "strike"})  # not made yet: left out
        (root / "c").mkdir(parents=True)
        for name in ("ready_gleaners_a.webp", "ready_gleaners_b.webp", "wickwardens_march.webp"):
            (root / "c" / name).write_bytes(b"x")
        (root / "m.json").write_text(json.dumps({"assets": rows}))
        old = (H.ROOT, H.MANIFEST)
        H.ROOT, H.MANIFEST = str(root), "m.json"
        try:
            out = H.build_batches(str(self.review))
        finally:
            H.ROOT, H.MANIFEST = old
        self.assertEqual(out, {"cw_host_base": 1, "cw_host": 1})
        base = json.loads((self.review / "cw_host_base" / "batch.json").read_text())
        self.assertEqual(base["mode"], "concept")
        self.assertEqual(base["items"][0]["id"], "gleaners_ready")  # the gate's item for the family
        self.assertEqual(len(base["items"][0]["takes"]), 1)
        host = json.loads((self.review / "cw_host" / "batch.json").read_text())
        self.assertEqual([i["id"] for i in host["items"]], ["wickwardens_march_picture"])
        self.assertTrue((self.review / "cw_host" / "pictures" / "wickwardens_march.webp").exists())


if __name__ == "__main__":
    unittest.main(verbosity=1)
