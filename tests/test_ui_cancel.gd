extends "res://tests/test_case.gd"
## UX-1 (#194; design/UX_WAR_TABLE.md §1.4): one cancel, in order. Esc, and a right-click on empty board, go through one dispatcher
## (UiCancel, owned by the map screen) that closes the topmost thing only: a modal, march targeting, the Chronicle, the selection
## card, the active lens, the board's close-up, and with nothing left the menu. The codex, the close-up and the game screen's Esc
## all route through it. This file pins the dispatcher as plain logic, then every stacked pair that exists today through the real
## screens (and the pairs for the layers later tickets fill, with stand-ins), on the 3D board and the 2D map.

const GAME_SCENE := "res://ui/game_screen.tscn"
const MAP_SCENE := "res://ui/map_screen.tscn"
const CROWN := "kingdom"
const CLANS := "beasts"
const BOARD_SIZE := Vector2(1200, 836)


# --- fixtures -------------------------------------------------------------------------------------

func _game(config: Dictionary = {"players": [CROWN, CLANS], "seed": 4242, "ai": {CLANS: "normal"}}) -> GameScreen:
	var game := load(GAME_SCENE).instantiate() as GameScreen
	game.autosave_enabled = false
	game.start_game(config)
	return game


## A game screen showing the 3D board, built at once (headless: no frames run).
func _game_3d(config: Dictionary = {"players": [CROWN, CLANS], "seed": 4242, "ai": {CLANS: "normal"}}) -> GameScreen:
	var game := _game(config)
	game.use_board("3d")
	var b: Board3D = game.map.board
	b.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	b.size = BOARD_SIZE
	b.build_now()
	return game


func _esc() -> InputEventAction:
	var e := InputEventAction.new()
	e.action = "ui_cancel"
	e.pressed = true
	return e


## What is open now, by layer name, for a stack of things on `game`.
func _open(game: GameScreen) -> Array:
	var out := []
	for layer in UiCancel.LAYERS:
		if layer != "menu" and game.map.ui_cancel.is_open(layer):
			out.append(layer)
	return out


# --- the dispatcher, as logic -------------------------------------------------------------------------

func test_the_layers_are_the_specs_seven_in_the_specs_order() -> void:
	assert_eq(UiCancel.LAYERS, ["modal", "march", "chronicle", "card", "lens", "closeup", "menu"])


func test_it_closes_the_topmost_layer_only_one_per_press() -> void:
	var cancel := UiCancel.new()
	var open := {"modal": true, "march": true, "chronicle": true, "card": true, "lens": true, "closeup": true}
	var closed := []
	for layer in open:
		cancel.register(layer, func(): return open[layer], func():
			open[layer] = false
			closed.append(layer))
	var menu := []
	cancel.set_menu_opener(func(): menu.append("menu"))
	var seen := []
	cancel.cancelled.connect(func(layer: String): seen.append(layer))
	assert_eq(cancel.topmost(), "modal")
	for i in 6:
		assert_eq(cancel.cancel(), UiCancel.LAYERS[i], "press %d closes %s" % [i + 1, UiCancel.LAYERS[i]])
		assert_eq(closed.size(), i + 1, "and nothing else")
	assert_eq(closed, ["modal", "march", "chronicle", "card", "lens", "closeup"], "in the spec's order")
	assert_eq(menu, [], "the menu waits until everything else is closed")
	assert_eq(cancel.topmost(), "menu")
	assert_eq(cancel.cancel(), "menu", "nothing left: the menu")
	assert_eq(menu, ["menu"])
	assert_eq(seen, ["modal", "march", "chronicle", "card", "lens", "closeup", "menu"], "each press is announced")


func test_a_right_click_closes_things_but_never_opens_the_menu() -> void:
	var cancel := UiCancel.new()
	var card := [true]
	cancel.register("card", func(): return card[0], func(): card[0] = false)
	var menu := []
	cancel.set_menu_opener(func(): menu.append(1))
	assert_eq(cancel.cancel(true), "card", "it closes the card")
	assert_eq(cancel.cancel(true), "", "and with nothing open it does nothing")
	assert_eq(menu, [], "the menu is Esc's alone")
	assert_eq(cancel.cancel(), "menu", "Esc opens it")


func test_several_modals_close_the_one_drawn_on_top_first() -> void:
	var cancel := UiCancel.new()
	var open := {"ruler": true, "sacrifice": true, "codex": true}
	var order := []
	for entry in [["ruler", 20], ["sacrifice", 30], ["codex", 40]]:
		var id: String = entry[0]
		cancel.register("modal", func(): return open[id], func():
			open[id] = false
			order.append(id), int(entry[1]))
	for i in 3:
		assert_eq(cancel.cancel(), "modal")
	assert_eq(order, ["codex", "sacrifice", "ruler"], "highest priority first")
	assert_eq(cancel.cancel(), "", "and then there is nothing (no menu opener)")


