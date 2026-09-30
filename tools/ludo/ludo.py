#!/usr/bin/env python3
"""Generate CONCURRENT art + audio with the Ludo.ai API.

    python3 tools/ludo/ludo.py                 # everything missing in manifest.json
    python3 tools/ludo/ludo.py icon_attack     # just these ids (regenerates if --force)
    python3 tools/ludo/ludo.py --force id ...
    python3 tools/ludo/ludo.py --jobs 8 id ...   # a pool of 8 jobs in flight instead of one per lane
    python3 tools/ludo/ludo.py --account         # the credit balance (free)
    python3 tools/ludo/ludo.py --takes 3 id ...  # speech/voice/sfx: 3 takes (extras in .takes/)

Reads LUDO_API_KEY from the environment or .env.local. Idempotent: an asset whose
output file exists is skipped, and every job carries a stable request_id so a
retried submit returns the original job instead of charging twice.
Stdlib only. One worker per Ludo endpoint (the beta allows one in-flight job each), or
--jobs N: a pool that starts assets in manifest order (so a dependency always starts
before whatever waits on it).

Kinds: image, edit, styled, animate, sfx, music (optional `lyrics`), ambiance, voice,
speech, and since v1.9: keyframes (first/middle/last frames), transfer (motion preset),
sprite_edit (edit_mode prompt/outpaint/fix_loop on a sheet made in the last 7 days),
pose, rotate, video (image to video; final_same makes a loop), video_refs (a shot from
reference images), upscale (2x a video), model3d (image to GLB + snapshots) and
audio_transform (a remix of a local clip). Sprite kinds take `model: hydra` (its sound
track is saved as <out>_audio.mp3) and `gif: true` (saved as <out>_anim.gif). Every
charged call, cut-outs included, is summed into the ledger entry's credits (`calls`
lists them). Local animation inputs over 1 megapixel are downscaled before upload.
"""
import json
import os
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
API = "https://api.ludo.ai/api"
MANIFEST = os.path.join(os.path.dirname(__file__), "manifest.json")
LEDGER = os.path.join(ROOT, "assets", "ludo_ledger.json")
_ledger_lock = threading.Lock()
_print_lock = threading.Lock()


def log(*parts):
    with _print_lock:
        print(time.strftime("%H:%M:%S"), *parts, flush=True)


def api_key():
    key = os.environ.get("LUDO_API_KEY", "")
    if key:
        return key
    env = os.path.join(ROOT, ".env.local")
    if os.path.exists(env):
        for line in open(env):
            if line.startswith("LUDO_API_KEY="):
                return line.split("=", 1)[1].strip().strip('"')
    sys.exit("LUDO_API_KEY not set")


KEY = None


def call(method, path, body=None, timeout=90):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(API + path, data=data, method=method)
    req.add_header("Authorization", "ApiKey " + KEY)
    req.add_header("Content-Type", "application/json")
    for attempt in range(40):
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                raw = r.read()
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as e:
            msg = e.read().decode(errors="replace")
            ## a rate limit only means "slow down": keep waiting (a job already running must not be
            ## abandoned); server errors get the old five retries
            if (e.code == 429 and attempt < 39) or (e.code in (500, 502, 503, 504) and attempt < 5):
                if attempt % 4 == 0:
                    log("  retry", path, e.code, msg[:80])
                import random
                time.sleep(min(60, 10 * (attempt + 1)) + random.uniform(0, 10))
                continue
            raise RuntimeError("%s %s -> %s %s" % (method, path, e.code, msg[:400]))
        except (urllib.error.URLError, TimeoutError, OSError) as e:  ## OSError: dropped TLS records too
            if attempt < 5:
                time.sleep(5 * (attempt + 1))
                continue
            raise


def run_job(endpoint, params, request_id):
    body = dict(params)
    body["request_id"] = request_id
    job = call("POST", endpoint, body)
    jid = job["id"]
    while True:
        status = job.get("status")
        if status == "succeeded":
            return job
        if status in ("failed", "canceled"):
            raise RuntimeError("job %s %s: %s" % (jid, status, job.get("error")))
        job = call("GET", "/assets/jobs/%s?wait=55" % jid, timeout=90)


