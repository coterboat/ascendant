extends SceneTree
## CRASH-1 (#249): the live half of tests/test_muster_card.gd's real-input test. Not a test file (no "test_" prefix): the test runs it
## in a child process, because the runner's tests run before the scene tree is live (no layout pass, no mouse event routed). This is a
## real main loop with a whole game screen on the 3D board, in the game a new player gets (every system on, fog too), and every mouse
## event goes in through Input.parse_input_event, as the OS's do: Input, the window, Viewport.push_input, then the hover update that
## crashed Alex's game (signal 11 in Viewport::_drop_mouse_over). After each event it checks the control Godot treats as hovered
## (gui_get_hovered_control) is none or in the tree: Godot 4.5 keeps a control a mouse_exited handler took out of the tree as hovered,
## and reads it on the next mouse event, after it is freed. A failed check ends the run at once, before that next event.
##   * the pointer moves from Split straight onto a line of its forecast, in one event;
##   * a click on Split, the pointer left where it was while the forecast grows, orders the split;
##   * a portrait dragged onto New army orders another; one dragged onto a row moves a fighter;
##   * Merge all, Swap commanders and Send engines (the probe stands a second army with a captain and two engines at the capital, in
##     the session's own board) and Cancel muster, each clicked;
##   * from every muster button, one jump onto every control of the card in view, each checked (the class: no handler the pointer
##     sets off takes away the control it moves onto);
##   * the capital's Recruit and a recruit button and its fort panel, then Storm and Sally, on and off, on the forts tests' besieged
##     keep, from the army's card and from the fort panel.
## It prints one PASS or FAIL line a check and a last line, "MUSTER_PROBE OK" or "MUSTER_PROBE FAILED n". Never touches the
## player's settings or saves (they go to a scratch folder under user://).
## Errors count while the input runs, from the line INPUT_BEGIN to INPUT_END: each engine or script error raised then is a FAIL line,
## and the test counts the ERROR lines printed between the two. Before INPUT_BEGIN the setup has settled (the land baked on the main
## thread, the board built from it, the renderer's queued commands run, frames for the deferred calls and the frees), so nothing the
## setup started is counted as the input's. What the setup or the exit prints is the test's note, not a failure.
##
##   godot --headless --path . --script res://tests/muster_input_probe.gd
##   godot --path . --resolution 1600x900 --always-on-top --script res://tests/muster_input_probe.gd   (windowed, to watch it)

const Kit := preload("res://tests/muster_test_kit.gd")
const FortTest := preload("res://tests/test_fort_panel.gd")
const MAP_SCENE := "res://ui/map_screen.tscn"
const SCRATCH := "user://muster_input_probe"
const SEED := 4242
const HUMAN := "kingdom"
const FOE := "beasts"
## The lines that open and close the input: errors count between them (tests/test_muster_card.gd reads the same two lines).
const INPUT_BEGIN := "MUSTER_PROBE INPUT BEGIN"
const INPUT_END := "MUSTER_PROBE INPUT END"

var game: GameScreen
var screen: MapScreen  # the map screen driven: the game's, then a map screen of a siege
var results := []
var stopped := false
var errors := ErrorLog.new()
var _at := Vector2.ZERO  # where the pointer is (canvas coordinates)
var _pressed_on := ""  # the control under the pointer at the last press (for the checks' words)


## The errors Godot raises while the input runs (count(true) to count(false)), as the runner's own catcher takes them: engine and
## script errors, not warnings. Godot logs from any thread, so behind a mutex.
class ErrorLog extends Logger:
	var _counting := false
	var _during: PackedStringArray = []
	var _outside := 0
	var _mutex := Mutex.new()

	func count(on: bool) -> void:
		_mutex.lock()
		_counting = on
		_mutex.unlock()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool,
			error_type: int, _script_backtrace: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING:
			return
		var text := rationale if not rationale.is_empty() else code
		_mutex.lock()
		if _counting:
			_during.append("%s (%s:%d in %s)" % [text, file, line, function])
		else:
			_outside += 1
		_mutex.unlock()

	## The errors raised while counting.
	func during() -> PackedStringArray:
		_mutex.lock()
		var out := _during.duplicate()
		_mutex.unlock()
		return out

	## How many were raised while not counting (the setup, the exit).
	func outside() -> int:
		_mutex.lock()
		var n := _outside
		_mutex.unlock()
		return n


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(SCRATCH)
	GameSettings.default_path = SCRATCH.path_join("settings.cfg")
	_run()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(ok: bool, what: String) -> void:
	results.append("%s %s" % ["PASS" if ok else "FAIL", what])
	print(results.back())


