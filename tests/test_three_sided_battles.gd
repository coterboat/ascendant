extends "res://tests/test_case.gd"
## #265: battles with three sides can be watched. A Free Holds garrison caught between two players makes a three-sided
## battle today (and the Candlewake will make more): the rules resolve it and its log carries every side, and now the Simple
## view and the 3D stage play it. Each side has its own colour, banner, plate and place on the field (the camera frames them
## all); the scrubber, the cards and the hover text work for every side; and the playback's why lines name each side.
## Two-sided battles play exactly as before (their own tests run unchanged; the last test here checks a view that showed
## three sides shows two exactly as a fresh one does). The battles are tests/three_side_fixtures.gd: constructed turns
## fought by the real rules. Expected values come from the logs, the timeline and the data, never from this file.

const T := preload("res://tests/three_side_fixtures.gd")
const Fx := preload("res://tests/battle_playback_fixtures.gd")
const Formation := preload("res://world3d/battle_formation.gd")
const Walls := preload("res://world3d/battle_walls.gd")
const Cam := preload("res://world3d/battle_camera.gd")
const W3D := preload("res://world3d/battle_watch3d.gd")
const Watch := preload("res://ui/battle/battle_watch.gd")
const STEP := 1.0 / 60.0
const HOLDS := IndependentData.FACTION_ID


func _fixture(name: String) -> Dictionary:
	var fx := T.battle(name)
	assert_false(fx.is_empty(), "the three-sided battle %s is fought" % name)
	return fx


func _view(fx: Dictionary) -> BattleSimpleView:
	var v := BattleSimpleView.new()
	assert_eq(v.show_battle(fx.log, fx.report, fx.seats), "", "the three-sided battle plays in the Simple view")
	return v


func _stage(fx: Dictionary) -> BattleStage3D:
	var s := BattleStage3D.new()
	s.dive_from_board = false
	assert_eq(s.play(fx.log, fx.report, fx.state, fx.seats), "", "the three-sided battle plays on the 3D stage")
	return s


func _play_out(v: BattleSimpleView, speed: int) -> void:
	v.player.set_speed(speed)
	v.player.play()
	var frames := 0
	while not v.player.is_finished() and frames < 100000:
		v.tick(STEP)
		frames += 1
	for k in 150:
		v.tick(STEP)


## The seat each side's colour and emblem come from (the fixture's seat order; the Free Holds have none).
func _seat(fx: Dictionary, si: int) -> int:
	return (fx.seats as Array).find(String(fx.log.sides[si].faction))


## Side `si`'s name as the playback writes it.
func _name(fx: Dictionary, si: int) -> String:
	return String(fx.log.sides[si].name)


# --- the battles -------------------------------------------------------------------------------------------

func test_the_battles_are_three_sided_and_fought_by_the_rules() -> void:
	for name in T.names():
		var fx := _fixture(name)
		var lg: Dictionary = fx.log
		assert_eq(lg.sides.size(), 3, "%s: three sides fought" % name)
		assert_eq(BattleLog.validate(lg), [], "%s: its log is valid" % name)
		var attacked := {}
		for e in lg.events:
			if e.t == "attack":
				attacked[int(lg.fighters[int(e.by)].side)] = true
		assert_eq(attacked.size(), 3, "%s: every side attacked" % name)
		for sd in lg.sides:
			assert_true(Array(fx.event.factions).has(String(sd.faction)), "%s: the event names %s among its factions" % [name, sd.name])
	for name in ["holds", "fort"]:
		var lg2: Dictionary = _fixture(name).log
		assert_eq(String(lg2.defender), HOLDS, "%s: the Free Holds garrison holds the ground" % name)
	assert_true(_fixture("holds").log.get("siege", {}).is_empty(), "the hold's battle stands on open ground")
	assert_eq(String(_fixture("fort").log.siege.kind), "open", "the neutral keep's battle is fought in the open before its walls")
	assert_false((_fixture("rivals").log.siege.from_inside as Array).is_empty(), "at the besieged keep the garrison comes out of the gate")


