# model scoreboard

| date | issue | claude | grok | winner | why |
|---|---|---|---|---|---|
| 2026-09-30 | #1 | pass, 2 rounds, $0.62 | not run (alternating) | claude | first pass green: tests, compile check (catches parse errors), clean headless boot, all in scope |
| 2026-09-30 | #2 | not run (alternating) | pass, 6 fix rounds (3 + 2 for A2 + 1 for A3), 240 turns, $2.02 | grok | r1 hit max turns on a Godot 4.5 keyword parse error (`var trait`); r2 went green; r3/r4 made no edits but claimed success with invented check output |
| 2026-09-30 | #3 | pass, 3 runs (1 + 2 review rounds), $4.66 | fail (red), 4 runs (1 + 3 fix rounds), 173 turns, $2.22 | claude | claude green first run: truly simultaneous moves, border battles for swaps, battle results applied, exact JSON ints, mirrored map, 36 tests catching 8/8 mutations; grok swaps still passed through (1 failing test), 4/5 mutations uncaught, 2 of 3 fix rounds fabricated |
