extends "res://tests/test_case.gd"
## Battle report viewer (#7): the full AutoBattleResolver report in readable sections with the "why" on
## top, every number explained on hover, no raw ids, Close and Esc emit `closed`. Reports come from real
## battles: TurnResolver.resolve(..., AutoBattleResolver.new()) on scripted armies. The viewer builds
## its children in code, so it is tested outside the tree.

const SCENE := "res://ui/battle_report_viewer.tscn"
const RAW_IDS := ["kingdom", "beasts", "crownkeep", "fangridge", "thornvale", "wildmoor", "stonegate", "blackwood",
	"rivermarch", "greenglade", "westwatch", "highcrag", "knight_captain", "warchief", "spearmen", "tuskers",
	"fangthrowers", "war_bear", "codex:", "_"]
const FULL_SECTIONS := ["why", "sides", "terrain", "rounds", "casualties", "routs", "hits"]


# --- fixtures -------------------------------------------------------------------------------------

func _viewer() -> BattleReportViewer:
	var v := load(SCENE).instantiate() as BattleReportViewer
	assert_true(v != null, "scene instantiates as BattleReportViewer")
	return v


## A fresh state with the starting armies replaced by `specs`: [[id, owner, location, [unit ids]], ...].
func _state(specs: Array) -> GameState:
	var s := GameState.new(99)
	s.armies.clear()
	for spec in specs:
		var a := Army.new()
		a.id = spec[0]
		a.owner = spec[1]
		a.location = spec[2]
		var f := s.find_faction(a.owner)
		for type_id in spec[3]:
			var ut := TurnResolver.recruitable_type(f, type_id)
			if ut.is_commander:
				a.commander = Unit.new(ut, f.id)
			else:
				a.units.append(Unit.new(ut, f.id))
		s.armies.append(a)
	return s


## Resolves one turn with the real battle rules and returns its only battle event.
func _battle_event(specs: Array, orders: Dictionary, turn_seed: int) -> Dictionary:
	var result := TurnResolver.resolve(_state(specs), orders, turn_seed, AutoBattleResolver.new())
	var battles: Array = result.events.filter(func(e): return GameSession.BATTLE_TYPES.has(e.type))
	assert_eq(battles.size(), 1, "the turn has one battle")
	return battles[0] if not battles.is_empty() else {}


## The Aurel Crown holds Stonegate (hills, fort); the Thornmane Clans attack from Blackwood.
func _fort_battle(turn_seed: int = 3) -> Dictionary:
	return _battle_event([
		["kingdom-1", "kingdom", "stonegate", ["spearmen", "spearmen", "crossbowmen", "knight_captain"]],
		["beasts-2", "beasts", "blackwood", ["tuskers", "tuskers", "fangthrowers", "warchief"]],
	], {"beasts": [MoveOrder.new("beasts-2", "stonegate")], "kingdom": []}, turn_seed)


## The two armies swap Westwatch and Stonegate and meet on the border.
func _border_battle(turn_seed: int = 5) -> Dictionary:
	return _battle_event([
		["kingdom-1", "kingdom", "westwatch", ["knights", "spearmen"]],
		["beasts-2", "beasts", "stonegate", ["tuskers", "fangthrowers"]],
	], {"kingdom": [MoveOrder.new("kingdom-1", "stonegate")], "beasts": [MoveOrder.new("beasts-2", "westwatch")]}, turn_seed)


## Both armies arrive in Thornvale on the same turn: nobody defends.
func _arrival_battle(turn_seed: int = 4) -> Dictionary:
	return _battle_event([
		["kingdom-1", "kingdom", "highcrag", ["spearmen", "crossbowmen", "knights"]],
		["beasts-2", "beasts", "wildmoor", ["tuskers", "war_bear"]],
	], {"kingdom": [MoveOrder.new("kingdom-1", "thornvale")], "beasts": [MoveOrder.new("beasts-2", "thornvale")]}, turn_seed)


## Crossbowmen holding Rivermarch against a War Bear and the Warchief: the first seed where they break.
func _rout_battle() -> Dictionary:
	for sd in range(1, 40):
		var e := _battle_event([
			["kingdom-1", "kingdom", "rivermarch", ["crossbowmen", "crossbowmen", "crossbowmen"]],
			["beasts-2", "beasts", "greenglade", ["war_bear", "warchief"]],
		], {"beasts": [MoveOrder.new("beasts-2", "rivermarch")], "kingdom": []}, sd)
		if _side(e.numbers.report, "kingdom").get("routed", false):
			return e
	fail("no seed made the crossbowmen break")
	return {}


