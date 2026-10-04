class_name BattleSimpleView
extends Control
## The Simple view: a battle played back as two armies of portrait cards facing each other (M3-3, #58, as
## re-scoped by design/3D_DIRECTION.md §7.6; design/M3_BATTLES.md §3-§5, §7.4). It is one subscriber of a
## BattlePlayer: the player owns the clock, the beats and the state, and this view only draws them, so the
## 3D stage can replace the field later and keep the same player. It reads the log, the report, static data
## (Art, RulesCodex, the resolver's constants) and its own settings, and never changes the game.
##
## Screen (1600 x 900 base, centred when the window is wider or taller), as M3 §3.1:
##   top bar      0-88     the title, each side's plaque (emblem, name, attacking / defending / arrived, the
##                         terrain and fort chips) and strength bar with its break notch and numbers, the round
##   field        88-688   backdrop and cards (BattleLayout), effects, the round banner; 1216 wide while the
##                         why panel is docked
##   caption      688-752  the round's caption (BattleCaptions), each line linked to its codex entry; before
##                         round 1 the first-visit hint with its Got it button (remembered)
##   controls     752-900  BattleControls (M3-4): the scrubber with round ticks and key-moment markers;
##                         Restart, Play/Pause, 1x 2x 4x, Skip to end, a jump button per key-moment kind,
##                         Legend, Why, Close
##   why panel    1216, 88, 384 x 664   BattleWhyPanel (M3-4), docked right. When the battle only fits the
##                         narrow field as a crowd, the panel floats over the full-width field instead (§3.4).
## The legend (BattleLegend, M3-4) opens over the field. The result card comes up over the field at the end:
## the result, the why with its factor chips, each side's losses, the ruler, feast and aftermath lines, and
## Watch again / Full report / Close.
##
## The controls, the why panel, the legend and the selection (BattleSelection) talk only to the BattlePlayer,
## so the 3D stage hosts the same components. Clicking a card (or Tab) selects its fighter: the card keeps a
## white outline and the why panel pins its explanation.
##
## API:
##   show_event(event, seats = []) -> String         a battle event (numbers.log + numbers.report)
##   show_battle(log, report = {}, seats = [], event = {}) -> String
##        both return "" when it plays, or the plain reason it can't be watched (shown on screen instead)
##   play(log, report, state, seats) -> String   M3-5: the battle view contract BattleHost drives (see
##        ui/battle/README.md); the Simple view ignores `state`, which the 3D stage needs for the land
##   tick(delta)        advances the player and every motion; _process calls it, headless tests call it
##   player             the BattlePlayer (play(), set_speed(), seek()...; the buttons and keys drive it)
##   controls, why_panel, legend, selection   the M3-4 components
##   card(fid)          a fighter's BattleCard;  bar(si) a side's BattleStrengthBar
##   visible_texts()    every text a player can see or hover (for the no-raw-ids test)
##   signals closed, finished (M3-5: the result card is up, at the end or after Skip), codex_requested(key),
##        report_requested(event)
## M3-5: in a host's queue (controls.set_queue) the result card adds Next battle, or Back to the report on
## the last battle (both ask the host through controls.next_requested).
## Keys (§5.3): Space play/pause, 1 2 3 speed, Left/Right round, comma/period step (paused), Home/End,
## M next key moment, Tab / Shift+Tab select a fighter, Enter pin it (opens the why panel), L legend,
## W why panel (all BattleControls.handle_key); R watch again (on the result card); F1 the codex for what
## is hovered; Esc closes the legend, else the screen.
## Settings: reduced motion and screen shake come from the [battle] section of the settings file
## (BattleFx.settings); set reduced_motion / screen_shake before show_*() to override. The speed, the why
## panel, the legend and the first-visit hint are remembered there (BattleControls, BattleFx.save_settings).

signal closed
## M3-5: the playback reached the result (the result card is up).
signal finished
signal codex_requested(key: String)
signal report_requested(event: Dictionary)

const BASE := Vector2(1600, 900)
const TOP_H := 88.0
const FIELD_H := 600.0
const CAPTION_H := 64.0
## A side with more fighters than this is massed (§3.4): numbers only for big and killing hits and the
## hovered fighter, status glyphs only on rulers, commanders and the hovered fighter.
const MASSED := 40
## Floating numbers (§4.1 asks 16 / 22 / 14 px; a little larger here, since they sit on top of portraits).
const NUMBER_SIZE := 20
const BIG_NUMBER_SIZE := 26
const MISS_SIZE := 16
const BANNER_TIME := 0.8
const TAG_TIME := 2.5
const MOMENT_TOAST := 1.8
const FIRST_HINT := "The bars show hit points left; the white notch is where a side breaks. Hover anyone to see what it's doing and why."
const TOOLTIP_WRAP := 72
## The why panel's width when docked, and where the narrowed field ends (§3.1).
const WHY_W := 384.0
const WHY_X := 1216.0
const DEPLOY_LINE := "Before round 1: the armies deploy. Press Space to play, or L for what every mark means."
## #125: the terrain and fort chips keep this far from the title and the plaque, with this gap between them.
const CHIP_GAP := 10.0
const CHIP_SEPARATION := 6.0

var player: BattlePlayer = null
var reduced_motion := false
var screen_shake := true
var layout: Dictionary = {}

var _settings_read := false
var _log: Dictionary = {}
var _names_state: GameState = null  # play()'s state, for the armies' names (TurnReportText); null names them from data
var _report: Dictionary = {}
var _event: Dictionary = {}
var _seats: Array = []
var _side_seat: Array = [0, 1]
var _massed: Array = [false, false]
var _cards: Array = []
var _glyph_cards: Array = []  # the cards that can show status glyphs (on a massed side: rulers and commanders)
var _animating: Dictionary = {}
var _flash := BattleFx.FlashLimiter.new()
var _sound := BattleFx.SoundGate.new()
var _mood_on := false
var _shake := BattleFx.ShakeLimiter.new()
var _real := 0.0
var _last_time := 0.0
var _bars_dirty := true
var _glyphs_dirty := true
var _held_by: Array = [-1, -1]
var _shake_t := -1.0
var _shake_amp := 0.0
var _shake_dur := 0.0
var _shake_phase := 0.0
var _banner_t := -1.0
var _toast_t := -1.0
var _tag_t: Array = [-1.0, -1.0]
var _hovered := -1
var _why_open := true
var _why_docks := true
var _hint_seen := false
var _selected := -1

# Nodes.
var frame: Control
var stage: Control
var backdrop: BattleBackdrop
var cards_layer: Control
var effects: BattleEffects
var banner_label: Label
var toast_label: Label
var title_label: Label
var round_label: Label
var plaque_labels: Array = []
var chip_boxes: Array = []
var bars: Array = []
var bar_texts: Array = []
var tag_labels: Array = []
var center_chip: Label
var caption_labels: Array = []
var field: Control
var caption_strip: PanelContainer
var hint_button: Button
var controls: BattleControls
var why_panel: BattleWhyPanel
var legend: BattleLegend
var selection := BattleSelection.new()
## Aliases into the controls (and the result card's buttons), as M3-3 named them.
var scrubber: BattleScrubber
var buttons: Dictionary = {}
var moment_buttons: Dictionary = {}
var end_card: PanelContainer
var end_result: Label
var end_why: Label
var end_chips: HFlowContainer
var end_lines: VBoxContainer
var message_panel: PanelContainer
var message_label: Label


func _init() -> void:
	name = "BattleSimpleView"
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	size = BASE
	_build()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_center_frame)
	_center_frame()


func _process(delta: float) -> void:
	if visible and player != null:
		tick(delta)


# --- showing a battle -----------------------------------------------------------------------------