def result_urls(result):
    if isinstance(result, list):
        return [r["url"] for r in result if isinstance(r, dict) and r.get("url")]
    if isinstance(result, dict):
        if result.get("url"):
            return [result["url"]]
        for k in ("results", "images", "audio"):
            if isinstance(result.get(k), list):
                return result_urls(result[k])
    return []


def download(url, dest):
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    tmp = dest + ".part"
    with urllib.request.urlopen(url, timeout=120) as r, open(tmp, "wb") as f:
        f.write(r.read())
    os.replace(tmp, dest)


def ext_of(url, fallback):
    tail = url.split("?")[0].rsplit(".", 1)
    return "." + tail[1].lower() if len(tail) == 2 and len(tail[1]) <= 4 else fallback


def sniff(path):
    """Ludo sometimes names a WAV '.mp3'. Trust the bytes, not the URL."""
    with open(path, "rb") as f:
        head = f.read(16)
    if head[:4] == b"RIFF" and head[8:12] == b"WAVE":
        return ".wav"
    if head[:4] == b"RIFF" and head[8:12] == b"WEBP":
        return ".webp"
    if head[:8] == b"\x89PNG\r\n\x1a\n":
        return ".png"
    if head[:3] == b"ID3" or head[:2] in (b"\xff\xfb", b"\xff\xf3", b"\xff\xf2"):
        return ".mp3"
    if head[:4] == b"OggS":
        return ".ogg"
    if head[4:8] == b"ftyp":
        return ".mp4"
    if head[:4] == b"glTF":
        return ".glb"
    if head[:6] in (b"GIF87a", b"GIF89a"):
        return ".gif"
    if head[:3] == b"\xff\xd8\xff":
        return ".jpg"
    return None


def record(entry):
    ## two generator runs may share the ledger: lock across processes too
    import fcntl
    with _ledger_lock, open(LEDGER + ".lock", "w") as lk:
        fcntl.flock(lk, fcntl.LOCK_EX)
        led = {}
        if os.path.exists(LEDGER):
            led = json.load(open(LEDGER))
        old = led.get(entry["id"])
        if old and old.get("job") != entry.get("job"):
            ## a re-roll: keep what the earlier takes cost, so the ledger still adds up
            hist = old.pop("history", [])
            hist.append({k: old.get(k) for k in ("v", "job", "credits", "url", "endpoint")})
            entry["history"] = hist
        led[entry["id"]] = entry
        tmp = LEDGER + ".tmp"
        json.dump(led, open(tmp, "w"), indent=1, sort_keys=True)
        os.replace(tmp, LEDGER)


MANIFEST_V = {}
FAILED = set()  ## ids that failed in this run: whatever waits on them fails at once


def ledger_url(aid, key="url", wait=2400):
    """URL a finished asset was served from; waits for another lane to finish the
    version this manifest asks for (a re-themed portrait must not edit its old self)."""
    t0 = time.time()
    need = MANIFEST_V.get(aid, 1)
    while True:
        with _ledger_lock:
            led = json.load(open(LEDGER)) if os.path.exists(LEDGER) else {}
        if aid in led and led[aid].get(key) and int(led[aid].get("v", 1)) >= need:
            return led[aid][key]
        if aid in FAILED:
            raise RuntimeError("dependency %s failed" % aid)
        if time.time() - t0 > wait:
            raise RuntimeError("dependency %s never finished" % aid)
        time.sleep(5)


def existing(out_base):
    d = os.path.dirname(out_base)
    b = os.path.basename(out_base)
    if not os.path.isdir(d):
        return None
    for f in os.listdir(d):
        if f.startswith(b + ".") and not f.endswith((".part", ".import", ".json")):
            return os.path.join(d, f)
    return None


