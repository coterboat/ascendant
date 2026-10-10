extends "res://tests/test_case.gd"
## UX-3 (#206; design/UX_WAR_TABLE.md §3): the selection cards. A province and an army are two distinct sides: the province card
## manages the land (its fort, its recruitment) and the army card manages troops. What each test pins:
##   the cards replaced UX-1's temporary details card, as the selection host's presenter, in the Table's card slot;
##   the province card: the facts with their breakdowns, the fort (chip, walls, recruits a turn), the armies there (each selects),
##     and the actions on an owned province (Recruit's section, Fortify, the fort panel), kept in view above the scroll;
##   the army card: portraits with hit-point bars (the commander and the ruler gilt-ringed), strength, the army's own order and its
##     real actions (March, Change route, Storm or Sally, Cast, Cancel), and your other armies in the province for ARM-1;
##   March: the card folds into a slim strip, registered with UiCancel as the march layer; Esc and a right-click end it;
##   a rival's army: what FogView allows, and no actions;
##   the orders list stays under the tray's Orders button, with its cancel buttons;
##   a click on the land is the province side; every number on a card explains itself.
## Placement at the three sizes on both boards is tests/test_table_geometry.gd's (the live probe measures the card in each state).
## Numbers and words come from the data and the rules, never from this file.

const Fx := preload("res://tests/siege_fixtures.gd")
const FortTest := preload("res://tests/test_fort_panel.gd")
const GAME_SCENE := "res://ui/game_screen.tscn"
const MAP_SCENE := "res://ui/map_screen.tscn"
const CROWN := "kingdom"
const CLANS := "beasts"
const VS_COMPUTER := {"players": [CROWN, CLANS], "seed": 4242, "ai": {CLANS: "normal"}}
const ALL := {"rulers": true, "paths": true, "sieges": true, "fog": true, "magic": true, "independents": true}


# --- fixtures -------------------------------------------------------------------------------------

func _game(config: Dictionary = VS_COMPUTER) -> GameScreen:
	var game := load(GAME_SCENE).instantiate() as GameScreen
	game.autosave_enabled = false
	game.start_game(config)
	return game


func _map(s: GameState, viewer: String = CROWN) -> MapScreen:
	var map: MapScreen = load(MAP_SCENE).instantiate()
	map.set_state(s, viewer)
	return map


func _node(root: Node, node_name: String) -> Node:
	var found := root.find_children(node_name, "", true, false)
	if found.is_empty():
		fail("found %s under %s" % [node_name, root.name])
		return null
	return found[0]


func _has(root: Node, node_name: String) -> bool:
	return not root.find_children(node_name, "", true, false).is_empty()


## Visible up to `root` (is_visible_in_tree() needs the tree, which headless tests don't enter).
func _shown(c: Control, root: Node) -> bool:
	var n: Node = c
	while n != null and n != root:
		if n is CanvasItem and not n.visible:
			return false
		n = n.get_parent()
	return true


## Every visible text under `node`.
func _texts(node: Node, out: Array = []) -> Array:
	if node is CanvasItem and not (node as CanvasItem).visible:
		return out
	if node is Label or node is Button:
		out.append(node.text)
	for c in node.get_children():
		_texts(c, out)
	return out


func _opponent_army(s: GameState, at: String, units: Array) -> Army:
	return Fx.army(s, ["beasts-9", CLANS, at, units])


# --- the cards replaced the temporary details card ---------------------------------------------------

func test_the_cards_are_the_selection_hosts_presenter_in_the_tables_card_slot() -> void:
	var game := _game()
	var map := game.map
	var hud := map.table()
	assert_true(map.cards is SelectionCards, "the presenter is the selection cards")
	assert_eq(map.selection_host.presenter(), map.cards)
	assert_true(hud.pieces().has(map.cards) and map.cards.get_parent() == hud, "the Table's card piece, which places it")
	assert_false(ResourceLoader.exists("res://ui/details_card.gd"), "UX-1's temporary details card is gone")
	assert_eq(map.cards.mode, "province", "the capital is selected: its card")
	assert_true(map.cards.holder.get_child(0) is ProvinceCard)
	map.select_army("kingdom-1")
	assert_eq(map.cards.mode, "army")
	assert_true(map.cards.holder.get_child(0) is ArmyCard, "an army click opens the army card")
	assert_true(map.cards.holder.get_child(0).get_parent() == map.cards.holder and map.details.is_ancestor_of(map.cards.holder), "map.details holds the open card")
	game.free()


