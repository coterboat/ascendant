extends SceneTree
## A screenshot walk of a whole game on the real screens: the title, the new game screen, the build screen,
## then a game against the computer where a second AIPlayer gives the person's orders through the session
## (the same OrderBook checks a click gets). At each step it saves a PNG, so a director or builder can see
## what a player sees before calling a change done. Dev tool only: it never runs in the game or the tests.
##
##   $GODOT --path . --resolution 1600x900 -s res://tools/shots/play_shots.gd -- --out=/abs/dir [options]
##
## Options (all optional):
##   --out=DIR          where the PNGs and walk.md go (default user://shots)
##   --seed=N           the game seed (default 4242)
##   --human=ID         the faction the bot plays for the person (default kingdom); the other seat is the computer
##   --turns=N          stop after N turns (default 40) or when the game ends
##   --every=K          a map shot every K turns, plus every turn with a battle the person fought (default 5)
##   --battles=N        watch up to N of the person's battles in the battle host, one shot each (default 3)
##   --rulers / --paths / --sieges / --fog / --magic / --independents   switch those systems on (paths turn rulers on;
##                      magic turns paths and rulers on, as the new game screen's box does)
##   --no-menus         skip the title, new game and build screen shots
##   --fresh            the walk's settings are DIR/settings.cfg, deleted first, instead of the player's own: no settings
##                      file, so the first-game guide shows (MVP-1, #141), and the player's file is never read or written
## With --magic the person's seat also walks #116's playtest through the real screens: on turn 1 it opens the
## research panel's Magic tab (a shot), researches its first spell and sets the battle spellbook (a shot); once the
## spell is known it opens the tab again (a shot) and recruits two mages (an orders shot that turn).
##   --fast             skip the board's playback on turns that get no shot
## Windowed only: headless has no renderer, so the shots would be blank. walk.md lists every shot with the
## turn report's headline lines, so the walk can be read without opening the images.

const W := 1600
const H := 900
var out := "user://shots"
var game_seed := 4242
var human := "kingdom"
var max_turns := 40
var every := 5
var max_battles := 3
var flags := {"rulers": false, "paths": false, "sieges": false, "fog": false, "magic": false, "independents": false}
var menus := true
var fast := false
var fresh := false
var walk: PackedStringArray = []
var shot_n := 0
var mages_queued := 0  # --magic: the mages the person's seat has recruited
var spell_seen := false  # --magic: the Magic tab was shot once the first spell was known


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=", true, 1)
		match kv[0]:
			"out": out = kv[1]
			"seed": game_seed = int(kv[1])
			"human": human = kv[1]
			"turns": max_turns = int(kv[1])
			"every": every = maxi(1, int(kv[1]))
			"battles": max_battles = int(kv[1])
			"no-menus": menus = false
			"fast": fast = true
			"fresh": fresh = true
			_:
				if flags.has(kv[0]):
					flags[kv[0]] = true
	if flags.magic:
		flags.paths = true  # M5-5: magic needs paths, and paths need rulers
	if flags.paths:
		flags.rulers = true
	DirAccess.make_dir_recursive_absolute(out)
	if fresh:
		GameSettings.default_path = out.path_join("settings.cfg")
		if FileAccess.file_exists(GameSettings.default_path):
			DirAccess.remove_absolute(GameSettings.default_path)
	# The window stays as launched: `--resolution WxH` (see the header) takes a walk at another size, 1280x720 for
	# instance (MVP-1, #141: every screen fits both), and without it the window is the project's default, W x H.
	print("window: ", DisplayServer.window_get_size(), " (default ", Vector2i(W, H), ")")
	# Without vsync the frame loop never waits on the display, so a window covered by other windows (macOS stops
	# its display link) still renders at full speed and the walk doesn't stall.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_run()


func _frames(n: int) -> void:
	for k in n:
		await process_frame


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _shot(name: String, note: String = "") -> void:
	await _frames(4)
	await RenderingServer.frame_post_draw
	shot_n += 1
	var file := "%02d_%s.png" % [shot_n, name]
	root.get_texture().get_image().save_png(out.path_join(file))
	walk.append("- **%s**%s" % [file, ("  \n  " + note.replace("\n", "  \n  ")) if note != "" else ""])
	print("shot ", file)


