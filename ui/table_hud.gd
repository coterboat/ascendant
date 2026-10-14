class_name TableHud
extends Control
## UX-1 (design/UX_WAR_TABLE.md §1): the Table. The board fills the screen and this layer sits over it (under the
## game screen's Overlays layer, over the 3D board or the 2D map): the realm plaque with the system row under it (top
## left), the notification stack's slot (left edge), the opponent plaque and Menu (top right), and the tray and the End
## turn seal (bottom). The selection card, the guide, the notices, the lens legend and the move forecast float inside the
## board's safe area (TableLayout), each placed so that none overlaps another or a plaque. It replaces the old top bar,
## hint row and side panel of the map screen. Layout and geometry are TableLayout's (pure, tested); this node applies them.
##
## Input (§1.2): the root and every empty area are MOUSE_FILTER_IGNORE, so a click on empty HUD space reaches the board
## beneath and picks the province under it. Only the interactive pieces take the mouse (MOUSE_FILTER_STOP): the plaques,
## the system buttons, the card, the tray, the seal, the Menu button. pieces() lists them; tests/test_table_hud.gd walks
## the tree and holds every other node to IGNORE.
##
## API (later tickets plug in here instead of editing ui/map_screen.gd or ui/game_screen.gd):
##   add_system_button(id, button)    a button in the system row, in SYSTEM_ORDER's place for `id`
##   make_system_button(id, text, tooltip, on_pressed) -> Button   the same, building the button
##   system_button(id) -> Button      the row's button (null when none): the Chronicle and Lenses placeholders are here
##   add_plaque_item(control)         a control at the end of the realm plaque's second line
##   add_seal_item(control)           a control in the seal's slot (End turn, and Results at the end of a game)
##   notification_slot() -> Control   the column on the left edge: UX-6's NoticeStack fills it with medallions, and takes the mouse only where it draws
##   register_piece(control)          a control of someone else's that takes the mouse by design (the medallion stack, the Chronicle column):
##                                    pieces() lists it, so the input contract's test holds it and what is inside it to the rule
##   tray_slot() -> OrderTray         the tray's order slot: UX-4's tokens (ui/tray/), the placed orders by number and then the realm ones, with the
##                                    gold they leave; the hint line shows in its place while it is empty
##   opponent_slot -> HBoxContainer   where the rivals' plaques go
##   set_system_label(id, text)       a system button's label (shown beside its icon when wide, hidden when compact)
##   set_hint(text, tooltip)          the tray's one line of "what to do now"
##   set_floating(kind, control)      the card / legend / hover, which this node positions in the safe area
##   hang(kind, control)              the same for pieces that live elsewhere in the tree: the guide, the notice and the board's
##                                    playback bar, caption and close-up chip (TableLayout.FLOATING is the give-way order)
##   set_chronicle_open(open)         the Chronicle takes its column on the right (UX-6); the safe area narrows
##   pieces(), placed(), overflowed() the pieces that take the mouse, the last layout's rects, and what found no room (tests)
##   safe_area() -> Rect2             where a card, the guide and the notices may go (this node's own coordinates)
##   framing_area() -> Rect2          where a board frames the whole map at first: the safe area right of the card
##   set_seal_pulse(on)               the gentle pulse that tells a new player to press End turn
##   signal layout_changed            the safe area or a floating piece moved
##   signal compact_changed(on)       the window crossed 1600 logical width (the compact Table, §1.3)

signal layout_changed
signal compact_changed(on: bool)
## The system buttons that carry an icon (UX-0a's UiIcons, white masks tinted with the button's colours); the icon's name is the
## button's id except for the two in ICON_OF. A button without one (the ?) keeps its text. Below 1600 logical width the row
## shows the icons only (the tooltips name them): a button's label is kept in its "label" meta and put back when the window is
## wide. The research and magic chips keep their progress text.
const ICON_IDS := ["research", "magic", "ruler", "chronicle", "report", "lenses", "codex"]
const ICON_OF := {"report": "turn", "lenses": "lens"}
const ICON_PX := 20
const KEEP_TEXT := ["research", "magic"]

