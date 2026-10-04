extends "res://tests/test_case.gd"
## M5-0 (#111) acceptance, the scaffold for magic and fog of war (design/M5_MAGIC_FOG.md §14, §18):
## - every new state field round-trips through to_dict, from_dict and JSON: GameState.fog, magic, enchantments and
##   is_view; Faction.spellbook, enchant_counter and bastions; UnitType.summoned; Unit.until; Army.seen. (§14's
##   army_counters is #94's next_army_ids, already saved and tested by test_army_numbers.)
## - each is saved only when set and refused without its gate, with a plain reason;
## - a state without them saves byte-identically to `main`: tests/fixtures/m5_base_records.json holds M1, M2 and M4
##   AI games that tools/replay_fixture.gd (`-- --m5`) recorded on main before these fields existed (its note names
##   the commit), and each replays turn by turn, and plays again order for order from its spec;
## - the stubs MagicRules.vision_grants and RulerRules.ruler_alive.

const FIXTURE := "res://tests/fixtures/m5_base_records.json"
const Fixture := preload("res://tools/replay_fixture.gd")
const CROWN := "kingdom"
const CLANS := "beasts"

## Every key the M5 fields add, by where it is saved. None of them may appear in a game without M5.
const STATE_KEYS := ["fog", "magic", "enchantments", "is_view"]
const FACTION_KEYS := ["spellbook", "enchant_counter", "bastions"]


func _fixture() -> Dictionary:
	var data = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	assert_true(data is Dictionary, "the fixture loads")
	return data if data is Dictionary else {}


## The keys of the M5 fields found anywhere in a saved state (to_dict output): [] for a game without M5.
func _m5_keys(d: Dictionary) -> Array:
	var found := []
	for key in STATE_KEYS:
		if d.has(key):
			found.append(key)
	for f in d.get("factions", []):
		for key in FACTION_KEYS:
			if f.has(key):
				found.append("faction %s: %s" % [f.id, key])
		for ut in f.unit_types + [f.commander_type]:
			if ut.has("summoned"):
				found.append("unit type %s: summoned" % ut.get("id", ""))
	for a in d.get("armies", []):
		if a.has("seen"):
			found.append("army %s: seen" % a.id)
		for u in a.units + [a.commander, a.get("ruler", {})]:
			if u.has("until"):
				found.append("army %s: until" % a.id)
	return found


## A JSON round trip of `s`'s save: {"data": the parsed save, "loaded": GameState or null, "errors": [...]}.
func _round_trip(s: GameState) -> Dictionary:
	var data = JSON.parse_string(JSON.stringify(s.to_dict()))
	var errors := []
	var loaded := GameState.from_dict(data, errors)
	return {"data": data, "loaded": loaded, "errors": errors}


## Loads `d` (a save) and returns its errors; the load must fail.
func _refused(d: Dictionary, why: String) -> Array:
	var errors := []
	var loaded := GameState.from_dict(JSON.parse_string(JSON.stringify(d)), errors)
	assert_eq(loaded, null, "refused: %s" % why)
	assert_false(errors.is_empty(), "with a reason: %s" % why)
	return errors


func _has_error(errors: Array, text: String) -> bool:
	return errors.any(func(e): return String(e).contains(text))


func _faction_dict(d: Dictionary, fid: String) -> Dictionary:
	for f in d.factions:
		if f.id == fid:
			return f
	return {}


func _army_dict(d: Dictionary, aid: String) -> Dictionary:
	for a in d.armies:
		if a.id == aid:
			return a
	return {}


## A summoned creature's type for the tests (MagicData.SUMMONS is M5-5's): Thornwolves' numbers from §6.2.
func _wolves() -> UnitType:
	var ut := UnitType.new()
	ut.id = "thornwolves"
	ut.name = "Thornwolves"
	ut.hp = 9
	ut.attack = 11
	ut.defense = 4
	ut.morale = 8
	ut.cost = 0
	ut.summoned = true
	return ut


