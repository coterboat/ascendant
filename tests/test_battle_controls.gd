extends "res://tests/test_case.gd"
## M3-4 (#59): the battle controls, scrubber, selection, the why panel and the legend (BattleControls,
## BattleSelection, BattleWhy, BattleWhyPanel, BattleLegend) in the Simple view, headless, M1-style:
## - scrubbing to any point shows BattleTimeline's state there, and seeking equals playing: the field after
##   seeking to a point equals the field after playing to it, for every fixture, every round start and 200
##   seeded random events;
## - every §5.3 key works, every control's tooltip names its key, and jumps land with the 0.5 s lead-in;
## - UX-8 (#221): the scrubber's moment markers sit at their moments' events, a click on one jumps there, and only the
##   kinds the battle has are drawn; the bar, the queue row, the Why tab, the plates, the centre, the caption and the
##   why panel fit and keep off each other at the three supported sizes, on the Simple view and the 3D stage alike;
## - the why panel's numbers are BattleExplain's for the current beat (and sum to the log's), its pinned
##   fighter is BattleExplain's explanation now, and the round's totals add up to the log's round_end;
## - every legend row is drawn by the screen's own drawing function and links a codex entry that exists;
## - the speed, the why panel, the legend and the first-visit hint are remembered in the settings file;
## - no raw id in any of it.

const Fx := preload("res://tests/battle_playback_fixtures.gd")
const STEP := 1.0 / 60.0
const DELTA := 0.0001
const RANDOM_POINTS := 200


func _fixture(name: String) -> Dictionary:
	var fx := Fx.battle(name)
	assert_false(fx.is_empty(), "battle %s loads" % name)
	return fx


func _view(fx: Dictionary) -> BattleSimpleView:
	var v := BattleSimpleView.new()
	v.controls.remember = false
	assert_eq(v.show_battle(fx.log, fx.report), "", "the battle plays")
	return v


func _key(code: Key, shift := false) -> InputEventKey:
	var k := InputEventKey.new()
	k.keycode = code
	k.pressed = true
	k.shift_pressed = shift
	return k


func _clear_settings() -> void:
	if FileAccess.file_exists(GameSettings.default_path):
		DirAccess.remove_absolute(GameSettings.default_path)


## Every round start and RANDOM_POINTS seeded random log events that are not attacks (the state between two
## attacks of a round is a fold in display order, not a timeline state).
func _points(fx: Dictionary, tl: BattleTimeline, salt: int) -> Array:
	var out := []
	for n in range(1, tl.rounds() + 1):
		out.append(tl.round_start(n))
	var events: Array = fx.log.events
	var rng := RandomNumberGenerator.new()
	rng.seed = 5900 + salt
	var guard := 0
	while out.size() < tl.rounds() + RANDOM_POINTS and guard < 100000:
		guard += 1
		var i := rng.randi_range(0, events.size() - 1)
		if events[i].t != "attack":
			out.append(i)
	return out


## The time (s at 1x) of the first beat showing event i.
func _time_of_event(p: BattlePlayer, i: int) -> float:
	p.seek(i)
	return float(p.beats()[p.next_beat()].t)


# --- the scrubber, seeking and playing ------------------------------------------------------------

func test_scrubbing_shows_the_timelines_state() -> void:
	var salt := 0
	for name in Fx.names():
		salt += 1
		var fx := _fixture(name)
		var p := BattlePlayer.new(fx.log, fx.report)
		var bar := BattleControls.new()
		bar.remember = false
		bar.bind(p, BattleFx.DEFAULTS)
		var tl := p.timeline()
		var beats := p.beats()
		var checked := 0
		for i in _points(fx, tl, salt):
			var t := _time_of_event(p, i)
			p.restart()
			bar.scrubber.scrubbed.emit(t)
			bar.scrubber.released.emit()
			assert_true(absf(p.time() - t) < 0.000001, "%s: the scrubber seeks to %.3f s" % [name, t])
			assert_false(p.is_playing(), "%s: scrubbing while paused stays paused" % name)
			# An attack that lands at the very time of a later event (the round's last attack and its first
			# wound) is not shown yet at that time; one step (".") lands it.
			while p.next_beat() < beats.size() and String(beats[p.next_beat()].kind).begins_with("attack_"):
				p.step()
			# The next beat that applies a log event other than an attack: the state before it is the timeline's.
			var b := p.next_beat()
			while b < beats.size() and (not BattlePlayer.APPLYING.has(beats[b].kind) or beats[b].kind == "attack_landed"):
				b += 1
			if b >= beats.size():
				assert_eq(p.state(), tl.final_state(), "%s: past the last event, the final state" % name)
				continue
			var j := int(beats[b].event)
			assert_eq(p.state(), tl.state_at(j), "%s: scrubbing to %.3f s shows the timeline's state before event %d" % [name, t, j])
			checked += 1
		assert_true(checked >= RANDOM_POINTS / 2, "%s: %d points checked" % [name, checked])
		# A click maps its x to the time under it.
		var x := bar.scrubber.x_of(p.duration() * 0.4)
		assert_true(absf(bar.scrubber.t_of(x) - p.duration() * 0.4) < 0.001, "%s: a click's x is its time" % name)
		bar.free()


## What the field shows of the battle's facts: every card's numbers, state and glyphs, both bars and their
## texts, the round counter and the caption (not positions: motions may be mid-way while playing).
func _field(v: BattleSimpleView) -> Array:
	var out := []
	for c in v._cards:
		out.append([c.hp, c.pending, c.alive, c.gone, c.glyphs.duplicate()])
	for k in 2:
		var b: BattleStrengthBar = v.bars[k]
		out.append([snappedf(b.fill, 0.0001), snappedf(b.pending_share, 0.0001), b.out, b.held, v.bar_texts[k].text])
	out.append(v.round_label.text)
	out.append(v.caption_labels[0].text)
	out.append(v.caption_labels[1].text)
	return out


