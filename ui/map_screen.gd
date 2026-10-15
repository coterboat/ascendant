class_name MapScreen
extends Control
## The main map screen (issue #5): the M1 map drawn from a GameState, full-bleed, with the Table over it (UX-1, #194,
## design/UX_WAR_TABLE.md §1): the realm plaque with the viewing player's gold and the turn, the system row, the
## opponent plaque and Menu, the tray and the seal (TableHud), and the selection cards (SelectionCards, UX-3, #206: the army card
## and the province card, docked in the left column). UX-4 (#213, §3.4): every queued order is numbered on the board and in the tray
## (OrderTray, its tokens in tray_slot()), a click on a token focuses its place and opens its card (show_order), and the tray's cross
## or a right-click cancels it.
## Reads the GameState only and never changes it. Every number on screen has a tooltip with its
## breakdown (rules/breakdown.gd) and a plain-language description, ending with the codex entry that
## explains it: right-click (or F1 while hovering) asks for that entry with codex_requested (#8). In the
## map preview, where no game screen listens, the map opens a codex panel of its own.
## Player colours follow the seat: seat_order() is the session's seat order when there is a session.
##
## API for the orders UI and turn flow:
##   set_state(state, viewing_faction_id)  show a state (rebuilds the map; keeps the selection if it still exists)
##   select_province(id)                   select a province and show its card
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
##   intercept_back             true: the Menu button emits back_requested instead of leaving
##   hud                        the TableHud: add_system_button, add_plaque_item, add_seal_item (it replaces the old
##                              add_top_bar_control), the notification and tray slots, the safe area
##   set_hint(text, tooltip)    the one line of "what to do now" in the tray (at most two lines; the tooltip can say more)
##
## The host seams (UX-1, §1.1): later tickets plug into these instead of editing this file.
##   selection_host (SelectionHost)  "show this army or province" and "selection cleared"; the selection cards are its presenter
##   cards (SelectionCards)          the army card, the province card and one order's card (show_order); `details` is the open one's content
##   lens_host (LensHost)            the active lens id, its keys, and the feed to the board; UX-7's six lenses are registered
##                                   there by lens_ui (LensUi: the legend card, the Lenses button's picker, the 2D map's colours)
##   ui_cancel (UiCancel)            Esc and a right-click on empty board close the topmost thing, one per press (§1.4)
##   (the game screen has the fourth, report_host: ReportHost)
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
## they see and scouts say so; the forecasts are Forecast's fog forecasts. The 2D map veils what you can't see; the 3D board
## gives each sight level its own look (Vision.look). UX-2 retired the Vision map mode (its button and the 2D swap): the plate's
## hover names a province's level, and FogView.legend_rows keeps the legend's text for the Sight lens.

signal province_selected(province_id: String)
signal army_selected(army_id: String)
## The viewing player's queued orders changed (queued, refused or cancelled).
signal orders_changed
## The back button was pressed while intercept_back is on.
signal back_requested
## A number or term linked to the codex was right-clicked (or F1 was pressed over it).
signal codex_requested(key: String)

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
const TITLE_SCENE := "res://ui/title_screen.tscn"
const CODEX_SCENE := "res://ui/codex_panel.tscn"
## Added to the army strength tooltip: the number is a size guide, the move forecast has the odds.

var state: GameState = null
var viewing_faction_id := ""
var selected_province_id := ""
var selected_army_id := ""
var regions := {}  # province id -> ProvinceRegion
var board_text_floor := 0  # UI-FIT (#237): the least font size of the 2D plates' text, in canvas pixels (_apply_board_text_floor)
var orders: OrdersController = null  # issue #6: the viewing faction's orders this turn
var session: GameSession = null  # game screen (#7): when set, orders live in the session's books
var intercept_back := false  # game screen (#7): the host confirms before leaving
var status_text := ""  # last order result: the rules' reason when an order was refused
var arrow_layer: Control  # drawn above the regions: one arrow per queued move
var order_marks_2d: OrderMarks2D = null  # UX-4: the numbers and tokens of the queued orders over the 2D map (the 3D board draws its own)
var hover_panel: ForecastGlance  # the move forecast of the hovered province, compact; it lives in the selection card or the march strip (UX-3)
var own_codex: CodexPanel = null  # map preview only: opened when no game screen listens for codex_requested
var ruler_panel: RulerPanel = null  # M2-6: opened by open_ruler_panel(), over the map and the Table
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

