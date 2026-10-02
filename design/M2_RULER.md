# ASCENDANT: M2 design spec, "the ruler"

Status: **PROPOSED by the director (Claude session, 2026-10-01). Not yet approved by Alex; built provisionally so there is something to play. Alex can change anything.**

Built on: `design/GAME_BRIEF.md` (approved, "core system 1: the ruler and mandates"), `design/MILESTONES.md` (M1 format and the M2 outline), the M1 rules code on `main` at 499df09 (`rules/`, `data/`), and issue #25. Every number below is in the M1 engine's own terms: hp, attack, defense, morale, gold, provinces, rounds, ranks.

**Alex: read §12 (director's calls) first.** Those are the judgement calls. Everything else follows from them.

## the short version
- Each faction picks 1 of 2 rulers before the game. Crown: **King Corvane** (mortal line) or **the Ever-Regent** (undying archmage). Clans: **the Great Thornmane** (beast-god avatar) or **the Ninth Fang** (chieftain bloodline).
- Every ruler has a **power pool of 10**. Power you keep sets the ruler's hp, attack, defense and the rank of its one province ability. Power you spend buys mandates.
- 10 mandates in all: 6 shared and 2 exclusive per faction, costing 2 to 4 power.
- The ruler is a fighter that travels as its own army, one province per turn. Three of the rulers fight in the front rank; the Ever-Regent fights in the second rank.
- **Mid-game sacrifice:** one per turn, costs the mandate's price +1, needs a living ruler, and shows a preview before you confirm.
- **Death:** a mortal heir is crowned 2 turns later with half the kept power. The undying Regent re-forms 4 turns later with all of it. The god's avatar returns 1 turn later with 3 less, for good. Mandates always stay.
- Capturing the enemy capital still wins the game. A ruler's death never ends it.
- AI seats play one of 3 build presets per faction, chosen by a seeded roll, and give orders through the separately built `AIPlayer`.
- Balance target: keep-everything and spend-everything each win 40-60% of decisive games against each other in the autoplay check.

---

## 1. ruler model

### 1.1 ruler power
- Every ruler in M2 has a **power pool of 10**.
- **Kept power** = 10 minus the cost of the mandates picked before the game, minus later sacrifices, minus succession losses. It is a whole number from 0 to 10.
- Kept power never goes up in M2.
- Kept power sets:
  - the ruler's hp, attack and defense (§1.3)
  - its **ability rank** = 1 + kept power ÷ 3, rounded down. That gives rank 1 at 0-2 kept, rank 2 at 3-5, rank 3 at 6-8, and rank 4 at 9-10.
- Mandates are faction-wide and permanent. They stay when the ruler dies.

### 1.2 the four rulers

| id | name on screen | faction | kind | rank in battle | morale when alone | province ability | succession |
|---|---|---|---|---|---|---|---|
| `aurel_king` | King Corvane I (heirs: Corvane II, III, ...) | Aurel Crown | mortal line | front | 10 | Royal Court | heir in 2 turns, half power |
| `ever_regent` | the Ever-Regent | Aurel Crown | undying | second | 10 | Mending Light | re-forms in 4 turns, full power |
| `thornmane_avatar` | the Great Thornmane | Thornmane Clans | god | front | 14 | Dread | returns in 1 turn, −3 power for good |
| `fang_chieftain` | the Ninth Fang (heirs: the Tenth Fang, the Eleventh Fang, ...) | Thornmane Clans | mortal line | front | 12 | Warband Muster | heir in 2 turns, half power |

Flavour, one line each, for the codex and the build screen:
- **King Corvane** is an ordinary man of the Aurel line. Spend his power and he governs the best-equipped kingdom in the land. Keep it and he rides to war as a paladin.
- **The Ever-Regent** is an archmage who bound his life to the sunstone in Crownkeep. He cannot die, only be broken, and he re-forms slowly. His spells count as attacks until M5 brings magic.
- **The Great Thornmane** is the clans' beast-god, walking among them in a body of briar and fur. When the body is slain, the god takes a new one, a little less of itself each time.
- **The Ninth Fang** is the high chieftain of the old fang bloodline. When one Fang falls, the next of the blood takes the mantle.

### 1.3 stats from kept power
In the formulas, k is kept power. ÷2 is rounded down.

| ruler | hp | attack | defense |
|---|---|---|---|
| King Corvane | 18 + 2k | 9 + k÷2 | 8 + k÷2 |
| the Ever-Regent | 14 + k | 8 + k | 6 + k÷2 |
| the Great Thornmane | 24 + 3k | 8 + k | 7 + k÷2 |
| the Ninth Fang | 20 + 2k | 9 + k | 7 + k÷2 |

Full table (builders test against this):

| kept power | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| King hp | 18 | 20 | 22 | 24 | 26 | 28 | 30 | 32 | 34 | 36 | 38 |
| King attack | 9 | 9 | 10 | 10 | 11 | 11 | 12 | 12 | 13 | 13 | 14 |
| King defense | 8 | 8 | 9 | 9 | 10 | 10 | 11 | 11 | 12 | 12 | 13 |
| Regent hp | 14 | 15 | 16 | 17 | 18 | 19 | 20 | 21 | 22 | 23 | 24 |
| Regent attack | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 | 16 | 17 | 18 |
| Regent defense | 6 | 6 | 7 | 7 | 8 | 8 | 9 | 9 | 10 | 10 | 11 |
| Thornmane hp | 24 | 27 | 30 | 33 | 36 | 39 | 42 | 45 | 48 | 51 | 54 |
| Thornmane attack | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 | 16 | 17 | 18 |
| Thornmane defense | 7 | 7 | 8 | 8 | 9 | 9 | 10 | 10 | 11 | 11 | 12 |
| Fang hp | 20 | 22 | 24 | 26 | 28 | 30 | 32 | 34 | 36 | 38 | 40 |
| Fang attack | 9 | 10 | 11 | 12 | 13 | 14 | 15 | 16 | 17 | 18 | 19 |
| Fang defense | 7 | 7 | 8 | 8 | 9 | 9 | 10 | 10 | 11 | 11 | 12 |
| ability rank (all) | 1 | 1 | 1 | 2 | 2 | 2 | 3 | 3 | 3 | 4 | 4 |

For scale: the Knight Captain is 25 hp, 14 attack, 12 defense. The Warchief is 30 hp, 16 attack, 10 defense. A 10-kept ruler is worth roughly two commanders in battle. A 0-kept ruler is about a Knight.

Every ruler gives its side **+2 morale while it stands** (`RULER_MORALE = 2`). This stacks with a commander's +2. Rulers have no trait. They are not "units" for any mandate or trait that names units, so Royal Armories, Veteran Levies and Pack Leader skip them.

### 1.4 province abilities
Each ruler has one ability. It works in **the province the ruler is in** and scales with ability rank.

| ability | ruler | rank 1 | rank 2 | rank 3 | rank 4 | when |
|---|---|---|---|---|---|---|
| **Royal Court** | King Corvane | +2 gold | +3 gold | +4 gold | +5 gold | income phase: the province the King is in earns this much more, if you own it |
| **Mending Light** | the Ever-Regent | heal 3 | heal 6 | heal 9 | heal 12 | rulers phase: each of your wounded units and commanders in the Regent's province heals this many hp, up to its maximum (not rulers; they heal by §1.7) |
| **Dread** | the Great Thornmane | −1 morale | −1 morale | −1 morale | −1 morale | every enemy side in a province battle the avatar fights in. Not border battles. Stacks with Fury |
| **Warband Muster** | the Ninth Fang | 1 unit | 2 units | 3 units | 4 units | recruitment phase: you may recruit this many regular units per turn "with the Fang". They appear where the Fang is after movement and battles, if you own that province then. Same prices. Commanders still come only from the capital |

### 1.5 the ruler on the map
- **The ruler travels alone, as its own army.** That army holds only the ruler: no units, no commander. It moves one province per turn like any army (or two, by King's Roads, §2.3) and captures provinces like any army.
- It fights together with every other army of yours in the same province, or crossing the same border, as M1 already does for several armies.
- **Recruits never join the ruler's army.** A recruit joins the first army of yours by id at that place that has no ruler, or forms a new army there. So the ruler can always move on its own.
- **Army label:** `Aurel Crown ruler King Corvane I at Crownkeep`. Event text uses it the M1 way: `The Aurel Crown ruler King Corvane I at Crownkeep moved to Highcrag.`
- **Start of the game:** each capital holds the M1 starting army (army 1) and the ruler's army (army 2). The ruler is at full hp.
- **Map token:** the second gilt ring outside the player ring (`design/STYLE_BIBLE.md` §2.4, "ruler present").
- Builds are picked in secret (§4) but are public once turn 1 starts. M2 has no fog, and battle odds must count enemy mandates. Either player can open the enemy ruler's panel read-only.

### 1.6 the ruler in battle
- **Rank:**
  - **Front-rank rulers** (King, Thornmane, Fang) stand with the other units. Enemies can attack them from round 1.
  - **The Ever-Regent stands in the second rank**, with Volley units. Enemies reach him only once every front-rank fighter on his side has fallen.
  - Commanders stay behind everyone, as in M1.
- **Design intent:** a 0-kept front-rank ruler falls in about two thirds of even mid-game battles, even when its side wins. Keep a weak ruler at home. A 10-kept ruler almost never falls in an even battle.
- **Morale:** +2 while the ruler stands (§1.3). If a side has no regular units, its base morale is the highest morale among its commanders and ruler. Ruler morale values are in the §1.2 table.
- **Death in battle:** a ruler dies if its hp reaches 0, or if it is on the losing side. M1 has no retreats: every army on a losing side is destroyed, and that includes the ruler's.
- Hit chance, damage and targeting are M1's, unchanged apart from Drilled Ranks (§2.3).

### 1.7 ruler healing
At the end of every turn, in the rulers phase, a living ruler heals **25% of its maximum hp, rounded up**. For example, a 46-hp King heals 12. Regular units and commanders still never heal on their own, as in M1. They heal only through Mending Light and Feast of Victory.

---

## 2. mandates

### 2.1 rules
- Pick mandates before the game from your faction's list: the 6 shared mandates plus your 2 exclusives.
- Total cost must be 10 or less. Each mandate can be taken once.
- Kept power = 10 − total cost. An empty build keeps 10.
- Mandates take effect from turn 1 and never go away. That includes when the ruler dies.
- "Regular units" means the faction's roster units: Spearmen, Crossbowmen, Knights, Tuskers, Fangthrowers, War Bears. Not commanders, not rulers. "Fighters" means units, commanders and the ruler.

### 2.2 the list

| id | name | who | cost | effect, one line |
|---|---|---|---|---|
| `iron_discipline` | Iron Discipline | shared | 3 | Your side never breaks (routs) while one of your commanders in that battle stands, except at the end of the last round. |
| `drilled_ranks` | Drilled Ranks | shared | 2 | Your fighters' base hit chance is 70% instead of 60%. |
| `veteran_levies` | Veteran Levies | shared | 3 | Your regular units have +2 maximum hp. |
| `heavy_tithes` | Heavy Tithes | shared | 4 | Every province you own earns +2 gold per turn. |
| `muster_grounds` | Muster Grounds | shared | 4 | Recruits cost a fifth less: cost − (cost ÷ 5, rounded down). |
| `sworn_vassals` | Sworn Vassals | shared | 4 | Each turn, one neutral province next to your land swears fealty and joins you. |
| `royal_armories` | Royal Armories | Aurel Crown only | 3 | Your regular units have +1 attack. |
| `kings_roads` | King's Roads | Aurel Crown only | 2 | Armies can move two provinces in one turn inside your own territory. |
| `blood_frenzy` | Blood Frenzy | Thornmane Clans only | 3 | Your fighters below full hp have +3 attack. Tuskers' Berserk stacks with it, for +6. |
| `feast_of_victory` | Feast of Victory | Thornmane Clans only | 3 | After each battle you win, your fighters still standing heal to full hp. |

Buying everything would cost 25 for the Crown and 26 for the Clans (20 for the shared six, 5 or 6 for the exclusives), so a 10-power pool always forces a choice. Example spend-everything builds:
- Crown: Royal Armories + Heavy Tithes + Veteran Levies (3 + 4 + 3).
- Clans: Iron Discipline + Blood Frenzy + Sworn Vassals (3 + 3 + 4).

Tithe of Blood (from the brief) needs rituals, so it waits for M5.

### 2.3 exact effects
Each effect lives in the rules code (§9) and nowhere else. Tooltips, forecasts and previews call the same functions.

- **Iron Discipline.**
  - When it applies: at the end of a battle round, a side of yours that would break (lost % ≥ break %) does not break if at least one of your commanders in that battle is standing. Rulers don't count; the brief says "commander". Once the last commander falls, the normal check applies from the end of that round.
  - Not at the end of the last round (round 8, the round cap): there the normal check applies, so a line it holds past its break point can't win by lasting out the round cap (M2-8).
  - It has no downside, because M1 destroys routed armies anyway.
  - It is worth more to the Clans, whose morale is lower. That is intended.
- **Drilled Ranks.**
  - Your fighters' hit chance becomes clamp(70 + 4 × (attack − defense), 30, 90). M1's base is 60. The 30% floor and 90% cap stay.
  - Applies to every attack your units, commanders and ruler make.
- **Veteran Levies.**
  - Each regular unit's maximum hp is its type's hp + 2. New recruits arrive at the new maximum.
  - Bought by sacrifice: your existing regular units gain +2 maximum hp and +2 current hp at once.
- **Heavy Tithes.** Income phase: +2 gold for every province you own, the capital included. It is shown in each province's income breakdown.
- **Muster Grounds.**
  - Every recruit, commanders included, costs cost − (cost ÷ 5, rounded down).
  - Crown: Spearmen 7, Crossbowmen 8, Knights 16, Knight Captain 28.
  - Clans: Tuskers 9, Fangthrowers 7, War Bear 18, Warchief 28 (from the costs after the balance pass, #41).
  - Applies at the capital and to Warband Muster recruits.
- **Sworn Vassals.**
  - In the capture phase, after armies have captured provinces, your **best eligible province** joins you.
  - Eligible: it is neutral (no owner), has no army in it, and is next to a province you own after this turn's captures.
  - Best: the highest income. Ties go to the first province by id.
  - If another faction's Sworn Vassals picks the same province this turn, neither gets it, and neither picks again that turn.
  - At most one province per faction per turn. No gold changes hands.
  - The map marks the province that will join at the end of the turn. Its forecast says: "Rivermarch (9 gold) swears fealty to you at the end of this turn, unless an army ends the turn there."
- **Royal Armories.**
  - Regular units: attack = type attack + 1. Defense is unchanged: every regular unit's attack is odd and its defense breakpoint-safe (#41), so the +1 changes only the hit chance and never a damage step, also on a forest or fort (M2-8).
  - The starting army gets it too, and so do units you already have when it is bought by sacrifice.
- **King's Roads.**
  - A move order may name a **via** province, which makes it a **road move** from A through B (via) to C.
  - Legal when: you have King's Roads; B is next to A; C is next to B; C is not A; and **both B and C are provinces you owned at the start of the turn**. M1's capture rule means neither held an enemy army then.
  - From the movement phase on, a road move counts as a move from A straight to C. It never fights a border battle, because only one-step moves swap. It never stops or fights in B. If enemies are in C after movement, there is a battle in C under the usual rules.
  - The orders UI offers two-step destinations when they are legal and picks the first legal via by province id. The player can choose another.
  - Forecast: "moves by the King's Roads through Highcrag and is at Westwatch at the start of turn N".
- **Blood Frenzy.**
  - Each of your fighters whose current hp is below its maximum gets +3 attack, counted like a trait in the attack breakdown. Units, commanders and the ruler all count.
  - Tuskers' Berserk (+3) stacks with it, for +6.
  - Wounds carry over between battles (M1), so a wounded army starts its next battle in a frenzy.
- **Feast of Victory.**
  - After a battle you win, every fighter of yours still standing in it goes back to its maximum hp: units, commanders and the ruler.
  - The battle report's aftermath line says so: "Feast of Victory: the Thornmane Clans' 5 surviving fighters healed to full (+31 hp)."
  - This works against Blood Frenzy, which wants wounds. That tension is intended.

### 2.4 mid-game sacrifice
- **What:** a new order, **Sacrifice**, which names one mandate. The ruler gives up kept power and the faction gains the mandate for good.
- **Cost:** the mandate's price **+1**. For example, Royal Armories mid-game costs 5. The premium keeps the pre-game choice meaningful: "keep everything, then convert at turn 7" is legal, but it loses value.
- **Legal when:**
  - your ruler is alive
  - you don't already own the mandate
  - it is on your faction's list
  - your kept power is at least cost + 1
  - you haven't given another Sacrifice order this turn (one per turn)
- **When it happens:** in the first phase of resolution, before any other order is checked (§3). It already counts in this turn's moves, battles, recruits and income.
- The other player doesn't see it until the turn report, like any order.
- **Effect on the ruler:** kept power drops, so stats and ability rank drop at once. The ruler's current hp drops by the same amount as its maximum hp, but not below 1.
- **Queued orders:** your other orders are checked against the state with your queued sacrifice applied. So a road move or a Muster Grounds price can rely on a mandate you are sacrificing for this turn. If you cancel the sacrifice, the other orders are checked again, and any that no longer pass are removed from the list with the reason. Example: "Road move to Westwatch removed: you no longer have King's Roads."
- **Preview before confirming (mandatory):** the sacrifice dialog shows a before → after view of:
  - the ruler: kept power, hp, attack, defense, ability rank and ability effect
  - every changed unit stat and recruit price
  - income next turn
  - the battle odds of every attack you have queued this turn, fought again with the change
- Nothing changes until the player presses Confirm. The order can be cancelled like any other until End Turn.
- **Turn report:** "King Corvane I gave up 5 power for Royal Armories (4, +1 for a mid-game sacrifice). Kept power 10 → 5. Every regular unit of the Aurel Crown now has +1 attack and +1 defense."

---

## 3. turn resolution in M2 (phase order)
The fixed order. `RulesCodex "phase_order"` must say exactly this.

1. **sacrifice:** each faction's Sacrifice order is checked and applied, in faction id order.
2. **orders:** every other order is checked against the state after sacrifices. Invalid ones are rejected with a reason.
3. **movement:** one-step moves and road moves happen at once. Swaps on a border stop both sides there.
4. **battles:** border battles, then province battles, as in M1. After each battle, ruler deaths are recorded (§5.1) and Feast of Victory heals the winner.
5. **capture:** armies capture provinces as in M1, then Sworn Vassals provinces join.
6. **recruitment:** capital recruits, then Warband Muster recruits, each faction paying in the order its orders were given.
7. **income:** province income + Heavy Tithes + Royal Court.
8. **rulers:** Mending Light heals, then rulers heal 25%, then due successors arrive (§5.2).

`TurnResolver.PHASES` becomes `["sacrifice", "orders", "movement", "battles", "capture", "recruitment", "income", "rulers"]`. `GameSession.REPORT_PHASES` adds `"sacrifice"` first and `"rulers"` before `"victory"`. Determinism is as in M1: factions, armies, provinces and borders go in sorted id order, and every random draw comes from the turn's `SeededRNG`. Nothing in M2 adds randomness outside battles.

---

## 4. pre-game build screen

**Flow:**
1. On the new game screen, each seat is set to **Human** or **AI**, as well as faction and seed. M2 needs at least one human; AI-vs-AI games are only for the headless autoplay tool.
2. For each human seat in seat order:
   - a handoff screen: "Pass the computer to player N to choose a ruler and mandates. Continue only when nobody else can see the screen."
   - then the build screen.
3. AI seats pick their build silently (§6.1).
4. Builds are applied to the starting state, and the game starts with the M1 turn-1 handoff. With one human, there is no handoff: the human goes straight to turn 1.

**Layout** (one screen, no scrolling at 1600×900):
1. **Header:** "Player 1, Aurel Crown: choose your ruler and how much power to keep."
2. **Ruler picker:** two cards. Each card has a portrait (placeholder until M2-9), the name, the kind line ("mortal line · fights in the front rank"), the province ability in one line, and the succession rule in one line.
3. **Power bar:** 10 pips. Spent pips take the mandate's colour; kept pips are gilt. Text: "Power pool 10 · spent 6 · kept 4". Hover gives the breakdown: pool 10 − each mandate's cost = kept.
4. **Mandate list:** 8 rows (6 shared, then 2 exclusive tagged "Aurel Crown only"). Each row has a checkbox, the name, the cost as pips, the one-line effect, and a codex link.
   - A row that no longer fits is disabled with the reason: "Needs 4 power; 2 left."
   - Hovering a row shows exactly what it changes for this faction, e.g. "Spearmen 10 → 12 hp, Crossbowmen 8 → 10 hp, Knights 15 → 17 hp".
5. **Live preview** (updates on every click):
   - **Your ruler at this kept power:**
     - hp, attack, defense, +2 morale, rank, ability rank and its effect, each with a hover breakdown such as "attack 11 = base 9 + 2 from 4 kept power (½ per point, rounded down)"
     - the 0-kept and 10-kept values in grey beside them
     - a risk line: "Front rank: attacked from round 1. With 0 kept power it is likely to fall in a real battle."
   - **Your army:** the roster table (hp, attack, defense, cost) for units and the commander, plus the starting army. Every value a mandate changes is highlighted, with a ▲/▼ and the old value.
   - **Economy:** gold at the start, income on turn 1 (with modifiers), and recruit prices.
   - **Other effects:** one line per mandate that isn't a stat. For example, "King's Roads: two-province moves inside your land" or "Sworn Vassals: Rivermarch (9 gold) would join you at the end of turn 1".
   - **Succession with this build:** for example, "If King Corvane I dies, Corvane II is crowned at Crownkeep 2 turns later with 2 kept power (half of 4)."
6. **Presets:** three buttons, one per faction preset (§6.1, the same builds the AI uses), plus **Clear** (no mandates, keep 10).
   - Default when the screen opens: the faction's balanced preset.
7. **Lock in build:** always possible, because every combination the screen allows is legal. It moves on to the next human seat or starts the game.

All numbers come from the rules functions in §9. The screen does no math of its own.

---

## 5. ruler death and succession

### 5.1 when a ruler dies
- After each battle, the TurnResolver checks every faction whose ruler fought in it. The ruler is dead if either:
  - it fell (hp 0, while its side won), or
  - its army was destroyed because its side lost.
- The faction's ruler status becomes **dead**, the ruler's army is removed, and a `ruler_died` event is added (phase "battles").
- While a faction has no ruler, it has no province ability, no ruler morale in battle, and **cannot sacrifice**.
- Kept power at the moment of death decides the successor.

### 5.2 succession by type
If the ruler dies during turn **T** (turn numbers as players see them), the successor arrives in the rulers phase at the end of turn **T + delay**. It can be ordered from turn T + delay + 1, so the faction misses exactly *delay* turns of ruler.

| kind | rulers | delay | successor's kept power | name |
|---|---|---|---|---|
| mortal line | King Corvane, the Ninth Fang | 2 turns | half the dead ruler's, rounded down | next in line: Corvane II, the Tenth Fang, ... |
| undying | the Ever-Regent | 4 turns | the same as at death | unchanged |
| god | the Great Thornmane | 1 turn | 3 less than at death (never below 0), for good | unchanged |

For a ruler that dies with 10 kept power: the heir has 5, the Regent has 10 again, and the god has 7. With 4 kept: 2, 4 and 1.

- The successor arrives **at the capital, at full hp, in a new ruler army**.
- If the faction doesn't hold its capital when the successor is due, the successor waits and arrives at the end of the first turn it holds it again. Under M1's victory rule this can't happen, because losing the capital ends the game. The rule is here in case #25's "hold the capital for a turn" option is adopted.

### 5.3 the ruler dying in battle vs. the capital falling
- **Ruler dies in battle:** succession as above. The game goes on. Mandates stay.
- **Capital falls:** the M1 win condition is unchanged. Capturing the enemy capital wins, and both falling in the same turn is a draw (`VictoryCheck`, untouched). It doesn't matter where the ruler is or whether it is alive.
- **Both in the same turn** (for example, the ruler dies defending the capital as it falls): the capital decides. The game is over, and the final turn report still records the ruler's death.
- **The victory screen** lists each faction's build: its ruler, with kept power and alive/dead, and its mandates. The point is that players can argue about builds afterwards.

### 5.4 what the player sees
- **Codex entries:**
  - one per kind: `succession_mortal`, `succession_undying`, `succession_god`
  - `ruler_death`, which says plainly: "a ruler on a losing side is lost with its army; there are no retreats yet"
- **The ruler panel** shows the rule for your ruler all game, not only after a death. For example: "Mortal line: if King Corvane I dies, his heir is crowned at Crownkeep 2 turns later with half his kept power (now: 5 → 2)."
- **Turn report on death**, one event that names cause, effect and what happens next. Examples:
  - "King Corvane I fell in the battle of Thornvale. The Aurel line goes on: Corvane II will be crowned at Crownkeep at the end of turn 7 with 3 kept power (half of 7, rounded down). Until then the Aurel Crown has no ruler: no Royal Court, no ruler in battle, no sacrifices. Your mandates stay."
  - "The Ever-Regent was lost with his army when the Aurel Crown routed at Stonegate. Bound to the sunstone, he re-forms at Crownkeep at the end of turn 9 with all 6 of his kept power."
  - "The Great Thornmane's avatar was destroyed at Wildmoor. The god takes a new body at Fangridge at the end of turn 6, weaker for good: 7 kept power instead of 10."
- **Turn report on arrival:** "Corvane II was crowned at Crownkeep with 3 kept power: 25 hp, attack 10, defense 9, Royal Court +3 gold."
- **While waiting:** the capital shows a countdown badge ("heir in 2 turns"), and the ruler panel shows the same.

---

## 6. AI opponent

### 6.1 build presets
Each faction has 3 presets. AI seats use them, and they are the build screen's quick buttons. Data: `data/build_presets.gd`.

| preset id | name | faction | ruler | mandates | kept | AI ruler role | AI sacrifice picks, in order |
|---|---|---|---|---|---|---|---|
| `warrior_king` | Warrior King (keep) | Crown | King Corvane | none | 10 | field | Royal Armories, Veteran Levies |
| `iron_crown` | Iron Crown (spend) | Crown | King Corvane | Royal Armories, Heavy Tithes, Veteran Levies | 0 | home | none |
| `regents_court` | Regent's Court (balanced) | Crown | the Ever-Regent | Royal Armories, King's Roads | 5 | field | Drilled Ranks, Veteran Levies |
| `beast_god_unbound` | Beast-God Unbound (keep) | Clans | the Great Thornmane | none | 10 | field | Iron Discipline, Blood Frenzy |
| `clan_moot` | Clan Moot (spend) | Clans | the Ninth Fang | Iron Discipline, Blood Frenzy, Sworn Vassals | 0 | home | none |
| `blood_of_the_fang` | Blood of the Fang (balanced) | Clans | the Ninth Fang | Iron Discipline, Drilled Ranks | 5 | field | Blood Frenzy, Veteran Levies |

- **How an AI seat picks:** `presets[faction][rng.randi_range(0, 2)]`. `rng` is the seat's AI RNG, seeded with `game_seed * 7919 + (seat + 1) * 104729` (the formula behind `Simulator.policy_seed`), and this is its first draw.
- The same seed always gives the same AI build. The new game screen shows "AI build: random", and in M2 nothing else.

### 6.2 AI seats in the game flow
- `GameSession` takes the seat kinds. An AI seat gives its orders when its ORDERS phase starts:
  - it reads the **start-of-turn** state from `session.state()`
  - it gets orders from its `AIPlayer`
  - it queues each one through `queue_order`, so the same `OrderBook` checks apply
  - then it calls `end_turn`
- The AI never sees queued human orders: the session gives it nothing but the state.
- **Handoff only between two human seats.** With one human, the human ends the turn, the AI orders at once, the turn resolves, and the human sees the turn report at the start of their next turn. No "pass the computer" screen.
- **AI orders are recorded in history like any orders,** so `GameSession.replay` rebuilds AI games without running the AI. `record()` adds `"seat_kinds"`.
- The turn report shows AI results exactly like a human opponent's.

### 6.3 what M2 needs from `AIPlayer`
The brain itself is built separately (branch `m2-ai-player`). M2 uses this contract and adds the M2 behaviours to it in ticket M2-7.

```
AIPlayer.choose_build(state: GameState, faction_id: String, rng: SeededRNG) -> {"preset", "ruler", "mandates"}
AIPlayer.orders(state: GameState, faction_id: String, rng: SeededRNG) -> Array   # MoveOrder, RecruitOrder, SacrificeOrder
```

`choose_build` is exactly the §6.1 preset pick, so the build screen's presets and the AI's builds are always the same data.

Behaviours `orders()` must have in M2:
1. **Ruler role** from the preset:
   - **home:** the ruler's army never leaves the capital.
   - **field:** the ruler's army goes with the faction's strongest army (by hp × attack; ties go to the first by id).
     - In the same province: it gets the same move order, or holds if that army holds.
     - Elsewhere: it takes one step along the shortest path to that army's province.
     - Either way, it holds instead when `Forecast.battle_odds` for its move is "likely loss".
2. **Sacrifice:** at most one per turn, only with a living ruler. It sacrifices for the preset's first affordable unowned pick when either:
   - (a) an enemy army is next to its capital and the defenders' odds there are "close" or "likely loss", or
   - (b) it is turn 8 or later and its income is at most 80% of the strongest enemy's.
3. **Uses what it owns:** road moves when they shorten a march or a return home, and Warband Muster recruits whenever the Fang is in a province it owns.
4. **Legal orders only:** everything it returns passes `OrderBook` (zero rejections is a test).

---

## 7. approachability (mandatory; every M2 ticket ships its own part)

### 7.1 tooltips and breakdowns
Every number explains itself on hover, through `Breakdown` (lines sum to the total, as in M1):
- **Kept power:** "Kept power 4 = pool 10 − Royal Armories 4 − King's Roads 2", plus sacrifice lines and succession lines ("Succession: half of 9, rounded down −5").
- **Ruler stats:** "Attack 14 = base 9 + 5 from 10 kept power (½ per point, rounded down)".
- **Ability rank:** "Ability rank 2 = 1 + 4 kept power ÷ 3 (rounded down)", followed by what rank 2 does.
- **Unit stats with mandates:** "Defense 6 = Spearmen 5 + Royal Armories 1" and "Max hp 12 = Spearmen 10 + Veteran Levies 2".
- **Recruit price:** "Knights 16 gold = 20 − Muster Grounds 4".
- **Province income:** "Income of Crownkeep 15 = base 12 + Heavy Tithes 1 + Royal Court 2 (King Corvane I is here, ability rank 1)". This fills the "Modifiers" line M1 left at 0.
- **Every mandate name**, wherever it appears (build screen, ruler panel, reports): a tooltip with the exact effect, what it changes for you right now, and a codex link.

### 7.2 codex entries (`RulesCodex`), all new terms
- **Rulers:** `ruler`, `ruler_power`, `kept_power`, `ability_rank`, `ruler_rank`, `ruler_in_battle`, `ruler_healing`, `ruler_army`, `ruler_death`.
- **Succession:** `succession`, `succession_mortal`, `succession_undying`, `succession_god`.
- **Mandates:** `mandates`, `sacrifice`, `build`, `build_presets`, `ai_seat`.
- One entry per ruler: `ruler_aurel_king`, `ruler_ever_regent`, `ruler_thornmane_avatar`, `ruler_fang_chieftain`.
- One per ability: `ability_royal_court`, `ability_mending_light`, `ability_dread`, `ability_warband_muster`.
- One per mandate: `mandate_<id>` for all 10.
- Map mechanics: `road_move`, `field_recruit`.
- **Updated M1 entries:**
  - `phase_order` (§3)
  - `orders` (sacrifice and road moves)
  - `battle_rounds` (rulers' ranks)
  - `battle_morale` (ruler +2, Dread, Iron Discipline)
  - `battle_commanders` (rulers are not commanders)
  - `recruit` (recruits never join the ruler; Warband Muster)
  - `income` (Tithes, Royal Court)
  - `victory` (a ruler's death never ends the game; the capital does)

### 7.3 previews and forecasts
- **Build screen:** live previews (§4).
- **Sacrifice:** before → after preview and Confirm (§2.4).
- **Orders:**
  - the move forecast covers road moves
  - the recruit forecast covers Muster Grounds prices and Warband Muster ("joins the Ninth Fang wherever it ends this turn, if you own that province then")
  - the gold forecast includes Tithes and Royal Court
  - the map marks the province Sworn Vassals will take
  - battle odds include rulers, mandates and Dread automatically, because they fight the real resolver

### 7.4 battle report "why"
`AutoBattleResolver._factors` gains these factors. Each has a clause, a brief (for odds), and a codex id.
- `ruler`: damage the ruler dealt, measured exactly like `commander`. If #25's polish changes how commander damage is measured, the ruler follows. Example: "King Corvane I fought in the front rank and dealt about 22 damage."
- `morale_ruler`: "King Corvane I kept the line from breaking (+2 morale)."
- `mandate_royal_armories`, `mandate_drilled_ranks`, `mandate_blood_frenzy`: measured like trait parts. Example: "Royal Armories (+1 attack, +1 defense) was worth about 9 damage."
- `mandate_veteran_levies`: 2 hp counted for each regular unit that took damage. "Veteran Levies' extra hp absorbed about 12 damage."
- `mandate_iron_discipline`: a side held past its break point while a commander stood. Measured like the M1 "kept the line" factor. "Iron Discipline held the Thornmane Clans line past its breaking point (lost 81%, breaks at 75%) while its Warchief stood."
- `ability_dread`: measured like Fury. "The Great Thornmane's Dread (−2 morale) made the Aurel Crown break a round sooner."
- When a ruler falls, the round line already says "Aurel Crown's King Corvane I fell." Feast of Victory goes in the aftermath line.

### 7.5 turn report
New event types, each with `codex` set:
- `sacrificed` (phase sacrifice)
- `ruler_died` (battles)
- `vassal_joined` and `vassal_contested` (capture)
- `ruler_healed` and `mending` (rulers)
- `ruler_arrived` (rulers)

Recruits made with Warband Muster stay `recruited` events and say where. Road moves stay `army_moved` events and say "by the King's Roads through X". The succession texts are in §5.4.

---

## 8. balance intent

### 8.1 the shape we want
- **Keep everything is a tempo build.**
  - A 10-kept ruler is strongest in turns 1-7, when armies are small and the ruler is a large share of one. It is also a single point of failure.
  - Calibration: a 10-kept ruler adds about 50-70 gold of units to a 140-gold army.
- **Spend everything is a scaling build.**
  - Percentage mandates grow with the army, and economy mandates pay every turn.
  - Calibration: at 140 gold, Royal Armories is worth about 15-20 gold of units; at 280 gold, about 35.
  - Mandates survive the ruler's death.
- **Balanced builds trade a little of each.**
- **Within a faction, the two rulers should feel different, not ranked:**
  - King: governor or paladin, with gold.
  - Regent: second-rank artillery and a healer, very hard to keep dead.
  - Thornmane: the biggest body, with Dread.
  - Fang: forward reinforcements.

### 8.2 autoplay bands (checked by M2-8)
Both seats run `AIPlayer`; only the builds differ. "Decisive" means finished and not a draw. If a pairing has fewer than 60 decisive games, double its games.

| band | what | games | target |
|---|---|---|---|
| A. both viable | per faction, faction mirror: keep preset vs spend preset (`warrior_king` vs `iron_crown`, `beast_god_unbound` vs `clan_moot`) | 200 per faction (100 per seat order) | each build wins **40-60%** of decisive games |
| A2. same ruler (report only) | Regent keep-10 vs Regent spend-10, Fang keep-10 vs Fang spend-10 (explicit builds) | 100 each | reported; a result outside 35-65% goes to the director |
| B. no dominant preset | all 9 Crown × Clans preset pairings | 100 per pairing (50 per seat order) | no preset wins **more than 65%** of decisive games against any other |
| C. factions (report only) | B pooled | 900 | each faction wins 40-60%. A miss goes to Alex as part of #25 item 4, not tuned silently |
| D. rulers matter | A + B | - | a ruler dies in **25-60%** of games that reach turn 8; **every** successor that falls due arrives |
| E. length | A + B | - | median decisive game **10-16 turns** (M1's target was 10-15) |
| F. sacrifice is reachable | A + B | - | the AI sacrifices in **15-50%** of games |
| G. shape (report only) | A | - | keep wins ≥ 55% of keep-vs-spend games decided by turn 8; spend wins ≥ 55% of those decided after turn 12 |
| H. integrity | everything | - | 0 invariant violations, 0 session errors, 0 script errors; replaying every 10th game record gives an identical final state |

Bots aren't humans: the bands prove nothing is broken or dominant for the bots. Alex's playtest is the real check.

### 8.3 tuning knobs
M2-8 may change these without asking, recording before → after in its PR and updating the tables in this file (that ticket authorises the edit):
- any mandate cost ±1
- any ruler's hp per point ±1 and base stats ±2
- ability values ±1 per rank
- succession delays ±1 turn

Anything else, or a band that can't be met within these knobs, goes back to the director as a question for Alex.

### 8.4 calibration notes
The numbers were sanity-checked with a throwaway Python port of the M1 battle math (same formulas, not the engine; not committed), using mid-game armies of about 137 gold.

**What each item is worth, in gold of extra units:**

| item | worth |
|---|---|
| Royal Armories | about 20 (Crown), 15 (Clans) |
| Iron Discipline | about 10 (Crown), 25 (Clans) |
| Veteran Levies | about 8 |
| Drilled Ranks | about 8 |
| Blood Frenzy | about 8 |

**Rulers at 10 kept power** (early = a keep-10 ruler with its starting army attacking a spend-everything capital garrison of about 84 gold behind a fort):

| ruler | worth at 10 kept, mid-game | early capital attack wins |
|---|---|---|
| King | about 65 gold | 57% |
| Regent | about 45 gold | 41% |
| Thornmane | about 55 gold | 65% |
| Fang | about 50 gold | 50% |

These win rates count battle mandates only. The spend side's economy mandates, not modelled here, should move them about 10-20 points toward the spender.

**Rulers at 0 kept power:**
- A 0-kept front-rank King falls in 68% of even mid-game battles, even when his side wins.
- A 0-kept Regent in the second rank falls in 20%.

Battles in this engine are steep. +8 gold on one side of an even 137-gold battle already wins 71%. Morale effects are threshold-sensitive: −1 enemy morale moved one test from 26% to 48%. That is why Dread is only −1/−2.

**Autoplay results (M2-8, #36):** `autoplay.gd -- --matrix --jobs 8`, AIPlayer in both seats, seeds from 1, turn cap 60. The 1,206 games are 900 for band B plus 306 for A2's explicit builds; 1,406 before tuning, when two pairings had too few decisive games and were doubled.
- How the bands are measured: the engine has exactly two factions, so a same-faction mirror can't be set up. A is the Bradley-Terry head-to-head from both builds' records against the same opponents, the other faction's three presets in both seat orders: P(keep wins) = odds_keep / (odds_keep + odds_spend). "A, direct" pools the real keep-vs-spend games of band B. A2 is measured the same way as A. D counts ruler deaths before a game's last turn, since a ruler lost with its capital dies with the game.

| band | target | before tuning | after tuning |
|---|---|---|---|
| A, Crown (Warrior King / Iron Crown) | each 40-60% | 83 / 17 miss | 82 / 18 miss |
| A, Clans (Beast-God Unbound / Clan Moot) | each 40-60% | 84 / 16 miss | 71 / 29 miss |
| A, direct (keep / spend) | report | 100 / 0 | 80 / 20 |
| A2, Regent keep 10 / spend 10 | report, 35-65% | 85 / 15 | 68 / 32 |
| A2, Fang keep 10 / spend 10 | report, 35-65% | 99 / 1 | 100 / 0 |
| B, pairings over 65% | none | 7 of 9 miss | 8 of 9 miss |
| C, Crown / Clans | report | 41 / 59 | 45 / 55 |
| D, mid-game ruler death by turn 8 | 25-60% | 17% miss | 13% miss |
| D, successors due that arrived | all | 241 of 241 | 161 of 161 |
| E, median decisive length (games at the cap) | 10-16 | 19 (24% at the cap) miss | 21 (7%) miss |
| F, games with a sacrifice | 15-50% | 47% pass | 49% pass |
| G, keep wins by turn 8 / spend wins after turn 12 | report | none decided by turn 8 / 0% | none / 20% |
| H, integrity | 0 problems, replays identical | pass | pass |

- **Why B, A and A2 still miss:**
  - Warband Muster on a field Fang decides these AI games. Blood of the Fang wins all 300 of its band B games and the Fang keeping 10 wins all 102 of its A2 games.
  - In a diagnostic with Warband Muster at 0, Blood of the Fang fell to 17% against Warrior King and 22% against Regent's Court. Removing its Iron Discipline or cutting the Fang's body changed nothing.
  - The knob allows ±1 per rank, so rank 2 can't go below 1 recruit. The way it works needs a rule change.
  - Beyond that, a ruler that keeps 10 still beats the matching spend build in most games.
- **Why D and E miss:** these AI-vs-AI games are close to deterministic (several seeds play the same game). Both sides expand without fighting, then one or two battles decide the game, and the AI's ruler joins only likely wins. So rulers rarely die in mid-game, and games run past turn 16. No ruler or mandate number changes that.

---

## 9. engine changes at a glance (for builders)
- **Data:**
  - `data/rulers.gd` (`RulerData`: §1.2-1.4 numbers)
  - `data/mandates.gd` (`MandateData`: §2.2 ids, names, scope, cost, effect text, codex id)
  - `data/build_presets.gd` (§6.1)
  - Same style as `data/factions.gd`: const dictionaries.
- **State (serialized, validated, deep-copied):**
  - `Faction` gains `ruler_type`, `kept_power`, `mandates` (ids, in the order taken), `ruler_generation` (1 for the first ruler), `ruler_status` ("alive" / "dead"), `successor_turn`, `successor_power`, and `sacrifices` ([{turn, mandate, cost}]).
  - `Army` gains `ruler` (a `Unit` or null).
  - A ruler army holds only the ruler. A faction has at most one living ruler.
  - `from_dict` rejects unknown ids, kept power outside 0-10, and a ruler army with units, each in plain language.
  - The ruler's `UnitType` is built from its ruler type + kept power: `is_ruler = true`, cost 0, no trait. It is rebuilt whenever kept power changes and on load.
- **Pure rules** (`rules/ruler_rules.gd`, class `RulerRules`). These are the single source for battle, resolver, forecasts, breakdowns and every screen:
  - `build_errors`, `apply_build`
  - `ruler_stats` (hp, attack, defense, morale, rank, ability rank, ability value)
  - `unit_stats` (effective max hp, attack, defense, cost with modifier lines)
  - `available_mandates`, `sacrifice_check`, `successor_for`, `ruler_name(generation)`
- **Orders:**
  - new `SacrificeOrder(mandate_id)`, serialized `{"type": "sacrifice", "mandate": id}`
  - `MoveOrder` gains optional `via`, serialized `{"type": "move", "army", "to", "via"}`
  - `RecruitOrder` gains optional `at` = `"ruler"` for Warband Muster, serialized `{"type": "recruit", "unit_type", "at"}`
  - Old records without these fields load as M1 orders.
- **Battle** (`AutoBattleResolver`):
  - the ruler fighter is tier 0 (front) or tier 1 (second rank)
  - `RULER_MORALE = 2`
  - per-side base hit (60, or 70 with Drilled Ranks)
  - Royal Armories, Blood Frenzy and Dread as named parts
  - Iron Discipline in the rout check
  - Feast of Victory and a fallen ruler (`army.ruler = null`) in `_apply_losses`
  - report sides gain `"ruler": {"name", "fell", "hp_end"}`
  - Pack Leader becomes "every unit" only, not commanders or rulers
  - `StubBattleResolver` counts the ruler's attack + defense in strength
- **Resolver** (`TurnResolver`):
  - the phases in §3
  - ruler death bookkeeping
  - the empty-army cleanup also checks `ruler == null`
  - road-move collision rule
  - Sworn Vassals in capture
  - Warband Muster in recruitment
  - Tithes and Royal Court in income
  - the rulers phase
- **Session:**
  - `GameSession` takes seat kinds and AI players, and skips handoffs around AI seats
  - builds live in `start_state`, so `replay` needs nothing new
  - `VictoryCheck` is unchanged except that the summary lists builds
- **Autoplay:**
  - `Simulator.EVENT_TYPES` and the invariants learn the new events and ruler armies: a ruler-only army is not "empty", and gold accounting includes Tithes and Royal Court through the income events
  - `play_game` takes builds and AI seats

---

## 10. out of scope for M2
- **Magic:** schools, research, rituals, battle spells, the Regent's real spell mastery, and Tithe of Blood (M5).
- **Paths of ascension:** research, lock-in forks, transformations, and mandates unlocked by transformations (M4).
- **Fog of war** (M5). Everything stays visible, builds included.
- **More factions,** more than 2 rulers per faction, council rulers, ruler items and equipment.
- **Battle animation and effects** (M3).
- **Retreats, sieges,** independents with garrisons, and healing for regular units beyond Mending Light and Feast of Victory.
- **AI:** difficulty levels, an AI that picks custom (non-preset) builds, more than 2 seats.
- **Infrastructure:** save/load, sound, online play.
- **Issue #25's open questions** (capital race, fort strength, commander reach, faction balance). M2 doesn't decide them, and nothing here depends on their answers.

---

## 11. tickets
Github issues are to be cut once Alex has seen this. M2-n are placeholders. Every code ticket follows `CLAUDE.md`:
- pure rules code
- tests under `tests/`
- `tools/compile_check.gd` passes
- in-game explanation in the same PR
- a `playtest:` line in the PR

Parallel lanes:
- M2-1 first.
- Then M2-2, M2-3, M2-4 and M2-5 can run at the same time. M2-2 is the only one in `auto_battle_resolver.gd`; M2-3 and M2-4 both touch `turn_resolver.gd` in different phases, so expect one small merge.
- M2-9 can start now.
- M2-6, M2-7 and M2-8 close the milestone in that order.

**M2-1 `code` `hard` Ruler and mandate rules model** (needs M1)
- *Scope:*
  - data files, state fields, the ruler `UnitType`, `RulerRules` and starting setup (§1.5, §9)
  - build validation and application
  - serialization and replay with builds
  - `Breakdown` functions for kept power, ruler stats, ability rank and unit stats
  - the ruler's army on the map like any army: its label, and a tooltip with the ruler's stats and their breakdowns
  - until M2-5 lands, a new game applies each faction's balanced preset, so there is always something to play
  - every codex entry in §7.2 (the text of the gameplay entries can be finished by the ticket that ships the mechanic)
- *Acceptance:*
  - a table-driven test checks every ruler at kept 0-10 against §1.3
  - illegal builds (over 10, duplicate, other faction's exclusive, unknown id) are rejected with plain reasons; an empty build keeps 10
  - to_dict/from_dict/JSON round trips keep every new field
  - a recorded game with builds replays to an identical state
  - each capital starts with army 1 and the ruler's army
- *playtest:* start a new game, hover each ruler's army at the capitals, and check that every number explains itself and that every new codex entry opens.

**M2-2 `code` `hard` Battles with rulers and mandates** (needs 1)
- *Scope:*
  - rulers in the ranks (§1.6)
  - the battle mandates (Iron Discipline, Drilled Ranks, Veteran Levies' max hp, Royal Armories, Blood Frenzy, Feast of Victory) and Dread
  - "why" factors and clauses (§7.4)
  - report `ruler` fields
  - the M1 battle codex entries updated
- *Acceptance:*
  - fixed-seed tests pin each effect: Iron Discipline holds only while a commander stands; the 70% base; Blood Frenzy only below full hp; Feast heals only the winner; Dread only in the avatar's province battles; a front-rank ruler is targetable in round 1 and the Regent only after the front falls
  - a constructed battle names a mandate as its top "why", and another names the ruler
  - `Forecast.battle_odds` changes when a mandate is added
  - same seed, same report
- *playtest:* fight the same attack with and without Royal Armories and with a 0-kept vs 10-kept King, then read each "why".

**M2-3 `code` `hard` Ruler death and succession** (needs 1; parallel with 2: it detects death by the ruler's army disappearing or `army.ruler` becoming null, not by the report format)
- *Scope:*
  - death bookkeeping (§5.1)
  - the rulers phase: Mending Light, 25% ruler healing, successors (§5.2)
  - ruler-army rules and labels (§1.5)
  - succession waits for the capital
  - the victory summary lists builds
  - turn report events and texts (§5.4, §7.5)
  - `Simulator` invariants for ruler armies
- *Acceptance:*
  - tests for each kind's delay (T+2, T+4, T+1) and power (half, same, −3, never below 0), heir names, death by losing side vs. killed while winning, successor at full hp in a new army at the capital, healing amounts
  - every new event carries a codex id
  - a replay with deaths and successions is identical
- *playtest:* march a 0-kept King into a big enemy army and read the turn reports until Corvane II is crowned.

**M2-4 `code` Mandates and abilities on the map** (needs 1)
- *Scope:*
  - King's Roads (`via`, check, collision rule, forecast, two-step destinations in the orders UI)
  - Sworn Vassals (capture phase, contested rule, map marker, forecast)
  - Heavy Tithes and Royal Court (income and breakdowns)
  - Muster Grounds (prices everywhere)
  - Warband Muster (`at: "ruler"`, rank limit, resolution, forecast, "recruit with the Ninth Fang" in the recruit panel)
- *Acceptance:*
  - a road move never fights on a border
  - a road move into a province an enemy also entered fights there with no defender
  - a contested vassal province goes to nobody
  - Warband Muster recruits are cancelled at no cost when the Fang died or its province isn't yours after capture
  - every forecast equals the resolved result (tests call both)
- *playtest:* take King's Roads and Sworn Vassals, then check every forecast against the turn report.

**M2-5 `code` Pre-game build screen** (needs 1)
- *Scope:* seat kinds on the new game screen, the build screen (§4), hotseat handoff between human builders, presets, live previews, start game with builds.
- *Acceptance:*
  - headless UI tests in the M1 style
  - every number on the screen has a hover breakdown equal to `RulerRules`/`Breakdown` output
  - an unaffordable mandate is disabled with its reason
  - the default is the balanced preset
  - the other player's build is never on screen during the build phase
- *playtest:* build a keep-everything and a spend-everything Crown, and say from the previews alone how your first battle should go.

**M2-6 `code` Mid-game sacrifice and the ruler panel** (needs 1, 3; best after 2 and 4)
- *Scope:*
  - `SacrificeOrder` rules and serialization, the sacrifice phase, the order re-check on cancel (§2.4)
  - the sacrifice dialog with its before → after preview and Confirm
  - the ruler panel: your ruler with breakdowns, ability, succession rule and countdown, and mandates; the enemy ruler read-only
  - the gilt ruler ring on the map token, and the capital countdown badge
- *Acceptance:*
  - the preview equals the resolved result for the faction's own numbers (test)
  - rejected: no living ruler, too little power, a second sacrifice in one turn, an owned or foreign mandate
  - King's Roads bought by sacrifice allows a road move in the same turn
  - cancelling the sacrifice removes dependent orders with the reason
- *playtest:* keep everything, then sacrifice for Royal Armories just before a big battle; is the preview what happened?

**M2-7 `code` AI seat** (needs 4 and 6, and the AIPlayer ticket)
- *Scope:* the AI build pick (§6.1), AI seats in `GameSession` (§6.2), the M2 behaviours on the `AIPlayer` brain (§6.3), and the `ai_seat` codex entry.
- *Acceptance:*
  - a headless human-vs-AI session (the human seat scripted) runs 30 turns with zero AI order rejections
  - the AI's orders are identical whether or not the human queued orders first
  - the same seed gives the same AI build and orders
  - with one human there are no handoff screens
- *playtest:* play a full game against the AI with each faction; does it defend, sacrifice and march its ruler sensibly?

**M2-8 `code` Autoplay balance check for builds** (needs 2, 3, 4, 6, 7)
- *Scope:*
  - `Simulator` and `autoplay.gd` take builds (preset ids or explicit) and AI seats
  - report sections: wins by build, ruler deaths and successions, sacrifices, mandate picks, length
  - `--matrix` runs the §8.2 bands and prints a pass/miss table
  - exit code 0 only when band H holds; other bands are reported
  - tuning within the §8.3 knobs
- *Acceptance:*
  - the report is attached to the PR, with every number change before → after and the M2_RULER.md tables updated
  - any band still missed is listed with why
- *playtest:* read the bands table; do keep and spend both win?

**M2-9 `design` `asset` Ruler portraits** (no code dependencies)
- *Scope:*
  - art lead adds 4 portrait rows to `design/ASSET_MANIFEST.md` under the bible's portrait class. The Crown rulers are anchored to the kingdom portraits and the Clans rulers to the tuskers pick (§6.2 anchors and the leak rule apply).
  - asset builder generates them.
  - the build screen and ruler panel use them (placeholders until then).
- *Acceptance:* the bible's portrait gates (named held item visible, faction read at 96×128) and a contact sheet.
- *Budget:* 50 Ludo credits (4 portraits at about 1.5 each, plus re-rolls).
- *playtest:* do the four rulers read as who they are at 96×128?

---

## 12. director's calls (review these first)
1. **Pool of 10 for every ruler;** mandates cost 2-4. Rulers differ by body, rank, ability and succession, not by pool.
2. **Mid-game sacrifice costs +1 power,** one per turn, needs a living ruler, and resolves first in the turn, so it already counts in that turn's battles. Without the premium, "keep everything, convert later" would beat every pre-game build.
3. **Front rank for three rulers, second rank for the Regent.** A 0-kept ruler is meant to stay home. This makes "a weak ruler is easier to kill" literal.
4. **The ruler always travels alone, as its own army,** and recruits never join it. M1 has no merge or split orders, so this keeps the ruler free to move.
5. **A ruler on a losing side dies with its army,** consistent with M1's no-retreat rule. Alternative: a ruler still standing escapes to the capital wounded.
6. **Capturing the capital still wins; a ruler's death never ends the game.** Successors appear at the capital and wait if it's lost (future-proof for #25's option b).
7. **Succession numbers:** a mortal heir in 2 turns at half power; the undying in 4 turns at full; the god in 1 turn at −3 for good. Mandates always stay.
8. **Rulers heal 25% of max hp per turn.** Other fighters still don't heal, except through Mending Light and Feast of Victory.
9. **The archmage without magic:** the Ever-Regent's spells are his attack stat and his healing until M5.
10. **Sworn Vassals reinterpreted.** M1 has no independents to buy, so "join more cheaply" becomes "one neutral neighbour joins each turn, no army needed".
11. **Royal Armories and King's Roads are Crown-only;** Iron Discipline and Sworn Vassals are shared. Iron Discipline is worth more to the Clans, which is intended.
12. **Builds are secret while picked, public from turn 1.** M2 has no fog, and battle odds must count enemy mandates.
13. **The AI picks 1 of 3 presets per faction** by a seeded roll; no custom AI builds in M2.
14. **All names are proposals:** King Corvane, the Ever-Regent, the Great Thornmane, the Ninth Fang, and the mandate names that aren't from the brief.
