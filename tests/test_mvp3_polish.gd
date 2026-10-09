extends "res://tests/test_case.gd"
## MVP-3 (#177), first impressions polish with every system on (the neutral fort's battle text, item 13, has its own file:
## test_neutral_fort_text.gd). Headless, through the real screens. What each test pins:
##   1  the first-game guide folds the other systems' lines behind one row (every explanation still reachable), keeps its fog
##      line, and the first fog turn's banner waits for it instead of stacking beside it;
##   12 (the second walk's) the card stays short and hangs under the top bar, whatever height the bar has;
##   3  the new game screen's computer paragraph is one short line with a link to its codex entry;
##   5, 4 the top bar gives the hint a row of its own and the optional buttons a second row when the first is too narrow
##      (the real layout pass is tests/screen_fit_probe.gd's "game" screen, checked in test_screens_fit.gd);
##   6  the big centred panels shrink to fit a smaller viewport (PanelFit);
##   7  under fog the computer's notes are one quiet line, not a header with a scrolling box;
##   8  a greater working's card says what it needs once;
##   12a (the first walk's) the report folds a faction's recruits at one place into one line, and the record is untouched;
##   13a the report's aftermath has no "there are no retreats yet";
##   14 the turn report's backdrop is dark enough to quiet what it doesn't cover.
## Numbers and words come from the data and the rules, never from this file.

const GAME_SCENE := "res://ui/game_screen.tscn"
const CROWN := "kingdom"
const CLANS := "beasts"
const VS_COMPUTER := {"players": [CROWN, CLANS], "seed": 4242, "ai": {CLANS: "normal"}}
const ALL := {"rulers": true, "paths": true, "sieges": true, "fog": true, "magic": true, "independents": true}


func _game(config: Dictionary) -> GameScreen:
	var game := load(GAME_SCENE).instantiate() as GameScreen
	game.autosave_enabled = false
	game.start_game(config)
	return game


func _all_on() -> Dictionary:
	var config := VS_COMPUTER.duplicate()
	config.merge(ALL)
	return config


func _unseen() -> void:
	GameSettings.reset_hint(GameSettings.HINT_FIRST_GAME)
	GameSettings.reset_hint("fog")


func _card_text(node: Node, out: PackedStringArray) -> void:
	if node is CanvasItem and not (node as CanvasItem).visible:
		return
	if node is RichTextLabel:
		out.append((node as RichTextLabel).get_parsed_text())
	elif node is Label:
		out.append((node as Label).text)
	elif node is Button:
		out.append((node as Button).text)
	for c in node.get_children():
		_card_text(c, out)


# --- item 1 and the second walk's 12: the guide ---------------------------------------------------------------

func test_the_guide_folds_the_other_systems_and_every_explanation_stays_reachable() -> void:
	_unseen()
	var game := _game(_all_on())
	var guide := game.first_game_guide
	assert_eq(guide.showing(), CROWN, "the card is up on turn 1")
	assert_true(guide.systems_folded(), "the other systems are folded behind one row")
	assert_true(guide.systems_toggle.visible)
	assert_false(guide.systems_lines_box.visible)
	var shown := PackedStringArray()
	_card_text(guide, shown)
	var text := "\n".join(shown)
	var others := FirstGameGuide.SYSTEMS.filter(func(s): return String(s.id) != "fog")
	assert_eq(others.size(), 5, "five systems fold; fog does not")
	for s in others:
		var short := String(FirstGameGuide.SHORT_NAMES.get(String(s.id), s.name))
		assert_true(guide.systems_toggle.text.contains(short), "the row names %s: %s" % [short, guide.systems_toggle.text])
		assert_true(guide.systems_toggle.tooltip_text.replace("\n", " ").contains(String(s.rest)), "its tooltip says what %s is: %s" % [s.name, guide.systems_toggle.tooltip_text])
		assert_false((guide.system_lines[s.id] as Control).get_parent() != guide.systems_lines_box, "%s's line is in the fold" % s.id)
	assert_true((guide.system_lines["fog"] as Control).visible, "the fog line stays on the card")
	assert_eq(guide.system_lines["fog"].get_parent(), guide.systems_box, "outside the fold")
	assert_true(text.contains(String(FirstGameGuide.SYSTEMS[3].name)), "and says so: %s" % text)
	# Open it: every line is there, linked to its codex entry, with its tooltip.
	var opened := []
	guide.codex_requested.connect(func(key: String): opened.append(key))
	guide.systems_toggle.pressed.emit()
	assert_false(guide.systems_folded())
	assert_true(guide.systems_lines_box.visible)
	for s in FirstGameGuide.SYSTEMS:
		var line: RichTextLabel = guide.system_lines[s.id]
		assert_true(line.visible, "%s has its line" % s.id)
		assert_true(line.tooltip_text.replace("\n", " ").contains(String(s.tip).left(40)), "%s's tooltip is its tip" % s.id)
		line.meta_clicked.emit(String(s.entry))
		assert_eq(opened.back(), s.entry, "%s opens its codex entry" % s.id)
	guide.systems_toggle.pressed.emit()
	assert_true(guide.systems_folded(), "pressed again, it folds")
	game.free()
	_unseen()


