class_name BattleControls
extends Control
## The battle playback controls (M3-4, #59; design/M3_BATTLES.md §5.1-§5.3, §6). Renderer-agnostic: it
## talks only to a BattlePlayer (and a BattleSelection for Tab / Enter), so the 2D Simple view and the 3D
## battle stage host the same one. UX-8 (#221, design/UX_WAR_TABLE.md §6) changed its layout, not its job: it is a
## full-screen layer (it lets every click it doesn't use through to the stage under it) holding
##   the bottom bar  Restart · Play/Pause · 1× 2× 4× (one segmented control) · the scrubber (BattleScrubber): one tick
##                   per round, the playhead and a marker per key moment, each clickable (it replaces the row of moment
##                   buttons; a kind the battle lacks has no marker, and the scrubber's tooltip says why) · Skip to end ·
##                   Legend · Settings · Close (Settings only once a host offers it: show_settings(true), M3-5)
##   the queue row   M3-5, above the bar and only while a host plays a queue of battles (set_queue): ◂ Previous battle ·
##                   "Battle 2 of 3: Battle of Thornvale" · Next battle ▸ (on the last battle: Back to the report)
##   the Why tab     the why panel's handle on the right edge (buttons.why, W): on the edge while the panel is closed,
##                   at the panel's left edge while it is open
## The host view lays it out with fit(); bottom_reserve() is the height the bar and the queue row take.
## Every button's tooltip names its key (KEYS), and the buttons never take keyboard focus: every one has
## its own key, and Tab selects fighters (§5.3).
##
##   var bar := BattleControls.new()
##   bar.selection = sel                 optional: Tab / Shift+Tab / Enter drive it
##   bar.bind(player, BattleFx.settings())   sets the remembered speed and the Legend / Why toggles
##   bar.fit(view_size, band, tab_right)  lays the bar, the queue row and the Why tab out over a view of view_size;
##                                       band is the stage's free area (the queue row centres on it), tab_right the
##                                       x the Why tab hangs from
##   bar.handle_key(event) -> bool       §5.3's keys (the host calls it from its input handler; the host
##                                       keeps Esc and F1, which depend on what is open and hovered)
##   bar.tick(real_delta)                once a frame: moves the scrubber's playhead
##   bar.choose_speed(s), bar.set_legend(on), bar.set_why(on)   a player's choices: remembered in the
##                                       settings file ([battle] speed, legend_open, why_panel_open) unless
##                                       `remember` is false
##   bar.jump_to_mark(i)                 UX-8: what a click on the scrubber's marker i does
##   bar.set_queue(position, count, title)   M3-5: shows the queue row for battle `position` (0-based) of `count`
##                                       (hidden when count < 2); the host (BattleHost) calls it
##   bar.show_settings(on)               M3-5: shows the Settings button (the host opens the settings panel)
##   signals legend_toggled(on), why_toggled(on), close_requested, pin_requested(fid) (Enter),
##           reframe_requested (F, only when reframe_key is set: the 3D stage's camera, 3D_DIRECTION §7.4),
##           codex_requested(key) (right-click or F1 on a marker: its moment's entry),
##           next_requested (N, Next battle) and previous_requested (Shift+N), settings_requested (S, while
##           the Settings button shows) (M3-5), layout_changed (UX-8: the queue row came or went)

signal legend_toggled(on: bool)
signal why_toggled(on: bool)
signal close_requested
signal pin_requested(fid: int)
signal reframe_requested
signal codex_requested(key: String)
## M3-5: the queue's Next battle (N) and Previous battle (Shift+N), and the Settings button.
signal next_requested
signal previous_requested
signal settings_requested
## UX-8: bottom_reserve() changed (the queue row showed or hid): the host lays itself out again.
signal layout_changed

