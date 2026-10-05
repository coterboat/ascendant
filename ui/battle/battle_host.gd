class_name BattleHost
extends Control
## The one place the game opens a battle playback (M3-5, #60; design/M3_BATTLES.md §6, design/3D_DIRECTION.md
## §7.6). It is a full-screen overlay that plays a queue of battle events in the order given (the turn
## report's order), with Next and Previous through the queue; the last battle's Next, Close and Esc lead
## back to whatever opened it (the turn report). It never reads or changes anything but the events it was
## given: playback is a pure function of each battle's log (M3 §2.1).
##
## The view: the setting "Battle view" ([battle] view in the settings file: "3d", the default since M3b,
## or "simple") picks who draws the battle. The Simple view (BattleSimpleView) is always there; the 3D stage on
## the land (M3b) is loaded from stage_3d_path when that file exists. Until it does, choosing 3D falls back
## to the Simple view with a short note. Any view keeps the battle view contract in ui/battle/README.md:
##   func play(log, report, state: GameState, seats: Array) -> String   "" or why it can't be played
##   signal finished      the result is on screen        signal closed   the player closed the view
##   var controls: BattleControls   the shared control bar (the host adds its queue row and Settings)
##   optional: signal codex_requested(key), signal report_requested(event), vars reduced_motion, screen_shake
##
## API:
##   open(events, start_index = 0, session = null, viewer = "", state = null) -> String
##        plays events[start_index], with the rest as the queue. `session` gives the seat colours (and,
##        through rebuild_with, a missing log); `state` is the game as the watcher sees it (M5-2: their view in a
##        fog game; without it, session.state_for(viewer)); `viewer` is the faction watching, whose side's result
##        plays the victory or defeat sting ("" for nobody). Returns "" or why nothing can be watched. Under fog a
##        battle can be watched only by a side that fought it (fog_problem).
##   next(), previous()      move through the queue; next() on the last battle closes (back to the report)
##   close()                 closes the view and the host (emits closed)
##   current_event(), index, queue, view, view_kind ("simple" | "3d": what is on screen)
##   open_settings()         the settings panel over the battle (the control bar's Settings, S)
##   rebuild_with            Callable(event) -> {"log", "errors"}: rebuilds a battle's log that isn't kept
##                           (the game screen passes one that replays the game record); unset, such a
##                           battle says why it can't be watched
##   signals closed, codex_requested(key), report_requested(event) (the result card's Full report),
##           battle_opened(index)
## Static helpers, pure (the turn report and the game screen use them for the Watch buttons):
##   watch_problem(event, can_rebuild = false) -> String   "" when it can be watched, else the plain reason
##   fog_problem(event, viewer, fog) -> String              M5-2: under fog, why `viewer` may not watch it ("" if it may)
##   watchable(events, can_rebuild = false) -> Array        the battles that can be watched, in order
##   battles_of(events, faction) -> Array                   the battles `faction` fought ("" = all), in order
##   sting_for(log, viewer) -> String                       "sting_victory", "sting_defeat" or ""
##   battle_title(event) -> String                          "Battle of Thornvale"
##   chosen_view(path = "") -> String                       the Battle view setting

signal closed
signal codex_requested(key: String)
signal report_requested(event: Dictionary)
signal battle_opened(index: int)

const VIEW_SIMPLE := "simple"
const VIEW_3D := "3d"
## Where the 3D battle stage (M3b, under world3d/) will live: a scene (or a script) whose root keeps the
## battle view contract. Until the file exists, "3D on the land" plays in the Simple view.
const STAGE_3D_PATH := "res://world3d/battle_stage.tscn"
const FALLBACK_NOTE := "3D on the land isn't in the game yet, so this battle plays in the Simple view. The Battle view setting switches over once it arrives."
## The reasons a battle can't be watched (M3 §6, §2.4).
const NO_LOG := "This battle was fought with the test rules and has no playback."
const MORE_SIDES := "Battles with more than two sides can't be watched yet."
const NOT_KEPT := "This battle's playback isn't kept any more, and there is no game record here to rebuild it from."
const NOT_A_BATTLE := "Only battles can be watched."
const REBUILDING := "Regenerating this battle's playback from the game record…"
## M5-2 (§2.8): under fog only the sides that fought a battle saw it.
const NOT_YOURS := "Under fog of war you can watch only the battles you fought: you didn't see this one."
## How long the victory or defeat sting holds the battle music down before it comes back up (s, real time).
const STING_HOLD_S := 8.0
const NOTE_S := 6.0
## Views draw parts of themselves with a raised z_index (the Simple view's result card is 4, its legend 5);
## whatever opens over a battle (the settings here; the report viewer and the codex in the game screen) uses
## this z_index so it draws above them.
const OVER_Z := 8

