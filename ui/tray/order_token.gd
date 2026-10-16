class_name OrderToken
extends PanelContainer
## UX-4 (design/UX_WAR_TABLE.md §3.4, issue #213): one queued order as a small token, in the tray along the bottom or on the board where the
## order happens. A placed order wears its number in a gilt chip, then its icon (UiIcons) and, when there is room, its short words; a
## realm order (research, spellbook, mandate) has no number, just the icon and its words. The tooltip is the order's own sentence and
## breakdown (OrderMarks.tip) and ends with why the numbers move.
##
## A left click asks to focus the order's place and open its card (`pressed`); a right-click, or the tray token's cross, asks to cancel
## it (`cancel_requested`). The token only asks: the map screen does it, through its own order API, so the rules' checks are the
## same as for any other order. A right-click is the cancel here, so a token is not a codex link; the card a click opens has the
## order's line with its codex link.

signal pressed(index: int)
signal cancel_requested(index: int)

enum Look { TRAY, BOARD }

## The chip's and the icon's sizes, the tray token's height, and the room the words get when the Table is wide.
const CHIP_H := 22.0
const ICON_PX := 18
const TRAY_H := 34.0
const LABEL_W := 84.0  # UI-FIT (#237): the words at the floor's 15 px, "Westwatch" whole (72 held it at 13 px)
## UI-CLUTTER (#238): the words take what they need from LABEL_W up to this ("Knight Captain" whole); longer ones trim, their whole text in
## the tooltip. A fixed LABEL_W trimmed them with the tray half empty.
const LABEL_MAX := 150.0
const CROSS_PX := 18.0

var index := -1
## The mark's indices when it stands for several orders (a board recruit token): a click asks about the first.
var indices: Array = []
var mark: Dictionary = {}
var look := Look.TRAY
var chip: Label = null
var icon: TextureRect = null
var label: Label = null
var cross: Button = null

var _controller: OrdersController = null
var _compact := false
var _tight := false
var _row: HBoxContainer


## A token for `mark` (OrderMarks.marks, or a board mark from OrderMarks.board_marks) of `c`'s orders.
static func make(m: Dictionary, c: OrdersController, p_look: Look, compact: bool = false) -> OrderToken:
	var t := OrderToken.new()
	t.mark = m
	t.look = p_look
	t.index = int(m.get("index", -1))
	t.indices = (m.get("indices", [t.index]) as Array).duplicate()
	t._build(c)
	t.set_compact(compact)
	return t


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_NONE
	gui_input.connect(_on_gui_input)  # (the signal, so a test can drive a token without a window)


