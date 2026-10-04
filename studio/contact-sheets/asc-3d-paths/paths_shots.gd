extends SceneTree
## The evidence driver of batch asc-3d-paths (from #91's board_shots.gd): a paths game on the 3D board with
## each faction's transformation researched and its new units mustered, the changed units drawn in their
## transformation look (the row's "variants" entry merged over the row in memory here: the board has no
## code for it yet), screenshots of both capitals at several zooms, the fortress close-ups, the field
## armies, and a battle's playback. Kept with the screenshots it made (studio/ is ignored by Godot).
##   $GODOT --path . --always-on-top --resolution 1600x900 -s <absolute path to this file> -- --out=DIR --fork=a|b [--novariants]
## fork a: Celestial Host + Thorn Wild; fork b: Living Iron + Blood Pact. --always-on-top matters: a covered
## window on macOS stops presenting, and every later capture repeats the last frame.

const CROWN := "kingdom"
const CLANS := "beasts"
const Models := preload("res://world3d/models.gd")

var out := ""
var opts := {}
var game: GameScreen
var board: Board3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv := a.substr(2).split("=", true, 1)
			opts[kv[0]] = kv[1]
		elif a.begins_with("--"):
			opts[a.substr(2)] = true
	out = str(opts.get("out", "/tmp/a3p"))
	DirAccess.make_dir_recursive_absolute(out)
	change_scene_to_file("res://ui/title_screen.tscn")
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	var img: Image = root.get_texture().get_image()
	img.save_png(out.path_join(name + ".png"))
	print("shot ", name, " ", img.get_size())


func _away() -> void:
	var w := root.get_final_transform() * Vector2(1205, 895)
	Input.warp_mouse(w)
	var e := InputEventMouseMotion.new()
	e.position = w
	e.global_position = w
	Input.parse_input_event(e)
	await _frames(2)


## Nothing may cover the board (a handoff, an overlay), or it stops rendering and keeps its last frame.
func _uncover() -> void:
	for i in 10:
		if game.handoff.visible:
			game.handoff.ready_button.pressed.emit()
		var top = game._top_overlay()
		if top == null and not game.handoff.visible:
			return
		if top != null:
			print("closing overlay ", top.name)
			top.visible = false
		await process_frame


func _look(at: Vector2, z: float, name: String, wait := 70, pitch := -1.0) -> void:
	await _uncover()
	if game.map.board != board:
		print("the board was rebuilt: following the new one")
		board = game.map.board
	print("covered ", game._board_covered(), " in tree ", board.is_inside_tree(), " visible ", board.is_visible_in_tree())
	await _away()
	## the map's own camera moves (a selection's glide) can land during the wait: hold the rig every frame
	## set the goal each frame without snapping: the board eases to it and redraws while it moves
	for i in wait + 60:
		board.zoom = z
		board.goal = board.rig_for(at, z)
		if pitch > 0.0:
			board.goal["pitch"] = pitch
		await process_frame
	print(name, " zoom ", board.zoom, " goal span ", board.goal.get("span"), " rig span ", board.wv.rig.get("span"), " pitch ", board.wv.rig.get("pitch"))
	await _shot(name)


func _fork() -> Dictionary:
	if str(opts.get("fork", "a")) == "b":
		return {CROWN: {"oath": "crown_oath_forge", "trans": "crown_living_iron", "changed": "knights", "new": "iron_colossus"},
			CLANS: {"oath": "beasts_oath_blood", "trans": "beasts_blood_pact", "changed": "tuskers", "new": "bloodsworn"}}
	return {CROWN: {"oath": "crown_oath_dawn", "trans": "crown_celestial_host", "changed": "spearmen", "new": "seraphs"},
		CLANS: {"oath": "beasts_oath_grove", "trans": "beasts_thorn_wild", "changed": "fangthrowers", "new": "briarwardens"}}


## The changed units' rows drawn in their transformation look (what the board will do when it swaps).
func _swap_variants(fork: Dictionary) -> void:
	## the boot bake (World3DLaunch) loads the table's meshes on a worker: let it finish, never block on it
	var guard := 0
	while Board3D._task >= 0 and not WorkerThreadPool.is_task_completed(Board3D._task) and guard < 600:
		await process_frame
		guard += 1
	print("bake done after ", guard, " frames")
	var tb := Models.table()
	for fid in fork:
		var base := String(fork[fid]["changed"])
		var row: Dictionary = (tb["figures"][base] as Dictionary).duplicate(true)
		var v: Dictionary = row.get("variants", {}).get(fork[fid]["trans"], {})
		if v.is_empty():
			print("no variant row for ", base)
			continue
		for k in v:
			row[k] = v[k]
		tb["figures"][base] = row
		print("swapped ", base, " -> ", fork[fid]["trans"])
	Models._meshes.clear()


func _unit(s: GameState, fid: String, type_id: String) -> Unit:
	var f := s.find_faction(fid)
	return Unit.new(TurnResolver.recruitable_type(f, type_id), fid)


func _army(s: GameState, fid: String, pid: String, counts: Dictionary) -> Army:
	var a := Army.new()
	a.id = s.new_army_id(fid)
	a.owner = fid
	a.location = pid
	for t in counts:
		for i in int(counts[t]):
			a.units.append(_unit(s, fid, t))
	s.armies.append(a)
	return a


