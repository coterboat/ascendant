class_name GameScreen
extends Control
## The one main screen of a hotseat game (#6, #7). It hosts the MapScreen for the player at the
## controls and adds a HUD to its top bar (End turn, Turn report, Codex, Quit to title). It also shows
## the handoff cover between players, the turn report at the start of each player's turn, a placeholder
## battle report and a game-over overlay.
## Everything goes through GameSession: this screen reads the session and calls its API. It never
## changes rules state itself and holds no rules math. The map's orders are backed by the session's
## order books (OrdersController in session mode), and every forecast comes from Forecast.
##
## API:
##   start_game(config)   config = {"players": [faction ids in seat order], "seed": int}. Missing keys
##                        get default_config() values: every faction in data order and a random seed.
##                        If the screen enters the tree without start_game(), it starts a default game.
##   end_turn()           the End turn button: hands off to the next player, or resolves the turn.
##   open_turn_report()   the Turn report button: the last resolved turn's report.
##   open_codex(key)      the Codex button.
##   session              the GameSession being played. Read it; act through the API above.
## Leg 3 swaps these placeholders for the real screens: _show_battle_report(event), _show_victory(victory).

const SCENE := "res://ui/game_screen.tscn"
const TITLE_SCENE := "res://ui/title_screen.tscn"
const CODEX_SCENE := "res://ui/codex_panel.tscn"

var session: GameSession = null
var config := {}  # the config the running game was started with (defaults filled in)

# Nodes. Bound or built by _bind(), so the screen also works before it is in the tree (tests).
var map: MapScreen
var overlays: CanvasLayer  # report, battle report, codex, game over and quit confirmation
var handoff: HandoffScreen  # on its own CanvasLayer above everything else
var end_turn_button: Button
var report_button: Button
var codex_button: Button
var report_overlay: Control
var report_panel: TurnReportPanel
var battle_overlay: Control
var battle_title: Label
var battle_why: Label
var battle_lines: Label
var codex: CodexPanel
var victory_overlay: Control
var victory_title: Label
var victory_label: Label
var quit_overlay: Control
var _bound := false


func _ready() -> void:
	_bind()
	if session == null:
		start_game(default_config())


## Every faction in data order, and a random seed.
static func default_config() -> Dictionary:
	var players := []
	for f in FactionData.FACTIONS:
		players.append(f.id)
	return {"players": players, "seed": randi()}


## Starts a new hotseat game. See the class comment for `game_config`.
func start_game(game_config: Dictionary = {}) -> void:
	_bind()
	config = default_config()
	config.merge(game_config, true)
	config.players = Array(config.players).duplicate()
	config.seed = int(config.seed)
	_close_overlays()
	victory_overlay.visible = false
	handoff.visible = false
	# The state's seed and the game seed are the same, so GameSession's turn seeds match TurnResolver's.
	session = GameSession.new(GameState.new(config.seed), config.players, config.seed, AutoBattleResolver.new())
	map.session = session
	if session.phase() == GameSession.Phase.INVALID:
		_show_setup_errors(session.setup_errors())
		return
	_show_current_player()


## Ends the current player's turn. Returns "" or the session's reason it could not.
func end_turn() -> String:
	if session == null:
		return "No game is running."
	var why := session.end_turn()
	if not why.is_empty():
		map.set_hint(why)
		return why
	_close_overlays()
	match session.phase():
		GameSession.Phase.HANDOFF:
			_show_handoff()
		GameSession.Phase.GAME_OVER:
			_show_game_over()
	return ""


## Shows the last resolved turn's report. Does nothing before the first turn is resolved.
func open_turn_report() -> void:
	_bind()
	if session == null or session.turn_report().turn == 0:
		return
	report_panel.show_report(session)
	report_overlay.visible = true


func close_turn_report() -> void:
	report_overlay.visible = false


func open_codex(key: String = "") -> void:
	_bind()
	codex.open(key)


# --- the turn cycle -------------------------------------------------------------------------------

## The current player's ORDERS phase: their map, their orders, their capital selected for recruiting.
func _show_current_player() -> void:
	var fid := session.current_player()
	map.visible = true
	map.selected_army_id = ""
	map.selected_province_id = ""
	map.set_state(session.state(), fid)
	var f := map.state.find_faction(fid)
	var capital: Province = map.state.find_province(f.capital) if f else null
	if capital and capital.owner == fid:
		map.select_province(capital.id)
	_update_hud()


## Covers everything and hides the map until the next player presses Ready.
func _show_handoff() -> void:
	map.clear_preview()
	map.visible = false
	handoff.show_for(session)
	_update_hud()


func _on_handoff_acknowledged() -> void:
	_show_current_player()
	if session.turn_report().turn > 0:
		open_turn_report()


