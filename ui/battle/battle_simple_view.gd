class_name BattleSimpleView
extends Control
## The Simple view: a battle played back as two armies of portrait cards facing each other (M3-3, #58, as
## re-scoped by design/3D_DIRECTION.md §7.6; design/M3_BATTLES.md §3-§5, §7.4). It is one subscriber of a
## BattlePlayer: the player owns the clock, the beats and the state, and this view only draws them, so the
## 3D stage can replace the field later and keep the same player. It reads the log, the report, static data
## (Art, RulesCodex, the resolver's constants) and its own settings, and never changes the game.
##
## Screen (UX-8, #221, design/UX_WAR_TABLE.md §6): laid out over the whole view at any size (1600 x 900 base; 1280 x
## 720 at a 125% interface), everything over a full-bleed stage:
##   the stage    full-bleed: the backdrop fills the view; the cards (BattleLayout) and effects stand in the stage's
##                free band (stage_band(): under the plates, above the caption and the controls, left of the docked
##                why panel); the round banner and a key moment's line at the band's top
##   side plates  top left and top right (TableHud's plaque look): the side's name (and its people), a role chip
##                (defending, attacking, storming...), the strength bar with its break notch, and "hp · morale ·
##                breaks at N hp"; each side's morale tag hangs under its plate
##   the centre   top, between the plates: the battle's name and turn, the round, the condition chips (terrain,
##                fort or walls, or the note that nobody defends)
##   the caption  one plate in the lower third, above the controls: the round's caption (BattleCaptions), each line
##                linked to its codex entry; before round 1 the first-visit hint with its Got it button (remembered)
##   controls     BattleControls (M3-4, laid out by UX-8): the bottom bar (Restart, Play/Pause, 1x 2x 4x, the
##                scrubber with round ticks and a clickable marker per key moment, Skip to end, Legend, Settings,
##                Close), the queue row above it with more than one battle, and the Why tab on the right edge
##   why panel    BattleWhyPanel (M3-4), WHY_W wide down the right edge under the plates. Docked, the stage's band
##                narrows beside it; when the battle only fits the narrow band as a crowd, the panel floats over the
##                full-width band instead (§3.4).
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
## UX-8: the margin round the view's edge, the side plates' height, width range and gap to the centre, and the room
## the caption keeps above the controls. HUD_TOP is where the stage's free band starts (under the plates).
const MARGIN := 16.0
const SIDE_PLATE_H := 92.0
const SIDE_PLATE_MAX_W := 500.0
const SIDE_PLATE_MIN_W := 340.0
## #265: a side plate's least width when more than two share the top bar (264 at a 1280-wide view with three, less when the
## centre's words need more room: a long condition chip with no short words, as outside a besieged fort's walls).
const MANY_PLATE_MIN_W := 180.0
const SIDE_PLATE_GAP := 12.0
const CENTRE_MIN_W := 420.0
const HUD_TOP := MARGIN + SIDE_PLATE_H + 8.0
const CAPTION_RESERVE := 78.0
const CAPTION_GAP := 10.0
const CAPTION_MAX_W := 1100.0
## The view's height from which the result card keeps its full-size words.
const END_TALL := 850.0
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
## The why panel's width (§3.1).
const WHY_W := 384.0
const DEPLOY_LINE := "Before round 1: the armies deploy. Press Space to play, or L for what every mark means."
## The condition chips' gap.
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
var _sheet_hits := {}  # VFX-WIRE: event index -> true for a hit whose impact sheet started at its attack_started
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
var _band_last := Rect2()
var _loading := false
var _centre_w := 0.0  # #265: with more than two sides, the width the centre plate is given between the halves' plates
var _centre_need := 0.0  # #265: and the width its words need (the condition chips in their short words), at least CENTRE_MIN_W

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
## UX-8: the side plates (left, right), each with its name label, role chip, strength bar and text.
var plates: Array = []
var plaque_labels: Array = []
var role_chips: Array = []
var bars: Array = []
var bar_texts: Array = []
var tag_labels: Array = []
## UX-8: the centre plate (title, round, condition chips) and its row of condition chips; center_chip is the note
## that nobody defends (or the battle's place at the walls), shown as a chip in that row.
var centre: PanelContainer
var conditions: HBoxContainer
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
	resized.connect(_layout)
	_layout()


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
	_held_by = _per_side(-1)
	_ensure_plates(_log.sides.size())
	if player != null:
		_disconnect_player()
	player = BattlePlayer.new(_log, _report)
	player.reduced_motion = reduced_motion
	player.beat.connect(_on_beat)
	player.seeked.connect(_on_seeked)
	controls.bind(player, st)
	_loading = true
	_why_docks = not BattleLayout.build(_log, Vector2(view_size().x - WHY_W, stage_band().size.y)).crowd
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
	_show_result(false)
	_set_caption([])
	_last_time = 0.0
	_on_seeked(player.live_state())
	_loading = false
	_band_last = stage_band()
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


