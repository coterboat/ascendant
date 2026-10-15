class_name CastDialog
extends Control
## The cast dialog (M5-6, #117; M5-8, #119; design/M5_MAGIC_FOG.md §6.1, §11.2): opened from an army of yours that holds a
## caster ("Cast a ritual…" on its panel), it lists the rituals that army can cast, then the provinces each may target,
## how to pay (gold, or blood under Tithe of Blood) and Call the Pack's size, and shows the forecast: what it will do
## with your numbers, the price or the soldiers who bleed, the risk of a ward from what you can see, that the army holds
## this turn (and the move that cancels), and the gold left after your queued rituals and recruits. Every word of the
## forecast comes from MagicRules.forecast_ritual, the same ritual_effect the rituals phase runs, so the forecast is the
## result unless a rival's ward turns it aside. Nothing changes until Confirm, which queues the CastOrder (confirmed);
## it can be cancelled from its tray token until the turn ends.
##
## M5-8: the dialog docks at the right edge and leaves the board in view and clickable: the target is a ring on the board
## with every province in the ritual's range lit (rings_changed, which the map draws), and a click on a lit province picks
## it (accepts_province, which the map asks). The forecast's sentences are shown under headings (MagicRules.forecast_sections)
## and the budget line has its breakdown (Forecast.cast_budget). It offers only the legal targets (OrdersController.cast_options
## asks MagicRules.ritual_targets), so a target out of range is never a choice.

signal confirmed(ritual: String, army_id: String, target: String, pay: String, size: int)
signal cancelled
signal codex_requested(key: String)
## The provinces in range of the ritual shown, and the one chosen ("" for none): the map lights and rings them.
signal rings_changed(lit: Array, chosen: String)

const PANEL_WIDTH := 580
const NOTE := "Nothing changes until you cast. You can cancel the order from its token in the tray until you end the turn."
const SECTION_TITLES := {"effect": "What it will do", "blood": "The price in blood", "risk": "The risk", "pin": "The army"}

var orders: OrdersController = null
var army_id := ""
var options := []  # OrdersController.cast_options(army_id)
var ritual := ""  # the ritual shown
var target := ""
var pay := CastOrder.GOLD
var wolves := 0  # Call the Pack's size
var forecast := {}  # MagicRules.forecast_ritual for the choice shown
var budget := {}  # Forecast.cast_budget for it
var ritual_buttons := {}  # ritual id -> Button
var target_buttons := {}  # province id ("" for none) -> Button
var pay_buttons := {}  # CastOrder.GOLD / CastOrder.BLOOD -> Button
var size_buttons := {}  # wolves -> Button
var options_box: HFlowContainer
var choice_box: VBoxContainer
var intro_label: Label
var forecast_label: Label  # the forecast's first sentence; the others are in forecast_box
var forecast_box: VBoxContainer = null
var numbers_box: VBoxContainer = null  # the price and the ritual's own number, each with its breakdown
var budget_label: Label = null
var confirm_button: Button
var cancel_button: Button
var note_label: Label  # the line above the Cast button; nudge() borrows it
var _forecast_lines: Array = []  # the sentences on screen, for shown_forecast