func test_a_click_on_the_land_is_the_province_side_and_a_click_on_an_army_the_army_side() -> void:
	var game := _game()
	var map := game.map
	map.select_army("kingdom-1")
	assert_eq(map.selected_army_id, "kingdom-1")
	map.select_province("crownkeep")
	assert_eq(map.selected_army_id, "", "clicking the land its army stands on is the province side: the army is unselected")
	assert_eq(map.cards.mode, "province")
	assert_true(_has(map.details, "RecruitButton"), "so the land's actions are there")
	map.select_army("kingdom-1")
	assert_eq(map.cards.mode, "army", "and a click on the army is the army side")
	assert_eq(map.selected_province_id, "crownkeep")
	# With an army selected a click on a neighbour is still its move.
	map.select_province("westwatch")
	assert_eq(map.orders.orders().size(), 1, "the two-click move still works")
	assert_eq(map.selected_army_id, "kingdom-1", "and the army stays selected")
	game.free()


# --- the province card -----------------------------------------------------------------------------

func test_the_province_card_has_the_facts_the_fort_and_the_actions_of_the_land() -> void:
	var game := _game(_all_on())
	var map := game.map
	var s := map.state
	var capital: String = s.find_faction(CROWN).capital
	map.select_province(capital)
	var card := map.details
	var p := s.find_province(capital)
	assert_eq((_node(card, "ProvinceName") as Label).text, p.name)
	assert_true(_has(card, "OwnerBanner"), "flying its owner's banner")
	for name in ["OwnerLabel", "TerrainLabel", "IncomeLabel", "CapitalLabel", "NeighborsLabel", "FortLabel"]:
		var l := _node(card, name) as Label
		assert_true(l.has_meta(CodexLink.META), "%s links its codex entry" % name)
		assert_false(l.tooltip_text.is_empty(), "%s explains itself" % name)
	var income := _node(card, "IncomeLabel") as Label
	assert_eq(income.text, "Income: %d gold per turn" % int(Breakdown.province_income(s, capital).total))
	assert_true(income.tooltip_text.contains("= "), "the income's breakdown")
	# The fort: the chip, the walls and the recruits a turn (with how many are ordered), without opening the fort panel.
	assert_true(_has(card, "FortChip"), "the fort chip, as the plate has it")
	var walls := _node(card, "WallsLabel") as Label
	var recruits := _node(card, "RecruitLimitLabel") as Label
	assert_true(_shown(walls, card) and _shown(recruits, card), "the walls and the recruit cap show on the closed card")
	assert_true(recruits.text.contains("ordered"), "with the recruits ordered: %s" % recruits.text)
	assert_false(_shown(_node(card, "SiegeStatusLabel") as Label, card), "a quiet fort's siege line waits for the fort panel")
	# The actions are kept in view above the scrolling card.
	for name in ["RecruitButton", "FortPanelButton"]:
		var b := _node(card, name) as Button
		assert_true(map.cards.pinned.is_ancestor_of(b), "%s is pinned above the scroll" % name)
		assert_false(map.cards.scroll.is_ancestor_of(b), "and not in it")
	# The armies there, each a button that selects it, with its portraits.
	var here := s.armies.filter(func(a): return a.location == capital)
	assert_eq(card.find_children("ArmyRow_*", "", true, false).size(), here.size(), "every army there is listed")
	for a in here:
		var row := _node(map.details, "ArmyRow_%s" % a.id.validate_node_name())
		assert_true(row.find_child("UnitStrip", true, false) != null, "with its portraits")
		(row.find_child("ArmyButton", true, false) as Button).pressed.emit()
		assert_eq(map.selected_army_id, a.id, "pressing it selects the army")
		assert_eq(map.cards.mode, "army", "and opens its card")
		map.select_province(capital)
	game.free()


func test_enchantments_and_a_rivals_land_show_on_the_province_card() -> void:
	var s := GameState.with_magic(9, {CROWN: "regents_court", CLANS: "clan_moot"})
	s.enchantments.append({"id": "kingdom-e1", "ritual": "sanctum_ward", "faction": CROWN, "kind": "ward", "province": "crownkeep",
		"armies": [], "cast_turn": 1, "until_turn": 3, "bonus": 0, "ending": false})
	var map := _map(s, CROWN)
	map.select_province("crownkeep")
	assert_true(_has(map.details, "Enchantment_sanctum_ward"), "the ward on the land is on its card")
	map.select_province("fangridge")
	assert_false(_has(map.details, "RecruitButton"), "a rival's capital has no Recruit")
	assert_false(_has(map.details, "FortifyButton"), "and no Fortify")
	assert_false(_has(map.details, "RecruitSection"), "and no recruit section")
	map.free()


