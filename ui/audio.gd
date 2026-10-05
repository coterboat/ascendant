class_name GameAudio
extends Node
## The game's sound: music, ambiance beds and one-shot effects, every one described by
## res://assets/audio/audio.json (#79: file, bus, mix level, loop, fades, polyphony, cooldown and pitch
## jitter per event). One GameAudio runs as the `Audio` autoload. Screens never hold it: they call the
## static shortcuts below, which do nothing while no audio node is running (tests, tools).
##
##   GameAudio.sfx(event, delay_s = 0.0)  a one-shot effect (ui_click, order_queued, capital_captured, ...)
##   GameAudio.music(event)               crossfade to a music track or sting; "" fades the music out
##   GameAudio.ambiance(event)            crossfade to an ambiance bed; "" fades it out
##   GameAudio.battle(on)                 a battle is on screen: music_battle and amb_battle, with the map
##                                        music ducked under them; battle(false) brings the map back
##   GameAudio.report(events, delay_s)    the turn report's headline cues (report_cues), staggered
##   GameAudio.hush(on)                   M5-2: drop one-shot effects while on (a hotseat fog game's playback)
## The node's own API: play(event, delay_s), play_music(event), set_ambiance(event), push_mood(music,
## ambiance), pop_mood(). Volumes and mute are GameSettings' (master/music/sfx/ambiance, applied to the
## buses by GameSettings.apply_audio).
##
## What it promises:
##   - It never reads or writes game state and never draws from an RNG. Pitch jitter is a hash of the
##     event name and that event's own play counter (jitter_pitch): the same index always gives the
##     same pitch.
##   - Every call is safe headless. Outside the tree (tests), or under the Dummy audio driver (--headless),
##     it keeps its books (history, counters, cooldowns) but starts no players (live() is false).
##   - An unknown event or a missing file warns once, then is ignored.
##   - Buttons click and tick by themselves: every BaseButton that enters the tree is hooked (pressed ->
##     ui_click, pointer enters -> ui_hover), so no screen wires its own. Set the meta "silent" to true
##     on a button to leave it alone.

const MANIFEST_PATH := "res://assets/audio/audio.json"
## The buses audio.json routes to (default_bus_layout.tres has them; ensure_buses adds any missing).
const BUS_NAMES := ["Music", "SFX", "Ambiance"]
## How far the map music sinks under a battle (audio.json: "duck music_map under it").
const DUCK_DB := -14.0
const SILENT_DB := -80.0
## Voices of one effect at once when audio.json gives no max_polyphony; the oldest is cut to make room.
const DEFAULT_POLYPHONY := 3
const HISTORY_SIZE := 200
## The turn report's cues: at most this many, this far apart.
const REPORT_MAX_CUES := 3
const REPORT_GAP_S := 0.7
## Turn report events in the order their cue wins a place: [event type, cue]. "capital" is a captured
## event whose province was a capital.
const REPORT_CUES := [
	["ruler_died", "ruler_death"],
	["capital", "capital_captured"],
	["ruler_arrived", "succession_crown"],
	["sacrificed", "sacrifice"],
	["research_done", "research_complete"],
	["recruited", "recruit"],
	["captured", "march"],
	["army_moved", "march"],
]
const BATTLE_MUSIC := "music_battle"
const BATTLE_AMBIANCE := "amb_battle"
const SILENT_META := &"silent"

## The running audio node (the autoload sets itself here when it enters the tree; tests may set their own).
static var current: GameAudio = null

var manifest_path := MANIFEST_PATH
var events := {}  # event name -> its audio.json entry
var bus_names: Array = []  # from audio.json "buses"
var quiet := false  # true: warnings are only kept in `warnings`, not printed (tests)
var warnings: PackedStringArray = []
var history: Array[String] = []  # the last HISTORY_SIZE cues that played, oldest first
var last_pitch := {}  # event name -> the pitch_scale of its last play
var music_name := ""  # the music track or sting playing (or fading in) now
## M5-2 (§2.9): while true, one-shot effects are dropped (and kept in `hushed_cues`): a hotseat fog game's turn playback
## is silent but for the music and the ambient bed, because the other player is in the room. GameAudio.hush sets it.
var hushed := false
var hushed_cues: Array[String] = []
var ambiance_name := ""