func _init() -> void:
	name = "CastDialog"
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # the board stays clickable: a click on a lit province picks it
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -PANEL_WIDTH - 10
	panel.offset_right = -10
	panel.offset_top = 70
	panel.offset_bottom = -10
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := UiPalette.panel_style(16)
	style.border_color = UiPalette.GILT
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var head := HBoxContainer.new()
	head.name = "Head"
	box.add_child(head)
	var title := _label("Cast a ritual", 26, UiPalette.GILT)
	title.name = "Title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.mouse_filter = Control.MOUSE_FILTER_PASS
	title.tooltip_text = TooltipText.plain("Rituals", RulesCodex.text("ritual"))
	CodexLink.attach(title, "ritual", func(k): codex_requested.emit(k))
	head.add_child(title)
	cancel_button = _button("CancelButton", "Cancel", "Close this without casting anything.")
	cancel_button.pressed.connect(close)
	head.add_child(cancel_button)
	intro_label = _label("", 14, UiPalette.TEXT_SECONDARY)
	intro_label.name = "Intro"
	intro_label.set_meta("rule_text", true)  # words, with the army's name for life
	box.add_child(intro_label)
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var inner := VBoxContainer.new()
	inner.name = "Inner"
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 8)
	scroll.add_child(inner)
	options_box = HFlowContainer.new()
	options_box.name = "Options"
	options_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	options_box.add_theme_constant_override("h_separation", 6)
	options_box.add_theme_constant_override("v_separation", 6)
	inner.add_child(options_box)
	inner.add_child(HSeparator.new())
	choice_box = VBoxContainer.new()
	choice_box.name = "Choice"
	choice_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choice_box.add_theme_constant_override("separation", 6)
	inner.add_child(choice_box)
	var foot := HBoxContainer.new()
	foot.name = "Foot"
	foot.add_theme_constant_override("separation", 12)
	box.add_child(foot)
	note_label = _label(NOTE, 13, UiPalette.TEXT_SECONDARY)
	note_label.name = "Note"
	note_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(note_label)
	confirm_button = _button("ConfirmButton", "Cast", "")
	confirm_button.add_theme_color_override("font_color", UiPalette.GILT)
	confirm_button.pressed.connect(confirm)
	foot.add_child(confirm_button)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		if is_inside_tree():
			get_viewport().set_input_as_handled()


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
	var who := MagicView.casters_phrase(orders.state, army)
	var name := RulerRules._cap(TurnReportText.army_name(orders.state, army_id))
	var here := MagicRules._province_name(orders.state, army.location if army else "")
	if army != null and army.ruler != null:  # a ruler's army is the ruler alone: no "holds the Ever-Regent"
		intro_label.text = "%s at %s casts from where it starts the turn, before anyone moves, so it holds this turn." % [name, here]
	else:
		intro_label.text = "%s at %s holds %s. It casts from where it starts the turn, before anyone moves, so it holds this turn." % [name, here, who]
	var first := ""
	for o in options:
		var b := Button.new()
		b.name = "Ritual_%s" % String(o.ritual).validate_node_name()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(265, 0)
		b.add_theme_font_size_override("font_size", 14)
		b.text = "%s · %s\n%s" % [o.name, o.price, String(o.line) if o.ok else String(o.reason)]
		var icon := SpellIcons.texture(String(o.ritual))  # UI-ICONS (#233): the ritual's icon, when its art has landed
		if icon != null:
			b.icon = icon
			b.expand_icon = true
			b.add_theme_constant_override("icon_max_width", 34)
			b.set_meta("spell_icon", String(o.ritual))
		b.disabled = not o.ok
		var price_bd := Breakdown.ritual_price(orders.view_state(), orders.faction_id, String(o.ritual), int(o.sizes[0]) if not o.sizes.is_empty() else 0)
		b.set_meta("breakdown", price_bd)
		b.tooltip_text = "%s\n\n%s" % [TooltipText.from_breakdown(price_bd), TooltipText.wrap_text("%s %s" % [String(MagicRules.spell_data(o.ritual).text), "" if o.ok else String(o.reason)])]
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


## Says something to the player in the foot line (a click on a province out of reach); the next choice puts the usual note back.
func nudge(text: String) -> void:
	note_label.text = text
	note_label.add_theme_color_override("font_color", UiPalette.GILT)


## True while the dialog is open and `province_id` is a legal target of the ritual shown: a click on it on the board picks it.
func accepts_province(province_id: String) -> bool:
	return visible and not ritual.is_empty() and target_buttons.has(province_id) and not String(province_id).is_empty()


## The provinces in range of the ritual shown (ids), and the chosen one ("" when it has no target): what the board lights.
func lit_provinces() -> Array:
	var out := []
	for pid in target_buttons:
		if not String(pid).is_empty():
			out.append(String(pid))
	return out


## Confirm: asks for the CastOrder (the host queues it) and closes.
func confirm() -> void:
	if ritual.is_empty() or not forecast.get("ok", false):
		return
	visible = false
	rings_changed.emit([], "")
	confirmed.emit(ritual, army_id, target, pay, wolves)


func close() -> void:
	visible = false
	rings_changed.emit([], "")
	cancelled.emit()


## The forecast on screen, for tests: the rules' sentences, one to a line.
func shown_forecast() -> String:
	return "\n".join(_forecast_lines)


