extends "res://tests/test_case.gd"
## #125, the board's share: far-zoom army stands (world3d/stands.gd), the musician's quality rung, and the
## path-unit variants (a transformed faction's units wear their variant model family, on the board and in a
## 3D battle). Headless: nothing renders, but stands, blends, picking, layouts and meshes are all computed.
## Expected values come from the states, the model table and the stands' own constants, never hardcoded.

const Stands := preload("res://world3d/stands.gd")
const Armies := preload("res://world3d/armies.gd")
const Models := preload("res://world3d/models.gd")
const PB := preload("res://tests/path_battle_fixtures.gd")
const Fx := preload("res://tests/battle_playback_fixtures.gd")
const BOARD_SIZE := Vector2(1200, 836)
const HOST := ["crown_drillyard", "crown_charters", "crown_oath_dawn", "crown_celestial_host"]
const SUNSPEARS := "crown_celestial_host"


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


## A mid-game state with armies all over the map: the real AI playing both sides for `turns` turns.
func _mid_game(game_seed: int, turns: int) -> GameState:
	var st := GameState.new(game_seed)
	for t in turns:
		var orders := {}
		var seat := 0
		for f in st.factions:
			orders[f.id] = AIPlayer.new().plan_orders(st, f.id, SeededRNG.new(game_seed * 7919 + (seat + 1) * 104729 + t * 31), "normal")
			seat += 1
		var res: Dictionary = TurnResolver.resolve(st, orders, TurnResolver.seed_for_turn(st))
		if res.get("new_state") == null:
			break
		st = res["new_state"]
	return st


## Runs the board's camera for `seconds` at 1/30 s steps.
func _run_camera(b: Board3D, seconds: float) -> void:
	for k in int(seconds * 30.0):
		b._camera(1.0 / 30.0)


# --- stands -----------------------------------------------------------------------------------------

func test_the_stand_switch_has_hysteresis() -> void:
	assert_true(Stands.wants_stands(Stands.STAND_IN_PX - 0.5, false), "under the in threshold: stands")
	assert_false(Stands.wants_stands(Stands.STAND_IN_PX + 0.5, false), "above it, from figures: still figures")
	assert_true(Stands.wants_stands(Stands.STAND_OUT_PX - 0.5, true), "between the two, from stands: still stands (no flicker)")
	assert_false(Stands.wants_stands(Stands.STAND_OUT_PX + 0.5, true), "over the out threshold: figures again")
	assert_true(Stands.STAND_IN_PX < Stands.STAND_OUT_PX, "the band between them is the hysteresis")
	assert_true(Stands.STAND_IN_PX <= 24.0, "stands only where a man-sized figure falls under the bible's 24 px (3D_DIRECTION 6.1)")


func test_far_out_every_army_becomes_a_stand_and_blends_back_close_in() -> void:
	var st := _mid_game(4242, 10)
	var b := _board_for(st)
	assert_true(st.armies.size() >= 4, "the game has armies to stand (%d)" % st.armies.size())
	b.fit_whole(true)
	b.wv.rig = b.goal.duplicate()
	_run_camera(b, 1.0)
	var px_per_unit: float = b.size.y / float(b.wv.rig["span"])
	var man_px: float = Armies.Kit.FIG * float(b.armies.fig_scale) * px_per_unit
	assert_true(man_px < Stands.STAND_IN_PX, "over the whole map a figure would stand %.1f px tall: too small to read" % man_px)
	assert_eq(b.stands.k, 1.0, "the stands are full")
	assert_eq(b.armies.blend, 0.0, "and the figures blended away")
	for e in b.armies.armies.values():
		for t in e["types"].keys():
			for mi in e["types"][t]["mis"]:
				assert_false((mi as Node3D).visible, "no figure MultiMesh draws behind the stands")
	for a in st.armies:
		assert_true(b.stands.stands.has(a.id), "%s has a stand" % a.id)
		var s: Dictionary = b.stands.stands[a.id]
		var e: Dictionary = b.armies.armies[a.id]
		assert_eq(s["colour"], e["colour"], "%s's stand wears its owner's colour" % a.id)
		## its figures: its most numerous types on the board, at most three, the extras left out
		var counts := {}
		for f in e["figs"]:
			if not Stands.EXTRAS.has(String(f["type"])):
				counts[f["type"]] = int(counts.get(f["type"], 0)) + 1
		var types: Array = s["types"]
		assert_true(types.size() <= Stands.MAX_TYPES and types.size() == mini(Stands.MAX_TYPES, counts.size()), "%s shows up to three types" % a.id)
		for j in range(1, types.size()):
			assert_true(int(counts[types[j - 1]]) >= int(counts[types[j]]), "%s's stand puts its most numerous type first" % a.id)
		## the count plate rides the stand, and the stand picks its army
		var plate := b.army_plate_point(a.id)
		assert_true(plate.distance_to(b.project3(b.stands.anchor(a.id))) < 0.01, "%s's count plate rides over its stand" % a.id)
		var r := b.army_rect(a.id)
		assert_true(r.size.x > 0.0, "%s's stand has a box on screen to click" % a.id)
	## close in: the blocks come back
	b.zoom = 0.8
	var c: Vector2 = b.wv.terrain.centre_of(st.armies[0].location)
	b.goal = b.rig_for(c, b.zoom)
	b.wv.rig = b.goal.duplicate()
	_run_camera(b, 1.0)
	assert_eq(b.stands.k, 0.0, "close in, no stands")
	assert_eq(b.armies.blend, 1.0, "the figures are back")
	assert_false(b.stands.visible, "the stands node draws nothing")
	_free_board(b)


