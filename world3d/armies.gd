## The armies on the 3D board. The figures ARE the army markers (design/3D_DIRECTION.md 6.1): every army
## stands as a formation of miniatures, a block per unit type (Models.block_size figures, front rank
## first, Volley behind, the commander and the banner bearer at the back), every base painted in the
## owner's colour, the banner in the owner's colour with the seat's emblem.
##
## Where they stand (layout_of()):
##   * at a capital: in the fortress's muster yard, a block to a slot (world3d/muster.gd), facing the
##     gate; armies the yard can't hold muster in a war camp outside the walls, a tent behind every
##     block, a fire and its smoke for every army there;
##   * M3c S-4, in a game with sieges, at every other fort (a palisade, a keep): its owner's armies packed in its
##     yard (Muster.packed), the overflow in the war camp outside its gate; at a besieged fort (a capital too) the
##     garrison packs into the yard, tighter the bigger it is, and what still doesn't fit packs at the gate, while
##     the besiegers camp in a ring round the walls (a tent and a fire behind each army, facing the walls), their
##     siege works before the gate and the engines they carry at the walls;
##   * elsewhere: on the province's stage, facing its roads.
## While a player plans (show_plan(), their own orders only): queued recruits stand as ghosts in the
## slots they will take, and armies ordered to march gather in a column at the gate (or the edge of
## their province), facing the road they will take; the rest of the yard closes ranks.
##
## Turn playback (play()), in the turn report's phases (world3d/choreo.gd):
##   Movement  every march files out of the gate (two abreast, the banner first), marches the roads, and
##             stops where its battle is (a border crossing, a line before the defenders), or comes to
##             its new place;
##   Battles   each battle in turn: the defenders step out to their line (before their gate at a
##             fortress), the two lines trade blows (strike poses, lunges, recoils), the fallen topple
##             and lie in their fallen pose, the winners cheer; a border battle's winners march on; at a fort
##             (M3c S-4) a sally's armies file out of the gate two abreast and form up facing the camps, a storm
##             meets at the walls, a breach battle in the gap;
##   Sieges    (M3c S-4) each fort beat in the report's order: the camps go up and the chevrons rise, the camp
##             and the engines strike the walls and the damage look changes, a breach collapses the gate side
##             with a rubble burst, a lifted siege folds its camps, masons repair, a new level stands;
##   Captures  the new owner's colour sweeps out from its arriving column, the fortress takes its banners;
##   Recruits  recruits march in through their fort's gate (or appear on the stage) and form up; scaffolding
##             goes up where a fort was ordered; everyone settles in their place of the state after.
## Each phase plays only when the turn has something in it. Beats (march, clash, strike, fall, capture,
## recruit) are signalled for the board's sounds. It reads the states and events only and never
## changes them; at the end the board stands exactly as built from the state after (tests).
##
## Figures are drawn with one MultiMesh per army, unit type and distinct pose mesh (a pose with no model
## of its own shares the ready pose's), compacted each sync so a pose draws only its own figures.
## Cosmetic variety (a step's phase, who strikes first) comes from a hash of ids, never from a random
## number generator.
extends Node3D

const Kit := preload("res://world3d/kit.gd")
const Models := preload("res://world3d/models.gd")
const Playback := preload("res://world3d/playback.gd")
const Muster := preload("res://world3d/muster.gd")
const Choreo := preload("res://world3d/choreo.gd")
const WorldView := preload("res://world3d/world_view.gd")
const SiegeBoard := preload("res://world3d/siege_board.gd")
const SH_GHOST := preload("res://world3d/shaders/ghost.gdshader")
const SH_SMOKE := preload("res://world3d/shaders/smoke.gdshader")
const SH_MEMORY := preload("res://world3d/shaders/memory_ghost.gdshader")
const SH_WICK := preload("res://world3d/shaders/wick_flame.gdshader") ## CW-8: an army's flame on its figures' wicks
const CandleFigures := preload("res://world3d/candle_figures.gd")
const Vision := preload("res://world3d/vision.gd")
const MagicBeats := preload("res://world3d/magic_beats.gd")
const SPEED := 21.0 ## march speed, world units a second at 1x
const IN_SPEED := 24.0 ## recruits marching in
const GAP := 4.4 ## between pairs in a column
const LANE := 1.7 ## half the column's width
const GATHER_GAP := 3.3 ## a gathered column's pairs, closer than on the march
const CLASH := 2.0 ## a battle's exchange (seconds at 1x)
const BATTLE_STEP := 1.7 ## the next battle begins this long after the last
const STEP_OUT := 1.2 ## defenders step out to their line
const LINE_BACK := 4.6 ## a side's line stands this far from the battle's front
const PHASE_GAP := 0.35
const CAPTURE_STEP := 0.4
const SWEEP_TIME := 1.2
const REFORM := 2.0 ## the re-form at the end of the turn
const TAIL := 0.6
const CAMP_OUT := 5.0 ## the war camp's first row, out from the gate
const ROAD_CLEAR := 7.0 ## the camp keeps this far off the road out of the gate
const SMOKE_PUFFS := 6
const MUSICIAN_OFF_RUNG := 2 ## #125: the musician stands down from this quality rung (world_view.gd set_quality)
const RING_GAP := 12.0 ## M3c S-4: a besieging army's front stands this far outside the walls
const RING_TENT := 4.5 ## its tent stands this far behind its last rank
const GATE_APRON := 9.0 ## a besieged garrison's overflow packs this deep outside its gate
const SIEGE_BEAT := 1.15 ## a fort beat of the sieges phase (seconds at 1x); a breach takes longer
const BREACH_BEAT := 1.6

## #125: the musician in every colour party (off on the lower quality rungs: the board sets it, musicians_at).
static var musicians := true
## CW-8: the wick flames sway on the quality ladder's top rungs, never with reduced motion (the board sets it, set_flicker).
static var flicker := true
static var _wick_mesh: ArrayMesh = null
static var _wick_mat: ShaderMaterial = null

## The land changed hands: the board repaints the province's wash and its fortress.
signal captured(province_id: String, owner_id: String)
## A capture's sweep begins from the arriving column (`from`, a map point): the board animates the wash.
signal capture_swept(province_id: String, owner_id: String, from: Vector2)
## A battle's clash begins.
signal clash_started(label: String)
## A beat of the playback: kind "march", "clash", "strike", "fall", "capture" or "recruit", and its index
## among the turn's beats of that kind (the board picks the sound from them, Choreo.sound_for).
signal beat(kind: String, index: int)
## The whole turn has played (or was skipped); the board now shows the state after.
signal playback_finished
## M3c S-4: a fort beat plays (the board's dust and shake): `kind` from Choreo.FORT_BEATS, at the fort's province.
signal fort_beat(province_id: String, kind: String, index: int)
## M5-3: the re-form begins: the board shows the state after's sight from here (the veil lifts or falls as everyone re-forms).
signal reform_started
## M5-3: a ritual's beat (Playback.plan's "rituals"): where it starts (`from`, "" when the caster is hidden from the viewer:
## the beat then starts at the target) and where it falls. The effects are drawn from magic_beat (below), which carries every beat whole.
signal ritual_beat(from: String, at: String, ritual: String, index: int)
## M5-9: any magic beat of the turn (Playback.plan's "rituals": a cast, a fizzle, a fall, a payment in blood, a summoning, a fort raised,
## an enchantment beginning or ending, a heal or a bite, a fading, a reading), whole, when it plays; the spell effects draw it
## (world3d/enchant_decals.gd). `phase` is the report's (rituals or enchantments). It reads the beat; nothing here changes the game.
signal magic_beat(beat: Dictionary, index: int)

var wv: Node3D ## world_view.gd
var prefer_models := true ## false: every figure as its primitive (the preview's P key)
var state: GameState
var seats: Array = []
var armies := {} ## army id -> entry: {"id", "owner", "colour", "emblem", "figs", "types", "banner", "province", "units", "ruler", "ghost"}
var ghost_root: Node3D
var memory_root: Node3D ## M5-3: the remembered armies' ghosts (Vision), apart from the queued recruits' ghosts
var camp_root: Node3D
var camps := {} ## province id -> {"tents": [{"pos", "yaw", "y", "style", "colour", "ring"}], "fires": [Vector3], "works": [{"pos", "yaw", "y", "style", "colour", "kind"}]}: the camps standing now
var rings := {} ## M3c S-4: province id -> {"besieger", "camps": [army ids]}: the besieged forts' camp rings standing now
var gathered := {} ## army id -> the province it was ordered to: armies gathered at their gate (planning cue)
var plan_ctx := {} ## the viewing player's plan the board shows (show_plan)
var _ghost_entries: Array = []
var _plan_key := ""
var _camp_key := ""
var _engines: Array = [] ## M3c S-4: the siege engines standing at besieged forts: [{"mm", "i", "xf", "fwd", "pos"}]
var _mats := {}
var _play: Dictionary = {}
var beat_province := "" ## M5-3: the province of the beat that just fired ("" when it has none): the board plays sound only for what the viewer sees
var clock := 0.0
var fig_scale := 1.0 ## toy scale: figures stand taller when the camera is far, so the army reads
var blend := 1.0 ## #125: the figures' share against the far-zoom stands (stands.gd): 0 hides them
var fig_shadows := true ## figures cast shadows only from the default zoom in (far out they are a few pixels)
var speed := 1.0 ## playback speed (1, 2, 4)
var snap_at_end := true ## rebuild from the state after when the playback ends (tests turn it off to compare)


func _init() -> void:
	ghost_root = Node3D.new()
	ghost_root.name = "Ghosts"
	add_child(ghost_root)
	memory_root = Node3D.new()
	memory_root.name = "Memories"
	add_child(memory_root)
	camp_root = Node3D.new()
	camp_root.name = "Camps"
	add_child(camp_root)


