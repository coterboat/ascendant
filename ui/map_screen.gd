class_name MapScreen
extends Control
## The main map screen (issue #5): the M1 map drawn from a GameState, a top bar with the viewing
## player's gold and the turn, and a side panel with the selected province's details.
## Reads the GameState only and never changes it. Every number on screen has a tooltip with its
## breakdown (rules/breakdown.gd) and a plain-language description, ending with the codex entry that
## explains it: right-click (or F1 while hovering) asks for that entry with codex_requested (#8). In the
## map preview, where no game screen listens, the map opens a codex panel of its own.
## Player colours follow the seat: seat_order() is the session's seat order when there is a session.
##
## API for the orders UI and turn flow:
##   set_state(state, viewing_faction_id)  show a state (rebuilds the map; keeps the selection if it still exists)
##   select_province(id)                   select a province and fill the side panel
##   select_army(id)                       select an army (and its province)
##   focus_province(id)                    select a province and flash it to draw the eye
##   preview_move(id)                      hover preview: what clicking `id` would order for the selected army
##   open_ruler_panel(), close_ruler_panel()   the ruler panel (M2-6): your ruler and the enemy's, read-only
##   open_sacrifice_dialog(mandate_id)     the sacrifice dialog over it; queue_sacrifice(mandate_id) queues one
##   signal province_selected(id), signal army_selected(id), signal orders_changed
##   signal codex_requested(key)           a linked number or term was right-clicked (or F1)
##   set_board(board)                      M3a.1: draws the map as the 3D world (world3d/board3d.gd) instead of
##                                         the 2D regions; null puts the 2D map back. The board picks
##                                         provinces and armies and calls this screen's own API, and
##                                         this screen calls board.sync() whenever what it shows changes.
##
## Hooks for the game screen (#7), which hosts this screen for the player at the controls:
##   session                    set it before set_state(): orders then go through GameSession's books
##   intercept_back             true: the back button emits back_requested instead of leaving
##   add_top_bar_control(c)     puts a HUD control in the top bar, just before the back button
##   set_hint(text, tooltip)    the short help text in the top bar (at most two lines; the tooltip can
##                              say more)
##
## Sound (GameAudio): an accepted order sounds order_queued, with march after a move and recruit after a
## recruit; a sacrifice sounds sacrifice; a cancelled order order_cancelled. A refused order is silent
## (its reason shows in the panel).
##
## Colour is never the only channel (design/STYLE_BIBLE.md 1.1): every owner ring and army badge also
## carries the seat's emblem (SeatEmblem: Player 1 circle, Player 2 square, nobody a slate shield), and
## so does the viewing player's name in the top bar.
##
## Forts and sieges (M3c S-3, #101), only in a game with sieges: the "Fort:" line names the level and the fort
## section (FortPanel) follows it, with every number explained and the viewer's Fortify, Storm and Sally choices;
## the recruit section becomes "Recruit at" with a picker of your forts, each greyed with the rules' reason when
## it can't take recruits; a move into an enemy fort can be turned into a storm from its order line (Storm now);
## and a relief move sends the garrison out to join it (OrdersController.queue_move).
##
## Art (#10, through Art): the map is one painted board: a sea with shallows and wave marks, one
## landmass under every province (its coast keylined in map ink, land bridges along the roads), sandy
## roads, and each province painted with its terrain tile over a soft drop shadow. The viewing faction's
## banner stands by its name in the top bar (with the seat emblem on it), the selected province's
## header is painted with its terrain and flies its owner's banner, and units show their portraits in
## the army list and on the recruit buttons.
##
## Fog of war (M5-2, #113; design/M5_MAGIC_FOG.md §2.4-§2.10, §11.1): in a fog game `state` is the viewer's view
## (GameSession.state_for), and set_fog(memory, intel, before) gives the map the rest of what that viewer knows (its
## memory, its intel and its view at the start of the last resolved turn), never the truth. Province tooltips say why a
## province is seen or what is remembered of it; a rival's army shows as its sighting ("≈20", "≈10 · 2 turns ago"),
## with every type's range, last turn's sighting and how to see it exactly in the side panel; your armies say how far
## they see and scouts say so; the forecasts are Forecast's fog forecasts. The Vision map mode (set_map_mode("vision"),
## the Vision button over the map) draws every province's sight level on the 2D map, with its legend; out of it, the
## 2D map still veils what you can't see.

signal province_selected(province_id: String)
signal army_selected(army_id: String)
## The viewing player's queued orders changed (queued, refused or cancelled).
signal orders_changed
## The back button was pressed while intercept_back is on.
signal back_requested
## A number or term linked to the codex was right-clicked (or F1 was pressed over it).
signal codex_requested(key: String)

const SIDE_PANEL_WIDTH := 400
## The board under the provinces (STYLE_BIBLE.md 1.2: sea, deep sea, map ink; fog veil for the roads).
const SEA_DEEP := Color("#244E6E")
const SEA := Color("#2F7A93")
const ROAD := Color("#E6D9BC")
## How far the landmass and the shallows reach past each province, as a multiple of its radius, and
## how wide the land bridges along the roads are (design space).
const LAND_GROW := 1.3
const SHALLOW_GROW := [1.78, 1.52]
const LAND_BRIDGE := 58.0
## The land between provinces: the plains tile, dimmed and greyed so the provinces stand out on it.
const LAND_TINT := Color(0.5, 0.55, 0.43)
const LAND_TILE := 260.0
## Portrait sizes in the side panel: army rows and recruit buttons.
const ROW_PORTRAIT := Vector2(44, 44)
const TITLE_SCENE := "res://ui/title_screen.tscn"
const CODEX_SCENE := "res://ui/codex_panel.tscn"
## Added to the army strength tooltip: the number is a size guide, the move forecast has the odds.
const STRENGTH_GUIDE := "For your real chances, select one of your armies next to this one and hover its province: the move forecast fights that battle with the full rules and shows the odds."

var state: GameState = null
var viewing_faction_id := ""
var selected_province_id := ""
var selected_army_id := ""
var regions := {}  # province id -> ProvinceRegion
var orders: OrdersController = null  # issue #6: the viewing faction's orders this turn
var session: GameSession = null  # game screen (#7): when set, orders live in the session's books
var intercept_back := false  # game screen (#7): the host confirms before leaving
var status_text := ""  # last order result: the rules' reason when an order was refused
var arrow_layer: Control  # drawn above the regions: one arrow per queued move
var hover_panel: PanelContainer  # hover preview bar at the bottom of the map
var hover_label: Label
var own_codex: CodexPanel = null  # map preview only: opened when no game screen listens for codex_requested
var ruler_panel: RulerPanel = null  # M2-6: opened by open_ruler_panel(), over the map and the side panel
var sacrifice_dialog: SacrificeDialog = null  # M2-6: opened from the ruler panel
var cast_dialog: CastDialog = null  # M5-6: opened from an army of yours that holds a caster
## M3a.1: the 3D board (Board3D) drawn in the map view instead of the 2D regions, or null for the 2D map.
## The regions are still built (hidden): they keep the tooltips and marks the board mirrors.
var board: Control = null
## M5-2, fog of war: what the viewer knows besides its view (set_fog): its memory and intel, and its view at the start
## of the last resolved turn (for "last turn" on a sighting). Empty and null without fog.
var fog_memory := {}
var fog_intel := {}
var fog_before: GameState = null
## M5-2: "" (the map) or "vision" (the Vision map mode: sight levels on the 2D map, with the legend).
var map_mode := ""
var vision_button: Button
var vision_legend: PanelContainer

# Scene nodes, looked up by _bind() rather than @onready so the screen also works before it is in
# the tree (tests build it headless, and callers may set_state() before adding it).
var map_view: Control
var map_canvas: Control
var details: VBoxContainer
var faction_label: Label
var faction_emblem: SeatEmblem  # the viewing player's seat emblem, on their banner left of their name
var faction_crest: Control  # the viewing faction's banner (Art) with the seat emblem on it
var faction_banner: Art.BannerCard
var gold_label: Label  # hidden when nobody's gold is shown (game over, spectator)
var turn_label: Label
var hint_label: Label  # wraps to at most two lines
var back_button: Button


func _ready() -> void:
	_bind()
	if state == null:
		# Opened straight from the title screen: show a fresh default M1 game from player 1's view.
		state = GameState.new()
		viewing_faction_id = state.factions[0].id
	set_state(state, viewing_faction_id)
	_fit_map()


## M5-2: what the viewer knows besides its view, in a fog game (GameSession.memory, intel and view_before); set it
## before set_state. {} and null without fog.
func set_fog(memory: Dictionary, intel: Dictionary, before: GameState) -> void:
	fog_memory = memory
	fog_intel = intel
	fog_before = before


## Shows `new_state` as seen by `faction_id`. Rebuilds every region; the state is only read.
func set_state(new_state: GameState, faction_id: String) -> void:
	if orders == null or orders.state != new_state or orders.faction_id != faction_id or orders.session != session:
		orders = OrdersController.new(new_state, faction_id, session)
		status_text = ""
	orders.fog_memory = fog_memory
	orders.fog_intel = fog_intel
	state = new_state
	viewing_faction_id = faction_id
	_bind()
	for child in map_canvas.get_children():
		map_canvas.remove_child(child)
		child.queue_free()
	regions.clear()
	var seats := seat_order()
	for p in state.provinces:
		if not MapLayout.has_position(p.id):
			push_error("The map layout has no position for province '%s'." % p.id)
			continue
		var region := ProvinceRegion.new()
		region.setup(state, p, MapLayout.position_of(p.id), seats, faction_id)
		region.pressed.connect(select_province)
		region.army_pressed.connect(select_army)
		region.codex_requested.connect(request_codex)
		region.mouse_entered.connect(preview_move.bind(p.id))
		region.mouse_exited.connect(clear_preview)
		map_canvas.add_child(region)
		regions[p.id] = region
		if FogView.active(state):
			region.setup_fog(state, faction_id, fog_memory, fog_before)  # M5-2: sight, memory and sightings
	map_canvas.queue_redraw()
	arrow_layer.queue_redraw()
	clear_preview()
	_update_top_bar()
	if state.find_province(selected_province_id) == null:
		selected_province_id = ""
	if state.find_army(selected_army_id) == null:
		selected_army_id = ""
	_update_map_marks()
	_show_details()
	_follow_ruler_panel()
	vision_button.visible = FogView.active(state)
	if not FogView.active(state):
		map_mode = ""
	_apply_map_mode()
	_sync_board()


## M5-2: the map mode: "" for the map, "vision" for the Vision map mode (fog games only): every province drawn at its
## sight level on the 2D map (in clear sight, glimpsed, out of sight, never seen), with the legend; on the 3D board the
## 2D map stands in while it is on.
func set_map_mode(mode: String) -> void:
	_bind()
	map_mode = mode if mode == "vision" and FogView.active(state) else ""
	_apply_map_mode()


func _apply_map_mode() -> void:
	var vision := map_mode == "vision"
	for id in regions:
		regions[id].vision_mode = vision
		regions[id].queue_redraw()
	vision_legend.visible = vision
	if vision:
		_fill_vision_legend()
	vision_button.set_pressed_no_signal(vision)
	vision_button.text = "Vision: on" if vision else "Vision"
	if board != null:
		board.visible = not vision
		map_canvas.visible = vision
		arrow_layer.visible = vision


