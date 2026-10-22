extends "res://tests/test_case.gd"
## CW-7 (#258, design/CANDLEWAKE.md §1, §12): the screens for three factions in two seats. The new game screen's "Candlewake
## (preview)" box (off by default, remembered in the settings file) lets either seat pick them; the same faction can't sit
## twice; a faction that can't play a ticked system yet says so in plain words and disables Start; each seat's line names
## its capital, the Candlewake's as the Long Vigil and which map capital it is this game; a rematch of a Candlewake game
## ticks the box again. The title hangs a preview faction's banner only with the box ticked and its art in, three as a
## triptych. The art, report and victory lookups find the Candlewake's units and name (the battle views' are lane 3D's).
## The engine side (the factory, the derived capitals, Quick start's draw) is tests/test_three_factions.gd's (CW-0).

const SCENE := "res://ui/new_game_screen.tscn"
const TITLE_SCENE := "res://ui/title_screen.tscn"
const CROWN := "kingdom"
const CLANS := "beasts"
const WAKE := "candlewake"


func _settings_path(tag: String) -> String:
	var path := "user://test_three_faction_screens_%s_%d.cfg" % [tag, OS.get_process_id()]
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return path


## The screen as a player finds it, with its settings in `path` (the box as the file says, as _ready reads it).
func _screen(path: String) -> NewGameScreen:
	var screen := load(SCENE).instantiate() as NewGameScreen
	screen.settings_file = path
	screen._show_preview(GameSettings.preview_factions_on(path))
	return screen


func _items(picker: OptionButton) -> Array:
	var out := []
	for i in picker.item_count:
		out.append(String(picker.get_item_metadata(i)))
	return out


## Whether a banner hangs at `spot` ([left anchor, right anchor]) and `rows` ([top anchor, bottom anchor, top offset, bottom
## offset]); anchors are single-precision floats.
func _at(banner: Control, spot: Array, rows: Array) -> bool:
	return is_equal_approx(banner.anchor_left, float(spot[0])) and is_equal_approx(banner.anchor_right, float(spot[1])) \
		and is_equal_approx(banner.anchor_top, float(rows[0])) and is_equal_approx(banner.anchor_bottom, float(rows[1])) \
		and is_equal_approx(banner.offset_top, float(rows[2])) and is_equal_approx(banner.offset_bottom, float(rows[3]))


func _wake_name() -> String:
	return String(FactionData.row(WAKE).name)


# --- the new game screen ---------------------------------------------------------------------------------------------

func test_the_preview_box_is_off_by_default_and_lists_the_candlewake_when_ticked() -> void:
	var path := _settings_path("box")
	var screen := _screen(path)
	assert_false(screen.preview_on(), "off by default")
	assert_eq(screen.faction_ids(), [CROWN, CLANS], "the pickers list the two shipped factions")
	for picker in screen.seat_pickers:
		assert_eq(_items(picker), [CROWN, CLANS])
	assert_false(screen.select_faction(2, WAKE), "the Candlewake can't be picked with the box clear")
	assert_true(String(screen.preview_toggle.text).begins_with(_wake_name()), screen.preview_toggle.text)
	screen.set_preview(true)
	assert_true(GameSettings.preview_factions_on(path), "the box is remembered in the settings file")
	assert_eq(screen.faction_ids(), FactionData.ids(), "ticked: every faction")
	for picker in screen.seat_pickers:
		assert_eq(_items(picker), FactionData.ids())
		assert_true(picker.get_item_text(FactionData.ids().find(WAKE)).ends_with("(preview)"), "the item says it is a preview")
	assert_eq([screen.seat_faction(1), screen.seat_faction(2)], [CROWN, CLANS], "ticking it keeps the seats")
	assert_true(screen.select_faction(2, WAKE))
	assert_eq(screen.seat_faction(2), WAKE)
	# Cleared, the seat that held them takes the first faction the other seat doesn't hold.
	screen.set_preview(false)
	assert_false(GameSettings.preview_factions_on(path))
	assert_eq([screen.seat_faction(1), screen.seat_faction(2)], [CROWN, CLANS])
	screen.free()
	# A new screen finds the box as the file left it.
	GameSettings.set_preview_factions(true, path)
	var again := _screen(path)
	assert_true(again.preview_on() and again.faction_ids().has(WAKE), "remembered for the next new game")
	again.free()
	DirAccess.remove_absolute(path)


