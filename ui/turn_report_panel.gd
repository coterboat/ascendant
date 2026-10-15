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
## M3a.2: on the 3D board a "Watch this turn again" button by the header (set_watch_again) asks the host
## to play the turn on the land once more (watch_again_requested); the report opens again after it.
## M3-5 (#60, design/M3_BATTLES.md §6): every battle row gets **Watch** beside "Battle report"
## (watch_requested(event)), disabled with the reason when the battle can't be played back
## (BattleHost.watch_problem); the computer's battles are watchable like anyone's. The header gets **Watch
## your battles (N)** (watch_battles_requested(events)): the viewer's battles in report order, or "Watch
## the battles (N)" when nobody in particular reads the report (watch mode, game over).
## #55: with the state after the turn (show_report always has it), the rows read as TurnReportText writes
## them: armies by their names for life ("the Crown's 3rd"), battles by the units that fought and how each
## side came out, captures by what became of the defenders, rejected orders by their result, and the moves
## of the movement phase grouped by destination. A row naming armies says how they are named in its tooltip.
## Without a state (show_report_data's default) the rows are the events' own text, in resolver order.
## M3c S-3 (#101, design/M3C_SIEGES.md §9.4, §9.5), in a game with sieges: the Sieges phase gets its heading (the
## lines themselves, fort clauses and the reader's turn words included, are TurnReportText's); the "needs you" lines at the top name the viewer's besieged forts, the
## forts it besieges and any breach (show_siege_needs_you, FortView.needs_you); and with the game screen's
## chronicle set, the first siege, storm, sally and breach of the game each get two plain sentences under their
## line, with a codex link, once per player (SiegeChronicle.teach).
## M5-2 fog of war (#113, design/M5_MAGIC_FOG.md §2.8, §11.1): show_report reads the session as its viewer does
## (turn_report_for, state_for, view_before): the report is the viewer's own, with the line "Fog of war: this report shows
## what you saw" under the header (fog_label), and under each battle you fought where the enemy differed from what you
## saw at the start of the turn, its "what you didn't see" (FogView.missed_text).

signal province_focus_requested(province_id: String)
signal battle_report_requested(event: Dictionary)
signal codex_requested(key: String)
## M3a.2: "Watch this turn again" was pressed (only shown while the host can replay the turn on the board).
signal watch_again_requested
## M3-5: a battle row's Watch, and "Watch your battles (N)" (the battles in report order).
signal watch_requested(event: Dictionary)
signal watch_battles_requested(events: Array)