## A paths game on turn 3 with magic on and every magic field set: spellbooks, enchantment counts, a Bastion fort,
## one enchantment of each kind (sorted by id, numbered from each faction's count), and a summoned pack.
func _magic_state() -> GameState:
	var s := GameState.with_paths(5)
	s.current_turn = 3
	s.magic = true
	var crown := s.find_faction(CROWN)
	var clans := s.find_faction(CLANS)
	var home := crown.capital
	var border: String = s.find_province(home).neighbors[0]
	crown.spellbook = {"order": ["sunburst", "sunlance", "shield_of_law"], "off": ["shield_of_law"]}
	crown.enchant_counter = 3
	crown.bastions = [border]
	clans.enchant_counter = 2
	var crown_army := ""
	for a in s.armies:
		if a.owner == CROWN and a.ruler == null:
			crown_army = a.id
	s.enchantments = [
		{"id": "beasts-e1", "ritual": "bloodrot", "faction": CLANS, "kind": "curse", "province": home, "armies": [],
			"cast_turn": 2, "until_turn": 4, "bonus": 1, "ending": true},
		{"id": "beasts-e2", "ritual": "blood_moon", "faction": CLANS, "kind": "global", "province": "", "armies": [],
			"cast_turn": 3, "until_turn": 5, "bonus": 0, "ending": false},
		{"id": "kingdom-e1", "ritual": "dawn_blessing", "faction": CROWN, "kind": "blessing", "province": home,
			"armies": [crown_army], "cast_turn": 3, "until_turn": 5, "bonus": 2, "ending": false},
		{"id": "kingdom-e2", "ritual": "sanctum_ward", "faction": CROWN, "kind": "ward", "province": home, "armies": [],
			"cast_turn": 3, "until_turn": 4, "bonus": 0, "ending": false},
		{"id": "kingdom-e3", "ritual": "far_sight", "faction": CROWN, "kind": "sight", "province": clans.capital,
			"armies": [], "cast_turn": 3, "until_turn": 5, "bonus": 0, "ending": false},
	]
	var wolves := _wolves()
	clans.unit_types.append(wolves)  # a summoned type loads from the faction's known types (M5-5 adds MagicData's)
	var pack := Army.new()
	pack.id = s.new_army_id(CLANS)
	pack.owner = CLANS
	pack.location = clans.capital
	for i in 3:
		var u := Unit.new(wolves, CLANS)
		u.until = s.current_turn + 4
		pack.units.append(u)
	pack.units.append(Unit.new(wolves, CLANS))  # until 0: a creature that stays until it falls (the Greenwrath's rule)
	s.armies.append(pack)
	return s


## A player's view on turn 2 (FogRules.view_state is M5-1's): the Clans' starting army as a glimpsed stand-in.
func _view_state() -> GameState:
	var s := GameState.new(5)
	s.current_turn = 2
	s.fog = true
	s.is_view = true
	for a in s.armies:
		if a.owner == CLANS:
			a.seen = {"level": "glimpse", "turn": 2, "blessed": 0,
				"counts": {"tuskers": {"shown": 5, "low": 3, "high": 7, "text": "about 5"}},
				"total": {"shown": 5, "low": 3, "high": 7, "text": "about 5"}}
	return s


# --- the fixture: recorded on main, replayed here --------------------------------------------------

