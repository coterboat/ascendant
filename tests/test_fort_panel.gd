extends "res://tests/test_case.gd"
## M3c S-3 (#101, design/M3C_SIEGES.md §9, §15): the fort and siege UI, headless in M1 style.
##   - every number on the fort panel has a hover breakdown equal to SiegeRules / Breakdown;
##   - Fortify, Storm and Sally queue the right orders and show the rules' rejection reasons;
##   - a relief move queues sallies for every garrison army but the ruler's;
##   - the recruit picker greys a besieged fort, a full one and a just-captured one, each with its reason;
##   - a rival's siege and Fortify orders never show, also in hotseat;
## and the plate's fort chip, the move preview (Besiege / Storm now / relief), the report lines and "needs
## you" lines, the first-siege sentences, the battle viewer's chips, the victory screen's numbers and the S-2
## odds seam. Expected numbers come from FortData and SiegeRules, never typed in.

const Fx := preload("res://tests/siege_fixtures.gd")
const MAP_SCENE := "res://ui/map_screen.tscn"
const GAME_SCENE := "res://ui/game_screen.tscn"
const CROWN := "kingdom"
const CLANS := "beasts"
const LINK_LINE := "Codex: %s (right-click or F1 to open)"


# --- set-ups -----------------------------------------------------------------------------------------

## Turn 2 of a siege of Stonegate (a keep, the Crown's): the Crown's 3rd (8 Spearmen and a Knight Captain)
## inside, the Clans' 5th (14 Tuskers and 1 engine) outside since turn 1, walls 5 of 6. The Crown's 7th
## (Knights) stands next door at Westwatch, able to march in as a relief.
static func besieged_keep(rulers: bool = false) -> GameState:
	var s := GameState.with_sieges(99, {}, {"rulers": rulers})
	var keep := s.armies.filter(func(a): return a.ruler != null)
	s.armies.clear()
	s.armies.append(Fx.army(s, ["kingdom-3", CROWN, "stonegate", Fx.units("spearmen", 8) + ["knight_captain"]]))
	s.armies.append(Fx.army(s, ["beasts-5", CLANS, "stonegate", Fx.units("tuskers", 14), 1]))
	s.armies.append(Fx.army(s, ["kingdom-7", CROWN, "westwatch", Fx.units("knights", 3)]))
	for a in keep:
		a.id = "%s-%d" % [a.owner, 11 if a.owner == CROWN else 12]  # clear of the armies above
		if a.owner == CROWN:
			a.location = "stonegate"  # the King sits in the besieged keep
		s.armies.append(a)
	s.next_army_id = 20
	s.find_province("stonegate").owner = CROWN
	s.find_province("westwatch").owner = CROWN
	var p := s.find_province("stonegate")
	p.walls = 5
	p.siege_since = 1
	s.current_turn = 1
	var errors := []
	assert(s.validate(errors), str(errors))
	return s


func _map(s: GameState, viewer: String, session: GameSession = null) -> MapScreen:
	var map: MapScreen = load(MAP_SCENE).instantiate()
	map.session = session
	map.set_state(s, viewer)
	return map


func _fort(map: MapScreen) -> Control:
	var found := map.details.find_children("FortSection", "", true, false)
	if found.is_empty():
		fail("the side panel has a fort section")
		return Control.new()
	return found[0]


func _node(root: Node, node_name: String) -> Node:
	var found := root.find_children(node_name, "", true, false)
	if found.is_empty():
		fail("found %s under %s" % [node_name, root.name])
		return null
	return found[0]


func _has(root: Node, node_name: String) -> bool:
	return not root.find_children(node_name, "", true, false).is_empty()


func _siege_orders(map: MapScreen) -> Array:
	return map.orders.orders().filter(func(o): return o is SiegeOrder)


## The label's number breakdown: its tooltip is that breakdown (with the codex line), the lines add up to the
## total, and the total is the number the label shows.
func _assert_breakdown(l: Control, where: String) -> Dictionary:
	assert_true(l.has_meta(FortPanel.BREAKDOWN), "%s: '%s' (%s) carries its breakdown" % [where, l.name, _text(l)])
	if not l.has_meta(FortPanel.BREAKDOWN):
		return {}
	var b: Dictionary = l.get_meta(FortPanel.BREAKDOWN)
	assert_eq(Breakdown.sum_of_lines(b), int(b.total), "%s: '%s' lines add up to its total" % [where, l.name])
	assert_true(l.tooltip_text.begins_with(TooltipText.from_breakdown(b)), "%s: '%s' shows its breakdown on hover: %s" % [where, l.name, l.tooltip_text])
	assert_true(_text(l).contains(str(int(b.total))), "%s: '%s' shows the breakdown's total %d: %s" % [where, l.name, int(b.total), _text(l)])
	return b


func _text(c: Control) -> String:
	if c is Label:
		return (c as Label).text
	if c is Button:
		return (c as Button).text
	return ""


## Every label of the fort section that shows a number (an army's "3rd" doesn't count) has its breakdown,
## unless it is the rules' own rejection reason.
func _assert_every_number_explained(fort: Control, where: String) -> void:
	var ordinal := RegEx.create_from_string("\\b\\d+(st|nd|rd|th)\\b")
	var digit := RegEx.create_from_string("\\d")
	for c in fort.find_children("*", "Label", true, false):
		var l := c as Label
		if l.has_meta(FortPanel.REASON):
			continue
		if digit.search(ordinal.sub(l.text, "", true)) != null:
			_assert_breakdown(l, where)


# --- the fort panel: every number explained -----------------------------------------------------------

