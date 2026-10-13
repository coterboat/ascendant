#!/usr/bin/env python3
"""(Copied from CONCURRENT tools/ludo/glb_slim.py for the ascendant 3D spike.) Slim a Ludo GLB for the repo: its PNG textures re-encoded as JPEG (a 1024 colour map goes from
about 1.5 MB to 200 KB), everything else byte for byte. Godot reads JPEG in a GLB as it reads PNG.

    python3 tools/ludo/glb_slim.py in.glb out.glb [--q 3] [--max 1024] [--albedo-only]

The import that goes with it (write_import) embeds the textures in Godot's own import, compressed
for the GPU, instead of extracting PNG copies next to the model (which the repo would carry twice).
Stdlib plus ffmpeg.
"""
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile

FF = shutil.which("ffmpeg") or "/opt/homebrew/opt/ffmpeg-full/bin/ffmpeg"


def _pad(b, fill=b"\x00"):
    return b + fill * ((4 - len(b) % 4) % 4)


def read_glb(path):
    data = open(path, "rb").read()
    magic, _ver, _length = struct.unpack("<III", data[:12])
    if magic != 0x46546C67:
        raise ValueError("not a GLB: " + path)
    off = 12
    js, binc = None, b""
    while off < len(data):
        clen, ctype = struct.unpack("<II", data[off:off + 8])
        chunk = data[off + 8:off + 8 + clen]
        if ctype == 0x4E4F534A:
            js = json.loads(chunk)
        elif ctype == 0x004E4942:
            binc = chunk
        off += 8 + clen
    return js, binc


def write_glb(path, js, binc):
    jb = _pad(json.dumps(js, separators=(",", ":")).encode(), b" ")
    bb = _pad(binc)
    total = 12 + 8 + len(jb) + 8 + len(bb)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(jb), 0x4E4F534A))
        f.write(jb)
        f.write(struct.pack("<II", len(bb), 0x004E4942))
        f.write(bb)


def _to_jpeg(data, q, max_size=0, ext="png"):
    with tempfile.TemporaryDirectory() as d:
        src = os.path.join(d, "in." + ext)
        dst = os.path.join(d, "out.jpg")
        open(src, "wb").write(data)
        vf = ["-vf", "scale='min(%d,iw)':-2" % max_size] if max_size else []
        subprocess.run([FF, "-y", "-loglevel", "fatal", "-i", src, *vf, "-q:v", str(q), dst], check=True)
        return open(dst, "rb").read()


def albedo_only(js):
    """(ascendant spike) Keep only each material's base colour map: drop the metallic-roughness,
    normal, occlusion and emissive maps (their textures, images and buffer views, indices remapped),
    and make the material matte (Ludo ships metallicFactor 1.0, which reads "too shiny"). The game
    overrides the materials anyway; this halves the file."""
    keep_tex = []
    for m in js.get("materials", []):
        pbr = m.setdefault("pbrMetallicRoughness", {})
        if "baseColorTexture" in pbr and pbr["baseColorTexture"]["index"] not in keep_tex:
            keep_tex.append(pbr["baseColorTexture"]["index"])
        pbr.pop("metallicRoughnessTexture", None)
        pbr["metallicFactor"] = 0.0
        pbr["roughnessFactor"] = 0.85
        for k in ("normalTexture", "occlusionTexture", "emissiveTexture"):
            m.pop(k, None)
    tex_map = {old: new for new, old in enumerate(keep_tex)}
    textures = [js["textures"][t] for t in keep_tex]
    keep_img = []
    for t in textures:
        if t["source"] not in keep_img:
            keep_img.append(t["source"])
    img_map = {old: new for new, old in enumerate(keep_img)}
    for t in textures:
        t["source"] = img_map[t["source"]]
    for m in js.get("materials", []):
        pbr = m["pbrMetallicRoughness"]
        if "baseColorTexture" in pbr:
            pbr["baseColorTexture"]["index"] = tex_map[pbr["baseColorTexture"]["index"]]
    dead_views = set(img["bufferView"] for i, img in enumerate(js.get("images", [])) if i not in img_map and "bufferView" in img)
    js["textures"] = textures
    js["images"] = [js["images"][i] for i in keep_img]
    ## drop the dead views and renumber every reference to the rest
    views = js.get("bufferViews", [])
    view_map = {}
    kept = []
    for i, v in enumerate(views):
        if i in dead_views:
            continue
        view_map[i] = len(kept)
        kept.append(v)
    js["bufferViews"] = kept
    for acc in js.get("accessors", []):
        if "bufferView" in acc:
            acc["bufferView"] = view_map[acc["bufferView"]]
    for img in js["images"]:
        if "bufferView" in img:
            img["bufferView"] = view_map[img["bufferView"]]
    return js