var _loaded := false
var _streams := {}  # event name -> AudioStream, or null when its file is missing
var _counters := {}  # event name -> plays so far (the pitch jitter index)
var _last_ms := {}  # event name -> Time.get_ticks_msec() of its last play (cooldowns)
var _voices := {}  # event name -> Array of AudioStreamPlayer (one-shot effects)
var _tracks: Array = []  # music and ambiance players: {"event", "kind", "player", "base_db", "gain", "target", "rate", "stop_at_zero"}
var _pending: Array = []  # delayed one-shots: {"event", "at"} in _clock seconds
var _moods: Array = []  # push_mood's stack of {"music", "ambiance"}
var _clock := 0.0
var _warned := {}
var _dummy_driver := false  # --headless: nothing can be heard, and stopped playbacks would never be freed


func _init() -> void:
	name = "Audio"
	process_mode = Node.PROCESS_MODE_ALWAYS
	_dummy_driver = AudioServer.get_driver_name() == "Dummy"


func _enter_tree() -> void:
	current = self


func _exit_tree() -> void:
	if current == self:
		current = null
	# Stop and let go of every stream, so no playback outlives the game (it would leak at exit).
	for child in get_children():
		if child is AudioStreamPlayer:
			child.stop()
			child.stream = null
	_tracks.clear()
	_voices.clear()
	_pending.clear()
	_streams.clear()


func _ready() -> void:
	load_manifest()
	ensure_buses(bus_names)
	GameSettings.load_from().apply_audio()
	get_tree().node_added.connect(_on_node_added)
	_hook_buttons(get_tree().root)


# --- static shortcuts (what screens call) ---------------------------------------------------------

static func sfx(event: String, delay_s: float = 0.0) -> void:
	if current != null:
		current.play(event, delay_s)


static func music(event: String) -> void:
	if current != null:
		current.play_music(event)


static func ambiance(event: String) -> void:
	if current != null:
		current.set_ambiance(event)


## M5-2: hushes one-shot effects (`on`) or lets them play again; music and the ambient bed go on (§2.9).
static func hush(on: bool) -> void:
	if current != null:
		current.hushed = on


## A battle on screen (the battle report viewer, later its playback): battle music and bed over the
## ducked map music. battle(false) restores what played before.
static func battle(on: bool) -> void:
	if current == null:
		return
	if on:
		current.push_mood(BATTLE_MUSIC, BATTLE_AMBIANCE)
	else:
		current.pop_mood()


## The headline cues of a turn report's events, staggered from `delay_s`.
static func report(report_events: Array, delay_s: float = 0.0) -> void:
	var cues := report_cues(report_events)
	for i in cues.size():
		sfx(cues[i], delay_s + i * REPORT_GAP_S)


## The cues for a turn report: one per kind of event that happened, most dramatic first (REPORT_CUES),
## at most `max_cues`. Pure: the same events always give the same cues.
static func report_cues(report_events: Array, max_cues: int = REPORT_MAX_CUES) -> Array[String]:
	var seen := {}
	for e in report_events:
		if not e is Dictionary:
			continue
		var kind := String(e.get("type", ""))
		var numbers = e.get("numbers", {})
		if kind == "captured" and numbers is Dictionary and bool(numbers.get("is_capital", false)):
			kind = "capital"
		seen[kind] = true
	var cues: Array[String] = []
	for pair in REPORT_CUES:
		if cues.size() >= max_cues:
			break
		if seen.has(pair[0]) and not cues.has(pair[1]):
			cues.append(pair[1])
	return cues


