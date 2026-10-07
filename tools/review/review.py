#!/usr/bin/env python3
"""Accept/reject review tool for generated assets (voice lines, images, video).

Batches live in review/<batch>/ at the repo root:
    batch.json   written by a generator: the items to review, and the actions that finish it
    review.json  written by this tool: the verdicts
    rejected.json written by `apply` (and before a regen action runs): what a generator should re-roll
    runs.log     written by this tool: the output of every action run from the UI

Commands:
    serve  [--port 8766] [--open]   local web UI + JSON API on 127.0.0.1
    status [<batch>]                counts per verdict per group
    apply  <batch> [--dry-run]      copy accepted files to their targets, write rejected.json
    new    <batch> --title "..." [--mode concept]   scaffold an empty batch
    sample [--force]                build the review/_sample demo batch
    lessons [--write docs/PROMPTING.md]  what every review so far says about the prompts

Standard library only. See tools/review/README.md. The 3D viewer is Google's <model-viewer>, vendored
in tools/review/vendor/ and served from there, so the page works offline.
"""
from __future__ import annotations

import argparse
import codecs
import filecmp
import hmac
import json
import math
import os
import re
import secrets
import shlex
import shutil
import signal
import subprocess
import struct
import sys
import tempfile
import threading
import time
import wave
import webbrowser
import zlib
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, quote, unquote, urlsplit

TOOL_DIR = Path(__file__).resolve().parent
REPO = TOOL_DIR.parent.parent
REVIEW = REPO / "review"
INDEX_HTML = TOOL_DIR / "index.html"
VENDOR = TOOL_DIR / "vendor"   # the 3D viewer's script, served at /vendor/<file> (no CDN, works offline)
TOKEN_SLOT = "__REVIEW_TOKEN__"  # index.html carries this; the server swaps in its token

VERDICTS = ("accept", "revise", "reject", "pending")
KEPT = ("accept", "revise")  # revise (Good with changes, concept mode) counts as kept, and its note travels with it
MODES = ("standard", "concept")  # batch.json "mode": concept batches are judged Good / Good with changes / Bad
BATCH_RE = re.compile(r"^[A-Za-z0-9_][A-Za-z0-9_.-]*$")
MTIME_EPS = 0.001  # slack for float round-trips through JSON
HISTORY_KEEP = 10

IMAGE_EXTS = (".png", ".webp", ".jpg", ".jpeg", ".gif", ".svg")
VIDEO_EXTS = (".mp4", ".webm", ".mov", ".m4v", ".ogv")
MODEL_EXTS = (".glb", ".gltf")  # 3D models, shown in an orbit viewer
## where a generator may point at the clip behind an image item (a GIF, a poster frame)
VIDEO_META_KEYS = ("video", "video_mp4", "video_webm", "video_mov")

CONTENT_TYPES = {
    ".mp3": "audio/mpeg", ".wav": "audio/wav", ".ogg": "audio/ogg", ".oga": "audio/ogg",
    ".opus": "audio/ogg", ".m4a": "audio/mp4", ".flac": "audio/flac",
    ".png": "image/png", ".webp": "image/webp", ".jpg": "image/jpeg", ".jpeg": "image/jpeg",
    ".gif": "image/gif", ".svg": "image/svg+xml", ".json": "application/json",
    ".mp4": "video/mp4", ".m4v": "video/mp4", ".webm": "video/webm", ".mov": "video/quicktime",
    ".ogv": "video/ogg",
    ".glb": "model/gltf-binary", ".gltf": "model/gltf+json",
    ".bin": "application/octet-stream",  # a .gltf's buffer, fetched by the viewer next to it
}
## what /vendor/ serves: the viewer's script, and nothing else
VENDOR_TYPES = {".js": "text/javascript; charset=utf-8"}
VENDOR_NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]*$")
## The page loads nothing from outside this server (the 3D viewer is vendored, no CDN) and may not be framed.
## 'wasm-unsafe-eval' lets the viewer compile its bundled Meshopt decoder; it does not allow eval() of text.
PAGE_CSP = ("default-src 'self'; script-src 'self' 'unsafe-inline' 'wasm-unsafe-eval'; style-src 'self' 'unsafe-inline'; "
            "img-src 'self' data: blob:; media-src 'self' blob:; connect-src 'self' blob: data:; worker-src 'self' blob:; "
            "object-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'")

_LOCK = threading.Lock()  # serialises review.json read-modify-write


class ReviewError(Exception):
    def __init__(self, msg: str, status: int = 400):
        super().__init__(msg)
        self.status = status


# ---------------------------------------------------------------- storage

def ensure_review_root() -> None:
    REVIEW.mkdir(exist_ok=True)
    gd = REVIEW / ".gdignore"
    if not gd.exists():
        gd.touch()


def batch_dir(name: str, must_exist: bool = True) -> Path:
    if not name or not BATCH_RE.match(name):
        raise ReviewError(f"bad batch name: {name!r}")
    d = REVIEW / name
    if must_exist and not (d / "batch.json").is_file():
        raise ReviewError(f"no such batch: {name} (expected {d / 'batch.json'})", 404)
    return d


def list_batch_names() -> list[str]:
    if not REVIEW.is_dir():
        return []
    return sorted(p.name for p in REVIEW.iterdir()
                  if p.is_dir() and BATCH_RE.match(p.name) and (p / "batch.json").is_file())


def read_json(path: Path, default):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        return default


