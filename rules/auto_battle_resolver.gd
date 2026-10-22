class_name AutoBattleResolver
extends BattleResolver
## The real battle rules (#4). Pure and deterministic: every roll comes from the SeededRNG passed in,
## sides go in sorted faction id order, armies in sorted id order, units in army order, commanders
## last. Player-facing statement of these rules: RulesCodex "battle_*" and "trait_*" entries.
##
## A battle is fought in rounds, at most ROUND_CAP. Each round every standing fighter (unit or
## commander) attacks once, all at the same time (damage lands at the end of the round):
##   target  a random standing enemy it can reach (_targets). Units without Volley form the front
##           rank. Volley units (Crossbowmen) form the second rank: the front rank shields them while
##           at least as many front-rank units stand as second-rank ones, and attackers with Skirmish
##           (Fangthrowers) can always reach them. Commanders stand behind everyone and can only be
##           targeted once no unit stands in front of them.
##   hit     chance = BASE_HIT + HIT_PER_POINT per point of attack above the target's defense,
##           clamped to MIN_HIT..MAX_HIT percent. One roll of 1-100 per attack.
##   damage  ceil(attack / 2) - floor(target defense / 4), at least MIN_DAMAGE.
## Terrain helps only the defender (the faction that held the province): TERRAIN bonuses, plus
## FORT_DEFENSE in a province with a fort. Border battles and meetings where everyone arrived this
## turn have no defender, so nobody gets terrain.
## Forts and sieges (M3c S-1b, design/M3C_SIEGES.md §4.1): a battle at a fort in a game with sieges carries a
## "siege" block (SiegeRules.siege_block). Then the flat fort bonus is gone; in a storm every fighter of the
## stormed armies (from_inside) gets WALLS defense (WALLS_DEFENSE_PER_STEP for every WALL_STEP wall strength
## standing, rounded up), and in a sally or a breach battle the fighters from inside get COVER (COVER_DEFENSE).
## Engines are counts on armies, never fighters, so this code never sees them.
## Morale: a side's morale = average morale of its units at the start (rounded down; a lone
## commander uses its own), +COMMANDER_MORALE while its commander stands, + trait effects (Inspire,
## Fury). At the end of each round a side breaks (routs) once it has lost at least
## BREAK_BASE_PCT + morale x MORALE_PCT_PER_POINT percent of its starting hp (clamped to
## MIN_BREAK_PCT..MAX_BREAK_PCT).
## A routed side leaves the battle and loses. The TurnResolver then destroys every army on a losing
## side, routed or not (including attackers still standing at the round cap): no retreats in M1.
## The battle ends when only one side is left in the field. If every remaining side drops out in the
## same round, the one with the largest share of its starting hp left keeps the field (then the
## defender, then a seeded roll). Round cap: after ROUND_CAP rounds the defender holds if it is still
## standing; with no defender, the side with the largest share of its starting hp left wins (ties: a
## seeded roll).
##
## Traits (data/factions.gd gives each unit type one), one effect each. The trait constants below are
## the single source of truth for their numbers: the rules read them, and every description players
## see is built from them (TRAIT_TEXT, which is data/factions.gd's trait_desc and the start of each
## RulesCodex trait_* entry, and TRAIT_SHORT):
##   Shield Wall  +SHIELD_WALL_DEFENSE defense while another friendly fighter stands.
##   Volley       fights from the second rank, shielded while its front rank is at least as big.
##   Charge       +CHARGE_DAMAGE damage on hits in round 1 (CHARGE_DAMAGE_FOREST in a forest).
##   Inspire      +INSPIRE_MORALE to its side's morale while it stands.
##   Berserk      +BERSERK_ATTACK attack while below full hp.
##   Skirmish     can attack the second rank as well as the front rank (see target above).
##   Fury         each standing War Bear gives enemy sides -FURY_MORALE morale (at most -FURY_MAX).
##   Pack Leader  +PACK_LEADER_ATTACK attack to every friendly unit while it stands.
##
## The report's "why" names the 1-3 factors worth the most hp to a side. Every factor is measured as
## what it added over doing without it, in expected damage (or hp kept from a rout), so they compare:
## a trait counts only its own effect (Charge: the charge bonus on its hits), and a commander counts
## the damage it dealt beyond what the same gold in its side's ordinary units would have dealt
## (_line_baseline). Its morale and its trait (Inspire, Pack Leader) are factors of their own.
##
## Rulers and mandates (M2-2, #30; design/M2_RULER.md §1.6, §2.3, §7.4). Only in a game with rulers
## (GameState.with_rulers): without a ruler on the field and without mandates, a battle is fought, and
## reported, exactly as above. The numbers come from data (RulerData, MandateData) through RulerRules
## (unit_stats, unit_max_hp, battle_effects, dread_value), the same functions every tooltip reads:
##   the ruler    fights beside its side's armies with the stats its kept power gives it. King Corvane,
##                the Great Thornmane and the Ninth Fang stand in the front rank; the Ever-Regent in the
##                second rank, with the Volley units and under the same shield rule (Skirmish reaches
##                him). +RULER_MORALE morale to its side while it stands. Not a unit: Royal Armories,
##                Veteran Levies and Pack Leader skip it. When it falls in a battle its side wins, its
##                army no longer holds it (army.ruler = null) and TurnResolver records the death.
##   Dread        the Great Thornmane: every enemy side in a province battle (not a border battle) has
##                its ability value less morale while the avatar stands. Adds to Fury.
##   Iron Discipline   a side that would break does not while one of its commanders stands, except at
##                     the end of the last round (ROUND_CAP), where the usual check applies (M2-8).
##   Drilled Ranks     the side's base hit chance is the mandate's base_hit (70) instead of BASE_HIT.
##   Veteran Levies    regular units have more maximum hp (RulerRules.unit_max_hp).
##   Royal Armories    regular units have more attack and defense (RulerRules.unit_stats), as named parts.
##   Blood Frenzy      every fighter below its maximum hp has more attack, a named part like Berserk.
##   Feast of Victory  after a battle the side wins, its standing fighters heal to full (_apply_losses).
## Each of these is a "why" factor measured like the rest: the ruler counts the damage it dealt (it costs
## no gold, so all of it is what it added), its morale is a factor of its own (morale_ruler), the stat
## mandates count what their parts added (mandate_*), Veteran Levies the damage its extra hp absorbed,
## Iron Discipline the hp it kept from a rout, and Dread is measured like Fury (ability_dread).
##
## The battle event log (M3-1, #56; design/M3_BATTLES.md §2). fight(..., record = true) also writes a
## complete log of the battle while it fights, from the same values it uses: every attack with its
## target roll, hit roll, chance, damage and their parts, every wound, death, morale check and rout,
## round by round, and the RNG state before and after. Schema, checks and helpers: BattleLog
## (rules/battle_log.gd). Recording is passive: it draws nothing from the RNG, reorders nothing and
## changes no state, so the report, the winner, the armies and the RNG state are the same with it on or
## off. resolve_battle() records (TurnResolver keeps the log in the event's numbers.log); estimate() and
## resolve() by default don't.
##
## Paths of ascension in battle (M4-3, #68; design/M4_ASCENSION.md §4.7, §4.9, §4.10, §9.6). Only in a
## game with paths (GameState.with_paths) or with a transformation's new unit on the field: otherwise a
## battle, its report and its log are exactly as above. The numbers come from PathData through
## RulerRules.unit_stats (AscensionRules.unit_parts) and the constants below:
##   path parts   every researched node's stat parts on regular units, as named parts "path_<node>": attack
##                and defense in _attack / _defense, hp in the maximum hp, and morale in the side's base
##                morale (the average now counts each unit's morale with its parts; base_morale_parts says
##                how much of it each node gave). Each is a "why" factor measured like a mandate's part
##                (morale: like Inspire, "morale_path_<node>").
##   Wings        (Seraphs) can attack any enemy fighter, whatever its rank; while an enemy commander
##                stands it attacks a commander (a seeded pick among them, the same single target roll).
##   Iron Hide    (Iron Colossus) every hit on it deals IRON_HIDE_DAMAGE less, never below MIN_DAMAGE: a
##                named damage part beside Charge's.
##   Rooted       (Briarwardens) +ROOTED_DEFENSE defense in a province battle in a forest province, whoever
##                holds it; never in a border battle. A named defense part.
##   Lifedrinker  (Bloodsworn) at the end of each round, after damage lands and before morale is checked,
##                if it still stands it heals 1/LIFEDRINK_DIVISOR of the damage its hits dealt that round,
##                rounded up, up to its maximum.
##   Dread Lands  (the Blood Pact's province rule) in a province battle in a province the Blood Pact
##                owned at the start of the turn, every enemy side has the rule's value less morale for the
##                whole battle (a morale part "Dread Lands"). Ownership only changes in the capture phase,
##                after every battle, so the province's owner as the battle is fought is that owner. It
##                doesn't stack with Dread (M4-6, §10.3 and §15 call 13): while an enemy ruler's Dread takes
##                morale from a side, Dread Lands takes only what goes beyond it (with both at 1, nothing),
##                and it takes its full value again once that ruler has fallen.
##   Red Harvest  (mandate) after a battle its side wins, RED_HARVEST_GOLD gold for every enemy fighter lost
##                in it (all of a losing side's fighters: fallen, or destroyed with their armies). The
##                report gets "red_harvest"; TurnResolver pays it.
## Report sides gain "people" ({"id", "name"} of the transformation, or {}) in a game with paths.
##
## Battle spells (M5-7, #118; design/M5_MAGIC_FOG.md §5). Only in a game with magic (GameState.with_magic): without
## it a battle, its report and its log are exactly as above, and a magic battle with no caster draws exactly what it
## would have drawn without magic. The numbers come from MagicData through MagicRules (spellbook, battle_spells,
## mastery_bonus, spell_numbers, can_heal), the same functions every tooltip reads:
##   Mage         (Sunstone Adepts, Thornmane Shamans) fights from the second rank, under Volley's shield rule.
##                It casts instead of attacking; one with nothing useful to cast attacks, and is never Volley.
##   the cast step  each round, after the round event and before the first attack, every standing caster (each
##                mage, and the Ever-Regent) casts: highest mastery bonus first (its best over its schools), the
##                ruler first among equals, then fighter order. Each casts the first spell of its side's spellbook
##                (on spells only, that it can cast) that is useful and that nobody on its side has cast yet this
##                round; once every useful spell has been cast, it starts again from the top. Spells never roll.
##   bolts        (Sunlance, Bloodbolt) sure damage at the end of the round, to a target picked by the spell's
##                rule among the enemies the caster could attack, counting damage already aimed at them this round
##                (never overkill), rulers and commanders only when nothing else is in reach. A ruler's spell
##                resistance (spell_resistance) takes ability rank / MagicData.RULER_RESIST off, never below 1.
##                Bloodbolt bleeds its caster (never below 1 hp), which the morale check leaves out and which
##                closes after a battle its side wins (resolve_battle).
##   hexes and shields  a part "spell_<id>" on the targets' attack or defense for the round: Briar Snare and Sunburst
##                -2 attack (credited, in the "why", to the side that cast it), Shield of Law +4 defense on units
##                without a terrain or fort bonus.
##   Dawn Blessing  +morale for the whole battle to a side with at least half its fighters in blessed armies.
##   Blood Moon   the moon's side heals back a quarter of the damage its attacks dealt each round (rounded down;
##                Lifedrinker's larger share instead), never above its maximum - 1; not in a province a rival warded.
##   curses       a side standing in a province a rival cursed heals from nothing: no Lifedrinker, moon or Feast.
## Each is a "why" factor with its codex entry: "spell_<id>" (bolts: the damage dealt; hexes: the expected damage
## taken off enemy attacks; shields: what the defense blocked; the moon: the hp healed back) and
## "morale_spell_dawn_blessing". The log gains "magic": true and its additions (BattleLog); report sides gain
## "casters" and "spells_cast".

const ROUND_CAP := 8
const BASE_HIT := 60
const HIT_PER_POINT := 4
const MIN_HIT := 30
const MAX_HIT := 90
const MIN_DAMAGE := 1
const BREAK_BASE_PCT := 20
const MORALE_PCT_PER_POINT := 5
const MIN_BREAK_PCT := 25
const MAX_BREAK_PCT := 95
const COMMANDER_MORALE := 2
const TERRAIN := {
	"plains": {"defense": 0, "attack": 0},
	"forest": {"defense": 2, "attack": 0},
	"hills": {"defense": 1, "attack": 1},
}
const FORT_DEFENSE := 2
## M3c (§4.1): the walls part in a storm and the cover part in a sally or breach battle, from FortData.
const WALLS := "walls"
const COVER := "cover"
const WALLS_DEFENSE_PER_STEP := FortData.WALLS_DEFENSE_PER_STEP
const WALL_STEP := FortData.WALL_STEP
const COVER_DEFENSE := FortData.COVER_DEFENSE
const SHIELD_WALL_DEFENSE := 2
const CHARGE_DAMAGE := 4
const CHARGE_DAMAGE_FOREST := 3
const INSPIRE_MORALE := 2
const BERSERK_ATTACK := 3
const FURY_MORALE := 2
const FURY_MAX := 3
const PACK_LEADER_ATTACK := 1
## M4-3 (§4.9): the transformations' traits. Iron Hide and Rooted are breakpoint values (a flat damage
## step, and exactly one damage step of defense); Lifedrinker's divisor is a tuning knob (1-3, §10.3).
const IRON_HIDE_DAMAGE := 1
const ROOTED_DEFENSE := 4
const LIFEDRINK_DIVISOR := 2
## Red Harvest (§4.10): gold for every enemy fighter lost in a battle its side wins.
const RED_HARVEST_GOLD := 1
## CW-2 (#253, design/CANDLEWAKE.md §2.1, §4.1): Wick and the Candlewake's traits. A regular of an army that keeps a flame
## fights with FLAME's attack part: its army's flame - 1 (WickRules.battle_flame, the flame the battle phase began with; -1 at
## flame 0, +2 at flame 3). Pall takes PALL_HIT off an attack's hit chance before the chance is held between MIN_HIT and
## MAX_HIT. A Gleaner that landed a hit in a round and still stands heals SIPHON_HEAL at its end (a curse that stops healing
## stops it). A Hundred-Wick that falls flares: FLARE_DAMAGE sure damage (no roll; no defense or Iron Hide turns it) to up to
## FLARE_TARGETS standing enemy fighters of the front rank, the healthiest first. While a Lamplighter stands, every enemy
## fighter that has fallen in the battle (not summoned creatures) gives its side TOLL_MORALE morale, at most TOLL_MAX.
## Each is a "why" factor with its codex entry (the four traits' "trait_*", and "wick"); a battle with one of them or a
## flame on the field logs "wick": true and its additions (BattleLog), so every other battle logs as before.
const FLAME := "flame"
const PALL_HIT := 5
const SIPHON_HEAL := 1
const FLARE_DAMAGE := 2
const FLARE_TARGETS := 6
const TOLL_MORALE := 1
const TOLL_MAX := 3
## M5-7: the Mage trait (MagicData's), the prefix of a spell's part and "why" factor ("spell_sunlance", also its
## RulesCodex entry), Dawn Blessing's morale part, and the Blood Moon's "why" factor (the hp it healed back).
const MAGE := MagicData.MAGE_TRAIT
const SPELL_PREFIX := "spell_"
const BLESSING := "spell_dawn_blessing"
const MOON := "spell_blood_moon"

const SHIELD_WALL := "Shield Wall"
const VOLLEY := "Volley"
const CHARGE := "Charge"
const INSPIRE := "Inspire"
const BERSERK := "Berserk"
const SKIRMISH := "Skirmish"
const FURY := "Fury"
const PACK_LEADER := "Pack Leader"
const WINGS := "Wings"
const IRON_HIDE := "Iron Hide"
const ROOTED := "Rooted"
const LIFEDRINKER := "Lifedrinker"
const PALL := "Pall"  # CW-2: the Candlewake's
const SIPHON := "Siphon"
const FLARE := "Flare"
const TOLL := "Toll"
const WICK_TRAITS := [PALL, SIPHON, FLARE, TOLL]
## M3c: the siege engines' trait (FortData.ENGINES). Engines never fight, so no fighter carries it in battle;
## its text is here so every trait the game shows has its rules' own words (codex trait_siege_engine).
const SIEGE_ENGINE := FortData.ENGINE_TRAIT
## The traits of the transformations' new units (M4-3): a battle with one of them on the field is a path
## battle even without a game state.
const PATH_TRAITS := [WINGS, IRON_HIDE, ROOTED, LIFEDRINKER]
## Lifedrinker's share in words, by LIFEDRINK_DIVISOR (its tuning range and one either side).
const SHARE_WORDS := {1: "all", 2: "half", 3: "a third", 4: "a quarter"}
## What each trait does, built from the constants the rules use: a unit type's trait description
## (data/factions.gd trait_desc, shown in unit tooltips) and the first sentence of its codex entry.
const TRAIT_TEXT := {
	SHIELD_WALL: "Gets +%d defense while any other fighter on its side still stands." % SHIELD_WALL_DEFENSE,
	VOLLEY: "Shoots from the second rank, behind its side's units without Volley. While at least as many of those stand as units with Volley, they shield it: only enemies with Skirmish can attack it. Commanders stand further back, so they don't count.",
	CHARGE: "Deals +%d damage with every hit in the first round of a battle" % CHARGE_DAMAGE + " (+%d in a forest)." % CHARGE_DAMAGE_FOREST,
	INSPIRE: "While it stands, its side gets +%d morale" % INSPIRE_MORALE + ", on top of the +%d any standing commander gives." % COMMANDER_MORALE,
	BERSERK: "Gets +%d attack while below full hit points." % BERSERK_ATTACK,
	SKIRMISH: "Can attack the enemy's second rank (its units with Volley) as well as its front rank, even while the front rank shields them.",
	FURY: "While it stands, every enemy side gets -%d morale" % FURY_MORALE + " (at most -%d in all, however many roar)." % FURY_MAX,
	PACK_LEADER: "While it stands, every unit on its side gets +%d attack." % PACK_LEADER_ATTACK,
	WINGS: "Can attack any enemy fighter, whatever its rank, even commanders behind the line. While an enemy commander stands, it attacks a commander.",
	IRON_HIDE: "Every hit on it deals %d less damage" % IRON_HIDE_DAMAGE + ", but always at least %d." % MIN_DAMAGE,
	ROOTED: "Gets +%d defense in a battle in a forest province, whoever holds it. Not in a battle on a border." % ROOTED_DEFENSE,
	LIFEDRINKER: "At the end of each round, if it still stands, it heals %s of the damage its hits dealt that round (rounded up), up to its maximum." % SHARE_WORDS[LIFEDRINK_DIVISOR],
	PALL: "Harder to hit: every attack on it has %d%% less hit chance" % PALL_HIT + ", taken off before the chance is held between %d%%" % MIN_HIT
		+ " and %d%%." % MAX_HIT,
	SIPHON: "At the end of each round in which it landed a hit, if it still stands, it heals %d hit point, up to its maximum. A curse that stops healing stops it." % SIPHON_HEAL,
	FLARE: "When it falls it flares: %d damage" % FLARE_DAMAGE + " to each of up to %d standing enemy fighters in the front rank, the healthiest first." % FLARE_TARGETS
		+ " The fire is sure: no roll, and no defense or Iron Hide turns it.",
	TOLL: "While it stands, every enemy fighter that has fallen in the battle gives its side +%d morale" % TOLL_MORALE
		+ ", up to +%d (summoned creatures don't count)." % TOLL_MAX,
	SIEGE_ENGINE: FortData.ENGINE_RULE,
	MAGE: "Casts a spell from your spellbook every round instead of attacking, and attacks only when no spell is useful. Fights from the second rank: safe while your front rank is at least as big. Fangthrowers and Seraphs can always reach it.",
}
## One-line summaries of TRAIT_TEXT, for odds reasons and compact lists.
## CW-4: Siphon's and Flare's words with a path's number (Red Gleaners heal 2; Brighter Flare burns 3): the trait's own text,
## TRAIT_TEXT, with `n` in place of SIPHON_HEAL or FLARE_DAMAGE. AscensionRules writes them on the roster when a node changes them.
static func siphon_words(n: int) -> String:
	return String(TRAIT_TEXT[SIPHON]).replace("heals %d hit point," % SIPHON_HEAL, "heals %d hit point%s," % [n, "" if n == 1 else "s"])


static func flare_words(n: int) -> String:
	return String(TRAIT_TEXT[FLARE]).replace("flares: %d damage" % FLARE_DAMAGE, "flares: %d damage" % n)


const TRAIT_SHORT := {
	SHIELD_WALL: "+%d defense in a group" % SHIELD_WALL_DEFENSE,
	VOLLEY: "shoots from the second rank",
	CHARGE: "+%d damage in the first round" % CHARGE_DAMAGE,
	INSPIRE: "+%d morale" % INSPIRE_MORALE,
	BERSERK: "+%d attack when wounded" % BERSERK_ATTACK,
	SKIRMISH: "reaches the second rank",
	FURY: "-%d enemy morale" % FURY_MORALE,
	PACK_LEADER: "+%d attack to every unit" % PACK_LEADER_ATTACK,
	WINGS: "flies over the line to strike commanders",
	IRON_HIDE: "-%d damage from every hit" % IRON_HIDE_DAMAGE,
	ROOTED: "+%d defense in a forest" % ROOTED_DEFENSE,
	LIFEDRINKER: "heals %s of the damage it deals" % SHARE_WORDS[LIFEDRINK_DIVISOR],
	PALL: "-%d%% to be hit" % PALL_HIT,
	SIPHON: "heals %d after a round it hits" % SIPHON_HEAL,
	FLARE: "%d damage" % FLARE_DAMAGE + " to %d front-rank enemies as it falls" % FLARE_TARGETS,
	TOLL: "+%d morale for each fallen enemy" % TOLL_MORALE + ", up to +%d" % TOLL_MAX,
	SIEGE_ENGINE: "+%d siege damage while besieging; never fights" % FortData.SIEGE.engine,
	MAGE: "casts a spell every round, from the second rank",
}

