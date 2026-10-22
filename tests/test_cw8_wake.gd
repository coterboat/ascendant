extends "res://tests/test_case.gd"
## CW-8 (#259, design/CANDLEWAKE.md §3.5): the Wake on the 3D board, the land half. The ground's pale-wax tint grows with the mark's
## stage and spreads from the roads and buildings (the reach mask); the buildings melt in step and drip on the top rungs; a lilac flame
## burns in every window from Sitting Up and candle-posts line the roads from the Wake-Line; a cold wake is greyer, unlit and fading,
## and keeps its melt. The quality ladder thins it (low: tint and windows; medium: posts and melt; high: drips and flicker). A
## Crown–Clans game draws none of it.

const WakeLook := preload("res://world3d/wake_look.gd")
const WakeLights := preload("res://world3d/wake_lights.gd")
const Vision := preload("res://world3d/vision.gd")
const Armies := preload("res://world3d/armies.gd")
const WorldView := preload("res://world3d/world_view.gd")
const Terrain3D := preload("res://world3d/terrain3d.gd")
const CROWN := "kingdom"
const CLANS := "beasts"
const WAKE := "candlewake"
const BOARD_SIZE := Vector2(1280, 720)


func _board_for(state: GameState) -> Board3D:
	var map := load("res://ui/map_screen.tscn").instantiate() as MapScreen
	map.set_state(state, state.factions[0].id)
	var b := Board3D.new()
	map.set_board(b)
	b.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	b.size = BOARD_SIZE
	b.build_now()
	return b


func _wake_game() -> GameState:
	var errors := []
	var s := GameState.create(23, [CROWN, WAKE], {}, {}, errors)
	assert_eq(errors, [])
	s.current_turn = 9
	return s


## Marks `pid` for the Candlewake at stage `n` as the land looks now (MarkRules.stage_now), from the stage's own threshold.
func _mark(s: GameState, pid: String, n: int) -> void:
	s.find_province(pid).owner = WAKE
	s.marks[pid] = {"mark": {"faction": WAKE, "since_turn": s.current_turn - MarkRules.threshold(s, WAKE, n)}}


## A cold wake at `pid` of stage `n`, made at the last wake step (E - 1, as the land looks now; §3.3: it lasts scar_turns a stage).
func _scar(s: GameState, pid: String, n: int) -> void:
	s.find_province(pid).owner = CROWN
	var e := MarkRules.end_clock(s) - 1
	s.marks[pid] = {"scar": {"faction": WAKE, "stage": n, "until_turn": e + int(MarkData.row(WAKE).scar_turns) * n}}


## The villages', landmarks' and cottages' materials.
func _village_mats(wv) -> Array:
	return wv.buildings.get_children().filter(func(c): return c is MultiMeshInstance3D and (String(c.name).begins_with("Village_")
		or String(c.name).begins_with("Cottages"))).map(func(c): return c.material_override)


# --- the look, pure ------------------------------------------------------------------------------------------------

func test_each_stage_shows_deeper_on_the_land() -> void:
	var s := _wake_game()
	var cap := s.find_faction(WAKE).capital
	var near: Array = s.find_province(cap).neighbors.duplicate()
	near.sort()
	var stages := MarkData.stage_count(WAKE)
	for n in range(1, stages + 1):
		_mark(s, String(near[n - 1]), n)
	var look := WakeLook.of(s)
	var line := MarkData.stage_index(WAKE, "wake_line")
	var last := {"tint": 0.0, "reach": 0.0, "melt": 0.0}
	for n in range(1, stages + 1):
		var pid := String(near[n - 1])
		var w: Dictionary = look[pid]
		assert_eq(int(w.stage), MarkRules.stage_now(s, pid), "%s shows the stage the card shows" % pid)
		assert_eq(int(w.stage), n)
		assert_false(bool(w.scar))
		assert_true(bool(w.lit), "a flame in every window from %s" % MarkData.stage(WAKE, 1).name)
		assert_eq(bool(w.posts), n >= line, "candle-posts from %s on" % MarkData.stage(WAKE, line).name)
		for k in last:
			assert_true(float(w[k]) > float(last[k]), "%s grows with the stage (%d: %s)" % [k, n, w])
			last[k] = float(w[k])
	assert_eq(int(look[cap].stage), stages, "the capital stands in the last stage from the start")
	assert_eq(float(look[cap].melt), 1.0, "and is melted all the way")
	var bare: Array = s.provinces.filter(func(p): return not s.marks.has(p.id))
	assert_true(not bare.is_empty() and not look.has(bare[0].id), "an unmarked province shows nothing")


