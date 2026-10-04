extends RefCounted
## The fixture battles of M3-1 (#56; design/M3_BATTLES.md §11): constructed states fought through the
## real TurnResolver and AutoBattleResolver, so each fixture is a battle event exactly as a game makes it
## (id, turn, index, aftermath and all). tools/battle_log.gd --fixtures writes them to FIXTURE_DIR as
## {"scenario", "what", "seed", "log", "report"}; tests/test_battle_log.gd fights each again on its seed
## and checks it is unchanged, and runs every check on it.
##
##   Scenarios.run(name, seed)       -> {"log", "report", "event", "errors"}: the scenario's battle on that turn seed
##   Scenarios.shows(name, log, report)  whether that battle shows what the scenario is for
##   Scenarios.find_seed(name)       the first turn seed in 1..MAX_SEED where it does (-1: none)
##
## Each scenario's battle is the turn's only battle. Armies are set up by hand and start at full hp
## (Veteran Levies included); rulers are on the map only in the scenarios that use them. The exception is
## "biggest": the biggest battle measured in AI-vs-AI games with rulers (§1.3, §8.1), rebuilt with
## BattleLog.regenerate from that game's record, which is stored beside the fixtures (BIGGEST_RECORD;
## --fixtures plays the game again only when the file is missing, so changes to the AI don't move it).

const Games := preload("res://tools/battle_log/games.gd")

const FIXTURE_DIR := "res://tests/fixtures/battles"
const MAX_SEED := 400
## The biggest measured battle: AI-vs-AI game seed 9 with rulers (tools/battle_log/games.gd), turn 34,
## battle 0. Its "seed" in the fixture is the game seed.
const BIGGEST := {"game_seed": 9, "turn": 34, "index": 0}
const BIGGEST_RECORD := "res://tests/fixtures/battles/biggest_game.json"

const NAMES := ["starting_plains", "forest_fort", "knights_charge", "skirmish", "iron_discipline", "king_falls_wins",
	"dread_feast_frenzy", "round_cap_defender", "border", "biggest"]
const WHAT := {
	"starting_plains": "The starting armies on plains: the Clans attack the Crown at Rivermarch (no rulers).",
	"forest_fort": "A forest defence with a fort: the Crown holds Thornvale (given a fort for this fixture) against the Clans.",
	"knights_charge": "A Knights' charge: Crown Knights hit home in round 1 on the plains of Rivermarch.",
	"skirmish": "Skirmish past the front: Clans Fangthrowers hit Crossbowmen their Spearmen still shield.",
	"iron_discipline": "Iron Discipline holding: the Clans, past their breaking point, held while their Warchief stood.",
	"king_falls_wins": "King Corvane falling while his side wins.",
	"dread_feast_frenzy": "Dread with Feast and Blood Frenzy: the Great Thornmane's Clans hold Wildmoor, frenzied, and feast after.",
	"round_cap_defender": "The round cap with the defender holding: a Knight Captain alone in the Stonegate fort against a Warchief.",
	"border": "A border battle: the Crown and the Clans swap Rivermarch and Greenglade and meet on the border.",
	"biggest": "The biggest battle measured in AI-vs-AI games with rulers (design/M3_BATTLES.md §1.3): game seed 9, turn 34, 277 fighters, 898 attacks, 4 rounds, rebuilt from the game's record.",
}

const CROWN := "kingdom"
const CLANS := "beasts"


## Fights scenario `name` on turn seed `seed`: {"log", "report", "event" (the battle event), "errors"}.
static func run(name: String, seed_value: int) -> Dictionary:
	if name == "biggest":
		return _run_biggest()
	var setup := _setup(name)
	if setup.has("error"):
		return {"log": {}, "report": {}, "event": {}, "errors": [setup.error]}
	var result := TurnResolver.resolve(setup.state, setup.orders, seed_value, AutoBattleResolver.new())
	if result.new_state == null:
		return {"log": {}, "report": {}, "event": {}, "errors": result.get("errors", [])}
	var battles: Array = result.events.filter(func(e): return GameSession.BATTLE_TYPES.has(e.type))
	if battles.size() != 1:
		return {"log": {}, "report": {}, "event": {}, "errors": ["Scenario %s had %d battles on seed %d; it should have one." % [
			name, battles.size(), seed_value]]}
	var ev: Dictionary = battles[0]
	return {"log": ev.numbers.get("log", {}), "report": ev.numbers.report, "event": ev, "errors": []}