## The side plate where side `si` is shown: with two sides the left (0) or the right (1) one; with more (#265), its place in
## the layout's plate order (the left half's sides, then the right's).
func plate_of(si: int) -> int:
	return _slot_of_side(si)


func _slot_of_side(si: int) -> int:
	var order: Array = layout.get("order", [])
	if order.size() >= 3:
		return maxi(0, order.find(si))
	return 0 if si == int(layout.get("left", 0)) else 1


## How many side plates the battle on screen uses: one a side, never fewer than the two of the top bar.
func plates_used() -> int:
	return maxi(2, (_log.get("sides", []) as Array).size())


## #265: the plates on the top bar's left half and on its right: [[plate indices], [plate indices]]. Two sides: [[0], [1]];
## more: the layout's halves, in plate order.
func plate_groups() -> Array:
	var n := plates_used()
	if n <= 2:
		return [[0], [1]]
	var groups: Array = layout.get("groups", [])
	var on_left := (groups[0] as Array).size() if groups.size() == 2 and (layout.get("order", []) as Array).size() == n else n - 1
	return [range(on_left), range(on_left, n)]


## Whether plate `k` is on the top bar's right half (its bar mirrored, its words to the right).
func plate_on_right(k: int) -> bool:
	return (plate_groups()[1] as Array).has(k)


## An Array with `value` for each side of the battle on screen.
func _per_side(value: Variant) -> Array:
	var out := []
	out.resize((_log.get("sides", []) as Array).size())
	out.fill(value)
	return out


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
	for k in tag_labels.size():
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
				# VFX-WIRE: the ruler's fall plays its sheet from its hit_frame (a death is not known ahead)
				var fall := VfxSheets.sheet(VfxSheets.for_moment("ruler_fall"))
				effects.add_impact(_upper(c), _scale() * 1.2, true, not reduced_motion and _flash.allow(_real), reduced_motion,
					VfxSheets.for_moment("ruler_fall"), VfxSheets.lead(fall))
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
	# VFX-WIRE (#242): a hit's impact sheet starts its lead-in now, so its hit_frame meets the blow (playback knows when it lands)
	if b.data.hit and not reduced_motion:
		var sid := BattleEffects.impact_sheet(b.data)
		var sh := VfxSheets.sheet(sid)
		if not sh.is_empty() and effects.add_impact(_upper(t), _scale(), bool(b.data.big), _flash.allow(_real), false, sid,
				VfxSheets.lead(sh) - float(b.data.delay)):
			_sheet_hits[int(b.event)] = true
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
		if not _sheet_hits.erase(int(b.event)):  # its sheet already started with the blow's lead-in
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
	_sheet_hits.clear()
	_animating.clear()
	_shake_t = -1.0
	stage.position = Vector2.ZERO
	_banner_t = -1.0
	banner_label.visible = false
	_toast_t = -1.0
	toast_label.visible = false
	for k in tag_labels.size():
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
	_show_result(false)
	controls.tick()


## Who Iron Discipline held each side with at `st` (the side's last morale check before it).
func _held_by_at(st: Dictionary) -> Array:
	var out := _per_side(-1)
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


## Tab order (§5.3): the left side first, then the right (#265: with more sides, plate by plate); each side front rank
## to back line, each rank front column first, top to bottom.
func _tab_order() -> Array:
	var ids := []
	for f in _log.fighters:
		ids.append(int(f.id))
	ids.sort_custom(func(a, b):
		var sa: Dictionary = layout.slots[a]
		var sb: Dictionary = layout.slots[b]
		var ka := [_slot_of_side(int(sa.side)), int(sa.tier), int(sa.col), int(sa.row), a]
		var kb := [_slot_of_side(int(sb.side)), int(sb.tier), int(sb.col), int(sb.row), b]
		for k in ka.size():
			if ka[k] != kb[k]:
				return ka[k] < kb[k]
		return false)
	return ids


# --- the why panel and the legend -----------------------------------------------------------------

## The view's size: the control's own (the window, under the host), or BASE before it has one.
func view_size() -> Vector2:
	return size if size.x > 10.0 and size.y > 10.0 else BASE


## The stage band's width: narrowed while the why panel is docked (§3.1), the whole view when it floats or is closed.
func field_width() -> float:
	return view_size().x - WHY_W if _why_open and _why_docks else view_size().x


## UX-8: the stage's free band, in the view's (and the field's) coordinates: under the plates, above the caption and
## the controls, left of the docked why panel. The cards stand in it; the 3D stage frames the battle in it.
func stage_band() -> Rect2:
	var bottom := view_size().y - controls.bottom_reserve() - CAPTION_RESERVE
	return Rect2(0.0, HUD_TOP, field_width(), maxf(120.0, bottom - HUD_TOP))


## The part of the band the why panel leaves free, docked or floating: the caption, the queue row and the result card
## centre on it.
func free_band() -> Rect2:
	var band := stage_band()
	if _why_open:
		band.size.x = minf(band.size.x, view_size().x - WHY_W)
	return band