func test_the_fixture_holds_m1_m2_and_m4_games_recorded_on_main() -> void:
	var data := _fixture()
	var note := String(data.get("note", ""))
	assert_true(note.contains("Recorded on main (") and not note.contains("commit not given"), "the note names main's commit: %s" % note)
	var games: Array = data.get("games", [])
	assert_eq(games.map(func(g): return g.name), Fixture.M5_GAMES.map(func(g): return g.name), "the games tools/replay_fixture.gd -- --m5 plays")
	var kinds := {"M1": 0, "M2": 0, "M4": 0}
	for g in games:
		var start := GameState.from_dict(g.record.start_state, [])
		assert_true(start != null, "%s: its start state loads" % g.name)
		if start == null:
			continue
		var kind := "M4" if start.paths else ("M2" if RulerRules.has_rulers(start) else "M1")
		var spec_kind := "M4" if bool(g.spec.get("paths", false)) else ("M2" if bool(g.spec.rulers) else "M1")
		assert_eq(kind, spec_kind, "%s is the game its spec says" % g.name)
		kinds[kind] += 1
		assert_eq(_m5_keys(g.record.start_state), [], "%s: main saved no M5 key" % g.name)
		assert_true(g.record.history.size() > 0 and g.record.history.size() == g.turns.size(), "%s: a digest for every turn" % g.name)
	for kind in kinds:
		assert_true(kinds[kind] >= 1, "the fixture has %s games" % kind)


func test_the_fixture_replays_byte_identically_turn_by_turn() -> void:
	for g in _fixture().get("games", []):
		var rec: Dictionary = g.record
		var errors := []
		var state := GameState.from_dict(rec.start_state, errors)
		assert_true(state != null, "%s: the start state loads: %s" % [g.name, ", ".join(errors)])
		if state == null:
			continue
		for i in rec.history.size():
			var entry: Dictionary = rec.history[i]
			var result := TurnResolver.resolve(state, OrderBook.orders_from_dict(entry.orders, errors), Serial.to_int(entry.seed), AutoBattleResolver.new())
			state = result.new_state
			var d := Fixture.digest(state, result.events)
			assert_eq(d.state, g.turns[i].state, "%s turn %d: the state is byte-identical to main" % [g.name, i + 1])
			assert_eq(d.events, g.turns[i].events, "%s turn %d: the events are byte-identical to main" % [g.name, i + 1])
			assert_eq(_m5_keys(state.to_dict()), [], "%s turn %d: no M5 key" % [g.name, i + 1])
		assert_eq(errors, [], "%s: every order loads" % g.name)
		assert_eq(JSON.stringify(state.to_dict()), g.final_state, "%s: the final state" % g.name)
		var replayed := GameSession.replay(JSON.parse_string(JSON.stringify(rec)), AutoBattleResolver.new())
		assert_eq(replayed.errors, [], "%s: GameSession.replay reads the record" % g.name)
		assert_eq(JSON.stringify(replayed.state.to_dict()), g.final_state, "%s: GameSession.replay agrees" % g.name)


func test_the_computer_plays_each_fixture_game_again_order_for_order() -> void:
	# The AI half (§1.3): the AI policy loop of tools/replay_fixture.gd, rerun from each game's spec, gives the orders
	# main gave, turn by turn. An AI change outside M5 (#131, say) re-records the fixture in its own commit.
	for g in _fixture().get("games", []):
		var again := Fixture.play(g.spec)
		var want: Array = g.record.history
		var got: Array = again.record.history
		assert_eq(got.size(), want.size(), "%s: as many turns" % g.name)
		for t in mini(got.size(), want.size()):
			assert_eq(JSON.stringify(JSON.parse_string(JSON.stringify(got[t].orders))), JSON.stringify(want[t].orders),
				"%s turn %d: the computer gives the orders it gave on main" % [g.name, t + 1])
			assert_eq(again.turns[t], g.turns[t], "%s turn %d: the same digests" % [g.name, t + 1])
		assert_eq(again.final_state, g.final_state, "%s: the same final state" % g.name)


