class_name ResearchPanel
extends Control
## The research panel (M4-4, #69; design/M4_ASCENSION.md §9.1): your faction's path as a tree in four
## columns (tier I, tier II, the Oaths, the transformations; the two sides of the fork stacked on the right,
## with lines for prerequisites). Each node card shows its state (researched, researching, available, needs,
## closed) with the plain reason, its cost and ETA "if researched next", and its effect, with a breakdown
## behind every number and a codex link on every line. "Research this" asks the host to queue a ResearchOrder
## (research_requested; GameScreen's ResearchHud queues it through GameSession.queue_research); an Oath's
## button opens the lock-in preview first (preview_requested), and nothing is queued until you swear.
## The sidebar: research per turn with its breakdown, research saved, the target with its progress and
## forecast, and each open side's road to its transformation.
## The enemy's path is a second tab, read-only and public only (§3.3): their researched nodes with turns,
## the side they swore and what it closed, and their research per turn. Never their target, so neither
## "researching" nor "available" nor an ETA is shown for them (tests check the screen is the same whatever
## their target is). Reads the state and the orders; never changes them. All words come from PathView.
## M5-2 fog of war (#113, design/M5_MAGIC_FOG.md §2.2, §2.6): in a fog game `state` is the viewer's view, so the enemy
## tab shows only what the viewer has learned of their path (the Oath and transformation, heralded to everyone, and the
## nodes seen at work in battle) and says they may have more; their research per turn counts only those nodes.

signal research_requested(node_id: String)
signal preview_requested(node_id: String)
signal closed
signal codex_requested(key: String)

const PANEL_SIZE := Vector2(1560, 850)
const SIDEBAR_WIDTH := 390.0
const STATE_COLOURS := {
	"researched": UiPalette.POSITIVE,
	"researching": UiPalette.GILT,
	"available": UiPalette.LINK,
	"needs": UiPalette.TEXT_SECONDARY,
	"closed": UiPalette.TEXT_DISABLED,
	"unresearched": UiPalette.TEXT_SECONDARY,
}

var state: GameState = null
var viewer_fid := ""  # the faction at the controls
var showing_fid := ""  # whose path is shown: the viewer's, or the enemy's (read-only)
var orders: Array = []  # the viewer's queued orders this turn
var can_order := false  # the viewer is giving orders now
var status_text := ""
var title_label: Label
var people_label: Label
var own_tab: Button
var enemy_tabs: HBoxContainer
var close_button: Button
var tree_box: HBoxContainer
var links: Control
var sidebar: VBoxContainer
var status_label: Label
var footer_label: Label
var cards := {}  # node id -> the card's PanelContainer (for tests and the links layer)
var buttons := {}  # node id -> its action button


func _init() -> void:
	name = "ResearchPanel"
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()


## Shows the viewer's own path. `p_orders` are its queued orders; `p_can_order` is whether it can give
## orders now (its own turn).
func show_for(p_state: GameState, p_viewer: String, p_orders: Array = [], p_can_order: bool = true) -> void:
	state = p_state
	viewer_fid = p_viewer
	orders = p_orders.duplicate()
	can_order = p_can_order
	showing_fid = p_viewer
	status_text = ""
	refresh()
	visible = true


## The enemy's path, read-only (public facts only).
func show_enemy(fid: String) -> void:
	showing_fid = fid
	refresh()


func show_own() -> void:
	showing_fid = viewer_fid
	refresh()


## New orders (after one was queued or cancelled) without leaving the tab.
func set_orders(p_orders: Array, p_status: String = "") -> void:
	orders = p_orders.duplicate()
	status_text = p_status
	refresh()


func is_own() -> bool:
	return showing_fid == viewer_fid


func close() -> void:
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		if is_inside_tree():
			get_viewport().set_input_as_handled()


