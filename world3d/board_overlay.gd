## The 2D over the 3D board (design/3D_DIRECTION.md 3.3, "text is never in 3D"): small Controls and
## drawings projected from the world every frame, at native resolution, through the board's project().
## Kept minimal, because the 3D armies are the markers (the critic's warning):
##   * each province's plate: its name (a crown on a capital, a tower on a fort) and its income, with
##     the income's breakdown and codex link on hover; a Sworn Vassals pennant and an heir countdown
##     badge when the map has them (their tooltips are the map's own);
##   * each army's count plate above its formation: the seat emblem and the unit count, the 2D badge's
##     tooltip and codex link, a click selects the army (a ruler's plate wears the gilt ring);
##   * the order arrows: every queued move drawn as a ribbon along the roads it marches (a King's Roads
##     move bends through its middle province's centre, ringed in gilt), and a dashed preview of the
##     move a click would order while you hover;
##   * during a turn's playback: a clash marker at each battle, and the playback bar (speed, skip);
##   * the board's legend in the corner, whose tooltip explains every mark on the land.
## Reads the map screen (state, selection, orders, regions' marks) and never changes the game.
extends Control

const Terrain3D := preload("res://world3d/terrain3d.gd")
const Playback := preload("res://world3d/playback.gd")
const Models := preload("res://world3d/models.gd")
const ARROW := Color("#FFFFFF")
const ARROW_HALO := Color(0.102, 0.086, 0.071, 0.85)
const LEGEND := "The 3D board, what you see:\n- A province's colour wash and inner border: its owner, in their player colour.\n- A white band inside a province: the one you selected. A cream band: the one under the mouse.\n- A soft gilt glow at the edges: where your selected army can march this turn.\n- A dashed gilt band: a King's Roads destination two provinces away.\n- Figures: each army as blocks of its units (a block per unit type, %s), its commander and banner bearer at the back. The plate above gives the exact count.\n- Translucent figures in a yard: the recruits you queued. Only you see them.\n- White arrows along the roads: your queued moves.\n- Crossed swords during a turn's playback: a battle. The turn report has the full story.\n\nDrag or WASD to pan, the wheel to zoom, double-click to glide to a province, C your capital, F the whole map, L Look A or B. Settings can switch to the 2D map."

var board: Control ## board3d.gd
var _plates := {} ## province id -> {"root": Control, "name": Label, "income": Label, "glyph": Control, "pennant": Control, "badge": Label}
var _army_plates := {} ## army id -> PanelContainer
var _built_for: GameState = null
var _army_sig := ""
var _ghost_plates: Array = [] ## [PanelContainer], one per ghost block, in ghost_list() order
var _ghost_sig := ""
var _play_bar: PanelContainer
var _play_label: Label
var _speed_buttons := {}
var _legend: Label
var _playing := false
var _last_view := Transform3D() ## the camera when the plates were last placed
var _dirty := true ## something changed: place the plates and redraw this frame


func _init() -> void:
	name = "BoardOverlay"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_legend()
	_build_play_bar()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


# ------------------------------------------------------------------ building

## The map changed (state, selection, orders): rebuild what depends on it.
func refresh() -> void:
	var map: Control = board.map
	if map == null or map.state == null:
		return
	if _built_for != map.state:
		_built_for = map.state
		_build_province_plates()
	_update_province_marks()
	_dirty = true
	var sig := "%s|%s|%s" % [map.state.get_instance_id(), map.selected_army_id, board.armies.armies.size()]
	if sig != _army_sig and not _playing:
		_army_sig = sig
		_build_army_plates()
	var ghosts: Array = board.armies.ghost_list()
	var gsig := ""
	for g in ghosts:
		gsig += "%s:%s;" % [g["province"], ",".join(PackedStringArray(g["types"]))]
	if gsig != _ghost_sig:
		_ghost_sig = gsig
		_build_ghost_plates(ghosts)
	## the legend and the playback bar stay above every plate
	move_child(_legend, get_child_count() - 1)
	move_child(_play_bar, get_child_count() - 1)
	queue_redraw()


