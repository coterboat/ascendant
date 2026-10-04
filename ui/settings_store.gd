class_name GameSettings
extends RefCounted
## The player's settings, kept in a small ConfigFile (user://settings.cfg by default):
##   window_mode          "windowed" or "fullscreen"
##   ui_scale             100 or 125 (percent): how big the whole interface is drawn
##   auto_watch_battles   false by default. Stored now for milestone 3, when battles play out on screen:
##                        then each battle of a turn will play by itself as the report opens.
## A missing or unreadable file, or a value this game doesn't know, gives the defaults for those values.
## apply(tree) puts window_mode and ui_scale into effect (the title screen does it once at start-up,
## and the settings panel after every change). Tests pass their own file; tests/runner.gd points
## default_path at a temporary file, so they never touch the real one.

const SECTION := "settings"
const WINDOW_MODES := ["windowed", "fullscreen"]
const WINDOW_MODE_NAMES := ["Windowed", "Fullscreen"]
const UI_SCALES := [100, 125]

static var default_path := "user://settings.cfg"
static var _applied_at_start := false

var path := ""
var window_mode := "windowed"
var ui_scale := 100
var auto_watch_battles := false


func _init(file_path: String = "") -> void:
	path = file_path if not file_path.is_empty() else default_path


## The settings saved at `file_path` (default_path when empty); the defaults for anything missing.
static func load_from(file_path: String = "") -> GameSettings:
	var settings := GameSettings.new(file_path)
	var cfg := ConfigFile.new()
	if cfg.load(settings.path) != OK:
		return settings
	var mode = cfg.get_value(SECTION, "window_mode", "windowed")
	if mode is String and WINDOW_MODES.has(mode):
		settings.window_mode = mode
	var scale = cfg.get_value(SECTION, "ui_scale", 100)
	if (scale is int or scale is float) and UI_SCALES.has(int(scale)):
		settings.ui_scale = int(scale)
	var watch = cfg.get_value(SECTION, "auto_watch_battles", false)
	if watch is bool:
		settings.auto_watch_battles = watch
	return settings


## Writes the settings to their file. Returns "" or why they could not be saved.
func save() -> String:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "window_mode", window_mode)
	cfg.set_value(SECTION, "ui_scale", ui_scale)
	cfg.set_value(SECTION, "auto_watch_battles", auto_watch_battles)
	var folder := path.get_base_dir()
	if not folder.is_empty() and not DirAccess.dir_exists_absolute(folder):
		DirAccess.make_dir_recursive_absolute(folder)
	return "" if cfg.save(path) == OK else "Your settings could not be saved."


func set_window_mode(mode: String) -> bool:
	if not WINDOW_MODES.has(mode):
		return false
	window_mode = mode
	return true


func set_ui_scale(percent: int) -> bool:
	if not UI_SCALES.has(percent):
		return false
	ui_scale = percent
	return true


## Puts the window mode and the interface scale into effect. The window mode is left alone in a
## headless run, where there is no window.
func apply(tree: SceneTree) -> void:
	if tree == null or tree.root == null:
		return
	tree.root.content_scale_factor = ui_scale / 100.0
	if DisplayServer.get_name() == "headless":
		return
	var want := DisplayServer.WINDOW_MODE_FULLSCREEN if window_mode == "fullscreen" else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != want:
		DisplayServer.window_set_mode(want)


## Applies the saved settings once per run (the title screen calls this when it first appears).
static func apply_saved_once(tree: SceneTree) -> void:
	if _applied_at_start or tree == null:
		return
	_applied_at_start = true
	load_from().apply(tree)