func test_a_three_sided_battle_can_be_watched_from_the_report() -> void:
	for name in T.names():
		var fx := _fixture(name)
		assert_eq(BattlePlayer.playback_problem(fx.log), "", "%s: the log plays back" % name)
		assert_eq(BattleHost.watch_problem(fx.event), "", "%s: the Watch button is on" % name)
		assert_eq(BattleHost.watchable([fx.event]).size(), 1, "%s: and it is in the battles to watch" % name)
	var path := GameSettings.default_path.get_base_dir().path_join("three_sided_host_%d.cfg" % OS.get_process_id())
	for kind in [BattleHost.VIEW_SIMPLE, BattleHost.VIEW_3D]:
		assert_eq(BattleFx.save_settings({"view": kind}, path), "")
		var h := BattleHost.new()
		h.settings_path = path
		var events := T.names().map(func(n): return _fixture(n).event)
		assert_eq(h.open(events, 0), "", "the host opens the three-sided battles (%s)" % kind)
		for i in events.size():
			assert_eq(h.view_kind, kind, "battle %d plays in the %s view" % [i, kind])
			assert_false(h.message_panel.visible, "battle %d: no message instead of the battle (%s)" % [i, kind])
			assert_true(h.view.visible, "battle %d is on screen (%s)" % [i, kind])
			assert_eq((h.view as BattleSimpleView).player.battle_log().sides.size(), 3, "battle %d: all three sides (%s)" % [i, kind])
			h.next()
		assert_false(h.visible, "the last battle's Next goes back to the report (%s)" % kind)
		h.free()
	DirAccess.remove_absolute(path)


# --- the Simple view ----------------------------------------------------------------------------------------

func test_the_simple_view_plays_every_side_to_the_timelines_final_state() -> void:
	for name in T.names():
		var fx := _fixture(name)
		var v := _view(fx)
		_play_out(v, 4)
		var fin := v.player.timeline().final_state()
		assert_eq(v.player.state(), fin, "%s: the player ends on the final state" % name)
		for f in fx.log.fighters:
			var c := v.card(int(f.id))
			var fs: Dictionary = fin.fighters[int(f.id)]
			assert_eq(c.hp, int(fs.hp), "%s: %s's card shows its final hp" % [name, f.name])
			assert_eq(c.alive, bool(fs.alive), "%s: %s's card is alive exactly when the fighter is" % [name, f.name])
			if fs.alive and (fs.fled or fs.lost):
				assert_false(c.visible, "%s: %s has left the field" % [name, f.name])
		for si in fx.log.sides.size():
			var st := BattleExplain.side_strength(fx.log, fin, si)
			var b := v.bar(si)
			assert_true(absf(b.fill - float(st.fill)) < 0.0001, "%s: %s's bar shows its final hp" % [name, _name(fx, si)])
			assert_true(absf(b.notch() - float(st.notch)) < 0.0001, "%s: %s's notch is at its final break line" % [name, _name(fx, si)])
			assert_eq(b.out, String(st.out), "%s: %s is out exactly as the log says" % [name, _name(fx, si)])
		assert_true(v.end_card.visible, "%s: the result card is up" % name)
		v.free()


func test_each_side_has_its_own_place_on_the_simple_field() -> void:
	var probe := BattleSimpleView.new()
	var field := Rect2(Vector2.ZERO, probe.stage_band().size)
	probe.free()
	for name in T.names():
		var fx := _fixture(name)
		var lg: Dictionary = fx.log
		var lay := BattleLayout.build(lg, field.size)
		var groups: Array = lay.groups
		assert_eq(groups.size(), 2, "%s: the sides stand on the field's two halves" % name)
		assert_eq((groups[0] as Array).size() + (groups[1] as Array).size(), 3, "%s: every side stands on one of them" % name)
		var defender := -1
		for sd in lg.sides:
			if sd.get("defender", false):
				defender = int(sd.index)
		if defender >= 0:
			assert_eq(groups[1], [defender], "%s: the defender holds the right half alone" % name)
		var region := []  # by side: the rect round its cards
		for si in lg.sides.size():
			var r := Rect2()
			for fid in lg.sides[si].fighters:
				var slot: Dictionary = lay.slots[int(fid)]
				assert_false(slot.is_empty(), "%s: %s has a slot" % [name, lg.fighters[int(fid)].name])
				var cr: Rect2 = slot.rect
				assert_true(field.encloses(cr), "%s: %s's card is inside the field" % [name, lg.fighters[int(fid)].name])
				assert_true((lay.areas[si] as Rect2).grow(0.5).encloses(cr), "%s: %s's card is inside its side's ground" % [name, lg.fighters[int(fid)].name])
				var left: bool = (groups[0] as Array).has(si)
				assert_eq(cr.get_center().x < field.size.x / 2.0, left, "%s: %s stands on its side's half" % [name, lg.fighters[int(fid)].name])
				assert_eq(int(slot.dir), 1 if left else -1, "%s: %s faces the centre" % [name, lg.fighters[int(fid)].name])
				r = cr if r.size == Vector2.ZERO else r.merge(cr)
			region.append(r)
		for a in 3:
			for b in range(a + 1, 3):
				assert_false((region[a] as Rect2).intersects(region[b]), "%s: %s and %s stand apart" % [name, _name(fx, a), _name(fx, b)])
				assert_false((lay.areas[a] as Rect2).intersects(lay.areas[b]), "%s: their grounds don't overlap" % name)
		var rects := []
		for f in lg.fighters:
			rects.append(lay.slots[int(f.id)].rect)
		for a in rects.size():
			for b in range(a + 1, rects.size()):
				if lay.crowd:
					assert_ne(rects[a].position, rects[b].position, "%s: no two cards share a place" % name)
				else:
					assert_false(rects[a].intersects(rects[b]), "%s: cards %d and %d don't overlap" % [name, a, b])
		# Each side's front rank nearer the centre than its back line.
		for si in lg.sides.size():
			var front := INF
			var back := INF
			for fid in lg.sides[si].fighters:
				var d: float = absf((lay.slots[int(fid)].rect as Rect2).get_center().x - field.size.x / 2.0)
				var tier := int(lg.fighters[int(fid)].tier)
				if tier == 0:
					front = minf(front, d)
				elif tier == 2:
					back = minf(back, d)
			if front < INF and back < INF:
				assert_true(front < back, "%s: %s's front rank stands nearer the centre than its back line" % [name, _name(fx, si)])


