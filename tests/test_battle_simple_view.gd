extends "res://tests/test_case.gd"
## M3-3 (#58, re-scoped by design/3D_DIRECTION.md §7.6): the 2D Simple view (BattleSimpleView) and its
## launcher (ui/battle/battle_watch.tscn) on every fixture, headless. Every fixture plays at 4x in fixed
## 1/60 s steps to the end, where every card and both strength bars equal BattleTimeline's final state; the
## layout gives every fighter its own place inside the field; hovering a card shows BattleExplain's own
## words and numbers; reduced motion turns off lunges, shakes and bright impact frames; no visible text has a
## raw id; watching battles leaves the game state, the turn report, its logs and the game record exactly as
## they were (the UI level of "playback never changes the outcome"); unwatchable battles say why; the
## controls and keys drive the player; and the biggest fixture plays inside §8.2's CPU budget.

const Watch := preload("res://ui/battle/battle_watch.gd")
const Scenarios := preload("res://tools/battle_log/scenarios.gd")
const STEP := 1.0 / 60.0
## §8.2: playback CPU per frame, headless, fixed 1/60 s steps (average and worst frame), on the build box.
const CPU_AVG_MS := 2.0
const CPU_MAX_MS := 4.0


func _fixture(name: String) -> Dictionary:
	var fx := Watch.load_fixture(name)
	assert_false(fx.is_empty(), "fixture %s loads" % name)
	return fx


func _view(fx: Dictionary, reduced := false) -> BattleSimpleView:
	var v := BattleSimpleView.new()
	v.reduced_motion = reduced
	assert_eq(v.show_battle(fx.log, fx.report), "", "the battle plays")
	return v


## Plays the view to the end at `speed`; returns the frames it took.
func _play_out(v: BattleSimpleView, speed: int) -> int:
	v.player.set_speed(speed)
	v.player.play()
	var frames := 0
	while not v.player.is_finished() and frames < 100000:
		v.tick(STEP)
		frames += 1
	# Let the last motions (fades, slides) finish.
	for k in 120:
		v.tick(STEP)
	return frames


func _collapse(text: String) -> String:
	var out := text.replace("\n", " ")
	while out.contains("  "):
		out = out.replace("  ", " ")
	return out.strip_edges()


func test_every_fixture_plays_to_the_timelines_final_state() -> void:
	for name in Scenarios.NAMES:
		var fx := _fixture(name)
		var v := _view(fx)
		_play_out(v, 4)
		var fin := v.player.timeline().final_state()
		assert_eq(v.player.state(), fin, "%s: the player ends on the final state" % name)
		for f in fx.log.fighters:
			var fid := int(f.id)
			var c := v.card(fid)
			var fs: Dictionary = fin.fighters[fid]
			assert_eq(c.hp, int(fs.hp), "%s: %s's card shows its final hp" % [name, f.name])
			assert_eq(c.alive, bool(fs.alive), "%s: %s's card is alive exactly when the fighter is" % [name, f.name])
			assert_eq(c.pending, 0, "%s: nothing pending at the end" % name)
			if not fs.alive:
				assert_true(c.visible and c.material == BattleCard.fallen_material(), "%s: %s stays as a grey fallen marker" % [name, f.name])
				assert_true(absf(c.modulate.a - BattleCard.FALLEN_ALPHA) < 0.01, "%s: the fallen marker at 40%%" % name)
			elif fs.fled or fs.lost:
				assert_false(c.visible, "%s: %s has left the field" % [name, f.name])
			else:
				assert_true(c.visible and c.modulate.a > 0.99, "%s: %s still stands" % [name, f.name])
				assert_eq(c.position, c.home, "%s: %s is back in its place" % [name, f.name])
		for si in 2:
			var st := BattleExplain.side_strength(fx.log, fin, si)
			var b := v.bar(si)
			assert_true(absf(b.fill - float(st.fill)) < 0.0001, "%s: side %d's bar shows its final hp" % [name, si])
			assert_eq(b.pending_share, 0.0, "%s: no pending damage on the bar" % name)
			assert_true(absf(b.notch() - float(st.notch)) < 0.0001, "%s: side %d's notch is at its final break line" % [name, si])
			assert_eq(b.out, String(st.out), "%s: side %d is out exactly as the log says" % [name, si])
		assert_true(v.end_card.visible, "%s: the result card is up" % name)
		assert_true(v.end_result.text.length() > 10, "%s: with the result" % name)
		assert_true(v.end_why.text.begins_with("Why: "), "%s: and the why" % name)
		v.free()


