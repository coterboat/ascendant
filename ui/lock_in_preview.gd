class_name LockInPreview
extends Control
## The lock-in preview (M4-4, #69; design/M4_ASCENSION.md §5): everything a side of the fork brings, before
## you swear its Oath. One dialog: the question, when it is done, what you gain (gilt) beside what you lose
## access to (greyed), your units before → after (was/now, as on the build screen) with the units on the map
## that change, income per turn before → after, how the units will look (PathPortrait placeholders until the
## portraits land), and Swear the Oath / Back. Nothing is queued until Swear the Oath; the order can still be
## cancelled like any order until End turn. After the Oath, a transformation's card opens the same dialog
## with the "you gain" column and "Research <transformation>".
## Every number comes from PathView.preview, which is AscensionRules.with_nodes on a copy of the state, so the
## preview is the result (tests/test_research_panel.gd plays it out and compares). Every number has its
## breakdown in the tooltip (meta "breakdown"), and every line links its codex entry.

signal confirmed(node_id: String)
signal closed
signal codex_requested(key: String)

const PANEL_SIZE := Vector2(1540, 860)
const PORTRAIT := Vector2(96, 128)

var data := {}  # PathView.preview
var title_label: Label
var when_label: Label
var gain_box: VBoxContainer
var lose_box: VBoxContainer
var lose_heading: Label
var roster: GridContainer
var map_box: VBoxContainer
var economy_label: Label
var look_box: HBoxContainer
var confirm_button: Button
var back_button: Button
var reason_label: Label


func _init() -> void:
	name = "LockInPreview"
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()


## Shows the preview of the side `node_id` is on, for `fid`, with `orders` (the faction's queued orders).
func show_for(state: GameState, fid: String, node_id: String, orders: Array = []) -> void:
	data = PathView.preview(state, fid, node_id, orders)
	_fill(state, fid)
	visible = true


func close() -> void:
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		if is_inside_tree():
			get_viewport().set_input_as_handled()


func _fill(state: GameState, fid: String) -> void:
	for box in [gain_box, lose_box, roster, map_box, look_box]:
		for c in box.get_children():
			box.remove_child(c)
			c.queue_free()
	if not data.get("ok", false):
		title_label.text = String(data.get("reason", ""))
		confirm_button.visible = false
		return
	var gain_mode: bool = data.mode == "oath"
	title_label.text = String(data.header)
	_show_line(when_label, String(data.when), data.when_breakdown, "", "lock_in")
	for line in data.gain:
		_line(gain_box, line, UiPalette.TEXT_PRIMARY)
	var magic := MagicView.lock_in_rows(data, fid)  # M5-8 (§8.5): the greater working it opens, the mastery it adds, the one it closes
	if not magic.gain.is_empty():
		var ml := _line(gain_box, magic.gain, UiPalette.GILT)
		ml.name = "MagicGain"
	lose_heading.text = "You lose access to" if gain_mode else "Already closed"
	for line in data.lose:
		_line(lose_box, line, UiPalette.TEXT_DISABLED)
	if not magic.lose.is_empty():
		_struck_line(lose_box, magic.lose).name = "MagicLose"
	_fill_roster(fid)
	for line in data.map_units:
		_line(map_box, line, UiPalette.TEXT_SECONDARY)
	var econ: Dictionary = data.economy
	_show_line(economy_label, String(econ.text), econ.breakdown, "", "income")
	economy_label.add_theme_color_override("font_color", UiPalette.POSITIVE if int(econ.after) > int(econ.before)
		else (UiPalette.NEGATIVE if int(econ.after) < int(econ.before) else UiPalette.TEXT_PRIMARY))
	_fill_look(fid)
	confirm_button.text = String(data.confirm_text)
	confirm_button.visible = true
	confirm_button.disabled = not data.can_confirm
	confirm_button.tooltip_text = TooltipText.plain(String(data.confirm_text), "%s %s" % [
		"Queues the research order. Nothing is closed until the Oath is done, and you can cancel the order in your orders list until you end the turn." if gain_mode
			else "Queues the research order for the transformation.", RulesCodex.text("lock_in")])
	CodexLink.attach(confirm_button, "lock_in", codex_requested.emit)
	reason_label.text = String(data.reason)
	reason_label.add_theme_color_override("font_color", UiPalette.TEXT_SECONDARY if AscensionRules.check_research(data.before, fid, String(data.target)).is_empty() else UiPalette.NEGATIVE)
	reason_label.visible = not String(data.reason).is_empty()