## Rebuilds the tree, the sidebar and the tabs.
func refresh() -> void:
	cards.clear()
	buttons.clear()
	for box in [tree_box, sidebar, enemy_tabs]:
		for c in box.get_children():
			box.remove_child(c)
			c.queue_free()
	if state == null or state.find_faction(showing_fid) == null:
		return
	var own := is_own()
	var f := state.find_faction(showing_fid)
	var path := AscensionRules.path_name(showing_fid)
	title_label.text = "Research: %s" % path.capitalize() if own else "Enemy path: %s, %s (read-only)" % [f.faction_name, path.capitalize()]
	if not own and FogView.active(state):
		title_label.text = "Enemy path: %s, %s (what you know)" % [f.faction_name, path.capitalize()]
	title_label.tooltip_text = TooltipText.plain(title_label.text, RulesCodex.text(String(AscensionRules.path_data(showing_fid).get("codex", "path"))))
	CodexLink.attach(title_label, String(AscensionRules.path_data(showing_fid).get("codex", "path")), codex_requested.emit)
	var people := AscensionRules.people_name(state, showing_fid)
	people_label.text = "%s · %s" % [f.faction_name, people] if not people.is_empty() else f.faction_name
	people_label.tooltip_text = TooltipText.plain(people_label.text, AscensionRules.province_rule_sentence(state, showing_fid, own) if not people.is_empty()
		else "Not transformed yet. %s" % RulesCodex.text("transformation"))
	CodexLink.attach(people_label, "transformation", codex_requested.emit)
	own_tab.button_pressed = own
	own_tab.text = "Your path"
	for other in state.factions:
		if other.id == viewer_fid:
			continue
		var tab := Button.new()
		tab.name = "EnemyTab_%s" % other.id.validate_node_name()
		tab.text = "Enemy path: %s" % other.faction_name
		tab.toggle_mode = true
		tab.button_pressed = showing_fid == other.id
		tab.focus_mode = Control.FOCUS_NONE
		tab.add_theme_font_size_override("font_size", 16)
		tab.tooltip_text = TooltipText.plain("The %s's path" % other.faction_name, "What they have researched, the Oath they swore and their research per turn are public. What they are researching is not.")
		if FogView.active(state):
			tab.tooltip_text = TooltipText.plain("The %s's path" % other.faction_name, "Under fog of war you see only what you have learned of it: the Oath they swore and their transformation, which everyone hears of, and the nodes you saw at work in a battle you fought. What they are researching is never shown.")
		CodexLink.attach(tab, "path", codex_requested.emit)
		tab.pressed.connect(show_enemy.bind(other.id))
		enemy_tabs.add_child(tab)
	for col in PathView.columns(state, showing_fid, orders if own else [], own):
		tree_box.add_child(_column(col, own))
	status_label.text = status_text
	status_label.visible = own and not status_text.is_empty()
	_fill_sidebar(own)
	footer_label.text = "Your research target is yours alone: the enemy sees what you have researched and the Oath you swore, never what you are researching. Hover a number for where it comes from; right-click it, or press F1, for its codex entry." if own \
		else "Read-only. Everything here is public: what they researched and when, the Oath they swore and their research per turn. What they are researching now is their secret, as yours is to them."
	if FogView.active(state):  # M5-2
		footer_label.text = "Under fog of war the enemy learns of your path only what they see: your Oath and transformation, and the nodes at work in battles they fight. Hover a number for where it comes from; right-click it, or press F1, for its codex entry." if own \
			else "Read-only, and only what you know: the Oath they swore and their transformation, which everyone hears of, and the nodes you saw at work in battles you fought. They may have more. Their research per turn counts only those, from the land they hold."
	links.queue_redraw()