func test_seeking_equals_playing_on_the_field() -> void:
	var salt := 100
	for name in Fx.names():
		salt += 1
		var fx := _fixture(name)
		var played := _view(fx)
		var seeker := _view(fx)
		var tl := played.player.timeline()
		var targets := {}
		for i in _points(fx, tl, salt):
			targets[maxf(0.0, _time_of_event(seeker.player, i) - DELTA)] = i
		var times := targets.keys()
		times.sort()
		seeker.player.restart()
		played.player.set_speed(4)
		played.player.play()
		var mismatches := 0
		for t in times:
			var guard := 0
			while played.player.time() < float(t) - 0.0000001 and played.player.is_playing() and guard < 100000:
				guard += 1
				var real := (float(t) - played.player.time()) / played.player.speed()
				played.tick(minf(STEP, maxf(real, 0.0000001)))
			seeker.player.seek_time(float(t))
			seeker.tick(0.0)
			var a := _field(played)
			var b := _field(seeker)
			if a != b and mismatches < 3:
				mismatches += 1
				for k in a.size():
					if a[k] != b[k]:
						fail("%s: at %.4f s (before event %d), played %s but seeked %s (item %d)" % [name, float(t), int(targets[t]),
							var_to_str(a[k]), var_to_str(b[k]), k])
						break
		assert_eq(mismatches, 0, "%s: the field after seeking equals the field after playing at %d points" % [name, times.size()])
		played.free()
		seeker.free()


func test_releasing_the_scrubber_resumes_from_the_nearest_rounds_attacks() -> void:
	var fx := _fixture("king_falls_wins")
	var v := _view(fx)
	var p := v.player
	p.play()
	var r2: float = float(p.round_times()[1].t)
	v.scrubber.scrubbed.emit(r2 + BattlePlayer.BANNER + 0.3)
	assert_false(p.is_playing(), "dragging pauses")
	v.scrubber.scrubbed.emit(r2 + BattlePlayer.BANNER + 0.2)
	assert_true(absf(p.time() - (r2 + BattlePlayer.BANNER + 0.2)) < 0.0001, "dragging follows the mouse")
	v.scrubber.released.emit()
	assert_true(p.is_playing(), "releasing resumes playing")
	assert_true(absf(p.time() - (r2 + BattlePlayer.BANNER)) < 0.0001, "from the start of round 2's attacks")
	p.pause()
	v.scrubber.scrubbed.emit(1.0)
	v.scrubber.released.emit()
	assert_false(p.is_playing(), "scrubbing while paused stays paused")
	assert_eq(p.time(), 1.0, "and stays where it was released")
	v.free()


# --- keys, tooltips, jumps --------------------------------------------------------------------------

func test_every_key_does_its_action() -> void:
	var fx := _fixture("king_falls_wins")
	var v := _view(fx)
	var p := v.player
	var tl := p.timeline()
	v._unhandled_input(_key(KEY_SPACE))
	assert_true(p.is_playing(), "Space plays")
	v._unhandled_input(_key(KEY_SPACE))
	assert_false(p.is_playing(), "Space pauses")
	for pair in [[KEY_2, 2], [KEY_3, 4], [KEY_1, 1]]:
		v._unhandled_input(_key(pair[0]))
		assert_eq(p.speed(), pair[1], "key %s: %dx" % [OS.get_keycode_string(pair[0]), pair[1]])
	v._unhandled_input(_key(KEY_RIGHT))
	assert_eq(p.state(), tl.state_at(tl.round_start(1)), "Right: round 1's start")
	v._unhandled_input(_key(KEY_RIGHT))
	assert_eq(p.state(), tl.state_at(tl.round_start(2)), "Right again: round 2's start")
	v._unhandled_input(_key(KEY_LEFT))
	assert_eq(p.state(), tl.state_at(tl.round_start(1)), "Left: back to round 1's start")
	v._unhandled_input(_key(KEY_LEFT))
	assert_eq(p.next_beat(), 0, "Left before round 1: the start of the battle")
	v._unhandled_input(_key(KEY_RIGHT))
	var before := p.next_beat()
	v._unhandled_input(_key(KEY_PERIOD))
	assert_true(p.next_beat() > before, "period steps one event while paused")
	v._unhandled_input(_key(KEY_COMMA))
	assert_eq(p.next_beat(), before, "comma steps back")
	v._unhandled_input(_key(KEY_END))
	assert_true(p.is_finished() and v.end_card.visible, "End: the result card")
	v._unhandled_input(_key(KEY_HOME))
	assert_eq(p.next_beat(), 0, "Home: the start")
	v._unhandled_input(_key(KEY_M))
	var first: Dictionary = p.moments()[0]
	assert_true(absf(p.time() - maxf(0.0, p.moment_time(first) - BattlePlayer.LEAD_IN)) < 0.0001, "M: the first key moment, with the lead-in")
	v._unhandled_input(_key(KEY_L))
	assert_true(v.legend.visible and v.controls.legend_open, "L opens the legend")
	v._unhandled_input(_key(KEY_ESCAPE))
	assert_false(v.legend.visible, "Esc closes the legend first")
	assert_true(v.visible, "and not the screen")
	var docked := v.why_panel.visible
	v._unhandled_input(_key(KEY_W))
	assert_eq(v.why_panel.visible, not docked, "W toggles the why panel")
	v._unhandled_input(_key(KEY_W))
	assert_eq(v.why_panel.visible, docked, "W again toggles it back")
	v._unhandled_input(_key(KEY_TAB))
	var first_fid: int = v._tab_order()[0]
	assert_eq(v.selection.selected, first_fid, "Tab selects the first fighter")
	v._unhandled_input(_key(KEY_TAB))
	assert_eq(v.selection.selected, int(v._tab_order()[1]), "Tab again: the next")
	v._unhandled_input(_key(KEY_TAB, true))
	assert_eq(v.selection.selected, first_fid, "Shift+Tab: back")
	v.controls.set_why(false, false)
	v._unhandled_input(_key(KEY_ENTER))
	assert_true(v.why_panel.visible, "Enter pins the selected fighter: the why panel opens")
	var opened := []
	v.codex_requested.connect(func(key): opened.append(key))
	v._on_card_hover(first_fid, true)
	v._unhandled_input(_f1())
	assert_eq(opened, [v.card(first_fid).codex_key], "F1 opens the hovered fighter's codex entry")
	v._on_card_hover(first_fid, false)
	p.skip_to_end()
	v._unhandled_input(_key(KEY_R))
	assert_true(p.is_playing() and not v.end_card.visible, "R on the result card watches again")
	var closed := [false]
	v.closed.connect(func(): closed[0] = true)
	v._unhandled_input(_key(KEY_ESCAPE))
	assert_true(closed[0] and not v.visible, "Esc with the legend closed closes the screen")
	v.free()