## The battle view contract (M3-5, ui/battle/README.md): plays `battle_log` with its `report`. `state` (the
## game state, for the 3D stage's land) only names the armies here, as the turn report does (#55).
func play(battle_log: Dictionary, report: Dictionary, state: GameState = null, seats: Array = []) -> String:
	_names_state = state
	return show_battle(battle_log, report, seats)


func show_event(event: Dictionary, seats: Array = []) -> String:
	var numbers: Dictionary = event.get("numbers", {})
	return show_battle(numbers.get("log", {}), numbers.get("report", {}), seats, event)


func show_battle(battle_log: Dictionary, report: Dictionary = {}, seats: Array = [], event: Dictionary = {}) -> String:
	var st := BattleFx.settings()
	if not _settings_read:
		_settings_read = true
		reduced_motion = reduced_motion or bool(st.reduced_motion)
		screen_shake = screen_shake and bool(st.screen_shake)
	_hint_seen = bool(st.first_hint_seen)
	visible = true
	var problem := BattlePlayer.playback_problem(battle_log)
	if problem.is_empty() and battle_log.get("sides", []).size() != 2:
		problem = "Battles with more than two sides can't be watched yet."
	if not problem.is_empty():
		_show_message(problem)
		return problem
	message_panel.visible = false
	_log = battle_log
	_report = report
	_event = event
	_seats = seats.duplicate()
	var order := _seats if not _seats.is_empty() else UiPalette.seat_order()
	_side_seat = []
	_massed = []
	for s in _log.sides:
		_side_seat.append(order.find(String(s.faction)))
		_massed.append(s.fighters.size() > MASSED)
	_held_by = [-1, -1]
	if player != null:
		_disconnect_player()
	player = BattlePlayer.new(_log, _report)
	player.reduced_motion = reduced_motion
	player.beat.connect(_on_beat)
	player.seeked.connect(_on_seeked)
	controls.bind(player, st)
	_why_docks = not BattleLayout.build(_log, Vector2(WHY_X, FIELD_H)).crowd
	if not _why_docks and controls.why_open:
		# Nothing fits beside the panel (§3.4): it starts collapsed for this battle, and Why / W opens it over
		# the field. The remembered setting is left as it is.
		controls.why_open = false
		controls.buttons.why.set_pressed_no_signal(false)
	_why_open = controls.why_open
	_shake.enabled = screen_shake and not reduced_motion
	_flash.reset()
	_shake.reset()
	_sound.reset()
	if not _mood_on:
		_mood_on = true
		GameAudio.battle(true)
	_apply_width()
	_build_field()
	selection.bind(player, _tab_order())
	why_panel.bind(player, selection)
	legend.reduced_motion = reduced_motion
	_set_legend_open(controls.legend_open)
	_fill_top_bar()
	_fill_end_card()
	end_card.visible = false
	_set_caption([])
	_last_time = 0.0
	_on_seeked(player.live_state())
	return ""


func _disconnect_player() -> void:
	for c in player.beat.get_connections():
		player.beat.disconnect(c.callable)
	for c in player.seeked.get_connections():
		player.seeked.disconnect(c.callable)


func close() -> void:
	if player != null:
		player.pause()
	if _mood_on:
		_mood_on = false
		GameAudio.battle(false)
	visible = false
	closed.emit()


func card(fid: int) -> BattleCard:
	return _cards[fid] if fid >= 0 and fid < _cards.size() else null


func bar(si: int) -> BattleStrengthBar:
	return bars[_slot_of_side(si)]


## The left (0) or right (1) slot of the top bar where side `si` is shown.
func _slot_of_side(si: int) -> int:
	return 0 if si == int(layout.get("left", 0)) else 1


# --- the clock and motion -------------------------------------------------------------------------

func tick(delta: float) -> void:
	if player == null:
		return
	_real += delta
	player.advance(delta)
	var now := player.time()
	var dt := maxf(0.0, now - _last_time)
	_last_time = now
	if dt > 0.0 and not _animating.is_empty():
		var done := []
		for c in _animating:
			if not (c as BattleCard).animate(dt):
				done.append(c)
		for c in done:
			_animating.erase(c)
	effects.step(dt, player.is_playing())
	for b in bars:
		(b as BattleStrengthBar).animate(dt)
	if _glyphs_dirty:
		_refresh_glyphs()
	if _bars_dirty:
		_refresh_bars()
	_tick_labels(dt)
	_tick_shake(delta)
	controls.tick(delta)
	why_panel.tick(delta)


func _tick_labels(dt: float) -> void:
	if _banner_t >= 0.0:
		_banner_t += dt
		banner_label.modulate.a = clampf(1.0 - (_banner_t - BANNER_TIME * 0.5) / (BANNER_TIME * 0.5), 0.0, 1.0)
		if _banner_t >= BANNER_TIME:
			_banner_t = -1.0
			banner_label.visible = false
	if _toast_t >= 0.0:
		_toast_t += dt
		if _toast_t >= MOMENT_TOAST:
			_toast_t = -1.0
			toast_label.visible = false
	for k in 2:
		if _tag_t[k] >= 0.0:
			_tag_t[k] += dt
			if _tag_t[k] >= TAG_TIME:
				_tag_t[k] = -1.0
				tag_labels[k].text = ""


func _tick_shake(real_delta: float) -> void:
	if _shake_t < 0.0:
		return
	if not player.is_playing():
		_shake_t = -1.0
		stage.position = Vector2.ZERO
		return
	_shake_t += real_delta
	var k := 1.0 - _shake_t / _shake_dur
	if k <= 0.0:
		_shake_t = -1.0
		stage.position = Vector2.ZERO
		return
	var a := _shake_amp * k
	var w := _shake_t * 55.0 + _shake_phase
	stage.position = Vector2(sin(w) * a * 2.0 / 3.0, cos(w * 1.3) * a / 3.0)


func _try_shake(spec: Dictionary, event_index: int) -> void:
	if spec.is_empty() or not player.is_playing() or scrubber.is_dragging():
		return
	if not _shake.allow(_real):
		return
	_shake_t = 0.0
	_shake_amp = float(spec.amp)
	_shake_dur = float(spec.dur)
	_shake_phase = float(event_index % 7) * 0.9


## The beat's sound cue (BattleFx.sound_of), spaced out in real time. Beats fire only while playing or
## stepping, so seeking and scrubbing are silent.
func _play_sound(b: Dictionary) -> void:
	var cue := BattleFx.sound_of(b)
	if not cue.is_empty() and _sound.allow(cue, _real):
		GameAudio.sfx(cue)


func _animate(c: BattleCard) -> void:
	if c != null and c.is_animating():
		_animating[c] = true


# --- beats ----------------------------------------------------------------------------------------