## A small dashed plate over each block of queued recruits: how many, and what they are.
func _build_ghost_plates(ghosts: Array) -> void:
	for g in _ghost_plates:
		(g as Node).queue_free()
	_ghost_plates.clear()
	var map: Control = board.map
	var st: GameState = map.state
	for g in ghosts:
		var counts := {}
		var order: Array = []
		for t in g["types"]:
			if not counts.has(t):
				counts[t] = 0
				order.append(t)
			counts[t] += 1
		var parts: Array = []
		for t in order:
			parts.append("%d %s" % [counts[t], _unit_name(st, String(g["owner"]), t)])
		var p := st.find_province(g["province"])
		var where: String = p.name if p != null else "your capital"
		var pc := PanelContainer.new()
		pc.name = "GhostPlate_%s" % String(g["province"])
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(UiPalette.PANEL_BG, 0.75)
		sb.border_color = UiPalette.GILT
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 6
		sb.content_margin_right = 6
		pc.add_theme_stylebox_override("panel", sb)
		var lb := Label.new()
		lb.text = "+%d queued" % (g["types"] as Array).size()
		lb.add_theme_font_size_override("font_size", 13)
		lb.add_theme_color_override("font_color", UiPalette.GILT)
		lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pc.add_child(lb)
		pc.mouse_filter = Control.MOUSE_FILTER_PASS
		pc.tooltip_text = TooltipText.plain("Queued recruits: %s" % ", ".join(parts),
			"They are paid when the turn ends and join your armies at %s. The translucent figures show where they will muster; only you see them, and cancelling the order in the side panel removes them." % where)
		CodexLink.attach(pc, TooltipText.codex_for("recruit"), map.request_codex)
		add_child(pc)
		_ghost_plates.append(pc)


func _unit_name(st: GameState, faction_id: String, type_id: String) -> String:
	var f := st.find_faction(faction_id)
	var ut: UnitType = TurnResolver.recruitable_type(f, type_id) if f != null else null
	return ut.name if ut != null else "recruits"


func _build_province_plates() -> void:
	for p in _plates.values():
		(p["root"] as Node).queue_free()
	_plates.clear()
	var map: Control = board.map
	var st: GameState = map.state
	for p in st.provinces:
		if board.wv.terrain.index_of(p.id) < 0:
			continue
		var root := VBoxContainer.new()
		root.name = "Plate_%s" % p.id
		root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_theme_constant_override("separation", -2)
		root.alignment = BoxContainer.ALIGNMENT_CENTER
		add_child(root)
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 3)
		root.add_child(row)
		var glyph: Control = null
		if p.is_capital or p.has_fort:
			glyph = _Glyph.new()
			glyph.kind = "crown" if p.is_capital else "tower"
			glyph.custom_minimum_size = Vector2(20, 16)
			glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
			glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(glyph)
		var name_label := Label.new()
		name_label.name = "NameLabel"
		name_label.text = p.name
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_label.add_theme_font_size_override("font_size", 16 if p.is_capital else 15)
		name_label.add_theme_color_override("font_color", UiPalette.TEXT_PRIMARY)
		name_label.add_theme_color_override("font_outline_color", UiPalette.KEYLINE_INK)
		name_label.add_theme_constant_override("outline_size", 5)
		var plaque := StyleBoxFlat.new()
		plaque.bg_color = Color(UiPalette.KEYLINE_INK, 0.55)
		plaque.set_corner_radius_all(6)
		plaque.content_margin_left = 6
		plaque.content_margin_right = 6
		plaque.content_margin_bottom = 1
		name_label.add_theme_stylebox_override("normal", plaque)
		row.add_child(name_label)
		var income := Breakdown.province_income(st, p.id)
		var inc := Label.new()
		inc.name = "IncomeLabel"
		inc.text = "%d gold" % int(income.total)
		inc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		inc.add_theme_font_size_override("font_size", 13)
		inc.add_theme_color_override("font_color", UiPalette.GILT)
		inc.add_theme_color_override("font_outline_color", UiPalette.KEYLINE_INK)
		inc.add_theme_constant_override("outline_size", 5)
		inc.mouse_filter = Control.MOUSE_FILTER_PASS
		inc.tooltip_text = TooltipText.from_breakdown(income)
		CodexLink.attach(inc, TooltipText.codex_for("province_income", income), map.request_codex)
		var pid: String = p.id
		inc.gui_input.connect(func(e: InputEvent):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				board.map.select_province(pid)
				inc.accept_event())
		root.add_child(inc)
		_plates[p.id] = {"root": root, "name": name_label, "income": inc, "glyph": glyph, "pennant": null, "badge": null, "sprout": null}