## The hovered control right after an event was handled, before anything queued for deletion is freed (Godot frees it at the end of the
## next physics step, before the next process_frame: checked later, a freed control reads as none). A control out of the tree here is
## the crash's state; the pointer then moves off the card at once, while that control is still alive, so Godot lets go of it and the
## run ends with its FAIL line instead of crashing on the next event.
func _hover_ok(what: String) -> bool:
	var h := root.gui_get_hovered_control()
	if h == null or h.is_inside_tree():
		return true
	_check(false, "%s: Godot's hovered control %s is out of the tree (it would be read freed on the next mouse event)" % [what, h.name])
	stopped = true
	var off := InputEventMouseMotion.new()
	off.position = Vector2(root.size) - Vector2(4, 4)
	off.global_position = off.position
	Input.parse_input_event(off)
	Input.flush_buffered_events()
	return false


## One mouse event through Input, as the OS sends them (Input, the window, Viewport.push_input), handled at once
## (Input.flush_buffered_events, the call the OS's event loop makes), checked, then a frame. False when the hover check failed.
func _send(e: InputEventMouse, what: String) -> bool:
	if stopped:
		return false
	var w: Vector2 = root.get_final_transform() * _at
	e.position = w
	e.global_position = w
	Input.parse_input_event(e)
	Input.flush_buffered_events()
	var ok := _hover_ok(what)
	await process_frame
	return ok


func _move(to: Vector2, what: String, held: bool = false) -> bool:
	var m := InputEventMouseMotion.new()
	var from: Vector2 = root.get_final_transform() * _at
	_at = to
	m.relative = root.get_final_transform() * to - from
	m.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	return await _send(m, what)


func _button(down: bool, what: String) -> bool:
	var b := InputEventMouseButton.new()
	b.button_index = MOUSE_BUTTON_LEFT
	b.pressed = down
	b.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	return await _send(b, what)


## A click where the pointer is: press, release, and a few frames for what it ordered to show.
func _click_here(what: String) -> bool:
	if not await _button(true, what + " (press)"):
		return false
	var h := root.gui_get_hovered_control()
	_pressed_on = String(h.name) if h != null else "nothing"
	if not await _button(false, what + " (release)"):
		return false
	await _frames(3)
	return true


func _click(c: Control, what: String) -> bool:
	if c == null or stopped:
		_check(false, "%s: it is on the card" % what)
		return false
	await _into_view(c)
	if not await _move(_centre(c), what + " (onto it)"):
		return false
	await _frames(2)
	return await _click_here(what)


## A drag from `from` to `to`, as a hand does it: press, a small move with the button held (Godot starts the drag past 10 px), then
## over the target, and the release there. Returns the forecast's lines while over the target (null when a check failed).
func _drag(from: Control, to: Control, what: String) -> Variant:
	if from == null or to == null or stopped:
		_check(false, "%s: both ends are on the card" % what)
		return null
	if not await _move(_centre(from), what + " (onto the portrait)"):
		return null
	await _frames(2)
	if not await _button(true, what + " (press)"):
		return null
	if not await _move(_centre(from) + Vector2(0, 14), what + " (the drag starts)", true):
		return null
	_check(root.gui_is_dragging(), "%s: the drag started" % what)
	if not await _move(_centre(to), what + " (over the target)", true):
		return null
	await _frames(2)
	var seen := _forecast(_board()).map(func(l): return String(l.text))
	if not await _button(false, what + " (the drop)"):
		return null
	await _frames(3)
	return seen


func _centre(c: Control) -> Vector2:
	return c.get_global_rect().get_center()


## Scrolls the card so `c` shows near the top of its view (the card is taller than the screen at 1600x900, and the "More" cue covers
## the bottom of the view while more of the card is below).
func _into_view(c: Control) -> void:
	var sc := screen.cards.scroll
	if sc.is_ancestor_of(c):
		sc.scroll_vertical += int(c.global_position.y - sc.global_position.y) - 40
	await _frames(3)


## The card's scroll shows `top` at the top of its view, so what follows it (New army, the rows) is in view together.
func _scroll_to_top(top: Control) -> void:
	var sc := screen.cards.scroll
	sc.scroll_vertical += int(top.global_position.y - sc.global_position.y) - 4
	await _frames(3)