## M2-2: the ruler's morale part and its "why" factor id, Dread's morale part, and the prefix of every
## mandate's part and factor id ("mandate_royal_armories"), which is also its RulesCodex entry.
const RULER := "ruler"
const DREAD := "Dread"
const MANDATE_PREFIX := "mandate_"
const RULER_RANK_WORDS := {"front": "in the front rank", "second": "from the second rank"}
## M4-3: the prefix of a path part's key and "why" factor id ("path_crown_living_iron", AscensionRules'
## PART_PREFIX), Dread Lands' morale part and its factor id (also its RulesCodex entry and PathData's
## province rule id), and Red Harvest's mandate id.
const PATH_PREFIX := "path_"
const DREAD_LANDS := "Dread Lands"
const DREAD_LANDS_ID := "dread_lands"
const RED_HARVEST := "red_harvest"
## Path stat words for the "why", and the verb that says what a part of that stat did.
const PATH_STAT_WORDS := {"attack": "attack", "defense": "defense", "hp": "maximum hp"}
const PATH_STAT_VERBS := {"attack": "was worth about %d damage", "defense": "turned aside about %d damage",
	"hp": "absorbed about %d damage"}

## Odds estimate: the real battle is fought ODDS_SAMPLES times on fixed internal seeds.
const ODDS_SAMPLES := 24
const ODDS_SEED := 4040
const LIKELY_WIN := 0.65
const LIKELY_LOSS := 0.35

## Below this many hp of impact a factor is too small to be called a reason.
const MIN_IMPACT := 0.5


# --- entry points ---------------------------------------------------------------------------------

## The issue's shape: `attacker` against `defender` (each an Army or an Array of one faction's
## Armies) in `province`. The defender gets the terrain. Pure: the armies are not changed.
## Returns {"result": {"winner", "strengths", "tie_break", "roll", "why", "report"}, "report": {...}},
## plus "log" (BattleLog schema) when `record` is true.
## `state` is optional and only used for player-facing names.
static func resolve(attacker, defender, province: Province, rng: SeededRNG, state: GameState = null, record := false) -> Dictionary:
	var att: Array = attacker if attacker is Array else [attacker]
	var dfn: Array = defender if defender is Array else [defender]
	var dfid: String = dfn[0].owner
	var sides := [{"faction": att[0].owner, "armies": att}, {"faction": dfid, "armies": dfn}]
	sides.sort_custom(func(a, b): return a.faction < b.faction)
	var ctx := {"kind": "province", "defender": dfid, "province": province,
		"province_ids": [province.id] if province else [], "state": state}
	var r := fight(sides, ctx, rng, record)
	var out := {"result": r.result, "report": r.result.report}
	if record:
		out["log"] = r.log
	return out


## BattleResolver interface, called by TurnResolver for every battle (any number of sides).
## Applies the winner's losses to its armies (dead units removed, wounds kept, a fallen ruler leaves
## its army, Feast of Victory heals); the TurnResolver removes the losing armies. The battle dictionary
## may carry "state" for names, terrain, rulers and mandates. With Feast of Victory, the report gains
## "feast": {"faction", "name", "fighters", "healed"} (TurnResolver's aftermath line says so).
## M3-1: the result also carries "log", the battle's event log (BattleLog), with a "feast" event when
## Feast of Victory healed anyone. The battle dictionary may carry "max_events" (tests: a lowered cap).
func resolve_battle(battle: Dictionary, rng: SeededRNG) -> Dictionary:
	var state = battle.get("state")
	var kind: String = battle.get("kind", "province")
	var pids: Array = battle.get("provinces", [])
	var province: Province = null
	if state is GameState and kind == "province" and not pids.is_empty():
		province = state.find_province(pids[0])
	var ctx := {"kind": kind, "defender": battle.get("defender", ""), "province": province,
		"province_ids": pids, "state": state if state is GameState else null}
	if battle.has("siege"):
		ctx["siege"] = battle.siege  # M3c: a battle at a fort in a game with sieges
	if battle.has("max_events"):
		ctx["max_events"] = battle.max_events
	var r := fight(battle.sides, ctx, rng, true)
	var closed := _close_bleeds(r.sides, r.result.winner)  # M5-7: bleeding closes when the battle ends
	if not closed.is_empty():
		var ci := -1
		var back := 0
		for i in r.sides.size():
			if r.sides[i].faction == r.result.winner:
				ci = i
		for row in closed:
			back += int(row[2]) - int(row[1])
		r.result.report["bleed_closed"] = {"faction": r.result.winner, "name": String(r.sides[ci].name), "fighters": closed.size(), "healed": back}
		r.result.report.lines.append("Bleeding closed: %s %s got back the %d hp %s bled casting Bloodbolt." % [_poss(String(r.sides[ci].name)),
			"caster" if closed.size() == 1 else "%d casters" % closed.size(), back, "it" if closed.size() == 1 else "they"])
		_log_push(r.log, int(ctx.get("max_events", BattleLog.MAX_EVENTS)), {"t": "bleed_closed", "side": ci, "closed": closed})
	var healed := _feast_healed(r.sides, r.result.winner)  # read before _apply_losses heals them
	var feast := _apply_losses(r.sides, r.result.winner)
	if not feast.is_empty():
		r.result.report["feast"] = feast
		var wi := -1
		for i in r.sides.size():
			if r.sides[i].faction == r.result.winner:
				wi = i
		_log_push(r.log, int(ctx.get("max_events", BattleLog.MAX_EVENTS)), {"t": "feast", "side": wi, "healed": healed})
	var harvest := red_harvest(r.sides, r.result.winner)
	if not harvest.is_empty():
		# M4-3: Red Harvest's gold (TurnResolver pays it and says so in the aftermath).
		r.result.report["red_harvest"] = harvest
		_log_push(r.log, int(ctx.get("max_events", BattleLog.MAX_EVENTS)), {"t": "harvest", "side": int(harvest.side),
			"fighters": int(harvest.fighters), "gold": int(harvest.gold)})
	r.result["log"] = r.log
	return r.result


## Red Harvest (M4-3, §4.10): when the winning side has it, {"faction", "name", "side" (its index),
## "fighters" (every fighter of the losing sides: fallen, or destroyed with their armies), "gold"
## (RED_HARVEST_GOLD for each)}; {} otherwise or when no enemy fighter was lost.
static func red_harvest(sides: Array, winner: String) -> Dictionary:
	var wi := -1
	var lost := 0
	for i in sides.size():
		if sides[i].faction == winner:
			wi = i
		else:
			lost += int(sides[i].count_start)
	if wi < 0 or int(sides[wi].get("red_harvest", 0)) <= 0 or lost == 0:
		return {}
	return {"faction": winner, "name": String(sides[wi].name), "side": wi, "fighters": lost,
		"gold": lost * int(sides[wi].red_harvest)}


## Pre-battle odds for `perspective` (a faction id among the sides): the real battle fought on
## ODDS_SAMPLES fixed seeds. Armies are not changed. Returns {"win_rate", "wins", "samples",
## "label": "likely win" | "close" | "likely loss", "reasons": [plain-language strings], "text"}.
static func estimate(sides: Array, ctx: Dictionary, perspective: String) -> Dictionary:
	var wins := 0
	var scores := {}  # factor key -> summed impact from the perspective's point of view
	var briefs := {}
	var spells := {}  # M5-7: faction -> {spell: true}, every spell its casters cast in the test battles
	for i in ODDS_SAMPLES:
		var r := fight(sides, ctx, SeededRNG.new(odds_seed(i)))
		if r.result.winner == perspective:
			wins += 1
		add_odds_factors(r.result.report, perspective, scores, briefs)
		for sr in r.result.report.sides:
			for sid in sr.get("spells_cast", {}):
				if not spells.has(sr.faction):
					spells[sr.faction] = {}
				spells[sr.faction][sid] = true
	return odds_summary(wins, scores, briefs, perspective, ctx.get("state"), spells)


## Adds one test battle's "why" factors to `scores` (factor key -> summed impact from `perspective`'s point of view,
## luck left out) and `briefs` (factor key -> its seed-free phrase). estimate() and the fort odds (M3c,
## Forecast.storm_odds and the others, which fight a chain of battles on each seed) both use it.
static func add_odds_factors(report: Dictionary, perspective: String, scores: Dictionary, briefs: Dictionary) -> void:
	for f in report.all_factors:
		if f.id == "luck":
			continue
		var key: String = "%s|%s" % [f.id, f.faction]
		var signed: float = f.impact if f.faction == perspective else -f.impact
		scores[key] = scores.get(key, 0.0) + signed
		briefs[key] = f.brief


## The odds of `perspective` from `wins` of ODDS_SAMPLES test battles and the summed factors (add_odds_factors):
## {"win_rate", "wins", "samples", "label", "reasons", "text"}. M5-7: `spells` ({faction: {spell: true}}, the spells
## cast in the test battles) adds a sentence naming them and "spells" ({faction: [ids in spellbook order]}).
static func odds_summary(wins: int, scores: Dictionary, briefs: Dictionary, perspective: String, state, spells: Dictionary = {}) -> Dictionary:
	var rate := float(wins) / ODDS_SAMPLES
	var label := "close"
	if rate >= LIKELY_WIN:
		label = "likely win"
	elif rate <= LIKELY_LOSS:
		label = "likely loss"
	var keys: Array = scores.keys()
	keys.sort()
	var pos := keys.filter(func(k): return scores[k] > MIN_IMPACT)
	var neg := keys.filter(func(k): return scores[k] < -MIN_IMPACT)
	pos.sort_custom(func(a, b): return scores[a] > scores[b])
	neg.sort_custom(func(a, b): return scores[a] < scores[b])
	var reasons := []
	if label == "likely win":
		for k in pos.slice(0, 2):
			reasons.append(briefs[k])
	elif label == "likely loss":
		for k in neg.slice(0, 2):
			reasons.append(briefs[k])
	else:
		if not pos.is_empty():
			reasons.append(briefs[pos[0]])
		if not neg.is_empty():
			reasons.append(briefs[neg[0]])
	var name := _faction_name(perspective, state)
	var text := "%s: %s won %d of %d test battles fought with these armies (%d%%)." % [
		_cap(label), name, wins, ODDS_SAMPLES, roundi(rate * 100)]
	if not reasons.is_empty():
		text += " Main reasons: %s." % "; ".join(reasons)
	var cast := {}
	if not spells.is_empty():
		var fids: Array = spells.keys()
		fids.sort()
		var parts := []
		for fid in fids:
			var ids := []
			for sid in MagicData.SPELLBOOK.get(fid, []):
				if spells[fid].has(sid):
					ids.append(String(sid))
			cast[fid] = ids
			parts.append("%s: %s" % [_faction_name(String(fid), state), " and ".join(ids.map(func(x): return MagicRules.spell_name(String(x))))])
		text += " Spells cast in the test battles (they always land): %s." % "; ".join(parts)
	text += " Each real battle still has its own rolls."
	var out := {"win_rate": rate, "wins": wins, "samples": ODDS_SAMPLES, "label": label, "reasons": reasons, "text": text}
	if not cast.is_empty():
		out["spells"] = cast
	return out


## The fixed seed of odds sample `i` (exposed so tests can check estimate() against resolve()).
static func odds_seed(i: int) -> int:
	return ODDS_SEED + i * 7919


## `base` is the attacker's base hit chance: BASE_HIT, or Drilled Ranks' (RulerRules.battle_effects).
static func hit_chance(attack: int, defense: int, base: int = BASE_HIT) -> int:
	return clampi(base + HIT_PER_POINT * (attack - defense), MIN_HIT, MAX_HIT)


static func damage(attack: int, defense: int) -> int:
	return maxi(MIN_DAMAGE, ceili(attack * 0.5) - floori(defense * 0.25))


static func break_pct(morale: int) -> int:
	return clampi(BREAK_BASE_PCT + morale * MORALE_PCT_PER_POINT, MIN_BREAK_PCT, MAX_BREAK_PCT)


static func codex_id_for_trait(trait_id: String) -> String:
	return "trait_" + trait_id.to_lower().replace(" ", "_")


# --- the battle -----------------------------------------------------------------------------------

## Fights one battle without changing any army. `sides` = [{"faction", "armies"}] sorted by faction
## id; `ctx` = {"kind", "defender", "province" (Province or null), "province_ids", "state"}, and
## optionally "max_events" (the log's cap, BattleLog.MAX_EVENTS by default; tests lower it).
## Returns {"result": BattleResolver result with "report", "sides": internal side records}, plus "log"
## (the battle event log, BattleLog's schema) when `record` is true. Recording is passive (M3-1).
static func fight(sides_in: Array, ctx: Dictionary, rng: SeededRNG, record := false) -> Dictionary:
	var state = ctx.get("state")
	var kind: String = ctx.get("kind", "province")
	var province = ctx.get("province")
	var terrain := ""
	var fort := false
	if province != null and kind == "province":
		terrain = province.terrain
		fort = province.has_fort
	var defender_fid: String = ctx.get("defender", "")
	var sides := _build_sides(sides_in, defender_fid, state, kind)
	if kind == "province" and province != null and state is GameState:
		for s in sides:
			s.dread_lands = dread_lands_value(state, s.faction, province)  # M4-3: the Blood Pact's own land
	var env := {"terrain": terrain, "fort": fort, "kind": kind}
	if ctx.has("siege"):
		env["siege"] = ctx.siege  # M3c: walls and cover replace the flat fort bonus (_defense)
		env["place_name"] = province.name if province != null else "the fort"  # for the walls and cover factors
	if MagicRules.has_magic(state):
		_setup_magic(sides, ctx, env, state)  # M5-7: casters, spellbooks and the enchantments in play
	# M3-1: the recorder, {"log", "cap"}, or null when not recording.
	var rec = null
	if record:
		rec = {"log": _log_header(sides, sides_in, ctx, env, rng, state), "cap": int(ctx.get("max_events", BattleLog.MAX_EVENTS))}

	var rounds := []
	var round_no := 0
	while round_no < ROUND_CAP and _standing(sides).size() > 1:
		round_no += 1
		rounds.append(_fight_round(sides, round_no, env, rng, rec))
	var impact_before := _impacts(sides) if rec != null else []
	_count_extra_hp(sides)

	var standing := _standing(sides)
	var winner_idx := -1
	var tie_break := "none"
	var roll := 0
	var tied := 0
	var end := ""
	if standing.size() == 1:
		winner_idx = standing[0]
		end = "rout"
		for s in sides:
			if s.destroyed and s.out_round == round_no:
				end = "destroyed"
		for s in sides:
			if s.routed and s.out_round == round_no:
				end = "rout"
	else:
		var pool := []
		if standing.is_empty():
			end = "mutual"
			for i in sides.size():
				if sides[i].out_round == round_no:
					pool.append(i)
		else:
			end = "round_cap"
			pool = standing
		var pick := _pick_best(sides, pool, defender_fid, end == "round_cap", rng)
		winner_idx = pick.index
		tie_break = pick.tie_break
		roll = pick.roll
		tied = int(pick.get("tied", 0))
		if end == "mutual":
			sides[winner_idx].routed = false
			sides[winner_idx].held_field = true

	var report := _report(sides, ctx, env, rounds, winner_idx, end, state)
	var strengths := {}
	for s in sides:
		strengths[s.faction] = s.strength
	var result := {"winner": sides[winner_idx].faction, "strengths": strengths, "tie_break": tie_break,
		"roll": roll, "why": report.why, "report": report}
	if rec == null:
		return {"result": result, "sides": sides}
	_log_push(rec.log, rec.cap, {"t": "end", "rounds": round_no, "winner": winner_idx, "how": end, "tie_break": tie_break,
		"roll": roll, "tied": tied, "impact": _impact_deltas(sides, impact_before)})
	rec.log.rng["after"] = Serial.int64_to_str(rng.get_state())
	return {"result": result, "sides": sides, "log": rec.log}


static func _build_sides(sides_in: Array, defender_fid: String, state, kind: String = "province") -> Array:
	var sides := []
	for i in sides_in.size():
		var sd: Dictionary = sides_in[i]
		var armies: Array = sd.armies.duplicate()
		armies.sort_custom(func(a, b): return a.id < b.id)
		# M2-2: what the side's mandates do in battle (nothing in a game without rulers).
		var effects := RulerRules.battle_effects(state if state is GameState else null, sd.faction)
		var mods_by_type := {}  # unit type id -> its part mods, from RulerRules.unit_stats
		var fighters := []
		var labels := []
		var morale_sum := 0
		var morale_by_key := {}  # M4-3: path morale part key -> the morale it adds over the side's units
		var type_names := {}  # unit type id -> the name its units fight under (a transformation renames)
		var regulars := 0
		var strength := 0
		var line_attacks := []
		var line_cost := 0
		var ruler_info := {}
		for a in armies:
			labels.append(_army_label(a, state))
			for u in a.units:
				var mods := _unit_mods(mods_by_type, sd.faction, u.type, state)
				var max_hp: int = RulerRules.unit_max_hp(state, u) if state is GameState else u.type.hp
				var fighter := _fighter(i, a, u, false, false, mods, max_hp)
				if a.flame >= 0 and u.type.trait_id != MAGE and not u.type.summoned:
					fighter["flame"] = WickRules.battle_flame(state if state is GameState else null, a)  # CW-2: regulars only
				if state is GameState and u.type.trait_id == FLARE and WickRules.flare_damage(state, sd.faction) != FLARE_DAMAGE:
					fighter["flare_damage"] = WickRules.flare_damage(state, sd.faction)  # CW-4: Brighter Flare
				if state is GameState and u.type.trait_id == SIPHON and WickRules.siphon_heal(state, sd.faction, u.type.id) != SIPHON_HEAL:
					fighter["siphon_heal"] = WickRules.siphon_heal(state, sd.faction, u.type.id)  # CW-4: Red Gleaners
				fighters.append(fighter)
				morale_sum += u.type.morale + _mods_total(mods.morale)
				for m in mods.morale:
					morale_by_key[m.key] = int(morale_by_key.get(m.key, 0)) + int(m.value)
				type_names[u.type.id] = u.type.name
				regulars += 1
				line_attacks.append(u.type.attack + _mods_total(mods.attack))
				line_cost += u.type.cost
			if a.commander:
				fighters.append(_fighter(i, a, a.commander, true))
			if a.ruler:
				# The ruler fights beside its side's armies: not a unit, so no unit mods (§1.3).
				var rf := _fighter(i, a, a.ruler, false, true)
				fighters.append(rf)
				ruler_info = _ruler_info(state, sd.faction, rf, kind)
			strength += StubBattleResolver.army_strength(a)
		if regulars == 0:
			# A commander fighting alone is compared with its faction's roster instead.
			for ut in _roster_types(sd.faction, state):
				line_attacks.append(ut.attack + _mods_total(_unit_mods(mods_by_type, sd.faction, ut, state).attack))
				line_cost += ut.cost
		var base_morale := 0
		var base_morale_parts := {}  # M4-3: what each path morale part added to the average (0s left out)
		if regulars > 0:
			base_morale = floori(float(morale_sum) / regulars)
			for k in morale_by_key:
				var without := floori(float(morale_sum - int(morale_by_key[k])) / regulars)
				if base_morale != without:
					base_morale_parts[k] = base_morale - without
		else:
			for f in fighters:
				base_morale = maxi(base_morale, f.type.morale)
		var hp := 0
		var power_attack := 0
		for f in fighters:
			hp += f.hp
			power_attack += f.type.attack
		sides.append({"faction": sd.faction, "name": _faction_name(sd.faction, state), "fighters": fighters,
			"armies": labels, "roster": _roster(armies), "is_defender": sd.faction == defender_fid, "base_morale": base_morale,
			"hp_start": hp, "count_start": fighters.size(), "regulars": regulars, "strength": strength, "power": hp * power_attack,
			"line_attacks": line_attacks, "line_cost": float(line_cost) / maxi(1, line_attacks.size()),
			"routed": false, "destroyed": false, "held_field": false, "out_round": 0, "rout_info": {},
			"attacks": 0, "hits": 0, "chance_sum": 0, "chance_min": 100, "chance_max": 0,
			"dealt": 0, "expected": 0.0, "luck_by": {}, "impact": {}, "triggers": {}, "trait_units": {},
			"volley_expected": 0.0, "cmd_expected": 0.0, "skirmish_reach": 0.0, "skirmish_targets": {}, "lost": [], "morale_log": [],
			# M2-2: the side's mandates and ruler.
			"mandates": effects.mandates, "base_hit": int(effects.base_hit), "base_hit_key": String(effects.base_hit_key),
			"frenzy": int(effects.wounded_attack), "frenzy_key": String(effects.wounded_attack_key),
			"iron": bool(effects.iron_discipline), "feast": bool(effects.feast_of_victory), "iron_held": [],
			"ruler_info": ruler_info, "dread": int(ruler_info.get("dread", 0)), "ruler_expected": 0.0, "ruler_dealt": 0,
			"ruler_fell": 0,
			# M4-3: paths. "paths": the game has them (the report then carries "people"); the rest only
			# ever change in a battle with path parts, a path trait or Dread Lands.
			"paths": state is GameState and AscensionRules.has_paths(state), "people": people_of(state, sd.faction),
			"base_morale_parts": base_morale_parts, "type_names": type_names, "dread_lands": 0,
			"red_harvest": RED_HARVEST_GOLD if state is GameState and RulerRules.has_mandate(state, sd.faction, RED_HARVEST) else 0,
			"wings_reach": 0.0, "wings_targets": {}, "wings_kills": [], "iron_hits": 0, "healed": 0,
			# M5-7: magic. Only _setup_magic, in a game with magic, ever changes these.
			"magic": false, "casters": [], "spellbook": [], "enchant_log": [], "blessed": 0, "blessed_fighters": 0, "moon": false,
			"cursed": false, "bled": 0, "moon_healed": 0, "spells_cast": {}, "spell_stats": {}, "cast_battle": {}, "type_rank": {}})
		for f in fighters:
			if not f.trait.is_empty():
				sides[i].trait_units[f.trait] = f.name
		if fighters.any(func(f): return f.has("flame") or WICK_TRAITS.has(f.trait)):
			# CW-2: what Wick and the Candlewake's traits did, kept only on a side that has them.
			sides[i].merge({"wick": true, "siphoned": 0, "flares": 0, "flared": 0, "toll": 0})
	return sides


## The people `fid` has become in `state` (M4-3, §9.6): {"id" (the side of the fork), "name"} once its
## transformation is researched, otherwise {} (also without paths or a state).
static func people_of(state, fid: String) -> Dictionary:
	if not (state is GameState) or not AscensionRules.has_paths(state):
		return {}
	var nid := AscensionRules.transformation(state, fid)
	if nid.is_empty():
		return {}
	var bid := String(AscensionRules.node_data(nid).get("branch", ""))
	return {"id": bid, "name": AscensionRules.branch_name(bid)}


## Dread Lands (§4.7): the morale every enemy side loses in a province battle in `province` when `fid`
## owns it and has researched a transformation with that province rule (the Blood Pact); 0 otherwise. The
## battles phase comes before captures, so the owner now is the owner at the start of the turn.
static func dread_lands_value(state, fid: String, province: Province) -> int:
	if not (state is GameState) or province == null or province.owner != fid or not AscensionRules.has_paths(state):
		return 0
	var rule := AscensionRules.province_rule(state, fid)
	return int(rule.get("value", 0)) if String(rule.get("id", "")) == DREAD_LANDS_ID else 0


