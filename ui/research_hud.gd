class_name ResearchHud
extends RefCounted
## Research on the game screen (M4-4, #69; design/M4_ASCENSION.md §9.1): the top bar chip, the research
## panel and the lock-in preview, hosted for GameScreen with the smallest hooks there (one line builds it in
## _build_hud, one line in _update_hud calls refresh()). Everything goes through the GameSession: "Research
## this" and "Swear the Oath" call GameSession.queue_research, so the order lands in the current player's
## order book like any other and is checked by the same rules.
##
## The chip ("Research: Arbalests / 12/15 · this turn", or "Research: choose / 14 waiting" in the attention
## colour) shows only in a game with paths, while a person gives orders; a click opens the panel. UX-1 (#194): the chips
## are the system row's Research and Magic buttons (TableHud.add_system_button), the progress badge being the chip's second line. The panel
## and the preview sit on the game's Overlays layer, so the codex opens above them. They follow the seat:
## refresh() closes them on the handoff cover, at game over, on a new turn or when another player is at the
## controls, so nothing of one player's research is left on screen for the next (hotseat).

var game: GameScreen
var chip: Button
var magic_chip: Button  # M5-8: "Magic: 3 spells / 2 mages · 1 cast ordered", in a game with magic; a click opens the Magic tab
var panel: ResearchPanel = null
var preview: LockInPreview = null


func _init(p_game: GameScreen) -> void:
	game = p_game
	chip = Button.new()
	chip.name = "ResearchChip"
	chip.focus_mode = Control.FOCUS_NONE
	chip.visible = false
	chip.custom_minimum_size = Vector2(0, 0)
	chip.add_theme_font_size_override("font_size", 13)
	chip.add_theme_constant_override("line_spacing", -3)
	chip.pressed.connect(open_panel)
	game.map.table().add_system_button("research", chip)
	magic_chip = Button.new()  # M5-8
	magic_chip.name = "MagicChip"
	magic_chip.focus_mode = Control.FOCUS_NONE
	magic_chip.visible = false
	magic_chip.custom_minimum_size = Vector2(0, 0)
	magic_chip.add_theme_font_size_override("font_size", 13)
	magic_chip.add_theme_constant_override("line_spacing", -3)
	magic_chip.pressed.connect(open_magic)
	game.map.table().add_system_button("magic", magic_chip)


## The viewing player's faction while a person gives orders in a game with paths; "" otherwise.
func viewer() -> String:
	var s := game.session
	var st := game.map.state if game.map else null
	if s == null or st == null or not AscensionRules.has_paths(st) or s.phase() != GameSession.Phase.ORDERS:
		return ""
	if game.is_watching() or s.is_computer(s.current_player()) or st.find_faction(s.current_player()) == null:
		return ""
	return s.current_player()


## GameScreen._update_hud: the chip's text and visibility; the panel and preview follow the seat.
func refresh() -> void:
	var fid := viewer()
	chip.visible = not fid.is_empty()
	magic_chip.visible = not fid.is_empty() and MagicRules.has_magic(game.map.state)
	if fid.is_empty():
		close_all()
		return
	var st := game.map.state
	if magic_chip.visible:  # M5-8
		var m := MagicView.chip(st, fid, game.session.current_orders())
		magic_chip.text = String(m.text)
		magic_chip.add_theme_color_override("font_color", UiPalette.GILT if m.attention else UiPalette.TEXT_PRIMARY)
		magic_chip.set_meta("breakdown", m.breakdown)
		magic_chip.tooltip_text = "%s\n\n%s" % [TooltipText.from_breakdown(m.breakdown), TooltipText.wrap_text(String(m.tooltip))]
		CodexLink.attach(magic_chip, String(m.codex), game.open_codex)
	var c := PathView.chip(st, fid, game.session.current_orders())
	chip.text = String(c.text)
	chip.add_theme_color_override("font_color", UiPalette.GILT if c.attention else UiPalette.TEXT_PRIMARY)
	chip.tooltip_text = "%s\n\n%s" % [TooltipText.from_breakdown(c.breakdown), TooltipText.wrap_text("Click to open the research panel: your path, what each node does and when it would be done, and the enemy's path.")]
	if MagicRules.has_magic(st):  # M5-8: a spell researched ahead of the road says what it does to your transformation
		var target := String(Forecast.research(st, fid, game.session.current_orders()).get("target", ""))
		var delay := Forecast.arcana_delay(st, fid, target, game.session.current_orders()) if not target.is_empty() else {}
		if bool(delay.get("applies", false)):
			chip.tooltip_text = "%s\n\n%s\n\n%s" % [TooltipText.from_breakdown(c.breakdown), TooltipText.wrap_text(String(delay.text)),
				TooltipText.wrap_text("Click to open the research panel: your path, your arcana, and the enemy's path.")]
	CodexLink.attach(chip, String(c.codex), game.open_codex)
	if panel != null and panel.visible:
		if panel.viewer_fid != fid or panel.state == null or panel.state.current_turn != st.current_turn:
			close_all()
		else:
			panel.state = st
			panel.set_orders(game.session.current_orders(), panel.status_text)


