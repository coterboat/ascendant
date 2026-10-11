extends "res://tests/test_case.gd"
## M3c S-5 (#103) acceptance, tests/test_battle_stage_walls.gd: battles at walls on the M3b stage (world3d/battle_walls.gd,
## world3d/battle_scenery.gd, design/M3C_SIEGES.md 10.3), headless. The battles are fought with the real resolver
## (tests/walls_stage_fixtures.gd: a storm at a keep, a palisade and a capital, in both kits, the breach, a sally, a relief,
## a relief with a sally, the gate battle), so their logs carry the real `siege` block.
##   * storm: the garrison on the wall walk (its Volley tier along the front, the commander on the gatehouse), or behind the
##     stakes where there is nothing to stand on; the stormers at the foot, facing the walls, with ladders (Crown) or the trunk
##     (Clans)
##   * breach: the garrison's front rank in the gap, the attackers before it, the breached look on the land
##   * open: both lines before the gate, the side with fighters from inside nearest it, and exactly those march out of it
##   * nobody stands inside a wall (fighters, colour party, tents, engines, ladders), whatever the damage look; the deck the
##     table says is on the model
##   * the walls' defense is on screen before the first hit lands (the caption, the plate, their tooltip)
##   * the stage only shows: the fixtures play to the timeline's final state, the game, the log and the report are unchanged
##     (M3's three levels of "playback never changes the outcome", run on siege battles), and nothing here rolls dice
## Expected values come from the logs, the fixtures' state and the walls specs, never hardcoded.

const WF := preload("res://tests/walls_stage_fixtures.gd")
const Walls := preload("res://world3d/battle_walls.gd")
const Scenery := preload("res://world3d/battle_scenery.gd")
const Formation := preload("res://world3d/battle_formation.gd")
const Cam := preload("res://world3d/battle_camera.gd")
const Figures := preload("res://world3d/battle_figures.gd")
const Models := preload("res://world3d/models.gd")
const WorldKit := preload("res://world3d/kit.gd")
const Fx := preload("res://tests/battle_playback_fixtures.gd")
const STEP := 1.0 / 60.0
const NEW_FILES := ["res://world3d/battle_walls.gd", "res://world3d/battle_scenery.gd"]


func _stage(reduced := false) -> BattleStage3D:
	var s := BattleStage3D.new()
	s.reduced_motion = reduced
	s.dive_from_board = false
	return s


## Plays fixture `name` on `s` the way the host does (play(): with the game's state, as the watcher sees it).
func _open(s: BattleStage3D, name: String, with_state := true) -> Dictionary:
	var fx := WF.battle(name)
	assert_false(fx.is_empty(), "%s: the battle was fought" % name)
	assert_eq(s.play(fx.log, fx.report, fx.state if with_state else null, []), "", "%s plays on the stage" % name)
	return fx


func _kind(name: String) -> String:
	return String(WF.battle(name).log.siege.kind)


func _names_of(kind: String) -> Array:
	return WF.names().filter(func(n): return not WF.battle(n).is_empty() and _kind(n) == kind)


func _info(s: BattleStage3D) -> Dictionary:
	return s.plan.walls.info


## A fighter's place in the fort's own frame (x across, z toward the back, the gate on -z).
func _local(s: BattleStage3D, fid: int) -> Vector2:
	return Walls.to_local(_info(s), s.plan.slots[fid].pos)


func _play_out(s: BattleStage3D, speed: int) -> void:
	s.player.set_speed(speed)
	s.player.play()
	var frames := 0
	while not s.player.is_finished() and frames < 100000:
		s.tick(STEP)
		frames += 1
	for k in 150:
		s.tick(STEP)


# --- the fixtures ----------------------------------------------------------------------------------------------

func test_the_fixtures_are_the_siege_battles_they_say_they_are() -> void:
	var expect := {"storm": "storm", "none": "breach", "sally": "open", "relief": "open", "relief_sally": "open", "gate": "open"}
	var kinds := {}
	for name in WF.names():
		var fx := WF.battle(name)
		assert_false(fx.is_empty(), "%s: the turn made the battle" % name)
		var c: Dictionary = WF.CASES[name]
		var want: String = "storm" if String(c.orders) == "gate" and int(c.index) == 1 else String(expect[String(c.orders)])
		assert_eq(String(fx.log.siege.kind), want, "%s: its kind" % name)
		kinds[want] = true
		assert_eq(BattleLog.validate(fx.log), [], "%s: a valid log" % name)
		assert_eq(BattleLog.verify_draws(fx.log), [], "%s: its draws check out" % name)
		assert_eq(BattleLog.cross_check(fx.log, fx.report), [], "%s: the report agrees" % name)
		assert_eq(int(fx.log.siege.walls_max), SiegeRules.walls_max(Walls.level_of(fx.log.siege)), "%s: the walls' size is the fort's level's" % name)
	assert_eq(kinds.keys().size(), 3, "the fixtures hold a storm, a breach and open battles")


# --- storm -----------------------------------------------------------------------------------------------------