func _on_beat(b: Dictionary, st: Dictionary) -> void:
	_play_sound(b)
	match String(b.kind):
		"deploy":
			for c in _cards:
				if c != null and int(_log.fighters[c.fid].tier) == 0:
					c.deploy(BattlePlayer.DEPLOY)
					_animate(c)
		"round_start":
			banner_label.text = String(b.data.banner)
			banner_label.visible = true
			banner_label.modulate.a = 1.0
			_banner_t = 0.0
			_update_round_label(st)
			_glyphs_dirty = true
		"attack_started":
			_attack_started(b)
		"attack_landed":
			_attack_landed(b, st)
		"wound":
			var c := card(int(b.fighter))
			c.sync(st.fighters[c.fid], c.glyphs)
			_bars_dirty = true
			_glyphs_dirty = true  # Berserk and Blood Frenzy start when wounded
		"death":
			var c := card(int(b.fighter))
			c.sync(st.fighters[c.fid], [])
			c.die()
			_animate(c)
			effects.add_dust(_feet(c), _scale())
			if b.data.ruler:
				effects.add_impact(_upper(c), _scale() * 1.2, true, not reduced_motion and _flash.allow(_real), reduced_motion)
				_try_shake(b.data.shake, int(b.event))
			_glyphs_dirty = true
			_bars_dirty = true
		"heal":
			# M4-3's Lifedrinker: a green rising number, and the hp bar refills.
			var c := card(int(b.fighter))
			if c != null:
				c.sync(st.fighters[c.fid], c.glyphs)
				effects.add_number(_upper(c), "+%d hp" % int(b.data.healed), UiPalette.POSITIVE, _number_size(false))
			_bars_dirty = true
			_glyphs_dirty = true
		"harvest":
			var side_name := String(_log.sides[int(b.side)].name)
			toast_label.text = "%s: %s takes %d gold from the %d enemy fighters lost." % [RulerRules.mandate_name(AutoBattleResolver.RED_HARVEST),
				side_name, int(b.data.gold), int(b.data.fighters)]
			toast_label.visible = true
			_toast_t = 0.0
		"morale":
			var si := int(b.side)
			if b.data.result == "held":
				_held_by[si] = int(b.data.held_by)
			else:
				_held_by[si] = -1
			var words := {"holds": "Morale check: holds", "breaks": "Morale check: breaks", "held": "Morale check: held by Iron Discipline"}
			var change: Dictionary = b.data.change
			var text := String(words.get(String(b.data.result), ""))
			if not change.is_empty():
				text = "%s. %s" % [String(change.text), text]
			_show_tag(si, text)
			bars[_slot_of_side(si)].set_strength(player.strength(si), true)
			_glyphs_dirty = true
			_bars_dirty = true  # the bar's text: morale and the break line
		"caption":
			_set_caption(b.data.lines)
		"rout":
			for fid in b.data.fled:
				var c := card(int(fid))
				if c != null and c.visible:
					c.sync(st.fighters[c.fid], [])
					c.rout()
					_animate(c)
			_bars_dirty = true
			_glyphs_dirty = true
			_show_tag(int(b.side), "%s broke and fled." % String(_log.sides[int(b.side)].name))
		"destroyed":
			_bars_dirty = true
			_glyphs_dirty = true
			_show_tag(int(b.side), "No one of %s is left standing." % String(_log.sides[int(b.side)].name))
		"moment":
			toast_label.text = String(b.data.text)
			toast_label.visible = true
			_toast_t = 0.0
		"end":
			_update_round_label(st)
			if b.data.how == "mutual":
				for fid in _log.sides[int(b.data.winner)].fighters:
					var c := card(int(fid))
					if c != null and st.fighters[int(fid)].alive:
						c.snap(st.fighters[int(fid)], c.glyphs)
						_animating.erase(c)
			_bars_dirty = true
			_glyphs_dirty = true
		"feast":
			for h in b.data.healed:
				var c := card(int(h[0]))
				if c != null:
					c.sync(st.fighters[c.fid], c.glyphs)
					effects.add_number(_upper(c), "+%d hp" % (int(h[2]) - int(h[1])), UiPalette.POSITIVE, _number_size(false))
			_bars_dirty = true
			_glyphs_dirty = true
		"aftermath":
			for fid in b.data.lost:
				var c := card(int(fid))
				if c != null and c.visible:
					c.sync(st.fighters[c.fid], [])
					c.fade_out()
					_animate(c)
			_glyphs_dirty = true
		"result":
			_show_end_card()


func _attack_started(b: Dictionary) -> void:
	var a := card(int(b.fighter))
	var t := card(int(b.target))
	if a == null or t == null:
		return
	var proj := String(b.data.projectile)
	if proj.is_empty():
		a.lunge(_center(t))
		_animate(a)
	else:
		var arc := 0.0 if reduced_motion else float(b.data.arc)
		effects.add_projectile(_upper(a), _upper(t), float(b.data.delay), arc, proj, bool(b.data.hit), _scale())


func _attack_landed(b: Dictionary, st: Dictionary) -> void:
	var t := card(int(b.target))
	if t == null:
		return
	var si := int(_log.fighters[t.fid].side)
	var fs: Dictionary = st.fighters[t.fid]
	var shown: bool = not _massed[si] or t.fid == _hovered or t.fid == _selected
	if b.data.hit:
		t.hit()
		_animate(t)
		t.sync(fs, t.glyphs)
		var big: bool = b.data.big
		var kills := int(fs.pending) >= int(fs.hp) and int(fs.pending) - int(b.data.damage) < int(fs.hp)
		effects.add_impact(_upper(t), _scale(), big, not reduced_motion and _flash.allow(_real), reduced_motion)
		if shown or big or kills:
			effects.add_number(_upper(t) - Vector2(0, 8), str(int(b.data.damage)), UiPalette.TEXT_PRIMARY, _number_size(big))
			if int(b.data.get("iron_hide", 0)) < 0:
				# Iron Hide's negative damage part, small and grey beside the number.
				effects.add_number(_upper(t) + Vector2(22, -2), "%d" % int(b.data.iron_hide), UiPalette.TEXT_SECONDARY, maxi(12, _number_size(false) - 6))
		_try_shake(b.data.shake, int(b.event))
		_bars_dirty = true
	elif shown:
		effects.add_number(_upper(t) - Vector2(0, 8), "miss", UiPalette.TEXT_SECONDARY, maxi(12, int(round(MISS_SIZE * _scale()))))


func _on_seeked(st: Dictionary) -> void:
	effects.clear()
	_animating.clear()
	_shake_t = -1.0
	stage.position = Vector2.ZERO
	_banner_t = -1.0
	banner_label.visible = false
	_toast_t = -1.0
	toast_label.visible = false
	for k in 2:
		_tag_t[k] = -1.0
		tag_labels[k].text = ""
	_last_time = player.time()
	_held_by = _held_by_at(st)
	for c in _cards:
		if c != null:
			c.snap(st.fighters[c.fid], _glyphs_for(c.fid, st))
	for si in _log.sides.size():
		bars[_slot_of_side(si)].set_strength(player.strength(si), false)
		bars[_slot_of_side(si)].tooltip_text = ""
	_refresh_bar_texts()
	_bars_dirty = false
	_glyphs_dirty = false
	var lines := []
	var next := player.next_beat()
	var beats := player.beats()
	for k in range(next - 1, -1, -1):
		if beats[k].kind == "caption":
			lines = beats[k].data.lines
			break
	_set_caption(lines)
	_update_round_label(st)
	end_card.visible = false
	controls.tick()


## Who Iron Discipline held each side with at `st` (the side's last morale check before it).
func _held_by_at(st: Dictionary) -> Array:
	var out := [-1, -1]
	var events: Array = _log.events
	for i in mini(int(st.event), events.size()):
		var e: Dictionary = events[i]
		if e.t == "morale":
			out[int(e.side)] = int(e.held_by) if e.result == "held" else -1
	return out


func _refresh_bars() -> void:
	_bars_dirty = false
	var strengths := []
	for si in _log.sides.size():
		var b: BattleStrengthBar = bars[_slot_of_side(si)]
		var st := player.strength(si)
		strengths.append(st)
		# Keep a sliding notch where it is going: only the morale beat moves it.
		b.fill = clampf(float(st.fill), 0.0, 1.0)
		b.pending_share = clampf(float(st.pending) / maxf(1.0, float(st.hp_start)), 0.0, b.fill)
		b.out = String(st.out)
		b.held = bool(st.held)
		b.queue_redraw()
	_refresh_bar_texts(strengths)


