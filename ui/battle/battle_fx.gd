class_name BattleFx
extends RefCounted
## The rules every battle renderer applies to its effects, whatever it draws with (M3-3, #58;
## design/M3_BATTLES.md §4.4, §4.5, §7.4; design/3D_DIRECTION.md §7.5): the flash limiter, the screen-shake
## spacing, effect pools, and the battle settings. Pure (no nodes), so the 2D Simple view and the 3D stage
## share them and tests check them without a screen. All times here are real seconds, never the playback
## clock, so 4x can't make the screen flash or jitter faster.
##
##   BattleFx.settings(path = "")   the [battle] section of the settings file: {"reduced_motion" (false),
##                                  "screen_shake" (true), "speed" (1), "why_panel_open" (true),
##                                  "legend_open" (false), "first_hint_seen" (false), "view" ("simple": M3-5's
##                                  "Battle view", "simple" or "3d")}. A missing or broken file, or a value this
##                                  game doesn't know, gives the defaults, with no error (§6).
##   BattleFx.save_settings(changes, path = "")   writes those keys into [battle], keeping every other key
##                                  and section of the file (M3-4: the last speed, the why panel and legend
##                                  toggles, the first-visit hint). Returns "" or why it could not be saved.
##   BattleFx.FlashLimiter          at most MAX_FLASHES bright-frame starts per rolling FLASH_WINDOW (§7.4,
##                                  WCAG 2.3.1); an impact over the limit plays without its bright frames
##   BattleFx.ShakeLimiter          at least SHAKE_SPACING between shakes; one that comes too soon is dropped
##   BattleFx.Pool                  a fixed number of live effects; a full pool skips the new one (§4.4)
##   BattleFx.sound_of(beat)        the battle sound cue for a beat (#84's audio.json events), or ""
##   BattleFx.SoundGate             keeps each cue at least SOUND_SPACING apart in real time, so 4x and
##                                  massed rounds don't machine-gun the same sample

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
## The battle's sound cues in assets/audio/audio.json (#84).
const SOUNDS := ["battle_hit", "battle_clash", "battle_miss", "battle_bolt", "battle_javelin", "battle_arcane", "battle_charge",
	"rout_horn", "ruler_death"]
## Real seconds between two plays of the same frequent cue (others: no limit; GameAudio's polyphony and
## cooldowns still apply on top).
const SOUND_SPACING := {"battle_hit": 0.06, "battle_clash": 0.06, "battle_miss": 0.08, "battle_bolt": 0.06, "battle_javelin": 0.06}
## Every CLASH_EVERY-th melee hit (by beat index, never an RNG) sounds as a clash for variety, as does
## any hit Iron Hide or Shield Wall took some of (audio.json: "alternate with battle_hit").
const CLASH_EVERY := 3
const SECTION := "battle"
const DEFAULTS := {"reduced_motion": false, "screen_shake": true, "speed": 1, "why_panel_open": true, "legend_open": false,
	"first_hint_seen": false, "view": "simple"}
## M3-5: the battle views a player can choose ("Battle view"): the Simple view, or the 3D stage on the land
## (BattleHost falls back to the Simple view until the 3D stage is in the game).
const VIEWS := ["simple", "3d"]
## The settings that are true or false (every key of DEFAULTS but the speed).
const _BOOLS := ["reduced_motion", "screen_shake", "why_panel_open", "legend_open", "first_hint_seen"]


## The battle settings from the game's settings file (GameSettings.default_path unless `path` is given).
static func settings(path: String = "") -> Dictionary:
	var out := DEFAULTS.duplicate()
	var file := path if not path.is_empty() else GameSettings.default_path
	var cfg := ConfigFile.new()
	if not FileAccess.file_exists(file) or cfg.load(file) != OK:
		return out
	for key in _BOOLS:
		var v = cfg.get_value(SECTION, key, DEFAULTS[key])
		if v is bool:
			out[key] = v
	var sp = cfg.get_value(SECTION, "speed", 1)
	if (sp is int or sp is float) and BattlePlayer.SPEEDS.has(int(sp)):
		out.speed = int(sp)
	var view = cfg.get_value(SECTION, "view", "simple")
	if view is String and VIEWS.has(view):
		out.view = view
	return out


## Writes `changes` (keys of DEFAULTS; anything else, or a value of the wrong kind, is ignored) into the
## [battle] section of the settings file, keeping the rest of the file as it was. Returns "" or why not.
static func save_settings(changes: Dictionary, path: String = "") -> String:
	var file := path if not path.is_empty() else GameSettings.default_path
	var cfg := ConfigFile.new()
	if FileAccess.file_exists(file):
		cfg.load(file)  # a broken file is simply rewritten
	var wrote := false
	for key in changes:
		var v = changes[key]
		if _BOOLS.has(key) and v is bool:
			cfg.set_value(SECTION, key, v)
			wrote = true
		elif key == "speed" and (v is int or v is float) and BattlePlayer.SPEEDS.has(int(v)):
			cfg.set_value(SECTION, key, int(v))
			wrote = true
		elif key == "view" and v is String and VIEWS.has(v):
			cfg.set_value(SECTION, key, v)
			wrote = true
	if not wrote:
		return ""
	var folder := file.get_base_dir()
	if not folder.is_empty() and not DirAccess.dir_exists_absolute(folder):
		DirAccess.make_dir_recursive_absolute(folder)
	return "" if cfg.save(file) == OK else "Your battle settings could not be saved."


## The sound cue for beat `b` (a BattlePlayer beat), or "" for none. Deterministic: the same beat always
## gives the same cue.
##   attack_started  battle_charge for a side's first Charge attack; battle_bolt / battle_javelin /
##                   battle_arcane when a projectile is released
##   attack_landed   battle_miss for a miss; for a melee or Wings hit, battle_clash when blocked or on every
##                   CLASH_EVERY-th beat index, else battle_hit (a projectile's hit has its release sound)
##   death           ruler_death for a ruler
##   rout            rout_horn
static func sound_of(b: Dictionary) -> String:
	var data: Dictionary = b.get("data", {})
	match String(b.get("kind", "")):
		"attack_started":
			if data.get("first_charge", false):
				return "battle_charge"
			match String(data.get("projectile", "")):
				"bolt":
					return "battle_bolt"
				"javelin":
					return "battle_javelin"
				"arcane":
					return "battle_arcane"
		"attack_landed":
			if not data.get("hit", false):
				return "battle_miss"
			var proj := String(data.get("projectile", ""))
			if proj.is_empty() or proj == "dive":
				if data.get("blocked", false) or int(b.get("i", 0)) % CLASH_EVERY == 0:
					return "battle_clash"
				return "battle_hit"
		"death":
			if data.get("ruler", false):
				return "ruler_death"
		"rout":
			return "rout_horn"
	return ""


## Spaces out repeats of a sound cue in real time (SOUND_SPACING); a repeat that comes too soon is dropped.
class SoundGate extends RefCounted:
	var _last := {}  # cue -> real time of its last play

	func allow(cue: String, now: float) -> bool:
		var gap := float(BattleFx.SOUND_SPACING.get(cue, 0.0))
		if gap > 0.0 and _last.has(cue) and now - float(_last[cue]) < gap:
			return false
		_last[cue] = now
		return true

	func reset() -> void:
		_last.clear()


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
