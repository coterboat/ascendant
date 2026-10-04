class_name Board3D
extends Control
## The 3D board (M3a.1, design/3D_DIRECTION.md 3.3): the game's map drawn as the 3D world under the
## map screen's own 2D UI. The world (world_view.gd: the land, sea, fortresses, villages; armies.gd: the
## armies as formations of miniatures) renders into a SubViewport that this Control draws in the map
## screen's map area, under the top bar, the side panel and every overlay. The 2D over it (names,
## incomes, count plates, order arrows, clash markers, the playback bar) is board_overlay.gd, projected
## from 3D every frame at native resolution.
##
## The map screen stays the one place that knows the game: the board picks what is under the mouse
## (the territory id of the land at the unprojected point, or the army formation under it) and calls
## the map's own select_province / select_army / preview_move / request_codex, so every signal, order
## and tooltip works as on the 2D map. The map calls sync() whenever its state, selection or orders
## change; the board mirrors them on the ground (shader highlights) and in the yard (ghost recruits).
##
## The board only reads the game: GameState, the turn's events and the orders. It never resolves a turn
## or changes a state (tests/test_board3d.gd checks the state is deep-equal before and after).
##
## Camera: drag (or the middle button) pans with the ground under the hand, the wheel zooms to the
## cursor with the pitch easing from 60 degrees over the whole map to 42 close in, WASD or the arrows
## pan, double-click glides to a province, C (or Home) to your capital, F frames the whole map, L
## switches Look A (Bright Cel) and Look B (lit painted). The whole map is framed on start.
## Playback: play_turn(before, events, after) plays the turn on the land (armies.gd) in the report's
## phases, under their captions (Movement, Battles, Captures, Recruits), with a sound at each beat
## (march, clash, strike, fall, the capture fanfare, recruit: GameAudio.sfx, varied by the beat's index,
## never by a random number); Space or a click skips it; its speed is a setting
## (GameSettings.playback_speed). A capture's new colour sweeps out from the arriving column.
##
## Planning (M3a.2, the viewing player's own orders only, so nothing of another seat's ever shows):
## queued recruits stand as ghosts in the yard slots they will take, armies ordered to march gather at
## their gate (or their stage's edge) facing the road, and the yard closes ranks behind them.
##
## The fortress close-up (M3a.2, design/3D_DIRECTION.md 8.3): View fortress in the recruit panel, or a
## double-click on a fortress, swoops the camera down into the yard (turned to look in through the gate);
## each queued recruit appears there at once as a ghost. Esc, zooming out, F, C or selecting another
## province leaves it.
##
## Rendering: the SubViewport renders only while the board is visible and not covered (cover_check:
## the handoff cover, a modal overlay); covered, it keeps its last frame. The quality ladder steps down
## by itself after 3 seconds under 40 fps (world_view.gd set_quality).

signal ready_to_show
signal playback_started
signal playback_finished
## The fortress close-up opened on a province, or closed ("").
signal closeup_changed(province_id: String)

const Terrain3D := preload("res://world3d/terrain3d.gd")
const WorldView := preload("res://world3d/world_view.gd")
const Armies := preload("res://world3d/armies.gd")
const BoardOverlay := preload("res://world3d/board_overlay.gd")
const Playback := preload("res://world3d/playback.gd")
const Models := preload("res://world3d/models.gd")
const Muster := preload("res://world3d/muster.gd")
const Choreo := preload("res://world3d/choreo.gd")
const Stands := preload("res://world3d/stands.gd")

const SPAN_NEAR := 70.0
const PITCH_FAR := 60.0
const PITCH_NEAR := 42.0
const FOV := 30.0
const DRAG_START := 6.0 ## pixels before a press becomes a pan
const LAND := Rect2(-6, -6, 1012, 618) ## what "the whole map" frames (design units)
const FOCUS_ZOOM := 0.55
const MAX_PX := 2.0 ## the 3D renders at most at 2 physical pixels per screen pixel
const SEA_VEIL := Color("#244E6E")
const CLOSE_PITCH := 52.0 ## the fortress close-up's pitch (design 8.1: about 35); the gate side is cut away so the walls never hide the yard
const CLOSE_SPAN := 56.0 ## the close-up frames the yard, its gate and the camp's edge
const CLOSE_MIN_SPAN := 34.0
const BATTLE_ZOOM := 0.8 ## the playback camera leans in this far on each battle
const MIN_FIG_PX := 26.0 ## a man-sized figure never stands shorter than this on the board (design 6.1: 24 px at 1080p)
const MAX_PIECE_SCALE := 3.2 ## past this the blocks pile into each other: the far-zoom stand's job (design 6.1)

static var _terrain: RefCounted = null
static var _task := -1
static var look := "cel" ## Look A by default (PR #81); L switches for the session