## The system row's order, left to right. An id not listed goes just before the Codex.
const SYSTEM_ORDER := ["research", "magic", "ruler", "chronicle", "report", "lenses", "codex", "help"]
const PLAQUE_MARGIN := Vector2(8.0, 6.0)
const SEAL_W := 190.0
## The window's size when this node is not in a tree yet (tests): the project's own.
const DEFAULT_VIEWPORT := Vector2(1600, 900)
const PULSE_S := 1.1

var faction_crest: Control  # the viewing faction's banner with the seat emblem pinned on it
var faction_banner: Art.BannerCard
var faction_emblem: SeatEmblem
var faction_label: Label
var turn_label: Label
var gold_label: Label
var plaque: PanelContainer
var plaque_row: HBoxContainer  # the crest, then the two lines
var plaque_trail: HBoxContainer  # the realm plaque's second line after the gold: add_plaque_item
var system_row: HBoxContainer
var opponent_slot: HBoxContainer
var opponent_panel: PanelContainer
var menu_button: Button
var notification_stack: Control
var tray: PanelContainer
var hint_label: Label  # the tray's one line of "what to do now": shown while the tray holds no orders
var tray_tokens: OrderTray  # UX-4: the order tokens (OrderTray, ui/tray/order_tray.gd)
var seal: PanelContainer
var seal_slot: HBoxContainer
## Tests: the size to lay out for when this node has no size of its own (outside a tree).
var viewport_override := Vector2.ZERO
var chronicle_open := false
var compact := false

var left_column: VBoxContainer  # the realm plaque with the system row under it
var right_column: HBoxContainer  # the opponent plaque and Menu
var bottom_row: HBoxContainer  # the tray and the seal
var _system := {}  # id -> Button
var _extra_pieces: Array = []  # register_piece: UX-6's medallion stack and Chronicle column
var _floating := {}  # kind -> Control
var _layout_queued := false
var _last_rects := {}
var _last_overflow := []
var _pulse: Tween = null
var _pulsing := false


func _init() -> void:
	name = "TableHud"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_left()
	_build_notification_stack()
	_build_top_right()
	_build_bottom()
	resized.connect(queue_layout)
	compact_changed.connect(tray_tokens.set_compact)


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED or what == NOTIFICATION_PARENTED:
		queue_layout()


# --- API ------------------------------------------------------------------------------------------

## The size the Table is laid out for: this node's own, or the project's window when it has none yet.
func viewport_size() -> Vector2:
	if viewport_override.x > 0.0 and viewport_override.y > 0.0:
		return viewport_override
	if size.x > 0.0 and size.y > 0.0:
		return size
	return DEFAULT_VIEWPORT


## The board's safe area in this node's coordinates (the window less the bands TableLayout reserves).
func safe_area() -> Rect2:
	return TableLayout.safe_area(viewport_size(), chronicle_open)


## True once the Table has a size of its own (it is in a tree and was laid out): until then there is no window to frame for.
func has_layout() -> bool:
	return size.x > 0.0 and size.y > 0.0


## Where the board frames the whole map: the safe area right of the docked card (TableLayout.framing_area).
func framing_area() -> Rect2:
	return TableLayout.framing_area(viewport_size(), chronicle_open)


func set_chronicle_open(open: bool) -> void:
	if open == chronicle_open:
		return
	chronicle_open = open
	queue_layout()


## Puts `button` in the system row at the place SYSTEM_ORDER gives `id`. A second button for the same id replaces the first.
func add_system_button(id: String, button: Button) -> Button:
	if _system.has(id) and _system[id] != button:
		var old: Button = _system[id]
		if old.get_parent() == system_row:
			system_row.remove_child(old)
		old.queue_free()
	_system[id] = button
	button.focus_mode = Control.FOCUS_NONE
	_give_icon(id, button)
	if button.get_parent() != system_row:
		if button.get_parent() != null:
			button.get_parent().remove_child(button)
		system_row.add_child(button)
	system_row.move_child(button, _system_index(id))
	button.minimum_size_changed.connect(queue_layout, CONNECT_REFERENCE_COUNTED)
	button.visibility_changed.connect(queue_layout, CONNECT_REFERENCE_COUNTED)
	queue_layout()
	return button


