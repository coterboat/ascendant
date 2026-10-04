extends "res://tests/test_case.gd"
## M3-3 (#58, re-scoped by design/3D_DIRECTION.md §7.6): the renderer-agnostic BattlePlayer
## (design/M3_BATTLES.md §4.1, §5.1-§5.3) on every fixture battle. The same log gives the same beats and
## timings; every log event is applied by exactly one beat; the beats follow §4.1's timing; seeks, jumps and
## skip land on BattleTimeline's own states; the clock's speeds, pause, step and the ruler-fall slow motion
## behave; playing a battle back reads its log and report and never changes them; nothing under ui/battle/
## draws a random number or calls the rules (the static level of "playback never changes the outcome");
## and BattleFx's flash limiter, shake spacing and settings follow §4.5, §6 and §7.4.

const Watch := preload("res://ui/battle/battle_watch.gd")
const Scenarios := preload("res://tools/battle_log/scenarios.gd")
const Fx := preload("res://tests/battle_playback_fixtures.gd")
const STEP := 1.0 / 60.0


func _fixture(name: String) -> Dictionary:
	var fx := Fx.battle(name)
	assert_false(fx.is_empty(), "battle %s loads" % name)
	return fx


## Plays `p` from the start at `speed` in fixed 1/60 s steps to the end; returns [[kind, event, t]] fired.
func _play_all(p: BattlePlayer, speed: int) -> Array:
	var fired := []
	var rec := func(b, _st): fired.append([b.kind, b.event, snappedf(float(b.t), 0.0001)])
	p.beat.connect(rec)
	p.restart()
	p.set_speed(speed)
	p.play()
	var guard := 0
	while not p.is_finished() and guard < 100000:
		p.advance(STEP)
		guard += 1
	p.beat.disconnect(rec)
	return fired


func test_the_same_log_gives_the_same_beats_and_timings() -> void:
	for name in Fx.names():
		var fx := _fixture(name)
		var a := BattlePlayer.new(fx.log, fx.report)
		var copy: Dictionary = BattleLog.from_json(BattleLog.to_json(fx.log)).log
		var b := BattlePlayer.new(copy, fx.report.duplicate(true))
		assert_eq(var_to_str(a.beats()), var_to_str(b.beats()), "%s: the same beats from a copy of the log" % name)
		assert_eq(a.duration(), b.duration(), "%s: the same length" % name)
		var fa := _play_all(a, 4)
		var fb := _play_all(b, 4)
		assert_eq(fa, fb, "%s: the same beats fire in the same order" % name)
		assert_eq(fa.size(), a.beats().size(), "%s: every beat fires once" % name)
		var again := _play_all(a, 4)
		assert_eq(again, fa, "%s: playing it again gives the same beats" % name)
		var at1 := _play_all(a, 1)
		assert_eq(at1, fa, "%s: 1x and 4x fire the same beats at the same schedule times" % name)


func test_every_log_event_is_applied_by_exactly_one_beat() -> void:
	for name in Fx.names():
		var fx := _fixture(name)
		var p := BattlePlayer.new(fx.log, fx.report)
		var count := {}
		var last_t := -1.0
		for b in p.beats():
			assert_true(BattlePlayer.KINDS.has(b.kind), "%s: a known beat kind %s" % [name, b.kind])
			assert_true(float(b.t) >= last_t - 0.000001, "%s: beat times never go back (%s at %.3f)" % [name, b.kind, b.t])
			last_t = float(b.t)
			if BattlePlayer.APPLYING.has(b.kind):
				count[int(b.event)] = int(count.get(int(b.event), 0)) + 1
		for i in fx.log.events.size():
			assert_eq(int(count.get(i, 0)), 1, "%s: event %d (%s) is applied once" % [name, i, fx.log.events[i].t])
		var beats: Array = p.beats()
		assert_eq(beats[0].kind, "deploy", "%s: the deploy beat comes first" % name)
		assert_eq(beats[-1].kind, "result", "%s: the result beat comes last" % name)
		var moments := 0
		for b in beats:
			if b.kind == "moment":
				moments += 1
		assert_eq(moments, BattleMoments.key_moments(fx.log).size(), "%s: one moment beat per key moment" % name)


