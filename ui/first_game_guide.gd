class_name FirstGameGuide
extends PanelContainer
## MVP-1 (#141): the first-game guide. On the first turn of a person's first game a small card sits in the map's
## top-left corner (under the board hint, over the water and the north-west hills; never a modal: only the card itself
## takes clicks) with one-line steps that tick off from the person's real orders. UX-9 (#234) rewrote them for the War Table: each
## points at the thing to use, where it is:
##   1. march: click an army, then March on its card         (a MoveOrder is queued)
##   2. recruit: click your capital, then Recruit on its card (a RecruitOrder is queued)
##   3. check them: the tray, then the Chronicle's Plan       (the Plan was shown: the seal opens it in a first game, UX-5)
##   4. seal them                                             (the person ended the turn: the card then shows every step
##                                                             ticked for a few seconds, over the board's playback, and goes)
## The next step to do is lit in gilt.
## and a link to the codex's "How to play" entry. In a game with rulers, paths, forts, fog, magic or independents one
## more line per system that is on follows, its name a link to that system's codex entry. Hide closes the card.
## MVP-3 (#177): the fog line stays on the card (it is what the board's "glimpsed" and "never seen" labels mean, and it says
## so in full, which is why the first fog turn's banner no longer stacks beside this card); the lines of the other systems
## fold behind one "Also on: ..." row (click to open them), so the card stays short enough to leave the province next to the
## capital, the natural first move, uncovered. Every explanation is still there: the row's tooltip, each line's tooltip and
## its codex link. UX-1: the Table (TableHud.hang) places the card at the top of the left column under the realm plaque, in the
## board's safe area, with the selection card docked under it, so the board frames the map to the right of both and the card
## never covers it; a playback bar that is in its way moves it down.
## Why top-left: the map's hover forecast bar runs along the bottom, the player's capital (with its armies and queued
## orders) is on the left edge from about 45% of the way down, the fog notice sits top centre, and the turn report, the
## codex and every other overlay are drawn above the card. Top-left, no taller than about 280 px with every system on,
## is the corner that clears them all.
##
## It is for people, not for the computer: a seat the computer plays never shows one. In hotseat every person gets
## their own card on their own turn 1, behind the handoff cover like the rest of the screen: ticks and "done" are kept
## per seat, a seat's card is built from that seat's own queued orders only (GameSession.current_orders is empty while
## the cover is up), and the title says whose it is.
##
## Fog: the guide reads the person's own queued orders, the per-viewer state's public game flags (rulers, paths, sieges,
## fog, magic, independents) and fixed text. It never reads a truth accessor (tests/test_first_game_guide.gd scans for it,
## on top of tests/test_fog_ui.gd's scan of every ui script), so it cannot say anything the person has no right to know.
##
## Remembered in the settings file's [hints] section (GameSettings.HINT_FIRST_GAME): once every person in the game has
## finished their first turn or pressed Hide, the guide never shows again, until Settings' "Show the first-game guide
## again" takes the hint back. A game started while the hint is unseen shows it; a game started after it was seen does not.
##
## API:
##   sync(session, view)        called by GameScreen whenever its HUD changes (orders, seat, turn): shows, ticks or hides
##   steps() -> Dictionary      {"move": bool, "recruit": bool, "end_turn": bool}: what the card ticks now
##   showing() -> String        the faction id whose card is up ("" while hidden or lingering)
##   lingering() -> bool, end_linger()   the moment after End turn, every step ticked, and its end
##   note_plan_seen(fid)        UX-9: the Plan was shown to `fid` (PlanHud says so): the third step ticks
##   next_step() -> String      UX-9: the id of the step lit as the one to do next ("" when all are done)
##   step_states(orders, ended, plan_seen) (static)   the ticks for a list of orders: pure, no scene needed
##   systems_on(view) (static)  the per-system lines for a game's flags: pure
##   signal codex_requested(key)   a link was pressed (GameScreen opens its codex there)

