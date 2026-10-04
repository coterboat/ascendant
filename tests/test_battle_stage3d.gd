extends "res://tests/test_case.gd"
## M3b, "battles on the land" (world3d/battle_stage.gd and its helpers): the 3D battle stage, headless.
## Nothing renders, but the stage's ground plan, figures, motions, effects, camera framing, projection and
## picking are all computed, so they are tested here exactly as the windowed stage runs them.
##   * every fixture (the 12 stored and the 4 path battles) plays to its end with no error, and every figure
##     ends standing, fallen or gone exactly as BattleTimeline's final state says
##   * beats map to the stage's actions (lunge, release and projectile, dive, recoil and impact, topple and
##     fallen, rout, heal, Iron Hide sparks, cheer, the aftermath's fade, camera shake)
##   * seeking and skipping land on BattleTimeline's state, and a sought stage stands as a played one
##   * watching changes nothing in the game: state, report, logs and record
##   * hovering and clicking a fighter drives BattleSelection and pins it in the why panel
##   * no raw id in anything the stage shows
##   * reduced motion turns off the shake, the bright frames, lunges and leaps, the deploy step
##   * the ground plan: every fighter its own place, ranks in order, the defender before its gate, a border
##     battle on its crossing, nobody in the sea, the same every time
##   * the camera frames every fighter inside the band the screen leaves clear, F reframes, a key-moment jump
##     frames the moment's camera hint
##   * the legend's stage rows are drawn by the stage's own functions; the war bear stands horse-sized
##   * the stage never rolls dice or resolves anything; the biggest battle plays inside the CPU budget
## Expected values come from the logs, the timeline and the data, never hardcoded.

const Fx := preload("res://tests/battle_playback_fixtures.gd")
const Scenarios := preload("res://tools/battle_log/scenarios.gd")
const Formation := preload("res://world3d/battle_formation.gd")
const Cam := preload("res://world3d/battle_camera.gd")
const Figures := preload("res://world3d/battle_figures.gd")
const Models := preload("res://world3d/models.gd")
const Kit := preload("res://world3d/kit.gd")
const W3D := preload("res://world3d/battle_watch3d.gd")
const STEP := 1.0 / 60.0
const CPU_AVG_MS := 2.0
const CPU_MAX_MS := 4.0
const STAGE_FILES := ["res://world3d/battle_stage.gd", "res://world3d/battle_figures.gd", "res://world3d/battle_formation.gd",
	"res://world3d/battle_camera.gd", "res://world3d/battle_watch3d.gd"]


func _fixture(name: String) -> Dictionary:
	var fx := Fx.battle(name)
	assert_false(fx.is_empty(), "battle %s loads" % name)
	return fx


func _stage(fx: Dictionary = {}, reduced := false) -> BattleStage3D:
	var s := BattleStage3D.new()
	s.reduced_motion = reduced
	if not fx.is_empty():
		assert_eq(s.show_battle(fx.log, fx.report), "", "the battle plays")
	return s


func _play_out(s: BattleStage3D, speed: int) -> int:
	s.player.set_speed(speed)
	s.player.play()
	var frames := 0
	while not s.player.is_finished() and frames < 100000:
		s.tick(STEP)
		frames += 1
	for k in 150:
		s.tick(STEP)
	return frames


## Every figure's hold ("stand", "fallen" or "gone") for the fighters of `st` (a timeline state).
static func _holds_of(st: Dictionary) -> Array:
	var out := []
	for fs in st.fighters:
		out.append("fallen" if not fs.alive else ("gone" if fs.fled or fs.lost else "stand"))
	return out


func _stage_holds(s: BattleStage3D) -> Array:
	var out := []
	for i in s.figures.n_fighters:
		out.append(String(s.figures.figs[i]["hold"]))
	return out


# --- every fixture ------------------------------------------------------------------------------------

func test_every_fixture_plays_to_the_timelines_final_state() -> void:
	var s := _stage()
	for name in Fx.names():
		var fx := _fixture(name)
		assert_eq(s.show_battle(fx.log, fx.report), "", "%s plays on the 3D stage" % name)
		assert_eq(s.figures.n_fighters, fx.log.fighters.size(), "%s: every fighter is its own figure" % name)
		assert_eq(s.figures.figs.size(), fx.log.fighters.size() + 2 * fx.log.sides.size(), "%s: and each side its bearer and musician" % name)
		_play_out(s, 4)
		var fin := s.player.timeline().final_state()
		assert_eq(s.player.state(), fin, "%s: the player ends on the final state" % name)
		assert_eq(_stage_holds(s), _holds_of(fin), "%s: every figure stands, lies or is gone as the final state says" % name)
		assert_true(s.end_card.visible, "%s: the result card is up" % name)
		## after the motions: standing figures are back in their places, fallen ones lie there
		var now := s.player.time()
		for i in s.figures.n_fighters:
			var p: Dictionary = s.figures.pose_at(i, now + 5.0)
			var hold := String(s.figures.figs[i]["hold"])
			if hold == "stand":
				assert_true((p["pos"] as Vector2).distance_to(s.figures.figs[i]["home"]) < 0.01 and float(p["scale"]) > 0.99,
					"%s: fighter %d stands in its place" % [name, i])
			elif hold == "fallen":
				assert_true(float(p["fall"]) >= 0.999, "%s: fighter %d lies where it fell" % [name, i])
			else:
				assert_false(bool(p["shown"]), "%s: fighter %d has left the field" % [name, i])
	s.free()