func test_beats_follow_the_spec_timing() -> void:
	for name in Fx.names():
		var fx := _fixture(name)
		var p := BattlePlayer.new(fx.log, fx.report)
		var tl := p.timeline()
		var beats: Array = p.beats()
		assert_eq(float(beats[0].t), 0.0, "%s: deploy at 0" % name)
		assert_eq(float(beats[0].dur), BattlePlayer.DEPLOY, "%s: deploy lasts 1.5 s" % name)
		for rt in p.round_times():
			var n := int(rt.round)
			var t0 := float(rt.t)
			var order := tl.display_order(n)
			var count := order.size()
			var stagger := minf(0.25, 1.6 / maxi(1, count))
			var starts := {}
			var lands := {}
			var wounds_at := -1.0
			var heal_at := -1.0
			var morale_at := -1.0
			var rout_at := -1.0
			var caption_at := -1.0
			var end_at := -1.0
			for b in beats:
				if int(b.round) != n:
					continue
				match String(b.kind):
					"attack_started":
						starts[int(b.event)] = float(b.t)
					"attack_landed":
						lands[int(b.event)] = float(b.t)
					"wound", "death":
						wounds_at = float(b.t) if wounds_at < 0.0 else wounds_at
					"heal":
						heal_at = float(b.t) if heal_at < 0.0 else heal_at
					"morale":
						morale_at = float(b.t) if morale_at < 0.0 else morale_at
					"rout", "destroyed":
						rout_at = float(b.t) if rout_at < 0.0 else rout_at
					"caption":
						caption_at = float(b.t)
					"round_end":
						end_at = float(b.t)
			var last_land := t0 + BattlePlayer.BANNER
			for k in count:
				var i := int(order[k])
				var want := t0 + BattlePlayer.BANNER + k * stagger
				assert_true(absf(float(starts[i]) - want) < 0.0005, "%s round %d: attack %d starts at banner + %d x stagger" % [name, n, k, k])
				var f: Dictionary = fx.log.fighters[int(fx.log.events[i].by)]
				var delay := float(BattlePlayer.projectile_of(f).get("flight", BattlePlayer.MELEE_IMPACT))
				assert_true(absf(float(lands[i]) - float(starts[i]) - delay) < 0.0005, "%s round %d: attack %d lands after its impact delay" % [name, n, k])
				assert_true(delay <= 0.8 and delay >= 0.12 - 0.0001, "%s: the impact lands within 0.8 s of the start" % name)
				last_land = maxf(last_land, float(lands[i]))
			var cursor := last_land
			if wounds_at >= 0.0:
				assert_true(absf(wounds_at - cursor) < 0.0005, "%s round %d: wounds land when the last attack has" % [name, n])
				cursor += BattlePlayer.WOUNDS
			if heal_at >= 0.0:
				assert_true(absf(heal_at - cursor) < 0.0005, "%s round %d: heals after the wounds" % [name, n])
				cursor += BattlePlayer.HEAL
			if morale_at >= 0.0:
				assert_true(absf(morale_at - cursor) < 0.0005, "%s round %d: morale 0.6 s after the wounds" % [name, n])
				cursor += BattlePlayer.MORALE
			assert_true(absf(caption_at - cursor) < 0.0005, "%s round %d: the caption at the end of the morale beat" % [name, n])
			if rout_at >= 0.0:
				assert_true(absf(rout_at - cursor) < 0.0005, "%s round %d: the rout after the morale beat" % [name, n])
				cursor += BattlePlayer.ROUT
			if end_at >= 0.0:
				assert_true(absf(end_at - cursor) < 0.0005, "%s round %d: the round ends after its last phase" % [name, n])
			var length := cursor - t0
			var cap := 0.4 + 1.6 + 0.35 + 0.6 + 0.5 + (1.5 if rout_at >= 0.0 else 0.0) + (BattlePlayer.HEAL if heal_at >= 0.0 else 0.0)
			assert_true(length <= cap + 0.0005, "%s round %d: %.2f s, within §4.1's round length" % [name, n, length])
		# The result card comes RESULT_DELAY after the end (or after a feast's refill, if longer).
		var end_t := -1.0
		for b in beats:
			if b.kind == "end":
				end_t = float(b.t)
		assert_true(absf(p.duration() - end_t - BattlePlayer.RESULT_DELAY) < 0.0005, "%s: the result 0.8 s after the end" % name)