# Scene nodes, looked up by _bind() rather than @onready so the screen also works before it is in
# the tree (tests build it headless, and callers may set_state() before adding it).
var map_view: Control
var map_canvas: Control
## UX-1: the Table over the map (plaques, system row, tray, seal) and the four host seams (the fourth, ReportHost, is the game screen's).
var hud: TableHud
var selection_host := SelectionHost.new()
var lens_host := LensHost.new()
var lens_ui: LensUi  # UX-7: the six lenses on this screen (keys 1 to 6, the legend card, the picker, both boards)
var ui_cancel := UiCancel.new()
var cards: SelectionCards  # the army card, the province card and one order's card: the selection host's presenter (UX-3, UX-4)
var details: VBoxContainer  # the open card's content (cards.details): what the side panel's lines became
var faction_label: Label  # the realm plaque's name (the HUD's own nodes)
var faction_emblem: SeatEmblem  # the viewing player's seat emblem, on their banner left of their name
var faction_crest: Control  # the viewing faction's banner (Art) with the seat emblem on it
var faction_banner: Art.BannerCard
var gold_label: Label  # hidden when nobody's gold is shown (game over, spectator)
var turn_label: Label
var ruler_line: Button  # the realm plaque's ruler and kept power (games with rulers); a click opens the Ruler panel
var hint_label: Label  # the tray's one line of "what to do now": wraps to at most two lines
var back_button: Button  # Menu (top right); "Back to title" in the map preview


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
		if cast_dialog != null and cast_dialog.visible:
			cast_dialog.close()  # M5-8: a new turn or another seat: the dialog's orders are stale
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
		region.mouse_exited.connect(leave_preview)
		map_canvas.add_child(region)
		regions[p.id] = region
		if FogView.active(state):
			region.setup_fog(state, faction_id, fog_memory, fog_before)  # M5-2: sight, memory and sightings
		region.set_text_floor(board_text_floor)
	map_canvas.queue_redraw()
	arrow_layer.queue_redraw()
	clear_preview()
	_update_realm_plaque()
	if state.find_province(selected_province_id) == null:
		selected_province_id = ""
	if state.find_army(selected_army_id) == null:
		selected_army_id = ""
	_update_map_marks()
	_announce_selection(false)
	_follow_ruler_panel()
	lens_ui.refresh()  # UX-7: the active lens for this state (off for a new session or seat)
	_sync_board()
	_refresh_order_marks()


func select_province(province_id: String) -> void:
	_select_province(province_id, false)


## `keep_army`: the click was on an army (select_army), so the army stays selected. A click on the land is the province side
## (UX-3, design/UX_WAR_TABLE.md §3: a province and an army are two distinct sides), so the army that stands there is unselected
## and the province card opens; with one of your armies selected a click on ANOTHER province still orders its move.
func _select_province(province_id: String, keep_army: bool) -> void:
	if state == null or state.find_province(province_id) == null:
		return
	if casting():  # M5-8: with the cast dialog open, a lit province is the target; any other click changes nothing
		if cast_dialog.accepts_province(province_id):
			cast_dialog.select_target(province_id)
		else:
			cast_dialog.nudge("%s is out of this ritual's reach. Pick a lit province, or cancel." % state.find_province(province_id).name)
		return
	# Two-click move: with one of your armies selected, clicking another province orders it there.
	var mover := board_army(selected_army_id)  # ARM-1: an army a queued muster forms can be given its move too
	if mover and orders and mover.owner == viewing_faction_id and mover.location != province_id:
		var refused := queue_move(mover.id, province_id)
		if refused.is_empty():
			return
		if cards.marching:  # UX-3 (§3.3): picking a march destination: the strip says why, and the pick goes on
			cards.march_refused(refused)
			return
		# Refused: the reason stays in the status line and the click selects the province as usual.
	else:
		status_text = ""
	clear_preview()
	selected_province_id = province_id
	var army := board_army(selected_army_id)
	if army == null or army.location != province_id or not keep_army:
		selected_army_id = ""
	for id in regions:
		regions[id].selected = id == province_id
	_update_road_targets()
	_announce_selection(true)
	_sync_board()
	if board != null and board.has_method("keep_in_view") and hud.has_layout():
		board.call("keep_in_view", province_id, hud.framing_area())  # UI-FIT (#237): never left under the card it opens
	province_selected.emit(province_id)


