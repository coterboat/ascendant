extends SceneTree
## QA-1 (#250): a monkey that plays the game the way a player's hand does. It starts a default game through the title's own
## SceneFlow (Quick start's config: every system on, the computer at Normal, rulers on the balanced preset, a fresh settings file so
## the first-game guide shows), then drives it only through real input: Input.parse_input_event with mouse motion, clicks, double
## and right clicks, drags between controls, the wheel and keys, each handled at once (Input.flush_buffered_events, the call the
## OS's event loop makes). Nothing here gives an order through the game's API: it reads the game only to aim (what is on screen,
## where a province or an army stands on the board) and to know when to stop. Dev tool only: never runs in the game or the tests.
##
##   $GODOT --path . --always-on-top --audio-driver Dummy --fixed-fps 60 --resolution 1600x900 --log-file DIR/godot.log \
##       -s res://tools/qa/monkey.gd -- --out=DIR [options]
##   (tools/qa/run_monkey.sh does this and says how the run ended; see tools/qa/README.md)
##
## Options (all optional):
##   --seed=N          the monkey's seed (default 1): the game's config (factions, game seed, the computer's build) and every choice
##                     of the hand come from it, so the same seed on the same build, window and interface size plays the same events
##   --out=DIR         events.log, summary.json, shots/ and the run's own settings and saves (default /tmp/ascendant-qa/monkey_<seed>)
##   --turns=N         stop once turn N+1 begins (default 12)
##   --minutes=M       stop after M minutes of play (default 20)
##   --ui-scale=N      the interface size in percent (100 or 125), saved as Settings saves it before the title appears
##   --resolution=WxH  resize the window to WxH at start (run_monkey.sh passes Godot's own --resolution instead)
##   --fog=on|off      fog of war (default on, as a new game ships)
##   --human=ID        the faction the person plays (default: the seed's pick, as Quick start picks)
##   --focus=AREA      weight one area (comma-separated for several): muster, research, fort, battles, chronicle, settings
##   --pace=N          the hand's average wait between gestures in frames (default 6)
##   --shots=N         a shot every N gestures (default 60; 0 for none), besides the start, each new turn, each screen not seen
##                     before (up to 40) and the end
##   --slow-ms=N       a frame slower than this is noted as SLOW with the gesture before it (default 400)
##   --build=TEXT      the build under test (run_monkey.sh passes the git sha and branch), written into the log's options
##   --replay=FILE     send the events of an events.log again at their frames instead of choosing them (the seed, faction, fog and
##                     interface size come from the log's options note; give the same window size)
##   --selftest=KIND   the harness checking itself: after 5 gestures the monkey raises an error ("error"), stops the main thread
##                     ("hang") or crashes Godot ("crash"), so run_monkey.sh's ERRORS, HANG and CRASH endings can be seen
##
## Every event goes to DIR/events.log BEFORE it is handled (flushed line by line, so a native crash leaves the line that caused it):
## `frame <TAB> json <TAB> what it aimed at  @ the screen and panels up` (tools/qa/monkey_log.gd). `#` lines are notes: the options and
## config, the turn changes, each engine or script error with the gesture before it, slow frames, shots, STUCK, and HOVER-FREED: Godot
## kept a control that left the tree as the hovered one (#249's class: the next mouse event after it is freed crashes). At the end
## DIR/summary.json says how the run ended: "turns", "minutes", "over", "stuck" (exit 4), "left_game" or "replayed".

const MonkeyLog := preload("res://tools/qa/monkey_log.gd")
const TITLE_SCENE := "res://ui/title_screen.tscn"
const AREAS := ["muster", "research", "fort", "battles", "chronicle", "settings"]
## The classes whose controls belong to an area: the hand aims inside them most of the time while one is on screen.
const FOCUS := {
	"muster": ["MusterBoard", "UnitStrip", "ArmyCard", "ArmyRow"],
	"research": ["ResearchPanel", "ResearchHud", "PathView", "LockInPreview"],
	"fort": ["FortPanel", "FortifyControls", "FortChip", "ProvinceCard", "RecruitSection", "WallsBar", "FortView"],
	"battles": ["BattleHost", "BattleControls", "BattleSimpleView", "BattleScrubber", "BattleReportViewer", "BattleWhyPanel", "BattleCard",
		"TurnReportPanel", "BattleLegend", "BattleStrengthBar"],
	"chronicle": ["ChronicleHud", "ChronicleColumn", "NoticeCard", "NoticeStack", "PlanHud", "PlanPage", "NoticeMedallion"],
	"settings": ["SettingsPanel"],
}
## The words on a control (its name, text or tooltip's first line) that lead to an area, so the hand finds its way there.
const OPENERS := {
	"muster": ["split", "merge", "new army", "armies here", "swap", "engines", "army"],
	"research": ["research", "magic", "spell", "path"],
	"fort": ["fort", "palisade", "keep", "storm", "sally", "recruit", "walls"],
	"battles": ["watch", "battle", "report", "replay", "skip", "march"],
	"chronicle": ["chronicle", "plan", "notice", "seal", "read"],
	"settings": ["menu", "settings", "resume", "interface", "volume"],
}
## Screens and panels named in the log while they are on screen: by script class, and the game screen's overlays by node name.
const PANELS := ["ArmyCard", "ProvinceCard", "OrderCard", "MusterBoard", "ResearchPanel", "FortPanel", "ChronicleColumn", "PlanPage",
	"BattleHost", "BattleSimpleView", "BattleReportViewer", "TurnReportPanel", "SettingsPanel", "CodexPanel", "RulerPanel", "CastDialog",
	"SacrificeDialog", "VictoryScreen", "HandoffScreen", "LoadScreen", "NewGameScreen", "BuildScreen", "FirstGameGuide", "ControlsHelp",
	"LensLegend"]
