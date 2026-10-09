#!/usr/bin/env python3
"""base_gate: the base-first review gate of the Ludo model pipeline (issue #179).

Every pose (march, strike, fallen) and every transformation look in the pipeline is an edit of a unit's ready picture,
the base. A wrong base spreads into every picture and model made from it (Alex 10-8: the Slinger's and the Sunspear's
bases were off, "and everything derived from them too"). So a family is made in two stages:

  base    the ready picture only, a few takes, into a concept batch `review/<batch>_base/` (Good / Good with
          changes / Bad in the Review Table, tools/review/README.md);
  derive  the other poses, the looks and the models, made only from a base Alex marked Good (or Good with changes,
          after a redo: the picture was redone and he looked at it again).

This module is the refusal. It reads the base batch's `review.json` through the Review Table's own status logic
(tools/review/review.py merge_item), so "accepted" means what the table means: a verdict, not regenerated since, on
an item whose file is there. Pure stdlib, no Ludo, no Godot; the batch scripts (asc_3d_grok.py, asc_3d_free_holds.py)
call `Gate.require_all(families)` before they submit a derive stage and `Gate.require(family)` before every derived
row.

    gate = base_gate.Gate("m4_redo_base", display=lambda f: "Sunspears", grandfathered={...})
    gate.require("sunspears")      # raises BaseNotAccepted("Sunspears: the base picture is waiting for Alex's ...")

States of a base (`gate.check(family)["state"]`):

    accepted             Good (accept): derive from the take he kept (`file`)
    accepted_after_redo  Good with changes (revise) on a picture that was redone and looked at again (the verdict has a
                         history: an earlier verdict on the old picture): derive from it, the note is his to follow up
    grandfathered        a family whose base Alex accepted before this gate existed (the ready model's accept in the
                         batch that built it); the script's table records which verdict. If that batch's review.json
                         is here and now says otherwise, the family is refused ("withdrawn")
    revise               Good with changes and not redone yet: the note is still to apply, refused
    pending              no verdict yet, or the picture was regenerated after it (it needs another look): refused
    rejected             Bad: refused until it is redone and accepted
    missing              the batch has the item but not its file: refused
    no_item / no_batch   nothing to review yet: refused, with how to make the base

`ASC_REVIEW_DIR` (an environment variable) names another folder of batches than `<repo>/review`; the tests use a
temporary one.
"""
from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
OK_STATES = ("accepted", "accepted_after_redo", "grandfathered")


class BaseNotAccepted(RuntimeError):
    """A derive stage was asked for a family whose base Alex has not accepted. The message is plain and names the
    family: it is what the script prints before it stops."""


def review_root() -> Path:
    env = os.environ.get("ASC_REVIEW_DIR")
    return Path(env) if env else ROOT / "review"


def _review_module():
    """tools/review/review.py (its status logic is the Review Table's own)."""
    p = str(ROOT / "tools" / "review")
    if p not in sys.path:
        sys.path.insert(0, p)
    import review  # noqa: E402
    return review


