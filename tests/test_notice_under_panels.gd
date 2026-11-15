extends "res://tests/test_case.gd"
## #290 (QA): after Menu > Save game, the "Game saved" notice stayed on top of the panels opened after it: it lived on its own
## CanvasLayer (15), above the game screen's overlays (10), so it covered Settings' title and first rows at 1280x720, the Codex's
## search at 125%, and the Rulers panel's own-ruler heading and portrait. The notice now hangs where the first-game guide does
## (#282, MapScreen.add_over_table): over the board and the Table, under the map's own panels and every overlay, so a panel opened
## after it covers it, and it still never blocks the map. The notice is shown here as Save shows it (show_notice), so nothing is
## written to the player's saves.

const GAME_SCENE := "res://ui/game_screen.tscn"


func _game() -> GameScreen:
	var game := load(GAME_SCENE).instantiate() as GameScreen
	game.autosave_enabled = false
	game.start_game({"players": ["kingdom", "beasts"], "seed": 21, "ai": {"beasts": "normal"}, "rulers": true})
	if game.handoff.visible:
		game.handoff.ready_button.pressed.emit()
	return game


## The canvas layer `item` draws in: its nearest CanvasLayer's, or 0 (the window's own canvas, under every CanvasLayer above 0).
func _layer(item: Node) -> int:
	var n := item.get_parent()
	while n != null:
		if n is CanvasLayer:
			return (n as CanvasLayer).layer
		n = n.get_parent()
	return 0


## Whether `top` draws over `under`: a higher canvas layer, or the same layer and later among the same parent's children.
func _draws_over(top: Node, under: Node) -> bool:
	if _layer(top) != _layer(under):
		return _layer(top) > _layer(under)
	return top.get_parent() == under.get_parent() and top.get_index() > under.get_index()


func test_a_panel_opened_after_the_saved_notice_covers_it() -> void:
	var game := _game()
	game.show_notice("Game saved", "Saved as \"Before the push\". %s" % SaveGame.ORDERS_NOTE)
	assert_true(game.notice_panel.visible, "the notice is up")
	game.open_settings()
	assert_true(_draws_over(game.settings_panel, game.notice_panel), "Settings covers it (layer %d over %d)" % [
		_layer(game.settings_panel), _layer(game.notice_panel)])
	game.settings_panel.visible = false
	game.open_codex()
	assert_true(_draws_over(game.codex, game.notice_panel), "the Codex covers it")
	game.codex.visible = false
	game.open_ruler_panel()
	assert_true(game.map.ruler_panel != null and game.map.ruler_panel.visible, "the Rulers panel is open")
	assert_true(_draws_over(game.map.ruler_panel, game.notice_panel), "the Rulers panel, one of the map's own, covers it")
	assert_true(game.notice_panel.visible, "and the notice is still there under them, until OK")
	game.free()


func test_the_notice_still_draws_over_the_board_and_the_table_under_the_realm_plaque() -> void:
	var game := _game()
	game.show_notice("Game saved", "Saved.")
	assert_true(_draws_over(game.notice_panel, game.map.hud), "over the Table (and the board under it)")
	assert_true(game.notice_panel.get_parent() == game.map, "in the map, where the guide is (not on a layer of its own)")
	assert_true(_layer(game.notice_panel) < game.overlays.layer, "under every overlay")
	game.notice_ok.pressed.emit()
	assert_false(game.notice_panel.visible, "OK still hides it")
	game.free()