func _refresh_bar_texts(strengths: Array = []) -> void:
	for si in _log.sides.size():
		var k := _slot_of_side(si)
		var st: Dictionary = strengths[si] if si < strengths.size() else player.strength(si)
		var text := String(st.text)
		if bar_texts[k].text == text and not bars[k].tooltip_text.is_empty():
			continue
		bar_texts[k].text = text
		var tip := CodexLink.with_link(TooltipText.plain("Strength of %s" % String(_log.sides[si].name),
			"%s. The bar is the hit points this side has left of what it started with. The white notch is where it breaks; hatched red is damage that lands at the end of this round. Whoever stays further above their notch is winning." % text), "battle_strength")
		bars[k].tooltip_text = tip
		bar_texts[k].tooltip_text = tip


func _refresh_glyphs() -> void:
	_glyphs_dirty = false
	var st := player.live_state()
	for c in _glyph_cards:
		if c.alive:
			c.sync(st.fighters[c.fid], _glyphs_for(c.fid, st))


## The status glyphs fighter `fid` shows at `st` (BattleTimeline.statuses, plus exposed, auras and Iron
## Discipline). On a massed side only rulers, commanders and the hovered fighter show them (§3.4).
func _glyphs_for(fid: int, st: Dictionary) -> Array:
	var f: Dictionary = _log.fighters[fid]
	var si := int(f.side)
	var fs: Dictionary = st.fighters[fid]
	if not fs.alive or fs.fled:
		return []
	if _massed[si] and f.role == "unit" and fid != _hovered and fid != _selected:
		return []
	var s := player.timeline().statuses(st, fid)
	var out := []
	if _held_by[si] == fid:
		out.append("iron")
	for a in s.auras:
		var kind := "aura_down" if a == AutoBattleResolver.FURY or a == AutoBattleResolver.DREAD else "aura_up"
		if not out.has(kind):
			out.append(kind)
	if s.shield_wall:
		out.append("shield_wall")
	if s.berserk:
		out.append("berserk")
	if s.blood_frenzy:
		out.append("blood_frenzy")
	if s.pack_leader:
		out.append("pack_leader")
	if int(f.tier) >= 1 and int(st.round) >= 1:
		out.append("shielded" if s.shielded else "exposed")
	return out


# --- geometry helpers -----------------------------------------------------------------------------

func _scale() -> float:
	return float(layout.get("scale", 1.0))


func _center(c: BattleCard) -> Vector2:
	return c.home + c.size / 2.0


func _upper(c: BattleCard) -> Vector2:
	return c.home + Vector2(c.size.x / 2.0, c.size.y * 0.38)


func _feet(c: BattleCard) -> Vector2:
	return c.home + Vector2(c.size.x / 2.0, c.size.y)


func _number_size(big: bool) -> int:
	return maxi(12, int(round((BIG_NUMBER_SIZE if big else NUMBER_SIZE) * _scale())))


# --- hover ----------------------------------------------------------------------------------------

## The hover text of fighter `fid` now: BattleExplain.explain_fighter's lines, each wrapped to keep the
## tooltip narrow. Every number in it is BattleExplain's.
func fighter_tooltip(fid: int) -> String:
	return tooltip_of(player.explain(fid))


static func tooltip_of(explain: Dictionary) -> String:
	var out := []
	for l in explain.get("lines", []):
		var line := String(l)
		var indent := line.length() - line.lstrip(" ").length()
		var pad := " ".repeat(indent)
		var wrapped := TooltipText.wrap_text(line.strip_edges(), TOOLTIP_WRAP - indent)
		for w in wrapped.split("\n"):
			out.append(pad + w)
	return "\n".join(out)


func _on_card_hover(fid: int, on: bool) -> void:
	_hovered = fid if on else (-1 if _hovered == fid else _hovered)
	var c := card(fid)
	if c != null and player != null:
		c.sync(player.live_state().fighters[fid], _glyphs_for(fid, player.live_state()))


## A click on a card: select its fighter (a second click clears it) and pin it in the why panel.
func _on_card_clicked(fid: int) -> void:
	selection.toggle(fid)
	if selection.selected >= 0 and not _why_open:
		controls.set_why(true, false)


func _on_selection(fid: int) -> void:
	var before := _selected
	_selected = fid
	if player == null:
		return
	for k in [before, fid]:
		var c := card(k)
		if c != null:
			c.selected = c.fid == fid
			c.sync(player.live_state().fighters[c.fid], _glyphs_for(c.fid, player.live_state()))
			c.queue_redraw()


## Tab order (§5.3): the left side first, then the right; each side front rank to back line, each rank
## front column first, top to bottom.
func _tab_order() -> Array:
	var ids := []
	for f in _log.fighters:
		ids.append(int(f.id))
	var left := int(layout.get("left", 0))
	ids.sort_custom(func(a, b):
		var sa: Dictionary = layout.slots[a]
		var sb: Dictionary = layout.slots[b]
		var ka := [0 if int(sa.side) == left else 1, int(sa.tier), int(sa.col), int(sa.row), a]
		var kb := [0 if int(sb.side) == left else 1, int(sb.tier), int(sb.col), int(sb.row), b]
		for k in ka.size():
			if ka[k] != kb[k]:
				return ka[k] < kb[k]
		return false)
	return ids


# --- the why panel and the legend -----------------------------------------------------------------

## The field's width: narrowed while the why panel is docked (§3.1), full when it floats or is closed.
func field_width() -> float:
	return WHY_X if _why_open and _why_docks else BASE.x


func _set_why_open(on: bool) -> void:
	_why_open = on
	var before := field.size.x
	_apply_width()
	if on:
		why_panel.refresh()
	if player != null and absf(field.size.x - before) > 0.5:
		var end_shown := end_card.visible
		_build_field()
		selection.order = _tab_order()
		_on_seeked(player.live_state())
		end_card.visible = end_shown
		var c := card(_selected)
		if c != null:
			c.selected = true


## The legend opens over the whole field and the why panel (it is modal: L, Esc or its x closes it).
func _set_legend_open(on: bool) -> void:
	legend.visible = on
	legend.place(Rect2(16, TOP_H + 8, BASE.x - 32, FIELD_H + CAPTION_H - 16))


## Sizes the field, the caption strip and what sits on them to field_width(), and docks or floats the why
## panel.
func _apply_width() -> void:
	var w := field_width()
	field.size.x = w
	for n in [stage, backdrop, cards_layer, effects]:
		(n as Control).size.x = w
	banner_label.size.x = w
	toast_label.size.x = w - 400.0
	caption_strip.size.x = w
	caption_strip.custom_minimum_size.x = w
	tag_labels[1].position.x = w - 24.0 - 520.0
	end_card.position.x = (w - end_card.custom_minimum_size.x) / 2.0
	message_panel.position.x = (w - message_panel.custom_minimum_size.x) / 2.0
	why_panel.visible = _why_open
	why_panel.position = Vector2(WHY_X, TOP_H)


func _on_hint_seen() -> void:
	_hint_seen = true
	BattleFx.save_settings({"first_hint_seen": true})
	if player != null:
		_on_seeked(player.live_state())


# --- input ----------------------------------------------------------------------------------------

## Tab selects fighters (§5.3) before the GUI's focus moves can take it, unless a control outside this
## screen (a codex search field above it) has the keyboard.
func _input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or k.keycode != KEY_TAB or not visible or player == null or not is_inside_tree():
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus != null and not is_ancestor_of(focus):
		return
	if controls.handle_key(event):
		_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or player == null:
		return
	if CodexLink.is_open_key(event):
		var key := card(_hovered).codex_key if _hovered >= 0 else ""
		if key.is_empty() and is_inside_tree():
			key = CodexLink.key_at(get_viewport().gui_get_hovered_control())
		if not key.is_empty():
			codex_requested.emit(key)
			_handled()
		return
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	match k.keycode:
		KEY_R:
			if not end_card.visible:
				return
			_watch_again()
		KEY_ESCAPE:
			if legend.visible:
				controls.set_legend(false)
			else:
				close()
		_:
			if not controls.handle_key(event):
				return
	_handled()


