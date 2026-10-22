extends "res://tests/test_case.gd"
## #285 (QA): a faction's own codex entries are listed only in a game that seats it. In a default game (the Crown against the
## Clans, the Candlewake still behind their preview) the codex holds no Candlewake rule; in a game that seats them, all of
## theirs; shared entries always. The title's codex lists what a new game can seat.

const PANEL_SCENE := "res://ui/codex_panel.tscn"
const CROWN := "kingdom"
const CLANS := "beasts"
const WAKE := "candlewake"


func _panel():
	var panel = load(PANEL_SCENE).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(panel)
	panel.entry_keys()
	return panel


func _free(panel) -> void:
	panel.get_parent().remove_child(panel)
	panel.free()


func _theirs() -> Array:
	return RulesCodex.ENTRIES.keys().filter(func(k): return RulesCodex.entry_faction(String(k)) == WAKE)


func test_the_candlewakes_entries_are_theirs() -> void:
	assert_false(_theirs().is_empty())
	for key in ["wick", "harbour", "guttering", "ruler_half_death", "ruler_mother_tallow", "trait_pall", "unit_guttering_ram"]:
		assert_eq(RulesCodex.entry_faction(key), WAKE, key)
	for key in RulesCodex.ENTRIES:
		var e: Dictionary = RulesCodex.ENTRIES[key]
		if RulesCodex.entry_faction(String(key)).is_empty():
			assert_false((String(e.title) + " " + String(e.text)).contains("Candlewake"), "%s is shared but speaks of the Candlewake" % key)
	assert_true(RulesCodex.shown_for("move", [CROWN, CLANS]), "a shared entry shows everywhere")
	assert_false(RulesCodex.shown_for("wick", [CROWN, CLANS]))
	assert_true(RulesCodex.shown_for("wick", [CROWN, WAKE]))


func test_a_default_codex_holds_no_candlewake_rule_and_a_candlewake_game_holds_them_all() -> void:
	var panel = _panel()
	for key in _theirs():
		assert_false(panel.entry_keys().has(key), "%s stays out of a codex without the Candlewake" % key)
	assert_eq(panel.filter("Wick"), panel.listed_keys().size())
	assert_false(panel.listed_keys().has("wick"), "searching finds no Wick either")
	panel.set_factions([CROWN, WAKE])
	for key in _theirs():
		assert_true(panel.entry_keys().has(key), "%s is listed in a game with the Candlewake" % key)
	assert_true(panel.listed_keys().has("wick"), "the search refreshes with the factions")
	_free(panel)


func test_the_game_screen_gives_the_codex_its_factions() -> void:
	var game := load("res://ui/game_screen.tscn").instantiate() as GameScreen
	game.autosave_enabled = false
	game.start_game({"players": [CROWN, CLANS], "seed": 4242, "ai": {CLANS: "normal"}})
	game.open_codex()
	assert_eq(game.codex.factions, [CROWN, CLANS])
	assert_false(game.codex.entry_keys().has("wick"))
	game.free()
