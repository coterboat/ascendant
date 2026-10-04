extends "res://tests/test_case.gd"
## M5-5 (#116): a magic game's state (design/M5_MAGIC_FOG.md §1.3, §6.2, §6.4, §14). with_magic and setup_magic, the
## Magic (M5 preview) box, the summoned creatures (loaded from MagicData, round-tripping, and left alone by Veteran
## Levies and Blood Levy), the checks M5-0 deferred to MagicData (spell and ritual ids, the Bastion cap, the mastery
## cap on an enchantment, a wolf's fading turn, the mage on the roster), and a recorded magic game replaying exactly.

const CROWN := "kingdom"
const CLANS := "beasts"
const Policies := preload("res://tools/autoplay/policies.gd")


func test_with_magic_is_the_paths_game_plus_magic() -> void:
	var s := GameState.with_magic(7)
	assert_true(s.magic and s.paths and RulerRules.has_rulers(s))
	assert_eq(s.current_turn, 0)
	for f in s.factions:
		var mage := TurnResolver.recruitable_type(f, String(MagicData.MAGES[f.id].id))
		assert_true(mage != null, "%s: its mage is on the roster" % f.id)
		assert_eq([mage.hp, mage.attack, mage.defense, mage.morale, mage.cost],
			[int(MagicData.MAGES[f.id].hp), int(MagicData.MAGES[f.id].attack), int(MagicData.MAGES[f.id].defense),
				int(MagicData.MAGES[f.id].morale), int(MagicData.MAGES[f.id].cost)])
		assert_eq(mage.trait_id, MagicData.MAGE_TRAIT)
		assert_false(mage.trait_description.is_empty(), "the unit card says what the trait does")
		assert_eq(f.spellbook, {})
		assert_eq(MagicRules.known_spells(s, f.id), [])
		assert_true(MagicRules.knows(s, f.id, "far_sight"), "Far Sight needs no research")
	var d := s.to_dict()
	assert_eq(d.magic, true)
	assert_eq(d.enchantments, [])
	var loaded := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	assert_true(loaded != null and loaded.magic)
	assert_eq(JSON.stringify(loaded.to_dict()), JSON.stringify(d), "a magic game saves and loads byte for byte")
	# The paths game underneath is the same as with_paths, apart from magic's fields.
	var p := GameState.with_paths(7)
	assert_eq(s.armies.size(), p.armies.size())
	assert_eq(s.find_faction(CROWN).ruler_type, p.find_faction(CROWN).ruler_type)
	# setup_magic needs paths and turn 0.
	var errors := []
	assert_false(GameState.with_rulers(7).setup_magic(errors))
	assert_true(errors.has("Magic needs paths (and paths need rulers). Set up paths first."), str(errors))
	var late := GameState.with_paths(7)
	late.current_turn = 2
	errors = []
	assert_false(late.setup_magic(errors))
	assert_true(errors.has("Magic is chosen before the game starts."), str(errors))
	# Report phases: the two magic phases join.
	assert_eq(GameSession.report_phases(s), GameSession.MAGIC_REPORT_PHASES)
	var both := GameState.with_magic(7)
	both.setup_sieges([])
	assert_eq(GameSession.report_phases(both).find("rituals"), GameSession.report_phases(both).find("orders") + 1)
	assert_eq(GameSession.report_phases(both).back(), "victory")
	assert_eq(GameSession.report_phases(both)[-2], "enchantments")


