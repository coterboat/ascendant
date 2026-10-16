extends SceneTree
## The live half of tests/test_screens_fit.gd (MVP-1, #141). Not a test file (no "test_" prefix): the test runs it in a
## child Godot process, because the test runner's tests run before the scene tree is live, so no Control ever gets a
## layout pass there. This script runs a real (headless) main loop: each screen goes into a SubViewport of the size
## asked, three frames lay it out as the engine would, and what it finds is printed as one line,
##
##   FIT_REPORT {"1600x900": {"new_game": {"clipped": [...], "rects": {"start": [x, y, w, h], ...}}, ...}, "1280x720": ...}
##
## `clipped` lists every visible button, label, check box, picker, text box, scroll container and panel that reaches
## outside the viewport and does not sit inside a ScrollContainer (what a scroll container holds is clipped to it, and
## the container itself is listed when it is out). `rects` holds the screens' key nodes in viewport coordinates.
## It never touches the player's settings or saves: settings go to a scratch file under user://.
##
##   godot --headless --path . --script res://tests/screen_fit_probe.gd

const SIZES := [Vector2i(1600, 900), Vector2i(1280, 720)]
const SCRATCH := "user://screen_fit_probe"

var report := {}


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(SCRATCH)
	GameSettings.default_path = SCRATCH.path_join("settings.cfg")
	_run()


func _run() -> void:
	await process_frame
	for size in SIZES:
		var key := "%dx%d" % [size.x, size.y]
		report[key] = {}
		for entry in _screens():
			report[key][entry[0]] = await _measure(size, entry[1])
	print("FIT_REPORT " + JSON.stringify(report))
	quit()


## Every screen the ticket names, and the worst cases of each: [name, Callable -> Control].
func _screens() -> Array:
	return [
		["title", _title],
		["new_game", _new_game],
		["new_game_full", _new_game_full],
		["new_game_error", _new_game_error],
		["victory", _victory.bind(false, false)],
		["victory_actions", _victory.bind(true, false)],
		["victory_everything", _victory.bind(true, true)],
		["victory_draw", _victory_draw],
		["build", _build],
		["codex", _codex],
		["settings", _settings],
		["load", _load],
		["guide", _guide],
		["game", _game],
		["game_research", _game_research],
		["game_report", _game_report],
		["game_cast", _game_cast],
	]


func _measure(size: Vector2i, make: Callable) -> Dictionary:
	var vp := SubViewport.new()
	vp.size = size
	vp.disable_3d = true
	root.add_child(vp)
	var screen: Control = make.call()
	vp.add_child(screen)
	for i in 4:
		await process_frame
	var clipped := []
	if not screen is GameScreen:  # the game's map is bigger than its window by design: its screens are measured by rects
		_clipped(screen, Rect2(Vector2.ZERO, Vector2(size)), false, clipped)
	var out := {"clipped": clipped, "rects": _rects(screen)}
	vp.queue_free()
	await process_frame
	return out


func _r(c: Control) -> Array:
	if c == null:
		return []
	var r := c.get_global_rect()
	return [r.position.x, r.position.y, r.size.x, r.size.y, c.is_visible_in_tree()]


## A rect as drawn: through the control's own transform, so a panel PanelFit has scaled reports the size it shows.
func _r_rect(r: Rect2) -> Array:
	return [r.position.x, r.position.y, r.size.x, r.size.y, true]


func _rt(c: Control) -> Array:
	if c == null:
		return []
	var r: Rect2 = c.get_global_transform() * Rect2(Vector2.ZERO, c.size)
	return [r.position.x, r.position.y, r.size.x, r.size.y, c.is_visible_in_tree()]