## Figures cast shadows (or not): far out they are a few pixels tall and their shadow splits are the
## dearest part of the map's frame, so the board turns them off there (their bases still ground them).
func set_fig_shadows(on: bool) -> void:
	if on == fig_shadows:
		return
	fig_shadows = on
	for e in armies.values():
		if bool(e.get("memory", false)):
			continue ## a memory ghost casts no shadow
		for t in e["types"].keys():
			for mi in e["types"][t]["mis"]:
				(mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## The figures' share against the far-zoom stands (stands.gd, #125): they shrink away as the stands grow in.
func set_blend(v: float) -> void:
	v = clampf(v, 0.0, 1.0)
	if absf(v - blend) < 0.004:
		return
	blend = v
	for e in armies.values():
		_sync(e)
	for g in _ghost_entries:
		_sync(g)


## Sets the toy scale (the board eases it with the zoom) and restands every figure.
func set_fig_scale(v: float) -> void:
	if absf(v - fig_scale) < 0.01:
		return
	fig_scale = v
	for e in armies.values():
		_sync(e)
	for g in _ghost_entries:
		_sync(g)


# ------------------------------------------------------------------ standing armies

## Stands every army of `s` in its place (no animation). Clears any playback. `ctx` is a plan (see
## show_plan); the playback passes the turn's marches so the columns start gathered at their gates.
func show_state(s: GameState, p_seats: Array, ctx: Dictionary = {}) -> void:
	state = s
	seats = p_seats
	_play = {}
	plan_ctx = ctx
	_plan_key = _key_of(ctx)
	for id in armies.keys():
		_free_army(armies[id])
	armies.clear()
	var lay := layout_of(s, ctx)
	var places: Dictionary = lay["places"]
	for a in s.armies:
		armies[a.id] = _make_entry(_desc_of(a), places.get(a.id, []))
	gathered = lay["gathered"]
	_set_ghosts(lay["ghosts"])
	_set_camps(lay["camps"])
	rings = lay["rings"]


## The viewing player's plan, drawn on the standing armies (their own orders only; the board never
## passes another seat's): {"departing": {army id: {"to", "via"}}, "ghosts": [{"province", "owner",
## "types": [unit type ids]}], "owner": the planning faction}. Armies ordered to march gather at their
## gate, the yard closes ranks, queued recruits stand as ghosts where they will muster.
func show_plan(ctx: Dictionary) -> void:
	if state == null or not _play.is_empty():
		return
	var key := _key_of(ctx)
	if key == _plan_key:
		return
	_plan_key = key
	plan_ctx = ctx
	var lay := layout_of(state, ctx)
	var places: Dictionary = lay["places"]
	for a in state.armies:
		if not armies.has(a.id):
			continue
		var e: Dictionary = armies[a.id]
		var placed: Array = places.get(a.id, [])
		if not _same_figures(e, placed):
			_free_army(e)
			e = _make_entry(_desc_of(a), placed)
			armies[a.id] = e
			continue
		for i in placed.size():
			var f: Dictionary = e["figs"][i]
			var sl: Dictionary = placed[i]
			for k in ["pos", "yaw", "y"]:
				f[k] = sl[k]
				f["from_" + k] = sl[k]
				f["to_" + k] = sl[k]
			f["pose"] = "ready"
		_sync(e)
	gathered = lay["gathered"]
	_set_ghosts(lay["ghosts"])
	_set_camps(lay["camps"])
	rings = lay["rings"]


static func _key_of(ctx: Dictionary) -> String:
	return JSON.stringify(ctx, "", true) if not ctx.is_empty() else ""


func _same_figures(e: Dictionary, placed: Array) -> bool:
	var figs: Array = e["figs"]
	if figs.size() != placed.size():
		return false
	for i in figs.size():
		if figs[i]["type"] != placed[i]["type"] or figs[i]["role"] != placed[i]["role"]:
			return false
	return true


func playing() -> bool:
	return not _play.is_empty()


## The board's description of an army: its blocks and leaders, as the layouts need.
func _desc_of(a: Army, st: GameState = null) -> Dictionary:
	var counts := {}
	var order: Array = []
	for u in a.units:
		var t: String = u.type.id
		if not counts.has(t):
			counts[t] = 0
			order.append(t)
		counts[t] += 1
	var blocks: Array = []
	for t in order:
		blocks.append({"type": t, "n": Models.block_size(counts[t]), "rank": Models.rank_of(t), "sp": _spacing(t)})
	blocks.sort_custom(func(x, y): return x["rank"] < y["rank"] or (x["rank"] == y["rank"] and x["type"] < y["type"]))
	var leaders: Array = []
	if a.ruler != null:
		var rt: String = a.ruler.type.id
		leaders.append({"type": rt, "role": "ruler", "rank": Models.rank_of(rt), "sp": _spacing(rt)})
	if a.commander != null:
		var ct: String = a.commander.type.id
		leaders.append({"type": ct, "role": "commander", "rank": 2, "sp": _spacing(ct)})
	var d := {"id": a.id, "owner": a.owner, "location": a.location, "blocks": blocks, "leaders": leaders,
		"units": a.units.size(), "ruler": a.ruler != null, "extras": extras()}
	if a.flame >= 0:
		d["flame"] = a.flame  # CW-8: its regulars' wicks burn at it (none in a view out of clear sight: -1)
	if Vision.is_memory(a):
		## M5-3: a remembered army (a grey ghost): no banner, no tent and no fire, fading a step for every 2 turns of age
		d["memory"] = true
		d["step"] = Vision.ghost_step(Vision.age_of(st if st != null else state, a))
	if Vision.is_stand_in(a):
		d["stand_in"] = true
	return d


## The army's cosmetic extras (design 6.2): the standard bearer, and the musician when the model table
## has one and `musicians` is on (#125: the board turns it off on the quality ladder's lower rungs,
## extras_for_rung). They never count; the plate's number leaves them out.
static func extras() -> Array:
	return ["bearer", "musician"] if Models.has_musician() and musicians else ["bearer"]


## Whether a quality rung keeps the musician (#92 measured it at 18% more figures): from MUSICIAN_OFF_RUNG
## down it stands down. The bearer always stays: it carries the army's banner, its owner's colour and emblem.
static func musicians_at(rung: int) -> bool:
	return rung < MUSICIAN_OFF_RUNG


## CW-8: whether the wick flames sway on board quality rung `rung` (the top two: 0 and 1), never with reduced motion.
static func flicker_at(rung: int, reduced: bool) -> bool:
	return rung <= 1 and not reduced


## CW-8: sets the flames' sway for every army at once (one shared material).
static func set_flicker(on: bool) -> void:
	flicker = on
	if _wick_mat != null:
		_wick_mat.set_shader_parameter("flicker", 1.0 if on else 0.0)


## CW-8: the flame drawn on a wick, a teardrop of unit height with its foot at the origin (scaled to CandleFigures.flame_look's
## height and width per figure), and its material; shared by every army.
static func wick_mesh() -> ArrayMesh:
	if _wick_mesh == null:
		var b := Kit.Builder.new()
		b.ball(0.36, Vector3(0, 0.33, 0), Color.WHITE, Vector3(1.0, 0.92, 1.0), 8)
		b.cyl(0.0, 0.33, 0.62, Vector3(0, 0.69, 0), Color.WHITE, 8)
		_wick_mesh = b.mesh()
	return _wick_mesh


static func wick_material() -> ShaderMaterial:
	if _wick_mat == null:
		_wick_mat = ShaderMaterial.new()
		_wick_mat.shader = SH_WICK
		_wick_mat.set_shader_parameter("flicker", 1.0 if flicker else 0.0)
	return _wick_mat


func _spacing(t: String) -> Vector2:
	if Kit.SPACING.has(t):
		return Kit.SPACING[t]
	var row := Models.figure_row(t)
	var fb := String(row.get("fallback", ""))
	var s := float(row.get("scale", 1.0))
	return (Kit.SPACING.get(fb, Vector2(4.2, 4.4)) as Vector2) * s


## Where every army's figures stand in `s` (army id -> [{"type", "role", "pos": Vector2, "yaw", "y"}]).
func arrange(s: GameState, ctx: Dictionary = {}) -> Dictionary:
	return layout_of(s, ctx)["places"]


## The whole layout of `s` under the plan `ctx` (show_plan's format): {"places": army id -> figure
## places, "ghosts": [{"province", "owner", "types", "figs": [places]}], "camps": province id -> camp,
## "gathered": army id -> destination, "musters": province id -> Muster.layout() (or, at a fort's yard,
## Muster.packed()), "rings": province id -> {"besieger", "camps": [army ids]} (M3c S-4)}. Pure of nodes.
func layout_of(s: GameState, ctx: Dictionary = {}) -> Dictionary:
	var out := {"places": {}, "ghosts": [], "camps": {}, "gathered": {}, "musters": {}, "rings": {}}
	var departing: Dictionary = ctx.get("departing", {})
	var by_prov := {}
	var dep_prov := {}
	var descs := {}
	for a in s.armies:
		var d := _desc_of(a)
		descs[a.id] = d
		var bucket: Dictionary = dep_prov if departing.has(a.id) else by_prov
		if not bucket.has(a.location):
			bucket[a.location] = []
		bucket[a.location].append(d)
	var ghost_by := {}
	for g in ctx.get("ghosts", []):
		var pid := String(g.get("province", ""))
		if pid.is_empty():
			continue
		if not ghost_by.has(pid):
			ghost_by[pid] = []
		ghost_by[pid].append(g)
	var t = wv.terrain
	var pids := {}
	for k in by_prov.keys() + dep_prov.keys() + ghost_by.keys():
		pids[k] = true
	var keys: Array = pids.keys()
	keys.sort()
	for pid in keys:
		if t.index_of(pid) < 0:
			continue
		var list: Array = by_prov.get(pid, [])
		var gh: Array = _ghost_entries_for(s, pid, ghost_by.get(pid, []), departing)
		var y: Dictionary = wv.yard_of(pid, s)
		if y.is_empty():
			_layout_stage(pid, list, gh, out)
		else:
			var p := s.find_province(pid)
			var owner: String = p.owner if p != null else ""
			var besieged: bool = s.sieges and SiegeRules.is_besieged(s, pid)
			if bool(y["capital"]) and not besieged:
				_layout_fortress(s, pid, y, list, gh, out)
			else:
				_layout_packed(pid, y, list.filter(func(d): return d["owner"] == owner), gh, out, besieged)
				var others: Array = list.filter(func(d): return d["owner"] != owner)
				if not others.is_empty():
					_layout_ring(s, pid, y, others, out)
		var deps: Array = dep_prov.get(pid, [])
		if not deps.is_empty():
			_layout_gather(pid, deps, departing, out, y)
	return out


## Queued recruits at `pid` as Muster ghost entries: each type joins the army the rules will most likely
## put it in (the planning player's first army there that isn't marching off and has no ruler; a
## commander the first without one), or a new army.
func _ghost_entries_for(s: GameState, pid: String, groups: Array, departing: Dictionary) -> Array:
	var out: Array = []
	for g in groups:
		var owner := String(g.get("owner", ""))
		var cands: Array = []
		for a in s.armies:
			if a.owner == owner and a.location == pid and a.ruler == null and not departing.has(a.id):
				cands.append(a)
		cands.sort_custom(func(x, y): return x.id < y.id)
		var counts := {}
		var order: Array = []
		for ty in g.get("types", []):
			if not counts.has(ty):
				counts[ty] = 0
				order.append(ty)
			counts[ty] += 1
		for ty in order:
			var leader: bool = Models.rank_of(ty) >= 2 and ty != "bearer"
			var aid := ""
			for a in cands:
				if not leader or a.commander == null:
					aid = a.id
					break
			out.append({"army": aid, "type": ty, "n": counts[ty], "leader": leader, "sp": _spacing(ty), "owner": owner})
	return out


## A fortress's armies in its muster yard and war camp (Muster.layout), its ghosts in their slots. `y` its
## yard (WorldView.yard_of).
func _layout_fortress(s: GameState, pid: String, y: Dictionary, list: Array, ghosts: Array, out: Dictionary) -> void:
	var t = wv.terrain
	var ct: Array = WorldView.court_of(y)
	var facing: Vector2 = ct[1]
	var row: Dictionary = Models.building_row("fortress", String(wv.capital_of.get(pid, "")))
	var mrow: Dictionary = row.get("muster", {})
	var g := Muster.grid(float(ct[2]), float(ct[3]), int(mrow.get("slots", Muster.YARD_SLOTS)))
	var p := s.find_province(pid)
	var m := Muster.layout(list, g, p.owner if p != null else "")
	out["musters"][pid] = m
	var fr := yard_frame(pid, y)
	var yaw: float = atan2(-facing.x, -facing.y)
	var floor_y: float = float(y["floor_y"])
	for aid in m["yard"].keys():
		var placed: Array = []
		for f in m["yard"][aid]:
			placed.append({"type": f["type"], "role": f["role"], "pos": _yard_point(fr, f["pos"]), "yaw": yaw, "y": floor_y})
		out["places"][aid] = placed
	var cf := camp_frame(pid, y)
	var tents: Array = []
	var fires: Array = []
	var owner_of := {}
	var remembered := {} ## M5-3: a remembered army has no tent and no fire
	for d in list:
		owner_of[d["id"]] = d["owner"]
		if bool(d.get("memory", false)):
			remembered[d["id"]] = true
	for aid in m["camp"].keys():
		var placed2: Array = []
		for f in m["camp"][aid]:
			var w := _camp_point(cf, f["pos"])
			placed2.append({"type": f["type"], "role": f["role"], "pos": w, "yaw": yaw, "y": maxf(t.height_at(w), 0.0)})
		out["places"][aid] = placed2
		var owner := String(owner_of.get(aid, ""))
		if remembered.has(aid):
			continue
		for k in m["camp_slots"][aid]:
			var tp := _camp_point(cf, Muster.camp_tent_point(k))
			tents.append({"pos": tp, "yaw": yaw, "y": maxf(t.height_at(tp), 0.0), "style": owner, "colour": _colour_of(owner)})
		var fp := _camp_point(cf, Muster.camp_fire_point(m["camp_slots"][aid][0]))
		fires.append(Vector3(fp.x, maxf(t.height_at(fp), 0.0), fp.y))
	if not tents.is_empty():
		out["camps"][pid] = {"tents": tents, "fires": fires}
	if ghosts.is_empty():
		return
	var gp: Array = Muster.ghost_places(m, list, ghosts)
	var figs: Array = []
	var types: Array = []
	var owner2 := String(ghosts[0].get("owner", ""))
	for gplace in gp:
		var w2: Vector2 = _yard_point(fr, gplace["pos"]) if gplace["where"] == "yard" else _camp_point(cf, gplace["pos"])
		var y2: float = floor_y if gplace["where"] == "yard" else maxf(t.height_at(w2), 0.0)
		figs.append({"type": gplace["type"], "role": gplace["role"], "pos": w2, "yaw": yaw, "y": y2, "where": gplace["where"]})
		types.append(gplace["type"])
	out["ghosts"].append({"province": pid, "owner": owner2, "types": types, "figs": figs})


## The yard's frame in the world: {"o" the slot grid's front middle, "x" across, "z" into the yard}. `y` the
## yard (WorldView.yard_of; a capital's when omitted).
func yard_frame(pid: String, y: Dictionary = {}) -> Dictionary:
	var ct: Array = WorldView.court_of(y if not y.is_empty() else wv.yard_of(pid, state))
	var facing: Vector2 = ct[1]
	var row: Dictionary = Models.building_row("fortress", String(wv.capital_of.get(pid, "")))
	var g := Muster.grid(float(ct[2]), float(ct[3]), int((row.get("muster", {}) as Dictionary).get("slots", Muster.YARD_SLOTS)))
	var depth: float = Muster.grid_size(g).y
	var inward := -facing
	var right := Vector2(-facing.y, facing.x)
	var o: Vector2 = (ct[0] as Vector2) + inward * maxf(0.0, (float(ct[3]) - depth) * 0.5)
	return {"o": o, "x": right, "z": inward, "grid": g}


## The war camp's frame: outside the gate, beside the road, {"o", "x" along the wall, "z" outward}.
func camp_frame(pid: String, y: Dictionary = {}) -> Dictionary:
	var yd: Dictionary = y if not y.is_empty() else wv.yard_of(pid, state)
	var g: Array = yd["gate"]
	var facing: Vector2 = yd["gate_dir"]
	var right := Vector2(-facing.y, facing.x)
	var o: Vector2 = (g[1] as Vector2) + facing * CAMP_OUT + right * ROAD_CLEAR
	return {"o": o, "x": right, "z": facing}


static func _yard_point(fr: Dictionary, p: Vector2) -> Vector2:
	return (fr["o"] as Vector2) + (fr["x"] as Vector2) * p.x + (fr["z"] as Vector2) * p.y


static func _camp_point(fr: Dictionary, p: Vector2) -> Vector2:
	return (fr["o"] as Vector2) + (fr["x"] as Vector2) * p.x + (fr["z"] as Vector2) * p.y


func _colour_of(owner: String) -> Color:
	if state == null:
		return UiPalette.NEUTRAL
	return UiPalette.seat_color(UiPalette.seat_index(state, owner, seats))


## Armies on a province's stage: each army's field formation facing the roads, one behind the other;
## queued recruits (Warband Muster) as a ghost block right after the first army.
func _layout_stage(pid: String, list0: Array, ghosts: Array, out: Dictionary) -> void:
	var t = wv.terrain
	var list: Array = list0.duplicate()
	list.sort_custom(func(x, y): return x["id"] < y["id"])
	var ghost_desc := {}
	if not ghosts.is_empty():
		var blocks: Array = []
		var leaders: Array = []
		var types: Array = []
		for gh in ghosts:
			for q in int(gh["n"]):
				types.append(gh["type"])
			if bool(gh["leader"]):
				leaders.append({"type": gh["type"], "role": "commander", "rank": 2, "sp": gh["sp"]})
			else:
				blocks.append({"type": gh["type"], "n": int(gh["n"]), "rank": Models.rank_of(gh["type"]), "sp": gh["sp"]})
		ghost_desc = {"id": "~ghost", "owner": ghosts[0]["owner"], "location": pid, "blocks": blocks, "leaders": leaders, "types": types}
		list.insert(mini(1, list.size()), ghost_desc)
	var c: Vector2 = t.centre_of(pid)
	var facing: Vector2 = wv.gate_dir(pid)
	var origin: Vector2 = c + facing * 10.0
	var depth := 0.0
	var basis := Basis.looking_at(Vector3(facing.x, 0, facing.y), Vector3.UP)
	for d in list:
		var slots: Array = _formation(d, 44.0)
		var placed: Array = []
		for sl in slots:
			var lp: Vector2 = sl["pos"]
			var w3: Vector3 = basis * Vector3(lp.x, 0, depth + lp.y)
			var p: Vector2 = origin + Vector2(w3.x, w3.z)
			placed.append({"type": sl["type"], "role": sl["role"], "pos": p, "yaw": atan2(-facing.x, -facing.y) + float(sl.get("yaw_off", 0.0)),
				"y": maxf(t.height_at(p), 0.0)})  # CW-8: a slumped crowd's figures face a little askew
		depth += Kit.formation_depth(slots) + 2.0
		if d["id"] == "~ghost":
			var gf: Array = placed.filter(func(sl): return sl["role"] != "bearer" and sl["role"] != "musician")
			out["ghosts"].append({"province": pid, "owner": d["owner"], "types": d["types"], "figs": gf})
		else:
			out["places"][d["id"]] = placed


## M3c S-4: a fort's yard (a palisade's or a keep's, or any besieged fort's): its owner's armies packed in the court
## (Muster.packed), tighter the bigger the garrison; the armies that don't fit muster in the war camp outside the gate
## or, while the fort is `besieged`, pack at the gate (the camp ground belongs to the besiegers). Queued recruits
## (ghosts) take the next places.
func _layout_packed(pid: String, y: Dictionary, mine: Array, ghosts: Array, out: Dictionary, besieged: bool) -> void:
	var t = wv.terrain
	var ct: Array = WorldView.court_of(y)
	var facing: Vector2 = ct[1]
	var yaw: float = atan2(-facing.x, -facing.y)
	var descs: Array = mine.duplicate()
	var gdesc := _ghost_desc(pid, ghosts)
	if not gdesc.is_empty():
		descs.append(gdesc)
	var m := Muster.packed(descs, float(ct[2]), float(ct[3]))
	out["musters"][pid] = m
	var o: Vector2 = ct[0]
	var inward: Vector2 = -facing
	var right := Vector2(-facing.y, facing.x)
	var floor_y: float = float(y["floor_y"])
	var placed_of := {}
	for aid in m["yard"].keys():
		var placed: Array = []
		for f in m["yard"][aid]:
			var lp: Vector2 = f["pos"]
			placed.append({"type": f["type"], "role": f["role"], "pos": o + right * lp.x + inward * lp.y, "yaw": yaw, "y": floor_y})
		placed_of[aid] = placed
	var over: Array = m["overflow"]
	if not over.is_empty():
		if besieged:
			var gp: Array = y["gate"]
			for aid in Muster.gate_packed(over).keys():
				var placed2: Array = []
				for f in Muster.gate_packed(over)[aid]:
					var lp2: Vector2 = f["pos"]
					var w: Vector2 = (gp[1] as Vector2) + right * lp2.x + facing * minf(lp2.y, GATE_APRON)
					placed2.append({"type": f["type"], "role": f["role"], "pos": w, "yaw": yaw, "y": maxf(t.height_at(w), 0.0)})
				placed_of[aid] = placed2
		else:
			var cf := camp_frame(pid, y)
			var tents: Array = []
			var fires: Array = []
			var k := 0
			for d in over:
				var need: Array = Muster.army_slots(d)
				var centres: Array = []
				var first := k
				for j in need.size():
					centres.append(Muster.camp_block_centre(k))
					var tp := _camp_point(cf, Muster.camp_tent_point(k))
					if d["id"] != "~ghost" and not bool(d.get("memory", false)):
						tents.append({"pos": tp, "yaw": yaw, "y": maxf(t.height_at(tp), 0.0), "style": d["owner"], "colour": _colour_of(d["owner"])})
					k += 1
				var placed3: Array = []
				for f in Muster.figures_at(need, centres):
					var w2 := _camp_point(cf, f["pos"])
					placed3.append({"type": f["type"], "role": f["role"], "pos": w2, "yaw": yaw, "y": maxf(t.height_at(w2), 0.0)})
				placed_of[d["id"]] = placed3
				if d["id"] != "~ghost" and not bool(d.get("memory", false)):
					var fp := _camp_point(cf, Muster.camp_fire_point(first))
					fires.append(Vector3(fp.x, maxf(t.height_at(fp), 0.0), fp.y))
			if not tents.is_empty():
				out["camps"][pid] = {"tents": tents, "fires": fires}
	for aid in placed_of.keys():
		if aid == "~ghost":
			var gf: Array = (placed_of[aid] as Array).filter(func(sl): return sl["role"] != "bearer" and sl["role"] != "musician")
			out["ghosts"].append({"province": pid, "owner": gdesc["owner"], "types": gdesc["types"], "figs": gf})
		else:
			out["places"][aid] = placed_of[aid]


## Queued recruits at a yard or a stage as one block description ("~ghost"), or {} for none.
func _ghost_desc(pid: String, ghosts: Array) -> Dictionary:
	if ghosts.is_empty():
		return {}
	var blocks: Array = []
	var leaders: Array = []
	var types: Array = []
	for gh in ghosts:
		for q in int(gh["n"]):
			types.append(gh["type"])
		if bool(gh["leader"]):
			leaders.append({"type": gh["type"], "role": "commander", "rank": 2, "sp": gh["sp"]})
		else:
			blocks.append({"type": gh["type"], "n": int(gh["n"]), "rank": Models.rank_of(gh["type"]), "sp": gh["sp"]})
	return {"id": "~ghost", "owner": ghosts[0]["owner"], "location": pid, "blocks": blocks, "leaders": leaders, "types": types, "extras": []}


## M3c S-4 (§10.1): a besieged fort's besiegers in a ring of camps outside the walls, one per army in id order: the
## army's formation facing the walls, its tent and fire behind it; the slots start beside the gate and go round
## (SiegeBoard.ring_angles), skipping ground that isn't the province's own. Their siege works stand before the gate
## and the engines they carry at the walls, in the besieging faction's kit.
func _layout_ring(s: GameState, pid: String, y: Dictionary, others: Array, out: Dictionary) -> void:
	var t = wv.terrain
	var list: Array = others.duplicate()
	list.sort_custom(func(a, b): return a["id"] < b["id"])
	var centre: Vector2 = y["centre"]
	var gd: Vector2 = y["gate_dir"]
	var r0: float = float(y["radius"])
	var besieger: String = SiegeRules.besieging_faction(s, pid) if s.sieges else String(list[0]["owner"])
	if besieger.is_empty():
		besieger = String(list[0]["owner"])
	var cands: Array = SiegeBoard.ring_angles(8)
	for k in 8:
		cands.append(deg_to_rad(18.0 + 45.0 * k) * (1.0 if k % 2 == 0 else -1.0))
	var used: Array = []
	var tents: Array = []
	var fires: Array = []
	var ids: Array = []
	for d in list:
		var slots: Array = _formation(d, 26.0)
		var depth: float = Kit.formation_depth(slots)
		var pick := -1
		for ci in cands.size():
			if used.has(ci):
				continue
			var dir0: Vector2 = gd.rotated(float(cands[ci]))
			var far: Vector2 = centre + dir0 * (r0 + RING_GAP + depth + RING_TENT + 3.0)
			var near: Vector2 = centre + dir0 * (r0 + RING_GAP)
			if t.province_at(far) == pid and t.province_at(near) == pid and t.coast_at(far) > 2.0:
				pick = ci
				break
		if pick < 0:
			for ci2 in cands.size():
				if not used.has(ci2):
					pick = ci2
					break
		used.append(pick)
		var dir: Vector2 = gd.rotated(float(cands[pick]))
		var facing: Vector2 = -dir
		var origin: Vector2 = centre + dir * (r0 + RING_GAP)
		var basis := Basis.looking_at(Vector3(facing.x, 0, facing.y), Vector3.UP)
		var placed: Array = []
		for sl in slots:
			var lp: Vector2 = sl["pos"]
			var w3: Vector3 = basis * Vector3(lp.x, 0, lp.y)
			var p: Vector2 = origin + Vector2(w3.x, w3.z)
			placed.append({"type": sl["type"], "role": sl["role"], "pos": p, "yaw": atan2(-facing.x, -facing.y) + float(sl.get("yaw_off", 0.0)),
				"y": maxf(t.height_at(p), 0.0)})  # CW-8: a slumped crowd's figures face a little askew
		out["places"][d["id"]] = placed
		ids.append(d["id"])
		var tp: Vector2 = origin + dir * (depth + RING_TENT)
		tents.append({"pos": tp, "yaw": atan2(-facing.x, -facing.y), "y": maxf(t.height_at(tp), 0.0), "style": d["owner"], "colour": _colour_of(d["owner"]), "ring": true})
		var fp: Vector2 = tp + Vector2(-dir.y, dir.x) * (Muster.SLOT.x * 0.5 + 1.5)
		fires.append(Vector3(fp.x, maxf(t.height_at(fp), 0.0), fp.y))
	## the siege works before the gate, and the engines the besiegers carry at the walls
	var works: Array = []
	var wyaw: float = atan2(gd.x, gd.y) ## the works' and engines' front (-Z) faces the walls
	var wp: Vector2 = centre + gd * (r0 + 8.0)
	works.append({"pos": wp, "yaw": wyaw, "y": maxf(t.height_at(wp), 0.0), "style": besieger, "colour": _colour_of(besieger), "kind": "siege_works"})
	var engines := 0
	for a in s.armies:
		if a.location == pid and ids.has(a.id):
			engines += a.engines
	var shown: int = mini(engines, 6)
	var side := Vector2(-gd.y, gd.x)
	for k in shown:
		var ep: Vector2 = centre + gd * (r0 + 3.5) + side * ((k - (shown - 1) * 0.5) * 6.0 + (7.0 if k >= shown / 2 else -7.0))
		works.append({"pos": ep, "yaw": wyaw, "y": maxf(t.height_at(ep), 0.0), "style": besieger, "colour": _colour_of(besieger), "kind": "siege_engine"})
	var camp: Dictionary = out["camps"].get(pid, {"tents": [], "fires": []})
	(camp["tents"] as Array).append_array(tents)
	(camp["fires"] as Array).append_array(fires)
	camp["works"] = works
	out["camps"][pid] = camp
	ids.sort()
	out["rings"][pid] = {"besieger": besieger, "camps": ids}


## Armies ordered to march (the planning player's own) gather in a column, two abreast with the banner at
## the head: outside the gate on the road to their first border at a fortress, else at their stage's edge
## facing it. Several columns at one gate stand side by side.
func _layout_gather(pid: String, deps0: Array, departing: Dictionary, out: Dictionary, yard: Dictionary = {}) -> void:
	var t = wv.terrain
	var deps: Array = deps0.duplicate()
	deps.sort_custom(func(x, y): return x["id"] < y["id"])
	var c: Vector2 = t.centre_of(pid)
	var in_fort: bool = not yard.is_empty()
	for ci in deps.size():
		var d: Dictionary = deps[ci]
		var dep: Dictionary = departing[d["id"]]
		var first := String(dep.get("via", ""))
		if first.is_empty():
			first = String(dep.get("to", ""))
		if t.index_of(first) < 0:
			first = pid
		var x: Variant = t.crossing(pid, first)
		var cross: Vector2 = (x as Vector2) if x != null else t.centre_of(first)
		var tail: Vector2
		var dir: Vector2
		if in_fort:
			var gp: Array = yard["gate"]
			var facing: Vector2 = yard["gate_dir"]
			tail = (gp[1] as Vector2) + facing * 2.0
			dir = ((cross - tail).normalized() + facing).normalized()
		else:
			dir = (cross - c).normalized() if cross.distance_to(c) > 0.1 else Vector2(0, -1)
			tail = c + dir * (t.stage_r[t.index_of(pid)] * 0.15)
		var base: Array = _base_order(d, in_fort)
		var side := Vector2(-dir.y, dir.x)
		var lateral: float = (ci - (deps.size() - 1) * 0.5) * 6.5
		## each pair's depth from its bigger figure, so mounts and beasts don't overlap
		var steps: Array = []
		var length := 0.0
		for k in range(0, base.size(), 2):
			var dpt: float = (_spacing(base[k]["type"]) as Vector2).y
			if k + 1 < base.size():
				dpt = maxf(dpt, (_spacing(base[k + 1]["type"]) as Vector2).y)
			var step: float = maxf(GATHER_GAP, dpt * 0.8)
			steps.append(length + step * 0.5)
			length += step
		var head: Vector2 = tail + dir * length
		var placed: Array = []
		for k in base.size():
			var wide: float = maxf(LANE, (_spacing(base[k]["type"]) as Vector2).x * 0.45)
			var lane: float = wide if k % 2 == 0 else -wide
			var p: Vector2 = head - dir * float(steps[k / 2]) + side * (lane + lateral)
			placed.append({"type": base[k]["type"], "role": base[k]["role"], "pos": p, "yaw": atan2(-dir.x, -dir.y), "y": maxf(t.height_at(p), 0.0)})
		out["places"][d["id"]] = placed
		out["gathered"][d["id"]] = String(dep.get("to", ""))


## An army's figures in the order its standing layout builds them (so a gathered army keeps its figures).
func _base_order(d: Dictionary, in_fort: bool) -> Array:
	if in_fort:
		var slots: Array = Muster.army_slots(d)
		var centres: Array = []
		for i in slots.size():
			centres.append(Vector2.ZERO)
		return Muster.figures_at(slots, centres)
	return _formation(d, 44.0)


## An army's field formation (Kit.formation_blocks), slumped into a crowd when its owner keeps a flame (CW-8: the Candlewake's massing,
## Kit.slump); every other army's ranks as before.
func _formation(d: Dictionary, max_w: float) -> Array:
	var slots: Array = Kit.formation_blocks(d["blocks"], d["leaders"], max_w, d.get("extras", ["bearer"]))
	return Kit.slump(slots, String(d["id"])) if WickRules.has_wick(String(d.get("owner", ""))) else slots


# ------------------------------------------------------------------ entries: figures in MultiMeshes

func _make_entry(d: Dictionary, placed: Array, ghost: bool = false) -> Dictionary:
	var seat: int = UiPalette.seat_index(state, d["owner"], seats)
	var col: Color = UiPalette.seat_color(seat)
	var e := {"id": d["id"], "owner": d["owner"], "colour": col, "emblem": seat if seat >= 0 else Kit.EMBLEM_SHIELD, "figs": [], "types": {},
		"province": d["location"], "units": d.get("units", 0), "ruler": d.get("ruler", false), "ghost": ghost,
		"transformation": AscensionRules.transformation(state, String(d["owner"])) if state != null else ""}
	if bool(d.get("memory", false)):
		e["memory"] = true
		e["step"] = int(d.get("step", 0))
	if bool(d.get("stand_in", false)):
		e["stand_in"] = true
	if d.has("flame"):
		e["flame"] = int(d["flame"])  # CW-8
	_fill_entry(e, placed, ghost)
	return e


## (Re)builds an entry's MultiMeshes and figures for `placed` places ({"from_*"} keys give a figure a
## start for the re-form). Per unit type, one MultiMesh per distinct pose mesh.
func _fill_entry(e: Dictionary, placed: Array, ghost: bool = false) -> void:
	_free_meshes(e)
	e["types"] = {}
	e["figs"] = []
	var count := {}
	var order: Array = []
	for sl in placed:
		if not count.has(sl["type"]):
			order.append(sl["type"])
		count[sl["type"]] = int(count.get(sl["type"], 0)) + 1
	var col: Color = e["colour"]
	var lin: Color = col.srgb_to_linear()
	var memory: bool = bool(e.get("memory", false)) and not ghost ## M5-3: a remembered army, grey and translucent in its own material
	var parent: Node = ghost_root if ghost else (memory_root if memory else self)
	for t in order:
		## #125: a transformed faction's units wear their variant's model family (Models.variant_of)
		var vt := Models.variant_of(t, String(e.get("transformation", "")))
		var pm: Dictionary = {"ready": Models.figure_mesh(t, prefer_models, "ready", "", vt)} if (ghost or memory) else Models.pose_meshes(t, prefer_models, String(e["owner"]), vt)
		var groups := {}
		var mis: Array = []
		var by_mesh := {}
		for pose in Models.POSES:
			if not pm.has(pose):
				continue
			var fm: Dictionary = pm[pose]
			var mid: int = (fm["mesh"] as Mesh).get_instance_id()
			if by_mesh.has(mid):
				groups[pose] = by_mesh[mid]
				continue
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = fm["mesh"]
			mm.instance_count = count[t]
			for i in count[t]:
				mm.set_instance_custom_data(i, lin)
			var mi := MultiMeshInstance3D.new()
			mi.name = "%s_%s_%s" % [str(e["id"]).validate_node_name(), t, pose]
			mi.multimesh = mm
			if ghost:
				mi.material_override = _ghost_mat(col)
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			elif memory:
				mi.material_override = _memory_mat(int(e.get("step", 0)))
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			else:
				mi.material_override = _figure_mat(fm["tex"])
				if not fig_shadows:
					mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parent.add_child(mi)
			by_mesh[mid] = mis.size()
			groups[pose] = mis.size()
			mis.append(mi)
		e["types"][t] = {"groups": groups, "mis": mis, "lying": (not ghost) and (not memory) and Models.has_pose_model(t, "fallen", prefer_models, vt), "variant": vt}
	var k := 0
	for sl in placed:
		var f := {"type": sl["type"], "role": sl["role"],
			"pos": sl.get("from_pos", sl["pos"]), "yaw": sl.get("from_yaw", sl["yaw"]), "y": sl.get("from_y", sl["y"]),
			"hop": 0.0, "tilt": 0.0, "fall": float(sl.get("from_fall", 0.0)), "lunge": 0.0, "back": 0.0,
			"scale": float(sl.get("from_scale", 1.0)), "pose": String(sl.get("pose", "ready")),
			"from_pos": sl.get("from_pos", sl["pos"]), "from_yaw": sl.get("from_yaw", sl["yaw"]), "from_y": sl.get("from_y", sl["y"]),
			"from_scale": float(sl.get("from_scale", 1.0)), "from_fall": float(sl.get("from_fall", 0.0)),
			"to_pos": sl["pos"], "to_yaw": sl["yaw"], "to_y": sl["y"], "to_scale": float(sl.get("to_scale", 1.0)),
			"phase": Choreo.hash_phase(str(e["id"]), k)}
		if sl.has("in_path"):
			f["in_path"] = sl["in_path"]
			f["in_t0"] = sl["in_t0"]
			if sl.get("keep_scale", false):
				f["keep_scale"] = true
		e["figs"].append(f)
		k += 1
	_fill_wicks(e, ghost or memory)
	if memory and e.get("banner") != null:
		(e["banner"] as Node).queue_free() ## a memory carries no banner
		e["banner"] = null
	if not e.has("banner") or e["banner"] == null:
		if not ghost and not memory:
			var bn: Node3D = wv.make_banner(col, e["emblem"], 11.0, Vector2(5.2, 3.4))
			add_child(bn)
			e["banner"] = bn
		else:
			e["banner"] = null
	_sync(e)


func _figure_mat(tex: Texture2D) -> ShaderMaterial:
	var key := "fig:%d" % (tex.get_instance_id() if tex != null else 0)
	if not _mats.has(key):
		var m: ShaderMaterial = wv.model_mat(Color.WHITE, tex, -1.0, true)
		m.set_shader_parameter("fig_lift", 1.0)
		_mats[key] = m
	return _mats[key]


func _ghost_mat(col: Color) -> ShaderMaterial:
	var key := "ghost:%s" % col.to_html()
	if not _mats.has(key):
		var gm := ShaderMaterial.new()
		gm.shader = SH_GHOST
		gm.set_shader_parameter("team", col)
		_mats[key] = gm
	return _mats[key]


## M5-3: a remembered army's material for its fade step (Vision.ghost_alpha): grey and translucent, one per step.
func _memory_mat(step: int) -> ShaderMaterial:
	var key := "memory:%d" % step
	if not _mats.has(key):
		var mm := ShaderMaterial.new()
		mm.shader = SH_MEMORY
		mm.set_shader_parameter("alpha", Vision.ghost_alpha(step))
		_mats[key] = mm
	return _mats[key]


func _free_meshes(e: Dictionary) -> void:
	for t in (e.get("types", {}) as Dictionary).keys():
		for mi in e["types"][t]["mis"]:
			(mi as Node).queue_free()
	e["types"] = {}
	if e.get("wick") != null:
		(e["wick"] as Node).queue_free()
	e["wick"] = null


## CW-8 (design/CANDLEWAKE.md §10): an army that keeps a flame burns it on its regulars' wicks, one MultiMesh for the army: none for a
## ghost or a memory, an army with no flame (-1: a rival's out of clear sight) or no figure that burns (CandleFigures.burns).
func _fill_wicks(e: Dictionary, faded: bool) -> void:
	e["wick"] = null
	var look := CandleFigures.flame_look(int(e.get("flame", -1)))
	if faded or look.is_empty():
		return
	var n := 0
	var tops := {}
	for f in e["figs"]:
		if f["role"] == "unit" and CandleFigures.burns(String(f["type"])):
			n += 1
			tops[f["type"]] = Models.fx_top(String(f["type"]))  # where each type's wick ends (the row's "fx_anchor")
	if n == 0:
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = wick_mesh()
	mm.instance_count = n
	for i in n:
		mm.set_instance_custom_data(i, look["col"])
	var mi := MultiMeshInstance3D.new()
	mi.name = "%s_wicks" % str(e["id"]).validate_node_name()
	mi.multimesh = mm
	mi.material_override = wick_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	e["wick"] = mi
	e["wick_look"] = look
	e["wick_tops"] = tops


func _free_army(e: Dictionary) -> void:
	_free_meshes(e)
	if e.get("banner") != null:
		(e["banner"] as Node).queue_free()
		e["banner"] = null


## Writes every figure's state into its pose's MultiMesh (compacted: each pose draws only its own
## figures), and the banner onto the bearer.
func _sync(e: Dictionary) -> void:
	var counters := {}
	var wick_i := 0
	for t in e["types"].keys():
		var z: Array = []
		z.resize((e["types"][t]["mis"] as Array).size())
		z.fill(0)
		counters[t] = z
	for f in e["figs"]:
		var te: Dictionary = e["types"][f["type"]]
		var gi: int = int(te["groups"].get(f["pose"], 0))
		var lying: bool = f["pose"] == "fallen" and bool(te["lying"])
		var yaw: float = f["yaw"]
		var basis := Basis(Vector3.UP, yaw)
		if float(f["tilt"]) != 0.0:
			basis = basis * Basis(Vector3.RIGHT, f["tilt"])
		if float(f["fall"]) > 0.0 and not lying:
			basis = basis * Basis(Vector3.RIGHT, -float(f["fall"]) * PI * 0.5)
		var sc: float = f["scale"]
		var p: Vector2 = f["pos"]
		var push: float = float(f["lunge"]) - float(f["back"])
		if push != 0.0:
			p += Vector2(-sin(yaw), -cos(yaw)) * push
		var xf := Transform3D(basis.scaled(Vector3.ONE * maxf(sc * fig_scale * blend, 0.001)), Vector3(p.x, float(f["y"]) + float(f["hop"]) * fig_scale * blend, p.y))
		var arr: Array = counters[f["type"]]
		var idx: int = arr[gi]
		arr[gi] = idx + 1
		((te["mis"][gi] as MultiMeshInstance3D).multimesh).set_instance_transform(idx, xf)
		if e.get("wick") != null and f["role"] == "unit" and CandleFigures.burns(String(f["type"])):
			## CW-8: its flame on its wick, out with the figure when it falls or fades
			var look: Dictionary = e["wick_look"]
			var lit := 0.0 if (sc < 0.05 or float(f["fall"]) > 0.5) else 1.0
			var wsz := Vector3(float(look["w"]), float(look["h"]), float(look["w"])) * maxf(sc * fig_scale * blend * lit, 0.001)
			(e["wick"] as MultiMeshInstance3D).multimesh.set_instance_transform(wick_i, Transform3D(basis.orthonormalized().scaled(wsz), xf * (e["wick_tops"][f["type"]] as Vector3)))
			wick_i += 1
		if f["role"] == "bearer" and e.get("banner") != null:
			var bn: Node3D = e["banner"]
			bn.transform = Transform3D(Basis(Vector3.UP, yaw + PI * 0.5).scaled(Vector3.ONE * maxf(fig_scale * blend, 0.001)), xf * Vector3(0.95, 1.2, 0.0))
			bn.visible = sc > 0.05 and float(f["fall"]) < 0.5 and blend > 0.02
	for t in e["types"].keys():
		var mis: Array = e["types"][t]["mis"]
		for gi in mis.size():
			var n: int = counters[t][gi]
			var mi: MultiMeshInstance3D = mis[gi]
			mi.multimesh.visible_instance_count = n
			mi.visible = n > 0 and blend > 0.01
	if e.get("wick") != null:
		(e["wick"] as MultiMeshInstance3D).visible = wick_i > 0 and blend > 0.01


## The middle of an army's standing figures and the height of its plate's foot (for its count plate),
## or Vector3(-99999, ...) when nothing of it stands.
func army_anchor(id: String) -> Vector3:
	if not armies.has(id):
		return Vector3(-99999, 0, 0)
	var e: Dictionary = armies[id]
	var sum := Vector3.ZERO
	var n := 0
	var top := -1.0e9
	for f in e["figs"]:
		if float(f["scale"]) < 0.05 or float(f["fall"]) > 0.5:
			continue
		var p: Vector2 = f["pos"]
		sum += Vector3(p.x, float(f["y"]), p.y)
		top = maxf(top, float(f["y"]))
		n += 1
	if n == 0:
		return Vector3(-99999, 0, 0)
	var mid: Vector3 = sum / float(n)
	return Vector3(mid.x, top + 13.0 * fig_scale, mid.z)


## Every standing figure of an army as [foot, head] world points (picking and plates).
func army_points(id: String) -> Array:
	var out: Array = []
	if not armies.has(id):
		return out
	for f in armies[id]["figs"]:
		if float(f["scale"]) < 0.05 or float(f["fall"]) > 0.5:
			continue
		var p: Vector2 = f["pos"]
		var y: float = f["y"]
		out.append([Vector3(p.x, y, p.y), Vector3(p.x, y + Kit.FIG * float(f["scale"]) * fig_scale, p.y)])
	return out


## VFX-WIRE (#242): the way army `id`'s figures face (its first standing figure's yaw), 0.0 when it has none on the board: a summoning
## ring under it turns with it.
func army_yaw(id: String) -> float:
	if not armies.has(id):
		return 0.0
	for f in armies[id]["figs"]:
		if float(f["scale"]) >= 0.05 and float(f["fall"]) <= 0.5:
			return float(f.get("yaw", 0.0))
	return 0.0


func figure_count() -> int:
	var n := 0
	for e in armies.values():
		n += (e["figs"] as Array).size()
	return n


## The draw groups the armies use now (MultiMeshInstances that draw), for the performance probe.
func draw_groups() -> int:
	var n := 0
	for e in armies.values():
		for t in e["types"].keys():
			for mi in e["types"][t]["mis"]:
				if (mi as Node3D).visible:
					n += 1
	return n


## What the board shows of the armies, for comparing two boards: army id -> {"owner", "province" (the
## land under its figures' middle), "figs": sorted ["type@x,z"] of every standing figure}.
func snapshot() -> Dictionary:
	var out := {}
	var t = wv.terrain
	for id in armies.keys():
		var e: Dictionary = armies[id]
		var figs: Array = []
		var sum := Vector2.ZERO
		var n := 0
		for f in e["figs"]:
			if float(f["scale"]) < 0.5 or float(f["fall"]) > 0.5:
				continue
			var p: Vector2 = f["pos"]
			figs.append("%s@%.1f,%.1f" % [f["type"], p.x, p.y])
			sum += p
			n += 1
		if n == 0:
			continue
		figs.sort()
		out[id] = {"owner": e["owner"], "province": t.province_at(sum / float(n)), "figs": figs}
	return out


## Everything the board draws of the armies, ghosts, gathered columns and camps (the hotseat privacy
## test compares two of these): sorted lines of "what@x,z pose".
func full_snapshot() -> Array:
	var out: Array = []
	for id in armies.keys():
		for f in armies[id]["figs"]:
			var p: Vector2 = f["pos"]
			out.append("%s %s@%.1f,%.1f %s %.2f" % [id, f["type"], p.x, p.y, f["pose"], float(f["scale"])])
	for g in _ghost_entries:
		for f in g["figs"]:
			var p2: Vector2 = f["pos"]
			out.append("ghost %s@%.1f,%.1f" % [f["type"], p2.x, p2.y])
	for pid in camps.keys():
		for tn in camps[pid]["tents"]:
			var p3: Vector2 = tn["pos"]
			out.append("tent %s@%.1f,%.1f" % [pid, p3.x, p3.y])
	for aid in gathered.keys():
		out.append("gathered %s -> %s" % [aid, gathered[aid]])
	out.sort()
	return out


# ------------------------------------------------------------------ ghost recruits (planning)

## Compatibility: queued recruits as ghosts with no other plan (`list` [{"province", "owner", "types"}]).
func show_ghosts(list: Array) -> void:
	var ctx := plan_ctx.duplicate()
	ctx["ghosts"] = list
	if list.is_empty():
		ctx.erase("ghosts")
	show_plan(ctx)


func _set_ghosts(list: Array) -> void:
	for g in _ghost_entries:
		_free_army(g)
	_ghost_entries = []
	for gl in list:
		var figs: Array = gl["figs"]
		if figs.is_empty():
			continue
		var d := {"id": "~ghost_" + String(gl["province"]), "owner": gl["owner"], "location": gl["province"]}
		var ge := _make_entry(d, figs, true)
		ge["types_list"] = gl["types"]
		ge["where"] = figs[0].get("where", "yard")
		_ghost_entries.append(ge)


## The ghost blocks standing now: [{"province", "owner", "types", "anchor": Vector3 over them, "where"}].
func ghost_list() -> Array:
	var out: Array = []
	for g in _ghost_entries:
		var sum := Vector3.ZERO
		var top := -1.0e9
		var n := 0
		for f in g["figs"]:
			var p: Vector2 = f["pos"]
			sum += Vector3(p.x, float(f["y"]), p.y)
			top = maxf(top, float(f["y"]))
			n += 1
		if n == 0:
			continue
		## the plate stands over the first ghost (the slot the first queued recruit takes)
		var f0: Dictionary = g["figs"][0]
		var p0: Vector2 = f0["pos"]
		out.append({"province": g["province"], "owner": g["owner"], "types": g.get("types_list", []),
			"anchor": Vector3(p0.x, top + 10.0 * fig_scale, p0.y), "where": g.get("where", "yard")})
	return out


func ghost_count() -> int:
	var n := 0
	for g in _ghost_entries:
		n += (g["figs"] as Array).size()
	return n


## M5-3: the remembered armies standing now (a fog game): army id -> {"province", "step" (how many fade steps old), "alpha", "figs"},
## apart from the queued recruits' ghosts (ghost_count stays exact).
func memory_list() -> Dictionary:
	var out := {}
	for id in armies.keys():
		var e: Dictionary = armies[id]
		if bool(e.get("memory", false)):
			var step := int(e.get("step", 0))
			out[id] = {"province": e["province"], "step": step, "alpha": Vision.ghost_alpha(step), "figs": (e["figs"] as Array).size()}
	return out


## M5-3: the rival stand-ins standing now (a fog game), memories included: army id -> true for a memory, false for a sighting.
func stand_in_list() -> Dictionary:
	var out := {}
	for id in armies.keys():
		var e: Dictionary = armies[id]
		if bool(e.get("stand_in", false)):
			out[id] = bool(e.get("memory", false))
	return out


## Where every ghost figure stands now: [{"type", "pos", "province"}] (tests).
func ghost_points() -> Array:
	var out: Array = []
	for g in _ghost_entries:
		for f in g["figs"]:
			out.append({"type": f["type"], "pos": f["pos"], "province": g["province"]})
	return out


# ------------------------------------------------------------------ war camps

## Builds the camps' tents (a MultiMesh per style: the owner's faction), fires and smoke. A model-table
## row "camp" (or "camp.<faction>") with a model on disk replaces the primitive tent.
func _set_camps(c: Dictionary) -> void:
	camps = c
	var key := JSON.stringify(c.keys()) + str(c.hash())
	if key == _camp_key:
		return
	_camp_key = key
	_engines.clear()
	for ch in camp_root.get_children():
		ch.queue_free()
	if c.is_empty():
		return
	var by_style := {}
	var fires: Array = []
	var works := {} ## M3c S-4: "kind|style" -> the siege works and engines standing at besieged forts
	for pid in c.keys():
		for tn in c[pid]["tents"]:
			var st := String(tn["style"])
			if not by_style.has(st):
				by_style[st] = []
			by_style[st].append(tn)
		fires.append_array(c[pid]["fires"])
		for wk in c[pid].get("works", []):
			var wkey := "%s|%s" % [wk["kind"], wk["style"]]
			if not works.has(wkey):
				works[wkey] = []
			works[wkey].append(wk)
	for wkey in works.keys():
		_build_works(String(wkey).get_slice("|", 0), String(wkey).get_slice("|", 1), works[wkey])
	for st in by_style.keys():
		var list: Array = by_style[st]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		var glb: Dictionary = Models.building_model("camp", st)
		var row: Dictionary = Models.building_row("camp", st)
		var sc := 1.0
		var lift := Vector3.ZERO
		if not glb.is_empty():
			var aabb: AABB = glb["aabb"]
			mm.mesh = glb["mesh"]
			sc = Muster.SLOT.x / maxf(maxf(aabb.size.x, aabb.size.z), 0.01)
			lift = Vector3(-aabb.get_center().x, -aabb.position.y, -aabb.get_center().z) * sc
		else:
			mm.mesh = Kit.tent(st)
		mm.instance_count = list.size()
		for i in list.size():
			var tn: Dictionary = list[i]
			var p: Vector2 = tn["pos"]
			var yaw: float = float(tn["yaw"]) + (deg_to_rad(float(row.get("yaw", 180.0))) if not glb.is_empty() else 0.0)
			var b := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * sc)
			mm.set_instance_transform(i, Transform3D(b, Vector3(p.x, float(tn["y"]) - 0.1, p.y) + Basis(Vector3.UP, yaw) * lift))
			mm.set_instance_custom_data(i, (tn["colour"] as Color).srgb_to_linear())
		var mi := MultiMeshInstance3D.new()
		mi.name = "Tents_" + st
		mi.multimesh = mm
		mi.material_override = wv.model_mat(Color.WHITE, glb.get("tex"), float(row.get("key_hue", -1.0)) if not glb.is_empty() else -1.0, true, 0.9, Color.WHITE, 1.0)
		camp_root.add_child(mi)
	if fires.is_empty():
		return
	var fm := MultiMesh.new()
	fm.transform_format = MultiMesh.TRANSFORM_3D
	fm.use_custom_data = true
	fm.mesh = Kit.campfire()
	fm.instance_count = fires.size()
	var sm := MultiMesh.new()
	sm.transform_format = MultiMesh.TRANSFORM_3D
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	sm.mesh = quad
	sm.instance_count = fires.size() * SMOKE_PUFFS
	for i in fires.size():
		var fp: Vector3 = fires[i]
		fm.set_instance_transform(i, Transform3D(Basis(), fp))
		fm.set_instance_custom_data(i, Color.WHITE)
		for k in SMOKE_PUFFS:
			sm.set_instance_transform(i * SMOKE_PUFFS + k, Transform3D(Basis(), fp))
	var fmi := MultiMeshInstance3D.new()
	fmi.name = "Fires"
	fmi.multimesh = fm
	fmi.material_override = wv.model_mat(Color.WHITE, null, -1.0, true)
	camp_root.add_child(fmi)
	var smi := MultiMeshInstance3D.new()
	smi.name = "Smoke"
	smi.multimesh = sm
	var smat := ShaderMaterial.new()
	smat.shader = SH_SMOKE
	smi.material_override = smat
	smi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	camp_root.add_child(smi)