## The attack, defense, maximum hp and morale parts the side's mandates and path give a regular unit of
## type `ut`, from RulerRules.unit_stats (Royal Armories, Veteran Levies; M4-3: every researched node's
## parts, Drillyard, Arbalests, Living Iron, ...): {"attack": [{"key", "value"}], "defense": [...], "hp":
## [...], "morale": [...]}, keyed by each part's key ("mandate_<id>", "path_<node>"). Empty for commanders,
## rulers, types outside the faction's roster and games with neither mandates nor paths. Cached per type.
static func _unit_mods(cache: Dictionary, fid: String, ut: UnitType, state) -> Dictionary:
	if cache.has(ut.id):
		return cache[ut.id]
	var out := {"attack": [], "defense": [], "hp": [], "morale": []}
	if state is GameState and not ut.is_commander and not ut.is_ruler and not ut.summoned \
			and (not RulerRules.mandates(state, fid).is_empty() or AscensionRules.has_paths(state)):  # M5-5: never summoned creatures
		var us := RulerRules.unit_stats(state, fid, ut.id)
		if us.get("ok", false):
			for stat in out:
				for m in us.mods.get(stat, []):
					var key := String(m.get("key", ""))
					if key.is_empty():
						key = MANDATE_PREFIX + String(m.get("mandate", ""))
					out[stat].append({"key": key, "value": int(m.value)})
	cache[ut.id] = out
	return out


static func _mods_total(mods: Array) -> int:
	var total := 0
	for m in mods:
		total += int(m.value)
	return total


## The ruler on a side, for the report and the "why": {"id", "name", "rank" ("front" | "second"),
## "kept_power", "max_hp", "attack", "defense", "hp_start", and "dread" (its Dread in this battle: the
## morale every enemy side loses while it stands, only in a province battle; 0 otherwise)}.
static func _ruler_info(state, fid: String, rf: Dictionary, kind: String) -> Dictionary:
	var ut: UnitType = rf.type
	var f: Faction = state.find_faction(fid) if state is GameState else null
	var dread := 0
	if kind == "province" and state is GameState:
		dread = RulerRules.dread_value(state, fid)
	return {"id": ut.id, "name": ut.name, "rank": RulerRules.battle_rank(ut.id), "kept_power": f.kept_power if f != null else 0,
		"max_hp": int(rf.max), "attack": ut.attack, "defense": ut.defense, "hp_start": int(rf.hp), "dread": dread}


## Who fought on a side, for the report: unit types with counts in first-seen order (armies by id,
## units in army order), then the commanders. Ids for the viewer, names and text for players:
##   {"units": [{"id", "name", "count"}], "commanders": [{"id", "name"}],
##    "text": "Spearmen (2), Crossbowmen, led by Knight Captain" | "Warchief alone"}
## With a ruler on the side (M2-2), also "ruler": {"id", "name"}, and the text ends ", with King
## Corvane I" ("King Corvane I alone" when the ruler fought by itself).
static func _roster(armies: Array) -> Dictionary:
	var units := []
	var index := {}
	var commanders := []
	var ruler := {}
	for a in armies:
		for u in a.units:
			if not index.has(u.type.id):
				index[u.type.id] = units.size()
				units.append({"id": u.type.id, "name": u.type.name, "count": 0})
			units[index[u.type.id]].count += 1
		if a.commander:
			commanders.append({"id": a.commander.type.id, "name": a.commander.type.name})
		if a.ruler:
			ruler = {"id": a.ruler.type.id, "name": a.ruler.type.name}
	var parts := []
	for e in units:
		parts.append(e.name if e.count == 1 else "%s (%d)" % [e.name, e.count])
	var leaders := {}
	var leader_order := []
	for c in commanders:
		if not leaders.has(c.name):
			leaders[c.name] = 0
			leader_order.append(c.name)
		leaders[c.name] += 1
	var led := []
	for n in leader_order:
		led.append(n if leaders[n] == 1 else "%s (%d)" % [n, leaders[n]])
	var text := ", ".join(parts)
	if not led.is_empty():
		text = ("%s alone" % " and ".join(led)) if parts.is_empty() else "%s, led by %s" % [text, " and ".join(led)]
	if ruler.is_empty():
		return {"units": units, "commanders": commanders, "text": text}
	if text.is_empty():
		text = "%s alone" % ruler.name
	else:
		text = "%s, with %s" % [text.trim_suffix(" alone"), ruler.name] if not text.ends_with(" alone") \
			else "%s and %s" % [text.trim_suffix(" alone"), ruler.name]
	return {"units": units, "commanders": commanders, "ruler": ruler, "text": text}


## The unit types `fid` can recruit (not its commander), from the game state when there is one.
static func _roster_types(fid: String, state) -> Array:
	if state is GameState:
		var f: Faction = state.find_faction(fid)
		if f != null:
			return f.unit_types
	for f in FactionData.rows():
		if f.id == fid:
			return f.unit_types.map(func(u): return UnitType.from_dict(u))
	return []


## One fighter. Tier 0 is the front rank, 1 the second rank (Volley units, and a ruler whose battle rank
## is "second"), 2 the commanders behind everyone. `mods` are its mandate parts (_unit_mods) and
## `max_hp` its maximum hp with them (RulerRules.unit_max_hp; the type's hp when not given).
static func _fighter(side_idx: int, army: Army, unit: Unit, is_cmd: bool, is_ruler: bool = false, mods: Dictionary = {},
		max_hp: int = -1) -> Dictionary:
	var t: String = unit.type.trait_id
	var tier := 0
	if is_cmd:
		tier = 2
	elif is_ruler:
		tier = 1 if RulerRules.battle_rank(unit.type.id) == "second" else 0
	elif t == VOLLEY or t == MAGE:
		tier = 1  # M5-7: mages fight from the second rank too
	return {"side": side_idx, "army": army.id, "army_ref": army, "unit": unit, "type": unit.type, "name": unit.type.name,
		"trait": t, "cmd": is_cmd, "tier": tier, "hp": unit.current_hp, "hp0": unit.current_hp,
		"max": max_hp if max_hp > 0 else unit.type.hp, "alive": unit.current_hp > 0, "pending": 0,
		"ruler": is_ruler, "mods": mods if not mods.is_empty() else {"attack": [], "defense": [], "hp": [], "morale": []}, "taken": 0}


static func _standing(sides: Array) -> Array:
	var out := []
	for i in sides.size():
		if not sides[i].routed and not sides[i].destroyed:
			out.append(i)
	return out


## One round. `rec` is fight()'s recorder ({"log", "cap"}) when the battle is being recorded (M3-1),
## otherwise null; recording only reads what the round computes.
static func _fight_round(sides: Array, round_no: int, env: Dictionary, rng: SeededRNG, rec = null) -> Dictionary:
	var standing := _standing(sides)
	var dealt := {}
	var hits := {}
	var attacks := {}
	var charge := {}
	var berserk := {}
	for si in standing:
		dealt[si] = 0
		hits[si] = 0
		attacks[si] = 0
	# M3-1 recording: who hit whom, expected damage per side, impact at the round's start, and each side's
	# reachable tiers (no fighter falls before the round ends, so they hold for every attack of the round).
	var hit_by := {}
	var expected_by := {}
	var impact_before := []
	var reach := {}
	if rec != null:
		impact_before = _impacts(sides)
		reach = _log_round(rec, sides, standing, round_no)
	# M5-7: the cast step, in a game with magic. Casters that cast don't attack this round.
	var magic: bool = env.get("magic", false)
	var spells := {"casting": {}, "lines": []}
	if magic:
		spells = _cast_step(sides, standing, round_no, env, rec, hit_by)
	for si in standing:
		var side: Dictionary = sides[si]
		for f in side.fighters:
			if not f.alive:
				continue
			if magic and spells.casting.has(int(f.ord)):
				continue
			var pool := _targets(sides, si, standing, f)
			if pool.is_empty():
				continue
			var pick := rng.randi_range(0, pool.size() - 1)
			var t: Dictionary = pool[pick]
			var tside: Dictionary = sides[t.side]
			var atk := _attack(f, side, env)
			var dfn := _defense(t, tside, f, env)
			var bonus := 0
			if f.trait == CHARGE and round_no == 1:
				bonus = CHARGE_DAMAGE_FOREST if env.terrain == "forest" else CHARGE_DAMAGE
			var base: int = side.base_hit  # BASE_HIT, or Drilled Ranks'
			var pall := -PALL_HIT if t.trait == PALL else 0  # CW-2: inside the clamp, so never folded into `base` (Drilled Ranks')
			var chance := hit_chance(atk.value, dfn.value, base + pall)
			var hide := _hide(t, damage(atk.value, dfn.value) + bonus)  # M4-3: Iron Hide (0 for anyone else)
			var dmg := damage(atk.value, dfn.value) + bonus - hide
			var expected := chance / 100.0 * dmg
			# What each modifier was worth on this attack, in expected damage.
			for p in atk.parts:
				var a2: int = atk.value - atk.parts[p]
				var gain: float = expected - hit_chance(a2, dfn.value, base + pall) / 100.0 * _dealt(t, damage(a2, dfn.value) + bonus)
				if magic and String(p).begins_with(SPELL_PREFIX):
					_add_impact(sides[int(f.hexed_by.get(p, si))], p, -gain)  # M5-7: a hex's worth is its caster's side's
				else:
					_add_impact(side, p, gain)
			for p in dfn.parts:
				var d2: int = dfn.value - dfn.parts[p]
				var saved: float = hit_chance(atk.value, d2, base + pall) / 100.0 * _dealt(t, damage(atk.value, d2) + bonus) - expected
				_add_impact(tside, p, saved)
			if pall != 0:
				# CW-2: Pall's worth is the hit chance it took off this attack, in expected damage, like a defense part.
				_add_impact(tside, PALL, (hit_chance(atk.value, dfn.value, base) - chance) / 100.0 * dmg)
				tside.triggers[PALL] = tside.triggers.get(PALL, 0) + 1
			if hide > 0:
				# Iron Hide: the damage it turned aside, in expected damage like every other defense part.
				_add_impact(tside, IRON_HIDE, chance / 100.0 * hide)
				tside.triggers[IRON_HIDE] = tside.triggers.get(IRON_HIDE, 0) + 1
			if base != BASE_HIT:
				# Drilled Ranks: what the side's higher base hit chance added to this attack.
				var plain_chance := hit_chance(atk.value, dfn.value, BASE_HIT + pall)
				if plain_chance != chance:
					_add_impact(side, side.base_hit_key, (chance - plain_chance) / 100.0 * dmg)
					side.triggers[side.base_hit_key] = side.triggers.get(side.base_hit_key, 0) + 1
			if f.ruler:
				# The ruler costs no gold, so all the damage it deals is what it added (§7.4).
				side.ruler_expected += expected
				_add_impact(side, RULER, expected)
			if f.trait == SKIRMISH and t.tier == 1 and _screened(tside, t):
				# Only Skirmish reached this target past its front rank. Counted in full: every hit on a
				# shielded second-rank fighter takes away about as much of the damage it would have gone on
				# to deal from safety (Volley's own factor counts half of what it dealt while shielded).
				side.skirmish_reach += expected
				side.skirmish_targets[t.name] = int(side.skirmish_targets.get(t.name, 0)) + 1
				_add_impact(side, SKIRMISH, expected)
			if f.trait == WINGS and _screened(tside, t):
				# M4-3: only Wings reached this target, a commander behind its line or a shielded second rank,
				# counted in full like Skirmish's reach (§9.6).
				side.wings_reach += expected
				side.wings_targets[t.name] = int(side.wings_targets.get(t.name, 0)) + 1
				side.triggers[WINGS] = side.triggers.get(WINGS, 0) + 1
				_add_impact(side, WINGS, expected)
			if bonus > 0:
				# Charge's worth is what it added to this hit (all of it, unless Iron Hide was already at the floor).
				_add_impact(side, CHARGE, chance / 100.0 * (dmg - _dealt(t, damage(atk.value, dfn.value))))
			if f.cmd:
				side.cmd_expected += expected
				_add_impact(side, "commander", expected - _line_baseline(side, f, dfn.value, atk.parts.get("terrain", 0)))
			if f.tier == 1 and not f.ruler and f.trait == VOLLEY and _screened(side, f):  # M5-7: a mage that attacks is not Volley
				side.volley_expected += expected
				_add_impact(side, VOLLEY, expected * 0.5)
			if atk.parts.has(BERSERK) and not berserk.has(si):
				berserk[si] = f.name
			var roll := rng.randi_range(1, 100)
			var hit := roll <= chance
			if rec != null:
				_log_attack(rec, round_no, f, t, reach, pool.size(), pick, chance, roll, hit, dmg, bonus, base, atk, dfn, expected, hide, pall)
				expected_by[si] = float(expected_by.get(si, 0.0)) + expected
				if hit:
					if not hit_by.has(t.id):
						hit_by[t.id] = []
					hit_by[t.id].append(f.id)
			side.attacks += 1
			side.chance_sum += chance
			side.chance_min = mini(side.chance_min, chance)
			side.chance_max = maxi(side.chance_max, chance)
			side.expected += expected
			# Luck of this attack in damage (what it did minus what an average roll would), by kind of
			# attack, so the report can say where a side's luck came from.
			var luck_key: String = f.name + ("|charge" if bonus > 0 else "")
			side.luck_by[luck_key] = side.luck_by.get(luck_key, 0.0) + (dmg if hit else 0) - expected
			attacks[si] += 1
			if hit:
				side.hits += 1
				side.dealt += dmg
				hits[si] += 1
				dealt[si] += dmg
				t.pending += dmg
				if bonus > 0:
					charge[si] = charge.get(si, 0) + bonus
				if f.ruler:
					side.ruler_dealt += dmg
				# M4-3: what Lifedrinker drinks back at the end of the round, Iron Hide's hits, and a
				# commander Wings struck (so the "why" can say it fell to the Seraphs).
				if f.trait == LIFEDRINKER or side.moon:  # M5-7: under the Blood Moon every fighter of its side drinks
					f["drink"] = int(f.get("drink", 0)) + dmg
				if f.trait == SIPHON:
					f["siphon"] = int(f.get("siphon", 0)) + dmg  # CW-2: it landed a hit this round (_siphon heals it at the end)
				if hide > 0:
					tside.iron_hits += 1
				if f.trait == WINGS and t.cmd:
					t["winged"] = round_no
					t["winged_by"] = si

	var highlights: Array = spells.lines.duplicate()  # M5-7: what was cast this round comes first
	for si in standing:
		if charge.has(si):
			highlights.append("%s %s charged home for %d extra damage." % [_poss(sides[si].name), sides[si].trait_units[CHARGE], charge[si]])
		if berserk.has(si):
			highlights.append("%s wounded %s went berserk (+%d attack)." % [_poss(sides[si].name), berserk[si], BERSERK_ATTACK])
	var fell := []  # CW-2: the fighters that fell this round (Toll counts them), and the Hundred-Wicks among them (they flare)
	var flaring := []
	for si in standing:
		for f in sides[si].fighters:
			var bleed := int(f.get("bleed", 0))  # M5-7: Bloodbolt's bleeding lands with the wounds
			if f.alive and (f.pending > 0 or bleed > 0):
				var before: int = f.hp
				f.hp = maxi(0, f.hp - f.pending)
				f.taken += before - f.hp
				var bled := 0
				if bleed > 0 and f.hp > 0:
					# Never below 1, and not lost to the enemy: the morale check leaves it out (side.bled).
					bled = mini(bleed, f.hp - 1)
					f.hp -= bled
					f["bled"] = int(f.get("bled", 0)) + bled
					sides[si].bled += bled
				if rec != null and f.hp < before:
					var by: Array = hit_by.get(f.id, []).duplicate()
					var wound := {"t": "wound", "n": round_no, "f": f.id, "from": before, "to": f.hp, "by": by}
					if bled > 0:
						by.append(f.id)
						wound["bled"] = bled
					_log_push(rec.log, rec.cap, wound)
					if f.hp == 0:
						_log_push(rec.log, rec.cap, {"t": "death", "n": round_no, "f": f.id, "by": hit_by.get(f.id, []).duplicate()})
				if f.hp == 0:
					f.alive = false
					sides[si].lost.append(f.name)
					fell.append(f)
					if f.trait == FLARE:
						flaring.append(f)
					for sid in f.get("bolted", {}):
						# M5-7: a bolt helped fell it this round (the spell's "why" names it).
						sides[int(f.bolted[sid])].spell_stats[sid].kills.append({"name": _target_ref(f), "round": round_no})
					highlights.append("%s %s fell." % [_poss(sides[si].name), _bare(f.name)])
					if f.ruler:
						sides[si].ruler_fell = round_no
					if f.cmd and int(f.get("winged", 0)) == round_no:
						# M4-3: Wings struck this commander in the round it fell.
						sides[int(f.winged_by)].wings_kills.append({"name": f.name, "trait": f.trait, "round": round_no,
							"side": sides[si].name})
			f.pending = 0
			if bleed > 0:
				f.bleed = 0
	if not flaring.is_empty():
		_flare(sides, flaring, round_no, highlights, rec, fell)  # CW-2: after the round's deaths, before any heal
	_drink(sides, standing, round_no, highlights, rec)
	_siphon(sides, standing, round_no, highlights, rec)
	_toll(sides, fell)

	# Morale is checked for every side before any of them leaves, so the order of sides never matters.
	var checks := {}
	for si in standing:
		var side: Dictionary = sides[si]
		var hp_now := _hp(side)
		if hp_now == 0:
			continue
		var m := _morale(sides, si, standing)
		# M5-7: hp a side's own casters bled are not lost to the enemy, so the check leaves them out (0 without magic).
		var lost_pct := roundi(100.0 * (side.hp_start - hp_now - side.bled) / maxi(1, side.hp_start))
		var entry := {"round": round_no, "morale": m.value, "parts": m.parts, "break_pct": break_pct(m.value),
			"lost_pct": lost_pct, "hp": hp_now}
		if side.magic:
			entry["bled"] = side.bled
		side.morale_log.append(entry)
		checks[si] = entry
	var outcomes := {}  # M3-1 recording: side index -> {"result", "held_by" (fighter id), "iron_last_round"}
	for si in standing:
		var side: Dictionary = sides[si]
		if _hp(side) == 0:
			side.destroyed = true
			side.out_round = round_no
			highlights.append("%s had no one left standing." % side.name)
		elif checks[si].lost_pct >= checks[si].break_pct:
			# Iron Discipline holds through every round but the last (M2-8, #36): at the end of round
			# ROUND_CAP the usual check applies, so a line it holds past its break point can't win by
			# stalling the attackers until the round cap.
			var holder := _iron_holder(side) if round_no < ROUND_CAP else ""
			var iron_last_round: bool = side.iron and holder.is_empty() and round_no >= ROUND_CAP and not _iron_holder(side).is_empty()
			if iron_last_round:
				highlights.append("%s holds a line only until the last round." % RulerRules.mandate_name(RulerRules.IRON_DISCIPLINE))
			if not holder.is_empty():
				# Iron Discipline: the side would break, but one of its commanders still stands (§2.3).
				checks[si]["held_by"] = holder
				side.iron_held.append(checks[si])
				if side.iron_held.size() == 1:
					highlights.append("%s would have broken after losing %d%% of its strength (morale %d holds only to %d%%), but %s held it while its %s stood." % [
						side.name, checks[si].lost_pct, checks[si].morale, checks[si].break_pct,
						RulerRules.mandate_name(RulerRules.IRON_DISCIPLINE), holder])
				if rec != null:
					outcomes[si] = {"result": "held", "held_by": _iron_holder_id(side), "iron_last_round": false}
				continue
			side.routed = true
			side.out_round = round_no
			side.rout_info = checks[si]
			highlights.append("%s broke and fled after losing %d%% of its strength (morale %d holds only to %d%%)." % [
				side.name, checks[si].lost_pct, checks[si].morale, checks[si].break_pct])
			if rec != null:
				outcomes[si] = {"result": "breaks", "held_by": -1, "iron_last_round": iron_last_round}
		elif rec != null:
			outcomes[si] = {"result": "holds", "held_by": -1, "iron_last_round": false}
	if rec != null:
		_log_round_end(rec, sides, standing, round_no, checks, outcomes, attacks, hits, dealt, expected_by, impact_before)

	var parts := []
	for si in standing:
		parts.append("%s dealt %d damage (%d of %d hits)" % [sides[si].name, dealt[si], hits[si], attacks[si]])
	var hp_after := {}
	for s in sides:
		hp_after[s.faction] = _hp(s)
	return {"round": round_no, "dealt": dealt.duplicate(), "highlights": highlights, "hp": hp_after,
		"line": "Round %d: %s.%s" % [round_no, ", ".join(parts), "" if highlights.is_empty() else " " + " ".join(highlights)]}


## Standing enemies fighter `attacker` of side `si` can reach. On each enemy side: its front rank
## (units without Volley), plus its second rank (Volley units) when the front rank no longer shields it
## (fewer front-rank units than second-rank ones stand) or when `attacker` has Skirmish; the second rank
## alone once the front rank has fallen; its commanders once no unit stands. Fighters keep their side's
## order, so a seed always picks the same target.
static func _targets(sides: Array, si: int, standing: Array, attacker: Dictionary = {}) -> Array:
	if attacker.get("trait", "") == WINGS:
		return _wings_targets(sides, si, standing)
	var reach: bool = attacker.get("trait", "") == SKIRMISH
	var pool := []
	for oi in standing:
		if oi == si:
			continue
		var tiers := _reachable_tiers(_tier_counts(sides[oi]), reach)
		for f in sides[oi].fighters:
			if f.alive and tiers.has(f.tier):
				pool.append(f)
	return pool


## The target rule's ranks (M3-1: factored out of _targets with no change in behaviour, so the battle
## log's "reach" is the rule itself): the tiers of a side with `counts` standing fighters per tier
## ([front, second, back]) that an enemy can attack. The front rank; the second rank too when it
## outnumbers the front rank or the attacker has Skirmish (`skirmish`); the second rank alone once the
## front rank has fallen; the commanders once no unit stands.
static func _reachable_tiers(counts: Array, skirmish: bool) -> Array:
	if counts[0] == 0:
		return [1] if counts[1] > 0 else [2]
	if counts[1] > 0 and (skirmish or counts[1] > counts[0]):
		return [0, 1]
	return [0]