func test_the_same_faction_twice_is_refused_with_the_candlewake_too() -> void:
	var path := _settings_path("twice")
	var screen := _screen(path)
	screen.set_preview(true)
	screen.set_all_systems(false)
	assert_true(screen.select_faction(1, WAKE) and screen.select_faction(2, WAKE))
	assert_false(screen.is_valid())
	assert_true(screen.error_text().contains("both picked %s" % _wake_name()), screen.error_text())
	assert_true(screen.start_button.disabled)
	assert_true(screen.select_faction(1, CROWN))
	assert_true(screen.is_valid(), screen.error_text())
	screen.free()
	DirAccess.remove_absolute(path)


func test_a_system_the_candlewake_cant_play_yet_is_named_and_disables_start() -> void:
	var path := _settings_path("systems")
	var screen := _screen(path)
	screen.set_preview(true)
	screen.set_all_systems(true)
	assert_true(screen.select_faction(2, WAKE))
	var missing := NewGameScreen.systems_not_ready(WAKE)
	var why := screen.system_problem(WAKE)
	if missing.is_empty():
		assert_eq(why, "", "every system is ready for them")
		screen.free()
		DirAccess.remove_absolute(path)
		return
	# The deepest box first: its words name every box to untick (GameState.system_problems, Rulers alone).
	var deepest := GameState.system_problems(WAKE, {String(missing[0]).to_lower(): true})
	assert_eq(why, String(deepest[0]))
	for box in missing:
		assert_true(why.contains(String(box)), "'%s' names %s" % [why, box])
	assert_true(screen.error_text().contains(why), screen.error_text())
	assert_true(screen.start_button.disabled)
	assert_eq(screen.system_problem(CROWN), "", "the Crown can play every system")
	# Unticking the deepest box clears the ones that lean on it, and the game can start with the rest.
	screen.call("set_" + String(missing[0]).to_lower(), false)
	assert_eq(screen.system_problem(WAKE), "", screen.error_text())
	assert_true(screen.is_valid(), screen.error_text())
	for key in ["sieges", "fog", "independents"]:
		assert_true(bool(screen.config().get(key, false)), "%s stays on: they can play it" % key)
	screen.free()
	DirAccess.remove_absolute(path)


func test_each_seat_names_its_capital_and_the_candlewake_name_theirs_the_long_vigil() -> void:
	var path := _settings_path("capital")
	var screen := _screen(path)
	screen.set_preview(true)
	screen.set_all_systems(false)
	var shown := String(FactionData.row(WAKE).capital_name)
	var map := GameState.new()
	for pair in [[CROWN, WAKE], [WAKE, CLANS]]:
		assert_true(screen.set_seats(pair))
		var cap := String(FactionData.capitals_for(pair)[WAKE])
		var seat: int = pair.find(WAKE)
		var line := String(screen.faction_labels[seat].text)
		assert_true(line.contains("Capital %s (%s this game)" % [shown, map.find_province(cap).name]), line)
		var other := String(pair[1 - seat])
		var own := map.find_province(String(FactionData.row(other).capital)).name
		assert_true(String(screen.faction_labels[1 - seat].text).contains("Capital %s," % own), screen.faction_labels[1 - seat].text)
	assert_true(String(screen.faction_labels[0].tooltip_text).contains(shown), "the tooltip says what the Long Vigil is")
	screen.free()
	DirAccess.remove_absolute(path)


func test_the_candlewake_seat_plays_as_configured_with_its_capital_named() -> void:
	var path := _settings_path("start")
	var screen := _screen(path)
	screen.set_preview(true)
	screen.set_all_systems(false)
	assert_true(screen.set_seats([CROWN, WAKE]))
	var config := screen.config()
	assert_eq(config.players, [CROWN, WAKE])
	var errors := []
	var s := GameScreen.starting_state(config, errors)
	assert_true(s != null and errors.is_empty(), "%s" % [errors])
	var wake := s.find_faction(WAKE)
	assert_eq(s.find_province(wake.capital).name, String(FactionData.row(WAKE).capital_name), "the game names it the Long Vigil")
	screen.free()
	DirAccess.remove_absolute(path)


func test_a_rematch_of_a_candlewake_game_ticks_the_box_again() -> void:
	var path := _settings_path("rematch")
	var screen := _screen(path)
	assert_false(screen.preview_on())
	screen.prefill({"players": [WAKE, CLANS], "seed": 12, "ai": {CLANS: "normal"}})
	assert_true(screen.preview_on(), "the rematch seats them, so the box is ticked")
	assert_eq([screen.seat_faction(1), screen.seat_faction(2)], [WAKE, CLANS])
	assert_true(screen.rematch_label.visible)
	screen.free()
	DirAccess.remove_absolute(path)