func test_states_without_the_fields_save_byte_identically_to_main() -> void:
	# The fixture's starting saves were written on main: today's setups write the same bytes.
	for g in _fixture().get("games", []):
		var rec: Dictionary = g.record
		var seed_value := Serial.to_int(rec.game_seed)
		var start: GameState
		if rec.has("builds"):
			var builds := {}
			for fid in rec.builds:
				builds[fid] = {"ruler": rec.builds[fid].ruler, "mandates": rec.builds[fid].mandates}
			start = GameState.with_paths(seed_value, builds) if bool(rec.start_state.get("paths", false)) else GameState.with_rulers(seed_value, builds)
		else:
			start = GameState.new(seed_value)
		var now := JSON.stringify(JSON.parse_string(JSON.stringify(start.to_dict())))  # numbers as the fixture's JSON holds them
		assert_eq(now, JSON.stringify(rec.start_state), "%s: the starting save is byte-identical to main" % g.name)
		# A save main wrote loads and saves again to the same bytes.
		var final_state := GameState.from_dict(JSON.parse_string(g.final_state), [])
		assert_true(final_state != null, "%s: main's final save loads" % g.name)
		if final_state != null:
			assert_eq(JSON.stringify(final_state.to_dict()), g.final_state, "%s: and saves again byte for byte" % g.name)
	# Every setup, sieges included, saves no M5 key, and the fields at their defaults change nothing.
	for s in [GameState.new(4), GameState.with_rulers(4), GameState.with_paths(4), GameState.with_sieges(4), GameState.with_sieges(4, {}, {"paths": true})]:
		var before := JSON.stringify(s.to_dict())
		assert_eq(_m5_keys(s.to_dict()), [], "no M5 key")
		assert_false(s.fog or s.magic or s.is_view, "every switch is off")
		assert_eq(s.enchantments, [])
		for f in s.factions:
			assert_eq([f.spellbook, f.enchant_counter, f.bastions], [{}, 0, []], "%s: the magic fields at their defaults" % f.id)
			for ut in f.unit_types:
				assert_false(ut.summoned)
		for a in s.armies:
			assert_eq(a.seen, {})
			for u in a.units:
				assert_eq(u.until, 0)
		var copy: GameState = s.deep_copy()
		assert_eq(JSON.stringify(copy.to_dict()), before, "a copy saves the same bytes")


# --- each field round-trips --------------------------------------------------------------------------

func test_fog_round_trips_and_is_saved_only_when_set() -> void:
	for s in [GameState.new(5), GameState.with_rulers(5), GameState.with_paths(5)]:
		var plain := JSON.stringify(s.to_dict())
		s.fog = true
		var d: Dictionary = s.to_dict()
		assert_eq(d.get("fog"), true, "a fog game carries 'fog'")
		var r := _round_trip(s)
		assert_eq(r.errors, [])
		assert_true(r.loaded != null and r.loaded.fog, "and loads with fog on")
		if r.loaded != null:
			assert_eq(JSON.stringify(r.loaded.to_dict()), JSON.stringify(d), "and saves again byte for byte")
			assert_true(s.deep_copy().fog, "deep_copy keeps it")
		s.fog = false
		assert_eq(JSON.stringify(s.to_dict()), plain, "off again, the save is the plain game's")


