extends "res://tests/test_case.gd"
## M3-5 (#60; design/M3_BATTLES.md §6): BattleHost, the one place the game opens a battle playback, headless.
## The queue plays in the order given and returns at the end; Next, Previous, the result card's Next battle
## and the keys move through it; battles that can't be watched say why (and one whose log isn't kept is
## regenerated from the game record); the Battle view setting picks the view, 3D falls back to Simple
## until the stage exists, and a stand-in stage proves the view contract; the victory and defeat stings
## come from the viewer's side; the settings survive a restart and a missing or broken file gives the
## defaults; and nothing the host shows has a raw id.

const Fx := preload("res://tests/battle_playback_fixtures.gd")
const ThreeFx := preload("res://tests/three_side_fixtures.gd")
const STAND_IN := "res://tests/battle_stage_stand_in.gd"
const RECORDS := "res://tests/fixtures/main_records.json"
## m1_greedy_vs_ai's turn 5 has two battles: a border battle, then a province battle.
const GAME := "m1_greedy_vs_ai"
const BATTLE_TURN := 5
const STEP := 1.0 / 60.0


# --- fixtures -------------------------------------------------------------------------------------

## A stored battle fixture as a turn report battle event.
func _event(fixture: String) -> Dictionary:
	var fx := Fx.battle(fixture)
	assert_false(fx.is_empty(), "battle %s loads" % fixture)
	var factions := []
	for s in fx.log.sides:
		factions.append(String(s.faction))
	return {"type": "border_battle" if fx.log.kind == "border" else "battle", "phase": "battles",
		"text": "A battle (%d fighters)." % fx.log.fighters.size(), "provinces": fx.log.provinces.duplicate(), "factions": factions,
		"numbers": {"log": fx.log, "report": fx.report}}


func _host() -> BattleHost:
	var h := BattleHost.new()
	h.settings_path = _settings_path()
	return h


func _settings_path() -> String:
	return GameSettings.default_path.get_base_dir().path_join("host_settings_%d.cfg" % OS.get_process_id())


func _key(code: Key, shift := false) -> InputEventKey:
	var k := InputEventKey.new()
	k.keycode = code
	k.pressed = true
	k.shift_pressed = shift
	return k


static func _record(turns: int) -> Dictionary:
	var data = JSON.parse_string(FileAccess.get_file_as_string(RECORDS))
	for g in data.games:
		if String(g.name) == GAME:
			var rec: Dictionary = g.record.duplicate(true)
			rec.history = rec.history.slice(0, turns)
			return rec
	return {}


func _session() -> GameSession:
	var loaded := GameSession.from_record(_record(BATTLE_TURN))
	assert_eq(loaded.errors, [], "the recorded game loads")
	var session: GameSession = loaded.session
	assert_eq(session.battle_events().size(), 2, "turn %d had two battles" % BATTLE_TURN)
	return session


func _shown_log(h: BattleHost) -> Dictionary:
	return (h.view as BattleSimpleView).player.battle_log()


# --- the queue ------------------------------------------------------------------------------------