## A new system button with its tooltip and press, added with add_system_button.
func make_system_button(id: String, text: String, tooltip: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.name = "%sButton" % id.capitalize()
	b.text = text
	b.tooltip_text = tooltip
	b.add_theme_font_size_override("font_size", 15)
	if on_pressed.is_valid():
		b.pressed.connect(func(): on_pressed.call())
	return add_system_button(id, b)


## The button's icon from UiIcons, tinted like its text; its label is remembered for the wide window.
func _give_icon(id: String, button: Button) -> void:
	if not ICON_IDS.has(id):
		return
	button.icon = UiIcons.icon(String(ICON_OF.get(id, id)), ICON_PX)
	button.expand_icon = false
	button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_constant_override("h_separation", 6)
	button.add_theme_color_override("icon_normal_color", UiPalette.TEXT_PRIMARY)
	button.add_theme_color_override("icon_hover_color", UiPalette.GILT)
	button.add_theme_color_override("icon_pressed_color", UiPalette.GILT)
	button.add_theme_color_override("icon_disabled_color", UiPalette.TEXT_DISABLED)
	if not button.has_meta("label") and not KEEP_TEXT.has(id):
		button.set_meta("label", button.text)
	_fit_label(id, button)


## Icons only below 1600 logical width: a plain button's text goes (its tooltip names it), and comes back when it is wide.
func _fit_label(id: String, button: Button) -> void:
	if not button.has_meta("label") or KEEP_TEXT.has(id):
		return
	button.text = "" if compact else String(button.get_meta("label"))


## Changes a system button's label (a toggle's "...: on"); in the compact Table the icon alone shows.
func set_system_label(id: String, text: String) -> void:
	var b: Button = _system.get(id, null)
	if b == null:
		return
	if b.has_meta("label"):
		b.set_meta("label", text)
		_fit_label(id, b)
	else:
		b.text = text


func system_button(id: String) -> Button:
	return _system.get(id, null)


func system_button_ids() -> Array:
	return _system.keys()


## A control at the end of the realm plaque's second line (after the gold), such as the ruler line.
func add_plaque_item(control: Control) -> void:
	plaque_trail.add_child(control)
	control.minimum_size_changed.connect(queue_layout, CONNECT_REFERENCE_COUNTED)
	queue_layout()


## A control in the seal's slot (End turn; Results takes its place at the end of a game). The seal shows once it has one.
func add_seal_item(control: Control) -> void:
	seal_slot.add_child(control)
	seal.visible = true
	control.minimum_size_changed.connect(queue_layout, CONNECT_REFERENCE_COUNTED)
	queue_layout()


func notification_slot() -> Control:
	return notification_stack


func tray_slot() -> OrderTray:
	return tray_tokens


## UX-6: a control that takes the mouse by design and lives in this Table (the medallion stack in the notification slot, the Chronicle
## column on the right edge). pieces() lists it. It must be MOUSE_FILTER_STOP, and sized to what it draws: an empty area of it would
## swallow the board's clicks.
func register_piece(control: Control) -> void:
	if not _extra_pieces.has(control):
		_extra_pieces.append(control)


## A floating piece the Table positions inside the safe area: "card", "legend" or "hover". It becomes a child of this node.
func set_floating(kind: String, control: Control) -> void:
	_register_floating(kind, control)
	if control.get_parent() != self:
		if control.get_parent() != null:
			control.get_parent().remove_child(control)
		add_child(control)
	control.set_anchors_preset(Control.PRESET_TOP_LEFT)
	queue_layout()


## A floating piece that lives elsewhere in the tree (the first-game guide on the game screen, the notice on its own layer, the
## board's playback bar, caption and close-up chip) and is positioned here all the same: "guide", "notice", "playback", "caption"
## or "closeup". Its parent must cover the window.
func hang(kind: String, control: Control) -> void:
	_register_floating(kind, control)
	control.set_anchors_preset(Control.PRESET_TOP_LEFT)
	queue_layout()


## Every control that takes the mouse by design (MOUSE_FILTER_STOP): the plaque, each system button, the opponent
## plaque, Menu, the tray, the seal and the floating pieces that are Table's own. Everything else is IGNORE.
func pieces() -> Array:
	var out: Array = [plaque, opponent_panel, menu_button, tray, seal]
	for id in _system:
		out.append(_system[id])
	for kind in ["card", "legend"]:
		if _piece(kind) != null:
			out.append(_piece(kind))
	for c in _extra_pieces:
		if is_instance_valid(c):
			out.append(c)
	return out


## The rect each floating piece was given by the last layout, and the pieces that found no free spot (a test reads them).
func placed() -> Dictionary:
	return _last_rects.duplicate()


func overflowed() -> Array:
	return _last_overflow.duplicate()


## The gentle pulse on the seal (a new player, once an order is queued): a slow glow of its border, never a shake.
func set_seal_pulse(on: bool) -> void:
	if on == _pulsing:
		return
	_pulsing = on
	if _pulse != null:
		_pulse.kill()
		_pulse = null
	seal.self_modulate = Color.WHITE
	if on and is_inside_tree():
		_pulse = create_tween().set_loops()
		_pulse.tween_property(seal, "self_modulate", Color(1.5, 1.35, 0.9), PULSE_S).set_trans(Tween.TRANS_SINE)
		_pulse.tween_property(seal, "self_modulate", Color.WHITE, PULSE_S).set_trans(Tween.TRANS_SINE)


func seal_pulsing() -> bool:
	return _pulsing


## Sets the tray's hint line, and its tooltip (the whole how-to).
func set_hint(text: String, tooltip: String = "") -> void:
	hint_label.text = text
	hint_label.tooltip_text = tooltip if not tooltip.is_empty() else TooltipText.wrap_text(text)


# --- layout ---------------------------------------------------------------------------------------

## Lays the floating pieces out at the end of the frame (many things ask in one frame).
func queue_layout() -> void:
	if _layout_queued:
		return
	_layout_queued = true
	_run_layout.call_deferred()


func _run_layout() -> void:
	_layout_queued = false
	relayout()


## Places every floating piece now, from the sizes they ask for.
func relayout() -> void:
	var vp := viewport_size()
	var now_compact := TableLayout.is_narrow(vp)
	if now_compact != compact:
		compact = now_compact
		for id in _system:
			_fit_label(id, _system[id])
		compact_changed.emit(compact)
	# The open Chronicle takes its column on the right (§1.3), so the opponent plaque and Menu keep to the board's side of it.
	var taken := TableLayout.chronicle_width(vp) if chronicle_open else 0.0
	right_column.offset_right = -(PLAQUE_MARGIN.x + taken)
	# The tray and the seal centre on what is left of the window (the bottom band narrows with the column).
	var middle := (vp.x - taken) * 0.5 / maxf(vp.x, 1.0)
	bottom_row.anchor_left = middle
	bottom_row.anchor_right = middle
	var card := _piece("card")
	if card != null and is_instance_valid(card) and card.has_method("fit"):
		card.call("fit", TableLayout.card_max_height(vp, chronicle_open))
	var pieces_now := {}
	for kind in TableLayout.FLOATING:
		var c := _shown(kind)
		if c == null:
			continue
		pieces_now[kind] = _wanted_size(kind, c, vp)
	var result := TableLayout.arrange(vp, pieces_now, chronicle_open)
	_last_rects = result.rects
	_last_overflow = result.overflow
	if _last_rects.has("card") and card != null:
		var squeezed: float = (_last_rects["card"] as Rect2).size.y
		if squeezed < float(pieces_now["card"].y) - 0.5:
			card.call("fit", squeezed)  # a piece above took some of its room: it scrolls
	for kind in _last_rects:
		var placed_piece := _piece(kind)
		if placed_piece != null:
			_apply(placed_piece, _last_rects[kind])
	layout_changed.emit()


func _shown(kind: String) -> Control:
	var c := _piece(kind)
	if c == null or not c.visible:
		return null
	return c


## The floating piece of that kind, or null when there is none or it was freed (the board's playback pieces go with the board when
## the 2D map takes over).
func _piece(kind: String) -> Control:
	if not _floating.has(kind):
		return null
	var c = _floating[kind]
	if c == null or not is_instance_valid(c):
		_floating.erase(kind)
		return null
	return c as Control


## The size a floating piece asks for: its fixed width and the height its content needs there.
func _wanted_size(kind: String, c: Control, vp: Vector2) -> Vector2:
	var minimum := c.get_combined_minimum_size()
	var safe := TableLayout.safe_area(vp, chronicle_open)
	match kind:
		"card":
			var h: float = float(c.call("desired_height")) if c.has_method("desired_height") else minimum.y
			return Vector2(TableLayout.CARD_W, minf(h, TableLayout.card_max_height(vp, chronicle_open)))
		"legend":
			return Vector2(maxf(TableLayout.LEGEND_W, minimum.x), minimum.y)
		"notice":
			return Vector2(maxf(minf(TableLayout.NOTICE_W, safe.size.x - 2.0 * TableLayout.GAP), minimum.x), minimum.y)
		"guide":
			return Vector2(maxf(minimum.x, c.custom_minimum_size.x), minimum.y)
		"hover":
			return Vector2(TableLayout.HOVER_MAX_W, minimum.y)
	return minimum  # playback, closeup, caption: as wide and tall as they are


func _apply(c: Control, r: Rect2) -> void:
	if not is_instance_valid(c):
		return
	c.set_anchors_preset(Control.PRESET_TOP_LEFT)
	c.grow_horizontal = Control.GROW_DIRECTION_END
	c.grow_vertical = Control.GROW_DIRECTION_END
	c.offset_left = r.position.x
	c.offset_top = r.position.y
	c.offset_right = r.end.x
	# A panel takes the height its content needs (it never goes smaller than that); anything else gets the rect's.
	c.offset_bottom = r.position.y if c is PanelContainer else r.end.y


func _register_floating(kind: String, control: Control) -> void:
	if not TableLayout.FLOATING.has(kind):
		push_error("TableHud: '%s' is not a floating piece." % kind)
		return
	if _piece(kind) == control:
		return
	_floating[kind] = control
	control.minimum_size_changed.connect(queue_layout, CONNECT_REFERENCE_COUNTED)
	control.visibility_changed.connect(queue_layout, CONNECT_REFERENCE_COUNTED)
	if control.has_signal("layout_wanted"):
		control.connect("layout_wanted", queue_layout)


func _system_index(id: String) -> int:
	var rank := SYSTEM_ORDER.find(id)
	if rank < 0:
		rank = SYSTEM_ORDER.find("codex")
	var at := 0
	for other in _system:
		if other == id:
			continue
		var r := SYSTEM_ORDER.find(other)
		if r < 0:
			r = SYSTEM_ORDER.find("codex")
		if r <= rank:
			at += 1
	return at


# --- building -------------------------------------------------------------------------------------

## A dark plaque: the panel colour, a keyline, rounded corners.
static func plaque_style(margin_x: int = 10, margin_y: int = 6) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UiPalette.PANEL_BG, 0.94)
	style.border_color = UiPalette.PANEL_BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = margin_x
	style.content_margin_right = margin_x
	style.content_margin_top = margin_y
	style.content_margin_bottom = margin_y
	return style