func test_magic_enchantments_and_the_factions_magic_fields_round_trip() -> void:
	var s := _magic_state()
	var d := s.to_dict()
	assert_eq(d.get("magic"), true)
	assert_eq(d.enchantments, s.enchantments, "every enchantment, in id order")
	for e in d.enchantments:
		assert_eq(e.keys(), MagicRules.ENCHANTMENT_KEYS, "%s: exactly the fields of §6.4" % e.id)
	var crown := _faction_dict(d, CROWN)
	assert_eq(crown.spellbook, {"order": ["sunburst", "sunlance", "shield_of_law"], "off": ["shield_of_law"]})
	assert_eq(crown.enchant_counter, 3)
	assert_eq(crown.bastions, s.find_faction(CROWN).bastions)
	assert_eq(_faction_dict(d, CLANS).spellbook, {}, "the default spellbook is saved as {}")
	var r := _round_trip(s)
	assert_eq(r.errors, [], "the magic game loads")
	var loaded: GameState = r.loaded
	assert_true(loaded != null)
	if loaded == null:
		return
	assert_true(loaded.magic)
	assert_eq(JSON.stringify(loaded.enchantments), JSON.stringify(s.enchantments), "the enchantments, numbers as ints")
	for e in loaded.enchantments:
		for key in ["cast_turn", "until_turn", "bonus"]:
			assert_eq(typeof(e[key]), TYPE_INT, "%s: '%s' loads as an int" % [e.id, key])
		assert_eq(typeof(e.ending), TYPE_BOOL)
	for fid in [CROWN, CLANS]:
		var want := s.find_faction(fid)
		var got := loaded.find_faction(fid)
		assert_eq(got.spellbook, want.spellbook, "%s: the spellbook" % fid)
		assert_eq(got.enchant_counter, want.enchant_counter, "%s: the enchantment count" % fid)
		assert_eq(typeof(got.enchant_counter), TYPE_INT)
		assert_eq(got.bastions, want.bastions, "%s: the Bastion forts" % fid)
	assert_eq(JSON.stringify(loaded.to_dict()), JSON.stringify(d), "it saves again byte for byte")
	assert_eq(JSON.stringify(s.deep_copy().to_dict()), JSON.stringify(d), "deep_copy is exact")
	# With magic off the same state writes none of the game's or the factions' magic keys (and would not load: the
	# gate test below).
	s.magic = false
	var off := s.to_dict()
	assert_false(off.has("magic") or off.has("enchantments"), "no magic or enchantments key without magic")
	for f in off.factions:
		for key in FACTION_KEYS:
			assert_false(f.has(key), "%s: no '%s' key without magic" % [f.id, key])


func test_summoned_types_and_until_round_trip() -> void:
	var ut := _wolves()
	var ut_d := ut.to_dict()
	assert_eq(ut_d.get("summoned"), true, "a summoned type carries 'summoned'")
	var ut_back := UnitType.from_dict(JSON.parse_string(JSON.stringify(ut_d)))
	assert_true(ut_back.summoned)
	assert_eq(ut_back.to_dict(), ut_d)
	ut.summoned = false
	assert_false(ut.to_dict().has("summoned"), "any other type saves as before")
	var u := Unit.new(_wolves(), CLANS)
	u.until = 7
	var u_d := u.to_dict()
	assert_eq(u_d.get("until"), 7)
	var u_back := Unit.from_dict(JSON.parse_string(JSON.stringify(u_d)), {"thornwolves": _wolves()})
	assert_eq(u_back.until, 7)
	assert_eq(typeof(u_back.until), TYPE_INT)
	u.until = 0
	assert_false(u.to_dict().has("until"), "until 0 is not saved")
	# In a game: the pack's three wolves fade on turn 7, the fourth creature stays (until 0, no key).
	var s := _magic_state()
	var r := _round_trip(s)
	assert_eq(r.errors, [])
	var pack: Army = s.armies.back()
	var saved := _army_dict(r.data, pack.id)
	assert_eq(saved.units.map(func(x): return int(x.get("until", 0))), [7, 7, 7, 0])
	assert_eq(saved.units.map(func(x): return x.has("until")), [true, true, true, false])
	assert_true(_faction_dict(r.data, CLANS).unit_types.back().get("summoned", false), "the summoned type is saved as one")
	if r.loaded != null:
		var back: Army = r.loaded.find_army(pack.id)
		assert_eq(back.units.map(func(x): return x.until), [7, 7, 7, 0])
		assert_true(back.units.all(func(x): return x.type.summoned))