func select_province(province_id: String) -> void:
	if state == null or state.find_province(province_id) == null:
		return
	if casting():  # M5-8: with the cast dialog open, a lit province is the target; any other click changes nothing
		if cast_dialog.accepts_province(province_id):
			cast_dialog.select_target(province_id)
		return
	# Two-click move: with one of your armies selected, clicking another province orders it there.
	var mover := state.find_army(selected_army_id)
	if mover and orders and mover.owner == viewing_faction_id and mover.location != province_id:
		if queue_move(mover.id, province_id).is_empty():
			return
		# Refused: the reason stays in the status line and the click selects the province as usual.
	else:
		status_text = ""
	clear_preview()
	selected_province_id = province_id
	var army := state.find_army(selected_army_id)
	if army == null or army.location != province_id:
		selected_army_id = ""
	for id in regions:
		regions[id].selected = id == province_id
	_update_road_targets()
	_show_details()
	_sync_board()
	province_selected.emit(province_id)


func select_army(army_id: String) -> void:
	var army: Army = state.find_army(army_id) if state else null
	if army == null:
		return
	selected_army_id = army_id
	select_province(army.location)
	army_selected.emit(army_id)


## Hover preview (#6): with one of your armies selected, shows what clicking `province_id` would
## order (arrival forecast and battle odds, or the rules' reason it can't be ordered) in a bar over the
## map, before you click. Returns the text shown, "" when there is nothing to preview.
func preview_move(province_id: String) -> String:
	_bind()
	var text := ""
	var army: Army = state.find_army(selected_army_id) if state else null
	if orders and army and army.owner == viewing_faction_id and army.location != province_id \
			and state.find_province(province_id) != null:
		text = orders.move_preview(army.id, province_id).text
	hover_label.text = text
	hover_panel.visible = not text.is_empty()
	return text


func clear_preview() -> void:
	if hover_panel:
		hover_label.text = ""
		hover_panel.visible = false


## Game screen hook: adds a HUD control to the top bar, just before the back button.
func add_top_bar_control(control: Control) -> void:
	_bind()
	var row := back_button.get_parent()
	row.add_child(control)
	row.move_child(control, back_button.get_index())


## The help text in the top bar. Keep it short: it wraps to at most two lines. `tooltip`, already
## formatted (TooltipText.plain), is shown on hover for help that doesn't fit; empty shows the text.
func set_hint(text: String, tooltip: String = "") -> void:
	_bind()
	hint_label.text = text
	hint_label.tooltip_text = tooltip if not tooltip.is_empty() else TooltipText.wrap_text(text)


## Faction ids in seat order, which pick the player colours: the session's players, or without a
## session the state's faction order (UiPalette.seat_order).
func seat_order() -> Array:
	return UiPalette.seat_order(state, session)


## Asks for the codex entry `key` (a linked number was right-clicked). A host (the game screen)
## listens to codex_requested; with nobody listening (the map preview) the map opens its own codex.
func request_codex(key: String) -> void:
	if not RulesCodex.ENTRIES.has(key):
		return
	if not codex_requested.get_connections().is_empty():
		codex_requested.emit(key)
		return
	if own_codex == null:
		own_codex = load(CODEX_SCENE).instantiate()
		own_codex.name = "Codex"
		var bg := own_codex.get_node_or_null("Background") as PanelContainer
		if bg:
			bg.add_theme_stylebox_override("panel", UiPalette.panel_style())
		add_child(own_codex)
	move_child(own_codex, get_child_count() - 1)
	own_codex.open(key)


## F1 over a linked number opens its codex entry. Only when no host listens: the game screen handles
## F1 itself, for its overlays too. (Esc is the codex panel's own business.)
func _input(event: InputEvent) -> void:
	if not CodexLink.is_open_key(event) or not codex_requested.get_connections().is_empty():
		return
	var key := CodexLink.key_at(get_viewport().gui_get_hovered_control())
	if not key.is_empty():
		get_viewport().set_input_as_handled()
		request_codex(key)


# --- the ruler panel and the sacrifice dialog (M2-6, #34) -----------------------------------------

## Opens the ruler panel over the map: the viewing faction's ruler with every number explained, its
## mandates and the sacrifice button, beside the enemy ruler (read-only). Only in a game with rulers.
func open_ruler_panel() -> void:
	if state == null or not RulerRules.has_rulers(state):
		return
	if ruler_panel == null:
		ruler_panel = RulerPanel.new()
		ruler_panel.codex_requested.connect(request_codex)
		ruler_panel.sacrifice_requested.connect(open_sacrifice_dialog.bind(""))
		ruler_panel.closed.connect(close_sacrifice_dialog)
		add_child(ruler_panel)
	clear_preview()
	ruler_panel.fog_intel = fog_intel  # M5-2: what you know of each rival
	move_child(ruler_panel, get_child_count() - 1)
	ruler_panel.show_for(state, viewing_faction_id, orders if state.find_faction(viewing_faction_id) != null else null)
	_raise_own_codex()


func close_ruler_panel() -> void:
	close_sacrifice_dialog()
	if ruler_panel != null and ruler_panel.visible:
		ruler_panel.close()


## Opens the sacrifice dialog over the ruler panel, previewing `mandate_id` (or the first one possible).
func open_sacrifice_dialog(mandate_id: String = "") -> void:
	if orders == null or state == null or state.find_faction(viewing_faction_id) == null:
		return
	if sacrifice_dialog == null:
		sacrifice_dialog = SacrificeDialog.new()
		sacrifice_dialog.codex_requested.connect(request_codex)
		sacrifice_dialog.confirmed.connect(_on_sacrifice_confirmed)
		add_child(sacrifice_dialog)
	move_child(sacrifice_dialog, get_child_count() - 1)
	sacrifice_dialog.show_for(orders, mandate_id)
	_raise_own_codex()


func close_sacrifice_dialog() -> void:
	if sacrifice_dialog != null and sacrifice_dialog.visible:
		sacrifice_dialog.close()


## Queues a Sacrifice order for the viewing faction. Returns "" or the rules' reason (also shown in the
## panel). Orders the sacrifice made fail are removed and listed in the status line.
func queue_sacrifice(mandate_id: String) -> String:
	var reason := orders.queue_sacrifice(mandate_id)
	if reason.is_empty():
		GameAudio.sfx("sacrifice")
		status_text = "Sacrifice ordered: %s. It resolves first when the turn ends, so your other orders already count on it; click the cross to cancel." % \
			RulerRules.mandate_name(mandate_id)
		status_text += _removed_text(orders.last_removed())
	else:
		status_text = reason
	_orders_changed()
	return reason


func _on_sacrifice_confirmed(mandate_id: String) -> void:
	queue_sacrifice(mandate_id)


## M5-6: opens the cast dialog for `army_id` (an army of yours that holds a caster), showing `ritual` or the first it can
## cast.
func open_cast_dialog(army_id: String, ritual: String = "") -> void:
	if orders == null or state == null or not MagicRules.has_magic(state) or state.find_faction(viewing_faction_id) == null:
		return
	if cast_dialog == null:
		cast_dialog = CastDialog.new()
		cast_dialog.codex_requested.connect(request_codex)
		cast_dialog.confirmed.connect(_on_cast_confirmed)
		cast_dialog.rings_changed.connect(_on_cast_rings)  # M5-8: the board lights the provinces in range and rings the target
		add_child(cast_dialog)
	move_child(cast_dialog, get_child_count() - 1)
	cast_dialog.show_for(orders, army_id, ritual)
	_raise_own_codex()


func close_cast_dialog() -> void:
	if cast_dialog != null and cast_dialog.visible:
		cast_dialog.close()


## M5-6: queues a cast order for the viewing faction. Returns "" or the rules' reason (also in the status line). A move
## given to the casting army is removed, and the status line says so.
func queue_cast(ritual: String, army_id: String, target: String, pay: String = CastOrder.GOLD, size: int = 0) -> String:
	var reason := orders.queue_cast(ritual, army_id, target, pay, size)
	if reason.is_empty():
		GameAudio.sfx("sacrifice")
		status_text = "Ritual ordered: %s. It is cast before anyone moves when the turn ends, and the army holds; click the cross to cancel." % \
			MagicRules.spell_name(ritual)
		status_text += _removed_text(orders.last_removed())
	else:
		status_text = reason
	_orders_changed()
	return reason


func _on_cast_confirmed(ritual: String, army_id: String, target: String, pay: String, size: int) -> void:
	queue_cast(ritual, army_id, target, pay, size)


## M5-8 (§11.2): the cast dialog lights every province in the ritual's range (a gilt wash and a dashed ring) and rings the
## target chosen; an empty list clears them. The 3D board draws the same two sets through its own marks (cast_lit, cast_ringed).
func _on_cast_rings(lit: Array, chosen: String) -> void:
	for id in regions:
		regions[id].set_cast_mark(ProvinceRegion.CAST_RING if id == chosen and not chosen.is_empty() \
			else (ProvinceRegion.CAST_LIT if lit.has(id) else ProvinceRegion.CAST_NONE))
	if arrow_layer != null:
		arrow_layer.queue_redraw()
	_sync_board()


## The provinces the cast dialog lights (in the ritual's range), by id, and the one it rings: for the 3D board's marks.
func cast_lit() -> Dictionary:
	var out := {}
	for id in regions:
		if regions[id].cast_mark == ProvinceRegion.CAST_LIT:
			out[id] = true
	return out


func cast_ringed() -> Dictionary:
	var out := {}
	for id in regions:
		if regions[id].cast_mark == ProvinceRegion.CAST_RING:
			out[id] = true
	return out


## True while the cast dialog is open: a click on the board picks a lit province as the target (select_province asks).
func casting() -> bool:
	return cast_dialog != null and cast_dialog.visible


## " Removed, because they no longer pass: ..." for a list of removed-order lines, "" for none.
func _removed_text(lines: Array) -> String:
	if lines.is_empty():
		return ""
	return " Also removed, because they relied on what changed: %s" % " ".join(lines)


## Keeps the ruler panel in step with set_state(): closed when the map changes player or turn, rebuilt
## otherwise.
func _follow_ruler_panel() -> void:
	if ruler_panel == null or not ruler_panel.visible:
		return
	if ruler_panel.viewing_faction_id != viewing_faction_id or ruler_panel.state == null \
			or ruler_panel.state.current_turn != state.current_turn or not RulerRules.has_rulers(state):
		close_ruler_panel()
		return
	ruler_panel.show_for(state, viewing_faction_id, orders if state.find_faction(viewing_faction_id) != null else null)


## In the map preview the map's own codex sits above the panels it opens from.
func _raise_own_codex() -> void:
	if own_codex != null:
		move_child(own_codex, get_child_count() - 1)


## Selects a province and flashes its region so the eye finds it (e.g. from a turn report line).
func focus_province(province_id: String) -> void:
	select_province(province_id)
	if board != null:
		board.focus_on(province_id)  # M3a.1: the camera glides there, and the land flashes
	var region: ProvinceRegion = regions.get(province_id)
	if region and region.is_inside_tree():
		region.modulate = Color(1.6, 1.6, 1.6)
		create_tween().tween_property(region, "modulate", Color.WHITE, 0.6)


# --- the 3D board (M3a.1) -------------------------------------------------------------------------