## The map's Sworn Vassals pennants and heir countdowns, mirrored onto the plates (their tooltips are
## the regions' own, codex links included).
func _update_province_marks() -> void:
	var map: Control = board.map
	for id in _plates.keys():
		var pl: Dictionary = _plates[id]
		var region = map.regions.get(id)
		if region == null:
			continue
		var want_pennant: bool = region.vassal_marker != null
		if want_pennant and pl["pennant"] == null:
			var pen := _Pennant.new()
			pen.custom_minimum_size = Vector2(22, 24)
			pen.mouse_filter = Control.MOUSE_FILTER_PASS
			(pl["root"].get_child(0) as Control).add_child(pen)
			pl["pennant"] = pen
		if pl["pennant"] != null:
			var pen2: Control = pl["pennant"]
			pen2.visible = want_pennant
			if want_pennant:
				pen2.seat = region.vassal_seat
				pen2.tooltip_text = region.vassal_marker.tooltip_text
				pen2.set_meta(CodexLink.META, CodexLink.key_at(region.vassal_marker))
				if not pen2.has_meta("hooked"):
					pen2.set_meta("hooked", true)
					pen2.gui_input.connect(func(e: InputEvent):
						if CodexLink.is_open_click(e) and pen2.has_meta(CodexLink.META):
							map.request_codex(String(pen2.get_meta(CodexLink.META))))
				pen2.queue_redraw()
		var wm: Control = region.wild_marker if "wild_marker" in region else null
		if wm != null and pl.get("sprout") == null:
			var sp := _Sprout.new()
			sp.custom_minimum_size = Vector2(20, 22)
			sp.mouse_filter = Control.MOUSE_FILTER_PASS
			(pl["root"].get_child(0) as Control).add_child(sp)
			sp.gui_input.connect(func(e: InputEvent):
				if CodexLink.is_open_click(e) and sp.has_meta(CodexLink.META):
					map.request_codex(String(sp.get_meta(CodexLink.META))))
			pl["sprout"] = sp
		if pl.get("sprout") != null:
			var sp2: Control = pl["sprout"]
			sp2.visible = wm != null
			if wm != null:
				sp2.tooltip_text = wm.tooltip_text
				sp2.set_meta(CodexLink.META, CodexLink.key_at(wm))
		var cb: Label = region.countdown_badge
		if cb != null and pl["badge"] == null:
			var b := Label.new()
			b.name = "CountdownBadge"
			b.add_theme_font_size_override("font_size", 12)
			b.add_theme_color_override("font_color", UiPalette.GILT)
			var style := StyleBoxFlat.new()
			style.bg_color = Color(UiPalette.PANEL_BG, 0.92)
			style.border_color = UiPalette.GILT
			style.set_border_width_all(1)
			style.set_corner_radius_all(6)
			style.content_margin_left = 5
			style.content_margin_right = 5
			b.add_theme_stylebox_override("normal", style)
			b.mouse_filter = Control.MOUSE_FILTER_PASS
			b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			(pl["root"] as Control).add_child(b)
			pl["badge"] = b
		if pl["badge"] != null:
			var b2: Label = pl["badge"]
			b2.visible = cb != null
			if cb != null:
				b2.text = cb.text
				b2.tooltip_text = cb.tooltip_text
				b2.set_meta(CodexLink.META, CodexLink.key_at(cb))


