class_name ChronicleColumn
extends PanelContainer
## UX-6 (design/UX_WAR_TABLE.md §5.1, §5.2): the Chronicle's right-hand column, 420 px wide (360 px below 1600 logical). It lies over the
## board's right edge, in the band the Table reserves for it (TableHud.set_chronicle_open narrows the safe area and moves the opponent
## plaque left), and opens from the system row's Chronicle button or from any medallion of the stack.
##
## Two tabs: READ, built here, and PLAN, which UX-5 fills (set_plan_page); until then the Plan tab is a disabled button that says so. Read
## has, top to bottom:
##   - the summary line: chips such as "1 battle won", "+1 province", "+2 Knights", and the gold ("5 → 23, +18 a turn");
##   - how the list is sorted (importance, place, kind) and one filter chip per kind, a hidden kind still counting ("3 hidden");
##   - the cards (NoticeCard), in a scrolling list, pinned ones from earlier turns first;
##   - the foot: Full report (today's TurnReportPanel, unchanged), Restore (what was dismissed), and when the Chronicle opens by itself.
## The column draws what ChronicleHud hands it (show_state) and says what was pressed with signals; it holds no game facts of its own.

signal close_requested
signal sort_changed(mode: String)
signal kind_toggled(kind: String, hidden: bool)
signal auto_open_changed(mode: String)
signal full_report_requested
signal restore_requested
signal focus_requested(province_id: String, id: String)
signal pin_toggled(id: String)
signal dismiss_requested(id: String)
signal battle_report_requested(event: Dictionary)
signal watch_requested(event: Dictionary)
signal codex_requested(key: String)
signal expand_toggled(id: String)

var title_label: Label
var read_tab: Button
var plan_tab: Button
var close_button: Button
var read_page: VBoxContainer
var plan_page: Control = null
var plan_holder: VBoxContainer
var summary_box: HFlowContainer
var gold_label: Label
var sort_buttons := {}  # mode -> Button
var chips := {}  # kind -> Button
var hidden_label: Label
var empty_label: Label
var scroll: ScrollContainer
var cards_box: VBoxContainer
var full_report_button: Button
var restore_button: Button
var auto_option: OptionButton
var cards: Array[NoticeCard] = []
var _building := false


func _init() -> void:
	name = "ChronicleColumn"
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	grow_horizontal = Control.GROW_DIRECTION_BEGIN  # never out of the window: a too-wide line grows the column leftward
	add_theme_stylebox_override("panel", _style())
	_build()


func _style() -> StyleBoxFlat:
	var style := TableHud.plaque_style(12, 10)
	style.bg_color = Color(UiPalette.PANEL_BG, 0.98)
	style.border_width_right = 0
	style.set_corner_radius_all(0)
	style.corner_radius_top_left = 8
	style.corner_radius_bottom_left = 8
	return style


