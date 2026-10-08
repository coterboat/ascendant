extends "res://tests/test_case.gd"
## IND-2 (#161): the Free Holds' look. The kit (world3d/kit.gd) has the independents' "style": a figure for each garrison
## unit type and the Hold Captain, picked by unit id, in the Free Holds' bone-and-grey (never the Crown's blue and gold or
## the Clans' tawny, moss and crimson); the model table (world3d/models.json) has a row for each, which swaps the
## placeholder for the Ludo model the moment its GLB is installed; a garrison stands on the 3D board and fights on the
## 3D battle stage in that look, under the independents' heater-shield banner; the portraits are looked up by unit id; and
## the Ludo batch that makes the models keeps to its credit cap. Expected values come from IndependentData (the unit ids)
## and the kit's own constants, never from pinned numbers.

const Models := preload("res://world3d/models.gd")
const Kit := preload("res://world3d/kit.gd")
const Figures := preload("res://world3d/battle_figures.gd")
const BOARD_SIZE := Vector2(1200, 836)
const HOLDS := IndependentData.FACTION_ID
const BATCH_MANIFEST := "res://tools/ludo/batches/asc-3d-free-holds.json"
const BATCH_LEDGER := "res://studio/ledgers/asc-3d-free-holds.jsonl"
const CREDIT_CAP := 120.0


## Every unit type id the Free Holds field: the three garrison types and the Hold Captain.
func _ids() -> Array:
	var out: Array = []
	for u in IndependentData.UNIT_TYPES:
		out.append(String(u.id))
	out.append(String(IndependentData.COMMANDER.id))
	return out


func _vertex_colours(m: Mesh) -> PackedColorArray:
	return (m.surface_get_arrays(0)[Mesh.ARRAY_COLOR]) as PackedColorArray


## True when every opaque vertex colour of a model figure (the base is a team part, alpha 0) is `want` grey, to the
## mesh's 8-bit colour precision.
func _model_tint_of(m: Mesh, want: float) -> bool:
	var seen := 0
	for c in _vertex_colours(m):
		if c.a < 0.5:
			continue
		seen += 1
		if absf(c.r - want) > 0.01 or absf(c.g - want) > 0.01 or absf(c.b - want) > 0.01:
			return false
	return seen > 0


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


func _independents_game(game_seed: int = 11) -> GameState:
	var s := GameState.new(game_seed)
	var errors := []
	assert_true(s.setup_independents(errors), "independents set up: %s" % [errors])
	return s


# --- the kit picks the independents' figures by unit id ---------------------------------------------

