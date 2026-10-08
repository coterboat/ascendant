extends "res://tests/test_case.gd"
## M5-3 (#114) acceptance, fog of war on the 3D board (design/M5_MAGIC_FOG.md §2, §12.1, §18): the board draws the viewer's
## view and never the truth. Headless: nothing renders, but the board's armies, plates, ground sight, playback beats and
## sounds are all computed, so they are tested here exactly as the windowed game runs them.
##   * a static scan: no truth accessor anywhere in world3d/, and the board code rolls no dice (test_board3d's BOARD_FILES)
##   * the board's armies equal the view's, with no instance for a hidden army; the vision texture is the viewer's sight
##   * the proof: changing anything hidden from the viewer (FogTestKit.perturb_hidden) changes nothing the board builds,
##     nor anything its playback does (beats, sounds, the board after every step)
##   * the board after a playback equals the board built from the view after, and its model equals
##     FogRules.apply_view_events, beats included (3 games x 12 turns, both viewers)
##   * stand-ins draw from the shown counts under a "≈" plate; memory ghosts have their own material and fade a step every
##     2 turns (the ghost-recruit count stays exact); a rival column marching out of sight walks to the border and fades
##   * rituals from hidden casters start at the target; sound only for what the viewer sees
##   * the legend, the plates and the tooltips name clear / glimpsed / out of sight and how old a ghost is
##   * a hotseat handoff leaves nothing of the last seat on the board
##   * with fog off the board is unchanged (every older board test holds as it was)
## Expected values come from the data and the states, never hardcoded.

const Kit := preload("res://tests/fog_test_kit.gd")
const BoardTests := preload("res://tests/test_board3d.gd")
const Playback := preload("res://world3d/playback.gd")
const Vision := preload("res://world3d/vision.gd")
const Models := preload("res://world3d/models.gd")
const Armies := preload("res://world3d/armies.gd")
const Stands := preload("res://world3d/stands.gd")
const WorldView := preload("res://world3d/world_view.gd")
const BOARD_SIZE := Vector2(1200, 836)
const CROWN := "kingdom"
const CLANS := "beasts"
## The truth accessors (§2.1): nothing in world3d/ may call them, there are no observer paths on the board.
const TRUTH := ["state", "turn_report", "battle_events", "builds", "record", "history", "victory"]

static var _board_cache: Board3D = null


# --- fixtures --------------------------------------------------------------------------------------------

## A board standing `view` as `viewer` sees it, with its memory (as GameScreen._set_map_for gives the map before the state).
func _board(view: GameState, viewer: String, memory: Dictionary, intel: Dictionary, before: GameState) -> Board3D:
	var map := load("res://ui/map_screen.tscn").instantiate() as MapScreen
	map.set_fog(memory, intel, before)
	map.set_state(view, viewer)
	var b := Board3D.new()
	map.set_board(b)
	b.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	b.size = BOARD_SIZE
	b.build_now()
	return b


## The same board standing another view (as the map screen changes its state: set_fog, then set_state).
func _stand(b: Board3D, view: GameState, viewer: String, memory: Dictionary, intel: Dictionary, before: GameState) -> void:
	b.map.set_fog(memory, intel, before)
	b.map.set_state(view, viewer)


func _free(b: Board3D) -> void:
	var map: Node = b.map
	if map != null:
		map.free()
	elif is_instance_valid(b):
		b.free()


func _game(config: Dictionary) -> GameScreen:
	var game := load("res://ui/game_screen.tscn").instantiate() as GameScreen
	game.autosave_enabled = false
	game.start_game(config)
	return game


## Everything the board builds of a view that a player could look at, as one dictionary: the ground's sight, every army's
## figures, ghosts, camps, plates, tags and tooltips, the legend. Two boards that read the same view must have the same model.
func _model(b: Board3D) -> Dictionary:
	var plates := {}
	for id in b.overlay._army_plates:
		var pc: PanelContainer = b.overlay._army_plates[id]
		var texts := []
		for l in pc.find_children("*", "Label", true, false):
			texts.append((l as Label).text)
		plates[id] = {"texts": texts, "tip": pc.tooltip_text, "modulate": pc.modulate}
	var tags := {}
	for pid in b.overlay._plates:
		var l: Label = b.overlay._plates[pid].get("sight")
		tags[pid] = [l.visible, l.text, l.tooltip_text] if l != null else []
	var camps := {}
	for pid in b.armies.camps:
		var tents := []
		for tn in b.armies.camps[pid]["tents"]:
			tents.append(tn["pos"])
		camps[pid] = {"tents": tents, "fires": b.armies.camps[pid]["fires"]}
	var army_tips := {}
	for id in b.armies.armies:
		army_tips[id] = b.overlay.army_tooltip(String(id))
	var province_tips := {}
	for p in b.map.state.provinces:
		province_tips[p.id] = b.overlay.province_tooltip(p.id)
	return {"vision": Array(b.wv.vision_bytes()), "fog_on": b.wv.fog_on, "levels": b.vision_levels.duplicate(), "owners": b.wv.owners_painted(),
		"full": b.armies.full_snapshot(), "snapshot": b.armies.snapshot(), "memory": b.armies.memory_list(), "stand_ins": b.armies.stand_in_list(),
		"ghosts": b.armies.ghost_list(), "camps": camps, "plates": plates, "tags": tags, "legend": b.overlay.legend_text(),
		"army_tips": army_tips, "province_tips": province_tips, "stands": Stands.plan_of(b.armies), "figures": b.armies.figure_count()}


## The keys of two models whose values differ ("" for none).
func _diff(a: Dictionary, b: Dictionary) -> String:
	var bad := []
	for k in a:
		if var_to_str(a[k]) != var_to_str(b.get(k)):
			bad.append(k)
	for k in b:
		if not a.has(k):
			bad.append(k)
	return ", ".join(bad)


## The playing of one turn on `b`, standing the view after first (as the game does it), stepped to its end: true when it
## played and ended. snap_at_end is off, so the board is as the playback left it. `log` collects what the playback did.
func _play(b: Board3D, vb: GameState, events: Array, va: GameState, viewer: String, memory: Dictionary, intel: Dictionary,
		log: Array = [], step: float = 1.0 / 15.0) -> bool:
	_stand(b, va, viewer, memory, intel, vb)
	b.armies.snap_at_end = false
	b.sounds.clear()
	b.rituals_played.clear()
	if not b.play_turn(vb, events, va):
		return false
	var guard := 0
	while b.is_playing() and guard < 9000:
		b.armies.step_playback(step)
		guard += 1
		if guard % 12 == 0:
			log.append(_step_line(b))
	b.armies.snap_at_end = true
	return not b.is_playing()


## One line of what the board shows mid-playback: the ground's sight, the figures and the ghosts.
func _step_line(b: Board3D) -> String:
	return "%s|%s|%s|%s|%d" % [Array(b.wv.vision_bytes()), b.armies.snapshot().hash(), b.armies.memory_list().keys(), b.armies.phase_now().get("key", ""),
		b.armies.figure_count()]


## What differs between two board models (Playback.model_of): ["key: id (played X, built Y)"], short enough to read.
func _model_diff(played: Dictionary, built: Dictionary) -> Array:
	var out := []
	for k in played:
		if not built.has(k):
			out.append("%s only in the played model" % k)
			continue
		var a = played[k]
		var b = built[k]
		if a is Dictionary and b is Dictionary:
			for id in a:
				if not b.has(id):
					out.append("%s: %s only played (%s)" % [k, id, str(a[id])])
				elif var_to_str(a[id]) != var_to_str(b[id]):
					out.append("%s: %s played %s, built %s" % [k, id, str(a[id]), str(b[id])])
			for id in b:
				if not a.has(id):
					out.append("%s: %s only built (%s)" % [k, id, str(b[id])])
		elif var_to_str(a) != var_to_str(b):
			out.append("%s differs" % k)
	for k in built:
		if not played.has(k):
			out.append("%s only in the built model" % k)
	return out


