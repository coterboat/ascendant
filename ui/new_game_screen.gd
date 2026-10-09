class_name NewGameScreen
extends Control
## New game setup (#8): which seat (Player 1, Player 2) plays which faction, whether a person or the
## computer plays it (#35; the computer at Easy or Normal), and the game seed, random by default.
## Start emits start_requested(config) with
##   {"players": [faction ids in seat order], "seed": int}
## plus, only when the computer plays a seat, "ai": {faction id: "easy" or "normal"}. A seat not in
## "ai" is human, so a hotseat config is exactly {"players", "seed"} as before. This is what
## GameScreen.start_game(config) takes. Every seat may be the computer: then the game is watch mode.
## While any seat is the computer, the computer's explanation (RulesCodex "computer_opponent") takes the
## place of the hotseat one. Factions come from data/factions.gd through the
## rules model (GameState builds the Faction objects); the hotseat explanation is RulesCodex
## "hotseat". The same faction can't be picked twice and the seed must be a whole number: either
## problem is explained in plain words and disables Start. Never changes rules state.
## Player colours follow the seat (UiPalette.seat_color): Player 1 is Vermilion, Player 2 Cobalt, so the
## faction picked for a seat is shown in that seat's colour and swapping seats swaps the colours.
## MVP defaults: Player 1 is a person and Player 2 the computer at Normal, with rulers on. Hotseat is one
## click away (Player 2's picker to Human), and Quick start skips this screen with the same defaults
## (quick_start_config). A rematch (prefill) keeps the last game's choices instead.
## MVP-2 (#163), the defaults flip: all six system boxes start ticked (SYSTEMS), with the preview labels gone, and every
## box stays a choice: untick one and the game plays without it. Each box shows a line of what it adds (the same one the
## first-game guide uses), a tooltip with the whole of it, and a link to its codex entry; the line beside the "Game systems"
## heading says which systems this game plays with and how the boxes lean on each other. A settings file from before the flip gets one
## extra line, once (defaults_label, GameSettings.defaults_notice_due). Launching with `-- --rulers`, `--paths`, `--sieges`,
## `--magic`, `--fog` or `--independents` still forces that system into any game (GameScreen.starting_state).
## Rulers (M2-5, #33): the "Rulers" box. Ticked, config() adds "rulers": true and Start
## opens the BuildScreen on top of this screen: every human seat picks a ruler and mandates in secret,
## computer seats get a seeded preset, and only then is start_requested emitted, with the config plus
## "builds" ({faction id: build}). Back on the build screen returns here and drops those builds.
## Paths (M4-1, #66): the "Paths" box. Paths need rulers, so ticking it ticks the rulers box too, and clearing the rulers
## box clears it. Ticked, config() adds "paths": true (GameScreen.starting_state then uses GameState.with_paths).
## Forts & sieges (M3c S-1a, #98; design/M3C_SIEGES.md §1.3): the "Forts & sieges" box, independent of Rulers and Paths.
## Ticked, config() adds "sieges": true (GameScreen.starting_state then uses GameState.with_sieges).
## Magic (M5-5, #116; design/M5_MAGIC_FOG.md §1.3): the "Magic" box. Magic needs Paths: ticking it ticks Paths and Rulers,
## and clearing Paths (or Rulers) clears it. Ticked, config() adds "magic": true (GameScreen.starting_state then uses
## GameState.with_magic).
## Fog of war (M5-1, #112; design/M5_MAGIC_FOG.md §1.3): the "Fog of war" box, independent of every other box. Ticked,
## config() adds "fog": true (GameScreen.starting_state then calls GameState.setup_fog on whichever game the other boxes make).
## Independents (IND-1, #142): the "Independents" box, independent of every other box. Ticked, config() adds
## "independents": true (GameScreen.starting_state then calls GameState.setup_independents: a Free Holds garrison in
## every neutral province).
## Layout (MVP-1, #141): it fits the default window (1600x900) and 1280x720. The title sits above, the error
## line and the Start and Back buttons below (always on screen), and the body scrolls between them when it is taller than
## the window leaves room for. The six boxes sit in two columns. tests/test_screens_fit.gd checks it at both sizes.
## Builds its children in code, so it works before it is in the tree (headless tests).
##
## API:
##   config() -> Dictionary          {"players", "seed"}, plus "ai" for computer seats and "rulers": true
##                                   while the rulers box is ticked; only meaningful when is_valid()
##   is_valid() -> bool
##   error_text() -> String          every problem in plain words, "" when valid
##   set_seed(value: int)            new_seed(avoid) -> int picks a random one (the "New seed" button),
##                                   never `avoid`
##   swap_seats()                    Player 1 and Player 2 trade factions (the "Swap seats" button); who
##                                   plays each seat, a person or the computer, stays with the seat
##   set_seat_kind(seat, kind) -> bool    "human" or "computer"; seat_kind(seat) -> String
##   set_seat_level(seat, level) -> bool  the computer's level, "easy" or "normal"; seat_level(seat)
##   select_faction(seat, faction_id) -> bool   seat is 1-based; false for an unknown seat or faction
##   set_seats(players) -> bool      every seat at once: faction ids in seat order
##   prefill(last_game)              a rematch of last_game ({"players", "seed", "ai", "rulers", "builds"}):
##                                   the same seating, the same human and computer seats at the same
##                                   levels, the rulers box as it was, each human seat's last build as
##                                   its starting build, and a new seed (the victory screen's New game)
##   set_rulers(on), rulers_on()     the "Rulers" box
##   set_paths(on), paths_on()       the "Paths" box (M4-1); ticking it ticks rulers
##   set_sieges(on), sieges_on()     the "Forts & sieges" box (M3c), on its own
##   set_magic(on), magic_on()       the "Magic" box (M5-5); ticking it ticks paths and rulers
##   set_fog(on), fog_on()           the "Fog of war" box (M5-1), on its own
##   set_independents(on), independents_on()   the "Independents" box (IND-1), on its own
##   set_all_systems(on)             every box at once (cleared: the basic game)
##   systems_ticked() -> Array       the SYSTEMS keys whose box is ticked, in screen order
##   default_systems() -> Dictionary (static) the config keys every system starts with: {"rulers": true, ...}
##   quick_start_config(rng) -> Dictionary   Quick start's config (static): a random faction for the person
##                                   in seat 1, the computer at Normal in seat 2, every system on (default_systems)
##                                   with the balanced preset for the person, and a random seed
##   build_screen                    the BuildScreen Start opens while rulers are on (null until then);
##                                   build_screen_open() -> bool
##   seat_faction(seat) -> String, faction_ids() -> Array[String]
##   start() -> bool                 emits start_requested when valid (the Start button, Enter in the seed);
##                                   with rulers on, opens the build screen instead, which emits it later
##   back()                          emits back_requested (the Back button, Esc)

