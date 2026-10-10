extends "res://tests/test_case.gd"
## The 3D board (M3a.1, world3d/board3d.gd): the game's map drawn as the 3D world under the map
## screen's 2D UI. Headless: nothing renders, but the board's picking, projection, state sync and
## playback are all computed, so they are tested here exactly as the windowed game runs them.
##   * the model table (world3d/models.json): every unit type in the data has a row, every row draws
##   * project / unproject round trip, and picking: a click on every province and every army returns
##     its own id, at the whole-map, default and near zooms
##   * selection through the board drives the map screen's own signals and API (select, two-click
##     move, hover preview, codex)
##   * state sync: owners, armies and ghost recruits follow the map's state and orders
##   * playback never changes the outcome: applying a turn's events to the board model of the state
##     before gives the board model of the state after (many autoplayed turns, with and without
##     rulers), the played board stands as one built from the state after, and the states are
##     deep-equal before and after
##   * the board only reads the game: no dice and no resolver in its code
## Expected values come from the data and the states, never hardcoded.

const GAME_SCENE := "res://ui/game_screen.tscn"
const Playback := preload("res://world3d/playback.gd")
const Models := preload("res://world3d/models.gd")
const BOARD_SIZE := Vector2(1200, 836)
const BOARD_FILES := ["res://world3d/board3d.gd", "res://world3d/board_overlay.gd", "res://world3d/armies.gd",
	"res://world3d/world_view.gd", "res://world3d/playback.gd", "res://world3d/models.gd", "res://world3d/kit.gd",
	"res://world3d/terrain3d.gd", "res://world3d/muster.gd", "res://world3d/choreo.gd"]


# --- fixtures -------------------------------------------------------------------------------------

func _game(config: Dictionary = {"players": ["kingdom", "beasts"], "seed": 4242}) -> GameScreen:
	var game := load(GAME_SCENE).instantiate() as GameScreen
	game.autosave_enabled = false
	game.start_game(config)
	return game


## A game screen showing the 3D board, built at once (headless: no frames run).
func _game_with_board(config: Dictionary = {"players": ["kingdom", "beasts"], "seed": 4242}) -> GameScreen:
	var game := _game(config)
	game.use_board("3d")
	var b: Board3D = game.map.board
	b.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	b.size = BOARD_SIZE
	b.build_now()
	return game


## A board standing `state` with no game screen around it.
func _board_for(state: GameState) -> Board3D:
	var map := load("res://ui/map_screen.tscn").instantiate() as MapScreen
	map.set_state(state, state.factions[0].id)
	var b := Board3D.new()
	map.set_board(b)
	b.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	b.size = BOARD_SIZE
	b.build_now()
	return b


func _free_board(b: Board3D) -> void:
	var map: Node = b.map
	if map != null:
		map.free()
	elif is_instance_valid(b):
		b.free()


## `turns` turns of a game the real AI plays for both sides, through the real resolver: [{"before",
## "events", "after"}]. With rulers when `rulers` is true.
func _autoplay(game_seed: int, turns: int, rulers: bool) -> Array:
	var out: Array = []
	var st: GameState = GameState.with_rulers(game_seed, {}, []) if rulers else GameState.new(game_seed)
	for t in turns:
		var orders := {}
		var seat := 0
		for f in st.factions:
			var rng := SeededRNG.new(game_seed * 7919 + (seat + 1) * 104729 + t * 31)
			orders[f.id] = AIPlayer.new().plan_orders(st, f.id, rng, "normal")
			seat += 1
		var res: Dictionary = TurnResolver.resolve(st, orders, TurnResolver.seed_for_turn(st))
		if res.get("new_state") == null:
			break
		out.append({"before": st, "events": res["events"], "after": res["new_state"]})
		st = res["new_state"]
		var over := false
		for f in st.factions:
			var cap := st.find_province(f.capital)
			if cap == null or cap.owner != f.id:
				over = true
		if over:
			break
	return out


func _zooms(b: Board3D) -> Array:
	return [0.0, Board3D.FOCUS_ZOOM, 0.9]