def atomic_write_json(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
            f.write("\n")
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def load_batch(name: str) -> tuple[Path, dict]:
    d = batch_dir(name)
    try:
        data = read_json(d / "batch.json", None)
    except json.JSONDecodeError as e:
        raise ReviewError(f"{name}/batch.json is not valid JSON: {e}", 500)
    if not isinstance(data, dict) or not isinstance(data.get("items", []), list):
        raise ReviewError(f"{name}/batch.json must be an object with an 'items' list", 500)
    items = [it for it in data.get("items", []) if isinstance(it, dict) and it.get("id")]
    data["items"] = items
    mode = data.get("mode")
    if mode is not None and mode not in MODES:
        raise ReviewError(f"{name}/batch.json: \"mode\" must be one of {', '.join(MODES)} (got {mode!r})", 500)
    data["mode"] = mode or "standard"
    return d, data


def load_review(d: Path) -> dict:
    try:
        data = read_json(d / "review.json", None)
    except json.JSONDecodeError as e:
        raise ReviewError(f"{d.name}/review.json is not valid JSON: {e}", 500)
    if not isinstance(data, dict):
        data = {}
    if not isinstance(data.get("items"), dict):
        data["items"] = {}
    return data


def item_path(d: Path, item: dict) -> Path | None:
    rel = item.get("file")
    if not rel or not isinstance(rel, str):
        return None
    p = (d / rel).resolve()
    root = d.resolve()
    if root not in p.parents:
        return None  # escapes the batch dir: treat as missing
    return p


def item_kind(item: dict) -> str:
    k = item.get("kind")
    if k in ("audio", "image", "video", "model"):
        return k
    ext = Path(item.get("file") or "").suffix.lower()
    if ext in IMAGE_EXTS:
        return "image"
    if ext in VIDEO_EXTS:
        return "video"
    if ext in MODEL_EXTS:
        return "model"
    return "audio"


def batch_file(d: Path, rel) -> Path | None:
    """An existing file inside the batch folder, named relative to that folder or, as some
    generators write it, relative to the repo root (review/<batch>/...)."""
    if not rel or not isinstance(rel, str) or os.path.isabs(rel):
        return None
    root = d.resolve()
    for base in (d, REPO):
        p = (base / rel).resolve()
        if root in p.parents and p.is_file():
            return p
    return None


def companion_video(d: Path, item: dict) -> Path | None:
    """The clip behind a non-video item: `video` or meta.video_mp4 (etc.), or a poster frame
    written next to its clip (x_poster.png -> x.mp4)."""
    if item_kind(item) == "video":
        return None
    meta = item.get("meta") if isinstance(item.get("meta"), dict) else {}
    for rel in [item.get("video")] + [meta.get(k) for k in VIDEO_META_KEYS]:
        p = batch_file(d, rel)
        if p is not None and p.suffix.lower() in VIDEO_EXTS:
            return p
    f = item_path(d, item)
    if f is not None and f.stem.endswith("_poster"):
        for ext in VIDEO_EXTS:
            p = f.with_name(f.stem[: -len("_poster")] + ext)
            if p.is_file():
                return p
    return None


## An art "seat" made a take: `claude`, `codex`, `grok` (any short name works; these three get their own colour).
## Items carry `seat` for their own file, and each entry of `takes` may carry one. The page can hide the
## names (Blind) until the item has a verdict, so a take is judged on its looks.
SEAT_RE = re.compile(r"^[a-z0-9][a-z0-9_-]{0,23}$")


def clean_seat(v) -> str | None:
    s = v.strip().lower() if isinstance(v, str) else ""
    return s if SEAT_RE.match(s) else None


## v1.11: takes. A generator may roll an item more than once. The extra takes sit beside its
## file in a .takes/ folder: <stem>.t2.mp3, <stem>.t3.mp3 (more rolls of the same take) and
## <stem>.r1.mp3, r2... (takes rejected in earlier rounds, higher is newer). A batch may also
## list them itself as `takes`. Accepting one records it as the item's `pick`, and install,
## "in game" and reconcile all use the pick.
TAKE_TAG_RE = re.compile(r"^(t|r)(\d{1,3})$")
MEDIA_EXTS = {e for e in CONTENT_TYPES if e not in (".json", ".bin")}


def item_takes(d: Path, item: dict) -> list[dict]:
    """The item's candidates, its own file first: [{file, label, path}] (path is None when missing).
    A generator may add a word on each (meta.take_info: {file: "falls 3.1 st"}), shown on its chip."""
    out = _item_takes(d, item)
    meta = item.get("meta") if isinstance(item.get("meta"), dict) else {}
    info = meta.get("take_info") if isinstance(meta.get("take_info"), dict) else {}
    for t in out:
        if isinstance(info.get(t["file"]), str) and info[t["file"]]:
            t["label"] += " · " + info[t["file"]][:40]
    return out


def _item_takes(d: Path, item: dict) -> list[dict]:
    main = item_path(d, item)
    root = d.resolve()
    out = [{"file": item.get("file"), "label": str(item.get("take_label") or "take 1"),
            "path": main if main is not None and main.is_file() else None, "seat": clean_seat(item.get("seat"))}]
    listed = item.get("takes")
    if isinstance(listed, list):
        for i, t in enumerate(listed):
            rel = t.get("file") if isinstance(t, dict) else t
            tp = batch_file(d, rel)
            if tp is None:
                continue
            label = (t.get("label") if isinstance(t, dict) else None) or f"take {i + 2}"
            out.append({"file": tp.relative_to(root).as_posix(), "label": str(label), "path": tp,
                        "seat": clean_seat(t.get("seat")) if isinstance(t, dict) else None})
        return out
    if main is None or not (main.parent / ".takes").is_dir():
        return out
    found = []
    for tp in (main.parent / ".takes").iterdir():
        if not tp.is_file() or tp.suffix.lower() not in MEDIA_EXTS:
            continue
        stem, _, tag = tp.stem.rpartition(".")
        m = TAKE_TAG_RE.match(tag)
        if stem == main.stem and m:
            found.append((m.group(1), int(m.group(2)), tp))
    found.sort(key=lambda x: (x[0] != "t", x[1] if x[0] == "t" else -x[1]))
    for kind, n, tp in found:
        out.append({"file": tp.relative_to(root).as_posix(),
                    "label": f"take {n}" if kind == "t" else f"rejected in round {n}", "path": tp, "seat": None})
    return out


def picked_path(d: Path, item: dict, entry: dict | None) -> Path | None:
    """The file the verdict is about: the picked take when one was accepted, else the item's own."""
    pick = entry.get("pick") if isinstance(entry, dict) else None
    if isinstance(pick, str) and pick and pick != item.get("file"):
        for t in item_takes(d, item)[1:]:
            if t["file"] == pick and t["path"] is not None:
                return t["path"]
    return item_path(d, item)


## "what's in the game now": the file an item replaces, when a browser can show it
GAME_EXTS = {".mp3", ".wav", ".ogg", ".m4a", ".png", ".webp", ".jpg", ".jpeg", ".gif", ".mp4", ".webm", ".glb", ".gltf"}


def game_path(item: dict) -> Path | None:
    meta = item.get("meta") if isinstance(item.get("meta"), dict) else {}
    cands = [item.get("target")]
    for pr in meta.get("install") or []:
        if isinstance(pr, (list, tuple)) and len(pr) == 2:
            cands.append(pr[1])
    for t in cands:
        p = _repo_target(t) if isinstance(t, str) else None
        if p is None or not p.is_file() or p.suffix.lower() not in GAME_EXTS:
            continue
        if any(part.startswith(".") for part in p.relative_to(REPO.resolve()).parts):
            continue  # never serve dotfiles or dot folders from the repo
        return p
    return None


def same_file(a: Path | None, b: Path | None) -> bool:
    try:
        return a is not None and b is not None and a.stat().st_size == b.stat().st_size and filecmp.cmp(a, b, shallow=False)
    except OSError:
        return False


def media_url(name: str, d: Path, p: Path, st=None) -> str:
    st = st or p.stat()
    rel = p.relative_to(d.resolve()).as_posix()
    return f"/media/{quote(name)}/{quote(rel)}?v={st.st_mtime:.3f}"


def merge_item(name: str, d: Path, item: dict, entry: dict | None, mode: str = "standard") -> dict:
    """batch item + its verdict entry + computed status."""
    p = picked_path(d, item, entry)
    exists = p is not None and p.is_file()
    st = p.stat() if exists else None
    entry = entry if isinstance(entry, dict) else {}
    verdict = entry.get("verdict", "pending")
    if verdict not in VERDICTS:
        verdict = "pending"
    regenerated = False
    fm = entry.get("file_mtime")
    if exists and verdict in ("accept", "revise", "reject") and "file_mtime" in entry:
        # file_mtime null = the verdict was given while the file was missing (a reject);
        # a file showing up since then is a new take.
        regenerated = fm is None or (isinstance(fm, (int, float)) and st.st_mtime > fm + MTIME_EPS)
    if not exists and verdict != "reject":
        status = "missing"  # a rejected missing file stays rejected, so it gets re-rolled
    elif regenerated:
        status = "pending"
    else:
        status = verdict
    ## "in game": accepted, installed by a successful Install run, and the file is the one installed
    inst = entry.get("installed") if isinstance(entry.get("installed"), dict) else None
    installed = bool(inst) and status in KEPT and exists and isinstance(inst.get("file_mtime"), (int, float)) \
        and abs(st.st_mtime - inst["file_mtime"]) <= MTIME_EPS
    out = dict(item)
    out["kind"] = item_kind(item)
    out.update(
        status=status,
        installed=installed,
        installed_at=inst.get("at") if installed else None,
        verdict=verdict,
        regenerated=regenerated,
        note=entry.get("note", "") or "",
        edited_text=entry.get("text"),
        decided_at=entry.get("at"),
        history=entry.get("history", []) if isinstance(entry.get("history"), list) else [],
        exists=exists,
        mtime=st.st_mtime if st else None,
        size=st.st_size if st else None,
        url=(media_url(name, d, p, st) if st else None),
        src=(p.relative_to(d.resolve()).as_posix() if p is not None else None),
        pick=(entry.get("pick") if p is not None and p != item_path(d, item) else None),
    )
    takes = item_takes(d, item)
    out["seat"] = takes[0]["seat"]  # the seat of the take the verdict is about (set below when it is another)
    if len(takes) > 1:
        rows = []
        for t in takes:
            tst = t["path"].stat() if t["path"] is not None else None
            rows.append({"file": t["file"], "label": t["label"], "exists": tst is not None, "seat": t["seat"],
                         "url": media_url(name, d, t["path"], tst) if tst else None,
                         "mtime": tst.st_mtime if tst else None, "size": tst.st_size if tst else None,
                         "picked": t["path"] is not None and t["path"] == p})
        out["takes"] = rows
        out["seat"] = next((r["seat"] for r in rows if r["picked"]), takes[0]["seat"])
    gp = game_path(item)
    if gp is not None:
        out["game_url"] = f"/game/{quote(name)}/{quote(item['id'])}?v={gp.stat().st_mtime:.3f}"
        out["game_same"] = same_file(p if exists else None, gp)
    poster = batch_file(d, item.get("poster"))
    if poster is not None:
        out["poster_url"] = media_url(name, d, poster)
    vid = companion_video(d, item)
    if vid is not None:
        vst = vid.stat()
        out.update(video_file=vid.relative_to(d.resolve()).as_posix(), video_size=vst.st_size,
                   video_url=media_url(name, d, vid, vst))
    return out


def merged_batch(name: str) -> dict:
    d, data = load_batch(name)
    rv = load_review(d)["items"]
    items = [merge_item(name, d, it, rv.get(it["id"]), data["mode"]) for it in data["items"]]
    return {"batch": name, "title": data.get("title") or name, "mode": data["mode"], "items": items,
            "actions": [public_action(a) for a in batch_actions(name, data)]}


def summarize(items: list[dict]) -> dict:
    c = {"total": len(items), "accept": 0, "revise": 0, "reject": 0, "pending": 0, "missing": 0, "regenerated": 0,
         "installed": 0}
    for it in items:
        c[it["status"]] += 1
        if it.get("installed"):
            c["installed"] += 1
        if it["regenerated"]:
            c["regenerated"] += 1
    c["reviewed"] = c["accept"] + c["revise"] + c["reject"]
    return c


## v1.11: lessons. Every note a reviewer writes is a lesson about the prompts. They are sorted into
## themes (a note can have several), and the generators read the same themes to steer a re-roll.
NOTE_THEMES = [
    # (theme, what it asks for, pattern, kinds it applies to: None = any)
    ("pause", "More pause between sentences", r"\bpause|spacing|space between|\bgaps?\b", ("audio",)),
    ("fall", "Falling (downward) inflection", r"downward|inflect|cadence|descend|trail(s|ing)? down|end(s)? on", ("audio",)),
    ("pitch", "Pitch too high", r"high[- ]?pitch|too high|pitched", ("audio",)),
    ("feeling", "More feeling (menace, anger, smugness, conviction...)",
     r"menac|anger|angry|smug|salty|annoy|conviction|stoic|satisf|confident|smarmy|furious|monotone|emotion|"
     r"shout|under (his|her) breath|finality|gloat|sneer|sarcas", ("audio",)),
    ("stress", "Stress a word", r"emphas|stress|\*\w+\*|\b[a-z]*[A-Z]{3,}[a-z]*\b", ("audio",)),
    ("pace", "Pacing or delivery", r"\bpacing|\bfaster|\bslower|\bspeed|\bdelivery|\brushed|\bdrag", ("audio",)),
    ("clipped", "Cut off at the end", r"cut off|cuts off|cutting off|cut out|clipped|truncat|blips", ("audio",)),
    ("wrong_voice", "Doesn't sound like the character", r"voice\b.*\b(isn'?t|not)\b|isn'?t \w+'s voice|wrong voice|sounds like a", ("audio",)),
    ("framing", "Cropped or out of frame", r"cut(s|ting)? (out|off)|cropp|out of frame|edges|sides|top of", ("image", "video")),
    ("artifacts", "Artifacts, noise or invented objects", r"noise|artifact|invent|glitch|garbl|smear|melt|extra \w+|should not be there", None),
    ("motion", "Motion snaps or jumps", r"snap|flip|jump|swirl|180|instant|pop(s|ping)?\b|one frame", ("image", "video")),
    ("acting", "Expression or acting", r"smile|glassy|stare|staring|expression|acknowledg|warmly|knowing|eyes", ("image", "video")),
    ("staging", "Staging: what the scene shows", r"flag|trampl|prisoner|already|march(ed|ing)?\b|scene|background", ("image", "video")),
    ("detail", "Hard to read the details", r"hard to read|detail|blurr|muddy|resolution", ("image", "video")),
    ("period", "Period or melody (music)", r"melod|fife|lyrics|instrument|tune|period|era\b", None),
    ("redo", "Just roll again", r"^\s*(redo|re-?do|try again|again)[.!]?\s*$", None),
    ("praise", "Praise", r"perfect|\bgreat\b|\blove\b|excellent|holy shit|nailed", None),
    # concept art (v2): the notes the art chips write
    ("more_like", "More like this", r"more like this", ("image",)),
    ("palette", "Wrong palette", r"palette|colou?r scheme|wrong colou?rs?|too (dark|bright|saturated|desaturated|muted)", ("image",)),
    ("faction", "Reads like another faction", r"another faction|other faction|reads (like|as) (a |the |an )?\w+|looks like (a |the |an )?\w+ faction", ("image",)),
    ("text_in_image", "Text in the image", r"text in|lettering|letters|captions?\b|watermark|\blogos?\b|writing in", ("image",)),
    ("lookalike", "Too close to something that exists", r"look-?alike|too close to|resembles|rip-?off|copy of|\bIP\b", ("image",)),
    ("silhouette", "Silhouette is right, the detail is not", r"silhouette|keep the (shape|outline)", ("image",)),
    # 3D models: the notes the model chips write
    ("concept_match", "Doesn't match the concept art", r"match the concept|doesn.?t match|not like the concept|off[- ]model", ("model",)),
    ("proportions", "Proportions are off", r"proportion|too (tall|short|wide|thin|fat|big|small)|\bscale\b", ("model",)),
    ("texture", "Texture is blurry or muddy", r"textures?|blurry|muddy|tiling|\bseams?\b", ("model",)),
    ("geometry", "Holes or broken geometry", r"holes?\b|broken|geometry|non-?manifold|floating|intersect|clipping", ("model",)),
    ("pose", "Wrong pose", r"\bpose|\bstance|\barms?\b|\blegs?\b", ("model",)),
]
## themes that are nothing to fix: a note that says what worked
NO_FIX_THEMES = ("praise", "more_like")
_THEME_RE = [(t, lbl, re.compile(pat, re.I if t != "stress" else 0), kinds) for t, lbl, pat, kinds in NOTE_THEMES]


def note_themes(note: str, kind: str = "audio") -> list[str]:
    """The themes a note touches, for an item of this kind (audio, image or video)."""
    if not isinstance(note, str) or not note.strip():
        return []
    out = []
    for t, _, rx, kinds in _THEME_RE:
        if kinds is not None and kind not in kinds:
            continue
        if t == "stress" and re.search(r"emphas|stress", note, re.I):
            out.append(t)
            continue
        if rx.search(note):
            out.append(t)
    if "silhouette" in out and "detail" in out:
        out.remove("detail")  # "keep the silhouette, change the detail" is one note, not two
    return out


def _item_notes(entry: dict) -> list[str]:
    notes = [h.get("note") for h in entry.get("history") or [] if isinstance(h, dict) and h.get("note")]
    if entry.get("note"):
        notes.append(entry["note"])
    seen, out = set(), []
    for n in notes:
        if n.strip().lower() not in seen:
            seen.add(n.strip().lower())
            out.append(n.strip())
    return out


def tally_seats(seats: dict, d: Path, item: dict, entry: dict, verdict: str) -> None:
    """Count one decided item against the seats that made its takes. Good and Good with changes go to the
    seat whose take was kept (the others were passed over); Bad goes to every seat that made a take, since
    every take of the item was rejected."""
    takes = item_takes(d, item)
    present = [tk["seat"] for tk in takes if tk["seat"]]
    if not present:
        return
    pick = entry.get("pick") if isinstance(entry.get("pick"), str) else None
    kept_take = next((tk for tk in takes if pick and tk["file"] == pick), takes[0])

    def bump(seat: str, key: str) -> None:
        row = seats.setdefault(seat, {"good": 0, "revise": 0, "bad": 0, "passed": 0, "items": 0})
        row[key] += 1

    for seat in dict.fromkeys(present):  # each seat once per item
        seats.setdefault(seat, {"good": 0, "revise": 0, "bad": 0, "passed": 0, "items": 0})["items"] += 1
    if verdict == "reject":
        for seat in dict.fromkeys(present):
            bump(seat, "bad")
        return
    winner = kept_take["seat"]
    if winner:
        bump(winner, "good" if verdict == "accept" else "revise")
    for seat in dict.fromkeys(present):
        if seat != winner:
            bump(seat, "passed")


def lessons(names: list[str] | None = None) -> dict:
    """Every batch's verdicts and notes, summed up: how often a first take is kept, by kind and by
    group (a voice), and what the notes ask for, by theme, with examples. `names` limits it to
    those batches (and then includes them even if they'd normally be skipped, as tests do)."""
    kinds: dict = {}
    groups: dict = {}
    themes = {t: {"theme": t, "label": lbl, "notes": 0, "fixed": 0, "open": 0, "kinds": {}, "examples": []}
              for t, lbl, _, _ in NOTE_THEMES}
    seats: dict = {}
    batches = 0
    for name in names if names is not None else list_batch_names():
        try:
            d, data = load_batch(name)
            entries = load_review(d)["items"]
        except ReviewError:
            continue
        if names is None and (name.startswith("_") or name.endswith("_lab") or data.get("lab")):
            continue  # the demo batch, and experiments (a lab's verdicts say which variant won, not which take)
        batches += 1
        for item in data.get("items", []):
            e = entries.get(item.get("id"))
            if not isinstance(e, dict):
                continue
            kind = item_kind(item)
            v = e.get("verdict", "pending")
            if v not in ("accept", "revise", "reject"):
                continue
            tally_seats(seats, d, item, e, v)
            was_rejected = any(isinstance(h, dict) and h.get("verdict") == "reject" for h in e.get("history") or [])
            rounds = 1 + sum(1 for h in e.get("history") or [] if isinstance(h, dict) and h.get("verdict") == "reject")
            for bucket, key in ((kinds, kind), (groups, f"{kind}:{item.get('group') or '-'}")):
                b = bucket.setdefault(key, {"decided": 0, "first_take": 0, "redone": 0, "open": 0, "revise": 0, "rounds": 0})
                b["decided"] += 1
                if v == "accept":
                    b["redone" if was_rejected else "first_take"] += 1
                    b["rounds"] += rounds
                elif v == "revise":
                    b["revise"] += 1  # kept, with changes asked for: neither a clean first take nor a reject
                else:
                    b["open"] += 1
            for note in _item_notes(e):
                for t in note_themes(note, kind):
                    th = themes[t]
                    th["notes"] += 1
                    th["kinds"][kind] = th["kinds"].get(kind, 0) + 1
                    if t in NO_FIX_THEMES:
                        pass  # nothing to fix
                    elif v == "accept" and (was_rejected or e.get("note") != note):
                        th["fixed"] += 1
                    elif v in ("reject", "revise"):
                        th["open"] += 1
                    if len(th["examples"]) < 5:
                        th["examples"].append({"batch": name, "id": item.get("id"), "group": item.get("group") or "",
                                               "note": note, "status": v})
    for bucket in (kinds, groups):
        for b in bucket.values():
            acc = b["first_take"] + b["redone"]
            b["first_take_rate"] = round(b["first_take"] / b["decided"], 3) if b["decided"] else None
            b["mean_rounds"] = round(b["rounds"] / acc, 2) if acc else None
    ranked = sorted((t for t in themes.values() if t["notes"]), key=lambda t: -t["notes"])
    return {"batches": batches, "kinds": kinds, "groups": groups, "themes": ranked, "seats": seats,
            "generated": datetime.now().isoformat(timespec="seconds")}


LESSONS_BEGIN, LESSONS_END = "<!-- lessons:begin -->", "<!-- lessons:end -->"


def lessons_markdown(ls: dict) -> str:
    pct = lambda x: "–" if x is None else f"{round(x * 100)}%"
    rows = ["| kind | decided | kept first take | good with changes | redone, then kept | still rejected | rounds to keep |",
            "|---|---|---|---|---|---|---|"]
    for k, b in sorted(ls["kinds"].items(), key=lambda kv: -kv[1]["decided"]):
        rows.append(f"| {k} | {b['decided']} | {b['first_take']} ({pct(b['first_take_rate'])}) | {b['revise']} | {b['redone']} | {b['open']} | {b['mean_rounds'] or '–'} |")
    voices = [(g.split(":", 1)[1], b) for g, b in ls["groups"].items() if g.startswith("audio:") and b["decided"] >= 8]
    vrow = ", ".join(f"{g} {pct(b['first_take_rate'])}" for g, b in sorted(voices, key=lambda x: x[1]["first_take_rate"] or 0))
    th = ["| theme | notes | fixed by a redo | still open | e.g. |", "|---|---|---|---|---|"]
    for t in ls["themes"]:
        ex = t["examples"][0]["note"] if t["examples"] else ""
        ex = (ex[:90] + "…") if len(ex) > 90 else ex
        th.append(f"| {t['label']} | {t['notes']} | {t['fixed']} | {t['open']} | “{ex.replace('|', '/')}” |")
    st = []
    if ls.get("seats"):
        st = ["", "| seat | good | good with changes | bad | passed over |", "|---|---|---|---|---|"]
        for seat, b in sorted(ls["seats"].items()):
            st.append(f"| {seat} | {b['good']} | {b['revise']} | {b['bad']} | {b['passed']} |")
    return "\n".join([LESSONS_BEGIN,
                      f"_Generated by `python3 tools/review/review.py lessons --write <file.md>` from "
                      f"{ls['batches']} review batches ({ls['generated'][:10]}). Don't edit by hand._", "",
                      *rows, "", f"First takes kept, by voice (8+ decided): {vrow or '–'}.", *st, "", *th, LESSONS_END])


def cmd_lessons(args) -> int:
    ls = lessons()
    if args.json:
        print(json.dumps(ls, indent=1))
        return 0
    md = lessons_markdown(ls)
    if args.write:
        path = Path(args.write)
        text = path.read_text(encoding="utf-8") if path.exists() else ""
        if LESSONS_BEGIN in text and LESSONS_END in text:
            head, _, rest = text.partition(LESSONS_BEGIN)
            _, _, tail = rest.partition(LESSONS_END)
            text = head + md + tail
        else:
            text = text.rstrip() + "\n\n" + md + "\n"
        path.write_text(text, encoding="utf-8")
        print(f"wrote the lessons block in {path}")
    else:
        print(md)
    return 0


def decide(name: str, item_id: str, verdict=None, note=None, text=None, take=None) -> dict:
    """A verdict, note or edit on an item. `take` (with accept) picks one of its takes."""
    if take is not None and not isinstance(take, str):
        raise ReviewError("take must be a file name")
    if verdict is not None and verdict not in VERDICTS:
        raise ReviewError(f"verdict must be one of {', '.join(VERDICTS)}")
    if note is not None and not isinstance(note, str):
        raise ReviewError("note must be a string")
    if text is not None and not isinstance(text, str):
        raise ReviewError("text must be a string")
    with _LOCK:
        d, data = load_batch(name)
        item = next((it for it in data["items"] if it["id"] == item_id), None)
        if item is None:
            raise ReviewError(f"no item {item_id!r} in {name}", 404)
        if verdict == "revise" and data["mode"] != "concept":
            raise ReviewError('"revise" (Good with changes) only exists in batches with "mode": "concept"')
        review = load_review(d)
        entries = review["items"]
        old = entries.get(item_id) if isinstance(entries.get(item_id), dict) else {}
        entry = dict(old)
        before = merge_item(name, d, item, old, data["mode"])
        p = item_path(d, item)
        if verdict in KEPT and take and take != item.get("file"):
            p = next((t["path"] for t in item_takes(d, item)[1:] if t["file"] == take), None)
            if p is None:
                raise ReviewError(f"{item_id} has no take {take!r}", 404)
        if verdict is not None:
            if verdict in KEPT and not (p is not None and p.is_file()):
                raise ReviewError("the file is missing; can't accept it", 409)
            if before["regenerated"]:
                # the file changed since this verdict: keep the old call as history
                prev = {k: old[k] for k in ("verdict", "note", "text", "at", "file_mtime") if k in old}
                entry["history"] = (entry.get("history") or [])[-(HISTORY_KEEP - 1):] + [prev]
                entry["note"] = ""
            entry["verdict"] = verdict
            entry["at"] = datetime.now().isoformat(timespec="seconds")
            entry["file_mtime"] = p.stat().st_mtime if p is not None and p.is_file() else None
            if verdict in KEPT and p is not None and p != item_path(d, item):
                entry["pick"] = p.relative_to(d.resolve()).as_posix()
            else:
                entry.pop("pick", None)  # the item's own file, or no take chosen at all
        if note is not None:
            entry["note"] = note.strip()
        if text is not None:
            t = text.strip()
            if not t or t == (item.get("text") or "").strip():
                entry.pop("text", None)
            else:
                entry["text"] = t
        entry.setdefault("verdict", "pending")
        entry.setdefault("note", "")
        if entry["verdict"] == "revise" and not entry["note"]:
            raise ReviewError("Good with changes needs a note saying what to change")
        entries[item_id] = entry
        atomic_write_json(d / "review.json", review)
        return merge_item(name, d, item, entry, data["mode"])


def rejected_entries(items: list[dict], mode: str = "standard") -> list[dict]:
    """What a generator redoes. A concept batch also lists its `revise` items (Good with changes):
    the next round redoes both, and each entry says which with `verdict` (`reject` = start again,
    `revise` = keep what works and apply the note)."""
    concept = mode == "concept"
    out = []
    for it in items:
        if it["status"] != "reject" and not (concept and it["status"] == "revise"):
            continue
        e = {"id": it["id"],
             "text": it.get("edited_text") or it.get("text") or "",
             "note": it.get("note") or "",
             "meta": it.get("meta") or {}}
        if concept:
            e["verdict"] = it["status"]
            e["group"] = it.get("group") or ""
            e["file"] = it.get("src") or it.get("file")  # the take the verdict is about
            if it.get("seat"):
                e["seat"] = it["seat"]
            if it.get("takes"):  # every candidate, so each seat can redo its own
                e["takes"] = [{"file": tk["file"], **({"seat": tk["seat"]} if tk.get("seat") else {})}
                              for tk in it["takes"]]
        out.append(e)
    return out


def write_rejected(name: str) -> tuple[Path, int]:
    """review/<batch>/rejected.json from the current verdicts (what a generator re-rolls)."""
    d, _ = load_batch(name)
    mb = merged_batch(name)
    rejected = rejected_entries(mb["items"], mb["mode"])
    atomic_write_json(d / "rejected.json", rejected)
    return d / "rejected.json", len(rejected)


# ---------------------------------------------------------------- actions
#
# batch.json may declare the commands that finish a review ("actions"). The UI shows them as
# buttons with their options; the browser only ever sends {batch, action, options} and the
# server builds the argv from the declaration: cmd[0] must be "python3" (run as this Python),
# cmd[1] a script inside the repo, and every option must be declared and valid.

OPTION_TYPES = ("bool", "int", "string", "choice")
FLAG_RE = re.compile(r"^--?[A-Za-z0-9][A-Za-z0-9_-]*$")
ACTION_ID_RE = re.compile(r"^[A-Za-z0-9_][A-Za-z0-9_.-]{0,63}$")
STRING_MAX = 500


def builtin_actions(name: str) -> list[dict]:
    """What a batch that declares no actions gets: this tool's own `apply`."""
    return [{"id": "install", "kind": "install", "label": "Install accepted",
             "help": "Copy every accepted file to its target and write rejected.json (review.py apply)",
             "cmd": ["python3", "tools/review/review.py", "apply", name], "builtin": True,
             "options": [{"flag": "--dry-run", "label": "Dry run", "type": "bool", "default": False,
                          "help": "Only list what would be copied"}]}]


def _is_int(v) -> bool:
    return isinstance(v, int) and not isinstance(v, bool)


def check_cmd(cmd) -> list[str]:
    """The declared cmd -> the argv prefix to run. Raises ReviewError when it isn't allowed."""
    if not isinstance(cmd, list) or len(cmd) < 2:
        raise ReviewError('cmd must be a list: ["python3", "<script inside the repo>", ...]')
    for c in cmd:
        if not isinstance(c, str) or not c or "\x00" in c:
            raise ReviewError("every cmd element must be a non-empty string")
    if cmd[0] != "python3":
        raise ReviewError('cmd[0] must be "python3"')
    rel = cmd[1]
    if os.path.isabs(rel) or rel.startswith("-"):
        raise ReviewError("cmd[1] must be a script path relative to the repo root")
    p = (REPO / rel).resolve()
    if REPO.resolve() not in p.parents or not p.is_file():
        raise ReviewError(f"cmd[1] {rel!r} is not a file inside the repo")
    return [sys.executable, str(p)] + cmd[2:]


def check_option(o) -> dict:
    if not isinstance(o, dict):
        raise ReviewError("each option must be an object")
    flag, typ = o.get("flag"), o.get("type")
    if not isinstance(flag, str) or not FLAG_RE.match(flag):
        raise ReviewError(f"option flag {flag!r} must look like --name")
    if typ not in OPTION_TYPES:
        raise ReviewError(f"option {flag}: type must be one of {', '.join(OPTION_TYPES)}")
    out = {"flag": flag, "type": typ, "label": str(o.get("label") or flag), "help": str(o.get("help") or "")}
    dflt = o.get("default")
    if typ == "bool":
        if dflt is not None and not isinstance(dflt, bool):
            raise ReviewError(f"option {flag}: default must be true or false")
        out["default"] = bool(dflt)
    elif typ == "int":
        for k in ("min", "max"):
            if o.get(k) is not None and not _is_int(o[k]):
                raise ReviewError(f"option {flag}: {k} must be an integer")
            out[k] = o.get(k)
        if dflt is not None and not _is_int(dflt):
            raise ReviewError(f"option {flag}: default must be an integer")
        if out["min"] is not None and out["max"] is not None and out["min"] > out["max"]:
            raise ReviewError(f"option {flag}: min is above max")
        out["default"] = dflt
        if dflt is not None:
            _check_int(out, dflt)
    elif typ == "string":
        if dflt is not None and not isinstance(dflt, str):
            raise ReviewError(f"option {flag}: default must be a string")
        out["default"] = dflt
    else:
        ch = o.get("choices")
        if (not isinstance(ch, list) or not ch
                or not all(isinstance(c, (str, int, float)) and not isinstance(c, bool) for c in ch)):
            raise ReviewError(f"option {flag}: choices must be a non-empty list of strings or numbers")
        if dflt is not None and dflt not in ch:
            raise ReviewError(f"option {flag}: default {dflt!r} is not one of the choices")
        out["choices"] = list(ch)
        out["default"] = dflt if dflt is not None else ch[0]
    return out


def _check_int(o: dict, v: int) -> None:
    if o.get("min") is not None and v < o["min"]:
        raise ReviewError(f"{o['flag']} must be at least {o['min']} (got {v})")
    if o.get("max") is not None and v > o["max"]:
        raise ReviewError(f"{o['flag']} must be at most {o['max']} (got {v})")


def check_action(a) -> dict:
    """A declared action, validated and normalised. Raises ReviewError with the reason."""
    if not isinstance(a, dict):
        raise ReviewError("each action must be an object")
    aid = a.get("id")
    if not isinstance(aid, str) or not ACTION_ID_RE.match(aid):
        raise ReviewError(f"action id {aid!r} must be a short name ([A-Za-z0-9_.-])")
    check_cmd(a.get("cmd"))
    opts = a.get("options") or []
    if not isinstance(opts, list):
        raise ReviewError("options must be a list")
    options = [check_option(o) for o in opts]
    flags = [o["flag"] for o in options]
    if len(set(flags)) != len(flags):
        raise ReviewError("an option flag is declared twice")
    kind = a.get("kind") or "custom"
    return {"id": aid, "kind": str(kind), "label": str(a.get("label") or aid), "help": str(a.get("help") or ""),
            "cmd": list(a["cmd"]), "options": options, "spends": a.get("spends") is True,
            "builtin": a.get("builtin") is True}


def batch_actions(name: str, data: dict) -> list[dict]:
    """The batch's actions, validated. An invalid one comes back with an "error" (and can't run);
    a batch that declares none gets the built-in install (this tool's `apply`)."""
    raw = data.get("actions")
    if raw is None or raw == []:
        raw = builtin_actions(name)
    if not isinstance(raw, list):
        return [{"id": "actions", "kind": "custom", "label": "actions", "help": "", "cmd": [], "options": [],
                 "spends": False, "builtin": False, "error": "batch.json: \"actions\" must be a list"}]
    out, seen = [], set()
    for i, a in enumerate(raw):
        try:
            act = check_action(a)
            if act["id"] in seen:
                raise ReviewError(f"action id {act['id']!r} is used twice")
            seen.add(act["id"])
        except ReviewError as e:
            aid = a.get("id") if isinstance(a, dict) and isinstance(a.get("id"), str) else f"action{i + 1}"
            label = a.get("label") if isinstance(a, dict) and isinstance(a.get("label"), str) else aid
            act = {"id": aid, "kind": str(a.get("kind") or "custom") if isinstance(a, dict) else "custom",
                   "label": label, "help": "", "cmd": [], "options": [], "spends": False, "builtin": False,
                   "error": str(e)}
        out.append(act)
    return out


def display_cmd(cmd: list[str], extra: list[str] = ()) -> str:
    return shlex.join(list(cmd) + list(extra))


def public_action(a: dict) -> dict:
    """What the UI needs to draw an action (never used to run one)."""
    out = {k: a.get(k) for k in ("id", "kind", "label", "help", "options", "spends", "builtin")}
    out["cmd"] = display_cmd(a["cmd"]) if a.get("cmd") else ""
    if a.get("error"):
        out["error"] = a["error"]
    return out


def build_argv(action: dict, options) -> tuple[list[str], list[str]]:
    """(argv to run, the option args as shown). Only declared options, each validated."""
    if action.get("error"):
        raise ReviewError(f"action {action['id']!r} can't run: {action['error']}")
    argv = check_cmd(action["cmd"])
    if options is None:
        options = {}
    if not isinstance(options, dict):
        raise ReviewError("options must be an object of {flag: value}")
    decl = {o["flag"]: o for o in action["options"]}
    for flag in options:
        if flag not in decl:
            raise ReviewError(f"unknown option {flag!r} for {action['id']}")
    extra: list[str] = []
    for o in action["options"]:
        flag = o["flag"]
        if flag not in options or options[flag] is None:
            continue  # not sent: the script's own default applies
        v, t = options[flag], o["type"]
        if t == "bool":
            if not isinstance(v, bool):
                raise ReviewError(f"{flag} must be true or false")
            if v:
                extra.append(flag)
        elif t == "int":
            if isinstance(v, str) and re.fullmatch(r"\s*-?\d{1,12}\s*", v):
                v = int(v)
            elif isinstance(v, float) and v.is_integer():
                v = int(v)
            if not _is_int(v):
                raise ReviewError(f"{flag} must be a whole number")
            _check_int(o, v)
            extra += [flag, str(v)]
        elif t == "string":
            if not isinstance(v, str):
                raise ReviewError(f"{flag} must be a string")
            if v == "":
                continue
            if len(v) > STRING_MAX or any(ord(c) < 32 or ord(c) == 127 for c in v):
                raise ReviewError(f"{flag}: at most {STRING_MAX} characters on one line")
            if v.startswith("-"):
                raise ReviewError(f"{flag}: the value may not start with '-'")
            extra += [flag, v]
        else:
            match = next((c for c in o["choices"] if c == v or str(c) == str(v)), None)
            if match is None or isinstance(v, (bool, list, dict)):
                raise ReviewError(f"{flag} must be one of: {', '.join(str(c) for c in o['choices'])}")
            extra += [flag, str(match)]
    return argv + extra, extra


# ---------------------------------------------------------------- runs

RUN_KEEP = 5            # finished runs remembered per batch
OUTPUT_KEEP = 2_000_000  # characters of output kept in memory per run (runs.log has it all)
KILL_GRACE = 3.0        # seconds between SIGTERM and SIGKILL on cancel


class Run:
    def __init__(self, batch: str, action: dict, argv: list[str], shown: str):
        self.id = secrets.token_hex(6)
        self.batch = batch
        self.action = action["id"]
        self.kind = action["kind"]
        self.label = action["label"]
        self.argv = argv
        self.cmd = shown
        self.started_at = datetime.now().isoformat(timespec="seconds")
        self.t0 = time.monotonic()
        self.t1: float | None = None
        self.status = "running"
        self.code: int | None = None
        self.cancel_requested = False
        self.proc: subprocess.Popen | None = None
        self.done = threading.Event()
        self._lock = threading.Lock()
        self._chunks: list[str] = []
        self._size = 0   # characters in _chunks
        self._base = 0   # characters dropped from the front

    def append(self, s: str) -> None:
        if not s:
            return
        with self._lock:
            self._chunks.append(s)
            self._size += len(s)
            while self._size > OUTPUT_KEEP and len(self._chunks) > 1:
                c = self._chunks.pop(0)
                self._size -= len(c)
                self._base += len(c)

    def read(self, frm: int) -> tuple[str, int, bool]:
        """(output from offset `frm`, the next offset, whether the start was dropped)."""
        with self._lock:
            end = self._base + self._size
            truncated = frm < self._base
            frm = min(max(frm, self._base), end)
            parts, pos = [], end
            for c in reversed(self._chunks):
                if pos <= frm:
                    break
                start = pos - len(c)
                parts.append(c[max(0, frm - start):])
                pos = start
            return "".join(reversed(parts)), end, truncated

    def elapsed(self) -> float:
        return (self.t1 if self.t1 is not None else time.monotonic()) - self.t0

    def info(self, frm: int | None = None) -> dict:
        out = {"id": self.id, "batch": self.batch, "action": self.action, "kind": self.kind,
               "label": self.label, "cmd": self.cmd, "status": self.status, "code": self.code,
               "started_at": self.started_at, "elapsed": round(self.elapsed(), 1),
               "log": f"review/{self.batch}/runs.log"}
        if frm is not None:
            text, nxt, truncated = self.read(frm)
            out.update(output=text, next=nxt, truncated=truncated)
        return out


_RUNS: dict[str, Run] = {}
_BATCH_RUNS: dict[str, list[str]] = {}
_RUNS_LOCK = threading.Lock()


def runs_for(name: str) -> list[Run]:
    """Newest first."""
    with _RUNS_LOCK:
        return [_RUNS[i] for i in reversed(_BATCH_RUNS.get(name, [])) if i in _RUNS]


def get_run(run_id: str) -> Run:
    run = _RUNS.get(run_id)
    if run is None:
        raise ReviewError(f"no run {run_id!r} (runs are kept in memory until the server restarts)", 404)
    return run


def _signal_run(run: Run, sig) -> None:
    p = run.proc
    if p is None or p.poll() is not None:
        return
    try:
        if os.name == "posix":
            os.killpg(p.pid, sig)  # the whole group: a script's own children (ludo.py, Godot) too
        elif sig == signal.SIGTERM:
            p.terminate()
        else:
            p.kill()
    except (ProcessLookupError, PermissionError, OSError):
        pass


def _open_log(d: Path):
    try:
        return open(d / "runs.log", "a", encoding="utf-8")
    except OSError:
        return None


def _pump(run: Run, logf) -> None:
    dec = codecs.getincrementaldecoder("utf-8")(errors="replace")
    fd = run.proc.stdout.fileno()

    def out(s: str) -> None:
        run.append(s)
        if logf:
            try:
                logf.write(s)
                logf.flush()
            except OSError:
                pass

    try:
        while True:
            try:
                b = os.read(fd, 65536)
            except OSError:
                b = b""
            if not b:
                break
            out(dec.decode(b))
        out(dec.decode(b"", final=True))
    finally:
        code = run.proc.wait()
        try:
            run.proc.stdout.close()
        except OSError:
            pass
        t1 = time.monotonic()
        status = "cancelled" if run.cancel_requested else ("ok" if code == 0 else "failed")
        out(f"\n[{status} · exit {code} · {t1 - run.t0:.1f}s]\n")  # before the status flips: a poll that
        run.code, run.t1 = code, t1                                  # sees it finished has all the output
        if status == "ok" and getattr(run, "install_snapshot", None):
            try:
                n = mark_installed(run.batch, run.install_snapshot)
                out(f"review: {n} accepted take{'s' if n != 1 else ''} marked in game\n")
            except (OSError, ReviewError) as e:
                out(f"review: couldn't mark the installed takes: {e}\n")
        run.status = status
        if logf:
            try:
                logf.close()
            except OSError:
                pass
        run.done.set()


def mark_installed(name: str, snapshot: dict) -> int:
    """After a successful install: every take that was accepted when it started is in the game."""
    at = time.strftime("%Y-%m-%dT%H:%M:%S")
    n = 0
    with _LOCK:
        d, _ = load_batch(name)
        review = load_review(d)
        entries = review["items"]
        for item_id, mt in snapshot.items():
            e = entries.get(item_id)
            if isinstance(e, dict) and e.get("verdict") in KEPT:
                e["installed"] = {"at": at, "file_mtime": mt}
                n += 1
        atomic_write_json(d / "review.json", review)
    return n


def _install_pairs(d: Path, item: dict, src: str | None = None) -> list[tuple[Path, Path]]:
    """(batch file, game file) pairs an accepted item installs: meta.install when the generator
    lists them (a sheet and its json, a converted video), else the picked take (`src`, batch
    relative; the item's own file when none) → target."""
    meta = item.get("meta") if isinstance(item.get("meta"), dict) else {}
    pairs = meta.get("install")
    out = []
    if isinstance(pairs, list) and pairs:
        for pr in pairs:
            if isinstance(pr, (list, tuple)) and len(pr) == 2:
                out.append((d / str(pr[0]), REPO / str(pr[1])))
    elif item.get("target"):
        out.append((d / str(src or item["file"]), REPO / str(item["target"])))
    return out


def reconcile(name: str) -> int:
    """Mark accepted takes whose installed copies already match as in the game (installs made
    before the review table tracked them, or by hand). Returns how many it marked."""
    n = 0
    with _LOCK:
        d, data = load_batch(name)
        review = load_review(d)
        entries = review["items"]
        for item in data["items"]:
            e = entries.get(item["id"])
            if not isinstance(e, dict) or e.get("verdict") not in KEPT:
                continue
            m = merge_item(name, d, item, e, data["mode"])
            if m["status"] not in KEPT or m["installed"] or m["mtime"] is None:
                continue
            pairs = _install_pairs(d, item, m.get("src"))
            if pairs and all(a.is_file() and b.is_file() and filecmp.cmp(a, b, shallow=False) for a, b in pairs):
                e["installed"] = {"at": time.strftime("%Y-%m-%dT%H:%M:%S"), "file_mtime": m["mtime"], "found": True}
                n += 1
        if n:
            atomic_write_json(d / "review.json", review)
    return n


def start_run(name: str, action_id: str, options=None) -> Run:
    d, data = load_batch(name)
    action = next((a for a in batch_actions(name, data) if a["id"] == action_id), None)
    if action is None:
        raise ReviewError(f"no action {action_id!r} in {name}", 404)
    argv, extra = build_argv(action, options)
    shown = display_cmd(action["cmd"], extra)
    with _RUNS_LOCK:
        busy = next((_RUNS[i] for i in _BATCH_RUNS.get(name, []) if i in _RUNS and _RUNS[i].status == "running"), None)
        if busy is not None:
            raise ReviewError(f"“{busy.label}” is still running for {name}: wait for it or cancel it", 409)
        run = Run(name, action, argv, shown)
        if action["kind"] == "install" and "--dry-run" not in extra:
            ## what this run installs: the kept takes as they are now (marked "in game" if it succeeds)
            run.install_snapshot = {it["id"]: it["mtime"] for it in merged_batch(name)["items"]
                                    if it["status"] in KEPT and it["mtime"] is not None}
        ids = _BATCH_RUNS.setdefault(name, [])
        ids.append(run.id)
        _RUNS[run.id] = run
        while len(ids) > RUN_KEEP:
            _RUNS.pop(ids.pop(0), None)
        logf = _open_log(d)
        head = f"$ {shown}\n"
        if logf:
            logf.write(f"\n===== {run.started_at}  {name} · {run.label}  (run {run.id}) =====\n{head}")
            logf.flush()
        run.append(head)
        try:
            if action["kind"] == "regen":
                ## the generator re-rolls what rejected.json lists: make it match the verdicts now
                rj, n = write_rejected(name)
                msg = f"review: wrote {rj.relative_to(REPO)} ({n} to re-roll)\n"
                run.append(msg)
                if logf:
                    logf.write(msg)
            kw: dict = {"start_new_session": True} if os.name == "posix" else \
                {"creationflags": getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0)}
            run.proc = subprocess.Popen(argv, cwd=str(REPO), stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                        stderr=subprocess.STDOUT, env=dict(os.environ, PYTHONUNBUFFERED="1"), **kw)
        except (OSError, ReviewError) as e:
            run.append(f"review: couldn't start it: {e}\n[failed]\n")
            run.status, run.t1 = "failed", time.monotonic()
            if logf:
                logf.write(f"review: couldn't start it: {e}\n[failed]\n")
                logf.close()
            run.done.set()
            return run
        threading.Thread(target=_pump, args=(run, logf), name=f"run-{run.id}", daemon=True).start()
    return run


