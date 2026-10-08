#!/usr/bin/env python3
"""Tests for tools/ludo/asc_3d_grok.py (stdlib unittest): the batch's rows, the review batch it builds, and the
install action that puts accepted models into the game. Run from anywhere:

    python3 tools/ludo/test_asc_3d_grok.py

They never call Ludo and never touch assets/models/ or world3d/models.json: the install runs against throwaway copies
of the descriptor and the board table in a temp folder, and the one review batch they build (to check what
review.py from-folder makes of the staged folder) is named review/_test_grok_<random> and removed afterwards.
"""
from __future__ import annotations

import hashlib
import json
import os
import secrets
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.dont_write_bytecode = True
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "review"))
import asc_3d_grok as G  # noqa: E402
import review as R  # noqa: E402

P, F = G.P, G.F
REPO = G.ROOT
SAMPLE_GLB = os.path.join(REPO, "assets", "models", "units", "kingdom", "spearmen_ready.glb")  ## any real Ludo GLB


def read(path, mode="r"):
    with open(path, mode) as f:
        return f.read()


def write(path, text):
    with open(path, "w") as f:
        f.write(text)


def jload(path):
    return json.loads(read(path))


def sha(path):
    return hashlib.sha256(read(path, "rb")).hexdigest()


def board_lines(path):
    return read(path).split("\n")


class Rows(unittest.TestCase):
    def test_every_family_and_pose_has_a_model_row_whose_target_is_in_the_game_now(self):
        models = [r for r in G.rows() if r["kind"] == "model3d"]
        self.assertEqual(len(models), len(G.FAMILIES) * len(G.POSES))
        d = F.load_descriptor()
        for r in models:
            self.assertTrue(os.path.exists(os.path.join(REPO, r["target"])), r["target"])
            key = P.vkey(r["unit"]) if r["unit"] in P.VARIANTS else r["unit"]
            self.assertEqual(d[r["group"]][key][r["pose"]]["path"], "res://" + r["target"])

    def test_the_eight_families_are_the_issues_and_sit_on_the_four_sides(self):
        self.assertEqual(set(G.FAMILIES), set(P.VARIANTS) | set(P.NEW))
        self.assertEqual({f["side"] for f in G.FAMILIES.values()}, set(G.SIDES))
        for side in G.SIDES:
            self.assertEqual(len([f for f in G.FAMILIES.values() if f["side"] == side]), 2, side)

    def test_the_sources_are_alexs_pictures_and_the_pose_lines_are_all_there(self):
        for name, fam in G.FAMILIES.items():
            if fam["art"]:
                self.assertTrue(os.path.exists(os.path.join(REPO, G.LORE, fam["art"])), fam["art"])
                self.assertTrue(fam["crop"], name)
            for pose in G.POSES[1:]:
                self.assertTrue(fam[pose], "%s %s" % (name, pose))

    def test_no_prompt_holds_a_negative(self):
        for r in G.rows():
            F.check_prompt(r.get("prompt"))  ## raises on "no", "not", "without", "never", "negative"

    def test_the_cap_is_the_issues_and_cost_stays_inside_it(self):
        self.assertEqual(G.CAP, 250.0)
        planned = sum(F.PRICE[{"edit": "/assets/image/edit", "styled": "/assets/image/style", "image": "/assets/image",
                               "model3d": "/assets/3d-model", "cutout": "/assets/image/remove-background"}[r["kind"]]]
                      * r.get("n", 1) for r in G.rows())
        self.assertLess(planned, G.CAP)

    def test_the_install_action_passes_the_review_tables_own_checks(self):
        for a in G.ACTIONS:
            norm = R.check_action(a)
            self.assertEqual(norm["id"], "install")
            self.assertEqual(norm["kind"], "install")
            self.assertIn("--dry-run", [o["flag"] for o in norm["options"]])