func test_no_raw_ids_with_the_preview_on() -> void:
	var path := _settings_path("ids")
	var screen := _screen(path)
	screen.set_preview(true)
	assert_true(screen.set_seats([WAKE, CROWN]))
	var texts := PackedStringArray([screen.preview_toggle.text, screen.preview_toggle.tooltip_text, screen.error_text()])
	for i in screen.seat_pickers.size():
		texts.append(screen.faction_labels[i].text)
		texts.append(screen.faction_labels[i].tooltip_text)
		for j in screen.seat_pickers[i].item_count:
			texts.append(screen.seat_pickers[i].get_item_text(j))
			texts.append(screen.seat_pickers[i].get_popup().get_item_tooltip(j))
	var text := "\n".join(texts)
	for raw in [WAKE, CROWN, CLANS, "crownkeep", "fangridge", "wickwardens", "lamplighter", ": ."]:
		assert_false(text.contains(raw), "no raw '%s' on the screen" % raw)
	screen.free()
	DirAccess.remove_absolute(path)


# --- the title -------------------------------------------------------------------------------------------------------

func test_the_title_hangs_a_preview_banner_only_with_the_box_ticked_and_its_art_in() -> void:
	assert_eq(TitleScreen.banner_factions(false), FactionData.playable(false), "the box clear: the shipped factions")
	var art_in := Art.banner(WAKE) != null
	assert_eq(TitleScreen.banner_factions(true).has(WAKE), art_in, "the box ticked: the Candlewake only once their art is in")
	var path := GameSettings.default_path
	var was := GameSettings.preview_factions_on(path)
	var key := Art.BANNER_PATH % WAKE
	var had_key := Art._cache.has(key)
	var cached = Art._cache.get(key)
	var stand_in := ImageTexture.create_from_image(Image.create(8, 20, false, Image.FORMAT_RGBA8))
	# Two banners hang where the scene has them.
	GameSettings.set_preview_factions(false, path)
	var title := load(TITLE_SCENE).instantiate() as TitleScreen
	title._bind()
	assert_true(title.get_node("KingdomBanner").visible and title.get_node("BeastsBanner").visible)
	for node_name in TitleScreen.BANNERS:  # TWO_BANNERS and TWO_BANNERS_Y are the scene's own numbers
		var scene_banner := title.get_node(node_name) as Control
		var fresh := (load(TITLE_SCENE).instantiate() as TitleScreen).get_node(node_name) as Control
		assert_true(_at(scene_banner, [fresh.anchor_left, fresh.anchor_right], [fresh.anchor_top, fresh.anchor_bottom, fresh.offset_top,
			fresh.offset_bottom]), "%s hangs where the scene hangs it" % node_name)
		fresh.get_parent().free()
	assert_true(_at(title.get_node("KingdomBanner"), TitleScreen.TWO_BANNERS[0], TitleScreen.TWO_BANNERS_Y), "the Crown's banner where the scene hangs it")
	assert_true(title.get_node_or_null(TitleScreen.banner_node_name(WAKE)) == null or not title.get_node(TitleScreen.banner_node_name(WAKE)).visible)
	# With the box ticked and art in (a stand-in here), three hang as a triptych, captioned with their names.
	GameSettings.set_preview_factions(true, path)
	Art._cache[key] = stand_in
	title.hang_banners()
	var wake_banner := title.get_node_or_null(TitleScreen.banner_node_name(WAKE)) as TextureRect
	assert_true(wake_banner != null and wake_banner.visible and wake_banner.texture == stand_in, "the Candlewake's banner hangs")
	if wake_banner != null:
		assert_eq((wake_banner.get_child(0) as Label).text, _wake_name())
	var order := TitleScreen.banner_factions(true)
	for i in order.size():
		var node := title.get_node(TitleScreen.banner_node_name(String(order[i]))) as TextureRect
		assert_true(_at(node, TitleScreen.THREE_BANNERS[i], TitleScreen.THREE_BANNERS_Y), "%s hangs in its third: %s" % [order[i],
			[node.anchor_left, node.anchor_right, node.anchor_top, node.anchor_bottom]])
	# A triptych: the same size, the Crown's and the Candlewake's side by side on the left flank, the Clans' on the right
	# (tests/test_screens_fit.gd measures them clear of the title and the menu at both sizes).
	var widths := TitleScreen.THREE_BANNERS.map(func(s): return snappedf(float(s[1]) - float(s[0]), 0.0001))
	assert_eq(widths, [widths[0], widths[0], widths[0]], "three banners of one size: %s" % [widths])
	assert_true(float(TitleScreen.THREE_BANNERS[0][1]) < float(TitleScreen.THREE_BANNERS[2][0]) and float(TitleScreen.THREE_BANNERS[2][1]) < 0.5
		and float(TitleScreen.THREE_BANNERS[1][0]) > 0.5, "two on the left, side by side, and one on the right")
	# The box cleared again: back to two, where they were.
	GameSettings.set_preview_factions(false, path)
	title.hang_banners()
	assert_false(wake_banner.visible, "the third comes down")
	assert_true(_at(title.get_node("BeastsBanner"), TitleScreen.TWO_BANNERS[1], TitleScreen.TWO_BANNERS_Y), "the Clans' banner back where the scene hangs it")
	assert_true(_at(title.get_node("KingdomBanner"), TitleScreen.TWO_BANNERS[0], TitleScreen.TWO_BANNERS_Y), "and the Crown's")
	title.free()
	if had_key:
		Art._cache[key] = cached
	else:
		Art._cache.erase(key)
	GameSettings.set_preview_factions(was, path)