signal start_requested(config: Dictionary)
signal back_requested
## MVP-3 (#177): the computer's paragraph links its codex entry (the title screen opens the codex there).
signal codex_requested(key: String)

const SEAT_COUNT := 2
const KINDS := ["human", "computer"]  # the seat kind pickers' items, in order
const KIND_NAMES := ["Human", "Computer"]
const LEVELS := ["easy", "normal"]  # AIPlayer.DIFFICULTIES, in the level pickers' order
const DEFAULT_LEVEL := "normal"
const DEFAULT_KINDS := ["human", "computer"]  # MVP: you against the computer
## MVP-2 (#163): the six system boxes in screen order, with the config key each adds and its name on the screen. Every one
## starts ticked (default_systems); the grid of two columns fills across in this order.
const SYSTEMS := [
	{"key": "rulers", "name": "Rulers"},
	{"key": "paths", "name": "Paths"},
	{"key": "sieges", "name": "Forts & sieges"},
	{"key": "magic", "name": "Magic"},
	{"key": "fog", "name": "Fog of war"},
	{"key": "independents", "name": "Independents"},
]
## MVP-2: the one line a settings file from before the flip gets, once, beside the title.
const DEFAULTS_NOTICE := "New: every system now starts ticked. Untick any you would rather play without."
## What each system adds, in one line under its box (the first-game guide says the same in FirstGameGuide.SYSTEMS).
const SYSTEM_LINES := {
	"rulers": "A ruler for each side; its power buys mandates.",
	"paths": "Research a path of upgrades; its Oaths lock you in.",
	"sieges": "Forts with walls: recruit at any fort, besiege or storm.",
	"magic": "Spells, mages and rituals, learned by research.",
	"fog": "You see only near your land and your armies.",
	"independents": "Free fighters garrison every neutral province.",
}
const MAX_SEED_DIGITS := 18  # any 18-digit number fits in a 64-bit int
const MAX_RANDOM_SEED := 999999999
const BACKGROUND := Color("#14131F")
## MVP-1 (#141): the screen's layout. The panel is as tall as the window leaves room for (SCREEN_MARGIN around it); its
## title, error line and Start and Back buttons are pinned, and the body between them scrolls (body_scroll).
const SCREEN_MARGIN := 20
const PANEL_WIDTH := 960.0
const PANEL_PADDING := 24
const NEGATIVE := UiPalette.NEGATIVE  # design/STYLE_BIBLE.md 1.3 "negative"

var body_scroll: ScrollContainer  # the seats, seed and boxes: scrolls when the window is too small for them
var seat_pickers: Array[OptionButton] = []
var kind_pickers: Array[OptionButton] = []  # Human or Computer, per seat
var level_pickers: Array[OptionButton] = []  # Easy or Normal, per seat; shown for computer seats only
var computer_title: Label  # "Playing against the computer": replaces the hotseat title while a seat is the computer
var computer_head: HBoxContainer  # MVP-3: that title with the link to the codex entry beside it
var computer_link: Button  # "How it plays": opens the codex entry "computer_opponent"
var computer_label: Label  # how the computer plays, in place of the hotseat explanation
var _hotseat_title: Label
var seat_labels: Array[Label] = []
var faction_labels: Array[Label] = []
var hotseat_label: Label
var rematch_label: Label  # shown after prefill(): why the seats are already set
var seed_edit: LineEdit
var new_seed_button: Button
var swap_button: Button
var error_label: Label
var start_button: Button
var back_button: Button
var rulers_toggle: CheckBox  # "Rulers": on by default
var rulers_label: Label  # what the box does, shown while it is ticked
var paths_toggle: CheckBox  # M4-1: "Paths": on by default; needs rulers
var sieges_toggle: CheckBox  # M3c: "Forts & sieges": on by default; independent of rulers and paths
var magic_toggle: CheckBox  # M5-5: "Magic": on by default; needs paths
var fog_toggle: CheckBox  # M5-1: "Fog of war": on by default; works with any game
var independents_toggle: CheckBox  # IND-1: "Independents": on by default; works with any game
var systems_label: Label  # MVP-2: which systems this game plays with, and how the boxes lean on each other
var defaults_label: Label  # MVP-2: shown once to a settings file from before the flip: every system starts ticked now
var settings_file := ""  # the settings file the defaults notice reads ("" = GameSettings.default_path); tests set it
var build_screen: BuildScreen = null  # opened by Start while rulers are on; built on first use
var _last_builds := {}  # faction id -> the last game's build of a human seat (rematch)
var _model: GameState
var _rng := RandomNumberGenerator.new()
var _digits := RegEx.create_from_string("^[0-9]+$")


func _init() -> void:
	name = "NewGameScreen"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_model = GameState.new()
	_rng.randomize()
	_build()
	for i in SEAT_COUNT:
		seat_pickers[i].select(i % _model.factions.size())
		kind_pickers[i].select(KINDS.find(DEFAULT_KINDS[i]))
	new_seed()


func _ready() -> void:
	# MVP-2: a settings file from before the flip hears once that every system starts ticked now.
	if GameSettings.defaults_notice_due(settings_file):
		defaults_label.visible = true
		GameSettings.mark_defaults_noticed(settings_file)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		if is_inside_tree():
			get_viewport().set_input_as_handled()
		# The build screen sits on top of this one: Esc is its Back (or closes its codex).
		if build_screen_open():
			build_screen.handle_cancel()
			return
		back()


# --- API ------------------------------------------------------------------------------------------

func config() -> Dictionary:
	var out := {"players": _seat_ids(), "seed": _seed_value()}
	var ai := {}
	var ids := _seat_ids()
	for i in ids.size():
		if seat_kind(i + 1) == "computer" and not String(ids[i]).is_empty():
			ai[ids[i]] = seat_level(i + 1)
	if not ai.is_empty():
		out["ai"] = ai
	if rulers_on():
		out["rulers"] = true
	if paths_on():
		out["paths"] = true
	if sieges_on():
		out["sieges"] = true
	if magic_on():
		out["magic"] = true
	if fog_on():
		out["fog"] = true
	if independents_on():
		out["independents"] = true
	return out


