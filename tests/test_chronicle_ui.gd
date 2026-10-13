extends "res://tests/test_case.gd"
## UX-6 (design/UX_WAR_TABLE.md §5.1, §5.2): the Chronicle's Read side on the game screen, headless in the M1 style, on the recorded game whose
## turn 5 has two battles (the same fixture as test_watch_entry_ui) and on built games:
##   - the Chronicle is the ReportHost's presenter; Full report and the Turn report button are still today's modal, unchanged;
##   - a turn with a battle you fought opens the column at that battle's card (its report a click away); a quiet turn only lights the
##     medallions and the badge; the player's setting (needs you / always / never / the old full report) decides;
##   - the medallion stack: one per notable announcement, a click opens its card, a right-click dismisses it, hide and show, "+N";
##   - the column: sort, one filter chip per kind (a hidden kind still counts), pin, dismiss, restore, the summary, markers on the board;
##   - hotseat: each seat's announcements, pins and dismissals are its own, and the handoff clears the column;
##   - Esc closes the Chronicle in UiCancel's order; the Table's input contract holds with the stack and the column on it.

const GAME_SCENE := "res://ui/game_screen.tscn"
const RECORDS := "res://tests/fixtures/main_records.json"
const GAME := "m1_greedy_vs_ai"
const BATTLE_TURN := 5
const CROWN := "kingdom"
const CLANS := "beasts"

var _modes_to_reset := false


# --- fixtures -------------------------------------------------------------------------------------

static func _full_record() -> Dictionary:
	var data = JSON.parse_string(FileAccess.get_file_as_string(RECORDS))
	for g in data.games:
		if String(g.name) == GAME:
			return g.record.duplicate(true)
	return {}


func _session(turns: int) -> GameSession:
	var rec := _full_record()
	rec.history = rec.history.slice(0, turns)
	var loaded := GameSession.from_record(rec)
	assert_eq(loaded.errors, [], "the recorded game loads")
	return loaded.session


## A game screen playing on from the recorded game after `turns` turns (a hotseat game opens on the handoff cover), the Chronicle opening
## by itself on `mode`.
func _game(turns: int, mode: String = "important") -> GameScreen:
	var session := _session(turns)
	var game := load(GAME_SCENE).instantiate() as GameScreen
	game.autosave_enabled = false
	game.save_store = SaveStore.new(_scratch())
	_isolate(game)
	game.chronicle_hud.settings.auto_open = mode
	assert_eq(game.load_game(SaveGame.make(session, {}, SaveGame.MANUAL, "Test", 0)), "", "the game loads")
	return game


func _scratch() -> String:
	return "user://chronicle_ui_test_%d" % OS.get_process_id()


## The run's settings file, as it was before any Chronicle test touched the default path (set once, restored by _clean_scratch).
static var _real_settings_path := ""


## Every setting this test's games write (the Chronicle's own, the hints a turn ended marks seen) goes to a scratch file: the run's shared
## settings file, which every later test reads, must never hear of them.
func _isolate(game: GameScreen) -> void:
	DirAccess.make_dir_recursive_absolute(_scratch())
	if _real_settings_path.is_empty():
		_real_settings_path = GameSettings.default_path
	GameSettings.default_path = _scratch().path_join("settings.cfg")
	game._bind()
	game.chronicle_hud.settings.path = GameSettings.default_path


func _clean_scratch() -> void:
	var dir := _scratch()
	if DirAccess.dir_exists_absolute(dir):
		for f in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(f))
		DirAccess.remove_absolute(dir)
	if not _real_settings_path.is_empty():
		GameSettings.default_path = _real_settings_path


func _play_recorded(game: GameScreen, turn: int) -> void:
	var orders := OrderBook.orders_from_dict(_full_record().history[turn - 1].orders)
	for o in orders.get(game.session.current_player(), []):
		assert_eq(game.session.queue_order(o), "", "the recorded order is accepted")
	assert_eq(game.end_turn(), "")


## The game at the start of turn BATTLE_TURN + 1, the Crown at the controls: turn 5's two battles are in its report, and the Chronicle has
## been told. `mode` is when it opens by itself.
func _battle_turn(mode: String = "important") -> GameScreen:
	var game := _game(BATTLE_TURN - 1, mode)
	game.handoff.ready_button.pressed.emit()
	game.close_turn_report()
	game.chronicle_hud.close()
	_play_recorded(game, BATTLE_TURN)
	game.handoff.ready_button.pressed.emit()
	game.close_turn_report()
	game.chronicle_hud.close()
	_play_recorded(game, BATTLE_TURN)
	assert_eq(game.session.turn_report().turn, BATTLE_TURN)
	assert_true(game.handoff.visible, "the Crown's handoff")
	game.handoff.ready_button.pressed.emit()
	return game