# --- beats to stage actions ------------------------------------------------------------------------------

## Fires beat `b` (and those sharing its time) from a seek just before it.
func _fire(s: BattleStage3D, b: Dictionary) -> void:
	s.player.seek_beat(int(b.i))
	s.player.play()
	s.tick(0.0001)
	s.player.pause()


func _has_motion(s: BattleStage3D, fid: int, kind: String) -> bool:
	for m in s.figures.figs[s.figures.index_of(fid)]["motions"]:
		if String(m["kind"]) == kind:
			return true
	return false


func _fx_kinds(s: BattleStage3D) -> Array:
	var out := []
	for e in s._fx:
		out.append(String(e["kind"]))
	return out


func test_beats_map_to_the_stages_actions() -> void:
	var s := _stage()
	var seen := {}
	for name in ["king_falls_wins", "skirmish", "path_wings", "path_lifedrinker", "path_iron_hide", "biggest"]:
		var fx := _fixture(name)
		assert_eq(s.show_battle(fx.log, fx.report), "", "%s plays" % name)
		var beats: Array = s.player.beats()
		for b in beats:
			if b.kind == "attack_landed" and b.data.hit and int(b.data.get("iron_hide", 0)) < 0 and not seen.has("iron"):
				_fire(s, b)
				assert_true(_fx_kinds(s).has("sparks"), "%s: Iron Hide sparks" % name)
				seen["iron"] = true
			match String(b.kind):
				"attack_started":
					var proj := String(b.data.projectile)
					var key := "start_" + (proj if proj != "" else "melee")
					if seen.has(key + name):
						continue
					seen[key + name] = true
					_fire(s, b)
					if proj == "":
						assert_true(_has_motion(s, int(b.fighter), "lunge"), "%s: a melee attack lunges at its target" % name)
						seen["lunge"] = true
					elif proj == "dive":
						assert_true(_has_motion(s, int(b.fighter), "dive"), "%s: Wings leap onto their target" % name)
						seen["dive"] = true
					else:
						assert_true(_has_motion(s, int(b.fighter), "shoot"), "%s: a shooter takes its strike pose" % name)
						assert_true(s._proj.size() >= 1, "%s: a %s flies" % [name, proj])
						assert_eq(String(s._proj[-1]["kind"]), proj, "%s: the projectile is the attacker's own" % name)
						seen[proj] = true
				"attack_landed":
					if not b.data.hit or seen.has("hit" + name):
						continue
					seen["hit" + name] = true
					_fire(s, b)
					assert_true(_has_motion(s, int(b.target), "recoil"), "%s: the target recoils" % name)
					assert_true(_fx_kinds(s).has("impact"), "%s: an impact lands" % name)
					seen["hit"] = true
				"death":
					if seen.has("death" + name):
						continue
					seen["death" + name] = true
					_fire(s, b)
					var i: int = s.figures.index_of(int(b.fighter))
					assert_eq(String(s.figures.figs[i]["hold"]), "fallen", "%s: the dead fall" % name)
					assert_true(_has_motion(s, int(b.fighter), "topple"), "%s: they topple first" % name)
					assert_true(_fx_kinds(s).has("dust"), "%s: and raise dust" % name)
					seen["death"] = true
				"rout":
					if seen.has("rout" + name):
						continue
					seen["rout" + name] = true
					_fire(s, b)
					for fid in b.data.fled:
						assert_eq(String(s.figures.figs[s.figures.index_of(int(fid))]["hold"]), "gone", "%s: the routed are leaving" % name)
						assert_true(_has_motion(s, int(fid), "rout"), "%s: running for the back edge" % name)
					seen["rout"] = true
				"heal":
					if seen.has("heal" + name):
						continue
					seen["heal" + name] = true
					_fire(s, b)
					assert_true(_fx_kinds(s).has("heal"), "%s: a heal rises green" % name)
					var texts := s._numbers.map(func(n): return String(n["text"]))
					assert_true(texts.has("+%d hp" % int(b.data.healed)), "%s: with its number" % name)
					seen["heal"] = true
				"end":
					_fire(s, b)
					var w := int(b.data.winner)
					var cheered := false
					for fid in fx.log.sides[w].fighters:
						if _has_motion(s, int(fid), "cheer"):
							cheered = true
					assert_true(cheered or b.data.how == "mutual", "%s: the winners cheer" % name)
					seen["end"] = true
	for want in ["lunge", "dive", "bolt", "javelin", "hit", "death", "rout", "heal", "end", "iron"]:
		assert_true(seen.has(want), "the fixtures exercised %s" % want)
	s.free()


