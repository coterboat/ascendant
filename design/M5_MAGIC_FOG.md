# ASCENDANT: M5 design spec, "magic and fog of war"

Status: **PROPOSED by the director (Claude session, 2026-10-04). Built provisionally under Alex's 10-4 'build an MVP you'd want to play'. Alex can change anything.**

Built on:
- `design/GAME_BRIEF.md`: pillars 1, 3, 4 and 5; core system 2's "magic schools" path; the core loop's "cast rituals" step and "rough battle odds against what you can see"; the Tithe of Blood mandate; the approachability rules.
- `design/MILESTONES.md`.
- `design/M2_RULER.md`: the rulers, the Ever-Regent's deferred spells, call 9.
- `design/M3_BATTLES.md`: the event log (§2), captions (§4.8), the why panel (§7.3).
- `design/M4_ASCENSION.md`: the spec format, research (§2), the bands (§10), the deferrals (§13).
- `design/3D_DIRECTION.md`: the quality ladder (§3.4), fog (§6.3, §6.6, §10.2), seasons (§10.4).
- `design/STYLE_BIBLE.md`: §2.4 "unscouted (fog)", VFX (§4.2), 3D classes (§8.10).
- `studio/ledgers/asc-3d-factions.jsonl`: 3.0 credits a model, 1.5 a picture call of 3 candidates, 0.5 a pose edit.
- The engine on `main` at bea3b51: `rules/`, `data/`, `ai/`, `ui/`, `world3d/`, `tools/`.
- Issues #25 and #94.

Every number is in the engine's own terms: hp, attack, defense, morale, gold, provinces, rounds, ranks and research points. Two terms are new: **mastery** and **sight**.