func test_the_queue_plays_in_order_with_next_previous_and_back() -> void:
	var events := [_event("king_falls_wins"), {"type": "captured", "text": "A capture."}, _event("forest_fort"), _event("border")]
	var battles := [events[0], events[2], events[3]]
	var h := _host()
	var opened := []
	var closed := [0]
	h.battle_opened.connect(func(i: int): opened.append(i))
	h.closed.connect(func(): closed[0] += 1)
	assert_eq(h.open(events, 2), "", "the queue opens")
	assert_true(h.visible, "the host covers the screen")
	assert_eq(h.queue.size(), 3, "only battles are queued")
	assert_eq(h.index, 1, "it starts at the battle asked for (events[2] is the queue's second)")
	assert_eq(var_to_str(_shown_log(h)), var_to_str(battles[1].numbers.log), "and plays that battle's log")
	var c: BattleControls = h.view.controls
	assert_true(c.queue_row.visible, "the queue row shows")
	assert_true(c.queue_label.text.begins_with("Battle 2 of 3: Battle "), c.queue_label.text)
	assert_false(c.buttons.previous_battle.disabled, "there is a battle before this one")
	assert_true(h.next(), "Next battle")
	assert_eq(h.index, 2)
	assert_eq(c.buttons.next_battle.text, "Back to the report", "the last battle's Next leads back")
	assert_true(h.previous())
	assert_true(h.previous())
	assert_eq(h.index, 0)
	assert_true(c.buttons.previous_battle.disabled, "the first battle has no Previous")
	assert_false(h.previous(), "nothing before the first")
	# The keys: N and Shift+N.
	assert_true(c.handle_key(_key(KEY_N)), "N is Next battle")
	assert_eq(h.index, 1)
	assert_true(c.handle_key(_key(KEY_N, true)), "Shift+N is Previous battle")
	assert_eq(h.index, 0)
	# The result card's Next battle.
	var v: BattleSimpleView = h.view
	var finished := [0]
	v.finished.connect(func(): finished[0] += 1)
	v.player.skip_to_end()
	v.tick(STEP)
	assert_eq(finished[0], 1, "the view says when the result is up")
	assert_true(v.end_card.visible and v.buttons.next_battle_card.visible, "the result card has Next battle")
	assert_eq(v.buttons.next_battle_card.text, "Next battle (2 of 3) ▸")
	v.buttons.next_battle_card.pressed.emit()
	assert_eq(h.index, 1, "it moves on")
	h.next()
	v.player.skip_to_end()
	v.tick(STEP)
	assert_eq(v.buttons.next_battle_card.text, "Back to the report", "the last result card leads back")
	assert_false(v.buttons.end_close.visible, "with no second button doing the same")
	v.buttons.next_battle_card.pressed.emit()
	assert_false(h.visible, "the end of the queue closes the host (the report shows again)")
	assert_eq(closed[0], 1, "closed once")
	assert_eq(opened, [1, 2, 1, 0, 1, 0, 1, 2], "every battle opened in queue order")
	# Esc in the view closes the host too.
	h.open(battles, 0)
	v._unhandled_input(_key(KEY_ESCAPE))
	assert_false(h.visible, "Esc goes back")
	assert_eq(closed[0], 2)
	h.free()


func test_a_single_battle_has_no_queue_row() -> void:
	var h := _host()
	assert_eq(h.open([_event("skirmish")]), "")
	var c: BattleControls = h.view.controls
	assert_false(c.queue_row.visible, "one battle: no queue row")
	assert_false(c.handle_key(_key(KEY_N)), "and N does nothing")
	h.view.player.skip_to_end()
	assert_false(h.view.buttons.next_battle_card.visible, "and no Next battle on the result card")
	assert_eq(h.open([{"type": "captured"}]), "There are no battles to watch.")
	h.free()


# --- battles that can't be watched ----------------------------------------------------------------

func test_battles_that_cant_be_watched_say_why() -> void:
	var good := _event("skirmish")
	var stub := {"type": "battle", "text": "A battle.", "numbers": {"winner": "kingdom"}}
	var cut := good.duplicate(true)
	cut.numbers.log.truncated = true
	var three: Dictionary = ThreeFx.battle("holds").event
	var unkept := good.duplicate(true)
	unkept.numbers.erase("log")
	assert_eq(BattleHost.watch_problem(good), "")
	assert_eq(BattleHost.watch_problem({"type": "captured"}), BattleHost.NOT_A_BATTLE)
	assert_eq(BattleHost.watch_problem(stub), BattleHost.NO_LOG)
	assert_eq(BattleHost.watch_problem(cut), "This battle is too big to play back. The report has everything.")
	assert_eq(BattleHost.watch_problem(three), "", "#265: a battle of three sides is watched like any other")
	assert_eq(BattleHost.watch_problem(unkept), BattleHost.NOT_KEPT, "a log that isn't kept, with nothing to rebuild it from")
	assert_eq(BattleHost.watch_problem(unkept, true), "", "with the game record it can be rebuilt")
	assert_true(BattleHost.needs_rebuild(unkept) and not BattleHost.needs_rebuild(good) and not BattleHost.needs_rebuild(stub))
	assert_eq(BattleHost.watchable([stub, good, cut, three, unkept]).size(), 2)
	# Opened anyway, the host says why and offers the next battle.
	var h := _host()
	h.open([stub, good])
	assert_true(h.message_panel.visible, "the reason is on screen")
	assert_eq(h.message_label.text, BattleHost.NO_LOG)
	assert_false(h.view.visible, "and no battle")
	assert_true(h.message_next.visible, "Next battle skips it")
	h.message_next.pressed.emit()
	assert_eq(h.index, 1)
	assert_false(h.message_panel.visible, "the message goes")
	assert_true(h.view.visible, "the next battle plays")
	h.open([cut])
	assert_eq(h.message_label.text, BattleHost.watch_problem(cut))
	assert_false(h.message_next.visible, "nothing to skip to")
	h.message_close.pressed.emit()
	assert_false(h.visible, "Back to the report closes")
	h.free()


