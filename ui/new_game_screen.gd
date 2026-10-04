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
## Rulers (M2-5, #33): the "Rulers" box, ticked by default. Ticked, config() adds "rulers": true and Start
## opens the BuildScreen on top of this screen: every human seat picks a ruler and mandates in secret,
## computer seats get a seeded preset, and only then is start_requested emitted, with the config plus
## "builds" ({faction id: build}). Back on the build screen returns here and drops those builds.
## Paths (M4-1, #66): the "Paths (M4 preview)" box, off by default (launching with `-- --paths` ticks it).
## Paths need rulers, so ticking it ticks the rulers box too, and clearing the rulers box clears it.
## Ticked, config() adds "paths": true (GameScreen.starting_state then uses GameState.with_paths).
## Forts & sieges (M3c S-1a, #98; design/M3C_SIEGES.md §1.3): the "Forts & sieges (M3c preview)" box, off by
## default (launching with `-- --sieges` ticks it), independent of Rulers and Paths. Ticked, config() adds
## "sieges": true (GameScreen.starting_state then uses GameState.with_sieges).
## Magic (M5-5, #116; design/M5_MAGIC_FOG.md §1.3): the "Magic (M5 preview)" box, off by default (launching with
## `-- --magic` ticks it). Magic needs Paths: ticking it ticks Paths and Rulers, and clearing Paths (or Rulers)
## clears it. Ticked, config() adds "magic": true (GameScreen.starting_state then uses GameState.with_magic).
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
##   set_rulers(on), rulers_on()     the "Rulers" box (ticked by default)
##   set_paths(on), paths_on()       the "Paths (M4 preview)" box (M4-1); ticking it ticks rulers
##   set_sieges(on), sieges_on()     the "Forts & sieges (M3c preview)" box (M3c), on its own
##   set_magic(on), magic_on()       the "Magic (M5 preview)" box (M5-5); ticking it ticks paths and rulers
##   quick_start_config(rng) -> Dictionary   Quick start's config (static): a random faction for the person
##                                   in seat 1, the computer at Normal in seat 2, rulers on with the balanced
##                                   preset for the person, and a random seed
##   build_screen                    the BuildScreen Start opens while rulers are on (null until then);
##                                   build_screen_open() -> bool
##   seat_faction(seat) -> String, faction_ids() -> Array[String]
##   start() -> bool                 emits start_requested when valid (the Start button, Enter in the seed);
##                                   with rulers on, opens the build screen instead, which emits it later
##   back()                          emits back_requested (the Back button, Esc)

signal start_requested(config: Dictionary)
signal back_requested

const SEAT_COUNT := 2
const KINDS := ["human", "computer"]  # the seat kind pickers' items, in order
const KIND_NAMES := ["Human", "Computer"]
const LEVELS := ["easy", "normal"]  # AIPlayer.DIFFICULTIES, in the level pickers' order
const DEFAULT_LEVEL := "normal"
const DEFAULT_KINDS := ["human", "computer"]  # MVP: you against the computer
const MAX_SEED_DIGITS := 18  # any 18-digit number fits in a 64-bit int
const MAX_RANDOM_SEED := 999999999
const BACKGROUND := Color("#14131F")
const NEGATIVE := UiPalette.NEGATIVE  # design/STYLE_BIBLE.md 1.3 "negative"

var seat_pickers: Array[OptionButton] = []
var kind_pickers: Array[OptionButton] = []  # Human or Computer, per seat
var level_pickers: Array[OptionButton] = []  # Easy or Normal, per seat; shown for computer seats only
var computer_title: Label  # "Playing against the computer": replaces the hotseat title while a seat is the computer
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
var paths_toggle: CheckBox  # M4-1: "Paths (M4 preview)": off by default; needs rulers
var sieges_toggle: CheckBox  # M3c: "Forts & sieges (M3c preview)": off by default; independent of rulers and paths
var magic_toggle: CheckBox  # M5-5: "Magic (M5 preview)": off by default; needs paths
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
	if last_game.get("rulers", false) == true or not builds.is_empty():
		set_rulers(true)
	elif last_game.has("players"):
		set_rulers(OS.get_cmdline_user_args().has("--rulers"))  # a game without rulers: a rematch without them
	if last_game.get("paths", false) == true:  # M4-1
		set_paths(true)
	elif last_game.has("players"):
		set_paths(_paths_by_default())
	if last_game.get("sieges", false) == true:  # M3c
		set_sieges(true)
	elif last_game.has("players"):
		set_sieges(_sieges_by_default())
	if last_game.get("magic", false) == true:  # M5-5
		set_magic(true)
	elif last_game.has("players"):
		set_magic(_magic_by_default())
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


## Ticks or clears the "Paths (M4 preview)" box (M4-1). Paths need rulers: ticking it ticks rulers too.
func set_paths(on: bool) -> void:
	paths_toggle.set_pressed_no_signal(on)
	if on:
		rulers_toggle.set_pressed_no_signal(true)
	_refresh()


func paths_on() -> bool:
	return paths_toggle.button_pressed


