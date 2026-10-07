# Vendored: the 3D viewer

The Review Table shows `.glb` / `.gltf` items in an orbit viewer (drag to turn, scroll to zoom, auto-turntable).
That viewer is Google's `<model-viewer>`, committed here so the page works **offline and with no CDN**: the server
hands it out at `/vendor/model-viewer.min.js`, and the page's Content-Security-Policy allows nothing from outside
`127.0.0.1`.

| | |
|---|---|
| package | `@google/model-viewer` **4.3.1** (npm, published by Google) |
| file | `dist/model-viewer.min.js`, an ES module that bundles its own three.js (loaded with `<script type="module">`) |
| fetched from | `https://cdn.jsdelivr.net/npm/@google/model-viewer@4.3.1/dist/model-viewer.min.js` |
| size | 1,068,903 bytes |
| sha256 | `283b0672384614b4847636c306fc93fe4b1fcadc76d668b4e47f0ca76bcf033b` (jsdelivr's own listing for the file, base64 `KDsGcjhGFLSEdjbDBvyT/ksfytx21mi05H8Mp2vPAzs=`, matched on download) |
| license | Apache License 2.0: `LICENSE-model-viewer` (from the same package). The bundle also carries three.js (MIT) and fflate (MIT); their notices are in the file's own comments. |

The file is committed byte for byte as published. Do not edit it. (It prints some `[$updateSource]` debug lines to the
browser console; that is the published build, not this tool.)

## What it can and cannot show offline

- Plain GLB / glTF with JPEG or PNG textures works. That covers what `tools/ludo/glb_slim.py` writes and everything under
  `assets/models/` (checked: no glTF extensions are used there; two of them are in the sample model batch).
- Meshopt-compressed files should work: the bundle has no download location for that decoder, it carries it (a WebAssembly
  module it compiles when the page loads, which is why the Content-Security-Policy allows `'wasm-unsafe-eval'`).
  Nothing in this repo is Meshopt-compressed, so that path has not been exercised.
- **Draco** and **KTX2/Basis** compressed files need decoder files that `<model-viewer>` fetches from `gstatic.com`.
  The page's Content-Security-Policy blocks that on purpose, so such a model shows "This model didn't load" and is
  listed under **Flagged**. If one is ever needed, vendor the decoders here too and point
  `ModelViewerElement.dracoDecoderLocation` / `ktx2TranscoderLocation` at `/vendor/` (and allow `.wasm` in
  `VENDOR_TYPES` in `review.py`).
- A `.gltf` with external `.bin` / texture files works when they sit next to it in the batch folder: they are fetched
  from `/media/<batch>/…`, relative to the `.gltf`.

## Updating it

```sh
V=4.3.1   # the version to move to
curl -sS -o tools/review/vendor/model-viewer.min.js https://cdn.jsdelivr.net/npm/@google/model-viewer@$V/dist/model-viewer.min.js
curl -sS -o tools/review/vendor/LICENSE-model-viewer https://cdn.jsdelivr.net/npm/@google/model-viewer@$V/LICENSE
# check both against jsdelivr's listing: https://data.jsdelivr.com/v1/packages/npm/@google/model-viewer@$V?structure=flat
# (its "hash" is the base64 sha256), then update this file and run: python3 tools/review/test_review.py
```

If `<model-viewer>` ever has to be replaced, the fallback is three.js r160+ with `GLTFLoader` and `OrbitControls`,
vendored the same way; only `mountModel()` and `makeViewer()` in `index.html` would change.
