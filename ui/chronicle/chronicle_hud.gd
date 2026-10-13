class_name ChronicleHud
extends RefCounted
## UX-6 (design/UX_WAR_TABLE.md §5.1, §5.2): the Chronicle's Read side on the game screen, with the smallest hooks there (one line builds it
## in _build_hud, one line in _update_hud calls refresh(), and GameScreen.report_ready_effects / open_battle_report are the two methods it
## calls back), like ResearchHud. It is the ReportHost's presenter (§1.1): when a turn's report is ready it builds the announcements of the
## VIEWER'S OWN report (ChronicleModel: GameSession.turn_report_for and state_for, filtered for fog exactly as the Turn report reads them),
## lights the medallions down the left edge (NoticeStack), counts the unread on the Chronicle button, and opens the column (ChronicleColumn)
## by itself when the turn asks for it (a setting: on important turns by default: a battle you fought, an army lost, land won or lost,
## anything that needs you). A quiet turn only lights the medallions. "Full report" and the Turn report button still open today's
## TurnReportPanel, unchanged, which is what open_report() hands back to the game screen.
##
## What it keeps outside the game: pins and dismissals in the ChronicleStore (a sidecar file beside the saves, per game and seat), the
## player's choices (sort, hidden kinds, when to open, the folded stack) in ChronicleSettings. Neither is in GameSession, a save, a record or
## a digest. In hotseat each seat has its own announcements, pins and dismissals, and the Chronicle is cleared whenever the seat changes
## (the handoff cover), so nothing of one seat's reaches the next.
##
## The Chronicle shows nothing in watch mode or at game over (nobody in particular is looking): the modal report is used there as before.
##
## API: open(at = ""), close(), toggle(), is_open(), refresh(), items() (what the column lists, in order), stack_items(), unread_count(),
##      pin(id), dismiss(id), restore_dismissed(), set_sort(mode), set_kind_hidden(kind, hidden), set_auto_open(mode), set_stack_shown(on),
##      set_plan_page(control), medallion(id)

var game: GameScreen
var settings: ChronicleSettings
var store: ChronicleStore
var button: Button
var column: ChronicleColumn
var stack: NoticeStack
var markers: ChronicleMarkers
var seat := ""  # whose announcements are showing ("" for nobody)
var turn := 0  # the turn the announcements describe
var announcements: Array = []  # this turn's, for `seat`
var summary: Dictionary = {}
var last_opened_at := ""  # the card the column last opened at
var _session: GameSession = null
var _identity := ""
var _seen := {}  # seat -> {id: true}
var _fresh := {}  # ids that were unread when the column opened (they stay gilt until it closes)
var _expanded := {}  # id -> true
var _prev_needs := {}  # seat -> {need key: true}: needs already there at the start of the last turn
var _needs_sig := ""
var _badge: PanelContainer
var _badge_label: Label
var _plan_page: Control = null
var _hud: TableHud
var _stack_room := -1
var _stack_compact := false


func _init(p_game: GameScreen) -> void:
	game = p_game
	_hud = game.map.table()
	settings = ChronicleSettings.load_from()
	store = ChronicleStore.new()
	button = _hud.make_system_button("chronicle", "Chronicle", "", toggle)
	_build_badge()
	stack = NoticeStack.new()
	stack.open_requested.connect(func(id: String): open(id))
	stack.dismiss_requested.connect(dismiss)
	stack.more_requested.connect(func(): open())
	stack.fold_toggled.connect(set_stack_shown)
	_hud.notification_slot().add_child(stack)
	_hud.register_piece(stack)
	column = ChronicleColumn.new()
	column.close_requested.connect(close)
	column.sort_changed.connect(set_sort)
	column.kind_toggled.connect(set_kind_hidden)
	column.auto_open_changed.connect(set_auto_open)
	column.full_report_requested.connect(func(): game.open_turn_report())
	column.restore_requested.connect(restore_dismissed)
	column.focus_requested.connect(_on_focus)
	column.pin_toggled.connect(pin)
	column.dismiss_requested.connect(dismiss)
	column.battle_report_requested.connect(func(e: Dictionary): game.open_battle_report(e))
	column.watch_requested.connect(func(e: Dictionary): game.watch_battle(e))
	column.codex_requested.connect(game.open_codex)
	column.expand_toggled.connect(func(id: String):
		if _expanded.has(id):
			_expanded.erase(id)
		else:
			_expanded[id] = true)
	_hud.add_child(column)
	_hud.register_piece(column)
	column.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	markers = ChronicleMarkers.new()
	markers.map = game.map
	_hud.add_child(markers)
	_hud.move_child(markers, 0)
	_hud.layout_changed.connect(_on_layout)
	_hud.compact_changed.connect(func(_on): _refresh_stack())
	game.map.ui_cancel.register("chronicle", is_open, close)
	game.report_host.set_presenter(self)
	_update_button()
	_on_layout()


