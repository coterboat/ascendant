# Review Table: accept or reject generated assets

A small local tool for going through AI-generated assets: concept art, 3D models, voice lines, music, images and video.
You listen or look, mark each one **accept** or **reject** (concept art: **Good**, **Good with changes** or **Bad**),
optionally fix the line text or add a note.
Then **Finish review** (`F`) installs the keepers where they belong and has the generator redo the rejects,
from buttons in the page, with the output streaming into a log drawer.

It uses only the Python 3 standard library: one script (`review.py`) and one HTML page (`index.html`).
It serves on `127.0.0.1` only. The one thing it carries that is not ours is the 3D viewer, Google's `<model-viewer>`, committed in
`vendor/` (see `vendor/README.md` for the version, the license and how to update it), so the page works offline.

```sh
python3 tools/review/review.py serve --open        # UI at http://127.0.0.1:8766
python3 tools/review/review.py sample              # optional: build the demo batches (_sample, _sample_concept, _sample_models)
python3 tools/review/test_review.py                # the tool's own tests (throwaway batches, no Ludo calls)
```

After changing `review.py`, restart `serve`: the page is re-read on every load, the server code is not.

## Commands

| command | what it does |
|---|---|
| `serve [--port 8766] [--open] [--verbose]` | Serves the UI plus a JSON API, and lists every batch under `review/`. Stopping it cancels any action still running. |
| `status [<batch>]` | Shows accepted / rejected / pending / missing counts for each group. |
| `apply <batch> [--dry-run]` | Copies every **accepted** file to its `target`, then writes `review/<batch>/rejected.json`. |
| `canon <batch> [--dry-run]` | Concept batches: copies every **Good** and **Good with changes** take into `assets/_concept/lore/<group>/` and writes that folder's `CANON.md`, then `rejected.json`. See [Canon](#canon-where-concept-art-ends-up). |
| `new <batch> --title "..." [--mode concept]` | Creates an empty `batch.json` (a concept batch with `--mode concept`). |
| `from-folder <dir> <batch> [--title T] [--mode concept] [--group-by prefix\|folder] [--recursive] [--sidecar JSON] [--target-dir DIR] [--add]` | Builds `review/<batch>/` from a folder of images, models, audio or video the art rounds wrote, and an optional `prompts.json`. See [A batch from a folder](#a-batch-from-a-folder). |
| `sample [--force]` | Builds the demo batches that are missing: `_sample` (voices and pictures), `_sample_concept` (crests from three seats, to judge blind) and `_sample_models` (two ruler models, each with a different one as "in game now"). `--force` wipes them and their verdicts. |
| `lessons [--write MD] [--json]` | What every batch's verdicts and notes say: first takes kept by kind and by voice, how each art seat did, and the note themes. `--write <file.md>` refreshes the block between `<!-- lessons:begin -->` and `<!-- lessons:end -->`. |

`apply` creates the target folders it needs and skips files that are already identical, so it is safe to run again.
If the target has a different extension from the source (for example, the target says `.mp3` but the file is `.wav`),
it copies the file next to the target using the source's extension and prints a warning.
Items that were regenerated after their verdict are not copied until you have listened to them again.

## Keys

| key | action |
|---|---|
| `Space` | Play or pause the current line or video (on an image without a video, or on a model, opens it large) |
| `↓` / `J`, `↑` / `K` | Move to the next or previous item (`Home` / `End` jump to the first or last) |
| `A` | Accept, then move on (concept batch: **Good**) |
| `C` | Concept batches only: **Good with changes**. Opens the note; a note is required. |
| `R` | Reject, then move on (concept batch: **Bad**; a note is optional) |
| `U` | Set the item back to pending |
| `←` / `→` | Previous / next take, when an item was rolled more than once. With autoplay on, each one plays. |
| `1`–`9` | Go to take N and play it. `A` keeps the take you are on. |
| `0` | Play (or show) what the game has now: the file this item would replace (a model: shown in its own viewer, `0` again goes back). |
| `B` | **Blind** on or off: hide which seat made each take until the item has a verdict (see [Seats](#seats-takes-from-several-artists-judged-blind)) |
| `W` | Lessons: what every review so far says about the prompts |
| `E` | Edit the line text for the re-roll. `Enter` saves the edit and marks the item **rejected**; `Esc` cancels. |
| `N` | Add or edit a note. `Enter` saves, `Esc` cancels. |
| `P` | Toggle **autoplay next** (on by default): after `A` or `R`, the next line or video starts playing |
| `V` | Show or hide the video behind an item (a GIF or poster frame with an mp4). On a video item, view it large. |
| `L` | Loop videos on or off |
| `Z` | View large: the image, the 3D model, or the video (with the browser's own controls and fullscreen). `Esc` closes. |
| `T` | 3D models: turntable on or off |
| `F` | **Finish review**: the counts, then the batch's actions. In there, `1`–`9` runs that action, `Esc` closes. |
| `O` | Open or close the run log (`Esc` closes it too) |
| `?` | Show the key help |

The fast loop is: listen, press `A` or `R`, and the next line plays on its own.
Every action also has a button. The page remembers your last batch, filter and position.
Clicking **Rescan** (or switching back to the browser window) picks up new or regenerated files.

**Flagged** marks spoken lines whose length looks wrong for their text: audio items with `meta.voice` set.
Music, sound effects and video are never length-checked. Lengths are measured in the browser as items load.

- A clip is flagged as too long when it runs longer than `words / 1.6 + 1.5` seconds. That usually means a glitch or repeated words.
- A clip is flagged as too short when it runs shorter than `words / 4.5` seconds. That usually means it was cut off.
- Files that are missing or fail to load are flagged too.
- Words inside `[brackets]` (audio tags) are not counted.

## Concept mode: Good, Good with changes, Bad

Concept art is judged differently from a voice line: it is rarely "right" or "wrong", it is *this one, but...*.
A batch with `"mode": "concept"` in its `batch.json` (or `review.py new <batch> --mode concept`) gets three verdicts:

| key | button | stored as | what it means |
|---|---|---|---|
| `A` | **Good** | `accept` | keep this as it is |
| `C` | **Good with changes** | `revise` | keep what works; the note says what to change. **The note is required**: `C` opens it, and `Enter` saves the verdict with the note. |
| `R` | **Bad** | `reject` | do it again; a note is optional |

- `revise` counts as **kept**: it is counted with the accepted ones in the progress bar and in Finish review, and `apply`
  copies it to its `target` like an accept. Its note travels with it. The server refuses a `revise` without a note, and
  refuses to empty the note of a `revise` item. `revise` only exists in concept batches (`decide` answers 400 otherwise).
- The sidebar tabs read **Good**, **Good with changes**, **In canon** and **Bad**, and the rows show the picture larger,
  because the picture is the point. `E` edits the prompt (it marks the item Bad, like editing a line).
- `N` opens the note with art chips: "More like this", "Wrong palette", "Reads like another faction", "Text in the image",
  "Not a lookalike of …" (the dots are selected so you can type the name over them), "Keep the silhouette, change the detail".
  They are written the same way every time so `lessons` can sort them into themes (`palette`, `faction`, `text_in_image`,
  `lookalike`, `silhouette`, `more_like`).
- The built-in install action of a concept batch is **Add to canon** (`review.py canon <batch>`, below).
- `rejected.json` of a concept batch carries the `revise` items too, so the next art round redoes both; each entry says
  which with `verdict`: `reject` = start again, `revise` = keep what works and apply the note.
- `lessons` counts `revise` in its own column (kept, with changes asked for), and a `revise` note stays "open" until the
  item is redone.

## Canon: where concept art ends up

`review.py canon <batch>` (the **Add to canon** button in Finish review, `F`) is the built-in install action of a concept batch.
It makes the approved art the reference that later 3D work starts from:

- every **Good** and **Good with changes** item (the take you kept, when it has several) is copied to
  `assets/_concept/lore/<group>/<item id>.<ext>`. `<group>` is the item's `group` (made safe for a folder name; `ungrouped` when
  it has none). Godot already ignores `assets/_concept/`, so nothing is imported.
- `assets/_concept/lore/<group>/CANON.md` gets one entry per image: **image** (shown, and its file name), **verdict**, **note**,
  **prompt**, **seat**, **batch** and **date** (of the verdict). Each entry sits between `<!-- canon:item ... -->` and
  `<!-- /canon:item -->` markers, so the next run updates it in place; anything you write in the file outside the markers is kept.
- it is safe to run again: identical images are left alone (`=`), an entry is rewritten only when something changed, and a
  redone image (a newer file for an item you accepted again) replaces its copy. An item that is no longer Good or Good with
  changes loses its entry (the run says so), but **an image is never deleted**.
- it never overwrites what it did not write: when `<item id>.<ext>` is already another batch's canon image, or a file nobody wrote
  through `canon`, the entry's image is named `<item id>__<batch>.<ext>` instead.
- `--dry-run` lists what it would do and writes nothing. It also writes `review/<batch>/rejected.json` (the Bad items, and the
  Good with changes ones with their notes) for the next round.
- from the page, the run marks the kept takes **In canon** (their tab), and **in canon now** (`0`) shows what canon has for an
  item next to the take you are on. The demo batch's groups start with `sample_`, so what it writes
  (`assets/_concept/lore/sample_*/`) is gitignored and easy to delete.

## Seats: takes from several artists, judged blind

Concept art is often made by more than one seat (`claude`, `codex`, `grok`) from the same brief. Say who made what, and
the table lets you judge the pictures without knowing:

```json
{"id": "aurel_crest", "kind": "image", "group": "aurel", "label": "Aurel crest", "text": "<the prompt>",
 "file": "codex/aurel_crest.png", "seat": "codex",
 "takes": [{"file": "grok/aurel_crest.png", "label": "take 2", "seat": "grok"},
           {"file": "claude/aurel_crest.png", "label": "take 3", "seat": "claude"}]}
```

- `seat` on the item is the seat of its own `file`; each entry of `takes` may carry its own `seat`. A seat is a short
  lowercase name (`claude`, `codex` and `grok` get their own colour; anything matching `[a-z0-9][a-z0-9_-]*`, up to 24
  characters, works; anything else is dropped).
- **Blind** (the sidebar toggle, or `B`) is on by default in a concept batch and remembered once you change it. While it is on
  and an item has no verdict, the takes read "take A", "take B" and no seat name is shown. The takes of an item that has seats
  are shown in a fixed shuffled order (the same on every visit, different for each item), so the first one is not always the
  same seat; the one on screen when you open the item is the first of that order. `←`/`→` and `1`–`9` follow the order shown.
- The verdict reveals them: the chips read the seat names (colour-coded, the kept one ticked), and a toast says "That was codex".
  Blind hides names on the page, not in the page's network traffic: it is for fair judging, not a secret.
- **Good** or **Good with changes** keep the take you are on and record it as the item's `pick`, as for any item with takes.
  **Bad** rejects every take of the item.
- **Lessons** (`W`, `review.py lessons`) adds a tally by seat: **good** and **good with changes** count for the seat whose take
  was kept, **passed over** counts for the other seats that had a take on that item, and **bad** counts against every seat that
  made a take on an item that was rejected. Items with no seats are not counted.
- `rejected.json` of a concept batch names the take each verdict is about (`file`, `seat`) and lists every candidate in `takes`
  (`[{"file", "seat"}]`), so the next round can have each seat redo its own.

## Takes, and what the game has now (v1.11)

An item may have been rolled more than once. Its **takes** show as a strip under it: the item's own file first,
then the others. `←`/`→` or `1`–`9` move between them and play them. **Accept** keeps the take you are on and
records it as the item's `pick`, which **Install**, `apply`, **In game** and `reconcile` all use from then on.
**Reject** rejects every take (the redo rolls new ones), and so does **Undo**, which clears the pick.

The takes are found beside the item's file, in a `.takes/` folder:

- `<stem>.t2.mp3`, `<stem>.t3.mp3`: more rolls of the same take (a generator's `--takes N` writes these).
- `<stem>.r1.mp3`, `r2`, …: takes rejected in earlier rounds, higher is newer (a voice redo moves the rejected
  file here). They show dashed, as "rejected in round N", so a new take can be heard against the old one.

A batch can also list them itself: `"takes": [{"file": "...", "label": "...", "seat": "..."}]` on the item (`seat` is optional,
see [Seats](#seats-takes-from-several-artists-judged-blind)). A generator can put
a few words on each take's chip with `meta.take_info` (`{"<file>": "falls 3.1 st, pause 0.49 s"}`), for example
what it measured on the take, and may put the best-measured take first.

When an item's `target` (or its first `meta.install` destination) already exists in the game and differs from the
take kept, the strip ends with **in game now** (`0`): it plays the game's copy, or shows it in the viewer for a
picture, or in the row's own 3D viewer for a model. Only media files (and `.glb` / `.gltf`) are served that way, never a
dotfile or anything outside the repo.

When a note changed what a voice was asked to say, `meta.speak` shows as **spoken as** under the line.

## Notes that teach

`N` opens the note with a row of **chips**: the notes the owner writes most, in the same words every time
("More pause between sentences", "Falling inflection at the end", "Keep it all in frame"…). Click one to add it.
"Stress \*word\*" selects *word* so you can type over it. Matching wording lets `lessons` sort notes into themes,
and a generator's redo can read the same themes to steer the next take (the hook is `note_themes()` in `review.py`; the
voice and Ludo glue Concurrent has on top of it is not ported). **Lessons** (`W`) shows the totals.

## Video

Items with `"kind": "video"` (mp4, webm, mov, m4v; `.ogv` too) play in the row: a player area under the text,
bigger on the current row, with a seek bar, the length, **Loop** (`L`) and **Large** (`Z`).
Only one thing plays at a time, and autoplay next works for video like it does for audio.
An optional `"poster"` (an image in the batch folder) is shown until the clip plays; without one,
the first frame is used.

An image item (a GIF, a poster frame) can carry the clip it came from: `"video": "<file>"` on the item, or
`meta.video_mp4` / `meta.video_webm` / `meta.video`, relative to the batch folder or to the repo root
(`review/<batch>/…`). A poster named `x_poster.png` next to `x.mp4` is picked up on its own. The row then shows
that clip under the image (`V` hides it, and `Space` plays it while it is shown). An audio item that carries a clip
(a soundtrack) gets a **▶ video** button instead.

Each clip is measured once: its size, length, and **loop seam**, which is how different the last frame is from the first.
Under 3% loops without a visible jump; over 8% jumps. That is the thing to check on a "living painting".

Chrome and Safari no longer decode Theora, so an `.ogv` (or Ogg video) item says so instead of showing a dead player:
open it in VLC or Godot, or review an mp4 of it.

## 3D models

Items with `"kind": "model"` (`.glb`, `.gltf`; guessed from the extension when `kind` is left out) get an orbit viewer in the
row, under the text, bigger on the current row:

- **drag** to turn the model, **scroll** over it to zoom (scrolling anywhere else scrolls the list), and it **turns by itself**
  (the turntable, `T`) on the current row only; touch it and it waits a moment, then carries on.
- **Reset view** goes back to the front; **Large** (`Z`, or `Space`) opens it big. `Esc` closes.
- The line under the text gives the model's bounding box as the file says it, the type and the size.
- **In game now** (`0`): when the item's `target` (or its first `meta.install` destination) already exists in the game and
  differs from the model you are looking at, `0` swaps the same viewer to the game's copy (badge "in game now") and back, so
  the new model and the old one can be compared from the same angle. Models rolled more than once have takes like anything else.
- Accepting, rejecting, notes, takes and `apply` work as for any item. The note chips for a model are "Doesn't match the concept
  art", "Proportions are off", "Texture is blurry or muddy", "Holes or broken geometry" and "Wrong pose"; `lessons` sorts them
  into the `concept_match`, `proportions`, `texture`, `geometry` and `pose` themes.
- A model that fails to load shows why and is listed under **Flagged**.

The viewer is Google's `<model-viewer>` 4.3.1, served from `tools/review/vendor/` at `/vendor/model-viewer.min.js` (nothing
else is served from there), with its neutral built-in lighting: no CDN, no HDR file to fetch, works with no network.
`.glb` is served as `model/gltf-binary` and `.gltf` as `model/gltf+json`, with HTTP Range support like all media. A `.gltf` with
external buffers or textures works when they sit next to it in the batch folder. Draco and KTX2 compressed files need decoders
that are not vendored; they show as a failed load (see `vendor/README.md`).

## Finish review: actions

**Finish review** (`F`, or the button above the list) shows accepted / rejected / pending / needs-a-listen counts,
warns when something is still pending, and lists the batch's **actions** as big buttons with their options.
The first few actions also have their own buttons next to it. A run's output streams into the log drawer at the
bottom (status, elapsed time, **Cancel run**), and when it ends the batch is rescanned: regenerated files come back
as **needs a listen**. `O` reopens the drawer later, with the last few runs of the batch (until the server restarts).
Every run is also appended to `review/<batch>/runs.log`, with a timestamped header.

A batch declares its actions in `batch.json`:

```json
"actions": [
  {"id": "install", "kind": "install", "label": "Install accepted",
   "help": "Copy the accepted takes into the game, then re-import in Godot",
   "cmd": ["python3", "tools/ludo/your_generator.py", "--install"],
   "options": [{"flag": "--dry-run", "label": "Dry run", "type": "bool", "default": false}]},
  {"id": "regen", "kind": "regen", "label": "Redo rejected",
   "help": "Regenerate every rejected take with Ludo (spends credits)",
   "cmd": ["python3", "tools/ludo/your_generator.py", "--regen"], "spends": true,
   "options": [{"flag": "--takes", "label": "Takes per line", "type": "int", "default": 1, "min": 1, "max": 4}]}
]
```

- `id`: unique in the batch (`[A-Za-z0-9_.-]`). `label` is the button; `help` is the line under it.
- `kind`: `install` and `regen` are the two the page knows (a green and a red button). Anything else is a plain extra action.
  Before a `regen` action runs, the tool rewrites `review/<batch>/rejected.json` from the current verdicts,
  so the generator always re-rolls exactly what is rejected now.
- `cmd`: `cmd[0]` must be `"python3"` (it runs as the Python that runs the server); `cmd[1]` must be a script inside the repo,
  relative to the repo root; the rest are fixed arguments. It runs with the repo root as its folder, the server's environment
  (plus `PYTHONUNBUFFERED=1`, so the output streams), and no stdin. One run at a time per batch.
- `options`: what the page shows as controls. Each has a `flag` (`--name`), a `label`, an optional `help`, a `type`, and a `default`:
  - `bool`: a checkbox; the flag is passed when it is ticked.
  - `int`: a number box, with optional `min` / `max`; passed as `--flag N`.
  - `string`: a text box; passed as `--flag value` (one line, at most 500 characters, and it may not start with `-`). Empty is left out.
  - `choice`: a drop-down of `choices`; passed as `--flag value`.
  Only declare flags the script really takes. An option the page leaves unset is not passed, so the script's own default applies.
- `spends: true`: running it asks first, saying it spends Ludo credits and how many items are rejected.

A batch without `actions` gets one built-in action, **Install accepted**, which runs this tool's own
`python3 tools/review/review.py apply <batch>` (with a **Dry run** option); a concept batch gets **Add to canon**, which runs
`python3 tools/review/review.py canon <batch>` instead. There is no **Redo rejected** then:
the button is there but disabled, because only the generator knows how to re-roll.

An action that doesn't pass these checks still shows, disabled, with the reason.

### Security

The server only listens on `127.0.0.1` and refuses requests addressed to any other host name. A web page open in your
browser could still try to POST to it, so every request that changes something (a verdict, starting or cancelling a run)
must carry the `X-Review-Token` header: a random token made when the server starts and written into the page it serves.
Requests with an `Origin` header other than the server's own are refused, and bodies must be `application/json`.
The page cannot send a command: it names an action and option values, and the server builds the command from `batch.json`
after checking every value. The page also refuses to be shown inside another site's frame, and its Content-Security-Policy
allows nothing from outside this server (`default-src 'self'`; no CDN, no external fonts or scripts), with `'wasm-unsafe-eval'`
only so the vendored viewer can compile its WebAssembly (it does not allow `eval()`). `/vendor/` serves `.js` files that sit
directly in `tools/review/vendor/`, and nothing else.

## A batch from a folder

An art round does not have to write `batch.json` by hand: drop its output in a folder and run

```sh
python3 tools/review/review.py from-folder art/round2 art_r2 --title "Round 2 portraits" --mode concept --group-by prefix
```

It copies the media into `review/<batch>/` (keeping the folder's layout) and writes `batch.json`. Every image, model (`.glb`,
`.gltf`), audio and video file in the folder becomes an item with its `kind` set; dotfiles and everything else (a dossier `.md`, a
`ref/` folder) are left alone, and so are sub-folders unless you pass `--recursive`. Nothing is overwritten: if the batch exists it
refuses, unless you pass `--add`, which lists only the files the batch does not have yet and leaves its verdicts alone. If the
folder already *is* `review/<batch>/`, nothing is copied.

- `--group-by prefix` makes the group the file name up to its last underscore, and the label the rest: `ember_orchard_ruler1.png`
  becomes group `ember_orchard`, label `ruler1`. `--group-by folder` uses the sub-folder (with `--recursive`). Default: no group.
- `--mode concept` writes `"mode": "concept"` (see [Concept mode](#concept-mode-good-good-with-changes-bad)).
- `--target-dir assets/models/rulers` gives every item the target `<dir>/<file name>`, so **Install accepted** has somewhere to put
  it. It must be inside the repo. (A concept batch has no targets: it installs with `canon`.)
- A `.gltf` brings the `.bin` and texture files it points at, and they are not items of their own.
- **`prompts.json`** (in the folder, or `--sidecar PATH`): what the generator knew about each file, keyed by its path in the folder
  (or just its file name):

```json
{"ember_orchard_ruler1.png": {"prompt": "Grandmother Cinderpod, ...", "seat": "codex", "group": "ember_orchard", "label": "Ruler 1"},
 "ember_orchard_ruler2.png": "a plain string is the prompt"}
```

  `prompt` becomes the item's `text`, `seat` is who made it, `group` and `label` override the defaults above. Optional too:
  `meta` (copied into the item's `meta`), `target` (this file's install target), and `item`. A folder whose name is a seat (`claude`,
  `codex`, `grok`), or a sub-folder of that name, sets the seat of the files in it when `prompts.json` doesn't. A name in the
  sidecar that matches no file is printed as a warning.
- **Takes from several seats:** files whose entries share an `item` name are the takes of one item. The first by path is the item's
  own file, the others are its `takes` (`take 2`, `take 3`, with their seats), and the entries fill in what the first lacks:

```json
{"codex/aurel.png": {"item": "aurel", "prompt": "the Aurel crest", "group": "aurel", "label": "Aurel crest"},
 "grok/aurel.png": {"item": "aurel"}, "claude/aurel.png": {"item": "aurel"}}
```

  (`python3 tools/review/review.py from-folder art/crests crests --mode concept --recursive`)

## The files

Everything lives in `review/<batch>/` at the repo root. `review/*/` is gitignored, and `review/.gdignore` keeps Godot from importing the files.

### `batch.json`, written by the generator

```json
{
  "batch": "voices_r1",
  "title": "Voice lines, round 1",
  "items": [
    {"id": "advisor.capture.v2", "kind": "audio", "group": "advisor", "label": "capture · variant 2",
     "text": "Another land for the empire!", "file": "advisor/capture_v2.mp3",
     "target": "assets/voice/advisor/capture_v2.mp3",
     "meta": {"voice": "voice_advisor", "manifest_id": "line18_advisor_capture_v2", "context": "we took a land"}}
  ]
}
```

- `id`: unique within the batch. Verdicts are keyed on it.
- `kind`: `"audio"` (mp3, wav, ogg, m4a), `"image"` (png, webp, jpg, gif), `"video"` (mp4, webm, mov, m4v, ogv) or
  `"model"` (glb, gltf; see [3D models](#3d-models)). Left out, it is guessed from the extension.
- `file`: path relative to the batch folder. The file may be missing while it is still generating. It then shows as *missing* and cannot be accepted.
- `target`: path relative to the repo, where `apply` copies the file once it is accepted.
- `group`: used by the group filter, for example a character name.
- `label`: the row title.
- `text`: optional. The spoken line, or the image prompt.
- `meta`: free-form. If `meta.context` is present, it is shown as a small *when: …* hint. `meta.voice` marks a spoken line (length-checked).
- `mode` (top level, next to `items`): `"concept"` for concept art (see [Concept mode](#concept-mode-good-good-with-changes-bad)); left out, it is a standard batch.
- `poster` (video items) and `video` (image items): see [Video](#video).
- `actions` (top level, next to `items`): see [Finish review](#finish-review-actions).

### `review.json`, written by the tool

```json
{"items": {"advisor.capture.v2": {"verdict": "accept", "note": "", "text": "edited text (only if edited)",
                                  "at": "2026-09-27T12:00:00", "file_mtime": 1727400000.0}}}
```

- `verdict` is `accept`, `reject` or `pending`, and in a concept batch also `revise`. An item with no entry is pending.
- `pick` (v1.11): the take that was accepted, relative to the batch folder, when it isn't the item's own file.
- `file_mtime` is the file's mtime when the verdict was given. If the file on disk is newer, the item was regenerated: it counts as pending again ("needs a listen"), and the old verdict and note stay visible.
- When you re-decide a regenerated item, the old verdict moves into a `history` list.

### `rejected.json`, written by `apply` (and before a `regen` action runs)

```json
[{"id": "advisor.loss.v1", "text": "We have lost the river crossing, Commander.", "note": "too flat", "meta": {"voice": "voice_advisor"}}]
```

`text` is the edited text when there is one, otherwise the original. In a concept batch each entry also has
`"verdict": "reject"` or `"revise"`, the item's `group`, the `file` the verdict is about (the take that was kept, for a `revise`),
its `seat` when it has one, and all the candidates as `takes` when there are several. The `revise` items are listed with their notes:

```json
[{"id": "ruler1", "text": "<prompt>", "note": "Wrong palette", "meta": {}, "verdict": "revise", "group": "ember_orchard",
  "file": "grok/ruler1.png", "seat": "grok", "takes": [{"file": "codex/ruler1.png", "seat": "codex"}, {"file": "grok/ruler1.png", "seat": "grok"}]}]
```

## How a generator should use this

1. Write the media files into `review/<batch>/…`, then write `batch.json` with one item per file, and the `actions` that
   install and re-roll them. Use `new` to start an empty one.
   To be safe from half-written reads, write to a temp file and rename it into place.
2. Let the human review in the UI. They finish with the install action (or `apply <batch>` by hand).
3. The regen action (or you, by hand) reads `review/<batch>/rejected.json`. For each entry, regenerate using `text`
   (and `note` as guidance) and the voice or model settings in `meta`.
   **Overwrite the same `file` path.** The newer mtime is what puts the item back in the queue as "needs a listen".
   Also update the item's `text` in `batch.json` if you used the edited wording.
   To offer several takes, write the extras to `.takes/<stem>.t2.<ext>` and so on, and move the rejected file to
   `.takes/<stem>.r<N>.<ext>` first so it can be compared (see [Takes](#takes-and-what-the-game-has-now-v111)).
4. Repeat until nothing is rejected.

A generator plugs in through the batch's `actions` (its `--install` and `--regen` commands) and by reading `rejected.json`.
The tools in `tools/ludo/` are the ones that would write `--batch` output; none does yet (phase 2).

API, for scripts that want it:

| request | what it does |
|---|---|
| `GET /api/batches` | every batch, with counts |
| `GET /api/batch/<batch>` | items merged with verdicts and a computed `status`, plus the batch's `actions` |
| `POST /api/decide` `{batch, id, verdict?, note?, text?}` | give a verdict, note or edited text |
| `POST /api/run` `{batch, action, options?}` | start an action; returns `{run: {id, status, …}}` (409 while one is running for that batch) |
| `GET /api/run/<id>?from=<offset>` | the output since `offset`, the `next` offset, `status` (`running`, `ok`, `failed`, `cancelled`), `code`, `elapsed` |
| `POST /api/run/<id>/cancel` | stop it: SIGTERM to its whole process group, SIGKILL 3 s later if it is still there |
| `GET /api/runs?batch=<batch>` | the batch's last few runs, newest first |

Every POST needs `Content-Type: application/json` and the `X-Review-Token` header (see [Security](#security)).
Media is served from `/media/<batch>/<file>` with its type (audio, image, video and model) and supports HTTP Range requests.
`GET /game/<batch>/<item>` is the copy of an item in the game, and `GET /vendor/model-viewer.min.js` is the 3D viewer.