func test_the_view_flag_and_view_notes_round_trip() -> void:
	var s := _view_state()
	var d := s.to_dict()
	assert_eq(d.get("is_view"), true)
	var note: Dictionary = _army_dict(d, "beasts-1").seen
	assert_eq(note.keys(), Army.SEEN_KEYS, "the note's fixed shape, in order")
	assert_false(_army_dict(d, "kingdom-1").has("seen"), "the viewer's own army carries no note")
	var r := _round_trip(s)
	assert_eq(r.errors, [], "the view loads")
	var loaded: GameState = r.loaded
	assert_true(loaded != null and loaded.is_view and loaded.fog)
	if loaded == null:
		return
	var back: Dictionary = loaded.find_army("beasts-1").seen
	assert_eq(JSON.stringify(back), JSON.stringify(s.find_army("beasts-1").seen), "the note, numbers as ints")
	assert_eq(typeof(back.turn), TYPE_INT)
	assert_eq(typeof(back.total.shown), TYPE_INT)
	assert_eq(typeof(back.counts.tuskers.low), TYPE_INT)
	assert_eq(JSON.stringify(loaded.to_dict()), JSON.stringify(d), "it saves again byte for byte")
	assert_eq(JSON.stringify(s.deep_copy().to_dict()), JSON.stringify(d), "a view deep-copies exactly (§2.7)")


# --- the gates and the checks ------------------------------------------------------------------------

func test_each_field_is_refused_without_its_gate() -> void:
	var magic := _magic_state()
	var full: Dictionary = JSON.parse_string(JSON.stringify(magic.to_dict()))
	# Strip the switch and keep the fields: every one is named.
	var d: Dictionary = full.duplicate(true)
	d.erase("magic")
	var errors := _refused(d, "magic fields without magic")
	assert_true(_has_error(errors, "This game has 5 enchantments, but it is played without magic."), str(errors))
	assert_true(_has_error(errors, "has a battle spellbook, but this game is played without magic."), str(errors))
	assert_true(_has_error(errors, "has begun 3 enchantments, but this game is played without magic."), str(errors))
	assert_true(_has_error(errors, "has raised Bastion forts, but this game is played without magic."), str(errors))
	assert_true(_has_error(errors, "has the summoned creature Thornwolves, but this game is played without magic"), str(errors))
	assert_true(_has_error(errors, "a summoned creature, but this game is played without magic."), str(errors))
	# A unit that fades, in a game without magic.
	var m1: Dictionary = JSON.parse_string(JSON.stringify(GameState.new(5).to_dict()))
	m1.armies[0].units[0]["until"] = 4
	assert_true(_has_error(_refused(m1, "until without magic"), "a summoned creature, but this game is played without magic."))
	# Magic needs paths.
	var no_paths: Dictionary = JSON.parse_string(JSON.stringify(GameState.with_rulers(5).to_dict()))
	no_paths["magic"] = true
	assert_true(_has_error(_refused(no_paths, "magic without paths"), "magic needs paths"))
	# A view note in a true state.
	var truth: Dictionary = JSON.parse_string(JSON.stringify(_view_state().to_dict()))
	truth.erase("is_view")
	assert_true(_has_error(_refused(truth, "a view note in the true state"), "Army 'beasts-1' carries a view note, but this is the true game"))


func test_wrong_types_are_refused_with_plain_reasons() -> void:
	var base: Dictionary = JSON.parse_string(JSON.stringify(_magic_state().to_dict()))
	var cases := [
		[func(d): d["fog"] = "yes", "The 'fog' field of the saved game should be true or false, but the saved data has text there."],
		[func(d): d["is_view"] = 1, "The 'is_view' field of the saved game should be true or false"],
		[func(d): d["magic"] = [], "The 'magic' field of the saved game should be true or false, but the saved data has a list there."],
		[func(d): d["enchantments"] = "none", "The 'enchantments' field of the saved game should be a list"],
		[func(d): d.enchantments[0] = 3, "Enchantment 1 of the saved game should be a group of named values"],
		[func(d): d.enchantments[0]["ritual"] = 4, "The 'ritual' field of enchantment 'beasts-e1' should be text"],
		[func(d): d.enchantments[0]["armies"] = "all", "The 'armies' field of enchantment 'beasts-e1' should be a list"],
		[func(d): d.enchantments[0]["ending"] = "yes", "The 'ending' field of enchantment 'beasts-e1' should be true or false"],
		[func(d): _faction_dict(d, CROWN)["spellbook"] = ["sunlance"], "The 'spellbook' field of faction 'kingdom' should be a group of named values"],
		[func(d): _faction_dict(d, CROWN).spellbook["off"] = "sunlance", "The 'off' field of the spellbook of faction 'kingdom' should be a list"],
		[func(d): _faction_dict(d, CROWN)["bastions"] = "westwatch", "The 'bastions' field of faction 'kingdom' should be a list"],
		[func(d): _faction_dict(d, CLANS).unit_types.back()["summoned"] = "yes", "The 'summoned' field of unit type"],
		[func(d): d.armies[0]["seen"] = [], "The 'seen' field of army 'kingdom-1' should be a group of named values"],
	]
	for c in cases:
		var d: Dictionary = base.duplicate(true)
		c[0].call(d)
		var errors := _refused(d, c[1])
		assert_true(_has_error(errors, c[1]), "%s: %s" % [c[1], errors])


