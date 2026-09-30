# Ludo.ai playbook (distilled from Alex's repos)

Compiled 30 Sep 2026 from three repos. Every rule is tagged with its source file.
Source keys:
- **[C-CAP]** `coterboat/concurrent` `docs/LUDO_CAPABILITIES.md` (27 Sep 2026; the most complete and most recent)
- **[C-PROMPT]** `concurrent` `docs/PROMPTING.md` · **[C-ASSETS]** `concurrent` `docs/ASSETS.md` · **[C-CLAUDE]** `concurrent` `CLAUDE.md` · **[C-LOG]** `concurrent` `docs/CHANGELOG.md` · **[C-PY]** `concurrent` `tools/ludo/ludo.py`
- **[E-11]** `coterboat/EO7` `docs/11-GENERATED-ASSETS.md` · **[E-07]** `EO7` `docs/07-ART-STYLE-BIBLE.md` · **[E-16]** `EO7` `docs/16-AUDIO.md` · **[E-06]** `EO7` `docs/06-ASSET-CHECKLIST.md` · **[E-MAN]** `EO7` `data/assets/manifest/README.md` · **[E-TOOLS]** `EO7` `tools/ludo_*.py`, `tools/make_base_frame.py` (docstrings) · **[E-LOG]** `EO7` `AGENT_LOG.md` · **[E-WT]** `EO7` `SPRITES-WORKTREE.md`
- **[CS]** `coterboat/chesssensei` `README.md` "Assets", `PLAN.md` §2, `tools/gen_assets.py`, `tools/install_assets.py` (its `tools/ludo_client.py` is byte-identical to EO7's)

Where sources disagree, the newer one wins and the conflict is noted. EO7 is Jul–Aug 2026; CONCURRENT is Sep 2026.

---

## 1. Transport, auth, jobs

- REST base `https://api.ludo.ai/api`, header `Authorization: ApiKey <key>`, JSON bodies. [C-PY] (confirmed by the public spec `https://api.ludo.ai/api-documentation/swagger.json`, which is Swagger 2.0, v0.9.10)
- MCP alternative: `https://mcp.ludo.ai/mcp`, JSON-RPC, same tool names, body wrapped in `requestBody`, same `Authorization: ApiKey` header. Results come back as text prefixed `API Response (Status: NNN):`. [E-TOOLS ludo_client.py] [C-CAP]
- **Every call is an async job** (since Aug 2026): the response is `{id, status}`. Long-poll `GET /assets/jobs/{id}?wait=55` (MCP: `getApiJob {id, wait:30}`) until `succeeded`. The asset is in `result`; never read a URL from the first response. [C-CAP] [E-16] [EO7 CLAUDE.md]
- **`request_id` is sticky/cached.** Same id returns the existing job (~7 s against ~90 s). Useful for resume; a trap for retries. Put a version (`<project>-<id>-v<N>`) [C-CAP] or a digest of the request body [E-11] in the id, so a changed prompt or input gets a new id.
- **Download at once. URLs die after 7 days.** Never store a Ludo URL as a reference. [E-11] [C-CAP]
- **The edit tools accept only your own generations from the last 7 days** (`editSpritesheet`, `createSpriteAudio`, `editVideo`, `upscaleVideo`). Run repairs, re-skins and variants in the same pipeline run as their source. You can recover a lost URL by request id: `listGenerations?type=spritesheet&request_id=…` / `GET /assets/sprites/results`. [C-CAP] [E-11]
- **Concurrency.** EO7 (Jul) measured strict serialisation: ~1 sheet per 70 s whatever `--jobs` was set to, "one simultaneous request per endpoint (beta)". [E-11] [E-WT] CONCURRENT (Sep): up to 50 jobs queue, 2–3 run at once; ~35 jobs polling at once hit `429 Rate limit reached`. [C-CAP] → Keep a small worker pool, **retry 429 forever with backoff + jitter (never abandon a running job)**, retry 5xx ~5 times, and retry `OSError` (dropped TLS records seen). [C-PY] [C-CAP]
- Two worktrees or bots share one key's credits and rate limit. Parallel generation buys nothing. [E-WT]
- **Input frames for animation must be < 1 megapixel.** Downscale first (premultiplied, keeping alpha). A tool once overwrote its base frame with a 2.68 MP sheet and every later call was rejected. Refuse to write output over your own inputs. [C-CAP] [E-LOG] [E-11]
- Free endpoints: `GET /assets/account` (balance), `GET /docs`, `GET /docs/search`, `GET /assets/sprite/animation-presets` (641 presets), `GET /assets/generations`, `GET /assets/jobs`, `DELETE /assets/jobs/{id}` (a cancel refunds). `GET /auth/validate-api-key` returns a bare 204. [C-CAP] [E-11: EO7 believed no quota endpoint existed; `getAccount` does exist, see C-CAP]
- Failed jobs are not charged. [C-CAP]

## 2. Budget and cost discipline

- Prices (Sep 2026): image/edit/style/removeBackground/pose/rotate 0.5 each; forge animation 1.5 cr/s (4 minimum); hydra 3 cr/s (9 minimum); keyframe sheet ~4; SFX 2; ambiance 2; music 3; transform 3; voice/speech 1; 3D model 3; rig 1; video griffin 1.5/s (7.5 minimum), from references 2.5/s (12.5 minimum), upscale 0.2/s. [C-CAP] [C-PROMPT]
- Check `getAccount` before a big run and report the spend. [C-CLAUDE] [C-CAP]
- **Ledger every charged call**, including the cutouts (`removeBackground`) and each re-roll (keep a `history` list; don't overwrite). CONCURRENT's ledger drifted about 17–400 credits from the bill because of exactly these gaps. [C-CAP]
- Make generation **idempotent/resumable**: skip existing outputs unless `--force`; `--dry-run` prints the prompts; `--only <ids>`. A `"status": "placeholder"` manifest refuses to run, so a half-written manifest can't spend credits. [E-11] [E-MAN]
- **Scope the art bill before generating.** Decide each character's role first (a playable character was ~36 sheets against ~5 for an NPC). Never make sets "just in case". [E-11] [E-MAN]
- The adding of an asset should be a manifest entry, never a tool edit. [E-11]

## 3. Which endpoint for what (what worked / what didn't)

| Need | Use | Notes / source |
|---|---|---|
| Still art, icons, portraits, backgrounds, UI | `POST /assets/image` (`image_type` required; 22 types; `art_style`, `perspective`, `aspect_ratio`, `n` 1–8) | Returns ~1024×1024 lossy webp. Too small for 1920–2700 px parallax layers. [E-11] [E-07] |
| Keep a family consistent | `POST /assets/image/style` (`style_image`) | Paint every portrait after the first with the first as its style reference, so the set reads as one series. [C-LOG v1.2] [E-TOOLS] |
| Transparency | `POST /assets/image/remove-background` | Lossless PNG with real antialiased alpha; auto-crops. Use `creative_edit:false` to keep pixels exact. [E-07] [C-CAP] |
| Character in a new pose | `POST /assets/sprite/pose` then animate | Ludo's own advice: pose first, then animate. **Always feed the padded full canvas**; a narrow crop came back cropped and front-facing. [E-11] [C-CAP] |
| New camera angle | `POST /assets/sprite/rotate` (45° steps, elevation 0/30/60) | Clean three-quarter tabletop views. [C-CAP] EO7: `generatePose "Walk (Towards the camera)"` ≠ `rotateSprite 180`; they are not interchangeable. [E-MAN] |
| Simple loops | `animateSprite` model `forge` | Cheap, stable, fine for simple loops. [C-CAP] |
| Complex motion, talking portraits | `animateSprite` model `hydra` (Ludo's default since 21 Sep; returns an audio track; can lip-sync in its own voice) | Strict moderation on violence; retry a refusal on forge. [C-CAP] |
| Precise moves (attack, fall, cheer) | `POST /assets/sprite/animate-keyframes` (first/**middle**/last) | "Best result of the day". Forge holds the middle frame exactly. Output cells can be 21–145 px wider than the input: re-normalise the canvas in post. [C-CAP] |
| Preset motion | `transferMotion` (641 presets) | Hydra transfer: 500s. Forge: mostly works, but it changes the canvas to square cells and can turn the figure. Prefer keyframes. [C-CAP] |
| Re-skin a sheet, same motion (unit variants) | `editSpritesheet edit_mode:prompt` | Works. Keep the wording short ("a tall bearskin cap instead of the shako"); a long costume list failed 4/4 with a 500. It also trims the clip length. [C-CAP] |
| Fix a loop seam | `editSpritesheet edit_mode:fix_loop`, **then** trim playback (`use_frames`) | Neither half is enough alone (2.89× → 0.87×). Only on sheets that fail a seam check; on clean ones it adds drift. [E-11] [C-CAP] |
| Clipping at frame edge | `outpaint` | **Failed** (24 tiny cells, the flash gone). Use a manual margin at generation instead. [C-CAP] |
| Untinted VFX (smoke, blast, sparks) | `createImage image_type:sprite-vfx` → forge animate, manual margin | Keep VFX as a separate layer from tinted units. [C-CAP] [C-ASSETS] |
| Seamless textures | `createImage texture` | Works, then flatten the painted lighting in post. **Animated texture via API is rejected** ("blank keyframe"); scroll in a shader. [C-CAP] |
| Parallax layer | `createImage parallax_layer` | A wide haze band on transparency that repeats horizontally. [C-CAP] |
| Title/logo text | **Don't** use `logo` for words | Misspelled every time. Set the title in a real font over a generated ornament. [C-CAP] Chess Sensei: set the wordmark in a font. [CS PLAN] |
| Tiny pixel-exact glyphs/badges, 12 consistent pieces | **Don't** generate | Hand-write SVG. AI can't make consistent crisp-at-40px sets. [CS PLAN §2] |
| Living title/victory screens | `createVideo` griffin, `final_image` = first frame, then `upscaleVideo` | Loops. 832×480 → 1664×960. Crossfade the last 0.5 s in post. [C-CAP] |
| Cutscenes with your cast | `createVideoFromReferences` (1–5 refs) | Cast and rooms stay on-model; passed moderation with war content. [C-CAP] |
| Video restyle | `editVideo` | **Not worth it**: 10 cr, no audio, still 480p. Edit the still and re-animate it. [C-CAP] |
| 3D pieces | `createImage asset` → `create3DModel` | Good painted GLB (~20k tris). Rigging needs an A/T-pose; `animate3DModelPreset` is unusable (no `clip_url`). [C-CAP] |
| SFX | `POST /audio/sound-effect` | Returns real MP3. [E-16] |
| Ambient beds | `POST /audio/ambiance` | Returns **WAV behind a `.mp3` URL**. "Loop" is not seamless. [E-16] |
| Music | `POST /audio/music` (0 or 10–180 s in steps of 10; optional `lyrics`) | Seamless-ish loop. Instrumental unless `lyrics` is set. [C-CAP] EO7: 45 failed schema; ask for 60 and get 48–56. [E-16] |
| Themed variants of a track | `POST /audio/transform` (`modification_strength` 0.4 subtle / 0.6 clear / 0.8 strong) | Keeps the soundtrack one family. [C-CAP] |
| Voices | `/audio/voice` (designed), `/audio/speech` (cloned), `/audio/speech-preset` (catalog + emotion) | See §7. |
| Legacy models | `blitz`, `eagle`, `eagle-audio`, `tango` | Legacy since 17 Sep 2026, scheduled for removal. Don't use. [C-CAP] (EO7 chose `eagle` over `blitz` by measurement in Jul: blitz visual 4/10, broken gaits. Superseded.) |

## 4. Prompt rules

1. **There is no negative-prompt field.** "NEGATIVE: checkerboard" or "no X" gets *drawn* (a painted magenta checkerboard, measured). Never send a negative block; tools should refuse prompts containing one. [E-07] [E-11] [E-TOOLS]
2. **Say it positively.** Describe what should be there. [C-PROMPT #6] (C-CAP still found "does not fire, no flash" and "no cannon, no gun barrel" helped on specific animation/VFX prompts. Use sparingly and verify.)
3. **One verbatim style block per asset class**, appended unchanged, held in code. Never paraphrase it per asset. If a result needs tweaking, change the block, not the one prompt. [E-07]
4. **Separate blocks per class** (background / prop-character / UI). The block follows *what the art is*, not the tool that draws it. A wrong default block gave props a "parchment and leather" palette. [E-07] [E-06]
5. **Anchor style to art of the same class**: props to a shipped prop, rooms to rooms. Anchoring small rocks to a background layer inherited its dark outlines 3/3 times. [E-07]
6. **`augment_prompt: false`** when you need control. Ludo rewrites prompts behind the scenes by default. [E-11]
7. Set `image_type` explicitly (required on `createImage`). [E-11]
8. **Leave room in the frame**: margin on every side and headroom for whatever rises (a raised weapon, a flame, smoke). [C-PROMPT #1] State framing in the prompt: plants and rocks rooted at the bottom edge, overhanging branches attached at the top. [E-06]
9. **Describe the whole motion, including how it ends**, with a path ("swings back up in a slow arc to the shoulder"). A rotation over ~90° needs a middle keyframe. [C-PROMPT #2]
10. **Say what the hands hold throughout**, or the model invents props. [C-PROMPT #3]
11. **Name the expression and where the eyes go**, especially at the end of a clip. [C-PROMPT #4]
12. **Stage the outcome, not the struggle**, when the outcome is the point. [C-PROMPT #5]
13. Pin the view: "stays in side view facing right". Violent wording ("jolts back with one sharp recoil") made a figure turn around. A charge prompt made him fire. [C-CAP]
14. **Short wording beats long costume lists** on edits (a long one failed 4/4 with a 500). [C-CAP]
15. Every flag and heraldry must be invented. Regenerate anything resembling a real flag. [C-LOG v1.2]
16. SFX prompts: say the physical event plus "Close-mic, dry, no reverb, no music, no voice. Single short sound." [CS gen_assets.py]
17. Icons: "flat vector style, minimal, high contrast, clean edges, no text, no letters, no border, readable at 32 pixels", with `image_type: item-icon`. [CS gen_assets.py]
18. Background layers (hand-driven or big art): same seed for all layers of a room; layer-role composition lines (far / mid lower-two-thirds / near bottom-third, ground edge to edge); ask for flat magenta `#FF00FF`, never "transparent". [E-07] (For API sprites and props, use `removeBackground` instead of a plate: the API never returns clean magenta.) [E-07]

## 5. Sizes, formats, geometry

- Animation `frames` ∈ {4, 9, 16, 25, 36, 49, 64}. `frame_size` ∈ {32 … 384, 0, -1, -9}. [swagger]
- **`frame_size: -9` (true size), not `crop: true`.** -9 keeps the input frame's size *and position* in every frame, so states don't jump. Crop gave every sheet a different size. [E-11] [C-LOG v1.2] Exception: `animateSpriteKeyframes` at -9 still returns wider cells. Normalise them in post. [C-CAP]
- **Trim and scale the base frame before animating.** -9 copies the whole canvas: an untrimmed 768² input makes a 4600 px mostly-empty sheet. [E-11]
- **Use one shared padded canvas for a unit family** (CONCURRENT used 1152×768), so smoke and falls have room and every sheet lines up. [C-LOG v1.2] [C-CAP]
- Use a manual margin (`margin_ratio_mode: manual`) for VFX and portraits. Auto margin made faces small, and smoke clipped at 0.25 but stayed inside at 0.45/0.35. [C-CAP]
- The base frame must keep real alpha. An opaque backing makes the animator invent a plate colour. Downscale premultiplied. [E-11]
- Scale new characters against existing ones by **subject height**, not canvas. [E-MAN] [E-TOOLS ludo_views]
- **Sniff file headers, never trust extensions**: images come as webp behind `.png`; `createAmbiance` gives WAV behind `.mp3`. [E-16] [C-LOG "The .mp3 that Ludo sometimes returns is really a WAV"]
- Playback: 24 fps default for 36-frame sheets (1.5 s). Override per animation. [E-11] Portrait loops 8 fps, or 12–14 for Hydra talk loops. [C-ASSETS]
- Godot video: **Ogg Theora only**. `ffmpeg -i in.mp4 -c:v libtheora -q:v 5 -c:a libvorbis -q:a 4 out.ogv` (q5 ≈ q7 visually, ~40% smaller). [C-ASSETS]
- Ship sheets and art as webp, voices as mp3, music as MP3 (`AudioStreamMP3` loops natively), gate and loop-edit audio as 16-bit PCM. [C-ASSETS] [E-16]
- Build Godot `SpriteFrames` `.tres` from filenames by script (`<char>_<anim>.png` → animation), never by hand in the editor. Fail the build if a `requires` animation is missing, and use `aliases` rather than paying to generate duplicates. [E-11]

## 6. Consistency tricks

- **Pick from fresh candidates; don't revise.** A revision repaints the whole subject (mean RGB drift up to 21.8), and every animation inherits the drift. Generate 3–4 and choose; the cost is the same. [E-11] [E-TOOLS make_base_frame]
- Generate ~3 candidates for anything with a common failure (e.g. one roll in three had a hard black outline). Keep the candidates on disk (gitignored), record the installed pick in a tracked `installed.json`, and make swapping one `--install id:N` with no credits. [E-07] [E-06] [CS]
- **Never mix models within one character's set.** Pin the model per set. [E-11]
- Style-reference chain: first hero asset → `generateWithStyle` for the rest. [C-LOG v1.2]
- Anchoring (`final_image` = first/base frame) propagates whatever the anchor contains: a red collar survived regenerations. To break it, delete the sheet *and* its anchor, then run two passes (content, then loop). Anchoring to a clean base also suppresses invented details. [E-11]
- Variants: generate base + variants in one run (the 7-day edit window). [C-CAP]
- Judge consistency **side by side** (contact sheet of all rooms/assets), not one at a time. [E-07]
- A "gate" that audits palettes (`ludo_palette.py`) catches design drift that geometry checks miss, but it compares to the base, so a drifted base passes. [E-11]

## 7. Audio and voice

- SFX arrive with dead air in front and a long tail. Trim to onset, cap length per sound, short fade, normalise. For a move sound it must land within ms. With no human listener, prefer the fastest attack. [CS install_assets.py]
- `duration` doesn't bind: ask, then measure (asked 10, got 20.00 s). [E-16]
- `createAmbiance` "loops" but clicks at the wrap (7.4× typical motion). Always crossfade tail into head (→ ~3). An audio gate should check silence, clipping, DC, events in a bed, drones and seam. [E-16]
- Remix/music loudness varies wildly (−14.5 to −26.6 LUFS). Level each to its slot (−18/−19; songs −14) with a limiter. [C-CAP]
- Cloned speech (`/audio/speech`) has no emotion or speed control. Only the text and rolling takes steer it:
  - An ellipsis is the only pause mark that works (+0.1 s). `<break>` and `[pause]` are **read aloud**. Dashes and blank lines do nothing. [C-PROMPT]
  - Falling endings can't be written. Roll takes and keep the one that falls (measure pitch). `!` and trailing `...` raise the whole line. [C-PROMPT]
  - Stress by putting the word at the end of its clause. Stars and capitals are harmless but weak. [C-PROMPT]
  - Keep the words fixed and put direction in a separate `speak` field; subtitles come from `text`. Roll 2 takes for new lines, 3 for redos. [C-PROMPT]
  - Clone from the original voice sample, never from a take (the endings rose 4/4). [C-PROMPT]
- Hydra lip-sync speaks in Hydra's own voice: discard its audio and keep your voices, or accept it for cinematic lines. [C-CAP]
- Music direction: period-appropriate tunes (fife and drum), melody over sung lyrics. [C-PROMPT #7]
- (Local alternative seen in CONCURRENT: VoiceStudio/OmniVoice beat Ludo on voice quality, but it is Mac-local.) [C-PROMPT] [C-ASSETS]

## 8. Post-processing and QA gates

- Strip the baked ground shadow `animateSprite` adds (drop disconnected islands under 5% of the subject). [E-11]
- "Plate pockets": the animator's grey plate (~rgb 224) survives inside open mouths and gaps. Request `spritesheet_with_background` (free), read the exact plate colour off the borders, and key only that colour in interior regions. Veto when the plate is near the subject's own palette. [E-11]
- Gate each sheet: grid divides, has alpha, corners transparent, no stray islands, area stable, feet baseline stable (locomotion), and loop wrap ≤ 1.5× the sheet's own mean frame step (ratio, not absolute). Calibrate thresholds on your own good/bad art; if a batch passes first try, suspect the numbers. Per-animation tolerances need a written `_why`. [E-11] [EO7 data/assets/standards.json]
- Loops: generate with `final_image` = first frame (every sheet with it wrapped ≤ 1.42×; every one without ≥ 1.87×). Drop the duplicate last frame when packing; ping-pong if the seam still exceeds every inner step. [E-11] [C-LOG v1.2] (`final_image` about doubles generation time. [E-LOG])
- Read timing marks off frames (muzzle flash frame, fall-contact frame) into the sheet's JSON so the game syncs effects to them. [C-ASSETS]
- Textures: remove baked lighting by subtracting a wide blur taken on a 3×3 tiling (it stays seamless). [C-CAP]
- **No gate replaces looking.** A dirt pile fused to paws passed every automated check. Always review a contact sheet or GIF (`gif: true` is the only way to *watch* a loop). [E-11]
- Human review loop: generate into a review batch → accept/reject with notes → redo rewrites prompts from the notes → track first-take rate by kind (CONCURRENT: images 79%, video 78%, audio 68%). Don't make verdicts for the owner. [C-PROMPT] [C-ASSETS] [C-CLAUDE]

## 9. Repo hygiene and secrets

- Never print, log or commit `LUDO_API_KEY`. Keep it in `.env.local`/`.env`, which are gitignored. (EO7's key was pasted into chat once and flagged "rotate this".) [C-CLAUDE] [E-WT] [E-LOG]
- Masters, raw sheets and candidates stay gitignored. Commit only what the game loads. EO7's tracked candidates reached 390 MB and broke `git push`. [E-11] [C-ASSETS]
- No Git LFS until history nears ~1 GB: LFS downloads are metered, and a bot re-cloning on every push burns the quota. [C-ASSETS]

## 10. Findings from the ASCENDANT style probe (2026-09-30)

Source key: **[A-PROBE]** `coterboat/ascendant` batch `asc-style-probe`: per-call ledger `assets/_probe/asc-style-probe_ledger.json`, every candidate in `assets/_probe/<direction>/candidates/`, contact sheet `studio/contact-sheets/asc-style-probe.png`. 21 rows, 40.0 cr. These paths are on branch `assets/asc-style-probe` (PR #12, closed unmerged and superseded by the M1 PR). The branch is kept. The anchors it picked are copied into `assets/_anchors/` by the M1 PR.

**`tools/ludo/ludo.py` on ASCENDANT**
- **The global style append is switched off per entry with `"style": false`** in `tools/ludo/manifest.json`. The code is `if asset.get("style", True): prompt = prompt + ". " + style["image"]` (the `image` kind only). `art_style` still falls back to the global `style["art_style"]` unless the entry sets its own `art_style`, so set both. `edit`, `styled` and `animate` never append. [A-PROBE: all 21 request bodies in the ledger carry the manifest prompt verbatim, and the driver asserted `body["prompt"] == manifest prompt` before every createImage.]
- ludo.py doesn't fit the probe plan as-is. Its `request_id` is hard-coded to `concurrent-<id>-v<N>`. It always sends `n: 1`. `cutout: true` cuts out every take, not just the pick, so 3 candidates cost 3 cutouts. `fit_megapixel`/`image_size` shell out to `sips`, which only exists on macOS, so `fit: true` breaks on the Linux box. The probe drove the API with ludo.py's `call()` transport (429 backoff, 5xx and OSError retries) and built its own bodies with `asc_…` request ids and `n` = 2–3 per createImage/editImage call. [A-PROBE]

**createImage output by `image_type`**
- `sprite`, `sprite-vfx` and `ui_asset` come back as **RGBA with the background already transparent**, at about 768 px (768×768, 784×768, 768×784, 800×800), even when the prompt asks for a plain flat mid-grey or black background. `texture` returns opaque RGB 1024×1024, and `asset` returns opaque RGB 864×1152 for `ar_3_4`. [A-PROBE: 42 images]
  - The removeBackground cutout of a `sprite` pick matched the native alpha to within 1.1–3.9 alpha levels on average. On sprites it is close to a no-op, so decide per class whether that 0.5 cr is needed.
  - `sprite-vfx` has no black plate to use additively. Flatten it onto black yourself (alpha-composite over `#000`).
  - `ui_asset` can **key out the panel's own dark centre**. Storybook panel c1 came back with a transparent, mottled centre. Check the alpha of every panel candidate.

**animateSprite (forge)**
- **`loop: false` still trims the sheet**, and frame 0 isn't guaranteed to be your input. With `frames: 16, frame_size: -9, crop: false, final_image = initial_image`, four 1.5 s requests came back as 1.375 / 1.5 / 1.25 / 1.4375 s. The 1.25 s take (cel v2) started mid-motion, 8 px lower than the base. Gate every sheet on "frame 0 matches the base" before you use it. [A-PROBE]
- A one-phrase thrust-and-return with `final_image` = base worked in **1 of 4 takes**. The failures: the spear swung overhead and pointed backwards (storybook v2); the figure turned to face left mid-clip even though the prompt says "stays facing right" (tabletop v2); and the clip started mid-motion with no thrust (cel v2). Cel v3 thrusts and returns, but loses the spearhead in frames 4–8. This backs STYLE_BIBLE §4.1: use animateSpriteKeyframes with a middle strike pose for attacks. [A-PROBE]
- **Pole-arm units don't fit the standard 384 canvas.** A spear held level is about 1.4× the figure's height. With a 240 px figure and feet at (176, 344), the resting spear already reaches x ≈ 351–359, so a thrust leaves the cell (tabletop frames 1–2 touch the right edge). Give pole-arms a wider canvas, or carry the spear vertically in the base pose. [A-PROBE]

**Jobs, queue, budget**
- `DELETE /assets/jobs/{id}` on a queued job refunds everything (`credits_charged: 0`). **The request_id stays attached to the canceled job**: re-sending the same id returns that canceled job, so bump the version. [A-PROBE: jobs ac3238fa…, b6d53530…]
- `credits.available` drops by the full hold **when a job is accepted**, not when it finishes. A budget guard should use `balance_before − available` (which already includes in-flight jobs) plus the next call's cost. Adding your own in-flight tally on top counts those jobs twice. The probe's guard did that and falsely blocked a call at 28 + 9 + 4. [A-PROBE]
- Throughput at 01:25–01:50 ET: 2 jobs ran at once and the rest waited FIFO. Images took about 50 s each once started. Forge 1.5 s sheets took 1–3 min. [A-PROBE]

**Post / gates**
- Feet anchor for a three-quarter figure: the bottom 6% of the alpha catches only the rear boot. That put the storybook spear 15 px off the 384 canvas, and the queued job was canceled and redone. Use the bbox midpoint of the bottom 15%. [A-PROBE]
- editImage with the T-ironform block kept the silhouette on 6/6 candidates (alpha IoU 0.96–0.995 against the base, height ±0.4%). It sometimes left the face as flesh (storybook c1), or turned the spear and plume to iron as well (storybook c2, cel c1). [A-PROBE]
- Forest `texture` from these prompts renders too dark. All 6 candidates have mean L\* 27–30, against STYLE_BIBLE §1.2's 40–78 (forest anchor 46). Their seams already wrap (edge step / inner step 0.75–1.15), so they need a value lift in post or prompt, not a seam fix. [A-PROBE]

## 11. Findings from the ASCENDANT M1 batch (2026-09-30)

Source key: **[A-M1]** `coterboat/ascendant` batch `asc-m1-batch1` (issue #10): per-call ledger `studio/ledgers/asc-m1-batch1.jsonl` (request bodies, with base64 images shortened), contact sheet `studio/contact-sheets/asc-m1-batch1.png`. Candidates are kept locally, not in git.

**Prompts**
- **Check every manifest prompt against its §6 block before sending.** All three M1 terrain rows in `design/ASSET_MANIFEST.md` @ 80f85b7 read `ui_asset Subject: …`, because the C-terrain block had been replaced by the literal string `ui_asset`. The batch sent `C-terrain (v2, lighter) + " Subject: " + <manifest subject>`, and the driver asserts the block before every terrain call. Banner and portrait rows matched C-banner and C-portrait exactly. [A-M1]
- **`generateWithStyle` has no `art_style`, `perspective` or `aspect_ratio` field.** Only `style_image`, `prompt`, `image_type`, `n` and `augment_prompt` are sent, so "art_style Cel-Shaded" applies to createImage calls only. Styled portraits came back **near-square** (992–1072 × 992–1072 RGBA, 18 of 18 images), unlike createImage `portrait` + `ar_3_4` (848/880 × 1152). A 3:4 crop from a square loses about 12% at each side, and knights c3's upright lance sat in that strip. Prompt held items toward the middle, or pick candidates whose item survives the 3:4 crop. [A-M1]
- **`portrait` returns native alpha.** It comes back as RGBA with the background removed, even though C-portrait asks for "plain softly graded deep indigo background" (21 of 21 images). The manifest wants opaque webp q90, so the batch flattens every pick onto one code-drawn radial gradient (#333052 → #1C1B2A). That keeps all 8 backgrounds identical. [A-M1]

**Style references leak palette and costume**
- **A style reference passes its palette and costume across factions.** With the kingdom spearman as `style_image`, **8 of 9 beast portraits wore the kingdom's royal-blue tabard with gold trim**: war bear 3/3, fangthrowers 3/3, warchief 3/3 (also rendered as human faces with lion ears, not a lion-headed beastman), and tuskers 2/3. With the blue kingdom banner (probe c2) as `style_image`, **3 of 3 beast banners had blue cloth or blue bands**. That fails the "the two factions/banners differ in hue at a glance" gates. [A-M1]
  - Fix used: a **per-faction anchor**. The one clean beast (tuskers c2, itself styled from the spearman, so it keeps the series look) became `assets/_anchors/portrait_beasts.webp` for the remaining beast rows. For the beast banner, a **greyscale copy** of the banner anchor (`banner_grey.webp`) carries the linework and shading without the hue. Outcome: **unverified**. All 14 jobs sent with these two anchors died in the outage below (beast banner v2–v5, fangthrowers v2–v5, war bear v2–v4, warchief v2–v4).
- Styled portraits frame the face higher than the createImage anchor. The spearman anchor had eyes at 39.5%, and the styled picks had them at 29–36%. Measure every pick with a 1%-tick ruler on the 384×512 frame; eyeballing a coarse ruler was 4–5 points high. Move the figure down (the alpha cutout leaves background above) only when nothing touches the top edge. [A-M1]

**Terrain**
- The C-terrain v2 ("bright sunlit daylight") block lifted forest from mean L\* 27–30 (probe) to **52.5–55.8** (3 of 3), now 6.5–9.8 **above** the 46 target. A Lab L\* shift of −9.8 (a/b kept) hit 46.0, with chroma 41.9 and the seam ratio 0.74 → 0.97 (the 3×3 tile shows no seam). Plains and hills (styled from the corrected forest) never came back: 13 attempts, all 500s, so the ≥ 12 L\* spread between terrains is still unmeasured.
- **The "≤ 15 L\* variation inside a texture" gate needs a defined metric.** Per pixel, the forest's p5–p95 L\* is about 55 (canopy highlight against the gaps). On 64 px blocks (an 8×8 grid, about what one province shows at map zoom) it's 8.4. The batch reports both. The bible should say which one gates. [A-M1]

**Reliability**
- **Ludo image jobs failed in a run with `500 "AI server timeout. Please try again."`** After the last success at 10:50 ET, **31 consecutive jobs failed** until the batch stopped at 12:26 (createImage and generateWithStyle alike, charged 0), after 4–20 minutes each. Before that, 2 of 11 failed the same way, so 33 of 42 overall. Every failure refunds, but the request id is burned, so bump `v`. Run a retry driver that keeps at most 2 jobs in flight, bumps `v` on failure, and stops at a deadline. Don't hand-resubmit. **Running jobs can't be canceled**: `DELETE` answers 409 "Job is not in a cancelable state", so a job you stop polling still holds its credits until it resolves. Keep polling it to the end. The in-flight hold math from §10 held throughout: `6850.1 − available` always equalled charged + held. [A-M1]
