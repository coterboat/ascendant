#!/usr/bin/env python3
"""Tests for the base-first gate (tools/ludo/base_gate.py, issue #179) and for how the two batch scripts use it
(asc_3d_grok.py, asc_3d_free_holds.py), in stdlib unittest. Run from anywhere:

    python3 tools/ludo/test_base_gate.py

They never call Ludo (any call is a test failure) and never touch assets/ or review/: every base batch is a throwaway one
in a temporary folder (ASC_REVIEW_DIR), its verdicts written by the Review Table's own `decide` (tools/review/review.py,
pointed at that folder), so what the gate reads is what the table really writes. The scripts' own pick folders are
redirected into the temporary folder too.
"""
from __future__ import annotations

import json
import os
import shutil
import sys
import tempfile
import time
import unittest
from pathlib import Path

HERE = os.path.dirname(os.path.abspath(__file__))
sys.dont_write_bytecode = True
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "review"))
import asc_3d_free_holds as FH  # noqa: E402
import asc_3d_grok as G  # noqa: E402
import base_gate as B  # noqa: E402
import review as R  # noqa: E402

F = G.F


def write(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data if isinstance(data, bytes) else data.encode())
    return path


class Throwaway(unittest.TestCase):
    """A temporary folder of review batches: the Review Table and the gate both read it."""

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="base_gate_test_"))
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

    def candidates(self, family, takes=3, tag="a"):
        """`takes` candidate pictures named as the pipeline names them (<row>_c<k>.webp); written once per (family, tag),
        so building a batch again from the same candidates sees files that did not change."""
        out = []
        for k in range(1, takes + 1):
            p = self.tmp / "cands" / tag / ("%s_ready_base_c%d.webp" % (family, k))
            if not p.exists():
                write(p, ("%s take %d %s" % (family, k, tag)).encode())
            out.append(str(p))
        return out

    def batch(self, name, families, takes=3, tag="a"):
        """A base batch (concept mode) with one `<family>_ready` item per family, the way the scripts build it."""
        items = [{"id": "%s_ready" % f, "label": f, "group": f, "text": "prompt", "target": "assets/x/%s_ready.webp" % f,
                  "sources": self.candidates(f, takes, tag), "meta": {"row": "base_%s_ready" % f}} for f in families]
        return B.write_base_batch(name, "throwaway base batch", items, [], root=self.review)