func _build_left() -> void:
	left_column = VBoxContainer.new()
	left_column.name = "TopLeft"
	left_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_column.add_theme_constant_override("separation", 4)
	left_column.set_anchors_preset(Control.PRESET_TOP_LEFT)
	left_column.position = PLAQUE_MARGIN
	add_child(left_column)
	plaque = PanelContainer.new()
	plaque.name = "RealmPlaque"
	plaque.mouse_filter = Control.MOUSE_FILTER_STOP
	plaque.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	plaque.add_theme_stylebox_override("panel", plaque_style(8, 4))
	left_column.add_child(plaque)
	plaque_row = HBoxContainer.new()
	plaque_row.name = "Row"
	plaque_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plaque_row.add_theme_constant_override("separation", 8)
	plaque.add_child(plaque_row)
	# The crest: the faction's banner with the seat emblem pinned to its lower right corner.
	faction_crest = Control.new()
	faction_crest.name = "FactionCrest"
	faction_crest.custom_minimum_size = Vector2(40, 46)
	faction_crest.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	faction_crest.mouse_filter = Control.MOUSE_FILTER_IGNORE
	faction_crest.visible = false
	faction_banner = Art.banner_card("", 46.0)
	faction_banner.name = "FactionBanner"
	faction_banner.position = Vector2(-2, 0)
	faction_banner.size = Vector2(31, 46)
	faction_crest.add_child(faction_banner)
	faction_emblem = SeatEmblem.new(-1, SeatEmblem.Look.TOKEN, 22.0)
	faction_emblem.name = "FactionEmblem"
	faction_emblem.visible = false
	faction_emblem.position = Vector2(24, 23)
	faction_crest.add_child(faction_emblem)
	plaque_row.add_child(faction_crest)
	var lines := VBoxContainer.new()
	lines.name = "Lines"
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines.add_theme_constant_override("separation", 0)
	lines.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	plaque_row.add_child(lines)
	var first := HBoxContainer.new()
	first.name = "Line1"
	first.mouse_filter = Control.MOUSE_FILTER_IGNORE
	first.add_theme_constant_override("separation", 14)
	lines.add_child(first)
	faction_label = _plaque_label("FactionLabel", "Faction", UiPalette.TYPE_NUMBER, UiPalette.TEXT_PRIMARY, UiFonts.name())
	first.add_child(faction_label)
	turn_label = _plaque_label("TurnLabel", "Turn", UiPalette.TYPE_NUMBER, UiPalette.TEXT_PRIMARY, UiFonts.number())
	first.add_child(turn_label)
	var second := HBoxContainer.new()
	second.name = "Line2"
	second.mouse_filter = Control.MOUSE_FILTER_IGNORE
	second.add_theme_constant_override("separation", 14)
	lines.add_child(second)
	gold_label = _plaque_label("GoldLabel", "Gold", UiPalette.TYPE_BODY, UiPalette.GILT, UiFonts.number())
	second.add_child(gold_label)
	plaque_trail = HBoxContainer.new()
	plaque_trail.name = "Trail"
	plaque_trail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plaque_trail.add_theme_constant_override("separation", 10)
	second.add_child(plaque_trail)
	system_row = HBoxContainer.new()
	system_row.name = "SystemRow"
	system_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	system_row.add_theme_constant_override("separation", 6)
	left_column.add_child(system_row)