func _frame(b: Board3D, target: Vector2, z: float) -> void:
	b.zoom = z
	b.goal = b.rig_for(target, z)
	b._snap_rig()


func _on_screen(b: Board3D, s: Vector2) -> bool:
	return s.x > 4 and s.y > 4 and s.x < b.size.x - 4 and s.y < b.size.y - 4


# --- the model table ------------------------------------------------------------------------------

func test_every_unit_type_has_a_model_row_and_draws() -> void:
	assert_eq(Models.problems(), [], "the model table's rows are all sound")
	var ids: Array = []
	for f in FactionData.FACTIONS:
		for u in f.unit_types:
			ids.append(u.id)
		ids.append(f.commander.id)
	for r in RulerData.RULERS:
		ids.append(r.id)
	for id in PathData.NEW_UNITS.keys():
		ids.append(id)
	for id in ids:
		assert_false(Models.figure_row(id).is_empty(), "%s has a row in world3d/models.json" % id)
		var fm: Dictionary = Models.figure_mesh(id)
		assert_true(fm.get("mesh") is Mesh, "%s draws a mesh (%s)" % [id, fm.get("source", "?")])
	for kind in ["fortress", "fort", "cottage", "tree_broadleaf", "tree_pine", "rock"]:
		assert_true(Models.building_primitive(kind) is Mesh, "%s has a primitive piece" % kind)


func test_block_sizes_follow_the_table() -> void:
	var b: Dictionary = Models.table()["block"]
	assert_eq(Models.block_size(0), 0, "no units, no figures")
	assert_eq(Models.block_size(1), clampi(int(ceil(float(b.per_unit))), int(b.min), int(b.max)))
	assert_eq(Models.block_size(100), int(b.max), "a block never has more than the table's maximum")
	for n in range(1, 20):
		assert_true(Models.block_size(n + 1) >= Models.block_size(n), "a bigger block never shows fewer figures")
	assert_true(Models.block_rule_text().contains(str(int(b.max))), "the tooltips explain the rule with the table's numbers")


# --- projection and picking -----------------------------------------------------------------------

func test_project_and_unproject_round_trip_at_every_zoom() -> void:
	var game := _game_with_board()
	var b: Board3D = game.map.board
	var t = b.wv.terrain
	for id in t.ids:
		var c: Vector2 = t.centre_of(id)
		for z in _zooms(b):
			_frame(b, c, z)
			var s := b.project(c)
			assert_true(_on_screen(b, s), "%s's centre is on screen at zoom %.2f" % [id, z])
			var back := b.unproject(s)
			assert_true(back.distance_to(c) < 1.0, "%s: unproject(project(p)) comes back to p at zoom %.2f (%.2f off)" % [id, z, back.distance_to(c)])
	game.free()


func test_a_click_on_every_province_picks_that_province() -> void:
	var game := _game_with_board()
	var b: Board3D = game.map.board
	var t = b.wv.terrain
	var wrong := 0
	for z in _zooms(b):
		for id in t.ids:
			## a point of its land away from the armies' stage: its centre pushed toward its name plate
			var p: Vector2 = t.centre_of(id) + Vector2(0, t.stage_r[t.index_of(id)] * 1.4)
			if t.province_at(p) != id:
				p = t.centre_of(id)
			if z > 0.0:
				_frame(b, p, z)
			else:
				b.fit_whole(true)
			var s := b.project(p)
			if not _on_screen(b, s):
				continue
			if b.province_at(s) != id:
				wrong += 1
				fail("a click on %s at zoom %.2f picked %s" % [id, z, b.province_at(s)])
	assert_eq(wrong, 0, "every province picks itself")
	b.fit_whole(true)
	assert_eq(b.province_at(Vector2(4, 4)), "", "the sea in the corner picks nothing")
	game.free()


