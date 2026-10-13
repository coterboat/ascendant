extends SceneTree
## UI-ICONS (#233): screenshots of the magic art on screen: the Magic tab (the arcana and the battle spellbook with its preview) for
## each faction, an army card for each mage and summon (the Adepts, the Shamans, the Thornwolves, the Greenwrath), and a spell's
## codex page. A built game, so every new unit is on the board at once (a walk would need many turns, and the summons a ritual). Dev
## tool only.
##
##   $GODOT --path . --resolution 1600x900 --always-on-top -s res://tools/shots/magic_shots.gd -- --out=/abs/dir [--ui-scale=125]
##
## The game: the Crown (the Regent's Court) against the Clans (the Fang Chieftain with Tithe of Blood), each with its first four
## arcana known; the Crown's army of Spearmen and Adepts at Highcrag, the Clans' army of Tuskers and Shamans at Thornvale, and their
## summoned Thornwolves and Greenwrath at Bloodfen. Hotseat, the Crown at the controls; no fog, so every army's card shows its units.

const Mx := preload("res://tests/magic_battle_fixtures.gd")
const CROWN := "kingdom"
const CLANS := "beasts"
var out := "user://magic_shots"
var ui_scale := 100
var lines: PackedStringArray = []
var shot_n := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=", true, 1)
		match kv[0]:
			"out": out = kv[1]
			"ui-scale": ui_scale = int(kv[1])
	DirAccess.make_dir_recursive_absolute(out)
	GameSettings.default_path = out.path_join("settings.cfg")
	if FileAccess.file_exists(GameSettings.default_path):
		DirAccess.remove_absolute(GameSettings.default_path)
	GameSettings.mark_hint_seen(GameSettings.HINT_FIRST_GAME)  # no first-game guide over the cards
	if GameSettings.UI_SCALES.has(ui_scale):
		root.content_scale_factor = ui_scale / 100.0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.gui_disable_input = true
	_run()


func _state() -> GameState:
	var s := GameState.with_magic(9, {CROWN: "regents_court", CLANS: {"ruler": "fang_chieftain", "mandates": ["tithe_of_blood"]}})
	s = AscensionRules.with_nodes(s, CLANS, ["bloodbolt", "bloodrot", "briar_snare", "call_the_pack"])
	s = AscensionRules.with_nodes(s, CROWN, ["sunlance", "shield_of_law", "sanctum_ward", "dawn_blessing"])
	for f in s.factions:
		f.gold = 200
	Mx.army(s, CROWN, s.new_army_id(CROWN), "highcrag", ["spearmen", "spearmen", "spearmen", "adepts", "adepts"])
	Mx.army(s, CLANS, s.new_army_id(CLANS), "thornvale", ["tuskers", "tuskers", "tuskers", "shamans", "shamans"])
	Mx.army(s, CLANS, s.new_army_id(CLANS), "bloodfen", ["thornwolves", "thornwolves", "greenwrath"])
	for pid in ["highcrag"]:
		s.find_province(pid).owner = CROWN
	for pid in ["thornvale", "bloodfen"]:
		s.find_province(pid).owner = CLANS
	return s


func _run() -> void:
	await _frames(2)
	var s := _state()
	var session := GameSession.new(s, [CROWN, CLANS], 9, AutoBattleResolver.new())
	var game: GameScreen = load("res://ui/game_screen.tscn").instantiate()
	game.autosave_enabled = false
	game.save_store = SaveStore.new(out.path_join("saves"))
	root.add_child(game)
	await _frames(2)
	var why := game.load_game(SaveGame.make(session, {}, SaveGame.MANUAL, "Magic shots", 0))
	if not why.is_empty():
		push_error("magic_shots: " + why)
		quit(1)
		return
	if game.handoff.visible:
		game.handoff.ready_button.pressed.emit()
	if game.notice_panel.visible:
		game.notice_ok.pressed.emit()  # "Game loaded": not what these shots are about
	while not BattleStage3D.land_ready():
		await process_frame
	await _wait(2.0)
	lines.append("# magic_shots (window %s, interface %d%%: laid out at %s)" % [DisplayServer.window_get_size(), ui_scale, root.get_visible_rect().size])
	# The Magic tab (the arcana, the spellbook, its preview), the Crown's.
	game.research_hud.open_panel()
	game.research_hud.panel.show_magic()
	await _shot("magic_tab_crown", "The Crown's Magic tab: the arcana cards, the battle spellbook and what the Adepts' army will cast.")
	game.research_hud.close_all()
	# An army card for each new unit.
	for pair in [["highcrag", "the Crown's army with Adepts"], ["thornvale", "the Clans' army with Shamans"], ["bloodfen", "the Clans' summoned Thornwolves and Greenwrath"]]:
		var army := ""
		for a in game.session.state().armies:
			if a.location == pair[0] and a.ruler == null:
				army = a.id
		game.map.select_army(army)
		await _wait(0.6)
		await _shot("army_%s" % pair[0], "The army card: %s, each unit with its portrait." % pair[1])
	# A spell's codex page, and the cast dialog of the Crown's army.
	game.open_codex("spell_sunlance")
	await _wait(0.3)
	await _shot("codex_sunlance", "Sunlance's codex page (the list shows every spell's icon).")
	if game.codex != null:
		game.codex.close()
	var crown_army := ""
	for a in game.session.state().armies:
		if a.owner == CROWN and a.location == "highcrag" and a.ruler == null:
			crown_army = a.id
	game.map.open_cast_dialog(crown_army)
	await _wait(0.8)
	await _shot("cast_dialog", "The cast dialog of the Adepts' army: each ritual with its icon.")
	var f := FileAccess.open(out.path_join("shots.md"), FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit()


func _frames(n: int) -> void:
	for k in n:
		await process_frame


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _shot(name: String, note: String) -> void:
	await _frames(4)
	await RenderingServer.frame_post_draw
	shot_n += 1
	var file := "%02d_%s.png" % [shot_n, name]
	root.get_texture().get_image().save_png(out.path_join(file))
	lines.append("- **%s**  \n  %s" % [file, note])
	print("shot ", file)