var map: Control = null ## the MapScreen this board serves
var wv: Node3D ## world_view.gd
var armies: Node3D ## armies.gd
var stands: Node3D ## stands.gd (#125): the far-zoom army stands
var overlay: Control ## board_overlay.gd
var prepared := false
var cover_check: Callable = Callable() ## true while something covers the board (it then stops rendering)
var shown: GameState = null ## the state the board stands
var seats: Array = []
var zoom := 0.0 ## 0 the whole map, 1 all the way in
var goal := {} ## the rig the camera eases to
var hover_id := "" ## the province under the mouse
var hover_army := "" ## the army formation under the mouse
var auto_quality := true
var fps_samples: Array = [] ## (perf probes) recent frame times
var _vp: SubViewport
var _px := 1.0
var _span_fit := 600.0
var _fit_size := Vector2.ZERO
var _press := false
var _drag := false
var _press_pos := Vector2.ZERO
var _drag_ground := Vector2.ZERO
var _flash := {} ## province id -> 0..1, the focus flash
var _slow := 0.0
var _live := false
var _playing := false
var closeup := "" ## the fortress whose yard the close-up shows ("" none)
var _pre_closeup := {} ## the camera before the close-up: {"goal", "zoom"}
var sounds: Array = [] ## (tests) the beats' sounds this board asked for, in order


func _init() -> void:
	name = "Board3D"
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	clip_contents = true
	tooltip_text = " " ## the real text comes from _get_tooltip (what is under the mouse)
	set_meta(CodexLink.META, TooltipText.codex_for("province"))


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ensure_viewport()
	if _terrain == null and _task < 0:
		prebake()
	set_process(true)


## Starts baking the land on a worker thread (once a run; the land is the same every game). The title
## screen's autoload calls it at start-up, so a game's board is ready at once.
static func prebake() -> void:
	if _terrain != null or _task >= 0:
		return
	_task = WorkerThreadPool.add_task(_bake, false, "the 3D board's land")


## The land, its placement (trees, cottages, grain) and the model table's meshes, all pure: done off
## the main thread so the window stays live (design/3D_DIRECTION.md 3.3).
static func _bake() -> void:
	var t: RefCounted = Terrain3D.build()
	WorldView.plan_of(t)
	for f in FactionData.FACTIONS:
		for kind in ["fortress", "fort", "camp"]:
			Models.building_model(kind, String(f.id))
		for extra in ["bearer", "musician"]:
			Models.figure_mesh(extra, true, "ready", String(f.id))
	for type_id in (Models.table().get("figures", {}) as Dictionary).keys():
		Models.pose_meshes(type_id)
	for kind in (Models.table().get("buildings", {}) as Dictionary).keys():
		for path in Models.building_variants(String(kind)):
			Models.model_at(String(path))
	_terrain = t


## The baked land, waiting for the bake if it is under way (tests, and build_now()).
static func terrain_now() -> RefCounted:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	if _terrain == null:
		_bake()
	return _terrain


## Builds the world at once (tests and tools; the game builds it when the land is baked).
func build_now() -> void:
	_ensure_viewport()
	terrain_now()
	if not prepared:
		_build_world()


func _ensure_viewport() -> void:
	if _vp != null:
		return
	_vp = SubViewport.new()
	_vp.name = "World"
	_vp.own_world_3d = true
	_vp.transparent_bg = false
	_vp.msaa_3d = Viewport.MSAA_2X
	if RenderingServer.get_current_rendering_method() != "gl_compatibility":
		_vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	_vp.size = Vector2i(maxi(int(size.x), 64), maxi(int(size.y), 64))
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)


func _build_world() -> void:
	wv = WorldView.new()
	wv.name = "WorldView"
	_vp.add_child(wv)
	wv.setup(_terrain, look)
	wv.set_effects(true)
	armies = Armies.new()
	armies.name = "Armies"
	armies.wv = wv
	wv.add_child(armies)
	armies.captured.connect(_on_captured)
	armies.capture_swept.connect(_on_capture_swept)
	armies.beat.connect(_on_beat)
	armies.clash_started.connect(_on_clash_started)
	armies.playback_finished.connect(_on_playback_finished)
	stands = Stands.new()
	stands.wv = wv
	wv.add_child(stands)
	overlay = BoardOverlay.new()
	overlay.board = self
	add_child(overlay)
	prepared = true
	_fit_viewport(true)
	fit_whole(true)
	sync()
	ready_to_show.emit()
	queue_redraw()


# ------------------------------------------------------------------ following the map

## The map screen's state, selection or orders changed: mirror them. A playback in progress keeps the
## armies as they march (the board ends on the state after anyway).
func sync() -> void:
	if not prepared or map == null:
		return
	var st: GameState = map.state
	if st != null and st != shown and not _playing:
		stand(st)
	if not closeup.is_empty() and map.selected_province_id != closeup:
		exit_closeup()
	_sync_marks()
	_sync_plan()
	if overlay != null:
		overlay.refresh()


## Stands `st` on the board at once: owners, fortresses and armies.
func stand(st: GameState) -> void:
	shown = st
	seats = map.seat_order() if map != null else UiPalette.seat_order(st)
	armies.show_state(st, seats)
	_paint_owners(st)