## UX-8: the bottom bar's height, the queue row's and the gap above each, and the Why tab's size.
const BAR_H := 64.0
const QUEUE_H := 44.0
const GAP := 6.0
const TAB := Vector2(36, 104)
const QUEUE_MAX_W := 900.0
## How close to a round's start (s at 1x) counts as sitting on it, for ← and →.
const ROUND_EPS := 0.001
## The key of every action (§5.3), as the tooltips name them.
const KEYS := {
	"play": "Space", "speed1": "1", "speed2": "2", "speed4": "3", "previous_round": "Left", "next_round": "Right",
	"step_back": ",", "step": ".", "restart": "Home", "skip": "End", "next_moment": "M", "select_next": "Tab",
	"select_previous": "Shift+Tab", "pin": "Enter", "legend": "L", "why": "W", "close": "Esc",
	"next_battle": "N", "previous_battle": "Shift+N", "settings": "S",
}

var player: BattlePlayer = null
var selection: BattleSelection = null
var scrubber: BattleScrubber
var buttons: Dictionary = {}
var legend_open := false
var why_open := true
## Write the player's choices (speed, Legend, Why) to the settings file.
var remember := true
## The settings file ("" = GameSettings.default_path).
var settings_path := ""
## F asks for a reframe (the 3D stage's camera); off in the Simple view, where the camera is fixed.
var reframe_key := false
## M3-5: the queue row (set_queue): which battle of how many, 0-based; count < 2 hides the row.
var queue_position := 0
var queue_count := 0
## UX-8: the bottom bar, the speed control, the queue row (a plate above the bar) and the Why tab's word.
var bar: PanelContainer
var speed_box: HBoxContainer
var queue_row: PanelContainer
var queue_label: Label
var why_label: Label
var _resume_after_drag := false
var _tail_t := 0.0


func _init() -> void:
	name = "BattleControls"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	fit(Vector2(1600, 900), Rect2(0, 0, 1600, 900), 1600)


## Shows `p_player`'s battle: the scrubber's rounds and moment markers (and why a kind has none), and the
## settings' speed and toggles (BattleFx.settings() shape; {} reads the file).
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
	scrubber.duration = player.duration()
	scrubber.rounds = player.round_times()
	scrubber.time = player.time()
	scrubber.set_marks(marks_of(player))
	var missing := player.missing_moments()
	var lines := []
	for kind in BattleMoments.KINDS:
		if not missing.has(kind) or (kind == "spell" and not player.battle_log().get("magic", false)):
			continue  # M5-7: only a battle in a game with magic can have spells
		lines.append("%s: %s" % [String(BattleMoments.TITLES[kind]), String(missing[kind])])
	scrubber.missing_lines = lines
	_update_buttons()


## The scrubber's markers for `p`'s battle: one per key moment, at its beat's time, with its tooltip (what happened,
## how to jump there, and its codex entry) and its codex key.
static func marks_of(p: BattlePlayer) -> Array:
	var out := []
	for m in p.moments():
		var kind := String(m.kind)
		var key := String(m.get("codex", "battle_key_moments"))
		if not RulesCodex.ENTRIES.has(key):
			key = "battle_key_moments"
		var tip := TooltipText.plain(String(BattleMoments.TITLES.get(kind, "Key moment")),
			"%s Click to jump there (%s jumps to the next key moment of any kind)." % [String(m.text), KEYS.next_moment])
		out.append({"t": p.moment_time(m), "kind": kind, "event": int(m.event), "text": String(m.text), "codex": key,
			"tip": CodexLink.with_link(tip, key)})
	return out


func tick(_real_delta: float = 0.0) -> void:
	if player != null:
		scrubber.time = player.time()