func _gui_input(event: InputEvent) -> void:
	# A click on the empty field clears the selection.
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and player != null:
		var at := mb.position - frame.position
		if Rect2(Vector2(0, TOP_H), Vector2(field_width(), FIELD_H)).has_point(at):
			selection.clear()


func _handled() -> void:
	if is_inside_tree():
		get_viewport().set_input_as_handled()


func _watch_again() -> void:
	end_card.visible = false
	player.restart()
	player.play()


# --- texts ----------------------------------------------------------------------------------------

## Every text on screen or in a tooltip a player can reach now: labels, buttons, chips, cards' hover text,
## the scrubber's marks and the result card. For the no-raw-ids test.
func visible_texts() -> Array:
	var out := []
	_collect_texts(self, out)
	for c in _cards:
		if c != null:
			out.append(fighter_tooltip(c.fid))
	out.append_array(controls.visible_texts())
	out.append_array(legend.visible_texts())
	return out


func _collect_texts(n: Node, out: Array) -> void:
	if n is Label and not (n as Label).text.is_empty():
		out.append((n as Label).text)
	if n is Button and not (n as Button).text.is_empty():
		out.append((n as Button).text)
	if n is Control and not (n as Control).tooltip_text.is_empty() and not (n is BattleCard):
		out.append((n as Control).tooltip_text)
	for ch in n.get_children():
		_collect_texts(ch, out)


func _set_caption(lines: Array) -> void:
	for k in 2:
		var l: Label = caption_labels[k]
		CodexLink.detach(l)
		if k < lines.size():
			l.text = String(lines[k].text)
			l.tooltip_text = TooltipText.plain("Round caption", "What mattered most this round, worked out from the battle's own numbers.")
			CodexLink.attach(l, String(lines[k].codex), codex_requested.emit)
		elif k == 0 and lines.is_empty():
			l.text = FIRST_HINT if not _hint_seen else DEPLOY_LINE
			l.tooltip_text = TooltipText.plain("Watching a battle", "The battle was already fought; this plays it back with the same rolls as the report, so watching can never change it. A caption after every round says what mattered most.")
			CodexLink.attach(l, "battle_playback", codex_requested.emit)
		else:
			l.text = ""
			l.tooltip_text = ""
	hint_button.visible = lines.is_empty() and not _hint_seen


func _show_tag(si: int, text: String) -> void:
	var k := _slot_of_side(si)
	tag_labels[k].text = text
	_tag_t[k] = 0.0


func _update_round_label(st: Dictionary) -> void:
	var n := int(st.round)
	var cap := int(_log.get("round_cap", 8))
	if int(st.winner) >= 0 or st.beat == "end":
		round_label.text = "Battle over after %d %s" % [n, "round" if n == 1 else "rounds"]
	elif n <= 0:
		round_label.text = "The armies deploy"
	else:
		round_label.text = "Round %d of at most %d" % [n, cap]


func _show_message(text: String) -> void:
	message_label.text = text
	message_panel.visible = true
	end_card.visible = false


# --- the result card ------------------------------------------------------------------------------

func _show_end_card() -> void:
	# M3-5: in a host's queue, Next battle (or Back to the report on the last one) joins the card.
	var queue := controls.queue_count >= 2
	buttons.next_battle_card.visible = queue
	buttons.end_close.visible = not queue or controls.has_next_battle()
	if queue:
		buttons.next_battle_card.text = "Next battle (%d of %d) ▸" % [controls.queue_position + 2, controls.queue_count] if controls.has_next_battle() \
			else "Back to the report"
		buttons.next_battle_card.tooltip_text = "Watch the next battle (%s)." % BattleControls.KEYS.next_battle if controls.has_next_battle() \
			else "That was the last battle: go back to the turn report (%s)." % BattleControls.KEYS.next_battle
	end_card.visible = true
	end_card.reset_size()
	finished.emit()


## Fills the result card when the battle loads (its content is fixed per battle), so the end beat only
## shows it.
func _fill_end_card() -> void:
	end_result.text = _result_sentence()
	var why := String(_report.get("why", ""))
	end_why.text = "Why: %s." % _cap(why) if not why.is_empty() else "Why: the report gives no single reason."
	end_why.tooltip_text = TooltipText.plain("Why", "The biggest reasons this battle went the way it did, from the battle report.")
	var entry := "battle_rounds"
	for f in _report.get("factors", []):
		var e := BattleExplain.factor_entry(String(f.get("id", "")))
		if RulesCodex.ENTRIES.has(e):
			entry = e
			break
	CodexLink.attach(end_why, entry, codex_requested.emit)
	for c in end_chips.get_children():
		end_chips.remove_child(c)
		c.queue_free()
	var seen := {}
	for f in _report.get("factors", []):
		var key := BattleExplain.factor_entry(String(f.get("id", "")))
		var title := String(RulesCodex.entry(key).get("title", "")) if RulesCodex.ENTRIES.has(key) else ""
		if title.is_empty() or seen.has(title):
			continue
		seen[title] = true
		var chip := _chip(title, TooltipText.wrap_text(_cap(String(f.get("text", "")))) if not String(f.get("text", "")).is_empty() else title)
		end_chips.add_child(chip)
		CodexLink.attach(chip, key, codex_requested.emit)
	for c in end_lines.get_children():
		end_lines.remove_child(c)
		c.queue_free()
	for line in end_card_lines():
		var l := _label(String(line), 17, UiPalette.TEXT_PRIMARY)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 950  # so a new line never measures itself one word wide and stretches the card
		end_lines.add_child(l)
	end_card.reset_size()  # a card filled for a longer battle before shrinks back to its content
	buttons.report.disabled = _report.is_empty()
	buttons.report.tooltip_text = "Open the full battle report: every round, loss and morale check in words." if not _report.is_empty() \
		else "This battle has no written report."


## The result card's lines under the why: each side's losses, the ruler lines, the feast and the aftermath.
func end_card_lines() -> Array:
	var out := []
	var fin := player.timeline().final_state()
	for si in _log.sides.size():
		var side: Dictionary = _log.sides[si]
		# Those who fell in the fight; the aftermath sentence below says who else was lost with their army.
		var fell := 0
		for fid in side.fighters:
			if not fin.fighters[int(fid)].alive:
				fell += 1
		out.append("%s: %d of %d fighters fell · %d of %d hp left" % [side.name, fell, side.fighters.size(), int(fin.sides[si].hp), int(side.hp_start)])
	for e in _log.events:
		if e.t == "death" and _log.fighters[int(e.f)].role == "ruler":
			out.append("%s fell in round %d." % [_cap(String(_log.fighters[int(e.f)].name)), int(e.n)])
		elif e.t == "feast":
			# The aftermath sentence names the feast when there is one; say it here only if it doesn't.
			var feast := RulerRules.mandate_name(RulerRules.FEAST_OF_VICTORY)
			var after := BattleLog.find_event(_log, "aftermath")
			if after < 0 or not String(_log.events[after].get("text", "")).contains(feast):
				var healed := 0
				for h in e.healed:
					healed += int(h[2]) - int(h[1])
				out.append("%s healed %d hp after the battle." % [feast, healed])
		elif e.t == "harvest":
			var harvest := RulerRules.mandate_name(AutoBattleResolver.RED_HARVEST)
			var aft := BattleLog.find_event(_log, "aftermath")
			if aft < 0 or not String(_log.events[aft].get("text", "")).contains(harvest):
				out.append("%s: %s took %d gold from the %d enemy fighters lost." % [harvest, _log.sides[int(e.side)].name, int(e.gold), int(e.fighters)])
		elif e.t == "aftermath" and not String(e.get("text", "")).is_empty():
			out.append(String(e.text))
	return out