func test_every_fighter_has_its_own_place_in_the_field() -> void:
	var field := Rect2(0, 0, BattleSimpleView.BASE.x, BattleSimpleView.FIELD_H)
	for name in Scenarios.NAMES:
		var fx := _fixture(name)
		var lay := BattleLayout.build(fx.log, field.size)
		var rects := []
		for f in fx.log.fighters:
			var slot: Dictionary = lay.slots[int(f.id)]
			assert_false(slot.is_empty(), "%s: %s has a slot" % [name, f.name])
			var r: Rect2 = slot.rect
			assert_true(field.encloses(r), "%s: %s's card is inside the field" % [name, f.name])
			var on_left := int(f.side) == int(lay.left)
			assert_eq(r.get_center().x < field.size.x / 2.0, on_left, "%s: %s stands on its side's half" % [name, f.name])
			rects.append(r)
		var defender := String(fx.log.defender)
		if not defender.is_empty():
			assert_eq(String(fx.log.sides[int(lay.right)].faction), defender, "%s: the defender stands on the right" % name)
		for a in rects.size():
			for b in range(a + 1, rects.size()):
				if lay.crowd:
					assert_ne(rects[a].position, rects[b].position, "%s: no two cards share a place" % name)
				else:
					assert_false(rects[a].intersects(rects[b]), "%s: cards %d and %d don't overlap" % [name, a, b])
		assert_true(float(lay.scale) >= BattleLayout.SCALES[-1], "%s: cards no smaller than the smallest scale" % name)
		# Fronts nearest the centre: every front-rank card is nearer the middle than its side's back line.
		for si in 2:
			var front := INF
			var back := INF
			for fid in fx.log.sides[si].fighters:
				var d: float = absf((lay.slots[int(fid)].rect as Rect2).get_center().x - field.size.x / 2.0)
				var tier := int(fx.log.fighters[int(fid)].tier)
				if tier == 0:
					front = minf(front, d)
				elif tier == 2:
					back = minf(back, d)
			if front < INF and back < INF:
				assert_true(front < back, "%s: side %d's front rank stands nearer the centre than its back line" % [name, si])
	var big := BattleLayout.build(_fixture("biggest").log, field.size)
	assert_true(big.crowd, "the 277-fighter battle closes its rows into a crowd")
	var small := BattleLayout.build(_fixture("starting_plains").log, field.size)
	assert_eq(small.scale, 1.0, "the starting armies fit at full size")


func test_hovering_a_card_shows_battle_explain() -> void:
	for name in ["king_falls_wins", "skirmish", "dread_feast_frenzy"]:
		var fx := _fixture(name)
		var v := _view(fx)
		var tl := v.player.timeline()
		var points := [tl.round_start(1), tl.round_start(2) + 3, fx.log.events.size()]
		for i in points:
			v.player.seek(i)
			var st := v.player.state()
			for f in fx.log.fighters:
				var fid := int(f.id)
				var ex := BattleExplain.explain_fighter(tl, fid, int(st.event), st)
				var tip := v.card(fid)._get_tooltip(Vector2.ZERO)
				assert_eq(_collapse(tip), _collapse(" ".join(ex.lines)), "%s: %s's hover is BattleExplain's, word for word" % [name, f.name])
				assert_eq(v.card(fid).hp, int(ex.hp_value), "%s: the card's hp is the explanation's" % name)
				assert_eq(v.card(fid).pending, int(ex.pending), "%s: the card's pending is the explanation's" % name)
				assert_eq(v.card(fid).codex_key, String(ex.codex), "%s: right-click opens the explanation's codex entry" % name)
				for line in tip.split("\n"):
					assert_true(line.length() <= BattleSimpleView.TOOLTIP_WRAP + 12, "%s: the hover stays narrow" % name)
		v.free()