func test_each_side_has_its_plate_colour_and_cards() -> void:
	for name in T.names():
		var fx := _fixture(name)
		var v := _view(fx)
		var lg: Dictionary = fx.log
		var order: Array = v.layout.order
		assert_eq(order.size(), 3, "%s: three plates, one a side" % name)
		var shown := v.plates.filter(func(p): return (p as Control).visible)
		assert_eq(shown.size(), 3, "%s: all three on screen" % name)
		var colours := {}
		var view := Rect2(Vector2.ZERO, v.view_size())
		for si in lg.sides.size():
			var k := v.plate_of(si)
			assert_eq(int(order[k]), si, "%s: %s's plate is the one the order gives it" % [name, _name(fx, si)])
			assert_true(String(v.plaque_labels[k].text).begins_with(_name(fx, si)), "%s: plate %d names %s" % [name, k, _name(fx, si)])
			assert_eq(v.bars[k].seat, _seat(fx, si), "%s: %s's bar wears its seat's colour and emblem" % [name, _name(fx, si)])
			assert_eq(v.bar(si), v.bars[k], "%s: bar(%d) is its plate's bar" % [name, si])
			colours[UiPalette.seat_color(_seat(fx, si)).to_html()] = true
			var pr := Rect2((v.plates[k] as Control).position, (v.plates[k] as Control).size)
			assert_true(view.encloses(pr), "%s: %s's plate is inside the view" % [name, _name(fx, si)])
			assert_false(pr.intersects(Rect2(v.centre.position, v.centre.size)), "%s: %s's plate leaves the centre plate clear" % [name, _name(fx, si)])
			for fid in lg.sides[si].fighters:
				assert_eq(v.card(int(fid)).seat, _seat(fx, si), "%s: %s's card is in its side's colour" % [name, lg.fighters[int(fid)].name])
			assert_false(String(v.bar_texts[k].tooltip_text).is_empty(), "%s: %s's strength explains itself" % [name, _name(fx, si)])
		assert_eq(colours.size(), 3, "%s: three sides, three colours" % name)
		for a in 3:
			for b in range(a + 1, 3):
				var ra := Rect2((v.plates[a] as Control).position, (v.plates[a] as Control).size)
				var rb := Rect2((v.plates[b] as Control).position, (v.plates[b] as Control).size)
				assert_false(ra.intersects(rb), "%s: plates %d and %d don't overlap" % [name, a, b])
		# The plates on the left half come before the centre plate, those on the right after it.
		for k in 3:
			var left: bool = (v.layout.groups[0] as Array).has(int(order[k]))
			var px: float = (v.plates[k] as Control).position.x
			assert_eq(px < v.centre.position.x, left, "%s: plate %d stands on its side's half of the top bar" % [name, k])
		v.free()


