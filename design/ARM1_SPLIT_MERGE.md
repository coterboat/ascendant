# ASCENDANT: ARM-1, splitting, merging and swapping commanders

Status: **r6 by the director (Claude session, 2026-10-10). Both of Alex's questions answered on 10-10; the doc to build from.** r4: Alex chose to build blessings properly now ("b) is genuinely the long-term answer so we might as well build it now"): a blessing stays with its army; units that leave lose it; units that join don't gain it (§2.1). Part of the War Table milestone (`design/UX_WAR_TABLE.md` §3.5); issue #195.
- Alex (10-10, after his playtest): "we need a much better army merging system, including swapping commanders", and "manage … the troop and army movement/distribution/merging side".
- **r1** was the issue's draft. Codex's hostile round on it (25 findings, 10 blockers) rewrote it into r2, and a second round on r2 (9 findings, 2 blockers, both about precision) gave r3. Appendix A lists the changes.

Built on:
- `rules/army.gd` (units, one commander, engines; a ruler travels alone);
- `rules/order_book.gd` (`check_order`, `order_from_dict`);
- `rules/ruler_rules.gd` (`state_after_orders`, the projected board every order is checked against);
- `rules/turn_resolver.gd` (phases, the orders phase, events);
- `rules/magic_rules.gd` (blessings and curses on armies, casts, pins);
- `rules/siege_rules.gd` (engines, sallies, relief);
- `rules/fog_rules.gd` (views, stand-ins);
- `rules/game_state.gd` (`next_army_ids`);
- `ai/`.

## goal
Your armies in a province become clay: split them, merge them, swap their commanders. It all happens in the plan, so you see each army as it will stand before you give it a move. A split is a real tactic (hold the keep with half, march with half), and the game says so.

## the short version
- **One new order type, `MusterOrder`,** with three kinds: **transfer** (units, a commander and engines from one army to another, or to a new army), **merge** (all of one army into another), and **swap** (two armies exchange commanders).
- **Planned, then resolved first.**
  - **All of a faction's musters come before all its other orders, whatever their place in the list.** Among themselves they apply in the order given.
  - The order book applies them to the projected board (`state_after_orders`), and every non-muster order is checked against that board: moves, casts, sieges, recruits.
  - At resolution, musters run **first in the existing orders phase**, in the same order, so the new armies get **the same real ids** the plan showed.
  - **There are no refs and no new phase.**
- **A game without a muster resolves exactly as before:** the same phase lists, codex text, events, records and digests.
- **A blessing stays with its army** (Alex 10-10): units that leave it lose the blessing, and units that join it don't gain it (§2.1). Curses lie on provinces and touch every army there alike, so they don't matter to a muster. **A ruler's army can't muster:** a ruler travels alone.
- **Engines move only when the order says so,** and only to an army that can carry them.
- **The computer doesn't muster** in ARM-1. It plans from the real state each turn, as now.
- **A pure `MusterForecast`** shows every army before and after: units, commander, engines, strength, sight, name, which queued orders it breaks, and where this turn's recruits will join.

## 1. the order
```
MusterOrder {
  kind:     "transfer" | "merge" | "swap",
  from:     army id (transfer, merge; swap: the first army),
  to:       army id, or "" for a new army (transfer only; swap: the second army),
  units:    [indices into from.units, on the board as it stands when this order applies] (transfer),
  commander: bool (transfer: the commander goes too),
  engines:  int (transfer: how many of from's engines go; 0 by default)
}
```
- **Indices** refer to the board the order applies to: the start of the turn, plus this faction's earlier musters, in order.
  - That board is deterministic, so a plan and its resolution see the same units.
  - **Multi-hop is allowed:** units sent from A to B can go on from B to C in a later muster. Each muster acts on the board as it stands; the end state is the same in planning and resolution.
  - Within one order, an index may appear only once.
  - **Adding, changing or cancelling any muster re-checks every later muster and every non-muster order** (§3).