## Whether a fought scenario shows what it is for.
static func shows(name: String, battle_log: Dictionary, report: Dictionary) -> bool:
	if battle_log.is_empty():
		return false
	var events: Array = battle_log.events
	match name:
		"starting_plains", "border":
			return true
		"forest_fort":
			return events.any(func(e): return e.t == "attack" and e.defense.parts.has("terrain") and e.defense.parts.has("fort"))
		"knights_charge":
			return events.any(func(e): return e.t == "attack" and e.hit and e.bonus.has(AutoBattleResolver.CHARGE))
		"skirmish":
			return events.any(func(e): return e.t == "attack" and e.hit and e.reach == "skirmish")
		"iron_discipline":
			return events.any(func(e): return e.t == "morale" and e.result == "held")
		"king_falls_wins":
			var king := _ruler_id(battle_log, CROWN)
			return report.winner == CROWN and events.any(func(e): return e.t == "death" and int(e.f) == king)
		"dread_feast_frenzy":
			var frenzy := AutoBattleResolver.MANDATE_PREFIX + RulerRules.BLOOD_FRENZY
			return events.any(func(e): return e.t == "morale" and e.parts.has(AutoBattleResolver.DREAD)) \
				and events.any(func(e): return e.t == "attack" and e.attack.parts.has(frenzy)) \
				and events.any(func(e): return e.t == "feast")
		"round_cap_defender":
			var end: Dictionary = events[BattleLog.find_event(battle_log, "end")]
			return end.how == "round_cap" and end.tie_break == "defender"
		"biggest":
			var attacks := events.filter(func(e): return e.t == "attack").size()
			return battle_log.fighters.size() == 277 and attacks == 898 and int(report.rounds_fought) == 4
	return false


## The first turn seed in 1..MAX_SEED on which scenario `name` shows what it is for, or -1.
static func find_seed(name: String) -> int:
	if name == "biggest":
		var r := _run_biggest()
		return int(BIGGEST.game_seed) if r.errors.is_empty() and shows(name, r.log, r.report) else -1
	for sd in range(1, MAX_SEED + 1):
		var r := run(name, sd)
		if r.errors.is_empty() and shows(name, r.log, r.report):
			return sd
	return -1


static func fixture_path(name: String) -> String:
	return "%s/%s.json" % [FIXTURE_DIR, name]


## The stored fixture's seed, or -1 when there is no fixture file.
static func fixture_seed(name: String) -> int:
	var path := fixture_path(name)
	if not FileAccess.file_exists(path):
		return -1
	var fx = JSON.parse_string(FileAccess.get_file_as_string(path))
	return int(fx.get("seed", -1)) if fx is Dictionary else -1


## A constructed province scenario's battle as AutoBattleResolver.fight takes it, without TurnResolver:
## the armies after the scenario's moves, where they meet, the defender being the one faction that didn't
## move. {"sides", "ctx"}, or {"error"}. Nothing draws from the turn's RNG before its battles, so fighting
## this on SeededRNG(seed) is the scenario's battle on that turn seed.
static func direct(name: String) -> Dictionary:
	var setup := _setup(name)
	if setup.has("error"):
		return setup
	var s: GameState = setup.state
	var moved := {}
	for fid in setup.orders:
		for order in setup.orders[fid]:
			s.find_army(order.army_id).location = order.to
			moved[order.army_id] = true
	for p in s.provinces:
		var by := {}
		var holders := {}
		for a in s.armies:
			if a.location != p.id:
				continue
			if not by.has(a.owner):
				by[a.owner] = []
			by[a.owner].append(a)
			if not moved.has(a.id):
				holders[a.owner] = true
		if by.size() < 2:
			continue
		var fids: Array = by.keys()
		fids.sort()
		var sides := []
		for fid in fids:
			sides.append({"faction": fid, "armies": by[fid]})
		var defender: String = holders.keys()[0] if holders.size() == 1 else ""
		return {"sides": sides, "ctx": {"kind": "province", "defender": defender, "province": p, "province_ids": [p.id], "state": s}}
	return {"error": "Scenario %s has no province battle." % name}