func test_a_click_on_every_army_picks_that_army() -> void:
	var game := _game_with_board({"players": ["kingdom", "beasts"], "seed": 11, "rulers": true})
	var b: Board3D = game.map.board
	var st: GameState = game.map.state
	assert_true(st.armies.size() >= 4, "a game with rulers starts with an army and a ruler each")
	for z in _zooms(b):
		for a in st.armies:
			_frame(b, b.wv.terrain.centre_of(a.location), z)
			var r := b.army_rect(a.id)
			assert_true(r.size.x > 0.0, "%s stands on the board at zoom %.2f" % [a.id, z])
			## the figure of this army that no other army's box covers
			var spot := Vector2(-1, -1)
			for pair in b.armies.army_points(a.id):
				var s := b.project3((pair[0] + pair[1]) * 0.5)
				var clash := false
				for o in st.armies:
					if o.id != a.id and b.army_rect(o.id).has_point(s):
						clash = true
				if not clash and _on_screen(b, s):
					spot = s
					break
			if spot.x < 0:
				continue
			assert_eq(b.army_at(spot), a.id, "a click on %s's figures at zoom %.2f picks it" % [a.id, z])
	game.free()


# --- selection through the board drives the map screen ---------------------------------------------

func test_clicks_on_the_board_select_through_the_map_screen() -> void:
	var game := _game_with_board()
	var b: Board3D = game.map.board
	var map := game.map
	var st: GameState = map.state
	var me := map.viewing_faction_id
	var picked := []
	map.province_selected.connect(func(id): picked.append(["province", id]))
	map.army_selected.connect(func(id): picked.append(["army", id]))
	var t = b.wv.terrain
	## a province
	var other: String = "thornvale"
	_frame(b, t.centre_of(other), Board3D.FOCUS_ZOOM)
	b.click(b.project(t.centre_of(other) + Vector2(0, t.stage_r[t.index_of(other)] * 1.4)))
	assert_eq(map.selected_province_id, other, "a click on the land selects its province")
	assert_true(picked.has(["province", other]), "and the map screen emits province_selected")
	## my army, by its figures
	var army: Army = null
	for a in st.armies:
		if a.owner == me:
			army = a
	_frame(b, t.centre_of(army.location), Board3D.FOCUS_ZOOM)
	b.click(b.army_rect(army.id).get_center())
	assert_eq(map.selected_army_id, army.id, "a click on an army's figures selects it")
	assert_true(picked.has(["army", army.id]), "and the map screen emits army_selected")
	## hover a neighbour: the move preview, then click it: the two-click move
	var here := st.find_province(army.location)
	var to: String = here.neighbors[0]
	b.fit_whole(true)
	var s := b.project(t.centre_of(to) + Vector2(0, t.stage_r[t.index_of(to)] * 1.4))
	b.hover(s)
	assert_eq(b.hover_id, to, "the board knows the province under the mouse")
	assert_true(map.hover_panel.visible, "hovering a neighbour with your army selected shows the move preview")
	assert_eq(map.hover_label.text, map.orders.move_preview(army.id, to).text, "the same forecast as the 2D map")
	b.click(s)
	var moves := game.session.current_orders().filter(func(o): return o is MoveOrder)
	assert_eq(moves.size(), 1, "the second click ordered the move (%s)" % map.status_text)
	if moves.size() == 1:
		assert_eq(moves[0].to, to)
	## the tooltips: the province's (its 2D wording, the 3D marks, its income) and the army's
	var tip: String = b._get_tooltip(s)
	assert_true(tip.contains(st.find_province(to).name), "the ground's tooltip names the province")
	assert_true(tip.contains("Codex:"), "and links its codex entry")
	## right-click: the codex entry of what is under the mouse
	var asked := []
	map.codex_requested.connect(func(k): asked.append(k))
	var rc := CodexLink.right_click()
	rc.position = s
	b._gui_input(rc)
	assert_eq(asked, [TooltipText.codex_for("province")], "a right-click on the land opens the Province entry")
	game.free()