func test_the_card_is_short_with_every_system_on() -> void:
	_unseen()
	var game := _game(_all_on())
	var guide := game.first_game_guide
	var open := PackedStringArray()
	_card_text(guide, open)
	guide.toggle_systems()
	var opened := PackedStringArray()
	_card_text(guide, opened)
	assert_true(open.size() < opened.size(), "folded, the card has fewer lines than open (%d against %d)" % [open.size(), opened.size()])
	# Layout is not live in a headless test: the card's minimum height is its content's.
	var folded_height := guide.get_combined_minimum_size().y
	guide.toggle_systems()
	assert_true(guide.get_combined_minimum_size().y <= folded_height + 0.5, "folding it again brings the height back")
	game.free()
	_unseen()


func test_the_card_hangs_under_the_top_bar_whatever_height_the_bar_has() -> void:
	var g := FirstGameGuide.new()
	assert_eq(g.offset_top, FirstGameGuide.TOP, "by itself it hangs where it always did")
	g.hang_under(62.0)
	assert_eq(g.offset_top, 62.0 + FirstGameGuide.BELOW_BAR)
	assert_eq(g.offset_top, FirstGameGuide.TOP, "under the old 62 px bar that is the same place")
	g.hang_under(105.0)
	assert_eq(g.offset_top, 105.0 + FirstGameGuide.BELOW_BAR, "under a taller bar it moves down with it")
	g.free()


func test_the_first_fog_banner_waits_for_the_guide_and_the_guide_says_the_same() -> void:
	_unseen()
	var config := VS_COMPUTER.duplicate()
	config["fog"] = true
	var game := _game(config)
	var guide := game.first_game_guide
	assert_eq(guide.showing(), CROWN, "the first-game card is up")
	assert_true(guide.explains_fog(), "and its fog line is what explains fog")
	assert_false(game.notice_panel.visible, "so the banner does not stack beside it")
	# The line's tooltip carries the whole rule the banner said.
	var tip := String((guide.system_lines["fog"] as Control).tooltip_text).replace("\n", " ")
	for part in ["exactly only where you own land or have an army", "glimpse armies roughly", "forts, commanders, rulers and scouts", "only what you saw last"]:
		assert_true(tip.contains(part), "the fog line's tooltip says '%s': %s" % [part, tip])
	# Finishing (or hiding) the card counts as having been told: the banner never comes after it either.
	assert_false(GameSettings.hint_seen("fog"))
	guide.hide_button.pressed.emit()
	assert_true(GameSettings.hint_seen(GameSettings.HINT_FIRST_GAME))
	assert_true(GameSettings.hint_seen("fog"), "the card's fog line told them: no banner later")
	game.free()
	# Without the card (it was seen in an earlier game) the banner is still the first fog turn's hint.
	var later := _game(config)
	assert_eq(later.first_game_guide.showing(), "", "no card")
	_unseen()
	GameSettings.mark_hint_seen(GameSettings.HINT_FIRST_GAME)
	var banner := _game(config)
	assert_true(banner.notice_panel.visible, "the banner shows when no card does")
	assert_eq(banner.notice_label.text, GameScreen.FOG_HINT)
	banner.free()
	later.free()
	_unseen()


func test_a_game_without_fog_has_no_banner_and_the_card_has_no_fog_line() -> void:
	_unseen()
	var config := VS_COMPUTER.duplicate()
	config["rulers"] = true
	var game := _game(config)
	assert_false(game.first_game_guide.explains_fog())
	assert_false(game.notice_panel.visible)
	assert_false((game.first_game_guide.system_lines["fog"] as Control).visible)
	game.free()
	_unseen()


# --- item 3: the new game screen ------------------------------------------------------------------------------

