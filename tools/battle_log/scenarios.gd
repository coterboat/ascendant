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
##
## M5-7 (#118): the scripted magic battles (MAGIC_NAMES), fought the same way in a game with magic, each showing a
## battle spell at work. They aren't stored as fixtures: tests fight them on the first seed that shows what they are for
## (find_seed), so they follow the rules as they are. run(), shows(), find_seed() and direct() take their names too.

const Games := preload("res://tools/battle_log/games.gd")

const FIXTURE_DIR := "res://tests/fixtures/battles"
const MAX_SEED := 400
## The biggest measured battle: AI-vs-AI game seed 9 with rulers (tools/battle_log/games.gd), turn 34,
## battle 0. Its "seed" in the fixture is the game seed.
const BIGGEST := {"game_seed": 9, "turn": 34, "index": 0}
const BIGGEST_RECORD := "res://tests/fixtures/battles/biggest_game.json"

const NAMES := ["starting_plains", "forest_fort", "knights_charge", "skirmish", "iron_discipline", "king_falls_wins",
	"dread_feast_frenzy", "round_cap_defender", "border", "biggest", "one_round", "mutual_rout"]
## M5-7: the scripted magic battles (not stored fixtures; see above).
const MAGIC_NAMES := ["magic_shamans", "magic_regent", "magic_fort", "magic_sunburst", "magic_blood_moon", "magic_free_holds"]
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
	"one_round": "A one-round battle: a lone Crown Spearmen holding Rivermarch is swept away in the first round (M3-2's turning point has none).",
	"mutual_rout": "A mutual rout: both sides break in the same round on the Rivermarch-Greenglade border, and the one with more strength left keeps the field.",
	"biggest": "The biggest battle measured in AI-vs-AI games with rulers (design/M3_BATTLES.md §1.3): game seed 9, turn 34, 277 fighters, 746 attacks, 3 rounds, rebuilt from the game's record.",
	"magic_shamans": "Two Thornmane Shamans (Briar Snare and Bloodbolt) with a Clans warband attack the Crown at Rivermarch: the M5-7 playtest battle.",
	"magic_regent": "The Ever-Regent and two Sunstone Adepts (Sunlance, Shield of Law) march blessed out of Crownkeep to attack the Clans at Rivermarch.",
	"magic_fort": "Two Sunstone Adepts help hold the Crownkeep fort against the Clans: Shield of Law is skipped behind the walls, so they cast Sunlance.",
	"magic_sunburst": "The Crown, sworn to the Dawn, calls down Sunburst on a Clans front rank in round 1 at Rivermarch.",
	"magic_blood_moon": "The Blood Pact under its Blood Moon, with Shamans casting Bloodbolt, attacks the Crown at Rivermarch: fighters heal back and the casters bleed.",
	"magic_free_holds": "Two Thornmane Shamans (Briar Snare) and a Clans warband storm a Free Holds garrison at Ironspike in a game with independents.",
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
		"one_round":
			return int(events[BattleLog.find_event(battle_log, "end")].rounds) == 1
		"mutual_rout":
			return events[BattleLog.find_event(battle_log, "end")].how == "mutual"
		"magic_shamans":
			return _cast(battle_log, "briar_snare") and _cast(battle_log, "bloodbolt")
		"magic_regent":
			var regent := _ruler_id(battle_log, CROWN)
			return events.any(func(e): return e.t == "cast" and int(e.by) == regent and e.spell == "sunlance") and _cast(battle_log, "shield_of_law") \
				and events.any(func(e): return e.t == "morale" and e.parts.has(AutoBattleResolver.BLESSING))
		"magic_fort":
			return events.any(func(e): return e.t == "cast" and Array(e.get("skipped", [])).any(func(x): return x.spell == "shield_of_law"))
		"magic_sunburst":
			return events.any(func(e): return e.t == "cast" and e.spell == "sunburst" and int(e.n) == 1)
		"magic_blood_moon":
			return events.any(func(e): return e.t == "heal" and e.get("spell", "") == "blood_moon") \
				and events.any(func(e): return e.t == "wound" and int(e.get("bled", 0)) > 0)
		"magic_free_holds":
			var holds := -1
			for sd in battle_log.sides:
				if String(sd.faction) == IndependentData.FACTION_ID:
					holds = int(sd.index)
			return holds >= 0 and events.any(func(e): return e.t == "cast" and int(battle_log.fighters[int(e.targets[0])].side) == holds)
		"biggest":
			var attacks := events.filter(func(e): return e.t == "attack").size()
			# #94 renamed the armies of its game (each faction numbers its own), which reorders who strikes when:
			# the same 277 fighters now fight 742 attacks over 3 rounds (898 over 4 before), with the same winner.
			# #131: Blood Frenzy +2 instead of +3 (the Clans' Clan Moot has it) changes who falls when: 746 attacks, same
			# 3 rounds and winner. Turns 1-33 of the game have no battle, so its record still replays to this battle.
			return battle_log.fighters.size() == 277 and attacks == 746 and int(report.rounds_fought) == 3
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
		"one_round":
			var s := _state()
			_army(s, "kingdom-1", CROWN, "rivermarch", ["spearmen"])
			_army(s, "beasts-2", CLANS, "greenglade", ["tuskers", "tuskers", "tuskers", "war_bear", "warchief"])
			return {"state": s, "orders": {CLANS: [MoveOrder.new("beasts-2", "rivermarch")]}}
		"mutual_rout":
			var s := _state()
			_army(s, "kingdom-1", CROWN, "rivermarch", ["spearmen", "spearmen", "crossbowmen"])
			_army(s, "beasts-2", CLANS, "greenglade", ["tuskers", "fangthrowers", "fangthrowers"])
			return {"state": s, "orders": {CROWN: [MoveOrder.new("kingdom-1", "greenglade")], CLANS: [MoveOrder.new("beasts-2", "rivermarch")]}}
		# M5-7: the scripted magic battles.
		"magic_shamans":
			var s := _magic_state({}, [CLANS, ["briar_snare", "bloodbolt"]])
			if s == null:
				return {"error": "The magic_shamans set-up failed."}
			_army(s, "kingdom-21", CROWN, "rivermarch", ["spearmen", "spearmen", "spearmen", "spearmen", "crossbowmen", "crossbowmen", "knights",
				"knights", "knight_captain"])
			_army(s, "beasts-22", CLANS, "greenglade", ["tuskers", "tuskers", "tuskers", "tuskers", "fangthrowers", "fangthrowers", "war_bear",
				"shamans", "shamans", "warchief"])
			return {"state": s, "orders": {CLANS: [MoveOrder.new("beasts-22", "rivermarch")]}}
		"magic_regent":
			var s := _magic_state({CROWN: {"ruler": "ever_regent", "mandates": []}}, [CROWN, ["sunlance", "shield_of_law"]])
			if s == null:
				return {"error": "The magic_regent set-up failed."}
			var reg := RulerRules.ruler_army(s, CROWN)
			_army(s, "kingdom-21", CROWN, "crownkeep", ["spearmen", "spearmen", "spearmen", "spearmen", "spearmen", "knights", "adepts", "adepts"])
			_army(s, "beasts-22", CLANS, "rivermarch", ["tuskers", "tuskers", "tuskers", "tuskers", "fangthrowers", "war_bear", "war_bear", "warchief"])
			_enchant(s, "dawn_blessing", CROWN, "crownkeep", ["kingdom-21", reg.id])
			return {"state": s, "orders": {CROWN: [MoveOrder.new("kingdom-21", "rivermarch"), MoveOrder.new(reg.id, "rivermarch")]}}
		"magic_fort":
			var s := _magic_state({}, [CROWN, ["sunlance", "shield_of_law"]])
			if s == null:
				return {"error": "The magic_fort set-up failed."}
			_army(s, "kingdom-21", CROWN, "crownkeep", ["spearmen", "spearmen", "spearmen", "spearmen", "crossbowmen", "adepts", "adepts", "knight_captain"])
			_army(s, "beasts-22", CLANS, "rivermarch", ["tuskers", "tuskers", "tuskers", "tuskers", "tuskers", "fangthrowers", "war_bear", "warchief"])
			return {"state": s, "orders": {CLANS: [MoveOrder.new("beasts-22", "crownkeep")]}}
		"magic_sunburst":
			var s := _magic_state({}, [CROWN, ["crown_drillyard", "crown_charters", "crown_oath_dawn", "sunlance", "dawn_blessing", "sunburst"]])
			if s == null:
				return {"error": "The magic_sunburst set-up failed."}
			_army(s, "kingdom-21", CROWN, "crownkeep", ["spearmen", "spearmen", "spearmen", "spearmen", "spearmen", "spearmen", "knights", "knights",
				"adepts", "adepts", "adepts"])
			_army(s, "beasts-22", CLANS, "rivermarch", ["tuskers", "tuskers", "tuskers", "tuskers", "tuskers", "tuskers", "fangthrowers", "war_bear",
				"warchief"])
			return {"state": s, "orders": {CROWN: [MoveOrder.new("kingdom-21", "rivermarch")]}}
		"magic_blood_moon":
			var s := _magic_state({}, [CLANS, ["beasts_boar_hide", "beasts_raiding", "beasts_oath_blood", "beasts_blood_pact", "bloodbolt",
				"bloodrot", "blood_moon"]])
			if s == null:
				return {"error": "The magic_blood_moon set-up failed."}
			_army(s, "kingdom-21", CROWN, "rivermarch", ["spearmen", "spearmen", "spearmen", "spearmen", "crossbowmen", "knights", "knights",
				"knight_captain"])
			_army(s, "beasts-22", CLANS, "greenglade", ["tuskers", "tuskers", "tuskers", "bloodsworn", "bloodsworn", "fangthrowers", "shamans",
				"shamans", "warchief"])
			_enchant(s, "blood_moon", CLANS, "", [])
			return {"state": s, "orders": {CLANS: [MoveOrder.new("beasts-22", "rivermarch")]}}
		"magic_free_holds":
			var s := _magic_state({}, [CLANS, ["briar_snare"]], "ironspike")
			if s == null:
				return {"error": "The magic_free_holds set-up failed."}
			_army(s, "beasts-22", CLANS, "fangridge", ["tuskers", "tuskers", "tuskers", "tuskers", "fangthrowers", "shamans", "shamans", "warchief"])
			return {"state": s, "orders": {CLANS: [MoveOrder.new("beasts-22", "ironspike")]}}
	return {"error": "There is no fixture scenario called '%s'. The scenarios are: %s." % [name, ", ".join(NAMES + MAGIC_NAMES)]}


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


