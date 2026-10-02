extends "res://tests/test_case.gd"
## #49: loading never crashes on malformed data. GameState.from_dict, the loaders it calls and
## GameSession.replay fail with a plain-language reason when a field has the wrong type (Serial load
## checks), never with a script error (the runner fails any test that logs one) and never with a silent
## null. One test per crash site the review found, then a sweep over every field of a saved game.
## Also the validation gap from the same issue: a living ruler with no ruler's army is rejected, while
## every state the game itself makes with rulers (deaths in battle included) still validates.

const Simulator := preload("res://tools/autoplay/simulator.gd")
const SEATS := ["kingdom", "beasts"]
## Words a plain-language load error never uses.
const JARGON := ["Dictionary", "Array", "String", "Nil", "null", "Variant", "Invalid", "SCRIPT"]
## Values of the wrong type the sweep puts in every field.
const WRONG := ["x", 3, true, [], ["x"], {"a": 1}]


## StubBattleResolver's result, then every ruler on the winning side falls: its army no longer holds
## it, as when a ruler's hp reaches 0 in a battle its side wins.
class RulerFallsResolver extends BattleResolver:
	func resolve_battle(battle: Dictionary, rng: SeededRNG) -> Dictionary:
		var result := StubBattleResolver.new().resolve_battle(battle, rng)
		for side in battle.sides:
			if side.faction == result.winner:
				for a in side.armies:
					a.ruler = null
		return result


# --- fixtures -------------------------------------------------------------------------------------

## A saved game with rulers: armies kingdom-1 and beasts-2, then the rulers' kingdom-3 and beasts-4.
func _rulers() -> Dictionary:
	return GameState.with_rulers(5, {"kingdom": "regents_court", "beasts": "clan_moot"}, []).to_dict()


func _by_id(list: Array, id: String) -> Dictionary:
	for d in list:
		if d.get("id") == id:
			return d
	return {}


## Loading `data` fails: null, at least one reason, every reason plain, the first one equal to (or,
## with `exact` false, containing) `expected`.
func _assert_rejected(data, expected: String, what: String, exact: bool = true) -> void:
	var errs := []
	assert_eq(GameState.from_dict(data, errs), null, "%s is rejected" % what)
	assert_false(errs.is_empty(), "%s: the load says why" % what)
	_assert_plain(errs, what)
	if not errs.is_empty():
		if exact:
			assert_eq(errs[0], expected, what)
		else:
			assert_true(String(errs[0]).contains(expected), "%s: '%s' in %s" % [what, expected, errs])


## Every reason is a sentence in plain words: capitalised, ending in a full stop, no engine jargon.
func _assert_plain(errs: Array, what: String) -> void:
	for e in errs:
		var text := String(e)
		assert_true(text.length() > 20 and text.ends_with(".") and text.substr(0, 1) == text.substr(0, 1).to_upper(),
			"%s: a sentence: %s" % [what, text])
		for word in JARGON:
			assert_false(text.contains(word), "%s: no '%s' in: %s" % [what, word, text])


## A record with one resolved turn in which the Aurel Crown moved its starting army.
func _record() -> Dictionary:
	var session := GameSession.new(GameState.with_rulers(5, {}, []), SEATS, 5, StubBattleResolver.new())
	assert_eq(session.queue_move("kingdom-1", "westwatch"), "")
	assert_eq(session.end_turn(), "")
	assert_eq(session.acknowledge_handoff(), "")
	assert_eq(session.end_turn(), "")
	return session.record()


# --- one test per crash site (#49) ----------------------------------------------------------------

func test_army_units_that_are_not_a_list_of_units() -> void:
	var d := _rulers()
	_by_id(d.armies, "kingdom-1")["units"] = "x"
	_assert_rejected(d, "The 'units' field of army 'kingdom-1' should be a list, but the saved data has text there.", "units = \"x\"")
	d = _rulers()
	_by_id(d.armies, "kingdom-1").units[1] = "x"
	_assert_rejected(d, "Unit 2 of army 'kingdom-1' should be a group of named values, but the saved data has text there.", "a unit that is text")
	d = _rulers()
	_by_id(d.armies, "kingdom-1").units[0]["type_id"] = 3
	_assert_rejected(d, "The 'type_id' field of unit 1 of army 'kingdom-1' should be text, but the saved data has a number there.", "a unit type id that is a number")