func _texts(node: Node) -> String:
	var out := PackedStringArray()
	_collect(node, out)
	return "\n".join(out)


func _collect(node: Node, out: PackedStringArray) -> void:
	if node is CanvasItem and not (node as CanvasItem).visible:
		return
	if node is Label:
		out.append((node as Label).text)
	elif node is Button:
		out.append((node as Button).text)
	for c in node.get_children():
		_collect(c, out)


func _click(c: Control, button: int = MOUSE_BUTTON_LEFT) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = button
	press.pressed = true
	press.position = c.size * 0.5
	press.global_position = c.global_position + c.size * 0.5
	c._gui_input(press)


# --- the presenter ---------------------------------------------------------------------------------------

func test_the_chronicle_is_the_report_hosts_presenter_and_the_full_report_is_todays_modal() -> void:
	var game := _battle_turn()
	var hud := game.chronicle_hud
	assert_eq(game.report_host.presenter(), hud, "the Chronicle registered as the presenter")
	assert_eq(game.chronicle_button, hud.button)
	assert_false(game.chronicle_button.disabled)
	assert_false(game.report_overlay.visible, "today's modal does not open on its own")
	assert_true(hud.is_open(), "a battle you fought opens the Chronicle")
	assert_true(game.report_host.last_ready >= BATTLE_TURN, "the host heard the report was ready")
	# Full report is today's TurnReportPanel, unchanged.
	hud.column.full_report_button.pressed.emit()
	assert_true(game.report_overlay.visible and game.report_host.is_open(), "Full report opens the modal")
	assert_eq(game.report_panel.event_rows().size() > 0, true)
	game.close_turn_report()
	assert_false(game.report_overlay.visible)
	game.report_button.pressed.emit()
	assert_true(game.report_overlay.visible, "so does the Turn report button")
	game.close_turn_report()
	game.free()
	_clean_scratch()


func test_the_table_lists_the_stack_and_the_column_as_its_pieces() -> void:
	var game := _battle_turn()
	var hud := game.map.table()
	var c := game.chronicle_hud
	assert_true(hud.pieces().has(c.stack) and hud.pieces().has(c.column), "both take the mouse by design")
	assert_true(hud.notification_slot().is_ancestor_of(c.stack), "the stack is in the left-edge slot")
	assert_eq(hud.notification_slot().mouse_filter, Control.MOUSE_FILTER_IGNORE, "the slot around it ignores the mouse")
	assert_true(c.column.get_parent() == hud and c.markers.get_parent() == hud)
	assert_eq(c.markers.mouse_filter, Control.MOUSE_FILTER_IGNORE, "the markers never take a click")
	assert_true(hud.chronicle_open, "an open Chronicle narrows the safe area")
	assert_eq(hud.safe_area().end.x, hud.viewport_size().x - TableLayout.chronicle_width(hud.viewport_size()))
	var bad := []
	_walk_filters(hud, hud.pieces(), bad)
	assert_eq(bad, [], "every other control on the Table still ignores the mouse")
	game.free()
	_clean_scratch()


func _walk_filters(node: Node, pieces: Array, bad: Array) -> void:
	for ch in node.get_children():
		var control := ch as Control
		if control == null or pieces.has(control):
			continue
		if control.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			bad.append("%s (%s)" % [control.name, control.get_class()])
		_walk_filters(control, pieces, bad)


# --- when it opens ---------------------------------------------------------------------------------------

func test_a_battle_you_fought_opens_the_column_at_its_card_with_its_report_a_click_away() -> void:
	var game := _battle_turn()
	var hud := game.chronicle_hud
	assert_true(hud.is_open())
	var at := hud.column.card(hud.last_opened_at)
	assert_true(at != null, "it opened at a card: %s" % hud.last_opened_at)
	assert_false(at.item.battle.is_empty(), "at a battle's card")
	assert_true(at.battle_button != null and at.watch_button != null, "with Watch and Battle report")
	at.battle_button.pressed.emit()
	assert_true(game.battle_viewer.visible, "Battle report opens the battle viewer")
	game.battle_viewer.close()
	assert_eq(hud.column.cards.size(), hud.items().size(), "a card for every listed announcement")
	game.free()
	_clean_scratch()