func _column(col: Dictionary, own: bool) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "Column_%s" % String(col.kind)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 14)
	var h := Label.new()
	h.text = String(col.title)
	h.add_theme_font_size_override("font_size", 18)
	h.add_theme_color_override("font_color", UiPalette.GILT)
	h.tooltip_text = TooltipText.plain(String(col.title), RulesCodex.text(String(col.codex)))
	h.mouse_filter = Control.MOUSE_FILTER_PASS
	CodexLink.attach(h, String(col.codex), codex_requested.emit)
	box.add_child(h)
	var fork: bool = String(col.kind) == PathData.OATH or String(col.kind) == PathData.TRANSFORMATION
	for i in col.cards.size():
		if fork and i > 0:
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(0, 22)
			box.add_child(gap)
		box.add_child(_card(col.cards[i], own))
	return box


## One node card: name, kind, effect, state with reason, cost and ETA, and its button.
func _card(c: Dictionary, own: bool) -> PanelContainer:
	var nid := String(c.node)
	var panel := PanelContainer.new()
	panel.name = "Card_%s" % nid.validate_node_name()
	panel.set_meta("node", nid)
	panel.set_meta("state", String(c.state))
	var st := String(c.state)
	var style := StyleBoxFlat.new()
	style.bg_color = UiPalette.PANEL_RAISED if st != AscensionRules.CLOSED else UiPalette.PANEL_BG
	var accent: Color = STATE_COLOURS.get(st, UiPalette.PANEL_BORDER)
	if not String(c.colour).is_empty() and st != AscensionRules.CLOSED:
		accent = PathView.FORK_COLOURS.get(String(c.colour), accent) if st != AscensionRules.RESEARCHING else UiPalette.GILT
	style.border_color = accent
	style.set_border_width_all(3 if st == AscensionRules.RESEARCHING else 2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", style)
	if st == AscensionRules.CLOSED:
		panel.modulate = Color(1, 1, 1, 0.6)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	panel.add_child(box)
	var name_label := _label(box, String(c.name), 18, UiPalette.TEXT_PRIMARY if st != AscensionRules.CLOSED else UiPalette.TEXT_DISABLED)
	name_label.name = "Name"
	name_label.tooltip_text = TooltipText.plain(String(c.name), "%s%s" % [String(c.detail), ("\n\n" + String(c.reason)) if not String(c.reason).is_empty() else ""])
	CodexLink.attach(name_label, String(c.codex), codex_requested.emit)
	var kind := RulerRules._cap(String(c.kind_name))  # "Tier II", "Oath", "Transformation"
	if not String(c.branch).is_empty():
		kind = "%s · %s" % [kind, AscensionRules.branch_name(String(c.branch))]
	var kind_label := _label(box, kind, 13, UiPalette.TEXT_SECONDARY)
	kind_label.name = "Kind"
	var effect := _label(box, String(c.effect), 14, UiPalette.TEXT_SECONDARY)
	effect.name = "Effect"
	effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	effect.tooltip_text = TooltipText.plain(String(c.name), String(c.detail))
	effect.set_meta("rule_text", true)  # the node's rule, as in the codex; its numbers now are in the tooltip
	CodexLink.attach(effect, String(c.codex), codex_requested.emit)
	var state_label := _label(box, String(c.state_line), 15, STATE_COLOURS.get(st, UiPalette.TEXT_PRIMARY))
	state_label.name = "State"
	state_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var reason := String(c.reason)
	# The state line's numbers (ETA, the turn it was done) are the card's breakdown; for a node that needs
	# something or is closed, its description is the plain reason.
	state_label.set_meta("breakdown", c.breakdown)
	state_label.tooltip_text = TooltipText.from_breakdown(c.breakdown)
	CodexLink.attach(state_label, "fork" if st == AscensionRules.CLOSED else "research_order", codex_requested.emit)
	if st == AscensionRules.CLOSED and own:
		var why := _label(box, reason, 13, UiPalette.TEXT_DISABLED)
		why.name = "Reason"
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		why.set_meta("breakdown", c.breakdown)
		why.tooltip_text = TooltipText.from_breakdown(c.breakdown)
		CodexLink.attach(why, "fork", codex_requested.emit)
	var number := _label(box, String(c.number_text), 14, UiPalette.TEXT_PRIMARY)
	number.name = "Numbers"
	number.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	number.set_meta("breakdown", c.breakdown)
	number.tooltip_text = TooltipText.from_breakdown(c.breakdown)
	CodexLink.attach(number, String(c.breakdown.get("codex", "research")), codex_requested.emit)
	if own:
		var b := _card_button(c)
		if b != null:
			box.add_child(b)
			buttons[nid] = b
	cards[nid] = panel
	return panel


## The card's button: Research this; Swear… (opens the lock-in preview) on an open Oath; What it brings on a
## fork node that can't be ordered yet or is your current road. None on researched or closed nodes.
func _card_button(c: Dictionary) -> Button:
	var nid := String(c.node)
	var st := String(c.state)
	if st == AscensionRules.RESEARCHED and String(c.branch).is_empty():
		return null
	if st == AscensionRules.CLOSED:
		return null
	var fork := not String(c.branch).is_empty()
	if st != AscensionRules.AVAILABLE and not fork:
		return null  # an ordinary node being researched, or one that needs another first
	var b := Button.new()
	b.name = "Action"
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 15)
	if c.is_oath and st == AscensionRules.AVAILABLE:
		b.text = "Swear… (preview first)"
		b.tooltip_text = TooltipText.plain("Swear %s" % AscensionRules.node_ref(nid), "Opens the lock-in preview: everything this side gives and everything it closes, before anything is queued. %s" % RulesCodex.text("lock_in"))
		b.disabled = not can_order
		b.pressed.connect(func(): preview_requested.emit(nid))
		CodexLink.attach(b, "lock_in", codex_requested.emit)
	elif st == AscensionRules.AVAILABLE:
		b.text = "Research this"
		b.tooltip_text = TooltipText.plain("Research %s" % String(c.name), "Makes it your research target: %s %s" % [
			String(Forecast.research(state, viewer_fid, orders, nid).get("text", "")), RulesCodex.text("research_order")])
		b.disabled = not can_order
		b.pressed.connect(func(): research_requested.emit(nid))
		CodexLink.attach(b, "research_order", codex_requested.emit)
	elif fork:
		b.text = "What it brings"
		b.tooltip_text = TooltipText.plain("What %s brings" % AscensionRules.branch_ref(String(c.branch)), "Opens the lock-in preview of this side of the fork: what you gain, what you lose access to, and your units before and after.")
		b.pressed.connect(func(): preview_requested.emit(nid))
		CodexLink.attach(b, "lock_in", codex_requested.emit)
	if b.disabled:
		b.tooltip_text = TooltipText.plain(b.text, "You can choose research only while you give orders for your own turn.")
	return b


