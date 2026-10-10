class_name DetailsCard
extends PanelContainer
## UX-1 (design/UX_WAR_TABLE.md §1.1, issue #194): the temporary details card. The map screen's side panel is gone, and
## until UX-3 builds the army and province cards this card holds what the panel held, docked bottom left in the board's
## safe area: the province's facts, the armies there, your orders with their cancel buttons, and recruiting. The content
## is today's: MapScreen's own builders fill `details`, so every breakdown tooltip and codex link is as it was. UX-3's
## cards replace it by registering with the SelectionHost instead (SelectionHost.set_presenter).
##
## It is shown when something is selected, and closable: the close button, Esc and a right-click on empty board (UiCancel's
## "card" step) hide it and put your army back to unselected, so a click on a neighbour never gives an order you can't see.
## The province stays selected: the board's close-up depends on it. The tray's Orders button shows the card again with
## the orders list when nothing is selected, so no order is ever out of reach.
##
## It is the SelectionHost's presenter: show_province / show_army open it, refresh_selection rebuilds it (an order was queued
## or cancelled, a new turn), clear_selection hides it.

signal closed
## The height it needs changed: the TableHud places it again.
signal layout_wanted

var details: VBoxContainer  # MapScreen's builders fill this
var scroll: ScrollContainer
var close_button: Button
var title_label: Label
## Set by MapScreen: rebuilds `details` from the map's own selection and orders.
var fill := Callable()
## Hidden by the player (the close button or UiCancel) until something else is selected.
var dismissed := false
## Opened by the tray's Orders button with nothing selected.
var forced := false

var _header: HBoxContainer
var _max_height := 480.0
var _want_queued := false


func _init() -> void:
	name = "DetailsCard"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(TableLayout.CARD_W, 0)
	var style := UiPalette.panel_style()
	style.bg_color = Color(UiPalette.PANEL_BG, 0.97)
	style.content_margin_left = 14
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 10
	add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.name = "Box"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	add_child(box)
	_header = HBoxContainer.new()
	_header.name = "Header"
	_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_header)
	title_label = Label.new()
	title_label.name = "CardTitle"
	title_label.text = "Selection"
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.add_theme_font_size_override("font_size", 14)
	title_label.add_theme_color_override("font_color", UiPalette.TEXT_SECONDARY)
	_header.add_child(title_label)
	close_button = Button.new()
	close_button.name = "CloseCardButton"
	close_button.text = "✕"
	close_button.flat = true
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.tooltip_text = "Close this card (Esc). Click the land or an army again to bring it back, or press Orders to see your orders."
	close_button.pressed.connect(dismiss)
	_header.add_child(close_button)
	scroll = ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	details = VBoxContainer.new()
	details.name = "Details"
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 8)
	scroll.add_child(details)
	details.minimum_size_changed.connect(_want_layout)


# --- the SelectionHost's presenter ----------------------------------------------------------------

func show_province(_province_id: String) -> void:
	_open()


func show_army(_army_id: String, _province_id: String) -> void:
	_open()


func clear_selection() -> void:
	if not forced:
		visible = false
	_fill()


## Something it shows changed: rebuild; hidden or shown stays as it is (a card the player closed stays closed).
func refresh_selection() -> void:
	_fill()


## The tray's Orders button: the card with the orders, whatever is selected (nothing selected: "No province selected").
func open_orders() -> void:
	dismissed = false
	forced = true
	visible = true
	_fill()
	_want_layout()


## The close button, Esc, a right-click on empty board: hides the card until something is selected again.
func dismiss() -> void:
	if not visible and not forced:
		return
	dismissed = true
	forced = false
	visible = false
	closed.emit()


func is_showing() -> bool:
	return visible


# --- size -----------------------------------------------------------------------------------------

## Called by the TableHud before it places the card: the card may be at most `max_height` tall; its scroll gets the
## height its content needs up to that.
func fit(max_height: float) -> void:
	_max_height = max_height
	var header_h := _header.get_combined_minimum_size().y + 4.0
	var style := get_theme_stylebox("panel")
	var padding := style.get_margin(SIDE_TOP) + style.get_margin(SIDE_BOTTOM)
	var room := maxf(max_height - header_h - padding, 80.0)
	var want := clampf(details.get_combined_minimum_size().y, 60.0, room)
	if not is_equal_approx(scroll.custom_minimum_size.y, want):
		scroll.custom_minimum_size.y = want


## The height the card asks for now (its content, its header and its padding), before the cap.
func desired_height() -> float:
	var header_h := _header.get_combined_minimum_size().y + 4.0
	var style := get_theme_stylebox("panel")
	return details.get_combined_minimum_size().y + header_h + style.get_margin(SIDE_TOP) + style.get_margin(SIDE_BOTTOM)


# --- internals ------------------------------------------------------------------------------------

func _open() -> void:
	dismissed = false
	visible = true
	_fill()
	_want_layout()


func _fill() -> void:
	if fill.is_valid():
		fill.call()
	_want_layout()


func _want_layout() -> void:
	if _want_queued:
		return
	_want_queued = true
	_emit_layout.call_deferred()


func _emit_layout() -> void:
	_want_queued = false
	layout_wanted.emit()