func _plaque_label(node_name: String, text: String, font_size: int, color: Color, font: Font) -> Label:
	var l := Label.new()
	l.name = node_name
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_PASS  # tooltips; the plaque under it takes the click
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	l.add_theme_font_override("font", font)  # UX-0a's type tokens: UiFonts by what the text is, UiPalette.TYPE_* for its size
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


func _build_notification_stack() -> void:
	notification_stack = Control.new()
	notification_stack.name = "NotificationStack"
	notification_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notification_stack.anchor_left = 0.0
	notification_stack.anchor_right = 0.0
	notification_stack.anchor_top = 0.0
	notification_stack.anchor_bottom = 1.0
	notification_stack.offset_left = 0.0
	notification_stack.offset_right = TableLayout.STACK_W
	notification_stack.offset_top = TableLayout.TOP_LEFT_H
	notification_stack.offset_bottom = -TableLayout.BOTTOM_H
	add_child(notification_stack)


func _build_top_right() -> void:
	right_column = HBoxContainer.new()
	right_column.name = "TopRight"
	right_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_column.add_theme_constant_override("separation", 8)
	right_column.anchor_left = 1.0
	right_column.anchor_right = 1.0
	right_column.anchor_top = 0.0
	right_column.anchor_bottom = 0.0
	right_column.offset_right = -PLAQUE_MARGIN.x
	right_column.offset_top = PLAQUE_MARGIN.y
	right_column.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(right_column)
	opponent_panel = PanelContainer.new()
	opponent_panel.name = "OpponentPlaque"
	opponent_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	opponent_panel.visible = false
	opponent_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	opponent_panel.add_theme_stylebox_override("panel", plaque_style(8, 4))
	right_column.add_child(opponent_panel)
	opponent_slot = HBoxContainer.new()
	opponent_slot.name = "OpponentSlot"
	opponent_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	opponent_slot.add_theme_constant_override("separation", 12)
	opponent_panel.add_child(opponent_slot)
	menu_button = Button.new()
	menu_button.name = "BackButton"
	menu_button.text = "Menu"
	menu_button.focus_mode = Control.FOCUS_NONE
	menu_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	menu_button.custom_minimum_size = Vector2(76, 40)
	menu_button.add_theme_font_size_override("font_size", 16)
	right_column.add_child(menu_button)