func test_seek_lands_on_the_timelines_state() -> void:
	for name in Fx.names():
		var fx := _fixture(name)
		var p := BattlePlayer.new(fx.log, fx.report)
		var tl := p.timeline()
		var events: Array = fx.log.events
		var bad := 0
		for i in events.size():
			if events[i].t == "attack":
				continue
			p.seek(i)
			if p.state() != tl.state_at(i):
				bad += 1
				if bad <= 3:
					fail("%s: seek(%d) (%s) lands on state_at(%d)" % [name, i, events[i].t, i])
		for n in range(1, tl.rounds() + 1):
			assert_true(p.seek_round(n), "%s: round %d exists" % [name, n])
			assert_eq(p.state(), tl.state_at(tl.round_start(n)), "%s: seek_round(%d) is state_at(round_start)" % [name, n])
			assert_eq(p.round_now(), n - 1 if n > 1 else 0, "%s: before round %d's banner fires" % [name, n])
		assert_false(p.seek_round(tl.rounds() + 1), "%s: no round after the last" % name)
		p.seek(events.size())
		assert_eq(p.state(), tl.final_state(), "%s: seek(events.size()) is the final state" % name)


func test_attacks_fold_in_display_order() -> void:
	for name in ["starting_plains", "skirmish", "biggest"]:
		var fx := _fixture(name)
		var p := BattlePlayer.new(fx.log, fx.report)
		var beats: Array = p.beats()
		var landed_so_far := {}  # round -> pending dealt to each side so far
		var checked := 0
		for b in beats:
			if b.kind != "attack_landed":
				continue
			var n := int(b.round)
			var sums: Array = landed_so_far.get(n, [0, 0])
			if checked < 60 or name != "biggest":
				p.seek_beat(int(b.i))
				var st := p.state()
				for si in 2:
					assert_eq(int(st.sides[si].pending), int(sums[si]), "%s: before beat %d, side %d's pending is what has landed" % [name, b.i, si])
				checked += 1
			if b.data.hit:
				var ts := int(fx.log.fighters[int(b.target)].side)
				sums[ts] += int(b.data.damage)
			landed_so_far[n] = sums


func test_jumps_land_a_lead_in_before_each_moment() -> void:
	for name in Fx.names():
		var fx := _fixture(name)
		var p := BattlePlayer.new(fx.log, fx.report)
		var tl := p.timeline()
		for m in p.moments():
			p.pause()
			p.restart()
			var got := p.jump_to_moment(String(m.kind))
			assert_eq(String(got.get("kind", "")), String(m.kind), "%s: the jump finds a %s" % [name, m.kind])
			var mt := p.moment_time(got)
			assert_true(absf(p.time() - maxf(0.0, mt - BattlePlayer.LEAD_IN)) < 0.0005, "%s: %s lands 0.5 s before its beat" % [name, m.kind])
			assert_false(p.is_playing(), "%s: a jump keeps pause" % name)
			# Every beat before the landing time has fired; the state is theirs.
			var fold := BattlePlayer.new(fx.log, fx.report)
			fold.seek_time(p.time())
			assert_eq(p.state(), fold.state(), "%s: %s lands on the state at its time" % [name, m.kind])
			# Playing on, the moment's beat fires within the lead-in, with its event shown.
			var seen := []
			var rec := func(b, st):
				if b.kind == "moment" and int(b.event) == int(got.event):
					seen.append(st.duplicate(true))
			p.beat.connect(rec)
			p.play()
			var guard := 0
			while seen.is_empty() and guard < 200:
				p.advance(STEP)
				guard += 1
			p.beat.disconnect(rec)
			assert_eq(seen.size(), 1, "%s: the %s beat fires after the lead-in" % [name, m.kind])
			assert_true(guard <= int(ceil(BattlePlayer.LEAD_IN / STEP)) + 2, "%s: within 0.5 s at 1x" % name)
			if not seen.is_empty() and fx.log.events[int(got.event)].t != "attack":
				assert_eq(seen[0], tl.state_at(int(got.event) + 1), "%s: at the %s beat the state is state_at(event + 1)" % [name, m.kind])
		for kind in BattleMoments.missing(fx.log):
			p.seek_time(1.0)
			assert_eq(p.jump_to_moment(String(kind)), {}, "%s: no %s to jump to" % [name, kind])
			assert_eq(p.time(), 1.0, "%s: a missing moment leaves the playhead" % name)