## The chip: opens the research panel on your own path.
func open_panel() -> void:
	var fid := viewer()
	if fid.is_empty():
		return
	if panel == null:
		panel = ResearchPanel.new()
		panel.research_requested.connect(queue)
		panel.spellbook_requested.connect(queue_spellbook)  # M5-5: the Magic tab's battle spellbook
		panel.preview_requested.connect(open_preview)
		panel.codex_requested.connect(game.open_codex)
		panel.closed.connect(func(): if preview != null: preview.visible = false)
		game.overlays.add_child(panel)
	_raise(panel)
	panel.show_for(game.map.state, fid, game.session.current_orders(), true)


## M5-8: the Magic chip opens the research panel on its Magic tab (the arcana, mastery and the battle spellbook).
func open_magic() -> void:
	open_panel()
	if panel != null:
		panel.show_magic()


## The lock-in preview of the side `node_id` is on, above the panel.
func open_preview(node_id: String) -> void:
	var fid := viewer()
	if fid.is_empty():
		return
	if preview == null:
		preview = LockInPreview.new()
		preview.confirmed.connect(_on_confirmed)
		preview.codex_requested.connect(game.open_codex)
		game.overlays.add_child(preview)
	_raise(preview)
	preview.show_for(game.map.state, fid, node_id, game.session.current_orders())


## Queues a ResearchOrder for the current player through the session. Returns "" or the rules' reason,
## which the panel shows in its status line either way.
func queue(node_id: String) -> String:
	var why := game.session.queue_research(node_id)
	var status := why
	if why.is_empty():
		var fc := Forecast.research(game.map.state, viewer(), game.session.current_orders())
		status = "Research order given: %s It replaces any research order you gave this turn, and you can cancel it in your orders list until you end the turn." % String(fc.get("text", ""))
		if game.map.has_method("_orders_changed"):
			game.map._orders_changed()  # the side panel's orders list, End turn's count and this chip
	if panel != null and panel.visible:
		panel.set_orders(game.session.current_orders(), status)
	return why


## M5-5: queues a SpellbookOrder (the Magic tab's battle spellbook) through the session; a new one replaces the
## one given this turn. Returns "" or the rules' reason, shown in the panel's status line either way.
func queue_spellbook(order: Array, off: Array) -> String:
	var why := game.session.queue_spellbook(order, off)
	var status := why
	if why.is_empty():
		status = "Battle spellbook set: %s. It applies from this turn and is kept until you change it; you can cancel it in your orders list until you end the turn." % MagicRules.spellbook_text(order, off)
		if game.map.has_method("_orders_changed"):
			game.map._orders_changed()
	if panel != null and panel.visible:
		panel.set_orders(game.session.current_orders(), status)
	return why


func _on_confirmed(node_id: String) -> void:
	if queue(node_id).is_empty() and preview != null:
		preview.visible = false


func close_all() -> void:
	if preview != null:
		preview.visible = false
	if panel != null and panel.visible:
		panel.visible = false


func _raise(overlay: Control) -> void:
	game.overlays.move_child(overlay, game.overlays.get_child_count() - 1)
	overlay.visible = true