func test_every_number_on_the_panel_has_a_breakdown_equal_to_the_rules() -> void:
	var s := besieged_keep()
	var p := s.find_province("stonegate")
	var turn := s.current_turn + 1
	# The garrison's view.
	var map := _map(s, CROWN)
	map.select_province("stonegate")
	var fort := _fort(map)
	assert_eq(_node(map.details, "FortLabel").text, "Fort: %s" % FortData.LEVELS[2].name, "the fort line names the level")
	var walls := _assert_breakdown(_node(fort, "WallsLabel"), "garrison")
	assert_eq(walls, Breakdown.walls(s, "stonegate"), "walls: Breakdown.walls")
	assert_eq(int(walls.total), p.walls)
	assert_true(_node(fort, "WallsLabel").text.contains("%d of %d" % [p.walls, int(FortData.LEVELS[2].walls)]))
	var storm_def := _assert_breakdown(_node(fort, "StormDefenseLabel"), "garrison")
	assert_eq(storm_def, Breakdown.walls_defense(s, "stonegate"), "walls if stormed: Breakdown.walls_defense")
	assert_eq(int(storm_def.total), FortData.WALLS_DEFENSE_PER_STEP * ceili(float(p.walls) / FortData.WALL_STEP))
	var bar := _node(fort, "WallsBar") as WallsBar
	assert_eq(bar.walls, p.walls, "the walls bar shows the walls")
	assert_eq(bar.walls_max, int(FortData.LEVELS[2].walls))
	assert_eq(bar.tooltip_text, _node(fort, "WallsLabel").tooltip_text, "and explains itself the same way")
	var limit := _assert_breakdown(_node(fort, "RecruitLimitLabel"), "garrison")
	assert_eq(limit, Breakdown.recruit_limit(s, "stonegate", CROWN, map.orders.orders()), "recruits: Breakdown.recruit_limit")
	assert_eq(int(limit.total), int(FortData.LEVELS[2].recruits))
	var dmg := _assert_breakdown(_node(fort, "SiegeDamageLabel"), "garrison")
	assert_eq(dmg, Breakdown.siege_damage(s, "stonegate"), "siege damage: Breakdown.siege_damage")
	var expect_dmg := int(FortData.SIEGE.camp) + mini(int(FortData.SIEGE.troops_max), 14 / int(FortData.SIEGE.per_troops)) \
		+ mini(1, 14 / int(FortData.SIEGE.troops_per_engine))
	assert_eq(int(dmg.total), mini(expect_dmg, int(FortData.SIEGE.max)), "siege damage from FortData.SIEGE")
	var breach := _assert_breakdown(_node(fort, "BreachLabel"), "garrison")
	assert_eq(int(breach.total), SiegeRules.breach_turn(p.walls, int(dmg.total), turn), "the breach turn is SiegeRules.breach_turn")
	assert_eq(int(breach.total), turn + ceili(float(p.walls) / int(dmg.total)) - 1)
	var cut := _assert_breakdown(_node(fort, "CutOffLabel"), "garrison")
	assert_eq(cut, Breakdown.cut_off(s, "stonegate"), "the cut-off: Breakdown.cut_off")
	assert_true(_node(fort, "CutOffLabel").text.begins_with("Cut off"), _node(fort, "CutOffLabel").text)
	var status := _assert_breakdown(_node(fort, "SiegeStatusLabel"), "garrison")
	assert_eq(int(status.total), SiegeRules.turn_of_siege(s, "stonegate"), "the turn of the siege")
	var inside := _assert_breakdown(_node(fort, "InsideLabel"), "garrison")
	assert_eq(int(inside.total), SiegeRules.troops(SiegeRules.garrison(s, "stonegate")), "troops inside the walls")
	var outside := _assert_breakdown(_node(fort, "OutsideLabel"), "garrison")
	assert_eq(int(outside.total), SiegeRules.troops(SiegeRules.besiegers(s, "stonegate")), "troops outside the walls")
	assert_true(_node(fort, "OutsideLabel").text.contains(SiegeRules.engines_text(CLANS, 1)), "the engines outside are named")
	_assert_every_number_explained(fort, "garrison")
	# The besiegers' view: the same numbers, from the other side.
	var them := _map(s, CLANS)
	them.select_province("stonegate")
	var fort2 := _fort(them)
	assert_eq(_node(fort2, "SiegeDamageLabel").get_meta(FortPanel.BREAKDOWN), Breakdown.siege_damage(s, "stonegate"))
	assert_eq(_node(fort2, "WallsLabel").get_meta(FortPanel.BREAKDOWN), Breakdown.walls(s, "stonegate"))
	_assert_every_number_explained(fort2, "besieger")
	map.free()
	them.free()


func test_construction_and_a_quiet_fort_explain_their_numbers() -> void:
	var s := GameState.with_sieges(5)
	s.armies.clear()
	s.find_province("rivermarch").owner = CROWN
	s.find_province("rivermarch").works = {"faction": CROWN, "to": 1, "left": 1, "turn": 1}
	s.current_turn = 1
	var map := _map(s, CROWN)
	map.select_province("rivermarch")
	var fort := _fort(map)
	var b := _assert_breakdown(_node(fort, "ConstructionLabel"), "construction")
	assert_eq(b, Breakdown.construction(s, "rivermarch"), "construction: Breakdown.construction")
	assert_eq(int(b.total), 1)
	assert_false(_has(fort, "WallsLabel"), "no walls before the palisade stands")
	_assert_every_number_explained(fort, "construction")
	# A quiet capital: walls and recruits, and no siege lines.
	map.select_province("crownkeep")
	fort = _fort(map)
	assert_eq(int(_node(fort, "WallsLabel").get_meta(FortPanel.BREAKDOWN).total), int(FortData.LEVELS[3].walls))
	assert_eq(int(_node(fort, "RecruitLimitLabel").get_meta(FortPanel.BREAKDOWN).total), int(FortData.LEVELS[3].recruits))
	assert_false(_has(fort, "SiegeDamageLabel"), "no siege, so no siege damage line")
	assert_true(_node(fort, "SiegeStatusLabel").text.contains("Not besieged"), _node(fort, "SiegeStatusLabel").text)
	_assert_every_number_explained(fort, "capital")
	map.free()


func test_a_game_without_sieges_has_no_fort_section() -> void:
	var s := GameState.new(3)
	s.place_starting_armies()
	var map := _map(s, CROWN)
	map.select_province("stonegate")
	assert_false(_has(map.details, "FortSection"), "M1: no fort section")
	assert_eq(_node(map.details, "FortLabel").text, "Fort: Yes", "the M1 fort line is unchanged")
	map.free()


# --- Fortify ---------------------------------------------------------------------------------------