func _paint_owners(st: GameState) -> void:
	var cols := {}
	for p in st.provinces:
		if not p.owner.is_empty():
			cols[p.id] = UiPalette.owner_color(st, p.owner, seats)
	wv.set_owners(cols)
	for id in wv.fortresses.keys():
		var p := st.find_province(id)
		wv.set_fortress_colour(id, UiPalette.owner_color(st, p.owner, seats) if p != null and not p.owner.is_empty() else UiPalette.NEUTRAL)
	for id in wv.forts.keys():
		var p2 := st.find_province(id)
		wv.set_fort_colour(id, UiPalette.owner_color(st, p2.owner, seats) if p2 != null and not p2.owner.is_empty() else UiPalette.NEUTRAL)


func _sync_marks() -> void:
	var sel: String = map.selected_province_id
	wv.set_highlights(sel, hover_id)
	var road := {}
	var move := {}
	for id in map.regions.keys():
		if map.regions[id].road_target:
			road[id] = true
	var st: GameState = map.state
	var army: Army = st.find_army(map.selected_army_id) if st != null else null
	if army != null and army.owner == map.viewing_faction_id and map.orders != null and not _playing:
		var here := st.find_province(army.location)
		if here != null:
			for n in here.neighbors:
				move[n] = true
	## provinces the rules turned to forest since the land was baked (the Wild Spreads)
	var grown := {}
	if st != null:
		var t = wv.terrain
		for p in st.provinces:
			var i: int = t.index_of(p.id)
			if i >= 0 and p.terrain == "forest" and t.terrain_of[i] != "forest":
				grown[p.id] = true
	wv.set_marks(road, move, _flash, grown)


## The viewing player's plan on the board (their own orders only): queued recruits as ghosts in the
## slots they will take, armies ordered to march gathered at their gate.
func _sync_plan() -> void:
	if _playing:
		return
	armies.show_plan(plan_of_orders())


## The plan the viewing player's orders draw: {"departing": {army id: {"to", "via"}}, "ghosts":
## [{"province", "owner", "types"}], "owner"}. Never another seat's orders: the map's OrdersController
## is the viewing faction's own.
func plan_of_orders() -> Dictionary:
	var st: GameState = map.state if map != null else null
	if map == null or map.orders == null or st == null or map.viewing_faction_id.is_empty():
		return {}
	var fid: String = map.viewing_faction_id
	var f := st.find_faction(fid)
	if f == null:
		return {}
	var by_place := {}
	var order: Array = []
	var departing := {}
	for o in map.orders.orders():
		if o is MoveOrder:
			var a := st.find_army(o.army_id)
			if a != null and a.owner == fid:
				departing[o.army_id] = {"to": o.to, "via": o.via if o.is_road_move() else ""}
			continue
		if not (o is RecruitOrder):
			continue
		var where := f.capital
		if o.is_with_ruler():
			var ra := RulerRules.ruler_army(st, fid)
			where = ra.location if ra != null else ""
		if where.is_empty():
			continue
		if not by_place.has(where):
			by_place[where] = []
			order.append(where)
		by_place[where].append(o.unit_type_id)
	var ghosts: Array = []
	for where in order:
		ghosts.append({"province": where, "owner": fid, "types": by_place[where]})
	var ctx := {}
	if not departing.is_empty():
		ctx["departing"] = departing
	if not ghosts.is_empty():
		ctx["ghosts"] = ghosts
	if not ctx.is_empty():
		ctx["owner"] = fid
	return ctx


# ------------------------------------------------------------------ turn playback

## Plays a resolved turn on the land: the board stands `before`, then the armies march, fight and
## re-form as `events` say, ending on `after`. Returns false (nothing plays) when the board isn't
## ready; the caller then just shows the state after.
func play_turn(before: GameState, events: Array, after: GameState) -> bool:
	if not prepared or before == null or after == null:
		return false
	var plan := Playback.plan(before, events, after)
	if plan["marches"].is_empty() and plan["battles"].is_empty() and plan["recruits"].is_empty() \
			and plan["arrivals"].is_empty() and plan["captures"].is_empty():
		return false
	exit_closeup(true)
	shown = before
	seats = map.seat_order() if map != null else UiPalette.seat_order(after)
	armies.speed = float(GameSettings.load_from().playback_speed)
	armies.seats = seats
	wv.clear_sweeps()
	_paint_owners(before)
	_playing = true
	armies.play(plan, before, after)
	_frame_action(plan)
	_sync_marks()
	if overlay != null:
		overlay.begin_playback(plan, after)
	playback_started.emit()
	return true


