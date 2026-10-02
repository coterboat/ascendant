class_name TurnReportPanel
extends PanelContainer
## The last resolved turn's report (#7): a header, then one row per event in resolver order, grouped
## under plain-language phase headings. A game-over event is pulled to the top and highlighted.
## Clicking a row asks the map to focus its first province; battle rows get a "Battle report" button.
## Rows whose event names a RulesCodex entry get a small "?" button that asks for that entry
## (codex_requested), so the host can open the codex panel there.
## Reads the session only and never changes rules state. Builds its children in code.

signal province_focus_requested(province_id: String)
signal battle_report_requested(event: Dictionary)
signal codex_requested(key: String)

const PHASE_TITLES := {
	"orders": "Orders",
	"movement": "Movement",
	"battles": "Battles",
	"capture": "Captures",
	"recruitment": "Recruitment",
	"income": "Income",
	"victory": "Victory",
}
const GAME_OVER_TYPE := "game_over"

var header_label: Label
var empty_label: Label
var victory_box: PanelContainer
var victory_label: Label
var rows_box: VBoxContainer
var scroll: ScrollContainer
var _event_rows: Array[Button] = []
var _battle_buttons: Array[Button] = []
var _codex_buttons: Array[Button] = []


func _init() -> void:
	name = "TurnReportPanel"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()


## Rebuilds the panel from session.turn_report().
func show_report(session: GameSession) -> void:
	show_report_data(session.turn_report() if session != null else {})


## Rebuilds the panel from a report dictionary shaped like GameSession.turn_report().
func show_report_data(report: Dictionary) -> void:
	_clear_rows()
	header_label.text = report.get("header", "No turns have been resolved yet.")
	var events: Array = report.get("events", [])
	empty_label.visible = events.is_empty() and int(report.get("turn", 0)) > 0

	var victory_texts: Array[String] = []
	for e in events:
		if _is_game_over(e):
			victory_texts.append(str(e.get("text", "")))
	victory_label.text = "\n".join(victory_texts)
	victory_box.visible = not victory_texts.is_empty()

	var current_phase := ""
	for e in events:
		if _is_game_over(e):
			continue
		var phase := str(e.get("phase", ""))
		if phase != current_phase:
			current_phase = phase
			rows_box.add_child(_phase_heading(phase))
		rows_box.add_child(_event_row(e))
	visible = true


## Every event row button, in display order (for tests and keyboard focus).
func event_rows() -> Array[Button]:
	return _event_rows


func battle_buttons() -> Array[Button]:
	return _battle_buttons


## The "?" buttons, in display order. Each has meta "codex_key" naming its RulesCodex entry.
func codex_buttons() -> Array[Button]:
	return _codex_buttons


static func phase_title(phase: String) -> String:
	return PHASE_TITLES.get(phase, phase.capitalize())


func _is_game_over(e: Dictionary) -> bool:
	return e.get("type", "") == GAME_OVER_TYPE


func _phase_heading(phase: String) -> Label:
	var l := Label.new()
	l.name = "Heading_%s" % phase
	l.text = phase_title(phase)
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", Color(0.95, 0.82, 0.5))
	return l


## One event: [the event text button, its "Battle report" button] in an inner box, then the "?".
func _event_row(e: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var content := HBoxContainer.new()
	content.name = "Event"
	content.add_theme_constant_override("separation", 12)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(content)
	var provinces: Array = e.get("provinces", [])

	var b := Button.new()
	b.text = str(e.get("text", ""))
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 18)
	var tip := RulesCodex.text(str(e.get("codex", "")))
	if not provinces.is_empty():
		tip = ("%s\n\n" % tip if not tip.is_empty() else "") + "Click to show this on the map."
	b.tooltip_text = tip
	b.set_meta("event", e)
	b.pressed.connect(_on_row_pressed.bind(e))
	content.add_child(b)
	_event_rows.append(b)

	if GameSession.BATTLE_TYPES.has(e.get("type", "")):
		var battle := Button.new()
		battle.text = "Battle report"
		battle.tooltip_text = "Open the full report for this battle: who fought, the odds, and the losses."
		battle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		battle.pressed.connect(_on_battle_pressed.bind(e))
		content.add_child(battle)
		_battle_buttons.append(battle)

	var key := str(e.get("codex", ""))
	if RulesCodex.ENTRIES.has(key):
		row.add_child(_codex_button(key))
	return row


func _codex_button(key: String) -> Button:
	var q := Button.new()
	q.name = "CodexButton"
	q.text = "?"
	q.custom_minimum_size = Vector2(36, 36)
	q.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	q.add_theme_font_size_override("font_size", 18)
	q.tooltip_text = "Explain this: opens the codex entry \"%s\"." % String(RulesCodex.entry(key).get("title", ""))
	q.set_meta("codex_key", key)
	q.pressed.connect(_on_codex_pressed.bind(key))
	_codex_buttons.append(q)
	return q


func _on_row_pressed(e: Dictionary) -> void:
	var provinces: Array = e.get("provinces", [])
	if not provinces.is_empty():
		province_focus_requested.emit(str(provinces[0]))


func _on_battle_pressed(e: Dictionary) -> void:
	battle_report_requested.emit(e.duplicate(true))


func _on_codex_pressed(key: String) -> void:
	codex_requested.emit(key)


func _clear_rows() -> void:
	_event_rows.clear()
	_battle_buttons.clear()
	_codex_buttons.clear()
	for c in rows_box.get_children():
		rows_box.remove_child(c)
		c.queue_free()


func _build() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.11, 0.14, 0.97)
	style.set_content_margin_all(24)
	add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", 14)
	add_child(box)

	header_label = Label.new()
	header_label.name = "HeaderLabel"
	header_label.add_theme_font_size_override("font_size", 32)
	box.add_child(header_label)

	victory_box = PanelContainer.new()
	victory_box.name = "VictoryBanner"
	var vstyle := StyleBoxFlat.new()
	vstyle.bg_color = Color(0.35, 0.27, 0.06, 1.0)
	vstyle.border_color = Color(1.0, 0.84, 0.3)
	vstyle.set_border_width_all(3)
	vstyle.set_content_margin_all(16)
	victory_box.add_theme_stylebox_override("panel", vstyle)
	victory_box.visible = false
	victory_box.tooltip_text = RulesCodex.text("victory")
	box.add_child(victory_box)
	victory_label = Label.new()
	victory_label.name = "VictoryLabel"
	victory_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	victory_label.add_theme_font_size_override("font_size", 24)
	victory_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.75))
	victory_box.add_child(victory_label)

	empty_label = Label.new()
	empty_label.name = "EmptyLabel"
	empty_label.text = "Nothing happened this turn."
	empty_label.visible = false
	box.add_child(empty_label)

	scroll = ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	rows_box = VBoxContainer.new()
	rows_box.name = "Rows"
	rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows_box.add_theme_constant_override("separation", 6)
	scroll.add_child(rows_box)