class GateStates(Throwaway):
    def gate(self, **kw):
        return B.Gate("t_base", display=lambda f: f.replace("_", " ").title(), **kw)

    def test_no_batch_refuses_and_names_the_family(self):
        r = self.gate().check("sunspears")
        self.assertFalse(r["ok"])
        self.assertEqual(r["state"], "no_batch")
        with self.assertRaises(B.BaseNotAccepted) as cm:
            self.gate().require("sunspears")
        self.assertIn("Sunspears", str(cm.exception))
        self.assertIn("Alex", str(cm.exception))

    def test_a_batch_without_the_item_refuses(self):
        self.batch("t_base", ["hill_slingers"])
        r = self.gate().check("sunspears")
        self.assertEqual(r["state"], "no_item")
        self.assertFalse(r["ok"])

    def test_a_base_with_no_verdict_is_refused_as_waiting_for_alex(self):
        self.batch("t_base", ["sunspears"])
        r = self.gate().check("sunspears")
        self.assertEqual(r["state"], "pending")
        self.assertFalse(r["ok"])
        self.assertIn("waiting for Alex's verdict", r["message"])
        self.assertIn("Sunspears", r["message"])

    def test_good_allows_it_and_hands_back_the_take_he_kept(self):
        self.batch("t_base", ["sunspears"])
        take2 = self.review / "t_base" / "sunspears" / "sunspears_ready_c2.webp"
        self.assertTrue(take2.exists())
        R.decide("t_base", "sunspears_ready", verdict="accept", take="sunspears/sunspears_ready_c2.webp")
        r = self.gate().require("sunspears")
        self.assertTrue(r["ok"])
        self.assertEqual(r["state"], "accepted")
        self.assertEqual(Path(r["file"]).resolve(), take2.resolve(), "the gate names the take he kept, not take 1")

    def test_good_on_the_first_take_hands_back_the_items_own_file(self):
        self.batch("t_base", ["sunspears"])
        R.decide("t_base", "sunspears_ready", verdict="accept")
        r = self.gate().require("sunspears")
        self.assertEqual(Path(r["file"]).name, "sunspears_ready_c1.webp")

    def test_bad_refuses_with_his_note(self):
        self.batch("t_base", ["sunspears"])
        R.decide("t_base", "sunspears_ready", verdict="reject", note="the halo is still there")
        r = self.gate().check("sunspears")
        self.assertEqual(r["state"], "rejected")
        self.assertFalse(r["ok"])
        self.assertIn("the halo is still there", r["message"])
        self.assertIn("Bad", r["message"])

    def test_good_with_changes_is_refused_until_the_base_was_redone_and_looked_at_again(self):
        self.batch("t_base", ["hill_slingers"])
        R.decide("t_base", "hill_slingers_ready", verdict="revise", note="a real sling, not a long rope")
        r = self.gate().check("hill_slingers")
        self.assertEqual(r["state"], "revise")
        self.assertFalse(r["ok"], "Good with changes on a picture that was not redone is not a nailed-down base")
        self.assertIn("a real sling, not a long rope", r["message"])
        self.assertIn("not been redone", r["message"])
        ## the redo: new pictures, newer than his verdict: back in the queue, still refused
        time.sleep(0.02)
        self.batch("t_base", ["hill_slingers"], tag="redone")
        for p in (self.review / "t_base" / "hill_slingers").glob("*.webp"):
            os.utime(p, (time.time() + 5, time.time() + 5))
        r = self.gate().check("hill_slingers")
        self.assertEqual(r["state"], "pending")
        self.assertFalse(r["ok"])
        self.assertIn("redone after his verdict", r["message"])
        ## he looks again: Good with changes once more, now after a redo: allowed
        R.decide("t_base", "hill_slingers_ready", verdict="revise", note="the pouch a little smaller")
        r = self.gate().require("hill_slingers")
        self.assertTrue(r["ok"])
        self.assertEqual(r["state"], "accepted_after_redo")

    def test_a_base_regenerated_after_it_was_accepted_is_refused_until_he_looks_again(self):
        self.batch("t_base", ["sunspears"])
        R.decide("t_base", "sunspears_ready", verdict="accept")
        self.assertTrue(self.gate().check("sunspears")["ok"])
        for p in (self.review / "t_base" / "sunspears").glob("*.webp"):
            os.utime(p, (time.time() + 5, time.time() + 5))
        r = self.gate().check("sunspears")
        self.assertFalse(r["ok"])
        self.assertEqual(r["state"], "pending")
        self.assertTrue(r["regenerated"])
        R.decide("t_base", "sunspears_ready", verdict="accept")
        self.assertTrue(self.gate().check("sunspears")["ok"])

    def test_undo_puts_it_back_to_waiting(self):
        self.batch("t_base", ["sunspears"])
        R.decide("t_base", "sunspears_ready", verdict="accept")
        R.decide("t_base", "sunspears_ready", verdict="pending")
        self.assertFalse(self.gate().check("sunspears")["ok"])

    def test_a_missing_file_is_refused(self):
        self.batch("t_base", ["sunspears"])
        R.decide("t_base", "sunspears_ready", verdict="accept")
        for p in (self.review / "t_base" / "sunspears").glob("*.webp"):
            p.unlink()
        r = self.gate().check("sunspears")
        self.assertFalse(r["ok"])
        self.assertEqual(r["state"], "missing")

    def test_require_all_names_every_family_that_fails(self):
        self.batch("t_base", ["sunspears", "hill_slingers"])
        R.decide("t_base", "sunspears_ready", verdict="accept")
        with self.assertRaises(B.BaseNotAccepted) as cm:
            self.gate().require_all(["sunspears", "hill_slingers", "wildkin"])
        msg = str(cm.exception)
        self.assertIn("Hill Slingers", msg)
        self.assertIn("Wildkin", msg)
        self.assertNotIn("Sunspears:", msg, "a family that passes is not named as refused")
        self.assertEqual(self.gate().require_all(["sunspears"])["sunspears"]["state"], "accepted")