func test_a_quiet_turn_only_lights_the_medallions_and_the_badge() -> void:
	var game := load(GAME_SCENE).instantiate() as GameScreen
	game.autosave_enabled = false
	game.save_store = SaveStore.new(_scratch())
	_isolate(game)
	game.chronicle_hud.settings.auto_open = "important"
	game.start_game({"players": [CROWN, CLANS], "seed": 21, "ai": {CLANS: "normal"}})
	var hud := game.chronicle_hud
	assert_eq(game.end_turn(), "", "turn 1 with no orders")
	assert_true(int(game.session.turn_report_for(CROWN).turn) >= 1)
	assert_true(hud.announcements.size() > 0, "even a quiet turn has its announcements (the treasury, at least)")
	assert_eq(hud.announcements.filter(func(it): return it.important), [], "nothing important happened")
	assert_false(hud.is_open(), "the column stays shut")
	assert_false(game.report_overlay.visible, "and so does the modal: a quiet turn doesn't nag")
	assert_false(game.map.table().chronicle_open)
	for it in hud.announcements:
		if it.routine:
			assert_true(hud.stack.medallion(String(it.id)) == null, "%s is routine: no medallion" % it.headline)
	var notable := ChronicleModel.notable(hud.items()).size()
	assert_eq(hud.stack.medallions.size() > 0, notable > 0, "a medallion for each notable announcement, none when there is none")
	assert_eq(hud.unread_count(), notable, "the badge counts exactly those")
	hud.open()
	assert_true(hud.column.cards.size() == hud.items().size() and hud.column.cards.size() > 0, "the routine ones are in the column")
	game.free()
	_clean_scratch()


func test_the_players_setting_decides_when_it_opens() -> void:
	for mode in ["never", "needs_you"]:
		var game := _battle_turn(mode)
		assert_false(game.chronicle_hud.is_open(), "%s: not for a battle" % mode)
		assert_false(game.report_overlay.visible, "%s: and not the modal" % mode)
		assert_true(game.chronicle_hud.unread_count() > 0, "%s: but the badge counts the news" % mode)
		assert_true(game.chronicle_hud.stack.visible and game.chronicle_hud.stack.medallions.size() > 0, "%s: and the medallions are lit" % mode)
		game.free()
	var always := _game(BATTLE_TURN - 1, "always")
	always.handoff.ready_button.pressed.emit()
	assert_true(always.chronicle_hud.is_open(), "always: every turn")
	always.free()
	var report := _battle_turn("report")
	assert_true(report.report_overlay.visible, "the full report: today's modal opens, as it always did")
	assert_false(report.chronicle_hud.is_open(), "and the column does not")
	report.free()
	_clean_scratch()


func test_the_choice_is_a_setting_kept_apart_from_the_game() -> void:
	var path := _scratch().path_join("settings.cfg")
	DirAccess.make_dir_recursive_absolute(_scratch())
	var s := ChronicleSettings.new(path)
	assert_eq(s.auto_open, ChronicleSettings.default_auto_open)
	assert_eq(s.sort, "importance")
	assert_true(s.set_auto_open("never") and s.set_sort("kind") and s.set_kind_hidden("abroad", true) and s.set_kind_hidden("realm", true))
	assert_false(s.set_auto_open("sometimes"))
	assert_false(s.set_kind_hidden("weather", true))
	s.stack_shown = false
	assert_eq(s.save(), "")
	var back := ChronicleSettings.load_from(path)
	assert_eq([back.auto_open, back.sort, back.hidden, back.stack_shown], ["never", "kind", ["abroad", "realm"], false])
	# The rest of the file is kept, and a file this saves is stamped like GameSettings' own.
	var g := GameSettings.new(path)
	g.set_ui_scale(125)
	assert_eq(g.save(), "")
	var both := ChronicleSettings.load_from(path)
	assert_eq(both.auto_open, "never", "the game's settings keep the Chronicle's section")
	assert_eq(GameSettings.load_from(path).ui_scale, 125, "and the Chronicle's keep the game's")
	assert_false(GameSettings.defaults_notice_due(path), "a file the Chronicle created is stamped")
	var bad := FileAccess.open(path, FileAccess.WRITE)
	bad.store_string("[chronicle]\nauto_open=\"sometimes\"\nsort=3\nhidden=[\"abroad\", \"weather\", 7]\nstack_shown=\"yes\"\n")
	bad.close()
	var odd := ChronicleSettings.load_from(path)
	assert_eq([odd.auto_open, odd.sort, odd.hidden, odd.stack_shown], [ChronicleSettings.default_auto_open, "importance", ["abroad"], true], "unknown values are ignored")
	DirAccess.remove_absolute(path)
	_clean_scratch()