func test_the_top_bar_fits_three_plates_and_the_centre_at_every_size() -> void:
	## the base view and the smallest the screens are held to (1280 x 720: a 1600 x 900 window at a 125% interface)
	for view_size in [BattleSimpleView.BASE, Vector2(1280, 720)]:
		for name in T.names():
			var fx := _fixture(name)
			var v := BattleSimpleView.new()
			v.size = view_size
			assert_eq(v.show_battle(fx.log, fx.report, fx.seats), "", "%s plays at %s" % [name, view_size])
			var rects := []
			for k in 3:
				rects.append(Rect2((v.plates[k] as Control).position, (v.plates[k] as Control).size))
			var mid := Rect2(v.centre.position, Vector2(v._centre_w, v.centre.size.y))
			for k in 3:
				assert_true(Rect2(Vector2.ZERO, view_size).encloses(rects[k]), "%s at %s: plate %d is inside the view" % [name, view_size, k])
				assert_false((rects[k] as Rect2).intersects(mid), "%s at %s: plate %d leaves the centre clear" % [name, view_size, k])
				assert_true((rects[k] as Rect2).size.x >= BattleSimpleView.MANY_PLATE_MIN_W, "%s at %s: plate %d keeps its least width" % [name, view_size, k])
			var chips := v.conditions.get_children().filter(func(c): return (c as Control).visible)
			assert_true(v.chips_width(chips) + 20.0 <= v._centre_w + 0.5, "%s at %s: the condition chips fit the centre (%.0f of %.0f)" % [name,
				view_size, v.chips_width(chips) + 20.0, v._centre_w])
			assert_true(absf(v.centre.size.x - v._centre_w) < 0.5, "%s at %s: the centre plate keeps the width between the plates" % [name, view_size])
			## each side's morale tag stays on the field, clear of every other, with the why panel docked over the right or closed
			for why_open in [true, false]:
				v.controls.set_why(why_open, false)
				var fw := v.field_width()
				var tags := []
				for k in 3:
					var tr: Rect2 = v._tag_rect(k, fw)
					assert_true(tr.size.x > 0.0 and tr.position.x >= BattleSimpleView.MARGIN - 0.5 and tr.end.x <= fw - BattleSimpleView.MARGIN + 0.5,
						"%s at %s, why %s: tag %d hangs on the field (%s, the field %.0f wide)" % [name, view_size, why_open, k, tr, fw])
					tags.append(tr)
				for a in 3:
					for b in range(a + 1, 3):
						assert_false((tags[a] as Rect2).intersects(tags[b]), "%s at %s, why %s: tags %d and %d stand apart" % [name, view_size, why_open, a, b])
			v.free()


func test_each_morale_tag_names_its_side_in_both_views() -> void:
	for name in T.names():
		var fx := _fixture(name)
		for kind in ["simple", "3d"]:
			var v: BattleSimpleView = BattleSimpleView.new() if kind == "simple" else BattleStage3D.new()
			assert_eq(v.show_battle(fx.log, fx.report, fx.seats), "", "%s plays (%s)" % [name, kind])
			var checked := {}
			for b in v.player.beats():
				if b.kind != "morale" or checked.has(int(b.side)):
					continue
				## a round's morale checks land together: fire them
				v.player.seek_beat(int(b.i))
				v.player.play()
				v.tick(0.0001)
				v.player.pause()
				for si in fx.log.sides.size():
					var text := String(v.tag_labels[v.plate_of(si)].text)
					if not text.is_empty() and not checked.has(si):
						assert_true(text.begins_with(_name(fx, si)), "%s (%s): %s's morale tag says whose it is (\"%s\")" % [name, kind, _name(fx, si), text])
						checked[si] = true
			assert_eq(checked.size(), 3, "%s (%s): every side's morale check shows its tag" % [name, kind])
			v.free()