## Wings (M4-3, §4.9): every standing enemy commander while any stands, otherwise every standing enemy
## fighter, whatever its rank. Rulers are not commanders, so they aren't preferred (but can be reached).
## Fighters keep their side's order, so a seed always picks the same target.
static func _wings_targets(sides: Array, si: int, standing: Array) -> Array:
	var commanders := []
	var anyone := []
	for oi in standing:
		if oi == si:
			continue
		for f in sides[oi].fighters:
			if f.alive:
				anyone.append(f)
				if f.cmd:
					commanders.append(f)
	return commanders if not commanders.is_empty() else anyone


## The ranks Wings can reach on a side with `counts` standing fighters per tier (the battle log's
## "wings_tiers"): its commanders while one stands, otherwise every rank with someone in it. When any enemy
## side has a commander standing, Wings goes only for commanders (_wings_targets).
static func _wings_tiers(counts: Array) -> Array:
	if counts[2] > 0:
		return [2]
	var out := []
	for tier in 3:
		if counts[tier] > 0:
			out.append(tier)
	return out


## Standing fighters of `side` per tier: [front, second, back].
static func _tier_counts(side: Dictionary) -> Array:
	var counts := [0, 0, 0]
	for f in side.fighters:
		if f.alive:
			counts[f.tier] += 1
	return counts


## What the same gold as commander `f` would have dealt with this attack if it had been spent on its
## side's ordinary units, on average (the yardstick for the commander's "why" factor): the commander's
## cost in average units of its side (or of its faction's roster when it fights alone), each attacking
## a target with `defense` (with the side's terrain attack bonus `terrain_attack`), times the share of
## those units that would still be standing, taken as the share of the side's units still standing
## (or, for a lone commander, its own share of hit points left).
static func _line_baseline(side: Dictionary, f: Dictionary, defense: int, terrain_attack: int) -> float:
	var attacks: Array = side.line_attacks
	if attacks.is_empty() or side.line_cost <= 0.0:
		return 0.0
	var per_unit := 0.0
	for a in attacks:
		per_unit += hit_chance(a + terrain_attack, defense, side.base_hit) / 100.0 * damage(a + terrain_attack, defense)
	per_unit /= attacks.size()
	var standing := 0.0
	if side.regulars > 0:
		var alive := 0
		for o in side.fighters:
			if o.alive and not o.cmd:
				alive += 1
		standing = float(alive) / side.regulars
	else:
		standing = float(f.hp) / maxi(1, f.hp0)
	return per_unit * f.type.cost / side.line_cost * standing


## True when enemies without Skirmish can't reach fighter `f` because the ranks in front of it shield
## it: a second-rank (Volley) fighter while at least as many front-rank units as second-rank ones stand,
## a commander while any unit stands.
static func _screened(side: Dictionary, f: Dictionary) -> bool:
	var counts := [0, 0, 0]
	for o in side.fighters:
		if o.alive:
			counts[o.tier] += 1
	if f.tier == 1:
		return counts[0] > 0 and counts[0] >= counts[1]
	if f.tier == 2:
		return counts[0] + counts[1] > 0
	return false


static func _attack(f: Dictionary, side: Dictionary, env: Dictionary) -> Dictionary:
	var parts := {}
	if side.is_defender:
		var ta: int = TERRAIN.get(env.terrain, {}).get("attack", 0)
		if ta > 0:
			parts["terrain"] = ta
	if f.trait == BERSERK and f.hp < f.max:
		parts[BERSERK] = BERSERK_ATTACK
	var frenzy: int = side.get("frenzy", 0)
	if frenzy > 0 and f.hp < f.max:
		parts[side.frenzy_key] = frenzy  # Blood Frenzy: every fighter, the ruler included
	if not f.cmd and not f.get("ruler", false):
		for o in side.fighters:
			if o.alive and o.cmd and o.trait == PACK_LEADER:
				parts[PACK_LEADER] = PACK_LEADER_ATTACK
	if f.has("flame") and int(f.flame) != 1:
		parts[FLAME] = int(f.flame) - 1  # CW-2 (§2.1): a regular fights at its army's flame - 1
	for m in f.get("mods", {}).get("attack", []):
		parts[m.key] = int(parts.get(m.key, 0)) + int(m.value)  # Royal Armories
	var value: int = f.type.attack
	for p in parts:
		value += parts[p]
		side.triggers[p] = side.triggers.get(p, 0) + 1
	for p in f.get("spell_atk", {}):
		parts[p] = int(f.spell_atk[p])  # M5-7: a hex on it this round (Briar Snare, Sunburst)
		value += parts[p]
	return {"value": value, "parts": parts}


static func _defense(t: Dictionary, tside: Dictionary, _attacker: Dictionary, env: Dictionary) -> Dictionary:
	var parts := {}
	var siege: Dictionary = env.get("siege", {})
	if tside.is_defender:
		var td: int = TERRAIN.get(env.terrain, {}).get("defense", 0)
		if td > 0:
			parts["terrain"] = td
		if env.fort and siege.is_empty():
			parts["fort"] = FORT_DEFENSE
	if not siege.is_empty() and Array(siege.get("from_inside", [])).has(t.army):
		# M3c (§4.1): the stormed garrison stands behind its walls; a sally or the breach keeps its cover.
		if String(siege.get("kind", "")) == SiegeRules.STORM:
			if int(siege.get("walls_defense", 0)) > 0:
				parts[WALLS] = int(siege.walls_defense)
		elif int(siege.get("cover_defense", 0)) > 0:
			parts[COVER] = int(siege.cover_defense)
	if t.trait == SHIELD_WALL:
		for o in tside.fighters:
			if o.alive and o != t:
				parts[SHIELD_WALL] = SHIELD_WALL_DEFENSE
				break
	if t.trait == ROOTED and env.get("kind", "province") == "province" and env.terrain == "forest":
		parts[ROOTED] = ROOTED_DEFENSE  # M4-3: whoever holds the forest, never on a border
	for m in t.get("mods", {}).get("defense", []):
		parts[m.key] = int(parts.get(m.key, 0)) + int(m.value)  # Royal Armories
	var value: int = t.type.defense
	for p in parts:
		value += parts[p]
		tside.triggers[p] = tside.triggers.get(p, 0) + 1
	for p in t.get("spell_def", {}):
		parts[p] = int(t.spell_def[p])  # M5-7: a shield on it this round (Shield of Law)
		value += parts[p]
	return {"value": value, "parts": parts}


static func _morale(sides: Array, si: int, standing: Array) -> Dictionary:
	var side: Dictionary = sides[si]
	var parts := {}
	for f in side.fighters:
		if f.alive and f.cmd:
			parts["commander"] = COMMANDER_MORALE
			if f.trait == INSPIRE:
				parts[INSPIRE] = INSPIRE_MORALE
	var bears := 0
	for oi in standing:
		if oi == si:
			continue
		for f in sides[oi].fighters:
			if f.alive and f.trait == FURY:
				bears += 1
	if bears > 0:
		parts[FURY] = -mini(FURY_MAX, FURY_MORALE * bears)
	# M2-2: the side's own ruler while it stands, and an enemy avatar's Dread while it stands.
	for f in side.fighters:
		if f.alive and f.get("ruler", false):
			parts[RULER] = RulerData.RULER_MORALE
	var dread := 0
	for oi in standing:
		if oi != si and int(sides[oi].get("dread", 0)) > 0 and _ruler_standing(sides[oi]):
			dread += int(sides[oi].dread)
	if dread > 0:
		parts[DREAD] = -dread
	# M4-3: Dread Lands, for the whole battle, on every side but the Blood Pact's own (§4.7). M4-6: it doesn't
	# stack with Dread, so it takes only what goes beyond the Dread this side suffers now.
	var lands := 0
	for oi in sides.size():
		if oi != si:
			lands = maxi(lands, int(sides[oi].get("dread_lands", 0)))
	lands = maxi(0, lands - dread)
	if lands > 0:
		parts[DREAD_LANDS] = -lands
	if int(side.get("blessed", 0)) > 0:
		parts[BLESSING] = int(side.blessed)  # M5-7: Dawn Blessing, counted at the battle's start
	if int(side.get("toll", 0)) > 0 and side.fighters.any(func(f): return f.alive and f.trait == TOLL):
		parts[TOLL] = int(side.toll)  # CW-2: the enemies fallen so far, while a Lamplighter stands
	var value: int = side.base_morale
	for p in parts:
		value += parts[p]
	return {"value": value, "parts": parts}


static func _ruler_standing(side: Dictionary) -> bool:
	for f in side.fighters:
		if f.get("ruler", false) and f.alive:
			return true
	return false


## Iron Discipline (§2.3): the name of a commander of `side` still standing when the side has the
## mandate, so it does not break this round; "" otherwise (rulers don't count).
static func _iron_holder(side: Dictionary) -> String:
	if not side.iron:
		return ""
	for f in side.fighters:
		if f.alive and f.cmd:
			return f.name
	return ""


## The log id of the commander _iron_holder names (the same fighter), or -1. Recording only (M3-1).
static func _iron_holder_id(side: Dictionary) -> int:
	if not side.iron:
		return -1
	for f in side.fighters:
		if f.alive and f.cmd:
			return int(f.id)
	return -1


## Iron Hide (M4-3, §4.9): how much less a hit of `raw` damage (Charge included) deals to target `t`:
## IRON_HIDE_DAMAGE for a fighter with Iron Hide, never taking the hit below MIN_DAMAGE; 0 for anyone else.
static func _hide(t: Dictionary, raw: int) -> int:
	if t.trait != IRON_HIDE:
		return 0
	return clampi(raw - MIN_DAMAGE, 0, IRON_HIDE_DAMAGE)


## The damage a hit of `raw` damage deals to target `t`, after Iron Hide (`raw` for anyone without it).
static func _dealt(t: Dictionary, raw: int) -> int:
	return raw - _hide(t, raw)


## Lifedrinker (M4-3, §4.9), at the end of round `round_no`, after its damage has landed and before
## morale is checked: every fighter with it that still stands heals 1/LIFEDRINK_DIVISOR of the damage its
## hits dealt this round, rounded up, up to its maximum. One that fell this round heals nothing. Counts the
## hp it healed as its "why" worth, writes a heal event to the log and one highlight per side.
## M5-7: under the Blood Moon (side.moon) every standing fighter of the moon's side heals back a quarter of the damage
## its attacks dealt that round, rounded down (spell damage never counts), and a Lifedrinker the larger of its two
## shares, not both; none of them above its maximum - 1. A cursed side (side.cursed) heals back nothing.
static func _drink(sides: Array, standing: Array, round_no: int, highlights: Array, rec) -> void:
	var share := int(MagicData.SPELLS.blood_moon.get("share", 4))
	for si in standing:
		var side: Dictionary = sides[si]
		var healed := 0
		var who := ""
		var moon: bool = side.moon
		var moon_healed := 0
		for f in side.fighters:
			var drinker: bool = f.trait == LIFEDRINKER
			if not drinker and not moon:
				continue
			var drunk := int(f.get("drink", 0))
			f["drink"] = 0
			var top: int = f.max - 1 if moon else f.max
			if not f.alive or drunk <= 0 or f.hp >= top or side.cursed:
				continue
			var by_trait := ceili(float(drunk) / LIFEDRINK_DIVISOR) if drinker else 0
			var by_moon := floori(float(drunk) / share) if moon else 0
			var from_moon := by_moon > by_trait
			var heal := mini(by_moon if from_moon else by_trait, top - f.hp)
			if heal <= 0:
				continue
			var before: int = f.hp
			f.hp += heal
			var ev := {"t": "heal", "n": round_no, "f": f.id if rec != null else -1, "from": before, "to": f.hp, "dealt": drunk}
			if from_moon:
				moon_healed += heal
				ev["spell"] = "blood_moon"
			else:
				healed += heal
				who = f.name
				side.triggers[LIFEDRINKER] = side.triggers.get(LIFEDRINKER, 0) + 1
				ev["trait"] = LIFEDRINKER
			if rec != null:
				_log_push(rec.log, rec.cap, ev)
		if healed > 0:
			side.healed += healed
			_add_impact(side, LIFEDRINKER, float(healed))
			highlights.append("%s %s drank back %d hp." % [_poss(side.name), who, healed])
		if moon_healed > 0:
			side.moon_healed += moon_healed
			_add_impact(side, MOON, float(moon_healed))
			highlights.append("Under the Blood Moon, %s healed back %d hp." % [side.name, moon_healed])


## CW-2 (design/CANDLEWAKE.md §4.1, the round's order): every Hundred-Wick that fell this round flares, one at a time in (side,
## army, unit) order, which is the order of `flaring`: FLARE_DAMAGE sure damage (no roll; no defense or Iron Hide turns it) to
## each of up to FLARE_TARGETS standing enemy fighters in the front rank, the healthiest first, ties by side, then army and
## unit (their place in their side's list). A fighter an earlier Flare felled is gone before the next one picks. Every fighter
## the Flares fell is added to `fell`. Logs a "flare" event, then the wounds and deaths it dealt, by the flaring fighter.
static func _flare(sides: Array, flaring: Array, round_no: int, highlights: Array, rec, fell: Array) -> void:
	for fw in flaring:
		var si := int(fw.side)
		var targets := []
		for oi in sides.size():
			if oi == si:
				continue
			for i in sides[oi].fighters.size():
				var t: Dictionary = sides[oi].fighters[i]
				if t.alive and int(t.tier) == 0:
					targets.append([t, oi, i])
		if targets.is_empty():
			continue
		targets.sort_custom(func(a, b):
			if int(a[0].hp) != int(b[0].hp):
				return int(a[0].hp) > int(b[0].hp)
			if int(a[1]) != int(b[1]):
				return int(a[1]) < int(b[1])
			return int(a[2]) < int(b[2]))
		targets = targets.slice(0, FLARE_TARGETS)
		var side: Dictionary = sides[si]
		side.flares = int(side.get("flares", 0)) + 1
		side.triggers[FLARE] = side.triggers.get(FLARE, 0) + 1
		var burn := int(fw.get("flare_damage", FLARE_DAMAGE))  # CW-4: Brighter Flare burns hotter
		if rec != null:
			_log_push(rec.log, rec.cap, {"t": "flare", "n": round_no, "f": fw.id, "targets": targets.map(func(x): return x[0].id),
				"damage": burn})
		var dealt := 0
		var names := []
		for x in targets:
			var t: Dictionary = x[0]
			var before: int = t.hp
			t.hp = maxi(0, t.hp - burn)
			t.taken += before - t.hp
			dealt += before - t.hp
			names.append(t.name)
			if rec != null:
				_log_push(rec.log, rec.cap, {"t": "wound", "n": round_no, "f": t.id, "from": before, "to": t.hp, "by": [fw.id]})
				if t.hp == 0:
					_log_push(rec.log, rec.cap, {"t": "death", "n": round_no, "f": t.id, "by": [fw.id]})
			if t.hp == 0:
				t.alive = false
				sides[int(x[1])].lost.append(t.name)
				fell.append(t)
				highlights.append("%s %s fell." % [_poss(sides[int(x[1])].name), _bare(t.name)])
				if t.ruler:
					sides[int(x[1])].ruler_fell = round_no
		side.flared = int(side.get("flared", 0)) + dealt
		_add_impact(side, FLARE, float(dealt))
		highlights.append("%s %s flared as it fell: %d damage to %s." % [_poss(side.name), _bare(fw.name), burn, _count_names(names)])


## CW-2: the flame parts a side's regulars fought with, in words: "+1 attack (flame 2)", "+2 attack (flame 3) and +1 attack
## (flame 2)", hottest first.
static func _flame_words(s: Dictionary) -> String:
	var flames := {}
	for f in s.fighters:
		if f.has("flame") and int(f.flame) != 1:
			flames[int(f.flame)] = true
	var keys := flames.keys()
	keys.sort()
	keys.reverse()
	return RulerRules._and_list(keys.map(func(fl): return "%+d attack (flame %d)" % [int(fl) - 1, int(fl)]))


## "6 Spearmen", "4 Spearmen and 2 Knights": how many of each name, in the order they first appear.
static func _count_names(names: Array) -> String:
	var order := []
	var counts := {}
	for n in names:
		if not counts.has(n):
			order.append(n)
			counts[n] = 0
		counts[n] += 1
	var parts := []
	for n in order:
		parts.append("%d %s" % [counts[n], n] if int(counts[n]) > 1 or _plural(String(n)) else "1 " + String(n))
	return RulerRules._and_list(parts)


## CW-2: a Gleaner (Siphon) that landed a hit this round and still stands heals SIPHON_HEAL, up to its maximum; a curse that
## stops healing (Bloodrot: side.cursed) stops it. Logs a "heal" with trait Siphon.
static func _siphon(sides: Array, standing: Array, round_no: int, highlights: Array, rec) -> void:
	for si in standing:
		var side: Dictionary = sides[si]
		var healed := 0
		var who := ""
		for f in side.fighters:
			var drunk := int(f.get("siphon", 0))
			if drunk <= 0:
				continue
			f.erase("siphon")
			if not f.alive or f.hp >= f.max or side.cursed:
				continue
			var before: int = f.hp
			f.hp = mini(f.max, f.hp + int(f.get("siphon_heal", SIPHON_HEAL)))  # CW-4: Red Gleaners drink 2
			healed += f.hp - before
			who = f.name
			side.triggers[SIPHON] = side.triggers.get(SIPHON, 0) + 1
			if rec != null:
				_log_push(rec.log, rec.cap, {"t": "heal", "n": round_no, "f": f.id, "from": before, "to": f.hp, "dealt": drunk, "trait": SIPHON})
		if healed > 0:
			side.siphoned = int(side.get("siphoned", 0)) + healed
			_add_impact(side, SIPHON, float(healed))
			highlights.append("%s %s drank %d hp." % [_poss(side.name), who, healed])


## CW-2: Toll. Every side that keeps a toll (a side with Wick) counts the enemy fighters in `fell` (not summoned creatures),
## TOLL_MORALE each, up to TOLL_MAX for the battle; _morale adds it while one of its Lamplighters stands.
static func _toll(sides: Array, fell: Array) -> void:
	if fell.is_empty():
		return
	for si in sides.size():
		if not sides[si].has("toll") or not sides[si].trait_units.has(TOLL):
			continue
		var n := 0
		for f in fell:
			if int(f.side) != si and not f.type.summoned:
				n += 1
		sides[si].toll = mini(TOLL_MAX, int(sides[si].toll) + TOLL_MORALE * n)


## Veteran Levies (§7.4): the damage each regular unit's extra maximum hp absorbed (up to the bonus, for
## a unit that took that much), added to the side's impact under the mandate's key once the battle ends.
static func _count_extra_hp(sides: Array) -> void:
	for s in sides:
		var absorbed := {}
		var keys := []
		for f in s.fighters:
			var left: int = f.taken
			for m in f.mods.hp:
				if int(m.value) <= 0:
					continue  # a part lowering max hp (the Blood Pact's Bloodtuskers) absorbs nothing
				var a := mini(int(m.value), left)
				left -= a
				if not absorbed.has(m.key):
					absorbed[m.key] = 0
					keys.append(m.key)
				absorbed[m.key] += a
		for k in keys:
			if absorbed[k] > 0:
				_add_impact(s, k, float(absorbed[k]))


static func _hp(side: Dictionary) -> int:
	var total := 0
	for f in side.fighters:
		total += f.hp
	return total


static func _share(side: Dictionary) -> float:
	return float(_hp(side)) / maxi(1, side.hp_start)


static func _pick_best(sides: Array, pool: Array, defender_fid: String, defender_holds: bool, rng: SeededRNG) -> Dictionary:
	if defender_holds:
		for i in pool:
			if sides[i].faction == defender_fid:
				return {"index": i, "tie_break": "defender", "roll": 0}
	var best := -1.0
	var tied := []
	for i in pool:
		var sh := _share(sides[i])
		if sh > best + 0.000001:
			best = sh
			tied = [i]
		elif absf(sh - best) <= 0.000001:
			tied.append(i)
	if tied.size() == 1:
		return {"index": tied[0], "tie_break": "none", "roll": 0}
	for i in tied:
		if sides[i].faction == defender_fid:
			return {"index": i, "tie_break": "defender", "roll": 0}
	var r := rng.randi_range(0, tied.size() - 1)
	return {"index": tied[r], "tie_break": "roll", "roll": r, "tied": tied.size()}  # "tied": for the log (M3-1)


static func _add_impact(side: Dictionary, key: String, amount: float) -> void:
	side.impact[key] = side.impact.get(key, 0.0) + amount


## The winner's losses on its armies: fallen units and commanders leave them, a fallen ruler leaves its
## army (army.ruler = null; TurnResolver removes the empty army and records the death, M2-3's contract),
## and survivors keep their wounds, unless the side has Feast of Victory: then every fighter still
## standing heals to its maximum hp. Returns {"faction", "name", "fighters" (standing), "healed" (hp
## in all)} for a Feast that healed anyone, otherwise {}.
static func _apply_losses(sides: Array, winner: String) -> Dictionary:
	var feast := {}
	for s in sides:
		if s.faction != winner:
			continue
		var standing := 0
		var healed := 0
		for f in s.fighters:
			var army: Army = f.army_ref
			if f.alive:
				var hp: int = f.hp
				if s.feast and not s.cursed:  # M5-7: a cursed side heals from nothing
					standing += 1
					healed += maxi(0, f.max - hp)
					hp = maxi(hp, f.max)
				f.unit.current_hp = hp
			elif f.cmd:
				army.commander = null
			elif f.ruler:
				army.ruler = null
			else:
				army.units.erase(f.unit)
		if s.feast and not s.cursed and healed > 0:
			feast = {"faction": s.faction, "name": s.name, "fighters": standing, "healed": healed}
	return feast


# --- battle spells (M5-7, design/M5_MAGIC_FOG.md §5) ------------------------------------------------------