func test_a_rulers_fall_bursts_and_shakes_the_camera() -> void:
	var s := _stage(_fixture("king_falls_wins"))
	var b := {}
	for x in s.player.beats():
		if x.kind == "death" and x.data.ruler:
			b = x
	assert_false(b.is_empty(), "the king falls in this battle")
	s.player.seek_beat(int(b.i))
	s.player.play()
	s.tick(0.0001)
	assert_true(_fx_kinds(s).has("burst"), "a gilt burst marks the fall")
	assert_eq(s.shakes_started, 1, "the camera shakes once")
	var before: Vector3 = s.wv.rig["target"]
	s.tick(0.05)
	assert_true((s.wv.rig["target"] as Vector3).distance_to(s.rig["target"]) > 0.0001, "the shake moves the camera off its rig")
	for k in 40:
		s.tick(STEP)
	assert_true((s.wv.rig["target"] as Vector3).distance_to(s.rig["target"]) < 0.0001, "and settles back")
	assert_true(before != Vector3.INF)
	s.free()


# --- seek and skip ----------------------------------------------------------------------------------------

func test_seeking_and_skipping_land_on_the_timelines_state() -> void:
	var s := _stage()
	for name in ["king_falls_wins", "forest_fort", "mutual_rout", "path_red_harvest", "border"]:
		var fx := _fixture(name)
		s.show_battle(fx.log, fx.report)
		var tl := s.player.timeline()
		var n: int = fx.log.events.size()
		var points := [0]
		for r in range(1, tl.rounds() + 1):
			points.append(tl.round_start(r))
		for k in range(0, n, maxi(1, n / 12)):
			points.append(k)
		for i in points:
			s.player.seek(i)
			assert_eq(_stage_holds(s), _holds_of(tl.state_at(i)), "%s: seeking to event %d shows that event's state" % [name, i])
		s.player.skip_to_end()
		s.tick(STEP)
		assert_eq(_stage_holds(s), _holds_of(tl.final_state()), "%s: skip lands on the final state" % name)
		assert_true(s.end_card.visible, "%s: with the result card" % name)
		## a stage played to a time stands as a stage sought to it (holds and places, after the motions)
		for frac in [0.35, 0.7]:
			var t: float = s.player.duration() * frac
			s.player.restart()
			s.player.set_speed(4)
			s.player.play()
			while s.player.time() < t and not s.player.is_finished():
				s.tick(STEP)
			s.player.pause()
			var played := _stage_holds(s)
			assert_eq(played, _holds_of(s.player.state()), "%s: played to %.1f s, the figures show the player's state" % [name, s.player.time()])
			## the beats at the very time playback stopped have fired: seek a hair past them (M3-4's 0.1 ms rule)
			var tt := s.player.time() + 0.0001
			s.player.seek_time(tt)
			assert_eq(_stage_holds(s), played, "%s: seeking to %.1f s equals playing to it" % [name, tt])
	s.free()


# --- watching changes nothing --------------------------------------------------------------------------

func test_watching_on_the_land_never_changes_the_game() -> void:
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
	var watch := W3D.new()
	for e in events:
		assert_eq(watch.watch(e, session.players()), "", "the battle can be watched on the land")
		var s: BattleStage3D = watch.stage
		_play_out(s, 4)
		s.player.seek_round(2)
		s.player.next_moment()
		s.tick(STEP)
		for fid in range(0, e.numbers.log.fighters.size(), 13):
			s.fighter_tooltip(fid)
			s.selection.select(fid)
		s.reframe()
		s.player.skip_to_end()
		s.tick(STEP)
		s.report_requested.emit(e)
		assert_true(watch.viewer.visible, "Full report opens the battle report viewer")
	assert_eq(var_to_str(events), events_before, "the watched events (their reports and logs) are unchanged")
	assert_eq(var_to_str(session.state().to_dict()), state_before, "the game state is unchanged")
	assert_eq(var_to_str(session.turn_report()), report_before, "the turn report is unchanged")
	assert_eq(var_to_str(session.record()), record_before, "the game record is unchanged")
	watch.free()


func test_the_stage_never_rolls_dice_or_resolves_anything() -> void:
	for path in STAGE_FILES:
		var text := FileAccess.get_file_as_string(path)
		assert_false(text.is_empty(), "%s can be read" % path)
		for banned in ["RandomNumberGenerator", "SeededRNG", "randf", "randi", "randomize(", "TurnResolver.", "AutoBattleResolver.new",
				".fight(", ".end_turn(", ".queue_order(", "seed("]:
			assert_false(text.contains(banned), "%s never uses %s" % [path, banned])


# --- hover and click ------------------------------------------------------------------------------------

## Where fighter `fid`'s upper body is on screen, in the stage's own coordinates.
func _screen_of(s: BattleStage3D, fid: int) -> Vector2:
	var e: Array = s.figures.ends_at(s.figures.index_of(fid), s.player.time())
	var v := Cam.project(s.wv.rig, s._view, (e[0] as Vector3).lerp(e[1], 0.55))
	return v / s._px + s.frame.position + Vector2(0, BattleSimpleView.TOP_H)