func test_a_cold_wake_is_unlit_keeps_its_melt_and_fades_back() -> void:
	var s := _wake_game()
	var cap := s.find_faction(WAKE).capital
	var pid := String(s.find_province(cap).neighbors[0])
	var n := MarkData.stage_count(WAKE)
	_scar(s, pid, n)
	var turns := int(MarkData.row(WAKE).scar_turns) * n
	var was := {"tint": INF, "reach": INF}
	for k in turns: ## every turn it stands, until the wake step that removes it (§3.3)
		if k > 0:
			s.current_turn += 1
		var w: Dictionary = WakeLook.of(s)[pid]
		assert_true(bool(w.scar), "a cold wake")
		assert_false(bool(w.lit), "unlit")
		assert_false(bool(w.posts), "no candle-posts")
		assert_eq(float(w.melt), float(WakeLook.MELT[n]), "its buildings keep the melt the mark had")
		assert_true(float(w.tint) > 0.0 and float(w.tint) <= float(WakeLook.TINT[n]), "a cold wake's tint, no stronger than the mark's")
		for key in was:
			assert_true(float(w[key]) < float(was[key]), "the %s fades back turn by turn (turn %d: %s)" % [key, k, w])
			was[key] = float(w[key])


func test_the_ground_and_the_buildings_read_one_texture() -> void:
	var s := _wake_game()
	var cap := s.find_faction(WAKE).capital
	var near: Array = s.find_province(cap).neighbors.duplicate()
	near.sort()
	_mark(s, String(near[0]), 1)
	_scar(s, String(near[1]), 2)
	var look := WakeLook.of(s)
	var ids: Array = s.provinces.map(func(p): return p.id)
	var bytes := WakeLook.texels(look, ids, Vision.WIDTH)
	assert_eq(bytes.size(), Vision.WIDTH * 4)
	for i in ids.size():
		var w: Dictionary = look.get(ids[i], {})
		var px := bytes.slice(i * 4, i * 4 + 4)
		if w.is_empty():
			assert_eq(px, PackedByteArray([0, 0, 0, 0]), "%s has no Wake" % ids[i])
			continue
		var tint := roundi(float(w.tint) * 255.0)
		assert_eq(int(px[0]), 0 if bool(w.scar) else tint, "r: a live Wake's tint (%s)" % ids[i])
		assert_eq(int(px[1]), tint if bool(w.scar) else 0, "g: a cold wake's (%s)" % ids[i])
		assert_eq(int(px[2]), roundi(float(w.melt) * 255.0), "b: the melt (%s)" % ids[i])
		assert_eq(int(px[3]), roundi(float(w.reach) * 255.0), "a: the reach (%s)" % ids[i])


func test_the_quality_ladder_thins_the_wake() -> void:
	var low := WakeLook.ladder(WakeLook.MEDIUM_RUNG + 1)
	for k in ["melt", "posts", "drips", "sway"]:
		assert_false(bool(low[k]), "the low rung keeps only the tint and the window flames, not %s" % k)
	var mid := WakeLook.ladder(WakeLook.MEDIUM_RUNG)
	assert_true(bool(mid.melt) and bool(mid.posts), "medium adds the posts and the melt")
	assert_false(bool(mid.drips) or bool(mid.sway), "but not the drips or the flicker")
	var high := WakeLook.ladder(WakeLook.HIGH_RUNG)
	for k in ["melt", "posts", "drips", "sway"]:
		assert_true(bool(high[k]), "high draws %s" % k)
	var still := WakeLook.ladder(0, true)
	assert_true(bool(still.drips) and not bool(still.sway), "reduced motion stills the flames and keeps the drips")