## M3c S-4: a besieger's siege works or engines (`kind` "siege_works" or "siege_engine") in `style` (its faction's
## kit): the model table's model, else the code primitive, in one MultiMesh with the besieger's colour on its team
## parts. The engines are kept so a strike beat can lunge them at the walls (_strike_engines).
func _build_works(kind: String, style: String, list: Array) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var glb: Dictionary = Models.building_model(kind, style)
	var row: Dictionary = Models.building_row(kind, style)
	var sc := 1.0
	var lift := Vector3.ZERO
	if not glb.is_empty():
		var aabb: AABB = glb["aabb"]
		mm.mesh = glb["mesh"]
		sc = float(row.get("side", 10.0)) / maxf(maxf(aabb.size.x, aabb.size.z), 0.01)
		lift = Vector3(-aabb.get_center().x, -aabb.position.y, -aabb.get_center().z) * sc
	else:
		mm.mesh = Models.building_primitive(kind, style)
	mm.instance_count = list.size()
	for i in list.size():
		var wk: Dictionary = list[i]
		var p: Vector2 = wk["pos"]
		var yaw: float = float(wk["yaw"]) + (deg_to_rad(float(row.get("yaw", 180.0))) if not glb.is_empty() else 0.0)
		var xf := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * sc), Vector3(p.x, float(wk["y"]) - 0.1, p.y) + Basis(Vector3.UP, yaw) * lift)
		mm.set_instance_transform(i, xf)
		mm.set_instance_custom_data(i, (wk["colour"] as Color).srgb_to_linear())
		if kind == "siege_engine":
			_engines.append({"mm": mm, "i": i, "xf": xf, "fwd": Vector3(-sin(float(wk["yaw"])), 0, -cos(float(wk["yaw"]))), "pos": p})
	var mi := MultiMeshInstance3D.new()
	mi.name = "%s_%s" % [kind.capitalize().replace(" ", ""), style]
	mi.multimesh = mm
	mi.material_override = wv.model_mat(Color.WHITE, glb.get("tex"), float(row.get("key_hue", -1.0)) if not glb.is_empty() else -1.0, true, 0.92, Color.WHITE, 1.0)
	camp_root.add_child(mi)