## The budget line on screen ("Gold after your queued rituals and recruits: 5."), for tests.
func shown_budget() -> String:
	return budget_label.text if budget_label != null else ""


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
	forecast_box = null
	numbers_box = null
	budget_label = null
	forecast_label = null
	# (The ritual's own line is the tooltip of its button above; the forecast below says what it does with your numbers.)
	var targets: Array = o.targets
	if not (targets.size() == 1 and String(targets[0]).is_empty()):
		choice_box.add_child(_label("Target: pick one below, or click a lit province on the board", 15, UiPalette.TEXT_PRIMARY))
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
		var wl := _label("Wolves (%d gold each)" % int(MagicRules.spell_data(ritual).cost), 15, UiPalette.TEXT_PRIMARY)
		wl.set_meta("rule_text", true)
		choice_box.add_child(wl)
		var row := HBoxContainer.new()
		row.name = "Sizes"
		choice_box.add_child(row)
		for n in range(int(o.sizes[0]), int(o.sizes[1]) + 1):
			var size_bd := Breakdown.ritual_price(orders.view_state(), orders.faction_id, ritual, n)
			var b := _button("Size_%d" % n, "%d" % n, "")
			b.set_meta("breakdown", size_bd)
			b.tooltip_text = "%s\n\n%s" % [TooltipText.from_breakdown(size_bd), TooltipText.wrap_text("Call %d Thornwolves, %d gold." % [n, n * int(MagicRules.spell_data(ritual).cost)])]
			b.toggle_mode = true
			b.pressed.connect(set_wolves.bind(n))
			row.add_child(b)
			size_buttons[n] = b
	if bool(o.blood):
		choice_box.add_child(_label("Pay with", 15, UiPalette.TEXT_PRIMARY))
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
	forecast_box = VBoxContainer.new()
	forecast_box.name = "Forecast"
	forecast_box.add_theme_constant_override("separation", 6)
	choice_box.add_child(forecast_box)
	numbers_box = VBoxContainer.new()
	numbers_box.name = "Numbers"
	numbers_box.add_theme_constant_override("separation", 2)
	choice_box.add_child(numbers_box)
	budget_label = _label("", 15, UiPalette.TEXT_PRIMARY)
	budget_label.name = "Budget"
	budget_label.mouse_filter = Control.MOUSE_FILTER_PASS
	choice_box.add_child(budget_label)


func _refresh() -> void:
	note_label.text = NOTE
	note_label.add_theme_color_override("font_color", UiPalette.TEXT_SECONDARY)
	for pid in target_buttons:
		target_buttons[pid].set_pressed_no_signal(pid == target)
	for how in pay_buttons:
		pay_buttons[how].set_pressed_no_signal(how == pay)
	for n in size_buttons:
		size_buttons[n].set_pressed_no_signal(n == wolves)
	forecast = orders.cast_preview(ritual, army_id, target, pay, wolves)
	_forecast_lines = Array(forecast.get("lines", [])).duplicate()
	_fill_forecast()
	_fill_numbers()
	_fill_budget()
	confirm_button.disabled = not forecast.get("ok", false)
	confirm_button.tooltip_text = TooltipText.plain("Cast", String(forecast.get("text", "")) if forecast.get("ok", false) \
		else String(forecast.get("reason", "")))
	rings_changed.emit(lit_provinces(), target)