## #285's hook for the box: the title's codex lists a faction's own entries only for the factions a new game can seat, so the
## Candlewake's rules (Wick first, the entry their box links) are listed while the box is ticked, and not while it is clear.
func test_the_titles_codex_lists_their_rules_while_the_box_is_ticked() -> void:
	var path := GameSettings.default_path
	var was := GameSettings.preview_factions_on(path)
	var folder := "user://test_three_faction_screens_codex_%d" % OS.get_process_id()
	var title := load(TITLE_SCENE).instantiate() as TitleScreen
	title.store = SaveStore.new(folder)
	(Engine.get_main_loop() as SceneTree).root.add_child(title)  # as tests/test_codex_panel.gd's panel (any API call binds it)
	GameSettings.set_preview_factions(false, path)
	title.open_codex()
	assert_eq(title.codex.factions, FactionData.playable(false), "the box clear: the finished factions")
	assert_false(title.codex.entry_keys().has(NewGameScreen.PREVIEW_CODEX), "no Candlewake rule")
	title.codex.visible = false  # closed, as its Close does
	GameSettings.set_preview_factions(true, path)
	title.open_codex(NewGameScreen.PREVIEW_CODEX)
	assert_eq(title.codex.factions, FactionData.playable(true), "the box ticked: the Candlewake too")
	assert_true(title.codex.entry_keys().has(NewGameScreen.PREVIEW_CODEX), "their rules are listed")
	assert_eq(title.codex.current_key(), NewGameScreen.PREVIEW_CODEX, "and the box's link opens at Wick")
	title.get_parent().remove_child(title)
	title.free()
	DirAccess.remove_absolute(folder)
	GameSettings.set_preview_factions(was, path)


# --- lookups that read every faction row -------------------------------------------------------------------------------

func test_the_art_report_and_victory_lookups_find_the_candlewake() -> void:
	var row := FactionData.row(WAKE)
	for u in row.unit_types:
		assert_eq(Art.unit_faction(String(u.id)), WAKE, "%s is theirs" % u.id)
		assert_eq(Art._unit_name(String(u.id)), String(u.name))
	assert_eq(Art.unit_faction(String(row.commander.id)), WAKE)
	assert_true(Art._is_commander(String(row.commander.id)))
	var first: Dictionary = row.unit_types[0]
	var e := {"type": "recruited", "factions": [WAKE], "text": "The %s recruited %s at the Long Vigil." % [_wake_name(), first.name]}
	assert_eq(TurnReportPanel.recruited_unit(e), String(first.id), "a recruit line finds its unit")
	assert_eq(VictoryScreen._faction_name(WAKE, null), _wake_name(), "a name without a state")