const PANEL_NAMES := ["GameMenu", "QuitConfirm", "SaveDialog", "ReportOverlay", "SetupErrors"]
## Never pressed: these close the app, take the window out from on top (a fullscreen window), or start a game whose seed is drawn
## at random (Quick start, the new game screen's Start and the build screen's Ready), which a seed could not replay.
const DENY_NAMES := ["QuitButton", "WindowPicker", "QuickStartButton"]
const DENY_UNDER := {"StartButton": "NewGameScreen", "ReadyButton": "BuildScreen"}
const KEYS := [KEY_ESCAPE, KEY_SPACE, KEY_ENTER, KEY_TAB, KEY_F1, KEY_F, KEY_C, KEY_HOME, KEY_L, KEY_W, KEY_A, KEY_S, KEY_D, KEY_UP,
	KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_QUOTELEFT, KEY_M, KEY_N, KEY_R, KEY_EQUAL, KEY_MINUS,
	KEY_COMMA, KEY_PERIOD, KEY_END, KEY_P, KEY_E, KEY_Q, KEY_O, KEY_DELETE, KEY_BACKSPACE]
const NEW_SCREEN_SHOTS := 40


## Engine and script errors from anywhere (any thread), held until the main loop writes them into events.log beside the last gesture.
class QaLogger extends Logger:
	var mutex := Mutex.new()
	var pending: Array = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int,
			script_backtraces: Array[ScriptBacktrace]) -> void:
		var kind: String = ["ERROR", "WARNING", "SCRIPT ERROR", "SHADER ERROR"][clampi(error_type, 0, 3)]
		var text := "%s: %s (%s at %s:%d)" % [kind, rationale if rationale != "" else code, function, file, line]
		for bt in script_backtraces:
			var frames: PackedStringArray = []
			for i in mini(bt.get_frame_count(), 4):
				frames.append("%s %s:%d" % [bt.get_frame_function(i), bt.get_frame_file(i), bt.get_frame_line(i)])
			if not frames.is_empty():
				text += " <- " + " <- ".join(frames)
				break
		mutex.lock()
		pending.append(text)
		mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

	func take() -> Array:
		mutex.lock()
		var out := pending
		pending = []
		mutex.unlock()
		return out


var seed_n := 1
var out := ""
var max_turns := 12
var max_minutes := 20.0
var ui_scale := 100
var resolution := Vector2i.ZERO
var fog := true
var human := ""
var focus: PackedStringArray = []
var pace := 6
var shot_every := 60
var slow_ms := 400
var build := ""
var selftest := ""
var replay_path := ""
var replay_options := {}
var unknown_options: PackedStringArray = []

var rng := RandomNumberGenerator.new()
var log_file: FileAccess
var qa_logger: QaLogger
var frame_n := 0  # frames since the board was ready (the replay's clock)
var _last_usec := 0
var mouse := Vector2.ZERO  # where the hand's pointer is, in window pixels
var mask := 0
var gestures := 0
var events := 0
var errors := 0
var own_errors := 0  # errors raised in tools/qa/ (the monkey's own bugs, never the game's)
var warnings := 0
var hover_freed := 0
var slow: Array = []  # {"frame", "ms", "after", "turn"}
var last_what := "(start)"
var started_msec := 0
var config := {}
var turn_seen := 0
var turn_gestures := 0
var turn_budget := 30
var end_tries := 0
var off_game := 0
var verdict := ""
var shots := 0
var screens_seen := {}
var aim_checked := false
## The targets of the screen as last read: {"kind", "rect" (window pixels), "node", "what", "w", "area", "way", "dir"}.
var targets: Array = []
var drops: Array = []
var panel_nodes: Array = []  # [name, node] of the panels up at the last read
var _reveal := {}  # scroll container id -> {"node", "dir", "what"}: a focused area hidden in it (scroll that way to see it)
var _xf := Transform2D.IDENTITY  # the root's final transform: viewport (canvas) units to window pixels
var _hover_id := 0
var _hover_desc := "nothing"
var _stale_id := 0
var _pending_shot := ""
var _march_follow := false  # --focus=battles: March was just pressed, so the next gesture picks a neighbouring province


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=", true, 1)
		var v := kv[1] if kv.size() > 1 else ""
		match kv[0]:
			"seed": seed_n = int(v)
			"out": out = v
			"turns": max_turns = int(v)
			"minutes": max_minutes = float(v)
			"ui-scale": ui_scale = int(v)
			"resolution": resolution = MonkeyLog.parse_size(v)
			"fog": fog = v != "off"
			"human": human = v
			"focus": focus = v.split(",", false)
			"pace": pace = maxi(1, int(v))
			"shots": shot_every = int(v)
			"slow-ms": slow_ms = int(v)
			"build": build = v
			"selftest": selftest = v
			"replay": replay_path = v
			_: unknown_options.append(a)
	if not replay_path.is_empty():
		# The seed, faction, fog and interface size of the run being replayed (its options note), whatever the command line says.
		replay_options = MonkeyLog.note_json(MonkeyLog.head(replay_path), "options")
		if replay_options.is_empty():
			push_error("monkey: %s has no options note to replay" % replay_path)
		seed_n = int(replay_options.get("seed", seed_n))
		ui_scale = int(replay_options.get("ui_scale", ui_scale))
		fog = bool(replay_options.get("fog", fog))
		human = String(replay_options.get("human", human))
	if out.is_empty():
		out = "/tmp/ascendant-qa/monkey_%d" % seed_n
	if not replay_path.is_empty() and ProjectSettings.globalize_path(out.path_join("events.log")) == ProjectSettings.globalize_path(replay_path):
		out = out.path_join("replay")  # never write over the log being replayed
	var base := out
	var n := 2
	while FileAccess.file_exists(out.path_join("events.log")):
		out = "%s_%d" % [base, n]  # a folder of its own: never another run's log, settings or saves
		n += 1
	DirAccess.make_dir_recursive_absolute(out.path_join("shots"))
	rng.seed = hash("monkey %d" % seed_n)
	# The run's own settings and saves, never the player's: no settings file, so the first-game guide shows as for a new player.
	GameSettings.default_path = out.path_join("settings.cfg")
	SaveStore.default_root = out.path_join("saves")
	if GameSettings.UI_SCALES.has(ui_scale) and ui_scale != 100:
		var saved := GameSettings.new(GameSettings.default_path)
		saved.set_ui_scale(ui_scale)
		saved.save()
	if resolution != Vector2i.ZERO:
		DisplayServer.window_set_size(resolution)
	# As play_shots: without vsync a covered window still renders and the run never waits on the display.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	qa_logger = QaLogger.new()
	OS.add_logger(qa_logger)
	log_file = FileAccess.open(out.path_join("events.log"), FileAccess.WRITE)
	process_frame.connect(_on_frame)
	_run()


