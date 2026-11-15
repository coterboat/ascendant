extends "res://tests/test_case.gd"
## #289 (QA): every card showed the last order's result (MapScreen.status_text, through CardBase.add_status) whatever the card was
## about, so an order's card could say "Order cancelled." about another order: the research order's card, after the spellbook
## order was cancelled with the cross on its tray token. And an army's card read another army's "Move ordered." as its own.
## A card now shows the last result only when it is about that card's army, province or order, and the cards it is about
## still show it.

const CROWN := "kingdom"
const CLANS := "beasts"
const GAME_SCENE := "res://ui/game_screen.tscn"


func _game(config: Dictionary = {}) -> GameScreen:
	var game := load(GAME_SCENE).instantiate() as GameScreen
	game.autosave_enabled = false
	var c := {"players": [CROWN, CLANS], "seed": 4242, "ai": {CLANS: "normal"}}
	c.merge(config, true)
	game.start_game(c)
	if game.handoff.visible:
		game.handoff.ready_button.pressed.emit()
	return game


## The open card's status line ("" when it has none).
func _status(map: MapScreen) -> String:
	var l := map.cards.find_child("StatusLabel", true, false) as Label
	return l.text if l != null else ""


func _has_label(root: Node, text: String) -> bool:
	return root.find_children("*", "Label", true, false).any(func(l): return (l as Label).text == text)


func test_an_orders_card_never_reads_another_orders_cancel() -> void:
	var game := _game({"magic": true})
	var map := game.map
	var hud := game.research_hud
	hud.open_panel()
	hud.panel.show_magic()
	(hud.panel.buttons["sunlance"] as Button).pressed.emit()  # a research order
	(hud.panel.spellbook_checks["sunburst"] as CheckBox).toggled.emit(false)  # and a spellbook order
	hud.close_all()
	var list := map.orders.orders()
	var research = list.filter(func(o): return o is ResearchOrder)[0]
	var book = list.filter(func(o): return o is SpellbookOrder)[0]
	var tray := map.table().tray_slot()
	tray.token_for(list.find(book)).cross.pressed.emit()  # the spellbook order's cross
	assert_false(map.orders.orders().has(book), "the spellbook order is cancelled")
	assert_true(map.status_text.begins_with("Order cancelled"), map.status_text)
	var i := map.orders.orders().find(research)
	assert_true(i >= 0, "the research order stands")
	tray.token_for(i).pressed.emit(i)
	assert_eq(map.cards.mode, "order")
	assert_true(_has_label(map.details, "Research · a realm order"), "the research order's card")
	assert_eq(_status(map), "", "it doesn't read the spellbook order's cancel as its own")
	game.free()


## Selecting an army or a province clears the last result, so a stale one came from a card that stays open while another order
## changes: here an army's card, while a tray token's cross cancels an order it isn't about.
func test_an_open_armys_card_shows_its_own_result_and_not_another_orders() -> void:
	var game := _game({"rulers": true, "paths": true})
	var map := game.map
	var mine := map.state.armies.filter(func(a): return a.owner == CROWN)
	assert_true(mine.size() >= 2, "the Crown has two armies (its ruler's is the second)")
	var first: Army = mine[0]
	var other: Army = mine[1]
	var to := String(map.state.find_province(first.location).neighbors[0])  # a one-step march (no forts in this game)
	map.select_army(first.id)
	map.select_province(to)
	var march = map.orders.orders().back()
	assert_true(march is MoveOrder and map.status_text.begins_with("Move ordered"), "%s marches to %s: %s" % [first.id, to, map.status_text])
	assert_eq(_status(map), map.status_text, "the marching army's card says it was ordered")
	assert_eq(game.session.queue_order(ResearchOrder.new(_first_crown_research(game.session.state()))), "")  # a realm order
	map._orders_changed()
	var tray := map.table().tray_slot()
	var research = map.orders.orders().filter(func(o): return o is ResearchOrder)[0]
	tray.token_for(map.orders.orders().find(research)).cross.pressed.emit()
	assert_true(map.status_text.begins_with("Order cancelled"), map.status_text)
	assert_eq(map.cards.mode, "army")
	assert_eq(_status(map), "", "the army's card, still open, doesn't read the research order's cancel as its own")
	map.select_army(other.id)
	tray.token_for(map.orders.orders().find(march)).cross.pressed.emit()
	assert_false(map.orders.orders().has(march), "the march is cancelled")
	assert_eq(_status(map), "", "another army's card doesn't read the first army's cancel as its own")
	# The army whose order it was: its card says so.
	map.select_army(first.id)
	map.select_province(to)
	(map.cards.find_child("CancelButton", true, false) as Button).pressed.emit()  # Cancel order, on the army's card
	assert_true(_status(map).begins_with("Order cancelled"), "the army's card says its march was cancelled: \"%s\"" % _status(map))
	game.free()


func _first_crown_research(s: GameState) -> String:
	for n in PathData.PATHS[CROWN].nodes:
		if AscensionRules.check_research(s, CROWN, String(n.id)).is_empty():
			return String(n.id)
	return ""


func test_a_result_still_shows_on_the_card_it_is_about() -> void:
	var game := _game()
	var map := game.map
	var capital := map.state.find_faction(CROWN).capital
	map.select_province(capital)
	(map.details.find_children("Recruit_*", "Button", true, false)[0] as Button).pressed.emit()
	assert_true(map.status_text.begins_with("Recruit ordered"), map.status_text)
	assert_eq(_status(map), map.status_text, "the capital's card says the recruit was ordered")
	# A march the rules refuse: the province clicked is selected, and its card says why.
	var army: Army = map.state.armies.filter(func(a): return a.owner == CROWN)[0]
	var far := ""
	var d := MagicRules.distances(map.state, army.location)
	for pid in d:
		if int(d[pid]) >= 3 and far.is_empty():
			far = String(pid)
	assert_false(far.is_empty(), "a province three steps away")
	map.select_army(army.id)
	map.select_province(far)
	assert_false(map.status_text.is_empty(), "the march to %s is refused" % far)
	assert_eq(map.cards.mode, "province")
	assert_eq(map.selected_province_id, far)
	assert_eq(_status(map), map.status_text, "the province clicked says why")
	game.free()