# --- the stack -------------------------------------------------------------------------------------------

func test_the_stack_has_a_medallion_per_notable_announcement_and_quiet_ones_have_none() -> void:
	var game := _battle_turn()
	var hud := game.chronicle_hud
	var stack := hud.stack
	var notable := ChronicleModel.notable(hud.items())
	assert_true(stack.visible)
	assert_eq(stack.medallions.size(), mini(notable.size(), stack.capacity if stack.capacity > 0 else 1), "one for each, up to what fits")
	for i in stack.medallions.size():
		assert_eq(stack.medallions[i].id, String(notable[i].id), "in the list's order")
	var routine := hud.items().filter(func(it): return it.routine)
	for it in routine:
		assert_true(stack.medallion(String(it.id)) == null, "a routine announcement (%s) has no medallion" % it.headline)
	assert_true(routine.size() > 0, "the turn had routine news (the treasury)")
	for m in stack.medallions:
		assert_eq(m.mouse_filter, Control.MOUSE_FILTER_STOP)
		var tip := m.tooltip_text.replace("\n", " ")
		assert_true(tip.contains("Click to read it in the Chronicle"), "hover explains it")
		assert_true(tip.contains(String(hud.items().filter(func(it): return String(it.id) == m.id)[0].headline)), "and shows its headline")
	game.free()
	_clean_scratch()


func test_a_click_on_a_medallion_opens_its_card_and_a_right_click_dismisses_it() -> void:
	var game := _battle_turn("never")
	var hud := game.chronicle_hud
	assert_false(hud.is_open())
	var unread := hud.unread_count()
	assert_true(unread > 0)
	assert_true(hud.button.get_node("UnreadBadge").visible, "the Chronicle button wears an unread badge")
	assert_eq((hud.button.get_node("UnreadBadge").get_child(0) as Label).text, str(unread))
	var m: NoticeMedallion = hud.stack.medallions[hud.stack.medallions.size() - 1]
	var id := m.id
	_click(m)
	assert_true(hud.is_open(), "a click opens the Chronicle")
	assert_eq(hud.last_opened_at, id, "at that card")
	assert_true(hud.column.card(id) != null)
	assert_eq(hud.unread_count(), 0, "nothing is unread any more")
	assert_false(hud.button.get_node("UnreadBadge").visible)
	var before := hud.items().size()
	var m2: NoticeMedallion = hud.stack.medallion(id)
	_click(m2, MOUSE_BUTTON_RIGHT)
	assert_eq(hud.items().size(), before - 1, "a right-click dismisses it")
	assert_true(hud.stack.medallion(id) == null and hud.column.card(id) == null)
	assert_true(hud.store.is_dismissed(CROWN, id), "in the store, not the game")
	hud.restore_dismissed()
	assert_eq(hud.items().size(), before, "Restore brings it back")
	game.free()
	_clean_scratch()


func test_the_stack_folds_away_and_comes_back_and_shows_plus_n() -> void:
	var game := _battle_turn("never")
	var hud := game.chronicle_hud
	var stack := hud.stack
	var notable := ChronicleModel.notable(hud.items()).size()
	assert_true(notable >= 1)
	stack.toggle.pressed.emit()
	assert_false(stack.shown, "Hide folds it")
	assert_eq(stack.medallions.size(), 0, "no medallions")
	assert_true(stack.visible and stack.toggle.text.begins_with("Notices"), "a small Notices button with the count stays")
	assert_false(hud.settings.stack_shown)
	stack.toggle.pressed.emit()
	assert_true(stack.shown and stack.medallions.size() > 0, "and Notices brings the medallions back")
	# At most six below 1600 logical, then "+N".
	assert_eq(NoticeStack.capacity_for(488.0, true), 6, "1280x720: six")
	assert_true(NoticeStack.capacity_for(668.0, false) >= 8, "1600x900: room for more")
	var items := []
	for i in 9:
		items.append({"id": "x%d" % i, "turn": 1, "kind": "battles", "image": "battle_won", "headline": "News %d" % i, "detail": "d", "province": "", "place": "",
			"routine": false, "important": false, "battle": {}, "source_rows": ["d"], "type": "battle", "codex": "defended", "rank": 10, "own": true, "facts": {}})
	stack.show_items(items, {}, 6, true, true)
	assert_eq(stack.medallions.size(), 6)
	assert_true(stack.more.visible and stack.more.text == "+3", "+3 for the rest")
	stack.more_requested.connect(func(): hud.open())
	stack.more.pressed.emit()
	assert_true(hud.is_open(), "+N opens the Chronicle")
	game.free()
	_clean_scratch()