class Grandfathered(Throwaway):
    REC = {"bloodsworn": {"batch": "t_looks", "item": "blood_pact_bloodsworn_ready", "at": "2026-10-08T18:47:55"}}

    def gate(self):
        return B.Gate("t_base", grandfathered=self.REC)

    def test_a_recorded_acceptance_stands_with_no_batch_at_all(self):
        r = self.gate().require("bloodsworn")
        self.assertEqual(r["state"], "grandfathered")
        self.assertIsNone(r["file"], "nothing to adopt: the pick the model was made from stays")

    def test_it_stands_while_the_batch_that_gave_it_still_says_accept(self):
        d = self.review / "t_looks"
        write(d / "review.json", json.dumps({"items": {"blood_pact_bloodsworn_ready": {"verdict": "accept"}}}))
        self.assertTrue(self.gate().check("bloodsworn")["ok"])

    def test_it_is_withdrawn_when_that_batch_now_says_otherwise(self):
        d = self.review / "t_looks"
        write(d / "review.json", json.dumps({"items": {"blood_pact_bloodsworn_ready": {"verdict": "reject", "note": "no"}}}))
        r = self.gate().check("bloodsworn")
        self.assertFalse(r["ok"])
        self.assertEqual(r["state"], "withdrawn")
        self.assertIn("Bloodsworn", r["message"])

    def test_a_family_that_is_not_recorded_still_needs_its_base(self):
        self.assertFalse(self.gate().check("sunspears")["ok"])


class BaseBatchWriter(Throwaway):
    def test_it_builds_a_concept_batch_the_review_table_loads_with_the_takes(self):
        n = self.batch("t_base", ["sunspears", "hill_slingers"])
        self.assertEqual(n, 2)
        d, data = R.load_batch("t_base")
        self.assertEqual(data["mode"], "concept")
        it = next(i for i in data["items"] if i["id"] == "sunspears_ready")
        self.assertEqual(it["file"], "sunspears/sunspears_ready_c1.webp")
        self.assertEqual([t["file"] for t in it["takes"]],
                         ["sunspears/sunspears_ready_c2.webp", "sunspears/sunspears_ready_c3.webp"])
        takes = R.item_takes(d, it)
        self.assertEqual(len(takes), 3)
        self.assertTrue(all(t["path"] is not None for t in takes))
        self.assertEqual(it["target"], "assets/x/sunspears_ready.webp")

    def test_building_again_keeps_the_verdicts_and_does_not_requeue_an_unchanged_item(self):
        self.batch("t_base", ["sunspears"])
        R.decide("t_base", "sunspears_ready", verdict="accept")
        self.batch("t_base", ["sunspears"])  # the same candidates, built again
        m = R.merged_batch("t_base")
        self.assertEqual(m["items"][0]["status"], "accept")
        self.assertFalse(m["items"][0]["regenerated"])


# ---------------------------------------------------------------------------------------------- the scripts
class NoLudo:
    """Any call to Ludo during a test is a failure."""

    def __enter__(self):
        self.calls = []
        self._old = F.ludo.call

        def boom(*a, **k):
            self.calls.append(a)
            raise AssertionError("a Ludo call was made: %r" % (a[:2],))
        F.ludo.call = boom
        return self

    def __exit__(self, *exc):
        F.ludo.call = self._old