func _f1() -> InputEventKey:
	return _key(KEY_F1)


func test_every_control_names_its_key() -> void:
	var v := _view(_fixture("king_falls_wins"))
	var keys := BattleControls.KEYS
	var want := {"restart": keys.restart, "play": keys.play, "speed1": keys.speed1, "speed2": keys.speed2, "speed4": keys.speed4,
		"skip": keys.skip, "legend": keys.legend, "why": keys.why, "close": keys.close}
	for id in want:
		var b: Button = v.controls.buttons[id]
		assert_true(b.tooltip_text.contains("(%s)" % want[id]) or b.tooltip_text.contains("(%s " % want[id]), "%s's tooltip names its key %s: %s" % [b.text, want[id], b.tooltip_text])
		assert_eq(b.focus_mode, Control.FOCUS_NONE, "%s never takes the keyboard (Space stays play / pause, Tab selects)" % b.text)
	for m in v.scrubber.marks:
		assert_true(String(m.tip).replace("\n", " ").contains("M jumps to the next key moment"), "the %s marker names M" % m.kind)
	assert_true(v.why_panel.close_button.tooltip_text.contains("(%s)" % keys.why), "the why panel's x names W")
	v.player.play()
	assert_true(v.controls.buttons.play.tooltip_text.contains("Pause (Space)"), "Pause names Space too")
	assert_false(BattleControls.KEYS.is_empty())
	v.free()


func test_jumps_land_on_their_moment_with_the_lead_in() -> void:
	for name in ["king_falls_wins", "knights_charge", "border", "biggest"]:
		var fx := _fixture(name)
		var v := _view(fx)
		var p := v.player
		var marks: Array = v.scrubber.marks
		assert_eq(marks.size(), BattleMoments.key_moments(fx.log).size(), "%s: one marker per key moment" % name)
		for i in marks.size():
			var m: Dictionary = marks[i]
			p.restart()
			v.scrubber._gui_input(_click(v.scrubber.mark_point(i)))
			var at := maxf(0.0, float(m.t) - BattlePlayer.LEAD_IN)
			assert_true(absf(p.time() - at) < 0.0001, "%s: the %s marker lands %.1f s before its moment" % [name, m.kind, BattlePlayer.LEAD_IN])
			assert_false(p.is_playing(), "%s: a jump keeps pause" % name)
			# Playing on, the moment's beat fires within the lead-in, on its event.
			var fired := {}
			p.play()
			var guard := 0
			while fired.is_empty() and guard < 200:
				guard += 1
				for fb in p.advance(STEP):
					if fb.kind == "moment" and fb.data.kind == m.kind:
						fired = fb
			assert_eq(int(fired.get("event", -1)), int(m.event), "%s: %s fires on its moment's event" % [name, m.kind])
			assert_true(guard * STEP * p.speed() <= BattlePlayer.LEAD_IN + 0.6 + STEP * 4, "%s: within the lead-in" % name)
			p.pause()
		v.free()


func _click(at: Vector2, button := MOUSE_BUTTON_LEFT, pressed := true) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
	e.position = at
	return e