# --- the column ------------------------------------------------------------------------------------------

func test_the_column_sorts_filters_and_counts_what_it_hides() -> void:
	var game := _battle_turn("never")
	var hud := game.chronicle_hud
	hud.open()
	var column := hud.column
	var all := hud.items().size()
	assert_eq(column.cards.size(), all)
	var order := column.cards.map(func(c): return int(c.item.rank))
	var sorted_order := order.duplicate()
	sorted_order.sort()
	assert_eq(order.slice(order.size() - sorted_order.size()), sorted_order, "importance by default")
	column.sort_buttons["place"].pressed.emit()
	assert_eq(hud.settings.sort, "place")
	var places := column.cards.map(func(c): return String(c.item.place)).filter(func(p): return p != "")
	var sorted_places := places.duplicate()
	sorted_places.sort_custom(func(a, b): return a.to_lower() < b.to_lower())
	assert_eq(places, sorted_places, "by place, A to Z")
	column.sort_buttons["kind"].pressed.emit()
	var kinds := column.cards.map(func(c): return ChronicleModel.KINDS.find(String(c.item.kind)))
	var sorted_kinds := kinds.duplicate()
	sorted_kinds.sort()
	assert_eq(kinds, sorted_kinds, "by kind")
	# One chip per kind; a hidden kind still counts.
	assert_eq(column.chips.size(), ChronicleModel.KINDS.size())
	var battles: int = ChronicleModel.counts(hud._everything()).battles
	assert_true(battles >= 1)
	column.chips["battles"].button_pressed = false
	assert_true(hud.settings.hidden.has("battles"), "the choice is a setting")
	assert_eq(column.cards.size(), all - battles, "the battles are not listed")
	assert_true(column.hidden_label.visible and column.hidden_label.text == "%d hidden" % battles, "but are counted: %s" % column.hidden_label.text)
	assert_eq(column.chips["battles"].text, str(battles), "the chip still counts them")
	column.chips["battles"].button_pressed = true
	assert_eq(column.cards.size(), all, "and a click brings them back")
	assert_false(column.hidden_label.visible)
	game.free()
	_clean_scratch()


func test_the_summary_heads_the_column() -> void:
	var game := _battle_turn("never")
	var hud := game.chronicle_hud
	hud.open()
	var texts := hud.column.summary_box.get_children().map(func(c): return (c.get_child(0) as Label).text)
	assert_eq(texts.size(), hud.summary.chips.size())
	assert_true(texts.size() > 0 or hud.column.gold_label.visible, "chips or the gold line: %s" % [texts])
	if hud.column.gold_label.visible:
		assert_true(hud.column.gold_label.text.begins_with("Gold "), hud.column.gold_label.text)
	game.free()
	_clean_scratch()


func test_a_card_has_its_medallion_headline_detail_place_pin_dismiss_and_codex_link() -> void:
	var game := _battle_turn("never")
	var hud := game.chronicle_hud
	hud.open()
	for card in hud.column.cards:
		var it: Dictionary = card.item
		assert_true(card.medallion != null and card.medallion.image == String(it.image), "%s: its own medallion" % it.headline)
		assert_eq(card.headline_label.text, String(it.headline))
		assert_eq(card.detail_label.text, String(it.detail))
		assert_true(card.detail_label.max_lines_visible == 2, "the detail in up to two lines")
		assert_true(card.pin_button != null and card.dismiss_button != null)
		assert_false(card.pin_button.tooltip_text.is_empty())
		assert_false(card.dismiss_button.tooltip_text.is_empty())
		assert_true(card.codex_button != null and RulesCodex.ENTRIES.has(String(card.codex_button.get_meta("codex_key"))), "%s: its codex link" % it.headline)
		assert_eq(card.place_button != null, not String(it.province).is_empty(), "the place, when it has one")
	var with_rows := hud.column.cards.filter(func(c): return c.details_button != null)
	assert_true(with_rows.size() > 0, "a card whose report lines say more has a Details button")
	var card: NoticeCard = with_rows[0]
	assert_false(card.rows_box.visible)
	card.details_button.pressed.emit()
	assert_true(card.rows_box.visible and card.detail_label.max_lines_visible == -1, "a click expands to the full report lines")
	assert_eq(card.rows_box.get_child_count(), card.item.source_rows.size())
	assert_eq((card.rows_box.get_child(0) as Label).text, String(card.item.source_rows[0]), "exactly TurnReportText's row")
	game.free()
	_clean_scratch()