## The forecast under its headings: the rules' sentences, each with what it is (MagicRules.forecast_sections).
func _fill_forecast() -> void:
	if forecast_box == null:
		return
	for c in forecast_box.get_children():
		forecast_box.remove_child(c)
		c.queue_free()
	forecast_label = null
	var sections: Array = forecast.get("sections", [])
	if sections.is_empty():
		sections = Array(forecast.get("lines", [])).map(func(t): return {"kind": "effect", "text": t})
	var turned: bool = forecast.get("effect", {}).get("outcome", "") == MagicRules.TURNED
	var tip := TooltipText.plain(MagicRules.spell_name(ritual), "%s %s" % [String(forecast.get("text", "")), RulesCodex.text(MagicRules.spell_codex(ritual))])
	for sec in sections:
		var kind := String(sec.kind)
		var h := _label(String(SECTION_TITLES.get(kind, "")), 13, UiPalette.GILT)
		h.name = "Heading_%s" % kind
		forecast_box.add_child(h)
		var colour := UiPalette.TEXT_PRIMARY
		if kind == "risk" or (kind == "effect" and turned):
			colour = UiPalette.NEGATIVE.lightened(0.2)
		var l := _label(String(sec.text), 15, colour)
		l.name = "Forecast_%s" % kind
		l.set_meta("rule_text", true)  # the rules' sentence; its numbers are listed with their breakdowns below
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		l.tooltip_text = tip
		CodexLink.attach(l, "ward" if kind == "risk" else ("pinned" if kind == "pin" else MagicRules.spell_codex(ritual)), func(k): codex_requested.emit(k))
		forecast_box.add_child(l)
		if forecast_label == null:
			forecast_label = l


## The numbers behind the forecast, each with its breakdown (§11.3): the price (gold, or the blood a Tithe of Blood cast
## takes) and the ritual's own number with your mastery ("Dawn Blessing 16 = 12 + mastery 1 x 4").
func _fill_numbers() -> void:
	if numbers_box == null:
		return
	for c in numbers_box.get_children():
		numbers_box.remove_child(c)
		c.queue_free()
	if not forecast.get("ok", false):
		return
	var view := orders.view_state()
	var fid := orders.faction_id
	var head := _label("The numbers (hover each for where it comes from)", 13, UiPalette.GILT)
	head.name = "Heading_numbers"
	numbers_box.add_child(head)
	var price := Breakdown.ritual_price(view, fid, ritual, wolves)
	var text := "Price: %d gold" % int(price.total)
	if pay == CastOrder.BLOOD:
		text = "Price: %d hit points of the army's soldiers (%d gold, 1 hit point a gold)" % [int(price.total) * MagicData.BLOOD_PER_GOLD, int(price.total)]
	_number_line("Price", text, price)
	var sp := MagicRules.spell_data(ritual)
	if not sp.get("per_bonus", {}).is_empty():
		var caster := String(forecast.get("effect", {}).get("caster", MagicRules.MAGE))
		var nb := Breakdown.spell_number(view, fid, ritual, caster if not caster.is_empty() else MagicRules.MAGE)
		_number_line("Size", "%s: %s" % [MagicRules.spell_name(ritual), MagicView.number_words(nb)], nb)


func _number_line(node_name: String, text: String, bd: Dictionary) -> void:
	var l := _label(text, 15, UiPalette.TEXT_PRIMARY)
	l.name = "Number_%s" % node_name
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	l.set_meta("breakdown", bd)
	l.tooltip_text = TooltipText.from_breakdown(bd)
	CodexLink.attach(l, String(bd.get("codex", "ritual")), func(k): codex_requested.emit(k))
	numbers_box.add_child(l)


## The gold line: what is left after the rituals and recruits queued, this cast included (Forecast.cast_budget).
func _fill_budget() -> void:
	if budget_label == null or orders == null:
		return
	var list := orders.orders()
	if forecast.get("ok", false):
		list.append(CastOrder.new(ritual, army_id, target, pay, wolves))
	budget = Forecast.cast_budget(orders.view_state(), orders.faction_id, list)
	budget_label.text = String(budget.text)
	budget_label.set_meta("breakdown", budget.breakdown)
	budget_label.tooltip_text = TooltipText.from_breakdown(budget.breakdown)
	CodexLink.attach(budget_label, "cast_order", func(k): codex_requested.emit(k))


func _show_nothing() -> void:
	ritual = ""
	forecast = {}
	_forecast_lines = []
	for c in choice_box.get_children():
		choice_box.remove_child(c)
		c.queue_free()
	forecast_label = null
	forecast_box = null
	numbers_box = null
	budget_label = null
	var none := _label("This army can't cast a ritual now: each one says why above.", 15, UiPalette.TEXT_SECONDARY)
	none.name = "Nothing"
	choice_box.add_child(none)
	confirm_button.disabled = true
	rings_changed.emit([], "")


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
	b.add_theme_font_size_override("font_size", 15)
	if not tip.is_empty():
		b.tooltip_text = TooltipText.plain(text, tip)
	return b