## Glides the camera to frame the turn's action: its battles and the columns marching to them; with no
## battle, the viewing player's own columns; else every column (the whole map when it all moves).
func _frame_action(plan: Dictionary) -> void:
	var t = wv.terrain
	var pts: Array = []
	var fighting := {}
	for b in plan["battles"]:
		for pid in b["provinces"]:
			if t.index_of(pid) >= 0:
				pts.append(t.centre_of(pid))
		for aid in b["armies"]:
			fighting[aid] = true
	var me: String = map.viewing_faction_id if map != null else ""
	for pass_i in 3:
		for m in plan["marches"]:
			var take: bool = (pass_i == 0 and fighting.has(m["army"])) or (pass_i == 1 and m["owner"] == me) or pass_i == 2
			if not take:
				continue
			for pid in m["hops"]:
				if t.index_of(pid) >= 0:
					pts.append(t.centre_of(pid))
		if not pts.is_empty():
			break
	if pts.is_empty():
		return
	var box := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		box = box.expand(p)
	box = box.grow(60.0)
	var aspect: float = size.x / maxf(size.y, 1.0)
	var span: float = maxf(box.size.y * 1.2, box.size.x / maxf(aspect, 0.5))
	var z: float = clampf((log(maxf(span, SPAN_NEAR)) - log(_span_fit)) / (log(SPAN_NEAR) - log(_span_fit)), 0.0, 0.62)
	zoom = z
	goal = rig_for(box.get_center(), z)


func is_playing() -> bool:
	return _playing


func skip_playback() -> void:
	if _playing:
		armies.skip()


func set_playback_speed(v: float) -> void:
	armies.speed = v
	var s := GameSettings.load_from()
	if s.set_playback_speed(int(v)):
		s.save()


## A beat of the playback: its sound (Choreo.sound_for: the kind, varied by the beat's index). Sound only
## reads the beat; it never changes the board or the game.
func _on_beat(kind: String, index: int) -> void:
	var ev := Choreo.sound_for(kind, index)
	if ev.is_empty():
		return
	sounds.append(ev)
	GameAudio.sfx(ev)


## A battle's exchange begins: the playback camera leans in on it (it eases there; any pan takes over).
func _on_clash_started(_label: String) -> void:
	var cl: Array = armies.clashes_now()
	if cl.is_empty():
		return
	var at: Vector3 = cl[cl.size() - 1]["at"]
	zoom = maxf(zoom, BATTLE_ZOOM)
	goal = rig_for(Vector2(at.x, at.z) + Vector2(0, 6), zoom)


## A capture's sweep begins: the wash's old colour stays outside a front running out from `from`.
func _on_capture_swept(province_id: String, _owner_id: String, from: Vector2) -> void:
	wv.start_sweep(province_id, from, wv.old_owner_colour(province_id))


func _on_captured(province_id: String, owner_id: String) -> void:
	var st: GameState = shown
	var c: Color = UiPalette.owner_color(st, owner_id, seats) if st != null else UiPalette.NEUTRAL
	wv.paint_owner(province_id, c, not owner_id.is_empty())
	if wv.fortresses.has(province_id):
		wv.set_fortress_colour(province_id, c)
	wv.set_fort_colour(province_id, c)


func _on_playback_finished() -> void:
	_playing = false
	wv.clear_sweeps()
	shown = armies.state
	if shown != null:
		_paint_owners(shown)
	if overlay != null:
		overlay.end_playback()
	if map != null and map.state != null and map.state != shown:
		stand(map.state)
	_sync_marks()
	_sync_plan()
	if overlay != null:
		overlay.refresh()
	playback_finished.emit()


# ------------------------------------------------------------------ what the camera sees

## A map point (design units) on the land, to this board's local pixels (Vector2(-99999) behind).
func project(p: Vector2, lift: float = 0.0) -> Vector2:
	if not prepared:
		return Vector2(-99999, -99999)
	var s: Vector2 = wv.project(p, lift)
	return s / _scale() if s.x > -99990 else s


func project3(v: Vector3) -> Vector2:
	if not prepared:
		return Vector2(-99999, -99999)
	var s: Vector2 = wv.project3(v)
	return s / _scale() if s.x > -99990 else s


## A local pixel onto the ground (design units), refined over the hills.
func unproject(local: Vector2) -> Vector2:
	return wv.unproject(local * _scale()) if prepared else Vector2.ZERO


func _scale() -> Vector2:
	if _vp == null or size.x < 1.0 or size.y < 1.0:
		return Vector2.ONE
	return Vector2(_vp.size) / size


## The province under a local pixel ("" for the sea or off the land).
func province_at(local: Vector2) -> String:
	if not prepared:
		return ""
	var g := unproject(local)
	if not Rect2(Terrain3D.ORIGIN, Terrain3D.EXTENT).has_point(g):
		return ""
	return wv.terrain.province_at(g)


## The army formation under a local pixel ("" for none): the formation whose figures' screen box holds
## the point (the smallest when several do), so a click on an army picks it even where a hill stands
## in front of its ground.
func army_at(local: Vector2) -> String:
	if not prepared or _playing:
		return ""
	var best := ""
	var best_area := 1.0e18
	for id in armies.armies.keys():
		if String(id).begins_with("~"):
			continue
		var r := army_rect(id)
		if r.size.x <= 0.0 or not r.has_point(local):
			continue
		var area: float = r.size.x * r.size.y
		if area < best_area:
			best_area = area
			best = id
	return best