signal codex_requested(key: String)

const WIDTH := 350.0
const MARGIN := 12.0
## Where the card starts before the Table has placed it: the top left of the board's safe area (TableLayout).
const TOP := 120.0
## How long the card stays, every step ticked, over the board's playback after End turn.
const LINGER := 3.5
const HOW_TO_PLAY := "how_to_play"
## The steps: each a single line that says what to do and where, and a tooltip with the rest.
const STEPS := [
	{"id": "move", "title": "March: click an army, then March",
		"tip": "Click one of your armies on the board: its card opens beside it. Press March, then a province next to it (or click the province straight away). The march shows as a numbered arrow on the board and a token in the tray along the bottom, with its forecast, and nothing happens until every player has ended the turn. An army you don't move holds where it is.",
		"entry": "move"},
	{"id": "recruit", "title": "Recruit: click your capital, then Recruit",
		"tip": "Click your capital (the crown on the board): its card opens. Press Recruit on the card, then a unit. The price is paid, and the unit joins you, when the turn resolves.",
		"entry": "recruit"},
	{"id": "plan", "title": "Check them: the tray, then the Plan",
		"tip": "Every order is a numbered token in the tray along the bottom; hover one for its forecast. The Chronicle's Plan reads them all back as sentences, each with its forecast: in your first game the End turn seal opens it first.",
		"entry": "turn_review"},
	{"id": "end_turn", "title": "Seal: the seal, then Seal the orders",
		"tip": "End turn (the seal, bottom right) opens the Plan in your first game; Seal the orders at its foot locks your orders in. Every player's orders then resolve together, in one fixed order, and the Chronicle tells you what happened and why.",
		"entry": "orders"},
]
## The "Also on" row's short names (one line wide), where a system's full name is longer.
const SHORT_NAMES := {"sieges": "Forts"}
## One line for each system that is on, in this order: the linked name, the rest of the line (short enough to stay on
## one line) and the codex entry the name opens. The flags are on the game's state (systems_on).
const SYSTEMS := [
	{"id": "rulers", "name": "Rulers", "rest": "turn power into mandates", "entry": "ruler",
		"tip": "Every faction is led by a ruler. The power it keeps makes it strong in person; the power it spends buys mandates for the whole nation. Builds are public, and the Ruler button in the system row explains every number."},
	{"id": "paths", "name": "Paths", "rest": "research upgrades that lock in", "entry": "path",
		"tip": "Your faction researches a path with research points from its land. Most nodes are ordinary upgrades; a few forks lock you in for the rest of the game."},
	{"id": "sieges", "name": "Forts and sieges", "rest": "recruit at any fort", "entry": "fort_levels",
		"tip": "Forts have levels and walls. You recruit at any fort you own, and an army that marches into an enemy fort with a garrison inside besieges it instead of fighting."},
	{"id": "fog", "name": "Fog of war", "rest": "you see only near your land", "entry": "fog_of_war",
		"tip": "You see exactly only where you own land or have an army; next to that you glimpse armies roughly (two away from forts, commanders, rulers and scouts); beyond, only what you saw last. That is what \"glimpsed\" and \"never seen\" mean on the map. Fog changes what you are shown, never the rules."},
	{"id": "magic", "name": "Magic", "rest": "spells, mages and rituals", "entry": "magic",
		"tip": "You learn spells by research. Mages cast them by themselves in every round of a battle, and rituals are orders you pay for in gold."},
	{"id": "independents", "name": "Independents", "rest": "garrison the neutral land", "entry": "independents",
		"tip": "Every neutral province starts with a garrison of free fighters who answer to no ruler. To take a province you must beat its garrison in battle."},
]