def cancel_run(run_id: str) -> Run:
    run = get_run(run_id)
    if run.status != "running" or run.proc is None:
        return run
    run.cancel_requested = True
    _signal_run(run, signal.SIGTERM)
    kill = getattr(signal, "SIGKILL", signal.SIGTERM)
    t = threading.Timer(KILL_GRACE, lambda: run.status == "running" and _signal_run(run, kill))
    t.daemon = True
    t.start()
    return run


def cancel_all_runs() -> None:
    for run in list(_RUNS.values()):
        if run.status == "running":
            cancel_run(run.id)


# ---------------------------------------------------------------- server

class Handler(BaseHTTPRequestHandler):
    server_version = "AscendantReview/1.0"
    protocol_version = "HTTP/1.1"
    verbose = False

    def log_message(self, fmt, *args):
        if self.verbose:
            sys.stderr.write("[review] " + (fmt % args) + "\n")

    # -- helpers
    def _host_ok(self) -> bool:
        # Refuse requests addressed to any other host name (DNS-rebinding guard).
        host = (self.headers.get("Host") or "").strip().lower()
        if host.startswith("["):
            hostname = host[1:host.find("]")] if "]" in host else host
        else:
            hostname = host.rsplit(":", 1)[0] if ":" in host else host
        return hostname in ("127.0.0.1", "localhost", "::1", "")

    def _origin_ok(self) -> bool:
        # A page on another site can still POST here from the user's browser: refuse any
        # request that says it comes from somewhere other than this server's own page.
        origin = self.headers.get("Origin")
        if origin is None:
            return True
        port = self.server.server_address[1]
        return origin in (f"http://127.0.0.1:{port}", f"http://localhost:{port}", f"http://[::1]:{port}")

    def _token_ok(self) -> bool:
        got = (self.headers.get("X-Review-Token") or "").encode()
        return hmac.compare_digest(got, self.server.token.encode())

    def _send_bytes(self, status: int, body: bytes, ctype: str, extra: dict | None = None, head=False):
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        if not head:
            self.wfile.write(body)

    def _json(self, status: int, obj, head=False):
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self._send_bytes(status, body, "application/json; charset=utf-8", head=head)

    def _error(self, status: int, msg: str, head=False):
        self._json(status, {"error": msg}, head=head)

    def _send_file(self, path: Path, head=False, ctype: str | None = None):
        st = path.stat()
        size = st.st_size
        ctype = ctype or CONTENT_TYPES.get(path.suffix.lower(), "application/octet-stream")
        start, end, status = 0, size - 1, 200
        rng = self.headers.get("Range")
        if rng:
            m = re.fullmatch(r"\s*bytes=(\d*)-(\d*)\s*", rng)
            if m and (m.group(1) or m.group(2)):
                if m.group(1):
                    start = int(m.group(1))
                    end = min(int(m.group(2)), size - 1) if m.group(2) else size - 1
                else:
                    start, end = max(0, size - int(m.group(2))), size - 1
                if start >= size or start > end:
                    self.send_response(416)
                    self.send_header("Content-Range", f"bytes */{size}")
                    self.send_header("Content-Length", "0")
                    self.end_headers()
                    return
                status = 206
            # multi-range / malformed: ignore it and send the whole file (RFC 9110 allows this)
        length = max(0, end - start + 1)
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(length))
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Last-Modified", self.date_time_string(st.st_mtime))
        if status == 206:
            self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.end_headers()
        if head or length == 0:
            return
        with open(path, "rb") as f:
            f.seek(start)
            remaining = length
            while remaining > 0:
                chunk = f.read(min(65536, remaining))
                if not chunk:
                    break
                self.wfile.write(chunk)
                remaining -= len(chunk)

    # -- routes
    def _route_get(self, head=False):
        if not self._host_ok():
            return self._error(403, "forbidden host", head)
        url = urlsplit(self.path)
        path = url.path
        if path in ("/", "/index.html"):
            try:
                html = INDEX_HTML.read_text(encoding="utf-8")
            except FileNotFoundError:
                return self._error(500, f"missing {INDEX_HTML}", head)
            body = html.replace(TOKEN_SLOT, self.server.token).encode("utf-8")
            return self._send_bytes(200, body, "text/html; charset=utf-8", head=head, extra={
                "X-Frame-Options": "DENY", "Content-Security-Policy": PAGE_CSP,
                "X-Content-Type-Options": "nosniff", "Referrer-Policy": "no-referrer"})
        if path == "/api/runs":
            name = (parse_qs(url.query).get("batch") or [""])[0]
            batch_dir(name)
            return self._json(200, {"runs": [r.info() for r in runs_for(name)]}, head)
        if path.startswith("/api/run/"):
            run = get_run(unquote(path[len("/api/run/"):]).strip("/"))
            try:
                frm = int((parse_qs(url.query).get("from") or ["0"])[0])
            except ValueError:
                raise ReviewError("from must be a number")
            return self._json(200, run.info(frm), head)
        if path == "/api/batches":
            out = []
            for name in list_batch_names():
                try:
                    mb = merged_batch(name)
                    out.append({"batch": name, "title": mb["title"], "mode": mb["mode"],
                                "counts": summarize(mb["items"])})
                except ReviewError as e:
                    out.append({"batch": name, "title": name, "error": str(e)})
            return self._json(200, {"batches": out, "root": str(REVIEW)}, head)
        if path.startswith("/api/batch/"):
            name = unquote(path[len("/api/batch/"):]).strip("/")
            return self._json(200, merged_batch(name), head)
        if path == "/api/lessons":
            return self._json(200, lessons(), head)
        if path.startswith("/game/"):
            name, _, iid = path[len("/game/"):].partition("/")
            _, data = load_batch(unquote(name))
            item = next((it for it in data["items"] if it.get("id") == unquote(iid)), None)
            gp = game_path(item) if item else None
            if gp is None:
                return self._error(404, "nothing in the game for that item", head)
            return self._send_file(gp, head)
        if path.startswith("/media/"):
            rest = path[len("/media/"):]
            name, _, rel = rest.partition("/")
            d = batch_dir(unquote(name))
            p = (d / unquote(rel)).resolve()
            if d.resolve() not in p.parents or not p.is_file():
                return self._error(404, "no such file", head)
            return self._send_file(p, head)
        if path.startswith("/vendor/"):
            ## the 3D viewer's script: only a .js that sits directly in tools/review/vendor/
            name = unquote(path[len("/vendor/"):])
            ctype = VENDOR_TYPES.get(Path(name).suffix.lower())
            p = (VENDOR / name).resolve() if VENDOR_NAME_RE.match(name) else None
            if p is None or ctype is None or p.parent != VENDOR.resolve() or not p.is_file():
                return self._error(404, "no such vendored file", head)
            return self._send_file(p, head, ctype)
        if path == "/favicon.ico":
            return self._send_bytes(204, b"", "image/x-icon", head=head)
        return self._error(404, "not found", head)

    def _guard(self, fn, *a, **kw):
        try:
            fn(*a, **kw)
        except ReviewError as e:
            self._error(e.status, str(e))
        except _DROPPED:
            pass  # browsers drop media connections all the time
        except Exception as e:  # keep the server alive; report the failure
            sys.stderr.write(f"[review] error on {self.command} {self.path}: {e!r}\n")
            try:
                self._error(500, f"{type(e).__name__}: {e}")
            except Exception:
                pass

    def do_GET(self):
        self._guard(self._route_get)

    def do_HEAD(self):
        self._guard(self._route_get, head=True)

    def do_POST(self):
        self._guard(self._route_post)

    def _route_post(self):
        if not self._host_ok():
            return self._error(403, "forbidden host")
        path = urlsplit(self.path).path
        try:
            length = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            return self._error(400, "bad Content-Length")
        if length > 1_000_000:
            return self._error(413, "request too large")
        raw = self.rfile.read(length) if length > 0 else b""
        m = re.fullmatch(r"/api/run/([0-9a-f]{1,32})/cancel", path)
        if path not in ("/api/decide", "/api/run") and not m:
            return self._error(404, "not found")
        # every POST changes state: it must come from this server's own page
        if not self._origin_ok():
            return self._error(403, "cross-origin request refused")
        if not self._token_ok():
            return self._error(403, "missing or stale X-Review-Token: reload the page")
        if "application/json" not in (self.headers.get("Content-Type") or ""):
            return self._error(415, "send application/json")
        try:
            body = json.loads(raw.decode("utf-8") or "{}")
        except (UnicodeDecodeError, json.JSONDecodeError):
            return self._error(400, "body is not JSON")
        if not isinstance(body, dict):
            return self._error(400, "body must be a JSON object")
        if m:
            return self._json(200, {"ok": True, "run": cancel_run(m.group(1)).info()})
        if path == "/api/run":
            if not isinstance(body.get("batch"), str) or not isinstance(body.get("action"), str):
                return self._error(400, "need {batch, action, options?}")
            run = start_run(body["batch"], body["action"], body.get("options"))
            return self._json(200, {"ok": True, "run": run.info()})
        if not body.get("batch") or not body.get("id"):
            return self._error(400, "need {batch, id, verdict?, note?, text?, take?}")
        item = decide(str(body["batch"]), str(body["id"]),
                      verdict=body.get("verdict"), note=body.get("note"), text=body.get("text"),
                      take=body.get("take"))
        return self._json(200, {"ok": True, "item": item})


