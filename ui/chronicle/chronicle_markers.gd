class_name ChronicleMarkers
extends Control
## UX-6 (design/UX_WAR_TABLE.md §5.2, "Markers"): each card on view in the open Chronicle puts a numbered marker at its province on the
## board, the same number as the card. They go when the card is dismissed or the column closes. This layer sits in the Table under every
## plaque and card, and ignores the mouse (the board keeps its picking). It follows the camera: each frame it projects the province's centre
## through the 3D board (Board3D.project), or reads the 2D region's place, so a marker stays on its province as the board is panned and zoomed.
## The markers show nothing but a number and a province the viewer's own report named.
## UI-CLUTTER (#238): a province's markers stand side by side (they fanned 15 px apart at 24 px wide, "1 4 8" unreadable), lift clear
## of the board's plates (the 3D overlay's taken_rects, the 2D names), and each says what it is: hover names its card and the others
## at that province, and a click opens its card in the Chronicle (marker_pressed). Only the discs take the mouse; the layer does not.
##
##   set_markers([{"number", "province", "id", "headline"}])   what to show now ([] clears it)
##   pulse(id)                                     swell one marker (its card's place chip was pressed)
##   marker(id) -> NumberBadge                     for tests
##   point_of(province_id) -> Vector2              where a province is, in this layer's pixels (Vector2(-99999, -99999) when off screen or unknown)

const OFFSCREEN := Vector2(-99999, -99999)
## The gap between the markers that stand side by side on one province.
const GAP := 3.0
## How many times a province's markers lift to clear a plate under them before they stay put (the map framed small at 125% with the
## Chronicle open packs the plates: three was not enough there).
const LIFTS := 8

## A marker was clicked: its card's id (ChronicleHud opens the column at it).
signal marker_pressed(id: String)

var map: MapScreen = null
var _markers := {}  # id -> NumberBadge
var _wanted: Array = []


func _init() -> void:
	name = "ChronicleMarkers"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_process(false)


func set_markers(list: Array) -> void:
	_wanted = list.duplicate()
	var keep := {}
	for m in list:
		keep[String(m.id)] = true
	for id in _markers.keys():
		if not keep.has(id):
			var gone: Node = _markers[id]
			remove_child(gone)  # out of the tree at once, so a new marker of the same id takes its name
			gone.queue_free()
			_markers.erase(id)
	for m in list:
		var id := String(m.id)
		if not _markers.has(id):
			var b := NumberBadge.new(int(m.number), 24.0)
			b.name = "Marker_%s" % id.validate_node_name()
			b.mouse_filter = Control.MOUSE_FILTER_STOP  # the disc takes the mouse: its hover names the card, a click opens it
			b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			b.gui_input.connect(func(e: InputEvent):
				if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
					b.accept_event()
					marker_pressed.emit(id))
			add_child(b)
			_markers[id] = b
		(_markers[id] as NumberBadge).set_number(int(m.number))
	for m in list:
		(_markers[String(m.id)] as Control).tooltip_text = tooltip_for(String(m.id))
	set_process(not _wanted.is_empty())
	visible = not _wanted.is_empty()
	_place()


func marker(id: String) -> NumberBadge:
	return _markers.get(id, null)


func marker_ids() -> Array:
	return _markers.keys()


## The marker discs on the board now: the Table's pieces (TableHud.register_piece_source), each taking the mouse where it draws.
func discs() -> Array:
	return _markers.values().filter(func(b): return is_instance_valid(b) and not (b as Node).is_queued_for_deletion())


func pulse(id: String) -> void:
	var b: NumberBadge = _markers.get(id, null)
	if b != null:
		b.pulse()


func _process(_delta: float) -> void:
	_place()


