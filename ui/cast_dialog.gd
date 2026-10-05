class_name CastDialog
extends Control
## The cast dialog, minimal (M5-6, #117; design/M5_MAGIC_FOG.md §6.1, §11.2): opened from an army of yours that holds a
## caster ("Cast a ritual…" on its panel), it lists the rituals that army can cast, then the provinces each may target,
## how to pay (gold, or blood under Tithe of Blood) and Call the Pack's size, and shows the forecast: what it will do
## with your numbers, the price or the soldiers who bleed, the risk of a ward, and that the army holds this turn. Every
## word comes from MagicRules.forecast_ritual, the same ritual_effect the rituals phase runs, so the forecast is the
## result unless a rival's ward turns it aside. Nothing changes until Confirm, which queues the CastOrder (confirmed);
## it can be cancelled from the orders list until the turn ends. M5-8 builds the full dialog on this (the board ring,
## risk by sight, the budget line).

signal confirmed(ritual: String, army_id: String, target: String, pay: String, size: int)
signal cancelled
signal codex_requested(key: String)

const PANEL_SIZE := Vector2(1180, 760)

var orders: OrdersController = null
var army_id := ""
var options := []  # OrdersController.cast_options(army_id)
var ritual := ""  # the ritual shown
var target := ""
var pay := CastOrder.GOLD
var wolves := 0  # Call the Pack's size
var forecast := {}  # MagicRules.forecast_ritual for the choice shown
var ritual_buttons := {}  # ritual id -> Button
var target_buttons := {}  # province id ("" for none) -> Button
var pay_buttons := {}  # CastOrder.GOLD / BLOOD -> Button
var size_buttons := {}  # wolves -> Button
var options_box: VBoxContainer
var choice_box: VBoxContainer
var intro_label: Label
var forecast_label: Label
var confirm_button: Button
var cancel_button: Button


func _init() -> void:
	name = "CastDialog"
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
	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var title := _label("Cast a ritual", 28, UiPalette.GILT)
	title.name = "Title"
	CodexLink.attach(title, "ritual", func(k): codex_requested.emit(k))
	title.mouse_filter = Control.MOUSE_FILTER_PASS
	title.tooltip_text = TooltipText.plain("Rituals", RulesCodex.text("ritual"))
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
	left.custom_minimum_size = Vector2(380, 0)
	left.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(left)
	options_box = VBoxContainer.new()
	options_box.name = "Options"
	options_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	options_box.add_theme_constant_override("separation", 6)
	left.add_child(options_box)
	var right := ScrollContainer.new()
	right.name = "ChoiceScroll"
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(right)
	choice_box = VBoxContainer.new()
	choice_box.name = "Choice"
	choice_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choice_box.add_theme_constant_override("separation", 8)
	right.add_child(choice_box)
	var foot := HBoxContainer.new()
	foot.name = "Foot"
	foot.add_theme_constant_override("separation", 14)
	box.add_child(foot)
	var note := _label("Nothing changes until you confirm. The order can be cancelled like any other until you end the turn.", 15,
		UiPalette.TEXT_SECONDARY)
	note.name = "Note"
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(note)
	cancel_button = _button("CancelButton", "Cancel", "Close this without casting anything.")
	cancel_button.pressed.connect(close)
	foot.add_child(cancel_button)
	confirm_button = _button("ConfirmButton", "Cast", "")
	confirm_button.add_theme_color_override("font_color", UiPalette.GILT)
	confirm_button.pressed.connect(confirm)
	foot.add_child(confirm_button)


## Fills the dialog for `p_orders`' faction and the army `p_army_id` and shows it, with `select` (by default the first
## ritual it can cast) chosen.
func show_for(p_orders: OrdersController, p_army_id: String, select: String = "") -> void:
	orders = p_orders
	army_id = p_army_id
	for c in options_box.get_children():
		options_box.remove_child(c)
		c.queue_free()
	ritual_buttons.clear()
	options = orders.cast_options(army_id)
	var army := orders.state.find_army(army_id)
	var who := MagicRules.casters(orders.state, army).map(func(c): return MagicRules.caster_name(c))
	intro_label.text = "%s at %s holds %s. A ritual is cast from where the army starts the turn, before anyone moves, so the army holds this turn. Pick a ritual, then its target." % [
		RulerRules._cap(TurnReportText.army_name(orders.state, army_id)), MagicRules._province_name(orders.state, army.location if army else ""),
		MagicRules._and_list(who)]
	var first := ""
	for o in options:
		var b := Button.new()
		b.name = "Ritual_%s" % String(o.ritual).validate_node_name()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		b.add_theme_font_size_override("font_size", 16)
		b.text = "%s · %s\n%s" % [o.name, o.price, String(o.line) if o.ok else String(o.reason)]
		b.disabled = not o.ok
		b.tooltip_text = TooltipText.plain(String(o.name), "%s %s" % [String(MagicRules.spell_data(o.ritual).text), "" if o.ok else String(o.reason)])
		CodexLink.attach(b, MagicRules.spell_codex(o.ritual), func(k): codex_requested.emit(k))
		b.pressed.connect(select_ritual.bind(String(o.ritual)))
		options_box.add_child(b)
		ritual_buttons[o.ritual] = b
		if o.ok and first.is_empty():
			first = o.ritual
	var pick := select if ritual_buttons.has(select) and not ritual_buttons[select].disabled else first
	if pick.is_empty():
		_show_nothing()
	else:
		select_ritual(pick)
	visible = true