func test_the_magic_box_ticks_paths_and_rulers_and_starts_a_magic_game() -> void:
	var screen := load("res://ui/new_game_screen.tscn").instantiate() as NewGameScreen
	assert_false(screen.magic_on(), "off by default")
	assert_false(screen.config().has("magic"))
	screen.set_magic(true)
	assert_true(screen.magic_on())
	assert_true(screen.paths_on(), "ticking Magic ticks Paths")
	assert_true(screen.rulers_on(), "and Rulers")
	assert_eq(screen.config().get("magic"), true)
	screen.set_paths(false)
	assert_false(screen.magic_on(), "clearing Paths clears Magic")
	screen.set_magic(true)
	screen.set_rulers(false)
	assert_false(screen.magic_on(), "clearing Rulers clears Paths and Magic")
	screen.prefill({"players": [CROWN, CLANS], "seed": 5, "rulers": true, "paths": true, "magic": true})
	assert_true(screen.magic_on(), "a rematch of a magic game has magic")
	assert_true(String(screen.magic_toggle.tooltip_text).contains("Research spells, recruit mages and cast rituals. Needs Paths and Rulers, so they're on too."),
		screen.magic_toggle.tooltip_text)
	screen.free()
	var s := GameScreen.starting_state({"players": [CROWN, CLANS], "seed": 5, "rulers": true, "paths": true, "magic": true})
	assert_true(s != null and s.magic and s.paths)
	assert_false(s.sieges)
	var with_forts := GameScreen.starting_state({"players": [CROWN, CLANS], "seed": 5, "magic": true, "sieges": true})
	assert_true(with_forts.magic and with_forts.sieges, "magic with forts and sieges")
	var tithe := GameScreen.starting_state({"players": [CROWN, CLANS], "seed": 5, "magic": true,
		"builds": {CLANS: {"ruler": "fang_chieftain", "mandates": ["tithe_of_blood"]}}})
	assert_true(tithe.find_faction(CLANS).mandates.has("tithe_of_blood"), "a build with Tithe of Blood")
	assert_false(GameScreen.starting_state({"players": [CROWN, CLANS], "seed": 5, "paths": true}).magic)


func test_summoned_creatures_load_round_trip_and_mandates_leave_them_alone() -> void:
	# Veteran Levies (+2 hp to regular units) and the Blood Pact's Blood Levy (recruits arrive wounded).
	var s := GameState.with_magic(7, {CLANS: {"ruler": "fang_chieftain", "mandates": ["veteran_levies"]}})
	s = AscensionRules.with_nodes(s, CLANS, ["beasts_boar_hide", "beasts_raiding", "beasts_oath_blood"])
	assert_true(AscensionRules.blood_levy_divisor(s, CLANS) > 0, "Blood Levy is on")
	var pack := Army.new()
	pack.id = s.new_army_id(CLANS)
	pack.owner = CLANS
	pack.location = s.find_faction(CLANS).capital
	for i in 3:
		var wolf := Unit.new(MagicRules.summon_type("thornwolves"), CLANS)
		wolf.until = s.current_turn + 1 + int(MagicData.SPELLS.call_the_pack.duration)
		pack.units.append(wolf)
	var grove := Army.new()
	grove.id = s.new_army_id(CLANS)
	grove.owner = CLANS
	grove.location = s.find_faction(CLANS).capital
	grove.units.append(Unit.new(MagicRules.summon_type("greenwrath"), CLANS))
	s.armies.append_array([pack, grove])
	for u in [pack.units[0], grove.units[0]]:
		assert_eq(RulerRules.unit_max_hp(s, u), u.type.hp, "%s: Veteran Levies and path parts skip it" % u.type.name)
		assert_eq(AscensionRules.arrival_hp(s, CLANS, u.type, u.type.hp), u.type.hp, "%s: Blood Levy skips it" % u.type.name)
		assert_eq(AscensionRules.unit_parts(s, CLANS, u.type).hp, [])
	var tusker := Unit.new(TurnResolver.recruitable_type(s.find_faction(CLANS), "tuskers"), CLANS)
	assert_true(RulerRules.unit_max_hp(s, tusker) > tusker.type.hp, "a regular unit does get Veteran Levies")
	assert_true(s.validate([]))
	var d := s.to_dict()
	assert_false(_roster_ids(d, CLANS).has("thornwolves"), "never on a roster")
	var loaded := GameState.from_dict(JSON.parse_string(JSON.stringify(d)), [])
	assert_true(loaded != null, "the summoned types load from MagicData")
	var back := loaded.find_army(pack.id)
	assert_eq(back.units.map(func(u): return u.until), [pack.units[0].until, pack.units[0].until, pack.units[0].until])
	assert_true(back.units[0].type.summoned)
	assert_eq(loaded.find_army(grove.id).units[0].until, 0, "the Greenwrath stays until it falls")
	assert_eq(JSON.stringify(loaded.to_dict()), JSON.stringify(d), "they save again byte for byte")
	# A battle's unit mods skip them too.
	assert_eq(AutoBattleResolver._unit_mods({}, CLANS, MagicRules.summon_type("thornwolves"), s), {"attack": [], "defense": [], "hp": [], "morale": []})
	# Without magic the types don't load at all.
	var no_magic: Dictionary = JSON.parse_string(JSON.stringify(d))
	no_magic.erase("magic")
	assert_eq(GameState.from_dict(no_magic, []), null)