## UX-8 (§6): every key moment is a marker on the scrubber at its event's place (its beat's time), with today's words, a
## jump on a click and its codex entry on a right-click; a kind the battle lacks has no marker, and the scrubber says why.
func test_moment_markers_sit_at_their_events_and_only_the_kinds_the_battle_has() -> void:
	for name in Fx.names():
		var fx := _fixture(name)
		var v := _view(fx)
		var p := v.player
		var want := BattleMoments.key_moments(fx.log)
		var marks: Array = v.scrubber.marks
		assert_eq(marks.size(), want.size(), "%s: a marker per moment" % name)
		var kinds := {}
		for m in want:
			kinds[String(m.kind)] = true
			var found := marks.filter(func(k): return k.kind == m.kind and int(k.event) == int(m.event))
			assert_eq(found.size(), 1, "%s: the %s at event %d has its marker" % [name, m.kind, int(m.event)])
			if found.is_empty():
				continue
			assert_true(absf(float(found[0].t) - p.moment_time(m)) < 0.0001, "%s: at its beat's time" % name)
			assert_true(String(found[0].tip).replace("\n", " ").contains(String(m.text)), "%s: its tooltip is the moment's words" % name)
		for m in marks:
			assert_true(kinds.has(String(m.kind)), "%s: no marker of a kind the battle lacks (%s)" % [name, m.kind])
			assert_true(RulesCodex.ENTRIES.has(String(m.codex)), "%s: the %s marker links a codex entry" % [name, m.kind])
		var missing := BattleMoments.missing(fx.log)
		for kind in missing:
			if kind == "spell" and not fx.log.get("magic", false):
				continue
			var why_not := String(missing[kind])
			assert_true(v.scrubber.missing_lines.any(func(l): return String(l).ends_with(why_not)), "%s: the scrubber says why there is no %s" % [name, kind])
		# The markers stand apart: two that would overlap stack in two lanes.
		for i in marks.size():
			for j in range(i + 1, marks.size()):
				var d: Vector2 = v.scrubber.mark_point(i) - v.scrubber.mark_point(j)
				assert_true(absf(d.x) >= BattleScrubber.MARK or absf(d.y) >= BattleScrubber.MARK - 0.1,
					"%s: markers %d and %d don't sit on each other" % [name, i, j])
		v.free()
	# Hover, F1 and right-click: the marker's own codex entry; a click on the bare line still scrubs.
	var fx2 := _fixture("king_falls_wins")
	var w := _view(fx2)
	var sc := w.scrubber
	assert_false(sc.marks.is_empty())
	var opened := []
	w.codex_requested.connect(func(key): opened.append(key))
	var mm := InputEventMouseMotion.new()
	mm.position = sc.mark_point(0)
	sc._gui_input(mm)
	assert_eq(sc.hovered, 0, "hovering a marker lights it")
	assert_eq(CodexLink.key_at(sc), String(sc.marks[0].codex), "F1 over it finds its codex entry")
	assert_eq(sc._get_tooltip(sc.mark_point(0)), String(sc.marks[0].tip), "and its tooltip is the moment's")
	sc._gui_input(_click(sc.mark_point(0), MOUSE_BUTTON_RIGHT))
	assert_eq(opened, [String(sc.marks[0].codex)], "a right-click opens it")
	sc._notification(Control.NOTIFICATION_MOUSE_EXIT)
	assert_eq(CodexLink.key_at(sc), "", "leaving the scrubber drops it")
	sc._gui_input(_click(Vector2(sc.x_of(2.0), sc.line_y())))
	assert_true(absf(w.player.time() - 2.0) < 0.0001, "a click on the line seeks there")
	sc._gui_input(_click(Vector2(sc.x_of(2.0), sc.line_y()), MOUSE_BUTTON_LEFT, false))
	w.free()


# --- the why panel ----------------------------------------------------------------------------------

## The attack event that landed last in the current round, worked out from the beats directly.
func _last_attack(p: BattlePlayer) -> int:
	var beats := p.beats()
	for k in range(p.next_beat() - 1, -1, -1):
		var b: Dictionary = beats[k]
		if b.kind == "round_start":
			return -1
		if b.kind == "attack_landed":
			return int(b.event)
	return -1


func _values(bd: Dictionary) -> Array:
	var out := []
	for l in bd.lines:
		out.append(int(l.value))
	return out


func _sum(values: Array) -> int:
	var s := 0
	for x in values:
		s += int(x)
	return s


func test_the_why_panel_shows_battle_explain_for_the_current_beat() -> void:
	for name in ["king_falls_wins", "forest_fort", "iron_discipline", "skirmish", "dread_feast_frenzy", "path_iron_hide"]:
		var fx := _fixture(name)
		var v := _view(fx)
		var p := v.player
		var tl := p.timeline()
		var panel := v.why_panel
		assert_true(panel.visible, "%s: the why panel is open by default" % name)
		var beats := p.beats()
		var fid := int(fx.log.sides[0].fighters[0])
		v.selection.select(fid)
		var attacks_seen := 0
		for k in range(0, beats.size(), maxi(1, beats.size() / 60)) + [beats.size()]:
			if k < beats.size():
				p.seek_beat(k)
			else:
				p.skip_to_end()
			var ev := _last_attack(p)
			assert_eq(int(panel.shown.attack_event), ev, "%s: at beat %d the panel explains the attack that landed last" % [name, k])
			if ev >= 0:
				attacks_seen += 1
				var ex := BattleExplain.explain_attack(fx.log, ev)
				var e: Dictionary = fx.log.events[ev]
				assert_eq(panel.shown.chance_values, _values(ex.chance), "%s: hit chance lines are BattleExplain's" % name)
				assert_eq(int(panel.shown.chance_total), int(e.chance), "%s: the hit chance is the log's" % name)
				assert_eq(_sum(panel.shown.chance_values), int(e.chance), "%s: the hit chance lines sum to it" % name)
				assert_eq(panel.shown.damage_values, _values(ex.damage), "%s: damage lines are BattleExplain's" % name)
				assert_eq(int(panel.shown.damage_total), int(e.damage), "%s: the damage is the log's" % name)
				assert_eq(_sum(panel.shown.damage_values), int(e.damage), "%s: the damage lines sum to it" % name)
				assert_eq(panel.attack_summary.text, String(ex.summary), "%s: the summary line is BattleExplain's" % name)
				assert_eq(panel.roll_label.text, String(ex.roll), "%s: the roll is BattleExplain's" % name)
				var shown_total: Label = panel.chance_grid.get_child((ex.chance.lines.size() + 1) * 2 + 1)
				assert_eq(shown_total.text, "%d%%" % int(e.chance), "%s: the grid shows the total" % name)
			# Morale checks this round so far.
			var morale := []
			for kk in range(p.next_beat() - 1, -1, -1):
				if beats[kk].kind == "round_start":
					break
				if beats[kk].kind == "morale":
					morale.push_front(BattleExplain.explain_morale(fx.log, int(beats[kk].event)))
			if p.next_beat() < beats.size():
				assert_eq(panel.shown.morale_events, morale, "%s: the round's morale checks are BattleExplain's" % name)
			# The pinned fighter: BattleExplain's explanation at this point.
			var st := p.state()
			assert_eq(panel.shown.selected_lines, BattleExplain.explain_fighter(tl, fid, int(st.event), st).lines,
				"%s: the pinned fighter's explanation is BattleExplain's now" % name)
		assert_true(attacks_seen > 0, "%s: attacks were checked" % name)
		# At each round's end, the round's totals are the log's round_end numbers.
		var why := BattleWhy.new(p)
		for b in beats:
			if b.kind != "round_end":
				continue
			var re: Dictionary = fx.log.events[int(b.event)]
			var m := why.at(int(b.i) + 1, tl.state_at(int(b.event) + 1))
			for si in fx.log.sides.size():
				var t: Dictionary = m.totals[si]
				assert_eq([t.attacks, t.hits, t.dealt], [int(re.attacks[si]), int(re.hits[si]), int(re.dealt[si])],
					"%s round %d: side %d's totals are the log's" % [name, int(re.n), si])
				assert_true(absf(float(t.expected) - float(re.expected[si])) < 0.6, "%s: expected damage adds up" % name)
		v.free()