func test_recruit_opens_a_section_that_stays_open_through_orders_and_closes_with_the_selection() -> void:
	var game := _game()
	var map := game.map
	var cards := map.cards
	var capital: String = map.state.find_faction(CROWN).capital
	map.select_province(capital)
	var button := _node(map.details, "RecruitButton") as Button
	var section := _node(map.details, "RecruitSection") as Control
	assert_false(section.visible, "the section is closed to begin with")
	assert_false(cards.section_open("recruit"))
	button.button_pressed = true  # the toggle, as a click does
	section = _node(map.details, "RecruitSection") as Control
	assert_true(cards.section_open("recruit") and section.visible, "the Recruit button opens it")
	assert_true((_node(map.details, "RecruitButton") as Button).button_pressed, "and its button shows it is open")
	var buy := section.find_children("Recruit_*", "Button", true, false)
	assert_eq(buy.size(), map.orders.recruitable_types().size(), "one button per unit type")
	for b in buy:
		assert_true(b.icon != null, "each wears its portrait")
	(buy[0] as Button).pressed.emit()
	assert_eq(game.session.current_orders().size(), 1, "a recruit button queues through the orders, as before")
	assert_true((_node(map.details, "RecruitSection") as Control).visible, "the order rebuilt the card, and the section stayed open")
	assert_true(_has(map.details, "GoldAfterLabel"), "with the gold left after your orders")
	assert_false(_texts(map.details).has("Your orders this turn"), "the orders list is the tray's, not the section's")
	map.select_province("westwatch")
	assert_false(cards.section_open("recruit"), "another province closes it")
	map.select_province(capital)
	assert_false((_node(map.details, "RecruitSection") as Control).visible, "and it is closed when the capital comes back")
	game.free()


func test_the_recruit_picker_of_a_game_with_forts_keeps_the_section_open_between_your_forts() -> void:
	var s := Fx.state([["kingdom-1", CROWN, "crownkeep", ["spearmen"]]], {"stonegate": CROWN, "westwatch": CROWN})
	var map := _map(s, CROWN)
	map.select_province("crownkeep")
	assert_true(_has(map.details, "RecruitButton"), "the capital recruits")
	map.cards.open_section("recruit")
	var picker := _node(map.details, "RecruitAtPicker")
	assert_true(picker != null, "the picker lists your forts")
	var stonegate := _node(picker, "RecruitAt_stonegate") as Button
	assert_true(stonegate != null)
	stonegate.pressed.emit()
	assert_eq(map.selected_province_id, "stonegate", "the picker selects that fort")
	assert_true(map.cards.section_open("recruit"), "and the section stays open at it")
	assert_eq((_node(map.details, "RecruitHeading") as Label).text, "Recruit at Stonegate")
	map.free()


func test_fortify_is_the_cards_own_action_and_the_fort_panel_opens_whole() -> void:
	var s := GameState.with_sieges(5)
	s.armies.clear()
	s.find_province("rivermarch").owner = CROWN
	var map := _map(s, CROWN)
	map.select_province("rivermarch")
	var button := _node(map.details, "FortifyButton") as Button
	assert_true(map.cards.pinned.is_ancestor_of(button), "Fortify is pinned above the scroll, as an action of the card")
	assert_false(_has(map.details, "RecruitButton"), "a province with no fort takes no recruits")
	assert_false(_has(map.details, "FortPanelButton"), "and has no fort panel until a fort or site stands")
	button.pressed.emit()
	var queued := map.orders.orders().filter(func(o): return o is FortifyOrder)
	assert_eq(queued.size(), 1, "one FortifyOrder, through today's flow")
	assert_eq(String(queued[0].province), "rivermarch")
	assert_true(_has(map.details, "FortifyQueued"), "the card says it is ordered")
	assert_false(_has(map.details, "FortifyButton"), "in place of the button")
	map.free()
	# A fort with a siege: the panel's summary is always there, the rest opens with its button.
	var keep := FortTest.besieged_keep()
	var m2 := _map(keep, CROWN)
	m2.select_province("stonegate")
	var siege := _node(m2.details, "SiegeDamageLabel") as Label
	var walls := _node(m2.details, "WallsLabel") as Label
	assert_true(_shown(walls, m2.details), "walls show on the closed card")
	assert_true(_shown(_node(m2.details, "SiegeStatusLabel") as Label, m2.details), "so does a siege that stands")
	assert_false(_shown(siege, m2.details), "the siege's numbers wait for the fort panel")
	var open := _node(m2.details, "FortPanelButton") as Button
	open.button_pressed = true
	assert_true(m2.cards.section_open("fort"))
	assert_true(_shown(_node(m2.details, "SiegeDamageLabel") as Label, m2.details), "the Fort panel button opens the whole panel")
	assert_true(_has(m2.details, "SallyHeading"), "with the garrison's Sally choices")
	m2.free()