func is_valid() -> bool:
	return _problems().is_empty()


func error_text() -> String:
	return "\n".join(_problems())


func set_seed(value: int) -> void:
	seed_edit.text = str(value)
	_refresh()


## Picks a new random seed, never `avoid` (the last game's seed, for a rematch), shows it and returns it.
func new_seed(avoid: int = -1) -> int:
	var value := _rng.randi_range(1, MAX_RANDOM_SEED)
	while value == avoid:
		value = _rng.randi_range(1, MAX_RANDOM_SEED)
	set_seed(value)
	return value


## Seats every player at once: `players` holds faction ids in seat order. Returns false, changing
## nothing, unless there is one known faction per seat.
func set_seats(players: Array) -> bool:
	if players.size() != seat_pickers.size():
		return false
	var ids := faction_ids()
	for fid in players:
		if not ids.has(String(fid)):
			return false
	for i in seat_pickers.size():
		seat_pickers[i].select(ids.find(String(players[i])))
	_refresh()
	return true


## A rematch of `last_game` ({"players", "seed"}, GameScreen.config): the same factions in the same
## seats, and a new random seed so the dice fall differently. An unusable seating is left as it is.
## A game with rulers ("rulers" or "builds") ticks the rulers box again, and each human seat's build
## becomes its starting build on the build screen (a computer seat rolls its preset again from the new
## seed). Builds are public once a game starts, so this shows nobody anything new.
func prefill(last_game: Dictionary) -> void:
	_close_builds()
	var players := Array(last_game.get("players", []))
	var ai: Dictionary = last_game.get("ai", {}) if last_game.get("ai") is Dictionary else {}
	rematch_label.visible = set_seats(players)
	if rematch_label.visible:
		for i in players.size():
			var fid := String(players[i])
			set_seat_kind(i + 1, "computer" if ai.has(fid) else "human")
			if ai.has(fid):
				set_seat_level(i + 1, String(ai[fid]))
	var builds: Dictionary = last_game.get("builds", {}) if last_game.get("builds") is Dictionary else {}
	_last_builds = {}
	for fid in builds:
		if not ai.has(String(fid)):
			_last_builds[String(fid)] = builds[fid]
	# MVP-2: a rematch plays the systems the last game had, even a game from before the flip that had none (a launch switch
	# forces its system into every game, so it stays).
	if last_game.get("rulers", false) == true or not builds.is_empty():
		set_rulers(true)
	elif last_game.has("players"):
		set_rulers(_forced("rulers"))  # a game without rulers: a rematch without them
	if last_game.get("paths", false) == true:  # M4-1
		set_paths(true)
	elif last_game.has("players"):
		set_paths(_forced("paths"))
	if last_game.get("sieges", false) == true:  # M3c
		set_sieges(true)
	elif last_game.has("players"):
		set_sieges(_forced("sieges"))
	if last_game.get("magic", false) == true:  # M5-5
		set_magic(true)
	elif last_game.has("players"):
		set_magic(_forced("magic"))
	if last_game.get("fog", false) == true:  # M5-1
		set_fog(true)
	elif last_game.has("players"):
		set_fog(_forced("fog"))
	if last_game.has("players"):  # IND-1
		set_independents(last_game.get("independents", false) == true or _forced("independents"))
	new_seed(int(last_game.get("seed", -1)))


func swap_seats() -> void:
	var picks := []
	for p in seat_pickers:
		picks.append(p.selected)
	picks.reverse()
	for i in seat_pickers.size():
		seat_pickers[i].select(picks[i])
	_refresh()


## Sets the faction of `seat` (1-based). Returns false, changing nothing, for an unknown seat or faction.
func select_faction(seat: int, faction_id: String) -> bool:
	var index := faction_ids().find(faction_id)
	if seat < 1 or seat > seat_pickers.size() or index < 0:
		return false
	seat_pickers[seat - 1].select(index)
	_refresh()
	return true


## Sets who plays `seat` (1-based): "human" or "computer". Returns false, changing nothing, otherwise.
func set_seat_kind(seat: int, kind: String) -> bool:
	if seat < 1 or seat > kind_pickers.size() or not KINDS.has(kind):
		return false
	kind_pickers[seat - 1].select(KINDS.find(kind))
	_refresh()
	return true


## "human" or "computer" for `seat` (1-based), or "".
func seat_kind(seat: int) -> String:
	if seat < 1 or seat > kind_pickers.size():
		return ""
	return KINDS[maxi(kind_pickers[seat - 1].selected, 0)]


## Sets the computer's level for `seat` (1-based): "easy" or "normal". Returns false, changing nothing,
## otherwise. The level is kept while the seat is human, for when it is switched back to the computer.
func set_seat_level(seat: int, level: String) -> bool:
	if seat < 1 or seat > level_pickers.size() or not LEVELS.has(level):
		return false
	level_pickers[seat - 1].select(LEVELS.find(level))
	_refresh()
	return true


## The computer's level picked for `seat` (1-based), or "".
func seat_level(seat: int) -> String:
	if seat < 1 or seat > level_pickers.size():
		return ""
	return LEVELS[maxi(level_pickers[seat - 1].selected, 0)]


## Faction id picked for `seat` (1-based), or "".
func seat_faction(seat: int) -> String:
	if seat < 1 or seat > seat_pickers.size():
		return ""
	return _seat_ids()[seat - 1]


## Every faction that can be picked, in the order the pickers list them.
func faction_ids() -> Array[String]:
	var out: Array[String] = []
	for f in _model.factions:
		out.append(f.id)
	return out


## Emits start_requested(config()) when the setup is valid. Returns whether it did. With rulers on, it
## opens the build screen instead (returning true), and start_requested follows once every human seat
## has locked in a build; with no human seat that is at once.
func start() -> bool:
	_refresh()
	if not is_valid():
		return false
	if rulers_on():
		_open_builds()
		return true
	start_requested.emit(config())
	return true


func back() -> void:
	_close_builds()
	back_requested.emit()


## Ticks or clears the "Rulers" box.
func set_rulers(on: bool) -> void:
	rulers_toggle.set_pressed_no_signal(on)
	_refresh()


func rulers_on() -> bool:
	return rulers_toggle.button_pressed


## Ticks or clears the "Paths" box (M4-1). Paths need rulers: ticking it ticks rulers too.
func set_paths(on: bool) -> void:
	paths_toggle.set_pressed_no_signal(on)
	if on:
		rulers_toggle.set_pressed_no_signal(true)
	_refresh()


