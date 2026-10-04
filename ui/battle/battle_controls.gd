class_name BattleControls
extends Control
## The battle playback control bar (M3-4, #59; design/M3_BATTLES.md §5.1-§5.3, §6). Renderer-agnostic: it
## talks only to a BattlePlayer (and a BattleSelection for Tab / Enter), so the 2D Simple view hosts it now
## and the 3D battle stage hosts it unchanged later. 1600 x 148 at the base viewport.
##   row 1  the round scrubber (BattleScrubber): one tick per round, the playhead and a marker per key
##          moment. Click or drag anywhere to see that point at once; on release, playback resumes from the
##          start of the nearest round's attacks if it was playing (§5.1).
##   row 2  Restart · Play/Pause · 1x 2x 4x · Skip to end | First to fall · Charge · Ruler falls · Turning
##          point · Rout (disabled with the reason when the battle has none) | Legend · Why · Close
## Every button's tooltip names its key (KEYS), and the buttons never take keyboard focus: every one has
## its own key, and Tab selects fighters (§5.3).
##
##   var bar := BattleControls.new()
##   bar.selection = sel                 optional: Tab / Shift+Tab / Enter drive it
##   bar.bind(player, BattleFx.settings())   sets the remembered speed and the Legend / Why toggles
##   bar.handle_key(event) -> bool       §5.3's keys (the host calls it from its input handler; the host
##                                       keeps Esc and F1, which depend on what is open and hovered)
##   bar.tick(real_delta)                once a frame: moves the scrubber's playhead
##   bar.choose_speed(s), bar.set_legend(on), bar.set_why(on)   a player's choices: remembered in the
##                                       settings file ([battle] speed, legend_open, why_panel_open) unless
##                                       `remember` is false
##   signals legend_toggled(on), why_toggled(on), close_requested, pin_requested(fid) (Enter),
##           reframe_requested (F, only when reframe_key is set: the 3D stage's camera, 3D_DIRECTION §7.4),
##           codex_requested(key) (right-click or F1 on a jump button: Key moments)

signal legend_toggled(on: bool)
signal why_toggled(on: bool)
signal close_requested
signal pin_requested(fid: int)
signal reframe_requested
signal codex_requested(key: String)

const SIZE := Vector2(1600, 148)
## How close to a round's start (s at 1x) counts as sitting on it, for ← and →.
const ROUND_EPS := 0.001
## The key of every action (§5.3), as the tooltips name them.
const KEYS := {
	"play": "Space", "speed1": "1", "speed2": "2", "speed4": "3", "previous_round": "Left", "next_round": "Right",
	"step_back": ",", "step": ".", "restart": "Home", "skip": "End", "next_moment": "M", "select_next": "Tab",
	"select_previous": "Shift+Tab", "pin": "Enter", "legend": "L", "why": "W", "close": "Esc",
}

var player: BattlePlayer = null
var selection: BattleSelection = null
var scrubber: BattleScrubber
var buttons: Dictionary = {}
var moment_buttons: Dictionary = {}
var legend_open := false
var why_open := true
## Write the player's choices (speed, Legend, Why) to the settings file.
var remember := true
## The settings file ("" = GameSettings.default_path).
var settings_path := ""
## F asks for a reframe (the 3D stage's camera); off in the Simple view, where the camera is fixed.
var reframe_key := false
var _resume_after_drag := false
var _tail_t := 0.0


func _init() -> void:
	name = "BattleControls"
	size = SIZE
	custom_minimum_size = SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()