func _result_sentence() -> String:
	for line in _report.get("lines", []):
		if String(line).begins_with("Result: "):
			return String(line).trim_prefix("Result: ")
	var end_i := BattleLog.find_event(_log, "end")
	if end_i < 0:
		return "The playback stops here: this battle's log was cut short."
	var e: Dictionary = _log.events[end_i]
	var n := int(e.rounds)
	return "%s won after %d %s." % [_log.sides[int(e.winner)].name, n, "round" if n == 1 else "rounds"]


static func _cap(text: String) -> String:
	return text if text.is_empty() else text[0].to_upper() + text.substr(1)


# --- building -------------------------------------------------------------------------------------

func _center_frame() -> void:
	if frame == null:
		return
	var s := size if size.x > 10.0 else BASE
	frame.position = ((s - BASE) / 2.0).floor().max(Vector2.ZERO)


func _build_field() -> void:
	for c in cards_layer.get_children():
		cards_layer.remove_child(c)
		c.queue_free()
	effects.clear()
	layout = BattleLayout.build(_log, Vector2(field_width(), FIELD_H))
	_cards = []
	_cards.resize(_log.fighters.size())
	_glyph_cards = []
	var order := []
	for f in _log.fighters:
		var slot: Dictionary = layout.slots[int(f.id)]
		var c := BattleCard.new()
		c.reduced_motion = reduced_motion
		c.setup(f, _side_seat[int(f.side)], slot.rect, int(slot.dir), float(layout.scale), bool(layout.bar_on_top), float(layout.bar_h),
			float(slot.back_x))
		var fid := int(f.id)
		c.explain_source = func(): return fighter_tooltip(fid)
		c.codex_requested.connect(codex_requested.emit)
		c.mouse_entered.connect(_on_card_hover.bind(fid, true))
		c.mouse_exited.connect(_on_card_hover.bind(fid, false))
		c.clicked.connect(_on_card_clicked)
		c.selected = fid == _selected
		_cards[fid] = c
		order.append(c)
		if not _massed[int(f.side)] or f.role != "unit":
			_glyph_cards.append(c)
	# Lower rows draw in front (a crowd overlaps upward).
	order.sort_custom(func(a, b): return a.home.y < b.home.y if a.home.y != b.home.y else a.fid < b.fid)
	for c in order:
		cards_layer.add_child(c)
	# A defended fort stands behind the defender's half.
	var on := ""
	for side in _log.sides:
		if side.get("defender", false):
			on = "left" if int(side.index) == int(layout.left) else "right"
	backdrop.setup(_log, on)


func _fill_top_bar() -> void:
	var place := String(_report.get("place", ""))
	if place.is_empty():
		var pids: Array = _log.get("provinces", [])
		place = "at %s" % BattleBackdrop.province_name(String(pids[0])) if not pids.is_empty() else "in the field"
	var turn := int(_log.get("turn", 0))
	title_label.text = "Battle %s%s" % [place, " · turn %d" % turn if turn > 0 else ""]
	_fit(title_label, 20, 13)
	var border: bool = _log.get("kind", "province") == "border"
	var defender := String(_log.get("defender", ""))
	for si in _log.sides.size():
		var k := _slot_of_side(si)
		var side: Dictionary = _log.sides[si]
		var role := "on the border" if border else ("defending" if side.get("defender", false) else ("attacking" if not defender.is_empty() else "arrived"))
		if not border and not _siege_block().is_empty():
			role = FortView.siege_role(_siege_block(), si)  # M3c S-3: "storming", "sallying garrison", "garrison, in the breach"...
		var people := String(side.get("people", {}).get("name", "")) if side.get("people", {}) is Dictionary else ""
		plaque_labels[k].text = "%s · %s · %s" % [side.name, people, role] if not people.is_empty() else "%s · %s" % [side.name, role]
		_fit(plaque_labels[k], 18, 13)
		var people_words := " Its people: %s." % people if not people.is_empty() else ""
		plaque_labels[k].tooltip_text = TooltipText.plain(String(side.name), "%s, %s. %s%s" % [SeatEmblem.describe(_side_seat[si]).capitalize(),
			_role_words(side, border, defender), _army_words(side), people_words])
		var b: BattleStrengthBar = bars[k]
		b.seat = _side_seat[si]
		b.mirrored = k == 1
		for c in chip_boxes[k].get_children():
			chip_boxes[k].remove_child(c)
			c.queue_free()
		if side.get("defender", false) and not border:
			var terrain := String(_log.get("terrain", ""))
			var bonus: Dictionary = AutoBattleResolver.TERRAIN.get(terrain, {})
			if int(bonus.get("defense", 0)) > 0:
				var text := "%s: +%d defense" % [terrain.capitalize(), int(bonus.defense)]
				if int(bonus.get("attack", 0)) > 0:
					text += " and +%d attack" % int(bonus.attack)
				var chip := _chip(text, TooltipText.plain("Terrain", "The defender of a %s province gets %s." % [terrain, text.substr(text.find(":") + 2)]))
				var short := "%s +%d def" % [terrain.capitalize(), int(bonus.defense)] + (", +%d atk" % int(bonus.attack) if int(bonus.get("attack", 0)) > 0 else "")
				chip.set_meta("full", text)
				chip.set_meta("short", short)
				chip_boxes[k].add_child(chip)
				CodexLink.attach(chip, TooltipText.codex_for(TooltipText.terrain_kind(terrain)), codex_requested.emit)
			var walls := FortView.siege_chip(_siege_block())
			if not walls.is_empty():  # M3c S-3 (§9.7): a stormed garrison's walls replace the fort's old +2
				var wchip := _chip(String(walls.text), String(walls.tip))
				wchip.name = "SiegeChip"
				wchip.set_meta("full", wchip.text)  # #125: "Walls +3 def" where the full words don't fit (_place_chips)
				wchip.set_meta("short", wchip.text.get_slice(" (", 0).replace(": ", " ").replace(" defense", " def"))
				chip_boxes[k].add_child(wchip)
				CodexLink.attach(wchip, String(walls.codex), codex_requested.emit)
			elif _log.get("fort", false):
				var fchip := _chip("Fort: +%d defense" % AutoBattleResolver.FORT_DEFENSE, TooltipText.plain("Fort", "Only a defender gets a fort's bonus: +%d defense to every fighter." % AutoBattleResolver.FORT_DEFENSE))
				fchip.set_meta("full", fchip.text)
				fchip.set_meta("short", "Fort +%d def" % AutoBattleResolver.FORT_DEFENSE)
				chip_boxes[k].add_child(fchip)
				CodexLink.attach(fchip, "fort", codex_requested.emit)
	for k2 in 2:
		_place_chips(k2)
	var open := FortView.siege_chip(_siege_block())
	if border:
		center_chip.text = "Border battle: nobody defends, no terrain bonus"
	elif defender.is_empty() and not open.is_empty():
		center_chip.text = String(open.text)  # M3c S-3 (§9.7): outside the walls, or through the breach
	elif defender.is_empty():
		center_chip.text = "Nobody was defending: no terrain bonus"
	else:
		center_chip.text = ""
	center_chip.visible = not center_chip.text.is_empty()
	center_chip.tooltip_text = TooltipText.plain("Terrain", "Only a side that already held the province gets its terrain and fort bonus. Here nobody did.") if center_chip.visible else ""
	if center_chip.visible and defender.is_empty() and not open.is_empty() and not border:
		center_chip.tooltip_text = String(open.tip)
		CodexLink.attach(center_chip, String(open.codex), codex_requested.emit)
	elif center_chip.visible:
		CodexLink.attach(center_chip, "battle_terrain", codex_requested.emit)