func _build_army_plates() -> void:
	for p in _army_plates.values():
		(p as Node).queue_free()
	_army_plates.clear()
	var map: Control = board.map
	var st: GameState = map.state
	var seats: Array = map.seat_order()
	for a in st.armies:
		var seat: int = UiPalette.seat_index(st, a.owner, seats)
		var col: Color = UiPalette.seat_color(seat)
		var selected: bool = a.id == map.selected_army_id
		var pc := PanelContainer.new()
		pc.name = "ArmyPlate_%s" % a.id.validate_node_name()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(UiPalette.PANEL_BG, 0.9)
		sb.border_color = UiPalette.SELECTION if selected else col
		sb.set_border_width_all(3 if selected else 2)
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 4
		sb.content_margin_right = 6
		sb.content_margin_top = 0
		sb.content_margin_bottom = 0
		if a.ruler != null:
			## the ruler's second, gilt ring (STYLE_BIBLE.md 2.4)
			sb.shadow_color = UiPalette.GILT
			sb.shadow_size = 3
		pc.add_theme_stylebox_override("panel", sb)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 3)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pc.add_child(hb)
		var em := SeatEmblem.new(seat, SeatEmblem.Look.TOKEN, 15.0)
		em.mouse_filter = Control.MOUSE_FILTER_IGNORE
		em.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(em)
		var lb := Label.new()
		lb.text = RulerPanel.badge_text(a) if a.ruler != null else str(a.units.size())
		lb.add_theme_font_size_override("font_size", 15)
		lb.add_theme_color_override("font_color", UiPalette.TEXT_PRIMARY)
		lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(lb)
		pc.tooltip_text = army_tooltip(a.id, false)
		pc.mouse_filter = Control.MOUSE_FILTER_PASS  ## the wheel and drags go on to the board
		pc.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		CodexLink.attach(pc, "ruler_army" if a.ruler != null else TooltipText.codex_for("army_units", Breakdown.army_units(st, a.id)), map.request_codex)
		var aid: String = a.id
		pc.gui_input.connect(func(e: InputEvent):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				board.click_army(aid)
				pc.accept_event())
		add_child(pc)
		_army_plates[a.id] = pc


# ------------------------------------------------------------------ tooltips

## A province's tooltip on the 3D board: its 2D region's own tooltip (name, terrain and how it grew,
## owner, the King's Roads or Forest Stride note when it is a road destination, its codex link), with the
## 2D marks replaced by the 3D board's in words, plus its income's breakdown lines.
func province_tooltip(pid: String) -> String:
	var map: Control = board.map
	var st: GameState = map.state
	var p := st.find_province(pid)
	var region = map.regions.get(pid)
	if p == null or region == null:
		return ""
	var seats: Array = map.seat_order()
	var seat: int = UiPalette.seat_index(st, p.owner, seats)
	var marks := "Neutral: no colour wash." if seat < 0 else "Player %d's province: %s wash and inner border, %s emblem on its armies' plates." % [
		seat + 1, UiPalette.seat_color_name(seat), SeatEmblem.shape_of(seat)]
	if p.is_capital:
		marks += " Capital (the crown, and the fortress whose yard musters its armies)."
	elif p.has_fort:
		marks += " Fort (the tower)."
	var text: String = String(region.tooltip_text)
	var at := text.rfind("\n\nCodex: ")
	if at >= 0:
		text = text.substr(0, at)
	text = text.replace(TooltipText.wrap_text(region.marks_text(p)), TooltipText.wrap_text(marks))
	text = text.replace(region.marks_text(p), marks)
	text = text.replace("dashed gilt ring", "dashed gilt band").replace("Click to see its terrain, income and armies.",
		"Click to see its terrain, income and armies; double-click to glide there.")
	## the income's breakdown lines (its long explanation is on the plate's gold, with the income's codex link)
	var income: Dictionary = Breakdown.province_income(st, pid).duplicate(true)
	income["description"] = ""
	text += "\n\n" + TooltipText.from_breakdown(income).strip_edges()
	return CodexLink.with_link(text, TooltipText.codex_for("province"))


## An army's tooltip: its 2D badge's own (its units' breakdown or the ruler's summary, whose it is, a
## heal forecast when Hallowed Land or the Forges will heal it), with how to read its figures.
func army_tooltip(aid: String, with_link: bool = true) -> String:
	var map: Control = board.map
	var st: GameState = map.state
	var a: Army = st.find_army(aid)
	if a == null:
		return ""
	var key: String = "ruler_army" if a.ruler != null else TooltipText.codex_for("army_units", Breakdown.army_units(st, a.id))
	var text := ""
	var region = map.regions.get(a.location)
	var badge: Control = region.army_box.get_node_or_null("Army_%s" % a.id.validate_node_name()) if region != null else null
	if badge != null:
		text = String(badge.tooltip_text)
		var at := text.rfind("\n\nCodex: ")
		if at >= 0:
			text = text.substr(0, at)
		text = text.replace(" badge, ", " plate, ").replace("outside the badge", "on the plate")
	else:
		text = RulerPanel.summary(st, a) if a.ruler != null else TooltipText.from_breakdown(Breakdown.army_units(st, a.id))
	if a.ruler == null:
		text += "\n\n" + TooltipText.wrap_text("Its figures stand in a block per unit type (%s); the plate has the exact number." % Models.block_rule_text())
	return CodexLink.with_link(text, key) if with_link else text


