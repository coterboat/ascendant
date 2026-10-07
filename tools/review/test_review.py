#!/usr/bin/env python3
"""Tests for the review table (stdlib unittest). Run from anywhere:

    python3 tools/review/test_review.py

They make throwaway batches under review/_test_<random>/ (scripts, media), start the server on a
free port in-process, and delete everything afterwards. Nothing here calls Ludo or touches a
real batch.
"""
from __future__ import annotations

import contextlib
import io
import json
import os
import secrets
import shutil
import sys
import tempfile
import textwrap
import threading
import time
import unittest
import urllib.error
import urllib.request
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import review as R  # noqa: E402

TAG = "_test_" + secrets.token_hex(3)

## prints its argv, then `--lines` lines slowly; exits 1 with --fail; --forever runs until killed
## (and starts a child that would, too: cancel must take the whole process group down)
SCRIPT = textwrap.dedent("""\
    import subprocess, sys, time
    args = sys.argv[1:]
    print("argv:", " ".join(args), flush=True)
    n = int(args[args.index("--lines") + 1]) if "--lines" in args else 3
    if "--forever" in args:
        child = subprocess.Popen([sys.executable, "-c", "import time\\nwhile True: time.sleep(0.2)"])
        print("child", child.pid, flush=True)
        while True:
            print("tick", flush=True)
            time.sleep(0.1)
    for i in range(n):
        print("line %d" % (i + 1), flush=True)
        time.sleep(0.05)
    if "--show-rejected" in args:
        print(open("review/%s/rejected.json" % args[args.index("--show-rejected") + 1]).read(), flush=True)
    sys.exit(1 if "--fail" in args else 0)
""")


def make_batch(name: str, data: dict, files: dict[str, bytes] = None) -> Path:
    d = R.REVIEW / name
    d.mkdir(parents=True, exist_ok=True)
    for rel, blob in (files or {}).items():
        p = d / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(blob)
    R.atomic_write_json(d / "batch.json", {"batch": name, **data})
    return d


def script_rel() -> str:
    return f"review/{TAG}/slow.py"


def action(**kw) -> dict:
    a = {"id": "go", "kind": "install", "label": "Go", "cmd": ["python3", script_rel(), "--install"], "options": []}
    a.update(kw)
    return a


class ArgvTests(unittest.TestCase):
    """Building argv from a declared action and the options the page sent."""

    @classmethod
    def setUpClass(cls):
        R.ensure_review_root()
        (R.REVIEW / TAG).mkdir(parents=True, exist_ok=True)
        (R.REVIEW / TAG / "slow.py").write_text(SCRIPT)

    def act(self, **kw):
        return R.check_action(action(**kw))

    def test_options_build_argv(self):
        a = self.act(options=[
            {"flag": "--dry-run", "label": "Dry run", "type": "bool", "default": False},
            {"flag": "--takes", "label": "Takes", "type": "int", "default": 1, "min": 1, "max": 4},
            {"flag": "--model", "label": "Model", "type": "choice", "choices": ["a", "b"]},
            {"flag": "--tag", "label": "Tag", "type": "string"}])
        argv, extra = R.build_argv(a, {"--dry-run": True, "--takes": 3, "--model": "b", "--tag": "hello world"})
        self.assertEqual(argv[0], sys.executable)
        self.assertEqual(Path(argv[1]), (R.REPO / script_rel()).resolve())
        self.assertEqual(argv[2:], ["--install", "--dry-run", "--takes", "3", "--model", "b", "--tag", "hello world"])
        self.assertEqual(extra, ["--dry-run", "--takes", "3", "--model", "b", "--tag", "hello world"])
        # false / missing / null / empty: left out (the script's own default applies)
        argv, extra = R.build_argv(a, {"--dry-run": False, "--takes": None, "--tag": ""})
        self.assertEqual(extra, [])
        self.assertEqual(R.build_argv(a, None)[1], [])
        # an int may arrive as a numeric string or a whole float
        self.assertEqual(R.build_argv(a, {"--takes": "2"})[1], ["--takes", "2"])
        self.assertEqual(R.build_argv(a, {"--takes": 4.0})[1], ["--takes", "4"])

    def test_bad_options_rejected(self):
        a = self.act(options=[
            {"flag": "--dry-run", "type": "bool"},
            {"flag": "--takes", "type": "int", "min": 1, "max": 4},
            {"flag": "--model", "type": "choice", "choices": ["a", "b"]},
            {"flag": "--tag", "type": "string"}])
        bad = [
            {"--evil": True},                       # undeclared flag
            {"; rm -rf /": True},                   # not even a flag
            {"--dry-run": "yes"},                   # bool must be a bool
            {"--takes": 9}, {"--takes": 0},         # out of range
            {"--takes": "abc"}, {"--takes": 2.5},   # not a whole number
            {"--takes": True},                      # bools aren't ints
            {"--model": "c"}, {"--model": ["a"]},   # not a choice
            {"--tag": "--install"},                 # would read as a flag
            {"--tag": "two\nlines"},                # control characters
            {"--tag": 5},                           # not a string
        ]
        for opts in bad:
            with self.subTest(opts=opts), self.assertRaises(R.ReviewError):
                R.build_argv(a, opts)
        with self.assertRaises(R.ReviewError):
            R.build_argv(a, ["--dry-run"])  # options must be an object

    def test_cmd_restrictions(self):
        (R.REPO / "review" / TAG / "sub").mkdir(exist_ok=True)
        bad_cmds = [
            ["bash", script_rel()],                      # only python3
            ["/usr/bin/python3", script_rel()],          # not a path to a python either
            ["python", script_rel()],
            ["python3"],                                 # needs a script
            ["python3", "-c", "print(1)"],               # no inline code
            ["python3", "../outside.py"],                # stays in the repo
            ["python3", "/etc/hosts"],                   # no absolute paths
            ["python3", f"review/{TAG}/missing.py"],     # must exist
            ["python3", f"review/{TAG}/sub"],            # must be a file
            ["python3", script_rel(), 7],                # strings only
            "python3 " + script_rel(),                   # a list, not a shell string
        ]
        for cmd in bad_cmds:
            with self.subTest(cmd=cmd), self.assertRaises(R.ReviewError):
                R.check_action(action(cmd=cmd))
        R.check_action(action())  # the good one passes

    def test_declaration_validation(self):
        bad = [
            {"options": [{"flag": "dry", "type": "bool"}]},                      # not --flag
            {"options": [{"flag": "--x", "type": "float"}]},                     # unknown type
            {"options": [{"flag": "--x", "type": "choice", "choices": []}]},
            {"options": [{"flag": "--x", "type": "int", "min": 5, "max": 1}]},
            {"options": [{"flag": "--x", "type": "int", "default": 9, "max": 4}]},
            {"options": [{"flag": "--x", "type": "bool"}, {"flag": "--x", "type": "bool"}]},
            {"id": "has space"},
        ]
        for kw in bad:
            with self.subTest(kw=kw), self.assertRaises(R.ReviewError):
                R.check_action(action(**kw))
        # batch_actions marks a bad one with an error instead of failing the batch
        acts = R.batch_actions("x", {"actions": [action(), action(id="bad", cmd=["sh", "x"])]})
        self.assertNotIn("error", acts[0])
        self.assertIn("error", acts[1])
        with self.assertRaises(R.ReviewError):
            R.build_argv(acts[1], {})
        # the same id twice
        acts = R.batch_actions("x", {"actions": [action(), action()]})
        self.assertIn("error", acts[1])

    def test_builtin_when_no_actions(self):
        for data in ({}, {"actions": []}):
            acts = R.batch_actions("demo", data)
            self.assertEqual([a["id"] for a in acts], ["install"])
            self.assertEqual(acts[0]["cmd"], ["python3", "tools/review/review.py", "apply", "demo"])
            self.assertTrue(acts[0]["builtin"])
            self.assertFalse(any(a["kind"] == "regen" for a in acts))


