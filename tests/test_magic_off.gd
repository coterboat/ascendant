extends "res://tests/test_case.gd"
## M5-5 (#116) acceptance, "with magic off" (design/M5_MAGIC_FOG.md §1.3): M1, M2 and M4 games are byte-identical to
## `main`. tests/fixtures/m5_base_records.json holds M1, M2 and M4 AI games that M5-0 recorded on main before magic
## existed (tools/replay_fixture.gd -- --m5; its note names the commit). Each replays turn by turn from its stored
## orders, and the AI policy loop, rerun from each game's spec, gives the computer's orders turn by turn. Without magic
## no magic key, phase, event, spell, mage or mandate of magic appears, and nothing magic can be ordered.

const FIXTURE := "res://tests/fixtures/m5_base_records.json"
const Fixture := preload("res://tools/replay_fixture.gd")
const CROWN := "kingdom"
const CLANS := "beasts"


func _games() -> Array:
	var data = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	assert_true(data is Dictionary, "the fixture loads")
	return data.get("games", []) if data is Dictionary else []


func test_the_base_records_replay_byte_identically_with_magic_off() -> void:
	var games := _games()
	assert_true(games.size() >= 6, "M1, M2 and M4 games")
	for g in games:
		var rec: Dictionary = g.record
		var errors := []
		var state := GameState.from_dict(rec.start_state, errors)
		assert_true(state != null, "%s: the start state loads: %s" % [g.name, ", ".join(errors)])
		if state == null:
			continue
		assert_false(state.magic, "%s has no magic" % g.name)
		for i in rec.history.size():
			var entry: Dictionary = rec.history[i]
			var result := TurnResolver.resolve(state, OrderBook.orders_from_dict(entry.orders, errors), Serial.to_int(entry.seed), AutoBattleResolver.new())
			state = result.new_state
			var d := Fixture.digest(state, result.events)
			assert_eq(d.state, g.turns[i].state, "%s turn %d: the state is byte-identical to main" % [g.name, i + 1])
			assert_eq(d.events, g.turns[i].events, "%s turn %d: the events are byte-identical to main" % [g.name, i + 1])
			for e in result.events:
				assert_ne(String(e.type), "research_sold", "%s: nothing is sold without magic" % g.name)
				assert_true(TurnResolver.phases(state).has(e.phase), "%s: a phase of its game" % e.type)
		assert_eq(JSON.stringify(state.to_dict()), g.final_state, "%s: the final state" % g.name)


func test_the_computer_gives_the_same_orders_with_magic_off() -> void:
	for g in _games():
		var again := Fixture.play(g.spec)
		var want: Array = g.record.history
		var got: Array = again.record.history
		assert_eq(got.size(), want.size(), "%s: as many turns" % g.name)
		for t in mini(got.size(), want.size()):
			assert_eq(JSON.stringify(JSON.parse_string(JSON.stringify(got[t].orders))), JSON.stringify(want[t].orders),
				"%s turn %d: the computer's orders are main's" % [g.name, t + 1])
		assert_eq(again.final_state, g.final_state, "%s: the same final state" % g.name)


func test_without_magic_nothing_magic_is_saved_listed_or_orderable() -> void:
	for s in [GameState.new(4), GameState.with_rulers(4), GameState.with_paths(4), GameState.with_sieges(4, {}, {"paths": true})]:
		assert_false(MagicRules.has_magic(s))
		var d: Dictionary = s.to_dict()
		assert_false(d.has("magic") or d.has("enchantments"), "no magic key")
		assert_false(GameSession.report_phases(s).has("rituals") or GameSession.report_phases(s).has("enchantments"))
		for f in s.factions:
			for key in ["spellbook", "enchant_counter", "bastions"]:
				assert_false(_faction_dict(d, f.id).has(key), "%s: no '%s'" % [f.id, key])
			var mage_id := String(MagicData.MAGES[f.id].id)
			assert_eq(TurnResolver.recruitable_type(f, mage_id), null, "%s: no mage on the roster" % f.id)
			assert_eq(MagicRules.known_spells(s, f.id), [])
			assert_false(MagicRules.knows(s, f.id, "far_sight"), "not even Far Sight")
			assert_eq(MagicRules.vision_grants(s, f.id), [])
			assert_true(MagicRules.can_heal(s, f.id, f.capital), "nobody is cursed")
			for nid in MagicRules.arcana_ids(f.id):
				var check := AscensionRules.check_research(s, f.id, nid)
				assert_false(check.is_empty(), "%s can't research %s" % [f.id, nid])
			assert_false(AscensionRules.available_nodes(s, f.id).any(func(n): return AscensionRules.is_arcana(String(n))), "no arcana on offer")
			assert_false(RulerRules.available_mandates(f.id, s).has(MagicRules.TITHE_OF_BLOOD), "no Tithe of Blood")
		var cast := OrderBook.check_order(s, CLANS, CastOrder.new("bloodrot", "beasts-1", "crownkeep"), [])
		assert_eq(String(cast.get("code", "")), "no_magic", "a cast order is refused")
		assert_true(String(cast.reason).contains("Magic (M5 preview)"), String(cast.reason))
		var book := OrderBook.check_order(s, CLANS, SpellbookOrder.new(["bloodbolt", "briar_snare"]), [])
		assert_eq(String(book.get("code", "")), "no_magic", "a spellbook order is refused")
	# Tithe of Blood: refused by sacrifice and by a build in a game without magic.
	var r := GameState.with_rulers(4, {CLANS: "blood_of_the_fang"})
	r.find_faction(CLANS).kept_power = 10
	assert_eq(String(RulerRules.sacrifice_check(r, CLANS, MagicRules.TITHE_OF_BLOOD).get("code", "")), "no_magic")
	var errors := []
	assert_eq(GameState.with_rulers(4, {CLANS: {"ruler": "fang_chieftain", "mandates": [MagicRules.TITHE_OF_BLOOD]}}, errors), null)
	assert_true(errors.any(func(e): return String(e).contains("a mandate of magic, but this game is played without magic")), str(errors))


func test_magic_orders_in_a_game_without_magic_are_rejected_and_change_nothing() -> void:
	var s := GameState.with_paths(4)
	var r := TurnResolver.resolve(s, {CLANS: [SpellbookOrder.new(["bloodbolt", "briar_snare"]), CastOrder.new("bloodrot", "beasts-1", "crownkeep")]}, 1)
	var rejected: Array = r.events.filter(func(e): return e.type == "order_rejected")
	assert_eq(rejected.size(), 2)
	assert_eq(rejected.map(func(e): return String(e.cause)), ["no_magic", "no_magic"])
	for e in rejected:
		assert_false(String(e.text).contains("_"), "no raw id: %s" % e.text)
	var plain := TurnResolver.resolve(s, {}, 1)
	assert_eq(JSON.stringify(r.new_state.to_dict()), JSON.stringify(plain.new_state.to_dict()), "the state is as if they were never given")


func _faction_dict(d: Dictionary, fid: String) -> Dictionary:
	for f in d.factions:
		if f.id == fid:
			return f
	return {}
