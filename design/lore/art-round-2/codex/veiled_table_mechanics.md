# Veiled Table: The Quiet Turn

The Veiled Table should not win by applying a better combat modifier. It should win by making several truthful, limited views of the same turn work together: discovering which threat is real, offering Free Holds a way not to fight, and placing decoy evidence where rivals expect an army. The resolver still sees ordinary orders and true state. Only each player's fog view changes.

## Turn loop

A Table turn begins with **Read the Room**. The player opens an intelligence overlay that sorts border provinces into known, estimated, remembered, and unknown. It highlights contradictions: a glimpse larger than last turn, an army that vanished from sight, a newly empty fort, or a rival whose visible movement cannot explain a capture. This is presentation over the existing per-viewer view state, not omniscience.

Next comes **Set the Table**. The player spends a small, capped number of influence actions. Influence is not a new currency: each action costs gold, an army order, or a ruler/commander action, and the UI shows that cost immediately. The player might investigate one rival army, prepare terms for one adjacent Free Hold, plant one false sighting, or establish a listening post.

Then the player gives ordinary movement, recruitment, research, ritual, and battle orders. Forecasts show two columns where uncertainty matters: “if your current sight is accurate” and “known limits.” Prepared terms show exactly why a Hold will or will not accept. Finally, after resolution, the turn report separates public events, reports from the Table's own witnesses, and claims that proved false. The pleasure is deduction followed by commitment, not clicking through spy menus.

## Signature actions

### 1. Sound the Depth

Choose one glimpsed rival sighting within range of a Table scout, commander, fort, or listening post. Pay gold to improve that sighting by one information step for this planning phase: narrow its total-size band and reveal either its largest unit type or whether a commander/ruler is present. It never grants exact hit points or the rival's orders, and never turns a veiled province into clear sight.

The forecast names the source and result: “Your courier at Mossbridge narrows the sighting from about 8–12 to about 9–10; at least one Tide Strider is present.” This touches fog estimates, sight sources, order validation, gold, and the viewer-specific forecast. It does not touch resolution.

### 2. Terms Before Spears

Choose one adjacent Free Hold that the Table can see and prepare a public offer. The offer has two or three legible conditions selected from existing state: pay gold; leave no Table army in the Hold this turn; have no rival-owned neighbour; or keep a ruler in an adjacent province. During the normal capture phase, if every previewed condition is true, the Hold changes owner without a battle and its garrison becomes unavailable for one turn while oaths are settled. If any condition fails—including a rival army arriving—the normal deterministic battle occurs.

The Hold's acceptance calculation is visible to the Table before commit and becomes public only if ownership changes. This replaces Sworn Vassals for this faction rather than stacking with it. It touches neutral ownership, Free Hold garrisons, gold, movement arrival, captures, reports, and AI valuation. It is the Table's economic tempo tool, but it cannot steal an owned province or bypass a rival contest.

### 3. False Place Setting

Choose an owned province in range of a Table commander or listening post. Create a decoy army sighting with a declared broad size band and one plausible public roster silhouette. The decoy exists only in eligible rivals' next view states: clear sight immediately disproves it; a glimpse may display it as an estimate; veiled memory records nothing new. It can never move, capture, block, fight, provide sight, alter a forecast's underlying rules result, or fool the AI through truth access. Instead, both human and AI opponents receive the same viewer-specific decoy datum and confidence marker.

If a rival plans against it, their forecast says “an unconfirmed sighting may be present,” never that an army certainly exists. At resolution the decoy expires, and a rival who gains clear sight gets “the report was false” in their private turn report. This touches view-state sightings, memory, forecast language, and AI belief weights only. Hotseat remains fair because the handoff rebuilds the next player's view and never shows who planted it.

### 4. Listening Post

A Table army may spend its movement order to establish a temporary post in an owned province. Until the next resolution it acts as a sight source with scout range and lets Sound the Depth reach from that province. It disappears if the province changes owner. On the 3D board it is a small field table, awning, and smoke standard visible only to its owner and to rivals with clear sight.

This creates the central positional choice: march troops, or stop them to improve next turn's knowledge. It touches army orders, sight sources, ownership checks, view-filtered board props, and turn reports.

### 5. Open the Ledger

Once per turn, the Table's ruler may spend its province action to investigate one rival with whom it has gained sight this turn. Choose one category—mandates, kept power, ordinary research, or spellbook—and gain one bounded fact already supported by the intel system. The ruler cannot move that turn. The action's tooltip lists every possible result before commit, and the report identifies the sight event that made it legal.

This touches ruler actions, existing intel records, sight events, and reports. It makes keeping ruler power meaningful: a powerful ruler survives at a listening frontier, while a heavily sacrificed ruler must work from safer forts.

## Winning fights it cannot win by force

The Table does not delete enemy troops or secretly rewrite orders. It wins by avoiding the wrong battle. Sound the Depth tells it which border is weak. False Place Setting pressures a rival to guard the wrong province, but openly carries uncertainty. Terms Before Spears turns a neutral flank without losing bodies. Listening Posts let small armies pause and create a better planning turn. When combat is unavoidable, the Table uses ordinary commanders, terrain, forts, formations, spells, and mandates; its advantage is that it more often chooses a favourable defender battle or a meeting against a divided rival.

## Counterplay

Clear sight defeats decoys immediately. Scouts and Far Sight are the hard answers; moving unpredictably and attacking posts are softer ones. A rival can contest a Free Hold to void peaceful terms, cut the Table away from adjacency, or force it to spend gold on repeated investigation. Public ownership, rulers, deaths, transformations, and global rituals remain public exactly as in the base fog rules. No Table action conceals them. The Table also pays opportunity cost: stopped armies, an immobile ruler, and gold not spent on recruits or magic.

## Computer play and build cost

The AI already consumes a per-viewer state, so it must never be handed truth to “understand” a decoy. Give each sighting a confidence and expected-value range. The AI uses Sound the Depth where narrowing that range could flip a move decision; offers Terms when its expected capture cost exceeds the price; plants decoys near threatened objectives; and places posts on high-centrality owned provinces. Difficulty changes planning breadth, not hidden information.

The cheapest pieces are Read the Room and Open the Ledger, which mostly expose existing fog and intel data. Sound the Depth adds a temporary estimate override. Listening Post adds an army order and sight-source row. Terms Before Spears adds a conditional neutral-capture branch. False Place Setting is the riskiest build: it requires a new viewer-only sighting record, save support, forecast copy, AI belief handling, hotseat tests, and strict static checks that it never enters `GameState` or the resolver. If schedule is tight, ship the first four and prototype decoys last.

## Where it may not be fun

The danger is analysis paralysis, especially if every province invites an operation; the guardrail is two influence actions per turn by default, repeat-last-turn support, and a recommended action marker. Deception can feel like the game lied; every uncertain sighting therefore carries a confidence icon and source tooltip, and no forecast converts it into certainty. Peaceful Hold capture can feel like stolen combat; rivals get a full turn of public adjacency information and can contest it. Espionage can become punitive bookkeeping; posts expire automatically, operations have no agents to shuffle, and failed actions explain one cause in plain language. Finally, a player who dislikes deduction should have a preset plan—“Scout border, offer nearest Hold”—that is competent, transparent, and editable.

This design makes the Veiled Table's question fundamentally different: not “which bonus wins this battle?” but “which battle is real, and can I make it unnecessary?”