## Two walls that cannot hurt each other: the battle runs out of rounds and the defender holds.
func _round_cap_report() -> Dictionary:
	var wall := UnitType.new()
	wall.id = "wall"
	wall.name = "Wall"
	wall.hp = 200
	wall.attack = 1
	wall.defense = 10
	wall.morale = 20
	var sides := []
	for fid in ["beasts", "kingdom"]:
		var a := Army.new()
		a.id = "%s-9" % fid
		a.owner = fid
		a.location = "rivermarch"
		a.units.append(Unit.new(wall, fid))
		sides.append({"faction": fid, "armies": [a]})
	var r: Dictionary = AutoBattleResolver.fight(sides, {"kind": "province", "defender": "kingdom"}, SeededRNG.new(1)).result
	assert_eq(r.report.end, "round_cap")
	return r.report


func _side(report: Dictionary, fid: String) -> Dictionary:
	for sr in report.get("sides", []):
		if sr.faction == fid:
			return sr
	return {}


func _visible_controls(node: Node, out: Array) -> Array:
	if node is CanvasItem and not (node as CanvasItem).visible:
		return out
	if node is Control:
		out.append(node)
	for c in node.get_children():
		_visible_controls(c, out)
	return out


func _visible_text(node: Node) -> String:
	var out := PackedStringArray()
	for c in _visible_controls(node, []):
		if c is Label or c is Button:
			out.append(c.text)
		if not c.tooltip_text.is_empty():
			out.append(c.tooltip_text)
	return "\n".join(out)


func _section_text(v: BattleReportViewer, section_name: String) -> String:
	var s := v.section(section_name)
	assert_true(s != null, "section %s exists" % section_name)
	if s == null:
		return ""
	var out := PackedStringArray()
	for c in _visible_controls(s, []):
		if c is Label:
			out.append(c.text)
	return "\n".join(out)


func _has_digit(text: String) -> bool:
	for ch in text:
		if ch >= "0" and ch <= "9":
			return true
	return false


## Every visible Label or Button showing a number explains it on hover. Returns how many were checked.
func _assert_numbers_explained(v: BattleReportViewer, where: String) -> int:
	var checked := 0
	for c in _visible_controls(v, []):
		if not (c is Label or c is Button) or not _has_digit(c.text):
			continue
		checked += 1
		assert_false(c.tooltip_text.strip_edges().is_empty(), "%s: '%s' has a tooltip" % [where, c.text])
		assert_ne(c.mouse_filter, Control.MOUSE_FILTER_IGNORE, "%s: '%s' takes the mouse so its tooltip shows" % [where, c.text])
	return checked


func _assert_no_raw_ids(text: String, where: String) -> void:
	assert_false(text.is_empty(), "%s has text" % where)
	for id in RAW_IDS:
		assert_false(text.contains(id), "%s shows no raw id '%s'" % [where, id])


func _all_reports() -> Array:
	return [["fort battle", _fort_battle()], ["border battle", _border_battle()], ["arrival battle", _arrival_battle()],
		["rout", _rout_battle()], ["round cap", {"numbers": {"report": _round_cap_report()}}]]


# --- the report -----------------------------------------------------------------------------------

func test_why_comes_first_and_stands_out() -> void:
	var e := _fort_battle()
	var report: Dictionary = e.numbers.report
	var v := _viewer()
	assert_false(v.visible, "hidden until a report is shown")
	assert_true(v.show_event(e), "a real battle event has a report")
	assert_true(v.visible)
	assert_eq(v.section_names()[0], "why", "the why section is first")
	var why_label := v.section("why").find_child("WhyLabel", true, false) as Label
	var result_label := v.section("why").find_child("ResultLabel", true, false) as Label
	assert_true(why_label != null and result_label != null, "the why box has a result and a why")
	assert_true(why_label.text.begins_with("Why: "), why_label.text)
	assert_true(why_label.text.contains(String(report.why).substr(1)), "shows the report's why: %s" % why_label.text)
	assert_true(result_label.text.contains(String(report.winner_name)), "names the winner: %s" % result_label.text)
	assert_true(result_label.get_theme_font_size("font_size") >= 28, "the result is the biggest text")
	assert_true(why_label.get_theme_font_size("font_size") >= 24, "the why is prominent")
	assert_true(v.title_label.text.contains("Stonegate"), v.title_label.text)
	v.free()


