# Lanes

The studio runs as one **director** session and a few standing **lanes**. A lane is a long-lived Claude session with one shape of
work: it takes that shape's tickets in order, one at a time, and keeps what it learned about its part of the code from one ticket
to the next. The director cuts tickets, verifies, merges, and holds the slot. Alex plays, decides, and can talk to any lane directly.

Session names are the addresses: **`ascendant director`**, **`ascendant lane UI`**, **`ascendant lane Art`**, **`ascendant lane AI`**,
**`ascendant lane Candlewake`**, **`ascendant lane QA`**, **`ascendant lane 3D`**. Past the MVP, work lands on the `next` branch: read "Past the MVP" at the end
first, because it changes the base branch, the slot and what READY needs.

## The director
- Cuts tickets (one GitHub issue each) and gives each lane its queue. Routes design questions: Alex's calls go to him as numbered
  questions with lettered options and a pick; provisional calls are logged on #25 with the option picked.
- Verifies every PR merged with current main (compile, full suite, boots with every flag, the shots), merges one at a time, and
  logs each merge on #25. **Only the director merges or pushes to main.**
- Holds the slot (below), and may still hand a one-off ticket to a builder subagent when no lane fits or the lane is busy.
- At most three lanes and builders building at once.

## The slot
One full Godot suite or autoplay matrix at a time on this Mac, across the studio (Alex 10-11: parallel suites nearly bricked it).
- Before a full suite or a matrix, send the director `SLOT? <ticket> <what> on <sha>` and wait for `GO`.
- When it's done: `DONE <ticket> <passed>/<failed> on <sha>, slot free`.
- Compile checks, focused `--only=` runs, boots and shot walks don't need the slot. Run shot walks with `--always-on-top`; a walk
  that stalls is a covered window, so ask for the slot and rerun.

## Messages
- Lanes message the director by name: `SendMessage(to: "ascendant director")`. The director answers each lane by its name.
- If the director can't be reached (restarted or compacted), leave a coter-kit note (`remember`, kind `thread`, to
  `ascendant director`) and keep going on whatever isn't blocked.
- Reports are one line:
  - `READY #<pr> <sha>: compile <n>/0, suite <n>/<n> on <sha>, boots 0 ERROR, shots <dir>`
  - `BLOCKED <ticket>: <why>`
  - `Q <ticket>: <numbered question, lettered options, your pick>`

## Every lane
- One branch and one PR per ticket, based on `refs/remotes/origin/main`. `Closes #<n>` on its own line, a `playtest:` line, the
  provisional calls under "Decisions I made on my own".
- Never merge or push main. Commit by path, never `git add -A`. Never call EnterWorktree or ExitWorktree.
- `design/`, `playtest/` and `studio/` only when the ticket says so (CLAUDE.md).
- While a PR waits on the director, start the next ticket on a new branch. When the director says main moved under you, merge it.
- Derive test numbers from data, never hardcode stats or gold.
- Godot on the Mac: `/Users/coterboat/Downloads/Godot.app/Contents/MacOS/Godot`; `--headless --path . --import` first in a fresh
  worktree and after adding a `class_name`; boots are headless only (`--quit-after 120`, grep for ERROR).

## The lanes

### UI: `ascendant lane UI`
The War Table (`design/UX_WAR_TABLE.md`) and the screens: UX-5 #220, UX-8 #221, UX-9, then UI fixes from playtests.
- Owns `ui/`, `world3d/board_overlay.gd`, `tools/shots/`. A ticket that touches `ui/map_screen.gd` or `ui/game_screen.gd` says so
  in its PR; the director merges those one at a time.
- Every ticket: before and after shots at 1600x900, 1600x900 at 125% and 1280x720 (`tools/shots/play_shots.gd --defaults --fresh`),
  looked at by the lane before it says READY. Every new mechanic gets its tooltip, preview or codex line in the same PR.

### Art: `ascendant lane Art`
The art pipeline: Review Table batches (`review/<batch>/`, `tools/review/README.md`), `assets/`, the Ludo and Bake3D tools, the rig lab.
- Never accepts or rejects for Alex; he does that in the Review Table.
- **Base first** (Alex 10-8): a few style samples go to Alex before a full batch, and an approved base before anything derived from it.
- Each batch logs its credit spend. The 2D art Alex still wants: concept art (also as model3d inputs), portraits, lore and codex art.
- Queue: UX-ART #222 (the 32 notice medallions, keys in #218's PR body; `NoticeArt` picks up `assets/ui/notices/<key>.png` with no code
  change), then the rigged-model line (one Bake3D model per unit, our own clips; `tools/rig_lab/`), then what Alex picks.

### Rules and AI: `ascendant lane AI`
`rules/`, `ai/`, balance, and the playtest bots' AI findings: #182, #184, #183 and what playtests turn up.
- A rules change gets a Codex critic round on its issue before building (as ARM-1 did), and leaves every record, digest and
  fixture byte-identical unless the ticket says otherwise.