## Tests and the 3D stage's ticket may point this elsewhere.
static var stage_3d_path := STAGE_3D_PATH

var queue: Array = []
var index := -1
var session: GameSession = null
var viewer := ""
## M5-2: the game as the watcher sees it (open's `state`): names, ground and colours come from here.
var watch_state: GameState = null
var view: Control = null
var view_kind := ""
var rebuild_with: Callable = Callable()
## The settings file ("" = GameSettings.default_path).
var settings_path := ""
## The sting played at the end of the battle on screen ("" for none), for tests.
var last_sting := ""

var note_label: Label
var message_panel: PanelContainer
var message_label: Label
var message_close: Button
var message_next: Button
var settings_panel: SettingsPanel = null
var _views := {}  # view kind -> its view, kept for the next battle
var _logs := {}  # queue index -> a rebuilt log (rebuild_with)
var _pending_rebuild := -1
var _switching := false
var _sting_on := false
var _sting_gen := 0
var _note_t := -1.0
var _resume_after_settings := false


func _init() -> void:
	name = "BattleHost"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()


func _process(delta: float) -> void:
	if not visible:
		return
	if _pending_rebuild >= 0:
		rebuild_now()
	if _note_t >= 0.0:
		_note_t += delta
		if _note_t > NOTE_S:
			_note_t = -1.0
			note_label.visible = false


func _unhandled_input(event: InputEvent) -> void:
	# The view handles its own keys; Esc on the host's own message (a reason, or regenerating) closes it.
	if visible and message_panel.visible and event.is_action_pressed("ui_cancel"):
		if is_inside_tree():
			get_viewport().set_input_as_handled()
		close()


# --- opening and the queue ------------------------------------------------------------------------

## Plays events[start_index] (battle events only; anything else is left out of the queue). See the class
## comment. Returns "" or why nothing can be watched.
func open(events: Array, start_index: int = 0, p_session: GameSession = null, p_viewer: String = "", p_state: GameState = null) -> String:
	var battles := []
	var start := -1
	for i in events.size():
		var e = events[i]
		if e is Dictionary and GameSession.BATTLE_TYPES.has(String(e.get("type", ""))):
			if i == start_index or (start < 0 and i > start_index):
				start = battles.size()
			battles.append(e)
	if battles.is_empty():
		return "There are no battles to watch."
	_end_sting()
	queue = battles
	session = p_session
	viewer = p_viewer
	watch_state = p_state
	if watch_state == null and session != null and not viewer.is_empty():
		watch_state = session.state_for(viewer)
	_logs = {}
	visible = true
	_play(clampi(start, 0, battles.size() - 1))
	return ""


func current_event() -> Dictionary:
	return queue[index] if index >= 0 and index < queue.size() else {}


## The next battle of the queue; on the last one, back to the report (closes). True if another battle plays.
func next() -> bool:
	if index + 1 < queue.size():
		_play(index + 1)
		return true
	close()
	return false


func previous() -> bool:
	if index <= 0:
		return false
	_play(index - 1)
	return true


## Closes the view and the host; emits closed once.
func close() -> void:
	_pending_rebuild = -1
	_end_sting()
	if view != null:
		view.close()  # its closed signal finishes the job (_on_view_closed); it also ends the battle music
	if visible:
		_finish_close()


func _finish_close() -> void:
	_end_sting()
	if settings_panel != null:
		settings_panel.visible = false
	message_panel.visible = false
	note_label.visible = false
	_note_t = -1.0
	var was := visible
	visible = false
	if was:
		closed.emit()


