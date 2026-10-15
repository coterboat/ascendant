extends "res://tests/test_case.gd"
## UI-FIT (#237; design/UX_WAR_TABLE.md §7, the style bible's §2.1): no text the player reads draws below the 12 px floor in the
## smallest supported window, 1280x720 at 100%, where the screens are laid out at 1600x900 and drawn at 0.8. So no Label, Button
## or RichTextLabel on these screens uses a font below UiPalette.TYPE_FLOOR logical px (15 x 0.8 = 12): the Table with its cards,
## tray, guide and plaques, the Chronicle (Read and Plan), the research panel's two tabs, the cast dialog, the turn report, the
## build screen, the codex, and the battle viewer on both views (plates, centre, caption, controls, the Why panel, the legend, the
## result card). Text drawn on the board itself (plates, tiles, marks) scales with the camera and is the board's to fit.

const Mx := preload("res://tests/magic_battle_fixtures.gd")
const BFx := preload("res://tests/battle_playback_fixtures.gd")
const GAME_SCENE := "res://ui/game_screen.tscn"
const CROWN := "kingdom"
const CLANS := "beasts"


## The visible text nodes under `root` drawn below the floor: ["<path>: <size> px \"<text>\""].
static func below_floor(root: Node) -> Array:
	var out := []
	for n in root.find_children("*", "Control", true, false):
		var c := n as Control
		if not _visible(c, root):
			continue
		var fs := -1
		var text := ""
		if c is Label:
			text = (c as Label).text
			fs = c.get_theme_font_size("font_size")
		elif c is Button:
			text = (c as Button).text
			fs = c.get_theme_font_size("font_size")
		elif c is RichTextLabel:
			text = (c as RichTextLabel).get_parsed_text() if (c as RichTextLabel).is_inside_tree() else (c as RichTextLabel).text
			fs = c.get_theme_font_size("normal_font_size")
		if fs < 0 or text.strip_edges().is_empty():
			continue
		if fs < UiPalette.TYPE_FLOOR and not _on_the_board(c):
			out.append("%s: %d px \"%s\"" % [String(root.get_path_to(c)), fs, text.substr(0, 40).replace("\n", " ")])
	return out


## Text on the board itself (the 2D map's province tiles): it zooms with the map, so it is the board's to fit, not a fixed size.
static func _on_the_board(c: Control) -> bool:
	var n: Node = c
	while n != null:
		if String(n.name) == "MapCanvas":
			return true
		n = n.get_parent()
	return false


## Visible as far as `root` (the test's nodes are not always in the tree, where is_visible_in_tree is false).
static func _visible(c: Control, root: Node) -> bool:
	var n: Node = c
	while n != null:
		if n is CanvasItem and not (n as CanvasItem).visible:
			return false
		if n == root:
			return true
		n = n.get_parent()
	return true


func _assert_floor(root: Node, what: String) -> void:
	var low := below_floor(root)
	assert_eq(low, [], "%s: every text at %d px or more (%d below)" % [what, UiPalette.TYPE_FLOOR, low.size()])


func test_the_floor_is_the_bibles_12_px_at_the_smallest_window() -> void:
	assert_true(UiPalette.TYPE_FLOOR * 0.8 >= 12.0, "15 logical px draw at 12 on screen at 1280x720")
	for t in [UiPalette.TYPE_TITLE, UiPalette.TYPE_NAME, UiPalette.TYPE_BODY, UiPalette.TYPE_SMALL, UiPalette.TYPE_NUMBER]:
		assert_true(t >= UiPalette.TYPE_FLOOR, "every type token is at the floor or above (%d)" % t)