func test_fortify_queues_the_order_with_its_preview() -> void:
	var s := GameState.with_sieges(5)
	s.armies.clear()
	s.find_province("rivermarch").owner = CROWN
	var map := _map(s, CROWN)
	map.select_province("rivermarch")
	var button := _node(_fort(map), "FortifyButton") as Button
	assert_false(button.disabled, "a palisade can be built at Rivermarch")
	var fc := Forecast.fortify(s, CROWN, "rivermarch")
	assert_true(button.text.contains(FortData.LEVELS[1].name.to_lower()) and button.text.contains("%d gold" % int(FortData.LEVELS[1].cost)), button.text)
	assert_true(button.tooltip_text.replace("\n", " ").contains(TooltipText.wrap_text(String(fc.text)).replace("\n", " ").left(60)),
		"the button's hover is the Fortify forecast: %s" % button.tooltip_text)
	button.pressed.emit()
	var queued := map.orders.orders().filter(func(o): return o is FortifyOrder)
	assert_eq(queued.size(), 1, "one Fortify order")
	assert_eq(String(queued[0].province), "rivermarch")
	assert_true(map.status_text.contains(str(int(fc.stands))), "the status says when it stands: %s" % map.status_text)
	var line := map.orders.order_texts()[0]
	assert_true(line.contains("Rivermarch") and line.contains(str(int(fc.stands))), "the order line has the forecast: %s" % line)
	assert_eq(map.orders.gold_after_recruits().gold_after, s.find_faction(CROWN).gold - int(FortData.LEVELS[1].cost), "it is paid from the same gold")
	# A second site is refused, with the rules' reason on screen.
	s.find_province("greenglade").owner = CROWN
	map.select_province("greenglade")
	var second := _node(_fort(map), "FortifyButton") as Button
	assert_true(second.disabled, "one Fortify order a turn")
	var want := SiegeRules.check_fortify(s, CROWN, "greenglade", null, 1)
	assert_eq(_node(_fort(map), "FortifyReason").text, String(want.reason), "the reason is the rules' own")
	map.free()


func test_fortify_refused_with_the_reason_when_gold_or_the_enemy_say_no() -> void:
	var s := GameState.with_sieges(5)
	s.armies.clear()
	s.find_province("rivermarch").owner = CROWN
	s.find_province("greenglade").owner = CROWN
	s.armies.append(Fx.army(s, ["beasts-4", CLANS, "greenglade", ["tuskers"]]))
	s.find_faction(CROWN).gold = int(FortData.LEVELS[1].cost) - 1
	var map := _map(s, CROWN)
	map.select_province("rivermarch")
	var fort := _fort(map)
	assert_true((_node(fort, "FortifyButton") as Button).disabled, "too little gold")
	assert_eq(_node(fort, "FortifyReason").text, String(Forecast.fortify(s, CROWN, "rivermarch").reason))
	assert_true(_node(fort, "FortifyReason").text.contains("gold"), _node(fort, "FortifyReason").text)
	map.select_province("greenglade")
	fort = _fort(map)
	assert_true((_node(fort, "FortifyButton") as Button).disabled, "an enemy army stands there")
	assert_eq(_node(fort, "FortifyReason").text, String(SiegeRules.check_fortify(s, CROWN, "greenglade").reason))
	# The upgrade button on a palisade names the keep.
	Fx.set_fort(s, "rivermarch", 1)
	s.find_faction(CROWN).gold = 200
	map.set_state(s, CROWN)
	map.select_province("rivermarch")
	var up := _node(_fort(map), "FortifyButton") as Button
	assert_true(up.text.contains(FortData.LEVELS[2].name.to_lower()), "Upgrade to a keep: %s" % up.text)
	map.free()


# --- Storm -----------------------------------------------------------------------------------------

func test_storm_toggle_queues_and_cancels_the_storm() -> void:
	var s := besieged_keep()
	var map := _map(s, CLANS)
	map.select_province("stonegate")
	var toggle := _node(_fort(map), "StormToggle") as BaseButton
	assert_false(toggle.button_pressed, "waiting is the default")
	assert_false(toggle.disabled)
	var note := _node(_fort(map), "StormNote") as Label
	assert_true(note.text.contains("move it away"), "the toggle says how to keep an army out: %s" % note.text)
	toggle.button_pressed = true
	var storms := _siege_orders(map)
	assert_eq(storms.size(), 1, "one storm queued")
	assert_true(storms[0].is_storm() and storms[0].province == "stonegate")
	toggle = _node(_fort(map), "StormToggle") as BaseButton
	assert_true(toggle.button_pressed, "the toggle shows the queued storm")
	toggle.button_pressed = false
	assert_eq(_siege_orders(map).size(), 0, "unticking cancels it")
	map.free()


func test_storm_refused_at_breached_walls_with_the_reason() -> void:
	var s := besieged_keep()
	s.find_province("stonegate").walls = 0
	var map := _map(s, CLANS)
	map.select_province("stonegate")
	var toggle := _node(_fort(map), "StormToggle") as BaseButton
	assert_true(toggle.disabled, "breached walls can't be stormed")
	var want := SiegeRules.check_siege_order(s, CLANS, SiegeOrder.storm("stonegate"), [])
	assert_eq(_node(_fort(map), "StormReason").text, String(want.reason), "the rules' reason")
	map.free()