_DROPPED = (BrokenPipeError, ConnectionResetError, ConnectionAbortedError, TimeoutError)


class Server(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, *a, **kw):
        super().__init__(*a, **kw)
        # new each start: the served page carries it, every POST must echo it back
        self.token = secrets.token_urlsafe(24)

    def handle_error(self, request, client_address):
        # a browser closing an idle keep-alive or a half-read media stream is not an error
        if isinstance(sys.exc_info()[1], _DROPPED):
            return
        super().handle_error(request, client_address)


def cmd_serve(args) -> int:
    ensure_review_root()
    Handler.verbose = args.verbose
    try:
        httpd = Server(("127.0.0.1", args.port), Handler)
    except OSError as e:
        print(f"can't bind 127.0.0.1:{args.port}: {e} (another review server running? try --port)",
              file=sys.stderr)
        return 1
    url = f"http://127.0.0.1:{args.port}/"
    names = list_batch_names()
    for nm in names:
        try:
            k = reconcile(nm)
            if k:
                print(f"review: {nm}: {k} accepted take{'s' if k != 1 else ''} already in the game")
        except (OSError, ReviewError, ValueError):
            pass
    print(f"review: serving {url}  ({len(names)} batch{'es' if len(names) != 1 else ''} in {REVIEW})")
    print("review: Ctrl+C to stop", flush=True)
    if args.open:
        threading.Timer(0.4, lambda: webbrowser.open(url)).start()
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nreview: stopped")
    finally:
        cancel_all_runs()  # don't leave a generator running with nobody watching it
        httpd.server_close()
    return 0