func _json(v) -> String:
	return JSON.stringify(v.to_dict() if v is GameState else v)


## The kit's games of one kind first (m1, m2, m4, sieges), so a short loop covers every kind.
func _sampled_games(count: int) -> Array:
	return Kit.games().slice(0, count)


func _gd_files(dir: String) -> Array:
	var out := []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_gd_files(dir.path_join(d)))
	return out


## A line of code without its comment ("" for a comment line); a "#" inside a string doesn't start a comment.
static func _code_part(line: String) -> String:
	var s := line.strip_edges()
	if s.begins_with("#"):
		return ""
	var quote := ""
	for i in line.length():
		var c := line[i]
		if quote.is_empty() and (c == "\"" or c == "'"):
			quote = c
		elif c == quote and (i == 0 or line[i - 1] != "\\"):
			quote = ""
		elif c == "#" and quote.is_empty():
			return line.substr(0, i)
	return line


# --- the static scans ---------------------------------------------------------------------------------

func test_no_truth_accessor_anywhere_in_world3d() -> void:
	var files := _gd_files("res://world3d")
	assert_true(files.size() >= 20, "the scan reads every world3d script (%d)" % files.size())
	var re := RegEx.new()
	re.compile("\\.(%s)\\(\\)|\\bOBSERVER\\b|\\bGameSession\\b|\\.session\\b|\\bsession\\._[a-z_]+" % "|".join(TRUTH))
	var found := []
	for path in files:
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for i in lines.size():
			var code := _code_part(lines[i])
			if not code.is_empty() and re.search(code) != null:
				found.append("%s:%d: %s" % [path.get_file(), i + 1, lines[i].strip_edges()])
	assert_eq(found, [], "the board reads its map's view and nothing else: no truth accessor, no session, no observer")


func test_the_board_code_rolls_no_dice_and_resolves_nothing() -> void:
	var files: Array = Array(BoardTests.BOARD_FILES) + ["res://world3d/vision.gd", "res://world3d/stands.gd", "res://world3d/trays.gd"]
	for path in files:
		var text := FileAccess.get_file_as_string(path)
		assert_false(text.is_empty(), "%s can be read" % path)
		for banned in ["RandomNumberGenerator", "SeededRNG", "randf(", "randi(", "randomize(", "TurnResolver.resolve", ".end_turn(",
				".queue_order(", ".acknowledge_handoff(", "FogRules.view_state(", "FogRules.report_for(", "FogRules.turn_for("]:
			assert_false(text.contains(banned), "%s never uses %s" % [path, banned])


# --- the board is the view ------------------------------------------------------------------------

func test_the_vision_texture_is_the_viewers_sight() -> void:
	var seen_levels := {}
	var b: Board3D = null
	var checks := 0
	for g in Kit.games():
		for i in g.turns.size():
			if i % 4 != 1:
				continue
			var t: Dictionary = g.turns[i]
			for v in Kit.SEATS:
				var view: GameState = t.view_after[v]
				if b == null:
					b = _board(view, v, t.memory_after[v], t.intel_after[v], t.view_before[v])
				else:
					_stand(b, view, v, t.memory_after[v], t.intel_after[v], t.view_before[v])
				var label := "%s turn %d, %s" % [g.name, t.turn, v]
				assert_true(b.wv.fog_on, "%s: the veil is on" % label)
				assert_eq(b.wv.vision_bytes().size(), Vision.WIDTH, "%s: a 16 x 1 texture, a texel for each province index" % label)
				# the ground is the TRUE sight of the viewer (a view's own sight equals the truth's), with "never" from its memory
				var sight := FogRules.sight(t.after, v)
				var ids: Array = b.wv.terrain.ids
				for k in ids.size():
					var pid: String = ids[k]
					var want: int
					match String(sight[pid]):
						"clear":
							want = 255
						"glimpse":
							want = 170
						_:
							want = 0 if int(t.memory_after[v].provinces.get(pid, {}).get("seen_turn", -1)) < 0 else 85
					assert_eq(int(b.wv.vision_bytes()[k]), want, "%s: %s's texel" % [label, pid])
					seen_levels[int(b.wv.vision_bytes()[k])] = true
					assert_eq(b.vision_of(pid), String(FogView.vision_level(view, v, pid, t.memory_after[v])), "%s: %s's level" % [label, pid])
				for k in range(ids.size(), Vision.WIDTH):
					assert_eq(int(b.wv.vision_bytes()[k]), 255, "%s: texels past the map are clear" % label)
				checks += 1
	assert_true(checks >= 20, "the vision texture was checked over many views (%d)" % checks)
	for texel in [0, 85, 170, 255]:
		assert_true(seen_levels.has(texel), "the games showed texel %d (never seen, remembered, glimpsed, clear)" % texel)
	# the quality ladder: the clouds drift on the rungs below 3 and stand still from rung 3
	for rung in [0, 1, 2, 3, 0]:
		b.set_quality_rung(rung)
		assert_eq(float(b.wv.gmat.get_shader_parameter("fog_drift")), 1.0 if rung < WorldView.FOG_STILL_RUNG else 0.0, "rung %d: the clouds %s" % [rung, "drift" if rung < WorldView.FOG_STILL_RUNG else "stand still"])
		assert_true(b.wv.fog_on, "and the veil is on at every rung")
	_free(b)


func test_the_boards_armies_equal_the_views_and_no_hidden_army_is_instanced() -> void:
	var b: Board3D = null
	var hidden_seen := 0
	var checks := 0
	for g in Kit.games():
		for i in g.turns.size():
			if i % 3 != 2:
				continue
			var t: Dictionary = g.turns[i]
			for v in Kit.SEATS:
				var view: GameState = t.view_after[v]
				if b == null:
					b = _board(view, v, t.memory_after[v], t.intel_after[v], t.view_before[v])
				else:
					_stand(b, view, v, t.memory_after[v], t.intel_after[v], t.view_before[v])
				var label := "%s turn %d, %s" % [g.name, t.turn, v]
				var want_ids := []
				for a in view.armies:
					want_ids.append(a.id)
				want_ids.sort()
				var got_ids: Array = b.armies.armies.keys()
				got_ids.sort()
				assert_eq(got_ids, want_ids, "%s: the board's armies are the view's armies" % label)
				# the figures of every army are what the view's units and leaders draw as blocks
				var sight := FogRules.sight(t.after, v)
				for a in view.armies:
					var e: Dictionary = b.armies.armies[a.id]
					assert_eq(bool(e.get("memory", false)), String(a.seen.get("level", "")) == FogData.MEMORY, "%s: %s's memory flag" % [label, a.id])
					var expect := 0
					var counts := {}
					for u in a.units:
						counts[u.type.id] = int(counts.get(u.type.id, 0)) + 1
					for tid in counts:
						expect += Models.block_size(int(counts[tid]))
					assert_true((e["figs"] as Array).size() >= expect, "%s: %s draws a block per unit type" % [label, a.id])
				# no army the viewer can't see: nothing true is on the board at a province out of sight but memories
				for pid in sight:
					if String(sight[pid]) != "veiled":
						continue
					for a in t.after.armies:
						if a.owner == v or a.location != pid:
							continue
						hidden_seen += 1
						for id in b.armies.armies:
							var e2: Dictionary = b.armies.armies[id]
							if e2["province"] == pid:
								assert_true(bool(e2.get("memory", false)), "%s: %s out of sight shows only a memory, not %s" % [label, pid, id])
						assert_false(b.armies.armies.has(a.id), "%s: the true army %s has no instance" % [label, a.id])
						# nothing the scene holds carries a true rival id
						for node in b.armies.find_children("*", "MultiMeshInstance3D", true, false):
							if node.is_queued_for_deletion():
								continue  # headless runs no frame: a freed node (the last board's) lingers until one
							assert_false(String(node.name).begins_with(a.id.validate_node_name() + "_"), "%s: no node for the hidden %s" % [label, a.id])
				checks += 1
	assert_true(checks >= 40 and hidden_seen >= 20, "many views, with hidden armies among them (%d views, %d hidden armies)" % [checks, hidden_seen])
	_free(b)