## The state the cards and the orders read (ARM-1, design/ARM1_SPLIT_MERGE.md §3): `state`, or, when a muster is queued, the board
## those musters leave (OrdersController.view_state), where the armies they form already stand with their real ids.
func board_state() -> GameState:
	if state == null or orders == null or not MusterRules.has_musters(orders.orders()):
		return state
	return orders.view_state()


## Army `army_id` on that board: a real army, or one a queued muster forms (null when it is neither).
func board_army(army_id: String) -> Army:
	var board := board_state()
	return board.find_army(army_id) if board != null else null


func select_army(army_id: String) -> void:
	var army: Army = board_army(army_id)
	if army == null:
		return
	selected_army_id = army_id
	_select_province(army.location, true)
	army_selected.emit(army_id)


## Hover preview (#6): with one of your armies selected, shows what clicking `province_id` would order (arrival forecast and battle
## odds, or the rules' reason it can't be ordered) before you click: two or three short lines in the army's card (or the march strip),
## with an "i" whose tooltip is the whole forecast (MoveGlance, ForecastGlance). Returns the full text, "" when there is nothing to preview.
func preview_move(province_id: String) -> String:
	_bind()
	var text := ""
	var army: Army = board_army(selected_army_id) if state else null
	if orders and army and army.owner == viewing_faction_id and army.location != province_id \
			and state.find_province(province_id) != null:
		var glance := MoveGlance.build(orders, army.id, province_id)
		text = String(glance.full)
		hover_panel.show_glance(glance, request_codex)
	if text.is_empty():
		hover_panel.clear()
	return text


## The forecast is gone: hidden at once (a new selection, an order, a new state, a hand-over).
func clear_preview() -> void:
	if hover_panel:
		hover_panel.clear()


## The pointer left the province (or the board): the forecast stays, dimmer, in the card or the strip, until another province is hovered or
## the selection or the orders change, so the pointer can travel to its "i" and read the whole paragraph.
func leave_preview() -> void:
	if hover_panel and hover_panel.visible:
		hover_panel.set_stale(true)


## The tray's one line of "what to do now" (UX-1: it was the top bar's hint). Keep it short: it wraps to at most two lines.
## `tooltip`, already formatted (TooltipText.plain), is shown on hover for help that doesn't fit; empty shows the text.
func set_hint(text: String, tooltip: String = "") -> void:
	_bind()
	hud.set_hint(text, tooltip)


## The Table over the map (TableHud): built on first use, like the rest of this screen.
func table() -> TableHud:
	_bind()
	return hud


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
		own_codex.cancel_router = func(): ui_cancel.cancel()  # UX-1: Esc goes through the one dispatcher
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


## Esc in the map preview, where no game screen owns it: the one dispatcher (UiCancel). In a game the game screen calls it, so
## nothing here runs twice. Lens keys (1 to 6, UX-7) turn a lens on or off while no modal panel is open, and ` turns it off.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not intercept_back:
		if not ui_cancel.cancel().is_empty() and is_inside_tree():
			get_viewport().set_input_as_handled()


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo or ui_cancel.is_open("modal"):
		return
	var lens := lens_host.id_for_key(k.keycode)
	if lens.is_empty() and k.physical_keycode != KEY_NONE:
		lens = lens_host.id_for_key(k.physical_keycode)  # UX-7: the top row's 1 to 6 on any layout (AZERTY's & é " ' ( -)
	if not lens.is_empty():
		lens_host.toggle(lens)
		if is_inside_tree():
			get_viewport().set_input_as_handled()
	elif (k.keycode == KEY_QUOTELEFT or k.physical_keycode == KEY_QUOTELEFT) and not lens_host.active_id().is_empty():  # the key left of 1, on any layout
		lens_host.clear()
		if is_inside_tree():
			get_viewport().set_input_as_handled()


