# ASCENDANT: milestones

Every milestone ends in something Alex can play. Alex approves each milestone's scope before tickets are cut, and plays and approves it at the end. Scope follows `design/GAME_BRIEF.md`.

---

## milestone 1: playable skeleton
Status: **Scope APPROVED by Alex, 2026-09-30. Built; awaiting Alex's playtest.**

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

## milestone 2: the ruler
Status: **PROPOSED by the director (Claude session, 2026-10-01). Not yet approved by Alex; built provisionally so there is something to play. Alex can change anything.**

Full spec, with every number, rule and acceptance criterion: `design/M2_RULER.md`. Its §12 lists the director's calls to review first.

### goal
Before the game, each player picks a ruler and splits 10 ruler power between keeping it (a stronger ruler on the battlefield) and spending it on mandates (faction-wide traits). The ruler fights, can die, and is succeeded by its own rule. Mid-game, the ruler can sacrifice more power for a new mandate. A basic AI can take either seat, so one person can play a full game. This milestone proves pillar 1: power is a budget you spend on your people, and both keeping and spending win games.

### what's in
- **Four rulers, two per faction:**
  - Aurel Crown: King Corvane (mortal line) and the Ever-Regent (undying archmage).
  - Thornmane Clans: the Great Thornmane (beast-god avatar) and the Ninth Fang (chieftain bloodline).
  - Each has stats that scale with kept power, a front or second battle rank, one province ability, and a succession rule.
- **Ruler power:** a pool of 10. Kept power sets hp, attack, defense and the ability's rank.
- **Mandates:** 10 in all, 6 shared and 2 exclusive per faction, costing 2-4 power. The brief's Royal Armories, Iron Discipline, King's Roads and Sworn Vassals are among them, all expressed as stats, income, movement, recruitment, battle constants and morale.
- **Pre-game build screen:** keep vs. spend, with live previews of the ruler and of every faction-wide change, plus 3 presets per faction. Hotseat builds stay hidden until the game starts.
- **Mid-game sacrifice:** one per turn, at the mandate's price +1, with a before → after preview and a confirm.
- **Ruler death and succession:**
  - a mortal heir in 2 turns at half power
  - the undying in 4 turns at full power
  - the god in 1 turn at −3 power, for good
  - mandates stay
  - capturing the capital still decides the game
- **A basic AI opponent:** human or AI per seat. The AI plays one of 3 presets per faction and orders through the separately built `AIPlayer`.
- **Explanations for all of it:** tooltips with breakdowns, codex entries, forecasts, "why" lines in the battle report that name rulers and mandates, and turn report lines for sacrifice and succession.
- **An autoplay balance check** for builds, with target bands.
- **Four ruler portraits.**