def _read(path: Path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def item_status(batch: str, item_id: str, root: Path | None = None) -> dict:
    """One item of review/<batch>, as the Review Table sees it: {state, file, note, status, verdict, redone}.
    `state` is one of accepted, accepted_after_redo, revise, pending, rejected, missing, no_item, no_batch;
    `file` is the path of the take the verdict is about (when it is there)."""
    d = Path(root or review_root()) / batch
    data = _read(d / "batch.json")
    if not isinstance(data, dict) or not isinstance(data.get("items"), list):
        return {"state": "no_batch", "file": None, "note": "", "status": None, "verdict": None, "redone": False}
    item = next((it for it in data["items"] if isinstance(it, dict) and it.get("id") == item_id), None)
    if item is None:
        return {"state": "no_item", "file": None, "note": "", "status": None, "verdict": None, "redone": False}
    rv = _read(d / "review.json")
    entries = rv.get("items") if isinstance(rv, dict) and isinstance(rv.get("items"), dict) else {}
    m = _review_module().merge_item(batch, d, item, entries.get(item_id), data.get("mode") or "standard")
    status = m["status"]
    redone = bool(m.get("history"))
    state = {"accept": "accepted", "reject": "rejected", "pending": "pending", "missing": "missing"}.get(status)
    if status == "revise":
        state = "accepted_after_redo" if redone else "revise"
    if state in ("accepted", "accepted_after_redo") and not m["exists"]:
        state = "missing"
    src = (d / m["src"]) if m.get("src") else None
    return {"state": state, "file": src if src is not None and m["exists"] else None, "note": m.get("note") or "",
            "status": status, "verdict": m.get("verdict"), "redone": redone,
            "regenerated": bool(m.get("regenerated"))}


class Gate:
    """The gate of one batch script: `batch` is the base batch (`review/<batch>/`, a concept batch with one item per
    family, `item_of(family)` its id), `display(family)` the name the messages use, and `grandfathered` maps a family
    to the verdict that stands for its base, {"batch", "item", "at"} (a base Alex accepted before the gate)."""

    def __init__(self, batch: str, display=None, item_of=None, grandfathered: dict | None = None,
                 root: Path | None = None):
        self.batch = batch
        self.display = display or (lambda family: family.replace("_", " ").title())
        self.item_of = item_of or (lambda family: "%s_ready" % family)
        self.grandfathered = dict(grandfathered or {})
        self.root = root  # None: review_root() when asked (the environment may change between calls)

    # -------------------------------------------------------------------------------- one family
    def check(self, family: str) -> dict:
        """The family's base: {ok, state, family, file, note, message}. Never raises."""
        g = self.grandfathered.get(family)
        if g is not None:
            return self._finish(family, self._grandfathered(g))
        return self._finish(family, item_status(self.batch, self.item_of(family), self.root))

    def _grandfathered(self, g: dict) -> dict:
        """A recorded verdict stands unless the batch it was given in is here and says it is no longer Good."""
        rv = _read(Path(self.root or review_root()) / g["batch"] / "review.json")
        entries = rv.get("items") if isinstance(rv, dict) and isinstance(rv.get("items"), dict) else {}
        e = entries.get(g["item"])
        if isinstance(e, dict) and e.get("verdict") not in (None, "accept"):
            return {"state": "withdrawn", "file": None, "note": e.get("note") or "", "verdict": e.get("verdict")}
        return {"state": "grandfathered", "file": None, "note": "", "verdict": "accept"}

    def _finish(self, family: str, st: dict) -> dict:
        out = dict(st, family=family, ok=st["state"] in OK_STATES)
        out["message"] = "" if out["ok"] else self.message(family, st)
        return out

    def message(self, family: str, st: dict) -> str:
        name = self.display(family)
        where = "review/%s/" % self.batch
        item = self.item_of(family)
        note = (" His note: \"%s\"" % st["note"]) if st.get("note") else ""
        s = st["state"]
        tail = (" Poses, looks and models are only made from a base he marked Good (or Good with changes, after a "
                "redo).")
        if s == "no_batch":
            return ("%s: there is no base picture to build from yet (%s is not made). Make the base first and have "
                    "Alex review it in the Review Table.%s" % (name, where, tail))
        if s == "no_item":
            return ("%s: the base batch %s has no item %s. Make the base first and have Alex review it.%s"
                    % (name, where, item, tail))
        if s == "pending":
            why = ("the base picture was redone after his verdict and needs another look"
                   if st.get("regenerated") else "the base picture is waiting for Alex's verdict")
            return "%s: %s (%s, item %s).%s" % (name, why, where, item, tail)
        if s == "revise":
            return ("%s: the base picture was marked Good with changes and has not been redone yet (%s, item %s).%s "
                    "Redo the base, then have him look again.%s" % (name, where, item, note, tail))
        if s == "rejected":
            return ("%s: the base picture was marked Bad (%s, item %s).%s Redo the base and have him look again.%s"
                    % (name, where, item, note, tail))
        if s == "missing":
            return "%s: the base picture's file is missing from %s (item %s).%s" % (name, where, item, tail)
        if s == "withdrawn":
            g = self.grandfathered[family]
            return ("%s: its base was accepted in %s (%s), but that verdict now says %s.%s Have the base reviewed "
                    "again.%s" % (name, g["batch"], g["item"], st.get("verdict"), note, tail))
        return "%s: the base is not accepted.%s" % (name, tail)

    def require(self, family: str) -> dict:
        """check(), and BaseNotAccepted (the plain message) when the base is not accepted."""
        r = self.check(family)
        if not r["ok"]:
            raise BaseNotAccepted(r["message"])
        return r

    def require_all(self, families) -> dict:
        """require() for each of the families, in order; every family that fails is named in the one error. Returns
        {family: check result}."""
        results, bad = {}, []
        for f in dict.fromkeys(families):
            results[f] = self.check(f)
            if not results[f]["ok"]:
                bad.append(results[f]["message"])
        if bad:
            raise BaseNotAccepted("\n".join(bad))
        return results


# ---------------------------------------------------------------------------------------- the base batch
def write_base_batch(batch: str, title: str, items: list, actions: list, convert=None, root: Path | None = None) -> int:
    """review/<batch>/ as a concept batch (Good / Good with changes / Bad) of base pictures, one item per family.
    `items`: [{id, label, group, text, target, meta, sources}], `sources` the candidate pictures, take 1 first; each is
    copied (through `convert(src, dst)`, a plain copy by default) to `<group as a folder name>/<id>_c<k>.webp`, `k` the number in the
    candidate's name (`..._c2.webp`), take 1 being the item's own file and the rest its `takes`. A file is rewritten
    only when its source is newer, so building again never puts an unchanged item back in the review queue; a redone
    picture is newer and does ("needs another look"). The batch's review.json is never touched. Returns the item count."""
    import shutil
    d = Path(root or review_root()) / batch
    d.mkdir(parents=True, exist_ok=True)
    convert = convert or shutil.copy2
    out = []
    for it in items:
        files = []
        for src in it["sources"]:
            k = os.path.basename(src).rsplit("_c", 1)[1].split(".")[0]
            rel = "%s/%s_c%s.webp" % (re.sub(r"[^a-z0-9_]+", "_", it["group"].lower()).strip("_"), it["id"], k)
            dst = d / rel
            if not (dst.exists() and dst.stat().st_mtime >= os.path.getmtime(src)):
                dst.parent.mkdir(parents=True, exist_ok=True)
                convert(src, str(dst))
            files.append((rel, k))
        item = {"id": it["id"], "kind": "image", "group": it["group"], "label": it["label"], "text": it["text"],
                "file": files[0][0], "target": it["target"], "meta": it.get("meta") or {},
                "take_label": "take 1 (candidate %s)" % files[0][1]}
        if len(files) > 1:
            item["takes"] = [{"file": f, "label": "take %d (candidate %s)" % (i + 2, k)}
                             for i, (f, k) in enumerate(files[1:])]
        out.append(item)
    data = {"batch": batch, "title": title, "mode": "concept", "items": out, "actions": actions}
    tmp = d / "batch.json.tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=1)
        f.write("\n")
    os.replace(tmp, d / "batch.json")
    return len(out)