func test_a_jump_keeps_playing_and_m_cycles_through_moments() -> void:
	var fx := _fixture("king_falls_wins")
	var p := BattlePlayer.new(fx.log, fx.report)
	p.play()
	p.jump_to_moment("ruler_falls")
	assert_true(p.is_playing(), "a jump keeps playing")
	p.pause()
	p.restart()
	var kinds := []
	for k in p.moments().size():
		kinds.append(String(p.next_moment().kind))
	var want := p.moments().map(func(m): return String(m.kind))
	assert_eq(kinds, want, "M steps through the moments in order")
	assert_eq(String(p.next_moment().kind), String(want[0]), "and wraps to the first")


func test_skip_to_end_gives_the_final_state() -> void:
	for name in Fx.names():
		var fx := _fixture(name)
		var p := BattlePlayer.new(fx.log, fx.report)
		var fired := []
		var done := [0]
		p.beat.connect(func(b, _st): fired.append(String(b.kind)))
		p.finished.connect(func(): done[0] += 1)
		p.play()
		p.advance(0.5)
		fired.clear()
		p.skip_to_end()
		assert_eq(p.state(), p.timeline().final_state(), "%s: skip lands on the final state" % name)
		assert_eq(fired, ["result"], "%s: skip fires only the result beat" % name)
		assert_eq(done[0], 1, "%s: finished once" % name)
		assert_true(p.is_finished(), "%s: finished" % name)
		assert_false(p.is_playing(), "%s: the clock stops at the end" % name)
		p.play()
		assert_true(p.is_playing() and p.time() == 0.0, "%s: play after the end watches again from the start" % name)


func test_step_and_step_back_move_one_event() -> void:
	var fx := _fixture("skirmish")
	var p := BattlePlayer.new(fx.log, fx.report)
	var tl := p.timeline()
	var fired := p.step()
	assert_eq(fired.map(func(b): return String(b.kind)), ["deploy", "round_start"], "the first step shows the deploy and round 1's banner")
	assert_eq(p.state(), tl.state_at(1), "after one step: state_at(1)")
	var before := p.state()
	p.step()
	p.step_back()
	assert_eq(p.state(), before, "step back undoes the step")
	p.step_back()
	assert_eq(p.state(), tl.state_at(0), "and back to the start")


func test_speed_pause_and_the_clock() -> void:
	var fx := _fixture("skirmish")
	var p := BattlePlayer.new(fx.log, fx.report)
	assert_eq(p.speed(), 1, "1x by default")
	assert_false(p.set_speed(3), "3x isn't a speed")
	assert_eq(p.advance(1.0), [], "nothing moves while paused")
	assert_eq(p.time(), 0.0, "paused")
	for s in [1, 2, 4]:
		p.pause()
		p.restart()
		p.set_speed(s)
		p.play()
		var frames := 0
		while not p.is_finished() and frames < 100000:
			p.advance(STEP)
			frames += 1
		var want := int(ceil(p.duration() / s / STEP))
		assert_true(absi(frames - want) <= 1, "%dx plays the %.2f s battle in %d frames (got %d)" % [s, p.duration(), want, frames])


