class_name LoadScreen
extends Control
## The Load game screen (title screen and the game menu): every saved game, newest first, with what its
## header says (name, when, turn, who plays whom, rulers, seed and a summary line), a Load button and a
## Delete button that asks first. A save that can't be read is listed with the reason in plain words and
## can only be deleted. Load reads the file and emits load_requested(save); the host turns it into a
## game (GameScreen.load_game) and calls show_error() when that fails, so a damaged save never crashes.
## Builds its children in code, so it works before it is in the tree (headless tests).
##
## API:
##   open(store = null)       lists the saves of `store` (default SaveStore.new()) and shows the screen
##   entries                  SaveStore.list() as shown, newest first; rows: one Control per entry
##   load_entry(index) -> bool       the row's Load button: emits load_requested(save) when the file reads
##   ask_delete(index), confirm_delete(), cancel_delete()   the row's Delete button and its question
##   show_error(text)         shows why a save could not be loaded
##   back()                   the Back button (Esc): hides the screen and emits back_requested

signal load_requested(save: Dictionary)
signal back_requested

const BACKGROUND := Color("#14131F")

var store: SaveStore = null
var entries: Array = []
var rows: Array = []
var list_box: VBoxContainer
var empty_label: Label
var error_label: Label
var back_button: Button
var confirm_overlay: Control
var confirm_label: Label
var confirm_button: Button
var _pending_delete := -1


func _init() -> void:
	name = "LoadScreen"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		if is_inside_tree():
			get_viewport().set_input_as_handled()
		if confirm_overlay.visible:
			cancel_delete()
		else:
			back()


func open(save_store: SaveStore = null) -> void:
	store = save_store if save_store != null else SaveStore.new()
	error_label.visible = false
	cancel_delete()
	refresh()
	visible = true
	if is_inside_tree():
		back_button.grab_focus.call_deferred()


func refresh() -> void:
	for r in rows:
		list_box.remove_child(r)
		r.queue_free()
	rows = []
	entries = store.list() if store else []
	for i in entries.size():
		var row := _row(i, entries[i])
		list_box.add_child(row)
		rows.append(row)
	empty_label.visible = entries.is_empty()


func load_entry(index: int) -> bool:
	if index < 0 or index >= entries.size():
		return false
	var got := store.read(entries[index].path)
	if not got.errors.is_empty():
		show_error(SaveGame.error_text(got.errors))
		return false
	error_label.visible = false
	load_requested.emit(got.save)
	return true


func ask_delete(index: int) -> void:
	if index < 0 or index >= entries.size():
		return
	_pending_delete = index
	confirm_label.text = "Delete \"%s\"? This can't be undone." % _title(entries[index])
	confirm_overlay.visible = true
	if is_inside_tree():
		confirm_button.grab_focus.call_deferred()


func confirm_delete() -> String:
	var why := "There is no save to delete."
	if _pending_delete >= 0 and _pending_delete < entries.size():
		why = store.delete(entries[_pending_delete].path)
	cancel_delete()
	refresh()
	if not why.is_empty():
		show_error(why)
	return why


func cancel_delete() -> void:
	_pending_delete = -1
	confirm_overlay.visible = false


func show_error(text: String) -> void:
	error_label.text = text
	error_label.visible = not text.is_empty()


func back() -> void:
	cancel_delete()
	visible = false
	back_requested.emit()


## "Autosave" or the player's name for it; "A damaged save" when the file can't be read.
static func _title(entry: Dictionary) -> String:
	if not entry.errors.is_empty():
		return "A damaged save"
	return String(entry.header.get("name", "A saved game"))


## The second line of a row: "Turn 5 · Aurel Crown (you) vs Thornmane Clans (Computer, Normal) · Rulers".
static func details_text(header: Dictionary) -> String:
	var parts := ["Turn %d" % Serial.to_int(header.get("turn", 0))]
	var seats := SaveGame.seats_text(header)
	if not seats.is_empty():
		parts.append(seats)
	parts.append("Rulers" if header.get("rulers", false) == true else "No rulers")
	return "  ·  ".join(parts)


# --- nodes ----------------------------------------------------------------------------------------

