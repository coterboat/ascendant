# Game Dev Pipeline — Human PM + Thin Bots + Build Agents

You are the studio: vision, fun, merge, ship. Agents do volume. Grok Bots only hold the queue and touch tools that need a logged-in computer. Code and asset *thinking* runs on Grok Build / the SuperGrok weekly pool (the bar that was at 4%), not the Bot week.

## Wallets (do not mix)

| Wallet | Spend on | Do not spend on |
|---|---|---|
| **You** | Fun, scope, kill features, final merge, live play | Ticket writing, file moves, first-pass code |
| **Grok Bot week** | Director orchestration, long unattended computer-use, GitHub/browser that must stay signed in | Code loops, art taste essays, critic vs tester debates |
| **SuperGrok week (Chat / Build / Imagine)** | `grok -p` implementation, reviews, asset generation, reports | Fan-out of 6 Bots all reasoning |
| **xAI API key** | CI overflow after the week is dead, headless jobs you accept as cash | Default path for the pipeline |

Auth rule: Build jobs use `grok login` (subscription). Never default `XAI_API_KEY` on the Bot VM or you silently leave the $30 pool.

## People and agents

### Human (you)
- Set the north star for the current slice (one verb: “turn resolution feels fair”).
- Play the build that agents stamped. Only you decide fun / off.
- Approve or reject merge. Director may *recommend*; it does not ship taste.
- Once a week: prune the backlog so agents cannot invent scope.

### Standing Bots (2, maybe 3)

**Director** (only coordinator)
- Owns the board: now / next / blocked.
- Turns your notes + last play report into *jobs* with inputs, command, done-when.
- Never implements, never paints, never plays the game for fun.
- Merge policy: hold human-gated PRs; auto-merge only chore/docs if you explicitly allow it.

**Clerk** (optional; delete if `gh` + hooks cover it)
- Labels, status checks, “reports landed,” changelog stubs.
- No opinions. If it starts reviewing code, kill the role.

**Runner** (optional, only if a generator UI or store dashboard needs a real browser for hours)
- Executes Director jobs that cannot be a CLI.
- One at a time. No personality.

Park: art lead, asset builder, builder-as-Bot, play critic, playtester-as-Bot, eggbot. Those become jobs and files.

### Headless agents (Build)

Run in the repo, billed to SuperGrok Usage:

| Job id | Command shape | Done when |
|---|---|---|
| `build` | `grok -p "…" --cwd repo --max-turns 20` | PR open, CI noted in `/reports/build-<sha>.md` |
| `assets` | generate from manifest + Imagine/ludo | `/reports/assets-<sha>.md` + files on convention |
| `review` | read diff, checklist only | `/reports/review-<pr>.md` approve / request-changes |
| `play-script` | headless or scripted session vs build | `/reports/play-<sha>.md` (mechanics, not “is it fun”) |
| `fix` | tight loop from review or CI | new commit or closed with reason |

`--max-turns` is mandatory. Parallel jobs are opt-in and rare.

## Source of truth (repo, not chat)

```
/design/
  north-star.md          # what this game is; you write this
  current-slice.md       # this week’s one verb; you + Director
  art-bible.md           # palette, size, naming, silhouette rules
  assets.toml            # id → path → status (missing|wip|final)
/reports/
  play-<sha>.md          # scripted + your human addendum
  build-<sha>.md
  assets-<sha>.md
  review-<pr>.md
/pipeline/
  jobs.schema.md         # contract below
  director-rules.md
```

Chat is disposable. If it is not a file, it did not happen.

### Job contract (Director emits only this)

```text
JOB: <build|assets|review|play-script|fix>
SLICE: <current-slice title>
INPUT: <paths>
CMD: <exact command or Runner step>
MAX_TURNS: <n>
DONE WHEN: <file exists AND predicate>
BLOCKED IF: <CI red | missing manifest id | you said hold>
```

No job without DONE WHEN. No Bot-to-Bot argument.

## Flow (one slice)

```
you set current-slice.md
        │
        v
   Director diffs repo + last /reports/play-*
        │
        ├── assets job  → Imagine/ludo + files + assets.toml
        ├── build job   → grok -p implements → PR
        └── review job  → checklist on the PR
        │
        v
   play-script job writes mechanical report
        │
        v
   YOU play the build
        │
        ├── fun / ship   → you (or Director on your word) merge
        └── off          → you write 5 bullets into play-<sha>.md
                              Director opens the next fix job
```

Playtester Bot and play critic Bot are replaced by: scripted smoke + your hands. The script answers “did the turn resolve, did the map clip, did HP go negative.” You answer “was it fun.”

## Art without an art Bot

Need-list is a diff:

```
assets.toml ids required by current-slice
minus
files that exist and status=final
= job input
```

Quality is gates in `art-bible.md`, not a lead Bot:

- correct pixel size / atlas slot
- name matches id
- silhouette reads at target size
- palette within bible
- no duplicate of an existing id

Generate 3–4, keep 1 that passes gates, else fail the job and list ids. Director does not “have taste.” It runs the gate.

If generation needs ludo/Imagine in a browser for a long batch, that is the only reason to keep Runner. Still one job, one report.

## GitHub

- One PR per job. No omnibus “studio dump.”
- Director may open/hold. You merge anything that changes feel.
- Clerk (or Actions) posts report links on the PR.
- CI is a gate for `DONE WHEN`, not a Bot personality.

## Cadence

**Daily (15–30 min, you)**  
Play the latest stamped build. Write bullets. Tell Director “hold #N” or “slice still X.”

**Daily (agents)**  
Director: at most one build job and one assets job in flight.  
Build pool: watch grok.com Usage. At 80%, stop starting jobs.

**Weekly**  
- Bot week and SuperGrok week reset on different clocks — plan from the two screens, not vibes.  
- Kill unused Bot names.  
- If SuperGrok bar is still tiny and Bot is maxed, the graph leaked again.  
- If SuperGrok bar dies from Build, consider Plus ($100), not Heavy, unless you want multi-agent Heavy mode.

## What you deleted from the old sidebar

| Old Bot | New home |
|---|---|
| director | stays, thinner |
| builder | `build` / `fix` Build jobs |
| art lead + asset builder | `assets.toml` + `assets` job |
| playtester + play critic | `play-script` + you |
| repo clerk | Actions/`gh`, or tiny Clerk Bot |
| dr eggbot | offline; do not leave in the weekly loop |

## First rebuild steps

1. Freeze all Bots except Director.
2. Add the folders above. Move today’s “PR #14 is final” chatter into reports.
3. Put `grok login` on the machine that runs jobs. Ban API keys there.
4. Implement one slice end-to-end: Director job → Build PR → you play → one fix job.
5. Only add Clerk or Runner if a step still requires a babysat browser.

Done means: you play, you steer, the week’s code/art volume hits the 4% bar on purpose, and the Bot bar stays a coordinator tax.