func test_a_trackpad_pinch_or_two_finger_scroll_zooms_like_the_wheel() -> void:
	## playtest 10-10: on a MacBook, zoom did nothing. macOS sends a trackpad's pinch and two-finger scroll as
	## gestures, never as wheel clicks, and the board only listened to the wheel.
	var pinch_out := InputEventMagnifyGesture.new()
	pinch_out.factor = 1.02
	var pinch_in := InputEventMagnifyGesture.new()
	pinch_in.factor = 0.98
	var scroll_up := InputEventPanGesture.new()
	scroll_up.delta = Vector2(0, -2)
	var scroll_down := InputEventPanGesture.new()
	scroll_down.delta = Vector2(0, 2)
	var sideways := InputEventPanGesture.new()
	sideways.delta = Vector2(3, 0)
	assert_true(Board3D.trackpad_zoom(pinch_out) > 0.0, "spreading the fingers zooms in")
	assert_true(Board3D.trackpad_zoom(pinch_in) < 0.0, "pinching them together zooms out")
	assert_true(Board3D.trackpad_zoom(scroll_up) > 0.0, "a two-finger scroll up zooms in, as the wheel up does")
	assert_true(Board3D.trackpad_zoom(scroll_down) < 0.0, "a scroll down zooms out")
	assert_eq(Board3D.trackpad_zoom(sideways), 0.0, "a sideways scroll doesn't zoom")
	var big := InputEventMagnifyGesture.new()
	big.factor = 3.0
	assert_true(absf(Board3D.trackpad_zoom(big)) <= 0.07 + 0.000001, "one gesture event zooms at most a wheel click")
	assert_eq(Board3D.trackpad_zoom(CodexLink.right_click()), 0.0, "other events don't zoom")
	## through the board's own input, at the middle of the board
	var game := _game_with_board()
	var b: Board3D = game.map.board
	var mid := b.size * 0.5
	b.zoom = 0.5
	pinch_out.position = mid
	b._gui_input(pinch_out)
	assert_true(b.zoom > 0.5, "a pinch on the board zooms it in (%.3f)" % b.zoom)
	var z := b.zoom
	scroll_down.position = mid
	b._gui_input(scroll_down)
	assert_true(b.zoom < z, "a two-finger scroll down zooms it out (%.3f)" % b.zoom)
	z = b.zoom
	sideways.position = mid
	b._gui_input(sideways)
	assert_eq(b.zoom, z, "a sideways scroll leaves the zoom")
	game.free()


# --- state sync -----------------------------------------------------------------------------------

func test_the_board_follows_the_state_owners_armies_and_queued_recruits() -> void:
	var game := _game_with_board()
	var b: Board3D = game.map.board
	var st: GameState = game.map.state
	_check_board_matches(b, st, "at the start")
	## a queued recruit stands as a ghost in the yard; cancelling it removes it
	var f := st.find_faction(game.map.viewing_faction_id)
	game.map.selected_army_id = ""
	game.map.select_province(f.capital)
	var types: Array = game.map.orders.recruitable_types()
	assert_eq(game.map.queue_recruit(types[0].id), "", "a recruit can be queued")
	assert_eq(b.armies.ghost_count(), 1, "the queued recruit stands as one ghost figure")
	assert_eq(b.armies.ghost_list()[0]["province"], f.capital, "in the capital where it will join")
	game.map.cancel_order(0)
	assert_eq(b.armies.ghost_count(), 0, "cancelling the order removes the ghost")
	## a new state (a whole hotseat turn): the board stands it
	game.end_turn()
	game._on_handoff_acknowledged()
	game.end_turn()
	game._on_handoff_acknowledged()
	if b.is_playing():
		b.skip_playback()
	assert_false(b.is_playing(), "the playback can be skipped")
	_check_board_matches(b, game.map.state, "after a turn")
	game.free()


func _check_board_matches(b: Board3D, st: GameState, when: String) -> void:
	var painted: Dictionary = b.wv.owners_painted()
	var seats: Array = b.map.seat_order()
	for p in st.provinces:
		var want: Color = UiPalette.owner_color(st, p.owner, seats) if not p.owner.is_empty() else Color(0, 0, 0, 0)
		var got: Color = painted[p.id]
		assert_true(got.is_equal_approx(want) or (p.owner.is_empty() and got.a < 0.5) or _close(got, want),
			"%s: %s's wash is its owner's colour" % [when, p.id])
	var ids: Array = b.armies.armies.keys()
	ids.sort()
	var want_ids: Array = st.armies.map(func(a): return a.id)
	want_ids.sort()
	assert_eq(ids, want_ids, "%s: the board stands every army of the state, and no other" % when)
	var snap: Dictionary = b.armies.snapshot()
	for a in st.armies:
		assert_eq(snap[a.id]["province"], a.location, "%s: %s stands in %s" % [when, a.id, a.location])