## Shows `p_player`'s battle: the scrubber's rounds and moments, the jump buttons (or why each is
## disabled), and the settings' speed and toggles (BattleFx.settings() shape; {} reads the file).
func bind(p_player: BattlePlayer, settings: Dictionary = {}) -> void:
	if player != null:
		for c in player.playing_changed.get_connections():
			if c.callable.get_object() == self:
				player.playing_changed.disconnect(c.callable)
		for c in player.speed_changed.get_connections():
			if c.callable.get_object() == self:
				player.speed_changed.disconnect(c.callable)
	player = p_player
	var st := settings if not settings.is_empty() else BattleFx.settings(settings_path)
	player.playing_changed.connect(_on_playing_changed)
	player.speed_changed.connect(_on_speed_changed)
	player.set_speed(int(st.get("speed", 1)))
	legend_open = bool(st.get("legend_open", false))
	why_open = bool(st.get("why_panel_open", true))
	_tail_t = player.duration()
	for b in player.beats():
		if b.kind == "end":
			_tail_t = float(b.t)
			break
	var marks := []
	for m in player.moments():
		marks.append({"t": player.moment_time(m), "kind": String(m.kind), "text": String(m.text)})
	scrubber.duration = player.duration()
	scrubber.rounds = player.round_times()
	scrubber.marks = marks
	scrubber.time = player.time()
	scrubber.queue_redraw()
	var missing := player.missing_moments()
	for kind in BattleMoments.KINDS:
		var b: Button = moment_buttons[kind]
		var have := player.moments().filter(func(m): return m.kind == kind)
		b.disabled = have.is_empty()
		if have.is_empty():
			b.tooltip_text = TooltipText.wrap_text(String(missing.get(kind, "Not in this battle.")))
		else:
			var tip := String(have[0].text)
			if have.size() > 1:
				tip += " (%d in this battle: press again for the next.)" % have.size()
			b.tooltip_text = TooltipText.wrap_text(tip + " Jump there (%s jumps to the next key moment of any kind)." % KEYS.next_moment)
		CodexLink.attach(b, "battle_key_moments", codex_requested.emit)
	_update_buttons()


func tick(_real_delta: float = 0.0) -> void:
	if player != null:
		scrubber.time = player.time()


# --- a player's choices -----------------------------------------------------------------------------

func choose_speed(s: int) -> void:
	if player != null and player.set_speed(s):
		_save({"speed": s})
	_update_buttons()


func set_legend(on: bool, save := true) -> void:
	legend_open = on
	buttons.legend.set_pressed_no_signal(on)
	if save:
		_save({"legend_open": on})
	legend_toggled.emit(on)


func set_why(on: bool, save := true) -> void:
	why_open = on
	buttons.why.set_pressed_no_signal(on)
	if save:
		_save({"why_panel_open": on})
	why_toggled.emit(on)


func _save(changes: Dictionary) -> void:
	if remember:
		BattleFx.save_settings(changes, settings_path)


# --- keys (§5.3) ------------------------------------------------------------------------------------

## Handles one of §5.3's keys. Returns whether it was one (the host then marks the event handled).
func handle_key(event: InputEvent) -> bool:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo or player == null:
		return false
	match k.keycode:
		KEY_SPACE:
			player.toggle()
		KEY_1:
			choose_speed(1)
		KEY_2:
			choose_speed(2)
		KEY_3:
			choose_speed(4)
		KEY_LEFT:
			previous_round()
		KEY_RIGHT:
			next_round()
		KEY_COMMA:
			if not player.is_playing():
				player.step_back()
		KEY_PERIOD:
			if not player.is_playing():
				player.step()
		KEY_HOME:
			player.restart()
		KEY_END:
			player.skip_to_end()
		KEY_M:
			player.next_moment()
		KEY_L:
			set_legend(not legend_open)
		KEY_W:
			set_why(not why_open)
		KEY_TAB:
			if selection == null:
				return false
			if k.shift_pressed:
				selection.previous()
			else:
				selection.next()
		KEY_ENTER, KEY_KP_ENTER:
			if selection == null or selection.selected < 0:
				return false
			pin_requested.emit(selection.selected)
		KEY_F:
			if not reframe_key:
				return false
			reframe_requested.emit()
		_:
			return false
	return true


## ← : the last round start before the playhead (before round 1, the start of the battle). Sitting on a
## round's start, that is the round before it.
func previous_round() -> void:
	var best := -1
	for r in player.round_times():
		if float(r.t) < player.time() - ROUND_EPS:
			best = int(r.round)
	if best < 1 or not player.seek_round(best):
		player.restart()


## → : the first round start after the playhead (after the last round, the result).
func next_round() -> void:
	for r in player.round_times():
		if float(r.t) > player.time() + ROUND_EPS and player.seek_round(int(r.round)):
			return
	player.skip_to_end()


# --- scrubbing --------------------------------------------------------------------------------------

