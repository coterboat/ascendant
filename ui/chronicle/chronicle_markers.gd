class_name ChronicleMarkers
extends Control
## UX-6 (design/UX_WAR_TABLE.md §5.2, "Markers"): each card on view in the open Chronicle puts a numbered marker at its province on the
## board, the same number as the card. They go when the card is dismissed or the column closes. This layer sits in the Table under every
## plaque and card, and ignores the mouse (the board keeps its picking). It follows the camera: each frame it projects the province's centre
## through the 3D board (Board3D.project), or reads the 2D region's place, so a marker stays on its province as the board is panned and zoomed.
## The markers show nothing but a number and a province the viewer's own report named.
##
##   set_markers([{"number", "province", "id"}])   what to show now ([] clears it)
##   pulse(id)                                     swell one marker (its card's place chip was pressed)
##   marker(id) -> NumberBadge                     for tests
##   point_of(province_id) -> Vector2              where a province is, in this layer's pixels (Vector2(-99999, -99999) when off screen or unknown)

const OFFSCREEN := Vector2(-99999, -99999)
## Markers on one province fan out sideways by this much, so none hides another.
const FAN := 15.0

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
			(_markers[id] as Node).queue_free()
			_markers.erase(id)
	for m in list:
		var id := String(m.id)
		if not _markers.has(id):
			var b := NumberBadge.new(int(m.number), 24.0)
			b.name = "Marker_%s" % id.validate_node_name()
			add_child(b)
			_markers[id] = b
		(_markers[id] as NumberBadge).set_number(int(m.number))
	set_process(not _wanted.is_empty())
	visible = not _wanted.is_empty()
	_place()


func marker(id: String) -> NumberBadge:
	return _markers.get(id, null)


func marker_ids() -> Array:
	return _markers.keys()


func pulse(id: String) -> void:
	var b: NumberBadge = _markers.get(id, null)
	if b != null:
		b.pulse()


func _process(_delta: float) -> void:
	_place()


func _place() -> void:
	var seen := {}  # province -> how many markers it already has
	for m in _wanted:
		var b: NumberBadge = _markers.get(String(m.id), null)
		if b == null:
			continue
		var p := point_of(String(m.province))
		var shown := p.x > -99990.0
		b.visible = shown
		if not shown:
			continue
		var k := int(seen.get(String(m.province), 0))
		seen[String(m.province)] = k + 1
		b.position = (p + Vector2(k * FAN, 0.0) - b.size * 0.5).round()


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