# --- the army card ------------------------------------------------------------------------------------

func test_the_army_card_shows_portraits_with_hit_point_bars_strength_and_the_commander() -> void:
	var s := GameState.new(3)
	var army: Army = s.find_army("kingdom-1")
	army.units[0].current_hp = maxi(1, army.units[0].type.hp / 2)  # one fighter is wounded
	var map := _map(s, CROWN)
	map.select_army(army.id)
	var card := map.details
	var strip := _node(card, "UnitStrip") as UnitStrip
	var chips := strip.chips()
	assert_eq(chips.size(), army.units.size() + 1, "a portrait for every fighter and the commander")
	assert_true((chips[0] as UnitStrip.Chip).is_commander, "the commander first")
	assert_eq(((chips[0] as UnitStrip.Chip).get_child(0) as Art.PortraitCard).frame, UiPalette.GILT, "framed in gilt")
	for i in army.units.size():
		var chip := chips[i + 1] as UnitStrip.Chip
		assert_true(chip.has_bar(), "each with a hit-point bar")
		assert_eq(chip.unit_ref, army.units[i])
		assert_true(is_equal_approx(chip.fraction(), float(army.units[i].current_hp) / float(army.units[i].type.hp)), "the bar is its hit points over its maximum")
	assert_true((chips[1] as UnitStrip.Chip).fraction() < 1.0, "the wounded one is a shorter bar")
	assert_true(chips[1].tooltip_text.contains("hit points"), "hovering one names it and its hit points: %s" % chips[1].tooltip_text)
	var strength := _node(card, "StrengthLabel") as Label
	assert_eq(strength.text, "Rough strength: %d" % int(Breakdown.army_strength(s, army.id).total))
	assert_true(strength.tooltip_text.contains("= "), "strength keeps today's breakdown tooltip")
	assert_eq(String(strength.get_meta(CodexLink.META)), "army_strength")
	assert_eq((_node(card, "UnitsLabel") as Label).text, "Units: %d" % army.units.size())
	assert_true(_has(card, "CommanderLabel"), "the commander line")
	assert_false(_has(card, "ArmySight"), "sight is a fog line: none without fog")
	map.free()


func test_a_strip_without_bars_says_nothing_of_hit_points() -> void:
	var s := GameState.new(3)
	var army: Army = s.find_army("beasts-1")
	army.units[0].current_hp = 1
	for with_bars in [true, false]:
		var strip := UnitStrip.make(s, army, Vector2(40, 40), Callable(), with_bars)
		assert_eq(strip.chips().size(), army.units.size() + (1 if army.commander != null else 0))
		for chip in strip.chips():
			assert_eq(chip.has_bar(), with_bars, "the bar is drawn only where hit points are shown")
			var says: bool = chip.tooltip_text.contains(" of %d hit points" % int((chip as UnitStrip.Chip).unit_ref.type.hp))
			assert_eq(says, with_bars, "and so is the number in the tooltip (a rival's hit points under fog are not ours to see)")


func test_a_rulers_army_card_has_the_ruler_gilt_ringed_with_its_hit_points() -> void:
	var s := GameState.with_rulers(7)
	var ruler := RulerRules.ruler_army(s, CROWN)
	ruler.ruler.current_hp = 5
	var map := _map(s, CROWN)
	map.select_army(ruler.id)
	var chip := _node(map.details, "Chip_ruler") as UnitStrip.Chip
	assert_true(chip.is_ruler and (chip.get_child(0) as Art.PortraitCard).frame == UiPalette.GILT, "the ruler, gilt-ringed")
	assert_true(is_equal_approx(chip.fraction(), 5.0 / float(int(Breakdown.ruler_stat(s, CROWN, "hp").total))), "its bar is its hit points over its maximum")
	assert_true(_has(map.details, "OpenRulerPanel"), "and the Ruler panel button")
	assert_eq((_node(map.details, "RulerRow") as Control).find_children("*", "PortraitCard", true, false).size(), 0, "the face is not shown twice")
	map.free()


