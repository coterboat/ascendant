extends "res://tests/test_case.gd"
## #316 (QA): the research panel's Magic tab status line was reported to end with a double period ("…until you end the turn..").
## The line is what the game screen writes after an order from the tab (ResearchHud.queue, ResearchHud.queue_spellbook): a research
## order joins the research forecast's sentences to its own, a spellbook change joins the spellbook's names to its. Pinned for both
## factions with a Magic tab, on the line as the panel shows it: it is the order's, it ends with one period, and no sentence it joins
## brings a second.

const GAME_SCENE := "res://ui/game_screen.tscn"
const SEED := 21
## The factions whose games have a Magic tab, each with a rival.
const SEATS := [["kingdom", "beasts"], ["beasts", "kingdom"]]


func _game(seats: Array) -> GameScreen:
	var game := load(GAME_SCENE).instantiate() as GameScreen
	game.start_game({"players": seats, "seed": SEED, "magic": true})
	if game.handoff.visible:
		game.handoff.ready_button.pressed.emit()
	return game


func _assert_one_period(line: String, where: String) -> void:
	assert_true(line.ends_with(".") and not line.ends_with(".."), "%s: the line ends with one period: \"%s\"" % [where, line.right(90)])
	assert_false(line.contains(".."), "%s: no sentence it joins brings a second period: \"%s\"" % [where, line])


func test_the_magic_tabs_status_line_ends_with_one_period() -> void:
	for seats in SEATS:
		var game := _game(seats)
		var hud := game.research_hud
		hud.open_panel()
		hud.panel.show_magic()
		var spell := ""  # the first spell the tab lets this faction research now
		for key in hud.panel.buttons:
			if not (hud.panel.buttons[key] as Button).disabled:
				spell = String(key)
				break
		assert_false(spell.is_empty(), "%s: a spell to research" % seats[0])
		(hud.panel.buttons[spell] as Button).pressed.emit()
		var fc := Forecast.research(game.map.state, seats[0], game.session.current_orders())
		var line := hud.panel.status_label.text
		assert_true(hud.panel.status_label.visible and line.begins_with("Research order given: %s " % String(fc.text)), "%s: the research order's line, with its forecast: \"%s\"" % [seats[0], line])
		_assert_one_period(line, "%s, researching %s" % [seats[0], spell])
		var check: CheckBox = hud.panel.spellbook_checks.values()[0]
		check.toggled.emit(not check.button_pressed)
		var book: Array = game.session.current_orders().filter(func(o): return o is SpellbookOrder)
		assert_eq(book.size(), 1, "%s: the spellbook order" % seats[0])
		line = hud.panel.status_label.text
		assert_true(line.begins_with("Battle spellbook set: %s. " % MagicRules.spellbook_text(book[0].order, book[0].off)), "%s: the spellbook's line, with its spells: \"%s\"" % [seats[0], line])
		_assert_one_period(line, "%s, the spellbook" % seats[0])
		game.free()