# ------------------------------------------------------------------ every frame

func _process(_delta: float) -> void:
	if board == null or not board.prepared or board.map == null or not is_visible_in_tree():
		return
	## only when the camera moved, a turn is playing, or the map changed: an idle board costs nothing here
	var view: Transform3D = board.wv.cam_xform
	if not _dirty and not _playing and view.is_equal_approx(_last_view):
		return
	_dirty = false
	_last_view = view
	var t = board.wv.terrain
	var vp: Vector2 = size
	for id in _plates.keys():
		var pl: Dictionary = _plates[id]
		var root: Control = pl["root"]
		var i: int = t.index_of(id)
		var c: Vector2 = t.centres[i]
		var r: float = t.stage_r[i]
		## under the stage (south), so the armies' plates above it stay clear
		var s: Vector2 = board.project(c + Vector2(0, r * (0.95 if t.is_capital[i] else 1.15)), 2.0)
		if root.size.x <= 1.0:
			root.reset_size()
		root.position = (s - Vector2(root.size.x * 0.5, 0.0)).round()
		root.visible = s.x > -200 and s.x < vp.x + 200 and s.y > -60 and s.y < vp.y + 60
	var placed: Array = []
	for id in _army_plates.keys():
		var pc: PanelContainer = _army_plates[id]
		if _playing:
			pc.visible = false
			continue
		var s2: Vector2 = board.army_plate_point(id)
		if s2.x < -9999:
			pc.visible = false
			continue
		if pc.size.x <= 1.0:
			pc.reset_size()
		var rect := Rect2(s2 - Vector2(pc.size.x * 0.5, pc.size.y), pc.size)
		## a simple declutter: a plate that would sit on another one moves up above it
		for k in 4:
			var hit := false
			for o in placed:
				if (o as Rect2).grow(1.0).intersects(rect):
					rect.position.y = (o as Rect2).position.y - rect.size.y - 2.0
					hit = true
			if not hit:
				break
		placed.append(rect)
		pc.position = rect.position.round()
		pc.visible = s2.x > -100 and s2.x < vp.x + 100 and s2.y > -50 and s2.y < vp.y + 50
	var ghosts: Array = board.armies.ghost_list()
	for i in _ghost_plates.size():
		var gp: PanelContainer = _ghost_plates[i]
		if i >= ghosts.size() or _playing:
			gp.visible = false
			continue
		var s3: Vector2 = board.project3(ghosts[i]["anchor"])
		if gp.size.x <= 1.0:
			gp.reset_size()
		var grect := Rect2(s3 - Vector2(gp.size.x * 0.5, gp.size.y), gp.size)
		for k in 4:
			var hit := false
			for o in placed:
				if (o as Rect2).grow(1.0).intersects(grect):
					grect.position.y = (o as Rect2).position.y - grect.size.y - 2.0
					hit = true
			if not hit:
				break
		placed.append(grect)
		gp.position = grect.position.round()
		gp.visible = s3.x > -100 and s3.x < vp.x + 100 and s3.y > -50 and s3.y < vp.y + 50
	if _playing:
		_play_label.text = _play_text()
	queue_redraw()


func _draw() -> void:
	if board == null or not board.prepared or board.map == null:
		return
	var map: Control = board.map
	if not _playing and map.orders != null and map.state != null:
		for o in map.orders.orders():
			if o is MoveOrder:
				_draw_move(o.army_id, o.to, o.via if o.is_road_move() else "", false)
		## the hover preview: the move a click would order, dashed
		var army: Army = map.state.find_army(map.selected_army_id)
		var hov: String = board.hover_id
		if army != null and army.owner == map.viewing_faction_id and not hov.is_empty() and hov != army.location \
				and map.hover_panel.visible:
			var via := ""
			var dest: Dictionary = map.orders.road_destinations(army.id)
			if dest.has(hov) and not (dest[hov] as Array).is_empty():
				via = dest[hov][0]
			var here: Province = map.state.find_province(army.location)
			if (here != null and here.neighbors.has(hov)) or not via.is_empty():
				_draw_move(army.id, hov, via, true)
	if _playing:
		for c in board.armies.clashes_now():
			_draw_clash(board.project3(c["at"] + Vector3(0, 10, 0)), float(c["k"]), String(c["label"]))