# --- the ReportHost presenter ------------------------------------------------------------------------

## Today's modal report (the Turn report button, the column's Full report, the victory screen's Final turn report) is the game screen's.
func open_report() -> bool:
	return game.open_report()


func close_report() -> void:
	game.close_report()


func is_report_open() -> bool:
	return game.is_report_open()


## The report of `report_turn` is ready (after the board's playback): build the viewer's announcements, light the medallions, sound the
## report's cues and start the player's battles when Settings ask, and open the column when the turn asks for it.
func on_report_ready(report_turn: int, context: Dictionary) -> void:
	_sync_game()
	var eyes := _eyes()
	if eyes.is_empty():
		game.on_report_ready(report_turn, context)  # watch mode: nobody in particular, so today's modal, with the computers' thoughts
		return
	if eyes != seat:
		_switch_seat(eyes)
	_build()
	_refresh_all()
	if settings.auto_open == "report":
		game.on_report_ready(report_turn, context)  # the old way, by choice: the modal opens, the cues sound, the battles auto-watch
		_remember_needs()
		return
	game.report_ready_effects(context)
	var act := ChronicleModel.auto_open(_openers(), settings.auto_open)
	_remember_needs()
	if bool(act.open):
		open(String(act.at))


# --- building ---------------------------------------------------------------------------------------

## The announcements of the viewer's own report of the last resolved turn (ChronicleModel). Only the per-viewer accessors are read.
func _build() -> void:
	var session := game.session
	var report: Dictionary = session.turn_report_for(seat)
	var st: GameState = session.state_for(seat)
	turn = int(report.get("turn", 0))
	if turn <= 0 or st == null:
		announcements = []
		summary = ChronicleModel.summary([], report, st, seat)
		return
	var before: GameState = session.view_before(seat) if bool(report.get("fog", false)) else null
	var needs := ChronicleModel.needs(st, seat, turn, session.current_orders())
	_needs_sig = _signature(needs)
	announcements = ChronicleModel.build(report, st, seat, {"before": before, "needs": needs})
	summary = ChronicleModel.summary(announcements, report, st, seat)


## The current-state needs change as the player gives orders (a research order settles "Choose what to research").
func _refresh_needs() -> void:
	if seat.is_empty() or turn <= 0 or game.session.phase() != GameSession.Phase.ORDERS:
		return
	var st: GameState = game.session.state_for(seat)
	var needs := ChronicleModel.needs(st, seat, turn, game.session.current_orders())
	var sig := _signature(needs)
	if sig == _needs_sig:
		return
	_needs_sig = sig
	announcements = announcements.filter(func(it): return String(it.type) != "need")
	announcements = ChronicleModel.need_items(needs, st, turn) + announcements
	_refresh_all()


func _signature(needs: Array) -> String:
	return "|".join(needs.map(func(n): return "%s:%s" % [n.key, n.text.hash()]))


## The announcements that may open the column: this turn's, kept and shown, and a need only when it is new.
func _openers() -> Array:
	var old: Dictionary = _prev_needs.get(seat, {})
	return _pool().filter(func(it):
		if String(it.type) == "need" and old.has(String(it.need)):
			return false  # it was there last turn: the medallion and the badge say so, the column does not open for it again
		return not (settings.hidden as Array).has(String(it.kind)))


func _remember_needs() -> void:
	var keys := {}
	for it in announcements:
		if String(it.type) == "need":
			keys[String(it.need)] = true
	_prev_needs[seat] = keys


