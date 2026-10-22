extends "res://tests/test_case.gd"
## CW-7 (#258, design/CANDLEWAKE.md §1, §12): the screens for three factions in two seats. The new game screen's "Candlewake
## (preview)" box (off by default, remembered in the settings file) lets either seat pick them; the same faction can't sit
## twice; a faction that can't play a ticked system yet says so in plain words and disables Start; each seat's line names
## its capital, the Candlewake's as the Long Vigil and which map capital it is this game; a rematch of a Candlewake game
## ticks the box again. The title hangs a preview faction's banner only with the box ticked and its art in, three as a
## triptych. The art, report and victory lookups find the Candlewake's units and name.
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


## Whether a banner hangs at `spot` ([left anchor, right anchor]; anchors are single-precision floats).
func _at(banner: Control, spot: Array) -> bool:
	return is_equal_approx(banner.anchor_left, float(spot[0])) and is_equal_approx(banner.anchor_right, float(spot[1]))


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
	assert_true(_at(title.get_node("KingdomBanner"), TitleScreen.TWO_BANNERS[0]), "the Crown's banner where the scene hangs it")
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
		assert_true(_at(node, TitleScreen.THREE_BANNERS[i]), "%s hangs in its third: %s" % [order[i], [node.anchor_left, node.anchor_right]])
	# The box cleared again: back to two, where they were.
	GameSettings.set_preview_factions(false, path)
	title.hang_banners()
	assert_false(wake_banner.visible, "the third comes down")
	assert_true(_at(title.get_node("BeastsBanner"), TitleScreen.TWO_BANNERS[1]), "the Clans' banner back where the scene hangs it")
	title.free()
	if had_key:
		Art._cache[key] = cached
	else:
		Art._cache.erase(key)
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
	var roster := BattleLayout._roster(WAKE)
	assert_eq(roster.size(), row.unit_types.size() + 1, "a battle's roster order has their units and commander")