func _rects(screen: Control) -> Dictionary:
	var rects := {}
	if screen is GameScreen:
		var map := (screen as GameScreen).map
		var report_box: Control = screen.report_overlay.get_node("Center/Box")
		var research: Control = null
		if screen.research_hud != null and screen.research_hud.panel != null:
			research = screen.research_hud.panel.get_node("Center/Panel")
		# UX-1: the Table. The top bar, the hint row and the side panel are gone; the plaques, the system row, the tray and the seal
		# sit over a full-bleed map view. (tests/table_probe.gd measures every piece in every state, and the mouse; this is the fit.)
		var hud := map.table()
		rects = {"plaque": _r(hud.plaque), "system_row": _r(hud.system_row), "opponent": _r(hud.opponent_panel), "tray": _r(hud.tray), "seal": _r(hud.seal),
			"end_turn": _r(screen.end_turn_button), "menu": _r(map.back_button),
			"hint": _r(map.hint_label), "research": _r(screen.research_hud.chip), "magic": _r(screen.research_hud.magic_chip),
			"ruler": _r(screen.ruler_button), "report": _r(screen.report_button), "codex": _r(screen.codex_button), "help": _r(screen.help_button),
			"chronicle": _r(screen.chronicle_button), "lenses": _r(screen.lenses_button),
			"compact": [1.0 if hud.compact else 0.0, 0.0, 0.0, 0.0, true], "card": _r(map.cards), "safe": _r_rect(hud.safe_area()),
			"guide": _r(screen.first_game_guide), "map": _r(map.map_view),
			"research_panel": _rt(research), "research_close": _r(screen.research_hud.panel.close_button) if research != null else [],
			"report_box": _rt(report_box), "report_close": _r(screen.report_overlay.find_child("CloseReportButton", true, false))}
		if map.cast_dialog != null and map.cast_dialog.visible:  # UI-POLISH-1 (#239): the cast dialog and what it shows
			rects["cast_panel"] = _r(map.cast_dialog.panel)
			rects["cast_want"] = map.cast_dialog.panel.get_combined_minimum_size().y
	elif screen is NewGameScreen:
		rects = {"start": _r(screen.start_button), "back": _r(screen.back_button), "scroll": _r(screen.body_scroll),
			"panel": _r(screen.find_child("Panel", true, false)), "error": _r(screen.error_label),
			"content_h": screen.body_scroll.get_child(0).get_combined_minimum_size().y}
	elif screen is VictoryScreen:
		rects = {"new_game": _r(screen.new_game_button), "back": _r(screen.title_button), "captures": _r(screen.captures_box),
			"captures_heading": _r(screen.captures_heading), "scroll": _r(screen.find_child("Scroll", true, false)),
			"panel": _r(screen.find_child("Panel", true, false)), "actions": _r(screen.actions_row),
			"content_h": (screen.find_child("Scroll", true, false) as ScrollContainer).get_child(0).get_combined_minimum_size().y}
	elif screen is TitleScreen:
		rects = {"box": _r(screen.get_node("Center/Box")), "new_game": _r(screen.new_game_button), "quit": _r(screen.quit_button),
			"continue": _r(screen.continue_button), "map_preview": _r(screen.map_preview_button)}
	elif screen is BuildScreen:
		rects = {"lock_in": _r(screen.lock_button), "back": _r(screen.back_button),
			"columns": _r(screen.find_child("ColumnsScroll", true, false)), "header": _r(screen.find_child("Header", true, false)),
			"more": _r(screen.columns_more), "more_button": _r(screen.columns_more.button),  # UI-FIT (#237): the "More" cue
			"columns_h": (screen.find_child("Columns", true, false) as Control).get_combined_minimum_size().y}
	elif screen is CodexPanel:
		rects = {"panel": _r(screen.get_node("Background")), "close": _r(screen.get_node("%CloseButton"))}
	elif screen is SettingsPanel:
		rects = {"panel": _r(screen.find_child("Panel", true, false)), "close": _r(screen.close_button), "guide": _r(screen.guide_button)}
	elif screen is LoadScreen:
		rects = {"panel": _r(screen.find_child("Panel", true, false)), "back": _r(screen.back_button),
			"list": _r(screen.find_child("Scroll", true, false))}
	elif screen is FirstGameGuide:
		var title: Label = screen.title_label
		var font: Font = title.get_theme_font("font")
		rects = {"card": _r(screen), "title": _r(title),
			"title_need": [font.get_string_size(title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, title.get_theme_font_size("font_size")).x, 0.0, 0.0, 0.0, true]}
	return rects