func test_a_storm_puts_the_garrison_on_the_walls_and_the_stormers_at_their_foot() -> void:
	var s := _stage()
	var storms := _names_of("storm")
	assert_true(storms.size() >= 7, "storms at a keep, a palisade and a capital, in both kits (%d)" % storms.size())
	for name in storms:
		var fx := _open(s, name)
		var siege: Dictionary = fx.log.siege
		var plan: Dictionary = s.plan
		var info := _info(s)
		var spec: Dictionary = info.spec
		assert_eq(String(plan.where), "walls", "%s: it stands at the walls" % name)
		assert_eq(int(plan.near), int(siege.garrison), "%s: the garrison is the side at the walls" % name)
		assert_eq(int(plan.far), 1 - int(siege.garrison), "%s: the stormers the other" % name)
		var has_deck: bool = not (spec.decks as Array).is_empty()
		var deck_ys := []
		for d in spec.decks:
			deck_ys.append(float(d[4]))
		for d in spec.sides:
			deck_ys.append(float(d[4]))
		if not (spec.gate_top as Array).is_empty():
			deck_ys.append(float(spec.gate_top[3]))
		var volley := 0
		var volley_up := 0
		for fid in fx.log.sides[int(plan.near)].fighters:
			var f: Dictionary = fx.log.fighters[int(fid)]
			var sl: Dictionary = plan.slots[int(fid)]
			var station := String(sl.station)
			assert_true(["deck", "gate_top", "yard", "reserve"].has(station), "%s: %s stands at a place of the fort (%s)" % [name, f.name, station])
			if not has_deck:
				assert_true(["yard", "reserve"].has(station), "%s: nothing to stand on in this kit: %s stands in the yard" % [name, f.name])
			if ["deck", "gate_top"].has(station):
				var yl := float(sl.y) - float(info.base_y)
				assert_true(deck_ys.any(func(y): return absf(float(y) - yl) < 0.01), "%s: %s stands on a wall walk at its height (%.2f)" % [name, f.name, yl])
				assert_true(float(sl.lift) > 1.0, "%s: and keeps that height when it lunges" % name)
			if f.role == "unit" and int(f.tier) == 1:
				volley += 1
				if ["deck", "gate_top"].has(station):
					volley_up += 1
			if has_deck and f.role == "commander" and not (spec.gate_top as Array).is_empty():
				assert_eq(station, "gate_top", "%s: the commander commands from the gatehouse" % name)
			assert_true(bool(sl.rail), "%s: %s strikes where it stands, with a wall in the way" % [name, f.name])
		if has_deck:
			assert_eq(volley_up, volley, "%s: the Volley tier is along the top of the walls (%d)" % [name, volley])
		## the stormers: at the foot, outside, facing the walls, with the right tools
		var fv: Vector2 = (-(info.front as Vector2)).rotated(deg_to_rad(float(plan.walls.turn)))
		for fid in fx.log.sides[int(plan.far)].fighters:
			var sl2: Dictionary = plan.slots[int(fid)]
			assert_eq(String(sl2.station), "line", "%s: a stormer stands in the open" % name)
			var l := Walls.to_local(info, sl2.pos)
			assert_false(absf(l.x) < float(info.radius) + 1.0 and absf(l.y) < float(info.radius) + 1.0, "%s: a stormer stands off the fort's base (%s)" % [name, str(l)])
			if absf(float(plan.walls.turn)) < 0.01:
				assert_true(l.y < -float(spec.outer), "%s: a stormer stands at the foot of the gate-side wall (z %.1f)" % [name, l.y])
			assert_true(absf(angle_difference(float(sl2.yaw), atan2(-fv.x, -fv.y))) < 0.02, "%s: and faces the walls" % name)
		var scenery: Dictionary = plan.walls.scenery
		var clans := String(fx.log.sides[int(plan.far)].faction) == "beasts"
		assert_eq((scenery.trunk as Dictionary).is_empty(), not clans, "%s: the Clans bring the trunk" % name)
		assert_eq((scenery.ladders as Array).is_empty(), clans, "%s: the Crown brings ladders" % name)
		for lad in scenery.ladders:
			var top: Vector3 = lad.top
			var lt := Walls.to_local(info, Vector2(top.x, top.z))
			assert_true(absf(lt.y - (Walls.face_z(spec, lt.x) + 0.3)) < 0.05, "%s: a ladder leans on the gate-side wall (%s)" % [name, str(lt)])
			assert_true(absf(top.y - Walls.world_y(info, float(spec.floor) + float(spec.wall_h))) < 0.01, "%s: up to its top" % name)
		assert_eq(s.scenery.counts.ladders, (scenery.ladders as Array).size(), "%s: the ladders are drawn" % name)
		assert_eq(s.scenery.counts.trunk, 0 if (scenery.trunk as Dictionary).is_empty() else 1, "%s: so is the trunk" % name)
	s.free()


# --- breach ---------------------------------------------------------------------------------------------------