## Times scenario `name`'s battle with recording off and on, `runs` times each, interleaved and
## alternating which goes first, from the same RNG state: {"off_min", "off_median", "on_min", "on_median"}
## in milliseconds. "biggest" is timed inside its real turn (TimingResolver catches the battle as
## TurnResolver hands it over); a constructed scenario on its fixture's seed (direct()).
static func time_recording(name: String, runs: int) -> Dictionary:
	if name == "biggest":
		var rec = _biggest_record()
		var start := GameSession.replay(rec, null, int(BIGGEST.turn) - 1)
		var entry: Dictionary = rec.history[int(BIGGEST.turn) - 1]
		var timer := TimingResolver.new()
		timer.index = int(BIGGEST.index)
		timer.runs = runs
		TurnResolver.resolve(start.state, OrderBook.orders_from_dict(entry.orders, []), Serial.to_int(entry.seed), timer)
		return timer.times
	var d := direct(name)
	return TimingResolver.time_fights(d.sides, d.ctx, maxi(1, fixture_seed(name)), -1, runs)


## The real battle rules, timing battle `index` of the turn with recording off and on before fighting it
## as usual (AutoBattleResolver.fight changes no army, so timing it first changes nothing).
class TimingResolver extends AutoBattleResolver:
	var index := 0
	var runs := 5
	var times := {}
	var _seen := 0

	func resolve_battle(battle: Dictionary, rng: SeededRNG) -> Dictionary:
		if _seen == index:
			var state = battle.get("state")
			var pids: Array = battle.get("provinces", [])
			var province: Province = null
			if state is GameState and battle.get("kind", "province") == "province" and not pids.is_empty():
				province = state.find_province(pids[0])
			var ctx := {"kind": battle.get("kind", "province"), "defender": battle.get("defender", ""), "province": province,
				"province_ids": pids, "state": state}
			times = time_fights(battle.sides, ctx, rng.get_seed(), rng.get_state(), runs)
		_seen += 1
		return super.resolve_battle(battle, rng)

	## Fights the battle `runs` times with recording off and `runs` times on, alternating which goes first,
	## each from the same RNG seed and state (rng_state -1: just the seed).
	static func time_fights(sides: Array, ctx: Dictionary, seed_value: int, rng_state: int, count: int) -> Dictionary:
		var off := []
		var on := []
		for i in count:
			for k in 2:
				var record := (i + k) % 2 == 1
				var rng := SeededRNG.new(seed_value)
				if rng_state != -1:
					rng.set_state(rng_state)
				var t0 := Time.get_ticks_usec()
				AutoBattleResolver.fight(sides, ctx, rng, record)
				var ms := (Time.get_ticks_usec() - t0) / 1000.0
				(on if record else off).append(ms)
		off.sort()
		on.sort()
		return {"off_min": off[0], "off_median": off[off.size() / 2], "on_min": on[0], "on_median": on[on.size() / 2]}


## The biggest battle, rebuilt from its game's record: {"log", "report", "event", "errors"}.
static func _run_biggest() -> Dictionary:
	var rec = _biggest_record()
	if not (rec is Dictionary):
		return {"log": {}, "report": {}, "event": {}, "errors": ["There is no record of the biggest battle's game at %s: run tools/battle_log.gd --fixtures." % BIGGEST_RECORD]}
	var r := BattleLog.regenerate(rec, int(BIGGEST.turn), int(BIGGEST.index))
	return {"log": r.log, "report": r.report, "event": {}, "errors": r.errors}


## The stored record of the biggest battle's game, or null.
static func _biggest_record():
	if not FileAccess.file_exists(BIGGEST_RECORD):
		return null
	var data = JSON.parse_string(FileAccess.get_file_as_string(BIGGEST_RECORD))
	return data.get("record") if data is Dictionary else null