func test_the_table_its_cards_the_chronicle_and_the_guide() -> void:
	GameSettings.default_path = "user://type_floor_%d.cfg" % OS.get_process_id()
	var game := load(GAME_SCENE).instantiate() as GameScreen
	game.autosave_enabled = false
	game._bind()
	game.start_game({"players": [CROWN, CLANS], "seed": 4242, "ai": {CLANS: "normal"}, "independents": true, "paths": true, "rulers": true,
		"sieges": true, "fog": true, "magic": true,
		"builds": {CROWN: RulerRules.preset_build(RulerRules.balanced_preset(CROWN)), CLANS: BuildScreen.computer_build(CLANS, 4242, 1)}})
	var map := game.map
	map.select_army("kingdom-1")
	_assert_floor(game, "the Table with an army's card")
	map.select_province("westwatch")
	map.select_province("crownkeep")
	_assert_floor(game, "the Table with a province's card and a march")
	game.plan_hud.open_plan()
	_assert_floor(game, "the Chronicle's Plan")
	game.chronicle_hud.column.show_tab("read")
	_assert_floor(game, "the Chronicle's Read")
	game.research_hud.open_panel()
	_assert_floor(game.research_hud.panel, "the research panel")
	game.research_hud.panel.show_magic()
	_assert_floor(game.research_hud.panel, "the Magic tab")
	game.research_hud.close_all()
	game.free()
	DirAccess.remove_absolute(GameSettings.default_path)


func test_the_battle_viewer_on_both_views() -> void:
	var fx := BFx.battle("king_falls_wins")
	for v in [BattleSimpleView.new(), BattleStage3D.new()]:
		v.controls.remember = false
		assert_eq(v.show_battle(fx.log, fx.report), "")
		v.controls.set_why(true, false)
		_assert_floor(v, "%s: plates, caption, controls and Why" % v.name)
		v.controls.set_legend(true, false)
		_assert_floor(v, "%s: the legend" % v.name)
		v.controls.set_legend(false, false)
		v.player.skip_to_end()
		_assert_floor(v, "%s: the result card" % v.name)
		v.free()


func test_the_build_screen_the_report_the_codex_and_the_cast_dialog() -> void:
	var b := load(BuildScreen.SCENE).instantiate() as BuildScreen
	b.begin({"players": [CROWN, CLANS], "seed": 9, "magic": true, "ai": {CLANS: "normal"}})
	if b.step == BuildScreen.Step.HANDOFF:
		b.acknowledge()
	_assert_floor(b, "the build screen")
	b.free()
	var codex: CodexPanel = load("res://ui/codex_panel.tscn").instantiate()
	codex.show_entry("how_to_play")
	_assert_floor(codex, "the codex")
	codex.free()
	var s := GameState.with_magic(9, {CROWN: "regents_court", CLANS: {"ruler": "fang_chieftain", "mandates": ["tithe_of_blood"]}})
	s = AscensionRules.with_nodes(s, CROWN, ["sunlance", "shield_of_law", "sanctum_ward", "dawn_blessing"])
	for f in s.factions:
		f.gold = 200
	Mx.army(s, CROWN, s.new_army_id(CROWN), "highcrag", ["spearmen", "spearmen", "adepts", "adepts"])
	s.find_province("highcrag").owner = CROWN
	var session := GameSession.new(s, [CROWN, CLANS], 9, AutoBattleResolver.new())
	var game := load(GAME_SCENE).instantiate() as GameScreen
	game.autosave_enabled = false
	assert_eq(game.load_game(SaveGame.make(session, {}, SaveGame.MANUAL, "Type floor", 0)), "")
	if game.handoff.visible:
		game.handoff.ready_button.pressed.emit()
	var army := ""
	for a in game.session.state().armies:
		if a.owner == CROWN and a.location == "highcrag" and a.ruler == null:
			army = a.id
	game.map.open_cast_dialog(army)
	_assert_floor(game.map.cast_dialog, "the cast dialog")
	game.map.cast_dialog.visible = false
	game.end_turn()
	if game.handoff.visible:
		game.handoff.ready_button.pressed.emit()
	game.end_turn()
	if game.handoff.visible:
		game.handoff.ready_button.pressed.emit()
	game.open_turn_report()
	if game.report_overlay != null:
		_assert_floor(game.report_overlay, "the turn report")
	game.free()
