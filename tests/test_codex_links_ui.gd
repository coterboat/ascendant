extends "res://tests/test_case.gd"
## Codex links from tooltips (#8: "Terms in tooltips and reports link to their entry"). Every number on
## the map (top bar, side panel, region badges, recruit buttons, order lines) and on the victory screen
## ends its tooltip with "Codex: <entry> (right-click or F1 to open)", and a right-click opens the codex
## at that entry. Every codex key linked this way exists in RulesCodex.

const GAME_SCENE := "res://ui/game_screen.tscn"
const LINK_LINE := "Codex: %s (right-click or F1 to open)"


func _game() -> GameScreen:
	var game := load(GAME_SCENE).instantiate() as GameScreen
	game.start_game({"players": ["kingdom", "beasts"], "seed": 99})
	return game


## Every control under `root` with a codex link.
func _linked(root: Node) -> Array:
	var out := []
	if root is Control and root.has_meta(CodexLink.META):
		out.append(root)
	for c in root.get_children():
		out.append_array(_linked(c))
	return out


func _shown(c: Control, root: Node) -> bool:
	var n: Node = c
	while n != null and n != root:
		if n is CanvasItem and not n.visible:
			return false
		n = n.get_parent()
	return true


func _has_digit(text: String) -> bool:
	for ch in text:
		if ch >= "0" and ch <= "9":
			return true
	return false


## Every linked control names an existing entry at the end of its tooltip.
func _assert_links_valid(root: Node, where: String) -> int:
	var n := 0
	for c in _linked(root):
		var key := String(c.get_meta(CodexLink.META))
		assert_true(RulesCodex.ENTRIES.has(key), "%s: '%s' links codex key %s, which exists" % [where, c.name, key])
		var title := String(RulesCodex.entry(key).get("title", ""))
		assert_true(c.tooltip_text.replace("\n", " ").ends_with(LINK_LINE % title),
			"%s: the tooltip of '%s' ends with its codex entry: %s" % [where, c.name, c.tooltip_text])
		n += 1
	return n


## Every shown Label or Button under `root` that shows a number has a codex link.
func _assert_numbers_linked(root: Node, where: String, skip: Array = []) -> int:
	var n := 0
	var stack: Array = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		if not (node is Label or node is Button) or skip.has(node) or not _shown(node, root):
			continue
		if _has_digit(node.text):
			n += 1
			assert_true(node.has_meta(CodexLink.META), "%s: '%s' shows a number and links its codex entry" % [where, node.text])
	return n


func test_every_codex_key_the_ui_maps_to_exists() -> void:
	for kind in TooltipText.CODEX:
		assert_true(RulesCodex.ENTRIES.has(TooltipText.CODEX[kind]), "TooltipText.CODEX[%s] = %s exists" % [kind, TooltipText.CODEX[kind]])
		assert_eq(TooltipText.codex_for(kind), TooltipText.CODEX[kind])
	assert_eq(TooltipText.codex_for("no such kind"), "", "an unknown kind links nothing")
	assert_eq(TooltipText.codex_for("gold", {"codex": "recruit"}), "recruit", "a breakdown's own codex key wins")
	assert_eq(TooltipText.codex_for("gold", {"codex": "no_such_entry"}), "", "but only when it exists")
	# Every unit type's trait has its own entry (the Units entry, the battle report and the trait links).
	for f in GameState.new().factions:
		var types: Array = f.unit_types.duplicate()
		types.append(f.commander_type)
		for ut in types:
			var key := AutoBattleResolver.codex_id_for_trait(ut.trait_id)
			assert_true(RulesCodex.ENTRIES.has(key), "%s's trait has codex entry %s" % [ut.name, key])


func test_map_numbers_link_to_the_codex_and_every_key_exists() -> void:
	var game := _game()
	var map := game.map
	# Seat 1's capital: the top bar, the province, its army, the recruit buttons.
	_order_some(game)
	var linked := _assert_links_valid(map, "orders phase")
	assert_true(linked >= 15, "top bar, side panel, badges, recruit buttons and order lines are linked (%d)" % linked)
	for label in [map.gold_label, map.turn_label, map.faction_label]:
		assert_true(label.has_meta(CodexLink.META), "the top bar's %s is linked" % label.name)
	assert_eq(String(map.gold_label.get_meta(CodexLink.META)), "gold")
	assert_eq(String(map.turn_label.get_meta(CodexLink.META)), "phase_order")
	var numbers := _assert_numbers_linked(map.details, "side panel")
	assert_true(numbers >= 5, "income, units, strength, unit counts, gold after recruits, recruit buttons (%d)" % numbers)
	for id in map.regions:
		var region: ProvinceRegion = map.regions[id]
		assert_eq(String(region.income_label.get_meta(CodexLink.META)), "income", "%s's income badge" % id)
		for badge in region.army_box.get_children():
			assert_eq(String(badge.get_meta(CodexLink.META)), "army", "%s's army badge" % id)
			assert_false((badge as Button).text.contains("1 units"), "badge plural: %s" % badge.text)
	# The order lines: a move links to moving, a recruit to recruiting.
	var lines := map.details.find_children("OrderLine", "Label", true, false)
	assert_eq(lines.size(), 2)
	assert_eq(String(lines[0].get_meta(CodexLink.META)), "move")
	assert_eq(String(lines[1].get_meta(CodexLink.META)), "recruit")
	for b in map.details.find_children("Recruit_*", "Button", true, false):
		assert_eq(String(b.get_meta(CodexLink.META)), "recruit")
	# An enemy province with an army: owner, terrain, its army's numbers.
	map.select_province("fangridge")
	_assert_links_valid(map, "enemy capital")
	_assert_numbers_linked(map.details, "enemy capital")
	map.select_province("thornvale")
	_assert_links_valid(map, "empty province")
	game.free()


