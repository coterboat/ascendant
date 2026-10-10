extends "res://tests/test_case.gd"
## ARM-1 step 1 (design/ARM1_SPLIT_MERGE.md §2.1): per-unit statuses. `Unit.statuses` (saved only when not empty),
## the `UnitStatus` registry (fields, validation, clearing, tooltip, codex and fog hooks), the helpers (`has_status`,
## `add_status`, `remove_status`, `UnitStatus.clear_source`) and the first kind, `outside_blessing`, with its validation.

const CROWN := "kingdom"
const CLANS := "beasts"


# --- fixtures ---------------------------------------------------------------------------------------

## A magic game with a Dawn Blessing (the enchantment's id returned) on the Crown's first army.
func _blessed_game() -> Dictionary:
	var s := GameState.with_magic(7, {CROWN: "regents_court", CLANS: "blood_of_the_fang"})
	assert_true(s != null, "the magic game starts")
	var army := _field(s, CROWN)
	var began := MagicRules._begin(s, CROWN, "dawn_blessing", "blessing", army.location, 1, 4, 0, [army.id])
	return {"state": s, "army": army, "blessing": String(began.id)}


func _field(s: GameState, fid: String) -> Army:
	for a in s.armies:
		if a.owner == fid and a.ruler == null:
			return a
	return null


func _roundtrip(s: GameState) -> GameState:
	var errors := []
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())), errors)
	assert_true(back != null, "the state loads after a JSON round trip: %s" % [errors])
	return back


func _errors_of(s: GameState) -> Array:
	var errors := []
	s.validate(errors)
	return errors


func _unit_dict(extra: Dictionary) -> Dictionary:
	var d := {"type_id": "spearmen", "current_hp": 10, "owner": CROWN}
	d.merge(extra, true)
	return d


# --- the unit ---------------------------------------------------------------------------------------

func test_a_unit_without_statuses_saves_exactly_as_before() -> void:
	var s := GameState.new(7)
	for a in s.armies:
		for u in a.units:
			assert_eq(u.to_dict().keys(), ["type_id", "current_hp", "owner"], "no statuses key on a plain unit")
	var u := Unit.new(TurnResolver.recruitable_type(s.find_faction(CROWN), "spearmen"), CROWN)
	u.until = 5
	assert_eq(u.to_dict().keys(), ["type_id", "current_hp", "owner", "until"], "until still saves alone")
	u.add_status(UnitStatus.OUTSIDE_BLESSING, "kingdom-e1")
	assert_eq(u.to_dict().keys(), ["type_id", "current_hp", "owner", "until", "statuses"], "statuses come last, and only when set")
	u.remove_status(UnitStatus.OUTSIDE_BLESSING)
	assert_eq(u.to_dict().keys(), ["type_id", "current_hp", "owner", "until"], "back to no key once the list is empty")


func test_the_helpers_add_find_and_remove() -> void:
	var s := GameState.new(7)
	var u := Unit.new(TurnResolver.recruitable_type(s.find_faction(CROWN), "spearmen"), CROWN)
	assert_false(u.has_status(UnitStatus.OUTSIDE_BLESSING))
	assert_true(u.add_status(UnitStatus.OUTSIDE_BLESSING, "kingdom-e1"), "added")
	assert_false(u.add_status(UnitStatus.OUTSIDE_BLESSING, "kingdom-e1"), "the same status is not added twice")
	assert_true(u.add_status(UnitStatus.OUTSIDE_BLESSING, "kingdom-e2"), "another source is another status")
	assert_eq(u.statuses.size(), 2)
	assert_true(u.has_status(UnitStatus.OUTSIDE_BLESSING))
	assert_true(u.has_status(UnitStatus.OUTSIDE_BLESSING, "kingdom-e1"))
	assert_false(u.has_status(UnitStatus.OUTSIDE_BLESSING, "kingdom-e3"))
	assert_eq(u.remove_status(UnitStatus.OUTSIDE_BLESSING, "kingdom-e1"), 1, "one removed by source")
	assert_false(u.has_status(UnitStatus.OUTSIDE_BLESSING, "kingdom-e1"))
	assert_true(u.has_status(UnitStatus.OUTSIDE_BLESSING, "kingdom-e2"))
	assert_eq(u.remove_status(UnitStatus.OUTSIDE_BLESSING), 1, "the rest removed by kind")
	assert_eq(u.statuses, [])
	assert_eq(u.remove_status(UnitStatus.OUTSIDE_BLESSING), 0, "nothing left to remove")


