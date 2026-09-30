# ASCENDANT: milestones

Every milestone ends in something Alex can play. Alex approves each milestone's scope before tickets are cut, and plays and approves it at the end. Scope follows `design/GAME_BRIEF.md`.

---

## milestone 1: playable skeleton
Status: **Scope APPROVED by Alex, 2026-09-30. In progress.**

### goal
Two players on one computer take simultaneous turns on a small province map, move and recruit armies, and fight battles that resolve together. Every battle and turn outcome is explained in plain language. There's no magic, no rulers or mandates, and no animation yet. This milestone proves the turn engine and the readability promise.

### what's in
- **Map:** one hand-authored map with about 14 provinces and three terrain types (plains, forest, hills). Each province has income and neighbors. It's drawn in 2D, clickable, and every number on it has a hover tooltip.
- **Two factions:** placeholder factions with a clear contrast, for example a disciplined human kingdom and a wild beast tribe. Each has 3 unit types and 1 commander type, with simple stats (hp, attack, defense, morale, cost) and one distinct trait each.
- **Orders:** move an army to a neighboring province, and recruit units in your capital with gold. Every order shows a forecast before you commit, such as arrival, cost, and gold left.
- **Simultaneous turns (hotseat):** player 1 gives orders, a handoff screen hides them, player 2 gives orders, then the turn resolves.
- **Turn resolution:** pure, deterministic rules code running from a seed in a fixed order: movement, then battles, then capture, then income. Replaying the same seed and orders always gives the same result.
- **Autobattle (rules only):** two armies fight in rounds by rules code. There are no visuals yet. The result is a **readable battle report** that says who fought, what happened in each round, and a plain "why you won or lost" summary.
- **Turn report:** a panel at the start of each turn listing every change (moves, battles, captures, income) with cause and effect, linked to provinces.
- **Win condition:** capture the enemy capital.
- **A minimal in-game codex** covering the terms used above.
- **A small asset batch:** terrain tiles, two faction banners, and static unit portraits, made to the style bible. This is also the studio's first full asset pipeline run.

### what's out (later milestones)
Rulers and mandates, paths of ascension, magic, battle animation and effects, AI opponents, fog of war, save/load, sound, and more than two factions.

### what to play and what to feel for (at the end)
Play a full hotseat game to a capital capture, about 10 to 15 turns. Feel for three things. You should always know what an order will do before you commit it. After every battle, you should be able to say why it went that way from the report alone. And resolving orders simultaneously should create real guessing and counterplay, not confusion.

### tickets (github issues #1 to #10)
1. #1 `code` Godot project scaffold: project, `tests/runner.gd`, `tools/compile_check.gd`, headless boot.
2. #2 `code` Core rules model: provinces, factions, units, armies, game state, seeded RNG. Pure code with no scene dependencies. (needs 1)
3. #3 `code` `hard` Order collection and deterministic turn resolver: movement, collisions, capture, income, plus a replay/determinism test. (needs 2)
4. #4 `code` `hard` Autobattle rules and battle report generation, with a plain-language "why" summary. (needs 2)
5. #5 `code` Map screen: render provinces, selection, hover tooltips with number breakdowns. (needs 2)
6. #6 `code` Orders UI: move and recruit, with forecasts. (needs 3, 5)
7. #7 `code` Turn flow: hotseat handoff, end turn, turn report panel, battle report viewer. (needs 3, 4, 6)
8. #8 `code` New game screen, win condition, minimal codex. (needs 7)
9. #9 `design` Art lead: M1 manifest entries (terrain, banners, portraits) against the style bible.
10. #10 `asset` Asset builder: M1 asset batch from the manifest, within the Ludo budget. (needs 9)

Budget: 1,500 Ludo credits for the milestone. M1 art is small, so expect well under that.

---

## later milestones (outline, not approved)
- **M2: the ruler.** Rulers, ruler power, keep-vs-spend mandates, mid-game sacrifice, ruler death and succession, and a basic AI opponent.
- **M3: battles worth watching.** Animated sprite playback of autobattles, spell and impact effects, and playback controls.
- **M4: paths of ascension.** Research paths, a first lock-in fork, and one transformation per faction.
- **M5: magic.** Magic schools, rituals, battle spells, and fog of war.