func test_a_log_that_isnt_kept_is_regenerated_from_the_record() -> void:
	var session := _session()
	var record_before := var_to_str(session.record())
	var report_before := var_to_str(session.turn_report())
	var battles := session.battle_events()
	var unkept: Dictionary = battles[1].duplicate(true)
	unkept.numbers.erase("log")
	var h := _host()
	h.rebuild_with = func(e: Dictionary) -> Dictionary: return GameScreen.rebuild_battle_log(session, e)
	assert_eq(h.open([unkept], 0, session), "")
	assert_true(h.message_panel.visible and h.message_label.text == BattleHost.REBUILDING, "Regenerating… shows first")
	assert_false(h.message_close.visible, "with nothing to press")
	h.rebuild_now()
	assert_false(h.message_panel.visible, "then the battle plays")
	assert_eq(var_to_str(_shown_log(h)), var_to_str(battles[1].numbers.log), "the rebuilt log is the battle's own log")
	# A battle that isn't in the report can't be rebuilt, and says so.
	var stranger := unkept.duplicate(true)
	stranger.text = "Some other battle."
	h.open([stranger], 0, session)
	h.rebuild_now()
	assert_true(h.message_panel.visible, "the reason is on screen")
	assert_true(h.message_label.text.contains("isn't in the last turn's report"), h.message_label.text)
	# Without a way to rebuild, it is not watchable.
	var h2 := _host()
	h2.open([unkept], 0, session)
	assert_eq(h2.message_label.text, BattleHost.NOT_KEPT)
	assert_eq(var_to_str(session.record()), record_before, "the game record is unchanged")
	assert_eq(var_to_str(session.turn_report()), report_before, "the turn report is unchanged")
	h.free()
	h2.free()


# --- the view: setting, fallback, contract --------------------------------------------------------

func test_the_battle_view_setting_and_the_3d_fallback() -> void:
	var path := _settings_path()
	DirAccess.remove_absolute(path)
	var keep := BattleHost.stage_3d_path
	assert_eq(BattleHost.chosen_view(path), "3d", "3D on the land by default (M3b)")
	assert_eq(BattleFx.save_settings({"view": "simple"}, path), "")
	var h := _host()
	h.open([_event("skirmish")])
	assert_eq(h.view_kind, "simple", "Simple stays a setting")
	assert_false(h.note_label.visible, "no note for the Simple view")
	assert_eq(BattleFx.save_settings({"view": "3d"}, path), "")
	BattleHost.stage_3d_path = "res://world3d/no_such_stage.tscn"
	assert_false(BattleHost.has_stage_3d())
	h.open([_event("skirmish")])
	assert_eq(h.view_kind, "simple", "3D without the stage falls back to the Simple view")
	assert_true(h.view is BattleSimpleView)
	assert_true(h.note_label.visible and h.note_label.text == BattleHost.FALLBACK_NOTE, "with a note that says so")
	BattleHost.stage_3d_path = keep
	h.free()
	DirAccess.remove_absolute(path)


func test_a_3d_stage_that_keeps_the_contract_plugs_in() -> void:
	var path := _settings_path()
	BattleFx.save_settings({"view": "3d"}, path)
	var keep := BattleHost.stage_3d_path
	BattleHost.stage_3d_path = STAND_IN
	assert_true(BattleHost.has_stage_3d())
	var session := _session()
	var battles := session.battle_events()
	var h := _host()
	var a := GameAudio.new()
	GameAudio.current = a
	var winner := String(battles[0].numbers.winner)
	assert_eq(h.open(battles, 0, session, winner), "")
	assert_eq(h.view_kind, "3d", "the stage is used")
	assert_true(BattleHost.keeps_contract(h.view))
	var stage = h.view
	assert_eq(stage.calls.size(), 1, "play() was called once")
	var call: Dictionary = stage.calls[0]
	assert_eq(var_to_str(call.log), var_to_str(battles[0].numbers.log), "with the battle's log")
	assert_eq(var_to_str(call.report), var_to_str(battles[0].numbers.report), "its report")
	assert_true(call.state is GameState, "the game state, for the land")
	assert_eq(call.seats, session.players(), "and the seats")
	assert_false(h.note_label.visible, "no fallback note")
	assert_true(stage.controls.queue_row.visible, "the host put its queue row on the stage's control bar")
	assert_true(stage.controls.buttons.settings.visible, "and its Settings button")
	stage.finish()
	assert_eq(h.last_sting, "sting_victory", "finished plays the viewer's sting")
	stage.controls.next_requested.emit()
	assert_eq(h.index, 1, "the stage's bar moves the queue")
	assert_eq(stage.calls.size(), 2)
	stage.close()
	assert_false(h.visible, "closing the stage closes the host")
	assert_false(a.in_mood(), "and leaves no battle mood behind")
	GameAudio.current = null
	a.free()
	BattleHost.stage_3d_path = keep
	h.free()
	DirAccess.remove_absolute(path)


