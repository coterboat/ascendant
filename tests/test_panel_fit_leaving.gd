extends "res://tests/test_case.gd"
## #330 (QA): after leaving a game, every window resize or interface-size change logged three errors for each panel PanelFit had fitted
## in it ("Lambda capture at index 0 was freed", "... index 1 ...", "Cannot call method 'is_inside_tree' on a null value" at
## panel_fit.gd:40), and more with every game left. PanelFit.attach hooked its fit to the window's size_changed when the panel entered
## the tree and never unhooked it, so the window kept calling it after the panel was freed. The runner's tests run before the scene
## tree is live, so no panel enters the tree in them: tests/panel_fit_probe.gd is a real (headless) main loop in a child Godot process
## that plays a game, leaves it with Quit to title, Continues and leaves again, resizing as it goes. One probe run serves the file.

const PROBE := "res://tests/panel_fit_probe.gd"
const SCRATCH := "user://panel_fit_probe"

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
		if line.begins_with("PANEL_FIT_REPORT "):
			parsed = JSON.parse_string(line.trim_prefix("PANEL_FIT_REPORT "))
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


func test_leaving_a_game_unhooks_its_fitted_panels_from_the_window() -> void:
	var report := _probe()
	var base := int(report.get("base", -1))
	var fits_up: Array = report.get("fits_in_game", [])
	var fits_left: Array = report.get("fits_after_leaving", [])
	var after: Array = report.get("after_leaving", [])
	var left_hooked: Array = report.get("left_hooked", [])
	assert_eq(after.size(), 2, "the probe played and left two games")
	for i in fits_up.size():
		assert_true(int(fits_up[i]) > 0, "while game %d is up, its fitted panels follow the window (%d fits hooked)" % [i + 1, int(fits_up[i])])
	if fits_up.size() == 2:
		assert_eq(int(fits_up[1]), int(fits_up[0]), "the same panels in both games, the same fits")
	for i in after.size():
		assert_eq(int(fits_left[i]) if i < fits_left.size() else -1, 0, "after leaving game %d, none of its fits is still hooked" % (i + 1))
		assert_eq(int(after[i]), base, "and the window has only the title's hookups (left hooked: %s)" % [
			left_hooked[i] if i < left_hooked.size() else "?"])
	if after.size() == 2:
		assert_eq(int(after[1]), int(after[0]), "their count doesn't grow with each game left")


func test_resizing_after_leaving_games_logs_no_error() -> void:
	var report := _probe()
	var after_leaving: Array = report.get("resize_errors", ["(no report)"])
	var in_games: Array = report.get("in_game_errors", ["(no report)"])
	assert_eq(after_leaving.size(), 0, "the interface size and a window resize on the title, after two games: no error (%s)" % [
		after_leaving.slice(0, 3)])
	assert_eq(in_games.size(), 0, "nor while a game is up, the second after the first was left (%s)" % [in_games.slice(0, 3)])
	var other: Array = report.get("other_errors", [])
	if not other.is_empty():
		_notes.append("the probe logged %d errors outside the resizes (starting, leaving, Continue), not counted: %s" % [
			other.size(), other.slice(0, 3)])