func test_bad_magic_values_are_refused_with_plain_reasons() -> void:
	var cases := [
		[func(s: GameState): s.enchantments[0].faction = "elves", "Enchantment 'beasts-e1' belongs to 'elves', which is not a faction in this game."],
		[func(s: GameState): s.enchantments[1].kind = "summon", "Enchantment 'beasts-e2' is of kind 'summon', but an enchantment is a blessing, a ward, a curse, a global or a sight."],
		[func(s: GameState): s.enchantments[1].province = "crownkeep", "Enchantment 'beasts-e2' is global, so it lies on no province, but it names 'crownkeep'."],
		[func(s: GameState): s.enchantments[3].province = "atlantis", "Enchantment 'kingdom-e2' lies on 'atlantis', which is not a province on this map."],
		[func(s: GameState): s.enchantments[3].armies = ["kingdom-1"], "Enchantment 'kingdom-e2' lists armies, but only a blessing is on armies."],
		[func(s: GameState): s.enchantments[2].armies = ["beasts-1"], "Enchantment 'kingdom-e1' blesses army 'beasts-1', which is not an army of 'kingdom' in this game."],
		[func(s: GameState): s.enchantments[2].until_turn = 2, "Enchantment 'kingdom-e1' lasts through turn 2, before turn 3, when it was cast."],
		[func(s: GameState): s.enchantments[3].until_turn = 3, "Enchantment 'kingdom-e2' lasted through turn 3, and turn 3 is over, so it should have ended."],
		[func(s: GameState): s.enchantments[3].cast_turn = 0, "Enchantment 'kingdom-e2' was cast on turn 0, but turns count from 1."],
		[func(s: GameState): s.enchantments[2].bonus = -1, "Enchantment 'kingdom-e1' has a mastery bonus of -1, but a bonus is never below 0."],
		[func(s: GameState): s.enchantments[3].ending = true, "Enchantment 'kingdom-e2' is ending early, but only a curse is ended early (by a ward)."],
		[func(s: GameState): s.enchantments.reverse(), "The enchantments are kept in id order, but"],
		[func(s: GameState): s.enchantments[1].id = "beasts-e1", "Two enchantments share the id 'beasts-e1'."],
		[func(s: GameState): s.find_faction(CROWN).enchant_counter = 2, "Enchantment 'kingdom-e3' is numbered 3, but Aurel Crown has begun 2 enchantments."],
		[func(s: GameState): s.find_faction(CROWN).spellbook = {"order": ["sunlance", "sunlance"], "off": []}, "Aurel Crown's battle spellbook lists 'sunlance' twice."],
		[func(s: GameState): s.find_faction(CROWN).spellbook = {"order": ["sunlance"], "off": ["bloodbolt"]}, "Aurel Crown's battle spellbook switches off 'bloodbolt', which is not in its order."],
		[func(s: GameState): s.find_faction(CROWN).bastions = ["atlantis"], "Aurel Crown raised a Bastion fort at 'atlantis', which is not a province on this map."],
		[func(s: GameState): s.find_faction(CROWN).bastions.append(s.find_faction(CROWN).bastions[0]), "lists its Bastion fort at"],
		[func(s: GameState): s.armies[0].units[0].until = 6, "only summoned creatures fade."],
		[func(s: GameState): s.armies.back().units[0].until = 3, "should have faded at the end of turn 3, and turn 3 is over."],
	]
	for c in cases:
		var s := _magic_state()
		c[0].call(s)
		var errors := []
		assert_false(s.validate(errors), "refused: %s" % c[1])
		assert_true(_has_error(errors, c[1]), "%s: %s" % [c[1], errors])
		assert_eq(GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())), []), null, "and does not load: %s" % c[1])
	var ok := []
	assert_true(_magic_state().validate(ok), "the magic test state itself is valid: %s" % [ok])


