class_name SacrificeDialog
extends Control
## The sacrifice dialog (M2-6, #34; design/M2_RULER.md §2.4): pick a mandate from your faction's list and
## see a before → after preview of your own numbers (kept power, the ruler's hit points, attack, defense,
## ability rank and effect, every unit stat and recruit price it changes, income this turn, your queued
## attacks fought again, and any queued order it would remove). Nothing changes until Confirm, which
## queues the Sacrifice order (confirmed); it can be cancelled from its tray token until the turn ends.
## Every number comes from Forecast.sacrifice, which reads the same copy the sacrifice phase resolves
## with, so the preview is what happens. Opened from the ruler panel (MapScreen.open_sacrifice_dialog).

signal confirmed(mandate_id: String)
signal cancelled
signal codex_requested(key: String)

const PANEL_SIZE := Vector2(1240, 800)
const WARNING := Color("#F0913A")  # design/STYLE_BIBLE.md 1.3: warning, always with ⚠

var orders: OrdersController = null
var selected := ""  # the mandate whose preview is shown ("" when none can be picked)
var preview := {}  # Forecast.sacrifice for `selected`
var option_buttons := {}  # mandate id -> Button
var options_box: VBoxContainer
var preview_box: VBoxContainer
var rows_grid: GridContainer  # label | now | → | after the sacrifice
var intro_label: Label
var note_label: Label
var confirm_button: Button
var cancel_button: Button
var _previews := {}  # mandate id -> Forecast.sacrifice (the dialog's state never changes while open)


func _init() -> void:
	name = "SacrificeDialog"
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0, 0, 0, 0.5)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.name = "Center"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.custom_minimum_size = PANEL_SIZE
	var style := UiPalette.panel_style(22)
	style.border_color = UiPalette.GILT
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	PanelFit.attach(panel, center)  # MVP-3 (#177): a panel bigger than a 1280x720 viewport (125%) shrinks to fit it
	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var title := _label("Sacrifice power for a mandate", 28, UiPalette.GILT)
	title.name = "Title"
	box.add_child(title)
	intro_label = _label("", 16, UiPalette.TEXT_SECONDARY)
	intro_label.name = "Intro"
	box.add_child(intro_label)
	var body := HBoxContainer.new()
	body.name = "Body"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 22)
	box.add_child(body)
	var left := ScrollContainer.new()
	left.name = "OptionsScroll"
	left.custom_minimum_size = Vector2(400, 0)
	left.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(left)
	options_box = VBoxContainer.new()
	options_box.name = "Options"
	options_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	options_box.add_theme_constant_override("separation", 6)
	left.add_child(options_box)
	var right := ScrollContainer.new()
	right.name = "PreviewScroll"
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(right)
	preview_box = VBoxContainer.new()
	preview_box.name = "Preview"
	preview_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_box.add_theme_constant_override("separation", 8)
	right.add_child(preview_box)
	var foot := HBoxContainer.new()
	foot.name = "Foot"
	foot.add_theme_constant_override("separation", 14)
	box.add_child(foot)
	note_label = _label("Nothing changes until you confirm. The order can be cancelled like any other until you end the turn.", 15,
		UiPalette.TEXT_SECONDARY)
	note_label.name = "Note"
	note_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(note_label)
	cancel_button = _button("CancelButton", "Cancel", "Close this without sacrificing anything.")
	cancel_button.pressed.connect(close)
	foot.add_child(cancel_button)
	confirm_button = _button("ConfirmButton", "Confirm sacrifice", "")
	confirm_button.add_theme_color_override("font_color", UiPalette.GILT)
	confirm_button.pressed.connect(confirm)
	foot.add_child(confirm_button)