func _build() -> void:
	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	# The header: the title, the two tabs, close.
	var head := HBoxContainer.new()
	head.name = "Head"
	head.add_theme_constant_override("separation", 6)
	box.add_child(head)
	title_label = Label.new()
	title_label.name = "Title"
	title_label.text = "Chronicle"
	title_label.add_theme_font_override("font", UiFonts.title())
	title_label.add_theme_font_size_override("font_size", UiPalette.TYPE_NAME + 2)
	title_label.add_theme_color_override("font_color", UiPalette.GILT)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.tooltip_text = TooltipText.plain("The Chronicle", "The announcements of each turn, like the start-of-turn notices of Dominions and Total War: sort them, hide the kinds you don't need, pin the ones to keep and dismiss the rest.")
	title_label.mouse_filter = Control.MOUSE_FILTER_PASS
	head.add_child(title_label)
	read_tab = _tab("ReadTab", "Read", true)
	read_tab.tooltip_text = TooltipText.plain("Read", "What happened: the announcements of the turn that just resolved.")
	read_tab.pressed.connect(func(): show_tab("read"))
	head.add_child(read_tab)
	plan_tab = _tab("PlanTab", "Plan", false)
	plan_tab.disabled = true
	plan_tab.tooltip_text = TooltipText.plain("Plan", "Your orders as sentences, with their forecasts, and the seal. It arrives in a later update.")
	plan_tab.pressed.connect(func(): show_tab("plan"))
	head.add_child(plan_tab)
	close_button = Button.new()
	close_button.name = "CloseButton"
	close_button.icon = UiIcons.icon("dismiss", 18)
	close_button.expand_icon = false
	close_button.flat = true
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.custom_minimum_size = Vector2(34, 34)
	close_button.add_theme_color_override("icon_normal_color", UiPalette.TEXT_SECONDARY)
	close_button.add_theme_color_override("icon_hover_color", UiPalette.GILT)
	close_button.tooltip_text = TooltipText.plain("Close the Chronicle", "Esc closes it too. The medallions stay on the left edge.")
	close_button.pressed.connect(close_requested.emit)
	head.add_child(close_button)
	# Read.
	read_page = VBoxContainer.new()
	read_page.name = "ReadPage"
	read_page.add_theme_constant_override("separation", 7)
	read_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(read_page)
	summary_box = HFlowContainer.new()
	summary_box.name = "Summary"
	summary_box.add_theme_constant_override("h_separation", 6)
	summary_box.add_theme_constant_override("v_separation", 4)
	read_page.add_child(summary_box)
	gold_label = Label.new()
	gold_label.name = "Gold"
	gold_label.add_theme_font_override("font", UiFonts.number())
	gold_label.add_theme_font_size_override("font_size", UiPalette.TYPE_SMALL)
	gold_label.add_theme_color_override("font_color", UiPalette.GILT)
	gold_label.mouse_filter = Control.MOUSE_FILTER_PASS
	read_page.add_child(gold_label)
	read_page.add_child(_controls())
	empty_label = Label.new()
	empty_label.name = "Empty"
	empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	empty_label.add_theme_font_size_override("font_size", UiPalette.TYPE_SMALL)
	empty_label.add_theme_color_override("font_color", UiPalette.TEXT_SECONDARY)
	read_page.add_child(empty_label)
	scroll = ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	read_page.add_child(scroll)
	cards_box = VBoxContainer.new()
	cards_box.name = "Cards"
	cards_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards_box.add_theme_constant_override("separation", 7)
	scroll.add_child(cards_box)
	read_page.add_child(_foot())
	# Plan (UX-5's page goes here).
	plan_holder = VBoxContainer.new()
	plan_holder.name = "PlanPage"
	plan_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	plan_holder.visible = false
	box.add_child(plan_holder)


func _tab(node_name: String, text: String, on: bool) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.toggle_mode = true
	b.button_pressed = on
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", UiPalette.TYPE_SMALL + 1)
	return b


## The sort buttons and the filter chips.
func _controls() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.name = "Controls"
	v.add_theme_constant_override("separation", 5)
	var sort_row := HBoxContainer.new()
	sort_row.name = "SortRow"
	sort_row.add_theme_constant_override("separation", 4)
	v.add_child(sort_row)
	var label := Label.new()
	label.text = "Sort"
	label.add_theme_font_size_override("font_size", UiPalette.TYPE_SMALL)
	label.add_theme_color_override("font_color", UiPalette.TEXT_SECONDARY)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sort_row.add_child(label)
	var group := ButtonGroup.new()
	for mode in ChronicleModel.SORTS:
		var b := Button.new()
		b.name = "Sort_%s" % mode
		b.text = String(ChronicleModel.SORT_NAMES[mode])
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", UiPalette.TYPE_SMALL)
		b.tooltip_text = TooltipText.plain("Sort by %s" % String(ChronicleModel.SORT_NAMES[mode]).to_lower(), {
			"importance": "Needs you first, then the battles you fought, an army lost, your land, rivals' land you saw, rulers, magic, your realm, and what you saw abroad.",
			"place": "By the province each announcement happened in, A to Z.",
			"kind": "Grouped by kind: needs you, battles, land, rulers, magic, realm, seen abroad."}[mode])
		b.pressed.connect(func(): sort_changed.emit(mode))
		sort_row.add_child(b)
		sort_buttons[mode] = b
	var chip_row := HFlowContainer.new()
	chip_row.name = "ChipRow"
	chip_row.add_theme_constant_override("h_separation", 4)
	chip_row.add_theme_constant_override("v_separation", 4)
	v.add_child(chip_row)
	for kind in ChronicleModel.KINDS:
		var chip := Button.new()
		chip.name = "Chip_%s" % kind
		chip.toggle_mode = true
		chip.button_pressed = true
		chip.icon = NoticeArt.icon(String(ChronicleModel.KIND_ICONS[kind]), 18)
		chip.expand_icon = false
		chip.focus_mode = Control.FOCUS_NONE
		chip.custom_minimum_size = Vector2(46, 30)
		chip.add_theme_font_size_override("font_size", UiPalette.TYPE_SMALL)
		chip.add_theme_color_override("icon_normal_color", UiPalette.TEXT_PRIMARY)
		chip.add_theme_color_override("icon_pressed_color", UiPalette.GILT)
		chip.add_theme_color_override("icon_hover_color", UiPalette.GILT)
		chip.add_theme_color_override("icon_hover_pressed_color", UiPalette.GILT)
		chip.toggled.connect(func(shown: bool):
			if not _building:
				kind_toggled.emit(kind, not shown))
		chip_row.add_child(chip)
		chips[kind] = chip
	hidden_label = Label.new()
	hidden_label.name = "HiddenCount"
	hidden_label.add_theme_font_size_override("font_size", UiPalette.TYPE_SMALL)
	hidden_label.add_theme_color_override("font_color", UiPalette.TEXT_SECONDARY)
	hidden_label.mouse_filter = Control.MOUSE_FILTER_PASS
	hidden_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip_row.add_child(hidden_label)
	return v