- **Merge** moves every unit, and the commander if the target has none. If both have one, the source's commander stays behind as a commander-only army, which today's rules allow; the forecast says so before you commit. Engines go too, if the target can carry them; if not, the merge is refused with its reason.
- **Swap** exchanges the two commanders in one step, so neither army is ever leaderless or holds two.
- **Serialized** as `{"type": "muster", ...}` through `to_dict` and `OrderBook.order_from_dict`, with a **strict parser.** Unlike the older lenient parsers, which coerce, default and ignore extra keys (`order_book.gd:285-301`):
  - **transfer:** requires `kind`, `from`, `to` (a String; "" for a new army), `units` (an Array of unique non-negative ints), `commander` (bool) and `engines` (a non-negative int).
  - **merge:** requires `kind`, `from`, `to`.
  - **swap:** requires `kind`, `from`, `to`.
  - Any other key, a missing key, or a wrong type makes the dictionary malformed.
- **A malformed muster in a record is an error:** the record fails to load with a plain reason, never silently skipped (`OrderBook.orders_from_dict` today drops what it can't parse, `order_book.gd:264-276`; a muster isn't dropped). Our own writer never produces one; the case is a corrupt or hand-edited file. Records replay through `GameSession.replay` and `from_record`.

## 2. what may muster
- **Both armies are yours, in the same province,** at the start of the turn and as the plan stands. That is the projected board's location: an army that moves this turn has moved after musters, so musters see where it starts.
- **Neither holds a ruler:** neither the source, nor the target, nor a merge's target (`ruler_rules.gd` keeps a ruler alone).
- **Blessed armies muster like any other.** Their blessings follow §2.1. **A curse doesn't stop a muster:** curses lie on the province (`magic_rules.gd:2081`) and touch every army of the faction there before and after alike.
- **Indices:** an index past the army's end, or repeated within the order, is refused.
- **Non-empty results:** a transfer must move at least one unit or the commander.
  - **The source after it:** if it keeps no units and no commander, it **disbands**, and its engines must have moved (a carrier needs a fighter, `siege_rules.gd:332`), or the order is refused.
  - **The target after it:** at most one commander, and engines within the cap (`FortData.ARMY_ENGINES_MAX`).
- **A new army** gets its id from `next_army_ids`, exactly as `GameState` hands out ids today (`game_state.gd:325`). The projected board allocates it on its copy, and resolution allocates it on the real state in the same order, so the ids match.
  - A refused or cancelled muster allocates nothing: the projection is rebuilt from scratch whenever the plan changes, never edited.
  - **Names:** "the Crown's 4th". Gaps from disbanded armies stay (names are permanent, `turn_report_text.gd:196-217`), and a merge's target keeps its name.

### 2.1 blessings: they stay with their army (Alex 10-10)
Today a blessing is an enchantment that lists army ids (`magic_rules.gd:815-820`).
- Each blessed army heals a set number of hit points a turn, one at a time across its fighters (`enchantment_step`, `_give`, `magic_rules.gd:1459, 1532-1589`).
- A side at least half blessed fights with +1 morale. Its battle log and report count blessed fighters (`auto_battle_resolver.gd:1539-1556, 2674`).
- **Every one of these today decides by army id alone.** ARM-1 makes them decide **per fighter**.

**The rule:**
- **Units that leave a blessed army lose its blessing.** A new army made from them isn't in the blessing's list. A unit that moves on to another army is under that army's blessing only if it was already there.
- **Units that join a blessed army don't gain its blessing,** however they join:
  - by a transfer or merge;
  - a commander by a transfer or swap;
  - **a recruit** that joins an existing blessed army in the recruitment phase (`_add_recruit`, `turn_resolver.gd:1617-1635`).

  Each is marked **outside** that blessing.
  - Summons and successors form new armies (`magic_rules.gd:959`, `ruler_rules.gd:456`), so nothing joins there.