func test_hover_and_click_pick_a_fighter_for_the_selection() -> void:
	var s := _stage(_fixture("king_falls_wins"))
	s.player.seek_round(1)
	var picked := 0
	for f in s._log.fighters:
		var fid := int(f.id)
		var at := _screen_of(s, fid)
		var got := s.pick(at)
		if got == fid:
			picked += 1
		assert_true(got >= 0, "something is under %s" % f.name)
	assert_true(picked >= s._log.fighters.size() * 0.8, "a ray picks most fighters by their own upper body (%d of %d; the rest stand behind another)" % [picked, s._log.fighters.size()])
	var king := -1
	for f in s._log.fighters:
		if f.role == "ruler":
			king = int(f.id)
	var at2 := _screen_of(s, king)
	var mm := InputEventMouseMotion.new()
	mm.position = at2
	s._gui_input(mm)
	assert_eq(s._hovered, king, "hovering the king hovers him")
	assert_false(s._get_tooltip(at2).is_empty(), "and his tooltip explains him")
	assert_eq(s._get_tooltip(at2), s.fighter_tooltip(king), "in BattleExplain's words")
	s.controls.set_why(false, false)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = at2
	s._gui_input(click)
	assert_eq(s.selection.selected, king, "a click selects him in BattleSelection")
	assert_true(s.controls.why_open, "and opens the why panel")
	s.why_panel.refresh()
	assert_eq(int(s.why_panel.shown.selected), king, "which pins him")
	s._gui_input(click)
	assert_eq(s.selection.selected, -1, "a second click clears it")
	var empty := InputEventMouseButton.new()
	empty.button_index = MOUSE_BUTTON_LEFT
	empty.pressed = true
	empty.position = s.frame.position + Vector2(8, BattleSimpleView.TOP_H + 8)
	s.selection.select(king)
	s._gui_input(empty)
	assert_eq(s.selection.selected, -1, "a click on empty land clears the selection")
	s.free()


func test_tab_order_goes_from_the_screens_left_side_front_to_back() -> void:
	var s := _stage(_fixture("king_falls_wins"))
	var order := s._tab_order()
	assert_eq(order.size(), s._log.fighters.size(), "every fighter is in the Tab order once")
	var left := int(s.layout.left)
	var seen_right := false
	for fid in order:
		var side := int(s._log.fighters[int(fid)].side)
		if side != left:
			seen_right = true
		assert_false(seen_right and side == left, "the left side comes first")
	s.free()


# --- texts ------------------------------------------------------------------------------------------

func test_no_visible_text_has_a_raw_id() -> void:
	var s := _stage()
	for name in Fx.names():
		var fx := _fixture(name)
		s.show_battle(fx.log, fx.report)
		var ids := _raw_ids(fx.log)
		var texts := []
		for i in [0, s.player.timeline().round_start(1) + 2]:
			s.player.seek(i)
			texts.append_array(s.visible_texts())
		s.player.play()
		for k in 300:
			s.tick(STEP)
		texts.append_array(s.visible_texts())
		s.player.skip_to_end()
		s.tick(STEP)
		texts.append_array(s.visible_texts())
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
	s.free()


func _raw_ids(battle_log: Dictionary) -> Array:
	var ids := {}
	for sd in battle_log.sides:
		ids[String(sd.faction)] = true
		for a in sd.armies:
			ids[String(a.id)] = true
		for m in sd.mandates:
			ids[String(m)] = true
		var people = sd.get("people", {})
		if people is Dictionary and not people.is_empty():
			ids[String(people.id)] = true
	for f in battle_log.fighters:
		ids[String(f.type)] = true
		if not f.ruler.is_empty():
			ids[String(f.ruler.id)] = true
	for p in battle_log.provinces:
		ids[String(p)] = true
	if not String(battle_log.id).is_empty():
		ids[String(battle_log.id)] = true
	return ids.keys()


# --- reduced motion --------------------------------------------------------------------------------

func test_reduced_motion_turns_off_shake_flashes_lunges_and_leaps() -> void:
	for name in ["king_falls_wins", "knights_charge", "path_wings"]:
		var fx := _fixture(name)
		var full := _stage(fx)
		var bright_full := _count_while_playing(full)
		assert_true(full.lunges_started > 0, "%s: with motion, melee attacks lunge" % name)
		assert_true(bright_full > 0, "%s: with motion, impacts start bright (under the flash limiter)" % name)
		full.free()
		var calm := _stage(fx, true)
		var bright := _count_while_playing(calm)
		assert_eq(calm.lunges_started, 0, "%s: reduced motion: no lunges or leaps" % name)
		assert_eq(calm.shakes_started, 0, "%s: no camera shake" % name)
		assert_eq(bright, 0, "%s: no bright impact frames" % name)
		assert_true(calm.player.reduced_motion, "%s: and no slow motion" % name)
		calm.free()


