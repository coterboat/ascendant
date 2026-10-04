extends Control
## A standalone launcher that plays one battle on the 3D stage (M3b, world3d/battle_stage.gd), as
## ui/battle/battle_watch.tscn does for the Simple view: it hosts the stage, the full battle report viewer
## (the result card's Full report) and the codex (right-click or F1 on anything linked).
##
##   godot --path . -- --battle3d --fixture biggest           (world3d/launch.gd opens this scene)
##   godot --path . res://world3d/battle_watch3d.tscn -- --fixture king_falls_wins
##   options: --fixture NAME (a file in tests/fixtures/battles, or path_wings / path_iron_hide /
##            path_lifedrinker / path_red_harvest, fought on the spot by the tests' path fixtures; default
##            starting_plains), --speed 1|2|4, --paused, --reduced-motion, --quit-at-end (prints the frame
##            times, fps and draw calls, then quits)
##
## In code: watch(source, seats = [], report = {}) -> "" or why it can't be watched. `source` is a battle
## event (numbers.log + numbers.report), a fixture-style {"log", "report"}, or a bare log.

signal closed

const Watch := preload("res://ui/battle/battle_watch.gd")
const DEFAULT_FIXTURE := "starting_plains"
const PATH_FIXTURES := "res://tests/battle_playback_fixtures.gd"

var stage: BattleStage3D
var viewer: BattleReportViewer
var codex: Control
var quit_at_end := false
var _seats: Array = []
var _frames := 0
var _frame_ms: Array = []
var _draws: Array = []
var _last_usec := 0


func _init() -> void:
	name = "BattleWatch3D"
	stage = BattleStage3D.new()
	add_child(stage)
	viewer = BattleReportViewer.new()
	add_child(viewer)
	codex = (load("res://ui/codex_panel.tscn") as PackedScene).instantiate()
	codex.visible = false
	add_child(codex)
	stage.closed.connect(_on_stage_closed)
	stage.report_requested.connect(func(e: Dictionary): viewer.show_event(e, null, _seats))
	stage.codex_requested.connect(_open_codex)
	viewer.codex_requested.connect(_open_codex)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if get_tree().current_scene != self:
		return
	var args := OS.get_cmdline_user_args()
	var fixture := DEFAULT_FIXTURE
	var speed := 0
	var paused := false
	for k in args.size():
		var a := String(args[k])
		if a == "--fixture" and k + 1 < args.size():
			fixture = String(args[k + 1])
		elif a.begins_with("--fixture="):
			fixture = a.trim_prefix("--fixture=")
		elif a == "--speed" and k + 1 < args.size():
			speed = int(args[k + 1])
		elif a.begins_with("--speed="):
			speed = int(a.trim_prefix("--speed="))
		elif a == "--paused":
			paused = true
		elif a == "--reduced-motion":
			stage.reduced_motion = true
		elif a == "--quit-at-end":
			quit_at_end = true
	var fx := load_fixture(fixture)
	if fx.is_empty():
		push_warning("There is no battle fixture called %s." % fixture)
		return
	if not watch(fx).is_empty():
		return
	if speed > 0:
		stage.player.set_speed(speed)
	if not paused:
		stage.player.play()
	if quit_at_end:
		stage.player.finished.connect(_report_and_quit.bind(fixture))


func _process(_delta: float) -> void:
	if not quit_at_end:
		return
	var now := Time.get_ticks_usec()
	if _last_usec > 0:
		_frame_ms.append((now - _last_usec) / 1000.0)
		_draws.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	_last_usec = now
	_frames += 1


## Plays `source` on the stage. Returns "" or the plain reason it can't be watched.
func watch(source: Dictionary, seats: Array = [], report: Dictionary = {}) -> String:
	_seats = seats.duplicate()
	viewer.visible = false
	if source.has("numbers"):
		return stage.show_event(source, seats)
	if source.has("log") and source.log is Dictionary:
		return stage.show_battle(source.log, source.get("report", report), seats)
	return stage.show_battle(source, report, seats)


## A stored battle fixture, or one of the tests' path battles, as {"log", "report"} ({} when unknown).
static func load_fixture(fixture_name: String) -> Dictionary:
	if fixture_name.begins_with("path_") and ResourceLoader.exists(PATH_FIXTURES):
		var fixtures: Script = load(PATH_FIXTURES)
		return fixtures.call("battle", fixture_name)
	return Watch.load_fixture(fixture_name)


func _open_codex(key: String) -> void:
	codex.open(key)
	move_child(codex, get_child_count() - 1)


func _on_stage_closed() -> void:
	closed.emit()
	if is_inside_tree() and get_tree().current_scene == self:
		get_tree().quit()


func _report_and_quit(fixture: String) -> void:
	var sorted := _frame_ms.duplicate()
	sorted.sort()
	var p95: float = sorted[int(sorted.size() * 0.95)] if not sorted.is_empty() else 0.0
	var mx: float = sorted[-1] if not sorted.is_empty() else 0.0
	var mean := 0.0
	for v in sorted:
		mean += float(v)
	mean /= maxf(1.0, float(sorted.size()))
	var dsorted := _draws.duplicate()
	dsorted.sort()
	var dmax: int = dsorted[-1] if not dsorted.is_empty() else 0
	var ps := stage.perf_stats()
	print("watched %s in 3D: %d frames, %.1f fps, frame time p95 %.2f ms, max %.2f ms, draw calls max %d, %d figures in %d groups, rung %d" % [
		fixture, _frames, 1000.0 / maxf(mean, 0.001), p95, mx, dmax, int(ps["figures"]), int(ps["groups"]), int(ps["rung"])])
	get_tree().create_timer(0.3).timeout.connect(func(): get_tree().quit())