## The side plates' width at this view's width: as wide as SIDE_PLATE_MAX_W while the centre keeps CENTRE_MIN_W between them.
## #265: with more than two sides every plate shares the row equally (at least MANY_PLATE_MIN_W), leaving the centre the room
## its words need.
func plate_width() -> float:
	var n := plates_used()
	if n > 2:
		var mid := maxf(CENTRE_MIN_W, _centre_need)
		return clampf(floorf((view_size().x - 2.0 * MARGIN - float(n) * SIDE_PLATE_GAP - mid) / float(n)), MANY_PLATE_MIN_W, SIDE_PLATE_MAX_W)
	return clampf(floorf((view_size().x - 2.0 * MARGIN - 2.0 * SIDE_PLATE_GAP - CENTRE_MIN_W) / 2.0), SIDE_PLATE_MIN_W, SIDE_PLATE_MAX_W)


## Where side plate `k` stands on the top bar now (the view's coordinates).
func plate_rect(k: int) -> Rect2:
	var v := view_size()
	var pw := plate_width()
	var groups := plate_groups()
	var left: Array = groups[0]
	var right: Array = groups[1]
	if left.has(k):
		return Rect2(MARGIN + left.find(k) * (pw + SIDE_PLATE_GAP), MARGIN, pw, SIDE_PLATE_H)
	var from_end := right.size() - right.find(k)
	return Rect2(v.x - MARGIN - from_end * pw - (from_end - 1) * SIDE_PLATE_GAP, MARGIN, pw, SIDE_PLATE_H)


## Where side plate `k`'s morale tag hangs: under its plate, on its plate's side, left of the docked why panel (field `fw`).
func _tag_rect(k: int, fw: float) -> Rect2:
	var pr := plate_rect(k)
	var y := MARGIN + SIDE_PLATE_H + 6.0
	if plates_used() <= 2:
		var tw := minf(520.0, fw / 2.0 - MARGIN - 8.0)
		return Rect2(MARGIN if k == 0 else fw - MARGIN - tw, y, tw, 22.0)
	return Rect2(minf(pr.position.x, fw - MARGIN - pr.size.x), y, pr.size.x, 22.0)


func _set_why_open(on: bool) -> void:
	_why_open = on
	_layout()
	if on:
		why_panel.refresh()


## The legend opens over the whole stage and the why panel (it is modal: L, Esc or its x closes it).
func _set_legend_open(on: bool) -> void:
	legend.visible = on
	_place_legend()


func _place_legend() -> void:
	var v := view_size()
	legend.place(Rect2(MARGIN, HUD_TOP, v.x - 2.0 * MARGIN, v.y - BattleControls.BAR_H - BattleControls.GAP - HUD_TOP))


## Lays the screen out for the view's size and field_width(): the full-bleed stage and the band in it, the plates, the
## centre, the tags, the caption, the controls, the why panel, the result card and the legend. When the band moved
## (a resize, the why panel docking or closing, the queue row), the battle on it is laid out again (_band_changed).
func _apply_width() -> void:
	_layout()


func _layout() -> void:
	if frame == null:
		return
	var v := view_size()
	var fw := field_width()
	var band := stage_band()
	frame.position = Vector2.ZERO
	frame.size = v
	field.position = Vector2.ZERO
	field.size = v
	stage.size = v
	backdrop.size = v
	backdrop.horizon = band.position.y + BattleBackdrop.HORIZON_H * band.size.y / 600.0
	backdrop.span_w = fw
	for n in [cards_layer, effects]:
		(n as Control).position = band.position
		(n as Control).size = band.size
	banner_label.position = Vector2(0, band.position.y + 14.0)
	banner_label.size.x = fw
	toast_label.position = Vector2(200, band.position.y + 54.0)
	toast_label.size.x = maxf(200.0, fw - 400.0)
	# The plates in the top corners, the centre between them.
	_place_plates(fw)
	_fit_texts()
	_place_caption()
	why_panel.visible = _why_open
	var wy := HUD_TOP
	why_panel.position = Vector2(v.x - WHY_W, wy)
	why_panel.custom_minimum_size = Vector2(WHY_W, v.y - BattleControls.BAR_H - BattleControls.GAP - wy)
	why_panel.size = why_panel.custom_minimum_size
	var free := free_band()
	controls.fit(v, free, free.end.x)
	_fit_end_card(free)
	message_panel.position = Vector2(roundf(free.position.x + (free.size.x - message_panel.custom_minimum_size.x) / 2.0), free.position.y + 120.0)
	_place_legend()
	var changed := band != _band_last
	_band_last = band
	if changed and player != null and not _loading and not _log.is_empty():
		_band_changed()


## The band moved under a battle on screen: lay its cards out again on the same state.
func _band_changed() -> void:
	var end_shown := end_card.visible
	_build_field()
	selection.order = _tab_order()
	_on_seeked(player.live_state())
	_show_result(end_shown)
	var c := card(_selected)
	if c != null:
		c.selected = true