func _play(i: int) -> void:
	_end_sting()
	index = i
	last_sting = ""
	message_panel.visible = false
	var event: Dictionary = queue[i]
	var numbers: Dictionary = event.get("numbers", {})
	var battle_log: Dictionary = _logs.get(i, numbers.get("log", {}))
	var problem := watch_problem(event, rebuild_with.is_valid()) if battle_log.is_empty() \
		else watch_problem({"type": "battle", "numbers": {"log": battle_log}})
	if problem.is_empty():
		problem = fog_problem(event, viewer, watch_state != null and watch_state.fog)  # M5-2: participants only
	_use_view(chosen_view(settings_path))
	if problem.is_empty() and battle_log.is_empty():
		# The log isn't kept: rebuild it from the game record first (next frame, so the note shows).
		_hide_view()
		_show_message(REBUILDING, false)
		_pending_rebuild = i
		battle_opened.emit(i)
		return
	if not problem.is_empty():
		_hide_view()
		_show_message(problem)
		battle_opened.emit(i)
		return
	var st := BattleFx.settings(settings_path)
	if "reduced_motion" in view:
		view.set("reduced_motion", bool(st.reduced_motion))
	if "screen_shake" in view:
		view.set("screen_shake", bool(st.screen_shake))
	var why: String = view.play(battle_log, numbers.get("report", {}), watch_state,
		session.players() if session != null else [])
	if not why.is_empty():
		_hide_view()
		_show_message(why)
		battle_opened.emit(i)
		return
	view.visible = true
	var c := _controls_of(view)
	if c != null:
		_wire_controls(c)
		c.set_queue(i, queue.size(), battle_title(event))
	battle_opened.emit(i)


## Closes the view on screen without closing the host (for a message, or a switch of view).
func _hide_view() -> void:
	if view != null and view.visible:
		_switching = true
		view.close()
		_switching = false


## Rebuilds the waiting battle's log (rebuild_with) and plays it, or says why it can't. _process calls it
## the frame after "Regenerating…" shows; tests call it directly.
func rebuild_now() -> void:
	if _pending_rebuild < 0:
		return
	var i := _pending_rebuild
	_pending_rebuild = -1
	var out: Dictionary = rebuild_with.call(queue[i]) if rebuild_with.is_valid() else {"log": {}, "errors": [NOT_KEPT]}
	var rebuilt: Dictionary = out.get("log", {})
	if rebuilt.is_empty():
		var errors: Array = out.get("errors", [])
		_show_message(String(errors[0]) if not errors.is_empty() else NOT_KEPT)
		return
	_logs[i] = rebuilt
	_play(i)


# --- the view -------------------------------------------------------------------------------------

## The view for `kind`, made the first time it is needed. "3d" without the stage falls back to "simple",
## with the note.
func _use_view(kind: String) -> void:
	var want := kind
	var v: Control = _views.get(want)
	if v == null and want == VIEW_3D:
		v = _make_stage()
		if v == null:
			want = VIEW_SIMPLE
			v = _views.get(VIEW_SIMPLE)
			_show_note(FALLBACK_NOTE)
	if v == null:
		v = BattleSimpleView.new()
	if not _views.has(want):
		_views[want] = v
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		v.connect("closed", _on_view_closed)
		v.connect("finished", _on_view_finished)
		if v.has_signal("codex_requested"):
			v.connect("codex_requested", func(key: String): codex_requested.emit(key))
		if v.has_signal("report_requested"):
			v.connect("report_requested", func(_e: Dictionary): _on_report_requested())
		add_child(v)
		move_child(v, 1)  # above the background, under the note, the message and the settings
	if view != null and view != v:
		_hide_view()
	view = v
	view_kind = want


## The 3D stage from stage_3d_path, or null when it isn't there (or doesn't keep the contract).
func _make_stage() -> Control:
	if stage_3d_path.is_empty() or not ResourceLoader.exists(stage_3d_path):
		return null
	var res = load(stage_3d_path)
	var v = null
	if res is PackedScene:
		v = (res as PackedScene).instantiate()
	elif res is Script and (res as Script).can_instantiate():
		v = (res as Script).new()
	if v is Control and keeps_contract(v):
		return v
	if v is Node:
		(v as Node).free()
	return null


## Whether `v` keeps the battle view contract (ui/battle/README.md). `controls` may still be null here when
## the stage builds it in _ready; it must be a BattleControls once play() has returned.
static func keeps_contract(v: Object) -> bool:
	return v != null and v.has_method("play") and v.has_method("close") and v.has_signal("finished") and v.has_signal("closed") \
		and "controls" in v


## Connects a view's control bar to the queue and the settings, once.
func _wire_controls(c: BattleControls) -> void:
	if c.has_meta(&"battle_host"):
		return
	c.set_meta(&"battle_host", true)
	c.next_requested.connect(func(): next())
	c.previous_requested.connect(func(): previous())
	c.settings_requested.connect(open_settings)
	c.show_settings(true)


static func _controls_of(v: Control) -> BattleControls:
	return v.get("controls") as BattleControls if v != null and "controls" in v else null


func _on_view_closed() -> void:
	if _switching:
		return
	_finish_close()


func _on_report_requested() -> void:
	_end_sting()  # the report viewer brings its own battle mood; never leave a sting under it
	report_requested.emit(current_event().duplicate(true))


