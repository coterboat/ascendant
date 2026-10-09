extends "res://tests/test_case.gd"
## MVP-1 (#141) acceptance, every screen fits the default window: at 1600x900 (project.godot's size) and at 1280x720
## (also what 1600x900 becomes at Settings' 125% interface size), the New game screen's Start and Back buttons, the
## victory screen's last section and its buttons, the title, the build screen, the codex, the settings and the load screen
## all lie inside the viewport, or inside a ScrollContainer that does, with the buttons pinned outside the scroll.
## The headless runner's tests run before the scene tree is live, so no Control gets a layout pass here. The layout is
## measured by tests/screen_fit_probe.gd instead, a real (headless) main loop in a child Godot process that puts each
## screen in a SubViewport of the size and prints where everything ended up. One probe run serves the whole file.
## The live check of the same screens, with pictures, is tools/shots/play_shots.gd (windowed).

const PROBE := "res://tests/screen_fit_probe.gd"
const SCRATCH := "user://screen_fit_probe"  # the probe's own settings and saves (tests/screen_fit_probe.gd)
const SIZES := {"1600x900": Vector2(1600, 900), "1280x720": Vector2(1280, 720)}
const SCREENS := ["title", "new_game", "new_game_full", "new_game_error", "victory", "victory_actions", "victory_everything",
	"victory_draw", "build", "codex", "settings", "load", "guide", "game", "game_research", "game_report"]
const NEW_GAMES := ["new_game", "new_game_full", "new_game_error"]
const VICTORIES := ["victory", "victory_actions", "victory_everything", "victory_draw"]
## A scroll container smaller than this is not a visible way to the content in it.
const MIN_SCROLL_HEIGHT := 200.0

static var _reports := {}


# --- the probe --------------------------------------------------------------------------------------

## The probe's report for a run with `args` (after "--"): {"1600x900": {screen: {"clipped", "rects"}}, "1280x720": ...}.
## One child process per distinct `args`, kept for the rest of the run.
func _report(args: Array = []) -> Dictionary:
	var key := " ".join(args)
	if _reports.has(key):
		return _reports[key]
	var cmd := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", PROBE]
	if not args.is_empty():
		cmd.append("--")
		cmd.append_array(args)
	var output := []
	var code := OS.execute(OS.get_executable_path(), cmd, output, true)
	_remove_tree(SCRATCH)  # the probe's scratch settings and saves
	var text := "\n".join(output)
	var parsed = {}
	for line in text.split("\n"):
		if line.begins_with("FIT_REPORT "):
			parsed = JSON.parse_string(line.trim_prefix("FIT_REPORT "))
	assert_true(parsed is Dictionary and not parsed.is_empty(), "the probe reported (exit code %d): %s" % [code, text.right(600)])
	_reports[key] = parsed if parsed is Dictionary else {}
	return _reports[key]


## Deletes a folder and everything in it.
static func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for sub in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(sub))
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)


func _screen(size_key: String, name: String, args: Array = []) -> Dictionary:
	var sizes := _report(args)
	if not sizes.has(size_key) or not sizes[size_key].has(name):
		assert_true(false, "the probe measured %s at %s" % [name, size_key])
		return {"clipped": [], "rects": {}}
	return sizes[size_key][name]


## A rect from the report: Rect2 and whether the node was visible in the tree.
func _rect(screen: Dictionary, key: String) -> Rect2:
	var r: Array = screen.rects.get(key, [])
	assert_true(r.size() == 5, "the probe found %s" % key)
	return Rect2(r[0], r[1], r[2], r[3]) if r.size() == 5 else Rect2()


func _shown(screen: Dictionary, key: String) -> bool:
	var r: Array = screen.rects.get(key, [])
	return r.size() == 5 and bool(r[4])


func _inside(r: Rect2, viewport: Vector2) -> bool:
	return Rect2(Vector2.ZERO, viewport).grow(0.5).encloses(r)


## The ticket's alternative to "inside the viewport": a section inside a scroll container that is itself on screen,
## big enough to read, and reaches the section (it starts below the scroll's top).
func _reachable(section: Rect2, scroll: Rect2, viewport: Vector2) -> bool:
	return _inside(scroll, viewport) and scroll.size.y >= MIN_SCROLL_HEIGHT and section.position.y >= scroll.position.y \
		and section.position.x >= scroll.position.x - 0.5 and section.end.x <= scroll.end.x + 0.5