# --- on the board ----------------------------------------------------------------------------------------------------

func test_the_wake_on_the_board() -> void:
	var s := _wake_game()
	var cap := s.find_faction(WAKE).capital
	var b := _board_for(s)
	var wv = b.wv
	var t = wv.terrain
	## a Sitting Up province, one on the Wake-Line and a cold wake, each with a building on it
	var built: Array = t.ids.filter(func(id): return not t.is_capital[t.index_of(id)] and not wv.wake_buildings(String(id)).is_empty())
	assert_true(built.size() >= 3, "provinces with buildings: %s" % [built])
	var line := MarkData.stage_index(WAKE, "wake_line")
	_mark(s, String(built[0]), 1)
	_mark(s, String(built[1]), line)
	_scar(s, String(built[2]), MarkData.stage_count(WAKE))
	var look := WakeLook.of(s)
	b.set_quality_rung(0)
	wv.set_wake(look)
	assert_eq(wv.wake_bytes(), WakeLook.texels(look, t.ids, Vision.WIDTH), "the ground reads the look")
	var lights = wv.wake_lights
	assert_true(lights != null, "the Wake's lights are made with the first Wake")
	var windows := 0
	for pid in look:
		if bool(look[pid].lit):
			for bld in wv.wake_buildings(String(pid)):
				var wide: float = maxf(bld["mesh"].get_aabb().size.x, bld["mesh"].get_aabb().size.z) * (bld["xf"] as Transform3D).basis.get_scale().y
				windows += WakeLights.windows_of(bld["mesh"], 3 if wide > WakeLights.BIG else 1).size()
	assert_eq(int(lights.counts.windows), windows, "a flame in every window of every lit province, none on the cold wake")
	var fortress_mesh: Mesh = wv.fortresses[cap]["node"].get_child(0).mesh
	assert_true(WakeLights.windows_of(fortress_mesh, 3).size() > 4, "the fortress has windows all along its walls")
	for st in WorldView.wake_seats(t):
		for p in lights._posts.multimesh.instance_count:
			var at: Vector3 = lights._posts.multimesh.get_instance_transform(p).origin
			assert_true(Vector2(at.x, at.z).distance_to(st[0]) > float(st[1]), "no candle-post stands inside a building: %s" % at)
	assert_true(WakeLights.windows_of(wv.wake_buildings(String(built[2]))[0]["mesh"]).size() > 0, "the cold wake has windows to leave dark")
	assert_true(int(lights.counts.posts) > 0, "candle-posts along the Wake-Line's and Deep Wake's roads")
	var drawn: MultiMesh = lights._flames.multimesh
	wv.set_wake(look.duplicate(true))
	assert_true(lights._flames.multimesh == drawn, "a repaint with nothing changed draws nothing again")
	## the fortress: its own model has windows; its banners and any palisade never do, and a banner never melts on its own
	var fortress: Node3D = wv.fortresses[cap]["node"]
	var own: Array = wv.wake_buildings(cap).map(func(bld): return bld["mesh"])
	var staffs := 0
	var stack: Array = [fortress]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is MeshInstance3D and (n as MeshInstance3D).material_override is ShaderMaterial and not n.has_meta("wake"):
			staffs += 1
			assert_false(own.has((n as MeshInstance3D).mesh), "%s is no building with windows" % n.name)
			var melts = (n as MeshInstance3D).material_override.get_shader_parameter("prop_melts")
			assert_true(melts == null or float(melts) == 0.0, "%s doesn't melt on its own" % n.name)
	assert_true(staffs >= 2, "the gate towers' banners stand on the fortress")
	assert_true(own.has(wv.fortresses[cap]["node"].get_child(0).mesh), "the fortress's own model has windows")
	var banners: Array = fortress.get_children().filter(func(ch): return ch.has_meta("wake_y"))
	assert_eq(banners.size(), 2)
	for bn in banners:
		assert_true(absf(bn.position.y - float(bn.get_meta("wake_y")) * (1.0 - float(look[cap].melt) * 0.22)) < 0.001,
			"a banner comes down with its melting tower")
	lights.sync(wv, {String(built[0]): look[built[0]]}, WakeLook.ladder(0))
	assert_eq(int(lights.counts.posts), 0, "none for a province only Sitting Up")
	assert_true(int(lights.counts.windows) > 0, "though its windows burn")
	wv.set_wake({})
	wv.set_wake(look)
	## the melt: every village's and cottage's material and its own ink, a fort's and the fortress's; never the shared outline
	var mats: Array = _village_mats(wv) + [wv.fortresses[cap].mat]
	assert_true(mats.size() > 1)
	for m in mats:
		assert_eq(float(m.get_shader_parameter("prop_melts")), 1.0, "a building melts in the Wake")
		assert_eq(float(m.get_shader_parameter("prop_drips")), 1.0, "and drips on the top rung")
		var ink = wv._own_outline.get(m)
		assert_true(ink != null and ink != wv.outline_mat, "with its own ink")
		assert_eq(float(ink.get_shader_parameter("prop_melts")), 1.0, "which melts with it")
		assert_true(m.get_shader_parameter("melt_pivot") is Vector3 and float(m.get_shader_parameter("melt_h")) > 0.0, "about its own base")
	var shared = wv.outline_mat.get_shader_parameter("prop_melts")
	assert_true(shared == null or float(shared) == 0.0, "the outline every model shares never melts")
	b.set_quality_rung(WakeLook.MEDIUM_RUNG)
	assert_eq(float(mats[0].get_shader_parameter("prop_melts")), 1.0, "medium keeps the melt")
	assert_eq(float(mats[0].get_shader_parameter("prop_drips")), 0.0, "without the drips")
	var lit_windows := int(lights.counts.windows)
	b.set_quality_rung(WakeLook.MEDIUM_RUNG + 1)
	for m in mats:
		assert_eq(float(m.get_shader_parameter("prop_melts")), 0.0, "the low rung draws no melt")
	assert_eq(int(lights.counts.posts), 0, "nor posts")
	assert_eq(int(lights.counts.windows), lit_windows, "and keeps the window flames")
	for bn in banners:
		assert_eq(bn.position.y, float(bn.get_meta("wake_y")), "and the banners stand where they were")
	assert_true(float(Armies.wick_material().get_shader_parameter("min_px")) > 0.0, "far out the army's flames grow to be seen")
	b.map.free()