func test_the_computer_paragraph_is_one_short_line_with_a_codex_link() -> void:
	var ng: NewGameScreen = load("res://ui/new_game_screen.tscn").instantiate()
	ng._refresh()
	assert_true(ng.computer_label.visible, "against the computer by default")
	assert_true(ng.computer_label.text.length() <= 100, "one line, not a block (%d characters): %s" % [ng.computer_label.text.length(), ng.computer_label.text])
	assert_true(ng.computer_label.text.contains("Easy") and ng.computer_label.text.contains("Normal"), "it still says what the levels are")
	assert_true(ng.computer_link.visible and ng.computer_head.visible)
	var opened := []
	ng.codex_requested.connect(func(key: String): opened.append(key))
	ng.computer_link.pressed.emit()
	assert_eq(opened, ["computer_opponent"], "the link opens the codex entry")
	assert_true(RulesCodex.ENTRIES.has("computer_opponent"))
	assert_eq(CodexLink.key_at(ng.computer_label), "computer_opponent", "right-click or F1 on the paragraph does too")
	ng.free()


# --- items 4 and 5: the top bar rows --------------------------------------------------------------------------

func test_the_hint_has_a_row_of_its_own_and_the_optional_buttons_can_join_it() -> void:
	var game := _game(_all_on())
	var map := game.map
	assert_eq(map.hint_label.get_parent(), map.hint_row, "the hint sits in the second row")
	assert_eq(map.hint_row.get_parent(), map.bar_row.get_parent(), "under the buttons' row")
	for button in [game.end_turn_button, map.back_button]:
		assert_eq(button.get_parent(), map.bar_row, "%s is in the first row" % button.text)
	# Narrow: every optional button moves down beside the hint, End turn and Menu stay; wide: they come back, in order.
	var chips := [game.research_hud.chip, game.research_hud.magic_chip, game.ruler_button, game.report_button, game.codex_button]
	var order_before := map.bar_row.get_children().map(func(c): return c.name)
	map._bar_narrow = true
	map._place_bar_items()
	for c in chips:
		assert_eq(c.get_parent(), map.hint_row, "%s moved beside the hint" % c.name)
	assert_eq(game.end_turn_button.get_parent(), map.bar_row)
	assert_eq(map.back_button.get_parent(), map.bar_row)
	assert_eq(map.hint_row.get_child(0), map.hint_label, "the hint stays first in its row, expanding")
	assert_eq(map.bar_row.get_child(map.bar_row.get_child_count() - 1), map.back_button, "Menu stays last")
	map._bar_narrow = false
	map._place_bar_items()
	assert_eq(map.bar_row.get_children().map(func(c): return c.name), order_before, "wide again: the same buttons in the same order")
	assert_eq(map.hint_row.get_child_count(), 1, "and only the hint in the second row")
	game.free()


func test_the_hint_and_its_whole_help_are_unchanged() -> void:
	var game := _game(_all_on())
	assert_true(game.map.hint_label.text.begins_with("Move: select an army"), game.map.hint_label.text)
	assert_true(game.map.hint_label.tooltip_text.replace("\n", " ").contains("neighboring province"), "the tooltip keeps the whole how-to")
	game.free()


# --- item 6: big panels fit a small viewport -----------------------------------------------------------------

func test_a_big_panel_shrinks_to_fit_a_small_viewport_and_not_otherwise() -> void:
	var panels := {"research": ResearchPanel.PANEL_SIZE, "lock-in": LockInPreview.PANEL_SIZE, "ruler": RulerPanel.PANEL_SIZE,
		"sacrifice": SacrificeDialog.PANEL_SIZE, "report": Vector2(1040, 760)}
	for name in panels:
		var size: Vector2 = panels[name]
		assert_eq(PanelFit.scale_for(size, Vector2(1600, 900)), 1.0, "%s is untouched at 1600x900" % name)
		var s := PanelFit.scale_for(size, Vector2(1280, 720))
		assert_true(s > 0.0 and s <= 1.0, "%s: a scale of %s" % [name, s])
		assert_true(size.x * s <= 1280.0 - 2.0 * PanelFit.MARGIN + 0.01 and size.y * s <= 720.0 - 2.0 * PanelFit.MARGIN + 0.01,
			"%s fits a 1280x720 viewport scaled by %.2f" % [name, s])
		assert_true(s >= PanelFit.MIN_SCALE, "%s stays readable (%.2f)" % [name, s])
	assert_eq(PanelFit.scale_for(Vector2(1000, 600), Vector2(1280, 720)), 1.0, "a panel that fits is left alone")
	assert_eq(PanelFit.scale_for(Vector2(4000, 4000), Vector2(1280, 720)), PanelFit.MIN_SCALE, "never smaller than the floor")
	assert_eq(PanelFit.scale_for(Vector2.ZERO, Vector2(1280, 720)), 1.0, "no size, no scaling")


