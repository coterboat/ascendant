## Magic on the 3D board (M5-9, #120; design/M5_MAGIC_FOG.md §6.4, §12.2, §12.3, §15.3): the decals an enchantment keeps on the land
## while it lasts, the beats of a turn's rituals and enchantments, a Bastion's fort. Placeholders in code (world3d/spell_plan.gd plans
## each mark, world3d/spell_fx.gd draws them), so the milestone never waits for the VFX sheets.
##
##   * standing decals, read from the state the board stands (under fog the viewer's own view: a rival's enchantment shows only
##     where the view has it): a gilt ring under each blessed army, a blue band on a warded province, crimson veins on a cursed
##     one, an eye plate over a province in Far Sight. Animated on rung 0-1, still from rung 2 (SpellPlan.standing).
##   * beats (Armies.magic_beat, from Playback.plan's "rituals"): a ritual cast shows a pillar of light at a caster the viewer sees
##     and a mote along the roads to the target, then the target's decal; a ritual from a caster the viewer can't see arrives at its
##     target with no direction (the beat's `from` is "" then, and nothing here ever looks the caster up); a fizzle, a payment in
##     blood, a summoning ring the creatures step out of, a fort that rises behind scaffolding (a Bastion), an enchantment beginning
##     or ending, a blessing healing, a curse biting, a summon dissolving into leaves, the eye opening over a rival's capital.
##   * a Bastion's fort in a game without sieges (the baked map has none there), drawn from the state like the map's own.
##
## It reads the state it is given and the beats it is told of, and changes neither: effects never change anything. No dice: a mote's
## place is a hash of its index (SpellPlan.h01).
##
##   sync(state)                  the standing decals (and raised forts) of the state the board stands
##   on_beat(beat, index)         one magic beat of the playback (Armies.magic_beat)
##   begin_play(), end_play()     a turn's playback: armies march away from the rings that follow them; scaffolding comes down
##   plan_of(beat)                the SpellPlan the beat plays (tests: every beat has one)
extends Node3D

const SpellFx := preload("res://world3d/spell_fx.gd")
const SpellPlan := preload("res://world3d/spell_plan.gd")
const SiegeBoard := preload("res://world3d/siege_board.gd")
const Terrain3D := preload("res://world3d/terrain3d.gd")
const Vision := preload("res://world3d/vision.gd")

const PROV_R := 1.7 ## a province's decals are sized from its stage radius
const PROV_R_MIN := 36.0
const PROV_R_MAX := 70.0
const MAP_MIDDLE := Vector2(500.0, 300.0) ## the Blood Moon hangs over the middle of the map
const RISE_STEP := 0.22 ## seconds a Bastion's scaffolding takes to go up a step

var wv: Node3D
var armies: Node3D
var fx: SpellFx
var rung := 0
var reduced_motion := false
var played: Array = [] ## (tests) the beats drawn: [{"key", "skipped", "from": bool}]
var sync_count := 0
var _flash := BattleFx.FlashLimiter.new()
var _viewer := ""
var _sig := {}
var _rising := {}
var _dress: Node3D


func _init() -> void:
	name = "EnchantDecals"
	fx = SpellFx.new()
	fx.auto_step = true
	fx.flash = _flash
	add_child(fx)


## The board legend's lines for magic (the 3D board's legend, BoardOverlay.legend_text): what the decals and beats mean. "" in a game
## without magic, so that game's legend is exactly what it was.
static func legend_lines(state: GameState) -> String:
	if state == null or not MagicRules.has_magic(state):
		return ""
	return "\n".join([
		"\n\nMagic (the M5 preview):",
		"- A gilt ring under an army: it is blessed. A blue band on a province: a Sanctum Ward turns rival rituals aside there. Crimson veins on a province: a curse, which stops healing there for any army that isn't its caster's and takes hit points each turn. An eye over a province: Far Sight. Hover a province's badge for the exact effect and when it ends.",
		"- A ritual you can see cast: a pillar of light at its caster, a mote running the roads to its target, then a mark on the target. A ritual cast from somewhere you can't see arrives at its target with no direction.",
		"- A ring of thorns that creatures step out of: a summoning. A fort rising behind scaffolding: Bastion. Creatures dissolving into leaves: a summon whose time is up.",
		"- A blood-red moon over the map: the Blood Moon, under which its caster's fighters heal back part of the damage they deal in every battle.",
		"- The turn's playback opens with the Rituals phase, before anyone marches, and closes with the Enchantments phase: blessed armies heal in gilt motes, a curse bites in crimson ones, and an enchantment that has run its course lets go of the land.",
	])