func test_bad_view_notes_are_refused_with_plain_reasons() -> void:
	var cases := [
		[func(n: Dictionary): n.level = "peeked", "The view note of army 'beasts-1' has the level 'peeked', but a note is clear, glimpse or memory."],
		[func(n: Dictionary): n.erase("blessed"), "The view note of army 'beasts-1' has no 'blessed'."],
		[func(n: Dictionary): n["gold"] = 40, "The view note of army 'beasts-1' holds 'gold', which a view note never holds."],
		[func(n: Dictionary): n.turn = -1, "The view note of army 'beasts-1' has 'turn' -1, but it is a whole number from 0."],
		[func(n: Dictionary): n.total.erase("high"), "The view note of army 'beasts-1' has no 'high' in its total."],
		[func(n: Dictionary): n.counts.tuskers["true_count"] = 4, "holds 'true_count' in its count of 'tuskers', which a round count never holds."],
		[func(n: Dictionary): n.counts = [], "has counts that are not a group of round counts by unit type."],
	]
	for c in cases:
		var s := _view_state()
		c[0].call(s.find_army("beasts-1").seen)
		var errors := []
		assert_false(s.validate(errors), "refused: %s" % c[1])
		assert_true(_has_error(errors, c[1]), "%s: %s" % [c[1], errors])
	var ok := []
	assert_true(_view_state().validate(ok), "the view test state itself is valid: %s" % [ok])


# --- the stubs ---------------------------------------------------------------------------------------

func test_vision_grants_is_a_stub_that_grants_nothing() -> void:
	for s in [GameState.new(5), GameState.with_rulers(5), GameState.with_paths(5), _magic_state()]:
		for f in s.factions:
			assert_eq(MagicRules.vision_grants(s, f.id), [], "%s sees nothing through magic until Far Sight (M5-6)" % f.id)


func test_ruler_alive_reads_the_ruler_status_alone() -> void:
	var m1 := GameState.new(5)
	assert_false(RulerRules.ruler_alive(m1, CROWN), "no ruler in an M1 game")
	var s := GameState.with_rulers(5)
	assert_false(RulerRules.ruler_alive(s, "elves"), "no such faction")
	for fid in [CROWN, CLANS]:
		assert_true(RulerRules.ruler_alive(s, fid))
		assert_eq(RulerRules.ruler_alive(s, fid), RulerRules.has_living_ruler(s, fid), "on the map, both agree")
	# Off the map (as a view that doesn't know where the rival's ruler is): alive, but not has_living_ruler.
	s.armies = s.armies.filter(func(a): return not (a.owner == CLANS and a.ruler != null))
	assert_true(RulerRules.ruler_alive(s, CLANS), "alive, location unknown")
	assert_false(RulerRules.has_living_ruler(s, CLANS), "has_living_ruler is unchanged: it needs the army")
	s.find_faction(CLANS).ruler_status = RulerRules.DEAD
	assert_false(RulerRules.ruler_alive(s, CLANS), "a dead ruler")