def ledger_v(aid):
    with _ledger_lock:
        led = json.load(open(LEDGER)) if os.path.exists(LEDGER) else {}
    return int(led[aid].get("v", 1)) if aid in led else 0


MIME = {".png": "image/png", ".webp": "image/webp", ".jpg": "image/jpeg", ".jpeg": "image/jpeg",
        ".mp3": "audio/mpeg", ".wav": "audio/wav", ".ogg": "audio/ogg", ".m4a": "audio/mp4"}


def image_size(path):
    out = subprocess.run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", path], capture_output=True, text=True).stdout
    w = int(out.split("pixelWidth:")[1].split()[0])
    h = int(out.split("pixelHeight:")[1].split()[0])
    return w, h


def fit_megapixel(path, limit=1000000):
    """Animation inputs must be under 1 MP: a bigger local image goes up as a scaled PNG copy."""
    w, h = image_size(path)
    if w * h < limit:
        return path
    s = (limit * 0.98 / float(w * h)) ** 0.5
    nw, nh = int(w * s) // 2 * 2, int(h * s) // 2 * 2
    tmp = os.path.join(tempfile.gettempdir(), "ludo_fit_%d_%s.png" % (os.getpid(), os.path.basename(path).rsplit(".", 1)[0]))
    subprocess.run(["sips", "-s", "format", "png", "-z", str(nh), str(nw), path, "--out", tmp], capture_output=True, check=True)
    log("  downscaled %s %dx%d -> %dx%d (1 MP limit)" % (os.path.relpath(path, ROOT), w, h, nw, nh))
    return tmp


def local_image(rel, fit=False):
    """A local file as a base64 data URI (for inputs we prepared ourselves)."""
    import base64
    path = os.path.join(ROOT, rel)
    mime = MIME.get(os.path.splitext(path)[1].lower(), "image/webp")
    if fit:
        path = fit_megapixel(path)
        mime = MIME.get(os.path.splitext(path)[1].lower(), mime)
    return "data:%s;base64,%s" % (mime, base64.b64encode(open(path, "rb").read()).decode())


def source(asset, key="from", fit=False):
    if asset.get(key + "_file"):
        return local_image(asset[key + "_file"], fit)
    return ledger_url(asset[key])


def refs(asset, key="refs"):
    """A list of reference images: local files (paths with a '/') or ledger ids."""
    return [local_image(r) if "/" in r else ledger_url(r) for r in asset.get(key, [])]


def charged(calls, endpoint, job):
    calls.append({"endpoint": endpoint, "job": job.get("id"), "credits": job.get("credits_charged") or 0})


def sprite_params(asset, params):
    """The shared knobs of the animation endpoints."""
    for k in ("crop", "margin_ratio_mode", "margin_ratio_horizontal", "margin_ratio_vertical", "augment_prompt", "gif"):
        if k in asset:
            params[k] = asset[k]
    if asset.get("with_background"):
        params["spritesheet_with_background"] = True
    return params


def sheet_result(asset, res, out_base, downloads):
    url = res.get("spritesheet_with_background_url") if asset.get("with_background") and res.get("spritesheet_with_background_url") else res["spritesheet_url"]
    if res.get("audio_url"):
        downloads.append((res["audio_url"], out_base + "_audio.mp3"))
    if res.get("gif_url"):
        downloads.append((res["gif_url"], out_base + "_anim.gif"))
    if asset.get("keep_video") and res.get("video_url"):
        downloads.append((res["video_url"], out_base + "_video.mp4"))
    extra = {"cols": res.get("num_cols"), "rows": res.get("num_rows"), "frames": res.get("num_frames"),
             "duration": res.get("duration")}
    return url, extra


def spoken(asset):
    """What the voice is asked to say: `speak` when set (the words plus performance marks a
    review note asked for: pauses, *stress*), else the line's `text` (its subtitle)."""
    return asset.get("speak") or asset["text"]


TAKE_KINDS = ("speech", "voice", "sfx")