var title_label: Label
var progress_label: Label
var hide_button: Button
var step_checks := {}  # step id -> the tick (a CheckBox that only shows)
var systems_box: VBoxContainer  # the fog line, the "Also on" row and the other systems' lines
var systems_toggle: Button  # the "Also on: ..." row: opens and folds the other systems' lines
var systems_lines_box: VBoxContainer  # the other systems' lines, folded until the row is pressed
var system_lines := {}  # system id -> the RichTextLabel of its line
var closing_label: Label
var how_button: Button
var _showing := ""  # the faction id whose card is up
var _turn := 0  # the turn it was shown for
var _session_id := 0
var _enabled := false  # the hint was unseen when this game started
var _humans: Array = []  # faction ids a person plays, in seat order
var _done := {}  # faction id -> true once that person ended their first turn or hid the card
var _ended := {}  # faction id -> true once that person ended their first turn
var _plan_seen := {}  # faction id -> true once the Plan was shown to that person (UX-9)
var _lingering := false
var _linger_until := 0
var _systems: Array = []  # the SYSTEMS lines on in this game (ids)
var _systems_open := false  # the "Also on" row is open
var _fog_explained := false  # the card's fog line told this game's players how fog works: the first fog turn's banner is not needed
var _seat_title := ""


func _init() -> void:
	name = "FirstGameGuide"
	visible = false
	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = MARGIN
	offset_right = MARGIN + WIDTH
	offset_top = TOP
	offset_bottom = TOP
	custom_minimum_size = Vector2(WIDTH, 0)
	var style := UiPalette.panel_style(8)
	style.border_color = UiPalette.GILT
	add_theme_stylebox_override("panel", style)
	_build()


# --- API ------------------------------------------------------------------------------------------

## Shows, ticks or hides the card for the game as it stands. `view` is the viewer's state (its game flags are public).
func sync(session: GameSession, view: GameState) -> void:
	if session == null or view == null or session.phase() == GameSession.Phase.INVALID:
		_hide()
		return
	if session.get_instance_id() != _session_id:
		_new_game(session)
	var fid := _person_giving_orders(session)
	var turn := session.turn_number()
	if _showing != "" and (fid != _showing or turn != _turn):
		_finished_turn(_showing, session)  # the seat whose card was up ended its turn
	if _lingering:
		if turn > 1 and session.human_seats() == 1 and Time.get_ticks_msec() < _linger_until:
			return
		_lingering = false
	if not _enabled or fid.is_empty() or turn != 1 or _done.has(fid):
		_hide()
		return
	_show_for(session, view, fid, turn)


## True when the card's other-systems lines are folded behind the "Also on" row (always, while no other system is on).
func systems_folded() -> bool:
	return not _systems_open or not systems_toggle.visible


## Opens or folds the other systems' lines (the "Also on" row does it).
func toggle_systems() -> void:
	_systems_open = not _systems_open
	_refresh_systems()


## True while the card is up with its fog line, which tells the players how fog works (the game screen then skips the
## first fog turn's banner: one card at a time).
func explains_fog() -> bool:
	return _fog_explained and showing() != ""


## What the card ticks now.
func steps() -> Dictionary:
	var out := {}
	for id in step_checks:
		out[id] = (step_checks[id] as CheckBox).button_pressed
	return out


## The faction id whose card is up, "" while it is hidden.
func showing() -> String:
	return _showing if visible and not _lingering else ""


func lingering() -> bool:
	return _lingering and visible


## The ticks for `orders` (the person's queued orders), whether the Plan was shown to them and whether they have ended the turn
## (which ticks the Plan too: a turn sealed was a turn checked, as far as the card goes).
static func step_states(orders: Array, ended: bool, plan_seen: bool = false) -> Dictionary:
	var moved := false
	var recruited := false
	for o in orders:
		if o is MoveOrder:
			moved = true
		elif o is RecruitOrder:
			recruited = true
	return {"move": moved, "recruit": recruited, "plan": plan_seen or ended, "end_turn": ended}