func test_the_checks_against_magic_data() -> void:
	var cases := [
		[func(s: GameState): s.find_faction(CROWN).spellbook = {"order": ["sunlance", "sunburst", "fireball"], "off": []},
			"lists 'fireball', which is not one of its battle spells"],
		[func(s: GameState): s.find_faction(CROWN).spellbook = {"order": ["sunlance", "sunburst"], "off": []}, "leaves out Shield of Law"],
		[func(s: GameState): s.find_faction(CROWN).bastions = ["westwatch", "highcrag", "rivermarch"],
			"has raised 3 Bastion forts, but a faction can raise at most %d, ever" % MagicData.BASTION_CAP],
		[func(s: GameState): s.enchantments = [_enchantment(CROWN, "sanctum_ward", "ward", 4)], "has a mastery bonus of 4, but mastery runs from 0 to +3"],
		[func(s: GameState): s.enchantments = [_enchantment(CROWN, "fireball", "curse", 0)], "names 'fireball', which is not a ritual in this game"],
		[func(s: GameState): s.enchantments = [_enchantment(CROWN, "sunlance", "curse", 0)], "names 'sunlance', which is not a ritual in this game"],
		[func(s: GameState): s.enchantments = [_enchantment(CROWN, "sanctum_ward", "curse", 0)], "is a curse, but Sanctum Ward is a ward"],
		[func(s: GameState): s.enchantments = [_enchantment(CROWN, "bloodrot", "curse", 0)], "a ritual of Blood, which the Aurel Crown can't cast"],
		[func(s: GameState): s.armies.append(_pack(s, 0)), "are summoned for a few turns, but these have no turn to fade on"],
		[func(s: GameState): s.armies.append(_wrath(s, 5)), "but the Greenwrath stays until it falls"],
		[func(s: GameState): s.find_faction(CLANS).unit_types = s.find_faction(CLANS).unit_types.filter(func(ut): return ut.id != "shamans"),
			"has magic but not its mage, the Thornmane Shamans, on its roster"],
		[func(s: GameState): s.find_faction(CLANS).unit_types.append(MagicRules.summon_type("thornwolves")), "summoned creatures are called by rituals, never recruited"],
	]
	for c in cases:
		var s := GameState.with_magic(7)
		s.find_faction(CROWN).enchant_counter = 1
		c[0].call(s)
		var errors := []
		assert_false(s.validate(errors), "refused: %s" % c[1])
		assert_true(errors.any(func(e): return String(e).contains(c[1])), "%s: %s" % [c[1], errors])
	# A view's stand-in pack carries 0 (§2.7, relaxed check 4): no fading turn is needed there.
	var view := GameState.with_magic(7)
	view.is_view = true
	var stand_in := _pack(view, 0)
	stand_in.seen = {"level": "glimpse", "turn": 0, "counts": {}, "total": {"shown": 5, "low": 3, "high": 7, "text": "about 5"}, "blessed": 0}
	view.armies.append(stand_in)
	var ok := []
	assert_true(view.validate(ok), str(ok))
	# A mage on a roster without magic.
	var m4 := GameState.with_paths(7)
	m4.find_faction(CROWN).unit_types.append(MagicRules.mage_type(CROWN))
	var errors := []
	assert_false(m4.validate(errors))
	assert_true(errors.any(func(e): return String(e).contains("can recruit Sunstone Adepts, but this game is played without magic")), str(errors))


