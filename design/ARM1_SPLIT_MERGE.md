# ASCENDANT: ARM-1, splitting, merging and swapping commanders

Status: **DRAFT r3 by the director (Claude session, 2026-10-10), for Alex's sign-off.** Part of the War Table milestone (`design/UX_WAR_TABLE.md` §3.5); issue #195.
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
- **Blessed armies can't muster** in the MVP, giving or receiving (blessings are the only enchantments that name armies, `magic_rules.gd:815`; curses lie on provinces and touch every army there alike). A ruler's army can't either: a ruler travels alone.
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
- **Neither is blessed** (`MagicRules`' blessing on the army, `magic_rules.gd:815`). The forecast says "the Crown's 1st is blessed: it can't take or give troops while the blessing lasts." Inheriting blessings is later. **A curse doesn't stop a muster:** curses lie on the province (`magic_rules.gd:2081`) and touch every army of the faction there before and after alike.
- **Indices:** an index past the army's end, or repeated within the order, is refused.
- **Non-empty results:** a transfer must move at least one unit or the commander.
  - **The source after it:** if it keeps no units and no commander, it **disbands**, and its engines must have moved (a carrier needs a fighter, `siege_rules.gd:332`), or the order is refused.
  - **The target after it:** at most one commander, and engines within the cap (`FortData.ARMY_ENGINES_MAX`).
- **A new army** gets its id from `next_army_ids`, exactly as `GameState` hands out ids today (`game_state.gd:325`). The projected board allocates it on its copy, and resolution allocates it on the real state in the same order, so the ids match.
  - A refused or cancelled muster allocates nothing: the projection is rebuilt from scratch whenever the plan changes, never edited.
  - **Names:** "the Crown's 4th". Gaps from disbanded armies stay (names are permanent, `turn_report_text.gd:196-217`), and a merge's target keeps its name.

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
  - Blessed armies can't muster (§2), so a muster never moves a unit across a blessing partition.
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
- Inheriting or splitting blessings; musters by blessed armies.
- Musters across provinces, or during a move.
- The computer mustering (a later AI ticket).
- Recruit orders naming their destination army (the forecast names it instead).
- **Each faction's own way to muster** (the Candlewake's guttered masses, say). That belongs with the faction flavour, later.

## 11. director's calls
1. **One order, three kinds,** planned on the projected board and resolved first in the orders phase. No refs and no new phase.
2. **Blessed armies and rulers' armies don't muster** in the MVP. Curses, which lie on provinces, don't stop a muster.
3. **Splits are a tactic,** not an exploit: holding with part and marching with part is allowed and explained.
4. **Engines move only when told,** within the carrier rules.
5. **Musters are visible like any army in sight;** the orders themselves are private.
6. **The computer doesn't muster yet;** a human's musters reach it as ordinary armies.

## 12. questions for Alex
1. **Blessed armies:**
   - a) can't muster in the MVP (my pick: simple, safe);
   - b) a blessing stays with its army id, and units that leave lose it, units that join don't gain it (more to build and test).
2. **Merge all when both armies have commanders:**
   - a) the source's commander stays behind as its own army (my pick; the forecast says so);
   - b) refuse until you swap or move one.

---

## appendix A. critic rounds

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