func test_every_section_is_rendered_from_a_real_report() -> void:
	var e := _fort_battle()
	var report: Dictionary = e.numbers.report
	var v := _viewer()
	assert_true(v.show_report(report))
	assert_eq(v.section_names(), FULL_SECTIONS, "sections in order; no round cap section")

	var sides := _section_text(v, "sides")
	for sr in report.sides:
		assert_true(sides.contains(sr.name), "who fought names %s" % sr.name)
		for label in sr.armies:
			assert_true(sides.contains(label), "who fought lists the army: %s" % label)
		assert_true(sides.contains("Fighters: %d, with %d hit points in all" % [sr.fighters_start, sr.hp_start]), sides)
		assert_true(sides.contains("Starting morale: %d" % sr.base_morale), sides)
	assert_true(sides.contains("Defending: it was already holding the province."), "the defender is marked")
	assert_true(sides.contains("Attacking: it moved into the province."), "the attacker is marked")

	var terrain := _section_text(v, "terrain")
	assert_true(terrain.contains("Terrain: Hills"), terrain)
	assert_true(terrain.contains("The defending Aurel Crown got +1 defense and +1 attack from the hills."), terrain)
	assert_true(terrain.contains("+2 defense more from the fort"), terrain)

	var rounds := _section_text(v, "rounds")
	assert_eq(report.rounds.size(), report.rounds_fought)
	for r in report.rounds:
		assert_true(rounds.contains("Round %d" % r.round), "round %d is listed" % r.round)
		for h in r.highlights:
			assert_true(rounds.contains(h), "round %d highlight: %s" % [r.round, h])
	assert_false(rounds.contains("Round %d" % (report.rounds_fought + 1)), "no extra rounds")

	var casualties := _section_text(v, "casualties")
	var routs := _section_text(v, "routs")
	var hits := _section_text(v, "hits")
	for sr in report.sides:
		assert_true(casualties.contains("%s lost %d of %d" % [sr.name, sr.fighters_lost, sr.fighters_start]), casualties)
		assert_true(casualties.contains("Hit points left: %d of %d" % [sr.hp_end, sr.hp_start]), casualties)
		assert_true(routs.contains(sr.name), "morale line for %s" % sr.name)
		if sr.attacks > 0:
			assert_true(hits.contains("%s hit %d%% of the time (%d of %d attacks)." % [sr.name, sr.hit_rate, sr.hits, sr.attacks]), hits)
			assert_true(hits.contains("Damage dealt: %d" % sr.damage_dealt), hits)
	v.free()


func test_border_and_arrival_battles_say_nobody_defended() -> void:
	var v := _viewer()
	var border := _border_battle()
	assert_eq(border.type, "border_battle")
	assert_true(v.show_event(border))
	assert_true(_section_text(v, "terrain").contains("border battle"), _section_text(v, "terrain"))
	assert_true(_section_text(v, "sides").contains("on the border"), _section_text(v, "sides"))
	assert_true(v.title_label.text.contains("border"), v.title_label.text)

	var arrival := _arrival_battle()
	assert_eq(arrival.numbers.defender, "")
	assert_true(v.show_event(arrival))
	assert_true(_section_text(v, "terrain").contains("nobody was defending"), _section_text(v, "terrain"))
	assert_true(_section_text(v, "sides").contains("Arrived at the same time"), _section_text(v, "sides"))
	assert_eq(v.section_names(), FULL_SECTIONS, "re-showing rebuilds the sections")
	v.free()


func test_a_rout_names_who_broke_with_a_morale_breakdown() -> void:
	var e := _rout_battle()
	var v := _viewer()
	assert_true(v.show_event(e))
	var k := _side(e.numbers.report, "kingdom")
	var check: Dictionary = {}
	for entry in k.morale_log:
		if entry.round == k.out_round:
			check = entry
	var line: Label = null
	for c in _visible_controls(v.section("routs"), []):
		if c is Label and c.text.begins_with("Aurel Crown broke and fled in round %d" % k.out_round):
			line = c
	assert_true(line != null, "the routs section says who broke: %s" % _section_text(v, "routs"))
	if line:
		assert_true(line.text.contains("lost %d%% of its hit points, and its morale of %d holds only to %d%%" % [check.lost_pct, check.morale, check.break_pct]), line.text)
		assert_true(line.tooltip_text.contains("Average morale of its units: %d" % k.base_morale), line.tooltip_text)
		for part in check.parts:
			var shown := "%s: %+d" % [BattleReportViewer.MORALE_PART_NAMES.get(part, part), check.parts[part]]
			assert_true(line.tooltip_text.contains(shown), "morale effect line '%s' in: %s" % [shown, line.tooltip_text])
		assert_true(line.tooltip_text.contains("= Morale: %d" % check.morale), "the breakdown totals the report's morale")
	var fled: int = k.fighters_start - k.fighters_lost
	var fled_text := "Its last fighter standing fled when it broke." if fled == 1 else "The other %d fled when it broke." % fled
	assert_true(_section_text(v, "casualties").contains(fled_text), "casualties say who fled: %s" % _section_text(v, "casualties"))
	v.free()