# --- stings ---------------------------------------------------------------------------------------

func test_victory_and_defeat_stings_from_the_viewers_side() -> void:
	var e := _event("king_falls_wins")
	var lg: Dictionary = e.numbers.log
	var end_i := BattleLog.find_event(lg, "end")
	var won := String(lg.sides[int(lg.events[end_i].winner)].faction)
	var lost := String(lg.sides[1 - int(lg.events[end_i].winner)].faction)
	assert_eq(BattleHost.sting_for(lg, won), "sting_victory")
	assert_eq(BattleHost.sting_for(lg, lost), "sting_defeat")
	assert_eq(BattleHost.sting_for(lg, ""), "", "nobody in particular: no sting")
	assert_eq(BattleHost.sting_for(lg, "a_third_faction"), "", "a faction that didn't fight: no sting")
	var a := GameAudio.new()
	GameAudio.current = a
	for case in [[won, "sting_victory"], [lost, "sting_defeat"], ["", ""]]:
		var h := _host()
		h.open([e, _event("skirmish")], 0, null, String(case[0]))
		assert_true(a.in_mood(), "the battle music is up")
		var v: BattleSimpleView = h.view
		v.player.play()
		assert_eq(h.last_sting, "", "no sting before the end")
		v.player.skip_to_end()
		assert_eq(h.last_sting, String(case[1]), "the viewer %s hears %s" % [case[0], case[1]])
		if not String(case[1]).is_empty():
			assert_eq(a.music_name, String(case[1]), "the sting plays over the battle music")
		h.next()
		assert_eq(a.music_name, GameAudio.BATTLE_MUSIC, "the next battle brings the battle music back")
		h.close()
		assert_false(a.in_mood(), "closing leaves no battle mood behind")
		h.free()
	GameAudio.current = null
	a.free()


# --- settings -------------------------------------------------------------------------------------

func test_the_settings_survive_a_restart_and_a_broken_file_gives_the_defaults() -> void:
	var path := _settings_path()
	DirAccess.remove_absolute(path)
	assert_eq(BattleFx.settings(path), BattleFx.DEFAULTS, "no file: the defaults")
	assert_eq(BattleFx.settings(path).view, "3d", "3D on the land by default (M3b)")
	assert_false(GameSettings.load_from(path).auto_watch_battles, "auto-watch is off by default")
	var keep := BattleHost.stage_3d_path
	BattleHost.stage_3d_path = "res://world3d/no_such_stage.tscn"
	BattleFx.save_settings({"view": "simple"}, path)
	var panel := SettingsPanel.new()
	panel.open(GameSettings.load_from(path))
	assert_eq(panel.battle_view_picker.selected, 0, "Simple")
	assert_eq(panel.battle_speed_picker.selected, 0, "1x")
	assert_false(panel.reduced_motion_toggle.button_pressed)
	assert_true(panel.screen_shake_toggle.button_pressed)
	assert_eq(panel.watch_picker.selected, 0)
	assert_false(panel.battle_view_note.visible)
	panel.battle_view_picker.item_selected.emit(1)
	panel.battle_speed_picker.item_selected.emit(2)
	panel.reduced_motion_toggle.toggled.emit(true)
	panel.screen_shake_toggle.toggled.emit(false)
	panel.watch_picker.item_selected.emit(1)
	panel.set_window_mode("fullscreen")  # [settings] saved after [battle]: both stay
	assert_true(panel.battle_view_note.visible, "3D chosen without the stage: the note says it plays Simple")
	panel.free()
	BattleHost.stage_3d_path = keep
	# A restart: everything is read back from the file.
	var st := BattleFx.settings(path)
	assert_eq(st.view, "3d")
	assert_eq(st.speed, 4)
	assert_true(st.reduced_motion)
	assert_false(st.screen_shake)
	var gs := GameSettings.load_from(path)
	assert_true(gs.auto_watch_battles)
	assert_eq(gs.window_mode, "fullscreen")
	var again := SettingsPanel.new()
	again.open(GameSettings.load_from(path))
	assert_eq([again.battle_view_picker.selected, again.battle_speed_picker.selected, again.watch_picker.selected], [1, 2, 1])
	assert_true(again.reduced_motion_toggle.button_pressed and not again.screen_shake_toggle.button_pressed)
	assert_true(again.screen_shake_toggle.disabled, "reduced motion turns shake off whatever it says")
	again.free()
	# The default speed is the speed a battle starts at.
	var h := _host()
	h.open([_event("skirmish")])
	var v: BattleSimpleView = h.view
	assert_true(v.reduced_motion, "the host gives the view reduced motion from the settings")
	h.free()
	# A broken file, and values of the wrong kind: the defaults, with no error.
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("this is [not a config {{{")
	f.close()
	assert_eq(BattleFx.settings(path), BattleFx.DEFAULTS, "a broken file: the defaults")
	assert_false(GameSettings.load_from(path).auto_watch_battles)
	f = FileAccess.open(path, FileAccess.WRITE)
	f.store_string("[battle]\nview=\"sideways\"\nspeed=3\nreduced_motion=\"yes\"\nscreen_shake=0\n[settings]\nauto_watch_battles=\"yes\"\n")
	f.close()
	assert_eq(BattleFx.settings(path), BattleFx.DEFAULTS, "unknown values: the defaults")
	assert_false(GameSettings.load_from(path).auto_watch_battles)
	var broken := SettingsPanel.new()
	broken.open(GameSettings.load_from(path))
	assert_eq(broken.battle_view_picker.selected, BattleFx.VIEWS.find(String(BattleFx.DEFAULTS.view)), "the panel shows the defaults")
	broken.free()
	DirAccess.remove_absolute(path)