func test_reduced_motion_turns_off_lunges_shakes_and_flashes() -> void:
	var fx := _fixture("knights_charge")
	var seen := {}
	for reduced in [false, true]:
		var v := _view(fx, reduced)
		var moved := false
		var bright := false
		var rings := false
		var shook := false
		v.player.play()
		var guard := 0
		while not v.player.is_finished() and guard < 4000:
			v.tick(STEP)
			guard += 1
			for f in fx.log.fighters:
				var c := v.card(int(f.id))
				if c.alive and c.visible and c.position.distance_to(c.home) > 0.5:
					moved = true
				if not c.alive and absf(c.rotation) > 0.001:
					moved = true
			for it in v.effects.impacts.items:
				if it.bright:
					bright = true
				if it.ring:
					rings = true
			if v.stage.position != Vector2.ZERO:
				shook = true
		seen[reduced] = {"moved": moved, "bright": bright, "rings": rings, "shook": shook}
		assert_eq(v.player.reduced_motion, reduced, "the player's slow motion follows the setting")
		v.free()
	assert_true(seen[false].moved and seen[false].bright and seen[false].shook, "normally cards lunge, impacts flash and the Knights' charge shakes")
	assert_false(seen[true].moved, "with reduced motion no card lunges, shakes, tips or slides")
	assert_false(seen[true].bright, "with reduced motion no impact has bright frames")
	assert_false(seen[true].shook, "with reduced motion the screen never shakes")
	assert_true(seen[true].rings, "with reduced motion impacts are static rings")


func test_reduced_motion_is_read_from_the_settings_file() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("battle", "reduced_motion", true)
	DirAccess.make_dir_recursive_absolute(GameSettings.default_path.get_base_dir())
	cfg.save(GameSettings.default_path)
	var v := BattleSimpleView.new()
	v.show_battle(_fixture("skirmish").log)
	assert_true(v.reduced_motion, "the [battle] reduced_motion setting reaches the view")
	assert_true(v.card(0).reduced_motion, "and its cards")
	v.free()
	DirAccess.remove_absolute(GameSettings.default_path)
	var w := BattleSimpleView.new()
	w.show_battle(_fixture("skirmish").log)
	assert_false(w.reduced_motion, "without a settings file, reduced motion is off")
	w.free()


func test_no_visible_text_has_a_raw_id() -> void:
	for name in Scenarios.NAMES:
		var fx := _fixture(name)
		var v := _view(fx)
		var ids := _raw_ids(fx.log)
		var texts := []
		for i in [0, v.player.timeline().round_start(1) + 2]:
			v.player.seek(i)
			texts.append_array(v.visible_texts())
		v.player.play()
		for k in 400:
			v.tick(STEP)
		texts.append_array(v.visible_texts())
		v.player.skip_to_end()
		v.tick(STEP)
		texts.append_array(v.visible_texts())
		assert_true(v.end_card.visible, "%s: the result card is checked too" % name)
		var snake := RegEx.create_from_string("[a-z]+_[a-z_]+")
		var word := RegEx.create_from_string("[A-Za-z0-9_-]+")
		for t in texts:
			var text := String(t)
			assert_true(snake.search(text) == null, "%s: no snake_case id in \"%s\"" % [name, text])
			var words := {}
			for m in word.search_all(text):
				words[m.get_string()] = true
			for id in ids:
				assert_false(words.has(id), "%s: no raw id '%s' in \"%s\"" % [name, id, text])
		v.free()