## An army formation's box on screen (local pixels), a little padded; empty when nothing of it stands.
func army_rect(id: String) -> Rect2:
	var pts: Array = stands.points(id) if stands != null and stands.k > 0.5 else armies.army_points(id)
	if pts.is_empty():
		return Rect2()
	var lo := Vector2(1.0e9, 1.0e9)
	var hi := Vector2(-1.0e9, -1.0e9)
	for pair in pts:
		for v in pair:
			var s := project3(v)
			if s.x < -99990:
				continue
			lo = lo.min(s)
			hi = hi.max(s)
	if hi.x < lo.x:
		return Rect2()
	return Rect2(lo, hi - lo).grow(5.0)


## Where an army's count plate stands (local pixels), or Vector2(-99999) when nothing of it stands.
func army_plate_point(id: String) -> Vector2:
	var a: Vector3 = stands.anchor(id) if stands != null and stands.k > 0.5 else armies.army_anchor(id)
	if a.x < -9999:
		return Vector2(-99999, -99999)
	return project3(a)


# ------------------------------------------------------------------ the camera

func rig_for(target: Vector2, z: float, yaw := 0.0) -> Dictionary:
	var span: float = exp(lerpf(log(_span_fit), log(SPAN_NEAR), z))
	var pitch: float = lerpf(PITCH_FAR, PITCH_NEAR, z)
	var h: float = maxf(wv.terrain.height_at(target), 0.0) * smoothstep(0.2, 0.6, z)
	return {"target": Vector3(target.x, h, target.y), "pitch": pitch, "yaw": yaw, "fov": FOV, "span": span}


## Frames the whole map in the board (fit on start, F).
func fit_whole(instant: bool = false) -> void:
	if not closeup.is_empty():
		wv.set_cutaway(closeup, false)
		wv.set_yard_light(false)
		closeup = ""
		closeup_changed.emit("")
	zoom = 0.0
	goal = rig_for(LAND.get_center(), 0.0)
	if instant:
		_snap_rig()


## Glides the camera to a province (a double-click, a turn report line), at least at the default zoom.
func focus_on(province_id: String, instant: bool = false) -> void:
	if not prepared or wv.terrain.index_of(province_id) < 0:
		return
	if not closeup.is_empty():
		exit_closeup(true)
	zoom = maxf(zoom, FOCUS_ZOOM)
	goal = rig_for(wv.terrain.centre_of(province_id) + Vector2(0, 6), zoom)
	_flash[province_id] = 1.0
	if instant:
		_snap_rig()


## C or Home: the viewing player's capital.
func focus_capital() -> void:
	if map == null or map.state == null:
		return
	var f: Faction = map.state.find_faction(map.viewing_faction_id)
	if f != null:
		focus_on(f.capital)


func _snap_rig() -> void:
	wv.rig = goal.duplicate()
	wv.apply_rig()


# ------------------------------------------------------------------ the fortress close-up (M3a.2)

## True when `province_id` has a fortress yard the close-up can show.
func can_closeup(province_id: String) -> bool:
	return prepared and wv.fortresses.has(province_id)


## Swoops the camera into the yard of the fortress at `province_id` (View fortress, a double-click):
## turned to look in through the gate, steep enough that the walls never hide a block. The recruit panel
## stays 2D beside it; queued recruits stand as ghosts in their slots. Returns false when there is none.
func enter_closeup(province_id: String, instant: bool = false) -> bool:
	if not can_closeup(province_id) or _playing:
		return false
	if closeup.is_empty():
		_pre_closeup = {"goal": goal.duplicate(), "zoom": zoom}
	if not closeup.is_empty() and closeup != province_id:
		wv.set_cutaway(closeup, false)
	closeup = province_id
	goal = closeup_rig(province_id)
	zoom = 1.0
	wv.set_cutaway(province_id, true)
	wv.set_yard_light(true)
	if instant:
		_snap_rig()
	if overlay != null:
		overlay.refresh()
	closeup_changed.emit(province_id)
	return true


## Leaves the close-up: the camera goes back where it was, north up again.
func exit_closeup(instant: bool = false) -> void:
	if closeup.is_empty():
		return
	wv.set_cutaway(closeup, false)
	wv.set_yard_light(false)
	closeup = ""
	var back: Dictionary = _pre_closeup.get("goal", {})
	if back.is_empty():
		back = rig_for(LAND.get_center(), 0.0)
	goal = back.duplicate()
	goal["yaw"] = 0.0
	zoom = float(_pre_closeup.get("zoom", 0.0))
	if instant:
		_snap_rig()
	if overlay != null:
		overlay.refresh()
	closeup_changed.emit("")


