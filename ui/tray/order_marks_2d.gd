class_name OrderMarks2D
extends Control
## UX-4 (design/UX_WAR_TABLE.md §3.4, issue #213): the order marks on the 2D map (the 3D board's are in world3d/board_overlay.gd). The same
## tokens (OrderToken, the BOARD look) from the same marks (OrderMarks.board_marks): a march's number in the middle of its arrow, and a
## token in the province for a recruit (the number and "+N units", every recruit made there folded into one), a fortify (walls), a
## storm or sally (siege), a ritual and a muster. The layer is in screen space over the map view (the tokens are never scaled with the
## map), and every token takes the first free spot (OrderSpots) clear of every region's name, income and army badges, the Table's pieces and
## the tokens placed before it, so a number never sits on a label.
##
## The layer takes no clicks of its own (MOUSE_FILTER_IGNORE); a token takes its own: a click focuses its place and opens its card, a
## right-click cancels it, both through the map screen's own API.

var map: MapScreen = null
var _tokens: Array = []  # [OrderToken]


func _init() -> void:
	name = "OrderMarks2D"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false


## Rebuilds the tokens from the map screen's orders and places them. Hidden while the 3D board is up (it draws its own).
func refresh() -> void:
	for t in _tokens:
		remove_child(t)
		t.queue_free()
	_tokens.clear()
	visible = map != null and map.board == null and map.orders != null and map.state != null
	if not visible:
		return
	for bm in OrderMarks.board_marks(OrderMarks.marks(map.orders)):
		var t := OrderToken.make(bm, map.orders, OrderToken.Look.BOARD)
		t.pressed.connect(func(i: int): map.show_order(i))
		t.cancel_requested.connect(func(i: int): map.cancel_order(i))
		add_child(t)
		_tokens.append(t)
	place()
	if is_inside_tree() and not get_tree().process_frame.is_connected(place):
		get_tree().process_frame.connect(place, CONNECT_ONE_SHOT)  # the regions' labels have their sizes a frame on


## The order tokens now (each has its `mark`).
func tokens() -> Array:
	return _tokens.duplicate()


## The tokens as placed now: each in the first free spot, a march's number along its arrow and the rest round their province.
func place() -> void:
	if not visible or map == null or map.state == null or map.map_canvas == null:
		return
	var canvas: Control = map.map_canvas
	var k: float = canvas.scale.x
	var taken := _taken()
	var bounds := Rect2(Vector2(2.0, 2.0), size - Vector2(4.0, 4.0))
	if size.x < 8.0:
		bounds = Rect2(Vector2.ZERO, Vector2(8192.0, 8192.0))  # no layout yet (a headless test): no edges
	var hud := OrderSpots.hud_rects(map, global_position)
	for tk in _tokens:
		var tok := tk as OrderToken
		tok.set_tight(false)
		tok.size = tok.get_combined_minimum_size()
		var rect := OrderSpots.free_spot(_spots(tok.mark, tok.size, canvas.position, k), taken, bounds, true)
		if rect.size.x <= 0.0:  # no room for the whole token: its number alone, else the spot that overlaps least
			tok.set_tight(true)
			tok.size = tok.get_combined_minimum_size()
			rect = OrderSpots.free_spot(_spots(tok.mark, tok.size, canvas.position, k), taken, bounds, false, hud)
		tok.visible = rect.size.x > 0.0
		if not tok.visible:
			continue
		tok.position = rect.position.round()
		taken.append(rect.grow(2.0))


## What a token must keep clear of: each region's name, income, fort chip, enchantments, heir countdown and army badges (as drawn, through
## the canvas's own transform) and the Table's pieces. UI-CLUTTER (#238): the chip, the enchantments and the countdown too.
func _taken() -> Array:
	var out := OrderSpots.hud_rects(map, global_position)
	for id in map.regions:
		var region: ProvinceRegion = map.regions[id]
		if not region.is_visible_in_tree():
			continue
		for c in [region.name_label, region.income_label, region.fort_chip, region.enchantment_badges, region.countdown_badge, region.army_box]:
			var ctl := c as Control
			if ctl != null and ctl.is_visible_in_tree() and ctl.size.x > 0.0:
				out.append((ctl.get_global_transform() * Rect2(Vector2.ZERO, ctl.size)).grow(2.0))
	return out


## The rects, best first, a token of `sz` may take: along a march's arrow (the middle first), else on a ring round its province.
func _spots(m: Dictionary, sz: Vector2, origin: Vector2, k: float) -> Array:
	if String(m["class"]) == "march":
		var from := String(m.place)
		var to := String(m.to)
		if not MapLayout.has_position(from) or not MapLayout.has_position(to):
			return []
		var a := MapLayout.position_of(from)
		var b := MapLayout.position_of(to)
		var via := String(m.via)
		var pts := PackedVector2Array([origin + a * k, origin + b * k])
		if not via.is_empty() and MapLayout.has_position(via):
			pts = PackedVector2Array([origin + a * k, origin + map._via_bend(a, b, via) * k, origin + b * k])  # a road move bends through its middle province
		return OrderSpots.path_spots(pts, sz)
	var pid := String(m.place)
	var province: Province = map.state.find_province(pid)
	if province == null or not MapLayout.has_position(pid):
		return []
	var r := MapLayout.radius_of(province) * k * 0.85
	return OrderSpots.ring_spots(origin + MapLayout.position_of(pid) * k, r, r, sz)
