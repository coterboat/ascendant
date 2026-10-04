class_name GameSettings
extends RefCounted
## The player's settings, kept in a small ConfigFile (user://settings.cfg by default):
##   window_mode          "windowed" or "fullscreen"
##   ui_scale             100 or 125 (percent): how big the whole interface is drawn
##   auto_watch_battles   false by default. M3-5: "Watch my battles at the start of each turn": the game
##                        screen plays the player's battles (BattleHost) once the turn report has opened,
##                        after the board's playback and any handoff. The battle screen's own settings
##                        (battle view, speed, reduced motion, screen shake) are in [battle] (BattleFx).
##   board                "3d" (default) or "2d": the map as the 3D world (M3a.1, world3d/board3d.gd) or as
##                        the 2D map. The 2D map stays a setting until M3a.1 is accepted.
##   playback_speed       1, 2 or 4: how fast a resolved turn plays out on the 3D board (remembered).
##   master_volume, music_volume, sfx_volume, ambiance_volume
##                        0 to 100 (percent, 100 by default): the Master, Music, SFX and Ambiance buses
##                        (GameAudio). The mix itself lives in assets/audio/audio.json.
##   muted                false by default: true silences everything (the Master bus)
## A missing or unreadable file, or a value this game doesn't know, gives the defaults for those values.
## apply(tree) puts window_mode, ui_scale and the volumes into effect (the title screen does it once at
## start-up, and the settings panel after every change); apply_audio() does the volumes alone (the
## Audio autoload does it as the game starts). Tests pass their own file; tests/runner.gd points
## default_path at a temporary file, so they never touch the real one.

const SECTION := "settings"
const WINDOW_MODES := ["windowed", "fullscreen"]
const WINDOW_MODE_NAMES := ["Windowed", "Fullscreen"]
const UI_SCALES := [100, 125]
const BOARDS := ["3d", "2d"]
const BOARD_NAMES := ["3D world", "2D map"]
const PLAYBACK_SPEEDS := [1, 2, 4]
## Each volume setting and the bus it sets.
const VOLUME_BUSES := {"master_volume": "Master", "music_volume": "Music", "sfx_volume": "SFX", "ambiance_volume": "Ambiance"}
const VOLUME_NAMES := {"master_volume": "Master", "music_volume": "Music", "sfx_volume": "Effects", "ambiance_volume": "Ambiance"}

static var default_path := "user://settings.cfg"
static var _applied_at_start := false

var path := ""
var window_mode := "windowed"
var ui_scale := 100
var auto_watch_battles := false
var board := "3d"
var playback_speed := 1
var master_volume := 100
var music_volume := 100
var sfx_volume := 100
var ambiance_volume := 100
var muted := false


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
	var board_value = cfg.get_value(SECTION, "board", "3d")
	if board_value is String and BOARDS.has(board_value):
		settings.board = board_value
	var speed_value = cfg.get_value(SECTION, "playback_speed", 1)
	if (speed_value is int or speed_value is float) and PLAYBACK_SPEEDS.has(int(speed_value)):
		settings.playback_speed = int(speed_value)
	for key in VOLUME_BUSES:
		var v = cfg.get_value(SECTION, key, 100)
		if (v is int or v is float) and v >= 0 and v <= 100:
			settings.set(key, int(v))
	var mute = cfg.get_value(SECTION, "muted", false)
	if mute is bool:
		settings.muted = mute
	return settings


## Writes the settings to their file. Returns "" or why they could not be saved.
func save() -> String:
	var cfg := ConfigFile.new()
	# Keep the file's other sections (the battle screen's [battle] settings, M3-4); a broken file is rewritten.
	if FileAccess.file_exists(path):
		cfg.load(path)
	cfg.set_value(SECTION, "window_mode", window_mode)
	cfg.set_value(SECTION, "ui_scale", ui_scale)
	cfg.set_value(SECTION, "auto_watch_battles", auto_watch_battles)
	cfg.set_value(SECTION, "board", board)
	cfg.set_value(SECTION, "playback_speed", playback_speed)
	for key in VOLUME_BUSES:
		cfg.set_value(SECTION, key, int(get(key)))
	cfg.set_value(SECTION, "muted", muted)
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


func set_board(value: String) -> bool:
	if not BOARDS.has(value):
		return false
	board = value
	return true


func set_playback_speed(value: int) -> bool:
	if not PLAYBACK_SPEEDS.has(value):
		return false
	playback_speed = value
	return true


## Sets one volume (a VOLUME_BUSES key) to `percent`, kept within 0 to 100. False for an unknown key.
func set_volume(key: String, percent: int) -> bool:
	if not VOLUME_BUSES.has(key):
		return false
	set(key, clampi(percent, 0, 100))
	return true


func volume(key: String) -> int:
	return int(get(key)) if VOLUME_BUSES.has(key) else 0


## The bus level for a volume setting: 0% is silent, 100% is 0 dB, and in between the square of the
## fraction (50% is about -12 dB), which sounds closer to "half as loud" than a straight line.
static func volume_db(percent: int) -> float:
	if percent <= 0:
		return -80.0
	var x := clampi(percent, 0, 100) / 100.0
	return linear_to_db(x * x)


## Puts the volumes and the mute into effect on the audio buses (adding any bus the layout lacks).
func apply_audio() -> void:
	GameAudio.ensure_buses()
	for key in VOLUME_BUSES:
		var bus := AudioServer.get_bus_index(String(VOLUME_BUSES[key]))
		if bus == -1:
			continue
		var percent := volume(key)
		AudioServer.set_bus_volume_db(bus, volume_db(percent))
		AudioServer.set_bus_mute(bus, percent <= 0 or (muted and key == "master_volume"))


## Puts the window mode, the interface scale and the volumes into effect. The window mode is left alone
## in a headless run, where there is no window.
func apply(tree: SceneTree) -> void:
	apply_audio()
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