## What a marker's hover says: its card, and every card on view at the same province, by number.
func tooltip_for(id: String) -> String:
	var mine := {}
	for m in _wanted:
		if String(m.id) == id:
			mine = m
	if mine.is_empty():
		return ""
	var place := String(mine.province)
	var p: Province = map.state.find_province(place) if map != null and map.state != null else null
	var lines := []
	for m in _wanted:
		if String(m.province) == place:
			lines.append("%d. %s" % [int(m.number), String(m.get("headline", ""))])
	return TooltipText.plain("Chronicle card %d" % int(mine.number), "%s\n\nThe Chronicle's cards at %s, by their numbers:\n%s\n\nClick to open this card in the Chronicle." % [
		String(mine.get("headline", "")), p.name if p != null else place, "\n".join(lines)])


## Each province's markers in a row on its point, lifted over any plate of the board's under them, in the order the cards are listed.
func _place() -> void:
	var groups := {}  # province -> its markers' entries, in card order
	for m in _wanted:
		var pid := String(m.province)
		if not groups.has(pid):
			groups[pid] = []
		(groups[pid] as Array).append(m)
	var taken := taken_rects()
	for pid in groups:
		var entries: Array = groups[pid]
		var p := point_of(String(pid))
		var shown := p.x > -99990.0
		var badges := []
		for m in entries:
			var b: NumberBadge = _markers.get(String(m.id), null)
			if b != null:
				b.visible = shown
				badges.append(b)
		if not shown or badges.is_empty():
			continue
		var w: float = (badges[0] as Control).size.x
		var total := badges.size() * w + (badges.size() - 1) * GAP
		var row := Rect2(p - Vector2(total * 0.5, w * 0.5), Vector2(total, w))
		for k in LIFTS:
			var top := INF
			for o: Rect2 in taken:
				if o.intersects(row):
					top = minf(top, o.position.y)
			if top == INF:
				break
			row.position.y = top - w - 2.0
		for i in badges.size():
			(badges[i] as Control).position = (row.position + Vector2(i * (w + GAP), 0.0)).round()
		taken.append(row)


## The board's own text this layer keeps clear of, in its pixels: the 3D board's plates and order marks (BoardOverlay.taken_rects),
## or the 2D map's province names.
func taken_rects() -> Array:
	var out := []
	if map == null or not is_inside_tree():
		return out
	var origin := get_global_rect().position
	var board = map.board
	if board != null and is_instance_valid(board) and board.get("overlay") != null and board.overlay.has_method("taken_rects"):
		var shift: Vector2 = (board.overlay as Control).get_global_rect().position - origin
		for r: Rect2 in board.overlay.taken_rects():
			out.append(Rect2(r.position + shift, r.size))
		return out
	if map.map_canvas == null or not map.map_canvas.is_visible_in_tree():
		return out
	for id in map.regions:
		var label: Control = (map.regions[id] as ProvinceRegion).name_label
		if label != null and label.is_visible_in_tree():
			var r: Rect2 = label.get_global_transform() * Rect2(Vector2.ZERO, label.size)
			out.append(Rect2(r.position - origin, r.size))
	return out


## Where a province's marker belongs, in this layer's pixels: above its centre on the 3D board, over its region on the 2D map.
func point_of(province_id: String) -> Vector2:
	if map == null or not is_inside_tree():
		return OFFSCREEN
	var origin := get_global_rect().position
	var board = map.board
	if board != null and is_instance_valid(board) and board.get("prepared") == true and board.get("wv") != null:
		var terrain = board.wv.terrain
		var i: int = terrain.index_of(province_id)
		if i < 0:
			return OFFSCREEN
		var s: Vector2 = board.project(terrain.centres[i], 12.0)
		if s.x < -99990.0:
			return OFFSCREEN
		return s + Vector2(0, -26) + board.get_global_rect().position - origin  # above the province's stage, clear of its figures
	var region: Control = map.regions.get(province_id, null)
	if region == null or not region.is_inside_tree() or not map.map_canvas.is_visible_in_tree():
		return OFFSCREEN
	return region.get_global_transform() * Vector2(region.size.x * 0.5, region.size.y * 0.02) - origin  # on the region's top rim, clear of its name