func paths_on() -> bool:
	return paths_toggle.button_pressed


## Ticks or clears the "Forts & sieges" box (M3c). It needs neither rulers nor paths.
func set_sieges(on: bool) -> void:
	sieges_toggle.set_pressed_no_signal(on)
	_refresh()


func sieges_on() -> bool:
	return sieges_toggle.button_pressed


## Ticks or clears the "Magic" box (M5-5). Magic needs paths: ticking it ticks paths and rulers too.
func set_magic(on: bool) -> void:
	magic_toggle.set_pressed_no_signal(on)
	if on:
		paths_toggle.set_pressed_no_signal(true)
		rulers_toggle.set_pressed_no_signal(true)
	_refresh()


func magic_on() -> bool:
	return magic_toggle.button_pressed


## Ticks or clears the "Fog of war" box (M5-1). It needs no other box.
func set_fog(on: bool) -> void:
	fog_toggle.set_pressed_no_signal(on)
	_refresh()


func fog_on() -> bool:
	return fog_toggle.button_pressed


## Ticks or clears the "Independents" box (IND-1). It needs no other box.
func set_independents(on: bool) -> void:
	independents_toggle.set_pressed_no_signal(on)
	_refresh()


func independents_on() -> bool:
	return independents_toggle.button_pressed


## Ticks or clears every system box at once: cleared is the basic game (config() adds no system key).
func set_all_systems(on: bool) -> void:
	for toggle in [rulers_toggle, paths_toggle, sieges_toggle, magic_toggle, fog_toggle, independents_toggle]:
		toggle.set_pressed_no_signal(on)
	_refresh()


## The system keys whose box is ticked now, in screen order (SYSTEMS).
func systems_ticked() -> Array:
	var out := []
	for sys in SYSTEMS:
		if bool(call(String(sys.key) + "_on")):
			out.append(String(sys.key))
	return out


## MVP-2 (#163): what every system starts as, as the config keys it adds: all six on. The boxes start from this, and so
## does Quick start.
static func default_systems() -> Dictionary:
	var out := {}
	for sys in SYSTEMS:
		out[String(sys.key)] = true
	return out


## A `-- --<system>` launch switch forces that system into every game (GameScreen.starting_state), so a rematch keeps it.
static func _forced(key: String) -> bool:
	return OS.get_cmdline_user_args().has("--" + key)


func build_screen_open() -> bool:
	return build_screen != null and build_screen.visible


## Quick start's config: the person in seat 1 plays a random faction against the computer at Normal in
## seat 2, with every system on (default_systems: rulers, paths, forts and sieges, magic, fog of war and independents)
## and a random seed. The person gets their faction's balanced preset and the
## computer the preset its seeded dice pick (BuildScreen.computer_build, the same roll AISeat makes), so
## the game starts at once, without the build screen. The same as Start with this screen's defaults.
static func quick_start_config(rng: RandomNumberGenerator = null) -> Dictionary:
	var dice := rng
	if dice == null:
		dice = RandomNumberGenerator.new()
		dice.randomize()
	var ids := []
	for f in FactionData.FACTIONS:
		ids.append(f.id)
	var human: String = ids[dice.randi_range(0, ids.size() - 1)]
	var others := ids.filter(func(fid): return fid != human)
	var opponent: String = others[dice.randi_range(0, others.size() - 1)]
	var game_seed := dice.randi_range(1, MAX_RANDOM_SEED)
	var builds := {human: RulerRules.preset_build(RulerRules.balanced_preset(human)),
		opponent: BuildScreen.computer_build(opponent, game_seed, 1)}
	var out := {"players": [human, opponent], "seed": game_seed, "ai": {opponent: DEFAULT_LEVEL}, "builds": builds}
	out.merge(default_systems())
	return out


func _open_builds() -> void:
	if build_screen == null:
		build_screen = load(BuildScreen.SCENE).instantiate() as BuildScreen
		build_screen.finished.connect(_on_builds_finished)
		build_screen.back_requested.connect(_on_builds_back)
		add_child(build_screen)
	move_child(build_screen, get_child_count() - 1)
	build_screen.begin(config(), _last_builds)


func _close_builds() -> void:
	if build_screen_open():
		build_screen.back()


## Every human seat locked in: the game starts with the builds.
func _on_builds_finished(game_config: Dictionary) -> void:
	start_requested.emit(game_config)


func _on_builds_back() -> void:
	if is_inside_tree():
		start_button.grab_focus.call_deferred()


# --- checks ---------------------------------------------------------------------------------------

func _seat_ids() -> Array:
	var ids := []
	for p in seat_pickers:
		ids.append(String(p.get_item_metadata(p.selected)) if p.selected >= 0 else "")
	return ids


func _seed_value() -> int:
	var text := seed_edit.text.strip_edges()
	return text.to_int() if _seed_problem(text).is_empty() else 0


func _seed_problem(text: String) -> String:
	var t := text.strip_edges()
	if t.is_empty():
		return "Enter a seed, or press New seed for a random one."
	if _digits.search(t) == null:
		return "The seed must be a whole number made of digits only, like 482913."
	if t.length() > MAX_SEED_DIGITS:
		return "The seed can have at most %d digits." % MAX_SEED_DIGITS
	return ""


func _problems() -> Array[String]:
	var out: Array[String] = []
	var ids := _seat_ids()
	for i in ids.size():
		if String(ids[i]).is_empty():
			out.append("Pick a faction for Player %d." % (i + 1))
		for j in range(i + 1, ids.size()):
			if not String(ids[i]).is_empty() and ids[i] == ids[j]:
				out.append("Player %d and Player %d both picked %s. Each player needs a different faction." % [
					i + 1, j + 1, _faction(ids[i]).faction_name])
	var seed_problem := _seed_problem(seed_edit.text)
	if not seed_problem.is_empty():
		out.append(seed_problem)
	return out