func _fill_sidebar(own: bool) -> void:
	var s := PathView.sidebar(state, showing_fid, orders if own else [], own)
	_heading(sidebar, "Research per turn", "research_points")
	var rate := _label(sidebar, String(s.rate_text), 18, UiPalette.TEXT_PRIMARY)
	rate.name = "RateLabel"
	_bd(rate, s.rate)
	var short := _label(sidebar, String(AscensionRules.research_rate(state, showing_fid).short), 14, UiPalette.TEXT_SECONDARY)
	short.name = "RateParts"
	_bd(short, s.rate)
	if not own:
		sidebar.add_child(HSeparator.new())
		_heading(sidebar, "Their Oath", "oath")
		var sw := _label(sidebar, String(s.sworn_text), 15, UiPalette.TEXT_PRIMARY)
		sw.name = "SwornLabel"
		sw.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_tip(sw, String(s.sworn_text), RulesCodex.text("fork"), "fork")
		sw.set_meta("rule_text", true)
		if not String(s.people).is_empty():
			var p := _label(sidebar, AscensionRules.province_rule_sentence(state, showing_fid, false), 14, UiPalette.TEXT_SECONDARY)
			p.name = "TheirRule"
			p.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_tip(p, String(s.people), RulesCodex.text("transformation"), "transformation")
			p.set_meta("rule_text", true)
		var secret := _label(sidebar, "What they are researching now is secret.", 14, UiPalette.TEXT_DISABLED)
		secret.name = "SecretLabel"
		secret.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_tip(secret, "Research targets are private", RulesCodex.text("research_order"), "research_order")
		return
	var pool := _label(sidebar, String(s.pool_text), 17, UiPalette.TEXT_PRIMARY)
	pool.name = "PoolLabel"
	_bd(pool, s.progress)
	sidebar.add_child(HSeparator.new())
	_heading(sidebar, "Researching", "research")
	if String(s.target).is_empty():
		var none := _label(sidebar, String(s.target_text), 15, UiPalette.GILT if not s.complete else UiPalette.TEXT_SECONDARY)
		none.name = "TargetText"
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_bd(none, s.progress)
	else:
		var t := _label(sidebar, "%s: %d of %d" % [String(s.target_name), mini(int(s.pool), int(s.cost)), int(s.cost)], 17, UiPalette.GILT)
		t.name = "TargetLabel"
		_bd(t, s.progress)
		var bar := ProgressBar.new()
		bar.name = "TargetProgress"
		bar.max_value = maxf(1.0, float(s.cost))
		bar.value = minf(float(s.pool), float(s.cost))
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 14)
		bar.tooltip_text = TooltipText.from_breakdown(s.progress)
		sidebar.add_child(bar)
		var fc := _label(sidebar, String(s.target_text), 14, UiPalette.TEXT_SECONDARY)
		fc.name = "TargetText"
		fc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_bd(fc, s.progress)
	if not s.routes.is_empty():
		sidebar.add_child(HSeparator.new())
		_heading(sidebar, "The road to each transformation", "transformation")
		for r in s.routes:
			var l := _label(sidebar, String(r.text), 14, PathView.FORK_COLOURS.get(String(AscensionRules.branch_data(String(r.branch)).get("colour", "")), UiPalette.TEXT_PRIMARY))
			l.name = "Route_%s" % String(r.branch)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_bd(l, r.breakdown)
	sidebar.add_child(HSeparator.new())
	var sw := _label(sidebar, String(s.sworn_text), 14, UiPalette.TEXT_SECONDARY)
	sw.name = "SwornLabel"
	sw.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip(sw, "Your Oath", RulesCodex.text("fork"), "fork")
	sw.set_meta("rule_text", true)
	if status_label.visible:
		_bd(status_label, s.progress)