## CW-4's path and CW-5's magic wait in preview tables; the screens read them through the rules' lookups, so the report finds a
## Candlewake transformation's new unit in its recruit line (it raised a script error on a Candlewake game's report), the Oath's
## lock-in preview names the unit the other side would have brought, the research sidebar shows both roads, and the art finds
## their mage, their summons and their new units.
func test_the_report_the_path_screens_and_the_art_read_the_candlewakes_preview_tables() -> void:
	var sides := AscensionRules.branches_for(WAKE)
	assert_eq(sides.size(), 2, "the Candlewake's fork has two sides")
	var s := GameState.create(7, [WAKE, CROWN], {"rulers": true, "paths": true}, {}, [])
	assert_true(s != null, "a Candlewake game with paths")
	if s == null:
		return
	for side in sides:
		var trans := String(AscensionRules.branch_data(side).transformation)
		var new_id := String(AscensionRules.node_effects(trans).get("new_unit", ""))
		if not new_id.is_empty():
			var unit_name := String(AscensionRules.new_unit_data(new_id).name)
			var e := {"type": "recruited", "factions": [WAKE], "text": "The %s recruited %s at the Long Vigil." % [_wake_name(), unit_name]}
			assert_eq(TurnReportPanel.recruited_unit(e), new_id, "a recruit of %s finds its unit" % unit_name)
			assert_eq(Art.unit_faction(new_id), WAKE, "%s is theirs" % unit_name)
		var p := PathView.preview(s, WAKE, String(AscensionRules.branch_data(side).oath))
		assert_true(bool(p.get("ok", false)), "%s's Oath has its lock-in preview: %s" % [side, p.get("reason", "")])
		var other_trans := String(AscensionRules.branch_data(AscensionRules.other_branch(WAKE, side)).transformation)
		var other_new := String(AscensionRules.node_effects(other_trans).get("new_unit", ""))
		if not other_new.is_empty():
			var lost := " ".join(Array(p.get("lose", [])).map(func(l): return String(l.text)))
			assert_true(lost.contains(String(AscensionRules.new_unit_data(other_new).name)), "the side it closes names its new unit: %s" % lost)
	assert_eq(PathView.sidebar(s, WAKE).routes.size(), sides.size(), "the research sidebar shows the road to each side")
	var mage := String(MagicRules.mage_data(WAKE).get("id", ""))
	assert_false(mage.is_empty(), "they have a mage")
	assert_eq(Art.unit_faction(mage), WAKE, "their mage is theirs")
	for sid in MagicData.PREVIEW_SUMMONS:
		assert_eq(Art.unit_faction(String(sid)), String(MagicData.PREVIEW_SUMMONS[sid].get("faction", "")), "%s's faction" % sid)


# --- what the box and the seat lines say (CW-7: every new mechanic is explained) -------------------------------------------

func test_the_box_says_what_the_preview_is_and_what_isnt_built_yet_and_links_the_codex() -> void:
	var path := _settings_path("tooltip")
	var screen := _screen(path)
	var tip := String(screen.preview_toggle.tooltip_text).replace("\n", " ")  # as it reads, whatever the wrapping
	var row := FactionData.row(WAKE)
	assert_true(tip.begins_with(NewGameScreen.preview_label()), "titled with the box's words: %s" % tip)
	assert_true(tip.contains("still being built"), tip)
	for f in FactionData.FACTIONS:
		assert_true(tip.contains("the %s" % String(f.name)), "names %s as a faction to play them against" % f.name)
	assert_true(tip.contains(String(row.capital_name)), "the capital they take")
	for box in NewGameScreen.systems_not_ready(WAKE):
		assert_true(tip.contains(box), "names %s, a box they can't play yet" % box)
	assert_true(tip.contains("computer") and tip.contains("flame"), "the computer doesn't plan around their flame yet (CW-6): %s" % tip)
	assert_eq(tip.contains("their art"), Art.banner(WAKE) == null, "their art, while it is still coming")
	var drawn := NewGameScreen.quick_start_factions(true, NewGameScreen.default_systems()).has(WAKE)
	assert_eq(tip.contains("Quick start leaves them out"), not drawn, "Quick start seats them only once they play every system")
	assert_eq(tip.contains("Quick start may seat them"), drawn, "and the box says so once it may")
	assert_eq(NewGameScreen.not_built(CROWN), [], "nothing left to build for a finished faction")
	# Its codex line: a right-click (or F1) opens their own rule, and doesn't tick the box.
	assert_true(RulesCodex.ENTRIES.has(NewGameScreen.PREVIEW_CODEX), "a codex entry")
	assert_eq(String(screen.preview_toggle.get_meta(CodexLink.META, "")), NewGameScreen.PREVIEW_CODEX)
	assert_true(String(screen.preview_toggle.tooltip_text).ends_with(CodexLink.with_link("", NewGameScreen.PREVIEW_CODEX)),
		"the tooltip ends with its codex line")
	var opened := []
	screen.codex_requested.connect(func(key: String): opened.append(key))
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.pressed = true
	screen.preview_toggle.gui_input.emit(click)
	assert_eq(opened, [NewGameScreen.PREVIEW_CODEX], "a right-click on the box opens the codex there")
	assert_false(screen.preview_on(), "and leaves the box as it was")
	screen.free()
	DirAccess.remove_absolute(path)


