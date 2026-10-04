# ASCENDANT: M3 design spec, "battles worth watching"

Status: **PROPOSED by the director (Claude session, 2026-10-02). Not yet approved by Alex; nothing will be built until Alex has played M1/M2 and approves.**

Built on: `design/GAME_BRIEF.md` (approved: pillar 3, "battle presentation", the approachability rules), `design/MILESTONES.md` (M1 and M2 as format models, the M3 outline line), `design/STYLE_BIBLE.md` (§2 readability, §4.1 unit animation, §4.2 VFX), `design/ASSET_MANIFEST.md`, `studio/ludo-playbook.md`, and the battle code on `main` at ce6dfb7: `rules/auto_battle_resolver.gd`, `rules/turn_resolver.gd` (`_fight`), `ui/battle_report_viewer.gd`, with the rules and report data described in PRs #19, #41 and #48. Battle sizes were measured with a throwaway script (not committed) that played 120 AI-vs-AI games with rulers on `main`.

**Alex: read §12 (director's calls) first.** Those are the judgement calls. Everything else follows from them.

## the short version
- The battle rules don't change. The resolver writes a complete **battle event log** while it fights: every attack with its rolls, every wound, death, morale check and rout, every trait and mandate effect, round by round.
- **Playback is a pure function of that log.** It never calls the rules and never draws a random number, so it can't change an outcome. Tests check this at three levels (§2.1).
- The log replays from the seed: each recorded roll is re-drawn from the RNG state saved at the start of the battle, and the log of any battle can be rebuilt from the game record.
- Logs are kept in memory with the last turn's report only. They are never saved and never go into the game record (§2.4).
- **The battle screen:** a fixed, full-screen view. The attacker is on the left and the defender on the right, with the fort behind it. Every fighter is drawn in its real rank: front, second, back. The backdrop shows the province's terrain.
- **Readability first:** a strength bar per side shows hit points left and a notch where that side breaks. A caption after every round says what mattered, using the report's own "why" factors. Hovering anyone shows what it is doing and the exact numbers behind it.
- **Controls:** 1×, 2× and 4× speed, pause, skip to the end, jumps to five key moments (first to fall, charge, ruler falls, turning point, rout), and a round scrubber.
- **Entry points:** a Watch button on every battle row of the turn report and in the battle report viewer, and "Watch your battles (N)" at the top of the turn report. Auto-watching at the start of a turn is a setting, off by default. The AI's battles can be watched like any other.
- **Placeholders first:** everything works with portrait cards in player colour plus emblem. Sprite art swaps in figure by figure as it lands.
- **Art:** 12 animated figures (8 units and 4 rulers, 5 states each), 7 effects, 3 horizon bands and a fort. That is 321 Ludo credits planned and 482 with the re-roll reserve. Budget: 500.
- 9 tickets, M3-1 to M3-9 (§11).

---

## 1. what exists, and what playback needs

### 1.1 the battle today (unchanged by M3)
- **Rounds:** at most 8 (`ROUND_CAP`). Each round, every standing fighter attacks once, all at the same time. Damage lands at the end of the round, so a fighter that falls still strikes that round.
- **Targets:** a seeded pick among the enemies it can reach.
  - Ranks are tiers: 0 is the front, 1 is the second rank (Volley units and the Ever-Regent), and 2 is the commanders at the back.
  - The front rank shields the second rank while at least as many front-rank fighters stand as second-rank ones. Skirmish reaches the second rank anyway.
  - Commanders can be reached only once no unit stands in front of them.
- **Hit:** chance = clamp(base + 4 × (attack − defense), 30, 90). Base is 60, or 70 with Drilled Ranks. One roll of 1-100.
- **Damage:** ceil(attack ÷ 2) − floor(defense ÷ 4), at least 1, plus Charge in round 1.
- **Morale:** a side breaks at the end of a round once its lost % ≥ break % = clamp(20 + 5 × morale, 25, 95). Iron Discipline can hold it.
- **End:** one side left, a mutual rout, or the round cap.
- **Losers:** the TurnResolver destroys every army on a losing side. There are no retreats.

### 1.2 what the report has, and what it lacks
The report (`numbers.report` on each battle event) has:
- per-round totals per side (dealt, hits, attacks), highlights, and hp per side at each round's end
- each side's morale checks (`morale_log`) and lost fighters (names only)
- ruler fields, mandates, and the deciding factors (`factors`, `all_factors`)

That is enough for a written report but not for playback. It doesn't say:
- **who hit whom:** no per-attack attacker, target, roll, chance, damage or modifier parts
- **which fighter is which:** two "Spearmen" can't be told apart, and there is no per-fighter hp over time
- **which ranks could be reached** in each round
- **when each factor mattered:** factor worth is summed over the whole battle, not per round
- **the RNG state** the battle started from

M3 adds all of these in the event log (§2).

### 1.3 how big battles get (measured)
Measured with a throwaway script on `main`: AI vs AI with rulers, both seat orders, a turn cap of 60, Godot 4.5.1 headless on Alex's Mac. "Side" means one faction's fighters in one battle.

| | AI "normal", 80 games | AI "easy", 40 games |
|---|---|---|
| battles | 144 | 59 |
| fighters per battle, p50 / p90 / p99 / max | 75 / 161 / 216 / **277** | 76 / 137 / 211 / 268 |
| fighters on one side, p50 / p90 / p99 / max | 38 / 86 / 120 / 145 | 42 / 74 / 108 / **149** |
| attacks per battle, p50 / p90 / max | 202 / 533 / **898** | 225 / 441 / 693 |
| rounds, p50 / max | 4 / 8 | 4 / 8 |
| battles in one turn, max | 1 | 2 |
| report JSON, max | 32 KB | 33 KB |
| battles with more than 2 sides | 0 | 0 |

- M1 games played by the greedy bot are much smaller: at most 44 fighters per battle, median 8. The M2 AI builds large armies late in the game, so **every number in this spec is sized for 280 fighters (150 a side) and 900 attacks.**
- Resolving a constructed 145-a-side battle took 98 ms, measured while three runs shared the machine. Run alone, a 40-a-side battle took 5.9 ms where it had taken 12.4 ms shared, so alone the big battle is about 50 ms.

---

## 2. architecture: the battle event log

### 2.1 the contract
```
TurnResolver ── AutoBattleResolver.fight(sides, ctx, rng, record = true) ──► result: winner, report, log
                                                                                  │
GameSession keeps the last turn's events: numbers.report + numbers.log ───────────┘
                                                                                  │
BattleTimeline.build(log) (pure, rules/) ──► BattleScreen plays it (ui/) ─────────┘   reads only, never writes
```
1. **One source.** The resolver writes the log while it fights, from the same values it uses. Nothing in the UI recomputes a hit chance, damage or morale.
2. **Recording is passive.** It doesn't draw from the RNG, reorder anything or change any state. `record = false` (used for odds estimates) costs nothing.
3. **Playback is a pure function of the log.**
   - The battle UI reads the log, the report, static data (art, codex text, rules constants) and its own clock.
   - It never calls `AutoBattleResolver`, `TurnResolver` or `GameSession` methods that change state, and never creates a `SeededRNG` or `RandomNumberGenerator`.
   - Cosmetic variation (idle phase, projectile arc) comes from a hash of the fighter id and event index, never from an RNG.
4. **Three levels of "playback never changes the outcome" tests:**
   - **rules:** report, winner, armies and RNG state are identical with recording on and off (M3-1)
   - **UI:** `GameState.to_dict()`, the event's report and log, and `GameSession.record()` are deep-equal before and after watching (M3-3, M3-5)
   - **static:** no RNG or resolver calls in `ui/battle_*.gd` (M3-3)
5. **Replays from the seed.**
   - The log stores the RNG state before and after the battle. `BattleLog.verify_draws(log)` re-draws every recorded roll from the "before" state and must land on the "after" state.
   - `BattleLog.regenerate(record, turn, index)` rebuilds any battle's log from the game record (§2.4).

### 2.2 the log schema (version 1)
A log is a JSON-safe Dictionary. 64-bit integers are strings (`Serial.int64_to_str`). Fighter and side references are integer ids into the log's own arrays. Every name is player-facing and every id is a data id, as in the report.

**Top level:**
```
{
  "v": 1,
  "id": "t7b1",                 # "t<turn>b<index>"; set by TurnResolver ("" outside a game)
  "turn": 7,                    # the turn being resolved, as players count turns (0 outside a game)
  "index": 1,                   # 0-based battle index in resolution order (border battles, then province battles)
  "kind": "province",           # "province" | "border"
  "provinces": ["thornvale"],   # one id, or the two ids of the border
  "terrain": "forest",          # the province terrain; "" for a border battle
  "fort": false,                # the province has a fort
  "defender": "kingdom",        # faction id, or "" when nobody held the ground
  "round_cap": 8,
  "rng": {"seed": "…", "before": "…", "after": "…"},   # SeededRNG seed and state, as strings
  "sides": [SIDE, …],           # in the resolver's side order (faction id order)
  "fighters": [FIGHTER, …],     # in the resolver's fighter order (below)
  "events": [EVENT, …],         # in the exact order the resolver did things
  "truncated": false            # true if recording stopped at MAX_EVENTS (§2.4)
}
```

**SIDE:**
```
{"index": 0, "faction": "beasts", "name": "Thornmane Clans", "defender": false,
 "armies": [{"id": "beasts-3", "label": "Thornmane Clans army at Thornvale (3 units, led by Warchief)"}],
 "fighters": [0, 1, 2, 3],      # ids of this side's fighters
 "hp_start": 76, "base_morale": 7,
 "start_morale": {"morale": 9, "parts": {"commander": 2}, "break_pct": 65},   # _morale() before round 1
 "base_hit": 60,                # 70 with Drilled Ranks
 "frenzy": 0,                   # Blood Frenzy's attack bonus (3), or 0
 "iron": true, "feast": false,  # Iron Discipline, Feast of Victory
 "dread": 0,                    # this side's ruler's Dread in this battle, or 0
 "mandates": ["iron_discipline", "blood_frenzy"]}   # battle mandates in play, in the order taken
```

**FIGHTER:** one per unit, commander and ruler. The order is the resolver's: sides in order; within a side, armies by id; within an army, its units in army order, then its commander, then its ruler.
```
{"id": 3, "side": 0, "army": "beasts-3", "role": "unit",   # "unit" | "commander" | "ruler"
 "type": "tuskers", "name": "Tuskers", "trait": "Berserk",  # trait "" when none
 "tier": 0,                    # 0 front, 1 second, 2 back
 "hp": 14, "max_hp": 16, "hp_parts": {"mandate_veteran_levies": 2},
 "attack": 11, "defense": 4, "morale": 7, "cost": 11,       # the type's own numbers; parts come per attack
 "ruler": {}}                  # a ruler: {"id": "aurel_king", "kept_power": 4, "rank": "front", "dread": 0}
```

**EVENTS.** Every event has `"t"` (its type) and, except `end`, `feast` and `aftermath`, `"n"` (the round). Within a round the order is always: `round`, every `attack` (in the resolver's attack order), then the `wound` and `death` events (side order, fighter order, each death right after its wound), then `morale` for each side still standing with hp, then `rout` or `destroyed`, then `round_end`.

| t | fields | meaning |
|---|---|---|
| `round` | `n`; `reach`: `[{"side", "tiers": [int], "skirmish_tiers": [int]}]` | A round starts. For each side, the tiers enemies can attack this round: `tiers` for ordinary attackers, `skirmish_tiers` for attackers with Skirmish. Computed by the resolver's own target rule (`_reachable_tiers`, factored out of `_targets` with no change in behaviour). |
| `attack` | `n`, `by`, `to`, `pool`, `pick`, `chance`, `roll`, `hit`, `damage`, `bonus`, `base_hit`, `attack`, `defense`, `reach`, `screened`, `expected` | One attack (details below). |
| `wound` | `n`, `f`, `from`, `to`, `by`: [fighter ids] | At the end of round `n`, fighter `f`'s hp went from `from` to `to`. `by` lists the fighters that hit it this round, in attack order. |
| `death` | `n`, `f`, `by` | Fighter `f` fell (its hp reached 0). A ruler's death is this event with a fighter whose role is "ruler". |
| `morale` | `n`, `side`, `morale`, `base`, `parts`, `break_pct`, `lost_pct`, `hp`, `result`, `held_by`, `decisive`, `iron_last_round` | One morale check (details below). |
| `rout` | `n`, `side`, `fled`: [ids] | The side broke and left the battle. `fled` lists its fighters still standing. |
| `destroyed` | `n`, `side` | The side had no one left standing. |
| `round_end` | `n`, `hp`, `attacks`, `hits`, `dealt`, `expected`, `impact` | Per side, as arrays in side order: hp left, attacks, hits, damage dealt and expected damage this round. `impact`: per side, `{factor key: worth this round}`, 2 decimals, zeros left out. The keys and accumulator are exactly the resolver's `side.impact`, so the rounds add up to the report's factors (§2.5). |
| `end` | `rounds`, `winner` (side index), `how` ("rout" \| "destroyed" \| "mutual" \| "round_cap"), `tie_break` ("none" \| "defender" \| "roll"), `roll`, `tied` (count of tied sides when `tie_break` is "roll"), `impact` (per side, worth added after the rounds: Veteran Levies) | The battle is over. |
| `feast` | `side`, `healed`: `[[fighter, from, to], …]` | Feast of Victory healed the winner's survivors (only when it healed someone). |
| `aftermath` | `destroyed_armies`: [army ids], `lost`: [fighter ids], `fallen_rulers`: [fighter ids], `text` | Added by TurnResolver after it applies the result. `lost` are fighters still standing on a losing side, destroyed with their armies. `text` is the report's aftermath sentence. |

**The attack event**, with every field. The example is a wounded Tuskers hitting Spearmen who hold a forest:
```
{"t": "attack", "n": 2, "by": 3, "to": 9,
 "pool": 4, "pick": 2,          # target roll: rng.randi_range(0, pool - 1) returned pick
 "chance": 72, "roll": 37,      # hit roll: rng.randi_range(1, 100) returned roll
 "hit": true,                   # roll <= chance
 "damage": 5,                   # damage on a hit, bonus included (dealt = damage if hit, else 0)
 "bonus": {},                   # damage bonus parts, e.g. {"Charge": 4} in round 1; {} when none
 "base_hit": 60,                # the attacker's side's base hit chance
 "attack":  {"value": 14, "base": 11, "parts": {"Berserk": 3}},
 "defense": {"value": 11, "base": 7,  "parts": {"terrain": 2, "Shield Wall": 2}},
 "reach": "front",              # "front" | "second" | "back" | "skirmish" (only Skirmish could reach this target)
 "screened": false,             # the attacker itself was out of reach of ordinary attackers (Volley shooting from safety)
 "expected": 3.6}               # chance / 100 × damage, 1 decimal
```
Check: chance = clamp(60 + 4 × (14 − 11), 30, 90) = 72. Damage = ceil(14 ÷ 2) − floor(11 ÷ 4) = 7 − 2 = 5. Expected = 0.72 × 5 = 3.6.
`attack.parts` and `defense.parts` are the resolver's own `_attack()` and `_defense()` parts, keyed as in the report: `terrain`, `fort`, trait names, and `mandate_<id>`.

**The morale event**, with every field:
```
{"t": "morale", "n": 2, "side": 0, "morale": 7, "base": 7,
 "parts": {"commander": 2, "Fury": -2},
 "break_pct": 55, "lost_pct": 61, "hp": 30,
 "result": "breaks",            # "holds" | "breaks" | "held" (Iron Discipline kept it)
 "held_by": -1,                 # for "held": the fighter id of the commander standing; otherwise -1
 "decisive": ["Fury"],          # the parts that decided this check (below)
 "iron_last_round": false}      # Iron Discipline would have held, but this is round 8
```
`decisive` uses `break_pct()`, the same comparison the report's morale factors use:
- **holds:** every positive part p with lost_pct ≥ break_pct(morale − p). Without p, the side would have broken.
- **breaks:** every negative part p with lost_pct < break_pct(morale − p). Without p, it would have held.
- **held:** `[]`. Iron Discipline is the reason.

In a mutual rout, every side that broke gets a `rout` event. The `end` event's winner keeps the field (the resolver resets its `routed`).

**Where every trait, mandate and ruler effect shows up:**

| effect | in the log |
|---|---|
| terrain, fort (defender only) | `attack.attack.parts.terrain`, `attack.defense.parts.terrain` / `.fort` |
| Shield Wall | `attack.defense.parts["Shield Wall"]` |
| Volley | fighter `tier` 1; `attack.screened` |
| Charge | `attack.bonus.Charge` (round 1) |
| Berserk, Pack Leader | `attack.attack.parts.Berserk`, `["Pack Leader"]` |
| Skirmish | `attack.reach` = "skirmish"; `round.reach[].skirmish_tiers` |
| Inspire, commander +2, ruler +2 | `morale.parts.Inspire`, `.commander`, `.ruler` |
| Fury, Dread | `morale.parts.Fury`, `.Dread` (on the enemy side); `side.dread` |
| Drilled Ranks | `attack.base_hit` = 70; `side.base_hit` |
| Royal Armories, Blood Frenzy | `attack.attack.parts` / `attack.defense.parts` `mandate_royal_armories`, `mandate_blood_frenzy` |
| Veteran Levies | `fighter.hp_parts`; `end.impact` |
| Iron Discipline | `morale.result` = "held", `held_by`; `morale.iron_last_round` |
| Feast of Victory | the `feast` event |
| rulers | attacks `by` a ruler fighter; its `death`; `aftermath.fallen_rulers`; `ruler.kept_power` and `rank` in the fighter |

### 2.3 recording (resolver changes, M3-1)
- `AutoBattleResolver.fight(sides_in, ctx, rng, record := false)` builds the log alongside the report and returns it as `"log"` (absent when `record` is false).
  - `resolve_battle()` passes `record = true` and puts the log in its result as `"log"`.
  - `estimate()` passes false.
  - `resolve()` takes a `record` argument, default false.
- The `BattleResolver` interface gains an optional `"log"` in the result. `StubBattleResolver` gives none.
- `TurnResolver._fight()` then:
  - sets `id`, `turn` and `index` (the turn as players count it is `s.current_turn + 1`)
  - appends the `aftermath` event
  - stores the log in the event's `numbers.log`, beside `numbers.report`
- **Constraint:** the report, every factor and every existing test stay byte-identical. The only refactor allowed is factoring `_reachable_tiers` out of `_targets`.

### 2.4 storage, size limits, regeneration
- **Where logs live:** in memory, in `numbers.log` of the battle events of **the last resolved turn**. That is where the report already rides, and `GameSession` already keeps only the last turn's report. When the next turn resolves, the old logs go with the old report.
- **Never stored:**
  - Logs are not in `GameSession.record()` or `history()`. The record stays "start state + orders + seeds".
  - When save/load comes, logs are regenerated, not saved.
- **Regeneration:** `BattleLog.regenerate(game_record, turn, index) -> {"log", "report", "errors"}`.
  - It replays the record to the start of `turn` (`GameSession.replay` gains an `up_to_turn` argument), resolves that turn with its recorded orders and seed, and returns battle `index`.
  - Errors are plain language, for example "This game record has no turn 9." or "Turn 7 had 1 battle, so there is no battle 3."
  - Used by the determinism tests, the dev tool `tools/battle_log.gd` (dumps a battle's log, report and captions as JSON from a record) and, later, save/load.
  - Budget: ≤ 1.0 s for a 60-turn game on the build box.
- **Size:**
  - The biggest measured battle (277 fighters, 898 attacks, 4 rounds) has about 1,750 events. Its log is estimated at about 340 KB of JSON: fighters about 72 KB, attacks about 216 KB, wounds about 41 KB, the rest about 11 KB.
  - Budgets: **≤ 400 KB of JSON for the biggest fixture**, ≤ 1 MB for one turn's logs, and recording adds ≤ 25% to the resolve time of the biggest fixture.
- **Hard cap:** `BattleLog.MAX_EVENTS = 12000`, about 7 times the biggest measured battle.
  - Past it, recording stops and the log gets `"truncated": true`. The battle itself is fought to the end as usual, because recording is passive.
  - Watch is disabled for that battle with "This battle is too big to play back. The report has everything."
  - No measured battle comes near the cap.

### 2.5 derived data (pure, `rules/`, tested)
- **`BattleTimeline.build(log)`** folds the events into states, with a keyframe at every `round` event. `state_at(i)` is the state before event `i`:
  - **per fighter:** hp, pending damage, alive, fled, lost
  - **per side:** hp, pending damage, morale, break %, lost %, `out` ("" \| "routed" \| "destroyed"), `held`
  - **overall:** the round and the beat: "deploy" \| "attacks" \| "wounds" \| "morale" \| "end"
  - `final_state()`, and `round_start(n)` (an event index)
- **`display_order(n)`:** round `n`'s attacks taken round-robin across sides (side 0's first, side 1's first, side 0's second, and so on), each side in log order. All attacks of a round land at the same moment in the rules, so any display order is truthful. Alternating keeps either side from looking as if it struck first.
- **`statuses(state, fighter)`:** derived from the header and the hp, not logged:
  - Shield Wall active: the trait, and another friendly fighter standing
  - Berserk active: the trait, and hp below max
  - Blood Frenzy active: `side.frenzy` > 0, and hp below max
  - Pack Leader bonus: a unit, with a standing friendly commander that has Pack Leader
  - shielded: its tier is not in the enemy's ordinary `reach` tiers this round
  - aura source: commander, Inspire, ruler, Fury, Dread
- **Cross-checks** (M3-1 tests, on every fixture and every battle of 20 autoplay games):
  - The final state equals the report: hp_end, `lost` names in order, routed/destroyed/out_round, rounds_fought, per-round hp, attacks, hits and dealt, the ruler's fell/fell_round/hp_end, and the feast's healed total.
  - Σ `round_end.impact` + `end.impact` equals each side's impact in the report's `all_factors`, ±0.1.
  - The derived statuses agree with every attack's parts.
  - Every attack's target sits in a tier its attacker could reach that round.

---

## 3. battlefield layout

### 3.1 the screen (1600×900 base viewport, checked at 1920×1080)
The project stretches `canvas_items` from 1600×900, so all numbers are in that space.

| region | x, y, w, h | contents |
|---|---|---|
| top bar | 0, 0, 1600, 88 | title ("Battle of Thornvale (forest) · turn 7"), side plaques, the two strength bars (§4.8), the round counter, Close |
| field | 0, 88, 1600, 600 | backdrop and fighters. 1216 wide while the why panel is open |
| caption strip | 0, 688, 1600, 64 | the round caption (§4.8). 1216 wide while the why panel is open |
| controls | 0, 752, 1600, 148 | scrubber and buttons (§5) |
| why panel | 1216, 88, 384, 664 | docked right, collapsible to a 32 px tab (§7.3) |

Inside the field:
- the horizon band takes y 88-248 (160 px), and the ground y 248-688
- fighters' feet stand between y 300 and y 672
- the camera is fixed: no pan and no zoom

### 3.2 sides and ranks
- **Which side where:** the defender is on the right. With no defender (everyone arrived, or a border battle), side 0 in faction id order is on the left. Each side faces the centre.
- **Columns:** each side's fighters stand in columns, front rank nearest the centre. The order outwards is front rank (tier 0), then second rank (tier 1), then back line (tier 2, commanders).
  - The gap between the two front ranks is 120·s px, so lunges don't overlap.
  - Ranks are 24·s px apart.
  - The left and right margins are 32 px.
- **Slots:** the column pitch is 60·s px and the row pitch (feet to feet) 40·s px, where s is the figure scale (§3.4).
  - Columns fill top to bottom, frontmost column first.
  - Within a tier, fighters are grouped by unit type (in faction roster order), then in log order, so blocks read as blocks.
  - Large figures (Knights, War Bear, the Great Thornmane) take two rows of one column.
- **Rulers** stand in the middle row of their tier's frontmost column: King Corvane, the Great Thornmane and the Ninth Fang in the front rank; the Ever-Regent in the second rank.
  - A name plate is always shown, for example "King Corvane I · 34/38".
  - The ground ellipse gets the bible's second gilt ring (§2.4, "ruler present").
- **Commanders** stand in the middle rows of the back line, with a standard glyph.
- **Depth:** figures draw in order of feet y, lower in front. Fallen figures draw beneath standing ones.
- **More than two sides:** none occurred in M2 (the map has two factions). The screen supports exactly two. A battle with more sides keeps its written report, and Watch says "Battles with more than two sides can't be watched yet."

### 3.3 terrain, border and fort
- **Province battle:** a code sky gradient (placeholder colours `#A9CBE6` to `#E9EEF0`; the art lead sets the final ones in M3-8), then the terrain's horizon band (art, §9), then the ground.
  - **Ground:** the M1 terrain texture (`assets/terrain/<terrain>.webp`, 512 seamless) tiled across the ground band at 50% horizontal and 30% vertical scale, so it suggests the high angle.
  - **Without art:** the ground is the bible's flat terrain anchor colour (plains `#B3B86A`, forest `#3F7A55`, hills `#B08A5E`), and the horizon is a code silhouette 25% darker than the ground: bumps for forest, long curves for hills, a flat line for plains.
- **Defender's plaque chips:**
  - "Forest: +2 defense to the defender" (or the hills' +1 defense and +1 attack)
  - "Fort: +2 defense"
  - "Nobody was defending: no terrain bonus"
- **Border battle:** plains visuals, a dashed map-ink line down the centre with the two province names at its top, and the chip "Border battle: nobody defends, no terrain bonus".
- **Fort:** drawn only when the province has a fort **and** someone defends, because only a defender gets it. The wall layer stands behind the defender's back line. Its bottom sits on y 688, it is 480 px tall, and its right edge is the field's right edge. Without art, it is a code-drawn crenellated band in map ink `#2A231C` at 60%.

### 3.4 big battles
- The layout picks one scale s for both sides: the largest of **1.0, 0.875 and 0.75** at which both formations fit, with the why panel as the player left it.
  - At s = 1 a human-sized figure is 96 px tall. At 0.75 it is 72 px, the bible's minimum (§2.1).
  - If nothing fits, the why panel collapses into an overlay (its button still opens it over the field) and the layout tries again.
- **Files:** if nothing fits even then, each figure stands for a file of up to k fighters of the same type, army and tier (k = 2, 3, and so on, until it fits).
  - The figure shows a "×k" badge and a file hp bar. Hover lists each fighter in the file.
  - A file loses a figure when its count drops to a multiple of k.
  - No measured battle needs files.
- **Capacity in slots per side** (the layout code computes these; the numbers are for reference):

| s (figure height) | why panel open | why panel closed |
|---|---|---|
| 1.0 (96 px) | about 80 | about 110 |
| 0.875 (84 px) | about 100 | about 140 |
| 0.75 (72 px) | about 140 | about 195 |

  Against the measurements: the median side (38) fits at 1.0, p90 (86) at 0.875, p99 (120) at 0.75, and the biggest (149) at 0.75 with the panel closed.
- **Massed battles** (more than 40 fighters on a side):
  - floating damage numbers show only for big hits (≥ 8), the hits that kill, and the selected fighter
  - status glyphs show only on rulers, commanders and the hovered or selected fighter
  - the bars and captions carry the story

---

## 4. playback presentation

### 4.1 beats and timing
Durations at 1×. 2× and 4× divide every duration and multiply every sprite's fps.

| beat | duration at 1× | what happens |
|---|---|---|
| deploy | 1.5 s | plaques and bars fill; the front ranks step forward 48·s px (move animation) |
| round banner | 0.4 s | "Round 3 of at most 8"; a rank that became reachable shows its exposed glyph |
| attacks | stagger × (A − 1) + the last impact | attack i in display order starts at i × stagger, where stagger = min(0.25 s, 1.6 s ÷ A) and A is the round's attacks; the last impact lands at most 0.8 s after its start |
| wounds land | 0.6 s | pending damage becomes lost hp; deaths start (the death animation runs on through the next beats) |
| morale | 0.5 s | break notches move; each check shows its result; Iron Discipline's hold |
| rout or destroyed | 1.5 s | only in the round a side leaves |
| result | after 0.8 s | the result card (§4.8) |

- A round takes at most 0.4 + 1.6 + 0.8 + 0.6 + 0.5 = **3.9 s at 1×**, plus 1.5 s in a rout round.
- A typical 4-round battle takes about 19 s at 1× and 5 s at 4×. The longest (8 rounds) takes about 35 s at 1× and 9 s at 4×.

**Event to visual:**

| log event | visual |
|---|---|
| `round` | banner; a shielded rank that became reachable gets the exposed glyph and a 0.3 s outline |
| `attack`, hit | the attacker plays attack, with a lunge (melee) or a projectile (§4.4). At impact: the target plays hit, an impact effect (big if damage ≥ 8), a floating number, and a pending chunk on the target's hp bar and its side's strength bar |
| `attack`, miss | the same attack. At impact: "miss" in grey; a projectile flies on 40 px and fades, with a dust puff where it lands |
| `wound` | the hp bar drops from `from` to `to` over 0.3 s |
| `death` | death animation, dust, and the figure stays as a fallen marker (desaturated 30% after 1 s) so losses can be counted. A ruler also gets the ruler-fall burst, 0.6 s of 0.5× slow motion, and a 6 px shake |
| `morale` | the notch moves to the new break line; a tag when morale changed ("−4 morale: the Knight Captain fell"); "holds", "breaks" or "held by Iron Discipline" on the bar |
| `rout` | the survivors turn and run to their back edge (move animation at 1.5× speed, fading out at the edge); the bar shows "BROKE" |
| `destroyed` | the bar shows "NO ONE LEFT" |
| `round_end` | the round caption (§4.8); the round's numbers in the why panel |
| `end` | the result card. In a mutual rout, the winner's figures stop at the field edge and turn back |
| `feast` | the winner's survivors get a "+hp" tag and refill over 0.6 s |
| `aftermath` | the losers' remaining figures fade out; the aftermath sentence goes on the result card |

- **Floating numbers:** `#F1ECE0` with a 2 px ink `#1A1612` outline, 16 px at s = 1 (12 px minimum) and 22 px for big hits. They rise 24 px over 0.6 s and fade. A miss shows "miss" in text secondary `#BDB6CF` at 14 px.
- **Overlaps:** when a fighter is hit while attacking, its attack keeps playing, and the hit shows only as the impact effect plus a 0.15 s tint toward negative `#F06A64` at 40%.

### 4.2 placeholder visuals (built first; the milestone works with these alone)
- **Figure = a portrait card,** 72×96 px at s = 1:
  - the unit's portrait (`assets/portraits/<faction>/<unit>.webp`; rulers per M2-9) when the file exists
  - otherwise the panel colour `#282740` with the unit's 32 px class glyph (bible §2.3 and §4: hand-written SVG)
  - a 3 px player-colour border with the bible's keylines, the slot emblem at 16 px top-left, and a status glyph slot top-right
  - the keylined 2 px player-colour ground ellipse beneath, and the code-drawn hp bar under the card
- **Sizes:** rulers' cards are 1.25× and get the outer gilt border; commanders' cards are 1.1× with the standard glyph; large units' cards are 1.25×.
- **Facing:** portraits face left (C-portrait), so the left side's cards flip to face right. Sprites (§4.3) are the other way round: art faces right and the right side flips.
- **Motion:**
  - attack: a lunge 24·s px toward the target over 0.12 s and back over 0.18 s; impact at 0.12 s
  - hit: a 3 px horizontal shake for 0.15 s and the 40% negative tint
  - death: the card tips 90° toward its own back edge over 0.4 s and stays at 40% opacity
  - rout: the card flips and slides to the back edge over 1.0 s, fading out
- **Effects:**
  - projectile: a 10 px white dot with a 24 px tapering trail (the Regent's is gilt `#E6B84E`)
  - impact: a code-drawn 8-point star (white core, ink outline) for 0.2 s, at 1.6× size for big hits
  - dust: three grey circles growing and fading over 0.4 s

### 4.3 sprite animation (when art lands, M3-6)
States follow the bible §4.1 exactly: idle, move, attack, hit and death, with the sheet layout and sidecar JSON there. In the battle:

| state | when | how |
|---|---|---|
| idle | standing | loop at 8 fps; start frame = hash(fighter id) mod 15, so crowds don't bob in step |
| move | deploy step, rout flight | loop at 12 fps; the engine translates the figure |
| attack | each attack | one-shot at 16 fps. Melee: the engine moves the figure toward the target by min(48·s px, 25% of the distance) and back during the clip, and the impact lands on the sheet's `impact_frame`. Ranged: the projectile spawns on `release_frame` at the sidecar's `muzzle` offset (default (40, −60) from the feet anchor at s = 1) |
| hit | each hit taken, unless it is attacking | one-shot at 12 fps (0.75 s) |
| death | at the wounds beat | one-shot at 12 fps (1.33 s), then hold the last frame; dust at the feet |

- **Display size:** 96·s px figure height for human-sized figures, and large figures at the same scale (120-160·s px), as the bible's ship cells give.
- **Fallback:** per figure. A unit whose `assets/units/<faction>/<unit>/<unit>.tres` is missing uses its card, so a battle can mix art and cards.

### 4.4 projectiles and impacts
- **Projectile by attacker:**

| attacker | projectile | speed | arc apex |
|---|---|---|---|
| Volley (Crossbowmen) | bolt | 1400 px/s | 8% of distance |
| Skirmish (Fangthrowers) | javelin | 900 px/s | 18% of distance, rotating along the path |
| the Ever-Regent | arcane bolt | 1100 px/s | straight |

  - Flight time is clamped to 0.15-0.45 s (the speed adjusts).
  - Every other attacker is melee (lunge). The mapping is one data table in the battle UI.
- **Impacts:**
  - normal hit: `hit_impact` at 96·s px
  - big hit (damage ≥ 8: charges, 10-kept rulers, frenzied Tuskers) or the first Charge hit of each side: `big_impact` at 160·s px
  - a ruler falls: `ruler_fall`
  - impacts are additive and centred on the target's upper body
  - death, a missed projectile, rout, and the Knights' first step in round 1: `dust_puff`
- **Pools:** 48 impacts, 96 projectiles and 32 floating numbers alive at once. An effect that finds its pool full is skipped, not queued: effects are cosmetic and the bars carry the facts.

### 4.5 screen shake
The bible §2.5 limits apply: code only, ≤ 6 px, ≤ 0.25 s, big hits only.
- **Triggers, and nothing else:**

| trigger | amplitude | duration |
|---|---|---|
| a hit with damage ≥ 8 | 3 px | 0.15 s |
| the first Charge hit of each side in round 1 | 4 px | 0.20 s |
| a ruler falls | 6 px | 0.25 s |

- **Rate:** at least 0.75 s of real time between shakes. A shake that comes too soon is dropped, not queued, so 4× never jitters.
- **Off:** while paused or scrubbing, with reduced motion, or with the screen-shake setting off.
- **Motion:** a decaying offset, two thirds horizontal and one third vertical, with its phase taken from the event index (no RNG).

### 4.6 auras and area markers (code-drawn, bible §2.5: caster colour, keylines, 15% fill, emblem)
- **Morale auras:** a ring at the source's feet, radius 40·s px, in its side's colour.
  - **▲** for its own side's morale: commander +2, Inspire +2, ruler +2.
  - **▼** for enemy morale: Fury −2 per bear (at most −3), Dread −1 or −2.
  - At each morale beat, ▼ auras send one ring wave out to 120·s px over 0.5 s.
  - When the source falls, its aura fades over 0.3 s, and its side's notch moves at the next morale beat.
- **Reach on hover:** the enemies the hovered fighter can reach get a 2 px white outline. A shielded fighter shows a small shield glyph.
- **Exposed rank:** when the round's `reach` adds a side's tier 1 (or tier 2) for ordinary attackers, that rank gets the exposed glyph, and the caption explains it (§4.8).

### 4.7 morale and rout
- **Break notch:** a white 3 px line with an ink keyline on the side's strength bar. It marks the hp where the side breaks.
  - Position: share 1 − break_pct/100.
  - Label: the exact threshold, "breaks at 26 hp or less". That is the largest hp h with roundi(100 × (hp_start − h) ÷ hp_start) ≥ break %, computed in `BattleExplain`. Example: hp_start 76, morale 9 (break 65%): at 27 hp the loss rounds to 64%, at 26 hp to 66%.
- **When morale changes** (a commander or ruler falls, a bear falls), the notch slides over 0.4 s with a tag: "−4 morale: the Knight Captain fell (commander +2, Inspire +2)".
- **Breaking:** at the morale beat, a side whose loss reached its break % gets "BROKE" with a broken-banner glyph, and its survivors flee (§4.1).
- **Iron Discipline:** when it holds, a gilt chain glyph sits on the notch and on the holding commander, and the caption says so. On round 8 (`iron_last_round`): "Iron Discipline holds a line only until the last round."

### 4.8 readability: strength bars, captions, result card
**Strength bars (top bar, always visible), one per side, 520×22 px:**
- the fill is hp left as a share of `hp_start`, in the side's colour with keylines, with the side's emblem at the bar's start
- pending damage is a hatched negative-red chunk at the fill's end, so the pattern carries it as well as the colour
- the break notch (§4.7)
- underneath: "38 / 76 hp · morale 9 · breaks at 26 hp or less"
- the plaque beside it: the emblem at 24 px, the faction name, "attacking", "defending" or "arrived", and the terrain and fort chips

The two bars answer "who's winning" at any moment: whoever is further above their notch.

**Round captions** (`BattleCaptions.for_round(log, report, n)`, pure, M3-2):
- They appear in the caption strip at the end of round n's morale beat, at most two lines, 18 px.
- Each line carries a `factor` id from the report's factor ids when one applies, and a codex link (the viewer's `FACTOR_ENTRIES` map).
- Line 1 is the first rule that matches, in this order:
  1. **A side left:** "Round 3: Thornmane Clans broke: it had lost 73%, and morale 7 holds only to 55%." If a part was decisive, line 2: "Fury (−2 morale) made it break a round sooner." (factors `rout`, `Fury`, `ability_dread`)
  2. **A ruler fell:** "Round 2: King Corvane I fell in the front rank (26 hp, 4 kept power)." (factor `ruler`)
  3. **A morale part held a side:** "Round 2: the Knight Captain kept Aurel Crown's line (+2 morale): it has lost 62% and holds to 70%; without him, 60%." (factors `morale_commander`, `morale_Inspire`, `morale_ruler`, `mandate_iron_discipline`)
  4. **A rank became reachable:** "Round 3: Aurel Crown's Crossbowmen are exposed: only 1 front-rank fighter stands in front of 2 in the second rank."
  5. **The round's biggest `round_end.impact` among the report's chosen factors:** "Round 1: the Knights' charge added about 8 damage." (factors as in the report)
  6. **Otherwise the round's totals:** "Round 4: Aurel Crown dealt 12 (3 of 4 hits), Thornmane Clans dealt 9 (2 of 3)."
- **Line 2,** if line 1 didn't use it: luck, when one side's dealt − expected this round is at least 5 and at least 25% of expected. "Lucky round for Aurel Crown: 20 damage where about 12 was expected." (factor `luck`)

**Result card** (0.8 s after `end`; Skip goes straight to it):
- the report's result sentence in gilt
- "Why:" with the report's why, one chip per chosen factor, each linked to the codex
- per side: fighters lost of the starting count, and hp left
- ruler lines, the Feast line and the aftermath sentence
- buttons: **Watch again** (R), **Full report**, **Next battle (2 of 3)** (N), **Back** (Esc)

---

## 5. controls and hover

### 5.1 the control bar
- **Row 1 (y 760-800):** the round scrubber, 1200 px wide: one tick per round (1 to `rounds`), the playhead, and key-moment icons on the bar. Click or drag anywhere: the field shows that point's state from the timeline at once.
  - Animations don't replay while dragging.
  - On release, playback resumes from the start of the nearest attack beat if it was playing.
- **Row 2 (y 812-884):** Restart · Play/Pause · 1× · 2× · 4× · Skip to end │ First to fall · Charge · Ruler falls · Turning point · Rout │ Legend · Why · Settings · Close.
- **Defaults:**
  - The first battle ever watched plays at 1×. The last chosen speed is remembered after that.
  - Every button has a tooltip that names its shortcut.

### 5.2 key moments (`BattleMoments.key_moments(log)`, pure, M3-2)
Each moment is `{"kind", "round", "event" (index), "fighter" (id or −1), "text", "codex"}`.
- **Jumping:** the playhead goes to the moment's display beat minus a 0.5 s lead-in and keeps the current play/pause state.
- **Missing moments:** a button with no moment is disabled with the reason, for example "No charge: neither side has Charge."

| kind | definition | text example |
|---|---|---|
| `first_blood` | the first `death` event: the first fighter to fall, not the first hit (that always comes in the first second) | "First to fall: Aurel Crown's Spearmen, round 2." |
| `charge` | the first round-1 `attack` with `bonus.Charge` | "Aurel Crown's Knights charge: +4 damage on each hit this round." |
| `ruler_falls` | each `death` of a ruler fighter (the button steps through them) | "King Corvane I falls in round 2." |
| `turning_point` | below | "Turning point, round 3: from here on Aurel Crown stayed further from breaking." |
| `rout` | each `rout` or `destroyed` event | "Thornmane Clans breaks in round 3." |

**Turning point.** A side's margin after round r = its `break_pct` − `lost_pct` from that round's morale event. Margin 0 is `start_morale.break_pct`, and a side that is out keeps its last margin.
- The leader after round r is the side with the larger margin. On a tie there is no leader.
- **The turning point** is the first round r ≥ 1 such that the eventual winner is the sole leader after every round from r to the last, and was not the sole leader after round r − 1.
- **No turning point** when:
  - the winner led from round 0 (the button says "Aurel Crown was ahead from the start")
  - the battle lasted one round
  - it ended in a mutual rout or at the round cap (the result card explains those)

### 5.3 keyboard
| key | action |
|---|---|
| Space | play / pause |
| 1 / 2 / 3 | 1× / 2× / 4× |
| ← / → | previous / next round start |
| , / . | previous / next event (while paused) |
| Home / End | restart / skip to end |
| M | next key moment of any kind |
| Tab / Shift+Tab | select the next / previous fighter (left side first, front to back) |
| Enter | pin the selected fighter in the why panel |
| L / W | legend / why panel |
| F1 | codex for the hovered element (the existing convention, as is right-click) |
| Esc | close the legend, else close the screen |

### 5.4 hover: what it's doing and why
Hovering shows the tooltip after 0.25 s, at once while paused. Clicking pins it in the why panel. All text comes from `BattleExplain` (pure, M3-2), built from the attack event's own parts and the resolver's constants (`HIT_PER_POINT`, `MIN_HIT`, `MAX_HIT`, `MIN_DAMAGE`), and rendered with `TooltipText.from_breakdown`.
1. **Who:** "Spearmen · Aurel Crown · front rank" (or "· ruler, 4 kept power", "· commander").
2. **Hit points:** "6 of 8 (5 more coming this round)".
3. **Doing now:** one of
   - "attacking Tuskers, one of the 4 enemies it can reach"
   - "waiting for the next round"
   - "fell in round 2 after 3 attacks (2 hits, 9 damage)"
   - "fled"
   - "won, still standing"
4. **Hit chance:** "68% = base 60 + 4 × (attack 10 − defense 8)", with the parts underneath (whatever they are for this attack):
   - "attack 10 = Spearmen 9 + Royal Armories 1"
   - "Tuskers' defense 8 = Tuskers 4 + forest 2 (defending) + fort 2"
   - the clamp line when the 30-90% limits applied
   - the Drilled Ranks base line when the base is 70
5. **Damage on a hit:** "3 = half of attack 10, rounded up (5) − a quarter of defense 8, rounded down (2)". Minimum 1, and a Charge line in round 1 when it applies.
6. **The roll:** "Rolled 37 of 100: a hit (68 or less hits)."
7. **Who can reach it:** one of
   - "every enemy (front rank)"
   - "only enemies with Skirmish: 3 front-rank fighters shield the 2 in its rank"
   - "nobody yet: units still stand in front of it"
8. **What it gives:** for example "+2 morale to its side while it stands (commander)" or "−2 morale to every enemy side while it stands (Fury)".
9. **Codex:** a line naming its entry ("F1 or right-click: the codex").

Between rounds and after the battle, lines 4-6 show its last attack.

---

## 6. entry points
- **Turn report:** each battle row gets **Watch** beside the existing "Battle report" button. Its tooltip: "Play this battle back. The playback shows exactly what the report describes."
- **Battle report viewer:** **Watch** in the header beside Close. The result card's **Full report** goes the other way.
- **Watch your battles (N):** at the top of the turn report, when the last turn had battles your faction fought.
  - It plays them in report order. The result card's Next battle moves on, and Back returns to the report.
  - With two factions every battle is yours. A future third faction's other battles would get "Watch battles (N)".
- **Auto-watch setting,** "Start each turn by watching my battles": off by default.
  - When on, the queue starts after the handoff (or at once with one human) and before the report. Esc goes to the report.
- **The AI's battles are watchable,** exactly like a human opponent's: every battle in the report has Watch.
- **Hotseat safety:** watching happens only inside the current player's ORDERS phase, never behind the handoff cover. Battles are public (M2 has no fog), and the battle screen shows nothing of this turn's queued orders.
- **Watch is disabled, with the reason, when:**
  - the battle has no log (fought with the test resolver): "This battle was fought with the test rules and has no playback."
  - it had more than two sides
  - its log is truncated
- **Hosting:** the battle screen is a full-rect overlay that `GameScreen` hosts, like the viewer. `GameScreen.watch_battles(events, start := 0)` opens it, and the screen's signals are `closed`, `codex_requested(key)` and `report_requested(event)`.
- **Settings:** a new `user://settings.cfg` (ConfigFile), the game's first settings file, in section `[battle]`:

| key | default |
|---|---|
| `watch_at_turn_start` | false |
| `speed` | 1 (1, 2 or 4) |
| `reduced_motion` | false |
| `screen_shake` | true |
| `why_panel_open` | true |
| `first_hint_seen` | false |

  A missing or broken file means the defaults, with no error. The settings panel opens from the battle screen and the title screen.

---

## 7. approachability (mandatory; every M3 ticket ships its own part)

### 7.1 legend
The **Legend** (L) lists every visual on the screen. Each row shows the visual, drawn by the same function the field uses, with a one-line meaning and a codex link:
- side ring, ellipse and emblem
- the gilt ruler ring and the commander's standard
- the three rank columns
- the hp bar, with its hatched pending damage
- the fallen marker
- the strength bar, its notch, and "BROKE"
- the ▲ and ▼ auras
- each status glyph: Shield Wall, Berserk, Blood Frenzy, shielded, exposed, Iron Discipline
- the three projectiles
- normal and big impacts
- "shake means a big hit or a fallen ruler"
- white numbers and grey "miss"
- the five key-moment icons

### 7.2 codex entries (`RulesCodex`)
**New:**
- `battle_playback`: what the screen shows; that it never changes the result; that it shows the same rolls as the report.
- `battle_formation`: ranks on screen, the defender on the right, and that places within a rank are only for show.
- `battle_strength`: the strength bar and its break notch.
- `battle_pending_damage`: damage lands at the end of the round, so a fighter that falls still strikes.
- `battle_key_moments`: the five moments, including the turning point's definition.
- `battle_auras`: ▲ and ▼ rings: commander, Inspire, ruler, Fury, Dread.

**Updated:**
- `battle_rounds`: "Watch any battle from the turn report"
- `battle_morale`: the notch on the strength bar
- `battle_commanders`: the back line on screen

No term on the screen goes without an entry (brief rule 7).

### 7.3 the "why did that happen" panel
Docked right, 384 px wide, and synced with the playhead. It shows, top to bottom:
1. **Now:** the current beat in one line, for example "Round 2 · damage lands: 3 fighters fell."
2. **This round:**
   - the round's caption lines (§4.8)
   - the totals: "Aurel Crown dealt 20 (2 of 3 hits, about 12 expected) · Thornmane Clans dealt 0 (0 of 3, about 7 expected)"
   - a feed of the round's notable events: deaths, exposed ranks, morale checks, charges, big hits, lucky hits (chance ≤ 40%) and unlucky misses (chance ≥ 80%). Clicking an entry jumps to it.
3. **Selected fighter:** the pinned §5.4 breakdown.
4. **The report's why:** the chosen factors as chips. A chip lights up when that factor has worth in the current round, for example "Charge: +8 this round".

Every line is right-click / F1 linked to the codex (`CodexLink.attach`).

### 7.4 accessibility
- **Colour plus shape:**
  - The emblem goes with the colour on every side element: plaque, bar, ellipse and card border.
  - Pending damage is hatched. Hit and miss are words.
  - Auras are ▲ and ▼, the break line is a line with a label, and "BROKE" is a word with a glyph.
  - Nothing relies on colour alone, so the screen is playable in greyscale.
- **No flashing above the safe threshold** (WCAG 2.3.1, three flashes per second):
  - no full-screen or large-area flashes at all; a ruler's fall uses slow motion, not a white-out
  - impact effects stay above 80% opacity for at most 2 frames (bible §2.5) and cover at most 192×192 px at s = 1
  - **a flash limiter:** at most 3 bright-frame starts per rolling 1.0 s of real time anywhere on screen; further impacts in that window start after their flash frames
  - nothing blinks: no blinking tags, bars or text
- **Reduced motion** (setting, default off):
  - no shake, no lunges (attacks play in place), no slow motion and no aura waves
  - the deploy step is instant
  - impacts become a static ring for 0.3 s
  - routed figures fade where they stand
  - projectiles still fly (they are information), in straight lines
- **Text:**
  - at least 12 px everywhere, numbers 16 px
  - text contrast ≥ 4.5:1, numbers and tooltips ≥ 7:1 (bible §2.5)
  - floating numbers carry an ink outline, so they read on any terrain
- **Keyboard:** everything works from the keyboard (§5.3), and Tab focus reaches every control.
- **First visit:** the first time the screen opens, a one-line hint: "The bars show hit points left; the white notch is where a side breaks. Hover anyone to see what it's doing and why." It has a Got it button and is remembered as `first_hint_seen`.

---

## 8. performance

### 8.1 target and method
- **Target hardware:** integrated graphics of the Intel UHD 620 class (2017-2019 laptops), OpenGL 3.3 through the GL Compatibility renderer, 8 GB RAM, a 1920×1080 window.
- **Method:**
  - The studio has no such machine. The playtester measures on the build box and on Alex's Mac with the `-- --perf` overlay (M3-7), and the budgets below leave about 2× headroom there.
  - CPU budgets are also checked headless in `tests/`.
- **Test battle:** the biggest fixture, the 277-fighter, 898-attack battle from §1.3, regenerated into `tests/fixtures/battles/` by `tools/battle_log.gd`.

### 8.2 budgets
| what | budget |
|---|---|
| frame time while playing, any speed, with art | p95 ≤ 16.7 ms (60 fps), max ≤ 33 ms, including the frames a battle starts, ends, skips or seeks |
| playback CPU per frame (headless test, fixed 1/60 s steps) | ≤ 2.0 ms average and ≤ 4.0 ms max on the build box |
| draw calls per frame (`RENDER_TOTAL_DRAW_CALLS_IN_FRAME`) | ≤ 300 |
| battle textures in memory | ≤ 192 MB, loaded when the screen opens and freed when it closes |
| Watch to first frame | ≤ 1.0 s with art, ≤ 0.3 s with placeholders |
| log and timeline in memory, biggest battle | ≤ 8 MB |
| recording cost | ≤ 25% added to the biggest fixture's resolve time; 0 with `record = false` |
| regenerating one battle's log | ≤ 1.0 s for a 60-turn game |

### 8.3 how the budgets are met
- **Batching:**
  - Each unit type's state sheet is one atlas texture, so its figures batch.
  - hp bars, ellipses, notches and glyphs are drawn by one overlay node per side in `_draw()`.
  - Floating numbers share one font.
- **Pools** (§4.4) and no per-frame allocations. Seeking uses round keyframes plus at most one round of events (≤ 600).
- **Preloading:** when the turn report opens, a threaded preload (`ResourceLoader.load_threaded_request`) starts on the sheets for the battles it lists.
- **Textures are imported lossless,** with no VRAM compression, to keep the cel outlines crisp. Worst case, from ship cells as RGBA8:

| figure family | per figure |
|---|---|
| standard | 4 × 2.36 + 1.33 = 10.8 MB |
| reach | 14.4 MB |
| large | 24.2 MB |

  The heaviest pair of rosters (the Crown with King or Regent against the Clans with the Great Thornmane) is 70.9 + 80.8 = 151.7 MB, plus about 14 MB for effects and backdrops: about 166 MB.
- **Massed-battle thinning** (§3.4).

---

## 9. assets

### 9.1 the list (minimal for M3)
All rows follow the bible: Bright Cel blocks, `art_style: Cel-Shaded`, positive prompts, keyframed attacks, `frame_size: -9`, forge, the gates in §4.1/§4.2, candidates never committed, a ledger for every call. The art lead writes the literal prompts and gates in M3-8. This is the list and the budget.

**Figures:** 12, each a base frame plus idle (16 frames, 15 used), move (16, 15 used), attack (16, keyframed), hit (9) and death (16). That is 23.0 cr each (bible §4.1).

| # | figure | path under `assets/units/` | canvas | class read | base pose: what the hands hold | strike pose (keyframe) | style anchor |
|---|---|---|---|---|---|---|---|
| 1 | Spearmen | `kingdom/spearmen/` | reach 512×384 | infantry | spear upright, round shield | lunging, spear thrust level to the right | unit anchor c3 (probe spearman) |
| 2 | Crossbowmen | `kingdom/crossbowmen/` | standard 384 | ranged | crossbow across the chest | crossbow levelled to the right at the shot (`release_frame`) | Spearmen pick |
| 3 | Knights | `kingdom/knights/` | large 576 | mounted | lance upright | horse lunging, lance couched level to the right | Spearmen pick |
| 4 | Knight Captain | `kingdom/knight_captain/` | standard | commander | sword raised above the head | sword cut down to the right | Spearmen pick |
| 5 | King Corvane | `kingdom/aurel_king/` | standard | infantry | crowned helm, longsword and kite shield | longsword cut to the right | Spearmen pick |
| 6 | the Ever-Regent | `kingdom/ever_regent/` | standard | caster | sunstone staff with a glowing focus | staff thrust forward, casting to the right (`release_frame`) | Spearmen pick |
| 7 | Tuskers | `beasts/tuskers/` | standard | heavy infantry | stone-headed club on the shoulder | club swung down to the right | **greyscale copy** of c3 (bible §3 rule 3, the leak rule) |
| 8 | Fangthrowers | `beasts/fangthrowers/` | standard | ranged | bundle of javelins, one raised | javelin thrown to the right (`release_frame`) | Tuskers pick |
| 9 | War Bear | `beasts/war_bear/` | large | monster / beast | (claws) | rearing swipe to the right | Tuskers pick |
| 10 | Warchief | `beasts/warchief/` | standard | commander | horned-skull totem staff upright | staff smashed down to the right | Tuskers pick |
| 11 | the Great Thornmane | `beasts/thornmane_avatar/` | large | monster / beast | (briar and fur) | lunging claw swipe to the right | Tuskers pick |
| 12 | the Ninth Fang | `beasts/fang_chieftain/` | standard | infantry | bone-hilted greatblade | greatblade swung to the right | Tuskers pick |

- One sprite per ruler at every kept power, and heirs share it (Corvane II looks like Corvane I).
- The base frames double as future map tokens (bible §4.1). Wiring them into the map is not M3.

**Effects:** 7, at 5.5 cr each (bible §4.2: a still with n = 3, then forge).

| id | kind (bible §4.2) | cell, frames | used for |
|---|---|---|---|
| `hit_impact` | impact | 192, 16 | every hit (VFX anchor c1; installing the probe still saves its 1.5) |
| `big_impact` | impact | 192, 16 | hits ≥ 8 damage, the first Charge hit |
| `ruler_fall` | impact (gilt) | 192, 16 | a ruler falls |
| `dust_puff` | smoke / dust (normal alpha) | 192, 16 | deaths, ranged misses, rout, the charge step |
| `bolt` | projectile | 128, 9 | Volley |
| `javelin` | projectile | 128, 9 | Skirmish |
| `arcane_bolt` | projectile | 128, 9 | the Ever-Regent's attacks (his "spells" until M5) |

**Backdrops:**
- **Horizon bands, 3 at 1.5 cr each** (plains, forest, hills): `createImage parallax_layer`, a wide band on transparency that repeats horizontally (playbook §3). Shipped at 1024×256 and drawn 160 px tall.
- **Fort wall, 1 at 2.0 cr:** `asset` + removeBackground, a stone curtain wall with a gatehouse in high three-quarter view, facing left. Master 864×1152, shipped at 384×512.
- The bible has no class for either yet. M3-8 adds them.
- **Ground:** the M1 terrain textures, at 0 cr.

**Not generated:** status glyphs, emblems, the standard and crown glyphs and the control icons are hand-written SVG (bible §4: 24×24 viewBox, 2 px strokes, fill `#F1ECE0`, stroke `#1A1612`), made in the code tickets.

### 9.2 credits
| item | planned | with re-roll reserve |
|---|---|---|
| 12 figures × 23.0 | 276.0 | 414.0 (×1.5, bible §4.1) |
| 7 effects × 5.5 | 38.5 | 57.8 |
| 3 horizon bands × 1.5 | 4.5 | 6.8 |
| 1 fort × 2.0 | 2.0 | 3.0 |
| **total** | **321.0** | **481.5** |

**Budget: 500 Ludo credits.** Flag the director above 482. For scale, the balance after the style probe was 6,850.1 (ASSET_MANIFEST). The cheaper alternative is in §12 call 11.

### 9.3 if art is late
- **Nothing waits for art.** M3-3 to M3-7 are built and accepted on placeholders (§4.2). The loader swaps art in per figure, per effect and per terrain as files land, each with its own fallback.
- **Priority if credits or time run short:**
  1. the 8 unit figures
  2. `hit_impact`, `dust_puff`, `bolt`, `javelin`
  3. the 4 rulers
  4. `big_impact`, `ruler_fall`, `arcane_bolt`
  5. the horizon bands and the fort
- The milestone can close with cards for any figure. The director lists which in the closing note.
- The M1 portraits (PR #14) and M2 ruler portraits (M2-9) are not on `main` yet. Until they are, the cards show class glyphs.

---

## 10. out of scope for M3
- **Magic:** spells, spell effects, cast animations and area spells (M5). The Ever-Regent's arcane bolt is only the look of his ordinary attack.
- **Direct control:** orders during a battle, and pre-battle formation or orders. The brief's "formation and simple orders" need rules first, in a later milestone. M3 draws the ranks the rules already have.
- **3D,** and camera pan or zoom: the camera is fixed and always shows everyone.
- **Replay sharing:** exporting or sending logs, videos, GIFs or links. Also watching battles from earlier turns in the game; regeneration exists only for tests and the dev tool.
- **Sound and music:** not scheduled (§12 call 12).
- **Battles with more than two sides** (none in M2).
- **New rules,** balance changes and retreats.
- **Map tokens** made from the new base frames: a small follow-up after M3-9.
- **Save/load and online play.** Logs are regenerated, never saved, when save/load comes.

---

## 11. tickets
Github issues are to be cut once Alex has approved. M3-n are placeholders, and every ticket is labelled `milestone:3`. Every code ticket follows `CLAUDE.md`:
- pure rules code where it can be
- tests under `tests/`
- `tools/compile_check.gd` passes
- in-game explanation in the same PR
- a `playtest:` line in the PR

Parallel lanes:
- **M3-1 first.** M3-8 can start as soon as Alex approves (no code dependencies), and M3-9 follows it.
- After M3-1, **M3-2** (`rules/`) and **M3-3** (`ui/`) run at the same time.
- After M3-3, **M3-5** (turn report, viewer, game screen) and **M3-6** (battle screen visuals) run at the same time. **M3-4** joins once M3-2 is in. M3-4 and M3-6 both touch the battle screen, so expect one small merge.
- **M3-7** closes the milestone, with art if M3-9 has landed and with placeholders otherwise.

**M3-1 `code` `hard` Battle event log** (needs M2 on `main`)
- *Scope:*
  - recording in `AutoBattleResolver.fight` (§2.3): the `record` flag, `_reachable_tiers`, the log in `resolve_battle`'s result
  - `TurnResolver._fight`: id, turn, index, `aftermath`, `numbers.log`
  - `rules/battle_log.gd` (`BattleLog`): `validate` (plain reasons), `verify_draws`, `to_json` / `from_json`, `MAX_EVENTS`, `regenerate`
  - `GameSession.replay(…, up_to_turn)`
  - `rules/battle_timeline.gd` (`BattleTimeline`, §2.5)
  - `tools/battle_log.gd` (dump a battle from a record; `--fixtures` rewrites the fixture set)
  - at least 10 fixtures in `tests/fixtures/battles/`, each `{log, report}`: starting armies on plains; a forest defence with a fort; a Knights' charge; Skirmish past the front; Iron Discipline holding; King Corvane falling while his side wins; Dread with Feast and Blood Frenzy; the round cap with the defender holding; a border battle; the biggest measured battle (§1.3)
- *Acceptance:*
  - **Outcome unchanged:**
    - every existing test passes unmodified
    - for 500 seeded battles (the harness's starting armies plus the M2 ruler fixtures): with recording on and off, the report, the winner, the armies after `_apply_losses` and the RNG state after the battle are identical
    - `Forecast.battle_odds` text is unchanged
  - **Determinism:**
    - the same state, orders and seed give byte-identical log JSON, also after a JSON round trip of the game record
    - `verify_draws` passes for every battle of 20 AI-vs-AI autoplay games with rulers
    - `regenerate` returns the identical log for every one of those battles
  - **Consistency:** all of §2.5's cross-checks, on every fixture and every one of those battles.
  - **Size:**
    - the biggest fixture is ≤ 400 KB of JSON and recording adds ≤ 25% to its resolve time
    - a lowered cap produces `truncated: true` and leaves the outcome unchanged
    - `record()` and `history()` hold no logs
- *playtest:* run `tools/battle_log.gd` on an autoplay record and read one battle's dump next to its report in the viewer: does every attack, death and morale check match the report's rounds?

**M3-2 `code` Key moments, captions and explanations** (needs 1)
- *Scope:*
  - `rules/battle_moments.gd` (§5.2)
  - `rules/battle_captions.gd` (§4.8)
  - `rules/battle_explain.gd`: the attack breakdown, fighter status, reach, morale check and break threshold (§4.7, §5.4), as `Breakdown`-style dictionaries for `TooltipText.from_breakdown`
  - the codex entries in §7.2
  - `tools/battle_log.gd --captions`
- *Acceptance:*
  - fixture tests pin each moment, including every "none" case of the turning point (ahead from the start, one round, mutual rout, round cap)
  - every number in a caption equals the log or the report (tests parse them back)
  - `explain_attack`'s lines sum to the attack's chance (with the clamp line when it applies) and damage
  - the break threshold follows the resolver's rule: for every morale check in the fixtures, a side at the threshold hp breaks and a side at one more hp holds
  - no caption or explanation contains a raw id, and every one links a codex entry that exists
  - the same log gives the same captions
- *playtest:* read the `--captions` output for the 10 fixtures: is each round's caption the reason you would give?

**M3-3 `code` `hard` Battle screen with placeholder visuals** (needs 1)
- *Scope:*
  - `ui/battle_screen.gd/.tscn`
  - `ui/battle_field.gd`: layout (§3), backdrop with its no-art fallback, fort
  - placeholder cards and effects (§4.2)
  - `ui/battle_player.gd`: the clock and beats (§4.1), 1×/2×/4×, pause, skip
  - hp bars with pending damage; deaths and fallen markers; rout
  - strength bars and notches (§4.7, §4.8), the round counter, the result card
  - the caption strip, showing round totals until M3-2's captions land
  - `GameScreen.watch_battles`, behind a debug key until M3-5
- *Acceptance:*
  - a headless test plays every fixture at 4× with fixed 1/60 s steps, and the field's end state equals `BattleTimeline.final_state()` for every fighter and both bars
  - **playback never changes the outcome:** the game state, the event's report and log are deep-equal before and after watching
  - static test: no `SeededRNG`, `RandomNumberGenerator`, `randi` or `randf` in `ui/battle_*.gd`, and no calls to `AutoBattleResolver.fight` or `TurnResolver`
  - every fighter of every fixture gets a slot inside the field at s ≥ 0.75, and no two slots overlap
  - beat durations match §4.1 within one frame
  - it works with no art at all
  - *performance:* the biggest fixture stays within §8.2's playback CPU budget, headless
- *playtest:* watch the starting-armies fixture and a real battle at 1× and 4×: from the bars alone, can you tell who is winning at every moment?

**M3-4 `code` Controls, scrubber, hover and the why panel** (needs 2, 3)
- *Scope:*
  - the control bar (§5.1)
  - key-moment jumps, disabled with reasons (§5.2)
  - the scrubber, the keyboard (§5.3), hover and pinning (§5.4)
  - the why panel (§7.3), the legend (§7.1), M3-2's captions, codex links
- *Acceptance:*
  - **seeking equals playing:** for every fixture, the field after seeking to event i equals the field after playing to it, for every round start and 200 seeded random i
  - a jump lands on its moment's event with the 0.5 s lead-in
  - every tooltip equals `BattleExplain`'s text for that fighter at that event
  - every legend row is drawn by the field's own function
  - every control has a tooltip naming its shortcut
  - headless UI tests in the M1 style
- *playtest:* pause on a hit you didn't expect and hover the attacker and the target: can you say why it hit from the tooltip alone?

**M3-5 `code` Entry points: Watch, your battles, settings** (needs 3; best after 4)
- *Scope:*
  - Watch on turn report rows and in the viewer header
  - "Watch your battles (N)" and the queue with Next and Back
  - auto-watch at turn start
  - `user://settings.cfg` and the settings panel (§6)
  - hotseat safety, and the disabled-with-reason cases
  - the AI's battles watchable
- *Acceptance:*
  - every battle event with a log has a Watch button, and the others have their reason
  - the queue plays in report order and returns to the report
  - auto-watch starts after the handoff, never before it
  - `session.record()` and `session.turn_report()` are deep-equal before and after watching
  - settings survive a restart, and a missing or broken file gives the defaults with no error
  - headless UI tests
- *playtest:* play a hotseat turn with two battles and auto-watch on, then turn it off and use the Watch buttons. Which do you prefer?

**M3-6 `code` Sprite animation, effects and motion** (needs 3; art from 9, placeholders until then)
- *Scope:*
  - the per-figure art loader with fallback (§4.3)
  - animation states, idle phases, lunges, `impact_frame` and `release_frame` sync
  - projectiles, impacts and dust (§4.4)
  - the ruler-fall burst and slow motion
  - auras and area markers (§4.6)
  - screen shake (§4.5), the flash limiter and reduced motion (§7.4)
  - terrain, horizon and fort art with fallbacks
- *Acceptance:*
  - a figure with art and one without fight in one battle with no errors
  - impacts and numbers fire on `impact_frame` or on projectile arrival (tested with a fixture sheet JSON)
  - in the busiest fixture at 4×, no 1-second window has more than 3 bright-frame starts
  - shakes fire only on §4.5's triggers, within its limits and spacing
  - reduced motion: no shake, lunges, slow motion or waves
  - the outcome is unchanged, as in M3-3
- *playtest:* watch a Knights' charge and a ruler falling at 1×, then again with reduced motion: is the big moment still clear?

**M3-7 `code` Big battles and performance** (needs 4, 5, 6)
- *Scope:*
  - massed battles (§3.4: scale steps, panel collapse, files, thinning)
  - pools and batching (§8.3)
  - threaded preload, and freeing textures on close
  - `-- --perf`: an overlay that also logs fps, p95 frame time and draw calls to `user://perf.csv`
- *Acceptance:*
  - §8.2's budgets on the biggest fixture: the CPU ones as a headless test
  - the frame-time, draw-call, memory and first-frame ones in the playtester's measured report from the build box and Alex's Mac, attached to the PR
  - no frame above 33 ms when a battle starts, ends, skips or seeks
- *playtest:* watch the 277-fighter fixture at 1× and 4×: is it smooth, and can you still tell who is winning?

**M3-8 `design` Art lead: M3 manifest rows and bible additions** (no code dependencies)
- *Scope:*
  - `design/ASSET_MANIFEST.md` rows for every item in §9.1, with the literal prompts (style block first, positive phrasing), held items, strike poses and anchors (the leak rule for the Clans), gates and candidates
  - `design/STYLE_BIBLE.md`: a battle horizon band class, a battle prop class (the fort), the battle sky colours, and the contact-sheet rows and GIFs for animated rows
- *Acceptance:*
  - every row has id, class, canvas, frames, path, prompt, candidates, gates and status `spec`
  - the per-row credits add up to §9.2
  - bible changes bump `v` on any row they touch
- *playtest:* none; the art lead checks the rows against §9.1: everything the screen needs, and nothing else.

**M3-9 `asset` Asset builder: M3 batch** (needs 8)
- *Scope:*
  - generate the rows in §9.3's priority order
  - the bible's gates: silhouette at 32 px, feet anchor, figure L*, frame 0 = base, weapon whole in every frame, loop wrap, measured `impact_frame` / `release_frame` with a `_why`
  - the `.tres` builder script, which fails when a state is missing
  - a contact sheet and GIFs, and a ledger for every charged call
  - candidates and masters stay gitignored
- *Acceptance:*
  - the gates pass on every sheet
  - every figure plays in the battle screen at 96 and 72 px
  - the ledger stays within budget (flag above 482)
- *Budget:* 500 Ludo credits.
- *playtest:* watch the starting-armies fixture with art: does every unit read as its class at 72 px?

---

## 12. director's calls (review these first)
1. **One log, written by the resolver as it fights.** Playback reads only the log and the report. Recording is passive, and it is off for odds estimates, so forecasts cost nothing more.
2. **Logs live only with the last turn's report, in memory.** Anything older is regenerated from the game record. Logs are never saved and never go into the record. Alternative: store every battle's log in the record, which makes records about 300 KB per big battle.
3. **Truthful simultaneity.** A round's attacks play staggered and alternating between sides. Damage shows as pending and lands at the end of the round, so a fighter that falls still strikes that round. Alternative: show each hit at once, which reads faster but contradicts the rules and the report.
4. **Fixed camera.** The defender is on the right with the fort behind it; with no defender, faction id order decides. Every fighter is always on screen.
5. **Big battles are real.** AI games reach 277 fighters, 149 on one side. Every fighter stays its own figure, scaled in three steps down to the bible's 72 px minimum. Files of 2 or more come only beyond that, and no measured battle needs them.
6. **"First blood" means the first fighter to fall,** not the first hit.
7. **The turning point is measured by distance from breaking,** not by hp. Breaking decides most battles: a rout is cited in 73% of the harness battles' "why" (#41).
8. **Watching is a choice.** There are Watch buttons and "Watch your battles (N)". Auto-watch at turn start is a setting, off by default, after the brief's "people watch battles because they want to".
9. **Speeds are 1×, 2× and 4×.** A typical battle takes about 19 s at 1× and 5 s at 4×, and Skip is one key away. The first battle plays at 1×; after that, the last speed is remembered.
10. **Placeholders first.** The milestone never waits for art: portrait cards (class glyphs until the portraits merge) in player colour plus emblem. Art swaps in per figure.
11. **Art scope.** Full five-state sheets for all 12 figures (8 units and 4 rulers), 7 effects, 3 horizon bands and a fort: 321 cr planned, 482 with reserve, a budget of 500. Cheaper option: the 4 rulers as base frames only, moved by code, which saves 86 cr planned (about 129 with reserve).
12. **M3 is silent.** Sound isn't scheduled. A small battle sound batch (about 10 effects at 4.0 cr = 40 cr) would be the cheapest big upgrade afterwards.
13. **The game's first settings file,** `user://settings.cfg`: auto-watch, speed, reduced motion, shake, panel and hint.
14. **Lossless textures** (no VRAM compression) keep the cel outlines crisp. The worst case is about 166 MB per battle on screen, within a 192 MB budget.
15. **Two sides only** on the battle screen. Battles with more sides keep their written report.
16. **All on-screen names are proposals:** "strength bar", "break notch", "turning point", "first to fall", "Watch your battles".