func test_the_place_chip_focuses_the_board_and_pulses_its_marker() -> void:
	var game := _battle_turn("never")
	var hud := game.chronicle_hud
	hud.open()
	var with_place := hud.column.cards.filter(func(c): return c.place_button != null)
	assert_true(with_place.size() > 0)
	var card: NoticeCard = with_place[0]
	var markers := hud.markers.marker_ids()
	assert_true(markers.has(String(card.item.id)), "each card with a place has a marker on the board")
	assert_eq(hud.markers.marker(String(card.item.id)).number, card.number, "the same number as the card")
	card.place_button.pressed.emit()
	assert_eq(game.map.selected_province_id, String(card.item.province), "the board selects the province")
	assert_true(hud.is_open(), "and the Chronicle stays open")
	game.free()
	_clean_scratch()


func test_markers_are_numbered_like_the_cards_and_go_with_the_card_or_the_column() -> void:
	var game := _battle_turn("never")
	var hud := game.chronicle_hud
	assert_eq(hud.markers.marker_ids(), [], "none while the column is closed")
	hud.open()
	var numbered := hud.column.cards.filter(func(c): return c.number > 0)
	assert_true(numbered.size() > 0)
	for i in numbered.size():
		assert_eq(numbered[i].number, i + 1, "1, 2, 3 down the list")
		assert_true(numbered[i].badge.visible)
	assert_eq(hud.markers.marker_ids().size(), numbered.size())
	var gone: NoticeCard = numbered[0]
	var id := String(gone.item.id)
	gone.dismiss_button.pressed.emit()
	assert_false(hud.markers.marker_ids().has(id), "dismissed: its marker goes")
	assert_eq(hud.markers.marker_ids().size(), numbered.size() - 1)
	hud.close()
	assert_eq(hud.markers.marker_ids(), [], "and they all go when the column closes")
	game.free()
	_clean_scratch()


# --- pins ---------------------------------------------------------------------------------------------------

func test_a_pinned_card_stays_across_turns_as_it_was_shown_and_lives_outside_the_game() -> void:
	var game := _battle_turn("never")
	var hud := game.chronicle_hud
	hud.open()
	var card: NoticeCard = hud.column.cards.filter(func(c): return not c.item.battle.is_empty())[0]
	var id := String(card.item.id)
	var shown := [String(card.item.headline), String(card.item.detail), card.item.source_rows.duplicate(), String(card.item.province)]
	var record_before := var_to_str(game.session.record())
	card.pin_button.toggled.emit(true)
	assert_true(hud.store.is_pinned(CROWN, id))
	assert_true(FileAccess.file_exists(hud.store.path()), "kept in a sidecar file: %s" % hud.store.path())
	assert_eq(var_to_str(game.session.record()), record_before, "the game's record is untouched")
	assert_eq(hud.column.card(id).pinned, true)
	assert_true(hud.stack.medallion(id) == null or hud.stack.medallion(id).pinned, "its medallion wears a pin")
	# Play on: the next turn's announcements replace the turn's, the pinned card stays, exactly as it was shown.
	hud.close()
	game.close_turn_report()
	_play_recorded(game, BATTLE_TURN + 1)
	game.handoff.ready_button.pressed.emit()  # the Clans'
	game.close_turn_report()
	hud.close()
	_play_recorded(game, BATTLE_TURN + 1)
	game.handoff.ready_button.pressed.emit()  # the Crown's again
	assert_ne(int(game.session.turn_report().turn), BATTLE_TURN)
	hud.open()
	var kept := hud.column.card(id)
	assert_true(kept != null, "the pinned card is still there on a later turn")
	if kept != null:
		assert_true(kept.item.get("carried", false), "carried from an earlier turn")
		assert_eq([String(kept.item.headline), String(kept.item.detail), kept.item.source_rows, String(kept.item.province)], shown, "exactly as it was shown")
		assert_eq(hud.column.cards[0], kept, "pinned cards from earlier turns come first")
		assert_true(kept.watch_button == null or kept.watch_button.disabled, "an old battle can't be watched again")
		var stack_ids: Array = hud.stack_items().map(func(it): return String(it.id))
		assert_true(stack_ids.has(id) and stack_ids.back() == id, "in the stack the older pinned card is below this turn's news (newest on top)")
		kept.pin_button.toggled.emit(false)
		assert_true(hud.column.card(id) == null, "unpinned, it goes with its turn")
	game.free()
	_clean_scratch()