## Draws the map as the 3D world `new_board` (a Board3D), or as the 2D regions again with null. The
## board fills the map view under the hover preview; the regions and the 2D arrows are hidden but kept,
## so every API, tooltip and mark still works through them.
func set_board(new_board: Control) -> void:
	_bind()
	if new_board == board:
		return
	if board != null and is_instance_valid(board):
		board.get_parent().remove_child(board)
		board.queue_free()
	board = new_board
	map_canvas.visible = board == null
	arrow_layer.visible = board == null
	if board != null:
		map_view.add_child(board)
		map_view.move_child(board, 0)
		board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		board.map = self
		if board.has_signal("closeup_changed"):
			board.closeup_changed.connect(func(_pid): _show_details())
		_apply_map_mode()
		_sync_board()


func _sync_board() -> void:
	if board != null:
		board.sync()


# --- layout ---------------------------------------------------------------------------------------

## Finds the scene's nodes and wires their signals, once.
func _bind() -> void:
	if map_view != null:
		return
	map_view = %MapView
	map_canvas = %MapCanvas
	details = %Details
	faction_label = %FactionLabel
	gold_label = %GoldLabel
	turn_label = %TurnLabel
	hint_label = get_node("Layout/TopBar/Row/Hint")
	back_button = %BackButton
	# The crest: the faction's banner with the seat emblem pinned to its lower right corner.
	faction_crest = Control.new()
	faction_crest.name = "FactionCrest"
	faction_crest.custom_minimum_size = Vector2(46, 46)
	faction_crest.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	faction_crest.mouse_filter = Control.MOUSE_FILTER_IGNORE
	faction_crest.visible = false
	faction_banner = Art.banner_card("", 46.0)
	faction_banner.name = "FactionBanner"
	faction_banner.position = Vector2(-2, 0)
	faction_banner.size = Vector2(31, 46)
	faction_crest.add_child(faction_banner)
	faction_emblem = SeatEmblem.new(-1, SeatEmblem.Look.TOKEN, 22.0)
	faction_emblem.name = "FactionEmblem"
	faction_emblem.visible = false
	faction_emblem.position = Vector2(24, 23)
	faction_crest.add_child(faction_emblem)
	faction_label.get_parent().add_child(faction_crest)
	faction_label.get_parent().move_child(faction_crest, 0)
	# A slightly tighter top bar than the scene's, so the banner fits and the hint keeps two full lines
	# even with the game screen's Ruler button.
	var bar_row := back_button.get_parent() as HBoxContainer
	bar_row.add_theme_constant_override("separation", 12)
	for l: Label in [faction_label, gold_label, turn_label]:
		l.add_theme_font_size_override("font_size", 19)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	map_view.resized.connect(_fit_map)
	(map_view as ColorRect).color = SEA_DEEP
	map_canvas.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	map_canvas.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	map_canvas.draw.connect(_draw_links)
	back_button.pressed.connect(_on_back_pressed)
	# Order arrows sit above the map canvas (same transform, see _fit_map) so regions don't hide them.
	arrow_layer = Control.new()
	arrow_layer.name = "OrderArrows"
	arrow_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arrow_layer.size = MapLayout.SIZE
	arrow_layer.draw.connect(_draw_order_arrows)
	map_view.add_child(arrow_layer)
	# Hover preview bar along the bottom of the map; grows upwards with its text.
	hover_panel = PanelContainer.new()
	hover_panel.name = "HoverPreview"
	hover_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_panel.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UiPalette.PANEL_BG, 0.94)
	style.border_color = UiPalette.GILT
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	hover_panel.add_theme_stylebox_override("panel", style)
	hover_panel.anchor_left = 0.0
	hover_panel.anchor_right = 1.0
	hover_panel.anchor_top = 1.0
	hover_panel.anchor_bottom = 1.0
	hover_panel.offset_left = 16
	hover_panel.offset_right = -16
	hover_panel.offset_top = -16
	hover_panel.offset_bottom = -16
	hover_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	map_view.add_child(hover_panel)
	_build_vision()
	hover_label = Label.new()
	hover_label.name = "HoverLabel"
	hover_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hover_label.add_theme_font_size_override("font_size", 17)
	hover_label.add_theme_color_override("font_color", UiPalette.TEXT_PRIMARY)
	hover_panel.add_child(hover_label)


## M5-2: the Vision button at the map's upper right (fog games only) and the legend it opens under it.
func _build_vision() -> void:
	vision_button = Button.new()
	vision_button.name = "VisionButton"
	vision_button.text = "Vision"
	vision_button.toggle_mode = true
	vision_button.focus_mode = Control.FOCUS_NONE
	vision_button.visible = false
	vision_button.add_theme_font_size_override("font_size", 16)
	vision_button.anchor_left = 1.0
	vision_button.anchor_right = 1.0
	vision_button.offset_left = -150
	vision_button.offset_right = -12
	vision_button.offset_top = 10
	vision_button.offset_bottom = 46
	vision_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	vision_button.tooltip_text = TooltipText.plain("Vision", "Show what you can see: every province in clear sight, glimpsed, out of sight or never seen, with what each mark means. Hover a province for why you see it, or what you remember of it. Click again to go back to the map.")
	vision_button.toggled.connect(func(on: bool): set_map_mode("vision" if on else ""))
	CodexLink.attach(vision_button, "sight", request_codex)
	map_view.add_child(vision_button)
	vision_legend = PanelContainer.new()
	vision_legend.name = "VisionLegend"
	vision_legend.visible = false
	vision_legend.mouse_filter = Control.MOUSE_FILTER_PASS
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UiPalette.PANEL_BG, 0.94)
	style.border_color = UiPalette.PANEL_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	vision_legend.add_theme_stylebox_override("panel", style)
	vision_legend.anchor_left = 1.0
	vision_legend.anchor_right = 1.0
	vision_legend.offset_left = -282
	vision_legend.offset_right = -12
	vision_legend.offset_top = 54
	vision_legend.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	map_view.add_child(vision_legend)
	var box := VBoxContainer.new()
	box.name = "Rows"
	box.add_theme_constant_override("separation", 6)
	vision_legend.add_child(box)


## M5-2: the Vision legend's rows (FogView.legend_rows), each with its swatch: the veil as the 2D map draws it.
func _fill_vision_legend() -> void:
	var box := vision_legend.get_node("Rows") as VBoxContainer
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	var title := Label.new()
	title.text = "Vision: what you can see"
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", UiPalette.GILT)
	box.add_child(title)
	for row in FogView.legend_rows(state):
		var line := HBoxContainer.new()
		line.name = "Row_%s" % String(row.key)
		line.add_theme_constant_override("separation", 8)
		line.mouse_filter = Control.MOUSE_FILTER_PASS
		box.add_child(line)
		var swatch := ProvinceRegion.legend_swatch(String(row.key))
		line.add_child(swatch)
		var l := Label.new()
		l.text = "%s: %s" % [String(row.title), String(row.short)]
		l.add_theme_font_size_override("font_size", 15)
		l.add_theme_color_override("font_color", UiPalette.TEXT_PRIMARY)
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		l.tooltip_text = TooltipText.plain(String(row.title), "%s %s" % [String(row.text), RulesCodex.text(String(row.codex))])
		CodexLink.attach(l, String(row.codex), request_codex)
		line.add_child(l)


## Scales the design-space canvas to fit the map view, centred, keeping its aspect ratio.
func _fit_map() -> void:
	var avail := map_view.size
	if avail.x <= 0 or avail.y <= 0:
		return
	var s: float = min(avail.x / MapLayout.SIZE.x, avail.y / MapLayout.SIZE.y)
	map_canvas.scale = Vector2(s, s)
	map_canvas.position = (avail - MapLayout.SIZE * s) / 2.0
	arrow_layer.scale = map_canvas.scale
	arrow_layer.position = map_canvas.position


## The board under the regions: sea and shallows, the landmass with its inked coast and land bridges,
## the roads between neighbouring provinces, and each province's drop shadow.
func _draw_links() -> void:
	if state == null:
		return
	var links := road_links()
	_draw_waves(links)
	# Shallows, then the coast keyline, then the land: each layer is opaque, so overlaps never show.
	for i in SHALLOW_GROW.size():
		var colour: Color = SEA_DEEP.lerp(SEA, 0.55 + 0.45 * i)
		_draw_land_layer(links, SHALLOW_GROW[i], LAND_BRIDGE * (2.3 - 0.5 * i), colour, null)
	_draw_land_layer(links, LAND_GROW + 0.04, LAND_BRIDGE + 8.0, UiPalette.MAP_INK, null)
	_draw_land_layer(links, LAND_GROW, LAND_BRIDGE, LAND_TINT, Art.terrain("plains"))
	for l in links:
		map_canvas.draw_line(l[0], l[1], Color(UiPalette.MAP_INK, 0.85), 11.0, true)
		map_canvas.draw_line(l[0], l[1], ROAD.darkened(0.08), 6.0, true)
		map_canvas.draw_dashed_line(l[0], l[1], ROAD.lightened(0.3), 2.0, 9.0, true)
	for p in state.provinces:
		if MapLayout.has_position(p.id):
			var shadow := MapLayout.region_polygon(p.id, MapLayout.position_of(p.id) + Vector2(4, 7), MapLayout.radius_of(p))
			map_canvas.draw_colored_polygon(shadow, Color(UiPalette.KEYLINE_INK, 0.42))


## Every road between two placed provinces once, as [from, to] in design space.
func road_links() -> Array:
	var out := []
	if state == null:
		return out
	for p in state.provinces:
		for n in p.neighbors:
			if p.id < n and MapLayout.has_position(p.id) and MapLayout.has_position(n):
				out.append([MapLayout.position_of(p.id), MapLayout.position_of(n)])
	return out


## One layer of the landmass: every province grown by `grow`, and a band `bridge` wide along every road,
## in `colour` (multiplying `texture`, tiled across the board, when there is one).
func _draw_land_layer(links: Array, grow: float, bridge: float, colour: Color, texture: Texture2D) -> void:
	var shapes := []
	for p in state.provinces:
		if MapLayout.has_position(p.id):
			shapes.append(MapLayout.region_polygon(p.id, MapLayout.position_of(p.id), MapLayout.radius_of(p) * grow))
	for l in links:
		var a: Vector2 = l[0]
		var b: Vector2 = l[1]
		var n := (b - a).normalized().orthogonal() * bridge / 2.0
		shapes.append(PackedVector2Array([a + n, b + n, b - n, a - n]))
	for poly: PackedVector2Array in shapes:
		if texture == null:
			map_canvas.draw_colored_polygon(poly, colour)
			continue
		var uvs := PackedVector2Array()
		for pt in poly:
			uvs.append(pt / LAND_TILE)
		map_canvas.draw_colored_polygon(poly, colour, uvs, texture)


## Small cel wave marks on the open sea, on a jittered grid that keeps clear of the land. Deterministic,
## so the board never shimmers between redraws.
func _draw_waves(links: Array) -> void:
	var colour := Color(SEA.lightened(0.25), 0.45)
	for gx in range(-8, 26):
		for gy in range(-4, 16):
			var h := absi(hash(Vector2i(gx, gy)))
			var at := Vector2(gx * 52.0 + float(h % 23), gy * 46.0 + float((h / 23) % 19))
			if (gx + gy) % 2 == 0 or not _open_sea(at, links):
				continue
			var r := 7.0 + float(h % 4)
			map_canvas.draw_arc(at, r, PI * 1.15, PI * 1.85, 8, colour, 2.0, true)
			map_canvas.draw_arc(at + Vector2(r * 1.25, 0), r, PI * 1.15, PI * 1.85, 8, colour, 2.0, true)


