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
##   --defaults         MVP-2 (#163): the game as a new player gets it: every system on, and the new game screen left exactly
##                      as it ships (no box touched), so the shot shows the defaults. Combine with --fresh.
##   --ui-scale=N       the interface size in percent, 100 or 125, as Settings' "Interface size" sets it (MVP-3, #177): the window
##                      stays as launched, so `--resolution 1600x900 --ui-scale=125` lays the screens out at 1280x720
##   --no-menus         skip the title, new game and build screen shots
##   --fresh            the walk's settings are DIR/settings.cfg, deleted first, instead of the player's own: no settings
##                      file, so the first-game guide shows (MVP-1, #141), and the player's file is never read or written
## With --magic the person's seat also walks #116's playtest through the real screens: on turn 1 it opens the
## research panel's Magic tab (a shot), researches its first spell and sets the battle spellbook (a shot); once the
## spell is known it opens the tab again (a shot) and recruits two mages (an orders shot that turn). M5-8 (#119): once a
## mage stands in an army it shoots that army's panel (the casters line), the Magic tab with its spellbook preview and, when
## the army can cast a ritual (Far Sight with --fog, or any ritual researched), the cast dialog, then orders the cast: that
## turn's report (a shot) has the rituals rows.
##   --fast             skip the board's playback on turns that get no shot
##   --board=2d         the 2D map instead of the 3D board (UX-2: the label diet and the veil on the flat map); default 3d
##   --stage            UX-2: on the last turn, after its orders shot, stage the VIEW the map shows (never the game) so every level of sight and every
##                      fort level is on the whole-map shot: one province you never saw is remembered, a palisade stands and another is
##                      being raised in your land, and a keep's walls are knocked down a step. Shot as tNN_fullmap_staged (needs --fullmap)
##   --split=N          UX-6: on turn N (after turn 1's recruits) the person's seat splits its biggest army in two before its other orders, so that
##                      turn's Chronicle shows ARM-1's muster entry (default: none)
##   --chronicle=MODE   UX-6: when the Chronicle opens by itself, whatever the player's settings say: important (the default), needs_you, always,
##                      never (the medallions only, to see them lit and unread) or report (today's modal report)
##   --fullmap          UX-2: after each orders shot, frame the whole map (the F key) and shoot it again as tNN_fullmap, then put the
##                      camera back, so the four veil looks and the three fort levels can be named without hovering
## Windowed only: headless has no renderer, so the shots would be blank. walk.md lists every shot with the
## turn report's headline lines, so the walk can be read without opening the images.

const Vision := preload("res://world3d/vision.gd")
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
var fullmap := false
var stage := false
var board_kind := "3d"
var split_turn := -1
var chronicle_mode := ""
var fresh := false
var defaults := false
var ui_scale := 100
var walk: PackedStringArray = []
var shot_n := 0
var mages_queued := 0  # --magic: the mages the person's seat has recruited
var spell_seen := false  # --magic: the Magic tab was shot once the first spell was known
var casters_seen := false  # --magic: the army panel and the spellbook preview were shot once a mage stood in an army
var cast_done := false  # --magic: the cast dialog was shot and a ritual ordered
var cast_turn := -1  # the turn that ritual was ordered: its report is shot


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
			"fullmap": fullmap = true
			"stage": stage = true
			"board": board_kind = kv[1]
			"split": split_turn = int(kv[1])
			"chronicle": chronicle_mode = kv[1]
			"fresh": fresh = true
			"defaults": defaults = true
			"ui-scale": ui_scale = int(kv[1])
			_:
				if flags.has(kv[0]):
					flags[kv[0]] = true
	if defaults:
		for k in flags:
			flags[k] = true
	if flags.magic:
		flags.paths = true  # M5-5: magic needs paths, and paths need rulers
	if flags.paths:
		flags.rulers = true
	DirAccess.make_dir_recursive_absolute(out)
	if fresh:
		GameSettings.default_path = out.path_join("settings.cfg")
		if FileAccess.file_exists(GameSettings.default_path):
			DirAccess.remove_absolute(GameSettings.default_path)
	if GameSettings.UI_SCALES.has(ui_scale) and ui_scale != 100:
		# As a player sets it in Settings: a saved ui_scale, which the title screen applies when it first appears (with no
		# [hints] in the file the first-game guide still shows). The scale goes on the root now too, for --no-menus.
		var saved := GameSettings.new(GameSettings.default_path if fresh else "")
		saved.set_ui_scale(ui_scale)
		if fresh:
			saved.save()
		root.content_scale_factor = ui_scale / 100.0
	# The window stays as launched: `--resolution WxH` (see the header) takes a walk at another size, 1280x720 for
	# instance (MVP-1, #141: every screen fits both), and without it the window is the project's default, W x H.
	print("window: ", DisplayServer.window_get_size(), " (default ", Vector2i(W, H), ")")
	# Without vsync the frame loop never waits on the display, so a window covered by other windows (macOS stops
	# its display link) still renders at full speed and the walk doesn't stall.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	# The walk drives the game through its API, never through input: a stray key or click from the real desktop (the window is
	# always on top) would press Continue on the title, or put a tooltip in a shot. (MVP-3, #177: a 125% walk loaded the
	# player's own autosave that way.)
	root.gui_disable_input = true
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
	if ChronicleModel.AUTO_OPEN.has(chronicle_mode):
		ChronicleSettings.default_auto_open = chronicle_mode
	var game: GameScreen = load("res://ui/game_screen.tscn").instantiate()
	game.autosave_enabled = false
	game.save_store = SaveStore.new(out.path_join("saves"))
	root.add_child(game)
	await _frames(2)
	game.start_game(_config())
	if board_kind != "3d":
		game.use_board(board_kind)
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
		if turn == split_turn:
			_queue_split(game)
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
			if fullmap:
				await _fullmap_shot(game, "t%02d_fullmap" % turn, "Turn %d, the whole map framed (F): veil looks and forts at full zoom." % turn)
				if stage and turn == max_turns:
					var staged := _stage_view(game)
					await _fullmap_shot(game, "t%02d_fullmap_staged" % turn, "Turn %d, the whole map framed, the view staged: %s" % [turn, staged])
		print("turn %d: end turn" % turn)
		game.end_turn()
		await _settle(game, fast and not (turn % every == 0 or turn + 1 == max_turns))
		print("turn %d: settled" % turn)
		await _chronicle_shot(game, turn)
		var report := game.session.turn_report_for(human)
		var mine := BattleHost.battles_of(game.session.battle_events(), human)
		var lines := _headlines(report)
		if turn == 1 or turn % every == 0 or not mine.is_empty() or game.session.is_over() or turn == cast_turn:
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
	await _magic_casters(game, turn)
	return shot