## A battle in a game with magic: each side's casters (each mage, and a ruler that casts in battle), each with the
## spells it can cast in its side's spellbook order (on spells only) and its mastery per school; the enchantments in
## play; and the roster order hexes and shields break ties with. Fighters get "ord", their place in fighter order
## (the log's id), for the cast order.
static func _setup_magic(sides: Array, ctx: Dictionary, env: Dictionary, state: GameState) -> void:
	env["magic"] = true
	var pid := ""
	var pids: Array = ctx.get("province_ids", [])
	if env.kind == "province" and not pids.is_empty():
		pid = String(pids[0])
	var k := 0
	for s in sides:
		for f in s.fighters:
			f["ord"] = k
			k += 1
	for s in sides:
		var fid: String = s.faction
		s.magic = true
		var book := MagicRules.spellbook(state, fid)
		var on := []
		for sid in book.order:
			if not book.off.has(sid):
				on.append(String(sid))
		s.spellbook = on
		var faction := state.find_faction(fid)
		var rm := MagicRules.ruler_magic(faction.ruler_type) if faction != null else {}
		var by_kind := {MagicRules.MAGE: MagicRules.battle_spells(state, fid, MagicRules.MAGE),
			MagicRules.RULER: MagicRules.battle_spells(state, fid, MagicRules.RULER)}
		for f in s.fighters:
			var kind := ""
			if f.ruler and rm.get("battle", false) == true:
				kind = MagicRules.RULER
			elif not f.cmd and not f.ruler and MagicRules.is_mage(f.type):
				kind = MagicRules.MAGE
			if kind.is_empty():
				continue
			var known: Array = by_kind[kind]
			var schools: Array = rm.get("schools", []) if kind == MagicRules.RULER else MagicRules.schools(fid)
			var mastery := {}
			var best := 0
			for school in schools:
				var v := int(MagicRules.mastery_bonus(state, fid, String(school), kind).value)
				mastery[String(school)] = v
				best = maxi(best, v)
			f["caster"] = {"kind": kind, "spells": on.filter(func(x): return known.has(x)), "mastery": mastery, "best": best}
			s.casters.append(f)
		var rank := 0
		if faction != null:
			for ut in faction.unit_types:
				s.type_rank[ut.id] = rank
				rank += 1
		for sid in MagicData.SUMMONS:
			if not s.type_rank.has(sid):
				s.type_rank[sid] = rank
				rank += 1
		_setup_enchantments(s, state, pid)


## The enchantments in play for side `s` in a battle in province `pid` ("" on a border, where nobody is cursed and
## no ward lies): Dawn Blessing's morale, counted once at the start (at least half the side's fighters blessed), the
## Blood Moon (outside a province a rival has warded) and a rival's curse (the side heals from nothing). Each goes
## into the log as {"id", "ritual", "effect"}.
static func _setup_enchantments(s: Dictionary, state: GameState, pid: String) -> void:
	var fid: String = s.faction
	var blessed := {}
	var blessings := []
	var moon := {}
	for e in state.enchantments:
		var ritual := String(e.ritual)
		if String(e.faction) != fid:
			continue
		if ritual == "dawn_blessing":
			var hit := false
			for f in s.fighters:
				if Array(e.armies).has(f.army):
					hit = true  # the side has an army under the blessing
					# ARM-1 (design/ARM1_SPLIT_MERGE.md §2.1): a fighter is blessed only if its army is listed AND it is not
					# marked outside this blessing (it joined the army after the casting): MagicRules.covers, per fighter
					if MagicRules.covers(e, String(f.army), f.unit):
						blessed[f.ord] = true
			if hit:
				blessings.append(e)
		elif ritual == "blood_moon":
			moon = e
	if not blessings.is_empty():
		var morale := int(MagicData.SPELLS.dawn_blessing.get("morale", 1))
		var count := blessed.size()
		var enough := count * 2 >= int(s.count_start)
		s.blessed = morale if enough else 0
		s.blessed_fighters = count
		for e in blessings:
			var effect := "+%d morale: %d of %d fighters blessed" % [morale, count, int(s.count_start)] if enough \
				else "no morale: only %d of %d fighters blessed, under half" % [count, int(s.count_start)]
			s.enchant_log.append({"id": String(e.id), "ritual": "dawn_blessing", "effect": effect})
	if not moon.is_empty():
		s.moon = _rival_ward(state, fid, pid).is_empty()
		s.enchant_log.append({"id": String(moon.id), "ritual": "blood_moon",
			"effect": "heals back %s of the damage its attacks deal" % MagicRules.moon_share_word() if s.moon else "outside the moon: a rival ward lies on this province"})
	if not MagicRules.can_heal(state, fid, pid):
		s.cursed = true
		for e in state.enchantments:
			if String(e.kind) == "curse" and String(e.province) == pid and String(e.faction) != fid:
				s.enchant_log.append({"id": String(e.id), "ritual": String(e.ritual), "effect": "cursed: it can't heal here"})


## A ward a faction other than `fid` holds on province `pid` (the Blood Moon stays out of it), or {}.
static func _rival_ward(state: GameState, fid: String, pid: String) -> Dictionary:
	if pid.is_empty():
		return {}
	for e in state.enchantments:
		if String(e.kind) == "ward" and String(e.province) == pid and String(e.faction) != fid:
			return e
	return {}


## Spell resistance (§5.2): what a bolt on a ruler of ability rank `rank` loses, rank / MagicData.RULER_RESIST rounded
## down (rank 1: 0; ranks 2-3: 1; rank 4: 2). The bolt still deals at least MIN_DAMAGE.
static func spell_resistance(rank: int) -> int:
	return floori(float(rank) / MagicData.RULER_RESIST)


## The cast step of round `round_no` (§5.1), after the round event and before the first attack. Clears last round's
## spell parts, then every standing caster casts: highest mastery bonus first, the ruler first among equals, then
## fighter order. Draws nothing. Returns {"casting": {fighter ord: true} (they don't attack this round), "lines": the
## round line's sentences}.
static func _cast_step(sides: Array, standing: Array, round_no: int, env: Dictionary, rec, hit_by: Dictionary) -> Dictionary:
	var out := {"casting": {}, "lines": []}
	var queue := []
	for si in standing:
		for f in sides[si].fighters:
			f["spell_atk"] = {}
			f["spell_def"] = {}
			f["hexed_by"] = {}
			f["bolted"] = {}
			f["bleed"] = 0
		for f in sides[si].casters:
			if f.alive:
				queue.append(f)
	if queue.is_empty():
		return out
	queue.sort_custom(func(a, b):
		if int(a.caster.best) != int(b.caster.best):
			return int(a.caster.best) > int(b.caster.best)
		if a.ruler != b.ruler:
			return a.ruler
		return int(a.ord) < int(b.ord))
	var done := {}  # side index -> {spell: true}: cast by someone on that side this round
	var summary := {}  # side index -> the plans cast, in order
	for c in queue:
		var si: int = c.side
		var cast: Dictionary = done.get(si, {})
		var skipped := []
		var pick := {}
		var again := {}
		for sid in c.caster.spells:
			var plan := _spell_plan(String(sid), c, sides, standing, round_no, env)
			if plan.has("skip"):
				skipped.append({"spell": String(sid), "reason": String(plan.skip)})
				continue
			if not cast.has(sid):
				pick = plan
				break
			if again.is_empty():
				again = plan
		if pick.is_empty() and not again.is_empty():
			pick = again
			pick["again"] = true  # every useful spell had been cast this round: from the top again
		if pick.is_empty():
			continue  # nothing useful: it attacks
		cast[pick.spell] = true
		done[si] = cast
		_apply_cast(pick, c, sides, round_no, rec, hit_by, skipped)
		out.casting[int(c.ord)] = true
		if not summary.has(si):
			summary[si] = []
		summary[si].append(pick)
	var keys: Array = summary.keys()
	keys.sort()
	for si in keys:
		out.lines.append(_cast_line(sides[si], summary[si]))
	return out


## What spell `sid` would do if caster `c` cast it now (§5.2), or {"skip": why it isn't useful, in plain words}:
## {"spell", "kind", "school", "bonus", "targets": [fighters, in fighter order], "value" (a bolt's damage with
## mastery), "damage" (after spell resistance), "resist", "self" (Bloodbolt's bleed), "part" ({"stat", "value"} for
## a hex or shield), "why" (the target rule, in plain words)}.
static func _spell_plan(sid: String, c: Dictionary, sides: Array, standing: Array, round_no: int, env: Dictionary) -> Dictionary:
	var sp := MagicRules.spell_data(sid)
	var si: int = c.side
	var side: Dictionary = sides[si]
	var school := String(sp.get("school", ""))
	var bonus := int(c.caster.mastery.get(school, 0))
	var name := String(sp.get("name", sid))
	var key := SPELL_PREFIX + sid
	var plan := {"spell": sid, "kind": String(sp.get("kind", "")), "school": school, "bonus": bonus, "targets": [], "value": 0,
		"damage": 0, "resist": 0, "self": 0, "part": {}, "why": ""}
	match String(sp.get("kind", "")):
		"bolt":
			var need := int(sp.get("min_caster_hp", 0))
			if int(c.hp) < need:
				return {"skip": "the caster has %d hp, and %s needs %d or more" % [int(c.hp), name, need]}
			var live := []
			for t in _targets(sides, si, standing, c):
				if t.hp - t.pending > 0:
					live.append(t)
			if live.is_empty():
				return {"skip": "every enemy in reach is already going to die from the damage aimed at it this round"}
			var units := live.filter(func(t): return not t.cmd and not t.ruler)
			var pool: Array = units if not units.is_empty() else live
			var best: Dictionary = pool[0]
			for t in pool:
				if _bolt_better(sid, t, best):
					best = t
			var value := int(MagicRules.spell_numbers(sid, bonus).value)
			var resist := 0
			if best.ruler:
				var rank := RulerRules.ability_rank(int(sides[best.side].ruler_info.get("kept_power", 0)))
				resist = clampi(spell_resistance(rank), 0, value - MIN_DAMAGE)
			plan.targets = [best]
			plan.value = value
			plan.resist = resist
			plan.damage = value - resist
			plan.self = int(sp.get("bleed", 0))
			var who := _target_ref(best)
			if units.is_empty():
				plan.why = "nothing but rulers and commanders was in reach, so %s" % who
			elif sid == "sunlance":
				plan.why = "%s %s the highest maximum hp in reach (%d)%s" % [_the(who), "have" if _plural(who) else "has", int(best.max),
					", the most hurt of those" if pool.filter(func(t): return t.max == best.max).size() > 1 else ""]
			else:
				plan.why = "%s %s the fewest hp left in reach (%d) and %s not yet going to die this round" % [_the(who),
					"have" if _plural(who) else "has", int(best.hp - best.pending), "are" if _plural(who) else "is"]
		"hex":
			if sp.has("round"):
				# Sunburst: every enemy fighter in the front rank, rulers included, once per side per battle.
				if round_no != int(sp.round):
					return {"skip": "%s works only in round %d" % [name, int(sp.round)]}
				if side.cast_battle.has(sid):
					return {"skip": "%s was already called down this battle" % name}
				for oi in standing:
					if oi == si:
						continue
					for t in sides[oi].fighters:
						if t.alive and t.tier == 0 and not t.spell_atk.has(key):
							plan.targets.append(t)
				if plan.targets.is_empty():
					return {"skip": "no enemy fighter stands in the front rank"}
				plan.why = "round %d: every enemy fighter in the front rank (%d)" % [round_no, plan.targets.size()]
			else:
				var forest: bool = env.kind == "province" and env.terrain == "forest"
				var count := int(MagicRules.spell_numbers(sid, bonus, forest).count)
				var group := _spell_group(sides, standing, si, true, key, env)
				if group.is_empty():
					return {"skip": "no enemy front-rank unit is left that it hasn't already hexed this round"}
				plan.targets = Array(group.free).slice(0, count)
				plan.why = "the %s were the most numerous enemy front-rank type with units not yet hexed by it this round (%d standing); it covers up to %d%s" % [
					_bare(String(group.name)), int(group.count), count, " in a forest" if forest else ""]
			plan.part = {"stat": String(sp.get("stat", "attack")), "value": int(sp.get("value", 0))}
		"shield":
			var count := int(MagicRules.spell_numbers(sid, bonus).count)
			var group := _spell_group(sides, standing, si, false, key, env)
			if group.is_empty():
				return {"skip": _shield_skip(side, env, key)}
			plan.targets = Array(group.free).slice(0, count)
			plan.why = "the %s were its most numerous front-rank type with units not yet shielded and without a terrain or fort bonus (%d standing); it covers up to %d" % [
				_bare(String(group.name)), int(group.count), count]
			plan.part = {"stat": String(sp.get("stat", "defense")), "value": int(sp.get("value", 0))}
		_:
			return {"skip": "%s is not a battle spell this build can cast" % name}
	return plan


## Whether fighter `t` is a better target than `best` for bolt `sid` (§5.2): Sunlance, the highest maximum hp and of
## those the fewest hp left; Bloodbolt (and any other bolt), the fewest hp left. Ties keep the earlier fighter.
static func _bolt_better(sid: String, t: Dictionary, best: Dictionary) -> bool:
	if sid == "sunlance" and int(t.max) != int(best.max):
		return int(t.max) > int(best.max)
	return int(t.hp - t.pending) < int(best.hp - best.pending)


## The unit type a hex (`enemy`) or a shield picks (§5.2): among the front-rank units ("units" are regular units and
## summoned creatures, never commanders or rulers) of the enemy sides, or of the caster's own side without a terrain or
## fort bonus, the type with the most standing that still has units without part `key` this round. Ties go in side
## order, then roster order, then summoned types in data order. {"side", "type", "name", "count", "free": [fighters
## without the part, in fighter order]}, or {} when no type has one.
static func _spell_group(sides: Array, standing: Array, si: int, enemy: bool, key: String, env: Dictionary) -> Dictionary:
	var groups := {}
	var order := []
	var stat := "spell_atk" if enemy else "spell_def"
	for oi in standing:
		if (oi == si) == enemy:
			continue
		for t in sides[oi].fighters:
			if not t.alive or t.tier != 0 or t.cmd or t.ruler:
				continue
			if not enemy and _ground(t, sides[oi], env) > 0:
				continue
			var gk := "%d|%s" % [oi, t.type.id]
			if not groups.has(gk):
				groups[gk] = {"side": oi, "type": t.type.id, "name": t.name, "count": 0, "free": []}
				order.append(gk)
			groups[gk].count += 1
			if not t[stat].has(key):
				groups[gk].free.append(t)
	var best := {}
	for gk in order:
		var g: Dictionary = groups[gk]
		if g.free.is_empty():
			continue
		if best.is_empty() or int(g.count) > int(best.count) or (int(g.count) == int(best.count) and int(g.side) == int(best.side)
				and int(sides[g.side].type_rank.get(g.type, 1 << 20)) < int(sides[best.side].type_rank.get(best.type, 1 << 20))):
			best = g
	return best


## The defense a fighter of `tside` already has from the ground (§5.2's "terrain or fort bonus"): the defender's
## terrain and flat fort bonus, and in a battle at a fort with sieges the walls or the cover of a fighter from inside.
## The same rule as _defense, read only.
static func _ground(t: Dictionary, tside: Dictionary, env: Dictionary) -> int:
	var siege: Dictionary = env.get("siege", {})
	var g := 0
	if tside.is_defender:
		g += int(TERRAIN.get(env.terrain, {}).get("defense", 0))
		if env.fort and siege.is_empty():
			g += FORT_DEFENSE
	if not siege.is_empty() and Array(siege.get("from_inside", [])).has(t.army):
		g += int(siege.get("walls_defense", 0)) if String(siege.get("kind", "")) == SiegeRules.STORM else int(siege.get("cover_defense", 0))
	return g


## Why Shield of Law has nothing to cover on `side`, in plain words: "the Spearmen have the fort's +2 defense, and
## Shield of Law never covers a unit with a terrain or fort bonus".
static func _shield_skip(side: Dictionary, env: Dictionary, key: String) -> String:
	var name := MagicRules.spell_name(key.trim_prefix(SPELL_PREFIX))
	var front := []
	for f in side.fighters:
		if f.alive and f.tier == 0 and not f.cmd and not f.ruler:
			front.append(f)
	if front.is_empty():
		return "none of its units stands in the front rank"
	for f in front:
		if _ground(f, side, env) > 0:
			var bits := []
			var siege: Dictionary = env.get("siege", {})
			if side.is_defender and int(TERRAIN.get(env.terrain, {}).get("defense", 0)) > 0:
				bits.append("the %s's +%d" % [env.terrain if env.terrain != "hills" else "hill", int(TERRAIN[env.terrain].defense)])
			if side.is_defender and env.fort and siege.is_empty():
				bits.append("the fort's +%d" % FORT_DEFENSE)
			if not siege.is_empty() and Array(siege.get("from_inside", [])).has(f.army):
				bits.append("the walls' +%d" % int(siege.get("walls_defense", 0)) if String(siege.get("kind", "")) == SiegeRules.STORM \
					else "the cover of the walls (+%d)" % int(siege.get("cover_defense", 0)))
			return "the %s %s %s defense, and %s never covers a unit with a terrain or fort bonus" % [_bare(String(f.name)),
				"have" if _plural(String(f.name)) else "has", " and ".join(bits), name]
	return "every one of its front-rank units is already shielded this round"


## Casts `plan` (from _spell_plan) by caster `c`: a bolt's damage waits as pending (it lands with the round's wounds)
## and counts its worth (the damage it will deal, never past the target's hp left) for its side; a hex or shield puts
## its part on its targets for the round; Bloodbolt marks its caster's bleed. Writes the log's cast event.
static func _apply_cast(plan: Dictionary, c: Dictionary, sides: Array, round_no: int, rec, hit_by: Dictionary, skipped: Array) -> void:
	var si: int = c.side
	var side: Dictionary = sides[si]
	var sid: String = plan.spell
	var key := SPELL_PREFIX + sid
	var st: Dictionary = side.spell_stats.get(sid, {"casts": 0, "rounds": {}, "casters": [], "targets": {}, "units": 0, "damage": 0, "kills": []})
	st.casts += 1
	st.rounds[round_no] = true
	var cname := _caster_ref(c)
	if not st.casters.has(cname):
		st.casters.append(cname)
	match String(plan.kind):
		"bolt":
			var t: Dictionary = plan.targets[0]
			var worth := mini(int(plan.damage), t.hp - t.pending)
			t.pending += int(plan.damage)
			t.bolted[sid] = si
			_add_impact(side, key, float(worth))
			st.damage += worth
			if int(plan.self) > 0:
				c.bleed = int(plan.self)
			if rec != null:
				if not hit_by.has(t.id):
					hit_by[t.id] = []
				hit_by[t.id].append(c.id)
		"hex":
			for t in plan.targets:
				t.spell_atk[key] = int(plan.part.value)
				t.hexed_by[key] = si
		"shield":
			for t in plan.targets:
				t.spell_def[key] = int(plan.part.value)
	for t in plan.targets:
		var nm := _target_ref(t)
		st.targets[nm] = int(st.targets.get(nm, 0)) + 1
	st.units += plan.targets.size()
	side.spell_stats[sid] = st
	side.spells_cast[sid] = int(side.spells_cast.get(sid, 0)) + 1
	side.cast_battle[sid] = true
	if rec == null:
		return
	var ev := {"t": "cast", "n": round_no, "by": c.id, "spell": sid, "school": String(plan.school), "kind": String(plan.kind),
		"bonus": int(plan.bonus), "targets": plan.targets.map(func(t): return int(t.id))}
	if plan.kind == "bolt":
		ev["value"] = int(plan.value)
		ev["resist"] = int(plan.resist)
	else:
		ev["part"] = plan.part.duplicate()
	ev["damage"] = int(plan.damage) if plan.kind == "bolt" else 0
	ev["self"] = int(plan.self)
	var book := ", ".join(side.spellbook.map(func(x): return MagicRules.spell_name(String(x))))
	var how := "every useful spell in its side's spellbook (%s) had been cast this round, so it started again from the top with %s" % [book,
		MagicRules.spell_name(sid)] if plan.get("again", false) \
		else "%s was the first useful spell in its side's spellbook (%s) that nobody on its side had cast yet this round" % [MagicRules.spell_name(sid), book]
	ev["why"] = "%s; %s" % [how, String(plan.why)]
	if not skipped.is_empty():
		ev["skipped"] = skipped.duplicate(true)
	_log_push(rec.log, rec.cap, ev)


## Whether a unit's name reads as a plural ("Spearmen", "Knights"; not "War Bear"), for "has" or "have".
static func _plural(name: String) -> bool:
	return name.ends_with("s") or name.ends_with("men")


## A caster in running text: "the Thornmane Shamans", "the Ever-Regent".
static func _caster_ref(c: Dictionary) -> String:
	return String(c.name) if c.ruler else _the(String(c.name))


## A spell's target in running text, without "the" for units ("Knights", "War Bear"), a ruler or commander by name.
static func _target_ref(t: Dictionary) -> String:
	return String(t.name) if t.ruler or t.cmd else _bare(String(t.name))


## The round line's sentence for one side's casts: "Thornmane Clans cast Briar Snare (6 Knights, -2 attack this round)
## and Bloodbolt (5 sure damage to Spearmen)."
static func _cast_line(side: Dictionary, picks: Array) -> String:
	var by_spell := {}
	var order := []
	for p in picks:
		if not by_spell.has(p.spell):
			by_spell[p.spell] = []
			order.append(p.spell)
		by_spell[p.spell].append(p)
	var parts := []
	for sid in order:
		var ps: Array = by_spell[sid]
		var names := {}
		var name_order := []
		var units := 0
		var damage := 0
		for p in ps:
			damage += int(p.damage)
			for t in p.targets:
				var nm := _target_ref(t)
				if not names.has(nm):
					names[nm] = 0
					name_order.append(nm)
				names[nm] += 1
				units += 1
		var whom := []
		for nm in name_order:
			whom.append(nm if int(names[nm]) == 1 else "%d %s" % [int(names[nm]), nm])
		var times := "" if ps.size() == 1 else " %d times" % ps.size()
		var p0: Dictionary = ps[0]
		if p0.kind == "bolt":
			parts.append("%s%s (%d sure damage to %s)" % [MagicRules.spell_name(sid), times, damage, " and ".join(whom)])
		else:
			parts.append("%s%s (%s, %+d %s this round)" % [MagicRules.spell_name(sid), times, " and ".join(whom), int(p0.part.value), String(p0.part.stat)])
	return "%s cast %s." % [side.name, " and ".join(parts)]


## Bleeding closes when the battle ends (§5.2): every standing fighter of the winning side gets back the hp it bled
## (never above its maximum). Returns [[fighter, hp before, hp after]] for each one healed.
static func _close_bleeds(sides: Array, winner: String) -> Array:
	var out := []
	for s in sides:
		if s.faction != winner:
			continue
		for f in s.fighters:
			var bled := int(f.get("bled", 0))
			if not f.alive or bled <= 0:
				continue
			var before: int = f.hp
			f.hp = mini(f.max, f.hp + bled)
			s.bled -= f.hp - before
			f.bled = 0
			if f.hp > before:
				out.append([int(f.get("id", -1)), before, int(f.hp)])
	return out


# --- the battle event log (M3-1, design/M3_BATTLES.md §2.2-§2.3) ----------------------------------
# These only read the battle's values and append to the log: nothing here draws from the RNG or writes
# to a side or fighter, except the log id ("id") _log_header gives each fighter record.

const TIER_WORDS := ["front", "second", "back"]


