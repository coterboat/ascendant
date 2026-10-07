# Veiled Table v3: Called It

## The faction in two sentences

The Veiled Table wins by saying what everyone else is about to do, committing those predictions with its orders, and turning correct calls into tempo. It is not omniscient and it does not falsify the resolver: it studies the same incomplete world available to its player, makes a public-feeling wager, and earns the delicious post-resolution moment when the report says, **Called it.**

The fantasy is a room full of hosts, couriers, cooks and witnesses reading six wars at once beneath the Held Sun. One rival’s march may be nowhere near Table land. It still matters, because correctly understanding the whole table is the faction’s power.

## Faction rule: Calls

During planning, the Table may lock up to **three Calls** alongside its ordinary orders. Each Call predicts one checkable event in the coming resolution. The starting menu is deliberately small:

- a named rival army enters one of two adjacent provinces;
- a named province changes owner, or does not change owner;
- a named rival fights at least one battle;
- a named public ruler moves, remains, or falls;
- two named rival factions meet in battle.

The interface offers only legal subjects the Table’s current view can name. A remembered army can be called by its public faction and last-seen army name, but the tooltip makes the uncertainty explicit. Calls are stored with the submitted order bundle and scored after resolution from the authoritative event log. There is no random roll and no judgment call: replaying the same orders produces the same answers.

Each offered Call has a visible value of one to three **Insights**. Insight is a short track, not spendable currency. An obvious call pays one: a huge army beside an empty Free Hold probably takes it. A constrained call pays two: which branch that army chooses. A hard call pays three: two distant rivals meet, or an unseen remembered army reappears in a particular place. Difficulty is computed when the Call is locked from public geometry, current viewer knowledge and the forecast’s existing probability bands. It never changes after seeing hidden orders.

Safe non-events are controlled. “This remote province does not change owner” is never offered unless the province is currently contested, adjacent to a visible threat, or changed owner recently. The same subject cannot fill two slots, repeating the same successful Call on consecutive turns reduces its value by one, and a zero-value Call cannot be locked. Pass is always allowed.

## The reward: a mind gathering momentum

Correct Calls add their Insights to a five-space track. Wrong Calls break the current streak but do not remove banked spaces. A turn with at least two correct Calls advances the streak; at three consecutive such turns, the Table earns **Read Ahead** for its next planning phase. Read Ahead upgrades one existing sighting by one information step for free, using the same bounded result as Sound the Depth. It does not reveal an order.

Filling all five Insight spaces triggers **Set the Room** after resolution. The player chooses one of three simple rewards for next turn: one free Sound the Depth, one Listening Post that does not consume movement, or a modest gold rebate on Terms Before Spears. Then the track empties. These are information and tempo rewards, not direct battle damage. The faction feels clever because understanding creates the favorable battle; the prediction itself does not kill anyone.

The turn report makes the payoff theatrical but brief. Resolution first shows the event, then stamps a copper bowl beside it and expands a single line: “Called it: the Ninth Fang marched to Mossbridge. Hard Call, +3 Insight.” Other players receive a public summary—“The Veiled Table correctly called two rival moves”—but never the Call’s hidden premise, source sighting or reward choice. A perfect three-Call turn puts three smoke curls above Commonroof for one round on the shared board. That is the boast everyone sees.

## The old fog tools now serve the read

**Read the Room** becomes the Calls screen’s evidence layer. It groups clear sightings, glimpses, memories and contradictions without producing new facts.

**Sound the Depth** still spends gold to narrow one sighting or reveal a bounded fact. Its main purpose is now obvious: pay before commit to turn a hunch into a better Call. It never reveals orders.

**Listening Posts** still cost an army’s movement to create a temporary sight source. Their new value is coverage: each post may unlock Calls about one additional province within its sight range. The unit did not march, so the player has paid for that reach.

**Open the Ledger** still trades the ruler’s province action for one bounded intel fact. It can raise or lower a Call’s displayed difficulty only because the player genuinely knows more.

