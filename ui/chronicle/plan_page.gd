class_name PlanPage
extends VBoxContainer
## UX-5 (design/UX_WAR_TABLE.md §5.3): the Chronicle's Plan tab, the end-of-turn review. It draws what PlanHud hands it (show_plan, a
## PlanModel.build) and says what was pressed with signals; it holds no game facts of its own. Top to bottom:
##   - your orders as sentences: the placed ones by the tray's number, then the realm orders by their icon. Each shows the order's first
##     sentence (the order, with its price or finish turn) and, for a march into a fight, its battle forecast in gilt; the whole sentence
##     and the breakdown behind its numbers are its tooltip (the tray token's), its codex entry a right-click away; a click on it focuses
##     its place on the board and opens its card, and its x cancels it;
##   - the checks, as Needs-you cards (the Read side's own cards, with their place and codex; pinning and dismissing stay on Read);
##   - the foot: the gold after the orders, when the seal opens this page first (review before sealing, a setting), and the seal itself:
##     "Seal the orders · End turn".

signal cancel_requested(index: int)
signal focus_requested(index: int)
signal check_focus_requested(province_id: String, id: String)
signal seal_requested
signal review_changed(mode: String)
signal codex_requested(key: String)

const REVIEW_NAMES := {"first_game": "Your first game", "always": "Always", "never": "Never"}
const REVIEW_HELP := {
	"first_game": "The seal opens this page first during your first game, so you see your orders as sentences with their forecasts before they are sealed. From your second game the seal ends the turn at once.",
	"always": "The seal always opens this page first; Seal the orders here ends the turn.",
	"never": "The seal ends the turn at once. This page is still a click away on the Chronicle's Plan tab.",
}
const EMPTY := "No orders yet. Click an army to march it, or your land to recruit there; each order you give is listed here as a sentence."
const NO_CHECKS := "Nothing needs you this turn."

var intro: Label
var orders_head: Label
var scroll: ScrollContainer
var list_box: VBoxContainer
var rows: Array = []  # the sentence rows (PanelContainer), in the order shown
var empty_label: Label
var checks_head: Label
var checks_box: VBoxContainer
var check_cards: Array = []  # NoticeCard
var no_checks: Label
var gold_label: Label
var review_option: OptionButton
var seal_button: Button
var shown: Dictionary = {}  # what show_plan was last given (for tests)
var _pulse: Tween = null
var _pulsing := false


func _init() -> void:
	name = "PlanPageBody"
	add_theme_constant_override("separation", 7)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build()


## Draws `plan` (PlanModel.build), with `review` the review setting (ChronicleSettings.REVIEWS) and `seal_on` whether the seal can be
## pressed now (someone is giving orders), `seal_tip` its tooltip.
func show_plan(plan: Dictionary, review: String, seal_on: bool, seal_tip: String) -> void:
	shown = plan
	for r in rows:
		list_box.remove_child(r)
		r.queue_free()
	rows = []
	var sentences: Array = plan.get("sentences", [])
	for s in sentences:
		var row := _row(s)
		list_box.add_child(row)
		rows.append(row)
	list_box.move_child(checks_head, list_box.get_child_count() - 1)
	list_box.move_child(checks_box, list_box.get_child_count() - 1)
	list_box.move_child(no_checks, list_box.get_child_count() - 1)
	empty_label.visible = sentences.is_empty()
	var placed := sentences.filter(func(s): return not bool(s.realm)).size()
	orders_head.text = "Your orders · %s" % TooltipText.count(sentences.size(), "order") if not sentences.is_empty() else "Your orders"
	orders_head.tooltip_text = TooltipText.plain("Your orders", "%s on the board, numbered as on the board and in the tray, then the realm orders (research, the spellbook, a mandate), which have no place and no number. Each line is the order with its forecast; hover it for the numbers behind it." % TooltipText.count(placed, "placed order"))
	for c in check_cards:
		checks_box.remove_child(c)
		c.queue_free()
	check_cards = []
	for it in plan.get("checks", []):
		var card := NoticeCard.new()
		card.setup(it, {})
		card.pin_button.visible = false  # pinning and dismissing are the Read side's
		card.dismiss_button.visible = false
		card.focus_requested.connect(func(pid: String, id: String): check_focus_requested.emit(pid, id))
		card.codex_requested.connect(codex_requested.emit)
		checks_box.add_child(card)
		check_cards.append(card)
	no_checks.visible = check_cards.is_empty()
	checks_head.text = "Needs you · %d" % check_cards.size() if not check_cards.is_empty() else "Needs you"
	gold_label.text = String(plan.get("gold", ""))
	gold_label.tooltip_text = CodexLink.with_link(String(plan.get("gold_tip", "")), "gold_after_recruits")
	gold_label.visible = not gold_label.text.is_empty()
	review_option.select(ChronicleSettings.REVIEWS.find(review))
	seal_button.disabled = not seal_on
	seal_button.tooltip_text = seal_tip