func test_army_commander_that_is_not_a_unit() -> void:
	var d := _rulers()
	_by_id(d.armies, "kingdom-1")["commander"] = "x"
	_assert_rejected(d, "The 'commander' field of army 'kingdom-1' should be a group of named values, but the saved data has text there.", "commander = \"x\"")
	d = _rulers()
	_by_id(d.armies, "beasts-2")["commander"] = 7
	_assert_rejected(d, "The 'commander' field of army 'beasts-2' should be a group of named values, but the saved data has a number there.", "commander = 7")


func test_faction_unit_types_that_are_not_a_list_of_unit_types() -> void:
	var d := _rulers()
	_by_id(d.factions, "kingdom")["unit_types"] = "x"
	_assert_rejected(d, "The 'unit_types' field of faction 'kingdom' should be a list, but the saved data has text there.", "unit_types = \"x\"")
	d = _rulers()
	_by_id(d.factions, "kingdom").unit_types[0] = "x"
	_assert_rejected(d, "Unit type 1 of faction 'kingdom' should be a group of named values, but the saved data has text there.", "a unit type that is text")
	d = _rulers()
	_by_id(d.factions, "beasts").unit_types[2]["is_commander"] = "no"
	_assert_rejected(d, "The 'is_commander' field of unit type 3 of faction 'beasts' should be true or false, but the saved data has text there.", "is_commander = \"no\"")


func test_faction_commander_type_that_is_not_a_unit_type() -> void:
	var d := _rulers()
	_by_id(d.factions, "kingdom")["commander_type"] = "x"
	_assert_rejected(d, "The 'commander_type' field of faction 'kingdom' should be a group of named values, but the saved data has text there.", "commander_type = \"x\"")


func test_text_fields_that_are_not_text() -> void:
	# The review's M1 repro (a province owner that is a number) and its neighbours: name, terrain, id
	# and a faction's capital.
	for key in ["owner", "name", "terrain"]:
		var m1 := GameState.new(5).to_dict()
		_by_id(m1.provinces, "westwatch")[key] = 3
		_assert_rejected(m1, "The '%s' field of province 'westwatch' should be text, but the saved data has a number there." % key, "province %s = 3" % key)
	var d := _rulers()
	var index := 0
	while d.provinces[index].id != "westwatch":
		index += 1
	d.provinces[index]["id"] = 3
	_assert_rejected(d, "The 'id' field of province number %d should be text, but the saved data has a number there." % (index + 1), "province id = 3")
	d = _rulers()
	_by_id(d.factions, "kingdom")["capital"] = 3
	_assert_rejected(d, "The 'capital' field of faction 'kingdom' should be text, but the saved data has a number there.", "capital = 3")
	d = _rulers()
	_by_id(d.provinces, "crownkeep")["is_capital"] = "yes"
	_assert_rejected(d, "The 'is_capital' field of province 'crownkeep' should be true or false, but the saved data has text there.", "is_capital = \"yes\"")
	d = _rulers()
	_by_id(d.provinces, "crownkeep")["neighbors"] = "westwatch"
	_assert_rejected(d, "The 'neighbors' field of province 'crownkeep' should be a list, but the saved data has text there.", "neighbors = \"westwatch\"")


func test_lists_of_provinces_factions_and_armies_that_are_not_lists_of_groups() -> void:
	for key in ["provinces", "factions", "armies"]:
		var d := _rulers()
		d[key] = "x"
		_assert_rejected(d, "The '%s' field of the saved game should be a list, but the saved data has text there." % key, "%s = \"x\"" % key)
	var entries := {"provinces": "Province", "factions": "Faction", "armies": "Army"}
	for key in entries:
		var d := _rulers()
		d[key][1] = "x"
		_assert_rejected(d, "%s 2 of the saved game should be a group of named values, but the saved data has text there." % entries[key], "an entry of %s that is text" % key)
	_assert_rejected([], "The saved game should be a group of named values, but the saved data has a list there.", "a saved game that is a list")