## Plays `s` at 1x, watching every figure's place and the impacts: returns how many impacts started bright,
## and fails when a figure leaves its place with reduced motion on (other than a rout or a fade).
func _count_while_playing(s: BattleStage3D) -> int:
	var bright := 0
	s.player.play()
	var frames := 0
	while not s.player.is_finished() and frames < 20000:
		s.tick(STEP)
		frames += 1
		for e in s._fx:
			if String(e["kind"]) == "impact" and int(e["frames"]) == 1:
				if bool(e.get("bright", false)):
					bright += 1
				if s.reduced_motion:
					assert_true(bool(e.get("ring", false)), "with reduced motion an impact is a still ring")
		if s.reduced_motion and frames % 7 == 0:
			var now := s.player.time()
			for i in s.figures.n_fighters:
				var f: Dictionary = s.figures.figs[i]
				if String(f["hold"]) != "stand":
					continue
				var p: Dictionary = s.figures.pose_at(i, now)
				assert_true((p["pos"] as Vector2).distance_to(f["home"]) < 0.001 and float(p["extra_y"]) == 0.0 and float(p["hop"]) == 0.0,
					"with reduced motion figure %d stays in its place" % i)
	return bright


func test_impacts_never_flash_more_than_three_times_a_second() -> void:
	var s := _stage(_fixture("biggest"))
	s.player.set_speed(4)
	s.player.play()
	var starts := []
	var frames := 0
	while not s.player.is_finished() and frames < 20000:
		s.tick(STEP)
		frames += 1
		for e in s._fx:
			if String(e["kind"]) == "impact" and int(e["frames"]) == 1 and bool(e.get("bright", false)):
				starts.append(s._real)
	assert_true(starts.size() > 0, "big battles do flash")
	for k in starts.size():
		var n := 0
		for t in starts:
			if float(t) >= float(starts[k]) and float(t) < float(starts[k]) + BattleFx.FLASH_WINDOW - 0.0001:
				n += 1
		assert_true(n <= BattleFx.MAX_FLASHES, "at most %d bright starts in any second (%d)" % [BattleFx.MAX_FLASHES, n])
	s.free()


# --- the ground plan ---------------------------------------------------------------------------------------

func test_every_fighter_has_its_own_place_in_rank_order_on_land() -> void:
	var t: RefCounted = Board3D.terrain_now()
	var s := _stage()
	for name in Fx.names():
		var fx := _fixture(name)
		s.show_battle(fx.log, fx.report)
		var plan: Dictionary = s.plan
		var again := Formation.plan(fx.log, t, s._world_info(), s._band().size.x / s._band().size.y)
		assert_eq(var_to_str(again["slots"]), var_to_str(plan["slots"]), "%s: the same log stands the same way every time" % name)
		var slots: Array = plan["slots"]
		var axis: Vector2 = plan["axis"]
		var site: Vector2 = plan["site"]
		for a in slots.size():
			var sa: Dictionary = slots[a]
			var pa: Vector2 = sa["pos"]
			assert_true(t.coast_at(pa) > 0.0, "%s: fighter %d stands on land" % [name, a])
			for b in range(a + 1, slots.size()):
				var sb: Dictionary = slots[b]
				var d := pa.distance_to(sb["pos"])
				assert_true(d > 2.5, "%s: fighters %d and %d have places of their own (%.1f apart)" % [name, a, b, d])
		## ranks: a side's tier 0 nearer the middle than its tier 1, its tier 1 nearer than its tier 2
		for si in fx.log.sides.size():
			var near := {}
			for fid in fx.log.sides[si].fighters:
				var sl: Dictionary = slots[int(fid)]
				var depth := absf(((sl["pos"] as Vector2) - site).dot(axis))
				var tier := int(sl["tier"])
				near[tier] = minf(float(near.get(tier, INF)), depth)
				near["max%d" % tier] = maxf(float(near.get("max%d" % tier, -INF)), depth)
			for tier in [0, 1]:
				if near.has(tier) and near.has(tier + 1):
					assert_true(float(near["max%d" % tier]) < float(near[tier + 1]), "%s: side %d's rank %d stands in front of rank %d" % [name, si, tier, tier + 1])
		## the two sides face each other across the middle
		var dn: float = ((slots[int(fx.log.sides[int(plan.near)].fighters[0])]["pos"] as Vector2) - site).dot(axis)
		var df: float = ((slots[int(fx.log.sides[int(plan.far)].fighters[0])]["pos"] as Vector2) - site).dot(axis)
		assert_true(dn < 0.0 and df > 0.0, "%s: the near side stands on its half, the far side on the other" % name)
	s.free()