func _open_sea(at: Vector2, links: Array) -> bool:
	for p in state.provinces:
		if MapLayout.has_position(p.id) and at.distance_to(MapLayout.position_of(p.id)) < MapLayout.radius_of(p) * 1.95:
			return false
	for l in links:
		if Geometry2D.get_closest_point_to_segment(at, l[0], l[1]).distance_to(at) < LAND_BRIDGE * 1.4:
			return false
	return true


# --- top bar --------------------------------------------------------------------------------------

func _update_top_bar() -> void:
	var f := state.find_faction(viewing_faction_id)
	var seats := seat_order()
	var seat := seats.find(viewing_faction_id)
	faction_label.text = f.faction_name if f else "Spectator"
	faction_label.add_theme_color_override("font_color", UiPalette.owner_color(state, viewing_faction_id, seats).lightened(0.25))
	faction_label.tooltip_text = ""
	CodexLink.detach(faction_label)
	faction_emblem.seat = seat
	faction_emblem.visible = f != null and seat >= 0
	faction_banner.texture = Art.banner(viewing_faction_id) if f else null
	faction_crest.visible = f != null
	if f:
		var colour := "" if seat < 0 else " You are Player %d: your provinces and armies are drawn in %s, with a %s emblem." % [
			seat + 1, UiPalette.seat_color_name(seat), SeatEmblem.shape_of(seat)]
		var fog_line := " Fog of war is on: you see exactly only your own land and armies, the rest roughly or as you last saw it." \
			if FogView.active(state) else ""
		faction_label.tooltip_text = TooltipText.plain("You are playing %s" % faction_label.text,
			"The map, gold and forecasts are shown from this faction's point of view.%s%s" % [colour, fog_line])
		CodexLink.attach(faction_label, TooltipText.codex_for("faction"), request_codex)
	# Without a faction (game over, spectator) the gold label is hidden, so the bar has no empty gap.
	gold_label.visible = f != null
	if f:
		var g := Breakdown.gold(state, viewing_faction_id)
		var income: int = g.total - f.gold
		gold_label.text = "Gold %d   (+%d per turn)" % [f.gold, income]
		gold_label.tooltip_text = TooltipText.from_breakdown(g)
		CodexLink.attach(gold_label, TooltipText.codex_for("gold", g), request_codex)
	else:
		gold_label.text = ""
		gold_label.tooltip_text = ""
		CodexLink.detach(gold_label)
	# Breakdown.turn is 1-based like every turn players see: its title is the label.
	var t := Breakdown.turn(state)
	turn_label.text = String(t.title)
	turn_label.tooltip_text = TooltipText.from_breakdown(t)
	CodexLink.attach(turn_label, TooltipText.codex_for("turn", t), request_codex)


# --- side panel -----------------------------------------------------------------------------------

# --- orders (issue #6) ----------------------------------------------------------------------------

## Queues a move for the viewing faction. Returns "" or the rules' reason (also shown in the panel).
func queue_move(army_id: String, to_province: String) -> String:
	var reason := orders.queue_move(army_id, to_province)
	status_text = reason if not reason.is_empty() else "Move ordered. Armies move when the turn ends; click the cross to cancel."
	if reason.is_empty() and not orders.last_relief.is_empty():  # M3c: the garrison comes out to join the relief
		var place := state.find_province(to_province).name
		status_text = "Relief ordered: it marches into %s when the turn ends, and the garrison comes out to join it: %s. Untick them in %s's fort panel to keep them in." % [
			place, RulerRules._and_list(orders.last_relief.map(func(id): return TurnReportText.army_name(state, id))), place]
	elif reason.is_empty() and orders.siege_kind(army_id, to_province) == "besiege":
		status_text = "Move ordered: it besieges %s when the turn ends. Tick Storm now on the order to storm from the march instead." % state.find_province(to_province).name
	_order_sound(reason, "march")
	_orders_changed()
	return reason


## Queues one recruit at the capital. Returns "" or the rules' reason (also shown in the panel).
func queue_recruit(unit_type_id: String) -> String:
	var reason := orders.queue_recruit(unit_type_id)
	status_text = reason if not reason.is_empty() else "Recruit ordered. It is paid and joins at your capital when the turn ends."
	_order_sound(reason, "recruit")
	_orders_changed()
	return reason


## Queues one recruit with the ruler (Warband Muster). Returns "" or the rules' reason.
func queue_recruit_with_ruler(unit_type_id: String) -> String:
	var reason := orders.queue_recruit_with_ruler(unit_type_id)
	status_text = reason if not reason.is_empty() else "Recruit ordered. It is paid and joins %s where it ends the turn, if you own that province then." % \
		RulerRules.current_name(state, viewing_faction_id)
	_order_sound(reason, "recruit")
	_orders_changed()
	return reason


## M3c S-3: queues one recruit at the fort `at` ("" for the capital). Returns "" or the rules' reason.
func queue_recruit_at(unit_type_id: String, at: String) -> String:
	var reason := orders.queue_recruit(unit_type_id, at)
	var place := state.find_province(at)
	status_text = reason if not reason.is_empty() else "Recruit ordered. It is paid and joins your armies at %s when the turn ends." % (
		place.name if place != null else "your capital")
	_order_sound(reason, "recruit")
	_orders_changed()
	return reason


## M3c S-3: queues a Fortify order for `province_id` (the fort panel's Fortify or Upgrade). "" or the reason.
func queue_fortify(province_id: String) -> String:
	var reason := orders.queue_fortify(province_id)
	if reason.is_empty():
		var fc := orders.fortify_preview(province_id)
		status_text = "Fortify ordered: %s at %s stands at the end of turn %d if no enemy army stands there, and takes recruits from turn %d. Click the cross to cancel." % [
			SiegeRules.fort_phrase(int(fc.level)), state.find_province(province_id).name, int(fc.stands), int(fc.recruit_from)]
	else:
		status_text = reason
	_order_sound(reason, "")
	_orders_changed()
	return reason


## M3c S-3: the Storm toggle (fort panel, or Storm now on a move): storm `province_id` this turn, or wait.
func set_storm(province_id: String, on: bool) -> String:
	var reason := orders.set_storm(province_id, on)
	var place := state.find_province(province_id).name
	if reason.is_empty():
		status_text = ("Storm ordered: every army of yours at %s attacks its garrison when the turn ends. Untick it to wait instead." if on \
			else "Storm cancelled: your armies wait at %s, and the walls keep dropping.") % place
		if not on:
			status_text += _removed_text(orders.last_removed())
	else:
		status_text = reason
	_order_sound(reason, "")
	_orders_changed()
	return reason


## M3c S-3: a Sally tick: `army_id` comes out of its besieged fort this turn (on), or stays inside.
func set_sally(army_id: String, on: bool) -> String:
	var reason := orders.set_sally(army_id, on)
	var name := TurnReportText.army_name(state, army_id)
	if reason.is_empty():
		status_text = ("Sally ordered: %s comes out when the turn ends and fights the siege lines in the open. Untick it to stay inside." if on \
			else "%s stays inside the walls.") % (name if on else RulerRules._cap(name))
	else:
		status_text = reason
	_order_sound(reason, "")
	_orders_changed()
	return reason


## Sends the road move at `index` through its next legal province (King's Roads).
func change_via(index: int) -> void:
	var reason := orders.change_via(index)
	status_text = reason if not reason.is_empty() else "Road move changed: it now goes the other way. It moved to the end of your orders."
	_order_sound(reason, "")
	_orders_changed()


func cancel_order(index: int) -> void:
	var reason := orders.cancel(index)
	status_text = reason if not reason.is_empty() else "Order cancelled." + _removed_text(orders.last_removed())
	if reason.is_empty():
		GameAudio.sfx("order_cancelled")
	_orders_changed()


## An accepted order (`reason` empty): order_queued, then `follow` (march, recruit) just after it.
func _order_sound(reason: String, follow: String) -> void:
	if not reason.is_empty():
		return
	GameAudio.sfx("order_queued")
	if not follow.is_empty():
		GameAudio.sfx(follow, 0.12)


func _orders_changed() -> void:
	if arrow_layer:
		arrow_layer.queue_redraw()
	clear_preview()
	_update_map_marks()
	_show_details()
	if ruler_panel != null and ruler_panel.visible:
		ruler_panel.refresh()  # a queued or cancelled sacrifice shows there
	_sync_board()
	orders_changed.emit()


## The map marks that follow the orders: King's Roads destinations for the selected army and the
## provinces Sworn Vassals will take (both from the rules, through OrdersController).
func _update_map_marks() -> void:
	_update_road_targets()
	_update_vassal_marks()
	_update_province_rule_marks()
	_update_fortify_ghosts()


## M3c S-3: a scaffold ghost on the plate of each province the viewer has a Fortify order for. Only the viewer's
## own orders: another seat's never show.
func _update_fortify_ghosts() -> void:
	if state == null or orders == null or not state.sieges:
		return
	for id in regions:
		var i := orders.fortify_index(id)
		regions[id].set_fortify_ghost(i >= 0, orders.order_texts()[i] if i >= 0 else "")


## With one of your armies selected, marks every province two steps away that a click would reach by
## the King's Roads (OrdersController.road_destinations), naming the way through.
func _update_road_targets() -> void:
	if state == null or orders == null:
		return
	var targets := {}
	var army := state.find_army(selected_army_id)
	if army != null and army.owner == viewing_faction_id:
		targets = orders.road_destinations(army.id)
	for id in regions:
		var vias: Array = targets.get(id, [])
		var via_name := ""
		var rule := "King's Roads"
		if not vias.is_empty():
			via_name = state.find_province(vias[0]).name
			rule = orders.road_rule_name(army.id, id, vias[0])  # M4-2: or Forest Stride
		regions[id].set_road_target(not vias.is_empty(), via_name, rule)


## Marks the province each faction's Sworn Vassals will take at the end of the turn (Forecast.vassal,
## counting your queued moves), with the forecast in its tooltip.
func _update_vassal_marks() -> void:
	if state == null or orders == null:
		return
	var marks := {}  # province id -> [forecast]
	for v in orders.vassal_forecasts():
		if String(v.province).is_empty():
			continue
		if not marks.has(v.province):
			marks[v.province] = []
		marks[v.province].append(v)
	var seats := seat_order()
	for id in regions:
		var list: Array = marks.get(id, [])
		if list.is_empty():
			regions[id].set_vassal_mark(-2, "")
			continue
		var texts := []
		for v in list:
			texts.append(v.text)
		# Two factions after one province: it joins nobody, so the mark is the neutral one.
		var seat := -1 if list.size() > 1 else UiPalette.seat_index(state, list[0].faction, seats)
		regions[id].set_vassal_mark(seat, TooltipText.plain("Sworn Vassals", " ".join(texts) + " " + RulesCodex.text("mandate_sworn_vassals")))