func test_a_breach_puts_the_garrisons_front_rank_in_the_gap_and_the_attackers_before_it() -> void:
	var s := _stage()
	var breaches := _names_of("breach")
	assert_true(breaches.size() >= 3, "breaches at a keep, a palisade and a capital (%d)" % breaches.size())
	for name in breaches:
		var fx := _open(s, name)
		var siege: Dictionary = fx.log.siege
		var info := _info(s)
		var spec: Dictionary = info.spec
		assert_eq(int(s.plan.near), int(siege.garrison), "%s: the garrison stands in the breach" % name)
		assert_eq(int(siege.walls), 0, "%s: the walls are down" % name)
		assert_eq(String(s.wv.fort_table()[String(fx.log.provinces[0])].look), "breached", "%s: the fort on the land wears its breached look" % name)
		var front_z := INF
		var rank0_z := []
		for fid in fx.log.sides[int(s.plan.near)].fighters:
			var l := _local(s, int(fid))
			var sl: Dictionary = s.plan.slots[int(fid)]
			if String(sl.station) == "yard":
				assert_true(l.y >= float(spec.breach_z), "%s: nobody stands out in front of the breach (z %.1f)" % [name, l.y])
				front_z = minf(front_z, l.y)
			if int(sl.tier) == 0 and String(sl.station) == "yard":
				rank0_z.append(l.y)
		assert_true(front_z < float(spec.breach_z) + 5.5, "%s: the front rank fills the gap (z %.1f at the cut %.1f)" % [name, front_z, float(spec.breach_z)])
		for fid in fx.log.sides[int(s.plan.far)].fighters:
			assert_true(_local(s, int(fid)).y < float(spec.breach_z), "%s: the attackers stand before the gap" % name)
		assert_true(float(s.plan.walls.scenery.trunk.size()) == 0 and (s.plan.walls.scenery.ladders as Array).is_empty(), "%s: no ladders and no trunk at a breach" % name)
	s.free()


# --- open battles -----------------------------------------------------------------------------------------------

func test_open_battles_form_before_the_gate_and_those_from_inside_march_out_of_it() -> void:
	var s := _stage()
	var opens := _names_of("open")
	assert_true(opens.size() >= 6, "a sally, a relief, a relief with a sally and the gate battle in a keep and a capital (%d)" % opens.size())
	for name in opens:
		var fx := _open(s, name)
		var siege: Dictionary = fx.log.siege
		var info := _info(s)
		var spec: Dictionary = info.spec
		var inside_armies: Array = siege.from_inside
		var from_inside := []
		var side_with := -1
		for si in fx.log.sides.size():
			for fid in fx.log.sides[si].fighters:
				if inside_armies.has(String(fx.log.fighters[int(fid)].army)):
					from_inside.append(int(fid))
					side_with = si
		if side_with >= 0:
			assert_eq(int(s.plan.near), side_with, "%s: whoever came out of the gate stands nearest it" % name)
		else:
			assert_eq(int(s.plan.near), 1 - int(siege.garrison), "%s: a relief comes to the besiegers at the walls" % name)
		for f in fx.log.fighters:
			var sl: Dictionary = s.plan.slots[int(f.id)]
			assert_eq(String(sl.station), "line", "%s: both lines stand in the open before the gate" % name)
			assert_true(_local(s, int(f.id)).y < -float(spec.outer), "%s: %s stands out of the gate (z %.1f)" % [name, f.name, _local(s, int(f.id)).y])
		## the march
		var march: Dictionary = s.plan.walls.march
		var arrivals := []
		if ["relief", "relief_sally"].has(String(siege.why)) and int(siege.garrison) != int(s.plan.near):
			for fid in fx.log.sides[int(siege.garrison)].fighters:
				if not from_inside.has(int(fid)):
					arrivals.append(int(fid))
		assert_eq(march.keys().size(), from_inside.size() + arrivals.size(), "%s: exactly the fighters from inside march out, and a relief arrives" % name)
		for fid in arrivals:
			var arrival: Dictionary = march[fid]
			assert_true(bool(arrival.arrives) and float(arrival.s_in) == 0.0, "%s: relief fighter %d arrives on the road" % [name, fid])
			var from_p: Vector2 = arrival.path[0]
			assert_true(from_p.distance_to(info.centre) > (s.plan.slots[fid].pos as Vector2).distance_to(info.centre), "%s: from behind its line, farther from the fort" % name)
			assert_true((arrival.path[-1] as Vector2).is_equal_approx(s.plan.slots[fid].pos), "%s: to its place" % name)
		for fid in from_inside:
			assert_true(march.has(fid), "%s: fighter %d marches" % [name, fid])
			var path: Array = march[fid].path
			var first := Walls.to_local(info, path[0])
			var last: Vector2 = path[-1]
			assert_true(first.y > float((spec.gate_path as Array)[0]) - 0.5 and absf(first.x) < float(spec.gate), "%s: it starts in the yard behind the gate" % name)
			assert_true(last.is_equal_approx(s.plan.slots[fid].pos), "%s: and ends in its place" % name)
			var through := false
			for p in path:
				var lp := Walls.to_local(info, p)
				if absf(lp.x) < float(spec.gate) and lp.y < float((spec.gate_path as Array)[0]) and lp.y > float((spec.gate_path as Array)[1]) - 2.0:
					through = true
			assert_true(through, "%s: through the gate" % name)
			assert_false(Walls.inside_wall(info, path[0], Walls.world_y(info, float(spec.floor))), "%s: the column waits in the yard, not in a wall" % name)
		## and it plays: the deploy beat sets exactly those fighters marching, the others stand or step
		s.player.restart()
		s.player.set_speed(1)
		s.player.play()
		s.tick(0.001)
		for i in s.figures.n_fighters:
			var fid2 := int(s.figures.figs[i].fid)
			var kinds := (s.figures.figs[i].motions as Array).map(func(m): return String(m.kind))
			assert_eq(kinds.has("march_out"), march.has(fid2), "%s: fighter %d marches out of the gate only if it came from inside" % [name, fid2])
		for fid in from_inside.slice(0, 3):
			var i2: int = s.figures.index_of(fid)
			var at0: Dictionary = s.figures.pose_at(i2, 0.0)
			assert_true(Walls.to_local(info, at0.pos).y > float((spec.gate_path as Array)[0]) - 0.5, "%s: it begins inside the gate" % name)
			var at_end: Dictionary = s.figures.pose_at(i2, float(march[fid].dur) + 0.01)
			assert_true((at_end.pos as Vector2).distance_to(s.plan.slots[fid].pos) < 0.01, "%s: and arrives in its place" % name)
		s.player.pause()
	s.free()