func _refresh() -> void:
	if paths_toggle != null and paths_on() and not rulers_on():
		paths_toggle.set_pressed_no_signal(false)  # M4-1: paths need rulers
	if magic_toggle != null and magic_on() and not paths_on():
		magic_toggle.set_pressed_no_signal(false)  # M5-5: magic needs paths
	var problems := _problems()
	error_label.text = "\n".join(problems)
	error_label.visible = not problems.is_empty()
	start_button.disabled = not problems.is_empty()
	start_button.tooltip_text = "Start the game with these players and this seed. Player 1 gives orders first." if problems.is_empty() \
		else "You can't start yet:\n%s" % "\n".join(problems)
	var humans := 0
	for i in kind_pickers.size():
		if seat_kind(i + 1) == "human":
			humans += 1
	var to_builds := rulers_on() and humans > 0
	start_button.text = "Choose builds" if to_builds else "Start"
	if to_builds and problems.is_empty():
		start_button.tooltip_text = "Go on to the build screen: each player picks a ruler and mandates in secret%s, and the game starts once every build is locked in. Player 1 gives orders first." % (
			", passing the computer between them" if humans > 1 else "")
	rulers_label.visible = rulers_on()
	var computers := 0
	for i in kind_pickers.size():
		var is_computer := seat_kind(i + 1) == "computer"
		level_pickers[i].visible = is_computer
		if is_computer:
			computers += 1
	computer_label.visible = computers > 0
	computer_title.visible = computers > 0
	computer_head.visible = computers > 0
	# Against the computer, passing the computer around doesn't apply: its explanation takes the place.
	hotseat_label.visible = computers == 0
	_hotseat_title.visible = computers == 0
	if computers == kind_pickers.size():
		computer_label.text = "The computer plays every seat, so you will watch: press Next turn to play each turn. %s" % _computer_short()
	elif computers > 0:
		computer_label.text = _computer_short()
	var ids := _seat_ids()
	for i in seat_pickers.size():
		var f := _faction(ids[i])
		faction_labels[i].text = "Plays in %s. %s" % [UiPalette.seat_color_name(i), _faction_summary(f)] if f else ""
		if f and seat_kind(i + 1) == "computer":
			faction_labels[i].text += " The computer plays this seat at the %s level." % AISeat.level_name(seat_level(i + 1))
			if rulers_on():
				faction_labels[i].text += " Its build: one of its three presets, picked at random from the seed."
		elif f and rulers_on():
			faction_labels[i].text += " Picks a ruler and mandates on the build screen."
		faction_labels[i].tooltip_text = _faction_tooltip(f) if f else ""
		seat_pickers[i].tooltip_text = "Player %d plays %s.\n\n%s" % [i + 1, f.faction_name, _faction_tooltip(f)] if f \
			else "Pick the faction Player %d plays." % (i + 1)
	_refresh_systems_label()


## MVP-2: the line under the boxes: which systems this game plays with, and how the boxes lean on each other.
func _refresh_systems_label() -> void:
	if systems_label == null:
		return
	var out: Array[String] = []
	for sys in SYSTEMS:
		if not bool(call(String(sys.key) + "_on")):
			out.append(String(sys.name))
	var head := "All six systems are on."
	if out.size() == SYSTEMS.size():
		head = "Playing the basic game, without any system."
	elif not out.is_empty():
		head = "Playing without %s." % _names_list(out)
	systems_label.text = "%s Paths need Rulers, and Magic needs Paths." % head


## "A", "A and B", "A, B and C".
static func _names_list(names: Array[String]) -> String:
	if names.size() <= 1:
		return "".join(names)
	return "%s and %s" % [", ".join(names.slice(0, names.size() - 1)), names.back()]


func _faction(fid: String) -> Faction:
	return _model.find_faction(fid)


func _computer_short() -> String:
	return "Same rules as you, and it never sees your orders. Easy makes more mistakes than Normal."  # MVP-3 (#177): one line


## "Capital Crownkeep, 50 gold to start. Spearmen, Crossbowmen and Knights, led by a Knight Captain."
func _faction_summary(f: Faction) -> String:
	var names := []
	for ut in f.unit_types:
		names.append(ut.name)
	var units: String = ", ".join(names)
	if names.size() > 1:
		units = "%s and %s" % [", ".join(names.slice(0, names.size() - 1)), names.back()]
	var capital := _model.find_province(f.capital)
	var text := "Capital %s, %d gold to start. %s" % [capital.name if capital else "unknown", f.gold, units]
	if f.commander_type:
		text += ", led by a %s" % f.commander_type.name
	return text + "."


func _faction_tooltip(f: Faction) -> String:
	var lines := PackedStringArray()
	lines.append(f.faction_name)
	lines.append(TooltipText.wrap_text("Starting gold %d: %s" % [f.gold, Faction.describe("gold")]))
	var capital := _model.find_province(f.capital)
	if capital:
		lines.append(TooltipText.wrap_text("Capital %s: %s" % [capital.name, Province.describe("capital")]))
	lines.append("")
	var types: Array = f.unit_types.duplicate()
	if f.commander_type:
		types.append(f.commander_type)
	for ut in types:
		lines.append(TooltipText.wrap_text("%s%s: %d hit points, attack %d, defense %d, morale %d, costs %d gold. %s: %s." % [
			ut.name, " (commander)" if ut.is_commander else "", ut.hp, ut.attack, ut.defense, ut.morale, ut.cost,
			ut.trait_id, AutoBattleResolver.TRAIT_SHORT.get(ut.trait_id, ut.get_trait_desc())]))
	return "\n".join(lines)


func _on_seed_submitted(_text: String) -> void:
	start()


# --- nodes ----------------------------------------------------------------------------------------