def slim(src, dst, q=3, max_size=0, albedo=False):
    """Every PNG texture to JPEG; with max_size, every texture (JPEG too) no wider than that."""
    js, binc = read_glb(src)
    if albedo:
        albedo_only(js)
    views = js.get("bufferViews", [])
    images = js.get("images", [])
    swap = {}
    for img in images:
        mime = img.get("mimeType")
        if "bufferView" not in img or mime not in ("image/png", "image/jpeg"):
            continue
        if mime == "image/jpeg" and not max_size:
            continue
        v = views[img["bufferView"]]
        start = v.get("byteOffset", 0)
        swap[img["bufferView"]] = _to_jpeg(binc[start:start + v["byteLength"]], q, max_size,
                                           "png" if mime == "image/png" else "jpg")
        img["mimeType"] = "image/jpeg"
    ## rebuild the binary chunk view by view, every view on a 4-byte boundary
    out = bytearray()
    for i, v in enumerate(views):
        start = v.get("byteOffset", 0)
        piece = swap.get(i, binc[start:start + v["byteLength"]])
        while len(out) % 4:
            out.append(0)
        v["byteOffset"] = len(out)
        v["byteLength"] = len(piece)
        out += piece
    if js.get("buffers"):
        js["buffers"][0]["byteLength"] = len(out)
    write_glb(dst, js, bytes(out))
    return os.path.getsize(src), os.path.getsize(dst)


IMPORT = """[remap]

importer="scene"
importer_version=1
type="PackedScene"

[deps]

source_file="res://{res}"

[params]

nodes/root_type=""
nodes/root_name=""
nodes/apply_root_scale=true
nodes/root_scale=1.0
meshes/ensure_tangents=true
meshes/generate_lods=true
meshes/create_shadow_meshes=true
meshes/light_baking=1
animation/import=false
materials/extract=0
gltf/naming_version=2
gltf/embedded_image_handling=2
"""


def import_uid(path):
    """The uid of an existing .import ("uid://..."), or None when there is no file or no uid line."""
    if not os.path.exists(path):
        return None
    with open(path) as f:
        m = re.search(r'^uid="(uid://[^"]+)"\s*$', f.read(), re.M)
    return m.group(1) if m else None


def write_import(res_path, root):
    """A .import beside the model that embeds its textures (GPU-compressed) rather than extracting them. The uid of
    an import already there is kept, so scenes that name the model by uid still find it after a replace; Godot
    writes path= and dest_files= back on its next import."""
    path = os.path.join(root, res_path + ".import")
    text = IMPORT.format(res=res_path)
    uid = import_uid(path)
    if uid:
        text = text.replace('type="PackedScene"\n', 'type="PackedScene"\nuid="%s"\n' % uid, 1)
    with open(path, "w") as f:
        f.write(text)


if __name__ == "__main__":
    a = sys.argv[1:]
    albedo = "--albedo-only" in a
    a = [x for x in a if x != "--albedo-only"]
    opts = {"--q": 3, "--max": 0}
    for k in opts:
        if k in a:
            i = a.index(k)
            opts[k] = int(a[i + 1])
            a = a[:i] + a[i + 2:]
    before, after = slim(a[0], a[1], opts["--q"], opts["--max"], albedo)
    print("%s: %.2f MB -> %.2f MB" % (os.path.basename(a[1]), before / 1e6, after / 1e6))