func _bd(l: Label, b: Dictionary) -> void:
	l.set_meta("breakdown", b)
	l.tooltip_text = TooltipText.from_breakdown(b)
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	CodexLink.attach(l, String(b.get("codex", "research")), codex_requested.emit)


func _tip(l: Label, title: String, text: String, codex: String) -> void:
	l.tooltip_text = TooltipText.plain(title, text)
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	CodexLink.attach(l, codex, codex_requested.emit)


func _heading(parent: Control, text: String, codex: String) -> Label:
	var l := _label(parent, text, 17, UiPalette.GILT)
	_tip(l, text, RulesCodex.text(codex), codex)
	return l


func _label(parent: Control, text: String, font_size: int, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", colour)
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(l)
	return l


func _build() -> void:
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0, 0, 0, 0.55)
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
	panel.add_theme_stylebox_override("panel", UiPalette.panel_style(18))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var head := HBoxContainer.new()
	head.name = "Head"
	head.add_theme_constant_override("separation", 12)
	box.add_child(head)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 0)
	head.add_child(titles)
	title_label = _label(titles, "Research", 26, UiPalette.GILT)
	title_label.name = "Title"
	people_label = _label(titles, "", 15, UiPalette.TEXT_SECONDARY)
	people_label.name = "People"
	own_tab = Button.new()
	own_tab.name = "OwnTab"
	own_tab.text = "Your path"
	own_tab.toggle_mode = true
	own_tab.focus_mode = Control.FOCUS_NONE
	own_tab.add_theme_font_size_override("font_size", 16)
	own_tab.tooltip_text = TooltipText.plain("Your path", RulesCodex.text("path"))
	own_tab.pressed.connect(show_own)
	head.add_child(own_tab)
	enemy_tabs = HBoxContainer.new()
	enemy_tabs.name = "EnemyTabs"
	head.add_child(enemy_tabs)
	close_button = Button.new()
	close_button.name = "CloseButton"
	close_button.text = "Close"
	close_button.custom_minimum_size = Vector2(110, 38)
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.add_theme_font_size_override("font_size", 17)
	close_button.tooltip_text = "Close the research panel and go back to the map (Esc)."
	close_button.pressed.connect(close)
	head.add_child(close_button)
	var body := HBoxContainer.new()
	body.name = "Body"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 24)
	box.add_child(body)
	var tree_holder := Control.new()
	tree_holder.name = "TreeHolder"
	tree_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tree_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(tree_holder)
	tree_box = HBoxContainer.new()
	tree_box.name = "Tree"
	tree_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tree_box.add_theme_constant_override("separation", 30)
	tree_holder.add_child(tree_box)
	links = Links.new()
	links.name = "Links"
	links.panel = self
	links.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tree_holder.add_child(links)
	tree_holder.move_child(links, 0)  # under the cards
	tree_box.resized.connect(links.queue_redraw)
	var side_panel := PanelContainer.new()
	side_panel.name = "Sidebar"
	side_panel.custom_minimum_size = Vector2(SIDEBAR_WIDTH, 0)
	var side_style := UiPalette.panel_style(14)
	side_style.bg_color = UiPalette.PANEL_RAISED.darkened(0.2)
	side_panel.add_theme_stylebox_override("panel", side_style)
	body.add_child(side_panel)
	sidebar = VBoxContainer.new()
	sidebar.name = "SidebarLines"
	sidebar.add_theme_constant_override("separation", 6)
	side_panel.add_child(sidebar)
	status_label = _label(box, "", 15, UiPalette.GILT)
	status_label.name = "StatusLabel"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.visible = false
	footer_label = _label(box, "", 14, UiPalette.TEXT_SECONDARY)
	footer_label.name = "Footer"
	footer_label.set_meta("rule_text", true)  # help text ("F1"), not a number
	footer_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