func test_a_loaded_game_finds_its_pins_and_a_new_game_starts_clean() -> void:
	var game := _battle_turn("never")
	var hud := game.chronicle_hud
	hud.open()
	var card: NoticeCard = hud.column.cards[0]
	var id := String(card.item.id)
	card.pin_button.toggled.emit(true)
	var save := SaveGame.make(game.session, {}, SaveGame.MANUAL, "Test", 0)
	var again := load(GAME_SCENE).instantiate() as GameScreen
	again.autosave_enabled = false
	again.save_store = SaveStore.new(_scratch())
	_isolate(again)
	again.chronicle_hud.settings.auto_open = "never"
	assert_eq(again.load_game(save), "")
	again.handoff.ready_button.pressed.emit()
	assert_true(again.chronicle_hud.store.is_pinned(CROWN, id), "the sidecar is read when the save loads")
	again.free()
	var bare := load(GAME_SCENE).instantiate() as GameScreen
	bare.autosave_enabled = false
	bare.save_store = SaveStore.new(_scratch() + "_elsewhere")
	_isolate(bare)
	bare.chronicle_hud.settings.auto_open = "never"
	assert_eq(bare.load_game(save), "")
	bare.handoff.ready_button.pressed.emit()
	assert_eq(bare.chronicle_hud.store.pinned(CROWN), [], "a save loaded without its sidecar has no pins")
	bare.free()
	game.free()
	_clean_scratch()
	var elsewhere := _scratch() + "_elsewhere"
	if DirAccess.dir_exists_absolute(elsewhere):
		DirAccess.remove_absolute(elsewhere)


# --- hotseat -------------------------------------------------------------------------------------------------

func test_each_seat_has_its_own_chronicle_and_the_handoff_clears_it() -> void:
	var game := _battle_turn("never")
	var hud := game.chronicle_hud
	assert_eq(hud.seat, CROWN)
	hud.open()
	var crown_card: NoticeCard = hud.column.cards[0]
	var crown_id := String(crown_card.item.id)
	var crown_text := String(crown_card.item.headline) + String(crown_card.item.detail)
	crown_card.pin_button.toggled.emit(true)
	hud.dismiss(String(hud.column.cards[hud.column.cards.size() - 1].item.id))
	game.close_turn_report()
	assert_eq(game.end_turn(), "")
	assert_true(game.handoff.visible, "the cover is up")
	assert_false(hud.is_open(), "the column is shut behind it")
	assert_eq(hud.seat, "", "nobody in particular is looking")
	assert_eq(hud.items(), [], "nothing is listed")
	assert_false(hud.stack.visible, "no medallions")
	assert_eq(hud.markers.marker_ids(), [])
	assert_true(game.chronicle_button.disabled, "the button waits")
	game.handoff.ready_button.pressed.emit()
	assert_eq(hud.seat, CLANS, "the next seat's own Chronicle")
	assert_eq(hud.store.pinned(CLANS), [], "seat 2 never sees seat 1's pins")
	assert_eq(hud.store.dismissed(CLANS), [])
	hud.open()
	var column_text := _texts(hud.column)
	assert_false(column_text.contains(crown_text), "nothing of seat 1's pinned card is on seat 2's column")
	assert_false(hud.column.card(crown_id) != null and hud.column.card(crown_id).pinned, "and no pin on a card with the same id")
	assert_true(hud.store.is_pinned(CROWN, crown_id), "while seat 1's pin is safe in the store")
	game.free()
	_clean_scratch()


# --- Esc, the Plan page, watch mode ------------------------------------------------------------------------