## A move along the roads: [army's province, (the way through), destination], each hop centre to the
## border crossing to the next centre, projected point by point so it lies along the land.
func _draw_move(army_id: String, to: String, via: String, preview: bool) -> void:
	var map: Control = board.map
	var army: Army = map.state.find_army(army_id)
	if army == null:
		return
	var t = board.wv.terrain
	var hops: Array = [army.location]
	if not via.is_empty():
		hops.append(via)
	hops.append(to)
	var pts := PackedVector2Array()
	for k in range(hops.size() - 1):
		if t.index_of(hops[k]) < 0 or t.index_of(hops[k + 1]) < 0:
			return
		var path: PackedVector2Array = t.road_path(hops[k], hops[k + 1])
		for q in range(path.size()):
			if k > 0 and q == 0:
				continue
			pts.append(path[q])
	## start at the edge of the army's stage, end at the edge of the destination's
	var start_r: float = t.stage_r[t.index_of(hops[0])] * 0.75
	var end_r: float = t.stage_r[t.index_of(to)] * 0.8
	var world := _trim(pts, start_r, end_r)
	var screen := PackedVector2Array()
	for p in _resample(world, 5.0):
		var s: Vector2 = board.project(p, 1.5)
		if s.x < -9999:
			return
		screen.append(s)
	if screen.size() < 2:
		return
	var tip: Vector2 = screen[screen.size() - 1]
	var back_i := screen.size() - 1
	while back_i > 0 and screen[back_i].distance_to(tip) < 22.0:
		back_i -= 1
	var dir: Vector2 = (tip - screen[back_i]).normalized()
	var side := Vector2(-dir.y, dir.x)
	var base: Vector2 = tip - dir * 20.0
	var shaft := screen.slice(0, back_i + 1)
	shaft.append(base)
	if preview:
		_dashed(shaft, Color(UiPalette.GILT, 0.95), 5.0)
		draw_colored_polygon(PackedVector2Array([tip, base + side * 9.0, base - side * 9.0]), Color(UiPalette.GILT, 0.95))
		return
	draw_polyline(shaft, ARROW_HALO, 12.0, true)
	draw_polyline(shaft, ARROW, 6.0, true)
	draw_colored_polygon(PackedVector2Array([tip + dir * 3.0, base + side * 15.0, base - side * 15.0]), ARROW_HALO)
	draw_colored_polygon(PackedVector2Array([tip, base + side * 11.0, base - side * 11.0]), ARROW)
	if not via.is_empty():
		var vs: Vector2 = board.project(t.centre_of(via), 1.5)
		draw_circle(vs, 11.0, UiPalette.KEYLINE_HALO)
		draw_circle(vs, 8.0, UiPalette.KEYLINE_INK)
		draw_circle(vs, 6.0, UiPalette.GILT)


static func _trim(pts: PackedVector2Array, a: float, b: float) -> PackedVector2Array:
	var lens := PackedFloat32Array([0.0])
	for i in range(1, pts.size()):
		lens.append(lens[i - 1] + pts[i - 1].distance_to(pts[i]))
	var total: float = lens[lens.size() - 1]
	if total <= a + b + 1.0:
		return pts
	var out := PackedVector2Array()
	out.append(_at(pts, lens, a))
	for i in range(1, pts.size() - 1):
		if lens[i] > a and lens[i] < total - b:
			out.append(pts[i])
	out.append(_at(pts, lens, total - b))
	return out


static func _at(pts: PackedVector2Array, lens: PackedFloat32Array, d: float) -> Vector2:
	for i in range(1, pts.size()):
		if d <= lens[i]:
			var seg: float = maxf(lens[i] - lens[i - 1], 0.001)
			return pts[i - 1].lerp(pts[i], (d - lens[i - 1]) / seg)
	return pts[pts.size() - 1]