func _state(fork: Dictionary) -> GameState:
	var errors := []
	var s := GameState.with_paths(21, {}, errors)
	for fid in fork:
		var tier1 := AscensionRules.node_ids(fid).filter(func(n): return AscensionRules.node_kind(n) == PathData.TIER1)
		s = AscensionRules.with_nodes(s, fid, tier1 + [fork[fid]["oath"], fork[fid]["trans"]])
	var c: Dictionary = fork[CROWN]
	var b: Dictionary = fork[CLANS]
	## the yards: each capital's army gets the fork's units
	var yard := {CROWN: {c["changed"]: 3, c["new"]: 3, "crossbowmen": 2},
		CLANS: {b["changed"]: 3, b["new"]: 3, ("tuskers" if b["changed"] != "tuskers" else "fangthrowers"): 2}}
	## the yard's recruits join each capital's army (a ruler travels alone, M2 §1.5: not the ruler's)
	var caps := {CROWN: "crownkeep", CLANS: "fangridge"}
	for fid in caps:
		var host: Army = null
		for a in s.armies:
			if a.owner == fid and a.location == caps[fid] and a.ruler == null:
				host = a
				break
		if host == null:
			_army(s, fid, caps[fid], yard[fid])
			continue
		for ty in yard[fid]:
			for i in int(yard[fid][ty]):
				host.units.append(_unit(s, fid, ty))
	## field armies face to face across the Rivermarch / Greenglade border
	_army(s, CROWN, "rivermarch", {c["new"]: 5, c["changed"]: 5})
	_army(s, CLANS, "greenglade", {b["new"]: 5, b["changed"]: 5})
	print("state errors ", errors)
	return s


func _run() -> void:
	await _frames(30)
	var title := current_scene as TitleScreen
	var fork := _fork()
	if not opts.has("novariants"):
		await _swap_variants(fork)
	var s := _state(fork)
	game = load("res://ui/game_screen.tscn").instantiate() as GameScreen
	var cfg := {"players": [CROWN, CLANS], "seed": 21, "paths": true}
	game.start_game(cfg)
	var session := GameSession.new(s, [CROWN, CLANS], 21)
	var save := SaveGame.make(session, {}, "manual", "shots", 0)
	print("load ", game.load_game(save))
	SceneFlow.switch(title, game)
	await _frames(5)
	board = game.map.board
	var guard := 0
	while (board == null or not board.prepared) and guard < 4000:
		await process_frame
		board = game.map.board
		guard += 1
	print("board ready after ", guard, " frames")
	if game.handoff.visible:
		game.handoff.ready_button.pressed.emit()
	game.close_turn_report()
	game.notice_panel.visible = false
	await _frames(30)
	var t = board.wv.terrain
	var tag := str(opts.get("fork", "a"))
	await _look(t.centre_of("rivermarch").lerp(t.centre_of("greenglade"), 0.5), 0.3, "%s_01_wide" % tag, 60)
	for cap in ["crownkeep", "fangridge"]:
		var c: Vector2 = t.centre_of(cap)
		await _look(c + Vector2(0, 4), 0.5, "%s_02_%s_default" % [tag, cap])
		await _look(c + Vector2(0, 4), 0.8, "%s_03_%s_close" % [tag, cap])
		await _look(c + Vector2(0, 4), 1.0, "%s_04_%s_closest" % [tag, cap])
	## the fortress close-up (View fortress): the yard at true stage scale
	for cap in ["crownkeep", "fangridge"]:
		await _uncover()
		board.enter_closeup(cap)
		for i in 150:
			await process_frame
		await _shot("%s_04b_%s_fortress_closeup" % [tag, cap])
		board.exit_closeup(true)
		for i in 30:
			await process_frame
	for pid in ["rivermarch", "greenglade"]:
		var p: Vector2 = t.centre_of(pid)
		await _look(p + Vector2(0, 4), 0.5, "%s_05_%s_default" % [tag, pid])
		await _look(p + Vector2(0, 4), 0.95, "%s_06_%s_close" % [tag, pid])
	## a battle: the Crown's field army marches into Greenglade
	var st: GameState = game.map.state
	for a in st.armies:
		if a.owner == CROWN and a.location == "rivermarch":
			print("move ", game.map.queue_move(a.id, "greenglade"))
	await _frames(5)
	game.end_turn()  ## seat 1 (the Crown) commits
	await _frames(10)
	if game.handoff.visible:
		game.handoff.ready_button.pressed.emit()
		await _frames(10)
	game.end_turn()  ## seat 2 (the Clans) commits: the turn resolves
	var w0 := Time.get_ticks_msec()
	while not board.is_playing() and Time.get_ticks_msec() - w0 < 20000:
		if game.handoff.visible:
			game.handoff.ready_button.pressed.emit()
		await process_frame
	print("playing ", board.is_playing())
	var gg: Vector2 = t.centre_of("greenglade")
	var marks := [5.0, 7.0, 8.5, 10.0, 11.5, 13.0, 15.0]
	var mi := 0
	var t0 := Time.get_ticks_msec()
	while board.is_playing() and Time.get_ticks_msec() - t0 < 90000:
		var top = game._top_overlay()
		if top != null:
			top.visible = false
		## hold a close view of the battle once the columns have arrived
		if board.armies.play_time() > 4.5:
			board.zoom = 0.97
			board.goal = board.rig_for(gg + Vector2(0, 4), 0.97)
		await process_frame
		var tp: float = board.armies.play_time()
		if mi < marks.size() and tp >= marks[mi]:
			await _shot("%s_07_playback_t%04.1f" % [tag, tp])
			mi += 1
	await _frames(20)
	game.close_turn_report()
	await _look(gg + Vector2(0, 4), 0.95, "%s_08_after_battle" % tag)
	quit()