func setup(p_wv: Node3D, p_armies: Node3D) -> void:
	wv = p_wv
	armies = p_armies
	if wv != null and wv.get("gmat") != null:
		fx.bind_ground((wv.gmat as ShaderMaterial).get_shader_parameter("height_tex"), Terrain3D.ORIGIN, Terrain3D.EXTENT) ## decals lie on the land


func set_rung(r: int) -> void:
	rung = SpellPlan.clamp_rung(r)
	fx.rung = rung
	_sig.clear() ## the standing decals redraw at the new rung


func _process(delta: float) -> void:
	_step_rising(delta * (armies.speed if armies != null else 1.0))


# ------------------------------------------------------------------ places

func _terrain() -> Variant:
	return wv.terrain


## A point of the land, a little above the ground.
func ground(p: Vector2, lift: float = 0.0) -> Vector3:
	return (_terrain().ground_at(p) as Vector3) + Vector3.UP * lift


## The middle of a province, on the ground.
func prov_pos(pid: String) -> Vector3:
	return ground(_terrain().centre_of(pid))


## The radius the province's decals are sized from.
func prov_r(pid: String) -> float:
	var i: int = _terrain().index_of(pid)
	return clampf(float(_terrain().stage_r[i]) * PROV_R, PROV_R_MIN, PROV_R_MAX) if i >= 0 else PROV_R_MIN


## Where an army stands on the board and how wide: {"at", "r"}, {} when none of it stands.
func army_ring(aid: String) -> Dictionary:
	var pts: Array = armies.army_points(aid) if armies != null else []
	if pts.is_empty():
		return {}
	var sum := Vector3.ZERO
	for p in pts:
		sum += (p[0] as Vector3)
	var mid: Vector3 = sum / float(pts.size())
	var r := 0.0
	for p in pts:
		r = maxf(r, Vector2((p[0] as Vector3).x - mid.x, (p[0] as Vector3).z - mid.z).length())
	return {"at": mid, "r": maxf(r + 4.0, 7.0), "yaw": armies.army_yaw(aid) if armies != null and armies.has_method("army_yaw") else 0.0}


## The roads a mote runs from province `a` to province `b`, as world points just above the ground: the roads between neighbours,
## straight where there is none, through the provinces between along the shortest way.
func route(a: String, b: String) -> PackedVector3Array:
	var t = _terrain()
	var out := PackedVector3Array()
	var ia: int = t.index_of(a)
	var ib: int = t.index_of(b)
	if ia < 0 or ib < 0:
		return out
	var prev := {ia: -1}
	var queue := [ia]
	while not queue.is_empty() and not prev.has(ib):
		var cur: int = queue.pop_front()
		for j in t.neighbours[cur]:
			if not prev.has(j):
				prev[j] = cur
				queue.append(j)
	var chain := []
	var at := ib
	while at != -1 and prev.has(at):
		chain.push_front(at)
		at = int(prev[at])
	if chain.is_empty() or int(chain[0]) != ia:
		chain = [ia, ib]
	for k in range(1, chain.size()):
		var seg: PackedVector2Array = t.road_path(t.ids[chain[k - 1]], t.ids[chain[k]])
		if seg.size() < 2:
			seg = PackedVector2Array([t.centres[chain[k - 1]], t.centres[chain[k]]])
		elif (seg[0] as Vector2).distance_to(t.centres[chain[k - 1]]) > (seg[seg.size() - 1] as Vector2).distance_to(t.centres[chain[k - 1]]):
			seg.reverse()
		for p in seg:
			if out.is_empty() or out[out.size() - 1].distance_to(ground(p, 2.0)) > 0.5:
				out.append(ground(p, 2.0))
	return out


# ------------------------------------------------------------------ the standing decals