func _build() -> void:
	var background := ColorRect.new()
	background.name = "Background"
	background.color = BACKGROUND
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	# MVP-1 (#141): the panel is as tall as the window leaves room for. The title is pinned above and Start and Back
	# below (so Start is always on screen), and the body between them scrolls when it does not fit: at 1600x900 the
	# default game fits as it stands, at 1280x720 the toggles scroll.
	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, SCREEN_MARGIN)
	add_child(margin)
	var centered := HBoxContainer.new()
	centered.name = "Centered"
	centered.alignment = BoxContainer.ALIGNMENT_CENTER
	centered.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(centered)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = UiPalette.PANEL_BG
	style.border_color = UiPalette.PANEL_BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(PANEL_PADDING)
	panel.add_theme_stylebox_override("panel", style)
	centered.add_child(panel)

	var frame := VBoxContainer.new()
	frame.name = "Box"
	frame.add_theme_constant_override("separation", 10)
	panel.add_child(frame)

	# The title row also holds the one-time note to a settings file from before the flip, so it costs no height.
	var title_row := HBoxContainer.new()
	title_row.name = "TitleRow"
	title_row.add_theme_constant_override("separation", 24)
	frame.add_child(title_row)
	title_row.add_child(_label("TitleLabel", "New game", 40, UiPalette.GILT))
	defaults_label = _label("DefaultsLabel", DEFAULTS_NOTICE, 17, UiPalette.GILT)
	defaults_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	defaults_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	defaults_label.size_flags_vertical = Control.SIZE_SHRINK_END
	defaults_label.visible = false
	title_row.add_child(defaults_label)
	rematch_label = _label("RematchLabel", "Rematch: the same players in the same seats as the last game, with a new seed. Change anything you like.", 17, UiPalette.GILT)
	rematch_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rematch_label.visible = false
	frame.add_child(rematch_label)
	body_scroll = ScrollContainer.new()
	body_scroll.name = "Scroll"
	body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_child(body_scroll)
	var box := VBoxContainer.new()
	box.name = "Body"
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	body_scroll.add_child(box)

	var hotseat := RulesCodex.entry("hotseat")
	_hotseat_title = _label("HotseatTitle", String(hotseat.get("title", "")), 20, UiPalette.TEXT_PRIMARY)
	box.add_child(_hotseat_title)
	hotseat_label = _label("HotseatLabel", String(hotseat.get("text", "")), 16, UiPalette.TEXT_SECONDARY)
	hotseat_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tooltip(hotseat_label, TooltipText.plain(String(RulesCodex.entry("handoff").get("title", "")), RulesCodex.text("handoff")))
	box.add_child(hotseat_label)
	var computer_entry := RulesCodex.entry("computer_opponent")
	computer_head = HBoxContainer.new()
	computer_head.name = "ComputerHead"
	computer_head.add_theme_constant_override("separation", 16)
	computer_head.visible = false
	box.add_child(computer_head)
	computer_title = _label("ComputerTitle", String(computer_entry.get("title", "")), 20, UiPalette.TEXT_PRIMARY)
	computer_title.visible = false
	computer_head.add_child(computer_title)
	computer_link = Button.new()
	computer_link.name = "ComputerCodexLink"
	computer_link.text = "How it plays, in the codex"
	computer_link.flat = true
	computer_link.focus_mode = Control.FOCUS_NONE
	computer_link.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	computer_link.add_theme_font_size_override("font_size", 16)
	computer_link.add_theme_color_override("font_color", UiPalette.LINK)
	computer_link.add_theme_color_override("font_hover_color", UiPalette.GILT)
	computer_link.tooltip_text = TooltipText.plain(String(computer_entry.get("title", "")), "The whole of it: what the computer sees, how Easy and Normal differ, and what it does with fog of war and magic. Opens the codex.")
	computer_link.pressed.connect(func(): codex_requested.emit("computer_opponent"))
	computer_head.add_child(computer_link)
	computer_label = _label("ComputerLabel", "", 16, UiPalette.TEXT_SECONDARY)
	computer_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	computer_label.visible = false
	_tooltip(computer_label, CodexLink.with_link(TooltipText.plain(String(computer_entry.get("title", "")),
		RulesCodex.text("computer_opponent")), "computer_opponent"))
	CodexLink.attach(computer_label, "computer_opponent", codex_requested.emit)  # right-click or F1 works here too
	box.add_child(computer_label)

	var seats_head := HBoxContainer.new()
	seats_head.name = "SeatsHead"
	box.add_child(seats_head)
	var seats_heading := _label("SeatsHeading", "Who plays which faction", 24, UiPalette.GILT)
	seats_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seats_head.add_child(seats_heading)
	for i in SEAT_COUNT:
		var seat_box := VBoxContainer.new()
		seat_box.name = "Seat%d" % (i + 1)
		seat_box.add_theme_constant_override("separation", 4)
		box.add_child(seat_box)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		seat_box.add_child(row)
		row.add_child(VictoryScreen.seat_emblem(i))
		var seat_label := _label("SeatLabel", "Player %d" % (i + 1), 24, UiPalette.seat_color(i).lightened(0.3))
		seat_label.custom_minimum_size = Vector2(130, 0)
		_tooltip(seat_label, TooltipText.plain("Player %d" % (i + 1), "%s Player %d plays in %s on the map, in battle reports and on the victory screen. Colours belong to the seat, so swapping seats swaps the colours too." % [
			RulesCodex.text("hotseat"), i + 1, UiPalette.seat_color_name(i)]))
		row.add_child(seat_label)
		seat_labels.append(seat_label)
		var picker := OptionButton.new()
		picker.name = "FactionPicker"
		picker.custom_minimum_size = Vector2(320, 44)
		picker.add_theme_font_size_override("font_size", 22)
		for f in _model.factions:
			picker.add_item(f.faction_name)
			var idx := picker.item_count - 1
			picker.set_item_metadata(idx, f.id)
			picker.get_popup().set_item_tooltip(idx, _faction_tooltip(f))
		picker.item_selected.connect(func(_index: int): _refresh())
		# The picked faction reads in the seat's colour, the colour it will have in the game.
		for state_name in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			picker.add_theme_color_override(state_name, UiPalette.seat_color(i).lightened(0.3))
		row.add_child(picker)
		seat_pickers.append(picker)
		row.add_child(_kind_picker(i))
		row.add_child(_level_picker(i))
		var summary := _label("FactionSummary", "", 16, UiPalette.TEXT_SECONDARY)
		summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		summary.mouse_filter = Control.MOUSE_FILTER_PASS
		seat_box.add_child(summary)
		faction_labels.append(summary)

	swap_button = Button.new()
	swap_button.name = "SwapButton"
	swap_button.text = "Swap seats"
	swap_button.custom_minimum_size = Vector2(170, 38)
	swap_button.add_theme_font_size_override("font_size", 18)
	swap_button.tooltip_text = "Player 1 and Player 2 trade factions, and with them their colours (colours belong to the seat). Player 1 still gives orders first, and each seat keeps its player, a person or the computer."
	swap_button.pressed.connect(swap_seats)
	seats_head.add_child(swap_button)

	var seed_row := HBoxContainer.new()
	seed_row.name = "SeedRow"
	seed_row.add_theme_constant_override("separation", 12)
	box.add_child(seed_row)
	var seed_heading := _label("SeedHeading", "Seed", 24, UiPalette.GILT)
	seed_heading.custom_minimum_size = Vector2(150, 0)
	seed_row.add_child(seed_heading)
	seed_edit = LineEdit.new()
	seed_edit.name = "SeedEdit"
	seed_edit.custom_minimum_size = Vector2(320, 44)
	seed_edit.add_theme_font_size_override("font_size", 22)
	seed_edit.placeholder_text = "A whole number"
	seed_edit.max_length = MAX_SEED_DIGITS + 4
	seed_edit.tooltip_text = TooltipText.plain("Seed", "The seed decides every random roll in the game, such as hits in battle. The same seed, factions and orders always play out exactly the same way, so a game can be replayed or shared. It starts random; type your own to replay a game.")
	seed_edit.text_changed.connect(func(_text: String): _refresh())
	seed_edit.text_submitted.connect(_on_seed_submitted)
	seed_row.add_child(seed_edit)
	new_seed_button = Button.new()
	new_seed_button.name = "NewSeedButton"
	new_seed_button.text = "New seed"
	new_seed_button.custom_minimum_size = Vector2(160, 44)
	new_seed_button.add_theme_font_size_override("font_size", 20)
	new_seed_button.tooltip_text = "Pick a new random seed."
	new_seed_button.pressed.connect(new_seed)
	seed_row.add_child(new_seed_button)

	# The six boxes in two columns, each with a line of what it adds. Their heading carries a line of which of them this game
	# plays with and how they lean on each other (both link the codex's "Game systems"); what the Rulers box leads to has a
	# line of its own below them.
	var systems_row := HBoxContainer.new()
	systems_row.name = "SystemsRow"
	systems_row.add_theme_constant_override("separation", 16)
	box.add_child(systems_row)
	var systems_tip := CodexLink.with_link(TooltipText.plain("Game systems", RulesCodex.text("game_systems")), "game_systems")
	var systems_heading := _label("SystemsHeading", "Game systems", 24, UiPalette.GILT)
	systems_heading.tooltip_text = systems_tip
	systems_heading.mouse_filter = Control.MOUSE_FILTER_PASS
	systems_row.add_child(systems_heading)
	systems_label = _label("SystemsLabel", "", 16, UiPalette.TEXT_SECONDARY)
	systems_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	systems_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	systems_label.size_flags_vertical = Control.SIZE_SHRINK_END
	systems_label.tooltip_text = systems_tip
	systems_label.mouse_filter = Control.MOUSE_FILTER_PASS
	systems_row.add_child(systems_label)
	var grid := GridContainer.new()
	grid.name = "Toggles"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 4)
	box.add_child(grid)
	rulers_toggle = CheckBox.new()
	rulers_toggle.name = "RulersToggle"
	rulers_toggle.text = "Rulers"
	rulers_toggle.add_theme_font_size_override("font_size", 20)
	rulers_toggle.tooltip_text = CodexLink.with_link(TooltipText.plain("Rulers",
		"Before the game each player picks a ruler and how much of its power to keep, and spends the rest on mandates for the whole nation. Untick it for the simpler game without rulers. Paths and Magic need Rulers, so unticking it unticks them too. %s" % RulesCodex.text("build_screen")), "build_screen")
	rulers_toggle.set_pressed_no_signal(true)
	rulers_toggle.toggled.connect(func(_on: bool): _refresh())
	_add_system(grid, rulers_toggle, "rulers")
	_build_paths_row(grid)
	_build_sieges_row(grid)
	_build_magic_row(grid)
	_build_fog_row(grid)
	_build_independents_row(grid)
	rulers_label = _label("RulersLabel", "Each player picks a ruler and mandates on the next screen, in secret. Builds are public once the game starts.", 16, UiPalette.TEXT_SECONDARY)
	rulers_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tooltip(rulers_label, CodexLink.with_link(TooltipText.plain(String(RulesCodex.entry("build").get("title", "")), RulesCodex.text("build")), "build"))
	rulers_label.visible = false
	box.add_child(rulers_label)

	error_label = _label("ErrorLabel", "", 19, NEGATIVE)
	error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	error_label.visible = false
	_tooltip(error_label, "Start stays off until this is fixed.")
	frame.add_child(error_label)  # pinned with the buttons, so why Start is off is always on screen

	var buttons := HBoxContainer.new()
	buttons.name = "Buttons"
	buttons.add_theme_constant_override("separation", 20)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	frame.add_child(buttons)
	back_button = Button.new()
	back_button.name = "BackButton"
	back_button.text = "Back"
	back_button.custom_minimum_size = Vector2(160, 56)
	back_button.add_theme_font_size_override("font_size", 22)
	back_button.tooltip_text = "Go back without starting a game (Esc)."
	back_button.pressed.connect(back)
	buttons.add_child(back_button)
	start_button = Button.new()
	start_button.name = "StartButton"
	start_button.text = "Start"
	start_button.custom_minimum_size = Vector2(220, 56)
	start_button.add_theme_font_size_override("font_size", 26)
	for state_name in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = UiPalette.PANEL_RAISED.lightened(0.08 if state_name == "hover" else 0.0)
		sb.border_color = UiPalette.GILT
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(6)
		start_button.add_theme_stylebox_override(state_name, sb)
	start_button.pressed.connect(start)
	buttons.add_child(start_button)