func test_right_click_opens_the_codex_at_the_entry() -> void:
	var game := _game()
	_order_some(game)
	var samples := [game.map.gold_label, game.map.turn_label,
		game.map.details.find_children("IncomeLabel", "Label", true, false)[0],
		game.map.details.find_children("StrengthLabel", "Label", true, false)[0],
		game.map.details.find_children("OrderLine", "Label", true, false)[0],
		game.map.details.find_children("Recruit_*", "Button", true, false)[0],
		game.map.regions["fangridge"].army_box.get_child(0),
		game.map.regions["crownkeep"].income_label]
	for c in samples:
		var key := String(c.get_meta(CodexLink.META))
		assert_false(game.codex.visible)
		c.gui_input.emit(CodexLink.right_click())
		assert_true(game.codex.visible, "right-clicking '%s' opens the codex" % c.name)
		assert_eq(game.codex.current_key(), key, "at %s" % key)
		game.codex.close()
	# A left click is not a codex request.
	var left := InputEventMouseButton.new()
	left.button_index = MOUSE_BUTTON_LEFT
	left.pressed = true
	game.map.gold_label.gui_input.emit(left)
	assert_false(game.codex.visible, "a left click does not open the codex")
	# F1 finds the link of the hovered control or its nearest linked parent.
	var f1 := InputEventKey.new()
	f1.keycode = KEY_F1
	f1.pressed = true
	assert_true(CodexLink.is_open_key(f1))
	var child := Control.new()
	game.map.gold_label.add_child(child)
	assert_eq(CodexLink.key_at(child), "gold", "F1 over a child of a linked label")
	assert_eq(CodexLink.key_at(game.map.hint_label), "", "nothing linked: F1 does nothing")
	game.free()


func test_victory_screen_numbers_link_to_the_codex() -> void:
	var start := GameState.new(99)
	start.armies.clear()
	var a := Army.new()
	a.id = "kingdom-1"
	a.owner = "kingdom"
	a.location = "ebonpeak"
	a.units.append(Unit.new(TurnResolver.recruitable_type(start.find_faction("kingdom"), "knights"), "kingdom"))
	start.armies.append(a)
	start.find_province("ebonpeak").owner = "kingdom"
	var session := GameSession.new(start, ["kingdom", "beasts"], 7, AutoBattleResolver.new())
	assert_eq(session.queue_move("kingdom-1", "fangridge"), "")
	assert_eq(session.end_turn(), "")
	assert_eq(session.acknowledge_handoff(), "")
	assert_eq(session.end_turn(), "")
	assert_true(session.is_over())
	var screen := VictoryScreen.new()
	assert_true(screen.show_for(session))
	var linked := _assert_links_valid(screen, "victory screen")
	assert_true(linked >= 7, "caption, headline, seat, summary, turns, battles, provinces held, capture (%d)" % linked)
	var numbers := _assert_numbers_linked(screen, "victory screen")
	assert_true(numbers >= 5, "every number on the victory screen is linked (%d)" % numbers)
	var asked := []
	screen.codex_requested.connect(func(key: String): asked.append(key))
	screen.turns_label.gui_input.emit(CodexLink.right_click())
	screen.province_labels()[0].gui_input.emit(CodexLink.right_click())
	assert_eq(asked, ["phase_order", "province"], "right-clicks ask for the entries behind the numbers")
	screen.free()


func test_battle_report_headings_link_to_the_codex() -> void:
	var game := _game()
	var viewer := game.battle_viewer
	var s := game.session.state()
	var sides := [{"faction": "beasts", "armies": [s.find_army("beasts-2")]}, {"faction": "kingdom", "armies": [s.find_army("kingdom-1")]}]
	var province := s.find_province("thornvale")
	var ctx := {"kind": "province", "defender": "", "province": province, "province_ids": ["thornvale"], "state": s}
	var fought := AutoBattleResolver.fight(sides, ctx, SeededRNG.new(5))
	assert_true(viewer.show_report(fought.result.report, s, game.session.players()))
	var linked := _assert_links_valid(viewer, "battle report")
	assert_true(linked >= 7, "the result, the why and the section headings are linked (%d)" % linked)
	var heading := viewer.section("routs").find_child("Heading", false, false) as Label
	heading.gui_input.emit(CodexLink.right_click())
	assert_true(game.codex.visible, "a battle report heading opens the codex")
	assert_eq(game.codex.current_key(), "battle_morale")
	game.free()


## Seat 1 (Aurel Crown) moves its army and recruits Spearmen; its capital ends up selected.
func _order_some(game: GameScreen) -> void:
	var map := game.map
	map.select_army("kingdom-1")
	map.select_province("westwatch")
	map.selected_army_id = ""
	map.select_province("crownkeep")
	var recruit := map.details.find_children("Recruit_spearmen", "Button", true, false)
	assert_eq(recruit.size(), 1)
	recruit[0].pressed.emit()
	assert_eq(game.session.current_orders().size(), 2)