class ScriptsRefuse(Throwaway):
    """The gate as the two scripts use it. Their pick folders are redirected into the temporary folder."""

    def setUp(self):
        super().setUp()
        self.old_roots = (G.ROOT, FH.ROOT)
        ## the scripts' ROOT is where picks are read and adopted: a copy of just the folders they touch
        self.root = self.tmp / "repo"
        self.root.mkdir()
        G.ROOT = FH.ROOT = str(self.root)

    def tearDown(self):
        G.ROOT, FH.ROOT = self.old_roots
        super().tearDown()

    # -- grok
    def test_grok_refuses_to_derive_sunspears_poses_and_models_from_an_unaccepted_base(self):
        with NoLudo() as ludo:
            for stage in ("poses", "models"):
                with self.assertRaises(SystemExit) as cm:
                    G.run(stage, ["sunspears"], 1, 1.0)
                self.assertIn("Sunspears", str(cm.exception))
                self.assertIn("base", str(cm.exception))
            self.assertEqual(ludo.calls, [])

    def test_grok_refuses_the_whole_stage_when_any_family_it_would_touch_is_unaccepted(self):
        with NoLudo() as ludo:
            with self.assertRaises(SystemExit) as cm:
                G.run("poses", [], 1, 1.0)  # every family: the Sunspears' base is not accepted
            self.assertIn("Sunspears", str(cm.exception))
            self.assertEqual(ludo.calls, [])

    def test_grok_checks_every_derived_row_too(self):
        row = {"id": "pic_sunspears_march", "stage": "poses", "unit": "sunspears"}
        with self.assertRaises(B.BaseNotAccepted) as cm:
            G.gate_row(row)
        self.assertIn("Sunspears", str(cm.exception))
        ## a grandfathered family goes through
        G.gate_row({"id": "pic_bloodsworn_march", "stage": "poses", "unit": "bloodsworn"})

    def test_the_driver_calls_the_gate_before_it_reads_or_submits_a_row(self):
        old = F.GATE_ROW
        F.GATE_ROW = G.gate_row
        try:
            with NoLudo() as ludo:
                for stage in ("poses", "models"):
                    with self.assertRaises(B.BaseNotAccepted):
                        F.run_row({"id": "x_sunspears_march", "stage": stage, "unit": "sunspears", "kind": "edit",
                                   "from_file": "does/not/exist.webp", "prompt": "p", "n": 1}, {"v": {}}, time.time() + 60)
                self.assertEqual(ludo.calls, [], "refused before any call (and before the input picture was read)")
        finally:
            F.GATE_ROW = old

    def test_grok_allows_it_from_an_accepted_base_and_derives_from_the_take_he_kept(self):
        self.batch(G.BASE_BATCH, ["sunspears"])
        R.decide(G.BASE_BATCH, "sunspears_ready", verdict="accept", take="sunspears/sunspears_ready_c3.webp")
        kept = self.review / G.BASE_BATCH / "sunspears" / "sunspears_ready_c3.webp"
        old_pick = write(self.root / G.pick_of("sunspears", "ready"), b"the old picture with the halo")
        G.gate_row({"id": "pic_sunspears_march", "stage": "poses", "unit": "sunspears"})
        self.assertEqual(old_pick.read_bytes(), kept.read_bytes(), "the poses read the picture he accepted")

    def test_grok_base_stage_is_not_gated_and_a_base_row_cannot_be_picked(self):
        base = [r for r in G.rows() if r["stage"] == "base"]
        self.assertEqual([r["unit"] for r in base], ["sunspears"])
        G.gate_row({"id": base[0]["id"], "stage": "base", "unit": "sunspears"})  # no raise: the gate's own input
        with self.assertRaises(SystemExit) as cm:
            G.pick("base_sunspears_ready", 1)
        self.assertIn("Review Table", str(cm.exception))

    def test_grok_status_lists_the_seven_grandfathered_families_and_the_two_waiting(self):
        states = {f: G.GATE.check(f)["state"] for f in G.FAMILIES}
        self.assertEqual({f for f, s in states.items() if s == "grandfathered"}, set(G.GRANDFATHERED))
        self.assertEqual({f for f, s in states.items() if s != "grandfathered"}, {"sunspears"})

    # -- the free holds
    def test_free_holds_refuses_hill_slingers_from_an_unaccepted_base(self):
        with NoLudo() as ludo:
            for stage in ("poses", "models"):
                with self.assertRaises(SystemExit) as cm:
                    FH.run(stage, ["hill_slingers"], 1, 1.0)
                self.assertIn("Hill Slingers", str(cm.exception))
            self.assertEqual(ludo.calls, [])

    def test_free_holds_regen_goes_through_the_same_gate_row_by_row(self):
        with self.assertRaises(B.BaseNotAccepted):
            FH.gate_row({"id": "model_hill_slingers_strike", "stage": "models", "unit": "hill_slingers"})
        FH.gate_row({"id": "model_wildkin_strike", "stage": "models", "unit": "wildkin"})  # grandfathered

    def test_free_holds_allows_it_from_an_accepted_base_and_adopts_the_take(self):
        self.batch(FH.BASE_BATCH, ["hill_slingers"])
        R.decide(FH.BASE_BATCH, "hill_slingers_ready", verdict="accept", take="hill_slingers/hill_slingers_ready_c2.webp")
        kept = self.review / FH.BASE_BATCH / "hill_slingers" / "hill_slingers_ready_c2.webp"
        write(self.root / FH.pick_path("hill_slingers_ready"), b"the old picture with the long rope")
        FH.gate_row({"id": "pic_hill_slingers_strike", "stage": "poses", "unit": "hill_slingers"})
        self.assertEqual((self.root / FH.pick_path("hill_slingers_ready")).read_bytes(), kept.read_bytes())

    def test_free_holds_base_row_cannot_be_picked_and_is_not_in_the_concept_batch(self):
        base = [r for r in FH.rows() if r["stage"] == "base"]
        self.assertEqual([r["unit"] for r in base], ["hill_slingers"])
        self.assertTrue(all(r["stage"] != "base" for r in FH.rows() if r["id"].startswith("pic_")))
        with self.assertRaises(SystemExit):
            FH.main(["pick", base[0]["id"], "1"])