func test_a_rulers_fall_slows_the_clock_unless_reduced_motion() -> void:
	var fx := _fixture("king_falls_wins")
	var frames := {}
	for reduced in [false, true]:
		var p := BattlePlayer.new(fx.log, fx.report)
		p.reduced_motion = reduced
		p.play()
		var n := 0
		while not p.is_finished() and n < 100000:
			p.advance(STEP)
			n += 1
		frames[reduced] = n
	var extra: float = (int(frames[false]) - int(frames[true])) * STEP
	var want := BattlePlayer.SLOWMO_SECONDS * (1.0 - BattlePlayer.SLOWMO_RATE)
	assert_true(absf(extra - want) <= 2.0 * STEP, "the king's fall adds %.2f s of real time (got %.3f)" % [want, extra])


func test_playback_reads_the_log_and_report_and_changes_neither() -> void:
	for name in ["king_falls_wins", "dread_feast_frenzy", "biggest"]:
		var fx := _fixture(name)
		var log_before := var_to_str(fx.log)
		var report_before := var_to_str(fx.report)
		var p := BattlePlayer.new(fx.log, fx.report)
		_play_all(p, 4)
		p.seek_round(2)
		p.next_moment()
		for fid in range(0, fx.log.fighters.size(), 7):
			p.explain(fid)
			p.strength(int(fx.log.fighters[fid].side))
		p.skip_to_end()
		assert_eq(var_to_str(fx.log), log_before, "%s: the log is unchanged" % name)
		assert_eq(var_to_str(fx.report), report_before, "%s: the report is unchanged" % name)


func test_nothing_in_the_battle_ui_draws_a_random_number_or_calls_the_rules() -> void:
	var banned := RegEx.create_from_string(
		"\\b(SeededRNG|RandomNumberGenerator|randi|randf|randi_range|randf_range|randfn|randomize|rand_from_seed|seed)\\s*\\(|\\bSeededRNG\\b|\\bRandomNumberGenerator\\b|\\bTurnResolver\\b|AutoBattleResolver\\s*\\.\\s*(fight|resolve|resolve_battle|estimate)\\b|\\.(end_turn|queue_order|queue_move|queue_recruit|queue_sacrifice|queue_research|begin_turn|acknowledge_handoff|cancel_order)\\s*\\(")
	var files := _scripts("res://ui/battle")
	assert_true(files.size() >= 8, "the battle UI scripts are scanned (%d)" % files.size())
	for path in files:
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for k in lines.size():
			var line := String(lines[k])
			var code := line.split("#")[0] if not line.strip_edges().begins_with("##") else ""
			var m := banned.search(code)
			assert_true(m == null, "%s:%d calls no RNG or rules: %s" % [path, k + 1, line.strip_edges()])


func _scripts(dir_path: String) -> Array:
	var out := []
	for f in DirAccess.get_files_at(dir_path):
		if f.ends_with(".gd"):
			out.append(dir_path.path_join(f))
	for d in DirAccess.get_directories_at(dir_path):
		out.append_array(_scripts(dir_path.path_join(d)))
	return out


func test_a_battle_without_playback_says_why() -> void:
	assert_eq(BattlePlayer.playback_problem({}), "This battle was fought with the test rules and has no playback.")
	var fx := _fixture("skirmish")
	var cut: Dictionary = fx.log.duplicate(true)
	cut.truncated = true
	assert_eq(BattlePlayer.playback_problem(cut), "This battle is too big to play back. The report has everything.")
	assert_eq(BattlePlayer.playback_problem(fx.log), "")