const PHASE_TITLES := {
	"orders": "Orders",
	"movement": "Movement",
	"battles": "Battles",
	"sieges": "Sieges",
	"capture": "Captures",
	"recruitment": "Recruitment",
	"income": "Income",
	"rituals": "Rituals",  # M5-6
	"enchantments": "Enchantments",  # M5-6
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
var watch_again_button: Button  # M3a.2: hidden unless the host can replay the turn (set_watch_again)
var watch_battles_button: Button  # M3-5: "Watch your battles (N)"; hidden when the report has none
## M3-5: whether a battle whose log isn't kept can be rebuilt (the host has the game record): show_report
## sets it when it has a session (show_report_data's `rebuild`).
var can_rebuild := false
var _watch_buttons: Array[Button] = []
var _watch_queue: Array = []  # the battles "Watch your battles" plays, in report order
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
var _viewer := ""  # M4-4: the faction the report is shown to ("" for public text only)
var needs_you_label: Label = null  # M4-4: "Choose what to research: ..." at the top, when it applies
## M3c S-3: the game's siege chronicle (the game screen sets it), for the first-siege sentences; null: none.
var chronicle: SiegeChronicle = null
var siege_needs_you: VBoxContainer = null  # M3c S-3: the siege "needs you" lines at the top, when there are any
## M5-2: the fog header line (hidden without fog), and the viewer's view at the start of the reported turn, for "what you
## didn't see" (show_report sets it; null: no such lines).
var fog_label: Label
var fog_before: GameState = null


func _init() -> void:
	name = "TurnReportPanel"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()


## Rebuilds the panel from the session's report as `eyes` read it (GameScreen.viewer(): the person at the controls, or
## the observer once nobody in particular is; M5-2). Without `eyes`, the person giving orders now, or nobody in
## particular. `computer_notes` (AISeat.report_notes) fills the "What the computer was thinking" section; leave it
## empty in a hotseat game.
func show_report(session: GameSession, computer_notes: Array = [], eyes: String = "") -> void:
	# M4-4: the person at the controls reads their own transformation as "Your people have become ..." and,
	# with nothing to research chosen, the "needs you" line. Nobody (watch mode, game over) reads public text.
	var viewer := ""
	if session != null and session.phase() == GameSession.Phase.ORDERS and not session.is_computer(session.current_player()):
		viewer = session.current_player()
	if eyes.is_empty():
		eyes = viewer
	elif session != null and session.players().has(eyes) and session.phase() != GameSession.Phase.GAME_OVER:
		viewer = eyes
	var report := session.turn_report_for(eyes) if session != null else {}
	var after: GameState = session.state_for(eyes) if session != null else null
	fog_before = session.view_before(eyes) if session != null and bool(report.get("fog", false)) else null
	show_report_data(report, viewer, session != null, after)
	if not viewer.is_empty() and after != null:
		# UX-6 (§5.2): the current-state "needs you" lines are one pure function, ChronicleModel.needs, which the Chronicle reads too
		var needs := ChronicleModel.needs(after, viewer, int(report.get("turn", 0)))
		var research := needs.filter(func(n): return String(n.kind) == "research")
		show_needs_you(String(research[0].text) if not research.is_empty() else "")
		show_siege_needs_you(needs.filter(func(n): return String(n.kind) == "siege").map(func(n): return {"text": n.text, "province": n.province, "codex": n.codex}))  # M3c
	_show_seats(session, after)
	show_computer_notes(computer_notes)


## Rebuilds the panel from a report dictionary shaped like GameSession.turn_report(). `rebuild` (M3-5): a
## battle log that isn't kept can be rebuilt from the game record (show_report has the session). `state`
## (#55): the state after the turn, which the rows' wording reads (TurnReportText.rows).
func show_report_data(report: Dictionary, viewer: String = "", rebuild: bool = false, state: GameState = null) -> void:
	_viewer = viewer
	can_rebuild = rebuild
	_clear_rows()
	_clear_seats()
	show_computer_notes([])
	header_label.text = report.get("header", "No turns have been resolved yet.")
	fog_label.visible = bool(report.get("fog", false))  # M5-2
	var events: Array = report.get("events", [])
	empty_label.visible = events.is_empty() and int(report.get("turn", 0)) > 0

	var victory_texts: Array[String] = []
	for e in events:
		if _is_game_over(e):
			victory_texts.append(str(e.get("text", "")))
	victory_label.text = "\n".join(victory_texts)
	victory_box.visible = not victory_texts.is_empty()

	var current_phase := ""
	var sieges := state != null and state.sieges
	var teach: Array = chronicle.teach(events, viewer, int(report.get("turn", 0))) if chronicle != null and sieges else []
	for row in TurnReportText.rows(events, state, viewer):
		var e: Dictionary = row.event
		if _is_game_over(e):
			continue
		var phase := str(e.get("phase", ""))
		if phase != current_phase:
			current_phase = phase
			rows_box.add_child(_phase_heading(phase))
		rows_box.add_child(_event_row(e, String(row.text), state != null))
		if fog_label.visible and fog_before != null:
			var missed := FogView.missed_text(e, viewer, fog_before)  # M5-2: what you didn't see
			if not missed.is_empty():
				rows_box.add_child(_missed_row(missed))
		for t in teach:
			if is_same(t.event, e):
				rows_box.add_child(_teach_row(t))  # M3c: the first siege, storm, sally or breach of the game
	_show_watch_battles(events)
	visible = true


## Every event row button, in display order (for tests and keyboard focus).
func event_rows() -> Array[Button]:
	return _event_rows


func battle_buttons() -> Array[Button]:
	return _battle_buttons


## M3-5: every battle row's Watch button, in display order (meta "event": its battle event).
func watch_buttons() -> Array[Button]:
	return _watch_buttons


## M3-5: the battles "Watch your battles (N)" plays, in report order.
func watch_queue() -> Array:
	return _watch_queue.duplicate(true)


## The "?" buttons, in display order. Each has meta "codex_key" naming its RulesCodex entry.
func codex_buttons() -> Array[Button]:
	return _codex_buttons


## Shows or hides "Watch this turn again" (the host shows it while the 3D board can replay the turn).
func set_watch_again(enabled: bool) -> void:
	watch_again_button.visible = enabled


static func phase_title(phase: String) -> String:
	return PHASE_TITLES.get(phase, phase.capitalize())


## Fills the "What the computer was thinking" section under the events: one block per computer seat
## ({"faction_name", "seat", "level", "notes"}, see AISeat.report_notes). An empty list hides it. Entries that are all
## "hidden": true (fog: the notes are kept back) show as one quiet line, without the header.
func show_computer_notes(entries: Array) -> void:
	_note_labels.clear()
	for c in notes_body.get_children():
		notes_body.remove_child(c)
		c.queue_free()
	notes_section.visible = not entries.is_empty()
	notes_toggle = notes_section.get_node("ComputerNotesToggle") if not entries.is_empty() else null
	if entries.is_empty():
		return
	# MVP-3 (#177): under fog every note is "hidden while the fog lasts": that is one quiet line, not a header with a count
	# and a scrolling box (it squeezed the events list on every turn). The line keeps its tooltip and its codex link.
	var quiet := entries.all(func(en): return bool(en.get("hidden", false)))
	notes_toggle.visible = not quiet
	if quiet:
		var first: Dictionary = entries[0]
		var line := Label.new()
		line.text = String((first.get("notes", [""]) as Array)[0])
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.add_theme_font_size_override("font_size", 15)
		line.add_theme_color_override("font_color", UiPalette.TEXT_SECONDARY)
		line.tooltip_text = TooltipText.plain("What the computer was thinking", "The computer's own reasons for the orders it gave this turn. Under the fog of war they would name its hidden armies and plans, so they are kept back until the game is over. %s" % AISeat.tag_help(
			String(first.get("faction_name", "The computer")), String(first.get("level", ""))))
		CodexLink.attach(line, "computer_opponent", codex_requested.emit)
		notes_body.add_child(line)
		_note_labels.append(line)
		notes_scroll.custom_minimum_size = Vector2(0, 28)
		_refresh_notes_toggle()
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
	notes_scroll.visible = computer_notes_open or not notes_toggle.visible  # the quiet fog line has no header to fold it


## The seats under the header, each computer faction with its tag. Only for games with a computer seat. `state` is the
## game as the reader sees it (names only).
func _show_seats(session: GameSession, state: GameState) -> void:
	_clear_seats()
	if session == null or state == null or session.computer_seats().is_empty():
		return
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


## One event: [the event text button, its "Battle report" button] in an inner box, then the "?". `text` is
## its line (TurnReportText); `named` says the line calls armies by their names.
func _event_row(e: Dictionary, text: String, named: bool = false) -> HBoxContainer:
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
	b.text = text
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 18)
	var tip := RulesCodex.text(str(e.get("codex", "")))
	if named and TurnReportText.NAMES_ARMIES.has(str(e.get("type", ""))):
		tip = ("%s\n\n" % tip if not tip.is_empty() else "") + TurnReportText.NAMES_HINT
	if not provinces.is_empty():
		tip = ("%s\n\n" % tip if not tip.is_empty() else "") + "Click to show this on the map."
	b.tooltip_text = tip
	b.set_meta("event", e)
	b.pressed.connect(_on_row_pressed.bind(e))
	content.add_child(b)
	_event_rows.append(b)

	if GameSession.BATTLE_TYPES.has(e.get("type", "")):
		content.add_child(_watch_button(e))
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