## Paths start ticked when the game was launched with `-- --paths` (GameScreen.starting_state).
static func _paths_by_default() -> bool:
	return OS.get_cmdline_user_args().has("--paths")


## Ticks or clears the "Forts & sieges (M3c preview)" box (M3c). It needs neither rulers nor paths.
func set_sieges(on: bool) -> void:
	sieges_toggle.set_pressed_no_signal(on)
	_refresh()


func sieges_on() -> bool:
	return sieges_toggle.button_pressed


## Forts and sieges start ticked when the game was launched with `-- --sieges` (GameScreen.starting_state).
static func _sieges_by_default() -> bool:
	return OS.get_cmdline_user_args().has("--sieges")


## Ticks or clears the "Magic (M5 preview)" box (M5-5). Magic needs paths: ticking it ticks paths and rulers too.
func set_magic(on: bool) -> void:
	magic_toggle.set_pressed_no_signal(on)
	if on:
		paths_toggle.set_pressed_no_signal(true)
		rulers_toggle.set_pressed_no_signal(true)
	_refresh()


func magic_on() -> bool:
	return magic_toggle.button_pressed


## Magic starts ticked when the game was launched with `-- --magic` (GameScreen.starting_state).
static func _magic_by_default() -> bool:
	return OS.get_cmdline_user_args().has("--magic")


func build_screen_open() -> bool:
	return build_screen != null and build_screen.visible


## Rulers start ticked (MVP default).
static func _rulers_by_default() -> bool:
	return true


## Quick start's config: the person in seat 1 plays a random faction against the computer at Normal in
## seat 2, with rulers on and a random seed. The person gets their faction's balanced preset and the
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
	return {"players": [human, opponent], "seed": game_seed, "ai": {opponent: DEFAULT_LEVEL}, "rulers": true, "builds": builds}


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


func _faction(fid: String) -> Faction:
	return _model.find_faction(fid)


func _computer_short() -> String:
	return "The computer plays by the same rules as you and gives its orders at the same time, without seeing yours. Easy makes more mistakes than Normal."


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

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	var style := StyleBoxFlat.new()
	style.bg_color = UiPalette.PANEL_BG
	style.border_color = UiPalette.PANEL_BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(36)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.name = "Box"
	box.custom_minimum_size = Vector2(900, 0)
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)

	box.add_child(_label("TitleLabel", "New game", 48, UiPalette.GILT))
	rematch_label = _label("RematchLabel", "Rematch: the same players in the same seats as the last game, with a new seed. Change anything you like.", 18, UiPalette.GILT)
	rematch_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rematch_label.visible = false
	box.add_child(rematch_label)
	var hotseat := RulesCodex.entry("hotseat")
	_hotseat_title = _label("HotseatTitle", String(hotseat.get("title", "")), 22, UiPalette.TEXT_PRIMARY)
	box.add_child(_hotseat_title)
	hotseat_label = _label("HotseatLabel", String(hotseat.get("text", "")), 18, UiPalette.TEXT_SECONDARY)
	hotseat_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tooltip(hotseat_label, TooltipText.plain(String(RulesCodex.entry("handoff").get("title", "")), RulesCodex.text("handoff")))
	box.add_child(hotseat_label)
	var computer_entry := RulesCodex.entry("computer_opponent")
	computer_title = _label("ComputerTitle", String(computer_entry.get("title", "")), 22, UiPalette.TEXT_PRIMARY)
	computer_title.visible = false
	box.add_child(computer_title)
	computer_label = _label("ComputerLabel", "", 18, UiPalette.TEXT_SECONDARY)
	computer_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	computer_label.visible = false
	_tooltip(computer_label, CodexLink.with_link(TooltipText.plain(String(computer_entry.get("title", "")),
		RulesCodex.text("computer_opponent")), "computer_opponent"))
	box.add_child(computer_label)

	box.add_child(_label("SeatsHeading", "Who plays which faction", 26, UiPalette.GILT))
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
		var summary := _label("FactionSummary", "", 17, UiPalette.TEXT_SECONDARY)
		summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		summary.mouse_filter = Control.MOUSE_FILTER_PASS
		seat_box.add_child(summary)
		faction_labels.append(summary)

	swap_button = Button.new()
	swap_button.name = "SwapButton"
	swap_button.text = "Swap seats"
	swap_button.custom_minimum_size = Vector2(200, 44)
	swap_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	swap_button.add_theme_font_size_override("font_size", 20)
	swap_button.tooltip_text = "Player 1 and Player 2 trade factions, and with them their colours (colours belong to the seat). Player 1 still gives orders first, and each seat keeps its player, a person or the computer."
	swap_button.pressed.connect(swap_seats)
	box.add_child(swap_button)

	box.add_child(_label("SeedHeading", "Seed", 26, UiPalette.GILT))
	var seed_row := HBoxContainer.new()
	seed_row.name = "SeedRow"
	seed_row.add_theme_constant_override("separation", 12)
	box.add_child(seed_row)
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

	var rulers_row := HBoxContainer.new()
	rulers_row.name = "RulersRow"
	rulers_row.add_theme_constant_override("separation", 14)
	box.add_child(rulers_row)
	rulers_toggle = CheckBox.new()
	rulers_toggle.name = "RulersToggle"
	rulers_toggle.text = "Rulers"
	rulers_toggle.add_theme_font_size_override("font_size", 20)
	rulers_toggle.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	rulers_toggle.tooltip_text = CodexLink.with_link(TooltipText.plain("Rulers",
		"Before the game each player picks a ruler and how much of its power to keep, and spends the rest on mandates for the whole nation. Untick it for the simpler game without rulers. %s" % RulesCodex.text("build_screen")), "build_screen")
	rulers_toggle.set_pressed_no_signal(_rulers_by_default())
	rulers_toggle.toggled.connect(func(_on: bool): _refresh())
	rulers_row.add_child(rulers_toggle)
	rulers_label = _label("RulersLabel", "Each player picks a ruler and mandates on the next screen, in secret. Builds are public once the game starts.", 17, UiPalette.TEXT_SECONDARY)
	rulers_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rulers_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tooltip(rulers_label, CodexLink.with_link(TooltipText.plain(String(RulesCodex.entry("build").get("title", "")), RulesCodex.text("build")), "build"))
	rulers_label.visible = false
	rulers_row.add_child(rulers_label)
	_build_paths_row(box)
	_build_sieges_row(box)
	_build_magic_row(box)

	error_label = _label("ErrorLabel", "", 19, NEGATIVE)
	error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	error_label.visible = false
	_tooltip(error_label, "Start stays off until this is fixed.")
	box.add_child(error_label)

	var buttons := HBoxContainer.new()
	buttons.name = "Buttons"
	buttons.add_theme_constant_override("separation", 20)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(buttons)
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