func _clipped(n: Node, viewport: Rect2, in_scroll: bool, out: Array) -> void:
	var c := n as Control
	if c != null:
		if not c.visible:
			return
		var leaf := c is Button or c is Label or c is LineEdit or c is OptionButton or c is CheckBox or c is RichTextLabel
		if (not in_scroll and (leaf or c is PanelContainer)) or c is ScrollContainer:
			var r := c.get_global_rect()
			if r.size.x > 0.0 and not viewport.grow(0.5).encloses(r):
				out.append("%s (%s): %s" % [c.name, c.get_class(), r])
		if c is ScrollContainer:
			in_scroll = true
	for k in n.get_children():
		_clipped(k, viewport, in_scroll, out)


# --- the screens ------------------------------------------------------------------------------------

func _title() -> Control:
	var t: TitleScreen = load("res://ui/title_screen.tscn").instantiate()
	t.store = SaveStore.new(SCRATCH.path_join("saves"))
	t.refresh_saves()
	t.continue_button.visible = true  # the tallest the title gets: a save to continue
	return t


func _new_game() -> Control:
	return NewGameScreen.new()


## Every box ticked (MVP-2: the default), a rematch note, the settings-file note, and the computer's explanation: the most the
## screen ever shows.
func _new_game_full() -> Control:
	var s := NewGameScreen.new()
	var last := {"players": ["kingdom", "beasts"], "seed": 7, "ai": {"beasts": "normal"}}
	last.merge(NewGameScreen.default_systems())
	s.prefill(last)
	s.defaults_label.visible = true
	s.set_seat_kind(1, "computer")
	s.set_seat_kind(2, "computer")
	return s


## An invalid seed: the error line shows above the buttons and Start is off.
func _new_game_error() -> Control:
	var s := NewGameScreen.new()
	s.seed_edit.text = "not a number"
	s.seed_edit.text_changed.emit("not a number")
	return s


func _summary() -> Dictionary:
	return {"winner": "beasts", "turn": 22, "draw": false, "turns_played": 22, "battles": 1,
		"text": "Thornmane Clans captured Crownkeep, the Aurel Crown capital, on turn 22. Thornmane Clans wins after 22 turns and 1 battle. Provinces held: Aurel Crown 3, Thornmane Clans 11.",
		"provinces_held": {"kingdom": 3, "beasts": 11}, "captures": [{"captor": "beasts", "capital": "crownkeep", "of": "kingdom"}]}


## A game over: `actions` adds the game screen's two extra buttons, `everything` the paths, sieges and fog blocks.
func _victory(actions: bool, everything: bool) -> Control:
	var v := VictoryScreen.new()
	if actions:
		v.add_action("FinalReportButton", "Final turn report", "x")
		v.add_action("ViewMapButton", "View the map", "x")
	var state := GameState.new(99)
	if everything:
		state = GameState.with_paths(99, {}, [])
		state.setup_sieges()
		state.setup_fog()
		v.siege_stats = {"kingdom": {"forts_built": 2, "sieges_won": 1, "storms": 0}, "beasts": {"forts_built": 1, "sieges_won": 3, "storms": 2}}
		v.fog_lift = {"factions": [{"faction": "kingdom", "name": "Aurel Crown", "lines": ["Ruler: King Corvane, 4 power kept", "Gold: 120", "Armies: 3"]},
			{"faction": "beasts", "name": "Thornmane Clans", "lines": ["Ruler: Great Thornmane, 6 power kept", "Gold: 220", "Armies: 5"]}],
			"missed": [{"turn": 5, "faction": "kingdom", "text": "x"}, {"turn": 9, "faction": "kingdom", "text": "y"}]}
	v.show_victory(_summary(), state, ["kingdom", "beasts"], {"beasts": "normal"})
	return v