## The text of event `e` as `viewer` reads it (M4-4): a faction's own transformation speaks to it ("Your
## people have become the Celestial Host. ...", the event's numbers.own_text); everything else as it is.
## The rows read TurnReportText's lines, which use this for the events whose own text they keep.
static func event_text(e: Dictionary, viewer: String = "") -> String:
	return TurnReportText.own_text(e, viewer)


## The "needs you" line (M4-4, design/M4_ASCENSION.md §9.5) at the top of the report: nothing is being
## researched and research is waiting. "" removes it.
func show_needs_you(text: String) -> void:
	if needs_you_label != null:
		rows_box.remove_child(needs_you_label)
		needs_you_label.queue_free()
		needs_you_label = null
	if text.is_empty():
		return
	needs_you_label = Label.new()
	needs_you_label.name = "NeedsYou"
	needs_you_label.text = "Needs you: %s" % text
	needs_you_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	needs_you_label.add_theme_font_size_override("font_size", 18)
	needs_you_label.add_theme_color_override("font_color", UiPalette.GILT)
	needs_you_label.tooltip_text = TooltipText.plain("Choose what to research", RulesCodex.text("research_order"))
	CodexLink.attach(needs_you_label, "research_order", codex_requested.emit)
	rows_box.add_child(needs_you_label)
	rows_box.move_child(needs_you_label, 0)