func test_statuses_survive_a_json_round_trip() -> void:
	var g := _blessed_game()
	var s: GameState = g.state
	var army: Army = g.army
	army.units[0].add_status(UnitStatus.OUTSIDE_BLESSING, g.blessing)
	army.commander.add_status(UnitStatus.OUTSIDE_BLESSING, g.blessing)
	assert_eq(_errors_of(s), [], "the marked state is valid")
	var back := _roundtrip(s)
	var again := back.find_army(army.id)
	assert_eq(again.units[0].statuses, [{"kind": "outside_blessing", "source": g.blessing}])
	assert_eq(again.commander.statuses, [{"kind": "outside_blessing", "source": g.blessing}])
	assert_eq(again.units[1].statuses, [], "an unmarked unit stays unmarked")
	assert_eq(JSON.stringify(back.to_dict()), JSON.stringify(s.to_dict()), "save, load and save again gives the same bytes")
	assert_eq(JSON.stringify(s.deep_copy().to_dict()), JSON.stringify(s.to_dict()), "a deep copy keeps them")


# --- the parser -------------------------------------------------------------------------------------

func test_a_malformed_status_list_fails_the_load_with_a_plain_reason() -> void:
	var s := GameState.new(7)
	var types := {}
	for f in s.factions:
		for ut in f.unit_types:
			types[ut.id] = ut
	var cases := {
		"not a list": [{"statuses": "outside"}, "should be a list"],
		"an entry that is not a group": [{"statuses": ["outside_blessing"]}, "is not a group of named values"],
		"no kind": [{"statuses": [{"source": "x"}]}, "no 'kind'"],
		"an unknown kind": [{"statuses": [{"kind": "poisoned", "source": "x"}]}, "'poisoned', which this game does not know"],
		"a missing field": [{"statuses": [{"kind": "outside_blessing"}]}, "no 'source'"],
		"a field of the wrong type": [{"statuses": [{"kind": "outside_blessing", "source": 7}]}, "'source' as a number, not text"],
		"an extra field": [{"statuses": [{"kind": "outside_blessing", "source": "x", "turns": 3}]}, "holds 'turns'"],
		"the same status twice": [{"statuses": [{"kind": "outside_blessing", "source": "x"}, {"kind": "outside_blessing", "source": "x"}]}, "twice"],
	}
	for name in cases:
		var errors := []
		var u := Unit.from_dict(_unit_dict(cases[name][0]), types, errors, "unit 1 of army 'kingdom-1'")
		assert_eq(u, null, "%s fails to load" % name)
		assert_false(errors.is_empty(), "%s says why" % name)
		if not errors.is_empty():
			assert_true(String(errors[0]).contains(cases[name][1]), "%s: the reason names it (%s)" % [name, errors[0]])
	var ok := Unit.from_dict(_unit_dict({"statuses": [{"kind": "outside_blessing", "source": "kingdom-e1"}]}), types, [])
	assert_true(ok != null and ok.has_status(UnitStatus.OUTSIDE_BLESSING, "kingdom-e1"), "a well-formed status loads")
	var none := Unit.from_dict(_unit_dict({"statuses": []}), types, [])
	assert_true(none != null and none.statuses.is_empty(), "an empty list loads as none")
	var legacy := Unit.from_dict(_unit_dict({}), types, [])
	assert_true(legacy != null and legacy.statuses.is_empty(), "a unit with no key loads as none")
	var nothing := Unit.from_dict(_unit_dict({"statuses": null}), types, [])
	assert_true(nothing != null and nothing.statuses.is_empty(), "null means none, as every other optional field")