func _board() -> MusterBoard:
	var found := screen.details.find_children("ArmiesHere", "", true, false)
	return found[0] as MusterBoard if not found.is_empty() else null


func _card() -> ArmyCard:
	var holder := screen.cards.holder
	return holder.get_child(0) as ArmyCard if holder.get_child_count() > 0 else null


func _forecast(b: MusterBoard) -> Array:
	return b.forecast_lines.get_children().filter(func(c): return c is Label and (c as Label).is_visible_in_tree()) if b != null else []


func _orders() -> Array:
	return screen.orders.orders()


## The windowed run: the real cursor must not sit over the window, or Godot's own motion at the real cursor (after a drop, or when a
## control's cursor shape changes) moves the hover under the probe.
func _keep_off_the_cursor() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var cur := DisplayServer.mouse_get_position()
	var area := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var size := DisplayServer.window_get_size()
	var pos := DisplayServer.window_get_position()
	if not Rect2i(pos, size).grow(20).has_point(cur):
		return
	for t in [Vector2i(pos.x, cur.y + 40), Vector2i(pos.x, cur.y - size.y - 40), Vector2i(cur.x + 40, pos.y), Vector2i(cur.x - size.x - 40, pos.y)]:
		if area.encloses(Rect2i(t, size)):
			DisplayServer.window_set_position(t)
			return


## Lets what the setup started finish before errors count: the board built from the baked land, the renderer's queued commands run
## (RenderingServer.force_sync), and frames, each of which flushes the deferred calls (the message queue) and frees what was queued.
func _settle() -> void:
	await _frames(8)
	RenderingServer.force_sync()
	await _frames(4)


func _run() -> void:
	await process_frame
	_keep_off_the_cursor()
	OS.add_logger(errors)
	# The land bakes here, on the main thread, before the game's board would bake it on a worker (Board3D.prebake). Headless, a
	# worker's bake races the dummy renderer, whose mesh RIDs are not thread safe (mesh_create() takes the RID on the calling thread,
	# and the dummy's RID_Owner has no lock; the GL renderer's has): on a loaded machine that printed `Parameter "m" is null.` (the
	# dummy mesh storage) and `Condition "!F" is true.` (the renderer's dependency tracker) while the land baked, before any input. A
	# bake already under way (a windowed run's autoload starts one) is waited for with frames: it asks the renderer, which answers
	# between frames.
	while Board3D._task >= 0 and not WorkerThreadPool.is_task_completed(Board3D._task):
		await process_frame
	Board3D.terrain_now()
	var gs := GameSettings.new(SCRATCH.path_join("settings.cfg"))
	gs.set_board("3d")
	gs.save()
	game = load("res://ui/game_screen.tscn").instantiate()
	game.autosave_enabled = false
	game.save_store = SaveStore.new(SCRATCH.path_join("saves"))
	game.start_game({"players": [HUMAN, FOE], "seed": SEED, "rulers": true, "paths": true, "sieges": true, "fog": true, "magic": true,
		"independents": true, "ai": {FOE: "normal"},
		"builds": {HUMAN: RulerRules.preset_build(RulerRules.balanced_preset(HUMAN)), FOE: BuildScreen.computer_build(FOE, SEED, 1)}})
	root.size = Vector2i(1600, 900)
	root.add_child(game)
	await process_frame
	screen = game.map
	var board3d: Board3D = game.map.board
	var t0 := Time.get_ticks_msec()
	while not board3d.prepared and float(Time.get_ticks_msec() - t0) / 1000.0 < 120.0:
		await create_timer(0.1).timeout
	await _settle()
	print(INPUT_BEGIN)
	errors.count(true)
	await _muster()
	await _sweep()
	await _recruit_and_fort()
	await _fort_in_a_siege()
	errors.count(false)
	print(INPUT_END)
	for e in errors.during():
		_check(false, "no error while the input ran, but: %s" % e)
	if errors.outside() > 0:
		print("MUSTER_PROBE note: %d errors before the input (the setup), not counted" % errors.outside())
	var failed := results.filter(func(r): return String(r).begins_with("FAIL"))
	print("MUSTER_PROBE ", "OK" if failed.is_empty() and not stopped else "FAILED %d" % failed.size())
	if is_instance_valid(game):
		game.queue_free()
	await process_frame
	OS.remove_logger(errors)
	quit()


# --- Armies here ---------------------------------------------------------------------------------------------------