## M3c S-4: the engines at `province_id`'s walls lunge `k` (0..1) of a stroke toward them (a strike beat).
func _strike_engines(province_id: String, k: float) -> void:
	var y: Dictionary = wv.yard_of(province_id, state)
	if y.is_empty():
		return
	for en in _engines:
		if (en["pos"] as Vector2).distance_to(y["centre"]) > float(y["radius"]) + 12.0:
			continue
		var xf: Transform3D = en["xf"]
		(en["mm"] as MultiMesh).set_instance_transform(int(en["i"]), Transform3D(xf.basis, xf.origin + (en["fwd"] as Vector3) * 2.2 * k))


## M3c S-4: the besieging armies camped round `province_id`'s walls, sorted ([] with no siege there).
func ring_of(province_id: String) -> Array:
	return ((rings.get(province_id, {}) as Dictionary).get("camps", []) as Array).duplicate()


## M3c S-4: how many tents stand in `province_id`'s camp ring.
func ring_tents(province_id: String) -> int:
	var n := 0
	for tn in (camps.get(province_id, {}) as Dictionary).get("tents", []):
		if bool(tn.get("ring", false)):
			n += 1
	return n


## Every army's figures where they stand now: {army id: [{"type", "pos", "y"}]} (tests).
func full_snapshot_by_army() -> Dictionary:
	var out := {}
	for id in armies.keys():
		var list: Array = []
		for f in armies[id]["figs"]:
			list.append({"type": f["type"], "pos": f["pos"], "y": f["y"]})
		out[id] = list
	return out