func test_the_battle_stands_where_geography_puts_it() -> void:
	var t: RefCounted = Board3D.terrain_now()
	var s := _stage()
	## a fortress: the defender before its own gate, the walls behind it
	var big := _fixture("biggest")
	## the woods, rocks and houses where a battle stands are lifted off the table, and come back after it
	var lifted_any := 0
	for name in Fx.names():
		var fx := _fixture(name)
		s.show_battle(fx.log, fx.report)
		assert_eq(_props_inside(s), 0, "%s: no tree, rock or house stands on the battle's ground" % name)
		var lifted := s.cleared_count()
		lifted_any += lifted
		var there := s.props_standing_on(s.plan.footprint, true)
		assert_true(lifted >= there, "%s: every one there was lifted (%d of %d)" % [name, lifted, there])
		s.restore_ground()
		assert_eq(s.cleared_count(), 0, "%s: afterwards they are put back" % name)
		assert_eq(_props_inside(s), there, "%s: all %d of them" % [name, there])
		s.clear_for(s.plan.footprint)
	assert_true(lifted_any > 0, "some battles stand where woods or houses stood")
	s.show_battle(big.log, big.report)
	assert_eq(String(s.plan.where), "gate", "a defended capital is fought before its gate")
	var dsi := -1
	for sd in big.log.sides:
		if sd.defender:
			dsi = int(sd.index)
	assert_eq(int(s.plan.near), dsi, "the defender stands nearest the walls")
	var gate: Array = s.wv.gate_points("crownkeep")
	for fid in big.log.sides[dsi].fighters:
		var p: Vector2 = s.plan.slots[int(fid)]["pos"]
		assert_true(p.distance_to(t.centre_of("crownkeep")) > (gate[1] as Vector2).distance_to(t.centre_of("crownkeep")) - 1.0,
			"the defenders stand outside the gate")
	## a border battle on its crossing
	var border := _fixture("border")
	s.show_battle(border.log, border.report)
	assert_eq(String(s.plan.where), "border")
	var x: Vector2 = t.crossing(String(border.log.provinces[0]), String(border.log.provinces[1]))
	assert_true((s.plan.site as Vector2).distance_to(x) < 0.01, "a border battle stands on the crossing")
	## a fort the world doesn't have: the stage puts one up behind the defender
	var fort := _fixture("forest_fort")
	s.show_battle(fort.log, fort.report)
	assert_eq(String(s.plan.where), "fort")
	assert_true(s.stage_fort != null, "the fort stands")
	var fp: Vector2 = s.plan.fort["pos"]
	var site: Vector2 = s.plan.site
	assert_true((fp - site).dot(s.plan.axis) < 0.0, "behind the defender's half")
	## a fort the world has (Stonegate)
	var sg := _fixture("round_cap_defender")
	s.show_battle(sg.log, sg.report)
	assert_eq(String(s.plan.where), "fort")
	assert_true(bool(s.plan.fort.get("world", false)), "Stonegate's own fort stands behind its defender")
	assert_true(s.stage_fort == null, "and the stage adds none")
	## the attacker forms up toward the road home
	var kf := _fixture("king_falls_wins")
	s.show_battle(kf.log, kf.report)
	var asi := 1 - int(s.plan.near)
	var home := Formation.home_dir(t, "rivermarch", String(kf.log.sides[asi].faction))
	assert_true((s.plan.axis as Vector2).dot(home) > 0.5, "the attacker stands toward the border it came by")
	s.free()


## How many woods, rocks and houses stand on the battle's footprint.
func _props_inside(s: BattleStage3D) -> int:
	return s.props_standing_on(s.plan.footprint)


# --- the camera -------------------------------------------------------------------------------------------

func test_the_camera_frames_every_fighter_in_the_band() -> void:
	var t: RefCounted = Board3D.terrain_now()
	var s := _stage()
	for name in Fx.names():
		var fx := _fixture(name)
		s.show_battle(fx.log, fx.report)
		var band := s._band().grow(4.0)
		for f in fx.log.fighters:
			var e: Array = s.figures.ends_at(int(f.id), 0.0)
			for p in e:
				var v := Cam.project(s.wv.rig, s._view, p)
				assert_true(band.has_point(v), "%s: %s stands inside the band the screen leaves clear (%s)" % [name, f.name, v])
		assert_true(Cam.sees_all(t, s.goal, s._points([], true), s._obstacles()) or float(s.goal.pitch) >= Cam.PITCH_MAX,
			"%s: no hill or wall hides anyone (or the camera looks down as steeply as it may)" % name)
		var pitch := float(s.goal.pitch)
		assert_true(pitch >= Cam.PITCH_MIN and pitch <= Cam.PITCH_MAX, "%s: the pitch stays in the battle's range (%.0f)" % [name, pitch])
	s.free()


func test_f_reframes_and_a_jump_frames_the_moment() -> void:
	var s := _stage(_fixture("king_falls_wins"))
	var whole := s.goal.duplicate()
	## the right button turns the camera; F frames the whole battle again
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	s._gui_input(press)
	var drag := InputEventMouseMotion.new()
	drag.relative = Vector2(120, 30)
	s._gui_input(drag)
	assert_true(absf(float(s.rig.yaw) - float(whole.yaw)) > 10.0, "a right-drag turns the camera")
	var key := InputEventKey.new()
	key.keycode = KEY_F
	key.pressed = true
	assert_true(s.controls.handle_key(key), "F is the reframe key")
	for k in 90:
		s.tick(STEP)
	assert_true(absf(float(s.rig.yaw) - float(whole.yaw)) < 0.01 and absf(float(s.rig.span) - float(whole.span)) < 0.01, "F frames the whole battle again")
	## a key-moment jump frames the moment's fighters, then rises back
	var m := s.player.jump_to_moment("ruler_falls")
	assert_false(m.is_empty(), "the king's fall is a key moment")
	assert_eq(s.focus_moves, 1, "the jump frames the moment's camera hint")
	for k in 70:
		s.tick(STEP)
	var subject := int(m.camera.fighters[0])
	var sp: Vector2 = s.plan.slots[subject]["pos"]
	var tg: Vector3 = s.rig.target
	assert_true(float(s.rig.span) < float(whole.span) - 0.5, "it comes in closer than the whole battle")
	assert_true(Vector2(tg.x, tg.z).distance_to(sp) < Vector2((whole.target as Vector3).x, (whole.target as Vector3).z).distance_to(sp) + 0.01,
		"toward the falling king")
	s.player.play()
	for k in int((BattleStage3D.FOCUS_HOLD + BattleStage3D.MOVE_TIME + 0.5) / STEP):
		s.tick(STEP)
	assert_true(absf(float(s.rig.span) - float(s.goal.span)) < 0.01, "after the moment the camera rises back to the whole battle")
	s.free()


