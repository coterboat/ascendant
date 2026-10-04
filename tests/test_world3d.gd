extends "res://tests/test_case.gd"
## The 3D world spike's pure parts (world3d/): the land baked from the map, the formations, and the
## real game the preview plays back. Expected numbers come from data/map.gd and world3d/kit.gd.

const Terrain3D := preload("res://world3d/terrain3d.gd")
const Kit := preload("res://world3d/kit.gd")
const Scenario := preload("res://world3d/scenario.gd")

static var _land: RefCounted = null


func _terrain() -> RefCounted:
	if _land == null:
		_land = Terrain3D.build()
	return _land


func _neighbour_pairs() -> Dictionary:
	var pairs := {}
	for p in MapData.PROVINCES:
		for q in p.neighbors:
			pairs[Terrain3D.pair(p.id, q)] = true
	return pairs


func test_land_is_deterministic() -> void:
	var a = _terrain()
	var b = Terrain3D.build()
	assert_eq(a.heights.size(), b.heights.size())
	assert_true(a.heights == b.heights, "same seed, same heights")
	assert_true(a.data_image.get_data() == b.data_image.get_data(), "same seed, same territories")


func test_every_province_stands_on_its_own_land() -> void:
	var t = _terrain()
	for p in MapData.PROVINCES:
		var c: Vector2 = MapLayout.position_of(p.id)
		assert_eq(t.province_at(c), p.id, "%s's centre is in %s" % [p.id, p.id])
		assert_true(t.coast_at(c) > 40.0, "%s's centre is well inland (%.0f)" % [p.id, t.coast_at(c)])


func test_every_neighbour_pair_has_a_crossing_and_a_road() -> void:
	var t = _terrain()
	var pairs := _neighbour_pairs()
	assert_eq(t.roads.size(), pairs.size(), "one road per pair of neighbours")
	for key in pairs.keys():
		var ids: PackedStringArray = (key as String).split("|")
		var x: Variant = t.crossing(ids[0], ids[1])
		assert_true(x != null, "%s has a crossing" % key)
		if x == null:
			continue
		assert_true(t.border_at(x) < 4.0, "%s's crossing is on the border (%.1f away)" % [key, t.border_at(x)])
		assert_true(t.coast_at(x) > 0.0, "%s's crossing is on land" % key)
		assert_true([ids[0], ids[1]].has(t.province_at(x)), "%s's crossing is in one of the two" % key)
		var path: PackedVector2Array = t.road_path(ids[0], ids[1])
		assert_eq(path.size(), 3, "%s's road goes centre, crossing, centre" % key)


func test_walls_stand_only_between_provinces_that_are_not_neighbours() -> void:
	var t = _terrain()
	var pairs := _neighbour_pairs()
	var checked := 0
	for k in range(0, t.heights.size(), 7):
		if t.idx[k] == Terrain3D.SEA or t.border[k] > 1.5 or t.coast[k] < 6.0:
			continue
		var a: String = t.ids[t.idx[k]]
		var b: String = t.ids[t.second[k]]
		var neighbours: bool = pairs.has(Terrain3D.pair(a, b))
		assert_eq(t.wall[k] == 1, not neighbours, "the border %s|%s is a wall only when they are not neighbours" % [a, b])
		checked += 1
	assert_true(checked > 100, "border cells checked: %d" % checked)


func test_walls_rise_into_ridges_and_roads_cross_low() -> void:
	var t = _terrain()
	var wall_h := 0.0
	var wall_n := 0
	for k in t.heights.size():
		if t.wall[k] == 1 and t.border[k] < 1.5 and t.coast[k] > 40.0 and t.road_d[k] > 30.0:
			wall_h += t.heights[k]
			wall_n += 1
	assert_true(wall_n > 0, "there are walls")
	var mean_stage := 0.0
	for v in t.stage_h:
		mean_stage += v
	mean_stage /= t.stage_h.size()
	assert_true(wall_h / wall_n > mean_stage + 10.0, "walls stand above the stages (%.1f vs %.1f)" % [wall_h / wall_n, mean_stage])


func test_land_is_mirror_symmetric() -> void:
	var t = _terrain()
	var twin := {}
	for w in MapLayout.MIRROR.keys():
		twin[w] = MapLayout.MIRROR[w]
		twin[MapLayout.MIRROR[w]] = w
	var n := 0
	var same := 0
	var y := 20.0
	while y < 580.0:
		var x := 10.0
		while x < 480.0:
			var p := Vector2(x, y)
			var q := Vector2(1000.0 - x, y)
			var a: String = t.province_at(p)
			var b: String = t.province_at(q)
			n += 1
			if (a == "" and b == "") or (a != "" and twin.get(a, "") == b):
				same += 1
			x += 13.0
		y += 13.0
	assert_true(float(same) / n > 0.98, "the east half mirrors the west (%d of %d points)" % [same, n])


func test_stages_are_level() -> void:
	var t = _terrain()
	for i in t.ids.size():
		var c: Vector2 = t.centres[i]
		var r: float = t.stage_r[i] * 0.5
		var lo := 1.0e9
		var hi := -1.0e9
		for a in 8:
			var p: Vector2 = c + Vector2(cos(a * TAU / 8.0), sin(a * TAU / 8.0)) * r
			lo = minf(lo, t.height_at(p))
			hi = maxf(hi, t.height_at(p))
		assert_true(hi - lo < 2.0, "%s's stage is level (%.2f)" % [t.ids[i], hi - lo])


func test_formation_has_a_company_per_unit_plus_commander_and_bearer() -> void:
	var state := GameState.new(12345)
	var army: Army = state.armies[0]
	var types: Array = Scenario.unit_types(army)
	var slots: Array = Kit.formation(types, Scenario.commander_type(army), 42.0)
	var want := 2
	for t in types:
		want += int(Kit.FIGS[t][0])
	assert_eq(slots.size(), want, "figures for %s" % str(types))
	var roles := {}
	for s in slots:
		roles[s["role"]] = int(roles.get(s["role"], 0)) + 1
		assert_true(absf((s["pos"] as Vector2).x) < 42.0 * 0.5 + 0.01, "every figure inside the width")
	assert_eq(roles.get("commander", 0), 1)
	assert_eq(roles.get("bearer", 0), 1)


func test_autoplay_is_real_and_deterministic() -> void:
	var a: Array = Scenario.autoplay(4242, 3)
	var b: Array = Scenario.autoplay(4242, 3)
	assert_eq(a.size(), b.size())
	for i in a.size():
		assert_eq(str(Scenario.moves_of(a[i])), str(Scenario.moves_of(b[i])), "turn %d moves" % i)
		var before: GameState = a[i]["before"]
		for m in Scenario.moves_of(a[i]):
			var army := before.find_army(m["army"])
			assert_true(army != null, "a mover existed before the turn")
			if army != null:
				assert_eq(army.location, m["from"], "it moved from where it stood")
	var any_moves := false
	for turn in a:
		if not Scenario.moves_of(turn).is_empty():
			any_moves = true
	assert_true(any_moves, "the AI moved armies in three turns")