def take_out(out, k):
    """Take k (2, 3, ...) of an asset sits beside it: <dir>/.takes/<name>.t<k>.<ext>."""
    return os.path.join(os.path.dirname(out), ".takes", "%s.t%d" % (os.path.basename(out), k))


def with_takes(assets, n=None):
    """Every speech, voice or sfx asset plus its extra takes (`takes` in the manifest, or
    --takes N for this run): the same prompt rolled again under its own id `<id>~t<k>`, so each
    take has its own request id and ledger entry and a rerun skips the takes already made."""
    out = []
    for a in assets:
        out.append(a)
        k_max = int(n if n is not None else a.get("takes", 1))
        if a.get("kind") not in TAKE_KINDS or "~t" in a["id"]:
            continue
        for k in range(2, k_max + 1):
            t = dict(a, id="%s~t%d" % (a["id"], k), out=take_out(a["out"], k))
            MANIFEST_V[t["id"]] = int(a.get("v", 1))
            out.append(t)
    return out


def build(asset, style, force):
    aid = asset["id"]
    out_base = os.path.join(ROOT, asset["out"])
    have = existing(out_base)
    ver = asset.get("v", 1)
    if have and not force and ledger_v(aid) >= ver:
        return
    kind = asset["kind"]
    rid = "concurrent-%s-v%s" % (aid, ver)
    t0 = time.time()
    extra = {}
    calls = []
    downloads = []  ## (url, path) side files: sound tracks, gif previews, snapshots
    if kind == "edit":
        src = source(asset)
        params = {"image": src, "prompt": asset["prompt"], "n": 1, "augment_prompt": asset.get("augment", True)}
        job = run_job("/assets/image/edit", params, rid)
        charged(calls, "/assets/image/edit", job)
        url = result_urls(job["result"])[0]
        if asset.get("cutout"):
            cut = run_job("/assets/image/remove-background",
                          {"image": url, "crop": True, "creative_edit": False}, rid + "-cut")
            charged(calls, "/assets/image/remove-background", cut)
            url = result_urls(cut["result"])[0]
        endpoint = "/assets/image/edit"
    elif kind == "animate":
        src = source(asset, fit=asset.get("fit", False))
        params = {"initial_image": src, "motion_prompt": asset["prompt"], "model": asset.get("model", "forge"),
                  "duration": asset.get("duration", 2), "frames": asset.get("frames", 16),
                  "frame_size": asset.get("frame_size", 128), "loop": asset.get("loop", False),
                  "image_type": asset.get("image_type", "sprite")}
        if asset.get("final_same"):
            params["final_image"] = src  ## the loop ends where it began: no reset jump
        elif asset.get("final") or asset.get("final_file"):
            params["final_image"] = source(asset, "final")  ## ends on a known pose
        for k in ("crop", "margin_ratio_mode"):
            if k in asset:
                params[k] = asset[k]
        if asset.get("with_background"):
            params["spritesheet_with_background"] = True
        sprite_params(asset, params)
        job = run_job("/assets/sprite/animate", params, rid)
        charged(calls, "/assets/sprite/animate", job)
        res = job["result"]
        url, extra = sheet_result(asset, res, out_base, downloads)
        if not asset.get("gif") and not res.get("audio_url"):
            extra = {"cols": res.get("num_cols"), "rows": res.get("num_rows"), "frames": res.get("num_frames")}
        endpoint = "/assets/sprite/animate"
    elif kind == "voice":
        params = {"voice_description": asset["describe"], "text": spoken(asset), "type": "human",
                  "augment_prompt": asset.get("augment", True)}
        job = run_job("/audio/voice", params, rid)
        charged(calls, "/audio/voice", job)
        url = result_urls(job["result"])[0]
        endpoint = "/audio/voice"
    elif kind == "speech":
        sample = ledger_url(asset["voice"])
        params = {"text": spoken(asset), "sample": sample}
        job = run_job("/audio/speech", params, rid)
        charged(calls, "/audio/speech", job)
        url = result_urls(job["result"])[0]
        endpoint = "/audio/speech"
    elif kind == "styled":
        params = {"style_image": ledger_url(asset["style_from"]), "prompt": asset["prompt"],
                  "image_type": asset.get("type", "art"), "n": 1, "augment_prompt": asset.get("augment", True)}
        job = run_job("/assets/image/style", params, rid)
        charged(calls, "/assets/image/style", job)
        url = result_urls(job["result"])[0]
        if asset.get("cutout"):
            cut = run_job("/assets/image/remove-background",
                          {"image": url, "crop": True, "creative_edit": False}, rid + "-cut")
            charged(calls, "/assets/image/remove-background", cut)
            url = result_urls(cut["result"])[0]
        endpoint = "/assets/image/style"
    elif kind == "image":
        prompt = asset["prompt"]
        if asset.get("style", True):
            prompt = prompt + ". " + style["image"]
        params = {
            "image_type": asset.get("type", "art"),
            "prompt": prompt,
            "art_style": asset.get("art_style", style["art_style"]),
            "perspective": asset.get("perspective", "Any perspective"),
            "aspect_ratio": asset.get("aspect", "ar_1_1"),
            "n": 1,
            "augment_prompt": asset.get("augment", True),
        }
        job = run_job("/assets/image", params, rid)
        charged(calls, "/assets/image", job)
        url = result_urls(job["result"])[0]
        if asset.get("cutout"):
            cut = run_job("/assets/image/remove-background",
                          {"image": url, "crop": True, "creative_edit": False}, rid + "-cut")
            charged(calls, "/assets/image/remove-background", cut)
            url = result_urls(cut["result"])[0]
        endpoint = "/assets/image"
    elif kind in ("sfx", "music", "ambiance"):
        endpoint = {"sfx": "/audio/sound-effect", "music": "/audio/music", "ambiance": "/audio/ambiance"}[kind]
        params = {"description": asset["prompt"], "augment_prompt": asset.get("augment", True)}
        if "duration" in asset:
            params["duration"] = asset["duration"]
        if kind == "sfx":
            params["loop"] = asset.get("loop", False)
        if kind == "music" and asset.get("lyrics"):
            params["lyrics"] = asset["lyrics"]
        job = run_job(endpoint, params, rid)
        charged(calls, endpoint, job)
        url = result_urls(job["result"])[0]
    elif kind in ("keyframes", "transfer"):
        if kind == "keyframes":
            endpoint = "/assets/sprite/animate-keyframes"
            params = {}
            if asset.get("from") or asset.get("from_file"):
                params["initial_image"] = source(asset, fit=True)
            if asset.get("middle") or asset.get("middle_file"):
                params["middle_image"] = source(asset, "middle", fit=True)
            if asset.get("final_same"):
                params["final_image"] = params["initial_image"]
            elif asset.get("final") or asset.get("final_file"):
                params["final_image"] = source(asset, "final", fit=True)
            if asset.get("prompt"):
                params["motion_prompt"] = asset["prompt"]
        else:
            endpoint = "/assets/sprite/transfer-motion"
            params = {"image": source(asset, fit=True), "preset_id": asset["preset_id"],
                      "perspective": asset.get("perspective", "horizon"), "direction": asset.get("direction", "E")}
        params.update({"model": asset.get("model", "forge"), "duration": asset.get("duration", 3),
                       "frames": asset.get("frames", 25), "frame_size": asset.get("frame_size", -9),
                       "loop": asset.get("loop", False), "image_type": asset.get("image_type", "sprite")})
        if kind == "transfer":
            params.pop("image_type")
        sprite_params(asset, params)
        job = run_job(endpoint, params, rid)
        charged(calls, endpoint, job)
        url, extra = sheet_result(asset, job["result"], out_base, downloads)
    elif kind == "sprite_edit":
        endpoint = "/assets/sprite/edit"
        params = {"spritesheet_url": ledger_url(asset["source"]), "edit_mode": asset.get("edit_mode", "prompt")}
        if asset.get("prompt"):
            params["prompt"] = asset["prompt"]
        if asset.get("refs"):
            params["images"] = refs(asset)
        for k in ("model", "duration", "frames", "frame_size", "loop"):
            if k in asset:
                params[k] = asset[k]
        sprite_params(asset, params)
        job = run_job(endpoint, params, rid)
        charged(calls, endpoint, job)
        url, extra = sheet_result(asset, job["result"], out_base, downloads)
    elif kind in ("pose", "rotate"):
        if kind == "pose":
            endpoint = "/assets/sprite/pose"
            params = {"image": source(asset), "pose": asset.get("pose", "Other"), "n": asset.get("n", 1)}
            if asset.get("prompt"):
                params["description"] = asset["prompt"]
        else:
            endpoint = "/assets/sprite/rotate"
            params = {"image": source(asset), "camera_rotation": asset.get("rotation", 45), "n": asset.get("n", 1)}
            if "elevation" in asset:
                params["camera_elevation"] = asset["elevation"]
        job = run_job(endpoint, params, rid)
        charged(calls, endpoint, job)
        urls = result_urls(job["result"])
        url = urls[0]
        for i, u in enumerate(urls):
            downloads.append((u, "%s_%d%s" % (out_base, i, ext_of(u, ".webp"))))
    elif kind == "video":
        endpoint = "/assets/video"
        src = source(asset)
        params = {"image": src, "prompt": asset["prompt"], "model": asset.get("model", "griffin"),
                  "duration": asset.get("duration", 5), "augment_prompt": asset.get("augment", True)}
        if asset.get("final_same"):
            params["final_image"] = src
        elif asset.get("final") or asset.get("final_file"):
            params["final_image"] = source(asset, "final")
        job = run_job(endpoint, params, rid)
        charged(calls, endpoint, job)
        url = job["result"]["url"]
        extra = {"duration": job["result"].get("duration"), "has_audio": job["result"].get("has_audio")}
    elif kind == "video_refs":
        endpoint = "/assets/video/references"
        params = {"images": refs(asset), "prompt": asset["prompt"], "model": asset.get("model", "griffin"),
                  "duration": asset.get("duration", 5), "aspect_ratio": asset.get("aspect", "ar_16_9")}
        job = run_job(endpoint, params, rid)
        charged(calls, endpoint, job)
        url = job["result"]["url"]
        extra = {"duration": job["result"].get("duration"), "has_audio": job["result"].get("has_audio")}
    elif kind == "upscale":
        endpoint = "/assets/video/upscale"
        params = {"video": ledger_url(asset["source"])}
        job = run_job(endpoint, params, rid)
        charged(calls, endpoint, job)
        url = job["result"]["url"]
        extra = {"duration": job["result"].get("duration"), "has_audio": job["result"].get("has_audio")}
    elif kind == "model3d":
        endpoint = "/assets/3d-model"
        params = {"image": source(asset), "target_num_faces": asset.get("faces", 20000),
                  "texture_size": asset.get("texture_size", 1024), "texture_type": asset.get("texture_type", "pbr")}
        job = run_job(endpoint, params, rid)
        charged(calls, endpoint, job)
        url = job["result"]["model_url"]
        for i, u in enumerate(job["result"].get("snapshots") or []):
            downloads.append((u, "%s_snap%d%s" % (out_base, i, ext_of(u, ".png"))))
    elif kind == "audio_transform":
        endpoint = "/audio/transform"
        params = {"sample": local_image(asset["sample_file"]), "prompt": asset["prompt"],
                  "modification_strength": asset.get("strength", 0.6), "duration": asset.get("duration", 0),
                  "augment_prompt": asset.get("augment", True)}
        job = run_job(endpoint, params, rid)
        charged(calls, endpoint, job)
        url = result_urls(job["result"])[0]
    else:
        raise RuntimeError("unknown kind %s" % kind)
    dest = out_base + ext_of(url, ".bin")
    if have and have != dest:
        os.remove(have)
    download(url, dest)
    real = sniff(dest)
    if real and not dest.endswith(real):
        fixed = out_base + real
        os.replace(dest, fixed)
        dest = fixed
    for u, p in downloads:
        try:
            download(u, p)
        except Exception as e:  # a side file (gif, sound track) must not lose the main one
            log("  side file failed", os.path.relpath(p, ROOT), str(e)[:120])
    if extra:
        json.dump(extra, open(out_base + ".json", "w"))

    def short(v):
        if isinstance(v, str) and v.startswith("data:"):
            return v[:40] + "...(base64)"
        if isinstance(v, list):
            return [short(x) for x in v]
        return v
    params = {k: short(v) for k, v in params.items()}
    entry = {"id": aid, "v": ver, "endpoint": endpoint, "params": params, "job": job.get("id"),
             "credits": round(sum(c["credits"] for c in calls), 2) if calls else job.get("credits_charged"),
             "url": url, "file": os.path.relpath(dest, ROOT)}
    if len(calls) > 1:
        entry["calls"] = calls
    if kind in ("keyframes", "transfer", "sprite_edit", "animate") and isinstance(job.get("result"), dict):
        for k in ("video_url", "audio_url", "gif_url"):
            if job["result"].get(k):
                entry[k] = job["result"][k]
    if downloads:
        entry["side_files"] = [os.path.relpath(p, ROOT) for u, p in downloads]
    record(entry)
    log("done %-22s %5.0fs  %s" % (aid, time.time() - t0, os.path.relpath(dest, ROOT)))