# ---------------------------------------------------------------- status / apply / new

def _table(rows: list[list], header: list[str]) -> str:
    widths = [max(len(str(r[i])) for r in [header] + rows) for i in range(len(header))]
    fmt = lambda r: "  ".join(str(c).ljust(widths[0]) if i == 0 else str(c).rjust(widths[i])
                              for i, c in enumerate(r))
    return "\n".join(["  " + fmt(header)] + ["  " + fmt(r) for r in rows])


def cmd_status(args) -> int:
    names = [args.batch] if args.batch else list_batch_names()
    if not names:
        print(f"no batches in {REVIEW}")
        return 0
    for name in names:
        mb = merged_batch(name)
        items = mb["items"]
        groups: dict[str, list] = {}
        for it in items:
            groups.setdefault(str(it.get("group") or "-"), []).append(it)
        concept = mb["mode"] == "concept"
        header = (["group", "good", "changes", "bad", "pending", "missing", "total"] if concept
                  else ["group", "accepted", "rejected", "pending", "missing", "total"])

        def row(g, c):
            if concept:
                return [g, c["accept"], c["revise"], c["reject"], c["pending"], c["missing"], c["total"]]
            return [g, c["accept"], c["reject"], c["pending"], c["missing"], c["total"]]
        rows = [row(g, summarize(groups[g])) for g in sorted(groups)]
        c = summarize(items)
        if len(groups) > 1:
            rows.append(row("(all)", c))
        print(f"{name} — {mb['title']}   {c['reviewed']}/{c['total']} reviewed")
        print(_table(rows, header))
        if c["regenerated"]:
            print(f"  {c['regenerated']} regenerated since their verdict (counted as pending: needs a listen)")
        print()
    return 0


