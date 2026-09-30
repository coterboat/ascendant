# rules for coding models in this repo

- Godot 4.5, GDScript, GL Compatibility renderer. Godot binary on the build box: `/home/box/playtester/godot/godot`.
- Read `design/GAME_BRIEF.md` and the linked issue before writing code. Build only what the issue asks.
- Keep game rules in pure, testable code (no scene dependencies) so turn resolution can be unit-tested and replayed deterministically. Simultaneous turns: all orders are collected, then resolved in one deterministic pass from a seed.
- Every feature ships with tests under `tests/` run by `tests/runner.gd`, and `tools/compile_check.gd` must pass.
- Approachability is a requirement: every new mechanic needs in-game explanation (tooltip, preview, or forecast) in the same PR.
- Never print or commit secrets. Never edit `design/`, `playtest/`, or `studio/` unless the issue says to.
- In the PR description, add a line starting `playtest:` describing what to poke at.