func test_the_flash_limiter_allows_three_bright_starts_a_second() -> void:
	var fl := BattleFx.FlashLimiter.new()
	assert_true(fl.allow(0.0) and fl.allow(0.1) and fl.allow(0.2), "three bright starts in a second")
	assert_false(fl.allow(0.3), "a fourth in the same second is held back")
	assert_false(fl.allow(0.99), "still inside the window")
	assert_true(fl.allow(1.0), "once the first leaves the window, another may start")
	assert_eq(fl.count(1.0), 3, "three in the window")
	# At 4x, a burst of impacts in one frame still gets at most three bright starts.
	var burst := BattleFx.FlashLimiter.new()
	var allowed := 0
	for k in 20:
		if burst.allow(5.0):
			allowed += 1
	assert_eq(allowed, BattleFx.MAX_FLASHES, "a burst of 20 impacts gets 3 bright starts")


func test_shakes_are_spaced_and_can_be_switched_off() -> void:
	var sh := BattleFx.ShakeLimiter.new()
	assert_true(sh.allow(0.0), "the first shake")
	assert_false(sh.allow(0.5), "too soon: dropped")
	assert_true(sh.allow(0.75), "0.75 s later")
	sh.enabled = false
	assert_false(sh.allow(10.0), "switched off")


func test_battle_settings_default_and_read_the_battle_section() -> void:
	var dir := "user://test_battle_settings_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("settings.cfg")
	assert_eq(BattleFx.settings(path), BattleFx.DEFAULTS, "no file: the defaults")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("this is [not a config")
	f.close()
	assert_eq(BattleFx.settings(path), BattleFx.DEFAULTS, "a broken file: the defaults")
	var cfg := ConfigFile.new()
	cfg.set_value("battle", "reduced_motion", true)
	cfg.set_value("battle", "screen_shake", false)
	cfg.set_value("battle", "speed", 4)
	cfg.save(path)
	var want := BattleFx.DEFAULTS.duplicate()
	want.merge({"reduced_motion": true, "screen_shake": false, "speed": 4}, true)
	assert_eq(BattleFx.settings(path), want, "the [battle] section is read")
	cfg.set_value("battle", "speed", 3)
	cfg.set_value("battle", "reduced_motion", "yes")
	cfg.save(path)
	var st := BattleFx.settings(path)
	assert_eq(st.speed, 1, "an unknown speed gives 1x")
	assert_eq(st.reduced_motion, false, "a value of the wrong kind gives the default")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(dir)


# --- battles with paths (M4-3, #83) and new log kinds ----------------------------------------------

## The beats of `kind` in `p`.
func _beats_of(p: BattlePlayer, kind: String) -> Array:
	return p.beats().filter(func(b): return b.kind == kind)