func _build_bottom() -> void:
	bottom_row = HBoxContainer.new()
	bottom_row.name = "Bottom"
	bottom_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_row.add_theme_constant_override("separation", 10)
	bottom_row.anchor_left = 0.5
	bottom_row.anchor_right = 0.5
	bottom_row.anchor_top = 1.0
	bottom_row.anchor_bottom = 1.0
	bottom_row.offset_bottom = -PLAQUE_MARGIN.x
	bottom_row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom_row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(bottom_row)
	tray = PanelContainer.new()
	tray.name = "Tray"
	tray.mouse_filter = Control.MOUSE_FILTER_STOP
	tray.size_flags_vertical = Control.SIZE_SHRINK_END
	tray.add_theme_stylebox_override("panel", plaque_style(10, 6))
	bottom_row.add_child(tray)
	var row := HBoxContainer.new()
	row.name = "Row"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	tray.add_child(row)
	hint_label = Label.new()
	hint_label.name = "HintLabel"
	hint_label.mouse_filter = Control.MOUSE_FILTER_PASS
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.max_lines_visible = 2
	hint_label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	hint_label.custom_minimum_size = Vector2(300, 0)
	hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hint_label.add_theme_font_size_override("font_size", 15)
	hint_label.add_theme_color_override("font_color", UiPalette.TEXT_SECONDARY)
	row.add_child(hint_label)
	# UX-4 (§3.4): the orders as tokens, placed ones by number and then the realm ones, with the gold they leave. While there are none the
	# hint line says what to do; the tray's tooltip explains the numbers.
	tray_tokens = OrderTray.new()
	tray_tokens.name = "TraySlot"
	tray_tokens.changed.connect(func(count: int): hint_label.visible = count == 0)
	row.add_child(tray_tokens)
	tray.tooltip_text = TooltipText.plain("Your orders",
		"The orders you have given this turn, in the order given: the numbered ones first, each also marked with its number on the board, then the realm orders (research, spellbook, mandate) as icons. Hover one for its forecast, click it to see it and change or cancel it, or press its cross, or right-click it, to cancel. %s" % OrderMarks.RENUMBER_NOTE)
	seal = PanelContainer.new()
	seal.name = "Seal"
	seal.mouse_filter = Control.MOUSE_FILTER_STOP
	seal.visible = false
	seal.size_flags_vertical = Control.SIZE_SHRINK_END
	var style := plaque_style(8, 6)
	style.border_color = UiPalette.GILT
	style.set_border_width_all(3)
	seal.add_theme_stylebox_override("panel", style)
	bottom_row.add_child(seal)
	seal_slot = HBoxContainer.new()
	seal_slot.name = "SealSlot"
	seal_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	seal.add_child(seal_slot)