func _each_size(check: Callable) -> void:
	for key in SIZES:
		check.call(key, SIZES[key])


# --- the tests --------------------------------------------------------------------------------------

func test_the_probe_measured_every_screen_at_both_sizes() -> void:
	var report := _report()
	for key in SIZES:
		assert_true(report.has(key), "a report for %s" % key)
		for name in SCREENS:
			assert_true(report.get(key, {}).has(name), "%s was measured at %s" % [name, key])


func test_nothing_clips_at_either_size() -> void:
	_each_size(func(key: String, _viewport: Vector2):
		for name in SCREENS:
			assert_eq(_screen(key, name).clipped, [], "%s at %s: nothing reaches outside the window outside a scroll container" % [name, key]))


func test_new_game_start_and_back_are_on_screen_below_the_body() -> void:
	_each_size(func(key: String, viewport: Vector2):
		for name in NEW_GAMES:
			var s := _screen(key, name)
			var start := _rect(s, "start")
			var back := _rect(s, "back")
			var scroll := _rect(s, "scroll")
			var where := "%s at %s" % [name, key]
			assert_true(_shown(s, "start") and _inside(start, viewport), "%s: Start is inside the viewport (%s)" % [where, start])
			assert_true(_shown(s, "back") and _inside(back, viewport), "%s: Back is inside the viewport (%s)" % [where, back])
			assert_true(start.position.y >= scroll.end.y - 0.5 and back.position.y >= scroll.end.y - 0.5, "%s: the buttons are pinned below the scrolling body, not in it" % where)
			assert_true(_inside(_rect(s, "panel"), viewport), "%s: the panel is inside the viewport" % where)
			assert_true(_inside(scroll, viewport) and scroll.size.y >= MIN_SCROLL_HEIGHT, "%s: the body is a visible scroll container (%s)" % [where, scroll])
			if name == "new_game_error":
				assert_true(_shown(s, "error") and _inside(_rect(s, "error"), viewport), "%s: why Start is off is on screen too" % where))


func test_the_default_new_game_screen_needs_no_scrolling_at_1600x900() -> void:
	var s := _screen("1600x900", "new_game")
	assert_true(float(s.rects.content_h) <= _rect(s, "scroll").size.y, "the seats, seed and boxes (%d px) fit the body at 1600x900 (%d px)" % [
		s.rects.content_h, _rect(s, "scroll").size.y])


func test_the_victory_screens_last_section_and_buttons_are_on_screen() -> void:
	_each_size(func(key: String, viewport: Vector2):
		for name in VICTORIES:
			var s := _screen(key, name)
			var where := "%s at %s" % [name, key]
			var last := _rect(s, "captures")
			var scroll := _rect(s, "scroll")
			assert_true(_shown(s, "captures") and _shown(s, "captures_heading"), "%s: Capitals captured is there" % where)
			assert_true(_inside(last, viewport) or _reachable(last, scroll, viewport),
				"%s: the last section (%s) lies inside the viewport or inside a visible scroll container (%s)" % [where, last, scroll])
			for button in ["new_game", "back"]:
				var r := _rect(s, button)
				assert_true(_shown(s, button) and _inside(r, viewport), "%s: %s is inside the viewport (%s)" % [where, button, r])
				assert_true(r.position.y >= scroll.end.y - 0.5, "%s: %s is pinned below the scrolling body" % [where, button])
			if _shown(s, "actions"):
				assert_true(_inside(_rect(s, "actions"), viewport) and _rect(s, "actions").position.y >= scroll.end.y - 0.5, "%s: the extra buttons are pinned too" % where)
			assert_true(_inside(_rect(s, "panel"), viewport), "%s: the panel is inside the viewport" % where))


func test_a_games_victory_screen_needs_no_scrolling_at_1600x900() -> void:
	for name in ["victory", "victory_actions", "victory_draw"]:
		var s := _screen("1600x900", name)
		assert_true(float(s.rects.content_h) <= _rect(s, "scroll").size.y, "%s: every section (%d px) is on screen at 1600x900 without scrolling (%d px)" % [
			name, s.rects.content_h, _rect(s, "scroll").size.y])
		assert_true(_inside(_rect(s, "captures"), SIZES["1600x900"]) and _rect(s, "captures").end.y <= _rect(s, "scroll").end.y + 0.5, "%s: Capitals captured is inside the body" % name)