## The sting for the end of a game: sting_victory when a person at the table won (or nobody but the
## computer played), sting_defeat when the computer beat the only person, and for a draw. "" while the
## game runs.
static func ending_sting(victory: Dictionary, players: Array, computer_seats: Dictionary) -> String:
	if victory.is_empty():
		return ""
	if bool(victory.get("draw", false)):
		return "sting_defeat"
	var winner := String(victory.get("winner", ""))
	var humans := players.filter(func(fid): return not computer_seats.has(fid))
	if humans.is_empty() or humans.has(winner):
		return "sting_victory"
	return "sting_defeat"


## The pitch_scale of play number `index` (0-based) of `event`: 1 +/- `amount`, from an FNV-1a hash of
## the name and the index. No RNG: the same arguments always give the same pitch.
static func jitter_pitch(event: String, index: int, amount: float) -> float:
	if amount <= 0.0:
		return 1.0
	var h := 2166136261
	for byte in ("%s#%d" % [event, index]).to_utf8_buffer():
		h = ((h ^ byte) * 16777619) & 0xFFFFFFFF
	var unit := float(h & 0xFFFF) / 65535.0  # 0..1
	return 1.0 + amount * (unit * 2.0 - 1.0)


## Adds every bus in `names` (and BUS_NAMES) that the layout lacks, each sending to Master.
static func ensure_buses(names: Array = []) -> void:
	for bus in BUS_NAMES + names:
		if AudioServer.get_bus_index(String(bus)) != -1:
			continue
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, String(bus))
		AudioServer.set_bus_send(index, &"Master")


# --- the node's API ------------------------------------------------------------------------------

## Reads audio.json (manifest_path). Returns false, with one warning, when it can't be read.
func load_manifest() -> bool:
	_loaded = true
	events = {}
	bus_names = []
	var text := FileAccess.get_file_as_string(manifest_path) if FileAccess.file_exists(manifest_path) else ""
	var data = JSON.parse_string(text) if not text.is_empty() else null
	if not data is Dictionary or not data.get("events") is Dictionary:
		_warn("manifest", "The sound list %s could not be read, so the game plays no sound." % manifest_path)
		return false
	var base := String(data.get("base", manifest_path.get_base_dir() + "/"))
	for event_name in data.events:
		var e = data.events[event_name]
		if not e is Dictionary or not e.has("file"):
			_warn("bad:" + String(event_name), "The sound '%s' in %s names no file." % [event_name, manifest_path])
			continue
		var entry: Dictionary = e.duplicate()
		entry["path"] = base.path_join(String(e.file))
		events[String(event_name)] = entry
	if data.get("buses") is Dictionary:
		bus_names = data.buses.keys()
	return true


func has_event(event: String) -> bool:
	_ensure_loaded()
	return events.has(event)


## Plays `event`: a one-shot effect now (or after `delay_s`), or, for a Music or Ambiance event, a
## crossfade to it. Returns false when it was skipped: unknown, its file missing, or inside its cooldown.
func play(event: String, delay_s: float = 0.0) -> bool:
	if not _known(event):
		return false
	match String(events[event].get("bus", "")):
		"Music":
			return play_music(event)
		"Ambiance":
			return set_ambiance(event)
	if hushed:  # M5-2: a hotseat fog game's playback
		hushed_cues.append(event)
		return false
	if delay_s > 0.0 and live():
		_pending.append({"event": event, "at": _clock + delay_s})
		return true
	return _play_now(event)


## Crossfades to the music track or sting `event` ("" fades the music out). Clears any battle mood:
## a screen that picks its own music owns it from now on.
func play_music(event: String) -> bool:
	_moods.clear()
	return _switch("music", event, false)


func set_ambiance(event: String) -> bool:
	_moods.clear()
	return _switch("ambiance", event, false)


