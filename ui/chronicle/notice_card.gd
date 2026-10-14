class_name NoticeCard
extends PanelContainer
## UX-6 (design/UX_WAR_TABLE.md §5.2, "A card"): one announcement in the Chronicle's Read list. It has
##   - its medallion (the kind icon on a coloured disc until UX-ART's art lands), and a number when it has a marker on the board;
##   - the headline, and the detail in up to two lines, which a click expands to the full report lines it came from (source_rows);
##   - the place, a chip that focuses the board on it (the same number is the marker's);
##   - Watch and Battle report on a battle you fought;
##   - the "?" that opens its codex entry, Pin and Dismiss.
## It only shows the announcement it was given (ChronicleModel's output, or a pinned card's payload as it was shown) and says what was
## pressed with signals; the Chronicle does the rest.

signal focus_requested(province_id: String, id: String)
signal pin_toggled(id: String)
signal dismiss_requested(id: String)
signal battle_report_requested(event: Dictionary)
signal watch_requested(event: Dictionary)
signal codex_requested(key: String)
signal expand_toggled(id: String)

var item: Dictionary = {}
var number := 0
var pinned := false
var unread := false
var expanded := false
var watch_why := ""  # why Watch is off ("" when it can be played back)
var medallion: NoticeMedallion
var badge: NumberBadge
var headline_label: Label
var detail_label: Label
var rows_box: VBoxContainer
var place_button: Button
var watch_button: Button
var battle_button: Button
var codex_button: Button
var pin_button: Button
var dismiss_button: Button
var details_button: Button
var _flash: Tween = null