## A muster button clicked: ordered when the rules allow it, otherwise disabled with the order book's reason (its tooltip).
func _press_button(kind: String) -> bool:
	var b := _board()
	var button: Button = {"split": b.split_button, "merge": b.merge_button, "swap": b.swap_button, "engines": b.engines_button}[kind]
	if button == null:
		_check(false, "the %s button is on the card" % kind)
		return false
	var refused := button.disabled
	var why := button.tooltip_text.get_slice("\n\n", 1).replace("\n", " ").left(120)
	var before := _orders().size()
	if not await _click(button, "a click on %s" % button.text):
		return false
	if refused:
		_check(_orders().size() == before, "%s is refused, with its reason: %s" % [kind, why])
	else:
		_check(_orders().size() == before + 1 and _orders().back() is MusterOrder, "the click orders the %s (%d orders)" % [kind, _orders().size()])
	return true


## The forecast while a drag was over its target: what it would do, or the rules' reason it can't be done.
func _dropped(seen: Variant, before: int, what: String) -> void:
	var lines: Array = seen if seen is Array else []
	var refused: bool = lines.size() == 1 and String(lines[0]) != MusterBoard.HINT and not String(lines[0]).begins_with("If you order this")
	if refused:
		_check(_orders().size() == before, "%s is refused, and the forecast said why: %s" % [what, lines[0]])
	else:
		_check(_orders().size() == before + 1, "%s is ordered (%d orders); the forecast showed %s" % [what, _orders().size(), lines.slice(0, 2)])