**Alex: read §19 (director's calls) and §20 (questions only you can answer) first.** Everything else follows from them. Appendix A records the two critic rounds and what each changed.

## goal
Each faction learns its own magic down two schools. It casts spells in battle that you can watch and understand. It casts rituals on the map that bless, curse, summon and scout.

As a separate switch, the world goes dark beyond your borders. You see your own land exactly, your neighbours roughly, and the rest only as you last saw it. A rival's muster has to be scouted or found with Far Sight.

This milestone proves two things:
- Magic can be deep without being opaque: every spell is explained at the moment it matters.
- Fog makes simultaneous turns a guessing game without ever letting a player, or the computer, cheat.

## the short version
- **Two switches, both off by default.**
  - "Magic (M5 preview)" needs Paths, so ticking it also ticks Paths and Rulers.
  - "Fog of war (M5 preview)" works with any game.
  - With both off, every M1, M2 and M4 game is byte-identical to `main`.
- **Fog is a lens, not a rule.** The resolver never reads the fog flag. Fog decides only what each player is shown and what the computer is given to think with.
  - One small rule change comes with it: in a fog game each faction numbers its own armies.
- **What you see:**
  - **In clear sight**, exactly: provinces you own or stand in.
  - **Glimpsed**, rounded ("about 20 fighters: about 15 Tuskers, about 5 Fangthrowers, led by a Warchief"): one province beyond your land and armies, two beyond a fort, a commander, a ruler or a scout.
  - **Out of sight**: everything else, drawn as you **last saw** it.
  - Province owners, terrain and forts stay public.
- **Hidden under fog:** armies out of sight, gold, recruits, research, ordinary path nodes, mandates, kept power and spells. Each is learned when you fight it, see it or read it with Far Sight.
  - Oaths, transformations, deaths and successions are heralded to everyone.
- **One input for everything:** the **view state**. Every screen, forecast, the 3D board and the AI read a GameState built for one viewer **by allow-list**.
  - Tests prove that changing anything hidden from a viewer changes nothing they can see and nothing the computer orders.
- **Four schools:**
  - the Aurel Crown has **Sun** and **Law**; the Thornmane Clans have **the Wild** and **Blood**
  - each school has a battle spell (10 research), a ritual (15), a mastery node (20) and a greater working (25)
  - only the school's aligned Oath opens its greater working, so a faction can learn 7 of its 8 nodes
- **Casters:**
  - one mage unit per faction: **Sunstone Adepts** and **Thornmane Shamans**, fighting from the second rank
  - the **Ever-Regent**: Sunlance from turn 1 and every Crown battle spell
  - the Great Thornmane and the Ninth Fang cast their school's rituals
  - King Corvane casts nothing
  - kept power raises a ruler's **mastery**
- **The price is gold.** Rituals cost gold, so there is nothing new to manage.
  - **Tithe of Blood** (a Clans mandate, cost 3) lets a mage's own army pay in blood instead: 1 hp per gold, one soldier at a time.
  - It can't be held with Feast of Victory.
- **Battle spells cast themselves and never roll dice.** Each round, casters spread out over the side's **spellbook**, an order you set before battle in which you can also switch spells off. Every cast appears as:
  - a `cast` event in the battle log
  - a named part in the report's "why"
  - a caption: "the Thornmane Shamans' Briar Snare slowed 6 Knights: −2 attack this round, about 7 damage saved"
  - a line in the why panel
- **Rituals are orders:** a caster, a ritual, a target.
  - They resolve in a new **rituals** phase before movement, wards first.
  - A ritual a ward turns aside costs half its price.
  - Curses and blessings move a fixed number of hp a turn.
  - A new **enchantments** phase ends the turn.
- **Research has a use after the path:** 115 research of arcana, then research turns into gold.
- **AI:** deterministic research and ritual plans per preset, with no new random draws. Under fog it gets only its own view.
- **3D:** fog is a 16 × 1 vision texture beside the owner wash, one lookup in the ground shader, free on every rung. Spells are billboards, decals and code particles that the quality ladder thins.
- **Balance target:**
  - both schools of each faction get used
  - no spell is the top reason in more than a quarter of battles
  - M4's fork bands still hold
  - Tithe of Blood is worth no more than 5 points
  - Regent's Court wins at most 60%
  - fewer games than M4's 21% reach the turn cap
- **14 tickets,** M5-0 to M5-13: a small shared scaffold, then a fog lane and a magic lane in parallel (§18).
- **Art:** about 118 Ludo credits planned, 177 with reserve; budget 180 (§15).

---

## 1. what exists, and what M5 adds

### 1.1 the engine M5 builds on (unchanged unless this spec says so)
- **Phases (M4):** sacrifice, orders, movement, battles, capture, recruitment, income, research, rulers.
  - The sequence is hard-coded in `TurnResolver.resolve()`; `PATH_PHASES` documents it.
  - Only battles draw from the turn's `SeededRNG`.
- **Battles** (`AutoBattleResolver`):
  - Up to 8 rounds. Every standing fighter attacks once a round, and damage lands at the end of the round.
  - Hit chance = clamp(base + 4 × (attack − defense), 30, 90).
  - Damage = ceil(attack ÷ 2) − floor(defense ÷ 4), at least 1.
  - Ranks:
    - tier 0 is the front
    - tier 1 is the second rank (Volley, the Ever-Regent), shielded while at least as many front-rank fighters stand
    - tier 2 is the commanders
  - Fighters are ordered by army id (sorted as strings), then units in army order. Each attack's target is an index into that order.
  - Every modifier is a **named part**, and every "why" factor is measured from parts.
- **The breakpoint rule (#41):**
  - Attacks are odd. Defenses, counting Shield Wall, are 4k or 4k+1.
  - So a single +2 (terrain, a fort, Shield Wall) changes only the hit chance.
  - Permanent parts keep that alignment (M4 §3.2): attack ±2, defense +4.
- **The battle log** (M3-1) is version 1, with M4's additions under `"paths": true`. Captions, key moments and the why panel read only the log and the report.
- **Research** (M4):
  - one pool and one target
  - 5 a turn from the capital, 1 from every other province
  - ETA forecasts
  - a full path is 100 research, done around turn 11, after which the pool has nothing to buy (M4 call 16)
- **Rulers** (M2):
  - kept power 0-10 sets their stats and **ability rank** = 1 + kept ÷ 3, rounded down (1-4)
  - `RulerRules.has_living_ruler` needs the ruler's army on the map, and its callers (the ruler panel, healing) read that army's location
  - the Ever-Regent fights from the second rank, and "his spells count as attacks until M5"
- **Army ids** come from one global counter, `GameState.next_army_id` ("kingdom-7").
- **Hotseat** (#7, M3a.2):
  - An opaque cover goes up between human seats.
  - Each seat sees the last turn's playback and report behind its own cover.
  - The board keeps its last frame while covered.
- **The save** (`SaveGame`): the game record (start state, orders, seeds), a header, and the computer's dice and notes. Loading replays the record.
- **The AI** reads the whole `GameState` today:
  - `AISeat` calls `session.state()` in `_init` and `take_turn`, and `report_notes` reads `session.turn_report()`
  - the autoplay `Simulator` hands `session.state()` to its policies (`simulator.gd:183`)
  - under fog, this is the biggest change (3D_DIRECTION §10.2)

### 1.2 what M5 adds
- **Fog of war (§2):** sight, estimates, memory, intel, the view state, per-viewer reports and playback, hotseat rules, fog-safe forecasts, order checks and saves.
- **Magic (§3-§8):**
  - four schools, mages, mastery and the spellbook
  - the arcana research tree
  - five battle spells and eight rituals
  - Tithe of Blood and the Ever-Regent's spells
  - two summoned creatures
  - enchantments, and the rituals and enchantments phases
- **Around them:** the AI (§10), explanations for all of it (§11), the 3D vision mask and spell effects (§12), autoplay bands (§13) and an art batch (§15).

### 1.3 the two switches (off by default)
| switch | box on the new game screen | needs | without it |
|---|---|---|---|
| `GameState.magic` | **Magic (M5 preview)** | Paths: ticking it ticks Paths and Rulers; clearing Paths clears it | No magic key is saved. No rituals or enchantments phase runs. No `cast` event or magic report field appears. Nothing is sold for research. |
| `GameState.fog` | **Fog of war (M5 preview)** | nothing: it works in an M1, M2, M4 or magic game | No `fog` key is saved, every screen reads the true state, every report is unfiltered |

- **Setup:** `GameState.with_magic(seed, builds)` is `with_paths` plus `setup_magic()`. `setup_fog()` can follow any setup; it sets `fog` and calls `setup_army_counters()` (§2.1).
- **Saving:** every new key is saved only when it is set, as `paths` is.
- **Tooltips:**
  - Magic: "Research spells, recruit mages and cast rituals. Needs Paths and Rulers, so they're on too."
  - Fog of war: "You see exactly only where you own land or have an army; next to that, roughly; beyond, only what you saw last. In hotseat, each player sees only their own view."
- **Acceptance (M5-1, M5-5):** `tests/test_fog_off.gd` and `tests/test_magic_off.gd` replay `tests/fixtures/m5_base_records.json`.
  - The fixture holds M1, M2 and M4 records that M5-0 records on `main` (§18).
  - Each test compares turn-by-turn digests, as `tests/test_paths_off.gd` does.
  - Each also reruns the AI policy loop of `tools/replay_fixture.gd` and compares the AI's orders turn by turn.
  - A non-M5 AI change, such as #94, re-records the fixture in its own commit.

---

## 2. fog of war

### 2.1 the principle: fog is a lens, not a rule
- **The resolver never reads `GameState.fog`.** It reads one new setup choice that fog games turn on, plus magic rules:
  - **`army_counters`** (per-faction army numbers): `setup_army_counters()` gives each faction its own counter, starting at its highest existing army number + 1. From then on `new_army_id` numbers each faction's armies alone, so the numbers on your armies can't count your rival's.
    - It is saved whenever it is set, whatever `fog` says.
    - It is a small rule change. Army ids sort as strings, so fighter order, and with it which roll goes to which attack, differs from a game without counters. That is why only fog games turn it on.
    - **Director's note (2026-10-04):** issue #94 makes per-faction army numbering the rule in **every** game. Its reason is the turn report's army names ("the Crown's 13th" on turn 1), and it re-records the fixtures for that change. Once #94 is on `main`:
      - `army_counters` is the base game's counter and not a fog setup choice. M5-0/M5-1 reuse #94's counter and save key instead of adding `setup_army_counters()`.
      - The "only fog games" rule change goes away, and so does the "`army_counters` on" half of G11's no-fog control.
      - Wherever this spec says fog games number armies per faction, read it as "all games do".
  - **Far Sight** is a magic rule whenever magic is on (§6.2). It writes an enchantment that FogRules reads. Without fog, the UI and the AI simply never offer it.
  - **Acceptance (M5-1):** a fog record replayed with `fog` stripped and `army_counters` kept gives identical states.
- **Truth stays behind named doors.** In a fog game, every player-facing surface reads through the per-viewer accessors:
  - `GameSession.state_for(viewer)`, `turn_report_for(viewer)`, `view_before(viewer)`, `memory(viewer)` and `intel(viewer)`.
  - With fog off, `state_for` returns `state()` and `turn_report_for` returns `turn_report()`, so nothing changes.
- **Truth accessors** are `state()`, `turn_report()`, `battle_events()`, `builds()`, `record()`, `history()` and `victory()`.
  - A static scan forbids them in `ui/`, `world3d/`, `ai/` and the autoplay policies.
  - The exceptions are an allow-listed set of observer paths: the victory screen, save and load, and battle regeneration for a participant (§2.8).
- **The observer** is a named constant, `FogRules.OBSERVER` (`"@observer"`), never a default.
  - It sees the truth. AI-vs-AI watch mode, the autoplay tool's invariants and the victory screen use it.
  - (`""` already means "the faction itself" in `Forecast` and "public text" in the turn report.)
  - The victory screen lifts the fog: each rival's mandates, path, spells, spellbook and gold over the game (from replaying the record), and a list of every "what you didn't see" moment (§2.8).

### 2.2 what is public and what is private
| | under fog | why |
|---|---|---|
| province owners, terrain, forts, capitals | **public** | The map's colours always tell the truth, so the territory wash, Sworn Vassals, the save header and the 3D village and fort pieces can't leak. Dominions shows owners too. A capture reveals that an army was there, which is fair scouting. |
| each rival's ruler (who), its death, its successor and the successor's kept power | **public** (heralded) | A ruler is famous, and a coronation is public. The build screen's choice of ruler is known from turn 1. |
| Oaths and transformations | **public** (heralded) | M4 call 4 gave the rival "a turn report and a few turns to react". A transformation changes the board everyone sees. Everyone knows an Oath sets its transformation as the next research target. |
| global rituals (Blood Moon) | **public** | The moon turns red for everyone. |
| every faction's roster | **public** | The codex lists every faction's units. In a magic game the mage is on the roster from turn 1, but it can't be recruited until a spell is known (§3.2), so the roster never reveals research. |
| armies, recruits, gold, income modifiers | private | learned by sight (§2.3) |
| mandates, kept power between heralds, ordinary path nodes, spells, the spellbook | private | learned by intel (§2.6) |
| research pool and target | private | The pool is learned from a Far Sight reading (§6.2). The target is never learned, beyond the Oath rule above. |

### 2.3 sight
Each viewer has one **sight level** per province, computed from the state at the start of a turn (after the last resolution). Distances are steps along the map's neighbour links.

| level (id) | players read | when | rival armies there |
|---|---|---|---|
| `clear` | **in clear sight** | you own it, an army of yours stands in it, or your Far Sight is on it | exact fighters with their current hp (pooled per faction, §2.7) |
| `glimpse` | **glimpsed** | not clear, and within the sight range of one of your sources | estimates (§2.4) |
| `veiled` | **out of sight** | otherwise | your memory of it (§2.5), or "never seen" |

**Sight sources and ranges** (`data/fog.gd`, `FogData.SIGHT`):
| source | range |
|---|---|
| a province you own | 1 |
| an army of yours | 1 |
| an army of yours holding a **scout**, a commander or a ruler | 2 |
| a fort you own (capitals have forts) | 2 |

- **Scouts** are unit types with sight 2: Knights (mounted), Fangthrowers (skirmishers), Seraphs (winged) and Thornwolves (§6.2).
  - Transformations keep the id, so Iron Knights and Thornthrowers are scouts too.
  - New factions add rows.
- **Sight never upgrades a glimpse to clear sight.** Exact numbers of rival armies come only from fighting them (§2.5) or from Far Sight.
  - An enemy army can't stand in a province you own at the start of a turn (the capture rule), and walking into its province means a battle.
  - That is the point: forecasts have to guess, and Far Sight is worth gold.
- **At the start of a game** on the M1 map (the test derives the counts by breadth-first search from `MapData`):
  - The Crown owns Crownkeep, which is in clear sight.
  - Its fort and its starting army (Knights, Knight Captain) both reach 2, so Westwatch, Highcrag, Rivermarch, Stonegate, Thornvale and Greenglade are glimpsed.
  - The Clans' seven provinces are out of sight. The Clans see the mirror.
  - Each side sees its rival's border, not its heart.
- **Why a province is seen:** `FogRules.sources(state, viewer, pid)` names the reason ("Glimpsed from your army at Highcrag (range 1)"), for the tooltip and the Vision map mode (§11).

### 2.4 what a glimpse shows: estimates
For each rival faction with armies in a glimpsed province, its armies there are pooled into one **sighting**. The **total** is rounded, then shared out over the types, so many small groups can't hide fighters.

| part | shown as | forecasts assume |
|---|---|---|
| the total of units and summoned creatures | rounded: "about 20 fighters" | the shown total, and also the top of its range (§2.10) |
| each type present | the shown total shared out over the types in proportion to their true counts: "about 15 Tuskers, about 5 Fangthrowers" | as shown |
| commanders | their type and exact count ("led by a Warchief") | as shown |
| the ruler | its name, maximum hp, attack, defense and kept power ("a ruler is hard to hide") | as shown, at full hp |
| enchantments on those armies or that province | named (a blessing's glow, a ward's band) | as shown |
| wounds, exact counts, how many armies | **not shown** | full hp |

**The rounding rule.** It lives in one place, `FogRules.round_count(n)` → `{"shown", "low", "high", "text"}`:

| true total | shown |
|---|---|
| 1-2 | "1-2" (forecasts assume 2) |
| 3-49 | the nearest 5, and at least 5 |
| 50+ | the nearest 10 |

- **The arithmetic** is integer: step × floor((n + step ÷ 2) ÷ step).
- **`low` and `high` are computed, not tabled.** They are the smallest and largest true counts that show that number. "About 5" is 3-7, "about 15" is 13-17, "about 50" is 48-54, and "about 60" is 55-64.
- **Sharing out** uses largest remainders: each type gets floor(shown × its share), the leftover goes to the largest remainders, ties go in roster order and then summoned types in data order, and every type present gets at least 1.
  - So 3 of each of 5 types (15) shows as "about 15 fighters", about 3 of each. Five types of 7 (35) shows as "about 35".
  - The top of the range is shared out the same way.
- **Canonical order.** The sighting lists types in roster order, then summoned types in data order. Nothing about the true order of armies or units survives the pooling.
- **The hover shows the change:** "about 20 (18-22); last turn about 15 (13-17)". A band crossing doesn't read as five recruits.

### 2.5 memory: last seen
**Memory** is per viewer. For every province it holds the last sighting or clear view of rival armies there, and the turn it was taken. It updates after each resolved turn, in this order:
1. **Moves seen leaving.** A rival move out of a province you could see enters memory where you saw it head: "seen marching toward Ironspike". This is the first step of the march, even for a two-step road move (§2.8).
2. **What you see now.** Every province in clear sight or glimpsed replaces its memory with the current view, which is empty if no rival army is there.
3. **Battles you fought.** The enemy's survivors where the battle ended are kept exactly, beside the current view: "last fought turn 6: 6 Tuskers survived, 18 hp in all."
4. **Out of sight.** Provinces out of sight keep what they had.

- **A rival ruler is remembered once,** at its latest sighting. Its ghost is cleared when its death is heralded.
- **Remembered armies are in the view state** as stand-ins at their last place, with a view note `{"level": "memory", "turn": N}`.
  - The board draws them as grey ghosts that fade a step for every 2 turns of age, with the plate "≈10 · 3 turns ago".
  - Forecasts against them say "if it is still there".
- **Memory is derived, never saved.** It is a pure function of the game record and the viewer.
  - `GameSession` keeps it incrementally, and `from_record` rebuilds it during the replay that loading already runs.
  - Budget: ≤ 0.2 s for a 60-turn game on the build box.

### 2.6 intel: what you know about each rival
- **One rule:** you learn a rival's mandate, path node or spell when something you are shown names it:
  - a battle you fought (the report's sides list their mandates in play, their path parts and the spells they cast)
  - a turn report line shown to you (a vassal joining "by Sworn Vassals", a curse falling on your land)
  - an enchantment you can see
  - a Far Sight reading of that rival's capital (§6.2), which gives everything private except the research target, as of that turn
- **Kept power** is learned whenever you see or fight the ruler, at any sight level, and at its heralded death and succession. It is shown with the turn it was learned.
  - Until then the view assumes **10 minus the cost of the mandates you know**, which is the most it could be.
  - A known value is capped the same way, so a newly learned mandate never makes the view impossible.
- **Spells:** a mage you can see proves its faction knows at least one battle spell.
  - Until you learn which, forecasts assume the first **tier I** spell of that faction's default spellbook, and say so: "Their Shamans: assumed Briar Snare."
  - The Crown's assumed spell is Sunlance.
- **Intel is a set of ids per rival:** `{"mandates", "nodes", "spells", "kept_power", "kept_turn"}`.
  - It is derived from the viewer's own filtered reports, never saved, and always reproducible.
  - Learned facts stay learned.

### 2.7 the view state: one input for every screen, forecast and the AI
`FogRules.view_state(state, viewer, memory, intel)` returns a `GameState`. It is pure, and cached per turn and viewer.

**It is built by allow-list, not by scrubbing.** A fresh `GameState` with `is_view = true` gets only the fields listed here. Anything not copied can't leak, including fields future milestones add.
- **Provinces:** every public field (§2.2).
- **The viewer's faction and armies:** complete, with their true ids. The viewer orders its own armies by those ids, and per-faction counters make them count only its own armies.
- **Rival factions:**
  - public: id, name, capital, roster, ruler type, ruler status and generation, `successor_turn`, `successor_power`, `path_branch`
  - from intel:
    - `researched`: heralded nodes plus intel, sorted by turn
    - `mandates`
    - `kept_power`: known or assumed, capped (§2.6)
    - `spellbook`: the default until learned
  - zeroed: gold, research pool, target, sacrifices, enchantment counter, Bastion list
- **Rival armies:** pooled per (faction, province) into **stand-ins** of a fixed shape. Each has a **view id** that never reveals a true id or how many armies there are:
  - `seen-<faction>-<province>`: the units not blessed, plus the first commander
  - `seen-<faction>-<province>-b`: the blessed units, if any (a blessing's glow is visible)
  - `seen-<faction>-<province>-c2`, `-c3` …: one army for each further commander
  - `seen-<faction>-<province>-ruler`: the ruler alone, as M2 requires
  - Units carry their exact hp in clear sight, and full hp at the shown counts otherwise.
- **Enchantments:**
  - The viewer's own enchantments appear with their true ids.
  - A rival's appear only where the province, or for a blessing an army, is in clear sight or glimpsed, with **view ids**: `seen-<ritual>-<province>`, or `seen-<ritual>` for a global. A blessing's armies are listed by view id.
  - Global enchantments always appear.
- **Zeroed counters:** `next_army_id`, `army_counters`, `rng` and `seed_value`. The view holds nothing that could predict a battle roll, or count armies or rituals raised out of sight.

**A view is a valid GameState for every reader:**
- **Relaxed validation.** `validate` relaxes exactly these checks, for rivals only, when `is_view` is set. `tests/test_fog_view.gd` has a case for each:
  1. `AscensionRules.validate`: prerequisites and the turn order of `researched`.
  2. `RulerRules.validate_factions`: the kept-power arithmetic and the `sacrifice_only` check.
  3. `GameState._living_rulers_on_map`.
  4. Summoned units' `until` (stand-ins carry 0).
- **Liveness.** A new `RulerRules.ruler_alive(state, fid)` reads `ruler_status` alone. `has_living_ruler` is unchanged.
  - Screens that show a rival ruler use `ruler_alive` and handle "alive, location unknown". The ruler panel does today read its army's location.
- **Serialization.** `to_dict` and `from_dict` carry each army's view note and `is_view`, so a view deep-copies exactly.
  - The note is `Army.seen`: `{"level": "clear" | "glimpse" | "memory", "turn", "counts": {type: round_count}, "total": round_count, "blessed": n}`.
  - A true state never has either key.
- **Acceptance:** `view.deep_copy()` round-trips, and `Forecast.*`, `RulerRules.with_sacrifice`, `OrderBook.check_order`, `AIPlayer.plan_orders` and `AIPlayer._scratch_with` all run on views.

**Order checks run on the true state.** A legal order is never refused because of the view. They can't leak, because **an order's legality may depend only on public facts and the player's own state** (§2.10).

**The proof: four indistinguishability tests** (M5-1, `tests/test_fog_view.gd`), on 20 seeded fog games, for each viewer:
- **Snapshot,** at every third turn. `FogTestKit.perturb_hidden(state, viewer, seed)` returns a changed state plus an id-renaming map, with memory and intel held fixed. It changes:
  - out-of-sight rival armies: their existence, number, location, merges, splits, units and hp
  - glimpsed pools: how they divide into armies and blessed parts, and each type's true count within what keeps the same sighting
  - rival enchantments and summons out of sight
  - rival gold, research pool and target, unknown mandates, nodes and spells, the spellbook, and kept power while unseen
  - all true rival army ids

  `view_state` must be byte-identical afterwards, view notes included.
- **Report.** `report_for` (§2.8) is given the perturbed true before and after states, with the events renamed by the map. The filtered report must be byte-identical.
- **Two-turn.** Resolve the base turn. Compute the viewer's sight at the start of this turn and of the next. Then vary the rival's orders, using only:
  - recruits at a rival capital that is out of sight both times
  - moves by armies that have no other orders, between rival-owned provinces out of sight both times
  - research orders
  - sacrifices for mandates the viewer doesn't know
  - Sanctum Ward on such provinces
  - Call the Pack where the pack is out of sight both times

  Discard any variation whose public facts (owners, forts, terrain, heralds) differ. Assert that at least 5 variations ran per game. The viewer's next view, report, memory and intel must be identical.
- **Three-turn.** A ritual is hidden on turn 1, and a visible one follows on turn 2. Nothing on turn 3 may differ. This catches counters such as enchantment ids.
- M5-4 adds the AI's orders to the snapshot and two-turn tests, and M5-3 adds the board's model.

### 2.8 the turn report and battle reports, per viewer
`FogRules.report_for(events, viewer, before, after, memory, intel)` returns the viewer's events.
- It is pure, and takes the true states before and after the turn.
- It follows one **audience table**, `FogData.AUDIENCE`, which says for every event type who sees it whole, who sees a rebuilt version, and who sees nothing.

| who | what they get |
|---|---|
| the faction an event is about, for its own events (its recruits, income, research, sacrifices, healing, rejected orders, its rituals' payment) | the event whole |
| everyone, for public events: `captured`, `vassal_joined`, `vassal_contested`, `ruler_died`, `ruler_arrived`, `succession_waiting`, `oath_sworn`, `transformed`, `wild_spread`, `fort_raised`, `game_over`, and `ritual_cast` for a global ritual | a **rebuilt** event |
| a viewer who saw a rival move | one rebuilt event per (faction, from, first step), pooled and rounded: "An army of the Thornmane Clans (about 10 fighters: Tuskers, Fangthrowers) marched from Wildmoor to Thornvale." If the end is out of sight: "… marched out of Wildmoor toward Ironspike, out of your sight." A two-step road move names only its first step. |
| a viewer whose land a rival ritual targets | a separate event, `ritual_fell`: the ritual, the caster's faction, the effect and how to stop it, **never the caster's province** (§11.2's curse line) |
| a caster whose ritual lands on a rival's province | its own `ritual_cast`. What it did there (`curse_bit`, a reading) is rebuilt at the caster's sight level, so a curse never counts a garrison you can't see. |
| everyone else | nothing |

**Rebuilt events.** A rebuilt event is a new dictionary built from three things only:
- the allow-listed numbers, `FogData.SAFE_NUMBERS[type]` (listed in §14)
- view ids
- text made from `FogData.TEXT` templates, using those numbers alone

The resolver's own text and numbers never pass through, because they read private state. `sworn_text` has a research ETA; `transformed_text` reads mandates and full unit stats; `units_changed`, `hp_total` and `own_text` count or describe the rival's units.

**Battles.**
- A participant sees the whole battle: report, log, playback and "why". You fought them, so you saw them. With two factions, every battle has both.
- In the participant's copy, the battle event's `armies` and `numbers.destroyed` are rewritten to the view ids in `view_before`. True ids stay only inside `numbers.log`; with per-faction counters, they tell you only how many armies that rival has ever raised, and that is declared acceptable.
- For M6's third faction: a battle you are not in shows as a clash line, at the sighting's detail, if its site is in sight. It can't be watched.

**"What you didn't see."** This line goes on any battle where the true enemy differed from your start-of-turn view of it, in counts, mandates or spells. For example: "You had glimpsed about 10 Tuskers at Thornvale; 14 fought you (armies can join during a turn), with Iron Discipline, which you hadn't seen. Against what was really there, the odds were 31%."
- The UI computes the odds when the row is shown, from the battle's true starting sides, which a participant saw.
- The victory screen lists every such line.

**Per-viewer playback.**
- **One fold.** `FogRules.apply_view_events(model, events)` folds a minimal army model (view id → owner, location, counts).
- **Rebuilt moves** carry `view_from` and `view_to`.
- **Synthetic events.** After the real events, `report_for` appends `sighting_changed`, `sighting_lost` and `memory_added` events. They cover exactly what is left over between the folded `view_before` and `view_after`: hidden recruits, a band crossing, a province going out of sight.
- **The result:** for every viewer, `view_before` plus the filtered events equals `view_after`, exactly. This is M3a.2's "playback = state", per viewer.
- `world3d/playback.gd` reads its beats from the same events, and its test checks its board model against `apply_view_events`. That includes the beats: no surviving march plays as fallen.
- `GameSession` keeps `view_before(viewer)` for this.

### 2.9 hotseat
- **Each seat plays through its own view.** The board, every panel, the playback and the report are built from that seat's accessors. M3a.2 already plays each seat's playback behind its own cover.
- **The handoff rebuilds before it uncovers.** On Ready, the board, overlay and panels are rebuilt for the next seat while the cover is still up, and the SubViewport's kept frame is cleared.
  - Headless test: the rebuild runs, and the kept frame is marked cleared, before the cover hides.
  - Build-box check: the first frame captured after a handoff is the new seat's.
- **The cover adds a line under fog:** "Fog of war is on: each player sees only their own view. Continue only when nobody else can see the screen."
- **The computer's "what it was thinking" notes** name its hidden armies and plans. Under fog they stay hidden until the game is over. They are still in the save.
- **Sound** plays only for what the viewer can see; `GameAudio.report` reads `turn_report_for(viewer)`.
  - In a hotseat fog game, the turn playback's sound is off, apart from a neutral ambient bed, because the other player is in the room.
  - A player who times the other's playback learns roughly how much they saw. That is accepted.
- **Not stoppable, and said so:** a player who peeks at the other seat's screen, or opens the save file (§2.11). Hotseat fog is enforced by the screen, as in every hotseat game.

### 2.10 forecasts and order checks under fog
**Every forecast runs on the view state and says so briefly.** The detail is one hover away (approachability rule 4).
- **Glimpsed:** "Odds against what you can see: 58% (close), 41% if they are at the top of the range ⓘ".
- **Out of sight:** "You can't see Wildmoor (last seen empty 3 turns ago / never seen): any army there will be a surprise. No odds."
- **The ⓘ hover lists the assumptions:**
  - the sighting with its ranges
  - the mandates and spells you know ("Iron Discipline, seen at Thornvale on turn 4"; "their Shamans: assumed Briar Snare")
  - their assumed kept power ("10, the most it could be")
  - "They may have more you haven't seen, and they may summon creatures or raise a fort there this turn."

**Forecast equals result** (M2-M4's tests) now holds when three conditions are met:
- every province the order involves is in clear sight
- no unseen army enters it
- the view's stand-ins equal the truth pooled the same way: the same fighters, hp, mandates, spells and enchantments

The battle-odds test compares the forecast on the view with the forecast on the pooled truth. Pooling changes fighter order, so the odds against unpooled armies can differ by a sample or two even with full knowledge.

The rest of the time, the forecast is honest about its guess, and §2.8's "what you didn't see" explains the miss.

**The move forecast shows what you will see:** "Next turn this army will see Wildmoor and Fangridge (it has Knights: range 2)."

**Legality never reads hidden facts.** Every order's check reads only public facts (owners, terrain, forts, the map) and the player's own state.
- Whether a province is warded, or a rival caster stands there, is a rival's private fact, so neither is ever part of legality.
- Acceptance (M5-1, `tests/test_fog_orders.gd`): for every order the UI can offer in 20 fog games, `OrderBook.check_order` gives the same answer on the true state and on the viewer's view.

**Sworn Vassals** picks on the truth, so its forecast says "joins you at the end of the turn, unless an army you can't see stands there".

### 2.11 the save
- **The save holds the truth.** That is the record (the start state with `"fog": true` and `army_counters`, orders and seeds), the header, and the computer's dice and notes. There are no other new keys. Memory and intel are rebuilt by the replay that loading already runs (§2.5).
- **The header is fog-safe** because owners are public: "Turn 5: Aurel Crown holds 6 provinces, Thornmane Clans 5."
- **Server-free means honour-based.** The file contains everything. That is acceptable for hotseat and single player. Online play would need a file per player or a server, and the lens design keeps that door open.
- **Save-scumming against the computer** is possible, as it already is for battle rolls: save at turn start, end the turn, see where it went, load. It is the player's choice; an ironman option is a question for Alex (§20).

---

## 3. magic: schools, casters and the price

### 3.1 the schools
| school | faction | aligned Oath (opens the greater working) | flavour | battle spells | rituals |
|---|---|---|---|---|---|
| **Sun** | Aurel Crown | Oath of the Dawn (Celestial Host) | light that smites and heals | Sunlance; Sunburst (greater) | Dawn Blessing |
| **Law** | Aurel Crown | Oath of the Forge (Living Iron) | shields for armies on the march, wards against magic, stone | Shield of Law | Sanctum Ward; Bastion (greater) |
| **the Wild** | Thornmane Clans | Oath of the Grove (Thorn Wild) | thorn, beast and forest | Briar Snare | Call the Pack; Wake the Greenwrath (greater) |
| **Blood** | Thornmane Clans | Oath of Blood (Blood Pact) | the price paid in life | Bloodbolt | Bloodrot; Blood Moon (greater) |

- **The Crown heals, shields its field armies and fortifies; the Clans snare, summon and curse.** Each gets an answer to the other's tools:
  - Sanctum Ward ends Bloodrot, keeps Far Sight out and shuts out the Blood Moon.
  - Sunlance kills the biggest creature first.
  - Briar Snare blunts the Knights.
  - Bloodrot denies healing to a fortress the Clans can't storm.
- **Each school pairs with one side of its faction's fork,** so the Oath you swear also decides your greatest working (§8). This is the brief's "magic schools" as a path, folded into the one path M4 built rather than a second fork.
- **Hooks for new factions** are rows:
  - a school in `MagicData.SCHOOLS` (`{id, name, factions, aligned_branch, nodes}`)
  - a faction's schools in `MagicData.FACTION_SCHOOLS[fid]`, its mage in `MAGES[fid]`, its default spellbook in `SPELLBOOK[fid]`
  - every spell in the §3.4 vocabulary
  - The lore room's factions 3-6 add rows. A new effect kind is code, and is the only thing that is.

### 3.2 who casts: mages, rulers and mastery
**Casters.** A **caster** is any mage, or any ruler that can cast rituals, which is every ruler but King Corvane. In battle, only mages and the Ever-Regent cast. The codex `caster` entry says exactly this.

**Mages** are regular units with the trait **Mage**. They fight from the second rank (tier 1), under the same shield rule as Volley. Each round they cast instead of attacking (§5.1).

| id | name | faction | hp | attack | defense | morale | cost | trait |
|---|---|---|---|---|---|---|---|---|
| `adepts` | Sunstone Adepts | Aurel Crown | 10 | 7 | 5 | 9 | 15 | Mage |
| `shamans` | Thornmane Shamans | Thornmane Clans | 10 | 7 | 4 | 8 | 14 | Mage |

- **On the roster from turn 1; recruitable once the faction knows a spell.** The roster stays static, so it never reveals research (§2.2).
  - `TurnResolver.check_recruit` gates them: "The Sunstone Adepts can be recruited once the Crown knows a spell. Research Sunlance or Shield of Law (10 research). The Ever-Regent's own Sunlance doesn't count."
  - They are recruited at the capital, and with Warband Muster.
- **Stats** follow the breakpoint rule. Mages are regular units, so mandates apply to them (Royal Armories, Veteran Levies, Blood Levy). No path node changes them.
- **Mages count as second-rank fighters for the shield rule.** An army with more mages and crossbowmen than front-rank fighters has an exposed second rank, and Skirmish (Fangthrowers) and Wings (Seraphs) always reach it.
  - The mage card says so: "fights from the second rank: safe while your front rank is at least as big; Fangthrowers and Seraphs can always reach it."
  - The recruit preview warns: "This army will have 8 second-rank and 6 front-rank fighters: its second rank is exposed."
- **A mage that attacks** (when no spell is useful) makes an ordinary attack. It is never counted as Volley in the "why" (M5-7 guards `_fight_round`'s second-rank branch on the trait).

**Rulers with magic:**
| ruler | schools | in battle | rituals |
|---|---|---|---|
| King Corvane | none: "an ordinary man" | no | no |
| the Ever-Regent | Sun, Law | **casts**: Sunlance from turn 1, plus every Crown battle spell researched | every Crown ritual researched, and Far Sight |
| the Great Thornmane | the Wild | fights in the front rank | Wild rituals and Far Sight |
| the Ninth Fang | Blood | fights in the front rank | Blood rituals and Far Sight |

**Mastery** is a caster's skill **in one school**, shown and computed as a **bonus**:

| source | bonus |
|---|---|
| a mage | +0 |
| a ruler | + (ability rank − 1): from 0 to +3 |
| the faction's transformation, in its aligned school | +1 |
| that school's mastery node (§4) | +1 |
| **in all** | **at most +3**; the breakdown shows the cap ("capped at +3") |

Each school's bonus adds to exactly two things, one in battle and one on the map. Nothing else scales: never a part (−2, +4), a price other than the wolves', or a greater working.

| school | each point of bonus adds |
|---|---|
| Sun | Sunlance +1 damage; Dawn Blessing +4 hp a turn |
| Law | Shield of Law +1 unit; Sanctum Ward +1 turn |
| the Wild | Briar Snare +1 unit; Call the Pack up to 1 more wolf (5 gold each) |
| Blood | Bloodbolt +1 damage; Bloodrot +4 hp a turn |

This is the brief's "power you keep makes the ruler personally strong: combat stats, spell mastery", made literal. The army panel shows mastery per spell: "Sunlance 5 (mastery +1: Celestial Host); Shield of Law 6 units (+0)."

### 3.3 the price: gold, and blood
- **Rituals cost gold.** There is no new resource and nothing to shuffle; the brief cuts gem busywork. Battle spells cost nothing but the caster's action that round.
- **Tithe of Blood** (§7.1) is the brief's own mandate, "sacrifices fuel rituals instead of gold". A Clans mage's army can pay in blood instead.
- **Why not mana or gems:** a separate resource would need a source, a pool, a forecast and an AI, which is the busywork the brief cuts. Gold already makes rituals compete with recruits, and that is the real decision.

### 3.4 the spell vocabulary (data, so new factions add spells as rows)
Every spell is a row in `MagicData.SPELLS`: `{id, name, school, tier, kind, cost (rituals), range, target, duration, value, count, codex, text}`. Its `text` is the one plain line players read. Battle effects come from these kinds only, each with a codex entry:

| kind | players read | in battle | limit |
|---|---|---|---|
| `bolt` | bolt | one enemy it can reach, picked by the spell's rule, takes `value` damage at the end of the round; it ignores defense, Iron Hide and Rooted; a ruler's spell resistance lowers it (§5.2) | each cast is one bolt |
| `hex` | hex | up to `count` enemy units of one type, or every fighter in a rank, get a part this round | a unit takes a given hex at most once a round |
| `shield` | shield | up to `count` friendly units of one type get a part this round | a unit takes a given shield at most once a round |
| `drink` | heals back | standing fighters heal a share of the damage their attacks dealt, at the end of the round | – |

Ritual effects come from these kinds: `blessing` (on armies), `ward` (on a province), `curse` (on a province), `summon`, `raising` (changes the map for good), `global` (affects every battle) and `sight` (Far Sight).

---

## 4. the arcana: research continues into magic

**The arcana** is each faction's second research tree: two schools, four nodes each. Players see it as the **Magic** tab of the research panel.
- **Same machinery as the path:** the same pool, one-target rule, ETAs and research phase (M4 §2).
- **Lookup:** `AscensionRules` reads arcana nodes through a lookup hook (`node_data` falls back to `MagicData`).
- **Kinds of their own:** arcana nodes have their own kinds, `spell` and `mastery`, so the path's rules are untouched. `is_ordinary`, `requires_any`, `node_ids` and `path_complete` still count path nodes only.
- **New functions:** `arcana_ids` and `all_complete`.

| tier | Crown | Clans | cost | needs |
|---|---|---|---|---|
| I (battle spell) | Sunlance (Sun), Shield of Law (Law) | Briar Snare (Wild), Bloodbolt (Blood) | 10 | nothing |
| II (ritual) | Dawn Blessing (Sun), Sanctum Ward (Law) | Call the Pack (Wild), Bloodrot (Blood) | 15 | the school's tier I |
| mastery | Sun Mastery, Law Mastery | Wild Mastery, Blood Mastery | 20 | the school's tier II; gives +1 mastery in that school to every caster (§3.2) |
| III (greater working) | Sunburst (Sun), Bastion (Law) | Wake the Greenwrath (Wild), Blood Moon (Blood) | 25 | the school's tier II **and** the school's aligned Oath |

**Totals:**
- A whole school is 70.
- Everything a faction can learn is 115: both schools' tiers I and II and mastery, plus one tier III.
- With the path's 100, that is 215 research to want, against about 11 a turn. M4's games run a median of 18 turns, so research has a use all game.

**Pacing** (design intent, on M4 §2.4's land: 6, 7, 8, 9, 10, 11, 11 … a turn):

| plan | order | first spell (end of turn) | transformation (end of turn) | greater working (end of turn) |
|---|---|---|---|---|
| path first | two tier I nodes, Oath, transformation, then the aligned school | 9 | **8** | 13 |
| magic first | aligned tier I, two tier I path nodes, Oath, transformation, tier II, tier III | **2** (mages from turn 3) | 9 | 13 |
| broad | both tier I spells, two tier I path nodes, Oath, transformation | 2 and 4 | 10 | 15 |

Opening with a spell costs the transformation about one turn. That is the new decision before the fork, and every arcana card shows it: "Researching this first delays your transformation by about 1 turn (ETA 9 → 10)."

**After everything.** Once nothing is left to research (every path and arcana node is researched or closed), research becomes gold, in magic games only.
- **The rate:** 2 research for 1 gold, rounded down, with spare points carried. It happens in the research phase.
- **The event:** "Nothing is left to research: your scholars sold their learning for 5 gold (11 research)."

**Spells are researched, not sworn.** Nothing in the arcana closes anything; only the Oath gates tier III.

**Under fog, a rival's arcana is private** (§2.6). Without fog, it is public in the rival's read-only research panel, as M4's path is.

---

## 5. battle spells

### 5.1 the cast step and the spellbook
- **When:** each round, after the `round` event and before the first attack, every standing caster casts. The casters are mages and the Ever-Regent.
- **Order:** casters act **highest mastery bonus first**, taking a caster's best bonus over its schools. Ties go to the ruler first, then to the lowest fighter id.
- **The spellbook** is the faction's battle spells in an order the player sets (**SpellbookOrder**, below), each one on or off.
  - A caster can cast every spell its faction knows that is on.
  - The Regent's own Sunlance is a locked row, "Ever-Regent: always known". Switching it off stops him casting it.
  - The defaults (`MagicData.SPELLBOOK`): **Crown:** Sunburst, Sunlance, Shield of Law. **Clans:** Briar Snare, Bloodbolt.
- **The rule, in one line:** casters spread out first.
  - Each casts the first spell in the spellbook that is useful and that nobody on its side has cast yet this round.
  - When every useful spell has been cast once, the next caster starts again from the top.
  - A caster with nothing useful attacks, as any fighter does.

| spell | useful when |
|---|---|
| Sunburst | round 1, and this side hasn't cast it this battle |
| Sunlance, Bloodbolt | an enemy it can reach is not already going to die from damage aimed at it this round; Bloodbolt also needs the caster at 3 hp or more |
| Briar Snare | an enemy front-rank unit type has units not yet snared this round |
| Shield of Law | one of your front-rank unit types has units not yet shielded this round **and without a terrain or fort bonus** |

- **Examples (Crown defaults):**
  - The Regent alone casts Sunlance every round.
  - The Regent and one Adept: the Regent (ruler first) casts Sunlance, and the Adept casts Shield of Law.
  - Defending a fort, forest or hills, Shield of Law is never useful (§5.2), so the Adept casts Sunlance too.
  - Three Adepts in the field cast Sunlance, Shield of Law, then Sunlance again.
- **Examples (Clans defaults):**
  - One Shaman snares every round while a front-rank type has units left to snare.
  - With two Shamans, the second casts Bloodbolt if it is known. Otherwise it snares 6 more units of the most numerous type with units not yet snared.
- **A caster that casts doesn't attack that round.** The cast is its action.
- **Spells never roll.** No target roll, no hit roll, no resistance roll.
  - Targets follow fixed rules and effects are fixed numbers, so a spell is plannable and always explained by one sentence (pillar 4).
  - **A battle with no caster draws exactly what it drew before.** A battle with casters draws fewer attack rolls, all logged.
- **Timing:** spell damage lands at the end of the round, with the attacks' damage (M1's rule). Hexes and shields apply to the attacks of the round they are cast in.
- **SpellbookOrder(order, off)** is the player's battle doctrine: preparation, not micromanagement (pillar 3).
  - Serialized as `{"type": "spellbook", "order": [ids], "off": [ids]}`.
  - At most one per turn. It applies in the orders phase, so this turn's battles use it, and it persists in `Faction.spellbook`.
  - It is set in the Magic tab's **Battle spellbook** list.
  - Under fog it is private, and learned by seeing the casts.
  - The list previews each of your armies from the real cast step: "Army at Highcrag (Ever-Regent, 2 Adepts): Regent Sunlance, Adept Shield of Law, Adept Sunlance. Defending a fort, forest or hills: Shield of Law is skipped."

### 5.2 the spells
| id | school | tier | kind | effect | example |
|---|---|---|---|---|---|
| `sunlance` | Sun | I | bolt | 4 damage to the enemy unit or creature it can reach with the **highest maximum hp**, the most hurt of those first. Rulers and commanders only when nothing else is in reach. | Four Adepts in reach of 2 War Bears (23 hp): all four lances go into the first bear, 16 damage. Not into the healthiest Tusker, so no Berserk goes off for nothing. |
| `shield_of_law` | Law | I | shield | +4 defense this round for up to **6** of your front-rank units of one type: the most numerous type with units not yet shielded **and without a terrain or fort bonus**, first standing in line | Your Spearmen (9 with Shield Wall → 13) attacking against Tuskers: each Tusker's hit chance drops 68% → 52%, its damage 4 → 3. About 7 damage blocked a round with 6 of 20 covered. |
| `sunburst` | Sun | III | hex (a rank) | round 1 only, once per side per battle: **every** enemy fighter in the front rank, rulers included, has −2 attack this round | 40 Tuskers against Spearmen: hit chance 68% → 60%, damage 4 → 3 each. About 37 damage saved in round 1. |
| `briar_snare` | Wild | I | hex | −2 attack this round for up to **6** enemy front-rank units of one type (**8 in a forest province battle**): the most numerous type with units not yet snared, first standing in line | 6 Knights against Tuskers: hit chance 88% → 80%, damage 5 → 4 each. About 7 damage saved that round. |
| `bloodbolt` | Blood | I | bolt | 5 damage to the enemy unit or creature it can reach with the **fewest hp left** that isn't already going to die this round. Rulers and commanders only when nothing else is in reach. The caster bleeds 2 hp. | A Shaman (10 hp) can cast it four rounds running. Each bolt finishes the weakest enemy in reach. |

- **Mastery** (§3.2): Sunlance's and Bloodbolt's damage, and Shield of Law's and Briar Snare's count, each +1 per point of bonus in their school.
- **Bolts never overkill.** Targets count the damage already aimed at them this round (hp − pending damage, including earlier casts). Ties go to the lowest fighter id.
- **Rulers have spell resistance.** "A ruler shrugs off part of every bolt": each bolt on a ruler deals ability rank ÷ 2 less, rounded down (rank 1: 0; ranks 2-3: 1; rank 4: 2), never below 1.
  - Both bolts reach a ruler only when nothing else is in reach, so a well-kept ruler is no longer the bolts' magnet, as M2 §1.6 intends.
  - Sunburst is a hex, not a bolt, so it covers a front-rank ruler like anyone else.
- **Shield of Law is a field spell.** It never covers a unit that already has a terrain or fort bonus.
  - So it can't stack with walls or woods, and never helps a stack hold its capital. It helps attackers, and armies on open plains.
  - Its +4 keeps every defense on 4k or 4k+1: Spearmen 9 → 13, Iron Knights 13 → 17.
- **Parts follow the breakpoint rule:** attack −2 (one damage step) and defense +4 (one damage step that keeps the alignment). Spell parts are named parts (`spell_<id>`), read by every tooltip, breakdown and "why".
- **"Units"** are regular units and summoned creatures, never commanders or rulers, except where a spell says "fighter".
  - The "most numerous type" counts standing units. Ties go in roster order, then summoned types in data order.
  - "First standing in line" means fighter order.
  - In M6, with several enemy sides, a hex looks across all of them in side order.
- **Bleeding** (Bloodbolt) is damage on the caster from itself, landing with the round's wounds.
  - It never takes the caster below 1 hp, and it turns on the caster's Blood Frenzy.
  - **It doesn't count as lost for the morale check:** a side's lost share counts hp lost to the enemy.
  - **It closes when the battle ends** if the caster still stands: the bled hp come back, as a `bleed_closed` aftermath line.

### 5.3 no stacking (the veteran's question)
- **A unit takes a given hex or shield at most once a round,** and Sunburst comes once per side per battle. A second caster with the same spell covers more units, or moves on (§5.1).
- **Bolts add up,** because each is one caster's action and costs 14-15 gold of fragile second-rank fighter. They focus on one target until it dies, never overkill, and reach rulers last.
- **Spell parts stack with other parts** as separate named parts, exactly as mandate and path parts do. Shield of Law is the exception by its own rule.
- **No morale spells in battle.** M4-6 found that −4 morale stacks decide games. The only morale magic is Dawn Blessing's +1 on your own armies (§6.2).

### 5.4 in the log, the report, the captions and the why panel
**Battle log.** Still schema version 1, with additions under a top-level `"magic": true`, as M4 did with `"paths"`. Every other log is byte-identical.
- **side:** `"casters"` (fighter ids), `"spellbook"` (spell ids in order, on only), `"enchantments"` (`[{"id", "ritual", "effect"}]` in play)
- **fighter:** `"mastery"` (`{school: bonus}`) for casters; `"summoned": true` for creatures
- **new event `cast`**, after `round` and before the round's attacks, one per cast:
  ```
  {"t": "cast", "n": 1, "by": 12, "spell": "briar_snare", "school": "wild", "kind": "hex", "bonus": 0,
   "targets": [3, 4, 5, 6, 7, 8],                 # fighter ids, in order
   "part": {"stat": "attack", "value": -2},       # hex and shield (they last the round)
   "damage": 0,                                   # bolt: per target, after spell resistance
   "self": 0,                                     # Bloodbolt: the caster's bleeding
   "why": "spread: nobody had cast Briar Snare this round; Knights were the most numerous front-rank type"}
  ```
- **attack:** `attack.parts` and `defense.parts` may hold `"spell_<id>"` keys.
- **wound:** `by` includes the casters whose bolt hit, and a bleeding caster itself.
- **heal:** `"spell": "blood_moon"` in place of `"trait"` when the moon's share was the one used.
- **round_end.impact:** includes `spell_<id>` keys.
- **Helpers:**
  - `BattleLog.validate` learns `cast`; `verify_draws` needs nothing, since casts draw nothing.
  - `cross_check` adds "cast damage equals the matching part of the wounds".
  - `BattleTimeline` folds cast damage as pending, and `statuses` gains **snared** and **shielded**.

**Report "why"** (`AutoBattleResolver._factors`). Each factor has a clause, a brief and a codex id.
- **`spell_<id>`,** measured in the impact accumulator:
  - bolts: the damage they dealt
  - shields: what the defense part blocked, measured like terrain
  - hexes: the expected damage the part took off enemy attacks, **credited to the casting side.** `_fight_round` credits attack parts to the attacker, so M5-7 inverts spell attack parts explicitly.
  - Blood Moon: the hp healed back
- **`morale_spell_dawn_blessing`:** measured from the morale checks, like Inspire.
- **Clauses:**
  - "The Thornmane Shamans' Briar Snare slowed the Knights for about 14 damage over 3 rounds."
  - "Sunlance felled the War Bear in round 2, never missing."
- **Report sides** gain `"casters"` and `"spells_cast"` **only in a magic game.**

**Captions** (`BattleCaptions`):
- **A new line-1 rule, "greater",** after "ruler": a tier III cast. "Round 1: the Aurel Crown's Sunstone Adepts called down Sunburst: the 40 Thornmane fighters in the front rank have −2 attack this round."
- **A new rule, "first spell":** the first cast of each spell in a battle is always named once, on the next free line 2 from that round on. "The Sunstone Adepts cast Shield of Law: 6 Spearmen +4 defense this round."
- **Spell factors** go through the existing "impact" rule, with their own phrases (`_worth_phrase`):
  - hex: "Round 1: the Thornmane Shamans' Briar Snare slowed 6 Knights: −2 attack this round, about 7 damage saved."
  - shield: "Round 3: the Sunstone Adepts' Shield of Law gave 6 Spearmen +4 defense this round: about 7 damage blocked."
  - bolt: "Round 2: Sunlance struck the War Bear for 8 damage (2 casts, never missing)."
  - heals back: "Round 4: under the Blood Moon, the Thornmane Clans healed back 9 hp."

**Key moments** (`BattleMoments`): a new kind, **`spell`** ("First spell"). It marks the first `cast` event, then each tier III cast. When there is none it is disabled, with "No spells: neither side has a caster".

**The why panel and hover** (`BattleExplain`):
- A caster: "Thornmane Shamans · second rank · casting Briar Snare on 6 Knights: −2 attack this round. It cast Briar Snare because it's first in their spellbook (Briar Snare, Bloodbolt) and nobody had cast it yet this round. Spells always land: they don't roll."
  - The text says "your spellbook" for your own casters.
  - A skipped spell names its reason: "Shield of Law skipped: your Spearmen have the fort's +2."
- A target: "attack 9 = Knights 11 − Briar Snare 2 (the Shamans, this round)".
- A bolt on a ruler: "Sunlance 6 − the Great Thornmane's spell resistance 1 (ability rank 3) = 5".
- The feed lists every cast as a notable event.

---

## 6. rituals

### 6.1 the cast order
**CastOrder(ritual, army, target, pay, size)** is serialized as `{"type": "cast", "ritual", "army", "target", "pay", "size"}`.
- `pay` is `"gold"` or `"blood"`.
- `size` is Call the Pack's wolves; it is absent for every other ritual.
- Old records without it load unchanged.

**The caster.** The army named must be yours and must hold a caster for that ritual: one of your mages (any of your faction's schools), or your ruler if the ritual is in its school (§3.2). The ritual is cast **from the province where that army starts the turn**.

**Casting pins the army: it holds this turn.**
- **The pinned set:** `MagicRules.pinned_armies(state, fid, orders)` computes it from every legal cast in the whole order list, as `RulerRules.state_after_orders` does for sacrifices. `check_move` consults it, and so does the resolver.
- **Queuing a cast** drops any move for that army, whenever it was given, with the reason: "Move to Thornvale removed: the army at Fangridge is casting Bloodrot this turn, so it holds."

**Limits:**
- one cast order per army per turn
- each ritual at most once per faction per turn
- **a running budget:** your queued gold-paid rituals plus queued recruits must fit your gold
  - `OrderBook` accepts a new spending order only if everything queued still fits. On a re-check it keeps orders in the order given.
  - `TurnResolver.price_recruits` and `Forecast` take the gold the rituals phase actually spent, so they agree.

**Legal when** (checked in the orders phase against the state after sacrifices, using only public facts and your own state, §2.10):
- the game has magic
- your faction knows the ritual (researched; Far Sight needs no research)
- the army is yours and holds a caster for it
- the target is in range and fits the ritual's target rule (§6.2)
- you can pay: within the running budget, or with `pay: "blood"`, under Tithe of Blood with enough hp in the caster's army (§7.1)

**Rejected with a plain reason.** For example: "Bloodrot reaches 2 provinces from the caster. Crownkeep is 3 from your Shamans at Wildmoor."

### 6.2 the rituals
**Durations.** Every duration is written "through turn N": the effect lasts through the end of turn N and ends in that turn's enchantments phase (`until_turn` = N). T is the turn the ritual is cast.

| id | name | school | tier | kind | price | target | through | effect |
|---|---|---|---|---|---|---|---|---|
| `dawn_blessing` | Dawn Blessing | Sun | II | blessing | 12 | a province you own within 2, **where an army of yours stands** | T + 2 | Every army of yours standing there as the ritual resolves is blessed, wherever it then goes. **In battle:** a side gets +1 morale for the whole battle if, when the battle starts, at least half its fighters are in blessed armies. **In the enchantments phase:** each blessed army heals **12 hp** (+4 per Sun bonus), one hp at a time to its wounded fighter with the fewest hp left. |
| `sanctum_ward` | Sanctum Ward | Law | II | ward | 8 | a province you own within 2 | T + 1 (+1 per Law bonus) | Rival rituals aimed at it are **turned aside** (§6.3). A rival curse already there ends at the end of this turn, after biting once more. Battles there are outside the Blood Moon. |
| `bastion` | Bastion | Law | III | raising | 30 | a province you own within 1 that has no fort | for good | It gains a fort. **At most 2 Bastion forts per faction, ever** (`Faction.bastions`), whether or not they are later lost. A captured Bastion fort serves its new owner. |
| `call_the_pack` | Call the Pack | Wild | II | summon | **5 a wolf** | the caster's province | T + 4 | You choose 3 up to 3 + Wild bonus Thornwolves. They form **a new army of their own** there, which holds this turn. A new pack can be called only once the last has faded or fallen. |
| `wake_the_greenwrath` | Wake the Greenwrath | Wild | III | summon | 30 | the caster's province, which must be **forest** | until it falls | The Greenwrath forms a new army of its own there, which holds this turn. One at a time. |
| `bloodrot` | Bloodrot | Blood | II | curse | 15 | a province not yours within 2 | T + 2 | **Fighters there not of your faction can't heal.** In the enchantments phase it takes **12 hp** (+4 per Blood bonus) from them, one hp at a time from the fighter with the most hp left, never below 1. It first bites after this turn's battles. |
| `blood_moon` | Blood Moon | Blood | III | global | 26 | none | T + 2 | In every battle, each of your standing fighters heals back a fifth of the damage its attacks dealt that round, **rounded down**. A fighter that already heals back (Lifedrinker) heals the larger share, not both. **Under the moon none of yours heals back above maximum − 1:** the wound stays open. Spell damage isn't healed back. Battles in a rival's warded province are outside the moon. Only one global ritual can be up at a time. |
| `far_sight` | Far Sight | common | – | sight | 6 | any province within 3 | T + 2 | You see it **in clear sight at the start of your next 2 turns.** On a rival's capital you also get a **reading**: that rival's gold, mandates, kept power, research pool, nodes, spells and spellbook, but not its research target. A rival caster standing there blocks the reading, not the sight. |

**Turned aside costs half.** A ritual aimed at a province a rival has warded is turned aside, and you pay half its price, rounded down: "the power is spent". This keeps a ward a real guess and stops free probing.
- A ritual that fails for any other reason costs nothing: the caster's army is gone, the Greenwrath is already awake, or the target no longer fits.
- A Far Sight whose reading a caster blocks is not turned aside. You see the province, caster included, and pay full price.

**Summoned creatures** (`MagicData.SUMMONS`):

| id | name | hp | attack | defense | morale | trait | notes |
|---|---|---|---|---|---|---|---|
| `thornwolves` | Thornwolves | 9 | 11 | 4 | 8 | Skirmish | a scout (sight 2); gone at the end of T + 4 |
| `greenwrath` | Greenwrath | 40 | 15 | 9 | 14 | Rooted | drawn twice as big; one fighter for every rule; stays until it falls |

- **Loading and saving.** They are never recruited, but they are always on the faction's list of known unit types in a magic game, so they load and save.
- **Mandates skip them.** Mandates, path parts and Blood Levy skip them, as they skip rulers. `UnitType.summoned` is honoured by `unit_max_hp`, `arrival_hp` and `_unit_mods`.
- **Fading.** A creature that fades leaves its army. An army left empty is removed, with an event.
- **Pricing.** A wiped pack can be called again the next turn, so wolves are disposable forward fighters at 5 gold each, against a Fangthrower's 8: +1 hp, −1 defense, and gone after 5 turns. That is how they are priced.

**Far Sight** is a rule whenever magic is on (§2.1); without fog, the UI and the AI never offer it.
- Every faction with a caster knows it, without research.
- Only a Sanctum Ward turns it aside. A caster in the province blocks only the reading.

**Why these numbers:**
- **Budgets, not per-fighter effects.** Dawn Blessing and Bloodrot move a fixed number of hp a turn. A curse that took 2 hp from every fighter would take 584 hp a bite from M4's 292-unit stand-off. A blessing that healed every fighter would heal over 1,000 hp for 12 gold.
  - Over its life, Bloodrot takes 36 hp and stops all healing. Dawn Blessing heals 36 hp on each blessed army.
  - That is about 2-3 hp per gold, the M2 rule of thumb for value per price.
- **"Can't heal" is the stand-off breaker.** It stops Mending Light (up to 12 a turn on every wounded fighter), Hallowed Land and the Forges. A stack the AI won't attack (#94) stops recovering, unless the Crown wards it.
- **Dawn Blessing rides with armies.** It helps an army march out, not a stack sit at home.
- **Sanctum Ward gives no battle bonus.** It lasts 2 turns for 8 gold, and each ritual is cast at most once a turn, so the Crown can hold at most 2 or 3 wards up.
- **Call the Pack** is capped at one pack and priced per wolf, so mastery buys a bigger pack, not a free one.
- **Bastion** stops at two, so the Forge Crown gets two forward forges, not a fortified home.

### 6.3 resolution: the rituals phase and the enchantments phase
**The rituals phase** is new. It comes after orders and before movement. Cast orders resolve in this fixed order of kinds:
1. **wards** (Sanctum Ward)
2. **curses** (Bloodrot)
3. **blessings** (Dawn Blessing)
4. **summons** (Call the Pack, Wake the Greenwrath)
5. **raisings** (Bastion)
6. **global** (Blood Moon)
7. **sight** (Far Sight)

Within a kind they go by faction id, then in the order each player gave them. Each ritual then has one of three outcomes:
- **Turned aside.** The target carries a rival's ward, counting wards resolved earlier this phase. Half the price is paid, and nothing else happens: "Sanctum Ward turned your Bloodrot aside at Crownkeep: half its price (7 gold) was spent."
- **Failed otherwise.** Nothing is paid, and the reason goes in your report.
- **Took effect.** The ritual is paid (in gold, or in blood by §7.1) and takes effect. `ritual_cast` records it, plus `blood_paid`, `summoned`, `fort_raised` and `enchantment_began` where they apply.

**Why this order:**
- **Wards first.** A ward cast in the same turn as a curse protects. A defender who guesses right wins the exchange, and the order is fixed and documented (pillar 5).
- **Gold before recruits.** Rituals spend gold before the recruitment phase, and the running budget (§6.1) means a queued recruit never finds its gold gone.
- **Before movement.** A caster casts where it starts the turn, like Warband Muster's gathering. Blessings then count in this turn's battles, summons can defend their province this turn, and a curse bites at the end of the turn.
- **The forecast warns** that a rival may summon or raise a fort before the battle (§2.10).

**The enchantments phase** is new, and comes last. It runs province by province in id order, and enchantment by id within each:
1. **Dawn Blessing heals** blessed armies (after Mending Light, which stays in the rulers phase).
2. **Bloodrot** takes its hp.
3. **Endings.** Every enchantment whose `until_turn` is this turn ends, and so does a curse a ward ended this turn, after biting. Summoned creatures whose time is up fade.

Each step has an event: `blessing_healed`, `curse_bit`, `enchantment_ended`, `summon_faded`.

**Healing while cursed.** A fighter is cursed while it stands in a province under a rival's Bloodrot at the moment of healing. A cursed fighter heals from nothing:
- Mending Light and ruler healing (rulers phase)
- Hallowed Land and the Forges (research phase)
- Dawn Blessing
- Feast of Victory after a battle in that province
- Lifedrinker and the Blood Moon in a battle there

A border battle is in no province, so nobody in it is cursed.

### 6.4 enchantments in the state
- **`GameState.enchantments`** is sorted by id and saved only in a magic game. Each entry is `{"id", "ritual", "faction", "kind", "province", "armies", "cast_turn", "until_turn", "bonus", "ending"}`:
  - `province` is "" for a global
  - `armies` is the blessed army ids (blessings only)
  - `ending` is true once a ward has ended a curse
- **Ids count per faction** ("beasts-e3", from `Faction.enchant_counter`). Views show rivals' enchantments only under view ids (§2.7), so the counter never leaks.
- **Summoned units** carry `until`: the turn they fade, or 0 for the Greenwrath. It is serialized only when non-zero.
- **The same ritual on the same target restarts it** with a new `until_turn`, paid again. It never stacks: one Bloodrot per province, one blessing per army, one ward per province.
- **A blessing follows its armies.** A destroyed army loses it. Recruits who join a blessed army are blessed. Armies never merge in this engine (there is no merge order), so nothing else can join one.
- **Captures don't touch enchantments.**
  - A ward protects only its caster's faction, so it stops protecting a province that changes hands.
  - A curse on a province its caster then captures goes on, and hurts only other factions' fighters.
- **Far Sight** is a `sight` enchantment. `MagicRules.vision_grants(state, fid)` reads it, and `FogRules.sight` calls that.
- **`Faction.bastions`** lists the provinces Bastion raised, for the cap.
- **`GameState.validate`** checks every enchantment, summoned unit and Bastion entry in plain language.

---

## 7. Tithe of Blood and the rulers' magic

### 7.1 Tithe of Blood
**The mandate:** `tithe_of_blood`, **Thornmane Clans only, cost 3** (4 by mid-game sacrifice).
- It lives in its own list, `MandateData.MAGIC_MANDATES`, so the M2 build screen and presets are unchanged without magic.
- **It can't be held with Feast of Victory:** "blood given is not taken back". Whichever is owned excludes the other, on the build screen and in `sacrifice_check`. The Blood Pact already forswears Feast for the same reason.

**The build-screen row:** "Lets rituals your Shamans cast be paid in hp instead of gold: 1 hp a gold, from the regular units in the Shamans' own army, one soldier at a time. You choose gold or blood on each cast. Rituals your ruler casts always cost gold, because a ruler stands alone. Can't be taken with Feast of Victory. First use: Far Sight once you have Shamans (with fog on), otherwise your first tier II ritual (about turn 5)."

**The effect:**
- **The price.** A ritual can be paid in blood: **1 hp for each gold**, from the regular units **in the caster's own army**, which holds anyway.
- **One soldier at a time.** The unit with the most current hp gives until it is at 1 hp, then the next. Ties go in army order.
- **Not rulers.** A ruler's army holds no regular units, so a ruler always pays in gold.
- **Short of blood.** If the army can't give that much, the order is illegal with `pay: "blood"`.
- **Turned aside.** A turned-aside ritual takes half the hp.

**Example:** Call the Pack with 3 wolves (15), paid by a garrison of 6 Tuskers at 14 hp. The first Tusker gives 13 (down to 1 hp) and the second gives 2 (down to 12). That is two wounded Tuskers, not six.

**The forecast names the soldiers and the side effects:** "Paid in blood: 2 of your 6 Tuskers at Fangridge give 15 hp (one to 1 hp, one to 12). Both will be wounded: Berserk on. The army holds this turn."
- If a Shaman in that army would drop below 3 hp, the forecast adds: "Your Shaman can't cast Bloodbolt below 3 hp."

**Why one at a time, and no Feast.** Spreading the price as 1 hp per soldier would be the perfect Berserk and Blood Frenzy pattern: each Tusker's expected damage on Spearmen would go 2.7 → 6.3. Feast would hand the blood back after every win. Either would make the price a bonus, as M4's first Blood Levy was; that had to be cut twice (M4 §10.4).

**Why Clans only:** blood is a Clans school, and Berserk, Blood Frenzy and the Blood Pact are where wounds mean something. A shared version is a question for Alex (§20).

### 7.2 the Ever-Regent's spells
- **He casts in battle (§5.1).**
  - Sunlance is his from turn 1, whether or not the Crown has researched it, because he taught it to the Adepts.
  - Every Crown battle spell the Crown researches joins his spellbook.
  - Ties go to the ruler, so he casts first among equals.
- **His mastery bonus** is ability rank − 1, plus the Celestial Host and Sun Mastery, at most +3:
  - Sunlance deals 4-7.
  - Shield of Law covers 6-9 units.
- **Against his M2 attack:** at kept power 5 his attack was 13. Against Tuskers (defense 4) that is a 90% hit chance for 6 damage, about 5.4 expected; Sunlance at rank 2 is 5 sure damage. The damage is a wash. His gain is in targeting (the biggest creature, focused until it falls) and in rituals.
- **On the map** he casts every Crown ritual the Crown has researched, and Far Sight.
- **Mending Light** (M2) is unchanged, except that it can't heal cursed fighters.
- **Looks:** the M3 arcane-bolt projectile becomes Sunlance's gilt beam. His fifth 3D pose is **cast** (3D_DIRECTION §9.3 budgets five poses for rulers, "or cast for casters").
- **Regent's Court** won 93% of the M4 games it finished. §13.2's band G10 now holds it to at most 60%, and §13.3 gives it knobs.

### 7.3 the other rulers
- **The Great Thornmane** casts Wild rituals and Far Sight: Call the Pack (up to 3 + bonus wolves, 5 gold each) and Wake the Greenwrath. His battle role is unchanged: the front rank, and Dread.
- **The Ninth Fang** casts Blood rituals and Far Sight: Bloodrot (12 + 4 per bonus hp a turn) and Blood Moon. Warband Muster is unchanged.
- **King Corvane** casts nothing. His power goes into Royal Court and his own sword, and that difference is the point of choosing him.
- **Casting holds the ruler,** like any caster's army (§6.1). A field ruler chooses between marching and casting.
- **The build screen's ruler cards** gain one line, with numbers live at the kept power you are setting:
  - "Casts Sunlance in battle (5 damage now) and every Crown ritual you research."
  - "Casts Wild rituals: up to 4 wolves (20 gold) once you research Call the Pack."
  - "Casts nothing: an ordinary man."

---

## 8. magic, paths and transformations
1. **The Oath opens its school's greatest working** (tier III). Swearing the Dawn closes Bastion; swearing the Forge closes Sunburst. The fork now decides magic too.
2. **The transformation adds +1 mastery** in its aligned school to every caster of the faction:
   - Celestial Host → Sun
   - Living Iron → Law
   - Thorn Wild → the Wild
   - Blood Pact → Blood

   There is no rename and no new art; it is a breakdown line. The cap of +3 applies: a rank-4 Regent gains nothing, and the line says so.
3. **The other school stays open** at tiers I and II and its mastery node. Magic gives breadth; the fork gives depth.
4. **Province rules meet rituals:**
   - Hallowed Land heals at home, and Dawn Blessing heals armies on the march.
   - The Forges heal to full in the two forts Bastion can raise, and Forge Tithe pays +4 gold for each.
   - The Wild Spreads grows the forests where Briar Snare catches 8 and the Greenwrath can wake.
   - The Blood Moon keeps Blood Levy's wounds open while the Bloodtuskers heal back.
   - Bloodrot stops Hallowed Land and the Forges where it lies.
5. **The lock-in preview** (M4 §5) gains one row per side, listing only what changes:
   - "Opens Sunburst (Sun, greater working). Sunlance: Adepts 4 → 5, the Ever-Regent 5 → 6. Dawn Blessing heals 16 a turn instead of 12."
   - The closed side's greater working is struck through.
6. **Mandates:** nothing forswears Tithe of Blood. The Thorn Wild already forswears Blood Frenzy, which makes blood-paying less attractive there, and that is intended.

---

## 9. turn resolution in M5 (phase order)
The fixed order. `RulesCodex "phase_order"` must say exactly this.

1. **sacrifice:** as M2.
2. **orders:** spellbook orders apply. Cast orders are checked first, which pins their armies. Then every other order is checked, as in M4.
3. **rituals** (magic): §6.3. Each ritual is turned aside, fails, or is paid and applied, in the order of kinds.
4. **movement:** as M4. Pinned armies and newly summoned creatures hold.
5. **battles:** as M4, plus each round's cast step (§5.1), blessings' +1 morale and the Blood Moon. Bleeds close at the end of the battle.
6. **capture:** as M4.
7. **recruitment:** as M4. Mages need a known spell, and recruits are priced from the gold left after rituals.
8. **income:** as M4.
9. **research:** as M4, with arcana nodes. Healing here skips cursed fighters, and research becomes gold once nothing is left.
10. **rulers:** as M2. Healing here skips cursed fighters.
11. **enchantments** (magic): §6.3. Blessings heal, curses bite, then the endings.

- `TurnResolver.MAGIC_PHASES` is `["sacrifice", "orders", "rituals", "movement", "battles", "capture", "recruitment", "income", "research", "rulers", "enchantments"]`.
- `resolve()` runs the two new phases only when `state.magic`. `PATH_PHASES` and `PHASES` are untouched.
- `GameSession.MAGIC_REPORT_PHASES` adds `"rituals"` after `"orders"`, and `"enchantments"` before `"victory"`.
- **M5 adds no randomness:** spells and rituals never draw, and fog draws nothing.

---

## 10. AI

### 10.1 under fog: fair play
- **The AI is handed its view and nothing else.**
  - In a fog game, `AISeat` passes `session.view_state(fid)` to `AIPlayer.plan_orders`, in `_init` (the build pick) and in `take_turn`.
  - `report_notes` reads `turn_report_for(fid)`.
  - In fog games the autoplay `Simulator` passes the same view to its policies, and keeps the observer for its invariants only.
  - The brain's signature doesn't change.
- **Estimates:**
  - It plans attacks against the shown numbers, which is what a human sees.
  - Its capital-threat check counts the top of each sighting's total (from the view note), so cheap mixed armies can't bluff it into freezing, and big ones can't hide.
- **Its orders are always legal.** They are checked on the true state by the same `OrderBook`, and legality reads only public facts and its own state (§2.10). "Zero rejections" stays a test.
- **The game seed.** The brain keeps it for its own fork roll (M4 `choose_branch`). A static test checks that `ai/` never resolves a turn, never seeds an RNG from a turn seed, and never calls a session's truth accessors.
- **New behaviour,** all rules, with no new draws:
  - **Stale ghosts.** `ai/ai_fog.gd` strips remembered armies older than 3 turns from the view once, before planning (`MEMORY_TRUST = 3`).
  - **Scouting.** When its objective (#94's strike, or the enemy capital) is out of sight or only remembered, it moves its nearest free scout army one step toward it, if the step is safe by today's odds rule. Or it casts Far Sight (§10.2).
- **How the tests prove it** (`tests/test_ai_fog.gd`):
  1. **`test_orders_ignore_hidden_facts`:** the snapshot and two-turn tests (§2.7), run through the brain. The view is byte-identical, **and so are the AI's orders.**
  2. **`test_ai_seat_reads_only_the_view`:** a spy `GameSession` records the accessors the seat calls; no truth accessor is called in a fog game. A static scan of `ai/` and the autoplay policies backs it up.
  3. **`test_zero_rejections_under_fog`:** 30 turns of human against AI with fog give zero AI rejections, and the same seed gives the same orders.
  4. **Fog off:** with fog off, AI games are identical to `main` (`test_fog_off.gd`'s policy rerun).

### 10.2 magic
- **Research.** `data/build_presets.gd` gains `ai_arcana` per preset.
  - It researches its aligned school's tier I after its first ordinary node; it knows its fork from `choose_branch`.
  - Then it follows `ai_path`.
  - After the transformation: aligned tier II, tier III and mastery, then the other school's tier I and II.
- **Spellbook:** the default. The AI sends no SpellbookOrder in M5.
- **Recruits.** `_recruit_value` values a mage from its spellbook, using the resolver's own constants, over `ROUNDS_GUESS`:
  - a bolt at its damage
  - a hex or shield at its count × the expected damage its part moves, against the most numerous enemy front-rank type (or our own)
  - At most one mage per 4 regular units in an army, so its second rank isn't exposed (M5-11: 6 → 4, §13.3).
- **Rituals:** at most one a turn per eligible army, only from armies that hold anyway (garrisons) or a ruler on its `home` role. It never pins an army it ordered to attack. The first rule that applies wins:

| priority | ritual | when |
|---|---|---|
| 1 | Sanctum Ward | an own province is cursed; **or (ward ahead)** its capital is within 2 of a province the rival owns and the rival can curse (Blood known, or always without fog) and the capital has no ward through next turn; or (fog) its capital was read by Far Sight last turn |
| 2 | Dawn Blessing | its main army stands in an own province, will attack this turn or next, and isn't blessed |
| 3 | Wake the Greenwrath | known, not awake, and a caster stands in a forest |
| 4 | Call the Pack | known, no pack alive, and an enemy army within 2 of the caster; the full size it can afford |
| 5 | Bloodrot | the strongest enemy stack it can see within range (an enemy capital first) |
| 6 | Blood Moon | its main army will attack this turn |
| 7 | Bastion | its highest-income frontier province without a fort, while it has raised fewer than 2 |
| 8 | Far Sight (fog only) | its objective or the enemy capital if not in clear sight, and not turned aside there in the last 3 turns |

- **Gold:** rituals take at most 40% of the gold left after essential recruits (`RITUAL_SHARE = 0.4`).
- **Tithe of Blood:** it pays in blood when its caster's army can give the price and keep two thirds of its hp. `blood_of_the_fang` puts Tithe of Blood first in its sacrifice picks in a magic game, since no preset holds Feast.
- **Battle spells need no AI:** the resolver casts them.
- **Determinism:** every choice is a rule, with ties broken by id. Magic adds no draw to the seat RNG, and with magic off, AI games are unchanged.
- **#94 under fog:** its stand-off rule reads only the view in a fog game. M5-4 checks it.

---

## 11. approachability (mandatory; every M5 ticket ships its own part)
The new player's test: can they understand every spell, ritual and fog mark **at the moment it matters**? These are the moments. Long text sits one hover away (approachability rule 4).

### 11.1 fog
| moment | what the player sees |
|---|---|
| new game screen | the Fog of war tooltip (§1.3) |
| first fog turn | a one-line hint, with Got it, remembered in settings: "Fog of war is on. You see exactly where you own land or stand; next to that you glimpse armies roughly (two away from forts, commanders, rulers and scouts); beyond, only what you saw last." |
| hovering a glimpsed army | "≈20 fighters (Thornmane Clans), glimpsed from your army at Highcrag: about 15 Tuskers, about 5 Fangthrowers, led by a Warchief. About 20 means 18-22. Last turn: about 15. You glimpse them because they are next to your land." The next line depends on the game. **Fog only:** "Fight them to see them exactly." **Magic with a caster:** "Fight them, or cast Far Sight, to see them exactly." **Magic, no caster yet:** "… or cast Far Sight once you have a mage (research any spell first)." |
| hovering a province out of sight | "You can't see Wildmoor now. Last seen 3 turns ago (turn 6): about 10 Tuskers, about 5 Fangthrowers. Last fought there on turn 4: 6 Tuskers survived, 18 hp in all. You can see as far as Thornvale (range 1)." |
| unit card, army panel, move forecast | "Scout: sees 2 provinces." / "This army sees 2 provinces (it has Knights)." / "Next turn this army will see Wildmoor and Fangridge." |
| any forecast | §2.10's short line, with ⓘ for the assumptions; a target out of sight says "no odds" |
| a rival's panel | "What you know about the Thornmane Clans: the Great Thornmane (kept power 7, seen turn 5). Mandates: Iron Discipline (seen in battle, turn 4). Spells: Briar Snare. They may have more." A ruler you can't see shows "alive, location unknown". |
| turn report | the header "Fog of war: this report shows what you saw", and §2.8's "what you didn't see" |
| map | a **Vision** map mode: in clear sight, glimpsed and out of sight, with each province's source on hover. The world legend adds the veil, the "≈" plate, the ghost ("remembered: last seen N turns ago"), "never seen", and the eye |
| victory screen | "The fog lifts": everything everyone had, and every "what you didn't see" (§2.1) |

### 11.2 magic
| moment | what the player sees |
|---|---|
| build screen | the magic line on each ruler card (§7.3) and the Tithe of Blood row (§7.1) |
| the **Magic** tab | Two school columns of four cards each: name, cost, ETA, one-line effect, state, "delays your transformation by about 1 turn". Tier III shows "needs the Oath of the Dawn". Hover shows the full effect with your numbers now, and what changes for your casters: "Briar Snare: −2 attack this round on up to 6 enemy front-rank units of one type (8 in a forest). Against the Crown's Knights, each snared Knight deals about 1.2 less damage that round. Once researched, with your spellbook as it is: 1 Shaman snares every round; a second casts Bloodbolt if you know it, otherwise it snares 6 more." Shield of Law's card starts: "Field spell: never on units that already have a terrain or fort bonus. It does nothing for defenders in a fort, forest or hills; it helps when you attack and on open plains." A mastery node shows each caster's change: "Ever-Regent: already at the +3 cap, no change." |
| the Battle spellbook list | drag to reorder and tick to switch off. A live preview per army, from the real cast step (§5.1), shows the skips ("defending a fort, forest or hills: Shield of Law is skipped"). The Regent's Sunlance is a locked row. |
| first spell | the turn report: "You researched Sunlance. You can now recruit Sunstone Adepts at Crownkeep, from turn 3. In battle, each Adept casts a spell every round instead of attacking: Sunlance deals 4 damage to the biggest enemy creature it can reach, never missing." |
| recruiting a mage | The unit card lists the spellbook in order, one line each, and says "casts instead of attacking; fights from the second rank: safe while your front rank is at least as big; Fangthrowers and Seraphs can always reach it". The recruit preview warns if the second rank would be exposed. |
| an army's panel | "Casters: 2 Sunstone Adepts. Sunlance 4 damage, Shield of Law 6 units (mastery +0)." |
| before a battle | The odds forecast names the spells each side will cast, and what it skips: "Your 2 Adepts will cast Sunlance and Sunlance (Shield of Law has no effect here: your Spearmen have the fort's +2). Their Shamans: assumed Briar Snare." |
| during a battle | the cast effect; the caption (§5.4: every spell named at least once); the why panel's feed; hover on caster and target; the legend's glyph for each kind (bolt, hex, shield, heals back) |
| after a battle | the report's "why" chips name the spells, each linked to its codex entry |
| ordering a ritual | the **cast dialog**, two clicks from the army (Cast → ritual) |
| a curse lands on you | the `ritual_fell` line: "Bloodrot fell on Crownkeep (Thornmane Clans). Your fighters there can't heal, and it takes 12 hp from them at the end of every turn through turn 9, from your healthiest fighters, never below 1. Only fighters still in Crownkeep at the end of a turn are hit. To stop it: cast Sanctum Ward on Crownkeep (it bites once more, then ends), or move your armies out." Without Law: "Sanctum Ward (Law: 25 research to reach) would end it. Until then, move out or wait for turn 9." |
| an enchantment on the map | its decal and a badge "through turn 7"; hover gives the exact effect, who cast it, and when it ends |
| turn report | `ritual_cast`, `ritual_turned_aside`, `ritual_fell`, `summoned`, `fort_raised`, `blessing_healed`, `curse_bit`, `enchantment_ended`, `summon_faded`, `research_sold`, each with its codex link |

**The cast dialog** shows:
- **The target:** a ring on the board, with the provinces in range lit.
- **The price:** gold, or the soldiers who would bleed (§7.1).
- **The effect, with your numbers:**
  - "Bloodrot on Crownkeep: the fighters there (about 30 you can see) can't heal, and it takes 12 hp a turn from them, through turn 9. It first bites after this turn's battles."
  - Dawn Blessing adds "Blesses your army at Highcrag (24 fighters); armies arriving this turn aren't blessed."
  - Call the Pack adds a size picker (3 up to 3 + bonus) and "They form a new army at Fangridge, and can move from next turn."
  - Bastion adds "1 of 2 Bastion forts used."
- **The pin:** "Your army at Fangridge (24 fighters) holds this turn; this cancels its move to Thornvale."
- **The risk, from what you can see:**
  - "Ward seen on Crownkeep: this will be turned aside (7 gold lost)."
  - "No ward seen at the start of the turn; one cast this turn would still turn it aside."
  - "Out of sight: turned aside if warded."
  - For Far Sight: "A Crown caster there would block the reading, not the sight."
- **Gold after:** "Gold after your queued rituals and recruits: 5."

### 11.3 tooltips and breakdowns
Every number explains itself through `Breakdown`, with lines that sum to the total:
- "Mastery in Sun +2 = ability rank 2 (+1) + Celestial Host (+1)" / "Sunlance 6 = 4 + mastery 2"
- "Defense 13 = Spearmen 7 + Shield Wall 2 + Shield of Law 4 (the Adepts, this round)"
- "Sunlance on the Great Thornmane 5 = 6 − spell resistance 1 (ability rank 3)"
- "Ritual price 15 gold, or 15 hp from your Shamans' army (Tithe of Blood: 1 hp a gold)"
- "Research 11 → 5 gold (nothing left to research: 2 research a gold)"

### 11.4 codex entries (`RulesCodex`), all new terms
- **Fog:** `fog_of_war`, `sight`, `vision_clear` ("in clear sight"), `vision_glimpsed`, `vision_out_of_sight`, `estimates` ("about N" and its ranges, shared out by type), `last_seen` (ghosts, "never seen"), `scouts`, `intel` ("what you know"), `public_facts`, `view_odds` ("odds against what you can see").
- **Magic:**
  - general: `magic`, `school_sun`, `school_law`, `school_wild`, `school_blood`, `arcana` ("the Magic tab"), `caster`, `mage`, `trait_mage`, `mastery`, `spellbook`, `greater_working`
  - spell kinds: `spell_kind_bolt`, `spell_kind_hex`, `spell_kind_shield`, `spell_kind_heals_back`
  - rituals and their effects: `ritual`, `cast_order`, `pinned`, `turned_aside`, `enchantment`, `blessing`, `ward`, `curse`, `summoned`, `spell_resistance`, `bleed`
  - phases and selling: `phase_rituals`, `phase_enchantments`, `research_sold`
- **One per spell, ritual and mastery node:** `spell_<id>` for all 13, `node_<id>` for the 4 mastery nodes.
- **Creatures and the mandate:** `unit_thornwolves`, `unit_greenwrath`, `mandate_tithe_of_blood`.
- **Updated entries:**
  - turns and orders: `phase_order` (§9), `orders` (cast and spellbook orders), `research` (the Magic tab, research sold)
  - rulers: `ruler_ever_regent` (his spells), `ruler_thornmane_avatar` and `ruler_fang_chieftain` (their rituals)
  - battle: `battle_rounds` (the cast step), `battle_morale` (bleeding doesn't count), `trait_berserk` (a bolt that wounds turns it on)
  - map and healing: `fort` (Bastion), `healing` (cursed fighters heal from nothing)
  - mandates: `mandate_feast_of_victory` (excludes Tithe of Blood)
  - game: `hotseat` (fog), `victory` (the fog lifts)

### 11.5 the "nothing hidden that matters" check
Pillar 4 and fog pull against each other. The resolution is that every rule stays visible; only the rival's private state is hidden.
- Every hidden thing is named as hidden where it matters: forecasts list their assumptions and give a top-of-range figure, and panels say "they may have more".
- Randomness is still shown as odds, and spells never add any.

---

## 12. 3D: the vision mask and spell effects

### 12.1 the vision mask
- **`vision_tex`** is a 16 × 1 R8 texture beside `owner_tex`, one texel per province index.
  - It is rewritten whenever the viewer or the turn changes: 0 never seen, 85 remembered, 170 glimpsed, 255 in clear sight.
  - The ground shader looks it up with the province index it already reads from `data_image.r`. That is one fetch and one mix, which every rung carries, Compatibility included.
- **The look** follows bible §2.4's "unscouted (fog)":
  - **Out of sight:** terrain desaturated 70%, a cool veil at 40%, and 45° hatching. Terrain still reads from its geometry, and the owner wash stays, because owners are public.
  - **Never seen:** the same, plus a slow cloud drift, static from rung 3.
  - **Glimpsed:** a faint 10% veil.
  - **In clear sight:** untouched.
  - **Edges** are hard, on the keylined province border.
- **Armies:**
  - **Hidden armies are never instanced:** no node, no MultiMesh instance, no shadow, no plate, no sound.
  - **Stand-ins** draw as blocks from the shown counts, under an "≈20" plate.
  - **Remembered armies** are grey translucent ghosts in their own material, kept separate from ghost recruits, so M3a.2's ghost-recruit count stays exact. Their plate reads "≈10 · 3 turns ago", and they fade a step every 2 turns.
  - **A rival's fortress yard** shows its stand-in or ghost blocks, or stands empty under the veil.
- **The playback:**
  - It is built from `view_before(viewer)` and `turn_report_for(viewer)`, synthetic events included (§2.8).
  - A rival column marching out of sight walks to the border and fades.
  - **A ritual from a hidden caster has no travelling mote:** its beat starts at the target, so the board never shows the direction it came from.
  - `GameScreen` takes the turn's "before" from `view_before`, never `state()`.
- **Tests (M5-3, `tests/test_fog_board.gd`):**
  - the board's armies equal the view's, with no instance for a hidden army
  - the board model is byte-identical under `perturb_hidden`
  - the board model after playback equals `FogRules.apply_view_events`, beats included (3 games × 12 turns)
  - the static no-RNG check scans `test_board3d`'s `BOARD_FILES` list (`world3d/scenario.gd` is a tool and rolls dice)
- **Build-box checks:** the first frame after a handoff; `--perf` shows the veil costs ≤ 0.2 ms at rung 0, and it runs on rung 5.

### 12.2 spell and ritual effects on the quality ladder
| effect | rung 0-1 | rung 2 | rung 3 | rung 4-5 |
|---|---|---|---|---|
| bolt (Sunlance's gilt beam, Bloodbolt's crimson bolt) | code beam mesh, trail and glow; impact sheet | no glow | beam without trail; impact sheet | a straight line; impact sheet at half size |
| hex (Briar Snare) | vines from a decal ring at each target's feet, billboard briars, 32 particles | 16 particles | decal ring and one billboard each | decal ring only |
| hex on a rank (Sunburst) | a glare ring sweeping the enemy front, flare sheet, a 4 px shake within M3's limits | no bloom | ring and sheet | ring only |
| shield (Shield of Law) | a translucent shield quad per covered fighter (one MultiMesh), a rim pulse | same | quads, no pulse | a ▲ decal under each covered fighter |
| heals back | green numbers, rising motes (24 particles) | 12 | numbers only | numbers only |
| map: a ritual cast | a beam at a visible caster, a mote along the roads to the target, then the decal | same | no mote | decal only |
| map: enchantments | animated decals: a gilt ring under blessed armies, a blue band for a ward, crimson veins for a curse, an eye plate for Far Sight | static | static | static |
| map: summon, Bastion | a briar ring the creatures step out of; the fort rises behind scaffolding | same | fade in | pop in |

- **Budgets** (3D_DIRECTION §3.5): spells add at most 150 draw calls to a battle (the cap is 2,000) and at most 1.5 ms of GPU time at rung 0 on the recommended tier.
  - **Pools:** at most 32 spell effects alive. When the pool is full, a new effect is skipped, not queued.
  - **Shaders** are precompiled by the shader baker.
- **The flash limiter and reduced motion** (M3 §7.4) apply. Sunburst is a ring and a flare, never a white-out.
- **Identity in code:** effects are untinted; ownership comes from the decal's colour and the caster's ring.

### 12.3 the events the board reads
| event | phase | the board does |
|---|---|---|
| `ritual_cast` | rituals | the cast beat (caster, target, ritual, school, price) |
| `ritual_turned_aside` | rituals | a fizzle at the caster; the ward's band flashes at the target |
| `ritual_fell` | rituals (target side) | the effect arrives at the target, with no direction |
| `blood_paid` | rituals | red mist rising from the paying block |
| `summoned` | rituals | creatures step out of a briar ring |
| `fort_raised` | rituals | the fort rises |
| `enchantment_began` / `enchantment_ended` | rituals / enchantments | decals on and off |
| `blessing_healed`, `curse_bit` | enchantments | motes on the armies there |
| `summon_faded` | enchantments | the creatures dissolve into leaves |
| `far_sight_reading` | rituals | the eye opens over the rival capital (the caster's view only) |
| `sighting_changed`, `sighting_lost`, `memory_added` | synthetic, per viewer | blocks re-form, fade into the veil, or a ghost appears |
| battle log `cast` | battles (playback) | §12.2's battle effects |

---

## 13. balance intent

### 13.1 the shape we want
- **Each school is a style, not a ranking:**
  - **Sun:** sure damage that fells the biggest creature, and healing that marches.
  - **Law:** field shields, wards against magic, and two forward forts.
  - **The Wild:** control and disposable bodies.
  - **Blood:** finishing the weak, attrition that stops healing, and sustain.
- **Mages should be worth their price, not more.**
  - Sunlance's 4 sure damage, focused until a creature falls, is about a crossbowman's 4.4 against Tuskers and better against anything big, for 15 gold against 10.
  - Shield of Law blocks about 7 a round in the field. Briar Snare saves about 7 a round (9 in a forest). Bloodbolt deals 5 a round from a 16-gold body.
  - So a mage is roughly 1-1.5 crossbowmen at 1.6-1.8 times the price, and rituals pay back the gap.
  - M2's lesson holds: battles are steep (+8 gold on one side of an even 137-gold battle wins 71%). So these numbers are first-pass, and M5-11 measures them.
- **Rituals should move about 2-3 hp of value per gold over their life:**
  - Dawn Blessing (12): 36 hp per blessed army, plus +1 morale.
  - Bloodrot (15): 36 hp, plus no healing.
  - Call the Pack (5 a wolf): disposable Fangthrower-like fighters at 5 gold each.
  - Far Sight (6): the truth about one province, twice.
  - The greater workings (26-30): each worth about a transformation's province rule.
- **Magic must not break the fork.** M4's P1 and P2 must still hold. If a school makes one side of a fork dominant, the school is tuned, not the fork.
- **Magic should shorten stand-offs:**
  - Shield of Law never covers a unit with a terrain or fort bonus.
  - Blessings ride with armies.
  - Bloodrot stops healing, and Bastion stops at two forts.
  - No ritual makes a province harder to take except those two forts.
- **Fog should change decisions, not the fairness of outcomes.** Fog-on and fog-off games of the same cells should have similar lengths and faction splits.

### 13.2 autoplay bands (checked by M5-11)
- **Setup:** both seats run `AIPlayer`, with paths and magic on.
- **Main matrix:** every Crown side × Clans side (4) × all 9 preset pairings × both seat orders × 25 games = **1,800 games**, fog off.
- **Fog matrix:** the same cells × 10 = **720 games**, fog on. The AI is given only its view (§10.1).
- **No-fog control for G11:** the fog matrix's seeds rerun with fog off and `army_counters` on, so the only difference is what each seat sees.
- **Tithe pairs:** the 3 Clans presets × 3 Crown presets × both seat orders × 20 seeds, run twice = **720 games**.
  - One run gives the Clans preset Tithe of Blood; the other gives it a test-only 3-cost mandate that does nothing, so kept power is the same.
  - A scripted human-style Tithe build that bleeds to the floor runs in the same harness.
- **Control:** #71's 1,800-game path matrix (magic off) on the same seeds.
- **Decisive** means finished and not a draw. A branch pairing with fewer than 120 decisive games doubles its games. Expect about 1.3× M4's runtime per game.

| band | what | target |
|---|---|---|
| G1. both schools used | per faction, each school researched to tier I in **40%+** of games reaching turn 10, and its spells or rituals used in **25%+** of games | each school |
| G2. no dominant spell | no spell or ritual is the top "why" factor in more than **25%** of battles; no ritual is more than **50%** of its faction's rituals | none over |
| G3. magic matters (report) | share of battles with a caster whose "why" names a spell (target 30-60%); win rate of the side with the larger spell worth | reported |
| G4. the fork still holds | M4's P1 (each side 40-60%, Bradley-Terry) and P2 (no side above 65%), with magic on | as M4 |
| G5. length | median decisive game **12-25** turns; at most **15%** at the 60-turn cap (M4: 21%) | both |
| G6. transformations still happen | median transformation turn **8-12**; both transformed by turn 15 in **80%+** of games reaching it | both |
| G7. rituals happen | a ritual cast by turn 10 in **80%+** of games reaching turn 10; every ritual cast in **10%+** of the games where its faction knows it | both |
| G8. mages bought | mages are **4-20%** of each faction's regular recruits | each faction |
| G9. Tithe of Blood | in the Tithe pairs, the Clans' win rate with Tithe within **±5 points** of the null-mandate run; the scripted build reported | within |
| G10. the Regent | Regent's Court wins at most **60%** of its decisive games, and its share of capped games is no higher than the other Crown presets' | both |
| G11. fog | fog matrix against its no-fog control: median length within **±3 turns**; **successful** Far Sights cast in **30%+** of fog games reaching turn 8; Crown / Clans 40-60% (report); how often the winner changed (report) | the bands |
| G12. earlier games unbroken | M1, M2 and M4 records replay byte-identically, and the AI's rerun orders match, with magic and fog off; with magic on, M2's band F (a sacrifice in 15-50% of games) holds | all |
| G13. integrity | 0 invariant violations (gold counts ritual prices, half prices and research sold; hp counts blood paid, curses, blessings, bleeding and healing back; summons fade and enchantments end on their turn); 0 session or script errors; replaying every 10th game is identical; 0 ritual forecast mismatches for targets in clear sight with nothing turned aside; on every 10th turn of every fog game, §2.7's snapshot test passes, AI orders included | 0 |
| G14. ritual value (report, with a target) | each ritual's hp moved (healed or drained) per gold over its life, in the main matrix; target **1-4**, misses go to tuning | reported |

Exit code 0 only when G12 and G13 hold. Bots aren't humans, and they ward reactively where humans ward ahead. The bands prove nothing is broken or dominant for the bots; Alex's playtest is the real check.

### 13.3 tuning knobs
M5-11 may change these without asking, recording before → after in its PR and updating this file's tables (that ticket authorises the edit):
- **Spells:** Sunlance 3-5; Bloodbolt 4-6, bleeding 1-3; Shield of Law and Briar Snare counts 4-8 (forest +1 to +3); spell resistance on or off. Parts stay −2 and +4 (breakpoint values). Sunburst stays −2 on round 1.
- **Rituals:**
  - prices ±30% (wolves 4-6 each); durations ±1 turn
  - Dawn Blessing and Bloodrot budgets 8-16 (per bonus 2-6)
  - Blood Moon's share from a third to a fifth (rounded down)
  - Thornwolves through T + 3 to T + 5
  - the Greenwrath's hp ±6 and attack in steps of 2
  - Bastion's cap 1-3
  - the turned-aside share from a third to all
- **The Regent:** his Sunlance base 3-4; Mending Light ±1 per rank (an M2 knob, used here only in magic games).
- **Mages:** cost ±3, hp ±2, morale ±1. The mastery cap +2 or +3.
- **Arcana costs** ±20% (I 8-12, II 12-18, mastery 16-24, III 20-30); research sold at 2-3 research a gold.
- **Tithe of Blood:** 1-2 hp a gold; cost ±1.
- **AI:** `RITUAL_SHARE` 0.3-0.5; the mage ratio from 1 in 4 to 1 in 8; `MEMORY_TRUST` 2-4.
- **Not knobs:** sight ranges, the rounding rule, what is public, and making Tithe of Blood shared. These are fairness or identity rules, so they go to Alex.

Anything else, or a band that can't be met within these knobs, goes back to the director as a question for Alex.

---

## 14. engine changes at a glance (for builders)
**Data** (const dictionaries only, in `data/factions.gd` style):
- `data/fog.gd` (`FogData`):
  - `SIGHT`: owned province 1, army 1; fort, commander, ruler and scout types 2
  - `ESTIMATE`: §2.4's steps
  - `AUDIENCE`: per event type (§2.8)
  - `TEXT`: rebuilt-event templates
  - `SAFE_NUMBERS`, per event type. A rebuilt event carries these numbers and nothing else:

    | event | safe numbers |
    |---|---|
    | `captured` | income, is_capital |
    | `vassal_joined` | income |
    | `vassal_contested` | income |
    | `ruler_died` | ruler, kind, name, generation, kept_power, successor_turn, successor_power |
    | `ruler_arrived` | ruler, kind, name, generation, kept_power, max_hp, attack, defense, ability_rank |
    | `succession_waiting` | successor_turn, successor_power, successor_generation |
    | `oath_sworn` | node, branch, closed, turn |
    | `transformed` | node, branch, renamed, new_unit, province_rule, opens_mandate, forswears, turn |
    | `wild_spread` | province, from_terrain, terrain |
    | `fort_raised` | province |
    | `ritual_cast` (global) | ritual, until_turn |
    | `ritual_fell` | ritual, faction, until_turn, budget |
    | a rebuilt move | faction, from, to, total (round_count), types |

    **Never carried:** `units_changed`, `hp_total`, `own_text`, research ETAs, gold, true army ids.
- `data/magic.gd` (`MagicData`):
  - schools and spells: `SCHOOLS`, `FACTION_SCHOOLS`, `SPELLS` (13 rows), `SPELLBOOK`, `MASTERY_NODES`
  - units and casters: `MAGES`, `SUMMONS`, `RULER_MAGIC`
  - mastery: `MASTERY` (sources, the per-school table and the +3 cap)
  - constants: `RULER_RESIST` (rank ÷ 2), `RESEARCH_SOLD` (2), `TURNED_ASIDE` (½), `BASTION_CAP` (2)
- `data/mandates.gd`: `MAGIC_MANDATES` (Tithe of Blood, with `excludes: "feast_of_victory"`).
- `data/build_presets.gd`: `ai_arcana`.

**State** (every key serialized only when set; all fields added by M5-0):
- `GameState`: `fog`, `magic`, `enchantments`, `army_counters` (saved whenever non-empty), `is_view` (views only)
- `Faction`: `spellbook`, `enchant_counter`, `bastions`
- `UnitType.summoned`
- `Unit.until` (summoned units only)
- `Army.seen` (views only)

**Pure rules:**
- `rules/fog_rules.gd` (`FogRules`, with `OBSERVER`):
  - sight: `has_fog`, `sight`, `sources`
  - estimates: `round_count` (computed ranges), `sighting` (rounded total, shared out)
  - views: `view_state` (allow-list, stand-in shape, view ids, relaxed checks)
  - knowledge: `remember`, `learn`
  - reports: `report_for(events, viewer, before, after, memory, intel)`, `apply_view_events`
- `rules/magic_rules.gd` (`MagicRules`):
  - casters and spells: `has_magic`, `schools`, `known_spells`, `spellbook`, `casters`, `mastery_bonus` (per school, with parts)
  - orders and prices: `pinned_armies`, `check_cast` (with the running budget), `ritual_targets`, `price`, `blood_plan`
  - healing and sight: `can_heal`, `vision_grants`
  - ritual effects (M5-6): `ritual_effect` (one pure function used by both the rituals phase and the forecast), `forecast_ritual`, `place_summon`, `enchantment_step`
  - text functions and `validate`
- `rules/cast_order.gd` (`CastOrder`) and `rules/spellbook_order.gd` (`SpellbookOrder`), with `OrderBook` support (the pinned set, the running budget).
- `AscensionRules`: the arcana lookup hook, distinct kinds, `arcana_ids`, `all_complete`, research sold; `_heal_plan` skips cursed fighters.
- `RulerRules`: `ruler_alive` (new); `unit_max_hp` skips summoned units; `heal_ruler` and `apply_mending_light` skip cursed fighters; `sacrifice_check` honours `excludes`.
- `GameState`: `from_dict` loads `MagicData.SUMMONS` types in a magic game; `validate` relaxes §2.7's four checks for views; `new_army_id` uses `army_counters`; `setup_army_counters`.

**Resolver** (`TurnResolver`):
- `MAGIC_PHASES`, gated in `resolve()`
- spellbook and cast orders first in orders; `_rituals_phase`, `_enchantments_phase`
- `check_recruit`'s mage gate
- `price_recruits`' reserved gold

**Battle** (`AutoBattleResolver`):
- the Mage trait (tier 1, `TRAIT_TEXT`, `TRAIT_SHORT`, the guarded second-rank branch)
- the cast step (highest bonus, ruler first, fighter id), spell parts
- bolts with pending-aware targets and spell resistance; the bleed, excluded from the break check and closed after the battle
- Blood Moon in `_drink` (the larger share, rounded down, max − 1, wards outside)
- blessing morale in `_morale` (counted at the battle's start)
- Feast and healing back skip cursed fighters (`MagicRules.can_heal`)
- the factors, with the hex credit inverted
- report `casters` and `spells_cast` in magic games only

**Log and helpers:**
- `BattleLog`: `cast`, the `"magic"` additions, `validate`, `cross_check`
- `BattleTimeline`: cast damage, statuses
- `BattleCaptions`: the "greater" and "first spell" rules, phrases
- `BattleMoments`: `spell`
- `BattleExplain`: caster, skip, target and resistance lines

**Forecast:**
- the view note in every forecast's text, two odds against sightings, "no odds" out of sight, sight in `move` (M5-2)
- gold after queued rituals, spells assumed (M5-8)
- battle odds name the spells each side will cast, through `AutoBattleResolver.estimate`'s reasons (M5-7)

**Session:** `GameSession.state_for`, `view_state`, `view_before`, `turn_report_for`, `memory` and `intel`, kept per resolved turn and rebuilt in `from_record`; `MAGIC_REPORT_PHASES`.

**Save:** no new keys beyond the state above. The header stays fog-safe.

**Tools:**
- `tools/replay_fixture.gd` records M4 games (`with_paths`, `configure`)
- `Simulator`: `--magic`, `--fog`, `--tithe`; fog games pass views to the policies; magic invariants
- `tools/battle_log/scenarios.gd` gains scripted magic battles

---

## 15. art

### 15.1 what M5 asks for
Prices come from the ledger and bible §8.10: a base picture with 3 candidates costs 1.5, a model 3.0, and a pose picture 0.5. So a 4-pose figure costs 1.5 + 3.0 + 3 × 3.5 = **15.0**.

| piece | kind | poses | how | cr |
|---|---|---|---|---|
| Sunstone Adepts | Crown mage figure | ready, march, **cast**, fallen | C-model, anchored to the Crown's Spearmen pick (white linen, royal blue, gold, a sunstone staff) | 15.0 |
| Thornmane Shamans | Clans mage figure | ready, march, cast, fallen | C-model, anchored to the Tuskers pick (bone, moss, a briar-and-skull staff, crimson paint) | 15.0 |
| Thornwolves | Clans summon (beast) | ready, run, strike, fallen | C-model four-legged, anchored to the War Bear pick (briar-grown wolves) | 15.0 |
| Greenwrath | Clans summon (large) | ready, march, strike, fallen | C-model large, anchored to the Briarwardens' style (a walking thicket with a stag skull) | 15.0 |
| the Ever-Regent's cast pose | ruler pose | cast | already in each faction's ruler budget (3D_DIRECTION §9.5: 5 poses for rulers); listed in case the M3a.2 batch made "cheer" instead | 3.5 |
| portraits | 4 (Adepts, Shamans, Thornwolves, Greenwrath) | – | C-portrait, 2D | 6.0 |
| spell icons | 13 spells and rituals, plus Tithe of Blood | – | C-spell (bible §4.1: spell icon M5, 1.5 each) | 21.0 |
| VFX sheets | `sun_flare` (impact), `briar_burst` (impact), `blood_spray` (impact), `cast_channel` (cast loop), `summon_ring` (cast loop) | – | bible §4.2, C-vfx, 5.5 each | 27.5 |

- **The leak rule:** Crown pieces anchor only to Crown picks, and Clans pieces only to Clans picks (bible §3 rule 3).
- **The 24 px silhouette gate** (bible §8.9):
  - a mage reads as a caster, with the staff overhead in the cast pose
  - wolves read as quadrupeds, wider than they are tall
  - the Greenwrath stands taller than a War Bear
- **The lore room** may rename the mages and creatures and change their look before the art lead writes the rows. Pictures wait for its call on the two factions' looks (3D_DIRECTION §11).

### 15.2 credits
| phase | what | planned | with re-roll reserve (×1.5) |
|---|---|---|---|
| 1 | 4 figures (60.0) + the Regent's cast pose (3.5) + 4 portraits (6.0) | 69.5 | 104.3 |
| 2 | 14 icons (21.0) + 5 VFX sheets (27.5) | 48.5 | 72.8 |
| **total** | | **118.0** | **177.0** |

**Budget: 180 Ludo credits.** The asset builder flags the director above 177.

The cheaper option is phase 1 only (104 with reserve). Icons would then stay code glyphs and effects code-only, both of which exist as placeholders (§15.3).

### 15.3 placeholders (the milestone never waits for art)
- **Figures:** `Kit` primitives.
  - A mage is a robed figure with a staff (`Kit.figure("mage")`).
  - Wolves are a low four-legged block.
  - The Greenwrath is a tall thicket of stacked cylinders.
  - Each has a row in `world3d/models.json` with `"model": ""` and a fallback, so the GLBs drop in without code changes.
- **Portraits:** M3's placeholder card with a new class glyph (`mage` and `beast`) in player colour, plus the emblem.
- **Icons:** a code-drawn school glyph (sun disc, law square, thorn, blood drop) as free SVGs, with a kind mark.
- **VFX:** code only: beams, decal rings, GPU particles in flat cel colours, and the M3 code star.
- **Fog:** all code. No art is needed.

---

## 16. interactions with forts and sieges (M3c, designed in parallel)
M3c (`design/M3C_SIEGES.md`) isn't written yet. M5 assumes forts will matter, and keeps these seams open:
- **Bastion raises a fort,** at most 2 ever per faction.
  - If M3c adds fort levels or walls, Bastion builds the lowest level at once. Whichever ticket lands second adapts the effect.
  - Living Iron's Forges and Forge Tithe count a Bastion fort like any other.
- **Bloodrot on a besieged fort** stops the garrison healing and wears it down, on top of the siege. M3c may want a curse to stop walls being repaired too; that is M3c's call.
- **Neither ward nor shield stacks with walls.** Shield of Law never covers a unit that has a fort bonus, and Sanctum Ward adds no defense. Under a siege, a ward still turns rituals and Far Sight aside.
- **Far Sight on a fort** shows its garrison exactly. Under fog, a fort's towers see 2 provinces, so a fort is also a watchtower.
- **Phase order:** M3c's sieges phase comes after battles. Rituals come before movement, so a Bastion fort exists for that turn's battles and sieges. A curse cast this turn bites at the end of the turn, after the siege.
- **No M5 spell damages walls.** Magic against walls, if Alex wants it, is a later `raising`-kind effect.

---

## 17. out of scope for M5
- **Seasons** (3D_DIRECTION §10.4): deferred. They are a rule of their own, with their own forecasts and grades, and M5 is already two systems. This is a question for Alex (§20).
- **More magic:** a third school per faction, dispelling or counterspell duels, picking spells by hand inside a battle, magic items, mages for independents, magic sites or gems, ley sites, a Crown global ritual, a Clans ward. The veteran's flavour ideas are kept for the lore room.
- **Mages as commanders,** mages leading armies, and mage transformations with new art.
- **Fog beyond two factions and one screen:** fog for battles you didn't fight (that needs M6's third faction), naval fog, encrypted or per-player saves, an ironman option, online play.
- **AI:** difficulty levels for fog or magic, counter-scouting, reacting to the rival's research, setting its own spellbook.
- **Movement magic** (teleports, flying armies), magic against walls, weather magic.
- **Issue #25's open questions and #94's stand-off rule.** M5 doesn't decide them, and nothing here depends on their answers.

---

## 18. tickets
Github issues are to be cut once Alex has seen this. M5-n are placeholders, and every ticket is labelled `milestone:5`. Every code ticket follows `CLAUDE.md`:
- pure rules code
- tests under `tests/`, with expected numbers derived from data, not hardcoded
- `tools/compile_check.gd` passes
- in-game explanation in the same PR
- a `playtest:` line in the PR

**Parallel lanes and file ownership:**

```
             M5-0 (scaffold, about a day)
               │
fog lane     M5-1 ──┬── M5-2 (ui/, forecast fog text)
               │    ├── M5-3 (world3d/: fog) ──────────────────────┐
               │    └── M5-4 (ai/: seat, fog) ──────────────────┐  │
magic lane   M5-5 ──┬── M5-6 (rituals) ──┬── M5-8 (ui/: magic)  │  │
                    └── M5-7 (battle) ───┼── M5-9 (3D effects) ─┼──┘
                                         └── M5-10 (ai/: magic) ┴── M5-11 (balance)
art          M5-12 (now) ── M5-13
```

**M5-0 goes first.** It is a small scaffold that removes the shared-file collisions:
- **The fixture:** it extends `tools/replay_fixture.gd` to record M4 games, and records `tests/fixtures/m5_base_records.json`.
- **Every new serialized field** (§14), each saved only when set, with round-trip tests.
- **Stubs:** `MagicRules.vision_grants`, which returns [], and `RulerRules.ruler_alive`.

**Then M5-1 and M5-5 start the same day.** Fog and magic share no rules file after that, except:
- `GameSession`: M5-1 adds the view accessors, and M5-5 adds `MAGIC_REPORT_PHASES`. Whichever merges second rebases.
- `ruler_rules.gd`: M5-1 adds view handling in `ruler_alive` and its callers; M5-5 adds the summoned skip in `unit_max_hp` and `excludes` in `sacrifice_check`. They touch different functions, and the second to merge rebases.
- The new game screen: M5-1 adds the fog box, M5-5 the magic box. Expect a small merge.

**After M5-1, these run together:**
- **M5-2** owns `ui/`: `game_screen.gd`, `map_screen.gd`, `ui/battle/battle_host.gd`'s state read, `GameAudio.report`'s input, the handoff rebuild and kept-frame clearing, and fog sound. It also owns `rules/forecast.gd`'s fog text.
- **M5-3** owns `world3d/`.
- **M5-4** owns `ai/ai_seat.gd` and `ai/ai_fog.gd`.

**After M5-5, these run together:**
- **M5-6** owns `turn_resolver.gd` and the ritual half of `magic_rules.gd`. It also owns the heal skips in `ruler_rules.gd` (`heal_ruler`, `apply_mending_light`) and `ascension_rules.gd` (`_heal_plan`), and `simulator.gd`'s invariants.
- **M5-7** owns `auto_battle_resolver.gd` (including the Feast skip), `battle_log.gd`, `battle_timeline.gd`, `battle_captions.gd`, `battle_moments.gd`, `battle_explain.gd` and `tools/battle_log/scenarios.gd`.
- `MagicRules.can_heal` is M5-5's, so both can call it.

**Later tickets:**
- **M5-8** needs M5-6. It creates `ui/magic_tab.gd`, `ui/cast_dialog.gd` and `ui/enchantment_badges.gd`, and adds hooks in `ui/research_panel.gd`, `ui/orders_controller.gd` and the army panel. It owns the magic lines in `rules/forecast.gd`: gold after queued rituals, and spells assumed. Its few lines in M5-2's files are rebased.
- **M5-9** needs M5-3, M5-6 and M5-7. It creates `world3d/spell_fx.gd`, `world3d/enchant_decals.gd` and `ui/battle/battle_spell_fx.gd`, plus one hook line each in `board3d.gd`, `playback.gd` and the battle player.
- **M5-10** needs M5-6 and M5-7, and M5-4 for Far Sight. It owns `ai/ai_magic.gd` and its calls from `ai_player.gd`. M5-4's changes there are in other functions.
- **M5-11** needs M5-4, M5-6, M5-7 and M5-10, and closes the milestone. It owns `Simulator`'s flags and matrix.
- **M5-12** can start now. **M5-13** follows it.

**`RulesCodex`:** each ticket appends its own block under a heading comment.

**M5-0 `code` Scaffold** (needs M4 on `main`)
- *Scope:*
  - `tools/replay_fixture.gd` records M4 games
  - the fixture `tests/fixtures/m5_base_records.json`, with M1, M2 and M4 records and their AI policy runs
  - every §14 state field, with gated serialization and validation
  - the stubs `MagicRules.vision_grants` and `RulerRules.ruler_alive`
- *Acceptance (`tests/test_m5_fields.gd`):*
  - each field round-trips through `to_dict`, `from_dict` and JSON
  - a state without the fields saves byte-identically to `main`
  - the fixture replays on `main`
- *playtest:* none. Nothing a player sees changes.

**M5-1 `code` `hard` Fog rules model** (needs 0)
- *Scope:*
  - `data/fog.gd`
  - `rules/fog_rules.gd`: sight, `round_count` and sightings, memory, intel, the view state, `report_for` with templates and `SAFE_NUMBERS`, `apply_view_events`
  - `setup_fog`, `setup_army_counters` and the **Fog of war (M5 preview)** box
  - `ruler_alive` in views, and its callers in `rules/`
  - `GameSession`'s per-viewer accessors
  - `tests/fog_test_kit.gd`: `perturb_hidden` with its renaming map, and the two-turn generator
  - the fog codex entries
- *Acceptance:*
  - `tests/test_fog_rules.gd`:
    - sight levels and sources on constructed boards, and §2.3's start (counts by BFS from `MapData`)
    - `round_count` for every n from 0 to 200, with its ranges computed and checked against brute force
    - the sharing out: sums to the shown total, everyone present ≥ 1, ties in roster order
    - stand-ins have the fixed shape
  - `tests/test_fog_view.gd`:
    - the snapshot, report, two-turn and three-turn tests (§2.7) on 20 seeded games for both viewers
    - one case for each relaxed check
    - the serialized view holds no true rival id, gold, research, unknown mandate or enchantment counter
    - `view.deep_copy()` round-trips
    - `Forecast.*`, `with_sacrifice`, `check_order`, `plan_orders` and `_scratch_with` all run on views
  - `tests/test_fog_report.gd`:
    - every event type follows the audience table
    - a rebuilt event holds only `SAFE_NUMBERS`, and its text comes from `FogData.TEXT`
    - for each viewer, `apply_view_events(view_before, filtered events)` equals `view_after`
  - `tests/test_fog_orders.gd`: the same check results on the true state and on the view (20 games)
  - `tests/test_fog_save.gd`:
    - memory and intel are rebuilt identically after load
    - a record replayed with `fog` stripped and `army_counters` kept gives the same states
  - `tests/test_fog_off.gd`: with fog off, M1, M2 and M4 records replay byte-identically, and the AI's rerun orders match
- *playtest:* start a fog game, and from the tooltips alone say what you can see of the Clans, and why.

**M5-2 `code` Fog on screen** (needs 1)
- *Scope:*
  - every UI read through the per-viewer accessors: map, panels, tooltips, top bar, battle host, audio, and the rival ruler and research panels ("alive, location unknown")
  - the per-viewer turn report and its header line; "what you didn't see"; Watch for participants only
  - the handoff: rebuild under the cover, clear the kept frame, take the turn's "before" from `view_before`
  - in hotseat fog games, the playback is muted apart from the ambient bed
  - the Vision map mode and the legend rows
  - scout lines
  - forecasts' fog text: the short line, two odds, ⓘ, "no odds" out of sight, sight in `move`
  - the computer's notes hidden under fog; the victory screen's "fog lifts"
- *Acceptance:*
  - `tests/test_fog_ui.gd` (headless, M1 style): province tooltips show memory and sources; a glimpsed army shows its ranges and last turn; every number has a breakdown; the rebuild runs under the cover
  - a static scan finds no truth accessor in `ui/` outside the observer paths
  - forecast equals result under §2.10's conditions (20 games)
  - in hotseat, seat 2's panels are identical under `perturb_hidden` of seat 1's private facts
  - the computer's notes stay hidden until game over
- *playtest:* play a hotseat fog game for 6 turns, and check that nothing on your screen tells you anything about the other seat that the fog says it shouldn't.

**M5-3 `code` Fog on the 3D board** (needs 1)
- *Scope:*
  - `vision_tex`, and the ground shader's veil, hatching and clouds
  - armies from the view: stand-in blocks, "≈" plates, memory ghosts in their own material, rival yards
  - per-viewer playback from the filtered events; rituals from hidden casters start at the target
  - sound only for visible things
- *Acceptance:*
  - `tests/test_fog_board.gd`, as in §12.1
  - build-box checks: the first frame after a handoff, and `--perf`
- *playtest:* on the 3D board, can you tell at a glance which provinces you see exactly, roughly and not at all, and how old each ghost is?

**M5-4 `code` AI under fog** (needs 1)
- *Scope:*
  - `AISeat` passes the view in fog games: `_init`, `take_turn`, and `report_notes` through `turn_report_for`
  - `ai/ai_fog.gd`: stale ghosts, scouting, the capital check against the top of each total
  - #94's stand-off rule on the view, if #94 has landed
- *Acceptance (`tests/test_ai_fog.gd`):*
  - the four tests in §10.1
  - with fog off, AI games are identical to `main`
- *playtest:* play a fog game against the computer. Does it scout, and does it ever react to something it couldn't have seen?

**M5-5 `code` `hard` Magic rules model** (needs 0)
- *Scope:*
  - `data/magic.gd` and `MAGIC_MANDATES`
  - `magic_rules.gd`, first half: schools, spellbooks, casters, mastery per school, `pinned_armies`, `check_cast`, the running budget, prices, blood plans, `can_heal`, `vision_grants`, validation
  - the arcana through `AscensionRules`: distinct kinds, mastery nodes, and research sold with its event in `_research_phase`
  - the static mage roster, and the recruit gate
  - summoned types: loaded, and skipped by `unit_max_hp`, `arrival_hp` and `_unit_mods`
  - Tithe of Blood excluding Feast of Victory
  - `with_magic`, `setup_magic` and the **Magic (M5 preview)** box
  - `CastOrder` and `SpellbookOrder` in `OrderBook`
  - `Breakdown` lines, and the magic codex entries
- *Acceptance:*
  - `tests/test_magic_rules.gd`:
    - a table of cast legality, each case with its plain reason: range, target rule, knowledge, caster, pin, one per army, once per faction, budget, blood
    - mastery for every caster, at every ability rank, per school, with the cap
    - §7.1's blood plan, exactly
    - a queued cast drops its army's move, whatever the order the two were given in
    - recruits and rituals share the budget
    - Tithe of Blood and Feast of Victory exclude each other
  - `tests/test_arcana.gd`:
    - node legality
    - ETA equals completion
    - the mage gate opens on the first spell
    - research is sold only when nothing is left, and only in magic games
  - a wolf and the Greenwrath round-trip, and Veteran Levies and Blood Levy leave them alone
  - a recorded magic game replays identically
  - `tests/test_magic_off.gd`: byte-identical replays, and matching AI reruns, with magic off
- *playtest:* start a magic game, research a spell, recruit two mages, set the spellbook, and read the cards and the order checks without casting anything.

**M5-6 `code` `hard` Rituals on the map** (needs 5)
- *Scope:*
  - `MAGIC_PHASES`; spellbook and cast orders in the orders phase; `_rituals_phase`; `_enchantments_phase`
  - `ritual_effect`, `forecast_ritual`, `place_summon`
  - every ritual in §6.2: budgets, summons in their own armies and the pack size, Bastion's cap (`Faction.bastions`), the Blood Moon enchantment, Far Sight with its reading and the caster block
  - turned aside at half price
  - Tithe of Blood payments
  - the heal skips in `ruler_rules.gd` and `ascension_rules.gd`
  - the report events; the `Simulator` invariants
- *Acceptance:*
  - `tests/test_rituals.gd`:
    - every ritual's effect and its "through turn" arithmetic
    - budgets taken and given one hp at a time, in the stated order
    - a same-turn ward turns a curse and a Far Sight aside at half price
    - a ward ends an existing curse after one more bite
    - a caster blocks a reading but not the sight
    - one pack and one Greenwrath at a time; Bastion's cap counts forts ever raised
    - summons hold on their arrival turn and fade on time; empty armies are removed
    - blessings follow armies and recruits
    - cursed fighters heal from nothing in the rulers and research phases
    - every ritual forecast equals its result when nothing is turned aside
  - `tests/test_tithe_of_blood.gd`: one soldier at a time; never below 1; only the caster's army; never a ruler; half when turned aside; illegal when short
  - a replay through every ritual is identical
- *playtest:* as the Clans with Tithe of Blood, curse the Crown's capital and call the pack, then check every forecast against the turn report.

**M5-7 `code` `hard` Battle spells** (needs 5; parallel with 6)
- *Scope:*
  - the Mage trait and the guarded branch
  - the cast step: highest bonus, ruler first, fighter id, spreading out, the spellbook
  - the five spells and the Regent's Sunlance: targeting, spell resistance, the bleed (excluded from the break check, closed after the battle), Shield of Law's field rule
  - blessing morale at the battle's start; Blood Moon (read from `state.enchantments`)
  - Feast and healing back skip cursed fighters
  - the factors (hex credit inverted) and the magic-only report fields
  - the log's `cast` event and additions; validate and cross-check; timeline statuses
  - the captions' "greater" and "first spell" rules and phrases; the `spell` moment; `BattleExplain`'s lines
  - scripted scenarios
- *Acceptance:*
  - `tests/test_battle_spells.gd` (fixed seeds pin each spell):
    - the spreading rule and spellbook order, on and off, including the Regent's locked row
    - Sunlance focuses on the highest maximum hp, most hurt first, and reaches rulers last; Bloodbolt finishes the weakest; neither overkills
    - spell resistance by rank
    - Shield of Law never covers a unit with a terrain or fort bonus, and every covered defense is 4k or 4k+1
    - Briar Snare's forest count
    - the bleed: never below 1, not counted in the break check, closed after the battle
    - Blood Moon: the larger share, rounded down, max − 1, wards outside
    - mastery scaling
    - a caster that casts doesn't attack, and a mage that attacks isn't counted as Volley
  - a battle with no caster draws exactly what it drew before
  - a constructed battle names each spell as its top "why"
  - `Forecast.battle_odds` changes when a spell is researched
  - `tests/test_spell_log.gd`: `validate`, `verify_draws` and `cross_check` pass on the scripted scenarios; playback never changes the outcome (M3's three levels)
  - `tests/test_spell_captions.gd`: §5.4's Briar Snare caption exactly; every spell captioned at least once; every factor has a phrase and a codex entry
  - with magic off, every M1-M4 battle and report is unchanged
- *playtest:* fight the same battle with and without two Shamans, watch both, and say from the captions and the why panel what the spells did.

**M5-8 `code` Magic on screen** (needs 5, 6; best after 7)
- *Scope:*
  - the Magic tab: cards with "delays", Shield of Law's field line, mastery nodes per caster, and the Battle spellbook with its per-army preview
  - the HUD chip; the lock-in preview's magic row
  - mage cards with spellbooks and the exposure warning; the army panel's per-spell line
  - the cast dialog (§11.2): forecast, size picker, risk by sight, budget line
  - enchantment badges, and `ritual_fell`'s answer line
  - the turn report rows
  - the build screen's Tithe of Blood row and the ruler cards' live lines
  - the first-spell text
  - `forecast.gd`'s magic lines
- *Acceptance (`tests/test_magic_ui.gd`, headless, M1 style):*
  - every number has a breakdown equal to `MagicRules`, `Forecast` or `Breakdown`
  - the dialog offers only legal targets, and its forecast equals `forecast_ritual`
  - the preview equals the result for a cast
  - the spellbook preview equals the resolver's casts on scripted battles
  - tier III and closed cards show their reasons
  - every term on screen has a codex entry
- *playtest:* without the codex, order each ritual once and say what it will do, and set a spellbook and say what your casters will cast. Then check the turn report and the battle.

**M5-9 `code` Magic in 3D** (needs 3, 6, 7; placeholders first)
- *Scope:*
  - the map's ritual beats, decals, summons and Bastion's rise (§12.2, §12.3)
  - the battle stage's spell effects on the quality ladder
  - pools, the flash limiter and reduced motion
  - the legend rows; model-table rows for the four new figures
- *Acceptance:*
  - `tests/test_spell_fx.gd`:
    - every event and every `cast` kind has a beat at every rung
    - effects never change the state
    - no RNG in the new files
    - a full pool skips
    - the flash limiter counts Sunburst
  - build-box check: `--perf` on a 280-fighter battle with 6 casters stays within budget
- *playtest:* watch a battle with every spell at rung 0 and at rung 3. Can you name each spell from its effect and the caption?

**M5-10 `code` AI with magic** (needs 6, 7; Far Sight after 4)
- *Scope:*
  - `ai_arcana` and research orders
  - mage values and the mage ratio
  - the ritual rules (§10.2), including warding ahead
  - `RITUAL_SHARE`; pins only armies that hold
  - Bastion's cap; the pack size; Tithe of Blood payments and the sacrifice pick
- *Acceptance (`tests/test_ai_magic.gd`):*
  - 30 turns of human against AI with magic gives zero rejections
  - the same seed gives the same research, rituals and orders
  - every ritual rule fires on a constructed board, warding ahead included
  - it never pins an army ordered to attack
  - with magic off, games are identical to `main`
- *playtest:* play a magic game against each faction's computer. Does it research, recruit mages and cast rituals that make sense?

**M5-11 `code` Autoplay balance check for magic and fog** (needs 4, 6, 7, 10)
- *Scope:*
  - `Simulator`: `--magic`, `--fog` (views to the policies) and `--tithe`; `autoplay.gd` and `--matrix`
  - the matrices in §13.2, including the no-fog control and the Tithe pairs with the null mandate
  - report sections for every band
  - the pass/miss table, with exit code 0 only when G12 and G13 hold
  - tuning within §13.3
- *Acceptance:*
  - the report is attached to the PR, with every number change before → after and this file's tables updated
  - any band still missed is listed with why and its diagnostic, as #71 did
- *playtest:* read the bands table. Are both schools used, does any spell dominate, is Tithe of Blood fair, is the Regent held, and do fewer games stall?

**M5-12 `design` Art lead: M5 manifest rows** (no code dependencies)
- *Scope:*
  - `design/ASSET_MANIFEST.md` rows for §15.1: literal prompts, anchors, gates, candidates, status `spec`
  - the `mage` and `beast` class glyphs, and the four school glyphs
  - the C-pose line for "cast"
- *Acceptance:*
  - every row has its full set of fields
  - the rows add up to §15.2
  - bible changes bump `v`
- *playtest:* none. The art lead checks the rows against §15.1 and the lore room's looks.

**M5-13 `asset` Asset builder: M5 batch** (needs 12, and the lore room's looks for the two factions)
- *Scope:*
  - phase 1: 4 figures (16 models), the Regent's cast pose if it's missing, and 4 portraits
  - phase 2: 14 icons and 5 VFX sheets
  - the bible's gates, a contact sheet, and the ledger
- *Acceptance:*
  - the gates pass
  - every figure shows on the board and the battle stage through its model-table row
  - the ledger stays within budget (flag above 177)
- *Budget:* 180 Ludo credits.
- *playtest:* at 24 px on the board, can you tell a mage from a soldier, and a wolf from a bear?

---

## 19. director's calls (review these first)
1. **Fog is a lens, not a rule.** The resolver never reads the fog flag. Fog changes only what each player is shown and what the computer is given. That makes it testable and keeps online play possible.
   - Fog games also number each faction's armies separately, so your own ids can't count your rival's.
   - That is a small rule change: fighter order shifts, so battles with the same seed differ from a game without it.
2. **Owners, terrain, forts, rosters and heralds stay public under fog;** armies, gold, research and builds are private. The map's colours never lie, and that closes most leak paths.
3. **Three sight levels:**
   - in clear sight where you own or stand
   - glimpsed one province out, or two from forts, commanders, rulers and scouts
   - out of sight beyond, drawn from memory

   Exact counts of enemy armies come only from Far Sight or from fighting them.
4. **Estimates round the total and share it out by type,** so small groups can't hide fighters. Forecasts give two odds: at the shown numbers, and at the top of the range. The AI plans attacks on the shown numbers, and guards its capital against the top. No dice in fog.
5. **Builds are learned, not shown.** One rule: you learn a mandate, node or spell when something you are shown names it. Oaths, transformations, deaths and successions are heralded.
6. **One view state, built by allow-list,** feeds every screen, forecast, the board and the AI. It uses pooled stand-ins, view ids and four explicitly relaxed validation checks. Rebuilt events use their own text and an allow-list of numbers.
   - The proof is four indistinguishability tests: snapshot, report, two-turn and three-turn.
7. **Saves hold the truth;** memory and intel are rebuilt by replay. Hotseat fog is enforced by the screen. Hotseat playback is muted under fog. Save-scumming against the computer is not stopped.
8. **Four schools, two per faction, each paired with one side of the fork.**
   - The Oath opens that school's greatest working, and the transformation adds +1 mastery.
   - Each school also has a mastery node outside the fork.
   - Magic folds into M4's single path rather than adding a second fork.
9. **Mages are second-rank regular units,** on the roster from turn 1 but recruitable only once a spell is known. The shield rule limits stacking. No mage commanders in M5.
10. **The rulers:** the Ever-Regent casts in battle, with Sunlance from turn 1. The Thornmane and the Fang cast rituals only. King Corvane casts nothing.
    - A ruler's mastery bonus is its ability rank − 1, and its spell resistance is rank ÷ 2.
    - Both bolts reach rulers only when nothing else is in reach. So keeping power makes a ruler a better caster, and harder to kill with magic.
11. **Spells never roll dice.** Targets come from fixed rules, and effects are fixed numbers.
    - Sunlance focuses the biggest creature until it falls; Bloodbolt finishes the weakest. Neither overkills.
    - The alternative is Dominions-style resistance rolls: more flavour, less readable.
12. **Casters spread over a spellbook you set before battle** (order, and on or off), highest mastery first and the ruler first among equals.
    - No choices inside a battle, as M3 promised.
    - Researching a spell never silently changes your casters: the card and the spellbook preview say what will change.
13. **Rituals cost gold.** Tithe of Blood (Clans, 3 power, never with Feast of Victory) lets a mage's own army pay in blood at 1 hp a gold, one soldier at a time.
    - The alternative is a mana or gem resource.
14. **Rituals resolve before movement, wards first.**
    - A ritual turned aside costs half; any other failure costs nothing.
    - A caster's army holds the turn it casts, one ritual per army per turn.
    - A running budget covers rituals and recruits together.
15. **Curses and blessings move a fixed number of hp a turn** (12, +4 per point of mastery); "can't heal" is the real curse.
    - Shield of Law is a field spell, and Bastion stops at two forts.
    - Magic is aimed at M4's capital stand-off, not at deepening it.
16. **Research has a use after the path:** the arcana's 115 research, then research sold at 2 research for 1 gold.
17. **Both switches are off by default,** like Rulers and Paths before them. Magic needs Paths; fog needs nothing.
18. **Seasons are deferred** (§20).
19. **Art:** 4 new figures, 4 portraits, 14 icons and 5 VFX sheets, for 118 credits planned and 177 with reserve, against a budget of 180.
    - The cheaper option is figures and portraits only (104).
20. **First-pass numbers, not yet simulated.** They follow #41's breakpoint rule and M2's rules of thumb. M5-11 tunes within §13.3.
21. **All names are proposals,** and the lore writers' room can rename any of them:
    - the schools ("Law" was renamed from "Order", so it can't be confused with orders)
    - every spell and ritual
    - the Sunstone Adepts, Thornmane Shamans, Thornwolves and Greenwrath
    - mastery; "in clear sight", "glimpsed" and "out of sight"
    - the Magic tab

## 20. questions only Alex can answer
1. **Fog's public facts:** should province owners stay visible to everyone (my call, §2.2), or should the map itself be fogged ("last seen owned by")?
2. **Hidden builds:** should mandates and kept power be hidden under fog and learned (my call), or stay public from turn 1 as in M2?
3. **Dice in magic:** spells that always land (my call, for readability), or Dominions-style resistance rolls shown as odds?
4. **The price of magic:** gold for rituals (my call), or a separate magic resource?
5. **Tithe of Blood:** Clans only (my call), or shared, so a Crown could go dark?
6. **Seasons:** in M5 after all, in their own step, or not at all? 3D_DIRECTION §10.4 proposed them for M5 "if approved".
7. **Hotseat honesty:** is "the save file holds the truth" acceptable, or should fog wait for per-player files? And should there be an ironman option against the computer?
8. **Defaults:** when should Magic and Fog become on by default? After your playtest of this milestone, or later?
9. **Budget:** 180 Ludo credits for the M5 batch, or the 104-credit option with figures and portraits only?

---

## appendix A. critic rounds
Two rounds, three seats each:
- a new player who has never played Dominions
- a Dominions veteran
- the engineer, checking the draft against the code at bea3b51

Each seat read the whole draft independently. Round 2 read the revision and was told what round 1 had found, so it could check the fixes.

### round 1
**New player:**
- **Silent changes to casters.** Researching a spell could silently change what casters already do; for example, Shield of Law displaced the Regent's Sunlance for good.
  - Fixed by the player-set spellbook (§5.1), the "spread out" rule, the ruler first among equals, and previews on the cards.
- **One number under fog.** A fog forecast gave one number for a range.
  - Fixed: two odds, with ⓘ for the assumptions (§2.10).
- **A missed forecast didn't say why.**
  - Fixed: "what you didn't see" (§2.8).
- **Hidden costs.** "A failed ritual costs nothing" hid the pin and blood costs.
  - Fixed: the cast dialog's pin, risk and blood lines (§11.2).
- **"Lasts N turns" was ambiguous.**
  - Fixed: durations read "through turn N" everywhere (§6.2).
- **Example texts contradicted the rules.** Fixed.
- **"Stand there to see them" was a trap,** since standing there means attacking.
  - Fixed (§11.1).
- **Term clashes:**
  - Order → **Law**, because of "orders".
  - The battle "ward" → **shield**.
  - Arcana → the **Magic** tab.
  - Codex entries for every new term.
- **"Mastery 3" read as +3.**
  - Fixed: mastery is shown as a bonus (§3.2).
- **The build screen and the new game screen had no explanation moment.**
  - Fixed (§1.3, §7.1, §7.3).
- **Bolts overkilled,** and spells that weren't the round's biggest factor went uncaptioned.
  - Fixed: pending-aware targets, and the "first spell" caption rule.
- **Scouting wasn't shown.**
  - Fixed: scout lines on cards, panels and move forecasts.
- **Several rituals plus recruits could fail unpredictably.**
  - Fixed: a running budget (§6.1).
- **Memory threw away what you learned in battle.**
  - Fixed: the battle line is kept (§2.5).
- **A curse landing didn't say what to do.**
  - Fixed: the answer line (§11.2).

**Veteran:**
- **Bolts sniped rulers and overkilled.**
  - 6 Adepts killed a kept-10 Thornmane in round 3.
  - 10 Shamans killed a kept-10 King in round 1.
  - Fixed: pending-aware targeting, rulers last, spell resistance (§5.2).
- **Shield of Law crossed the breakpoint at forts** (11 → 13), covered a whole rank (about 132 damage blocked a round against 100 Tuskers, not "about 6"), and deepened the stand-off.
  - Fixed: +4 on up to 6 units of one type, never on units with a terrain or fort bonus.
- **Tithe of Blood paid you to use it:** spreading 1 hp a soldier pre-frenzies the whole army.
  - Fixed: only the caster's own army pays, one soldier at a time down to 1 hp, rulers never; band G9.
- **Sunburst's 1 damage switched on Berserk and Blood Frenzy for every unhurt Tusker.**
  - Fixed: Sunburst is now −2 attack on the whole front in round 1.
- **Blood Moon healed Berserk units to full,** which switched frenzy off.
  - Fixed: a cap at maximum − 1.
- **Bloodrot was all or nothing against stacked heals,** and heals stacked to 22-25 a turn.
  - Fixed: "can't heal" plus a drain, and no income effect.
- **Wards first plus free failure meant no guessing game.**
  - Fixed: half price when turned aside, a 2-turn ward, and a reactive ward lets the curse bite once more.
- **Fog leaks:**
  - your own army-id gaps
  - enchantment ids
  - rosters revealing the first spell
  - a caster's own curse events counting a veiled garrison
  - Fixed: per-faction counters, static rosters, sight-level rebuilding, and a two-turn test.
- **Wardedness in legality would leak,** and only the Crown could block scrying.
  - Fixed: never part of legality, and a counter open to both factions.
- **Per-type rounding could be gamed** (five types at 7 hide 29%).
  - Fixed: two odds, and the AI planning against the top (both refined in round 2).
- **Save-scumming the computer under fog.**
  - Accepted, and an ironman option asked of Alex.
- **Summons dodged the movement rule,** and refills were free.
  - Fixed: summons form their own holding army, cost 5 gold a wolf, one pack at a time.
- **Bastion and the Regent deepened the stand-off.**
  - Fixed: Bastion capped at 2; a Regent band.
- **Spellbook quirks.**
  - Fixed: the player-set spellbook.
- **Flavour was thin.**
  - Fixed: targeting with identity, mastery nodes; ley sites and a Crown global were left to the lore room.

**Engineer:**
- **The view state couldn't be a valid GameState** (stand-in shape, unseen rulers, researched prerequisites, sacrifices, view notes lost on copy).
  - Fixed: `is_view` with explicit relaxed checks, a fixed stand-in shape, serialized notes, and round-trip and readers-run-on-views tests.
- **Summons broke save and load** (types not on any roster), and got mandate hp.
  - Fixed: `UnitType.summoned`, loaded in `from_dict`, skipped by the hp, arrival and mod readers.
- **Far Sight made the resolver read fog.**
  - Fixed: it is a magic rule whenever magic is on, and only the UI and AI hide it.
- **View ids collided and were unstable,** and true ids leaked through battle events.
  - Fixed: pooled stand-ins with slot ids, per-faction counters, participants' true ids only in logs.
- **The indistinguishability test was weak and partly vacuous.**
  - Fixed: broader perturbations, canonical order, a report test on perturbed inputs, a two-turn test.
- **"Public" events carried private facts,** and "own = factions holds you" was unsafe.
  - Fixed: an audience table, `SAFE_NUMBERS`, separate target-side events.
- **The roster leaked the first spell.**
  - Fixed: a static roster and a recruit gate.
- **Per-viewer playback couldn't satisfy "playback = state".**
  - Fixed: `view_before`, synthetic sighting events, ghosts in their own material.
- **Holes in "byte-identical when off":**
  - ungated report fields
  - research sold
  - arcana kinds polluting `requires_any`
  - attacking mages counted as Volley
  - recorded orders can't prove AI unchanged
  - All fixed, with AI policy reruns in the off tests.
- **Cast orders weren't independent of order in the OrderBook,** and rituals didn't share the recruit budget.
  - Fixed: the pinned set and the running budget.
- **File-ownership collisions:** fixture, `forecast.gd`, `ui/`, the battle host, audio, the ritual forecast, M5-9's hooks.
  - Reassigned.
- **Untestable acceptance:** M5-7's autoplay games, the GPU budget and first-frame checks, hard-coded counts, a weak forecast condition.
  - Fixed: scripted scenarios, build-box checks, BFS-derived counts, a stronger condition.
- **AISeat's three truth reads.**
  - Named and changed.
- **Battle spells underspecified:** hex picks, ties, bleed order, Shield coverage, blessing morale, hex credit.
  - Specified.
- **Truth accessors beyond `state()`.**
  - Listed and scanned.
- **Per-army rebuilt moves leaked army splits.**
  - Aggregated.
- **`""` already meant two other things.**
  - `FogRules.OBSERVER`.

### round 2
**New player:**
- **Wrong text about Tithe of Blood.** The build-screen row was wrong: rulers can't use it, Far Sight is the first use under fog, and the blood/gold choice is made per cast.
  - Rewritten (§7.1), and the forecast warns about Berserk and Bloodbolt.
- **Shield of Law does nothing in most defensive battles, and nothing said so.**
  - The card, the battle forecast, the caster hover and the spellbook preview now say so; Law's flavour was reworded.
- **The spellbook's explanations contradicted its rule:** "another type", the Regent missing from the preview, "he casts first" false at low kept power.
  - Fixed: the per-army preview from the real cast step, the Regent's locked row, ruler first among equals, corrected texts.
- **No forecast line for a target out of sight,** and the assumed spell for the Crown came out as Sunburst.
  - Fixed: "no odds" out of sight; assume the first tier I spell.
- **Far Sight was offered where impossible, and the risk ignored what you can see.**
  - Fixed: branching hovers, one `caster` definition, risk lines by sight, a caster blocking only the reading.
- **The curse line sounded already solved.**
  - Rewritten, with effect, duration, who is hit, and how to stop it.
- **Clashes:** "turned aside" (rituals, shields, resistance) and "power" (kept power, resistance).
  - Fixed: "blocked" for shields, "spell resistance", and Sunburst stated to cover rulers.
- **Dawn Blessing's morale rule was invisible,** and its heal could be cancelled by a 1-hp heal.
  - Fixed: morale counted at the battle's start and shown; the heal became a per-army budget.
- **Mastery showed one number for per-school values,** the cap was silent, the lock-in row was wrong, and packs couldn't be cast smaller.
  - Fixed: per-spell display, the cap shown, a corrected row, a size picker.
- **Mage exposure, jargon, codex gaps for the spell kinds, live ruler-card numbers.**
  - Fixed.
- **The victory screen was one line.**
  - Expanded (§2.1).

**Veteran:**
- **Bloodrot and Dawn Blessing hit every fighter for a fixed price:** 300 hp from a 50-unit capital for 15 gold; over 1,000 hp healed for 12. This was the dominant line.
  - Fixed: per-turn hp budgets (12, +4 per point of mastery).
  - "Can't heal" stays uncapped as the stand-off breaker.
  - New band G14 measures ritual value per gold.
  - The AI wards ahead.
- **Tithe of Blood with Feast of Victory made rituals free,** and G9 measured mandate swaps.
  - Fixed: Tithe and Feast exclude each other; G9 uses a null mandate of equal cost, plus a scripted build.
- **Sunlance's "most hp left" made rulers magnets** (a kept-7 Thornmane took 26 sure damage in round 1), spread damage, and switched frenzy on.
  - Fixed: the highest maximum hp, most hurt first, rulers last.
- **Blood Moon at max − 1 plus Lifedrinker looped with no counterplay,** and its knob did nothing.
  - Fixed: rounded down, the larger share, and warded provinces outside the moon.
- **Rounding each type let a human bluff the AI** (15 fighters shown as 25 and assumed 35).
  - Fixed: round the total and share it out; the AI attacks on the shown numbers and guards on the top of the total.
- **A caster blocking Far Sight made it a half-price caster detector and killed capital readings.**
  - Fixed: a caster blocks only the reading; G11 counts successful Far Sights.
- **Leaks:**
  - enchantment ids still carried counters
  - road moves showed their end
  - hotseat sound
  - an impossible band
  - Fixed: view ids for rival enchantments, a three-turn test, the first step only, muted hotseat playback, G13 scoped to clear sight.
- **Mastery was unequal by an order of magnitude.**
  - Fixed: each school's bonus scales one battle effect and one ritual (§3.2).
- **The bleed was permanent for the Blood Pact,** and unclear in the break check.
  - Fixed: it closes after the battle and isn't counted.
- **The Regent was still too strong,** and G10 was toothless.
  - Fixed: G10 absolute (at most 60%), Regent knobs, and §7.2's comparison corrected.
- **Small holes:**
  - Bastion counts forts ever raised
  - the pack is priced as disposable
  - forecasts warn about summons and forts
  - All fixed.

**Engineer:**
- **Public heralds still leaked through the resolver's own text and numbers** (`sworn_text`'s ETA, `transformed_text` reading mandates, `units_changed`).
  - Fixed: all rebuilt text comes from `FogData.TEXT`, and §14 lists `SAFE_NUMBERS` and what is never carried.
- **The report test froze leaky events,** and `report_for` lacked the inputs it needed.
  - Fixed: it takes the true states, perturbation returns a renaming map, and the two-turn test varies research and sacrifices.
- **`army_counters` broke its own test, and "changes no outcome" was false.**
  - Fixed: saved whenever set, its initial values defined, admitted as a rule change, and G11's control runs with counters on.
- **Views failed validation in ordinary play:** `path_branch` missing, rulers remembered twice, kept power against new mandates.
  - Fixed: the copies, rulers remembered once, the kept-power cap, the four relaxed checks listed with a test each.
- **Changing `has_living_ruler` would crash the ruler panel.**
  - Fixed: a new `ruler_alive`, with callers handling "location unknown".
- **"Playback = state" wasn't exact:** province-bound ids, true ids in battle events.
  - Fixed: one fold, `apply_view_events`; rebuilt moves and battle events carry view ids; synthetic events defined as the leftover.
- **The AI still got the truth** through the autoplay Simulator and `report_notes`.
  - Fixed (§10.1, M5-11).
- **The two-turn test's variations were undefined.**
  - Fixed: a generator, with discards and a minimum count.
- **Remaining ownership collisions:** the heals across three files, M5-3's items in `game_screen.gd`, the grants function, the fixture tool, the forecast lines.
  - Fixed: M5-0's scaffold and explicit owners.
- **The pin didn't drop an earlier move,** and the budget didn't reach the forecasts.
  - Fixed: `pinned_armies` over the whole list, and reserved gold in `price_recruits` and `Forecast`.
- **Forecast = result was untestable for odds,** because pooling changes fighter order.
  - Fixed: compare against the truth pooled the same way.
- **Determinism gaps:** the cast order across schools, bolt ties, Blood Moon's rounding and logging, the cap's scope.
  - Specified.
- **State gaps:** Bastion's count, rival enchantment ids, the target-side event's name.
  - Fixed: `Faction.bastions`, view ids, `ritual_fell`.
- **Acceptance checks that couldn't run:** `round_count`'s ranges at 48-54, the world3d RNG scan, fixture re-recording.
  - Fixed: computed ranges, `BOARD_FILES`, re-recording stated.