## How many tents stand in war camps now (tests, the legend).
func tent_count() -> int:
	var n := 0
	for pid in camps.keys():
		n += (camps[pid]["tents"] as Array).size()
	return n


# ------------------------------------------------------------------ turn playback

## Plays a resolved turn: `plan` is Playback.plan(before, events, after). Re-stands `before` with the
## turn's marching armies gathered at their gates, then plays the phases (see the top). Ends standing the
## state after; emits playback_finished.
func play(plan: Dictionary, before: GameState, after: GameState) -> void:
	var departing := {}
	for m in plan.get("marches", []):
		var hops: Array = m["hops"]
		if hops.size() >= 2 and not m.has("alias_of"):
			departing[m["army"]] = {"to": hops[hops.size() - 1], "via": hops[1] if hops.size() > 2 else ""}
	_set_ghosts([])
	show_state(before, seats, {"departing": departing})
	## M5-3: a rival column the viewer saw march (Playback.plan's seen marches) is its stand-in's block, under an alias, so
	## the view after's stand-ins (new ids, or the same ids at other places) fade in beside it as it walks off and fades
	for m in plan.get("marches", []):
		if m.has("alias_of") and armies.has(String(m["alias_of"])):
			armies[String(m["army"])] = armies[String(m["alias_of"])]
			armies.erase(String(m["alias_of"]))
	var t = wv.terrain
	var lay_after := layout_of(after)
	var dest: Dictionary = lay_after["places"]
	var battles: Array = plan.get("battles", [])
	var marches: Array = plan.get("marches", [])
	var march_of := {}
	for m in marches:
		march_of[m["army"]] = m
	var stops := {} ## army id -> [battle indices it fights in, in order]
	for bi in battles.size():
		for aid in battles[bi]["armies"]:
			if not stops.has(aid):
				stops[aid] = []
			stops[aid].append(bi)
	var beats: Array = []
	var T0 := 0.35
	## M5-3: the rituals phase (before movement): each ritual's beat starts where the viewer may see it start (a cast of the
	## viewer's own: at its caster; one from a hidden caster: at its target), and falls at its target. M5-9: the marches begin
	## after the phase (MagicBeats.span), each beat carries its plan beat for the effects, and the enchantments phase's come later.
	var ritual_i := 0
	var ritual_beats: Array = MagicBeats.early(plan.get("rituals", []))
	for r in ritual_beats:
		beats.append({"kind": "ritual", "t": 0.05 + MagicBeats.gap(ritual_beats.size()) * ritual_i, "phase": "rituals", "index": ritual_i, "from": String(r.get("from", "")),
			"at": String(r.get("at", "")), "ritual": String(r.get("ritual", "")), "province": String(r.get("at", "")), "beat": r})
		ritual_i += 1
	T0 += MagicBeats.span(ritual_beats.size())
	## the full way of every march, and where it is cut for its battles
	var ways := {}
	for m in marches:
		var aid: String = m["army"]
		if not armies.has(aid):
			continue
		var hops: Array = m["hops"]
		if hops.size() < 2 or t.index_of(hops[0]) < 0 or t.index_of(hops[hops.size() - 1]) < 0:
			continue
		ways[aid] = _way(armies[aid], hops, bool(m["to_border"]))
	## each battle's geometry: its front, every army's line
	var geo: Array = []
	for bi in battles.size():
		geo.append(_battle_geometry(battles[bi], ways))
	## Movement: every march to its first stop (its first battle's line, or its place in the state after)
	var t_move_end := T0
	var arrive := {} ## army id -> when its column stands at its current stop
	var rest := {} ## army id -> the way left after its current stop
	if not ways.is_empty():
		beats.append({"kind": "march", "t": T0, "phase": "movement"})
	for aid in ways.keys():
		var e: Dictionary = armies[aid]
		var way: PackedVector2Array = ways[aid]
		var st: Array = stops.get(aid, [])
		var target: Array
		var way1: PackedVector2Array = way
		if not st.is_empty():
			var g0: Dictionary = geo[st[0]]
			var cut: float = float(g0["cut"].get(aid, -1.0))
			if cut >= 0.0:
				way1 = _cut_way(way, cut)
				rest[aid] = _rest_way(way, cut)
			target = g0["lines"].get(aid, [])
		elif bool(march_of[aid]["survived"]):
			target = dest.get(aid, [])
		else:
			target = _line_slots(e, way[way.size() - 1], (way[way.size() - 1] - way[maxi(0, way.size() - 2)]).normalized(), 0.0)
		var sched: Array = _march(e, way1, target, T0)
		var arr := T0
		for s in sched:
			_add_leg(s["fig"], s)
			arr = maxf(arr, float(s["t_arrive"]))
		arrive[aid] = arr
		t_move_end = maxf(t_move_end, arr)
	## Battles, in the report's order
	var clashes: Array = []
	var cursor: float = (t_move_end + PHASE_GAP) if not ways.is_empty() else T0
	var pending_walk: Array = [] ## [army id] province battles' winners: they take the land in the captures phase
	var strike_i := 0
	var fall_i := 0
	var battles_end := cursor
	var clashes_end := cursor
	var march_on := {} ## province id -> when the winners marching on from a border battle arrive there
	for bi in battles.size():
		var b: Dictionary = battles[bi]
		var g: Dictionary = geo[bi]
		var ready := cursor
		for aid in b["armies"]:
			if arrive.has(aid) and ways.has(aid):
				ready = maxf(ready, float(arrive[aid]))
		## M3c S-4: a sally (or the garrison coming out with a relief) spills out of the gate in a column two abreast
		## and forms up facing the camps
		var sallied := {}
		var sg2: Dictionary = b.get("siege", {})
		if String(sg2.get("kind", "")) == "open" and g.has("yard"):
			var yd: Dictionary = g["yard"]
			var gpts: Array = yd["gate"]
			var gate_way := PackedVector2Array([gpts[0], gpts[1], (gpts[1] as Vector2) + (yd["gate_dir"] as Vector2) * 5.0])
			for aid in sg2.get("from_inside", []):
				if ways.has(aid) or not armies.has(aid) or not g["lines"].has(aid):
					continue
				var arr_s := cursor
				for sc in _march(armies[aid], gate_way, g["lines"][aid], cursor):
					_add_leg(sc["fig"], sc)
					arr_s = maxf(arr_s, float(sc["t_arrive"]))
				ready = maxf(ready, arr_s)
				sallied[aid] = true
		var tb := ready
		## defenders (they did not march) step out to their line
		for aid in b["armies"]:
			if ways.has(aid) or sallied.has(aid) or not armies.has(aid) or not g["lines"].has(aid):
				continue
			var e2: Dictionary = armies[aid]
			var line: Array = g["lines"][aid]
			for i in mini(line.size(), (e2["figs"] as Array).size()):
				var f: Dictionary = e2["figs"][i]
				var sl: Dictionary = line[i]
				_add_leg(f, {"kind": "walk", "t0": tb - STEP_OUT, "t1": tb - 0.1, "from": f["pos"], "to": sl["pos"],
					"from_y": f["y"], "to_y": sl["y"], "to_yaw": sl["yaw"]})
		var rec := {"at": t.ground_at(g["front"]), "t0": tb, "t1": tb + CLASH, "label": Playback.battle_label(b, before),
			"index": bi, "front": g["front"], "line": String(b.get("text", ""))}
		clashes.append(rec)
		beats.append({"kind": "clash", "t": tb, "phase": "battles", "index": bi})
		var losses := _battle_figures(b, g, after, tb)
		## the exchange's beats: alternating volleys, then the fallen
		for v in 3:
			beats.append({"kind": "strike", "t": tb + 0.25 + v * 0.4 + Choreo.LUNGE_TIME * 0.5, "phase": "battles", "index": strike_i})
			strike_i += 1
		if losses > 0:
			beats.append({"kind": "fall", "t": tb + CLASH * 0.5, "phase": "battles", "index": fall_i})
			fall_i += 1
		## the winners march on: a border battle's to their destination (or their next battle)
		for aid in b["armies"]:
			if not ways.has(aid) or b["destroyed"].has(aid) or not bool(march_of[aid]["survived"]):
				continue
			var st2: Array = stops.get(aid, [])
			var at_k: int = st2.find(bi)
			if at_k < 0:
				continue
			var e3: Dictionary = armies[aid]
			var nxt: int = st2[at_k + 1] if at_k + 1 < st2.size() else -1
			if rest.has(aid):
				var way2: PackedVector2Array = rest[aid]
				var target2: Array
				if nxt >= 0:
					var gn: Dictionary = geo[nxt]
					var cut2: float = float(gn["cut"].get(aid, -1.0))
					if cut2 >= 0.0:
						var off: float = _lens(ways[aid])[_lens(ways[aid]).size() - 1] - _lens(way2)[_lens(way2).size() - 1]
						rest[aid] = _rest_way(ways[aid], cut2)
						way2 = _cut_way(way2, maxf(0.0, cut2 - off))
					else:
						rest.erase(aid)
					target2 = gn["lines"].get(aid, [])
				else:
					rest.erase(aid)
					target2 = dest.get(aid, [])
				var sched2: Array = _march(e3, way2, target2, tb + CLASH, true)
				var arr2: float = tb + CLASH
				for s in sched2:
					_add_leg(s["fig"], s)
					arr2 = maxf(arr2, float(s["t_arrive"]))
				arrive[aid] = arr2
				if nxt < 0:
					battles_end = maxf(battles_end, arr2)
					var hops3: Array = march_of[aid]["hops"]
					var dest_p: String = hops3[hops3.size() - 1]
					march_on[dest_p] = maxf(float(march_on.get(dest_p, 0.0)), arr2)
			elif nxt < 0:
				pending_walk.append(aid)
		cursor = tb + BATTLE_STEP
		battles_end = maxf(battles_end, tb + CLASH)
		clashes_end = maxf(clashes_end, tb + CLASH)
	## the fallen that never marched or fought on screen (a ruler that died): they topple with the last battle
	for aid in plan.get("fallen", {}).keys():
		if not armies.has(aid):
			continue
		for f in armies[aid]["figs"]:
			if not f.has("die_at"):
				f["die_at"] = battles_end - 0.6 + Choreo.hash01(aid, int(f["phase"] * 100.0)) * 0.3
	## Sieges (M3c S-4, §10.2): each fort beat of the sieges phase in the report's order, at its fort; the forts'
	## looks, camps and chevrons change as each beat plays (step_playback: _fort_camps, _apply_fort)
	var fort_steps: Array = []
	var t_s0: float = (battles_end + PHASE_GAP) if not battles.is_empty() else ((t_move_end + PHASE_GAP) if not ways.is_empty() else T0)
	var ts := t_s0
	var fort_i := 0
	for fb in plan.get("forts", []):
		if String(fb["phase"]) != "sieges":
			continue
		var fkind := String(Choreo.FORT_BEATS.get(fb["kind"], ""))
		var dur: float = BREACH_BEAT if fb["kind"] == "walls_breached" else SIEGE_BEAT
		fort_steps.append({"t": ts, "apply": ts + dur * 0.7, "t1": ts + dur, "beat": fb, "kind": fkind, "index": fort_i})
		beats.append({"kind": fkind, "t": ts, "phase": "sieges", "index": fort_i, "province": _heard_at(fb)})
		if fb["kind"] in ["siege_started", "walls_damaged"]:
			_siege_strikes(fb, ts, dur)
		fort_i += 1
		ts += dur
	var t_s_end := ts
	## Captures: the new owner's colour sweeps out from its arriving column
	var t_c0: float = (t_s_end + PHASE_GAP) if not fort_steps.is_empty() else ((battles_end + PHASE_GAP) if not battles.is_empty() else (t_move_end + PHASE_GAP))
	var caps: Array = []
	var caps_list: Array = plan.get("captures", [])
	for i in caps_list.size():
		var c: Dictionary = caps_list[i]
		var origin: Vector2 = t.centre_of(c["province"]) if t.index_of(c["province"]) >= 0 else Vector2.ZERO
		for aid in ways.keys():
			var hops2: Array = march_of[aid]["hops"]
			if armies[aid]["owner"] == c["owner"] and hops2[hops2.size() - 1] == c["province"] and bool(march_of[aid]["survived"]):
				var w: PackedVector2Array = ways[aid]
				origin = w[w.size() - 1]
				break
		var tc: float = t_c0 + i * CAPTURE_STEP
		caps.append({"province": c["province"], "owner": c["owner"], "t": tc, "done": false, "from": origin, "kind": c.get("kind", "captured")})
		beats.append({"kind": "capture", "t": tc, "phase": "capture", "index": i, "province": _heard_at(c)})
	for aid in pending_walk:
		var e4: Dictionary = armies[aid]
		var target3: Array = dest.get(aid, [])
		var used := {}
		for f in e4["figs"]:
			var best := -1
			var best_d := 1.0e18
			for q in target3.size():
				if used.has(q) or target3[q]["type"] != f["type"]:
					continue
				var d2: float = (target3[q]["pos"] as Vector2).distance_squared_to(f["to_pos"])
				if d2 < best_d:
					best_d = d2
					best = q
			if best < 0:
				continue
			used[best] = true
			var sl2: Dictionary = target3[best]
			_add_leg(f, {"kind": "walk", "t0": t_c0 - 0.2, "t1": t_c0 + 1.6, "from": f["to_pos"], "to": sl2["pos"],
				"from_y": f["to_y"], "to_y": sl2["y"], "to_yaw": sl2["yaw"]})
	var t_c_end: float = t_c0
	if not caps.is_empty():
		t_c_end = t_c0 + (caps.size() - 1) * CAPTURE_STEP + SWEEP_TIME
	## a site razed in capture collapses as its province's colour sweeps in
	for fb2 in plan.get("forts", []):
		if String(fb2["phase"]) != "capture":
			continue
		var tr: float = t_c0
		for cp in caps:
			if cp["province"] == fb2["province"]:
				tr = float(cp["t"]) + 0.3
		var k2 := String(Choreo.FORT_BEATS.get(fb2["kind"], ""))
		fort_steps.append({"t": tr, "apply": tr + 0.2, "t1": tr + SIEGE_BEAT, "beat": fb2, "kind": k2, "index": fort_i})
		beats.append({"kind": k2, "t": tr, "phase": "capture", "index": fort_i, "province": _heard_at(fb2)})
		fort_i += 1
		t_c_end = maxf(t_c_end, tr + SIEGE_BEAT)
	if not pending_walk.is_empty():
		t_c_end = maxf(t_c_end, t_c0 + 1.6)
	## every leg done before the re-form
	var last_leg := 0.0
	for e5 in armies.values():
		for f in e5["figs"]:
			for lg in f.get("legs", []):
				last_leg = maxf(last_leg, float(lg.get("t_arrive", lg.get("t1", 0.0))))
	var t_reform: float = maxf(t_c_end, last_leg) + PHASE_GAP * 0.5
	## the phases and their captions
	var phases: Array = []
	if not ways.is_empty():
		var n_m: int = ways.size()
		phases.append({"key": "movement", "t0": T0, "t1": t_move_end,
			"detail": ("1 army marches" if n_m == 1 else "%d armies march" % n_m) + ("" if battles.is_empty() else " to battle" if battles.size() == n_m else "")})
	if not battles.is_empty():
		phases.append({"key": "battles", "t0": clashes[0]["t0"] - 0.2, "t1": clashes_end, "detail": clashes[0]["label"]})
		if not march_on.is_empty() and battles_end > clashes_end + 0.8:
			var names: Array = []
			var mk: Array = march_on.keys()
			mk.sort()
			for pid in mk:
				var pp := after.find_province(pid)
				if pp != null:
					names.append(pp.name)
			phases.append({"key": "movement", "t0": clashes_end + 0.1, "t1": battles_end,
				"detail": "The winners march on to %s" % " and ".join(names) if not names.is_empty() else "The winners march on"})
	var sieges_steps: Array = fort_steps.filter(func(st): return st["beat"]["phase"] == "sieges")
	if not sieges_steps.is_empty():
		phases.append({"key": "sieges", "t0": t_s0 - 0.1, "t1": t_s_end, "detail": String(sieges_steps[0]["beat"]["label"])})
	if not caps.is_empty():
		phases.append({"key": "capture", "t0": t_c0 - 0.1, "t1": t_c_end, "detail": _capture_text(caps[0], after)})
	var recruits: Array = plan.get("recruits", [])
	var arrivals: Array = plan.get("arrivals", [])
	## scaffolding goes up where a fort was ordered, as the recruits come in
	var sites: Array = []
	for fb3 in plan.get("forts", []):
		if String(fb3["phase"]) != "recruitment":
			continue
		var tq: float = t_reform + 0.3 + sites.size() * 0.35
		var k3 := String(Choreo.FORT_BEATS.get(fb3["kind"], ""))
		fort_steps.append({"t": tq, "apply": tq + 0.1, "t1": tq + SIEGE_BEAT, "beat": fb3, "kind": k3, "index": fort_i})
		beats.append({"kind": k3, "t": tq, "phase": "recruitment", "index": fort_i, "province": _heard_at(fb3)})
		sites.append(fb3)
		fort_i += 1
	if not recruits.is_empty() or not arrivals.is_empty() or not sites.is_empty():
		var rdetail: String = _recruit_text(recruits, arrivals, after)
		if rdetail.is_empty():
			rdetail = String(sites[0]["label"])
		phases.append({"key": "recruitment", "t0": t_reform, "t1": t_reform + REFORM, "detail": rdetail})
	## M5-9: the magic phases. The rituals phase opens the turn; the enchantments phase closes it (blessings heal, curses bite, endings,
	## summons fade) and a summoning's creatures step out of their ring as the armies re-form.
	var late_beats: Array = MagicBeats.late(plan.get("rituals", []))
	var t_magic := 0.0
	for li in late_beats.size():
		var lb: Dictionary = late_beats[li]
		var tl := t_reform + 0.2 + MagicBeats.gap(late_beats.size()) * li
		beats.append({"kind": "ritual", "t": tl, "phase": String(lb.get("phase", "enchantments")), "index": ritual_i + li, "from": String(lb.get("from", "")),
			"at": String(lb.get("at", "")), "ritual": String(lb.get("ritual", "")), "province": String(lb.get("at", "")), "beat": lb})
		t_magic = maxf(t_magic, tl + 1.6)
	if not ritual_beats.is_empty():
		phases.insert(0, {"key": "rituals", "t0": 0.0, "t1": maxf(T0 - 0.1, 0.1), "detail": MagicBeats.detail(ritual_beats)})
	var ench_beats: Array = late_beats.filter(func(x): return String(x.get("phase", "")) == "enchantments")
	if not ench_beats.is_empty():
		phases.append({"key": "enchantments", "t0": t_reform + 0.2, "t1": t_magic, "detail": MagicBeats.detail(ench_beats)})
	var active: Array = []
	for aid in armies.keys():
		for f in armies[aid]["figs"]:
			if f.has("legs") or f.has("die_at") or f.has("battles"):
				active.append(aid)
				break
	beats.sort_custom(func(a, b): return float(a["t"]) < float(b["t"]))
	var march_i := 0
	for bt in beats:
		if bt["kind"] == "march":
			bt["index"] = march_i
			march_i += 1
	fort_steps.sort_custom(func(a, b): return float(a["t"]) < float(b["t"]))
	var t_end: float = maxf(t_reform + REFORM + TAIL, t_magic + TAIL)
	for st in fort_steps:
		t_end = maxf(t_end, float(st["t1"]) + TAIL)
	var fm := SiegeBoard.model_of(before)
	_play = {"t": 0.0, "clashes": clashes, "caps": caps, "t_march": t_move_end, "t_reform": t_reform,
		"t_end": t_end, "after": after, "dest": dest, "reformed": false, "plan": plan,
		"phases": phases, "beats": beats, "active": active, "recruit_beats": 0,
		## M3c S-4: the forts as they stand through the turn (SiegeBoard's part of the board model), stepped by
		## each fort beat; the camps and rings of the state after, which a siege's beats put up or fold
		"fort_steps": fort_steps, "fm": fm, "worked": SiegeBoard.worked_sites(fm.get("works", {})), "worked_done": false,
		"camps_after": lay_after["camps"], "rings_after": lay_after["rings"]}


