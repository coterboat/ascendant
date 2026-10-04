class_name FortData
## Forts and sieges (M3c, design/M3C_SIEGES.md §2, §3, §5, §12): the numbers every siege rule, forecast,
## breakdown, codex entry and screen reads. Pure data, like data/factions.gd. The rules are SiegeRules.
## Only a game with sieges uses any of this (GameState.setup_sieges); an M1, M2 or M4 game never does.
##
## The words used everywhere: troops are the units that fight (every regular unit in an army); commanders
## and rulers are not troops, and engines are not units at all. The recruit limit counts every recruit.

## Fort levels by number (the index is the level). "walls" is the most wall strength the level has;
## "recruits" how many recruits it takes a turn (troops, commanders and engines alike); "commanders" and
## "engines" whether it may recruit them; "repair" the walls it regains each turn no enemy army is there;
## "cost" and "turns" what a Fortify order building it costs and how many turns of work it needs (the
## citadel can't be built: capitals start as one).
const LEVELS := [
	{"level": 0, "id": "", "name": "no fort", "walls": 0, "recruits": 0, "commanders": false, "engines": false,
		"repair": 0, "cost": 0, "turns": 0},
	{"level": 1, "id": "palisade", "name": "Palisade", "walls": 3, "recruits": 2, "commanders": false, "engines": false,
		"repair": 1, "cost": 30, "turns": 2},
	{"level": 2, "id": "keep", "name": "Keep", "walls": 6, "recruits": 4, "commanders": true, "engines": true,
		"repair": 2, "cost": 50, "turns": 3},
	{"level": 3, "id": "citadel", "name": "Citadel", "walls": 9, "recruits": 8, "commanders": true, "engines": true,
		"repair": 3, "cost": 0, "turns": 0},
]
const MAX_LEVEL := 3
## The highest level a Fortify order builds: a palisade, then a keep. Citadels stay at capitals.
const MAX_BUILT := 2

## Walls if stormed (§4.1): every fighter of a stormed garrison gets WALLS_DEFENSE_PER_STEP defense for every
## WALL_STEP wall strength still standing, rounded up. Always a multiple of 2, so #41's breakpoints hold.
const WALL_STEP := 3
const WALLS_DEFENSE_PER_STEP := 2
## The cover the fighters from inside the walls keep in a sally or at the breach (§4.1).
const COVER_DEFENSE := 2

## Siege damage a turn (§3.3): the siege camp, +1 for every `per_troops` troops (rounded down, at most
## `troops_max`), +`engine` for each engine (at most `engines_max`, and at most one for every
## `troops_per_engine` troops); never more than `max`.
const SIEGE := {"camp": 1, "per_troops": 10, "troops_max": 2, "engine": 1, "engines_max": 3, "troops_per_engine": 5, "max": 6}

## The level each fort starts at on any map (§2.2): a capital is a citadel, every other province with a fort
## on the map a keep, all at full walls.
const START := {"capital": 3, "fort": 2}
## Turns after a capture before the new owner's fort takes recruits (§2.3): a fort taken on turn 7 takes
## recruits from turn 9 (owned_since + CAPTURE_WAIT < the turn being ordered).
const CAPTURE_WAIT := 1
## A faction that retakes its own fort by this many turns after losing it gets its old standing back.
const RETAKE_TURNS := 2

## The most engines one army carries (§5).
const ARMY_ENGINES_MAX := 3
## The trait engines carry, as players read it, and what it does.
const ENGINE_TRAIT := "Siege Engine"
const ENGINE_RULE := "It doesn't fight: while its army besieges a fort it adds %d siege damage a turn," % SIEGE.engine \
	+ " if there are at least %d troops for every engine," % SIEGE.troops_per_engine \
	+ " and at most %d engines count in one siege. It is lost with its army." % SIEGE.engines_max
## One siege engine per faction (§5). They are never units: a recruited engine adds 1 to the `engines` of
## the army it joins, they never fight, and they are lost with their army. They are not in any roster:
## TurnResolver.recruitable_type offers them only in a game with sieges.
const ENGINES := {
	"kingdom": {"id": "siege_ram", "name": "Siege Ram", "plural": "Siege Rams", "faction": "kingdom", "cost": 18,
		"text": "A ram on wheels under a timber roof. " + ENGINE_RULE},
	"beasts": {"id": "wallbreakers", "name": "Wallbreakers", "plural": "Wallbreakers", "faction": "beasts", "cost": 16,
		"text": "A crew with a great iron-shod trunk. " + ENGINE_RULE},
}


## The row of LEVELS for `level` (the no-fort row for anything out of range).
static func level(n: int) -> Dictionary:
	return LEVELS[n] if n >= 0 and n < LEVELS.size() else LEVELS[0]


## The engine `faction_id` recruits, or {}.
static func engine_for(faction_id: String) -> Dictionary:
	return ENGINES.get(faction_id, {})


## The engine with this id, or {}.
static func engine_by_id(engine_id: String) -> Dictionary:
	for fid in ENGINES:
		if String(ENGINES[fid].id) == engine_id:
			return ENGINES[fid]
	return {}