## UX-9: the Plan was shown to `fid` (the seal opened it, or the Chronicle's Plan tab was pressed): its step ticks.
func note_plan_seen(fid: String) -> void:
	if fid.is_empty() or _plan_seen.has(fid):
		return
	_plan_seen[fid] = true
	if _showing == fid:
		var ticks := steps()
		ticks["plan"] = true
		_tick(ticks)


## The id of the step lit as the one to do next: the first one not ticked ("" when every one is).
func next_step() -> String:
	for step in STEPS:
		var check: CheckBox = step_checks[String(step.id)]
		if not check.button_pressed:
			return String(step.id)
	return ""


## The system lines for a game: the entries of SYSTEMS whose system is on in `view`, in order.
static func systems_on(view: GameState) -> Array:
	var flags := {"rulers": RulerRules.has_rulers(view), "paths": view.paths, "sieges": view.sieges, "fog": view.fog,
		"magic": view.magic, "independents": view.independents}
	return SYSTEMS.filter(func(s): return flags.get(String(s.id), false))


# --- showing --------------------------------------------------------------------------------------

func _new_game(session: GameSession) -> void:
	_session_id = session.get_instance_id()
	_showing = ""
	_turn = 0
	_done = {}
	_ended = {}
	_plan_seen = {}
	_lingering = false
	_enabled = not GameSettings.hint_seen(GameSettings.HINT_FIRST_GAME)
	_humans = session.players().filter(func(f): return not session.is_computer(f))
	_systems = []
	_hide()


## The faction id of the person giving orders now, "" while nobody is (the handoff cover, the computer's seat, a
## finished game, a game only the computer plays).
func _person_giving_orders(session: GameSession) -> String:
	if session.phase() != GameSession.Phase.ORDERS or session.human_seats() == 0:
		return ""
	var fid := session.current_player()
	return "" if session.is_computer(fid) else fid


func _show_for(session: GameSession, view: GameState, fid: String, turn: int) -> void:
	if _showing != fid or _turn != turn:
		_showing = fid
		_turn = turn
		_set_systems(view)
		_seat_title = "First game guide" if session.human_seats() <= 1 else "Guide: Player %d" % session.current_seat()
		title_label.text = _seat_title
		closing_label.visible = false
		how_button.visible = true
	_tick(step_states(session.current_orders(), _ended.has(fid), _plan_seen.has(fid)))
	visible = true


func _tick(states: Dictionary) -> void:
	var done := 0
	var lit := false
	for step in STEPS:
		var id := String(step.id)
		var on: bool = states.get(id, false)
		var check: CheckBox = step_checks[id]
		check.button_pressed = on
		var next := not on and not lit  # UX-9: the first step not done yet is lit in gilt
		lit = lit or next
		check.add_theme_color_override("font_disabled_color", UiPalette.POSITIVE if on else (UiPalette.GILT if next else UiPalette.TEXT_PRIMARY))
		if on:
			done += 1
	progress_label.text = "%d of %d" % [done, STEPS.size()]


func _hide() -> void:
	_showing = ""
	_lingering = false
	visible = false


## The seat `fid` ended its first turn (or the turn moved on while its card was up).
func _finished_turn(fid: String, session: GameSession) -> void:
	_ended[fid] = true
	_done[fid] = true
	var ticks := steps()
	ticks["end_turn"] = true
	ticks["plan"] = true
	_tick(ticks)
	_mark_if_everyone_done()
	_showing = ""
	# With one person the card stays a moment over the board's playback, every step ticked, then goes. In hotseat the
	# handoff cover is up (and another person's turn is next): it goes at once.
	if session.human_seats() == 1 and session.phase() == GameSession.Phase.ORDERS:
		_lingering = true
		_linger_until = Time.get_ticks_msec() + int(LINGER * 1000.0)
		closing_label.visible = true
		how_button.visible = false
		visible = true
		if is_inside_tree():
			get_tree().create_timer(LINGER).timeout.connect(end_linger)


## The moment is over (a timer ends it by itself): the card goes.
func end_linger() -> void:
	if _lingering:
		_hide()