## The transformations' province rules (M4-2, §9.4): a sprout on each province the Wild Spreads grows at
## the end of the turn, and the heal forecast on each army Hallowed Land or the Forges heals, from
## OrdersController.province_rule_forecasts (the rules' own picks).
func _update_province_rule_marks() -> void:
	if state == null or orders == null:
		return
	var wild := {}  # province id -> [forecast texts]
	for pr in orders.province_rule_forecasts():
		for pick in pr.spread:
			if not wild.has(pick.province):
				wild[pick.province] = []
			wild[pick.province].append(String(pick.text))
		for army_id in pr.by_army:
			var a := state.find_army(String(army_id))
			if a != null and regions.has(a.location):
				regions[a.location].set_heal_note(String(army_id), String(pr.by_army[army_id].text))
	for id in regions:
		var texts: Array = wild.get(id, [])
		regions[id].set_wild_mark("" if texts.is_empty() else TooltipText.plain("The Wild Spreads",
			" ".join(texts) + " " + RulesCodex.text("wild_spreads")))


## One arrow per queued move, from the army's province to its destination. A road move (King's Roads)
## bends through the province it goes through, which gets a small ring.
func _draw_order_arrows() -> void:
	if orders == null or state == null:
		return
	for o in orders.orders():
		if not (o is MoveOrder):
			continue
		var army := state.find_army(o.army_id)
		if army == null or not MapLayout.has_position(army.location) or not MapLayout.has_position(o.to):
			continue
		var a := MapLayout.position_of(army.location)
		var b := MapLayout.position_of(o.to)
		if o.is_road_move() and MapLayout.has_position(o.via) and state.find_province(o.via) != null:
			var v := _via_bend(a, b, o.via)
			var first := (v - a).normalized()
			_draw_shaft(a + first * 34.0, v)
			arrow_layer.draw_circle(v, 12.0, UiPalette.KEYLINE_HALO)
			arrow_layer.draw_circle(v, 8.0, UiPalette.SELECTION)
			arrow_layer.draw_circle(v, 4.0, UiPalette.GILT)
			a = v
		var dir := (b - a).normalized()
		var side := Vector2(-dir.y, dir.x)
		var start := a + dir * (14.0 if o.is_road_move() else 34.0)
		var tip := b - dir * 34.0
		var base := tip - dir * 26.0
		_draw_shaft(start, base)
		arrow_layer.draw_colored_polygon(PackedVector2Array([tip + dir * 3.0, base + side * 17.0, base - side * 17.0]), UiPalette.KEYLINE_HALO)
		arrow_layer.draw_colored_polygon(PackedVector2Array([tip, base + side * 13.0, base - side * 13.0]), UiPalette.SELECTION)


## Where a road move's arrow bends inside the province it goes through: off its centre, towards the
## side the arrow comes from and goes to, so the province's name and income stay readable.
func _via_bend(from: Vector2, to: Vector2, via_id: String) -> Vector2:
	var centre := MapLayout.position_of(via_id)
	var r := MapLayout.radius_of(state.find_province(via_id))
	var toward := ((from + to) / 2.0) - centre
	if toward.length() < 1.0:
		toward = Vector2(0, 1)  # straight through: pass below the labels instead
	return centre + toward.normalized() * r * 0.72


func _draw_shaft(from: Vector2, to: Vector2) -> void:
	arrow_layer.draw_line(from, to, UiPalette.KEYLINE_HALO, 13.0, true)
	arrow_layer.draw_line(from, to, UiPalette.SELECTION, 7.0, true)


## The orders list under the province details: each order with its forecast and a cancel button,
## live gold after recruits, and recruit buttons when your capital is selected.
func _add_orders_section() -> void:
	var f: Faction = state.find_faction(viewing_faction_id) if state else null
	if orders == null or f == null:
		return
	details.add_child(HSeparator.new())
	_add_heading("Your orders this turn", 20)
	if not status_text.is_empty():
		var status := _add_text(status_text, TooltipText.plain("Order check",
			"Orders are checked with the same rules the turn uses, so a refused order would fail at the end of the turn too."), UiPalette.GILT)
		status.name = "StatusLabel"
		_link(status, "order_check")
	var texts := orders.order_texts()
	if texts.is_empty():
		_add_text("No orders yet. Select one of your armies, then click a neighboring province to move it there. Select your capital to recruit.",
			"", UiPalette.TEXT_SECONDARY)
	for i in texts.size():
		var row := HBoxContainer.new()
		row.name = "Order_%d" % i
		details.add_child(row)
		var line := _add_text(texts[i], TooltipText.from_breakdown(orders.order_breakdown(i)), UiPalette.TEXT_PRIMARY, row)
		line.name = "OrderLine"
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.custom_minimum_size.x = 300
		_link(line, orders.order_codex_kind(i))
		var vias := orders.road_vias_at(i)
		if vias.size() > 1:
			# King's Roads: the first way through is picked by province id; the player can choose another.
			var o: MoveOrder = orders.orders()[i]
			var next: String = vias[(vias.find(o.via) + 1) % vias.size()]
			var via_button := Button.new()
			via_button.name = "ViaButton"
			via_button.text = "↻"
			via_button.tooltip_text = TooltipText.plain("Another way through",
				"This road move goes through %s. Click to go through %s instead; it arrives at the same time either way. %s" % [
					state.find_province(o.via).name, state.find_province(next).name, RulesCodex.text("road_move")])
			via_button.focus_mode = Control.FOCUS_NONE
			via_button.pressed.connect(change_via.bind(i))
			_link(via_button, "road_move")
			row.add_child(via_button)
		var besieged := orders.storm_target(i)
		if not besieged.is_empty():  # M3c S-3: Besiege, or Storm now, on a line of its own under the order
			var sub := HBoxContainer.new()
			sub.name = "StormNowRow_%d" % i
			var pad := Control.new()
			pad.custom_minimum_size = Vector2(16, 0)
			sub.add_child(pad)
			sub.add_child(_storm_now_toggle(besieged))
			details.add_child(sub)
			details.move_child(sub, row.get_index() + 1)
		var cancel := Button.new()
		cancel.name = "CancelButton"
		cancel.text = "✕"
		cancel.tooltip_text = "Cancel this order. Nothing happens until the turn ends, so you can change your mind."
		cancel.focus_mode = Control.FOCUS_NONE
		cancel.pressed.connect(cancel_order.bind(i))
		row.add_child(cancel)
	var g := orders.gold_after_recruits()
	var gold := _add_text("%s: %d" % ["Gold after recruits and rituals" if int(g.get("rituals", 0)) > 0 else "Gold after recruits", g.gold_after],
		TooltipText.from_breakdown(orders.gold_breakdown()), UiPalette.GILT)
	gold.name = "GoldAfterLabel"
	_link(gold, "gold_after_recruits")
	if state.sieges:
		_add_fort_recruit_section(f)  # M3c S-3: recruit at any fort you own
	elif selected_province_id == f.capital:
		var capital := state.find_province(f.capital)
		_add_heading("Recruit at %s" % capital.name, 18)
		_add_fortress_view_button(f.capital)
		for ut in orders.recruitable_types():
			var b := Button.new()
			b.name = "Recruit_%s" % ut.id.validate_node_name()
			b.text = "Recruit %s (%d gold)" % [ut.name, orders.recruit_cost(ut.id)]
			b.tooltip_text = TooltipText.from_breakdown(orders.recruit_breakdown(ut.id))
			_link(b, "recruit")
			_style_unit_button(b, ut.id, f.id)
			b.pressed.connect(queue_recruit.bind(ut.id))
			details.add_child(b)
			_add_rank_warning(ut.id, "")  # M5-8
	_add_ruler_recruit_section()


## M5-8 (§3.2, §11.2): under a recruit button, "This army will have 8 second-rank and 6 front-rank fighters: its second rank is
## exposed", when recruiting it would leave the army's second rank exposed (MagicView.recruit_warning). Nothing otherwise.
func _add_rank_warning(unit_type_id: String, at: String) -> void:
	var rank := MagicView.recruit_warning(orders.view_state(), viewing_faction_id, unit_type_id, at, orders.orders())
	if rank.is_empty():
		return
	var warn := _add_text(rank, TooltipText.plain("Exposed second rank", "%s %s" % [rank, RulesCodex.text("trait_mage")]), UiPalette.GILT)
	warn.name = "RecruitExposed_%s" % unit_type_id.validate_node_name()
	warn.add_theme_font_size_override("font_size", 15)
	warn.set_meta("rule_text", true)
	CodexLink.attach(warn, "trait_mage", request_codex)


## M3a.2: on the 3D board, "View fortress" swoops the camera into the capital's muster yard, where each
## queued recruit appears at once as a ghost in its slot (and back to the map when the view is open).
func _add_fortress_view_button(capital_id: String) -> void:
	if board == null or not board.has_method("can_closeup") or not board.can_closeup(capital_id):
		return
	var open: bool = String(board.closeup) == capital_id
	var b := Button.new()
	b.name = "ViewFortressButton"
	b.text = "Back to the map (Esc)" if open else "View fortress: see your muster yard"
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 16)
	b.add_theme_color_override("font_color", UiPalette.GILT)
	b.tooltip_text = TooltipText.plain("View fortress",
		"A close look at %s's muster yard. Your armies stand there a block to a slot, facing the gate, and each recruit you queue below appears at once as a translucent figure in the slot it will take. An army the yard can't hold musters in the war camp outside the walls. Esc or zooming out goes back to the map." % state.find_province(capital_id).name)
	b.pressed.connect(func():
		if String(board.closeup) == capital_id:
			board.exit_closeup()
		else:
			board.enter_closeup(capital_id))
	details.add_child(b)


## Warband Muster (§1.4): with the Ninth Fang's province selected, a "Recruit with the Ninth Fang"
## section: how many recruits are left this turn and one button per regular unit, at the same prices.
func _add_ruler_recruit_section() -> void:
	var info := orders.ruler_recruit_info()
	if not info.get("ok", false) or selected_province_id != info.province:
		return
	var heading := _add_heading("Recruit with %s" % info.ruler, 18)
	heading.name = "RulerRecruitHeading"
	var left := _add_text("%d of %d left this turn (Warband Muster). They join your armies here at the end of the turn, even if %s moves on." % [
		info.left, info.limit, info.ruler],
		TooltipText.plain("Recruit with %s" % info.ruler, info.text), UiPalette.TEXT_SECONDARY)
	left.name = "RulerRecruitLeft"
	_link(left, "field_recruit")
	for ut in orders.recruitable_types():
		var b := Button.new()
		b.name = "RecruitWithRuler_%s" % ut.id.validate_node_name()
		b.text = "Recruit %s with %s (%d gold)" % [ut.name, info.ruler, orders.recruit_cost(ut.id)]
		b.tooltip_text = TooltipText.from_breakdown(orders.recruit_breakdown(ut.id, RecruitOrder.AT_RULER))
		_link(b, "field_recruit")
		_style_unit_button(b, ut.id, viewing_faction_id)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.disabled = info.left <= 0
		b.pressed.connect(queue_recruit_with_ruler.bind(ut.id))
		details.add_child(b)