func test_a_bad_status_in_a_saved_game_fails_the_game_load() -> void:
	var g := _blessed_game()
	var d: Dictionary = g.state.to_dict()
	d.armies[0].units[0]["statuses"] = [{"kind": "poisoned", "source": "x"}]
	var errors := []
	assert_eq(GameState.from_dict(JSON.parse_string(JSON.stringify(d)), errors), null, "the game does not load")
	assert_true(String(errors[0]).contains("poisoned"), "the reason names the kind: %s" % [errors])


# --- validation against the game ---------------------------------------------------------------------

func test_outside_blessing_is_valid_only_against_a_live_blessing_of_its_own_army() -> void:
	var g := _blessed_game()
	var s: GameState = g.state
	var army: Army = g.army
	var u: Unit = army.units[0]
	u.add_status(UnitStatus.OUTSIDE_BLESSING, g.blessing)
	assert_eq(_errors_of(s), [], "a live blessing of its own faction that lists the army: valid")
	u.statuses = []
	# An unknown source.
	u.add_status(UnitStatus.OUTSIDE_BLESSING, "kingdom-e99")
	var errors := _errors_of(s)
	assert_eq(errors.size(), 1, "an unknown source is one problem: %s" % [errors])
	assert_true(String(errors[0]).contains("not an enchantment in play"), "plain reason: %s" % [errors])
	# The wrong source kind: a ward.
	u.statuses = []
	var ward := MagicRules._begin(s, CROWN, "sanctum_ward", "ward", army.location, 1, 4, 0, [])
	u.add_status(UnitStatus.OUTSIDE_BLESSING, String(ward.id))
	errors = _errors_of(s)
	assert_true(not errors.is_empty() and String(errors[0]).contains("is a ward, not a blessing"), "the wrong source kind: %s" % [errors])
	# The wrong owner: a rival's blessing.
	u.statuses = []
	var rival := _field(s, CLANS)
	var theirs := MagicRules._begin(s, CLANS, "dawn_blessing", "blessing", rival.location, 1, 4, 0, [rival.id])
	u.add_status(UnitStatus.OUTSIDE_BLESSING, String(theirs.id))
	errors = _errors_of(s)
	assert_true(not errors.is_empty() and String(errors[0]).contains("belongs to"), "the wrong owner: %s" % [errors])
	# The wrong army: a blessing that doesn't list this army.
	u.statuses = []
	var other := Army.new()
	other.id = s.new_army_id(CROWN)
	other.owner = CROWN
	other.location = army.location
	other.units.append(Unit.new(TurnResolver.recruitable_type(s.find_faction(CROWN), "spearmen"), CROWN))
	s.armies.append(other)
	other.units[0].add_status(UnitStatus.OUTSIDE_BLESSING, g.blessing)
	errors = _errors_of(s)
	assert_true(not errors.is_empty() and String(errors[0]).contains("does not list army"), "the wrong army: %s" % [errors])


func test_a_commander_may_be_outside_a_blessing_and_a_ruler_may_not() -> void:
	var g := _blessed_game()
	var s: GameState = g.state
	var army: Army = g.army
	army.commander.add_status(UnitStatus.OUTSIDE_BLESSING, g.blessing)
	assert_eq(_errors_of(s), [], "a commander can join a blessed army, and is then outside it")
	army.commander.statuses = []
	var ruler := RulerRules.ruler_army(s, CROWN)
	# Bless the ruler's army too, so only the "ruler" rule can object.
	var list: Array = MagicRules._enchantment(s, g.blessing).armies
	list.append(ruler.id)
	ruler.ruler.add_status(UnitStatus.OUTSIDE_BLESSING, g.blessing)
	var errors := _errors_of(s)
	assert_true(not errors.is_empty() and String(errors[0]).contains("travels alone"), "a ruler never joins an army: %s" % [errors])