func _muster() -> void:
	var map := screen
	var capital := String(map.state.find_faction(HUMAN).capital)
	var mine: Array = map.state.armies.filter(func(a): return a.owner == HUMAN and a.ruler == null and a.location == capital and a.units.size() >= 2)
	_check(not mine.is_empty(), "an army of yours with fighters to split stands at the capital")
	if mine.is_empty():
		return
	var army_id := String(mine[0].id)
	# A second army with a captain and two engines beside it, so Swap commanders and Send engines have something to do: the default game
	# has none on turn 1. The probe puts it in the session's own board (its _state, and the fog views built from it: there is no public
	# way in) and shows the map again, so the orders the card gives are checked against it as any other. The probe never ends the turn.
	var extra := Kit.army(game.session._state, HUMAN, capital, ["spearmen", "spearmen"], "captain", 2)
	game.session._fog_cache.clear()
	game._set_map_for(HUMAN)
	map.select_army(army_id)
	await _frames(6)
	var b := _board()
	_check(b != null and b.rows.has(extra.id), "Armies here is on %s's card, with a row for %s" % [army_id, extra.id])
	if b == null or not b.rows.has(extra.id):
		return
	# The pointer onto Split: its forecast shows.
	await _into_view(b.split_button)
	if not await _move(_centre(b.split_button), "onto Split"):
		return
	await _frames(2)
	_check(root.gui_get_hovered_control() == b.split_button, "the pointer is over Split")
	var lines := _forecast(b)
	_check(lines.any(func(l): return String(l.text).contains("If you order this")), "hovering Split shows its forecast: %s" % [lines.map(func(l): return l.text)])
	# The crash's path: one event from Split straight onto a line of its forecast. Split's mouse_exited clears the forecast; were the line
	# freed inside that handler, Godot would keep it as the hovered control.
	if lines.is_empty():
		return
	var line: Label = lines.back()
	if not await _move(_centre(line), "from Split straight onto the forecast line '%s'" % line.text.left(40)):
		return
	await _frames(2)
	_check(true, "a jump from Split onto its forecast leaves a hovered control that is in the tree")
	# A click on Split with the pointer left where it was: the forecast grows when Split is hovered, and Split must stay under the pointer.
	var before := _orders().size()
	b = _board()
	await _into_view(b.split_button)
	if not await _move(_centre(b.split_button), "back onto Split"):
		return
	await _frames(3)
	_check(b.split_button.get_global_rect().has_point(_at), "Split is still under the pointer once its forecast has grown: %s, the pointer at %s" % [
		b.split_button.get_global_rect(), _at])
	if not await _click_here("a click on Split"):
		return
	_check(_orders().size() == before + 1 and _orders().back() is MusterOrder and String(_orders().back().to_army).is_empty(),
		"the click orders the split (%d orders)" % _orders().size())
	# A portrait of this army dragged onto New army: from the card's own portraits when New army is in view with them, else from a row.
	b = _board()
	var chips: Array = _card().strip.chips()
	await _into_view(chips.back())
	var from: Control = chips.back()
	var view := screen.cards.scroll.get_global_rect()
	if not view.has_point(_centre(b.new_zone)):
		await _scroll_to_top(b.new_zone)
		from = b.rows[extra.id].strip.chips().back()
	before = _orders().size()
	var seen = await _drag(from, b.new_zone, "a portrait dragged onto New army")
	if seen == null:
		return
	_dropped(seen, before, "the drop on New army")
	# A portrait dragged onto a row: one of this army's onto the captain's army's row.
	b = _board()
	var row: MusterBoard.Row = b.rows[extra.id]
	await _scroll_to_top(b.new_zone)
	from = _card().strip.chips().back()
	if not screen.cards.scroll.get_global_rect().has_point(_centre(from)):
		var others: Array = b.rows.values().filter(func(r): return r != row and not r.greyed and r.strip != null and not r.strip.chips().is_empty())
		from = others.front().strip.chips().back() if not others.is_empty() else null
	before = _orders().size()
	seen = await _drag(from, row, "a portrait dragged onto %s's row" % extra.id)
	if seen == null:
		return
	_dropped(seen, before, "the drop on %s's row" % extra.id)
	# The captain's army as the partner (its Partner tick), then Swap commanders.
	b = _board()
	row = b.rows.get(extra.id)
	if row == null or row.partner_check == null:
		_check(false, "the captain's army has its row and its Partner tick")
		return
	if not row.partner_check.button_pressed:
		if not await _click(row.partner_check, "a click on the captain's army's Partner tick"):
			return
	_check(_board().partner_id == extra.id, "the captain's army is the partner")
	if not await _press_button("swap"):
		return
	# Send engines, from the captain's army's own card (its row's name selects it): one engine on the stepper, then the button.
	b = _board()
	row = b.rows.get(extra.id)
	if not await _click(row.name_button if row != null else null, "a click on the captain's army's name"):
		return
	b = _board()
	_check(b != null and b.army_id == extra.id and b.engines_button != null, "the captain's army's card has the engines stepper and Send engines")
	if b == null or b.engines_button == null:
		return
	if not await _click(b.engines_row.find_child("EnginesMore", true, false), "a click on the engines stepper's +"):
		return
	_check(_board().engines_going == 1, "the stepper sends one engine (the press was on %s)" % _pressed_on)
	if not await _press_button("engines"):
		return
	# Merge all, back on the first army's card.
	map.select_army(army_id)
	await _frames(4)
	if not await _press_button("merge"):
		return
	# Cancel muster, on each army's card, until no muster is left.
	var cancels := 0
	for id in [army_id, extra.id]:
		map.select_army(id)
		await _frames(4)
		while cancels < 12 and not stopped:
			var cancel: Button = screen.cards.pinned.find_child("CancelButton", true, false)
			if cancel == null or not cancel.text.contains("muster"):
				break
			before = _orders().size()
			if not await _click(cancel, "a click on Cancel muster"):
				return
			_check(_orders().size() < before, "Cancel muster withdraws it (%d orders left)" % _orders().size())
			cancels += 1
	_check(cancels >= 1, "Cancel muster was on the cards (%d clicks)" % cancels)
	_check(_orders().filter(func(o): return o is MusterOrder).is_empty(), "no muster is left")


# --- the class: from every muster button, one jump onto every control of the card --------------------------------------------------------

func _sweep() -> void:
	if stopped:
		return
	var b := _board()
	if b == null:
		return
	var jumps := 0
	for kind in ["split", "merge", "swap", "engines"]:
		b = _board()
		var button: Button = {"split": b.split_button, "merge": b.merge_button, "swap": b.swap_button, "engines": b.engines_button}[kind]
		if button == null:
			continue
		await _into_view(button)
		var at := _centre(button)
		if not await _move(at, "onto %s" % button.name):
			return
		await _frames(2)
		for p in _points():
			if not await _move(at, "back onto %s" % button.name):
				return
			await _frames(1)
			if not await _move(p, "from %s straight onto %s" % [button.name, p]):
				return
			jumps += 1
	_check(jumps > 0, "%d jumps from the muster buttons straight onto every control of the card in view: each left a hovered control in the tree" % jumps)