## The log's header (top level, sides and fighters; events come as the battle is fought). Numbers each
## fighter record with its log id, in the resolver's fighter order.
static func _log_header(sides: Array, sides_in: Array, ctx: Dictionary, env: Dictionary, rng: SeededRNG, state) -> Dictionary:
	var fighters := []
	var side_logs := []
	var standing := _standing(sides)
	var paths := _log_paths(sides)
	for si in sides.size():
		var s: Dictionary = sides[si]
		var ids := []
		for f in s.fighters:
			f["id"] = fighters.size()
			ids.append(f.id)
			fighters.append(_log_fighter(f, s))
		var armies: Array = sides_in[si].armies.duplicate()
		armies.sort_custom(func(a, b): return a.id < b.id)  # as _build_sides orders them (and their labels)
		var army_logs := []
		for ai in armies.size():
			army_logs.append({"id": armies[ai].id, "label": s.armies[ai]})
		var m := _morale(sides, si, standing)
		var side_log := {"index": si, "faction": s.faction, "name": s.name, "defender": s.is_defender, "armies": army_logs,
			"fighters": ids, "hp_start": s.hp_start, "base_morale": s.base_morale,
			"start_morale": {"morale": m.value, "parts": m.parts, "break_pct": break_pct(m.value)},
			"base_hit": s.base_hit, "frenzy": s.frenzy, "iron": s.iron, "feast": s.feast, "dread": s.dread,
			"mandates": s.mandates.duplicate()}
		if paths:
			# M4-3: the people it fights as, what each path morale part added to its base morale, the
			# morale Dread Lands takes from every enemy side here, and Red Harvest's gold per fighter.
			side_log["people"] = s.people.duplicate()
			side_log["base_morale_parts"] = s.base_morale_parts.duplicate()
			side_log["dread_lands"] = s.dread_lands
			side_log["red_harvest"] = s.red_harvest
		if s.magic:
			# M5-7: its casters, its spellbook (on spells, in order) and the enchantments in play.
			side_log["casters"] = s.casters.map(func(f): return int(f.id))
			side_log["spellbook"] = s.spellbook.duplicate()
			side_log["enchantments"] = s.enchant_log.duplicate(true)
		side_logs.append(side_log)
	var out := {"v": BattleLog.VERSION, "id": "", "turn": 0, "index": 0, "kind": env.kind,
		"provinces": ctx.get("province_ids", []).duplicate(), "terrain": env.terrain, "fort": env.fort,
		"defender": ctx.get("defender", ""), "round_cap": ROUND_CAP,
		"rng": {"seed": Serial.int64_to_str(rng.get_seed()), "before": Serial.int64_to_str(rng.get_state()), "after": ""},
		"sides": side_logs, "fighters": fighters, "events": [], "truncated": false}
	if paths:
		out["paths"] = true  # M4-3: the path additions below are in this log (BattleLog: "paths")
	if env.get("magic", false):
		out["magic"] = true  # M5-7: the magic additions are in this log (BattleLog: "magic")
	if sides.any(func(s): return s.get("wick", false)):
		out["wick"] = true  # CW-2: a flame or a Candlewake trait is on the field (BattleLog: "wick")
	if env.has("siege"):
		out["siege"] = env.siege.duplicate(true)  # M3c (§4.4): what kind of battle at a fort, and what the walls did
	return out


## True when a battle's log carries the M4-3 path additions: the game has paths, or a fighter with a path
## trait is on the field. Every other log is exactly the M3-1 schema.
static func _log_paths(sides: Array) -> bool:
	for s in sides:
		if s.get("paths", false):
			return true
		for f in s.fighters:
			if PATH_TRAITS.has(f.trait):
				return true
	return false


static func _log_fighter(f: Dictionary, s: Dictionary) -> Dictionary:
	var hp_parts := {}
	for m in f.mods.hp:
		hp_parts[m.key] = int(hp_parts.get(m.key, 0)) + int(m.value)
	var ruler := {}
	if f.ruler and not s.ruler_info.is_empty():
		ruler = {"id": s.ruler_info.id, "kept_power": s.ruler_info.kept_power, "rank": s.ruler_info.rank, "dread": s.ruler_info.dread}
	var ut: UnitType = f.type
	var out := {"id": f.id, "side": f.side, "army": f.army, "role": "commander" if f.cmd else ("ruler" if f.ruler else "unit"),
		"type": ut.id, "name": f.name, "trait": f.trait, "tier": f.tier, "hp": f.hp, "max_hp": f.max, "hp_parts": hp_parts,
		"attack": ut.attack, "defense": ut.defense, "morale": ut.morale, "cost": ut.cost, "ruler": ruler}
	if f.has("caster"):
		out["mastery"] = f.caster.mastery.duplicate()  # M5-7: a caster's bonus in each school it casts
	if ut.summoned:
		out["summoned"] = true  # M5-7: a summoned creature
	for key in ["flare_damage", "siphon_heal"]:
		if f.has(key):
			out[key] = int(f[key])  # CW-4: a path's Flare or Siphon, where it differs from the trait's own
	return out


## Appends `ev` unless the log has reached `cap` events: then recording stops and the log is marked
## "truncated" (the battle itself goes on as usual).
static func _log_push(battle_log: Dictionary, cap: int, ev: Dictionary) -> void:
	BattleLog.append(battle_log, ev, cap)


## The round event, with each standing side's reachable tiers from the target rule. Returns them by side
## index ({"tiers", "skirmish_tiers"}) for the round's attack events.
static func _log_round(rec: Dictionary, sides: Array, standing: Array, round_no: int) -> Dictionary:
	var by_side := {}
	var reach := []
	var paths: bool = rec.log.get("paths", false)
	for si in standing:
		var counts := _tier_counts(sides[si])
		var r := {"side": si, "tiers": _reachable_tiers(counts, false), "skirmish_tiers": _reachable_tiers(counts, true)}
		if paths:
			r["wings_tiers"] = _wings_tiers(counts)  # M4-3
		by_side[si] = r
		reach.append(r)
	_log_push(rec.log, rec.cap, {"t": "round", "n": round_no, "reach": reach})
	return by_side


static func _log_attack(rec: Dictionary, round_no: int, f: Dictionary, t: Dictionary, reach: Dictionary, pool: int, pick: int,
		chance: int, roll: int, hit: bool, dmg: int, bonus: int, base: int, atk: Dictionary, dfn: Dictionary, expected: float,
		hide: int = 0, pall: int = 0) -> void:
	var how: String = TIER_WORDS[t.tier]
	if not reach[t.side].tiers.has(t.tier):
		how = "wings" if f.trait == WINGS else "skirmish"  # only Skirmish (or Wings, M4-3) could reach it
	# The damage parts: Charge's bonus, and Iron Hide's reduction (M4-3) as a negative part.
	var damage_parts := {CHARGE: bonus} if bonus > 0 else {}
	if hide > 0:
		damage_parts[IRON_HIDE] = -hide
	var ev := {"t": "attack", "n": round_no, "by": f.id, "to": t.id, "pool": pool, "pick": pick,
		"chance": chance, "roll": roll, "hit": hit, "damage": dmg, "bonus": damage_parts,
		"base_hit": base, "attack": {"value": atk.value, "base": f.type.attack, "parts": atk.parts},
		"defense": {"value": dfn.value, "base": t.type.defense, "parts": dfn.parts}, "reach": how,
		"screened": not reach[f.side].tiers.has(f.tier), "expected": _dec(expected, 10.0)}
	if pall != 0:
		ev["pall"] = pall  # CW-2: what Pall took off the hit chance, inside the clamp (only on an attack on Pall)
	_log_push(rec.log, rec.cap, ev)


## The round's morale checks, routs and destructions, and its round_end totals.
static func _log_round_end(rec: Dictionary, sides: Array, standing: Array, round_no: int, checks: Dictionary, outcomes: Dictionary,
		attacks: Dictionary, hits: Dictionary, dealt: Dictionary, expected_by: Dictionary, impact_before: Array) -> void:
	for si in standing:
		if not checks.has(si):
			continue
		var c: Dictionary = checks[si]
		var o: Dictionary = outcomes[si]
		var ev := {"t": "morale", "n": round_no, "side": si, "morale": c.morale, "base": sides[si].base_morale,
			"parts": c.parts.duplicate(), "break_pct": c.break_pct, "lost_pct": c.lost_pct, "hp": c.hp, "result": o.result,
			"held_by": o.held_by, "decisive": _decisive(c, o.result), "iron_last_round": o.iron_last_round}
		if c.has("bled"):
			ev["bled"] = int(c.bled)  # M5-7: hp its own casters bled, left out of lost_pct
		_log_push(rec.log, rec.cap, ev)
	for si in standing:
		var s: Dictionary = sides[si]
		if s.destroyed:
			_log_push(rec.log, rec.cap, {"t": "destroyed", "n": round_no, "side": si})
		elif s.routed:
			var fled := []
			for f in s.fighters:
				if f.alive:
					fled.append(f.id)
			_log_push(rec.log, rec.cap, {"t": "rout", "n": round_no, "side": si, "fled": fled})
	var hp := []
	var att := []
	var hit := []
	var dlt := []
	var expd := []
	for si in sides.size():
		hp.append(_hp(sides[si]))
		att.append(int(attacks.get(si, 0)))
		hit.append(int(hits.get(si, 0)))
		dlt.append(int(dealt.get(si, 0)))
		expd.append(_dec(float(expected_by.get(si, 0.0)), 100.0))
	_log_push(rec.log, rec.cap, {"t": "round_end", "n": round_no, "hp": hp, "attacks": att, "hits": hit, "dealt": dlt,
		"expected": expd, "impact": _impact_deltas(sides, impact_before)})


## The parts that decided a morale check (§2.2): for "holds", each positive part without which the side
## would have broken; for "breaks", each negative part without which it would have held; [] for "held".
static func _decisive(check: Dictionary, result: String) -> Array:
	var out := []
	if result == "held":
		return out
	for p in check.parts:
		var v: int = check.parts[p]
		if result == "holds" and v > 0 and check.lost_pct >= break_pct(check.morale - v):
			out.append(p)
		elif result == "breaks" and v < 0 and check.lost_pct < break_pct(check.morale - v):
			out.append(p)
	return out


## A copy of every side's impact accumulator.
static func _impacts(sides: Array) -> Array:
	var out := []
	for s in sides:
		out.append(s.impact.duplicate())
	return out


## Per side, what each impact key gained since `before` (_impacts), to 2 decimals, zeros left out.
static func _impact_deltas(sides: Array, before: Array) -> Array:
	var out := []
	for si in sides.size():
		var d := {}
		var was: Dictionary = before[si]
		for k in sides[si].impact:
			var v := _dec(float(sides[si].impact[k]) - float(was.get(k, 0.0)), 100.0)
			if v != 0.0:
				d[k] = v
		out.append(d)
	return out


## `x` rounded to 1 / `per` (10.0: one decimal), as the double nearest that decimal, so the value
## survives a JSON round trip exactly (snappedf's multiply can land a bit off it: 4.6000000000000005).
static func _dec(x: float, per: float) -> float:
	return roundf(x * per) / per


## Feast of Victory's healing, read before _apply_losses applies it: [[fighter id, hp, max hp]] for each
## standing fighter of the winning side below its maximum, when that side has the mandate.
static func _feast_healed(sides: Array, winner: String) -> Array:
	var out := []
	for s in sides:
		if s.faction != winner or not s.feast or s.cursed:
			continue
		for f in s.fighters:
			if f.alive and f.hp < f.max:
				out.append([int(f.id), int(f.hp), int(f.max)])
	return out


# --- the report -----------------------------------------------------------------------------------

static func _report(sides: Array, ctx: Dictionary, env: Dictionary, rounds: Array, wi: int, end: String, state) -> Dictionary:
	var winner: Dictionary = sides[wi]
	var where := _place(ctx, state)
	var factors := _factors(sides, env, wi, end, rounds.size())
	var chosen := _choose(factors, wi)
	var clauses := []
	for c in chosen:
		clauses.append(c.clause)
	var why := "; ".join(clauses)

	var lines := []
	var who := []
	var siege: Dictionary = env.get("siege", {})
	for si in sides.size():
		var s: Dictionary = sides[si]
		var role := "defending" if s.is_defender else ("attacking" if not String(ctx.get("defender", "")).is_empty() else "arrived")
		if not siege.is_empty():
			role = _siege_role(siege, si, s)  # M3c: "defending the walls", "sallying", "relief", "outside the walls", ...
		if not s.people.is_empty():
			role = "%s, %s" % [s.people.name, role]  # M4-3: "Aurel Crown (Celestial Host, attacking)"
		who.append("%s (%s) with the %s" % [s.name, role, " and the ".join(s.armies)])
	if siege.is_empty():
		lines.append("Battle %s. %s." % [where, "; ".join(who)])
	else:
		# M3c (§4.5): the first line names the kind of battle at the fort.
		var names := sides.map(func(x): return String(x.name))
		lines.append("%s %s." % [siege_sentence(siege, String(env.get("place_name", "the fort")), names, String(env.get("terrain", ""))), "; ".join(who)])
	var paths_line := _paths_line(sides)
	if not paths_line.is_empty():
		lines.append(paths_line)
	var magic_line := _magic_line(sides)
	if not magic_line.is_empty():
		lines.append(magic_line)
	for r in rounds:
		lines.append(r.line)
	var side_reports := []
	var losses := []
	for s in sides:
		var lost_count: int = s.lost.size()
		losses.append(_losses_text(s))
		var rate := 0 if s.attacks == 0 else roundi(100.0 * s.hits / s.attacks)
		var avg := 0 if s.attacks == 0 else roundi(float(s.chance_sum) / s.attacks)
		var sr := {"faction": s.faction, "name": s.name, "armies": s.armies.duplicate(),
			"roster": s.roster.duplicate(true),
			"defender": s.is_defender, "fighters_start": s.count_start, "fighters_lost": lost_count,
			"lost": s.lost.duplicate(), "hp_start": s.hp_start, "hp_end": _hp(s), "routed": s.routed,
			"destroyed": s.destroyed, "out_round": s.out_round, "attacks": s.attacks, "hits": s.hits,
			"hit_rate": rate, "expected_hit_rate": avg,
			"hit_chance_range": [s.chance_min if s.attacks > 0 else 0, s.chance_max],
			"damage_dealt": s.dealt, "damage_expected": snappedf(s.expected, 0.1),
			"triggers": s.triggers.duplicate(), "morale_log": s.morale_log.duplicate(true),
			"base_morale": s.base_morale}
		# M2-2: only a side with a ruler or battle mandates carries these, so an M1 report is unchanged.
		if not s.ruler_info.is_empty():
			sr["ruler"] = _ruler_report(s)
		if not s.mandates.is_empty():
			sr["mandates"] = _mandates_report(s)
		# M4-3: only in a game with paths, or a battle where a path effect worked.
		if s.paths:
			sr["people"] = s.people.duplicate()
		if s.dread_lands > 0:
			sr["dread_lands"] = s.dread_lands
		if s.healed > 0:
			sr["lifedrinker_healed"] = s.healed
		if s.magic:
			# M5-7: only in a game with magic. Its casters (by type, like the roster) and how often it cast each spell.
			sr["casters"] = _casters_report(s)
			sr["spells_cast"] = s.spells_cast.duplicate()
			if s.blessed > 0:
				sr["blessed"] = s.blessed
			if s.moon_healed > 0:
				sr["moon_healed"] = s.moon_healed
		side_reports.append(sr)
	lines.append("Casualties: %s." % "; ".join(losses))
	var hit_parts := []
	for sr in side_reports:
		if sr.attacks > 0:
			var lo: int = sr.hit_chance_range[0]
			var hi: int = sr.hit_chance_range[1]
			var chances := ("a %d%% chance" % lo) if lo == hi else ("a %d-%d%% chance, about %d%% on average" % [lo, hi, sr.expected_hit_rate])
			hit_parts.append("%s hit %d%% of the time (%d of %d; each attack had %s)" % [sr.name, sr.hit_rate, sr.hits, sr.attacks, chances])
	if not hit_parts.is_empty():
		lines.append("Hits: %s." % "; ".join(hit_parts))
	var how := ""
	match end:
		"destroyed": how = "no enemy was left standing"
		"rout": how = "the enemy broke and fled"
		"mutual": how = "both sides broke in the same round, and %s had more of its strength left" % winner.name
		"round_cap":
			if winner.is_defender:
				how = "the attack was not decided after %d rounds, so the defender held" % ROUND_CAP
			else:
				how = "nothing was decided after %d rounds, and %s had more of its strength left" % [ROUND_CAP, winner.name]
	var n := rounds.size()
	lines.append("Result: %s won after %d %s: %s." % [winner.name, n, "round" if n == 1 else "rounds", how])
	lines.append("Why: %s." % _cap(why))
	var summary := "%s won after %d %s: %s. %s." % [winner.name, n, "round" if n == 1 else "rounds", why, "; ".join(losses)]
	var chosen_out := []
	for c in chosen:
		var co := {"id": c.id, "faction": c.faction, "impact": snappedf(c.impact, 0.1), "text": c.clause, "favors_winner": c.faction == winner.faction}
		if c.has("codex"):
			co["codex"] = c.codex  # M4-3: path factors name their RulesCodex entry
		chosen_out.append(co)
	var all_out := []
	for f in factors:
		var fo := {"id": f.id, "faction": f.faction, "impact": snappedf(f.impact, 0.1), "brief": f.brief, "text": f.clause}
		if f.has("codex"):
			fo["codex"] = f.codex
		all_out.append(fo)
	var out := {"kind": env.kind, "provinces": ctx.get("province_ids", []).duplicate(), "place": where,
		"terrain": env.terrain, "fort": env.fort, "defender": ctx.get("defender", ""), "winner": winner.faction,
		"winner_name": winner.name, "end": end, "rounds_fought": n, "round_cap": ROUND_CAP,
		"rounds": rounds.duplicate(true), "sides": side_reports, "factors": chosen_out, "all_factors": all_out,
		"why": why, "summary": summary, "lines": lines}
	if not siege.is_empty():
		out["siege"] = siege.duplicate(true)  # M3c (§4.5): the same block as the log's, for the viewer's walls chip
	return out


## M3c (§4.3, §4.5): the sentence that names a battle at a fort, from its siege block (SiegeRules.siege_block),
## the province's name and the sides' names in side order: "The Thornmane Clans stormed the walls of Crownkeep
## (9 of 9: +6 defense) on the second turn of the siege." / "Through the breach at Stonegate, the Aurel Crown's
## garrison met the Thornmane Clans in the open: ...". TurnResolver's battle event starts with it too.
static func siege_sentence(siege: Dictionary, place: String, names: Array, terrain: String = "") -> String:
	var gi := int(siege.get("garrison", -1))
	var owner := String(names[gi]) if gi >= 0 and gi < names.size() else ""
	var others := []
	for i in names.size():
		if i != gi:
			others.append(String(names[i]))
	var them := " and ".join(others)
	var everyone := " and ".join(names)
	var theirs := _poss(them) if not them.is_empty() else "enemy"
	var own := _poss(owner) if not owner.is_empty() else "the"
	match String(siege.get("why", "")):
		"storm":
			var n := int(siege.get("turn_of_siege", 0))
			var when := "from the march, with no siege before" if n <= 0 else "on the %s turn of the siege" % RulerRules.ordinal_word(n).to_lower()
			return "The %s stormed the walls of %s (%d of %d: +%d defense) %s." % [them, place, int(siege.walls), int(siege.walls_max),
				int(siege.walls_defense), when]
		"sally":
			return "At %s, the %s garrison sallied out against the %s siege lines. Outside the walls nobody holds the ground." % [place, own, theirs]
		"gate":
			return "At %s, the %s stormers met the sallying garrison at the gate. Outside the walls nobody holds the ground." % [place, theirs]
		"relief":
			return "At %s, a relief army of the %s met the %s siege lines outside the walls, where nobody holds the ground." % [place, owner, theirs]
		"relief_sally":
			return "At %s, a relief army of the %s reached the walls and met the %s siege lines, and the garrison sallied to join it. Outside the walls nobody holds the ground." % [
				place, owner, theirs]
		"rivals":
			return "At %s, the %s met outside the walls, where nobody holds the ground." % [place, everyone]
		"empty":
			var hi := int(siege.get("holder", -1))
			if hi >= 0 and hi < names.size():
				# MVP-3 (#177): a neutral fort's Free Holds garrison holds the ground in the open (SiegeRules.next_battle): the
				# terrain's bonus is its, the walls and cover are nobody's.
				var rest := []
				for i in names.size():
					if i != hi:
						rest.append(String(names[i]))
				var ground := ground_words(terrain)
				return "At %s, the %s garrison met the %s before its %s, holding the ground%s." % [place, names[hi], " and ".join(rest),
					String(siege.get("fort", "fort")), " (%s)" % ground if not ground.is_empty() else ""]
			return "At %s, the %s arrived together before the empty fort, where nobody holds the ground." % [place, everyone]
		"breach":
			return "Through the breach at %s, the %s garrison met the %s in the open: nobody holds the ground, and the garrison keeps +%d cover among the ruins." % [
				place, own, them, int(siege.get("cover_defense", 0))]
	return "At %s, the %s met outside the walls." % [place, everyone]


## What the ground gives the side that holds it, in a few words: "hills: +1 defense, +1 attack", "forest: +2 defense",
## "plains: no terrain bonus". "" when the terrain is unknown. The numbers are TERRAIN's.
static func ground_words(terrain: String) -> String:
	if terrain.is_empty():
		return ""
	var bonus: Dictionary = TERRAIN.get(terrain, {})
	var parts := []
	if int(bonus.get("defense", 0)) > 0:
		parts.append("+%d defense" % int(bonus.defense))
	if int(bonus.get("attack", 0)) > 0:
		parts.append("+%d attack" % int(bonus.attack))
	return "%s: %s" % [terrain, ", ".join(parts) if not parts.is_empty() else "no terrain bonus"]


## A side's role in a battle at a fort (M3c), for the report's first line.
static func _siege_role(siege: Dictionary, si: int, s: Dictionary) -> String:
	if String(siege.get("kind", "")) == SiegeRules.OPEN and int(siege.get("holder", -1)) >= 0:
		return "holding the ground" if si == int(siege.holder) else "attacking"  # MVP-3 (#177): a neutral fort's garrison
	var garrison := si == int(siege.get("garrison", -1))
	var inside := false
	for f in s.fighters:
		if Array(siege.get("from_inside", [])).has(f.army):
			inside = true
	match String(siege.get("kind", "")):
		SiegeRules.STORM:
			return "defending the walls" if garrison else "storming"
		SiegeRules.BREACH:
			return "garrison, in the breach" if garrison else "attacking through the breach"
	if garrison:
		if inside and String(siege.get("why", "")) == "relief_sally":
			return "relief and sallying garrison"
		return "sallying garrison" if inside else "relief"
	return "outside the walls"