func _foot() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.name = "Foot"
	v.add_theme_constant_override("separation", 5)
	v.add_child(HSeparator.new())
	var row := HFlowContainer.new()
	row.name = "FootRow"
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 4)
	v.add_child(row)
	full_report_button = Button.new()
	full_report_button.name = "FullReportButton"
	full_report_button.text = "Full report"
	full_report_button.focus_mode = Control.FOCUS_NONE
	full_report_button.add_theme_font_size_override("font_size", UiPalette.TYPE_SMALL + 1)
	full_report_button.add_theme_color_override("font_color", UiPalette.GILT)
	full_report_button.tooltip_text = TooltipText.plain("Full report", "Every line of last turn's report, in the order the turn resolved, with the computer's thoughts: today's Turn report, unchanged.")
	full_report_button.pressed.connect(full_report_requested.emit)
	row.add_child(full_report_button)
	restore_button = Button.new()
	restore_button.name = "RestoreButton"
	restore_button.flat = true
	restore_button.focus_mode = Control.FOCUS_NONE
	restore_button.add_theme_font_size_override("font_size", UiPalette.TYPE_SMALL)
	restore_button.tooltip_text = TooltipText.plain("Restore", "Bring back the announcements you dismissed this turn.")
	restore_button.pressed.connect(restore_requested.emit)
	row.add_child(restore_button)
	var opens := Label.new()
	opens.text = "Opens"
	opens.add_theme_font_size_override("font_size", UiPalette.TYPE_SMALL)
	opens.add_theme_color_override("font_color", UiPalette.TEXT_SECONDARY)
	opens.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(opens)
	auto_option = OptionButton.new()
	auto_option.name = "AutoOpen"
	auto_option.focus_mode = Control.FOCUS_NONE
	auto_option.add_theme_font_size_override("font_size", UiPalette.TYPE_SMALL)
	auto_option.fit_to_longest_item = false
	for mode in ChronicleModel.AUTO_OPEN:
		auto_option.add_item(String(ChronicleModel.AUTO_OPEN_NAMES[mode]))
		auto_option.set_item_tooltip(auto_option.item_count - 1, TooltipText.wrap_text(String(ChronicleModel.AUTO_OPEN_HELP[mode])))
	auto_option.item_selected.connect(func(i: int):
		if not _building:
			auto_open_changed.emit(String(ChronicleModel.AUTO_OPEN[i])))
	row.add_child(auto_option)
	return v


# --- showing --------------------------------------------------------------------------------------