static func _resample(pts: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var n: int = maxi(1, int(a.distance_to(b) / step))
		for k in n:
			out.append(a.lerp(b, float(k) / n))
	out.append(pts[pts.size() - 1])
	return out


func _dashed(pts: PackedVector2Array, col: Color, w: float) -> void:
	var acc := 0.0
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		if fmod(acc, 18.0) < 11.0:
			draw_line(a, b, Color(UiPalette.KEYLINE_INK, 0.7), w + 3.0, true)
			draw_line(a, b, col, w, true)
		acc += a.distance_to(b)


## A battle's clash marker: crossed swords in a pulsing ring, with its label.
func _draw_clash(at: Vector2, k: float, label: String) -> void:
	if at.x < -9999:
		return
	var pulse: float = 1.0 + 0.18 * sin(k * TAU * 2.0)
	var r: float = 20.0 * pulse
	draw_circle(at, r + 3.0, Color(UiPalette.KEYLINE_INK, 0.85))
	draw_circle(at, r, Color(UiPalette.NEGATIVE.darkened(0.25), 0.92))
	draw_arc(at, r + 1.5, 0, TAU, 32, UiPalette.GILT, 2.0, true)
	for sgn in [-1.0, 1.0]:
		var d := Vector2(sgn, -1.0).normalized()
		draw_line(at - d * r * 0.62, at + d * r * 0.62, UiPalette.KEYLINE_INK, 6.0, true)
		draw_line(at - d * r * 0.62, at + d * r * 0.62, UiPalette.TEXT_PRIMARY, 3.0, true)
		var hilt: Vector2 = at - d * r * 0.42
		var side := Vector2(-d.y, d.x)
		draw_line(hilt - side * 5.0, hilt + side * 5.0, UiPalette.GILT, 3.0, true)
	var f := get_theme_default_font()
	var w: float = f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	var box := Rect2(at + Vector2(-w * 0.5 - 7.0, r + 6.0), Vector2(w + 14.0, 22.0))
	draw_rect(box, Color(UiPalette.PANEL_BG, 0.92))
	draw_rect(box, UiPalette.GILT, false, 1.0)
	draw_string(f, box.position + Vector2(7.0, 16.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UiPalette.TEXT_PRIMARY)


# ------------------------------------------------------------------ playback bar and legend

func begin_playback(plan: Dictionary, after: GameState) -> void:
	_playing = true
	_play_bar.set_meta("turn", int(plan.get("turn", after.current_turn)))
	_play_bar.set_meta("battles", (plan.get("battles", []) as Array).size())
	_play_bar.visible = true
	_mark_speed(board.armies.speed)
	_play_label.text = _play_text()
	queue_redraw()


func end_playback() -> void:
	_playing = false
	_play_bar.visible = false
	_army_sig = ""
	queue_redraw()


func _play_text() -> String:
	var turn := int(_play_bar.get_meta("turn", 0))
	var n := int(_play_bar.get_meta("battles", 0))
	var what := "the armies march" if n == 0 else ("the armies march, and %s" % ("1 battle is fought" if n == 1 else "%d battles are fought" % n))
	return "Turn %d plays out: %s." % [turn, what]


func _build_play_bar() -> void:
	_play_bar = PanelContainer.new()
	_play_bar.name = "PlaybackBar"
	_play_bar.visible = false
	_play_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UiPalette.PANEL_BG, 0.94)
	style.border_color = UiPalette.GILT
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(8)
	_play_bar.add_theme_stylebox_override("panel", style)
	_play_bar.anchor_left = 0.5
	_play_bar.anchor_right = 0.5
	_play_bar.offset_top = 12
	_play_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_play_bar.tooltip_text = TooltipText.plain("The turn plays out on the board",
		"The armies' moves, battles and captures of the turn that just resolved, exactly as the rules decided them: watching never changes anything. Space or a click on the land skips it, and the turn report opens next. The speed you pick is remembered.")
	add_child(_play_bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_play_bar.add_child(row)
	_play_label = Label.new()
	_play_label.name = "PlaybackLabel"
	_play_label.add_theme_font_size_override("font_size", 17)
	_play_label.add_theme_color_override("font_color", UiPalette.TEXT_PRIMARY)
	_play_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_play_label)
	for v in GameSettings.PLAYBACK_SPEEDS:
		var b := Button.new()
		b.name = "Speed%d" % v
		b.text = "%d×" % v
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 15)
		b.tooltip_text = "Play the turn at %d× speed. The speed is remembered for the next turns." % v
		var speed_v: int = v
		b.pressed.connect(func():
			board.set_playback_speed(float(speed_v))
			_mark_speed(float(speed_v)))
		row.add_child(b)
		_speed_buttons[v] = b
	var skip := Button.new()
	skip.name = "SkipButton"
	skip.text = "Skip (Space)"
	skip.focus_mode = Control.FOCUS_NONE
	skip.add_theme_font_size_override("font_size", 15)
	skip.add_theme_color_override("font_color", UiPalette.GILT)
	skip.tooltip_text = "Skip to the end of the turn: the board shows where everything stands now, and the turn report opens."
	skip.pressed.connect(func(): board.skip_playback())
	row.add_child(skip)