func _victory_draw() -> Control:
	var v := VictoryScreen.new()
	var summary := _summary()
	summary.winner = ""
	summary.draw = true
	summary.captures = [{"captor": "beasts", "capital": "crownkeep", "of": "kingdom"}, {"captor": "kingdom", "capital": "fangridge", "of": "beasts"}]
	v.add_action("FinalReportButton", "Final turn report", "x")
	v.add_action("ViewMapButton", "View the map", "x")
	v.show_victory(summary, GameState.new(99), ["kingdom", "beasts"], {"beasts": "normal"})
	return v


func _build() -> Control:
	var b := load(BuildScreen.SCENE).instantiate() as BuildScreen
	b.begin({"players": ["kingdom", "beasts"], "seed": 4242, "ai": {"beasts": "normal"}, "rulers": true})
	if b.step == BuildScreen.Step.HANDOFF:
		b.acknowledge()
	return b


func _codex() -> Control:
	var c: CodexPanel = load("res://ui/codex_panel.tscn").instantiate()
	c.open("how_to_play")
	return c


func _settings() -> Control:
	var p := SettingsPanel.new()
	p.open(GameSettings.new(SCRATCH.path_join("settings.cfg")))
	return p


func _load() -> Control:
	var l := LoadScreen.new()
	l.open(SaveStore.new(SCRATCH.path_join("saves")))
	return l


## A game with every system on at turn 1, orders phase, the first-game card up (the 2D map: the 3D board's land bake needs a
## renderer, and the Table, the cards and the panels are the same either way; tests/table_probe.gd has the 3D board).
func _game() -> Control:
	var gs := GameSettings.new(SCRATCH.path_join("settings.cfg"))
	gs.set_board("2d")
	gs.save()
	GameSettings.reset_hint(GameSettings.HINT_FIRST_GAME)  # a game before this one finished its first turn: the card shows again
	GameSettings.reset_hint("fog")
	var g: GameScreen = load("res://ui/game_screen.tscn").instantiate()
	g.autosave_enabled = false
	g.save_store = SaveStore.new(SCRATCH.path_join("saves"))
	g.start_game({"players": ["kingdom", "beasts"], "seed": 777, "rulers": true, "paths": true, "sieges": true, "fog": true, "magic": true,
		"independents": true, "ai": {"beasts": "normal"},
		"builds": {"kingdom": RulerRules.preset_build(RulerRules.balanced_preset("kingdom")), "beasts": BuildScreen.computer_build("beasts", 777, 1)}})
	return g


## The same game with the research panel open on its Magic tab (the biggest centred panel).
func _game_research() -> Control:
	var g: GameScreen = _game()
	g.close_turn_report()
	g.research_hud.open_magic()
	return g


## The same game after turn 1, with the turn report open.
func _game_report() -> Control:
	var g: GameScreen = _game()
	g.close_turn_report()
	g.end_turn()
	g.open_turn_report()
	return g


## UI-POLISH-1 (#239): the same game with the cast dialog open for the ruler's army (it casts Far Sight from turn 1).
func _game_cast() -> Control:
	var g: GameScreen = _game()
	g.close_turn_report()
	var ruler := RulerRules.ruler_army(g.session.state(), "kingdom")
	g.map.open_cast_dialog(ruler.id)
	return g


## The first-game card in a game with every system on, its tallest state.
func _guide() -> Control:
	GameSettings.reset_hint(GameSettings.HINT_FIRST_GAME)
	var state := GameState.with_rulers(9)
	state.setup_paths()
	state.setup_sieges()
	state.setup_fog()
	state.setup_magic()
	state.setup_independents()
	var session := GameSession.new(state, ["kingdom", "beasts"], 9, StubBattleResolver.new(), {"beasts": "normal"})
	var g := FirstGameGuide.new()
	g.sync(session, session.state_for("kingdom"))
	return g