func test_storm_now_on_a_move_into_an_enemy_fort() -> void:
	var s := besieged_keep()
	s.armies.append(Fx.army(s, ["beasts-9", CLANS, "thornvale", Fx.units("tuskers", 6)]))
	var map := _map(s, CLANS)
	map.select_army("beasts-9")
	var preview := map.preview_move("stonegate")
	assert_true(preview.begins_with("Click to join the siege of Stonegate."), "the Clans already besiege it: %s" % preview)
	assert_true(preview.contains("Storm now"), "and offers Storm now: %s" % preview)
	assert_false(preview.contains("+2 fort") or preview.contains("its fort gives"), "no promise of the old fort bonus: %s" % preview)
	var fc := Forecast.siege(s, CLANS, "stonegate", [MoveOrder.new("beasts-9", "stonegate")])
	assert_true(preview.contains("reach 0"), "with the siege forecast: %s" % preview)
	assert_true(preview.contains(str(int(fc.breach_turn))), "the breach turn from Forecast.siege: %s" % preview)
	assert_eq(map.queue_move("beasts-9", "stonegate"), "")
	assert_true(map.orders.order_texts()[0].begins_with("Join the siege of Stonegate: the Clans' 9th"), map.orders.order_texts()[0])
	var row_toggle := _node(map.details, "StormNowToggle") as BaseButton
	assert_false(row_toggle.button_pressed)
	row_toggle.button_pressed = true
	assert_eq(_siege_orders(map).size(), 1, "Storm now on the move queues the fort's storm")
	assert_true(map.orders.order_texts()[0].begins_with("Storm Stonegate from the march"), map.orders.order_texts()[0])
	map.free()
	# A fort nobody of yours besieges yet: Besiege.
	var fresh := Fx.state([["kingdom-3", CROWN, "stonegate", Fx.units("spearmen", 4)], ["beasts-9", CLANS, "thornvale", Fx.units("tuskers", 6)]],
		{"stonegate": CROWN, "thornvale": CLANS})
	var m2 := _map(fresh, CLANS)
	m2.select_army("beasts-9")
	var p2 := m2.preview_move("stonegate")
	assert_true(p2.begins_with("Click to besiege Stonegate."), p2)
	assert_true(p2.contains("Storm now"), p2)
	assert_true(p2.contains("From next turn (2) Stonegate is cut off"), "the cut-off from Forecast.siege: %s" % p2)
	m2.free()


# --- Sally and relief ------------------------------------------------------------------------------

func test_sally_ticks_queue_one_sally_per_army_and_say_what_is_risked() -> void:
	var s := besieged_keep(true)
	var ruler := RulerRules.ruler_army(s, CROWN)
	var map := _map(s, CROWN)
	map.select_province("stonegate")
	var fort := _fort(map)
	var tick := _node(fort, "SallyTick_kingdom-3") as BaseButton
	var ruler_tick := _node(fort, "SallyTick_%s" % ruler.id.validate_node_name()) as BaseButton
	assert_false(tick.button_pressed, "holding is the default")
	assert_false(ruler_tick.button_pressed, "the ruler is unticked")
	assert_true(ruler_tick.tooltip_text.contains("ruler"), "the ruler's tick warns: %s" % ruler_tick.tooltip_text)
	tick.button_pressed = true
	var sallies := _siege_orders(map)
	assert_eq(sallies.size(), 1, "one sally")
	assert_true(sallies[0].is_sally() and sallies[0].army_id == "kingdom-3" and sallies[0].with_army.is_empty())
	var risk := _assert_breakdown(_node(_fort(map), "SallyRisk"), "sally")
	assert_eq(int(risk.total), 1, "the ruler's army stays inside")
	assert_true(_node(_fort(map), "SallyRisk").text.contains("destroyed"), _node(_fort(map), "SallyRisk").text)
	(_node(_fort(map), "SallyTick_kingdom-3") as BaseButton).button_pressed = false
	assert_eq(_siege_orders(map).size(), 0, "unticking cancels it")
	map.free()


func test_a_sally_refused_shows_the_reason() -> void:
	var s := besieged_keep()
	var map := _map(s, CROWN)
	assert_eq(map.queue_move("kingdom-3", "westwatch"), "", "the garrison army leaves instead")
	map.select_province("stonegate")
	var tick := _node(_fort(map), "SallyTick_kingdom-3") as BaseButton
	assert_true(tick.disabled, "an army with a move can't sally")
	var want := SiegeRules.check_siege_order(s, CROWN, SiegeOrder.sally("kingdom-3"), [MoveOrder.new("kingdom-3", "westwatch")])
	assert_eq(_node(_fort(map), "SallyReason_kingdom-3").text, String(want.reason))
	map.free()


func test_relief_queues_sallies_for_every_garrison_army_but_the_rulers() -> void:
	var s := besieged_keep(true)
	s.armies.append(Fx.army(s, ["kingdom-4", CROWN, "stonegate", Fx.units("crossbowmen", 3)]))
	var ruler := RulerRules.ruler_army(s, CROWN)
	var map := _map(s, CROWN)
	map.select_army("kingdom-7")
	var preview := map.preview_move("stonegate")
	assert_true(preview.contains("relief"), "a relief: %s" % preview)
	assert_true(preview.contains("The garrison comes out to join you"), preview)
	assert_true(preview.contains(TurnReportText.army_name(s, "kingdom-3")) and preview.contains(TurnReportText.army_name(s, "kingdom-4")), preview)
	assert_true(preview.contains("%s stays inside" % ruler.ruler.type.name), "the ruler stays inside: %s" % preview)
	assert_eq(map.queue_move("kingdom-7", "stonegate"), "")
	var sallies := _siege_orders(map)
	var by_army := {}
	for o in sallies:
		assert_true(o.is_sally(), "only sallies")
		assert_eq(o.with_army, "kingdom-7", "tied to the relief")
		by_army[o.army_id] = true
	assert_eq(by_army.keys().size(), 2, "every garrison army but the ruler's")
	assert_true(by_army.has("kingdom-3") and by_army.has("kingdom-4"))
	assert_false(by_army.has(ruler.id), "the ruler stays inside")
	assert_true(map.status_text.contains("join"), map.status_text)
	map.select_province("stonegate")
	assert_true(_node(_fort(map), "ReliefNote").text.contains("Westwatch"), "the fort panel shows the relief: %s" % _node(_fort(map), "ReliefNote").text)
	# Cancelling the relief move removes the tied sallies (the rules' re-check).
	var idx := -1
	for i in map.orders.orders().size():
		if map.orders.orders()[i] is MoveOrder:
			idx = i
	map.cancel_order(idx)
	assert_eq(_siege_orders(map).size(), 0, "the tied sallies went with the relief")
	map.free()


func test_a_sally_ticked_before_the_relief_goes_out_with_it() -> void:
	var s := besieged_keep()
	var map := _map(s, CROWN)
	assert_eq(map.set_sally("kingdom-3", true), "")
	assert_eq(_siege_orders(map)[0].with_army, "", "a sally of its own")
	assert_eq(map.queue_move("kingdom-7", "stonegate"), "")
	var sallies := _siege_orders(map)
	assert_eq(sallies.size(), 1, "still one sally for the army")
	assert_eq(sallies[0].with_army, "kingdom-7", "now tied to the relief, so it stays in if the relief never comes")
	var line: String = Array(map.orders.order_texts()).filter(func(t): return t.begins_with("Relief for Stonegate"))[0]
	assert_true(line.contains("The garrison comes out to join you: the Crown's 3rd"), line)
	map.free()


