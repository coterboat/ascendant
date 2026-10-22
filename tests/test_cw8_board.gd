extends "res://tests/test_case.gd"
## CW-8 (#259, design/CANDLEWAKE.md §10): the Candlewake on the 3D board, the army half. Every Candlewake figure (the host, the
## candlebeasts, the commander and rulers, the mage, the Snuffed, the Pouring's new units) is a code-primitive placeholder with a
## row in world3d/models.json; the army's flame burns on its regulars' crown wicks (smoke at 0, lilac to a tall flame at 3, cherry at
## 4, nothing out of clear sight); the host stands as a slumped crowd. The Crown's and the Clans' armies look as before.

const Kit := preload("res://world3d/kit.gd")
const Models := preload("res://world3d/models.gd")
const Armies := preload("res://world3d/armies.gd")
const CandleFigures := preload("res://world3d/candle_figures.gd")
const CROWN := "kingdom"
const WAKE := "candlewake"
const BOARD_SIZE := Vector2(1280, 720)


func _wake_ids() -> Array:
	var row := FactionData.row(WAKE)
	var out: Array = row.unit_types.map(func(u): return String(u.id)) + [String(row.commander.id)]
	for r in RulerRules.rulers_for(WAKE):
		out.append(String(r))
	out.append(String(MagicData.PREVIEW_MAGES[WAKE].id))
	for sid in MagicData.PREVIEW_SUMMONS:
		out.append(String(sid))
	for nid in PathData.PREVIEW_NEW_UNITS:
		out.append(String(nid))
	return out


func _board_for(state: GameState) -> Board3D:
	var map := load("res://ui/map_screen.tscn").instantiate() as MapScreen
	map.set_state(state, state.factions[0].id)
	var b := Board3D.new()
	map.set_board(b)
	b.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	b.size = BOARD_SIZE
	b.build_now()
	return b


func _army(s: GameState, at: String, types: Array, flame: int) -> Army:
	var a := Army.new()
	a.id = s.new_army_id(WAKE)
	a.owner = WAKE
	a.location = at
	for t in types:
		a.units.append(Unit.new(TurnResolver.recruitable_type(s.find_faction(WAKE), String(t), s), WAKE))
	a.flame = flame
	s.armies.append(a)
	return a


# --- the figures -------------------------------------------------------------------------------------------

func test_every_candlewake_figure_has_its_row_and_draws() -> void:
	for id in _wake_ids():
		assert_true(CandleFigures.has(id), "%s is one of the Candlewake's figures" % id)
		assert_true(Kit.has_figure(id), "%s has a figure" % id)
		var row := Models.figure_row(id)
		assert_eq(String(row.get("faction", "")), WAKE, "%s's row" % id)
		assert_eq(String(row.get("fallback", "")), id, "%s falls back to its own primitive" % id)
		var m: ArrayMesh = Kit.figure(id)
		assert_true(m.get_aabb().size.y > 2.5, "%s stands up: %s" % [id, m.get_aabb()])
	var hound: AABB = Kit.figure("wax_hounds").get_aabb()
	assert_true(hound.size.z > hound.size.y, "a hound is longer than it is tall (the 24 px silhouette reads a beast)")
	for id in ["half_death", "mother_tallow"]:
		assert_true(Models.is_ruler(id), "%s wears the ruler's ring" % id)
	assert_eq(Models.rank_of("chandlers_apprentices"), 1, "the mage stands in the second rank")
	assert_eq(Models.rank_of("lamplighter"), 2, "the commander at the back")


func test_each_burning_figures_wick_is_its_rows_anchor() -> void:
	for id in CandleFigures.BURNING:
		var top := CandleFigures.wick_top(id)
		assert_true(top.y > 2.0, "%s has a wick: %s" % [id, top])
		assert_true(Models.fx_top(id).distance_to(top) < 0.01, "%s's row anchors the flame at its wick: %s vs %s" % [id, Models.fx_top(id), top])
	for id in ["lamplighter", "mother_tallow", "chandlers_apprentices", "snuffed"]:
		assert_false(CandleFigures.burns(id), "%s never burns the army's flame" % id)


