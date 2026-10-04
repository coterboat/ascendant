class_name TurnReportPanel
extends PanelContainer
## The last resolved turn's report (#7): a header, then one row per event in resolver order, grouped
## under plain-language phase headings. A game-over event is pulled to the top and highlighted.
## Clicking a row asks the map to focus its first province; battle rows get a "Battle report" button.
## Rows whose event names a RulesCodex entry get a small "?" button that asks for that entry
## (codex_requested), so the host can open the codex panel there.
## Games with a computer seat (#35) add two things. Under the header, the seats are named, each computer
## faction with its "Computer (Normal)" tag. Under the events, pinned above the footer so it never
## scrolls out of sight, a collapsible "What the computer was thinking" section lists the computer's own
## notes (AIPlayer.last_plan_notes) for the turn that just resolved, in a box of its own that scrolls
## when the notes are long. The host passes them in (AISeat.report_notes), and they are never shown
## before the turn resolves, because they describe the computer's simultaneous orders. The section
## remembers whether the player opened or closed it.
## Reads the session only and never changes rules state. Builds its children in code.
## Art (#10): a recruitment row shows the recruited unit's face at its left (Art), and the panel uses the
## style bible's deep indigo.

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
const BACKGROUND := UiPalette.PANEL_BG
const ROW_PORTRAIT := Vector2(40, 40)
## The computer's notes box: at most this tall (it scrolls past that), sized from a rough line count.
const NOTES_MAX_HEIGHT := 190
const NOTE_LINE_HEIGHT := 25
const NOTE_CHARS_PER_LINE := 105

var header_label: Label
var seats_box: HBoxContainer  # the seats, with the computer tag; only in games with a computer seat
var empty_label: Label
var victory_box: PanelContainer
var victory_label: Label
var rows_box: VBoxContainer
var scroll: ScrollContainer
var _event_rows: Array[Button] = []
var _battle_buttons: Array[Button] = []
var _codex_buttons: Array[Button] = []
var computer_notes_open := true  # the player's choice for the notes section, kept across turns
var notes_section: VBoxContainer  # pinned under the events; hidden without computer notes
var notes_toggle: Button = null  # the section's header button, while the report has computer notes
var notes_scroll: ScrollContainer
var notes_body: VBoxContainer
var _note_labels: Array[Label] = []


func _init() -> void:
	name = "TurnReportPanel"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()


## Rebuilds the panel from session.turn_report(). `computer_notes` (AISeat.report_notes) fills the
## "What the computer was thinking" section; leave it empty in a hotseat game.
func show_report(session: GameSession, computer_notes: Array = []) -> void:
	show_report_data(session.turn_report() if session != null else {})
	_show_seats(session)
	show_computer_notes(computer_notes)


## Rebuilds the panel from a report dictionary shaped like GameSession.turn_report().
func show_report_data(report: Dictionary) -> void:
	_clear_rows()
	_clear_seats()
	show_computer_notes([])
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


## Fills the "What the computer was thinking" section under the events: one block per computer seat
## ({"faction_name", "seat", "level", "notes"}, see AISeat.report_notes). An empty list hides it.
func show_computer_notes(entries: Array) -> void:
	_note_labels.clear()
	for c in notes_body.get_children():
		notes_body.remove_child(c)
		c.queue_free()
	notes_section.visible = not entries.is_empty()
	notes_toggle = notes_section.get_node("ComputerNotesToggle") if not entries.is_empty() else null
	if entries.is_empty():
		return
	var lines := 0  # rough wrapped line count, for the box's height
	for entry in entries:
		var level := String(entry.get("level", ""))
		var faction_name := String(entry.get("faction_name", "The computer"))
		if entries.size() > 1:
			var who := Label.new()
			who.text = "%s, %s" % [faction_name, AISeat.tag_text(level)]
			who.add_theme_font_size_override("font_size", 18)
			who.add_theme_color_override("font_color", UiPalette.seat_color(int(entry.get("seat", 0))).lightened(0.3))
			notes_body.add_child(who)
			lines += 1
		var notes: Array = entry.get("notes", [])
		if notes.is_empty():
			notes = ["Nothing new to report this turn."]
		for line in notes:
			var l := Label.new()
			l.text = "•  %s" % line
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.add_theme_font_size_override("font_size", 17)
			l.add_theme_color_override("font_color", UiPalette.TEXT_SECONDARY)
			l.tooltip_text = TooltipText.plain("%s, %s" % [faction_name, AISeat.tag_text(level)], AISeat.tag_help(faction_name, level))
			CodexLink.attach(l, "computer_opponent", codex_requested.emit)
			notes_body.add_child(l)
			_note_labels.append(l)
			lines += ceili((String(line).length() + 3) / float(NOTE_CHARS_PER_LINE))
	notes_scroll.custom_minimum_size = Vector2(0, mini(lines * NOTE_LINE_HEIGHT + 6, NOTES_MAX_HEIGHT))
	_refresh_notes_toggle()


## Opens or closes the notes section; the choice holds for the next reports too.
func toggle_computer_notes() -> void:
	computer_notes_open = not computer_notes_open
	_refresh_notes_toggle()