# --- the recruit picker ------------------------------------------------------------------------------

func test_the_recruit_picker_greys_a_besieged_a_full_and_a_just_captured_fort() -> void:
	var s := besieged_keep()
	Fx.rich(s, CROWN)
	s.find_province("blackwood").owner = CROWN
	s.find_province("highcrag").owner = CROWN
	Fx.set_fort(s, "highcrag", 1)
	s.find_province("highcrag").owned_since = s.current_turn  # taken last turn
	var map := _map(s, CROWN)
	var limit := int(FortData.LEVELS[2].recruits)
	for i in limit:
		assert_eq(map.queue_recruit_at("spearmen", "blackwood"), "", "recruit %d at Blackwood" % (i + 1))
	map.select_province("crownkeep")
	var picker := _node(map.details, "RecruitAtPicker")
	var want := {
		"stonegate": SiegeRules.check_recruit_at(s, CROWN, "stonegate", s.find_faction(CROWN).unit_types[0], 0),
		"blackwood": SiegeRules.check_recruit_at(s, CROWN, "blackwood", s.find_faction(CROWN).unit_types[0], limit),
		"highcrag": SiegeRules.check_recruit_at(s, CROWN, "highcrag", s.find_faction(CROWN).unit_types[0], 0),
	}
	assert_eq(String(want.stonegate.code), "fort_cut_off")
	assert_eq(String(want.blackwood.code), "fort_full")
	assert_eq(String(want.highcrag.code), "fort_just_taken")
	var capital := _node(picker, "RecruitAt_crownkeep") as Button
	assert_false(capital.disabled, "the capital takes recruits")
	assert_true(capital.button_pressed, "and is the fort picked")
	for pid in want:
		var b := _node(picker, "RecruitAt_%s" % pid) as Button
		assert_true(b.disabled, "%s is greyed" % pid)
		assert_true(b.tooltip_text.replace("\n", " ").contains(TooltipText.wrap_text(String(want[pid].reason)).replace("\n", " ")),
			"%s says why: %s" % [pid, b.tooltip_text])
		assert_eq(_node(picker, "RecruitAtReason_%s" % pid).text, String(want[pid].reason), "%s's reason is on screen" % pid)
	assert_true((_node(picker, "RecruitAt_blackwood") as Button).text.contains("%d of %d" % [limit, limit]), "the count: %s" % (_node(picker, "RecruitAt_blackwood") as Button).text)
	# Picking a fort selects it; its recruit buttons recruit there.
	s.find_province("stonegate").siege_since = 0
	map.free()


func test_recruit_buttons_recruit_at_the_picked_fort() -> void:
	var s := GameState.with_sieges(5)
	s.armies.clear()
	Fx.rich(s, CROWN)
	s.find_province("stonegate").owner = CROWN
	var map := _map(s, CROWN)
	map.select_province("stonegate")
	var heading := _node(map.details, "RecruitHeading") as Label
	assert_true(heading.text.contains("Stonegate"), heading.text)
	var b := _node(map.details, "Recruit_spearmen") as Button
	b.pressed.emit()
	var r := map.orders.orders()[0] as RecruitOrder
	assert_eq(r.at, "stonegate", "recruited at Stonegate")
	var line := map.orders.order_texts()[0]
	assert_true(line.contains("Stonegate") and line.contains("1 of %d" % int(FortData.LEVELS[2].recruits)), "the order names the fort and its count: %s" % line)
	# The engine is offered at a keep.
	var engine := FortData.engine_for(CROWN)
	assert_true(_has(map.details, "Recruit_%s" % String(engine.id)), "the Siege Ram is offered at a keep")
	map.free()


# --- hotseat privacy -----------------------------------------------------------------------------------

func test_a_rivals_siege_and_fortify_orders_never_show_also_in_hotseat() -> void:
	var s := besieged_keep()
	s.find_province("rivermarch").owner = CROWN
	var session := GameSession.new(s, [CROWN, CLANS], 4)
	var map := _map(session.state(), CROWN, session)
	assert_eq(map.orders.queue_fortify("rivermarch"), "")
	assert_eq(map.orders.set_sally("kingdom-3", true), "")
	assert_eq(session.current_orders().size(), 2)
	assert_eq(session.end_turn(), "")
	assert_eq(session.phase(), GameSession.Phase.HANDOFF, "hotseat: the cover first")
	session.acknowledge_handoff()
	map.set_state(session.state(), CLANS)
	assert_eq(map.orders.orders().size(), 0, "the Clans see none of the Crown's orders")
	map.select_province("rivermarch")
	assert_false(_has(map.details, "FortifyQueued"), "no Fortify of the Crown's shows")
	for c in map.details.find_children("*", "Label", true, false):
		assert_false((c as Label).text.contains("Fortify ordered") or (c as Label).text.contains("sally"), "nothing of the Crown's orders: %s" % (c as Label).text)
	map.select_province("stonegate")
	assert_false(_has(_fort(map), "SallyTick_kingdom-3"), "the Crown's sally ticks never show to the Clans")
	for c in _fort(map).find_children("*", "Label", true, false):
		assert_false((c as Label).text.to_lower().contains("sallies"), "no word of a queued sally: %s" % (c as Label).text)
	assert_false((map.regions["rivermarch"] as ProvinceRegion).fortify_ghost, "no scaffold ghost of the Crown's on the plate")
	# The Clans' own storm shows to them.
	assert_eq(map.set_storm("stonegate", true), "")
	assert_true((_node(_fort(map), "StormToggle") as BaseButton).button_pressed, "the Clans see their own storm")
	map.free()