func test_the_windows_are_on_the_walls_and_the_wax_spreads_from_the_roads() -> void:
	var b := _board_for(_wake_game())
	var wv = b.wv
	var t = wv.terrain
	var meshes := {}
	for pid in t.ids:
		for bld in wv.wake_buildings(String(pid)):
			meshes[(bld["mesh"] as Mesh).get_instance_id()] = bld["mesh"]
	assert_true(meshes.size() >= 3, "villages, landmarks and the fortress")
	for key in meshes:
		var mesh: Mesh = meshes[key]
		var box := mesh.get_aabb()
		var spots := WakeLights.windows_of(mesh)
		assert_true(spots.size() >= 2 and spots.size() <= 4, "a window on each side it has walls: %s" % [spots])
		assert_eq(WakeLights.windows_of(mesh), spots, "the same every time")
		assert_true(WakeLights.windows_of(mesh, 3).size() <= 12, "three at most a side on a big one")
		for p in spots:
			assert_true(box.grow(maxf(box.size.x, box.size.z) * 0.1).has_point(p), "%s is on the building %s" % [p, box])
			assert_true(absf((p as Vector3).y - (box.position.y + box.size.y * WakeLights.WINDOW_AT)) < 0.001, "at window height")
	## the reach mask: none out at sea, nothing at the foot of a building or on a road
	var img: Image = WorldView.wake_reach_of(t)
	assert_true(img == WorldView.wake_reach_of(t), "worked out once per land")
	assert_eq(img.get_format(), Image.FORMAT_R8)
	var step: float = float(t.cell) * 2.0
	var at := func(p: Vector2) -> float:
		var x := clampi(int((p.x - Terrain3D.ORIGIN.x) / step), 0, img.get_width() - 1)
		var y := clampi(int((p.y - Terrain3D.ORIGIN.y) / step), 0, img.get_height() - 1)
		return img.get_pixel(x, y).r * WakeLook.REACH_MAX
	assert_eq(at.call(Terrain3D.ORIGIN), WakeLook.REACH_MAX, "the open sea is out of reach")
	for v in WorldView.plan_of(t)["villages"]:
		assert_true(float(at.call(v["pos"])) < step, "a village's foot is in reach at once: %s" % v["pos"])
	for road in t.roads:
		var mid: Vector2 = ((road.pts[0] as Vector2) + (road.pts[1] as Vector2)) * 0.5
		assert_true(float(at.call(mid)) < step, "so is its road: %s" % mid)
	b.map.free()