func test_under_fog_the_army_card_says_how_far_it_sees() -> void:
	var game := _game({"players": [CROWN, CLANS], "seed": 4242, "fog": true, "ai": {CLANS: "normal"}})
	var map := game.map
	map.select_army("kingdom-1")
	var line := _node(map.details, "ArmySight") as Label
	assert_eq(line.text, FogView.army_sight_line(map.state.find_army("kingdom-1")), "sight range, in the fog line's words")
	assert_true(line.has_meta(CodexLink.META))
	game.free()


# --- the army's actions --------------------------------------------------------------------------------

func test_march_folds_the_card_into_a_strip_and_esc_brings_it_back() -> void:
	var game := _game()
	var map := game.map
	var cards := map.cards
	map.select_army("kingdom-1")
	var march := _node(map.details, "MarchButton") as Button
	assert_true(cards.pinned.is_ancestor_of(march), "March is pinned: the card's first action is always in view")
	assert_false(march.disabled)
	var full := cards.desired_height()
	march.pressed.emit()
	assert_true(cards.marching, "March starts picking a destination")
	assert_true(cards.strip.visible and not cards._box.visible, "the card folds into the strip")
	assert_eq(cards.strip_label.text, "March: pick a province · Esc to cancel")
	assert_true(cards.desired_height() < full * 0.5 and cards.desired_height() < 90.0, "a slim strip, docked in the card's place (%f of %f)" % [cards.desired_height(), full])
	assert_eq(map.ui_cancel.topmost(), "march", "UiCancel's march layer is the topmost thing")
	assert_eq(map.ui_cancel.cancel(), "march", "Esc ends the targeting and only that")
	assert_false(cards.marching)
	assert_true(cards.visible and cards._box.visible and not cards.strip.visible, "the card is back")
	assert_eq(map.selected_army_id, "kingdom-1", "with the army still selected")
	assert_eq(map.ui_cancel.topmost(), "card", "and the next Esc would close the card")
	# A right-click on empty board ends it the same way.
	cards.begin_march()
	assert_eq(map.ui_cancel.cancel(true), "march")
	assert_false(cards.marching)
	# The strip's own cross.
	cards.begin_march()
	cards.strip_cancel.pressed.emit()
	assert_false(cards.marching)
	game.free()


func test_picking_a_destination_orders_the_march_and_a_refusal_keeps_the_pick_going() -> void:
	var game := _game()
	var map := game.map
	var cards := map.cards
	var army: Army = map.state.find_army("kingdom-1")
	var here := map.state.find_province(army.location)
	var far := ""
	for p in map.state.provinces:
		if p.id != here.id and not here.neighbors.has(p.id):
			far = p.id
			break
	map.select_army(army.id)
	cards.begin_march()
	map.select_province(far)
	assert_true(cards.marching, "a refused destination leaves the pick going")
	assert_true(cards.strip_note.visible and not cards.strip_note.text.is_empty(), "the strip says why: %s" % cards.strip_note.text)
	assert_eq(cards.strip_note.text, TurnResolver.check_move(map.state, CROWN, MoveOrder.new(army.id, far)).reason, "in the rules' own words")
	assert_eq(map.orders.orders().size(), 0, "and nothing was ordered")
	map.select_province(here.neighbors[0])
	assert_false(cards.marching, "a destination ends it")
	assert_eq(map.orders.orders().size(), 1, "with the move ordered through today's flow")
	assert_true(map.orders.orders()[0] is MoveOrder and map.orders.orders()[0].to == here.neighbors[0])
	assert_eq(map.selected_army_id, army.id, "the army stays selected")
	assert_true(cards.visible and cards._box.visible, "and its card is back, showing the order")
	var line := _node(map.details, "OrderLine") as Label
	assert_true(line.text.contains(map.state.find_province(here.neighbors[0]).name), "the order's forecast line: %s" % line.text)
	# It already has a move: March is greyed, and says why.
	var march := _node(map.details, "MarchButton") as Button
	assert_true(march.disabled, "no second move")
	assert_true(march.tooltip_text.contains("already has a move order"), march.tooltip_text)
	game.free()


func test_cancel_order_withdraws_the_armys_order() -> void:
	var game := _game()
	var map := game.map
	map.select_army("kingdom-1")
	map.select_province("westwatch")
	assert_eq(game.session.current_orders().size(), 1)
	var cancel := _node(map.details, "CancelButton") as Button
	assert_true(map.cards.pinned.is_ancestor_of(cancel), "pinned with the other actions")
	cancel.pressed.emit()
	assert_eq(game.session.current_orders().size(), 0, "the order is gone, through the orders' own cancel")
	assert_false(_has(map.details, "CancelButton"), "and so is its button")
	assert_false((_node(map.details, "MarchButton") as Button).disabled, "March is offered again")
	game.free()