## M3c S-3: the siege "needs you" lines (FortView.needs_you: [{"text", "province", "codex"}]) at the top, under
## any research line; each one shows its fort on the map when clicked. [] removes them.
func show_siege_needs_you(lines: Array) -> void:
	if siege_needs_you != null:
		rows_box.remove_child(siege_needs_you)
		siege_needs_you.queue_free()
		siege_needs_you = null
	if lines.is_empty():
		return
	siege_needs_you = VBoxContainer.new()
	siege_needs_you.name = "SiegeNeedsYou"
	siege_needs_you.add_theme_constant_override("separation", 2)
	for line in lines:
		var b := Button.new()
		b.name = "NeedsYou_%s" % String(line.province).validate_node_name()
		b.text = "Needs you: %s" % String(line.text)
		b.flat = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_font_size_override("font_size", 18)
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			b.add_theme_color_override(c, UiPalette.GILT)
		b.tooltip_text = TooltipText.plain("Needs you", "%s Click to show it on the map." % RulesCodex.text(String(line.codex)))
		CodexLink.attach(b, String(line.codex), codex_requested.emit)
		var pid := String(line.province)
		b.pressed.connect(func(): province_focus_requested.emit(pid))
		siege_needs_you.add_child(b)
	rows_box.add_child(siege_needs_you)
	rows_box.move_child(siege_needs_you, 1 if needs_you_label != null else 0)


## UX-9: the width a wrapping row's words measure their height at (narrower than the panel at its smallest, 1280x720 logical).
const WRAP_W := 620.0