## UX-8: lays the controls out over a view of `view`: the bar along the bottom, the queue row above it centred on
## `band` (the stage's free area), and the Why tab hanging left of `tab_right`, just under `band`'s top.
func fit(view: Vector2, band: Rect2, tab_right: float) -> void:
	position = Vector2.ZERO
	size = view
	bar.position = Vector2(0, view.y - BAR_H)
	bar.size = Vector2(view.x, BAR_H)
	var qw := clampf(band.size.x - 32.0, 320.0, QUEUE_MAX_W)
	queue_row.size = Vector2(qw, QUEUE_H)
	queue_row.position = Vector2(roundf(band.position.x + (band.size.x - qw) / 2.0), view.y - BAR_H - GAP - QUEUE_H)
	var tab: Button = buttons.why
	tab.size = TAB
	tab.position = Vector2(tab_right - TAB.x, band.position.y + 8.0)
	_size_scrubber()


## The scrubber's size and place in the bar, worked out as the bar's row lays it out (everything else at its own width,
## the scrubber the rest), so it is right at once: the row only sorts itself on the next frame, and never outside the tree.
func _size_scrubber() -> void:
	var row: HBoxContainer = scrubber.get_parent()
	var sep := float(row.get_theme_constant("separation"))
	var inner := bar.size.x - 24.0
	var shown := row.get_children().filter(func(c): return (c as Control).visible)
	var fixed := sep * maxi(0, shown.size() - 1)
	var before := 0.0
	var seen := false
	for c in shown:
		if c == scrubber:
			seen = true
			continue
		var w := (c as Control).get_combined_minimum_size().x
		fixed += w
		if not seen:
			before += w + sep
	scrubber.size = Vector2(maxf(scrubber.custom_minimum_size.x, inner - fixed), scrubber.custom_minimum_size.y)
	scrubber.position = Vector2(before, (BAR_H - 16.0 - scrubber.size.y) / 2.0)
	scrubber._assign_lanes()


## The height the controls take at the bottom of the view: the bar, and the queue row while it shows.
func bottom_reserve() -> float:
	return BAR_H + (QUEUE_H + GAP if queue_row.visible else 0.0)


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
	_update_tab()
	if save:
		_save({"why_panel_open": on})
	why_toggled.emit(on)


func _save(changes: Dictionary) -> void:
	if remember:
		BattleFx.save_settings(changes, settings_path)


## UX-8: a click on the scrubber's marker `i` jumps to its moment, with the lead-in, keeping play or pause.
func jump_to_mark(i: int) -> Dictionary:
	if player == null or i < 0 or i >= scrubber.marks.size():
		return {}
	return player.jump_to(scrubber.marks[i])


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
		KEY_S:
			if not buttons.settings.visible:
				return false
			settings_requested.emit()
		KEY_N:
			if queue_count < 2:
				return false
			if k.shift_pressed:
				if queue_position <= 0:
					return false
				previous_requested.emit()
			else:
				next_requested.emit()
		_:
			return false
	return true


# --- the queue (M3-5) -------------------------------------------------------------------------------

## Shows the queue row for battle `position` (0-based) of `count` in the host's queue, titled `title` (the
## battle's place, e.g. "Battle of Thornvale"). Fewer than two battles hide it.
func set_queue(position: int, count: int, title: String = "") -> void:
	queue_count = count
	queue_position = clampi(position, 0, maxi(count - 1, 0))
	var was := queue_row.visible
	queue_row.visible = count >= 2
	if was != queue_row.visible:
		layout_changed.emit()
	if count < 2:
		return
	queue_label.text = "Battle %d of %d%s" % [queue_position + 1, count, (": " + title) if not title.is_empty() else ""]
	queue_label.tooltip_text = TooltipText.plain("Watching a queue of battles",
		"These are the turn's battles in the order the report lists them. Next battle (%s) moves on; the last one leads back to the report, and so does Close (%s) at any time." % [KEYS.next_battle, KEYS.close])
	var first := queue_position == 0
	var last := queue_position == count - 1
	buttons.previous_battle.disabled = first
	buttons.previous_battle.tooltip_text = "This is the first battle of the queue." if first \
		else "Watch the battle before this one (%s)." % KEYS.previous_battle
	buttons.next_battle.text = "Back to the report" if last else "Next battle ▸"
	buttons.next_battle.tooltip_text = "This was the last battle: go back to the turn report (%s)." % KEYS.next_battle if last \
		else "Watch the next battle, %d of %d (%s)." % [queue_position + 2, count, KEYS.next_battle]