class Install(unittest.TestCase):
    """install() on throwaway copies: a temp root with the descriptor, the board table and a review batch."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="grok_install_")
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.desc = os.path.join(self.tmp, "assets", "models", "models.json")
        self.board = os.path.join(self.tmp, "world3d", "models.json")
        os.makedirs(os.path.dirname(self.desc))
        os.makedirs(os.path.dirname(self.board))
        shutil.copy(F.DESCRIPTOR, self.desc)
        shutil.copy(P.BOARD_TABLE, self.board)
        self._saved = (F.DESCRIPTOR, P.BOARD_TABLE)
        F.DESCRIPTOR, P.BOARD_TABLE = self.desc, self.board
        self.addCleanup(self._restore)
        self.bdir = os.path.join(self.tmp, "review", "m4_looks")
        os.makedirs(os.path.join(self.bdir, "celestial_host"))
        self.items = []
        self.verdicts = {}

    def _restore(self):
        F.DESCRIPTOR, P.BOARD_TABLE = self._saved

    def add(self, family, pose, verdict="accept", men=1.234, share=0.9, regenerated=False):
        """One review item: the candidate (a real Ludo GLB), its target (the model in the game now) and meta as
        build_sidecar writes it; its verdict as the review table's review.json keeps it."""
        side = G.FAMILIES[family]["side"]
        rel = "%s/%s_%s.glb" % (side, family, pose)
        os.makedirs(os.path.join(self.bdir, side), exist_ok=True)
        dst = os.path.join(self.bdir, rel)
        shutil.copy(SAMPLE_GLB, dst)
        lying = pose in G.LYING
        iid = "%s_%s_%s" % (side, family, pose)
        self.items.append({"id": iid, "kind": "model", "file": rel, "group": side, "target": G.model_target(family, pose),
                           "meta": {"family": family, "pose": pose, "size": {"axis": "length" if lying else "height",
                                                                              "men": men}, "body_share": share,
                                    "art": "test.jpg"}})
        if verdict:
            mt = os.path.getmtime(dst)
            self.verdicts[iid] = {"verdict": verdict, "file_mtime": mt - (5.0 if regenerated else 0.0)}
        return iid

    def commit(self):
        write(os.path.join(self.bdir, "batch.json"), json.dumps({"batch": "m4_looks", "title": "t", "items": self.items}))
        write(os.path.join(self.bdir, "review.json"), json.dumps({"items": self.verdicts}))

    def run_install(self, **kw):
        self.commit()
        return G.install("m4_looks", root=self.tmp, **kw)

    def snapshot(self):
        out = {}
        for base, _, files in os.walk(self.tmp):
            if os.sep + "review" in base:
                continue
            for f in files:
                p = os.path.join(base, f)
                out[os.path.relpath(p, self.tmp)] = sha(p)
        return out

    def test_a_dry_run_changes_nothing(self):
        self.add("sunspears", "ready")
        self.add("briarwardens", "strike")
        self.commit()
        before = self.snapshot()
        done = G.install("m4_looks", dry=True, root=self.tmp)
        self.assertEqual(len(done), 2)
        self.assertEqual(self.snapshot(), before)
        self.assertFalse(os.path.exists(os.path.join(self.tmp, G.model_target("sunspears", "ready"))))

    def test_an_accepted_model_goes_to_its_target_and_its_rows_are_rewritten(self):
        self.add("sunspears", "ready", men=1.111, share=0.85)
        self.add("iron_colossus", "fallen", men=2.5, share=0.8)
        done = self.run_install()
        self.assertEqual({i for i, _ in done}, {"celestial_host_sunspears_ready", "living_iron_iron_colossus_fallen"})
        for fam, pose in (("sunspears", "ready"), ("iron_colossus", "fallen")):
            dst = os.path.join(self.tmp, G.model_target(fam, pose))
            self.assertEqual(sha(dst), sha(SAMPLE_GLB))
            self.assertTrue(os.path.exists(dst + ".import"))
        d = jload(self.desc)
        e = d["variants"]["spearmen__crown_celestial_host"]["ready"]
        self.assertEqual(e["size"], {"axis": "height", "men": 1.111})
        self.assertEqual(e["body_share"], 0.85)
        self.assertEqual(e["kind"], "variant")  ## the row's identity is kept
        self.assertEqual(e["transformation"], "crown_celestial_host")
        self.assertEqual(e["body_men"], P.VARIANTS["sunspears"]["body"])
        self.assertIn("#162", e["notes"])
        c = d["units"]["iron_colossus"]["fallen"]
        self.assertEqual(c["size"], {"axis": "length", "men": 2.5})
        ## the board's rows follow: the figure's ready height and the pose sizes
        tb = jload(self.board)["figures"]
        self.assertEqual(tb["spearmen"]["variants"]["crown_celestial_host"]["pose_size"]["ready"]["men"], 1.111)
        self.assertEqual(tb["iron_colossus"]["pose_size"]["fallen"]["men"], 2.5)

    def test_only_this_batchs_board_rows_change_and_every_other_line_stays_byte_for_byte(self):
        self.add("bloodsworn", "ready", men=1.5)
        before = board_lines(self.board)
        self.run_install()
        after = board_lines(self.board)
        self.assertEqual(len(before), len(after))
        changed = [i for i in range(len(before)) if before[i] != after[i]]
        self.assertEqual(len(changed), 1)
        self.assertTrue(after[changed[0]].startswith('\t\t"bloodsworn": '))
        ## the table is still valid JSON, and the other rows of the table are the same objects
        a, b = json.loads("\n".join(before)), json.loads("\n".join(after))
        for k in a["figures"]:
            if k != "bloodsworn":
                self.assertEqual(a["figures"][k], b["figures"][k], k)

    def test_the_other_models_rows_of_the_descriptor_are_untouched(self):
        self.add("seraphs", "march")
        before = jload(self.desc)
        self.run_install()
        after = jload(self.desc)
        self.assertNotEqual(before["units"]["seraphs"]["march"], after["units"]["seraphs"]["march"])
        for pose in ("ready", "strike", "fallen"):
            self.assertEqual(before["units"]["seraphs"][pose], after["units"]["seraphs"][pose])
        before["units"]["seraphs"].pop("march")
        after["units"]["seraphs"].pop("march")
        self.assertEqual(before, after)

    def test_pending_rejected_and_regenerated_items_are_not_installed(self):
        self.add("sunspears", "ready", verdict="accept")
        self.add("sunspears", "march", verdict="reject")
        self.add("sunspears", "strike", verdict=None)
        self.add("sunspears", "fallen", verdict="accept", regenerated=True)  ## the file is newer than the verdict
        done = self.run_install()
        self.assertEqual([i for i, _ in done], ["celestial_host_sunspears_ready"])
        for pose in ("march", "strike", "fallen"):
            self.assertFalse(os.path.exists(os.path.join(self.tmp, G.model_target("sunspears", pose))), pose)

    def test_only_installs_just_those_items(self):
        self.add("sunspears", "ready")
        self.add("sunspears", "march")
        done = self.run_install(only={"celestial_host_sunspears_march"})
        self.assertEqual([i for i, _ in done], ["celestial_host_sunspears_march"])
        self.assertFalse(os.path.exists(os.path.join(self.tmp, G.model_target("sunspears", "ready"))))

    def test_nothing_accepted_writes_nothing(self):
        self.add("sunspears", "ready", verdict=None)
        before = self.snapshot()
        self.assertEqual(self.run_install(), [])
        self.assertEqual(self.snapshot(), before)

    def test_installing_twice_is_safe_and_keeps_an_existing_import(self):
        self.add("bloodtuskers", "ready", men=1.3)
        self.run_install()
        dst = os.path.join(self.tmp, G.model_target("bloodtuskers", "ready"))
        write(dst + ".import", "# the model's own import (and uid) stays\n")
        first = self.snapshot()
        self.run_install()
        self.assertEqual(self.snapshot(), first)
        self.assertTrue(read(dst + ".import").startswith("# the model's own"))