func test_with_nothing_registered_and_no_menu_there_is_nothing_to_cancel() -> void:
	var cancel := UiCancel.new()
	assert_false(cancel.is_open("modal"))
	assert_false(cancel.is_open("menu"), "the menu is not a provider: it is what is left")
	assert_eq(cancel.topmost(), "", "no menu opener, no layer")
	assert_eq(cancel.cancel(), "", "and Esc does nothing")


# --- the stacked pairs that exist today -----------------------------------------------------------------

func test_the_codex_over_the_report_closes_first_then_the_report() -> void:
	var game := _game({"players": [CROWN, CLANS], "seed": 77})
	game.end_turn()
	game.handoff.ready_button.pressed.emit()
	game.end_turn()
	game.handoff.ready_button.pressed.emit()
	assert_true(game.report_overlay.visible)
	game.open_codex("gold")
	assert_true(game.codex.visible)
	assert_true(game.codex.handle_cancel(_esc()), "the codex takes Esc through the dispatcher")
	assert_false(game.codex.visible, "and closes")
	assert_true(game.report_overlay.visible, "the report under it is still there")
	game._unhandled_input(_esc())
	assert_false(game.report_overlay.visible, "the next Esc closes the report")
	assert_false(game.menu_overlay.visible, "and not the menu: one thing a press")
	game.free()


func test_the_codex_routes_through_the_dispatcher_not_around_it() -> void:
	var game := _game()
	assert_true(game.codex.cancel_router.is_valid(), "the game's codex asks the dispatcher")
	var seen := []
	game.map.ui_cancel.cancelled.connect(func(layer: String): seen.append(layer))
	game.open_codex("gold")
	game.codex.handle_cancel(_esc())
	assert_eq(seen, ["modal"], "the dispatcher closed it, as a modal")
	assert_false(game.codex.visible)
	game.free()


func test_the_ruler_panel_and_the_sacrifice_dialog_over_the_card() -> void:
	var game := _game({"players": [CROWN, CLANS], "seed": 77, "rulers": true})
	var map := game.map
	assert_true(map.cards.visible, "the capital's card is up")
	map.open_ruler_panel()
	map.open_sacrifice_dialog("")
	assert_true(map.sacrifice_dialog.visible and map.ruler_panel.visible)
	assert_eq(map.ui_cancel.cancel(), "modal")
	assert_false(map.sacrifice_dialog.visible, "the dialog over the panel closes first")
	assert_true(map.ruler_panel.visible and map.cards.visible)
	assert_eq(map.ui_cancel.cancel(), "modal")
	assert_false(map.ruler_panel.visible, "then the panel")
	assert_true(map.cards.visible, "the card is not touched yet")
	assert_eq(map.ui_cancel.cancel(), "card")
	assert_false(map.cards.visible)
	game.free()


func test_the_game_screens_esc_used_to_open_the_menu_over_a_ruler_panel_and_does_not_now() -> void:
	var game := _game({"players": [CROWN, CLANS], "seed": 77, "rulers": true})
	game.map.open_ruler_panel()
	game._unhandled_input(_esc())
	assert_false(game.menu_overlay.visible, "the menu does not open over an open panel")
	assert_false(game.map.ruler_panel.visible, "Esc closed the panel")
	game.free()


func test_overlays_of_the_game_screen_close_one_per_press() -> void:
	var game := _game({"players": [CROWN, CLANS], "seed": 77, "paths": true, "rulers": true})
	game.open_menu()
	game.open_settings()
	assert_true(game.menu_overlay.visible and game.settings_panel.visible)
	assert_eq(game.map.ui_cancel.cancel(), "modal")
	assert_false(game.settings_panel.visible, "settings over the menu closes first")
	assert_true(game.menu_overlay.visible)
	game.open_save_dialog()
	assert_eq(game.map.ui_cancel.cancel(), "modal")
	assert_false(game.save_overlay.visible, "the save dialog over the menu")
	assert_true(game.menu_overlay.visible)
	game.open_load_screen()
	assert_eq(game.map.ui_cancel.cancel(), "modal")
	assert_false(game.load_screen.visible, "the load screen over the menu")
	game._on_quit_requested()
	assert_true(game.quit_overlay.visible)
	assert_eq(game.map.ui_cancel.cancel(), "modal")
	assert_false(game.quit_overlay.visible, "the quit question over the menu")
	assert_true(game.menu_overlay.visible)
	assert_eq(game.map.ui_cancel.cancel(), "modal")
	assert_false(game.menu_overlay.visible, "and the menu last")
	game.research_hud.open_panel()
	assert_true(game.research_hud.panel.visible)
	assert_eq(game.map.ui_cancel.cancel(), "modal")
	assert_false(game.research_hud.panel.visible, "the research panel closes through it too")
	game.free()