## One cell of the two-column grid: the box, and under it a line of what the system adds, in the box's own tooltip.
func _add_system(grid: Container, toggle: CheckBox, key: String) -> void:
	var cell := VBoxContainer.new()
	cell.name = "%sCell" % key.capitalize()
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.add_theme_constant_override("separation", 0)
	cell.add_child(toggle)
	var indent := MarginContainer.new()
	indent.add_theme_constant_override("margin_left", 34)
	cell.add_child(indent)
	var adds := _label("%sAdds" % key.capitalize(), system_line(key), 15, UiPalette.TEXT_SECONDARY)
	adds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	adds.tooltip_text = toggle.tooltip_text
	adds.mouse_filter = Control.MOUSE_FILTER_PASS
	indent.add_child(adds)
	grid.add_child(cell)


## What `key`'s system adds, in a line (under its box).
static func system_line(key: String) -> String:
	return String(SYSTEM_LINES.get(key, ""))


## M4-1: the "Paths" box under the rulers box. Ticking it ticks rulers (paths need them).
func _build_paths_row(box: Container) -> void:
	paths_toggle = CheckBox.new()
	paths_toggle.name = "PathsToggle"
	paths_toggle.text = "Paths"
	paths_toggle.add_theme_font_size_override("font_size", 20)
	paths_toggle.tooltip_text = CodexLink.with_link(TooltipText.plain("Paths",
		"Each faction researches its path with research points from its land, then swears an Oath that transforms its people. Untick it for a game without paths. Paths need rulers, so ticking it ticks Rulers too, and unticking it unticks Magic. %s" % RulesCodex.text("path")), "path")
	paths_toggle.set_pressed_no_signal(true)
	paths_toggle.toggled.connect(func(on: bool): set_paths(on))
	_add_system(box, paths_toggle, "paths")