## The close-up's rig for a fortress: over its yard's slots, a little toward the gate (the gathered
## columns and the camp's edge in view), the camera on the gate's side looking in.
func closeup_rig(province_id: String) -> Dictionary:
	var fr: Dictionary = armies.yard_frame(province_id)
	var size: Vector2 = Muster.grid_size(fr["grid"])
	var facing: Vector2 = wv.fortresses[province_id]["gate_dir"]
	var c: Vector2 = (fr["o"] as Vector2) + (fr["z"] as Vector2) * (size.y * 0.5) + facing * 9.0
	var t = wv.terrain
	var y: float = t.stage_h[t.index_of(province_id)] + float(wv.fortresses[province_id]["floor"])
	return {"target": Vector3(c.x, y, c.y), "pitch": CLOSE_PITCH, "yaw": rad_to_deg(atan2(facing.x, facing.y)), "fov": FOV, "span": CLOSE_SPAN}


## The span that fits the whole land in the board at the far pitch.
func _compute_fit() -> void:
	if not prepared or size.x < 8 or size.y < 8:
		return
	var lo := 200.0
	var hi := 3000.0
	var keep: Dictionary = wv.rig.duplicate()
	for i in 22:
		var mid: float = (lo + hi) * 0.5
		_span_fit = mid
		wv.rig = rig_for(LAND.get_center(), 0.0)
		wv.apply_rig()
		var ok := true
		for c in [LAND.position, Vector2(LAND.end.x, LAND.position.y), Vector2(LAND.position.x, LAND.end.y), LAND.end]:
			var s: Vector2 = wv.project3(Vector3(c.x, 0.0, c.y)) / _scale()
			if s.x < 8.0 or s.y < 8.0 or s.x > size.x - 8.0 or s.y > size.y - 8.0:
				ok = false
				break
		if ok:
			hi = mid
		else:
			lo = mid
	_span_fit = hi
	wv.rig = keep
	wv.apply_rig()


func _move_goal(v: Vector2) -> void:
	var t: Vector3 = goal["target"]
	var p := Vector2(clampf(t.x + v.x, LAND.position.x, LAND.end.x), clampf(t.z + v.y, LAND.position.y, LAND.end.y))
	var h: float = maxf(wv.terrain.height_at(p), 0.0) * smoothstep(0.2, 0.6, zoom)
	goal["target"] = Vector3(p.x, h, p.y)


func zoom_at(local: Vector2, dz: float) -> void:
	if not closeup.is_empty():
		## in the close-up the wheel leans in a little; zooming out leaves it
		if dz < 0.0:
			exit_closeup()
		else:
			goal["span"] = maxf(CLOSE_MIN_SPAN, float(goal["span"]) * 0.9)
		return
	## zoom to the cursor: the ground under it stays under it
	_snap_rig()
	var g0 := unproject(local)
	zoom = clampf(zoom + dz, 0.0, 1.0)
	var t: Vector3 = goal["target"]
	goal = rig_for(Vector2(t.x, t.z), zoom, float(goal["yaw"]))
	for i in 3:
		_snap_rig()
		var g1 := unproject(local)
		_move_goal(g0 - g1)
	_snap_rig()


func _camera(delta: float) -> void:
	var pan := Vector2.ZERO
	if _keys_allowed():
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			pan.y -= 1
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			pan.y += 1
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			pan.x -= 1
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			pan.x += 1
	if pan != Vector2.ZERO:
		## screen directions, whichever way the camera is turned (the close-up turns it)
		var yr: float = deg_to_rad(float(goal["yaw"]))
		var right := Vector2(cos(yr), -sin(yr))
		var back := Vector2(sin(yr), cos(yr))
		var v: Vector2 = (right * pan.x + back * pan.y).normalized()
		_move_goal(v * float(goal["span"]) * 0.85 * delta)
	var k: float = 1.0 - exp(-delta * 7.0)
	var r: Dictionary = wv.rig
	r["target"] = (r["target"] as Vector3).lerp(goal["target"], k)
	r["span"] = exp(lerpf(log(float(r["span"])), log(float(goal["span"])), k))
	r["pitch"] = lerpf(r["pitch"], goal["pitch"], k)
	r["yaw"] = float(r["yaw"]) + wrapf(float(goal["yaw"]) - float(r["yaw"]), -180.0, 180.0) * k
	wv.apply_rig()
	## far out the figures stand taller (toy scale) so every army reads as a marker over the map, and a
	## man-sized figure never stands shorter than MIN_FIG_PX on screen (design 6.1, piece scale)
	var z: float = clampf((log(float(r["span"])) - log(_span_fit)) / (log(SPAN_NEAR) - log(_span_fit)), 0.0, 1.0)
	var px_per_unit: float = size.y / maxf(float(r["span"]), 1.0)
	var min_scale: float = clampf(MIN_FIG_PX / (Armies.Kit.FIG * maxf(px_per_unit, 0.01)), 1.0, MAX_PIECE_SCALE)
	armies.set_fig_scale(maxf(lerpf(2.4, 1.0, smoothstep(0.0, 0.8, z)), min_scale))
	## #125: where even piece scale leaves a man-sized figure too small to read, the armies become stands
	## (stands.gd, with hysteresis); the figures blend away as the stands grow in
	var was_k: float = stands.k
	armies.set_blend(stands.step(delta, Armies.Kit.FIG * armies.fig_scale * px_per_unit, px_per_unit, armies))
	if overlay != null and absf(stands.k - was_k) > 0.0001:
		overlay.refresh() ## the count plates ride the stands
	## the model woods and rocks only at the near zoom, on the upper quality rungs (hysteresis): from the
	## default zoom they put two million triangles on screen for little you can see (measured)
	if wv.prop_models and (z < 0.76 or wv.quality >= 2):
		wv.set_prop_models(false)
	elif not wv.prop_models and z > 0.82 and wv.quality < 2:
		wv.set_prop_models(true)
	## the figures' shadows only from the default zoom in (hysteresis)
	if armies.fig_shadows and z < 0.4:
		armies.set_fig_shadows(false)
		wv.set_building_shadows(false)
	elif not armies.fig_shadows and z > 0.46:
		armies.set_fig_shadows(true)
		wv.set_building_shadows(true)
	## the woods' ink outlines only close in (hysteresis, so a zoom never flickers them)
	if wv.prop_outlines and z < 0.62:
		wv.set_prop_outlines(false)
	elif not wv.prop_outlines and z > 0.68:
		wv.set_prop_outlines(true)
	## Look A borrows Look B's glossy sea close in (the director's call on PR #81)
	if wv.look == "cel":
		wv.wmat.set_shader_parameter("toon", 1.0 - smoothstep(0.55, 0.9, z))