func test_the_victory_screen_takes_esc_and_nothing_closes() -> void:
	var game := _game({"players": [CROWN, CLANS], "seed": 77})
	for step in [["westwatch", "bloodfen"], ["stonegate", "deepwood"], ["blackwood", "greenglade"], ["ebonpeak", "rivermarch"], ["fangridge", ""]]:
		game.session.queue_move("kingdom-1", step[0])
		game.end_turn()
		game.handoff.ready_button.pressed.emit()
		if not String(step[1]).is_empty():
			game.session.queue_move("beasts-1", step[1])
		game.end_turn()
		if game.session.is_over():
			break
		game.handoff.ready_button.pressed.emit()
	assert_true(game.victory_screen.visible)
	game._unhandled_input(_esc())
	assert_true(game.victory_screen.visible, "the victory screen stays, as it did")
	assert_false(game.menu_overlay.visible, "and Esc does not open the menu over it")
	game.free()


func test_under_the_handoff_cover_esc_does_nothing() -> void:
	var game := _game({"players": [CROWN, CLANS], "seed": 77})
	game.end_turn()
	assert_true(game.handoff.visible)
	game._unhandled_input(_esc())
	assert_false(game.menu_overlay.visible, "no menu behind the cover")
	game.free()


func test_esc_with_nothing_open_but_a_card_closes_the_card_then_opens_the_menu() -> void:
	var game := _game()
	var map := game.map
	assert_true(map.cards.visible)
	game._unhandled_input(_esc())
	assert_false(map.cards.visible, "the first Esc closes the card")
	assert_false(game.menu_overlay.visible)
	game._unhandled_input(_esc())
	assert_true(game.menu_overlay.visible, "the second opens the menu")
	game._unhandled_input(_esc())
	assert_false(game.menu_overlay.visible, "the third closes it again")
	game.free()


# --- the card, the lens and the close-up (3D board) --------------------------------------------------------

func test_a_modal_then_the_card_then_the_close_up_then_the_menu_on_the_3d_board() -> void:
	var game := _game_3d()
	var map := game.map
	var b: Board3D = map.board
	var capital := map.state.find_faction(CROWN).capital
	map.select_army("kingdom-1")
	assert_true(b.enter_closeup(capital, true), "the close-up of the capital's yard")
	game.open_codex("gold")
	assert_eq(_open(game), ["modal", "card", "closeup"], "all three are up")
	var steps := []
	for i in 5:
		steps.append(map.ui_cancel.cancel())
	assert_eq(steps, ["modal", "card", "closeup", "menu", "modal"], "one layer a press, in the specs' order, the menu closing last")
	assert_false(game.codex.visible)
	assert_eq(map.selected_army_id, "", "the card step put the army back")
	assert_eq(map.selected_province_id, capital, "but kept the province")
	assert_eq(b.closeup, "", "the close-up left")
	assert_false(game.menu_overlay.visible)
	game.free()


func test_the_card_closes_before_the_close_up_and_the_close_up_survives_it() -> void:
	var game := _game_3d()
	var map := game.map
	var b: Board3D = map.board
	var capital := map.state.find_faction(CROWN).capital
	b.enter_closeup(capital, true)
	assert_eq(map.ui_cancel.cancel(), "card")
	assert_eq(b.closeup, capital, "the close-up is still on after the card closed (the province stays selected)")
	assert_eq(map.ui_cancel.cancel(), "closeup")
	assert_eq(b.closeup, "")
	game.free()


func test_a_lens_closes_after_the_card_and_before_the_close_up() -> void:
	var game := _game_3d()
	var map := game.map
	var b: Board3D = map.board
	var capital := map.state.find_faction(CROWN).capital
	map.lens_host.register("owner", "Owner", KEY_1)
	map.lens_host.activate("owner")
	b.enter_closeup(capital, true)
	assert_eq(_open(game), ["card", "lens", "closeup"])
	var steps := []
	for i in 3:
		steps.append(map.ui_cancel.cancel())
	assert_eq(steps, ["card", "lens", "closeup"], "the card, then the lens, then the close-up")
	assert_eq(map.lens_host.active_id(), "", "the lens is off and the art is back")
	game.free()