func test_change_route_is_offered_for_a_road_move_with_another_way_through_only() -> void:
	var s := GameState.with_rulers(7, {CROWN: "regents_court"})
	for pid in ["westwatch", "stonegate", "highcrag"]:
		s.find_province(pid).owner = CROWN
	var map := _map(s, CROWN)
	map.select_army("kingdom-1")
	map.select_province("westwatch")  # a plain one-step move
	assert_false(_has(map.details, "ViaButton"), "no road move, no Change route")
	map.free()
	var s2 := GameState.with_rulers(7, {CROWN: "regents_court"})
	s2.find_army("kingdom-1").location = "thornvale"
	for pid in ["thornvale", "stonegate", "wildmoor", "blackwood"]:
		s2.find_province(pid).owner = CROWN
	var m2 := _map(s2, CROWN)
	m2.select_army("kingdom-1")
	assert_false(_has(m2.details, "ViaButton"), "no order yet: no route to change")
	m2.select_province("blackwood")
	var via := _node(m2.details, "ViaButton") as Button
	assert_eq(via.text, "Change route")
	assert_true(m2.cards.pinned.is_ancestor_of(via), "an action of the card")
	assert_true(via.tooltip_text.contains("Wildmoor"), "it says where it goes instead: %s" % via.tooltip_text)
	var first: String = m2.orders.orders()[0].via
	via.pressed.emit()
	assert_true(m2.orders.orders()[0].is_road_move() and m2.orders.orders()[0].via != first, "change_via sent it the other way")
	assert_eq(m2.orders.orders().size(), 1, "still one order")
	m2.free()


func test_storm_and_sally_open_the_fort_panel_from_the_army_card() -> void:
	var s := FortTest.besieged_keep()
	# The besieger: Storm or wait.
	var map := _map(s, CLANS)
	map.select_army("beasts-5")
	var button := _node(map.details, "SiegeButton") as Button
	assert_eq(button.text, "Storm the walls")
	assert_true(map.cards.pinned.is_ancestor_of(button), "an action of the card")
	var frame := _node(map.details, "SiegeFrame") as Control
	assert_false(frame.visible, "the fort panel is closed until the button opens it")
	button.button_pressed = true
	frame = _node(map.details, "SiegeFrame") as Control
	assert_true(frame.visible, "the button opens the fort panel under the card")
	var toggle := _node(frame, "StormToggle") as BaseButton
	assert_false(toggle.button_pressed)
	toggle.button_pressed = true
	assert_eq(map.orders.orders().filter(func(o): return o is SiegeOrder and o.is_storm()).size(), 1, "the storm is queued through today's flow (SiegeOrder)")
	assert_true(map.cards.section_open("siege"), "and the card keeps the panel open")
	assert_true((_node(map.details, "StormToggle") as BaseButton).button_pressed, "showing the storm ordered")
	map.free()
	# The besieged: Sally.
	var m2 := _map(s, CROWN)
	m2.select_army("kingdom-3")
	var sally := _node(m2.details, "SiegeButton") as Button
	assert_eq(sally.text, "Sally: lift the siege")
	sally.button_pressed = true
	var tick := _node(m2.details, "SallyTick_kingdom-3") as BaseButton
	assert_true(_shown(tick, m2.details), "the Sally tick, in the opened panel")
	tick.button_pressed = true
	assert_eq(m2.orders.orders().filter(func(o): return o is SiegeOrder and o.is_sally()).size(), 1)
	# An army that is nowhere near a siege has no such action.
	m2.select_army("kingdom-7")
	assert_false(_has(m2.details, "SiegeButton"), "Westwatch is quiet")
	m2.free()