func test_hover_cards_tab_and_click_reach_every_side() -> void:
	for name in T.names():
		var fx := _fixture(name)
		var v := _view(fx)
		var lg: Dictionary = fx.log
		v.player.seek_round(1)
		for f in lg.fighters:
			var fid := int(f.id)
			var tip := String(v.card(fid).explain_source.call())
			assert_eq(tip, BattleSimpleView.tooltip_of(BattleExplain.explain_fighter(v.player.timeline(), fid, int(v.player.live_state().event),
				v.player.live_state())), "%s: %s's hover text is BattleExplain's" % [name, f.name])
			assert_true(_collapse(tip).contains(String(lg.sides[int(f.side)].name)), "%s: and it names %s's side" % [name, f.name])
		var order: Array = v.selection.order
		assert_eq(order.size(), lg.fighters.size(), "%s: every fighter is in the Tab order" % name)
		var seen := {}
		for fid in order:
			seen[int(fid)] = true
		assert_eq(seen.size(), lg.fighters.size(), "%s: once each" % name)
		# Tab goes plate by plate: each side's fighters together, in the order of the plates.
		var plate_seq := []
		for fid in order:
			var k := v.plate_of(int(lg.fighters[int(fid)].side))
			if plate_seq.is_empty() or plate_seq[-1] != k:
				plate_seq.append(k)
		assert_eq(plate_seq, [0, 1, 2], "%s: Tab goes through the sides in the plates' order" % name)
		for si in lg.sides.size():
			var fid0 := int(lg.sides[si].fighters[0])
			v.controls.set_why(false, false)
			v._on_card_clicked(fid0)
			assert_eq(v.selection.selected, fid0, "%s: a click on %s's card selects it" % [name, _name(fx, si)])
			assert_true(v.controls.why_open, "%s: and opens the why panel" % name)
			v.why_panel.refresh()
			assert_eq(int(v.why_panel.shown.selected), fid0, "%s: which pins %s's fighter" % [name, _name(fx, si)])
			v._on_card_clicked(fid0)
		v.free()


func test_the_scrubber_lands_every_side_on_the_timeline() -> void:
	for name in T.names():
		var fx := _fixture(name)
		var v := _view(fx)
		var lg: Dictionary = fx.log
		var tl := v.player.timeline()
		for n in range(1, tl.rounds() + 1):
			assert_true(v.player.seek_round(n), "%s: round %d is on the scrubber" % [name, n])
			var st := tl.state_at(tl.round_start(n))
			_check_view_at(v, fx, st, "%s round %d" % [name, n])
		var moments := v.player.moments()
		assert_false(moments.is_empty(), "%s: the scrubber has key moments" % name)
		var routs := {}
		for m in moments:
			if m.kind == "rout":
				routs[int(m.side)] = true
			assert_false(v.player.jump_to(m).is_empty(), "%s: the %s marker jumps" % [name, m.kind])
			_check_view_at(v, fx, v.player.live_state(), "%s at its %s" % [name, m.kind])
		for e in lg.events:
			if e.t == "rout" or e.t == "destroyed":
				assert_true(routs.has(int(e.side)), "%s: %s leaving the field has its marker" % [name, _name(fx, int(e.side))])
		assert_eq(v.controls.scrubber.marks.size(), moments.size(), "%s: a marker for every moment" % name)
		for mk in v.controls.scrubber.marks:
			assert_false(String(mk.tip).is_empty(), "%s: the %s marker explains itself" % [name, mk.kind])
		v.free()


func _check_view_at(v: BattleSimpleView, fx: Dictionary, st: Dictionary, where: String) -> void:
	for si in fx.log.sides.size():
		var want := BattleExplain.side_strength(fx.log, st, si)
		assert_true(absf(v.bar(si).fill - clampf(float(want.fill), 0.0, 1.0)) < 0.0001, "%s: %s's bar is the timeline's" % [where, _name(fx, si)])
	for f in fx.log.fighters:
		assert_eq(v.card(int(f.id)).hp, int(st.fighters[int(f.id)].hp), "%s: %s's card is the timeline's" % [where, f.name])


# --- the why lines ------------------------------------------------------------------------------------------

func test_the_why_lines_name_each_side() -> void:
	for name in T.names():
		var fx := _fixture(name)
		var lg: Dictionary = fx.log
		var p := BattlePlayer.new(lg, fx.report)
		var why := BattleWhy.new(p)
		var start := String(why.at(0, p.live_state()).now)
		for si in lg.sides.size():
			assert_true(start.contains(_name(fx, si)), "%s: before round 1 the panel names %s (%s)" % [name, _name(fx, si), start])
		p.skip_to_end()
		var end := String(why.at(p.next_beat(), p.live_state()).now)
		var v := _view(fx)
		v.player.skip_to_end()
		var result := v.end_result.text
		var lines: Array = v.end_card_lines()
		for si in lg.sides.size():
			assert_true(end.contains(_name(fx, si)), "%s: at the end the panel names %s (%s)" % [name, _name(fx, si), end])
			assert_true(result.contains(_name(fx, si)), "%s: the result names %s (%s)" % [name, _name(fx, si), result])
			assert_true(lines.any(func(l): return String(l).begins_with(_name(fx, si) + ":")), "%s: the result card has %s's losses" % [name, _name(fx, si)])
		for text in [end, result]:
			for vague in ["the enemy", "both sides"]:
				assert_false(text.contains(vague), "%s: \"%s\" says who, not \"%s\"" % [name, text, vague])
		# Every side that left the field is named with the round it left in.
		for e in lg.events:
			if e.t == "rout" or e.t == "destroyed":
				var said := "%s %s in round %d" % [_name(fx, int(e.side)), "broke" if e.t == "rout" else "had no one left", int(e.n)]
				assert_true(result.contains(said), "%s: the result says \"%s\" (%s)" % [name, said, result])
		v.free()


