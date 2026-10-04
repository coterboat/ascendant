extends "res://tests/test_case.gd"
## Scene smoke tests for issue #5's map screen: it builds from a GameState headless without errors,
## selection fills the side panel, every number on screen has a breakdown tooltip, the top bar
## shows gold and turn, and nothing it does changes the state.

const MAP_SCENE := "res://ui/map_screen.tscn"


## Instantiates the map screen, hands it `state` before it enters the tree, and adds it to the root.
func _open(state: GameState = null, faction_id: String = "kingdom") -> MapScreen:
	var screen: MapScreen = load(MAP_SCENE).instantiate()
	if state:
		screen.set_state(state, faction_id)
	(Engine.get_main_loop() as SceneTree).root.add_child(screen)
	return screen


func _close(screen: MapScreen) -> void:
	screen.get_parent().remove_child(screen)
	screen.free()


func _controls(node: Node, out: Array = []) -> Array:
	for child in node.get_children():
		if child is Control:
			out.append(child)
		_controls(child, out)
	return out


func _find(screen: MapScreen, node_name: String) -> Label:
	for c in _controls(screen.details):
		if c.name == node_name and c is Label:
			return c
	return null


## Visible up to the screen (is_visible_in_tree() needs the tree, which headless tests don't enter).
func _shown(c: Control, screen: Control) -> bool:
	var n: Node = c
	while n != null and n != screen:
		if n is CanvasItem and not n.visible:
			return false
		n = n.get_parent()
	return true


func _has_digit(text: String) -> bool:
	for ch in text:
		if ch >= "0" and ch <= "9":
			return true
	return false


## Every Label or Button showing a number must explain it: a tooltip with a breakdown total line.
func _assert_numbers_explained(screen: MapScreen, where: String) -> int:
	var checked := 0
	for c in _controls(screen):
		if not (c is Label or c is Button) or not _shown(c, screen):
			continue
		if not _has_digit(c.text):
			continue
		checked += 1
		assert_false(c.tooltip_text.is_empty(), "%s: '%s' has a tooltip" % [where, c.text])
		assert_true(c.tooltip_text.contains("= "), "%s: tooltip of '%s' shows a breakdown total" % [where, c.text])
		assert_true(c.tooltip_text.split("\n").size() >= 4, "%s: tooltip of '%s' has lines and a description" % [where, c.text])
		assert_ne(c.mouse_filter, Control.MOUSE_FILTER_IGNORE, "%s: '%s' takes the mouse so its tooltip shows" % [where, c.text])
	return checked


func test_scene_builds_one_region_per_province_from_the_default_state() -> void:
	var screen := _open()  # no state handed over: like the title screen's Map preview button
	# The runner works inside SceneTree._initialize, before the root enters the tree, so _ready does
	# not fire on add_child here. Call it the way the engine does when the title screen opens the map.
	screen._ready()
	assert_true(screen.state != null, "opens with a fresh default game")
	assert_eq(screen.viewing_faction_id, screen.state.factions[0].id, "viewed by player 1")
	assert_eq(screen.regions.size(), screen.state.provinces.size(), "one region per province")
	assert_eq(screen.map_canvas.get_child_count(), screen.state.provinces.size(), "regions live on the map canvas")
	for p in screen.state.provinces:
		var region: ProvinceRegion = screen.regions[p.id]
		assert_eq(region.income_label.text, "%d gold" % p.income, "%s shows its income" % p.name)
		assert_eq(region.name_label.text, p.name, "%s shows its name, not its id" % p.name)
	var badges := 0
	for id in screen.regions:
		badges += screen.regions[id].army_box.get_child_count()
	assert_eq(badges, screen.state.armies.size(), "one army badge per army")
	_close(screen)


func test_select_province_fills_the_side_panel() -> void:
	var screen := _open(GameState.new())
	var got := []
	screen.province_selected.connect(func(id): got.append(id))
	screen.select_province("crownkeep")
	assert_eq(got, ["crownkeep"], "province_selected fires with the id")
	assert_true(screen.regions["crownkeep"].selected, "the region shows it is selected")
	assert_eq(_find(screen, "TerrainLabel").text, "Terrain: Plains")
	assert_eq(_find(screen, "IncomeLabel").text, "Income: 12 gold per turn")
	assert_eq(_find(screen, "OwnerLabel").text, "Owner: Aurel Crown")
	assert_eq(_find(screen, "CapitalLabel").text, "Capital: Yes, the capital of Aurel Crown")
	assert_eq(_find(screen, "FortLabel").text, "Fort: Yes")
	assert_eq(_find(screen, "UnitsLabel").text, "Units: 3", "the starting army has three units")
	assert_eq(_find(screen, "CommanderLabel").text, "Commander: Knight Captain")
	var strength := StubBattleResolver.army_strength(screen.state.armies[0])
	var strength_label := _find(screen, "StrengthLabel")
	assert_eq(strength_label.text, "Rough strength: %d" % strength, "labelled as a rough guide")
	assert_true(strength_label.tooltip_text.contains("move forecast"), "the tooltip points to the forecast odds")
	assert_eq(String(strength_label.get_meta(CodexLink.META)), "army_strength", "and links the codex entry that says it is a guide")

	screen.select_province("thornvale")
	assert_false(screen.regions["crownkeep"].selected, "the old selection is cleared")
	assert_eq(_find(screen, "TerrainLabel").text, "Terrain: Forest")
	assert_eq(_find(screen, "IncomeLabel").text, "Income: 6 gold per turn")
	assert_eq(_find(screen, "OwnerLabel").text, "Owner: Nobody (neutral)")
	assert_eq(_find(screen, "UnitsLabel"), null, "no armies in Thornvale")
	_close(screen)