func _on_hide_pressed() -> void:
	if _showing != "":
		_done[_showing] = true
		_mark_if_everyone_done()
	_hide()


## The hint is remembered once every person in the game has finished or hidden their card.
func _mark_if_everyone_done() -> void:
	for fid in _humans:
		if not _done.has(fid):
			return
	GameSettings.mark_hint_seen(GameSettings.HINT_FIRST_GAME)
	if _fog_explained:
		GameSettings.mark_hint_seen("fog")  # the card's fog line said it: the banner has nothing left to add


func _set_systems(view: GameState) -> void:
	var on := systems_on(view)
	_systems = on.map(func(s): return String(s.id))
	for id in system_lines:
		(system_lines[id] as Control).visible = _systems.has(id)
	systems_box.visible = not on.is_empty()
	_fog_explained = _systems.has("fog")
	_systems_open = false
	_refresh_systems()


## The "Also on" row and the folded lines for the systems that are on (the fog line is never folded).
func _refresh_systems() -> void:
	var others := SYSTEMS.filter(func(s): return String(s.id) != "fog" and _systems.has(String(s.id)))
	systems_toggle.visible = not others.is_empty()
	systems_lines_box.visible = _systems_open and not others.is_empty()
	var names := others.map(func(s): return String(SHORT_NAMES.get(String(s.id), s.name)))
	systems_toggle.text = "%s Also on: %s" % ["\u25BE" if _systems_open else "\u25B8", "" if _systems_open else ", ".join(names)]
	var tip := others.map(func(s): return "%s: %s" % [String(s.name), String(s.rest)])
	systems_toggle.tooltip_text = TooltipText.plain("The other systems in this game",
		"%s.\n\nClick to open or fold one line about each; every name in them opens its codex entry, and hovering a line says more." % "\n".join(tip))


# --- nodes ----------------------------------------------------------------------------------------