# --- the 3D stage --------------------------------------------------------------------------------------------

func test_the_3d_stage_plays_every_side_to_the_timelines_final_state() -> void:
	for name in T.names():
		var fx := _fixture(name)
		var s := _stage(fx)
		var lg: Dictionary = fx.log
		assert_eq(s.figures.n_fighters, lg.fighters.size(), "%s: every fighter is its own figure" % name)
		assert_eq(s.figures.figs.size(), lg.fighters.size() + 2 * lg.sides.size(), "%s: and each side its bearer and musician" % name)
		assert_eq(s.figures.banners.size(), 3, "%s: each side carries its banner" % name)
		for i in s.figures.figs.size():
			var f: Dictionary = s.figures.figs[i]
			assert_eq(f["lin"], BattleStage3D.figure_colour(_seat(fx, int(f["side"]))), "%s: figure %d stands on its side's colour" % [name, i])
		_play_out(s, 4)
		var fin := s.player.timeline().final_state()
		assert_eq(s.player.state(), fin, "%s: the player ends on the final state" % name)
		for f in lg.fighters:
			var fs: Dictionary = fin.fighters[int(f.id)]
			var want := "fallen" if not fs.alive else ("gone" if fs.fled or fs.lost else "stand")
			assert_eq(String(s.figures.figs[s.figures.index_of(int(f.id))]["hold"]), want, "%s: %s stands, lies or is gone as the log says" % [name, f.name])
		for si in lg.sides.size():
			assert_true(absf(s.bar(si).fill - float(BattleExplain.side_strength(lg, fin, si).fill)) < 0.0001, "%s: %s's bar on the land" % [name, _name(fx, si)])
		assert_true(s.end_card.visible, "%s: the result card is up" % name)
		s.free()


func test_each_side_stands_in_its_own_place_on_the_land() -> void:
	var t: RefCounted = Board3D.terrain_now()
	for name in T.names():
		var fx := _fixture(name)
		var s := _stage(fx)
		var lg: Dictionary = fx.log
		var slots: Array = s.plan["slots"]
		var walls: Dictionary = s.plan.get("walls", {})
		var centre := Vector2.ZERO
		var centroids := []
		for si in lg.sides.size():
			var c := Vector2.ZERO
			for fid in lg.sides[si].fighters:
				assert_true(slots[int(fid)] != null, "%s: %s has a place" % [name, lg.fighters[int(fid)].name])
				c += slots[int(fid)]["pos"]
			c /= float(lg.sides[si].fighters.size())
			centroids.append(c)
			centre += c
		centre /= 3.0
		for a in slots.size():
			var pa: Vector2 = slots[a]["pos"]
			assert_true(t.coast_at(pa) > 0.0, "%s: fighter %d stands on land" % [name, a])
			if not walls.is_empty():
				assert_false(Walls.inside_wall(walls["info"], pa, float(slots[a]["y"])), "%s: fighter %d stands outside every wall" % [name, a])
			for b in range(a + 1, slots.size()):
				var d := pa.distance_to(slots[b]["pos"])
				assert_true(d > 2.5, "%s: fighters %d and %d have places of their own (%.1f apart)" % [name, a, b, d])
				if int(slots[a]["side"]) != int(slots[b]["side"]):
					assert_true(d > Formation.FILE_PITCH, "%s: fighters %d and %d of different sides stand apart (%.1f)" % [name, a, b, d])
		# Each side's ground: nearer its own middle than any other side's.
		for si in lg.sides.size():
			for fid in lg.sides[si].fighters:
				var p: Vector2 = slots[int(fid)]["pos"]
				for other in lg.sides.size():
					if other != si:
						assert_true(p.distance_to(centroids[si]) < p.distance_to(centroids[other]),
							"%s: %s stands with %s, not %s" % [name, lg.fighters[int(fid)].name, _name(fx, si), _name(fx, other)])
		# Every front rank faces the fight: toward the battle's middle.
		for si in lg.sides.size():
			for fid in lg.sides[si].fighters:
				var sl: Dictionary = slots[int(fid)]
				if int(sl["tier"]) != 0 or String(sl.get("station", "line")) != "line":
					continue
				var facing := Vector2(-sin(float(sl["yaw"])), -cos(float(sl["yaw"])))
				assert_true(facing.dot(centre - (sl["pos"] as Vector2)) > 0.0, "%s: %s faces the fight" % [name, lg.fighters[int(fid)].name])
		var again: Dictionary = s.plan.duplicate(true)
		s.play(fx.log, fx.report, fx.state, fx.seats)
		assert_eq(var_to_str(s.plan["slots"]), var_to_str(again["slots"]), "%s: the same log stands the same way every time" % name)
		assert_eq(_props_on(s), 0, "%s: no tree, rock or house stands on the battle's ground" % name)
		s.free()