func _keys_allowed() -> bool:
	if not is_visible_in_tree() or _covered():
		return false
	var fo := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	return not (fo is LineEdit or fo is TextEdit)


func _covered() -> bool:
	return cover_check.is_valid() and bool(cover_check.call())


# ------------------------------------------------------------------ frame

func _process(delta: float) -> void:
	if not prepared:
		if (_task >= 0 and WorkerThreadPool.is_task_completed(_task)) or (_task < 0 and _terrain != null):
			terrain_now()
			_build_world()
		queue_redraw()
		return
	var live := is_visible_in_tree() and not _covered()
	if live != _live:
		_live = live
		_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if live else SubViewport.UPDATE_ONCE
	if not live:
		return
	_fit_viewport()
	if overlay != null and (hover_id != "" or _playing):
		overlay.queue_redraw()
	_camera(delta)
	if not wv.sweeps.is_empty():
		wv.step_sweeps(delta * (armies.speed if _playing else 1.0))
	if not _flash.is_empty():
		for id in _flash.keys():
			_flash[id] = float(_flash[id]) - delta * 1.6
			if float(_flash[id]) <= 0.0:
				_flash.erase(id)
		_sync_marks()
	fps_samples.append(delta)
	if fps_samples.size() > 240:
		fps_samples.pop_front()
	_watch_speed(delta)


func _fit_viewport(force: bool = false) -> void:
	var s: float = 1.0
	if is_inside_tree():
		s = get_viewport().get_final_transform().get_scale().x
	_px = clampf(s, 1.0, MAX_PX)
	var want := Vector2i(maxi(int(size.x * _px), 64), maxi(int(size.y * _px), 64))
	if _vp.size != want:
		_vp.size = want
		force = true
	wv.view_size = Vector2(_vp.size)
	if force or _fit_size != size:
		_fit_size = size
		queue_redraw() ## the viewport's texture is drawn once per size; its frames update by themselves
		_compute_fit()
		if zoom <= 0.001:
			fit_whole(true)


func _watch_speed(delta: float) -> void:
	## a slower machine sheds the dearest effects a step at a time: under 40 fps for 3 s together
	if not auto_quality or wv.quality >= 3:
		return
	if delta > 1.0 / 40.0:
		_slow += delta
	else:
		_slow = maxf(0.0, _slow - delta * 0.5)
	if _slow > 3.0:
		_slow = 0.0
		set_quality_rung(wv.quality + 1)


## A quality rung (world_view.gd set_quality: the ladder steps down by itself, _watch_speed). From
## Armies.MUSICIAN_OFF_RUNG down the musicians stand down from every colour party (#125, #92's cost); the
## bearers stay (they carry the banners).
func set_quality_rung(q: int) -> void:
	wv.set_quality(q)
	var keep := Armies.musicians_at(wv.quality)
	if keep == Armies.musicians:
		return
	Armies.musicians = keep
	if shown != null and not _playing:
		armies.show_state(shown, seats, plan_of_orders())
		if overlay != null:
			overlay.refresh()