func test_their_seat_line_says_what_the_preview_means_and_a_computer_seat_what_it_cant_do_yet() -> void:
	var path := _settings_path("lines")
	var screen := _screen(path)
	screen.set_preview(true)
	screen.set_all_systems(false)
	assert_true(screen.set_seats([CROWN, WAKE]))
	screen.set_seat_kind(1, "human")
	screen.set_seat_kind(2, "computer")
	var line := String(screen.faction_labels[1].text)
	assert_true(line.contains("A preview, still being built"), line)
	for box in NewGameScreen.systems_not_ready(WAKE):
		assert_true(line.contains(box), "'%s' names %s" % [line, box])
	var note := NewGameScreen.computer_preview_note(WAKE)
	assert_true(note.contains("flame") and line.contains(note), "the computer's seat says it doesn't plan around their flame yet: %s" % line)
	assert_false(String(screen.faction_labels[0].text).contains("preview"), "the Crown's line is as it was")
	assert_eq(NewGameScreen.computer_preview_note(CROWN), "", "nothing to say for a finished faction")
	screen.swap_seats()  # the Candlewake to the person's seat: no computer line for them
	assert_false(String(screen.faction_labels[0].text).contains(note), screen.faction_labels[0].text)
	screen.free()
	DirAccess.remove_absolute(path)


# --- a Candlewake game through the screens -------------------------------------------------------------------------------

const PLAYED_TURNS := 3


## The title as a player finds it, with saves of its own in `folder`.
func _title(folder: String) -> TitleScreen:
	var title := load(TITLE_SCENE).instantiate() as TitleScreen
	title.store = SaveStore.new(folder)
	title._bind()
	return title


## A person's orders: one of each unit at the capital, then the first march the session takes.
func _person_orders(session: GameSession) -> void:
	var state := session.state()
	var fid := session.current_player()
	for ut in state.find_faction(fid).unit_types:
		session.queue_recruit(ut.id)
	for a in state.armies:
		if a.owner == fid:
			for n in state.find_province(a.location).neighbors:
				if session.queue_move(a.id, n).is_empty():
					return


## `turns` more turns, the computer's seat played by the game's own AISeat.
func _play(game: GameScreen, turns: int) -> void:
	var session := game.session
	var goal := session.turns_played() + turns
	for guard in turns * 8:
		if session.turns_played() >= goal or session.is_over():
			return
		if session.phase() == GameSession.Phase.HANDOFF:
			session.acknowledge_handoff()
		elif session.is_computer_turn():
			game.computer.play(session)
		else:
			_person_orders(session)
			assert_eq(session.end_turn(), "", "the person's turn ends")


func _labels_text(node: Node) -> String:
	var out := PackedStringArray()
	if node is Label:
		out.append((node as Label).text)
	for c in node.get_children():
		out.append(_labels_text(c))
	return "\n".join(out)