func test_hotseat_game_screen_never_shows_the_other_seats_fort_orders() -> void:
	var s := besieged_keep()
	s.find_province("rivermarch").owner = CROWN
	var session := GameSession.new(s, [CROWN, CLANS], 4, AutoBattleResolver.new())
	var game := load(GAME_SCENE).instantiate() as GameScreen
	game.autosave_enabled = false
	assert_eq(game.load_game(SaveGame.make(session, {}, SaveGame.MANUAL, "Hotseat", 0)), "")
	game.handoff.ready_button.pressed.emit()
	assert_eq(game.session.current_player(), CROWN)
	assert_eq(game.map.queue_fortify("rivermarch"), "")
	game.map.select_province("rivermarch")
	assert_true(_has(game.map.details, "FortifyQueued"), "the Crown sees its own Fortify order")
	assert_true((game.map.regions["rivermarch"] as ProvinceRegion).fortify_ghost, "and its scaffold ghost on the plate")
	assert_eq(game.end_turn(), "")
	assert_true(game.handoff.visible, "the cover between the seats")
	game.handoff.ready_button.pressed.emit()
	assert_eq(game.session.current_player(), CLANS)
	game.map.select_province("rivermarch")
	assert_false(_has(game.map.details, "FortifyQueued"), "the Clans never see it")
	assert_false((game.map.regions["rivermarch"] as ProvinceRegion).fortify_ghost, "nor its ghost")
	game.free()


# --- the plate --------------------------------------------------------------------------------------

func test_the_plate_has_a_fort_chip_with_the_walls_bar() -> void:
	var s := besieged_keep()
	var map := _map(s, CROWN)
	var region: ProvinceRegion = map.regions["stonegate"]
	var chip := region.fort_chip
	assert_true(chip != null, "a fort chip on Stonegate's plate")
	var p := s.find_province("stonegate")
	assert_eq(chip.walls_bar.walls, p.walls)
	assert_eq(chip.walls_bar.walls_max, int(FortData.LEVELS[2].walls))
	assert_eq(chip.walls_bar.step, FortData.WALL_STEP, "the bar marks the storm steps")
	assert_true(chip.besieged, "a besieged chip")
	assert_true(chip.tooltip_text.begins_with(TooltipText.from_breakdown(Breakdown.walls(s, "stonegate"))), chip.tooltip_text)
	assert_true(chip.tooltip_text.contains("Thornmane Clans"), "the tooltip names the besiegers: %s" % chip.tooltip_text)
	assert_eq(String(chip.get_meta(CodexLink.META)), "siege", "a besieged chip links Siege")
	assert_true(map.regions["westwatch"].fort_chip == null, "no fort, no chip")
	assert_eq(map.regions["crownkeep"].fort_chip.label.text, FortData.LEVELS[3].name, "the capital's chip says Citadel")
	assert_false(map.regions["crownkeep"].fort_chip.besieged)
	# A breached fort and a construction site.
	p.walls = 0
	s.find_province("rivermarch").owner = CROWN
	s.find_province("rivermarch").works = {"faction": CROWN, "to": 1, "left": 2, "turn": 1}
	map.set_state(s, CROWN)
	assert_true(map.regions["stonegate"].fort_chip.label.text.contains("breached"), map.regions["stonegate"].fort_chip.label.text)
	var site: FortChip = map.regions["rivermarch"].fort_chip
	assert_true(site != null and site.label.text.contains("0/%d" % int(FortData.LEVELS[1].turns)), "the construction chip: %s" % (site.label.text if site else "none"))
	assert_eq(String(site.get_meta(CodexLink.META)), "construction")
	assert_false(GameState.new().sieges, "M1 plates are unchanged")
	var m1 := _map(GameState.new(3), CROWN)
	assert_true(m1.regions["stonegate"].fort_chip == null, "no chip without sieges")
	map.free()
	m1.free()


# --- the turn report --------------------------------------------------------------------------------

func test_report_lines_and_needs_you_for_both_sides() -> void:
	var s := Fx.state([["kingdom-3", CROWN, "stonegate", Fx.units("knights", 12)], ["beasts-5", CLANS, "blackwood", Fx.units("tuskers", 4)]],
		{"stonegate": CROWN, "blackwood": CLANS})
	Fx.rich(s, CLANS)
	var orders := {CROWN: [MoveOrder.new("kingdom-3", "blackwood")], CLANS: [RecruitOrder.new("tuskers", "blackwood")]}
	var result := Fx.resolve(s, orders)
	var after: GameState = result.new_state
	var events: Array = result.events
	assert_eq(Fx.events_of(events, "siege_started").size(), 1, "a siege started")
	var panel := TurnReportPanel.new()
	panel.show_report_data({"turn": 1, "header": "Turn 1 results", "events": events}, CLANS, false, after)
	assert_true(_has(panel, "Heading_sieges"), "a Sieges heading")
	assert_eq(_node(panel, "Heading_sieges").text, "Sieges")
	var rows := panel.event_rows().map(func(b): return b.text)
	var recruited: Array = rows.filter(func(t): return t.contains("recruited Tuskers"))
	assert_eq(recruited.size(), 1)
	var clause := "(%s, %d of %d this turn)" % [SiegeRules.level_word(2), 1, SiegeRules.recruit_limit(2)]
	assert_true(recruited[0].contains(clause), "the recruit line names the fort and its count: %s" % recruited[0])
	var needs := FortView.needs_you(after, CLANS, 1)
	assert_eq(needs.size(), 1, "the garrison gets a needs-you line")
	var p := after.find_province("blackwood")
	var dmg := SiegeRules.siege_damage_at(after, "blackwood")
	var end := SiegeRules.breach_turn(p.walls, int(dmg.total), 2)
	assert_true(String(needs[0].text).begins_with("Your fort at Blackwood is besieged"), needs[0].text)
	assert_true(String(needs[0].text).contains("end of turn %d" % end) and String(needs[0].text).contains("Sally, send relief, or hold."), needs[0].text)
	panel.show_siege_needs_you(needs)
	assert_true(_node(panel, "SiegeNeedsYou").get_child_count() == 1)
	var mine := FortView.needs_you(after, CROWN, 1)
	assert_eq(mine.size(), 1, "the besiegers get theirs")
	assert_true(String(mine[0].text).begins_with("Your armies besiege Blackwood: storm, wait for the walls to reach 0"), mine[0].text)
	# The breach, to both sides.
	p.walls = 0
	for fid in [CROWN, CLANS]:
		var lines := FortView.needs_you(after, fid, 1)
		assert_true(String(lines[0].text).begins_with("Blackwood's walls are down. Next turn (2) you fight there in the open, unless you leave"), lines[0].text)
	panel.free()