## Fills the dialog for `p_orders`' faction and shows it, previewing `select` (by default the first
## mandate the ruler can sacrifice for).
func show_for(p_orders: OrdersController, select: String = "") -> void:
	orders = p_orders
	_previews.clear()
	selected = ""
	preview = {}
	for c in options_box.get_children():
		options_box.remove_child(c)
		c.queue_free()
	option_buttons.clear()
	var state := orders.state
	var fid := orders.faction_id
	intro_label.text = "%s keeps %d power. A mandate bought now costs its price +%d, at most one per turn, and it counts from this turn on, because a sacrifice resolves first. Pick one to see what it changes." % [
		RulerRules._cap(RulerRules.current_name(state, fid)), RulerRules.kept_power(state, fid), MandateData.SACRIFICE_PREMIUM]
	var first := ""
	for o in orders.sacrifice_options():
		var b := Button.new()
		b.name = "Option_%s" % String(o.mandate).validate_node_name()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		b.add_theme_font_size_override("font_size", 16)
		b.text = "%s · %d power (%d +%d)\n%s" % [o.name, o.cost, o.price, MandateData.SACRIFICE_PREMIUM, _option_status(o)]
		b.disabled = not o.ok
		b.tooltip_text = TooltipText.plain("%s by sacrifice" % o.name, "%s %s" % [o.effect,
			o.reason if not o.ok else "Click to see what it changes for you."])
		CodexLink.attach(b, String(RulerRules.mandate_data(o.mandate).get("codex", "mandates")), codex_requested.emit)
		b.pressed.connect(select_mandate.bind(String(o.mandate)))
		options_box.add_child(b)
		option_buttons[o.mandate] = b
		if o.ok and first.is_empty():
			first = o.mandate
	var pick := select if option_buttons.has(select) and not option_buttons[select].disabled else first
	if pick.is_empty():
		_show_nothing()
	else:
		select_mandate(pick)
	visible = true


## Shows the before → after preview for `mandate_id` and arms Confirm when it is legal.
func select_mandate(mandate_id: String) -> void:
	if orders == null:
		return
	selected = mandate_id
	if not _previews.has(mandate_id):
		_previews[mandate_id] = orders.sacrifice_preview(mandate_id)
	preview = _previews[mandate_id]
	for mid in option_buttons:
		option_buttons[mid].set_pressed_no_signal(mid == mandate_id)
	confirm_button.disabled = not preview.get("ok", false)
	confirm_button.tooltip_text = TooltipText.plain("Confirm sacrifice", "Queue the Sacrifice order for %s. %s" % [
		preview.get("name", ""), preview.get("text", "")]) if preview.get("ok", false) \
		else TooltipText.plain("Confirm sacrifice", String(preview.get("reason", "")))
	_fill_preview()


## Confirm: asks for the Sacrifice order (the host queues it) and closes.
func confirm() -> void:
	if selected.is_empty() or not preview.get("ok", false):
		return
	visible = false
	confirmed.emit(selected)


func close() -> void:
	visible = false
	cancelled.emit()


## The preview rows on screen, for tests: [{"label", "before", "after"}] as shown.
func shown_rows() -> Array:
	var out := []
	if rows_grid == null:
		return out
	var cells := rows_grid.get_children()
	for i in range(4, cells.size(), 4):
		var after := (cells[i + 3] as Label).text.trim_suffix(" ▲").trim_suffix(" ▼")
		out.append({"label": (cells[i] as Label).text, "before": (cells[i + 1] as Label).text, "after": after})
	return out


func _option_status(o: Dictionary) -> String:
	if o.ok:
		return String(o.effect)
	match String(o.code):
		"owned_mandate":
			return "Yours already."
		"queued":
			return "Queued this turn."
		"not_enough_power":
			return "Needs %d power; %s keeps %d." % [int(o.cost), RulerRules.current_name(orders.state, orders.faction_id),
				RulerRules.kept_power(orders.state, orders.faction_id)]
	return String(o.reason)


func _show_nothing() -> void:
	_clear_preview()
	confirm_button.disabled = true
	confirm_button.tooltip_text = TooltipText.plain("Confirm sacrifice", "There is no mandate to sacrifice for right now.")
	var why := "No mandate can be bought by sacrifice right now."
	var check := RulerRules.sacrifice_check(orders.state, orders.faction_id, "")
	if String(check.get("code", "")) in ["no_ruler", "no_living_ruler", "second_sacrifice"]:
		why = String(check.reason)
	var l := _label(why, 18, UiPalette.TEXT_PRIMARY)
	l.name = "NothingLabel"
	preview_box.add_child(l)


func _clear_preview() -> void:
	rows_grid = null
	for c in preview_box.get_children():
		preview_box.remove_child(c)
		c.queue_free()