## M4-1: the "Paths (M4 preview)" box under the rulers box. Ticking it ticks rulers (paths need them).
func _build_paths_row(box: Container) -> void:
	var row := HBoxContainer.new()
	row.name = "PathsRow"
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)
	paths_toggle = CheckBox.new()
	paths_toggle.name = "PathsToggle"
	paths_toggle.text = "Paths (M4 preview)"
	paths_toggle.add_theme_font_size_override("font_size", 20)
	paths_toggle.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	paths_toggle.tooltip_text = CodexLink.with_link(TooltipText.plain("Paths (preview)",
		"A preview of milestone 4, the paths of ascension: each faction researches its path with research points from its land, then swears an Oath that transforms its people. Paths need rulers, so this ticks Rulers too. Paths are still being built, so some of their effects may not be in play yet. %s" % RulesCodex.text("path")), "path")
	paths_toggle.set_pressed_no_signal(_paths_by_default())
	if paths_toggle.button_pressed:
		rulers_toggle.set_pressed_no_signal(true)
	paths_toggle.toggled.connect(func(on: bool): set_paths(on))
	row.add_child(paths_toggle)


## M3c: the "Forts & sieges (M3c preview)" box under the paths box. It is independent of Rulers and Paths.
func _build_sieges_row(box: Container) -> void:
	var row := HBoxContainer.new()
	row.name = "SiegesRow"
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)
	sieges_toggle = CheckBox.new()
	sieges_toggle.name = "SiegesToggle"
	sieges_toggle.text = "Forts & sieges (M3c preview)"
	sieges_toggle.add_theme_font_size_override("font_size", 20)
	sieges_toggle.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	sieges_toggle.tooltip_text = CodexLink.with_link(TooltipText.plain("Forts & sieges (preview)",
		"A preview of milestone 3c: forts have levels and walls, you recruit at any fort you own and can build more, and an army that marches into an enemy fort with a garrison inside besieges it instead of fighting, until it storms the walls or they fall. It works with or without Rulers and Paths. Forts and sieges are still being built, so the map and the panels may not show all of it yet. %s" % RulesCodex.text("fort_levels")), "fort_levels")
	sieges_toggle.set_pressed_no_signal(_sieges_by_default())
	sieges_toggle.toggled.connect(func(on: bool): set_sieges(on))
	row.add_child(sieges_toggle)


## M5-5: the "Magic (M5 preview)" box under the sieges box. Ticking it ticks Paths and Rulers (magic needs them).
func _build_magic_row(box: Container) -> void:
	var row := HBoxContainer.new()
	row.name = "MagicRow"
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)
	magic_toggle = CheckBox.new()
	magic_toggle.name = "MagicToggle"
	magic_toggle.text = "Magic (M5 preview)"
	magic_toggle.add_theme_font_size_override("font_size", 20)
	magic_toggle.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	magic_toggle.tooltip_text = CodexLink.with_link(TooltipText.plain("Magic (preview)",
		"Research spells, recruit mages and cast rituals. Needs Paths and Rulers, so they're on too. Magic is still being built: battle spells and rituals don't take effect yet, but you can research the arcana, recruit mages and set your spellbook. %s" % RulesCodex.text("magic")), "magic")
	magic_toggle.set_pressed_no_signal(_magic_by_default())
	if magic_toggle.button_pressed:
		paths_toggle.set_pressed_no_signal(true)
		rulers_toggle.set_pressed_no_signal(true)
	magic_toggle.toggled.connect(func(on: bool): set_magic(on))
	row.add_child(magic_toggle)


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