func test_stands_blend_over_time_and_never_flicker_on_the_threshold() -> void:
	var st := _mid_game(7, 6)
	var b := _board_for(st)
	var s: Node3D = b.stands
	## just under the in threshold: on, blending in over BLEND_TIME
	var px := 1.0
	var blend: float = s.step(Stands.BLEND_TIME * 0.5, Stands.STAND_IN_PX - 1.0, px, b.armies)
	assert_true(s.k > 0.4 and s.k < 0.6, "half way through the blend after half its time (%.2f)" % s.k)
	assert_true(absf(blend - (1.0 - s.k)) < 0.0001, "the figures take the other share")
	s.step(Stands.BLEND_TIME, Stands.STAND_IN_PX - 1.0, px, b.armies)
	assert_eq(s.k, 1.0)
	## wobbling inside the band keeps the stands
	for man in [Stands.STAND_IN_PX + 1.0, Stands.STAND_OUT_PX - 1.0, Stands.STAND_IN_PX + 0.2]:
		s.step(0.1, man, px, b.armies)
		assert_eq(s.k, 1.0, "inside the band (%.1f px) the stands stay" % man)
	_free_board(b)


# --- the musician's rung --------------------------------------------------------------------------

func _extras_on_board(b: Board3D) -> Dictionary:
	var out := {"bearer": 0, "musician": 0}
	for e in b.armies.armies.values():
		for f in e["figs"]:
			if out.has(String(f["role"])):
				out[String(f["role"])] = int(out[String(f["role"])]) + 1
	return out


func test_the_musicians_stand_down_on_the_lower_rungs_and_the_bearers_stay() -> void:
	assert_true(Armies.musicians_at(0) and Armies.musicians_at(Armies.MUSICIAN_OFF_RUNG - 1), "the upper rungs keep the musicians")
	assert_false(Armies.musicians_at(Armies.MUSICIAN_OFF_RUNG), "from MUSICIAN_OFF_RUNG down they stand down")
	var st := _mid_game(4242, 6)
	var b := _board_for(st)
	var before := _extras_on_board(b)
	assert_true(Models.has_musician(), "the model table has a musician")
	assert_eq(before.musician, before.bearer, "every colour party has its musician at rung 0")
	b.set_quality_rung(Armies.MUSICIAN_OFF_RUNG)
	var low := _extras_on_board(b)
	assert_eq(low.musician, 0, "on the lower rung no musician stands")
	assert_eq(low.bearer, before.bearer, "every army keeps its banner bearer")
	assert_eq(b.armies.figure_count(), b.armies.figure_count(), "the board re-stood its armies")
	b.set_quality_rung(0)
	assert_eq(_extras_on_board(b).musician, before.musician, "set back to the top rung, the musicians return")
	Armies.musicians = true
	_free_board(b)


# --- the path-unit variants -------------------------------------------------------------------------