func _opponent() -> String:
	for f in FactionData.FACTIONS:
		if f.id != human:
			return f.id
	return ""


func _config() -> Dictionary:
	var foe := _opponent()
	var cfg := {"players": [human, foe], "seed": game_seed, "ai": {foe: "normal"}}
	if flags.rulers:
		cfg.rulers = true
		cfg.builds = {human: RulerRules.preset_build(RulerRules.balanced_preset(human)),
			foe: BuildScreen.computer_build(foe, game_seed, 1)}
	for k in ["paths", "sieges", "fog", "magic", "independents"]:
		if flags[k]:
			cfg[k] = true
	return cfg


func _run() -> void:
	await _frames(2)
	if menus:
		await _menus()
	var game: GameScreen = load("res://ui/game_screen.tscn").instantiate()
	game.autosave_enabled = false
	game.save_store = SaveStore.new(out.path_join("saves"))
	root.add_child(game)
	await _frames(2)
	game.start_game(_config())
	while not BattleStage3D.land_ready():
		await process_frame
	Board3D.terrain_now()
	await _wait(1.0)
	var brain := AIPlayer.new()
	var seat: int = game.session.players().find(human)
	brain.configure(game_seed, seat)
	var rng := SeededRNG.new(AISeat.seat_seed(game_seed + 1, seat))
	var watched := 0
	while not game.session.is_over() and game.session.turn_number() <= max_turns:
		var turn := game.session.turn_number()
		await _close_overlays(game)
		var magic_shot := false
		if flags.magic:
			magic_shot = await _magic_steps(game, turn)
		var orders: Array = brain.plan_orders(game.session.state(), human, rng, "normal")
		var refused := []
		for o in orders:
			if flags.magic and o is ResearchOrder and not MagicRules.knows_a_spell(game.session.state(), human):
				continue  # the person's seat researches its first spell (_magic_steps), not the computer's pick
			var why := game.session.queue_order(o)
			if why != "":
				refused.append(why)
		if game.map.has_method("_orders_changed"):
			game.map._orders_changed()
		var texts := game.session.current_order_texts()
		if turn == 1 or turn % every == 0 or magic_shot:
			await _shot("t%02d_orders" % turn, "Turn %d orders: %s%s" % [turn, "; ".join(texts),
				("\n  REFUSED: " + "; ".join(refused)) if not refused.is_empty() else ""])
		print("turn %d: end turn" % turn)
		game.end_turn()
		await _settle(game, fast and not (turn % every == 0 or turn + 1 == max_turns))
		print("turn %d: settled" % turn)
		var report := game.session.turn_report_for(human)
		var mine := BattleHost.battles_of(game.session.battle_events(), human)
		var lines := _headlines(report)
		if turn == 1 or turn % every == 0 or not mine.is_empty() or game.session.is_over():
			if not game.report_overlay.visible:
				game.open_turn_report()
			await _shot("t%02d_report" % turn, "Turn %d report: %s" % [turn, lines])
		if not mine.is_empty() and watched < max_battles:
			var why := game.watch_battles(mine, 0)
			if why == "":
				watched += 1
				await _wait(6.0)
				await _shot("t%02d_battle" % turn, "Battle watched: %s (view %s)" % [
					BattleHost.battle_title(mine[0]), game.battle_host.view_kind])
				await _wait(14.0)
				await _shot("t%02d_battle_end" % turn, "Same battle, later.")
				game.battle_host.close()
				print("turn %d: battle closed" % turn)
				await _frames(4)
			else:
				walk.append("- watch refused on turn %d: %s" % [turn, why])
	print("game loop done, over: ", game.session.is_over())
	if game.session.is_over():
		await _close_overlays(game)
		print("overlays closed")
		game.show_results()
		await _shot("victory", "Winner: %s after %d turns, %d battles." % [game.session.winner(),
			game.session.turns_played(), game.session.battles_fought()])
	else:
		walk.append("- stopped at the turn limit (%d) with no winner" % max_turns)
	_write_walk()
	quit()