**Terms Before Spears** remains the Table’s conditional way to take a Free Hold. Calling that same Hold’s ownership is legal but worth no Insight: the Table cannot manufacture a wager it already controls.

**False Place Setting** should not ship with Calls. Viewer-only decoys are the most expensive and trust-sensitive part of the old kit, and prediction already supplies the faction’s signature. It can return later as an advanced mandate, with no ability to affect the Table’s own Call values.

## Fairness, especially in hotseat

Calls never expose another player’s submitted orders. Before handoff, the Table sees choices generated only from `state_for(viewer)`, its memory and intel, public facts, and existing forecasts. Once locked, Calls disappear behind the handoff screen with the rest of that player’s orders. Later players see no pending predictions. The resolver evaluates Calls only after all movement, battles, captures and deaths are complete.

The scoring record stores a predicate and public identifiers, not a snapshot of hidden state. Reports are filtered per viewer. If a correct Call depended on an army the Table could only remember, rivals learn merely that a hard Call succeeded—not that the Table had a Listening Post, exact count, or special sight line. Static checks should forbid Call UI and AI code from truth accessors just as fog already does.

## Computer play

The AI receives exactly the Table’s per-viewer state. It builds a small candidate list, estimates each event from visible strength, shortest paths, objectives, ownership pressure and its normal opponent model, then selects Calls by expected Insight with a diversity rule across factions and event types. Easy AI favors high-confidence one-point Calls. Strong AI considers more candidates and accepts worthwhile uncertainty, but never reads true armies or pending orders.

Calls also improve legibility of the AI’s action. Its end-turn report can say, “It expected the Crown to defend Sunfield because the Noonmark was threatened.” Difficulty changes search breadth, not information.

## Counterplay

The answer is to become harder to read, but unpredictability must have a price. Splitting an army, taking a longer road, holding beside an obvious objective, or declining an advantageous attack can spoil a Call; each also sacrifices concentration, movement or tempo. A rival can destroy Listening Posts, deny clear sight, present two credible targets, or use an unexpected commander composition. It cannot simply toggle “be unpredictable.”

Because the Table is rewarded for calls about wars elsewhere, opponents cannot fully starve it by avoiding its border. They can, however, reduce the value of obvious play. Publicly transforming, moving a ruler, or massing at a Noonmark broadcasts intent. That is fair: those actions are powerful enough to bear an informational cost.

Wrong Calls must matter without creating a death spiral. They break streaks and occupy scarce slots, but do not take gold or delete accumulated Insight. The Table has spent attention and missed tempo; it has not lost an army to a bad guess.

## Avoiding analysis paralysis

The Calls panel recommends three candidates and can fill them with one button. Advanced players may open a list capped at twelve candidates, sorted by subject, with no free-form province-by-province construction. Each card contains one sentence, one value and one evidence drawer. Calls lock with ordinary orders, and changing relevant Table orders automatically revalidates them.

New players begin with two slots; a path node unlocks the third. A preset called **Read the Neighbours** chooses the safest varied Calls. The post-turn reveal resolves all Calls in one compact sequence. No agent roster, spy assignment, probability slider or separate currency is added.

## Engine cost and sensible cut line

The core build needs: a serializable `CallOrder` row; candidate generation from viewer state; stable event-log predicates for movement, battle, ownership and ruler events; deterministic scoring after resolution; per-viewer report lines; the five-space track and streak on faction state; save/load and replay fixtures; forecast/tooltips; hotseat concealment tests; and AI candidate valuation. The existing report, movement events, ownership changes, ruler events, fog accessors and order submission pipeline do most of the heavy lifting.

The cheapest shippable version has two Calls, four predicate types, fixed one-or-two Insight values, the track, and one Read Ahead reward. Three slots, dynamic three-point difficulty, Set the Room choices and public smoke flourish are polish. False Place Setting remains out. This keeps the promise sharp: predict the turn, see the world prove you right, and use that knowledge before anyone else can.