# --- the list -----------------------------------------------------------------------------------------

## This turn's announcements that were not dismissed, plus the cards the seat pinned on earlier turns (as they were shown).
func _pool() -> Array:
	var out := announcements.filter(func(it): return not store.is_dismissed(seat, String(it.id)))
	return out


func _carried() -> Array:
	var live := {}
	for it in announcements:
		live[String(it.id)] = true
	var out := []
	for payload in store.pinned(seat):
		if not live.has(String(payload.id)) and not store.is_dismissed(seat, String(payload.id)):
			payload["carried"] = true
			out.append(payload)
	return out


## What the column lists, in order: pinned cards from earlier turns, then this turn's in the sort the player chose, less the kinds hidden.
func items() -> Array:
	if seat.is_empty():
		return []
	var pool: Array = ChronicleModel.sorted(_pool(), settings.sort)
	return ChronicleModel.filtered(_carried() + pool, settings.hidden)


## All that is listable before the filter, to count what the filter hides.
func _everything() -> Array:
	return _carried() + _pool() if not seat.is_empty() else []


## The medallions: the listed announcements that are not routine, this turn's first in the list's order and the cards pinned on earlier turns
## below them (newest on top, §1.3).
func stack_items() -> Array:
	var notable := ChronicleModel.notable(items())
	return notable.filter(func(it): return not bool(it.get("carried", false))) + notable.filter(func(it): return bool(it.get("carried", false)))


func unread_count() -> int:
	if seat.is_empty():
		return 0
	var seen: Dictionary = _seen.get(seat, {})
	return stack_items().filter(func(it): return not seen.has(String(it.id)) and not bool(it.get("carried", false))).size()


func medallion(id: String) -> NoticeMedallion:
	return stack.medallion(id)


# --- showing ------------------------------------------------------------------------------------------

func _refresh_all() -> void:
	_refresh_stack()
	_refresh_column()
	_update_button()


func _refresh_stack() -> void:
	if stack == null:
		return
	var list := stack_items()
	var seen: Dictionary = _seen.get(seat, {})
	var flags := {}
	for it in list:
		var id := String(it.id)
		flags[id] = {"unread": not seen.has(id) and not bool(it.get("carried", false)), "pinned": store.is_pinned(seat, id)}
	_stack_room = _room()
	_stack_compact = _hud.compact
	stack.show_items(list, flags, _stack_room, _stack_compact, settings.stack_shown)


func _refresh_column() -> void:
	if column == null:
		return
	if not column.visible:
		markers.set_markers([])
		return
	var list := items()
	var cards := []
	var markers_now := []
	var n := 0
	var seen_cards := {}
	for it in list:
		var id := String(it.id)
		var number := 0
		if column.visible and not String(it.province).is_empty():
			n += 1
			number = n
			markers_now.append({"number": n, "province": String(it.province), "id": id})
		cards.append({"item": it, "opts": {"number": number, "pinned": store.is_pinned(seat, id), "unread": _fresh.has(id),
			"expanded": _expanded.has(id), "watch_why": _watch_why(it)}})
		seen_cards[id] = true
	var everything := _everything()
	var counts := ChronicleModel.counts(everything)
	column.show_state({"cards": cards, "summary": summary if not seat.is_empty() else {}, "sort": settings.sort, "hidden": settings.hidden,
		"counts": counts, "hidden_count": everything.size() - list.size(), "dismissed_count": _dismissed_now().size(),
		"auto_open": settings.auto_open, "empty": _empty_text()})
	markers.set_markers(markers_now if column.visible else [])


func _dismissed_now() -> Array:
	return announcements.filter(func(it): return store.is_dismissed(seat, String(it.id)))


func _empty_text() -> String:
	if seat.is_empty():
		return "Nothing to announce while nobody in particular is looking."
	if turn <= 0:
		return "Nothing yet. The news of each turn arrives here when the turn starts."
	if announcements.is_empty() and store.pinned(seat).is_empty():
		return "A quiet turn: nothing to announce. Full report has every line."
	return "Everything is hidden or dismissed. Switch a kind back on above, or press Restore."