func test_rng_that_is_not_a_group() -> void:
	var d := _rulers()
	d["rng"] = "x"
	_assert_rejected(d, "The 'rng' field of the saved game should be a group of named values, but the saved data has text there.", "rng = \"x\"")


func test_ruler_fields_of_the_wrong_type() -> void:
	# The review found these loaded as empty without a crash; they now fail like every other field.
	var d := _rulers()
	_by_id(d.armies, "kingdom-3")["ruler"] = "x"
	_assert_rejected(d, "The 'ruler' field of army 'kingdom-3' should be a group of named values, but the saved data has text there.", "ruler = \"x\"")
	d = _rulers()
	_by_id(d.factions, "kingdom")["mandates"] = "royal_armories"
	_assert_rejected(d, "The 'mandates' field of faction 'kingdom' should be a list, but the saved data has text there.", "mandates = \"royal_armories\"")
	d = _rulers()
	_by_id(d.factions, "beasts")["sacrifices"] = ["x"]
	_assert_rejected(d, "Sacrifice 1 of faction 'beasts' should be a group of named values, but the saved data has text there.", "a sacrifice that is text")
	d = _rulers()
	_by_id(d.factions, "beasts")["ruler_status"] = 5
	_assert_rejected(d, "The 'ruler_status' field of faction 'beasts' should be text, but the saved data has a number there.", "ruler_status = 5")


func test_replay_order_entries_that_are_not_orders_are_skipped_and_reported() -> void:
	var good := _record()
	var rec: Dictionary = good.duplicate(true)
	rec.history[0].orders["kingdom"].append("x")
	var rep := GameSession.replay(rec, StubBattleResolver.new())
	assert_eq(rep.errors, ["Turn 1: Order 2 for 'kingdom' should be a group of named values, but the saved data has text there."])
	assert_true(rep.state != null, "the readable orders still replay")
	if rep.state != null:
		assert_eq(rep.state.to_dict(), GameSession.replay(good, StubBattleResolver.new()).state.to_dict(), "the move still happened")
	rec = good.duplicate(true)
	rec.history[0].orders["beasts"] = "x"
	rep = GameSession.replay(rec, StubBattleResolver.new())
	assert_eq(rep.errors, ["Turn 1: The orders for 'beasts' should be a list, but the saved data has text there."])
	_assert_plain(rep.errors, "orders = \"x\"")
	# OrderBook on its own keeps the orders it can read.
	var errs := []
	var orders := OrderBook.orders_from_dict({"kingdom": [7, {"type": "move", "army": "kingdom-1", "to": "westwatch"}]}, errs)
	assert_eq(orders.kingdom.size(), 1)
	assert_eq(errs, ["Order 1 for 'kingdom' should be a group of named values, but the saved data has a number there."])


func test_replay_passes_on_why_a_record_cannot_load() -> void:
	# The review's repro: a starting state with units that are text.
	var rec := _record()
	rec.start_state.armies[0]["units"] = "x"
	var errs := []
	assert_eq(GameState.from_dict(rec.start_state, errs), null)
	var rep := GameSession.replay(rec)
	assert_eq(rep.state, null)
	assert_eq(rep.errors, errs, "replay passes the load's reason on")
	assert_eq(rep.errors, ["The 'units' field of army 'kingdom-1' should be a list, but the saved data has text there."])
	var cases := [
		[[], "The replay should be a group of named values, but the saved data has a list there."],
		[{"start_state": "x"}, "The saved game should be a group of named values, but the saved data has text there."],
		[{"start_state": _rulers(), "history": "x"}, "The 'history' field of the replay should be a list, but the saved data has text there."],
		[{"start_state": _rulers(), "history": ["x"]}, "Turn 1 of the replay should be a group of named values, but the saved data has text there."],
		[{"start_state": _rulers(), "history": [{"orders": "x"}]}, "The 'orders' field of turn 1 of the replay should be a group of named values, but the saved data has text there."],
	]
	for c in cases:
		rep = GameSession.replay(c[0])
		assert_eq(rep.state, null, c[1])
		assert_eq(rep.errors, [c[1]])