## M5-8: a mage stands in an army of the person's seat: its panel (the casters line), the Magic tab (the spellbook preview) and,
## when the army can cast a ritual, the cast dialog (a shot) and the cast, ordered for this turn.
func _magic_casters(game: GameScreen, turn: int) -> void:
	var st := game.session.state()
	var army: Army = null
	for a in st.armies:
		if a.owner == human and a.ruler == null and a.units.any(func(u): return MagicRules.is_mage(u.type)):
			army = a
			break
	if army == null:
		return
	if not casters_seen:
		casters_seen = true
		game.map.select_province(army.location)
		await _shot("t%02d_army_casters" % turn, "The army with the mages: the casters line and each spell with its number.")
		game.research_hud.open_panel()
		game.research_hud.panel.show_magic()
		await _shot("t%02d_magic_tab_spellbook" % turn, "The Magic tab with the spellbook previewed for each army that holds a caster.")
		game.research_hud.close_all()
	if cast_done:
		return
	for o in game.map.orders.cast_options(army.id):
		if not bool(o.ok):
			continue
		game.map.open_cast_dialog(army.id, String(o.ritual))
		await _wait(0.8)  # the board eases the lit provinces in
		await _shot("t%02d_cast_dialog" % turn, "The cast dialog for %s: targets lit on the board, the forecast, the risk, the budget." % MagicRules.spell_name(String(o.ritual)))
		game.map.cast_dialog.confirm()
		cast_done = true
		cast_turn = turn
		walk.append("- turn %d: ordered %s from the army at %s" % [turn, MagicRules.spell_name(String(o.ritual)), army.location])
		return


## UX-2 (--stage): stages the VIEW the map shows, not the game: a province you never saw is remembered (out of sight), a palisade
## stands in your land, another is being raised, and a keep's walls are knocked down a step, so the whole-map shot holds all four levels
## of sight and all three fort levels with whole and damaged walls. Returns what it did, for the walk.
func _stage_view(game: GameScreen) -> String:
	var map = game.map
	var st: GameState = map.state.deep_copy() ## a copy: the board stands a new state object, and the game's own is never touched
	var notes := []
	var memory: Dictionary = map.fog_memory
	var levels := Vision.levels(st, human, memory)
	for p in st.provinces:
		if String(levels.get(p.id, "")) == FogView.NEVER and not p.is_capital:
			if not memory.has("provinces"):
				memory["provinces"] = {}
			memory["provinces"][p.id] = {"seen_turn": 1}
			notes.append("%s remembered" % p.name)
			break
	var raised := 0
	for p in st.provinces:
		if p.owner != human or p.is_capital or p.fort_level > 0 or not p.works.is_empty() or raised >= 2:
			continue
		if raised == 0:
			p.fort_level = 1
			p.has_fort = true
			p.walls = SiegeRules.walls_max(1)
			notes.append("a palisade at %s" % p.name)
		else:
			p.works = {"to": 1, "left": 1}
			notes.append("a palisade being raised at %s" % p.name)
		raised += 1
	var keep: Province = null
	for p in st.provinces:
		if p.fort_level == 2 and p.walls == SiegeRules.walls_max(2):
			if keep == null or not st.armies.any(func(a): return a.location == p.id): ## a keep with nobody's plate over it, if there is one
				keep = p
				if not st.armies.any(func(a): return a.location == p.id):
					break
	if keep != null:
		keep.walls = maxi(1, keep.walls - FortData.WALL_STEP)
		notes.append("%s's keep damaged (walls %d of %d)" % [keep.name, keep.walls, SiegeRules.walls_max(2)])
	map.set_state(st, map.viewing_faction_id)
	return "; ".join(notes)