class EveryDeriveStageIsGated(unittest.TestCase):
    """A stage that is not on the base side must be one the gate covers: a new stage added later is noticed here."""
    BASE_SIDE = {"cuts", "styled", "fixes", "base", "portraits", "bases1", "bases2", "portraits1", "portraits2"}

    def test_grok(self):
        stages = {r["stage"] for r in G.rows()}
        self.assertEqual(set(G.DERIVE_STAGES), {"poses", "models"})
        self.assertEqual(stages - set(G.DERIVE_STAGES), stages & self.BASE_SIDE)

    def test_free_holds(self):
        stages = {r["stage"] for r in FH.rows()}
        self.assertEqual(set(FH.DERIVE_STAGES), {"poses", "models"})
        self.assertEqual(stages - set(FH.DERIVE_STAGES), stages & self.BASE_SIDE)

    def test_every_family_has_a_base_that_the_gate_can_judge(self):
        for f in G.FAMILIES:
            self.assertTrue(f in G.GRANDFATHERED or f in G.BASE_REDO, f)
        for u in FH.UNITS:
            self.assertTrue(u in FH.GRANDFATHERED or u in FH.BASE_REDO, u)

    def test_the_grandfathered_families_are_the_ones_whose_ready_model_alex_accepted(self):
        ## the verdicts themselves are in the review folder of whoever ran the review, so this reads them when they are there
        rv = Path(B.ROOT) / "review"
        for table in (G.GRANDFATHERED, FH.GRANDFATHERED):
            for fam, rec in table.items():
                p = rv / rec["batch"] / "review.json"
                if p.exists():
                    e = json.loads(p.read_text())["items"].get(rec["item"], {})
                    self.assertEqual(e.get("verdict"), "accept", "%s: %s in %s" % (fam, rec["item"], rec["batch"]))