func test_the_why_panel_follows_playback_and_its_feed_jumps() -> void:
	var fx := _fixture("king_falls_wins")
	var v := _view(fx)
	var p := v.player
	var panel := v.why_panel
	p.set_speed(4)
	p.play()
	var guard := 0
	while p.round_now() < 2 and guard < 5000:
		v.tick(STEP)
		guard += 1
	# While playing, it refreshes at most every LIVE_INTERVAL; one more interval and it is current.
	for k in int(BattleWhyPanel.LIVE_INTERVAL / STEP) + 2:
		v.tick(STEP)
	p.pause()
	assert_eq(int(panel.shown.position), p.next_beat(), "after a pause the panel shows the playhead")
	assert_true(String(panel.now_label.text).begins_with("Round 2"), "Now: round 2 (%s)" % panel.now_label.text)
	# The caption is BattleCaptions' for the round that ended last.
	assert_eq(panel.shown.caption, p.caption(1), "the caption on the panel is round 1's")
	# The feed: each entry jumps right after its beat, where the panel explains it.
	p.skip_to_end()
	p.seek_round(1)
	var why := BattleWhy.new(p)
	var end_of_r1 := -1
	for b in p.beats():
		if b.kind == "round_end" and int(b.round) == 1:
			end_of_r1 = int(b.i)
	p.seek_beat(end_of_r1)
	var feed: Array = why.at(p.next_beat(), p.live_state()).feed
	assert_true(not feed.is_empty(), "round 1 has notable events")
	var entry: Dictionary = feed[0]
	var button: Button = panel.feed_box.get_child(0)
	assert_eq(button.text, "• " + String(entry.text), "the feed shows the entry")
	assert_true(RulesCodex.ENTRIES.has(CodexLink.key_at(button)), "and links its codex entry")
	button.pressed.emit()
	assert_eq(p.next_beat(), int(entry.beat) + 1, "clicking it jumps right after it")
	if p.beats()[int(entry.beat)].kind == "attack_landed":
		assert_eq(int(panel.shown.attack_event), int(entry.event), "where the panel explains that attack")
	v.free()


func test_factor_chips_light_up_in_the_rounds_they_matter() -> void:
	var lit_any := false
	for name in Fx.names():
		var fx := _fixture(name)
		var p := BattlePlayer.new(fx.log, fx.report)
		var why := BattleWhy.new(p)
		var factors: Array = fx.report.get("factors", [])
		var at_end := why.at(p.beats().size(), p.timeline().final_state())
		assert_true(at_end.chips.size() <= factors.size(), "%s: one chip per chosen factor at most" % name)
		for b in p.beats():
			if b.kind != "round_end":
				continue
			var m := why.at(int(b.i) + 1, p.timeline().state_at(int(b.event) + 1))
			for c in m.chips:
				assert_true(RulesCodex.ENTRIES.has(String(c.codex)), "%s: each chip links an entry" % name)
				if c.lit:
					lit_any = true
					assert_true(String(c.text).contains("this round"), "%s: a lit chip says it mattered this round: %s" % [name, c.text])
					if not BattleLog._non_impact(String(c.id)):
						var re: Dictionary = fx.log.events[int(b.event)]
						assert_eq(roundi(float(c.worth)), roundi(float(re.impact[int(c.side)].get(c.id, 0.0))), "%s: its worth is the log's impact" % name)
	assert_true(lit_any, "some chip lights up somewhere")


# --- the legend ---------------------------------------------------------------------------------------

## The screen's drawing code: every ui/battle script but the legend's own.
func _screen_sources() -> String:
	var out := ""
	for f in DirAccess.get_files_at("res://ui/battle"):
		if f.ends_with(".gd") and f != "battle_legend.gd":
			out += FileAccess.get_file_as_string("res://ui/battle".path_join(f)) + "\n"
	out += FileAccess.get_file_as_string("res://ui/seat_emblem.gd")
	return out


func _class_script(class_name_text: String) -> Script:
	for c in ProjectSettings.get_global_class_list():
		if String(c["class"]) == class_name_text:
			return load(String(c.path))
	return null