## The note lines of the notes section, in display order (empty without computer notes).
func computer_note_labels() -> Array[Label]:
	return _note_labels


func _refresh_notes_toggle() -> void:
	if notes_toggle == null:
		return
	var count := _note_labels.size()
	notes_toggle.text = "What the computer was thinking (%s)  ·  %s" % [TooltipText.count(count, "note"),
		"click to hide" if computer_notes_open else "click to show"]
	notes_scroll.visible = computer_notes_open


## The seats under the header, each computer faction with its tag. Only for games with a computer seat.
func _show_seats(session: GameSession) -> void:
	_clear_seats()
	if session == null or session.computer_seats().is_empty():
		return
	var state := session.state()
	var players := session.players()
	for i in players.size():
		var fid := String(players[i])
		if i > 0:
			var vs := Label.new()
			vs.text = "vs"
			vs.add_theme_font_size_override("font_size", 18)
			vs.add_theme_color_override("font_color", UiPalette.TEXT_SECONDARY)
			seats_box.add_child(vs)
		var seat := HBoxContainer.new()
		seat.name = "Seat%d" % (i + 1)
		seat.add_theme_constant_override("separation", 8)
		seats_box.add_child(seat)
		seat.add_child(VictoryScreen.seat_emblem(i))
		var f := state.find_faction(fid)
		var faction_name := f.faction_name if f else "An unknown faction"
		var name_label := Label.new()
		name_label.text = faction_name
		if not session.is_computer(fid) and session.human_seats() == 1:
			name_label.text += " (you)"
		name_label.add_theme_font_size_override("font_size", 18)
		name_label.add_theme_color_override("font_color", UiPalette.seat_color(i).lightened(0.3))
		seat.add_child(name_label)
		if session.is_computer(fid):
			seat.add_child(VictoryScreen.computer_tag(faction_name, session.computer_level(fid), codex_requested.emit))
	seats_box.visible = true


func _clear_seats() -> void:
	for c in seats_box.get_children():
		seats_box.remove_child(c)
		c.queue_free()
	seats_box.visible = false


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
	var unit_id := recruited_unit(e)
	if not unit_id.is_empty():
		var card := Art.portrait_card(unit_id, ROW_PORTRAIT, "", Art.Crop.FACE)
		row.add_child(card)
		row.move_child(card, 0)

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


## The unit type a "recruited" event is about ("knights"), found by the unit names of the recruiting
## faction in the event's text; "" for any other event.
static func recruited_unit(e: Dictionary) -> String:
	if str(e.get("type", "")) != "recruited":
		return ""
	var factions: Array = e.get("factions", [])
	var text := str(e.get("text", ""))
	for f in FactionData.FACTIONS:
		if not factions.is_empty() and f.id != str(factions[0]):
			continue
		for u in f.unit_types + [f.commander]:
			if text.contains(" recruited %s " % u.name):
				return String(u.id)
		# M4-2: a transformation's renamed and new units (PathData), which the faction data doesn't name.
		for nid in AscensionRules.node_ids(String(f.id)):
			var fx := AscensionRules.node_effects(nid)
			for type_id in fx.get("rename", {}):
				if text.contains(" recruited %s " % String(fx.rename[type_id])):
					return String(type_id)
			var new_id := String(fx.get("new_unit", ""))
			if not new_id.is_empty() and text.contains(" recruited %s " % String(PathData.NEW_UNITS[new_id].name)):
				return new_id
	return ""


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
	style.bg_color = BACKGROUND  # opaque: nothing under the report (map, victory screen) shows through its text
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

	seats_box = HBoxContainer.new()
	seats_box.name = "Seats"
	seats_box.add_theme_constant_override("separation", 8)
	seats_box.visible = false
	box.add_child(seats_box)

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

	# The computer's notes (#35): pinned under the events, hidden in hotseat games.
	notes_section = VBoxContainer.new()
	notes_section.name = "ComputerNotes"
	notes_section.add_theme_constant_override("separation", 4)
	notes_section.visible = false
	box.add_child(notes_section)
	notes_section.add_child(HSeparator.new())
	var toggle := Button.new()
	toggle.name = "ComputerNotesToggle"
	toggle.flat = true
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggle.add_theme_font_size_override("font_size", 22)
	for state_name in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		toggle.add_theme_color_override(state_name, Color(0.95, 0.82, 0.5))
	toggle.tooltip_text = TooltipText.plain("What the computer was thinking",
		"The computer's own reasons for the orders it gave this turn. It decided them from the map at the start of the turn, at the same time as you and without seeing your orders, so they only appear once the turn has resolved. Click to show or hide them.")
	CodexLink.attach(toggle, "computer_opponent", codex_requested.emit)
	toggle.pressed.connect(toggle_computer_notes)
	notes_section.add_child(toggle)
	notes_scroll = ScrollContainer.new()
	notes_scroll.name = "ComputerNotesScroll"
	notes_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	notes_section.add_child(notes_scroll)
	notes_body = VBoxContainer.new()
	notes_body.name = "ComputerNotesBody"
	notes_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	notes_body.add_theme_constant_override("separation", 4)
	notes_scroll.add_child(notes_body)
