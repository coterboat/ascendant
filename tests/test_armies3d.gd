extends "res://tests/test_case.gd"
## M3a.2, the armies on the 3D board (world3d/armies.gd, muster.gd, choreo.gd, board3d.gd): pose swaps,
## muster yards and war camps, ghosts and gather cues (only ever the viewing player's), the fortress
## close-up, the playback's phases, captions, beats and sounds, and "Watch this turn again".
## Headless: nothing renders, but every layout, beat and pose is computed exactly as the windowed game
## computes it. Expected values come from the data, the states and the model table, never hardcoded.

const GAME_SCENE := "res://ui/game_screen.tscn"
const Playback := preload("res://world3d/playback.gd")
const Models := preload("res://world3d/models.gd")
const Muster := preload("res://world3d/muster.gd")
const Choreo := preload("res://world3d/choreo.gd")
const BOARD_SIZE := Vector2(1200, 836)


# --- fixtures -------------------------------------------------------------------------------------

func _game(config: Dictionary) -> GameScreen:
	var game := load(GAME_SCENE).instantiate() as GameScreen
	game.autosave_enabled = false
	game.start_game(config)
	return game


func _game_with_board(config: Dictionary = {"players": ["kingdom", "beasts"], "seed": 4242}) -> GameScreen:
	var game := _game(config)
	game.use_board("3d")
	var b: Board3D = game.map.board
	b.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	b.size = BOARD_SIZE
	b.build_now()
	return game


func _board_for(state: GameState) -> Board3D:
	var map := load("res://ui/map_screen.tscn").instantiate() as MapScreen
	map.set_state(state, state.factions[0].id)
	var b := Board3D.new()
	map.set_board(b)
	b.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	b.size = BOARD_SIZE
	b.build_now()
	return b


func _free_board(b: Board3D) -> void:
	var map: Node = b.map
	if map != null:
		map.free()
	elif is_instance_valid(b):
		b.free()


## `turns` turns of a game the real AI plays for both sides, through the real resolver.
func _autoplay(game_seed: int, turns: int, rulers: bool) -> Array:
	var out: Array = []
	var st: GameState = GameState.with_rulers(game_seed, {}, []) if rulers else GameState.new(game_seed)
	for t in turns:
		var orders := {}
		var seat := 0
		for f in st.factions:
			var rng := SeededRNG.new(game_seed * 7919 + (seat + 1) * 104729 + t * 31)
			orders[f.id] = AIPlayer.new().plan_orders(st, f.id, rng, "normal")
			seat += 1
		var res: Dictionary = TurnResolver.resolve(st, orders, TurnResolver.seed_for_turn(st))
		if res.get("new_state") == null:
			break
		out.append({"before": st, "events": res["events"], "after": res["new_state"]})
		st = res["new_state"]
		var over := false
		for f in st.factions:
			var cap := st.find_province(f.capital)
			if cap == null or cap.owner != f.id:
				over = true
		if over:
			break
	return out


func _has_battle(turn: Dictionary) -> bool:
	for e in turn["events"]:
		if String(e.get("type", "")) in Playback.BATTLES:
			return true
	return false


## Plays a turn on the board to its end in fixed steps; returns how many steps it took.
func _play_out(b: Board3D, step: float = 1.0 / 30.0) -> int:
	var guard := 0
	while b.is_playing() and guard < 6000:
		b.armies.step_playback(step)
		guard += 1
	return guard


func _desc(id: String, owner: String, blocks: Array, leaders: Array = []) -> Dictionary:
	var bl: Array = []
	for b in blocks:
		bl.append({"type": b[0], "n": b[1], "rank": Models.rank_of(b[0]), "sp": Vector2(4.2, 4.4)})
	var ld: Array = []
	for l in leaders:
		ld.append({"type": l, "role": "commander", "rank": 2, "sp": Vector2(6.0, 6.0)})
	return {"id": id, "owner": owner, "location": "x", "blocks": bl, "leaders": ld}


# --- poses ----------------------------------------------------------------------------------------