## --magic: the person's seat walks #116's playtest through the real screens (see the header). Returns true on a turn
## whose orders should be shot (the mages were recruited).
func _magic_steps(game: GameScreen, turn: int) -> bool:
	var st := game.session.state()
	var hud := game.research_hud
	if turn == 1:
		hud.open_panel()
		hud.panel.show_magic()
		await _shot("t01_magic_tab", "The Magic tab on turn 1: the arcana, mastery and the battle spellbook.")
		var first := String(MagicRules.school_data(MagicRules.schools(human)[0]).nodes[0])
		var b: Button = hud.panel.buttons.get(first)
		if b != null:
			b.pressed.emit()
		var book := MagicView.spellbook(st, human, game.session.current_orders())
		var last := String(book.order.back())
		hud.panel._request_spellbook(MagicView.moved(book, last, -1))
		await _shot("t01_magic_tab_queued", "Researching %s; the spellbook changed: %s. Status: %s" % [MagicRules.spell_name(first),
			MagicRules.spellbook_text(MagicView.spellbook(st, human, game.session.current_orders()).order, []), hud.panel.status_label.text])
		hud.close_all()
		return false
	if not MagicRules.knows_a_spell(st, human):
		return false
	if not spell_seen:
		spell_seen = true
		hud.open_panel()
		hud.panel.show_magic()
		await _shot("t%02d_magic_tab_known" % turn, "The Magic tab once %s is known." % MagicRules.spell_name(MagicRules.known_spells(st, human)[0]))
		hud.close_all()
	var shot := false
	var mage := String(MagicRules.mage_data(human).id)
	while mages_queued < 2:
		var why: String = game.map.queue_recruit(mage)
		if why != "":
			walk.append("- turn %d: recruiting a mage refused: %s" % [turn, why])
			break
		mages_queued += 1
		shot = true
	return shot


func _menus() -> void:
	var title: Node = load("res://ui/title_screen.tscn").instantiate()
	root.add_child(title)
	await _wait(1.0)
	await _shot("title")
	title.queue_free()
	await _frames(2)
	var ng: NewGameScreen = load("res://ui/new_game_screen.tscn").instantiate()
	root.add_child(ng)
	await _frames(2)
	ng.set_seat_kind(2, "computer")
	ng.set_rulers(flags.rulers)
	ng.set_paths(flags.paths)
	ng.set_sieges(flags.sieges)
	ng.set_fog(flags.fog)
	ng.set_magic(flags.magic)
	ng.set_independents(flags.independents)
	await _shot("new_game", "Config: %s" % JSON.stringify(ng.config()))
	if flags.rulers:
		ng.start()
		await _frames(4)
		if ng.build_screen_open():
			await _shot("build_screen")
	ng.queue_free()
	await _frames(2)


## Waits for the board's playback after End turn: the game screen opens the turn report once the playback
## has finished (or at once without one), so the report showing is the signal. Gives up after 90 s.
func _settle(game: GameScreen, skip: bool = false) -> void:
	var start := Time.get_ticks_msec()
	while not game.report_overlay.visible and not game.session.is_over() and Time.get_ticks_msec() - start < 90000:
		if skip and game.map.board != null and game.map.board.has_method("skip_playback") and game.map.board.is_playing():
			game.map.board.skip_playback()
		await process_frame
	await _wait(0.5)


func _close_overlays(game: GameScreen) -> void:
	if game.battle_host.visible:
		game.battle_host.close()
	if game.report_overlay.visible:
		game.close_turn_report()
	await _frames(2)


## The report's first few lines, flattened to one string for walk.md.
func _headlines(report: Dictionary) -> String:
	var out_lines := []
	for key in ["header", "events"]:
		var v = report.get(key)
		if v is String and v != "":
			out_lines.append(v)
		elif v is Array:
			for e in v.slice(0, 8):
				out_lines.append(String(e.get("text", "")) if e is Dictionary else str(e))
	return " | ".join(out_lines.filter(func(s): return s != ""))


func _write_walk() -> void:
	var f := FileAccess.open(out.path_join("walk.md"), FileAccess.WRITE)
	f.store_string("# play_shots walk (seed %d, %s vs computer, %s)\n\n%s\n" % [game_seed, human,
		JSON.stringify(flags), "\n".join(walk)])
	f.close()
	print("walk written: ", out.path_join("walk.md"))