## UX-9 (the director's call on Q UX-9, b): while the table's seal points here, this seal pulses gilt, slowly, as TableHud's does: one
## thing to press at a time.
func pulse_seal(on: bool) -> void:
	if on == _pulsing:
		return
	_pulsing = on
	if _pulse != null:
		_pulse.kill()
		_pulse = null
	seal_button.self_modulate = Color.WHITE
	if on and is_inside_tree():
		_pulse = create_tween().set_loops()
		_pulse.tween_property(seal_button, "self_modulate", Color(1.5, 1.35, 0.9), TableHud.PULSE_S).set_trans(Tween.TRANS_SINE)
		_pulse.tween_property(seal_button, "self_modulate", Color.WHITE, TableHud.PULSE_S).set_trans(Tween.TRANS_SINE)


func seal_pulsing() -> bool:
	return _pulsing


## The sentence rows' words, in the order shown (for tests and the no-raw-ids check).
func sentence_texts() -> Array:
	return (shown.get("sentences", []) as Array).map(func(s): return String(s.text))


func _row(s: Dictionary) -> PanelContainer:
	var row := PanelContainer.new()
	row.name = "Order_%d" % int(s.index)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_theme_stylebox_override("panel", _row_style())
	row.tooltip_text = String(s.tip)
	row.set_meta("index", int(s.index))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(line)
	if bool(s.realm):
		var icon := TextureRect.new()
		icon.name = "Icon"
		icon.texture = UiIcons.icon(String(s.icon), 16)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		icon.custom_minimum_size = Vector2(24, 24)
		icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(icon)
	else:
		var badge := NumberBadge.new(int(s.number))
		badge.name = "Number"
		badge.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		line.add_child(badge)
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", 2)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(words)
	var text := Label.new()
	text.name = "Sentence"
	text.text = String(s.get("head", s.text))
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size.x = 200
	text.add_theme_font_override("font", UiFonts.body())
	text.add_theme_font_size_override("font_size", UiPalette.TYPE_SMALL + 1)
	text.add_theme_color_override("font_color", UiPalette.TEXT_PRIMARY)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_child(text)
	if not String(s.get("forecast", "")).is_empty():
		var fc := Label.new()
		fc.name = "Forecast"
		fc.text = String(s.forecast)
		fc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		fc.max_lines_visible = 2
		fc.custom_minimum_size.x = 200
		fc.add_theme_font_override("font", UiFonts.number())
		fc.add_theme_font_size_override("font_size", UiPalette.TYPE_SMALL)
		fc.add_theme_color_override("font_color", UiPalette.GILT)
		fc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		words.add_child(fc)
	var cross := Button.new()
	cross.name = "Cancel"
	cross.icon = UiIcons.icon("dismiss", 16)
	cross.flat = true
	cross.focus_mode = Control.FOCUS_NONE
	cross.custom_minimum_size = Vector2(30, 30)
	cross.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	cross.add_theme_color_override("icon_normal_color", UiPalette.TEXT_SECONDARY)
	cross.add_theme_color_override("icon_hover_color", UiPalette.NEGATIVE)
	cross.tooltip_text = TooltipText.plain("Cancel this order", "Take it back before the turn is sealed. %s" % (OrderMarks.REALM_NOTE if bool(s.realm) else OrderMarks.RENUMBER_NOTE))
	var index := int(s.index)
	cross.pressed.connect(func(): cancel_requested.emit(index))
	line.add_child(cross)
	CodexLink.attach(row, String(s.codex), codex_requested.emit)
	row.gui_input.connect(func(e: InputEvent):
		var mb := e as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			focus_requested.emit(index)
			row.accept_event())
	return row


func _row_style() -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = Color(UiPalette.PANEL_RAISED, 0.7)
	st.border_color = UiPalette.PANEL_BORDER
	st.set_border_width_all(1)
	st.set_corner_radius_all(6)
	st.content_margin_left = 8
	st.content_margin_right = 4
	st.content_margin_top = 5
	st.content_margin_bottom = 5
	return st