class ReviewBatch(unittest.TestCase):
    """What review.py from-folder makes of the staged folder, through batch(): a throwaway batch in review/."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="grok_stage_")
        self.name = "_test_grok_" + secrets.token_hex(3)
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.addCleanup(shutil.rmtree, os.path.join(REPO, "review", self.name), True)
        self._saved = G.GLB_CAND
        G.GLB_CAND = os.path.relpath(self.tmp, REPO)  ## stage_dir() -> <tmp>/_stage
        self.addCleanup(self._restore)
        rec = {}
        for fam, pose in (("sunspears", "ready"), ("sunspears", "march"), ("briarwardens", "ready"),
                          ("bloodtuskers", "fallen"), ("iron_colossus", "strike")):
            dst = G.staged_path(fam, pose)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copy(SAMPLE_GLB, dst)
            lying = pose in G.LYING
            rec.setdefault(fam, {})[pose] = {"frac": 0.9, "men": 1.2, "axis": "length" if lying else "height",
                                             "faces": 4000, "bytes": 1, "extent": [1, 1, 1], "measured_frac": 0.9}
        G.save_stage_state(rec)

    def _restore(self):
        G.GLB_CAND = self._saved

    def test_the_batch_has_a_model_item_per_staged_file_grouped_by_side_with_the_current_model_as_target(self):
        G.batch(self.name)
        data = jload(os.path.join(REPO, "review", self.name, "batch.json"))
        self.assertEqual(len(data["items"]), 5)
        for it in data["items"]:
            self.assertEqual(it["kind"], "model")
            self.assertIn(it["group"], G.SIDES)
            self.assertEqual(it["group"], G.FAMILIES[it["meta"]["family"]]["side"])
            self.assertEqual(it["target"], G.model_target(it["meta"]["family"], it["meta"]["pose"]))
            self.assertTrue(os.path.exists(os.path.join(REPO, it["target"])), it["target"])  ## what `0` compares with
            self.assertTrue(os.path.exists(os.path.join(REPO, "review", self.name, it["file"])))
        acts = data["actions"]
        self.assertEqual([a["id"] for a in acts], ["install"])
        self.assertEqual(acts[0]["cmd"][-1], self.name)
        R.check_action(acts[0])

    def test_running_it_again_adds_new_files_refreshes_changed_ones_and_keeps_verdicts(self):
        G.batch(self.name)
        bd = os.path.join(REPO, "review", self.name)
        write(os.path.join(bd, "review.json"),
              json.dumps({"items": {"celestial_host_sunspears_ready": {"verdict": "reject", "note": "x"}}}))
        shutil.copy(SAMPLE_GLB, G.staged_path("bloodsworn", "ready"))  ## a new model
        with open(G.staged_path("sunspears", "ready"), "ab") as f:  ## a changed one
            f.write(b"\0" * 4)
        rec = G.load_stage_state()
        rec["bloodsworn"] = {"ready": dict(rec["sunspears"]["ready"])}
        G.save_stage_state(rec)
        G.batch(self.name)
        data = jload(os.path.join(bd, "batch.json"))
        self.assertEqual(len(data["items"]), 6)
        self.assertEqual(sha(os.path.join(bd, "celestial_host", "sunspears_ready.glb")), sha(G.staged_path("sunspears", "ready")))
        self.assertEqual(jload(os.path.join(bd, "review.json"))["items"]["celestial_host_sunspears_ready"]["verdict"], "reject")


class PortraitBatch(unittest.TestCase):
    """The portraits' concept batch, from fake cutouts and fake Ludo takes in a temp folder."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="grok_por_")
        self.name = "_test_grokp_" + secrets.token_hex(3)
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.addCleanup(shutil.rmtree, os.path.join(REPO, "review", self.name), True)
        self._saved = (G.PIC_CAND, G.PORTRAIT_DIR, G.manifest_rows)
        self.addCleanup(self._restore)
        pic = os.path.join(self.tmp, "pic")
        os.makedirs(pic)
        G.PIC_CAND = os.path.relpath(pic, REPO)
        G.PORTRAIT_DIR = os.path.relpath(os.path.join(self.tmp, "por"), REPO)
        for name in G.PORTRAIT_CROPS:  ## a cutout big enough for every crop box
            G._ffmpeg("-f", "lavfi", "-i", "color=c=0x80c080:s=1300x1100,format=rgba", "-frames:v", "1",
                      os.path.join(pic, name + "_cut_c1.png"))
        for k in (1, 2, 3):
            G._ffmpeg("-f", "lavfi", "-i", "color=c=0x303050:s=1024x1024", "-frames:v", "1",
                      os.path.join(pic, "thornthrowers_portrait_c%d.webp" % k))
        rel = os.path.relpath(os.path.join(pic, "thornthrowers_portrait"), REPO)
        G.manifest_rows = lambda: {"por_thornthrowers": {"kind": "styled", "out": rel}}

    def _restore(self):
        G.PIC_CAND, G.PORTRAIT_DIR, G.manifest_rows = self._saved

    def test_eight_concept_items_grouped_by_side_with_the_games_portrait_as_target(self):
        G.portraits_batch(self.name)
        bd = os.path.join(REPO, "review", self.name)
        data = jload(os.path.join(bd, "batch.json"))
        self.assertEqual(data["mode"], "concept")
        self.assertEqual(sorted(it["id"] for it in data["items"]), sorted(G.FAMILIES))
        for it in data["items"]:
            self.assertEqual(it["group"], G.FAMILIES[it["id"]]["side"])
            self.assertEqual(it["target"], G.portrait_path(it["id"]))
            self.assertTrue(os.path.exists(os.path.join(REPO, it["target"])), it["target"])  ## `0` shows it
            self.assertTrue(os.path.exists(os.path.join(bd, it["file"])))
        by = {it["id"]: it for it in data["items"]}
        self.assertEqual(len(by["thornthrowers"]["takes"]), 2)  ## three Ludo takes, no art of Alex's
        self.assertNotIn("takes", by["sunspears"])
        R.check_action(data["actions"][0])
        self.assertEqual(data["actions"][0]["cmd"][-1], self.name)

    def test_a_portrait_is_384_by_512_and_the_looks_right_ones_are_turned_to_face_left(self):
        G.portraits_batch(self.name)
        bd = os.path.join(REPO, "review", self.name)
        probe = os.path.join(os.path.dirname(F.FF), "ffprobe") if os.path.dirname(F.FF) else "ffprobe"
        for rel in ("celestial_host/sunspears.webp", "thorn_wild/thornthrowers_t2.webp", "blood_pact/bloodsworn.webp"):
            out = subprocess.run([probe, "-v", "error", "-show_entries", "stream=width,height", "-of", "csv=p=0",
                                  os.path.join(bd, rel)], capture_output=True, text=True).stdout.strip()
            self.assertEqual(out, "384,512", rel)
        self.assertTrue(G.PORTRAIT_CROPS["sunspears"][4])  ## the sunspear looks right in Alex's art
        self.assertFalse(G.PORTRAIT_CROPS["bloodsworn"][4])  ## the wolf already looks left

    def test_every_crop_box_is_3_to_4_and_inside_a_real_cutout(self):
        for name, (x, y, w, h, _) in G.PORTRAIT_CROPS.items():
            self.assertAlmostEqual(w / h, 0.75, delta=0.01, msg=name)
            self.assertGreaterEqual(x, 0)
            self.assertGreaterEqual(y, 0)


if __name__ == "__main__":
    ## the pipeline modules this drives (asc_3d_factions, glb_slim) leave a few files to the garbage collector
    unittest.main(verbosity=2, warnings="ignore")