func test_changing_anything_hidden_changes_nothing_the_board_builds() -> void:
	var b: Board3D = null
	var checks := 0
	var plates_with_estimates := 0
	var memories := 0
	for g in Kit.games():
		for i in g.turns.size():
			if i % 3 != 2 and i != g.turns.size() - 1:
				continue
			var t: Dictionary = g.turns[i]
			for v in Kit.SEATS:
				var view: GameState = t.view_after[v]
				if b == null:
					b = _board(view, v, t.memory_after[v], t.intel_after[v], t.view_before[v])
				else:
					_stand(b, view, v, t.memory_after[v], t.intel_after[v], t.view_before[v])
				var base := _model(b)
				for a in view.armies:
					plates_with_estimates += 1 if Vision.is_stand_in(a) else 0
					memories += 1 if Vision.is_memory(a) else 0
				for k in 2:
					var p := Kit.perturb_hidden(t.after, v, hash([g.seed, t.turn, v, k, "board"]))
					assert_eq(p.errors, [], "%s turn %d, %s: the perturbed state is a valid game" % [g.name, t.turn, v])
					if p.state == null:
						continue
					assert_ne(_json(p.state), _json(t.after), "the truth did change")
					var view2 := FogRules.view_state(p.state, v, t.memory_after[v], t.intel_after[v])
					_stand(b, view2, v, t.memory_after[v], t.intel_after[v], t.view_before[v])
					var d := _diff(base, _model(b))
					assert_eq(d, "", "%s turn %d, %s, perturbation %d: the board is identical (differs in: %s)" % [g.name, t.turn, v, k, d])
					checks += 1
					_stand(b, view, v, t.memory_after[v], t.intel_after[v], t.view_before[v])
	assert_true(checks >= 20 * 2 * 3, "many boards were compared (%d)" % checks)
	assert_true(plates_with_estimates > 20 and memories > 0, "with estimates (%d) and memories (%d) among them" % [plates_with_estimates, memories])
	_free(b)


# --- the playback, per viewer -----------------------------------------------------------------------

func test_the_board_model_after_a_playback_equals_apply_view_events_beats_included() -> void:
	## every kit game (20 games x 12 turns x both viewers): the viewer's events lead to the model of the view after, exactly as
	## FogRules.apply_view_events folds them, and the plan's beats agree with it
	var turns := 0
	var seen_marches := 0
	var away_marches := 0
	var sightings := 0
	var battles := 0
	for g in Kit.games():
		for t in g.turns:
			for v in Kit.SEATS:
				var vb: GameState = t.view_before[v]
				var va: GameState = t.view_after[v]
				var events: Array = t.report[v]
				var label := "%s turn %d, %s" % [g.name, t.turn, v]
				var played := Playback.apply_events(Playback.model_of(vb), events)
				var built := Playback.model_of(va)
				_expect_same_models(played, built, vb, va, v, label)
				var fold := FogRules.apply_view_events(FogRules.view_model(vb), events)
				var places := {}
				for id in fold:
					places[id] = String(fold[id].location)
				assert_eq(played["armies"], places, "%s: the board model equals apply_view_events" % label)
				var plan := Playback.plan(vb, events, va)
				for m in plan["marches"]:
					if m.has("seen"):
						seen_marches += 1
						away_marches += 1 if bool(m["to_border"]) else 0
						var stand_in := vb.find_army(String(m["alias_of"]))
						assert_true(stand_in != null and stand_in.owner == m["owner"] and stand_in.location == m["hops"][0] and not stand_in.seen.is_empty(),
							"%s: a seen march is a rival stand-in's block, from where it stood" % label)
						assert_ne(String(stand_in.seen.get("level", "")), FogData.MEMORY, "%s: a memory never marches" % label)
						var at_end := false
						for a in va.armies:
							if a.owner == m["owner"] and a.location == m["hops"][1] and String(a.seen.get("level", "")) != FogData.MEMORY:
								at_end = true
						assert_eq(bool(m["to_border"]), not at_end, "%s: a seen march walks to the border exactly when the road led out of sight" % label)
						continue
					var survives := va.find_army(String(m["army"])) != null
					assert_eq(bool(m["survived"]), survives, "%s: %s is marked as surviving exactly when the view after has it" % [label, m["army"]])
					if bool(m["survived"]):
						assert_false(plan["fallen"].has(m["army"]), "%s: no surviving march plays as fallen (%s)" % [label, m["army"]])
				for id in plan["fallen"]:
					assert_true(va.find_army(String(id)) == null, "%s: %s fell and is gone from the view after" % [label, id])
				for sg in plan["sightings"]:
					sightings += 1
					assert_eq(va.find_army(String(sg["id"])) == null, bool(sg["gone"]), "%s: %s's sighting is gone exactly when the view after has no such army" % [label, sg["id"]])
				battles += plan["battles"].size()
				turns += 1
	assert_true(turns >= 400, "many turns (%d)" % turns)
	assert_true(seen_marches >= 200 and away_marches >= 50 and sightings >= 500 and battles >= 5,
		"with seen marches (%d, %d of them out of sight), sightings (%d) and battles (%d) among them" % [seen_marches, away_marches, sightings, battles])


## Two board models (Playback.model_of) must agree. A construction site (works) is the one thing a viewer's events cannot
## carry: it is seen where the province is (FogRules §2.7), so a site may appear or vanish with the sight alone.
func _expect_same_models(played: Dictionary, built: Dictionary, vb: GameState, va: GameState, viewer: String, label: String) -> void:
	var pa := played.duplicate(true)
	var bu := built.duplicate(true)
	var sight_after := FogRules.sight(va, viewer)
	var sight_before := FogRules.sight(vb, viewer)
	for key in ["works"]:
		if not pa.has(key) or not bu.has(key):
			continue
		for pid in pa[key].keys() + bu[key].keys():
			if var_to_str(pa[key].get(pid)) == var_to_str(bu[key].get(pid)):
				continue
			assert_true(String(sight_after.get(pid, "veiled")) != "veiled" or String(sight_before.get(pid, "veiled")) != "veiled",
				"%s: a site at %s changed without the viewer seeing the province" % [label, pid])
			pa[key].erase(pid)
			bu[key].erase(pid)
	assert_eq(_model_diff(pa, bu), [], "%s: the events lead to the view after" % label)