## Through the real screens: the title's New game, the box ticked, `seats` seated with the person in seat 1 and the computer in
## seat 2, the systems they can't play yet unticked as the error line says (every other stays on), the person's build on the
## build screen (`build` when the person plays the Candlewake, the balanced preset otherwise), and the game; then PLAYED_TURNS
## turns, a save through the game's own Save, a load of it, and a rematch of it.
func _candlewake_game(seats: Array, build: Dictionary) -> void:
	var where := "%s in seat %d" % [_wake_name(), seats.find(WAKE) + 1]
	var folder := "user://test_three_faction_screens_game_%d_%d" % [OS.get_process_id(), seats.find(WAKE)]
	var title := _title(folder)
	title.new_game_button.pressed.emit()
	var setup := title.new_game_screen
	setup.preview_toggle.button_pressed = true  # as a click does
	assert_true(setup.preview_on() and GameSettings.preview_factions_on(), "%s: the box is ticked and remembered" % where)
	assert_true(setup.set_seats(seats), where)
	setup.set_seat_kind(1, "human")
	setup.set_seat_kind(2, "computer")
	setup.set_seed(4242)
	var unready := NewGameScreen.systems_not_ready(WAKE)
	assert_eq(setup.is_valid(), unready.is_empty(), "%s: with every box as it ships, Start waits for what they can't play yet" % where)
	for sys in NewGameScreen.SYSTEMS:  # untick those boxes, as the error line says
		if unready.has(String(sys.name)):
			setup.call("set_" + String(sys.key), false)
	assert_true(setup.is_valid(), "%s: %s" % [where, setup.error_text()])
	var playable := NewGameScreen.SYSTEMS.filter(func(sys): return not unready.has(String(sys.name))).map(func(sys): return String(sys.key))
	assert_eq(setup.systems_ticked(), playable, "%s: every system they can play stays on" % where)
	setup.start_button.pressed.emit()
	var b := setup.build_screen
	assert_true(b != null and b.visible, "%s: Start goes to the build screen" % where)
	if b == null:
		title.free()
		return
	var fid := String(seats[0])
	assert_eq(b.faction_id, fid, "%s: the person builds for their own faction" % where)
	if fid == WAKE:
		assert_true(_labels_text(b).contains(String(FactionData.row(WAKE).capital_name)), "%s: the build screen names the Long Vigil" % where)
		assert_true(b.select_ruler(String(build.ruler)), "%s: their ruler %s" % [where, build.ruler])
		b.clear_build()
		for m in build.mandates:
			assert_true(b.set_mandate(String(m), true), "%s: their mandate %s" % [where, m])
	var chosen := b.current_build()
	assert_true(b.lock_in(), "%s: the build locks in" % where)
	var game := title.next_scene as GameScreen
	assert_true(game != null, "%s: locking in starts the game" % where)
	if game == null:
		title.free()
		return
	game.autosave_enabled = false
	game.save_store = SaveStore.new(folder)
	var s := game.session.state()
	assert_eq(game.session.setup_errors(), [], where)
	assert_eq(game.session.players(), seats, "%s: the seats as picked" % where)
	var wake := s.find_faction(WAKE)
	assert_true(wake != null and s.find_province(wake.capital).name == String(FactionData.row(WAKE).capital_name),
		"%s: their capital is the Long Vigil" % where)
	assert_eq(s.find_faction(fid).ruler_type, String(chosen.ruler), "%s: the person's ruler" % where)
	assert_eq(s.find_faction(fid).mandates, Array(chosen.mandates), "%s: and mandates" % where)
	if fid == WAKE:
		assert_eq(chosen, build, "%s: the build picked on the screen" % where)
	_play(game, PLAYED_TURNS)
	assert_true(game.session.turns_played() >= PLAYED_TURNS and not game.session.is_over(), "%s: %d turns played" % [
		where, game.session.turns_played()])
	# Saved as the Save button saves (at the start of the turn), and loaded.
	game._snapshot = SaveGame.computer_snapshot(game.computer, game.session)
	assert_eq(game.save_game("Candlewake test"), "", "%s: the game saves" % where)
	var saves := SaveStore.new(folder).list().filter(func(e): return String(e.kind) == SaveGame.MANUAL)
	assert_eq(saves.size(), 1, "%s: one save" % where)
	if saves.size() == 1:
		var read := SaveStore.new(folder).read(String(saves[0].path))
		assert_eq(read.errors, [], where)
		var made := SceneFlow.make_loaded_game(read.save)
		assert_eq(made.error, "", "%s: the save loads" % where)
		var loaded := made.game as GameScreen
		if loaded:
			assert_eq(var_to_str(loaded.session.state().to_dict()), var_to_str(game.session.state().to_dict()), "%s: the same game" % where)
			assert_eq(loaded.session.players(), seats, where)
			# A rematch of it ticks the box and seats them again, wherever the box was left.
			var again := _screen(_settings_path("rematch_game"))
			assert_false(again.preview_on())
			again.prefill(loaded.config)
			assert_true(again.preview_on() and again.rematch_label.visible, "%s: the rematch ticks the box" % where)
			assert_eq([again.seat_faction(1), again.seat_faction(2)], seats, where)
			DirAccess.remove_absolute(again.settings_file)
			again.free()
			loaded.free()
	game.free()
	title.free()
	SaveStore.new(folder).clear()
	DirAccess.remove_absolute(folder)


func test_a_candlewake_game_through_the_screens_builds_starts_plays_saves_and_loads() -> void:
	var was := GameSettings.preview_factions_on()
	# The person plays the Candlewake against the computer's Crown, with the ruler their balanced preset doesn't pick and a
	# mandate of their own.
	var balanced := RulerRules.preset_build(RulerRules.balanced_preset(WAKE))
	var other := RulerRules.rulers_for(WAKE).filter(func(r): return r != balanced.ruler)
	var own := RulerRules.available_mandates(WAKE).filter(func(m): return String(RulerRules.mandate_data(String(m)).faction) == WAKE)
	assert_false(other.is_empty() or own.is_empty(), "they have a second ruler and a mandate of their own")
	if not other.is_empty() and not own.is_empty():
		_candlewake_game([WAKE, CROWN], {"ruler": String(other[0]), "mandates": [String(own[0])]})
	# The computer plays them against the person's Clans.
	_candlewake_game([CLANS, WAKE], {})
	GameSettings.set_preview_factions(was)


# --- the capital's name on its own, and the victory screen -----------------------------------------------------------

