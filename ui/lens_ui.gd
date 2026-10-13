class_name LensUi
extends RefCounted
## UX-7 (#217; design/UX_WAR_TABLE.md §4): the six map lenses on the map screen, plugged into UX-1's LensHost seam. It registers the
## lenses (keys 1 to 6) with the host, owns the legend card (the Table's "legend" piece) and the Lenses button's picker in the system
## row, and puts the active lens on the board that is showing:
##   * the 3D board: the host's feed (MapScreen._sync_board calls it before every board sync) gives WorldView.set_lens the texture and
##     BoardOverlay.set_lens the plate values; with no lens, or while a turn plays out on the board, the board shows none;
##   * the 2D map: each ProvinceRegion's flat colour and plate value (set_lens), redone whenever the map rebuilds its regions.
## What a lens shows is MapLens.build's, worked out once per state, viewer, orders and lens (the viewer's view and own orders only).
##
## On and off (§4.0, §11.4): a lens's key turns it on, the same key, Esc (UiCancel's "lens" step) or ` turns it off; the button's picker
## does the same for the mouse; one at a time; never switched on by the game. Every session starts with lenses off, and so does a
## hotseat seat: the lens goes off when the map's session or viewer changes.
##
##   refresh()          the map has a new state (MapScreen.set_state): redo the lens for it
##   open_picker()      the Lenses button: the list of lenses, with the active one ticked
##   choose(index)      the picker's item `index` (0 to 5 a lens, OFF_ITEM off)
##   result() -> Dictionary   the active lens's MapLens.build result ({} with none)
##   legend, button, picker   the legend card, the Lenses button, its PopupMenu

const OFF_ITEM := 100
const TOOLTIP := "Extra map views (1–6). Off by default."

var map: Control  # the MapScreen
var legend: LensLegend
var button: Button
var picker: PopupMenu
var _result := {}
var _dirty := true
var _gen := 0
var _fed := {}  # board instance id -> the generation it was fed (or -1 for none)
var _seen_viewer := "?"
var _seen_session: Object = null
var _hooked := {}  # board instance id -> true once its playback signals are connected


func _init(p_map: Control) -> void:
	map = p_map
	var host: LensHost = map.lens_host
	for id in MapLens.IDS:
		host.register(id, MapLens.title_of(id), int(MapLens.lens(id).key), _feed)
	host.active_changed.connect(_on_active_changed)
	legend = LensLegend.new()
	map.hud.set_floating("legend", legend)
	button = map.hud.make_system_button("lenses", "Lenses", TooltipText.plain("Lenses", TOOLTIP), open_picker)
	CodexLink.attach(button, "map_lenses", func(k): map.request_codex(k))
	picker = PopupMenu.new()
	picker.name = "LensPicker"
	for i in MapLens.IDS.size():
		var id: String = MapLens.IDS[i]
		var l := MapLens.lens(id)
		picker.add_radio_check_item("%s: %s" % [String(l.title), String(l.question)], i)
		picker.set_item_accelerator(picker.get_item_index(i), int(l.key))
		picker.set_item_tooltip(picker.get_item_index(i), TooltipText.wrap_text("%s, %s." % [String(l.question), String(l.feel)]))
	picker.add_separator()
	picker.add_item("Off (Esc or `)", OFF_ITEM)
	picker.id_pressed.connect(choose)
	button.add_child(picker)
	map.orders_changed.connect(_on_orders_changed)


## The active lens's build ({} when none is on).
func result() -> Dictionary:
	if String(map.lens_host.active_id()).is_empty():
		return {}
	_ensure()
	return _result


## The map has a new state (or a new viewer, or a new session). A new session or viewer turns the lens off; otherwise it is worked
## out again for the new state.
func refresh() -> void:
	var viewer := String(map.viewing_faction_id)
	var session: Object = map.session
	if viewer != _seen_viewer or session != _seen_session:
		_seen_viewer = viewer
		_seen_session = session
		if not String(map.lens_host.active_id()).is_empty():
			map.lens_host.clear()  # every session, and every hotseat seat, starts with lenses off
			return
	_dirty = true
	_apply()