func _build() -> void:
	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", 1)
	add_child(box)

	var head := HBoxContainer.new()
	head.name = "Head"
	head.add_theme_constant_override("separation", 5)
	box.add_child(head)
	title_label = _label("TitleLabel", "First game guide", 18, UiPalette.GILT)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS  # the head row also holds How to play and Hide
	head.add_child(title_label)
	progress_label = _label("ProgressLabel", "0 of %d" % STEPS.size(), 15, UiPalette.TEXT_SECONDARY)
	progress_label.tooltip_text = TooltipText.plain("Your first turn", "The things to do on a first turn. Each ticks off by itself once you have done it, and the next one is lit in gold.")
	progress_label.mouse_filter = Control.MOUSE_FILTER_PASS
	head.add_child(progress_label)
	hide_button = Button.new()
	hide_button.name = "HideButton"
	hide_button.text = "Hide"
	hide_button.flat = true
	hide_button.focus_mode = Control.FOCUS_NONE
	hide_button.add_theme_font_size_override("font_size", 15)
	_tight(hide_button)
	hide_button.add_theme_color_override("font_color", UiPalette.TEXT_SECONDARY)
	hide_button.tooltip_text = TooltipText.plain("Hide the guide", "Closes this card. Settings has \"Show the first-game guide again\" to bring it back in your next game.")
	hide_button.pressed.connect(_on_hide_pressed)
	head.add_child(hide_button)

	for step in STEPS:
		var check := CheckBox.new()
		check.name = "Step_%s" % String(step.id)
		check.text = String(step.title)
		check.disabled = true  # a tick you can see, not a switch you can flip
		check.focus_mode = Control.FOCUS_NONE
		check.add_theme_font_size_override("font_size", 16)
		_tight(check)
		check.add_theme_color_override("font_disabled_color", UiPalette.TEXT_PRIMARY)
		check.tooltip_text = TooltipText.plain(String(step.title), String(step.tip))
		CodexLink.attach(check, String(step.entry), codex_requested.emit)
		box.add_child(check)
		step_checks[String(step.id)] = check

	closing_label = _label("ClosingLabel", "That is a turn. It plays out now; then the Chronicle says what happened and why.", 15, UiPalette.POSITIVE)
	closing_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	closing_label.custom_minimum_size = Vector2(WIDTH - 16.0, 0)
	closing_label.visible = false
	box.add_child(closing_label)

	systems_box = VBoxContainer.new()
	systems_box.name = "Systems"
	systems_box.add_theme_constant_override("separation", 1)
	systems_box.visible = false
	box.add_child(systems_box)
	systems_lines_box = VBoxContainer.new()
	systems_lines_box.name = "SystemLines"
	systems_lines_box.add_theme_constant_override("separation", 1)
	systems_lines_box.visible = false
	for s in SYSTEMS:
		var line := RichTextLabel.new()
		line.name = "System_%s" % String(s.id)
		line.bbcode_enabled = true
		line.fit_content = true
		line.scroll_active = false
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.add_theme_font_size_override("normal_font_size", 13)
		line.add_theme_color_override("default_color", UiPalette.TEXT_SECONDARY)
		line.add_theme_color_override("meta_color", UiPalette.LINK)
		line.custom_minimum_size = Vector2(WIDTH - 16.0, 0)
		line.text = "[url=%s]%s[/url]: %s" % [String(s.entry), String(s.name), String(s.rest)]
		line.meta_clicked.connect(func(meta: Variant): codex_requested.emit(String(meta)))
		line.tooltip_text = CodexLink.with_link(TooltipText.plain(String(s.name), String(s.tip)), String(s.entry))
		line.visible = false
		(systems_box if String(s.id) == "fog" else systems_lines_box).add_child(line)  # fog's line never folds
		system_lines[String(s.id)] = line
	systems_toggle = Button.new()
	systems_toggle.name = "SystemsToggle"
	systems_toggle.flat = true
	systems_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	systems_toggle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	systems_toggle.focus_mode = Control.FOCUS_NONE
	systems_toggle.custom_minimum_size = Vector2(WIDTH - 16.0, 0)
	systems_toggle.add_theme_font_size_override("font_size", 13)
	_tight(systems_toggle)
	systems_toggle.add_theme_color_override("font_color", UiPalette.TEXT_SECONDARY)
	systems_toggle.add_theme_color_override("font_hover_color", UiPalette.GILT)
	systems_toggle.pressed.connect(toggle_systems)
	systems_toggle.visible = false
	systems_box.add_child(systems_toggle)
	systems_box.add_child(systems_lines_box)

	how_button = Button.new()
	how_button.name = "HowToPlayButton"
	how_button.text = "How to play"
	how_button.flat = true
	how_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	how_button.focus_mode = Control.FOCUS_NONE
	how_button.add_theme_font_size_override("font_size", 15)
	_tight(how_button)
	how_button.add_theme_color_override("font_color", UiPalette.LINK)
	how_button.add_theme_color_override("font_hover_color", UiPalette.GILT)
	how_button.tooltip_text = TooltipText.plain("How to play", "The turn loop (read, plan, commit, resolve, watch), the Table, the Chronicle and the battle viewer, why orders are simultaneous and where every number explains itself.")
	how_button.pressed.connect(func(): codex_requested.emit(HOW_TO_PLAY))
	# MVP-3 (#177): beside Hide in the head row, not a row of its own: the card is shorter by a line and leaves the capital's
	# neighbor clear at 125% too.
	head.add_child(how_button)
	head.move_child(how_button, hide_button.get_index())


## The card is a small thing: a button or tick keeps no padding of its own, so each row is as tall as its text.
func _tight(b: BaseButton) -> void:
	var sb := StyleBoxEmpty.new()
	sb.content_margin_left = 2.0
	sb.content_margin_right = 2.0
	sb.content_margin_top = 1.0
	sb.content_margin_bottom = 1.0
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(state, sb)


func _label(node_name: String, text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.name = node_name
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l