func test_every_legend_row_is_drawn_by_the_screens_own_function_and_links_the_codex() -> void:
	var rows := BattleLegend.overlay_rows() + BattleLegend.field_rows()
	var src := _screen_sources()
	var ids := {}
	for r in rows:
		assert_false(ids.has(r.id), "row %s is listed once" % r.id)
		ids[r.id] = true
		assert_true(RulesCodex.ENTRIES.has(String(r.codex)), "%s links a codex entry that exists (%s)" % [r.id, r.codex])
		assert_false(String(r.title).is_empty() or String(r.text).is_empty(), "%s has a title and a meaning" % r.id)
		var parts := String(r.drawn_by).split(".")
		assert_eq(parts.size(), 2, "%s names its drawing function" % r.id)
		var script := _class_script(parts[0])
		assert_true(script != null, "%s: %s is a class" % [r.id, parts[0]])
		if script == null:
			continue
		var is_static := false
		for m in script.get_script_method_list():
			if String(m.name) == parts[1] and (int(m.flags) & METHOD_FLAG_STATIC) != 0:
				is_static = true
		assert_true(is_static, "%s: %s is a static function" % [r.id, r.drawn_by])
		# The screen itself draws with it: called somewhere in the screen's code, not only defined.
		var calls := src.count(parts[1] + "(") - src.count("func " + parts[1] + "(")
		assert_true(calls >= 1, "%s: the screen draws with %s" % [r.id, r.drawn_by])
		assert_true((r.draw as Callable).is_valid() or r.has("node"), "%s draws something" % r.id)
		if r.has("reduced"):
			assert_false(String(r.reduced).is_empty(), "%s says what reduced motion does" % r.id)
	# §7.1's list, and #59's: every mark on the screen has a row.
	for want in ["emblem", "card", "ruler", "commander", "ranks", "hp_bar", "fallen", "strength_bar", "strength_pending", "notch", "tag", "broke",
			"no_one_left", "aura_up", "aura_down", "shield_wall", "berserk", "blood_frenzy", "pack_leader", "shielded", "exposed", "iron",
			"bolt", "javelin", "arcane", "wings", "impact", "big_impact", "shake", "number", "miss", "heal", "iron_hide", "rout_slide", "lunge", "dust",
			"moment_first_blood", "moment_charge", "moment_ruler_falls", "moment_turning_point", "moment_rout"]:
		assert_true(ids.has(want), "the legend has a row for %s" % want)
	# Every status glyph the cards can show has its row.
	for g in BattleCard.GLYPHS:
		assert_true(ids.has(g), "the glyph %s has a legend row" % g)


func test_the_legend_opens_lists_every_row_and_opens_the_codex() -> void:
	var v := _view(_fixture("forest_fort"))
	assert_false(v.legend.visible, "the legend starts closed")
	v.controls.buttons.legend.pressed.emit()
	assert_true(v.legend.visible, "the Legend button opens it")
	var rows := BattleLegend.overlay_rows() + BattleLegend.field_rows()
	assert_eq(v.legend.row_nodes.size(), rows.size(), "one row on screen per mark")
	var opened := []
	v.codex_requested.connect(func(key): opened.append(key))
	for k in v.legend.row_nodes.size():
		var row: Control = v.legend.row_nodes[k]
		assert_eq(CodexLink.key_at(row), String(rows[k].codex), "row %s links its entry" % rows[k].id)
		assert_true(row.tooltip_text.contains("Codex: "), "and its tooltip names it")
	(v.legend.row_nodes[0] as Control).gui_input.emit(CodexLink.right_click())
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	(v.legend.row_nodes[1] as Control).gui_input.emit(click)
	assert_eq(opened, [String(rows[0].codex), String(rows[1].codex)], "right-click and click open the codex")
	v.reduced_motion = true
	v.legend.reduced_motion = true
	var texts := " ".join(v.legend.visible_texts())
	assert_true(texts.contains("With reduced motion, attacks play in place"), "with reduced motion the motion rows say so")
	v.free()


# --- selection, docking -----------------------------------------------------------------------------

func test_tab_and_clicks_select_a_fighter_and_pin_it() -> void:
	var fx := _fixture("king_falls_wins")
	var v := _view(fx)
	var order := v._tab_order()
	var left := int(v.layout.left)
	assert_eq(order.size(), fx.log.fighters.size(), "every fighter is in the Tab order")
	var seen_right := false
	var last_tier := -1
	for fid in order:
		var slot: Dictionary = v.layout.slots[fid]
		if int(slot.side) != left:
			if not seen_right:
				last_tier = -1
			seen_right = true
		else:
			assert_false(seen_right, "the left side comes first")
		assert_true(int(slot.tier) >= last_tier, "front rank to back line")
		last_tier = int(slot.tier)
	v.selection.next()
	var fid0: int = order[0]
	assert_true(v.card(fid0).selected, "the selected card keeps its outline")
	v.card(order[1])._gui_input(_left_click())
	assert_eq(v.selection.selected, int(order[1]), "a click selects")
	assert_false(v.card(fid0).selected, "and the other card loses its outline")
	assert_eq(v.why_panel.shown.selected, int(order[1]), "the why panel pins it")
	v.card(order[1])._gui_input(_left_click())
	assert_eq(v.selection.selected, -1, "a second click clears it")
	# Fighters that left the field are skipped.
	v.player.skip_to_end()
	var fin := v.player.timeline().final_state()
	for k in order.size() + 1:
		var f := v.selection.next()
		var fs: Dictionary = fin.fighters[f]
		assert_false(fs.alive and (fs.fled or fs.lost), "Tab skips fighters that left the field")
	# A click on a card opens a closed why panel.
	v.controls.set_why(false, false)
	v.selection.clear()
	v.card(fid0)._gui_input(_left_click())
	assert_true(v.why_panel.visible, "clicking a card pins it in the why panel, opening it")
	v.free()


func _left_click() -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	return e


