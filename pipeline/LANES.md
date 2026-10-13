# Lanes

The studio runs as one **director** session and a few standing **lanes**. A lane is a long-lived Claude session with one shape of
work: it takes that shape's tickets in order, one at a time, and keeps what it learned about its part of the code from one ticket
to the next. The director cuts tickets, verifies, merges, and holds the slot. Alex plays, decides, and can talk to any lane directly.

Session names are the addresses: **`ascendant director`**, **`ascendant lane UI`**, **`ascendant lane Art`**, **`ascendant lane AI`**.

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
The War Table (`design/UX_WAR_TABLE.md`) and the screens: UX-5, UX-8, UX-9, then UI fixes from playtests.
- Owns `ui/`, `world3d/board_overlay.gd`, `tools/shots/`. A ticket that touches `ui/map_screen.gd` or `ui/game_screen.gd` says so
  in its PR; the director merges those one at a time.
- Every ticket: before and after shots at 1600x900, 1600x900 at 125% and 1280x720 (`tools/shots/play_shots.gd --defaults --fresh`),
  looked at by the lane before it says READY. Every new mechanic gets its tooltip, preview or codex line in the same PR.

### Art: `ascendant lane Art`
The art pipeline: Review Table batches (`review/<batch>/`, `tools/review/README.md`), `assets/`, the Ludo and Bake3D tools, the rig lab.
- Never accepts or rejects for Alex; he does that in the Review Table.
- **Base first** (Alex 10-8): a few style samples go to Alex before a full batch, and an approved base before anything derived from it.
- Each batch logs its credit spend. The 2D art Alex still wants: concept art (also as model3d inputs), portraits, lore and codex art.
- Queue: UX-ART (the 32 notice medallions, keys in #218's PR body; `NoticeArt` picks up `assets/ui/notices/<key>.png` with no code
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