## M5-3: the province a beat is heard at, for the board's sound gate (Board3D.sound_seen): the province of a PUBLIC beat (a rival's
## capture or fort the viewer was only told of: its event is rebuilt), "" for a beat of the viewer's own (a battle fought, a march, a
## recruit), which it always hears. Without fog nothing is rebuilt, so every beat is heard.
func _heard_at(beat_plan: Dictionary) -> String:
	return String(beat_plan.get("province", "")) if bool(beat_plan.get("rebuilt", false)) else ""


## M3c S-4: a siege's strike at the walls (siege_started, walls_damaged): the besieging armies turn to the walls and
## strike twice through the beat (the exchange's strike poses and lunges, with no enemy to recoil).
func _siege_strikes(fb: Dictionary, ts: float, dur: float) -> void:
	var y: Dictionary = wv.yard_of(String(fb["province"]), state)
	if y.is_empty():
		return
	var wall: Vector2 = y["centre"]
	for aid in fb.get("armies", []):
		if not armies.has(aid):
			continue
		var figs: Array = armies[aid]["figs"]
		for i in figs.size():
			var f: Dictionary = figs[i]
			var j: float = Choreo.hash01(String(aid), i + 3) * 0.12
			if not f.has("battles"):
				f["battles"] = []
			f["battles"].append({"t0": ts, "t1": ts + dur * 0.8, "face": wall, "strikes": [ts + 0.12 + j, ts + 0.52 + j],
				"recoils": [], "cheer": -1.0, "gap": 2.4})


## M3c S-4: a fort beat's camps: a siege that starts or goes on stands its ring as the state after has it (the tents
## go up, the works and engines take their places); a siege lifted or ended folds it.
func _fort_camps(st: Dictionary) -> void:
	var pid := String(st["beat"]["province"])
	var c: Dictionary = camps.duplicate()
	match String(st["beat"]["kind"]):
		"siege_started", "walls_damaged":
			var after_camp: Dictionary = (_play["camps_after"] as Dictionary).get(pid, {})
			if after_camp.is_empty():
				return
			c[pid] = after_camp
			rings[pid] = (_play["rings_after"] as Dictionary).get(pid, {})
		"siege_lifted", "siege_ended":
			c.erase(pid)
			rings.erase(pid)
		_:
			return
	_set_camps(c)


## M3c S-4: one fort beat onto the forts as they stand (SiegeBoard.apply_one, the event alone).
func _apply_fort(st: Dictionary) -> void:
	if st.has("applied") or _play.is_empty():
		return
	st["applied"] = true
	var fm: Dictionary = _play["fm"]
	if fm.is_empty():
		return
	SiegeBoard.apply_one(fm["forts"], fm["works"], fm["sieges"], st["beat"]["event"], _play["worked"])


## M3c S-4: the turn of work every site standing at the start of the turn got (it has no event), once.
func _work_sites() -> void:
	if _play.is_empty() or bool(_play["worked_done"]) or (_play["fm"] as Dictionary).is_empty():
		return
	_play["worked_done"] = true
	SiegeBoard.finish_work(_play["fm"]["works"], _play["worked"])


## M3c S-4: the board draws the forts as they stand now in the playback.
func _push_forts() -> void:
	if _play.is_empty() or (_play["fm"] as Dictionary).is_empty():
		return
	wv.show_forts(SiegeBoard.board_table(_play["fm"], wv.map_kits()), fort_colours())


## M3c S-4: the playback ends: every fort beat applied and the sites worked, so the forts stand as the state after's.
func _finish_forts() -> void:
	for st in _play.get("fort_steps", []):
		_apply_fort(st)
	_work_sites()
	_push_forts()
	_strike_engines_all(0.0)


func _strike_engines_all(k: float) -> void:
	for pid in rings.keys():
		_strike_engines(pid, k)


## Every faction's player colour (the chevrons, a rising fort's roofs).
func fort_colours() -> Dictionary:
	var out := {}
	if state != null:
		for f in state.factions:
			out[f.id] = _colour_of(f.id)
	return out


## Where a battle is fought and where each army stands for it: {"front": Vector2, "lines": army id ->
## [places], "cut": army id -> the distance along its way where its column stops}.
func _battle_geometry(b: Dictionary, ways: Dictionary) -> Dictionary:
	var t = wv.terrain
	var provs: Array = b["provinces"]
	var out := {"front": Vector2.ZERO, "lines": {}, "cut": {}}
	var by_owner := {}
	var approach := {} ## army id -> unit vector from the front toward where it comes from
	var front: Vector2
	if b["kind"] == "border_battle" and provs.size() >= 2:
		var x: Variant = t.crossing(provs[0], provs[1])
		front = (x as Vector2) if x != null else (t.centre_of(provs[0]) + t.centre_of(provs[1])) * 0.5
		for aid in b["armies"]:
			if not ways.has(aid):
				continue
			var way: PackedVector2Array = ways[aid]
			var lens := _lens(way)
			var dc := _nearest_along(way, lens, front)
			out["cut"][aid] = maxf(0.0, dc - LINE_BACK)
			var behind: Vector2 = _along(way, lens, maxf(0.0, dc - 12.0))[0]
			approach[aid] = (behind - front).normalized() if behind.distance_to(front) > 0.1 else Vector2(0, 1)
	else:
		var pid: String = provs[0] if not provs.is_empty() else ""
		var c: Vector2 = t.centre_of(pid) if t.index_of(pid) >= 0 else Vector2.ZERO
		var mean := Vector2.ZERO
		var defended := false
		for aid in b["armies"]:
			if ways.has(aid):
				var way2: PackedVector2Array = ways[aid]
				var last: Vector2 = way2[way2.size() - 1]
				mean += (last - c).normalized()
			elif armies.has(aid):
				defended = true
		mean = mean.normalized() if mean.length() > 0.01 else Vector2(0, 1)
		if defended and wv.fortresses.has(pid):
			var gp: Array = wv.gate_points(pid)
			front = (gp[1] as Vector2) + (wv.fortresses[pid]["gate_dir"] as Vector2) * 16.0
		elif defended:
			front = c + mean * (t.stage_r[t.index_of(pid)] * 0.4)
		else:
			front = c
		for aid in b["armies"]:
			if ways.has(aid):
				var way3: PackedVector2Array = ways[aid]
				var last2: Vector2 = way3[way3.size() - 1]
				approach[aid] = (last2 - front).normalized() if last2.distance_to(front) > 0.1 else mean
				out["cut"][aid] = -1.0
		## M3c S-4 (§10.2): a battle at a fort's walls. The fort owner's side stands on the gate's side of the front,
		## everyone else outside: a storm meets at the walls, a breach battle in the gap, a battle in the open
		## before the gate (a sally's armies file out of it to their line).
		var sg: Dictionary = b.get("siege", {})
		var yard: Dictionary = wv.yard_of(pid, state) if not sg.is_empty() else {}
		if not yard.is_empty():
			var gd: Vector2 = yard["gate_dir"]
			var gp2: Array = yard["gate"]
			match String(sg.get("kind", "")):
				"storm":
					front = (gp2[1] as Vector2) + gd * 2.0
				"breach":
					front = gp2[1]
				_:
					front = (gp2[1] as Vector2) + gd * 14.0
			var pp := state.find_province(pid) if state != null else null
			var fort_owner: String = pp.owner if pp != null else ""
			for aid in b["armies"]:
				if not armies.has(aid):
					continue
				approach[aid] = -gd if String(armies[aid]["owner"]) == fort_owner else gd
				if ways.has(aid):
					out["cut"][aid] = -1.0
			out["yard"] = yard
	## defenders face the attackers from the other side of the front
	var att := Vector2.ZERO
	for aid in approach.keys():
		att += approach[aid]
	for aid in b["armies"]:
		if not approach.has(aid):
			approach[aid] = (-att).normalized() if att.length() > 0.01 else Vector2(0, -1)
		var owner := ""
		if armies.has(aid):
			owner = armies[aid]["owner"]
		if not by_owner.has(owner):
			by_owner[owner] = []
		by_owner[owner].append(aid)
	## a side's armies stand shoulder to shoulder along the front, so the side reads as one battle line
	for owner in by_owner.keys():
		var list: Array = (by_owner[owner] as Array).filter(func(x): return armies.has(x))
		list.sort()
		if list.is_empty():
			continue
		var a: Vector2 = Vector2.ZERO
		for aid in list:
			a += approach[aid]
		a = a.normalized() if a.length() > 0.01 else approach[list[0]]
		var side := Vector2(-a.y, a.x)
		var widths: Array = []
		var total := 0.0
		for aid in list:
			var w: float = float(_line_across((armies[aid]["figs"] as Array).size())) * 4.0
			widths.append(w)
			total += w + 3.0
		total -= 3.0
		var x: float = -total * 0.5
		for i in list.size():
			var centre: Vector2 = front + side * (x + float(widths[i]) * 0.5)
			out["lines"][list[i]] = _line_slots(armies[list[i]], centre, -a, LINE_BACK)
			x += float(widths[i]) + 3.0
	out["front"] = front
	return out


## The exchange of one battle: every figure of its armies turns to the enemy, the sides strike in
## alternating volleys (the struck side recoils), the dead topple, the winners cheer. The dead: every
## figure of a destroyed army; of a survivor, the figures its blocks lose (front ones first). Returns how
## many fall.
func _battle_figures(b: Dictionary, g: Dictionary, after: GameState, tb: float) -> int:
	var sides := {}
	for aid in b["armies"]:
		if not armies.has(aid):
			continue
		var owner: String = armies[aid]["owner"]
		if not sides.has(owner):
			sides[owner] = []
		sides[owner].append(aid)
	var owners: Array = sides.keys()
	owners.sort()
	var centre := {}
	for owner in owners:
		var sum := Vector2.ZERO
		var n := 0
		for aid in sides[owner]:
			for s in g["lines"].get(aid, []):
				sum += s["pos"]
				n += 1
		centre[owner] = sum / float(maxi(n, 1))
	var fallen := 0
	for oi in owners.size():
		var owner: String = owners[oi]
		var enemy := Vector2.ZERO
		var ne := 0
		for o2 in owners:
			if o2 != owner:
				enemy += centre[o2]
				ne += 1
		enemy = enemy / float(maxi(ne, 1))
		var won: bool = String(b.get("winner", "")) == owner
		for aid in sides[owner]:
			var e: Dictionary = armies[aid]
			var dies := _dying(e, aid, b, after)
			var figs: Array = e["figs"]
			for i in figs.size():
				var f: Dictionary = figs[i]
				var jitter: float = Choreo.hash01(aid, i) * 0.12
				var strikes: Array = []
				var recoils: Array = []
				for v in 3:
					var tv: float = tb + 0.25 + v * 0.4
					if v % 2 == oi % 2:
						strikes.append(tv + jitter)
					else:
						recoils.append(tv + Choreo.LUNGE_TIME * 0.5 + jitter)
				var bt := {"t0": tb, "t1": tb + CLASH, "face": enemy, "strikes": strikes, "recoils": recoils,
					"cheer": (tb + CLASH - 0.55) if won else -1.0,
					"gap": clampf(enemy.distance_to(g["front"]) * 0.6, 3.0, 12.0)}
				if not f.has("battles"):
					f["battles"] = []
				f["battles"].append(bt)
				if dies.has(i) and not f.has("die_at"):
					f["die_at"] = tb + CLASH * 0.5 + Choreo.hash01(aid, i + 7) * 0.3
					fallen += 1
	return fallen