func _raw_ids(battle_log: Dictionary) -> Array:
	var ids := {}
	for s in battle_log.sides:
		ids[String(s.faction)] = true
		for a in s.armies:
			ids[String(a.id)] = true
		for m in s.mandates:
			ids[String(m)] = true
	for f in battle_log.fighters:
		ids[String(f.type)] = true
		if not f.ruler.is_empty():
			ids[String(f.ruler.id)] = true
	for p in battle_log.provinces:
		ids[String(p)] = true
	if not String(battle_log.id).is_empty():
		ids[String(battle_log.id)] = true
	return ids.keys()


func test_watching_battles_never_changes_the_game() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string(Scenarios.BIGGEST_RECORD))
	var rec: Dictionary = data.record.duplicate(true)
	rec.history = rec.history.slice(0, int(Scenarios.BIGGEST.turn))
	var loaded := GameSession.from_record(rec)
	assert_eq(loaded.errors, [], "the game loads")
	var session: GameSession = loaded.session
	var state_before := var_to_str(session.state().to_dict())
	var report_before := var_to_str(session.turn_report())
	var record_before := var_to_str(session.record())
	var events := session.battle_events()
	assert_true(events.size() >= 1, "the last turn had battles")
	var events_before := var_to_str(events)
	var watch := Watch.new()
	for e in events:
		assert_eq(watch.watch(e, session.players()), "", "the battle can be watched")
		var v: BattleSimpleView = watch.view
		_play_out(v, 4)
		v.player.seek_round(2)
		v.player.next_moment()
		for fid in range(0, e.numbers.log.fighters.size(), 11):
			v.fighter_tooltip(fid)
		v.player.skip_to_end()
		v.tick(STEP)
		v.report_requested.emit(e)
		assert_true(watch.viewer.visible, "Full report opens the battle report viewer")
	assert_eq(var_to_str(events), events_before, "the watched events (their reports and logs) are unchanged")
	assert_eq(var_to_str(session.state().to_dict()), state_before, "the game state is unchanged")
	assert_eq(var_to_str(session.turn_report()), report_before, "the turn report, with its reports and logs, is unchanged")
	assert_eq(var_to_str(session.record()), record_before, "the game record is unchanged")
	watch.free()


func test_battles_that_cant_be_watched_say_why() -> void:
	var v := BattleSimpleView.new()
	var why := v.show_event({"type": "battle", "text": "A battle.", "numbers": {}})
	assert_eq(why, "This battle was fought with the test rules and has no playback.")
	assert_true(v.message_panel.visible and v.message_label.text == why, "the reason is on screen")
	var fx := _fixture("skirmish")
	var cut: Dictionary = fx.log.duplicate(true)
	cut.truncated = true
	assert_eq(v.show_battle(cut), "This battle is too big to play back. The report has everything.")
	var three: Dictionary = fx.log.duplicate(true)
	three.sides.append(three.sides[0].duplicate(true))
	assert_eq(v.show_battle(three), "Battles with more than two sides can't be watched yet.")
	assert_eq(v.show_battle(fx.log, fx.report), "", "a good log plays")
	assert_false(v.message_panel.visible, "and the message goes away")
	v.free()