class ServerTests(unittest.TestCase):
    """The HTTP side: token and Origin checks, runs, the built-in apply, video media."""

    @classmethod
    def setUpClass(cls):
        R.ensure_review_root()
        cls.name = TAG
        cls.plain = TAG + "_plain"
        crest = R.REVIEW / TAG / "_crest.png"
        R._write_png(crest, 16)
        png = crest.read_bytes()
        crest.unlink()
        cls.video = bytes(range(256)) * 40  # 10240 bytes: enough for Range tests (not a real clip)
        make_batch(cls.name, {
            "title": "actions test",
            "actions": [
                action(id="install", options=[{"flag": "--lines", "type": "int", "default": 3, "min": 1, "max": 50},
                                              {"flag": "--fail", "type": "bool"}]),
                action(id="forever", kind="custom", label="Forever", cmd=["python3", script_rel(), "--forever"]),
                action(id="regen", kind="regen", label="Redo", spends=True,
                       cmd=["python3", script_rel(), "--show-rejected", TAG]),
                action(id="broken", cmd=["bash", "-c", "echo pwned"]),
            ],
            "items": [
                {"id": "clip", "kind": "video", "file": "clip.mp4", "target": f"review/{TAG}/out/clip.mp4", "poster": "poster.png"},
                {"id": "clip2", "file": "clip.webm"},
                {"id": "gif", "kind": "image", "file": "anim.gif", "meta": {"video_mp4": "clip.mp4"}},
                {"id": "gif2", "kind": "image", "file": "anim.gif", "meta": {"video_mp4": f"review/{TAG}/clip.mov"}},
                {"id": "still", "kind": "image", "file": "still_poster.png"},
                {"id": "nope", "kind": "image", "file": "anim.gif", "meta": {"video_mp4": "../../README.md"}},
            ],
        }, {"slow.py": SCRIPT.encode(), "clip.mp4": cls.video, "clip.webm": cls.video, "clip.mov": cls.video,
            "clip.ogv": cls.video, "still_poster.png": png, "still.m4v": cls.video, "poster.png": png, "anim.gif": png})
        R.decide(cls.name, "clip", verdict="reject", note="too dark")
        make_batch(cls.plain, {"title": "no actions", "items": [
            {"id": "crest", "kind": "image", "file": "crest.png", "target": f"review/{cls.plain}/out/crest.png"}]},
            {"crest.png": png})
        R.decide(cls.plain, "crest", verdict="accept")
        cls.httpd = R.Server(("127.0.0.1", 0), R.Handler)
        cls.port = cls.httpd.server_address[1]
        cls.base = f"http://127.0.0.1:{cls.port}"
        threading.Thread(target=cls.httpd.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        R.cancel_all_runs()
        for r in list(R._RUNS.values()):
            r.done.wait(10)
        cls.httpd.shutdown()
        cls.httpd.server_close()
        shutil.rmtree(R.REVIEW / cls.name, ignore_errors=True)
        shutil.rmtree(R.REVIEW / cls.plain, ignore_errors=True)

    # -- helpers
    def req(self, method, path, body=None, headers=None, token=True, ctype="application/json"):
        data = None if body is None else (body if isinstance(body, bytes) else json.dumps(body).encode())
        h = {}
        if method == "POST":
            if ctype:
                h["Content-Type"] = ctype
            if token:
                h["X-Review-Token"] = self.httpd.token
        h.update(headers or {})
        rq = urllib.request.Request(self.base + path, data=data, method=method, headers=h)
        try:
            with urllib.request.urlopen(rq, timeout=15) as r:
                return r.status, dict(r.headers), r.read()
        except urllib.error.HTTPError as e:
            with e:
                return e.code, dict(e.headers), e.read()

    def jreq(self, *a, **kw):
        status, headers, body = self.req(*a, **kw)
        return status, json.loads(body or b"null")

    def run_to_end(self, batch, action_id, options=None, timeout=20):
        st, d = self.jreq("POST", "/api/run", {"batch": batch, "action": action_id, "options": options or {}})
        self.assertEqual(st, 200, d)
        rid, out, nxt = d["run"]["id"], "", 0
        seen_running = d["run"]["status"] == "running"
        t0 = time.time()
        while time.time() - t0 < timeout:
            st, info = self.jreq("GET", f"/api/run/{rid}?from={nxt}")
            self.assertEqual(st, 200, info)
            self.assertEqual(info["next"], nxt + len(info["output"]))  # offsets line up
            out += info["output"]
            nxt = info["next"]
            if info["status"] != "running":
                return info, out, seen_running
            time.sleep(0.05)
        self.fail("run did not finish")

    # -- page + token
    def test_index_carries_token_and_frame_guard(self):
        st, h, body = self.req("GET", "/")
        self.assertEqual(st, 200)
        html = body.decode()
        self.assertIn(self.httpd.token, html)
        self.assertNotIn(R.TOKEN_SLOT, html)
        self.assertEqual(h.get("X-Frame-Options"), "DENY")

    def test_post_needs_token_origin_and_json(self):
        body = {"batch": self.name, "id": "gif", "note": "hi"}
        st, d = self.jreq("POST", "/api/decide", body, token=False)
        self.assertEqual(st, 403)
        self.assertIn("X-Review-Token", d["error"])
        st, d = self.jreq("POST", "/api/decide", body, headers={"X-Review-Token": "wrong"})
        self.assertEqual(st, 403)
        st, d = self.jreq("POST", "/api/decide", body, headers={"Origin": "http://evil.example"})
        self.assertEqual(st, 403)
        self.assertIn("cross-origin", d["error"])
        st, d = self.jreq("POST", "/api/decide", body, headers={"Origin": "null"})
        self.assertEqual(st, 403)
        st, d = self.jreq("POST", "/api/decide", body, headers={"Origin": f"http://127.0.0.1:{self.port + 1}"})
        self.assertEqual(st, 403)
        st, d = self.jreq("POST", "/api/decide", body, ctype="text/plain")
        self.assertEqual(st, 415)
        st, d = self.jreq("POST", "/api/run", {"batch": self.name, "action": "install"}, token=False)
        self.assertEqual(st, 403)
        st, d = self.jreq("POST", "/api/run/abcdef123456/cancel", {}, headers={"Origin": "http://evil.example"})
        self.assertEqual(st, 403)
        st, d = self.jreq("POST", "/api/decide", body, headers={"Host": "evil.example:80"})
        self.assertEqual(st, 403)
        # the page's own origin (either name) is fine
        for origin in (f"http://127.0.0.1:{self.port}", f"http://localhost:{self.port}"):
            st, d = self.jreq("POST", "/api/decide", body, headers={"Origin": origin})
            self.assertEqual(st, 200, d)
        st, d = self.jreq("POST", "/api/decide", body)  # no Origin (curl, scripts): token is enough
        self.assertEqual(st, 200, d)

    def test_batch_lists_actions_for_the_ui(self):
        st, d = self.jreq("GET", f"/api/batch/{self.name}")
        acts = {a["id"]: a for a in d["actions"]}
        self.assertEqual(acts["install"]["cmd"], f"python3 {script_rel()} --install")
        self.assertTrue(acts["regen"]["spends"])
        self.assertIn("error", acts["broken"])
        st, d = self.jreq("GET", f"/api/batch/{self.plain}")
        self.assertEqual([(a["id"], a["builtin"]) for a in d["actions"]], [("install", True)])

    # -- runs
    def test_run_streams_output_and_exit_status(self):
        info, out, _ = self.run_to_end(self.name, "install", {"--lines": 5})
        self.assertEqual(info["status"], "ok")
        self.assertEqual(info["code"], 0)
        self.assertIn(f"$ python3 {script_rel()} --install --lines 5", out)
        lines = [ln for ln in out.splitlines() if ln.startswith("line ")]
        self.assertEqual(lines, [f"line {i}" for i in range(1, 6)])
        self.assertIn("argv: --install --lines 5", out)
        self.assertGreater(info["elapsed"], 0.2)
        # a failing one
        info, out, _ = self.run_to_end(self.name, "install", {"--lines": 1, "--fail": True})
        self.assertEqual((info["status"], info["code"]), ("failed", 1))
        # both landed in runs.log with a header
        log = (R.REVIEW / self.name / "runs.log").read_text()
        self.assertIn("=====", log)
        self.assertIn("line 5", log)
        self.assertIn("[failed · exit 1", log)
        # and the run list shows newest first
        st, d = self.jreq("GET", f"/api/runs?batch={self.name}")
        self.assertEqual(d["runs"][0]["code"], 1)
        # reading from an offset gives just the rest
        rid = d["runs"][0]["id"]
        st, full = self.jreq("GET", f"/api/run/{rid}?from=0")
        st, tail = self.jreq("GET", f"/api/run/{rid}?from=10")
        self.assertEqual(tail["output"], full["output"][10:])

    def test_bad_run_requests(self):
        st, d = self.jreq("POST", "/api/run", {"batch": self.name, "action": "install", "options": {"--evil": 1}})
        self.assertEqual(st, 400)
        st, d = self.jreq("POST", "/api/run", {"batch": self.name, "action": "install", "options": {"--lines": 99}})
        self.assertEqual(st, 400)
        st, d = self.jreq("POST", "/api/run", {"batch": self.name, "action": "broken"})
        self.assertEqual(st, 400)
        st, d = self.jreq("POST", "/api/run", {"batch": self.name, "action": "nope"})
        self.assertEqual(st, 404)
        # the browser can't send a command
        st, d = self.jreq("POST", "/api/run", {"batch": self.name, "action": "install", "cmd": ["bash"]})
        self.assertEqual(st, 200)  # extra keys are ignored: it ran the declared one
        R._RUNS[d["run"]["id"]].done.wait(10)
        self.assertEqual(R._RUNS[d["run"]["id"]].argv[1], str((R.REPO / script_rel()).resolve()))
        st, d = self.jreq("GET", "/api/run/doesnotexist")
        self.assertEqual(st, 404)

    def test_one_run_per_batch_and_cancel(self):
        st, d = self.jreq("POST", "/api/run", {"batch": self.name, "action": "forever"})
        self.assertEqual(st, 200, d)
        rid = d["run"]["id"]
        try:
            # wait for the child to exist
            t0, out = time.time(), ""
            while "child" not in out and time.time() - t0 < 10:
                out = self.jreq("GET", f"/api/run/{rid}?from=0")[1]["output"]
                time.sleep(0.05)
            child = int(out.split("child ")[1].split()[0])
            st, d = self.jreq("POST", "/api/run", {"batch": self.name, "action": "install"})
            self.assertEqual(st, 409)
            self.assertIn("still running", d["error"])
        finally:
            st, d = self.jreq("POST", f"/api/run/{rid}/cancel", {})
        self.assertEqual(st, 200)
        self.assertTrue(R._RUNS[rid].done.wait(10))
        st, info = self.jreq("GET", f"/api/run/{rid}?from=0")
        self.assertEqual(info["status"], "cancelled")
        self.assertIn("tick", info["output"])
        # the script's own child went down with it (give launchd a moment to reap it)
        for _ in range(50):
            try:
                os.kill(child, 0)
            except ProcessLookupError:
                break
            time.sleep(0.1)
        else:
            os.kill(child, 9)
            self.fail("the run's child process outlived the cancel")

    def test_regen_writes_rejected_first(self):
        (R.REVIEW / self.name / "rejected.json").unlink(missing_ok=True)
        info, out, _ = self.run_to_end(self.name, "regen")
        self.assertEqual(info["status"], "ok", out)
        self.assertIn("1 to re-roll", out)
        self.assertIn('"too dark"', out)  # the script read the fresh rejected.json

    def test_builtin_apply_for_a_batch_without_actions(self):
        target = R.REVIEW / self.plain / "out" / "crest.png"
        info, out, _ = self.run_to_end(self.plain, "install", {"--dry-run": True})
        self.assertEqual(info["status"], "ok", out)
        self.assertIn("apply", info["cmd"])
        self.assertIn("[dry-run]", out)
        self.assertFalse(target.exists())
        info, out, _ = self.run_to_end(self.plain, "install", {})
        self.assertEqual(info["status"], "ok", out)
        self.assertIn("copied 1", out)
        self.assertTrue(target.is_file())
        st, d = self.jreq("POST", "/api/run", {"batch": self.plain, "action": "regen"})
        self.assertEqual(st, 404)  # no regen without a generator

    def test_install_marks_accepted_takes_in_game(self):
        def crest():
            st, d = self.jreq("GET", f"/api/batch/{self.plain}")
            return next(it for it in d["items"] if it["id"] == "crest")
        R.decide(self.plain, "crest", verdict="accept")
        d = R.REVIEW / self.plain
        rv = R.load_review(d)
        rv["items"]["crest"].pop("installed", None)  # an earlier test may have installed it
        R.atomic_write_json(d / "review.json", rv)
        info, out, _ = self.run_to_end(self.plain, "install", {"--dry-run": True})
        self.assertEqual(info["status"], "ok", out)
        self.assertFalse(crest()["installed"], "a dry run installs nothing")
        info, out, _ = self.run_to_end(self.plain, "install", {})
        self.assertEqual(info["status"], "ok", out)
        self.assertIn("marked in game", out)
        it = crest()
        self.assertTrue(it["installed"] and it["status"] == "accept" and it["installed_at"])
        self.assertEqual(R.summarize(R.merged_batch(self.plain)["items"])["installed"], 1)
        # a new take on the same file is no longer the one in the game
        f = R.REVIEW / self.plain / "crest.png"
        t = time.time() + 5
        os.utime(f, (t, t))
        it = crest()
        self.assertFalse(it["installed"])
        self.assertEqual(it["status"], "pending")
        R.decide(self.plain, "crest", verdict="accept")
        self.assertFalse(crest()["installed"], "accepted again, but not installed yet")

    # -- video
    def test_video_items_and_companions(self):
        st, d = self.jreq("GET", f"/api/batch/{self.name}")
        items = {it["id"]: it for it in d["items"]}
        self.assertEqual(items["clip"]["kind"], "video")
        self.assertTrue(items["clip"]["poster_url"].startswith(f"/media/{self.name}/poster.png?v="))
        self.assertEqual(items["clip2"]["kind"], "video")  # inferred from .webm
        self.assertEqual(items["gif"]["video_file"], "clip.mp4")
        self.assertEqual(items["gif2"]["video_file"], "clip.mov")  # given relative to the repo
        self.assertEqual(items["still"]["video_file"], "still.m4v")  # x_poster.png -> x.m4v
        self.assertNotIn("video_url", items["nope"])  # outside the batch folder: ignored
        self.assertNotIn("video_url", items["clip"])

    def test_video_mime_and_range(self):
        for f, ctype in (("clip.mp4", "video/mp4"), ("clip.webm", "video/webm"), ("clip.mov", "video/quicktime"),
                         ("still.m4v", "video/mp4"), ("clip.ogv", "video/ogg")):
            with self.subTest(f=f):
                st, h, body = self.req("GET", f"/media/{self.name}/{f}")
                self.assertEqual(st, 200)
                self.assertEqual(h["Content-Type"], ctype)
                self.assertEqual(h["Accept-Ranges"], "bytes")
                self.assertEqual(body, self.video)
        n = len(self.video)
        st, h, body = self.req("GET", f"/media/{self.name}/clip.mp4", headers={"Range": "bytes=0-1"})
        self.assertEqual((st, body, h["Content-Range"]), (206, self.video[:2], f"bytes 0-1/{n}"))
        st, h, body = self.req("GET", f"/media/{self.name}/clip.mp4", headers={"Range": "bytes=1000-"})
        self.assertEqual((st, body), (206, self.video[1000:]))
        st, h, body = self.req("GET", f"/media/{self.name}/clip.mp4", headers={"Range": "bytes=-100"})
        self.assertEqual((st, body, h["Content-Range"]), (206, self.video[-100:], f"bytes {n - 100}-{n - 1}/{n}"))
        st, h, body = self.req("GET", f"/media/{self.name}/clip.mp4", headers={"Range": f"bytes={n}-"})
        self.assertEqual(st, 416)
        st, h, body = self.req("HEAD", f"/media/{self.name}/clip.mp4", headers={"Range": "bytes=0-99"})
        self.assertEqual((st, h["Content-Length"], body), (206, "100", b""))


class TakesTests(unittest.TestCase):
    """v1.11: several takes of an item, the pick, what the game has now, and the lessons."""

    @classmethod
    def setUpClass(cls):
        R.ensure_review_root()
        cls.name = TAG + "_takes"
        out = f"review/{cls.name}/out"
        cls.files = {"a/line.mp3": b"MAIN" * 50, "a/.takes/line.t2.mp3": b"TWO!" * 50, "a/.takes/line.t3.mp3": b"THRE" * 50,
                     "a/.takes/line.r1.mp3": b"OLD1" * 50, "a/.takes/line.r2.mp3": b"OLD2" * 50,
                     "a/.takes/other.t2.mp3": b"NOPE" * 50, "a/solo.mp3": b"SOLO" * 50,
                     "out/solo.mp3": b"GAME" * 50, "out/secret.json": b"{}", "out/.hidden.mp3": b"HIDE"}
        make_batch(cls.name, {"title": "takes", "items": [
            {"id": "line", "kind": "audio", "file": "a/line.mp3", "target": f"{out}/line.mp3", "group": "varek"},
            {"id": "solo", "kind": "audio", "file": "a/solo.mp3", "target": f"{out}/solo.mp3", "group": "varek"},
            {"id": "json", "kind": "audio", "file": "a/solo.mp3", "target": f"{out}/secret.json"},
            {"id": "dot", "kind": "audio", "file": "a/solo.mp3", "target": f"{out}/.hidden.mp3"},
        ]}, cls.files)
        cls.httpd = R.Server(("127.0.0.1", 0), R.Handler)
        cls.base = f"http://127.0.0.1:{cls.httpd.server_address[1]}"
        threading.Thread(target=cls.httpd.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.httpd.shutdown()
        cls.httpd.server_close()
        shutil.rmtree(R.REVIEW / cls.name, ignore_errors=True)

    def item(self, iid):
        return {it["id"]: it for it in R.merged_batch(self.name)["items"]}[iid]

    def get(self, path):
        try:
            with urllib.request.urlopen(self.base + path, timeout=10) as r:
                return r.status, r.read()
        except urllib.error.HTTPError as e:
            with e:
                return e.code, e.read()

    def test_takes_found_beside_the_file(self):
        it = self.item("line")
        self.assertEqual([t["file"] for t in it["takes"]],
                         ["a/line.mp3", "a/.takes/line.t2.mp3", "a/.takes/line.t3.mp3", "a/.takes/line.r2.mp3", "a/.takes/line.r1.mp3"])
        self.assertEqual([t["label"] for t in it["takes"]][:3], ["take 1", "take 2", "take 3"])
        self.assertTrue(it["takes"][3]["label"].startswith("rejected"))
        self.assertTrue(it["takes"][0]["picked"], "nothing picked yet: the item's own file")
        self.assertNotIn("takes", self.item("solo"), "one file, no takes strip")

    def test_accepting_a_take_picks_it_and_install_uses_it(self):
        R.decide(self.name, "line", verdict="accept", take="a/.takes/line.t3.mp3")
        it = self.item("line")
        self.assertEqual((it["status"], it["pick"], it["src"]), ("accept", "a/.takes/line.t3.mp3", "a/.takes/line.t3.mp3"))
        self.assertIn(".takes/line.t3.mp3", it["url"])
        self.assertEqual([t["picked"] for t in it["takes"]], [False, False, True, False, False])
        with self.assertRaises(R.ReviewError):
            R.decide(self.name, "line", verdict="accept", take="a/.takes/other.t2.mp3")
        R.cmd_apply(type("A", (), {"batch": self.name, "dry_run": False})())
        game = R.REVIEW / self.name / "out" / "line.mp3"
        self.assertEqual(game.read_bytes(), self.files["a/.takes/line.t3.mp3"], "install copies the pick")
        self.assertEqual(R.reconcile(self.name), 1)
        self.assertTrue(self.item("line")["installed"])
        self.assertTrue(self.item("line")["game_same"])
        ## rejecting drops the pick: a redo re-rolls the line
        R.decide(self.name, "line", verdict="reject")
        it = self.item("line")
        self.assertIsNone(it["pick"])
        self.assertEqual(it["src"], "a/line.mp3")
        R.decide(self.name, "line", verdict="accept")
        self.assertIsNone(self.item("line")["pick"], "accepting take 1 records no pick")

    def test_the_game_copy_is_served_only_for_media(self):
        it = self.item("solo")
        self.assertTrue(it["game_url"].startswith(f"/game/{self.name}/solo?v="))
        self.assertFalse(it["game_same"])
        st, body = self.get(f"/game/{self.name}/solo")
        self.assertEqual((st, body), (200, self.files["out/solo.mp3"]))
        for iid in ("json", "dot"):
            with self.subTest(iid=iid):
                self.assertNotIn("game_url", self.item(iid))
                self.assertEqual(self.get(f"/game/{self.name}/{iid}")[0], 404)
        self.assertEqual(self.get(f"/game/{self.name}/nosuch")[0], 404)

    def test_note_themes_and_lessons(self):
        cases = {
            "More pause between the sentences": {"pause"},
            "Inflection is wrong - should be downwards. *always* should be emphasized": {"fall", "stress"},
            "Needs more pause/spacing between the sentences.": {"pause"},
            "make it sound like she's a smug asshole": {"feeling"},
            "Redo": {"redo"},
            "Last few blips of 'regiments' is cut off": {"clipped"},
        }
        for note, want in cases.items():
            with self.subTest(note=note):
                self.assertEqual(set(R.note_themes(note, "audio")), want)
        self.assertEqual(R.note_themes("Cuts out the sides", "image"), ["framing"])
        R.decide(self.name, "solo", verdict="reject", note="More pause between sentences")
        ls = R.lessons([self.name])  ## only this batch: a fresh clone has no others (B-004)
        pause = next(t for t in ls["themes"] if t["theme"] == "pause")
        self.assertEqual((pause["notes"], pause["open"]), (1, 1))
        self.assertEqual(ls["batches"], 1)
        self.assertGreaterEqual(ls["kinds"]["audio"]["open"], 1)
        self.assertNotIn(self.name, [e["batch"] for t in R.lessons()["themes"] for e in t["examples"]],
                         "a normal run skips test and demo batches")
        md = R.lessons_markdown(ls)
        self.assertTrue(md.startswith(R.LESSONS_BEGIN) and md.endswith(R.LESSONS_END))
        R.decide(self.name, "solo", verdict="pending", note="")


def png_bytes(size: int = 16) -> bytes:
    """A tiny valid PNG, made by the tool's own sample-image writer."""
    tmp = R.REVIEW / TAG / "_png.png"
    R._write_png(tmp, size)
    blob = tmp.read_bytes()
    tmp.unlink()
    return blob


class ConceptTests(unittest.TestCase):
    """Concept mode: Good / Good with changes / Bad, stored as accept / revise / reject."""

    @classmethod
    def setUpClass(cls):
        R.ensure_review_root()
        cls.name = TAG + "_concept"
        cls.png = png_bytes()
        cls.files = {"a.png": cls.png + b"a", "b.png": cls.png + b"b", "c.png": cls.png + b"c", "d.png": cls.png + b"d"}
        make_batch(cls.name, {"title": "concept", "mode": "concept", "items": [
            {"id": "a", "file": "a.png", "group": "ember", "text": "prompt a", "target": f"review/{cls.name}/out/a.png"},
            {"id": "b", "file": "b.png", "group": "ember", "text": "prompt b", "target": f"review/{cls.name}/out/b.png"},
            {"id": "c", "file": "c.png", "group": "veil", "text": "prompt c", "target": f"review/{cls.name}/out/c.png"},
            {"id": "d", "file": "d.png", "group": "veil", "text": "prompt d"},
            {"id": "gone", "file": "gone.png", "group": "veil"},
        ]}, cls.files)
        cls.std = TAG + "_std"
        make_batch(cls.std, {"title": "standard", "items": [{"id": "s", "file": "s.png"}]}, {"s.png": cls.png})
        cls.httpd = R.Server(("127.0.0.1", 0), R.Handler)
        cls.base = f"http://127.0.0.1:{cls.httpd.server_address[1]}"
        threading.Thread(target=cls.httpd.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.httpd.shutdown()
        cls.httpd.server_close()
        for n in (cls.name, cls.std):
            shutil.rmtree(R.REVIEW / n, ignore_errors=True)

    def setUp(self):
        # every test starts from a clean slate: no verdicts, the original files
        for n, fs in ((self.name, self.files), (self.std, {"s.png": self.png})):
            d = R.REVIEW / n
            (d / "review.json").unlink(missing_ok=True)
            for rel, blob in fs.items():
                (d / rel).write_bytes(blob)
                os.utime(d / rel, (1_700_000_000, 1_700_000_000))

    def item(self, iid):
        return {it["id"]: it for it in R.merged_batch(self.name)["items"]}[iid]

    def post(self, body):
        rq = urllib.request.Request(self.base + "/api/decide", data=json.dumps(body).encode(), method="POST",
                                    headers={"Content-Type": "application/json", "X-Review-Token": self.httpd.token})
        try:
            with urllib.request.urlopen(rq, timeout=10) as r:
                return r.status, json.loads(r.read())
        except urllib.error.HTTPError as e:
            with e:
                return e.code, json.loads(e.read())

    def test_mode_is_reported_and_validated(self):
        self.assertEqual(R.merged_batch(self.name)["mode"], "concept")
        self.assertEqual(R.merged_batch(self.std)["mode"], "standard")
        bad = make_batch(TAG + "_badmode", {"mode": "concepts", "items": []})
        try:
            with self.assertRaises(R.ReviewError):
                R.merged_batch(TAG + "_badmode")
        finally:
            shutil.rmtree(bad, ignore_errors=True)

    def test_revise_needs_a_note(self):
        with self.assertRaises(R.ReviewError) as cm:
            R.decide(self.name, "a", verdict="revise")
        self.assertEqual(cm.exception.status, 400)
        with self.assertRaises(R.ReviewError):
            R.decide(self.name, "a", verdict="revise", note="   ")
        self.assertEqual(self.item("a")["status"], "pending", "a refused verdict changes nothing")
        # over HTTP: 400 without the note, 200 with it
        st, d = self.post({"batch": self.name, "id": "a", "verdict": "revise"})
        self.assertEqual(st, 400)
        self.assertIn("note", d["error"])
        st, d = self.post({"batch": self.name, "id": "a", "verdict": "revise", "note": "Wrong palette"})
        self.assertEqual(st, 200)
        self.assertEqual((d["item"]["status"], d["item"]["note"]), ("revise", "Wrong palette"))
        # the note can't be emptied while the verdict stands; clearing the verdict frees it
        with self.assertRaises(R.ReviewError):
            R.decide(self.name, "a", note="")
        self.assertEqual(self.item("a")["note"], "Wrong palette")
        R.decide(self.name, "a", verdict="pending")
        self.assertEqual(self.item("a")["note"], "Wrong palette", "the note stays when the verdict is cleared")
        R.decide(self.name, "a", note="")

    def test_revise_only_in_concept_batches(self):
        with self.assertRaises(R.ReviewError):
            R.decide(self.std, "s", verdict="revise", note="change it")
        R.decide(self.std, "s", verdict="accept")  # accept and reject are unchanged
        R.decide(self.std, "s", verdict="pending")

    def test_revise_counts_as_kept(self):
        R.decide(self.name, "a", verdict="accept")
        R.decide(self.name, "b", verdict="revise", note="Keep the silhouette, change the detail")
        R.decide(self.name, "c", verdict="reject", note="Text in the image")
        c = R.summarize(R.merged_batch(self.name)["items"])
        self.assertEqual((c["accept"], c["revise"], c["reject"], c["pending"], c["missing"]), (1, 1, 1, 1, 1))
        self.assertEqual(c["reviewed"], 3)
        self.assertEqual(self.item("b")["verdict"], "revise")
        self.assertEqual(self.item("b")["note"], "Keep the silhouette, change the detail")
        # a regenerated file puts it back in the queue; the old call and note stay visible
        f = R.REVIEW / self.name / "b.png"
        t = time.time() + 5
        os.utime(f, (t, t))
        it = self.item("b")
        self.assertEqual((it["status"], it["regenerated"], it["note"]), ("pending", True, "Keep the silhouette, change the detail"))
        R.decide(self.name, "b", verdict="revise", note="Better, now the colours")
        it = self.item("b")
        self.assertEqual((it["status"], it["note"]), ("revise", "Better, now the colours"))
        self.assertEqual(it["history"][-1]["verdict"], "revise")

    def test_rejected_json_carries_the_revise_items(self):
        R.decide(self.name, "a", verdict="accept")
        R.decide(self.name, "b", verdict="revise", note="More like this, but warmer")
        R.decide(self.name, "c", verdict="reject", note="Text in the image")
        path, n = R.write_rejected(self.name)
        rows = {e["id"]: e for e in json.loads(path.read_text())}
        self.assertEqual(n, 2)
        self.assertEqual(set(rows), {"b", "c"})
        self.assertEqual((rows["b"]["verdict"], rows["b"]["note"], rows["b"]["text"]), ("revise", "More like this, but warmer", "prompt b"))
        self.assertEqual((rows["c"]["verdict"], rows["c"]["group"]), ("reject", "veil"))
        # a standard batch's list is what it always was: rejects only, no verdict key
        R.decide(self.std, "s", verdict="reject", note="no")
        path, n = R.write_rejected(self.std)
        self.assertEqual([set(e) for e in json.loads(path.read_text())], [{"id", "text", "note", "meta"}])

    def test_apply_copies_the_kept_items_to_their_targets(self):
        R.decide(self.name, "a", verdict="accept")
        R.decide(self.name, "b", verdict="revise", note="Warmer")
        R.decide(self.name, "c", verdict="reject")
        out = R.REVIEW / self.name / "out"
        shutil.rmtree(out, ignore_errors=True)
        R.cmd_apply(type("A", (), {"batch": self.name, "dry_run": False})())
        self.assertEqual(sorted(p.name for p in out.iterdir()), ["a.png", "b.png"], "Good and Good with changes are kept")

    def test_art_chips_sort_into_themes(self):
        cases = {
            "More like this": {"more_like"},
            "Wrong palette": {"palette"},
            "Reads like another faction": {"faction"},
            "Text in the image": {"text_in_image"},
            "Not a lookalike of Atlas Gaming's knight": {"lookalike"},
            "Keep the silhouette, change the detail": {"silhouette"},
            "Wrong palette, Text in the image": {"palette", "text_in_image"},
        }
        for note, want in cases.items():
            with self.subTest(note=note):
                self.assertEqual(set(R.note_themes(note, "image")), want)
        self.assertEqual(R.note_themes("Wrong palette", "audio"), [], "the art themes are for pictures")

    def test_lessons_count_revise(self):
        R.decide(self.name, "a", verdict="accept")
        R.decide(self.name, "b", verdict="revise", note="Wrong palette")
        R.decide(self.name, "c", verdict="reject", note="Text in the image")
        ls = R.lessons([self.name])
        img = ls["kinds"]["image"]
        self.assertEqual((img["decided"], img["first_take"], img["revise"], img["open"]), (3, 1, 1, 1))
        th = {t["theme"]: t for t in ls["themes"]}
        self.assertEqual((th["palette"]["notes"], th["palette"]["open"]), (1, 1), "a revise note is still open")
        self.assertEqual((th["text_in_image"]["notes"], th["text_in_image"]["open"]), (1, 1))
        self.assertIn("good with changes", R.lessons_markdown(ls))

    def test_new_scaffolds_a_concept_batch(self):
        name = TAG + "_new"
        try:
            R.cmd_new(type("A", (), {"batch": name, "title": "New concepts", "mode": "concept"})())
            self.assertEqual(R.load_batch(name)[1]["mode"], "concept")
        finally:
            shutil.rmtree(R.REVIEW / name, ignore_errors=True)


class SeatTests(unittest.TestCase):
    """Takes from several art seats (claude, codex, grok), and the per-seat tally in lessons."""

    @classmethod
    def setUpClass(cls):
        R.ensure_review_root()
        cls.name = TAG + "_seats"
        png = png_bytes()
        names = ["a_codex", "a_grok", "b_codex", "b_grok", "c_codex", "c_grok", "c_claude", "d_claude", "e_none"]
        cls.files = {f"{n.split('_')[1]}/{n}.png": png + n.encode() for n in names}
        f = lambda n: f"{n.split('_')[1]}/{n}.png"
        make_batch(cls.name, {"title": "seats", "mode": "concept", "items": [
            {"id": "a", "file": f("a_codex"), "seat": "codex", "takes": [{"file": f("a_grok"), "label": "take 2", "seat": "grok"}]},
            {"id": "b", "file": f("b_codex"), "seat": "Codex ", "text": "prompt b",
             "takes": [{"file": f("b_grok"), "seat": "grok"}]},
            {"id": "c", "file": f("c_codex"), "seat": "codex",
             "takes": [{"file": f("c_grok"), "seat": "grok"}, {"file": f("c_claude"), "seat": "claude"}]},
            {"id": "d", "file": f("d_claude"), "seat": "claude"},
            {"id": "e", "file": f("e_none")},
            {"id": "odd", "file": f("e_none"), "seat": "not a seat!", "takes": [{"file": f("a_grok"), "seat": 7}]},
        ]}, cls.files)
        cls.f = staticmethod(f)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(R.REVIEW / cls.name, ignore_errors=True)

    def setUp(self):
        (R.REVIEW / self.name / "review.json").unlink(missing_ok=True)

    def item(self, iid):
        return {it["id"]: it for it in R.merged_batch(self.name)["items"]}[iid]

    def test_seats_are_cleaned(self):
        self.assertEqual([R.clean_seat(x) for x in ("codex", " Grok ", "claude", "x" * 40, "not a seat!", "", None, 7)],
                         ["codex", "grok", "claude", None, None, None, None, None])
        self.assertEqual(self.item("b")["takes"][0]["seat"], "codex", "case and spaces are tidied")
        odd = self.item("odd")
        self.assertEqual([t["seat"] for t in odd["takes"]], [None, None], "a seat that is not a plain name is dropped")

    def test_takes_carry_their_seat(self):
        it = self.item("c")
        self.assertEqual([(t["file"], t["seat"]) for t in it["takes"]],
                         [(self.f("c_codex"), "codex"), (self.f("c_grok"), "grok"), (self.f("c_claude"), "claude")])
        self.assertEqual(it["seat"], "codex", "nothing picked: the item's own take")
        R.decide(self.name, "c", verdict="accept", take=self.f("c_claude"))
        it = self.item("c")
        self.assertEqual((it["seat"], it["pick"]), ("claude", self.f("c_claude")), "the seat follows the take that was kept")
        self.assertEqual([t["picked"] for t in it["takes"]], [False, False, True])
        self.assertEqual(self.item("d")["seat"], "claude", "a single take carries the item's seat")
        self.assertNotIn("takes", self.item("d"))
        self.assertIsNone(self.item("e")["seat"])

    def test_the_tally_by_seat(self):
        R.decide(self.name, "a", verdict="accept", take=self.f("a_grok"))                 # grok wins, codex passed over
        R.decide(self.name, "b", verdict="revise", note="Wrong palette")                  # codex (own take) wins with changes
        R.decide(self.name, "c", verdict="reject", note="Text in the image")              # all three seats: bad
        R.decide(self.name, "d", verdict="accept")                                        # claude, single take
        R.decide(self.name, "e", verdict="accept")                                        # no seat: not counted
        seats = R.lessons([self.name])["seats"]
        self.assertEqual(seats["codex"], {"good": 0, "revise": 1, "bad": 1, "passed": 1, "items": 3})
        self.assertEqual(seats["grok"], {"good": 1, "revise": 0, "bad": 1, "passed": 1, "items": 3})
        self.assertEqual(seats["claude"], {"good": 1, "revise": 0, "bad": 1, "passed": 0, "items": 2})
        self.assertEqual(set(seats), {"codex", "grok", "claude"})
        md = R.lessons_markdown(R.lessons([self.name]))
        self.assertIn("| seat | good | good with changes | bad | passed over |", md)
        self.assertIn("| grok | 1 | 0 | 1 | 1 |", md)

    def test_no_seats_no_tally(self):
        R.decide(self.name, "e", verdict="accept")
        self.assertEqual(R.lessons([self.name])["seats"], {})
        self.assertNotIn("| seat |", R.lessons_markdown(R.lessons([self.name])))

    def test_the_sample_concept_batch_has_takes_from_three_seats(self):
        d = R.REVIEW / (TAG + "_sample")
        R._build_sample_concept(d)
        mb = R.merged_batch(d.name)
        self.assertEqual(mb["mode"], "concept")
        seats = {t["seat"] for it in mb["items"] for t in (it.get("takes") or [it])}
        self.assertEqual(seats, {"claude", "codex", "grok"})
        self.assertTrue(all(it["exists"] for it in mb["items"]))
        self.assertTrue(all(it["group"].startswith("sample_") for it in mb["items"]), "canon groups that are easy to tell")

    def test_rejected_json_names_the_take_and_its_seat(self):
        R.decide(self.name, "a", verdict="revise", note="Keep the silhouette, change the detail", take=self.f("a_grok"))
        R.decide(self.name, "c", verdict="reject")
        path, n = R.write_rejected(self.name)
        rows = {e["id"]: e for e in json.loads(path.read_text())}
        self.assertEqual((rows["a"]["verdict"], rows["a"]["file"], rows["a"]["seat"]), ("revise", self.f("a_grok"), "grok"))
        self.assertEqual([t["seat"] for t in rows["a"]["takes"]], ["codex", "grok"])
        self.assertEqual(rows["c"]["verdict"], "reject")
        self.assertEqual([t["seat"] for t in rows["c"]["takes"]], ["codex", "grok", "claude"], "a redo knows every seat's take")


class ModelTests(unittest.TestCase):
    """3D models: kind, MIME types, "in game now", and the vendored viewer that works offline."""

    @classmethod
    def setUpClass(cls):
        R.ensure_review_root()
        cls.name = TAG + "_models"
        cls.glb = b"glTF\x02\x00\x00\x00" + bytes(range(256)) * 20      # not a real model: the server only serves it
        cls.game = b"glTF\x02\x00\x00\x00" + b"GAME" * 100
        out = f"review/{cls.name}/out"
        cls.files = {"king.glb": cls.glb, "scene.gltf": b'{"asset": {"version": "2.0"}}', "scene.bin": b"\x00\x01\x02\x03",
                     ".takes/king.t2.glb": cls.glb[::-1], "out/king.glb": cls.game, "out/same.glb": cls.glb, "same.glb": cls.glb,
                     "out/notes.json": b"{}"}
        make_batch(cls.name, {"title": "models", "items": [
            {"id": "king", "file": "king.glb", "group": "rulers", "target": f"{out}/king.glb"},
            {"id": "scene", "file": "scene.gltf", "kind": "model"},
            {"id": "same", "file": "same.glb", "target": f"{out}/same.glb"},
            {"id": "typed", "file": "king.glb", "kind": "model", "target": f"{out}/notes.json"},
            {"id": "nofile", "file": "gone.glb", "kind": "model"},
        ]}, cls.files)
        cls.httpd = R.Server(("127.0.0.1", 0), R.Handler)
        cls.base = f"http://127.0.0.1:{cls.httpd.server_address[1]}"
        threading.Thread(target=cls.httpd.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.httpd.shutdown()
        cls.httpd.server_close()
        shutil.rmtree(R.REVIEW / cls.name, ignore_errors=True)

    def item(self, iid):
        return {it["id"]: it for it in R.merged_batch(self.name)["items"]}[iid]

    def get(self, path, headers=None, method="GET"):
        rq = urllib.request.Request(self.base + path, method=method, headers=headers or {})
        try:
            with urllib.request.urlopen(rq, timeout=10) as r:
                return r.status, dict(r.headers), r.read()
        except urllib.error.HTTPError as e:
            with e:
                return e.code, dict(e.headers), e.read()

    def test_kind_is_guessed_from_the_extension(self):
        self.assertEqual(R.item_kind({"file": "a/king.glb"}), "model")
        self.assertEqual(R.item_kind({"file": "a/KING.GLTF"}), "model")
        self.assertEqual(R.item_kind({"file": "a/king.glb", "kind": "audio"}), "audio", "an explicit kind wins")
        self.assertEqual(R.item_kind({"file": "a/king.png"}), "image")
        self.assertEqual(self.item("king")["kind"], "model")
        self.assertEqual(self.item("scene")["kind"], "model")

    def test_models_are_served_with_their_type_and_ranges(self):
        for f, ctype in (("king.glb", "model/gltf-binary"), ("scene.gltf", "model/gltf+json"), ("scene.bin", "application/octet-stream")):
            with self.subTest(f=f):
                st, h, body = self.get(f"/media/{self.name}/{f}")
                self.assertEqual((st, h["Content-Type"]), (200, ctype))
                self.assertEqual(body, self.files[f])
        st, h, body = self.get(f"/media/{self.name}/king.glb", headers={"Range": "bytes=0-3"})
        self.assertEqual((st, body), (206, b"glTF"))

    def test_models_can_be_accepted_and_have_takes(self):
        self.assertEqual([t["file"] for t in self.item("king")["takes"]], ["king.glb", ".takes/king.t2.glb"],
                         "more rolls of a model sit in .takes/ like any other take")
        R.decide(self.name, "king", verdict="accept")
        it = self.item("king")
        self.assertEqual((it["status"], it["exists"], it["kind"]), ("accept", True, "model"))
        R.decide(self.name, "king", verdict="pending")
        self.assertFalse(self.item("nofile")["exists"])
        with self.assertRaises(R.ReviewError):
            R.decide(self.name, "nofile", verdict="accept")

    def test_in_game_now_works_for_models(self):
        it = self.item("king")
        self.assertTrue(it["game_url"].startswith(f"/game/{self.name}/king?v="))
        self.assertFalse(it["game_same"], "the game has a different model")
        st, h, body = self.get(f"/game/{self.name}/king")
        self.assertEqual((st, h["Content-Type"], body), (200, "model/gltf-binary", self.game))
        self.assertTrue(self.item("same")["game_same"], "an identical model: no \"in game now\" button")
        self.assertNotIn("game_url", self.item("typed"), "only media files are served from the game, never a .json")
        self.assertNotIn("game_url", self.item("scene"))
        self.assertEqual(self.get(f"/game/{self.name}/typed")[0], 404)

    def test_the_viewer_is_vendored_and_served_locally(self):
        self.assertTrue((R.VENDOR / "model-viewer.min.js").is_file(), "tools/review/vendor/model-viewer.min.js is committed")
        readme = (R.VENDOR / "README.md").read_text()
        self.assertRegex(readme, r"model-viewer@\d+\.\d+\.\d+")
        self.assertIn("Apache", readme)
        self.assertTrue((R.VENDOR / "LICENSE-model-viewer").is_file())
        st, h, body = self.get("/vendor/model-viewer.min.js")
        self.assertEqual((st, h["Content-Type"]), (200, "text/javascript; charset=utf-8"))
        self.assertEqual(body, (R.VENDOR / "model-viewer.min.js").read_bytes())
        for bad in ("/vendor/", "/vendor/nope.js", "/vendor/LICENSE-model-viewer", "/vendor/README.md", "/vendor/..%2Freview.py",
                    "/vendor/%2e%2e/review.py", "/vendor/sub/x.js", "/vendor/.hidden.js"):
            with self.subTest(bad=bad):
                self.assertEqual(self.get(bad)[0], 404)

    def test_the_page_loads_nothing_from_a_cdn(self):
        st, h, body = self.get("/")
        html = body.decode()
        self.assertIn('src="/vendor/model-viewer.min.js"', html)
        for host in ("cdn.jsdelivr.net", "unpkg.com", "cdnjs.cloudflare.com", "gstatic.com", "googleapis.com"):
            self.assertNotIn(host, html)
        csp = h["Content-Security-Policy"]
        self.assertIn("default-src 'self'", csp)
        self.assertIn("frame-ancestors 'none'", csp)
        self.assertNotRegex(csp, r"https?:")

    def test_model_chips_sort_into_themes(self):
        cases = {
            "Doesn’t match the concept art": {"concept_match"},
            "Proportions are off": {"proportions"},
            "Texture is blurry or muddy": {"texture"},
            "Holes or broken geometry": {"geometry"},
            "Wrong pose": {"pose"},
        }
        for note, want in cases.items():
            with self.subTest(note=note):
                self.assertEqual(set(R.note_themes(note, "model")), want)
        self.assertEqual(R.note_themes("Wrong pose", "image"), [])
        R.decide(self.name, "king", verdict="reject", note="Holes or broken geometry")
        ls = R.lessons([self.name])
        self.assertEqual(ls["kinds"]["model"]["decided"], 1)
        self.assertEqual({t["theme"] for t in ls["themes"]}, {"geometry"})
        R.decide(self.name, "king", verdict="pending", note="")

    def test_the_sample_model_batch(self):
        d = R.REVIEW / (TAG + "_sample_models")
        R._build_sample_models(d)
        mb = R.merged_batch(d.name)
        self.assertGreaterEqual(len(mb["items"]), 1)
        self.assertTrue(all(it["kind"] == "model" and it["exists"] and "game_url" in it and not it["game_same"] for it in mb["items"]))
        self.assertTrue(all(it["target"].startswith("review/_sample_models/out/") for it in mb["items"]), "installing it touches nothing real")


class FromFolderTests(unittest.TestCase):
    """`review.py from-folder <dir> <batch>`: a folder an art round wrote into becomes a batch."""

    def setUp(self):
        self.src = Path(tempfile.mkdtemp(prefix="review_ff_"))
        self.name = TAG + "_ff"
        self.png = png_bytes()
        shutil.rmtree(R.REVIEW / self.name, ignore_errors=True)

    def tearDown(self):
        shutil.rmtree(self.src, ignore_errors=True)
        shutil.rmtree(R.REVIEW / self.name, ignore_errors=True)

    def put(self, rel, blob=None):
        p = self.src / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(blob if blob is not None else self.png + rel.encode())
        return p

    def run_ff(self, *args, name=None):
        out = io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(out):
            code = R.main(["from-folder", str(self.src), name or self.name, *args])
        return code, out.getvalue()

    def batch(self):
        return R.load_batch(self.name)[1]

    def test_a_folder_of_images_becomes_a_batch(self):
        for f in ("ember_orchard_ruler1.png", "ember_orchard_commander.png", "veiled_table_ruler1.png", "lone.png"):
            self.put(f)
        self.put("dossier.md", b"# notes")
        self.put(".hidden.png")
        (self.src / "prompts.json").write_text(json.dumps({
            "ember_orchard_ruler1.png": {"prompt": "a gardener queen", "seat": "Codex", "label": "Queen"},
            "veiled_table_ruler1.png": "a masked broker",
            "missing.png": {"prompt": "nothing here"}}))
        code, out = self.run_ff("--title", "Round 2", "--mode", "concept", "--group-by", "prefix")
        self.assertEqual(code, 0, out)
        self.assertIn("4 items (4 image)", out)
        self.assertIn("'missing.png' names no file", out, "a sidecar entry for no file is a warning")
        b = self.batch()
        self.assertEqual((b["title"], b["mode"]), ("Round 2", "concept"))
        items = {it["id"]: it for it in b["items"]}
        self.assertEqual(set(items), {"ember_orchard_ruler1", "ember_orchard_commander", "veiled_table_ruler1", "lone"})
        q = items["ember_orchard_ruler1"]
        self.assertEqual((q["kind"], q["group"], q["label"], q["text"], q["seat"], q["file"]),
                         ("image", "ember_orchard", "Queen", "a gardener queen", "codex", "ember_orchard_ruler1.png"))
        self.assertEqual((items["ember_orchard_commander"]["group"], items["ember_orchard_commander"]["label"]), ("ember_orchard", "commander"))
        self.assertEqual(items["veiled_table_ruler1"]["text"], "a masked broker", "a plain string is the prompt")
        self.assertNotIn("group", items["lone"], "no underscore, no prefix group")
        self.assertEqual(items["lone"]["label"], "lone")
        d = R.REVIEW / self.name
        self.assertEqual(sorted(p.name for p in d.glob("*.png")), sorted(f"{i}.png" for i in items))
        self.assertFalse((d / "dossier.md").exists() or (d / ".hidden.png").exists(), "only media is copied")
        mb = R.merged_batch(self.name)  # and it is a batch the table can open
        self.assertEqual(mb["mode"], "concept")
        self.assertTrue(all(it["exists"] for it in mb["items"]))

    def test_group_by_folder_and_seat_folders(self):
        self.put("codex/aurel.png")
        self.put("grok/fang.png")
        self.put("other/ever.png")
        code, out = self.run_ff("--group-by", "folder", "--recursive")
        self.assertEqual(code, 0, out)
        items = {it["id"]: it for it in self.batch()["items"]}
        self.assertEqual({k: (v["group"], v.get("seat")) for k, v in items.items()},
                         {"codex_aurel": ("codex", "codex"), "grok_fang": ("grok", "grok"), "other_ever": ("other", None)},
                         "a folder named after a seat says who made what is in it")
        self.assertEqual(items["codex_aurel"]["file"], "codex/aurel.png")
        self.assertTrue((R.REVIEW / self.name / "grok" / "fang.png").is_file())

    def test_a_folder_named_after_a_seat(self):
        seat_dir = self.src / "grok"
        seat_dir.mkdir()
        (seat_dir / "a_b.png").write_bytes(self.png)
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            R.main(["from-folder", str(seat_dir), self.name, "--mode", "concept"])
        self.assertEqual(self.batch()["items"][0]["seat"], "grok")

    def test_seat_takes_from_one_item(self):
        self.put("codex/aurel.png")
        self.put("grok/aurel.png")
        self.put("claude/aurel.png")
        self.put("codex/fang.png")
        (self.src / "prompts.json").write_text(json.dumps({
            "codex/aurel.png": {"item": "aurel", "prompt": "the Aurel crest", "group": "aurel", "label": "Aurel crest"},
            "grok/aurel.png": {"item": "aurel"}, "claude/aurel.png": {"item": "aurel"}}))
        code, out = self.run_ff("--mode", "concept", "--recursive")
        self.assertEqual(code, 0, out)
        self.assertIn("2 extra takes", out)
        items = {it["id"]: it for it in self.batch()["items"]}
        self.assertEqual(set(items), {"aurel", "codex_fang"})
        a = items["aurel"]
        self.assertEqual((a["file"], a["seat"], a["text"], a["group"], a["label"]),
                         ("claude/aurel.png", "claude", "the Aurel crest", "aurel", "Aurel crest"),
                         "its own file is the first by path; the sidecar entries of the others fill in what it lacks")
        self.assertEqual(sorted((a["seat"], *[t["seat"] for t in a["takes"]])), ["claude", "codex", "grok"])
        self.assertEqual([t["label"] for t in a["takes"]], ["take 2", "take 3"])
        merged = {it["id"]: it for it in R.merged_batch(self.name)["items"]}["aurel"]
        self.assertEqual(len(merged["takes"]), 3)
        self.assertTrue(all(t["exists"] for t in merged["takes"]))

    def test_models_and_install_targets(self):
        self.put("aurel_king_march.glb", b"glTF\x02\x00\x00\x00" + b"x" * 64)
        self.put("aurel_king_ready.glb", b"glTF\x02\x00\x00\x00" + b"y" * 64)
        code, out = self.run_ff("--group-by", "prefix", "--target-dir", "assets/models/rulers")
        self.assertEqual(code, 0, out)
        self.assertIn("2 model", out)
        items = {it["id"]: it for it in self.batch()["items"]}
        m = items["aurel_king_march"]
        self.assertEqual((m["kind"], m["group"], m["label"], m["target"]),
                         ("model", "aurel_king", "march", "assets/models/rulers/aurel_king_march.glb"))
        self.assertNotIn("mode", json.loads((R.REVIEW / self.name / "batch.json").read_text()), "standard is not written")
        mb = R.merged_batch(self.name)
        self.assertTrue(all(it["kind"] == "model" for it in mb["items"]))
        # a per-file target in the sidecar wins; one outside the repo is refused
        (self.src / "prompts.json").write_text(json.dumps({"aurel_king_march.glb": {"target": "assets/models/rulers/other.glb"}}))
        shutil.rmtree(R.REVIEW / self.name)
        self.assertEqual(self.run_ff("--target-dir", "assets/models/rulers")[0], 0)
        self.assertEqual({it["id"]: it["target"] for it in self.batch()["items"]}["aurel_king_march"], "assets/models/rulers/other.glb")
        shutil.rmtree(R.REVIEW / self.name)
        code, out = self.run_ff("--target-dir", "../outside")
        self.assertEqual(code, 2, out)
        self.assertIn("outside the repo", out)

    def test_a_gltf_brings_its_buffers_and_textures_and_they_are_not_items(self):
        self.put("scene.gltf", json.dumps({"asset": {"version": "2.0"}, "buffers": [{"uri": "scene.bin", "byteLength": 4}],
                                           "images": [{"uri": "tex/skin.png"}, {"uri": "data:image/png;base64,AAAA"}]}).encode())
        self.put("scene.bin", b"\x00\x01\x02\x03")
        self.put("tex/skin.png")
        self.put("other.png")
        code, out = self.run_ff("--recursive")
        self.assertEqual(code, 0, out)
        self.assertEqual(sorted(it["id"] for it in self.batch()["items"]), ["other", "scene"])
        d = R.REVIEW / self.name
        self.assertTrue((d / "scene.bin").is_file() and (d / "tex" / "skin.png").is_file(), "copied next to the .gltf")

    def test_it_will_not_overwrite_a_batch_but_can_add_to_it(self):
        self.put("a_one.png")
        self.assertEqual(self.run_ff("--title", "T")[0], 0)
        R.decide(self.name, "a_one", verdict="accept")
        code, out = self.run_ff()
        self.assertEqual(code, 2, out)
        self.assertIn("--add", out)
        self.put("a_two.png")
        self.put("sub/a_one.png")
        code, out = self.run_ff("--add", "--recursive")
        self.assertEqual(code, 0, out)
        b = self.batch()
        self.assertEqual(b["title"], "T", "the batch keeps its title")
        self.assertEqual(sorted(it["id"] for it in b["items"]), ["a_one", "a_two", "sub_a_one"])
        self.assertEqual(self.run_ff("--add")[1].count("nothing new"), 1, "running it again adds nothing")
        self.assertEqual(R.merged_batch(self.name)["items"][0]["status"], "accept", "verdicts are untouched")

    def test_a_folder_that_is_already_the_batch_is_not_copied(self):
        d = R.REVIEW / self.name
        d.mkdir(parents=True)
        (d / "x_y.png").write_bytes(self.png)
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            self.assertEqual(R.main(["from-folder", str(d), self.name, "--group-by", "prefix"]), 0)
        self.assertEqual([it["file"] for it in self.batch()["items"]], ["x_y.png"])
        self.assertNotIn("copied from", out.getvalue())

    def test_bad_input_is_refused_with_a_reason(self):
        self.assertEqual(self.run_ff()[0], 2, "an empty folder")
        self.put("notes.txt", b"hi")
        code, out = self.run_ff()
        self.assertEqual(code, 2, out)
        self.assertIn("no images", out)
        self.put("a.png")
        self.assertEqual(self.run_ff(name="bad name!")[0], 2)
        (self.src / "prompts.json").write_text("{not json")
        self.assertEqual(self.run_ff()[0], 2)
        code, out = self.run_ff(name=self.name)
        self.assertIn("not valid JSON", out)
        with contextlib.redirect_stderr(io.StringIO()) as err:
            code = R.main(["from-folder", str(self.src / "nope"), self.name])
        self.assertEqual(code, 2)
        self.assertIn("not a folder", err.getvalue())


if __name__ == "__main__":
    try:
        unittest.main(verbosity=2)
    finally:
        for stray in R.REVIEW.glob(TAG + "*"):  # the throwaway batches, whatever a failed test left behind
            shutil.rmtree(stray, ignore_errors=True)