## A right-click on the 2D map's empty sea closes the topmost thing, like Esc (the 3D board does the same from its own
## input; a province or an army under the click has its codex entry instead).
func _on_map_view_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
		ui_cancel.cancel(true)
		accept_event()


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
		status_text = "Sacrifice ordered: %s. It resolves first when the turn ends, so your other orders already count on it; cancel it with the cross on its tray token." % \
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
		status_text = "Ritual ordered: %s. It is cast before anyone moves when the turn ends, and the army holds; Cancel order on its card, or the cross on its tray token, takes it back." % \
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
	_refresh_order_marks()
	lens_ui.refresh()  # UX-7: the lens legend names the 3D-only effects on the 2D map
	if board != null:
		map_view.add_child(board)
		map_view.move_child(board, 0)
		board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		board.map = self
		if board.has_signal("closeup_changed"):
			board.closeup_changed.connect(func(_pid): _show_details())
		if board.has_signal("ready_to_show"):
			board.ready_to_show.connect(_hang_board_pieces)
		_on_table_layout()
		_sync_board()
		if board.get("prepared") == true:
			_hang_board_pieces()


## The 3D board's overlay exists (its land is built): the Table places its playback bar, its caption and its close-up chip in the
## board's safe area, so nothing covers their buttons (UX-1, §1.3).
func _hang_board_pieces() -> void:
	if board == null or board.get("overlay") == null:
		return
	var overlay: Control = board.overlay
	overlay.hung = true
	hud.hang("playback", overlay.play_bar())
	hud.hang("caption", overlay.caption_panel())
	hud.hang("closeup", overlay.closeup_chip())


func _sync_board() -> void:
	if board != null:
		lens_host.feed_board(board)  # UX-1: the active lens (none yet) feeds the board before it syncs
		board.sync()


# --- layout ---------------------------------------------------------------------------------------

## Finds the scene's nodes, builds the Table over them and wires their signals, once.
func _bind() -> void:
	if map_view != null:
		return
	map_view = %MapView
	map_canvas = %MapCanvas
	_build_table()
	map_view.resized.connect(_fit_map)
	(map_view as ColorRect).color = SEA_DEEP
	map_canvas.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	map_canvas.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	map_canvas.draw.connect(_draw_links)
	map_view.gui_input.connect(_on_map_view_input)
	back_button.pressed.connect(_on_back_pressed)
	# Order arrows sit above the map canvas (same transform, see _fit_map) so regions don't hide them.
	arrow_layer = Control.new()
	arrow_layer.name = "OrderArrows"
	arrow_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arrow_layer.size = MapLayout.SIZE
	arrow_layer.draw.connect(_draw_order_arrows)
	map_view.add_child(arrow_layer)
	order_marks_2d = OrderMarks2D.new()
	order_marks_2d.map = self
	map_view.add_child(order_marks_2d)
	# The move forecast of a hovered destination: two or three short lines and an "i" with the whole paragraph (UX-3). It no longer floats
	# over the board: the selection cards adopt it, under an army's actions and in the march strip.
	hover_panel = ForecastGlance.new()
	cards.adopt_forecast(hover_panel)
	_register_cancel_layers()