func test_a_cast_order_is_the_armys_order_and_the_card_cancels_it() -> void:
	var s := GameState.with_magic(9, {CROWN: "regents_court", CLANS: {"ruler": "fang_chieftain", "mandates": ["tithe_of_blood"]}})
	s = AscensionRules.with_nodes(s, CLANS, ["bloodbolt", "bloodrot", "briar_snare", "call_the_pack"])
	for f in s.factions:
		f.gold = 200
	var a := Army.new()
	a.id = s.new_army_id(CLANS)
	a.owner = CLANS
	a.location = "thornvale"
	for t in ["shamans", "tuskers", "tuskers"]:
		a.units.append(Unit.new(TurnResolver.recruitable_type(s.find_faction(CLANS), t, s), CLANS))
	s.armies.append(a)
	s.find_province("thornvale").owner = CLANS
	var map := _map(s, CLANS)
	map.select_army(a.id)
	var cast := _node(map.details, "CastRitual") as Button
	assert_true(map.cards.pinned.is_ancestor_of(cast), "Cast a ritual is an action of the card")
	cast.pressed.emit()
	assert_true(map.cast_dialog != null and map.cast_dialog.visible, "it opens today's cast dialog")
	map.cast_dialog.select_ritual("bloodrot")
	map.cast_dialog.select_target("crownkeep")
	map.cast_dialog.confirm()
	assert_eq(map.orders.orders().size(), 1, "the ritual is ordered")
	assert_true(map.orders.orders()[0] is CastOrder)
	var line := _node(map.details, "OrderLine") as Label
	assert_true(line.text.begins_with("Cast Bloodrot on Crownkeep"), "the army card words its cast order: %s" % line.text)
	assert_true((_node(map.details, "MarchButton") as Button).disabled, "an army that casts holds: no March")
	(_node(map.details, "CancelButton") as Button).pressed.emit()
	assert_eq(map.orders.orders().size(), 0, "Cancel order withdraws the ritual")
	map.free()


# --- a rival's army ---------------------------------------------------------------------------------

func test_a_rivals_army_card_shows_what_it_may_and_has_no_actions() -> void:
	var s := GameState.new(3)
	var map := _map(s, CROWN)
	map.select_army("beasts-1")
	assert_eq(map.cards.mode, "army", "a rival's army has its card too")
	assert_true(_has(map.details, "Army_beasts-1"))
	assert_true(_has(map.details, "ArmyTitle") and _has(map.details, "StrengthLabel"), "what the side panel always showed of it, without fog")
	for name in ["ArmyActions", "MarchButton", "CancelButton", "ViaButton", "SiegeButton", "CastRitual"]:
		assert_false(_has(map.details, name), "no %s on a rival's army" % name)
	assert_eq(map.cards.pinned.get_child_count(), 0, "nothing is pinned: there is nothing to do")
	assert_false(_has(map.details, "ArmiesHere"), "and your other armies are not its business")
	map.free()


func test_under_fog_a_rivals_stand_in_shows_only_its_sighting() -> void:
	var s := GameState.new(3)
	s.find_army("beasts-1").location = "westwatch"  # next to the Crown's capital: glimpsed
	s.setup_fog([])
	var session := GameSession.new(s, [CROWN, CLANS], 3, StubBattleResolver.new())
	var view := session.state_for(CROWN)
	var stand_ins := view.armies.filter(func(a): return a.owner == CLANS and FogView.is_stand_in(a))
	assert_true(not stand_ins.is_empty(), "the rival is in the view as a stand-in")
	var rival: Army = stand_ins[0]
	var map: MapScreen = load(MAP_SCENE).instantiate()
	map.set_fog(session.memory(CROWN), session.intel(CROWN), session.view_before(CROWN))
	map.set_state(view, CROWN)
	map.select_army(rival.id)
	var card := map.details
	assert_true(_has(card, "FightersLabel"), "its sighting: %s" % [_texts(card)])
	var fighters := (_node(card, "FightersLabel") as Label).text
	assert_true(fighters.contains("about") or fighters.contains("Fighters"), fighters)
	assert_false(_has(card, "UnitStrip"), "no portraits row: it holds no fighters we could count exactly")
	for name in ["ArmyActions", "MarchButton", "CancelButton", "SiegeButton", "CastRitual"]:
		assert_false(_has(card, name), "no %s" % name)
	assert_eq(map.cards.pinned.get_child_count(), 0)
	var all_text := "\n".join(_texts(card))
	for u in s.find_army("beasts-1").units:
		assert_false(all_text.contains("%s ×" % u.type.name), "no exact count of %s: %s" % [u.type.name, all_text])
	# The province card lists it by its sighting, as a button.
	map.select_province("westwatch")
	var row := _node(map.details, "ArmyRow_%s" % rival.id.validate_node_name())
	assert_eq((row.find_child("ArmyButton", true, false) as Button).text, FogView.army_heading(view, rival))
	assert_true(row.find_child("UnitStrip", true, false) == null, "with no portraits")
	map.free()


# --- your other armies here (ARM-1's place) ---------------------------------------------------------