func test_the_codex_says_how_to_read_the_wake_on_the_land() -> void:
	var text := RulesCodex.text(MarkRules.CODEX)
	for words in ["pale with wax", "every window", "candle-posts", MarkData.stage(WAKE, MarkData.stage_index(WAKE, "wake_line")).name, "melt", "greyer and unlit"]:
		assert_true(text.contains(words), "the Wake's page says %s" % words)


func test_the_long_vigil_has_its_page() -> void:
	var row := FactionData.row(WAKE)
	var e := RulesCodex.entry("long_vigil")
	assert_eq(String(e.get("faction", "")), WAKE, "a Candlewake page")
	assert_eq(String(e.get("title", "")).to_lower(), String(row.capital_name).to_lower(), "named as the capital is on the map")
	var text := RulesCodex.text("long_vigil")
	var deep := MarkData.stage(WAKE, MarkData.stage_count(WAKE))
	assert_true(text.contains(String(deep.name)) and text.contains("harbour"), "it stands in %s from the start, a harbour" % deep.name)
	assert_true(text.contains("every %d turns" % int(MarkData.row(WAKE).risen.every)), "the dead rise there: %s" % text)
	assert_true(text.contains("cold wake that lasts %d turns for every stage" % int(MarkData.row(WAKE).scar_turns)), "and it cools if it falls")
	assert_true(RulesCodex.text(MarkRules.CODEX).contains(String(row.capital_name)), "the Wake's page names it, so it links there")
	assert_true(RulesCodex.shown_for("long_vigil", [CROWN, WAKE]) and not RulesCodex.shown_for("long_vigil", [CROWN, CLANS]),
		"shown only where the Candlewake play")


func test_a_crown_clans_game_draws_no_wake() -> void:
	var errors := []
	var s := GameState.create(23, [CROWN, CLANS], {}, {}, errors)
	assert_eq(errors, [])
	assert_eq(WakeLook.of(s), {}, "no marks, no Wake")
	var b := _board_for(s)
	var wv = b.wv
	var blank := PackedByteArray()
	blank.resize(Vision.WIDTH * 4)
	assert_eq(wv.wake_bytes(), blank, "the ground's Wake texture is blank")
	assert_true(wv.wake_lights == null, "no lights made")
	assert_true(wv.wake_reach_tex == null, "no reach mask worked out")
	var on = wv.gmat.get_shader_parameter("wake_on")
	assert_true(on == null or float(on) == 0.0, "and the ground never reads the Wake")
	for m in _village_mats(wv):
		var melts = m.get_shader_parameter("prop_melts")
		assert_true(melts == null or float(melts) == 0.0, "no building melts")
	b.map.free()