# --- the run --------------------------------------------------------------------------------------------------------

func _run() -> void:
	await _frames(2)
	_keep_off_the_cursor()
	var screen := DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
	_note("options " + JSON.stringify({"seed": seed_n, "ui_scale": ui_scale, "fog": fog, "human": human, "focus": ",".join(focus),
		"turns": max_turns, "minutes": max_minutes, "pace": pace, "window": [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y],
		"screen": [screen.x, screen.y], "build": build, "replay": replay_path, "godot": Engine.get_version_info().string}))
	if not unknown_options.is_empty():
		_note("unknown options ignored: %s" % " ".join(unknown_options))
	for a in focus:
		if not AREAS.has(a):
			_note("unknown focus area %s (the areas: %s)" % [a, ", ".join(AREAS)])
	if not replay_options.is_empty() and replay_options.get("window") is Array:
		var was: Array = replay_options.window
		if Vector2i(int(was[0]), int(was[1])) != DisplayServer.window_get_size():
			_note("REPLAY WINDOW DIFFERS: the run was %dx%d, this window is %s: the clicks land elsewhere" % [int(was[0]), int(was[1]), DisplayServer.window_get_size()])
	change_scene_to_file(TITLE_SCENE)
	await _frames(4)
	var title := current_scene as TitleScreen
	if title == null:
		_finish("no_title")
		return
	config = _game_config()
	_note("config " + JSON.stringify(config))
	title.start_game(config)  # the title's own path to a game (SceneFlow.make_game, then switch), as Start and Quick start take it
	var t0 := Time.get_ticks_msec()
	while not _board_ready():
		await process_frame
		if Time.get_ticks_msec() - t0 > 300000:
			_finish("no_board")
			return
	await _frames(30)
	mouse = Vector2(root.size) * 0.5
	_note("ready: window %s, laid out at %s (ui scale %d%%), turn %d, loaded in %.1f s" % [root.size, root.get_visible_rect().size,
		ui_scale, _turn(), (Time.get_ticks_msec() - t0) / 1000.0])
	started_msec = Time.get_ticks_msec()
	frame_n = 0
	turn_seen = _turn()
	if replay_path.is_empty():
		await _shot("start")
		await _aim_check()
		await _play()
	else:
		await _replay()
	if verdict.is_empty():
		verdict = "done"
	await _shot("end")
	_finish(verdict)


func _game_config() -> Dictionary:
	var dice := RandomNumberGenerator.new()
	dice.seed = seed_n
	var cfg := NewGameScreen.quick_start_config(dice)
	if not human.is_empty() and human != String(cfg.players[0]):
		var foe := ""
		for f in FactionData.FACTIONS:
			if String(f.id) != human:
				foe = String(f.id)
				break
		cfg.players = [human, foe]
		cfg.ai = {foe: NewGameScreen.DEFAULT_LEVEL}
		cfg.builds = {human: RulerRules.preset_build(RulerRules.balanced_preset(human)), foe: BuildScreen.computer_build(foe, int(cfg.seed), 1)}
	human = String(cfg.players[0])
	if not fog:
		cfg.fog = false
	return cfg


## One motion onto the seal, and the control Godot then holds as hovered must be the seal: the hand's window pixels and the game's
## layout agree at this window size and interface scale (a 1280x720 window, or 125%, scales the canvas).
func _aim_check() -> void:
	var g := _game()
	if g == null or g.get("end_turn_button") == null or not (g.end_turn_button as Control).is_visible_in_tree():
		return
	var b: Control = g.end_turn_button
	_xf = root.get_final_transform()
	var r := _win_rect(b)
	_motion(r.get_center(), "aim check: the seal's middle")
	var h := root.gui_get_hovered_control()
	aim_checked = h != null and (h == b or b.is_ancestor_of(h))
	_note("aim check %s: the seal at %s (window pixels), hovered %s" % ["ok" if aim_checked else "FAILED", r, _describe(h)])
	await _frames(2)


func _play() -> void:
	turn_budget = rng.randi_range(12, 50)
	while true:
		var why := _stop_reason()
		if not why.is_empty():
			verdict = why
			return
		await _gesture()
		gestures += 1
		turn_gestures += 1
		if game_is_up() == false:
			off_game += 1
		if gestures == 5 and not selftest.is_empty():
			_selftest()
		if shot_every > 0 and gestures % shot_every == 0:
			await _shot("g%d" % gestures)
		var wait := rng.randi_range(1, pace * 2)
		if rng.randf() < 0.06:
			wait += rng.randi_range(20, 70)  # a pause: tooltips open, the board settles
		await _frames(wait)


func game_is_up() -> bool:
	return _game() != null


## --selftest: the harness's own endings, on demand (never during a hunt).
func _selftest() -> void:
	_note("SELFTEST %s" % selftest)
	match selftest:
		"error":
			push_error("monkey selftest: an error, as the game's would be logged")
		"hang":
			var until := Time.get_ticks_msec() + 3600 * 1000
			while Time.get_ticks_msec() < until:
				pass  # the main thread stops here, as a game that loops forever would
		"crash":
			OS.crash("monkey selftest: a native crash")


func _stop_reason() -> String:
	var game := _game()
	if game == null:
		return "left_game" if off_game > 120 else ""
	off_game = 0
	if started_msec > 0 and (Time.get_ticks_msec() - started_msec) / 60000.0 >= max_minutes:
		return "minutes"
	var turn := _turn()
	if turn != turn_seen:
		_note("turn %d begins (after %d gestures on turn %d, %d end-turn tries)" % [turn, turn_gestures, turn_seen, end_tries])
		turn_seen = turn
		turn_gestures = 0
		end_tries = 0
		turn_budget = rng.randi_range(12, 50)
		_pending_shot = "t%02d" % turn
	if turn > max_turns:
		return "turns"
	if game.session != null and game.session.is_over() and turn_gestures > 60:
		return "over"
	if end_tries >= 40:
		_note("STUCK: turn %d did not end after %d tries to seal it; up: %s" % [turn, end_tries, _screen()])
		return "stuck"
	return ""


# --- one gesture ----------------------------------------------------------------------------------------------------