## The enchantments the state stands, drawn: ward, curse and sight on their provinces, a blessing on each of its armies, and the forts
## Bastion raised. Called whenever the board stands a state (Board3D._paint_owners); a hotseat handoff clears the last seat's marks.
func sync(st: GameState) -> void:
	if wv == null or st == null:
		return
	sync_count += 1
	var who: String = st.view_of if Vision.active(st) else ""
	if who != _viewer:
		_viewer = who
		fx.clear()
		fx.clear_standing()
		_sig.clear()
		_end_rising()
	var want := {}
	var raised := []
	if MagicRules.has_magic(st):
		for e in st.enchantments:
			var kind := String(e.kind)
			if not SpellPlan.STANDING_KINDS.has(kind):
				continue
			var els: Array = []
			if kind == "blessing":
				var rings := []
				for aid in e.armies:
					var ring := army_ring(String(aid))
					if not ring.is_empty():
						rings.append(ring)
				els = SpellPlan.standing(kind, rung, {"armies": rings}, reduced_motion)
			elif _terrain().index_of(String(e.province)) >= 0:
				var pid := String(e.province)
				els = SpellPlan.standing(kind, rung, {"at": prov_pos(pid), "r": prov_r(pid)}, reduced_motion)
			if not els.is_empty():
				want["e:" + String(e.id)] = els
		if not st.sieges:
			## a fort that is not on the baked map was raised by Bastion (the only other way to a fort is a siege game's Fortify)
			for p in st.provinces:
				var i: int = _terrain().index_of(p.id)
				if p.has_fort and i >= 0 and not _terrain().has_fort[i]:
					raised.append(p.id)
	wv.set_raised_forts(raised)
	for key in fx.standing_keys():
		if not want.has(key):
			fx.clear_standing(key)
			_sig.erase(key)
	for key in want:
		var sig := var_to_str(want[key])
		if String(_sig.get(key, "")) != sig:
			_sig[key] = sig
			fx.set_standing(key, want[key])


## The turn's playback begins: the rings that follow armies come off (the armies march away from them), and are drawn again where
## the state after stands them (sync).
func begin_play() -> void:
	for key in fx.standing_keys():
		if key.begins_with("e:") and String(_sig.get(key, "")).contains("sun_ring"):
			fx.clear_standing(key)
			_sig.erase(key)


## The playback is over: scaffolding that went up round a raised fort comes down (the fort itself stands from the state).
func end_play() -> void:
	_end_rising()


# ------------------------------------------------------------------ the beats

## What a magic beat plays: the SpellPlan for it, or {} when the beat has no place on this board (a province it can't find).
func plan_of(beat: Dictionary) -> Dictionary:
	var key := SpellPlan.board_key(beat)
	if not SpellPlan.BOARD_KEYS.has(key):
		return {}
	var t = _terrain()
	var at_pid := String(beat.get("at", ""))
	var has_at: bool = not at_pid.is_empty() and t.index_of(at_pid) >= 0
	var args := {"school": SpellPlan.school_of(String(beat.get("ritual", ""))), "rkind": String(beat.get("rkind", "")),
		"ekind": String(beat.get("ekind", "")), "global": bool(beat.get("global", false)), "map": ground(MAP_MIDDLE)}
	if has_at:
		args["at"] = prov_pos(at_pid)
		args["r"] = prov_r(at_pid)
	elif not bool(beat.get("global", false)) and key != "ritual_turned_aside":
		return {}
	var ids: Array = beat.get("armies", [])
	## a caster the viewer sees: a pillar at its army (else its province) and the roads from there. The beat's `from` is "" for
	## a caster it doesn't, so this never has a place to look for.
	var from_pid := String(beat.get("from", ""))
	if not from_pid.is_empty() and t.index_of(from_pid) >= 0:
		var ring: Dictionary = army_ring(String(ids[0])) if not ids.is_empty() else {}
		args["from"] = (ring["at"] as Vector3) if not ring.is_empty() else prov_pos(from_pid)
		if has_at:
			args["path"] = route(from_pid, at_pid)
	match key:
		"blood_paid":
			var ring2: Dictionary = army_ring(String(ids[0])) if not ids.is_empty() else {}
			args["from"] = (ring2["at"] as Vector3) if not ring2.is_empty() else (args["at"] if has_at else Vector3.ZERO)
		"summoned", "summon_faded":
			var aid := String(beat.get("army", ""))
			var r3: Dictionary = army_ring(aid)
			if r3.is_empty():
				r3 = army_ring("~fallen~" + aid)
			if not r3.is_empty():
				args["at"] = r3["at"]
				args["r"] = r3["r"]
				args["yaw"] = r3["yaw"]  # VFX-WIRE: the ring turns with the summons
			elif has_at:
				args["r"] = 8.0
		"fort_raised":
			var i: int = t.index_of(at_pid)
			args["at"] = ground(_fort_spot(i))
			args["r"] = 14.0
			args["height"] = 16.0
		"blessing_healed", "curse_bit", "enchantment_ended", "enchantment_began":
			var rings := []
			for aid in ids:
				var rg := army_ring(String(aid))
				if not rg.is_empty():
					rings.append(rg)
			args["armies"] = rings
		"far_sight_reading":
			pass
	if not args.has("at") and not bool(args["global"]) and key != "ritual_turned_aside":
		return {}
	if not args.has("at"):
		args["at"] = args["map"]
	return SpellPlan.board(key, rung, args, reduced_motion)