## The final map, seen by nobody in particular, under the game-over overlay.
func _show_game_over() -> void:
	map.visible = true
	map.selected_army_id = ""
	map.selected_province_id = ""
	map.set_state(session.state(), "")
	map.faction_label.text = "Game over"
	map.faction_label.tooltip_text = TooltipText.plain("Game over", "Nobody gives orders any more. The map shows the final positions.")
	_update_hud()
	_show_victory(session.victory())


## Clicking a report line closes the report and shows that province on the map.
func _on_report_focus(province_id: String) -> void:
	close_turn_report()
	map.selected_army_id = ""  # so the click can't be taken as a move order for a selected army
	map.focus_province(province_id)


func _on_quit_requested() -> void:
	if session == null or session.is_over():
		_go_to_title()
		return
	quit_overlay.visible = true


func _go_to_title() -> void:
	if is_inside_tree():
		get_tree().change_scene_to_file(TITLE_SCENE)


func _close_overlays() -> void:
	report_overlay.visible = false
	battle_overlay.visible = false
	quit_overlay.visible = false
	if codex.visible:
		codex.close()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	for overlay in [quit_overlay, battle_overlay, report_overlay]:
		if overlay.visible:
			overlay.visible = false
			get_viewport().set_input_as_handled()
			return


# --- placeholders leg 3 replaces ------------------------------------------------------------------

## Battle report (#7), placeholder viewer: the "why" on top, then the full report's plain lines.
## Leg 3 swaps this method for the battle report viewer.
func _show_battle_report(event: Dictionary) -> void:
	_bind()
	var numbers: Dictionary = event.get("numbers", {})
	var report: Dictionary = numbers.get("report", {})
	battle_title.text = "Battle %s" % report.place if report.has("place") else "Battle report"
	var why := str(numbers.get("why", ""))
	var why_lines := PackedStringArray()
	for clause in why.split(";", false):
		var c := clause.strip_edges()
		if not c.is_empty():
			why_lines.append("•  %s" % (c.left(1).to_upper() + c.substr(1)))
	battle_why.text = "\n".join(why_lines) if not why_lines.is_empty() else "No reasons were recorded for this battle."
	var lines: Array = report.get("lines", [])
	battle_lines.text = "\n\n".join(PackedStringArray(lines)) if not lines.is_empty() else str(event.get("text", ""))
	battle_overlay.visible = true


## Game over (#8), placeholder: the victory summary and a way back to the title screen.
## Leg 3 swaps this method for the victory screen.
func _show_victory(victory: Dictionary) -> void:
	_bind()
	var winner := str(victory.get("winner", ""))
	var f: Faction = map.state.find_faction(winner) if map.state and not winner.is_empty() else null
	if victory.get("draw", false):
		victory_title.text = "The game is a draw"
	elif f:
		victory_title.text = "%s wins" % f.faction_name
	else:
		victory_title.text = "The game is over"
	victory_label.text = str(victory.get("text", ""))
	victory_overlay.visible = true


func _show_setup_errors(errors: Array) -> void:
	map.visible = false
	victory_title.text = "This game could not start"
	victory_label.text = " ".join(PackedStringArray(errors))
	victory_overlay.visible = true
	_update_hud()


# --- HUD ------------------------------------------------------------------------------------------

func _update_hud() -> void:
	var playing: bool = session != null and session.phase() == GameSession.Phase.ORDERS
	var n: int = session.current_orders().size() if playing else 0
	end_turn_button.disabled = not playing
	end_turn_button.text = "End turn (%s)" % _count(n, "order") if playing else "End turn"
	end_turn_button.tooltip_text = _end_turn_tooltip(n)
	var has_report: bool = session != null and session.turn_report().turn > 0
	report_button.disabled = not has_report
	var report_help := "Read again what happened last turn. Click a line to see it on the map."
	if not has_report:
		report_help = "Nothing has happened yet. The report of each turn appears here once every player has ended the turn."
	report_button.tooltip_text = TooltipText.plain("Turn report", report_help)
	if session == null or map.state == null or session.phase() == GameSession.Phase.INVALID:
		return
	map.turn_label.text = "Turn %d" % session.turn_number()
	map.turn_label.tooltip_text = _turn_tooltip()
	if playing:
		map.set_hint("Player %d of %d, %s: give your orders. Select an army, then click a neighboring province to move it. Select your capital to recruit." % [
			session.current_seat(), session.players().size(), session.current_player_name()])
	elif session.is_over():
		map.set_hint("The game is over. Open the turn report to see how the last turn went.")