## Writes BIGGEST_RECORD by playing its game, unless it is already there. "" when the record is there.
static func ensure_biggest_record() -> String:
	if _biggest_record() is Dictionary:
		return ""
	var g := Games.play(int(BIGGEST.game_seed))
	if not g.errors.is_empty():
		return "The biggest battle's game didn't play: %s" % "; ".join(g.errors)
	var f := FileAccess.open(BIGGEST_RECORD, FileAccess.WRITE)
	if f == null:
		return "Could not write %s." % BIGGEST_RECORD
	f.store_string(JSON.stringify({"what": "The record (GameSession.record()) of AI-vs-AI game seed %d with rulers, whose turn %d has the biggest measured battle." % [
		int(BIGGEST.game_seed), int(BIGGEST.turn)], "record": g.record}) + "\n")
	f.close()
	return ""


# --- the set-ups --------------------------------------------------------------------------------------

## {"state", "orders"} for a scenario, or {"error"}.
static func _setup(name: String) -> Dictionary:
	match name:
		"starting_plains":
			var s := _state()
			_army(s, "kingdom-1", CROWN, "rivermarch", _starting(s, CROWN))
			_army(s, "beasts-2", CLANS, "greenglade", _starting(s, CLANS))
			return {"state": s, "orders": {CLANS: [MoveOrder.new("beasts-2", "rivermarch")]}}
		"forest_fort":
			var s := _state()
			s.find_province("thornvale").has_fort = true
			_army(s, "kingdom-1", CROWN, "thornvale", ["spearmen", "spearmen", "spearmen", "crossbowmen", "knight_captain"])
			_army(s, "beasts-2", CLANS, "wildmoor", ["tuskers", "tuskers", "tuskers", "fangthrowers", "war_bear", "warchief"])
			return {"state": s, "orders": {CLANS: [MoveOrder.new("beasts-2", "thornvale")]}}
		"knights_charge":
			var s := _state()
			_army(s, "beasts-1", CLANS, "rivermarch", ["tuskers", "tuskers", "fangthrowers", "warchief"])
			_army(s, "kingdom-2", CROWN, "crownkeep", ["knights", "knights", "spearmen", "spearmen", "knight_captain"])
			return {"state": s, "orders": {CROWN: [MoveOrder.new("kingdom-2", "rivermarch")]}}
		"skirmish":
			var s := _state()
			_army(s, "kingdom-1", CROWN, "rivermarch", ["spearmen", "spearmen", "crossbowmen", "crossbowmen"])
			_army(s, "beasts-2", CLANS, "greenglade", ["fangthrowers", "fangthrowers", "fangthrowers", "tuskers"])
			return {"state": s, "orders": {CLANS: [MoveOrder.new("beasts-2", "rivermarch")]}}
		"iron_discipline":
			var s := _state({CROWN: {"ruler": "aurel_king", "mandates": []},
				CLANS: {"ruler": "fang_chieftain", "mandates": [RulerRules.IRON_DISCIPLINE]}})
			if s == null:
				return {"error": "The iron_discipline set-up failed."}
			_army(s, "beasts-1", CLANS, "wildmoor", ["tuskers", "tuskers", "fangthrowers", "warchief"])
			_army(s, "kingdom-2", CROWN, "thornvale", ["spearmen", "spearmen", "spearmen", "crossbowmen", "crossbowmen", "knights",
				"knights", "knight_captain"])
			return {"state": s, "orders": {CROWN: [MoveOrder.new("kingdom-2", "wildmoor")]}}
		"king_falls_wins":
			var s := _state({CROWN: {"ruler": "aurel_king", "mandates": []}, CLANS: {"ruler": "fang_chieftain", "mandates": []}})
			if s == null:
				return {"error": "The king_falls_wins set-up failed."}
			_army(s, "kingdom-1", CROWN, "rivermarch", ["spearmen", "spearmen", "spearmen", "spearmen", "crossbowmen", "crossbowmen",
				"knights", "knights", "knight_captain"])
			_ruler(s, CROWN, "rivermarch", 0, "kingdom-9")
			_army(s, "beasts-2", CLANS, "greenglade", ["tuskers", "tuskers", "tuskers", "fangthrowers", "war_bear", "warchief"])
			return {"state": s, "orders": {CLANS: [MoveOrder.new("beasts-2", "rivermarch")]}}
		"dread_feast_frenzy":
			var s := _state({CROWN: {"ruler": "aurel_king", "mandates": []},
				CLANS: {"ruler": "thornmane_avatar", "mandates": [RulerRules.BLOOD_FRENZY, RulerRules.FEAST_OF_VICTORY]}})
			if s == null:
				return {"error": "The dread_feast_frenzy set-up failed."}
			_army(s, "beasts-1", CLANS, "wildmoor", ["tuskers", "tuskers", "tuskers", "fangthrowers", "war_bear", "warchief"])
			_ruler(s, CLANS, "wildmoor", -1, "beasts-9")
			_army(s, "kingdom-2", CROWN, "thornvale", ["spearmen", "spearmen", "spearmen", "crossbowmen", "knights", "knight_captain"])
			return {"state": s, "orders": {CROWN: [MoveOrder.new("kingdom-2", "wildmoor")]}}
		"round_cap_defender":
			var s := _state()
			_army(s, "kingdom-1", CROWN, "stonegate", ["knight_captain"])
			_army(s, "beasts-2", CLANS, "blackwood", ["warchief"])
			return {"state": s, "orders": {CLANS: [MoveOrder.new("beasts-2", "stonegate")]}}
		"border":
			var s := _state()
			_army(s, "kingdom-1", CROWN, "rivermarch", ["spearmen", "spearmen", "crossbowmen", "knights", "knight_captain"])
			_army(s, "beasts-2", CLANS, "greenglade", ["tuskers", "tuskers", "fangthrowers", "war_bear", "warchief"])
			return {"state": s, "orders": {CROWN: [MoveOrder.new("kingdom-1", "greenglade")], CLANS: [MoveOrder.new("beasts-2", "rivermarch")]}}
	return {"error": "There is no fixture scenario called '%s'. The scenarios are: %s." % [name, ", ".join(NAMES)]}