## M5-7: a game with magic (and rulers and paths) with `research` = [faction id, [node ids]] researched, and no armies
## but the rulers' own at their capitals. With `holds`, a game with independents too, keeping only the Free Holds
## garrison of that province.
static func _magic_state(builds: Dictionary, research: Array = [], holds: String = "") -> GameState:
	var b := {CROWN: {"ruler": "aurel_king", "mandates": []}, CLANS: {"ruler": "fang_chieftain", "mandates": []}}
	for fid in builds:
		b[fid] = builds[fid]
	var errors := []
	var s := GameState.with_magic(1, b, errors)
	if s == null or (not holds.is_empty() and not s.setup_independents(errors)):
		push_error("battle log scenarios: %s" % " ".join(errors))
		return null
	var keep: Array[Army] = []
	for a in s.armies:
		if a.ruler != null or (a.owner == IndependentData.FACTION_ID and a.location == holds):
			keep.append(a)
	s.armies = keep
	if not research.is_empty():
		s = AscensionRules.with_nodes(s, String(research[0]), research[1], 0)
	return s


## M5-7: an enchantment written by hand (M5-6 casts them in a real game), in its saved form, cast on turn 1.
static func _enchant(s: GameState, ritual: String, fid: String, province: String, armies: Array) -> void:
	var f := s.find_faction(fid)
	f.enchant_counter += 1
	s.enchantments.append({"id": "%s-e%d" % [fid, f.enchant_counter], "ritual": ritual, "faction": fid,
		"kind": String(MagicRules.spell_data(ritual).kind), "province": province, "armies": armies.duplicate(), "cast_turn": 1,
		"until_turn": 3, "bonus": 0, "ending": false})
	s.enchantments.sort_custom(func(x, y): return String(x.id) < String(y.id))


## Whether `battle_log` has a cast of spell `sid`.
static func _cast(battle_log: Dictionary, sid: String) -> bool:
	return battle_log.events.any(func(e): return e.t == "cast" and e.spell == sid)


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