## The roster table: every unit with hit points, attack, defense, morale and cost, each changed number in
## colour with "was N" under it; the new unit's row marked "new".
func _fill_roster(fid: String) -> void:
	roster.columns = 2 + PathView.STATS.size()
	var corner := _small("Unit", TooltipText.plain("Your units", "Your units once you have transformed, as the board stands now. A coloured number changes; the number under it is what it is now."))
	CodexLink.attach(corner, "units", codex_requested.emit)
	roster.add_child(corner)
	for stat in PathView.STATS:
		var h := _small(String(PathView.STAT_HEADS[stat]), TooltipText.plain(String(PathView.STAT_HEADS[stat]), RulesCodex.text(String(PathView.STAT_CODEX[stat]))))
		CodexLink.attach(h, String(PathView.STAT_CODEX[stat]), codex_requested.emit)
		roster.add_child(h)
	roster.add_child(_small("Trait", TooltipText.plain("Traits", RulesCodex.text("units"))))
	for row in data.units:
		var name_text := String(row.name)
		if not String(row.was_name).is_empty():
			name_text = "%s → %s" % [row.was_name, row.name]
		if row.new:
			name_text = "%s (new)" % row.name
		var nl := Label.new()
		nl.name = "Unit_%s" % String(row.type).validate_node_name()
		nl.text = name_text
		nl.add_theme_font_size_override("font_size", 16)
		nl.add_theme_color_override("font_color", UiPalette.GILT if row.new or not String(row.was_name).is_empty() else UiPalette.TEXT_PRIMARY)
		nl.tooltip_text = TooltipText.plain(name_text, "A new unit, recruited at your capital from the turn after the transformation." if row.new
			else ("Changed by the transformation; every one on the map changes at once." if not String(row.was_name).is_empty() else "Unchanged by this side of the fork, unless a number below says otherwise."))
		nl.mouse_filter = Control.MOUSE_FILTER_PASS
		CodexLink.attach(nl, "transformation" if row.new or not String(row.was_name).is_empty() else "units", codex_requested.emit)
		roster.add_child(nl)
		for stat in PathView.STATS:
			var cell: Dictionary = row.cells[stat]
			var box := VBoxContainer.new()
			box.add_theme_constant_override("separation", -4)
			var v := Label.new()
			v.name = "Value_%s_%s" % [String(row.type).validate_node_name(), stat]
			v.add_theme_font_size_override("font_size", 16)
			_show_line(v, str(int(cell.after)), cell.after_bd, "", String(cell.after_bd.get("codex", PathView.STAT_CODEX[stat])))
			var colour := UiPalette.TEXT_PRIMARY
			if cell.changed:
				colour = UiPalette.POSITIVE if cell.better else UiPalette.NEGATIVE
			elif row.new:
				colour = UiPalette.GILT
			v.add_theme_color_override("font_color", colour)
			box.add_child(v)
			if cell.changed:
				var was := Label.new()
				was.name = "Was_%s_%s" % [String(row.type).validate_node_name(), stat]
				was.add_theme_font_size_override("font_size", 12)
				was.add_theme_color_override("font_color", UiPalette.TEXT_DISABLED)
				_show_line(was, "was %d" % int(cell.before), cell.before_bd, "", String(cell.before_bd.get("codex", "units")))
				box.add_child(was)
			roster.add_child(box)
		var t := Label.new()
		t.text = String(row.trait)
		t.add_theme_font_size_override("font_size", 14)
		t.add_theme_color_override("font_color", UiPalette.TEXT_SECONDARY)
		var key := AutoBattleResolver.codex_id_for_trait(String(row.trait))
		t.tooltip_text = TooltipText.plain(String(row.trait), String(AutoBattleResolver.TRAIT_TEXT.get(String(row.trait), "")))
		t.mouse_filter = Control.MOUSE_FILTER_PASS
		CodexLink.attach(t, key, codex_requested.emit)
		roster.add_child(t)


