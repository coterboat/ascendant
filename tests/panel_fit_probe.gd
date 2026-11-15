extends SceneTree
## The live half of tests/test_panel_fit_leaving.gd (#330). Not a test file (no "test_" prefix): the test runs it in a child Godot
## process, because the runner's tests run before the scene tree is live, so no panel there ever enters the tree and PanelFit never
## hooks the window. This script runs a real (headless) main loop through the issue's steps: from the title it starts a game, opens
## every panel PanelFit fits (the research panel and its lock-in preview, the Rulers panel and the sacrifice dialog; the turn report's
## box is built with the screen), changes the interface size, and leaves with Menu > Quit to title; then Continue, the same again;
## then, on the title, the interface size and a window resize once more. It prints one line,
##
##   PANEL_FIT_REPORT {"base": n, "in_game": [n, n], "after_leaving": [n, n], "fits_in_game": [n, n], "fits_after_leaving": [n, n],
##                     "left_hooked": [[...], [...]], "in_game_errors": [...], "resize_errors": [...], "other_errors": [...]}
##
## base, in_game and after_leaving count the window's size_changed hookups on the first title, while each game is up, and on the title
## after leaving each game; fits_* count PanelFit's own among them (the fits panel_fit.gd hooked); left_hooked describes the hookups
## after leaving that the first title did not have. in_game_errors and resize_errors are what Godot logged while the resizes ran in the
## games and on the title at the end (engine and script errors, not warnings); other_errors, what it logged the rest of the time.
## It never touches the player's settings or saves: both go to a scratch folder under user://, which the test removes.
##
##   godot --headless --path . --script res://tests/panel_fit_probe.gd

const SCRATCH := "user://panel_fit_probe"
const REPORT := "PANEL_FIT_REPORT "
const PANEL_FIT := "res://ui/panel_fit.gd"
## You (the Crown) against the computer, every system on, a fixed seed: Quick start's game without its random draw.
const PLAYERS := ["kingdom", "beasts"]
const SEED := 21
const RESEARCH_NODE := "crown_oath_forge"  # a Crown research node, for the lock-in preview


## The errors Godot logs (engine and script errors, not warnings), kept apart while count(true) is on. Godot logs from any thread, so
## behind a mutex.
class ErrorLog extends Logger:
	var _counting := false
	var _during: PackedStringArray = []
	var _outside: PackedStringArray = []
	var _mutex := Mutex.new()

	func count(on: bool) -> void:
		_mutex.lock()
		_counting = on
		_mutex.unlock()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool,
			error_type: int, _script_backtrace: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING:
			return
		var text := "%s (%s:%d in %s)" % [rationale if not rationale.is_empty() else code, file, line, function]
		_mutex.lock()
		if _counting:
			_during.append(text)
		else:
			_outside.append(text)
		_mutex.unlock()

	## The errors logged while counting, since the last call.
	func take() -> PackedStringArray:
		_mutex.lock()
		var out := _during
		_during = PackedStringArray()
		_mutex.unlock()
		return out

	## The errors logged while not counting.
	func outside() -> PackedStringArray:
		_mutex.lock()
		var out := _outside.duplicate()
		_mutex.unlock()
		return out


var errors := ErrorLog.new()
var settings: GameSettings
var report := {"in_game": [], "after_leaving": [], "fits_in_game": [], "fits_after_leaving": [], "left_hooked": [],
	"in_game_errors": [], "resize_errors": []}


func _initialize() -> void:
	OS.add_logger(errors)
	DirAccess.make_dir_recursive_absolute(SCRATCH)
	GameSettings.default_path = SCRATCH.path_join("settings.cfg")
	SaveStore.default_root = SCRATCH.path_join("saves")
	settings = GameSettings.load_from()
	settings.set_board("2d")  # the quicker board to build; the panels are the same on both
	settings.set_ui_scale(100)
	settings.save()
	_run()


func _run() -> void:
	await process_frame
	var title := SceneFlow.make_title()
	root.add_child(title)
	current_scene = title
	await _frames(3)
	var base := _hookups()
	report["base"] = base.size()
	for n in 2:
		var on_title := current_scene as TitleScreen
		var game: GameScreen = on_title.start_game(_config()) if n == 0 else on_title.continue_game()  # Quick start's game, then Continue
		if game == null:
			print("PANEL_FIT_PROBE could not start game %d" % (n + 1))
			break
		await _frames(3)
		_open_every_fitted_panel(game)
		await _frames(3)
		var up := _hookups()
		report["in_game"].append(up.size())
		report["fits_in_game"].append(_fits(up))
		report["in_game_errors"].append_array(await _resize())
		_quit_to_title(game)
		await _frames(3)  # the game screen is freed at the end of the frame it is left in
		var now := _hookups()
		report["after_leaving"].append(now.size())
		report["fits_after_leaving"].append(_fits(now))
		report["left_hooked"].append(_extra(now, base))
	report["resize_errors"] = await _resize()
	report["other_errors"] = Array(errors.outside())
	OS.remove_logger(errors)
	print(REPORT + JSON.stringify(report))
	quit()


func _config() -> Dictionary:
	var config := {"players": PLAYERS, "seed": SEED, "ai": {"beasts": NewGameScreen.DEFAULT_LEVEL}}
	config.merge(NewGameScreen.default_systems())
	return config


## Every panel PanelFit fits on a game screen, opened once (each is built on its first open and kept until the screen is freed).
func _open_every_fitted_panel(game: GameScreen) -> void:
	game.research_hud.open_panel()
	game.research_hud.open_preview(RESEARCH_NODE)
	game.open_ruler_panel()
	game.map.open_sacrifice_dialog()


## Menu > Quit to title, and Quit to title on the confirmation.
func _quit_to_title(game: GameScreen) -> void:
	game.map.close_ruler_panel()
	game._on_quit_requested()
	var confirm := game.find_child("ConfirmQuitButton", true, false) as Button
	if confirm != null and confirm.is_visible_in_tree():
		confirm.pressed.emit()
	else:
		game._go_to_title()  # a game that is over leaves without the confirmation


## Settings' interface size to 125% and back (GameSettings.apply sets the window's content scale), then a window resize (the
## window's size_changed, as a drag sends it): the errors Godot logged while they ran.
func _resize() -> Array:
	errors.take()
	errors.count(true)
	for percent in [125, 100]:
		settings.set_ui_scale(percent)
		settings.apply(self)
		await _frames(2)
	root.size_changed.emit()
	await _frames(2)
	errors.count(false)
	return Array(errors.take())


## The window's size_changed hookups, each as "<object> <method>" (a lambda's object is the script that made it).
func _hookups() -> Array:
	var out := []
	for c in root.size_changed.get_connections():
		var callable: Callable = c.callable
		var target = callable.get_object()
		var who := "null"
		if target is Script:
			who = (target as Script).resource_path
		elif target != null:
			who = target.get_class()
		out.append("%s %s" % [who, callable.get_method() if not callable.is_custom() else str(callable)])
	return out


## How many of `hookups` are PanelFit's fits.
func _fits(hookups: Array) -> int:
	return hookups.filter(func(h): return String(h).begins_with(PANEL_FIT + " ")).size()


## The hookups in `now` that `base` did not have (each counted as often as it is in `now` beyond `base`).
func _extra(now: Array, base: Array) -> Array:
	var left := base.duplicate()
	var out := []
	for h in now:
		var i := left.find(h)
		if i >= 0:
			left.remove_at(i)
		else:
			out.append(h)
	return out


func _frames(n: int) -> void:
	for k in n:
		await process_frame
