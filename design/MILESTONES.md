# ASCENDANT: milestones

Every milestone ends in something Alex can play. Alex approves each milestone's scope before tickets are cut, and plays and approves it at the end. Scope follows `design/GAME_BRIEF.md`.

---

## 3D restructure (proposed by the director, 2026-10-04)
Alex decided on 2026-10-04 that the game goes 3D with a 2D interface. Full direction: `design/3D_DIRECTION.md`. Its §11 has the restructure and its §14 the calls to review first. **This restructure is a proposal until Alex approves it.** The sections below stay as written; M3's is superseded in part.

- **Now:** M3-1 (#56, event log) and M3-2 (#57, captions and explanations) continue unchanged. They are renderer-agnostic. The 3D spike, the look A/B and the lore writers' room (6 factions) run alongside.
- **M3a.1 the world:** Forward+ and a quality ladder; the 3D world in a SubViewport under the 2D UI; terrain, borders, territory wash, roads and rivers from the M1 map; fortress kits; villages; the camera; orders on the 3D board; armies as blocks of ready poses. *Play:* an M2 game on the 3D board, with every order and tooltip working as on the 2D map.
- **M3a.2 the armies:** full pose families, formations, muster yards and war camps, the fortress close-up, and the turn's playback (march-out, border clashes, captures, recruits mustering). Independents, if approved. *Play:* watch each turn resolve on the land, and predict the next battle from what you saw muster.
- **M3b battles on the land:** M3's event log, timeline, controls, why panel and approachability drive a 3D stage on the province. #58 is re-scoped; #61, #62, #63 and #64 are rewritten for 3D. *Play:* M3's own goals.
- **Forts and sieges** (proposal): sieges, walls, and building and upgrading fortresses.
- **M4 in 3D:** M4's rules as built, with transformed model families and a 3D turntable in the lock-in preview.
- **M5 magic and fog:** magic, fog of war on the world's vision mask, and seasons if approved.
- **M6 six factions and bigger maps:** the lore room's factions 3-6, generated maps for 2-6 players, and battles with more than two sides.
- **Art:** about 200 Ludo credits per faction planned (about 300 with reserve). About 1,465 planned and 2,170 with reserve in all, about 540 of it in the M3 steps. This replaces M3's sprite plan and M4's phase-2 battle figures.

---

## milestone 1: playable skeleton
Status: **Scope APPROVED by Alex, 2026-09-30. Built; awaiting Alex's playtest.** Code tickets #1-#8 closed (2026-10-02), balanced by #41, plus Computer seats (#42). The art batch (#10, PR #14) is waiting for Alex. Open design calls are in #25.

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
Status: **PROPOSED by the director (Claude session, 2026-10-01). Not yet approved by Alex; built provisionally so there is something to play. Alex can change anything.** All code tickets are built and merged (#29-#36, plus #54 for Warband Muster); ruler portraits (#37) are waiting for Alex. To play it, tick **Rulers (M2 preview)** on the new game screen; it's off by default, so M1 plays unchanged. Bands that still miss and the provisional calls are in #25 and in §8.4 of `M2_RULER.md`.

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

**Superseded in part by `design/3D_DIRECTION.md` (2026-10-04), after Alex's call to go 3D.** Still valid: the event log, the pure helpers, the controls, the why panel, the entry points, approachability and the goals. Superseded: the 2D field and sprites, the fixed camera, the GL Compatibility / integrated-graphics performance target, and the sprite art batch. Battles become a 3D stage on the province (M3b in the restructure above). Ticket changes are in `3D_DIRECTION.md` §7.6: #56 and #57 unchanged; #58 re-scoped; #59 and #60 small additions; #61, #62, #63 and #64 rewritten.

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

## milestone 4: paths of ascension
Status: **PROPOSED by the director (Claude session, 2026-10-04). Built provisionally under Alex's 10-4 'build an MVP you'd want to play'. Alex can change anything.**

Full spec, with every number, rule and acceptance criterion: `design/M4_ASCENSION.md`. Its §15 lists the director's calls to review first.

### goal
Each faction researches down one path and, mid-game, swears an Oath at a fork that closes the other side for good. A few turns later its people transform: one of its units changes, a new unit joins the roster, the economy and the provinces follow new rules, and the army looks different. Before swearing, the player sees exactly what they gain and lose. This milestone proves pillar 2: commit and become, so that two games with the same faction feel different because of the fork taken.

### what's in
- **Research:**
  - research points from land: the capital yields 5 a turn and every other province 1
  - one research target at a time from one pool; switching is free and spare points carry over
  - a new research phase after income
  - an ETA in turns on every node
- **One path per faction, 8 nodes:**
  - 4 ordinary nodes (stats, economy, movement) in two tiers
  - one fork between two Oaths; each Oath needs any two ordinary nodes, locks the other side out, and brings an economy rule
  - each Oath leads to a transformation
- **Four transformations:**
  - Aurel Crown: the **Celestial Host** (Sunspears, winged Seraphs that dive at commanders, Tithe of Light, Hallowed Land heals your wounded) or **Living Iron** (Iron Knights, the Iron Colossus, Deep Mines, forts that repair to full)
  - Thornmane Clans: the **Thorn Wild** (Thornthrowers, Briarwardens rooted in forests, Bounty of the Wild, the map turning to forest) or the **Blood Pact** (Bloodtuskers, Bloodsworn who drink their wounds back, Blood Levy, Dread Lands)
  - each changes one unit, adds one, adds a province rule and a new look, opens one mandate for sacrifice and forswears one
- **A mandatory lock-in preview:** gains, what you lose access to, every unit stat before → after, and the units' portraits (placeholders until art).
- **A research panel** with a HUD chip, the path tree, ETAs and the rival's path read-only.
- **AI research:** each build preset has a research order, and the AI picks its side of the fork by a seeded roll.
- **Explanations for all of it:** tooltips with breakdowns, codex entries, forecasts, turn report lines ("Your people have become the Celestial Host: ..."), and battle "why" lines naming transformation effects.
- **An autoplay balance check** with target bands for both sides of each fork.
- **Eight portraits** (each side's new unit and changed unit), with battle figures after M3's base sheets.
- **Opt-in for now:** "Paths (M4 preview)" on the new game screen needs Rulers; off, M1 and M2 play exactly as before.

### what's out (later milestones)
Magic and magic research (M5), more than one path or fork per faction, research buildings, rulers and commanders transforming, undoing a transformation, a use for research after the path is complete, fog of war, more factions, AI difficulty levels, save/load, sound, and the open questions in #25.

### what to play and what to feel for (at the end)
Play two games against the AI with the same faction, swearing a different Oath each time. Feel for four things:
- The lock-in preview tells you what you will become clearly enough that you can predict your turn-9 army before you swear.
- Swearing the Oath feels like a real commitment, and the turns before it (rush or round out) are a real decision.
- After the transformation, your army plays differently, and the turn and battle reports say why.
- The second game with the same faction feels different from the first.

### tickets (github issues to be cut; M4-n are placeholders)
After M4-1, tickets 2, 3 and 4 run in parallel, each owning its files; 5 needs 2 and 3, and 6 closes the milestone. M4-7 can start now, and M4-8's second phase follows M3-9.
1. M4-1 `code` `hard` Research and path rules model: path data, faction fields, `AscensionRules`, `ResearchOrder`, the research phase, research forecasts and breakdowns, every stat, income and price effect, opt-in setup, serialization and replay. (needs M2)
2. M4-2 `code` `hard` Transformations on the map: roster changes, Blood Levy, Raiding Parties, Forest Stride, the Wild Spreads, Hallowed Land, the Forges, opened and forsworn mandates, turn report events. (needs 1)
3. M4-3 `code` `hard` Battles with paths: Wings, Iron Hide, Rooted, Lifedrinker, path morale, Dread Lands, Red Harvest, "why" factors. (needs 1)
4. M4-4 `code` Research panel and lock-in preview, people labels, victory screen, placeholders. (needs 1; best after 2)
5. M4-5 `code` AI research and transformations: preset research orders, the seeded fork pick, using the new units and rules. (needs 2, 3)
6. M4-6 `code` Autoplay balance check for paths against the bands in `design/M4_ASCENSION.md` §10. (needs 2, 3, 5)
7. M4-7 `design` Art lead: M4 manifest rows, the T-thornwild block and fork glyphs. (no code dependencies)
8. M4-8 `asset` Asset builder: 8 portraits, then 8 battle figures after M3-9. (needs 7)

Budget: 300 Ludo credits for the milestone (190 planned, 285 with the re-roll reserve; 18 of that for the portraits that ship with the milestone).

---

## milestone 5: magic and fog of war
Status: **PROPOSED by the director (Claude session, 2026-10-04). Built provisionally under Alex's 10-4 'build an MVP you'd want to play'. Alex can change anything.**

The full spec, with every number, rule and acceptance criterion, is `design/M5_MAGIC_FOG.md`. Read its §19 (director's calls) and §20 (questions only Alex can answer) first.

### goal
Each faction learns its own magic down two schools. It casts spells in battle that you can watch and understand. It casts rituals on the map that bless, curse, summon and scout.

As a separate switch, the world goes dark beyond your borders. You see your own land exactly, your neighbours roughly, and the rest only as you last saw it. A rival's muster has to be scouted, or found with Far Sight.

This milestone proves two things:
- magic can be deep without being opaque
- fog makes simultaneous turns a guessing game without letting a player, or the computer, cheat

### what's in
- **Two switches, both off by default:**
  - **Magic (M5 preview)** needs Paths.
  - **Fog of war (M5 preview)** works with any game.
  - With both off, M1, M2 and M4 games are byte-identical.
- **Fog is a lens, not a rule.** The resolver never reads it.
  - **What you see:**
    - in clear sight: where you own land or stand
    - glimpsed: one province beyond, or two from forts, commanders, rulers and scouts; the total is rounded and shared out by type ("about 20 fighters: about 15 Tuskers, about 5 Fangthrowers")
    - out of sight: everything else, drawn from what you last saw
  - **What stays public:** owners, terrain, forts, rosters and heralds (Oaths, transformations, deaths, successions).
  - **What is learned** when you fight, see or read it: mandates, kept power and spells.
  - **One input for everything:** every screen, forecast, the 3D board and the AI read one view state built by allow-list.
  - **The proof:** four indistinguishability tests show that changing anything hidden from a viewer changes nothing they see, and nothing the computer orders.
- **Four schools:**
  - the Aurel Crown has Sun and Law; the Thornmane Clans have the Wild and Blood
  - each school has a battle spell, a ritual, a mastery node and a greater working that its aligned Oath opens
  - a new Magic tab holds 115 research of arcana, and research turns into gold once nothing is left
- **Casters:**
  - Sunstone Adepts and Thornmane Shamans fight from the second rank
  - the Ever-Regent casts Sunlance from turn 1
  - the Great Thornmane and the Ninth Fang cast rituals
  - King Corvane casts nothing
  - kept power raises mastery and spell resistance
- **Battle spells cast themselves and never roll dice.** Casters spread over a spellbook you order before battle. Every cast is a `cast` event in the log, a "why" factor, a caption and a line in the why panel.
- **Eight rituals**, paid in gold:
  - they resolve before movement, wards first
  - a ritual turned aside costs half its price
  - curses and blessings move a fixed number of hp a turn
  - Far Sight scouts and reads a rival capital
  - two summoned creatures
- **Tithe of Blood:** a Clans mandate that lets a mage's own army pay in blood. It can't be held with Feast of Victory.
- **AI:** deterministic research and ritual plans. Under fog it gets only its own view.
- **3D:** a vision mask beside the owner wash, and spell effects that the quality ladder thins.
- **Explanations for all of it:** forecasts that say what they assume, "what you didn't see" after a surprise, a cast dialog, spellbook previews, codex entries and captions.
- **An autoplay balance check** with 14 bands.

### what's out (later milestones)
- Seasons (a question for Alex).
- A third school per faction, dispelling, magic items, magic sites or gems.
- Mage commanders.
- Fog for battles you didn't fight (M6), per-player saves and online play.
- AI difficulty levels, and the open questions in #25.

### what to play and what to feel for (at the end)
Play a magic game against the AI with each faction, then a hotseat game with fog. Feel for four things:
- **At the moment it matters,** you can say what every spell and ritual will do: the card, the cast dialog and the battle caption all agree.
- **The schools and the Oath matter:** the two games feel different because of the magic you chose.
- **Under fog,** you have to guess and scout, and the forecast tells you honestly what it assumed. When you are surprised, the report says why.
- **In hotseat,** nothing on your screen tells you what the fog says you shouldn't know.

### tickets (github issues to be cut; M5-n are placeholders)
M5-0 goes first: a scaffold of the shared state fields and the fixture, about a day. Then the fog lane (1, then 2, 3 and 4) and the magic lane (5, then 6 and 7, then 8, 9 and 10) run in parallel. M5-11 closes the milestone. M5-12 can start now.

0. M5-0 `code` Scaffold: every new state field with gated saving, the M4-aware replay fixture, stubs. (needs M4)
1. M5-1 `code` `hard` Fog rules model: sight, estimates, memory, intel, the view state, per-viewer reports, the indistinguishability tests. (needs 0)
2. M5-2 `code` Fog on screen: every UI through the view, the per-viewer report, the Vision mode, forecast texts, the hotseat handoff. (needs 1)
3. M5-3 `code` Fog on the 3D board: the vision mask, stand-ins and ghosts, per-viewer playback. (needs 1)
4. M5-4 `code` AI under fog: the AI handed only its view, scouting, the proof tests. (needs 1)
5. M5-5 `code` `hard` Magic rules model: data, the arcana, mages, mastery, cast and spellbook orders, the running budget, Tithe of Blood. (needs 0)
6. M5-6 `code` `hard` Rituals on the map: the rituals and enchantments phases and every ritual. (needs 5)
7. M5-7 `code` `hard` Battle spells: the cast step, the five spells, the log, captions and the why panel. (needs 5)
8. M5-8 `code` Magic on screen: the Magic tab, the spellbook, the cast dialog, badges. (needs 5, 6)
9. M5-9 `code` Magic in 3D: ritual beats, decals, summons, battle spell effects on the quality ladder. (needs 3, 6, 7)
10. M5-10 `code` AI with magic: research, mages, the ritual rules. (needs 6, 7; 4 for Far Sight)
11. M5-11 `code` Autoplay balance check for magic and fog against the bands in `design/M5_MAGIC_FOG.md` §13. (needs 4, 6, 7, 10)
12. M5-12 `design` Art lead: M5 manifest rows and glyphs. (no code dependencies)
13. M5-13 `asset` Asset builder: 4 figures, 4 portraits, 14 icons, 5 VFX sheets. (needs 12, and the lore room's looks)

Budget: 180 Ludo credits for the milestone (118 planned, 177 with the re-roll reserve). The cheaper option is figures and portraits only (104).