## The Lenses button: the picker under it, the active lens ticked.
func open_picker() -> void:
	var active := String(map.lens_host.active_id())
	for i in MapLens.IDS.size():
		picker.set_item_checked(picker.get_item_index(i), MapLens.IDS[i] == active)
	picker.set_item_disabled(picker.get_item_index(OFF_ITEM), active.is_empty())
	if not button.is_inside_tree():
		return
	var at := button.get_screen_position() + Vector2(0, button.size.y + 2.0)
	picker.popup(Rect2i(Vector2i(at), Vector2i.ZERO))


## The picker's item: a lens (its key's toggle: the active one goes off), or off.
func choose(item: int) -> void:
	if item == OFF_ITEM:
		map.lens_host.clear()
	elif item >= 0 and item < MapLens.IDS.size():
		map.lens_host.toggle(MapLens.IDS[item])


func _on_active_changed(_id: String) -> void:
	_dirty = true
	_apply()
	var board: Control = map.board
	if board != null and String(map.lens_host.active_id()).is_empty():
		_clear_board(board)


func _on_orders_changed() -> void:
	if String(map.lens_host.active_id()).is_empty():
		return
	_dirty = true
	_apply()  # the board is fed again by the sync that follows (MapScreen._orders_changed)


## Works the active lens out again when something it reads changed.
func _ensure() -> void:
	var id := String(map.lens_host.active_id())
	if not _dirty and String(_result.get("id", "")) == id:
		return
	_dirty = false
	_gen += 1
	if id.is_empty() or map.state == null:
		_result = {}
		return
	var own: Array = []
	if map.orders != null and map.state.find_faction(String(map.viewing_faction_id)) != null:
		own = map.orders.orders()
	_result = MapLens.build(id, map.state, String(map.viewing_faction_id), map.seat_order(), own, map.fog_memory)


## The 2D map's regions, the legend and the button follow the active lens.
func _apply() -> void:
	var id := String(map.lens_host.active_id())
	if id.is_empty():
		for pid in map.regions:
			map.regions[pid].set_lens("", {})
		legend.show_legend({}, false)
		map.hud.set_system_label("lenses", "Lenses")
		return
	_ensure()
	var entries: Dictionary = _result.get("entries", {})
	for pid in map.regions:
		map.regions[pid].set_lens(id, entries.get(pid, {}), map.request_codex)
	legend.show_legend(_result.get("legend", {}), map.board == null, map.request_codex)
	map.hud.set_system_label("lenses", "Lenses: %s" % MapLens.title_of(id))


## The host's feed for every lens: the active lens onto the 3D board (MapScreen._sync_board calls it before each sync).
func _feed(board: Object) -> void:
	if board == null or not is_instance_valid(board):
		return
	_hook(board)
	if board.get("prepared") != true or board.get("wv") == null:
		return  # fed when it is ready (_hook)
	if board.has_method("is_playing") and board.is_playing():
		_clear_board(board)
		return  # a turn playing out shows the land as it plays; the lens comes back at its end
	_ensure()
	var key := board.get_instance_id()
	if int(_fed.get(key, -1)) == _gen:
		return
	_fed[key] = _gen
	board.wv.set_lens(String(_result.get("id", "")), _result.get("entries", {}))
	board.overlay.set_lens(_result, map.request_codex)


func _clear_board(board: Object) -> void:
	if board.get("wv") != null and board.wv.has_method("clear_lens"):
		board.wv.clear_lens()
	if board.get("overlay") != null:
		board.overlay.clear_lens()
	_fed[board.get_instance_id()] = -1


## Once per board: it is fed when its land is ready, cleared while a turn plays out and fed again at the end.
func _hook(board: Object) -> void:
	var key := board.get_instance_id()
	if _hooked.has(key):
		return
	_hooked[key] = true
	if board.has_signal("ready_to_show"):
		board.connect("ready_to_show", func(): _refeed(board))
	if board.has_signal("playback_started"):
		board.connect("playback_started", func(): _clear_board(board))
	if board.has_signal("playback_finished"):
		board.connect("playback_finished", func(): _refeed(board))


func _refeed(board: Object) -> void:
	if not is_instance_valid(board) or String(map.lens_host.active_id()).is_empty():
		return
	_fed.erase(board.get_instance_id())
	_feed(board)