# --- nobody stands inside a wall ------------------------------------------------------------------------------------

func test_nobody_stands_inside_a_wall() -> void:
	var s := _stage()
	var looks := {}
	for name in WF.names():
		var fx := _open(s, name)
		var info := _info(s)
		looks[String(info.look)] = true
		var all := []
		for sl in s.plan.slots:
			all.append(sl)
		all.append_array(s.plan.extras)
		for sl in all:
			var inside := Walls.inside_wall(info, sl.pos, float(sl.y))
			if inside:
				print("   ", name, ": inside a wall at ", Walls.to_local(info, sl.pos), " y ", float(sl.y) - float(info.base_y))
			assert_false(inside, "%s: nobody (%s) stands inside a wall" % [name, str(sl.get("type", sl.get("station", "")))])
			assert_false(Walls.hidden(info, sl.pos, float(sl.y) + 1.0) and ["deck", "gate_top"].has(String(sl.get("station", ""))), "%s: nobody stands on a wall the damage has taken" % name)
		## the scenery stands clear of the walls and of every fighter
		var sc: Dictionary = s.plan.walls.scenery
		for key in ["tents", "engines", "works"]:
			for e in sc[key]:
				assert_false(Walls.inside_wall(info, e.pos, float(e.y)), "%s: a %s stands clear of the walls" % [name, key])
				for sl in s.plan.slots:
					assert_true((sl.pos as Vector2).distance_to(e.pos) > 2.5, "%s: and of every fighter" % name)
		if not (sc.trunk as Dictionary).is_empty():
			assert_false(Walls.inside_wall(info, sc.trunk.pos, float(sc.trunk.y)), "%s: the trunk lies before the gate" % name)
		for lad in sc.ladders:
			assert_false(Walls.inside_wall(info, lad.foot, float(lad.y)), "%s: a ladder's foot stands on the ground" % name)
		## and on the land
		for f in fx.log.fighters:
			var p: Vector2 = s.plan.slots[int(f.id)].pos
			if ["line", "reserve"].has(String(s.plan.slots[int(f.id)].station)):
				assert_true(s.terrain.coast_at(p) > 0.0 and s.terrain.province_at(p) != "", "%s: %s stands on land" % [name, f.name])
	assert_true(looks.has("intact") and looks.has("breached") and (looks.has("damaged") or looks.has("battered")), "walls whole, damaged and breached were all checked (%s)" % str(looks.keys()))
	s.free()


## The top of the fort model at fort-frame (x, z), as the board draws it (WorldView._fort_piece: scaled to the row's side,
## turned by its yaw, set on its base): the highest face that points up there, or -1 when the model is not under it.
func _model_top(kind: String, kit: String, x: float, z: float) -> float:
	var glb: Dictionary = Models.building_model(kind, kit)
	if glb.is_empty():
		return -1.0
	var row: Dictionary = Models.building_row(kind, kit)
	var aabb: AABB = glb["aabb"]
	var sc := float(row.get("side", 26.0)) * WorldKit.fort_scale(kind) / maxf(aabb.size.x, aabb.size.z) ## UX-2: each level is drawn Kit.fort_scale bigger
	var basis := Basis(Vector3.UP, deg_to_rad(float(row.get("yaw", 180.0))))
	var c := aabb.get_center()
	var off: Vector3 = (basis * Vector3(-c.x, -aabb.position.y, -c.z)) * sc
	off.y -= float(row.get("sink", 0.0)) ## (the sink is of the model as the table has it: it is not scaled)
	var faces: PackedVector3Array = (glb["mesh"] as Mesh).get_faces()
	var best := -1.0
	var p := Vector2(x, z)
	for t in range(0, faces.size(), 3):
		var a: Vector3 = basis * (faces[t] * sc) + off
		var b: Vector3 = basis * (faces[t + 1] * sc) + off
		var d: Vector3 = basis * (faces[t + 2] * sc) + off
		var n := (b - a).cross(d - a)
		if n.length() < 0.0001 or absf(n.normalized().y) < 0.3:
			continue
		var v0 := Vector2(b.x - a.x, b.z - a.z)
		var v1 := Vector2(d.x - a.x, d.z - a.z)
		var v2 := p - Vector2(a.x, a.z)
		var den := v0.x * v1.y - v1.x * v0.y
		if absf(den) < 1e-9:
			continue
		var u := (v2.x * v1.y - v1.x * v2.y) / den
		var w := (v0.x * v2.y - v2.x * v0.y) / den
		if u >= -0.02 and w >= -0.02 and u + w <= 1.02:
			best = maxf(best, a.y + u * (b.y - a.y) + w * (d.y - a.y))
	return best