func test_path_battles_get_beats_for_heals_harvest_wings_and_iron_hide() -> void:
	for name in Fx.PATH_NAMES:
		var fx := _fixture(name)
		assert_true(fx.log.get("paths", false), "%s is a battle with paths" % name)
		assert_eq(BattleLog.validate(fx.log), [], "%s: a valid log" % name)
	# Lifedrinker: one heal beat per heal event, after the round's wounds and before its morale checks.
	var lf := _fixture("path_lifedrinker")
	var p := BattlePlayer.new(lf.log, lf.report)
	var tl := p.timeline()
	var heals := _beats_of(p, "heal")
	var heal_events: Array = lf.log.events.filter(func(e): return e.t == "heal")
	assert_eq(heals.size(), heal_events.size(), "a heal beat for every heal")
	assert_true(heals.size() >= 1, "the Lifedrinker healed")
	for hb in heals:
		var e: Dictionary = lf.log.events[int(hb.event)]
		assert_eq(int(hb.fighter), int(e.f), "the heal beat is the healer's")
		assert_eq(int(hb.data.healed), int(e.to) - int(e.from), "it carries the hp healed")
		assert_eq(String(hb.data.trait), AutoBattleResolver.LIFEDRINKER, "and the trait")
		for b in p.beats():
			if int(b.round) != int(hb.round):
				continue
			if b.kind == "wound" or b.kind == "death":
				assert_true(int(b.i) < int(hb.i) and float(b.t) < float(hb.t), "the wounds land before the heal")
			elif b.kind == "morale":
				assert_true(int(b.i) > int(hb.i) and float(b.t) > float(hb.t), "morale is checked after it")
		p.seek_beat(int(hb.i))
		var fired := p.step()
		assert_eq(fired[-1].kind, "heal", "stepping fires the heal")
		assert_eq(p.state(), tl.state_at(int(hb.event) + 1), "after the heal beat the state is state_at(heal + 1)")
		assert_eq(int(p.state().fighters[int(e.f)].hp), int(e.to), "with the healed hp")
	# Red Harvest: one harvest beat after the end, before the aftermath, carrying the gold.
	var rh := _fixture("path_red_harvest")
	var q := BattlePlayer.new(rh.log, rh.report)
	var hv := _beats_of(q, "harvest")
	assert_eq(hv.size(), 1, "one harvest beat")
	var he: Dictionary = rh.log.events[int(hv[0].event)]
	assert_eq(int(hv[0].data.gold), int(he.gold), "with its gold")
	assert_eq(int(hv[0].data.fighters), int(he.fighters), "and the fighters lost")
	assert_true(int(_beats_of(q, "end")[0].i) < int(hv[0].i) and int(hv[0].i) < int(_beats_of(q, "aftermath")[0].i), "between the end and the aftermath")
	q.skip_to_end()
	assert_eq(q.state(), q.timeline().final_state(), "skip still lands on the final state")
	# Wings: the Seraphs dive (no lunge), and at least one dive strikes a standing commander.
	var wg := _fixture("path_wings")
	var w := BattlePlayer.new(wg.log, wg.report)
	var at_commander := 0
	for b in _beats_of(w, "attack_started"):
		var f: Dictionary = wg.log.fighters[int(b.fighter)]
		if f.trait == AutoBattleResolver.WINGS:
			assert_eq(String(b.data.projectile), "dive", "a Wings attack is a dive")
		if b.data.wings and wg.log.fighters[int(b.target)].role == "commander":
			at_commander += 1
			assert_eq(String(b.data.reach), "wings", "its reach is Wings'")
	assert_true(at_commander >= 1, "a Seraphs dive strikes the Warchief")
	# Iron Hide: the hit's negative damage part is in the beat, and the damage is the log's.
	var ih := _fixture("path_iron_hide")
	var r := BattlePlayer.new(ih.log, ih.report)
	var hidden := 0
	for b in _beats_of(r, "attack_landed"):
		var e: Dictionary = ih.log.events[int(b.event)]
		if e.hit and e.bonus.has(AutoBattleResolver.IRON_HIDE):
			hidden += 1
			assert_eq(int(b.data.iron_hide), -AutoBattleResolver.IRON_HIDE_DAMAGE, "Iron Hide takes 1 off")
			assert_eq(int(b.data.parts[AutoBattleResolver.IRON_HIDE]), -AutoBattleResolver.IRON_HIDE_DAMAGE, "as a named damage part")
			assert_eq(int(b.data.damage), int(e.damage), "the damage is the log's")
			assert_true(b.data.blocked, "a hit Iron Hide took some of")
	assert_true(hidden >= 1, "Iron Hide turned some hits")


func test_a_log_event_of_an_unknown_kind_still_gets_exactly_one_beat() -> void:
	var fx := _fixture("skirmish")
	var lg: Dictionary = fx.log.duplicate(true)
	# A future kind, between round 1's wounds and its morale checks, and another after the end.
	var at := -1
	for i in lg.events.size():
		if lg.events[i].t == "morale":
			at = i
			break
	lg.events.insert(at, {"t": "omen", "n": 1})
	lg.events.insert(BattleLog.find_event(lg, "end") + 1, {"t": "epilogue"})
	var p := BattlePlayer.new(lg, fx.report)
	var tl := p.timeline()
	var count := {}
	for b in p.beats():
		if BattlePlayer.APPLYING.has(b.kind):
			count[int(b.event)] = int(count.get(int(b.event), 0)) + 1
	for i in lg.events.size():
		assert_eq(int(count.get(i, 0)), 1, "event %d (%s) is applied once" % [i, lg.events[i].t])
	var unknown := _beats_of(p, "event")
	assert_eq(unknown.map(func(b): return String(b.data.t)), ["omen", "epilogue"], "each unknown kind is an \"event\" beat")
	for i in lg.events.size():
		if lg.events[i].t != "attack":
			p.seek(i)
			assert_eq(p.state(), tl.state_at(i), "seek(%d) is still state_at(%d)" % [i, i])
	p.skip_to_end()
	assert_eq(p.state(), tl.final_state(), "and skip the final state")