func test_every_beat_shows_its_pose_with_procedural_motion() -> void:
	for beat in Choreo.BEAT_POSES.keys():
		assert_true(Models.POSES.has(Choreo.pose_for(beat)), "%s shows one of the model table's poses" % beat)
	assert_eq(Choreo.pose_for("stand"), "ready", "standing in the yard: ready")
	assert_eq(Choreo.pose_for("march"), "march", "marching the roads: march")
	assert_eq(Choreo.pose_for("strike"), "strike", "a clash's blow: strike")
	assert_eq(Choreo.pose_for("fallen"), "fallen", "the dead: fallen")
	assert_eq(Choreo.pose_for("something new"), "ready", "an unknown beat stands ready")
	## motion over the pose
	var hops := 0
	for i in 12:
		var m := Choreo.motion("march", i * 0.07, 0.3)
		assert_eq(m["pose"], "march")
		if float(m["hop"]) > 0.05:
			hops += 1
		assert_true(absf(float(m["tilt"])) <= Choreo.SWAY + 0.0001, "a march sways a little")
	assert_true(hops > 6, "a march hops")
	var s0 := Choreo.motion("strike", 0.0)
	var s1 := Choreo.motion("strike", Choreo.LUNGE_TIME * 0.5)
	var s2 := Choreo.motion("strike", Choreo.LUNGE_TIME + Choreo.STRIKE_HOLD + 0.1)
	assert_eq(s0["pose"], "strike", "the strike pose shows at the impact")
	assert_true(float(s1["lunge"]) > float(s0["lunge"]) and is_equal_approx(float(s1["lunge"]), Choreo.LUNGE), "a strike lunges a quarter of the gap at its height")
	assert_eq(s2["pose"], "ready", "then the figure stands ready again")
	assert_true(float(Choreo.motion("recoil", Choreo.RECOIL * 0.5)["back"]) > 0.0, "a struck figure recoils")
	var t0 := Choreo.motion("topple", 0.0)
	var t1 := Choreo.motion("topple", Choreo.TOPPLE + 0.01)
	assert_eq(t0["fall"], 0.0, "a topple starts standing")
	assert_eq(t1["fall"], 1.0, "and ends lying")
	assert_eq(t0["pose"], "ready")
	assert_eq(t1["pose"], "fallen", "then the fallen pose takes over")
	## deterministic: the same arguments always give the same motion (no dice)
	assert_eq(Choreo.motion("march", 1.234, Choreo.hash_phase("a", 3)), Choreo.motion("march", 1.234, Choreo.hash_phase("a", 3)))


func test_pose_models_come_from_the_table_and_fall_back_to_the_ready_model() -> void:
	var keep: Dictionary = Models.table().duplicate(true)
	var probe := "res://assets/models/probe/spearman.glb"
	var other := "res://assets/models/probe/tusker.glb"
	var table := keep.duplicate(true)
	table["figures"]["spearmen"] = {"faction": "kingdom", "model": probe, "height": 1.3, "yaw": 180, "fallback": "spearmen", "rank": 0,
		"poses": {"ready": probe, "march": {"model": other}, "fallen": other},
		"pose_size": {"fallen": {"axis": "length", "men": 1.0}}}
	Models.clear_cache()
	Models._table = table
	var ready: Dictionary = Models.figure_mesh("spearmen", true, "ready")
	var march: Dictionary = Models.figure_mesh("spearmen", true, "march")
	var strike: Dictionary = Models.figure_mesh("spearmen", true, "strike")
	var fallen: Dictionary = Models.figure_mesh("spearmen", true, "fallen")
	assert_eq(ready["source"], "model", "the ready pose draws its model")
	assert_eq(march["pose"], "march", "a pose with a model of its own draws it (a {\"model\": path} entry)")
	assert_true(march["mesh"] != ready["mesh"], "with its own mesh")
	assert_true(strike["mesh"] == ready["mesh"], "a pose with no model shares the ready mesh (one MultiMesh)")
	assert_true(Models.has_pose_model("spearmen", "fallen") and not Models.has_pose_model("spearmen", "strike"))
	## the fallen pose is sized along its length (a figure lying down), the others by height
	var fa: AABB = (fallen["mesh"] as Mesh).get_aabb()
	assert_true(maxf(fa.size.x, fa.size.z) > 5.0 and maxf(fa.size.x, fa.size.z) < 9.5, "the fallen pose is about a man long (%.2f)" % maxf(fa.size.x, fa.size.z))
	assert_eq(Models.pose_size(table["figures"]["spearmen"], "march"), {"axis": "height", "men": 1.3}, "no pose_size: the row's height")
	assert_eq(Models.problems(), [], "the pose rows are sound")
	## the armies draw one MultiMesh per distinct pose mesh and compact each pose's figures
	var st := GameState.new(4242)
	var b := _board_for(st)
	var aid := ""
	for a in st.armies:
		for u in a.units:
			if u.type.id == "spearmen":
				aid = a.id
	assert_ne(aid, "", "a starting army has spearmen")
	var e: Dictionary = b.armies.armies[aid]
	var te: Dictionary = e["types"]["spearmen"]
	assert_eq((te["mis"] as Array).size(), 3, "ready, march and fallen meshes: three MultiMeshes (strike shares ready's)")
	assert_eq(te["groups"]["strike"], te["groups"]["ready"])
	var n := 0
	for f in e["figs"]:
		if f["type"] == "spearmen":
			n += 1
	var first: Dictionary = {}
	for f in e["figs"]:
		if f["type"] == "spearmen":
			first = f
			break
	first["pose"] = "march"
	b.armies._sync(e)
	var mis: Array = te["mis"]
	assert_eq((mis[te["groups"]["march"]] as MultiMeshInstance3D).multimesh.visible_instance_count, 1, "the marching figure draws in the march MultiMesh")
	assert_eq((mis[te["groups"]["ready"]] as MultiMeshInstance3D).multimesh.visible_instance_count, n - 1, "the rest in the ready one")
	assert_false((mis[te["groups"]["fallen"]] as MultiMeshInstance3D).visible, "an empty pose draws nothing")
	_free_board(b)
	Models.clear_cache()
	Models._table = keep
	## no poses at all: every pose is the one model or primitive of today
	for pose in Models.POSES:
		assert_true(Models.figure_mesh("crossbowmen", false, pose)["mesh"] == Models.figure_mesh("crossbowmen", false, "ready")["mesh"],
			"primitives: %s is the ready primitive" % pose)


