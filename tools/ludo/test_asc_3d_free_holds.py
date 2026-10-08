#!/usr/bin/env python3
"""Tests for tools/ludo/asc_3d_free_holds.py (stdlib unittest): the batch's rows, the floor-slab trim, the cap
accounting and the board table's row surgery. Run from anywhere:

    python3 tools/ludo/test_asc_3d_free_holds.py

They never call Ludo and never touch assets/models/ or world3d/models.json: the board test runs against throwaway
copies of the descriptor and the board table in a temp folder.
"""
from __future__ import annotations

import json
import os
import shutil
import struct
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.dont_write_bytecode = True
sys.path.insert(0, HERE)
import asc_3d_free_holds as FH  # noqa: E402

F = FH.F
glb_slim = FH.glb_slim


def synthetic_glb(path):
    """A one-mesh GLB like Ludo's: a body (a box from y 0.1 to 1.0 on a 0.3 foot print) standing on a flat ground slab
    (a plate 1.0 wide and 0.004 thick at y 0 that tilts up to 0.03 at one edge), POSITION, NORMAL and TEXCOORD_0
    accessors in views of their own, uint32 indices."""
    pos, nrm, uv, idx = [], [], [], []

    def box(x0, y0, z0, x1, y1, z1):
        base = len(pos)
        for x in (x0, x1):
            for y in (y0, y1):
                for z in (z0, z1):
                    pos.append((x, y, z))
                    nrm.append((0.0, 1.0, 0.0))
                    uv.append((0.5, 0.5))
        for a, b, c in ((0, 1, 3), (0, 3, 2), (4, 6, 7), (4, 7, 5), (0, 4, 5), (0, 5, 1), (2, 3, 7), (2, 7, 6),
                        (0, 2, 6), (0, 6, 4), (1, 5, 7), (1, 7, 3)):
            idx.extend((base + a, base + b, base + c))
    box(-0.15, 0.1, -0.15, 0.15, 1.0, 0.15)  # the body
    n_body = len(idx) // 3
    box(-0.5, 0.0, -0.5, 0.5, 0.004, 0.5)  # the slab
    n_all = len(idx) // 3
    chunks = []
    views, accs = [], []

    def add(data, ctype, count, typ, target):
        off = sum(len(c) for c in chunks)
        chunks.append(data + b"\x00" * ((4 - len(data) % 4) % 4))
        views.append({"buffer": 0, "byteOffset": off, "byteLength": len(data), "target": target})
        accs.append({"bufferView": len(views) - 1, "componentType": ctype, "count": count, "type": typ})
        return len(accs) - 1
    flat = [c for p in pos for c in p]
    a_pos = add(struct.pack("<%df" % len(flat), *flat), 5126, len(pos), "VEC3", 34962)
    accs[a_pos]["min"] = [min(flat[k::3]) for k in range(3)]
    accs[a_pos]["max"] = [max(flat[k::3]) for k in range(3)]
    a_nrm = add(struct.pack("<%df" % (len(pos) * 3), *[c for n in nrm for c in n]), 5126, len(pos), "VEC3", 34962)
    a_uv = add(struct.pack("<%df" % (len(pos) * 2), *[c for u in uv for c in u]), 5126, len(pos), "VEC2", 34962)
    a_idx = add(struct.pack("<%dI" % len(idx), *idx), 5125, len(idx), "SCALAR", 34963)
    js = {"asset": {"version": "2.0"}, "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0}],
          "meshes": [{"primitives": [{"attributes": {"POSITION": a_pos, "NORMAL": a_nrm, "TEXCOORD_0": a_uv}, "indices": a_idx}]}],
          "bufferViews": views, "accessors": accs, "buffers": [{"byteLength": sum(len(c) for c in chunks)}]}
    glb_slim.write_glb(path, js, b"".join(chunks))
    return n_body, n_all


class Rows(unittest.TestCase):
    def test_every_unit_has_four_poses_of_pictures_and_models_in_the_independents_folders(self):
        rows = FH.rows()
        models = {(r["unit"], r["pose"]): r for r in rows if r["kind"] == "model3d"}
        for uid in FH.UNITS:
            for pose in FH.POSES:
                self.assertIn((uid, pose), models, "%s %s has a model row" % (uid, pose))
                self.assertEqual(models[(uid, pose)]["target"], "assets/models/units/independents/%s_%s.glb" % (uid, pose))
            pics = {r["pose"] for r in rows if r["id"].startswith("pic_%s_" % uid)}
            self.assertEqual(pics, set(FH.POSES))
            self.assertTrue(any(r["id"] == "por_" + uid for r in rows), "%s has a portrait" % uid)

    def test_a_models_picture_is_the_pick_its_pose_row_writes(self):
        rows = {r["id"]: r for r in FH.rows()}
        for r in rows.values():
            if r["kind"] == "model3d":
                self.assertEqual(r["from_file"], rows["pic_%s_%s" % (r["unit"], r["pose"])]["pick_to"])

    def test_prompts_are_phrased_positively_and_the_style_anchors_are_greyscale_or_same_faction(self):
        for r in FH.rows():
            if r.get("prompt"):
                F.check_prompt(r["prompt"])  # raises on a negative word (bible 3, rule 1)
            if r["kind"] == "styled":
                anchor = os.path.basename(r["style_file"])
                self.assertTrue(anchor.startswith("grey_") or "independents" in r["style_file"],
                                "%s: a cross-faction style anchor is greyscale (the leak rule), got %s" % (r["id"], anchor))
        for name, src in FH.GREY.items():
            self.assertTrue(os.path.exists(os.path.join(FH.ROOT, src)), "%s: its source picture is committed" % name)

    def test_shipped_portraits_are_written_only_by_the_install_action(self):
        for r in FH.rows():
            self.assertNotIn("assets/portraits/", r.get("pick_to", ""), "%s picks into a pipeline-input folder" % r["id"])
        self.assertEqual(FH.portrait_path("wildkin"), "assets/portraits/independents/wildkin.webp")