func test_the_why_panel_docks_beside_a_narrower_field_or_floats_over_a_crowd() -> void:
	var v := _view(_fixture("starting_plains"))
	var docked_w := BattleSimpleView.BASE.x - BattleSimpleView.WHY_W
	assert_eq(v.field_width(), docked_w, "docked: the band is the view less the panel")
	for f in v._log.fighters:
		assert_true((v.layout.slots[int(f.id)].rect as Rect2).end.x + v.cards_layer.position.x <= v.why_panel.position.x, "every card is left of the panel")
	v.controls.set_why(false, false)
	assert_eq(v.field_width(), BattleSimpleView.BASE.x, "closed: the full width")
	assert_false(v.why_panel.visible, "and the panel is hidden")
	for f in v._log.fighters:
		assert_eq(v.card(int(f.id)).hp, int(v.player.live_state().fighters[int(f.id)].hp), "the field was rebuilt on the same state")
	v.free()
	var big := _view(_fixture("biggest"))
	assert_false(big.why_panel.visible, "the biggest battle only fits the narrow field as a crowd: the panel starts collapsed")
	assert_eq(big.field_width(), BattleSimpleView.BASE.x, "with the full-width field")
	big.controls.set_why(true, false)
	assert_true(big.why_panel.visible, "Why opens it")
	assert_eq(big.field_width(), BattleSimpleView.BASE.x, "over the field, which keeps its width")
	big.free()


# --- the layout (UX-8) ------------------------------------------------------------------------------

## The logical sizes the viewer is laid out at: a 1600x900 (or 1280x720) window at 100%, and 1600x900 at 125%.
const VIEWS := [Vector2(1600, 900), Vector2(1280, 720)]


func _rect(c: Control) -> Rect2:
	return Rect2(c.position, c.size)


## Every piece of the viewer's HUD that is on screen now, by name: the plates, the centre, the caption, the bar, the queue
## row and the Why tab (the controls are a full-view layer at 0, 0), the why panel and the result card.
func _pieces(v: BattleSimpleView) -> Dictionary:
	var out := {"plate left": _rect(v.plates[0]), "plate right": _rect(v.plates[1]), "centre": _rect(v.centre),
		"bar": _rect(v.controls.bar), "why tab": _rect(v.controls.buttons.why)}
	if v.caption_strip.visible:
		out["caption"] = _rect(v.caption_strip)
	if v.controls.queue_row.visible:
		out["queue row"] = _rect(v.controls.queue_row)
	if v.why_panel.visible:
		out["why panel"] = _rect(v.why_panel)
	if v.end_card.visible:
		out["result card"] = _rect(v.end_card)
	return out


func _assert_fits(v: BattleSimpleView, what: String) -> void:
	var view := Rect2(Vector2.ZERO, v.view_size())
	var pieces := _pieces(v)
	for name in pieces:
		var r: Rect2 = pieces[name]
		assert_true(view.grow(0.5).encloses(r), "%s: the %s is inside the view (%s in %s)" % [what, name, r, view])
	var names := pieces.keys()
	for i in names.size():
		for j in range(i + 1, names.size()):
			var a: Rect2 = pieces[names[i]]
			var b: Rect2 = pieces[names[j]]
			assert_true(a.intersection(b).get_area() <= 1.0, "%s: the %s and the %s keep apart (%s, %s)" % [what, names[i], names[j], a, b])
	var band := v.stage_band()
	assert_true(band.position.y >= v.plates[0].position.y + v.plates[0].size.y, "%s: the stage's band starts under the plates" % what)
	assert_true(band.end.y <= v.view_size().y - v.controls.bottom_reserve(), "%s: and ends above the controls" % what)
	assert_true(v.caption_strip.position.y >= v.view_size().y * 2.0 / 3.0 - 0.5, "%s: the caption is in the lower third" % what)
	assert_ne(v.caption_strip.visible, v.end_card.visible, "%s: the result card stands in for the caption" % what)
	if pieces.has("why panel") and v._why_docks:
		assert_true(band.end.x <= v.why_panel.position.x + 0.5, "%s: the band ends at the docked why panel" % what)
	if pieces.has("result card"):
		var r: Rect2 = pieces["result card"]
		assert_true(r.position.x >= band.position.x and r.end.x <= band.end.x + 0.5 and r.position.y >= band.position.y, "%s: the result card is inside the band" % what)


## UX-8 (§6, and #221's before shot at 1600x900 at 125%, where the old fixed 1600x900 frame lost its right side and its
## controls): at every supported size, both views lay every piece inside the view and keep the pieces apart, with the
## why panel open or closed, with and without the queue row, and with the result card up.
func test_the_viewer_fits_every_size_with_its_pieces_apart() -> void:
	for at in VIEWS:
		for kind in ["simple", "3d"]:
			for name in ["king_falls_wins", "biggest", "round_cap_defender"]:
				var fx := _fixture(name)
				var v: BattleSimpleView = BattleSimpleView.new() if kind == "simple" else BattleStage3D.new()
				v.controls.remember = false
				v.size = at
				assert_eq(v.show_battle(fx.log, fx.report), "", "the battle plays")
				var what := "%s %s at %s" % [kind, name, at]
				_assert_fits(v, what + ", why as remembered")
				v.controls.set_why(not v.controls.why_open, false)
				_assert_fits(v, what + ", why toggled")
				v.controls.set_queue(1, 3, "Battle of Thornvale")
				assert_true(v.controls.queue_row.visible, "the queue row shows")
				_assert_fits(v, what + ", in a queue")
				v.controls.set_why(true, false)
				_assert_fits(v, what + ", in a queue, why open")
				v.player.skip_to_end()
				assert_true(v.end_card.visible, "the result card is up")
				_assert_fits(v, what + ", at the result")
				v.controls.set_queue(0, 1)
				assert_false(v.controls.queue_row.visible, "one battle: no queue row")
				_assert_fits(v, what + ", out of the queue")
				v.free()