# --- item 7: the computer's notes under fog ------------------------------------------------------------------

func test_under_fog_the_computers_notes_are_one_quiet_line() -> void:
	var config := VS_COMPUTER.duplicate()
	config["fog"] = true
	var game := _game(config)
	game.close_turn_report()
	game.end_turn()
	game.open_turn_report()
	var panel := game.report_panel
	assert_true(panel.notes_section.visible, "the section is there")
	assert_false(panel.notes_toggle.visible, "without its header and count")
	assert_true(panel.notes_scroll.visible, "the line shows")
	var labels := panel.computer_note_labels()
	assert_eq(labels.size(), 1, "one line")
	assert_true(String(labels[0].text).contains(FogView.NOTES_HIDDEN), labels[0].text)
	assert_true(labels[0].get_theme_font_size("font_size") <= 16, "a quiet size")
	assert_eq(CodexLink.key_at(labels[0]), "computer_opponent", "it still links its entry")
	assert_true(String(labels[0].tooltip_text).length() > 60, "and explains itself on hover")
	assert_true(panel.notes_scroll.custom_minimum_size.y <= 30.0, "it takes one line of room, not a scrolling box (%s)" % panel.notes_scroll.custom_minimum_size)
	# Without fog the section is as it was: a header with the count.
	var plain := _game(VS_COMPUTER)
	plain.close_turn_report()
	plain.end_turn()
	plain.open_turn_report()
	assert_true(plain.report_panel.notes_toggle.visible, "without fog the notes have their header")
	plain.free()
	# Game over lifts the fog: the notes show as notes again.
	game.session._phase = GameSession.Phase.GAME_OVER
	game.open_turn_report()
	assert_true(game.report_panel.notes_toggle.visible, "once the game is over the notes show")
	game.free()


# --- item 8: a greater working says what it needs once --------------------------------------------------------

func test_a_greater_workings_card_says_what_it_needs_once() -> void:
	var errors := []
	var s := GameState.with_magic(77, {}, errors)
	assert_eq(errors, [])
	# Every tier III spell of both factions, from the data: no static "Needs ..." sentence in its own text (the card's
	# needs line names what is still missing, the Oath included), and at most one such line on the card.
	var greater := 0
	for fid in [CROWN, CLANS]:
		for nid in MagicData.ARCANA[fid].map(func(n): return String(n.id)):
			var sp := MagicRules.spell_data(nid)
			if sp.is_empty() or String(sp.get("tier", "")) != "III":
				continue
			greater += 1
			assert_false(String(sp.text).contains("Needs"), "%s's own text has no needs sentence: %s" % [sp.name, sp.text])
			var detail := String(MagicView.card(s, fid, nid).detail)
			var count := detail.split("Needs ").size() - 1
			assert_true(count <= 1, "%s's card says it needs something at most once (%d): %s" % [sp.name, count, detail])
	assert_eq(greater, 4, "one greater working for each school of the two factions")


# --- the turn report: recruits, aftermath, backdrop -----------------------------------------------------------

func _recruit_turn(sieges: bool, orders: Array) -> Dictionary:
	var s := GameState.with_sieges(77) if sieges else GameState.new(77)
	s.find_faction(CROWN).gold = 500
	var list := []
	for type_id in orders:
		list.append(RecruitOrder.new(type_id))
	return TurnResolver.resolve(s, {CROWN: list}, 5, AutoBattleResolver.new())