func _build(c: OrdersController) -> void:
	var numbers: Array = mark.get("numbers", [int(mark.get("number", 0))])
	var realm := bool(mark.get("realm", false))
	name = "OrderToken_%d" % int(numbers[0]) if not realm else "RealmToken_%s" % String(mark["class"])
	add_theme_stylebox_override("panel", _style(false))
	_row = HBoxContainer.new()
	_row.name = "Row"
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_theme_constant_override("separation", 4)
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(_row)
	if not realm:
		chip = Label.new()
		chip.name = "Number"
		chip.text = OrderMarks.numbers_text(numbers)
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		chip.custom_minimum_size = Vector2(CHIP_H, CHIP_H)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		chip.add_theme_font_override("font", UiFonts.number())
		chip.add_theme_font_size_override("font_size", 15)
		chip.add_theme_color_override("font_color", UiPalette.KEYLINE_INK)
		var disc := StyleBoxFlat.new()
		disc.bg_color = UiPalette.GILT
		disc.set_corner_radius_all(int(CHIP_H / 2.0))
		disc.content_margin_left = 5
		disc.content_margin_right = 5
		disc.content_margin_top = 0
		disc.content_margin_bottom = 0
		chip.add_theme_stylebox_override("normal", disc)
		_row.add_child(chip)
	icon = TextureRect.new()
	icon.name = "Icon"
	icon.texture = UiIcons.icon(String(mark.get("icon", "orders")), ICON_PX)
	icon.self_modulate = UiPalette.GILT if realm else UiPalette.TEXT_PRIMARY
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	icon.custom_minimum_size = Vector2(ICON_PX, ICON_PX)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.visible = not (look == Look.BOARD and String(mark["class"]) == "march")  # a march's mark on the board is its number alone
	_row.add_child(icon)
	label = Label.new()
	label.name = "Words"
	label.text = String(mark.get("label", "")) if look == Look.TRAY else String(mark.get("board", ""))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.add_theme_font_size_override("font_size", UiPalette.TYPE_FLOOR)  # UI-FIT (#237): the floor
	label.add_theme_color_override("font_color", UiPalette.TEXT_PRIMARY)
	if look == Look.TRAY:
		var natural := label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiPalette.TYPE_FLOOR).x + 2.0
		label.custom_minimum_size.x = clampf(ceilf(natural), LABEL_W, LABEL_MAX)
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	else:
		label.add_theme_color_override("font_outline_color", UiPalette.KEYLINE_INK)
		label.add_theme_constant_override("outline_size", 3)
	label.visible = not label.text.is_empty()
	_row.add_child(label)
	if look == Look.TRAY:
		cross = Button.new()
		cross.name = "CancelButton"
		cross.text = "×"
		cross.flat = true
		cross.focus_mode = Control.FOCUS_NONE
		cross.custom_minimum_size = Vector2(CROSS_PX, CROSS_PX)
		cross.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cross.add_theme_font_size_override("font_size", 16)
		cross.add_theme_color_override("font_color", UiPalette.TEXT_SECONDARY)
		cross.add_theme_color_override("font_hover_color", UiPalette.NEGATIVE)
		cross.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		cross.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
		cross.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
		cross.tooltip_text = TooltipText.plain("Cancel this order",
			"Takes the order back. Nothing happens until the turn ends, so you can change your mind. The orders after it move up one number.")
		cross.pressed.connect(func(): cancel_requested.emit(index))
		_row.add_child(cross)
	_controller = c
	tooltip_text = " "  # the real text is built when it is asked for (_get_tooltip): nine tokens are rebuilt with every order, and a forecast costs
	mouse_entered.connect(func(): add_theme_stylebox_override("panel", _style(true)))
	mouse_exited.connect(func(): add_theme_stylebox_override("panel", _style(false)))


## The tooltip: one order's, or every recruit a board token folds together. It has no codex line: a right-click here is the cancel,
## and the order's card (a click) links its codex entry. Built when the hover asks, from the orders as they are then.
func _get_tooltip(_at_position: Vector2) -> String:
	if _controller == null:
		return ""
	return OrderMarks.tip(_controller, index) if indices.size() <= 1 else OrderMarks.group_tip(_controller, mark)


## The words go when the Table is compact (below 1600 logical width): the number or the icon alone, the text in the tooltip.
func set_compact(on: bool) -> void:
	_compact = on
	if label != null:
		label.visible = not _tight and not label.text.is_empty() and (look == Look.BOARD or not on)
	update_minimum_size()


func is_compact() -> bool:
	return _compact


## A board token with no room for its icon and words: just its number, so the number is still readable (the tooltip has the rest).
func set_tight(on: bool) -> void:
	_tight = on
	if icon != null:
		icon.visible = not on and not (look == Look.BOARD and String(mark["class"]) == "march")
	if label != null:
		label.visible = not on and not label.text.is_empty() and (look == Look.BOARD or not _compact)
	update_minimum_size()


func is_tight() -> bool:
	return _tight


func _on_gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	if mb.button_index == MOUSE_BUTTON_LEFT:
		accept_event()  # first: the order's change rebuilds the tokens, and this one goes with them
		pressed.emit(index)
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		accept_event()
		cancel_requested.emit(index)


func _style(hover: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.set_corner_radius_all(8 if look == Look.TRAY else 7)
	if look == Look.TRAY:
		s.bg_color = Color(UiPalette.PANEL_RAISED, 0.96)
		s.border_color = UiPalette.GILT if hover else UiPalette.PANEL_BORDER
		s.set_border_width_all(1)
		s.content_margin_left = 5
		s.content_margin_right = 3
		s.content_margin_top = 4
		s.content_margin_bottom = 4
	else:
		s.bg_color = Color(UiPalette.KEYLINE_INK, 0.9)
		s.border_color = Color("#FFF3C4") if hover else UiPalette.GILT
		s.set_border_width_all(2)
		s.content_margin_left = 3
		s.content_margin_right = 6
		s.content_margin_top = 2
		s.content_margin_bottom = 2
	return s