- Autoplay matrices always run under the slot, from a snapshot directory (the worktree changing mid-run leaks into the run).
- AI changes: a 4-game AI-vs-AI smoke early, not only constructed positions.

## Starting a lane
The director offers a chip with a short brief: who you are, your section of this file, your queue. Alex clicks it. A stopped lane
can be resumed and keeps its name. When the director restarts, it runs ListAgents and tells each lane it's back.

### Candlewake: `ascendant lane Candlewake`
Milestone C's rules (`design/CANDLEWAKE.md`, the third faction): CW-0, CW-1, CW-2, CW-3, CW-4, CW-5, CW-12, in that order.
- Owns `rules/` and `data/` for the Candlewake and the engine's third-faction seams. A ticket that touches `ui/` or `world3d/` beyond a
  line or two hands that part to lane UI (CW-7, CW-8) through the director.
- Every Crown–Clans game stays byte-identical: records, digests and fixtures for every old feature combination (CW-0's gate).
- The faction ships behind the "Candlewake (preview)" box, off by default, until CW-11's bands pass.

### 3D: `ascendant lane 3D`
The board, the battle stage and the turn's playback: `world3d/` (except `board_overlay.gd`, lane UI's) and `ui/battle/`. #265 (battles with
three sides), CW-8 #259 (the Candlewake on the board), the `qa` findings filed for `3d`, then the battle feel.
- Every ticket: shots of the board and the stage before and after, windowed with `--always-on-top`, looked at before READY, and boots
  with `-- --world3d` and `-- --battle3d`. The playback never changes the outcome (GAME_BRIEF: battle presentation).

### QA: `ascendant lane QA`
Plays the game the way a player does and files what breaks: crashes, script errors, stuck states, clipped or overlapping UI, numbers
that don't explain themselves, slow frames.
- Owns `tools/qa/` (the crash-hunting harness) and nothing else; it files issues instead of fixing game code.
- Every finding is one GitHub issue labelled `qa`, with the steps, the seed, a shot and the log lines, and the lane that owns it
  (`ui`, `3d`, `rules`, `ai`, `art`) in the title. A crash or a lost game is `P0` in the title.

## Past the MVP: the `next` branch (from 2026-10-22)
Alex walked the MVP on 10-21 ("the core foundation is solid") and asked for refinement, polish and the rest of the game. Main stays
the build he plays; everything new lands on **`next`**, an integration branch the director verifies and merges into. Alex promotes
`next` to main when he has played it.
- **Base and PRs:** branch from `refs/remotes/origin/next` and open PRs against `next` (`gh pr create --base next`). A fix Alex needs
  in the build he plays (a crash) branches from `origin/main` and targets `main`; the director also merges it into `next`.
- **Stacking:** when your next ticket needs your own PR that isn't on `next` yet, branch from that PR's branch and say "stacked on
  #<n>" in the body. Never wait idle for a merge.
- **READY needs:** compile check 0 failed, focused runs (`-- --only=`) of every test file your change could touch, boots 0 ERROR
  (headless, plus `-- --world3d` when you touched `world3d/`), and shots for anything a player sees. **The full suite is the
  director's:** it runs on the merge candidate (`next` plus one or more PRs) and sends failures back to the lane.
- **The slot is a lock directory**, so nobody waits for a message: `mkdir /private/tmp/ascendant-slot` succeeds only for one
  process. Write `<lane> <ticket> <what> <sha> <time>` into `/private/tmp/ascendant-slot/owner`, run, then `rm -rf` it. If `mkdir`
  fails, keep working and wait with a background until-loop (`until mkdir /private/tmp/ascendant-slot 2>/dev/null; do sleep 30;
  done`). The slot covers full suites and autoplay matrices. A lock older than 2 hours whose owner's process is gone is stale:
  remove it and say so to the director.
- **CPU:** jobsnearme's lanes run Playwright on this Mac too, and alone they hold the 1-minute load at 20-24 (10-22), so waiting
  for a quiet machine means never running. Instead, every Godot run longer than a minute runs at low priority, so jobsnearme's
  e2e keeps the CPU it needs: `nice -n 10 <godot ...>`. Only multi-process work (autoplay matrices) also waits for a 1-minute
  load under 28, and then runs with `--jobs 2`. Lane QA runs one harness window at a time; its runs don't take the slot.
- **The main checkout** (`/Users/coterboat/Documents/GitHub/ascendant`) is Alex's: never edit, switch, commit or import there.
  Read from it only.
- **Questions don't stop a lane:** send `Q` to the director, take your pick provisionally, write it under "Decisions I made on my
  own", and keep going. The director logs the calls on #25 and asks Alex only what is truly his (art verdicts, spending, the brief).
- **Wrap-up:** when the director sends `WRAP UP` (the weekly usage line nears its cap), commit what's finished, push your branch,
  open or update a draft PR with where it stands and what's next, and stop.