## Puts slot `k`'s terrain and fort chips where they never overlap the title or the plaque (#125): beside the
## plaque's text when they fit between it and the title, in their short words ("Hills +1 def, +1 atk") if only
## those fit, else centred under the round counter (that row's note only shows when nobody defends, and
## chips only when someone does). The full words stay in each chip's tooltip.
func _place_chips(k: int) -> void:
	var box: HBoxContainer = chip_boxes[k]
	var chips := box.get_children()
	if chips.is_empty():
		return
	var tf := _font_of(title_label)
	var tw := tf.get_string_size(title_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size_of(title_label, 20)).x
	var title_l := title_label.position.x + (title_label.size.x - tw) / 2.0
	var title_r := title_l + tw
	var pl: Label = plaque_labels[k]
	var pw := minf(_font_of(pl).get_string_size(pl.text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size_of(pl, 18)).x, pl.size.x)
	var lo := pl.position.x + pw + CHIP_GAP if k == 0 else title_r + CHIP_GAP
	var hi := title_l - CHIP_GAP if k == 0 else pl.position.x + pl.size.x - pw - CHIP_GAP
	for words in ["full", "short"]:
		for c in chips:
			(c as Label).text = String((c as Label).get_meta(words, (c as Label).text))
		var w := chips_width(chips)
		if w <= hi - lo:
			box.position = Vector2(lo if k == 0 else hi - w, 6)
			box.size = Vector2(w, 22)
			return
	## under the round counter, centred in the title's column
	var w2 := chips_width(chips)
	box.position = Vector2(title_label.position.x + (title_label.size.x - w2) / 2.0, center_chip.position.y)
	box.size = Vector2(w2, 20)


## The width the chips take side by side (their text, padding and the box's gaps).
func chips_width(chips: Array) -> float:
	var w := 0.0
	for c in chips:
		var l := c as Label
		w += _font_of(l).get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size_of(l, 13)).x + 12.0
	return w + CHIP_SEPARATION * maxi(0, chips.size() - 1)


func _font_of(l: Control) -> Font:
	return l.get_theme_font("font") if l.get_theme_font("font") != null else l.get_theme_default_font()


func _font_size_of(l: Control, fallback: int) -> int:
	return l.get_theme_font_size("font_size") if l.has_theme_font_size_override("font_size") else fallback


## M3c S-3: the battle's siege block (§4.4): the log's, the report's, or the event's (S-1b puts it on the event first).
func _siege_block() -> Dictionary:
	for src in [_log, _report, _event.get("numbers", {}) if _event is Dictionary else {}]:
		if src is Dictionary and src.get("siege") is Dictionary and not (src.siege as Dictionary).is_empty():
			return src.siege
	return {}


func _role_words(side: Dictionary, border: bool, defender: String) -> String:
	if border:
		return "met the enemy on the border as both armies tried to swap places"
	if not _siege_block().is_empty():  # M3c S-3: its role at the fort and what it meant
		var si := (_log.get("sides", []) as Array).find(side)
		return "%s: %s" % [FortView.siege_role(_siege_block(), si), String(FortView.role_meaning(_siege_block(), si).text)]
	if side.get("defender", false):
		return "defending: it already held the province"
	if defender.is_empty():
		return "arrived at the same time as the enemy, so nobody defends"
	return "attacking: it marched in"


## The side's armies as the turn report and the map name them (TurnReportText.log_armies, #55), then its size.
func _army_words(side: Dictionary) -> String:
	var titles := TurnReportText.log_armies(_log, String(side.get("faction", "")), _names_state).map(func(a): return String(a.title))
	if titles.is_empty():
		for a in side.armies:
			titles.append(String(a.label))
	var n: int = side.fighters.size()
	return "%s: %d %s, %d hp, morale %d." % [RulerRules._cap(RulerRules._and_list(titles)), n, "fighter" if n == 1 else "fighters",
		int(side.hp_start), int(side.start_morale.morale)]


func _build() -> void:
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.color = UiPalette.PANEL_BG
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	frame = Control.new()
	frame.name = "Frame"
	frame.size = BASE
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)

	# The field: a clipping window, a stage inside it that shakes.
	field = Control.new()
	field.name = "Field"
	field.position = Vector2(0, TOP_H)
	field.size = Vector2(BASE.x, FIELD_H)
	field.clip_contents = true
	field.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(field)
	stage = Control.new()
	stage.name = "Stage"
	stage.size = field.size
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	field.add_child(stage)
	stage.position = Vector2.ZERO
	backdrop = BattleBackdrop.new()
	backdrop.name = "Backdrop"
	backdrop.size = field.size
	stage.add_child(backdrop)
	cards_layer = Control.new()
	cards_layer.name = "Cards"
	cards_layer.size = field.size
	cards_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(cards_layer)
	effects = BattleEffects.new()
	effects.name = "Effects"
	effects.size = field.size
	effects.z_index = 2
	stage.add_child(effects)
	banner_label = _label("", 30, UiPalette.TEXT_PRIMARY)
	banner_label.name = "Banner"
	banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_label.position = Vector2(0, 14)
	banner_label.size = Vector2(BASE.x, 40)
	banner_label.add_theme_color_override("font_outline_color", UiPalette.KEYLINE_INK)
	banner_label.add_theme_constant_override("outline_size", 8)
	banner_label.visible = false
	banner_label.z_index = 3
	field.add_child(banner_label)
	toast_label = _label("", 18, UiPalette.GILT)
	toast_label.name = "MomentToast"
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.position = Vector2(200, 54)
	toast_label.size = Vector2(BASE.x - 400, 28)
	toast_label.add_theme_color_override("font_outline_color", UiPalette.KEYLINE_INK)
	toast_label.add_theme_constant_override("outline_size", 4)
	toast_label.visible = false
	toast_label.z_index = 3
	field.add_child(toast_label)
	_build_top_bar()
	_build_caption()
	_build_controls()
	_build_end_card()
	_build_message()
	selection.changed.connect(_on_selection)


func _build_top_bar() -> void:
	var top := ColorRect.new()
	top.name = "TopBar"
	top.color = UiPalette.PANEL_RAISED
	top.size = Vector2(BASE.x, TOP_H)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(top)
	title_label = _label("", 20, UiPalette.TEXT_PRIMARY)
	title_label.name = "Title"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.position = Vector2(560, 6)
	title_label.size = Vector2(480, 26)
	title_label.clip_text = true
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	top.add_child(title_label)
	round_label = _label("", 18, UiPalette.GILT)
	round_label.name = "RoundLabel"
	round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	round_label.position = Vector2(560, 34)
	round_label.size = Vector2(480, 24)
	round_label.tooltip_text = TooltipText.plain("Rounds", "A battle is fought in rounds. Every fighter attacks once a round, damage lands at the end of the round, then each side checks its morale.")
	round_label.mouse_filter = Control.MOUSE_FILTER_PASS
	top.add_child(round_label)
	CodexLink.attach(round_label, "battle_rounds", codex_requested.emit)
	center_chip = _label("", 13, UiPalette.TEXT_SECONDARY)
	center_chip.name = "TerrainNote"
	center_chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_chip.position = Vector2(560, 60)
	center_chip.size = Vector2(480, 20)
	center_chip.mouse_filter = Control.MOUSE_FILTER_PASS
	top.add_child(center_chip)
	for k in 2:
		var x := 24.0 if k == 0 else BASE.x - 24.0 - 520.0
		var plaque := _label("", 18, UiPalette.TEXT_PRIMARY)
		plaque.name = "Plaque%d" % k
		plaque.position = Vector2(x + (30.0 if k == 0 else 0.0), 4)
		plaque.size = Vector2(300, 26)
		plaque.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if k == 0 else HORIZONTAL_ALIGNMENT_RIGHT
		if k == 1:
			plaque.position.x = x + 520.0 - 30.0 - 300.0
		plaque.mouse_filter = Control.MOUSE_FILTER_PASS
		top.add_child(plaque)
		plaque_labels.append(plaque)
		var chips := HBoxContainer.new()
		chips.name = "Chips%d" % k
		chips.add_theme_constant_override("separation", 6)
		chips.position = Vector2(x + (330.0 if k == 0 else 0.0), 6)
		chips.size = Vector2(190, 22)
		chips.alignment = BoxContainer.ALIGNMENT_BEGIN if k == 0 else BoxContainer.ALIGNMENT_END
		top.add_child(chips)
		chip_boxes.append(chips)
		var b := BattleStrengthBar.new()
		b.name = "StrengthBar%d" % k
		b.position = Vector2(x, 34)
		b.size = Vector2(520, 22)
		top.add_child(b)
		bars.append(b)
		var t := _label("", 14, UiPalette.TEXT_SECONDARY)
		t.name = "StrengthText%d" % k
		t.position = Vector2(x + (30.0 if k == 0 else 0.0), 60)
		t.size = Vector2(490, 20)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if k == 0 else HORIZONTAL_ALIGNMENT_RIGHT
		t.mouse_filter = Control.MOUSE_FILTER_PASS
		top.add_child(t)
		bar_texts.append(t)
		CodexLink.attach(b, "battle_strength", func(key): codex_requested.emit(key))
		CodexLink.attach(t, "battle_strength", func(key): codex_requested.emit(key))
		var tag := _label("", 16, UiPalette.GILT)
		tag.name = "MoraleTag%d" % k
		tag.position = Vector2(x, TOP_H + 4.0)
		tag.size = Vector2(520, 22)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if k == 0 else HORIZONTAL_ALIGNMENT_RIGHT
		BattleStrengthBar.style_tag(tag)
		tag.z_index = 3
		frame.add_child(tag)
		tag_labels.append(tag)