## M5-2 (§2.8): "What you didn't see: ..." under a battle you fought, linked to the odds-against-what-you-can-see entry.
func _missed_row(text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Missed"
	row.add_theme_constant_override("separation", 12)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(28, 0)
	row.add_child(pad)
	var l := Label.new()
	l.name = "MissedText"
	l.text = "What you didn't see: %s" % text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = WRAP_W  # UX-9: a wrapping line measures its height at a real width (it ran off the panel at 125%)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", UiPalette.GILT)
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	l.tooltip_text = TooltipText.plain("What you didn't see", "The enemy that fought you was not what you saw at the start of the turn: armies can join during a turn, and a glimpse rounds what it shows. %s" % RulesCodex.text("view_odds"))
	CodexLink.attach(l, "view_odds", codex_requested.emit)
	row.add_child(l)
	return row


## M3c S-3 (§9.5): a first-siege sentence under its line: "Your first siege. A siege: ...", linked to its entry.
func _teach_row(t: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Teach_%s" % String(t.kind)
	row.add_theme_constant_override("separation", 12)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(28, 0)
	row.add_child(pad)
	var l := Label.new()
	l.text = "%s. %s" % [String(t.title), String(t.text)]
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = WRAP_W
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", UiPalette.GILT.lerp(UiPalette.TEXT_PRIMARY, 0.35))
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	l.tooltip_text = TooltipText.plain(String(t.title), RulesCodex.text(String(t.codex)))
	CodexLink.attach(l, String(t.codex), codex_requested.emit)
	row.add_child(l)
	row.add_child(_codex_button(String(t.codex)))
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


## M3-5: a battle row's Watch: plays the battle back, or says why it can't.
func _watch_button(e: Dictionary) -> Button:
	var w := Button.new()
	w.name = "WatchButton"
	w.text = "Watch"
	w.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	w.set_meta("event", e)
	var why := BattleHost.watch_problem(e, can_rebuild)
	w.disabled = not why.is_empty()
	if why.is_empty():
		var tip := "Play this battle back. The playback shows exactly what the report describes, and watching never changes anything."
		if BattleHost.needs_rebuild(e):
			tip += " Its playback is rebuilt from the game record first, which takes a moment."
		w.tooltip_text = TooltipText.plain("Watch this battle", tip)
	else:
		w.tooltip_text = TooltipText.plain("Can't watch this battle", why)
	w.pressed.connect(func(): watch_requested.emit(e.duplicate(true)))
	_watch_buttons.append(w)
	return w


## M3-5: "Watch your battles (N)" at the top: the viewer's battles that can be played back, in report order
## ("Watch the battles (N)" for nobody in particular). Hidden when the viewer fought none.
func _show_watch_battles(events: Array) -> void:
	var theirs := BattleHost.battles_of(events, _viewer)
	_watch_queue = BattleHost.watchable(theirs, can_rebuild)
	watch_battles_button.visible = not theirs.is_empty()
	if theirs.is_empty():
		return
	var n := _watch_queue.size()
	var whose := "your" if not _viewer.is_empty() else "the"
	watch_battles_button.text = "Watch %s battles (%d)" % [whose, n]
	watch_battles_button.disabled = n == 0
	var left_out := theirs.size() - n
	var why := ""
	for e in theirs:
		why = BattleHost.watch_problem(e, can_rebuild)
		if not why.is_empty():
			break
	if n == 0:
		watch_battles_button.tooltip_text = TooltipText.plain("Can't watch these battles", why)
		return
	var what := "%s battle of this turn back" % whose if n == 1 \
		else "%s %d battles of this turn back, one after another, in the order this report lists them" % [whose, n]
	var tip := "Play %s. Next battle moves on, and the last one brings you back here; Esc comes back at any time. Watching never changes anything." % what
	if left_out > 0:
		tip += " %s can't be played back: %s" % [TooltipText.count(left_out, "more battle"), why]
	watch_battles_button.tooltip_text = TooltipText.plain("Watch %s battles" % whose, tip)


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
	needs_you_label = null  # freed with the rows below
	siege_needs_you = null
	_event_rows.clear()
	_battle_buttons.clear()
	_watch_buttons.clear()
	_watch_queue = []
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

	var head_row := HBoxContainer.new()
	head_row.name = "HeadRow"
	head_row.add_theme_constant_override("separation", 16)
	box.add_child(head_row)
	header_label = Label.new()
	header_label.name = "HeaderLabel"
	header_label.add_theme_font_size_override("font_size", 32)
	header_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_row.add_child(header_label)
	watch_battles_button = Button.new()
	watch_battles_button.name = "WatchBattlesButton"
	watch_battles_button.text = "Watch your battles"
	watch_battles_button.visible = false
	watch_battles_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	watch_battles_button.add_theme_font_size_override("font_size", 18)
	watch_battles_button.add_theme_color_override("font_color", UiPalette.GILT)
	watch_battles_button.pressed.connect(func(): watch_battles_requested.emit(_watch_queue.duplicate(true)))
	head_row.add_child(watch_battles_button)
	watch_again_button = Button.new()
	watch_again_button.name = "WatchAgainButton"
	watch_again_button.text = "Watch this turn again"
	watch_again_button.visible = false
	watch_again_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	watch_again_button.add_theme_font_size_override("font_size", 18)
	watch_again_button.tooltip_text = TooltipText.plain("Watch this turn again",
		"Close the report and play this turn on the board once more: the marches, the battles, the captures and the recruits, exactly as the rules decided them. Watching never changes anything. The report opens again when it ends.")
	watch_again_button.pressed.connect(func(): watch_again_requested.emit())
	head_row.add_child(watch_again_button)

	fog_label = Label.new()
	fog_label.name = "FogLabel"
	fog_label.text = FogView.REPORT_HEADER
	fog_label.visible = false
	fog_label.add_theme_font_size_override("font_size", 16)
	fog_label.add_theme_color_override("font_color", UiPalette.TEXT_SECONDARY)
	fog_label.mouse_filter = Control.MOUSE_FILTER_PASS
	fog_label.tooltip_text = TooltipText.plain("Fog of war", RulesCodex.text("fog_of_war"))
	CodexLink.attach(fog_label, "fog_of_war", codex_requested.emit)
	box.add_child(fog_label)

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