## UX-2: the whole map framed as the F key does, shot, and the camera put back where it was. The glide takes a moment.
func _fullmap_shot(game: GameScreen, name: String, note: String) -> void:
	var b = game.map.board
	if b == null or not b.has_method("fit_whole") or not b.get("prepared"):
		return
	var was: Dictionary = (b.goal as Dictionary).duplicate()
	var was_zoom: float = b.zoom
	b.fit_whole()
	await _wait(1.6)
	await _shot(name, note)
	b.goal = was
	b.zoom = was_zoom
	await _wait(1.0)


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
	if not defaults:  # --defaults leaves every box as the screen ships it
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


## Waits for the board's playback after End turn: the report host hears the turn's report is ready once the playback has finished (or
## at once without one) (UX-6: the Chronicle presents it; the modal opens only on request). Gives up after 90 s.
func _settle(game: GameScreen, skip: bool = false) -> void:
	var start := Time.get_ticks_msec()
	while game.report_host.last_ready < game.session.turns_played() and not game.session.is_over() and Time.get_ticks_msec() - start < 90000:
		if skip and game.map.board != null and game.map.board.has_method("skip_playback") and game.map.board.is_playing():
			game.map.board.skip_playback()
		await process_frame
	await _wait(0.5)


func _close_overlays(game: GameScreen) -> void:
	if game.chronicle_hud != null:
		game.chronicle_hud.close()
	if game.battle_host.visible:
		game.battle_host.close()
	if game.report_overlay.visible:
		game.close_turn_report()
	await _frames(2)


## UX-6: the Chronicle at the start of a turn: how it came up by itself (a shot of the table as the player finds it), then, with a map
## shot every few turns or whenever something important happened, the column open at its first card.
func _chronicle_shot(game: GameScreen, turn: int) -> void:
	var hud := game.chronicle_hud
	if hud == null or game.session.is_over():
		return
	var important := hud.announcements.filter(func(it): return it.important)
	var note := "Turn %d begins: %d announcements (%d notable, %d important); the column %s by itself; %d unread." % [turn, hud.announcements.size(),
		ChronicleModel.notable(hud.items()).size(), important.size(), "opened" if hud.is_open() else "stayed shut", hud.unread_count()]
	if turn == 1 or turn % every == 0 or not important.is_empty() or turn == split_turn:
		await _shot("t%02d_start" % turn, note)
		if not hud.is_open():
			hud.open()
			await _shot("t%02d_chronicle" % turn, "Turn %d: the Chronicle opened from its button. Headlines: %s" % [turn, " | ".join(hud.items().map(func(it): return String(it.headline)).slice(0, 8))])
		else:
			walk.append("  headlines: %s" % " | ".join(hud.items().map(func(it): return String(it.headline)).slice(0, 8)))
		hud.close()


## --split: the person's seat splits its biggest army (the units after the first half form a new one).
func _queue_split(game: GameScreen) -> void:
	var st := game.session.state()
	var best: Army = null
	for a in st.armies:
		if a.owner == human and a.ruler == null and a.units.size() >= 2 and (best == null or a.units.size() > best.units.size()):
			best = a
	if best == null:
		walk.append("- turn %d: nothing to split" % split_turn)
		return
	var indices := []
	for i in range(best.units.size() / 2, best.units.size()):
		indices.append(i)
	var why: String = game.session.queue_order(MusterOrder.transfer(best.id, "", indices))
	walk.append("- turn %d: split %s%s" % [split_turn, best.id, (" REFUSED: " + why) if why != "" else ""])


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
	f.store_string("# play_shots walk (seed %d, %s vs computer, %s; window %s, interface %d%%: the screens are laid out at %s)\n\n%s\n" % [game_seed,
		human, JSON.stringify(flags), DisplayServer.window_get_size(), int(root.content_scale_factor * 100.0 + 0.5),
		root.get_visible_rect().size, "\n".join(walk)])
	f.close()
	print("walk written: ", out.path_join("walk.md"))