func test_flame_height_is_the_flame() -> void:
	assert_eq(CandleFigures.flame_look(-1), {}, "no flame shown out of clear sight")
	assert_true(bool(CandleFigures.flame_look(0).smoke), "smoke at 0")
	var h := []
	for f in [1, 2, 3, 4]:
		var look := CandleFigures.flame_look(f)
		assert_false(bool(look.smoke), "a flame at %d" % f)
		h.append(float(look.h))
	assert_true(h[0] < h[1] and h[1] < h[2] and h[2] < h[3], "taller with the flame: %s" % [h])
	assert_eq((CandleFigures.flame_look(3).col as Color).r < (CandleFigures.flame_look(3).col as Color).b, true, "lilac at 3")
	assert_true((CandleFigures.flame_look(4).col as Color).r > (CandleFigures.flame_look(4).col as Color).b, "cherry-red at 4 (the Red Wake)")
	assert_true(Armies.flicker_at(0, false) and not Armies.flicker_at(2, false) and not Armies.flicker_at(0, true),
		"the flames sway on the top rungs only, never with reduced motion")


# --- the massing ------------------------------------------------------------------------------------------------

func test_the_host_stands_as_a_slumped_crowd_and_everyone_else_as_before() -> void:
	var blocks := [{"type": "wickwardens", "n": 8, "rank": 0, "sp": Vector2(4.2, 4.4)}]
	var leaders := [{"type": "lamplighter", "role": "commander", "rank": 2, "sp": Vector2(6.0, 6.0)}]
	var ranks := Kit.formation_blocks(blocks, leaders, 44.0)
	var crowd := Kit.slump(ranks, "candlewake-3")
	assert_eq(crowd, Kit.slump(ranks, "candlewake-3"), "the same army slumps the same way every time")
	assert_ne(crowd, Kit.slump(ranks, "candlewake-4"), "and another army its own way")
	var moved := 0
	for i in ranks.size():
		var a: Dictionary = ranks[i]
		var b: Dictionary = crowd[i]
		var d: Vector2 = (b.pos as Vector2) - (a.pos as Vector2)
		if String(a.role) == "unit":
			assert_true(absf(d.x) <= Kit.SLUMP_X and d.y >= 0.0 and d.y <= Kit.SLUMP_Z, "a figure sags within its place: %s" % d)
			assert_true(absf(float(b.yaw_off)) <= Kit.SLUMP_YAW)
			if d.length() > 0.05:
				moved += 1
		else:
			assert_eq(d, Vector2.ZERO, "%s keeps its place" % a.role)
	assert_true(moved >= 6, "never a rectangle: %d of 8 moved" % moved)


# --- on the board -------------------------------------------------------------------------------------------------

func test_the_flame_burns_on_the_regulars_wicks_on_the_board() -> void:
	var errors := []
	var s := GameState.create(23, [CROWN, WAKE], {}, {}, errors)
	assert_eq(errors, [])
	var cap := s.find_faction(WAKE).capital
	var near: Array = s.find_province(cap).neighbors.duplicate()
	near.sort()
	var hot := _army(s, String(near[0]), ["wickwardens", "wickwardens", "gleaners", "wax_hounds"], 3)
	var cold := _army(s, String(near[1]), ["wickwardens", "wickwardens"], 0)
	var b := _board_for(s)
	var armies = b.armies
	var e: Dictionary = armies.armies[hot.id]
	assert_true(e.get("wick") != null, "a burning army has its wick flames")
	var burning: int = e["figs"].filter(func(f): return String(f.role) == "unit" and CandleFigures.burns(String(f.type))).size()
	assert_eq((e["wick"] as MultiMeshInstance3D).multimesh.instance_count, burning, "one flame for each regular's figure")
	assert_eq(int(e.flame), 3)
	assert_true(bool(armies.armies[cold.id]["wick_look"].smoke), "flame 0 smokes")
	for a in s.armies:
		if a.owner == CROWN and armies.armies.has(a.id):
			assert_true(armies.armies[a.id].get("wick") == null, "the Crown's army has no wicks")
			assert_false(armies.armies[a.id].has("flame"))
	b.map.free()