## UX-8: a resize lays the battle out again on the same state: the band, the cards (Simple view) and the plates follow the
## new size.
func test_a_resize_lays_the_battle_out_again() -> void:
	var fx := _fixture("king_falls_wins")
	var v := _view(fx)
	v.player.seek_round(2)
	var hp := []
	for f in fx.log.fighters:
		hp.append(v.card(int(f.id)).hp)
	var before := v.stage_band()
	v.size = Vector2(1280, 720)
	v._layout()
	assert_ne(v.stage_band(), before, "the band follows the view")
	_assert_fits(v, "resized to 1280x720")
	for f in fx.log.fighters:
		var r: Rect2 = v.layout.slots[int(f.id)].rect
		assert_true(Rect2(Vector2.ZERO, v.stage_band().size).encloses(r), "%s's card is inside the new band" % f.name)
		assert_eq(v.card(int(f.id)).hp, int(hp[fx.log.fighters.find(f)]), "on the same state")
	v.free()


## UX-8 (§6): the Simple view and the 3D stage are built from the one BattleControls, with the same markers and keys.
func test_both_views_share_the_one_controls_component() -> void:
	var fx := _fixture("king_falls_wins")
	var a := _view(fx)
	var b := BattleStage3D.new()
	b.controls.remember = false
	assert_eq(b.show_battle(fx.log, fx.report), "")
	for v in [a, b]:
		assert_true(v.controls is BattleControls, "%s hosts BattleControls" % v.name)
		assert_true(v.controls.get_parent() == v.frame, "%s: on its frame" % v.name)
		assert_eq(v.scrubber, v.controls.scrubber, "%s: its scrubber is the controls'" % v.name)
		assert_eq(v.buttons, v.controls.buttons, "%s: and its buttons" % v.name)
	assert_eq(a.scrubber.marks, b.scrubber.marks, "the same markers on both")
	assert_eq(a.controls.buttons.keys(), b.controls.buttons.keys(), "the same buttons")
	assert_true(b.controls.reframe_key and not a.controls.reframe_key, "F reframes only the 3D stage's camera")
	a.free()
	b.free()


# --- settings -------------------------------------------------------------------------------------

func test_the_speed_panels_and_hint_are_remembered() -> void:
	_clear_settings()
	var fx := _fixture("skirmish")
	var a := BattleSimpleView.new()
	a.show_battle(fx.log, fx.report)
	assert_eq(a.player.speed(), 1, "the first battle ever plays at 1x")
	assert_true(a.why_panel.visible, "with the why panel open")
	assert_false(a.legend.visible, "and the legend closed")
	assert_true(a.hint_button.visible, "the first-visit hint has its Got it")
	a.controls.buttons.speed4.pressed.emit()
	a._unhandled_input(_key(KEY_W))
	a._unhandled_input(_key(KEY_L))
	a.hint_button.pressed.emit()
	assert_false(a.hint_button.visible, "Got it hides the hint")
	assert_ne(a.caption_labels[0].text, BattleSimpleView.FIRST_HINT, "and its line")
	var st := BattleFx.settings()
	assert_eq([st.speed, st.why_panel_open, st.legend_open, st.first_hint_seen], [4, false, true, true], "all four are in the settings file")
	a.free()
	var b := BattleSimpleView.new()
	b.show_battle(fx.log, fx.report)
	assert_eq(b.player.speed(), 4, "the next battle plays at the last speed")
	assert_false(b.why_panel.visible, "with the why panel as it was left")
	assert_true(b.legend.visible, "and the legend")
	assert_false(b.hint_button.visible, "and no hint")
	# A speed set by code (the launcher's --speed) is not a choice: it isn't remembered.
	b.player.set_speed(2)
	assert_eq(BattleFx.settings().speed, 4, "only a player's choice is remembered")
	b.free()
	# The game's own settings keep the battle section when they are saved.
	var gs := GameSettings.load_from()
	gs.set_ui_scale(125)
	assert_eq(gs.save(), "")
	assert_eq(BattleFx.settings().speed, 4, "saving the game settings keeps [battle]")
	assert_eq(GameSettings.load_from().ui_scale, 125, "and their own")
	assert_eq(BattleFx.save_settings({"speed": 3, "nonsense": true}), "", "unknown keys and speeds are ignored")
	assert_eq(BattleFx.settings().speed, 4, "the speed stays")
	_clear_settings()


# --- no raw ids -------------------------------------------------------------------------------------

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
	return ids.keys()


func test_no_raw_ids_in_the_controls_panel_or_legend() -> void:
	var snake := RegEx.create_from_string("[a-z]+_[a-z_]+")
	var word := RegEx.create_from_string("[A-Za-z0-9_-]+")
	for name in Fx.names():
		var fx := _fixture(name)
		var v := _view(fx)
		var ids := _raw_ids(fx.log)
		var texts := []
		v.selection.next()
		var tl := v.player.timeline()
		for n in range(1, tl.rounds() + 1):
			for b in v.player.beats():
				if b.kind == "caption" and int(b.round) == n:
					v.player.seek_beat(int(b.i) + 1)
			texts.append_array(v.why_panel.visible_texts())
		v.player.skip_to_end()
		texts.append_array(v.why_panel.visible_texts())
		texts.append_array(v.controls.visible_texts())
		texts.append_array(v.legend.visible_texts())
		for t in texts:
			var text := String(t)
			assert_true(snake.search(text) == null, "%s: no snake_case id in \"%s\"" % [name, text])
			var words := {}
			for m in word.search_all(text):
				words[m.get_string()] = true
			for id in ids:
				assert_false(words.has(id), "%s: no raw id '%s' in \"%s\"" % [name, id, text])
		v.free()