class TheRedoCarriesAlexsNotes(unittest.TestCase):
    def prompt(self, fam, pose):
        return next(r["prompt"] for r in G.rows() if r["id"] == "pic_%s_%s" % (fam, pose))

    def test_no_prompt_holds_a_negative(self):
        for r in G.rows() + FH.rows():
            F.check_prompt(r.get("prompt"))

    def test_sunspears_base_gets_rid_of_the_halo_and_the_spikes_and_holds_the_spear_by_its_low_end(self):
        p = G.BASE_REDO["sunspears"]
        for word in ("get rid of the halo", "random spikes", "low end"):
            self.assertIn(word, p)
        for pose in ("march", "strike", "fallen"):
            self.assertNotIn("halo", G.FAMILIES["sunspears"][pose], pose)
        self.assertIn("low end", G.FAMILIES["sunspears"]["strike"])

    def test_bloodsworn_blades_grow_from_the_forearms_in_every_derived_pose(self):
        for pose in ("march", "strike", "fallen"):
            line = G.FAMILIES["bloodsworn"][pose]
            self.assertIn("grow", line, pose)
            self.assertIn("forearm", line, pose)
            self.assertNotIn("held low", line)
            self.assertNotIn("lying on the floor", line, "a blade is never dropped: it is part of his arm")
            self.assertIn("forearms", self.prompt("bloodsworn", pose))

    def test_briarwardens_march_holds_the_club(self):
        self.assertIn("gripping the handle of the spiked tree-trunk club", self.prompt("briarwardens", "march"))

    def test_thornthrowers_fallen_scatters_the_spears_and_the_hands_are_empty(self):
        line = self.prompt("thornthrowers", "fallen")
        self.assertIn("scattered", line)
        self.assertIn("empty", line)

    def test_the_redone_poses_are_the_issues_five_and_the_sunspears_four_and_their_models_target_what_the_game_has_now(self):
        self.assertEqual(set(G.REDO), {("bloodsworn", "march"), ("bloodsworn", "strike"), ("bloodsworn", "fallen"),
                                       ("briarwardens", "march"), ("thornthrowers", "fallen"),
                                       ("sunspears", "ready"), ("sunspears", "march"), ("sunspears", "strike"),
                                       ("sunspears", "fallen")})
        for (fam, pose), note in G.REDO.items():
            self.assertTrue(note)
            row = next(r for r in G.rows() if r["id"] == "model_%s_%s" % (fam, pose))
            self.assertTrue(os.path.exists(os.path.join(G.ROOT, row["target"])), row["target"])
            if pose == "ready":  ## its picture is the base: no picture row of its own
                self.assertFalse(any(r["id"] == "pic_%s_%s" % (fam, pose) for r in G.rows()))
                continue
            pic = next(r for r in G.rows() if r["id"] == "pic_%s_%s" % (fam, pose))
            self.assertEqual(pic["n"], G.REDO_TAKES)

    def test_the_bloodsworn_strike_names_the_blades_of_both_forearms(self):
        """Alex 10-9 (m4_redo): "close, but it removed the arm blade on the other arm". March and fallen have both."""
        line = G.FAMILIES["bloodsworn"]["strike"]
        self.assertIn("right forearm", line)
        self.assertIn("left forearm", line)
        self.assertIn("both forearms", line)
        self.assertIn("blades growing along his left forearm", line)
        self.assertNotIn("his left claws thrust forward, mouth", line, "v2's wording, which lost the left blades")

    def test_a_redone_ready_model_gets_a_new_request_id_without_a_picture_row(self):
        """`redo sunspears:ready` bumps only the model row (the ready picture is the base), so the old job is not handed back."""
        tmp = tempfile.mkdtemp()
        old = (G.MANIFEST, F.MANIFEST, G.LEDGER, G.ROOT, F.ROOT)
        try:
            G.MANIFEST = F.MANIFEST = os.path.join(tmp, "m.json")
            G.LEDGER = os.path.join(tmp, "l.jsonl")
            ## the candidates it moves to old/ are the throwaway folder's, never the repo's: `redo` finds them through
            ## F.cand_files (F.ROOT) and moves them under G.ROOT, so both are redirected (an earlier version of this
            ## test redirected only G.ROOT and carried a real candidate GLB away)
            G.ROOT = F.ROOT = tmp
            real = os.path.join(old[3], "assets", "models", "candidates", "grok", "sunspears_ready.glb")
            write(os.path.join(tmp, "assets", "models", "candidates", "grok", "sunspears_ready.glb"), b"glb")
            with open(G.LEDGER, "w") as f:
                f.write(json.dumps({"row": "model_sunspears_ready", "request_id": "ascgrok-model_sunspears_ready-v1",
                                    "credits_charged": 4}) + "\n")
            G.write_manifest({"balance_before": G.SENTINEL, "v": {}, "picks": {"model_sunspears_ready": 1}})
            G.redo([("sunspears", "ready")])
            st = G.load_state()
            self.assertEqual(st["v"]["model_sunspears_ready"], 2)
            self.assertNotIn("pic_sunspears_ready", st["v"])
            self.assertNotIn("model_sunspears_ready", st["picks"])
            self.assertFalse(os.path.exists(os.path.join(tmp, "assets", "models", "candidates", "grok",
                                                         "sunspears_ready.glb")), "the old candidate went to old/")
            self.assertTrue(os.path.exists(os.path.join(tmp, "assets", "models", "candidates", "grok", "old",
                                                        "v1_sunspears_ready.glb")))
            if os.path.exists(real):  ## the repo's own candidate is never touched
                self.assertNotEqual(Path(real).read_bytes(), b"glb")
        finally:
            G.MANIFEST, F.MANIFEST, G.LEDGER, G.ROOT, F.ROOT = old
            shutil.rmtree(tmp, ignore_errors=True)

    def test_hill_slingers_base_is_a_real_sling_and_the_strike_twirls_it_overhead(self):
        p = FH.BASE_REDO["hill_slingers"]
        for word in ("short leather cord", "pouch", "doubled"):
            self.assertIn(word, p)
        for word in ("rope", "spool", "long cord"):
            self.assertNotIn(word, p)
        u = FH.UNITS["hill_slingers"]
        self.assertIn("doubled", u["base"])
        strike = u["strike"]
        for word in ("elbow", "fingers pointing toward the sky", "twirling the sling", "above his head"):
            self.assertIn(word, strike)
        self.assertNotIn("rifle", strike)
        self.assertNotIn("long leather sling", u["outfit"])

    def test_hill_slingers_base_redo_keeps_the_kept_take_and_loses_the_outline(self):
        """Alex 10-9 on take 3: "This added a cel-shaded outline effect the other models don't have". v1 said "Same outline
        style"; v2 is an edit of the take he kept, repainted in the soft matte look of the other Free Holds pictures."""
        p = FH.BASE_REDO["hill_slingers"]
        self.assertNotIn("outline", p, "the words that drew the outline are gone, and none names it")
        for word in ("soft matte", "clay miniature", "soft shading", "same sling and pouch", "doubled"):
            self.assertIn(word, p)
        row = next(r for r in FH.rows() if r["id"] == "base_hill_slingers_ready")
        self.assertEqual(row["from_file"], FH.BASE_FROM["hill_slingers"], "an edit of the kept take, not the old ready picture")
        self.assertNotEqual(row["from_file"], row["pick_to"])
        self.assertTrue(row["from_file"].startswith("assets/_concept/candidates/"), "gitignored: never committed")

    def test_the_base_redo_input_is_the_take_he_kept_when_he_marked_it_good_with_changes(self):
        tmp = tempfile.mkdtemp()
        old = FH.ROOT
        try:
            FH.ROOT = tmp
            write(os.path.join(tmp, "review", FH.BASE_BATCH, "hill_slingers", "hill_slingers_ready_c3.webp"), b"take three")
            write(os.path.join(tmp, FH.pick_path("hill_slingers_ready")), b"the old ready picture")
            entry = {"id": "hill_slingers_ready", "verdict": "revise", "file": "hill_slingers/hill_slingers_ready_c3.webp"}
            dst = FH.prepare_base_input("hill_slingers", entry)
            self.assertEqual(Path(dst).read_bytes(), b"take three")
            ## Bad: no kept take, so the edit starts from the current ready picture
            dst = FH.prepare_base_input("hill_slingers", dict(entry, verdict="reject"))
            self.assertEqual(Path(dst).read_bytes(), b"the old ready picture")
            ## a unit with no BASE_FROM is left alone
            self.assertIsNone(FH.prepare_base_input("wildkin", entry))
        finally:
            FH.ROOT = old
            shutil.rmtree(tmp, ignore_errors=True)

    def test_the_pose_prompts_keep_to_the_c_pose_frame(self):
        for fam, pose in G.REDO:
            if pose != "ready":  ## the ready picture is the base, not a pose edit
                self.assertIn("The same figure, now ", self.prompt(fam, pose))