## UX-1: the Table. The HUD sits over the map view; the selection cards are its first floating piece and the selection host's
## presenter; the realm plaque's labels are the ones the old top bar had (the same names, tooltips and codex links).
func _build_table() -> void:
	hud = TableHud.new()
	add_child(hud)
	faction_label = hud.faction_label
	gold_label = hud.gold_label
	turn_label = hud.turn_label
	faction_crest = hud.faction_crest
	faction_banner = hud.faction_banner
	faction_emblem = hud.faction_emblem
	hint_label = hud.hint_label
	back_button = hud.menu_button
	back_button.text = "Back to title"
	back_button.tooltip_text = TooltipText.plain("Back to title", "Leave the map preview for the title screen.")
	ruler_line = Button.new()
	ruler_line.name = "RulerLine"
	ruler_line.flat = true
	ruler_line.focus_mode = Control.FOCUS_NONE
	ruler_line.visible = false
	ruler_line.alignment = HORIZONTAL_ALIGNMENT_LEFT
	ruler_line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ruler_line.add_theme_font_size_override("font_size", UiPalette.TYPE_SMALL)
	for state_name in ["normal", "hover", "pressed", "disabled", "focus"]:
		var bare := StyleBoxEmpty.new()  # a line of text, not a button: no padding, so the plaque stays two lines tall
		bare.content_margin_left = 0
		bare.content_margin_right = 0
		bare.content_margin_top = 0
		bare.content_margin_bottom = 0
		ruler_line.add_theme_stylebox_override(state_name, bare)
	ruler_line.add_theme_color_override("font_color", UiPalette.TEXT_SECONDARY)
	ruler_line.add_theme_color_override("font_hover_color", UiPalette.GILT)
	ruler_line.pressed.connect(open_ruler_panel)
	hud.add_plaque_item(ruler_line)
	cards = SelectionCards.new()
	cards.map = self
	details = cards.details
	hud.set_floating("card", cards)
	selection_host.set_presenter(cards)
	hud.layout_changed.connect(_on_table_layout)
	# UX-4: the tray's tokens: a click focuses the order's place and opens its card, the cross (or a right-click) cancels it.
	hud.tray_slot().codex_opener = request_codex
	hud.tray_slot().order_pressed.connect(show_order)
	hud.tray_slot().order_cancelled.connect(cancel_order)
	lens_ui = LensUi.new(self)  # UX-7: registers the lenses with the host, the legend card and the Lenses button


## The Table's layers in the one cancel dispatcher (§1.4): the map screen's own modals, the selection card, the lens and the
## board's close-up. The game screen adds its overlays and the menu.
func _register_cancel_layers() -> void:
	# Modals the map screen owns: the codex of the map preview over the sacrifice dialog over the ruler panel; the cast dialog.
	ui_cancel.register("modal", func(): return own_codex != null and own_codex.visible, func(): own_codex.close(), 40)
	ui_cancel.register("modal", func(): return sacrifice_dialog != null and sacrifice_dialog.visible, close_sacrifice_dialog, 30)
	ui_cancel.register("modal", func(): return cast_dialog != null and cast_dialog.visible, close_cast_dialog, 30)
	ui_cancel.register("modal", func(): return ruler_panel != null and ruler_panel.visible, close_ruler_panel, 20)
	ui_cancel.register("march", func(): return cards.marching, cards.end_march)  # UX-3 (§3.3): the march strip's Esc
	ui_cancel.register("card", func(): return cards.visible, dismiss_selection_card)
	ui_cancel.register("lens", func(): return not lens_host.active_id().is_empty(), lens_host.clear)
	ui_cancel.register("closeup", func(): return board != null and String(board.closeup) != "", func(): board.exit_closeup())
	lens_host.active_changed.connect(func(_id): _sync_board())


## Scales the design-space canvas to fit the board's framing area (the safe area right of the card column), centred, keeping
## its aspect ratio: every province of the 2D map stays in view and clear of the plaques, the card and the tray.
func _fit_map() -> void:
	if map_view.size.x <= 0 or map_view.size.y <= 0 or arrow_layer == null:
		return
	var avail := hud.framing_area()
	var s: float = min(avail.size.x / MapLayout.SIZE.x, avail.size.y / MapLayout.SIZE.y)
	map_canvas.scale = Vector2(s, s)
	map_canvas.position = avail.position + (avail.size - MapLayout.SIZE * s) / 2.0
	_apply_board_text_floor()
	arrow_layer.scale = map_canvas.scale
	arrow_layer.position = map_canvas.position
	if order_marks_2d != null:
		order_marks_2d.place()