class Cap(unittest.TestCase):
    def test_the_cap_is_counted_from_the_batchs_own_ledger_and_stays_under_the_issues(self):
        self.assertLessEqual(FH.CAP, FH.JOB_CAP)
        self.assertEqual(FH.JOB_CAP, 120.0)
        self.assertEqual(F.account, FH.own_balance, "the driver reads this batch's balance, not the shared account's")
        self.assertAlmostEqual(FH.own_balance(), FH.SENTINEL - FH.ledger_spent())
        total = sum(F.PRICE["/assets/3d-model"] if r["kind"] == "model3d" else F.PRICE["/assets/image"] * r.get("n", 1)
                    for r in FH.rows())
        self.assertLess(total, FH.CAP, "one full pass of the batch fits under the stop line")


class FloorTrim(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="fh_trim_")
        self.addCleanup(shutil.rmtree, self.tmp, True)

    def test_the_ground_slab_is_cut_away_and_the_figure_stands_as_it_was(self):
        src, dst = os.path.join(self.tmp, "a.glb"), os.path.join(self.tmp, "b.glb")
        n_body, n_all = synthetic_glb(src)
        before, after = FH.trim_floor(src, dst)
        self.assertEqual(before, n_all)
        pos, tris, _ = F.glb_mesh(dst)
        self.assertEqual(after, len(tris))
        self.assertLessEqual(len(tris), n_body, "no slab triangle is left")
        self.assertGreater(len(tris), n_body - 4, "the body keeps its sides and top")
        ys = [p[1] for p in pos]
        self.assertGreaterEqual(min(ys), 0.1 - 1e-6, "the vertices of the slab are gone too")
        self.assertAlmostEqual(max(ys), 1.0, places=5)
        js, _ = glb_slim.read_glb(dst)
        acc = js["accessors"]
        self.assertEqual(acc[js["meshes"][0]["primitives"][0]["attributes"]["POSITION"]]["count"], len(pos))
        self.assertAlmostEqual(acc[js["meshes"][0]["primitives"][0]["attributes"]["POSITION"]]["min"][1], min(ys), places=5)

    def test_a_model_with_no_slab_keeps_its_figure(self):
        # the synthetic body alone (its first box), lifted off the floor: nothing in the zone to cut
        src, dst = os.path.join(self.tmp, "a.glb"), os.path.join(self.tmp, "b.glb")
        n_body, _ = synthetic_glb(src)
        pos, tris, _ = F.glb_mesh(src)
        lo = min(p[1] for p in pos)
        gone = FH.floor_triangles(pos, tris, lo, max(p[1] for p in pos) - lo)
        self.assertEqual(len([k for k in gone if k < n_body]), 0, "the body's triangles are never in the slab")


class BoardTable(unittest.TestCase):
    def test_board_rows_are_edited_line_by_line_and_nothing_else_changes(self):
        tmp = tempfile.mkdtemp(prefix="fh_board_")
        self.addCleanup(shutil.rmtree, tmp, True)
        table = os.path.join(tmp, "models.json")
        shutil.copy(FH.BOARD_TABLE, table)
        before = open(table).read().split("\n")
        desc = {"units": {}}
        for uid in FH.UNITS:
            desc["units"][uid] = {pose: {"path": "res://assets/models/units/independents/%s_%s.glb" % (uid, pose), "yaw": 0.0,
                                         "size": {"axis": "length" if pose == "fallen" else "height", "men": 1.0 + 0.1 * i}}
                                  for i, pose in enumerate(FH.POSES)}
        old_table, old_load = FH.BOARD_TABLE, F.load_descriptor
        FH.BOARD_TABLE, F.load_descriptor = table, lambda: desc
        try:
            rows = FH.board()
        finally:
            FH.BOARD_TABLE, F.load_descriptor = old_table, old_load
        after = open(table).read().split("\n")
        self.assertEqual(len(before), len(after))
        changed = [k for k in range(len(before)) if before[k] != after[k]]
        heads = ['\t\t"%s": ' % k for k in list(FH.UNITS) + ["bearer", "musician"]]
        for k in changed:
            self.assertTrue(any(after[k].startswith(h) for h in heads), "only the Free Holds' rows change, not: " + after[k][:60])
        self.assertGreaterEqual(len(changed), 2, "at least the bearer and the musician take the Free Holds' models")
        data = json.loads("\n".join(after))
        for uid in FH.UNITS:
            row = data["figures"][uid]
            self.assertEqual(row["model"], "res://assets/models/units/independents/%s_ready.glb" % uid)
            self.assertEqual(set(row["poses"]), set(FH.POSES))
            self.assertEqual(row["tint"], FH.FIGURE_TINT)
            self.assertEqual(row["fallback"], uid, "the kit's placeholder row survives")
        self.assertEqual(data["figures"]["bearer"]["models"]["independents"], data["figures"]["free_spears"]["model"])
        self.assertEqual(data["figures"]["bearer"]["models"]["kingdom"], json.loads("\n".join(before))["figures"]["bearer"]["models"]["kingdom"])
        self.assertEqual(sorted(rows), sorted(list(FH.UNITS) + ["bearer", "musician"]))


if __name__ == "__main__":
    unittest.main()