def _repo_target(target: str) -> Path | None:
    if not target or not isinstance(target, str) or os.path.isabs(target):
        return None
    p = (REPO / target).resolve()
    return p if REPO.resolve() in p.parents else None


def cmd_apply(args) -> int:
    name = args.batch
    d, _ = load_batch(name)
    mb = merged_batch(name)
    dry = args.dry_run
    tag = "[dry-run] " if dry else ""
    copied = unchanged = skipped = 0
    warnings: list[str] = []
    for it in mb["items"]:
        if it["verdict"] in KEPT and it["status"] == "missing":
            warnings.append(f"{it['id']}: accepted but its file is missing — skipped")
            skipped += 1
            continue
        if it["status"] not in KEPT:
            continue
        src = (d / it["src"]).resolve() if it.get("src") else item_path(d, it)
        dest = _repo_target(it.get("target"))
        if dest is None:
            warnings.append(f"{it['id']}: target {it.get('target')!r} is missing or outside the repo — skipped")
            skipped += 1
            continue
        if src.suffix.lower() != dest.suffix.lower():
            stale = dest if dest.exists() else None
            dest = dest.with_suffix(src.suffix)
            msg = (f"{it['id']}: target says {Path(it['target']).suffix} but the file is {src.suffix}; "
                   f"copying to {dest.relative_to(REPO)}")
            if stale:
                msg += f" (the old {stale.relative_to(REPO)} is still there)"
            warnings.append(msg)
        rel = dest.relative_to(REPO)
        if dest.exists() and filecmp.cmp(src, dest, shallow=False):
            unchanged += 1
            print(f"  {tag}=  {rel}  (unchanged)")
            continue
        verb = "overwrite" if dest.exists() else "new"
        print(f"  {tag}+  {rel}  ({verb})")
        if not dry:
            dest.parent.mkdir(parents=True, exist_ok=True)
            tmp = dest.with_name(f".{dest.name}.tmp")
            shutil.copy2(src, tmp)
            os.replace(tmp, dest)
        copied += 1

    rejected = rejected_entries(mb["items"], mb["mode"])
    rj = d / "rejected.json"
    if not dry:
        atomic_write_json(rj, rejected)

    c = summarize(mb["items"])
    for w in warnings:
        print(f"  ! {w}")
    revised = f", {c['revise']} good with changes" if mb["mode"] == "concept" else ""
    print(f"{tag}{name}: {'would copy' if dry else 'copied'} {copied}, unchanged {unchanged}, "
          f"skipped {skipped}  ·  {c['accept']} accepted{revised}, {c['reject']} rejected, "
          f"{c['pending']} pending, {c['missing']} missing")
    print(f"{tag}{'would write' if dry else 'wrote'} {rj.relative_to(REPO)} ({len(rejected)} to re-roll)")
    if c["regenerated"]:
        print(f"  {c['regenerated']} item(s) were regenerated after their verdict and were not applied: "
              "give them a listen first")
    return 0