**The marker is the first per-unit status** (Alex 10-10: "that system can then be used to attach any sort of status effect we can conceive of… the more systems thinking the better"). Dominions remembers its afflictions and enchantments on each unit, and so will we.
- **`Unit.statuses`:** a list of status records, each `{kind, source, ...}`.
  - ARM-1 ships one kind, **`outside_blessing`**: `{"kind": "outside_blessing", "source": <the blessing's enchantment id>}`.
  - **Saved only when the list isn't empty,** as `Unit.until` already is (`unit.gd:19, 44`), so every existing record and save is byte-identical.
- **`UnitStatus`** (new, `rules/unit_status.gd`, pure) is the registry. Each kind registers:
  - its fields and their types;
  - its validation;
  - when it clears (a source enchantment ending, the unit leaving its army, a turn count);
  - how it reads in a tooltip and the codex;
  - how it shows in a rival's view (hidden, or seen in clear sight).
- **Helpers:** `Unit.has_status(kind, source)` and `add_status` / `remove_status`, and `UnitStatus.clear_source(source)`. `MagicRules.clear_outside` below is that last call.
- **`outside_blessing` is valid only** if its source is a live blessing of the unit's own faction that lists the army the unit stands in. Validation fails otherwise, with a plain reason.
- **Tests:** a malformed status, an unknown kind, the wrong source kind, owner or army, a commander, legacy bytes, and the registry's own (every kind declares every hook).
- **What it opens up (parking lot, not ARM-1):**
  - afflictions and wounds that last (Dominions' afflictions);
  - veterancy and experience;
  - fear, poison or burning that outlive a battle;
  - per-unit curses;
  - the Candlewake's wax-touched;
  - blessings themselves moving from army lists to per-unit coverage, once every reader goes through the registry.

  Each is a new kind with its own effect code; the plumbing (save, validate, clear, show, fog) is already there.

**Where it counts.** Every place that reads a blessing's coverage takes the blessing's id and skips fighters outside it:
- **healing:** `enchantment_step` passes the blessing id to `_give`, which skips fighters marked outside. The army's full heal goes to the fighters it covers;
- **battle:** a fighter is blessed only if its army is listed and its unit isn't outside that blessing. This drives the half-blessed morale, `blessed_fighters`, the enchantment log and the battle report's text;
- **fog**, in both the clear pooling (`pool_now`, `fog_rules.gd:359-376`) and the glimpse counts (`_count_units`, 414-458): a unit is blessed or plain by itself, not by its army. Commanders stay where today's pooling puts them (plain or extra-commander stand-ins, never the blessed partition), and the codex says so;
- **the computer:** a Dawn Blessing proposal (`ai/ai_magic.gd:511`) values the **covered** fighters, not the army id. A partly covered main army can be worth re-casting on, and a fixture tests it;
- **words:** the army panel and tooltips (`map_screen.gd:1741`; UX-3's card later), the cast forecast, the brief and healing report sentences (`magic_rules.gd:1183, 1233`), and the battle report use covered and total counts: "blessed: 6 of 8 fighters; 2 joined after it was cast." The blessing's codex entry explains it.

**When the marker clears.** One helper, `MagicRules.clear_outside(enchantment_id)` (it calls `UnitStatus.clear_source`), is called on every path that ends a blessing:
- the cast-time replacement of another blessing (`magic_rules.gd:943`);
- time running out, and the last army leaving (`enchantment_step`, 1509-1518).

The marker also clears when its unit leaves the army.

**Re-casting.** A blessing re-cast over an army restarts it **with the same id** (`ritual_effect` and `_begin`, `magic_rules.gd:941, 983`). So a successful cast or restart **clears the outside markers for that id on the armies it now lists**, and the new casting covers everyone in them. (Wards end rival curses, not blessings, so there is no ward case.)

**Multi-hop:** a unit sent from a blessed A to a plain B loses A's blessing; sent on to a blessed C, it is outside C's. Planning and resolution agree.

**The forecast and the report say it:**
- forecast: "2 Knights join the Crown's 1st; its Dawn Blessing won't cover them";
- report: "Two Knights joined the Crown's 1st at Crownkeep. They aren't under its blessing.";
- recruits: "the new Knights join the Crown's 1st, outside its blessing".

**Tests:**
- healing with outside units (none to them; the same budget to the rest);
- half-blessed morale, the battle log and the report with outside regulars and commanders;
- fog clear and glimpse with outside units (the snapshot probe);
- a recruit joining a blessed army;
- the marker clearing at each ending path, and on a re-cast;
- multi-hop;
- validation and save and load;
- the AI fixture;
- byte-identity of every legacy record.

## 3. orders that depend on a muster
Today the order book checks each order against `state_after_orders` (sacrifice effects). ARM-1 adds musters to that function. Musters are **hoisted**: the projection applies every muster first, in order, then checks every non-muster order against the result, wherever it sits in the list. So:
- **Moves, casts, sieges (sallies and relief), recruits and fortify orders** are all checked against the board after your musters. A new army can march, cast or sally the same turn.
- **Changing or cancelling a muster** rebuilds the projection and re-checks every later order. An order that no longer holds (its army gone, its caster moved away) is **dropped with a plain reason**, as a sacrifice or cast change drops orders today (`OrderBook` `_last_dropped`).
- **A pin (a casting army can't move)** follows the army id the cast names, on the projected board.
- **Recruitment** joins the first eligible army by id at the recruitment phase (`turn_resolver.gd:1587-1617`), after movement and battles.
  - The forecast names the army a recruit **would join if the armies still stand there at recruitment**, and says so ("joins the Crown's 4th if it is still at Crownkeep").
  - Ids sort as text: "kingdom-10" comes before "kingdom-2". The forecast uses the same sort, and a test covers it.
- **The planning UI's projected board:** `OrdersController.view_state()` caches the projected board only when a sacrifice is queued, keyed by its mandate (`ui/orders_controller.gd:165-169`). ARM-1 changes it to always project when a muster or sacrifice is queued, and to rebuild after every queue, replacement, removal and cancellation. Cards, roads, casts, sieges and forecasts read that board.

## 4. resolution
- **A muster pass, first in the orders phase:** for each faction in id order, its musters apply in the order given, checked again on the real board.
  - **It mutates the resolver's working copy before anything else in the phase,** before `MagicRules.pinned_armies` and before any `check_move`, `check_cast` or `check_siege_order` (`turn_resolver.gd:621-696`). Those checks run on the real copy, not on `state_after_orders`, so the pass has to come first; a test pins it.
  - A muster can't fail there when the plan passed, since no other faction acts on your armies before it. If one does (a state the plan never saw), it is rejected with an `order_rejected` event, and the non-muster orders naming its armies are rejected after it, each with a reason.
- **The phase lists don't change.** No `muster` phase; `PHASES`, `PATH_PHASES` and `MAGIC_PHASES` and the codex's phase order stay byte-for-byte. The codex gains one sentence under the orders phase.
- **Events**, typed and structured, in the orders phase:
  - `army_split` `{from, to (new), units: [type ids], commander, engines}`
  - `units_transferred` `{from, to, units, commander, engines}`
  - `armies_merged` `{from, to, units, commander_left: bool}`
  - `commanders_swapped` `{a, b}`
  - `army_disbanded` `{army}` (after a transfer emptied it)

  Each has its plain sentence in `TurnReportText` ("Two Knights of the Crown's 1st formed the Crown's 4th at Crownkeep."). **Only the owner's report shows them** (fog filtering, §5).
- **Battles:** splits are a tactic, and they are allowed.
  - Part of an army can hold a province while the rest marches. Defender status follows each army's own move (`turn_resolver.gd:139, 772`), and a fragment that stays is the holder.
  - Several fragments can take different roads. Each is its own army in movement and battles, as two armies are today.
  - The codex entry and the forecast say this plainly: "the half that stays defends Crownkeep; the half that marches meets the Free Holds at Westwatch."

## 5. fog
- **Your own view** shows everything.
- **A rival's view:** armies are pooled stand-ins per (faction, province), split by blessing and by extra commanders (`fog_rules.gd:352-549`).
  - **Blessing partitions:** a muster can move units across them. Units that leave a blessed army become plain, and units that join one are plain inside it (§2.1). The rival's view pools by the unit, so what a rival sees in sight is exactly the true blessed and plain counts, no more.
  - **Engines** are pooled and handed out to stand-ins synthetically, not by their real carrier (`fog_rules.gd:428`). Moving engines between your armies may change nothing in a rival's view, or change which stand-in seems to carry them.
  - Commanders can move, so the **extra-commander stand-ins can change**. A rival who has that province in sight sees the new count of commanders there, exactly as they would see any change of composition. A rival who doesn't, sees nothing. This is stated, not hidden: musters are visible like any army in sight.
- **Muster events** are the owner's only. A rival sees the result through sight at the end of the turn, not the order.
- **Memory continuity:** a remembered stand-in keeps its view id and note until it is seen again, as today.
- **Tests:** the snapshot probe (`tests/fog_test_kit.gd`). A rival's view after a muster equals the view of the same composition reached without one, in clear, glimpse and memory views, including transfers, merges and disbands that move engines.

## 6. the computer
- **It never orders a muster** in ARM-1.
- **It plans from the real state each turn** (after resolution, the ids are real), so a human's musters reach it as ordinary armies.
- **Tests:** an audit of its id-keyed caches (`ai/ai_player.gd:267, 521`, `ai/ai_sieges.gd:67`), plus AI-versus-human fixtures where the human splits, merges and swaps under fog, sieges and magic. The AI's orders must stay valid, and its games without a human muster byte-identical.

## 7. the forecast and the explanation
- **`MusterForecast`** (pure). Given the start board, the plan and a candidate muster, it returns for each army involved:
  - the units, commander, engines, strength, sight and name, before and after;
  - the orders the muster would drop, with their reasons;
  - each queued recruit's destination army;
  - a battle note when a fragment will hold and another march.

  The army card shows it as you drag, and the order book's refusal reasons come from the same function.
- **Explained:** a codex entry, "Splitting and merging armies" (what may muster, enchantments, rulers, engines, the tactic); the order's tooltip and Plan sentence (UX-5); and every refusal in plain words.

## 8. the UI (with UX-3)
`design/UX_WAR_TABLE.md` §3.5:
- the army card lays out your armies in the province side by side;
- drag units and commanders between them, or to "New army";
- **Split**, **Merge all** and **Swap commanders** buttons;
- the forecast updates live as you drag, before anything is ordered;
- engines are a stepper on the transfer;
- the tray token and Plan sentence;
- an army that can't muster is greyed, with its reason.

## 9. tests (ARM-1's PR)
- **The order:** serialization and strict parsing; every refusal in §2; indices against the sequential board; duplicate claims.
- **The projection:** ids allocated on the copy match resolution's; cancelling or changing a muster rebuilds it and drops dependants with reasons; nothing is allocated for a refused muster.
- **Dependencies:**
  - a new army's move, cast, sally and relief;
  - a mage moved out of a casting army;
  - a pin;
  - recruits' destinations;
  - engines with each carrier rule and the cap.
- **Battles:** hold-and-march (who is the holder), multiple destinations, a border swap with a fragment.
- **Records:**
  - **every legacy fixture replays byte-identically** (`test_paths_off`, `test_fog_off`, `test_game_session` and the fixture suites);
  - an explicit assertion that the phase arrays and codex text are unchanged for a game without musters;
  - records with musters replay through `replay` and `from_record`;
  - save and load mid-plan.
- **Fog:** the snapshot probe (§5).
- **The computer:** the fixtures in §6.
- **Names:** across split, merge, summon, successor, recruitment, save and replay.

## 10. out of scope
- Musters across provinces, or during a move.
- The computer mustering (a later AI ticket).
- Recruit orders naming their destination army (the forecast names it instead).
- **Each faction's own way to muster** (the Candlewake's guttered masses, say). That belongs with the faction flavour, later.

## 11. director's calls
1. **One order, three kinds,** planned on the projected board and resolved first in the orders phase. No refs and no new phase.
2. **Blessings stay with their army** (Alex 10-10): leavers lose them, and joiners are marked outside them. **Rulers' armies don't muster.** Curses, which lie on provinces, don't matter.
3. **Splits are a tactic,** not an exploit: holding with part and marching with part is allowed and explained.
4. **Engines move only when told,** within the carrier rules.
5. **Musters are visible like any army in sight;** the orders themselves are private.
6. **The computer doesn't muster yet;** a human's musters reach it as ordinary armies.

## 12. questions for Alex
1. ~~Blessed armies~~: **answered 10-10: b),** "genuinely the long-term answer so we might as well build it now" (§2.1).
2. ~~Merge all when both armies have commanders~~: **answered 10-10: a),** the source's commander stays behind as its own army, and the forecast says so first.