func test_the_kit_has_a_figure_for_every_garrison_unit_by_id() -> void:
	var ids := _ids()
	assert_eq(Array(Kit.INDEPENDENTS), ids, "the kit's independents' figures are the data's garrison units and the Hold Captain")
	var generic: Mesh = Kit.figure("a_unit_nobody_has_heard_of")
	for id in ids:
		assert_true(Kit.has_figure(id), "%s has its own figure" % id)
		var m: Mesh = Kit.figure(id)
		assert_true(m != null and m.get_surface_count() == 1, "%s draws one surface" % id)
		assert_ne(m.get_aabb().size, generic.get_aabb().size, "%s is no copy of the generic figure" % id)
		assert_true(m.get_aabb().size.y > Kit.FIG * 0.8, "%s stands about a man tall (%.2f)" % [id, m.get_aabb().size.y])
	var seen := {}
	for id in ids:
		var key := str((Kit.figure(id) as Mesh).get_aabb()) + str((Kit.figure(id) as Mesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size())
		assert_false(seen.has(key), "%s is told apart from the other garrison figures" % id)
		seen[key] = true
	assert_true(Kit.has_figure(Kit.INDEPENDENTS_PARTY), "the colour party has an independents' figure too")


func test_the_free_holds_wear_bone_and_grey_never_the_crowns_or_the_clans_colours() -> void:
	## the signature colours of the other two peoples (kit.gd's faction palettes; leather and wood browns are shared kit material)
	var others: Array = [Kit.ROYAL, Kit.GOLD, Kit.ROOF, Kit.MOSS, Kit.CRIMSON, Kit.FUR]
	var parts: Array = _ids()
	parts.append(Kit.INDEPENDENTS_PARTY)
	for id in parts:
		var cols := _vertex_colours(Kit.figure(id))
		assert_true(cols.size() > 0, "%s carries vertex colours" % id)
		var light := false
		var dark := false
		for c in cols:
			if c.a < 0.5:
				continue ## a team part (the base): the player's colour, never baked in
			var srgb: Color = c.linear_to_srgb()
			for o in others:
				var d := absf(srgb.r - o.r) + absf(srgb.g - o.g) + absf(srgb.b - o.b)
				assert_true(d > 0.12, "%s has no part in a colour of the Crown or the Clans (%s is %.2f from %s)" % [id, srgb.to_html(false), d, (o as Color).to_html(false)])
			var l: float = srgb.get_luminance()
			light = light or l > 0.45
			dark = dark or l < 0.35
		assert_true(light and dark, "%s has a light area and a dark one, so it reads in greyscale (bible 2.5)" % id)
	## the armies' base is the independents' slate on a garrison (the owner colour), as the 2D map's neutral
	assert_eq(UiPalette.seat_color(-1), UiPalette.NEUTRAL, "nobody is slate")


func test_the_war_camp_tent_has_the_independents_style_too() -> void:
	var crown: Mesh = Kit.tent("kingdom")
	var holds: Mesh = Kit.tent(HOLDS)
	assert_true(holds.surface_get_arrays(0)[Mesh.ARRAY_COLOR] != crown.surface_get_arrays(0)[Mesh.ARRAY_COLOR], "the Free Holds' tent is no Crown tent")
	for c in _vertex_colours(holds):
		var srgb: Color = c.linear_to_srgb()
		assert_true(absf(srgb.r - Kit.ROYAL.r) + absf(srgb.g - Kit.ROYAL.g) + absf(srgb.b - Kit.ROYAL.b) > 0.12 or c.a < 0.5, "no royal blue in the Free Holds' tent")


# --- the model table -----------------------------------------------------------------------------------

func test_every_garrison_unit_has_a_model_row_that_draws_and_a_placeholder_until_its_model_is_installed() -> void:
	assert_eq(Models.problems(), [], "the model table's rows are all sound")
	for id in _ids():
		var row := Models.figure_row(id)
		assert_false(row.is_empty(), "%s has a row in world3d/models.json" % id)
		assert_eq(String(row.get("faction", "")), HOLDS, "%s is the Free Holds'" % id)
		assert_eq(String(row.get("fallback", "")), id, "%s falls back to its own kit figure" % id)
		var fm: Dictionary = Models.figure_mesh(id)
		assert_true(fm.get("mesh") is Mesh, "%s draws a mesh (%s)" % [id, fm.get("source", "?")])
		var path := String(row.get("model", ""))
		assert_eq(String(fm.get("source", "")), "model" if (not path.is_empty() and ResourceLoader.exists(path)) else "primitive",
			"%s stands as its installed model, or as the kit's placeholder until then" % id)
	var holds := IndependentData.faction()
	assert_eq(Models.rank_of(String(holds.commander_type.id)), 2, "the Hold Captain stands at the back with the colours")
	for ut in holds.unit_types:
		assert_true(Models.rank_of(String(ut.id)) < 2, "%s stands in a rank of the line" % ut.id)


func test_an_installed_model_swaps_the_placeholder_in_by_the_models_row() -> void:
	## what `asc_3d_free_holds.py install-accepted` does to world3d/models.json: a model, a height, a pose list
	var keep: Dictionary = Models.table().duplicate(true)
	var probe := "res://assets/models/probe/spearman.glb"
	var other := "res://assets/models/probe/tusker.glb"
	assert_true(ResourceLoader.exists(probe) and ResourceLoader.exists(other), "the probe models are in the repo")
	var table := keep.duplicate(true)
	var id := "free_spears"
	var row: Dictionary = table["figures"][id]
	var before := Models.figure_mesh(id)
	row["model"] = probe
	row["height"] = 1.0
	row["poses"] = {"ready": probe, "march": other}
	row["pose_size"] = {"march": {"axis": "height", "men": 1.0}}
	row["tint"] = 0.5
	table["figures"]["bearer"]["models"][HOLDS] = probe
	table["figures"]["bearer"]["model_tint"] = {HOLDS: 0.25}
	Models.clear_cache()
	Models._table = table
	var ready: Dictionary = Models.figure_mesh(id)
	var march: Dictionary = Models.figure_mesh(id, true, "march")
	assert_eq(ready["source"], "model", "the accepted ready model replaces the placeholder")
	assert_ne(ready["mesh"], before["mesh"], "with its own mesh")
	assert_eq(march["pose"], "march", "and its march pose draws its own model")
	assert_eq(Models.problems(), [], "the swapped row is sound")
	assert_true(_model_tint_of(ready["mesh"], 0.5), "a row's tint darkens its model (the pale wool must not blow out)")
	var bearer: Dictionary = Models.figure_mesh("bearer", true, "ready", HOLDS)
	assert_eq(bearer["source"], "model", "the colour party can wear an installed model of the Free Holds")
	assert_true(_model_tint_of(bearer["mesh"], 0.25), "with its own tint for that faction")
	assert_true(_model_tint_of(Models.figure_mesh("bearer", true, "ready", "kingdom")["mesh"], 1.0), "and the other peoples' bearers are as made")
	Models.clear_cache()
	assert_eq(Models.figure_mesh(id)["source"], before["source"], "put back, the table gives the same figure again")


func test_the_colour_party_of_a_garrison_stands_in_the_free_holds_kit() -> void:
	for extra in ["bearer", "musician"]:
		var holds: Dictionary = Models.figure_mesh(extra, true, "ready", HOLDS)
		var crown: Dictionary = Models.figure_mesh(extra, true, "ready", "kingdom")
		assert_true(holds["mesh"] is Mesh, "the %s draws for the Free Holds" % extra)
		assert_ne(holds["mesh"], crown["mesh"], "and is no Crown figure")
		assert_eq(holds["mesh"], Models.figure_mesh(extra, true, "march", HOLDS)["mesh"], "every pose of the Free Holds' %s is the same figure" % extra)
		var royal := false
		for c in _vertex_colours(holds["mesh"]):
			var s: Color = c.linear_to_srgb()
			royal = royal or (c.a > 0.5 and absf(s.r - Kit.ROYAL.r) + absf(s.g - Kit.ROYAL.g) + absf(s.b - Kit.ROYAL.b) < 0.12)
		assert_false(royal, "no royal blue plume on the Free Holds' %s" % extra)
	assert_ne(Models.figure_mesh("bearer", true, "ready")["mesh"], Models.figure_mesh("bearer", true, "ready", HOLDS)["mesh"], "other armies keep their own bearer")


# --- the 3D board --------------------------------------------------------------------------------------

func test_a_garrison_stands_on_the_board_in_its_own_look_under_the_shield_banner() -> void:
	var s := _independents_game()
	var b := _board_for(s)
	var garrisons := 0
	for a in s.armies:
		if a.owner != HOLDS:
			continue
		garrisons += 1
		var e: Dictionary = b.armies.armies[a.id]
		assert_eq(e["owner"], HOLDS)
		assert_eq(e["colour"], UiPalette.NEUTRAL, "%s stands on slate bases" % a.id)
		assert_eq(e["emblem"], Kit.EMBLEM_SHIELD, "%s flies the independents' heater shield, not a player's circle" % a.id)
		assert_true(e["banner"] != null, "%s carries its banner" % a.id)
		var want := {}
		for u in a.units:
			want[String(u.type.id)] = true
		if a.commander != null:
			want[String(a.commander.type.id)] = true
		var shown := {}
		for f in e["figs"]:
			shown[String(f["type"])] = true
		for t in want:
			assert_true(shown.has(t), "%s: a %s stands in it" % [a.id, t])
		for t in shown:
			assert_true(want.has(t) or t == "bearer" or t == "musician", "%s: only its own units and the colour party stand in it (%s)" % [a.id, t])
	assert_true(garrisons > 0, "the game has garrisons")
	assert_true(b.armies.armies.size() >= garrisons)
	_free_board(b)


func test_the_players_armies_keep_their_numbered_emblems() -> void:
	var s := _independents_game()
	var b := _board_for(s)
	for a in s.armies:
		if a.owner == HOLDS:
			continue
		var seat := UiPalette.seat_index(s, a.owner, b.armies.seats)
		assert_true(seat >= 0, "%s's army has a seat" % a.owner)
		assert_eq(b.armies.armies[a.id]["emblem"], seat, "a player's banner keeps the emblem of its seat")
	_free_board(b)


# --- the 3D battle stage -------------------------------------------------------------------------------

func _garrison_battle() -> Dictionary:
	var s := _independents_game()
	var army: Army = null
	for a in s.armies:
		if a.owner == "kingdom":
			army = a
	var res: Dictionary = TurnResolver.resolve(s, {"kingdom": [MoveOrder.new(army.id, "westwatch")]}, 5)
	for e in res.events:
		if e.type == "battle" and (e.numbers as Dictionary).has("log"):
			return e
	return {}


func test_a_garrison_battle_plays_on_the_3d_stage_with_the_garrisons_figures_and_banner() -> void:
	var event := _garrison_battle()
	assert_false(event.is_empty(), "a Crown attack on a garrison fights a battle")
	var stage := BattleStage3D.new()
	assert_eq(stage.show_event(event, ["kingdom", "beasts"]), "", "the battle plays on the stage")
	var log: Dictionary = event.numbers.log
	var holds_side := -1
	for si in log.sides.size():
		if String(log.sides[si].faction) == HOLDS:
			holds_side = si
	assert_ne(holds_side, -1, "the Free Holds are a side of the battle")
	stage.build_now()
	var types := {}
	for i in stage.figures.n_fighters:
		var f: Dictionary = stage.figures.figs[i]
		if int(f["side"]) == holds_side:
			types[String(f["type"])] = true
	assert_false(types.is_empty(), "the garrison's figures stand on the stage")
	var own: Array = _ids()
	for t in types:
		assert_true(own.has(t), "a Free Holds figure on the stage is one of their own (%s)" % t)
		assert_false(Models.figure_row(String(t)).is_empty(), "%s has its row" % t)
	assert_eq(stage.figures.banners.size(), log.sides.size(), "each side carries its banner")
	assert_eq(stage._side_seat[holds_side], -1, "the garrison's side has no seat: its banner takes the independents' shield")
	stage.free()


# --- portraits ------------------------------------------------------------------------------------------

func test_portraits_are_found_by_unit_id_under_the_independents() -> void:
	for id in _ids():
		assert_eq(Art.unit_faction(id), HOLDS, "%s belongs to the Free Holds for the art lookup" % id)
		var path: String = Art.PORTRAIT_PATH % [HOLDS, id]
		assert_eq(path, "res://assets/portraits/independents/%s.webp" % id)
		assert_eq(Art.portrait(id) != null, ResourceLoader.exists(path), "%s: a portrait when its file is installed, none before" % id)
	assert_eq(Art.unit_faction("spearmen"), "kingdom", "the other peoples' lookup is untouched")


# --- the Ludo batch ------------------------------------------------------------------------------------

func test_the_ludo_batch_covers_every_garrison_unit_and_keeps_to_its_cap() -> void:
	var f := FileAccess.open(BATCH_MANIFEST, FileAccess.READ)
	assert_true(f != null, "the batch manifest is committed")
	var man: Dictionary = JSON.parse_string(f.get_as_text())
	var models := {}
	var negatives := RegEx.create_from_string("(?i)\\b(no|not|without|never|negative)\\b")
	for a in man.assets:
		if a.has("prompt"):
			assert_true(negatives.search(String(a.prompt)) == null, "%s: a prompt is phrased positively (bible 3, rule 1)" % a.id)
		if a.kind == "model3d":
			assert_true(String(a.target).begins_with("assets/models/units/%s/" % HOLDS), "%s installs under the independents' models" % a.id)
			models["%s_%s" % [a.unit, a.pose]] = true
	for id in _ids():
		for pose in Models.POSES.slice(0, 4):
			assert_true(models.has("%s_%s" % [id, pose]), "the batch makes %s's %s model" % [id, pose])
	assert_true(float(man.cap) <= CREDIT_CAP and float(man.job_cap) <= CREDIT_CAP, "the batch's stop line is under the issue's cap")
	var spent := 0.0
	var lf := FileAccess.open(BATCH_LEDGER, FileAccess.READ)
	assert_true(lf != null, "every charged call is in the batch's ledger")
	if lf != null:
		while not lf.eof_reached():
			var line := lf.get_line().strip_edges()
			if not line.is_empty():
				spent += float(JSON.parse_string(line).get("credits_charged", 0.0))
	assert_true(spent <= CREDIT_CAP, "the ledger sums to %.1f credits, within the issue's %.0f" % [spent, CREDIT_CAP])