## Shows `ritual_id`'s targets, payment and size, choosing the first of each, and its forecast.
func select_ritual(ritual_id: String) -> void:
	var o := _option(ritual_id)
	if o.is_empty():
		return
	ritual = ritual_id
	for rid in ritual_buttons:
		ritual_buttons[rid].set_pressed_no_signal(rid == ritual_id)
	var targets: Array = o.targets
	target = String(targets[0]) if not targets.is_empty() else ""
	pay = CastOrder.GOLD
	wolves = int(o.sizes[0]) if not o.sizes.is_empty() else 0
	_fill_choices(o)
	_refresh()


func select_target(province_id: String) -> void:
	target = province_id
	_refresh()


func set_pay(how: String) -> void:
	pay = how
	_refresh()


func set_wolves(n: int) -> void:
	wolves = n
	_refresh()


## Confirm: asks for the CastOrder (the host queues it) and closes.
func confirm() -> void:
	if ritual.is_empty() or not forecast.get("ok", false):
		return
	visible = false
	confirmed.emit(ritual, army_id, target, pay, wolves)


func close() -> void:
	visible = false
	cancelled.emit()


## The forecast on screen, for tests.
func shown_forecast() -> String:
	return forecast_label.text if forecast_label != null else ""


func _option(ritual_id: String) -> Dictionary:
	for o in options:
		if String(o.ritual) == ritual_id:
			return o
	return {}


func _fill_choices(o: Dictionary) -> void:
	for c in choice_box.get_children():
		choice_box.remove_child(c)
		c.queue_free()
	target_buttons.clear()
	pay_buttons.clear()
	size_buttons.clear()
	var head := _label(String(o.name), 22, UiPalette.GILT)
	head.name = "RitualName"
	choice_box.add_child(head)
	var line := _label(String(MagicRules.spell_data(ritual).text), 15, UiPalette.TEXT_SECONDARY)
	line.name = "RitualText"
	choice_box.add_child(line)
	var targets: Array = o.targets
	if not (targets.size() == 1 and String(targets[0]).is_empty()):
		choice_box.add_child(_label("Target", 17, UiPalette.TEXT_PRIMARY))
		var row := HFlowContainer.new()
		row.name = "Targets"
		choice_box.add_child(row)
		for pid in targets:
			var b := _button("Target_%s" % String(pid).validate_node_name(), MagicRules._province_name(orders.state, String(pid)),
				"Cast %s on %s." % [String(o.name), MagicRules._province_name(orders.state, String(pid))])
			b.toggle_mode = true
			b.pressed.connect(select_target.bind(String(pid)))
			row.add_child(b)
			target_buttons[pid] = b
	if not o.sizes.is_empty() and int(o.sizes[0]) != int(o.sizes[1]):
		choice_box.add_child(_label("Wolves", 17, UiPalette.TEXT_PRIMARY))
		var row := HBoxContainer.new()
		row.name = "Sizes"
		choice_box.add_child(row)
		for n in range(int(o.sizes[0]), int(o.sizes[1]) + 1):
			var b := _button("Size_%d" % n, "%d" % n, "Call %d Thornwolves, %d gold." % [n, n * int(MagicRules.spell_data(ritual).cost)])
			b.toggle_mode = true
			b.pressed.connect(set_wolves.bind(n))
			row.add_child(b)
			size_buttons[n] = b
	if bool(o.blood):
		choice_box.add_child(_label("Pay with", 17, UiPalette.TEXT_PRIMARY))
		var row := HBoxContainer.new()
		row.name = "Pay"
		choice_box.add_child(row)
		for how in [CastOrder.GOLD, CastOrder.BLOOD]:
			var b := _button("Pay_%s" % how, "Gold" if how == CastOrder.GOLD else "Blood (Tithe of Blood)",
				RulesCodex.text("mandate_tithe_of_blood") if how == CastOrder.BLOOD else "Pay the ritual's price in gold.")
			b.toggle_mode = true
			b.pressed.connect(set_pay.bind(how))
			row.add_child(b)
			pay_buttons[how] = b
	choice_box.add_child(HSeparator.new())
	choice_box.add_child(_label("Forecast", 17, UiPalette.TEXT_PRIMARY))
	forecast_label = _label("", 16, UiPalette.TEXT_PRIMARY)
	forecast_label.name = "Forecast"
	forecast_label.mouse_filter = Control.MOUSE_FILTER_PASS
	choice_box.add_child(forecast_label)


func _refresh() -> void:
	for pid in target_buttons:
		target_buttons[pid].set_pressed_no_signal(pid == target)
	for how in pay_buttons:
		pay_buttons[how].set_pressed_no_signal(how == pay)
	for n in size_buttons:
		size_buttons[n].set_pressed_no_signal(n == wolves)
	forecast = orders.cast_preview(ritual, army_id, target, pay, wolves)
	if forecast_label != null:
		forecast_label.text = "\n".join(forecast.get("lines", []))
		forecast_label.tooltip_text = TooltipText.plain(MagicRules.spell_name(ritual), "%s %s" % [String(forecast.get("text", "")),
			RulesCodex.text(MagicRules.spell_codex(ritual))])
	confirm_button.disabled = not forecast.get("ok", false)
	confirm_button.tooltip_text = TooltipText.plain("Cast", String(forecast.get("text", "")) if forecast.get("ok", false) \
		else String(forecast.get("reason", "")))


func _show_nothing() -> void:
	ritual = ""
	forecast = {}
	for c in choice_box.get_children():
		choice_box.remove_child(c)
		c.queue_free()
	forecast_label = null
	var none := _label("This army can't cast a ritual now: each one says why on the left.", 16, UiPalette.TEXT_SECONDARY)
	none.name = "Nothing"
	choice_box.add_child(none)
	confirm_button.disabled = true


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


func _button(node_name: String, text: String, tip: String) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 16)
	if not tip.is_empty():
		b.tooltip_text = TooltipText.plain(text, tip)
	return b