## Fills the column. `state`: "cards" [{"item", "opts"}] in display order, "summary" (ChronicleModel.summary), "sort", "hidden" (kinds),
## "counts" {kind: n of announcements of it}, "hidden_count", "dismissed_count", "auto_open", "empty" (what to say with no cards).
func show_state(state: Dictionary) -> void:
	_building = true
	var keep_scroll := scroll.scroll_vertical
	for c in cards:
		cards_box.remove_child(c)
		c.queue_free()
	cards.clear()
	for c in summary_box.get_children():
		summary_box.remove_child(c)
		c.queue_free()
	var summary: Dictionary = state.get("summary", {})
	for chip in summary.get("chips", []):
		summary_box.add_child(_summary_chip(chip))
	var gold: Dictionary = summary.get("gold", {})
	gold_label.visible = not gold.is_empty()
	gold_label.text = String(gold.get("text", ""))
	gold_label.tooltip_text = TooltipText.plain("Gold", String(gold.get("tip", "")))
	var mode := String(state.get("sort", "importance"))
	for m in sort_buttons:
		(sort_buttons[m] as Button).button_pressed = m == mode
	var hidden: Array = state.get("hidden", [])
	var counts: Dictionary = state.get("counts", {})
	for kind in chips:
		var chip: Button = chips[kind]
		var n := int(counts.get(kind, 0))
		chip.button_pressed = not hidden.has(kind)
		chip.text = str(n) if n > 0 else ""
		chip.modulate = Color(1, 1, 1, 0.5) if hidden.has(kind) else (Color.WHITE if n > 0 else Color(1, 1, 1, 0.7))
		chip.tooltip_text = TooltipText.plain("%s (%d)" % [ChronicleModel.KIND_NAMES[kind], n],
			"%s %s" % [ChronicleModel.KIND_HELP[kind], "Click to show them." if hidden.has(kind) else "Click to hide them."])
	var hidden_count := int(state.get("hidden_count", 0))
	hidden_label.visible = hidden_count > 0
	hidden_label.text = "%d hidden" % hidden_count
	hidden_label.tooltip_text = TooltipText.plain("%d hidden" % hidden_count, "%s hidden by the kinds you switched off. They still count here; click a dimmed kind to show it again." % TooltipText.count(hidden_count, "announcement"))
	for entry in state.get("cards", []):
		var card := NoticeCard.new()
		card.setup(entry.item, entry.opts)
		card.focus_requested.connect(focus_requested.emit)
		card.pin_toggled.connect(pin_toggled.emit)
		card.dismiss_requested.connect(dismiss_requested.emit)
		card.battle_report_requested.connect(battle_report_requested.emit)
		card.watch_requested.connect(watch_requested.emit)
		card.codex_requested.connect(codex_requested.emit)
		card.expand_toggled.connect(expand_toggled.emit)
		cards_box.add_child(card)
		cards.append(card)
	empty_label.visible = cards.is_empty()
	empty_label.text = String(state.get("empty", "Nothing to announce yet. The news of each turn arrives here when it starts."))
	var dismissed := int(state.get("dismissed_count", 0))
	restore_button.visible = dismissed > 0
	restore_button.text = "Restore (%d)" % dismissed
	var at := ChronicleModel.AUTO_OPEN.find(String(state.get("auto_open", "important")))
	auto_option.select(maxi(at, 0))
	auto_option.tooltip_text = TooltipText.plain("When the Chronicle opens by itself", String(ChronicleModel.AUTO_OPEN_HELP.get(String(state.get("auto_open", "important")), "")))
	_building = false
	scroll.set_deferred("scroll_vertical", keep_scroll)


func _summary_chip(chip: Dictionary) -> Control:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	p.tooltip_text = TooltipText.plain(String(chip.text), String(chip.get("tip", "")))
	var style := StyleBoxFlat.new()
	style.bg_color = UiPalette.PANEL_RAISED
	var tone := String(chip.get("tone", ""))
	style.border_color = NoticeArt.ring(tone) if tone != "" else UiPalette.PANEL_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", style)
	var l := Label.new()
	l.text = String(chip.text)
	l.add_theme_font_size_override("font_size", UiPalette.TYPE_SMALL)
	l.add_theme_color_override("font_color", UiPalette.TEXT_PRIMARY)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	return p


## The card for an announcement id, or null.
func card(id: String) -> NoticeCard:
	for c in cards:
		if String(c.item.id) == id:
			return c
	return null


## Scrolls the list to a card and flashes it (once the cards have their sizes: a frame after they were built).
func reveal(id: String) -> void:
	var c := card(id)
	if c == null:
		return
	c.flash()
	if is_inside_tree():
		_scroll_to(id)


func _scroll_to(id: String) -> void:
	await get_tree().process_frame
	var c := card(id)
	if c == null or not c.is_inside_tree():
		return
	# The least scrolling that shows the whole card: the cards above it (a need, say) stay in view when they fit.
	var top := int(c.position.y)
	var bottom := top + int(c.size.y)
	if top < scroll.scroll_vertical:
		scroll.scroll_vertical = maxi(top - 4, 0)
	elif bottom > scroll.scroll_vertical + int(scroll.size.y):
		scroll.scroll_vertical = bottom - int(scroll.size.y) + 4


# --- tabs -----------------------------------------------------------------------------------------

## UX-5 puts its Plan page here: the tab is enabled and shows it.
func set_plan_page(page: Control) -> void:
	if plan_page != null and plan_page.get_parent() == plan_holder:
		plan_holder.remove_child(plan_page)
	plan_page = page
	plan_tab.disabled = page == null
	if page != null:
		plan_holder.add_child(page)
	else:
		show_tab("read")


func show_tab(tab: String) -> void:
	var plan := tab == "plan" and plan_page != null
	read_page.visible = not plan
	plan_holder.visible = plan
	read_tab.button_pressed = not plan
	plan_tab.button_pressed = plan


func current_tab() -> String:
	return "plan" if plan_holder.visible else "read"