func test_recruits_at_one_place_are_one_line_and_the_record_is_untouched() -> void:
	for sieges in [true, false]:
		var result := _recruit_turn(sieges, ["spearmen", "spearmen", "knights", "spearmen"])
		var recruits: Array = result.events.filter(func(e): return e.type == "recruited")
		assert_eq(recruits.size(), 4, "four recruit events, as ever")
		for e in recruits:
			assert_false(String(e.text).contains("recruited 3 "), "the record's own sentences are one unit each: %s" % e.text)
		var rows := TurnReportText.rows(result.events, result.new_state)
		var recruit_rows := rows.filter(func(r): return String(r.event.type) == "recruited")
		assert_eq(recruit_rows.size(), 1, "the report has one line for them (sieges %s)" % sieges)
		var text := String(recruit_rows[0].text)
		var cost := 0
		for e in recruits:
			cost += int(e.numbers.cost)
		var names := []
		var faction: Faction = result.new_state.find_faction(CROWN)
		for type_id in ["spearmen", "knights"]:
			for ut in faction.unit_types:
				if ut.id == type_id:
					names.append(ut.name)
		assert_true(text.contains("recruited 3 %s and %s " % [names[0], names[1]]), text)
		assert_true(text.contains("for %d gold (%d gold left)" % [cost, int(recruits.back().numbers.gold_after)]), "the costs added up, the last gold left: %s" % text)
		if sieges:
			assert_true(text.contains("(%s, %d of %d this turn)" % [TurnReportText._fort_word(recruits.back().numbers, "crownkeep", result.new_state),
				int(recruits.back().numbers.count), int(recruits.back().numbers.limit)]), "the fort's count is the last unit's: %s" % text)
		assert_true(text.contains("They"), "plural: %s" % text)
		assert_eq(rows.size(), result.events.filter(func(e): return not TurnReportText.is_beat(e, result.events)).size() - 3, "three rows fewer than events")


func test_one_recruit_keeps_its_own_line_exactly() -> void:
	var result := _recruit_turn(true, ["knights"])
	var rows := TurnReportText.rows(result.events, result.new_state)
	var recruit_rows := rows.filter(func(r): return String(r.event.type) == "recruited")
	assert_eq(recruit_rows.size(), 1)
	var e: Dictionary = result.events.filter(func(x): return x.type == "recruited")[0]
	assert_eq(String(recruit_rows[0].text), TurnReportText.line(e, result.events, result.new_state), "a lone recruit reads as it always did")


func test_recruits_in_different_places_or_armies_stay_apart() -> void:
	var a := {"type": "recruited", "cause": "order", "factions": [CROWN], "provinces": ["crownkeep"], "armies": ["kingdom-1"], "numbers": {"cost": 20}}
	var b := a.duplicate(true)
	assert_true(TurnReportText._same_recruit_place(a, b))
	b.provinces = ["stonegate"]
	assert_false(TurnReportText._same_recruit_place(a, b), "another place")
	b = a.duplicate(true)
	b.armies = ["kingdom-2"]
	assert_false(TurnReportText._same_recruit_place(a, b), "another army")
	b = a.duplicate(true)
	b.cause = "with_ruler"
	assert_false(TurnReportText._same_recruit_place(a, b), "a Warband Muster recruit has its own words")
	b = a.duplicate(true)
	b.factions = [CLANS]
	assert_false(TurnReportText._same_recruit_place(a, b), "another faction")


func test_the_report_never_promises_retreats() -> void:
	var e := {"type": "battle"}
	assert_false(TurnReportText.readable_aftermath("x (there are no retreats yet).").contains("retreats"))
	assert_true(e.has("type"))
	# The three outcomes of the report's loser line, from a real resolved battle: none says "no retreats yet".
	var s := GameState.new(3)
	var winner := Army.new()
	winner.id = "kingdom-9"
	winner.owner = CROWN
	winner.location = "westwatch"
	for i in 6:
		winner.units.append(Unit.new(s.find_faction(CROWN).unit_types[1], CROWN))
	s.armies.append(winner)
	var loser: Army = s.armies.filter(func(a): return a.owner == CLANS)[0]
	loser.location = "stonegate"
	var result := TurnResolver.resolve(s, {CROWN: [MoveOrder.new(winner.id, "stonegate")]}, 11, AutoBattleResolver.new())
	for row in TurnReportText.rows(result.events, result.new_state):
		assert_false(String(row.text).contains("no retreats yet"), row.text)


func test_the_turn_reports_backdrop_is_dark_enough_to_quiet_the_side_panel() -> void:
	var game := _game(VS_COMPUTER)
	var dim := game.report_overlay.get_node("Dim") as ColorRect
	assert_true(is_equal_approx(dim.color.a, GameScreen.REPORT_DIM), "the overlay uses it (%s)" % dim.color.a)
	assert_true(GameScreen.REPORT_DIM >= 0.7, "dark enough that half-cut lines behind the box don't read")
	assert_true(GameScreen.REPORT_DIM < 1.0, "and the map is still faintly there")
	game.free()