func test_escape_closes_the_chronicle_in_uicancels_order() -> void:
	var game := _battle_turn()
	var hud := game.chronicle_hud
	assert_true(hud.is_open())
	var cancel := game.map.ui_cancel
	assert_eq(cancel.topmost(), "chronicle", "with no modal or march open, the Chronicle is the topmost thing")
	game.map.select_province("crownkeep")
	assert_true(cancel.is_open("card"), "the selection card is open too")
	assert_eq(cancel.cancel(), "chronicle", "Esc closes the Chronicle first")
	assert_false(hud.is_open())
	assert_false(game.map.table().chronicle_open, "and the safe area opens again")
	assert_eq(cancel.cancel(), "card", "then the card")
	game.free()
	_clean_scratch()


func test_ux5_can_put_its_plan_page_in_the_second_tab() -> void:
	var game := _battle_turn("never")
	var column := game.chronicle_hud.column
	assert_true(column.plan_tab.disabled, "the Plan tab says it is coming")
	assert_true(column.plan_tab.tooltip_text.contains("later update"))
	var page := Label.new()
	page.text = "Your orders as sentences."
	game.chronicle_hud.set_plan_page(page)
	assert_false(column.plan_tab.disabled)
	column.plan_tab.pressed.emit()
	column.show_tab("plan")
	assert_eq(column.current_tab(), "plan")
	assert_true(page.is_visible_in_tree() or column.plan_holder.visible)
	column.show_tab("read")
	assert_eq(column.current_tab(), "read")
	game.free()
	_clean_scratch()


func test_watch_mode_has_no_chronicle_and_keeps_the_modal() -> void:
	var game := load(GAME_SCENE).instantiate() as GameScreen
	game.autosave_enabled = false
	game.save_store = SaveStore.new(_scratch())
	_isolate(game)
	game.start_game({"players": [CROWN, CLANS], "seed": 11, "ai": {CROWN: "normal", CLANS: "normal"}})
	var hud := game.chronicle_hud
	assert_true(game.is_watching())
	assert_true(game.chronicle_button.disabled, "nobody in particular plays: nothing to announce to anyone")
	assert_eq(game.next_turn(), "")
	assert_false(hud.is_open())
	game.free()
	_clean_scratch()


func test_a_game_against_the_computer_starts_with_an_enabled_chronicle_and_no_news() -> void:
	var game := load(GAME_SCENE).instantiate() as GameScreen
	game.autosave_enabled = false
	game.save_store = SaveStore.new(_scratch())
	_isolate(game)
	game.start_game({"players": [CROWN, CLANS], "seed": 12, "ai": {CLANS: "normal"}})
	var hud := game.chronicle_hud
	assert_false(game.chronicle_button.disabled)
	assert_eq(hud.announcements, [], "before the first turn resolves there is no news")
	assert_false(hud.is_open())
	hud.open()
	assert_true(hud.is_open(), "the button still opens it")
	assert_true(hud.column.empty_label.visible, "and says so")
	assert_true(hud.column.empty_label.text.contains("turn"), hud.column.empty_label.text)
	game.free()
	_clean_scratch()


func test_research_waiting_is_a_need_that_settles_when_an_order_is_queued() -> void:
	var game := load(GAME_SCENE).instantiate() as GameScreen
	game.autosave_enabled = false
	game.save_store = SaveStore.new(_scratch())
	_isolate(game)
	game.chronicle_hud.settings.auto_open = "important"
	game.start_game({"players": [CROWN, CLANS], "seed": 13, "ai": {CLANS: "normal"}, "rulers": true, "paths": true})
	assert_eq(game.end_turn(), "")
	var hud := game.chronicle_hud
	var needs := hud.announcements.filter(func(it): return it.type == "need")
	assert_eq(needs.size(), 1, "nothing is being researched: a Needs you card")
	assert_eq(needs[0].kind, "needs_you")
	assert_true(hud.is_open(), "something needs you: the Chronicle opens")
	hud.close()
	var target := ""
	for n in AscensionRules.node_ids(CROWN):
		if AscensionRules.check_research(game.map.state, CROWN, n).is_empty():
			target = n
			break
	assert_false(target.is_empty())
	assert_eq(game.session.queue_order(ResearchOrder.new(target)), "")
	game._update_hud()
	assert_eq(hud.announcements.filter(func(it): return it.type == "need").size(), 0, "a research order settles it")
	game.free()
	_clean_scratch()