## M3c: the "Forts & sieges" box under the paths box. It is independent of Rulers and Paths.
func _build_sieges_row(box: Container) -> void:
	sieges_toggle = CheckBox.new()
	sieges_toggle.name = "SiegesToggle"
	sieges_toggle.text = "Forts & sieges"
	sieges_toggle.add_theme_font_size_override("font_size", 20)
	sieges_toggle.tooltip_text = CodexLink.with_link(TooltipText.plain("Forts & sieges",
		"Forts have levels and walls, you recruit at any fort you own and can build more, and an army that marches into an enemy fort with a garrison inside besieges it instead of fighting, until it storms the walls or they fall. Untick it for the plain forts of the basic game. It works with or without Rulers and Paths. %s" % RulesCodex.text("fort_levels")), "fort_levels")
	sieges_toggle.set_pressed_no_signal(true)
	sieges_toggle.toggled.connect(func(on: bool): set_sieges(on))
	_add_system(box, sieges_toggle, "sieges")


## M5-5: the "Magic" box under the sieges box. Ticking it ticks Paths and Rulers (magic needs them).
func _build_magic_row(box: Container) -> void:
	magic_toggle = CheckBox.new()
	magic_toggle.name = "MagicToggle"
	magic_toggle.text = "Magic"
	magic_toggle.add_theme_font_size_override("font_size", 20)
	magic_toggle.tooltip_text = CodexLink.with_link(TooltipText.plain("Magic",
		"Research spells, recruit mages and cast rituals. Untick it for a game without magic. Magic needs Paths and Rulers, so ticking it ticks them too, and unticking either unticks it. %s" % RulesCodex.text("magic")), "magic")
	magic_toggle.set_pressed_no_signal(true)
	magic_toggle.toggled.connect(func(on: bool): set_magic(on))
	_add_system(box, magic_toggle, "magic")


## M5-1: the "Fog of war" box under the magic box. It is independent of every other box. Its tooltip is §1.3's, with the
## codex entry one click away.
func _build_fog_row(box: Container) -> void:
	fog_toggle = CheckBox.new()
	fog_toggle.name = "FogToggle"
	fog_toggle.text = "Fog of war"
	fog_toggle.add_theme_font_size_override("font_size", 20)
	fog_toggle.tooltip_text = CodexLink.with_link(TooltipText.plain("Fog of war", fog_tooltip()), "fog_of_war")
	fog_toggle.set_pressed_no_signal(true)
	fog_toggle.toggled.connect(func(on: bool): set_fog(on))
	_add_system(box, fog_toggle, "fog")


## IND-1: the "Independents" box under the fog box. Its tooltip says what it does, with the codex
## entry one click away.
func _build_independents_row(box: Container) -> void:
	independents_toggle = CheckBox.new()
	independents_toggle.name = "IndependentsToggle"
	independents_toggle.text = "Independents"
	independents_toggle.add_theme_font_size_override("font_size", 20)
	independents_toggle.tooltip_text = CodexLink.with_link(TooltipText.plain("Independents", independents_tooltip()), "independents")
	independents_toggle.set_pressed_no_signal(true)
	independents_toggle.toggled.connect(func(on: bool): set_independents(on))
	_add_system(box, independents_toggle, "independents")


## The independents box's explanation.
static func independents_tooltip() -> String:
	return "Every neutral province starts with a garrison of the %s, local fighters who answer to no ruler. To take a province you must beat its garrison in battle, so expanding costs troops and the richest provinces need a real army. Unticked, neutral provinces are empty and fall to the first army that walks in. It works with every other box." % IndependentData.FACTION_NAME


## The fog box's explanation (design/M5_MAGIC_FOG.md §1.3).
static func fog_tooltip() -> String:
	return "You see exactly only where you own land or have an army; next to that, roughly; beyond, only what you saw last. In hotseat, each player sees only their own view. Untick it to see the whole map. It works with or without Rulers, Paths and Forts & sieges."


## Human or Computer for seat `i` (0-based).
func _kind_picker(i: int) -> OptionButton:
	var picker := OptionButton.new()
	picker.name = "KindPicker"
	picker.custom_minimum_size = Vector2(170, 44)
	picker.add_theme_font_size_override("font_size", 20)
	for k in KIND_NAMES.size():
		picker.add_item(KIND_NAMES[k])
	picker.get_popup().set_item_tooltip(0, "A person plays this seat. With two people, the screen is covered between their turns so nobody sees the other's orders.")
	picker.get_popup().set_item_tooltip(1, "The computer plays this seat, by the same rules as you. It gives its orders at the same time as you, without seeing yours.")
	picker.tooltip_text = CodexLink.with_link(TooltipText.plain("Who plays Player %d" % (i + 1),
		"A person, or the computer. %s" % RulesCodex.text("computer_opponent")), "computer_opponent")
	picker.select(0)
	picker.item_selected.connect(func(_index: int): _refresh())
	kind_pickers.append(picker)
	return picker


## Easy or Normal for seat `i` (0-based); hidden while the seat is human.
func _level_picker(i: int) -> OptionButton:
	var picker := OptionButton.new()
	picker.name = "LevelPicker"
	picker.custom_minimum_size = Vector2(140, 44)
	picker.add_theme_font_size_override("font_size", 20)
	for level in LEVELS:
		picker.add_item(AISeat.level_name(level))
	picker.get_popup().set_item_tooltip(0, AISeat.tag_help("this faction", "easy"))
	picker.get_popup().set_item_tooltip(1, AISeat.tag_help("this faction", "normal"))
	picker.tooltip_text = TooltipText.plain("How well the computer plays Player %d" % (i + 1),
		"Easy makes more mistakes: it passes up about one in three of its good attacks and captures, recruits at random and keeps a thinner guard on its capital. Normal plays as well as it can. Neither level cheats.")
	picker.select(LEVELS.find(DEFAULT_LEVEL))
	picker.visible = false
	picker.item_selected.connect(func(_index: int): _refresh())
	level_pickers.append(picker)
	return picker


func _label(node_name: String, text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.name = node_name
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


func _tooltip(l: Label, text: String) -> void:
	l.tooltip_text = text
	l.mouse_filter = Control.MOUSE_FILTER_PASS