func test_round_cap_section_only_when_the_battle_ran_out_of_rounds() -> void:
	var v := _viewer()
	assert_true(v.show_report(_round_cap_report()))
	assert_eq(v.section_names(), FULL_SECTIONS + ["round_cap"], "the round cap section comes last")
	var text := _section_text(v, "round_cap")
	assert_true(text.contains("Nobody had won after %d rounds" % AutoBattleResolver.ROUND_CAP), text)
	assert_true(text.contains("Aurel Crown was defending, so it held its ground and won."), text)
	assert_true(_section_text(v, "terrain").contains("No terrain bonus applied here."), _section_text(v, "terrain"))
	assert_true(v.show_event(_fort_battle()))
	assert_false(v.section_names().has("round_cap"), "no round cap section for a decided battle")
	assert_eq(v.section("round_cap"), null)
	v.free()


func test_every_number_has_a_tooltip() -> void:
	var v := _viewer()
	for pair in _all_reports():
		assert_true(v.show_event(pair[1]), pair[0])
		var checked := _assert_numbers_explained(v, pair[0])
		assert_true(checked >= 10, "%s: checked %d numbers" % [pair[0], checked])
	v.free()


func test_no_raw_ids_in_any_report() -> void:
	var v := _viewer()
	for pair in _all_reports():
		assert_true(v.show_event(pair[1]), pair[0])
		_assert_no_raw_ids(_visible_text(v), pair[0])
	v.free()


func test_event_without_a_report_says_so() -> void:
	# The default StubBattleResolver attaches no report.
	var s := _state([
		["kingdom-1", "kingdom", "stonegate", ["spearmen"]],
		["beasts-2", "beasts", "blackwood", ["tuskers"]],
	])
	var stub_events: Array = TurnResolver.resolve(s, {"beasts": [MoveOrder.new("beasts-2", "stonegate")]}, 1).events
	var stub: Dictionary = stub_events.filter(func(e): return e.type == "battle")[0]
	assert_true(stub.numbers.report.is_empty())

	var v := _viewer()
	assert_true(v.show_event(_fort_battle()))
	assert_false(v.show_event(stub), "no report: show_event returns false")
	assert_true(v.visible, "the viewer still opens to say so")
	assert_true(v.message_label.visible)
	assert_eq(v.message_label.text, "No detailed report for this battle.")
	assert_eq(v.section_names(), [], "the old report's sections are gone")
	var text := _visible_text(v)
	assert_true(text.contains(stub.text), "the event's own sentence is still shown")
	_assert_no_raw_ids(text, "no-report message")
	assert_true(_assert_numbers_explained(v, "no report") >= 1)

	assert_false(v.show_event({}), "an empty event")
	assert_false(v.show_event({"type": "income", "numbers": {"income": 12}, "text": "Income."}), "not a battle")
	assert_false(v.show_report({}), "an empty report")
	assert_true(v.message_label.visible)
	assert_true(v.show_event(_fort_battle()), "a real report after the message")
	assert_false(v.message_label.visible, "the message goes away")
	v.free()


func test_close_button_and_escape_emit_closed() -> void:
	var v := _viewer()
	var closes := [0]
	v.closed.connect(func(): closes[0] += 1)
	v.show_event(_fort_battle())
	v.close_button.pressed.emit()
	assert_eq(closes[0], 1, "Close emits closed")
	assert_false(v.visible, "Close hides the viewer")

	var esc := InputEventAction.new()
	esc.action = "ui_cancel"
	esc.pressed = true
	v._unhandled_input(esc)
	assert_eq(closes[0], 1, "Esc does nothing while hidden")
	v.show_event(_fort_battle())
	v._unhandled_input(esc)
	assert_eq(closes[0], 2, "Esc emits closed")
	assert_false(v.visible)
	assert_false(v.close_button.tooltip_text.is_empty())
	v.free()


func test_codex_entries_behind_the_tooltips_exist() -> void:
	for key in BattleReportViewer.FACTOR_ENTRIES.values():
		assert_true(RulesCodex.ENTRIES.has(key), "factor entry %s exists" % key)
	for f in FactionData.FACTIONS:
		for u in f.unit_types + [f.commander]:
			assert_ne(BattleReportViewer._factor_entry(u.trait), "", "trait %s has a codex entry" % u.trait)
	for pair in _all_reports():
		for f in pair[1].numbers.report.factors:
			assert_ne(BattleReportViewer._factor_entry(f.id), "", "%s: factor %s is explained" % [pair[0], f.id])