## How they will look: the changed unit's portrait now → in the fork's frame, and the new unit's card.
func _fill_look(fid: String) -> void:
	var look: Dictionary = data.look
	var colour := String(look.colour)
	var note := "Placeholder until the portraits land: the base portrait inside a frame in the fork's colour with %s." % String(look.glyph)
	if not String(look.changed).is_empty():
		var now := Art.portrait_card(String(look.changed), PORTRAIT, fid)
		look_box.add_child(_captioned(now, "%s now" % String(look.changed_was), TooltipText.plain(String(look.changed_was), "Your %s as they look now." % String(look.changed_was))))
		var arrow := Label.new()
		arrow.text = "→"
		arrow.add_theme_font_size_override("font_size", 34)
		arrow.add_theme_color_override("font_color", UiPalette.GILT)
		arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		look_box.add_child(arrow)
		var after := PathPortrait.make(String(look.changed), fid, colour, PORTRAIT)
		var after_tip := "Your %s as they will look, in the fork's frame." % String(look.changed_name) if after.shows_variant else note
		look_box.add_child(_captioned(after, String(look.changed_name), TooltipText.plain(String(look.changed_name), after_tip)))
	if not String(look.new_unit).is_empty():
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(24, 0)
		look_box.add_child(spacer)
		var card := PathPortrait.make(String(look.new_unit), fid, colour, PORTRAIT)
		var new_tip := "A new unit, in the fork's frame." if card.has_art() else "A new unit. Placeholder until its portrait lands: a card with its initial in the fork's frame."
		look_box.add_child(_captioned(card, "%s (new)" % String(look.new_name), TooltipText.plain(String(look.new_name), new_tip)))