func _end_turn_tooltip(n: int) -> String:
	if session == null or session.phase() != GameSession.Phase.ORDERS:
		var idle := "The game is over, so there are no more turns." if session and session.is_over() else "Nobody is giving orders right now."
		return TooltipText.plain("End turn", idle)
	var seat := session.current_seat()
	var players := session.players()
	var text := "End your turn with %s queued. " % _count(n, "order")
	if seat < players.size():
		var next: Faction = map.state.find_faction(players[seat]) if map.state else null
		text += "The screen is then covered so you can pass the computer to player %d (%s), whose orders stay hidden from you. Nothing happens until the last player ends their turn." % [
			seat + 1, next.faction_name if next else "the next player"]
	else:
		text += "You are the last player this turn, so everyone's orders resolve together as soon as you end it."
	return TooltipText.plain("End turn", text)


## The session's 1-based turn, with the game seed so the game can be replayed.
func _turn_tooltip() -> String:
	var state := map.state
	# The seed opens its own paragraph so the wrapping never splits it.
	var seed_text := "\n\n" + TooltipText.wrap_text("Game seed %d. Start a game with the same players and this seed, give the same orders, and every turn and battle plays out the same." % config.seed)
	if session.is_over():
		return TooltipText.plain("Turn %d" % session.turn_number(), "The game ended on turn %d." % session.turn_number()) + seed_text
	var b := {"title": "Turn %d" % session.turn_number(),
		"description": "Player %d of %d is giving orders. %s" % [session.current_seat(), session.players().size(), RulesCodex.text("hotseat")],
		"lines": [{"label": "Turns resolved so far", "value": state.current_turn, "note": ""},
			{"label": "This turn", "value": session.turn_number() - state.current_turn, "note": "the turn being ordered now"}],
		"total_label": "Turn being played", "total": session.turn_number()}
	return TooltipText.from_breakdown(b) + seed_text


static func _count(n: int, noun: String) -> String:
	if n == 0:
		return "no %ss" % noun
	return "%d %s%s" % [n, noun, "" if n == 1 else "s"]


# --- building the screen --------------------------------------------------------------------------

## Finds the scene's nodes, builds the HUD and overlays and wires their signals, once.
func _bind() -> void:
	if _bound:
		return
	_bound = true
	map = $Map
	overlays = $Overlays
	handoff = $HandoffLayer/Handoff
	handoff.acknowledged.connect(_on_handoff_acknowledged)
	map.intercept_back = true
	map.back_requested.connect(_on_quit_requested)
	map.orders_changed.connect(_update_hud)
	_build_hud()
	_build_overlays()


func _build_hud() -> void:
	report_button = _hud_button("TurnReportButton", "Turn report", open_turn_report)
	map.add_top_bar_control(report_button)
	codex_button = _hud_button("CodexButton", "Codex", open_codex.bind(""))
	codex_button.tooltip_text = TooltipText.plain("Codex", "Every rule of the game in plain language, searchable.")
	map.add_top_bar_control(codex_button)
	end_turn_button = _hud_button("EndTurnButton", "End turn", end_turn)
	end_turn_button.custom_minimum_size = Vector2(210, 0)
	end_turn_button.add_theme_font_size_override("font_size", 18)
	end_turn_button.add_theme_color_override("font_color", UiPalette.GILT)
	map.add_top_bar_control(end_turn_button)
	map.back_button.text = "Quit to title"
	map.back_button.tooltip_text = TooltipText.plain("Quit to title",
		"Leave this game and go back to the title screen. You are asked to confirm first: games are not saved yet.")


func _hud_button(node_name: String, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 16)
	b.pressed.connect(func(): action.call())
	return b