## The prerequisite lines between the cards: tier I → tier II, any two ordinary nodes → each Oath (faint),
## and each Oath → its transformation. Drawn under the cards from their laid-out rects.
class Links extends Control:
	var panel: ResearchPanel

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if panel == null or panel.state == null:
			return
		var fid := panel.showing_fid
		for nid in AscensionRules.node_ids(fid):
			var n := AscensionRules.node_data(nid)
			for r in n.get("requires", []):
				_link(String(r), nid, UiPalette.PANEL_BORDER.lightened(0.3), 3.0)
			if int(n.get("requires_any", 0)) > 0:
				for o in AscensionRules.node_ids(fid):
					if AscensionRules.node_kind(o) == PathData.TIER2:
						_link(o, nid, Color(UiPalette.PANEL_BORDER, 0.7), 1.5)

	func _link(from_id: String, to_id: String, colour: Color, width: float) -> void:
		var a: Control = panel.cards.get(from_id)
		var b: Control = panel.cards.get(to_id)
		if a == null or b == null or not a.is_inside_tree() or not b.is_inside_tree():
			return
		var ra := a.get_global_rect()
		var rb := b.get_global_rect()
		var origin := get_global_rect().position
		var p0 := Vector2(ra.end.x, ra.get_center().y) - origin
		var p1 := Vector2(rb.position.x, rb.get_center().y) - origin
		var mid := (p0.x + p1.x) / 2.0
		draw_polyline(PackedVector2Array([p0, Vector2(mid, p0.y), Vector2(mid, p1.y), p1]), colour, width, true)