class BaseBatchActions(unittest.TestCase):
    def test_the_base_batchs_actions_pass_the_review_tables_own_checks(self):
        for acts, script in ((G.BASE_ACTIONS, "asc_3d_grok.py"), (FH.BASE_ACTIONS, "asc_3d_free_holds.py")):
            kinds = {}
            for a in acts:
                norm = R.check_action(a)
                kinds[norm["kind"]] = a
            self.assertEqual(set(kinds), {"install", "regen"})
            self.assertTrue(kinds["regen"]["spends"], "Redo rejected spends credits: the table asks first")
            self.assertEqual(kinds["regen"]["cmd"][1], "tools/ludo/%s" % script)
            self.assertEqual(kinds["regen"]["cmd"][2], "regen-base")
            self.assertEqual(kinds["install"]["cmd"][:3], ["python3", "tools/review/review.py", "apply"])

    def test_the_two_base_batches_are_named_as_the_issue_says(self):
        self.assertEqual(G.BASE_BATCH, "m4_redo_base")
        self.assertEqual(FH.BASE_BATCH, "ind_redo_base")
        self.assertEqual(G.REDO_BATCH, "m4_redo")


class RoundBudget(unittest.TestCase):
    def test_the_two_scripts_share_the_issues_120_credits(self):
        self.assertEqual(FH.JOB_CAP, 120.0)
        self.assertEqual(G.CAP + FH.CAP, 120.0)
        self.assertEqual(G.ROUND, FH.ROUND)

    def test_the_driver_counts_the_rounds_own_ledger_lines_not_the_shared_account(self):
        self.assertEqual(F.ROUND, FH.ROUND, "the driver stamps the last script's round on its ledger lines")
        for mod in (G, FH):
            self.assertIs(mod.F, F)
        self.assertEqual(FH.own_balance(), FH.SENTINEL - FH.ledger_spent(FH.ROUND))
        self.assertEqual(G.own_balance(), G.SENTINEL - G.ledger_spent(G.ROUND))

    def test_a_ledger_line_carries_the_round_and_only_its_lines_count(self):
        tmp = tempfile.mkdtemp(prefix="base_gate_ledger_")
        old = (F.LEDGER, F.ROUND, G.LEDGER, FH.LEDGER)
        try:
            F.LEDGER = G.LEDGER = FH.LEDGER = os.path.join(tmp, "l.jsonl")
            F.ROUND = "redo-test"
            F.ledger_line({"row": "a", "credits_charged": 4})
            F.ROUND = None
            F.ledger_line({"row": "b", "credits_charged": 3})
            with open(F.LEDGER) as f:
                lines = [json.loads(x) for x in f]
            self.assertEqual(lines[0]["round"], "redo-test")
            self.assertNotIn("round", lines[1])
            for mod in (G, FH):
                self.assertEqual(mod.ledger_spent("redo-test"), 4.0)
                self.assertEqual(mod.ledger_spent(), 7.0)
                self.assertEqual(mod.ledger_spent("another"), 0.0)
        finally:
            F.LEDGER, F.ROUND, G.LEDGER, FH.LEDGER = old
            F.ROUND = FH.ROUND
            shutil.rmtree(tmp, ignore_errors=True)

    def test_a_full_rerun_of_the_redo_fits_inside_the_rounds_cap(self):
        price = lambda r: F.PRICE[{"edit": "/assets/image/edit", "styled": "/assets/image/style",
                                   "model3d": "/assets/3d-model", "cutout": "/assets/image/remove-background",
                                   "image": "/assets/image"}[r["kind"]]] * r.get("n", 1)  # noqa: E731
        grok = sum(price(r) for r in G.rows() if r["stage"] == "base"
                   or (r["id"].split("_", 1)[1] in ["%s_%s" % k for k in G.REDO] and r["stage"] in ("poses", "models")))
        ## the redo is nine poses now (the Sunspears' four joined the first five): it fits with room for three re-rolled models
        model = F.PRICE["/assets/3d-model"]
        self.assertLess(grok + 3 * model, G.CAP, "the redo and three re-rolled models stay inside the round's cap")
        fh = sum(price(r) for r in FH.rows() if r["unit"] == "hill_slingers" and r["stage"] in ("base", "poses", "models"))
        self.assertLess(fh * 2, FH.CAP)


if __name__ == "__main__":
    unittest.main(verbosity=1)