func _build_overlays() -> void:
	# Bottom to top: game over, turn report, battle report, codex, quit confirmation.
	var v := _overlay("VictoryOverlay", Vector2(820, 0), 0.55)
	victory_overlay = v[0]
	victory_title = _label("VictoryTitle", 40, UiPalette.GILT)
	victory_title.tooltip_text = TooltipText.plain("Winning the game", RulesCodex.text("victory"))
	victory_title.mouse_filter = Control.MOUSE_FILTER_PASS
	v[1].add_child(victory_title)
	victory_label = _label("VictoryText", 22, UiPalette.TEXT_PRIMARY)
	v[1].add_child(victory_label)
	var vrow := _button_row(v[1])
	_overlay_button(vrow, "FinalReportButton", "Final turn report", open_turn_report,
		"Read the report of the last turn, which ended the game.")
	_overlay_button(vrow, "ViewMapButton", "View the map", func(): victory_overlay.visible = false,
		"Close this and look at the final map. Quit to title from the top bar when you are done.")
	_overlay_button(vrow, "VictoryTitleButton", "Back to title", _go_to_title, "Go back to the title screen.")

	report_overlay = _report_overlay()

	var b := _overlay("BattleReport", Vector2(1000, 720))
	battle_overlay = b[0]
	battle_title = _label("BattleTitle", 30, UiPalette.GILT)
	b[1].add_child(battle_title)
	var why_heading := _label("WhyHeading", 20, UiPalette.TEXT_SECONDARY)
	why_heading.text = "Why it went this way"
	b[1].add_child(why_heading)
	battle_why = _label("BattleWhy", 20, UiPalette.TEXT_PRIMARY)
	b[1].add_child(battle_why)
	var full_heading := _label("FullHeading", 20, UiPalette.TEXT_SECONDARY)
	full_heading.text = "The full report"
	b[1].add_child(full_heading)
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	b[1].add_child(scroll)
	battle_lines = _label("BattleLines", 17, UiPalette.TEXT_PRIMARY)
	battle_lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(battle_lines)
	var brow := _button_row(b[1])
	_overlay_button(brow, "CloseBattleButton", "Close", func(): battle_overlay.visible = false, "Back to the turn report.")

	codex = load(CODEX_SCENE).instantiate()
	codex.name = "Codex"
	codex.visible = false
	# The codex panel's default background lets the map show through its text; use the opaque panel.
	var codex_bg := codex.get_node_or_null("Background") as PanelContainer
	if codex_bg:
		codex_bg.add_theme_stylebox_override("panel", _panel_style(0))
	overlays.add_child(codex)

	var q := _overlay("QuitConfirm", Vector2(640, 0))
	quit_overlay = q[0]
	var qtitle := _label("QuitTitle", 30, UiPalette.GILT)
	qtitle.text = "Quit to the title screen?"
	q[1].add_child(qtitle)
	var qtext := _label("QuitText", 20, UiPalette.TEXT_PRIMARY)
	qtext.text = "Games are not saved yet, so this game will be lost."
	q[1].add_child(qtext)
	var qrow := _button_row(q[1])
	_overlay_button(qrow, "KeepPlayingButton", "Keep playing", func(): quit_overlay.visible = false, "Go back to the game.")
	_overlay_button(qrow, "ConfirmQuitButton", "Quit to title", _go_to_title, "Leave this game for the title screen.")


## The turn report panel in a modal frame with a footer: a hint and a Close button.
func _report_overlay() -> Control:
	var overlay := _overlay_base("ReportOverlay", 0.45)
	var center := CenterContainer.new()
	center.name = "Center"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var box := VBoxContainer.new()
	box.name = "Box"
	box.custom_minimum_size = Vector2(1040, 760)
	box.add_theme_constant_override("separation", 0)
	center.add_child(box)
	report_panel = TurnReportPanel.new()
	report_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	report_panel.province_focus_requested.connect(_on_report_focus)
	report_panel.battle_report_requested.connect(func(e: Dictionary): _show_battle_report(e))
	box.add_child(report_panel)
	var footer := PanelContainer.new()
	footer.name = "Footer"
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.11, 0.14, 0.97)  # matches the report panel
	style.border_color = UiPalette.PANEL_BORDER
	style.border_width_top = 1
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 12
	style.content_margin_bottom = 16
	footer.add_theme_stylebox_override("panel", style)
	box.add_child(footer)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	footer.add_child(row)
	var hint := _label("ReportHint", 16, UiPalette.TEXT_SECONDARY)
	hint.text = "Click a line to see it on the map. Battles have a full report. Reopen this from Turn report in the top bar."
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.add_child(hint)
	var close := Button.new()
	close.name = "CloseReportButton"
	close.text = "Close"
	close.custom_minimum_size = Vector2(140, 44)
	close.add_theme_font_size_override("font_size", 20)
	close.tooltip_text = "Close the report and give your orders."
	close.pressed.connect(close_turn_report)
	row.add_child(close)
	return overlay


## A hidden full-screen overlay: a dim backdrop that swallows clicks.
func _overlay_base(node_name: String, dim_alpha: float) -> Control:
	var overlay := Control.new()
	overlay.name = node_name
	overlay.visible = false
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0, 0, 0, dim_alpha)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	overlays.add_child(overlay)
	return overlay


## An overlay with a centred panel. Returns [overlay, the panel's VBoxContainer].
func _overlay(node_name: String, panel_size: Vector2, dim_alpha: float = 0.6) -> Array:
	var overlay := _overlay_base(node_name, dim_alpha)
	var center := CenterContainer.new()
	center.name = "Center"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.custom_minimum_size = panel_size
	panel.add_theme_stylebox_override("panel", _panel_style(28))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	return [overlay, box]


## The opaque overlay panel: the map's panel colours with a keyline border.
static func _panel_style(margin: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UiPalette.PANEL_BG
	style.border_color = UiPalette.PANEL_BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(margin)
	return style


func _button_row(parent: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Buttons"
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 14)
	parent.add_child(row)
	return row


func _overlay_button(row: HBoxContainer, node_name: String, text: String, action: Callable, tooltip: String) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.tooltip_text = tooltip
	b.custom_minimum_size = Vector2(150, 44)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(func(): action.call())
	row.add_child(b)
	return b


func _label(node_name: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.name = node_name
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l
