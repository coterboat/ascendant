#!/usr/bin/env python3
"""Tests for tools/ludo/asc_3d_fixtures.py (stdlib unittest): the batch's rows and prompts, its budget and ledger, the gate, the
shots it plans and the review batch it builds. Run from anywhere:

    python3 tools/ludo/test_asc_3d_fixtures.py

They never call Ludo, never start Godot and never write assets/ or world3d/models.json: the one review batch they build (to check
what review.py from-folder makes of the staged folder) is named review/_test_fixtures_<random>, made from a real Ludo GLB of the
repo copied into a temp folder, and removed afterwards.
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
import unittest
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
sys.dont_write_bytecode = True
sys.path.insert(0, HERE)
import asc_3d_fixtures as X  # noqa: E402
import base_gate  # noqa: E402

F, G = X.F, X.G
REPO = X.ROOT
SAMPLE_GLB = os.path.join(REPO, "assets", "models", "units", "kingdom", "spearmen_ready.glb")  ## any real Ludo GLB
PNG = bytes.fromhex("89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000d49444154789c6360f8cf0000000200"
                    "01e221bc330000000049454e44ae426082")
TABLES = [os.path.join(REPO, "world3d", "models.json"), os.path.join(REPO, "assets", "models", "models.json")]


def jload(path):
    with open(path) as f:
        return json.load(f)


def sha(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


class Rows(unittest.TestCase):
    def test_the_batch_makes_pictures_of_the_fixture_the_body_and_the_fused_strike_and_a_model_of_each_pick(self):
        rows = X.rows()
        ids = [r["id"] for r in rows]
        self.assertEqual(len(ids), len(set(ids)), "row ids are unique")
        pics = [r for r in rows if r["kind"] != "model3d"]
        models = [r for r in rows if r["kind"] == "model3d"]
        self.assertEqual({r["id"] for r in pics}, {"pic_blade", "pic_blade_edit", "pic_strike_body", "pic_strike_fused",
                                                    "pic_cuff_r1", "pic_cuff_r2", "pic_cuff_r3"})
        self.assertEqual({r["id"] for r in models}, {"model_blade", "model_strike_body", "model_strike_fused",
                                                      "model_cuff_a", "model_cuff_b", "model_cuff_c"})
        picks = {r["pick_to"] for r in pics}
        for m in models:
            ## a model reads a pick of this batch: some picture row's own pick, or a named pick (`pick <row> <k> <name>`: the blade's
            ## and the cuff blades' models are made from take k of a picture row under the name of the part)
            self.assertEqual(os.path.dirname(m["from_file"]), X.PICKS, "%s reads a pick of this batch" % m["id"])
            if m["id"] in ("model_strike_body", "model_strike_fused"):
                self.assertIn(m["from_file"], picks)
        for r in rows:
            self.assertEqual(r["unit"], X.FAMILY)

    def test_the_blade_is_a_small_model_and_the_figure_is_not(self):
        faces = {r["id"]: r["faces"] for r in X.rows() if r["kind"] == "model3d"}
        self.assertLess(faces["model_blade"], faces["model_strike_body"] / 3, "a fixture drawn on every figure costs few triangles")
        for k in "abc":
            self.assertLess(faces["model_cuff_" + k], faces["model_strike_body"] / 2, "a blade with its cuff is under half a figure")

    def test_no_prompt_holds_a_negative_and_the_fused_line_says_what_the_blade_is(self):
        for r in X.rows():
            if r.get("prompt"):
                F.check_prompt(r["prompt"])  ## raises on no / not / without / never / negative
        for word in ("thick", "bone-white", "forearm", "open"):
            self.assertIn(word, X.STRIKE_FUSED)
        for word in ("hilt", "grip", "sword", "gap"):
            self.assertNotIn(word, X.STRIKE_FUSED.lower(), "a word that is drawn is not in the prompt")
        self.assertNotIn("blade", X.STRIKE_BODY.lower(), "the body's picture asks for no blade at all")
        for rnd, text in X.CUFF_PROMPTS.items():
            for word in ("cuff", "sinew", "thick", "one solid piece", "wedge"):
                self.assertIn(word, text, "cuff round %s says what the part is" % rnd)
            self.assertNotIn("hilt", text.lower())
            self.assertNotIn("grip", text.lower())

    def test_nothing_of_this_batch_is_committed(self):
        ready = G.pick_of(X.FAMILY, "ready")
        for r in X.rows():
            for key in ("pick_to", "from_file", "style_file"):
                p = r.get(key)
                if p and p != ready:  ## the ready picture is the existing committed pipeline input, only read here
                    self.assertTrue(p.startswith("assets/_concept/candidates/"), "%s: %s is under a gitignored candidates folder" % (r["id"], p))
        for a in jload(X.MANIFEST)["assets"]:
            self.assertIn("/candidates/", a["out"], a["id"])
        self.assertTrue(X.PICKS.startswith("assets/_concept/candidates/"))
        self.assertTrue(X.GLB_CAND.startswith("assets/models/candidates/"))

    def test_the_pictures_that_are_edits_start_from_the_accepted_ready_picture(self):
        ready = G.pick_of(X.FAMILY, "ready")
        for r in X.rows():
            if r["id"] in ("pic_blade_edit", "pic_strike_body", "pic_strike_fused", "pic_cuff_r1", "pic_cuff_r2", "pic_cuff_r3"):
                self.assertEqual(r["from_file"], ready, r["id"])
            if r["id"] == "pic_blade":
                self.assertEqual(r["style_file"], ready)


class Budget(unittest.TestCase):
    def test_the_cap_was_raised_by_exactly_the_cuff_rounds_20_and_the_driver_stops_at_the_20(self):
        self.assertEqual(X.ROUND, G.ROUND)
        self.assertEqual(X.CAP, 35.0 + 20.0, "the first round's 35, raised by exactly the cuff round's 20")
        self.assertEqual(X.STOP, 23.5 + 20.0, "the first round spent 23.5: the cuff round stops 20 after it")
        self.assertEqual(X.F.CAP, X.STOP, "the driver stops there, not at the looser cap")

    def test_every_ledger_line_is_tagged_with_the_round_and_the_spend_stays_in_the_cap(self):
        with open(X.LEDGER) as f:
            lines = [json.loads(line) for line in f if line.strip()]
        self.assertTrue(lines, "the ledger has the batch's charged calls")
        for e in lines:
            self.assertEqual(e.get("round"), X.ROUND, e["row"])
            self.assertTrue(e["request_id"].startswith(X.RID + "-"), e["request_id"])
        self.assertAlmostEqual(X.ledger_spent(X.ROUND), sum(float(e["credits_charged"]) for e in lines))
        self.assertLessEqual(X.ledger_spent(X.ROUND), X.STOP)
        self.assertEqual(X.F.account(), X.SENTINEL - X.ledger_spent(X.ROUND), "the driver counts this batch's own spend, not the shared account")

    def test_a_pass_of_every_row_fits_the_cap_with_room_for_rerolls(self):
        total = 0.0
        for r in X.rows():
            ep = {"model3d": "/assets/3d-model", "styled": "/assets/image/style", "edit": "/assets/image/edit"}[r["kind"]]
            total += F.PRICE[ep] * r.get("n", 1)
        self.assertLess(total, X.STOP, "a pass of every row stays inside the stop line")


class Gate(unittest.TestCase):
    def test_a_row_is_refused_when_the_bloodsworns_base_is_no_longer_accepted(self):
        """The Bloodsworn's base is grandfathered (Alex accepted its ready model on 10-8): the gate is open, until the batch that
        accepted it says otherwise."""
        row = {"id": "pic_blade", "unit": X.FAMILY, "stage": "pictures"}
        g = G.GRANDFATHERED[X.FAMILY]
        with tempfile.TemporaryDirectory() as root, mock.patch.dict(os.environ, {"ASC_REVIEW_DIR": root}):
            X.gate_row(row)  ## nothing says otherwise: it stands
            os.makedirs(os.path.join(root, g["batch"]))
            with open(os.path.join(root, g["batch"], "review.json"), "w") as f:
                json.dump({"items": {g["item"]: {"verdict": "reject", "note": "no", "at": "2026-10-10T09:00:00"}}}, f)
            with self.assertRaises(base_gate.BaseNotAccepted):
                X.gate_row(row)
            with self.assertRaises(SystemExit):
                X.run("pictures", [], 1, 1)  ## refuses before it reads the key or calls Ludo


class Sizes(unittest.TestCase):
    def test_a_pose_is_sized_by_the_bodys_share_of_the_models_box(self):
        with mock.patch.object(X.F, "measure", return_value={"size": [1.0, 0.8, 0.4]}), mock.patch.object(X, "staged_path", lambda r: r):
            self.assertAlmostEqual(X.men_for("strike_body"), round(X.BODY_MEN / X.BODY_SHARE["strike_body"], 3))
            taller = X.men_for("strike_body", 0.92)
            self.assertAlmostEqual(taller, round(X.BODY_MEN / X.BODY_SHARE["strike_body"] * 0.92 / 0.8, 3),
                                   msg="blades add to the box: the same scale over the taller box")
            self.assertGreater(taller, X.men_for("strike_body"))
        for share in X.BODY_SHARE.values():
            self.assertTrue(0.6 < share < 1.0)


class Shots(unittest.TestCase):
    ATT = [{"mesh": "res://assets/models/candidates/fixtures/_stage/blade.glb", "pivot": [0, -0.4, 0],
            "poses": {"strike": {"pos": [0.3, 0.2, 0.0], "rot": [0, 0, 20], "scale": 0.4}}}]

    def test_the_comparison_draws_the_game_as_it_is_then_each_candidate_from_a_row_built_in_memory(self):
        before = [sha(t) for t in TABLES]
        cuff = [{"mesh": "res://assets/models/candidates/fixtures/_stage/cuff_a.glb", "pivot": [0, -0.4, 0],
                 "poses": {"strike": {"pos": [-0.25, 0.28, -0.05], "rot": [-72.0, 90.0, 0.0], "scale": 0.42}}}]
        with mock.patch.object(X.F, "measure", return_value={"size": [1.0, 0.8, 0.4]}), mock.patch.object(X, "staged_path", lambda r: r):
            plan = X.compare_plan(self.ATT, [("a2) cuff", cuff), ("a3) cuff hook", cuff)])
        self.assertEqual([sha(t) for t in TABLES], before, "the game's tables are not written")
        self.assertEqual([s["yaw"] for s in plan], [c[1] for c in X.CAMERAS])
        self.assertEqual(len({s["file"] for s in plan}), len(plan))
        items = plan[0]["items"]
        self.assertEqual([i["label"] for i in items], ["in the game now", "a) flat blade", "a2) cuff", "a3) cuff hook", "b) fused blades"])
        with open(TABLES[0]) as f:
            installed = json.load(f)["figures"][X.FAMILY]
        self.assertEqual(items[0]["row"], installed, "the game's own figure is its row exactly as the table holds it")
        self.assertEqual(items[0]["path"], "res://" + X.GAME_STRIKE)
        self.assertNotIn("attachments", installed, "(the installed row names none)")
        self.assertEqual(items[1]["row"]["attachments"], self.ATT, "a) is the loader's: the row names the blades")
        self.assertEqual(items[2]["row"]["attachments"], cuff, "so is each cuff candidate: its row names the blades")
        self.assertEqual(items[1]["path"], items[2]["path"], "on the same body")
        self.assertNotIn("attachments", items[4]["row"], "b) is one model, nothing attached")
        for i in items[1:]:
            self.assertEqual(i["row"]["poses"], installed["poses"], "the rest of the row is the installed one")
            self.assertEqual(i["row"]["pose_size"]["ready"], installed["pose_size"]["ready"])
        self.assertEqual(items[2]["row"]["pose_size"]["strike"], items[1]["row"]["pose_size"]["strike"], "the body is sized by the body alone")
        json.dumps(plan)  ## it is what sheet.gd reads

    def test_a_cuff_part_is_placed_in_the_terms_a_person_thinks_in_and_the_euler_angles_are_solved(self):
        import math
        for axis in ("x", "y"):
            for theta, roll, yaw in ((70, 0, 0), (-105, 180, 0), (160, -30, 0), (-25, 30, 15), (0, 0, 0), (90, 90, 0)):
                rot = X.rot_for(axis, theta, roll, yaw)
                want = X._mul(X._rot("y", math.radians(yaw)), X._mul(X._rot("z", math.radians(theta)), X._rot(axis, math.radians(roll))))
                ex, ey, ez = (math.radians(a) for a in rot)  ## Godot's Basis.from_euler default: Y, then X, then Z
                got = X._mul(X._rot("y", ey), X._mul(X._rot("x", ex), X._rot("z", ez)))
                for i in range(3):
                    for j in range(3):
                        self.assertAlmostEqual(got[i][j], want[i][j], places=3, msg="%s %s %s %s" % (axis, theta, roll, yaw))
        params = {"axis": "y", "pivot": [0.02, -0.4, 0.0], "arms": [{"pos": [-0.25, 0.28, -0.05], "scale": 0.42, "theta": 70, "roll": 0},
                                                                    {"pos": [0.26, 0.2, -0.05], "scale": 0.42, "theta": -105, "roll": 180}]}
        row = X.cuff_row("cuff_a", params)
        self.assertEqual(len(row["attachments"]), 2, "one entry a forearm")
        for e, arm in zip(row["attachments"], params["arms"]):
            self.assertEqual(e["mesh"], X.STAGE_RES + "cuff_a.glb")
            self.assertEqual(e["pivot"], params["pivot"], "the pivot is the cuff's centre: pos is where the cuff sits")
            t = e["poses"][X.STRIKE]
            self.assertEqual((t["pos"], t["scale"]), (arm["pos"], arm["scale"]))
            self.assertEqual(len(t["rot"]), 3)

    def test_the_placement_plan_is_seven_views_on_a_graph_paper_then_four_close_ups_of_the_same_row(self):
        row = {"attachments": self.ATT}
        plan = X.place_plan(row)
        self.assertEqual(len(plan), len(X.RAW_VIEWS) + len(X.ZOOMS))
        self.assertEqual(len({s["file"] for s in plan}), len(plan))
        for s in plan:
            self.assertEqual(s["mode"], "raw")
            self.assertEqual(s["items"][0]["row"], row)
            self.assertEqual(s["items"][0]["pose"], X.STRIKE)
        views = [s.get("view") for s in plan[:len(X.RAW_VIEWS)] if s.get("view")]
        self.assertEqual(set(views), {"front", "right", "back", "left", "top"}, "the five straight views carry the scale")
        for s in plan[len(X.RAW_VIEWS):]:
            self.assertLess(s["extent"], plan[0]["extent"], "a close-up")


class Batch(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="fixtures_test_")
        self.name = "_test_fixtures_" + secrets.token_hex(3)
        self.bdir = os.path.join(REPO, "review", self.name)
        stage = os.path.join(self.tmp, "_stage")
        os.makedirs(stage)
        for n in ("blade", "blade_v1", "strike_body", "strike_fused", "strike_attach", "strike_attach_cuff_a", "strike_attach_cuff_c",
                  "cuff_a", "cuff_b", "cuff_c"):
            shutil.copy(SAMPLE_GLB, os.path.join(stage, n + ".glb"))
        self.sheets = os.path.join(self.tmp, "_review")
        os.makedirs(self.sheets)
        with open(os.path.join(self.sheets, "compare_board.png"), "wb") as f:
            f.write(PNG)
        self.row = os.path.join(self.tmp, "strike_attachments.json")
        with open(self.row, "w") as f:
            json.dump({"attachments": Shots.ATT}, f)
        self.cuff_rows = {}
        for k in ("cuff_a", "cuff_c"):
            self.cuff_rows[k] = os.path.join(self.tmp, "row_%s.json" % k)
            with open(self.cuff_rows[k], "w") as f:
                json.dump({"attachments": Shots.ATT}, f)
            with open(os.path.join(self.tmp, "params_%s.json" % k), "w") as f:
                json.dump({"axis": "y", "pivot": [0, 0, 0], "arms": []}, f)
        recs = {"strike_attach": {"men": 1.39, "axis": "height", "faces": 7000},
                "strike_attach_cuff_a": {"men": 1.36, "axis": "height", "faces": 9000},
                "strike_attach_cuff_c": {"men": 1.47, "axis": "height", "faces": 9200}}
        self.patches = [
            mock.patch.object(X, "GLB_CAND", self.tmp),  ## absolute: os.path.join(ROOT, abs) is abs
            mock.patch.object(X, "SHEETS", self.sheets),
            mock.patch.object(X, "attachments_path", lambda: self.row),
            mock.patch.object(X, "cuff_row_path", lambda key: self.cuff_rows[key]),
            mock.patch.object(X, "cuff_params_path", lambda key: os.path.join(self.tmp, "params_%s.json" % key)),
            mock.patch.object(X, "load_records", lambda: recs),
        ]
        for p in self.patches:
            p.start()

    def tearDown(self):
        for p in self.patches:
            p.stop()
        shutil.rmtree(self.tmp, ignore_errors=True)
        shutil.rmtree(self.bdir, ignore_errors=True)

    def test_the_batch_holds_the_strike_candidates_first_each_with_the_games_strike_as_target_and_no_actions(self):
        before = [sha(t) for t in TABLES]
        X.batch(self.name)
        self.assertEqual([sha(t) for t in TABLES], before, "no row of the game's tables was written")
        data = jload(os.path.join(self.bdir, "batch.json"))
        self.assertNotIn("actions", data, "nothing installs from this batch: the verdicts and the install are the owner's")
        items = data["items"]
        self.assertEqual([i["group"] for i in items], ["strike"] * 4 + ["parts"] * 6)
        strike = items[:4]
        self.assertEqual([i["label"].split("·")[-1].strip()[:3] for i in strike], ["a) ", "a2)", "a3)", "b) "], "a, a2, a3, b in that order")
        self.assertTrue(strike[0]["id"].endswith("attach") and strike[3]["id"].endswith("fused"))
        self.assertEqual({i["id"] for i in strike[1:3]}, {"strike_bloodsworn_strike_attach_cuff_a", "strike_bloodsworn_strike_attach_cuff_c"})
        self.assertEqual({i["id"] for i in items[4:]}, {"parts_bloodsworn_blade", "parts_bloodsworn_blade_1200", "parts_bloodsworn_cuff_a",
                                                         "parts_bloodsworn_cuff_b", "parts_bloodsworn_cuff_c", "parts_bloodsworn_strike_body"})
        for it in strike:
            self.assertEqual(it["kind"], "model")
            self.assertEqual(it["target"], X.GAME_STRIKE)
            self.assertTrue(os.path.exists(os.path.join(REPO, it["target"])), "`0` has the game's model to show")
            self.assertEqual(it["meta"]["pose"], X.STRIKE)
            self.assertGreater(it["meta"]["size"]["men"], 1.0)
            self.assertTrue(os.path.exists(os.path.join(self.bdir, it["file"])))
        for it in items[4:]:
            self.assertNotIn("target", it, "the parts are not stand-ins for anything in the game")
        self.assertEqual(strike[0]["meta"]["size"]["men"], 1.39, "the baked model is sized by its own box")
        self.assertEqual(strike[1]["meta"]["size"]["men"], 1.36)

    def test_the_candidate_row_and_the_sheets_come_along_and_the_row_says_what_it_is(self):
        X.batch(self.name)
        row = jload(os.path.join(self.bdir, "attachments.json"))
        self.assertEqual(row["attachments"], Shots.ATT)
        self.assertIn("not installed", row["_note"])
        for k in ("cuff_a", "cuff_c"):  ## each cuff candidate's row and the placement it was made from
            crow = jload(os.path.join(self.bdir, "attachments_%s.json" % k))
            self.assertEqual(crow["attachments"], Shots.ATT)
            self.assertIn("not installed", crow["_note"])
            self.assertTrue(os.path.exists(os.path.join(self.bdir, "placement_%s.json" % k)))
        self.assertTrue(os.path.exists(os.path.join(self.bdir, "sheets", "compare_board.png")))

    def test_it_passes_the_review_tables_own_checks_and_keeps_verdicts_when_run_again(self):
        review = os.path.join(REPO, "tools", "review", "review.py")
        X.batch(self.name)
        st = subprocess.run([sys.executable, review, "status", self.name], capture_output=True, text=True, cwd=REPO)
        self.assertEqual(st.returncode, 0, st.stdout + st.stderr)
        self.assertIn("0/10 reviewed", st.stdout)
        data = jload(os.path.join(self.bdir, "batch.json"))
        first = data["items"][0]
        fm = os.path.getmtime(os.path.join(self.bdir, first["file"]))
        with open(os.path.join(self.bdir, "review.json"), "w") as f:
            json.dump({"items": {first["id"]: {"verdict": "reject", "note": "x", "at": "2026-10-10T12:00:00", "file_mtime": fm}}}, f)
        X.batch(self.name)
        again = jload(os.path.join(self.bdir, "batch.json"))
        self.assertEqual([i["id"] for i in again["items"]], [i["id"] for i in data["items"]], "the same ten, not doubled")
        self.assertEqual(jload(os.path.join(self.bdir, "review.json"))["items"][first["id"]]["verdict"], "reject", "the verdict stays")


if __name__ == "__main__":
    unittest.main()
