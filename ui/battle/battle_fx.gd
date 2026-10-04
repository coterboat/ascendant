class_name BattleFx
extends RefCounted
## The rules every battle renderer applies to its effects, whatever it draws with (M3-3, #58;
## design/M3_BATTLES.md §4.4, §4.5, §7.4; design/3D_DIRECTION.md §7.5): the flash limiter, the screen-shake
## spacing, effect pools, and the battle settings. Pure (no nodes), so the 2D Simple view and the 3D stage
## share them and tests check them without a screen. All times here are real seconds, never the playback
## clock, so 4x can't make the screen flash or jitter faster.
##
##   BattleFx.settings(path = "")   the [battle] section of the settings file: {"reduced_motion" (false),
##                                  "screen_shake" (true), "speed" (1)}. A missing or broken file, or a value
##                                  this game doesn't know, gives the defaults, with no error (§6).
##   BattleFx.FlashLimiter          at most MAX_FLASHES bright-frame starts per rolling FLASH_WINDOW (§7.4,
##                                  WCAG 2.3.1); an impact over the limit plays without its bright frames
##   BattleFx.ShakeLimiter          at least SHAKE_SPACING between shakes; one that comes too soon is dropped
##   BattleFx.Pool                  a fixed number of live effects; a full pool skips the new one (§4.4)

## §7.4: at most 3 bright-frame starts per rolling second, anywhere on screen.
const MAX_FLASHES := 3
const FLASH_WINDOW := 1.0
## Bible §2.5: an impact stays above 80% opacity for at most 2 frames.
const BRIGHT_FRAMES := 2
## §4.5: at least 0.75 s of real time between shakes.
const SHAKE_SPACING := 0.75
## §4.4's pools.
const MAX_IMPACTS := 48
const MAX_PROJECTILES := 96
const MAX_NUMBERS := 32
const SECTION := "battle"
const DEFAULTS := {"reduced_motion": false, "screen_shake": true, "speed": 1}


## The battle settings from the game's settings file (GameSettings.default_path unless `path` is given).
static func settings(path: String = "") -> Dictionary:
	var out := DEFAULTS.duplicate()
	var file := path if not path.is_empty() else GameSettings.default_path
	var cfg := ConfigFile.new()
	if not FileAccess.file_exists(file) or cfg.load(file) != OK:
		return out
	var rm = cfg.get_value(SECTION, "reduced_motion", false)
	if rm is bool:
		out.reduced_motion = rm
	var shake = cfg.get_value(SECTION, "screen_shake", true)
	if shake is bool:
		out.screen_shake = shake
	var sp = cfg.get_value(SECTION, "speed", 1)
	if (sp is int or sp is float) and BattlePlayer.SPEEDS.has(int(sp)):
		out.speed = int(sp)
	return out


## Counts bright-frame starts in a rolling window of real time.
class FlashLimiter extends RefCounted:
	var _starts: Array = []  # real times of the bright-frame starts in the window

	## True (and counted) when an effect may start its bright frames at real time `now`.
	func allow(now: float) -> bool:
		while not _starts.is_empty() and now - float(_starts[0]) >= BattleFx.FLASH_WINDOW:
			_starts.pop_front()
		if _starts.size() >= BattleFx.MAX_FLASHES:
			return false
		_starts.append(now)
		return true

	## Bright-frame starts in the window ending at `now`.
	func count(now: float) -> int:
		return _starts.filter(func(t): return now - float(t) < BattleFx.FLASH_WINDOW).size()

	func reset() -> void:
		_starts.clear()


## Keeps shakes at least SHAKE_SPACING apart in real time; switched off with reduced motion, by the
## screen-shake setting, and while paused or scrubbing (the caller doesn't ask then).
class ShakeLimiter extends RefCounted:
	var enabled := true
	var _last := -1000.0

	func allow(now: float) -> bool:
		if not enabled or now - _last < BattleFx.SHAKE_SPACING:
			return false
		_last = now
		return true

	func reset() -> void:
		_last = -1000.0


## A fixed number of live effects. add() returns false (and drops the effect) when the pool is full.
class Pool extends RefCounted:
	var cap := 0
	var items: Array = []

	func _init(capacity: int = 0) -> void:
		cap = capacity

	func add(item: Dictionary) -> bool:
		if items.size() >= cap:
			return false
		items.append(item)
		return true

	## Ages every item by `dt` ("age" against "life") and drops the finished ones.
	func age(dt: float) -> void:
		if items.is_empty():
			return
		var keep := []
		for it in items:
			it.age = float(it.age) + dt
			if float(it.age) < float(it.life):
				keep.append(it)
		items = keep

	func clear() -> void:
		items.clear()

	func size() -> int:
		return items.size()