func test_a_recorded_magic_game_replays_identically() -> void:
	var start := GameState.with_magic(11, {CLANS: {"ruler": "fang_chieftain", "mandates": ["tithe_of_blood", "iron_discipline"]}})
	var session := GameSession.new(start, [CROWN, CLANS], 11, AutoBattleResolver.new())
	var clans_ai = Policies.make("ai")
	clans_ai.configure(11, 1)
	var rng := SeededRNG.new(11 * 7919 + 2 * 104729)
	var turns := 0
	var recruited_mage := false
	while not session.is_over() and session.turns_played() < 14:
		if session.phase() == GameSession.Phase.HANDOFF:
			session.acknowledge_handoff()
		var fid := session.current_player()
		var state := session.state()
		if fid == CROWN:
			if turns == 0:
				assert_eq(session.queue_research("sunlance"), "")
				assert_eq(session.queue_spellbook(["shield_of_law", "sunlance", "sunburst"], ["sunburst"]), "")
			elif MagicRules.knows_a_spell(state, CROWN) and not recruited_mage:
				assert_eq(session.queue_recruit("adepts"), "")
				recruited_mage = true
			elif not MagicRules.known_spells(state, CROWN).is_empty() and AscensionRules.research_target(state, CROWN).is_empty():
				session.queue_research("shield_of_law")
		else:
			for o in clans_ai.orders(state, CLANS, rng):
				assert_eq(session.queue_order(o), "", "the computer's orders are legal in a magic game")
		session.end_turn()
		if fid == CLANS:
			turns += 1
	assert_true(recruited_mage, "the Crown recruited Adepts once it knew Sunlance")
	var rec := session.record()
	var replayed := GameSession.replay(JSON.parse_string(JSON.stringify(rec)), AutoBattleResolver.new())
	assert_eq(replayed.errors, [], "the record replays")
	assert_eq(JSON.stringify(replayed.state.to_dict()), JSON.stringify(session.state().to_dict()), "to the same state")
	assert_true(replayed.state.magic)
	assert_eq(replayed.state.find_faction(CROWN).spellbook, {"order": ["shield_of_law", "sunlance", "sunburst"], "off": ["sunburst"]})
	var has_adepts := false
	for a in replayed.state.armies:
		for u in a.units:
			if u.type.id == "adepts":
				has_adepts = true
	assert_true(has_adepts or session.is_over(), "the Adepts are on the map")
	# Saved and loaded through SaveGame, it is the same game.
	var restored := GameSession.from_record(JSON.parse_string(JSON.stringify(rec)), AutoBattleResolver.new())
	assert_eq(JSON.stringify(restored.state().to_dict()), JSON.stringify(session.state().to_dict()))


func _roster_ids(d: Dictionary, fid: String) -> Array:
	for f in d.factions:
		if f.id == fid:
			return f.unit_types.map(func(ut): return ut.id)
	return []


func _enchantment(fid: String, ritual: String, kind: String, bonus: int) -> Dictionary:
	return {"id": "%s-e1" % fid, "ritual": ritual, "faction": fid, "kind": kind, "province": "crownkeep", "armies": [],
		"cast_turn": 1, "until_turn": 2, "bonus": bonus, "ending": false}


func _pack(s: GameState, until: int) -> Army:
	var a := Army.new()
	a.id = s.new_army_id(CLANS)
	a.owner = CLANS
	a.location = s.find_faction(CLANS).capital
	var wolf := Unit.new(MagicRules.summon_type("thornwolves"), CLANS)
	wolf.until = until
	a.units.append(wolf)
	return a


func _wrath(s: GameState, until: int) -> Army:
	var a := Army.new()
	a.id = s.new_army_id(CLANS)
	a.owner = CLANS
	a.location = s.find_faction(CLANS).capital
	var w := Unit.new(MagicRules.summon_type("greenwrath"), CLANS)
	w.until = until
	a.units.append(w)
	return a