func test_the_decks_and_floors_the_table_names_are_on_the_models() -> void:
	## the placements stand on what the table says: if an art pass swaps a model, this says the table needs retuning
	var checked := 0
	for key in ["fort.kingdom", "fortress.kingdom", "fort.beasts", "fortress.beasts"]:
		var kind: String = String(key).get_slice(".", 0)
		var kit: String = String(key).get_slice(".", 1)
		if Models.building_model(kind, kit).is_empty():
			continue
		var spec: Dictionary = Walls.spec_of(kind, kit)
		for lane in (spec.decks as Array) + (spec.sides as Array):
			var a := Vector2(float(lane[0]), float(lane[1]))
			var b := Vector2(float(lane[2]), float(lane[3]))
			var n := int(a.distance_to(b))
			for k in range(0, n):
				var p := a.lerp(b, float(k) / float(maxi(n, 1)))
				var top := _model_top(kind, kit, p.x, p.y)
				assert_true(absf(top - float(lane[4])) < 1.6, "%s: the walk at (%.1f, %.1f) is %.1f up, the table says %.1f" % [key, p.x, p.y, top, float(lane[4])])
				checked += 1
		if not (spec.gate_top as Array).is_empty():
			var g: Array = spec.gate_top
			for dx in [-1.0, 0.0, 1.0]:
				var top2 := _model_top(kind, kit, float(g[0]) + dx * float(g[2]) * 0.3, float(g[1]))
				assert_true(absf(top2 - float(g[3])) < 1.6, "%s: the gatehouse roof is %.1f up, the table says %.1f" % [key, top2, float(g[3])])
				checked += 1
		for zone in Walls.zones_of(spec):
			var x0 := float(zone["x0"]) if zone.has("x0") else -float(zone.get("x", float(zone.get("r", 0.0)) * 0.5))
			var x1 := float(zone["x1"]) if zone.has("x1") else -x0
			for cx in [x0, x1]:
				for cz in [float(zone["z0"]), float(zone["z1"])]:
					var top3 := _model_top(kind, kit, cx, cz)
					assert_true(top3 < float(spec.floor) + 1.6, "%s: the yard's corner (%.1f, %.1f) is open floor (%.1f up)" % [key, cx, cz, top3])
					checked += 1
	assert_true(checked > 40, "the models were sampled (%d points)" % checked)


# --- the walls' defense on screen before the first hit ---------------------------------------------------------------

func test_the_walls_defense_reads_on_screen_before_the_first_hit() -> void:
	var s := _stage()
	for name in WF.names():
		var fx := _open(s, name)
		var siege: Dictionary = fx.log.siege
		assert_eq(s.player.time(), 0.0, "%s: nothing has been played" % name)
		assert_eq(int(s.player.state().round), 0, "%s: no round has begun, so no hit has landed" % name)
		var pids: Array = fx.log.provinces
		var place := BattleBackdrop.province_name(String(pids[0]))
		var line := Walls.caption_text(siege, place)
		assert_false(line.is_empty(), "%s: the caption has a line about the walls" % name)
		assert_eq(String(s.caption_labels[1].text), line, "%s: it is on the screen's caption" % name)
		assert_true(s.visible_texts().has(line), "%s: and among the texts a player can see" % name)
		var plate := Walls.plate_text(siege)
		assert_false(plate.is_empty(), "%s: the plate over the walls has words" % name)
		match String(siege.kind):
			"storm":
				assert_true(line.contains("+%d" % int(siege.walls_defense)) and line.contains("%d of %d" % [int(siege.walls), int(siege.walls_max)]),
					"%s: a storm's line says the defense and the walls: %s" % [name, line])
				assert_true(plate.contains("+%d defense" % int(siege.walls_defense)) and plate.contains("(%d of %d)" % [int(siege.walls), int(siege.walls_max)]),
					"%s: and so does the plate: %s" % [name, plate])
			"breach", "open":
				if int(siege.cover_defense) > 0:
					assert_true(line.contains("+%d cover" % int(siege.cover_defense)) and plate.contains("+%d cover" % int(siege.cover_defense)),
						"%s: the cover is named: %s / %s" % [name, line, plate])
		## the line links to the codex entry and explains itself on hover, as the chip does
		var chip := FortView.siege_chip(siege)
		assert_true(String(s.caption_labels[1].tooltip_text).begins_with(String(chip.tip)), "%s: the caption's tooltip is the walls' own words, then the codex's" % name)
		s._walls_plate = Rect2(Vector2(20, 20), Vector2(100, 24))
		assert_eq(s._get_tooltip(s.frame.position + Vector2(0, BattleSimpleView.TOP_H) + Vector2(40, 30)), String(chip.tip), "%s: hovering the plate says it too" % name)
		assert_true(plate.length() < 60, "%s: the plate is short enough to hang over the wall (%d characters)" % [name, plate.length()])
	## and once the battle is played the same line is replaced by the round captions, the plate stays
	_open(s, "storm_keep")
	_play_out(s, 4)
	assert_true(s.player.is_finished(), "the battle plays out")
	s.free()