# --- muster yards and war camps --------------------------------------------------------------------

func test_the_muster_layout_is_deterministic_fits_the_yard_and_overflows_to_the_camp() -> void:
	var g := Muster.grid(42.0, 16.0)
	assert_eq(g.x * g.y, Muster.YARD_SLOTS, "a capital's courtyard holds %d blocks" % Muster.YARD_SLOTS)
	var gs := Muster.grid_size(g)
	assert_true(gs.x <= 42.0 and gs.y <= 16.0, "the slot grid fits the courtyard")
	assert_eq(Muster.grid(200.0, 200.0).x * Muster.grid(200.0, 200.0).y, Muster.YARD_SLOTS, "never more than a capital's slots")
	assert_eq(Muster.grid(5.0, 5.0), Vector2i(1, 1), "always at least one slot")
	var descs: Array = [
		_desc("a1", "kingdom", [["spearmen", 8], ["crossbowmen", 3]], ["knight_captain"]),
		_desc("a2", "kingdom", [["knights", 4]]),
		_desc("a3", "kingdom", [["spearmen", 2], ["crossbowmen", 2], ["knights", 2]]),
	]
	var m := Muster.layout(descs, g, "kingdom")
	var shuffled: Array = [descs[2], descs[0], descs[1]]
	assert_eq(Muster.layout(shuffled, g, "kingdom"), m, "the same armies always stand in the same slots, whatever order they come in")
	var need := 0
	for d in descs:
		need += Muster.army_slots(d).size()
	assert_true(need > g.x * g.y, "this muster needs more slots than the yard has (%d)" % need)
	assert_false((m["camp"] as Dictionary).is_empty(), "so an army musters in the war camp")
	assert_eq((m["tents"] as Array).size(), m["camp_used"], "a tent behind every camp block")
	assert_eq((m["fires"] as Array).size(), (m["camp"] as Dictionary).size(), "a fire for every army in the camp")
	var used := 0
	for u in m["used"]:
		used += 1 if u else 0
	assert_true(used <= g.x * g.y)
	## every yard figure stands inside the grid, never closer to another than the drill allows
	var pts: Array = []
	for aid in m["yard"].keys():
		assert_eq((m["yard"][aid] as Array).size(), Muster.figures_at(Muster.army_slots(_find(descs, aid)), _zeros(Muster.army_slots(_find(descs, aid)).size())).size(),
			"%s stands every figure" % aid)
		for f in m["yard"][aid]:
			var p: Vector2 = f["pos"]
			assert_true(absf(p.x) <= gs.x * 0.5 + 0.01 and p.y >= -0.01 and p.y <= gs.y + 0.01, "%s's %s stands in the yard (%s)" % [aid, f["type"], p])
			pts.append(p)
	for i in pts.size():
		for j in range(i + 1, pts.size()):
			assert_true((pts[i] as Vector2).distance_to(pts[j]) >= Muster.DRILL.x - 0.15, "no two figures stand on each other")
	## an enemy army never takes the yard
	var m2 := Muster.layout([_desc("b1", "beasts", [["tuskers", 2]])], g, "kingdom")
	assert_true((m2["camp"] as Dictionary).has("b1") and (m2["yard"] as Dictionary).is_empty(), "only the owner's armies muster in its yard")


func _find(descs: Array, id: String) -> Dictionary:
	for d in descs:
		if d["id"] == id:
			return d
	return {}