## A recruit button: the unit's portrait (its face) at the left, then "Recruit <unit> (<cost> gold)",
## on a raised card that lights its border gilt on hover. M5-2: under fog a scout says so on its card.
func _style_unit_button(b: Button, unit_type_id: String, faction_id: String) -> void:
	if FogView.active(state):
		var f := state.find_faction(faction_id)
		for ut in (f.unit_types if f != null else []):
			if ut.id == unit_type_id and not FogView.scout_line(ut).is_empty():
				b.tooltip_text += "\n\n" + TooltipText.wrap_text("%s %s" % [FogView.scout_line(ut), RulesCodex.text("scouts")])
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, ROW_PORTRAIT.y + 10)
	b.icon = Art.face(Art.unit_portrait(state, faction_id, unit_type_id))
	b.expand_icon = false
	b.add_theme_constant_override("icon_max_width", int(ROW_PORTRAIT.x))
	b.add_theme_constant_override("h_separation", 12)
	b.add_theme_font_size_override("font_size", 17)
	b.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	for state_name in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = UiPalette.PANEL_RAISED.lightened(0.06 if state_name == "hover" else 0.0)
		sb.border_color = UiPalette.GILT if state_name in ["hover", "pressed"] else UiPalette.PANEL_BORDER
		sb.set_border_width_all(2 if state_name in ["hover", "pressed"] else 1)
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 5
		sb.content_margin_right = 10
		sb.content_margin_top = 5
		sb.content_margin_bottom = 5
		if state_name == "disabled":
			sb.bg_color = UiPalette.PANEL_BG
		b.add_theme_stylebox_override(state_name, sb)
	b.add_theme_color_override("font_hover_color", UiPalette.GILT)
	b.add_theme_color_override("icon_disabled_color", Color(1, 1, 1, 0.4))


## M3c S-3: "Fort: Keep" (linked to the level's own entry), then the fort section (FortPanel) in a frame.
func _add_fort_section(p: Province) -> void:
	var level_key: String = String(SiegeRules.level_data(p.fort_level).id) if p.fort_level > 0 else "fort_levels"
	var text := "Fort: %s" % (SiegeRules.level_name(p.fort_level) if p.fort_level > 0 else "none")
	var fort_label := _add_text(text, TooltipText.plain(text, RulesCodex.text(level_key)))
	fort_label.name = "FortLabel"
	CodexLink.attach(fort_label, level_key, request_codex)
	var panel := FortPanel.make(self, p.id)
	if panel == null:
		return
	var frame := PanelContainer.new()
	frame.name = "FortFrame"
	var style := StyleBoxFlat.new()
	style.bg_color = UiPalette.PANEL_RAISED
	style.border_color = UiPalette.PANEL_BORDER
	style.border_width_left = 3
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	frame.add_theme_stylebox_override("panel", style)
	frame.add_child(panel)
	details.add_child(frame)


## M3c S-3: "Recruit at <fort>": a picker of every fort you own (each with its count this turn, greyed with the
## rules' reason when it can't take recruits), then the recruit buttons for the fort selected on the map.
func _add_fort_recruit_section(f: Faction) -> void:
	var places := orders.recruit_places()
	var here := places.filter(func(r): return r.province == selected_province_id)
	if here.is_empty():
		return
	var place: Dictionary = here[0]
	var heading := _add_heading("Recruit at %s" % place.name, 18)
	heading.name = "RecruitHeading"
	heading.tooltip_text = TooltipText.plain("Recruit at", RulesCodex.text("recruit_at_forts"))
	heading.mouse_filter = Control.MOUSE_FILTER_PASS
	_link(heading, "recruit_at")
	var picker := VBoxContainer.new()
	picker.name = "RecruitAtPicker"
	picker.add_theme_constant_override("separation", 2)
	details.add_child(picker)
	for r in places:
		var b := Button.new()
		b.name = "RecruitAt_%s" % String(r.province).validate_node_name()
		b.toggle_mode = true
		b.button_pressed = r.province == selected_province_id
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 16)
		var level := SiegeRules.level_word(int(r.level))
		b.text = "%s (%s): %d of %d this turn" % [r.name, level, int(r.count), int(r.limit)]
		var limit := Breakdown.recruit_limit(state, String(r.province), viewing_faction_id, orders.orders())
		var tip := TooltipText.from_breakdown(limit)
		if not r.ok:
			b.disabled = true
			tip = TooltipText.plain("%s can't take recruits" % r.name, String(r.reason)) + "\n\n" + tip
		else:
			tip = TooltipText.plain("Recruit at %s" % r.name, "Click to recruit here: the buttons below make their recruits at %s, and they join your armies there." % r.name) + "\n\n" + tip
		b.tooltip_text = tip
		_link(b, "recruit_at")
		var pid := String(r.province)
		b.pressed.connect(func(): select_province(pid))
		picker.add_child(b)
		if not r.ok:
			var why := _add_text(String(r.reason), TooltipText.plain("Why not", String(r.reason)), UiPalette.NEGATIVE.lightened(0.25), picker)
			why.name = "RecruitAtReason_%s" % pid.validate_node_name()
			why.add_theme_font_size_override("font_size", 15)
	if place.province == f.capital:
		_add_fortress_view_button(f.capital)
	if not place.ok:
		return
	var at: String = "" if place.province == f.capital else String(place.province)
	for ut in orders.recruitable_types_at(String(place.province)):
		var b := Button.new()
		b.name = "Recruit_%s" % ut.id.validate_node_name()
		b.text = "Recruit %s (%d gold)" % [ut.name, orders.recruit_cost(ut.id)]
		var tip := TooltipText.from_breakdown(orders.recruit_breakdown(ut.id, at))
		var fc := Forecast.recruit_at(orders.view_state(), viewing_faction_id, ut.id, at, orders.orders())
		if not fc.ok and String(fc.code) != "not_enough_gold":
			b.disabled = true
			tip = TooltipText.plain("Can't recruit %s here" % ut.name, String(fc.reason)) + "\n\n" + tip
		b.tooltip_text = tip
		_link(b, "recruit_at" if not SiegeRules.is_engine(ut) else "recruit")
		if SiegeRules.is_engine(ut):
			CodexLink.attach(b, SiegeRules.engine_codex(ut.id), request_codex)
		_style_unit_button(b, ut.id, f.id)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var type_id: String = ut.id
		b.pressed.connect(func(): queue_recruit_at(type_id, at))
		details.add_child(b)
		if b.disabled:
			var why := _add_text(String(fc.reason), TooltipText.plain("Why not", String(fc.reason)), UiPalette.NEGATIVE.lightened(0.25))
			why.name = "RecruitReason_%s" % ut.id.validate_node_name()
			why.add_theme_font_size_override("font_size", 15)
		else:
			_add_rank_warning(ut.id, at)


## M3c S-3: "Storm now" on the order line of a move into an enemy fort: the fort's storm (one per fort).
func _storm_now_toggle(province_id: String) -> CheckBox:
	var t := CheckBox.new()
	t.name = "StormNowToggle"
	t.text = "Storm now"
	t.focus_mode = Control.FOCUS_NONE
	t.button_pressed = orders.storm_index(province_id) >= 0
	var check := orders.storm_check(province_id)
	var p := state.find_province(province_id)
	var tip := "Off: your armies besiege %s and the walls drop each turn. On: every army of yours there storms it this turn, from the march, against its walls (+%d defense) and its %s." % [
		p.name, SiegeRules.walls_defense(p.walls), p.terrain]
	if not check.is_empty():
		t.disabled = true
		tip = "%s %s" % [String(check.reason), tip]
	t.tooltip_text = TooltipText.plain("Besiege or storm now", "%s %s" % [tip, RulesCodex.text("storm")])
	CodexLink.attach(t, "storm", request_codex)
	t.toggled.connect(func(on: bool): set_storm(province_id, on))
	return t


func _show_details() -> void:
	_show_province_details()
	_add_orders_section()


func _show_province_details() -> void:
	_bind()
	for child in details.get_children():
		details.remove_child(child)
		child.queue_free()
	var p: Province = state.find_province(selected_province_id) if state else null
	if p == null:
		_add_heading("No province selected", 22)
		_add_text("Click a province on the map to see its terrain, income, owner and armies.\nHover any number to see where it comes from.",
			"", UiPalette.TEXT_SECONDARY)
		return

	_add_province_header(p)
	var garrison := state.garrison_at(p.id)  # IND-1 (#142): the Free Holds garrison you must beat to take it
	var owner_name := "Nobody (neutral)" if p.owner.is_empty() else state.find_faction(p.owner).faction_name
	if garrison != null:
		owner_name = "Neutral, held by %s" % TurnReportText.army_name(state, garrison.id)
	var seats := seat_order()
	var owner_seat := UiPalette.seat_index(state, p.owner, seats)
	var owner_help := RulesCodex.text("neutral")
	if not p.owner.is_empty():
		var mark := "" if owner_seat < 0 else " It is Player %d, drawn in %s with a %s emblem." % [
			owner_seat + 1, UiPalette.seat_color_name(owner_seat), SeatEmblem.shape_of(owner_seat)]
		owner_help = "The faction that holds %s and earns its income.%s %s" % [p.name, mark, RulesCodex.text("capture")]
	var owner_label := _add_text("Owner: %s" % owner_name, TooltipText.plain("Owner", owner_help))
	owner_label.name = "OwnerLabel"
	owner_label.add_theme_color_override("font_color", UiPalette.owner_color(state, p.owner, seats).lightened(0.3))
	_link(owner_label, TooltipText.owner_kind(p.owner))
	if garrison != null:
		var n := garrison.units.size()
		var who := TurnReportText.army_name(state, garrison.id)
		var garrison_label := _add_text("Garrison: %s, %d %s%s" % [who.trim_prefix("the "), n, "unit" if n == 1 else "units",
			" and a Hold Captain" if garrison.commander != null else ""], TooltipText.plain("Garrison of the %s" % IndependentData.FACTION_NAME,
			"To take %s you must beat %s: moving in starts a battle where it holds the ground. Select one of your armies next to it to see your odds. %s" % [
				p.name, who, RulesCodex.text("independents")]), UiPalette.TEXT_SECONDARY)
		garrison_label.name = "GarrisonLabel"
		_link(garrison_label, "independents")
	# Terrain, capital and fort explain themselves with their codex entries' own words.
	var terrain_kind := TooltipText.terrain_kind(p.terrain)
	var terrain_label := _add_text("Terrain: %s" % p.terrain.capitalize(), TooltipText.plain("Terrain: %s" % p.terrain.capitalize(),
		TooltipText.codex_text(terrain_kind)))
	terrain_label.name = "TerrainLabel"
	_link(terrain_label, terrain_kind)
	var income := Breakdown.province_income(state, p.id)
	# The total its owner earns (Heavy Tithes and Royal Court included, M2); the tooltip breaks it down.
	var income_tip := TooltipText.from_breakdown(income)
	if FogView.active(state) and not p.owner.is_empty() and p.owner != viewing_faction_id and RulerRules.has_rulers(state):
		income_tip += "\n\n" + TooltipText.wrap_text("Under fog this counts only the mandates of theirs you know: they may earn more here.")
	var income_label := _add_text("Income: %d gold per turn" % int(income.total), income_tip, UiPalette.GILT)
	income_label.name = "IncomeLabel"
	_link(income_label, "province_income", income)
	var capital_text := "No"
	if p.is_capital:
		capital_text = "Yes"
		for f in state.factions:
			if f.capital == p.id:
				capital_text = "Yes, the capital of %s" % f.faction_name
	var capital_label := _add_text("Capital: %s" % capital_text, TooltipText.plain("Capital", TooltipText.codex_text("capital")))
	capital_label.name = "CapitalLabel"
	_link(capital_label, "capital")
	if state.sieges:
		_add_fort_section(p)  # M3c S-3: the level, then the fort section
	else:
		var fort_label := _add_text("Fort: %s" % ("Yes" if p.has_fort else "No"), TooltipText.plain("Fort", TooltipText.codex_text("fort")))
		fort_label.name = "FortLabel"
		_link(fort_label, "fort")
	var names := []
	for n in p.neighbors:
		var np := state.find_province(n)
		names.append(np.name if np else n)
	var neighbors_label := _add_text("Neighbors: %s" % ", ".join(names), TooltipText.plain("Neighbors",
		"The provinces joined to %s by a road. %s" % [p.name, RulesCodex.text("move")]))
	neighbors_label.name = "NeighborsLabel"
	_link(neighbors_label, "neighbors")
	if FogView.active(state):
		_add_vision_line(p)  # M5-2: in clear sight, glimpsed or out of sight, and why
	_add_enchantment_lines(p)  # M5-6: wards, curses and Far Sight on it

	details.add_child(HSeparator.new())
	_add_heading("Armies here", 20)
	var any := false
	for a in state.armies:
		if a.location == p.id:
			any = true
			if FogView.is_stand_in(a):
				_add_stand_in(a)  # M5-2: a rival army as you see it
			else:
				_add_army(a)
	if not any and FogView.active(state) and FogView.vision_level(state, viewing_faction_id, p.id, fog_memory) in [FogRules.VEILED, FogView.NEVER]:
		var unknown := _add_text("None that you know of: you can't see %s now." % p.name, TooltipText.plain("Out of sight",
			FogView.province_text(state, viewing_faction_id, p.id, fog_memory)), UiPalette.TEXT_SECONDARY)
		unknown.name = "NoArmiesKnown"
		_link(unknown, "remembered")
	elif not any:
		var none := _add_text("No armies here.", TooltipText.plain("No armies", RulesCodex.text("undefended")), UiPalette.TEXT_SECONDARY)
		_link(none, "no_armies")