func test_settings_open_over_the_battle_and_pause_it() -> void:
	var h := _host()
	h.open([_event("forest_fort")])
	var v: BattleSimpleView = h.view
	v.player.play()
	assert_true(v.controls.buttons.settings.visible, "the host offers Settings on the control bar")
	assert_true(v.controls.buttons.settings.tooltip_text.contains("(S)"), "naming its key")
	assert_true(v.controls.handle_key(_key(KEY_S)), "S opens the settings")
	assert_true(h.settings_panel != null and h.settings_panel.visible, "the settings panel is over the battle")
	assert_eq(h.settings_panel.get_index(), h.get_child_count() - 1, "on top")
	assert_false(v.player.is_playing(), "the battle pauses")
	h.settings_panel.close()
	assert_true(v.player.is_playing(), "and plays on when they close")
	h.free()
	# The launcher's own Simple view doesn't offer it.
	var plain := BattleSimpleView.new()
	assert_false(plain.controls.buttons.settings.visible)
	assert_false(plain.controls.handle_key(_key(KEY_S)))
	plain.free()


# --- texts ----------------------------------------------------------------------------------------

func test_no_raw_ids_in_what_the_host_shows() -> void:
	var names := ["king_falls_wins", "border", "forest_fort", "dread_feast_frenzy"]
	var events := names.map(func(n): return _event(n))
	var h := _host()
	h.open(events, 0)
	var snake := RegEx.create_from_string("[a-z]+_[a-z_]+")
	for i in events.size():
		var v: BattleSimpleView = h.view
		var texts: Array = v.visible_texts()
		v.player.skip_to_end()
		texts.append_array(v.visible_texts())
		texts.append(h.view.controls.queue_label.text)
		texts.append(BattleHost.battle_title(events[i]))
		var ids := _raw_ids(events[i].numbers.log)
		for t in texts:
			var text := String(t)
			assert_true(snake.search(text) == null, "%s: no snake_case id in \"%s\"" % [names[i], text])
			for id in ids:
				assert_false(_has_word(text, id), "%s: no raw id '%s' in \"%s\"" % [names[i], id, text])
		h.next()
	for text in [BattleHost.FALLBACK_NOTE, BattleHost.NO_LOG, BattleHost.NOT_KEPT, BattleHost.REBUILDING]:
		assert_true(snake.search(text) == null, text)
	h.free()


func _has_word(text: String, word: String) -> bool:
	var re := RegEx.create_from_string("[A-Za-z0-9_-]+")
	for m in re.search_all(text):
		if m.get_string() == word:
			return true
	return false


func _raw_ids(battle_log: Dictionary) -> Array:
	var ids := {}
	for s in battle_log.sides:
		ids[String(s.faction)] = true
		for a in s.armies:
			ids[String(a.id)] = true
	for f in battle_log.fighters:
		ids[String(f.type)] = true
	for p in battle_log.provinces:
		ids[String(p)] = true
	return ids.keys()