func _props_on(s: BattleStage3D) -> int:
	return s.props_standing_on(s.plan.footprint)


func test_the_camera_frames_every_side_and_the_plates_follow_the_screen() -> void:
	var t: RefCounted = Board3D.terrain_now()
	for name in T.names():
		var fx := _fixture(name)
		var s := _stage(fx)
		var lg: Dictionary = fx.log
		var band := s._band().grow(4.0)
		var mid := 0.0
		var xs := []
		for si in lg.sides.size():
			var x := 0.0
			for fid in lg.sides[si].fighters:
				for p in s.figures.ends_at(s.figures.index_of(int(fid)), 0.0):
					var at := Cam.project(s.wv.rig, s._view, p)
					assert_true(band.has_point(at), "%s: %s stands inside the band the screen leaves clear (%s)" % [name, lg.fighters[int(fid)].name, at])
					x += at.x
			x /= 2.0 * lg.sides[si].fighters.size()
			xs.append(x)
			mid += x / 3.0
		assert_true(Cam.sees_all(t, s.goal, s._points([], true), s._obstacles()) or float(s.goal.pitch) >= Cam.PITCH_MAX,
			"%s: no hill or wall hides anyone (or the camera looks down as steeply as it may)" % name)
		# The plates of the sides on the screen's left come first, then the centre, then the right's.
		var groups: Array = s.layout.groups
		for si in lg.sides.size():
			var left: bool = (groups[0] as Array).has(si)
			var k := s.plate_of(si)
			assert_eq((s.plates[k] as Control).position.x < s.centre.position.x, left, "%s: %s's plate is on its half of the top bar" % [name, _name(fx, si)])
		for a in (groups[0] as Array):
			for b in (groups[1] as Array):
				assert_true(float(xs[int(a)]) < float(xs[int(b)]), "%s: %s stands left of %s on screen, as their plates do" % [name, _name(fx, int(a)), _name(fx, int(b))])
		s.free()


func test_hovering_and_clicking_a_fighter_of_each_side_on_the_land() -> void:
	for name in T.names():
		var fx := _fixture(name)
		var s := _stage(fx)
		var lg: Dictionary = fx.log
		s.player.seek_round(1)
		for si in lg.sides.size():
			var got := -1
			for fid in lg.sides[si].fighters:
				var at := _screen_of(s, int(fid))
				if s.pick(at) == int(fid):
					got = int(fid)
					break
			assert_true(got >= 0, "%s: a fighter of %s can be picked by its own figure" % [name, _name(fx, si)])
			if got < 0:
				continue
			var at2 := _screen_of(s, got)
			var mm := InputEventMouseMotion.new()
			mm.position = at2
			s._gui_input(mm)
			assert_eq(s._hovered, got, "%s: hovering %s's fighter hovers it" % [name, _name(fx, si)])
			assert_eq(s._get_tooltip(at2), s.figure_tooltip(got), "%s: its tooltip explains it" % name)
			assert_true(_collapse(s._get_tooltip(at2)).contains(_name(fx, si)), "%s: and names its side" % name)
			var click := InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_LEFT
			click.pressed = true
			click.position = at2
			s._gui_input(click)
			assert_eq(s.selection.selected, got, "%s: a click selects %s's fighter" % [name, _name(fx, si)])
			s._gui_input(click)
		var order: Array = s._tab_order()
		assert_eq(order.size(), lg.fighters.size(), "%s: every fighter is in the Tab order once" % name)
		var plate_seq := []
		for fid in order:
			var k := s.plate_of(int(lg.fighters[int(fid)].side))
			if plate_seq.is_empty() or plate_seq[-1] != k:
				plate_seq.append(k)
		assert_eq(plate_seq, [0, 1, 2], "%s: Tab goes through the sides in the plates' order" % name)
		s.free()