## Builds the card for `it`. `opts`: "number" (its marker's number, 0 for none), "pinned", "unread", "expanded", "watch_why".
func setup(it: Dictionary, opts: Dictionary = {}) -> void:
	item = it
	number = int(opts.get("number", 0))
	pinned = bool(opts.get("pinned", false))
	unread = bool(opts.get("unread", false))
	expanded = bool(opts.get("expanded", false))
	watch_why = String(opts.get("watch_why", ""))
	name = "Card_%s" % String(it.id).validate_node_name()
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func _build() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	add_theme_stylebox_override("panel", _style(false))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	add_child(box)
	# The head: medallion (and its number), the headline over "turn · kind", pin and dismiss.
	var head := HBoxContainer.new()
	head.name = "Head"
	head.add_theme_constant_override("separation", 8)
	box.add_child(head)
	var image := Control.new()
	image.custom_minimum_size = Vector2(NoticeMedallion.SIZE_CARD + 6, NoticeMedallion.SIZE_CARD)
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(image)
	medallion = NoticeMedallion.new(item, NoticeMedallion.SIZE_CARD, false)
	medallion.set_flags(unread, pinned)
	image.add_child(medallion)
	badge = NumberBadge.new(number, 20.0)
	badge.name = "NumberBadge"
	badge.position = Vector2(NoticeMedallion.SIZE_CARD - 12.0, -4.0)
	badge.visible = number > 0
	badge.tooltip_text = ""
	image.add_child(badge)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(titles)
	var spell_icon := SpellIcons.rect(String(item.get("spell", "")), 30)  # UI-ICONS (#233): a card about a spell wears its icon
	if spell_icon != null:
		head.add_child(spell_icon)
	headline_label = Label.new()
	headline_label.name = "Headline"
	headline_label.text = String(item.headline)
	headline_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	headline_label.add_theme_font_override("font", UiFonts.name())
	headline_label.add_theme_font_size_override("font_size", UiPalette.TYPE_BODY + 1)
	headline_label.add_theme_color_override("font_color", UiPalette.GILT if unread else UiPalette.TEXT_PRIMARY)
	headline_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	titles.add_child(headline_label)
	var meta := Label.new()
	meta.name = "Meta"
	meta.text = "%s · turn %d" % [ChronicleModel.KIND_NAMES.get(String(item.kind), ""), int(item.turn)]
	meta.add_theme_font_size_override("font_size", UiPalette.TYPE_SMALL)
	meta.add_theme_color_override("font_color", UiPalette.TEXT_DISABLED)
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	titles.add_child(meta)
	pin_button = _icon_button("PinButton", "pin")
	pin_button.toggle_mode = true
	pin_button.button_pressed = pinned
	pin_button.tooltip_text = TooltipText.plain("Unpin" if pinned else "Pin",
		"Unpin this card: it goes at the next turn." if pinned else "Keep this card in the Chronicle on the turns to come, exactly as it reads now.")
	pin_button.toggled.connect(func(_on: bool): pin_toggled.emit(String(item.id)))
	head.add_child(pin_button)
	dismiss_button = _icon_button("DismissButton", "dismiss")
	dismiss_button.tooltip_text = TooltipText.plain("Dismiss", "Remove this announcement and its medallion and marker. The Chronicle's Restore button brings dismissed ones back.")
	dismiss_button.pressed.connect(func(): dismiss_requested.emit(String(item.id)))
	head.add_child(dismiss_button)
	# The detail: two lines, or all the lines of the report it came from.
	detail_label = Label.new()
	detail_label.name = "Detail"
	detail_label.text = String(item.detail)
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_label.max_lines_visible = -1 if expanded else 2  # (no trimming mode: with one, a wrapping label's minimum height collapses to a line's hair)
	detail_label.add_theme_font_size_override("font_size", UiPalette.TYPE_SMALL)
	detail_label.add_theme_color_override("font_color", UiPalette.TEXT_SECONDARY)
	detail_label.mouse_filter = Control.MOUSE_FILTER_STOP
	detail_label.tooltip_text = TooltipText.plain("The whole report line", "Click to read the lines of the turn report this came from, or to fold them away.")
	detail_label.gui_input.connect(func(event: InputEvent):
		var b := event as InputEventMouseButton
		if b != null and b.pressed and b.button_index == MOUSE_BUTTON_LEFT:
			toggle_expanded())
	box.add_child(detail_label)
	rows_box = VBoxContainer.new()
	rows_box.name = "SourceRows"
	rows_box.add_theme_constant_override("separation", 3)
	rows_box.visible = expanded
	for row in item.source_rows:
		var l := Label.new()
		l.text = String(row)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_font_size_override("font_size", UiPalette.TYPE_SMALL)
		l.add_theme_color_override("font_color", UiPalette.TEXT_PRIMARY)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rows_box.add_child(l)
	box.add_child(rows_box)
	# The actions.
	var actions := HFlowContainer.new()
	actions.name = "Actions"
	actions.add_theme_constant_override("h_separation", 6)
	actions.add_theme_constant_override("v_separation", 4)
	box.add_child(actions)
	if not String(item.province).is_empty():
		place_button = Button.new()
		place_button.name = "PlaceButton"
		place_button.text = String(item.place)
		place_button.icon = UiIcons.icon("sight", 16)
		place_button.expand_icon = false
		place_button.focus_mode = Control.FOCUS_NONE
		place_button.add_theme_font_size_override("font_size", UiPalette.TYPE_SMALL)
		place_button.add_theme_color_override("icon_normal_color", UiPalette.GILT)
		place_button.tooltip_text = TooltipText.plain("Show %s" % String(item.place),
			"Select %s and glide the board to it. %s" % [String(item.place), "The numbered marker there is this card's (%d)." % number if number > 0 else ""])
		place_button.pressed.connect(func(): focus_requested.emit(String(item.province), String(item.id)))
		actions.add_child(place_button)
	if not (item.battle as Dictionary).is_empty():
		watch_button = Button.new()
		watch_button.name = "WatchButton"
		watch_button.text = "Watch"
		watch_button.focus_mode = Control.FOCUS_NONE
		watch_button.add_theme_font_size_override("font_size", UiPalette.TYPE_SMALL)
		watch_button.disabled = not watch_why.is_empty()
		watch_button.tooltip_text = TooltipText.plain("Watch this battle",
			"Play this battle back. The playback shows exactly what the report describes, and watching never changes anything.") \
			if watch_why.is_empty() else TooltipText.plain("Can't watch this battle", watch_why)
		watch_button.pressed.connect(func(): watch_requested.emit((item.battle as Dictionary).duplicate(true)))
		actions.add_child(watch_button)
		battle_button = Button.new()
		battle_button.name = "BattleReportButton"
		battle_button.text = "Battle report"
		battle_button.focus_mode = Control.FOCUS_NONE
		battle_button.add_theme_font_size_override("font_size", UiPalette.TYPE_SMALL)
		battle_button.tooltip_text = "Open the full report for this battle: who fought, the odds, and the losses."
		battle_button.pressed.connect(func(): battle_report_requested.emit((item.battle as Dictionary).duplicate(true)))
		actions.add_child(battle_button)
	if item.source_rows.size() > 1 or String(item.source_rows[0]) != String(item.detail):
		details_button = Button.new()
		details_button.name = "DetailsButton"
		details_button.text = "Less" if expanded else "Details"
		details_button.flat = true
		details_button.focus_mode = Control.FOCUS_NONE
		details_button.add_theme_font_size_override("font_size", UiPalette.TYPE_SMALL)
		details_button.tooltip_text = detail_label.tooltip_text
		details_button.pressed.connect(toggle_expanded)
		actions.add_child(details_button)
	var key := String(item.codex)
	if RulesCodex.ENTRIES.has(key):
		codex_button = Button.new()
		codex_button.name = "CodexButton"
		codex_button.text = "?"
		codex_button.custom_minimum_size = Vector2(30, 28)
		codex_button.focus_mode = Control.FOCUS_NONE
		codex_button.add_theme_font_size_override("font_size", UiPalette.TYPE_SMALL)
		codex_button.tooltip_text = "Explain this: opens the codex entry \"%s\"." % String(RulesCodex.entry(key).get("title", ""))
		codex_button.set_meta("codex_key", key)
		codex_button.pressed.connect(func(): codex_requested.emit(key))
		actions.add_child(codex_button)