### what's out (later milestones)
Magic (including the Regent's real spells and Tithe of Blood), paths of ascension and transformations, fog of war, more factions or rulers, battle animation, retreats and sieges, AI difficulty levels, save/load, sound, and the open M1 questions in #25.

### what to play and what to feel for (at the end)
Play two games of about 10 to 15 turns, against the AI or hotseat: one with a keep-everything build and one with a spend-everything build. Feel for four things:
- The build screen makes the trade-off clear, and you can predict what each choice will do before you lock it in.
- Your ruler is a real piece: risking a strong ruler or hiding a weak one is a decision you keep making.
- A ruler's death is dramatic but readable: the turn report says what happens next and when.
- The sacrifice is a lever you actually consider when things turn.

### tickets (github issues to be cut; M2-n are placeholders)
After M2-1, tickets 2 to 5 can run in parallel. M2-9 can start now.
1. M2-1 `code` `hard` Ruler and mandate rules model: data, state, stats and breakdowns, builds, serialization and replay, codex. (needs M1)
2. M2-2 `code` `hard` Battles with rulers and mandates: rulers in the ranks, battle mandates, Dread, "why" lines naming rulers and mandates. (needs 1)
3. M2-3 `code` `hard` Ruler death and succession: death bookkeeping, the rulers phase, successors, turn report, determinism tests. (needs 1)
4. M2-4 `code` Mandates and abilities on the map: King's Roads, Sworn Vassals, Heavy Tithes, Muster Grounds, Royal Court, Warband Muster, with forecasts. (needs 1)
5. M2-5 `code` Pre-game build screen with live previews, presets and hotseat handoff. (needs 1)
6. M2-6 `code` Mid-game sacrifice with preview, and the ruler panel. (needs 1, 3)
7. M2-7 `code` AI seat: human/AI seats, AI build presets, AI turn flow on the `AIPlayer` brain. (needs 4, 6, AIPlayer)
8. M2-8 `code` Autoplay balance check for builds against the bands in `design/M2_RULER.md` §8. (needs 2, 3, 4, 6, 7)
9. M2-9 `design` `asset` Four ruler portraits: art lead manifest rows, asset builder batch. (no code dependencies)

Budget: 50 Ludo credits for the milestone (4 portraits plus re-rolls).

---

## milestone 3: battles worth watching
Status: **PROPOSED by the director (Claude session, 2026-10-02). Not yet approved by Alex; nothing will be built until Alex has played M1/M2 and approves.**

Full spec, with every number, schema and acceptance criterion: `design/M3_BATTLES.md`. Its §12 lists the director's calls to review first.

### goal
Any battle from the turn report can be watched as an animated playback of exactly what the rules decided. While it plays, you can always tell who is winning and why. The battle rules don't change. This milestone proves pillar 3: battles are worth watching, and watching makes the report's "why" visible.

### what's in
- **A battle event log:**
  - the resolver records every attack (attacker, target, rolls against chances, damage and its parts), wound, death, morale check, rout, and every trait, mandate and ruler effect, round by round
  - it is deterministic and verified against the seed
  - it is kept with the last turn's report and regenerated from the game record when needed
- **Playback that never changes the outcome:** a pure function of the log, tested at the rules, UI and code level.
- **A battle screen:**
  - ranks as the rules have them (front, second, back), with the defender on the right
  - a terrain backdrop and the fort
  - strength bars with a break notch, a "why" caption after every round, and a result card
  - battles of up to 280 fighters (the largest AI battles measured in M2 games), every fighter its own figure
- **Placeholders first:** portrait cards in player colour plus emblem. Sprite animation (idle, move, attack, hit, death), projectiles for Volley, Skirmish and the Ever-Regent, impacts, dust, rule-bound screen shake and aura markers swap in as the art lands.
- **Controls:**
  - 1×, 2× and 4× speed, pause and skip to the end
  - jumps to the first to fall, the charge, a ruler's fall, the turning point and the rout
  - a round scrubber
  - hover any fighter for its target, hit chance and damage breakdown, from the same numbers the rules used
- **Entry points:** Watch on every battle row and in the battle report viewer, and "Watch your battles (N)" at the top of the turn report. Auto-watch at turn start is a setting, off by default. The AI's battles are watchable.
- **Explanations for all of it:**
  - a legend for every visual
  - a "why did that happen" panel synced with the playback
  - new codex entries
  - colour plus shape, a flash limiter and a reduced-motion setting
- **Performance budgets** for integrated graphics in the GL Compatibility renderer.
- **An art batch:** 12 animated figures (8 units and 4 rulers), 7 effects, 3 horizon bands and a fort.

### what's out (later milestones)
Spells and magic effects (M5), direct control and pre-battle formation orders, 3D and camera control, replay sharing, watching earlier turns' battles in the game, sound, battles with more than two sides, new rules or balance changes, and save/load.

### what to play and what to feel for (at the end)
Play a game against the AI with rulers, and watch every battle for the first few turns, then only the ones you care about. Feel for four things:
- From the bars alone, you can tell who is winning at any moment.
- After a battle, you can say why it went that way from what you watched, and the report agrees.
- Hovering a surprising hit explains it.
- You choose to watch the next battle because you want to, not because you have to.

### tickets (github issues to be cut; M3-n are placeholders)
After M3-1, tickets 2 and 3 run in parallel; after 3, tickets 5 and 6 run in parallel, and 4 joins once 2 is in. M3-8 can start as soon as the scope is approved.
1. M3-1 `code` `hard` Battle event log: recording in the resolver, `numbers.log`, `BattleLog` (validate, verify_draws, regenerate), `BattleTimeline`, the dump tool and fixtures, outcome-unchanged and determinism tests. (needs M2)
2. M3-2 `code` Key moments, round captions and hover explanations, and the new codex entries. (needs 1)
3. M3-3 `code` `hard` Battle screen with placeholder visuals: layout, backdrop, beats at 1×/2×/4×, strength bars, result card, "playback never changes the outcome" tests. (needs 1)
4. M3-4 `code` Controls, scrubber, key-moment jumps, hover, the why panel and the legend. (needs 2, 3)
5. M3-5 `code` Entry points: Watch buttons, "Watch your battles", auto-watch and the settings file. (needs 3)
6. M3-6 `code` Sprite animation, projectiles, impacts, auras, screen shake, the flash limiter and reduced motion, with per-figure fallback. (needs 3; art from 9)
7. M3-7 `code` Big battles and performance: massed layout, pools, preload, the `--perf` report against the budgets. (needs 4, 5, 6)
8. M3-8 `design` Art lead: M3 manifest rows and the bible's backdrop and prop classes. (no code dependencies)
9. M3-9 `asset` Asset builder: M3 batch from the manifest, within the Ludo budget. (needs 8)

Budget: 500 Ludo credits for the milestone (321 planned, 482 with the re-roll reserve).

---

## later milestones (outline, not approved)
- **M4: paths of ascension.** Research paths, a first lock-in fork, and one transformation per faction.
- **M5: magic.** Magic schools, rituals, battle spells, and fog of war.
