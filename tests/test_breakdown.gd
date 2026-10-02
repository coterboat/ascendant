extends "res://tests/test_case.gd"
## Tests for issue #5's pure number breakdowns (rules/breakdown.gd), the tooltip formatter and the
## UI-only map layout. Every breakdown's total must equal the sum of its lines and the number the
## rules actually use.


func _assert_consistent(b: Dictionary, what: String) -> void:
	for key in ["title", "description", "lines", "total_label", "total"]:
		assert_true(b.has(key), "%s breakdown has %s" % [what, key])
	assert_eq(Breakdown.sum_of_lines(b), b.total, "%s: total equals the sum of its lines" % what)
	assert_false(String(b.description).is_empty(), "%s has a plain description" % what)
	for l in b.lines:
		assert_false(String(l.label).is_empty(), "%s: every line has a label" % what)


func test_province_income_matches_the_map_for_every_province() -> void:
	var s := GameState.new()
	for p in s.provinces:
		var b := Breakdown.province_income(s, p.id)
		_assert_consistent(b, p.name)
		assert_eq(b.total, p.income, "%s income total" % p.name)
		assert_eq(b.lines[0].value, p.income, "%s base income line" % p.name)
		assert_true(String(b.title).contains(p.name), "title names the province, not its id")


func test_gold_breakdown_is_gold_now_plus_income_of_owned_provinces() -> void:
	var s := GameState.new()
	for f in s.factions:
		var b := Breakdown.gold(s, f.id)
		_assert_consistent(b, f.faction_name)
		var income: int = TurnResolver.income_of(s, f.id).total
		assert_eq(b.total, f.gold + income, "%s gold next turn" % f.faction_name)
		assert_eq(b.lines[0].value, f.gold, "first line is gold now")
		assert_eq(b.lines.size(), 1 + TurnResolver.income_of(s, f.id).by_province.size(), "one line per owned province")
		assert_false(String(b.title).contains(f.id), "title uses the faction name, not its id")


func test_gold_breakdown_follows_province_ownership() -> void:
	var s := GameState.new()
	var before: int = Breakdown.gold(s, "kingdom").total
	s.find_province("westwatch").owner = "kingdom"
	var b := Breakdown.gold(s, "kingdom")
	_assert_consistent(b, "after capture")
	assert_eq(b.total, before + s.find_province("westwatch").income, "a captured province adds its income")
	var labels := []
	for l in b.lines:
		labels.append(l.label)
	assert_true(labels.has("Income from Westwatch"), "the new province has its own line")


func test_army_strength_matches_the_battle_rules() -> void:
	var s := GameState.new()
	for a in s.armies:
		var b := Breakdown.army_strength(s, a.id)
		_assert_consistent(b, a.id)
		assert_eq(b.total, StubBattleResolver.army_strength(a), "strength total is what battles use")
		assert_eq(b.lines.size(), a.units.size() + (1 if a.commander else 0), "one line per unit and commander")


func test_army_units_counts_units_by_type_without_the_commander() -> void:
	var s := GameState.new()
	var a := s.armies[0]
	a.units.append(Unit.new(a.units[0].type, a.owner))  # two of the first type
	var b := Breakdown.army_units(s, a.id)
	_assert_consistent(b, "units")
	assert_eq(b.total, a.units.size(), "units total excludes the commander")
	assert_eq(b.lines[0].value, 2, "duplicate unit types are counted together")
	assert_true(String(b.description).contains(a.commander.type.name), "description names the commander")
	var c := Breakdown.unit_count(s, a.id, a.units[0].type.name)
	_assert_consistent(c, "unit count")
	assert_eq(c.total, 2, "unit_count counts one type")
	assert_true(String(c.description).contains("Attack"), "unit count explains the unit's stats")


func test_turn_breakdown_and_missing_ids_are_safe() -> void:
	var s := GameState.new()
	s.current_turn = 4
	var t := Breakdown.turn(s)
	_assert_consistent(t, "turn")
	assert_eq(t.total, 5, "4 turns resolved: the players are ordering turn 5 (1-based)")
	assert_eq(t.title, "Turn 5")
	assert_eq(Breakdown.province_income(s, "nowhere").total, 0, "unknown province gives an empty breakdown")
	assert_eq(Breakdown.gold(s, "nobody").total, 0, "unknown faction gives an empty breakdown")
	assert_eq(Breakdown.army_strength(s, "ghost-1").total, 0, "unknown army gives an empty breakdown")


func test_breakdowns_do_not_change_the_state() -> void:
	var s := GameState.new()
	var before := s.to_dict()
	for p in s.provinces:
		Breakdown.province_income(s, p.id)
	for f in s.factions:
		Breakdown.gold(s, f.id)
	for a in s.armies:
		Breakdown.army_units(s, a.id)
		Breakdown.army_strength(s, a.id)
	Breakdown.turn(s)
	assert_eq(s.to_dict(), before, "breakdowns only read the state")


func test_tooltip_text_shows_lines_total_and_wrapped_description() -> void:
	var s := GameState.new()
	var text := TooltipText.from_breakdown(Breakdown.gold(s, "kingdom"))
	assert_true(text.begins_with("Gold of Aurel Crown"), "title first")
	assert_true(text.contains("Gold now: 45"), "first line shows the base value")
	assert_true(text.contains("Income from Crownkeep: +12"), "later lines show signed modifiers")
	assert_true(text.contains("= Gold next turn (before recruits): 57"), "total line")
	var wrapped := TooltipText.wrap_text(RulesCodex.text("phase_order"), 40)
	for line in wrapped.split("\n"):
		assert_true(line.length() <= 40, "wrapped line fits: '%s'" % line)
	assert_eq(wrapped.replace("\n", " "), RulesCodex.text("phase_order"), "wrapping keeps every word")


func test_layout_places_every_province_as_an_exact_mirror() -> void:
	var s := GameState.new()
	for p in s.provinces:
		assert_true(MapLayout.has_position(p.id), "layout places %s" % p.name)
	for west_id in MapLayout.MIRROR:
		var east_id: String = MapLayout.MIRROR[west_id]
		var w := MapLayout.position_of(west_id)
		var e := MapLayout.position_of(east_id)
		assert_eq(e.x, MapLayout.SIZE.x - w.x, "%s mirrors %s horizontally" % [east_id, west_id])
		assert_eq(e.y, w.y, "%s and %s share a row" % [east_id, west_id])
		var wp := s.find_province(west_id)
		var ep := s.find_province(east_id)
		assert_eq([ep.terrain, ep.income, ep.has_fort, ep.is_capital], [wp.terrain, wp.income, wp.has_fort, wp.is_capital],
			"mirror twins %s and %s match in the rules data" % [west_id, east_id])
	assert_eq(MapLayout.WEST.size() + MapLayout.MIRROR.size(), s.provinces.size(), "every province is placed exactly once")
	assert_true(MapLayout.is_east("fangridge") and not MapLayout.is_east("crownkeep"), "east half is the mirror side")