func test_the_board_after_a_playback_equals_the_board_built_from_the_view_after() -> void:
	## 3 games (M1, M2 with rulers, M3c sieges) x 12 turns x both viewers, and every other turn in the kit with a battle or a column
	## marching out of sight: the playback of the viewer's own report ends where a board built from its view after stands
	var b: Board3D = null
	var plays := 0
	var with_seen := 0
	var with_away := 0
	var with_battle := 0
	var cases := []
	var extras := 0
	for gi in Kit.games().size():
		var g: Dictionary = Kit.games()[gi]
		for t in g.turns:
			for v in Kit.SEATS:
				var plan := Playback.plan(t.view_before[v], t.report[v], t.view_after[v])
				var interesting := false
				for m in plan["marches"]:
					interesting = interesting or bool(m.get("seen", false)) and bool(m["to_border"])
				interesting = interesting or not plan["battles"].is_empty()
				if gi in [0, 1, 3]:
					cases.append([g, t, v])
				elif interesting and extras < 40:
					extras += 1
					cases.append([g, t, v])
	for c in cases:
		var g: Dictionary = c[0]
		var t: Dictionary = c[1]
		var v: String = c[2]
		var vb: GameState = t.view_before[v]
		var va: GameState = t.view_after[v]
		var events: Array = t.report[v]
		var label := "%s turn %d, %s" % [g.name, t.turn, v]
		var before_json := _json(vb)
		var after_json := _json(va)
		var plan := Playback.plan(vb, events, va)
		if b == null:
			b = _board(vb, v, t.memory_after[v], t.intel_after[v], vb)
		var ok := _play(b, vb, events, va, v, t.memory_after[v], t.intel_after[v], [], 1.0 / 10.0)
		if ok:
			plays += 1
			for m in plan["marches"]:
				with_seen += 1 if m.has("seen") else 0
				with_away += 1 if m.has("seen") and bool(m["to_border"]) else 0
			with_battle += 1 if not plan["battles"].is_empty() else 0
			var snap: Dictionary = b.armies.snapshot()
			var vision: PackedByteArray = b.wv.vision_bytes()
			var tents: int = b.armies.tent_count()
			assert_eq(b.armies.ghost_count(), 0, "%s: no recruit ghosts after a playback" % label)
			b.stand(va)
			assert_eq(snap, b.armies.snapshot(), "%s: every army stands where a board built from the view after puts it" % label)
			assert_eq(vision, b.wv.vision_bytes(), "%s: the ground shows the view after's sight" % label)
			assert_eq(tents, b.armies.tent_count(), "%s: the war camps are the view after's" % label)
		assert_eq(_json(vb), before_json, "%s: the view before is untouched" % label)
		assert_eq(_json(va), after_json, "%s: the view after is untouched" % label)
	assert_true(plays >= 40, "many turns played out on the board (%d)" % plays)
	assert_true(with_seen >= 20 and with_away >= 5 and with_battle >= 3, "with seen marches (%d, %d out of sight) and battles (%d) among them" % [with_seen, with_away, with_battle])
	if b != null:
		_free(b)


func test_changing_anything_hidden_changes_nothing_the_playback_does() -> void:
	## the playback of a turn (the beats, the board at every few steps, its sounds, the board it ends on) is the same whatever is
	## hidden from the viewer: the perturbed turn gives the same report and the same views, and the board plays it identically
	var b: Board3D = null
	var checks := 0
	var played := 0
	for g in Kit.games():
		for i in g.turns.size():
			if i % 5 != 4:
				continue
			var t: Dictionary = g.turns[i]
			for v in Kit.SEATS:
				var vb: GameState = t.view_before[v]
				var va: GameState = t.view_after[v]
				var events: Array = t.report[v]
				var label := "%s turn %d, %s" % [g.name, t.turn, v]
				if b == null:
					b = _board(vb, v, t.memory_after[v], t.intel_after[v], vb)
				var base_log := []
				var ok := _play(b, vb, events, va, v, t.memory_after[v], t.intel_after[v], base_log, 1.0 / 10.0)
				var base_sounds := b.sounds.duplicate()
				var base_model := _model(b)
				var keep := Kit.shown_armies(t.events, v, t.before)
				var seed_value := hash([g.seed, t.turn, v, "play"])
				var pb := Kit.perturb_hidden(t.before, v, seed_value, keep)
				var pa := Kit.perturb_hidden(t.after, v, seed_value, keep)
				assert_eq(pb.errors + pa.errors, [], "%s: both perturbed states are valid" % label)
				if pb.state == null or pa.state == null:
					continue
				var rename: Dictionary = pb.rename.duplicate()
				rename.merge(pa.rename)
				var turn := FogRules.turn_for(Kit.rename_events(t.events, rename), v, pb.state, pa.state, t.memory_before[v], t.intel_before[v])
				assert_eq(JSON.stringify(turn.events), JSON.stringify(events), "%s: the perturbed turn's report is the same" % label)
				assert_eq(_json(turn.view_before), _json(vb), "%s: and its view before" % label)
				assert_eq(_json(turn.view_after), _json(va), "%s: and its view after" % label)
				var log2 := []
				var ok2 := _play(b, turn.view_before, turn.events, turn.view_after, v, turn.memory, turn.intel, log2, 1.0 / 10.0)
				assert_eq(ok2, ok, "%s: it plays when the base turn plays" % label)
				assert_eq(log2, base_log, "%s: the board is the same at every few steps of the playback" % label)
				assert_eq(b.sounds, base_sounds, "%s: the same sounds" % label)
				var d := _diff(base_model, _model(b))
				assert_eq(d, "", "%s: the board it ends on is identical (differs in: %s)" % [label, d])
				checks += 1
				played += 1 if ok else 0
	assert_true(checks >= 30 and played >= 15, "many turns were compared (%d, %d of them played)" % [checks, played])
	if b != null:
		_free(b)


func test_a_rival_column_marching_out_of_sight_walks_to_the_border_and_fades() -> void:
	var b: Board3D = null
	var away_done := 0
	var seen_done := 0
	for g in Kit.games():
		for t in g.turns:
			for v in Kit.SEATS:
				var vb: GameState = t.view_before[v]
				var va: GameState = t.view_after[v]
				var plan := Playback.plan(vb, t.report[v], va)
				var marches: Array = plan["marches"].filter(func(m): return m.has("seen"))
				if marches.is_empty() or (away_done >= 8 and seen_done >= 8):
					continue
				var wants_away: bool = marches.any(func(m): return m["to_border"])
				if wants_away and away_done >= 8:
					continue
				if not wants_away and seen_done >= 8:
					continue
				var label := "%s turn %d, %s" % [g.name, t.turn, v]
				if b == null:
					b = _board(vb, v, t.memory_after[v], t.intel_after[v], vb)
				_stand(b, va, v, t.memory_after[v], t.intel_after[v], vb)
				b.armies.snap_at_end = false
				assert_true(b.play_turn(vb, t.report[v], va), "%s: it plays" % label)
				var start := {}
				for m in marches:
					var alias := String(m["army"])
					assert_true(b.armies.armies.has(alias), "%s: the stand-in's block marches under its alias" % label)
					assert_false(b.armies.armies.has(String(m["alias_of"])), "%s: and is not standing at its place any longer" % label)
					start[alias] = _centre(b.armies.armies[alias])
				var went := {}
				var guard := 0
				while b.is_playing() and guard < 6000:
					b.armies.step_playback(1.0 / 10.0)
					guard += 1
					for alias in start:
						var key := String(alias)
						if b.armies.armies.has(key):
							went[key] = maxf(float(went.get(key, 0.0)), _centre(b.armies.armies[key]).distance_to(start[key]))
				b.armies.snap_at_end = true
				assert_false(b.is_playing())
				var terrain = b.wv.terrain
				for m in marches:
					var alias := String(m["army"])
					assert_true(float(went.get(alias, 0.0)) > 6.0, "%s: the column walks off (%.1f units)" % [label, float(went.get(alias, 0.0))])
					var fallen_key := "~fallen~" + alias
					assert_true(b.armies.armies.has(fallen_key), "%s: it fades where it stopped (the view after has no such block)" % label)
					var e: Dictionary = b.armies.armies[fallen_key]
					for f in e["figs"]:
						assert_eq(float(f["to_scale"]), 0.0, "%s: every figure of it fades away" % label)
					var from: String = m["hops"][0]
					var to: String = m["hops"][1]
					var end_at := _centre_of_to(e)
					if bool(m["to_border"]):
						var cross: Vector2 = terrain.crossing(from, to)
						assert_true(end_at.distance_to(cross) <= 30.0, "%s: it stops at the border crossing (%.1f units from it)" % [label, end_at.distance_to(cross)])
						away_done += 1
					else:
						assert_true(end_at.distance_to(terrain.centre_of(to)) < start[alias].distance_to(terrain.centre_of(to)), "%s: it walks toward %s" % [label, to])
						seen_done += 1
				# the view after's own stand-ins stand where a board built from it puts them
				var snap: Dictionary = b.armies.snapshot()
				b.stand(va)
				assert_eq(snap, b.armies.snapshot(), "%s: and the board ends as the view after" % label)
	assert_true(away_done >= 3 and seen_done >= 3, "columns marching out of sight (%d) and into sight (%d) were played" % [away_done, seen_done])
	if b != null:
		_free(b)