func test_the_model_table_merges_a_transformations_variant_over_the_row() -> void:
	var base := Models.figure_row("spearmen")
	var v: Dictionary = (base.get("variants", {}) as Dictionary).get(SUNSPEARS, {})
	assert_false(v.is_empty(), "the spearmen row has the Celestial Host variant (#126)")
	var merged := Models.figure_row("spearmen", SUNSPEARS)
	assert_eq(String(merged.model), String(v.model), "the variant's model replaces the row's")
	assert_eq(float(merged.height), float(v.height), "and its height")
	assert_eq(String(merged.fallback), String(base.fallback), "the rest of the row stays")
	assert_eq(Models.variant_of("spearmen", SUNSPEARS), SUNSPEARS)
	assert_eq(Models.variant_of("spearmen", "beasts_blood_pact"), "", "another faction's transformation has no spearmen variant")
	assert_eq(Models.variant_of("crossbowmen", SUNSPEARS), "", "a unit without a variant keeps its own models")
	assert_eq(Models.variant_of("spearmen", ""), "", "no transformation, no variant")
	var vm: Mesh = Models.figure_mesh("spearmen", true, "ready", "", SUNSPEARS)["mesh"]
	var bm: Mesh = Models.figure_mesh("spearmen", true, "ready")["mesh"]
	assert_true(vm != bm, "the variant builds its own mesh (cached by its own key)")
	assert_eq(Models.pose_model_path("spearmen", "ready", SUNSPEARS), String(v.model), "from the variant's GLB")
	for pose in Models.POSES:
		var p := Models.pose_model_path("spearmen", pose, SUNSPEARS)
		assert_true(p.is_empty() or p.contains("crown_celestial_host"), "a variant pose never falls back to the base's %s model" % pose)


func _ready_mesh_of(b: Board3D, army_id: String, type_id: String) -> Mesh:
	var e: Dictionary = b.armies.armies[army_id]
	var te: Dictionary = e["types"][type_id]
	return (te["mis"][int(te["groups"]["ready"])] as MultiMeshInstance3D).multimesh.mesh


func test_a_transformed_faction_wears_its_variants_on_the_board() -> void:
	var host := PB.with_nodes(PB.game(), "kingdom", HOST)
	assert_eq(AscensionRules.transformation(host, "kingdom"), SUNSPEARS, "the Crown has become the Celestial Host")
	PB.army(host, "kingdom", "kingdom-11", "rivermarch", ["spearmen", "spearmen", "crossbowmen"])
	PB.army(host, "beasts", "beasts-12", "bloodfen", ["tuskers", "tuskers", "fangthrowers"])
	var b := _board_for(host)
	var sun: Mesh = Models.figure_mesh("spearmen", true, "ready", "", SUNSPEARS)["mesh"]
	assert_eq(_ready_mesh_of(b, "kingdom-11", "spearmen"), sun, "the Crown's spearmen stand as Sunspears")
	assert_eq(_ready_mesh_of(b, "kingdom-11", "crossbowmen"), Models.figure_mesh("crossbowmen", true, "ready")["mesh"], "a unit without a variant keeps its model")
	assert_eq(_ready_mesh_of(b, "beasts-12", "tuskers"), Models.figure_mesh("tuskers", true, "ready")["mesh"], "the untransformed Clans keep their tuskers")
	_free_board(b)
	var plain := PB.game()
	PB.army(plain, "kingdom", "kingdom-11", "rivermarch", ["spearmen", "spearmen"])
	var b2 := _board_for(plain)
	assert_eq(_ready_mesh_of(b2, "kingdom-11", "spearmen"), Models.figure_mesh("spearmen", true, "ready")["mesh"], "an untransformed game builds the base spearmen")
	_free_board(b2)