func _on_scrub(t: float) -> void:
	if player == null:
		return
	if not _resume_after_drag and player.is_playing():
		_resume_after_drag = true
		player.pause()
	player.seek_time(t)


func _on_scrub_released() -> void:
	if not _resume_after_drag:
		return
	_resume_after_drag = false
	var t := player.time()
	if t < _tail_t:
		player.seek_time(resume_time(t))
	player.play()


## Where playback resumes after a drag released at `t` (seconds at 1x): the start of the nearest round's
## attacks (§5.1), or `t` itself once the rounds are over.
func resume_time(t: float) -> float:
	if t >= _tail_t or player.round_times().is_empty():
		return t
	var best := t
	var gap := INF
	for r in player.round_times():
		var start := float(r.t) + BattlePlayer.BANNER
		if absf(start - t) < gap:
			gap = absf(start - t)
			best = start
	return best


# --- buttons ----------------------------------------------------------------------------------------

func _on_playing_changed(_playing: bool) -> void:
	_update_buttons()


func _on_speed_changed(_s: int) -> void:
	_update_buttons()


func _update_buttons() -> void:
	if player == null:
		return
	buttons.play.text = "Pause" if player.is_playing() else "Play"
	buttons.play.tooltip_text = ("Pause (%s)." if player.is_playing() else "Play (%s).") % KEYS.play
	for s in BattlePlayer.SPEEDS:
		(buttons["speed%d" % s] as Button).set_pressed_no_signal(player.speed() == s)
	buttons.legend.set_pressed_no_signal(legend_open)
	buttons.why.set_pressed_no_signal(why_open)


## Every text a player can see or hover on the bar (for the no-raw-ids test).
func visible_texts() -> Array:
	var out := []
	for b in buttons.values() + moment_buttons.values():
		out.append((b as Button).text)
		out.append((b as Button).tooltip_text)
	for m in scrubber.marks:
		out.append(String(m.text))
	return out


func _build() -> void:
	scrubber = BattleScrubber.new()
	scrubber.name = "Scrubber"
	scrubber.position = Vector2(200, 6)
	scrubber.size = Vector2(1200, 40)
	scrubber.scrubbed.connect(_on_scrub)
	scrubber.released.connect(_on_scrub_released)
	add_child(scrubber)
	var row := HBoxContainer.new()
	row.name = "Buttons"
	row.add_theme_constant_override("separation", 6)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.position = Vector2(12, 60)
	row.size = Vector2(SIZE.x - 24, 48)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	buttons.restart = _button(row, "Restart", "Watch from the start (%s)." % KEYS.restart, func(): player.restart())
	buttons.play = _button(row, "Play", "Play (%s)." % KEYS.play, func(): player.toggle())
	buttons.play.custom_minimum_size.x = 88
	for s in BattlePlayer.SPEEDS:
		var key: String = KEYS["speed%d" % s]
		var b := _button(row, "%d×" % s, "Play at %d× speed (%s). The speed you pick is remembered." % [s, key], choose_speed.bind(s))
		b.toggle_mode = true
		b.custom_minimum_size.x = 48
		buttons["speed%d" % s] = b
	buttons.skip = _button(row, "Skip to end", "Skip to the result (%s)." % KEYS.skip, func(): player.skip_to_end())
	row.add_child(VSeparator.new())
	for kind in BattleMoments.KINDS:
		moment_buttons[kind] = _button(row, String(BattleMoments.TITLES[kind]), "", func(): player.jump_to_moment(kind))
	row.add_child(VSeparator.new())
	buttons.legend = _button(row, "Legend", "What every mark on the screen means (%s)." % KEYS.legend, func(): set_legend(not legend_open))
	buttons.legend.toggle_mode = true
	buttons.why = _button(row, "Why", "The why panel: what is happening now, and why (%s). Click a fighter or press %s to pin its explanation there." % [KEYS.why, KEYS.select_next],
		func(): set_why(not why_open))
	buttons.why.toggle_mode = true
	buttons.close = _button(row, "Close", "Close the battle (%s)." % KEYS.close, func(): close_requested.emit())


func _button(parent: Control, text: String, tip: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(0, 44)
	b.add_theme_font_size_override("font_size", 16)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	parent.add_child(b)
	return b