## The middle of an army entry's figures where they stand now.
func _centre(e: Dictionary) -> Vector2:
	var sum := Vector2.ZERO
	var n := 0
	for f in e["figs"]:
		sum += f["pos"] as Vector2
		n += 1
	return sum / float(maxi(n, 1))


## The middle of where an army entry's figures are going (its figures' to_pos).
func _centre_of_to(e: Dictionary) -> Vector2:
	var sum := Vector2.ZERO
	var n := 0
	for f in e["figs"]:
		sum += f["to_pos"] as Vector2
		n += 1
	return sum / float(maxi(n, 1))


# --- stand-ins and memory ghosts ----------------------------------------------------------------------

func test_a_glimpse_draws_blocks_from_the_shown_counts_under_an_approx_plate() -> void:
	var b: Board3D = null
	var glimpsed := 0
	var rounded := 0
	var clear_exact := 0
	for g in Kit.games():
		for i in g.turns.size():
			if i % 3 != 1:
				continue
			var t: Dictionary = g.turns[i]
			for v in Kit.SEATS:
				var view: GameState = t.view_after[v]
				if b == null:
					b = _board(view, v, t.memory_after[v], t.intel_after[v], t.view_before[v])
				else:
					_stand(b, view, v, t.memory_after[v], t.intel_after[v], t.view_before[v])
				for a in view.armies:
					if a.owner == v:
						assert_eq(b.overlay.plate_text(view, a), "Ruler" if a.ruler != null else str(a.units.size()), "your own army's plate is its exact count")
						continue
					var label := "%s turn %d, %s: %s" % [g.name, t.turn, v, a.id]
					var text: String = b.overlay.plate_text(view, a)
					var level := String(a.seen.get("level", ""))
					assert_true(Vision.is_stand_in(a), "%s is a stand-in" % label)
					# the blocks are the shown counts' blocks
					var counts := {}
					for u in a.units:
						counts[u.type.id] = int(counts.get(u.type.id, 0)) + 1
					var drawn := {}
					for f in b.armies.armies[a.id]["figs"]:
						if f["role"] == "unit":
							drawn[f["type"]] = int(drawn.get(f["type"], 0)) + 1
					for tid in counts:
						assert_eq(int(drawn.get(tid, 0)), Models.block_size(int(counts[tid])), "%s: a block of %s for %d shown" % [label, tid, int(counts[tid])])
					if a.ruler != null:
						assert_true(text.begins_with("Ruler"), "%s: a ruler's plate" % label)
						continue
					if a.units.is_empty() and a.commander != null:
						assert_eq(text, a.commander.type.name, "%s: a further commander's plate names it" % label)
						continue
					match level:
						FogRules.GLIMPSE:
							glimpsed += 1
							assert_eq(text, "≈%s" % FogView.about(a.seen.total), "%s: a glimpse's plate reads ≈ and the shown number" % label)
							assert_eq(text, FogView.badge_text(view, a), "%s: it is the 2D badge's own words" % label)
							# never the truth: where the truth differs from the shown total, the plate says the shown one
							var truth_n := 0
							for r in t.after.armies:
								if r.owner == a.owner and r.location == a.location and r.ruler == null:
									truth_n += r.units.size()
							if truth_n != int(a.seen.total.shown) and String(a.seen.total.text) != FogData.FEW_TEXT:
								rounded += 1
								assert_ne(text, "≈%d" % truth_n, "%s: the plate shows the rounded %s, not the true %d" % [label, text, truth_n])
						FogData.MEMORY:
							assert_eq(text, "≈%s · %s" % [FogView.about(a.seen.total), Vision.ago_text(view, int(a.seen.turn))], "%s: a ghost's plate reads its age" % label)
							assert_true(text.ends_with("ago") or text.ends_with("start"), "%s: ends in its age (%s)" % [label, text])
						_:
							clear_exact += 1
							assert_eq(text, str(a.units.size()), "%s: in clear sight the plate is the exact count" % label)
	assert_true(glimpsed >= 20 and rounded >= 5, "glimpsed armies (%d), %d of them rounded away from the truth" % [glimpsed, rounded])
	_free(b)