## Changes the music and the bed for a while (a battle). The music playing now ducks under the new one
## and keeps its place; pop_mood() brings it back up.
func push_mood(music_event: String, ambiance_event: String) -> void:
	_moods.push_back({"music": music_name, "ambiance": ambiance_name})
	_switch("music", music_event, true)
	_switch("ambiance", ambiance_event, false)


func pop_mood() -> void:
	if _moods.is_empty():
		return
	var m: Dictionary = _moods.pop_back()
	_switch("music", String(m.music), false)
	_switch("ambiance", String(m.ambiance), false)


func in_mood() -> bool:
	return not _moods.is_empty()


## True when sounds really start: in the tree, with a real audio driver.
func live() -> bool:
	return is_inside_tree() and not _dummy_driver


## How many times `event` has played (its next pitch jitter index).
func play_count(event: String) -> int:
	return int(_counters.get(event, 0))


# --- inside ---------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_clock += delta
	if not _pending.is_empty():
		var due := _pending.filter(func(p): return float(p.at) <= _clock)
		if not due.is_empty():
			_pending = _pending.filter(func(p): return float(p.at) > _clock)
			for p in due:
				_play_now(String(p.event))
	for t in _tracks.duplicate():
		var player: AudioStreamPlayer = t.player
		if not is_instance_valid(player):
			_tracks.erase(t)
			continue
		if not is_equal_approx(float(t.gain), float(t.target)):
			t.gain = move_toward(float(t.gain), float(t.target), float(t.rate) * delta)
			_apply_gain(t)
		if (t.stop_at_zero and float(t.gain) <= 0.0) or not player.playing:
			_drop(t)


func _ensure_loaded() -> void:
	if not _loaded:
		load_manifest()


func _known(event: String) -> bool:
	_ensure_loaded()
	if events.has(event):
		return true
	_warn("unknown:" + event, "There is no sound called '%s' in %s." % [event, manifest_path])
	return false


func _play_now(event: String) -> bool:
	var e: Dictionary = events[event]
	var now := Time.get_ticks_msec()
	var cooldown := int(e.get("cooldown_ms", 0))
	if cooldown > 0 and _last_ms.has(event) and now - int(_last_ms[event]) < cooldown:
		return false
	var stream := _stream(event)
	if stream == null:
		return false
	_last_ms[event] = now
	var index := play_count(event)
	_counters[event] = index + 1
	var pitch := jitter_pitch(event, index, float(e.get("pitch_jitter", 0.0)))
	last_pitch[event] = pitch
	_remember(event)
	if not live():
		return true
	var player := _voice(event, e)
	player.stream = stream
	player.volume_db = float(e.get("volume_db", 0.0))
	player.pitch_scale = pitch
	player.play()
	return true


## A free player for `event`, a new one while under its polyphony, or else its oldest voice, cut.
func _voice(event: String, e: Dictionary) -> AudioStreamPlayer:
	var pool: Array = _voices.get(event, [])
	for p in pool:
		if not p.playing:
			return p
	if pool.size() < maxi(1, int(e.get("max_polyphony", DEFAULT_POLYPHONY))):
		var p := _player("Sfx_%s_%d" % [event, pool.size()], String(e.get("bus", "SFX")))
		pool.append(p)
		_voices[event] = pool
		return p
	var oldest: AudioStreamPlayer = pool[0]
	for p in pool:
		if p.get_playback_position() > oldest.get_playback_position():
			oldest = p
	oldest.stop()
	return oldest