# --- legend and models --------------------------------------------------------------------------------------

func test_the_stages_legend_rows_are_drawn_by_its_own_functions() -> void:
	var rows := BattleLegend.overlay_rows() + BattleStage3D.stage_rows()
	var src := ""
	for f in STAGE_FILES:
		src += FileAccess.get_file_as_string(f) + "\n"
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
		if parts[0] == "BattleStage3D" or parts[0] == "BattleEffects" or parts[0] == "BattleCard":
			var calls := src.count(parts[1] + "(") - src.count("func " + parts[1] + "(")
			assert_true(calls >= 1, "%s: the stage draws with %s" % [r.id, r.drawn_by])
		assert_true((r.draw as Callable).is_valid() or r.has("node"), "%s draws something" % r.id)
	for want in ["figure3d", "ruler3d", "commander3d", "ranks3d", "fallen3d", "lunge3d", "dive3d", "rout3d", "bolt3d", "javelin3d", "arcane3d",
			"impact", "big_impact", "ring", "dust", "sparks", "heal_rise", "burst", "select_ring", "aura_ring", "shake3d", "fort3d", "camera3d",
			"hp_bar", "number", "miss", "heal", "iron_hide", "strength_bar", "notch"]:
		assert_true(ids.has(want), "the 3D legend has a row for %s" % want)
	var s := BattleStage3D.new()
	assert_eq(s.legend.rows.size(), rows.size(), "the stage's legend lists the overlay's rows and its own")
	s.free()


func _class_script(class_name_text: String) -> Script:
	for c in ProjectSettings.get_global_class_list():
		if String(c["class"]) == class_name_text:
			return load(String(c.path))
	return null


func test_war_bears_and_the_other_big_models_stand_at_the_bibles_creature_scale() -> void:
	## STYLE_BIBLE.md 8.4: a large figure (mounted, beast) is 1.3-2.0 men; a monster ruler 2.5-3.5 men tall.
	## A war bear stands on all fours, so its longest side is its size: horse-sized, never bigger than a
	## mounted knight.
	var bear := Formation.footprint_of("war_bear")
	var bear_h := Formation.height_of("war_bear")
	var knight := Formation.footprint_of("knights")
	var knight_h := Formation.height_of("knights")
	var bear_men := maxf(bear.x, bear.y) / Kit.FIG
	assert_true(bear_men >= 1.3 and bear_men <= 2.0, "a war bear is 1.3-2.0 men long (%.2f)" % bear_men)
	assert_true(bear_h < knight_h, "and shorter than a knight on his horse")
	assert_true(maxf(bear.x, bear.y) <= maxf(knight.x, knight.y) * 1.05, "and no longer than the horse")
	for type_id in ["knights", "tuskers", "knight_captain", "warchief"]:
		var fp := Formation.footprint_of(type_id)
		var men := maxf(maxf(fp.x, fp.y), Formation.height_of(type_id)) / Kit.FIG
		assert_true(men <= 2.0, "%s stays within the large figures' 2 men (%.2f)" % [type_id, men])
	for ruler in ["aurel_king", "ever_regent", "fang_chieftain"]:
		var h := float(Models.figure_row(ruler).get("height", 0.0))
		assert_true(h >= 1.2 and h <= 1.45, "%s is a human-sized ruler (%.2f men)" % [ruler, h])
	var mh := float(Models.figure_row("thornmane_avatar").get("height", 0.0))
	assert_true(mh >= 2.5 and mh <= 3.5, "the Great Thornmane is a monster ruler (%.2f men)" % mh)


# --- odds and ends -----------------------------------------------------------------------------------------

func test_battles_that_cant_be_watched_say_why_on_the_land_too() -> void:
	var s := BattleStage3D.new()
	assert_eq(s.show_event({"type": "battle", "text": "A battle.", "numbers": {}}), "This battle was fought with the test rules and has no playback.")
	var fx := _fixture("skirmish")
	var three: Dictionary = fx.log.duplicate(true)
	three.sides.append(three.sides[0].duplicate(true))
	assert_eq(s.show_battle(three), "Battles with more than two sides can't be watched yet.")
	assert_eq(s.show_battle(fx.log, fx.report), "", "a good log plays")
	assert_false(s.message_panel.visible, "and the message goes away")
	s.free()