func _head(node_name: String, text: String) -> Label:
	var l := Label.new()
	l.name = node_name
	l.text = text
	l.add_theme_font_override("font", UiFonts.title())
	l.add_theme_font_size_override("font_size", UiPalette.TYPE_BODY)
	l.add_theme_color_override("font_color", UiPalette.GILT)
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	return l


func _note(node_name: String, text: String) -> Label:
	var l := Label.new()
	l.name = node_name
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", UiPalette.TYPE_SMALL)
	l.add_theme_color_override("font_color", UiPalette.TEXT_SECONDARY)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build() -> void:
	intro = _note("Intro", "Your orders this turn, as they will be carried out, each with its forecast. Look them over, then seal them.")
	add_child(intro)
	scroll = ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	list_box = VBoxContainer.new()
	list_box.name = "List"
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", 6)
	scroll.add_child(list_box)
	orders_head = _head("OrdersHead", "Your orders")
	list_box.add_child(orders_head)
	empty_label = _note("Empty", EMPTY)
	list_box.add_child(empty_label)
	checks_head = _head("ChecksHead", "Needs you")
	checks_head.tooltip_text = TooltipText.plain("Needs you", "What still waits on a choice of yours this turn: research to choose, a siege to answer. An order that answers one takes it off. The Chronicle's Read side shows the same cards.")
	list_box.add_child(checks_head)
	checks_box = VBoxContainer.new()
	checks_box.name = "Checks"
	checks_box.add_theme_constant_override("separation", 6)
	list_box.add_child(checks_box)
	no_checks = _note("NoChecks", NO_CHECKS)
	list_box.add_child(no_checks)
	# The foot: the gold, the review setting and the seal.
	add_child(HSeparator.new())
	gold_label = Label.new()
	gold_label.name = "Gold"
	gold_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gold_label.add_theme_font_override("font", UiFonts.number())
	gold_label.add_theme_font_size_override("font_size", UiPalette.TYPE_SMALL)
	gold_label.add_theme_color_override("font_color", UiPalette.GILT)
	gold_label.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(gold_label)
	CodexLink.attach(gold_label, "gold_after_recruits", codex_requested.emit)
	var review_row := HBoxContainer.new()
	review_row.name = "ReviewRow"
	review_row.add_theme_constant_override("separation", 6)
	add_child(review_row)
	var review_label := Label.new()
	review_label.text = "Review before sealing"
	review_label.add_theme_font_size_override("font_size", UiPalette.TYPE_SMALL)
	review_label.add_theme_color_override("font_color", UiPalette.TEXT_SECONDARY)
	review_label.mouse_filter = Control.MOUSE_FILTER_PASS
	review_label.tooltip_text = review_tooltip()
	CodexLink.attach(review_label, "turn_review", codex_requested.emit)
	review_row.add_child(review_label)
	review_option = OptionButton.new()
	review_option.name = "Review"
	review_option.focus_mode = Control.FOCUS_NONE
	review_option.add_theme_font_size_override("font_size", UiPalette.TYPE_SMALL)
	review_option.fit_to_longest_item = false
	for mode in ChronicleSettings.REVIEWS:
		review_option.add_item(String(REVIEW_NAMES[mode]))
		review_option.set_item_tooltip(review_option.item_count - 1, TooltipText.wrap_text(String(REVIEW_HELP[mode])))
	review_option.tooltip_text = review_tooltip()
	review_option.item_selected.connect(func(i: int): review_changed.emit(String(ChronicleSettings.REVIEWS[i])))
	review_row.add_child(review_option)
	seal_button = Button.new()
	seal_button.name = "SealButton"
	seal_button.text = "Seal the orders · End turn"
	seal_button.focus_mode = Control.FOCUS_NONE
	seal_button.custom_minimum_size = Vector2(0, 48)
	seal_button.add_theme_font_size_override("font_size", UiPalette.TYPE_NAME)
	seal_button.add_theme_color_override("font_color", UiPalette.GILT)
	var st := TableHud.plaque_style(10, 6)
	st.border_color = UiPalette.GILT
	st.set_border_width_all(3)
	seal_button.add_theme_stylebox_override("normal", st)
	seal_button.pressed.connect(seal_requested.emit)
	add_child(seal_button)


static func review_tooltip() -> String:
	return TooltipText.plain("Review before sealing", "Whether the End turn seal opens this page first, so you read your orders as sentences with their forecasts before they are sealed. Your first game (the default): on during your first game, off after. Always, or Never: the seal ends the turn at once. Settings has it too.")