## One side's losses for the casualty line, in plain words:
##   "Aurel Crown lost 1 of 4 fighters", "Thornmane Clans lost 2 of 3 fighters, and the last one fled",
##   "Thornmane Clans' only fighter fled", "Aurel Crown lost none of its 4 fighters".
static func _losses_text(s: Dictionary) -> String:
	var n: int = s.count_start
	var lost: int = s.lost.size()
	var fled: int = n - lost if s.routed else 0
	if n == 1:
		if lost == 1:
			return "%s lost its only fighter" % s.name
		return ("%s only fighter fled" % _poss(s.name)) if fled == 1 else "%s lost no fighters" % s.name
	if lost == 0:
		return ("%s lost no fighters, but all %d fled" % [s.name, n]) if fled > 0 else "%s lost none of its %d fighters" % [s.name, n]
	if lost == n:
		return ("%s lost both fighters" % s.name) if n == 2 else "%s lost all %d fighters" % [s.name, n]
	var text := "%s lost %d of %d fighters" % [s.name, lost, n]
	if fled == 1:
		text += ", and the last one fled"
	elif fled > 1:
		text += ", and the other %d fled" % fled
	return text


## A side's ruler in the report (§9): {"id", "name", "rank" ("front" | "second"), "kept_power",
## "max_hp", "attack", "defense", "hp_start", "hp_end", "fell" (its hp reached 0), "fell_round" (0 if it
## didn't), "damage_dealt", "damage_expected", and "dread" (the morale it took from every enemy side
## while it stood) when its Dread worked in this battle}. A ruler on a losing side is lost with its army
## even when it did not fall (TurnResolver).
static func _ruler_report(s: Dictionary) -> Dictionary:
	var info: Dictionary = s.ruler_info
	var hp_end := 0
	for f in s.fighters:
		if f.ruler:
			hp_end = f.hp
	var out := {"id": info.id, "name": info.name, "rank": info.rank, "kept_power": info.kept_power,
		"max_hp": info.max_hp, "attack": info.attack, "defense": info.defense, "hp_start": info.hp_start,
		"hp_end": hp_end, "fell": s.ruler_fell > 0, "fell_round": s.ruler_fell, "damage_dealt": s.ruler_dealt,
		"damage_expected": snappedf(s.ruler_expected, 0.1)}
	if int(info.dread) > 0:
		out["dread"] = int(info.dread)
	return out


## The battle mandates a side fought with, in the order taken: [{"id", "name", "effect", "codex"}].
static func _mandates_report(s: Dictionary) -> Array:
	var out := []
	for mid in s.mandates:
		var md := RulerRules.mandate_data(mid)
		out.append({"id": mid, "name": String(md.get("name", "")), "effect": String(md.get("effect", "")),
			"codex": String(md.get("codex", "mandates"))})
	return out


## Every candidate deciding factor: {"id", "side" (index it helped), "faction", "impact" (about how
## many hp it was worth to that side), "clause" (phrased for the report), "brief" (seed-free, for odds)}.
static func _factors(sides: Array, env: Dictionary, wi: int, end: String, rounds_fought: int) -> Array:
	var out := []
	var winner: Dictionary = sides[wi]
	for si in sides.size():
		var s: Dictionary = sides[si]
		var keys: Array = s.impact.keys()
		keys.sort()
		for k in keys:
			var v: float = s.impact[k]
			if v < 0.05:
				continue
			var won: bool = si == wi
			var c := ""
			var brief := ""
			var codex := ""  # M4-3: path factors carry their RulesCodex entry
			var unit: String = s.trait_units.get(k, "")
			var who := _poss(s.name)
			var dmg := roundi(v)
			match k:
				"terrain":
					var td: int = TERRAIN[env.terrain].defense
					var ta: int = TERRAIN[env.terrain].attack
					var bonus := "+%d defense" % td + (" and +%d attack" % ta if ta > 0 else "")
					c = "the %s gave the defending %s %s, worth about %d damage" % [env.terrain, s.name, bonus, dmg] if won \
						else "even though the %s gave the defending %s %s" % [env.terrain, s.name, bonus]
					brief = "the %s gives the defending %s %s" % [env.terrain, s.name, bonus]
				"fort":
					c = "the fort gave the defending %s +%d defense, worth about %d damage" % [s.name, FORT_DEFENSE, dmg] if won \
						else "even though the fort gave the defending %s +%d defense" % [s.name, FORT_DEFENSE]
					brief = "the fort gives the defending %s +%d defense" % [s.name, FORT_DEFENSE]
				WALLS:
					# M3c (§4.5): what the walls saved a stormed garrison, measured like terrain.
					var sg: Dictionary = env.siege
					var walls := "the walls of %s (%d of %d)" % [String(env.place_name), int(sg.walls), int(sg.walls_max)]
					c = "%s gave the defending %s +%d defense, worth about %d damage" % [walls, s.name, int(sg.walls_defense), dmg] if won \
						else "even though %s gave the defending %s +%d defense" % [walls, s.name, int(sg.walls_defense)]
					brief = "%s give the defending %s +%d defense" % [walls, s.name, int(sg.walls_defense)]
					codex = "battle_walls"
				COVER:
					# M3c (§4.5): the cover the fighters from inside keep in a sally or at the breach.
					var sg: Dictionary = env.siege
					var breach: bool = String(sg.kind) == SiegeRules.BREACH
					var cover := "the cover of %s %swalls (+%d defense)" % [_poss(String(env.place_name)), "ruined " if breach else "", int(sg.cover_defense)]
					var garrison := "%s garrison %s" % [who, "in the breach" if breach else "as it sallied"]
					c = "%s was worth about %d damage to %s" % [cover, dmg, garrison] if won else "even though %s helped %s" % [cover, garrison]
					brief = "%s for %s" % [cover, garrison]
					codex = "battle_breach" if breach else "battle_open"
				"commander":
					# v is the damage beyond what the same gold in ordinary units would have dealt.
					var cname := _commander_name(s)
					var total := roundi(s.cmd_expected)
					c = "%s %s fought from the back line and dealt about %d damage, about %d more than the same gold in ordinary units would have" % [
						who, cname, total, dmg] if won \
						else "even though %s %s dealt about %d damage from the back line" % [who, cname, total]
					brief = "%s %s (fights from the back line, +%d morale)" % [who, cname, COMMANDER_MORALE]
				SHIELD_WALL:
					c = "%s %s held their shield wall (+%d defense), turning aside about %d damage" % [who, unit, SHIELD_WALL_DEFENSE, dmg] if won \
						else "even though %s %s held their shield wall" % [who, unit]
				VOLLEY:
					c = "%s %s shot over their own front rank, out of reach, for about %d damage" % [who, unit, roundi(s.volley_expected)] if won \
						else "even though %s %s shot safely from the second rank" % [who, unit]
				CHARGE:
					c = "%s %s opened with a charge worth about %d extra damage%s" % [who, unit, dmg, " (the forest blunted it)" if env.terrain == "forest" else ""] if won \
						else "even though %s %s opened with a charge" % [who, unit]
				BERSERK:
					c = "%s %s went berserk once wounded (+%d attack), adding about %d damage" % [who, unit, BERSERK_ATTACK, dmg] if won \
						else "even though %s %s went berserk" % [who, unit]
				SKIRMISH:
					var behind := _the(_most_hit(s.skirmish_targets))
					c = "%s %s skirmished past the front line and hit %s behind it, for about %d damage" % [who, unit, behind, roundi(s.skirmish_reach)] if won \
						else "even though %s %s skirmished past the front line to %s" % [who, unit, behind]
				PACK_LEADER:
					c = "%s %s drove the pack (+%d attack to every unit), adding about %d damage" % [who, unit, PACK_LEADER_ATTACK, dmg] if won \
						else "even though %s %s drove the pack" % [who, unit]
				RULER:
					# The damage the ruler dealt (§7.4): it costs no gold, so all of it is what it added.
					var rname := String(s.ruler_info.name)
					var rank: String = RULER_RANK_WORDS.get(String(s.ruler_info.rank), "")
					c = "%s fought %s and dealt about %d damage%s" % [rname, rank, dmg, " before falling" if s.ruler_fell > 0 else ""] if won \
						else "even though %s fought %s and dealt about %d damage" % [rname, rank, dmg]
					brief = "%s (fights %s, +%d morale while it stands)" % [rname, rank, RulerData.RULER_MORALE]
				WINGS:
					# M4-3 (§9.6): the damage dealt to fighters only Wings could reach, like Skirmish's reach.
					var struck := _the(_most_hit(s.wings_targets))
					c = "%s %s flew over the line and struck %s, for about %d damage%s" % [who, unit, struck, roundi(s.wings_reach),
						_wings_kill_tail(s)] if won else "even though %s %s flew over the line to strike %s" % [who, unit, struck]
					codex = codex_id_for_trait(k)
				IRON_HIDE:
					var hits := "from each of %d %s" % [s.iron_hits, "hit" if s.iron_hits == 1 else "hits"] if s.iron_hits > 0 else "from every hit"
					c = "%s %s took %d less damage %s (Iron Hide), turning aside about %d damage" % [who, unit, IRON_HIDE_DAMAGE, hits, dmg] if won \
						else "even though %s %s took %d less damage %s (Iron Hide)" % [who, unit, IRON_HIDE_DAMAGE, hits]
					codex = codex_id_for_trait(k)
				ROOTED:
					c = "%s %s were rooted in the forest (+%d defense) and took about %d less damage" % [who, unit, ROOTED_DEFENSE, dmg] if won \
						else "even though %s %s were rooted in the forest (+%d defense)" % [who, unit, ROOTED_DEFENSE]
					codex = codex_id_for_trait(k)
				LIFEDRINKER:
					c = "%s %s drank back %d hp (Lifedrinker)" % [who, unit, s.healed] if won \
						else "even though %s %s drank back %d hp (Lifedrinker)" % [who, unit, s.healed]
					codex = codex_id_for_trait(k)
				FLAME:
					# CW-2 (§2.5): "Wick: +1 attack (flame 2)".
					var lit := _flame_words(s)
					c = "%s burned hot: Wick gave its regulars %s, worth about %d damage" % [s.name, lit, dmg] if won \
						else "even though Wick gave %s regulars %s" % [who, lit]
					brief = "Wick: %s" % lit
					codex = "wick"
				PALL:
					c = "%s %s were harder to hit (Pall, %d%% less hit chance), turning aside about %d damage" % [who, unit, PALL_HIT, dmg] if won \
						else "even though %s %s were harder to hit (Pall)" % [who, unit]
					codex = codex_id_for_trait(k)
				SIPHON:
					c = "%s %s drank %d hp back after their hits (Siphon)" % [who, unit, int(s.get("siphoned", 0))] if won \
						else "even though %s %s drank %d hp back (Siphon)" % [who, unit, int(s.get("siphoned", 0))]
					codex = codex_id_for_trait(k)
				FLARE:
					var flares := int(s.get("flares", 0))
					c = "%s %s flared as %s fell, burning %d damage into the enemy front rank" % [who, unit, "it" if flares == 1 else "they",
						int(s.get("flared", 0))] if won else "even though %s %s flared as %s fell" % [who, unit, "it" if flares == 1 else "they"]
					codex = codex_id_for_trait(k)
				_:
					var words := {}
					if k.begins_with(MANDATE_PREFIX):
						words = _mandate_words(s, k, dmg)
					elif k.begins_with(PATH_PREFIX):
						words = _path_words(s, k, dmg)  # M4-3: a path part, measured like a mandate's
						codex = AscensionRules.part_codex(k)
					elif k.begins_with(SPELL_PREFIX):
						words = _spell_words(s, k, dmg, sides, si)  # M5-7: a battle spell, or the Blood Moon
						codex = k
					if words.is_empty():
						continue
					c = String(words.done) + String(words.tail) if won else "even though %s" % words.done
					brief = String(words.brief)
			if brief.is_empty():
				brief = "%s %s (%s)" % [who, unit, TRAIT_SHORT.get(k, k)]
			var factor := {"id": k, "side": si, "faction": s.faction, "impact": v, "clause": c, "brief": brief}
			if not codex.is_empty():
				factor["codex"] = codex
			out.append(factor)

	# Morale: routs, and the morale effects that decided whether a side broke.
	for si in sides.size():
		var s: Dictionary = sides[si]
		if s.routed and si != wi:
			var ri: Dictionary = s.rout_info
			out.append({"id": "rout", "side": wi, "faction": winner.faction, "impact": float(ri.hp) * 0.5,
				"clause": "%s broke after losing %d%% of its strength (morale %d holds only to %d%%) and fled with %d hp unspent" % [
					s.name, ri.lost_pct, ri.morale, ri.break_pct, ri.hp],
				"brief": "%s is likely to break first (morale %d)" % [s.name, ri.morale]})
			var fury: int = ri.parts.get(FURY, 0)
			if fury < 0:
				var decisive: bool = ri.lost_pct < break_pct(ri.morale - fury)
				var bear_side := _side_with_trait(sides, FURY, si)
				if bear_side >= 0:
					var bs: Dictionary = sides[bear_side]
					out.append({"id": FURY, "side": bear_side, "faction": bs.faction,
						"impact": float(ri.hp) if decisive else float(-fury) * 0.5,
						"clause": ("%s %s roared (%d morale), and %s broke a round sooner than it would have" if decisive
							else "%s %s roared (%d morale) and shook %s") % [_poss(bs.name), bs.trait_units[FURY], fury, s.name] if bear_side == wi
							else "even though %s %s roared (%d morale)" % [_poss(bs.name), bs.trait_units[FURY], fury],
						"brief": "%s %s (%s)" % [_poss(bs.name), bs.trait_units[FURY], TRAIT_SHORT[FURY]]})
			# M2-2: the Great Thornmane's Dread, measured like Fury (§7.4).
			var dread: int = ri.parts.get(DREAD, 0)
			if dread < 0:
				var dread_side := _side_with_dread(sides, si)
				if dread_side >= 0:
					var ds: Dictionary = sides[dread_side]
					var decisive_dread: bool = ri.lost_pct < break_pct(ri.morale - dread)
					var whose := "%s %s (%d morale)" % [_poss(String(ds.ruler_info.name)), RulerRules.ability_name(String(ds.ruler_info.id)), dread]
					out.append({"id": "ability_dread", "side": dread_side, "faction": ds.faction,
						"impact": float(ri.hp) if decisive_dread else float(-dread) * 0.5,
						"clause": ("%s made %s break a round sooner than it would have" if decisive_dread else "%s shook %s") % [whose, s.name]
							if dread_side == wi else "even though %s shook %s" % [whose, s.name],
						"brief": "%s %s (%d enemy morale while it stands)" % [_poss(String(ds.ruler_info.name)),
							RulerRules.ability_name(String(ds.ruler_info.id)), dread]})
			# M4-3: Dread Lands, measured like Dread (§9.6).
			var lands: int = ri.parts.get(DREAD_LANDS, 0)
			if lands < 0:
				var land_side := _side_with_dread_lands(sides, si)
				if land_side >= 0:
					var ls: Dictionary = sides[land_side]
					var decisive_lands: bool = ri.lost_pct < break_pct(ri.morale - lands)
					var land := "fighting on %s own land cost %s %d morale" % [_poss(_people_ref(ls)), s.name, -lands]
					out.append({"id": DREAD_LANDS_ID, "side": land_side, "faction": ls.faction,
						"impact": float(ri.hp) if decisive_lands else float(-lands) * 0.5,
						"clause": ("%s: %s, and it broke a round sooner than it would have" if decisive_lands else "%s: %s") % [DREAD_LANDS, land]
							if land_side == wi else "even though %s (%s)" % [land, DREAD_LANDS],
						"brief": "%s (%s has %d less morale on %s own land)" % [DREAD_LANDS, s.name, -lands, _poss(_people_ref(ls))],
						"codex": DREAD_LANDS_ID})
	for si in sides.size():
		var s: Dictionary = sides[si]
		for key in ["commander", INSPIRE]:
			var held_by_it := false
			var seen := false
			for e in s.morale_log:
				var part: int = e.parts.get(key, 0)
				if part > 0:
					seen = true
					if e.lost_pct < e.break_pct and e.lost_pct >= break_pct(e.morale - part):
						held_by_it = true
			if not seen or key == "commander" and not held_by_it:
				continue
			var cname := _commander_name(s)
			var impact := float(_hp(s)) if held_by_it else float(INSPIRE_MORALE) * 0.5
			var c := ""
			if si == wi:
				# The commander's own +morale and Inspire's are separate factors, so their clauses differ
				# even when both kept the line from breaking.
				if key == "commander":
					c = "%s %s kept the line from breaking (+%d morale while it stands)" % [_poss(s.name), cname, COMMANDER_MORALE]
				else:
					c = ("%s %s inspired the line to hold (+%d morale from Inspire)" if held_by_it else "%s %s inspired the line (+%d morale from Inspire)") % [
						_poss(s.name), cname, INSPIRE_MORALE]
			else:
				c = "even though %s %s steadied the line" % [_poss(s.name), cname] if key == "commander" \
					else "even though %s %s inspired the line" % [_poss(s.name), cname]
			out.append({"id": "morale_" + key, "side": si, "faction": s.faction, "impact": impact, "clause": c,
				"brief": "%s %s (%s)" % [_poss(s.name), cname, "+%d morale" % (COMMANDER_MORALE + (INSPIRE_MORALE if key == INSPIRE else 0))]})
	# M4-3: path morale parts in the base morale (the Celestial Host's Sunspears), measured like Inspire.
	for si in sides.size():
		var s: Dictionary = sides[si]
		var keys: Array = s.base_morale_parts.keys()
		keys.sort()
		for key in keys:
			var part := int(s.base_morale_parts[key])
			if part <= 0 or s.morale_log.is_empty():
				continue
			var held_by_it := false
			for e in s.morale_log:
				if e.lost_pct < e.break_pct and e.lost_pct >= break_pct(e.morale - part):
					held_by_it = true
			var whose := _path_morale_words(s, String(key))
			var lifted := "raised %s morale by %d" % [_poss(s.name), part]
			var c := ""
			if si == wi:
				c = ("%s %s and kept the line from breaking" if held_by_it else "%s %s") % [whose, lifted]
			else:
				c = "even though %s steadied the line" % whose
			out.append({"id": "morale_" + String(key), "side": si, "faction": s.faction,
				"impact": float(_hp(s)) if held_by_it else float(part) * 0.5, "clause": c,
				"brief": "%s (%s)" % [whose, lifted], "codex": AscensionRules.part_codex(String(key))})
	# M5-7: Dawn Blessing's morale, measured like Inspire.
	for si in sides.size():
		var s: Dictionary = sides[si]
		var part := int(s.blessed)
		if part <= 0 or s.morale_log.is_empty():
			continue
		var held_by_it := false
		for e in s.morale_log:
			if e.lost_pct < e.break_pct and e.lost_pct >= break_pct(e.morale - part):
				held_by_it = true
		var lifted := "Dawn Blessing raised %s morale by %d (%d of %d fighters blessed)" % [_poss(s.name), part, int(s.blessed_fighters), int(s.count_start)]
		out.append({"id": "morale_" + BLESSING, "side": si, "faction": s.faction, "impact": float(_hp(s)) if held_by_it else float(part) * 0.5,
			"clause": ("%s and kept the line from breaking" if held_by_it else "%s") % lifted if si == wi else "even though Dawn Blessing steadied %s line" % _poss(s.name),
			"brief": "Dawn Blessing (+%d morale to %s)" % [part, s.name], "codex": BLESSING})
	# CW-2: Toll's morale, measured like Dawn Blessing's: the most it gave in a check, and whether it kept the line.
	for si in sides.size():
		var s: Dictionary = sides[si]
		var part := 0
		var held_by_it := false
		for e in s.morale_log:
			var toll := int(e.parts.get(TOLL, 0))
			part = maxi(part, toll)
			if toll > 0 and e.lost_pct < e.break_pct and e.lost_pct >= break_pct(e.morale - toll):
				held_by_it = true
		if part <= 0:
			continue
		var tolled := "%s %s tolled for the fallen (+%d morale)" % [_poss(s.name), String(s.trait_units.get(TOLL, "commander")), part]
		out.append({"id": "morale_" + TOLL, "side": si, "faction": s.faction, "impact": float(_hp(s)) if held_by_it else float(part) * 0.5,
			"clause": ("%s and kept the line from breaking" if held_by_it else "%s") % tolled if si == wi else "even though %s" % tolled,
			"brief": "%s %s (%s)" % [_poss(s.name), String(s.trait_units.get(TOLL, "commander")), TRAIT_SHORT[TOLL]], "codex": codex_id_for_trait(TOLL)})
	# M2-2: the ruler's +morale kept the line, measured like the commander's (§7.4), and Iron Discipline
	# held a side past its breaking point while a commander stood: the hp it kept from a rout.
	for si in sides.size():
		var s: Dictionary = sides[si]
		var won: bool = si == wi
		if not s.ruler_info.is_empty():
			var held_by_ruler := false
			for e in s.morale_log:
				var part: int = e.parts.get(RULER, 0)
				if part > 0 and e.lost_pct < e.break_pct and e.lost_pct >= break_pct(e.morale - part):
					held_by_ruler = true
			if held_by_ruler:
				var rname := String(s.ruler_info.name)
				out.append({"id": "morale_" + RULER, "side": si, "faction": s.faction, "impact": float(_hp(s)),
					"clause": "%s kept the line from breaking (+%d morale while it stands)" % [rname, RulerData.RULER_MORALE] if won
						else "even though %s steadied the line (+%d morale)" % [rname, RulerData.RULER_MORALE],
					"brief": "%s (+%d morale while it stands)" % [rname, RulerData.RULER_MORALE]})
		if not s.iron_held.is_empty():
			var last: Dictionary = s.iron_held.back()
			var iron := RulerRules.mandate_name(RulerRules.IRON_DISCIPLINE)
			var held := "%s held the %s line past its breaking point (lost %d%%, breaks at %d%%) while its %s stood" % [
				iron, s.name, last.lost_pct, last.break_pct, last.held_by]
			out.append({"id": MANDATE_PREFIX + RulerRules.IRON_DISCIPLINE, "side": si, "faction": s.faction, "impact": float(_hp(s)),
				"clause": held if won else "even though %s" % held,
				"brief": "%s keeps %s from breaking while one of its commanders stands" % [iron, s.name]})

	# Numbers: the bigger force, as a share of the fight's hp x attack. A side counts as the bigger force
	# only when it brought more hit points than every other side and at least as many fighters, and its
	# hp x attack was bigger too.
	var total_power := 0
	var total_hp := 0
	var biggest := 0
	for si in sides.size():
		total_power += sides[si].power
		total_hp += sides[si].hp_start
		if sides[si].hp_start > sides[biggest].hp_start:
			biggest = si
	var st: Dictionary = sides[biggest]
	var runner_up := -1  # the next biggest side, which the clause compares with
	var bigger := total_power > 0
	for si in sides.size():
		if si == biggest:
			continue
		var o: Dictionary = sides[si]
		if o.hp_start >= st.hp_start or o.count_start > st.count_start:
			bigger = false
		if runner_up < 0 or o.hp_start > sides[runner_up].hp_start:
			runner_up = si
	var even := 1.0 / sides.size()
	if bigger and runner_up >= 0 and float(st.power) / total_power > even:
		var o: Dictionary = sides[runner_up]
		var impact := (float(st.power) / total_power - even) * total_hp * 0.5
		var force := "%d %s (%d hp) against %d (%d hp)" % [st.count_start, "fighter" if st.count_start == 1 else "fighters",
			st.hp_start, o.count_start, o.hp_start]
		out.append({"id": "numbers", "side": biggest, "faction": st.faction, "impact": impact,
			"clause": "%s brought the bigger force: %s" % [st.name, force] if biggest == wi
				else "even though %s brought the bigger force (%s)" % [st.name, force],
			"brief": "%s has the bigger force (%d hp against %d)" % [st.name, st.hp_start, o.hp_start]})

	# Luck: damage dealt compared with what average rolls would have dealt (hit chance x damage of
	# every attack). The clause states exactly that, in damage, and gives hit rates only as separate
	# facts: a side whose big hits landed can be luckier in damage while hitting less often.
	var luck := []
	for s in sides:
		luck.append(s.dealt - s.expected)
	var others := 0.0
	var luckiest_other := -1
	for si in sides.size():
		if si == wi:
			continue
		others += luck[si] / (sides.size() - 1)
		if luckiest_other < 0 or luck[si] > luck[luckiest_other]:
			luckiest_other = si
	var adv: float = luck[wi] - others
	var lucky: int = wi if adv >= 0 else luckiest_other
	if lucky >= 0:
		# The side it is compared with: the unluckiest other side when the winner had the better
		# rolls, otherwise the winner. Either way luck[lucky] >= luck[other].
		var other := wi
		if lucky == wi:
			other = luckiest_other
			for si in sides.size():
				if si != wi and luck[si] < luck[other]:
					other = si
		var clause := _luck_clause(sides, lucky, other, luck)
		if lucky != wi:
			clause = "even though " + clause
		out.append({"id": "luck", "side": lucky, "faction": sides[lucky].faction, "impact": absf(adv), "clause": clause, "brief": "luck"})

	if end == "round_cap":
		out.append({"id": "round_cap", "side": wi, "faction": winner.faction, "impact": 1000000.0,
			"clause": ("the attackers could not break %s within %d rounds, so it held its ground" % [winner.name, ROUND_CAP]) if winner.is_defender
				else "after %d undecided rounds %s had more of its strength left" % [ROUND_CAP, winner.name],
			"brief": "%s only has to hold for %d rounds" % [winner.name, ROUND_CAP]})
	return out