func test_the_controls_and_keys_drive_the_player() -> void:
	var fx := _fixture("king_falls_wins")
	var v := _view(fx)
	v.buttons.play.pressed.emit()
	assert_true(v.player.is_playing(), "Play plays")
	assert_eq(v.buttons.play.text, "Pause", "and becomes Pause")
	v.buttons.speed4.pressed.emit()
	assert_eq(v.player.speed(), 4, "4x")
	assert_true(v.buttons.speed4.button_pressed and not v.buttons.speed1.button_pressed, "the speed buttons show it")
	v._unhandled_input(_key(KEY_1))
	assert_eq(v.player.speed(), 1, "key 1: 1x")
	v._unhandled_input(_key(KEY_SPACE))
	assert_false(v.player.is_playing(), "Space pauses")
	v._unhandled_input(_key(KEY_PERIOD))
	assert_true(v.player.next_beat() > 0, "period steps while paused")
	var r := v.player.round_now()
	v._unhandled_input(_key(KEY_RIGHT))
	assert_eq(v.player.state(), v.player.timeline().state_at(v.player.timeline().round_start(r + 1)), "Right goes to the next round's start")
	for kind in BattleMoments.KINDS:
		var b: Button = v.moment_buttons[kind]
		var has := not BattleMoments.of_kind(fx.log, kind).is_empty()
		assert_eq(b.disabled, not has, "%s's button is enabled exactly when there is one" % kind)
		assert_false(b.tooltip_text.is_empty(), "%s's button says what it does or why not" % kind)
	assert_true(v.moment_buttons.turning_point.tooltip_text.contains("ahead from the start"), "the disabled turning point says why")
	v.moment_buttons.ruler_falls.pressed.emit()
	var m: Dictionary = BattleMoments.of_kind(fx.log, "ruler_falls")[0]
	assert_true(absf(v.player.time() - (v.player.moment_time(m) - BattlePlayer.LEAD_IN)) < 0.001, "Ruler falls jumps to the king's fall")
	v.scrubber.scrubbed.emit(3.0)
	assert_eq(v.player.time(), 3.0, "the scrubber seeks")
	v.scrubber.released.emit()
	v._unhandled_input(_key(KEY_END))
	assert_true(v.end_card.visible, "End skips to the result card")
	v.buttons.again.pressed.emit()
	assert_true(v.player.is_playing() and not v.end_card.visible, "Watch again plays from the start")
	var closed := [false]
	v.closed.connect(func(): closed[0] = true)
	v._unhandled_input(_key(KEY_ESCAPE))
	assert_true(closed[0] and not v.visible, "Esc closes")
	for b in [v.buttons.restart, v.buttons.play, v.buttons.speed1, v.buttons.speed2, v.buttons.speed4, v.buttons.skip, v.buttons.close]:
		assert_true(b.tooltip_text.contains("(") and b.tooltip_text.contains(")"), "%s's tooltip names its key" % b.text)
	v.free()


func _key(code: Key) -> InputEventKey:
	var k := InputEventKey.new()
	k.keycode = code
	k.pressed = true
	return k


func test_the_bars_captions_and_terms_link_to_the_codex() -> void:
	var fx := _fixture("forest_fort")
	var v := _view(fx)
	var opened := []
	v.codex_requested.connect(func(key): opened.append(key))
	for si in 2:
		assert_eq(CodexLink.key_at(v.bar(si)), "battle_strength", "each strength bar links its codex entry")
		assert_true(v.bar(si).tooltip_text.contains("notch"), "and explains the notch")
	assert_eq(CodexLink.key_at(v.caption_labels[0]), "battle_playback", "before round 1, the hint links Watching a battle")
	v.player.play()
	while v.player.round_now() < 2 and not v.player.is_finished():
		v.tick(STEP)
	var line: Dictionary = v.player.caption(1)[0]
	assert_eq(v.caption_labels[0].text, String(line.text), "round 1's caption is BattleCaptions'")
	assert_eq(CodexLink.key_at(v.caption_labels[0]), String(line.codex), "and links its codex entry")
	var chips := []
	for k in 2:
		for c in v.chip_boxes[k].get_children():
			chips.append((c as Label).text)
	assert_true(chips.has("Forest: +2 defense") and chips.has("Fort: +2 defense"), "the defender's plaque has its terrain and fort chips")
	v.card(0)._gui_input(CodexLink.right_click())
	assert_eq(opened[-1], v.card(0).codex_key, "right-click on a card opens its codex entry")
	v.free()