func test_the_fort_on_the_land_is_the_logs_and_the_next_battle_puts_the_map_back() -> void:
	var s := _stage()
	for name in WF.names():
		var fx := _open(s, name)
		var siege: Dictionary = fx.log.siege
		var pid := String(fx.log.provinces[0])
		var level := Walls.level_of(siege)
		var row: Dictionary = s.wv.fort_table()[pid]
		assert_eq(String(row.kind), SiegeBoard_kind(level), "%s: the kit of the level the log names" % name)
		assert_eq(String(row.look), SiegeRules.damage_look(level, int(siege.walls)), "%s: wearing the look the walls' strength gives" % name)
		assert_eq(int(row.walls), int(siege.walls), "%s: at the walls the log has" % name)
		assert_eq(String(row.kit), String(s.wv.map_kits().get(pid, "")), "%s: in the kit the map gives it" % name)
		assert_eq(String(_info(s).kind), String(row.kind), "%s: and the planner stands at that fort" % name)
	var plain := Fx.battle("starting_plains")
	assert_eq(s.show_battle(plain.log, plain.report), "", "an ordinary battle plays next")
	assert_true(s.wv.fort_table().is_empty(), "the map's own forts are put back")
	assert_true(s.scenery.counts.values().all(func(n): return int(n) == 0), "the siege scenery is taken down")
	assert_ne(String(s.plan.where), "walls", "and the battle stands where geography puts it")
	s.free()


static func SiegeBoard_kind(level: int) -> String:
	return ["", "palisade", "fort", "fortress"][level]


# --- the camp ---------------------------------------------------------------------------------------------------

func test_the_besiegers_camp_has_a_tent_to_an_army_and_the_engines_they_still_carry() -> void:
	var s := _stage()
	var with_engines := 0
	for name in WF.names():
		var fx := _open(s, name)
		var sc: Dictionary = s.plan.walls.scenery
		var besieger := int(s.plan.walls.besieger)
		assert_eq(besieger, 1 - int(fx.log.siege.garrison), "%s: the besiegers are the fort's other side" % name)
		var carried := 0
		for a in fx.log.sides[besieger].armies:
			var army: Army = fx.state.find_army(String(a.id))
			if army != null:
				carried += army.engines
		assert_eq((sc.engines as Array).size(), mini(carried, Walls.MAX_ENGINES), "%s: the engines are those the besiegers' surviving armies carry (%d)" % [name, carried])
		assert_eq((sc.tents as Array).size(), maxi(1, (fx.log.sides[besieger].armies as Array).size()), "%s: a tent to an army" % name)
		assert_eq(String(sc.style), String(fx.log.sides[besieger].faction), "%s: in the besiegers' style" % name)
		assert_eq(s.scenery.counts.tents, (sc.tents as Array).size(), "%s: the tents are drawn" % name)
		assert_eq(s.scenery.counts.engines, (sc.engines as Array).size(), "%s: so are the engines" % name)
		assert_eq(s.scenery.counts.fires, (sc.tents as Array).size(), "%s: and a fire by each tent" % name)
		if carried > 0:
			with_engines += 1
			assert_false((sc.works as Array).is_empty(), "%s: the siege works stand with them" % name)
		assert_eq(_stage_engines(s, name, false), 0, "%s: without a game, no engines are claimed" % name)
	assert_true(with_engines >= 3, "some of the battles have engines in the camp (%d)" % with_engines)
	s.free()


func _stage_engines(s: BattleStage3D, name: String, with_state: bool) -> int:
	_open(s, name, with_state)
	return (s.plan.walls.scenery.engines as Array).size()


# --- the figures ------------------------------------------------------------------------------------------------

func test_a_fighter_on_a_wall_strikes_where_it_stands_and_fades_when_it_routs() -> void:
	var s := _stage()
	var fx := _open(s, "storm_keep")
	var info := _info(s)
	var deck_fid := -1
	for fid in fx.log.sides[int(s.plan.near)].fighters:
		if String(s.plan.slots[int(fid)].station) == "deck":
			deck_fid = int(fid)
			break
	assert_true(deck_fid >= 0, "a fighter stands on the wall")
	var i: int = s.figures.index_of(deck_fid)
	var home: Vector2 = s.figures.figs[i].home
	var target := Vector2.ZERO
	for fid in fx.log.sides[int(s.plan.far)].fighters:
		target = s.plan.slots[int(fid)].pos
		break
	s.figures.add_motion(i, {"kind": "lunge", "t0": 0.0, "dur": Figures.LUNGE_OUT + Figures.LUNGE_BACK, "to": target})
	var far_most := 0.0
	var lowest := INF
	for k in 12:
		var t := float(k) * (Figures.LUNGE_OUT + Figures.LUNGE_BACK) / 11.0
		var p: Dictionary = s.figures.pose_at(i, t)
		far_most = maxf(far_most, (p.pos as Vector2).distance_to(home))
		var ends: Array = s.figures.ends_at(i, t)
		lowest = minf(lowest, (ends[0] as Vector3).y)
	assert_true(far_most <= Figures.LUNGE_MAX * 0.25 + 0.01, "the lunge stays at the parapet (%.2f)" % far_most)
	## (a lunge sags in proportion to the wall it is on, and UX-2 draws each fort level bigger: so the slack scales with the kit's size)
	var slack := 1.0 * WorldKit.fort_scale(String(info.kind))
	assert_true(lowest >= float(s.figures.figs[i].y) - slack, "and on the wall: the feet never drop to the ground (%.2f of %.2f)" % [lowest, float(s.figures.figs[i].y)])
	var yl := float(s.figures.figs[i].y) - float(info.base_y)
	assert_true(yl > 5.0, "the wall is well above the ground (%.1f)" % yl)
	## a rout fades it where it stands instead of running it through the wall
	s._rout_figure(i, 1.0, 1.0)
	var kinds := (s.figures.figs[i].motions as Array).map(func(m): return String(m.kind))
	assert_true(kinds.has("fade") and not kinds.has("rout"), "a routed fighter on a wall fades (%s)" % str(kinds))
	s.free()