## The luck clause, in the terms luck is measured in: how much more or less damage two sides' hits did
## than average rolls would have, then their hit rates as separate facts. `lucky` had the better rolls
## (luck[lucky] >= luck[other]), so the side named first is the one the rolls helped or hurt most:
##   "Aurel Crown's hits did about 9 more damage than average rolls would (mostly its Knights' charge),
##    and Thornmane Clans' about 4 less; hit rates: Aurel Crown 67% (about 77% expected), ..."
static func _luck_clause(sides: Array, lucky: int, other: int, luck: Array) -> String:
	var ls: Dictionary = sides[lucky]
	var os: Dictionary = sides[other]
	var a := roundi(luck[lucky])
	var b := roundi(luck[other])
	var text := "both sides' hits did about as much damage as average rolls would"
	if a > 0:
		text = "%s hits did about %d more damage than average rolls would%s, and %s" % [
			_poss(ls.name), a, _luck_source(ls, true), _luck_brief(os, b)]
	elif b < 0:
		text = "%s hits did about %d less damage than average rolls would%s, and %s" % [
			_poss(os.name), -b, _luck_source(os, false), _luck_brief(ls, a)]
	var rates := []
	for s in [ls, os]:
		var rate := 0 if s.attacks == 0 else roundi(100.0 * s.hits / s.attacks)
		var exp_rate := 0 if s.attacks == 0 else roundi(float(s.chance_sum) / s.attacks)
		rates.append("%s %d%% (about %d%% expected)" % [s.name, rate, exp_rate])
	return "%s; hit rates: %s" % [text, ", ".join(rates)]


## The second side's part of the luck clause: "Thornmane Clans' about 4 less", "... about as much".
static func _luck_brief(side: Dictionary, d: int) -> String:
	if d > 0:
		return "%s about %d more" % [_poss(side.name), d]
	if d < 0:
		return "%s about %d less" % [_poss(side.name), -d]
	return "%s about as much" % _poss(side.name)


## " (mostly its Knights' charge)" when one kind of attack made up at least half of a side's luck in
## that direction (landed hits for good luck, misses for bad luck), otherwise "".
static func _luck_source(side: Dictionary, good: bool) -> String:
	var total: float = absf(side.dealt - side.expected)
	var best_key := ""
	var best := 0.0
	var keys: Array = side.luck_by.keys()
	keys.sort()
	for k in keys:
		var v: float = side.luck_by[k] if good else -side.luck_by[k]
		if v > best + 0.000001:
			best = v
			best_key = k
	if best_key.is_empty() or best < total * 0.5:
		return ""
	var parts := best_key.split("|")
	var charge := parts.size() > 1
	if good:
		return " (mostly its %s %s)" % [_poss(parts[0]), "charge" if charge else "hits"]
	return " (mostly its %s %s)" % [_poss(parts[0]), "missed charges" if charge else "misses"]


## Picks the 1-3 factors that best explain the result: the biggest ones that helped the winner, plus
## the biggest one that helped a loser when it was large enough to be worth an "even though".
static func _choose(factors: Array, wi: int) -> Array:
	var pos := factors.filter(func(f): return f.side == wi and f.impact > MIN_IMPACT)
	var neg := factors.filter(func(f): return f.side != wi and f.impact > MIN_IMPACT)
	var order := func(a, b):
		if a.impact != b.impact:
			return a.impact > b.impact
		return a.id < b.id
	pos.sort_custom(order)
	neg.sort_custom(order)
	var chosen: Array = pos.slice(0, 3)
	if not neg.is_empty() and neg[0].id != "numbers" or not neg.is_empty() and pos.is_empty():
		var bar: float = pos[mini(1, pos.size() - 1)].impact if not pos.is_empty() else 0.0
		if neg[0].impact >= bar * 0.75 and neg[0].impact < 1000000.0:
			if chosen.size() == 3:
				chosen.pop_back()
			chosen.append(neg[0])
	if chosen.is_empty():
		var all := factors.duplicate()
		all.sort_custom(order)
		chosen = all.slice(0, 1)
	return chosen


# --- names ----------------------------------------------------------------------------------------

static func _faction_name(fid: String, state) -> String:
	if state is GameState:
		return TurnResolver._faction_name(state, fid)
	for f in FactionData.rows():
		if f.id == fid:
			return f.name
	return "an unknown faction"


static func _army_label(army: Army, state) -> String:
	if state is GameState:
		return TurnResolver.army_label(state, army)
	return "%s army (%s)" % [_faction_name(army.owner, state), TurnResolver._army_detail(army)]


static func _place(ctx: Dictionary, state) -> String:
	var pids: Array = ctx.get("province_ids", [])
	var province = ctx.get("province")
	if ctx.get("kind", "province") == "border":
		if state is GameState and pids.size() == 2:
			return "on the border between %s and %s" % [TurnResolver._province_name(state, pids[0]), TurnResolver._province_name(state, pids[1])]
		return "on a border"
	if province != null:
		return "of %s (%s%s)" % [province.name, province.terrain, ", fort" if province.has_fort else ""]
	return "in the field"


static func _commander_name(side: Dictionary) -> String:
	for f in side.fighters:
		if f.cmd:
			return f.name
	return "commander"


## The name hit most often in `counts` ({name: hits}; the first in name order on a tie), for the clause.
static func _most_hit(counts: Dictionary) -> String:
	var names: Array = counts.keys()
	names.sort()
	var best := ""
	for n in names:
		if best.is_empty() or counts[n] > counts[best]:
			best = n
	return best if not best.is_empty() else "second rank"


static func _side_with_trait(sides: Array, trait_id: String, not_side: int) -> int:
	for i in sides.size():
		if i != not_side and sides[i].trait_units.has(trait_id):
			return i
	return -1


## The first side other than `not_side` whose ruler has Dread in this battle, or -1.
static func _side_with_dread(sides: Array, not_side: int) -> int:
	for i in sides.size():
		if i != not_side and sides[i].dread > 0:
			return i
	return -1


## A stat mandate's part of the "why", from its data (§7.4): {"done" (what it did, the clause without
## its worth), "tail" (", worth about N damage"), "brief" (seed-free, for odds)}; {} for a mandate with
## no part to explain. `key` is "mandate_<id>", `dmg` its worth in damage (hp absorbed for Veteran Levies).
static func _mandate_words(s: Dictionary, key: String, dmg: int) -> Dictionary:
	var mid := key.trim_prefix(MANDATE_PREFIX)
	var md := RulerRules.mandate_data(mid)
	if md.is_empty():
		return {}
	var name := String(md.name)
	if md.has("base_hit"):
		return {"done": "%s raised %s base hit chance to %d%%" % [name, _poss(s.name), s.base_hit],
			"tail": ", worth about %d damage" % dmg,
			"brief": "%s raises %s base hit chance to %d%%" % [name, _poss(s.name), s.base_hit]}
	if md.has("wounded_attack"):
		return {"done": "%s gave %s wounded fighters +%d attack" % [name, _poss(s.name), s.frenzy],
			"tail": ", adding about %d damage" % dmg,
			"brief": "%s gives %s wounded fighters +%d attack" % [name, _poss(s.name), s.frenzy]}
	var units: Dictionary = md.get("units", {})
	if units.has("hp") and units.size() == 1:
		var bonus := RulerRules.units_bonus_text(mid)
		return {"done": "%s gave %s units %s" % [name, _poss(s.name), bonus],
			"tail": ", which absorbed about %d damage" % dmg,
			"brief": "%s gives %s units %s" % [name, _poss(s.name), bonus]}
	if not units.is_empty():
		var bonus := RulerRules.units_bonus_text(mid)
		return {"done": "%s gave every %s unit %s" % [name, s.name, bonus],
			"tail": ", worth about %d damage" % dmg,
			"brief": "%s gives every %s unit %s" % [name, s.name, bonus]}
	return {}


# --- paths in the report (M4-3, §9.6) ---------------------------------------------------------------

## The first side other than `not_side` whose Dread Lands work in this battle, or -1.
static func _side_with_dread_lands(sides: Array, not_side: int) -> int:
	for i in sides.size():
		if i != not_side and int(sides[i].get("dread_lands", 0)) > 0:
			return i
	return -1


## The people a side fights as, in running text ("the Blood Pact"), or its faction's name without one.
static func _people_ref(s: Dictionary) -> String:
	if s.people.is_empty():
		return String(s.name)
	return AscensionRules.branch_ref(String(s.people.id))


## A node as running text in the "why": a transformation by its people ("the Celestial Host", "Living
## Iron"), any other node by its name ("Arbalests").
static func _node_words(node_id: String) -> String:
	var n := AscensionRules.node_data(node_id)
	if String(n.get("kind", "")) == PathData.TRANSFORMATION and not String(n.get("branch", "")).is_empty():
		return AscensionRules.branch_ref(String(n.branch))
	return AscensionRules.node_name(node_id)


## The name a side's units of `type_id` fought under (a transformation renames them: "Iron Knights").
static func _type_name(s: Dictionary, type_id: String) -> String:
	if s.type_names.has(type_id):
		return String(s.type_names[type_id])
	for f in FactionData.rows():
		for u in f.unit_types:
			if u.id == type_id:
				return String(u.name)
	return type_id.capitalize()


## A path part's part of the "why" (§9.6), from PathData: {"done", "tail", "brief"} like _mandate_words,
## or {} for a part with no battle stat to explain. `key` is "path_<node>", `dmg` its worth in damage:
##   "Living Iron (+4 defense on Iron Knights)" + " turned aside about 18 damage"
static func _path_words(s: Dictionary, key: String, dmg: int) -> Dictionary:
	var nid := key.trim_prefix(PATH_PREFIX)
	if AscensionRules.node_data(nid).is_empty():
		return {}
	var units: Dictionary = AscensionRules.node_effects(nid).get("unit", {})
	var bonuses := []
	var first_stat := ""
	var on := []
	var type_ids: Array = units.keys()
	type_ids.sort()
	for type_id in type_ids:
		var stats: Dictionary = units[type_id]
		var pieces := []
		for stat in ["attack", "defense", "hp"]:
			if int(stats.get(stat, 0)) > 0:
				pieces.append("+%d %s" % [int(stats[stat]), PATH_STAT_WORDS[stat]])
				if first_stat.is_empty():
					first_stat = stat
		if not pieces.is_empty():
			bonuses.append(" and ".join(pieces))
			on.append(_type_name(s, String(type_id)))
	if first_stat.is_empty():
		return {}
	var name := _node_words(nid)
	var bonus := ", ".join(bonuses)
	var units_text := " and ".join(on)
	return {"done": "%s (%s on %s %s)" % [name, bonus, _poss(s.name), units_text],
		"tail": " " + PATH_STAT_VERBS[first_stat] % dmg,
		"brief": "%s gives %s %s %s" % [name, _poss(s.name), units_text, bonus]}


## Who carries a path morale part, for the "why": "the Celestial Host's Sunspears (+2 morale each)".
static func _path_morale_words(s: Dictionary, key: String) -> String:
	var nid := key.trim_prefix(PATH_PREFIX)
	var units: Dictionary = AscensionRules.node_effects(nid).get("unit", {})
	var parts := []
	var type_ids: Array = units.keys()
	type_ids.sort()
	for type_id in type_ids:
		var m := int(units[type_id].get("morale", 0))
		if m != 0:
			parts.append("%s (%+d morale each)" % [_type_name(s, String(type_id)), m])
	return "%s %s" % [_poss(_node_words(nid)), " and ".join(parts)]


## The end of Wings' clause when a commander it struck fell that round: "; the Thornmane Clans' Warchief
## fell in round 3, and with it Pack Leader".
static func _wings_kill_tail(s: Dictionary) -> String:
	if s.wings_kills.is_empty():
		return ""
	var k: Dictionary = s.wings_kills[0]
	var text := "; %s %s fell in round %d" % [_poss(String(k.side)), _bare(String(k.name)), int(k.round)]
	if not String(k.trait).is_empty():
		text += ", and with it %s" % k.trait
	return text


# --- battle spells in the report (M5-7, §5.4) ---------------------------------------------------------------

## A battle spell's (or the Blood Moon's) part of the "why", from what the side's casters did: {"done", "tail",
## "brief"} like _mandate_words, or {} when the side never cast it. `key` is "spell_<id>", `dmg` its worth:
##   bolt    "the Ever-Regent's Sunlance felled the War Bear in round 2" + ", 16 sure damage in 4 casts, never missing"
##   hex     "the Thornmane Shamans' Briar Snare slowed the Knights" + " for about 14 damage over 3 rounds"
##   shield  "the Sunstone Adepts' Shield of Law gave the Spearmen +4 defense" + ", turning aside about 7 damage over 3 rounds"
##   moon    "under the Blood Moon, Thornmane Clans healed back 9 hp"
static func _spell_words(s: Dictionary, key: String, dmg: int, sides: Array, si: int) -> Dictionary:
	var sid := key.trim_prefix(SPELL_PREFIX)
	var sp := MagicRules.spell_data(sid)
	if sp.is_empty():
		return {}
	var name := String(sp.name)
	if sid == "blood_moon":
		return {"done": "under the Blood Moon, %s healed back %d hp" % [s.name, int(s.moon_healed)], "tail": "",
			"brief": "the Blood Moon (%s heals back %s of the damage its attacks deal)" % [s.name, MagicRules.moon_share_word()]}
	var st: Dictionary = s.spell_stats.get(sid, {})
	if st.is_empty():
		return {}
	var casters: Array = st.casters
	var whose := "%s %s" % [_poss(String(casters[0])), name] if casters.size() == 1 else "%s (cast by %s)" % [name, " and ".join(casters)]
	var rounds: int = st.rounds.size()
	var over := "in round %d" % int(st.rounds.keys()[0]) if rounds == 1 else "over %d rounds" % rounds
	var target := _the(_most_hit(st.targets)) if not _most_hit(st.targets).begins_with("the ") else _most_hit(st.targets)
	var n := MagicRules.spell_numbers(sid, 0)
	match String(sp.kind):
		"bolt":
			var casts := "%d sure damage in %d %s, never missing" % [int(st.damage), int(st.casts), "cast" if int(st.casts) == 1 else "casts"]
			if not st.kills.is_empty():
				var k: Dictionary = st.kills[0]
				var fell := _the(String(k.name)) if not String(k.name).begins_with("the ") else String(k.name)
				return {"done": "%s felled %s in round %d" % [whose, fell, int(k.round)], "tail": ", %s" % casts,
					"brief": "%s (%d sure damage a cast)" % [whose, int(n.value)]}
			return {"done": "%s struck %s for %s" % [whose, target, casts], "tail": "",
				"brief": "%s (%d sure damage a cast)" % [whose, int(n.value)]}
		"hex":
			var what := "the front rank of %s" % _other_names(sides, si) if sp.has("round") else target
			return {"done": "%s slowed %s (%d attack)" % [whose, what, int(sp.value)], "tail": " for about %d damage %s" % [dmg, over],
				"brief": "%s (%d attack on %s)" % [whose, int(sp.value), "every enemy front-rank fighter in round 1" if sp.has("round")
					else "up to %d enemy front-rank units a round" % int(n.count)]}
		"shield":
			return {"done": "%s gave %s +%d defense" % [whose, target, int(sp.value)], "tail": ", turning aside about %d damage %s" % [dmg, over],
				"brief": "%s (+%d defense on up to %d front-rank units a round, in the open)" % [whose, int(sp.value), int(n.count)]}
	return {}


## The other sides' names, for "the front rank of Thornmane Clans".
static func _other_names(sides: Array, si: int) -> String:
	var out := []
	for i in sides.size():
		if i != si:
			out.append(String(sides[i].name))
	return " and ".join(out)


## A side's casters for the report, by type like the roster: [{"id", "name", "count"}] (the ruler by its own name).
static func _casters_report(s: Dictionary) -> Array:
	var out := []
	var index := {}
	for f in s.casters:
		var id: String = f.type.id
		if not index.has(id):
			index[id] = out.size()
			out.append({"id": id, "name": String(f.name), "count": 0})
		out[index[id]].count += 1
	return out


## The report's line about magic, after the opening line, when a side has a caster or an enchantment is in play
## (otherwise ""): "Magic: Thornmane Clans cast with 2 Thornmane Shamans (spellbook: Briar Snare, Bloodbolt); Aurel
## Crown has no caster. Thornmane Clans: the Blood Moon heals back a quarter of the damage its attacks deal."
static func _magic_line(sides: Array) -> String:
	var any := false
	for s in sides:
		if s.magic and (not s.casters.is_empty() or not s.enchant_log.is_empty()):
			any = true
	if not any:
		return ""
	var who := []
	var spells := []
	for s in sides:
		if s.casters.is_empty():
			who.append("%s has no caster" % s.name)
			continue
		var names := []
		for c in _casters_report(s):
			names.append(String(c.name) if int(c.count) == 1 else "%d %s" % [int(c.count), String(c.name)])
		var book := ", ".join(s.spellbook.map(func(x): return MagicRules.spell_name(String(x))))
		who.append("%s casts with %s (spellbook: %s)" % [s.name, " and ".join(names), book if not book.is_empty() else "nothing on"])
	for s in sides:
		for e in s.enchant_log:
			spells.append("%s: %s, %s" % [s.name, MagicRules.spell_name(String(e.ritual)), String(e.effect)])
	var text := "Magic: %s." % _cap("; ".join(who))
	if not spells.is_empty():
		text += " %s." % ". ".join(spells)
	return text


## The report's line about paths, after the opening line, when one is in play (otherwise ""): who fought as
## which people, and Dread Lands. "Paths: Aurel Crown fought as the Celestial Host. Dread Lands: this is the
## Blood Pact's own land, so Aurel Crown has 1 less morale."
static func _paths_line(sides: Array) -> String:
	var people := []
	var lands := []
	for s in sides:
		if not s.people.is_empty():
			people.append("%s fought as %s" % [s.name, AscensionRules.branch_ref(String(s.people.id))])
		if int(s.dread_lands) > 0:
			var others := []
			for o in sides:
				if o.faction != s.faction:
					others.append(String(o.name))
			var line := "%s: this is %s own land, so %s %s %d less morale" % [DREAD_LANDS, _poss(_people_ref(s)),
				" and ".join(others), "has" if others.size() == 1 else "each have", int(s.dread_lands)]
			if int(s.get("dread", 0)) > 0:
				# M4-6: Dread Lands doesn't stack with Dread.
				line += ", but not on top of %s's Dread: while %s stands, Dread Lands adds nothing to it" % [String(s.ruler_info.get("name", "the ruler")),
					String(s.ruler_info.get("name", "the ruler"))]
			lands.append(line)
	if people.is_empty() and lands.is_empty():
		return ""
	var text := "Paths:"
	if not people.is_empty():
		text += " %s." % _cap("; ".join(people))
	for l in lands:
		text += " %s." % l
	return text


static func _poss(name: String) -> String:
	return name + ("'" if name.ends_with("s") else "'s")


## A name without its leading "the", for "Thornmane Clans' Great Thornmane fell." (other names unchanged).
static func _bare(name: String) -> String:
	return name.trim_prefix("the ")


## A name with "the" in front, unless it already has it: "the Crossbowmen", "the Ever-Regent".
static func _the(name: String) -> String:
	return name if name.begins_with("the ") else "the " + name


static func _cap(text: String) -> String:
	return text if text.is_empty() else text[0].to_upper() + text.substr(1)