# --- every field ----------------------------------------------------------------------------------

## Every field of a saved M1 game and of a saved game with rulers, one at a time, gets each value of
## the wrong type: the load either works (numbers fall back to their default, see Serial.to_int) and
## the state resolves a turn, or it fails with plain reasons. Never a script error, never a silent null.
func test_every_field_of_the_wrong_type_loads_or_says_why() -> void:
	var problems := []
	var loads := 0
	for base in [GameState.new(5).to_dict(), _rulers()]:
		var paths := []
		_paths(base, [], paths)
		for path in paths:
			for value in WRONG:
				var d: Dictionary = base.duplicate(true)
				_set_path(d, path, value)
				var errs := []
				var s := GameState.from_dict(d, errs)
				loads += 1
				if s == null and errs.is_empty():
					problems.append("%s = %s: null without a reason" % [str(path), JSON.stringify(value)])
				elif s == null:
					for e in errs:
						var text := String(e)
						if not text.ends_with(".") or JARGON.any(func(w): return text.contains(w)):
							problems.append("%s = %s: %s" % [str(path), JSON.stringify(value), text])
				elif value is String:
					assert_true(TurnResolver.resolve(s, {}, 1).new_state != null, "%s loaded and resolves a turn" % str(path))
	assert_true(loads > 2000, "the sweep covers every field (%d loads)" % loads)
	assert_eq(problems.slice(0, 10), [], "%d problems" % problems.size())


func _paths(v, prefix: Array, out: Array) -> void:
	if v is Dictionary:
		for k in v:
			out.append(prefix + [k])
			_paths(v[k], prefix + [k], out)
	elif v is Array:
		for i in v.size():
			out.append(prefix + [i])
			_paths(v[i], prefix + [i], out)


func _set_path(d, path: Array, value) -> void:
	var at = d
	for i in path.size() - 1:
		at = at[path[i]]
	at[path.back()] = value


# --- a living ruler is always on the map (#49) ----------------------------------------------------

func test_a_living_ruler_without_a_ruler_army_fails_validation() -> void:
	# The review's repro: the King's army dropped from a saved game.
	var d := GameState.with_rulers(5, {"kingdom": "warrior_king"}, []).to_dict()
	d.armies = d.armies.filter(func(a): return not (a.has("ruler") and a.owner == "kingdom"))
	_assert_rejected(d, "King Corvane I (Aurel Crown) is alive but has no ruler's army on the map. A living ruler always travels as its own army, and a ruler whose army is gone is dead.", "a living King without his army")
	# The same on a live state, with nothing else wrong.
	var s := GameState.with_rulers(5, {}, [])
	s.armies.erase(RulerRules.ruler_army(s, "beasts"))
	var errs := []
	assert_false(s.validate(errs))
	assert_eq(errs.size(), 1, str(errs))
	assert_true(errs.size() == 1 and String(errs[0]).contains("(Thornmane Clans) is alive but has no ruler's army on the map."), str(errs))
	# Recording the death, as TurnResolver does right after the battle that removed the army, gives a
	# state the game can reach: a dead ruler with a successor due.
	RulerRules.record_death(s, "beasts", 1)
	errs.clear()
	assert_true(s.validate(errs), str(errs))
	assert_true(GameState.from_dict(s.to_dict(), errs) != null, "and it loads: %s" % [errs])
	# Without rulers the rule never applies.
	var m1 := GameState.new(5)
	m1.armies.clear()
	assert_true(m1.validate([]), "an M1 game with no armies left still validates")