func test_battle_sounds_come_from_the_beats() -> void:
	assert_eq(BattleFx.sound_of({"kind": "attack_started", "data": {"projectile": "bolt"}}), "battle_bolt")
	assert_eq(BattleFx.sound_of({"kind": "attack_started", "data": {"projectile": "javelin"}}), "battle_javelin")
	assert_eq(BattleFx.sound_of({"kind": "attack_started", "data": {"projectile": "arcane"}}), "battle_arcane", "the Ever-Regent's bolt")
	assert_eq(BattleFx.sound_of({"kind": "attack_started", "data": {"projectile": "", "first_charge": true}}), "battle_charge")
	assert_eq(BattleFx.sound_of({"kind": "attack_started", "data": {"projectile": ""}}), "", "a melee swing makes its sound when it lands")
	assert_eq(BattleFx.sound_of({"kind": "attack_landed", "i": 7, "data": {"hit": false, "projectile": "bolt"}}), "battle_miss")
	assert_eq(BattleFx.sound_of({"kind": "attack_landed", "i": 7, "data": {"hit": true, "projectile": ""}}), "battle_hit")
	assert_eq(BattleFx.sound_of({"kind": "attack_landed", "i": 9, "data": {"hit": true, "projectile": ""}}), "battle_clash", "every third beat index clashes")
	assert_eq(BattleFx.sound_of({"kind": "attack_landed", "i": 7, "data": {"hit": true, "projectile": "", "blocked": true}}), "battle_clash", "a blocked hit clashes")
	assert_eq(BattleFx.sound_of({"kind": "attack_landed", "i": 7, "data": {"hit": true, "projectile": "dive"}}), "battle_hit", "a Wings dive hits like melee")
	assert_eq(BattleFx.sound_of({"kind": "attack_landed", "i": 7, "data": {"hit": true, "projectile": "bolt"}}), "", "a bolt sounded when it flew")
	assert_eq(BattleFx.sound_of({"kind": "death", "data": {"ruler": true}}), "ruler_death")
	assert_eq(BattleFx.sound_of({"kind": "death", "data": {"ruler": false}}), "")
	assert_eq(BattleFx.sound_of({"kind": "rout", "data": {}}), "rout_horn")
	# Every cue the beats can give is one of the nine, and each is in audio.json.
	var a := GameAudio.new()
	a.quiet = true
	for cue in BattleFx.SOUNDS:
		assert_true(a.has_event(cue), "%s is in audio.json" % cue)
	for name in Fx.names():
		var fx := _fixture(name)
		for b in BattlePlayer.new(fx.log, fx.report).beats():
			var cue := BattleFx.sound_of(b)
			assert_true(cue.is_empty() or BattleFx.SOUNDS.has(cue), "%s: %s is a battle cue" % [name, cue])
	a.free()
	# The gate spaces repeats of a frequent cue in real time, and leaves the rare ones alone.
	var gate := BattleFx.SoundGate.new()
	assert_true(gate.allow("battle_hit", 0.0))
	assert_false(gate.allow("battle_hit", 0.03), "too soon: dropped")
	assert_true(gate.allow("battle_clash", 0.03), "another cue is its own")
	assert_true(gate.allow("battle_hit", 0.07), "later: plays")
	assert_true(gate.allow("rout_horn", 0.0) and gate.allow("rout_horn", 0.01), "a rare cue is never held back")
