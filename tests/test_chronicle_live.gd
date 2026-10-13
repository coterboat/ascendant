extends "res://tests/test_case.gd"
## UX-6 (#214): the Chronicle in the LIVE path. The headless runner's tests run before the scene tree is live, so no Control ever gets a
## layout pass and no mouse event is routed; tests/chronicle_probe.gd is a real (headless) main loop in a child Godot process that pushes
## real mouse and key events through the viewport at a medallion, a card, a button, and reports what the running game did. One probe run
## serves the whole file. Pinned:
##   - a real turn's report lights the Chronicle (medallions, the unread badge) and, with the player's setting on "never", nothing opens;
##   - the viewport hovers a medallion; a LEFT-click opens the Chronicle at its card; a click on Pin keeps it in the sidecar store (and the
##     game's record is untouched); a click on the place chip focuses the board; a RIGHT-click on the medallion dismisses it with its card
##     and marker; Restore brings it back; Esc closes the Chronicle; the Chronicle button opens it and its close button shuts it; Hide folds
##     the stack and Notices brings it back;
##   - all of that on the 3D board and the 2D map at each size the spec supports, and nothing of the game changed under the mouse.

const PROBE := "res://tests/chronicle_probe.gd"
const SCRATCH := "user://chronicle_probe"
const SIZES := ["1600x900", "1600x900@125", "1280x720"]

static var _report := {}


func _probe() -> Dictionary:
	if not _report.is_empty():
		return _report
	var cmd := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", PROBE]
	var output := []
	var code := OS.execute(OS.get_executable_path(), cmd, output, true)
	_remove_tree(SCRATCH)
	var text := "\n".join(output)
	var parsed = {}
	for line in text.split("\n"):
		if line.begins_with("CHRONICLE_REPORT "):
			parsed = JSON.parse_string(line.trim_prefix("CHRONICLE_REPORT "))
	assert_true(parsed is Dictionary and not parsed.is_empty(), "the probe reported (exit code %d): %s" % [code, text.right(1200)])
	_report = parsed if parsed is Dictionary else {}
	return _report


static func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for sub in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(sub))
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)


## Every drive the probe made: the real turn's, then each board at each size.
func _drives() -> Array:
	var report := _probe()
	var out := []
	assert_true(report.has("real"), "the probe drove a real turn")
	out.append(report.get("real", {}).get("drive", {}))
	for board in ["3d", "2d"]:
		assert_true(report.has(board), "the probe drove the %s board" % board)
		for key in SIZES:
			assert_true(report.get(board, {}).has(key), "%s board at %s was driven" % [board, key])
			out.append(report.get(board, {}).get(key, {}))
	return out


func test_a_real_turn_lights_the_chronicle_and_the_setting_decides_it_stays_shut() -> void:
	var real: Dictionary = _probe().get("real", {})
	assert_eq(int(real.get("turns_played", 0)), 1, "turn 1 resolved")
	assert_eq(int(real.get("ready", 0)), 1, "and its report was ready")
	assert_true(int(real.get("announcements", 0)) > 0, "the Chronicle has the turn's announcements (%s)" % [real.get("announcements")])
	assert_true(int(real.get("notable", 0)) > 0, "some of them are notable, so there are medallions (%s)" % [real.get("notable")])
	assert_false(bool(real.get("modal_open", true)), "today's modal did not open on its own")
	assert_false(bool(real.get("auto_opened", true)), "and with the player's setting on 'never' neither did the column")
	assert_true(int(real.get("badge", 0)) > 0, "the Chronicle button counts the unread (%s)" % [real.get("badge")])


func test_real_mouse_events_open_pin_and_dismiss_a_medallion_on_the_real_turn() -> void:
	var d: Dictionary = _probe().get("real", {}).get("drive", {})
	_check_drive(d, "the real turn")


func test_real_mouse_events_work_on_both_boards_at_every_size() -> void:
	var n := 0
	for d in _drives():
		_check_drive(d, String(d.get("tag", "?")))
		n += 1
	assert_eq(n, 7, "the real turn and six board-and-size drives")


func _check_drive(d: Dictionary, where: String) -> void:
	assert_false(d.has("error"), "%s: the probe ran (%s)" % [where, d.get("error", "")])
	assert_true(int(d.get("medallions", 0)) >= 1, "%s: medallions are drawn" % where)
	assert_true(bool(d.get("hover_is_medallion", false)), "%s: the viewport hovers the medallion the mouse is over" % where)
	assert_true(bool(d.get("opened", false)), "%s: a left-click opens the Chronicle" % where)
	assert_true(bool(d.get("opened_at", false)), "%s: at that medallion's own card" % where)
	assert_true(bool(d.get("column_shown", false)), "%s: the column is on screen" % where)
	assert_true(bool(d.get("safe_narrowed", false)), "%s: and the Table's safe area made room for it" % where)
	assert_true(bool(d.get("card_present", false)), "%s: its card is in the list" % where)
	assert_eq(int(d.get("unread_after_open", -1)), 0, "%s: nothing is unread once it is open" % where)
	assert_true(int(d.get("cards_shown", 0)) >= 1, "%s: the column lists cards" % where)
	assert_true(float(d.get("detail_height_min", 0.0)) >= 14.0, "%s: every card's detail line is laid out with a height (%s px): it can be read" % [where, d.get("detail_height_min")])
	assert_true(float(d.get("card_height_max", 9999.0)) < 400.0, "%s: no card is taller than a screenful" % where)
	assert_true(bool(d.get("pinned", false)), "%s: a click on Pin keeps the card in the store" % where)
	assert_true(bool(d.get("pin_file", false)), "%s: in a sidecar file" % where)
	assert_true(bool(d.get("record_same_after_pin", false)), "%s: and the game's record did not change" % where)
	assert_true(bool(d.get("has_place", false)), "%s: the card driven has a place chip" % where)
	if d.has("focused"):
		assert_true(bool(d.get("focused")), "%s: the place chip focuses the board on its province" % where)
		assert_true(bool(d.get("still_open_after_focus", false)), "%s: and the Chronicle stays open" % where)
	assert_true(bool(d.get("dismissed", false)), "%s: a right-click on the medallion dismisses it" % where)
	assert_true(bool(d.get("card_gone", false)) and bool(d.get("medallion_gone", false)), "%s: with its card and its medallion" % where)
	assert_true(bool(d.get("unpinned_with_it", false)), "%s: a dismissed card is not kept pinned" % where)
	assert_true(bool(d.get("restored", false)), "%s: Restore brings it back" % where)
	assert_true(bool(d.get("esc_closed", false)), "%s: Esc closes the Chronicle" % where)
	assert_true(bool(d.get("safe_open_again", false)), "%s: and the safe area opens again" % where)
	assert_true(bool(d.get("button_opened", false)), "%s: the Chronicle button opens it" % where)
	assert_true(bool(d.get("close_button_closed", false)), "%s: and its close button shuts it" % where)
	assert_true(bool(d.get("folded", false)), "%s: Hide folds the stack away" % where)
	assert_true(bool(d.get("unfolded", false)), "%s: and Notices brings it back" % where)
	assert_true(bool(d.get("record_same", false)), "%s: nothing of the game's record changed under the mouse" % where)
	assert_true(bool(d.get("turns_same", false)), "%s: no turn was ended" % where)
	assert_true(bool(d.get("orders_same", false)), "%s: no order was given or lost" % where)
