# ASCENDANT: M4 design spec, "paths of ascension" (MVP slice)

Status: **PROPOSED by the director (Claude session, 2026-10-04). Built provisionally under Alex's 10-4 'build an MVP you'd want to play'. Alex can change anything.**

Built on: `design/GAME_BRIEF.md` (approved: pillar 2 "commit and become", core system 2, the core loop's research step and resolution order, the approachability rules), `design/MILESTONES.md` (M1-M3 as format models, the M4 outline line), `design/M2_RULER.md` (spec format, §8 bands, §11 tickets), `design/M3_BATTLES.md`, `design/STYLE_BIBLE.md` §5 (transformations), `design/ASSET_MANIFEST.md`, the engine on `main` at f79e660 (`data/`, `rules/`, `ai/`, `tools/autoplay/`), PRs #41, #52 and #54, and issue #25. Every number is in the engine's own terms: hp, attack, defense, morale, gold, provinces, rounds, ranks, and one new one, **research points**.

**Alex: read §15 (director's calls) first.** Those are the judgement calls. Everything else follows from them.

## the short version
- **Research points** come from land: your capital yields **5** a turn and every other province you own yields **1**. No new resource to manage, no gold spent, no buildings. A typical faction makes 6 a turn on turn 1 and 11 by turn 6.
- You research **one node at a time** from one pool. Switching costs nothing; spare points are never lost. Research resolves in a new **research** phase, after income. Every node shows its **ETA in turns** before you pick it.
- Each faction has **one path of 8 nodes**: 4 ordinary nodes (two tiers), then **one fork**. Each side of the fork is an **Oath** (the lock-in, which brings a new economy rule) followed by a **transformation**. Swearing one Oath closes the other side for the rest of the game.
- **Aurel Crown, "the Sunstone Path":** the **Celestial Host** (Sunspears, winged Seraphs that dive at commanders, a tithe on every province, wounds heal across your land) or **Living Iron** (Iron Knights, the Iron Colossus, deep mines in the hills, forts that repair you to full).
- **Thornmane Clans, "the Old Ways":** the **Thorn Wild** (Thornthrowers, Briarwardens rooted in forests, forest gold, and the map itself turning to forest) or the **Blood Pact** (Bloodtuskers, Bloodsworn who drink their wounds back, cheap recruits paid for in blood, invaders who lose heart on your land).
- A transformation renames and changes one unit you already have, adds one new unit, adds a province rule and a new look, opens one new mandate for mid-game sacrifice and closes one.
- **Every Oath shows a full lock-in preview first:** what you gain, what you lose access to, every unit stat before → after, and what the units will look like (portrait placeholders until art lands).
- Paths are opt-in for now, behind **"Paths (M4 preview)"** on the new game screen, which needs Rulers. Off, M1 and M2 play byte-for-byte as before.
- The AI follows its build preset's research order and picks its side of the fork by a seeded roll.
- **Balance target:** each side of each fork wins 40-60% against the other, no transformation wins more than 65% against any other, transformations land around turns 7-11, and games stay 12-25 turns.
- 8 tickets, M4-1 to M4-8 (§14). Art: 8 portraits ship with the milestone (18 cr with reserve); the 8 battle figures follow M3's base sheets (about 300 cr in all).

---

## 1. what exists, and what M4 adds

### 1.1 the engine M4 builds on (unchanged unless this spec says so)
- **Economy:** gold only. Each province pays its base income (5-12) to its owner in the income phase. Each half of the 14-province map makes 53 gold a turn. Mandates add to it: Heavy Tithes, plus Royal Court where the King stands.
- **Units:** each faction has 3 regular unit types and 1 commander, each with one trait. Stats follow #41's breakpoint rule: every attack is odd, and every defense (counting Shield Wall) is 4k or 4k+1. So a +2 terrain, fort or Shield Wall bonus changes only the hit chance, never a whole damage step.
- **Unit modifiers** already flow through one function: `RulerRules.unit_stats` returns named parts (`mandate_<id>`). Battles (`AutoBattleResolver._unit_mods`), tooltips and the "why" all read them. M4 adds path parts to the same function, so every path effect is a named part everywhere at once.
- **Income modifiers** already flow through `RulerRules.province_income_parts`. M4 adds path lines to it.
- **Phase order (M2):** sacrifice, orders, movement, battles, capture, recruitment, income, rulers.
- **Terrain** is part of the saved state (`Province.terrain`), so a province can change terrain without a schema change.
- **Two factions only.** A faction can't be mirrored against itself, so M2 measures "keep vs spend" by Bradley-Terry against a common field (§8.4 of `M2_RULER.md`). M4's fork bands are measured the same way (§10.2).

### 1.2 what M4 adds
- A research rule, a research order and a research phase (§2).
- One path per faction: 8 nodes, one fork, two transformations (§3, §4).
- The lock-in preview (§5).
- Hooks into mandates and sacrifice (§6).
- AI research (§8), explanations for all of it (§9), autoplay bands (§10) and an art batch (§12).

### 1.3 the opt-in switch
- `GameState.with_paths(seed, builds)` is the rulers game (`with_rulers`) plus a path for every faction. The new game screen gets a **Paths (M4 preview)** tick box. Ticking it also ticks **Rulers (M2 preview)**, because §6 needs rulers.
- Without it, no path field is serialized and no research event is made. M1 and M2 games, records and tests are byte-identical to `main` (an acceptance test, §14 M4-1).

---

## 2. research

### 2.1 where research points come from
**Research per turn = 5 for your capital + 1 for every other province you own.** Provinces count as they stand in the research phase, after this turn's captures and Sworn Vassals. A capital you don't hold yields nothing (the game is over then under the M1 victory rule; the line is there for #25's "hold the capital" option).

Why provinces and not gold:
- **No new resource and no new trade-off with recruiting.** Gold balance from #41/#52 stays untouched, and the AI's recruit logic needs no change.
- **It fits the game that already exists.** Holding land is how you win. Land now pays twice: in gold and in progress.
- **The flat 5 at the capital limits snowballing.** A faction holding 4 provinces makes 8; its rival holding 9 makes 13, not twice as much.
- **It is exactly forecastable** from the board, and it explains itself in one line: "Research 11 = Crownkeep 5 + 6 other provinces".
- **Economy nodes don't double-dip.** If research came from income, Market Charters and Heavy Tithes would also speed research.

Alternatives considered (§15 call 2): a share of income (double-dips, couples to mandates), a scholars' building (needs a build order and construction, out of scope), or gold converted to research (a second sink competing with recruits, hard for the AI).

### 2.2 the pool, the target and the order
- Each faction has **one research pool** (`research_points`, a whole number, starting at 0) and **one research target** (`research_target`: a node id, or none).
- **ResearchOrder(node)** sets the target. It persists from turn to turn until the node is done or you change it, so most turns need no research order at all.
  - At most one per faction per turn. Queuing another replaces the queued one in the `OrderBook`.
  - Checked in the **orders** phase against the state after sacrifices, like every other order.
  - Legal when: the game has paths; the node is on your faction's path; it isn't researched yet; it isn't closed by an Oath you swore (§3.3); and all its prerequisites were researched by the start of this turn.
  - Rejected with a plain reason. Example: "Arbalests needs Drillyard first. Drillyard costs 10 research; you have 4 and gain 7 a turn."
- **Research phase** (§7), for each faction in id order:
  1. The pool gains this turn's research (§2.1).
  2. If there is a target and the pool holds at least its cost, the cost is paid and the node is **done**. Its effects start now (§3.4). At most one node completes per faction per turn.
  3. When a node is done, the target becomes empty, **except** when it was an Oath: then its transformation becomes the target at once (the obvious next step, and one less click; the brief's "busywork gets sensible defaults").
  4. Then the province rules of a faction's transformation run (§4.6, §4.7).
- **Nothing is ever lost.** Points left over after a node stay in the pool. Points gained with no target stay in the pool. Changing the target moves nothing; the pool simply saves toward the new node.
- When every node of the path is done, research keeps filling the pool and has no use until M5's magic research (§15 call 16). The panel says "Path complete".

### 2.3 forecasts: the ETA
`Forecast.research(state, fid, orders)` uses the same function the research phase uses. It returns `{"rate", "rate_parts", "pool", "target", "cost", "eta", "done_turn", "text"}`.
- **ETA in turns** = 1 if the pool already covers the cost (done at the end of this turn), otherwise ceil((cost − pool) ÷ rate), counting this turn as 1.
- **done_turn** = the current turn number + ETA − 1. The node is done at the end of that turn and works from the next.
- Every available node in the panel shows its own ETA "if researched next". An Oath also shows the ETA of its transformation, as "about N turns", because the rate can change on the way.
- **Text:** "Arbalests: 12 of 15 research. You gain 9 a turn (Crownkeep 5, 4 other provinces 4), so it is done at the end of this turn, and your Crossbowmen have 13 attack from turn 6. Capturing or losing a province changes the pace by 1 a turn."
- **Forecast equals result:** when no province changes hands, the node completes on `done_turn` exactly (tested in M4-1 and counted across every AI game in M4-6).

### 2.4 pacing (design intent, not a test)
Assuming a faction holds 2, 3, 4, 5, 6, 7, 7, 7... provinces at the end of turns 1, 2, 3...: research per turn 6, 7, 8, 9, 10, 11, 11, 11...; in total 6, 13, 21, 30, 40, 51, 62, 73, 84, 95, 106 by the end of turns 1-11.

| plan | order | Oath done (end of turn) | transformation done (end of turn) |
|---|---|---|---|
| rush | two tier I nodes (20), Oath (20), transformation (30) = 70 | 5 | **8** |
| middle | three ordinary nodes (35), Oath, transformation = 85 | 7 | **10** |
| round out | all four ordinary nodes (50), Oath, transformation = 100 | 8 | **11** |

Rushing transforms about three turns sooner. The skipped ordinary nodes stay open afterwards. That is the path's main decision before the fork.

---

## 3. the paths

### 3.1 shape
Every path has the same shape, so the panel, the AI and the tests treat both factions alike:

```
 tier I          tier II                 the fork (any 2 ordinary nodes)
 [I-a] 10 ──► [II-a] 15        ┌──► [Oath A] 20 ──► [Transformation A] 30
 [I-b] 10 ──► [II-b] 15   ─────┤        (swearing one closes the other side)
                               └──► [Oath B] 20 ──► [Transformation B] 30
```

- **Ordinary nodes:** two tier I (10 each, no prerequisite) and two tier II (15 each, each needs one tier I node). They can be researched in any order the prerequisites allow, before or after the fork. They are never closed.
- **Oaths:** 20 each. Each needs **any two** ordinary nodes. Swearing one (completing it) closes the other Oath and its transformation for good. The Oath brings its side's **economy rule** at once.
- **Transformations:** 30 each. Each needs its own Oath. A transformation brings the new unit, the changed unit, the province rule, the look and the mandate change.
- **Full path:** 100 research. A faction can complete at most 6 of its 8 nodes.

### 3.2 node effects: the vocabulary
Every node effect is one of these, stored as data in `data/paths.gd` (`PathData`), applied by `rules/ascension_rules.gd` (`AscensionRules`), and read by every screen through the same functions:

| effect | engine meaning | read by |
|---|---|---|
| `unit` | `{type_id: {stat: n}}`: named part `path_<node>` on hp, attack, defense, morale or cost of that **regular** unit type | `RulerRules.unit_stats`, `unit_max_hp`, battles, prices, tooltips |
| `income_terrain` | `{terrain: n}`: every province of that terrain you own earns n more (or less) gold; never below 0 in total | `RulerRules.province_income_parts` |
| `tithe_per_province` | your capital earns n gold for every province you own, the capital included | `province_income_parts` |
| `capture_gold` | when your armies capture a province (not by Sworn Vassals), you gain n × its base income in gold, once | capture phase |
| `blood_levy` | regular recruits cost cost − floor(cost ÷ n) and arrive missing floor(max hp ÷ n) hp (never below 1) | `recruit_price`, recruitment phase |
| `forest_stride` | road moves through and into forest (§4.8) | `TurnResolver.check_move`, `Forecast.move` |
| `new_unit` | a `UnitType` added to the faction's roster | recruitment, battles, AI |
| `rename` | `{type_id: name}`: the changed unit's new name | roster, every report |
| `province_rule` | one of `hallowed_land`, `forges`, `wild_spreads`, `dread_lands`, with its value | research phase or battles |
| `opens_mandate`, `forswears` | a mandate that can now be bought by sacrifice; a mandate that no longer can | `RulerRules.available_mandates`, `sacrifice_check` |

**Stat rules (after #41):**
- Path attack parts are always **+2** (one whole damage step, on purpose). Never +1 or +3.
- Path defense parts always land a unit, counting Shield Wall, on **4k or 4k+1**. So terrain, forts and Shield Wall still change only the hit chance.
- hp, morale and cost parts are free of breakpoints.
- Path parts apply to **regular units only**, never commanders or rulers, exactly like mandates ("rulers are not units").
- Parts stack with mandates as separate named parts. Royal Armories' +1 already makes Crown attacks even; M2 accepted that, and M4 doesn't change it.

### 3.3 the fork lock
- An Oath is **sworn** when it completes in the research phase. From then on, `path_branch` holds its side, and the other Oath and transformation are **closed**.
- Targeting an Oath is not yet a commitment. Until it completes you can change your target freely, and nothing is closed. The lock-in preview says so (§5).
- Closed nodes stay visible in the panel, greyed, with the reason: "Closed: you swore the Oath of the Dawn on turn 5."
- Completed nodes, the sworn Oath and the transformation are public: both turn reports say so, and the enemy's faction panel lists them. Your research target is yours alone (§15 call 10).

### 3.4 when effects start
- A node's effects start **in the research phase of the turn it completes**, so they count from the next turn's orders, moves, battles, recruits and income. Effects that run in the research phase itself (§4.6, §4.7) run that same turn.
- **Units already on the map change at once.** A part raising maximum hp raises current hp by the same amount. A part lowering it lowers current hp by the same amount, never below 1. This is the M2 rule for Veteran Levies by sacrifice and for a sacrificing ruler.
- **Recruits** arrive at the new maximum, except under Blood Levy (§4.5).
- **A new unit** can be recruited from the next turn, at the capital and, with Warband Muster, with the Ninth Fang.
- **A changed unit keeps its id.** Its roster entry is renamed and its stat parts apply. Every unit of that type on the map is the changed unit from that moment, and saves, records and the battle log keep working with no migration.

### 3.5 the Aurel Crown: "the Sunstone Path"

| id | name | kind | cost | needs | effect |
|---|---|---|---|---|---|
| `crown_drillyard` | Drillyard | tier I | 10 | none | Spearmen +3 max hp (8 → 11). |
| `crown_charters` | Market Charters | tier I | 10 | none | Every plains province you own earns +2 gold. |
| `crown_arbalests` | Arbalests | tier II | 15 | Drillyard | Crossbowmen +2 attack (11 → 13). |
| `crown_stables` | Remount Stables | tier II | 15 | Market Charters | Knights cost 4 less (20 → 16). |
| `crown_oath_dawn` | Oath of the Dawn | Oath | 20 | any 2 ordinary | Swears to the **Celestial Host**. **Tithe of Light:** your capital earns +1 gold for every province you own. |
| `crown_oath_forge` | Oath of the Forge | Oath | 20 | any 2 ordinary | Swears to **Living Iron**. **Deep Mines:** every hills province you own earns +3 gold, and every forest province you own earns 1 less. |
| `crown_celestial_host` | Celestial Host | transformation | 30 | Oath of the Dawn | §4.1 |
| `crown_living_iron` | Living Iron | transformation | 30 | Oath of the Forge | §4.2 |

### 3.6 the Thornmane Clans: "the Old Ways"

| id | name | kind | cost | needs | effect |
|---|---|---|---|---|---|
| `beasts_boar_hide` | Boar Hide | tier I | 10 | none | Tuskers +3 max hp (14 → 17). |
| `beasts_raiding` | Raiding Parties | tier I | 10 | none | When your armies capture a province, you take gold equal to twice its base income, once. |
| `beasts_bone_fangs` | Bone Fangs | tier II | 15 | Boar Hide | Fangthrowers +2 attack (11 → 13). |
| `beasts_forest_stride` | Forest Stride | tier II | 15 | Raiding Parties | Your armies can move two provinces in a turn through a forest you own into another forest (§4.8). |
| `beasts_oath_grove` | Oath of the Grove | Oath | 20 | any 2 ordinary | Swears to the **Thorn Wild**. **Bounty of the Wild:** every forest province you own earns +2 gold. |
| `beasts_oath_blood` | Oath of Blood | Oath | 20 | any 2 ordinary | Swears to the **Blood Pact**. **Blood Levy:** your regular recruits cost a quarter less and arrive missing a quarter of their hp (§4.5). |
| `beasts_thorn_wild` | Thorn Wild | transformation | 30 | Oath of the Grove | §4.3 |
| `beasts_blood_pact` | Blood Pact | transformation | 30 | Oath of Blood | §4.4 |

The two paths mirror in shape and cost and differ in content: the Crown's tier I economy is steady income on plains, the Clans' is a raider's windfall on capture. The Crown has no movement node because it already has King's Roads; the Clans get Forest Stride.

---

## 4. the transformations

Each transformation changes four things, as the brief asks: **the roster** (one changed unit, one new unit), **the economy** (the Oath's rule, already running), **how provinces respond** (a province rule), and **the look**. It also changes which mandates the ruler can still buy (§6).

### 4.1 Aurel Crown: the Celestial Host
*The Aurel people take the sunstone's light into themselves. Their spears shine, the faithful pay their tithe in light, and wounds close wherever the Crown's banner flies.*

| part | rule |
|---|---|
| changed unit | **Spearmen → Sunspears**: +2 max hp (8 → 10), +2 morale (6 → 8). Shield Wall stays. |
| new unit | **Seraphs** (`seraphs`): hp 14, attack 13, defense 9, morale 12, cost 24, front rank, trait **Wings** (§4.9). |
| economy (from the Oath) | **Tithe of Light**: your capital earns +1 gold for every province you own (+7 with 7 provinces). |
| provinces | **Hallowed Land**: at the end of every turn, each of your wounded units and commanders in a province you own heals 3 hp, up to its maximum. |
| mandates | Opens **Hymn of Dawn** for sacrifice. Forswears **Heavy Tithes** ("the Host takes its tithe in light"). |
| look | Sunspears in white-gold radiant armour with a pale halo (bible block **T-celestial**). Seraphs, winged, generated in that style. Your provinces' borders gain a gilt inner glow and your banner a sun ring (code-drawn). |
| plays as | A field army that stays in the field: it heals on its own land and doesn't break easily, and its Seraphs dive at commanders. That is a direct answer to commander-reliant builds such as Iron Discipline and Pack Leader. |

### 4.2 Aurel Crown: Living Iron
*The Crown binds itself to living iron from the deep hills. Its knights become walking plate, colossi stand guard, and the forts become forges.*

| part | rule |
|---|---|
| changed unit | **Knights → Iron Knights**: +4 defense (9 → 13), +4 cost (20 → 24). Charge stays. |
| new unit | **Iron Colossus** (`iron_colossus`): hp 26, attack 13, defense 9, morale 12, cost 30, front rank, trait **Iron Hide** (§4.9). |
| economy (from the Oath) | **Deep Mines**: hills provinces you own earn +3 gold, forest provinces you own earn 1 less (+7 net with the Crown's home provinces). |
| provinces | **The Forges**: at the end of every turn, each of your wounded units and commanders in a province **with a fort** that you own heals to full. |
| mandates | Opens **Forge Tithe** for sacrifice. Forswears **King's Roads** ("iron does not march fast"). |
| look | Iron Knights in dark riveted living iron with glowing orange seams (bible block **T-ironform**); the Iron Colossus generated in that style. Your forts glow at the seams on the map, and your banner gets a rivet frame (code-drawn). |
| plays as | The anvil: armies that are slow to kill, a hills economy that wants Stonegate and Blackwood, and forts to fall back to and come out of whole. Remount Stables cancels the Iron Knights' price rise. |

### 4.3 Thornmane Clans: the Thorn Wild
*The clans give themselves to the old forest. The trees walk with them, the wild follows them into every land they hold, and the woods feed them.*

| part | rule |
|---|---|
| changed unit | **Fangthrowers → Thornthrowers**: +3 defense (5 → 8). Skirmish stays. |
| new unit | **Briarwardens** (`briarwardens`): hp 26, attack 11, defense 9, morale 10, cost 24, front rank, trait **Rooted** (§4.9). |
| economy (from the Oath) | **Bounty of the Wild**: every forest province you own earns +2 gold. |
| provinces | **The Wild Spreads** (§4.6): at the end of every turn, one province you own turns to forest, for good. |
| mandates | Opens **Deep Roots** for sacrifice. Forswears **Blood Frenzy** ("the wild is patient"). |
| look | Thornthrowers in living bark, moss and briar (new bible block **T-thornwild**, §12); Briarwardens generated in that style. A grown province switches to the forest tile, with a sprout marker on the turn it grew, and your forests get a vine border (code-drawn). |
| plays as | Map control. The wild makes your land defensive (+2 defense for whoever holds a forest, and Knights charge there for only +3), pays for itself through Bounty, roots the Briarwardens, and opens new Forest Stride lanes every turn. |

### 4.4 Thornmane Clans: the Blood Pact
*The clans make a bargain with something old and hungry. Their warriors grow savage, new ones are bought with blood instead of gold, and invaders feel the land itself watching.*

| part | rule |
|---|---|
| changed unit | **Tuskers → Bloodtuskers**: +2 attack (11 → 13), −2 max hp (14 → 12). Berserk stays. |
| new unit | **Bloodsworn** (`bloodsworn`): hp 16, attack 13, defense 5, morale 9, cost 18, front rank, trait **Lifedrinker** (§4.9). |
| economy (from the Oath) | **Blood Levy** (§4.5): regular recruits cost a quarter less and arrive missing a quarter of their hp. |
| provinces | **Dread Lands** (§4.7): in a province battle in a province you own, every enemy side has 1 less morale. |
| mandates | Opens **Red Harvest** for sacrifice. Forswears **Feast of Victory** ("the pact wants wounds, not feasts"). |
| look | Bloodtuskers in crimson and black with bone spurs and red eyes (bible block **T-bloodpact**); Bloodsworn generated in that style. Your provinces get a faint crimson vignette and your banner a blood-drip edge (code-drawn). |
| plays as | Tempo and aggression. More, cheaper bodies that start every fight wounded, so Berserk and Blood Frenzy are on from round 1; Bloodsworn that heal by hitting; and a home that is costly to invade while the army is away. |

### 4.5 Blood Levy, exactly
- Every **regular** recruit (not commanders) costs cost − floor(cost ÷ 4), computed from the type's base cost like Muster Grounds and added as its own part. Both together: Tuskers 11 − 2 − 2 = 7.
- The recruit arrives with floor(max hp ÷ 4) hp missing, never below 1 hp. Max hp counts every part (Boar Hide, Veteran Levies, Bloodtuskers).
- Prices: Tuskers 9, Fangthrowers 6, War Bear 17, Bloodsworn 14 (Bloodtuskers keep Tuskers' price).
- Arriving hp: Tuskers 11 of 14, Bloodtuskers 9 of 12, Fangthrowers 6 of 8, War Bear 18 of 23, Bloodsworn 12 of 16.
- It also applies to recruits made with the Ninth Fang (Warband Muster). They arrive wounded where the Fang started the turn.
- Feast of Victory heals them to full after a win, which turns Berserk and Blood Frenzy off. That is the M2 tension, kept.

### 4.6 The Wild Spreads, exactly
- **When:** in the research phase of every turn from the one the Thorn Wild completes, after research. One province a turn; two with Deep Roots, picked one after the other, so the second may grow from the first.
- **Which:** among the provinces you own that are not forest, not a capital, and next to a forest province you own: the one with the **highest base income**, ties going to the first by id. If none qualifies, nothing happens.
- **Effect:** its `terrain` becomes `"forest"` for the rest of the game, even if you lose it later. Its base income doesn't change. Whoever holds it now gets the forest's +2 defense instead of the hills' +1/+1 or the plains' nothing, Knights' Charge there is +3 instead of +4, Rooted works there, Bounty of the Wild pays for it, and Forest Stride can use it.
- **Forecast:** the map marks the province that will grow: "Bloodfen turns to forest at the end of this turn (the Wild Spreads), if you still hold it and Deepwood then."
- **Turn report:** "The Thorn Wild spread into Bloodfen. It is forest now: whoever holds it defends with +2 defense, and Knights charge there for +3 instead of +4."
- On the mirrored map, the Clans' home has four non-forest provinces besides the capital, so the wild covers it in about four turns, then grows into whatever they take.

### 4.7 province rules, exactly
- **Hallowed Land** (Celestial Host): research phase, after the Wild Spreads. Each of your wounded units and commanders in a province you own heals 3 hp (6 with Hymn of Dawn), up to its maximum. Rulers heal on their own (M2 §1.7) and are skipped. One `path_healed` event per faction, listing the provinces.
- **The Forges** (Living Iron): research phase. Each of your wounded units and commanders in a province with a fort that you own heals to full. The forts are Crownkeep, Stonegate, Blackwood and Fangridge. Rulers are skipped.
- Mending Light (rulers phase) still comes after both and still heals only up to the maximum.
- **Dread Lands** (Blood Pact): in a **province** battle (not a border battle) in a province you owned at the start of the turn, every enemy side has 1 less morale for the whole battle, as a named morale part `Dread Lands`. It adds to Dread and Fury (§15 call 13).

### 4.8 Forest Stride, exactly
- A move order may name a `via` province, as King's Roads does: a road move from A through B to C.
- Legal by Forest Stride when: you have Forest Stride; B is next to A; C is next to B; C is not A; **B and C are both forest**; and **B is a province you owned at the start of the turn**. C may belong to anyone.
- From the movement phase on, it is exactly a King's Roads road move. It goes from A straight to C, never fights a border battle, never stops in B, and in C it is an arriving army like any other.
- With both King's Roads and Forest Stride, a road move is legal if either rule allows it. The rejection reason names both rules.
- Forecast: "moves through the forest of Wildmoor (Forest Stride) and is at Thornvale at the start of turn N".
- The map's forests form a ring (Greenglade, Thornvale, Wildmoor, Deepwood), and the Thorn Wild adds to it.

### 4.9 the new traits
One effect each, like every M1 trait. Constants live in `AutoBattleResolver`, and the text players read is built from them (`TRAIT_TEXT`, `TRAIT_SHORT`).

| trait | unit | effect | constant |
|---|---|---|---|
| **Wings** | Seraphs | Can attack any enemy fighter, whatever its rank. While an enemy commander stands, it attacks a commander (a seeded pick among them). | none |
| **Iron Hide** | Iron Colossus | Every hit on it deals 1 less damage, but at least 1. A named damage part. | `IRON_HIDE_DAMAGE = 1` |
| **Rooted** | Briarwardens | +4 defense in a province battle in a forest province, whoever holds it. Not in border battles. A named defense part. | `ROOTED_DEFENSE = 4` |
| **Lifedrinker** | Bloodsworn | At the end of each round, if it still stands, it heals half the damage its hits dealt that round, rounded up, up to its maximum. | `LIFEDRINK_DIVISOR = 2` |

- Wings reaches the second rank like Skirmish and the commanders behind the line, which nothing else does. Rulers aren't commanders (M2), so they aren't preferred. A front-rank ruler is reachable anyway, and the Ever-Regent in the second rank is reachable by Wings.
- Iron Hide is a flat step, so it is breakpoint-safe by construction: 4k / 4k+1 defenses stay safe.
- Rooted's +4 is exactly one damage step on purpose (9 → 13). With a defender's forest +2 it is 15, still 3 off each hit.
- Lifedrinker heals after damage lands, consistent with M1's "damage lands at the end of the round". A Bloodsworn that falls that round heals nothing.

### 4.10 the new mandates (by sacrifice only)

| id | name | opened by | cost (sacrifice: +1) | effect |
|---|---|---|---|---|
| `hymn_of_dawn` | Hymn of Dawn | Celestial Host | 3 (4) | Hallowed Land heals 6 hp instead of 3. |
| `forge_tithe` | Forge Tithe | Living Iron | 3 (4) | Every province with a fort you own earns +4 gold. |
| `deep_roots` | Deep Roots | Thorn Wild | 3 (4) | The Wild Spreads into two provinces each turn instead of one. |
| `red_harvest` | Red Harvest | Blood Pact | 3 (4) | After each battle you win, you gain 1 gold for every enemy fighter lost in it (fallen, or destroyed with its army). |

---

## 5. the lock-in preview (mandatory)

Choosing an Oath as your research target, from the panel or anywhere else, always opens the **lock-in preview** first. Nothing is queued until you press **Swear the Oath**. The preview is built from `AscensionRules.preview(state, fid, oath_id)`, which applies the Oath and its transformation to a copy of the state. The screen does no math of its own.

**Layout** (one dialog, no scrolling at 1600×900):
1. **Header:** "Swear the Oath of the Dawn? It leads to the Celestial Host and closes Living Iron for the rest of the game."
2. **When:** "Oath: 20 research, done at the end of turn 5 at 9 a turn. The Celestial Host then needs 30 more: about turn 8. Nothing is closed until the Oath is done; until then you can change your research freely."
3. **Two columns, side by side:**
   - **You gain** (gilt). The Oath's economy rule with your numbers now ("Tithe of Light: Crownkeep +7 gold a turn, for your 7 provinces"). Then the transformation: the changed unit, the new unit's card with its trait, the province rule ("Hallowed Land: your wounded heal 3 hp a turn in every province you own"), and the mandate it opens ("Hymn of Dawn, 4 power by sacrifice").
   - **You lose access to** (greyed, struck through). The other Oath and its economy rule, the other transformation with its new unit, changed unit and province rule, and the mandate this side forswears ("Heavy Tithes can no longer be bought by sacrifice. Mandates you already have stay.").
4. **Your units, before → after:** the roster table (hp, attack, defense, morale, cost, trait) with every changed value highlighted ▲/▼ and its old value, the new unit's row marked "new", and the units on the map that will change ("your 6 Spearmen become Sunspears: +2 hp each, now and for every recruit"). Each number has a hover breakdown, as everywhere.
5. **How they will look:** for the changed unit, the current portrait → the transformed portrait; for the new unit, its portrait. Until the art lands, placeholders (§12.3): the base portrait inside a frame in the fork's colour with its glyph, and a class-glyph card for the new unit.
6. **Buttons:** **Swear the Oath** (queues the research order) and **Back**. The research order can be withdrawn like any order until End Turn.

- Targeting a transformation after its Oath needs no preview (the lock is already made), but its card opens the same "you gain" column on click.
- **Turn report when the Oath completes:** "The Aurel Crown swore the Oath of the Dawn and set out to become the Celestial Host. Living Iron is closed to them for the rest of the game. Tithe of Light: Crownkeep now earns 1 more gold for every province they own (+7 now). Researching next: Celestial Host, about 3 turns."

---

## 6. rulers and mandates (kept minimal)

- **Transformations open one mandate and forswear one** (§4.10, §4.1-4.4):
  - The opened mandate can be bought **only by mid-game sacrifice**, at its price +1 as usual (M2 §2.4). It isn't on the pre-game build screen except as a greyed row: "opens with the Celestial Host (M4)". That teaches the system before the game.
  - A forsworn mandate can no longer be bought by sacrifice. **Mandates you already have are never removed** (M2: mandates are permanent).
  - `RulerRules.available_mandates(state, fid)` and `sacrifice_check` read `PathData`. The rejection reason names the rule: "Heavy Tithes was forsworn when the Aurel Crown became the Celestial Host."
- **This is the bridge between the two core systems:** when your people transform, your ruler can spend power to deepen what they became.
- **Rulers are not changed by paths.** They keep their stats, rank, ability and look, and path parts skip them as mandates do. A ruler's death or succession doesn't touch research or a transformation.
- **What carries through naturally:**
  - Warband Muster can recruit new units, and Blood Levy applies to those recruits.
  - Royal Court, Heavy Tithes and path income lines stack in the income breakdown.
  - Royal Armories, Veteran Levies, Blood Frenzy and Drilled Ranks stack with path parts as separate named parts.
  - Feast of Victory heals Blood Levy's wounded recruits and turns their frenzy off (the M2 tension).
  - Wings is an answer to Iron Discipline: a side holds only while its commander stands.
- **Nothing else changes in M2's rules.** Builds, kept power, sacrifice premium, succession: all unchanged.

---

## 7. turn resolution in M4 (phase order)
The fixed order. `RulesCodex "phase_order"` must say exactly this.

1. **sacrifice:** as M2.
2. **orders:** every other order is checked against the state after sacrifices. **ResearchOrder sets the research target.** Road moves check King's Roads or Forest Stride.
3. **movement:** as M2. Forest Stride moves are road moves.
4. **battles:** as M2, plus the new traits, path parts, Dread Lands, and Red Harvest in the aftermath.
5. **capture:** as M2, then **Raiding Parties** gold for each province armies captured, then Sworn Vassals.
6. **recruitment:** as M2, with path prices and **Blood Levy**'s wounded arrivals.
7. **income:** province income with path lines (Market Charters, Tithe of Light, Deep Mines, Bounty of the Wild, Forge Tithe).
8. **research:** for each faction in id order: gain research, complete the target if it is paid for, apply the node (§3.4), then the transformation's province rules: the Wild Spreads, then Hallowed Land or the Forges.
9. **rulers:** as M2.

`TurnResolver.PHASES` becomes `["sacrifice", "orders", "movement", "battles", "capture", "recruitment", "income", "research", "rulers"]`. `GameSession.REPORT_PHASES` adds `"research"` after `"income"`. Determinism is as in M1/M2: factions, armies, provinces and borders in sorted id order, and every random draw from the turn's `SeededRNG`. **M4 adds no randomness outside battles.** Wings' target pick and Lifedrinker use the battle's own RNG and order.

---

## 8. AI

### 8.1 research plan, from the preset
Each build preset in `data/build_presets.gd` gains `ai_path`:

| preset | before the fork (in order) | fork weights |
|---|---|---|
| `warrior_king` (keep) | Drillyard, Market Charters | Celestial Host 1 : Living Iron 1 |
| `iron_crown` (spend) | Market Charters, Drillyard, Remount Stables | 1 : 1 |
| `regents_court` (balanced) | Drillyard, Arbalests | 1 : 1 |
| `beast_god_unbound` (keep) | Boar Hide, Raiding Parties | Thorn Wild 1 : Blood Pact 1 |
| `clan_moot` (spend) | Raiding Parties, Boar Hide, Forest Stride | 1 : 1 |
| `blood_of_the_fang` (balanced) | Boar Hide, Bone Fangs | 1 : 1 |

- **Order:** the listed ordinary nodes, then the chosen side's Oath, then its transformation, then the remaining ordinary nodes in data order.
- **The AI gives a ResearchOrder only when its target is empty or differs from its plan,** so most turns carry none.
- **The fork pick:** `AIPlayer.choose_branch(game_seed, seat, preset_id)`: a weighted pick, the first draw of `SeededRNG(AISeat.seat_seed(game_seed, seat) + BRANCH_SALT)`.
  - `BRANCH_SALT = 7`. It is its own stream, so the seat RNG's draws, and with them every M2 AI game, are unchanged.
  - It is a pure function of the seed, seat and preset, so it needs no saved AI state.
  - The autoplay can force a side (`--branches celestial_host,blood_pact`).
- **Never reads another faction's research target** (a test). It may read completed nodes and branches, which are public.

### 8.2 using what it has
- **Recruits:** `_recruit_value` values the new traits with the resolver's own constants:
  - Wings: worth more the more commanders the enemy fields.
  - Iron Hide: worth more against many low-damage attackers.
  - Rooted: by the share of forest provinces on the AI's front.
  - Lifedrinker: like Berserk.
  - Prices come from `RulerRules.recruit_price`, so Blood Levy, Remount Stables and Iron Knights' price count automatically.
- **Moves:** Forest Stride road moves follow the King's Roads logic (when they shorten a march, a return home or a recall). The capital-threat check counts enemy armies that can reach the capital by a road move this turn (King's Roads or Forest Stride).
- **Captures:** province choice already reads income. It must read `province_income_parts`, so Bounty of the Wild, Deep Mines and Market Charters steer it, and Raiding Parties adds the windfall to the value of a capture.
- **Sacrifice:** after transforming, the opened mandate goes last in the preset's sacrifice picks. Forsworn mandates are skipped (`sacrifice_check` rejects them).
- **No special behaviour in M4** for sending wounded armies to the Forges or Hallowed Land (§15 call 14).
- **Legal orders only:** zero rejections, as in M2.

---

## 9. approachability (mandatory; every M4 ticket ships its own part)

### 9.1 the research panel
- **HUD chip** on the map screen, always visible in a game with paths: "Research: Arbalests · 12/15 · end of this turn". With no target: "Research: choose a node · 14 waiting", in the attention colour. A click opens the panel.
- **The panel** (one screen, no scrolling at 1600×900):
  - **Left: the path tree** in four columns (tier I, tier II, the Oaths, the transformations), with the two sides of the fork stacked on the right and lines for prerequisites.
  - **Each node card:** name, cost, one-line effect, state, and ETA "if researched next".
    - States: **researched** ✓, **researching**, **available**, **needs** ("needs Drillyard"), or **closed** 🔒 with the reason.
    - Hover: the full effect with your numbers now ("Market Charters: +4 gold a turn now, from Crownkeep and Rivermarch"), and a codex link.
  - **Right: the research sidebar.** Research per turn with its breakdown, the pool, the target with a progress bar, and each transformation's path ETA ("Celestial Host: 50 to go, Oath 20 + 30, about 5 turns at 11 a turn").
  - **Buttons:** **Research this** on an available card. On an Oath it opens the lock-in preview (§5).
- **The enemy's path,** read-only from their faction panel: their completed nodes, Oath and transformation, and their research per turn. Never their target.
- **The faction and ruler panels** show the people: "Aurel Crown · Celestial Host", with a tooltip listing what the transformation does. Army labels don't change.
- **The victory screen** adds each faction's path: the nodes in the order taken, the Oath and the transformation, with turn numbers. So players can argue about paths as they do about builds.

### 9.2 tooltips and breakdowns
Every number explains itself on hover, through `Breakdown` (lines sum to the total, as in M1):
- **Research rate:** "Research 11 a turn = Crownkeep (capital) 5 + 6 other provinces × 1".
- **Node progress and ETA:** "Research after this turn 21 = pool now 12 + this turn 9. Arbalests needs 15, so it is done at the end of turn 5 and 6 carry over."
- **Unit stats with path parts:**
  - "Defense 13 = Knights 9 + Living Iron 4"
  - "Max hp 13 = Spearmen 8 + Drillyard 3 + Celestial Host 2"
  - "Morale 8 = Spearmen 6 + Celestial Host 2"
  - A changed unit's tooltip names both: "Sunspears (Spearmen of the Celestial Host)".
- **Province income:** "Income of Westwatch 9 = base 6 + Deep Mines 3" and "Income of Crownkeep 21 = base 12 + Royal Court 2 + Tithe of Light 7 (7 provinces)".
- **Recruit price and arriving hp:** "Tuskers 9 gold = 11 − Blood Levy 2" and "arrive with 11 of 14 hp (Blood Levy: a quarter missing, rounded down)".
- **Terrain** on a grown province: "Forest (grown by the Thorn Wild on turn 9; was hills)".
- **Every node, transformation, trait, province rule and new mandate name,** wherever it appears: a tooltip with the exact effect, what it changes for you right now, and a codex link.

### 9.3 codex entries (`RulesCodex`), all new terms
- **Research:** `research`, `research_points`, `research_order`, `research_phase`.
- **Paths:** `path`, `path_node`, `fork`, `oath`, `lock_in`, `transformation`, `forsworn`, plus `path_kingdom` and `path_beasts`.
- One per node: `node_<id>` for all 16 (an Oath's entry covers its economy rule, a transformation's covers its whole table).
- **New traits:** `trait_wings`, `trait_iron_hide`, `trait_rooted`, `trait_lifedrinker`.
- **Rules:** `tithe_of_light`, `deep_mines`, `bounty_of_the_wild`, `blood_levy`, `raiding_parties`, `forest_stride`, `hallowed_land`, `the_forges`, `wild_spreads`, `dread_lands`.
- **New mandates:** `mandate_hymn_of_dawn`, `mandate_forge_tithe`, `mandate_deep_roots`, `mandate_red_harvest`.
- **Updated entries:**
  - `phase_order` (§7) and `orders` (research orders)
  - `road_move` (Forest Stride)
  - `income` (path lines), `recruit` (path prices, Blood Levy), `capture` (Raiding Parties)
  - `terrain` and `forest` (the wild can grow forests)
  - `battle_morale` (path morale, Dread Lands)
  - `mandates` and `sacrifice` (opened and forsworn mandates)
  - `victory` (the paths taken)

### 9.4 forecasts
- **Research ETA** (§2.3) on every card and the chip.
- **The move forecast** covers Forest Stride, and Raiding Parties: "you capture it and gain 9 gold a turn, and 18 gold at once (Raiding Parties)".
- **The recruit forecast** covers path prices and Blood Levy's arriving hp.
- **The gold forecast** includes the path income lines.
- **The map marks** the province the Wild will spread into this turn.
- **Hallowed Land and the Forges:** a heal badge on each of your armies that will heal this turn, with the amount: "+3 hp each (Hallowed Land), if this army ends the turn here".
- **Battle odds** include path parts, traits and Dread Lands automatically, because they fight the real resolver.

### 9.5 turn report
New event types, each with `codex` set:
- `research_gained` (research): "The Aurel Crown gained 9 research (Crownkeep 5, 4 other provinces 4). Arbalests: 12 of 15 → done; 6 carry over." Or, when not done: "Celestial Host: 18 of 30, about 2 more turns." One per faction per turn.
- `research_done` (research): "Arbalests researched: the Aurel Crown's Crossbowmen now have 13 attack (was 11)."
- `oath_sworn` (research): the §5 text.
- `transformed` (research), to the faction itself: "Your people have become the Celestial Host. Your Spearmen are Sunspears now (10 hp, morale 8). You can recruit Seraphs (14 hp, attack 13, Wings) at Crownkeep from turn 9. Your wounded heal 3 hp each turn in every province you own (Hallowed Land). Hymn of Dawn can now be bought by sacrifice; Heavy Tithes can't."
  - To the rival: "The Aurel Crown has become the Celestial Host: ..." with the same facts.
- `wild_spread` (research): §4.6.
- `path_healed` (research): "Hallowed Land: 5 wounded fighters of the Aurel Crown healed 13 hp at Highcrag and Thornvale." / "The Forges: 3 wounded fighters healed to full at Stonegate (+17 hp)."
- `raided` (capture): "Raiding Parties: the Thornmane Clans took 18 gold from Rivermarch (twice its income). Gold: 31 → 49."
- **Unchanged event types that gain a clause:**
  - `recruited` events under Blood Levy: "... for 9 gold (Blood Levy). They arrive wounded, 11 of 14 hp, so Berserk is already on."
  - Battle aftermath with Red Harvest: "Red Harvest: the Thornmane Clans took 23 gold from the 23 enemy fighters lost."
- **"Needs you" line** when the target is empty and research is waiting: "Choose what to research: 14 research is waiting."

### 9.6 battle report "why"
`AutoBattleResolver._factors` gains these factors. Each has a clause, a brief (for odds) and a codex id.
- `path_<node>`: stat parts, measured exactly like mandate parts. "Living Iron (+4 defense on Iron Knights) turned aside about 18 damage." / "Arbalests (+2 attack on Crossbowmen) was worth about 11 damage."
- Path **morale** parts, measured like Inspire: "The Celestial Host's Sunspears (+2 morale) kept the line from breaking a round longer."
- `trait_wings`: the damage dealt to fighters only Wings could reach (commanders and a shielded second rank), measured like Skirmish's reach (#41). "The Seraphs flew over the line and struck the Warchief, for about 14 damage; the Thornmane Clans lost Pack Leader in round 3."
- `trait_iron_hide`: 1 hp for each hit taken. "Iron Hide: the Iron Colossus took 1 less damage from each of 11 hits."
- `trait_rooted`: what its +4 defense part saved, measured like terrain. "The Briarwardens were rooted in the forest (+4 defense) and took about 12 less damage."
- `trait_lifedrinker`: hp healed. "The Bloodsworn drank back 19 hp (Lifedrinker)."
- `dread_lands`: measured like Dread. "Dread Lands: fighting on the Blood Pact's own land cost the Aurel Crown 1 morale, and it broke a round sooner."
- **Report sides gain `"people"`** (`{"id", "name"}`, or none), so the header reads "Aurel Crown (Celestial Host)".
- **If M3-1's event log has merged:** log schema version 2 adds a `heal` event (Lifedrinker), Wings in each attack's reach tiers, and the new part keys. Playback shows heals as green numbers. `verify_draws` and the outcome-unchanged tests cover the new traits.

---

## 10. balance intent

### 10.1 the shape we want
- **Inside each fork, two real styles, not a ranking:**
  - Celestial Host: sustain and morale in the field, commander hunting.
  - Living Iron: durability, forts and hills.
  - Thorn Wild: map control and defensive terrain that grows.
  - Blood Pact: tempo, bodies, frenzy.
- **Each transformation should be worth about the same:**
  - its Oath's economy rule: about 6-10 gold a turn at 7 provinces
  - its roster change: about 20-30 gold of units in a 140-gold army (M2 calibration: Royal Armories ≈ 20)
  - its province rule: situational, about 5-10 gold a turn when it applies
- **Intended counters:**
  - The Thorn Wild's forests blunt Knights' Charge (+3), while Iron Knights rely on defense instead.
  - Seraphs punish commander-reliant builds. Blood of the Fang, the M2 preset that still wins 79% (#54), relies on Iron Discipline.
  - Iron Hide punishes many small hits (Fangthrowers, Tuskers).
  - Lifedrinker and Hallowed Land punish slow attrition.
  - Dread Lands punishes invading a Blood Pact home while its army is away.
- **The research decision:** rushing (transform on about turn 8) and rounding out (about turn 11 with all four ordinary nodes) should both be reasonable. The AI presets play both (§8.1).
- **Numbers are first-pass and not yet simulated.** They follow #41's breakpoint rule and M2's rules of thumb: +8 gold on one side of an even 137-gold battle already wins 71%, and morale is threshold-sensitive (−1 morale moved one test from 26% to 48%), which is why every morale effect here is 1 or 2. M4-6 measures and tunes them within §10.3.

### 10.2 autoplay bands (checked by M4-6)
- **Setup:** both seats run `AIPlayer` with paths on.
- **Cells:** every Crown side × Clans side (4 pairings) × all 9 preset pairings × both seat orders, 25 games each: 1,800 games. M2's 1,206 games took about 2 minutes with 8 jobs.
- "Decisive" means finished and not a draw. A branch pairing with fewer than 120 decisive games doubles its games.

| band | what | target |
|---|---|---|
| P1. both sides viable | per faction, side A vs side B, the Bradley-Terry head-to-head from their records against the other faction's two sides (pooled over presets and seat orders), as M2's band A | each side **40-60%** |
| P1d. direct (report) | each Crown side against each Clans side, pooled | reported |
| P2. no dominant transformation | each side against each opposing side, pooled over presets | **no more than 65%** of decisive games |
| P3. length | all games | median decisive game **12-25 turns**; at most **10%** at the 60-turn cap |
| P4. it happens | all games | median turn a faction transforms **7-11**; in **80%+** of games reaching turn 14, both factions have transformed |
| P5. paths matter (report) | all games | share of games where a battle's "why" names a path effect (target 30%+); ordinary nodes researched by the end; rush vs round-out win rates |
| P6. factions (report) | all games | Crown / Clans 40-60%. A miss goes to Alex with #25 item 4, not tuned silently |
| P7. M1 and M2 not broken | the M2 matrix (`--matrix`, paths off) | **every game record identical** to `main` for the same seeds. With paths on, band F (AI sacrifices in 15-50% of games) still passes; D and E are reported |
| P8. integrity | everything | 0 invariant violations (gold accounting counts Raiding Parties, Red Harvest and Blood Levy prices; terrain changes only by the Wild Spreads); 0 session or script errors; replaying every 10th game gives an identical final state; **0 research ETA mismatches** for targets set in a turn when no province changed hands |

Bots aren't humans: the bands prove nothing is broken or dominant for the bots. Alex's playtest is the real check.

### 10.3 tuning knobs
M4-6 may change these without asking, recording before → after in its PR and updating this file's tables (that ticket authorises the edit):
- **Research:** capital yield 4-6 (other provinces stay 1); node costs ±20% (tier I 8-12, tier II 12-18, Oath 16-24, transformation 24-36).
- **Units:** changed and new units' hp ±2, morale ±1, cost ±3. Attack only in steps of 2, keeping it odd. Defense only to values that land on 4k or 4k+1 counting Shield Wall.
- **Economy:**
  - Market Charters +1 to +3
  - Raiding Parties 1-3 times income
  - Tithe of Light 1 a province, or capped at 5-8
  - Deep Mines hills +2 to +4, forest 0 to −2
  - Bounty of the Wild +1 to +3
  - Blood Levy divisor 3-5, the same for price and hp
- **Province rules:** Hallowed Land 2-4 (Hymn of Dawn double), the Forges "to full" or 8 hp, the Wild Spreads every turn or every other turn, Dread Lands on or not stacking with Dread.
- **Traits:** Lifedrinker divisor 1-3. Wings "commanders first" on or off. Iron Hide and Rooted stay fixed (breakpoint values).
- **New mandates:** cost ±1.

Anything else, or a band that can't be met within these knobs, goes back to the director as a question for Alex.

---

## 11. engine changes at a glance (for builders)
- **Data:**
  - `data/paths.gd` (`PathData`): `RESEARCH = {"capital": 5, "province": 1}`; per faction the path id, name and 8 nodes, each `{id, name, kind, cost, requires, requires_any, branch, effects, codex, text}`; the 4 new unit types; province rule values.
  - `data/mandates.gd`: 4 new rows with `"path": <transformation id>` and `"sacrifice_only": true`.
  - `data/build_presets.gd`: `ai_path` per preset (§8.1).
  - Same style as `data/factions.gd`: const dictionaries only.
- **State** (serialized, validated, deep-copied only in a game with paths):
  - `Faction` gains `research_points`, `research_target`, `researched` (ids, in order, with the turn each was done), and `path_branch`.
  - `GameState` gains `paths: bool`.
  - The faction's `unit_types` gains the new unit and the changed unit's new name at the transformation; it is already serialized. `validate` checks that the roster matches `researched`, both ways, in plain language.
  - `Province.terrain` changes only by the Wild Spreads.
- **Pure rules** (`rules/ascension_rules.gd`, class `AscensionRules`). These are the single source for the resolver, forecasts, breakdowns, the AI and every screen:
  - `research_rate` (with parts), `node_state` (with reason), `available_nodes`, `check_research`
  - `complete_node`, `apply_node` (parts, roster, hp rule)
  - `unit_parts`, `income_parts`, `price_parts`, `blood_levy_hp`
  - `wild_spread_picks`, `heal_targets`, `forest_stride_ok`
  - `people_name`, `preview`
- **RulerRules:** `unit_stats` and `unit_max_hp` add `AscensionRules.unit_parts`; `province_income_parts` adds `income_parts`; `price_mods` adds `price_parts`; `available_mandates` and `sacrifice_check` read opened and forsworn mandates.
- **Orders:** new `ResearchOrder(node_id)`, serialized `{"type": "research", "node": id}`. `OrderBook` keeps one per faction. Old records without it load unchanged.
- **Resolver** (`TurnResolver`):
  - the phases in §7
  - `check_move` accepts Forest Stride vias
  - Raiding Parties in capture
  - Blood Levy arrivals in recruitment (`_add_recruit` takes an arriving hp)
  - the research phase
- **Battle** (`AutoBattleResolver`):
  - Wings in `_targets` (and the M3 reach tiers)
  - Iron Hide as a damage part, Rooted as a defense part, Lifedrinker at the end of the round
  - path morale parts in `_build_sides`' base morale
  - Dread Lands in `_morale`
  - Red Harvest in `_apply_losses`' result
  - the factors in §9.6, and report `people`
- **Session:** `REPORT_PHASES` adds `"research"`. `record()` needs nothing new, because paths live in `start_state` and research orders in history.
- **Autoplay:**
  - `Simulator.EVENT_TYPES` and the invariants learn the new events, gold sources and terrain changes
  - `play_game`, `autoplay.gd` and `--matrix` take `--paths` and `--branches`
  - the bands in §10.2

---

## 12. art

### 12.1 what M4 asks for
Per faction, 4 portraits: each side's new unit and each side's changed unit. Plus, once M3's base sheets exist, the matching battle figures.

| unit | kind | how (bible §5) | portrait | battle figure |
|---|---|---|---|---|
| Sunspears | Celestial variant of Spearmen | `editImage` with **T-celestial** | 1.5 | static 1.5 + 5 × `editSpritesheet` 4.0 = 21.5 |
| Seraphs | Celestial new unit (large canvas, wings) | `generateWithStyle`, style = Sunspears pick | 1.5 | 23.0 (§4.1 full figure) |
| Iron Knights | Living Iron variant of Knights | `editImage` with **T-ironform** | 1.5 | 21.5 |
| Iron Colossus | Living Iron new unit (large) | `generateWithStyle`, style = Iron Knights pick | 1.5 | 23.0 |
| Thornthrowers | Thorn Wild variant of Fangthrowers | `editImage` with **T-thornwild** (new) | 1.5 | 21.5 |
| Briarwardens | Thorn Wild new unit (large) | `generateWithStyle`, style = Thornthrowers pick | 1.5 | 23.0 |
| Bloodtuskers | Blood Pact variant of Tuskers | `editImage` with **T-bloodpact** | 1.5 | 21.5 |
| Bloodsworn | Blood Pact new unit (standard) | `generateWithStyle`, style = Bloodtuskers pick | 1.5 | 23.0 |

**New transformation block for the bible** (the art lead adds it under §5, M4-7): **T-thornwild:** `Remake the fur, hide and armour as living bark and green moss with small thorned briars and a few fresh leaves, same pose, same outline, same weapon, same coloured warpaint and trim.`

The recognisability contract (§5: IoU ≥ 0.85, same hands, same class read, one faction accent kept) applies to every variant. New units follow the leak rule: Clans units are anchored to Clans picks.

### 12.2 credits

| phase | what | planned | with re-roll reserve (×1.5) |
|---|---|---|---|
| 1, ships with M4 | 8 portraits × 1.5 | 12.0 | 18.0 |
| 2, after M3-9's base sheets | 4 variant figures × 21.5 + 4 new figures × 23.0 | 178.0 | 267.0 |
| **total** | | **190.0** | **285.0** |

**Budget: 300 Ludo credits** (flag the director above 285). Variant sheets must be made within 7 days of their base sheets (bible §5, Ludo URLs expire), so phase 2 is scheduled right behind M3-9. Cheaper option: phase 1 only (18 cr), with battle figures as code-tinted base sheets.

### 12.3 what ships with placeholders (the milestone never waits for art)
- **Variant portraits:** the base portrait inside a code-drawn frame in the fork's colour (gilt sun ring, riveted iron, vine, blood edge) with the fork's glyph.
- **New-unit portraits:** the M3 placeholder card, a class glyph in player colour plus emblem.
- **Battle figures:**
  - a changed unit with a base sheet but no variant: the base sheet with a code tint (gold, dark iron, moss green, crimson) and the fork glyph on its card
  - a new unit: the M3 placeholder card
- **Map and banner overlays:** code-drawn from the start, so they need no art: the gilt glow, forge seams, vine border, sprout marker, crimson vignette, and the banner overlays.
- **Fork glyphs:** 4 hand-written SVGs in the bible's glyph style (free).

---

## 13. out of scope for M4
- **Magic** (M5): magic schools and magic research, rituals, battle spells, Tithe of Blood, and the Ever-Regent's real spells. The brief's "magic schools" path waits for M5.
- **More than one path per faction** (the brief names military, society and magic paths) and **more than one fork per path.** The 1.0 target is 2-3 forks per faction.
- **Research buildings,** scholars, libraries or any construction. Research comes from provinces only.
- **Rulers changing with the people:** no ruler stat changes, no new ruler looks, no transformation-specific succession.
- **Commanders changing:** the Knight Captain and the Warchief stay as they are.
- **Undoing a transformation,** switching sides after an Oath, or research trading and stealing.
- **A use for research after the path is complete** (M5's magic research will be one).
- **Fog of war** (M5): paths stay public, as builds do.
- **New factions,** upkeep, population or a province loyalty system ("how provinces respond" is the four province rules only).
- **AI:** difficulty levels, a reactive fork choice, and seeking out the Forges or Hallowed Land to heal.
- **Infrastructure:** save/load files, sound, online play.
- **Issue #25's open questions:** M4 doesn't decide them, and nothing here depends on their answers.

---

## 14. tickets
Github issues are to be cut once Alex has seen this. M4-n are placeholders, and every ticket is labelled `milestone:4`. Every code ticket follows `CLAUDE.md`:
- pure rules code
- tests under `tests/`, with expected numbers derived from data, not hardcoded
- `tools/compile_check.gd` passes
- in-game explanation in the same PR
- a `playtest:` line in the PR

**Parallel lanes and file ownership:**
- **M4-1 first.** M4-7 can start now, with no code dependencies.
- After M4-1, three lanes run at the same time, each owning its files:
  - **M4-2** (`turn_resolver.gd` capture, recruitment and research steps; `ascension_rules.gd` province rules; `ruler_rules.gd` mandate checks)
  - **M4-3** (`auto_battle_resolver.gd` only)
  - **M4-4** (`ui/` only)
  - M4-2 and M4-3 both add `RulesCodex` entries: M4-2 appends after the M2 mandate entries, M4-3 after the trait entries.
- **M4-5** needs 2 and 3. **M4-6** closes the milestone.
- **M4-8** phase 1 follows M4-7; phase 2 follows M3-9.

**M4-1 `code` `hard` Research and path rules model** (needs M2 on `main`; M3 not required)
- *Scope:*
  - `data/paths.gd` with both paths (§3.5, §3.6)
  - the `Faction` and `GameState` fields, `GameState.with_paths` and the tick box on the new game screen (§1.3)
  - `AscensionRules` core: rate, node states, checks, completion, the fork lock, the Oath → transformation auto-target
  - `ResearchOrder` with `OrderBook` and serialization
  - the research phase (gain and complete) and its events (`research_gained`, `research_done`, `oath_sworn`)
  - `Forecast.research` and the `Breakdown` research lines
  - **all number effects:** path stat parts in `RulerRules.unit_stats` / `unit_max_hp` (including the §3.4 hp rule for units on the map), path income lines in `province_income_parts` (Market Charters, Tithe of Light, Deep Mines, Bounty of the Wild), and path price parts (Remount Stables, Iron Knights' cost)
  - the codex entries for research and paths
- *Acceptance:*
  - a table-driven test checks every node's legality (prerequisites, any-two, closed after an Oath, already done) with plain reasons
  - **forecast equals result:** for every node of both paths, with all armies holding, `Forecast.research` ETA and `done_turn` equal the turn it completes
  - research rate equals 5 + other provinces after captures and Sworn Vassals
  - spare points are never lost (change targets three times; the pool is conserved)
  - stat, income and price parts appear in `unit_stats`, `province_income_parts` and `Breakdown` and sum to the totals
  - to_dict/from_dict/JSON round trips keep every new field; a recorded game with research replays to an identical state
  - **with paths off:** every existing test passes unmodified, and an M2 game record from `main` replays byte-identically
- *playtest:* start a game with paths, research both tier I nodes and check each ETA against the turn it actually finished.

**M4-2 `code` `hard` Transformations on the map** (needs 1)
- *Scope:*
  - the roster change at a transformation (new unit, rename, units on the map converted, hp rule)
  - Blood Levy (prices and wounded arrivals, including Warband Muster recruits)
  - Raiding Parties (capture gold, `raided` event)
  - Forest Stride (`via` legality, forecast, two-step destinations in the orders UI)
  - the research-phase province rules: the Wild Spreads, Hallowed Land, the Forges, with their forecasts and the map marker
  - opened and forsworn mandates in `available_mandates` and `sacrifice_check`; Hymn of Dawn, Forge Tithe and Deep Roots
  - the `transformed`, `wild_spread` and `path_healed` events
  - `Simulator` invariants for the new gold sources and terrain changes
- *Acceptance:*
  - after each transformation, the roster, the units on the map and `validate` agree; a save made after it loads identically
  - the Wild Spreads picks match §4.6 on constructed boards (ties by id, capitals never, none qualifying, Deep Roots' second pick from the first)
  - Hallowed Land and Forges heal exactly as forecast for armies that hold
  - Blood Levy's price and arriving hp equal the recruit forecast
  - a Forest Stride move never fights on a border, and one into an occupied forest fights there
  - a forsworn mandate is rejected for sacrifice with its reason, and an owned one stays
  - a replay through every transformation is identical
- *playtest:* play the Clans to the Thorn Wild, watch three provinces grow, and check every forecast against the turn report.

**M4-3 `code` `hard` Battles with paths** (needs 1; parallel with 2: it reads path parts through `unit_stats` and the transformation from `researched`)
- *Scope:*
  - Wings, Iron Hide, Rooted and Lifedrinker (§4.9), with `TRAIT_TEXT` and `TRAIT_SHORT`
  - path morale parts in base morale
  - Dread Lands
  - Red Harvest
  - the "why" factors and report `people` (§9.6)
  - the trait and battle codex entries
  - the M3 log v2 additions if M3-1 has merged
- *Acceptance:*
  - fixed-seed tests pin each effect: Wings attacks a standing commander first and any rank otherwise; Iron Hide never below 1; Rooted only in forest province battles; Lifedrinker heals only if standing, after damage; Dread Lands only in province battles in provinces owned at the start of the turn
  - a constructed battle names each new trait and a path part as its top "why"
  - `Forecast.battle_odds` changes when a path part is added
  - same seed, same report
  - with paths off, every M1/M2 battle and report is unchanged (the M2 battle record tests pass unmodified)
- *playtest:* fight the same attack with and without Living Iron, then Seraphs against a Warchief-led army, and read each "why".

**M4-4 `code` Research panel and lock-in preview** (needs 1; best after 2 for the province rule texts)
- *Scope:*
  - the HUD chip, the research panel and the enemy's read-only path (§9.1)
  - the lock-in preview (§5) on `AscensionRules.preview`
  - the people line on the faction and ruler panels
  - the turn report lines and the "needs you" line
  - the victory screen's paths
  - the portrait placeholders and frames (§12.3)
  - the new mandates' greyed rows on the build screen
- *Acceptance:*
  - headless UI tests in the M1 style
  - every number on the panel and the preview has a hover breakdown equal to `AscensionRules` / `Breakdown`
  - **preview equals result:** after swearing and completing an Oath and its transformation, the roster, the prices and the income equal what the preview showed
  - a closed node shows its reason
  - the rival's research target is never on screen, also in hotseat
- *playtest:* open the panel on turn 3 and, from the lock-in preview alone, say what your army will look like and do on turn 9 under each Oath; then swear one and check.

**M4-5 `code` AI research and transformations** (needs 2, 3)
- *Scope:*
  - `ai_path` data, `choose_branch`, and research orders (§8.1)
  - trait-aware recruit values for the new units
  - Forest Stride moves and the two-step threat range
  - income-aware captures with path lines and Raiding Parties
  - the opened mandate in sacrifice picks
- *Acceptance:*
  - a headless human-vs-AI session with paths runs 30 turns with zero AI order rejections
  - the same seed gives the same branch and orders
  - M2 AI games (paths off) are identical to `main`
  - the AI never reads a rival's `research_target` (test with a poisoned value)
  - in 20 seeded AI games, every faction transforms by turn 14
- *playtest:* play a full game against the AI with each faction; does it research sensibly, swear an Oath and use its new units?

**M4-6 `code` Autoplay balance check for paths** (needs 2, 3, 5)
- *Scope:*
  - `--paths` and `--branches` in `Simulator`, `autoplay.gd` and `--matrix`
  - report sections: wins by side and pairing, transformation turns, nodes researched, rush vs round-out, "why" mentions
  - the §10.2 bands as a pass/miss table; exit code 0 only when P7 and P8 hold
  - tuning within §10.3
- *Acceptance:*
  - the report is attached to the PR, with every number change before → after and this file's tables updated
  - any band still missed is listed with why and the diagnostic behind it, as #52 did
- *playtest:* read the bands table; do both sides of each fork win, and does each transformation land mid-game?

**M4-7 `design` Art lead: M4 manifest rows and the T-thornwild block** (no code dependencies)
- *Scope:*
  - `design/ASSET_MANIFEST.md` rows for the 8 portraits and 8 figures in §12.1 (literal prompts, anchors, gates, candidates, status `spec`)
  - the T-thornwild block in `design/STYLE_BIBLE.md` §5
  - the 4 fork glyphs and the placeholder frame colours
- *Acceptance:*
  - every row has id, class, canvas, frames, path, prompt, candidates, gates and status
  - the per-row credits add up to §12.2
  - bible changes bump `v`
- *playtest:* none; the art lead checks the rows against §12.1.

**M4-8 `asset` Asset builder: M4 batch** (phase 1 needs 7; phase 2 needs 7 and M3-9's base sheets, within 7 days of them)
- *Scope:*
  - phase 1: the 8 portraits
  - phase 2: the 8 battle figures
  - the bible's gates (IoU ≥ 0.85 against the base, accent kept, faction read at 96×128, the M3 sheet gates for figures)
  - a contact sheet with base | Celestial | Iron and base | Thorn | Blood rows
  - a ledger for every charged call
- *Acceptance:*
  - the gates pass, and every portrait shows in the lock-in preview and the roster
  - the ledger stays within budget (flag above 285)
- *Budget:* 300 Ludo credits.
- *playtest:* at 96×128, can you tell each variant is still its unit, and which fork it took?

---

## 15. director's calls (review these first)
1. **One path per faction, 8 nodes, one fork, two transformations.** The brief's full picture (military, society and magic paths; 2-3 forks for 1.0) is later. This is the smallest slice where "commit and become" is real.
2. **Research comes from land:** the capital 5, every other province 1. No gold cost and no buildings. Alternatives: a share of income (double-dips with economy mandates), a scholars' building, or gold converted to research.
3. **One target, one pool, nothing lost.** Switching is free and spare points carry over. The brief's "research ETA" is a per-node forecast.
4. **The fork is two steps: an Oath, then the transformation.** The Oath is the lock-in and brings the economy rule; the transformation (about 3 turns later) brings the roster, the province rule and the look. The rival gets a turn report and a few turns to react. The lock happens when the Oath completes, not when it is ordered.
5. **An Oath needs any two of the four ordinary nodes,** and ordinary nodes stay open after the fork, so "rush or round out" is the decision before the fork.
6. **Changed units keep their id and change in place, for free.** Every Spearman becomes a Sunspear at once. A max-hp change moves current hp by the same amount (never below 1), the M2 rule.
7. **Each transformation opens one mandate (sacrifice only) and forswears one.** Owned mandates are never removed. This is the minimal link to rulers: your ruler can spend power to deepen what your people became.
8. **Rulers and commanders don't transform in M4,** in stats or in look. That saves 6 portraits and a lot of balance surface.
9. **Paths are opt-in** behind "Paths (M4 preview)", which needs Rulers. Off, M1 and M2 are byte-identical. Alternative: always on whenever rulers are.
10. **Your research target is private; completed nodes, Oaths and transformations are public.** M4 has no fog, and battle odds must count enemy transformations, as M2 did for builds.
11. **Four new traits:** Wings (attacks commanders first), Iron Hide, Rooted and Lifedrinker. Wings is also a deliberate answer to Iron Discipline builds, including Blood of the Fang (79% in #54).
12. **The Wild Spreads changes terrain for good,** even after the province is lost: the map remembers who passed. Forests help whoever holds them.
13. **Dread Lands stacks with Dread and Fury.** That can be −4 morale against a Clans home with the Thornmane and a War Bear. The knob to stop stacking is in §10.3.
14. **The AI's fork is a seeded 50/50 roll per preset,** not a reaction to the rival. The AI doesn't seek out healing provinces in M4.
15. **Fork balance is measured by Bradley-Terry against a common field,** like M2's band A, because the engine can't mirror a faction.
16. **The path is finite.** With full research done around turn 11, the pool has nothing to buy until M5 adds magic research. That is acceptable for an MVP.
17. **Art:** portraits ship with the milestone (18 cr with reserve); battle figures follow M3-9's base sheets (285 cr in all; budget 300). Cheaper option: portraits only, with code-tinted figures.
18. **First-pass numbers, not yet simulated.** They follow #41's breakpoint rule and M2's rules of thumb; M4-6 tunes within §10.3.
19. **All names are proposals:** the Sunstone Path, the Old Ways, every node, the Oaths, the four transformations, the four units, the four traits, the province rules and the four mandates.