func test_memory_ghosts_have_their_own_material_and_fade_a_step_every_two_turns() -> void:
	# the ladder itself: a step every 2 turns, to the last step, fainter each time
	assert_eq(Vision.ghost_step(0), 0)
	assert_eq(Vision.ghost_step(1), 0)
	assert_eq(Vision.ghost_step(2), 1, "a step after 2 turns")
	assert_eq(Vision.ghost_step(3), 1)
	assert_eq(Vision.ghost_step(4), 2)
	assert_eq(Vision.ghost_step(999), Vision.GHOST_ALPHA.size() - 1, "the last step stays")
	for k in range(1, Vision.GHOST_ALPHA.size()):
		assert_true(Vision.ghost_alpha(k) < Vision.ghost_alpha(k - 1), "step %d is fainter than step %d" % [k, k - 1])
	assert_true(Vision.ghost_alpha(Vision.GHOST_ALPHA.size() - 1) > 0.05, "the oldest ghost can still be seen")
	# on a board: find views with memories
	var b: Board3D = null
	var found := 0
	var aged := {}
	for g in Kit.games():
		for t in g.turns:
			for v in Kit.SEATS:
				var view: GameState = t.view_after[v]
				var ghosts := view.armies.filter(func(a): return Vision.is_memory(a))
				if ghosts.is_empty() or found >= 25:
					continue
				found += 1
				var label := "%s turn %d, %s" % [g.name, t.turn, v]
				if b == null:
					b = _board(view, v, t.memory_after[v], t.intel_after[v], t.view_before[v])
				else:
					_stand(b, view, v, t.memory_after[v], t.intel_after[v], t.view_before[v])
				var mem: Dictionary = b.armies.memory_list()
				var want := []
				for a in ghosts:
					want.append(a.id)
				want.sort()
				var got: Array = mem.keys()
				got.sort()
				assert_eq(got, want, "%s: exactly the remembered armies are ghosts" % label)
				for a in ghosts:
					var e: Dictionary = b.armies.armies[a.id]
					var step := Vision.ghost_step(Vision.age_of(view, a))
					aged[step] = true
					assert_eq(int(mem[a.id]["step"]), step, "%s: %s fades by its age" % [label, a.id])
					assert_eq(e.get("banner"), null, "%s: a memory carries no banner" % label)
					for tn in e["types"]:
						for mi in e["types"][tn]["mis"]:
							var m: ShaderMaterial = (mi as MultiMeshInstance3D).material_override as ShaderMaterial
							assert_true(m != null and m.shader == Armies.SH_MEMORY, "%s: %s draws in the memory material" % [label, a.id])
							assert_eq(float(m.get_shader_parameter("alpha")), Vision.ghost_alpha(step), "%s: at its age's opacity" % label)
							assert_eq((mi as Node).get_parent(), b.armies.memory_root, "%s: under the memories, not the recruit ghosts" % label)
							assert_eq((mi as GeometryInstance3D).cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s: and casts no shadow" % label)
				# at the far zoom a memory's stand is grey and carries no banner; in the woods it stands on no tray
				b.stands.snap(true, 1.0, b.armies)
				for a in ghosts:
					assert_true(b.stands.stands.has(a.id) and bool(b.stands.stands[a.id]["memory"]), "%s: %s has a stand, marked as a memory" % [label, a.id])
					assert_eq(b.stands.stands[a.id]["colour"], Stands.MEMORY_COLOUR, "%s: a grey stand" % label)
					assert_false(b.stands._banners.has(a.id), "%s: and no banner" % label)
				for a in view.armies:
					if not Vision.is_memory(a) and b.stands.stands.has(a.id):
						assert_true(b.stands._banners.has(a.id), "%s: an army that stands there keeps its banner (%s)" % [label, a.id])
				b.stands.snap(false, 1.0, b.armies)
				b.trays.rebuild(b.armies)
				for a in ghosts:
					assert_false(b.trays.trays.has(a.id), "%s: a memory stands on no tray" % label)
				# the queued recruits' ghosts are counted apart: the same plan gives the same count with or without memories
				var cap: String = view.find_faction(v).capital
				b.armies.show_plan({"ghosts": [{"province": cap, "owner": v, "types": ["spearmen", "crossbowmen"] if v == CROWN else ["tuskers", "tuskers"]}], "owner": v})
				assert_eq(b.armies.ghost_count(), 2, "%s: two queued recruits are two ghost figures, with %d memories on the board" % [label, ghosts.size()])
	assert_true(found >= 10, "views with memories were checked (%d)" % found)
	assert_true(aged.size() >= 2, "ghosts of different ages were seen (steps %s)" % [aged.keys()])
	# an old ghost is fainter than a new one on the same board: the same view with the sighting turn moved back
	var view: GameState = null
	var meta := {}
	for g in Kit.games():
		for t in g.turns:
			for v in Kit.SEATS:
				if t.view_after[v].armies.any(func(a): return Vision.is_memory(a)) and (view == null or t.view_after[v].current_turn > view.current_turn):
					view = t.view_after[v].deep_copy()
					meta = {"viewer": v, "memory": t.memory_after[v], "intel": t.intel_after[v], "before": t.view_before[v]}
	assert_true(view != null and view.current_turn >= 8, "a late view with a memory (turn %d)" % (view.current_turn if view != null else -1))
	var ghost: Army = view.armies.filter(func(a): return Vision.is_memory(a))[0]
	var last := -1.0
	for age in [1, 3, 5, 7, 9]:
		ghost.seen["turn"] = view.current_turn + 1 - age
		_stand(b, view.deep_copy(), meta.viewer, meta.memory, meta.intel, meta.before)
		var alpha := -1.0
		for tn in b.armies.armies[ghost.id]["types"]:
			for mi in b.armies.armies[ghost.id]["types"][tn]["mis"]:
				alpha = float(((mi as MultiMeshInstance3D).material_override as ShaderMaterial).get_shader_parameter("alpha"))
		assert_true(last < 0.0 or alpha < last, "a ghost %d turns old (alpha %.2f) is fainter than the younger one (%.2f)" % [age, alpha, last])
		last = alpha
		assert_true(b.overlay.plate_text(b.map.state, b.map.state.find_army(ghost.id)).ends_with("%d turns ago" % age) or age == 1,
			"its plate says %d turns ago" % age)
	_free(b)


# --- rituals and sound ------------------------------------------------------------------------------

## A sample event, in the resolver's shape (as test_fog_report builds them).
func _event(type: String, phase: String, provinces: Array, factions: Array, armies: Array, numbers: Dictionary) -> Dictionary:
	return {"type": type, "phase": phase, "provinces": provinces, "factions": factions, "armies": armies, "cause": "test",
		"numbers": numbers, "text": "The resolver's own words.", "codex": "orders"}


## A kit turn and viewer whose plan has something to play (a march or a battle), so a board plays it.
func _playable(viewer: String = "") -> Array:
	for g in Kit.games():
		for t in g.turns:
			for v in Kit.SEATS:
				if not viewer.is_empty() and v != viewer:
					continue
				var plan := Playback.plan(t.view_before[v], t.report[v], t.view_after[v])
				if not plan["marches"].is_empty() and plan["marches"].any(func(m): return not m.has("seen")):
					return [g, t, v]
	return []


func test_a_ritual_from_a_hidden_caster_starts_at_the_target() -> void:
	var g: Dictionary = Kit.games()[0]
	var t: Dictionary = g.turns[1]
	var ritual := {"ritual": "bloodrot", "faction": CLANS, "until_turn": 6, "budget": 12, "read": false, "blocked": false}
	var fell_numbers := ritual.duplicate()
	fell_numbers["province"] = "westwatch"
	var cast_numbers := ritual.duplicate()
	cast_numbers["global"] = false
	var global_numbers := {"ritual": "blood_moon", "until_turn": 6, "global": true}
	var crown_reports := []
	for caster_at in ["fangridge", "bloodfen"]:
		# the same turn twice, the Clans casting from two different (hidden) places
		var events := [
			_event("ritual_cast", "rituals", [caster_at, "westwatch"], [CLANS], ["beasts-1"], cast_numbers),
			_event("ritual_fell", "rituals", ["westwatch"], [CROWN, CLANS], [], fell_numbers),
			_event("ritual_cast", "rituals", [caster_at], [CLANS], ["beasts-1"], global_numbers)]
		var crown := FogRules.report_for(events, CROWN, t.before, t.after, t.memory_before[CROWN], t.intel_before[CROWN])
		var plan := Playback.plan(t.view_before[CROWN], crown, t.view_after[CROWN])
		crown_reports.append(JSON.stringify([crown, plan["rituals"]]))
		assert_eq(plan["rituals"].size(), 2, "the Crown is told of the curse and the heralded moon")
		for r in plan["rituals"]:
			assert_eq(String(r["from"]), "", "a ritual from a caster the Crown can't see starts nowhere in particular: no direction (%s)" % r["kind"])
		var fell: Dictionary = plan["rituals"].filter(func(r): return r["kind"] == "ritual_fell")[0]
		assert_eq(String(fell["at"]), "westwatch", "it falls at the target")
		assert_eq(String(fell["ritual"]), "bloodrot")
		assert_false(JSON.stringify(plan["rituals"]).contains(caster_at), "and nothing of the plan names the caster's province (%s)" % caster_at)
		# the caster's own report keeps its beat at its caster
		var own := FogRules.report_for(events, CLANS, t.before, t.after, t.memory_before[CLANS], t.intel_before[CLANS])
		var own_plan := Playback.plan(t.view_before[CLANS], own, t.view_after[CLANS])
		var cast: Dictionary = own_plan["rituals"].filter(func(r): return r["kind"] == "ritual_cast" and not bool(r["global"]))[0]
		assert_eq(String(cast["from"]), caster_at, "your own cast starts at your caster")
		assert_eq(String(cast["at"]), "westwatch")
	assert_eq(crown_reports[0], crown_reports[1], "whichever hidden place it was cast from, the Crown's report and beats are the same")
	# a board: the beats fire at the start of the playback, with no direction for the hidden caster
	var pick := _playable(CROWN)
	assert_false(pick.is_empty(), "a turn with something to play")
	var pt: Dictionary = pick[1]
	var vb: GameState = pt.view_before[CROWN]
	var va: GameState = pt.view_after[CROWN]
	var events2: Array = pt.report[CROWN].duplicate(true)
	events2.append(_event("ritual_fell", "rituals", ["westwatch"], [CROWN, CLANS], [], fell_numbers))
	var b := _board(vb, CROWN, pt.memory_after[CROWN], pt.intel_after[CROWN], vb)
	assert_true(_play(b, vb, events2, va, CROWN, pt.memory_after[CROWN], pt.intel_after[CROWN]), "the turn plays with the ritual in it")
	assert_eq(b.rituals_played, [{"from": "", "at": "westwatch", "ritual": "bloodrot"}], "the ritual's beat starts at its target")
	_free(b)


func test_sound_only_for_what_the_viewer_sees() -> void:
	var pick := _playable(CROWN)
	assert_false(pick.is_empty())
	var t: Dictionary = pick[1]
	var vb: GameState = t.view_before[CROWN]
	var va: GameState = t.view_after[CROWN]
	var sight0 := FogRules.sight(vb, CROWN)
	var sight1 := FogRules.sight(va, CROWN)
	var hidden := ""
	var visible := ""
	for p in vb.provinces:
		var both_veiled: bool = sight0[p.id] == "veiled" and sight1[p.id] == "veiled"
		if both_veiled and hidden.is_empty():
			hidden = p.id
		if sight0[p.id] != "veiled" and visible.is_empty() and p.owner != CROWN:
			visible = p.id
	assert_true(not hidden.is_empty() and not visible.is_empty(), "a province out of sight (%s) and one in it (%s)" % [hidden, visible])
	var captured := func(pid: String) -> Dictionary:
		var e := _event("captured", "capture", [pid], [CLANS, CROWN], [], {"income": 6, "is_capital": false})
		e["rebuilt"] = true
		return e
	var b := _board(vb, CROWN, t.memory_after[CROWN], t.intel_after[CROWN], vb)
	# the same turn as the game played it: its marches are heard
	_play(b, vb, t.report[CROWN], va, CROWN, t.memory_after[CROWN], t.intel_after[CROWN])
	assert_true(b.sounds.has("march"), "your own columns are heard marching: %s" % [b.sounds])
	var base_sounds := b.sounds.duplicate()
	# plus a capture the Crown was only told of, out of its sight: no fanfare
	var far: Array = t.report[CROWN].duplicate(true)
	far.append(captured.call(hidden))
	_play(b, vb, far, va, CROWN, t.memory_after[CROWN], t.intel_after[CROWN])
	assert_eq(b.sounds, base_sounds, "a capture out of sight (%s) makes no sound" % hidden)
	# the same capture in sight is heard
	var near: Array = t.report[CROWN].duplicate(true)
	near.append(captured.call(visible))
	_play(b, vb, near, va, CROWN, t.memory_after[CROWN], t.intel_after[CROWN])
	assert_eq(b.sounds.count("capital_captured"), base_sounds.count("capital_captured") + 1, "a capture in sight (%s) is heard: %s" % [visible, b.sounds])
	# the gate itself
	assert_false(b.sound_seen(hidden))
	assert_true(b.sound_seen(visible))
	assert_true(b.sound_seen(""), "a beat with no place is the viewer's own")
	_free(b)
	# without fog everything is heard
	var plain := GameState.new(21)
	var b2 := _board_plain(plain)
	for p in plain.provinces:
		assert_true(b2.sound_seen(p.id), "without fog %s is heard" % p.id)
	_free(b2)


## A board for a plain game (no fog).
func _board_plain(state: GameState) -> Board3D:
	var map := load("res://ui/map_screen.tscn").instantiate() as MapScreen
	map.set_state(state, state.factions[0].id)
	var b := Board3D.new()
	map.set_board(b)
	b.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	b.size = BOARD_SIZE
	b.build_now()
	return b


# --- words: the legend, the plates, the tooltips ------------------------------------------------------

static func _flat(text: String) -> String:
	return " ".join(text.replace("\n", " ").split(" ", false))


func test_the_legend_plates_and_tooltips_name_the_levels_and_the_age_of_a_ghost() -> void:
	var b: Board3D = null
	var levels_seen := {}
	var tips_checked := 0
	for g in Kit.games():
		for t in g.turns:
			if t.turn < 6:
				continue
			for v in Kit.SEATS:
				var view: GameState = t.view_after[v]
				if b == null:
					b = _board(view, v, t.memory_after[v], t.intel_after[v], t.view_before[v])
				else:
					_stand(b, view, v, t.memory_after[v], t.intel_after[v], t.view_before[v])
				var label := "%s turn %d, %s" % [g.name, t.turn, v]
				var legend := _flat(b.overlay.legend_text())
				for words in ["Fog of war", "In clear sight", "Glimpsed", "Out of sight", "Never seen", "≈20", "3 turns ago", "a step every 2 turns", "marching out of your sight", "from a caster you can't see"]:
					assert_true(legend.contains(words), "%s: the legend says \"%s\"" % [label, words])
				for pid in b.vision_levels:
					var level: String = b.vision_levels[pid]
					levels_seen[level] = true
					var pl: Dictionary = b.overlay._plates[pid]
					var sight: Label = pl.get("sight")
					if level == "clear":
						assert_true(sight == null or not sight.visible, "%s: %s in clear sight has no line under its plate" % [label, pid])
						continue
					assert_true(sight != null and sight.visible, "%s: %s has a line under its plate" % [label, pid])
					var seen_turn := int(t.memory_after[v].provinces.get(pid, {}).get("seen_turn", -1))
					assert_eq(sight.text, Vision.tag_for(view, level, seen_turn), "%s: %s's line" % [label, pid])
					match level:
						"glimpse":
							assert_eq(sight.text, "glimpsed")
						"veiled":
							assert_true(sight.text.begins_with("out of sight\nseen ") and (sight.text.ends_with("ago") or sight.text.ends_with("start")), "%s: %s (%s)" % [label, pid, sight.text])
						"never":
							assert_eq(sight.text, "never seen")
					assert_false(String(sight.tooltip_text).is_empty(), "%s: the line explains itself" % label)
					assert_true(_flat(sight.tooltip_text).contains(Vision.words(level).substr(0, 24)), "%s: and names the level" % label)
					assert_true(_flat(b.overlay.province_tooltip(pid)).contains(_flat(Vision.words(level))), "%s: %s's tooltip says how the ground shows it" % [label, pid])
					tips_checked += 1
				for a in view.armies:
					if a.owner == v:
						continue
					var tip := _flat(b.overlay.army_tooltip(a.id))
					match String(a.seen.get("level", "")):
						"glimpse":
							assert_true(tip.contains("drawn from the estimate on the plate"), "%s: %s's tooltip says its blocks are an estimate" % [label, a.id])
							assert_true(tip.contains("glimpse"), "%s: and that it is glimpsed" % label)
						"memory":
							assert_true(tip.contains("grey ghost") and tip.contains("ago") and tip.contains("a step every 2 turns"), "%s: %s's tooltip says how old the ghost is: %s" % [label, a.id, tip])
	assert_true(tips_checked >= 100, "many tooltips were checked (%d)" % tips_checked)
	for level in ["clear", "glimpse", "veiled", "never"]:
		assert_true(levels_seen.has(level), "the games showed %s" % level)
	_free(b)


# --- fog off ------------------------------------------------------------------------------------------

func test_with_fog_off_the_board_is_unchanged() -> void:
	var game := _game({"players": [CROWN, CLANS], "seed": 4242})
	game.use_board("3d")
	var b: Board3D = game.map.board
	b.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	b.size = BOARD_SIZE
	b.build_now()
	assert_false(b.wv.fog_on, "no veil")
	assert_eq(float(b.wv.gmat.get_shader_parameter("fog_on")), 0.0, "the ground shader's fog switch is off")
	assert_eq(b.wv.vision_bytes(), Vision.texels({}, []), "the vision texture is clear everywhere")
	assert_eq(b.vision_levels, {})
	assert_eq(b.armies.memory_list(), {})
	assert_eq(b.armies.stand_in_list(), {})
	assert_false(_flat(b.overlay.legend_text()).contains("Fog of war"), "the legend has no fog section")
	var st: GameState = game.map.state
	assert_eq(b.overlay.legend_text(), b.overlay.LEGEND % [Models.block_rule_text(), ""], "and is exactly the legend it was")
	for a in st.armies:
		assert_eq(b.overlay.plate_text(st, a), "Ruler" if a.ruler != null else str(a.units.size()), "%s's plate is its exact count" % a.id)
		assert_eq(b.overlay.army_tooltip(a.id).contains("the plate has the exact number"), a.ruler == null, "%s's tooltip is the old one" % a.id)
	for pid in b.overlay._plates:
		var l: Label = b.overlay._plates[pid].get("sight")
		assert_true(l == null or not l.visible, "%s has no sight line" % pid)
	# a fog game's observer (the truth, as watch mode and the victory screen read it) is a plain board too
	var fog_state := GameState.new(21)
	fog_state.setup_fog([])
	var b2 := _board_plain(fog_state)
	assert_false(b2.wv.fog_on, "the observer's truth is not a fog view: no veil")
	_free(b2)
	game.free()


# --- the handoff --------------------------------------------------------------------------------------

func test_the_first_frame_after_a_handoff_is_the_next_seats() -> void:
	var game := _game({"players": [CROWN, CLANS], "seed": 4242, "fog": true})
	game.use_board("3d")
	var b: Board3D = game.map.board
	b.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	b.size = BOARD_SIZE
	b.build_now()
	assert_eq(game.map.state.view_of, CROWN)
	assert_true(b.wv.fog_on, "seat 1's board is veiled")
	b.focus_on(game.map.state.find_faction(CROWN).capital, true)
	var levels1: Dictionary = b.vision_levels.duplicate()
	var bytes1: PackedByteArray = b.wv.vision_bytes()
	# seat 1 plans: a recruit queued at its capital stands as a ghost in its yard; it ends its turn
	var f1 := game.map.state.find_faction(CROWN)
	var recruit_type: String = String(f1.unit_types[0].id)
	assert_eq(game.map.queue_recruit(recruit_type), "", "seat 1 queues a recruit")
	b.sync()
	assert_true(b.armies.ghost_count() > 0, "it stands as a ghost in seat 1's yard")
	game.end_turn()
	assert_true(game.handoff.visible, "the cover is up")
	game.handoff.ready_button.pressed.emit()
	var entry: Dictionary = game.handoff_log.back()
	assert_eq(String(entry.faction), CLANS)
	assert_true(bool(entry.covered) and bool(entry.frame_cleared), "rebuilt under the cover, the kept frame cleared")
	for vp in b.find_children("*", "SubViewport", true, false):
		assert_eq((vp as SubViewport).render_target_clear_mode, SubViewport.CLEAR_MODE_ONCE, "the board's viewport clears")
		assert_eq((vp as SubViewport).render_target_update_mode, SubViewport.UPDATE_ONCE, "and draws once more before the cover lifts")
	# the board now is seat 2's: its sight, its armies; nothing of seat 1's plan or sight
	assert_eq(game.map.state.view_of, CLANS)
	var capital2: String = game.map.state.find_faction(CLANS).capital
	var want_at: Vector3 = b.rig_for(b.wv.terrain.centre_of(capital2) + Vector2(0, 6), b.zoom)["target"]
	assert_true(Vector3(b.wv.rig["target"]).distance_to(want_at) < 0.01 and Vector3(b.goal["target"]).distance_to(want_at) < 0.01,
		"the camera starts on seat 2's own capital, not where seat 1 was looking")
	assert_true(b._flash.is_empty() and b.closeup.is_empty(), "no flash or close-up of seat 1's is left")
	assert_eq(b.armies.ghost_count(), 0, "no ghost recruit of seat 1's is left in the yard")
	assert_eq(b.armies.gathered, {}, "no column gathered at a gate")
	assert_ne(b.vision_levels, levels1, "the ground shows seat 2's sight, not seat 1's")
	assert_ne(b.wv.vision_bytes(), bytes1)
	var view2: GameState = game.session.state_for(CLANS)
	var fresh := _board(view2, CLANS, game.session.memory(CLANS), game.session.intel(CLANS), game.session.view_before(CLANS))
	for key in ["vision", "levels", "full", "snapshot", "memory", "stand_ins", "ghosts", "camps", "tags", "legend", "stands", "figures", "fog_on", "owners"]:
		assert_eq(var_to_str(_model(b)[key]), var_to_str(_model(fresh)[key]), "%s: the handoff's board is a board built fresh for seat 2" % key)
	_free(fresh)
	game.free()


# --- cost ---------------------------------------------------------------------------------------------

func test_the_vision_texture_costs_almost_nothing() -> void:
	# The ground's veil is one texture fetch and one mix in the shader (measured windowed: the PR and world3d/README.md). What a
	# turn pays on the CPU is working out the 14 provinces' levels and writing 16 bytes.
	var g: Dictionary = Kit.games()[3]
	var t: Dictionary = g.turns.back()
	var view: GameState = t.view_after[CROWN]
	var b := _board(view, CROWN, t.memory_after[CROWN], t.intel_after[CROWN], t.view_before[CROWN])
	var levels: Dictionary = b.vision_levels.duplicate()
	assert_eq(levels.size(), view.provinces.size(), "every province has a level")
	var write_ms := best_ms(func():
		for i in 100:
			b.wv.set_vision(levels)) / 100.0
	var levels_ms := best_ms(func():
		for i in 100:
			Vision.levels(view, CROWN, t.memory_after[CROWN])) / 100.0
	var stand_ms := best_ms(func(): b.stand(view), 3)
	assert_eq(b.wv.vision_bytes(), Vision.texels(levels, b.wv.terrain.ids), "what was written is what was worked out")
	assert_perf(write_ms <= 0.05, "writing the vision texture took %.3f ms (budget 0.05 ms)" % write_ms)
	assert_perf(levels_ms <= 0.3, "working out the levels took %.3f ms (budget 0.3 ms)" % levels_ms)
	assert_perf(stand_ms <= 100.0, "standing a whole fog view (armies, plates, sight) took %.1f ms (budget 100 ms)" % stand_ms)
	_notes.append("vision texture: write %.3f ms, levels %.3f ms, a whole fog stand %.1f ms" % [write_ms, levels_ms, stand_ms])
	_free(b)