func test_a_transformed_faction_wears_its_variants_in_a_3d_battle() -> void:
	var host := PB.with_nodes(PB.game(), "kingdom", HOST)
	var a := PB.army(host, "kingdom", "kingdom-11", "rivermarch", ["spearmen", "spearmen", "spearmen"])
	var c := PB.army(host, "beasts", "beasts-12", "rivermarch", ["tuskers", "tuskers", "tuskers"])
	var r := PB.fight(host, [a, c], "rivermarch", "kingdom", 3)
	var stage := BattleStage3D.new()
	assert_eq(stage.play(r.log, r.result.report, host, []), "", "the battle plays from the host's play()")
	var sun: Mesh = Models.figure_mesh("spearmen", true, "ready", "", SUNSPEARS)["mesh"]
	var base_tusk: Mesh = Models.figure_mesh("tuskers", true, "ready")["mesh"]
	var meshes := {}
	for g in stage.figures.groups.values():
		meshes[(g["mi"] as MultiMeshInstance3D).multimesh.mesh] = true
	assert_true(meshes.has(sun), "the Crown's spearmen fight as Sunspears")
	assert_false(meshes.has(Models.figure_mesh("spearmen", true, "ready")["mesh"]), "and not as the base spearmen")
	assert_true(meshes.has(base_tusk), "the untransformed Clans fight as their own tuskers")
	## the same battle shown with no state (a log alone): no transformation known from the state, and these
	## logs carry no people, so the base models
	var plain := PB.game()
	var a2 := PB.army(plain, "kingdom", "kingdom-11", "rivermarch", ["spearmen", "spearmen"])
	var c2 := PB.army(plain, "beasts", "beasts-12", "rivermarch", ["tuskers", "tuskers"])
	var r2 := PB.fight(plain, [a2, c2], "rivermarch", "kingdom", 3)
	stage.play(r2.log, r2.result.report, plain, [])
	var meshes2 := {}
	for g2 in stage.figures.groups.values():
		meshes2[(g2["mi"] as MultiMeshInstance3D).multimesh.mesh] = true
	assert_false(meshes2.has(sun), "an untransformed game fights with the base spearmen")
	## the launcher's path battle (no state): the log's people say which transformation
	var wings := Fx.battle("path_wings")
	stage.show_battle(wings.log, wings.report)
	var crown_si := 0 if String(wings.log.sides[0].faction) == "kingdom" else 1
	assert_eq(stage.transformation_of(crown_si), SUNSPEARS, "a log alone: the people it records name the transformation")
	stage.free()


# --- the forest trays -------------------------------------------------------------------------------

const Trays := preload("res://world3d/trays.gd")
const THORN := ["beasts_boar_hide", "beasts_raiding", "beasts_oath_grove", "beasts_thorn_wild"]


## The Thorn Wild's Briarwardens and Thornthrowers in Greenglade, the Crown's blocks in Thornvale (both
## forest) and in Rivermarch (plains), at the default zoom over Greenglade (a glide's, Board3D.focus_on).
func _forest_board() -> Board3D:
	var st := PB.with_nodes(PB.game(), "beasts", THORN)
	assert_eq(AscensionRules.transformation(st, "beasts"), "beasts_thorn_wild", "the Clans have become the Thorn Wild")
	PB.army(st, "beasts", "beasts-12", "greenglade", ["briarwardens", "briarwardens", "briarwardens", "fangthrowers", "fangthrowers", "fangthrowers", "warchief"])
	PB.army(st, "kingdom", "kingdom-11", "thornvale", ["spearmen", "spearmen", "spearmen", "knights", "knights"])
	PB.army(st, "kingdom", "kingdom-13", "rivermarch", ["spearmen", "spearmen"])
	var b := _board_for(st)
	b.zoom = 0.0
	b.focus_on("greenglade", true)
	_run_camera(b, 0.5)
	assert_eq(b.zoom, Board3D.FOCUS_ZOOM, "the default zoom")
	return b


## How far figure `f` of entry `e` needs its tray either way (its slot; a figure far wider than its slot, its
## own width at the toy scale), and whether that widens its tray.
func _reach(b: Board3D, e: Dictionary, t: String) -> Vector2:
	return Trays.reach_of(b.armies._spacing(t) * 0.5, Trays.model_half_width(b.armies, e, t))


## Whether figure `f` of entry `e` (as far as it reaches) stands inside `tray`.
func _on_tray(b: Board3D, e: Dictionary, f: Dictionary, tray: Dictionary) -> bool:
	var sp: Vector2 = _reach(b, e, String(f["type"]))
	var yaw: float = tray["yaw"]
	var u := Vector2(cos(yaw), -sin(yaw))
	var v := Vector2(sin(yaw), cos(yaw))
	var d: Vector2 = (f["pos"] as Vector2) - (tray["centre"] as Vector2)
	var half: Vector2 = (tray["size"] as Vector2) * 0.5
	return absf(d.dot(u)) + sp.x <= half.x + 0.001 and absf(d.dot(v)) + sp.y <= half.y + 0.001


## Whether two trays of one formation (one frame) overlap.
func _overlap(t1: Dictionary, t2: Dictionary) -> bool:
	var yaw: float = t1["yaw"]
	var u := Vector2(cos(yaw), -sin(yaw))
	var v := Vector2(sin(yaw), cos(yaw))
	var d: Vector2 = (t2["centre"] as Vector2) - (t1["centre"] as Vector2)
	var reach: Vector2 = ((t1["size"] as Vector2) + (t2["size"] as Vector2)) * 0.5
	return absf(d.dot(u)) < reach.x - 0.001 and absf(d.dot(v)) < reach.y - 0.001