## The selected province's header: its name on a strip painted with its terrain tile, with its owner's
## banner at the right (no banner for a neutral province).
func _add_province_header(p: Province) -> void:
	var header := PanelContainer.new()
	header.name = "ProvinceHeader"
	var tex := Art.terrain(p.terrain)
	if tex != null:
		var sb := StyleBoxTexture.new()
		sb.texture = tex
		sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
		sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
		sb.region_rect = Rect2(0, 0, 512, 160)
		sb.modulate_color = Color(0.72, 0.72, 0.72)
		sb.set_content_margin_all(10)
		sb.content_margin_left = 14
		header.add_theme_stylebox_override("panel", sb)
	else:
		var flat := StyleBoxFlat.new()
		flat.bg_color = UiPalette.terrain_color(p.terrain).darkened(0.3)
		flat.set_content_margin_all(10)
		header.add_theme_stylebox_override("panel", flat)
	details.add_child(header)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	header.add_child(row)
	var title := Label.new()
	title.name = "ProvinceName"
	title.text = p.name
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", UiPalette.TEXT_PRIMARY)
	title.add_theme_color_override("font_outline_color", UiPalette.KEYLINE_INK)
	title.add_theme_constant_override("outline_size", 8)
	row.add_child(title)
	if not p.owner.is_empty():
		var banner := Art.banner_card(p.owner, 60.0)
		banner.name = "OwnerBanner"
		row.add_child(banner)
	header.custom_minimum_size = Vector2(0, 80)


func _add_army(a: Army) -> void:
	var panel := PanelContainer.new()
	panel.name = "Army_%s" % a.id.validate_node_name()
	var style := StyleBoxFlat.new()
	style.bg_color = UiPalette.PANEL_RAISED
	style.border_color = UiPalette.SELECTION if a.id == selected_army_id else UiPalette.owner_color(state, a.owner, seat_order())
	style.set_border_width_all(3 if a.id == selected_army_id else 2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", style)
	details.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)

	var header := Button.new()
	header.name = "ArmyHeader"
	var parts := army_header_parts(state, a)
	header.text = String(parts[0])  # the turn report's name for it (#55) and its place, on one line (#125)
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.autowrap_mode = TextServer.AUTOWRAP_OFF
	header.clip_text = true
	header.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	header.focus_mode = Control.FOCUS_NONE
	header.tooltip_text = TooltipText.from_breakdown(Breakdown.army_units(state, a.id)) + "\n\nClick to select this army."
	_link(header, "army_units")
	header.pressed.connect(select_army.bind(a.id))
	box.add_child(header)
	# Who is in it goes on the line under the name (#125: a big army's header wrapped to three lines).
	var who := _add_text(String(parts[1]), header.tooltip_text, UiPalette.TEXT_SECONDARY, box)
	who.name = "ArmyMembers"
	who.add_theme_font_size_override("font_size", 15)
	if a.ruler != null:
		# A ruler's army holds only its ruler (M2): show the ruler's numbers instead of units (RulerPanel).
		header.tooltip_text = RulerPanel.summary(state, a) + "\n\nClick to select this army."
		CodexLink.attach(header, "ruler_army", request_codex)
		if FogView.active(state):
			_add_sight_line(a, box)
		RulerPanel.fill(box, state, a, request_codex)
		_add_magic_lines(a, box)  # M5-6
		var open := Button.new()
		open.name = "OpenRulerPanel"
		open.text = "Ruler panel: both rulers, mandates and sacrifice"
		open.alignment = HORIZONTAL_ALIGNMENT_LEFT
		open.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		open.focus_mode = Control.FOCUS_NONE
		open.tooltip_text = TooltipText.plain("Ruler panel", "Every number of your ruler and the enemy's, explained, with the mandates each side has. Your living ruler can sacrifice power for a new mandate there.")
		CodexLink.attach(open, "ruler", request_codex)
		open.pressed.connect(open_ruler_panel)
		box.add_child(open)
		return

	var unit_breakdown := Breakdown.army_units(state, a.id)
	var units := _add_text("Units: %d" % a.units.size(), TooltipText.from_breakdown(unit_breakdown), UiPalette.TEXT_PRIMARY, box)
	units.name = "UnitsLabel"
	_link(units, "army_units", unit_breakdown)
	# A size guide only (RulesCodex "army_strength"): battles use the full rules, and the move forecast
	# has the real odds, so the label says "rough" and the tooltip points at the forecast.
	var sb := Breakdown.army_strength(state, a.id)
	sb.description = "%s %s" % [sb.get("description", ""), STRENGTH_GUIDE]
	var strength := _add_text("Rough strength: %d" % int(sb.total), TooltipText.from_breakdown(sb), UiPalette.TEXT_SECONDARY, box)
	strength.name = "StrengthLabel"
	_link(strength, "army_strength", sb)
	var commander_label: Label
	if a.commander:
		var row := _unit_row(box, a.commander.type.id, a.owner, 1)
		commander_label = _add_text("Commander: %s" % a.commander.type.name, TooltipText.plain("Commander: %s" % a.commander.type.name,
			Breakdown.unit_type_description(a.commander.type, RulerRules.price_text(state, a.owner, a.commander.type))), UiPalette.GILT, row)
		commander_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		commander_label = _add_text("Commander: none", TooltipText.plain("No commander", "This army has no commander to lead it."),
			UiPalette.TEXT_SECONDARY, box)
	commander_label.name = "CommanderLabel"
	_link(commander_label, "commander")
	if FogView.active(state):
		_add_sight_line(a, box)  # M5-2: how far it sees
	var seen := []
	for u in a.units:
		if seen.has(u.type.name):
			continue
		seen.append(u.type.name)
		var b := Breakdown.unit_count(state, a.id, u.type.name)
		var row := _unit_row(box, u.type.id, a.owner, int(b.total))
		var count_tip := TooltipText.from_breakdown(b)
		if FogView.active(state) and not FogView.scout_line(u.type).is_empty():
			count_tip += "\n\n" + TooltipText.wrap_text("%s %s" % [FogView.scout_line(u.type), RulesCodex.text("scouts")])
		var count_label := _add_text("%s ×%d" % [u.type.name, b.total], count_tip, UiPalette.TEXT_PRIMARY, row)
		count_label.name = "UnitCount"
		count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# The count's tooltip has the unit's stats and trait; its entry is Units, which links on to each.
		_link(count_label, "unit_count", b)
	_add_magic_lines(a, box)  # M5-6


## M5-6 (design/M5_MAGIC_FOG.md §6.4, §11.2): an army's magic on its panel: its blessing and when it ends, when its
## summoned creatures fade, and for an army of yours that holds a caster, "Cast a ritual…" (the cast dialog). Only what
## the state shows: under fog a rival's blessing appears only where you can see it (the view's enchantments).
func _add_magic_lines(a: Army, box: Control) -> void:
	if not MagicRules.has_magic(state):
		return
	var blessing := MagicRules.blessing_of(state, a.id)
	if not blessing.is_empty():
		var heal := int(MagicRules.spell_numbers(String(blessing.ritual), int(blessing.bonus)).value)
		var line := _add_text("Blessed: %s, through turn %d" % [MagicRules.spell_name(String(blessing.ritual)), int(blessing.until_turn)],
			TooltipText.plain("Blessed", "This army heals %d hit points at the end of every turn through turn %d, one at a time to its most wounded fighter, wherever it goes, and a side at least half blessed fights with +1 morale. %s" % [
				heal, int(blessing.until_turn), RulesCodex.text("blessing")]), UiPalette.GILT, box)
		line.name = "BlessedLine"
		CodexLink.attach(line, "blessing", request_codex)
	var fading := {}
	for u in a.units:
		if u.until > 0:
			fading[u.type.name] = u.until
	for type_name in fading:
		var line := _add_text("%s fade at the end of turn %d" % [type_name, int(fading[type_name])], TooltipText.plain("Summoned",
			RulesCodex.text("summoned")), UiPalette.TEXT_SECONDARY, box)
		line.name = "FadesLine"
		CodexLink.attach(line, "summoned", request_codex)
	if orders != null and a.owner == viewing_faction_id and not FogView.is_stand_in(a):
		_add_caster_lines(a, box)  # M5-8: "Casters: 2 Sunstone Adepts", then each spell with its number
	if orders == null or a.owner != viewing_faction_id or MagicRules.casters(state, a).is_empty() or FogView.is_stand_in(a):
		return
	if orders.cast_options(a.id).is_empty():
		return  # its casters know no ritual yet (Far Sight is offered only under fog): the Magic tab says what to research
	var cast := Button.new()
	cast.name = "CastRitual"
	cast.text = "Cast a ritual…"
	cast.alignment = HORIZONTAL_ALIGNMENT_LEFT
	cast.focus_mode = Control.FOCUS_NONE
	cast.tooltip_text = TooltipText.plain("Cast a ritual", "%s holds %s. %s" % [RulerRules._cap(TurnReportText.army_name(state, a.id)),
		MagicRules._and_list(MagicRules.casters(state, a).map(func(c): return MagicRules.caster_name(c))), RulesCodex.text("cast_order")])
	CodexLink.attach(cast, "cast_order", request_codex)
	cast.pressed.connect(open_cast_dialog.bind(a.id, ""))
	box.add_child(cast)