## The indices of an army's figures that die in battle `b`.
func _dying(e: Dictionary, aid: String, b: Dictionary, after: GameState) -> Dictionary:
	var out := {}
	var figs: Array = e["figs"]
	var a2: Army = after.find_army(aid)
	if a2 == null or b["destroyed"].has(aid):
		for i in figs.size():
			out[i] = true
		return out
	var want := {}
	for sl in _base_order(_desc_of(a2), false):
		want[sl["type"]] = int(want.get(sl["type"], 0)) + 1
	var have := {}
	for i in figs.size():
		var t: String = figs[i]["type"]
		have[t] = int(have.get(t, 0)) + 1
		if have[t] > int(want.get(t, 0)):
			out[i] = true
	return out


func _capture_text(c: Dictionary, after: GameState) -> String:
	var p := after.find_province(c["province"])
	var f := after.find_faction(c["owner"])
	var pn: String = p.name if p != null else "A province"
	var fname: String = f.faction_name if f != null else "a new owner"
	if c.get("kind", "") == "vassal_joined":
		return "%s swears fealty to the %s" % [pn, fname]
	return "%s is taken by the %s" % [pn, fname]


func _recruit_text(recruits: Array, arrivals: Array, after: GameState) -> String:
	var by := {}
	var order: Array = []
	for r in recruits:
		var pid: String = r["province"]
		if not by.has(pid):
			by[pid] = 0
			order.append(pid)
		by[pid] += 1
	var parts: Array = []
	for pid in order:
		var p := after.find_province(pid)
		parts.append("%s at %s" % ["1 recruit musters" if by[pid] == 1 else "%d recruits muster" % by[pid], p.name if p != null else "a province"])
	if not arrivals.is_empty():
		parts.append("a new ruler arrives")
	var text := ", ".join(parts)
	return text.substr(0, 1).to_upper() + text.substr(1) if not text.is_empty() else ""


func play_progress() -> float:
	return 0.0 if _play.is_empty() else clampf(float(_play["t"]) / float(_play["t_end"]), 0.0, 1.0)


func play_time() -> float:
	return 0.0 if _play.is_empty() else float(_play["t"])


func play_length() -> float:
	return 0.0 if _play.is_empty() else float(_play["t_end"])


## The phases of the playback: [{"key", "caption", "t0", "t1", "detail"}] (the playback bar's pips).
func phases() -> Array:
	var out: Array = []
	if _play.is_empty():
		return out
	var i := 0
	for p in _play["phases"]:
		out.append({"key": p["key"], "caption": Choreo.caption(p["key"]), "t0": p["t0"], "t1": p["t1"], "detail": p["detail"], "index": i})
		i += 1
	return out


## The phase playing now: {"key", "caption", "detail", "k" 0..1 through it, "line": during a battle, the turn
## report's own line for it (TurnReportText, the caption's tooltip)}, or {} between phases.
func phase_now() -> Dictionary:
	if _play.is_empty():
		return {}
	var now: float = _play["t"]
	var cur: Dictionary = {}
	var ci := -1
	var i := 0
	for p in _play["phases"]:
		if now >= float(p["t0"]) - 0.05:
			cur = p
			ci = i
		i += 1
	if cur.is_empty() or now > float(cur["t1"]) + 0.6:
		return {}
	var detail: String = cur["detail"]
	var line := ""
	if cur["key"] == "battles":
		for c in _play["clashes"]:
			if now >= float(c["t0"]) - 0.2:
				detail = c["label"]
				line = String(c.get("line", ""))
	elif cur["key"] == "capture":
		for c in _play["caps"]:
			if now >= float(c["t"]) - 0.05:
				detail = _capture_text(c, _play["after"])
	if cur["key"] in ["sieges", "capture", "recruitment"]:
		## M3c S-4: a fort beat names itself, and its turn report line lights up as it plays
		for st in _play.get("fort_steps", []):
			if String(st["beat"]["phase"]) == cur["key"] and now >= float(st["t"]) - 0.05:
				detail = String(st["beat"]["label"])
				line = String(st["beat"]["text"])
	var span: float = maxf(float(cur["t1"]) - float(cur["t0"]), 0.01)
	return {"key": cur["key"], "caption": Choreo.caption(cur["key"]), "detail": detail, "k": clampf((now - float(cur["t0"])) / span, 0.0, 1.0), "index": ci,
		"line": line}


## The beats of the playback: [{"kind", "t", "phase", "index"}] (tests and the board's sounds).
func beats() -> Array:
	return [] if _play.is_empty() else (_play["beats"] as Array).duplicate(true)


## The clash markers showing now: [{"at": Vector3, "k": 0..1 through the clash, "label"}].
func clashes_now() -> Array:
	var out: Array = []
	if _play.is_empty():
		return out
	var now: float = _play["t"]
	for c in _play["clashes"]:
		if now >= float(c["t0"]) and now <= float(c["t1"]) + 0.4:
			out.append({"at": c["at"], "k": clampf((now - float(c["t0"])) / CLASH, 0.0, 1.0), "label": c["label"]})
	return out


## Jumps to the end of the playback: the board stands the state after at once.
func skip() -> void:
	if _play.is_empty():
		return
	step_playback(float(_play["t_end"]) - float(_play["t"]) + 0.01, true)


## The column's way: out of the gate (or off the stage), over each border crossing (a road move goes
## through its middle province's centre), to the approach of the last province; a border battle's loser
## stops at the crossing.
func _way(e: Dictionary, hops: Array, to_border: bool) -> PackedVector2Array:
	var t = wv.terrain
	var from: String = hops[0]
	var to: String = hops[hops.size() - 1]
	var way := PackedVector2Array()
	var yard: Dictionary = wv.yard_of(from, state)
	var fp := state.find_province(from) if state != null else null
	if gathered.has(e["id"]) and not (e["figs"] as Array).is_empty():
		## gathered at the gate (or the stage's edge): the column marches on from its head
		way.append(e["figs"][0]["pos"])
	elif not yard.is_empty() and (fp == null or fp.owner == e["owner"]):
		## out of the gate (M3c S-4: any fort's, in a game with sieges); a besieger leaves from its camp
		var g: Array = yard["gate"]
		if _in_court(e, yard):
			way.append(g[0])
		way.append(g[1])
	else:
		var x0: Variant = t.crossing(hops[0], hops[1])
		var c0: Vector2 = t.centre_of(from)
		var dir0: Vector2 = (((x0 as Vector2) if x0 != null else t.centre_of(hops[1])) - c0).normalized()
		way.append(c0 + dir0 * (t.stage_r[t.index_of(from)] * 0.6))
	for k in range(hops.size() - 1):
		var x: Variant = t.crossing(hops[k], hops[k + 1])
		if x != null:
			way.append(x)
		if to_border:
			return way
		if k + 1 < hops.size() - 1:
			way.append(t.centre_of(hops[k + 1]))
	var cb: Vector2 = t.centre_of(to)
	var last: Vector2 = way[way.size() - 1]
	way.append(cb + (last - cb).normalized() * (t.stage_r[t.index_of(to)] * 0.9 + 6.0))
	return way


## Each figure's march along `way` from `t0`: nearest the way out first (a gathered column keeps its
## order, the banner at the head), two abreast, then to its place in `target` (same type, in order);
## `from_targets`: the march starts where the figures' last leg left them (a battle's winners marching on). Returns [{"fig", "kind": "column", "lane", "way", "lens", "t_dep", "t_enter",
## "t_exit", "t_arrive", "from", "from_y", "from_yaw", "to", "to_yaw", "to_y"}].
func _march(e: Dictionary, way: PackedVector2Array, target: Array, t0: float, from_targets: bool = false) -> Array:
	var t = wv.terrain
	var lens := _lens(way)
	var total: float = lens[lens.size() - 1]
	var order: Array = range((e["figs"] as Array).size())
	var start: Vector2 = way[0]
	var pos_of := func(f: Dictionary) -> Vector2: return (f["to_pos"] if from_targets else f["pos"]) as Vector2
	order.sort_custom(func(a, b): return (pos_of.call(e["figs"][a]) as Vector2).distance_to(start) < (pos_of.call(e["figs"][b]) as Vector2).distance_to(start))
	var sched: Array = []
	var shift := 0.0
	for k in order.size():
		var f: Dictionary = e["figs"][order[k]]
		var lead: float = (pos_of.call(f) as Vector2).distance_to(start) / SPEED
		shift = maxf(shift, lead - float(k / 2) * GAP / SPEED)
	var free: Array = target.duplicate()
	var end_c: Vector2 = way[way.size() - 1]
	for k in order.size():
		var f: Dictionary = e["figs"][order[k]]
		if f.has("die_at") and from_targets:
			continue
		var lane: float = LANE if k % 2 == 0 else -LANE
		var t_enter: float = t0 + shift + float(k / 2) * GAP / SPEED
		var p0: Vector2 = pos_of.call(f)
		var lead2: float = p0.distance_to(start) / SPEED
		var di := -1
		for q in free.size():
			if free[q]["type"] == f["type"]:
				di = q
				break
		if di < 0 and not free.is_empty():
			di = 0
		var goal: Dictionary = free[di] if di >= 0 else {"pos": end_c, "yaw": f["yaw"], "y": t.height_at(end_c)}
		if di >= 0:
			free.remove_at(di)
		var end_p: Vector2 = goal["pos"]
		var tail: float = way[way.size() - 1].distance_to(end_p)
		var y0: float = float(f["to_y"]) if from_targets else float(f["y"])
		sched.append({"fig": f, "kind": "column", "lane": lane, "way": way, "lens": lens, "total": total,
			"t_dep": t_enter - lead2, "t_enter": t_enter, "t_exit": t_enter + total / SPEED,
			"t_arrive": t_enter + total / SPEED + tail / SPEED, "from": p0, "from_y": y0, "from_yaw": f["yaw"],
			"to": end_p, "to_yaw": goal["yaw"], "to_y": goal["y"]})
		f["to_pos"] = end_p
		f["to_y"] = goal["y"]
		f["to_yaw"] = goal["yaw"]
	return sched


func _add_leg(f: Dictionary, leg: Dictionary) -> void:
	if not f.has("legs"):
		f["legs"] = []
	f["legs"].append(leg)
	if leg.get("kind", "") == "walk":
		f["to_pos"] = leg["to"]
		f["to_y"] = leg["to_y"]
		f["to_yaw"] = leg["to_yaw"]


func _in_court(e: Dictionary, yard: Dictionary) -> bool:
	if e["figs"].is_empty():
		return false
	var ct: Array = WorldView.court_of(yard)
	var g: Array = yard["gate"]
	var p: Vector2 = e["figs"][0]["pos"]
	return p.distance_to(ct[0]) < (g[1] as Vector2).distance_to(ct[0])


## A loose battle line for an army: rows across, centred `back` units behind `site` (against `f`, the
## way it faces), facing `f`.
func _line_slots(e: Dictionary, site: Vector2, f: Vector2, back: float) -> Array:
	var t = wv.terrain
	if f.length() < 0.01:
		f = Vector2(0, 1)
	f = f.normalized()
	var n: int = (e["figs"] as Array).size()
	var across: int = _line_across(n)
	var o: Vector2 = site - f * maxf(back, 3.0)
	var side := Vector2(-f.y, f.x)
	var out: Array = []
	var k := 0
	for fg in e["figs"]:
		var c: int = k % across
		var r: int = k / across
		var p: Vector2 = o + side * ((c - (across - 1) * 0.5) * 4.0) - f * (r * 4.4)
		out.append({"type": fg["type"], "pos": p, "yaw": atan2(-f.x, -f.y), "y": maxf(t.height_at(p), 0.0)})
		k += 1
	return out


## How many figures stand across in an army's battle line.
static func _line_across(n: int) -> int:
	return clampi(int(ceil(sqrt(n * 2.5))), 3, 10)


func _lens(pts: PackedVector2Array) -> PackedFloat32Array:
	var l := PackedFloat32Array([0.0])
	for i in range(1, pts.size()):
		l.append(l[i - 1] + pts[i - 1].distance_to(pts[i]))
	return l


func _along(pts: PackedVector2Array, lens: PackedFloat32Array, d: float) -> Array:
	d = clampf(d, 0.0, lens[lens.size() - 1])
	for i in range(1, pts.size()):
		if d <= lens[i] or i == pts.size() - 1:
			var seg: float = maxf(lens[i] - lens[i - 1], 0.001)
			var k: float = clampf((d - lens[i - 1]) / seg, 0.0, 1.0)
			return [pts[i - 1].lerp(pts[i], k), (pts[i] - pts[i - 1]).normalized()]
	return [pts[pts.size() - 1], Vector2(0, 1)]


## The distance along a way to the point of it nearest `p`.
func _nearest_along(pts: PackedVector2Array, lens: PackedFloat32Array, p: Vector2) -> float:
	var best := 0.0
	var best_d := 1.0e18
	for i in range(1, pts.size()):
		var a: Vector2 = pts[i - 1]
		var b: Vector2 = pts[i]
		var ab: Vector2 = b - a
		var k: float = clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var q: Vector2 = a + ab * k
		var d: float = q.distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = lens[i - 1] + ab.length() * k
	return best


## The way up to distance `d` along it.
func _cut_way(pts: PackedVector2Array, d: float) -> PackedVector2Array:
	var lens := _lens(pts)
	var out := PackedVector2Array()
	out.append(pts[0])
	for i in range(1, pts.size()):
		if lens[i] < d:
			out.append(pts[i])
		else:
			break
	var end: Vector2 = _along(pts, lens, d)[0]
	if out[out.size() - 1].distance_to(end) > 0.01:
		out.append(end)
	return out


## The way from distance `d` along it to its end.
func _rest_way(pts: PackedVector2Array, d: float) -> PackedVector2Array:
	var lens := _lens(pts)
	var out := PackedVector2Array()
	out.append(_along(pts, lens, d)[0])
	for i in range(1, pts.size()):
		if lens[i] > d + 0.01:
			out.append(pts[i])
	if out.size() < 2:
		out.append(pts[pts.size() - 1])
	return out


func _process(delta: float) -> void:
	clock += delta
	if _play.is_empty():
		return
	step_playback(delta * speed)


## Advances the playback by `delta` seconds of playback time (tests and the shot script step it).
func step_playback(delta: float, skipping: bool = false) -> void:
	if _play.is_empty():
		return
	_play["t"] = float(_play["t"]) + delta
	var now: float = _play["t"]
	## the marches, the battles' exchanges and the fallen
	if now < float(_play["t_reform"]) and not skipping:
		for id in _play["active"]:
			if not armies.has(id):
				continue
			var e: Dictionary = armies[id]
			for f in e["figs"]:
				_fig_step(f, now)
			_sync(e)
	## beats (the board's sounds): each once, never while skipping
	if not skipping:
		for bt in _play["beats"]:
			if not bt.get("fired", false) and now >= float(bt["t"]):
				bt["fired"] = true
				if bt["kind"] == "clash":
					var ci: int = int(bt.get("index", 0))
					if ci < (_play["clashes"] as Array).size():
						clash_started.emit(String(_play["clashes"][ci]["label"]))
				beat_province = String(bt.get("province", ""))
				if bt["kind"] == "ritual":
					if String((bt.get("beat", {}) as Dictionary).get("kind", "ritual_cast")) in ["ritual_cast", "ritual_turned_aside", "ritual_fell"]:
						ritual_beat.emit(String(bt.get("from", "")), String(bt.get("at", "")), String(bt.get("ritual", "")), int(bt.get("index", 0)))
					magic_beat.emit(bt.get("beat", {}), int(bt.get("index", 0)))
				beat.emit(String(bt["kind"]), int(bt.get("index", 0)))
				beat_province = ""
	## M3c S-4: the fort beats: the camps go up or fold as each fires, the forts' looks change at its end
	for st in _play.get("fort_steps", []):
		if not st.has("fired") and (now >= float(st["t"]) or skipping):
			st["fired"] = true
			if not skipping:
				fort_beat.emit(String(st["beat"]["province"]), String(st["kind"]), int(st["index"]))
			_fort_camps(st)
		if not st.has("applied") and (now >= float(st["apply"]) or skipping):
			_apply_fort(st)
			_push_forts()
		if not skipping and String(st["kind"]) in ["siege", "wall_hit"]:
			var dt: float = now - float(st["t"])
			_strike_engines(String(st["beat"]["province"]), absf(sin(dt * PI / 0.4)) if dt >= 0.0 and dt < 0.8 else 0.0)
	## the land changes hands: the sweep from the arriving column
	for c in _play["caps"]:
		if not c["done"] and (now >= float(c["t"]) or skipping):
			c["done"] = true
			if not skipping:
				capture_swept.emit(c["province"], c["owner"], c["from"])
			captured.emit(c["province"], c["owner"])
	## the re-form: every army to its place in the state after, recruits march in, the fallen go
	if now >= float(_play["t_reform"]) and not _play["reformed"]:
		_play["reformed"] = true
		_begin_reform()
	if _play["reformed"]:
		var k: float = 1.0 if skipping else smoothstep(0.0, 1.0, clampf((now - float(_play["t_reform"])) / REFORM, 0.0, 1.0))
		for e in armies.values():
			for f in e["figs"]:
				if f.has("in_path"):
					_march_in_step(f, now, skipping)
					continue
				var moving: bool = k < 1.0 and (f["from_pos"] as Vector2).distance_to(f["to_pos"]) > 2.0
				f["pos"] = (f["from_pos"] as Vector2).lerp(f["to_pos"], k)
				f["yaw"] = lerp_angle(float(f["from_yaw"]), float(f["to_yaw"]), k)
				f["y"] = lerpf(float(f["from_y"]), float(f["to_y"]), k)
				f["scale"] = lerpf(float(f["from_scale"]), float(f["to_scale"]), k)
				f["fall"] = lerpf(float(f.get("from_fall", 0.0)), 0.0, k) if float(f["to_scale"]) > 0.0 else float(f.get("from_fall", 0.0))
				f["lunge"] = 0.0
				f["back"] = 0.0
				f["tilt"] = 0.0
				if float(f["to_scale"]) > 0.0:
					var mo := Choreo.motion("march" if moving else "stand", now, float(f["phase"]))
					f["hop"] = mo["hop"] * (1.0 - k)
					f["pose"] = mo["pose"]
				else:
					f["hop"] = 0.0
			_sync(e)
	if now >= float(_play["t_end"]) or skipping:
		var after: GameState = _play["after"]
		_finish_forts()
		_play = {}
		if snap_at_end:
			show_state(after, seats)
		else:
			state = after
		playback_finished.emit()