func _gesture() -> void:
	if not _pending_shot.is_empty():
		var n := _pending_shot
		_pending_shot = ""
		await _shot(n)
	_read_screen()
	var sig := _screen()
	if not screens_seen.has(sig):
		screens_seen[sig] = true
		if screens_seen.size() <= NEW_SCREEN_SHOTS and gestures > 0:
			await _shot("new_" + sig.replace(">", "+").replace(" ", "").left(60))
	if _march_follow:
		# --focus=battles: a march needs its destination, as a player clicks it next (into a garrison, a rival: a battle)
		_march_follow = false
		var dest := _march_target()
		if not dest.is_empty() and rng.randf() < 0.8:
			await _click(_point_in(dest.rect, true), MOUSE_BUTTON_LEFT, false, "march to %s" % dest.what)
			return
	if turn_gestures >= turn_budget and rng.randf() < 0.35:
		await _end_turn()
		return
	var roll := rng.randf()
	if roll < 0.05:
		await _key_gesture()
		return
	if roll < 0.08:
		await _tap_key(KEY_ESCAPE, "Esc")
		return
	if roll < 0.11:
		await _sweep()
		return
	if roll < 0.13:
		await _end_turn()
		return
	var t := _pick_target()
	if t.is_empty():
		await _sweep()
		return
	await _act_on(t)


func _act_on(t: Dictionary) -> void:
	var r: Rect2 = t.rect
	var p := _point_in(r, String(t.kind).begins_with("board") or t.kind == "window")
	var what := "%s %s" % [t.kind, t.what]
	var roll := rng.randf()
	match String(t.kind):
		"drag":
			if roll < 0.6 and not drops.is_empty():
				var d: Dictionary = drops[rng.randi_range(0, drops.size() - 1)]
				await _drag(p, _point_in(d.rect, false), "%s -> drop %s" % [what, d.what])
			elif roll < 0.75:
				var other := _pick_target()
				await _drag(p, _point_in(other.rect, false) if not other.is_empty() else _random_point(), "%s -> %s" % [what, other.get("what", "anywhere")])
			else:
				await _click(p, MOUSE_BUTTON_LEFT, false, what)
		"text":
			await _click(p, MOUSE_BUTTON_LEFT, false, what)
			for i in rng.randi_range(1, 8):
				await _type_char()
			if rng.randf() < 0.5:
				await _tap_key(KEY_ENTER if rng.randf() < 0.7 else KEY_ESCAPE, "after typing")
		"range":
			if roll < 0.5:
				await _click(p, MOUSE_BUTTON_LEFT, false, what)
			elif roll < 0.8:
				await _drag(p, _point_in(r, false), what + " (slide)")
			else:
				await _wheel(p, rng.randi_range(1, 4), rng.randf() < 0.5, what)
		"scroll":
			if roll < 0.7:
				await _wheel(p, rng.randi_range(1, 6), rng.randf() < 0.6, what)
			else:
				await _click(p, MOUSE_BUTTON_LEFT, false, what)
		"reveal":
			# the focused area is in this scroll, out of view: turn the wheel toward it, as a player scrolls to what they want
			await _wheel(p, rng.randi_range(2, 6), int(t.dir) < 0, what)
		"board":
			if roll < 0.35:
				await _drag(p, p + Vector2(rng.randf_range(-300, 300), rng.randf_range(-200, 200)), what + " (pan)")
			elif roll < 0.7:
				await _wheel(p, rng.randi_range(1, 8), rng.randf() < 0.5, what)
			else:
				await _click(p, MOUSE_BUTTON_LEFT if rng.randf() < 0.8 else MOUSE_BUTTON_RIGHT, false, what)
		"board_province", "board_army":
			if roll < 0.62:
				await _click(p, MOUSE_BUTTON_LEFT, false, what)
			elif roll < 0.77:
				await _click(p, MOUSE_BUTTON_LEFT, true, what)
			elif roll < 0.85:
				await _click(p, MOUSE_BUTTON_RIGHT, false, what)
			else:
				await _hover(p, what)
		_:
			# buttons, popups, tabs and any control that takes the mouse or explains itself on hover
			if roll < 0.68:
				await _click(p, MOUSE_BUTTON_LEFT, false, what)
				if focus.has("battles") and t.kind == "button" and String(t.what).contains("\"March\""):
					_march_follow = true
			elif roll < 0.76:
				await _click(p, MOUSE_BUTTON_LEFT, true, what)
			elif roll < 0.86:
				await _click(p, MOUSE_BUTTON_RIGHT, false, what)
			elif roll < 0.95:
				await _hover(p, what)
			else:
				await _drag(p, _random_point(), what + " (pressed, dragged off)")
	# A click that rebuilds what is under the mouse (#249): sometimes the hand keeps moving across it at once.
	if rng.randf() < 0.3:
		await _sweep(rng.randi_range(2, 5), 0)


func _end_turn() -> void:
	end_tries += 1
	var game := _game()
	var b: Control = game.end_turn_button if game != null and game.get("end_turn_button") is Control else null
	for t in targets:  # the first game's review: the seal opens the Plan, and its Seal the orders ends the turn
		if is_instance_valid(t.node) and String(t.node.name) == "SealButton" and t.kind == "button" and rng.randf() < 0.8:
			await _seal(t.node, "END TURN %s" % t.what)
			return
	if b == null or not b.is_visible_in_tree():
		# something covers the table: put away the topmost thing, as a player would
		await _tap_key(KEY_ESCAPE, "end turn: the seal is hidden")
		return
	await _seal(b, "END TURN seal \"%s\"%s" % [b.text.replace("\n", " "), " (disabled)" if (b as BaseButton).disabled else ""])


## Moves to the seal and presses it; when something else is under the pointer there (a panel over the table), the hand closes that
## instead, by its own Close button when it has one, else Esc, as a player would.
func _seal(b: Control, what: String) -> void:
	var p := _point_in(_win_rect(b), false)
	last_what = "click " + what
	await _travel(p, what, false)
	var h := root.gui_get_hovered_control()  # read right after the motion was handled: never a control freed since
	if h == null or h == b or b.is_ancestor_of(h):
		await _press_here(MOUSE_BUTTON_LEFT, false)
		return
	var close := _close_for(h)
	_note("the seal is covered by %s" % _describe(h))
	if close.is_empty() or rng.randf() < 0.25:
		await _tap_key(KEY_ESCAPE, "the seal is covered")
	else:
		await _click(_point_in(close.rect, false), MOUSE_BUTTON_LEFT, false, "close what covers the seal: %s" % close.what)