# --- the stings (M3-3 left them for M3-5) -----------------------------------------------------------

## At the result: the viewer's side won or lost. The sting plays over the ducked battle music and the
## battle music comes back after STING_HOLD_S, at the next battle, or on close.
func _on_view_finished() -> void:
	var event := current_event()
	var battle_log: Dictionary = _logs.get(index, event.get("numbers", {}).get("log", {}))
	var sting := sting_for(battle_log, viewer)
	if sting.is_empty() or _sting_on:
		return
	last_sting = sting
	if GameAudio.current == null:
		return
	GameAudio.current.push_mood(sting, GameAudio.BATTLE_AMBIANCE)
	_sting_on = true
	_sting_gen += 1
	var gen := _sting_gen
	if is_inside_tree():
		get_tree().create_timer(STING_HOLD_S).timeout.connect(func(): if gen == _sting_gen: _end_sting())


func _end_sting() -> void:
	if not _sting_on:
		return
	_sting_on = false
	_sting_gen += 1
	if GameAudio.current != null:
		GameAudio.current.pop_mood()


# --- settings -------------------------------------------------------------------------------------

## The settings panel over the battle (Settings on the control bar, S). Playback pauses while it is open;
## the battle view, speed, reduced motion and screen shake apply from the next battle opened.
func open_settings() -> void:
	if settings_panel == null:
		settings_panel = SettingsPanel.new()
		settings_panel.z_index = OVER_Z
		settings_panel.closed.connect(_on_settings_closed)
		add_child(settings_panel)
	move_child(settings_panel, get_child_count() - 1)
	var c := _controls_of(view) if view != null else null
	_resume_after_settings = c != null and c.player != null and c.player.is_playing()
	if _resume_after_settings:
		c.player.pause()
	settings_panel.open(GameSettings.load_from(settings_path))


func _on_settings_closed() -> void:
	var c := _controls_of(view) if view != null else null
	if _resume_after_settings and c != null and c.player != null and visible:
		c.player.play()
	_resume_after_settings = false


# --- static helpers -------------------------------------------------------------------------------

## "" when `event` can be watched, else the plain reason (M3 §6): not a battle, fought with the test rules
## (no log and no report), more than two sides, a log cut short at BattleLog.MAX_EVENTS, or a log that
## isn't kept and can't be rebuilt (`can_rebuild`: the host has a rebuild_with).
static func watch_problem(event: Dictionary, can_rebuild: bool = false) -> String:
	if not GameSession.BATTLE_TYPES.has(String(event.get("type", ""))):
		return NOT_A_BATTLE
	var numbers = event.get("numbers", {})
	if not (numbers is Dictionary):
		return NO_LOG
	var battle_log = numbers.get("log", {})
	if battle_log is Dictionary and not battle_log.is_empty():
		var problem := BattlePlayer.playback_problem(battle_log)
		if problem.is_empty() and battle_log.get("sides", []).size() != 2:
			problem = MORE_SIDES
		return problem
	var report = numbers.get("report", {})
	if not (report is Dictionary) or report.is_empty():
		return NO_LOG
	return "" if can_rebuild else NOT_KEPT


## M5-2 (§2.8): under fog (`fog`), a battle can be watched only by a side that fought it: "" when `viewer` fought it (or
## nobody in particular watches, or there is no fog), otherwise why not.
static func fog_problem(event: Dictionary, watcher: String, fog: bool) -> String:
	if not fog or watcher.is_empty() or Array(event.get("factions", [])).has(watcher):
		return ""
	return NOT_YOURS


## True when `event` has a report but its log isn't kept (it can be rebuilt from the game record).
static func needs_rebuild(event: Dictionary) -> bool:
	var numbers = event.get("numbers", {})
	return numbers is Dictionary and GameSession.BATTLE_TYPES.has(String(event.get("type", ""))) \
		and (numbers.get("log", {}) as Dictionary).is_empty() and not (numbers.get("report", {}) as Dictionary).is_empty()


## The battles among `events` that can be watched, in their order.
static func watchable(events: Array, can_rebuild: bool = false) -> Array:
	return events.filter(func(e): return e is Dictionary and watch_problem(e, can_rebuild).is_empty())


## The battle events `faction` fought in, in their order ("" = every battle).
static func battles_of(events: Array, faction: String) -> Array:
	return events.filter(func(e): return e is Dictionary and GameSession.BATTLE_TYPES.has(String(e.get("type", ""))) \
		and (faction.is_empty() or Array(e.get("factions", [])).has(faction)))