## One figure at `now`, before the re-form: its legs (marches, steps), the battle exchanges over them,
## and its fall.
func _fig_step(f: Dictionary, now: float) -> void:
	f["lunge"] = 0.0
	f["back"] = 0.0
	if f.has("die_at") and now >= float(f["die_at"]):
		var mo := Choreo.motion("topple", now - float(f["die_at"]), float(f["phase"]))
		f["fall"] = mo["fall"]
		f["pose"] = mo["pose"]
		f["hop"] = 0.0
		f["tilt"] = 0.0
		return
	var moving := false
	var dir := Vector2.ZERO
	var legs: Array = f.get("legs", [])
	if not legs.is_empty():
		var leg: Dictionary = legs[0]
		for lg in legs:
			var st: float = float(lg.get("t_dep", lg.get("t0", 0.0)))
			if now >= st:
				leg = lg
		var r: Array = _leg_at(leg, now, f)
		f["pos"] = r[0]
		f["y"] = r[1]
		dir = r[2]
		moving = r[3]
		if moving and dir.length() > 0.01:
			f["yaw"] = lerp_angle(float(f["yaw"]), atan2(-dir.x, -dir.y), 0.35)
		elif not moving and now >= float(leg.get("t_arrive", leg.get("t1", 0.0))):
			f["yaw"] = lerp_angle(float(f["yaw"]), float(leg.get("to_yaw", f["yaw"])), 0.2)
	var mo2 := Choreo.motion("march" if moving else "stand", now, float(f["phase"]))
	f["hop"] = mo2["hop"]
	f["tilt"] = mo2["tilt"]
	f["pose"] = mo2["pose"]
	## a battle's exchange over it
	for bt in f.get("battles", []):
		if now < float(bt["t0"]) - 0.3 or now > float(bt["t1"]) + 0.2 or moving:
			continue
		var face: Vector2 = (bt["face"] as Vector2) - (f["pos"] as Vector2)
		if face.length() > 0.1:
			f["yaw"] = lerp_angle(float(f["yaw"]), atan2(-face.x, -face.y), 0.3)
		for ts in bt["strikes"]:
			var dt: float = now - float(ts)
			if dt >= 0.0 and dt < Choreo.LUNGE_TIME + Choreo.STRIKE_HOLD:
				var ms := Choreo.motion("strike", dt, float(f["phase"]))
				f["lunge"] = float(ms["lunge"]) * float(bt["gap"])
				f["pose"] = ms["pose"]
		for tr in bt["recoils"]:
			var dr: float = now - float(tr)
			if dr >= 0.0 and dr < Choreo.RECOIL:
				var mr := Choreo.motion("recoil", dr, float(f["phase"]))
				f["back"] = mr["back"]
				f["tilt"] = mr["tilt"]
		var ch: float = float(bt["cheer"])
		if ch >= 0.0 and now >= ch and now < ch + 0.55:
			var mc := Choreo.motion("cheer", now - ch, float(f["phase"]))
			f["hop"] = mc["hop"]
			f["pose"] = mc["pose"]


## A leg at `now`: [pos, y, direction of motion, moving].
func _leg_at(s: Dictionary, now: float, f: Dictionary) -> Array:
	var t = wv.terrain
	if s.get("kind", "column") == "walk":
		var t0: float = s["t0"]
		var t1: float = s["t1"]
		if now <= t0:
			return [s["from"], s["from_y"], Vector2.ZERO, false]
		if now >= t1:
			return [s["to"], s["to_y"], Vector2.ZERO, false]
		var k: float = (now - t0) / maxf(t1 - t0, 0.001)
		var p: Vector2 = (s["from"] as Vector2).lerp(s["to"], smoothstep(0.0, 1.0, k))
		return [p, lerpf(float(s["from_y"]), float(s["to_y"]), k), ((s["to"] as Vector2) - (s["from"] as Vector2)).normalized(), true]
	if now < float(s["t_dep"]):
		return [s["from"], s["from_y"], Vector2.ZERO, false]
	if now < float(s["t_enter"]):
		var k2: float = (now - float(s["t_dep"])) / maxf(float(s["t_enter"]) - float(s["t_dep"]), 0.001)
		var way: PackedVector2Array = s["way"]
		var w0: Vector2 = way[0]
		var w1: Vector2 = way[1] if way.size() > 1 else way[0] + Vector2(0, 1)
		var side: Vector2 = Vector2(-(w1 - w0).normalized().y, (w1 - w0).normalized().x) * float(s["lane"])
		var p2: Vector2 = (s["from"] as Vector2).lerp(w0 + side, k2)
		var y2: float = lerpf(float(s["from_y"]), maxf(t.height_at(p2), 0.0), k2 * k2) if k2 > 0.85 else float(s["from_y"])
		return [p2, y2, ((w0 + side) - (s["from"] as Vector2)).normalized(), true]
	if now < float(s["t_exit"]):
		var d: float = (now - float(s["t_enter"])) * SPEED
		var at: Array = _along(s["way"], s["lens"], d)
		var dir: Vector2 = at[1]
		var p3: Vector2 = (at[0] as Vector2) + Vector2(-dir.y, dir.x) * float(s["lane"])
		return [p3, maxf(t.height_at(p3), 0.0), dir, true]
	if now < float(s["t_arrive"]):
		var way2: PackedVector2Array = s["way"]
		var way_end: Vector2 = way2[way2.size() - 1]
		var k3: float = (now - float(s["t_exit"])) / maxf(float(s["t_arrive"]) - float(s["t_exit"]), 0.001)
		var p4: Vector2 = way_end.lerp(s["to"], k3)
		return [p4, lerpf(maxf(t.height_at(p4), 0.0), float(s["to_y"]), smoothstep(0.7, 1.0, k3)), ((s["to"] as Vector2) - way_end).normalized(), true]
	return [s["to"], s["to_y"], Vector2.ZERO, false]


## M3c S-4: whether a point is inside a yard's walls.
static func _inside(yard: Dictionary, p: Vector2) -> bool:
	return p.distance_to(yard["centre"]) < float(yard["radius"]) - 0.5


## A recruit marching in: along its path (the outer gate, the inner gate, its slot) from its start time,
## fading in as it comes through (a figure walking back in through the gate keeps its size).
func _march_in_step(f: Dictionary, now: float, skipping: bool) -> void:
	var path: PackedVector2Array = f["in_path"]
	var lens := _lens(path)
	var total: float = lens[lens.size() - 1]
	var dt: float = now - float(f["in_t0"])
	if skipping or dt * IN_SPEED >= total:
		f["pos"] = path[path.size() - 1]
		f["y"] = f["to_y"]
		f["yaw"] = lerp_angle(float(f["yaw"]), float(f["to_yaw"]), 1.0 if skipping else 0.25)
		f["scale"] = 1.0
		f["hop"] = 0.0
		f["tilt"] = 0.0
		f["pose"] = "ready"
		return
	var keep: bool = f.get("keep_scale", false)
	if dt < 0.0:
		f["pos"] = path[0]
		f["scale"] = 1.0 if keep else 0.0
		return
	var at: Array = _along(path, lens, dt * IN_SPEED)
	var dir: Vector2 = at[1]
	f["pos"] = at[0]
	f["y"] = lerpf(float(f["from_y"]), float(f["to_y"]), clampf(dt * IN_SPEED / maxf(total, 0.01), 0.0, 1.0))
	f["yaw"] = atan2(-dir.x, -dir.y)
	f["scale"] = 1.0 if keep else smoothstep(0.0, 0.3, dt)
	var mo := Choreo.motion("march_in", now, float(f["phase"]))
	f["hop"] = mo["hop"]
	f["tilt"] = mo["tilt"]
	f["pose"] = mo["pose"]


## The re-form begins: every army of the state after gets exactly its layout's figures, each one starting
## where a standing figure of its type is now; the rest are new (recruits, a new ruler): at a fortress
## they march in through the gate, elsewhere they appear at the edge of the formation. The figures left
## over and the fallen sink away.
func _begin_reform() -> void:
	reform_started.emit() ## M5-3: the board shows the state after's sight from here
	var after: GameState = _play["after"]
	var dest: Dictionary = _play["dest"]
	var t = wv.terrain
	var old := armies
	armies = {}
	var seen := {}
	var t_reform: float = _play["t_reform"]
	var new_k := {} ## province id -> recruits marching in there so far
	var recruit_end: float = t_reform + REFORM
	var first_new := {} ## army id -> when its first recruit comes through
	## M3c S-4: the forts as they stand once the sieges and captures are done and the sites worked
	for st in _play.get("fort_steps", []):
		if String(st["beat"]["phase"]) != "recruitment":
			_apply_fort(st)
	_work_sites()
	_push_forts()
	for a in after.armies:
		var stand_in := not a.seen.is_empty() ## M5-3: a rival's sighting in a view: it fades in, it never marches in as a recruit would
		var yard_a: Dictionary = wv.yard_of(a.location, after)
		var slots: Array = dest.get(a.id, [])
		var placed: Array = []
		var e_old: Dictionary = old.get(a.id, {})
		var pool: Array = (e_old.get("figs", []) as Array).filter(func(f): return float(f["scale"]) > 0.05 and float(f["fall"]) < 0.5)
		for sl in slots:
			var best := -1
			var best_d := 1.0e18
			for q in pool.size():
				if pool[q]["type"] != sl["type"]:
					continue
				var d2: float = (pool[q]["pos"] as Vector2).distance_squared_to(sl["pos"])
				if d2 < best_d:
					best_d = d2
					best = q
			var item: Dictionary = sl.duplicate()
			if best >= 0:
				var f0: Dictionary = pool[best]
				pool.remove_at(best)
				item["from_pos"] = f0["pos"]
				item["from_yaw"] = f0["yaw"]
				item["from_y"] = f0["y"]
				item["from_scale"] = f0["scale"]
				## M3c S-4: a figure coming back inside the walls (a sally's survivors) walks in by the gate
				if not yard_a.is_empty() and _inside(yard_a, sl["pos"]) and not _inside(yard_a, f0["pos"]) \
						and (f0["pos"] as Vector2).distance_to(yard_a["centre"]) < float(yard_a["radius"]) + 40.0:
					var gq: Array = yard_a["gate"]
					item["in_path"] = PackedVector2Array([f0["pos"], gq[1], gq[0], sl["pos"]])
					item["in_t0"] = t_reform + 0.1
					item["keep_scale"] = true
			elif stand_in:
				item["from_pos"] = sl["pos"]
				item["from_yaw"] = sl["yaw"]
				item["from_y"] = sl["y"]
				item["from_scale"] = 0.0
			else:
				## a new figure: through the gate at a fortress (M3c S-4: at any fort, in a game with sieges), else
				## from the edge of its formation
				var pid: String = a.location
				var path := PackedVector2Array()
				var from_y: float = sl["y"]
				if not yard_a.is_empty() and _inside(yard_a, sl["pos"]):
					var gp: Array = yard_a["gate"]
					var facing: Vector2 = yard_a["gate_dir"]
					path.append((gp[1] as Vector2) + facing * 6.0)
					path.append(gp[1])
					if (sl["pos"] as Vector2).distance_to(gp[0]) < (sl["pos"] as Vector2).distance_to(gp[1] as Vector2 + facing * 6.0):
						path.append(gp[0])
					from_y = maxf(t.height_at(path[0]), 0.0)
				else:
					var c: Vector2 = t.centre_of(pid) if t.index_of(pid) >= 0 else sl["pos"]
					var out_dir: Vector2 = ((sl["pos"] as Vector2) - c).normalized() if (sl["pos"] as Vector2).distance_to(c) > 0.5 else Vector2(0, 1)
					path.append((sl["pos"] as Vector2) + out_dir * 10.0)
				path.append(sl["pos"])
				var nk: int = int(new_k.get(pid, 0))
				new_k[pid] = nk + 1
				var t_in: float = t_reform + 0.15 + nk * 0.24
				item["in_path"] = path
				item["in_t0"] = t_in
				item["from_pos"] = path[0]
				item["from_y"] = from_y
				item["from_scale"] = 0.0
				var lens := _lens(path)
				recruit_end = maxf(recruit_end, t_in + lens[lens.size() - 1] / IN_SPEED)
				if not first_new.has(a.id):
					first_new[a.id] = t_in + 0.4
			placed.append(item)
		## the figures left over (losses in a battle it won) and its fallen sink where they lie
		for f0 in (e_old.get("figs", []) as Array):
			if pool.has(f0) or float(f0["fall"]) >= 0.5:
				placed.append({"type": f0["type"], "role": "unit", "pos": f0["pos"], "yaw": f0["yaw"], "y": f0["y"],
					"from_scale": f0["scale"], "to_scale": 0.0, "from_fall": f0["fall"], "pose": f0["pose"]})
		var e: Dictionary
		if not e_old.is_empty():
			e = e_old
			e["units"] = a.units.size()
			e["province"] = a.location
			var dd := _desc_of(a, after) ## M5-3: a glimpsed army that became a memory (or the reverse) changes its material here
			e["memory"] = bool(dd.get("memory", false))
			e["step"] = int(dd.get("step", 0))
			e["stand_in"] = stand_in
			_fill_entry(e, placed)
		else:
			e = _make_entry(_desc_of(a, after), placed)
		armies[a.id] = e
		seen[a.id] = true
	## the fallen armies: whatever still lies there sinks away
	for id in old.keys():
		if seen.has(id):
			continue
		var e2: Dictionary = old[id]
		for f in e2["figs"]:
			f["from_pos"] = f["pos"]
			f["from_yaw"] = f["yaw"]
			f["from_y"] = f["y"]
			f["from_scale"] = f["scale"]
			f["from_fall"] = f["fall"]
			f["to_pos"] = f["pos"]
			f["to_yaw"] = f["yaw"]
			f["to_y"] = f["y"]
			f["to_scale"] = 0.0
		armies["~fallen~" + id] = e2
	for e3 in armies.values():
		for f in e3["figs"]:
			if not f.has("from_pos"):
				f["from_pos"] = f["pos"]
				f["from_yaw"] = f["yaw"]
				f["from_y"] = f["y"]
			if not f.has("from_fall"):
				f["from_fall"] = 0.0
	## the recruits' beats, and the phase's end
	var ids: Array = first_new.keys()
	ids.sort()
	var ri := 0
	for aid in ids:
		_play["beats"].append({"kind": "recruit", "t": first_new[aid], "phase": "recruitment", "index": ri})
		ri += 1
	for p in _play["phases"]:
		if p["key"] == "recruitment":
			p["t1"] = recruit_end
	_play["t_end"] = maxf(float(_play["t_end"]), recruit_end + TAIL)
	## the camps of the state after
	_set_camps(_play["camps_after"])
	rings = _play["rings_after"]
