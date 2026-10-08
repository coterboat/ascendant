# ASCENDANT: M3c design spec, "forts and sieges"

Status: **PROPOSED by the director (Claude session, 2026-10-04). Built provisionally under Alex's 10-4 'build an MVP you'd want to play'. Alex can change anything.**

Built on: `design/GAME_BRIEF.md` (approved: the core loop's "movement, battles, sieges, income" order, "forts that gate recruitment" under what we keep from Dominions, pillars 3-5, the approachability rules), `design/3D_DIRECTION.md` (§5.3 fortress kits, §6.3 muster yards, §6.5 sieges at walls, and the §10.1 and §10.5 proposals this spec makes exact), `design/MILESTONES.md` (the "forts and sieges" line of the restructure), `design/M2_RULER.md`, `design/M3_BATTLES.md` (§2, the battle event log), `design/M4_ASCENSION.md` (format, §10 bands), the engine on `main` at bea3b51 (`rules/`, `data/`, `ai/`, `tools/autoplay/`, `world3d/`), issue #94 (the capital stand-off) and the art ledger `studio/ledgers/asc-3d-factions.jsonl`. The storm odds in §4.2 were measured with the real `AutoBattleResolver` in a throwaway script (not committed; §4.2.1 says exactly what it ran). Every number is in the engine's own terms (hp, attack, defense, morale, gold, provinces, rounds, ranks), plus one new one, **wall strength**.

Alex's call, 2026-10-04: *"we need a world where we see armies mustering on the map in a fortress ready to spill out for war. we're not settling here"*

**Alex: read §16 (director's calls) first, then §17 (questions for Alex, each with the default the build goes ahead on).**

## the short version
- **Forts become the places armies muster.** You recruit at any fort you own, not only at your capital. A fort's level sets how many recruits it takes a turn: a **palisade** 2, a **keep** 4, a **citadel** 8. Capitals start as citadels; Stonegate and Blackwood start as keeps.
- **You can build forts.** A Fortify order builds a palisade (30 gold, 2 turns) in a province you own, or turns a palisade into a keep (50 gold, 3 turns). You build one fort at a time, and citadels stay at capitals. Work stops while an enemy army stands in the province, and a captured site is razed.
- **Walls.** A palisade has 3 wall strength, a keep 6, a citadel 9. While they stand, an army that marches into an enemy fort with a garrison inside **besieges it instead of fighting**.
- **Each turn of siege, the walls drop** by the besiegers' siege damage: 1 for the siege camp, +1 for every 10 troops (at most +2), and +1 for each siege engine (at most +3, and 1 for every 5 troops); never more than 6 a turn. From the siege's second turn the fort is **cut off**: its province's income goes to the besiegers, and nobody can recruit there. Besiegers with fewer than half the garrison's troops are only **pickets** and cut nothing off.
- **The garrison holds, sallies or leaves. The besiegers wait, storm or leave.** Storming walls that still stand is costly: the garrison gets **+2 defense for every 3 wall strength left** (+6 behind a full citadel). Measured with the real battle rules, an army that wins in the open with 1.25 times the garrison's gold needs about 1.5 times to storm a full citadel, and loses twice as many fighters doing it.
- **Walls help most against a storm.** A sally, a relief army and the fight after the **breach** (walls at 0) are all battles in the open: nobody defends and nobody gets walls or terrain, but the garrison's own fighters keep **+2 cover**, so a fort always gives its defenders at least the old +2. At the breach, the battle comes on its own the next turn.
- **One deterministic pass.** A new **sieges** phase runs after battles, and no siege rule draws a random number. §3.9 lists every way orders can cross.
- **Siege engines:** one per faction, the Crown's **Siege Ram** and the Clans' **Wallbreakers**. They are carried by an army, never fight, and each adds 1 siege damage for every 5 troops with it. They are lost with their army. You recruit them at a keep or citadel.
- **The 3D board** shows fort levels, damaged walls, construction scaffolding, siege camps ringing the walls, the breach, and the garrison spilling out of the gate on a sally. It reads only the state and a short list of new events (§10).
- **AI:** it besieges only what it can win in the open, storms at likely odds, relieves its own forts together with a sally, builds one forward fort at a time and garrisons it, and turns #94's stand-off rule into a siege. Because the walls always fall, every siege it keeps up ends in a battle.
- **Off by default,** behind "Forts & sieges (M3c preview)", independent of Rulers and Paths. With it off, M1, M2 and M4 games replay byte-identically.
- **Balance targets:** median decisive game 12-22 turns, with at most 5% reaching the 60-turn cap (21% do today, #94); a siege in 60%+ of games that reach turn 12; storms are 15-60% of siege battles; turtling loses.
- 10 tickets, S-1a and S-1b, then S-2 to S-9 (§15). Art: 99.5 Ludo credits planned, 149 with the re-roll reserve; budget 155 (§13).

---

## 1. what exists, and what M3c adds

### 1.1 the engine M3c builds on (unchanged unless this spec says so)
- **A fort is one flag.** `Province.has_fort` is true at Crownkeep, Stonegate, Blackwood and Fangridge. In battle it gives the defender `FORT_DEFENSE`, +2 defense, as a named part `"fort"` (`AutoBattleResolver._defense`), on top of the terrain. M1 and M2 use it for nothing else. M4 reads it twice: the Forges (Living Iron heals to full in its forts) and Forge Tithe (+4 gold for every fort).
- **Recruits** appear only at the capital (`RecruitOrder.at` = ""), or with the Ninth Fang through Warband Muster (`at` = "ruler"). Only gold limits how many.
- **Economy:** each side starts with 45 gold and its capital, which pays 12 a turn. A side holding its half of the map (7 provinces, a neutral keep among them) makes 53 a turn. Units cost 8-22 gold.
- **Battles:** any province holding armies of two or more factions after movement has one battle. The defender is the one faction whose armies held (didn't move). If no single faction held, nobody defends and nobody gets terrain. Losers are destroyed: there are no retreats.
- **Hit and damage:** chance = clamp(60 + 4 × (attack − defense), 30, 90); damage = ceil(attack ÷ 2) − floor(defense ÷ 4), at least 1. Under #41's breakpoint rule every attack is odd and every defense is 4k or 4k+1, so a +2 bonus changes only the hit chance, and +4 is exactly one damage step.
- **Battles are steep.** M2 §8.4: +8 gold on one side of an even 137-gold battle already wins 71%. In §4.2's runs, 1.25 times the gold won 95-100% of open battles.
- **Phase order (M4):** sacrifice, orders, movement, battles, capture, recruitment, income, research, rulers. Every random draw comes from the turn's `SeededRNG` in sorted id order, and only battles draw.
- **The capital stand-off (#94).** In M4-6's 1,800 path games, 21% reached the 60-turn cap. Both seats stopped attacking and stacked every recruit at home, because attacks into a fort capital lose and the odds rule keeps the AI from trying again. #94, being built now, reads a stand-off from the state alone (units and gold worth 20 turns of income) and then hunts, besieges or raids. M3c gives that rule a real siege to make.
- **The 3D board** already draws fortresses at capitals (`fortress.<faction>`), forts (`fort.<faction>`) and war camps (`camp.<faction>`), musters recruits in the capital's yard, and plays each turn's events (PRs #87, #92). It reads the state and the events and never writes to them.

### 1.2 what M3c adds
- Fort levels, wall strength, and recruiting at forts (§2).
- Building and upgrading forts: the Fortify order and construction (§2.4-2.5).
- Sieges: the sieges phase, storm and sally orders, relief, the breach, and a deterministic table for every crossing of orders (§3, §6).
- Battles at walls: one new defense part, `"walls"`, and a `"siege"` block in the battle log and report (§4).
- Two siege engines (§5).
- AI (§8), explanations for all of it (§9), the 3D board (§10), autoplay bands (§11) and an art batch (§13).

### 1.3 the opt-in switch
- `GameState.setup_sieges(errors)` turns sieges on before turn 1 for any game: M1, rulers, or rulers with paths. It sets each fort's level from the map (§2.2), fills its walls, and adds each faction's siege engine to its roster. From then on `GameState.sieges` is true. `GameState.with_sieges(seed, builds, flags)` is the constructor the new game screen and the autoplay use.
- The new game screen gets a **Forts & sieges (M3c preview)** tick box. It is independent of Rulers and Paths and off by default; launching with `-- --sieges` ticks it.
- **With it off, nothing changes.** No siege field is saved, no siege phase runs, no siege event is made, no roster carries an engine, and recruit orders keep their M1 shape. Every existing test passes unmodified. The M1 and M2 games in `tests/fixtures/main_records.json`, the digests in `tests/fixtures/m2_matrix_digests.json`, and a new fixture of M4 path games recorded at bea3b51 before S-1a merges all replay byte-identically (S-1a's acceptance test).

---

## 2. forts

### 2.1 fort levels

| level | name | wall strength | walls if stormed, when full | recruits a turn | may recruit | repairs a turn | how you get one | cost | turns of work |
|---|---|---|---|---|---|---|---|---|---|
| 0 | no fort | – | – | – | – | – | – | – | – |
| 1 | **Palisade** | 3 | +2 defense | 2 | troops only | 1 | Fortify a province you own | 30 gold | 2 |
| 2 | **Keep** | 6 | +4 defense | 4 | troops, commanders, siege engines | 2 | Fortify a palisade | 50 gold | 3 |
| 3 | **Citadel** | 9 | +6 defense | 8 | troops, commanders, siege engines | 3 | capitals start as one | – | – |

- **Words used everywhere:** **troops** are the units that fight: every regular unit in an army. Commanders and rulers are not troops, and engines are not units at all (§5). The recruit limit counts every recruit: troops, commanders and engines alike.
- **Wall strength** (walls for short) is a whole number from 0 to the level's maximum. It drops only by siege damage (§3.3) and rises only by repair (§2.6) or a finished level (§2.4).
- **Walls if stormed:** +2 defense to every fighter of the garrison for every 3 wall strength still standing, rounded up (§4.1). Every text prints the number: "Walls 5 of 9: +4 defense if stormed." At 0 any fort is **breached**.
- **What each level is for:**
  - The palisade is mainly a place to recruit nearer the front. Its walls hold off a raid for 3 turns but delay a real army only one turn, and they make a storm only a little dearer. The Fortify preview says exactly that (§9.2).
  - The keep is a real strongpoint, and the only place besides a capital that recruits commanders and engines.
  - The citadel is the capital.
  - Each step adds 3 walls and +2 storm defense, and doubles the recruits.
- **Why no citadels outside capitals:** a citadel anyone can build (9 walls, +6, 8 recruits) is the fort-spam turtle the veteran critic feared (appendix A). A keep is the most a field fort can be.
- `Province.has_fort` stays. It is true exactly when the level is 1 or more, so the Forges, the board and the battle log's `"fort"` flag work with no change.

### 2.2 where forts start
- On the M1 map, **Crownkeep and Fangridge are citadels** (9 walls) and **Stonegate and Blackwood are keeps** (6 walls). No other province has a fort.
- Stonegate and Blackwood start neutral and empty, so the first army to walk in takes the keep whole (§3.8). Each is two moves from its side's capital (Crownkeep → Westwatch → Stonegate; Fangridge → Ebonpeak → Blackwood), and the two touch. They become the first forward forts both sides race for.
- On any map, a capital starts at level 3 and every other province with `has_fort` at level 2, all at full walls. Later maps may give a `fort_level` in their data.

### 2.3 recruiting at forts
- **A recruit order names where it is made:** your capital (`at` = "", as in M1), another fort you own (`at` = its province id), or your ruler through Warband Muster (`at` = "ruler", unchanged). In a game with sieges, an `at` naming the capital's own id is read as "" (without sieges it is rejected, as today).
- **A recruit at a fort is legal when:**
  - sieges are on, and the province had a fort at the start of the turn;
  - you have owned it **for `CAPTURE_WAIT` (2) full turns** since you took it, and still own it after capture. So a fort you take on turn 7 can take recruits from turn 10 (S-7 raised the wait from 1 to 2, §11.4). **Retaking your own fort** within 2 turns of losing it restores your old standing, so you can recruit there at once. A fort you build stands at the end of a turn and takes recruits from the turn after (§2.4);
  - it was **not cut off** at the start of the turn (§3.3). A cut-off fort refuses the order: "Stonegate is cut off by the Thornmane Clans' siege: nobody can recruit there this turn, even if you lift the siege." Pickets cut nothing off, and on the turn the enemy arrives, recruits already ordered there still arrive;
  - the unit may be recruited at that level: commanders and engines need a keep or citadel;
  - the recruits already ordered there this turn are fewer than its limit.
- **Gold is one pool** for every fort, Warband Muster and Fortify order, paid in the order given (M2's rule). `TurnResolver.price_recruits` takes the mixed list, counts recruits per fort, and is the one price every forecast and the recruitment phase use.
- **The capital counts as a fort,** a citadel taking 8 a turn. At 12-53 gold a turn and 8-22 gold a unit, that limit binds only for a rich realm buying cheap units: Muster Grounds Spearmen at 7 gold take 56 gold to reach 8. So recruiting at forts is mostly about **where** an army gathers, not how many it gets, and the place a realm builds its second fort is where its armies will gather.
- **Recruits join the first army there,** or form a new army there: M1's rule at the capital, now at any fort. They never join a ruler's army. Engines join the first army there with a fighter (§5). Warband Muster recruits don't count toward a fort's limit.
- **Why forts and not every province:** the brief keeps Dominions' "forts that gate recruitment", and Alex's picture is armies mustering in a fortress. A forward fort lets you choose where the muster happens, and the board shows it filling up.
- **Rejection reasons,** for example: "Stonegate is a palisade: it recruits troops only. Commanders need a keep or a citadel." / "Stonegate has taken 4 of its 4 recruits this turn." / "You took Blackwood on turn 7: it can take recruits from turn 10."

### 2.4 building and upgrading: the Fortify order
- **FortifyOrder(province)** builds the next level in a province you own: a palisade where there is no fort, a keep where there is a palisade. Serialized as `{"type": "fortify", "province": id}`.
- **Legal when:** sieges are on; you owned the province at the start of the turn; no enemy army stands in it; it is not a capital and its level is 0 or 1; and you have no construction under way anywhere and no other Fortify order this turn. **One fort at a time per faction.**
- **Paid** in the recruitment phase, in the order given with that faction's recruits, from the same gold. If there isn't enough gold then, the order is rejected at no cost, with the reason. It is also rejected at no cost if you lost the province in this turn's capture.
- **Work:** the site starts with all its turns of work left (2 for a palisade, 3 for a keep). In each later sieges phase where no enemy army stands in the province after battles, one turn of work is done. When the last is done the level goes up at once, at full walls, and `fort_by` records who built it.
- **So,** a palisade ordered on turn 7 is paid on turn 7, worked on turns 8 and 9, and stands at the end of turn 9. Recruit orders need the fort at the start of the turn, so it takes recruits from turn 10. The forecast says exactly that.
- **Costs, argued:**
  - A palisade (30 gold) is about 4 Spearmen or 3 Tuskers.
  - A keep from scratch (80 gold, 5 turns of work) is about one and a half turns of a full half's income.
  - One site at a time caps a faction at roughly four or five palisades, or two keeps, in a 20-turn game.
  - And every fort is a fort the enemy can take and recruit from.

### 2.5 construction under siege, and captured construction
- **An enemy army in the province** after battles (a siege, or an enemy just passing through) stops the work that turn. Nothing already done is lost.
- **Captured:** the site is **razed**. The work and the gold are lost, and the province keeps the level it had: capturing a palisade being raised to a keep gives the captor the palisade. Turn report: "The Thornmane Clans razed the half-built keep at Rivermarch when they took it. The palisade stands."
- **Can't be fortified:** a province with an enemy army in it, a besieged fort, a keep, a capital.

### 2.6 repair
- In each sieges phase where **no army of another faction stands in the province** after battles, a fort's walls rise by its level (palisade +1, keep +2, citadel +3), up to the maximum. A fort breached to 0 is whole again in 3 turns, whatever its level.
- Walls never repair under siege, and a captured fort keeps its walls as they were. If you take a breached fort, you hold a breached fort for a while.

---

## 3. sieges

### 3.1 inside and outside the walls
These words are used everywhere, and the codex entry `inside_outside` opens with four plain lines:
1. Walls help most if the enemy storms them: +2 defense for every 3 wall strength left.
2. A sally, a relief army, armies arriving together, and the fight after the breach are all in the open: nobody gets walls or ground, but the garrison's own fighters keep +2 cover from their fort.
3. An empty fort falls to whoever walks in.
4. From the turn after a real army besieges a fort, the fort is cut off: nobody can recruit there, and its income goes to the besiegers. A handful of pickets cuts nothing off.

The terms themselves:
- **The garrison** is the fort owner's armies that were in the province at the start of the turn and didn't move. They are **inside the walls**. A ruler's army counts.
- **Everyone else in the province is outside the walls.** That means enemy armies, whether they arrived this turn or were there already, and the owner's armies that arrive this turn (a **relief army**).
- **Besiegers** are enemy armies outside the walls of a fort that has standing walls and a garrison inside.
- If the owner's armies arrive while no enemy is there, they just go in, and from the next turn they are part of the garrison.

### 3.2 starting a siege
- **An army that ends its movement at an enemy fort with standing walls and a garrison inside doesn't fight. It besieges.** The exceptions: its faction ordered a storm (§3.5), or a relief army or a sally meets it outside (§3.6, §3.4).
- The province stays its owner's while the siege lasts. The capture phase already needs a single faction in a province, so nothing in capture changes.
- A siege needs no order. A policy or player that knows nothing about sieges still plays legal, sensible turns: its armies besiege by marching in, and its garrisons hold by standing still.
- **The siege's first turn already damages the walls,** because the siege camp goes up as the army arrives. The fort is not cut off until the second turn (§3.3), which gives the garrison a turn to sally against a raid before it loses anything.

### 3.3 what a siege does each turn
In the sieges phase, for each besieged fort in province id order:
1. **Siege damage** comes from the besiegers standing there after battles:

   | part | value |
   |---|---|
   | siege camp | 1 |
   | troops | +1 for every 10 troops, rounded down, at most +2 |
   | siege engines | +1 for each engine the besieging armies carry, at most +3, and at most 1 for every 5 troops |
   | **total** | **at most 6 a turn** |

2. **The walls drop by that much,** never below 0. If they reach 0, the fort is **breached** (§3.7).
3. **The cut-off** starts on the siege's second turn (the turn after it began) and lasts as long as the siege, **as long as the besiegers have at least half as many troops as the garrison** (rounded up). Fewer than that, and they are **pickets**: they still drop the walls, but they cut nothing off, take no income and block no recruits. One Fangthrower can't shut a capital. While it is cut off:
   - the province's **base income goes to the besieging faction** instead of its owner;
   - the owner's other income lines there are lost: Heavy Tithes, Royal Court, path lines, Forge Tithe;
   - nobody can recruit there, Warband Muster included: recruit orders at a fort besieged at the start of the turn are refused (§2.3);
   - the province still counts as its owner's for research (M4) and victory;
   - a siege lifted in this turn's battles cuts nothing off this turn.
   Turn report: "Crownkeep is cut off: its 12 gold went to the Thornmane Clans."

**Turns until the breach** (when siege damage doesn't change):

| besiegers | siege damage | palisade (3) | keep (6) | citadel (9) |
|---|---|---|---|---|
| a raid, 1-9 troops | 1 | 3 | 6 | 9 |
| 10-19 troops | 2 | 2 | 3 | 5 |
| 20+ troops | 3 | 1 | 2 | 3 |
| 20+ troops and 1 engine | 4 | 1 | 2 | 3 |
| 20+ troops and 2 engines | 5 | 1 | 2 | 2 |
| 20+ troops and 3 engines | 6 (the cap) | 1 | 1 | 2 |
| a raid of 5-9 troops with 1 engine (the most 5 troops can work) | 2 | 2 | 3 | 5 |

- **Why these numbers:**
  - Mid-game AI armies field 15-40 fighters a side (M3 §1.3: median 38 in late games). So a real army breaches a keep in 2 turns and a capital in 3, while a raid barely scratches a citadel.
  - Engines are the answer to a turtle. With 20+ troops, two engines turn a capital's siege from 3 turns to 2, and on its last turn the walls still stand at 4 (+4 if stormed), so that storm is still a real choice. A third engine turns a keep's siege from 2 turns to 1.
  - The cap means a capital always stands at least 2 turns, so the defender always gets at least one turn of orders between the siege starting and the breach.
- **The walls always fall.** Siege damage is at least 1 and walls don't repair under siege, so a siege that is kept up reaches a breach, and with it a battle, within 9 turns at worst and usually 2-3. Neither side can freeze a fort forever. This is the clock #94's stand-off needed.
- **State:** `Province.siege_since` holds the turn the current siege began (0 when there is none). The sieges phase sets `siege_since = current_turn + 1` (the turn being resolved, counted as players count turns). While resolving turn t, the fort is cut off when `0 < siege_since < t`, the siege still stands, and the besiegers' troops are at least half the garrison's (rounded up). Recruiting reads this at the start of the turn; income reads it after battles. A siege goes on as long as any enemy army stands outside after battles, even if the besieging faction changes (row 12 of §3.9).

### 3.4 the garrison's choices: hold, sally, leave
- **Hold** (no order): stay inside. The besiegers can only storm, wait for the breach, or leave.
- **Sally:** **SiegeOrder("sally", army)**, serialized as `{"type": "siege", "action": "sally", "army": id}`, **one per army**. Each army ordered to sally comes out and attacks every army outside the walls, **in the open: nobody defends, so nobody gets walls or terrain, but the sallying fighters keep +2 cover** from their walls (§4.1). Armies not ordered to sally stay inside.
  - **Legal when:** sieges are on; the army is yours, holds a fighter, and stands in its own fort; the fort was besieged at the start of the turn and its walls stand; and the army has no move order. Moving out is leaving, not sallying. The resolver checks sallies after every move, and OrderBook drops a sally when a move for that army is queued, wherever it comes in the list.
  - **If the sally wins,** the siege is lifted.
  - **If it loses,** the sallying armies are destroyed (no retreats, as always). Armies that stayed inside are unharmed. If none stayed, the fort is empty and the besiegers take it in the capture phase. The Sally toggle says so before you commit (§9.2).
  - **Why sally into the open:** a sally and the fight after the breach give the garrison the same +2 cover, so waiting only helps if the besiegers might storm or a relief might come. A garrison stronger than its besiegers should come out now, before it is cut off and before they grow; a weaker one waits for relief or for a storm. Battles are steep, so the forecast usually says plainly which side is stronger.
  - **Why per army:** mostly to keep your ruler inside. Armies can't be split and recruits join the first army at a fort, so a garrison is usually one army plus the ruler's. A small siege can't pin it for free, because pickets cut nothing off (§3.3).
- **Leave:** garrison armies may move out like any army. M1's "leaving first" rule applies: they are gone before anyone arrives, with no battle on the way out. A fort left empty is taken by the besiegers in the capture phase (§3.8).

### 3.5 the besiegers' choices: wait, storm, leave
- **Wait** (no order): the siege goes on and the walls drop.
- **Storm:** **SiegeOrder("storm", province)**, serialized as `{"type": "siege", "action": "storm", "province": id}`. **Every army of your faction at the fort after movement attacks the garrison** (the armies that stayed inside), your ruler's army included. The garrison defends with the walls (§4.1) and the terrain.
  - **Legal when:** sieges are on; the fort is another faction's; at the start of the turn its walls stood and a garrison was inside; and you have an army there, or a valid move order into it this turn. One storm order per fort per faction per turn.
  - **Storming from the march** is allowed: armies that arrive this turn and storm at once meet the walls as they stand. It is costly, but a real option with overwhelming force (§4.2).
  - **Called off:** if none of your armies stand at the fort after movement and border battles, or the garrison is gone, the storm is called off at no cost, with a report line.
  - **Storms are per fort, not per army,** because splitting a storm in two only feeds it to the walls piecemeal. Engines don't fight (§5), so nothing is lost by storming with all.
- **Leave:** besieging armies move away like any army. A siege with no besiegers left is lifted (§3.10).

### 3.6 relief
- **A relief army** is the owner's army arriving at its own besieged fort. It is outside the walls, so it meets the besiegers **in the open, where nobody defends**, and it gets no cover.
- **A relief army and a sally on the same turn fight together.** The owner gives both orders, which makes this the classic plan: march the relief in and order the garrison out to meet it. The move preview into your own besieged fort offers "The garrison comes out to join you", ticked by default for every garrison army except your ruler's, with both sets of odds shown (§9.2).
- **Sallies given with a relief are tied to it.** Such a sally carries the relief army's id (`"with": id` in its serialized form) and happens **only if that relief army stands outside the walls at the start of the battles phase**. If the relief was destroyed on the way (a border battle) or never set out, the tied sally is called off and the garrison stays inside (`sally_called_off`). Removing or cancelling the relief move removes its tied sallies, with the reason. The fort panel shows them as "sallying with the relief from Westwatch".
- If they win, the siege is lifted, and the relief army is inside from the next turn. If they lose, the relief army (and any sallying armies) is destroyed and the siege goes on; the walls still take this turn's damage.
- A road move (King's Roads, Forest Stride) into your own besieged fort is a relief like any other.
- When to relieve is a question of timing, not of ground: before the breach and after it, the fight is in the open, the garrison's fighters get +2 cover (sallying with you, or at the breach) and the relief gets none. Waiting only lets the besiegers grow and keeps your fort cut off.

### 3.7 the breach
- **At 0 wall strength the fort is breached and open.** If the garrison and the enemy are both still there at the next battles phase, they fight **on their own, with no order, in the open: nobody defends and nobody gets terrain, but the garrison's fighters keep +2 cover** among the ruins of their walls. Any relief army arriving that turn fights beside the garrison, without cover.
- Storm and sally orders at a breached fort are rejected with the reason "Stonegate's walls are down: the battle there comes on its own."
- **What a breach costs the garrison:** it loses its terrain and keeps +2 cover. On plains that is better than no fort (+2 against nothing); on hills it is about even (+2 defense against the hills' +1 defense and +1 attack). The hills of Stonegate and Blackwood count fully only in a storm. The walls chip at 0 and the garrison's breach line say so: "Breached: no walls and no hills; your garrison fights with +2 cover."
- Both sides see it coming: "The walls of Stonegate drop to 0 at the end of this turn (8). If you are both still there, you fight there next turn (9), in the open, your garrison with +2 cover." The besiegers may leave instead, and the garrison may leave or bring relief.
- An army that arrives at an enemy fort whose walls are already 0 (breached and not yet repaired) fights the garrison at once, in the open. There is no siege.
- **Why automatic, and why open:** an open fort is just a province with two enemies in it, and enemies in one province fight. Giving the garrison the ground and the defender's round-cap hold would make relief always wait for the breach (appendix A, round 1). The +2 cover is the same in a sally as at the breach, so relief timing stays neutral while home keeps an edge near parity (round 2). And it ends any chance of a besieger sitting on a breached fort forever.

### 3.8 empty forts
- **A fort with no garrison falls to the first army that walks in,** in the capture phase, as in M1. It keeps its level and its walls as they are; any construction there is razed. Its new owner can recruit there from the third turn after the capture (§2.3).
- If the owner's army and an enemy arrive at an empty fort on the same turn, they meet in the open (nobody defends), and the winner holds it.
- **Why:** a fort only delays an enemy if someone holds it. This is the strongest brake on fort spam (§11.1), because every empty fort is a recruiting post handed to the enemy.

### 3.9 when orders cross
Everything below happens in the battles phase, province by province in id order, after border battles, in one pass.
- **The rule:** at a fort, the only defender is a garrison being stormed. Every other battle there is in the open and nobody defends, but fighters coming from inside the walls (a sally, or the garrison at the breach) get +2 cover.
- **The order inside a province:** first the open battle outside the walls (if two or more factions are outside, counting sallying armies as their owner's), then the storm (if one was ordered and stormers and garrison armies are still there).
- An army can fight twice in a turn, exactly as an M1 border-battle winner can meet armies in its destination.

| # | at the start of the battles phase | what happens, in order | log `kind` / `why` |
|---|---|---|---|
| 1 | besiegers wait; garrison holds | no battle; the siege goes on | – |
| 2 | besiegers storm; garrison holds | a storm: the garrison defends with the walls and terrain | storm / storm |
| 3 | besiegers wait; garrison armies sally | an open battle: the sallying armies against every besieger | open / sally |
| 4 | besiegers storm; garrison armies sally | an open battle at the gate (sallying armies against the besiegers); then, if stormers still stand and armies stayed inside, the storm | open / gate, then storm / storm |
| 5 | a relief army arrives; garrison holds; besiegers wait | an open battle: relief against besiegers; the garrison stays inside | open / relief |
| 6 | a relief army arrives; garrison armies sally | one open battle: relief and sallying armies together against the besiegers | open / relief_sally |
| 7 | a relief army arrives; besiegers storm; garrison holds | an open battle (relief against besiegers); then, if stormers still stand, the storm | open / relief, then storm / storm |
| 8 | a relief army arrives; garrison armies sally; besiegers storm | one open battle (relief and sallying armies against the besiegers); then, if stormers still stand and armies stayed inside, the storm | open / relief_sally, then storm / storm |
| 9 | besiegers leave; garrison armies sally | no battle ("the garrison came out to find the siege lines empty"); the siege is lifted | – |
| 10 | besiegers leave; a relief army arrives | no battle; the siege is lifted and the relief army goes in | – |
| 11 | the garrison leaves; besiegers wait | no battle; the fort is empty and the besiegers take it in the capture phase | – |
| 12 | a second enemy faction arrives at a besieged fort (B was besieging; C arrives) | one open battle between everyone outside: B, C, and any sallying armies as a third side. The survivor besieges. A storm by B or C follows only if that faction ordered it and won | open / rivals, then storm / storm |
| 13 | an enemy arrives with a storm order where there was no siege | a storm at the walls as they stand | storm / storm |
| 14 | an enemy arrives without a storm order where there was no siege | no battle; a siege starts | – |
| 15 | an enemy and the owner's army arrive together, at an empty fort or at a garrisoned fort with no siege | an open battle between the arrivals (any garrison stays inside). At the empty fort the winner holds it; at the garrisoned one, an enemy that wins besieges | open / empty or open / relief |
| 16 | the walls were 0 at the start of the turn, with the garrison and enemies there | the battle through the breach, on its own and in the open: the owner's armies (garrison with +2 cover, and any relief) against the enemy | breach / breach |
| 17 | an enemy arrives at a fort whose walls are 0 and which has a garrison | the same battle at once; no siege | breach / breach |
| 18 | garrison armies gave a sally tied to a relief army (§3.6), and that relief army isn't outside the walls (destroyed on the way, or its move was refused) | no sally: the tied sallies are called off and those armies stay inside; then whatever the other rows say for the rest | – |

- **Determinism:**
  - Provinces are taken in id order. Within a province, the open battle comes first, then the storm.
  - Sides go in faction id order and armies in id order. Every draw comes from the turn's `SeededRNG`, in that order.
  - Battle ids `t<turn>b<index>` count battles in the order they are fought, so two battles in one province simply take consecutive indices.
  - **Sieges add no randomness outside battles:** siege damage, breaches, repair and construction are exact.
- **One pure function decides each battle.** `SiegeRules.next_battle(state, province_id, moved, siege_orders, fought)` returns the province's next battle, `{"kind": "open" | "storm" | "breach", "why", "sides", "defender", "from_inside"}`, or `{}` when there is none. `_province_battles` calls it in a loop on the surviving armies, since whether a storm follows depends on who won the open battle. Provinces without a fort keep M1's code path. The forecasts fight the same chain on each odds seed (§9.2), and a table-driven test checks all 18 rows (S-1b).
- **More than two sides** (row 12 with a sally) can happen only with three or more factions. The resolver already fights any number of sides; M3's playback shows two, and such a battle keeps its written report (M3 §3.2) until M6.

### 3.10 lifting a siege, and the fort falling
After battles, the sieges phase looks at each fort with `siege_since` set:
- **Only the owner's armies are there** (the besiegers left, lost a storm, or were beaten by a sally or relief): the siege is **lifted**. `siege_since` goes back to 0. The fort's income returns this turn, and it takes recruit orders again from the next turn (this turn's were refused at the start of the turn). Its walls repair from this sieges phase on (§2.6).
- **Only enemy armies are there** (a storm or breach battle destroyed the garrison, a sally lost with nobody left inside, or the garrison left): **the fort falls.** `siege_since` goes back to 0 with no damage, repair or work, a `siege_ended` event says so, and the capture phase hands the province over.
- **Both are there:** the siege goes on (§3.3).
- **Nobody is there** (both left): the siege is lifted.

---

## 4. battles at walls

### 4.1 the walls part
- **One new defense part, `"walls"`.** In a **storm** only, every fighter of the garrison gets +2 defense for every 3 wall strength still standing, rounded up: a full citadel +6; a citadel at 4-6 or a full keep +4; a palisade, a keep at 1-3 or a citadel at 1-3 +2; breached 0. The constants `WALLS_DEFENSE_PER_STEP = 2` and `WALL_STEP = 3` live in `AutoBattleResolver`, and every text players read is built from them.
- **Breakpoint-safe by construction.** The part is always a multiple of 2: +2 changes only the hit chance, +4 is one damage step, and +6 is one damage step plus a hit-chance step, as #41 requires.
- It stacks with the terrain (Stonegate's hills give the garrison +1 defense and +1 attack), Shield Wall, Rooted and every other part, each as its own named part.
- **Walls never count outside a storm.** Open battles and breach battles have no defender, so no walls and no terrain.
- **A second part, `"cover"`: +2 defense** to every fighter of the armies fighting **from inside the walls** (`from_inside`, §4.4) in a sally or a breach battle. Relief armies and besiegers never get it. It is a per-fighter part, like Rooted, so a relief army and a sallying garrison on one side get different defense. The constant is `COVER_DEFENSE = 2`, breakpoint-safe like every +2. The garrison therefore always has at least +2 from its fort, which matches the old flat fort bonus: +2, +4 or +6 if stormed, +2 in a sally or at the breach.
- **With sieges on, `"walls"` replaces `"fort"`.** The old flat +2 (`FORT_DEFENSE`) still applies in games without sieges, exactly as today. With sieges on, the battle log's `fort` flag still says whether the province has a fort (so the board draws it), and the new `siege` block (§4.4) says what the walls did.

### 4.2 what storming costs (measured)
Measured with the real `AutoBattleResolver` on `main` at bea3b51: a mid-game garrison of 240 gold on plains, stormed by the other faction's army. The walls were emulated by raising the garrison's defense. "Lost" is the share of the attacker's fighters lost in the battles it won. §4.2.1 says exactly what was run, so anyone can reproduce it; S-7 re-measures storms with the real `walls` part in the autoplay check.

| attacker's gold ÷ garrison's | in the open (a relief battle) | walls +2 (also the garrison's +2 cover in a sally or at the breach) | walls +4 | walls +6 (full citadel) |
|---|---|---|---|---|
| Clans storming the Crown, 1.0× | 57% won | 32% | 0% | 0% |
| Clans storming the Crown, 1.25× | 100% won, 32% lost | 98%, 37% | 56%, 48% | 22%, 53% |
| Clans storming the Crown, 1.5× | 100%, 20% | 100%, 23% | 100%, 36% | 95%, 40% |
| Crown storming the Clans, 1.0× | 43% | 23% | 1% | 0% |
| Crown storming the Clans, 1.25× | 100%, 36% | 96%, 40% | 20%, 51% | 5%, 52% |
| Crown storming the Clans, 1.5× | 100%, 20% | 100%, 23% | 97%, 36% | 83%, 42% |

- **What it means:**
  - In the open, about 1.25 times the gold wins. Against a garrison's +2 cover (a sally or the breach) it is the same at 1.25 times, but near parity the garrison gains 20-25 points.
  - Storming a full citadel takes about 1.5 times the gold and loses about twice as many fighters (40% instead of 20%). A full keep sits in between.
  - +2 matters only near parity, where it cuts about 20-25 points off the stormers' odds.
  - On hills the walls bite harder. At 1.5 times the gold, a storm of a 240-gold garrison in a full keep on hills, like Stonegate's (+4, and +1 for the hills), won 83-100%, and a storm of a full citadel on hills (+6, +1) only 12-16% (49-64% against a 120-gold garrison).
- **So the decision is real.** Storm now with about a third more army and heavier losses, or wait 2-3 turns for the breach (where the garrison still has +2 cover) while it is cut off, the besiegers take its income, and a relief may come. At the last step of walls (+2 if stormed), storming is the breach battle a turn early, with the garrison's terrain added: a timing choice. Battles are steep, so the forecast's odds are decisive, and they are shown before you commit (§9.2).
- At equal gold in the open, this particular mix favours the Clans (57% against 43%). That comes from how the armies were made up, not from a siege rule; band S6 watches the factions.

#### 4.2.1 how the numbers were measured
A throwaway GDScript `SceneTree` script, run headless with Godot 4.5.1 against `main` at bea3b51 (`godot --headless --path <repo> -s <script>`). It is not committed: this PR is design only, and S-7's autoplay check re-measures storms with the real `walls` part. To reproduce it:
- **Rules used:** `AutoBattleResolver.fight(sides, ctx, rng)` and nothing else: no `GameState` (`ctx.state` = null), so no rulers, mandates or paths. `ctx` = `{"kind": "province", "province": P, "province_ids": ["x"], "defender": <the garrison's faction id>}`, where `P` is a `Province` with `terrain` "plains" or "hills" and `has_fort` false. For the "in the open" runs, `defender` is "".
- **Armies:** `FactionData.create_factions()`. Each army is one `Army` holding its faction's commander plus units added in a repeating block until the army's cost (commander included) reaches its gold:
  - Crown block: Spearmen, Spearmen, Spearmen, Crossbowmen, Knights;
  - Clans block: Tuskers, Tuskers, Fangthrowers, Fangthrowers, War Bear.
  The garrison has 240 gold (and 120 for the hills note); the attacker has `int(240 × ratio)`, for ratios 1.0, 1.25, 1.5, 2.0, 2.5 and 3.0. Both factions were run in both roles.
- **Walls:** the garrison's unit types and commander are copied with `defense` raised by 0, 2, 4 or 6. Defense parts add up in `_defense`, so the hit chance and damage are the same as with a real `walls` part; only the "why" attribution differs.
- **Seeds:** battle `s` uses `SeededRNG.new(1000 + s × 7919)`. The 1.0× rows and the hills notes use s = 0-199 (200 battles per cell). The 1.25× and 1.5× rows, with their losses, use s = 0-99 (100 per cell).
- **Measures:** win rate = the share of battles whose `result.winner` is the attacker. Lost = the mean of `fighters_lost ÷ fighters_start` from the attacker's side in `result.report.sides`, over the battles it won.
- **The "in the open" column** for 1.25× and 1.5× is the walls +0 run with the garrison as defender. On plains a defender with no walls gets no bonus, and in the 200-battle runs the open and the walls +0 results were identical at every ratio.

### 4.3 open battles at a fort
- An open battle at a fort is an ordinary province battle (`kind` "province", so Rooted and Dread Lands work there as anywhere) with **no defender**: no terrain and no walls for anyone, and +2 cover for the fighters coming from inside. At the round cap the side with more of its strength left wins, as in M1's "arrived together".
- The report says which open battle it was:
  - "At Stonegate, the Aurel Crown's garrison sallied out against the Thornmane Clans' siege lines. Outside the walls nobody holds the ground."
  - "...a relief army reached Stonegate and met the siege lines, and the garrison sallied to join it."
  - "...the stormers met the sallying garrison at the gate."
  - "Through the breach at Stonegate, ..."

### 4.4 the battle event log (renderer-agnostic)
M3's contract holds: the resolver writes the log from the values it uses, recording is passive, and playback is a pure function of the log. M4 added its fields under a `"paths": true` flag instead of a version bump, and M3c does the same. A battle at a province with a fort, in a game with sieges, writes this at the top level:

```
"siege": {
  "kind": "storm" | "open" | "breach",
  "why": "storm" | "sally" | "gate" | "relief" | "relief_sally" | "rivals" | "empty" | "breach",   # per §3.9's last column
  "fort": "palisade" | "keep" | "citadel",   # the level's id
  "walls": 4, "walls_max": 6,               # at the battle; walls never change during a battle
  "walls_defense": 4,                       # the part each garrison fighter gets in a storm; 0 otherwise
  "cover_defense": 0,                       # 2 for the from_inside fighters in a sally or breach battle; 0 otherwise
  "garrison": 1,                            # the fort owner's side index, or -1 when the owner has no side
  "from_inside": ["kingdom-3"],             # the owner's armies fighting from inside: stormed, sallying,
                                            # or breach defenders. Relief armies are not in it
  "turn_of_siege": 3                        # 0 when there was no siege at the start of the turn
}
```

- **In a storm,** every attack on a garrison fighter carries `attack.defense.parts.walls`; **in a sally or breach battle,** every attack on a fighter from inside carries `attack.defense.parts.cover`, exactly as terrain and fort parts do today.
- **No new event types are needed inside a battle.** The walls are fixed for the whole battle, the breach happens between turns (§10.2), and a won storm uses the usual `end` and `aftermath` events, with the aftermath sentence saying the walls were taken.
- **Checks.** `BattleLog.validate` accepts `siege` and checks it against the header. A storm needs a garrison side and `walls` > 0; `walls_defense` = 2 × ceil(walls ÷ 3) in a storm and 0 otherwise; `cover_defense` = 2 exactly when `from_inside` fights in a sally or breach battle. `verify_draws`, `cross_check`, `regenerate` and M3-1's outcome-unchanged tests cover siege battles. **Every log from a game without sieges stays byte-identical.**
- **What the M3b 3D stage reads** (being built now on `m3b-3d-battles`; S-5 extends it):
  - `siege.kind` places the lines: a storm puts the garrison on the wall walk and the stormers at the foot with ladders or the trunk; a breach puts the garrison in the gap of the breached model; an open battle forms both lines before the gate.
  - `siege.walls` over `walls_max` picks the wall model (§10.1).
  - `from_inside` says who comes out of the gate.

### 4.5 the report's "why"
`AutoBattleResolver._factors` gains one factor, measured exactly like `terrain` and `fort` (what the part saved, in expected damage):
- `walls`: "the walls of Stonegate (4 of 6) gave the defending Aurel Crown +4 defense, worth about 19 damage", or "even though the walls of Crownkeep (9 of 9) gave the defending Aurel Crown +6 defense".
- `cover`: "the cover of Stonegate's walls (+2 defense) was worth about 9 damage to the Aurel Crown's sallying garrison".
- **The battle's first line names the kind:** "The Thornmane Clans stormed the walls of Crownkeep (9 of 9: +6 defense) on the second turn of the siege." / "Through the breach at Stonegate, ..."
- **The aftermath of a won storm or breach battle:** "The walls of Stonegate were taken. The Thornmane Clans hold the keep (2 of 6 walls)."
- The report's top level gains `siege`, the same block as the log's, so the battle report viewer can show the walls chip without the log.

---

## 5. siege engines
One engine per faction, added only when sieges are on, so M1/M2 rosters and armies are unchanged. They earn their place three ways:
- They are the answer to a turtle (a capital in 2 turns instead of 3).
- They make preparing a siege a decision: recruit engines at a forward keep, then march.
- They are the most readable siege picture on the board.

| id | name | faction | cost | trait |
|---|---|---|---|---|
| `siege_ram` | Siege Ram | Aurel Crown | 18 | Siege Engine |
| `wallbreakers` | Wallbreakers | Thornmane Clans | 16 | Siege Engine |

- **An engine is carried by an army, not a unit in it.** A recruited engine adds 1 to `Army.engines` of the army it joins (at most 3 an army). It is never a `Unit`, never in `army.units`, and never in the faction's `unit_types`. `TurnResolver.recruitable_type` offers the engine type only in a game with sieges.
- **Siege Engine** (the trait text players read): +1 siege damage each turn its army besieges. **An engine never fights.**
  - The battle code never sees an engine, because it reads only units, commanders and rulers. An engine adds no hp, morale or rank, and Wings, rout checks and the battle log never meet it.
  - **It moves with its army** and **is lost with it**: when its army is destroyed, in a lost battle or a won one in which all its fighters fell, its engines go too. The battle's aftermath says so: "...and its 2 Siege Rams were lost."
- **Each engine needs troops to work it.** At most 3 engines count in one siege, and at most 1 for every 5 troops besieging. One Fangthrower with three Wallbreakers does 1 siege damage, not 4.
- **Recruited at a keep or citadel only, into an army.** The engine joins the first army of yours at that fort that has a fighter and isn't a ruler's army, including one formed by a recruit ordered earlier that turn. If there is none, the order is refused at no cost: "Siege Rams need an army at Stonegate to carry them: recruit troops there first, or march an army in." Engines count toward the fort's recruit limit. Price rules apply as for any recruit (Muster Grounds, Blood Levy's price).
- **Moving engines to a siege** means marching the army that carries them. All your armies at a fort add their troops and engines to the siege, so a second army recruited at the forward keep can bring the engines up behind the main army. There is no order to hand engines from one army to another (§14).
- **Diminishing by design.** With 20+ troops, one engine takes siege damage from 3 to 4 (no faster at a citadel), two take it to 5 (a citadel in 2 turns), and three to 6, the cap (a keep in 1 turn). A fourth adds nothing. The recruit forecast says what each one would change before you buy it.
- **Data:** `FortData.ENGINES` holds each engine's id, name, faction, cost and text. The army's label adds them only when it carries some, in games with sieges: "Aurel Crown army at Highcrag (12 units, 2 Siege Rams, led by Knight Captain)". Tooltips show "Doesn't fight: +1 siege damage while besieging, for every 5 troops with it".
- **Why engines and not a "build siege works" order:** an order would be lighter for the rules, but engines that march with the army, can be seen coming, and are lost with it are the preparation pillar 3 asks for. Carried as a count on the army, they cost the battle rules nothing. The alternative, and the default the build uses, are §17 question 3.

---

## 6. turn resolution in M3c (phase order)
The fixed order. `RulesCodex "phase_order"` gains one sentence for games with sieges ("In a game with forts and sieges, sieges resolve between battles and capture: ..."), the way it already has one for paths.

1. **sacrifice:** as M2.
2. **orders:** every other order is checked against the state after sacrifices. **Siege orders** (storm, sally) are checked and recorded after every move order has been checked: a storm from the march against all of that faction's valid moves, road moves included, and a sally against any move for its army. Fortify orders are checked here and paid in recruitment.
3. **movement:** as before. Garrison armies that move leave the fort, and engines move with the armies that carry them.
4. **battles:** border battles, then each province in id order:
   - where there is no fort, an ordinary battle;
   - at a fort with standing walls, **the open battle outside the walls, then the storm** (§3.9), with nobody defending except a stormed garrison;
   - at a breached fort, **the battle through the breach**, in the open.
   After each battle, ruler deaths are recorded (M2).
5. **sieges** (new): each fort in id order:
   - **besieged** (the owner's armies and another faction's are there after battles): a new siege is recorded, the walls take siege damage, and a breach is recorded at 0;
   - **lifted, or fallen** (§3.10);
   - **repair**, where no army of another faction stands;
   - **construction:** one turn of work where no enemy army stands, and a finished level.
6. **capture:** as M4. An empty fort is captured with its level and walls, and construction there is razed. `owned_since` is set for the new owner (restored for a faction retaking its own fort within 2 turns, §2.3); Sworn Vassals sets it too.
7. **recruitment:** new Fortify orders are paid and their sites started, recruits are paid and arrive at their forts, and Warband Muster recruits gather, all in the order given from one pool.
8. **income:** a cut-off province pays its base income to the besiegers, and nothing to its owner.
9. **research:** as M4 (games with paths).
10. **rulers:** as M2.

- `TurnResolver.phases(state)` returns the list for a state's flags: PATH_PHASES or PHASES, with `"sieges"` after `"battles"` when sieges are on. `PHASES` and `PATH_PHASES` stay as they are (the paths-off test pins them). `GameSession.report_phases(state)` follows.
- **Why sieges come after battles and before capture:**
  - The brief's core loop names "movement, battles, sieges".
  - When a storm destroys the garrison, the stormers are left alone in the province, so the fort is captured that same turn.
  - Damage applies only to sieges still standing after this turn's battles.
- Construction and capture never happen in the same province on the same turn: work needs no enemy present, and capture needs one. So their order can't matter.

---

## 7. rulers, mandates and paths (what carries through)
Nothing in M2 or M4 changes, except Forge Tithe's count below. Where they meet M3c:
- **Rulers** garrison and besiege like any army, and a ruler's army alone can hold a fort. A successor still arrives at the capital, besieged or not ("the heir slipped in through the postern").
- **King's Roads and Forest Stride:** a road move into your own besieged fort is a relief, and a Forest Stride move into an enemy forest fort starts a siege. Road moves never fight border battles, as before.
- **Warband Muster:** recruits can't gather in a besieged province. The Ninth Fang besieging an enemy fort isn't in a province his faction owns, so M2's rule already stops field recruits there.
- **Sworn Vassals** can take a neutral fort (Stonegate, Blackwood), which joins with its keep.
- **Raiding Parties** pay on capturing a fort like on any province.
- **Dread Lands and Rooted** work in every battle at a fort, since all of them are province battles. Dread Lands works only where the Blood Pact owned the province at the start of the turn: in its own storms, sallies, reliefs and breach battles.
- **The Forges** (Living Iron) heal a garrison to full every turn, besieged or not.
- **Forge Tithe,** in games with sieges, pays +4 for every **keep or citadel** you own, and not for a cut-off one. Palisades don't count, or Living Iron would gain 4 gold a turn from every 30-gold palisade (appendix A); §11.3 keeps the knob.
- **Hallowed Land and Mending Light** heal inside the walls as anywhere.
- **Research** counts a besieged province as its owner's; only its income moves.
- **Victory** is unchanged: the game ends when a capital is captured. A besieged capital is not captured.

---

## 8. AI
Built on `AIPlayer` as it stands after #94 (stand-offs read from the state alone, then hunt, besiege or raid). Nothing below runs without sieges, so M1, M2 and M4 AI games stay identical. Every decision that risks an army uses `Forecast` odds, which fight the real battle rules through `SiegeRules.next_battle` (§9.2).

### 8.1 constants
S-7 tuned these within §11.3's ±0.1 and ±1 (the first values the build used are in §11.4, before → after). `REACH`, `STANDOFF_START_WIN` and `CAPITAL_RELIEF_WIN` are named in the rows' text; all of them live at the top of `ai/ai_sieges.gd`.

| name | value | use |
|---|---|---|
| `STORM_WIN` | 0.75 | storm a fort when the storm odds are at least this |
| `CAPITAL_STORM_WIN` | 0.6 | storm the enemy capital (taking it wins the game) |
| `RACE_STORM_WIN` | 0.55 | storm when an enemy relief army can reach the fort this turn |
| `SIEGE_START_WIN` | 0.45 | start a siege only if our odds against the garrison with its +2 cover, plus every enemy army that could reach the fort within `REACH` (1) move, are at least this; `STANDOFF_START_WIN` 0.4 in a #94 stand-off |
| `SIEGE_STAY_WIN` | 0.35 | stay while those odds are at least this; on the turn before the breach, stay only at `SIEGE_START_WIN` |
| `SIEGE_SALLY_WIN` | 0.55 | our garrison armies sally at these odds (M1's `SALLY_WIN` of 0.9 stays for coming out of a capital that isn't besieged) |
| `RELIEF_WIN` | 0.55 | send relief, with a sally, when the combined odds are at least this; `CAPITAL_RELIEF_WIN` 0.4 for the capital |
| `ABANDON_ODDS` | 0.35 | leave a non-capital fort before its breach when the odds in the open are below this and no relief can come within `REACH` moves |
| `ENGINES_PER_SIEGE` | 2 | engines the AI brings to a siege (3 when the objective is a keep, where the third saves a turn), never more than 1 for every 5 troops |
| `FORTIFY_TURN` | 6 | first turn the AI builds a fort |
| `MUSTER_WEIGHT` | 0.25 | how much a fort's recruit limit adds to its capture value (§8.2) |

### 8.2 besieging and storming
- **Targets:** an enemy fort on the main army's road to the enemy capital, or the capital itself.
  - An **empty** enemy fort next to a free army is walked into: a recruiting post for nothing.
  - A fort's capture value adds `MUSTER_WEIGHT` × its recruit limit × the price of our cheapest troop, so a keep counts about as one extra province of income (0.25 × 4 × 8 = 8 gold). Under siege, the province's base income counts for us from the second turn.
- **Start a siege** when our odds against the garrison with its +2 cover, plus every enemy army that could reach the fort within `REACH` moves, are at least `SIEGE_START_WIN`. Sallies and breach battles are the same battle (open, garrison with cover), so that one number answers both "can they come out and beat us?" and "do we win at the breach?". Otherwise mass, raid or wait, as today.
- **Each turn of a siege:**
  - storm when the storm odds reach `STORM_WIN` (`CAPITAL_STORM_WIN` at the enemy capital), or `RACE_STORM_WIN` when a relief army can reach the fort this turn;
  - otherwise wait;
  - leave when the stay rule says go.
- **No dance.** The start and stay tests both count every enemy army within `REACH` moves of the fort, so stepping a relief army back out of reach and in again doesn't bring the AI back into a siege it would lose. **S-7 set `REACH` to 1 (it was 2):** against two computers it was the single most effective of §11.3's knobs on the stand-offs (§11.4), but it means a relief army two provinces away no longer deters a siege, so a player can dance a relief army two provinces back and in again. That is Alex's call to keep or revert (§11.4). If it leaves because of relief, it attacks the relief army at `LIKELY_WIN`, or turns to another fort, or raids. All of this is read from positions in the state, with no memory between turns (#94's rule).
- **Engines:** when the main army's next objective is a fort with a garrison and standing walls, recruit engines at our keep or citadel nearest the objective, into the army there (with troops recruited first if no army stands there), and march that army to join the main army. Up to `ENGINES_PER_SIEGE`, and only while the capital's garrison need is met. The recruit forecast's "turns saved" decides whether each one is worth buying.
- **Never a cycle.** The AI besieges only what it would win in the open. Once in a siege it stays until the breach battle unless the stay rule says go. The walls drop by at least 1 a turn, so every siege it keeps up ends in a battle within a few turns.

### 8.3 defending forts
- **Capital threat, re-read.** An enemy army next to our capital can no longer simply attack it: it can storm (walls +6) or besiege. The recall rule uses the enemy's storm odds for this turn and the siege timeline for the turns after, so the AI keeps fewer armies at home and has more in the field.
- **Under siege:**
  - If a relief army can reach the fort this turn and the combined relief-and-sally odds reach `RELIEF_WIN` (0.5 at the capital), send it and sally with every garrison army but the ruler's.
  - Otherwise, sally with the armies whose odds alone reach `SIEGE_SALLY_WIN`, keeping the rest inside.
  - Otherwise hold, recruit at other forts, and march relief toward the fort.
  - A non-capital fort whose odds in the open are below `ABANDON_ODDS`, with no relief within `REACH` moves, is abandoned the turn before its breach if a safe neighbour exists.
- **Garrisons.** The AI leaves at least one army in each keep or citadel it owns that an enemy army could reach this turn, and in a palisade when it has an army to spare. It never hands a fort to a passing raider.

### 8.4 recruiting and building
- **Recruits:** gold is spent across our forts that aren't besieged and that we have held since the start of the previous turn:
  - first the capital, up to its limit, while it is threatened or its garrison need isn't met;
  - then the fort nearest the main army's objective (the forward muster);
  - then the capital and the other forts.
  Limits and level rules come from `SiegeRules`, so the AI never orders an illegal recruit.
- **Fortify,** from `FORTIFY_TURN`, one site at a time:
  - a **palisade** in a province we owned at the start of the turn, at least 2 moves from our capital, with no enemy army next to it, nearest the enemy capital (ties: income, then id), when the gold left after this turn's recruit plan is at least its cost or the recruit limits leave that much unspent;
  - an **upgrade** of the palisade nearest the front to a keep, when no enemy army is within `REACH` moves of it and 50 gold is left over.
- **Stand-offs (#94):** with sieges on, #94's "siege" action is a real siege. The main army besieges the enemy capital, or the nearest enemy fort on its road, with `SIEGE_START_WIN` at 0.5 and engines bought for it.

### 8.5 what the player sees of it
- The AI's notes (`last_plan_notes`, the "what is the computer doing" tooltip that #94 reuses) gain plain lines:
  - "Besieging Stonegate: its walls (6) drop to 0 in 2 turns, and in the open we likely win (19 of 24 test battles)."
  - "Storming Crownkeep now: its relief army at Highcrag could reach it this turn."
  - "Sallying out of Blackwood with the relief from Ebonpeak (odds: likely win)."
  - "Building a palisade at Rivermarch, to recruit nearer the front."
- **Legal orders only:** zero rejections over a 30-turn game, as in M2 and M4 (a test). The AI never reads another faction's orders, only the state.

---

## 9. approachability (mandatory; every M3c ticket ships its own part)

### 9.1 each mechanic and where it explains itself

| mechanic | tooltip or breakdown | forecast or preview | turn report | codex |
|---|---|---|---|---|
| fort levels | the fort chip on the province plate and panel: level, walls, recruits a turn, repair | the Fortify preview (§9.2) | `fort_built` | `fort_levels`, `palisade`, `keep`, `citadel` |
| recruiting at forts | the recruit panel's "Recruit at" picker, each fort with "2 of 4 this turn", greyed with the reason | the recruit forecast names the fort and the army the recruit joins | `recruited` says where | `recruit_at_forts`, `recruit` |
| Fortify and construction | the construction chip: "Palisade: 1 of 2 turns of work" | cost, the turn it stands, the turn it takes recruits, how long it holds, "one fort at a time" | `construction_started`, `construction_halted`, `fort_built`, `construction_razed` | `fortify`, `construction` |
| walls | "Walls 5 of 9: +4 defense if stormed", with the rule line | the turn they reach 0 | `walls_damaged`, `walls_breached`, `walls_repaired` | `walls`, `repair` |
| inside and outside | the province panel lists "Inside the walls" and "Outside the walls" | the move forecast says which an army will be | every siege line uses the words | `inside_outside` |
| starting a siege | the move preview into an enemy fort: **Besiege** or **Storm now**, with odds (§9.2) | turns until the breach, odds in the open, storm odds | `siege_started` (with a first-time explanation, §9.5) | `siege` |
| siege damage | "Siege damage 5 a turn = siege camp 1 + 22 troops +2 + 2 Wallbreakers +2 (1 for every 5 troops; at most 6)" | turns until the breach, and what one more engine would change | in `walls_damaged` | `siege_damage` |
| the cut-off | the income and recruit breakdowns: "cut off: 8 to the Thornmane Clans" | the gold forecasts of both sides, from the second turn | `income` names cut-off provinces on both sides | `cut_off` |
| storm | the move preview and the fort panel's Storm toggle: "All 3 of your armies at Stonegate storm, your ruler's included. To keep an army out, move it away." | storm odds now and the odds in the open at the breach | the battle line, or `storm_called_off` | `storm`, `battle_walls` |
| sally | the fort panel's Sally ticks, one per army, ruler off by default: "If they lose, the armies that came out are destroyed. 1 army stays inside." | odds for the armies ticked; with a relief army ordered in, the combined odds | the battle line, or `sally_found_nothing` | `sally` |
| relief | the move preview into your own besieged fort, with "The garrison comes out to join you" ticked | relief odds, with and without the sally | the battle line | `relief` |
| the breach | the walls chip turns to "breached" | "you fight at Stonegate next turn (9), in the open, unless you leave: odds ..." | `walls_breached` | `breach` |
| empty forts | the move preview into an empty enemy fort | "You take the keep at Stonegate unopposed (6 of 6 walls). You can recruit there from turn 10." | `captured` says the fort came with it | `empty_fort` |
| siege engines | the army tooltip lists them: "2 Siege Rams: don't fight; +1 siege damage each while besieging, for every 5 troops with them" | the recruit forecast: "joins the Aurel Crown army at Stonegate; +1 siege damage at Crownkeep: the walls drop to 0 in 2 turns instead of 3" | `recruited`; a lost battle's aftermath names lost engines | `trait_siege_engine`, `unit_siege_ram`, `unit_wallbreakers` |

### 9.2 forecasts (all from `SiegeRules`, the functions the resolver uses)
- **Text rules for every siege forecast and report line:**
  - Give both the relative and the absolute turn: "at the end of this turn (8)", "in 2 turns (turn 10)".
  - The walls "drop from 6 to 3"; "breached" means 0.
  - A breach turn always carries its condition: "turn 9 if the besiegers stay as they are; turn 8 if an engine joins them".
- **`Forecast.siege(state, fid, province, orders)`** gives:
  - the walls now and the storm defense they give;
  - siege damage with its parts;
  - the turn they reach 0;
  - whether the fort is cut off, and from when;
  - storm odds now, and the odds against the garrison with its +2 cover (a sally or the breach) and against a relief;
  - **and the other side's options,** because both sides order at once.

  Besieger's side: "Crownkeep's walls (9 of 9: +6 if stormed) drop by 3 a turn (siege camp 1, 24 troops +2) and reach 0 at the end of turn 11, in 3 turns, if you stay as you are. Storming now: likely loss (4 of 24 test battles won). Against their garrison with its +2 cover, as in a sally or at the breach: likely win (21 of 24). Their army at Highcrag can reach Crownkeep this turn: with it, close (13 of 24). From next turn (10) Crownkeep is cut off, and its 12 gold a turn comes to you."

  Garrison's side: "Your walls at Stonegate (4 of 6: +4 if stormed) drop to 1 at the end of this turn (8) and to 0 next turn (9) if the besiegers stay as they are. If they storm this turn, you likely hold (20 of 24). Sallying now with all 3 armies: close (11 of 24). Your army at Westwatch can reach Stonegate this turn: relief and sally together, likely win (18 of 24)."
- **Forecast equals result:** when no army enters or leaves the province, the walls reach 0 on the forecast turn and the cut-off starts on the forecast turn (S-1a's test; band S9 counts mismatches across every AI game).
- **`Forecast.storm_odds`, `sally_odds`, `relief_odds` and `breach_odds`** fight the real resolver through `SiegeRules.next_battle`. Where a plan chains two battles (§3.9 rows 4, 7, 8, 12), each odds seed fights the chain. `Forecast.battle_odds` and the move forecast route through the same plan, so a move into an enemy fort no longer promises "+2 fort" or a battle that won't happen (S-2).
- **`Forecast.fortify(state, fid, province, orders)`** says what the fort costs, when it stands, and how long it holds: "Palisade at Rivermarch: 30 gold now (14 left after your recruits). Built at the end of turn 9 if no enemy army stands there; you can recruit 2 a turn there from turn 10. Walls 3: against a raid they hold 3 turns, against 20 or more troops 1 turn, and they give +2 defense only if stormed. You can build one fort at a time." Rejections say why: "You are already building a keep at Greenglade (2 of 3 turns)."
- **The move forecast** into an enemy fort, your own besieged fort or an empty fort says which row of §3.9 it will be, with odds wherever there is a battle. Moving into your own fort while no siege is there warns: "If an enemy arrives there this turn too, you meet outside the walls, where nobody gets walls or ground."
- **The recruit forecast** names the fort and its count: "Spearmen at Stonegate (3 of 4 this turn): they join the Aurel Crown army there."
- **The gold forecast** shows a cut-off province's income going to the besiegers from the turn the cut-off starts, on both sides.
- **Battle odds everywhere** read the walls and the open-battle rule, because they fight the real resolver through the same plan.

### 9.3 tooltips and breakdowns
Every number explains itself on hover, through `Breakdown` (the lines add up to the total, as in M1):
- **Walls:** "Walls 5 of 9 = citadel 9 − siege damage 4 (turn 1: −4)". Repair: "+3 a turn while no enemy is here (citadel)".
- **Walls if stormed:** "+4 defense = 2 for every 3 wall strength standing: 5 → 2 steps (rounded up)".
- **Siege damage:** "5 a turn = siege camp 1 + 22 troops +2 (1 for every 10, at most 2) + 2 engines +2 (1 each, at most 3 and 1 for every 5 troops); at most 6".
- **Cut-off:** "Cut off: the Thornmane Clans have 22 troops outside, at least half of your 30 (15)." / "Not cut off: 4 troops outside are only pickets (half of your 30 is 15)."
- **Cover:** "+2 defense = cover of Stonegate's walls (fighting from inside, in a sally or at the breach)".
- **Recruit limit:** "Stonegate takes 4 recruits a turn (keep). Ordered: 3."
- **Province income, owner's side:** "Income of Stonegate 0 = base 8 − cut off 8 (besieged since turn 7; its income goes to the Thornmane Clans)". Besieger's side: "Stonegate (besieged) +8".
- **Construction:** "Keep at Greenglade: 2 of 3 turns of work done; stopped on turn 9 (an enemy army was there)".

### 9.4 turn report
New event types, each with `codex` set (phase in brackets):
- `siege_started` (sieges): "The Thornmane Clans laid siege to Stonegate with 22 troops and 2 Wallbreakers. Its walls dropped from 6 to 1 (siege damage 5). From next turn (8) Stonegate is cut off. The walls reach 0 next turn (8) if the besiegers stay as they are." The owner gets the same facts with "your".
- `walls_damaged` (sieges): "The siege of Crownkeep, turn 2: the walls dropped from 6 to 3 (+2 if stormed). They reach 0 next turn (11), if the besiegers stay as they are."
- `walls_breached` (sieges): "The walls of Stonegate are down (breached). If both sides are still there next turn (9), they fight there in the open, with no order."
- `siege_lifted` and `siege_ended` (sieges): "The siege of Blackwood is over: the relief army from Ebonpeak and the sallying garrison destroyed the Aurel Crown's siege lines." / "...the besiegers left." / "Stonegate fell: the Thornmane Clans' storm destroyed its garrison."
- `walls_repaired` (sieges): "The walls of Stonegate were repaired from 1 to 3 (+2 a turn, keep)."
- `construction_started` (recruitment), `construction_halted` (sieges), `fort_built` (sieges), `construction_razed` (capture): the sentences in §2.4-2.5.
- `storm_called_off`, `sally_called_off` and `sally_found_nothing` (battles): §3.5, §3.6 and row 9 of §3.9. "The garrison of Stonegate stayed inside: the relief from Westwatch never arrived."
- **Battle events** at forts carry `numbers.siege` (§4.4) and the causes `storm`, `breach`, `sally`, `gate`, `relief`, `relief_sally`, `rivals`, `empty`.
- **Clauses on existing events:**
  - `recruited` names the fort: "at Stonegate (keep, 3 of 4 this turn)".
  - `income` names cut-off provinces on both sides: "Stonegate paid nothing: it is cut off, and its 8 gold went to the Thornmane Clans." / "...and 8 from besieged Stonegate."
  - `captured` says a fort came with the province: "with its keep, 2 of 6 walls; you can recruit there from turn 10".
  - a battle's aftermath names engines lost with their armies: "...and its 2 Siege Rams were lost."
- **"Needs you" lines:**
  - "Your fort at Stonegate is besieged: its walls reach 0 in 2 turns (end of turn 9), if the besiegers stay as they are. Sally, send relief, or hold."
  - "Your armies besiege Crownkeep: storm, wait for the walls to reach 0 in 3 turns (end of turn 11), or leave."
  - On the breach, to both sides: "Stonegate's walls are down. Next turn (9) you fight there in the open, unless you leave: odds 14 of 24."

### 9.5 the first siege (a teaching moment)
The first `siege_started` event of a game, in both players' reports, ends with two plain sentences and a codex link: "A siege: the besiegers don't fight unless they storm the walls or the garrison comes out. Each turn the walls drop a little, and when they are down the battle comes on its own." The first storm, sally and breach each get one such sentence too. Later sieges add nothing.

### 9.6 codex entries (`RulesCodex`), all new terms
- **Forts (S-1a):** `fort` (updated: levels, recruiting, walls), `fort_levels`, `palisade`, `keep`, `citadel`, `recruit_at_forts`, `fortify`, `construction`.
- **Walls (S-1a):** `walls`, `repair`.
- **Sieges (S-1a):** `siege`, `inside_outside`, `siege_damage`, `cut_off`, `storm`, `sally`, `relief`, `breach`, `empty_fort`.
- **Engines (S-1a):** `trait_siege_engine`, `unit_siege_ram`, `unit_wallbreakers`.
- **Battles (S-2):** `battle_walls`, `battle_open` (outside the walls), `battle_breach`.
- **Updated entries:**
  - S-1a: `phase_order` (§6's sentence), `orders` (siege and Fortify orders), `recruit` (recruiting at forts), `income` (the cut-off), `capture` (empty forts, razed construction), `move` and `defended` (arriving at a fort), `victory` (a besieged capital is not lost), `mandate_forge_tithe` (keeps and citadels).
  - S-2: `battle_terrain` (walls replace the fort's +2 when sieges are on), `battle_rounds` (engines don't fight).

### 9.7 battle report viewer and Watch
- The defender chips gain one of three, each with a codex link:
  - in a storm: "Walls: +4 defense (5 of 9)";
  - in an open battle: "Outside the walls: nobody holds the ground; the garrison's fighters have +2 cover" (no cover line in a relief-only battle);
  - in a breach battle: "Through the breach: no walls, and nobody gets the hills".
- Hovering an attack on a garrison fighter shows the walls part in its defense breakdown (M3's hover reads the log's parts).
- Watch works for every siege battle with two sides.

---

## 10. the 3D board
The board reads only the state and the resolver's events, never writes to them, and never draws a random number (3D_DIRECTION §2). M3c adds no rule the board has to compute: every number it shows comes from `SiegeRules` and the events.

### 10.1 what the board draws from the state
| state | what the board draws |
|---|---|
| `fort_level` 1 / 2 / 3 | the kit: `palisade.<faction>` (new), `fort.<faction>` (today's fort) or `fortress.<faction>` (today's fortress). Map forts use the nearest capital's faction (today's rule); a built fort uses `fort_by`'s kit; a captured fort keeps its look and flies the new owner's banners |
| walls | a **damage look** that changes exactly where the storm defense does, one look per step of 3 lost: intact while every step stands (a citadel at 7-9, a keep at 4-6, a palisade at 1-3), damaged with one step lost, the damaged model plus code smoke, fire and rubble with two lost (a citadel at 1-3), and breached at 0. The plate's walls bar marks the same steps. So what you see on the land is what a storm would meet; the plate and tooltips give the number. A missing model falls back to code: a dither-cut notch in the wall (`model_common` `cut_plane`, as the close-up already uses), rubble props and smoke billboards |
| construction | scaffolding around the site, and the next level's model rising by a cut plane as work is done (1 of 2 turns: half height) |
| a besieged fort | the besiegers' armies in a **ring of camps** outside the walls (`camp.<faction>` models, one per army, facing the walls); the besieging faction's **siege works** model on the gate side; the engines their armies carry, at the walls; and **chevron banners** in the besieger's colour planted round the walls (the bible's "besieged" marker, drawn in code). The garrison stands in the yard. Any overflow packs tight behind the gate, since the war camp outside now belongs to the besiegers, and the plate keeps the exact count |
| cut-off | the province plate's income shows 0 with a siege glyph and an arrow to the besieger's colour; the village chimneys stop smoking (cosmetic) |

### 10.2 what it plays from the events
Each beat plays in its phase, in report order, at 1×, 2× or 4×, and its turn report line lights up as it plays (3D_DIRECTION §6.4).

| event (phase) | beat |
|---|---|
| `army_moved` into a besieged or enemy fort (movement) | the column marches the road; an army that will besiege fans out to its camp slot in the ring |
| `battle` with `siege.why` "sally" (battles) | **the garrison spills out of the gate** in a column two abreast (the `from_inside` armies), forms up facing the camps, and the lines clash (the clash beat; Watch opens the full battle) |
| `battle` with "relief" or "relief_sally" | the relief column arrives on the road; with a sally, the gate opens at the same moment |
| `battle` with "storm" | the stormers rush the walls with ladders (Crown) or the trunk (Clans), and the clash beat plays at the wall line |
| `battle` with "breach" | the lines meet in the breach |
| `siege_started` (sieges) | tents go up round the walls, the chevrons rise, the engines take their places, and the first strike plays as in `walls_damaged` |
| `walls_damaged` (sieges) | engines and the siege camp strike (strike poses), dust billboards rise at the wall, and the damage look updates at the end of the beat |
| `walls_breached` (sieges) | a wall section collapses: a swap to the breached model, a rubble burst (M3's dust effect sheet), and a rule-bound camera shake (M3 §4.5) |
| `siege_lifted` / `siege_ended` (sieges) | camps fold and march off (besiegers left), topple (beaten), or the banners change on the walls (the fort fell); the chevrons fall |
| `walls_repaired` (sieges) | a short masons' dust beat, and the damage look steps back |
| `construction_started` (recruitment), `fort_built` (sieges), `construction_razed` (capture) | scaffolding appears; the walls rise and the new kit swaps in; the scaffolding collapses in smoke |
| `recruited` at any fort (recruitment) | recruits march in through that fort's gate into its yard (M3a.2's muster beat, generalized from the capital to every fort) |

- **Playback equals the state** (3D_DIRECTION §6.4's test) still holds with sieges. Applying a turn's events to the board model of the state before gives the board model of the state after: levels, damage looks, construction, camp rings and who stands inside, over 5 seeds × 15 turns with sieges on (S-4).
- **Hotseat:** siege and Fortify orders stay private until the turn resolves, like every order. Storm and sally ticks and ghost scaffolding show only in their owner's view.

### 10.3 battles at walls on the M3b stage
M3b (#58, re-scoped and being built now) stages battles on the province from the log. With `siege` present (S-5):
- **Storm:** the garrison stands on the wall walk of the walls model, with its Volley tier and the Ever-Regent along the top. The stormers form at the foot and advance with ladders or the trunk. Hits on garrison fighters show the walls chip in the hover.
- **Breach:** the breached model, with the garrison's front rank filling the gap.
- **Open:** both lines form before the gate, and the `from_inside` armies march out of it first.
- Engines aren't fighters, so they stand as scenery in the besiegers' camp. The playback still never changes the outcome (M3's three test levels).

---

## 11. balance intent

### 11.1 the shape we want
- **Forts make war a series of decisions, not one pile-up:** where to recruit, what to fortify, whether to storm now or wait, whether to sally or hold for relief.
- **Turtling loses.** A turtle that stacks its capital is cut off from the siege's second turn by any real army (half its troops or more): its capital's 12 gold a turn goes to the besiegers, a 24-gold swing. Then it fights at the breach with +2 cover and no terrain, which is the same +2 M1's fort gave it, but after 2-3 turns of shrinking against a growing enemy. It can still recruit at its other forts, which is why taking those first matters.
- **Raids can't pin a fort for free.** Pickets (under half the garrison's troops) cut nothing off; a real besieging army can be sallied against in the open, where the garrison keeps its cover.
- **Fort spam doesn't pay.** One site at a time; 30-80 gold a fort; empty forts falling to anyone; captured forts recruiting for the captor after a turn; a 20-troop army breaching a palisade in one turn.
- **Storming is the expensive shortcut, and waiting the cheap, slow way** (§4.2): about a third more army and twice the losses, against 2-3 turns in which relief can come and the besiegers take the fort's income.
- **Sieges end games.** The walls always fall, so every siege reaches a battle. The 21% of games that stalled at the cap in M4-6 should mostly become sieges.
- **First-pass numbers.** They follow #41's breakpoint rule and the measurements in §4.2. S-7 measures them and tunes within §11.3.

### 11.2 autoplay bands (checked by S-7)
- **Setup:** both seats run `AIPlayer` with sieges on and rulers on.
- **Cells:** all 9 preset pairings × both seat orders × paths off and on (sides of the fork rolled) × 25 games = **900 siege games**. The same 900 seeds with sieges off are the baseline for S1 and S6. Band S7 adds 100 games of the `turtle` policy against `ai`; the turtle is taught to build a palisade and then a keep at its safest province, recruit there too, and never attack. For scale, M2's 1,206 games took about 2 minutes with 8 jobs.
- "Decisive" means finished and not a draw. A pairing with fewer than 60 decisive games doubles its games.

| band | what | target |
|---|---|---|
| S1. length | all siege games | median decisive game **12-22 turns**; at most **5%** at the 60-turn cap (the sieges-off baseline is reported beside it) |
| S2. sieges happen | all siege games | a siege starts in **60%+** of games reaching turn 12; report the share of capitals taken by storm or through a breach |
| S3. storm or wait | every battle at a fort with a siege | storms are **15-60%** of them (both choices get used); report the AI's storm win rate (expected 55-85%) |
| S4. forts built, not spammed | per faction per game | median forts built **1-3**; 95th percentile **5 or fewer** |
| S5. recruiting at forts matters | all recruits | **10-50%** made outside the capital |
| S6. nothing new dominates | preset pairings and factions | no pairing above 65% that was at or below 65% with sieges off on the same seeds; Crown / Clans reported (a miss goes to Alex rather than being tuned silently, as with M2's band C) |
| S7. turtling loses | `turtle` vs `ai` | the turtle wins **10% or fewer** of decisive games, and at most **10%** reach the cap |
| S8. off is identical | sieges off | `main_records.json`, `m2_matrix_digests.json` and the new M4 path fixture replay byte-identically; M4's P7 still passes |
| S9. integrity | everything | 0 invariant violations (walls in 0..max; levels change only by construction or capture; one site per faction; gold counts Fortify spending and cut-off income; nothing recruited at a cut-off fort or at one captured last turn; two factions share a province only in a siege; engines only on armies with a fighter, at most 3 each; no battle side without a fighter); 0 session or script errors; replaying every 10th game gives an identical final state; **0 siege forecast mismatches** (walls reach 0 on the forecast turn when no army entered or left) |
| S10. defence works (report) | sieges | the share ended by a sally or relief (target 10%+); the share of relief chances the AI took |

Bots aren't humans: the bands prove that nothing is broken or dominant for the bots. Alex's playtest is the real check.

#### 11.2.1 how S-7 reads each band
`autoplay.gd -- --matrix --sieges --independents --jobs 4` runs all of §11.2 (`tools/autoplay/siege_matrix.gd`). **The balance contract is the MVP config: independents on** (Alex, 10-5), in the siege games, the sieges-off baseline and the turtle games alike; a run without `--independents` is report-only for the balance bands. **The bands are target ranges we tune toward, not hard caps** (Alex, 10-8): the report prints each as pass or miss with the diagnostic behind a miss. The exit code is 0 only when S8 and S9 hold. Where §11.2 left a word open, the check reads it like this:
- **Games:** 900 siege games (the 9 preset pairings × both seat orders × paths off and on × 25), the same 900 seeds with sieges off, 100 games of the turtle against `ai` (and the same 100 with sieges off), and the 72 M2 matrix games for S8. A pairing with fewer than 60 decisive siege games plays its siege games and its baseline again on the next seeds, once.
- **S1:** decisive is finished and not a draw. The median is of decisive games; the cap share is of all games.
- **S2:** "a siege starts" is a `siege_started` event. A capital "taken by storm or through a breach" is judged on the battle at the capital in the turn it fell: a storm, a battle after the breach, an open battle at the gate, or no battle (the garrison had left and the besiegers walked in).
- **S3:** a battle at a fort with a siege is every battle with a siege block except an arrival at an empty fort. A storm is one of kind `storm`, including a storm from the march. The storm win rate is the stormers' wins.
- **S4:** a fort is a place: forts built counts palisades finished where there was none, per faction per game (§2.4: "four or five palisades, or two keeps"). A keep made of a palisade is the same fort one level up; the report prints it, and the count of every level finished, beside.
- **S5:** all recruits at forts, the capital included, are the denominator; Warband Muster recruits (made with the ruler, at no fort) are reported beside. Siege engines count as recruits.
- **S6:** a pairing is a Crown preset against a Clans preset, pooled over seat orders and over paths off and on. For each pairing above 65% the report says how many standard errors apart it is from the sieges-off share, so a tilt that is noise can be told from one that is not.
- **S7:** the turtle is `Policies.Turtle`. With sieges on it claims the safest neighbour of its capital once (its strongest army walks in, if the odds call it a likely win), saves for and builds a palisade and then a keep there, recruits there too, keeps armies standing in its forts, and never besieges or storms a fort. As in M1 it still attacks an adjacent army in the field that the odds call a likely win.
- **S8:** the 9 games of `tests/fixtures/main_records.json` and `m4_path_records.json` replay turn by turn against their recorded digests, and the 72 M2 matrix games' record digests equal `m2_matrix_digests.json`.
- **S9:** the invariants of §11.2 as `Simulator.check_invariants` states them; replays of every 10th siege game; and the breach forecast: each `siege_started` or `walls_damaged` event says on which turn the walls reach 0, and while the same armies stand outside and the siege damage is the same, the next event must say the same turn and the walls must reach 0 on it.
- **S10:** a siege "ended by a sally or relief" is one lifted by a battle of kind sally, gate, relief or relief with a sally. A relief chance is a turn when the owner of a besieged fort with standing walls has an army with a fighter one province away; it is taken when that army is ordered in.

### 11.3 tuning knobs
S-7 may change these without asking, recording before → after in its PR and updating this file's tables (that ticket authorises the edit):
- **Walls:** palisade 2-4, keep 5-7, citadel 8-10; the wall step (`WALL_STEP`) 2-4. The defense per step stays 2 (breakpoints).
- **Siege damage:** troops per +1 from 8 to 12; the most from troops 1-3; engines +1 each, counting at most 2-4; the cap 5-7. The siege camp's 1 stays, so every siege ends.
- **Repair:** the level a turn, or 1 a turn.
- **Recruit limits:** palisade 1-3, keep 3-5, citadel 6-10. The wait after capturing a fort: 0-2 turns.
- **Fortify:** palisade 20-40 gold and 1-3 turns; keep 40-70 gold and 2-4 turns.
- **Engines:** cost ±4.
- **The cut-off:** from the first or the second siege turn; base income to the besiegers, or to nobody.
- **Interactions:** whether the Forges work under siege; whether Forge Tithe counts palisades.
- **AI:** every constant in §8.1, ±0.1 for thresholds and ±1 for counts and turns.

Anything else, or a band that can't be met within these knobs, goes back to the director as a question for Alex.

### 11.4 S-7's first run: bands, tuning and what is still missed
`autoplay.gd -- --matrix --sieges --independents --jobs 4`, seed 1, turn cap 60, AI in both seats. 2,072 games (900 siege games, the same 900 with sieges off, 100 turtle games and 100 more with sieges off, 72 M2 games), about 22 minutes with 4 jobs on a shared Mac. The first run (the numbers as §2-§8 first stated them) is the "before"; the "after" is the tuning below. Both used the same seeds, and the sieges-off games are identical in the two runs.

**Bands, before → after** (target ranges, not hard caps):

| band | target | before | after |
|---|---|---|---|
| S1 length | median decisive 12-22; at most 5% at the cap | median 23; 211 of 1,100 at the cap (19%) **miss** | median 21; 11 of 900 at the cap (1%) **pass** (sieges off: median 20, 1 of 900) |
| S2 sieges happen | 60%+ of games reaching turn 12 | 76% **pass** | 95% **pass** (first siege on turn 9, was 19; 2.3 sieges a game, was 1.2) |
| S3 storm or wait | storms 15-60% of battles at forts | 73% (1,458 of 1,992), stormers won 96% **miss** | 57% (1,335 of 2,325), stormers won 96% **pass** (the 55-85% expected win rate is not met) |
| S4 forts built | median 1-3; 95th percentile 5 or fewer | median 1, 95th 4 **pass** | median 1, 95th 3 **pass** |
| S5 recruiting at forts | 10-50% outside the capital | 59% **miss** | 43% **pass** (46% counting Warband Muster) |
| S6 nothing new dominates | no pairing newly above 65% | 3 of 9 pairings newly above; Crown / Clans 49 / 51 (sieges off 41 / 59) **miss** | 2 of 9 newly above (Regent's Court vs Clan Moot, Clans 76%; Warrior King vs Blood of the Fang, Crown 67%); Crown / Clans 44 / 56 **miss** |
| S7 turtling loses | turtle wins 10% or fewer, at most 10% at the cap | 0 of 100, 0 at the cap **pass** | 0 of 100, 0 at the cap **pass** |
| S8 off is identical | fixtures and M2 games | 9 of 9 and 72 of 72 **pass** | 9 of 9 and 72 of 72 **pass** |
| S9 integrity | 0 problems, 0 forecast mismatches | 0 in 2,472 games, 744 forecast checks **pass** | 0 in 2,072 games, 1,098 forecast checks **pass** |
| S10 defence works (report) | 10%+ of sieges ended by a sally or relief | 1% (7 of 1,298); relief chances taken 29% (23 of 79) | 4% (91 of 2,098); relief chances taken 60% (155 of 260); 876 sally orders, was 67 |

**Every number change, before → after** (all inside §11.3):

| what | before → after | why |
|---|---|---|
| `CAPTURE_WAIT` (`data/forts.gd`) | 1 → **2** | A fort taken on turn 7 takes recruits from turn 10, not 9. The games that stalled had both armies stacked at the two forward keeps (Stonegate and Blackwood, which touch), recruiting there every turn; with the extra turn, the first recruits go to the capital, form armies there that can act, and the stacks stop growing in lockstep. Alone, with the first AI numbers, it left 9% at the cap; with the AI numbers below, 1%. |
| `STORM_WIN` | 0.65 → **0.75** | S3: the AI stormed whenever it was nearly sure, so 73% of the fights at forts were storms. It now waits for the breach when the storm is only likely. |
| `CAPITAL_STORM_WIN` | 0.5 → **0.6** | the same, at the enemy capital. |
| `RACE_STORM_WIN` | 0.45 → **0.55** | the same, when a relief can reach the fort. |
| `SIEGE_START_WIN` | 0.55 → **0.45** | S1: the AI started a siege only when it was likely to win the open fight with the garrison's cover; mirror stacks were never that. |
| `STANDOFF_START_WIN` | 0.5 → **0.4** | the same, in a #94 stand-off. |
| `SIEGE_STAY_WIN` | 0.45 → **0.35** | S1: stay in a siege a little longer. |
| `REACH` | 2 → **1** | S1: counts the enemy armies within one move of a fort, not two, when deciding to start, stay, abandon or garrison. With `REACH` 2 and everything else the same, 7-10% of games reached the cap (e, i below). See the call below. |
| `SIEGE_SALLY_WIN` | 0.65 → **0.55** | S10: a garrison sallies at lower odds (sally orders 67 → 876). |
| `RELIEF_WIN` | 0.65 → **0.55** | S10: relief is sent at lower odds. |
| `CAPITAL_RELIEF_WIN` | 0.5 → **0.4** | S10: the same for the capital. |

Texts that named the wait ("the turn after next") now read it from `FortData.CAPTURE_WAIT_WORDS`; the codex, the forecasts and the refusal reasons already took the turn number from the data.

**What was tried and left alone** (siege games only, same seeds, so each row is comparable with the 19% / 73% / 59% / 1% of the first run; "ends" is S10):

| run | change | games | at the cap | storms | outside the capital | sally / relief ends |
|---|---|---|---|---|---|---|
| a | start, stand-off and stay −0.1, storm thresholds −0.1 | 360 | 9% | 75% | 50% | 2% |
| b | a, `REACH` 1, sally and relief −0.1 | 540 | 4% | 68% | 49% | 5% |
| c | b, storm thresholds as the first numbers | 540 | 4% | 62% | 49% | 5% |
| d | c, storm thresholds +0.1 (the AI numbers above) | 540 | 4% | 59% | 50% | 5% |
| e | d with `REACH` 2 | 540 | 10% | 63% | 52% | 6% |
| f | the AI numbers above alone, full size | 900 | 4% | 57% | 51% | 4% |
| g | f and `CAPTURE_WAIT` 2 (**what shipped**) | 900 | 1% | 57% | 43% | 4% |
| h | `CAPTURE_WAIT` 2 with the first AI numbers | 900 | 9% | 73% | 47% | 1% |
| i | `CAPTURE_WAIT` 2 and the AI numbers with `REACH` 2 | 900 | 7% | 64% | 45% | 4% |
| j | f and recruit limits keep 3, palisade 1 | 900 | 4% | 58% | 42% | 4% |
| k | faster siege damage (8 troops per +1, up to +3, cap 7) | 440 | 21% | 70% | 60% | 0% |
| l | walls palisade 2, keep 5, citadel 8 | 440 | 21% | 71% | 60% | 1% |
| m | a, walls 4 / 7 / 10 | 540 | 10% | 73% | 50% | 4% |
| n | a, engines for sieges 3, `MUSTER_WEIGHT` 0.35 | 540 | 10% | 76% | 51% | 2% |
| o | a, Fortify 40 and 60 gold, `FORTIFY_TURN` 7, recruit limits 1 and 3 | 600 | 14% | 73% | 47% | 3% |
| p | d, slower siege damage (12 troops per +1, up to +1, cap 5) | 540 | 4% | 62% | 50% | 8% |
| q | d, walls 4 / 7 / 10 | 540 | 5% | 53% | 50% | 6% |
| r | d, slower damage and walls 4 / 7 / 10 | 540 | 5% | 58% | 50% | 9% |
| s | recruit limits 1 / 3 / 10 (Beast-God Unbound games only) | 300 | 49% of those | 71% | 67% | – |

- **The data knobs on walls and siege damage did not move the stalls** (k, l, m): the games at the cap had no siege at all (180 of 211 in the first run), so nothing about breaching mattered. They moved the storm share a little (q: 53%) and the sally and relief share (p, r: 8-9%), at some cost to the cap share and to the recruit share (q misses S5 by a hair). I kept the first walls and damage, because palisade walls above 3 give the board a damaged-palisade look it has no model for (`SiegeRules.damage_look`), and the gain is in a report band.
- **Recruit limits did not bind** (j, o, s): the computer buys 2-4 units a turn, under every limit in range, so the forward keep took everything either way; lowering them did not stop the stack.
- **The stand-off is the same as #93's.** Both computers stack at the two forward keeps (115 and 141 troops by turn 60 in the traced game), each judging the other's keep not worth besieging (24-34% in the open with the garrison's cover) and its own not safe to leave. 91% of the capped games (193 of 211) had Beast-God Unbound in them (its ruler keeps all 10 power). The capture wait and `REACH` were the two knobs that broke it; what would break it for good is an AI rule (for example: recruit at the capital once the forward keep holds a stack, and use that army to take the Free Holds garrisons or go round), which is not a §11.3 knob and belongs to the AI's owner.

**Bands still missed**
- **S6, two pairings and a faction split.** Regent's Court vs Clan Moot: the Clans win 76% (95% range 66-83%) against 64% with sieges off, 1.8 standard errors apart, so mostly the preset (it was already 64%). Warrior King vs Blood of the Fang: the Crown wins 67% (57-75%) against 46%, 3.0 standard errors apart, which is real. The diagnostic is the same in both: the side that wins more starts two to four times as many sieges (Warrior King 143 against Blood of the Fang's 70 in that pairing; Clan Moot 135 against Regent's Court's 40). Warrior King vs Clan Moot is over 65% for the Clans with sieges off (68%), and went to 77% in the first run and 80% now. Crown / Clans is 44 / 56 (sieges off 41 / 59; the first run 49 / 51). **Not tuned: a miss goes to Alex, as with M2's band C.** The knob that would move it is the engines' cost (±4), which moves every pairing at once.
- **S10, 4% against 10%.** The computer sallies and sends relief far more (sally orders 67 → 876; relief chances taken 29% → 60%) but a sally or relief still ends only 4% of sieges: most sieges end by storm, by the breach battle, or because the besiegers leave first. The slower-damage runs (p, r) reach 8-9%, but cost S3 or the cap margin and rewrite §3.3's table, so they are left for Alex's call. It is a report band.
- **S3's storm win rate** is 96% against an expected 55-85%: the computer storms only when it is nearly sure. Lowering `STORM_WIN` would bring the win rate into the band and push the storm share back above 60%, so I kept the share, the band that is a pass or a miss.

**Calls S-7 made**
1. **`REACH` is now 1.** It was 2 in §8.2 precisely so that a relief army stepping back two provinces could not be danced in and out of the AI's sights (appendix A, round 2). Against two computers it was the strongest lever for S1, so I took it, but a player can now do that dance again. Alex's call: keep it, or go back to 2 and accept 7-10% of games at the cap (e, i).
2. **Palisade walls above 3 are not a free knob** (the board has no damaged-palisade model), and I did not use them.
3. **The turtle claims a province.** The turtle of M1 owned only its capital, so it could never build a fort; it now walks its strongest army into the safest neighbour of its capital once and builds there. It still attacks an adjacent army in the field at likely odds, as in M1, and never a fort.
4. **The independents config only.** The plain (no Free Holds) matrix was not run; the contract is `--independents`.
5. **The AI was touched only in constants** (`ai/ai_sieges.gd`, ten values, with the first ones in a comment there).

---

## 12. engine changes at a glance (for builders)
- **Data** (`data/forts.gd`, `FortData`, const dictionaries like `data/factions.gd`):
  - `LEVELS`: per level `{id, name, walls, recruits, commanders, engines, repair, cost, turns}` (§2.1)
  - `WALL_STEP = 3`, `SIEGE = {"camp": 1, "per_troops": 10, "troops_max": 2, "engine": 1, "engines_max": 3, "max": 6}`
  - `START = {"capital": 3, "fort": 2}`, `CAPTURE_WAIT = 2` (turns before a captured fort takes recruits; it was 1 until S-7), `CAPTURE_WAIT_WORDS` (the same wait in words for the texts that name no numbers)
  - `ENGINES`: the two engines (§5) by faction: id, name, cost, text. They are not added to any roster.
- **State** (serialized, validated and deep-copied only in a game with sieges):
  - `GameState.sieges: bool`, saved only when true.
  - `Province` gains `fort_level`, `walls`, `fort_by` (the faction that built the current level; "" for map forts), `works` (`{}` or `{"faction", "to", "left", "turn"}`), `siege_since`, `owned_since` and `lost` (`{}` or `{"faction", "owned_since", "turn"}`: who lost it last, for the retake rule). `to_dict(sieges)` writes them only with sieges on. `has_fort` stays and equals `fort_level > 0`.
  - **`owned_since`, pinned:** the turn (as players count turns) its owner took it, 0 for owners from the start and for neutral provinces. Capture and Sworn Vassals set it to the turn being resolved. A recruit at a fort is legal on turn t when `owned_since + CAPTURE_WAIT < t`. When the faction in `lost` takes it back by `lost.turn + 2`, `owned_since` is restored from `lost`.
  - `Army` gains `engines` (0-3), written only when above 0, which can only happen with sieges on.
  - `validate` checks, in plain language:
    - levels are 0-3, and 3 only at a capital;
    - walls are in 0..max;
    - `has_fort` agrees with the level;
    - at most one site per faction, on a province it owns, with `to` = level + 1 ≤ 2 and `left` ≥ 1;
    - `siege_since` is set exactly when the owner's armies and another faction's are both in the province, and never after the current turn;
    - `0 ≤ owned_since ≤ current_turn`, and 0 for a neutral province;
    - an army's `engines` is 0-3, and only an army with a fighter (a unit or commander, not a ruler's army) carries any.
  - Rosters don't change: engines live in `FortData`, and `recruitable_type` offers them only with sieges on.
- **Pure rules** (`rules/siege_rules.gd`, class `SiegeRules`) are the single source for the resolver, forecasts, breakdowns, the AI and every screen:
  - `level_data`, `walls_max`, `walls_defense`, `damage_look`, `recruit_limit`, `may_recruit`, `repair_amount`
  - `garrison`, `outside`, `besiegers`, `is_besieged`, `is_cut_off`, `turn_of_siege`, `troops`
  - `siege_damage` (with parts), `turns_to_breach`, `breach_turn`
  - `check_fortify`, `check_siege_order`, `check_recruit_at`
  - `next_battle` (§3.9), `siege_step`, `works_step`, `repair_step`, `engines_counted`
  - texts: `siege_text`, `walls_text`, `fortify_text`
- **Orders:**
  - New `FortifyOrder(province)` and `SiegeOrder(action, target)`, serialized as in §2.4, §3.4 and §3.5. `RecruitOrder.at` may be a province id, only with sieges; the key stays absent for capital recruits, so M1 records are unchanged.
  - `OrderBook` checks them against all the queued orders, wherever they come in the list: a storm from the march needs a valid queued move into the fort; a sally needs no move for its army; one Fortify per faction; recruit counts per fort; an engine needs an army with a fighter at its fort.
  - Removing any move (`remove()` as well as `cancel()`) re-checks only the faction's storms and sallies; a storm that loses its move, or a tied sally whose relief move is gone, is dropped with its reason. With no siege orders queued, `remove()` behaves exactly as today (no drops, no `last_dropped`).
  - `SiegeOrder` serializes as `{"type": "siege", "action": "storm", "province": id}` or `{"type": "siege", "action": "sally", "army": id}`, plus `"with": <relief army id>` only for a tied sally.
  - Old records without them load unchanged.
- **Resolver** (`TurnResolver`):
  - `phases(state)` (§6)
  - orders: siege orders checked against all valid moves, and recorded; Fortify orders checked
  - `_province_battles`: at forts, a loop over `SiegeRules.next_battle`, passing the battle's `siege` block to the battle resolver and to the event as `numbers.siege`
  - the sieges phase: siege start, damage, breach, lift, fall, repair, construction work and completion
  - capture: construction razed; empty forts keep level and walls; `owned_since`
  - recruitment: `price_recruits` over the mixed list (recruits, engines and Fortify orders), recruits at forts with limits; `_add_recruit` adds an engine to `Army.engines` of the first army there with a fighter
  - income, with sums that hold for `Breakdown` on both sides:
    - owner: `RulerRules.province_income_parts` gains a part `cut_off` equal to minus the province's total after its floor, so the province pays exactly 0;
    - besieger: `income_of` adds the province's base income under the key `besieged:<province id>` in both `modifiers` and `by_province`, so base + modifiers = total holds;
    - `income_modifiers_text` prints both keys, and the income event lists cut-off provinces apart from the provinces that paid;
  - Forge Tithe's keep-or-citadel count and the capital's id read as "" apply only with sieges on.
- **Battle** (`AutoBattleResolver`):
  - **S-1b's small edits:** `_defense` adds the `walls` part to garrison fighters in a storm and the `cover` part to `from_inside` fighters in a sally or breach battle, and adds no `"fort"` part when the battle carries `siege`. Engines need no battle change: they are not units.
  - **S-2:** the `siege` block in the log and report, the `walls` and `cover` factors, the aftermath's lost engines, the Siege Engine codex text, captions and explanations.
- **BattleLog:** `siege` in `validate`, `cross_check` and the docs; the schema version stays 1.
- **Forecast:**
  - S-1a: `siege` (without odds), `fortify`, `recruit_at`.
  - S-2: `storm_odds`, `sally_odds`, `relief_odds`, `breach_odds`, the odds lines in `siege`, `battle_odds` routed through `next_battle`, and `move` and `defender_ground` learning sieges.
- **Session:** `report_phases(state)`. `record()` needs nothing new, because sieges live in `start_state` and siege orders in history.
- **Autoplay:**
  - S-1a: `Simulator`'s invariants (two factions may share a province only in a siege) and its phase list follow `phases(state)`.
  - S-7: `--sieges` in `play_game`, `autoplay.gd` and `--matrix`; `tools/autoplay/siege_matrix.gd` with §11.2's bands; the `turtle` policy's Fortify.

---

## 13. art

### 13.1 what M3c asks for
Real per-model costs come from `studio/ledgers/asc-3d-factions.jsonl` (#91's 74 models, 365 credits):
- a picture costs 0.5 per candidate: a new structure picture rolls 3 candidates (1.5), and a pose or damage edit rolls 2 (1.0);
- a `create3DModel` costs 3.0;
- so a model is about 3.5 credits plus its candidate pictures.

The fort and fortress concept pictures are already in `assets/_concept/<faction>/` (#91), so the damage looks are edits of local files, sent as base64, with no expired Ludo URLs.

| item | per faction | how (bible §8.11) | credits each | both factions |
|---|---|---|---|---|
| **palisade** (the level 1 kit). Crown: an earth rampart and timber stockade with a small blue-roofed gate tower. Clans: a ring of sharpened stakes and bone with a lookout | 1 | createImage C-structure, n 3 (1.5) + model (3.0) | 4.5 | 9.0 |
| **damage looks**: palisade breached; keep damaged and breached; citadel damaged and breached | 5 | editImage of the intact concept, n 2 (1.0) + model (3.0): "the same fort, its walls now cracked and scorched with fallen stones" / "...with a wide breach of rubble in the front wall" | 4.0 | 40.0 |
| **construction scaffold**. Crown: stone courses in timber scaffolding. Clans: a half-raised stake frame with ropes | 1 | createImage n 3 + model | 4.5 | 9.0 |
| **siege works**. Crown: mantlets and ladders. Clans: earth mounds, stake lines and a log rack | 1 | createImage n 3 + model | 4.5 | 9.0 |
| **siege engine** in 3 poses: ready, strike, wrecked. Engines never fight, so a march pose is the ready model sliding with a code wheel roll | 1 family | generateWithStyle from a faction pick, n 3 (1.5) + 2 pose edits, n 2 (2.0) + 3 models (9.0) | 12.5 | 25.0 |
| **engine portrait** (2D, roster and codex) | 1 | generateWithStyle, n 3 | 1.5 | 3.0 |
| **rubble pile** (a shared prop for breaches and badly damaged walls) | – | createImage n 3 + model | 4.5 | 4.5 |

Concept prompts follow the bible's C-structure and C-model blocks, and engines anchor only to same-faction picks (bible §3, rule 3). Every model goes through §9.2 of the 3D direction: slimming, our `piece` material, scale normalisation, the 24 px silhouette gate for the engines, a model sheet, and Alex's verdict.

### 13.2 credits

| what | planned | with re-roll reserve (×1.5) |
|---|---|---|
| palisades | 9.0 | 13.5 |
| damage looks | 40.0 | 60.0 |
| scaffolds | 9.0 | 13.5 |
| siege works | 9.0 | 13.5 |
| engines (3D) | 25.0 | 37.5 |
| engine portraits | 3.0 | 4.5 |
| rubble pile | 4.5 | 6.75 |
| **total** | **99.5** | **149.25** |

- **Budget: 155 Ludo credits.** Flag the director above 150. This is more than 3D_DIRECTION §9.5's "about 20 for fort-level kit variants", because it also prices the damage looks and the engines.
- **Cheaper option: 41.5 planned (62 with reserve).** It keeps the palisades, engines, portraits and rubble pile only. The damage looks become code notches, rubble and smoke on the intact models; the scaffolds become code lattices; the siege works become the existing camps with code ladders. See §17, question 4 (default: the full batch).
- **Each later faction** (M6) adds about 46 planned: a palisade 4.5, five damage looks 20, a scaffold and works 9, an engine family 12.5.
- **Throughput** (3D_DIRECTION §9.6): 26 models at about 12 an hour is about 2.5 hours unattended, pictures first.

### 13.3 what ships with placeholders (the milestone never waits for art)
- **Palisade:** `kit.gd`'s primitive fort (a square tower inside a ring of palisade, already drawn for `has_fort`), in the owner's kit colours.
- **Damage looks:** the intact model with a code notch (`cut_plane`), rubble primitives and smoke billboards (`shaders/smoke.gdshader`); the breach gets a wide notch on the gate side.
- **Scaffold:** a code lattice of thin boxes, with the next level's model rising by a cut plane.
- **Siege camp:** the existing `camp.<faction>` models in a ring, with code ladders (Crown) or a code log (Clans) as the works, and chevron banners (always code).
- **Engines:** a code ram (a box on a cylinder axle) or a code trunk on a sled, in the faction palette, with Kit's generic figures as crew. The 2D portrait is M3's class-glyph card.
- **2D:** the walls bar on the province plate, the siege glyph and every chip are code-drawn from the start.

---

## 14. out of scope for M3c
- **Hunger and supplies:** a besieged garrison doesn't starve. The walls are already the clock; hunger is a later knob if sieges run long.
- **Militia and independents:** an empty fort has no defenders of its own (3D_DIRECTION §10.6's independents would change this).
- **Citadels outside capitals, levels above citadel, and other buildings** (barracks, towers, roads). Fog of war's "a fort's towers see 2 provinces" waits for M5.
- **Razing your own fort or slighting a captured one.**
- **Partial storms:** a storm is ordered per fort. Sallies are ordered per army.
- **Splitting or merging armies, and handing engines from one army to another.**
- **Mining, sapping and siege magic** (M5 may add spells against walls), naval sieges, and wall-climbing traits beyond engines.
- **Retreats:** a beaten sally is destroyed, like any losing side.
- **Transformed engines and kits** (a Living Iron ram, a Thorn Wild palisade): later, with M4 in 3D.
- **Upkeep** for forts or armies.
- **Changes to victory:** capturing a capital still ends the game.
- **Battles with more than two sides on the 3D stage** (M6).
- **AI difficulty levels** beyond "easy" and "normal".

---

## 15. tickets
Github issues are to be cut once Alex has seen this. S-n are placeholders, and every ticket is labelled `milestone:3c`. Every code ticket follows `CLAUDE.md`:
- pure rules code
- tests under `tests/`, with expected numbers derived from data (`FortData`, the resolver's constants), not hardcoded
- `tools/compile_check.gd` passes
- in-game explanation in the same PR
- a `playtest:` line in the PR

**Parallel lanes and file ownership:**
- **S-1a, then S-1b, by the same builder, come first.** Together they own `data/forts.gd`, `rules/siege_rules.gd` (all of it, `next_battle` included), `rules/fortify_order.gd`, `rules/siege_order.gd`, `rules/province.gd`, `rules/army.gd`, `rules/game_state.gd`, `rules/recruit_order.gd`, `rules/order_book.gd`, `rules/turn_resolver.gd` (all of it), `rules/ruler_rules.gd` (the `cut_off` income part and Forge Tithe's count) and `rules/game_session.gd`. They also own the siege, Fortify and recruit functions in `rules/forecast.gd`, `rules/breakdown.gd`, the new game screen's tick box in `ui/new_game_screen.gd`, and `tools/autoplay/simulator.gd`'s invariants and phase list. In `rules/auto_battle_resolver.gd`, S-1b makes only the small edit in §12. S-8 can start now, with no code dependencies.
- **After S-1a merges,** S-3 and S-4 can start; after S-1b, S-2. Each owns its files:
  - **S-2:** the rest of `rules/auto_battle_resolver.gd`, `rules/battle_log.gd`, `rules/battle_captions.gd`, `rules/battle_explain.gd`, and in `rules/forecast.gd` the odds functions, `battle_odds`, `move` and `defender_ground`.
  - **S-3:** `ui/` only.
  - **S-4:** the `world3d/` board files (`armies.gd`, `world_view.gd`, `playback.gd`, `muster.gd`, `board_overlay.gd`, `kit.gd`) and `world3d/models.json`'s new kinds, with empty `model` fields and their primitive `fallback`; the tests `test_board3d*` and `test_armies3d*`.
- **`RulesCodex`:** S-1a adds its entries right after the `fort` entry and makes the S-1a updates in §9.6; S-2 adds its entries after the trait entries.
- **S-5** needs M3b (`m3b-3d-battles`) merged and S-2. It owns `world3d/battle_stage.gd` and `world3d/battle_formation.gd`.
- **S-6** needs S-2 and #94 merged. It owns `ai/` and `tools/autoplay/policies.gd`.
- **S-7** needs S-2 and S-6. It owns the rest of `tools/autoplay/`, and may edit the tables in §2.1, §3.3, §5 and §11 of this file.
- **S-9** follows S-8 and S-4. It fills the `model` fields of S-4's rows in `world3d/models.json`, and nothing else in that file. M3b and S-4 touch the file before it.
- S-3 is best after S-2, for the storm and sally odds; until then its controls show the siege forecast without odds.

**S-1a `code` `hard` Forts and sieges rules model: state, orders, the sieges phase, income** (needs `main`; M3b not required)
- *Before it merges:* record a fixture of M4 path games at bea3b51 with `tools/replay_fixture.gd`, for `test_sieges_off`.
- *Scope:*
  - `data/forts.gd`; the `Province`, `Army` and `GameState` fields; `setup_sieges`, `with_sieges` and the new game screen's tick box (§1.3)
  - `SiegeRules` except `next_battle`: levels, walls, siege damage (engines counted per 5 troops), garrison and besiegers, pickets and the cut-off, recruit checks, Fortify checks
  - `FortifyOrder`, `SiegeOrder` and `RecruitOrder.at` = a province, with `OrderBook` checks, re-checks and serialization
  - the resolver: `phases(state)`; arriving at a garrisoned fort starts a siege with no battle (a stub `next_battle` that returns M1's battle everywhere else); the sieges phase (start, damage, breach, lift, fall, repair, construction); razing, `owned_since` and the retake rule in capture and Sworn Vassals; recruiting at forts, engines joining armies, and Fortify payment through the mixed `price_recruits`; the cut-off in income on both sides, through `ruler_rules.gd`
  - the events of §9.4 outside battles; `Forecast.siege` (without odds), `fortify` and `recruit_at`; the `Breakdown` lines of §9.3
  - the codex entries and updates assigned to S-1a (§9.6); `Simulator`'s invariants and phase list
- *Acceptance (tests named):*
  - `tests/test_forts.gd`:
    - every level's numbers come from `FortData`;
    - Fortify legality as a table (owned, enemy present, capital, keep, one site, gold, lost in capture), with plain reasons;
    - construction progresses only with no enemy present, stops without loss, and is razed on capture;
    - repair by level; a finished level stands at full walls;
    - recruit limits, level rules (commanders and engines need a keep), the wait after capture and the retake rule, no recruits at a cut-off fort, and recruits allowed beside pickets;
    - an engine joins the first army with a fighter, is refused at no cost with no army there, and is lost with its army.
  - `tests/test_sieges_model.gd`:
    - arriving at a garrisoned fort starts a siege with no battle;
    - damage equals `siege_damage` for constructed armies (a raid, 10, 20, engines per 5 troops, the cap);
    - the cut-off starts on the siege's second turn, only while the besiegers have at least half the garrison's troops, and the base income goes to the besiegers; owner and besieger income breakdowns each sum to their totals;
    - a breach at 0; a lift when the besiegers leave; a fall that clears `siege_since` so the next turn loads;
    - an empty fort is captured with its level and walls;
    - **forecast equals result** for the breach turn and the cut-off, over every level and every row of §3.3.
  - `tests/test_siege_orders.gd`:
    - to_dict / from_dict / JSON round trips for every new field and order;
    - a recorded siege game replays to an identical state;
    - OrderBook drops a storm from the march when its move is removed, and a sally when a move for its army is queued after it, by `remove()` or `cancel()`, with the reason; with no siege orders, `remove()` drops nothing.
  - `tests/test_sieges_off.gd`:
    - with sieges off, every existing test passes unmodified;
    - `main_records.json` and the new M4 path fixture replay byte-identically turn by turn;
    - no siege key, phase, event or engine in M1, M2 or M4 games; `PHASES` and `PATH_PHASES` are unchanged; `at` naming the capital's id is still rejected.
- *playtest:* start a game with sieges, build a palisade on turn 6, and check the turn it stands and the turn it first takes recruits against the forecast. Then march into Stonegate's keep while the enemy holds it, and watch its walls reach 0 on the forecast turn.

**S-1b `code` `hard` Every crossing of orders: `next_battle` and the battle loop** (needs 1a; same builder)
- *Scope:* `SiegeRules.next_battle` (§3.9) in place of the stub; `_province_battles` looping over it at forts; tied sallies; called-off storms and sallies; the small battle edit (the `walls` and `cover` parts, no `"fort"` part with sieges on).
- *Acceptance (tests named):* `tests/test_siege_battles.gd`:
  - a table-driven test builds every row of §3.9 and checks the battles, their order, kinds, `why`, sides, defenders and `from_inside`;
  - the walls part equals 2 × ceil(walls ÷ 3) at every wall strength of every level and appears only in storms; the cover part is +2 on `from_inside` fighters in sallies and breach battles and nowhere else;
  - open and breach battles have no defender and no terrain; an army can fight the open battle and then the storm;
  - no battle side is ever without a fighter, and engines never appear in a battle;
  - the same seed gives the same result.
- *playtest:* order a relief with a tied sally, then cancel the relief move and check the sally is gone; send another relief that dies in a border battle and check the garrison stayed inside.

**S-2 `code` `hard` Battles at walls: report, log and odds** (needs 1b)
- *Scope:*
  - the `siege` block in the battle log and report (§4.4)
  - the `walls` factor and the battle's first line and aftermath (§4.5)
  - Siege Engine's `TRAIT_TEXT` and `TRAIT_SHORT`
  - `BattleLog.validate` and `cross_check` for `siege`; captions and hover explanations for the walls
  - `Forecast.storm_odds`, `sally_odds`, `relief_odds`, `breach_odds`, with chained battles fought on each seed; `battle_odds`, `move` and `defender_ground` routed through `next_battle`
  - the battle codex entries and S-2's updates (§9.6)
- *Acceptance (tests named):*
  - `tests/test_siege_log.gd`:
    - `validate`, `verify_draws` and `cross_check` pass on a storm, a sally, a relief, a gate battle and a breach battle;
    - `siege` matches §3.9's last column for each;
    - logs from games without sieges are byte-identical to `main`'s fixtures;
    - recording on and off gives the same outcome.
  - `tests/test_siege_odds.gd`:
    - a constructed storm names `walls` as its top "why";
    - for single-battle plans, `Forecast.storm_odds` equals `AutoBattleResolver.estimate` on the same plan;
    - a chained plan's odds come from fighting the chain;
    - the move forecast into an enemy fort says "besiege" and doesn't promise "+2 fort".
- *playtest:* storm Stonegate's full keep with about a third more gold than its garrison, then fight the same armies after the breach, and compare the odds, the losses and the "why".

**S-3 `code` Fort and siege UI** (needs 1a; best after 2)
- *Scope:*
  - the fort chip and walls bar on the province plate; the fort section of the province panel (level, walls, recruits a turn, construction, inside and outside the walls, siege damage, the breach turn)
  - Fortify and Upgrade with the preview; **Besiege / Storm now** in the move preview; the Storm toggle; Sally ticks per army (ruler off by default) with their risk line; "The garrison comes out to join you" in a relief move's preview; the recruit panel's "Recruit at" picker
  - every §9.4 report line, the "needs you" lines, the first-siege sentences (§9.5), and the battle viewer's chips (§9.7)
  - the victory screen's forts built, sieges won and storms
- *Acceptance (tests named):*
  - `tests/test_fort_panel.gd` (headless, M1 style):
    - every number on the panel has a hover breakdown equal to `SiegeRules` / `Breakdown`;
    - Fortify, Storm and Sally queue the right orders and show the rejection reasons;
    - the relief preview queues sallies for every garrison army but the ruler's;
    - the recruit picker greys a besieged fort, a full one and a just-captured one, each with its reason;
    - a rival's siege and Fortify orders never show, also in hotseat.
  - `tests/test_codex_terms.gd` passes with every new term linked.
- *playtest:* defend a besieged keep from the panel alone. Read when the walls reach 0, what a sally would do, and whether your relief army can get there in time.

**S-4 `code` Sieges on the 3D board** (needs 1a)
- *Scope:* §10.1 and §10.2: level kits, damage looks and their code fallbacks, construction scaffolding, the camp ring and siege works, chevrons, packed garrisons, recruits arriving in every fort's yard, and every beat in §10.2. Placeholders come first (§13.3), and the model-table kinds are ready for S-9's models.
- *Acceptance (tests named):* `tests/test_board3d_sieges.gd`:
  - the board model built from a state matches its levels, damage looks, construction and camp rings;
  - **playback equals state** over 5 seeds × 15 turns with sieges on;
  - the game state is deep-equal before and after a played turn;
  - the existing static check (no RNG or resolver calls in `world3d/`) passes;
  - a covered hotseat screen draws no private scaffold ghost.
- *playtest:* play a siege to the breach on the board. Can you tell from the land alone which fort is besieged, by whom, how damaged its walls are, and when the garrison came out?

**S-5 `code` Battles at walls on the M3b stage** (needs M3b merged and 2)
- *Scope:* §10.3: the storm, breach and open placements from the log's `siege` block, `from_inside` marching out of the gate, and engines as camp scenery.
- *Acceptance (tests named):* `tests/test_battle_stage_walls.gd` checks placements for storm, breach and open fixtures, that nobody stands inside a wall, and that M3's outcome-unchanged tests pass for siege battles.
- *playtest:* watch a storm and a sally. Does the walls' +6 read on screen before the first hit lands?

**S-6 `code` AI for forts and sieges** (needs 2 and #94)
- *Scope:* everything in §8: recruiting across forts, engines, besieging, storming, the stay rule and the 2-turn relief horizon, holding, per-army sallies, relief with a sally, abandoning a hopeless fort, garrisons, Fortify and Upgrade, #94's siege action, and the plain notes.
- *Acceptance (tests named):*
  - `tests/test_ai_sieges.gd`:
    - a headless human-vs-AI session with sieges runs 30 turns with zero AI order rejections;
    - constructed positions check each rule of §8.2-8.4: a storm at the threshold and not below; relief and sally sent together, ruler kept in; a hopeless keep abandoned; the palisade site chosen as §8.4 says; engines recruited into an army at the forward keep and marched to the siege, never beyond 1 per 5 troops; a relief army stepping 1 or 2 provinces back doesn't draw the AI into a losing siege; a garrison left in a reachable keep;
    - a stand-off state (both capitals stacked) becomes a siege within 6 AI turns and a battle at a fort within 12;
    - the same seed gives the same orders; the AI never reads a rival's queued orders.
  - With sieges off, `tests/test_ai_player.gd` and the M2/M4 AI fixtures are unchanged.
- *playtest:* play two games against the AI with sieges on, one turtling and one attacking. Does it besiege, storm when it should, and come to the rescue of its own forts?

**S-7 `code` Autoplay balance check for sieges** (needs 2 and 6)
- *Scope:*
  - `--sieges` in `Simulator`, `autoplay.gd` and `--matrix`; `tools/autoplay/siege_matrix.gd`
  - report sections: siege counts, storms against breaches, forts built, recruits by fort, siege lengths, and the cap share against the sieges-off baseline
  - the §11.2 bands as a pass/miss table, with exit code 0 only when S8 and S9 hold
  - the turtle policy's Fortify; tuning within §11.3
- *Acceptance:* the report is attached to the PR, with every number change before → after and this file's tables updated. Any band still missed is listed with why and the diagnostic behind it, as #93 did.
- *playtest:* read the bands table. Do sieges replace the stalled games, and does each side both storm and wait?

**S-8 `design` Art lead: M3c manifest rows** (no code dependencies)
- *Scope:* `design/ASSET_MANIFEST.md` rows for every item in §13.1 (literal prompts, anchors, gates, candidates, status `spec`); the damage-edit prompt block and the palisade and engine notes in `design/STYLE_BIBLE.md` §8.
- *Acceptance:* every row has id, class, faces, texture, path, prompt, candidates, gates and status; the per-row credits add up to §13.2; bible changes bump `v`.
- *playtest:* none; the art lead checks the rows against §13.1.

**S-9 `asset` Asset builder: the M3c batch** (needs 8 and 4)
- *Scope:* `tools/ludo/asc_3d_sieges.py`, on the pattern of `asc_3d_factions.py` (manifest, cost, run, pick, install, board rows); the ledger `studio/ledgers/asc-3d-sieges.jsonl`; contact sheets for the kits in each damage look and for the engine families; the `model` fields of S-4's rows in `world3d/models.json`.
- *Acceptance:* the gates pass (faces, texture, origin, facing, no islands, L\*, pose ΔE ≤ 8, the 24 px class read for engines); every model shows on the board in its state; the ledger stays within budget (flag above 150).
- *Budget:* 155 Ludo credits.
- *playtest:* at the default zoom, can you tell a palisade, a keep and a citadel apart, and see each damage look, without hovering?

---

## 16. director's calls (review these first)
1. **Forts are where you recruit.** You recruit at any fort you own: a palisade takes 2 a turn, a keep 4, a citadel 8. Capitals start as citadels, and Stonegate and Blackwood as keeps. A fort you capture takes recruits from the third turn after the capture (S-7 raised the wait from the second, §11.4), or at once if you retake your own within 2 turns. In games with sieges, this replaces M1's "recruit only at the capital".
2. **Three levels, two of them buildable.** A palisade costs 30 gold and 2 turns; a keep 50 more and 3 turns. Citadels exist only at capitals. Each faction has one fort under construction at a time. Work stops while an enemy army is there, and a captured site is razed.
3. **Arriving at a garrisoned fort with standing walls starts a siege, not a battle.** No order is needed to besiege or to hold.
4. **Walls 3 / 6 / 9, with +2 defense in a storm for every 3 left.** Siege damage is 1, +1 per 10 troops (at most +2), +1 per engine (at most +3), never more than 6 a turn. Walls repair by the level each turn no enemy is there.
5. **Walls help most against a storm.** Sallies, relief armies and the fight after the breach are open battles: nobody defends, and nobody gets walls or terrain, but the garrison's own fighters keep +2 cover (relief armies don't), so a fort always gives at least the old +2 and relief timing stays neutral. The breach battle comes on its own. A hill fort's garrison trades its hills for the cover at the breach, and every text says so.
6. **The cut-off starts on the siege's second turn, and only a real army cuts off.** From the turn after the enemy arrives, if the besiegers have at least half the garrison's troops, nobody can recruit at the fort and its base income goes to the besiegers. Lift the siege and the income returns that turn, recruiting the next. Smaller besiegers are pickets and cut nothing off.
7. **Storms are ordered per fort, sallies per army.** At a fort, the open battle comes first, then the storm.
8. **Empty forts fall** whole to the first army that walks in.
9. **Siege engines are carried by armies and never fight.** There is one per faction (Siege Ram, Wallbreakers), recruited at a keep into the army there. Each adds +1 siege damage, for every 5 troops besieging, at most 3. They are lost with their army.
10. **Off by default,** behind "Forts & sieges (M3c preview)", independent of Rulers and Paths. Off, everything is byte-identical, with M4 path games added to the fixtures to prove it.
11. **The AI** besieges what it would win in the open, storms at likely odds (even odds at a capital), relieves its forts with a sally, garrisons them, builds one forward fort at a time, and uses sieges to break #94's stand-offs.
12. **No hunger in M3c:** the walls are the clock.
13. **Forge Tithe counts keeps and citadels only** in games with sieges.
14. **Art:** 99.5 credits planned, 149 with reserve, budget 155. The cheaper option is 41.5 (62 with reserve).
15. **All names are proposals:** palisade, keep, citadel, troops, inside and outside the walls, the cut-off, siege camp, sally, relief, breach, Siege Ram, Wallbreakers, Siege Engine, Fortify.

## 17. questions for Alex
The build goes ahead on the **default** for each; Alex can change any of them, and each is one data switch or one ticket's scope.

1. **Recruiting at forts, with limits (call 1).** This is the biggest change to how the game feels: the capital stops being the only place armies appear, and the board shows where a war is gathering. Should capitals have a limit too, or only field forts?
   - **Default: capitals are citadels with a limit of 8 a turn.** It rarely binds (a realm needs about 56 gold of cheap troops in one turn to reach it), and when it does it pushes a rich realm to recruit nearer the front, which is the picture Alex asked for. The alternative is one row in `FortData` (citadel recruits: unlimited).
2. **Empty forts (call 8).** Should an empty fort fall at once to the first army that walks in, or hold out until its walls are breached even with nobody inside?
   - **Default: it falls at once,** whole. It is simple to explain, it is the strongest brake on fort spam, and it makes garrisons a decision. Holding out on its own would protect land without an army and make every palisade a free delay, which is the turtle the bands guard against.
3. **Siege engines carried by armies, or an order (call 9, §5).** Engines recruited at a keep and carried by an army, or a "build siege works" order given at a siege that lasts while it stands?
   - **Default: engines carried by armies, that never fight.** They are the better picture (rams rolling toward the walls) and the better decision (recruit them at a forward keep before you march), and as a count on the army they cost the battle rules nothing. The order version would save the two engine families (25 credits) and one AI rule.
4. **Art budget (call 14).** The full batch, with the damage looks as models, or the cheaper one, with the damage looks in code?
   - **Default: the full batch, 99.5 planned (149 with reserve, budget 155),** because damaged walls and the breach are the siege's main picture on the board. The cheaper option (41.5, 62 with reserve) still ships every rule and every beat; only the damage looks, scaffolds and siege works stay code-drawn.
5. **On by default later?** Once the bands pass and you have played it, should forts and sieges become part of the standard game, beside Rulers?
   - **Default: no, it stays an opt-in preview** until S-7's bands pass and you have played it. The decision is yours after the playtest.
6. **The AI's horizon (`REACH`, §8.2, §11.4).** S-7 set it to 1 so that two computers stop stacking at the forward keeps; a relief army two provinces away no longer deters a siege, so a player can dance one back and in again.
   - **Default: 1,** because with 2 about 7-10% of games still reach the cap. The alternative is the constant `REACH` in `ai/ai_sieges.gd` set back to 2, at that cost.

---

## appendix A: critic rounds
Two rounds on the draft, each from three seats, before the PR. The draft was revised after each round; every finding below is either fixed or answered.

### round 1
**A new player who has never played Dominions**
- *Sending help to your own besieged fort loses the army alone* unless you also ordered a sally on another panel. **Fixed:** the move preview offers "The garrison comes out to join you", ticked for every garrison army but the ruler's, with both odds (§3.6, §9.1). Moving into your own fort while no siege is there warns about meeting arrivals in the open (§9.2).
- *A sally or a storm commits every army, ruler included,* without saying so. **Fixed:** sallies are per army, with the ruler unticked by default, and the toggle states what is risked. The storm toggle names every army that will go (§3.4, §3.5, §9.1).
- *Moving into an enemy fort quietly becomes a siege.* **Fixed:** the move preview itself offers **Besiege** or **Storm now**, with odds (§9.1).
- *Forecasts showed only my side of a two-sided choice,* and breach turns read as certain. **Fixed:** every siege forecast also gives the other side's options and any enemy army that can reach the fort, and breach turns carry their condition (§9.2).
- *Stage names (intact, damaged, crumbling) meant different defenses at different levels.* **Fixed:** the rules text prints the wall number and the storm defense; damage looks are cosmetic, for the board only (§2.1, §10.1).
- *"Under siege" and "cut off" were used for the same thing.* **Fixed:** "besieged" from turn 1; "cut off" only for the income and recruit loss from turn 2 (§3.3, §9.3, §9.4).
- *Terms collided:* recruit or muster, wait or hold, "siege works" meaning three things, "the walls fall" meaning both dropping and breaching. **Fixed:** "Recruit at"; besiegers "wait"; the base damage is the "siege camp"; walls "drop"; "breached" means 0 (§9.2's text rules).
- *"Regular units" changed meaning between sections.* **Fixed:** one word, **troops** (units that fight, not engines), used for siege damage and palisade recruits; the recruit limit counts every recruit (§2.1).
- *The automatic breach battle had no "needs you" line.* **Fixed** for both sides (§9.4).
- *The palisade's "+2 defense" oversold it.* **Fixed:** the Fortify preview and §2.1 say how long it holds and that its walls help only against a storm.
- *A 17-row table is wiki material.* **Fixed:** the `inside_outside` codex entry opens with four plain lines (§3.1); the table is for builders and tests.
- *Turn numbers were ambiguous* ("end of turn 9" against "this turn"). **Fixed:** every text gives both (§9.2).

**A Dominions veteran**
- *Engines in the back rank were untouchable hp padding* that pushed back the rout point and won round caps. **Fixed:** engines never fight; they are lost when their side loses, or when an enemy reaches them with no fighting army of theirs in the province (§5).
- *Relief should always wait for the breach,* because the breach battle gave the garrison the ground and the round-cap hold. **Fixed:** breach battles are open, so the timing of relief is about time, not ground (§3.7).
- *Storm or wait was a lookup,* because +2 walls barely matter and two engines skipped the +4 step at a citadel. **Fixed:** engines give +1 each (at most 3), so a citadel with two engines stands at 4 walls (+4) on its last turn. §4.2 now shows that +2 matters near parity. The rest is the forecast's job.
- *The turtle counter was weak,* since the cut-off cost a capital 12 of about 53 gold and gave the besiegers nothing. **Fixed:** the base income goes to the besiegers, a 24-gold swing at a capital (§3.3). The AI's siege test is one open-battle number, so it besieges at parity in a stand-off (§8.2). The S7 turtle gets a rear keep.
- *A captured fort recruited the next turn,* so an 8-gold raider could take an empty keep and recruit 4 there behind 6 walls. **Fixed:** a captured fort takes recruits from the turn after next (§2.3; S-7 later made it the third turn after, §11.4), and the AI garrisons its keeps (§8.3).
- *Always exactly two engines.* **Fixed** by +1 engines with a cap of 3, and the recruit forecast shows the turns each one saves (§5). Escorts aren't required, because lone engines are lost.
- *The AI could ride into breach battles at 40% odds, and loop besiege-leave-return.* **Fixed:** it re-checks at `SIEGE_START_WIN` on the turn before the breach, and doesn't return to a fort while its relief stands next to it (§8.2).
- *An all-or-nothing sally made a cheap pin* (a small siege next to a big enemy army). **Fixed:** sallies are per army (§3.4).
- *The economy premise was wrong:* sides start with 45 gold and 12 a turn, not 53. **Fixed** in §1.1 and §2.3, which now say that recruit limits are mostly about where, not how many. `FORTIFY_TURN` moved from 4 to 6.
- *Forge Tithe on palisades* would pay Living Iron 4 gold a turn for every 30-gold palisade. **Fixed:** it counts keeps and citadels (§7).

**The engineer**
- *A fallen fort left `siege_since` set,* which would fail `validate` and give the next turn a null state. **Fixed:** the sieges phase has a "fort falls" branch (§3.10), and S-1 tests that the next turn loads.
- *A fixed `battle_plan` list can't know whether a storm follows the open battle.* **Fixed:** `next_battle` is a step function called in a loop on the survivors, and chained odds fight the chain (§3.9, §9.2).
- *S-1 and S-2's file ownership didn't work:* S-1 needed `_province_battles`, and the old "fort" part still applied. **Fixed:** S-1 owns `turn_resolver.gd` and all of `SiegeRules`, and makes two small resolver edits; S-2 owns the report, log and odds (§15).
- *Engines in rank 2 broke Wings and the log's cross-check.* **Fixed:** engines are never fighters (§5).
- *The breach defender contradicted M1's holder rule and §4.2's label.* **Fixed:** breach battles are open (§3.7), and §4.2's first column is now "in the open".
- *Fortify gold was invisible to the shared price check.* **Fixed:** `price_recruits` takes the mixed list and counts per fort; `at` naming the capital's id reads as "" (§2.3, §12).
- *Conditional recruits at besieged forts contradicted the checks.* **Fixed:** nobody can recruit at a fort that is besieged at the start of the turn, so there is no conditional order (§2.3).
- *Storm-from-the-march checks depended on order position,* and `remove()` didn't re-check. **Fixed:** storms are checked against all valid moves, and both `remove()` and `cancel()` re-check (§6, §12).
- *"M4 games stay byte-identical" was untested.* **Fixed:** S-1 records an M4 path fixture at bea3b51 before it merges (§1.3, §15).
- *Battle odds didn't see the walls,* and the move forecast promised "+2 fort". **Fixed:** S-2 owns routing `battle_odds`, `move` and `defender_ground` through `next_battle` (§9.2, §15).
- *`siege_since` arithmetic wasn't pinned.* **Fixed:** §3.3 gives the formula and says a siege continues when the besieging faction changes.
- *The log fields were undefined for some rows.* **Fixed:** §3.9 has a `kind` / `why` column; `from_inside` replaces `inside`; "field" and the undefined "empty" are gone or tied to a row.
- *The simulator's invariants and the static `phase_order` text would break.* **Fixed:** S-1 updates the invariants and phase list; the codex adds a sentence for siege games; every updated entry has an owner (§9.6). `models.json` rows are split between S-4 (kinds) and S-9 (models).

### round 2
The same three seats re-read the revised body (not this appendix). All 12 new-player, 10 veteran and 14 engineer items from round 1 were confirmed fixed, except the veteran's all-or-nothing sally (fixed differently below) and a partly-fixed besiege-leave-return loop. The rewrite brought these new findings, and the body was revised again.

**A new player**
- *The lone-engine rule destroyed engines even with your own troops beside them,* so engines marching to your own siege died on arrival; "next to an enemy" meant the same province. **Fixed** by a simpler model: engines are a count carried by an army (`Army.engines`), never units, so there is no lone-engine rule at all (§5).
- *Four passages disagreed about recruiting during a siege.* **Fixed:** one rule. A fort cut off at the start of the turn refuses recruit orders; lifting the siege returns its income that turn and recruiting the next (§2.3, §3.3, §3.10, codex line 4).
- *Cancelling a relief left its ticked sallies behind,* so the garrison went out alone. **Fixed:** sallies ticked with a relief are tied to it. They happen only if that relief stands outside the walls, and are removed with its move (§3.6, row 18 of §3.9).
- *A breached fort was worse than no fort:* the garrison lost its hills. **Fixed** with the veteran's cover (below): +2 at the breach; on hills about even, and said on the chip (§3.7).
- *Report strings broke the turn-number rules.* **Fixed** (§9.4).
- *A storm takes your ruler without saying how to keep it out.* **Fixed:** the toggle says "To keep an army out, move it away" (§9.1).
- *Codex line 2 left out relief.* **Fixed** (§3.1).
- *The board looked "damaged" while the walls still gave full defense.* **Fixed:** the damage look changes exactly at the storm steps, and the plate's walls bar marks them (§10.1).

**A Dominions veteran**
- *Per-army sallies didn't fix the pin, and the blockade made money.* Armies can't be split, so one 8-gold Fangthrower could cut off a capital held by one big army. **Fixed** by pickets: besiegers with fewer than half the garrison's troops drop the walls but cut nothing off, take no income and block no recruits (§3.3).
- *Walls were only a clock,* and a capital ended weaker than M1's (+2 and the round-cap hold). **Fixed:** fighters from inside get +2 cover in sallies and breach battles, relief armies none. A fort always gives at least the old +2, home keeps an edge near parity, and relief timing stays neutral (§4.1).
- *One troop plus three engines matched a real army's siege damage,* and lone engines were a trap. **Fixed:** at most 1 engine counts for every 5 troops, and engines are carried by armies (§3.3, §5).
- *Retaking your own fort made you wait to recruit there.* **Fixed:** a fort retaken within 2 turns gets its old standing back (§2.3, §12).
- *The AI's no-return rule could be danced* by stepping a relief army two provinces back. **Fixed** without memory between turns (#94 forbids hidden state): the start and stay tests count every enemy army within 2 turns of the fort (§8.2).
- *The keep's last step (+2) makes storming then nearly free.* **Answered:** with the cover, the breach battle also gives +2, so a storm at the last step is the same fight a turn early with the garrison's terrain added: a timing choice, not a free win (§4.2).

**The engineer**
- *Engines couldn't travel with an escort,* since there is no merge order and recruits form new armies. *The lone-engine sweep ran only after movement,* leaving validate holes and fighterless battle sides. *Destroyed engines left stale swap lists.* **All fixed** by engines as a count on armies: no engines-only armies exist, no sweep, no swap changes. Validate checks that engines ride only on armies with a fighter, and `next_battle` never returns a side without one (§5, §12, S-1b).
- *`owned_since` wasn't pinned.* **Fixed:** formula, Sworn Vassals sets it, validate bounds, and the retake record (§12).
- *The cut-off income sums weren't defined for Breakdown,* and `ruler_rules.gd` had no owner. **Fixed:** `cut_off` equals minus the province total; the besieger's line has its own key in `modifiers` and `by_province`; S-1a owns `ruler_rules.gd` (§12, §15).
- *A sally's "no move order" depended on order position.* **Fixed:** sallies are checked after every move, OrderBook drops a sally when its army gets a move, and `remove()` re-checks only siege orders, so M1/M2 behave as today (§6, §12).
- *Battle code still read engine data.* **Fixed:** engines are not units or roster types (§5).
- *Edges of "off = byte-identical"* (the capital-id `at`, Forge Tithe). **Fixed:** both apply only with sieges on, and `test_sieges_off` checks the first (§12, S-1a).
- *S-1 held all the rules work and blocked three lanes.* **Fixed:** S-1a (state, orders, the sieges phase, income), then S-1b (`next_battle` and the battle loop) by the same builder. S-3 and S-4 start after S-1a (§15).

**What round 2 confirmed:** determinism (no siege rule draws a random number; battle ids count battles in the order fought), the per-row log `kind` and `why`, `siege_since` across rows 12 and 15, and that construction and capture can't happen in the same province on the same turn.