func test_select_army_selects_its_province_and_signals() -> void:
	var screen := _open(GameState.new())
	var armies := []
	screen.army_selected.connect(func(id): armies.append(id))
	var army := screen.state.find_army("beasts-1")
	assert_true(army != null, "fixture: the beasts start with army beasts-1")
	screen.select_army(army.id)
	assert_eq(armies, [army.id], "army_selected fires")
	assert_eq(screen.selected_province_id, "fangridge", "selecting an army selects where it is")
	assert_eq(screen.selected_army_id, army.id)
	screen.focus_province("wildmoor")
	assert_eq(screen.selected_province_id, "wildmoor", "focus_province selects the province")
	assert_eq(screen.selected_army_id, "", "moving the selection away drops the army selection")
	_close(screen)


func test_every_number_on_screen_has_a_breakdown_tooltip() -> void:
	var s := GameState.new()
	s.find_province("thornvale").owner = "kingdom"  # an owned non-capital too
	var screen := _open(s)
	var checked := _assert_numbers_explained(screen, "nothing selected")
	assert_true(checked >= s.provinces.size() + 2, "region incomes, gold and turn were checked (%d)" % checked)
	for p in s.provinces:
		screen.select_province(p.id)
		_assert_numbers_explained(screen, p.name)
	screen.select_army(s.armies[0].id)
	_assert_numbers_explained(screen, "army selected")
	_close(screen)


func test_top_bar_shows_gold_with_breakdown_and_turn() -> void:
	var s := GameState.new()
	var screen := _open(s)
	assert_eq(screen.gold_label.text, "Gold 45   (+12 per turn)")
	assert_true(screen.gold_label.tooltip_text.contains("Gold now: 45"), "gold tooltip shows gold now")
	assert_true(screen.gold_label.tooltip_text.contains("Income from Crownkeep: +12"), "gold tooltip lists province income")
	assert_true(screen.gold_label.tooltip_text.contains("Gold next turn (before recruits): 57"), "gold tooltip shows next turn")
	assert_eq(screen.turn_label.text, "Turn 1", "turns are 1-based, like the tooltip")
	assert_eq(screen.faction_label.text, "Aurel Crown")

	var later := GameState.new()
	later.current_turn = 3
	later.find_faction("beasts").gold = 77
	later.find_province("deepwood").owner = "beasts"
	screen.set_state(later, "beasts")
	assert_eq(screen.faction_label.text, "Thornmane Clans", "top bar follows the viewing faction")
	assert_eq(screen.gold_label.text, "Gold 77   (+19 per turn)", "Fangridge 12 + Deepwood 7")
	assert_eq(screen.turn_label.text, "Turn 4", "3 turns resolved: turn 4 is being ordered")
	assert_true(screen.turn_label.tooltip_text.begins_with("Turn 4"), "the label matches its breakdown")
	_close(screen)


func test_the_screen_never_changes_the_state() -> void:
	var s := GameState.new()
	var before := s.to_dict()
	var screen := _open(s)
	for p in s.provinces:
		screen.select_province(p.id)
	for a in s.armies:
		screen.select_army(a.id)
	screen.focus_province("bloodfen")
	screen.set_state(s, "beasts")
	screen.select_province("does-not-exist")
	screen.select_army("does-not-exist")
	assert_eq(s.to_dict(), before, "the map screen only reads the state")
	_close(screen)


func test_title_screen_has_a_map_preview_button() -> void:
	var title: Control = load("res://ui/title_screen.tscn").instantiate()
	var button := title.get_node_or_null("Center/Box/MapPreviewButton") as Button
	assert_true(button != null, "title screen has the Map preview button")
	if button:
		assert_eq(button.text, "Map preview (dev)", "kept, but marked as a developer preview")
		assert_true(button.flat, "and drawn as a quiet secondary link")
		assert_false(button.tooltip_text.is_empty(), "the button explains itself")
	title.free()