func test_a_game_without_magic_has_no_blessing_to_be_outside_of() -> void:
	var s := GameState.new(7)
	var u: Unit = s.armies[0].units[0]
	u.add_status(UnitStatus.OUTSIDE_BLESSING, "kingdom-e1")
	var errors := _errors_of(s)
	assert_true(not errors.is_empty() and String(errors[0]).contains("not an enchantment in play"), "no magic, no blessing: %s" % [errors])
	assert_eq(s.deep_copy([]), null, "such a game does not load")


func test_a_view_keeps_the_viewers_markers_and_shows_a_rival_none() -> void:
	var g := _blessed_game()
	var s: GameState = g.state
	s.setup_fog([])
	var army: Army = g.army
	army.units[0].add_status(UnitStatus.OUTSIDE_BLESSING, g.blessing)
	var mine := FogRules.view_state(s, CROWN)
	assert_true(mine != null, "the viewer's view builds")
	assert_true(mine.find_army(army.id).units[0].has_status(UnitStatus.OUTSIDE_BLESSING, g.blessing), "its own marker is in its own view")
	var theirs := FogRules.view_state(s, CLANS)
	assert_true(theirs != null, "the rival's view builds")
	for a in theirs.armies:
		for u in UnitStatus.army_fighters(a):
			assert_eq(u.statuses, [], "no marker ever reaches a rival's view (%s)" % a.id)
	assert_eq(FogRules.view_state(s, FogRules.OBSERVER).find_army(army.id).units[0].statuses.size(), 1, "the observer sees the truth")


# --- clearing ---------------------------------------------------------------------------------------

func test_clear_source_clears_only_that_source() -> void:
	var g := _blessed_game()
	var s: GameState = g.state
	var army: Army = g.army
	var second := MagicRules._begin(s, CROWN, "dawn_blessing", "blessing", army.location, 1, 4, 0, [])
	army.units[0].add_status(UnitStatus.OUTSIDE_BLESSING, g.blessing)
	army.units[1].add_status(UnitStatus.OUTSIDE_BLESSING, g.blessing)
	army.commander.add_status(UnitStatus.OUTSIDE_BLESSING, g.blessing)
	army.units[2].add_status(UnitStatus.OUTSIDE_BLESSING, String(second.id))
	assert_eq(UnitStatus.clear_source(s, g.blessing), 3, "three markers of the blessing")
	assert_false(army.units[0].has_status(UnitStatus.OUTSIDE_BLESSING))
	assert_false(army.commander.has_status(UnitStatus.OUTSIDE_BLESSING))
	assert_true(army.units[2].has_status(UnitStatus.OUTSIDE_BLESSING, String(second.id)), "another source is untouched")
	assert_eq(UnitStatus.clear_source(s, String(second.id), "source_ends", ["nobody-1"]), 0, "limited to armies that aren't there: nothing")
	assert_eq(MagicRules.clear_outside(s, String(second.id), [army.id]), 1, "MagicRules.clear_outside is the blessing's call")
	assert_eq(MagicRules.clear_outside(s, String(second.id)), 0, "and clearing twice is harmless")


func test_a_marker_clears_when_its_unit_leaves_the_army() -> void:
	var s := GameState.new(7)
	var u := Unit.new(TurnResolver.recruitable_type(s.find_faction(CROWN), "spearmen"), CROWN)
	u.add_status(UnitStatus.OUTSIDE_BLESSING, "kingdom-e1")
	assert_eq(UnitStatus.clear_on_leave(u), 1)
	assert_eq(u.statuses, [])
	assert_eq(UnitStatus.clear_on_leave(u), 0)


# --- the registry's own ------------------------------------------------------------------------------