func test_the_title_fits_with_a_save_and_hides_the_dev_link() -> void:
	_each_size(func(key: String, viewport: Vector2):
		var s := _screen(key, "title")
		assert_true(_inside(_rect(s, "box"), viewport), "the title's menu at %s is inside the viewport (%s)" % [key, _rect(s, "box")])
		for button in ["continue", "new_game", "quit"]:
			assert_true(_shown(s, button) and _inside(_rect(s, button), viewport), "%s is on screen at %s" % [button, key])
		assert_false(_shown(s, "map_preview"), "Map preview (dev) is hidden at %s without --dev" % key))
	# In-process too: the button is still there (tests and tools find it), only hidden.
	var title: TitleScreen = load("res://ui/title_screen.tscn").instantiate()
	title.store = SaveStore.new(SCRATCH.path_join("title_saves"))
	title.refresh_saves()
	assert_false(TitleScreen.dev_mode(), "the runner is not launched with --dev")
	assert_true(title.map_preview_button != null and not title.map_preview_button.visible, "hidden unless launched with -- --dev")
	assert_false(title.get_node("Center/Box/DevGap").visible, "and its gap goes with it")
	assert_eq(title.map_preview_button.text, "Map preview (dev)", "it is still the developer preview")
	title.free()
	_remove_tree(SCRATCH)


func test_the_title_shows_the_dev_link_with_dev() -> void:
	_each_size(func(key: String, viewport: Vector2):
		var s := _screen(key, "title", ["--dev"])
		assert_true(_shown(s, "map_preview"), "launched with -- --dev, Map preview (dev) is there at %s" % key)
		assert_true(_inside(_rect(s, "box"), viewport) and _inside(_rect(s, "map_preview"), viewport), "and the title still fits at %s with it" % key)
		assert_eq(s.clipped, [], "nothing clips with it at %s" % key))


func test_the_build_screen_fits_and_its_columns_scroll_under_pinned_buttons() -> void:
	_each_size(func(key: String, viewport: Vector2):
		var s := _screen(key, "build")
		var columns := _rect(s, "columns")
		assert_true(_inside(_rect(s, "lock_in"), viewport) and _inside(_rect(s, "back"), viewport), "Lock in build and Back are on screen at %s" % key)
		assert_true(_inside(columns, viewport) and columns.size.y >= MIN_SCROLL_HEIGHT, "the columns sit in a visible scroll container at %s (%s)" % [key, columns])
		assert_true(_rect(s, "lock_in").position.y >= columns.end.y - 0.5, "Lock in build is pinned below the columns at %s" % key))


func test_the_codex_settings_and_load_screens_fit() -> void:
	_each_size(func(key: String, viewport: Vector2):
		var codex := _screen(key, "codex")
		assert_true(_inside(_rect(codex, "panel"), viewport) and _inside(_rect(codex, "close"), viewport), "the codex and its Close fit at %s" % key)
		var settings := _screen(key, "settings")
		assert_true(_inside(_rect(settings, "panel"), viewport) and _inside(_rect(settings, "close"), viewport), "the settings and their Close fit at %s" % key)
		assert_true(_shown(settings, "guide") and _inside(_rect(settings, "guide"), viewport), "Show the first-game guide again is on screen at %s" % key)
		var load := _screen(key, "load")
		var list := _rect(load, "list")
		assert_true(_inside(_rect(load, "panel"), viewport) and _inside(_rect(load, "back"), viewport), "the load screen and its Back fit at %s" % key)
		assert_true(_inside(list, viewport) and _rect(load, "back").position.y >= list.end.y - 0.5, "its list scrolls above a pinned Back at %s" % key))


func test_the_first_game_card_is_small_and_in_the_corner_at_both_sizes() -> void:
	_each_size(func(key: String, viewport: Vector2):
		var card := _rect(_screen(key, "guide"), "card")
		assert_true(_shown(_screen(key, "guide"), "card"), "the card shows at %s" % key)
		assert_true(_inside(card, viewport), "the card, with every system on, is inside the viewport at %s (%s)" % [key, card])
		assert_true(card.position.x <= 16.0 and card.position.y <= 110.0, "in the top-left corner, under the top bar, at %s (%s)" % [key, card])
		assert_true(card.end.y <= 360.0, "and ends above where the player's capital and its order tags start at 1600x900 (%d px)" % card.end.y)
		assert_true(card.size.x <= 360.0, "narrow (%d px)" % card.size.x)
		# The player's capital starts about 45% of the way down the map's left edge: with every system on the card ends above it.
		assert_true(card.end.y <= viewport.y * 0.54, "and short enough to leave the map its room at %s: it ends %d px down of %d" % [key, card.end.y, viewport.y]))