## The close button nearest the control `h` in the tree (Close, Resume, Back, x), or {}.
func _close_for(h: Control) -> Dictionary:
	var best := {}
	var best_depth := -1
	for t in targets:
		if t.kind != "button" or not is_instance_valid(t.node) or (t.node as BaseButton).disabled:
			continue
		var words := _words(t.node)
		var txt := String(t.node.get("text")).strip_edges()
		if not (words.contains("close") or words.contains("resume") or words.begins_with("back") or txt in ["×", "✕", "x", "X"]):
			continue
		var common: Node = t.node
		while common != null and not common.is_ancestor_of(h) and common != h:
			common = common.get_parent()
		var depth := 0 if common == null else String(common.get_path()).count("/")
		if depth > best_depth:
			best_depth = depth
			best = t
	return best


func _key_gesture() -> void:
	var k: Key = KEYS[rng.randi_range(0, KEYS.size() - 1)]
	if k in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT] and rng.randf() < 0.6:
		await _hold_key(k, rng.randi_range(4, 30))
	else:
		await _tap_key(k, "key")


# --- the screen -------------------------------------------------------------------------------------------------------

func _game() -> GameScreen:
	return current_scene as GameScreen


func _turn() -> int:
	var g := _game()
	return g.session.turn_number() if g != null and g.session != null else 0


func _board_ready() -> bool:
	var g := _game()
	if g == null or g.map == null or not BattleStage3D.land_ready():
		return false
	var b = g.map.board
	return b == null or bool(b.get("prepared"))


## The scene and the panels up at the last read that are still on screen, e.g. "GameScreen>ArmyCard>MusterBoard".
func _screen() -> String:
	var names: PackedStringArray = []
	var scene := current_scene
	if scene != null and scene.get_script() != null:
		names.append(String(scene.get_script().get_global_name()))
	elif scene != null:
		names.append(String(scene.name))
	else:
		names.append("?")
	var win := Rect2(Vector2.ZERO, Vector2(root.size))
	for pn in panel_nodes:
		var node = pn[1]
		if is_instance_valid(node) and (node as Control).is_visible_in_tree() and _win_rect(node).intersection(win).get_area() >= 400.0:
			names.append(String(pn[0]))
	return ">".join(names)


## A control's rect in window pixels: the root's final transform (the stretch to the window and the interface scale) after the
## control's own transform with its canvas layer and any embedded popup it sits in.
func _win_rect(c: Control) -> Rect2:
	return _xf * c.get_screen_transform() * Rect2(Vector2.ZERO, c.size)


## Reads what is on screen: every control a hand could aim at, with its kind and its visible rect in window pixels, plus the board's
## provinces and armies where they stand on screen this frame. With a focus, an area hidden in a scroll gives that scroll a way there.
func _read_screen() -> void:
	targets.clear()
	drops.clear()
	panel_nodes.clear()
	_reveal.clear()
	_xf = root.get_final_transform()
	var win := Rect2(Vector2.ZERO, Vector2(root.size))
	for c in root.get_children():
		_walk(c, win, [], null, false)
	for w in root.get_embedded_subwindows():
		if w.visible and w != root and w.get_class() != "TooltipPanel":
			var wr := Rect2(_xf * Vector2(w.position), Vector2(w.size) * _xf.get_scale())
			_add("window", wr.intersection(win), w, "%s %s" % [w.get_class(), w.name], 6.0, false, false)
	_add_board(win)
	for id in _reveal:
		var rv: Dictionary = _reveal[id]
		if is_instance_valid(rv.node):
			_add("reveal", _win_rect(rv.node).intersection(win), rv.node, "%s toward %s (%s)" % [_label(rv.node, ""), rv.what,
				"down" if int(rv.dir) > 0 else "up"], 10.0, false, true, int(rv.dir))


func _walk(n: Node, clip: Rect2, areas: Array, scroll: ScrollContainer, hidden: bool) -> void:
	if (n is CanvasItem and not (n as CanvasItem).visible) or (n is CanvasLayer and not (n as CanvasLayer).visible):
		return
	if n is Viewport or n is Node3D:
		return  # embedded popups are read on their own (above); a SubViewport's 3D world holds no controls
	var tags := areas
	var cls := ""
	if n.get_script() != null:
		cls = String(n.get_script().get_global_name())
	if not cls.is_empty():
		for area in focus:
			if FOCUS.has(area) and FOCUS[area].has(cls) and not tags.has(area):
				tags = tags.duplicate()
				tags.append(area)
	var c := n as Control
	if c != null:
		var r := _win_rect(c)
		var vis := Rect2() if hidden else r.intersection(clip)
		if not hidden and (PANELS.has(cls) or PANEL_NAMES.has(String(n.name))):
			panel_nodes.append([cls if PANELS.has(cls) else String(n.name), c])
		if tags != areas and scroll != null and (hidden or not clip.encloses(r)):
			_note_reveal(scroll, r, cls)
		if not hidden and vis.size.x >= 4.0 and vis.size.y >= 4.0 and c.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			_classify(c, vis, cls, tags)
		if c.clip_contents:
			clip = vis
			if vis.size.x <= 0.0 or vis.size.y <= 0.0:
				hidden = true
		if c is ScrollContainer:
			scroll = c
	if hidden and focus.is_empty():
		return  # nothing to look for out of view
	for k in n.get_children():
		_walk(k, clip, tags, scroll, hidden)


## A focused area at `r` is in `scroll` but out of its view: wheel that way (down when it is below).
func _note_reveal(scroll: ScrollContainer, r: Rect2, cls: String) -> void:
	var id := scroll.get_instance_id()
	if _reveal.has(id) or not scroll.is_visible_in_tree():
		return
	var view := _win_rect(scroll)
	var dir := 0
	if r.end.y > view.end.y + 4.0:
		dir = 1
	elif r.position.y < view.position.y - 4.0:
		dir = -1
	if dir != 0:
		_reveal[id] = {"node": scroll, "dir": dir, "what": cls}


func _denied(c: Control) -> bool:
	var nm := String(c.name)
	if DENY_NAMES.has(nm):
		return true
	if DENY_UNDER.has(nm):
		var p := c.get_parent()
		while p != null:
			if p.get_script() != null and String(p.get_script().get_global_name()) == DENY_UNDER[nm]:
				return true
			p = p.get_parent()
	return false