func _row(index: int, entry: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.name = "Save%d" % (index + 1)
	var style := StyleBoxFlat.new()
	style.bg_color = UiPalette.PANEL_RAISED
	style.border_color = UiPalette.PANEL_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	panel.add_child(row)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 2)
	row.add_child(text)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	text.add_child(head)
	var damaged: bool = not entry.errors.is_empty()
	head.add_child(_label("NameLabel", _title(entry), 22, UiPalette.NEGATIVE if damaged else UiPalette.GILT))
	var header: Dictionary = entry.header
	if not damaged:
		var when := _label("WhenLabel", SaveGame.when_text(Serial.to_int(header.get("saved_at", 0))), 16, UiPalette.TEXT_SECONDARY)
		when.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(when)
		var details := _label("DetailsLabel", details_text(header), 17, UiPalette.TEXT_PRIMARY)
		details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.add_child(details)
		var summary := _label("SummaryLabel", String(header.get("summary", "")), 16, UiPalette.TEXT_SECONDARY)
		summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		summary.tooltip_text = "Game seed %s. %s" % [String(header.get("seed", "")), SaveGame.ORDERS_NOTE]
		summary.mouse_filter = Control.MOUSE_FILTER_PASS
		text.add_child(summary)
	else:
		var why := _label("ErrorText", SaveGame.error_text(entry.errors), 16, UiPalette.TEXT_SECONDARY)
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.add_child(why)
	var load_button := _button("LoadButton", "Load", "Load this game at the start of turn %d. %s" % [
		Serial.to_int(header.get("turn", 0)), SaveGame.ORDERS_NOTE])
	load_button.visible = not damaged
	load_button.pressed.connect(load_entry.bind(index))
	row.add_child(load_button)
	var delete_button := _button("DeleteButton", "Delete", "Delete this save. You are asked to confirm first.")
	delete_button.pressed.connect(ask_delete.bind(index))
	row.add_child(delete_button)
	return panel


func _build() -> void:
	var background := ColorRect.new()
	background.name = "Background"
	background.color = BACKGROUND
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.add_theme_stylebox_override("panel", UiPalette.panel_style(32))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.name = "Box"
	box.custom_minimum_size = Vector2(1000, 0)
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	box.add_child(_label("TitleLabel", "Load game", 44, UiPalette.GILT))
	var note := _label("NoteLabel", "The game saves itself at the start of every turn and keeps the last three autosaves. %s" % SaveGame.ORDERS_NOTE, 17, UiPalette.TEXT_SECONDARY)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.custom_minimum_size = Vector2(1000, 520)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	list_box = VBoxContainer.new()
	list_box.name = "List"
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", 10)
	scroll.add_child(list_box)
	empty_label = _label("EmptyLabel", "No saved games yet. Start a game: it saves itself at the start of every turn.", 20, UiPalette.TEXT_SECONDARY)
	empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list_box.add_child(empty_label)
	error_label = _label("ErrorLabel", "", 19, UiPalette.NEGATIVE)
	error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	error_label.visible = false
	box.add_child(error_label)
	var buttons := HBoxContainer.new()
	buttons.name = "Buttons"
	buttons.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(buttons)
	back_button = _button("BackButton", "Back", "Go back without loading (Esc).")
	back_button.custom_minimum_size = Vector2(160, 52)
	back_button.pressed.connect(back)
	buttons.add_child(back_button)
	_build_confirm()


func _build_confirm() -> void:
	confirm_overlay = Control.new()
	confirm_overlay.name = "DeleteConfirm"
	confirm_overlay.visible = false
	confirm_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(confirm_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	confirm_overlay.add_child(dim)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	confirm_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	panel.add_theme_stylebox_override("panel", UiPalette.panel_style(28))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	panel.add_child(box)
	confirm_label = _label("ConfirmLabel", "", 22, UiPalette.TEXT_PRIMARY)
	confirm_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(confirm_label)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)
	var keep := _button("KeepButton", "Keep it", "Don't delete this save.")
	keep.pressed.connect(cancel_delete)
	row.add_child(keep)
	confirm_button = _button("ConfirmDeleteButton", "Delete", "Delete this save for good.")
	confirm_button.add_theme_color_override("font_color", UiPalette.NEGATIVE)
	confirm_button.pressed.connect(func(): confirm_delete())
	row.add_child(confirm_button)


func _button(node_name: String, text: String, tooltip: String) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.tooltip_text = tooltip
	b.custom_minimum_size = Vector2(120, 44)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", 20)
	return b


func _label(node_name: String, text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.name = node_name
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l