def cmd_new(args) -> int:
    ensure_review_root()
    d = batch_dir(args.batch, must_exist=False)
    bj = d / "batch.json"
    if bj.exists():
        print(f"{bj.relative_to(REPO)} already exists", file=sys.stderr)
        return 1
    d.mkdir(parents=True, exist_ok=True)
    data = {"batch": args.batch, "title": args.title or args.batch}
    if args.mode != "standard":
        data["mode"] = args.mode
    atomic_write_json(bj, {**data, "items": []})
    print(f"created {bj.relative_to(REPO)} — put media next to it and list them under \"items\"")
    return 0


# ---------------------------------------------------------------- sample batch

def _write_wav(path: Path, seconds: float, base_hz: float, seed: int) -> None:
    """A soft, speech-ish babble of tone syllables so durations are real."""
    rate = 22050
    n = int(seconds * rate)
    frames = bytearray()
    syl = 0.19  # syllable length (s)
    for i in range(n):
        t = i / rate
        k = int(t / syl)
        pos = (t % syl) / syl
        # every 5th syllable is a short pause, like a word gap
        on = ((k * 7 + seed) % 5) != 0
        env = math.sin(math.pi * pos) ** 1.5 if on else 0.0
        pitch = base_hz * (1 + 0.12 * math.sin(k * 1.7 + seed))
        s = math.sin(2 * math.pi * pitch * t) + 0.3 * math.sin(4 * math.pi * pitch * t)
        fade = min(1.0, t / 0.05, (seconds - t) / 0.08)
        v = int(max(-1, min(1, 0.28 * env * s * fade)) * 32767)
        frames += struct.pack("<h", v)
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(bytes(frames))


def _say_wav(path: Path, text: str, voice: str, rate: int, pad: float = 0.0) -> bool:
    """Real spoken words for the demo, from the Mac's own voices (say + afconvert). Returns
    False where those aren't available, and the caller falls back to tone babble."""
    say, conv = shutil.which("say"), shutil.which("afconvert")
    if not say or not conv:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".aiff")
    try:
        subprocess.run([say, "-v", voice, "-r", str(rate), "-o", str(tmp), text], check=True, capture_output=True)
        subprocess.run([conv, "-f", "WAVE", "-d", "LEI16@22050", str(tmp), str(path)], check=True, capture_output=True)
    except (subprocess.CalledProcessError, OSError):
        return False
    finally:
        if tmp.exists():
            tmp.unlink()
    if pad > 0:
        ## the deliberately-too-long take: trailing dead air, as a glitchy generation might have
        with wave.open(str(path), "rb") as r:
            params, frames = r.getparams(), r.readframes(r.getnframes())
        with wave.open(str(path), "wb") as w:
            w.setparams(params)
            w.writeframes(frames + b"\x00" * int(pad * params.framerate) * params.sampwidth * params.nchannels)
    return True


def _write_png(path: Path, size: int = 128) -> None:
    """A little crest: brass disc on navy, crimson band. Pure zlib/struct."""
    rows = []
    c = (size - 1) / 2
    for y in range(size):
        row = bytearray([0])  # filter: none
        for x in range(size):
            dx, dy = (x - c) / c, (y - c) / c
            r = math.hypot(dx, dy)
            if r < 0.78:
                col = (184, 65, 47) if abs(dy) < 0.16 else (217, 178, 95)
                if 0.70 < r:
                    col = (120, 92, 40)
            elif r < 0.86:
                col = (239, 230, 207)
            else:
                col = (15, 21, 34)
            row += bytes(col) + b"\xff"
        rows.append(bytes(row))
    raw = zlib.compress(b"".join(rows), 9)

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
           + chunk(b"IDAT", raw) + chunk(b"IEND", b""))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png)


def cmd_sample(args) -> int:
    """Build the demo batches that are missing (all of them with --force): the classic one, a
    concept batch with takes from three seats, and a model batch."""
    ensure_review_root()
    built = 0
    for name, build in (("_sample", _build_sample), ("_sample_concept", _build_sample_concept),
                        ("_sample_models", _build_sample_models)):
        d = REVIEW / name
        if (d / "batch.json").exists() and not args.force:
            print(f"{d.relative_to(REPO)} already exists (use --force to rebuild it; this clears its verdicts)")
            continue
        if d.exists():
            shutil.rmtree(d)
        build(d)
        built += 1
    return 0 if built else 1