func _classify(c: Control, vis: Rect2, cls: String, tags: Array) -> void:
	if _denied(c):
		return
	var words := _words(c)
	var w := 1.0
	var way := false
	for area in focus:
		if area == "battles" and not (c is BaseButton):
			continue  # the way to a battle is a button (March, Watch the battles), not the hint that mentions one
		if OPENERS.has(area):
			for o in OPENERS[area]:
				if words.contains(o):
					way = true
					w *= 3.0
					break
	if focus.has("battles") and c is BaseButton and String(c.get("text")).strip_edges() == "March":
		w *= 4.0  # the way into a battle above all: march the army you selected
	if c.has_method("_can_drop_data"):
		drops.append({"rect": vis, "what": _label(c, cls)})
	var kind := ""
	if c is Board3D:
		kind = "board"
		w *= 10.0
	elif c is BaseButton:
		kind = "button"
		w *= 0.3 if (c as BaseButton).disabled else 4.0
	elif c is LineEdit or c is TextEdit:
		kind = "text"
		w *= 0.5
	elif c is Range:
		kind = "range"
	elif c is ScrollContainer or c is ItemList or c is Tree or c is RichTextLabel:
		kind = "scroll"
	elif c is TabBar:
		kind = "tabs"
		w *= 2.0
	elif c.has_method("_get_drag_data") or c.get("drag_data") is Callable and (c.get("drag_data") as Callable).is_valid():
		kind = "drag"
		w *= 3.0
	elif c.mouse_filter == Control.MOUSE_FILTER_STOP and (not c.tooltip_text.is_empty() or c.has_method("_gui_input")):
		kind = "hot"
		w *= 1.5
	elif not c.tooltip_text.is_empty():
		kind = "tip"
		w *= 0.6
	if kind.is_empty():
		return
	_add(kind, vis, c, _label(c, cls), w, not tags.is_empty(), way)


func _add(kind: String, rect: Rect2, node: Node, what: String, w: float, area: bool, way: bool, dir: int = 0) -> void:
	if rect.size.x < 2.0 or rect.size.y < 2.0:
		return
	targets.append({"kind": kind, "rect": rect, "node": node, "what": what, "w": w, "area": area, "way": way, "dir": dir})


## The provinces and armies the board shows, where they stand on screen this frame.
func _add_board(win: Rect2) -> void:
	var g := _game()
	if g == null or g.map == null:
		return
	var b = g.map.board
	if b == null or not (b is Control) or not (b as Control).is_visible_in_tree() or not bool(b.get("prepared")):
		return
	var xf: Transform2D = _xf * (b as Control).get_screen_transform()
	var st: GameState = g.map.state
	if st == null:
		return
	var mine := String(g.map.viewing_faction_id)
	var inner := win.grow(-8.0)
	for p in st.provinces:
		if not MapLayout.has_position(p.id):
			continue
		var local: Vector2 = b.project(MapLayout.position_of(p.id))
		if local.x < -99990:
			continue
		var s := xf * local
		if inner.has_point(s):
			var lead := focus.has("fort") and p.owner == mine
			_add("board_province", Rect2(s - Vector2(10, 10), Vector2(20, 20)), b, "province %s (%s)" % [p.id, p.owner], 1.2 * (3.0 if lead else 1.0),
				false, lead)
			targets.back()["pid"] = String(p.id)
	for a in st.armies:
		var r: Rect2 = b.army_rect(a.id)
		if r.size.x <= 0.0:
			continue
		var sr := (xf * r).intersection(win)
		var lead := (focus.has("muster") and a.owner == mine) or (focus.has("battles"))
		var w := 2.0 * (3.0 if lead else 1.0)
		if focus.has("battles") and a.owner != mine and not focus.has("muster"):
			w = 3.0  # with battles, your own armies first (select one, then March), the others less
		_add("board_army", sr, b, "army %s (%s, %d units)" % [a.id, a.owner, a.units.size()], w, false, lead)


## A province on screen next to the selected army's (where its March can go), or {}.
func _march_target() -> Dictionary:
	var g := _game()
	if g == null or g.map == null or g.map.state == null:
		return {}
	var st: GameState = g.map.state
	var a := st.find_army(String(g.map.selected_army_id))
	var here := st.find_province(a.location) if a != null else null
	if here == null:
		return {}
	var near := targets.filter(func(t): return t.kind == "board_province" and here.neighbors.has(String(t.get("pid", ""))))
	return near[rng.randi_range(0, near.size() - 1)] if not near.is_empty() else {}


func _words(c: Control) -> String:
	var t := String(c.name)
	if c.get("text") is String:
		t += " " + String(c.get("text"))
	t += " " + c.tooltip_text.get_slice("\n", 0)
	return t.to_lower()


func _label(c: Control, cls: String) -> String:
	var text := ""
	if c.get("text") is String:
		text = String(c.get("text")).replace("\n", " ").left(40)
	var path := String(current_scene.get_path_to(c)) if current_scene != null and current_scene.is_ancestor_of(c) else String(c.get_path())
	return "%s%s \"%s\" [%s]" % [c.get_class(), ("/" + cls) if not cls.is_empty() else "", text, path.right(90)]


func _describe(c: Control) -> String:
	if c == null:
		return "nothing"
	if not c.is_inside_tree():
		return "%s \"%s\" (out of the tree)" % [c.get_class(), c.name]
	var cls := String(c.get_script().get_global_name()) if c.get_script() != null else ""
	return _label(c, cls)


## A pick weighted by each target's weight. With a focus: while the area is on screen the hand aims inside it more than half the
## time; while it isn't, it takes a way there (a button that opens it, your army or province on the board, a scroll toward it) often.
func _pick_target() -> Dictionary:
	if targets.is_empty():
		return {}
	var pool := targets
	if not focus.is_empty():
		var inside := targets.filter(func(t): return t.area)
		if not inside.is_empty():
			if rng.randf() < 0.55:
				pool = inside
		else:
			var ways := targets.filter(func(t): return t.way)
			if not ways.is_empty() and rng.randf() < 0.45:
				pool = ways
	var total := 0.0
	for t in pool:
		total += float(t.w)
	var x := rng.randf() * total
	for t in pool:
		x -= float(t.w)
		if x <= 0.0:
			return t
	return pool.back()