func _captioned(card: Control, caption: String, tip: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "Look_%s" % caption.validate_node_name()
	box.add_theme_constant_override("separation", 4)
	box.tooltip_text = tip
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(card)
	var l := Label.new()
	l.text = caption
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", UiPalette.TEXT_SECONDARY)
	box.add_child(l)
	return box


## A line of the preview: its text, its breakdown (or tooltip) and its codex link.
func _line(parent: Control, line: Dictionary, colour: Color) -> Label:
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", colour)
	_show_line(l, String(line.text), line.get("breakdown", {}), String(line.get("tooltip", "")), String(line.get("codex", "")))
	if line.get("rule", false):
		l.set_meta("rule_text", true)  # a rule in words (its codex entry explains it), not a number to break down
	parent.add_child(l)
	return l


## A line struck through (M5-8: the greater working this side closes, §8.5), as a RichTextLabel: [s]...[/s].
func _struck_line(parent: Control, line: Dictionary) -> RichTextLabel:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("normal_font_size", 15)
	l.add_theme_color_override("default_color", UiPalette.TEXT_DISABLED)
	l.text = "[s]%s[/s]" % String(line.text).replace("[", "[lb]")
	l.set_meta("struck", true)
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	l.tooltip_text = String(line.get("tooltip", ""))
	CodexLink.attach(l, String(line.get("codex", "")), codex_requested.emit)
	parent.add_child(l)
	return l


## Sets a label's text and tooltip: its breakdown (kept in meta "breakdown") or else `tooltip`, then the codex link.
func _show_line(l: Label, text: String, breakdown: Dictionary, tooltip: String, codex: String) -> void:
	l.text = text
	if not breakdown.is_empty():
		l.set_meta("breakdown", breakdown)
		l.tooltip_text = TooltipText.from_breakdown(breakdown)
	else:
		if l.has_meta("breakdown"):
			l.remove_meta("breakdown")
		l.tooltip_text = tooltip
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	CodexLink.attach(l, codex, codex_requested.emit)


func _small(text: String, tip: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", UiPalette.TEXT_SECONDARY)
	l.tooltip_text = tip
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	return l


func _heading(parent: Control, text: String, colour: Color, codex: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 19)
	l.add_theme_color_override("font_color", colour)
	l.tooltip_text = TooltipText.plain(text, RulesCodex.text(codex))
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	CodexLink.attach(l, codex, codex_requested.emit)
	parent.add_child(l)
	return l


func _build() -> void:
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0, 0, 0, 0.6)
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
	var style := UiPalette.panel_style(20)
	style.border_color = UiPalette.GILT
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	title_label = Label.new()
	title_label.name = "Title"
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.add_theme_font_size_override("font_size", 24)
	title_label.add_theme_color_override("font_color", UiPalette.GILT)
	box.add_child(title_label)
	when_label = Label.new()
	when_label.name = "When"
	when_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	when_label.add_theme_font_size_override("font_size", 15)
	when_label.add_theme_color_override("font_color", UiPalette.TEXT_SECONDARY)
	box.add_child(when_label)
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var body := VBoxContainer.new()
	body.name = "Body"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	scroll.add_child(body)
	var cols := HBoxContainer.new()
	cols.name = "Columns"
	cols.add_theme_constant_override("separation", 28)
	body.add_child(cols)
	var gain := VBoxContainer.new()
	gain.name = "Gain"
	gain.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gain.size_flags_stretch_ratio = 1.2
	gain.add_theme_constant_override("separation", 5)
	cols.add_child(gain)
	_heading(gain, "You gain", UiPalette.GILT, "transformation")
	gain_box = VBoxContainer.new()
	gain_box.name = "GainLines"
	gain_box.add_theme_constant_override("separation", 5)
	gain.add_child(gain_box)
	var lose := VBoxContainer.new()
	lose.name = "Lose"
	lose.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lose.add_theme_constant_override("separation", 5)
	cols.add_child(lose)
	lose_heading = _heading(lose, "You lose access to", UiPalette.TEXT_SECONDARY, "fork")
	lose_box = VBoxContainer.new()
	lose_box.name = "LoseLines"
	lose_box.add_theme_constant_override("separation", 5)
	lose.add_child(lose_box)
	body.add_child(HSeparator.new())
	var lower := HBoxContainer.new()
	lower.name = "Lower"
	lower.add_theme_constant_override("separation", 28)
	body.add_child(lower)
	var units := VBoxContainer.new()
	units.name = "Units"
	units.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	units.add_theme_constant_override("separation", 5)
	lower.add_child(units)
	_heading(units, "Your units, before → after", UiPalette.GILT, "units")
	roster = GridContainer.new()
	roster.name = "Roster"
	roster.add_theme_constant_override("h_separation", 18)
	roster.add_theme_constant_override("v_separation", 2)
	units.add_child(roster)
	map_box = VBoxContainer.new()
	map_box.name = "MapUnits"
	units.add_child(map_box)
	economy_label = Label.new()
	economy_label.name = "Economy"
	economy_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	economy_label.add_theme_font_size_override("font_size", 15)
	units.add_child(economy_label)
	var look := VBoxContainer.new()
	look.name = "LookColumn"
	look.add_theme_constant_override("separation", 5)
	lower.add_child(look)
	_heading(look, "How they will look", UiPalette.GILT, "transformation")
	look_box = HBoxContainer.new()
	look_box.name = "Look"
	look_box.add_theme_constant_override("separation", 10)
	look.add_child(look_box)
	var row := HBoxContainer.new()
	row.name = "Buttons"
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	reason_label = Label.new()
	reason_label.name = "Reason"
	reason_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reason_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reason_label.add_theme_font_size_override("font_size", 15)
	reason_label.add_theme_color_override("font_color", UiPalette.NEGATIVE)
	row.add_child(reason_label)
	back_button = Button.new()
	back_button.name = "BackButton"
	back_button.text = "Back"
	back_button.custom_minimum_size = Vector2(150, 44)
	back_button.focus_mode = Control.FOCUS_NONE
	back_button.add_theme_font_size_override("font_size", 18)
	back_button.tooltip_text = "Back to the research panel. Nothing is queued."
	back_button.pressed.connect(close)
	row.add_child(back_button)
	confirm_button = Button.new()
	confirm_button.name = "ConfirmButton"
	confirm_button.text = "Swear the Oath"
	confirm_button.custom_minimum_size = Vector2(220, 44)
	confirm_button.focus_mode = Control.FOCUS_NONE
	confirm_button.add_theme_font_size_override("font_size", 18)
	confirm_button.add_theme_color_override("font_color", UiPalette.GILT)
	confirm_button.pressed.connect(func():
		if data.get("ok", false) and data.get("can_confirm", false):
			confirmed.emit(String(data.target)))
	row.add_child(confirm_button)