## True when Next battle leads to another battle (not back to the report).
func has_next_battle() -> bool:
	return queue_count >= 2 and queue_position < queue_count - 1


## Shows or hides the Settings button (a host that can open the settings panel shows it).
func show_settings(on: bool) -> void:
	buttons.settings.visible = on
	_size_scrubber()


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
	_update_tab()
	if player == null:
		return
	buttons.play.text = "Pause" if player.is_playing() else "Play"
	buttons.play.tooltip_text = ("Pause (%s)." if player.is_playing() else "Play (%s).") % KEYS.play
	for s in BattlePlayer.SPEEDS:
		(buttons["speed%d" % s] as Button).set_pressed_no_signal(player.speed() == s)
	buttons.legend.set_pressed_no_signal(legend_open)
	buttons.why.set_pressed_no_signal(why_open)


func _update_tab() -> void:
	buttons.why.tooltip_text = ("Close the why panel (%s)." if why_open else
		"The why panel: what is happening now, and why (%s). Click a fighter or press %s to pin its explanation there.") % (
		[KEYS.why] if why_open else [KEYS.why, KEYS.select_next])


## Every text a player can see or hover on the controls (for the no-raw-ids test).
func visible_texts() -> Array:
	var out := []
	for b in buttons.values():
		if not (b as Button).visible or (queue_row.is_ancestor_of(b) and not queue_row.visible):
			continue
		out.append((b as Button).text)
		out.append((b as Button).tooltip_text)
	out.append(why_label.text)
	for m in scrubber.marks:
		out.append(String(m.text))
		out.append(String(m.tip))
	out.append(scrubber.base_tooltip())
	if queue_row.visible:
		out.append(queue_label.text)
		out.append(queue_label.tooltip_text)
	return out