func test_every_kind_declares_every_hook() -> void:
	assert_false(UnitStatus.kinds().is_empty(), "the registry has kinds")
	assert_true(UnitStatus.known(UnitStatus.OUTSIDE_BLESSING))
	assert_false(UnitStatus.known("poisoned"))
	var g := _blessed_game()
	for kind in UnitStatus.kinds():
		var row: Dictionary = UnitStatus.KINDS[kind]
		for hook in UnitStatus.HOOKS:
			assert_true(row.has(hook), "%s declares %s" % [kind, hook])
		assert_false(String(row.name).is_empty(), "%s has a name" % kind)
		assert_eq(UnitStatus.kind_name(kind), String(row.name))
		var fields: Dictionary = row.fields
		assert_true(fields.has("kind") and fields.has("source"), "%s has the common fields first" % kind)
		assert_eq(fields.keys().slice(0, 2), ["kind", "source"], "%s lists kind and source first" % kind)
		for trigger in row.clears:
			assert_true(UnitStatus.TRIGGERS.has(trigger), "%s clears on a known trigger (%s)" % [kind, trigger])
		assert_true(UnitStatus.FOG_RULES.has(row.fog), "%s has a fog rule" % kind)
		assert_true(RulesCodex.ENTRIES.has(UnitStatus.codex_id(kind)), "%s names a codex entry that exists" % kind)
		# The validate and tooltip hooks answer for a status of this kind.
		var status := {"kind": kind, "source": g.blessing}
		assert_eq(UnitStatus.shape_problems(status), [], "%s: a sample status is well formed" % kind)
		assert_false(UnitStatus.tooltip(status, g.state).is_empty(), "%s reads in a tooltip" % kind)
		assert_false(UnitStatus.tooltip(status).is_empty(), "%s reads in a tooltip even without a game" % kind)
		var unit: Unit = g.army.units[0]
		var why := UnitStatus.problem_in_state(g.state, g.army, unit, status)
		assert_eq(why, "", "%s: its own sample is valid against its own game" % kind)
		assert_true(UnitStatus.clears_on(kind, "source_ends") or UnitStatus.clears_on(kind, "turn") or UnitStatus.clears_on(kind, "leaves_army"),
			"%s says when it clears" % kind)
		# A rival sees a hidden status never, a clear one in clear sight only.
		var shown := UnitStatus.shown_to_rival(kind, FogRules.CLEAR)
		assert_eq(shown, row.fog == UnitStatus.FOG_CLEAR)
		assert_false(UnitStatus.shown_to_rival(kind, FogRules.GLIMPSE), "%s is never shown in a glimpse" % kind)
	assert_eq(UnitStatus.fog_rule(UnitStatus.OUTSIDE_BLESSING), UnitStatus.FOG_HIDDEN, "a rival never sees the marker itself")
	assert_true(UnitStatus.clears_on(UnitStatus.OUTSIDE_BLESSING, "source_ends"))
	assert_true(UnitStatus.clears_on(UnitStatus.OUTSIDE_BLESSING, "recast"))
	assert_true(UnitStatus.clears_on(UnitStatus.OUTSIDE_BLESSING, "leaves_army"))
	assert_false(UnitStatus.clears_on("poisoned", "source_ends"), "an unknown kind clears on nothing")
	assert_eq(UnitStatus.fog_rule("poisoned"), UnitStatus.FOG_HIDDEN, "an unknown kind is hidden")


func test_the_tooltip_names_the_blessing_and_no_ids() -> void:
	var g := _blessed_game()
	var text := UnitStatus.tooltip({"kind": "outside_blessing", "source": g.blessing}, g.state)
	assert_true(text.contains("Dawn Blessing"), "it names the blessing: %s" % text)
	assert_false(text.contains(g.blessing) or text.contains("outside_blessing"), "no ids in player text: %s" % text)


func test_covers_decides_per_fighter() -> void:
	var g := _blessed_game()
	var army: Army = g.army
	var blessing := MagicRules._enchantment(g.state, g.blessing)
	assert_true(MagicRules.covers(blessing, army.id, army.units[0]), "a unit of a listed army is covered")
	assert_true(MagicRules.covers(blessing, army.id, army.commander), "so is its commander")
	army.units[0].add_status(UnitStatus.OUTSIDE_BLESSING, g.blessing)
	assert_false(MagicRules.covers(blessing, army.id, army.units[0]), "a marked unit is not")
	assert_true(MagicRules.covers(blessing, army.id, army.units[1]), "its neighbours still are")
	assert_false(MagicRules.covers(blessing, "kingdom-99", army.units[1]), "an unlisted army is not covered")