func test_march_targeting_and_the_chronicle_sit_where_the_spec_puts_them() -> void:
	# Nothing registers these today (UX-3's targeting, UX-6's Chronicle): a stand-in shows the order they will close in.
	var game := _game()
	var map := game.map
	var open := {"march": true, "chronicle": true}
	var order := []
	for layer in open:
		map.ui_cancel.register(layer, func(): return open[layer], func():
			open[layer] = false
			order.append(layer))
	game.open_codex("gold")
	assert_eq(_open(game), ["modal", "march", "chronicle", "card"])
	var steps := []
	for i in 4:
		steps.append(map.ui_cancel.cancel())
	assert_eq(steps, ["modal", "march", "chronicle", "card"], "modal, march targeting, the Chronicle, then the card")
	game.free()


# --- through the real input paths ---------------------------------------------------------------------------

func test_the_board_no_longer_decides_esc_by_itself() -> void:
	var src := FileAccess.get_file_as_string("res://world3d/board3d.gd")
	var at := src.find("KEY_ESCAPE:")
	assert_true(at >= 0)
	var body := src.substr(at, src.find("KEY_SPACE:", at) - at)
	assert_false(body.contains("exit_closeup"), "Esc on the board is the dispatcher's, not its own")


func test_a_right_click_on_empty_3d_board_closes_the_topmost_thing() -> void:
	var game := _game_3d()
	var map := game.map
	var b: Board3D = map.board
	assert_true(b.province_at(Vector2(2, 2)).is_empty() and b.army_at(Vector2(2, 2)).is_empty(), "the corner of the board is empty sea")
	var click := CodexLink.right_click()
	click.position = Vector2(2, 2)
	assert_true(map.cards.visible)
	b._gui_input(click)
	assert_false(map.cards.visible, "the card closed")
	b._gui_input(click)
	assert_false(game.menu_overlay.visible, "and a second right-click does not open the menu")
	# On a province or an army a right-click is its codex entry, as it was.
	var capital := map.state.find_faction(CROWN).capital
	var at: Vector2 = b.project(b.wv.terrain.centre_of(capital))
	var on_land := CodexLink.right_click()
	on_land.position = at
	map.select_province(capital)
	assert_true(map.cards.visible)
	b._gui_input(on_land)
	assert_true(game.codex.visible, "a right-click on land opens its codex entry")
	assert_true(map.cards.visible, "and closes nothing")
	game.free()


func test_a_right_click_on_the_empty_2d_map_closes_the_topmost_thing() -> void:
	var game := _game()
	var map := game.map
	assert_true(map.board == null, "the 2D map")
	assert_true(map.cards.visible)
	map._on_map_view_input(CodexLink.right_click())
	assert_false(map.cards.visible, "the card closed")
	map._on_map_view_input(CodexLink.right_click())
	assert_false(game.menu_overlay.visible, "a right-click never opens the menu")
	game.free()


func test_a_right_click_on_a_2d_region_is_its_codex_entry_not_a_cancel() -> void:
	var game := _game()
	var map := game.map
	var region: ProvinceRegion = map.regions["westwatch"]
	assert_true(map.cards.visible)
	region.gui_input.emit(CodexLink.right_click())
	assert_true(game.codex.visible, "the region's own codex link took the click")
	assert_true(map.cards.visible, "the card stays")
	game.free()


func test_the_map_previews_codex_closes_through_the_dispatcher() -> void:
	var map: MapScreen = load(MAP_SCENE).instantiate()
	map._ready()
	map.select_province("crownkeep")
	map.request_codex("gold")
	assert_true(map.own_codex != null and map.own_codex.visible)
	assert_true(map.own_codex.cancel_router.is_valid())
	assert_true(map.own_codex.handle_cancel(_esc()))
	assert_false(map.own_codex.visible, "the preview's codex closes")
	assert_true(map.cards.visible, "and the card under it stays")
	map._unhandled_input(_esc())
	assert_false(map.cards.visible, "the preview has no game screen: the map handles Esc itself and closes the card")
	map.free()


func test_the_game_screen_and_the_map_do_not_both_handle_one_press() -> void:
	var game := _game()
	assert_true(game.map.intercept_back, "the map leaves Esc to the game screen")
	game.map._unhandled_input(_esc())
	assert_true(game.map.cards.visible, "so the map's own handler did nothing")
	game._unhandled_input(_esc())
	assert_false(game.map.cards.visible, "and the game screen's closed one thing")
	game.free()
