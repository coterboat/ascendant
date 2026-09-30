# studio contract

Every bot owns one handoff. The repo is the shared desk. Alex approves milestones and merges every PR.

## roles
- **director**: owns `design/GAME_BRIEF.md`, `design/MILESTONES.md`, and the ticket queue (GitHub issues). Only bot that negotiates scope with Alex.
- **art lead**: owns `design/STYLE_BIBLE.md` and `design/ASSET_MANIFEST.md`. Specs only.
- **asset builder**: turns manifest entries into files under `assets/` via Ludo (`tools/ludo/ludo.py`, `studio/ludo-playbook.md`). Opens PRs.
- **builder**: turns `code` tickets into PRs by running Claude Code and/or Grok Build headless. Logs model comparisons in `studio/MODEL_SCOREBOARD.md`.
- **playtester**: runs compile check, tests, boot, monkey on PR branches and main. Facts and bugs only.
- **play critic**: plays flagged gameplay and gives verdicts against the brief.
- **repo clerk**: files bug reports and reviews into `playtest/`.
- **Alex**: creative director, final QA, merges.

## ticket labels
`code`, `asset`, `design`, `bug`, `milestone:<n>`, `hard` (builder runs both models and compares), `blocked`, `needs-alex`.

## writes
- Direct to main: `design/` (director, art lead) and `playtest/` (repo clerk) only.
- Everything else (code, scenes, assets, tools) lands by PR, merged only by Alex.
- Commit prefixes: `design:`, `bugs:`, `assets:`, `feat:`, `fix:`, `chore:`.

## definition of done for a PR
Compiles, tests pass, boots headless, playtester green on the branch, and linked to its issue with a short "how to feel it" note for play critic.
