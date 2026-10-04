extends Control
## A standalone launcher that plays one battle in the Simple view (M3-3, #58), for testing and playtests.
## The game itself opens battles through BattleHost (M3-5: Watch on the turn report and in the battle report
## viewer, Watch your battles, auto-watch). It hosts the view, the full battle report viewer (the result
## card's Full report, whose Watch plays the battle again) and the codex (right-click or F1 on anything
## linked).
##
##   godot --path . res://ui/battle/battle_watch.tscn -- --fixture king_falls_wins
##   options: --fixture NAME (a file in tests/fixtures/battles; default starting_plains), --speed 1|2|4,
##            --paused, --reduced-motion, --no-art (every portrait and the ground as their placeholders,
##            to check the view works with no art at all), --quit-at-end (prints how it ran, then quits)
##
## In code: watch(source, seats = [], report = {}) -> "" or why it can't be watched. `source` is a battle
## event (numbers.log + numbers.report), a fixture-style {"log", "report"}, or a bare log.

signal closed

const FIXTURE_DIR := "res://tests/fixtures/battles"
const DEFAULT_FIXTURE := "starting_plains"

var view: BattleSimpleView
var viewer: BattleReportViewer
var codex: Control
var quit_at_end := false
var _seats: Array = []
var _frames := 0
var _frame_ms: Array = []
var _last_usec := 0


func _init() -> void:
	name = "BattleWatch"
	view = BattleSimpleView.new()
	add_child(view)
	viewer = BattleReportViewer.new()
	viewer.z_index = BattleHost.OVER_Z  # above the view's result card and legend (M3-5)
	add_child(viewer)
	codex = (load("res://ui/codex_panel.tscn") as PackedScene).instantiate()
	codex.visible = false
	codex.z_index = BattleHost.OVER_Z
	add_child(codex)
	view.closed.connect(_on_view_closed)
	view.report_requested.connect(func(e: Dictionary): viewer.show_event(e, null, _seats))
	view.codex_requested.connect(_open_codex)
	viewer.codex_requested.connect(_open_codex)
	viewer.watch_requested.connect(func(e: Dictionary):
		viewer.close()
		watch(e, _seats))


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if get_tree().current_scene != self:
		return
	# Run on its own: play a fixture from the command line.
	var args := OS.get_cmdline_user_args()
	var fixture := DEFAULT_FIXTURE
	var speed := 0
	var paused := false
	var no_art := false
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
		elif a == "--no-art":
			no_art = true
		elif a == "--reduced-motion":
			view.reduced_motion = true
		elif a == "--quit-at-end":
			quit_at_end = true
	var fx := load_fixture(fixture)
	if fx.is_empty():
		push_warning("There is no battle fixture called %s." % fixture)
		return
	var problem := watch(fx)
	if not problem.is_empty():
		return
	if no_art:
		show_without_art()
	if speed > 0:
		view.player.set_speed(speed)
	if not paused:
		view.player.play()
	if quit_at_end:
		view.player.finished.connect(_report_and_quit.bind(fixture))


func _process(_delta: float) -> void:
	if not quit_at_end:
		return
	var now := Time.get_ticks_usec()
	if _last_usec > 0:
		_frame_ms.append((now - _last_usec) / 1000.0)
	_last_usec = now
	_frames += 1


## Plays `source` in the view. Returns "" or the plain reason it can't be watched.
func watch(source: Dictionary, seats: Array = [], report: Dictionary = {}) -> String:
	_seats = seats.duplicate()
	viewer.visible = false
	if source.has("numbers"):
		return view.show_event(source, seats)
	if source.has("log") and source.log is Dictionary:
		return view.show_battle(source.log, source.get("report", report), seats)
	return view.show_battle(source, report, seats)


## A stored battle fixture as {"log", "report"} (the log normalised as the resolver wrote it), or {}.
static func load_fixture(fixture_name: String) -> Dictionary:
	var path := "%s/%s.json" % [FIXTURE_DIR, fixture_name]
	if not FileAccess.file_exists(path):
		return {}
	var fx = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (fx is Dictionary) or not (fx.get("log") is Dictionary):
		return {}
	var parsed := BattleLog.from_json(JSON.stringify(fx.log, "", false))
	return {"log": parsed.log, "report": fx.get("report", {})}


## Shows every card and the ground with their placeholders, as if no art had landed (§9.3).
func show_without_art() -> void:
	for c in view.cards_layer.get_children():
		(c as BattleCard).texture = null
		c.queue_redraw()
	view.backdrop.clear_art()


func _open_codex(key: String) -> void:
	codex.open(key)
	move_child(codex, get_child_count() - 1)


func _on_view_closed() -> void:
	closed.emit()
	if is_inside_tree() and get_tree().current_scene == self:
		get_tree().quit()


func _report_and_quit(fixture: String) -> void:
	var sorted := _frame_ms.duplicate()
	sorted.sort()
	var p95: float = sorted[int(sorted.size() * 0.95)] if not sorted.is_empty() else 0.0
	var mx: float = sorted[-1] if not sorted.is_empty() else 0.0
	print("watched %s: %d frames, frame time p95 %.2f ms, max %.2f ms" % [fixture, _frames, p95, mx])
	get_tree().create_timer(0.3).timeout.connect(func(): get_tree().quit())