---

## appendix A. critic rounds

**r6** (Alex 10-10): the marker becomes the first kind in a general per-unit status list (`Unit.statuses`, `UnitStatus`), so any status effect can attach to a unit later.

**r4** (Alex 10-10) replaced "blessed armies can't muster" with blessings that stay with their army (§2.1).

### round 3 (Codex, focused on §2.1, 2026-10-10): "the marker approach is sound, but the spec is not implementation-complete". 10 findings, 2 blockers. All taken in r5.
- **Blockers:**
  - a re-cast keeps the same id, so it clears the markers;
  - recruits joining a blessed army are marked too.
- **Majors:**
  - one clearing helper for every ending path;
  - no ward case;
  - healing, battle, fog clear and glimpse counted per fighter;
  - marker validation;
  - the AI values covered fighters.
- **Minor:** covered and total counts in every player-facing text.

### round 2 (Codex, hostile, on r2, 2026-10-10): 9 findings, 2 blockers. All taken.
- **Blockers:**
  - musters are hoisted before all non-muster orders, and any muster change re-checks them all (§3, the short version);
  - a malformed muster fails the record's load instead of being skipped (§1).
- **Majors:**
  - the planning UI's projected-board cache rebuilds on every change (§3);
  - the muster pass mutates the resolver's copy before pins and checks (§4);
  - multi-hop transfers are allowed, and "leaves once" dropped (§1);
  - the strict parser's exact keys and types (§1);
  - curses lie on provinces, so only blessings exclude (§2);
  - the recruit forecast is conditional, and ids sort as text (§3).
- **Minor:** rival engine pooling stated and probed (§5).

### round 1 (Codex, hostile, on the issue's draft, 2026-10-10): 25 findings, 10 blockers. All taken.
- **Blockers:**
  - refs can't pass the order book: replaced by the projected board, so there are no refs (§1, §3);
  - the atomic swap: its own kind (§1);
  - replay: a strict serialized shape (§1);
  - the new phase: dropped, so musters run first in the orders phase (§4);
  - mutable indices: defined against the sequential board, with re-checks (§1, §3);
  - blessings: enchanted armies can't muster (§2);
  - fog: musters are stated as visible in sight, and probe-tested (§5);
  - casts and sieges: checked on the projected board (§3);
  - engines: explicit, within the carrier rules (§1, §2).
- **Majors:**
  - "last transfer" engine ambiguity removed;
  - merge with two commanders;
  - rulers on either side;
  - id allocation and names;
  - dependent orders dropped with reasons;
  - battle tactics endorsed and tested;
  - "empty" defined;
  - recruitment's destination in the forecast;
  - the AI audit;
  - structured events;
  - the high-risk tests;
  - the legacy replay suite.
- **Minor:** the forecast is required.