func test_the_captured_line_says_the_fort_came_with_it() -> void:
	var s := Fx.state([["kingdom-3", CROWN, "westwatch", Fx.units("knights", 2)]], {"westwatch": CROWN})
	var result := Fx.resolve(s, {CROWN: [MoveOrder.new("kingdom-3", "stonegate")]})
	var panel := TurnReportPanel.new()
	panel.show_report_data({"turn": 1, "header": "Turn 1", "events": result.events}, CROWN, false, result.new_state)
	var rows: Array = panel.event_rows().map(func(b): return b.text).filter(func(t): return t.contains("Stonegate fell"))
	assert_eq(rows.size(), 1)
	assert_true(rows[0].contains("It came with its keep"), "the fort clause: %s" % rows[0])
	panel.free()


# --- the first siege: a teaching moment (§9.5) -----------------------------------------------------------

static func _siege_battle(kind: String, why: String) -> Dictionary:
	return {"type": "battle", "phase": "battles", "provinces": ["stonegate"], "factions": [CLANS, CROWN], "armies": [], "cause": why,
		"text": "A battle at Stonegate.", "codex": "battle_rounds",
		"numbers": {"siege": {"kind": kind, "why": why, "fort": "keep", "walls": 4, "walls_max": 6,
			"walls_defense": 4 if kind == "storm" else 0, "cover_defense": 0 if kind == "storm" else 2, "garrison": 1,
			"from_inside": ["kingdom-3"], "turn_of_siege": 2},
			"report": {"sides": [{"faction": CLANS, "defender": false}, {"faction": CROWN, "defender": kind == "storm"}]}}}


func test_first_siege_sentences_show_once_per_player_also_in_hotseat() -> void:
	var c := SiegeChronicle.new()
	var started := {"type": "siege_started", "phase": "sieges", "provinces": ["stonegate"], "factions": [CLANS, CROWN], "text": "The Clans laid siege.", "codex": "siege"}
	var t3 := [started]
	c.add_turn(3, t3)
	for viewer in [CROWN, CLANS]:
		var lines := c.teach(t3, viewer, 3)
		assert_eq(lines.size(), 1, "%s's report of the first siege teaches it" % viewer)
		assert_eq(String(lines[0].kind), "siege")
		assert_true(is_same(lines[0].event, started))
		assert_true(String(lines[0].text).contains("A siege: the besiegers don't fight unless they storm the walls or the garrison comes out."), lines[0].text)
		assert_eq(String(lines[0].codex), "siege")
		assert_eq(c.teach(t3, viewer, 3).size(), 1, "reopening the same report shows it again")
	var t5 := [started.duplicate(true)]
	c.add_turn(5, t5)
	assert_eq(c.teach(t5, CROWN, 5).size(), 0, "later sieges add nothing")
	assert_eq(c.teach(t5, CLANS, 5).size(), 0)
	# The first storm, sally and breach each get one sentence.
	var t6 := [_siege_battle("storm", "storm"), _siege_battle("open", "sally"),
		{"type": "walls_breached", "phase": "sieges", "provinces": ["stonegate"], "factions": [CLANS, CROWN], "text": "Down.", "codex": "breach"}]
	c.add_turn(6, t6)
	var kinds := c.teach(t6, CROWN, 6).map(func(l): return String(l.kind))
	kinds.sort()
	assert_eq(kinds, ["breach", "sally", "storm"], "storm, sally and breach once each")
	assert_eq(c.teach(t6, CROWN, 7).size(), 0, "not on a later report")
	# A player who only now reads a report (hotseat: the second seat) still gets it once.
	assert_eq(c.teach(t6, CLANS, 6).size(), 3)
	# A chronicle rebuilt for a loaded game counts the sentences as seen.
	var loaded := SiegeChronicle.new()
	loaded.add_turn(3, t3)
	loaded.mark_seen([CROWN, CLANS])
	assert_eq(loaded.teach(t5, CROWN, 5).size(), 0)
	assert_eq(loaded.teach(t3, CROWN, 3).size(), 1, "the loaded turn's own report still teaches")


func test_the_report_panel_shows_the_first_siege_sentence_under_its_line() -> void:
	var s := Fx.state([["kingdom-3", CROWN, "stonegate", Fx.units("knights", 12)], ["beasts-5", CLANS, "blackwood", Fx.units("tuskers", 4)]],
		{"stonegate": CROWN, "blackwood": CLANS})
	var result := Fx.resolve(s, {CROWN: [MoveOrder.new("kingdom-3", "blackwood")]})
	var c := SiegeChronicle.new()
	c.add_turn(1, result.events)
	var panel := TurnReportPanel.new()
	panel.chronicle = c
	panel.show_report_data({"turn": 1, "header": "Turn 1", "events": result.events}, CROWN, false, result.new_state)
	var teach := panel.find_children("Teach_siege", "", true, false)
	assert_eq(teach.size(), 1, "the sentence under the siege line")
	var l := (teach[0] as Control).find_children("*", "Label", true, false)[0] as Label
	assert_true(l.text.contains("A siege:"), l.text)
	assert_eq(String(l.get_meta(CodexLink.META)), "siege", "linked to Siege")
	panel.free()


# --- the battle viewer's chips (§9.7) ----------------------------------------------------------------