# --- the game screen with every system on (MVP-3, #177) ---------------------------------------------------------

func test_the_top_bar_shows_every_button_at_both_sizes() -> void:
	_each_size(func(key: String, viewport: Vector2):
		var g := _screen(key, "game")
		var where := "the game screen at %s" % key
		assert_true(_inside(_rect(g, "bar"), viewport), "%s: the top bar is inside the window (%s)" % [where, _rect(g, "bar")])
		assert_true(_shown(g, "end_turn") and _inside(_rect(g, "end_turn"), viewport), "%s: End turn is on screen (%s)" % [where, _rect(g, "end_turn")])
		assert_true(_shown(g, "menu") and _inside(_rect(g, "menu"), viewport), "%s: Menu is on screen (%s)" % [where, _rect(g, "menu")])
		assert_true(_shown(g, "hint") and _inside(_rect(g, "hint"), viewport), "%s: the hint is on screen (%s)" % [where, _rect(g, "hint")])
		assert_true(_rect(g, "hint").size.x >= 300.0, "%s: the hint has room (%d px)" % [where, _rect(g, "hint").size.x])
		for button in ["research", "magic", "ruler", "report", "codex"]:
			assert_true(_shown(g, button) and _inside(_rect(g, button), viewport), "%s: %s is on screen (%s)" % [where, button, _rect(g, button)])
		assert_true(_rect(g, "bar").end.y <= _rect(g, "map").position.y + 0.5, "%s: the map starts under the bar" % where)
		assert_true(_rect(g, "side").end.x <= viewport.x + 0.5, "%s: the side panel is inside the window" % where))
	# The narrow window needs the second row, the wide one does not: both come from the layout, not from this file.
	var wide := _screen("1600x900", "game")
	var narrow := _screen("1280x720", "game")
	assert_true(float(narrow.rects.narrow[0]) > 0.5, "at 1280x720 (125%) the optional buttons wrap beside the hint")
	assert_false(float(wide.rects.narrow[0]) > 0.5, "at 1600x900 they all fit in one row")


func test_the_first_game_card_hangs_under_the_bar_and_leaves_the_capitals_neighbor() -> void:
	_each_size(func(key: String, viewport: Vector2):
		var g := _screen(key, "game")
		var card := _rect(g, "guide")
		assert_true(_shown(g, "guide"), "the card is up at %s" % key)
		assert_true(card.position.y >= _rect(g, "bar").end.y, "at %s it hangs under the top bar (%s under %s)" % [key, card, _rect(g, "bar")])
		assert_true(_inside(card, viewport), "and inside the window at %s" % key)
		# The card folds its other systems and keeps How to play in its head row: 160 px, where it was 265 with every system's line
		# open. At 125% (the 1280x720 layout) that ends above the capital's neighbor's name plate.
		assert_true(card.size.y <= 170.0, "folded, the card is short at %s (%d px)" % [key, card.size.y]))


func test_the_big_panels_fit_the_window_at_both_sizes() -> void:
	_each_size(func(key: String, viewport: Vector2):
		var research := _screen(key, "game_research")
		assert_true(_shown(research, "research_panel"), "the research panel is open at %s" % key)
		assert_true(_inside(_rect(research, "research_panel"), viewport), "the research panel's Magic tab fits the window at %s (%s)" % [key, _rect(research, "research_panel")])
		assert_true(_shown(research, "research_close") and _inside(_rect(research, "research_close"), viewport), "its Close is on screen at %s" % key)
		var report := _screen(key, "game_report")
		assert_true(_shown(report, "report_box"), "the turn report is open at %s" % key)
		assert_true(_inside(_rect(report, "report_box"), viewport), "the turn report fits the window at %s (%s)" % [key, _rect(report, "report_box")])
		assert_true(_shown(report, "report_close") and _inside(_rect(report, "report_close"), viewport), "its Close is on screen at %s" % key))