func _close(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.01 and absf(a.g - b.g) < 0.01 and absf(a.b - b.b) < 0.01 and absf(a.a - b.a) < 0.01


func test_the_board_is_covered_by_the_handoff_and_overlays() -> void:
	var game := _game_with_board()
	assert_false(game._board_covered(), "nothing covers the board while a player gives orders")
	game.open_codex("")
	assert_true(game._board_covered(), "the codex covers it")
	game.codex.close()
	game.end_turn()
	assert_true(game.handoff.visible, "a hotseat End turn shows the handoff cover")
	assert_true(game._board_covered(), "the handoff cover covers the board (it stops rendering)")
	assert_false(game.map.board.is_visible_in_tree() and game.map.visible, "and the map with the board is hidden")
	game.free()


func test_the_2d_board_is_still_a_setting() -> void:
	var game := _game_with_board()
	assert_false(game.map.map_canvas.visible, "the 3D board replaces the 2D regions")
	game.use_board("2d")
	assert_true(game.map.board == null, "the 2D board has no 3D world")
	assert_true(game.map.map_canvas.visible, "and the 2D regions are back")
	assert_eq(game.map.regions.size(), game.map.state.provinces.size(), "with every province")
	game.free()


# --- playback never changes the outcome ------------------------------------------------------------

func test_playing_the_events_gives_the_next_state_board_model() -> void:
	var turns := 0
	for game_seed in [3, 4242, 90210, 77, 5150]:
		for rulers in [false, true]:
			for turn in _autoplay(game_seed, 12, rulers):
				var played := Playback.apply_events(Playback.model_of(turn["before"]), turn["events"])
				var built := Playback.model_of(turn["after"])
				assert_eq(played, built, "seed %d%s turn %d: the events lead to the state after" % [
					game_seed, " (rulers)" if rulers else "", (turn["before"] as GameState).current_turn + 1])
				turns += 1
	assert_true(turns >= 60, "checked over many turns (%d)" % turns)


func test_the_played_board_stands_as_one_built_from_the_next_state() -> void:
	## M3a.2: over several games, the phased playback (marches, battle exchanges with their fallen,
	## capture sweeps, recruits marching in, war camps) still ends exactly where a board built from the
	## state after stands, with a planning player's gathered columns standing before the turn
	var played_any := 0
	var battles := 0
	for game_seed in [4242, 77, 11]:
		var turns := _autoplay(game_seed, 14, true)
		var b: Board3D = null
		for turn in turns:
			var before: GameState = turn["before"]
			var after: GameState = turn["after"]
			if b == null:
				b = _board_for(before)
			var dict_before: Dictionary = before.to_dict()
			var dict_after: Dictionary = after.to_dict()
			## a plan stood on the board before the turn: the first faction's armies gathered to march
			b.stand(before)
			var dep := {}
			for a in before.armies:
				if a.owner == before.factions[0].id and not before.find_province(a.location).neighbors.is_empty():
					dep[a.id] = {"to": before.find_province(a.location).neighbors[0], "via": ""}
			b.armies.show_plan({"departing": dep, "owner": before.factions[0].id})
			## as the game does it: the map shows the state after, and the board plays the turn up to it
			b.map.set_state(after, before.factions[0].id)
			b.armies.snap_at_end = false
			if not b.play_turn(before, turn["events"], after):
				continue
			played_any += 1
			battles += Playback.plan(before, turn["events"], after)["battles"].size()
			var guard := 0
			while b.is_playing() and guard < 6000:
				b.armies.step_playback(1.0 / 30.0)
				guard += 1
			assert_false(b.is_playing(), "the playback ends by itself")
			var played_snap: Dictionary = b.armies.snapshot()
			var played_owners: Dictionary = b.wv.owners_painted()
			var played_tents: int = b.armies.tent_count()
			assert_eq(b.armies.ghost_count(), 0, "no ghosts stand after a playback")
			assert_true(b.wv.sweeps.is_empty(), "every capture's sweep is done")
			## a board built straight from the state after
			b.armies.snap_at_end = true
			b.stand(after)
			var label := "seed %d turn %d" % [game_seed, after.current_turn]
			assert_eq(played_snap, b.armies.snapshot(), "%s: every army stands where a board built from the state after puts it" % label)
			assert_eq(played_owners, b.wv.owners_painted(), "%s: the land's owners are the state after's" % label)
			assert_eq(played_tents, b.armies.tent_count(), "%s: the war camps are the state after's" % label)
			assert_eq(before.to_dict(), dict_before, "%s: the state before is untouched by the playback" % label)
			assert_eq(after.to_dict(), dict_after, "%s: the state after is untouched by the playback" % label)
		if b != null:
			_free_board(b)
	assert_true(played_any >= 12, "many turns played out (%d)" % played_any)
	assert_true(battles >= 2, "battles among them (%d)" % battles)


func test_a_game_plays_out_on_the_board_before_the_report_opens() -> void:
	var game := _game_with_board({"players": ["kingdom", "beasts"], "seed": 21, "ai": {"beasts": "normal"}})
	var b: Board3D = game.map.board
	var record_before: Dictionary = game.session.record()
	## march the army somewhere so the turn has something to play
	var st: GameState = game.map.state
	var me := game.map.viewing_faction_id
	for a in st.armies:
		if a.owner == me:
			game.map.queue_move(a.id, st.find_province(a.location).neighbors[0])
			break
	game.end_turn()
	assert_true(b.is_playing(), "the resolved turn plays out on the board")
	assert_false(game.report_overlay.visible, "the turn report waits for the playback")
	b.skip_playback()
	assert_false(b.is_playing())
	assert_true(game.report_overlay.visible, "then the report opens, as on the 2D board")
	assert_eq(game.session.record()["history"].size(), record_before["history"].size() + 1, "one turn resolved, exactly as without the board")
	_check_board_matches(b, game.map.state, "after the playback")
	game.free()


# --- the board only reads the game ------------------------------------------------------------------

func test_the_board_code_never_rolls_dice_or_resolves_turns() -> void:
	for path in BOARD_FILES:
		var text := FileAccess.get_file_as_string(path)
		assert_false(text.is_empty(), "%s can be read" % path)
		for banned in ["RandomNumberGenerator", "SeededRNG", "randf(", "randi(", "randomize(", "TurnResolver.resolve",
				".end_turn(", ".queue_order(", ".acknowledge_handoff("]:
			assert_false(text.contains(banned), "%s never uses %s" % [path, banned])


func test_settings_keep_the_board_and_the_playback_speed() -> void:
	var path := "user://test_board_settings_%d.cfg" % Time.get_ticks_usec()
	var s := GameSettings.load_from(path)
	assert_eq(s.board, "3d", "the 3D board is the default")
	assert_eq(s.playback_speed, 1, "turns play at 1x by default")
	assert_true(s.set_board("2d"))
	assert_true(s.set_playback_speed(4))
	assert_false(s.set_board("isometric"), "only the boards the game has")
	assert_false(s.set_playback_speed(3), "only 1x, 2x and 4x")
	assert_eq(s.save(), "")
	var back := GameSettings.load_from(path)
	assert_eq(back.board, "2d")
	assert_eq(back.playback_speed, 4)
	var panel := SettingsPanel.new()
	panel.open(GameSettings.load_from(path))
	assert_eq(panel.board_picker.selected, GameSettings.BOARDS.find("2d"), "the panel shows the saved board")
	panel.board_picker.item_selected.emit(GameSettings.BOARDS.find("3d"))
	assert_eq(GameSettings.load_from(path).board, "3d", "a change in the panel is saved at once")
	assert_true(panel.board_picker.tooltip_text.contains("2D map"), "the board picker explains itself")
	panel.free()
	DirAccess.remove_absolute(path)