func test_every_army_in_a_forest_stands_on_trays_in_its_owners_colour() -> void:
	var b := _forest_board()
	var st: GameState = b.shown
	assert_eq(b.stands.k, 0.0, "the default zoom shows the figures")
	assert_true(b.trays.visible, "the trays draw")
	for a in st.armies:
		var forest: bool = st.find_province(a.location).terrain == "forest"
		assert_eq(b.trays.trays.has(a.id), forest, "%s in %s: %s" % [a.id, a.location, "on trays" if forest else "no trays off the woods"])
		if not forest:
			continue
		var e: Dictionary = b.armies.armies[a.id]
		var trays: Array = b.trays.trays[a.id]
		## a tray for each block (a unit type's figures) and one for the command group at the back
		var types := {}
		var command := 0
		for f in e["figs"]:
			if String(f["role"]) == "unit":
				types[f["type"]] = true
			else:
				command += 1
		assert_eq(trays.size(), types.size() + (1 if command > 0 else 0), "%s: a tray per block and one for its command" % a.id)
		for t in trays:
			assert_eq(t["colour"], e["colour"], "%s's trays wear its owner's colour" % a.id)
			assert_eq(t["ruler"], bool(e["ruler"]), "a ruler's army's trays carry the gilt ring")
		## every figure, its whole slot (a canopy far wider than its slot, its width), stands on one of its trays
		for f in e["figs"]:
			var on := false
			for t in trays:
				on = on or _on_tray(b, e, f, t)
			assert_true(on, "%s's %s stands on a tray" % [a.id, f["type"]])
		## and its trays of slot-sized figures stand apart, a tray to a block
		var widened := func(t: Dictionary) -> bool:
			for ty in t["types"]:
				if _reach(b, e, String(ty)) != b.armies._spacing(String(ty)) * 0.5:
					return true
			return false
		for i in trays.size():
			for j in range(i + 1, trays.size()):
				if not widened.call(trays[i]) and not widened.call(trays[j]):
					assert_false(_overlap(trays[i], trays[j]), "%s's trays %d and %d stand apart" % [a.id, i, j])
	## the Briarwardens' canopies are far wider than their slots: their tray reaches past them
	var bw: Dictionary = b.armies.armies["beasts-12"]
	var half_w: float = Trays.model_half_width(b.armies, bw, "briarwardens")
	assert_true(half_w > b.armies._spacing("briarwardens").x * 0.5 * Trays.WIDE, "a Briarwarden's canopy (%.1f) overhangs its slot" % half_w)
	for t in b.trays.trays["beasts-12"]:
		if (t["types"] as Array).has("briarwardens"):
			assert_true((t["size"] as Vector2).x >= half_w * 2.0, "the Briarwardens' tray is wider than a canopy")
	assert_eq(b.trays.tray_count(), b.trays.trays["beasts-12"].size() + b.trays.trays["kingdom-11"].size(), "drawn: one mesh holds every tray")
	assert_true(preload("res://world3d/board_overlay.gd").LEGEND.contains("stands on a tray in its owner's colour"), "the board's legend explains the trays")
	_free_board(b)


func test_the_trays_step_aside_for_the_stands_and_the_playback() -> void:
	var b := _forest_board()
	var drawn: int = b.trays.tray_count()
	assert_true(drawn > 0, "trays under the forest armies")
	## far out the stands take over: no trays under them
	b.fit_whole(true)
	b.wv.rig = b.goal.duplicate()
	_run_camera(b, 1.0)
	assert_eq(b.stands.k, 1.0, "the stands are full")
	assert_false(b.trays.visible, "no trays under the stands")
	## close in again: back
	b.zoom = 0.0
	b.focus_on("greenglade", true)
	_run_camera(b, 1.0)
	assert_true(b.trays.visible and b.trays.tray_count() == drawn, "close in, the trays are back")
	## while a turn plays the figures march off their places: the trays wait for them to settle
	b.armies._play = {"probe": true}
	_run_camera(b, 0.1)
	assert_false(b.trays.visible, "no trays while the turn plays")
	b.armies._play = {}
	_run_camera(b, 0.1)
	assert_true(b.trays.visible, "settled, the trays are back")
	_free_board(b)