func _watch_why(it: Dictionary) -> String:
	if (it.battle as Dictionary).is_empty():
		return ""
	if bool(it.get("carried", false)) or int(it.turn) != turn:
		return "Only the battles of the turn that just resolved can be played back."
	return BattleHost.watch_problem(it.battle, true)


func _update_button() -> void:
	if button == null:
		return
	var active := not _eyes().is_empty()
	button.disabled = not active
	var n := unread_count()
	_badge.visible = n > 0 and active
	_badge_label.text = str(n)
	var help := "The turn's announcements, sorted and filtered, each with its own image: battles, land, rulers, magic and your realm. Pin the ones to keep, dismiss the rest. The medallions down the left edge are the same news."
	if not active:
		help = "Nobody in particular plays a side right now, so there is nothing to announce to you. Turn report has what happened."
	elif n > 0:
		help += " %s unread." % TooltipText.count(n, "announcement")
	button.tooltip_text = TooltipText.plain("Chronicle", help)


func _build_badge() -> void:
	_badge = PanelContainer.new()
	_badge.name = "UnreadBadge"
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = UiPalette.GILT
	style.set_corner_radius_all(9)
	style.content_margin_left = 5
	style.content_margin_right = 5
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	_badge.add_theme_stylebox_override("panel", style)
	_badge_label = Label.new()
	_badge_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge_label.add_theme_font_size_override("font_size", 12)
	_badge_label.add_theme_color_override("font_color", UiPalette.KEYLINE_INK)
	_badge.add_child(_badge_label)
	button.add_child(_badge)
	# A pill on the button's top right corner, as wide as its number: a zero-width box at the corner that grows leftward.
	_badge.anchor_left = 1.0
	_badge.anchor_right = 1.0
	_badge.anchor_top = 0.0
	_badge.anchor_bottom = 0.0
	_badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_badge.grow_vertical = Control.GROW_DIRECTION_END
	_badge.offset_left = 6.0
	_badge.offset_right = 6.0
	_badge.offset_top = -7.0
	_badge.offset_bottom = -7.0


## How many medallions the left edge has room for at this window size.
func _room() -> int:
	return NoticeStack.capacity_for(float(TableLayout.bands(_hud.viewport_size())["stack"].size.y), _hud.compact)


## The column's place on the right edge: its band's width (420 px, 360 px below 1600 logical), full height. The stack is rebuilt only when
## the room for medallions changed (the Table's layout_changed is emitted by every relayout, and a rebuild must never ask for another).
func _on_layout() -> void:
	if column == null:
		return
	var w := TableLayout.chronicle_width(_hud.viewport_size())
	column.offset_left = -w
	column.offset_right = 0.0
	column.offset_top = 0.0
	column.offset_bottom = 0.0
	if _room() != _stack_room or _hud.compact != _stack_compact:
		_refresh_stack()


# --- opening and closing ---------------------------------------------------------------------------------

func is_open() -> bool:
	return column != null and column.visible


func toggle() -> void:
	if is_open():
		close()
	else:
		open()


## Opens the column (at the card `at`, which it scrolls to and flashes). Nothing happens when nobody in particular is looking.
func open(at: String = "") -> void:
	_sync_game()
	var eyes := _eyes()
	if eyes.is_empty():
		return
	if eyes != seat:
		_switch_seat(eyes)
		_build()
	var was_open := is_open()
	var seen: Dictionary = _seen.get(seat, {})
	if not was_open:
		_fresh = {}
		for it in stack_items():
			if not seen.has(String(it.id)):
				_fresh[String(it.id)] = true
	column.visible = true
	_hud.set_chronicle_open(true)
	_on_layout()
	last_opened_at = at
	for it in stack_items():
		seen[String(it.id)] = true
	_seen[seat] = seen
	_refresh_all()
	column.show_tab("read" if column.current_tab() != "plan" else "plan")
	if not at.is_empty():
		column.reveal(at)
	if not was_open:
		game.report_host.notify_opened(turn)


func close() -> void:
	if not is_open():
		return
	column.visible = false
	_hud.set_chronicle_open(false)
	_fresh = {}
	_refresh_all()
	game.report_host.notify_closed(turn)