def _build_sample(d: Path) -> None:
    out = "review/_sample/out"
    items = [
        ("herald.capture.v1", "audio", "herald", "capture · variant 1", "Another land for the crown!",
         "herald/capture_v1.wav", f"{out}/voice/herald/capture_v1.mp3", 2.2, 220,
         {"voice": "voice_herald", "context": "we took a land"}),
        ("herald.loss.v1", "audio", "herald", "loss · variant 1", "We have lost the river crossing, my lord.",
         "herald/loss_v1.wav", f"{out}/voice/herald/loss_v1.wav", 3.0, 200,
         {"voice": "voice_herald", "context": "an enemy took one of our lands"}),
        ("herald.victory.v1", "audio", "herald", "victory · variant 1", "The kingdom endures. Glory to the crown!",
         "herald/victory_v1.wav", f"{out}/voice/herald/victory_v1.wav", 2.8, 240,
         {"voice": "voice_herald", "context": "we won the match"}),
        ("fang.taunt.v1", "audio", "fang", "taunt · variant 1", "Your walls will not hold.",
         "fang/taunt_v1.wav", f"{out}/voice/fang/taunt_v1.wav", 9.0, 130,
         {"voice": "voice_fang", "context": "the Fang chieftain attacks one of your forts"}),
        ("fang.defeat.v1", "audio", "fang", "defeat · variant 1", "This is not over.",
         "fang/defeat_v1.wav", f"{out}/voice/fang/defeat_v1.wav", None, 0,
         {"voice": "voice_fang", "context": "the Fang chieftain is eliminated"}),
        ("ever.greet.v1", "audio", "ever", "greeting · variant 1",
         "The Ever Court stands ready to march at your command.",
         "ever/greet_v1.wav", f"{out}/voice/ever/greet_v1.wav", 1.2, 160,
         {"voice": "voice_ever", "context": "the Ever Regent is chosen as an ally"}),
    ]
    ## spoken by the Mac's own voices where it has them: (voice, words per minute, dead air)
    speak = {"herald.capture.v1": ("Daniel", 170, 0), "herald.loss.v1": ("Daniel", 165, 0),
             "herald.victory.v1": ("Daniel", 170, 0), "fang.taunt.v1": ("Daniel", 120, 6.5),
             "ever.greet.v1": ("Daniel", 520, 0)}
    batch_items = []
    for i, (iid, kind, group, label, text, f, target, secs, hz, meta) in enumerate(items):
        if secs:
            v = speak.get(iid)
            if not (v and _say_wav(d / f, text, v[0], v[1], v[2])):
                _write_wav(d / f, secs, hz, seed=i)
        batch_items.append({"id": iid, "kind": kind, "group": group, "label": label, "text": text,
                            "file": f, "target": target, "meta": meta})
    _write_png(d / "images" / "crest.png")
    batch_items.append({"id": "icon.crest.v1", "kind": "image", "group": "icons", "label": "crest · variant 1",
                        "text": "a brass royal crest with a crimson band, flat, on navy",
                        "file": "images/crest.png", "target": f"{out}/icons/crest.png",
                        "meta": {"context": "HUD faction badge"}})
    ruler = REPO / "assets" / "portraits" / "rulers" / "aurel_king.webp"
    if ruler.is_file():
        shutil.copy2(ruler, d / "images" / "aurel_king.webp")
        batch_items.append({"id": "portrait.aurel_king.v1", "kind": "image", "group": "icons",
                            "label": "Aurel king · variant 1",
                            "text": "a crowned king in gilded armour, painterly",
                            "file": "images/aurel_king.webp", "target": f"{out}/portraits/aurel_king.webp",
                            "meta": {"context": "the ruler portrait on the setup screen"}})
    atomic_write_json(d / "batch.json", {"batch": "_sample", "title": "Sample batch (demo)", "items": batch_items})
    print(f"built {d.relative_to(REPO)} with {len(batch_items)} items "
          "(one file deliberately missing, one line far too long, one too short)")


def _write_emblem(path: Path, shape: str, base: tuple, accent: tuple, size: int = 192) -> None:
    """A little painted crest for the concept demo: a shape on a gradient, in the colours of a seat's take."""
    rows = []
    c = (size - 1) / 2
    for y in range(size):
        row = bytearray([0])
        for x in range(size):
            dx, dy = (x - c) / c, (y - c) / c
            k = y / size
            col = tuple(int(b * (0.55 + 0.45 * k)) for b in base)
            if shape == "disc":
                inside, ring = math.hypot(dx, dy) < 0.62, 0.52 < math.hypot(dx, dy) < 0.62
            elif shape == "diamond":
                inside, ring = abs(dx) + abs(dy) < 0.72, 0.60 < abs(dx) + abs(dy) < 0.72
            elif shape == "shield":
                def shield(w):  # a flat top, straight sides, a pointed foot
                    return abs(dx) < w and -w - 0.07 < dy < w + 0.05 and (dy < 0.05 or abs(dx) < w - (dy - 0.05))
                inside = shield(0.58)
                ring = inside and not shield(0.46)
            else:  # tower
                inside = (abs(dx) < 0.28 and -0.6 < dy < 0.6) or (abs(dx) < 0.5 and 0.35 < dy < 0.6) \
                    or (abs(dx) < 0.4 and -0.78 < dy < -0.6 and int((dx + 0.4) * 10) % 2 == 0)
                ring = False
            if inside:
                col = tuple(int(a * 0.55) for a in accent) if ring else accent
            row += bytes(col) + b"\xff"
        rows.append(bytes(row))
    raw = zlib.compress(b"".join(rows), 9)

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
                     + chunk(b"IDAT", raw) + chunk(b"IEND", b""))


def _build_sample_models(d: Path) -> None:
    """Two of the repo's ruler models as candidates, each with a different model as "what the game has
    now" (a copy under the batch's own out/ folder, so installing the sample touches nothing real)."""
    src = REPO / "assets" / "models" / "rulers"
    #       candidate,                   what the game has now,   item id
    spec = [("aurel_king_march.glb", "aurel_king_ready.glb", "aurel_king"),
            ("fang_chieftain_strike.glb", "fang_chieftain_march.glb", "fang_chieftain")]
    items = []
    for cand, game, iid in spec:
        if not (src / cand).is_file() or not (src / game).is_file():
            continue
        (d / "rulers").mkdir(parents=True, exist_ok=True)
        (d / "out" / "rulers").mkdir(parents=True, exist_ok=True)
        shutil.copy2(src / cand, d / "rulers" / f"{iid}.glb")
        shutil.copy2(src / game, d / "out" / "rulers" / f"{iid}.glb")
        items.append({"id": f"{iid}.v2", "kind": "model", "group": "rulers", "label": f"{iid.replace('_', ' ')} · new pose",
                      "text": "a ruler in a new pose, to replace the one in the game",
                      "file": f"rulers/{iid}.glb", "target": f"review/_sample_models/out/rulers/{iid}.glb",
                      "meta": {"context": "the ruler model on the 3D board"}})
    d.mkdir(parents=True, exist_ok=True)
    atomic_write_json(d / "batch.json", {"batch": "_sample_models", "title": "Sample model batch (demo)", "items": items})
    print(f"built {d.relative_to(REPO)} with {len(items)} model{'s' if len(items) != 1 else ''} "
          "(drag to turn, scroll to zoom, 0 shows what the game has now)")


def _build_sample_concept(d: Path) -> None:
    """Crests from three art seats, to be judged blind. Their groups start with `sample_`, so what
    `canon` writes for them (assets/_concept/lore/sample_*/) is easy to tell and to delete."""
    prompt = "a heraldic crest for {who}, flat bright cel shading on a plain ground, no text"
    #       item id,   label,           group,         seat takes: (seat, shape, base colour, accent colour)
    spec = [
        ("aurel_crest", "Aurel crest", "sample_aurel", "the Aurel kingdom, gold and royal blue",
         [("codex", "shield", (28, 44, 96), (226, 184, 82)), ("grok", "disc", (36, 52, 110), (240, 208, 120)),
          ("claude", "diamond", (22, 38, 84), (212, 168, 70))]),
        ("fang_banner", "Fang banner", "sample_fang", "the Fang clans, ember red and bone white",
         [("grok", "diamond", (96, 28, 24), (236, 224, 200)), ("codex", "shield", (110, 36, 28), (244, 232, 210))]),
        ("ever_sigil", "Ever sigil", "sample_ever", "the Ever Court, moss green and silver",
         [("claude", "disc", (30, 74, 58), (214, 224, 220))]),
        ("thornmane_mark", "Thornmane mark", "sample_ever", "Thornmane, thorn brown and amber",
         [("codex", "tower", (70, 46, 28), (232, 170, 70))]),
    ]
    items = []
    for iid, label, group, who, takes in spec:
        files = []
        for seat, shape, base, accent in takes:
            f = f"{seat}/{iid}.png"
            _write_emblem(d / f, shape, base, accent)
            files.append((seat, f))
        item = {"id": iid, "kind": "image", "group": group, "label": label, "text": prompt.format(who=who),
                "file": files[0][1], "seat": files[0][0], "meta": {"context": "round 1 crest sketches"}}
        if len(files) > 1:
            item["takes"] = [{"file": f, "label": f"take {i + 2}", "seat": seat} for i, (seat, f) in enumerate(files[1:])]
        items.append(item)
    atomic_write_json(d / "batch.json", {"batch": "_sample_concept", "title": "Sample concept batch (demo)",
                                         "mode": "concept", "items": items})
    print(f"built {d.relative_to(REPO)} with {len(items)} items: crests from three seats, to judge blind "
          "(A good, C good with changes, R bad)")


# ---------------------------------------------------------------- main

def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="review.py", description="Accept/reject review for generated assets.")
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("serve", help="serve the review UI on 127.0.0.1")
    p.add_argument("--port", type=int, default=8766)
    p.add_argument("--open", action="store_true", help="open the UI in your browser")
    p.add_argument("--verbose", action="store_true", help="log every request")
    p.set_defaults(fn=cmd_serve)
    p = sub.add_parser("status", help="counts per verdict per group")
    p.add_argument("batch", nargs="?")
    p.set_defaults(fn=cmd_status)
    p = sub.add_parser("apply", help="copy accepted files to their targets; write rejected.json")
    p.add_argument("batch")
    p.add_argument("--dry-run", action="store_true")
    p.set_defaults(fn=cmd_apply)
    p = sub.add_parser("reconcile", help="mark accepted takes whose installed copies already match as in the game")
    p.add_argument("batch", nargs="?")
    p.set_defaults(fn=lambda a: (print("\n".join(f"{nm}: {reconcile(nm)} marked in game" for nm in ([a.batch] if a.batch else list_batch_names()))) or 0))
    p = sub.add_parser("lessons", help="what every review so far says about the prompts")
    p.add_argument("--write", metavar="MD", help="replace the lessons block in this markdown file (docs/PROMPTING.md)")
    p.add_argument("--json", action="store_true")
    p.set_defaults(fn=cmd_lessons)
    p = sub.add_parser("new", help="scaffold an empty batch")
    p.add_argument("batch")
    p.add_argument("--title", default="")
    p.add_argument("--mode", choices=MODES, default="standard", help="concept: judged Good / Good with changes / Bad")
    p.set_defaults(fn=cmd_new)
    p = sub.add_parser("sample", help="build the demo batches (_sample, _sample_concept)")
    p.add_argument("--force", action="store_true")
    p.set_defaults(fn=cmd_sample)
    args = ap.parse_args(argv)
    try:
        return args.fn(args)
    except ReviewError as e:
        print(f"review: {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