## A state with the real factions and map and no armies. With `builds`, a game with rulers in which no
## ruler is on the map (each counts as dead, its successor due long after) until _ruler() places one.
static func _state(builds: Dictionary = {}) -> GameState:
	if builds.is_empty():
		var plain := GameState.new(1)
		plain.armies.clear()
		return plain
	var errors := []
	var s := GameState.with_rulers(1, builds, errors)
	if s == null:
		push_error("battle log scenarios: %s" % " ".join(errors))
		return null
	s.armies.clear()
	for f in s.factions:
		f.ruler_status = RulerRules.DEAD
		f.successor_turn = 999
		f.successor_power = f.kept_power
	return s


## An army of `owner` at `location` with these unit and commander ids, every unit at its maximum hp.
static func _army(s: GameState, id: String, owner: String, location: String, type_ids: Array) -> Army:
	var a := Army.new()
	a.id = id
	a.owner = owner
	a.location = location
	var f := s.find_faction(owner)
	for type_id in type_ids:
		var ut := TurnResolver.recruitable_type(f, type_id)
		if ut.is_commander:
			a.commander = Unit.new(ut, owner)
		else:
			var u := Unit.new(ut, owner)
			u.current_hp = RulerRules.unit_max_hp(s, u)
			a.units.append(u)
	s.armies.append(a)
	return a


## `fid`'s ruler, alive at full hp, in its own army at `location`, with `kept` kept power (-1: as built).
static func _ruler(s: GameState, fid: String, location: String, kept: int, id: String) -> Army:
	var f := s.find_faction(fid)
	if kept >= 0:
		f.kept_power = kept
	f.ruler_status = RulerRules.ALIVE
	f.successor_turn = 0
	f.successor_power = 0
	RulerRules.refresh_ruler_type(f)
	var a := Army.new()
	a.id = id
	a.owner = fid
	a.location = location
	a.ruler = Unit.new(f.ruler_unit_type, fid)
	s.armies.append(a)
	return a


## One of each unit type and the commander: the army each faction starts the game with.
static func _starting(s: GameState, fid: String) -> Array:
	var f := s.find_faction(fid)
	var ids := []
	for ut in f.unit_types:
		ids.append(ut.id)
	ids.append(f.commander_type.id)
	return ids


static func _ruler_id(battle_log: Dictionary, fid: String) -> int:
	for f in battle_log.fighters:
		if f.role == "ruler" and battle_log.sides[int(f.side)].faction == fid:
			return int(f.id)
	return -1