## Lays the side plates, their morale tags and the centre out: the plates plates_used() needs, each where plate_rect() puts
## it (with two sides, the top corners), its tag under it, the centre between the halves; any plate a battle with more sides
## left is hidden. #265: with more than two sides a tag wraps to a second line within its plate's width, so the tags of a
## round's morale checks never overlap.
func _place_plates(fw: float) -> void:
	var n := plates_used()
	for k in plates.size():
		var plate: PanelContainer = plates[k]
		var tag: Label = tag_labels[k]
		plate.visible = k < n
		if k >= n:
			tag.text = ""
			continue
		var pr := plate_rect(k)
		plate.position = pr.position
		plate.size = pr.size
		tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if n > 2 else TextServer.AUTOWRAP_OFF
		tag.max_lines_visible = 2 if n > 2 else -1
		var tr := _tag_rect(k, fw)
		tag.size.x = tr.size.x
		tag.position = tr.position
	if n <= 2:
		var cx := MARGIN + plate_width() + SIDE_PLATE_GAP
		centre.position = Vector2(cx, MARGIN)
		centre.size = Vector2(view_size().x - 2.0 * cx, 0.0)
		return
	var groups := plate_groups()
	var c0 := plate_rect(int((groups[0] as Array)[-1])).end.x + SIDE_PLATE_GAP
	var c1 := plate_rect(int((groups[1] as Array)[0])).position.x - SIDE_PLATE_GAP
	_centre_w = c1 - c0
	centre.position = Vector2(c0, MARGIN)
	centre.size = Vector2(_centre_w, 0.0)


## #265: makes sure the top bar has `n` side plates (two are built with the view; a battle with more sides adds the rest,
## which a later battle with fewer hides).
func _ensure_plates(n: int) -> void:
	while plates.size() < n:
		_build_plate(plates.size())
	while _tag_t.size() < tag_labels.size():
		_tag_t.append(-1.0)