func test_a_march_out_follows_its_path_and_holds_the_yards_floor_to_the_gate() -> void:
	var path := [Vector2(0, 0), Vector2(0, 10), Vector2(0, 20), Vector2(10, 20)]
	assert_eq(Walls.path_length(path, 2), 20.0, "the path's length to its third point")
	assert_eq(Walls.path_length(path, 3), 30.0, "and to its last")
	var a: Dictionary = Figures.along(path, 20.0 / 30.0)
	assert_true((a.pos as Vector2).is_equal_approx(Vector2(0, 20)) and absf(float(a.s) - 20.0) < 0.001, "two thirds of the way is its third point")
	assert_true((Figures.along(path, 0.5).pos as Vector2).is_equal_approx(Vector2(0, 15)), "half way is half the length")
	assert_true((Figures.along(path, 0.0).pos as Vector2).is_equal_approx(path[0]) and (Figures.along(path, 1.0).pos as Vector2).is_equal_approx(path[-1]), "the ends are the ends")
	assert_true(absf(angle_difference(float(Figures.along(path, 0.2).yaw), atan2(0.0, -1.0))) < 0.001, "it faces the way it walks")


# --- the camera ---------------------------------------------------------------------------------------------------

func test_the_camera_frames_the_fighters_the_walls_and_the_plate() -> void:
	var s := _stage()
	for name in WF.names():
		var fx := _open(s, name)
		var band := s._band().grow(4.0)
		for f in fx.log.fighters:
			for p in s.figures.ends_at(int(f.id), 0.0):
				var v := Cam.project(s.wv.rig, s._view, p)
				assert_true(band.has_point(v), "%s: %s stands inside the band the screen leaves clear (%s)" % [name, f.name, v])
		for p in s.plan.walls.frame_extra:
			var v2 := Cam.project(s.wv.rig, s._view, p)
			assert_true(band.has_point(v2), "%s: the walls and the camp stay in view (%s)" % [name, v2])
		var v3 := Cam.project(s.wv.rig, s._view, s.plan.walls.plate)
		assert_true(band.has_point(v3), "%s: and so does the plate's place (%s)" % [name, v3])
	s.free()


# --- determinism, files, the stage only shows ------------------------------------------------------------------------

func test_the_same_log_stands_the_same_way_every_time() -> void:
	var s := _stage()
	for name in ["storm_keep", "storm_capital_beasts", "breach", "sally", "relief_sally"]:
		var fx := _open(s, name)
		var first := var_to_str([s.plan.slots, s.plan.extras, s.plan.back, s.plan.walls.march, s.plan.walls.scenery])
		var again: Dictionary = Walls.plan(fx.log, s.terrain, s._world_info(), s._band().size.x / s._band().size.y, s.groups)
		assert_eq(var_to_str([again.slots, again.extras, again.back, again.walls.march, again.walls.scenery]), first, "%s: the plan is the same twice" % name)
	s.free()


func test_a_big_siege_battle_stands_in_files_too() -> void:
	var s := _stage()
	var fx := _open(s, "storm_keep")
	var groups := Formation.groups_of(fx.log, 6)
	assert_false(groups.is_empty(), "the battle is grouped into files")
	var plan := Walls.plan(fx.log, s.terrain, s._world_info(), 2.6, groups)
	for f in fx.log.fighters:
		assert_true(plan.slots[int(f.id)] != null, "every fighter has a place (%d)" % int(f.id))
	for k in (groups.members as Array).size():
		var members: Array = groups.members[k]
		for fid in members:
			assert_eq(var_to_str(plan.slots[int(fid)].pos), var_to_str(plan.slots[int(members[0])].pos), "a file's fighters share its figure's place")
	s.free()