func _fill_preview() -> void:
	_clear_preview()
	var mid := selected
	var cost := Breakdown.sacrifice_cost(mid)
	var head := _label("%s by sacrifice: %d power" % [preview.get("name", ""), int(preview.get("cost", 0))], 22, UiPalette.GILT)
	head.name = "PreviewHeading"
	head.tooltip_text = TooltipText.from_breakdown(cost)
	head.mouse_filter = Control.MOUSE_FILTER_PASS
	CodexLink.attach(head, String(RulerRules.mandate_data(mid).get("codex", "sacrifice")), codex_requested.emit)
	preview_box.add_child(head)
	var effect := _label(String(preview.get("effect", "")), 17, UiPalette.TEXT_PRIMARY)
	effect.name = "EffectLabel"
	preview_box.add_child(effect)
	if not preview.get("ok", false):
		var no := _label(String(preview.get("reason", "")), 17, UiPalette.NEGATIVE)
		no.name = "ReasonLabel"
		preview_box.add_child(no)
		return
	rows_grid = GridContainer.new()
	rows_grid.name = "Rows"
	rows_grid.columns = 4
	rows_grid.add_theme_constant_override("h_separation", 16)
	rows_grid.add_theme_constant_override("v_separation", 6)
	preview_box.add_child(rows_grid)
	for text in ["", "Now", "", "After the sacrifice"]:
		var h := _label(text, 15, UiPalette.TEXT_SECONDARY)
		h.autowrap_mode = TextServer.AUTOWRAP_OFF
		rows_grid.add_child(h)
	for row in preview.rows:
		var name_label := _label(String(row.label), 17, UiPalette.TEXT_PRIMARY)
		name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		name_label.mouse_filter = Control.MOUSE_FILTER_PASS
		name_label.tooltip_text = TooltipText.from_breakdown(row.breakdown)
		CodexLink.attach(name_label, String(row.codex), codex_requested.emit)
		rows_grid.add_child(name_label)
		var was := _label(String(row.before), 17, UiPalette.TEXT_SECONDARY)
		was.autowrap_mode = TextServer.AUTOWRAP_OFF
		rows_grid.add_child(was)
		var arrow := _label("→", 17, UiPalette.TEXT_SECONDARY)
		arrow.autowrap_mode = TextServer.AUTOWRAP_OFF
		rows_grid.add_child(arrow)
		var now := _label(String(row.after), 17, _trend_color(row))
		now.autowrap_mode = TextServer.AUTOWRAP_OFF
		now.text = "%s %s" % [String(row.after), _trend_mark(row)] if not _trend_mark(row).is_empty() else String(row.after)
		rows_grid.add_child(now)
	if not preview.effects.is_empty():
		var eh := _label("What else changes", 18, UiPalette.GILT)
		preview_box.add_child(eh)
		for line in preview.effects:
			var l := _label("•  %s" % line, 16, UiPalette.TEXT_PRIMARY)
			l.name = "EffectLine"
			preview_box.add_child(l)
	var oh := _label("Your queued attacks, fought again with the change", 18, UiPalette.GILT)
	oh.name = "OddsHeading"
	oh.tooltip_text = TooltipText.plain("Battle odds", RulesCodex.text("battle_odds"))
	oh.mouse_filter = Control.MOUSE_FILTER_PASS
	CodexLink.attach(oh, "battle_odds", codex_requested.emit)
	preview_box.add_child(oh)
	if preview.odds.is_empty():
		var none := _label("No attacks queued this turn: no move of yours goes into a province with an enemy army in it now.", 16,
			UiPalette.TEXT_SECONDARY)
		none.name = "NoOddsLabel"
		preview_box.add_child(none)
	for o in preview.odds:
		var l := _label("%s: %s → %s" % [o.name, o.before, o.after], 16, UiPalette.TEXT_PRIMARY)
		l.name = "OddsLine"
		preview_box.add_child(l)
	for line in preview.dropped:
		var w := _label("⚠ %s" % line, 16, WARNING)
		w.name = "DroppedLine"
		preview_box.add_child(w)


## ▲ when the number goes up, ▼ when it goes down (colour is never the only cue, bible 1.1).
func _trend_mark(row: Dictionary) -> String:
	var d := int(row.get("after_value", 0)) - int(row.get("before_value", 0))
	return "▲" if d > 0 else ("▼" if d < 0 else "")


## Positive when the change is good for you (a lower price, more attack), negative when it costs you.
func _trend_color(row: Dictionary) -> Color:
	var d := int(row.get("after_value", 0)) - int(row.get("before_value", 0))
	if d == 0:
		return UiPalette.TEXT_PRIMARY
	return UiPalette.POSITIVE if (d > 0) == bool(row.get("higher_is_better", true)) else UiPalette.NEGATIVE


func _label(text: String, font_size: int, color: Color) -> Label:
	font_size = maxi(font_size, UiPalette.TYPE_FLOOR)  # UI-FIT (#237): nothing the player reads below the floor
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


func _button(node_name: String, text: String, tooltip: String) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.tooltip_text = tooltip
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(170, 44)
	b.add_theme_font_size_override("font_size", 19)
	return b