## UI-FIT (#237): the 2D map's text never draws below the 12 px floor (UiPalette.SCREEN_FLOOR_PX, in the window's own pixels): the
## canvas is scaled down to fit the framing area (to 0.42 with the Chronicle open at 125%, where "3 units" drew at 7 px), so each plate's
## text is set at least as big as the floor over the canvas scale and the window's own scale.
func _apply_board_text_floor() -> void:
	var drawn := map_canvas.scale.x * _window_px_per_logical()
	var px := int(ceil(UiPalette.SCREEN_FLOOR_PX / maxf(drawn, 0.01)))
	if px == board_text_floor:
		return
	board_text_floor = px
	for id in regions:
		(regions[id] as ProvinceRegion).set_text_floor(board_text_floor)
	if order_marks_2d != null:
		order_marks_2d.place.call_deferred()  # UI-CLUTTER (#238): once the plates' text has its new size, the marks go round it


## How many of the window's own pixels a logical pixel is: 1.25 at 125%, 0.8 in a 1280x720 window (the project's 1600x900 stretched).
func _window_px_per_logical() -> float:
	var w := get_window() if is_inside_tree() else null
	var logical := get_viewport_rect().size if is_inside_tree() else Vector2.ZERO
	if w == null or logical.x <= 0.0:
		return 1.0
	return float(w.size.x) / logical.x


## The Table moved (a new window size, the Chronicle opening): the 2D map and the 3D board's whole-map framing follow the framing
## area, and the board's playback bar, caption and close-up chip are hung in the Table's layout.
func _on_table_layout() -> void:
	_fit_map()
	if board != null and board.has_method("set_fit_rect") and hud.has_layout():
		board.call("set_fit_rect", hud.framing_area())


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


# --- the realm plaque -----------------------------------------------------------------------------

## The realm plaque (top left): the viewing faction's banner and name, its gold with the income, the turn and, in a game with
## rulers, the ruler and its kept power. Every number keeps its breakdown tooltip and its codex link.
func _update_realm_plaque() -> void:
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
	# Without a faction (game over, spectator) the gold label is hidden, so the plaque has no empty gap.
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
	_update_ruler_line(f)


## The ruler line of the realm plaque: "King Corvane I · 6 kept" with the kept power's breakdown, and a click opens the Ruler
## panel. Only in a game with rulers, for a faction that has a ruler (a spectator's plaque has none).
func _update_ruler_line(f: Faction) -> void:
	var has := f != null and RulerRules.has_rulers(state) and f.has_ruler()
	ruler_line.visible = has
	CodexLink.detach(ruler_line)
	if not has:
		ruler_line.text = ""
		ruler_line.tooltip_text = ""
		return
	var kept := Breakdown.kept_power(state, viewing_faction_id)
	ruler_line.text = "%s · %d kept" % [RulerRules.current_name(state, viewing_faction_id), RulerRules.kept_power(state, viewing_faction_id)]
	ruler_line.tooltip_text = "%s\n\n%s" % [TooltipText.from_breakdown(kept), TooltipText.wrap_text("Click to open the Ruler panel: every number of your ruler and the enemy's, and the mandates each side has.")]
	CodexLink.attach(ruler_line, "ruler", request_codex)


# --- orders (issue #6) ----------------------------------------------------------------------------

## Queues a move for the viewing faction. Returns "" or the rules' reason (also shown in the panel).
func queue_move(army_id: String, to_province: String) -> String:
	var reason := orders.queue_move(army_id, to_province)
	status_text = reason if not reason.is_empty() else "Move ordered. Armies move when the turn ends; Cancel order on the army's card, or the cross on its tray token, takes it back."
	if reason.is_empty() and not orders.last_relief.is_empty():  # M3c: the garrison comes out to join the relief
		var place := state.find_province(to_province).name
		status_text = "Relief ordered: it marches into %s when the turn ends, and the garrison comes out to join it: %s. Untick them in %s's fort panel to keep them in." % [
			place, RulerRules._and_list(orders.last_relief.map(func(id): return TurnReportText.army_name(state, id))), place]
	elif reason.is_empty() and orders.siege_kind(army_id, to_province) == "besiege":
		status_text = "Move ordered: it besieges %s when the turn ends. Tick Storm now on the order to storm from the march instead." % state.find_province(to_province).name
	_order_sound(reason, "march")
	_orders_changed()
	return reason