## M5-8 (§11.2: "Casters: 2 Sunstone Adepts. Sunlance 4 damage, Shield of Law 6 units (mastery +0)."): the casters of one of
## your armies that cast in battle and each spell they cast in your spellbook's order, with its number now and its breakdown
## (mastery included). A spell the spellbook switches off says so. Nothing for an army with no such caster.
func _add_caster_lines(a: Army, box: Control) -> void:
	var line := MagicView.army_line(state, a)
	if line.is_empty():
		return
	var casters := MagicRules.casters(state, a).filter(func(c): return c.battle == true)
	var units_bd := Breakdown.army_units(state, a.id)
	var head := _add_text(String(line.header), "%s\n\n%s" % [TooltipText.from_breakdown(units_bd), TooltipText.wrap_text("%s %s" % [
		RulesCodex.text("caster"), RulesCodex.text("mage")])], UiPalette.GILT, box)
	head.name = "CastersLine"
	head.add_theme_font_size_override("font_size", 16)
	head.set_meta("breakdown", units_bd)
	CodexLink.attach(head, "caster", request_codex)
	for s in line.spells:
		var l := _add_text(String(s.text), TooltipText.from_breakdown(s.breakdown), UiPalette.TEXT_PRIMARY if s.on else UiPalette.TEXT_DISABLED, box)
		l.name = "Spell_%s" % String(s.spell)
		l.add_theme_font_size_override("font_size", 15)
		l.set_meta("breakdown", s.breakdown)
		CodexLink.attach(l, String(s.codex), request_codex)
	if line.spells.is_empty():
		var none := _add_text("No spell known yet: research one in the Magic tab.", TooltipText.plain("No spell yet", RulesCodex.text("arcana")),
			UiPalette.TEXT_SECONDARY, box)
		none.name = "CastersNone"
		none.add_theme_font_size_override("font_size", 15)
		CodexLink.attach(none, "arcana", request_codex)
	elif casters.size() > 0:
		var mastery_bd := Breakdown.mastery(state, a.owner, String(MagicRules.spell_data(String(line.spells[0].spell)).school), String(casters[0].kind))
		var mastery := _add_text(String(line.mastery_text), TooltipText.from_breakdown(mastery_bd), UiPalette.TEXT_SECONDARY, box)
		mastery.name = "MasteryLine"
		mastery.set_meta("breakdown", mastery_bd)
		mastery.add_theme_font_size_override("font_size", 14)
		CodexLink.attach(mastery, "mastery", request_codex)


## M5-6: the enchantments on a province (§6.4, §11.2), each with who cast it, what it does and through which turn,
## from the state shown (under fog, the view: only the ones you can see).
func _add_enchantment_lines(p: Province) -> void:
	if not MagicRules.has_magic(state):
		return
	for e in state.enchantments:
		if String(e.province) != p.id or String(e.kind) == "blessing":
			continue
		var what := EnchantmentBadges.effect_text(state, e)  # M5-8: the badge's words
		var who := MagicRules._faction_display(state, String(e.faction))
		var line := _add_text("%s (%s), through turn %d" % [MagicRules.spell_name(String(e.ritual)), who, int(e.until_turn)],
			TooltipText.plain(MagicRules.spell_name(String(e.ritual)), "%s %s" % [what, RulesCodex.text(String(e.kind))]),
			UiPalette.GILT, details)
		line.name = "Enchantment_%s" % String(e.ritual).validate_node_name()
		CodexLink.attach(line, MagicRules.spell_codex(String(e.ritual)), request_codex)


## M5-2: "Vision: Glimpsed", "Vision: Out of sight (last seen 2 turns ago)": the province's sight level for the
## viewer, with why it is seen or what is remembered of it on hover.
func _add_vision_line(p: Province) -> void:
	var level := FogView.vision_level(state, viewing_faction_id, p.id, fog_memory)
	var text := "Vision: %s" % String(FogView.LEVEL_TITLES.get(level, level))
	var seen_turn := int(fog_memory.get("provinces", {}).get(p.id, {}).get("seen_turn", -1))
	if level == FogRules.VEILED and seen_turn > 0:
		text += " (last seen %s)" % FogView._ago(state, seen_turn)
	var l := _add_text(text, TooltipText.plain(String(FogView.LEVEL_TITLES.get(level, level)),
		"%s %s" % [FogView.province_text(state, viewing_faction_id, p.id, fog_memory), RulesCodex.text(String(FogView.LEVEL_CODEX.get(level, "sight")))]),
		UiPalette.TEXT_SECONDARY)
	l.name = "VisionLabel"
	CodexLink.attach(l, String(FogView.LEVEL_CODEX.get(level, "sight")), request_codex)


## M5-2: one of your armies' sight line: "This army sees 2 provinces around it (it has Knights)."
func _add_sight_line(a: Army, box: Control) -> void:
	var line := FogView.army_sight_line(a)
	var l := _add_text(line, TooltipText.plain("Sight", "%s %s" % [line, RulesCodex.text("sight")]), UiPalette.TEXT_SECONDARY, box)
	l.name = "ArmySight"
	l.add_theme_font_size_override("font_size", 15)
	_link(l, "army_sight")


## M5-2: a rival army as the viewer sees it (§11.1): its sighting with the range of every type, its commander, last
## turn's sighting at that place, and how to see it exactly. A remembered army is greyed. Every number explains itself.
func _add_stand_in(a: Army) -> void:
	var level := String(a.seen.get("level", ""))
	var panel := PanelContainer.new()
	panel.name = "Army_%s" % a.id.validate_node_name()
	var style := StyleBoxFlat.new()
	style.bg_color = UiPalette.PANEL_RAISED if level != FogData.MEMORY else UiPalette.PANEL_BG
	style.border_color = UiPalette.SELECTION if a.id == selected_army_id else UiPalette.owner_color(state, a.owner, seat_order())
	style.set_border_width_all(3 if a.id == selected_army_id else 2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", style)
	if level == FogData.MEMORY:
		panel.modulate = Color(1, 1, 1, 0.72)
	details.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var b := FogView.army_breakdown(state, viewing_faction_id, a, fog_before)
	var tip := TooltipText.from_breakdown(b)
	var kind := "remembered" if level == FogData.MEMORY else ("glimpse" if level == FogRules.GLIMPSE else "vision")
	var header := Button.new()
	header.name = "ArmyHeader"
	header.text = FogView.army_heading(state, a)
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.focus_mode = Control.FOCUS_NONE
	header.tooltip_text = tip + "\n\nClick to select it."
	header.pressed.connect(select_army.bind(a.id))
	_link(header, kind)
	box.add_child(header)
	if a.ruler != null:
		var note := _add_text("A ruler is hard to hide: you see its name and numbers, but not its wounds or exactly where it goes next. Its kept power is what you know, or the most it could be.",
			TooltipText.plain("A rival ruler", RulesCodex.text("intel")), UiPalette.TEXT_SECONDARY, box)
		note.name = "RulerFogNote"
		_link(note, "rival_known")
		RulerPanel.fill(box, state, a, request_codex)
		return
	var total: Dictionary = a.seen.get("total", {})
	var count_text := FogView.range_text(total)
	if level == FogData.MEMORY:
		count_text += ", %s" % FogView._ago(state, int(a.seen.get("turn", 0)))
	var count := _add_text("Fighters: %s" % count_text, tip, UiPalette.TEXT_PRIMARY, box)
	count.name = "FightersLabel"
	_link(count, kind, b)
	for line in b.lines:
		var type_id := String(line.get("type", ""))
		var row: Control = _unit_row(box, type_id, a.owner, int(line.value)) if not type_id.is_empty() else box
		var ut: UnitType = null
		for u in a.units:
			if u.type.id == type_id:
				ut = u.type
		var unit_tip := tip
		if ut != null:
			unit_tip = "%s\n\n%s" % [tip, TooltipText.wrap_text("%s %s" % [Breakdown.unit_type_description(ut), FogView.scout_line(ut)])]
		var l := _add_text(String(line.label), unit_tip, UiPalette.TEXT_PRIMARY, row)
		l.name = "UnitCount"
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_link(l, "unit_count")
	if a.commander != null:
		var crow := _unit_row(box, a.commander.type.id, a.owner, 1)
		var c := _add_text("Led by a %s" % a.commander.type.name, TooltipText.plain("Commander: %s" % a.commander.type.name,
			Breakdown.unit_type_description(a.commander.type)), UiPalette.GILT, crow)
		c.name = "CommanderLabel"
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_link(c, "commander")
	var last := _add_text("Last turn: %s" % FogView.last_turn_text(state, a, fog_before), TooltipText.plain("Last turn",
		"What you saw at %s at the start of the last turn, for comparison: a band crossing (about 15 to about 20) can be a few fighters, not five. %s" % [
			TurnResolver._province_name(state, a.location), RulesCodex.text("estimates")]), UiPalette.TEXT_SECONDARY, box)
	last.name = "LastTurnLabel"
	_link(last, "glimpse")
	if level != FogRules.CLEAR:
		var how := _add_text("Fight them, or cast Far Sight once you have a mage, to see them exactly." if state.magic else "Fight them to see them exactly.",
			TooltipText.plain("Seeing them exactly", RulesCodex.text("sight")), UiPalette.TEXT_SECONDARY, box)
		how.name = "SeeExactly"
		_link(how, "vision")


## A row in the army list: the unit's portrait (its face, with a count badge for more than one), then
## the caller's label. Returns the row.
func _unit_row(parent: Control, unit_type_id: String, faction_id: String, count: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "UnitRow_%s" % unit_type_id.validate_node_name()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var card := Art.portrait_card(unit_type_id, ROW_PORTRAIT, faction_id, Art.Crop.FACE)
	card.texture = Art.unit_portrait(state, faction_id, unit_type_id)
	card.count = count
	row.add_child(card)
	return row


## Links a side panel label to the codex entry for its kind of number (TooltipText.CODEX).
func _link(control: Control, kind: String, breakdown: Dictionary = {}) -> void:
	CodexLink.attach(control, TooltipText.codex_for(kind, breakdown), request_codex)


func _add_heading(text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", UiPalette.GILT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(l)
	return l


## Adds a line of text with a tooltip. Labels with tooltips take the mouse so the tooltip shows.
## An army's side panel header as [the one-line header: its report name and where it is ("The Crown's 1st at
## Crownkeep"), the line under it: who is in it ("Spearmen, Crossbowmen and Knight Captain"; a ruler's army:
## "Ruler of the Aurel Crown")], from TurnReportText.army_title's own words (#125).
static func army_header_parts(st: GameState, a: Army) -> Array:
	var name := TurnReportText.army_name(st, a.id, a.owner)
	var bare := TurnReportText.army_title(st, a, false)
	var placed := TurnReportText.army_title(st, a)
	var inside := bare.substr(name.length()).strip_edges().trim_prefix("(").trim_suffix(")")
	return [RulerRules._cap(name) + placed.substr(bare.length()), RulerRules._cap(inside)]


func _add_text(text: String, tooltip: String, color: Color = UiPalette.TEXT_PRIMARY, parent: Control = null) -> Label:
	var l := Label.new()
	l.text = text
	l.tooltip_text = tooltip
	l.mouse_filter = Control.MOUSE_FILTER_PASS if not tooltip.is_empty() else Control.MOUSE_FILTER_IGNORE
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", color)
	(parent if parent else details).add_child(l)
	return l


func _on_back_pressed() -> void:
	if intercept_back:
		back_requested.emit()
		return
	get_tree().change_scene_to_file(TITLE_SCENE)