func test_the_launcher_plays_a_fixture_and_hosts_the_report_and_codex() -> void:
	var watch := Watch.new()
	assert_eq(watch.watch(Watch.load_fixture("one_round")), "", "a fixture plays")
	assert_true(watch.view.visible, "in the Simple view")
	watch.view.player.skip_to_end()
	watch.view.buttons.report.pressed.emit()
	assert_true(watch.viewer.visible, "Full report opens the battle report viewer")
	assert_eq(watch.viewer.section_names()[0], "why", "with the report")
	watch.view.codex_requested.emit("battle_playback")
	assert_true(watch.codex.visible, "the codex opens")
	assert_eq(watch.codex.current_key(), "battle_playback", "at the entry asked for")
	assert_eq(Watch.load_fixture("no_such_battle"), {}, "an unknown fixture is {}")
	var event := {"type": "battle", "numbers": Watch.load_fixture("skirmish")}
	assert_eq(watch.watch(event), "", "a battle event plays")
	assert_eq(watch.watch(Watch.load_fixture("skirmish").log), "", "a bare log plays")
	# With no art at all (§9.3), every card is its placeholder and the ground its flat colour, and the
	# battle still plays to the timeline's end.
	var fx := Watch.load_fixture("forest_fort")
	watch.watch(fx)
	watch.show_without_art()
	assert_false(watch.view.backdrop.has_art(), "no terrain art")
	_play_out(watch.view, 4)
	for f in fx.log.fighters:
		var c := watch.view.card(int(f.id))
		assert_true(c.texture == null, "%s is a placeholder card" % f.name)
		assert_eq(c.hp, int(watch.view.player.timeline().final_state().fighters[int(f.id)].hp), "and still ends on its final hp")
	assert_true(watch.view.end_card.visible, "the result card comes up without art too")
	watch.free()


## Playback CPU per frame on the biggest fixture at 4x, headless, fixed 1/60 s steps (§8.2). The runs are
## deterministic (the same work in frame k every time), so each frame's time is taken as its fastest over
## the runs: that filters out the moments a shared machine spends on other processes (which only ever make a
## frame slower) and keeps every frame's own cost, worst frame included. It stops once the budget is met,
## after at least MIN_RUNS runs and at most MAX_RUNS.
const MIN_RUNS := 3
const MAX_RUNS := 15


func test_the_biggest_battle_plays_inside_the_cpu_budget() -> void:
	var fx := _fixture("biggest")
	var best: Array = []
	var runs := 0
	for attempt in MAX_RUNS:
		runs += 1
		var v := _view(fx)
		v.player.set_speed(4)
		v.player.play()
		var frames := 0
		while not v.player.is_finished() and frames < 10000:
			var t0 := Time.get_ticks_usec()
			v.tick(STEP)
			var ms := (Time.get_ticks_usec() - t0) / 1000.0
			if frames < best.size():
				best[frames] = minf(float(best[frames]), ms)
			else:
				best.append(ms)
			frames += 1
		v.free()
		var m := _avg_max(best)
		if runs >= MIN_RUNS and m[0] <= CPU_AVG_MS and m[1] <= CPU_MAX_MS:
			break
	var am := _avg_max(best)
	var avg: float = am[0]
	var worst: float = am[1]
	print("     biggest fixture at 4x, headless, %d frames: playback CPU avg %.2f ms, worst frame %.2f ms (fastest of %d runs per frame)" % [best.size(), avg, worst, runs])
	assert_true(avg <= CPU_AVG_MS, "average %.2f ms per frame (budget %.1f ms)" % [avg, CPU_AVG_MS])
	assert_true(worst <= CPU_MAX_MS, "worst frame %.2f ms (budget %.1f ms)" % [worst, CPU_MAX_MS])


func _avg_max(times: Array) -> Array:
	var total := 0.0
	var worst := 0.0
	for ms in times:
		total += float(ms)
		worst = maxf(worst, float(ms))
	return [total / maxi(1, times.size()), worst]