func toggle_expanded() -> void:
	expanded = not expanded
	detail_label.max_lines_visible = -1 if expanded else 2
	rows_box.visible = expanded
	if details_button != null:
		details_button.text = "Less" if expanded else "Details"
	expand_toggled.emit(String(item.id))


## A short gilt flash of the card's border: the medallion that was clicked opened here.
func flash() -> void:
	if _flash != null:
		_flash.kill()
	add_theme_stylebox_override("panel", _style(true))
	if not is_inside_tree():
		return
	_flash = create_tween()
	_flash.tween_interval(1.2)
	_flash.tween_callback(func(): add_theme_stylebox_override("panel", _style(false)))


func _style(highlight: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UiPalette.PANEL_RAISED
	style.border_color = UiPalette.GILT if highlight else NoticeArt.disc(String(item.get("kind", ""))).lightened(0.25)
	style.set_border_width_all(2 if highlight else 1)
	style.border_width_left = 5
	style.set_corner_radius_all(6)
	style.content_margin_left = 10
	style.content_margin_right = 8
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	return style


func _icon_button(node_name: String, icon_name: String) -> Button:
	var b := Button.new()
	b.name = node_name
	b.icon = UiIcons.icon(icon_name, 18)
	b.expand_icon = false
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(32, 32)
	b.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	b.add_theme_color_override("icon_normal_color", UiPalette.TEXT_SECONDARY)
	b.add_theme_color_override("icon_hover_color", UiPalette.GILT)
	b.add_theme_color_override("icon_pressed_color", UiPalette.GILT)
	b.add_theme_color_override("icon_hover_pressed_color", UiPalette.GILT)
	return b