func _screen_of(s: BattleStage3D, fid: int) -> Vector2:
	var e: Array = s.figures.ends_at(s.figures.index_of(fid), s.player.time())
	var v := Cam.project(s.wv.rig, s._view, (e[0] as Vector3).lerp(e[1], 0.55))
	return v / s._px + s.frame.position + s.field.position


func test_a_broken_side_runs_off_its_own_way() -> void:
	for name in T.names():
		var fx := _fixture(name)
		var s := _stage(fx)
		var lg: Dictionary = fx.log
		for b in s.player.beats():
			if b.kind != "rout":
				continue
			s.player.seek_beat(int(b.i))
			s.player.play()
			s.tick(0.0001)
			s.player.pause()
			var si := int(b.side)
			var others := Vector2.ZERO
			for o in lg.sides.size():
				if o != si:
					for fid in lg.sides[o].fighters:
						others += s.plan["slots"][int(fid)]["pos"]
			others /= float(lg.fighters.size() - lg.sides[si].fighters.size())
			for fid in b.data.fled:
				var i: int = s.figures.index_of(int(fid))
				for m in s.figures.figs[i]["motions"]:
					if String(m["kind"]) == "rout":
						var from: Vector2 = m["from"]
						var to: Vector2 = m["to"]
						assert_true(to.distance_to(others) > from.distance_to(others), "%s: %s runs away from the others" % [name, lg.fighters[int(fid)].name])
		s.free()


func test_the_launcher_plays_the_three_sided_battles() -> void:
	var w := W3D.new()
	for name in T.names():
		var fx: Dictionary = W3D.load_fixture("three_" + name)
		assert_false(fx.is_empty(), "the 3D launcher finds three_%s" % name)
		assert_eq(w.watch(fx), "", "and plays it")
		assert_eq(w.stage.player.battle_log().sides.size(), 3)
	w.free()
	var sv := Watch.new()
	var fx2: Dictionary = Watch.load_fixture("three_holds")
	assert_false(fx2.is_empty(), "the Simple view's launcher finds it too")
	assert_eq(sv.watch(fx2), "", "and plays it")
	sv.free()


# --- two sides stay as they were ----------------------------------------------------------------------------

func test_a_view_that_showed_three_sides_shows_two_as_a_fresh_one_does() -> void:
	var three := _fixture("holds")
	for name in ["king_falls_wins", "border", "forest_fort"]:
		var two := Fx.battle(name)
		var fresh := BattleSimpleView.new()
		fresh.show_battle(two.log, two.report)
		var used := BattleSimpleView.new()
		used.show_battle(three.log, three.report, three.seats)
		used.show_battle(two.log, two.report)
		assert_eq(_plates_of(used), _plates_of(fresh), "%s: two plates, where and as they always were" % name)
		assert_eq(var_to_str(used.layout), var_to_str(fresh.layout), "%s: the same field" % name)
		assert_eq(used.selection.order, fresh.selection.order, "%s: the same Tab order" % name)
		fresh.free()
		used.free()
	var s := BattleStage3D.new()
	var two2 := Fx.battle("king_falls_wins")
	s.show_battle(two2.log, two2.report)
	var plan_before := var_to_str(s.plan)
	var plates_before := _plates_of(s)
	s.play(three.log, three.report, three.state, three.seats)
	s.show_battle(two2.log, two2.report)
	assert_eq(var_to_str(s.plan), plan_before, "the stage stands a two-sided battle as before")
	assert_eq(_plates_of(s), plates_before, "with its two plates as before")
	s.free()


## What each shown plate says and where it is.
func _plates_of(v: BattleSimpleView) -> Array:
	var out := []
	for k in v.plates.size():
		var p: Control = v.plates[k]
		if p.visible:
			out.append([k, p.position, p.size, v.plaque_labels[k].text, v.role_chips[k].text, v.bars[k].seat, v.bars[k].mirrored,
				v.tag_labels[k].position])
	return out


func _collapse(text: String) -> String:
	var out := text.replace("\n", " ")
	while out.contains("  "):
		out = out.replace("  ", " ")
	return out.strip_edges()