func test_your_other_armies_in_the_province_are_laid_out_on_the_card() -> void:
	var s := GameState.new(3)
	var second := Army.new()
	second.id = s.new_army_id(CROWN)
	second.owner = CROWN
	second.location = "crownkeep"
	second.units.append(Unit.new(TurnResolver.recruitable_type(s.find_faction(CROWN), "knights"), CROWN))
	s.armies.append(second)
	var map := _map(s, CROWN)
	map.select_army("kingdom-1")
	var box := _node(map.details, "ArmiesHere") as Control
	var rows := box.find_children("ArmyRow_*", "", true, false)
	assert_eq(rows.size(), 1, "the other army, not this one")
	assert_eq(String(rows[0].name), "ArmyRow_%s" % second.id.validate_node_name())
	assert_true(rows[0].find_child("UnitStrip", true, false) != null, "with its portraits")
	assert_eq((rows[0].find_child("UnitStrip", true, false) as UnitStrip).chips().size(), second.units.size(), "one for each fighter")
	(rows[0].find_child("ArmyButton", true, false) as Button).pressed.emit()
	assert_eq(map.selected_army_id, second.id, "a row selects its army (ARM-1 adds drag, Split, Merge all and Swap commanders here)")
	map.free()


# --- the orders list under the tray's Orders button ----------------------------------------------------

func test_the_trays_orders_button_shows_the_list_and_the_card_comes_back() -> void:
	var game := _game()
	var map := game.map
	var cards := map.cards
	map.select_army("kingdom-1")
	map.select_province("westwatch")
	var hud := map.table()
	hud.orders_button.pressed.emit()
	assert_eq(cards.mode, "orders")
	assert_true(_texts(map.details).has("Your orders this turn"))
	assert_true(cards.back_button.visible, "a way back to the card of what is selected")
	assert_eq(map.details.find_children("Order_*", "", true, false).size(), 1)
	(_node(map.details, "CancelButton") as Button).pressed.emit()
	assert_eq(game.session.current_orders().size(), 0, "cancel works as before")
	assert_eq(cards.mode, "orders", "and the list stays")
	cards.back_button.pressed.emit()
	assert_eq(cards.mode, "army", "Back returns to the army card")
	hud.orders_button.pressed.emit()
	assert_eq(map.ui_cancel.cancel(), "card", "Esc is the card layer")
	assert_eq(cards.mode, "army", "and from the list it goes back to the card under it")
	assert_eq(map.ui_cancel.cancel(), "card")
	assert_false(cards.visible, "the next closes the card")
	game.free()


# --- every number explains itself ----------------------------------------------------------------------

func test_every_number_on_every_card_has_a_breakdown_and_every_codex_link_resolves() -> void:
	var game := _game(_all_on())
	var map := game.map
	var s := map.state
	var checked := 0
	var cards := []
	for p in s.provinces:
		cards.append(["province", p.id])
	for a in s.armies:
		cards.append(["army", a.id])
	cards.append(["orders", ""])
	for entry in cards:
		match String(entry[0]):
			"province":
				map.select_province(String(entry[1]))
			"army":
				map.select_army(String(entry[1]))
			"orders":
				map.show_orders()
		var where := "%s %s" % entry
		for c in map.details.find_children("*", "", true, false):
			if not (c is Label or c is Button) or not _shown(c, map.details):
				continue
			if c is Label and not _has_digit_not_ordinal(c.text):
				continue
			if c is Button:
				continue  # a button's own tooltip explains what it does (the recruit buttons carry their price breakdown: tested with them)
			checked += 1
			assert_false(c.tooltip_text.is_empty(), "%s: '%s' has a tooltip" % [where, c.text])
			assert_ne(c.mouse_filter, Control.MOUSE_FILTER_IGNORE, "%s: '%s' takes the mouse so its tooltip shows" % [where, c.text])
		for c in map.details.find_children("*", "", true, false):
			if c is Control and c.has_meta(CodexLink.META):
				var key := String(c.get_meta(CodexLink.META))
				assert_true(RulesCodex.ENTRIES.has(key), "%s: '%s' links %s, which exists" % [where, c.name, key])
				assert_true((c as Control).tooltip_text.replace("\n", " ").ends_with("Codex: %s (right-click or F1 to open)" % RulesCodex.entry(key).title),
					"%s: '%s' ends its tooltip with its codex entry" % [where, c.name])
	assert_true(checked > 40, "numbers were checked (%d)" % checked)
	_notes.append("numbers on cards with a tooltip: %d" % checked)
	game.free()


func _has_digit_not_ordinal(text: String) -> bool:
	var ordinal := RegEx.create_from_string("\\b\\d+(st|nd|rd|th)\\b")
	var digit := RegEx.create_from_string("\\d")
	return digit.search(ordinal.sub(text, "", true)) != null


func _all_on() -> Dictionary:
	var config := VS_COMPUTER.duplicate()
	config.merge(ALL)
	return config