## UX-5 puts its Plan page in the column's second tab.
func set_plan_page(page: Control) -> void:
	_plan_page = page
	column.set_plan_page(page)


# --- the player's choices --------------------------------------------------------------------------------

func pin(id: String) -> void:
	if store.is_pinned(seat, id):
		store.unpin(seat, id)
	else:
		for it in _everything():
			if String(it.id) == id:
				store.pin(seat, ChronicleModel.pin_payload(it))
				break
	_save()
	_refresh_all()


func dismiss(id: String) -> void:
	if seat.is_empty():
		return
	store.unpin(seat, id)
	store.dismiss(seat, id)
	_save()
	_refresh_all()


func restore_dismissed() -> void:
	store.restore_all(seat, _dismissed_now().map(func(it): return String(it.id)))
	_save()
	_refresh_all()


func set_sort(mode: String) -> void:
	if settings.set_sort(mode):
		settings.save()
		_refresh_all()


func set_kind_hidden(kind: String, hidden: bool) -> void:
	if settings.set_kind_hidden(kind, hidden):
		settings.save()
		_refresh_all()


func set_auto_open(mode: String) -> void:
	if settings.set_auto_open(mode):
		settings.save()
		_refresh_column()


func set_stack_shown(on: bool) -> void:
	settings.stack_shown = on
	settings.save()
	_refresh_stack()


func _save() -> void:
	store.save()


func _on_focus(province_id: String, id: String) -> void:
	game.map.selected_army_id = ""  # so the click can't be taken as a move order for a selected army
	game.map.focus_province(province_id)
	markers.pulse(id)


# --- whose eyes ---------------------------------------------------------------------------------------------

## The faction whose announcements show: the person at the controls. "" when nobody in particular is looking (watch mode, the handoff
## cover, the end of the game), where the Chronicle is empty and closed.
func _eyes() -> String:
	var session := game.session
	if session == null or session.phase() == GameSession.Phase.INVALID or session.is_over() or game.is_watching():
		return ""
	var who := game.viewer()
	return who if session.players().has(who) else ""


## Called whenever the game screen changes what it shows (GameScreen._update_hud): follows the seat, a new or loaded game, and the needs.
func refresh() -> void:
	_sync_game()
	var eyes := _eyes()
	if eyes != seat:
		_switch_seat(eyes)
		if not eyes.is_empty() and int(game.session.turn_report_for(eyes).get("turn", 0)) > 0:
			_build()  # ready for the cover to lift: the report-ready that follows decides whether the column opens
		_refresh_all()
	elif not seat.is_empty():
		_refresh_needs()
		_update_button()
	else:
		_update_button()


## The seat changed (a hotseat handoff, a new game, the end): the Chronicle of the last seat is cleared and closed before anything of the
## next is built, so nothing of one seat's reaches the next.
func _switch_seat(eyes: String) -> void:
	if is_open():
		column.visible = false
		_hud.set_chronicle_open(false)
	_fresh = {}
	announcements = []
	summary = {}
	turn = 0
	seat = eyes
	NoticeArt.viewer = eyes  # the medallions wear the seat's own faction set (UX-ART #222)
	_needs_sig = ""
	markers.set_markers([])
	stack.show_items([], {}, 0, false, true)
	column.show_state({"cards": [], "summary": {}, "sort": settings.sort, "hidden": settings.hidden, "counts": {}, "hidden_count": 0,
		"dismissed_count": 0, "auto_open": settings.auto_open, "empty": ""})


## A new or loaded game: the store opens that game's sidecar (a new game starts clean), and everything of the last game is dropped.
func _sync_game() -> void:
	var session := game.session
	if session == null or session == _session:
		return
	_session = session
	_identity = ChronicleStore.identity(str(int(game.config.get("seed", 0))), session.players())
	store.root = game.save_store.root if game.save_store != null else SaveStore.default_root
	store.open_game(_identity, game.loaded_header.is_empty())
	_seen = {}
	_prev_needs = {}
	_expanded = {}
	_fresh = {}
	seat = "?"  # forces _switch_seat on the next refresh
	if is_open():
		column.visible = false
		_hud.set_chronicle_open(false)
	announcements = []