func _draw() -> void:
	if prepared:
		draw_texture_rect(_vp.get_texture(), Rect2(Vector2.ZERO, size), false)
		return
	draw_rect(Rect2(Vector2.ZERO, size), SEA_VEIL)
	var f := get_theme_default_font()
	var text := "Raising the land..."
	var w: float = f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
	draw_string(f, Vector2((size.x - w) * 0.5, size.y * 0.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, UiPalette.TEXT_SECONDARY)


# ------------------------------------------------------------------ input

func _gui_input(event: InputEvent) -> void:
	if not prepared:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			zoom_at(mb.position, 0.07 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -0.07)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_press = true
				_drag = false
				_press_pos = mb.position
				_snap_rig()
				_drag_ground = unproject(mb.position)
				if mb.double_click and not _playing:
					var pid := province_at(mb.position)
					if can_closeup(pid):
						if map != null and map.selected_province_id != pid:
							map.select_province(pid)
						enter_closeup(pid)
					elif not pid.is_empty():
						focus_on(pid)
			else:
				if _press and not _drag:
					click(mb.position)
				_press = false
				_drag = false
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_press = mb.pressed
			_drag = mb.pressed
			if mb.pressed:
				_snap_rig()
				_drag_ground = unproject(mb.position)
			accept_event()
		elif CodexLink.is_open_click(mb):
			var key := codex_key_at(mb.position)
			if not key.is_empty() and map != null:
				map.request_codex(key)
			accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _press and not _drag and mm.position.distance_to(_press_pos) > DRAG_START:
			_drag = true
		if _drag:
			## the ground under the hand stays under the hand
			_snap_rig()
			var now := unproject(mm.position)
			_move_goal(_drag_ground - now)
			_snap_rig()
		else:
			hover(mm.position)


## A click on the board (also what tests and tools call): skips a playback; otherwise selects the army
## formation under it, or the province. With one of your armies selected, a click on another
## province's army (or its land) orders the move there, exactly as on the 2D map.
func click(local: Vector2) -> void:
	if _playing:
		skip_playback()
		return
	if map == null:
		return
	var aid := army_at(local)
	if not aid.is_empty():
		click_army(aid)
		return
	var pid := province_at(local)
	if not pid.is_empty():
		map.select_province(pid)


## An army formation (or its count plate) was clicked.
func click_army(aid: String) -> void:
	if map == null or map.state == null:
		return
	var army: Army = map.state.find_army(aid)
	if army == null:
		return
	var mover: Army = map.state.find_army(map.selected_army_id)
	if mover != null and mover.owner == map.viewing_faction_id and mover.location != army.location:
		map.select_province(army.location) ## your army is selected: this orders the move there
	else:
		map.select_army(aid)


## The mouse is over `local`: the province and army under it, the ground's hover band, the move preview.
func hover(local: Vector2) -> void:
	var pid := province_at(local)
	var aid := army_at(local)
	hover_army = aid
	set_meta(CodexLink.META, TooltipText.codex_for("army_units") if not aid.is_empty() else TooltipText.codex_for("province"))
	if pid == hover_id:
		return
	hover_id = pid
	if map != null:
		if pid.is_empty():
			map.clear_preview()
		else:
			map.preview_move(pid)
		_sync_marks()
	if overlay != null:
		overlay.queue_redraw()


func codex_key_at(local: Vector2) -> String:
	if not army_at(local).is_empty():
		return TooltipText.codex_for("army_units")
	if not province_at(local).is_empty():
		return TooltipText.codex_for("province")
	return ""


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and prepared:
		hover_army = ""
		if not hover_id.is_empty():
			hover_id = ""
			if map != null:
				map.clear_preview()
			_sync_marks()


## The tooltip of whatever is under the mouse: an army's breakdown (as its 2D badge), or the province's
## (as its 2D region), with the 3D board's marks in words and the income breakdown.
func _get_tooltip(at_position: Vector2) -> String:
	if not prepared or map == null or map.state == null:
		return ""
	var aid := army_at(at_position)
	if not aid.is_empty():
		return overlay.army_tooltip(aid)
	var pid := province_at(at_position)
	if pid.is_empty():
		return ""
	return overlay.province_tooltip(pid)


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo or not prepared or not _keys_allowed():
		return
	match k.keycode:
		KEY_ESCAPE:
			if not closeup.is_empty():
				exit_closeup()
				get_viewport().set_input_as_handled()
		KEY_SPACE:
			if _playing:
				skip_playback()
				get_viewport().set_input_as_handled()
		KEY_C, KEY_HOME:
			exit_closeup(true)
			focus_capital()
			get_viewport().set_input_as_handled()
		KEY_F:
			fit_whole()
			get_viewport().set_input_as_handled()
		KEY_L:
			look = "painted" if wv.look == "cel" else "cel"
			wv.set_look(look)
			wv.set_effects(true)
			get_viewport().set_input_as_handled()
		KEY_EQUAL, KEY_KP_ADD:
			zoom_at(size * 0.5, 0.1)
			get_viewport().set_input_as_handled()
		KEY_MINUS, KEY_KP_SUBTRACT:
			zoom_at(size * 0.5, -0.1)
			get_viewport().set_input_as_handled()


## Mean frames per second over the recent frames (perf probes).
func measured_fps() -> float:
	if fps_samples.is_empty():
		return 0.0
	var sum := 0.0
	for d in fps_samples:
		sum += float(d)
	return float(fps_samples.size()) / maxf(sum, 0.0001)