func _point_in(r: Rect2, anywhere: bool) -> Vector2:
	if anywhere or r.size.x < 12.0 or r.size.y < 12.0:
		return r.position + Vector2(rng.randf(), rng.randf()) * r.size
	# mostly the middle, as a hand aims, sometimes the very edge
	var m := r.size * (0.15 if rng.randf() < 0.85 else 0.02)
	return r.position + m + Vector2(rng.randf(), rng.randf()) * (r.size - m * 2.0)


func _random_point() -> Vector2:
	return Vector2(rng.randf_range(2, root.size.x - 2), rng.randf_range(2, root.size.y - 2))


# --- the hand: every event goes into events.log, then through Input.parse_input_event ----------------------------------

## Moves the pointer to `to` in a few steps. `settle` false: no frame after the last step (the caller reads the hover at once).
func _travel(to: Vector2, what: String, settle: bool = true) -> void:
	var steps := rng.randi_range(1, 5)
	var from := mouse
	for i in steps:
		var last := i == steps - 1
		var p := from.lerp(to, float(i + 1) / steps)
		if not last:
			p += Vector2(rng.randf_range(-6, 6), rng.randf_range(-6, 6))
		_motion(p, what if last else "")
		if (settle or not last) and rng.randf() < 0.75:
			await process_frame


func _motion(p: Vector2, what: String) -> void:
	p = p.clamp(Vector2.ZERO, Vector2(root.size) - Vector2.ONE)
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	e.relative = p - mouse
	e.velocity = (p - mouse) * 60.0
	e.button_mask = mask
	mouse = p
	_send(e, what)


func _button(b: MouseButton, pressed: bool, double: bool, what: String) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = b
	e.pressed = pressed
	e.double_click = double
	e.position = mouse
	e.global_position = mouse
	e.factor = 1.0
	if b in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
		var bit := 1 << (b - 1)
		mask = (mask | bit) if pressed else (mask & ~bit)
	e.button_mask = mask
	_send(e, what)


func _click(p: Vector2, b: MouseButton, double: bool, what: String) -> void:
	last_what = ("double " if double else "right " if b == MOUSE_BUTTON_RIGHT else "") + "click " + what
	await _travel(p, last_what)
	await _press_here(b, double)


## A press and release where the pointer is (twice for a double click).
func _press_here(b: MouseButton, double: bool) -> void:
	if rng.randf() < 0.5:
		await process_frame
	_button(b, true, false, "")
	if rng.randf() < 0.8:
		await process_frame
	_button(b, false, false, "")
	if double:
		await _frames(rng.randi_range(0, 2))
		_button(b, true, true, "")
		await process_frame
		_button(b, false, false, "")
	await process_frame


func _hover(p: Vector2, what: String) -> void:
	last_what = "hover " + what
	await _travel(p, last_what)
	await _frames(rng.randi_range(30, 90))  # long enough for its tooltip


func _drag(from: Vector2, to: Vector2, what: String) -> void:
	last_what = "drag " + what
	await _travel(from, last_what)
	await process_frame
	_button(MOUSE_BUTTON_LEFT, true, false, "")
	await process_frame
	var steps := rng.randi_range(4, 14)
	for i in steps:
		_motion(from.lerp(to, float(i + 1) / steps), "")
		await process_frame
	await _frames(rng.randi_range(0, 4))
	_button(MOUSE_BUTTON_LEFT, false, false, "")
	await process_frame


func _wheel(p: Vector2, ticks: int, up: bool, what: String) -> void:
	last_what = "wheel %s x%d %s" % ["up" if up else "down", ticks, what]
	await _travel(p, last_what)
	for i in ticks:
		var b := MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
		_button(b, true, false, "")
		_button(b, false, false, "")
		if rng.randf() < 0.6:
			await process_frame


## The hand crossing the screen fast, through whatever is there (a card rebuilding under it, #249).
func _sweep(points: int = 0, settle: int = 1) -> void:
	if points <= 0:
		points = rng.randi_range(3, 12)
		last_what = "sweep"
	for i in points:
		_motion(_random_point() if rng.randf() < 0.5 else mouse + Vector2(rng.randf_range(-160, 160), rng.randf_range(-120, 120)),
			"sweep" if i == 0 and settle > 0 else "")
		if rng.randf() < 0.7:
			await process_frame
	await _frames(settle)


func _key(k: Key, pressed: bool, what: String, unicode: int = 0, echo: bool = false) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.unicode = unicode
	e.pressed = pressed
	e.echo = echo
	_send(e, what)


func _tap_key(k: Key, why: String) -> void:
	last_what = "key %s (%s)" % [OS.get_keycode_string(k), why]
	_key(k, true, last_what)
	await _frames(rng.randi_range(1, 4))
	_key(k, false, "")
	await process_frame


func _hold_key(k: Key, frames: int) -> void:
	last_what = "hold %s %d frames" % [OS.get_keycode_string(k), frames]
	_key(k, true, last_what)
	for i in frames:
		await process_frame
		if i % 8 == 7:
			_key(k, true, "", 0, true)
	_key(k, false, "")
	await process_frame


func _type_char() -> void:
	var chars := "abcdefghijklmnopqrstuvwxyz0123456789 "
	var ch := chars[rng.randi_range(0, chars.length() - 1)]
	var k: Key = OS.find_keycode_from_string(ch.to_upper()) if ch != " " else KEY_SPACE
	_key(k, true, "type '%s'" % ch, ch.unicode_at(0))
	await process_frame
	_key(k, false, "")


## Writes the event (flushed: a crash while it is handled leaves its line), then hands it to Input and has it handled at once, as
## the OS's event loop does each frame, then checks the hover Godot keeps.
func _send(e: InputEvent, what: String) -> void:
	events += 1
	if log_file != null:
		log_file.store_line(MonkeyLog.event_line(frame_n, e, what, _screen()))
		log_file.flush()
	Input.parse_input_event(e)
	Input.flush_buffered_events()
	_hover_check()