func test_battle_viewer_chips_for_storm_open_and_breach() -> void:
	var storm := FortView.siege_chip({"kind": "storm", "why": "storm", "walls": 5, "walls_max": 9, "walls_defense": 4, "cover_defense": 0})
	assert_eq(String(storm.text), "Walls: +4 defense (5 of 9)")
	assert_true(RulesCodex.ENTRIES.has(String(storm.codex)))
	var sally := FortView.siege_chip({"kind": "open", "why": "sally", "walls": 4, "walls_max": 6, "walls_defense": 0, "cover_defense": FortData.COVER_DEFENSE})
	assert_eq(String(sally.text), "Outside the walls: nobody holds the ground; the garrison's fighters have +%d cover" % FortData.COVER_DEFENSE)
	var relief := FortView.siege_chip({"kind": "open", "why": "relief", "walls": 4, "walls_max": 6, "walls_defense": 0, "cover_defense": 0})
	assert_eq(String(relief.text), "Outside the walls: nobody holds the ground", "no cover line in a relief-only battle")
	var breach := FortView.siege_chip({"kind": "breach", "why": "breach", "walls": 0, "walls_max": 6, "walls_defense": 0, "cover_defense": FortData.COVER_DEFENSE})
	assert_eq(String(breach.text), "Through the breach: no walls, and nobody gets the hills")
	# In the viewer, the storm chip replaces the old fort line. A real battle's report, with the siege block S-2
	# will write (§4.4, §4.5).
	var s := Fx.state([["kingdom-3", CROWN, "highcrag", Fx.units("spearmen", 3)], ["beasts-5", CLANS, "thornvale", Fx.units("tuskers", 6)]],
		{"highcrag": CROWN, "thornvale": CLANS})
	var result := Fx.resolve(s, {CLANS: [MoveOrder.new("beasts-5", "highcrag")]}, true)
	var battles := Fx.events_of(result.events, "battle")
	assert_eq(battles.size(), 1, "a real battle to read")
	var report: Dictionary = battles[0].numbers.report.duplicate(true)
	report["fort"] = true
	report["siege"] = {"kind": "storm", "why": "storm", "walls": 5, "walls_max": 9, "walls_defense": 4, "cover_defense": 0, "garrison": 1}
	var viewer := BattleReportViewer.new()
	viewer.show_report(report, result.new_state)
	var chip := viewer.find_children("SiegeChip", "", true, false)
	assert_eq(chip.size(), 1, "the viewer shows the siege chip")
	assert_eq((chip[0] as Label).text, "Walls: +4 defense (5 of 9)")
	assert_true((chip[0] as Label).has_meta(CodexLink.META))
	for l in viewer.find_children("*", "Label", true, false):
		assert_false((l as Label).text.begins_with("Fort: the defending"), "walls replace the fort line")
	viewer.free()


func test_a_real_storm_shows_its_walls_chip_teaches_and_counts() -> void:
	var s := Fx.state([["kingdom-3", CROWN, "stonegate", Fx.units("knights", 20)], ["beasts-5", CLANS, "blackwood", Fx.units("tuskers", 2)]],
		{"stonegate": CROWN, "blackwood": CLANS})
	var result := Fx.resolve(s, {CROWN: [MoveOrder.new("kingdom-3", "blackwood"), SiegeOrder.storm("blackwood")]}, true)
	var battles := Fx.events_of(result.events, "battle")
	assert_eq(battles.size(), 1, "a storm from the march")
	var siege: Dictionary = battles[0].get("numbers", {}).get("siege", {})
	assert_eq(String(siege.get("kind", "")), "storm", "the battle carries its siege block (S-1b)")
	var walls := int(FortData.LEVELS[2].walls)
	var viewer := BattleReportViewer.new()
	viewer.show_event(battles[0], result.new_state)
	var chip := viewer.find_children("SiegeChip", "", true, false)
	assert_eq(chip.size(), 1, "the viewer reads the event's siege block")
	assert_eq((chip[0] as Label).text, "Walls: +%d defense (%d of %d)" % [SiegeRules.walls_defense(walls), walls, walls])
	viewer.free()
	var c := SiegeChronicle.new()
	c.add_turn(1, result.events)
	assert_eq(c.teach(result.events, CROWN, 1).map(func(l): return String(l.kind)), ["storm"], "the first storm teaches")
	assert_eq(int(c.stats()[CROWN].storms), 1, "and counts for the stormers")


# --- the victory screen --------------------------------------------------------------------------------

func test_the_victory_screen_counts_forts_built_sieges_won_and_storms() -> void:
	var c := SiegeChronicle.new()
	c.add_turn(4, [{"type": "fort_built", "phase": "sieges", "provinces": ["rivermarch"], "factions": [CROWN], "text": "", "codex": "fort_levels"}])
	c.add_turn(7, [{"type": "siege_ended", "phase": "sieges", "provinces": ["blackwood"], "factions": [CROWN, CLANS], "text": "", "codex": "siege",
		"numbers": {"owner": CLANS, "besieger": CROWN, "why": "battle"}}, _siege_battle("storm", "storm")])
	c.add_turn(8, [{"type": "siege_lifted", "phase": "sieges", "provinces": ["stonegate"], "factions": [CLANS, CROWN], "text": "", "codex": "siege",
		"numbers": {"owner": CROWN, "besieger": CLANS, "why": "beaten"}}])
	var stats := c.stats()
	assert_eq(int(stats[CROWN].forts_built), 1)
	assert_eq(int(stats[CROWN].sieges_won), 2, "a fort taken and a siege broken")
	assert_eq(int(stats[CLANS].storms), 1, "the Clans stormed once")
	var screen := VictoryScreen.new()
	screen.siege_stats = stats
	screen.show_victory({"winner": CROWN, "turn": 9, "turns_played": 9, "battles": 3, "provinces_held": {CROWN: 8, CLANS: 6}, "captures": [], "text": "x"},
		GameState.with_sieges(1), [CROWN, CLANS])
	var line := _node(screen, "Sieges_%s" % CROWN) as Label
	assert_true(line.text.contains("1 fort built") and line.text.contains("2 sieges won") and line.text.contains("0 storms"), line.text)
	assert_true(line.has_meta(CodexLink.META), "linked to the codex")
	assert_true(_node(screen, "SiegesHeading").visible)
	screen.show_victory({"winner": CROWN, "turn": 9, "turns_played": 9, "battles": 3, "provinces_held": {CROWN: 8, CLANS: 6}, "captures": [], "text": "x"},
		GameState.new(1), [CROWN, CLANS])
	assert_false(_node(screen, "SiegesHeading").visible, "a game without sieges shows no siege numbers")
	screen.free()


# --- the S-2 seam -------------------------------------------------------------------------------------

func test_the_odds_seam_shows_no_odds_until_s2_plugs_in() -> void:
	var s := besieged_keep()
	for kind in ["storm", "sally", "relief"]:
		assert_eq(FortView.siege_odds(kind, s, CLANS, "stonegate", []), {}, "%s odds wait for S-2" % kind)
	assert_eq(FortView.odds_text({}), "", "no odds, no line")
	assert_eq(FortView.odds_text({"ok": true, "label": "likely win", "wins": 21, "samples": 24}), "likely win (21 of 24 test battles)")