## One magic beat plays (Armies.magic_beat). Nothing here is the game's: a plan is drawn and a fort may rise behind scaffolding.
func on_beat(beat: Dictionary, _index: int) -> void:
	if wv == null:
		return
	reduced_motion = bool(BattleFx.settings().get("reduced_motion", false))
	fx.reduced_motion = reduced_motion
	var plan := plan_of(beat)
	if plan.is_empty():
		return
	var now := Time.get_ticks_msec() / 1000.0
	fx.time_scale = armies.speed if armies != null else 1.0
	var out: Dictionary = fx.play(plan, now)
	played.append({"key": SpellPlan.board_key(beat), "skipped": bool(out.get("skipped", false)), "from": not String(beat.get("from", "")).is_empty()})
	if String(beat.get("kind", "")) == "fort_raised":
		_start_rise(String(beat.get("at", "")), String(beat.get("faction", "")))


# ------------------------------------------------------------------ a Bastion's fort rising

func _fort_spot(i: int) -> Vector2:
	return wv.fort_spot(_terrain(), i)[0]


## The fort goes up behind scaffolding: the board's own rising piece (world_view.gd _rising: the model drawn up to a height inside a
## lattice of timber), stepped up in a dozen frames on rung 0-2, quicker on rung 3 (a fade), at once from rung 4 (a pop).
func _start_rise(pid: String, faction: String) -> void:
	var st: GameState = armies.state if armies != null else null
	if wv == null or wv.buildings == null or _terrain().index_of(pid) < 0 or _rising.has(pid):
		return
	var steps := [0.14, 0.28, 0.42, 0.56, 0.7, 0.85, 1.0]
	if rung == 3:
		steps = [0.5, 1.0]
	elif rung >= 4 or reduced_motion:
		steps = [1.0]
	var col: Color = armies.fort_colours().get(faction, Color.WHITE) if armies != null else Color.WHITE
	_rising[pid] = {"t": 0.0, "step": -1, "steps": steps, "kind": SiegeBoard.kind_of(1) if (st != null and st.sieges) else "fort",
		"kit": faction, "col": col, "step_s": RISE_STEP if rung < 3 else 0.3}
	if _dress == null:
		_dress = Node3D.new()
		_dress.name = "BastionScaffold"
		wv.buildings.add_child(_dress)


func _step_rising(delta: float) -> void:
	for pid in _rising.keys():
		var r: Dictionary = _rising[pid]
		r["t"] = float(r["t"]) + delta
		var idx := mini(int(float(r["t"]) / float(r["step_s"])), (r["steps"] as Array).size() - 1)
		if idx == int(r["step"]):
			continue
		r["step"] = idx
		var holder := _dress.get_node_or_null("Rise_" + pid)
		if holder != null:
			holder.free()
		var h := Node3D.new()
		h.name = "Rise_" + pid
		_dress.add_child(h)
		wv._rising(h, pid, String(r["kind"]), String(r["kit"]), float((r["steps"] as Array)[idx]), r["col"])


func _end_rising() -> void:
	_rising.clear()
	if _dress != null and is_instance_valid(_dress):
		_dress.queue_free()
	_dress = null


## Is a fort rising now at `pid` (tests)?
func rising_at(pid: String) -> bool:
	return _rising.has(pid)