func _build_caption() -> void:
	var strip := PanelContainer.new()
	caption_strip = strip
	strip.name = "CaptionStrip"
	strip.position = Vector2(0, TOP_H + FIELD_H)
	strip.size = Vector2(BASE.x, CAPTION_H)
	var style := StyleBoxFlat.new()
	style.bg_color = UiPalette.PANEL_BG
	style.border_color = UiPalette.PANEL_BORDER
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	strip.add_theme_stylebox_override("panel", style)
	frame.add_child(strip)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	strip.add_child(line)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(col)
	hint_button = Button.new()
	hint_button.name = "GotIt"
	hint_button.text = "Got it"
	hint_button.tooltip_text = "Hide this hint for good. The legend (L) explains every mark on the screen."
	hint_button.focus_mode = Control.FOCUS_NONE
	hint_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hint_button.add_theme_font_size_override("font_size", 15)
	hint_button.pressed.connect(_on_hint_seen)
	hint_button.visible = false
	line.add_child(hint_button)
	for k in 2:
		var l := _label("", 18, UiPalette.TEXT_PRIMARY if k == 0 else UiPalette.TEXT_SECONDARY)
		l.name = "Caption%d" % k
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		col.add_child(l)
		caption_labels.append(l)


func _build_controls() -> void:
	controls = BattleControls.new()
	controls.position = Vector2(0, TOP_H + FIELD_H + CAPTION_H)
	controls.selection = selection
	frame.add_child(controls)
	scrubber = controls.scrubber
	buttons = controls.buttons
	moment_buttons = controls.moment_buttons
	controls.why_toggled.connect(_set_why_open)
	controls.legend_toggled.connect(_set_legend_open)
	controls.close_requested.connect(close)
	controls.codex_requested.connect(codex_requested.emit)
	controls.pin_requested.connect(func(_fid): if not _why_open: controls.set_why(true, false))
	why_panel = BattleWhyPanel.new()
	why_panel.position = Vector2(WHY_X, TOP_H)
	why_panel.z_index = 3
	why_panel.codex_requested.connect(codex_requested.emit)
	why_panel.close_requested.connect(func(): controls.set_why(false))
	frame.add_child(why_panel)
	legend = BattleLegend.new()
	legend.z_index = 5
	legend.visible = false
	legend.set_rows(BattleLegend.overlay_rows() + BattleLegend.field_rows())
	legend.codex_requested.connect(codex_requested.emit)
	legend.close_requested.connect(func(): controls.set_legend(false))
	frame.add_child(legend)


func _build_end_card() -> void:
	end_card = PanelContainer.new()
	end_card.name = "ResultCard"
	end_card.position = Vector2(300, TOP_H + 40)
	end_card.size = Vector2(1000, 0)
	end_card.custom_minimum_size = Vector2(1000, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = UiPalette.PANEL_BG
	style.border_color = UiPalette.GILT
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(22)
	end_card.add_theme_stylebox_override("panel", style)
	end_card.visible = false
	end_card.z_index = 4
	frame.add_child(end_card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	end_card.add_child(col)
	end_result = _label("", 26, UiPalette.GILT)
	end_result.name = "ResultLabel"
	end_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	end_result.custom_minimum_size.x = 950
	col.add_child(end_result)
	end_why = _label("", 18, UiPalette.TEXT_PRIMARY)
	end_why.name = "WhyLabel"
	end_why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	end_why.custom_minimum_size.x = 950
	end_why.mouse_filter = Control.MOUSE_FILTER_PASS
	col.add_child(end_why)
	end_chips = HFlowContainer.new()
	end_chips.name = "WhyChips"
	end_chips.add_theme_constant_override("h_separation", 8)
	col.add_child(end_chips)
	end_lines = VBoxContainer.new()
	end_lines.name = "Lines"
	end_lines.add_theme_constant_override("separation", 4)
	col.add_child(end_lines)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	col.add_child(row)
	buttons.again = _button(row, "Watch again", "Watch this battle again from the start (R).", _watch_again)
	buttons.report = _button(row, "Full report", "Open the full battle report.", func(): report_requested.emit(_event_for_report()))
	buttons.next_battle_card = _button(row, "Next battle ▸", "Watch the next battle (N).", func(): controls.next_requested.emit())
	buttons.next_battle_card.visible = false
	buttons.end_close = _button(row, "Close", "Close the battle (Esc).", close)


func _event_for_report() -> Dictionary:
	if not _event.is_empty():
		return _event
	return {"type": "battle", "numbers": {"report": _report, "log": _log}}


func _build_message() -> void:
	message_panel = PanelContainer.new()
	message_panel.name = "Message"
	message_panel.position = Vector2(400, 300)
	message_panel.custom_minimum_size = Vector2(800, 0)
	message_panel.add_theme_stylebox_override("panel", UiPalette.panel_style(24))
	message_panel.visible = false
	message_panel.z_index = 4
	frame.add_child(message_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	message_panel.add_child(col)
	message_label = _label("", 22, UiPalette.TEXT_PRIMARY)
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.custom_minimum_size.x = 750
	col.add_child(message_label)
	_button(col, "Close", "Close (Esc).", close)


## Shrinks `l`'s font from `largest` down to `smallest` until its text fits its width (then trims).
func _fit(l: Label, largest: int, smallest: int) -> void:
	var font := l.get_theme_default_font() if l.get_theme_font("font") == null else l.get_theme_font("font")
	var fs := largest
	while fs > smallest and font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > l.size.x:
		fs -= 1
	l.add_theme_font_size_override("font_size", fs)


func _label(text: String, font_size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _chip(text: String, tip: String) -> Label:
	var l := _label(text, 13, UiPalette.TEXT_PRIMARY)
	var style := StyleBoxFlat.new()
	style.bg_color = UiPalette.PANEL_BG
	style.border_color = UiPalette.GILT
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	l.add_theme_stylebox_override("normal", style)
	l.tooltip_text = tip
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	return l


func _button(parent: Control, text: String, tip: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(0, 44)
	b.add_theme_font_size_override("font_size", 17)
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(action)
	parent.add_child(b)
	return b