func test_a_siege_battle_plays_to_the_timelines_final_state_and_changes_nothing() -> void:
	var s := _stage()
	var checked := 0
	for name in WF.names():
		var fx := _open(s, name)
		var log_before := var_to_str(fx.log)
		var report_before := var_to_str(fx.report)
		var event_before := var_to_str(fx.event)
		var state_before := var_to_str(fx.state.to_dict())
		_play_out(s, 4)
		var fin := s.player.timeline().final_state()
		assert_eq(s.player.state(), fin, "%s: the player ends on the final state" % name)
		var holds := []
		for i in s.figures.n_fighters:
			holds.append(String(s.figures.figs[i].hold))
		var want := []
		for fs in fin.fighters:
			want.append("fallen" if not fs.alive else ("gone" if fs.fled or fs.lost else "stand"))
		assert_eq(holds, want, "%s: every figure stands, lies or is gone as the final state says, walls or no walls" % name)
		assert_true(s.end_card.visible, "%s: the result card is up" % name)
		## seeking lands on the same state, and a sought stage stands as a played one
		s.player.seek_round(2)
		s.player.next_moment()
		s.tick(STEP)
		s.player.skip_to_end()
		s.tick(STEP)
		assert_eq(s.player.state(), fin, "%s: a seek and a skip land on it too" % name)
		assert_eq(var_to_str(fx.log), log_before, "%s: the log is unchanged" % name)
		assert_eq(var_to_str(fx.report), report_before, "%s: the report is unchanged" % name)
		assert_eq(var_to_str(fx.event), event_before, "%s: the event is unchanged" % name)
		assert_eq(var_to_str(fx.state.to_dict()), state_before, "%s: the game is unchanged" % name)
		checked += 1
	assert_true(checked >= 10, "the battles were played (%d)" % checked)
	s.free()


func test_the_launcher_plays_a_siege_fixture_with_the_game_it_was_fought_in() -> void:
	var W3D := preload("res://world3d/battle_watch3d.gd")
	var w := W3D.new()
	var fx := W3D.load_fixture("siege_storm_won")
	assert_false(fx.is_empty() or not fx.has("state"), "the launcher finds the fixture and its game")
	assert_eq(w.watch(fx), "", "it plays")
	assert_eq(String(w.stage.plan.where), "walls", "at the walls")
	var carried := 0
	for a in fx.log.sides[1 - int(fx.log.siege.garrison)].armies:
		var army: Army = fx.state.find_army(String(a.id))
		if army != null:
			carried += army.engines
	assert_true(carried > 0, "the stormers won and kept their engines")
	assert_eq((w.stage.plan.walls.scenery.engines as Array).size(), mini(carried, Walls.MAX_ENGINES), "which stand in their camp")
	w.free()


func test_reduced_motion_keeps_a_sally_in_its_places() -> void:
	var s := _stage(true)
	var fx := _open(s, "sally")
	s.player.play()
	s.tick(0.001)
	for i in s.figures.n_fighters:
		var kinds := (s.figures.figs[i].motions as Array).map(func(m): return String(m.kind))
		assert_false(kinds.has("march_out") or kinds.has("deploy"), "fighter %d does not march with reduced motion" % int(s.figures.figs[i].fid))
	assert_eq(fx.log.siege.kind, "open")
	s.free()


# --- the rules the stage shows are the rules' (M3's levels: the player, and no dice) ------------------------------------

func test_the_player_plays_every_siege_battle_once_over_and_leaves_it_as_it_was() -> void:
	for name in WF.names():
		var fx := WF.battle(name)
		var log_before := var_to_str(fx.log)
		var p := BattlePlayer.new(fx.log, fx.report)
		var count := {}
		for b in p.beats():
			if BattlePlayer.APPLYING.has(b.kind):
				count[int(b.event)] = int(count.get(int(b.event), 0)) + 1
		for i in fx.log.events.size():
			assert_eq(int(count.get(i, 0)), 1, "%s: event %d is applied once" % [name, i])
		p.skip_to_end()
		assert_eq(p.state(), p.timeline().final_state(), "%s: skip lands on the final state" % name)
		for fid in range(0, fx.log.fighters.size(), 5):
			p.explain(fid)
		assert_eq(var_to_str(fx.log), log_before, "%s: playing and explaining leave the log as it was" % name)
		var again := BattlePlayer.new(fx.log, fx.report)
		assert_eq(var_to_str(again.beats()), var_to_str(BattlePlayer.new(fx.log, fx.report).beats()), "%s: the same log gives the same beats" % name)


func test_the_walls_code_never_rolls_dice_or_resolves_anything() -> void:
	var banned := RegEx.create_from_string(
		"\\b(SeededRNG|RandomNumberGenerator|randi|randf|randi_range|randf_range|randfn|randomize|rand_from_seed|seed)\\s*\\(|\\bSeededRNG\\b|\\bRandomNumberGenerator\\b|\\bTurnResolver\\b|AutoBattleResolver\\s*\\.\\s*(fight|resolve|resolve_battle|estimate)\\b|\\.(end_turn|queue_order|queue_move|queue_recruit|begin_turn|acknowledge_handoff|cancel_order)\\s*\\(")
	for path in NEW_FILES + ["res://world3d/battle_stage.gd", "res://world3d/battle_figures.gd"]:
		var lines := FileAccess.get_file_as_string(path).split("\n")
		assert_true(lines.size() > 50, "%s can be read" % path)
		for k in lines.size():
			var line := String(lines[k])
			var code := line.split("#")[0] if not line.strip_edges().begins_with("##") else ""
			assert_true(banned.search(code) == null, "%s:%d draws no number and calls no rules: %s" % [path, k + 1, line.strip_edges()])