func test_the_launcher_plays_a_fixture_and_a_path_battle() -> void:
	var w := W3D.new()
	for name in ["starting_plains", "path_wings"]:
		var fx: Dictionary = W3D.load_fixture(name)
		assert_false(fx.is_empty(), "the launcher finds %s" % name)
		assert_eq(w.watch(fx), "", "and plays it")
		assert_true(w.stage.player != null and w.stage.figures.n_fighters == fx.log.fighters.size())
	w.stage.codex_requested.emit("battle_playback")
	assert_true(w.codex.visible, "the codex opens over the stage")
	w.free()


func test_the_biggest_battle_plays_inside_the_cpu_budget() -> void:
	var fx := _fixture("biggest")
	var s := _stage(fx)
	var times := []
	s.player.set_speed(4)
	s.player.play()
	var frames := 0
	while not s.player.is_finished() and frames < 10000:
		var t0 := Time.get_ticks_usec()
		s.tick(STEP)
		times.append((Time.get_ticks_usec() - t0) / 1000.0)
		frames += 1
	var total := 0.0
	var worst := 0.0
	for ms in times:
		total += float(ms)
		worst = maxf(worst, float(ms))
	var avg := total / maxf(1.0, float(times.size()))
	print("     biggest fixture on the 3D stage at 4x, headless, %d frames: stage CPU avg %.2f ms, worst %.2f ms" % [times.size(), avg, worst])
	assert_true(s.player.is_finished(), "the biggest battle plays to its end")
	assert_perf(avg <= CPU_AVG_MS, "average %.2f ms per frame (budget %.1f ms)" % [avg, CPU_AVG_MS])
	assert_perf(worst <= CPU_MAX_MS * 3.0, "worst frame %.2f ms (budget %.1f ms, x3 for the frames a seek rebuilds every figure)" % [worst, CPU_MAX_MS])
	s.free()


# --- the host (M3-5, ui/battle/README.md) -----------------------------------------------------------------

func test_the_stage_keeps_the_battle_view_contract_in_the_host() -> void:
	assert_eq(BattleHost.STAGE_3D_PATH, "res://world3d/battle_stage.tscn", "the host loads the stage from its scene")
	assert_true(BattleHost.has_stage_3d(), "the 3D stage is in the game")
	assert_eq(BattleFx.DEFAULTS.view, "3d", "3D on the land is the default battle view")
	var path := GameSettings.default_path.get_base_dir().path_join("stage_host_%d.cfg" % OS.get_process_id())
	DirAccess.remove_absolute(path)
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/main_records.json"))
	var rec := {}
	for g in data.games:
		if String(g.name) == "m1_greedy_vs_ai":
			rec = g.record.duplicate(true)
			rec.history = rec.history.slice(0, 5)
	var loaded := GameSession.from_record(rec)
	assert_eq(loaded.errors, [], "the recorded game loads")
	var session: GameSession = loaded.session
	var battles := session.battle_events()
	assert_true(battles.size() >= 2, "the turn had battles to queue")
	var state_before := var_to_str(session.state().to_dict())
	var h := BattleHost.new()
	h.settings_path = path
	var winner := String(battles[0].numbers.winner)
	assert_eq(h.open(battles, 0, session, winner), "", "the host opens the queue")
	assert_eq(h.view_kind, "3d", "on the 3D stage, the default")
	assert_true(h.view is BattleStage3D, "the real stage")
	assert_true(BattleHost.keeps_contract(h.view), "which keeps the battle view contract")
	var stage: BattleStage3D = h.view
	assert_false(h.note_label.visible, "no fallback note")
	assert_true(stage.controls is BattleControls and stage.controls.queue_row.visible, "the host's queue row is on the stage's bar")
	assert_true(stage.controls.buttons.settings.visible, "and its Settings button")
	assert_eq(var_to_str(stage.player.battle_log()), var_to_str(battles[0].numbers.log), "it plays the first battle's log")
	assert_true(stage.figures.n_fighters == battles[0].numbers.log.fighters.size(), "on the land, every fighter a figure")
	var finished := [0]
	stage.finished.connect(func(): finished[0] += 1)
	stage.player.play()
	stage.player.skip_to_end()
	assert_eq(finished[0], 1, "finished when the result card is up")
	assert_eq(h.last_sting, "sting_victory", "and the host plays the viewer's sting")
	assert_true(stage.buttons.next_battle_card.visible, "the result card offers the next battle")
	stage.controls.next_requested.emit()
	assert_eq(h.index, 1, "the stage's bar moves the host's queue")
	assert_eq(var_to_str(stage.player.battle_log()), var_to_str(battles[1].numbers.log), "the same stage plays the next battle")
	stage.close()
	assert_false(h.visible, "closing the stage closes the host")
	assert_eq(var_to_str(session.state().to_dict()), state_before, "and the game is as it was")
	h.free()
	DirAccess.remove_absolute(path)