def worker(queue, style, force, failures):
    for asset in queue:
        try:
            build(asset, style, force)
        except Exception as e:  # keep the rest of the queue moving
            FAILED.add(asset["id"])
            failures.append((asset["id"], str(e)))
            log("FAIL", asset["id"], str(e)[:300])


def account():
    """The account's credits (a free call)."""
    return call("GET", "/assets/account").get("credits", {})


def main(argv):
    global KEY
    KEY = api_key()
    if "--account" in argv:
        c = account()
        print("credits available %.1f (plan %s, extra %s, used this period %s)" % (
            c.get("available", 0), c.get("plan_credits"), c.get("extra"), c.get("used")))
        return
    force = "--force" in argv
    jobs = 0
    if "--jobs" in argv:
        i = argv.index("--jobs")
        jobs = int(argv[i + 1])
        argv = argv[:i] + argv[i + 2:]
    takes = None
    if "--takes" in argv:
        i = argv.index("--takes")
        takes = int(argv[i + 1])
        argv = argv[:i] + argv[i + 2:]
    wanted = [a for a in argv if not a.startswith("--")]
    man = json.load(open(MANIFEST))
    for a in man["assets"]:
        MANIFEST_V[a["id"]] = int(a.get("v", 1))
    style = man["style"]
    assets = man["assets"]
    if wanted:
        assets = [a for a in assets if a["id"] in wanted]
    assets = with_takes(assets, takes)
    if jobs > 0:
        ## a pool that starts assets in manifest order: a dependency always starts before
        ## whatever waits on it, so the waits can never fill the pool and deadlock
        from concurrent.futures import ThreadPoolExecutor
        failures = []
        log("pool of %d for %d assets" % (jobs, len(assets)))
        with ThreadPoolExecutor(max_workers=jobs) as ex:
            for a in assets:
                ex.submit(worker, [a], style, force, failures)
        if failures:
            log("FAILED:", failures)
            sys.exit(1)
        log("all assets present")
        return
    lanes = {}
    lane_of = {"ambiance": "sfx"}
    for a in assets:
        lanes.setdefault(lane_of.get(a["kind"], a["kind"]), []).append(a)
    failures = []
    threads = [threading.Thread(target=worker, args=(q, style, force, failures)) for q in lanes.values()]
    log("lanes:", {k: len(v) for k, v in lanes.items()})
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    if failures:
        log("FAILED:", failures)
        sys.exit(1)
    log("all assets present")


if __name__ == "__main__":
    main(sys.argv[1:])