## ARM-1: queues a muster (a split, a transfer, a merge or a swap of commanders between your armies in one province). Returns ""
## or the rules' reason, which is the forecast's own (MusterForecast.refusal), also shown on the card.
func queue_muster(order: MusterOrder) -> String:
	var reason := orders.queue_muster(order)
	if reason.is_empty():
		status_text = "%s Armies muster first when the turn ends, before anything moves, so a new army can be given a move now. Cancel muster on the army's card, or the cross on its tray token, undoes it.%s" % [
			orders.order_text(orders.orders().size() - 1), _removed_text(orders.last_removed())]
	else:
		status_text = reason
	_order_sound(reason, "")
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
		status_text = "Fortify ordered: %s at %s stands at the end of turn %d if no enemy army stands there, and takes recruits from turn %d. Cancel it with the cross on its tray token." % [
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
	_refresh_order_marks()
	orders_changed.emit()


## UX-4: the tray's tokens and the 2D map's order marks follow the orders (the 3D board's marks follow board.sync(), above). Their numbers
## are places in orders(), so every change of the list, and a new turn, rebuilds them.
func _refresh_order_marks() -> void:
	if hud != null:
		hud.tray_slot().refresh(orders)
	if order_marks_2d != null:
		order_marks_2d.refresh()


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
	var army := board_army(selected_army_id)
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
		var army := board_army(o.army_id)  # ARM-1: the arrow of a new army starts where its split happened
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


## What the selection shows changed (an order, a new state, the close-up): the selection host's presenter rebuilds. A card the
## player closed stays closed.
func _show_details() -> void:
	_bind()
	selection_host.refresh()


## A tray token, or an order's mark on the board, was clicked (UX-4): focuses the order's place (the province is selected and the board
## glides there) and opens the order's card, with Change (where the order allows it) and Cancel. A realm order has no place: just its
## card. The army is unselected first, so focusing a place can never read as the second click of a two-click move.
func show_order(index: int) -> void:
	_bind()
	if orders == null or state == null or casting():
		return
	var list := orders.orders()
	if index < 0 or index >= list.size():
		return
	var place := OrderMarks.place_of(orders, index)
	if not place.is_empty() and state.find_province(place) != null:
		selected_army_id = ""
		focus_province(place)
	cards.open_order(list[index])


## Tells the selection host what is selected. `force` is a click: the card opens even if it was closed, and even for the same
## selection again. Without it (a new state) a closed card stays closed.
func _announce_selection(force: bool) -> void:
	var army: Army = board_army(selected_army_id) if state != null else null
	var province: Province = state.find_province(selected_province_id) if state != null else null
	var kind := ""
	var id := ""
	if province != null:
		kind = "province"
		id = province.id
		if army != null and army.location == province.id:
			kind = "army"
			id = army.id
	if kind.is_empty():
		selection_host.clear()
	elif not force and kind == selection_host.kind() and id == selection_host.id():
		selection_host.refresh()
	elif kind == "army":
		selection_host.show_army(id, selected_province_id)
	else:
		selection_host.show_province(id)


## UiCancel's "card" step, the card's close button: hides the card and puts your army back to unselected, so a click on a
## neighbouring province can never give an order from a card that is not there. The province stays selected (the close-up
## depends on it).
func dismiss_selection_card() -> void:
	_bind()
	cards.dismiss()
	if not cards.visible:
		clear_preview()  # the army it was for is unselected: its forecast goes with it
	if not cards.visible and not selected_army_id.is_empty():
		selected_army_id = ""
		_update_road_targets()
		_sync_board()


func _on_back_pressed() -> void:
	if intercept_back:
		back_requested.emit()
		return
	get_tree().change_scene_to_file(TITLE_SCENE)