## The sting for the end of `battle_log` as `viewer` sees it: their side won or lost. "" when the viewer
## didn't fight in it (or nobody is watching in particular), or the log has no end.
static func sting_for(battle_log: Dictionary, viewing: String) -> String:
	if viewing.is_empty() or battle_log.is_empty():
		return ""
	var sides: Array = battle_log.get("sides", [])
	var mine := -1
	for s in sides:
		if String(s.get("faction", "")) == viewing:
			mine = int(s.get("index", sides.find(s)))
	if mine < 0:
		return ""
	var end_i := BattleLog.find_event(battle_log, "end")
	if end_i < 0:
		return ""
	return "sting_victory" if int(battle_log.events[end_i].get("winner", -1)) == mine else "sting_defeat"


## "Battle of Thornvale": the report's place, or the province's name.
static func battle_title(event: Dictionary) -> String:
	var numbers: Dictionary = event.get("numbers", {}) if event.get("numbers") is Dictionary else {}
	var place := String((numbers.get("report", {}) as Dictionary).get("place", ""))
	if not place.is_empty():
		return "Battle %s" % place
	var provinces: Array = event.get("provinces", [])
	if provinces.is_empty():
		return "Battle"
	var names: Array = provinces.map(func(p): return BattleBackdrop.province_name(String(p)))
	return "Battle at %s" % " and ".join(PackedStringArray(names))


## The Battle view setting: "3d" (the default since M3b) or "simple".
static func chosen_view(path: String = "") -> String:
	return String(BattleFx.settings(path).get("view", VIEW_SIMPLE))


## Whether the 3D stage is in the game (stage_3d_path exists).
static func has_stage_3d() -> bool:
	return not stage_3d_path.is_empty() and ResourceLoader.exists(stage_3d_path)


# --- nodes ----------------------------------------------------------------------------------------

func _show_message(text: String, closable: bool = true) -> void:
	message_label.text = text
	message_close.visible = closable
	message_next.visible = closable and index + 1 < queue.size()
	message_panel.visible = true
	move_child(message_panel, get_child_count() - 1)


func _show_note(text: String) -> void:
	note_label.text = text
	note_label.visible = true
	_note_t = 0.0
	move_child(note_label, get_child_count() - 1)


func _build() -> void:
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.color = UiPalette.PANEL_BG
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	note_label = Label.new()
	note_label.name = "Note"
	note_label.visible = false
	note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Over the top of the field, left of where the why panel docks (the view's 1600x900 frame is centred).
	note_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	note_label.offset_left = -760
	note_label.offset_right = 380
	note_label.offset_top = 100
	note_label.offset_bottom = 168
	note_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	note_label.add_theme_font_size_override("font_size", 17)
	note_label.add_theme_color_override("font_color", UiPalette.GILT)
	var note_style := UiPalette.panel_style(10)
	note_label.add_theme_stylebox_override("normal", note_style)
	note_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	note_label.z_index = OVER_Z - 2
	add_child(note_label)
	message_panel = PanelContainer.new()
	message_panel.name = "Message"
	message_panel.visible = false
	message_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	message_panel.offset_left = -400
	message_panel.offset_right = 400
	message_panel.offset_top = -90
	message_panel.offset_bottom = 90
	message_panel.add_theme_stylebox_override("panel", UiPalette.panel_style(24))
	message_panel.z_index = OVER_Z - 1
	add_child(message_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	message_panel.add_child(col)
	message_label = Label.new()
	message_label.name = "MessageLabel"
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.custom_minimum_size = Vector2(740, 0)
	message_label.add_theme_font_size_override("font_size", 22)
	message_label.add_theme_color_override("font_color", UiPalette.TEXT_PRIMARY)
	col.add_child(message_label)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 12)
	col.add_child(row)
	message_next = Button.new()
	message_next.name = "MessageNext"
	message_next.text = "Next battle ▸"
	message_next.tooltip_text = "Skip this battle and watch the next one in the queue."
	message_next.custom_minimum_size = Vector2(0, 44)
	message_next.add_theme_font_size_override("font_size", 18)
	message_next.pressed.connect(func(): next())
	row.add_child(message_next)
	message_close = Button.new()
	message_close.name = "MessageClose"
	message_close.text = "Back to the report"
	message_close.tooltip_text = "Close and go back to the turn report (Esc)."
	message_close.custom_minimum_size = Vector2(0, 44)
	message_close.add_theme_font_size_override("font_size", 18)
	message_close.pressed.connect(close)
	row.add_child(message_close)
