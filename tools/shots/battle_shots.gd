extends SceneTree
## UX-8 (#221): screenshots of the battle viewer on stored fixture battles, in the real BattleHost with a queue of them,
## so a director or builder can see the viewer's layout at any size on either view without playing a game to a turn with
## two battles (play_shots.gd's walk shows the viewer as a game opens it; this shows every state of it). Dev tool only.
##
##   $GODOT --path . --resolution 1600x900 --always-on-top -s res://tools/shots/battle_shots.gd -- --out=/abs/dir [options]
##
## Options (all optional):
##   --out=DIR          where the PNGs and shots.md go (default user://battle_shots)
##   --view=V           "3d" (the default) or "simple": the Battle view setting the host plays them in
##   --ui-scale=N       the interface size in percent, 100 or 125, as Settings sets it (the window stays as launched)
##   --fixtures=a,b     the stored fixtures (tests/fixtures/battles) to queue, in order (default king_falls_wins,round_cap_defender)
## For each battle of the queue it shoots: the start (the first-visit hint and its Got it), round 2 with the why panel open,
## round 2 with it closed (the Why tab on the edge), and the result card. The settings file is DIR/settings.cfg, deleted
## first, so the hint shows and the player's own file is never touched. Windowed only (headless draws nothing).

const Watch := preload("res://ui/battle/battle_watch.gd")
var out := "user://battle_shots"
var view := "3d"
var ui_scale := 100
var fixtures: Array = ["king_falls_wins", "round_cap_defender"]
var lines: PackedStringArray = []
var shot_n := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=", true, 1)
		match kv[0]:
			"out": out = kv[1]
			"view": view = kv[1]
			"ui-scale": ui_scale = int(kv[1])
			"fixtures": fixtures = Array(kv[1].split(","))
	DirAccess.make_dir_recursive_absolute(out)
	GameSettings.default_path = out.path_join("settings.cfg")
	if FileAccess.file_exists(GameSettings.default_path):
		DirAccess.remove_absolute(GameSettings.default_path)
	BattleFx.save_settings({"view": view})
	if GameSettings.UI_SCALES.has(ui_scale):
		root.content_scale_factor = ui_scale / 100.0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.gui_disable_input = true  # the real mouse's tooltip stays out of the shots
	_run()


func _run() -> void:
	var events := []
	for f in fixtures:
		var fx := Watch.load_fixture(String(f))
		if fx.is_empty():
			push_error("battle_shots: no fixture %s" % f)
			continue
		var factions := []
		for s in fx.log.sides:
			factions.append(String(s.faction))
		events.append({"type": "border_battle" if fx.log.get("kind", "") == "border" else "battle", "phase": "battles",
			"text": "A battle.", "provinces": (fx.log.provinces as Array).duplicate(), "factions": factions,
			"numbers": {"log": fx.log, "report": fx.report}})
	var host := BattleHost.new()
	root.add_child(host)
	await _frames(2)
	lines.append("# battle_shots (view %s, window %s, interface %d%%: laid out at %s)" % [view, DisplayServer.window_get_size(), ui_scale,
		root.get_visible_rect().size])
	var why := host.open(events, 0)
	if not why.is_empty():
		push_error("battle_shots: " + why)
		quit(1)
		return
	for i in events.size():
		await _settle(host)
		var v: Control = host.view
		var name := "b%d" % (i + 1)
		var title := BattleHost.battle_title(events[i])
		await _shot("%s_start" % name, "%s (%s view), the start: the plates, the centre, the caption with the first-visit hint." % [title, host.view_kind])
		v.player.seek_round(mini(2, v.player.timeline().rounds()))
		v.controls.set_why(true, false)
		await _settle(host)
		await _shot("%s_round2_why" % name, "%s, round 2, the why panel open." % title)
		v.controls.set_why(false, false)
		await _settle(host)
		await _shot("%s_round2_tab" % name, "%s, round 2, the why panel closed: the Why tab on the edge." % title)
		v.player.skip_to_end()
		await _settle(host)
		await _shot("%s_result" % name, "%s, the result card." % title)
		if i < events.size() - 1:
			host.next()
	var f := FileAccess.open(out.path_join("shots.md"), FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit()


## Waits for the 3D stage's land (time-based: the bake runs on a worker, M5-7) and for the camera to settle.
func _settle(host: BattleHost) -> void:
	var t := 0.0
	while t < 30.0 and not BattleStage3D.land_ready():
		await create_timer(0.1).timeout
		t += 0.1
	await create_timer(1.6).timeout
	if host.view != null and host.view.player != null:
		host.view.player.pause()


func _frames(n: int) -> void:
	for k in n:
		await process_frame


func _shot(name: String, note: String) -> void:
	await _frames(4)
	await RenderingServer.frame_post_draw
	shot_n += 1
	var file := "%02d_%s.png" % [shot_n, name]
	root.get_texture().get_image().save_png(out.path_join(file))
	lines.append("- **%s**  \n  %s" % [file, note])
	print("shot ", file)