## Turns plate `k` to its half of the top bar: on the right, its role chip before its name and its words to the right (its
## bar mirrored by _fill_top_bar); on the left, the other way round. Plate 0 is built for the left and plate 1 for the right,
## as two sides always use them.
func _orient_plate(k: int, right: bool) -> void:
	var name_label: Label = plaque_labels[k]
	var head := name_label.get_parent() as HBoxContainer
	head.alignment = BoxContainer.ALIGNMENT_END if right else BoxContainer.ALIGNMENT_BEGIN
	head.move_child(role_chips[k], 0 if right else 1)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT
	(bar_texts[k] as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT
	(tag_labels[k] as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT


## The plates' names (shrunk to fit beside the role chip), the title (shrunk to the centre) and the condition chips
## (their short words when the full ones don't fit).
func _fit_texts() -> void:
	var inner := plate_width() - 20.0
	for k in plates_used():
		var chip: Label = role_chips[k]
		var cw := _font_of(chip).get_string_size(chip.text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size_of(chip, UiPalette.TYPE_SMALL)).x + 14.0 if chip.visible else 0.0
		var l: Label = plaque_labels[k]
		l.size.x = maxf(80.0, inner - cw - 8.0)
		_fit(l, UiPalette.TYPE_NAME, UiPalette.TYPE_SMALL + 1)
	var many := plates_used() > 2
	var cin := (_centre_w if many else centre.size.x) - 20.0
	title_label.size.x = cin
	_fit(title_label, UiPalette.TYPE_NAME, UiPalette.TYPE_SMALL + 1)
	var chips := conditions.get_children().filter(func(c): return (c as Control).visible)
	for words in ["full", "short"]:
		for c in chips:
			(c as Label).text = String((c as Label).get_meta(words, (c as Label).text))
		if chips_width(chips) <= cin:
			break
	if many:
		centre.size = Vector2(_centre_w, 0.0)  # #265: back to its width once the chips have their words


## #265: the width the centre plate's words need with more than two sides: its condition chips in their short words, and its
## padding (CENTRE_MIN_W at least, enough for the title and the round).
func _centre_words_w() -> float:
	var chips := conditions.get_children().filter(func(c): return (c as Control).visible)
	var saved := chips.map(func(c): return (c as Label).text)
	for c in chips:
		(c as Label).text = String((c as Label).get_meta("short", (c as Label).text))
	var w := chips_width(chips) + 24.0
	for k in chips.size():
		(chips[k] as Label).text = String(saved[k])
	return maxf(CENTRE_MIN_W, w)


## The caption plate: as wide as its words (at most the free band, less a margin), centred on the free band, its foot
## CAPTION_GAP above the controls. A line too long for that wraps to a second line (no more), and the plate grows upward.
func _place_caption() -> void:
	var band := free_band()
	var v := view_size()
	var got := 0.0
	if hint_button.visible:
		got = 12.0 + _font_of(hint_button).get_string_size(hint_button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 24.0
	var widest := 0.0
	for k in 2:
		var l: Label = caption_labels[k]
		if not l.text.is_empty():
			widest = maxf(widest, _font_of(l).get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size_of(l, 18)).x)
	var w := clampf(widest + got + 32.0, 240.0, minf(CAPTION_MAX_W, band.size.x - 2.0 * MARGIN))
	var inner := w - got - 30.0
	var h := 14.0
	for k in 2:
		var l: Label = caption_labels[k]
		l.visible = k == 0 or not l.text.is_empty()
		if not l.visible:
			continue
		var fs := _font_size_of(l, 18)
		var line_h := _font_of(l).get_height(fs)
		var lines := 1
		if not l.text.is_empty():
			lines = clampi(ceili(_font_of(l).get_multiline_string_size(l.text, HORIZONTAL_ALIGNMENT_CENTER, inner, fs).y / line_h - 0.01), 1, 2)
		l.custom_minimum_size = Vector2(inner, line_h * lines)
		h += line_h * lines
	caption_strip.custom_minimum_size = Vector2(w, h)
	caption_strip.size = Vector2(w, h)
	caption_strip.position = Vector2(roundf(band.position.x + (band.size.x - w) / 2.0), v.y - controls.bottom_reserve() - CAPTION_GAP - h)


## Shows or hides the result card. It stands in for the caption while it is up (its why and lines say it all).
func _show_result(on: bool) -> void:
	end_card.visible = on
	caption_strip.visible = not on


## The result card: at most 1000 wide, inside the band, near its top; in a short view (under END_TALL) its words a size
## smaller and it hangs just under the plates, so it stays above the controls.
func _fit_end_card(band: Rect2) -> void:
	var w := minf(1000.0, band.size.x - 48.0)
	end_card.custom_minimum_size.x = w
	end_card.size.x = w
	var tall := view_size().y >= END_TALL
	end_result.add_theme_font_size_override("font_size", 26 if tall else 22)
	end_why.add_theme_font_size_override("font_size", 18 if tall else 16)
	for l in [end_result, end_why] + end_lines.get_children():
		(l as Control).custom_minimum_size.x = w - 50.0
	for l in end_lines.get_children():
		(l as Label).add_theme_font_size_override("font_size", 17 if tall else 15)
	end_card.position = Vector2(roundf(band.position.x + (band.size.x - w) / 2.0), band.position.y + (24.0 if tall else 4.0))


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
		var at := mb.position - frame.position - field.position
		if Rect2(Vector2.ZERO, Vector2(field_width(), view_size().y)).has_point(at):
			selection.clear()


func _handled() -> void:
	if is_inside_tree():
		get_viewport().set_input_as_handled()


func _watch_again() -> void:
	_show_result(false)
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
		elif k == 1 and lines.is_empty() and not garrison_caption().is_empty():
			# MVP-3 (#177): a battle against a neutral province's garrison says what the Free Holds are and what they hold.
			l.text = garrison_caption()
			l.tooltip_text = TooltipText.plain("The Free Holds", RulesCodex.text("independents"))
			CodexLink.attach(l, "independents", codex_requested.emit)
		else:
			l.text = ""
			l.tooltip_text = ""
	hint_button.visible = lines.is_empty() and not _hint_seen
	_place_caption()


## MVP-3 (#177): the line under a garrison battle's first caption, before the first blow: who the Free Holds are, that they hold the
## ground, and what that gives them. "" for any other battle. A neutral fort's battle gets the walls' caption on the 3D stage
## instead (BattleWalls.caption_text), which says the same about the fort.
func garrison_caption() -> String:
	return garrison_caption_for(_log)


static func garrison_caption_for(battle_log: Dictionary) -> String:
	if battle_log.is_empty() or String(battle_log.get("defender", "")) != IndependentData.FACTION_ID or battle_log.get("kind", "province") != "province":
		return ""
	var name := IndependentData.FACTION_NAME
	for side in battle_log.get("sides", []):
		if String(side.get("faction", "")) == IndependentData.FACTION_ID:
			name = String(side.get("name", name))
	var pids: Array = battle_log.get("provinces", [])
	var place := BattleBackdrop.province_name(String(pids[0])) if not pids.is_empty() else "the province"
	var ground := AutoBattleResolver.ground_words(String(battle_log.get("terrain", "")))
	var fort := ""
	if battle_log.get("fort", false) and not battle_log.has("siege"):
		fort = ", and its fort +%d defense" % AutoBattleResolver.FORT_DEFENSE
	return "The %s, the neutral land's own fighters, hold %s (%s%s)." % [name, place, ground if not ground.is_empty() else "no terrain bonus", fort]


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
	_show_result(false)


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
	_show_result(true)
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
		var l := _label(String(line), 17 if view_size().y >= END_TALL else 15, UiPalette.TEXT_PRIMARY)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = end_card.custom_minimum_size.x - 50.0  # so a new line never measures itself one word wide and stretches the card
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
			out.append(TurnReportText.readable_aftermath(String(e.text)))
	return out


func _result_sentence() -> String:
	if _log.sides.size() > 2 and BattleLog.find_event(_log, "end") >= 0:
		return BattleWhy.result_sentence(_log)  # #265: who left the field and when, every side by name
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

func _build_field() -> void:
	for c in cards_layer.get_children():
		cards_layer.remove_child(c)
		c.queue_free()
	effects.clear()
	layout = BattleLayout.build(_log, stage_band().size)
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
	var border: bool = _log.get("kind", "province") == "border"
	var defender := String(_log.get("defender", ""))
	for c in conditions.get_children():
		if c != center_chip:
			conditions.remove_child(c)
			c.queue_free()
	for k in plates_used():
		_orient_plate(k, plate_on_right(k))
	for si in _log.sides.size():
		var k := _slot_of_side(si)
		var side: Dictionary = _log.sides[si]
		var role := "on the border" if border else ("defending" if side.get("defender", false) else ("attacking" if not defender.is_empty() else "arrived"))
		if not border and not _siege_block().is_empty():
			role = FortView.siege_role(_siege_block(), si)  # M3c S-3: "storming", "sallying garrison", "garrison, in the breach"...
		var people := String(side.get("people", {}).get("name", "")) if side.get("people", {}) is Dictionary else ""
		plaque_labels[k].text = "%s · %s" % [side.name, people] if not people.is_empty() else String(side.name)
		var people_words := " Its people: %s." % people if not people.is_empty() else ""
		plaque_labels[k].tooltip_text = TooltipText.plain(String(side.name), "%s, %s. %s%s" % [SeatEmblem.describe(_side_seat[si]).capitalize(),
			_role_words(side, border, defender), _army_words(side), people_words])
		var chip: Label = role_chips[k]
		chip.text = role
		chip.tooltip_text = TooltipText.plain(role.capitalize(), _role_words(side, border, defender).capitalize() + ".")
		var b: BattleStrengthBar = bars[k]
		b.seat = _side_seat[si]
		b.mirrored = plate_on_right(k)
		if side.get("defender", false) and not border:
			var terrain := String(_log.get("terrain", ""))
			var bonus: Dictionary = AutoBattleResolver.TERRAIN.get(terrain, {})
			if int(bonus.get("defense", 0)) > 0:
				var text := "%s: +%d defense" % [terrain.capitalize(), int(bonus.defense)]
				if int(bonus.get("attack", 0)) > 0:
					text += " and +%d attack" % int(bonus.attack)
				var chip2 := _chip(text, TooltipText.plain("Terrain", "The defender of a %s province gets %s." % [terrain, text.substr(text.find(":") + 2)]))
				var short := "%s +%d def" % [terrain.capitalize(), int(bonus.defense)] + (", +%d atk" % int(bonus.attack) if int(bonus.get("attack", 0)) > 0 else "")
				chip2.set_meta("full", text)
				chip2.set_meta("short", short)
				conditions.add_child(chip2)
				CodexLink.attach(chip2, TooltipText.codex_for(TooltipText.terrain_kind(terrain)), codex_requested.emit)
			var walls := FortView.siege_chip(_siege_block())
			if not walls.is_empty():  # M3c S-3 (§9.7): a stormed garrison's walls replace the fort's old +2
				var wchip := _chip(String(walls.text), String(walls.tip))
				wchip.name = "SiegeChip"
				wchip.set_meta("full", wchip.text)  # #125: "Walls +3 def" where the full words don't fit (_fit_texts)
				wchip.set_meta("short", String(walls.get("short", wchip.text.get_slice(" (", 0).replace(": ", " ").replace(" defense", " def"))))
				conditions.add_child(wchip)
				CodexLink.attach(wchip, String(walls.codex), codex_requested.emit)
			elif _log.get("fort", false):
				var fchip := _chip("Fort: +%d defense" % AutoBattleResolver.FORT_DEFENSE, TooltipText.plain("Fort", "Only a defender gets a fort's bonus: +%d defense to every fighter." % AutoBattleResolver.FORT_DEFENSE))
				fchip.set_meta("full", fchip.text)
				fchip.set_meta("short", "Fort +%d def" % AutoBattleResolver.FORT_DEFENSE)
				conditions.add_child(fchip)
				CodexLink.attach(fchip, "fort", codex_requested.emit)
	var open := FortView.siege_chip(_siege_block())
	CodexLink.detach(center_chip)
	if border:
		center_chip.text = "Border battle: nobody defends, no terrain bonus"
	elif defender.is_empty() and not open.is_empty():
		center_chip.text = String(open.text)  # M3c S-3 (§9.7): outside the walls, or through the breach
	elif defender.is_empty():
		center_chip.text = "Nobody was defending: no terrain bonus"
	else:
		center_chip.text = ""
	center_chip.visible = not center_chip.text.is_empty()
	center_chip.set_meta("full", center_chip.text)
	if border:
		center_chip.set_meta("short", "Border: nobody defends")
	elif defender.is_empty() and not open.is_empty():
		center_chip.set_meta("short", String(open.get("short", center_chip.text)))
	else:
		center_chip.set_meta("short", "Nobody defends: no bonus")
	center_chip.tooltip_text = TooltipText.plain("Terrain", "Only a side that already held the province gets its terrain and fort bonus. Here nobody did.") if center_chip.visible else ""
	if center_chip.visible and defender.is_empty() and not open.is_empty() and not border:
		center_chip.tooltip_text = String(open.tip)
		CodexLink.attach(center_chip, String(open.codex), codex_requested.emit)
	elif center_chip.visible:
		CodexLink.attach(center_chip, "battle_terrain", codex_requested.emit)
	conditions.visible = conditions.get_children().any(func(c): return (c as Control).visible)
	if plates_used() > 2:
		# #265: the plates follow the field's halves, known once it is laid out, and leave the centre its words' room
		_centre_need = _centre_words_w()
		_place_plates(field_width())
	_fit_texts()


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
	var many := (_log.get("sides", []) as Array).size() > 2  # #265: more than one enemy
	if border:
		return "met the other sides' armies on the border as they tried to cross it" if many else "met the enemy on the border as both armies tried to swap places"
	if not _siege_block().is_empty():  # M3c S-3: its role at the fort and what it meant
		var si := (_log.get("sides", []) as Array).find(side)
		return "%s: %s" % [FortView.siege_role(_siege_block(), si), String(FortView.role_meaning(_siege_block(), si).text)]
	if side.get("defender", false):
		return "defending: it already held the province"
	if defender.is_empty():
		return "arrived at the same time as the other sides, so nobody defends" if many else "arrived at the same time as the enemy, so nobody defends"
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

	# The field: a clipping window over the whole view (full-bleed, UX-8), a stage inside it that shakes.
	field = Control.new()
	field.name = "Field"
	field.position = Vector2.ZERO
	field.size = BASE
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
	banner_label.position = Vector2(0, HUD_TOP + 14.0)
	banner_label.size = Vector2(BASE.x, 40)
	banner_label.add_theme_color_override("font_outline_color", UiPalette.KEYLINE_INK)
	banner_label.add_theme_constant_override("outline_size", 8)
	banner_label.visible = false
	banner_label.z_index = 3
	field.add_child(banner_label)
	toast_label = _label("", 18, UiPalette.GILT)
	toast_label.name = "MomentToast"
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.position = Vector2(200, HUD_TOP + 54.0)
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
	_layout()


## UX-8: the side plates (top left and right), each side's morale tag under its plate, and the centre between them.
func _build_top_bar() -> void:
	for k in 2:
		_build_plate(k)
	centre = PanelContainer.new()
	centre.name = "Centre"
	centre.add_theme_stylebox_override("panel", TableHud.plaque_style(10, 6))
	centre.mouse_filter = Control.MOUSE_FILTER_STOP
	frame.add_child(centre)
	var mid := VBoxContainer.new()
	mid.add_theme_constant_override("separation", 3)
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.add_child(mid)
	title_label = _label("", UiPalette.TYPE_NAME, UiPalette.TEXT_PRIMARY)
	title_label.name = "Title"
	title_label.add_theme_font_override("font", UiFonts.title())
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.clip_text = true
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	mid.add_child(title_label)
	round_label = _label("", 17, UiPalette.GILT)
	round_label.name = "RoundLabel"
	round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	round_label.tooltip_text = TooltipText.plain("Rounds", "A battle is fought in rounds. Every fighter attacks once a round, damage lands at the end of the round, then each side checks its morale.")
	round_label.mouse_filter = Control.MOUSE_FILTER_PASS
	mid.add_child(round_label)
	CodexLink.attach(round_label, "battle_rounds", codex_requested.emit)
	_build_centre_chips(mid)


## Side plate `k` and its morale tag: plate 0 faces the left half, plate 1 the right (the two of every battle); a plate added
## for a battle with more sides (#265) goes after the last one and is turned to its half by _orient_plate.
func _build_plate(k: int) -> void:
	var right := k == 1
	var after := -1
	if k >= 2:
		after = (tag_labels[-1] as Node).get_index()
	var plate := PanelContainer.new()
	plate.name = "Plate%d" % k
	plate.add_theme_stylebox_override("panel", TableHud.plaque_style(10, 7))
	plate.mouse_filter = Control.MOUSE_FILTER_STOP
	plate.clip_contents = true
	frame.add_child(plate)
	plates.append(plate)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(col)
	var head := HBoxContainer.new()
	head.name = "Head"
	head.add_theme_constant_override("separation", 8)
	head.alignment = BoxContainer.ALIGNMENT_END if right else BoxContainer.ALIGNMENT_BEGIN
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(head)
	var name_label := _label("", UiPalette.TYPE_NAME, UiPalette.TEXT_PRIMARY)
	name_label.name = "Name%d" % k
	name_label.add_theme_font_override("font", UiFonts.name())
	name_label.custom_minimum_size.y = 26
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.mouse_filter = Control.MOUSE_FILTER_PASS
	plaque_labels.append(name_label)
	var role := _chip("", "")
	role.name = "Role%d" % k
	role.add_theme_font_size_override("font_size", UiPalette.TYPE_SMALL)
	role.add_theme_color_override("font_color", UiPalette.GILT)
	role.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	role_chips.append(role)
	if right:
		head.add_child(role)
		head.add_child(name_label)
	else:
		head.add_child(name_label)
		head.add_child(role)
	var b := BattleStrengthBar.new()
	b.name = "StrengthBar%d" % k
	b.custom_minimum_size = Vector2(200, 22)
	col.add_child(b)
	bars.append(b)
	var t := _label("", UiPalette.TYPE_SMALL, UiPalette.TEXT_SECONDARY)
	t.name = "StrengthText%d" % k
	t.add_theme_font_override("font", UiFonts.number())
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT
	t.clip_text = true
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	t.mouse_filter = Control.MOUSE_FILTER_PASS
	col.add_child(t)
	bar_texts.append(t)
	CodexLink.attach(b, "battle_strength", func(key): codex_requested.emit(key))
	CodexLink.attach(t, "battle_strength", func(key): codex_requested.emit(key))
	var tag := _label("", 16, UiPalette.GILT)
	tag.name = "MoraleTag%d" % k
	tag.position = Vector2(MARGIN, HUD_TOP)
	tag.size = Vector2(520, 22)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT
	BattleStrengthBar.style_tag(tag)
	tag.z_index = 3
	frame.add_child(tag)
	tag_labels.append(tag)
	if after >= 0:
		frame.move_child(plate, after + 1)
		frame.move_child(tag, after + 2)
	_plate_added(k)


## A side plate was added (k >= 2 for a battle of more sides, #265); the 3D stage puts its words on a dark backing.
func _plate_added(_k: int) -> void:
	pass


func _build_centre_chips(mid: VBoxContainer) -> void:
	conditions = HBoxContainer.new()
	conditions.name = "Conditions"
	conditions.add_theme_constant_override("separation", int(CHIP_SEPARATION))
	conditions.alignment = BoxContainer.ALIGNMENT_CENTER
	conditions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid.add_child(conditions)
	center_chip = _chip("", "")
	center_chip.name = "TerrainNote"
	center_chip.add_theme_color_override("font_color", UiPalette.TEXT_SECONDARY)
	center_chip.visible = false
	conditions.add_child(center_chip)


## UX-8: the caption, one plate in the lower third (placed by _place_caption): the round's caption, a second quieter
## line when the round has one, and the first-visit hint's Got it.
func _build_caption() -> void:
	var strip := PanelContainer.new()
	caption_strip = strip
	strip.name = "CaptionStrip"
	var style := TableHud.plaque_style(14, 6)
	style.bg_color = Color(UiPalette.PANEL_BG, 0.9)
	strip.add_theme_stylebox_override("panel", style)
	strip.mouse_filter = Control.MOUSE_FILTER_STOP
	strip.clip_contents = true
	frame.add_child(strip)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_child(line)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
		var l := _label("", 18 if k == 0 else 15, UiPalette.TEXT_PRIMARY if k == 0 else UiPalette.TEXT_SECONDARY)
		l.name = "Caption%d" % k
		l.add_theme_font_override("font", UiFonts.body())
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.max_lines_visible = 2  # (no trimming mode: with one, a wrapping label showed one line and its ellipsis at 125%, UX-9's walk)
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		col.add_child(l)
		caption_labels.append(l)


func _build_controls() -> void:
	controls = BattleControls.new()
	controls.selection = selection
	frame.add_child(controls)
	controls.layout_changed.connect(_layout)
	scrubber = controls.scrubber
	buttons = controls.buttons
	controls.why_toggled.connect(_set_why_open)
	controls.legend_toggled.connect(_set_legend_open)
	controls.close_requested.connect(close)
	controls.codex_requested.connect(codex_requested.emit)
	controls.pin_requested.connect(func(_fid): if not _why_open: controls.set_why(true, false))
	why_panel = BattleWhyPanel.new()
	why_panel.position = Vector2(BASE.x - WHY_W, HUD_TOP)
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
	end_card.position = Vector2(300, HUD_TOP + 40)
	end_card.size = Vector2(1000, 0)
	end_card.custom_minimum_size = Vector2(1000, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = UiPalette.PANEL_BG
	style.border_color = UiPalette.GILT
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(22)
	end_card.add_theme_stylebox_override("panel", style)
	_show_result(false)
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
	font_size = maxi(font_size, UiPalette.TYPE_FLOOR)  # UI-FIT (#237): nothing the player reads below the floor
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _chip(text: String, tip: String) -> Label:
	var l := _label(text, 15, UiPalette.TEXT_PRIMARY)
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