func test_their_capital_standing_alone_reads_the_long_vigil_with_a_capital() -> void:
	var s := GameState.create(5, [CROWN, WAKE], {}, {}, [])
	var cap := s.find_province(s.find_faction(WAKE).capital)
	var vigil := String(FactionData.row(WAKE).capital_name)
	assert_eq(cap.name, vigil, "in running text, as the row writes it")
	var heading := vigil.substr(0, 1).to_upper() + vigil.substr(1)
	var map: MapScreen = load("res://ui/map_screen.tscn").instantiate()
	map.set_state(s, WAKE)
	map.select_province(cap.id)
	var titles := map.details.find_children("ProvinceName", "", true, false)
	assert_false(titles.is_empty(), "the province card has its heading")
	if not titles.is_empty():
		assert_eq((titles[0] as Label).text, heading, "the card's heading")
	assert_eq((map.regions[cap.id] as ProvinceRegion).name_label.text, heading, "the 2D map's name plate")
	var crown_cap := s.find_province(s.find_faction(CROWN).capital)
	assert_eq((map.regions[crown_cap.id] as ProvinceRegion).name_label.text, crown_cap.name, "a name with its capital already is as it was")
	map.free()


## A Crown–Candlewake game whose only armies are `specs` ([id, owner, location, [unit ids]]), with `owners` holding those provinces.
func _wake_state(specs: Array, owners: Dictionary) -> GameState:
	var s := GameState.create(99, [CROWN, WAKE], {}, {}, [])
	s.armies.clear()
	for spec in specs:
		var a := Army.new()
		a.id = spec[0]
		a.owner = spec[1]
		a.location = spec[2]
		var f := s.find_faction(a.owner)
		for type_id in spec[3]:
			var ut := TurnResolver.recruitable_type(f, type_id)
			if ut.is_commander:
				a.commander = Unit.new(ut, f.id)
			else:
				a.units.append(Unit.new(ut, f.id))
		WickRules.light(s, a)
		s.armies.append(a)
	for pid in owners:
		s.find_province(pid).owner = owners[pid]
	return s


func _shown_text(node: Node) -> String:
	var out := PackedStringArray()
	if node is CanvasItem and not (node as CanvasItem).visible:
		return ""
	if node is Label or node is Button:
		out.append(String(node.text))
	if node is Control and not (node as Control).tooltip_text.is_empty():
		out.append((node as Control).tooltip_text)
	for c in node.get_children():
		out.append(_shown_text(c))
	return "\n".join(out)


func test_the_victory_screen_names_the_candlewake_and_the_long_vigil() -> void:
	var caps := FactionData.capitals_for([CROWN, WAKE])
	for winner in [CROWN, WAKE]:
		var loser := WAKE if winner == CROWN else CROWN
		var target := String(caps[loser])
		var s0 := GameState.create(99, [CROWN, WAKE], {}, {}, [])
		var start := String(s0.find_province(target).neighbors[0])
		var far := ""
		for p in s0.provinces:  # somewhere the loser's army can sit out the turn, out of the way
			if not p.is_capital and p.id != start and not s0.find_province(target).neighbors.has(p.id):
				far = p.id
				break
		var winner_row := FactionData.row(winner)
		var loser_row := FactionData.row(loser)
		var s := _wake_state([["%s-1" % winner, winner, start, [String(winner_row.unit_types[0].id), String(winner_row.commander.id)]],
			["%s-2" % loser, loser, far, [String(loser_row.unit_types[0].id)]]], {start: winner, far: loser})
		var session := GameSession.new(s, [CROWN, WAKE], 7, StubBattleResolver.new())
		assert_eq(session.setup_errors(), [], "%s's game starts" % winner)
		for fid in [CROWN, WAKE]:
			if fid == winner:
				assert_eq(session.queue_order(MoveOrder.new("%s-1" % winner, target)), "")
			assert_eq(session.end_turn(), "")
			if session.phase() == GameSession.Phase.HANDOFF:
				session.acknowledge_handoff()
		assert_true(session.is_over(), "%s walks into the empty capital and wins" % winner)
		var screen := load("res://ui/victory_screen.tscn").instantiate() as VictoryScreen
		assert_true(screen.show_for(session))
		var taken := session.state().find_province(target).name
		assert_eq(taken, s0.find_province(target).name)
		if loser == WAKE:
			assert_eq(taken, String(loser_row.capital_name), "the Candlewake's capital is the Long Vigil")
		assert_eq(screen.headline_label.text, "%s wins" % String(winner_row.name))
		assert_eq(screen.capture_labels().size(), 1)
		if not screen.capture_labels().is_empty():
			assert_eq(screen.capture_labels()[0].text, "%s captured %s, the %s capital." % [winner_row.name, taken, loser_row.name])
		assert_true(String(screen.summary_label.text).contains(taken), screen.summary_label.text)
		var text := _shown_text(screen)
		var raw := [CROWN, WAKE, String(caps[CROWN]), String(caps[WAKE])]
		for u in FactionData.row(WAKE).unit_types:
			raw.append(String(u.id))
		for id in raw:
			assert_false(text.contains(id), "%s's win: no raw '%s' on the victory screen" % [winner, id])
		screen.free()