func _build() -> void:
	bar = PanelContainer.new()
	bar.name = "Bar"
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UiPalette.PANEL_BG, 0.94)
	style.border_color = UiPalette.PANEL_BORDER
	style.border_width_top = 2
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	bar.add_theme_stylebox_override("panel", style)
	add_child(bar)
	var row := HBoxContainer.new()
	row.name = "Buttons"
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(row)
	buttons.restart = _button(row, "Restart", "Watch from the start (%s)." % KEYS.restart, func(): player.restart())
	buttons.play = _button(row, "Play", "Play (%s)." % KEYS.play, func(): player.toggle())
	buttons.play.custom_minimum_size.x = 88
	speed_box = HBoxContainer.new()
	speed_box.name = "Speed"
	speed_box.add_theme_constant_override("separation", 0)
	speed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(speed_box)
	for k in BattlePlayer.SPEEDS.size():
		var s: int = BattlePlayer.SPEEDS[k]
		var key: String = KEYS["speed%d" % s]
		var b := _button(speed_box, "%d×" % s, "Play at %d× speed (%s). The speed you pick is remembered." % [s, key], choose_speed.bind(s))
		b.toggle_mode = true
		b.custom_minimum_size.x = 46
		_segment(b, k == 0, k == BattlePlayer.SPEEDS.size() - 1)
		buttons["speed%d" % s] = b
	scrubber = BattleScrubber.new()
	scrubber.name = "Scrubber"
	scrubber.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scrubber.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	scrubber.scrubbed.connect(_on_scrub)
	scrubber.released.connect(_on_scrub_released)
	scrubber.moment_pressed.connect(func(i): jump_to_mark(i))
	scrubber.codex_requested.connect(codex_requested.emit)
	row.add_child(scrubber)
	buttons.skip = _button(row, "Skip to end", "Skip to the result (%s)." % KEYS.skip, func(): player.skip_to_end())
	buttons.legend = _button(row, "Legend", "The legend: what every mark on the screen means (%s)." % KEYS.legend, func(): set_legend(not legend_open))
	buttons.legend.toggle_mode = true
	buttons.settings = _button(row, "Settings", "The settings (%s): the battle view, watching your battles at the start of each turn, the speed, reduced motion and screen shake." % KEYS.settings,
		func(): settings_requested.emit())
	buttons.settings.visible = false
	buttons.close = _button(row, "Close", "Close the battle (%s)." % KEYS.close, func(): close_requested.emit())
	# The Why tab: the why panel's handle on the right edge (UX-8).
	var tab := _button(self, "", "", func(): set_why(not why_open))
	tab.name = "WhyTab"
	tab.toggle_mode = true
	tab.custom_minimum_size = TAB
	buttons.why = tab
	why_label = Label.new()
	why_label.name = "WhyWord"
	why_label.text = "Why"
	why_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	why_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	why_label.add_theme_font_override("font", UiFonts.name())
	why_label.add_theme_font_size_override("font_size", UiPalette.TYPE_BODY)
	why_label.add_theme_color_override("font_color", UiPalette.GILT)
	why_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	why_label.size = Vector2(TAB.y - 12.0, TAB.x)
	why_label.position = Vector2(0, TAB.y - 6.0)
	why_label.rotation = -PI / 2.0
	tab.add_child(why_label)
	_update_tab()
	# The queue row (M3-5): the host's queue of battles, shown by set_queue.
	queue_row = PanelContainer.new()
	queue_row.name = "Queue"
	queue_row.mouse_filter = Control.MOUSE_FILTER_STOP
	queue_row.add_theme_stylebox_override("panel", TableHud.plaque_style(8, 3))
	queue_row.visible = false
	add_child(queue_row)
	var qbox := HBoxContainer.new()
	qbox.add_theme_constant_override("separation", 12)
	qbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_row.add_child(qbox)
	buttons.previous_battle = _button(qbox, "◂ Previous battle", "", func(): previous_requested.emit())
	buttons.previous_battle.custom_minimum_size = Vector2(150, 34)
	queue_label = Label.new()
	queue_label.name = "QueueLabel"
	queue_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	queue_label.custom_minimum_size.x = 120
	queue_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	queue_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	queue_label.clip_text = true
	queue_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	queue_label.add_theme_font_override("font", UiFonts.name())
	queue_label.add_theme_font_size_override("font_size", UiPalette.TYPE_BODY)
	queue_label.add_theme_color_override("font_color", UiPalette.GILT)
	queue_label.mouse_filter = Control.MOUSE_FILTER_PASS
	qbox.add_child(queue_label)
	buttons.next_battle = _button(qbox, "Next battle ▸", "", func(): next_requested.emit())
	buttons.next_battle.custom_minimum_size = Vector2(150, 34)


func _button(parent: Control, text: String, tip: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(0, 44)
	b.add_theme_font_size_override("font_size", UiPalette.TYPE_BODY)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	parent.add_child(b)
	return b


## One segment of a segmented control: the theme's button looks with only the outer corners rounded.
static func _segment(b: Button, first: bool, last: bool) -> void:
	var theme := ThemeDB.get_project_theme()
	if theme == null:
		return
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var sb := theme.get_stylebox(state, "Button") if theme.has_stylebox(state, "Button") else null
		if not sb is StyleBoxFlat:
			continue
		var f := (sb as StyleBoxFlat).duplicate() as StyleBoxFlat
		if not first:
			f.corner_radius_top_left = 0
			f.corner_radius_bottom_left = 0
		if not last:
			f.corner_radius_top_right = 0
			f.corner_radius_bottom_right = 0
		b.add_theme_stylebox_override(state, f)