## The moment a ruler's army is destroyed in battle: the death is recorded in the same pass, so the
## turn's new state validates and loads. A ruler lost with its side in a province, one lost on a
## border, and one that falls while its side wins.
func test_the_state_right_after_a_ruler_falls_in_battle_validates() -> void:
	# [case, battle resolver, the King moves to Ebonpeak (a swap: a border battle), units beside him]
	var cases := [
		["lost in a province", StubBattleResolver.new(), false, []],
		["lost on a border", StubBattleResolver.new(), true, []],
		["fell while winning", RulerFallsResolver.new(), false, ["knights", "knights"]],
	]
	for c in cases:
		# The King stands at Blackwood; a Tusker band at Ebonpeak, next door, attacks him there.
		var s := GameState.with_rulers(7, {"kingdom": "warrior_king"}, [])
		s.current_turn = 3
		var king := RulerRules.ruler_army(s, "kingdom")
		king.location = "blackwood"
		if not c[3].is_empty():
			var guard := Army.new()
			guard.id = "kingdom-8"
			guard.owner = "kingdom"
			guard.location = "blackwood"
			for type_id in c[3]:
				guard.units.append(Unit.new(TurnResolver.recruitable_type(s.find_faction("kingdom"), type_id), "kingdom"))
			s.armies.append(guard)
		var raider := Army.new()
		raider.id = "beasts-9"
		raider.owner = "beasts"
		raider.location = "ebonpeak"
		raider.units.append(Unit.new(TurnResolver.recruitable_type(s.find_faction("beasts"), "tuskers"), "beasts"))
		s.armies.append(raider)
		var orders := {"beasts": [MoveOrder.new(raider.id, "blackwood")]}
		if c[2]:
			orders["kingdom"] = [MoveOrder.new(king.id, "ebonpeak")]
		assert_true(s.validate([]), "%s: the fixture is valid" % c[0])
		var result := TurnResolver.resolve(s, orders, 11, c[1])
		if c[2]:
			assert_eq(result.events.filter(func(e): return e.type == "border_battle").size(), 1, "%s: a border battle" % c[0])
		var after: GameState = result.new_state
		assert_true(after != null, c[0])
		if after == null:
			continue
		assert_eq(result.events.filter(func(e): return e.type == "ruler_died").size(), 1, "%s: the King died" % c[0])
		assert_eq(RulerRules.ruler_army(after, "kingdom"), null, "%s: his army went with him" % c[0])
		assert_eq(after.find_faction("kingdom").ruler_status, RulerRules.DEAD, c[0])
		var errs := []
		assert_true(after.validate(errs), "%s: %s" % [c[0], errs])
		assert_true(after.deep_copy(errs) != null, "%s loads: %s" % [c[0], errs])


## The sweep: AI against AI with rulers (what `autoplay --rulers` plays), over several seeds, two with
## all-mandate builds whose rulers keep no power and die easily. Simulator.check_invariants runs
## GameState.validate on the state after every turn, so a turn whose state doesn't validate shows up
## as a violation, and session.state() itself reloads every state through from_dict.
func test_every_state_of_games_with_rulers_validates() -> void:
	var deaths := 0
	var turns := 0
	for game_seed in range(1, 7):
		var seats: Array = SEATS if game_seed % 2 == 1 else ["beasts", "kingdom"]
		var builds: Array = ["", ""]  # each seat rolls its preset, as an AI seat does
		if game_seed <= 2:
			builds = seats.map(func(fid): return "iron_crown" if fid == "kingdom" else "clan_moot")
		var r := Simulator.play_game(game_seed, seats, ["ai", "ai"], 30, Callable(), {"rulers": true, "builds": builds})
		assert_eq(r.violations, [], "seed %d: every turn's state validates" % game_seed)
		assert_eq(r.errors, [], "seed %d: no session errors" % game_seed)
		turns += int(r.turns)
		for fid in r.ruler.deaths:
			deaths += int(r.ruler.deaths[fid])
	assert_true(turns > 60, "the sweep plays real games (%d turns)" % turns)
	assert_true(deaths > 0, "rulers died in battle along the way (%d), and those turns validated too" % deaths)