## Fades every track of `kind` but `event` out (or, with `duck`, down to DUCK_DB) and brings `event` in:
## its own track again when it is still playing (a ducked map theme), else a new one.
func _switch(kind: String, event: String, duck: bool) -> bool:
	if not event.is_empty() and not _known(event):
		return false
	var now_name := music_name if kind == "music" else ambiance_name
	var same := event == now_name and (not live() or _track(kind, event) != null)
	if kind == "music":
		music_name = event
	else:
		ambiance_name = event
	if not same and not event.is_empty():
		if _stream(event) == null:
			return false
		_remember(event)
	if not live():
		return true
	for other in _tracks:
		if other.kind != kind or other.event == event:
			continue
		if duck:
			_fade(other, db_to_linear(DUCK_DB), _fade_s(other.event, "fade_out_s"), false)
		else:
			_fade(other, 0.0, _fade_s(other.event, "fade_out_s"), true)
	if event.is_empty():
		return true
	var t = _track(kind, event)
	if t != null:
		_fade(t, 1.0, _fade_s(event, "fade_in_s"), false)
		return true
	var e: Dictionary = events[event]
	var player := _player("%s_%s" % [kind.capitalize(), event], String(e.get("bus", "Music")))
	player.stream = _stream(event)
	var fade_in := _fade_s(event, "fade_in_s")
	t = {"event": event, "kind": kind, "player": player, "base_db": float(e.get("volume_db", 0.0)),
		"gain": 0.0 if fade_in > 0.0 else 1.0, "target": 1.0, "rate": 1.0 / fade_in if fade_in > 0.0 else 1.0,
		"stop_at_zero": false}
	_tracks.append(t)
	_apply_gain(t)
	player.play()
	return true


## The playing track of `kind` for `event`, or null. A finished sting doesn't count.
func _track(kind: String, event: String):
	for t in _tracks:
		if t.kind == kind and t.event == event and is_instance_valid(t.player) and t.player.playing:
			return t
	return null


func _fade(t: Dictionary, target: float, seconds: float, stop_at_zero: bool) -> void:
	t.target = target
	t.stop_at_zero = stop_at_zero
	if seconds <= 0.0:
		t.gain = target
		_apply_gain(t)
	else:
		t.rate = absf(float(t.gain) - target) / seconds if not is_equal_approx(float(t.gain), target) else 1.0


func _fade_s(event: String, key: String) -> float:
	return maxf(0.0, float(events.get(event, {}).get(key, 0.0)))


func _apply_gain(t: Dictionary) -> void:
	var gain := float(t.gain)
	t.player.volume_db = float(t.base_db) + linear_to_db(gain) if gain > 0.0001 else SILENT_DB


func _drop(t: Dictionary) -> void:
	_tracks.erase(t)
	if is_instance_valid(t.player):
		t.player.stop()
		t.player.queue_free()


func _player(node_name: String, bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = node_name.validate_node_name()
	p.bus = bus if AudioServer.get_bus_index(bus) != -1 else "Master"
	add_child(p)
	return p


func _stream(event: String) -> AudioStream:
	if _streams.has(event):
		return _streams[event]
	var path := String(events[event].path)
	var stream: AudioStream = null
	if ResourceLoader.exists(path):
		stream = load(path) as AudioStream
	if stream == null:
		_warn("missing:" + event, "The sound file for '%s' is missing: %s." % [event, path])
	_streams[event] = stream
	return stream


func _remember(event: String) -> void:
	history.append(event)
	if history.size() > HISTORY_SIZE:
		history = history.slice(history.size() - HISTORY_SIZE)


func _warn(key: String, text: String) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	warnings.append(text)
	if not quiet:
		push_warning(text)


# --- buttons click by themselves ------------------------------------------------------------------

func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		_hook_button(node)


func _hook_buttons(node: Node) -> void:
	if node is BaseButton:
		_hook_button(node)
	for child in node.get_children():
		_hook_buttons(child)


func _hook_button(b: BaseButton) -> void:
	if b.pressed.is_connected(_on_button_pressed) or bool(b.get_meta(SILENT_META, false)):
		return
	b.pressed.connect(_on_button_pressed)
	b.mouse_entered.connect(_on_button_hovered.bind(b))


func _on_button_pressed() -> void:
	play("ui_click")


func _on_button_hovered(b: BaseButton) -> void:
	if is_instance_valid(b) and not b.disabled:
		play("ui_hover")