func _zeros(n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append(Vector2.ZERO)
	return out


func test_ghosts_take_the_slot_each_recruit_will_muster_in() -> void:
	var g := Muster.grid(42.0, 16.0)
	var descs: Array = [_desc("a1", "kingdom", [["spearmen", 3]], ["knight_captain"])]
	var m := Muster.layout(descs, g, "kingdom")
	var gp := Muster.ghost_places(m, descs, [{"army": "a1", "type": "spearmen", "n": 2, "sp": Vector2(4.2, 4.4)},
		{"army": "a1", "type": "crossbowmen", "n": 1, "sp": Vector2(4.2, 4.4)}])
	assert_eq(gp.size(), 3, "every queued recruit stands as a ghost")
	var slot_of_spears: int = m["slots"]["a1"][1]
	assert_eq(gp[0]["pos"], Muster.place_in_slot(Muster.slot_centre(g, slot_of_spears), Vector2(4.2, 4.4), 3), "a spearman joins its block at the next place")
	assert_eq(gp[1]["pos"], Muster.place_in_slot(Muster.slot_centre(g, slot_of_spears), Vector2(4.2, 4.4), 4))
	var free_slot: int = (m["used"] as Array).find(false)
	assert_eq(gp[2]["pos"], Muster.place_in_slot(Muster.slot_centre(g, free_slot), Vector2(4.2, 4.4), 0), "a new type opens the next free slot")
	## the real figures don't move when a ghost joins them (the slot fills from the middle out)
	var before: Array = m["yard"]["a1"]
	var after: Array = Muster.layout(descs, g, "kingdom")["yard"]["a1"]
	assert_eq(before, after)
	## a full yard sends new blocks to the camp
	var full: Array = []
	for i in Muster.YARD_SLOTS:
		full.append(_desc("f%d" % i, "kingdom", []))
	var mf := Muster.layout(full, g, "kingdom")
	var gf := Muster.ghost_places(mf, full, [{"army": "", "type": "knights", "n": 1, "sp": Vector2(5.2, 7.0)}])
	assert_eq(gf[0]["where"], "camp", "with the yard full, a new block of recruits musters in the camp")


func test_the_board_musters_a_capital_and_camps_the_overflow() -> void:
	var st := GameState.with_rulers(11, {}, [])
	var f: Faction = st.factions[0]
	## three more armies at the capital: more than its yard holds
	for i in 3:
		var a := Army.new()
		a.id = "%s-extra%d" % [f.id, i]
		a.owner = f.id
		a.location = f.capital
		for k in 3:
			a.units.append(Unit.new(f.unit_types[k % f.unit_types.size()], f.id))
		st.armies.append(a)
	var b := _board_for(st)
	var lay: Dictionary = b.armies.layout_of(st)
	var m: Dictionary = lay["musters"][f.capital]
	assert_false((m["camp"] as Dictionary).is_empty(), "the yard overflows into the war camp")
	assert_true(b.armies.tent_count() > 0, "the camp's tents stand")
	assert_eq(b.armies.tent_count(), m["camp_used"])
	## yard figures stand inside the fortress's courtyard (its own frame), camp figures outside the walls
	var fort: Dictionary = b.wv.fortresses[f.capital]
	var root_xf: Transform3D = fort["node"].transform
	var court: Rect2 = fort["court"]
	for aid in m["yard"].keys():
		for fg in b.armies.armies[aid]["figs"]:
			var p: Vector2 = fg["pos"]
			var local: Vector3 = root_xf.affine_inverse() * Vector3(p.x, 0, p.y)
			assert_true(court.grow(0.6).has_point(Vector2(local.x, local.z)), "%s stands in the courtyard" % aid)
	var c: Vector2 = b.wv.terrain.centre_of(f.capital)
	for aid in m["camp"].keys():
		for fg in b.armies.armies[aid]["figs"]:
			assert_true((fg["pos"] as Vector2).distance_to(c) > 30.0, "%s stands outside the walls" % aid)
	assert_true(b.overlay.standing_note(m["camp"].keys()[0]).contains("war camp"), "its tooltip says why it stands in the camp")
	_free_board(b)


# --- planning: ghosts and gather cues, the viewer's own only ----------------------------------------

func test_own_march_orders_gather_at_the_gate_and_recruits_stand_in_their_slots() -> void:
	var game := _game_with_board({"players": ["kingdom", "beasts"], "seed": 4242, "ai": {"beasts": "normal"}})
	var b: Board3D = game.map.board
	var st: GameState = game.map.state
	var me := game.map.viewing_faction_id
	var f := st.find_faction(me)
	var army: Army = null
	for a in st.armies:
		if a.owner == me and a.location == f.capital:
			army = a
	var yard_before: Array = (b.armies.armies[army.id]["figs"] as Array).map(func(x): return x["pos"])
	var to: String = st.find_province(army.location).neighbors[0]
	assert_eq(game.map.queue_move(army.id, to), "", "the move is ordered")
	assert_eq(b.armies.gathered.get(army.id, ""), to, "the army gathers at its gate")
	var gate: Array = b.wv.gate_points(f.capital)
	var near := 0
	for fg in b.armies.armies[army.id]["figs"]:
		if (fg["pos"] as Vector2).distance_to(gate[1]) < 40.0:
			near += 1
	assert_eq(near, (b.armies.armies[army.id]["figs"] as Array).size(), "every figure stands in the column by the gate")
	assert_true(b.overlay.army_tooltip(army.id).contains("Ordered to march"), "its tooltip says why it stands there")
	assert_true(b.overlay.get_node_or_null("ArmyPlate_%s/MarchMark" % army.id.validate_node_name()) != null or _plate_has_mark(b, army.id), "its plate carries the march mark")
	game.map.select_province(f.capital)
	var types: Array = game.map.orders.recruitable_types()
	assert_eq(game.map.queue_recruit(types[0].id), "")
	assert_eq(b.armies.ghost_count(), 1, "a queued recruit stands as one ghost")
	game.map.cancel_order(0)
	assert_false(b.armies.gathered.has(army.id), "cancelling the move brings the army back")
	var yard_after: Array = (b.armies.armies[army.id]["figs"] as Array).map(func(x): return x["pos"])
	assert_eq(yard_after, yard_before, "to exactly where it stood in the yard")
	assert_eq(b.armies.ghost_count(), 1, "the recruit is still queued")
	game.free()


func _plate_has_mark(b: Board3D, aid: String) -> bool:
	for c in b.overlay.get_children():
		if String(c.name).begins_with("ArmyPlate_%s" % aid.validate_node_name()):
			return c.find_child("MarchMark", true, false) != null
	return false


func test_hotseat_seat_two_sees_nothing_of_seat_ones_plan() -> void:
	var snaps: Array = []
	for queue in [true, false]:
		var game := _game_with_board({"players": ["kingdom", "beasts"], "seed": 4242})
		var b: Board3D = game.map.board
		var st: GameState = game.map.state
		var me := game.map.viewing_faction_id
		if queue:
			var f := st.find_faction(me)
			for a in st.armies:
				if a.owner == me and a.ruler == null:
					game.map.queue_move(a.id, st.find_province(a.location).neighbors[0])
			game.map.select_province(f.capital)
			for ut in game.map.orders.recruitable_types():
				game.map.queue_recruit(ut.id)
			assert_true(b.armies.ghost_count() > 0 and not b.armies.gathered.is_empty(), "seat 1 sees its own plan")
		game.end_turn()
		assert_true(game.handoff.visible, "the handoff covers the board")
		game.handoff._on_ready_pressed()
		assert_ne(game.map.viewing_faction_id, me, "seat 2 is at the controls")
		assert_eq(b.armies.ghost_count(), 0, "seat 2 sees no ghosts of seat 1's recruits")
		assert_true(b.armies.gathered.is_empty(), "nor seat 1's gathered columns")
		assert_true(b.plan_of_orders().is_empty(), "the board's plan is seat 2's own (empty)")
		snaps.append({"board": b.armies.full_snapshot(), "owners": b.wv.owners_painted(), "plates": _ghost_plates(b)})
		game.free()
	assert_eq(snaps[0], snaps[1], "seat 2's board is identical whatever seat 1 queued")


func _ghost_plates(b: Board3D) -> int:
	var n := 0
	for c in b.overlay.get_children():
		if String(c.name).begins_with("GhostPlate") and (c as Control).visible:
			n += 1
	return n


# --- the fortress close-up -----------------------------------------------------------------------

func test_the_fortress_close_up_enters_and_leaves_cleanly() -> void:
	var game := _game_with_board()
	var b: Board3D = game.map.board
	var st: GameState = game.map.state
	var dict_before: Dictionary = st.to_dict()
	var f := st.find_faction(game.map.viewing_faction_id)
	b.zoom = 0.3
	b.goal = b.rig_for(b.wv.terrain.centre_of("thornvale"), 0.3)
	b._snap_rig()
	var before_goal: Dictionary = b.goal.duplicate()
	game.map.select_province(f.capital)
	var button := game.map.details.find_child("ViewFortressButton", true, false) as Button
	assert_true(button != null, "the recruit panel offers View fortress on the 3D board")
	assert_true(button.tooltip_text.contains("muster yard"), "and explains it")
	button.pressed.emit()
	assert_eq(b.closeup, f.capital, "the camera swoops into the capital's yard")
	var facing: Vector2 = b.wv.fortresses[f.capital]["gate_dir"]
	assert_true(is_equal_approx(float(b.goal["yaw"]), rad_to_deg(atan2(facing.x, facing.y))), "looking in through the gate")
	assert_true(float(b.goal["span"]) < Board3D.SPAN_NEAR, "closer than the map's nearest zoom")
	assert_true(b.overlay.get_node("CloseupChip").visible, "the chip says where you are and how to leave")
	assert_true((game.map.details.find_child("ViewFortressButton", true, false) as Button).text.contains("Back to the map"), "the panel's button now leads back")
	## the recruit panel stays 2D, and each queued recruit appears in the yard at once
	var types: Array = game.map.orders.recruitable_types()
	game.map.queue_recruit(types[0].id)
	assert_eq(b.closeup, f.capital, "queueing a recruit keeps the close-up")
	assert_eq(b.armies.ghost_count(), 1, "the recruit stands in the yard at once")
	## zooming out leaves it, back where the camera was, north up
	b.zoom_at(b.size * 0.5, -0.07)
	assert_eq(b.closeup, "", "zooming out leaves the close-up")
	assert_eq(b.goal["target"], before_goal["target"], "the camera goes back where it was")
	assert_eq(float(b.goal["yaw"]), 0.0, "north up again")
	assert_false(b.overlay.get_node("CloseupChip").visible)
	## a double-click on a fortress opens it; selecting another province, F, or a playback close it
	b.enter_closeup(f.capital, true)
	game.map.select_province("thornvale")
	assert_eq(b.closeup, "", "selecting another province leaves it")
	b.enter_closeup(f.capital, true)
	b.fit_whole(true)
	assert_eq(b.closeup, "", "F (the whole map) leaves it")
	assert_false(b.enter_closeup("thornvale"), "a province without a fortress has no close-up")
	assert_eq(st.to_dict(), dict_before, "the close-up never touches the game")
	game.free()


# --- the playback: phases, captions, beats, sounds ------------------------------------------------

func test_the_playback_plays_the_reports_phases_with_captions_and_beats() -> void:
	var turns := _autoplay(4242, 14, true)
	var b: Board3D = null
	var checked := 0
	for turn in turns:
		var before: GameState = turn["before"]
		var after: GameState = turn["after"]
		if b == null:
			b = _board_for(before)
		b.map.set_state(after, before.factions[0].id)
		if not b.play_turn(before, turn["events"], after):
			continue
		var plan := Playback.plan(before, turn["events"], after)
		var phases: Array = b.armies.phases()
		var keys: Array = []
		for p in phases:
			assert_true(TurnReportPanel.PHASE_TITLES.has(p["key"]), "%s is one of the turn report's phases" % p["key"])
			assert_eq(p["caption"], Choreo.CAPTIONS[p["key"]])
			if not keys.has(p["key"]):
				keys.append(p["key"])
		var order: Array = Choreo.PHASES.filter(func(k): return keys.has(k))
		assert_eq(keys, order, "turn %d: the phases play in the report's order" % after.current_turn)
		assert_eq(keys.has("movement"), not plan["marches"].is_empty(), "Movement plays when armies march")
		assert_eq(keys.has("battles"), not plan["battles"].is_empty(), "Battles when battles were fought")
		assert_eq(keys.has("capture"), not plan["captures"].is_empty(), "Captures when land changed hands")
		var beats: Array = b.armies.beats()
		var clash := beats.filter(func(x): return x["kind"] == "clash")
		var caps := beats.filter(func(x): return x["kind"] == "capture")
		assert_eq(clash.size(), plan["battles"].size(), "a clash beat for every battle")
		assert_eq(caps.size(), plan["captures"].size(), "a capture beat for every capture")
		## captions while it plays
		var seen := {}
		var guard := 0
		while b.is_playing() and guard < 6000:
			b.armies.step_playback(1.0 / 30.0)
			var now: Dictionary = b.armies.phase_now()
			if not now.is_empty():
				seen[now["key"]] = true
				assert_false(String(now["detail"]).contains("_"), "captions never show ids")
			guard += 1
		for k in keys:
			assert_true(seen.has(k), "turn %d: the %s caption showed" % [after.current_turn, k])
		checked += 1
	assert_true(checked >= 6, "checked over many turns (%d)" % checked)
	_free_board(b)


func test_battles_play_a_strike_and_fall_exchange_and_the_fallen_lie_in_their_pose() -> void:
	var turns := _autoplay(4242, 14, true).filter(func(t): return _has_battle(t))
	assert_false(turns.is_empty(), "the autoplayed game has a battle")
	var turn: Dictionary = turns[0]
	var before: GameState = turn["before"]
	var after: GameState = turn["after"]
	var b := _board_for(before)
	b.map.set_state(after, before.factions[0].id)
	b.armies.snap_at_end = false
	assert_true(b.play_turn(before, turn["events"], after))
	var plan := Playback.plan(before, turn["events"], after)
	var clashes: Array = b.armies._play["clashes"]
	var t0: float = clashes[0]["t0"]
	var poses := {}
	var lunged := false
	var fallen_lying := 0
	var guard := 0
	while b.is_playing() and b.armies.play_time() < t0 + Board3D.Armies.CLASH + 0.3 and guard < 6000:
		b.armies.step_playback(1.0 / 60.0)
		for aid in plan["battles"][0]["armies"]:
			if not b.armies.armies.has(aid):
				continue
			for f in b.armies.armies[aid]["figs"]:
				poses[f["pose"]] = true
				if float(f["lunge"]) > 0.3:
					lunged = true
		guard += 1
	assert_true(poses.has("strike"), "the clash shows strike poses")
	assert_true(lunged, "the strikers lunge")
	assert_true(poses.has("fallen"), "the dead lie in their fallen pose")
	for aid in plan["battles"][0]["destroyed"]:
		if not b.armies.armies.has(aid):
			continue
		for f in b.armies.armies[aid]["figs"]:
			if float(f["fall"]) >= 1.0:
				fallen_lying += 1
	assert_true(fallen_lying > 0, "the losers have toppled")
	_play_out(b)
	assert_false(b.is_playing())
	_free_board(b)


func test_playing_the_turn_with_sound_never_changes_anything() -> void:
	var turns := _autoplay(4242, 14, true).filter(func(t): return _has_battle(t))
	var turn: Dictionary = turns[0]
	var before: GameState = turn["before"]
	var after: GameState = turn["after"]
	var dict_before: Dictionary = before.to_dict()
	var dict_after: Dictionary = after.to_dict()
	var results: Array = []
	var keep: GameAudio = GameAudio.current
	for with_audio in [true, false, true]:
		var audio: GameAudio = null
		if with_audio:
			audio = GameAudio.new()
			audio.quiet = true
			GameAudio.current = audio
		else:
			GameAudio.current = null
		var b := _board_for(before)
		b.map.set_state(after, before.factions[0].id)
		b.armies.snap_at_end = false
		b.play_turn(before, turn["events"], after)
		_play_out(b)
		results.append({"board": b.armies.snapshot(), "owners": b.wv.owners_painted(), "sounds": b.sounds.duplicate()})
		if audio != null:
			var heard: Array = Array(audio.history)
			assert_true(heard.has("march"), "the march sounds")
			assert_true(heard.has("battle_clash"), "the clash sounds")
			assert_true(heard.has("unit_fall"), "the fallen sound")
			audio.free()
		_free_board(b)
	GameAudio.current = keep
	assert_eq(results[0]["board"], results[1]["board"], "the board ends the same with or without sound")
	assert_eq(results[0]["owners"], results[1]["owners"])
	assert_eq(results[0]["sounds"], results[2]["sounds"], "the same turn asks for the same sounds every time (by beat index, never dice)")
	assert_eq(before.to_dict(), dict_before, "the state before is untouched")
	assert_eq(after.to_dict(), dict_after, "the state after is untouched")
	## strikes alternate their sounds by index
	assert_eq(Choreo.sound_for("strike", 0), "battle_hit")
	assert_eq(Choreo.sound_for("strike", 1), "battle_clash")
	assert_eq(Choreo.sound_for("strike", 2), "battle_hit")
	assert_eq(Choreo.sound_for("capture", 5), "capital_captured", "every capture plays the fanfare")
	assert_eq(Choreo.sound_for("nothing", 0), "")


func test_a_capture_sweeps_out_from_the_arriving_column() -> void:
	var turns := _autoplay(4242, 14, true)
	var b: Board3D = null
	var swept := 0
	for turn in turns:
		var before: GameState = turn["before"]
		var after: GameState = turn["after"]
		var plan := Playback.plan(before, turn["events"], after)
		if plan["captures"].is_empty():
			continue
		if b == null:
			b = _board_for(before)
		b.map.set_state(after, before.factions[0].id)
		b.play_turn(before, turn["events"], after)
		var cap: Dictionary = plan["captures"][0]
		var old: Color = b.wv.owners_painted()[cap["province"]]
		var guard := 0
		while b.is_playing() and b.wv.sweeps.is_empty() and guard < 6000:
			b.armies.step_playback(1.0 / 30.0)
			guard += 1
		assert_false(b.wv.sweeps.is_empty(), "a capture starts a sweep")
		if not b.wv.sweeps.is_empty():
			var sw: Dictionary = b.wv.sweeps[0]
			assert_eq(int(sw["i"]), b.wv.terrain.index_of(cap["province"]), "on the captured province")
			assert_true((sw["old"] as Color).is_equal_approx(old) or old.a < 0.5, "over its old owner's colour")
			swept += 1
		_play_out(b)
		assert_true(b.wv.sweeps.is_empty(), "the sweeps are done when the playback ends")
		if swept >= 2:
			break
	assert_true(swept >= 1, "a capture swept")
	if b != null:
		_free_board(b)


# --- every seat sees the turn, and can watch it again ---------------------------------------------

func test_every_hotseat_seat_sees_the_playback_and_can_watch_it_again() -> void:
	var game := _game_with_board({"players": ["kingdom", "beasts"], "seed": 21})
	var b: Board3D = game.map.board
	var st: GameState = game.map.state
	for a in st.armies:
		if a.owner == game.map.viewing_faction_id:
			game.map.queue_move(a.id, st.find_province(a.location).neighbors[0])
			break
	game.end_turn()
	game.handoff._on_ready_pressed()
	game.end_turn()
	assert_true(game.handoff.visible, "the turn resolved; seat 1's handoff")
	game.handoff._on_ready_pressed()
	assert_true(b.is_playing(), "seat 1 sees the turn play out")
	b.skip_playback()
	assert_true(game.report_overlay.visible, "then the report")
	assert_true(game.report_panel.watch_again_button.visible, "with Watch this turn again")
	var history: int = game.session.record()["history"].size()
	game.report_panel.watch_again_button.pressed.emit()
	assert_false(game.report_overlay.visible, "watching again closes the report")
	assert_true(b.is_playing(), "and plays the turn again")
	b.skip_playback()
	assert_true(game.report_overlay.visible, "the report opens again after it")
	assert_eq(game.session.record()["history"].size(), history, "watching again never resolves anything")
	## seat 1 plans the next turn, then seat 2 (who resolved the turn) sees it behind its own handoff
	game.close_turn_report()
	game.end_turn()
	assert_true(game.handoff.visible)
	game.handoff._on_ready_pressed()
	assert_true(b.is_playing(), "seat 2 sees the turn play out too, once")
	b.skip_playback()
	assert_eq(b.armies.ghost_count(), 0, "and none of seat 1's queued orders")
	game.free()


# --- the board only reads the game ------------------------------------------------------------------

func test_no_random_numbers_anywhere_in_world3d() -> void:
	var dir := DirAccess.open("res://world3d")
	assert_true(dir != null)
	var scanned := 0
	for file in dir.get_files():
		if not file.ends_with(".gd"):
			continue
		## scenario.gd seeds the real AI's own dice to autoplay a game for the dev preview: game rules, not looks
		if file == "scenario.gd":
			continue
		var text := FileAccess.get_file_as_string("res://world3d/" + file)
		for banned in ["RandomNumberGenerator", "SeededRNG", "randf", "randi", "randomize(", "rand_range", "randfn", "seed("]:
			assert_false(text.contains(banned), "world3d/%s never uses %s" % [file, banned])
		scanned += 1
	assert_true(scanned >= 10, "every world3d script was scanned (%d)" % scanned)


func test_playback_cpu_stays_inside_the_budget_on_a_big_turn() -> void:
	## a mid-game turn with many armies, stepped at fixed 1/60 s: the average cost of a step (design
	## 3.5: about 2 ms on the build box; generous here, as the suite shares the machine)
	var turns := _autoplay(4242, 16, true)
	var turn: Dictionary = turns[turns.size() - 1]
	for t in turns:
		if (t["after"] as GameState).armies.size() >= (turn["after"] as GameState).armies.size():
			turn = t
	var b := _board_for(turn["before"])
	b.map.set_state(turn["after"], (turn["before"] as GameState).factions[0].id)
	if not b.play_turn(turn["before"], turn["events"], turn["after"]):
		_free_board(b)
		return
	var steps := 0
	var t0 := Time.get_ticks_usec()
	while b.is_playing() and steps < 6000:
		b.armies.step_playback(1.0 / 60.0)
		steps += 1
	var avg_ms: float = (Time.get_ticks_usec() - t0) / 1000.0 / maxf(steps, 1)
	assert_false(b.is_playing(), "the big turn plays to its end")
	assert_perf(avg_ms < 4.0, "a playback step: %.2f ms on average over %d steps, %d figures (budget 4 ms; design 3.5 asks 2 ms on the build box)" % [avg_ms, steps, b.armies.figure_count()])
	_free_board(b)


# --- the world from the model table (PR #91's rows) -------------------------------------------------

func test_every_army_carries_its_factions_bearer_and_musician() -> void:
	var st := GameState.with_rulers(11, {}, [])
	var b := _board_for(st)
	var extras: Array = b.armies.extras()
	assert_true(extras.has("bearer"), "every army has a standard bearer")
	assert_eq(extras.has("musician"), Models.has_musician(), "and a musician when the table has one")
	for a in st.armies:
		var roles: Array = (b.armies.armies[a.id]["figs"] as Array).map(func(f): return f["role"])
		for ex in extras:
			assert_eq(roles.count(ex), 1, "%s stands with one %s" % [a.id, ex])
		var figs := 0
		for f in b.armies.armies[a.id]["figs"]:
			if f["role"] == "unit":
				figs += 1
		var want := 0
		var counts := {}
		for u in a.units:
			counts[u.type.id] = int(counts.get(u.type.id, 0)) + 1
		for t in counts.keys():
			want += Models.block_size(counts[t])
		assert_eq(figs, want, "%s: the extras never count as its units" % a.id)
	for f in FactionData.FACTIONS:
		var path := Models.extra_model_path("bearer", String(f.id))
		if not path.is_empty():
			assert_eq(Models.figure_mesh("bearer", true, "ready", String(f.id))["source"], "model", "the %s bearer wears its faction's model" % f.id)
	_free_board(b)


func test_the_board_reads_forts_villages_landmarks_and_props() -> void:
	var st := GameState.new(4242)
	var b := _board_for(st)
	var t = b.wv.terrain
	for i in t.ids.size():
		if t.has_fort[i] and not t.is_capital[i]:
			assert_true(b.wv.forts.has(t.ids[i]), "%s has its fort" % t.ids[i])
	## villages: at most one per province, of its terrain's kind, its variant from a hash of its id
	var villages: Array = b.wv.plan_of(t)["villages"]
	var seen := {}
	for v in villages:
		var kind: String = v["kind"]
		if kind.begins_with("village_"):
			assert_false(seen.has(v["province"]), "one village per province")
			seen[v["province"]] = true
			assert_eq(kind, "village_" + String(t.terrain_of[t.index_of(v["province"])]), "a village of its province's terrain")
		assert_true(t.province_at(v["pos"]) == v["province"], "%s stands on its own province" % kind)
	if not Models.building_variants("village_plains").is_empty():
		assert_true(villages.size() >= 8, "most provinces have a village (%d)" % villages.size())
	var n: int = Models.building_variants("village_plains").size()
	assert_eq(Models.variant_for("thornvale", n), Models.variant_for("thornvale", n), "a province always shows the same variant")
	## the trees and rocks as models close in, primitives far out
	if not b.wv._prop_chunks.is_empty():
		b.wv.set_prop_models(true)
		assert_true(b.wv.prop_models)
		for mi in b.wv._prop_prims:
			assert_false((mi as Node3D).visible, "close in, the primitive woods hide")
		b.wv.set_prop_models(false)
		for mi in b.wv._prop_chunks:
			assert_false((mi as Node3D).visible, "far out, the model woods hide")
	## the fort's roofs follow its owner
	for id in b.wv.forts.keys():
		var p := st.find_province(id)
		var want: Color = UiPalette.owner_color(st, p.owner, b.seats) if not p.owner.is_empty() else UiPalette.NEUTRAL
		var got: Color = (b.wv.forts[id]["mat"] as ShaderMaterial).get_shader_parameter("team")
		assert_true(got.is_equal_approx(want), "%s's fort roofs are its owner's colour" % id)
	_free_board(b)


func test_a_figure_never_stands_shorter_than_the_minimum_on_screen() -> void:
	var game := _game_with_board()
	var b: Board3D = game.map.board
	for z in [0.0, 0.3, Board3D.FOCUS_ZOOM, 1.0]:
		b.zoom = z
		b.goal = b.rig_for(Vector2(500, 300), z)
		b._snap_rig()
		b._camera(0.016)
		var px_per_unit: float = b.size.y / float(b.wv.rig["span"])
		var px: float = b.armies.fig_scale * Board3D.Armies.Kit.FIG * px_per_unit
		if is_equal_approx(b.armies.fig_scale, Board3D.MAX_PIECE_SCALE):
			## the whole map: piece scale stops where blocks would pile into each other (the far-zoom
			## stand of design 6.1 takes over from there; the count plates carry the army meanwhile)
			assert_true(z < 0.2, "only the whole-map end hits the piece-scale cap (zoom %.2f)" % z)
			continue
		assert_true(px >= Board3D.MIN_FIG_PX - 0.5, "at zoom %.2f a man-sized figure stands %.1f px tall (at least %.0f)" % [z, px, Board3D.MIN_FIG_PX])
	game.free()