## The centre of every control of the card the pointer can land on, in view: the jump targets of the sweep.
func _points() -> Array:
	var out := []
	var seen := {}
	var view := Rect2(Vector2.ZERO, Vector2(root.size))
	for n in screen.cards.find_children("*", "Control", true, false):
		var c := n as Control
		if c.mouse_filter == Control.MOUSE_FILTER_IGNORE or not c.is_visible_in_tree():
			continue
		var p := _centre(c).round()
		if not view.has_point(p) or seen.has(p):
			continue
		seen[p] = true
		out.append(p)
	return out


# --- Recruit and the fort panel ---------------------------------------------------------------------------------------------------------

func _recruit_and_fort() -> void:
	if stopped:
		return
	var capital := String(screen.state.find_faction(HUMAN).capital)
	screen.select_province(capital)
	await _frames(6)
	var cards := screen.cards
	var before := _orders().size()
	if not await _click(cards.pinned.find_child("RecruitButton", true, false), "a click on Recruit"):
		return
	_check(cards.section_open("recruit"), "Recruit opens its section")
	var buy: Button = cards.details.find_child("Recruit_*", true, false)
	if not await _click(buy, "a click on a recruit button"):
		return
	_check(_orders().size() == before + 1, "the recruit is ordered (%d orders)" % _orders().size())
	await _fort_panel(capital)


## The fort panel's buttons show in a siege, and turn 1 of a real game has none: a map screen of the forts tests' besieged keep
## (Stonegate: the Clans outside, the Crown inside, the siege recorded), as the Clans (Storm) and as the Crown (Sally). The army's
## siege action opens the panel under its card; the province's card has the whole panel.
func _fort_in_a_siege() -> void:
	if stopped:
		return
	game.queue_free()
	await _frames(2)
	var s := FortTest.besieged_keep()
	var keep := "stonegate"
	for viewer in [FOE, HUMAN]:
		screen = load(MAP_SCENE).instantiate()
		screen.set_state(s, viewer)
		root.add_child(screen)
		await _frames(6)
		var army: Army = s.armies.filter(func(a): return a.location == keep and a.owner == viewer and a.ruler == null).front()
		screen.select_army(army.id)
		await _frames(4)
		var action: Button = screen.cards.pinned.find_child("SiegeButton", true, false)
		if not await _click(action, "a click on %s's siege action (%s)" % [army.id, action.text if action != null else "none"]):
			return
		_check(screen.cards.section_open("siege"), "%s's siege action opens the fort panel under its card" % army.id)
		await _panel_buttons(screen.cards.details.find_child("SiegeFrame", true, false), "%s's card" % army.id)
		await _fort_panel(keep)
		root.remove_child(screen)
		screen.queue_free()
		await _frames(2)


## The card of `pid` with its fort panel open, every button of the panel clicked on and off again, and the panel closed.
func _fort_panel(pid: String) -> void:
	if stopped:
		return
	var cards := screen.cards
	screen.select_province(pid)
	await _frames(6)
	if not await _click(cards.pinned.find_child("FortPanelButton", true, false), "a click on %s's Fort panel" % pid):
		return
	_check(cards.section_open("fort"), "%s's fort panel opens" % pid)
	await _panel_buttons(cards.details.find_child("FortFrame", true, false), "%s's fort panel" % pid)
	if not await _click(cards.pinned.find_child("FortPanelButton", true, false), "a click on %s's Fort panel again" % pid):
		return
	_check(not cards.section_open("fort"), "%s's fort panel closes" % pid)


## Every button under `panel`, clicked on and then off again: each gives its order and takes it back, or is refused with its reason.
func _panel_buttons(panel: Node, where: String) -> void:
	if panel == null or stopped:
		return
	var names := []
	for x in panel.find_children("*", "BaseButton", true, false):
		if (x as Control).is_visible_in_tree():
			names.append(String(x.name))
	_check(true, "%s: %d buttons %s" % [where, names.size(), names])
	for button_name in names:
		for turn_on in [true, false]:
			var x: BaseButton = screen.cards.find_child(button_name, true, false)
			if x == null:
				_check(false, "%s is still on %s" % [button_name, where])
				return
			var refused := x.disabled
			var before := _orders().size()
			if not await _click(x, "a click on %s in %s" % [button_name, where]):
				return
			if refused:
				_check(_orders().size() == before, "%s in %s is refused, with its reason: %s" % [button_name, where, x.tooltip_text.left(100).replace("\n", " ")])
				break
			_check(_orders().size() != before, "%s in %s %s (%d orders)" % [button_name, where, "orders it" if turn_on else "takes it back", _orders().size()])