func _mark_speed(v: float) -> void:
	for k in _speed_buttons.keys():
		(_speed_buttons[k] as Button).set_pressed_no_signal(is_equal_approx(float(k), v))


func _build_legend() -> void:
	_legend = Label.new()
	_legend.name = "BoardLegend"
	_legend.text = "Board: drag or WASD to pan · wheel to zoom · C your capital · F whole map  (hover for the legend)"
	_legend.add_theme_font_size_override("font_size", 13)
	_legend.add_theme_color_override("font_color", UiPalette.TEXT_SECONDARY)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UiPalette.PANEL_BG, 0.72)
	style.set_corner_radius_all(6)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 2
	style.content_margin_bottom = 3
	_legend.add_theme_stylebox_override("normal", style)
	_legend.position = Vector2(10, 8)
	_legend.mouse_filter = Control.MOUSE_FILTER_PASS
	var lines: Array = []
	for line in (LEGEND % Models.block_rule_text()).split("\n"):
		lines.append(TooltipText.wrap_text(line) if line.begins_with("- ") or line.length() > TooltipText.WRAP else line)
	_legend.tooltip_text = "\n".join(lines)
	add_child(_legend)


## A crown (a capital) or a tower (a fort), as the 2D map draws them.
class _Glyph extends Control:
	var kind := "crown"

	func _draw() -> void:
		var at := size * 0.5
		var pts: PackedVector2Array
		var col: Color = UiPalette.GILT
		if kind == "crown":
			var w := 8.0
			pts = PackedVector2Array([at + Vector2(-w, 5), at + Vector2(-w, -4), at + Vector2(-w * 0.5, 1), at + Vector2(0, -6),
				at + Vector2(w * 0.5, 1), at + Vector2(w, -4), at + Vector2(w, 5)])
		else:
			col = UiPalette.TEXT_SECONDARY
			pts = PackedVector2Array([at + Vector2(-6, 6), at + Vector2(-6, -5), at + Vector2(-3, -5), at + Vector2(-3, -2),
				at + Vector2(0, -2), at + Vector2(0, -5), at + Vector2(3, -5), at + Vector2(3, -2), at + Vector2(6, -2),
				at + Vector2(6, -5), at + Vector2(6, 6)])
		draw_colored_polygon(pts, col)
		var closed := pts.duplicate()
		closed.append(pts[0])
		draw_polyline(closed, UiPalette.KEYLINE_INK, 1.5, true)


## The Wild Spreads' sprout (M4-2): the province turns to forest at the end of the turn.
class _Sprout extends Control:
	func _draw() -> void:
		var c := Vector2(size.x * 0.5, size.y - 3.0)
		draw_line(c, c + Vector2(0, -12), UiPalette.KEYLINE_INK, 4.0, true)
		draw_line(c, c + Vector2(0, -12), Color("#5E7F35"), 2.0, true)
		for sgn in [-1.0, 1.0]:
			var leaf := PackedVector2Array([c + Vector2(0, -8), c + Vector2(sgn * 8, -14), c + Vector2(sgn * 3, -6)])
			draw_colored_polygon(leaf, Color("#72C47A"))
			var closed := leaf.duplicate()
			closed.append(leaf[0])
			draw_polyline(closed, UiPalette.KEYLINE_INK, 1.2, true)


## The Sworn Vassals pennant (as ProvinceRegion draws it) in the joining faction's colour.
class _Pennant extends Control:
	var seat := -1

	func _draw() -> void:
		var colour := UiPalette.NEUTRAL if seat < 0 else UiPalette.seat_color(seat)
		var pole_x := 4.0
		draw_line(Vector2(pole_x, 1), Vector2(pole_x, 23), UiPalette.KEYLINE_INK, 3.0, true)
		var flag := PackedVector2Array([Vector2(pole_x + 1, 2), Vector2(21, 7), Vector2(pole_x + 1, 13)])
		draw_colored_polygon(flag, colour)
		var closed := flag.duplicate()
		closed.append(flag[0])
		draw_polyline(closed, UiPalette.KEYLINE_INK, 1.5, true)