## #249's class, caught the moment it happens: a handler the event set off (a mouse_exited) took out of the tree the very control
## the pointer moved onto, and Godot 4.5 still holds it as hovered. It is alive until the end of the frame; the next mouse event
## after that reads it freed and the game dies on signal 11 (Viewport::_drop_mouse_over). The run goes on, so the crash itself shows.
func _hover_check() -> void:
	var h := root.gui_get_hovered_control()
	if h == null:
		_hover_id = 0
		_hover_desc = "nothing"
		return
	if not h.is_inside_tree():
		if h.get_instance_id() != _stale_id:
			_stale_id = h.get_instance_id()
			hover_freed += 1
			_note("HOVER-FREED: Godot holds %s \"%s\" as hovered after it left the tree (the pointer left %s); the next mouse event after it is freed reads freed memory, #249's class [after %s]" % [
				h.get_class(), h.name, _hover_desc, last_what])
		return
	if h.get_instance_id() != _hover_id:
		_hover_id = h.get_instance_id()
		_hover_desc = _describe(h)


# --- --replay ---------------------------------------------------------------------------------------------------------

## The events of a log, each sent again on the frame it was sent on, with the screen it lands on logged anew.
func _replay() -> void:
	var f := FileAccess.open(replay_path, FileAccess.READ)
	if f == null:
		_note("cannot read the replay %s" % replay_path)
		verdict = "no_replay"
		return
	while not f.eof_reached():
		var ev := MonkeyLog.parse_event_line(f.get_line())
		if ev.is_empty():
			continue
		while frame_n < int(ev.frame):
			await process_frame
		var e := MonkeyLog.decode(ev.event, mouse)
		if e == null:
			continue
		if not String(ev.what).is_empty():
			last_what = String(ev.what)
			_read_screen()  # the panels up, for the log
		mouse = MonkeyLog.pointer_after(ev.event, mouse)
		_send(e, String(ev.what))
		var why := _stop_reason()
		if why == "stuck" or why == "left_game":
			verdict = why
			return
		if not _pending_shot.is_empty():
			var n := _pending_shot
			_pending_shot = ""
			await _shot(n)
	await _frames(60)
	verdict = "replayed"


# --- bookkeeping ----------------------------------------------------------------------------------------------------

func _on_frame() -> void:
	frame_n += 1
	var now := Time.get_ticks_usec()
	if _last_usec > 0:
		var ms := (now - _last_usec) / 1000.0
		if ms > slow_ms and started_msec > 0:
			slow.append({"frame": frame_n, "ms": int(ms), "after": last_what, "turn": _turn()})
			_note("SLOW frame %d: %d ms after %s%s%s" % [frame_n, int(ms), last_what, MonkeyLog.SEP, _screen()])
	_last_usec = now
	if frame_n % 300 == 0:
		_keep_off_the_cursor()
	if qa_logger != null:
		for err in qa_logger.take():
			var s := String(err)
			if s.begins_with("WARNING"):
				warnings += 1
				if s.contains("LOD bias"):
					continue  # the Metal driver's note at start, on every run
			else:
				errors += 1
				if s.contains("res://tools/qa/"):
					own_errors += 1
					s += " (the monkey's own)"
			_note("%s  [after %s%s%s]" % [s, last_what, MonkeyLog.SEP, _screen()])


## The real cursor must not sit over the window: Godot sends its own motion at the real cursor (after a drop, or when a hovered
## control's cursor shape changes), which would move the hover under the hand (tests/muster_input_probe.gd does the same).
func _keep_off_the_cursor() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var cur := DisplayServer.mouse_get_position()
	var size := DisplayServer.window_get_size()
	var pos := DisplayServer.window_get_position()
	if not Rect2i(pos, size).grow(20).has_point(cur):
		return
	var area := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	for t in [Vector2i(pos.x, cur.y + 40), Vector2i(pos.x, cur.y - size.y - 40), Vector2i(cur.x + 40, pos.y), Vector2i(cur.x - size.x - 40, pos.y)]:
		if area.encloses(Rect2i(t, size)):
			DisplayServer.window_set_position(t)
			_note("the window moved off the real cursor, to %s" % t)
			return
	# no room on the screen beside the cursor: past its edge, where the window still draws whole
	var t := Vector2i(pos.x, cur.y + 40) if cur.y < area.get_center().y else Vector2i(pos.x, cur.y - size.y - 40)
	DisplayServer.window_set_position(t)
	_note("the window moved off the real cursor, partly off the screen, to %s" % t)


func _note(text: String) -> void:
	print("monkey: ", text)
	if log_file != null:
		log_file.store_line(MonkeyLog.note_line(frame_n, text))
		log_file.flush()


func _frames(n: int) -> void:
	for k in n:
		await process_frame


func _shot(name: String) -> void:
	await process_frame
	var img := root.get_texture().get_image()
	if img == null:
		return
	shots += 1
	var file := "f%06d_%s.jpg" % [frame_n, name.validate_filename()]
	img.save_jpg(out.path_join("shots").path_join(file), 0.9)
	_note("shot %s%s%s" % [file, MonkeyLog.SEP, _screen()])


func _finish(how: String) -> void:
	var g := _game()
	var summary := {"verdict": how, "seed": seed_n, "human": human, "config_seed": config.get("seed", 0), "turn": _turn(),
		"over": g != null and g.session != null and g.session.is_over(), "gestures": gestures, "events": events, "errors": errors,
		"own_errors": own_errors, "warnings": warnings, "hover_freed": hover_freed, "aim_check": aim_checked, "shots": shots,
		"minutes": snappedf((Time.get_ticks_msec() - started_msec) / 60000.0, 0.01) if started_msec > 0 else 0.0, "frames": frame_n,
		"window": [root.size.x, root.size.y], "ui_scale": ui_scale, "fog": fog, "focus": ",".join(focus), "build": build,
		"replay": replay_path, "slow_frames": slow.size(), "slowest": _slowest(10), "screens": screens_seen.keys()}
	var f := FileAccess.open(out.path_join("summary.json"), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(summary, "  ") + "\n")
		f.close()
	_note("MONKEY END %s: turn %d, %d gestures, %d events, %d errors (%d the monkey's own), %d hover-freed, %d slow frames" % [how, _turn(),
		gestures, events, errors, own_errors, hover_freed, slow.size()])
	if log_file != null:
		log_file.close()
		log_file = null
	quit(4 if how == "stuck" else 0)


func _slowest(n: int) -> Array:
	var s := slow.duplicate()
	s.sort_custom(func(a, b): return int(a.ms) > int(b.ms))
	return s.slice(0, n)
